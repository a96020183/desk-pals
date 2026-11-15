// 52_study.swift — port of extension/desktop/DeskPals.Study.cs
// Desk Pals：讀書小幫手（學校行事曆的上課提醒和作業死線、搶課提醒、考試倒數、熬夜提醒、讀書統計）。
// 不分學生／上班族：每個功能有資料才會動（沒填學校行事曆就沒有上課／作業提醒；沒加考試就沒有倒數）。
// 桌面版自己就能用（不用 VS Code）：自己抓 ICS、自己解析、自己提醒；設定在公仔小屋的「讀書小幫手設定…」。
// 有 VS Code 的話，VS Code 設定（deskPals.schoolIcsUrl…）會從 pipe 推過來，以 VS Code 的為準（設定視窗顯示「由 VS Code 管理」）。
//
// 掛在核心的地方（都只有一兩行）：TickInner → StudyTick()、OnMsg 的 default → StudyMsg()、
//   AddHelpers → AddStudyMenus()／ExamNear()、StartFocus／StopFocus → ExamNear()、Priority → StudyPriority()、
//   Flavor → StudyFlavor()、OnNotify／Deliver → MeetingLike()、NoticeClicked → StudyClicked()、
//   DailyWrap → WeekTomatoNote()／StudyWrapParts()、TicketLine → CourseLine()、DrawTicketBadge → BadgeIsCourse()／DrawCapIcon()、
//   HouseMenu →「讀書小幫手設定…」、Snap → StudySnap()。搶課跟搶票共用 Ticket（Kind＝course）。
//
// pipe 指令：
//   course <unixMs> <提前分鐘> <url|-> <課名…>      搶課提醒（跟 ticket 一樣，只是用字換成選課）
//   exam <unixMs> <名稱…>、exam-del <id>               考試倒數
//   study-vs <urls,remind,…|->                        VS Code 這次管哪幾項（只有使用者在 VS Code 設過的）
//   study-set urls <網址…>｜remind <分>｜autoquiet 0/1｜late <HH:MM|off>｜nudge <HH:MM|off>｜workcal <網址|->
//                                                     VS Code 推設定（推過的那一項就以 VS Code 為準）
//   study-hello → study-state <json>；study-done <id>（這份作業交了）
//   測試用（只在離屏模式）：study-ics <檔案> [當成哪個網址]｜study-ics clear、study-clock <yyyy-MM-ddTHH:mm|off>、
//     study-idle <秒|-1>、study-dump、study-settings open|close|save|set <欄位> <值>
// 送回 VS Code：study-state {"bar","school","d":[…],"e":[…]}（狀態列、「這週要交的」）、study-done <id>
//
// mac 差異（都標了 // mac:）：
// - 時區：TimeZone(identifier:) 直接吃 IANA 名字；Outlook 匯出的 Windows 名字（"Taipei Standard Time"）用同一張對照表反查。
// - 正規式：C# 用 RegexOptions.ECMAScript（\b、\w、\d、\s 只看 ASCII，跟 JS 一樣）；NSRegularExpression 是 Unicode 規則，
//   所以這幾個寫成明確的 ASCII 字元類（中文字旁邊的 due 也算一個字）。
// - 抓 ICS：HttpWebRequest → URLSession（背景執行緒、20 秒、最多 4 次轉址、最多 8 MB）。打開網址：NSWorkspace。
import Foundation
import AppKit
import CryptoKit

// ================= ICS（行事曆）：解析＋重複規則展開（跟 practical.js 的 parseIcs／occurrences 同一套規則）=================
final class IcsTime { var Utc = 0; var Y = 0, M = 0, D = 0, H = 0, Mi = 0, S = 0; var Tz: String! = nil; var AllDay = false; init() {} }
final class IcsEvent {
    var Uid = "", Summary = "", Location = "", Description = "", Url = "", Conf = "", Status = "", RRule = "", Categories = ""
    var Start: IcsTime! = nil, End: IcsTime! = nil, RecurrenceId: IcsTime! = nil
    var Declined = false
    let ExDates = List<Int>()
    init() {}
}
final class IcsOcc { var Uid: String! = nil, Summary: String! = nil, Link: String! = nil; var Start = 0, End = 0; var Ev: IcsEvent! = nil, Parent: IcsEvent! = nil; init() {} }

