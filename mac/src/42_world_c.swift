// 42_world_c.swift — port of DeskPals.cs lines 8108–9616
// (notices, quiet/focus, reminders, PC health, downloads, daily wrap, tickets, lunch, previews)

import Foundation
import AppKit
import Darwin

// ================= 通知（CI、會議、Jira、工作日誌…）與番茄鐘 =================
//@@IN World
    var heldShare = List<Notice>()   // 分享螢幕／全螢幕時先存著
    var heldFocus = List<Notice>()   // 專注時先存著（低／一般）
    var current: Notice! = nil
    // ---------- 放大敲玻璃的全域冷卻（所有公仔共用一個）----------
    var lastZoom: Double = -1e9, lastAmbientZoom: Double = -1e9
    // ---------- 安靜一下（勿擾）----------
    var quietOn = false
    var quietEnd: Double = 0
    var lastQuietLeft = -1
    var heldQuiet = List<Notice>()
    // ---------- 番茄鐘 ----------
    var focusOn = false
    var breakOn = false
    var focusEnd: Double = 0, breakEnd: Double = 0
    var focusMin = 25, lastFocusLeft = -1
    // ================= 1) 提醒我 =================
    var reminders = List<Reminder>()
    var dueReminder: Reminder! = nil
    var remForm: ReminderForm! = nil
    // ================= 2) 電腦健康 =================
    var companyHost = ""
    var healthCd = Dict<String, DateTime>()
    // ================= 3) 下載完成 =================
    var dlWatch: DispatchSourceFileSystemObject? = nil   // mac: FileSystemWatcher → DispatchSource on the directory + diff listing
    var dlKnown: [String: String] = [:]                   // mac: 上次看到的目錄內容（名字 → 大小/時間），用來比對
    var dlPending = Dict<String, Arr<Int>>()   // 路徑 → {大小, 穩定起點 ticks}
    var dlCheck: Double = 0
    // ================= 4) 今天的我們 =================
    var day = Dict<String, Int>()
    var dayKey = ""
    var wrapShown = false
    // ================= 搶票提醒 =================
    var tickets = List<Ticket>()
    var ticketForm: TicketForm! = nil
    // ================= 午餐時間 =================
    var LunchState = ""          // "" / eat / nap / soon
    var forceLunch = -1                    // -1 照時間、1 強制開飯、2 強制午睡、0 強制結束
    var lunchChecked = -1
//@@END

extension World {
    final class Notice { var Kind: String! = nil, Url: String! = nil, Text: String! = nil; var Pri = 0; var At = DateTime.Now; var By: Pet! = nil; var Expire: Double = 0; var Repeated = false; var NextRound = false; init() {} }

    static func Priority(_ kind: String) -> Int {
        let sp = StudyPriority(kind); if sp >= 0 { return sp }   // 上課、考試、作業死線
        switch kind {
        case "ci-fail", "meeting", "meeting-now", "remind": return 2
        case "ci-ok", "cmd-fail", "jira", "pc-cpu", "pc-ram", "pc-disk", "net-down", "vpn": return 1
        default: break
        }
        return 0
    }

    // 只接受 http/https，或指向本機存在檔案的 file:///
    static func SafeUrl(_ u: String!) -> String! {
        if string.IsNullOrEmpty(u) || u == "-" { return nil }
        guard let uri = URL(string: u), let scheme = uri.scheme?.lowercased(), !scheme.isEmpty else { return nil }
        if scheme == "http" || scheme == "https" { return uri.absoluteString }
        if scheme == "file" && uri.isFileURL && FileManager.default.fileExists(atPath: uri.path) { return uri.path }
        return nil
    }

    // mac: Process.Start(url) → NSWorkspace.open（本機檔案路徑或 http/https）
    static func OpenUrl(_ u: String) -> Bool {
        let url: URL? = u.hasPrefix("/") ? URL(fileURLWithPath: u) : URL(string: u)
        guard let uu = url else { return false }
        return NSWorkspace.shared.open(uu)
    }

    // notify <kind> <url|-> <text...>
    func OnNotify(_ kind: String, _ url: String, _ text: String) {
        let n = Notice()
        n.Kind = kind; n.Url = World.SafeUrl(url); n.Text = text; n.Pri = World.Priority(kind); n.At = DateTime.Now
        if kind.StartsWith("meeting") { Count("meetings") }
        if kind == "ci-ok" || kind == "ci-fail" { Count("deploys") }
        if url != "-" && n.Url == nil { App.Log("notify: rejected url " + url) }
        if sharing || fsNow { heldShare.Add(n); return }
        if quietOn {
            // 安靜中：會議、CI 失敗還是說，但只冒泡泡；其他先存著
            if World.MeetingLike(n.Kind) || n.Kind == "ci-fail" { DeliverGentle(n); return }
            heldQuiet.Add(n); return
        }
        if focusOn && n.Pri < 2 { heldFocus.Add(n); return }
        Deliver(n, false)
    }

    // 分享／全螢幕結束 → 補送（太舊的丟掉；會議過了就不提）
    func FlushShareHeld() {
        if sharing || fsNow || heldShare.Count == 0 { return }
        let l = List<Notice>(heldShare); heldShare.Clear()
        var d = 1.5
        for n in l {
            let age = (DateTime.Now - n.At).TotalMinutes
            if age > 10 || (n.Kind == "meeting-now" && age > 2) || (n.Kind == "meeting" && age > 5) { continue }
            let nn = n
            Later(d) { if self.focusOn && nn.Pri < 2 { self.heldFocus.Add(nn) } else { self.Deliver(nn, false) } }
            d += 4
        }
    }

    static func Flavor(_ id: String, _ kind: String, _ night: Bool) -> String {
        let pk = PikFlavor(id, kind) ?? OrigFlavor(id, kind); if pk != nil { return pk! }   //@fan
        // <public> let pk = OrigFlavor(id, kind); if pk != nil { return pk! }
        let cu = CuFlavor(id, kind, night); if cu != nil { return cu! }
        let sd = StudyFlavor(id, kind); if sd != nil { return sd! }
        let extra = FlavorExtra(id, kind)
        if extra != nil { return extra! }
        if night && kind == "worklog" {
            switch id {
            // <fan>
            case "po": return "日誌好了…太陽寶寶下山了，回家吧："
            case "stitch": return "日誌好了…Ohana 在家等你："
            case "hangyodon": return "日誌好了…大家都回家了，你也回家吧："
            case "tinky": return "日誌好了…太陽寶寶下山了，丁丁說再見："
            case "dipsy": return "日誌好了…帽子戴好，回家吧："
            case "laalaa": return "日誌好了…啦…該回家囉："
            // </fan>
            default: return "日誌好了。然後下班："
            }
        }
        let keys: [String] = ["ci-run", "ci-ok", "ci-fail", "cmd-ok", "cmd-fail", "meeting", "meeting-now", "jira", "worklog"]
        let sp: [String] = ["Thwip～CI 跑起來了：", "CI 過了！帥！", "蜘蛛感應！CI 掛了：", "指令跑完了：", "嗯？指令失敗了：", "等等要開會喔：", "會議開始了！快去：", "有新的 Jira：", "今天的工作日誌好了："]   //@fan
        // <public> let sp: [String] = ["CI 跑起來了：", "CI 過了！帥！", "CI 掛了：", "指令跑完了：", "嗯？指令失敗了：", "等等要開會喔：", "會議開始了！快去：", "有新的 Jira：", "今天的工作日誌好了："]
        // <fan>
        let po: [String] = ["嘟嘟～CI 出發：", "全壘打！", "嗚…CI 摔倒了：", "好棒棒，跑完了：", "咦？沒成功：", "等一下要開會會喔：", "要開會了！快快：", "有新任務喔：", "今天的日誌寫好了～"]
        let st: [String] = ["ih! CI 在跑：", "CI 過了！嘻嘻嘻", "ih-ih-ih! CI 壞掉了：", "跑完了！", "失敗！史迪仔去咬它：", "等等開會！", "開會！快去！", "新的 Jira！", "日誌好了，Aloha："]
        let hg: [String] = ["英雄報告：CI 出發了", "英雄報告：", "交給我這個英雄…CI 失敗了：", "英雄報告：指令跑完", "嗚，指令失敗了：", "等一下有會議喔：", "會議開始了！快去吧：", "有新的 Jira 喔：", "今天的日誌好了，辛苦了："]
        let ti: [String] = ["丁丁的魔法袋：CI 出發囉：", "CI 過了！丁丁跳舞～", "哎喲！CI 跌倒了：", "跑完了，好棒棒：", "哎喲，指令失敗了：", "等一下要開會喔：", "開會了！丁丁陪你去：", "魔法袋裡有新的 Jira：", "今天的日誌寫好了～"]
        let di: [String] = ["CI 跑起來了，酷：", "CI 過了。酷。", "CI 掛了…帽子先扶好：", "跑完了，嘿～", "指令失敗了，別慌：", "等等要開會：", "開會了，走吧：", "新的 Jira：", "日誌好了："]
        let la: [String] = ["啦啦～CI 出發：", "CI 過了！啦啦啦～", "哎呀，CI 摔倒了：", "跑完了！啦～", "咦？指令沒成功：", "等一下要開會喔：", "開會了！快快快：", "有新的 Jira 喔：", "今天的日誌好了～啦啦："]
        // </fan>
        let i = keys.firstIndex(of: kind) ?? -1
        if i < 0 { return "" }
        switch id { case "po": return po[i]; case "stitch": return st[i]; case "hangyodon": return hg[i]; case "tinky": return ti[i]; case "dipsy": return di[i]; case "laalaa": return la[i]; default: break }   //@fan
        return sp[i]
    }

    func Deliver(_ n: Notice, _ repeat_: Bool) {
        if Hidden && n.Pri >= 2 && userHidden && !sharing && !fsNow { userHidden = false; ApplyHidden() }
        if Hidden { heldShare.Add(n); return }
        let l: Pet = Lead()
        n.By = l
        let text = World.Flavor(l.P.Id, n.Kind, Night) + " " + n.Text
        let hint: String! = n.Url != nil ? "點我打開" : nil
        if n.Pri >= 2 {
            l.Notify(text, hint, 2, focusOn, World.MeetingLike(n.Kind))
            for p in OutPets() { if p !== l && !focusOn { p.React() } }
            if !repeat_ && !n.Repeated {
                let nn = n
                Later(60) { if self.current === nn && !nn.Repeated { nn.Repeated = true; self.Deliver(nn, true) } }
            }
        } else if n.Pri == 1 {
            l.Notify(text, hint, 1, focusOn, false)
            for p in OutPets() { if p !== l && rnd.NextDouble() < 0.4 && !focusOn { p.React() } }
        } else { l.Notify(text, hint, 0, focusOn, false) }
        if n.Url != nil || n.Pri >= 1 { n.Expire = Now + 120; current = n; l.SetClickableBubble(n.Url != nil) }
    }

    // 點了正在通知的那隻（或他的泡泡）：有網址就打開
    @discardableResult
    func NoticeClicked(_ p: Pet) -> Bool {
        if current == nil || current.By !== p || Now > current.Expire { return false }
        let n: Notice = current; current = nil
        p.SetClickableBubble(false)
        if n.NextRound { StartFocus(focusMin); return true }
        if ReminderClicked(p, n) { return true }
        if StudyClicked(p, n) { return true }   // 作業：打開／交了
        if MisClicked(p, n) { return true }     // 下班清場：把視窗叫回來
        if n.Url != nil {
            if World.OpenUrl(n.Url) { p.Say("好～幫你打開了 👍", 1.4) }
            else { App.Log("open url: failed " + n.Url); p.Say("打不開耶…", 1.4) }
        } else { p.Say("收到～", 1.0) }
        return true
    }

