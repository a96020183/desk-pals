// Desk Pals：讀書小幫手（學校行事曆的上課提醒和作業死線、搶課提醒、考試倒數、熬夜提醒、讀書統計）。
// 不分學生／上班族：每個功能有資料才會動（沒填學校行事曆就沒有上課／作業提醒；沒加考試就沒有倒數）。
// 桌面版自己就能用（不用 VS Code）：自己抓 ICS、自己解析、自己提醒；設定在公仔小屋的「讀書小幫手設定…」。
// 有 VS Code 的話，VS Code 設定（deskPals.schoolIcsUrl…）會從 pipe 推過來，以 VS Code 的為準（設定視窗顯示「由 VS Code 管理」）。
// desk-pals.ps1 會把 DeskPals.cs 和 DeskPals.*.cs 接在一起編譯；這個檔的 using 放在 namespace 裡面，接起來才合法。
// 刻意寫成 C# 5（不用 $"" / ?. / => 成員 / nameof），之後 Mac 版照著逐行移植。
//
// 掛在 DeskPals.cs 的地方（都只有一兩行）：TickInner → StudyTick()、OnMsg 的 default → StudyMsg()、
//   AddHelpers → AddStudyMenus()／ExamNear()、StartFocus／StopFocus → ExamNear()、Priority → StudyPriority()、
//   Flavor → StudyFlavor()、OnNotify／Deliver → MeetingLike()、NoticeClicked → StudyClicked()、
//   DailyWrap → WeekTomatoNote()／StudyWrapParts()、TicketLine → CourseLine()、DrawTicketBadge → BadgeIsCourse()／DrawCapIcon()、
//   HouseMenu →「讀書小幫手設定…」、Snap → StudySnap()。搶課跟搶票共用 DeskPals.cs 的 Ticket（Kind＝course）。
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
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.Diagnostics;
    using System.Drawing;
    using System.Drawing.Drawing2D;
    using System.Drawing.Imaging;
    using System.IO;
    using System.Text;
    using System.Text.RegularExpressions;
    using System.Threading;
    using System.Web.Script.Serialization;
    using System.Windows.Forms;

    // ================= ICS（行事曆）：解析＋重複規則展開（跟 practical.js 的 parseIcs／occurrences 同一套規則）=================
    class IcsTime { public long Utc; public int Y, M, D, H, Mi, S; public string Tz; public bool AllDay; }
    class IcsEvent
    {
        public string Uid = "", Summary = "", Location = "", Description = "", Url = "", Conf = "", Status = "", RRule = "", Categories = "";
        public IcsTime Start, End, RecurrenceId;
        public bool Declined;
        public readonly List<long> ExDates = new List<long>();
    }
    class IcsOcc { public string Uid, Summary, Link; public long Start, End; public IcsEvent Ev, Parent; }

    static class Ics
    {
        static readonly DateTime Epoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        static long Ms(DateTime utc) { return (long)(utc - Epoch).TotalMilliseconds; }

        // 常見的 IANA 時區 → Windows 時區（.NET Framework 只認 Windows 的名字；Outlook 匯出的本來就是 Windows 名字）
        static readonly Dictionary<string, string> IanaToWin = new Dictionary<string, string> {
            { "Asia/Taipei", "Taipei Standard Time" }, { "Asia/Hong_Kong", "China Standard Time" }, { "Asia/Shanghai", "China Standard Time" },
            { "Asia/Macau", "China Standard Time" }, { "Asia/Chongqing", "China Standard Time" }, { "Asia/Tokyo", "Tokyo Standard Time" },
            { "Asia/Seoul", "Korea Standard Time" }, { "Asia/Singapore", "Singapore Standard Time" }, { "Asia/Kuala_Lumpur", "Singapore Standard Time" },
            { "Asia/Manila", "Singapore Standard Time" }, { "Asia/Bangkok", "SE Asia Standard Time" }, { "Asia/Ho_Chi_Minh", "SE Asia Standard Time" },
            { "Asia/Jakarta", "SE Asia Standard Time" }, { "Asia/Kolkata", "India Standard Time" }, { "Asia/Dubai", "Arabian Standard Time" },
            { "Australia/Sydney", "AUS Eastern Standard Time" }, { "Australia/Melbourne", "AUS Eastern Standard Time" }, { "Australia/Brisbane", "E. Australia Standard Time" },
            { "Australia/Perth", "W. Australia Standard Time" }, { "Pacific/Auckland", "New Zealand Standard Time" },
            { "Europe/London", "GMT Standard Time" }, { "Europe/Dublin", "GMT Standard Time" }, { "Europe/Paris", "Romance Standard Time" },
            { "Europe/Berlin", "W. Europe Standard Time" }, { "Europe/Amsterdam", "W. Europe Standard Time" }, { "Europe/Zurich", "W. Europe Standard Time" },
            { "Europe/Rome", "W. Europe Standard Time" }, { "Europe/Madrid", "Romance Standard Time" }, { "Europe/Stockholm", "W. Europe Standard Time" },
            { "America/New_York", "Eastern Standard Time" }, { "America/Toronto", "Eastern Standard Time" }, { "America/Chicago", "Central Standard Time" },
            { "America/Denver", "Mountain Standard Time" }, { "America/Phoenix", "US Mountain Standard Time" }, { "America/Los_Angeles", "Pacific Standard Time" },
            { "America/Vancouver", "Pacific Standard Time" }, { "Pacific/Honolulu", "Hawaiian Standard Time" } };

        // 某時區的牆上時間 → UTC 毫秒。fixedOff：檔案裡 VTIMEZONE 沒有夏令時間的固定時差（分鐘）
        public static long WallToUtc(int y, int m, int d, int h, int mi, int s, string tz, Dictionary<string, int> fixedOff)
        {
            DateTime wall;
            try { wall = new DateTime(y, m, d, h, mi, s, DateTimeKind.Unspecified); } catch { return 0; }
            if (tz == null) return Ms(DateTime.SpecifyKind(wall, DateTimeKind.Local).ToUniversalTime());
            if (tz == "UTC" || tz == "Etc/UTC" || tz == "GMT" || tz == "Z") return Ms(DateTime.SpecifyKind(wall, DateTimeKind.Utc));
            int off;
            if (fixedOff != null && fixedOff.TryGetValue(tz, out off)) return Ms(DateTime.SpecifyKind(wall, DateTimeKind.Utc)) - off * 60000L;
            TimeZoneInfo z = FindZone(tz);
            if (z != null)
            {
                try { return Ms(TimeZoneInfo.ConvertTimeToUtc(wall, z)); }
                catch (ArgumentException) { try { return Ms(TimeZoneInfo.ConvertTimeToUtc(wall.AddHours(1), z)); } catch { } }   // 夏令時間跳過的那一小時
            }
            return Ms(DateTime.SpecifyKind(wall, DateTimeKind.Local).ToUniversalTime());
        }

        static readonly Dictionary<string, TimeZoneInfo> zoneCache = new Dictionary<string, TimeZoneInfo>();
        static TimeZoneInfo FindZone(string tz)
        {
            lock (zoneCache)
            {
                TimeZoneInfo z;
                if (zoneCache.TryGetValue(tz, out z)) return z;
                string id = tz.Trim('"');
                string win;
                if (IanaToWin.TryGetValue(id, out win)) id = win;
                try { z = TimeZoneInfo.FindSystemTimeZoneById(id); } catch { z = null; }
                zoneCache[tz] = z;
                return z;
            }
        }

        static readonly Regex TimeRe = new Regex(@"^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$");
        public static IcsTime ParseTime(string v, Dictionary<string, string> p, Dictionary<string, int> fixedOff)
        {
            Match m = TimeRe.Match((v ?? "").Trim());
            if (!m.Success) return null;
            IcsTime t = new IcsTime();
            t.Y = int.Parse(m.Groups[1].Value); t.M = int.Parse(m.Groups[2].Value); t.D = int.Parse(m.Groups[3].Value);
            if (m.Groups[4].Success) { t.H = int.Parse(m.Groups[4].Value); t.Mi = int.Parse(m.Groups[5].Value); t.S = int.Parse(m.Groups[6].Value); }
            string vt;
            t.AllDay = !m.Groups[4].Success || (p.TryGetValue("VALUE", out vt) && vt == "DATE");
            string tz;
            t.Tz = m.Groups[7].Success ? "UTC" : (p.TryGetValue("TZID", out tz) ? tz : null);
            t.Utc = WallToUtc(t.Y, t.M, t.D, t.H, t.Mi, t.S, t.Tz, fixedOff);
            return t;
        }

        static string Unesc(string s) { return Regex.Replace(Regex.Replace(s, @"\\[nN]", "\n"), @"\\([,;\\])", "$1"); }

        // owner：行事曆擁有者（Google 私密網址裡就有信箱）——他按了「不參加」的不提醒
        public static List<IcsEvent> Parse(string text, string owner, out string calName)
        {
            calName = "";
            owner = (owner ?? "").ToLowerInvariant();
            string[] lines = text.Replace("\r\n ", "").Replace("\r\n\t", "").Replace("\n ", "").Replace("\n\t", "").Split('\n');
            List<IcsEvent> events = new List<IcsEvent>();
            Dictionary<string, int> fixedOff = new Dictionary<string, int>();
            // 先看 VTIMEZONE：只有 STANDARD、沒有 DAYLIGHT 的時區（例如 Asia/Taipei）＝固定時差
            string tzid = null; int stdOff = 0; bool hasStd = false, hasDst = false, inStd = false;
            foreach (string raw in lines)
            {
                string line = raw.TrimEnd('\r');
                if (line == "BEGIN:VTIMEZONE") { tzid = null; hasStd = hasDst = false; continue; }
                if (line == "END:VTIMEZONE") { if (tzid != null && hasStd && !hasDst) fixedOff[tzid] = stdOff; tzid = null; continue; }
                if (line == "BEGIN:STANDARD") { inStd = true; hasStd = true; continue; }
                if (line == "END:STANDARD") { inStd = false; continue; }
                if (line == "BEGIN:DAYLIGHT") { hasDst = true; continue; }
                if (line.StartsWith("TZID:") && tzid == null) tzid = line.Substring(5).Trim();
                if (inStd && line.StartsWith("TZOFFSETTO:"))
                {
                    Match o = Regex.Match(line.Substring(11).Trim(), @"^([+-])(\d{2})(\d{2})");
                    if (o.Success) stdOff = (o.Groups[1].Value == "-" ? -1 : 1) * (int.Parse(o.Groups[2].Value) * 60 + int.Parse(o.Groups[3].Value));
                }
                if (line.StartsWith("X-WR-CALNAME:")) calName = Unesc(line.Substring(13)).Trim();
            }
            IcsEvent cur = null;
            foreach (string raw in lines)
            {
                string line = raw.TrimEnd('\r');
                if (line == "BEGIN:VEVENT") { cur = new IcsEvent(); continue; }
                if (line == "END:VEVENT") { if (cur != null) events.Add(cur); cur = null; continue; }
                if (cur == null) continue;
                int i = line.IndexOf(':');
                if (i < 0) continue;
                string left = line.Substring(0, i), value = line.Substring(i + 1);
                string[] parts = left.Split(';');
                Dictionary<string, string> p = new Dictionary<string, string>();
                for (int k = 1; k < parts.Length; k++) { int j = parts[k].IndexOf('='); if (j > 0) p[parts[k].Substring(0, j).ToUpperInvariant()] = parts[k].Substring(j + 1).Trim('"'); }
                switch (parts[0].ToUpperInvariant())
                {
                    case "UID": cur.Uid = value; break;
                    case "SUMMARY": cur.Summary = Unesc(value); break;
                    case "LOCATION": cur.Location = Unesc(value); break;
                    case "DESCRIPTION": cur.Description = Unesc(value); break;
                    case "URL": cur.Url = value.Trim(); break;
                    case "CATEGORIES": cur.Categories = Unesc(value); break;
                    case "X-GOOGLE-CONFERENCE": cur.Conf = value.Trim(); break;
                    case "STATUS": cur.Status = value.Trim().ToUpperInvariant(); break;
                    case "RRULE": cur.RRule = value.Trim(); break;
                    case "DTSTART": cur.Start = ParseTime(value, p, fixedOff); break;
                    case "DTEND": cur.End = ParseTime(value, p, fixedOff); break;
                    case "RECURRENCE-ID": cur.RecurrenceId = ParseTime(value, p, fixedOff); break;
                    case "ATTENDEE":
                        { string ps; if (owner != "" && value.ToLowerInvariant() == "mailto:" + owner && p.TryGetValue("PARTSTAT", out ps) && ps.ToUpperInvariant() == "DECLINED") cur.Declined = true; }
                        break;
                    case "EXDATE": foreach (string v in value.Split(',')) { IcsTime t = ParseTime(v, p, fixedOff); if (t != null) cur.ExDates.Add(t.Utc); } break;
                }
            }
            return events;
        }

        static readonly string[] DAYS = { "SU", "MO", "TU", "WE", "TH", "FR", "SA" };

        // 單次、DAILY／WEEKLY／MONTHLY（BYDAY、BYMONTHDAY）／YEARLY、INTERVAL、COUNT、UNTIL、EXDATE、單次改期（RECURRENCE-ID）、取消；全天的不展開
        public static List<IcsOcc> Occurrences(List<IcsEvent> events, long from, long to)
        {
            List<IcsOcc> outl = new List<IcsOcc>();
            Dictionary<string, IcsEvent> overrides = new Dictionary<string, IcsEvent>();
            foreach (IcsEvent e in events) if (e.RecurrenceId != null && e.Uid != "") overrides[e.Uid + "@" + e.RecurrenceId.Utc] = e;
            foreach (IcsEvent e in events)
            {
                if (e.Start == null || e.Start.AllDay || e.RecurrenceId != null) continue;
                if (e.RRule == "") { Push(outl, e, e.Start.Utc, null, from, to); continue; }
                Dictionary<string, string> r = new Dictionary<string, string>();
                foreach (string kv in e.RRule.Split(';')) { int j = kv.IndexOf('='); if (j > 0) r[kv.Substring(0, j).ToUpperInvariant()] = kv.Substring(j + 1); }
                string freq = Get(r, "FREQ");
                int interval = Math.Max(1, ToInt(Get(r, "INTERVAL"), 1));
                int count = Get(r, "COUNT") != "" ? ToInt(Get(r, "COUNT"), int.MaxValue) : int.MaxValue;
                long until = long.MaxValue;
                if (Get(r, "UNTIL") != "") { IcsTime u = ParseTime(Get(r, "UNTIL"), new Dictionary<string, string>(), null); if (u != null) until = u.Utc; }
                string[] byday = Get(r, "BYDAY") != "" ? Get(r, "BYDAY").Split(',') : null;
                List<int> bymd = null;
                if (Get(r, "BYMONTHDAY") != "") { bymd = new List<int>(); foreach (string x in Get(r, "BYMONTHDAY").Split(',')) bymd.Add(ToInt(x, 0)); }
                DateTime day0 = new DateTime(e.Start.Y, e.Start.M, e.Start.D);
                DateTime endDay = Epoch.AddMilliseconds(to).Date.AddDays(2);
                DateTime mon0 = day0.AddDays(-(((int)day0.DayOfWeek + 6) % 7));   // 起始那週的週一
                int n = 0;
                for (DateTime t = day0; t <= endDay && n < count; t = t.AddDays(1))
                {
                    int wd = (int)t.DayOfWeek;
                    bool ok = false;
                    if (freq == "DAILY") ok = ((int)Math.Round((t - day0).TotalDays)) % interval == 0 && (byday == null || HasDay(byday, wd));
                    else if (freq == "WEEKLY")
                    {
                        int weeks = (int)Math.Floor((t - mon0).TotalDays / 7);
                        ok = weeks % interval == 0 && (byday != null ? HasDay(byday, wd) : wd == (int)day0.DayOfWeek);
                    }
                    else if (freq == "MONTHLY")
                    {
                        int months = (t.Year - e.Start.Y) * 12 + (t.Month - e.Start.M);
                        if (months % interval == 0)
                        {
                            if (byday != null)
                            {
                                foreach (string b in byday)
                                {
                                    Match mm = Regex.Match(b.Trim(), @"^([+-]?\d+)?(\w\w)$");
                                    if (!mm.Success || mm.Groups[2].Value != DAYS[wd]) continue;
                                    if (!mm.Groups[1].Success) { ok = true; break; }
                                    int nth = int.Parse(mm.Groups[1].Value);
                                    if (nth > 0 && (t.Day + 6) / 7 == nth) { ok = true; break; }
                                    int dim = DateTime.DaysInMonth(t.Year, t.Month);
                                    if (nth < 0 && (dim - t.Day + 7) / 7 == -nth) { ok = true; break; }
                                }
                            }
                            else ok = bymd != null ? bymd.Contains(t.Day) : t.Day == e.Start.D;
                        }
                    }
                    else if (freq == "YEARLY") ok = (t.Year - e.Start.Y) % interval == 0 && t.Month == e.Start.M && t.Day == e.Start.D;
                    if (!ok) continue;
                    long startUtc = WallToUtc(t.Year, t.Month, t.Day, e.Start.H, e.Start.Mi, e.Start.S, e.Start.Tz, null);
                    if (e.Start.Tz != null && e.Start.Tz != "UTC") startUtc = e.Start.Utc + (startUtc - WallToUtc(e.Start.Y, e.Start.M, e.Start.D, e.Start.H, e.Start.Mi, e.Start.S, e.Start.Tz, null));   // 用同一套時區換算，固定時差的 VTIMEZONE 也對
                    if (startUtc > until) break;
                    n++;
                    if (e.ExDates.Contains(startUtc)) continue;
                    IcsEvent ov;
                    if (overrides.TryGetValue(e.Uid + "@" + startUtc, out ov)) { if (ov.Start != null) Push(outl, ov, ov.Start.Utc, e, from, to); continue; }
                    Push(outl, e, startUtc, null, from, to);
                }
            }
            outl.Sort(delegate(IcsOcc a, IcsOcc b) { return a.Start.CompareTo(b.Start); });
            return outl;
        }

        static string Get(Dictionary<string, string> r, string k) { string v; return r.TryGetValue(k, out v) ? v : ""; }
        static int ToInt(string s, int d) { int v; return int.TryParse(s, out v) ? v : d; }
        static bool HasDay(string[] byday, int wd) { foreach (string b in byday) { string x = b.Trim(); if (x.Length >= 2 && x.Substring(x.Length - 2) == DAYS[wd]) return true; } return false; }

        static void Push(List<IcsOcc> outl, IcsEvent e, long startUtc, IcsEvent parent, long from, long to)
        {
            if (e.Status == "CANCELLED" || e.Declined) return;
            if (startUtc < from || startUtc > to) return;
            IcsEvent src = e.End != null && e.Start != null ? e : (parent != null && parent.End != null && parent.Start != null ? parent : null);
            long len = src != null ? Math.Max(5 * 60000L, src.End.Utc - src.Start.Utc) : 30 * 60000L;
            IcsOcc o = new IcsOcc();
            o.Uid = e.Uid != "" ? e.Uid : e.Summary; o.Start = startUtc; o.End = startUtc + len;
            o.Summary = e.Summary != "" ? e.Summary : (parent != null && parent.Summary != "" ? parent.Summary : "（沒有標題）");
            o.Link = MeetLink(e); if (o.Link == "" && parent != null) o.Link = MeetLink(parent);
            o.Ev = e; o.Parent = parent;
            outl.Add(o);
        }

        static readonly Regex MeetRe = new Regex(@"https://(?:meet\.google\.com|[\w.-]*zoom\.us|teams\.microsoft\.com|teams\.live\.com)/[^\s""<>)]+", RegexOptions.IgnoreCase);
        public static string MeetLink(IcsEvent e)
        {
            if (e.Conf.StartsWith("https://")) return e.Conf;
            Match m = MeetRe.Match(e.Location + " " + e.Description + " " + e.Url);
            if (m.Success) return m.Value;
            return e.Url.StartsWith("https://") ? e.Url : "";
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
    class SchoolFeed { public string Url, Kind, Name, Base, Owner; public List<IcsEvent> Events; }
    class SchoolTimed { public string Id, Kind, Summary, Location, Link; public long Start, End; }
    class SchoolDue { public string Id, Title, Course, Url; public long Due; }
    class SchoolExam { public string Id, Name; public long At; }
    class SchoolScan { public List<SchoolTimed> Timed = new List<SchoolTimed>(); public List<SchoolDue> Dues = new List<SchoolDue>(); public List<SchoolExam> Exams = new List<SchoolExam>(); }
    class SchoolPlanItem { public long At; public string Kind, Url, Text, Key; public int QuietMin; }

    static class School
    {
        // ECMAScript：\b、\w 只看英數字（中文字旁邊的 due 也算一個字），跟 JS 一樣
        const RegexOptions O = RegexOptions.IgnoreCase | RegexOptions.ECMAScript;
        static readonly Regex DueWord = new Regex(@"作業|功課|截止|到期|繳交|交件|提交|期限|deadline|\bdue\b|assignment|homework|\bhw\s*\d|submission|\bcloses?\b", O);
        static readonly Regex DueHard = new Regex(@"截止|到期|繳交|交件|deadline|\bdue\b|\bcloses?\b", O);   // 有長度的單次行程也算死線（例如自己排的「報告繳交截止」）
        static readonly Regex Opens = new Regex(@"\bopens?\b|開放作答|開始作答|開放繳交|開始繳交|開放提交", O);  // Moodle「… opens」：開始，不是截止
        static readonly Regex ExamWord = new Regex(@"期中考|期末考|小考|考試|段考|會考|測驗|\bexams?\b|midterm|final exam|\bquiz\b", O);
        static readonly Regex ClassWord = new Regex(@"上課|課程|講堂|教室|實驗|演習|助教課|\blecture\b|\blab\b|\btutorial\b|\bseminar\b|\bclass\b|\bsection\b|[館樓院]\s*\d\d", O);   // 課號（MATH4006）不算：Canvas 每個活動都帶課號
        static readonly Regex AssignLink = new Regex(@"/courses/\d+/assignments/\d+|#assignment_\d+|classroom\.google\.com/(?:u/\d+/)?c/[^\s/]+/(?:a|sa|mc)/|/mod/(?:assign|quiz|workshop)/view\.php", O);

        public static string KindOf(string url, string text)
        {
            string u = url ?? "";
            try { u = Uri.UnescapeDataString(u); } catch { }
            if (Regex.IsMatch(u, @"/feeds/calendars/", O) || Regex.IsMatch(text, @"^UID:event-(?:sub-)?assignment-|^UID:event-calendar-event-", RegexOptions.Multiline)) return "canvas";
            if (Regex.IsMatch(u, @"/calendar/export_execute\.php", O) || Regex.IsMatch(text, @"^PRODID:.*moodle", RegexOptions.Multiline | RegexOptions.IgnoreCase)) return "moodle";
            if (Regex.IsMatch(u, @"classroom[^/@]*@group\.calendar\.google\.com", O) || Regex.IsMatch(text, @"^X-WR-CALNAME:.*classroom", RegexOptions.Multiline | RegexOptions.IgnoreCase)) return "classroom";
            return "generic";
        }

        public static SchoolFeed Feed(string url, string text)
        {
            SchoolFeed f = new SchoolFeed();
            f.Url = url ?? ""; f.Kind = KindOf(url, text);
            Match b = Regex.Match(f.Url, @"^(https://.+?)/calendar/export_execute\.php", RegexOptions.IgnoreCase);
            f.Base = b.Success ? b.Groups[1].Value : "";
            Match ow = Regex.Match(f.Url, @"/ical/([^/]+)/");
            try { f.Owner = ow.Success ? Uri.UnescapeDataString(ow.Groups[1].Value) : ""; } catch { f.Owner = ""; }
            string name;
            f.Events = Ics.Parse(text, f.Owner, out name);
            f.Name = name;
            return f;
        }

        // assignment｜exam｜class｜event｜skip
        public static string Classify(IcsEvent e, SchoolFeed feed, IcsEvent parent)
        {
            if (e.Start == null || e.Status == "CANCELLED") return "skip";
            string sum = e.Summary != "" ? e.Summary : (parent != null ? parent.Summary : "");
            bool allDay = e.Start.AllDay;
            bool zero = !allDay && (e.End == null || e.End.Utc - e.Start.Utc <= 60000);   // Canvas／Moodle 的截止＝開始和結束同一刻
            bool recurring = e.RRule != "" || e.RecurrenceId != null || (parent != null && parent.RRule != "");
            string linky = e.Url + " " + e.Description + " " + e.Location;
            if (feed.Kind == "canvas" && Regex.IsMatch(e.Uid, @"^event-(?:sub-)?assignment-", O)) return "assignment";
            if (feed.Kind == "classroom") return Opens.IsMatch(sum) ? "skip" : "assignment";   // Classroom 課程日曆只放作業截止
            if (Opens.IsMatch(sum) && (zero || allDay)) return "skip";
            if (AssignLink.IsMatch(e.Url) || ((zero || allDay) && AssignLink.IsMatch(linky))) return "assignment";
            if ((zero || allDay) && DueWord.IsMatch(sum)) return "assignment";
            if (!allDay && !recurring && DueHard.IsMatch(sum) && !ExamWord.IsMatch(sum)) return "assignment";
            if (!allDay && ExamWord.IsMatch(sum)) return "exam";
            if (zero && (feed.Kind == "moodle" || DueWord.IsMatch(e.Description))) return "assignment";
            if (allDay) return "skip";          // 放假、校慶這類全天事件不提醒
            if (recurring || ClassWord.IsMatch((sum + " " + e.Location).Replace("助教室", ""))) return "class";
            return "event";
        }

        static string Clean(string s) { return Regex.Replace(s ?? "", @"[\r\n]+", " ").Trim(); }

        static void Title(IcsEvent e, SchoolFeed feed, out string title, out string course)
        {
            title = Clean(e.Summary); course = "";
            if (title == "") title = "（沒有標題）";
            Match m;
            if (feed.Kind == "canvas" && (m = Regex.Match(title, @"^(.*\S)\s*\[([^\]]+)\]$")).Success) { title = m.Groups[1].Value; course = m.Groups[2].Value; }
            if (feed.Kind == "moodle")
            {
                string t = Regex.Replace(Regex.Replace(title, @"\s+(?:is due to be graded|is due|closes|due)$", "", RegexOptions.IgnoreCase), @"\s*(?:截止|到期)$", "");
                if (t != "") title = t;
                course = Clean(e.Categories);
            }
            if (feed.Kind == "classroom") course = feed.Name;
        }

        static string FirstHttps(string text, bool httpToo)
        {
            Match m = Regex.Match(text, httpToo ? @"https?://[^\s""<>)\\]+" : @"https://[^\s""<>)\\]+", RegexOptions.IgnoreCase);
            return m.Success ? m.Value : "";
        }

        static string AssignUrl(IcsEvent e, SchoolFeed feed, long due)
        {
            string u = Regex.IsMatch(e.Url, @"^https?://", RegexOptions.IgnoreCase) ? e.Url.Trim() : "";
            if (feed.Kind == "canvas" && u != "")
            {
                // 行事曆頁 → 直接到作業頁
                Match ctx = Regex.Match(u, @"include_contexts=course_(\d+)"), a = Regex.Match(u, @"#assignment_(\d+)");
                Uri uri;
                if (ctx.Success && a.Success && Uri.TryCreate(u, UriKind.Absolute, out uri)) return uri.Scheme + "://" + uri.Authority + "/courses/" + ctx.Groups[1].Value + "/assignments/" + a.Groups[1].Value;
                return u;
            }
            string text = e.Description + " " + e.Location + " " + e.Url;
            Match cr = Regex.Match(text, @"https://classroom\.google\.com/[^\s""<>)\\]+", RegexOptions.IgnoreCase);
            if (cr.Success) return cr.Value;
            if (u != "") return u;
            if (feed.Kind == "moodle" && feed.Base != "") return feed.Base + "/calendar/view.php?view=day&time=" + (due / 1000);
            if (feed.Kind == "classroom") return "https://classroom.google.com/";
            return FirstHttps(text, false);
        }

        static string EventLink(IcsEvent e, IcsEvent parent)
        {
            string m = Ics.MeetLink(e);
            if (m == "" && parent != null) m = Ics.MeetLink(parent);
            if (m != "") return m;
            return FirstHttps(e.Url + " " + e.Location + " " + e.Description, true);
        }

        static string SafeId(string s) { return Regex.Replace(s ?? "", @"\s+", "_"); }
        // Canvas 的活動標題後面帶「 [課程代碼]」：講出來改成「（課程代碼）」
        static string Nice(string s, SchoolFeed feed) { s = Clean(s); return feed.Kind == "canvas" ? Regex.Replace(s, @"\s*\[([^\]]+)\]$", "（$1）") : s; }

        // 接下來 26 小時的課／考試／行程、14 天內的作業死線、120 天內的考試
        public static SchoolScan Scan(List<SchoolFeed> feeds, long now)
        {
            long dueTo = now + 14 * 86400000L, examTo = now + 120 * 86400000L, timedTo = now + 26 * 3600000L;
            SchoolScan r = new SchoolScan();
            HashSet<string> seen = new HashSet<string>();
            foreach (SchoolFeed feed in feeds)
            {
                // 全天的作業（Canvas 23:59 截止、Classroom 沒設時間）：當天 23:59 截止
                foreach (IcsEvent e in feed.Events)
                {
                    if (e.Start == null || !e.Start.AllDay || e.RRule != "" || e.RecurrenceId != null || e.Declined) continue;
                    if (Classify(e, feed, null) != "assignment") continue;
                    AddDue(r, seen, e, feed, Ics.WallToUtc(e.Start.Y, e.Start.M, e.Start.D, 23, 59, 0, null, null), now, dueTo);
                }
                foreach (IcsOcc o in Ics.Occurrences(feed.Events, now - 5 * 60000L, examTo))
                {
                    string kind = Classify(o.Ev, feed, o.Parent);
                    if (kind == "assignment") AddDue(r, seen, o.Ev, feed, o.Start, now, dueTo);
                    if (kind == "exam" && o.Start > now) { SchoolExam x = new SchoolExam(); x.Id = SafeId(o.Uid + "@" + o.Start); x.At = o.Start; x.Name = Nice(o.Summary, feed); r.Exams.Add(x); }
                    if ((kind == "class" || kind == "exam" || kind == "event") && o.Start <= timedTo)
                    {
                        string loc = Clean(o.Ev.Location != "" ? o.Ev.Location : (o.Parent != null ? o.Parent.Location : ""));
                        SchoolTimed t = new SchoolTimed();
                        t.Id = SafeId(o.Uid + "@" + o.Start); t.Kind = kind; t.Start = o.Start; t.End = o.End; t.Summary = Nice(o.Summary, feed);
                        t.Location = Regex.IsMatch(loc, @"^https?:", RegexOptions.IgnoreCase) ? "" : loc; t.Link = EventLink(o.Ev, o.Parent);
                        r.Timed.Add(t);
                    }
                }
            }
            r.Dues.Sort(delegate(SchoolDue a, SchoolDue b) { return a.Due.CompareTo(b.Due); });
            r.Exams.Sort(delegate(SchoolExam a, SchoolExam b) { return a.At.CompareTo(b.At); });
            return r;
        }

        static void AddDue(SchoolScan r, HashSet<string> seen, IcsEvent e, SchoolFeed feed, long due, long now, long dueTo)
        {
            if (due <= now || due > dueTo) return;
            string title, course;
            Title(e, feed, out title, out course);
            if (!seen.Add(title + "|" + due)) return;   // 同一份作業出現在兩個行事曆
            SchoolDue d = new SchoolDue();
            d.Id = SafeId((e.Uid != "" ? e.Uid : title) + "@" + due); d.Due = due; d.Title = title; d.Course = course; d.Url = AssignUrl(e, feed, due);
            r.Dues.Add(d);
        }

        // 上課／考試／行程的提醒：課前 N 分鐘＋開始時；上課、考試自動安靜（最多 4 小時）；同一時間的合成一則（考試優先）
        public static List<SchoolPlanItem> Plan(List<SchoolTimed> timed, long now, int before, bool autoQuiet)
        {
            Dictionary<long, List<SchoolTimed>> groups = new Dictionary<long, List<SchoolTimed>>();
            List<long> order = new List<long>();
            foreach (SchoolTimed t in timed)
            {
                List<SchoolTimed> g;
                if (!groups.TryGetValue(t.Start, out g)) { g = new List<SchoolTimed>(); groups[t.Start] = g; order.Add(t.Start); }
                g.Add(t);
            }
            List<SchoolPlanItem> plan = new List<SchoolPlanItem>();
            foreach (long start in order)
            {
                List<SchoolTimed> g = groups[start];
                string kind = "event", link = "", loc = "", key = "";
                long end = start;
                List<string> names = new List<string>();
                foreach (SchoolTimed t in g)
                {
                    if (Rank(t.Kind) > Rank(kind)) kind = t.Kind;
                    if (link == "") link = t.Link;
                    if (loc == "") loc = t.Location;
                    end = Math.Max(end, t.End);
                    names.Add(t.Summary);
                    key += (key == "" ? "" : "+") + t.Id;
                }
                string name = names.Count > 1 ? names[0] + "、" + names[1] + (names.Count > 2 ? " 等 " + names.Count + " 個" : "") : names[0];
                string hhmm = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMilliseconds(start).ToLocalTime().ToString("HH:mm");
                string where = loc != "" ? "・" + (loc.Length > 16 ? loc.Substring(0, 16) + "…" : loc) : "";
                string pre = kind == "class" ? hhmm + " " + name + where + "（" + before + " 分鐘後）"
                    : kind == "exam" ? hhmm + " " + name + where + "（" + before + " 分鐘後），文具帶好，加油！"
                    : hhmm + " " + name + where + "（" + before + " 分鐘後）";
                string go = kind == "class" ? name + (link != "" ? "（點我打開）" : "")
                    : kind == "exam" ? name + "，加油！🍀"
                    : name + (link != "" ? "（點我打開）" : "");
                string kPre = kind == "class" ? "class" : (kind == "exam" ? "exam-soon" : "event");
                string kNow = kind == "class" ? "class-now" : (kind == "exam" ? "exam-now" : "event-now");
                long at1 = start - before * 60000L;
                if (at1 > now) plan.Add(Item(at1, kPre, link, pre, 0, key + "@" + start + "-pre"));
                if (start > now)
                {
                    int q = autoQuiet && kind != "event" ? (int)Math.Min(240, Math.Round((end - start) / 60000.0)) : 0;
                    plan.Add(Item(start, kNow, link, go, Math.Max(0, q), key + "@" + start + "-now"));
                }
            }
            plan.Sort(delegate(SchoolPlanItem a, SchoolPlanItem b) { return a.At.CompareTo(b.At); });
            return plan;
        }
        static int Rank(string k) { return k == "exam" ? 3 : (k == "class" ? 2 : 1); }
        static SchoolPlanItem Item(long at, string kind, string url, string text, int q, string key)
        {
            SchoolPlanItem p = new SchoolPlanItem(); p.At = at; p.Kind = kind; p.Url = url; p.Text = text; p.QuietMin = q; p.Key = key;
            return p;
        }
    }

    partial class World
    {
        // ---------- 測試用時鐘、閒置（離屏測試才會用到）----------
        TimeSpan studyShift = TimeSpan.Zero;
        double studyIdleFake = -1;
        DateTime SNow() { return DateTime.Now + studyShift; }
        long SNowMs() { return UnixMs(SNow()); }
        double StudyIdle() { return studyIdleFake >= 0 ? studyIdleFake : W.IdleSeconds(); }

        class Exam { public long At; public string Name, Id, Src; public string LastDaily = ""; public bool DayBefore, Morning; }
        class Deadline { public string Id, Title, Course, Url; public long Due; public int Stage; }
        readonly List<Exam> exams = new List<Exam>();
        readonly List<Deadline> deadlines = new List<Deadline>();
        readonly HashSet<string> studyDone = new HashSet<string>();
        readonly Dictionary<string, List<string>> deadlineNotes = new Dictionary<string, List<string>>();   // 通知的字 → 哪幾份作業（點了可以標成交了）
        bool studyLoaded, haveSchool;
        double studyNext;
        static readonly int[] DueStages = { 3 * 24 * 60, 24 * 60, 180, 60 };   // 截止前 3 天、1 天、3 小時、1 小時

        // ---------- 設定（study-config.txt；VS Code 推過來的那幾項以 VS Code 為準）----------
        readonly List<string> schoolUrls = new List<string>();
        int classRemind = 10;
        bool classAutoQuiet = true, lateOn = true;
        int lateStartMin = 60, examNudgeMin = 20 * 60;      // 熬夜提醒幾點開始、考試倒數幾點講（-1＝關掉）
        string workCal = "";                                // VS Code 開會提醒用的行事曆：學校這邊就不重複提醒
        readonly HashSet<string> vsKeys = new HashSet<string>();
        string lateKey = ""; int lateLevel = -1; bool lateAsleep;

        // ================= 存檔 =================
        void LoadStudy()
        {
            studyLoaded = true;
            exams.Clear(); deadlines.Clear(); studyDone.Clear();
            foreach (string line in ReadText("exams.txt").Split('\n'))
            {
                string[] a = line.TrimEnd('\r').Split('\t');
                long at;
                if (a.Length < 6 || !long.TryParse(a[0], out at)) continue;
                Exam e = new Exam(); e.At = at; e.Src = a[1]; e.LastDaily = a[2];
                e.DayBefore = a[3].Length > 0 && a[3][0] == '1'; e.Morning = a[3].Length > 1 && a[3][1] == '1';
                e.Id = a[4]; e.Name = a[5];
                exams.Add(e);
            }
            foreach (string line in ReadText("deadlines.txt").Split('\n'))
            {
                string[] a = line.TrimEnd('\r').Split('\t');
                long due; int stage;
                if (a.Length < 6 || !long.TryParse(a[0], out due) || !int.TryParse(a[1], out stage)) continue;
                Deadline d = new Deadline(); d.Due = due; d.Stage = stage; d.Id = a[2]; d.Url = a[3] == "-" ? null : a[3]; d.Course = a[4] == "-" ? "" : a[4]; d.Title = a[5];
                deadlines.Add(d);
            }
            foreach (string line in ReadText("study-done.txt").Split('\n')) if (line.Trim() != "") studyDone.Add(line.Trim());
            LoadStudyConfig();
            haveSchool = schoolUrls.Count > 0;
            string[] lk = ReadText("late.txt").Split('\t');
            if (lk.Length == 3) { lateKey = lk[0]; int.TryParse(lk[1], out lateLevel); lateAsleep = lk[2] == "1"; }
        }

        void LoadStudyConfig()
        {
            lock (schoolUrls)
            {
                schoolUrls.Clear(); vsKeys.Clear();
                foreach (string line in ReadText("study-config.txt").Split('\n'))
                {
                    string l = line.Trim();
                    int i = l.IndexOf('=');
                    if (i <= 0) continue;
                    string k = l.Substring(0, i), v = l.Substring(i + 1).Trim();
                    switch (k)
                    {
                        case "url": { string u = NormUrl(v); if (u != null && !schoolUrls.Contains(u)) schoolUrls.Add(u); } break;
                        case "remind": { int n; if (int.TryParse(v, out n) && n > 0) classRemind = Math.Min(120, n); } break;
                        case "autoquiet": classAutoQuiet = v != "0"; break;
                        case "late": { int m = ParseHm(v); if (m >= 0) lateStartMin = m; } break;
                        case "lateon": lateOn = v != "0"; break;
                        case "nudge": examNudgeMin = v == "off" ? -1 : (ParseHm(v) >= 0 ? ParseHm(v) : examNudgeMin); break;
                        case "workcal": workCal = v; break;
                        case "vs": foreach (string x in v.Split(',')) if (x.Trim() != "") vsKeys.Add(x.Trim()); break;
                    }
                }
            }
        }

        void SaveStudyConfig()
        {
            StringBuilder sb = new StringBuilder();
            lock (schoolUrls) foreach (string u in schoolUrls) sb.Append("url=" + u + "\n");
            sb.Append("remind=" + classRemind + "\nautoquiet=" + (classAutoQuiet ? 1 : 0) + "\nlate=" + Hm(lateStartMin) + "\nlateon=" + (lateOn ? 1 : 0) + "\nnudge=" + Hm(examNudgeMin) + "\n");
            if (workCal != "") sb.Append("workcal=" + workCal + "\n");
            if (vsKeys.Count > 0) sb.Append("vs=" + string.Join(",", new List<string>(vsKeys).ToArray()) + "\n");
            WriteText("study-config.txt", sb.ToString());
        }

        // https://…、webcal://…（當成 https）；其他不收
        static string NormUrl(string s)
        {
            s = (s ?? "").Trim();
            if (s.StartsWith("webcal://", StringComparison.OrdinalIgnoreCase)) s = "https://" + s.Substring(9);
            else if (s.StartsWith("webcals://", StringComparison.OrdinalIgnoreCase)) s = "https://" + s.Substring(10);
            Uri u;
            if (!s.StartsWith("https://", StringComparison.OrdinalIgnoreCase) || !Uri.TryCreate(s, UriKind.Absolute, out u)) return null;
            return s;
        }

        void SaveExams()
        {
            StringBuilder sb = new StringBuilder();
            foreach (Exam e in exams)
                sb.Append(e.At + "\t" + e.Src + "\t" + e.LastDaily + "\t" + (e.DayBefore ? "1" : "0") + (e.Morning ? "1" : "0") + "\t" + e.Id + "\t" + OneLine(e.Name) + "\n");
            WriteText("exams.txt", sb.ToString());
        }

        void SaveDeadlines()
        {
            StringBuilder sb = new StringBuilder();
            foreach (Deadline d in deadlines)
                sb.Append(d.Due + "\t" + d.Stage + "\t" + d.Id + "\t" + (d.Url ?? "-") + "\t" + (d.Course == "" ? "-" : OneLine(d.Course)) + "\t" + OneLine(d.Title) + "\n");
            WriteText("deadlines.txt", sb.ToString());
        }

        void SaveLate() { WriteText("late.txt", lateKey + "\t" + lateLevel + "\t" + (lateAsleep ? "1" : "0")); }

        static string OneLine(string s) { return (s ?? "").Replace("\t", " ").Replace("\r", " ").Replace("\n", " ").Trim(); }

        // "01:00" → 60；"off"、空白、看不懂 → -1
        static int ParseHm(string s)
        {
            string[] a = (s ?? "").Trim().Replace("：", ":").Split(':');
            int h, m;
            if (a.Length == 2 && int.TryParse(a[0], out h) && int.TryParse(a[1], out m) && h >= 0 && h < 24 && m >= 0 && m < 60) return h * 60 + m;
            return -1;
        }
        static string Hm(int min) { return min < 0 ? "off" : (min / 60).ToString("00") + ":" + (min % 60).ToString("00"); }

        // ================= pipe =================
        static int NthSpace(string t, int n) { int i = -1; for (int k = 0; k < n; k++) { i = t.IndexOf(' ', i + 1); if (i < 0) return -1; } return i; }

        void StudyMsg(Client c, string[] p, string line)
        {
            if (!studyLoaded) LoadStudy();
            string t = line.Trim();
            switch (p[0])
            {
                case "course":
                    if (p.Length >= 5)
                    {
                        long ms; int lead; int i4 = NthSpace(t, 4);
                        if (long.TryParse(p[1], out ms) && int.TryParse(p[2], out lead)) AddTicket(ms, lead, p[3], i4 > 0 ? t.Substring(i4 + 1) : "", "course");
                    }
                    break;
                case "exam":
                    if (p.Length >= 3)
                    {
                        long ms; int i2 = NthSpace(t, 2);
                        if (long.TryParse(p[1], out ms)) AddExam(ms, i2 > 0 ? t.Substring(i2 + 1).Trim() : "", "me", null, true);
                    }
                    break;
                case "exam-del": if (p.Length >= 2) DelExam(p[1]); break;
                case "study-set": if (p.Length >= 2) StudySet(p); break;
                case "study-vs":   // VS Code 這次管哪幾項（其他的交還給桌面版的設定視窗）
                    vsKeys.Clear();
                    if (p.Length >= 2) foreach (string k in p[1].Split(',')) if (k != "-" && k.Trim() != "") vsKeys.Add(k.Trim());
                    StudySaved();
                    break;
                case "study-hello": Send(c, StateLine()); break;
                case "study-done": if (p.Length >= 2) { MarkDone(p[1], false); PushState(); } break;
                // ---- 測試用（只在離屏模式）----
                case "study-ics":
                    if (!App.Offscreen) break;
                    if (p.Length >= 2 && p[1] == "clear") { testFeeds.Clear(); haveSchool = schoolUrls.Count > 0; }
                    else if (p.Length >= 2) { try { testFeeds.Add(new KeyValuePair<string, string>(p.Length >= 3 ? p[2] : p[1], File.ReadAllText(p[1], Encoding.UTF8))); } catch (Exception ex) { App.Log("study-ics: " + ex.Message); } }
                    RescanNow();
                    break;
                case "study-clock":
                    {
                        DateTime want;
                        if (p.Length >= 2 && DateTime.TryParse(p[1], out want)) studyShift = want - DateTime.Now; else studyShift = TimeSpan.Zero;
                        studyNext = 0;
                        if (testFeeds.Count > 0) RescanNow();
                    }
                    break;
                case "study-idle": { double s; studyIdleFake = p.Length >= 2 && double.TryParse(p[1], out s) ? s : -1; } break;
                case "study-dump": Send(c, StudyDump()); break;
                case "study-settings":
                    if (p.Length < 2) break;
                    if (p[1] == "open") ShowStudySettings();
                    else if (studyForm != null && !studyForm.IsDisposed)
                    {
                        if (p[1] == "close") studyForm.Close();
                        else if (p[1] == "save") studyForm.Save();
                        else if (p[1] == "set" && p.Length >= 4) studyForm.TestSet(p[2], t.Substring(NthSpace(t, 3) + 1));
                    }
                    break;
            }
        }

        // VS Code 推設定：推過的那一項就記成「由 VS Code 管理」
        void StudySet(string[] p)
        {
            string k = p[1];
            switch (k)
            {
                case "urls":
                    lock (schoolUrls)
                    {
                        schoolUrls.Clear();
                        for (int i = 2; i < p.Length; i++) { string u = NormUrl(p[i]); if (u != null && !schoolUrls.Contains(u)) schoolUrls.Add(u); }
                    }
                    haveSchool = schoolUrls.Count > 0 || testFeeds.Count > 0;
                    fetchNow = true;
                    break;
                case "remind": { int n; if (p.Length >= 3 && int.TryParse(p[2], out n) && n > 0) classRemind = Math.Min(120, n); replan = true; } break;
                case "autoquiet": classAutoQuiet = p.Length < 3 || p[2] != "0"; replan = true; break;
                case "late": { int m = p.Length >= 3 ? ParseHm(p[2]) : -1; lateOn = m >= 0; if (m >= 0) lateStartMin = m; } break;
                case "nudge": examNudgeMin = p.Length >= 3 ? ParseHm(p[2]) : -1; break;
                case "workcal": workCal = p.Length >= 3 && p[2] != "-" ? (NormUrl(p[2]) ?? "") : ""; fetchNow = true; StudySaved(); return;
                default: return;
            }
            vsKeys.Add(k);
            StudySaved();
        }
        void StudySaved() { SaveStudyConfig(); if (studyForm != null && !studyForm.IsDisposed) studyForm.Reload(); }

        string StudyDump()
        {
            StringBuilder sb = new StringBuilder();
            sb.Append("study now=" + SNow().ToString("yyyy-MM-ddTHH:mm") + " school=" + (haveSchool ? 1 : 0) + " urls=" + schoolUrls.Count + " remind=" + classRemind + " autoquiet=" + (classAutoQuiet ? 1 : 0)
                + " late=" + (lateOn ? Hm(lateStartMin) : "off") + " nudge=" + Hm(examNudgeMin) + " lateKey=" + lateKey + " lateLevel=" + lateLevel + " asleep=" + (lateAsleep ? 1 : 0)
                + " quiet=" + (quietOn ? QuietLeft() : 0) + " vs=" + string.Join(",", new List<string>(vsKeys).ToArray()) + "\n");
            foreach (Exam e in exams) sb.Append("exam " + e.Src + " " + FromUnixMs(e.At).ToString("yyyy-MM-ddTHH:mm") + " daily=" + e.LastDaily + " before=" + (e.DayBefore ? 1 : 0) + " morning=" + (e.Morning ? 1 : 0) + " " + e.Name + "\n");
            foreach (Deadline d in deadlines) sb.Append("deadline " + FromUnixMs(d.Due).ToString("yyyy-MM-ddTHH:mm") + " stage=" + d.Stage + " " + d.Title + (d.Course != "" ? " [" + d.Course + "]" : "") + " " + (d.Url ?? "-") + "\n");
            foreach (SchoolPlanItem it in plan) sb.Append("plan " + FromUnixMs(it.At).ToString("yyyy-MM-ddTHH:mm") + " " + it.Kind + " q=" + it.QuietMin + (planFired.Contains(it.Key) ? " fired" : "") + " " + it.Text + "\n");
            foreach (Ticket tk in tickets) sb.Append("ticket " + tk.Kind + " " + FromUnixMs(tk.At).ToString("yyyy-MM-ddTHH:mm") + " stage=" + tk.Stage + " " + tk.Name + "\n");
            sb.Append("bar " + BarText() + "\n");
            sb.Append("end\n");
            return sb.ToString();
        }

        // ================= 給 VS Code 的狀態（狀態列、「這週要交的」）=================
        string lastState = "";
        string StateLine()
        {
            long now = SNowMs();
            List<Dictionary<string, object>> d = new List<Dictionary<string, object>>(), e = new List<Dictionary<string, object>>();
            foreach (Deadline x in deadlines)
            {
                if (x.Due <= now || x.Due - now > 7L * 86400000) continue;
                Dictionary<string, object> o = new Dictionary<string, object>();
                o["id"] = x.Id; o["due"] = x.Due; o["title"] = x.Title; o["course"] = x.Course; o["url"] = x.Url ?? "";
                d.Add(o);
            }
            foreach (Exam x in exams)
            {
                Dictionary<string, object> o = new Dictionary<string, object>();
                o["id"] = x.Id; o["at"] = x.At; o["name"] = x.Name;
                e.Add(o);
            }
            Dictionary<string, object> s = new Dictionary<string, object>();
            s["bar"] = BarText(); s["school"] = haveSchool ? 1 : 0; s["d"] = d; s["e"] = e;
            return "study-state " + new JavaScriptSerializer().Serialize(s) + "\n";
        }
        void PushState()
        {
            string s = StateLine();
            if (s == lastState) return;
            lastState = s;
            lock (clients) foreach (Client c in clients) Send(c, s);
        }

        // 狀態列：24 小時內的作業、7 天內的考試，挑最近的一個（沒有就空白）
        string BarText()
        {
            long now = SNowMs(), best = long.MaxValue;
            string text = "";
            foreach (Deadline x in deadlines)
                if (x.Due > now && x.Due - now <= 24 * 3600000L && x.Due < best) { best = x.Due; text = "📝 " + Short(x.Title, 8) + " " + LeftText(x.Due - now); }
            foreach (Exam x in exams)
                if (x.At > now && x.At - now <= 7L * 86400000 && x.At < best)
                {
                    best = x.At;
                    int days = (FromUnixMs(x.At).Date - SNow().Date).Days;
                    text = "📚 " + Short(x.Name, 8) + " " + (days <= 0 ? "今天" : (days == 1 ? "明天" : days + " 天"));
                }
            return text;
        }
        static string LeftText(long ms)
        {
            if (ms < 3600000) return "剩 " + Math.Max(1, (int)Math.Ceiling(ms / 60000.0)) + " 分";
            if (ms < 48 * 3600000L) return "剩 " + (ms / 3600000) + " 小時";
            return "剩 " + (ms / 86400000) + " 天";
        }

        // ================= 抓學校行事曆（背景執行緒；連不上就用上次存的）=================
        readonly List<KeyValuePair<string, string>> testFeeds = new List<KeyValuePair<string, string>>();   // 測試用：網址 → ICS 內容
        volatile bool fetchNow = true, replan;
        bool fetchStarted;
        string schoolStatus = "";                            // 給設定視窗：上次更新的狀況
        List<SchoolPlanItem> plan = new List<SchoolPlanItem>();
        readonly HashSet<string> planFired = new HashSet<string>();
        SchoolScan lastScan;

        void StartSchoolFetch()
        {
            fetchStarted = true;
            Thread th = new Thread(SchoolFetchLoop); th.IsBackground = true; th.Start();
        }

        void SchoolFetchLoop()
        {
            DateTime nextFetch = DateTime.MinValue, nextScan = DateTime.MinValue;
            Dictionary<string, string> texts = new Dictionary<string, string>();
            Thread.Sleep(3000);
            while (!closing)
            {
                try
                {
                    List<string> urls;
                    lock (schoolUrls) urls = new List<string>(schoolUrls);
                    string skip = workCal, skip2 = WorkMeetUrl();
                    urls.RemoveAll(delegate(string u) { return u == skip || u == skip2; });   // 跟開會提醒（VS Code 或桌面版的工作設定）同一份：不要提醒兩次
                    bool doFetch = fetchNow || DateTime.Now >= nextFetch;
                    if (urls.Count > 0 && !App.Offscreen && doFetch)
                    {
                        fetchNow = false;
                        nextFetch = DateTime.Now.AddMinutes(10);
                        int ok = 0;
                        string err = "";
                        foreach (string u in urls)
                        {
                            string text = Fetch(u, ref err);
                            if (text != null) { ok++; WriteText(CacheName(u), text); }
                            else text = ReadText(CacheName(u));
                            if (!string.IsNullOrEmpty(text)) texts[u] = text;
                        }
                        string st = DateTime.Now.ToString("HH:mm") + " 更新：" + ok + "/" + urls.Count + " 個行事曆" + (err != "" ? "（" + err + "）" : "");
                        schoolStatus = st;
                        nextScan = DateTime.MinValue;
                    }
                    else if (doFetch) { fetchNow = false; nextFetch = DateTime.Now.AddMinutes(10); }
                    if (DateTime.Now >= nextScan || replan)
                    {
                        nextScan = DateTime.Now.AddMinutes(2);
                        List<KeyValuePair<string, string>> feeds = new List<KeyValuePair<string, string>>();
                        foreach (string u in urls) { string tx; if (texts.TryGetValue(u, out tx)) feeds.Add(new KeyValuePair<string, string>(u, tx)); }
                        bool none = urls.Count == 0;
                        if (feeds.Count > 0 || none)
                        {
                            SchoolScan r = ScanFeeds(feeds);
                            Post(delegate { if (testFeeds.Count == 0) ApplyScan(r, none); });
                        }
                    }
                }
                catch (Exception ex) { App.Log("school fetch: " + ex.Message); }
                Thread.Sleep(1000);
            }
        }

        static string CacheName(string url)
        {
            using (System.Security.Cryptography.MD5 md5 = System.Security.Cryptography.MD5.Create())
            {
                byte[] h = md5.ComputeHash(Encoding.UTF8.GetBytes(url));
                StringBuilder sb = new StringBuilder("school-");
                for (int i = 0; i < 6; i++) sb.Append(h[i].ToString("x2"));
                return sb.Append(".ics").ToString();
            }
        }

        static string Fetch(string url, ref string err)
        {
            try
            {
                System.Net.ServicePointManager.SecurityProtocol |= (System.Net.SecurityProtocolType)3072;   // TLS 1.2
                System.Net.HttpWebRequest req = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(url);
                req.Timeout = 20000; req.ReadWriteTimeout = 20000; req.UserAgent = "DeskPals"; req.MaximumAutomaticRedirections = 4;
                req.AutomaticDecompression = System.Net.DecompressionMethods.GZip | System.Net.DecompressionMethods.Deflate;
                using (System.Net.HttpWebResponse resp = (System.Net.HttpWebResponse)req.GetResponse())
                using (StreamReader r = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                {
                    char[] buf = new char[8192];
                    StringBuilder sb = new StringBuilder();
                    int n;
                    while ((n = r.Read(buf, 0, buf.Length)) > 0) { sb.Append(buf, 0, n); if (sb.Length > 8000000) break; }   // 最多 8 MB
                    string s = sb.ToString();
                    if (!s.Contains("BEGIN:VCALENDAR")) { err = "有一個網址不是行事曆"; return null; }
                    return s;
                }
            }
            catch (System.Net.WebException ex)
            {
                System.Net.HttpWebResponse r = ex.Response as System.Net.HttpWebResponse;
                err = r != null ? "HTTP " + (int)r.StatusCode : "連不上";
                App.Log("school ics " + err + ": " + ex.Message);
                return null;
            }
            catch (Exception ex) { err = "讀取失敗"; App.Log("school ics: " + ex.Message); return null; }
        }

        SchoolScan ScanFeeds(List<KeyValuePair<string, string>> feeds)
        {
            List<SchoolFeed> fs = new List<SchoolFeed>();
            foreach (KeyValuePair<string, string> f in feeds)
            {
                try { fs.Add(School.Feed(f.Key, f.Value)); }
                catch (Exception ex) { App.Log("school parse: " + ex.Message); }
            }
            return School.Scan(fs, SNowMs());
        }

        // 測試：馬上用 testFeeds 掃一次（UI 執行緒）
        void RescanNow()
        {
            haveSchool = schoolUrls.Count > 0 || testFeeds.Count > 0;
            if (testFeeds.Count == 0) return;
            ApplyScan(ScanFeeds(testFeeds), false);
        }

        // 掃完：作業死線、行事曆上的考試換成這次的（提醒到哪一段、交了的照舊）；上課提醒重排
        void ApplyScan(SchoolScan r, bool none)
        {
            if (!studyLoaded) LoadStudy();
            lastScan = r;
            haveSchool = !none || testFeeds.Count > 0;
            long now = SNowMs();
            Dictionary<string, Deadline> old = new Dictionary<string, Deadline>();
            foreach (Deadline d in deadlines) old[d.Id] = d;
            deadlines.Clear();
            foreach (SchoolDue x in r.Dues)
            {
                if (studyDone.Contains(x.Id)) continue;
                Deadline d = new Deadline();
                d.Id = x.Id; d.Due = x.Due; d.Title = x.Title; d.Course = x.Course; d.Url = SafeUrl(x.Url);
                if (d.Url != null && !d.Url.StartsWith("http")) d.Url = null;
                Deadline was;
                d.Stage = old.TryGetValue(d.Id, out was) && was.Due == d.Due ? was.Stage : FirstStage(d.Due, now);
                deadlines.Add(d);
            }
            Dictionary<string, Exam> oldEx = new Dictionary<string, Exam>();
            foreach (Exam e in exams) if (e.Src == "ics") oldEx[e.Id] = e;
            exams.RemoveAll(delegate(Exam e) { return e.Src == "ics"; });
            foreach (SchoolExam x in r.Exams)
            {
                if (x.At <= now || studyDone.Contains(x.Id)) continue;
                Exam was;
                if (oldEx.TryGetValue(x.Id, out was) && was.At == x.At) { was.Name = x.Name; exams.Add(was); }
                else AddExam(x.At, x.Name, "ics", x.Id, false);
            }
            SortExams();
            SaveDeadlines(); SaveExams();
            replan = false;
            plan = School.Plan(r.Timed, now - 3 * 60000L, classRemind, classAutoQuiet);   // 剛到的那幾則也留著（重掃剛好卡在提醒那一刻不會漏；planFired 擋重複）
            PushState();
            if (studyForm != null && !studyForm.IsDisposed) studyForm.Invalidate();
        }

        // 第一次看到：已經過了的階段不補，但 24 小時內的話，最近那段馬上講一次
        static int FirstStage(long due, long now)
        {
            double left = (due - now) / 60000.0;
            int passed = 0;
            for (int s = 0; s < DueStages.Length; s++) if (left <= DueStages[s]) passed = s + 1;
            if (passed > 0 && left <= 24 * 60 && left > 0) passed--;
            return passed;
        }

        void MarkDone(string id, bool tell)
        {
            if (!studyLoaded) LoadStudy();
            studyDone.Add(id);
            List<string> keep = new List<string>(studyDone);
            if (keep.Count > 500) keep = keep.GetRange(keep.Count - 500, 500);
            WriteText("study-done.txt", string.Join("\n", keep.ToArray()));
            deadlines.RemoveAll(delegate(Deadline d) { return d.Id == id; });
            SaveDeadlines();
            if (tell) { string s = "study-done " + id + "\n"; lock (clients) foreach (Client c in clients) Send(c, s); PushState(); }
        }

        // ================= 每一輪 =================
        bool StudyBusy() { return quietOn || focusOn || sharing || fsNow || Hidden; }

        void StudyTick()
        {
            if (!studyLoaded) LoadStudy();
            if (Now < studyNext) return;
            studyNext = Now + 2;
            if (!fetchStarted) StartSchoolFetch();
            try { PlanTick(); DeadlineTick(); ExamTick(); LateTick(); PushState(); }
            catch (Exception ex) { App.Log("study: " + ex.Message); }
        }

        // ================= 上課／考試／行程提醒（跟開會一樣：課前 N 分鐘、開始時；上課、考試中自動安靜）=================
        void PlanTick()
        {
            if (plan.Count == 0) return;
            long now = SNowMs();
            foreach (SchoolPlanItem it in plan)
            {
                if (it.At > now || planFired.Contains(it.Key)) continue;
                planFired.Add(it.Key);
                if (now - it.At > (it.Kind.EndsWith("-now") ? 5 : 3) * 60000L) continue;   // 電腦睡著錯過太久的就不補
                App.Log("school " + it.Kind + ": " + it.Text);
                if (it.Kind == "class-now") { Count("classes"); WorkLogClass(it); }   // 工作來源：上課也寫進小本子（DeskPals.Work.cs）
                OnNotify(it.Kind, it.Url != "" ? it.Url : "-", it.Text);
                int q = it.QuietMin;
                if (q > 0) Later(10, delegate { StartQuiet(q); });   // 等「上課了」那則講完再安靜（不然馬上被「我安靜待著」蓋掉）
            }
            if (planFired.Count > 400) planFired.Clear();
        }

        // ================= 作業死線（3 天、1 天、3 小時、1 小時）=================
        void DeadlineTick()
        {
            if (deadlines.Count == 0) return;
            long now = SNowMs();
            List<Deadline> fire = new List<Deadline>();
            int top = -1;
            bool changed = false;
            for (int i = deadlines.Count - 1; i >= 0; i--)
            {
                Deadline d = deadlines[i];
                double left = (d.Due - now) / 60000.0;
                if (left < -60) { deadlines.RemoveAt(i); changed = true; continue; }
                int f = -1;
                for (int s = d.Stage; s < DueStages.Length; s++) if (left <= DueStages[s]) f = s;
                if (f < 0) continue;
                d.Stage = f + 1; changed = true;
                if (left <= 0) continue;     // 已經截止了：不再叫
                fire.Add(d); top = Math.Max(top, f);
            }
            if (changed) SaveDeadlines();
            if (fire.Count == 0) return;
            fire.Sort(delegate(Deadline a, Deadline b) { return a.Due.CompareTo(b.Due); });
            string text;
            if (fire.Count == 1) text = DeadlineText(fire[0], top, now);
            else
            {
                List<string> parts = new List<string>();
                for (int i = 0; i < fire.Count && i < 3; i++) parts.Add("「" + Short(fire[i].Title, 14) + "」" + DueWhen(fire[i].Due));
                text = "有 " + fire.Count + " 份作業快截止了：" + string.Join("、", parts.ToArray()) + (fire.Count > 3 ? "…" : "");
            }
            List<string> ids = new List<string>();
            foreach (Deadline d in fire) ids.Add(d.Id);
            deadlineNotes[text] = ids;
            App.Log("deadline stage " + top + ": " + text);
            OnNotify(top >= 3 ? "deadline-hot" : "deadline", fire[0].Url ?? "-", text);
        }

        static string Short(string s, int n)
        {
            if (s.Length <= n) return s;
            if (char.IsHighSurrogate(s[n - 1])) n--;
            return s.Substring(0, n) + "…";
        }
        static readonly string[] WeekDays = { "日", "一", "二", "三", "四", "五", "六" };

        // 今天 23:59／明天 23:59／11/20（五）23:59
        string DueWhen(long due)
        {
            DateTime d = FromUnixMs(due), n = SNow();
            int days = (d.Date - n.Date).Days;
            string hm = d.ToString("HH:mm");
            if (days == 0) return (d.Hour < 6 ? "今天凌晨 " : "今天 ") + hm;
            if (days == 1) return (d.Hour < 6 ? "明天凌晨 " : "明天 ") + hm;
            return d.ToString("M/d") + "（" + WeekDays[(int)d.DayOfWeek] + "）" + hm;
        }

        string DeadlineText(Deadline d, int stage, long now)
        {
            string name = "「" + d.Title + "」" + (d.Course != "" ? "（" + Short(d.Course, 12) + "）" : "");
            double left = (d.Due - now) / 60000.0;
            int days = (FromUnixMs(d.Due).Date - SNow().Date).Days;
            switch (stage)
            {
                case 0: return name + " " + DueWhen(d.Due) + " 截止，還有 " + Math.Max(1, days) + " 天";
                case 1: return name + " " + DueWhen(d.Due) + " 截止！別忘了 📝";
                case 2: return name + " 再 " + Math.Max(1, (int)Math.Ceiling(left / 60)) + " 小時就截止了（" + FromUnixMs(d.Due).ToString("HH:mm") + "）";
                default: return name + (left < 55 ? " 剩 " + Math.Max(1, (int)Math.Ceiling(left)) + " 分鐘！" : " 剩不到 1 小時！") + FromUnixMs(d.Due).ToString("HH:mm") + " 截止，趕快交 📝";
            }
        }

        // 點了作業通知：打開作業頁／交了／等等再說
        bool StudyClicked(Pet p, Notice n)
        {
            if (n.Kind != "deadline" && n.Kind != "deadline-hot") return false;
            List<string> ids;
            deadlineNotes.TryGetValue(n.Text, out ids);
            if (App.Offscreen) { p.Say("好～", 1.2); App.Log("deadline clicked (offscreen): " + n.Text); return true; }
            ContextMenuStrip m = new ContextMenuStrip();
            string url = n.Url;
            if (url != null) m.Items.Add("打開作業頁", null, delegate { OpenStudyUrl(p, url); });
            if (ids != null && ids.Count > 0)
            {
                List<string> l = ids;
                m.Items.Add(l.Count > 1 ? "都交了 ✓（不再提醒）" : "交了 ✓（不再提醒）", null, delegate { foreach (string id in l) MarkDone(id, true); p.Say("好棒！交了就輕鬆了 🎉", 2.2); });
            }
            m.Items.Add("等等再說", null, delegate { p.Say("好，時間快到會再叫你", 1.6); });
            ShowMenu(m, "作業", false);
            return true;
        }

        void OpenStudyUrl(Pet p, string url)
        {
            if (App.Offscreen) { App.Log("open (offscreen, skipped): " + url); return; }
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); p.Say("好～幫你打開了 👍", 1.4); }
            catch (Exception ex) { App.Log("open url: " + ex.Message); p.Say("打不開耶…", 1.4); }
        }

        // ================= 考試倒數 =================
        void SortExams() { exams.Sort(delegate(Exam a, Exam b) { return a.At.CompareTo(b.At); }); }

        public void AddExam(long at, string name, string src, string id, bool say)
        {
            if (!studyLoaded) LoadStudy();
            Exam e = new Exam();
            e.At = at; e.Name = string.IsNullOrEmpty(name) ? "考試" : OneLine(name); e.Src = src; e.Id = id ?? ("me-" + at);
            DateTime n = SNow(), ed = FromUnixMs(at);
            // 加的時候已經過了今天倒數的時間：今天不再補講（剛剛才講過記住了）
            if (examNudgeMin >= 0 && n.Hour * 60 + n.Minute >= examNudgeMin) e.LastDaily = n.ToString("yyyyMMdd");
            exams.RemoveAll(delegate(Exam x) { return x.Id == e.Id; });
            exams.Add(e);
            SortExams(); SaveExams();
            if (!say) return;
            PushState();
            int days = (ed.Date - n.Date).Days;
            string left = days <= 0 ? "就是今天" : (days == 1 ? "就是明天" : "還有 " + days + " 天");
            Lead().Say("📚 記住了：" + e.Name + "，" + ed.ToString("M/d HH:mm") + "，" + left + (examNudgeMin >= 0 && days >= 2 ? "。每天 " + Hm(examNudgeMin) + " 幫你倒數" : ""), 3.2);
        }

        void DelExam(string id)
        {
            Exam e = exams.Find(delegate(Exam x) { return x.Id == id; });
            if (e == null) return;
            exams.Remove(e);
            if (e.Src == "ics") MarkDone(id, false);   // 行事曆上的：下次同步也別再加回來
            SaveExams(); PushState();
            Lead().Say("取消考試倒數：" + e.Name, 1.8);
        }

        // 7 天內有考試：專注改叫「讀書 25 分鐘 📚」
        public bool ExamNear()
        {
            if (!studyLoaded) LoadStudy();
            long now = SNowMs();
            foreach (Exam e in exams) if (e.At > now && e.At - now <= 7L * 24 * 3600000) return true;
            return false;
        }

        // 早上那一則：07:30（考試比 08:30 早就提前到考前一小時）
        static DateTime MorningAt(DateTime exam)
        {
            DateTime m = exam.Date.AddHours(7.5);
            return exam.AddHours(-1) < m ? exam.AddHours(-1) : m;
        }

        void ExamTick()
        {
            if (exams.Count == 0) return;
            DateTime n = SNow();
            long now = UnixMs(n);
            bool changed = exams.RemoveAll(delegate(Exam x) { return now > x.At + 3 * 3600000L; }) > 0;   // 考完 3 小時就收掉
            if (changed) SaveExams();
            if (StudyBusy() || StudyIdle() > 120) return;          // 安靜、專注、分享螢幕、你不在：等一下再講（當天都還會補）
            string today = n.ToString("yyyyMMdd");
            int nowMin = n.Hour * 60 + n.Minute;
            Exam morning = null, before = null;
            List<Exam> daily = new List<Exam>();
            foreach (Exam e in exams)
            {
                DateTime ed = FromUnixMs(e.At);
                int days = (ed.Date - n.Date).Days;
                if (days == 0 && !e.Morning && now < e.At && n >= MorningAt(ed)) { if (morning == null) morning = e; }
                else if (days == 1 && !e.DayBefore && examNudgeMin >= 0 && nowMin >= examNudgeMin) { if (before == null) before = e; }
                else if (days >= 2 && days <= 14 && e.LastDaily != today && examNudgeMin >= 0 && nowMin >= examNudgeMin) daily.Add(e);
            }
            Pet l = Lead();
            if (morning != null)
            {
                morning.Morning = true; morning.LastDaily = today; SaveExams();
                string t = ExamPrefix(l.P.Id) + "今天 " + FromUnixMs(morning.At).ToString("HH:mm") + "「" + morning.Name + "」，加油！🍀 准考證、文具、學生證帶了嗎？";
                App.Log("exam morning: " + morning.Name);
                l.Notify(t, null, 1, false, false);
                foreach (Pet o in OutPets()) if (o != l) o.React();
                return;
            }
            if (before == null && daily.Count == 0) return;
            List<string> parts = new List<string>();
            foreach (Exam e in daily) { e.LastDaily = today; parts.Add("離「" + e.Name + "」還有 " + (FromUnixMs(e.At).Date - n.Date).Days + " 天"); }
            string text = parts.Count > 0 ? string.Join("、", parts.ToArray()) + " 📚 " + ExamTail(l.P.Id) : "";
            if (before != null)
            {
                // 明天就考：這則優先，其他的倒數接在後面一起講
                before.DayBefore = true; before.LastDaily = today;
                text = ExamPrefix(l.P.Id) + "明天 " + FromUnixMs(before.At).ToString("HH:mm") + " 就是「" + before.Name + "」了！重點再看一次，今晚早點睡 💤" + (parts.Count > 0 ? "（" + string.Join("、", parts.ToArray()) + "）" : "");
            }
            SaveExams();
            App.Log("exam nudge: " + text);
            StudyNudge(l, text);
        }

        // 倒數提醒：點泡泡就開始讀書（番茄鐘）
        void StudyNudge(Pet l, string text)
        {
            Notice nt = new Notice(); nt.Kind = "exam"; nt.Text = ""; nt.Pri = 1; nt.NextRound = true; nt.By = l; nt.Expire = Now + 120;
            current = nt;
            l.SetClickableBubble(true);
            l.Notify(text, "點我開始讀書 " + focusMin + " 分鐘", 1, false, false);
        }

        static string ExamPrefix(string id)
        {
            string cu = CuStudy(id, "x_exam_prefix", null, null, null); if (cu != null) return cu;   // 自己做的公仔（DeskPals.Custom.cs）
            // <fan>
            switch (id)
            {
                case "spidey": return "蜘蛛感應：";
                case "po": case "tinky": return "Eh-oh! ";
                case "stitch": return "ih! ";
                case "hangyodon": return "英雄報告：";
                case "dipsy": return "嘿，";
                case "laalaa": return "啦啦～";
            }
            // </fan>
            return id.StartsWith("pk") ? "皮克敏報告：" : "";   //@fan
            // <public> return "";
        }

        static string ExamTail(string id)
        {
            string cu = CuStudy(id, "x_exam_tail", null, null, null); if (cu != null) return cu;
            // <fan>
            switch (id)
            {
                case "po": return "小波陪你讀書！";
                case "stitch": return "史迪仔幫你翻書！ih!";
                case "hangyodon": return "讀書的你才是真正的英雄";
                case "tinky": return "丁丁陪你讀～";
                case "dipsy": return "讀一點，很酷。";
                case "laalaa": return "邊讀邊唱～啦啦";
            }
            // </fan>
            return id.StartsWith("pk") ? "皮克敏幫你搬課本！" : "今天讀一點？";   //@fan
            // <public> return "今天讀一點？";
        }

        // ================= 熬夜提醒（預設 01:00 起；02:00、03:00 再講；06:00 結束；離開電腦 15 分鐘就當你睡了）=================
        void LateTick()
        {
            if (!lateOn || lateStartMin < 0) return;
            DateTime n = SNow();
            int m = n.Hour * 60 + n.Minute;
            int sh = (m + 720) % 1440, st = (lateStartMin + 720) % 1440, end = (6 * 60 + 720) % 1440;   // 以中午當一天的開始，跨半夜好算
            if (sh < st || sh >= end) return;
            string key = n.AddHours(-12).ToString("yyyyMMdd");
            if (key != lateKey) { lateKey = key; lateLevel = -1; lateAsleep = false; SaveLate(); }
            if (lateAsleep) return;
            double idle = StudyIdle();
            if (lateLevel >= 0 && idle >= 15 * 60) { lateAsleep = true; SaveLate(); App.Log("latenight: idle, stop for tonight"); return; }
            int want = Math.Min(2, (sh - st) / 60);
            if (want <= lateLevel || idle > 120) return;          // 你不在電腦前：等你回來
            if (StudyBusy()) return;                              // 安靜、專注、分享螢幕：不吵
            lateLevel = want; SaveLate();
            Pet l = Lead();
            string text = LateNightLine(l.P.Id, want, n.ToString("H:mm")) + LateExtra(n);
            App.Log("latenight " + want + ": " + text);
            if (want == 0) { l.WakeIfSleep(); l.Say(text, 8); }
            else
            {
                l.Notify(text, null, 1, false, false);
                if (want == 2) foreach (Pet o in OutPets()) if (o != l) o.React();
            }
        }

        // 還在趕作業／明天有考試：補一句
        string LateExtra(DateTime n)
        {
            long now = UnixMs(n);
            foreach (Deadline d in deadlines)
                if (d.Due > now && d.Due - now <= 8 * 3600000L) return "（還在趕「" + Short(d.Title, 12) + "」嗎？交完就去睡）";
            foreach (Exam e in exams)
                if (e.At > now && e.At - now <= 14 * 3600000L) return "（" + FromUnixMs(e.At).ToString("H:mm") + " 還有「" + Short(e.Name, 12) + "」，睡飽比熬夜有用）";
            return "";
        }

        static string LateNightLine(string id, int lv, string hm)
        {
            string cu = CuStudy(id, "x_late" + Math.Max(0, Math.Min(2, lv)), hm, null, null); if (cu != null) return cu;
            string[] a;
            switch (id)
            {
                // <fan>
                case "spidey": a = new string[] { "已經 " + hm + " 了…蜘蛛也要睡覺的，今天先到這裡？🌙", hm + " 了。熬夜的英雄明天會變殭屍，存檔去睡吧", hm + "！！蜘蛛感應：你真的該睡了 😴 剩下的明天再做" }; break;
                case "po": a = new string[] { "嗚…" + hm + " 了，小波好睏…你也去睡覺覺好不好 🌙", hm + " 了！太陽寶寶都睡好久了，關電腦吧～", hm + " 了…小波撐不住了，一起去睡嘛 😴" }; break;
                case "stitch": a = new string[] { hm + " 了…史迪仔想睡了，你也睡 🌙", hm + "！ih! 睡覺！明天再玩！", hm + "！！再不睡史迪仔要拔電源線了喔 😴" }; break;
                case "hangyodon": a = new string[] { hm + " 了…我在泡泡裡都快睡著了，你也早點休息 🌙", hm + " 了，英雄也要睡飽才能拯救世界", hm + " 了！真的該睡了…這不是冷笑話 😴" }; break;
                case "tinky": a = new string[] { hm + " 了…丁丁抱著袋袋想睡覺覺 🌙", hm + " 了！天線寶寶說：該睡覺囉～", hm + " 了…丁丁跌坐在枕頭上了，你也去睡 😴" }; break;
                case "dipsy": a = new string[] { hm + "。很晚了，帽子拉低，該睡了 🌙", hm + "。熬夜不酷，睡覺比較酷。", hm + "。真的，去睡。😴" }; break;
                case "laalaa": a = new string[] { hm + " 了…拉拉唱搖籃曲給你聽～啦…啦… 🌙", hm + " 了！球球都睡了，你也睡吧～", hm + " 了…啦…（打哈欠）一起去睡嘛 😴" }; break;
                // </fan>
                default:
                    if (id.StartsWith("pk")) a = new string[] { hm + " 了…皮克敏都回洋蔥睡了 🌙", hm + " 了，夜晚很危險，快回基地睡覺！", hm + " 了！！再不睡天就亮了 😴" };   //@fan
                    else a = new string[] { "已經 " + hm + " 了，今天先到這裡好嗎？早點休息 🌙", hm + " 了，明天會很累喔，存檔去睡吧", hm + " 了！真的該睡了 😴" };   //@fan
                    // <public> a = new string[] { "已經 " + hm + " 了，今天先到這裡好嗎？早點休息 🌙", hm + " 了，明天會很累喔，存檔去睡吧", hm + " 了！真的該睡了 😴" };
                    break;
            }
            return a[Math.Max(0, Math.Min(2, lv))];
        }

        // ================= 通知（DeskPals.cs 的 Priority／Flavor／OnNotify／Deliver 會來問）=================
        static int StudyPriority(string kind)
        {
            switch (kind)
            {
                case "class": case "class-now": case "exam-soon": case "exam-now": case "deadline-hot": return 2;
                case "deadline": case "event": case "event-now": return 1;
            }
            return -1;
        }

        // 上課、考試、行程跟開會一樣：安靜時還是冒泡泡，敲玻璃走會議的冷卻
        static bool MeetingLike(string kind) { return kind.StartsWith("meeting") || kind.StartsWith("class") || kind.StartsWith("exam-") || kind.StartsWith("event"); }

        static string StudyFlavor(string id, string kind)
        {
            string[] keys = { "class", "class-now", "exam-soon", "exam-now", "event", "event-now", "deadline", "deadline-hot" };
            int i = Array.IndexOf(keys, kind);
            if (i < 0) return null;
            string[] a;
            Pal sp = Pal.Get(id);
            if (sp != null && sp.Lines.TryGetValue("sf_" + kind, out a) && a.Length > 0) return a[0];   // 角色自己的（翻翻：sf_<種類>）
            switch (id)
            {
                // <fan>
                case "po": a = new string[] { "🎒 小波提醒你上課：", "🎒 上課囉！Eh-oh!", "📚 要考試了，小波幫你加油：", "📚 考試！小波陪你：", "等一下有事喔：", "時間到囉：", "📝 小波提醒你寫作業：", "📝 嗚～快截止了：" }; break;
                case "stitch": a = new string[] { "🎒 ih! 要上課：", "🎒 上課！快去！", "📚 要考試！ih-ih!", "📚 考試！史迪仔幫你集氣：", "等等有事！", "開始了！", "📝 ih! 作業：", "📝 ih-ih-ih! 快截止：" }; break;
                case "hangyodon": a = new string[] { "🎒 英雄提醒：要上課了", "🎒 上課時間到了：", "📚 英雄報告：要考試了", "📚 考試開始，你就是英雄：", "等一下有行程喔：", "行程開始了：", "📝 英雄提醒你：", "📝 交給我這個英雄…快截止了：" }; break;
                case "tinky": a = new string[] { "🎒 丁丁提醒你上課：", "🎒 上課囉！Eh-oh!", "📚 要考試了，丁丁幫你加油：", "📚 考試！丁丁陪你：", "等一下有事喔：", "時間到囉：", "📝 魔法袋裡有作業：", "📝 哎喲！快截止了：" }; break;
                case "dipsy": a = new string[] { "🎒 要上課了：", "🎒 上課了，走吧：", "📚 要考試了，冷靜：", "📚 考試開始，酷：", "等等有事：", "開始了：", "📝 作業：", "📝 快截止了，帽子扶好：" }; break;
                case "laalaa": a = new string[] { "🎒 拉拉提醒你上課：", "🎒 上課囉！啦～", "📚 要考試了，拉拉幫你加油：", "📚 考試！啦啦加油：", "等一下有事喔：", "時間到囉：", "📝 拉拉提醒你寫作業：", "📝 啦！快截止了：" }; break;
                case "spidey": a = new string[] { "🎒 要上課囉：", "🎒 上課時間！", "📚 蜘蛛感應！要考試了：", "📚 考試開始！", "等一下有行程：", "行程開始了：", "📝 作業提醒：", "📝 蜘蛛感應！快截止了：" }; break;
                // </fan>
                default: a = new string[] { "🎒 要上課囉：", "🎒 上課時間！", "📚 要考試了：", "📚 考試開始！", "等一下有行程：", "行程開始了：", "📝 作業提醒：", "📝 快截止了：" }; break;
            }
            return a[i];
        }

        // ================= 搶課（Ticket 的 Kind＝course）=================
        static string CourseLine(string id, int stage, Ticket t)
        {
            string cu = CuStudy(id, "x_course" + Math.Max(0, Math.Min(4, stage)), null, t.Name, (t.Lead / 60) + " 小時"); if (cu != null) return cu;
            string h = (t.Lead / 60) + " 小時", n = t.Name;
            string[] a;
            switch (id)
            {
                // <fan>
                case "spidey": a = new string[] { "🎓 " + n + " 還有 " + h + "開放選課！先登入、志願序排好", "🎓 " + n + " 再 30 分鐘開放，選課頁先開好、課號抄好", "🎓 " + n + " 剩 10 分鐘！蜘蛛感應全開", "🎓 準備！手指放在加選按鈕上", "🎓 開放了！！快加選！Thwip!" }; break;
                case "po": a = new string[] { "🎓 " + n + " 還有 " + h + "開放選課！先登入、志願排好喔", "🎓 " + n + " 再 30 分鐘！課號先抄好，小波陪你等", "🎓 " + n + " 剩 10 分鐘！好緊張～", "🎓 準備！深呼吸～", "🎓 開放了！！衝衝衝！" }; break;
                case "stitch": a = new string[] { "🎓 " + n + " 還有 " + h + "開放選課！先登入！ih!", "🎓 " + n + " 30 分鐘！課號抄好，史迪仔幫你顧著", "🎓 " + n + " 10 分鐘！ih-ih-ih!", "🎓 準備！史迪仔也準備好了", "🎓 開放了！！衝啊！" }; break;
                case "hangyodon": a = new string[] { "🎓 " + n + " 還有 " + h + "開放選課！先登入、志願排好", "🎓 " + n + " 30 分鐘後開放，英雄陪你等", "🎓 " + n + " 剩 10 分鐘！英雄出動準備", "🎓 準備！這次一定選到！", "🎓 開放了！！祝你選到！" }; break;
                case "tinky": a = new string[] { "🎓 " + n + " 還有 " + h + "開放選課！先登入喔", "🎓 " + n + " 再 30 分鐘！丁丁陪你等", "🎓 " + n + " 剩 10 分鐘！魔法袋準備好了", "🎓 準備！深呼吸～", "🎓 開放了！！衝衝衝！" }; break;
                case "dipsy": a = new string[] { "🎓 " + n + " 還有 " + h + "開放選課，先登入", "🎓 " + n + " 30 分鐘後開放，課號抄好", "🎓 " + n + " 剩 10 分鐘，帽子戴好", "🎓 準備。冷靜，酷。", "🎓 開放了！！嘿！" }; break;
                case "laalaa": a = new string[] { "🎓 " + n + " 還有 " + h + "開放選課！先登入喔", "🎓 " + n + " 再 30 分鐘！拉拉唱歌陪你等", "🎓 " + n + " 剩 10 分鐘！好緊張～", "🎓 準備！啦…啦…", "🎓 開放了！！衝啊～啦！" }; break;
                // </fan>
                default:
                    if (id.StartsWith("pk")) a = new string[] { "🎓 " + n + " 還有 " + h + "開放選課！先登入、志願排好", "🎓 " + n + " 再 30 分鐘，皮克敏排好隊了", "🎓 " + n + " 剩 10 分鐘！全員集合！", "🎓 準備！吹哨子準備～", "🎓 開放了！！全員衝鋒！" };   //@fan
                    else a = new string[] { "🎓 " + n + " 還有 " + h + "開放選課！先登入、志願序排好", "🎓 " + n + " 再 30 分鐘開放，選課頁先開好", "🎓 " + n + " 剩 10 分鐘！", "🎓 準備！手指放在加選按鈕上", "🎓 開放了！！快加選！" };   //@fan
                    // <public> a = new string[] { "🎓 " + n + " 還有 " + h + "開放選課！先登入、志願序排好", "🎓 " + n + " 再 30 分鐘開放，選課頁先開好", "🎓 " + n + " 剩 10 分鐘！", "🎓 準備！手指放在加選按鈕上", "🎓 開放了！！快加選！" };
                    break;
            }
            return a[Math.Max(0, Math.Min(4, stage))];
        }

        // 倒數徽章上的是搶課就畫學士帽
        public bool BadgeIsCourse()
        {
            long now = UnixMs(DateTime.Now);
            foreach (Ticket t in tickets)
            {
                long ms = t.At - now;
                if ((ms > 0 && ms <= 10 * 60000) || (ms <= 0 && ms > -60000)) return t.Kind == "course";
            }
            return false;
        }

        // ================= 選單（小幫手）=================
        void AddStudyMenus(ToolStripItemCollection items)
        {
            if (!studyLoaded) LoadStudy();
            AddTicketMenus(items, "course");
            items.Add("考試倒數…", null, delegate { ShowExamForm(); });
            long now = SNowMs();
            if (exams.Count > 0)
            {
                ToolStripMenuItem my = new ToolStripMenuItem("我的考試（" + exams.Count + "）");
                foreach (Exam e in exams)
                {
                    Exam ee = e;
                    int days = (FromUnixMs(e.At).Date - SNow().Date).Days;
                    string left = days <= 0 ? "今天" : (days == 1 ? "明天" : "還有 " + days + " 天");
                    my.DropDownItems.Add(FromUnixMs(e.At).ToString("MM/dd HH:mm") + "　" + Short(e.Name, 16) + "　" + left + "（點一下取消）", null, delegate { DelExam(ee.Id); });
                }
                items.Add(my);
            }
            if (!haveSchool) { items.Add("學校行事曆（上課、作業提醒）…", null, delegate { ShowStudySettings(); }); return; }
            List<Deadline> week = deadlines.FindAll(delegate(Deadline d) { return d.Due > now && d.Due - now <= 7L * 24 * 3600000; });
            ToolStripMenuItem wk = new ToolStripMenuItem("這週要交的（" + week.Count + "）");
            if (week.Count == 0) { ToolStripMenuItem none = new ToolStripMenuItem("這週沒有要交的 🎉"); none.Enabled = false; wk.DropDownItems.Add(none); }
            foreach (Deadline d in week)
            {
                Deadline dd = d;
                ToolStripMenuItem it = new ToolStripMenuItem(DueWhen(d.Due) + "　" + Short(d.Title, 16) + (d.Course != "" ? "［" + Short(d.Course, 10) + "］" : ""));
                if (d.Url != null) it.DropDownItems.Add("打開作業頁", null, delegate { OpenStudyUrl(Lead(), dd.Url); });
                it.DropDownItems.Add("交了 ✓（不再提醒）", null, delegate { MarkDone(dd.Id, true); Lead().Say("好棒！「" + Short(dd.Title, 12) + "」交了 🎉", 2.2); });
                wk.DropDownItems.Add(it);
            }
            items.Add(wk);
        }

        // ================= 今天的小結 =================
        // 這週（週一起）的番茄數；跟今天一樣就不另外講
        static string WeekTomatoNote(int today)
        {
            DateTime d = DateTime.Now.Date;
            int back = ((int)d.DayOfWeek + 6) % 7, week = 0;
            for (int i = 0; i <= back; i++)
            {
                int v; int.TryParse(ReadText("tomato-" + d.AddDays(-i).ToString("yyyyMMdd") + ".txt"), out v);
                week += v;
            }
            return week > today ? "（這週 " + week + " 顆）" : "";
        }

        void StudyWrapParts(List<string> parts)
        {
            if (!studyLoaded) LoadStudy();
            if (Day("classes") > 0) parts.Add("上了 " + Day("classes") + " 堂課");
            long now = SNowMs();
            int n = 0;
            foreach (Deadline d in deadlines) if (d.Due > now && d.Due - now <= 7L * 24 * 3600000) n++;
            if (n > 0) parts.Add("這週還有 " + n + " 份作業要交");
            foreach (Exam e in exams)
            {
                if (e.At <= now) continue;
                int days = (FromUnixMs(e.At).Date - SNow().Date).Days;
                if (days >= 1 && days <= 14) parts.Add("離「" + Short(e.Name, 10) + "」還有 " + days + " 天");
                break;
            }
        }

        // ================= 小視窗：考試倒數、讀書小幫手設定 =================
        ExamForm examForm;
        void ShowExamForm()
        {
            if (App.Offscreen) return;
            if (examForm == null || examForm.IsDisposed) examForm = new ExamForm(this, Lead().P.Accent);
            Point c = Cursor.Position;
            Rectangle wa = WA(c.X, c.Y);
            examForm.StartPosition = FormStartPosition.Manual;
            examForm.Location = new Point(Math.Max(wa.Left, Math.Min(wa.Right - examForm.Width, c.X - examForm.Width / 2)), Math.Max(wa.Top, Math.Min(wa.Bottom - examForm.Height, c.Y - examForm.Height - 10)));
            examForm.Show();
            ActivateForm(examForm);
            examForm.FocusFirst();
            ExamForm ef = examForm;
            Later(0.2, delegate { if (ef.Visible) { ActivateForm(ef); ef.FocusFirst(); } });
        }

        StudySettingsForm studyForm;
        public void ShowStudySettings()
        {
            if (!studyLoaded) LoadStudy();
            if (studyForm == null || studyForm.IsDisposed) studyForm = new StudySettingsForm(this);
            Rectangle wa = App.Offscreen ? screens[0].WorkingArea : Screen.FromPoint(Cursor.Position).WorkingArea;
            studyForm.Location = new Point(wa.Left + (wa.Width - studyForm.Width) / 2, wa.Top + Math.Max(0, (wa.Height - studyForm.Height) / 2));
            studyForm.Show();
            if (App.Offscreen) return;
            ActivateForm(studyForm);
            StudySettingsForm sf = studyForm;
            Later(0.2, delegate { if (!sf.IsDisposed && sf.Visible) ActivateForm(sf); });
        }

        // 設定視窗讀寫用
        public string[] StudyUrls() { lock (schoolUrls) return schoolUrls.ToArray(); }
        public int ClassRemind { get { return classRemind; } }
        public bool ClassAutoQuiet { get { return classAutoQuiet; } }
        public bool LateOn { get { return lateOn; } }
        public int LateStart { get { return lateStartMin; } }
        public int ExamNudge { get { return examNudgeMin; } }
        public bool FromVsCode(string key) { return vsKeys.Contains(key); }
        public string SchoolStatus()
        {
            if (!haveSchool) return "還沒有學校行事曆";
            int week = 0; long now = SNowMs();
            foreach (Deadline d in deadlines) if (d.Due > now && d.Due - now <= 7L * 86400000) week++;
            return (schoolStatus != "" ? schoolStatus + "；" : (lastScan == null ? "更新中…；" : "")) + "這週 " + week + " 份作業";
        }
        public void ApplyStudySettings(List<string> urls, int remind, bool autoQuiet, bool late, int lateStart, int nudge)
        {
            if (!vsKeys.Contains("urls"))
                lock (schoolUrls)
                {
                    schoolUrls.Clear();
                    foreach (string u0 in urls) { string u = NormUrl(u0); if (u != null && !schoolUrls.Contains(u)) schoolUrls.Add(u); }
                }
            if (!vsKeys.Contains("remind") && remind > 0) classRemind = Math.Min(120, remind);
            if (!vsKeys.Contains("autoquiet")) classAutoQuiet = autoQuiet;
            if (!vsKeys.Contains("late")) { lateOn = late; if (lateStart >= 0) lateStartMin = lateStart; }
            if (!vsKeys.Contains("nudge")) examNudgeMin = nudge;
            haveSchool = schoolUrls.Count > 0 || testFeeds.Count > 0;
            SaveStudyConfig();
            fetchNow = true; replan = true;
            App.Log("study settings: urls=" + schoolUrls.Count + " remind=" + classRemind + " late=" + (lateOn ? Hm(lateStartMin) : "off") + " nudge=" + Hm(examNudgeMin));
            Lead().Say(schoolUrls.Count > 0 ? "🎒 記住了！上課前、作業截止前都會叫你" : "好～設定存好了", 2.4);
        }

        void StudySnap(Graphics g) { if (studyForm != null && !studyForm.IsDisposed && studyForm.VVisible) studyForm.PaintTo(g); }
    }

    partial class Pet
    {
        // 搶課倒數徽章上的小學士帽（跟搶票的票券同一個位置、同樣大小）
        public static void DrawCapIcon(Graphics g, float x0, float y0, float w, float k, bool hot)
        {
            SmoothingMode was = g.SmoothingMode;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            // 斜看的方帽：扁扁的菱形帽頂、底下一圈帽身、右邊垂一條流蘇
            using (SolidBrush board = new SolidBrush(Color.FromArgb(0xFF, 0xD8, 0x4A)))
            using (SolidBrush cap = new SolidBrush(Color.FromArgb(0xC8, 0x8A, 0x22)))
            {
                g.FillPolygon(cap, new PointF[] { new PointF(x0 + 2.0f * k, y0 + 3.0f * k), new PointF(x0 + w - 2.0f * k, y0 + 3.0f * k), new PointF(x0 + w - 2.4f * k, y0 + 6.0f * k), new PointF(x0 + 2.4f * k, y0 + 6.0f * k) });
                g.FillPolygon(board, new PointF[] { new PointF(x0 - 0.6f * k, y0 + 2.4f * k), new PointF(x0 + w / 2, y0 + 0.4f * k), new PointF(x0 + w + 0.6f * k, y0 + 2.4f * k), new PointF(x0 + w / 2, y0 + 4.2f * k) });
            }
            using (Pen tassel = new Pen(hot ? Color.White : Color.FromArgb(0xF0, 0x5A, 0x4A), Math.Max(1.2f, 0.9f * k)))
            {
                g.DrawLine(tassel, x0 + w / 2, y0 + 2.3f * k, x0 + w - 0.2f * k, y0 + 2.9f * k);
                g.DrawLine(tassel, x0 + w - 0.2f * k, y0 + 2.9f * k, x0 + w - 0.2f * k, y0 + 6.4f * k);
            }
            g.SmoothingMode = was;
        }
    }

    // 「考試倒數…」的小視窗（跟「搶票提醒…」同一個樣子）
    class ExamForm : Form
    {
        readonly World w;
        readonly TextBox name = new TextBox(), time = new TextBox();
        readonly DateTimePicker date = new DateTimePicker();
        readonly Label hint = new Label();
        public ExamForm(World w, Color accent)
        {
            this.w = w;
            Text = "📚 考試倒數";
            FormBorderStyle = FormBorderStyle.FixedToolWindow;
            ShowInTaskbar = false; TopMost = true; MaximizeBox = false; MinimizeBox = false;
            BackColor = Color.FromArgb(0xFF, 0xFB, 0xF4);
            Font = new Font("Microsoft JhengHei UI", 10f);
            AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(360, 200);
            int y0 = 12;
            AddLabel("什麼考試？（例如：微積分期末考）", y0); name.Location = new Point(14, y0 + 22); name.Width = 332; Controls.Add(name);
            AddLabel("考試日期與開始時間", y0 + 56);
            date.Format = DateTimePickerFormat.Custom; date.CustomFormat = "yyyy-MM-dd"; date.Location = new Point(14, y0 + 78); date.Width = 150; Controls.Add(date);
            time.Location = new Point(176, y0 + 78); time.Width = 80; time.Text = "09:00"; Controls.Add(time);
            Label tip = new Label(); tip.Text = "考前兩週每天倒數、前一天晚上和當天早上提醒"; tip.Location = new Point(14, y0 + 110); tip.AutoSize = true; tip.ForeColor = Color.FromArgb(0x80, 0x70, 0x60); Controls.Add(tip);
            Button ok = new Button(); ok.Text = "好，幫我倒數"; ok.Location = new Point(206, y0 + 138); ok.Size = new Size(140, 34);
            ok.FlatStyle = FlatStyle.Flat; ok.BackColor = accent; ok.ForeColor = Color.White; ok.FlatAppearance.BorderSize = 0;
            ok.Click += delegate { Submit(); };
            Controls.Add(ok);
            hint.Location = new Point(14, y0 + 146); hint.AutoSize = true; hint.ForeColor = Color.FromArgb(0xB0, 0x40, 0x40); Controls.Add(hint);
            AcceptButton = ok;
            KeyPreview = true;
            KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Escape) Hide(); };
            FormClosing += delegate(object s, FormClosingEventArgs e) { if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); } };
        }

        public void FocusFirst() { name.Select(); name.Focus(); }

        void AddLabel(string s, int y) { Label l = new Label(); l.Text = s; l.Location = new Point(14, y); l.AutoSize = true; Controls.Add(l); }

        void Submit()
        {
            DateTime t;
            string tm = time.Text.Trim().Replace("：", ":");
            if (name.Text.Trim() == "") { hint.Text = "什麼考試呢？"; name.Focus(); return; }
            if (!DateTime.TryParse(date.Value.ToString("yyyy-MM-dd") + " " + tm, out t)) { hint.Text = "時間看不懂，例如 09:00"; return; }
            if (t < DateTime.Now) { hint.Text = "這個時間已經過了喔"; return; }
            long ms = (long)(t.ToUniversalTime() - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalMilliseconds;
            w.AddExam(ms, name.Text.Trim(), "me", null, true);
            name.Text = ""; hint.Text = "";
            Hide();
        }
    }

    // ================= 讀書小幫手設定（公仔小屋 →「讀書小幫手設定…」）：跟第一次設定同一套像素樣子 =================
    // 學校行事曆網址（一行一個）、上課前幾分鐘、上課中自動安靜、熬夜提醒（幾點開始）、考試倒數幾點講。
    // VS Code 推過來的那幾項會鎖住並寫「由 VS Code 設定」。
    class StudySettingsForm : Form
    {
        readonly World w;
        readonly double d;
        readonly int U;
        readonly TextBox urls = new TextBox(), remind = new TextBox(), lateAt = new TextBox(), nudge = new TextBox();
        bool autoQuiet, lateOn;
        string hoverId = "", err = "";
        readonly Font titleF, labF, subF, btnF, boxF;
        public bool VVisible;
        readonly Dictionary<string, Rectangle> hits = new Dictionary<string, Rectangle>();
        static readonly Color Locked = Color.FromArgb(0xF1, 0xE8, 0xD8);   // 由 VS Code 管的欄位：灰一點、不能改

        public StudySettingsForm(World w)
        {
            this.w = w;
            d = w.S / 4.0;
            U = Math.Max(2, (int)Math.Round(2 * d));
            Text = "公仔櫃・讀書小幫手設定";
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false; MinimizeBox = false;
            ShowInTaskbar = true; TopMost = true;
            StartPosition = FormStartPosition.Manual;
            BackColor = Pix.Cream;
            DoubleBuffered = true;
            titleF = new Font("Microsoft JhengHei UI", 12f, FontStyle.Bold);
            labF = new Font("Microsoft JhengHei UI", 10.5f, FontStyle.Bold);
            subF = new Font("Microsoft JhengHei UI", 8.5f, FontStyle.Bold);
            btnF = new Font("Microsoft JhengHei UI", 11f, FontStyle.Bold);
            boxF = new Font("Consolas", 9.5f);
            ClientSize = new Size(Sc(600), Sc(600));
            KeyPreview = true;
            KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Escape) Close(); };
            foreach (TextBox t in new TextBox[] { urls, remind, lateAt, nudge })
            {
                t.BorderStyle = BorderStyle.None; t.BackColor = Color.FromArgb(0xFF, 0xFD, 0xF7); t.ForeColor = Pix.TextC;
                t.Font = t == urls ? boxF : new Font("Microsoft JhengHei UI", 10.5f, FontStyle.Bold);
                Controls.Add(t);
            }
            urls.Multiline = true; urls.ScrollBars = ScrollBars.Vertical; urls.WordWrap = false; urls.AcceptsReturn = true;
            remind.TextAlign = lateAt.TextAlign = nudge.TextAlign = HorizontalAlignment.Center;
            int x = Sc(36);
            urls.Bounds = new Rectangle(x + U, Sc(118) + U, ClientSize.Width - 2 * x - 2 * U, Sc(96) - 2 * U);
            remind.Bounds = Field(Sc(330), Sc(66));
            lateAt.Bounds = Field(Sc(406), Sc(66));
            nudge.Bounds = Field(Sc(468), Sc(66));
            Reload();
        }

        int Sc(int v) { return (int)Math.Round(v * d); }
        Rectangle Field(int y, int wd) { int h = Sc(26); return new Rectangle(ClientSize.Width - Sc(36) - wd + 2 * U, y + (h - Sc(18)) / 2, wd - 4 * U, Sc(18)); }

        public void Reload()
        {
            urls.Text = string.Join("\r\n", w.StudyUrls());
            remind.Text = w.ClassRemind.ToString();
            autoQuiet = w.ClassAutoQuiet; lateOn = w.LateOn;
            lateAt.Text = (w.LateStart / 60).ToString("00") + ":" + (w.LateStart % 60).ToString("00");
            nudge.Text = w.ExamNudge < 0 ? "" : (w.ExamNudge / 60).ToString("00") + ":" + (w.ExamNudge % 60).ToString("00");
            urls.ReadOnly = w.FromVsCode("urls"); remind.ReadOnly = w.FromVsCode("remind");
            lateAt.ReadOnly = w.FromVsCode("late"); nudge.ReadOnly = w.FromVsCode("nudge");
            foreach (TextBox t in new TextBox[] { urls, remind, lateAt, nudge }) t.BackColor = t.ReadOnly ? Locked : Color.FromArgb(0xFF, 0xFD, 0xF7);
            err = "";
            Invalidate();
        }

        // ---- 離屏測試模式：不真的顯示，snap 時畫到虛擬螢幕上（輸入框另外畫）----
        protected override void SetVisibleCore(bool value)
        {
            if (App.Offscreen) { VVisible = value; base.SetVisibleCore(false); return; }
            base.SetVisibleCore(value);
        }
        public void PaintTo(Graphics g)
        {
            Size cs = ClientSize;
            using (Bitmap b = new Bitmap(cs.Width, cs.Height, PixelFormat.Format24bppRgb))
            {
                using (Graphics gg = Graphics.FromImage(b))
                {
                    OnPaint(new PaintEventArgs(gg, new Rectangle(0, 0, cs.Width, cs.Height)));
                    foreach (TextBox t in new TextBox[] { urls, remind, lateAt, nudge })
                    {
                        using (SolidBrush bg = new SolidBrush(t.BackColor)) gg.FillRectangle(bg, t.Bounds);
                        string s = t.Multiline ? t.Text : t.Text;
                        TextRenderer.DrawText(gg, s, t.Font, t.Bounds, t.ForeColor, t.Multiline ? TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.NoPrefix : Pix.Mid);
                    }
                }
                g.DrawImageUnscaled(b, Left, Top);
            }
        }

        public void TestSet(string field, string value)
        {
            if (field == "urls") urls.Text = value.Replace(" ", "\r\n");
            else if (field == "remind") remind.Text = value;
            else if (field == "late") lateAt.Text = value;
            else if (field == "nudge") nudge.Text = value;
            else if (field == "autoquiet") autoQuiet = value == "1";
            else if (field == "lateon") lateOn = value == "1";
            Invalidate();
        }

        public void Save()
        {
            List<string> list = new List<string>();
            foreach (string line in urls.Text.Split(new char[] { '\r', '\n', ' ', ',' }, StringSplitOptions.RemoveEmptyEntries))
            {
                string s = line.Trim();
                if (s.StartsWith("webcal", StringComparison.OrdinalIgnoreCase)) s = "https" + s.Substring(s.IndexOf("://", StringComparison.Ordinal) < 0 ? 6 : s.IndexOf("://", StringComparison.Ordinal));
                if (!s.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) { err = "網址要 https:// 或 webcal:// 開頭：" + (s.Length > 30 ? s.Substring(0, 30) + "…" : s); Invalidate(); return; }
                list.Add(s);
            }
            int rm;
            if (!int.TryParse(remind.Text.Trim(), out rm) || rm < 1 || rm > 120) { err = "上課前幾分鐘：打 1～120"; Invalidate(); return; }
            int ls = HmOf(lateAt.Text);
            if (lateOn && ls < 0) { err = "熬夜提醒的時間看不懂，例如 01:00"; Invalidate(); return; }
            int ng = nudge.Text.Trim() == "" ? -1 : HmOf(nudge.Text);
            if (nudge.Text.Trim() != "" && ng < 0) { err = "考試倒數的時間看不懂，例如 20:00（空白＝不要每天倒數）"; Invalidate(); return; }
            w.ApplyStudySettings(list, rm, autoQuiet, lateOn, ls, ng);
            Close();
        }

        static int HmOf(string s)
        {
            string[] a = (s ?? "").Trim().Replace("：", ":").Split(':');
            int h, m;
            if (a.Length == 2 && int.TryParse(a[0], out h) && int.TryParse(a[1], out m) && h >= 0 && h < 24 && m >= 0 && m < 60) return h * 60 + m;
            return -1;
        }

        string HitAt(Point p) { foreach (KeyValuePair<string, Rectangle> kv in hits) if (kv.Value.Contains(p)) return kv.Key; return ""; }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            string h = HitAt(e.Location);
            if (h != hoverId) { hoverId = h; Cursor = h != "" ? Cursors.Hand : Cursors.Default; Invalidate(); }
        }
        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (e.Button != MouseButtons.Left) return;
            string h = HitAt(e.Location);
            if (h == "save") Save();
            else if (h == "cancel") Close();
            else if (h == "autoquiet" && !w.FromVsCode("autoquiet")) { autoQuiet = !autoQuiet; Invalidate(); }
            else if (h == "lateon" && !w.FromVsCode("late")) { lateOn = !lateOn; Invalidate(); }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.None;
            hits.Clear();
            int W0 = ClientSize.Width, H0 = ClientSize.Height, F = 4 * U, crown = Sc(56), x = Sc(36);
            Pix.Wood(g, 0, 0, W0, H0, U, false, 23);
            Pix.Panel(g, F, crown, W0 - 2 * F, H0 - crown - F, U, false);
            string t = "讀書小幫手設定";
            int tw = Pix.TextW(t, titleF), plw = tw + 14 * U, plh = Sc(34);
            Rectangle pr = new Rectangle((W0 - plw) / 2, (crown - plh) / 2 + U / 2, plw, plh);
            Pix.Plate(g, t, titleF, pr, U);
            Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.X - 9 * U, pr.Y + plh / 2 - 2 * U, U);
            Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.Right + 4 * U, pr.Y + plh / 2 - 2 * U, U);
            Color brown = Pix.C(0x9A6338);

            // 學校行事曆
            DrawLabel(g, "🎒 學校行事曆（ICS 網址，一行一個）", x, Sc(70), labF, Pix.TextC);
            DrawLabel(g, w.FromVsCode("urls") ? "由 VS Code 設定（deskPals.schoolIcsUrl）" : "上課前提醒、上課中安靜；作業截止前 3 天、1 天、3 小時、1 小時提醒", x, Sc(94), subF, brown);
            Frame(g, new Rectangle(x, Sc(118), W0 - 2 * x, Sc(96)), urls.ReadOnly);
            string[] how = {
                "Canvas／NTU COOL：行事曆 → 右邊「行事曆摘要」(Calendar Feed)",
                "Moodle：行事曆 → 匯入或匯出行事曆 → 匯出 → 取得行事曆網址",
                "Google Classroom、Google 日曆：日曆設定 →「iCal 格式的私密網址」" };
            for (int i = 0; i < how.Length; i++) DrawLabel(g, "・" + how[i], x, Sc(222) + i * Sc(18), subF, brown);
            DrawLabel(g, w.SchoolStatus(), x, Sc(282), subF, Pix.C(0x3F8A30));

            Dots(g, x, Sc(312), W0 - 2 * x);
            // 上課
            DrawLabel(g, "上課、考試前幾分鐘提醒" + (remind.ReadOnly ? "（由 VS Code 設定）" : ""), x, Sc(330) + Sc(4), labF, remind.ReadOnly ? Pix.Dim : Pix.TextC);
            Frame(g, new Rectangle(W0 - x - Sc(66), Sc(330), Sc(66), Sc(26)), remind.ReadOnly);
            Toggle(g, "autoquiet", "上課、考試時自動安靜到下課", autoQuiet, x, Sc(368), w.FromVsCode("autoquiet"));
            // 熬夜
            bool lk = w.FromVsCode("late");
            Toggle(g, "lateon", "熬夜提醒：過了這個時間還在用電腦，就催你去睡", lateOn, x, Sc(406), lk);
            Frame(g, new Rectangle(W0 - x - Sc(66), Sc(406), Sc(66), Sc(26)), lateAt.ReadOnly);
            DrawLabel(g, lk ? "由 VS Code 設定（deskPals.lateNightStart）" : "之後每一小時再講一次（最多三次）；你離開電腦、安靜、專注時不吵", x + Sc(30), Sc(436), subF, brown);
            // 考試
            DrawLabel(g, "考試倒數每天幾點講（空白＝不要）" + (nudge.ReadOnly ? "（由 VS Code 設定）" : ""), x, Sc(468) + Sc(4), labF, nudge.ReadOnly ? Pix.Dim : Pix.TextC);
            Frame(g, new Rectangle(W0 - x - Sc(66), Sc(468), Sc(66), Sc(26)), nudge.ReadOnly);

            if (err != "") DrawLabel(g, err, x, Sc(506), subF, Pix.C(0xB04040));
            int by = H0 - Sc(64), bh = Sc(44);
            DrawButton(g, "cancel", "取消", new Rectangle(Sc(30), by, Sc(130), bh), false);
            DrawButton(g, "save", "儲存", new Rectangle(W0 - Sc(30) - Sc(160), by, Sc(160), bh), true);
        }

        void DrawLabel(Graphics g, string s, int x, int y, Font f, Color c) { PixText.DrawText(g, World.NoEmoji(s), f, new Point(x, y), c, TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding); }

        // 輸入框的像素框（深木色外框、上面一條陰影）
        void Frame(Graphics g, Rectangle r, bool locked)
        {
            Pix.Round(g, locked ? Pix.Dim : Pix.C(0x8A6A4A), r.X, r.Y, r.Width, r.Height, U);
            Pix.Box(g, locked ? Locked : Color.FromArgb(0xFF, 0xFD, 0xF7), r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            Pix.Box(g, Pix.C(0xEAD7B4), r.X + U, r.Y + U, r.Width - 2 * U, U);
        }

        void Dots(Graphics g, int x, int y, int wd) { for (int sx = x; sx + U <= x + wd; sx += 3 * U) Pix.Box(g, Pix.C(0xD8BF94), sx, y, U, U); }

        // 像素勾勾開關（跟小屋選單的開關一樣：打勾＝開著）
        void Toggle(Graphics g, string id, string text, bool on, int x, int y, bool locked)
        {
            int s = Sc(20);
            Rectangle r = new Rectangle(x, y + (Sc(26) - s) / 2, s, s);
            Pix.Round(g, locked ? Pix.Dim : Pix.Ink, r.X, r.Y, s, s, U);
            Pix.Box(g, on ? Pix.C(0x5FB04A) : Color.FromArgb(0xFF, 0xFD, 0xF7), r.X + U, r.Y + U, s - 2 * U, s - 2 * U);
            if (on) Pix.Mono(g, Pix.CHECK, Color.White, r.X + (s - 5 * U) / 2, r.Y + (s - 5 * U) / 2, U);
            Color tc = locked ? Pix.Dim : (hoverId == id ? Pix.C(0x8A5A2A) : Pix.TextC);
            DrawLabel(g, text + (locked && id != "lateon" ? "（由 VS Code 設定）" : ""), x + s + Sc(10), y + Sc(4), labF, tc);
            hits[id] = new Rectangle(x, y, s + Sc(10) + Pix.TextW(World.NoEmoji(text), labF), Sc(26));
        }

        void DrawButton(Graphics g, string id, string text, Rectangle r, bool main)
        {
            bool hot = hoverId == id;
            Color face = main ? (hot ? Pix.C(0xFFD36A) : Pix.C(0xF6C453)) : (hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0));
            Color shade = main ? Pix.C(0xC8902C) : Pix.C(0xDCC6A2);
            Pix.Round(g, Pix.Ink, r.X, r.Y, r.Width, r.Height, U);
            Pix.Box(g, face, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            Pix.Box(g, shade, r.X + U, r.Bottom - 3 * U, r.Width - 2 * U, 2 * U);
            Pix.Box(g, Pix.Mix(face, Color.White, 0.6), r.X + 2 * U, r.Y + U, r.Width - 4 * U, U);
            PixText.DrawText(g, text, btnF, new Rectangle(r.X, r.Y, r.Width, r.Height - 2 * U), Pix.TextC, Pix.Mid);
            hits[id] = r;
        }
    }
}