enum Ics {
    static let Epoch = DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)
    static func Ms(_ utc: DateTime) -> Int { return CInt((utc - Epoch).TotalMilliseconds) }

    // 常見的 IANA 時區 → Windows 時區（.NET Framework 只認 Windows 的名字；Outlook 匯出的本來就是 Windows 名字）
    // mac: 反過來用——Windows 名字 → IANA（TimeZone 只認 IANA）
    static let IanaToWin: [(String, String)] = [
        ("Asia/Taipei", "Taipei Standard Time"), ("Asia/Hong_Kong", "China Standard Time"), ("Asia/Shanghai", "China Standard Time"),
        ("Asia/Macau", "China Standard Time"), ("Asia/Chongqing", "China Standard Time"), ("Asia/Tokyo", "Tokyo Standard Time"),
        ("Asia/Seoul", "Korea Standard Time"), ("Asia/Singapore", "Singapore Standard Time"), ("Asia/Kuala_Lumpur", "Singapore Standard Time"),
        ("Asia/Manila", "Singapore Standard Time"), ("Asia/Bangkok", "SE Asia Standard Time"), ("Asia/Ho_Chi_Minh", "SE Asia Standard Time"),
        ("Asia/Jakarta", "SE Asia Standard Time"), ("Asia/Kolkata", "India Standard Time"), ("Asia/Dubai", "Arabian Standard Time"),
        ("Australia/Sydney", "AUS Eastern Standard Time"), ("Australia/Melbourne", "AUS Eastern Standard Time"), ("Australia/Brisbane", "E. Australia Standard Time"),
        ("Australia/Perth", "W. Australia Standard Time"), ("Pacific/Auckland", "New Zealand Standard Time"),
        ("Europe/London", "GMT Standard Time"), ("Europe/Dublin", "GMT Standard Time"), ("Europe/Paris", "Romance Standard Time"),
        ("Europe/Berlin", "W. Europe Standard Time"), ("Europe/Amsterdam", "W. Europe Standard Time"), ("Europe/Zurich", "W. Europe Standard Time"),
        ("Europe/Rome", "W. Europe Standard Time"), ("Europe/Madrid", "Romance Standard Time"), ("Europe/Stockholm", "W. Europe Standard Time"),
        ("America/New_York", "Eastern Standard Time"), ("America/Toronto", "Eastern Standard Time"), ("America/Chicago", "Central Standard Time"),
        ("America/Denver", "Mountain Standard Time"), ("America/Phoenix", "US Mountain Standard Time"), ("America/Los_Angeles", "Pacific Standard Time"),
        ("America/Vancouver", "Pacific Standard Time"), ("Pacific/Honolulu", "Hawaiian Standard Time") ]

    // 某時區的牆上時間 → UTC 毫秒。fixedOff：檔案裡 VTIMEZONE 沒有夏令時間的固定時差（分鐘）
    static func WallToUtc(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int, _ tz: String!, _ fixedOff: Dict<String, Int>!) -> Int {
        // C#：new DateTime 不合法會丟例外 → 0
        if y < 1 || y > 9999 || m < 1 || m > 12 || d < 1 || d > DateTime.DaysInMonth(y, m) || h < 0 || h > 23 || mi < 0 || mi > 59 || s < 0 || s > 59 { return 0 }
        let wall = DateTime(y, m, d, h, mi, s, DateTimeKind.Unspecified)
        if tz == nil { return Ms(DateTime.SpecifyKind(wall, DateTimeKind.Local).ToUniversalTime()) }
        if tz == "UTC" || tz == "Etc/UTC" || tz == "GMT" || tz == "Z" { return Ms(DateTime.SpecifyKind(wall, DateTimeKind.Utc)) }
        var off = 0
        if fixedOff != nil && fixedOff.TryGetValue(tz, &off) { return Ms(DateTime.SpecifyKind(wall, DateTimeKind.Utc)) - off * 60000 }
        let z = FindZone(tz)
        if z != nil {
            if let r = ConvertTimeToUtc(wall, z!) { return r }
            if let r = ConvertTimeToUtc(wall.AddHours(1), z!) { return r }   // 夏令時間跳過的那一小時
        }
        return Ms(DateTime.SpecifyKind(wall, DateTimeKind.Local).ToUniversalTime())
    }

    // mac: TimeZoneInfo.ConvertTimeToUtc（跳過的那一小時＝nil，像 C# 丟 ArgumentException；重複的那一小時＝標準時間，跟 .NET 一樣）
    static func ConvertTimeToUtc(_ wall: DateTime, _ z: TimeZone) -> Int? {
        let w = Ms(DateTime.SpecifyKind(wall, DateTimeKind.Utc)) / 1000   // 牆上時間當成 UTC 的秒數
        var offs: [Int] = []
        for probe in [w - 86400, w, w + 86400] {
            let o = z.secondsFromGMT(for: Date(timeIntervalSince1970: Double(probe)))
            if !offs.contains(o) { offs.append(o) }
        }
        var hits: [Int] = []
        for o in offs {
            let t = w - o
            if z.secondsFromGMT(for: Date(timeIntervalSince1970: Double(t))) == o && !hits.contains(t) { hits.append(t) }
        }
        if hits.isEmpty { return nil }
        if hits.count > 1 { for t in hits { if !z.isDaylightSavingTime(for: Date(timeIntervalSince1970: Double(t))) { return t * 1000 } } }
        return hits[0] * 1000
    }

    static let zoneCache = Dict<String, TimeZone?>()
    static let zoneLock = NSObject()
    static func FindZone(_ tz: String) -> TimeZone? {
        return lock(zoneLock) { () -> TimeZone? in
            if let hit = zoneCache.Get(tz) { return hit }
            var id = tz.Trim("\"")
            for (iana, win) in IanaToWin { if win == id { id = iana; break } }   // mac: Windows 名字 → IANA
            let found = TimeZone(identifier: id)
            zoneCache[tz] = found
            return found
        }
    }

    static let TimeRe = Regex(#"^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$"#)
    static func ParseTime(_ v: String!, _ p: Dict<String, String>, _ fixedOff: Dict<String, Int>!) -> IcsTime! {
        let m = TimeRe.Match((v ?? "").Trim())
        if !m.Success { return nil }
        let t = IcsTime()
        t.Y = int.Parse(m.Groups[1].Value); t.M = int.Parse(m.Groups[2].Value); t.D = int.Parse(m.Groups[3].Value)
        if m.Groups[4].Success { t.H = int.Parse(m.Groups[4].Value); t.Mi = int.Parse(m.Groups[5].Value); t.S = int.Parse(m.Groups[6].Value) }
        var vt = ""
        t.AllDay = !m.Groups[4].Success || (p.TryGetValue("VALUE", &vt) && vt == "DATE")
        var tz = ""
        t.Tz = m.Groups[7].Success ? "UTC" : (p.TryGetValue("TZID", &tz) ? tz : nil)
        t.Utc = WallToUtc(t.Y, t.M, t.D, t.H, t.Mi, t.S, t.Tz, fixedOff)
        return t
    }

    static func Unesc(_ s: String) -> String { return Regex.Replace(Regex.Replace(s, #"\\[nN]"#, "\n"), #"\\([,;\\])"#, "$1") }

    // owner：行事曆擁有者（Google 私密網址裡就有信箱）——他按了「不參加」的不提醒
    static func Parse(_ text: String, _ owner0: String!, _ calName: inout String) -> List<IcsEvent> {
        calName = ""
        let owner = (owner0 ?? "").ToLowerInvariant()
        let lines = text.Replace("\r\n ", "").Replace("\r\n\t", "").Replace("\n ", "").Replace("\n\t", "").Split("\n")
        let events = List<IcsEvent>()
        let fixedOff = Dict<String, Int>()
        // 先看 VTIMEZONE：只有 STANDARD、沒有 DAYLIGHT 的時區（例如 Asia/Taipei）＝固定時差
        var tzid: String! = nil; var stdOff = 0; var hasStd = false, hasDst = false, inStd = false
        for raw in lines {
            let line = raw.TrimEnd("\r")
            if line == "BEGIN:VTIMEZONE" { tzid = nil; hasStd = false; hasDst = false; continue }
            if line == "END:VTIMEZONE" { if tzid != nil && hasStd && !hasDst { fixedOff[tzid] = stdOff }; tzid = nil; continue }
            if line == "BEGIN:STANDARD" { inStd = true; hasStd = true; continue }
            if line == "END:STANDARD" { inStd = false; continue }
            if line == "BEGIN:DAYLIGHT" { hasDst = true; continue }
            if line.StartsWith("TZID:") && tzid == nil { tzid = line.Substring(5).Trim() }
            if inStd && line.StartsWith("TZOFFSETTO:") {
                let o = Regex.Match(line.Substring(11).Trim(), #"^([+-])(\d{2})(\d{2})"#)
                if o.Success { stdOff = (o.Groups[1].Value == "-" ? -1 : 1) * (int.Parse(o.Groups[2].Value) * 60 + int.Parse(o.Groups[3].Value)) }
            }
            if line.StartsWith("X-WR-CALNAME:") { calName = Unesc(line.Substring(13)).Trim() }
        }
        var cur: IcsEvent! = nil
        for raw in lines {
            let line = raw.TrimEnd("\r")
            if line == "BEGIN:VEVENT" { cur = IcsEvent(); continue }
            if line == "END:VEVENT" { if cur != nil { events.Add(cur) }; cur = nil; continue }
            if cur == nil { continue }
            let i = line.IndexOf(":")
            if i < 0 { continue }
            let left = line.Substring(0, i), value = line.Substring(i + 1)
            let parts = left.Split(";")
            let p = Dict<String, String>()
            var k = 1
            while k < parts.count { let j = parts[k].IndexOf("="); if j > 0 { p[parts[k].Substring(0, j).ToUpperInvariant()] = parts[k].Substring(j + 1).Trim("\"") }; k += 1 }
            switch parts[0].ToUpperInvariant() {
            case "UID": cur.Uid = value
            case "SUMMARY": cur.Summary = Unesc(value)
            case "LOCATION": cur.Location = Unesc(value)
            case "DESCRIPTION": cur.Description = Unesc(value)
            case "URL": cur.Url = value.Trim()
            case "CATEGORIES": cur.Categories = Unesc(value)
            case "X-GOOGLE-CONFERENCE": cur.Conf = value.Trim()
            case "STATUS": cur.Status = value.Trim().ToUpperInvariant()
            case "RRULE": cur.RRule = value.Trim()
            case "DTSTART": cur.Start = ParseTime(value, p, fixedOff)
            case "DTEND": cur.End = ParseTime(value, p, fixedOff)
            case "RECURRENCE-ID": cur.RecurrenceId = ParseTime(value, p, fixedOff)
            case "ATTENDEE":
                var ps = ""
                if owner != "" && value.ToLowerInvariant() == "mailto:" + owner && p.TryGetValue("PARTSTAT", &ps) && ps.ToUpperInvariant() == "DECLINED" { cur.Declined = true }
            case "EXDATE": for v in value.Split(",") { let t = ParseTime(v, p, fixedOff); if t != nil { cur.ExDates.Add(t!.Utc) } }
            default: break
            }
        }
        return events
    }

    static let DAYS: [String] = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]

    // 單次、DAILY／WEEKLY／MONTHLY（BYDAY、BYMONTHDAY）／YEARLY、INTERVAL、COUNT、UNTIL、EXDATE、單次改期（RECURRENCE-ID）、取消；全天的不展開
    static func Occurrences(_ events: List<IcsEvent>, _ from: Int, _ to: Int) -> List<IcsOcc> {
        let outl = List<IcsOcc>()
        let overrides = Dict<String, IcsEvent>()
        for e in events { if e.RecurrenceId != nil && e.Uid != "" { overrides[e.Uid + "@" + String(e.RecurrenceId.Utc)] = e } }
        for e in events {
            if e.Start == nil || e.Start.AllDay || e.RecurrenceId != nil { continue }
            if e.RRule == "" { Push(outl, e, e.Start.Utc, nil, from, to); continue }
            let r = Dict<String, String>()
            for kv in e.RRule.Split(";") { let j = kv.IndexOf("="); if j > 0 { r[kv.Substring(0, j).ToUpperInvariant()] = kv.Substring(j + 1) } }
            let freq = Get(r, "FREQ")
            let interval = Math.Max(1, ToInt(Get(r, "INTERVAL"), 1))
            let count = Get(r, "COUNT") != "" ? ToInt(Get(r, "COUNT"), int.MaxValue) : int.MaxValue
            var until = long.MaxValue
            if Get(r, "UNTIL") != "" { let u = ParseTime(Get(r, "UNTIL"), Dict<String, String>(), nil); if u != nil { until = u!.Utc } }
            let byday: [String]? = Get(r, "BYDAY") != "" ? Get(r, "BYDAY").Split(",") : nil
            var bymd: List<Int>? = nil
            if Get(r, "BYMONTHDAY") != "" { bymd = List<Int>(); for x in Get(r, "BYMONTHDAY").Split(",") { bymd!.Add(ToInt(x, 0)) } }
            let day0 = DateTime(e.Start.Y, e.Start.M, e.Start.D)
            let endDay = Epoch.AddMilliseconds(to).Date.AddDays(2)
            let mon0 = day0.AddDays(-((day0.DayOfWeek.rawValue + 6) % 7))   // 起始那週的週一
            var n = 0
            var tNext = day0
            while tNext <= endDay && n < count {
                let t = tNext
                tNext = tNext.AddDays(1)
                let wd = t.DayOfWeek.rawValue
                var ok = false
                if freq == "DAILY" { ok = CInt(Math.Round((t - day0).TotalDays)) % interval == 0 && (byday == nil || HasDay(byday!, wd)) }
                else if freq == "WEEKLY" {
                    let weeks = CInt(Math.Floor((t - mon0).TotalDays / 7))
                    ok = weeks % interval == 0 && (byday != nil ? HasDay(byday!, wd) : wd == day0.DayOfWeek.rawValue)
                }
                else if freq == "MONTHLY" {
                    let months = (t.Year - e.Start.Y) * 12 + (t.Month - e.Start.M)
                    if months % interval == 0 {
                        if byday != nil {
                            for b in byday! {
                                let mm = Regex.Match(b.Trim(), #"^([+-]?\d+)?(\w\w)$"#)
                                if !mm.Success || mm.Groups[2].Value != DAYS[wd] { continue }
                                if !mm.Groups[1].Success { ok = true; break }
                                let nth = int.Parse(mm.Groups[1].Value)
                                if nth > 0 && (t.Day + 6) / 7 == nth { ok = true; break }
                                let dim = DateTime.DaysInMonth(t.Year, t.Month)
                                if nth < 0 && (dim - t.Day + 7) / 7 == -nth { ok = true; break }
                            }
                        }
                        else { ok = bymd != nil ? bymd!.Contains(t.Day) : t.Day == e.Start.D }
                    }
                }
                else if freq == "YEARLY" { ok = (t.Year - e.Start.Y) % interval == 0 && t.Month == e.Start.M && t.Day == e.Start.D }
                if !ok { continue }
                var startUtc = WallToUtc(t.Year, t.Month, t.Day, e.Start.H, e.Start.Mi, e.Start.S, e.Start.Tz, nil)
                if e.Start.Tz != nil && e.Start.Tz != "UTC" { startUtc = e.Start.Utc + (startUtc - WallToUtc(e.Start.Y, e.Start.M, e.Start.D, e.Start.H, e.Start.Mi, e.Start.S, e.Start.Tz, nil)) }   // 用同一套時區換算，固定時差的 VTIMEZONE 也對
                if startUtc > until { break }
                n += 1
                if e.ExDates.Contains(startUtc) { continue }
                var ov: IcsEvent? = nil
                if overrides.TryGetValue(e.Uid + "@" + String(startUtc), &ov) { if ov!.Start != nil { Push(outl, ov!, ov!.Start.Utc, e, from, to) }; continue }
                Push(outl, e, startUtc, nil, from, to)
            }
        }
        outl.Sort { (a: IcsOcc, b: IcsOcc) -> Int in a.Start.CompareTo(b.Start) }
        return outl
    }

    static func Get(_ r: Dict<String, String>, _ k: String) -> String { var v = ""; return r.TryGetValue(k, &v) ? v : "" }
    static func ToInt(_ s: String, _ d: Int) -> Int { var v = 0; return int.TryParse(s, &v) ? v : d }
    static func HasDay(_ byday: [String], _ wd: Int) -> Bool { for b in byday { let x = b.Trim(); if x.Length >= 2 && x.Substring(x.Length - 2) == DAYS[wd] { return true } }; return false }

    static func Push(_ outl: List<IcsOcc>, _ e: IcsEvent, _ startUtc: Int, _ parent: IcsEvent!, _ from: Int, _ to: Int) {
        if e.Status == "CANCELLED" || e.Declined { return }
        if startUtc < from || startUtc > to { return }
        let src: IcsEvent! = e.End != nil && e.Start != nil ? e : (parent != nil && parent.End != nil && parent.Start != nil ? parent : nil)
        let len = src != nil ? Math.Max(5 * 60000, src.End.Utc - src.Start.Utc) : 30 * 60000
        let o = IcsOcc()
        o.Uid = e.Uid != "" ? e.Uid : e.Summary; o.Start = startUtc; o.End = startUtc + len
        o.Summary = e.Summary != "" ? e.Summary : (parent != nil && parent.Summary != "" ? parent.Summary : "（沒有標題）")
        o.Link = MeetLink(e); if o.Link == "" && parent != nil { o.Link = MeetLink(parent) }
        o.Ev = e; o.Parent = parent
        outl.Add(o)
    }

    static let MeetRe = Regex(#"https://(?:meet\.google\.com|[\w.-]*zoom\.us|teams\.microsoft\.com|teams\.live\.com)/[^\s"<>)]+"#, RegexOptions.IgnoreCase)
    static func MeetLink(_ e: IcsEvent) -> String {
        if e.Conf.StartsWith("https://") { return e.Conf }
        let m = MeetRe.Match(e.Location + " " + e.Description + " " + e.Url)
        if m.Success { return m.Value }
        return e.Url.StartsWith("https://") ? e.Url : ""
    }
}

// ================= 學校行事曆：分類（上課／考試／行程／作業死線）=================
// 各家 ICS 的實際長相（規則照這個寫；test/fixtures 有範例，test/desktop-study.js 驗）：
//   Canvas（含 NTU COOL）：/feeds/calendars/user_….ics；作業 UID＝event-assignment-<id>（討論區分段＝event-sub-assignment-），
//     SUMMARY＝「標題 [課程代碼]」，DTSTART＝DTEND＝截止時間（UTC）；23:59 截止的作業是全天事件（只有 DTSTART;VALUE=DATE）；
//     URL＝…/calendar?include_contexts=course_<課>&…#assignment_<id>。行事曆活動 UID＝event-calendar-event-<id>。
//   Moodle：/calendar/export_execute.php?…；UID＝<id>@<主機>，SUMMARY＝「<名稱> is due」「… closes」「… opens」（介面語言），
//     截止類 DTSTART＝DTEND（UTC），CATEGORIES＝課程簡稱，沒有 URL。
//   Google Classroom：每個課程一個 Google 日曆（ID 含 classroom…@group.calendar.google.com），裡面只有作業截止：
//     沒設時間＝全天事件（當天 23:59 截止），有時間＝在截止時間的事件；說明裡有 classroom.google.com 的作業連結。
final class SchoolFeed { var Url: String! = nil, Kind: String! = nil, Name: String! = nil, Base: String! = nil, Owner: String! = nil; var Events: List<IcsEvent>! = nil; init() {} }
final class SchoolTimed { var Id: String! = nil, Kind: String! = nil, Summary: String! = nil, Location: String! = nil, Link: String! = nil; var Start = 0, End = 0; init() {} }
final class SchoolDue { var Id: String! = nil, Title: String! = nil, Course: String! = nil, Url: String! = nil; var Due = 0; init() {} }
final class SchoolExam { var Id: String! = nil, Name: String! = nil; var At = 0; init() {} }
final class SchoolScan { let Timed = List<SchoolTimed>(); let Dues = List<SchoolDue>(); let Exams = List<SchoolExam>(); init() {} }
final class SchoolPlanItem { var At = 0; var Kind: String! = nil, Url: String! = nil, Text: String! = nil, Key: String! = nil; var QuietMin = 0; init() {} }

enum School {
    // ECMAScript：\b、\w 只看英數字（中文字旁邊的 due 也算一個字），跟 JS 一樣
    // mac: NSRegularExpression 沒有 ECMAScript 模式 → \b、\d、\s、\w 寫成 ASCII 的字元類（RegexOptions.ECMAScript 照留著，shim 不理它）
    static let O: RegexOptions = [RegexOptions.IgnoreCase, RegexOptions.ECMAScript]
    static let B = "(?<![A-Za-z0-9_])", E = "(?![A-Za-z0-9_])", Dg = "[0-9]", Sp = #"[ \t\n\x0B\f\r]"#
    static let DueWord = Regex("作業|功課|截止|到期|繳交|交件|提交|期限|deadline|" + B + "due" + E + "|assignment|homework|" + B + "hw" + Sp + "*" + Dg + "|submission|" + B + "closes?" + E, O)
    static let DueHard = Regex("截止|到期|繳交|交件|deadline|" + B + "due" + E + "|" + B + "closes?" + E, O)   // 有長度的單次行程也算死線（例如自己排的「報告繳交截止」）
    static let Opens = Regex(B + "opens?" + E + "|開放作答|開始作答|開放繳交|開始繳交|開放提交", O)  // Moodle「… opens」：開始，不是截止
    static let ExamWord = Regex("期中考|期末考|小考|考試|段考|會考|測驗|" + B + "exams?" + E + "|midterm|final exam|" + B + "quiz" + E, O)
    static let ClassWord = Regex("上課|課程|講堂|教室|實驗|演習|助教課|" + B + "lecture" + E + "|" + B + "lab" + E + "|" + B + "tutorial" + E + "|" + B + "seminar" + E + "|" + B + "class" + E + "|" + B + "section" + E + "|[館樓院]" + Sp + "*" + Dg + Dg, O)   // 課號（MATH4006）不算：Canvas 每個活動都帶課號
    static let AssignLink = Regex("/courses/" + Dg + "+/assignments/" + Dg + "+|#assignment_" + Dg + "+|classroom\\.google\\.com/(?:u/" + Dg + "+/)?c/[^ \\t\\n\\x0B\\f\\r/]+/(?:a|sa|mc)/|/mod/(?:assign|quiz|workshop)/view\\.php", O)

    static func KindOf(_ url: String!, _ text: String) -> String {
        var u = url ?? ""
        u = Uri.UnescapeDataString(u)
        if Regex.IsMatch(u, "/feeds/calendars/", O) || Regex.IsMatch(text, "^UID:event-(?:sub-)?assignment-|^UID:event-calendar-event-", RegexOptions.Multiline) { return "canvas" }
        if Regex.IsMatch(u, #"/calendar/export_execute\.php"#, O) || Regex.IsMatch(text, "^PRODID:.*moodle", [RegexOptions.Multiline, RegexOptions.IgnoreCase]) { return "moodle" }
        if Regex.IsMatch(u, #"classroom[^/@]*@group\.calendar\.google\.com"#, O) || Regex.IsMatch(text, "^X-WR-CALNAME:.*classroom", [RegexOptions.Multiline, RegexOptions.IgnoreCase]) { return "classroom" }
        return "generic"
    }

    static func Feed(_ url: String!, _ text: String) -> SchoolFeed {
        let f = SchoolFeed()
        f.Url = url ?? ""; f.Kind = KindOf(url, text)
        let b = Regex.Match(f.Url, #"^(https://.+?)/calendar/export_execute\.php"#, RegexOptions.IgnoreCase)
        f.Base = b.Success ? b.Groups[1].Value : ""
        let ow = Regex.Match(f.Url, "/ical/([^/]+)/")
        f.Owner = ow.Success ? Uri.UnescapeDataString(ow.Groups[1].Value) : ""
        var name = ""
        f.Events = Ics.Parse(text, f.Owner, &name)
        f.Name = name
        return f
    }

    // assignment｜exam｜class｜event｜skip
    static func Classify(_ e: IcsEvent, _ feed: SchoolFeed, _ parent: IcsEvent!) -> String {
        if e.Start == nil || e.Status == "CANCELLED" { return "skip" }
        let sum: String = e.Summary != "" ? e.Summary : (parent != nil ? parent.Summary : "")
        let allDay = e.Start.AllDay
        let zero = !allDay && (e.End == nil || e.End.Utc - e.Start.Utc <= 60000)   // Canvas／Moodle 的截止＝開始和結束同一刻
        let recurring = e.RRule != "" || e.RecurrenceId != nil || (parent != nil && parent.RRule != "")
        let linky = e.Url + " " + e.Description + " " + e.Location
        if feed.Kind == "canvas" && Regex.IsMatch(e.Uid, "^event-(?:sub-)?assignment-", O) { return "assignment" }
        if feed.Kind == "classroom" { return Opens.IsMatch(sum) ? "skip" : "assignment" }   // Classroom 課程日曆只放作業截止
        if Opens.IsMatch(sum) && (zero || allDay) { return "skip" }
        if AssignLink.IsMatch(e.Url) || ((zero || allDay) && AssignLink.IsMatch(linky)) { return "assignment" }
        if (zero || allDay) && DueWord.IsMatch(sum) { return "assignment" }
        if !allDay && !recurring && DueHard.IsMatch(sum) && !ExamWord.IsMatch(sum) { return "assignment" }
        if !allDay && ExamWord.IsMatch(sum) { return "exam" }
        if zero && (feed.Kind == "moodle" || DueWord.IsMatch(e.Description)) { return "assignment" }
        if allDay { return "skip" }          // 放假、校慶這類全天事件不提醒
        if recurring || ClassWord.IsMatch((sum + " " + e.Location).Replace("助教室", "")) { return "class" }
        return "event"
    }

    static func Clean(_ s: String!) -> String { return Regex.Replace(s ?? "", #"[\r\n]+"#, " ").Trim() }

    static func Title(_ e: IcsEvent, _ feed: SchoolFeed, _ title: inout String, _ course: inout String) {
        title = Clean(e.Summary); course = ""
        if title == "" { title = "（沒有標題）" }
        if feed.Kind == "canvas" {
            let m = Regex.Match(title, #"^(.*\S)\s*\[([^\]]+)\]$"#)
            if m.Success { title = m.Groups[1].Value; course = m.Groups[2].Value }
        }
        if feed.Kind == "moodle" {
            let t = Regex.Replace(Regex.Replace(title, #"\s+(?:is due to be graded|is due|closes|due)$"#, "", RegexOptions.IgnoreCase), #"\s*(?:截止|到期)$"#, "")
            if t != "" { title = t }
            course = Clean(e.Categories)
        }
        if feed.Kind == "classroom" { course = feed.Name }
    }

    static func FirstHttps(_ text: String, _ httpToo: Bool) -> String {
        let m = Regex.Match(text, httpToo ? #"https?://[^\s"<>)\\]+"# : #"https://[^\s"<>)\\]+"#, RegexOptions.IgnoreCase)
        return m.Success ? m.Value : ""
    }

    static func AssignUrl(_ e: IcsEvent, _ feed: SchoolFeed, _ due: Int) -> String {
        let u = Regex.IsMatch(e.Url, "^https?://", RegexOptions.IgnoreCase) ? e.Url.Trim() : ""
        if feed.Kind == "canvas" && u != "" {
            // 行事曆頁 → 直接到作業頁
            let ctx = Regex.Match(u, #"include_contexts=course_(\d+)"#), a = Regex.Match(u, #"#assignment_(\d+)"#)
            var uri: Uri? = nil
            if ctx.Success && a.Success && Uri.TryCreate(u, UriKind.Absolute, &uri) { return uri!.Scheme + "://" + uri!.Authority + "/courses/" + ctx.Groups[1].Value + "/assignments/" + a.Groups[1].Value }
            return u
        }
        let text = e.Description + " " + e.Location + " " + e.Url
        let cr = Regex.Match(text, #"https://classroom\.google\.com/[^\s"<>)\\]+"#, RegexOptions.IgnoreCase)
        if cr.Success { return cr.Value }
        if u != "" { return u }
        if feed.Kind == "moodle" && feed.Base != "" { return feed.Base + "/calendar/view.php?view=day&time=" + String(due / 1000) }
        if feed.Kind == "classroom" { return "https://classroom.google.com/" }
        return FirstHttps(text, false)
    }

    static func EventLink(_ e: IcsEvent, _ parent: IcsEvent!) -> String {
        var m = Ics.MeetLink(e)
        if m == "" && parent != nil { m = Ics.MeetLink(parent) }
        if m != "" { return m }
        return FirstHttps(e.Url + " " + e.Location + " " + e.Description, true)
    }

    static func SafeId(_ s: String!) -> String { return Regex.Replace(s ?? "", #"\s+"#, "_") }
    // Canvas 的活動標題後面帶「 [課程代碼]」：講出來改成「（課程代碼）」
    static func Nice(_ s0: String!, _ feed: SchoolFeed) -> String { let s = Clean(s0); return feed.Kind == "canvas" ? Regex.Replace(s, #"\s*\[([^\]]+)\]$"#, "（$1）") : s }

    // 接下來 26 小時的課／考試／行程、14 天內的作業死線、120 天內的考試
    static func Scan(_ feeds: List<SchoolFeed>, _ now: Int) -> SchoolScan {
        let dueTo = now + 14 * 86400000, examTo = now + 120 * 86400000, timedTo = now + 26 * 3600000
        let r = SchoolScan()
        let seen = HashSet<String>()
        for feed in feeds {
            // 全天的作業（Canvas 23:59 截止、Classroom 沒設時間）：當天 23:59 截止
            for e in feed.Events! {
                if e.Start == nil || !e.Start.AllDay || e.RRule != "" || e.RecurrenceId != nil || e.Declined { continue }
                if Classify(e, feed, nil) != "assignment" { continue }
                AddDue(r, seen, e, feed, Ics.WallToUtc(e.Start.Y, e.Start.M, e.Start.D, 23, 59, 0, nil, nil), now, dueTo)
            }
            for o in Ics.Occurrences(feed.Events, now - 5 * 60000, examTo) {
                let kind = Classify(o.Ev, feed, o.Parent)
                if kind == "assignment" { AddDue(r, seen, o.Ev, feed, o.Start, now, dueTo) }
                if kind == "exam" && o.Start > now { let x = SchoolExam(); x.Id = SafeId(o.Uid + "@" + String(o.Start)); x.At = o.Start; x.Name = Nice(o.Summary, feed); r.Exams.Add(x) }
                if (kind == "class" || kind == "exam" || kind == "event") && o.Start <= timedTo {
                    let loc = Clean(o.Ev.Location != "" ? o.Ev.Location : (o.Parent != nil ? o.Parent.Location : ""))
                    let t = SchoolTimed()
                    t.Id = SafeId(o.Uid + "@" + String(o.Start)); t.Kind = kind; t.Start = o.Start; t.End = o.End; t.Summary = Nice(o.Summary, feed)
                    t.Location = Regex.IsMatch(loc, "^https?:", RegexOptions.IgnoreCase) ? "" : loc; t.Link = EventLink(o.Ev, o.Parent)
                    r.Timed.Add(t)
                }
            }
        }
        r.Dues.Sort { (a: SchoolDue, b: SchoolDue) -> Int in a.Due.CompareTo(b.Due) }
        r.Exams.Sort { (a: SchoolExam, b: SchoolExam) -> Int in a.At.CompareTo(b.At) }
        return r
    }

    static func AddDue(_ r: SchoolScan, _ seen: HashSet<String>, _ e: IcsEvent, _ feed: SchoolFeed, _ due: Int, _ now: Int, _ dueTo: Int) {
        if due <= now || due > dueTo { return }
        var title = "", course = ""
        Title(e, feed, &title, &course)
        if !seen.Add(title + "|" + String(due)) { return }   // 同一份作業出現在兩個行事曆
        let d = SchoolDue()
        d.Id = SafeId((e.Uid != "" ? e.Uid : title) + "@" + String(due)); d.Due = due; d.Title = title; d.Course = course; d.Url = AssignUrl(e, feed, due)
        r.Dues.Add(d)
    }

    // 上課／考試／行程的提醒：課前 N 分鐘＋開始時；上課、考試自動安靜（最多 4 小時）；同一時間的合成一則（考試優先）
    static func Plan(_ timed: List<SchoolTimed>, _ now: Int, _ before: Int, _ autoQuiet: Bool) -> List<SchoolPlanItem> {
        let groups = Dict<Int, List<SchoolTimed>>()
        let order = List<Int>()
        for t in timed {
            var g: List<SchoolTimed>? = nil
            if !groups.TryGetValue(t.Start, &g) { g = List<SchoolTimed>(); groups[t.Start] = g!; order.Add(t.Start) }
            g!.Add(t)
        }
        let plan = List<SchoolPlanItem>()
        for start in order {
            let g: List<SchoolTimed> = groups[start]
            var kind = "event", link = "", loc = "", key = ""
            var end = start
            var names: [String] = []
            for t in g {
                if Rank(t.Kind) > Rank(kind) { kind = t.Kind }
                if link == "" { link = t.Link }
                if loc == "" { loc = t.Location }
                end = Math.Max(end, t.End)
                names.append(t.Summary)
                key += (key == "" ? "" : "+") + t.Id
            }
            let name = names.count > 1 ? names[0] + "、" + names[1] + (names.count > 2 ? " 等 " + String(names.count) + " 個" : "") : names[0]
            let hhmm = DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMilliseconds(start).ToLocalTime().ToString("HH:mm")
            let where_ = loc != "" ? "・" + (loc.Length > 16 ? loc.Substring(0, 16) + "…" : loc) : ""
            let bs = String(before)
            let pre: String = kind == "class" ? hhmm + " " + name + where_ + "（" + bs + " 分鐘後）"
                : kind == "exam" ? hhmm + " " + name + where_ + "（" + bs + " 分鐘後），文具帶好，加油！"
                : hhmm + " " + name + where_ + "（" + bs + " 分鐘後）"
            let go: String = kind == "class" ? name + (link != "" ? "（點我打開）" : "")
                : kind == "exam" ? name + "，加油！🍀"
                : name + (link != "" ? "（點我打開）" : "")
            let kPre = kind == "class" ? "class" : (kind == "exam" ? "exam-soon" : "event")
            let kNow = kind == "class" ? "class-now" : (kind == "exam" ? "exam-now" : "event-now")
            let at1 = start - before * 60000
            if at1 > now { plan.Add(Item(at1, kPre, link, pre, 0, key + "@" + String(start) + "-pre")) }
            if start > now {
                let q = autoQuiet && kind != "event" ? CInt(Math.Min(240.0, Math.Round(Double(end - start) / 60000.0))) : 0
                plan.Add(Item(start, kNow, link, go, Math.Max(0, q), key + "@" + String(start) + "-now"))
            }
        }
        plan.Sort { (a: SchoolPlanItem, b: SchoolPlanItem) -> Int in a.At.CompareTo(b.At) }
        return plan
    }
    static func Rank(_ k: String) -> Int { return k == "exam" ? 3 : (k == "class" ? 2 : 1) }
    static func Item(_ at: Int, _ kind: String, _ url: String, _ text: String, _ q: Int, _ key: String) -> SchoolPlanItem {
        let p = SchoolPlanItem(); p.At = at; p.Kind = kind; p.Url = url; p.Text = text; p.QuietMin = q; p.Key = key
        return p
    }
}

//@@IN World
    // ---------- 測試用時鐘、閒置（離屏測試才會用到）----------
    var studyShift = TimeSpan.Zero
    var studyIdleFake: Double = -1
    var exams = List<Exam>()
    var deadlines = List<Deadline>()
    let studyDone = HashSet<String>()
    let deadlineNotes = Dict<String, List<String>>()   // 通知的字 → 哪幾份作業（點了可以標成交了）
    var studyLoaded = false, haveSchool = false
    var studyNext: Double = 0
    // ---------- 設定（study-config.txt；VS Code 推過來的那幾項以 VS Code 為準）----------
    let schoolUrls = List<String>()
    var classRemind = 10
    var classAutoQuiet = true, lateOn = true
    var lateStartMin = 60, examNudgeMin = 20 * 60      // 熬夜提醒幾點開始、考試倒數幾點講（-1＝關掉）
    var workCal = ""                                   // VS Code 開會提醒用的行事曆：學校這邊就不重複提醒
    let vsKeys = HashSet<String>()
    var lateKey = ""; var lateLevel = -1; var lateAsleep = false
    // ---------- 給 VS Code 的狀態 ----------
    var lastState = ""
    // ---------- 抓學校行事曆 ----------
    let testFeeds = List<KeyValuePair<String, String>>()   // 測試用：網址 → ICS 內容
    var fetchNow = true, replan = false                    // C#：volatile
    var fetchStarted = false
    var schoolStatus = ""                                 // 給設定視窗：上次更新的狀況
    var plan = List<SchoolPlanItem>()
    let planFired = HashSet<String>()
    var lastScan: SchoolScan! = nil
    // ---------- 小視窗 ----------
    var examForm: ExamForm! = nil
    var studyForm: StudySettingsForm! = nil
//@@END

extension World {
    func SNow() -> DateTime { return DateTime.Now + studyShift }
    func SNowMs() -> Int { return World.UnixMs(SNow()) }
    func StudyIdle() -> Double { return studyIdleFake >= 0 ? studyIdleFake : Double(W.IdleSeconds()) }

    final class Exam { var At = 0; var Name: String! = nil, Id: String! = nil, Src: String! = nil; var LastDaily = ""; var DayBefore = false, Morning = false; init() {} }
    final class Deadline { var Id: String! = nil, Title: String! = nil, Course: String! = nil, Url: String! = nil; var Due = 0; var Stage = 0; init() {} }
    static let DueStages: [Int] = [3 * 24 * 60, 24 * 60, 180, 60]   // 截止前 3 天、1 天、3 小時、1 小時

    // ================= 存檔 =================
    func LoadStudy() {
        studyLoaded = true
        exams.Clear(); deadlines.Clear(); studyDone.Clear()
        for line in World.ReadText("exams.txt").Split("\n") {
            let a = line.TrimEnd("\r").Split("\t")
            var at = 0
            if a.count < 6 || !long.TryParse(a[0], &at) { continue }
            let e = Exam(); e.At = at; e.Src = a[1]; e.LastDaily = a[2]
            e.DayBefore = a[3].Length > 0 && a[3][0] == "1"; e.Morning = a[3].Length > 1 && a[3][1] == "1"
            e.Id = a[4]; e.Name = a[5]
            exams.Add(e)
        }
        for line in World.ReadText("deadlines.txt").Split("\n") {
            let a = line.TrimEnd("\r").Split("\t")
            var due = 0, stage = 0
            if a.count < 6 || !long.TryParse(a[0], &due) || !int.TryParse(a[1], &stage) { continue }
            let d = Deadline(); d.Due = due; d.Stage = stage; d.Id = a[2]; d.Url = a[3] == "-" ? nil : a[3]; d.Course = a[4] == "-" ? "" : a[4]; d.Title = a[5]
            deadlines.Add(d)
        }
        for line in World.ReadText("study-done.txt").Split("\n") { if line.Trim() != "" { studyDone.Add(line.Trim()) } }
        LoadStudyConfig()
        haveSchool = schoolUrls.Count > 0
        let lk = World.ReadText("late.txt").Split("\t")
        if lk.count == 3 { lateKey = lk[0]; _ = int.TryParse(lk[1], &lateLevel); lateAsleep = lk[2] == "1" }
    }

    func LoadStudyConfig() {
        lock(schoolUrls) {
            schoolUrls.Clear(); vsKeys.Clear()
            for line in World.ReadText("study-config.txt").Split("\n") {
                let l = line.Trim()
                let i = l.IndexOf("=")
                if i <= 0 { continue }
                let k = l.Substring(0, i), v = l.Substring(i + 1).Trim()
                switch k {
                case "url": let u = World.NormUrl(v); if u != nil && !schoolUrls.Contains(u!) { schoolUrls.Add(u!) }
                case "remind": var n = 0; if int.TryParse(v, &n) && n > 0 { classRemind = Math.Min(120, n) }
                case "autoquiet": classAutoQuiet = v != "0"
                case "late": let m = World.ParseHm(v); if m >= 0 { lateStartMin = m }
                case "lateon": lateOn = v != "0"
                case "nudge": examNudgeMin = v == "off" ? -1 : (World.ParseHm(v) >= 0 ? World.ParseHm(v) : examNudgeMin)
                case "workcal": workCal = v
                case "vs": for x in v.Split(",") { if x.Trim() != "" { vsKeys.Add(x.Trim()) } }
                default: break
                }
            }
        }
    }

    func SaveStudyConfig() {
        let sb = StringBuilder()
        lock(schoolUrls) { for u in schoolUrls { sb.Append("url=" + u + "\n") } }
        sb.Append("remind=" + String(classRemind) + "\nautoquiet=" + (classAutoQuiet ? "1" : "0") + "\nlate=" + World.Hm(lateStartMin) + "\nlateon=" + (lateOn ? "1" : "0") + "\nnudge=" + World.Hm(examNudgeMin) + "\n")
        if workCal != "" { sb.Append("workcal=" + workCal + "\n") }
        if vsKeys.Count > 0 { sb.Append("vs=" + string.Join(",", vsKeys.ToArray()) + "\n") }
        World.WriteText("study-config.txt", sb.ToString())
    }

    // https://…、webcal://…（當成 https）；其他不收
    static func NormUrl(_ s0: String!) -> String! {
        var s = (s0 ?? "").Trim()
        if s.StartsWith("webcal://", StringComparison.OrdinalIgnoreCase) { s = "https://" + s.Substring(9) }
        else if s.StartsWith("webcals://", StringComparison.OrdinalIgnoreCase) { s = "https://" + s.Substring(10) }
        var u: Uri? = nil
        if !s.StartsWith("https://", StringComparison.OrdinalIgnoreCase) || !Uri.TryCreate(s, UriKind.Absolute, &u) { return nil }
        return s
    }

    func SaveExams() {
        let sb = StringBuilder()
        for e in exams {
            let a: String = String(e.At) + "\t" + e.Src + "\t" + e.LastDaily + "\t" + (e.DayBefore ? "1" : "0") + (e.Morning ? "1" : "0")
            sb.Append(a + "\t" + e.Id + "\t" + World.OneLine(e.Name) + "\n")
        }
        World.WriteText("exams.txt", sb.ToString())
    }

    func SaveDeadlines() {
        let sb = StringBuilder()
        for d in deadlines {
            let a: String = String(d.Due) + "\t" + String(d.Stage) + "\t" + d.Id + "\t" + (d.Url ?? "-")
            sb.Append(a + "\t" + (d.Course == "" ? "-" : World.OneLine(d.Course)) + "\t" + World.OneLine(d.Title) + "\n")
        }
        World.WriteText("deadlines.txt", sb.ToString())
    }

    func SaveLate() { World.WriteText("late.txt", lateKey + "\t" + String(lateLevel) + "\t" + (lateAsleep ? "1" : "0")) }

    static func OneLine(_ s: String!) -> String { return (s ?? "").Replace("\t", " ").Replace("\r", " ").Replace("\n", " ").Trim() }

    // "01:00" → 60；"off"、空白、看不懂 → -1
    static func ParseHm(_ s: String!) -> Int {
        let a = (s ?? "").Trim().Replace("：", ":").Split(":")
        var h = 0, m = 0
        if a.count == 2 && int.TryParse(a[0], &h) && int.TryParse(a[1], &m) && h >= 0 && h < 24 && m >= 0 && m < 60 { return h * 60 + m }
        return -1
    }
    static func Hm(_ min: Int) -> String { return min < 0 ? "off" : (min / 60).ToString("00") + ":" + (min % 60).ToString("00") }

    // ================= pipe =================
    static func NthSpace(_ t: String, _ n: Int) -> Int { var i = -1; var k = 0; while k < n { i = t.IndexOf(" ", i + 1); if i < 0 { return -1 }; k += 1 }; return i }

    func StudyMsg(_ c: Client, _ p: [String], _ line: String) {
        if !studyLoaded { LoadStudy() }
        let t = line.Trim()
        switch p[0] {
        case "course":
            if p.count >= 5 {
                var ms = 0, lead = 0; let i4 = World.NthSpace(t, 4)
                if long.TryParse(p[1], &ms) && int.TryParse(p[2], &lead) { AddTicket(ms, lead, p[3], i4 > 0 ? t.Substring(i4 + 1) : "", "course") }
            }
        case "exam":
            if p.count >= 3 {
                var ms = 0; let i2 = World.NthSpace(t, 2)
                if long.TryParse(p[1], &ms) { AddExam(ms, i2 > 0 ? t.Substring(i2 + 1).Trim() : "", "me", nil, true) }
            }
        case "exam-del": if p.count >= 2 { DelExam(p[1]) }
        case "study-set": if p.count >= 2 { StudySet(p) }
        case "study-vs":   // VS Code 這次管哪幾項（其他的交還給桌面版的設定視窗）
            vsKeys.Clear()
            if p.count >= 2 { for k in p[1].Split(",") { if k != "-" && k.Trim() != "" { vsKeys.Add(k.Trim()) } } }
            StudySaved()
        case "study-hello": World.Send(c, StateLine())
        case "study-done": if p.count >= 2 { MarkDone(p[1], false); PushState() }
        // ---- 測試用（只在離屏模式）----
        case "study-ics":
            if !App.Offscreen { break }
            if p.count >= 2 && p[1] == "clear" { testFeeds.Clear(); haveSchool = schoolUrls.Count > 0 }
            else if p.count >= 2 {
                do { testFeeds.Add(KeyValuePair<String, String>(p.count >= 3 ? p[2] : p[1], try File.ReadAllText(p[1], Encoding.UTF8))) }
                catch { App.Log("study-ics: " + error.localizedDescription) }
            }
            RescanNow()
        case "study-clock":
            var want = DateTime.MinValue
            if p.count >= 2 && DateTime.TryParse(p[1], &want) { studyShift = want - DateTime.Now } else { studyShift = TimeSpan.Zero }
            studyNext = 0
            if testFeeds.Count > 0 { RescanNow() }
        case "study-idle": var s: Double = 0; studyIdleFake = p.count >= 2 && double.TryParse(p[1], &s) ? s : -1
        case "study-dump": World.Send(c, StudyDump())
        case "study-settings":
            if p.count < 2 { break }
            if p[1] == "open" { ShowStudySettings() }
            else if studyForm != nil && !studyForm.IsDisposed {
                if p[1] == "close" { studyForm.Close() }
                else if p[1] == "save" { studyForm.Save() }
                else if p[1] == "set" && p.count >= 4 { studyForm.TestSet(p[2], t.Substring(World.NthSpace(t, 3) + 1)) }
            }
        default: break
        }
    }

    // VS Code 推設定：推過的那一項就記成「由 VS Code 管理」
    func StudySet(_ p: [String]) {
        let k = p[1]
        switch k {
        case "urls":
            lock(schoolUrls) {
                schoolUrls.Clear()
                var i = 2
                while i < p.count { let u = World.NormUrl(p[i]); if u != nil && !schoolUrls.Contains(u!) { schoolUrls.Add(u!) }; i += 1 }
            }
            haveSchool = schoolUrls.Count > 0 || testFeeds.Count > 0
            fetchNow = true
        case "remind": var n = 0; if p.count >= 3 && int.TryParse(p[2], &n) && n > 0 { classRemind = Math.Min(120, n) }; replan = true
        case "autoquiet": classAutoQuiet = p.count < 3 || p[2] != "0"; replan = true
        case "late": let m = p.count >= 3 ? World.ParseHm(p[2]) : -1; lateOn = m >= 0; if m >= 0 { lateStartMin = m }
        case "nudge": examNudgeMin = p.count >= 3 ? World.ParseHm(p[2]) : -1
        case "workcal": workCal = p.count >= 3 && p[2] != "-" ? (World.NormUrl(p[2]) ?? "") : ""; fetchNow = true; StudySaved(); return
        default: return
        }
        vsKeys.Add(k)
        StudySaved()
    }
    func StudySaved() { SaveStudyConfig(); if studyForm != nil && !studyForm.IsDisposed { studyForm.Reload() } }

    func StudyDump() -> String {
        let sb = StringBuilder()
        var head: String = "study now=" + SNow().ToString("yyyy-MM-ddTHH:mm") + " school=" + (haveSchool ? "1" : "0") + " urls=" + String(schoolUrls.Count) + " remind=" + String(classRemind) + " autoquiet=" + (classAutoQuiet ? "1" : "0")
        head += " late=" + (lateOn ? World.Hm(lateStartMin) : "off") + " nudge=" + World.Hm(examNudgeMin) + " lateKey=" + lateKey + " lateLevel=" + String(lateLevel) + " asleep=" + (lateAsleep ? "1" : "0")
        head += " quiet=" + String(quietOn ? QuietLeft() : 0) + " vs=" + string.Join(",", vsKeys.ToArray()) + "\n"
        sb.Append(head)
        for e in exams { sb.Append("exam " + e.Src + " " + World.FromUnixMs(e.At).ToString("yyyy-MM-ddTHH:mm") + " daily=" + e.LastDaily + " before=" + (e.DayBefore ? "1" : "0") + " morning=" + (e.Morning ? "1" : "0") + " " + e.Name + "\n") }
        for d in deadlines { sb.Append("deadline " + World.FromUnixMs(d.Due).ToString("yyyy-MM-ddTHH:mm") + " stage=" + String(d.Stage) + " " + d.Title + (d.Course != "" ? " [" + d.Course + "]" : "") + " " + (d.Url ?? "-") + "\n") }
        for it in plan { sb.Append("plan " + World.FromUnixMs(it.At).ToString("yyyy-MM-ddTHH:mm") + " " + it.Kind + " q=" + String(it.QuietMin) + (planFired.Contains(it.Key) ? " fired" : "") + " " + it.Text + "\n") }
        for tk in tickets { sb.Append("ticket " + tk.Kind + " " + World.FromUnixMs(tk.At).ToString("yyyy-MM-ddTHH:mm") + " stage=" + String(tk.Stage) + " " + tk.Name + "\n") }
        sb.Append("bar " + BarText() + "\n")
        sb.Append("end\n")
        return sb.ToString()
    }

    // ================= 給 VS Code 的狀態（狀態列、「這週要交的」）=================
    func StateLine() -> String {
        let now = SNowMs()
        var d: [Any] = [], e: [Any] = []
        for x in deadlines {
            if x.Due <= now || x.Due - now > 7 * 86400000 { continue }
            let o = Dict<String, Any>()
            o["id"] = x.Id as Any; o["due"] = x.Due; o["title"] = x.Title as Any; o["course"] = x.Course as Any; o["url"] = x.Url ?? ""
            d.append(o)
        }
        for x in exams {
            let o = Dict<String, Any>()
            o["id"] = x.Id as Any; o["at"] = x.At; o["name"] = x.Name as Any
            e.append(o)
        }
        let s = Dict<String, Any>()
        s["bar"] = BarText(); s["school"] = haveSchool ? 1 : 0; s["d"] = d; s["e"] = e
        return "study-state " + JavaScriptSerializer().Serialize(s) + "\n"
    }
    func PushState() {
        let s = StateLine()
        if s == lastState { return }
        lastState = s
        lock(clients) { for c in clients { World.Send(c, s) } }
    }

    // 狀態列：24 小時內的作業、7 天內的考試，挑最近的一個（沒有就空白）
    func BarText() -> String {
        let now = SNowMs(); var best = long.MaxValue
        var text = ""
        for x in deadlines {
            if x.Due > now && x.Due - now <= 24 * 3600000 && x.Due < best { best = x.Due; text = "📝 " + World.Short(x.Title, 8) + " " + World.LeftText(x.Due - now) }
        }
        for x in exams {
            if x.At > now && x.At - now <= 7 * 86400000 && x.At < best {
                best = x.At
                let days = (World.FromUnixMs(x.At).Date - SNow().Date).Days
                text = "📚 " + World.Short(x.Name, 8) + " " + (days <= 0 ? "今天" : (days == 1 ? "明天" : String(days) + " 天"))
            }
        }
        return text
    }
    static func LeftText(_ ms: Int) -> String {
        if ms < 3600000 { return "剩 " + String(Math.Max(1, CInt(Math.Ceiling(Double(ms) / 60000.0)))) + " 分" }
        if ms < 48 * 3600000 { return "剩 " + String(ms / 3600000) + " 小時" }
        return "剩 " + String(ms / 86400000) + " 天"
    }

    // ================= 抓學校行事曆（背景執行緒；連不上就用上次存的）=================
    func StartSchoolFetch() {
        fetchStarted = true
        let th = Thread { self.SchoolFetchLoop() }; th.IsBackground = true; th.Start()
    }

    func SchoolFetchLoop() {
        var nextFetch = DateTime.MinValue, nextScan = DateTime.MinValue
        let texts = Dict<String, String>()
        Thread.Sleep(3000)
        while !closing {
            do {
                let urls: List<String> = lock(schoolUrls) { List<String>(schoolUrls) }
                let skip = workCal
                urls.RemoveAll { (u: String) -> Bool in u == skip }   // 跟 VS Code 開會提醒同一份：不要提醒兩次
                let doFetch = fetchNow || DateTime.Now >= nextFetch
                if urls.Count > 0 && !App.Offscreen && doFetch {
                    fetchNow = false
                    nextFetch = DateTime.Now.AddMinutes(10)
                    var ok = 0
                    var err = ""
                    for u in urls {
                        var text: String! = World.Fetch(u, &err)
                        if text != nil { ok += 1; World.WriteText(World.CacheName(u), text) }
                        else { text = World.ReadText(World.CacheName(u)) }
                        if !string.IsNullOrEmpty(text) { texts[u] = text }
                    }
                    let st = DateTime.Now.ToString("HH:mm") + " 更新：" + String(ok) + "/" + String(urls.Count) + " 個行事曆" + (err != "" ? "（" + err + "）" : "")
                    schoolStatus = st
                    nextScan = DateTime.MinValue
                }
                else if doFetch { fetchNow = false; nextFetch = DateTime.Now.AddMinutes(10) }
                if DateTime.Now >= nextScan || replan {
                    nextScan = DateTime.Now.AddMinutes(2)
                    let feeds = List<KeyValuePair<String, String>>()
                    for u in urls { var tx = ""; if texts.TryGetValue(u, &tx) { feeds.Add(KeyValuePair<String, String>(u, tx)) } }
                    let none = urls.Count == 0
                    if feeds.Count > 0 || none {
                        let r = ScanFeeds(feeds)
                        Post { if self.testFeeds.Count == 0 { self.ApplyScan(r, none) } }
                    }
                }
            }
            Thread.Sleep(1000)
        }
    }

    static func CacheName(_ url: String) -> String {
        let h = Array(Insecure.MD5.hash(data: Data(url.utf8)))   // mac: System.Security.Cryptography.MD5 → CryptoKit
        let sb = StringBuilder("school-")
        for i in 0..<6 { sb.Append(String(format: "%02x", h[i])) }
        sb.Append(".ics")
        return sb.ToString()
    }

    // mac: HttpWebRequest → URLSession（背景執行緒上用 semaphore 等；最多 4 次轉址、讀到 8 MB 就停）
    final class StudyFetchTask: NSObject, URLSessionDataDelegate {
        var data = Data()
        var status = 0
        var failed: Error? = nil
        var capped = false
        var redirects = 0
        let done = DispatchSemaphore(value: 0)
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            completionHandler(.allow)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive d: Data) {
            data.append(d)
            if data.count > 8000000 { capped = true; dataTask.cancel() }   // 最多 8 MB
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            redirects += 1
            completionHandler(redirects > 4 ? nil : request)
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if !capped { failed = error }
            done.signal()
        }
    }

    static func Fetch(_ url: String, _ err: inout String) -> String! {
        guard let u = URL(string: url) else { err = "讀取失敗"; App.Log("school ics: bad url"); return nil }
        var req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("DeskPals", forHTTPHeaderField: "User-Agent")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20; cfg.timeoutIntervalForResource = 120
        let ft = StudyFetchTask()
        let session = URLSession(configuration: cfg, delegate: ft, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        session.dataTask(with: req).resume()
        if ft.done.wait(timeout: .now() + 125) == .timedOut { session.invalidateAndCancel(); err = "連不上"; App.Log("school ics " + err + ": timeout"); return nil }
        if let e = ft.failed { err = "連不上"; App.Log("school ics " + err + ": " + e.localizedDescription); return nil }
        if ft.status >= 300 { err = "HTTP " + String(ft.status); App.Log("school ics " + err); return nil }
        var s = String(decoding: ft.data, as: UTF8.self)
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }   // StreamReader 會吃掉 BOM
        if !s.Contains("BEGIN:VCALENDAR") { err = "有一個網址不是行事曆"; return nil }
        return s
    }

    func ScanFeeds(_ feeds: List<KeyValuePair<String, String>>) -> SchoolScan {
        let fs = List<SchoolFeed>()
        for f in feeds { fs.Add(School.Feed(f.Key, f.Value)) }
        return School.Scan(fs, SNowMs())
    }

    // 測試：馬上用 testFeeds 掃一次（UI 執行緒）
    func RescanNow() {
        haveSchool = schoolUrls.Count > 0 || testFeeds.Count > 0
        if testFeeds.Count == 0 { return }
        ApplyScan(ScanFeeds(testFeeds), false)
    }

    // 掃完：作業死線、行事曆上的考試換成這次的（提醒到哪一段、交了的照舊）；上課提醒重排
    func ApplyScan(_ r: SchoolScan, _ none: Bool) {
        if !studyLoaded { LoadStudy() }
        lastScan = r
        haveSchool = !none || testFeeds.Count > 0
        let now = SNowMs()
        let old = Dict<String, Deadline>()
        for d in deadlines { old[d.Id] = d }
        deadlines.Clear()
        for x in r.Dues {
            if studyDone.Contains(x.Id) { continue }
            let d = Deadline()
            d.Id = x.Id; d.Due = x.Due; d.Title = x.Title; d.Course = x.Course; d.Url = World.SafeUrl(x.Url)
            if d.Url != nil && !d.Url.StartsWith("http") { d.Url = nil }
            var was: Deadline? = nil
            d.Stage = old.TryGetValue(d.Id, &was) && was!.Due == d.Due ? was!.Stage : World.FirstStage(d.Due, now)
            deadlines.Add(d)
        }
        let oldEx = Dict<String, Exam>()
        for e in exams { if e.Src == "ics" { oldEx[e.Id] = e } }
        exams.RemoveAll { (e: Exam) -> Bool in e.Src == "ics" }
        for x in r.Exams {
            if x.At <= now || studyDone.Contains(x.Id) { continue }
            var was: Exam? = nil
            if oldEx.TryGetValue(x.Id, &was) && was!.At == x.At { was!.Name = x.Name; exams.Add(was!) }
            else { AddExam(x.At, x.Name, "ics", x.Id, false) }
        }
        SortExams()
        SaveDeadlines(); SaveExams()
        replan = false
        plan = School.Plan(r.Timed, now - 3 * 60000, classRemind, classAutoQuiet)   // 剛到的那幾則也留著（重掃剛好卡在提醒那一刻不會漏；planFired 擋重複）
        PushState()
        if studyForm != nil && !studyForm.IsDisposed { studyForm.Invalidate() }
    }

    // 第一次看到：已經過了的階段不補，但 24 小時內的話，最近那段馬上講一次
    static func FirstStage(_ due: Int, _ now: Int) -> Int {
        let left = Double(due - now) / 60000.0
        var passed = 0
        for s in 0..<DueStages.count { if left <= Double(DueStages[s]) { passed = s + 1 } }
        if passed > 0 && left <= 24 * 60 && left > 0 { passed -= 1 }
        return passed
    }

    func MarkDone(_ id: String, _ tell: Bool) {
        if !studyLoaded { LoadStudy() }
        studyDone.Add(id)
        var keep = List<String>(studyDone.ToArray())
        if keep.Count > 500 { keep = keep.GetRange(keep.Count - 500, 500) }
        World.WriteText("study-done.txt", string.Join("\n", keep.ToArray()))
        deadlines.RemoveAll { (d: Deadline) -> Bool in d.Id == id }
        SaveDeadlines()
        if tell { let s = "study-done " + id + "\n"; lock(clients) { for c in clients { World.Send(c, s) } }; PushState() }
    }

    // ================= 每一輪 =================
    func StudyBusy() -> Bool { return quietOn || focusOn || sharing || fsNow || Hidden }

    func StudyTick() {
        if !studyLoaded { LoadStudy() }
        if Now < studyNext { return }
        studyNext = Now + 2
        if !fetchStarted { StartSchoolFetch() }
        PlanTick(); DeadlineTick(); ExamTick(); LateTick(); PushState()
    }

    // ================= 上課／考試／行程提醒（跟開會一樣：課前 N 分鐘、開始時；上課、考試中自動安靜）=================
    func PlanTick() {
        if plan.Count == 0 { return }
        let now = SNowMs()
        for it in plan {
            if it.At > now || planFired.Contains(it.Key) { continue }
            planFired.Add(it.Key)
            if now - it.At > (it.Kind.EndsWith("-now") ? 5 : 3) * 60000 { continue }   // 電腦睡著錯過太久的就不補
            App.Log("school " + it.Kind + ": " + it.Text)
            if it.Kind == "class-now" { Count("classes") }
            OnNotify(it.Kind, it.Url != "" ? it.Url : "-", it.Text)
            let q = it.QuietMin
            if q > 0 { Later(10) { self.StartQuiet(q) } }   // 等「上課了」那則講完再安靜（不然馬上被「我安靜待著」蓋掉）
        }
        if planFired.Count > 400 { planFired.Clear() }
    }

    // ================= 作業死線（3 天、1 天、3 小時、1 小時）=================
    func DeadlineTick() {
        if deadlines.Count == 0 { return }
        let now = SNowMs()
        let fire = List<Deadline>()
        var top = -1
        var changed = false
        var i = deadlines.Count - 1
        while i >= 0 {
            let d: Deadline = deadlines[i]
            i -= 1
            let left = Double(d.Due - now) / 60000.0
            if left < -60 { deadlines.RemoveAt(i + 1); changed = true; continue }
            var f = -1
            var s = d.Stage
            while s < World.DueStages.count { if left <= Double(World.DueStages[s]) { f = s }; s += 1 }
            if f < 0 { continue }
            d.Stage = f + 1; changed = true
            if left <= 0 { continue }     // 已經截止了：不再叫
            fire.Add(d); top = Math.Max(top, f)
        }
        if changed { SaveDeadlines() }
        if fire.Count == 0 { return }
        fire.Sort { (a: Deadline, b: Deadline) -> Int in a.Due.CompareTo(b.Due) }
        var text: String
        if fire.Count == 1 { text = DeadlineText(fire[0], top, now) }
        else {
            var parts: [String] = []
            var j = 0
            while j < fire.Count && j < 3 { parts.append("「" + World.Short(fire[j].Title, 14) + "」" + DueWhen(fire[j].Due)); j += 1 }
            text = "有 " + String(fire.Count) + " 份作業快截止了：" + string.Join("、", parts) + (fire.Count > 3 ? "…" : "")
        }
        let ids = List<String>()
        for d in fire { ids.Add(d.Id) }
        deadlineNotes[text] = ids
        App.Log("deadline stage " + String(top) + ": " + text)
        OnNotify(top >= 3 ? "deadline-hot" : "deadline", fire[0].Url ?? "-", text)
    }

    // C#：s[n-1] 是高代理字（emoji 的前半）就少切一個，不要把 emoji 切成兩半
    static func Short(_ s0: String!, _ n0: Int) -> String {
        let s: String = s0 ?? ""
        var n = n0
        if s.Length <= n { return s }
        let u = Array(s.utf16)
        if n >= 1 && UTF16.isLeadSurrogate(u[n - 1]) { n -= 1 }   // mac: char.IsHighSurrogate(s[n - 1])，直接看 UTF-16
        return s.Substring(0, n) + "…"
    }
    static let WeekDays: [String] = ["日", "一", "二", "三", "四", "五", "六"]

    // 今天 23:59／明天 23:59／11/20（五）23:59
    func DueWhen(_ due: Int) -> String {
        let d = World.FromUnixMs(due), n = SNow()
        let days = (d.Date - n.Date).Days
        let hm = d.ToString("HH:mm")
        if days == 0 { return (d.Hour < 6 ? "今天凌晨 " : "今天 ") + hm }
        if days == 1 { return (d.Hour < 6 ? "明天凌晨 " : "明天 ") + hm }
        return d.ToString("M/d") + "（" + World.WeekDays[d.DayOfWeek.rawValue] + "）" + hm
    }

    func DeadlineText(_ d: Deadline, _ stage: Int, _ now: Int) -> String {
        let name: String = "「" + d.Title + "」" + (d.Course != "" ? "（" + World.Short(d.Course, 12) + "）" : "")
        let left = Double(d.Due - now) / 60000.0
        let days = (World.FromUnixMs(d.Due).Date - SNow().Date).Days
        switch stage {
        case 0: return name + " " + DueWhen(d.Due) + " 截止，還有 " + String(Math.Max(1, days)) + " 天"
        case 1: return name + " " + DueWhen(d.Due) + " 截止！別忘了 📝"
        case 2: return name + " 再 " + String(Math.Max(1, CInt(Math.Ceiling(left / 60)))) + " 小時就截止了（" + World.FromUnixMs(d.Due).ToString("HH:mm") + "）"
        default: return name + (left < 55 ? " 剩 " + String(Math.Max(1, CInt(Math.Ceiling(left)))) + " 分鐘！" : " 剩不到 1 小時！") + World.FromUnixMs(d.Due).ToString("HH:mm") + " 截止，趕快交 📝"
        }
    }

    // 點了作業通知：打開作業頁／交了／等等再說
    func StudyClicked(_ p: Pet, _ n: Notice) -> Bool {
        if n.Kind != "deadline" && n.Kind != "deadline-hot" { return false }
        var ids: List<String>? = nil
        deadlineNotes.TryGetValue(n.Text ?? "", &ids)
        if App.Offscreen { p.Say("好～", 1.2); App.Log("deadline clicked (offscreen): " + (n.Text ?? "")); return true }
        let m = ContextMenuStrip()
        let url: String! = n.Url
        if url != nil { m.Items.Add("打開作業頁", nil) { self.OpenStudyUrl(p, url) } }
        if ids != nil && ids!.Count > 0 {
            let l: List<String> = ids!
            m.Items.Add(l.Count > 1 ? "都交了 ✓（不再提醒）" : "交了 ✓（不再提醒）", nil) { for id in l { self.MarkDone(id, true) }; p.Say("好棒！交了就輕鬆了 🎉", 2.2) }
        }
        m.Items.Add("等等再說", nil) { p.Say("好，時間快到會再叫你", 1.6) }
        ShowMenu(m, "作業", false)
        return true
    }

    func OpenStudyUrl(_ p: Pet, _ url: String) {
        if App.Offscreen { App.Log("open (offscreen, skipped): " + url); return }
        if World.OpenUrl(url) { p.Say("好～幫你打開了 👍", 1.4) }   // mac: Process.Start → NSWorkspace.open
        else { App.Log("open url: failed " + url); p.Say("打不開耶…", 1.4) }
    }

    // ================= 考試倒數 =================
    func SortExams() { exams.Sort { (a: Exam, b: Exam) -> Int in a.At.CompareTo(b.At) } }

    func AddExam(_ at: Int, _ name: String!, _ src: String, _ id: String!, _ say: Bool) {
        if !studyLoaded { LoadStudy() }
        let e = Exam()
        e.At = at; e.Name = string.IsNullOrEmpty(name) ? "考試" : World.OneLine(name); e.Src = src; e.Id = id ?? ("me-" + String(at))
        let n = SNow(), ed = World.FromUnixMs(at)
        // 加的時候已經過了今天倒數的時間：今天不再補講（剛剛才講過記住了）
        if examNudgeMin >= 0 && n.Hour * 60 + n.Minute >= examNudgeMin { e.LastDaily = n.ToString("yyyyMMdd") }
        let eid: String = e.Id
        exams.RemoveAll { (x: Exam) -> Bool in x.Id == eid }
        exams.Add(e)
        SortExams(); SaveExams()
        if !say { return }
        PushState()
        let days = (ed.Date - n.Date).Days
        let left = days <= 0 ? "就是今天" : (days == 1 ? "就是明天" : "還有 " + String(days) + " 天")
        let tail = examNudgeMin >= 0 && days >= 2 ? "。每天 " + World.Hm(examNudgeMin) + " 幫你倒數" : ""
        Lead().Say("📚 記住了：" + e.Name + "，" + ed.ToString("M/d HH:mm") + "，" + left + tail, 3.2)
    }

    func DelExam(_ id: String) {
        let e0 = exams.Find { (x: Exam) -> Bool in x.Id == id }
        if e0 == nil { return }
        let e: Exam = e0!
        exams.Remove(e)
        if e.Src == "ics" { MarkDone(id, false) }   // 行事曆上的：下次同步也別再加回來
        SaveExams(); PushState()
        Lead().Say("取消考試倒數：" + e.Name, 1.8)
    }

    // 7 天內有考試：專注改叫「讀書 25 分鐘 📚」
    func ExamNear() -> Bool {
        if !studyLoaded { LoadStudy() }
        let now = SNowMs()
        for e in exams { if e.At > now && e.At - now <= 7 * 24 * 3600000 { return true } }
        return false
    }

    // 早上那一則：07:30（考試比 08:30 早就提前到考前一小時）
    static func MorningAt(_ exam: DateTime) -> DateTime {
        let m = exam.Date.AddHours(7.5)
        return exam.AddHours(-1) < m ? exam.AddHours(-1) : m
    }

    func ExamTick() {
        if exams.Count == 0 { return }
        let n = SNow()
        let now = World.UnixMs(n)
        let changed = exams.RemoveAll { (x: Exam) -> Bool in now > x.At + 3 * 3600000 } > 0   // 考完 3 小時就收掉
        if changed { SaveExams() }
        if StudyBusy() || StudyIdle() > 120 { return }          // 安靜、專注、分享螢幕、你不在：等一下再講（當天都還會補）
        let today = n.ToString("yyyyMMdd")
        let nowMin = n.Hour * 60 + n.Minute
        var morning: Exam! = nil, before: Exam! = nil
        let daily = List<Exam>()
        for e in exams {
            let ed = World.FromUnixMs(e.At)
            let days = (ed.Date - n.Date).Days
            if days == 0 && !e.Morning && now < e.At && n >= World.MorningAt(ed) { if morning == nil { morning = e } }
            else if days == 1 && !e.DayBefore && examNudgeMin >= 0 && nowMin >= examNudgeMin { if before == nil { before = e } }
            else if days >= 2 && days <= 14 && e.LastDaily != today && examNudgeMin >= 0 && nowMin >= examNudgeMin { daily.Add(e) }
        }
        let l: Pet = Lead()
        if morning != nil {
            morning.Morning = true; morning.LastDaily = today; SaveExams()
            let t = World.ExamPrefix(l.P.Id) + "今天 " + World.FromUnixMs(morning.At).ToString("HH:mm") + "「" + morning.Name + "」，加油！🍀 准考證、文具、學生證帶了嗎？"
            App.Log("exam morning: " + morning.Name)
            l.Notify(t, nil, 1, false, false)
            for o in OutPets() { if o !== l { o.React() } }
            return
        }
        if before == nil && daily.Count == 0 { return }
        var parts: [String] = []
        for e in daily { e.LastDaily = today; parts.append("離「" + e.Name + "」還有 " + String((World.FromUnixMs(e.At).Date - n.Date).Days) + " 天") }
        var text = parts.count > 0 ? string.Join("、", parts) + " 📚 " + World.ExamTail(l.P.Id) : ""
        if before != nil {
            // 明天就考：這則優先，其他的倒數接在後面一起講
            before.DayBefore = true; before.LastDaily = today
            text = World.ExamPrefix(l.P.Id) + "明天 " + World.FromUnixMs(before.At).ToString("HH:mm") + " 就是「" + before.Name + "」了！重點再看一次，今晚早點睡 💤" + (parts.count > 0 ? "（" + string.Join("、", parts) + "）" : "")
        }
        SaveExams()
        App.Log("exam nudge: " + text)
        StudyNudge(l, text)
    }

    // 倒數提醒：點泡泡就開始讀書（番茄鐘）
    func StudyNudge(_ l: Pet, _ text: String) {
        let nt = Notice(); nt.Kind = "exam"; nt.Text = ""; nt.Pri = 1; nt.NextRound = true; nt.By = l; nt.Expire = Now + 120
        current = nt
        l.SetClickableBubble(true)
        l.Notify(text, "點我開始讀書 " + String(focusMin) + " 分鐘", 1, false, false)
    }

    static func ExamPrefix(_ id: String) -> String {
        let cu = World.CuStudy(id, "x_exam_prefix", nil, nil, nil); if cu != nil { return cu! }   // 自己做的公仔（53_custom.swift）
        switch id {
        case "spidey": return "蜘蛛感應："
        case "po", "tinky": return "Eh-oh! "
        case "stitch": return "ih! "
        case "hangyodon": return "英雄報告："
        case "dipsy": return "嘿，"
        case "laalaa": return "啦啦～"
        default: break
        }
        return id.StartsWith("pk") ? "皮克敏報告：" : ""
    }

    static func ExamTail(_ id: String) -> String {
        let cu = World.CuStudy(id, "x_exam_tail", nil, nil, nil); if cu != nil { return cu! }
        switch id {
        case "po": return "小波陪你讀書！"
        case "stitch": return "史迪仔幫你翻書！ih!"
        case "hangyodon": return "讀書的你才是真正的英雄"
        case "tinky": return "丁丁陪你讀～"
        case "dipsy": return "讀一點，很酷。"
        case "laalaa": return "邊讀邊唱～啦啦"
        default: break
        }
        return id.StartsWith("pk") ? "皮克敏幫你搬課本！" : "今天讀一點？"
    }

    // ================= 熬夜提醒（預設 01:00 起；02:00、03:00 再講；06:00 結束；離開電腦 15 分鐘就當你睡了）=================
    func LateTick() {
        if !lateOn || lateStartMin < 0 { return }
        let n = SNow()
        let m = n.Hour * 60 + n.Minute
        let sh = (m + 720) % 1440, st = (lateStartMin + 720) % 1440, end = (6 * 60 + 720) % 1440   // 以中午當一天的開始，跨半夜好算
        if sh < st || sh >= end { return }
        let key = n.AddHours(-12).ToString("yyyyMMdd")
        if key != lateKey { lateKey = key; lateLevel = -1; lateAsleep = false; SaveLate() }
        if lateAsleep { return }
        let idle = StudyIdle()
        if lateLevel >= 0 && idle >= 15 * 60 { lateAsleep = true; SaveLate(); App.Log("latenight: idle, stop for tonight"); return }
        let want = Math.Min(2, (sh - st) / 60)
        if want <= lateLevel || idle > 120 { return }          // 你不在電腦前：等你回來
        if StudyBusy() { return }                              // 安靜、專注、分享螢幕：不吵
        lateLevel = want; SaveLate()
        let l: Pet = Lead()
        let text = World.LateNightLine(l.P.Id, want, n.ToString("H:mm")) + LateExtra(n)
        App.Log("latenight " + String(want) + ": " + text)
        if want == 0 { l.WakeIfSleep(); l.Say(text, 8) }
        else {
            l.Notify(text, nil, 1, false, false)
            if want == 2 { for o in OutPets() { if o !== l { o.React() } } }
        }
    }

    // 還在趕作業／明天有考試：補一句
    func LateExtra(_ n: DateTime) -> String {
        let now = World.UnixMs(n)
        for d in deadlines {
            if d.Due > now && d.Due - now <= 8 * 3600000 { return "（還在趕「" + World.Short(d.Title, 12) + "」嗎？交完就去睡）" }
        }
        for e in exams {
            if e.At > now && e.At - now <= 14 * 3600000 { return "（" + World.FromUnixMs(e.At).ToString("H:mm") + " 還有「" + World.Short(e.Name, 12) + "」，睡飽比熬夜有用）" }
        }
        return ""
    }

    static func LateNightLine(_ id: String, _ lv: Int, _ hm: String) -> String {
        let cu = World.CuStudy(id, "x_late" + String(Math.Max(0, Math.Min(2, lv))), hm, nil, nil); if cu != nil { return cu! }
        var a: [String]
        switch id {
        case "spidey": a = ["已經 " + hm + " 了…蜘蛛也要睡覺的，今天先到這裡？🌙", hm + " 了。熬夜的英雄明天會變殭屍，存檔去睡吧", hm + "！！蜘蛛感應：你真的該睡了 😴 剩下的明天再做"]
        case "po": a = ["嗚…" + hm + " 了，小波好睏…你也去睡覺覺好不好 🌙", hm + " 了！太陽寶寶都睡好久了，關電腦吧～", hm + " 了…小波撐不住了，一起去睡嘛 😴"]
        case "stitch": a = [hm + " 了…史迪仔想睡了，你也睡 🌙", hm + "！ih! 睡覺！明天再玩！", hm + "！！再不睡史迪仔要拔電源線了喔 😴"]
        case "hangyodon": a = [hm + " 了…我在泡泡裡都快睡著了，你也早點休息 🌙", hm + " 了，英雄也要睡飽才能拯救世界", hm + " 了！真的該睡了…這不是冷笑話 😴"]
        case "tinky": a = [hm + " 了…丁丁抱著袋袋想睡覺覺 🌙", hm + " 了！天線寶寶說：該睡覺囉～", hm + " 了…丁丁跌坐在枕頭上了，你也去睡 😴"]
        case "dipsy": a = [hm + "。很晚了，帽子拉低，該睡了 🌙", hm + "。熬夜不酷，睡覺比較酷。", hm + "。真的，去睡。😴"]
        case "laalaa": a = [hm + " 了…拉拉唱搖籃曲給你聽～啦…啦… 🌙", hm + " 了！球球都睡了，你也睡吧～", hm + " 了…啦…（打哈欠）一起去睡嘛 😴"]
        default:
            if id.StartsWith("pk") { a = [hm + " 了…皮克敏都回洋蔥睡了 🌙", hm + " 了，夜晚很危險，快回基地睡覺！", hm + " 了！！再不睡天就亮了 😴"] }
            else { a = ["已經 " + hm + " 了，今天先到這裡好嗎？早點休息 🌙", hm + " 了，明天會很累喔，存檔去睡吧", hm + " 了！真的該睡了 😴"] }
        }
        return a[Math.Max(0, Math.Min(2, lv))]
    }

    // ================= 通知（Priority／Flavor／OnNotify／Deliver 會來問）=================
    static func StudyPriority(_ kind: String) -> Int {
        switch kind {
        case "class", "class-now", "exam-soon", "exam-now", "deadline-hot": return 2
        case "deadline", "event", "event-now": return 1
        default: break
        }
        return -1
    }

    // 上課、考試、行程跟開會一樣：安靜時還是冒泡泡，敲玻璃走會議的冷卻
    static func MeetingLike(_ kind: String) -> Bool { return kind.StartsWith("meeting") || kind.StartsWith("class") || kind.StartsWith("exam-") || kind.StartsWith("event") }

    static func StudyFlavor(_ id: String, _ kind: String) -> String! {
        let keys: [String] = ["class", "class-now", "exam-soon", "exam-now", "event", "event-now", "deadline", "deadline-hot"]
        let i = keys.firstIndex(of: kind) ?? -1
        if i < 0 { return nil }
        var a: [String]
        switch id {
        case "po": a = ["🎒 小波提醒你上課：", "🎒 上課囉！Eh-oh!", "📚 要考試了，小波幫你加油：", "📚 考試！小波陪你：", "等一下有事喔：", "時間到囉：", "📝 小波提醒你寫作業：", "📝 嗚～快截止了："]
        case "stitch": a = ["🎒 ih! 要上課：", "🎒 上課！快去！", "📚 要考試！ih-ih!", "📚 考試！史迪仔幫你集氣：", "等等有事！", "開始了！", "📝 ih! 作業：", "📝 ih-ih-ih! 快截止："]
        case "hangyodon": a = ["🎒 英雄提醒：要上課了", "🎒 上課時間到了：", "📚 英雄報告：要考試了", "📚 考試開始，你就是英雄：", "等一下有行程喔：", "行程開始了：", "📝 英雄提醒你：", "📝 交給我這個英雄…快截止了："]
        case "tinky": a = ["🎒 丁丁提醒你上課：", "🎒 上課囉！Eh-oh!", "📚 要考試了，丁丁幫你加油：", "📚 考試！丁丁陪你：", "等一下有事喔：", "時間到囉：", "📝 魔法袋裡有作業：", "📝 哎喲！快截止了："]
        case "dipsy": a = ["🎒 要上課了：", "🎒 上課了，走吧：", "📚 要考試了，冷靜：", "📚 考試開始，酷：", "等等有事：", "開始了：", "📝 作業：", "📝 快截止了，帽子扶好："]
        case "laalaa": a = ["🎒 拉拉提醒你上課：", "🎒 上課囉！啦～", "📚 要考試了，拉拉幫你加油：", "📚 考試！啦啦加油：", "等一下有事喔：", "時間到囉：", "📝 拉拉提醒你寫作業：", "📝 啦！快截止了："]
        case "spidey": a = ["🎒 要上課囉：", "🎒 上課時間！", "📚 蜘蛛感應！要考試了：", "📚 考試開始！", "等一下有行程：", "行程開始了：", "📝 作業提醒：", "📝 蜘蛛感應！快截止了："]
        default: a = ["🎒 要上課囉：", "🎒 上課時間！", "📚 要考試了：", "📚 考試開始！", "等一下有行程：", "行程開始了：", "📝 作業提醒：", "📝 快截止了："]
        }
        return a[i]
    }

    // ================= 搶課（Ticket 的 Kind＝course）=================
    static func CourseLine(_ id: String, _ stage: Int, _ t: Ticket) -> String {
        let cu = World.CuStudy(id, "x_course" + String(Math.Max(0, Math.Min(4, stage))), nil, t.Name, String(t.Lead / 60) + " 小時"); if cu != nil { return cu! }
        let h = String(t.Lead / 60) + " 小時", n: String = t.Name
        var a: [String]
        switch id {
        case "spidey": a = ["🎓 " + n + " 還有 " + h + "開放選課！先登入、志願序排好", "🎓 " + n + " 再 30 分鐘開放，選課頁先開好、課號抄好", "🎓 " + n + " 剩 10 分鐘！蜘蛛感應全開", "🎓 準備！手指放在加選按鈕上", "🎓 開放了！！快加選！Thwip!"]
        case "po": a = ["🎓 " + n + " 還有 " + h + "開放選課！先登入、志願排好喔", "🎓 " + n + " 再 30 分鐘！課號先抄好，小波陪你等", "🎓 " + n + " 剩 10 分鐘！好緊張～", "🎓 準備！深呼吸～", "🎓 開放了！！衝衝衝！"]
        case "stitch": a = ["🎓 " + n + " 還有 " + h + "開放選課！先登入！ih!", "🎓 " + n + " 30 分鐘！課號抄好，史迪仔幫你顧著", "🎓 " + n + " 10 分鐘！ih-ih-ih!", "🎓 準備！史迪仔也準備好了", "🎓 開放了！！衝啊！"]
        case "hangyodon": a = ["🎓 " + n + " 還有 " + h + "開放選課！先登入、志願排好", "🎓 " + n + " 30 分鐘後開放，英雄陪你等", "🎓 " + n + " 剩 10 分鐘！英雄出動準備", "🎓 準備！這次一定選到！", "🎓 開放了！！祝你選到！"]
        case "tinky": a = ["🎓 " + n + " 還有 " + h + "開放選課！先登入喔", "🎓 " + n + " 再 30 分鐘！丁丁陪你等", "🎓 " + n + " 剩 10 分鐘！魔法袋準備好了", "🎓 準備！深呼吸～", "🎓 開放了！！衝衝衝！"]
        case "dipsy": a = ["🎓 " + n + " 還有 " + h + "開放選課，先登入", "🎓 " + n + " 30 分鐘後開放，課號抄好", "🎓 " + n + " 剩 10 分鐘，帽子戴好", "🎓 準備。冷靜，酷。", "🎓 開放了！！嘿！"]
        case "laalaa": a = ["🎓 " + n + " 還有 " + h + "開放選課！先登入喔", "🎓 " + n + " 再 30 分鐘！拉拉唱歌陪你等", "🎓 " + n + " 剩 10 分鐘！好緊張～", "🎓 準備！啦…啦…", "🎓 開放了！！衝啊～啦！"]
        default:
            if id.StartsWith("pk") { a = ["🎓 " + n + " 還有 " + h + "開放選課！先登入、志願排好", "🎓 " + n + " 再 30 分鐘，皮克敏排好隊了", "🎓 " + n + " 剩 10 分鐘！全員集合！", "🎓 準備！吹哨子準備～", "🎓 開放了！！全員衝鋒！"] }
            else { a = ["🎓 " + n + " 還有 " + h + "開放選課！先登入、志願序排好", "🎓 " + n + " 再 30 分鐘開放，選課頁先開好", "🎓 " + n + " 剩 10 分鐘！", "🎓 準備！手指放在加選按鈕上", "🎓 開放了！！快加選！"] }
        }
        return a[Math.Max(0, Math.Min(4, stage))]
    }

    // 倒數徽章上的是搶課就畫學士帽
    func BadgeIsCourse() -> Bool {
        let now = World.UnixMs(DateTime.Now)
        for t in tickets {
            let ms = t.At - now
            if (ms > 0 && ms <= 10 * 60000) || (ms <= 0 && ms > -60000) { return t.Kind == "course" }
        }
        return false
    }

    // ================= 選單（小幫手）=================
    func AddStudyMenus(_ items: ToolStripItemCollection) {
        if !studyLoaded { LoadStudy() }
        AddTicketMenus(items, "course")
        items.Add("考試倒數…", nil) { self.ShowExamForm() }
        let now = SNowMs()
        if exams.Count > 0 {
            let my = ToolStripMenuItem("我的考試（" + String(exams.Count) + "）")
            for e in exams {
                let ee = e
                let days = (World.FromUnixMs(e.At).Date - SNow().Date).Days
                let left = days <= 0 ? "今天" : (days == 1 ? "明天" : "還有 " + String(days) + " 天")
                my.DropDownItems.Add(World.FromUnixMs(e.At).ToString("MM/dd HH:mm") + "　" + World.Short(e.Name, 16) + "　" + left + "（點一下取消）", nil) { self.DelExam(ee.Id) }
            }
            items.Add(my)
        }
        if !haveSchool { items.Add("學校行事曆（上課、作業提醒）…", nil) { self.ShowStudySettings() }; return }
        let week: List<Deadline> = deadlines.FindAll { (d: Deadline) -> Bool in d.Due > now && d.Due - now <= 7 * 24 * 3600000 }
        let wk = ToolStripMenuItem("這週要交的（" + String(week.Count) + "）")
        if week.Count == 0 { let none = ToolStripMenuItem("這週沒有要交的 🎉"); none.Enabled = false; wk.DropDownItems.Add(none) }
        for d in week {
            let dd = d
            let it = ToolStripMenuItem(DueWhen(d.Due) + "　" + World.Short(d.Title, 16) + (d.Course != "" ? "［" + World.Short(d.Course, 10) + "］" : ""))
            if d.Url != nil { it.DropDownItems.Add("打開作業頁", nil) { self.OpenStudyUrl(self.Lead(), dd.Url) } }
            it.DropDownItems.Add("交了 ✓（不再提醒）", nil) { self.MarkDone(dd.Id, true); self.Lead().Say("好棒！「" + World.Short(dd.Title, 12) + "」交了 🎉", 2.2) }
            wk.DropDownItems.Add(it)
        }
        items.Add(wk)
    }

    // ================= 今天的小結 =================
    // 這週（週一起）的番茄數；跟今天一樣就不另外講
    static func WeekTomatoNote(_ today: Int) -> String {
        let d = DateTime.Now.Date
        let back = (d.DayOfWeek.rawValue + 6) % 7
        var week = 0
        var i = 0
        while i <= back {
            var v = 0; _ = int.TryParse(World.ReadText("tomato-" + d.AddDays(-i).ToString("yyyyMMdd") + ".txt"), &v)
            week += v
            i += 1
        }
        return week > today ? "（這週 " + String(week) + " 顆）" : ""
    }

    func StudyWrapParts(_ parts: List<String>) {
        if !studyLoaded { LoadStudy() }
        if Day("classes") > 0 { parts.Add("上了 " + String(Day("classes")) + " 堂課") }
        let now = SNowMs()
        var n = 0
        for d in deadlines { if d.Due > now && d.Due - now <= 7 * 24 * 3600000 { n += 1 } }
        if n > 0 { parts.Add("這週還有 " + String(n) + " 份作業要交") }
        for e in exams {
            if e.At <= now { continue }
            let days = (World.FromUnixMs(e.At).Date - SNow().Date).Days
            if days >= 1 && days <= 14 { parts.Add("離「" + World.Short(e.Name, 10) + "」還有 " + String(days) + " 天") }
            break
        }
    }

    // ================= 小視窗：考試倒數、讀書小幫手設定 =================
    func ShowExamForm() {
        if App.Offscreen { return }
        if examForm == nil || examForm.IsDisposed { examForm = ExamForm(self, Lead().P.Accent) }
        let c: Point = Cursor.Position
        let wa: Rectangle = WA(Double(c.X), Double(c.Y))
        examForm.StartPosition = FormStartPosition.Manual
        examForm.Location = Point(Math.Max(wa.Left, Math.Min(wa.Right - examForm.Width, c.X - examForm.Width / 2)), Math.Max(wa.Top, Math.Min(wa.Bottom - examForm.Height, c.Y - examForm.Height - 10)))
        examForm.Show()
        ActivateForm(examForm)
        examForm.FocusFirst()
        let ef: ExamForm = examForm
        Later(0.2) { if ef.Visible { self.ActivateForm(ef); ef.FocusFirst() } }
    }

    func ShowStudySettings() {
        if !studyLoaded { LoadStudy() }
        if studyForm == nil || studyForm.IsDisposed { studyForm = StudySettingsForm(self) }
        let wa: Rectangle = App.Offscreen ? screens[0].WorkingArea : Screen.FromPoint(Cursor.Position).WorkingArea
        studyForm.Location = Point(wa.Left + (wa.Width - studyForm.Width) / 2, wa.Top + Math.Max(0, (wa.Height - studyForm.Height) / 2))
        studyForm.Show()
        if App.Offscreen { return }
        ActivateForm(studyForm)
        let sf: StudySettingsForm = studyForm
        Later(0.2) { if !sf.IsDisposed && sf.Visible { self.ActivateForm(sf) } }
    }

    // 設定視窗讀寫用
    func StudyUrls() -> [String] { return lock(schoolUrls) { schoolUrls.ToArray() } }
    var ClassRemind: Int { return classRemind }
    var ClassAutoQuiet: Bool { return classAutoQuiet }
    var LateOn: Bool { return lateOn }
    var LateStart: Int { return lateStartMin }
    var ExamNudge: Int { return examNudgeMin }
    func FromVsCode(_ key: String) -> Bool { return vsKeys.Contains(key) }
    func SchoolStatus() -> String {
        if !haveSchool { return "還沒有學校行事曆" }
        var week = 0; let now = SNowMs()
        for d in deadlines { if d.Due > now && d.Due - now <= 7 * 86400000 { week += 1 } }
        return (schoolStatus != "" ? schoolStatus + "；" : (lastScan == nil ? "更新中…；" : "")) + "這週 " + String(week) + " 份作業"
    }
    func ApplyStudySettings(_ urls: List<String>, _ remind: Int, _ autoQuiet: Bool, _ late: Bool, _ lateStart: Int, _ nudge: Int) {
        if !vsKeys.Contains("urls") {
            lock(schoolUrls) {
                schoolUrls.Clear()
                for u0 in urls { let u = World.NormUrl(u0); if u != nil && !schoolUrls.Contains(u!) { schoolUrls.Add(u!) } }
            }
        }
        if !vsKeys.Contains("remind") && remind > 0 { classRemind = Math.Min(120, remind) }
        if !vsKeys.Contains("autoquiet") { classAutoQuiet = autoQuiet }
        if !vsKeys.Contains("late") { lateOn = late; if lateStart >= 0 { lateStartMin = lateStart } }
        if !vsKeys.Contains("nudge") { examNudgeMin = nudge }
        haveSchool = schoolUrls.Count > 0 || testFeeds.Count > 0
        SaveStudyConfig()
        fetchNow = true; replan = true
        App.Log("study settings: urls=" + String(schoolUrls.Count) + " remind=" + String(classRemind) + " late=" + (lateOn ? World.Hm(lateStartMin) : "off") + " nudge=" + World.Hm(examNudgeMin))
        Lead().Say(schoolUrls.Count > 0 ? "🎒 記住了！上課前、作業截止前都會叫你" : "好～設定存好了", 2.4)
    }

    func StudySnap(_ g: Graphics) { if studyForm != nil && !studyForm.IsDisposed && studyForm.VVisible { studyForm.PaintTo(g) } }
}

extension Pet {
    // 搶課倒數徽章上的小學士帽（跟搶票的票券同一個位置、同樣大小）
    static func DrawCapIcon(_ g: Graphics, _ x0: Double, _ y0: Double, _ w: Double, _ k: Double, _ hot: Bool) {
        let was = g.SmoothingMode
        g.SmoothingMode = SmoothingMode.AntiAlias
        // 斜看的方帽：扁扁的菱形帽頂、底下一圈帽身、右邊垂一條流蘇
        do {
            let board = SolidBrush(Color.FromArgb(0xFF, 0xD8, 0x4A))
            let cap = SolidBrush(Color.FromArgb(0xC8, 0x8A, 0x22))
            g.FillPolygon(cap, [PointF(x0 + 2.0 * k, y0 + 3.0 * k), PointF(x0 + w - 2.0 * k, y0 + 3.0 * k), PointF(x0 + w - 2.4 * k, y0 + 6.0 * k), PointF(x0 + 2.4 * k, y0 + 6.0 * k)])
            g.FillPolygon(board, [PointF(x0 - 0.6 * k, y0 + 2.4 * k), PointF(x0 + w / 2, y0 + 0.4 * k), PointF(x0 + w + 0.6 * k, y0 + 2.4 * k), PointF(x0 + w / 2, y0 + 4.2 * k)])
        }
        do {
            let tassel = Pen(hot ? Color.White : Color.FromArgb(0xF0, 0x5A, 0x4A), Math.Max(1.2, 0.9 * k))
            g.DrawLine(tassel, x0 + w / 2, y0 + 2.3 * k, x0 + w - 0.2 * k, y0 + 2.9 * k)
            g.DrawLine(tassel, x0 + w - 0.2 * k, y0 + 2.9 * k, x0 + w - 0.2 * k, y0 + 6.4 * k)
        }
        g.SmoothingMode = was
    }
}

// 「考試倒數…」的小視窗（跟「搶票提醒…」同一個樣子）
class ExamForm: Form {
    var w: World
    let name = TextBox(), time = TextBox()
    let date = DateTimePicker()
    let hint = Label()
    init(_ w: World, _ accent: Color) {
        self.w = w
        super.init()
        Text = "📚 考試倒數"
        FormBorderStyle = FormBorderStyle.FixedToolWindow
        ShowInTaskbar = false; TopMost = true; MaximizeBox = false; MinimizeBox = false
        BackColor = Color.FromArgb(0xFF, 0xFB, 0xF4)
        Font = WorldC_Font("Microsoft JhengHei UI", 10)
        AutoScaleMode = AutoScaleMode.Dpi
        ClientSize = Size(360, 200)
        let y0 = 12
        AddLabel("什麼考試？（例如：微積分期末考）", y0); name.Location = Point(14, y0 + 22); name.Width = 332; Controls.Add(name)
        AddLabel("考試日期與開始時間", y0 + 56)
        date.Format = DateTimePickerFormat.Custom; date.CustomFormat = "yyyy-MM-dd"; date.Location = Point(14, y0 + 78); date.Width = 150; Controls.Add(date)
        time.Location = Point(176, y0 + 78); time.Width = 80; time.Text = "09:00"; Controls.Add(time)
        let tip = Label(); tip.Text = "考前兩週每天倒數、前一天晚上和當天早上提醒"; tip.Location = Point(14, y0 + 110); tip.AutoSize = true; tip.ForeColor = Color.FromArgb(0x80, 0x70, 0x60); Controls.Add(tip)
        let ok = Button(); ok.Text = "好，幫我倒數"; ok.Location = Point(206, y0 + 138); ok.Size = Size(140, 34)
        ok.FlatStyle = FlatStyle.Flat; ok.BackColor = accent; ok.ForeColor = Color.White; ok.FlatAppearance.BorderSize = 0
        ok.Click = { [unowned self] in self.Submit() }
        Controls.Add(ok)
        hint.Location = Point(14, y0 + 146); hint.AutoSize = true; hint.ForeColor = Color.FromArgb(0xB0, 0x40, 0x40); Controls.Add(hint)
        AcceptButton = ok
        KeyPreview = true
        KeyDown = { [unowned self] (e: KeyEventArgs) in if e.KeyCode == Keys.Escape { self.Hide() } }
        FormClosing = { [unowned self] (e: FormClosingEventArgs) in if e.CloseReason == CloseReason.UserClosing { e.Cancel = true; self.Hide() } }
    }

    func FocusFirst() { NSApp.activate(ignoringOtherApps: true); name.Select(); name.Focus() }

    func AddLabel(_ s: String, _ y: Int) { let l = Label(); l.Text = s; l.Location = Point(14, y); l.AutoSize = true; Controls.Add(l) }

    func Submit() {
        var t = DateTime.Now
        let tm = time.Text.Trim().Replace("：", ":")
        if name.Text.Trim() == "" { hint.Text = "什麼考試呢？"; name.Focus(); return }
        if !DateTime.TryParse(date.Value.ToString("yyyy-MM-dd") + " " + tm, &t) { hint.Text = "時間看不懂，例如 09:00"; return }
        if t < DateTime.Now { hint.Text = "這個時間已經過了喔"; return }
        let ms = World.UnixMs(t)
        w.AddExam(ms, name.Text.Trim(), "me", nil, true)
        name.Text = ""; hint.Text = ""
        Hide()
    }
}

// mac: 多行的 NSTextField 按 Enter 換行（C# 的 AcceptsReturn）；打字照樣通知 TextBox
final class StudyUrlsDelegate: NSObject, NSTextFieldDelegate {
    weak var box: TextBox?
    init(_ b: TextBox) { box = b }
    func controlTextDidChange(_ obj: Notification) { box?._userEdited() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { textView.insertNewlineIgnoringFieldEditor(nil); return true }
        return false
    }
}

// ================= 讀書小幫手設定（公仔小屋 →「讀書小幫手設定…」）：跟第一次設定同一套像素樣子 =================
// 學校行事曆網址（一行一個）、上課前幾分鐘、上課中自動安靜、熬夜提醒（幾點開始）、考試倒數幾點講。
// VS Code 推過來的那幾項會鎖住並寫「由 VS Code 設定」。
class StudySettingsForm: Form {
    let w: World
    let d: Double
    let U: Int
    let urls = TextBox(), remind = TextBox(), lateAt = TextBox(), nudge = TextBox()
    var autoQuiet = false, lateOn = false
    var hoverId = "", err = ""
    var titleF: FontT! = nil, labF: FontT! = nil, subF: FontT! = nil, btnF: FontT! = nil, boxF: FontT! = nil
    var VVisible = false
    let hits = Dict<String, Rectangle>()
    static let Locked = Color.FromArgb(0xF1, 0xE8, 0xD8)   // 由 VS Code 管的欄位：灰一點、不能改
    static let Open = Color.FromArgb(0xFF, 0xFD, 0xF7)
    var urlsDelegate: StudyUrlsDelegate? = nil

    init(_ w: World) {
        self.w = w
        d = Double(w.S) / 4.0
        U = Math.Max(2, CInt(Math.Round(2 * d)))
        super.init()
        Text = "公仔櫃・讀書小幫手設定"
        FormBorderStyle = FormBorderStyleT.FixedSingle
        MaximizeBox = false; MinimizeBox = false
        ShowInTaskbar = true; TopMost = true
        StartPosition = FormStartPosition.Manual
        BackColor = Pix.Cream
        DoubleBuffered = true
        titleF = FontT("Microsoft JhengHei UI", 12, FontStyle.Bold)
        labF = FontT("Microsoft JhengHei UI", 10.5, FontStyle.Bold)
        subF = FontT("Microsoft JhengHei UI", 8.5, FontStyle.Bold)
        btnF = FontT("Microsoft JhengHei UI", 11, FontStyle.Bold)
        boxF = FontT("Consolas", 9.5)
        ClientSize = SizeT(Sc(600), Sc(600))
        KeyPreview = true
        KeyDown = { [unowned self] (e: KeyEventArgs) in if e.KeyCode == Keys.Escape { self.Close() } }
        urls.Multiline = true   // mac: 要在 Controls.Add（建 NSTextField）之前設，才會是多行
        for t in [urls, remind, lateAt, nudge] {
            t.BackColor = StudySettingsForm.Open; t.ForeColor = Pix.TextC
            t.Font = t === urls ? boxF! : FontT("Microsoft JhengHei UI", 10.5, FontStyle.Bold)
            Controls.Add(t)
            CuMaker.Borderless(t, StudySettingsForm.Open)   // mac: BorderStyle.None
        }
        // urls：ScrollBars.Vertical、WordWrap = false、AcceptsReturn = true
        if let tf = urls.tf { tf.cell?.wraps = false; tf.cell?.isScrollable = true; let dg = StudyUrlsDelegate(urls); tf.delegate = dg; urlsDelegate = dg }
        for t in [remind, lateAt, nudge] { t.tf?.alignment = .center }   // HorizontalAlignment.Center
        let x = Sc(36)
        urls.Bounds = Rectangle(x + U, Sc(118) + U, ClientSize.Width - 2 * x - 2 * U, Sc(96) - 2 * U)
        remind.Bounds = Field(Sc(330), Sc(66))
        lateAt.Bounds = Field(Sc(406), Sc(66))
        nudge.Bounds = Field(Sc(468), Sc(66))
        Reload()
    }

    func Sc(_ v: Int) -> Int { return CInt(Math.Round(Double(v) * d)) }
    func Field(_ y: Int, _ wd: Int) -> Rectangle { let h = Sc(26); return Rectangle(ClientSize.Width - Sc(36) - wd + 2 * U, y + (h - Sc(18)) / 2, wd - 4 * U, Sc(18)) }

    func Reload() {
        urls.Text = string.Join("\r\n", w.StudyUrls())
        remind.Text = String(w.ClassRemind)
        autoQuiet = w.ClassAutoQuiet; lateOn = w.LateOn
        lateAt.Text = (w.LateStart / 60).ToString("00") + ":" + (w.LateStart % 60).ToString("00")
        nudge.Text = w.ExamNudge < 0 ? "" : (w.ExamNudge / 60).ToString("00") + ":" + (w.ExamNudge % 60).ToString("00")
        urls.ReadOnly = w.FromVsCode("urls"); remind.ReadOnly = w.FromVsCode("remind")
        lateAt.ReadOnly = w.FromVsCode("late"); nudge.ReadOnly = w.FromVsCode("nudge")
        for t in [urls, remind, lateAt, nudge] {
            t.BackColor = t.ReadOnly ? StudySettingsForm.Locked : StudySettingsForm.Open
            t.tf?.backgroundColor = t.BackColor.ns   // mac: TextBox 的 BackColor 不會自己套到 NSTextField
        }
        err = ""
        Invalidate()
    }

    // ---- 離屏測試模式：不真的顯示，snap 時畫到虛擬螢幕上（輸入框另外畫）----
    override func SetVisibleCore(_ value: Bool) {
        if App.Offscreen { VVisible = value; super.SetVisibleCore(false); return }
        super.SetVisibleCore(value)
    }
    func PaintTo(_ g: Graphics) {
        let cs = ClientSize
        if cs.Width <= 0 || cs.Height <= 0 { return }
        let b = Bitmap(cs.Width, cs.Height, PixelFormat.Format24bppRgb)
        do {
            let gg = Graphics.FromImage(b)
            OnPaint(PaintEventArgs(gg, Rectangle(0, 0, cs.Width, cs.Height)))
            for t in [urls, remind, lateAt, nudge] {
                do { let bg = SolidBrush(t.BackColor); gg.FillRectangle(bg, t.Bounds) }
                let s = t.Multiline ? t.Text : t.Text
                let fl: TextFormatFlags = t.Multiline ? [TextFormatFlags.Left, TextFormatFlags.Top, TextFormatFlags.NoPrefix] : Pix.Mid
                TextRenderer.DrawText(gg, s, t.Font, t.Bounds, t.ForeColor, fl)
            }
        }
        g.DrawImageUnscaled(b, Left, Top)
    }

    func TestSet(_ field: String, _ value: String) {
        if field == "urls" { urls.Text = value.Replace(" ", "\r\n") }
        else if field == "remind" { remind.Text = value }
        else if field == "late" { lateAt.Text = value }
        else if field == "nudge" { nudge.Text = value }
        else if field == "autoquiet" { autoQuiet = value == "1" }
        else if field == "lateon" { lateOn = value == "1" }
        Invalidate()
    }

    func Save() {
        let list = List<String>()
        let seps: [Character] = ["\r", "\n", " ", ","]
        for line in urls.Text.Split(seps, StringSplitOptions.RemoveEmptyEntries) {
            var s = line.Trim()
            if s.StartsWith("webcal", StringComparison.OrdinalIgnoreCase) { s = "https" + s.Substring(s.IndexOf("://", StringComparison.Ordinal) < 0 ? 6 : s.IndexOf("://", StringComparison.Ordinal)) }
            if !s.StartsWith("https://", StringComparison.OrdinalIgnoreCase) { err = "網址要 https:// 或 webcal:// 開頭：" + (s.Length > 30 ? s.Substring(0, 30) + "…" : s); Invalidate(); return }
            list.Add(s)
        }
        var rm = 0
        if !int.TryParse(remind.Text.Trim(), &rm) || rm < 1 || rm > 120 { err = "上課前幾分鐘：打 1～120"; Invalidate(); return }
        let ls = StudySettingsForm.HmOf(lateAt.Text)
        if lateOn && ls < 0 { err = "熬夜提醒的時間看不懂，例如 01:00"; Invalidate(); return }
        let ng = nudge.Text.Trim() == "" ? -1 : StudySettingsForm.HmOf(nudge.Text)
        if nudge.Text.Trim() != "" && ng < 0 { err = "考試倒數的時間看不懂，例如 20:00（空白＝不要每天倒數）"; Invalidate(); return }
        w.ApplyStudySettings(list, rm, autoQuiet, lateOn, ls, ng)
        Close()
    }

    static func HmOf(_ s: String!) -> Int {
        let a = (s ?? "").Trim().Replace("：", ":").Split(":")
        var h = 0, m = 0
        if a.count == 2 && int.TryParse(a[0], &h) && int.TryParse(a[1], &m) && h >= 0 && h < 24 && m >= 0 && m < 60 { return h * 60 + m }
        return -1
    }

    func HitAt(_ p: Point) -> String { for kv in hits { if kv.Value.Contains(p) { return kv.Key } }; return "" }
    override func OnMouseMove(_ e: MouseEventArgs) {
        super.OnMouseMove(e)
        let h = HitAt(e.Location)
        if h != hoverId { hoverId = h; Cursor = h != "" ? Cursors.Hand : Cursors.Default; Invalidate() }
    }
    override func OnMouseUp(_ e: MouseEventArgs) {
        super.OnMouseUp(e)
        if e.Button != MouseButtons.Left { return }
        let h = HitAt(e.Location)
        if h == "save" { Save() }
        else if h == "cancel" { Close() }
        else if h == "autoquiet" && !w.FromVsCode("autoquiet") { autoQuiet = !autoQuiet; Invalidate() }
        else if h == "lateon" && !w.FromVsCode("late") { lateOn = !lateOn; Invalidate() }
    }

    override func OnPaint(_ e: PaintEventArgs) {
        let g = e.Graphics
        g.SmoothingMode = SmoothingMode.None
        hits.Clear()
        let W0 = ClientSize.Width, H0 = ClientSize.Height, F = 4 * U, crown = Sc(56), x = Sc(36)
        Pix.Wood(g, 0, 0, W0, H0, U, false, 23)
        Pix.Panel(g, F, crown, W0 - 2 * F, H0 - crown - F, U, false)
        let t = "讀書小幫手設定"
        let tw = Pix.TextW(t, titleF), plw = tw + 14 * U, plh = Sc(34)
        let pr = Rectangle((W0 - plw) / 2, (crown - plh) / 2 + U / 2, plw, plh)
        Pix.Plate(g, t, titleF, pr, U)
        Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.X - 9 * U, pr.Y + plh / 2 - 2 * U, U)
        Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.Right + 4 * U, pr.Y + plh / 2 - 2 * U, U)
        let brown = Pix.C(0x9A6338)

        // 學校行事曆
        DrawLabel(g, "🎒 學校行事曆（ICS 網址，一行一個）", x, Sc(70), labF, Pix.TextC)
        DrawLabel(g, w.FromVsCode("urls") ? "由 VS Code 設定（deskPals.schoolIcsUrl）" : "上課前提醒、上課中安靜；作業截止前 3 天、1 天、3 小時、1 小時提醒", x, Sc(94), subF, brown)
        Frame(g, Rectangle(x, Sc(118), W0 - 2 * x, Sc(96)), urls.ReadOnly)
        let how: [String] = [
            "Canvas／NTU COOL：行事曆 → 右邊「行事曆摘要」(Calendar Feed)",
            "Moodle：行事曆 → 匯入或匯出行事曆 → 匯出 → 取得行事曆網址",
            "Google Classroom、Google 日曆：日曆設定 →「iCal 格式的私密網址」" ]
        for i in 0..<how.count { DrawLabel(g, "・" + how[i], x, Sc(222) + i * Sc(18), subF, brown) }
        DrawLabel(g, w.SchoolStatus(), x, Sc(282), subF, Pix.C(0x3F8A30))

        Dots(g, x, Sc(312), W0 - 2 * x)
        // 上課
        DrawLabel(g, "上課、考試前幾分鐘提醒" + (remind.ReadOnly ? "（由 VS Code 設定）" : ""), x, Sc(330) + Sc(4), labF, remind.ReadOnly ? Pix.Dim : Pix.TextC)
        Frame(g, Rectangle(W0 - x - Sc(66), Sc(330), Sc(66), Sc(26)), remind.ReadOnly)
        Toggle(g, "autoquiet", "上課、考試時自動安靜到下課", autoQuiet, x, Sc(368), w.FromVsCode("autoquiet"))
        // 熬夜
        let lk = w.FromVsCode("late")
        Toggle(g, "lateon", "熬夜提醒：過了這個時間還在用電腦，就催你去睡", lateOn, x, Sc(406), lk)
        Frame(g, Rectangle(W0 - x - Sc(66), Sc(406), Sc(66), Sc(26)), lateAt.ReadOnly)
        DrawLabel(g, lk ? "由 VS Code 設定（deskPals.lateNightStart）" : "之後每一小時再講一次（最多三次）；你離開電腦、安靜、專注時不吵", x + Sc(30), Sc(436), subF, brown)
        // 考試
        DrawLabel(g, "考試倒數每天幾點講（空白＝不要）" + (nudge.ReadOnly ? "（由 VS Code 設定）" : ""), x, Sc(468) + Sc(4), labF, nudge.ReadOnly ? Pix.Dim : Pix.TextC)
        Frame(g, Rectangle(W0 - x - Sc(66), Sc(468), Sc(66), Sc(26)), nudge.ReadOnly)

        if err != "" { DrawLabel(g, err, x, Sc(506), subF, Pix.C(0xB04040)) }
        let by = H0 - Sc(64), bh = Sc(44)
        DrawButton(g, "cancel", "取消", Rectangle(Sc(30), by, Sc(130), bh), false)
        DrawButton(g, "save", "儲存", Rectangle(W0 - Sc(30) - Sc(160), by, Sc(160), bh), true)
    }

    func DrawLabel(_ g: Graphics, _ s: String, _ x: Int, _ y: Int, _ f: FontT, _ c: Color) { TextRenderer.DrawText(g, World.NoEmoji(s), f, PointT(x, y), c, [TextFormatFlags.NoPrefix, TextFormatFlags.NoPadding]) }

    // 輸入框的像素框（深木色外框、上面一條陰影）
    func Frame(_ g: Graphics, _ r: Rectangle, _ locked: Bool) {
        Pix.Round(g, locked ? Pix.Dim : Pix.C(0x8A6A4A), r.X, r.Y, r.Width, r.Height, U)
        Pix.Box(g, locked ? StudySettingsForm.Locked : Color.FromArgb(0xFF, 0xFD, 0xF7), r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U)
        Pix.Box(g, Pix.C(0xEAD7B4), r.X + U, r.Y + U, r.Width - 2 * U, U)
    }

    func Dots(_ g: Graphics, _ x: Int, _ y: Int, _ wd: Int) { var sx = x; while sx + U <= x + wd { Pix.Box(g, Pix.C(0xD8BF94), sx, y, U, U); sx += 3 * U } }

    // 像素勾勾開關（跟小屋選單的開關一樣：打勾＝開著）
    func Toggle(_ g: Graphics, _ id: String, _ text: String, _ on: Bool, _ x: Int, _ y: Int, _ locked: Bool) {
        let s = Sc(20)
        let r = Rectangle(x, y + (Sc(26) - s) / 2, s, s)
        Pix.Round(g, locked ? Pix.Dim : Pix.Ink, r.X, r.Y, s, s, U)
        Pix.Box(g, on ? Pix.C(0x5FB04A) : Color.FromArgb(0xFF, 0xFD, 0xF7), r.X + U, r.Y + U, s - 2 * U, s - 2 * U)
        if on { Pix.Mono(g, Pix.CHECK, Color.White, r.X + (s - 5 * U) / 2, r.Y + (s - 5 * U) / 2, U) }
        let tc = locked ? Pix.Dim : (hoverId == id ? Pix.C(0x8A5A2A) : Pix.TextC)
        DrawLabel(g, text + (locked && id != "lateon" ? "（由 VS Code 設定）" : ""), x + s + Sc(10), y + Sc(4), labF, tc)
        hits[id] = Rectangle(x, y, s + Sc(10) + Pix.TextW(World.NoEmoji(text), labF), Sc(26))
    }

    func DrawButton(_ g: Graphics, _ id: String, _ text: String, _ r: Rectangle, _ main: Bool) {
        let hot = hoverId == id
        let face = main ? (hot ? Pix.C(0xFFD36A) : Pix.C(0xF6C453)) : (hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0))
        let shade = main ? Pix.C(0xC8902C) : Pix.C(0xDCC6A2)
        Pix.Round(g, Pix.Ink, r.X, r.Y, r.Width, r.Height, U)
        Pix.Box(g, face, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U)
        Pix.Box(g, shade, r.X + U, r.Bottom - 3 * U, r.Width - 2 * U, 2 * U)
        Pix.Box(g, Pix.Mix(face, Color.White, 0.6), r.X + 2 * U, r.Y + U, r.Width - 4 * U, U)
        TextRenderer.DrawText(g, text, btnF, Rectangle(r.X, r.Y, r.Width, r.Height - 2 * U), Pix.TextC, Pix.Mid)
        hits[id] = r
    }
}