    func ExpireNotice() {
        if current != nil && Now > current.Expire { if current.By != nil { current.By.SetClickableBubble(false) }; current = nil }
    }

    // ---------- 放大敲玻璃的全域冷卻（所有公仔共用一個）----------
    func ZoomAllowed(_ kind: String) -> Bool {
        let idle: Double = Double(W.IdleSeconds())
        var ok: Bool
        if quietOn && kind != "user" { return false }
        if Lunch && kind != "user" && kind != "meeting" { return false }   // 午餐時間不放大（會議除外）
        switch kind {
        case "user": ok = true                                        // 選單「敲敲螢幕」：你自己叫的
        case "meeting": ok = Now - lastZoom >= 900
        case "high": ok = Now - lastZoom >= 900 && idle >= 20
        case "ambient": ok = Now - lastAmbientZoom >= 7200 && Now - lastZoom >= 900 && idle >= 120
        default: ok = false
        }
        if ok { lastZoom = Now; if kind == "ambient" { lastAmbientZoom = Now } }
        return ok
    }

    // ---------- 安靜一下（勿擾）----------
    func QuietLeft() -> Int { return quietOn ? Math.Max(0, CInt(Math.Ceiling((quietEnd - Now - 0.5) / 60.0))) : -1 }

    // 到今天下班（18:00）；已經過了就兩小時
    static func MinutesToOffWork() -> Int {
        let n = DateTime.Now, off = n.Date.AddHours(18)
        return n < off ? Math.Max(1, CInt(Math.Ceiling((off - n).TotalMinutes))) : 120
    }

    func StartQuiet(_ min: Int) {
        if min <= 0 { StopQuiet(); return }
        let was = quietOn
        // 只延長、不縮短（會議自動安靜不會把你手動設的兩小時變短）
        let end = Now + Double(Math.Min(min, 24 * 60) * 60)
        quietEnd = was ? Math.Max(quietEnd, end) : end
        quietOn = true
        AbortScene()
        for p in OutPets() { p.QuietDown() }
        if !was {
            let l: Pet = Lead()
            var line: String
            switch l.P.Id {
            // <fan>
            case "po": line = "噓～小波安靜陪你 🤫"
            case "stitch": line = "噓…史迪仔乖乖的"
            case "hangyodon": line = "好，我安靜待著…有事再叫我"
            case "tinky": line = "噓～丁丁抱著袋袋安靜陪你 🤫"
            case "dipsy": line = "噓。帽子拉低，安靜。"
            case "laalaa": line = "噓～拉拉小小聲 🤫"
            // </fan>
            default: line = l.P.Cu ? l.L("x_quiet_on") : "好，我安靜待著。"
            }
            l.Say(line, 2.2)
        }
        lastQuietLeft = QuietLeft()
        BroadcastQuiet()
    }

    func StopQuiet() {
        if !quietOn { return }
        quietOn = false
        BroadcastQuiet()
        let l: Pet = Lead()
        var line: String
        switch l.P.Id {
        // <fan>
        case "po": line = "安靜時間結束～Eh-oh!"
        case "stitch": line = "安靜結束！ih-ih!（小聲）"
        case "hangyodon": line = "安靜時間結束了…我好想講笑話"
        case "tinky": line = "安靜時間結束～Eh-oh!"
        case "dipsy": line = "安靜結束。嘿～"
        case "laalaa": line = "安靜時間結束～啦啦啦！"
        // </fan>
        default: line = l.P.Cu ? l.L("x_quiet_off") : "安靜時間結束～"
        }
        if heldQuiet.Count == 0 { l.Say(line, 2.4); return }
        // 一次說完：最新一則有網址就可以點
        let held = List<Notice>(heldQuiet); heldQuiet.Clear()
        let parts = List<String>()
        var withUrl: Notice! = nil
        for n in held { let t: String = n.Text.Length > 18 ? n.Text.Substring(0, 18) + "…" : n.Text; parts.Add(t); if n.Url != nil { withUrl = n } }
        var text = "安靜時間結束～剛剛有 " + String(held.Count) + " 件事：" + string.Join("、", parts.ToArray())
        if text.Length > 70 { text = text.Substring(0, 70) + "…" }
        l.Say(text, 8, false, withUrl != nil ? "點我打開最新那則" : nil)
        if withUrl != nil { withUrl.By = l; withUrl.Expire = Now + 120; current = withUrl; l.SetClickableBubble(true) }
    }

    // 安靜時用的：只冒泡泡、不敲玻璃、不放大
    func DeliverGentle(_ n: Notice) {
        let l: Pet = Lead()
        n.By = l
        l.Say(World.Flavor(l.P.Id, n.Kind, Night) + " " + n.Text, 7, n.Pri >= 2, n.Url != nil ? "點我打開" : nil)
        if n.Url != nil { n.Expire = Now + 120; current = n; l.SetClickableBubble(true) }
    }

    // 安靜時把「做完了」「上版了」「休息一下」這類也先存起來
    @discardableResult
    func HoldIfQuiet(_ kind: String, _ text: String) -> Bool {
        if !quietOn { return false }
        let n = Notice(); n.Kind = kind; n.Text = text; n.At = DateTime.Now; n.Pri = 0
        heldQuiet.Add(n)
        return true
    }

    func QuietTick() {
        if !quietOn { return }
        if Now >= quietEnd { StopQuiet(); return }
        let left = QuietLeft()
        if left != lastQuietLeft { lastQuietLeft = left; BroadcastQuiet() }
    }

    func BroadcastQuiet() {
        let msg = quietOn ? "quiet on " + String(QuietLeft()) + "\n" : "quiet off\n"
        lock(clients) { for c in clients { World.Send(c, msg) } }
    }

    // ---------- 番茄鐘 ----------
    func FocusLeft() -> Int { return focusOn ? Math.Max(0, CInt(Math.Ceiling((focusEnd - Now - 0.5) / 60.0))) : -1 }

    func StartFocus(_ min: Int) {
        focusMin = Math.Max(1, Math.Min(120, min))
        focusOn = true; breakOn = false
        focusEnd = Now + Double(focusMin * 60)
        AbortScene()
        for p in OutPets() { p.QuietDown() }
        let l: Pet = Lead()
        l.Say(ExamNear() ? String(focusMin) + " 分鐘讀書開始 📚 我們安靜陪你" : String(focusMin) + " 分鐘專注開始 🍅 我們安靜陪你", 2.4)
        lastFocusLeft = FocusLeft()
        BroadcastFocus()
    }

    func StopFocus(_ done: Bool) {
        if !focusOn { return }
        focusOn = false
        BroadcastFocus()
        let l: Pet = Lead()
        if !done { l.Say("好，先不專注了～", 1.6); FlushFocusHeld(1); return }
        let n = BumpTomato()
        var end: String
        switch l.P.Id {
        // <fan>
        case "po": end = "專注結束！休息 5 分鐘 ☕ 好棒棒！"
        case "stitch": end = "專注結束！休息 5 分鐘 ☕ 嘻嘻嘻，史迪仔有乖乖"
        case "hangyodon": end = "專注結束！休息 5 分鐘 ☕ 你才是真正的英雄"
        case "tinky": end = "專注結束！休息 5 分鐘 ☕ 丁丁跳舞給你看"
        case "dipsy": end = "專注結束。休息 5 分鐘 ☕ 你很酷"
        case "laalaa": end = "專注結束！休息 5 分鐘 ☕ 啦啦啦～好棒棒"
        // </fan>
        default: end = l.P.Cu ? l.L("x_focus_end") : "專注結束！休息 5 分鐘 ☕ 你超強的"
        }
        l.Knock((ExamNear() ? end.Replace("專注結束", "讀書結束") : end) + "　今天第 " + String(n) + " 顆 🍅", "high")
        for p in OutPets() { if p !== l { p.React() } }
        breakOn = true; breakEnd = Now + 300
        FlushFocusHeld(5)
    }

    func FlushFocusHeld(_ delay: Double) {
        if heldFocus.Count == 0 { return }
        let l = List<Notice>(heldFocus); heldFocus.Clear()
        let lead: Pet = Lead()
        Later(delay) { lead.Say("專注的時候來了 " + String(l.Count) + " 則通知，一則一則跟你說～", 2.4) }
        var d = delay + 2.8
        for n in l { let nn = n; Later(d) { self.Deliver(nn, false) }; d += 4.5 }
    }

    func BumpTomato() -> Int {
        let f = "tomato-" + DateTime.Now.ToString("yyyyMMdd") + ".txt"
        var n = 0; _ = int.TryParse(World.ReadText(f), &n)
        n += 1
        World.WriteText(f, n.ToString())
        return n
    }

    func FocusTick() {
        if focusOn {
            if Now >= focusEnd { StopFocus(true); return }
            let left = FocusLeft()
            if left != lastFocusLeft { lastFocusLeft = left; BroadcastFocus() }
        } else if breakOn && Now >= breakEnd {
            breakOn = false
            let l: Pet = Lead()
            let n = Notice(); n.Kind = "focus"; n.Text = ""; n.Pri = 1; n.NextRound = true; n.By = l; n.Expire = Now + 120
            current = n
            l.SetClickableBubble(true)
            l.Say("休息結束～要再來一輪嗎？🍅", 6, false, "點我開始")
        }
    }

    func BroadcastFocus() {
        let msg = focusOn ? "focus on " + String(FocusLeft()) + "\n" : "focus off\n"
        lock(clients) { for c in clients { World.Send(c, msg) } }
    }
}

//@@IN Pet
    var bubbleHint: String! = nil
//@@END

extension Pet {
    func Say(_ s: String?, _ sec: Double, _ alert: Bool, _ hint: String?) { Say(s, sec, alert); bubbleHint = hint }

    // 通知：pri 2 高（敲玻璃＋感應＋長泡泡）、1 一般（走向滑鼠＋泡泡）、0 低（短泡泡）；專注時溫柔一點
    func Notify(_ text: String, _ hint: String!, _ pri: Int, _ gentle: Bool, _ meeting: Bool) {
        WakeIfSleep()
        if pri >= 2 {
            sense = gentle ? 1.2 : 2.8
            if !gentle { Knock(text, meeting ? "meeting" : "high") }
            else if Out && Grounded() { Jump(0, -180 * k) }
            Say(text, gentle ? 6 : 9, true, hint)
        } else if pri == 1 {
            if Out && Grounded() && !gentle {
                let wa: Rectangle = w.WA(Cx, y + Double(SH) / 2.0)
                seekX = Pet.Clamp(Double(Cursor.Position.X), Double(wa.Left + SW), Double(wa.Right - SW)); gotoSpeed = 1.6; SetState("goto", 3)
            }
            Say(text, 6, false, hint)
        } else { Say(text, 3, false, hint) }
        Bt = Math.Max(Bt, pri >= 2 ? 9.0 : (pri == 1 ? 6.0 : 3.0))
        bubblePri = Math.Max(1, pri)
    }

    func SetClickableBubble(_ on: Bool) { EnsureForms(); Bub.SetClickable(on, self); if !on { bubbleHint = nil } }

    // 專注時：安靜、不亂跑
    func QuietDown() {
        if !Out { return }
        if Grounded() && state != "sleep" { SetState("idle", R(4, 8)) }
        fetching = false
    }
    var Quiet: Bool { return w.focusOn || w.quietOn }
}

// ================= 提醒我、電腦健康、下載完成、今天的小結 =================
extension World {
    // ---------- 共用：每個角色的開場白 ----------
    static func FlavorExtra(_ id: String, _ kind: String) -> String! {
        let pk = PikFlavor(id, kind) ?? OrigFlavor(id, kind); if pk != nil { return pk! }   //@fan
        // <public> let pk = OrigFlavor(id, kind); if pk != nil { return pk! }
        let cu = CuFlavor(id, kind, false); if cu != nil { return cu! }
        let keys: [String] = ["remind", "pc-cpu", "pc-ram", "pc-disk", "net-down", "net-up", "vpn", "download"]
        let sp: [String] = ["⏰ 提醒你：", "蜘蛛感應！電腦好燙：", "蜘蛛感應！記憶體快滿了：", "硬碟快滿了：", "網路斷了！", "網路回來了 👍", "連不到公司網路（VPN 斷了？）", "下載好了："]   //@fan
        // <public> let sp: [String] = ["⏰ 提醒你：", "電腦好燙：", "記憶體快滿了：", "硬碟快滿了：", "網路斷了！", "網路回來了 👍", "連不到公司網路（VPN 斷了？）", "下載好了："]
        // <fan>
        let po: [String] = ["⏰ 小波提醒你：", "電腦好忙好熱喔：", "記憶體要滿滿了：", "硬碟快塞滿了：", "網路斷掉了！嗚…", "網路回來了！Eh-oh!", "連不到公司網路耶（VPN 斷了？）", "下載好了！"]
        let st: [String] = ["⏰ ih! 提醒你：", "ih-ih! 電腦在冒煙：", "記憶體快爆了：", "硬碟要滿了：", "網路斷了！史迪仔去咬線！", "網路回來了！嘻嘻嘻", "公司網路連不到（VPN 斷了？）", "下載好了！ih!"]
        let hg: [String] = ["⏰ 英雄提醒你：", "電腦好像很累了：", "記憶體快滿了喔：", "硬碟快滿了：", "網路斷了…交給我這個英雄！", "網路回來了～太好了", "連不到公司網路（VPN 斷了嗎？）", "下載好了喔："]
        let ti: [String] = ["⏰ 丁丁提醒你：", "電腦好燙…丁丁幫你扇扇：", "記憶體要滿了，跟魔法袋一樣：", "硬碟快塞滿了：", "網路斷了！哎喲…", "網路回來了！Eh-oh!", "連不到公司網路耶（VPN 斷了？）", "下載好了！放進魔法袋～"]
        let di: [String] = ["⏰ 迪西提醒你：", "電腦很燙，酷不起來：", "記憶體快滿了：", "硬碟快滿了：", "網路斷了，冷靜：", "網路回來了，酷。", "連不到公司網路（VPN 斷了？）", "下載好了，嘿："]
        let la: [String] = ["⏰ 拉拉提醒你：", "電腦好熱喔：", "記憶體快滿滿了：", "硬碟快塞滿了：", "網路斷掉了！嗚…", "網路回來了！啦啦啦～", "連不到公司網路耶（VPN 斷了？）", "下載好了！啦～"]
        // </fan>
        let i = keys.firstIndex(of: kind) ?? -1
        if i < 0 { return nil }
        switch id { case "po": return po[i]; case "stitch": return st[i]; case "hangyodon": return hg[i]; case "tinky": return ti[i]; case "dipsy": return di[i]; case "laalaa": return la[i]; default: break }   //@fan
        return sp[i]
    }

    // ================= 1) 提醒我 =================
    final class Reminder { var At = 0; var Text: String! = nil; init() {} }
    static func UnixMs(_ t: DateTime) -> Int { return CInt((t.ToUniversalTime() - DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalMilliseconds) }
    static func FromUnixMs(_ ms: Int) -> DateTime { return DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMilliseconds(Double(ms)).ToLocalTime() }

    func LoadReminders() {
        reminders.Clear()
        for line in World.ReadText("reminders.txt").Split("\n") {
            let tab = line.IndexOf("\t")
            var ms = 0
            if tab > 0 && long.TryParse(line.Substring(0, tab), &ms) { let r = Reminder(); r.At = ms; r.Text = line.Substring(tab + 1).Trim(); reminders.Add(r) }
        }
    }

    func SaveReminders() {
        let sb = StringBuilder()
        for r in reminders { sb.Append(String(r.At) + "\t" + r.Text.Replace("\t", " ").Replace("\n", " ") + "\n") }
        World.WriteText("reminders.txt", sb.ToString())
    }

    func AddReminder(_ at: Int, _ text: String!) {
        var text: String = text ?? ""
        if string.IsNullOrEmpty(text) { text = "（提醒）" }
        let r = Reminder(); r.At = at; r.Text = text
        reminders.Add(r)
        reminders.Sort { (a: Reminder, b: Reminder) -> Int in a.At < b.At ? -1 : (a.At > b.At ? 1 : 0) }
        SaveReminders()
        let l: Pet = Lead()
        l.Say("好～" + World.FromUnixMs(at).ToString("HH:mm") + " 提醒你：" + text, 2.4)
    }

    func ReminderTick() {
        if reminders.Count == 0 { return }
        let now = World.UnixMs(DateTime.Now)
        if reminders[0].At > now { return }
        let r = reminders[0]; reminders.RemoveAt(0); SaveReminders()
        dueReminder = r
        Count("reminders")
        OnNotify("remind", "-", r.Text)
    }

    // 提醒的泡泡被點了：好了／10 分鐘後再提醒
    func ReminderClicked(_ p: Pet, _ n: Notice) -> Bool {
        if n.Kind != "remind" { return false }
        let text: String = n.Text
        if App.Offscreen { p.Say("好了～", 1.2); App.Log("reminder done (offscreen): " + text); return true }
        let m = ContextMenuStrip()
        m.Items.Add("好了 👍", nil) { p.Say("好～辦好了！", 1.4) }
        m.Items.Add("10 分鐘後再提醒", nil) { self.AddReminder(World.UnixMs(DateTime.Now.AddMinutes(10)), text) }
        ShowMenu(m, "提醒", false)
        return true
    }

    func AddReminderMenus(_ items: ToolStripItemCollection) {
        items.Add("提醒我…", nil) { self.ShowReminderForm() }
        if reminders.Count > 0 {
            let my = ToolStripMenuItem("我的提醒（" + String(reminders.Count) + "）")
            for r in reminders {
                let rr = r
                let whenS: String = World.FromUnixMs(r.At).ToString("MM/dd HH:mm"); let txtS: String = r.Text.Length > 20 ? r.Text.Substring(0, 20) + "…" : r.Text; let label: String = whenS + "　" + txtS + "　（點一下取消）"
                my.DropDownItems.Add(label, nil) { self.reminders.Remove(rr); self.SaveReminders(); self.Lead().Say("取消了：" + rr.Text, 1.8) }
            }
            items.Add(my)
        }
    }

    // 解析「15:30」或「45」（分鐘）
    static func ParseWhen(_ s0: String!) -> Int {
        let s = (s0 ?? "").Trim().Replace("：", ":")
        var min = 0
        if int.TryParse(s, &min) && min > 0 { return UnixMs(DateTime.Now.AddMinutes(Double(min))) }
        var t = DateTime.Now
        if s.Contains(":") && DateTime.TryParse(DateTime.Now.ToString("yyyy-MM-dd ") + s, &t) {
            if t < DateTime.Now { t = t.AddDays(1) }
            return UnixMs(t)
        }
        return 0
    }

    func ShowReminderForm() {
        if App.Offscreen { return }
        if remForm == nil || remForm.IsDisposed { remForm = ReminderForm(self, Lead().P.Accent) }
        remForm.StartPosition = FormStartPosition.Manual
        let c: Point = Cursor.Position
        let wa: Rectangle = WA(Double(c.X), Double(c.Y))
        remForm.Location = Point(Math.Max(wa.Left, Math.Min(wa.Right - remForm.Width, c.X - remForm.Width / 2)), Math.Max(wa.Top, Math.Min(wa.Bottom - remForm.Height, c.Y - remForm.Height - 10)))
        remForm.Show()
        ActivateForm(remForm)
        remForm.FocusFirst()
        let rf: ReminderForm = remForm
        Later(0.2) { if rf.Visible { self.ActivateForm(rf); rf.FocusFirst() } }   // 再補一次，確定拿到鍵盤
    }

    // ================= 2) 電腦健康（背景執行緒，每 5 秒）=================
    // mac: GlobalMemoryStatusEx → host_statistics64(HOST_VM_INFO64)；MEMSTAT 只留 dwMemoryLoad
    final class MEMSTAT { var dwLength = 64, dwMemoryLoad = 0; init() {} }
    @discardableResult
    static func GlobalMemoryStatusEx(_ m: MEMSTAT) -> Bool {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        if kr != KERN_SUCCESS { return false }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        if total <= 0 { return false }
        // 跟「活動監視器」的「已使用記憶體」一樣：App 記憶體（internal − purgeable）＋ 聯動 ＋ 壓縮
        let usedPages = Double(stats.internal_page_count) - Double(stats.purgeable_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)
        let used = Math.Max(0.0, usedPages * Double(pageSize))
        m.dwMemoryLoad = Math.Min(100, CInt(used * 100.0 / total))
        return true
    }

    // mac: PerformanceCounter("% Processor Time") → host_statistics(HOST_CPU_LOAD_INFO) 兩次取樣的差
    final class CpuCounter {
        var lastBusy: UInt64 = 0, lastTotal: UInt64 = 0
        init() {}
        static func Ticks() -> (UInt64, UInt64)? {
            var info = host_cpu_load_info()
            var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
            }
            if kr != KERN_SUCCESS { return nil }
            let u = UInt64(info.cpu_ticks.0), s = UInt64(info.cpu_ticks.1), i = UInt64(info.cpu_ticks.2), n = UInt64(info.cpu_ticks.3)
            return (u + s + n, u + s + i + n)
        }
        @discardableResult
        func NextValue() -> Double {
            guard let (b, t) = CpuCounter.Ticks() else { return 0 }
            let db = b &- lastBusy, dt = t &- lastTotal
            lastBusy = b; lastTotal = t
            if dt == 0 || dt > t { return 0 }
            return Double(db) * 100.0 / Double(dt)
        }
    }

    func HealthLoop() {
        Thread.Sleep(15000)
        var cpu: CpuCounter! = nil
        if CpuCounter.Ticks() != nil { cpu = CpuCounter(); cpu.NextValue() } else { App.Log("cpu counter: host_statistics failed") }
        var cpuHighSince = DateTime.MaxValue, ramHighSince = DateTime.MaxValue, netDownSince = DateTime.MaxValue, vpnDownSince = DateTime.MaxValue, nextDisk = DateTime.Now, nextNet = DateTime.Now
        var netAlerted = false
        while !closing {
            do {
                let now = DateTime.Now
                if cpu != nil {
                    let v = cpu.NextValue()
                    if v > 90 { if cpuHighSince == DateTime.MaxValue { cpuHighSince = now } } else { cpuHighSince = DateTime.MaxValue }
                    if cpuHighSince != DateTime.MaxValue && (now - cpuHighSince).TotalSeconds >= 180 && HealthReady("pc-cpu") {
                        let top = World.TopProcess()
                        let t = "CPU 一直在 90% 以上" + (top != nil ? "（" + top! + " 最忙）" : "")
                        Post { self.OnNotify("pc-cpu", "-", t) }
                    }
                }
                let m = MEMSTAT()
                if World.GlobalMemoryStatusEx(m) {
                    if m.dwMemoryLoad > 90 { if ramHighSince == DateTime.MaxValue { ramHighSince = now } } else { ramHighSince = DateTime.MaxValue }
                    if ramHighSince != DateTime.MaxValue && (now - ramHighSince).TotalSeconds >= 120 && HealthReady("pc-ram") {
                        let load = m.dwMemoryLoad; Post { self.OnNotify("pc-ram", "-", "記憶體用了 " + String(load) + "%，關幾個分頁或程式吧") }
                    }
                }
                if now >= nextDisk {
                    nextDisk = now.AddMinutes(10)
                    // mac: DriveInfo(系統碟) → 開機磁碟（/）的可用空間
                    let root = URL(fileURLWithPath: "/")
                    if let rv = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeLocalizedNameKey]) {
                        var avail = Double(rv.volumeAvailableCapacityForImportantUsage ?? 0)
                        if avail <= 0 { avail = Double(rv.volumeAvailableCapacity ?? 0) }
                        let total = Double(rv.volumeTotalCapacity ?? 0)
                        let freeGb = avail / 1073741824.0, pct = avail * 100.0 / Math.Max(1.0, total)
                        if total > 0 && (freeGb < 10 || pct < 5) && HealthReady("pc-disk") {
                            let t = (rv.volumeLocalizedName ?? "/") + " 只剩 " + freeGb.ToString("0.0") + " GB"; Post { self.OnNotify("pc-disk", "-", t) }
                        }
                    }
                }
                if now >= nextNet {
                    nextNet = now.AddSeconds(10)
                    let up = World.TcpOk("1.1.1.1", 443) || World.TcpOk("8.8.8.8", 443)
                    if !up {
                        if netDownSince == DateTime.MaxValue { netDownSince = now }
                        if !netAlerted && (now - netDownSince).TotalSeconds > 30 && HealthReady("net-down") { netAlerted = true; Post { self.OnNotify("net-down", "-", "兩個地方都連不上") } }
                    } else {
                        if netAlerted { netAlerted = false; Post { self.OnNotify("net-up", "-", "可以上網了") } }
                        netDownSince = DateTime.MaxValue
                        var host = ""
                        lock(healthCd) { host = self.companyHost }
                        if host != "" {
                            let ok = World.TcpOk(host, 443) || World.TcpOk(host, 80)
                            if !ok { if vpnDownSince == DateTime.MaxValue { vpnDownSince = now } } else { vpnDownSince = DateTime.MaxValue }
                            if vpnDownSince != DateTime.MaxValue && (now - vpnDownSince).TotalSeconds > 30 && HealthReady("vpn") {
                                let h2 = host; Post { self.OnNotify("vpn", "-", h2 + " 連不到") }
                            }
                        }
                    }
                }
            }
            Thread.Sleep(5000)
        }
    }

    func HealthReady(_ kind: String) -> Bool {
        var ready = true
        lock(healthCd) {
            var until = DateTime.Now
            if healthCd.TryGetValue(kind, &until) && DateTime.Now < until { ready = false; return }
            healthCd[kind] = DateTime.Now.AddMinutes(30)
        }
        return ready
    }

    // mac: TcpClient.BeginConnect + 2.5 秒逾時 → 非阻塞 BSD socket connect + poll
    static func TcpOk(_ host: String, _ port: Int) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>? = nil
        if getaddrinfo(host, String(port), &hints, &res) != 0 || res == nil { return false }
        defer { freeaddrinfo(res) }
        var ai = res
        while let a = ai {
            let fd = socket(a.pointee.ai_family, a.pointee.ai_socktype, a.pointee.ai_protocol)
            if fd >= 0 {
                var one: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                let fl = fcntl(fd, F_GETFL, 0)
                _ = fcntl(fd, F_SETFL, fl | O_NONBLOCK)
                var ok = false
                let r = connect(fd, a.pointee.ai_addr, a.pointee.ai_addrlen)
                if r == 0 { ok = true }
                else if errno == EINPROGRESS {
                    var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    if poll(&pfd, 1, 2500) > 0 {
                        var err: Int32 = 0
                        var len = socklen_t(MemoryLayout<Int32>.size)
                        if getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len) == 0 && err == 0 { ok = true }
                    }
                }
                close(fd)
                if ok { return true }
            }
            ai = a.pointee.ai_next
        }
        return false
    }

    // 最忙的程式（只在要提醒時才算一次）
    // mac: 取樣 TotalProcessorTime → `ps -Aceo pcpu=,comm= -r` 第一名（ps 的 %CPU 是近期平均）
    static func TopProcess() -> String! {
        let p = Foundation.Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Aceo", "pcpu=,comm=", "-r"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return nil }
        for raw in out.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let sp = line.firstIndex(of: " ") else { continue }
            let name = String(line[sp...]).trimmingCharacters(in: .whitespaces)
            if name.isEmpty || name == "ps" || name == "kernel_task" { continue }
            return name
        }
        return nil
    }

    // ================= 3) 下載完成 =================
    static func DownloadsDir() -> String { return (NSHomeDirectory() as NSString).appendingPathComponent("Downloads") }

    // mac: 目錄內容快照（名字 → 大小＋修改時間），用來找出新增／改名／變動的檔案
    static func DlSnapshot(_ dir: String) -> [String: String] {
        var m: [String: String] = [:]
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return m }
        for nm in names {
            let p = (dir as NSString).appendingPathComponent(nm)
            if let a = try? FileManager.default.attributesOfItem(atPath: p) {
                let sz = (a[.size] as? NSNumber)?.int64Value ?? -1
                let mt = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                m[p] = String(sz) + "/" + String(mt)
            } else { m[p] = "?" }
        }
        return m
    }

    func StartDownloadWatch() {
        let dir = World.DownloadsDir()
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) || !isDir.boolValue { return }
        let fd = open(dir, O_EVTONLY)
        if fd < 0 { App.Log("download watch: open failed errno " + String(errno)); return }
        dlKnown = World.DlSnapshot(dir)
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .extend, .attrib], queue: DispatchQueue.main)
        src.setEventHandler { [weak self] in
            guard let me = self else { return }
            let now = World.DlSnapshot(dir)
            for (p, sig) in now where me.dlKnown[p] != sig { me.DlSeen(p) }
            me.dlKnown = now
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        dlWatch = src
    }

    static func DlIgnore(_ p: String) -> Bool {
        let ext = Path.GetExtension(p).ToLowerInvariant()
        let name = Path.GetFileName(p)
        return ext == ".crdownload" || ext == ".part" || ext == ".tmp" || ext == ".download" || ext == ".partial" || name.StartsWith("~") || name.StartsWith(".")
    }

    func DlSeen(_ p: String) {
        if World.DlIgnore(p) { return }
        dlPending[p] = Arr<Int>([-1, DateTime.Now.Ticks])
    }

    func DownloadTick(_ dt: Double) {
        dlCheck -= dt
        if dlCheck > 0 || dlPending.Count == 0 { return }
        dlCheck = 1
        let done = List<String>()
        for kv in dlPending {
            let path: String = kv.Key
            var isDir: ObjCBool = false
            // FileInfo 對資料夾是 Exists=false（Safari 的 .download 套件夾也一樣）
            if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) || isDir.boolValue { done.Add(path); continue }
            guard let a = try? FileManager.default.attributesOfItem(atPath: path), let szn = a[.size] as? NSNumber else { done.Add(path); continue }
            let len = Int(szn.int64Value)
            if len != kv.Value[0] { kv.Value[0] = len; kv.Value[1] = DateTime.Now.Ticks; continue }
            if len <= 0 || (DateTime.Now - DateTime(kv.Value[1])).TotalSeconds < 3 { continue }
            // mac: 沒有強制鎖；能開來讀就算好了
            guard let fh = FileHandle(forReadingAtPath: path) else { continue }
            fh.closeFile()
            done.Add(path)
            let uri = URL(fileURLWithPath: path).absoluteString, name = Path.GetFileName(path)
            OnNotify("download", uri, name)
        }
        for d in done { dlPending.Remove(d) }
    }

    // ================= 4) 今天的我們 =================
    func LoadDay() {
        let k = DateTime.Now.ToString("yyyyMMdd")
        if k == dayKey { return }
        dayKey = k; day.Clear(); wrapShown = false
        for line in World.ReadText("day-" + k + ".txt").Split("\n") {
            let a = line.Trim().Split("=")
            var v = 0
            if a.count == 2 && int.TryParse(a[1], &v) { if a[0] == "wrap" { wrapShown = v > 0 } else { day[a[0]] = v } }
        }
    }

    func Count(_ key: String) {
        LoadDay()
        var v = 0; _ = day.TryGetValue(key, &v); day[key] = v + 1
        SaveDay()
    }

    func SaveDay() {
        let sb = StringBuilder()
        for kv in day { sb.Append(kv.Key + "=" + String(kv.Value) + "\n") }
        if wrapShown { sb.Append("wrap=1\n") }
        World.WriteText("day-" + dayKey + ".txt", sb.ToString())
    }

    func Day(_ k: String) -> Int { LoadDay(); var v = 0; _ = day.TryGetValue(k, &v); return v }

    // 下班那一刻（或右鍵「今天的小結」）：一張小卡
    func DailyWrap(_ fromMenu: Bool) {
        LoadDay()
        if !fromMenu && wrapShown { return }
        wrapShown = true; SaveDay()
        var tom = 0; _ = int.TryParse(World.ReadText("tomato-" + DateTime.Now.ToString("yyyyMMdd") + ".txt"), &tom)
        let parts = List<String>()
        if Day("meetings") > 0 { parts.Add("開了 " + String(Day("meetings")) + " 場會") }
        if tom > 0 { parts.Add("吃了 " + String(tom) + " 顆番茄🍅" + World.WeekTomatoNote(tom)) }
        if Day("deploys") > 0 { parts.Add("上版／CI " + String(Day("deploys")) + " 次") }
        if Day("tasks") > 0 { parts.Add("Claude／Codex 幫你做完 " + String(Day("tasks")) + " 件事") }
        if Day("saves") > 0 { parts.Add("存檔 " + String(Day("saves")) + " 次") }
        if Day("reminders") > 0 { parts.Add("完成 " + String(Day("reminders")) + " 個提醒") }
        if Day("pats") > 0 { parts.Add("摸了我們 " + String(Day("pats")) + " 下") }
        StudyWrapParts(parts)   // 上了幾堂課、這週還有幾份作業、離考試幾天
        let outs: List<Pet> = OutPets()
        let l: Pet = Lead()
        if parts.Count == 0 { l.Say("今天很安靜呢～今天辛苦了 ♥", 4); return }
        var intro: String
        switch l.P.Id {
        // <fan>
        case "po": intro = "Eh-oh! 今天的我們："
        case "stitch": intro = "Aloha～今天的 Ohana 紀錄："
        case "hangyodon": intro = "英雄報告：今天的我們"
        case "tinky": intro = "Eh-oh! 丁丁的魔法袋裝了今天的我們："
        case "dipsy": intro = "嘿，今天的我們："
        case "laalaa": intro = "啦啦～今天的我們："
        // </fan>
        default: intro = l.P.Cu ? l.L("x_wrap") : "今天的我們："
        }
        if outs.Count >= 2 && !quietOn {
            // 大家輪流講一句
            Begin(outs.ToArray())
            At(0) { l.Say(intro, 2.2) }
            var t = 2.4
            var i = 0
            while i < parts.Count { let p: Pet = outs[(i + 1) % outs.Count]; let s = parts[i]; At(t) { p.Say(s, 2.6) }; t += 2.6; i += 1 }
            At(t) { for p in outs { p.Say("今天辛苦了 ♥", 3) } }
            At(t + 3) { }
            return
        }
        let sb = StringBuilder(intro)
        sb.Append("\n")
        var i = 0
        while i < parts.Count { sb.Append((i % 2 == 0 ? "" : "、") + parts[i] + (i % 2 == 1 && i + 1 < parts.Count ? "\n" : "")); i += 1 }
        sb.Append("\n今天辛苦了 ♥")
        l.Say(sb.ToString(), 9)
    }
}

// 「提醒我…」的小視窗（自己畫的樣子，不用 VB InputBox）
class ReminderForm: Form {
    var w: World
    let what = TextBox(), when = TextBox()
    let hint = Label()
    var pick = 0
    init(_ w: World, _ accent: Color) {
        self.w = w
        super.init()
        Text = "提醒我…"
        FormBorderStyle = FormBorderStyle.FixedToolWindow
        ShowInTaskbar = false; TopMost = true; MaximizeBox = false; MinimizeBox = false
        BackColor = Color.FromArgb(0xFF, 0xFB, 0xF4)
        Font = WorldC_Font("Microsoft JhengHei UI", 10)
        AutoScaleMode = AutoScaleMode.Dpi
        ClientSize = Size(340, 190)
        let l1 = Label(); l1.Text = "要提醒什麼？"; l1.Location = Point(14, 12); l1.AutoSize = true
        what.Location = Point(14, 34); what.Width = 312
        let l2 = Label(); l2.Text = "什麼時候？（可以打 15:30 或 45 分鐘）"; l2.Location = Point(14, 66); l2.AutoSize = true
        Controls.Add(l1); Controls.Add(what); Controls.Add(l2)
        let labels: [String] = ["10 分", "30 分", "1 小時", "下班前"]
        let mins: [Int] = [10, 30, 60, -1]
        for i in 0..<4 {
            let b = Button(); b.Text = labels[i]; b.Location = Point(14 + i * 79, 90); b.Size = Size(74, 28)
            b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderColor = accent; b.BackColor = Color.White
            let m = mins[i]
            b.Click = { [unowned self] in
                var t = m > 0 ? DateTime.Now.AddMinutes(Double(m)) : DateTime.Now.Date.AddHours(17).AddMinutes(50)
                if t < DateTime.Now { t = t.AddDays(1) }
                self.pick = World.UnixMs(t)
                self.when.Text = t.ToString("HH:mm")
            }
            Controls.Add(b)
        }
        when.Location = Point(14, 126); when.Width = 120
        when.TextChanged = { [unowned self] in self.pick = 0 }
        let ok = Button(); ok.Text = "好，提醒我"; ok.Location = Point(206, 122); ok.Size = Size(120, 32)
        ok.FlatStyle = FlatStyle.Flat; ok.BackColor = accent; ok.ForeColor = Color.White; ok.FlatAppearance.BorderSize = 0
        ok.Click = { [unowned self] in self.Submit() }
        hint.Location = Point(14, 162); hint.AutoSize = true; hint.ForeColor = Color.FromArgb(0xB0, 0x40, 0x40)
        Controls.Add(when); Controls.Add(ok); Controls.Add(hint)
        AcceptButton = ok
        KeyPreview = true
        KeyDown = { [unowned self] (e: KeyEventArgs) in if e.KeyCode == Keys.Escape { self.Hide() } }
        FormClosing = { [unowned self] (e: FormClosingEventArgs) in if e.CloseReason == CloseReason.UserClosing { e.Cancel = true; self.Hide() } }
    }

    func FocusFirst() { NSApp.activate(ignoringOtherApps: true); what.Select(); what.Focus() }

    func Submit() {
        if what.Text.Trim() == "" { hint.Text = "要提醒什麼呢？"; what.Focus(); return }
        let at = pick > 0 ? pick : World.ParseWhen(when.Text)
        if at <= 0 { hint.Text = "時間看不懂耶，試試 15:30 或 45"; return }
        w.AddReminder(at, what.Text.Trim())
        what.Text = ""; when.Text = ""; hint.Text = ""; pick = 0
        Hide()
    }
}

// ================= 搶票提醒 =================
// 你自己排的：不受安靜／專注影響。開賣前 1～2 小時、30 分、10 分（對時）、1 分、開賣當下，一段一段提醒。
extension World {
    final class Ticket { var At = 0; var Lead = 0; var Url: String! = nil, Name: String! = nil; var Stage = 0; var Kind = "ticket"; init() {} }   // Kind：ticket｜course（搶課）

    func LoadTickets() {
        tickets.Clear()
        for line in World.ReadText("tickets.txt").Split("\n") {
            let a = line.TrimEnd("\r").Split("\t")
            var at = 0, lead = 0, stage = 0
            if a.count >= 5 && long.TryParse(a[0], &at) && int.TryParse(a[1], &lead) && int.TryParse(a[3], &stage) {
                let t = Ticket(); t.At = at; t.Lead = lead; t.Url = a[2] == "-" ? nil : a[2]; t.Stage = stage; t.Name = a[4]
                if a.count >= 6 && a[5] == "course" { t.Kind = "course" }
                tickets.Add(t)
            }
        }
    }

    func SaveTickets() {
        let sb = StringBuilder()
        for t in tickets {
            let at: String = String(t.At), lead: String = String(t.Lead), stage: String = String(t.Stage)
            let url: String = t.Url ?? "-"
            let name: String = t.Name.Replace("\t", " ").Replace("\n", " ")
            var line: String = at + "\t" + lead + "\t" + url
            line += "\t" + stage + "\t" + name + "\t" + t.Kind + "\n"
            sb.Append(line)
        }
        World.WriteText("tickets.txt", sb.ToString())
    }

    func AddTicket(_ at: Int, _ lead: Int, _ url: String, _ name: String!) { AddTicket(at, lead, url, name, "ticket") }
    func AddTicket(_ at: Int, _ lead: Int, _ url: String, _ name: String!, _ kind: String) {
        let t = Ticket()
        let course = kind == "course"
        t.Kind = course ? "course" : "ticket"
        t.At = at; t.Lead = lead == 60 ? 60 : 120; t.Name = string.IsNullOrEmpty(name) ? (course ? "搶課" : "搶票") : name
        t.Url = World.SafeUrl(url)
        if t.Url != nil && !t.Url.StartsWith("http") { t.Url = nil }   // 購票頁只收 http/https
        // 已經過了的階段就不補（例如只剩 20 分鐘才設定，就從 10 分鐘那段開始）
        let st = World.StagesOf(t)
        let left = Double(at - World.UnixMs(DateTime.Now)) / 60000.0
        t.Stage = 0
        for s in 0..<st.count { if left <= Double(st[s]) { t.Stage = s + 1 } }
        if t.Stage - 1 >= 2 { t.Stage -= 1 }   // 已經進到 10 分鐘內：最近那段馬上講（含對時、倒數）
        tickets.Add(t)
        tickets.Sort { (a: Ticket, b: Ticket) -> Int in a.At < b.At ? -1 : (a.At > b.At ? 1 : 0) }
        SaveTickets()
        let tn: String = t.Name, when: String = World.FromUnixMs(at).ToString("MM/dd HH:mm"), hrs: String = String(t.Lead / 60)
        let msg: String = (course ? "🎓 記住了：" : "🎫 記住了：") + tn + "，" + when + (course ? " 開放選課" : " 開賣") + "，提前 " + hrs + " 小時叫你"
        Lead().Say(msg, 3)
    }

    static func StagesOf(_ t: Ticket) -> [Int] { return [t.Lead, 30, 10, 1, 0] }

    static func TicketLine(_ id: String, _ stage: Int, _ t: Ticket) -> String {
        if t.Kind == "course" { return CourseLine(id, stage, t) }   // 搶課：52_study.swift
        let h = String(t.Lead / 60) + " 小時", n: String = t.Name
        let pk = PikTicket(id, stage, n, h) ?? OrigTicket(id, stage, n, h); if pk != nil { return pk! }   //@fan
        // <public> let pk = OrigTicket(id, stage, n, h); if pk != nil { return pk! }
        let cu = CuTicket(id, stage, n, h); if cu != nil { return cu! }
        let sp: [String] = ["🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款", "🎫 " + n + " 再 30 分鐘開賣，網頁先開好", "🎫 " + n + " 剩 10 分鐘！蜘蛛感應全開", "🎫 準備！手指放在按鈕上", "🎫 開搶！！Thwip!"]   //@fan
        // <public> let sp: [String] = ["🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款", "🎫 " + n + " 再 30 分鐘開賣，網頁先開好", "🎫 " + n + " 剩 10 分鐘！", "🎫 準備！手指放在按鈕上", "🎫 開搶！！"]
        // <fan>
        let po: [String] = ["🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款喔", "🎫 " + n + " 再 30 分鐘！小波陪你等", "🎫 " + n + " 剩 10 分鐘！好緊張～", "🎫 準備！深呼吸～", "🎫 開搶！！衝衝衝！"]
        let st: [String] = ["🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款！ih!", "🎫 " + n + " 30 分鐘！史迪仔幫你顧著", "🎫 " + n + " 10 分鐘！ih-ih-ih!", "🎫 準備！史迪仔也準備好了", "🎫 開搶！！衝啊！"]
        let hg: [String] = ["🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款", "🎫 " + n + " 30 分鐘後開賣，英雄陪你等", "🎫 " + n + " 剩 10 分鐘！英雄出動準備", "🎫 準備！這次一定搶到！", "🎫 開搶！！祝你搶到！"]
        let ti: [String] = ["🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款喔", "🎫 " + n + " 再 30 分鐘！丁丁陪你等", "🎫 " + n + " 剩 10 分鐘！魔法袋準備好了", "🎫 準備！深呼吸～", "🎫 開搶！！衝衝衝！"]
        let di: [String] = ["🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款", "🎫 " + n + " 30 分鐘後開賣，網頁先開好", "🎫 " + n + " 剩 10 分鐘！帽子戴好", "🎫 準備。冷靜，酷。", "🎫 開搶！！嘿！"]
        let la: [String] = ["🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款喔", "🎫 " + n + " 再 30 分鐘！拉拉唱歌陪你等", "🎫 " + n + " 剩 10 分鐘！好緊張～", "🎫 準備！啦…啦…", "🎫 開搶！！衝啊～啦！"]
        // </fan>
        switch id { case "po": return po[stage]; case "stitch": return st[stage]; case "hangyodon": return hg[stage]; case "tinky": return ti[stage]; case "dipsy": return di[stage]; case "laalaa": return la[stage]; default: break }   //@fan
        return sp[stage]
    }

    func TicketTick() {
        if tickets.Count == 0 { return }
        let now = World.UnixMs(DateTime.Now)
        var changed = false
        var i = tickets.Count - 1
        while i >= 0 {
            let t: Ticket = tickets[i]
            let st = World.StagesOf(t)
            let left = Double(t.At - now) / 60000.0
            // 找出「已經到了、還沒講過」的最後一段（中間錯過的就跳過）
            var fire = -1
            var s = t.Stage
            while s < st.count { if left <= Double(st[s]) { fire = s }; s += 1 }
            if fire >= 0 { t.Stage = fire + 1; changed = true; FireTicket(t, fire) }
            if t.Stage >= st.count && left < -10 { tickets.RemoveAt(i); changed = true }
            i -= 1
        }
        if changed { SaveTickets() }
    }

    func FireTicket(_ t: Ticket, _ stage: Int) {
        App.Log("ticket stage " + String(stage) + " " + t.Name)
        if sharing { return }                                  // 分享螢幕時不跳（畫面隱私）
        if userHidden { userHidden = false; ApplyHidden() }
        let l: Pet = Lead()
        let text = World.TicketLine(l.P.Id, stage, t)
        let hint: String! = t.Url != nil ? (t.Kind == "course" ? "點我打開選課系統" : "點我打開購票頁") : nil
        if stage == 1 { l.Notify(text, hint, 1, false, false) }
        else if stage == 0 || stage == 2 { l.Notify(text, hint, 2, false, false) }
        else {
            // 1 分鐘、開賣：不管冷卻一定放大
            lastZoom = Now
            l.ForceGlass(text, hint, stage == 4)
            if stage == 4 { Fireworks(WA(l.Cx, l.y), 4, CInt(l.Cx)); for p in OutPets() { if p !== l { p.React() } } }
        }
        if stage == 2 { CheckClock(t.Url, t.Kind == "course" ? "搶課" : "搶票") }
        let n = Notice(); n.Kind = "ticket"; n.Url = t.Url; n.Text = t.Name; n.Pri = 2; n.By = l; n.Expire = Now + 600
        if t.Url != nil { current = n; l.SetClickableBubble(true) }
    }

    // 開賣前 10 分鐘以內：倒數（給公仔頭上的大徽章用）；開賣後 1 分鐘顯示「開搶中」
    func TicketCountdown() -> String! {
        if tickets.Count == 0 { return nil }
        let now = World.UnixMs(DateTime.Now)
        for t in tickets {
            let ms = t.At - now
            if ms > 0 && ms <= 10 * 60000 { let s = (ms + 999) / 1000; return (s / 60).ToString("00") + ":" + (s % 60).ToString("00") }
            if ms <= 0 && ms > -60000 { return t.Kind == "course" ? "開放囉！" : "開搶中！" }
        }
        return nil
    }

    // 對時：拿 HTTP 回應的 Date 標頭跟電腦時間比
    func CheckClock(_ url: String!, _ what: String) {
        if App.Offscreen { return }   // 離屏測試不連網路
        var target = "https://www.google.com/"
        if url != nil, let u = URL(string: url), let sc = u.scheme, let h = u.host { target = sc + "://" + h + "/" }
        let tgt = target
        Thread {
            var off = World.ClockOffset(tgt)
            if off.isNaN && tgt != "https://www.google.com/" { off = World.ClockOffset("https://www.google.com/") }
            if off.isNaN { App.Log("clock check failed"); return }
            App.Log("clock offset " + off.ToString("0.0") + "s via " + tgt)
            if Math.Abs(off) <= 2 { return }
            let sec = CInt(Math.Round(Math.Abs(off)))
            let msg = off < 0 ? "電腦時間比標準時間慢 " + String(sec) + " 秒" : "電腦時間比標準時間快 " + String(sec) + " 秒"
            self.Post { self.Lead().Say("⏱ " + msg + "，" + what + "要看標準時間喔", 6, true) }
        }.Start()
    }

    // mac: 不跟隨轉址（3xx 也有 Date 標頭）
    final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }

    // 回傳「電腦時間 − 標準時間」秒數（NaN＝查不到）
    // mac: HttpWebRequest HEAD → URLSession（背景執行緒上用 semaphore 等）
    static func ClockOffset(_ url: String) -> Double {
        guard let u = URL(string: url) else { return Double.nan }
        var req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        req.httpMethod = "HEAD"; req.setValue("DeskPals", forHTTPHeaderField: "User-Agent")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5; cfg.timeoutIntervalForResource = 6
        let session = URLSession(configuration: cfg, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let sem = DispatchSemaphore(value: 0)
        var dateHdr: String? = nil
        let t0 = Date()
        var t1 = Date()
        let task = session.dataTask(with: req) { _, resp, _ in
            t1 = Date()
            if let hr = resp as? HTTPURLResponse { dateHdr = hr.value(forHTTPHeaderField: "Date") }
            sem.signal()
        }
        task.resume()
        if sem.wait(timeout: .now() + 7) == .timedOut { task.cancel(); return Double.nan }
        guard let d = dateHdr else { return Double.nan }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.timeZone = TimeZone(identifier: "GMT")
        fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let server = fmt.date(from: d) else { return Double.nan }
        let mid = t0.addingTimeInterval(t1.timeIntervalSince(t0) / 2)
        // Date 只到秒：標準時間大約在 server 到 server+1 秒之間，取中間
        return mid.timeIntervalSince(server.addingTimeInterval(0.5))
    }

    func AddTicketMenus(_ items: ToolStripItemCollection) { AddTicketMenus(items, "ticket") }
    func AddTicketMenus(_ items: ToolStripItemCollection, _ kind: String) {
        let word = kind == "course" ? "搶課" : "搶票"
        items.Add(word + "提醒…", nil) { self.ShowTicketForm(kind) }
        let mine: List<Ticket> = tickets.FindAll { (x: Ticket) -> Bool in x.Kind == kind }
        if mine.Count > 0 {
            let my = ToolStripMenuItem("我的" + word + "（" + String(mine.Count) + "）")
            for t in mine {
                let tt = t
                my.DropDownItems.Add(World.FromUnixMs(t.At).ToString("MM/dd HH:mm") + "　" + (t.Name.Length > 18 ? t.Name.Substring(0, 18) + "…" : t.Name) + "　（點一下取消）", nil) {
                    self.tickets.Remove(tt); self.SaveTickets(); self.Lead().Say("取消" + word + "提醒：" + tt.Name, 1.8)
                }
            }
            items.Add(my)
        }
    }

    func ShowTicketForm() { ShowTicketForm("ticket") }
    func ShowTicketForm(_ kind: String) {
        if App.Offscreen { return }
        if ticketForm != nil && !ticketForm.IsDisposed && ticketForm.Kind != kind { ticketForm.Dispose(); ticketForm = nil }
        if ticketForm == nil || ticketForm.IsDisposed { ticketForm = TicketForm(self, Lead().P.Accent, kind) }
        let c: Point = Cursor.Position
        let wa: Rectangle = WA(Double(c.X), Double(c.Y))
        ticketForm.StartPosition = FormStartPosition.Manual
        ticketForm.Location = Point(Math.Max(wa.Left, Math.Min(wa.Right - ticketForm.Width, c.X - ticketForm.Width / 2)), Math.Max(wa.Top, Math.Min(wa.Bottom - ticketForm.Height, c.Y - ticketForm.Height - 10)))
        ticketForm.Show()
        ActivateForm(ticketForm)
        ticketForm.FocusFirst()
        let tf: TicketForm = ticketForm
        Later(0.2) { if tf.Visible { self.ActivateForm(tf); tf.FocusFirst() } }
    }
}

extension Pet {
    // 一定放大敲玻璃（搶票最後一分鐘、開賣當下）
    func ForceGlass(_ text: String, _ hint: String!, _ loud: Bool) {
        WakeIfSleep()
        sense = loud ? 3.5 : 2.5
        if Out && Grounded() && state != "glass" { StartGlass(text) }
        Say(text, loud ? 10 : 8, true, hint)
        bubblePri = 2
        if loud { Burst(14); AddHeart(); AddHeart() }
    }

    // 搶票倒數的大徽章（畫在頭頂上）
    func DrawTicketBadge(_ g: Graphics, _ ox: Int, _ oy: Int) {
        let cd0 = w.TicketCountdown()
        if cd0 == nil || w.Lead() !== self { return }
        let cd: String = cd0!
        do {
            let f = Font("Consolas", Math.Max(13.0, 11 * k), FontStyle.Bold, GraphicsUnit.Pixel)
            let f2 = Font("Microsoft JhengHei UI", Math.Max(12.0, 9.5 * k), FontStyle.Bold, GraphicsUnit.Pixel)
            let use = cd.Contains(":") ? f : f2
            let ts: SizeF = g.MeasureString(cd, use)
            let iw: Double = 9 * k, bw: Double = ts.Width + iw + 10 * k, bh: Double = ts.Height + 4 * k
            let bx: Double = (Cx - bw / 2) - Double(ox)
            let by: Double = (y - Double(P.TopRows + 6) * Double(S) - bh) - Double(oy)
            let hot = !cd.Contains(":") || cd.StartsWith("00")
            do {
                let p = GraphicsPath()
                let r: Double = bh / 2
                p.AddArc(bx, by, 2 * r, 2 * r, 90, 180); p.AddArc(bx + bw - 2 * r, by, 2 * r, 2 * r, 270, 180); p.CloseFigure()
                do { let b = SolidBrush(hot ? Color.FromArgb(240, 0xD8, 0x3A, 0x3A) : Color.FromArgb(235, 0x2A, 0x2F, 0x45)); g.FillPath(b, p) }
                do { let rim = Pen(Color.FromArgb(220, 255, 255, 255), Math.Max(1.5, k)); g.DrawPath(rim, p) }
            }
            // 小票券圖示（搶課是學士帽）
            let tx: Double = bx + 5 * k, ty: Double = by + bh / 2 - 3.5 * k
            if w.BadgeIsCourse() { Pet.DrawCapIcon(g, tx - k, ty, iw, k, hot) }
            else {
                do { let tb = SolidBrush(Color.FromArgb(0xFF, 0xD8, 0x4A)); g.FillRectangle(tb, tx, ty, iw - 2 * k, 7 * k) }
                do { let hole = SolidBrush(hot ? Color.FromArgb(0xD8, 0x3A, 0x3A) : Color.FromArgb(0x2A, 0x2F, 0x45)); g.FillEllipse(hole, tx - 1.5 * k, ty + 2.2 * k, 3 * k, 2.6 * k) }
            }
            g.TextRenderingHint = TextRenderingHint.AntiAlias
            do { let wb = SolidBrush(Color.White); g.DrawString(cd, use, wb, bx + iw + 7 * k, by + 2 * k) }
        }
    }
}

// 「搶票提醒…」「搶課提醒…」的小視窗（Kind：ticket｜course）
class TicketForm: Form {
    var w: World
    let Kind: String
    let name = TextBox(), time = TextBox(), url = TextBox()
    let date = DateTimePicker()
    let lead1 = RadioButton(), lead2 = RadioButton()
    let hint = Label()
    convenience init(_ w: World, _ accent: Color) { self.init(w, accent, "ticket") }
    init(_ w: World, _ accent: Color, _ kind: String) {
        self.w = w
        Kind = kind == "course" ? "course" : "ticket"
        super.init()
        let course = Kind == "course"
        Text = course ? "🎓 搶課提醒" : "🎫 搶票提醒"
        FormBorderStyle = FormBorderStyle.FixedToolWindow
        ShowInTaskbar = false; TopMost = true; MaximizeBox = false; MinimizeBox = false
        BackColor = Color.FromArgb(0xFF, 0xFB, 0xF4)
        Font = WorldC_Font("Microsoft JhengHei UI", 10)
        AutoScaleMode = AutoScaleMode.Dpi
        ClientSize = Size(360, 268)
        let y0 = 12
        AddLabel(course ? "要搶哪門課？（例如：通識熱門課、體育羽球）" : "要搶什麼？（例如：五月天 演唱會）", y0); name.Location = Point(14, y0 + 22); name.Width = 332; Controls.Add(name)
        AddLabel(course ? "選課系統開放日期與時間" : "開賣日期與時間", y0 + 56)
        date.Format = DateTimePickerFormat.Custom; date.CustomFormat = "yyyy-MM-dd"; date.Location = Point(14, y0 + 78); date.Width = 150; Controls.Add(date)
        time.Location = Point(176, y0 + 78); time.Width = 80; time.Text = course ? "09:00" : "12:00"; Controls.Add(time)
        AddLabel(course ? "選課系統網址（可以不填）" : "購票網址（可以不填）", y0 + 112); url.Location = Point(14, y0 + 134); url.Width = 332; Controls.Add(url)
        lead2.Text = "提前 2 小時"; lead2.Checked = true; lead2.Location = Point(14, y0 + 168); lead2.AutoSize = true; Controls.Add(lead2)
        lead1.Text = "提前 1 小時"; lead1.Location = Point(130, y0 + 168); lead1.AutoSize = true; Controls.Add(lead1)
        let ok = Button(); ok.Text = "好，幫我盯著"; ok.Location = Point(206, y0 + 200); ok.Size = Size(140, 34)
        ok.FlatStyle = FlatStyle.Flat; ok.BackColor = accent; ok.ForeColor = Color.White; ok.FlatAppearance.BorderSize = 0
        ok.Click = { [unowned self] in self.Submit() }
        Controls.Add(ok)
        hint.Location = Point(14, y0 + 208); hint.AutoSize = true; hint.ForeColor = Color.FromArgb(0xB0, 0x40, 0x40); Controls.Add(hint)
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
        if !DateTime.TryParse(date.Value.ToString("yyyy-MM-dd") + " " + tm, &t) { hint.Text = "時間看不懂，例如 12:00"; return }
        if t < DateTime.Now { hint.Text = "這個時間已經過了喔"; return }
        let u = url.Text.Trim()
        if u != "" && !(u.StartsWith("http://") || u.StartsWith("https://")) { hint.Text = "網址要 http:// 或 https:// 開頭"; return }
        let ms = World.UnixMs(t)
        w.AddTicket(ms, lead1.Checked ? 60 : 120, u == "" ? "-" : u, name.Text.Trim(), Kind)
        name.Text = ""; url.Text = ""; hint.Text = ""
        Hide()
    }
}

// ================= 午餐時間（平日 12:00～13:30）=================
// 12:00 開飯（拿著自己的午餐）→ 13:00 吃飽睡午覺 → 13:25 提醒快結束 → 13:30 變回來工作
extension World {
    var Lunch: Bool { return LunchState != "" }

    func LunchByClock() -> String {
        let n = DateTime.Now
        if n.DayOfWeek == DayOfWeek.Saturday || n.DayOfWeek == DayOfWeek.Sunday { return "" }
        let m = n.Hour * 60 + n.Minute
        if m >= 12 * 60 && m < 13 * 60 { return "eat" }
        if m >= 13 * 60 && m < 13 * 60 + 25 { return "nap" }
        if m >= 13 * 60 + 25 && m < 13 * 60 + 30 { return "soon" }
        return ""
    }

    func LunchTick(_ force: Bool) {
        let minute = DateTime.Now.Minute
        if !force && minute == lunchChecked { return }
        lunchChecked = minute
        let want = forceLunch == 1 ? "eat" : (forceLunch == 2 ? "nap" : (forceLunch == 0 || !Feat("lunch") ? "" : LunchByClock()))
        if want == LunchState { return }
        let was = LunchState
        LunchState = want
        let outs: List<Pet> = OutPets()
        let l: Pet = Lead()
        var d = 0.0
        if want == "eat" && was == "" {
            for p in outs { let pp = p; Later(d) { pp.LunchStart() }; d += 0.8 }
            if outs.Count == 0 { l.Say(l.LunchLine("start"), 3) }
        } else if want == "nap" {
            for p in outs { let pp = p; Later(d) { pp.LunchNap() }; d += 0.6 }
        } else if want == "soon" {
            for p in outs { p.WakeIfSleep() }
            l.Say("午休快結束囉～", 3)
        } else if want == "" {
            for p in outs { let pp = p; Later(d) { pp.LunchEnd() }; d += 0.7 }
            if outs.Count == 0 { l.Say(l.LunchLine("end"), 3) }
        }
    }
}

extension Pet {
    // 每個角色的午餐
    static let PIZZA: [String] = ["1111", "1YSY", ".YYS", ".YY.", "..Y."]
    static let CUSTARD: [String] = ["..2...", ".P2PP.", "PPPPPP", "kWWWWk", ".kWWk."]
    static let SANDWICH: [String] = [".11111.", "1PPPPP1", "SSSSSSS", "YYYYYYY", ".11111."]
    static let MILKTEA: [String] = ["kkkk", "k22k", "k12k", "k22k", ".kk."]
    static let BUN: [String] = [".YY.", "Y1YY", "YWWY", "YYYY"]
    static let PLATE: [String] = ["..1....", "kWWWWWk", ".kkkkk."]

    func LunchLine(_ phase: String) -> String {
        if P.Pik { return PikLunchLine(phase) }   //@fan
        if P.Orig { return OrigLunchLine(phase) }
        if P.Cu { return CuLunchLine(phase) }
        // <fan>
        switch P.Id {
        case "po":
            if phase == "start" { return "嘟嘟糊！午餐時間！🔔" }
            if phase == "nap" { return "吃飽飽…小波想睡覺覺" }
            if phase == "end" { return "Eh-oh! 回來工作囉！" }
            return Pick(["嘟嘟糊！再來一碗！", "嘟嘟糊黏在臉上了嘻嘻", "好好吃～再來一次！"])
        case "stitch":
            if phase == "start" { return "午餐！好吃！ih-ih! 🔔" }
            if phase == "nap" { return "呼…吃太飽…" }
            if phase == "end" { return "回來工作！嘻嘻嘻" }
            return Pick(["好吃！ih-ih!", "（屑屑掉滿地）嘻嘻嘻", "史迪仔還要一個！"])
        case "hangyodon":
            if phase == "start" { return "午餐時間！港式奶茶＋菠蘿油 🔔" }
            if phase == "nap" { return "吃飽了…在泡泡裡睡一下" }
            if phase == "end" { return "回來工作！英雄也要上班" }
            return Pick(["奶茶要走冰…我自己就很冰了（魚嘛）", "菠蘿油的牛油要厚切！", "茶走、少甜，謝謝老闆～"])
        case "tinky":
            if phase == "start" { return "吐司時間！丁丁從魔法袋拿出吐司 🔔" }
            if phase == "nap" { return "吃飽飽…丁丁抱著袋袋睡覺覺" }
            if phase == "end" { return "Eh-oh! 回來工作囉！" }
            return Pick(["吐司！好香～", "吐司屑屑掉進袋子了", "再一片！再來一次！"])
        case "dipsy":
            if phase == "start" { return "嘟嘟糊時間！帽子不用拿下來 🔔" }
            if phase == "nap" { return "吃飽了…帽子拉低睡一下" }
            if phase == "end" { return "Eh-oh. 回來工作。" }
            return Pick(["嘟嘟糊，酷。", "（帽子沾到嘟嘟糊了）…沒事。", "再一碗。"])
        case "laalaa":
            if phase == "start" { return "午餐時間！吐司沾嘟嘟糊～啦啦啦 🔔" }
            if phase == "nap" { return "吃飽飽…拉拉抱著球球睡覺覺" }
            if phase == "end" { return "Eh-oh! 回來工作囉！啦～" }
            return Pick(["吐司沾嘟嘟糊～好好吃！", "啦啦啦～吃飯飯～", "嘟嘟糊黏在臉上了嘻嘻"])
        default: break
        }
        if phase == "start" { return "Pizza time! 🍕 午餐時間！" }
        if phase == "nap" { return "吃飽了…蜘蛛也要午睡 zZ" }
        if phase == "end" { return "回來工作！能力越強，吃得越多 🕸" }
        return Pick(["嗯～起司拉好長", "Pizza time! 🍕", "Thwip! 接到掉下來的臘腸了"])
        // </fan>
        // <public> return "午餐時間！🔔"
    }

    func LunchStart() {
        if !Out { return }
        WakeIfSleep()
        Say(LunchLine("start"), 3)
        Mark(0); Mark(0); Burst(6)
        if Grounded() { Jump(0, -240 * k) }
    }

    func LunchNap() {
        if !Out { return }
        if Grounded() { GoSleep(); t = 25 * 60 }
        Say(LunchLine("nap"), 2.6)
    }

    func LunchEnd() {
        if !Out { return }
        WakeIfSleep()
        Say(LunchLine("end"), 2.8)
        if Grounded() { Jump(0, -260 * k) }
    }

    func HoldingFood() -> Bool {
        return w.LunchState == "eat" || w.LunchState == "soon"
    }

    // 吃東西：手上的午餐（睡午覺時擺在旁邊的空盤子）
    func DrawLunch(_ g: Graphics, _ f: Fr, _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool) {
        if !w.Lunch || f.Rot != 0 || f.Fy { return }
        if state == "sleep" { DrawAt(g, Pet.PLATE, 12, 13, bx, by, ps, fx, false, true); return }
        if !HoldingFood() || state == "glass" || state == "hug" { return }
        let bite = Step2(2.5) ? 1 : 0   // 一口一口：手上的食物上下動
        if P.Pik { DrawPikLunch(g, f, bx, by, ps, fx, bite); return }   //@fan
        if P.Orig { DrawOrigLunch(g, f, bx, by, ps, fx, bite); return }
        if P.Cu { CuLunch(g, f, bx, by, ps, fx, bite); return }
        switch P.Id {
        // <fan>
        case "po":
            DrawAt(g, Pet.CUSTARD, 9, Double(8 + bite + f.AccDy), bx, by, ps, fx, false, true)
            // 嘟嘟糊沾在臉上
            do {
                let cu = SolidBrush(Night ? Color.FromArgb(0xC9, 0x7A, 0x96) : Color.FromArgb(0xFF, 0x9C, 0xC0))
                let cx = fx ? bx + 4 * ps : bx + 7 * ps
                g.FillRectangle(cu, cx, by + (5 + f.AccDy) * ps, ps, ps)
            }
        case "stitch":
            DrawAt(g, Pet.SANDWICH, 3, Double(6 + bite + f.AccDy), bx, by, ps, fx, false, true)
            if rnd.NextDouble() < 0.05 && notes.Count < 10 { notes.Add(Arr<Double>([R(-8, 8) * k, 0, 7])) }
        case "hangyodon":
            DrawAt(g, Pet.MILKTEA, 10.5, Double(8 + f.AccDy), bx, by, ps, fx, false, true)
            DrawAt(g, Pet.BUN, -2.5, Double(8 + bite + f.AccDy), bx, by, ps, fx, false, true)
        case "tinky": DrawAt(g, Pet.TOAST, 10.5, Double(P.BodyTop + 1 + bite + f.AccDy), bx, by, ps, fx, false, true)
        case "dipsy": DrawAt(g, A("DUDU"), 9, Double(P.BodyTop + bite + f.AccDy), bx, by, ps, fx, false, true)
        case "laalaa":
            DrawAt(g, Pet.TOAST, -1.5, Double(P.BodyTop + 1 + bite + f.AccDy), bx, by, ps, fx, false, true)
            DrawAt(g, A("DUDU_CUP"), 11, Double(P.BodyTop + 2 + f.AccDy), bx, by, ps, fx, false, true)
            // </fan>
        default:
            DrawAt(g, Pet.PIZZA, 10, Double(7 + bite), bx, by, ps, fx, false, true)
        }
    }

    // 櫃子裡的公仔也拿著午餐
    func DrawLunchShelf(_ g: Graphics, _ bx: Int, _ by: Int, _ ps: Int, _ flip: Bool) {
        if !w.Lunch { return }
        if P.Pik || P.Orig { return }   // 皮克敏、續命小隊在自己的櫃子畫法裡拿午餐   //@fan
        // <public> if P.Orig { return }
        var food: [String]; var col: Double, row: Double
        switch P.Id {
        // <fan>
        case "po": food = Pet.CUSTARD; col = 9; row = 8
        case "stitch": food = Pet.SANDWICH; col = 3; row = 6
        case "hangyodon": food = Pet.MILKTEA; col = 10.5; row = 8
        case "tinky": food = Pet.TOAST; col = 10.5; row = Double(P.BodyTop + 1)
        case "dipsy": food = A("DUDU"); col = 9; row = Double(P.BodyTop)
        case "laalaa": food = Pet.TOAST; col = -1.5; row = Double(P.BodyTop + 1)
        // </fan>
        default: food = Pet.PIZZA; col = 10; row = 7
        }
        DrawAt(g, food, col, row, bx, by, ps, flip, false, true)
    }
}

extension Pet {
    // 外出中的格子：淡淡的剪影，櫃子還是他的位置
    func DrawGhost(_ g: Graphics, _ fx: Int, _ fy: Int, _ ps: Int, _ night: Bool) {
        if P.Spr != nil { CuGhost(g, fx, fy, ps, night); return }
        let rows: [String] = Pal.Stack(A("HEAD"), A("BODY"), A("LEGS_A"))
        let bx = fx - rows[0].Length * ps / 2, by = fy - rows.count * ps
        let c: Color = P.Accent
        do {
            let b = SolidBrush(Color.FromArgb(night ? 34 : 42, c.R, c.G, c.B))
            for r in 0..<rows.count {
                let row = Array(rows[r])
                for i in 0..<row.count {
                    if row[i] != "." { g.FillRectangle(b, bx + i * ps, by + r * ps, ps, ps) }
                }
            }
        }
    }

    // 在櫃子裡要佔幾列高（腳到最高點：天線、耳朵、帽子、滑板車墊高、晃動）
    func ShelfRows() -> Int {
        if P.Pik { return PikShelfRows() }   //@fan
        if P.Orig { return OrigShelfRows() }
        if P.Cu { return CuShelfRows() }
        let hat = (w.SeasonNow == "xmas" || Level() >= 3) ? 4 : 0
        switch P.Id {
        // <fan>
        case "po": return 16 + P.TopRows + 1                             // 扶著停在旁邊的滑板車
        case "stitch": return 16 + Math.Max(P.TopRows, hat > 0 ? 3 : 0) + 1
        case "hangyodon": return 16 + (hat > 0 ? 2 : 0) + 1
        case "tinky": return 16 + P.TopRows + 1                           // 天線從帽子穿出來，不會更高
        case "dipsy": return 16 + P.TopRows + 2                           // 高帽子＋偶爾抬一下
        case "laalaa": return 16 + Math.Max(P.TopRows, hat > 0 ? 7 : 0) + 1
        // </fan>
        default: break
        }
        return 16 + hat + 1
    }

    func PreviewLevel(_ x: Int) { xp = x }

    func Reload() { xp = 0; lastPatDay = ""; patsToday = 0; patsDate = ""; LoadBond() }

    // <fan>
    // 開發用預覽：每個角色各種姿勢排成一張圖
    static func PreviewSheet(_ path: String, _ night: Bool) {
        let w = World(6)
        w.Night = night
        let poses: [[String]] = [
            ["spidey", "idle", "walk", "hug", "glass", "sleep", "hang", "swing", "dizzy"],
            ["po", "idle", "walk", "hug", "glass", "sleep", "bat1", "bat2", "bat3", "catch", "homerun", "wave", "roll"],
            ["stitch", "idle", "walk", "hug", "glass", "sleep", "ceil", "curl", "elvis", "grin", "wall", "chomp"],
            ["hangyodon", "idle", "walk", "hug", "glass", "sleep", "silly", "hero", "swim", "cape", "trip", "header"]]
        let cw = 34 * 6, ch = 30 * 6
        do {
            let b = Bitmap(cw * 12, ch * 4)
            let g = Graphics.FromImage(b)
            let f = Font("Arial", 10)
            g.Clear(night ? Color.FromArgb(0x30, 0x34, 0x44) : Color.FromArgb(0xE6, 0xEA, 0xF0))
            for r in 0..<poses.count {
                let p: Pet = w.Get(poses[r][0])
                p.Out = true
                for c in 1..<poses[r].count {
                    let s = poses[r][c]
                    p.state = s; p.anim = 0.3; p.t = 1; p.Bt = 0; p.rolling = false; p.hangPhase = 1; p.poseKind = ""; p.dir = 1; p.tripT = 0; p.caped = false
                    if s == "walk" { p.anim = 0.05 }
                    if s.StartsWith("bat") { p.state = "bat"; p.batT = s == "bat1" ? 0.1 : (s == "bat2" ? 0.28 : 0.5) }
                    if s == "homerun" || s == "grin" { p.state = "pose"; p.poseKind = s }
                    if s == "roll" { p.state = "air"; p.rolling = true; p.anim = 0.1 }
                    if s == "silly" || s == "hero" { p.state = "pose"; p.poseKind = s }
                    if s == "swim" { p.Mark(5); p.Mark(5) }
                    if s == "cape" { p.state = "swim"; p.caped = true }
                    if s == "trip" { p.state = "capetrip"; p.tripT = 1 }
                    p.x = Double((c - 1) * cw + 11 * 6); p.y = Double(r * ch + 11 * 6)
                    g.DrawString(s, f, night ? Brushes.White : Brushes.Black, (c - 1) * cw + 4, r * ch + 2)
                    p.PaintPet(g, 0, 0)
                    p.notes.Clear()
                }
            }
            b.Save(path, ImageFormat.Png)
        }
    }

    static func PreviewTubbySheet(_ path: String, _ night: Bool) {
        let w = World(6, Pal.Teletubbies)
        w.Night = night
        let ids: [String] = ["tinky", "dipsy", "laalaa", "po"]
        let poses: [String] = ["idle", "walk", "hug", "glass", "sleep", "plop", "dance", "wave", "photo", "special1", "special2", "special3", "ride", "wearhat", "toast", "lunch", "nightidle"]
        let cw = 30 * 6, ch = 40 * 6
        do {
            let b = Bitmap(cw * poses.count, ch * ids.count)
            let g = Graphics.FromImage(b)
            let f = Font("Arial", 10)
            g.Clear(night ? Color.FromArgb(0x30, 0x34, 0x44) : Color.FromArgb(0xE6, 0xEA, 0xF0))
            for r in 0..<ids.count {
                let p: Pet = w.Get(ids[r])
                p.Out = true
                for c in 0..<poses.count {
                    let s = poses[c]
                    p.state = s; p.anim = 0.3; p.t = 1; p.Bt = 0; p.rolling = false; p.poseKind = ""; p.dir = 1; p.sT = 0; p.bagItem = ""
                    p.RidingPo = false; p.WearHat = false; p.HoldToast = false; p.InScene = false; w.LunchState = ""
                    var nightIdle = false
                    if s == "walk" { p.anim = 0.05 }
                    if s == "plop" { p.sT = 0.2 }
                    if s == "photo" { p.state = "pose"; p.poseKind = "photo" }
                    if s == "special1" { if ids[r] == "tinky" { p.state = "bagdig"; p.bagItem = "toast"; p.sT = 1.5 } else if ids[r] == "dipsy" { p.state = "hattoss"; p.sT = 0.6 } else if ids[r] == "laalaa" { p.state = "juggle"; p.sT = 0.33 } else { p.state = "spin" } }
                    if s == "special2" { if ids[r] == "dipsy" { p.state = "pose"; p.poseKind = "hatwave" } else if ids[r] == "laalaa" { p.state = "twirl" } else if ids[r] == "tinky" { p.state = "bagdig"; p.bagItem = ""; p.sT = 0.4 } else { p.state = "catch" } }
                    if s == "special3" { if ids[r] == "dipsy" { p.state = "pose"; p.poseKind = "hattip" } else if ids[r] == "laalaa" { p.state = "kick"; p.t = 0.3 } else if ids[r] == "tinky" { p.state = "pose"; p.poseKind = "sing" } else { p.state = "dizzy" } }
                    if s == "ride" { p.state = "walk"; p.RidingPo = ids[r] == "tinky" }
                    if s == "wearhat" { p.state = "idle"; p.WearHat = ids[r] == "tinky" }
                    if s == "toast" { p.state = "idle"; p.HoldToast = true }
                    if s == "lunch" { p.state = "idle"; w.LunchState = "eat" }
                    if s == "nightidle" { p.state = "idle"; nightIdle = true; p.anim = 2 }
                    let wasNight = w.Night; if nightIdle { w.Night = true }
                    p.x = Double(c * cw + 9 * 6); p.y = Double(r * ch + 20 * 6)
                    g.DrawString(s, f, night ? Brushes.White : Brushes.Black, c * cw + 4, r * ch + 2)
                    p.PaintPet(g, 0, 0)
                    p.notes.Clear(); p.sparks.Clear(); p.hearts.Clear()
                    w.Night = wasNight
                }
            }
            b.Save(path, ImageFormat.Png)
        }
    }
    // </fan>

    // 開發用：櫃子畫成圖
    static func PreviewShelf(_ path: String, _ night: Bool) {
        let w = World(4)
        w.Night = night
        w.PreviewShelfTo(path)
    }
}

extension World {
    func PreviewShelfTo(_ path: String) {
        shelf = ShelfForm(self, S)
        shelf.Place(Rectangle(0, 0, 400, 400))
        let favs: [String] = ["spidey", "po", "stitch", "hangyodon", "po"]   //@fan
        // <public> let favs: [String] = ["duoduo", "meidian", "cici", "duoduo", "meidian"]
        let W0 = shelf.Area.Width + 16, H0 = shelf.Area.Height + 16
        do {
            let b = Bitmap(W0 * favs.count, H0)
            let g = Graphics.FromImage(b)
            g.Clear(Night ? Color.FromArgb(0x25, 0x2A, 0x38) : Color.FromArgb(0xD8, 0xE0, 0xEA))
            shelf.Night = Night
            for v in 0..<favs.count {
                favPin = favs[v]
                for p in Pets { p.PreviewLevel(v == 4 ? 0 : 600) }   // 前四張戴最大的帽子（最壞情況）
                let c: [Pet?] = CellPets()
                var o = [Bool](repeating: false, count: 4)
                if v == 4 { for i in 0..<4 { o[i] = true } }       // 最後一張：全部外出（剪影）
                g.DrawImageUnscaled(shelf.Snapshot(c, o, 1.0 + Double(v) * 0.7), v * W0 + 8, 8)
            }
            b.Save(path, ImageFormat.Png)
        }
    }
}

// Form 子類別裡 `Font` 是屬性名稱，型別用這個別名
typealias WorldC_Font = Font
