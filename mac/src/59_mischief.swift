// 59_mischief.swift — port of extension/desktop/DeskPals.Mischief.cs
// Desk Pals：搗蛋（四個惡作劇）——搶游標、下班清場、購物警察、打字太兇。名稱、規則、pipe 指令都跟 C# 一樣（見 C# 檔開頭）。
//
// 安全（跟 Windows 一樣）：不關閉、不結束任何程式；打字只數次數；搶游標你一動就放手；全螢幕、簡報、分享螢幕、按著滑鼠鍵時不搗蛋；
//   會動到真實電腦的事都經過 MisSys，離屏測試換成 MisFake（只記錄呼叫）。
//
// mac 差異（都標了 // mac:）：
// - 移游標：SetCursorPos → CGWarpMouseCursorPosition（不會產生滑鼠事件）＋ CGAssociateMouseAndMouseCursorPosition（不卡住滑鼠）。
// - 你動了嗎：GetLastInputInfo → CGEventSource.secondsSinceLastEventType 換算成時間戳（毫秒）。
// - 下班清場：視窗「縮小」→ 隱藏那個 App（NSRunningApplication.hide；一個 App 一次、最多 3 個），叫回來＝unhide。
//   不擷取視窗畫面（要「螢幕錄影」權限，CGWindowListCreateImage 也已淘汰）：假視窗一律畫成卡通視窗（標題＝視窗名稱或 App 名稱）。
// - 打字太兇：低階鍵盤掛鉤 → 系統的「放開按鍵」計數器 CGEventSource.counterForEventType（只有次數，看不到哪個鍵）。
//   macOS 可能要「輸入監控」權限：只在你自己從小屋打開開關時問一次（IOHIDRequestAccess）；沒權限數不到，就安靜地不觸發、不再彈窗。
// - 購物警察：別的 App 的視窗標題要「螢幕錄影」權限才拿得到；沒有就只看得到 App 名稱（認不出購物網站，就不哭）。
import Foundation
import AppKit
import IOKit.hid

// 一個視窗（真的：CGWindowID；假的：測試用的編號）
final class MisWin { var H: IntPtr = 0; var R = Rectangle(0, 0, 0, 0); var Title = ""; var Min = false; var Pid = 0; init() {} }   // mac: Pid（隱藏／叫回整個 App 用）

// ================= 會動到真實電腦的事都在這裡（離屏測試換成 MisFake）=================
class MisSys {
    static let MyPid = Int(ProcessInfo.processInfo.processIdentifier)
    init() {}

    var Fake: Bool { return false }
    func Clock() -> DateTime { return DateTime.Now }
    func Idle() -> Double { return W.IdleSeconds() }
    func CursorPos() -> Point { return CursorT.Position }
    func Buttons() -> Bool { return Control.MouseButtons != MouseButtons.None }
    func Fullscreen() -> Bool { return false }   // 真的全螢幕由 World.FullscreenCheck 判斷
    // mac: 最後一次鍵盤滑鼠輸入的時間戳（開機後第幾毫秒）：變了＝你動了
    func InputStamp() -> Int {
        let anyInput = CGEventType(rawValue: ~0)!
        let ago = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        return Int(((ProcessInfo.processInfo.systemUptime - ago) * 1000).rounded())
    }
    // mac: 移游標不會產生事件；接著把滑鼠跟游標接回去（不然滑鼠會卡一下）
    func Warp(_ x: Int, _ y: Int) {
        _ = CGWarpMouseCursorPosition(CGPoint(x: CGFloat(x), y: CGFloat(y)))
        _ = CGAssociateMouseAndMouseCursorPosition(1)
    }
    // 搶游標期間：你有沒有按鍵盤。不看「最後輸入時間」（移游標之後可能被系統更新，會誤判成你動了）；
    // 改成 keyDown 的計數器有沒有變（沒「輸入監控」權限時讀不到，再看一輪目前按著的鍵）；只看有沒有按，不記是哪個鍵
    var keyDownBase = 0
    func KeyPrime() { keyDownBase = Int(CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)) }
    func KeyPressed() -> Bool {
        if Int(CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)) != keyDownBase { return true }
        for code in 0..<128 { if CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code)) { return true } }
        return false
    }

    // 前景視窗的標題（購物警察用；自己的視窗不算）
    func FgTitle() -> String {
        let h = W.GetForegroundWindow()
        if h == 0 || Form._FromHandle(h) != nil { return "" }
        guard let s = W.Info(h) else { return "" }
        if s.Pid == MisSys.MyPid { return "" }
        return s.Name.isEmpty ? s.Owner : s.Name
    }

    // 前面幾個 App 的最前面那個視窗（由前到後）：不含自己
    func Windows(_ w: World, _ max: Int) -> List<MisWin> {
        let l = List<MisWin>()
        var pids: [Int] = []
        for wi in w.Wins {
            if l.Count >= max { break }
            if !w.Cands.ContainsKey(wi.H) { continue }
            guard let s = W.Info(wi.H) else { continue }
            if s.Pid == MisSys.MyPid || s.Pid == 0 || pids.contains(s.Pid) { continue }   // mac: 一個 App 一次（隱藏是整個 App）
            pids.append(s.Pid)
            let m = MisWin()
            m.H = wi.H; m.R = Rectangle.FromLTRB(wi.L, wi.T, wi.R, wi.B); m.Pid = s.Pid
            m.Title = s.Name.isEmpty ? s.Owner : s.Name
            l.Add(m)
        }
        return l
    }

    // mac: 不擷取視窗畫面（要螢幕錄影權限）→ 假視窗畫成卡通視窗
    func Capture(_ m: MisWin) -> Bitmap? { return nil }

    // mac: 只是隱藏那個 App（不關閉）；叫回來＝取消隱藏
    func Minimize(_ m: MisWin) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid_t(m.Pid)) else { return false }
        return app.hide()
    }
    func Restore(_ m: MisWin, _ activate: Bool) {
        guard let app = NSRunningApplication(processIdentifier: pid_t(m.Pid)) else { return }
        if app.isHidden { _ = app.unhide() }
        if activate { _ = app.activate(options: []) }
    }

    // ---- 打字太兇：只數「放開按鍵」幾次 ----
    // mac: 系統的計數器（CGEventSource.counterForEventType）；沒開就不讀
    var keyUps = 0
    var watching = false
    func KeyCount() -> Int {
        if watching { keyUps = Int(CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyUp)) }
        return keyUps
    }
    var KeyWatching: Bool { return watching }
    func KeyWatch(_ on: Bool) {
        if on == watching { return }
        watching = on
        App.Log("mischief: key counter " + (on ? "on" : "off"))
    }
    // mac: 「輸入監控」權限——只在你自己打開開關時問一次（系統記得你的選擇，之後不會再跳）
    func AskKeyPermission() {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue == kIOHIDAccessTypeGranted.rawValue { return }
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
    func Dump() -> String { return "" }
}

// ================= 測試用：什麼都不真的做，只記錄 =================
final class MisFake: MisSys {
    var Cur = Point(700, 420)
    var Btn = false, Fs = false, Watching = false
    var Stamp = 0
    var IdleSec: Double = 0, T: Double = 0, Rate: Double = 0, RateUntil: Double = 0, RateLast: Double = 0, RateAcc: Double = 0
    var Fg = ""
    var Shift = TimeSpan.Zero
    var Warps = 0, Asked = 0
    var LastWarp = Point(0, 0)
    let Wins = List<MisWin>()      // 最前面的在 [0]
    let Calls = List<String>()
    var nextH = 0x7100

    override var Fake: Bool { return true }
    override func Clock() -> DateTime { return DateTime.Now + Shift }
    override func Idle() -> Double { return IdleSec }
    override func CursorPos() -> Point { return Cur }
    override func Buttons() -> Bool { return Btn }
    override func Fullscreen() -> Bool { return Fs }
    // 跟真的系統一樣：移游標之後「最後輸入時間」會（晚一點、非同步地）被更新——第一次讀還是舊的，下一次就變新的
    var warpPending = 0
    override func InputStamp() -> Int { if warpPending == 1 { warpPending = 2 } else if warpPending == 2 { Stamp += 50; warpPending = 0 }; return Stamp }
    override func Warp(_ x: Int, _ y: Int) { Cur = Point(x, y); LastWarp = Cur; Warps += 1; warpPending = 1 }
    var KeyDown = false                                   // mischief-fake input：假裝你按了鍵盤
    override func KeyPrime() { KeyDown = false }
    override func KeyPressed() -> Bool { return KeyDown }
    override func FgTitle() -> String { return Fg }
    func AddWin(_ r: Rectangle, _ title: String) {
        let m = MisWin()
        m.H = nextH; nextH += 1; m.R = r; m.Title = title
        Wins.Insert(0, m)
    }
    override func Windows(_ w: World, _ max: Int) -> List<MisWin> {
        let l = List<MisWin>()
        for m in Wins { if !m.Min && l.Count < max { l.Add(m) } }
        return l
    }
    override func Capture(_ m: MisWin) -> Bitmap? { Calls.Add("capture " + m.Title); return nil }
    override func Minimize(_ m: MisWin) -> Bool { m.Min = true; Calls.Add("minimize " + m.Title); return true }
    override func Restore(_ m: MisWin, _ activate: Bool) { if m.Min { m.Min = false; Calls.Add("restore " + m.Title + (activate ? " (front)" : "")) } }
    override func KeyCount() -> Int {
        let end = Math.Min(T, RateUntil)
        if end > RateLast { if Watching { RateAcc += (end - RateLast) * Rate }; RateLast = end }
        return Int(RateAcc)
    }
    override var KeyWatching: Bool { return Watching }
    override func KeyWatch(_ on: Bool) { if on != Watching { Watching = on; Calls.Add("keywatch " + (on ? "on" : "off")) } }
    override func AskKeyPermission() { Asked += 1; Calls.Add("ask-permission") }
    override func Dump() -> String {
        let sb = StringBuilder()
        sb.Append("fake cursor=" + String(Cur.X) + "," + String(Cur.Y) + " warps=" + String(Warps))
        sb.Append(" lastwarp=" + String(LastWarp.X) + "," + String(LastWarp.Y) + " keys=" + String(KeyCount()))
        sb.Append(" watching=" + (Watching ? "1" : "0") + " asked=" + String(Asked) + "\n")
        for m in Wins {
            let r = m.R
            sb.Append("win " + String(r.X) + "," + String(r.Y) + "," + String(r.Width) + "," + String(r.Height))
            sb.Append(" min=" + (m.Min ? "1" : "0") + " " + m.Title + "\n")
        }
        for c in Calls { sb.Append("call " + c + "\n") }
        return sb.ToString()
    }
}

// 下班清場的假視窗：卡通視窗（mac 不擷取畫面）。點得穿。
final class MisWinForm: OverlayForm {
    var img: Bitmap! = nil
    var title = ""
    static let TitleFont = FontT("Microsoft JhengHei UI", 10, FontStyle.Bold)
    init(_ b: Bitmap?, _ t: String?, _ r: Rectangle) {
        super.init(true)
        img = b; title = t ?? ""
        Bounds = r
    }
    override func OnPaint(_ e: PaintEventArgs) { MisWinForm.DrawWin(e.Graphics, img, title, ClientSize.Width, ClientSize.Height) }
    static func DrawWin(_ g: Graphics, _ img: Bitmap?, _ title: String, _ wd: Int, _ ht: Int) {
        if img != nil { g.DrawImageUnscaled(img, 0, 0); return }
        let body = SolidBrush(Color.FromArgb(0xF4, 0xF5, 0xF8))
        let bar = SolidBrush(Color.FromArgb(0xD6, 0xDB, 0xE4))
        let line = SolidBrush(Color.FromArgb(0xC9, 0xCF, 0xDB))
        let edge = Pen(Color.FromArgb(0x7A, 0x84, 0x98))
        g.FillRectangle(body, 0, 0, wd, ht)
        g.FillRectangle(bar, 0, 0, wd, Math.Min(ht, 30))
        var i = 0
        while i < 8 {
            let ly = 52 + i * 26
            if ly + 10 > ht { break }
            g.FillRectangle(line, 24, ly, Math.Max(10, (wd - 48) * (i % 3 == 2 ? 55 : 85) / 100), 10)
            i += 1
        }
        g.DrawRectangle(edge, 0, 0, wd - 1, ht - 1)
        // 標題（DrawString 才會跟著 Graphics 的位移；太長就截掉）
        let max = Math.Max(1, (wd - 20) / 14)
        let tt = title.Length > max ? title.Substring(0, Math.Max(1, max - 1)) + "…" : title
        let tb = SolidBrush(Color.FromArgb(0x2A, 0x2F, 0x45))
        g.DrawString(tt, MisWinForm.TitleFont, tb, 10.0, 6.0)
    }
}

// ================= 公仔這邊：演法（用現有的狀態）＋角色專屬的接口 =================
//@@IN Pet
    var misAct = ""                  // 正在演哪一個：grab／cry／fly／puppet（""＝沒有）
    var misPoseNow = "idle"
    var misPh = 0
    var misT: Double = 0, misX0: Double = 0, misY0: Double = 0, misX1: Double = 0, misY1: Double = 0, misDur: Double = 0, misArc: Double = 0, misHome: Double = 0
    var misCur = Point(0, 0)         // 搶游標：游標「應該」在的位置（不在＝你動了）
//@@END

extension Pet {
    var MisBusy: Bool { return misAct != "" }

    // Step 一開始呼叫：演到一半就由這裡控制（回傳 true＝這格處理完了）
    func MisStep(_ dt: Double) -> Bool {
        if misAct == "" { return false }
        var gone = dragging
        switch state {
        case "drag", "fling", "stowfly", "enter", "exit": gone = true
        default: break
        }
        if gone { MisRelease(); return false }
        misT += dt
        switch misAct {
        case "grab": MisGrabStep()
        case "cry": MisCryStep(dt)
        case "fly": MisFlyStep(dt)
        default: break
        }
        if misAct != "" { MisPose(misPoseNow) }   // 每格都套一次（別的地方改了狀態也拉回來）
        return true
    }

    // ---- 角色專屬版本的接口 ----
    // 新角色要自己的演法就加在這裡（例如之後的「躲躲」：搶游標的 hold／run 改成把游標藏進紙箱）。
    // what：wind 準備／leap 飛撲／hold 抓到／fall、run 拖著跑／drop 放下／caught 被抓到／brace、push 推視窗／
    //       cry 抱錢包哭／fly 被震飛／dizzy 暈／back 爬回來／idle
    // 回傳 true＝這隻自己設好了狀態；false＝用通用演法
    func MisCharPose(_ what: String) -> Bool {
        // 續命小隊（躲躲、沒電、刺刺）：狀態照通用的走（移動、物理不變），畫哪一張圖由 Pet.MisFrame 決定（51_original.swift）：
        // 躲躲抓到游標收進紙箱、拖著跑用「箱子長腳逃跑」；沒電搶到游標抱著當枕頭；刺刺抱錢包哭（圖上已經有錢包和眼淚）
        return false
    }
    // 抱著的小道具（預設：錢包）；角色專屬的道具也從這裡換
    func MisPropArt(_ what: String) -> [String]? { return what == "cry" && !P.Orig ? Pet.MIS_WALLET : nil }   // 續命小隊的哭圖已經畫了錢包

    // 通用演法：只用現有的狀態，每個角色都畫得出來
    func MisPose(_ what: String) {
        misPoseNow = what
        if MisCharPose(what) { return }
        switch what {
        case "wind": poseKind = "grin"; state = "pose"
        case "leap", "fall", "fly": state = "air"
        case "hold": state = "hug"
        case "run", "push", "back": state = "goto"
        case "brace": state = "kick"
        case "drop": state = "dance"
        case "caught", "dizzy": state = "dizzy"
        case "cry": state = "think"
        default: state = "idle"
        }
    }

    func MisLine(_ key: String) -> String { return Pick(World.MisLinesFor(P.Id, key)) }
    func MisOnFloor() -> Bool { return Math.Abs(y - Double(w.WA(Cx, y + Double(SH) / 2.0).Bottom - SH)) < 3 }

    // 演完：交還給平常的狀態（在半空中就掉下來）
    func MisFinish(_ pose: String, _ dur: Double) {
        misAct = ""; rolling = false
        w.MisPetDone(self)
        if supH == 0 && !MisOnFloor() { dizzyOnLand = pose == "caught" || pose == "dizzy"; Jump(0, 0); return }
        MisPose(pose)
        t = dur
    }
    // 被拖走、丟回櫃子：直接放掉
    func MisRelease() { misAct = ""; rolling = false; w.MisPetDone(self) }
    // World 叫停（全螢幕、躲起來、安靜…）
    func MisAbort() { if misAct != "" { MisFinish("idle", 1) } }

    // ---------- 搶游標 ----------
    func MisGrab(_ c: Point) {
        misAct = "grab"; misPh = 0; misT = 0; misCur = c
        supH = 0; sc = 1; rolling = false
        dir = Double(c.X) >= Cx ? 1 : -1
        MisPose("wind"); Mark(1)
        Say(MisLine("grab_start"), 2.6)
    }

    func MisGrabStep() {
        if misT > 6.5 && misPh < 4 { MisFinish("idle", 1); return }   // 最長幾秒：時間到就放手
        if misPh <= 3 && w.MisUserMoved(misCur) { MisCaught(); return }
        switch misPh {
        case 0:   // 準備（盯著游標）
            dir = Double(misCur.X) >= Cx ? 1 : -1
            if misT >= 0.6 {
                misPh = 1; misT = 0; misX0 = x; misY0 = y
                misX1 = Double(misCur.X) - Double(SW) / 2.0; misY1 = Double(misCur.Y) - Double(SH) * 0.45
                let d = Math.Sqrt((misX1 - x) * (misX1 - x) + (misY1 - y) * (misY1 - y))
                misDur = Clamp(d / (1100 * k), 0.45, 1.1); misArc = Math.Min(160 * k, d * 0.35)
                MisPose("leap")
            }
        case 1:   // 飛撲過去
            let f = Math.Min(1, misT / misDur)
            x = misX0 + (misX1 - misX0) * f; y = misY0 + (misY1 - misY0) * f - Math.Sin(Math.PI * f) * misArc
            if f >= 1 { misPh = 2; misT = 0; MisPose("hold"); Mark(1); Burst(6); _ = MisHoldCursor() }
        case 2:   // 抓到了
            if !MisHoldCursor() { return }
            if misT >= 0.3 {
                let wa = w.WA(Cx, y + Double(SH) / 2.0)
                let d2 = Cx - Double(wa.Left) > Double(wa.Right) - Cx ? -1 : 1   // 往空間大的那邊跑
                dir = d2
                misPh = 3; misT = 0; misX0 = x; misY0 = y; misY1 = Double(wa.Bottom - SH)
                misX1 = Clamp(x + Double(d2) * 520 * k, Double(wa.Left + 4), Double(wa.Right - SW - 4))
                misDur = 2.6
                MisPose(y < misY1 - 4 ? "fall" : "run")
                Say(MisLine("grab_carry"), 2.2)
            }
        case 3:   // 拖著游標跑
            let f = Math.Min(1, misT / misDur), fy = Math.Min(1, misT / 0.55)
            x = misX0 + (misX1 - misX0) * Ease(f)
            y = misY0 + (misY1 - misY0) * fy * fy
            if fy >= 1 && misPoseNow != "run" { MisPose("run") }
            if !MisHoldCursor() { return }
            if f >= 1 { misPh = 4; misT = 0; MisPose("drop"); Burst(6); Say(MisLine("grab_drop"), 2.4) }   // 放手（游標留在這）
        case 4:   // 嗆聲
            if misT >= 1.8 { MisFinish("idle", 1.5) }
        default: break
        }
    }

    // 游標放在手上（World 只有搶游標進行中、你沒按著滑鼠才會真的移）
    func MisHoldCursor() -> Bool {
        let hx = CInt(Math.Round(Cx + Double(dir * 4 * S))), hy = CInt(Math.Round(y + Double(SH) * 0.45))
        if !w.MisWarp(hx, hy) { MisCaught(); return false }
        misCur = w.MisCursor()
        return true
    }

    func MisCaught() {
        let held = misPh >= 2
        Say(MisLine(held ? "grab_caught" : "grab_seen"), 2.4)
        Mark(1)
        MisFinish("caught", 1.4)
    }

    // ---------- 購物警察：抱著錢包大哭 ----------
    func MisCry(_ site: String, _ n: Int) {
        misAct = "cry"; misPh = 0; misT = 0
        MisPose("cry")
        Say(MisLine(n >= 2 ? "shop_n" : "shop").Replace("{n}", World.MisNum(n)).Replace("{site}", site), 4.5)
        Mark(4)
        if Is("meidian") && SqBattery.Link { SqBattery.Level = Math.Max(0.0, SqBattery.Level - 0.02) }   // 錢包痛，電也痛
    }
    func MisCryStep(_ dt: Double) {
        if rnd.NextDouble() < dt * 2.5 { Mark(4) }
        if misT >= 4.6 { MisFinish("idle", 1.2) }
    }

    // ---------- 打字太兇：被震飛、暈一下、爬回來 ----------
    func MisFly() {
        misAct = "fly"; misPh = 0; misT = 0
        let wa = w.WA(Cx, y + Double(SH) / 2.0)
        let d = Cx - Double(wa.Left) > Double(wa.Right) - Cx ? -1 : 1
        misHome = x
        misX0 = x; misY0 = y
        misX1 = Clamp(x + Double(d) * R(380, 620) * k, Double(wa.Left + 4), Double(wa.Right - SW - 4))
        misY1 = Double(wa.Bottom - SH)
        misDur = 1.1; misArc = 260 * k
        supH = 0; sc = 1; dir = d; rolling = true
        MisPose("fly"); Burst(10); Mark(1)
        Say(MisLine("typing"), 2.4)
        if Is("meidian") && SqBattery.Link { SqBattery.Level = Math.Max(0.0, SqBattery.Level - 0.03) }   // 被震掉 3% 的電
    }
    func MisFlyStep(_ dt: Double) {
        switch misPh {
        case 0:
            let f = Math.Min(1, misT / misDur)
            x = misX0 + (misX1 - misX0) * f; y = misY0 + (misY1 - misY0) * f - Math.Sin(Math.PI * f) * misArc
            if f >= 1 { rolling = false; misPh = 1; misT = 0; MisPose("dizzy"); Burst(6) }
        case 1:
            if misT >= 1.3 { misPh = 2; misT = 0; dir = misHome > x ? 1 : -1; MisPose("back"); Say(MisLine("typing_back"), 2.4) }
        case 2:
            let sp = 70 * k * dt
            if Math.Abs(misHome - x) <= sp || misT > 5 { MisFinish("idle", 1.2); break }
            dir = misHome > x ? 1 : -1
            x += Double(dir) * sp
        default: break
        }
    }

    // ---------- 下班清場：位置由 World 控制（推視窗） ----------
    func MisPuppet(_ on: Bool) {
        if on { misAct = "puppet"; misT = 0; supH = 0; sc = 1; rolling = false; return }
        if misAct == "puppet" { MisFinish("idle", 1.2) }
    }

    // ---------- 畫：抱著的道具、眼淚（PaintPet 裡呼叫） ----------
    static let MIS_WALLET = [".kkkkkkk.", "kbbbbbbbk", "kbmmmmmbk", "kbbbbbggk", "kBBBBBggk", "kbbbbbbbk", ".kkkkkkk."]
    static func MisCol(_ c: Character) -> Color {
        switch c {
        case "k": return Color.FromArgb(0x2A, 0x22, 0x1E)
        case "b": return Color.FromArgb(0xB9, 0x7A, 0x45)
        case "B": return Color.FromArgb(0x8A, 0x55, 0x2E)
        case "g": return Color.FromArgb(0xF2, 0xC9, 0x4C)
        case "m": return Color.FromArgb(0x7C, 0xC6, 0x7A)
        case "t": return Color.FromArgb(0x7F, 0xC8, 0xFF)
        default: return Color.White
        }
    }
    static func MisPix(_ g: Graphics, _ art: [String], _ bx: Int, _ by: Int, _ ps: Int) {
        let hw = Math.Max(1, ps / 3)
        for pass in 0..<2 {
            for ry in 0..<art.count {
                let row = Array(art[ry])
                for rx in 0..<row.count {
                    let c = row[rx]
                    if c == "." { continue }
                    let b = SolidBrush(pass == 0 ? Color.White : Pet.MisCol(c))
                    if pass == 0 { g.FillRectangle(b, bx + rx * ps - hw, by + ry * ps - hw, ps + 2 * hw, ps + 2 * hw) }
                    else { g.FillRectangle(b, bx + rx * ps, by + ry * ps, ps, ps) }
                }
            }
        }
    }
    func MisDraw(_ g: Graphics, _ ox: Int, _ oy: Int) {
        if misAct != "cry" || P.Orig { return }   // 續命小隊的哭圖已經有錢包和眼淚
        if let art = MisPropArt("cry") {
            let ps = Math.Max(1, S * 2 / 3), aw = art[0].Length * ps, ah = art.count * ps
            Pet.MisPix(g, art, CInt(Math.Round(Cx - Double(aw) / 2.0)) - ox, CInt(Math.Round(y + Double(SH) * 0.58 - Double(ah) / 2.0)) - oy, ps)
        }
        // 眼淚：兩邊往下滴
        let tp = Math.Max(1, S / 2)
        let fall = (anim * 30 * k) % Double(7 * S)
        let tb = SolidBrush(Pet.MisCol("t"))
        var s = -1
        while s <= 1 {
            let tx = CInt(Math.Round(Cx + Double(s) * 3.5 * Double(S))) - ox
            let ty = CInt(Math.Round(y + Double((P.BodyTop - 3) * S) + fall)) - oy
            g.FillRectangle(tb, tx, ty, tp, tp * 2)
            g.FillRectangle(tb, tx, ty - 3 * tp, tp, tp)
            s += 2
        }
    }
}

// ================= World：什麼時候演、安全檢查、下班清場、設定、pipe =================
//@@IN World
    var mis: MisSys! = nil
    var misGrabMin = 3                   // 搶游標：滑鼠鍵盤都沒動幾分鐘
    var misClearDay = "", misShopMonth = ""
    var misShopN = 0
    var misGrabCd: Double = 0, misShopCd: Double = 0, misTypeCd: Double = 0, misCheckT: Double = 0, misShopSince: Double = 0
    var misGrabArmed = true
    var misShopSite = ""
    var MisKind = ""                     // 正在演哪一個：grab／clear／shop／typing（""＝沒有）
    var misPet: Pet! = nil
    var misKeysLast = -1
    var misBuckets: [Double] = [0, 0, 0, 0, 0, 0]   // 最近幾秒，每秒放開幾個按鍵（只有次數）
    var misBucket = 0
    var misBucketT: Double = 0
    var misPending = ""; var misPendingT: Double = 0   // 測試指令要演但公仔還在半空中：等一下再試
    // 下班清場
    let misPushed = List<MisWin>()       // 縮小（mac：隱藏）了的（還原用）
    let misQueue = List<MisWin>()
    var misForm: MisWinForm! = nil
    var misWin: MisWin! = nil
    var misWa = Rectangle(0, 0, 0, 0)
    var misPh = 0, misPushDir = 1, misDone = 0
    var misT: Double = 0, misJx0: Double = 0, misJy0: Double = 0, misJx1: Double = 0, misJy1: Double = 0
//@@END

extension World {
    // 小屋「搗蛋」的開關（存在 features.txt，跟其他開關一起）；搶游標預設關著
    static let MisFeatureList: [[String]] = [
        ["mis_grab", "搶游標（滑鼠停太久就被叼走）"],
        ["mis_clear", "下班清場（把視窗推出螢幕）"],
        ["mis_shop", "購物警察（逛購物網站會哭）"],
        ["mis_typing", "打字太兇（會被震飛）"]]
    static func MisDefaultOff(_ key: String) -> Bool { return key == "mis_grab" || key == "mis_typing" }   // 搶游標、打字太兇預設關

    // 購物網站：[ 顯示的名字, 視窗標題裡會出現的字… ]（不分大小寫、不看空白；要加網站就加一行）
    static let MisShops: [[String]] = [
        ["蝦皮", "蝦皮購物", "shopee"],
        ["momo", "momo購物", "momoshop"],
        ["PChome", "pchome24h", "24h購物", "pchome商店街"],
        ["露天", "露天拍賣", "露天市集", "ruten"],
        ["淘寶", "淘寶", "淘宝", "taobao", "天貓", "天猫", "tmall"],
        ["Amazon", "amazon.com", "amazon.co.jp", "amazon.co.uk", "amazon.de", "amazon.ca", "amazon.sg", "亞馬遜購物"],
        ["樂天", "樂天市場", "楽天市場", "rakutenichiba"],
        ["博客來", "博客來", "books.com.tw"],
        ["Yahoo 購物中心", "yahoo購物", "yahoo奇摩購物", "yahoo!奇摩購物", "yahoo奇摩超級商城"],
        ["AliExpress", "aliexpress", "速賣通"],
        ["酷澎", "酷澎", "coupang"],
        ["SHEIN", "shein"],
        ["Temu", "temu"],
        ["東森購物", "東森購物", "etmall"],
        ["誠品線上", "誠品線上", "eslite.com"]]

    static func MisShopSite(_ title: String?) -> String? {
        let t = (title ?? "").ToLowerInvariant().Replace(" ", "")
        if t == "" { return nil }
        for s in World.MisShops {
            var i = 1
            while i < s.count { if t.Contains(s[i].ToLowerInvariant().Replace(" ", "")) { return s[0] }; i += 1 }
        }
        return nil
    }

    // 簡報播放中（就算沒有全螢幕）也不搗蛋
    static func MisPresenting(_ t: String?) -> Bool {
        let l = (t ?? "").ToLowerInvariant()
        return l.Contains("投影片放映") || l.Contains("簡報者檢視") || l.Contains("簡報播放") || l.Contains("slide show") || l.Contains("presenter view") || l.Contains("keynote")
    }

    // ---- 台詞（寫死、無厘頭）：先找「角色 id.key」，沒有就用通用的 ----
    static let MisLines: [String: [String]] = World.MisLinesInit()
    static func MisLinesInit() -> [String: [String]] {
        var d: [String: [String]] = [:]
        d["grab_start"] = ["你的游標我先保管", "這個游標沒人用？那我帶走囉", "游標借我玩一下下", "嘿嘿…游標是我的了"]
        d["grab_carry"] = ["嘿咻嘿咻～", "來追我啊～", "游標好重喔…", "快跑快跑！"]
        d["grab_drop"] = ["放這邊，自己來拿～", "游標寄放在這，不用謝", "好啦還你，我只是帶它散散步", "游標說它玩得很開心"]
        d["grab_caught"] = ["被抓到了！還你還你", "好快！還給你啦", "我只是幫你擦擦游標…", "哎呀被發現了"]
        d["grab_seen"] = ["咦！你在喔？", "沒、沒有要拿你的游標啦", "（假裝路過）"]
        d["clear_start"] = ["下班了！視窗們也該回家了", "清場時間到～", "叮咚，今天的視窗營業到這裡", "下班囉，大家收工！"]
        d["clear_push"] = ["嘿咻～推推推", "視窗們回家囉～", "這個也下班！"]
        d["clear_done"] = ["下班了，視窗都回家了", "清乾淨了！快回家吧", "桌面好乾淨～明天見", "視窗都下班了，換你了"]
        d["clear_restore"] = ["好啦好啦，視窗都回來了", "視窗回來加班了…你也辛苦了", "全部叫回來了～"]
        d["shop"] = ["{site}…錢包在哭，我也在哭", "購物車放著就好，不要結帳啊～", "這個真的需要嗎…（抱緊錢包）", "{site}又在叫你了對不對"]
        d["shop_n"] = ["這個月已經買第{n}次了欸", "第{n}次了…錢包要離家出走了", "{site}第{n}次…我的錢包好痛"]
        d["typing"] = ["哇啊啊！鍵盤地震！", "打太兇了啦～", "鍵盤要冒煙了！", "你是在跟鍵盤吵架嗎"]
        d["typing_back"] = ["呼…爬回來了", "我回來了…輕一點打好嗎", "飛好遠…先喘一下", "鍵盤颱風過了嗎…"]
        // 續命小隊
        d["duoduo.grab_start"] = ["游標…我先收進箱子保管", "這個游標…可以住我的箱子嗎", "（箱子打開）游標，進來"]
        d["duoduo.grab_carry"] = ["箱子長腳了！跑！", "（箱子咚咚咚跑走）", "不、不要追我！"]
        d["duoduo.grab_drop"] = ["還、還你…放這裡了", "游標在箱子裡睡著了…還你", "（從箱子裡把游標推出來）"]
        d["duoduo.grab_caught"] = ["被發現了！還你還你", "我、我只是幫你保管！"]
        d["duoduo.clear_start"] = ["下班了…視窗們也該回箱子了", "（推推）視窗回家…"]
        d["duoduo.shop"] = ["{site}的箱子…會送來跟我搶位子嗎", "又要買新的箱子嗎…（抱緊錢包）"]
        d["duoduo.shop_n"] = ["這個月第{n}個包裹了…家裡箱子比我還多", "第{n}次了…我的箱子要被比下去了"]
        d["duoduo.typing"] = ["鍵盤地震！我的箱子要塌了", "哇啊啊箱子飛起來了！"]
        d["duoduo.typing_back"] = ["呼…箱子還在…我回來了", "（箱子長腳慢慢走回來）"]
        d["meidian.grab_start"] = ["借你的游標當枕頭", "這游標看起來很好睡", "游標借我充電一下"]
        d["meidian.grab_carry"] = ["嘿…咻…（好耗電）", "拖著游標好累…"]
        d["meidian.grab_drop"] = ["（抱著游標睡著了）zZ", "游標當枕頭剛剛好…還你", "睡飽了…游標還你"]
        d["meidian.clear_start"] = ["我快沒電了，視窗們也一起關機吧", "下班了…大家都去充電"]
        d["meidian.shop_n"] = ["第{n}次了…我的電跟你的錢一起在掉", "這個月第{n}次…電量和存款都紅了"]
        d["meidian.typing"] = ["震掉我 3% 了！", "哇啊！電要灑出來了！"]
        d["meidian.typing_back"] = ["呼…電還在…爬回來了", "（慢慢走回來）剩一點電了"]
        d["cici.grab_start"] = ["這游標我沒收了", "游標借我。不還", "哼，游標歸我"]
        d["cici.grab_caught"] = ["哼，誰要你的游標", "拿去！才不稀罕"]
        d["cici.grab_drop"] = ["放這裡了。不是故意的", "還你。…才沒有很好玩"]
        d["cici.clear_done"] = ["下班。不是為了你，是視窗很吵", "清乾淨了。快回家"]
        d["cici.shop"] = ["買那個幹嘛…（偷看）多少錢", "{site}？…錢包在哭，我才沒有"]
        d["cici.typing"] = ["再打那麼大力我要炸毛了", "盆、盆要翻了！"]
        d["cici.typing_back"] = ["哼，我自己走回來的", "土都灑出來了…"]
        // 窩伴小世界（溫柔版的搗蛋）
        d["fanfan.grab_start"] = ["游標借我當書籤一下下", "你休息一下，游標我幫你顧著", "（把游標夾進書裡）"]
        d["fanfan.grab_drop"] = ["游標還你～剛剛有好好休息嗎", "書籤用完了，還你"]
        d["fanfan.grab_caught"] = ["被找到了～還你還你", "我只是想讓你休息一下"]
        d["fanfan.clear_start"] = ["下班了，書闔起來，視窗也收一收", "今天的頁數夠了，我們收工"]
        d["fanfan.clear_done"] = ["桌面整理好了，今天辛苦了", "收好了，明天從這裡繼續"]
        d["fanfan.shop"] = ["{site}…這個真的需要嗎？先放購物車一晚", "要不要先想一下下再買？"]
        d["fanfan.typing"] = ["哇，書頁被吹走了～", "打字好用力，手會痛喔"]
        d["fanfan.typing_back"] = ["書籤撿回來了，我回來了", "（抱著書走回來）輕輕打就好"]
        d["bobo.grab_start"] = ["游標先放旁邊，喝口水吧", "（把游標收進圍裙口袋）休息一下", "游標我先保管，你去倒杯水"]
        d["bobo.grab_drop"] = ["喝完水了嗎？游標還你", "放這裡了～"]
        d["bobo.grab_caught"] = ["被發現了～還你，記得喝水", "好啦還你"]
        d["bobo.clear_start"] = ["下班了，視窗們也該吃晚餐了", "收工囉，去吃飯吧"]
        d["bobo.clear_done"] = ["收好了，快去吃飯", "桌面乾乾淨淨，晚餐吃什麼呢"]
        d["bobo.shop"] = ["{site}…錢包說它有點累", "買之前先喝口水，冷靜一下"]
        d["bobo.shop_n"] = ["這個月第{n}次了，錢包也要休息喔", "第{n}次了…今天先不要好不好"]
        d["bobo.typing"] = ["哇，水杯差點翻了～", "輕一點點，手腕會酸"]
        d["bobo.typing_back"] = ["水沒灑，我回來了", "（端著水杯走回來）慢慢打"]
        d["mian.grab_start"] = ["游標也想休息一下", "（抱著游標）一起放空一分鐘", "游標借我抱一下下"]
        d["mian.grab_drop"] = ["游標休息好了，還你", "抱完了～還你"]
        d["mian.grab_caught"] = ["被找到了～還你", "好，還你，記得深呼吸"]
        d["mian.clear_start"] = ["下班了，讓視窗也休息吧", "今天就到這裡，慢慢收"]
        d["mian.clear_done"] = ["都收好了，好好休息", "桌面空空的，心也輕輕的"]
        d["mian.shop"] = ["{site}…想買的話，明天再看一次好嗎", "深呼吸～真的需要嗎"]
        d["mian.typing"] = ["哇～被吹得軟軟地飛走了", "打字好用力，肩膀放鬆"]
        d["mian.typing_back"] = ["飄回來了～輕輕打就好", "（慢慢飄回來）呼…"]
        return d
    }
    static func MisLinesFor(_ id: String, _ key: String) -> [String] {
        if let a = World.MisLines[id + "." + key] { return a }
        if let a = World.MisLines[key] { return a }
        return ["嘿嘿"]
    }
    static let MisZh = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
    static func MisNum(_ n: Int) -> String { return n >= 0 && n <= 10 ? World.MisZh[n] : String(n) }

    func MisStart() {
        let real = !App.Offscreen || ProcessInfo.processInfo.environment["DESKPALS_MISCHIEF_REAL"] == "1"
        mis = real ? MisSys() : (MisFake() as MisSys)
        MisLoad()
        App.Log("mischief: " + (real ? "real" : "fake") + MisFlags())
    }

    // 收工前：停掉、把視窗全部叫回來、不再數按鍵
    func MisQuit() {
        if mis == nil { return }
        MisStop(); MisRestore(false); mis.KeyWatch(false)
    }

    func MisLoad() {
        for line in World.ReadText("mischief.txt").components(separatedBy: "\n") {
            let a = line.Trim().components(separatedBy: "=")
            if a.count != 2 { continue }
            let v = a[1].Trim()
            var n = 0
            switch a[0].Trim() {
            case "grabmin": if int.TryParse(v, &n) { misGrabMin = Math.Max(1, Math.Min(60, n)) }
            case "clearday": misClearDay = v
            case "shopmonth": misShopMonth = v
            case "shopn": if int.TryParse(v, &n) { misShopN = n }
            default: break
            }
        }
    }
    func MisSave() {
        World.WriteText("mischief.txt", "grabmin=" + String(misGrabMin) + "\nclearday=" + misClearDay + "\nshopmonth=" + misShopMonth + "\nshopn=" + String(misShopN) + "\n")
    }

    // 開關改了（小屋＝你自己按的；VS Code 推的不算）
    func MisFeatChanged(_ key: String, _ on: Bool, _ user: Bool) {
        if !key.StartsWith("mis_") || mis == nil { return }
        if key == "mis_typing" && on && user { mis.AskKeyPermission() }   // mac: 只在你自己打開時問一次「輸入監控」
        if !on && MisKind != "" && "mis_" + MisKind == key { MisStop() }
        misCheckT = 0
    }

    // VS Code 推設定：mischief-set grab|clear|shop|typing 0|1、grabmin <分>
    func MisSet(_ key: String, _ val: String) {
        if key == "grabmin" { var m = 0; if int.TryParse(val, &m) { misGrabMin = Math.Max(1, Math.Min(60, m)); MisSave() }; return }
        let fk = "mis_" + key
        var known = false
        for f in World.MisFeatureList { if f[0] == fk { known = true } }
        if !known { return }
        let on = val != "0"
        if Feat(fk) == on { return }
        feats[fk] = on
        SaveFeatures()
        App.Log("feature " + fk + "=" + (on ? "1" : "0") + " (VS Code)")
        MisFeatChanged(fk, on, false)
    }

    func MisMsg(_ c: Client, _ p: [String], _ line: String) -> Bool {
        switch p[0] {
        case "mischief-set": if p.count >= 3 { MisSet(p[1], p[2]) }; return true
        case "mischief-dump": World.Send(c, MisDump()); return true
        case "mischief-fake": MisFakeCmd(p, line); return true
        case "mischief-site": World.Send(c, "site " + (World.MisShopSite(World.MisRest(line, 1)) ?? "-") + "\n"); return true   // 測試：這個標題算哪個購物網站
        default: return false
        }
    }

    func MisAct(_ arg: String) {
        switch arg {
        case "cursor", "grab", "clear", "shop", "typing": misPending = arg; misPendingT = Now + 6; MisRunPending()
        case "restore": MisRestore(true)
        case "stop": misPending = ""; MisStop()
        default: break
        }
    }

    // 測試指令：公仔準備好（在地上、沒在演別的）就演
    func MisRunPending() {
        if misPending == "" { return }
        if Now > misPendingT { App.Log("mischief: " + misPending + " not ready, skipped"); misPending = ""; return }
        if MisKind != "" || !MisReady(Lead(), true) { return }
        let a = misPending; misPending = ""
        switch a {
        case "cursor", "grab": _ = MisStartGrab(true)
        case "clear": MisStartClear(true)
        case "shop": MisStartShop(World.MisShopSite(mis.FgTitle()) ?? "購物網站")
        case "typing": MisStartTyping()
        default: break
        }
    }

    func MisFakeCmd(_ p: [String], _ line: String) {
        guard let f = mis as? MisFake, p.count >= 2 else { return }
        var a = 0, b = 0, c = 0, d = 0
        var v: Double = 0
        switch p[1] {
        case "cursor": if p.count >= 4 && int.TryParse(p[2], &a) && int.TryParse(p[3], &b) { f.Cur = Point(a, b) }
        case "input": f.Stamp += 1000; f.IdleSec = 0; f.KeyDown = true
        case "button": f.Btn = p.count >= 3 && p[2] == "1"
        case "fs": f.Fs = p.count >= 3 && p[2] == "1"
        case "idle": if p.count >= 3 && double.TryParse(p[2], &v) { f.IdleSec = v }
        case "fg": f.Fg = World.MisRest(line, 2)
        case "typing":
            if p.count >= 4 && double.TryParse(p[2], &v) && int.TryParse(p[3], &a) { _ = f.KeyCount(); f.Rate = v; f.RateLast = f.T; f.RateUntil = f.T + Double(a) }
        case "win":
            if p.count >= 6 && int.TryParse(p[2], &a) && int.TryParse(p[3], &b) && int.TryParse(p[4], &c) && int.TryParse(p[5], &d) { f.AddWin(Rectangle(a, b, c, d), World.MisRest(line, 6)) }
        case "clock":
            var want = DateTime.Now
            if p.count >= 3 && DateTime.TryParse(p[2], &want) { f.Shift = want - DateTime.Now } else { f.Shift = TimeSpan.Zero }
        case "reset": f.Wins.Clear(); f.Calls.Clear(); f.Warps = 0; f.Fg = ""; f.Btn = false; f.Fs = false; f.IdleSec = 0; f.Rate = 0
        default: break
        }
    }
    // 第 n 個空白之後的全部（標題可以有空白）
    static func MisRest(_ line: String, _ n: Int) -> String {
        let t = line.Trim()
        var i = -1
        var k2 = 0
        while k2 < n { i = t.IndexOf(" ", i + 1); if i < 0 { return "" }; k2 += 1 }
        return t.Substring(i + 1)
    }

    // mac: Swift 的型別推斷吃不下一整串 + 和 ?:，拆成幾段
    func MisFlags() -> String {
        var s = " grab=" + (Feat("mis_grab") ? "1" : "0")
        s += " clear=" + (Feat("mis_clear") ? "1" : "0")
        s += " shop=" + (Feat("mis_shop") ? "1" : "0")
        s += " typing=" + (Feat("mis_typing") ? "1" : "0")
        s += " grabmin=" + String(misGrabMin)
        return s
    }

    func MisDump() -> String {
        let sb = StringBuilder()
        let l: Pet! = Lead()
        var lead = "-"
        if l != nil { lead = l.P.Id + ":" + l.state; if l.MisBusy { lead += ":busy" } }
        let notice = current != nil && current.Kind == "mis-restore" ? "1" : "0"
        sb.Append("mischief backend=" + (mis.Fake ? "fake" : "real"))
        sb.Append(" kind=" + (MisKind == "" ? "-" : MisKind))
        sb.Append(MisFlags())
        sb.Append(" pushed=" + String(misPushed.Count))
        sb.Append(" form=" + (misForm != nil ? "1" : "0"))
        sb.Append(" clearday=" + (misClearDay == "" ? "-" : misClearDay))
        sb.Append(" shopn=" + String(misShopN) + " notice=" + notice + " lead=" + lead + "\n")
        sb.Append(mis.Dump())
        sb.Append("end\n")
        return sb.ToString()
    }

    // ---- 安全檢查 ----
    func MisReady(_ l: Pet!, _ allowSleep: Bool) -> Bool {
        if l == nil || !l.Out || l.InScene || l.Dragging || l.MisBusy || !l.Grounded() { return false }
        return allowSleep || l.state != "sleep"
    }
    // 絕對不搗蛋：全螢幕（遊戲、影片）、簡報、分享螢幕、躲起來、按著滑鼠鍵、選單開著
    func MisSafeCore() -> Bool {
        if Hidden || fsNow || sharing || pmenu != nil || mis.Fullscreen() || mis.Buttons() { return false }
        return !World.MisPresenting(mis.FgTitle())
    }
    // 平常（自己跑出來搗蛋）再加上：安靜、專注時不搗蛋
    func MisSafe() -> Bool { return !quietOn && !focusOn && MisSafeCore() }

    func MisTick(_ dt: Double) {
        if mis == nil { return }
        if let fk = mis as? MisFake { fk.T = Now }
        misGrabCd -= dt; misShopCd -= dt; misTypeCd -= dt
        if MisKind == "clear" { MisClearStep(dt) }
        if MisKind != "" && (Hidden || fsNow || sharing || quietOn || focusOn || mis.Fullscreen()) { App.Log("mischief: stopped (" + MisKind + ")"); MisStop() }
        if MisKind != "" && MisKind != "clear" && (misPet == nil || !misPet.MisBusy) { MisKind = ""; misPet = nil }
        MisKeys(dt)
        MisRunPending()
        misCheckT -= dt
        if misCheckT > 0 { return }
        misCheckT = 0.5
        mis.KeyWatch(Feat("mis_typing") && !Hidden && !fsNow)   // 全螢幕（遊戲）、躲起來時不數
        if MisKind != "" || !MisSafe() { return }
        if Feat("mis_clear") && MisClearDue() { MisStartClear(false); return }
        if Feat("mis_shop") { MisShopCheck() }
        if MisKind == "" && Feat("mis_grab") { MisGrabCheck() }
    }

    func MisStop() {
        if MisKind == "clear" { MisClearEnd(); return }
        let p = misPet
        MisKind = ""; misPet = nil
        if p != nil && p!.MisBusy { p!.MisAbort() }
    }

    // 公仔演完了（自己結束、被抓到、被拖走）
    func MisPetDone(_ p: Pet) {
        if p !== misPet || MisKind == "clear" { return }
        MisKind = ""; misPet = nil
    }

    // ---------- 搶游標 ----------
    func MisGrabCheck() {
        if misGrabCd > 0 { return }
        if mis.Idle() < Double(misGrabMin) * 60.0 { misGrabArmed = true; return }
        if !misGrabArmed { return }   // 同一段沒動只搶一次
        if MisStartGrab(false) { misGrabArmed = false }
    }

    func MisStartGrab(_ force: Bool) -> Bool {
        let l: Pet! = Lead()
        if !MisReady(l, true) || !MisSafeCore() { return false }
        let c = mis.CursorPos()
        if !Inside(Double(c.X), Double(c.Y)) { return false }
        l.WakeIfSleep()
        MisKind = "grab"; misPet = l; misGrabCd = 15 * 60
        mis.KeyPrime()
        l.MisGrab(c)
        App.Log("mischief grab" + (force ? " (asked)" : ""))
        return true
    }

    // 公仔要移游標：只有搶游標進行中、你沒按著滑鼠時才會真的移；一定在螢幕裡面
    func MisWarp(_ x0: Int, _ y0: Int) -> Bool {
        if MisKind != "grab" || mis.Buttons() { return false }
        let wa = WA(Double(x0), Double(y0))
        let x = Math.Max(wa.Left + 1, Math.Min(wa.Right - 2, x0))
        let y = Math.Max(wa.Top + 1, Math.Min(wa.Bottom - 2, y0))
        mis.Warp(x, y)
        return true
    }
    func MisCursor() -> Point { return mis.CursorPos() }
    // 你動了嗎：按著滑鼠鍵、有任何輸入（最後輸入時間變了）、游標不在公仔放的地方
    // 你動了嗎：按著滑鼠鍵、按了鍵盤、游標不在公仔放的地方（容忍 4 px）。不看「最後輸入時間」：公仔自己移游標之後系統也可能更新它
    func MisUserMoved(_ expect: Point) -> Bool {
        if mis.Buttons() || mis.KeyPressed() { return true }
        let c = mis.CursorPos()
        return Math.Abs(c.X - expect.X) > 4 || Math.Abs(c.Y - expect.Y) > 4
    }

    // ---------- 購物警察 ----------
    func MisShopCheck() {
        guard let site = World.MisShopSite(mis.FgTitle()) else { misShopSite = ""; return }
        if site != misShopSite { misShopSite = site; misShopSince = Now; return }
        if Now - misShopSince < 2 || misShopCd > 0 { return }   // 停在購物網站 2 秒以上才算；哭過之後 20 分鐘內不再哭
        MisStartShop(site)
    }

    func MisStartShop(_ site: String) {
        let l: Pet! = Lead()
        if !MisReady(l, true) || !MisSafeCore() { return }
        l.WakeIfSleep()
        misShopCd = 20 * 60
        let month = mis.Clock().ToString("yyyy-MM")
        if month != misShopMonth { misShopMonth = month; misShopN = 0 }
        misShopN += 1
        MisSave()
        MisKind = "shop"; misPet = l
        l.MisCry(site, misShopN)
        App.Log("mischief shop #" + String(misShopN))
    }

    // ---------- 打字太兇（只有每秒幾下的次數） ----------
    func MisKeys(_ dt: Double) {
        let kc = mis.KeyCount()
        if misKeysLast < 0 || kc < misKeysLast { misKeysLast = kc }
        misBuckets[misBucket] += Double(kc - misKeysLast)
        misKeysLast = kc
        if Now - misBucketT < 1 { return }   // 每一格是牆上時間的 1 秒（主迴圈卡住也一樣）
        misBucketT = Now
        // 最近 4 秒：每一秒都 ≥ 6 下、加起來 ≥ 36 下 → 震飛
        var fast = true
        var sum: Double = 0
        for i in 0..<4 { let v = misBuckets[(misBucket - i + 6) % 6]; sum += v; if v < 6 { fast = false } }
        misBucket = (misBucket + 1) % 6
        misBuckets[misBucket] = 0
        if fast && sum >= 36 && misTypeCd <= 0 && MisKind == "" && Feat("mis_typing") && MisSafe() { MisStartTyping() }
    }

    func MisStartTyping() {
        let l: Pet! = Lead()
        if !MisReady(l, true) || !MisSafeCore() { return }
        l.WakeIfSleep()
        misTypeCd = 10 * 60
        for i in 0..<misBuckets.count { misBuckets[i] = 0 }
        MisKind = "typing"; misPet = l
        l.MisFly()
        App.Log("mischief typing")
    }

    // ---------- 下班清場 ----------
    func MisClearDue() -> Bool {
        if !Feat("night") || forceNight == 0 { return false }   // 跟「下班時間」同一套：平日 18:00 之後
        let n = mis.Clock()
        if n.DayOfWeek == DayOfWeek.Saturday || n.DayOfWeek == DayOfWeek.Sunday { return false }
        if n.Hour < 18 || n.Hour >= 21 || (n.Hour == 18 && n.Minute < 1) { return false }   // 18:00 那一分鐘先讓「今天的小結」講
        if misClearDay == n.ToString("yyyy-MM-dd") { return false }   // 一天一次
        return mis.Idle() < 60   // 人在電腦前才演（不在就等你回來）
    }

    func MisStartClear(_ force: Bool) {
        let l: Pet! = Lead()
        if !MisReady(l, true) || !MisSafeCore() { return }
        misClearDay = mis.Clock().ToString("yyyy-MM-dd")
        MisSave()
        let wins = mis.Windows(self, 3)
        if wins.Count == 0 { if force { l.Say("下班了！桌面已經很乾淨了，快回家吧", 3) }; return }
        l.WakeIfSleep()
        MisKind = "clear"; misPet = l
        misQueue.Clear(); misQueue.AddRange(wins); misDone = 0
        l.MisPuppet(true)
        l.MisPose("wind"); l.Mark(1)
        l.Say(l.MisLine("clear_start"), 2.6)
        misPh = 0; misT = 0
        App.Log("mischief clear " + String(wins.Count) + " window(s)" + (force ? " (asked)" : ""))
    }

    func MisClearStep(_ dt: Double) {
        let l: Pet! = misPet
        if l == nil || !l.MisBusy || !l.Out { MisClearEnd(); return }
        misT += dt
        switch misPh {
        case 0: if misT >= 1.3 { MisClearNext() }
        case 1:   // 跳到視窗邊
            let f = Math.Min(1, misT / 0.7)
            l.x = misJx0 + (misJx1 - misJx0) * f
            l.y = misJy0 + (misJy1 - misJy0) * f - Math.Sin(Math.PI * f) * 120 * k
            l.dir = misJx1 >= misJx0 ? 1 : -1
            if f >= 1 { misPh = 2; misT = 0; l.dir = misPushDir; l.MisPose("brace") }
        case 2:   // 頂住
            if misT >= 0.45 { misPh = 3; misT = 0; l.MisPose("push"); if misDone == 0 { l.Say(l.MisLine("clear_push"), 1.8) } }
        case 3:   // 推出去（越推越快）
            let f = Math.Min(1, misT / 1.5), e = f * f
            let r = misWin.R
            let dist: Double = misPushDir < 0 ? Double(r.Right - misWa.Left + 30) : Double(misWa.Right - r.Left + 30)
            let fx = CInt(Math.Round(Double(r.X) + Double(misPushDir) * dist * e))
            if misForm != nil { misForm.Location = Point(fx, r.Y) }
            let edge: Double = misPushDir < 0 ? Double(fx + r.Width) : Double(fx)
            let px: Double = edge - Double(l.SW) * (misPushDir < 0 ? 0.25 : 0.75)
            l.x = World.Mid(px, Double(misWa.Left), Double(misWa.Right - l.SW))
            if rnd.NextDouble() < dt * 2 { l.Mark(4) }
            if f >= 1 { MisCloseForm(); misDone += 1; misPh = 4; misT = 0; l.MisPose("idle") }
        case 4: if misT >= 0.35 { MisClearNext() }
        default: break
        }
    }

    // 下一個視窗：先蓋上假視窗 → 真的縮小（mac：隱藏 App）→ 公仔跳到要推的那一邊
    func MisClearNext() {
        let l: Pet! = misPet
        while misQueue.Count > 0 {
            let mw = misQueue[0]
            misQueue.RemoveAt(0)
            let wa = WA(Double(mw.R.X) + Double(mw.R.Width) / 2.0, Double(mw.R.Y) + Double(mw.R.Height) / 2.0)
            let b = mis.Capture(mw)
            let f = MisWinForm(b, mw.Title, mw.R)
            f.Show(); f.Refresh()
            Zorder()
            if !mis.Minimize(mw) { f.Close(); continue }
            misPushed.Add(mw)
            misForm = f; misWin = mw; misWa = wa
            let wcx: Double = Double(mw.R.X) + Double(mw.R.Width) / 2.0
            let scx: Double = Double(wa.X) + Double(wa.Width) / 2.0
            misPushDir = wcx < scx ? -1 : 1   // 往近的那一邊推
            let edge: Double = misPushDir < 0 ? Double(mw.R.Right) : Double(mw.R.Left)
            let px: Double = edge - Double(l.SW) * (misPushDir < 0 ? 0.25 : 0.75)
            misJx0 = l.x; misJy0 = l.y
            misJx1 = World.Mid(px, Double(wa.Left), Double(wa.Right - l.SW))
            misJy1 = Double(Math.Min(mw.R.Bottom, wa.Bottom) - l.SH)
            misPh = 1; misT = 0
            l.MisPose("leap")
            return
        }
        MisClearEnd()
    }

    func MisCloseForm() { if misForm != nil { misForm.Close(); misForm = nil } }

    func MisClearEnd() {
        MisCloseForm()
        misQueue.Clear()
        let l: Pet! = misPet
        MisKind = ""; misPet = nil
        if l != nil && l.MisBusy { l.MisPuppet(false) }
        if misPushed.Count == 0 || l == nil { return }
        // 點公仔（或泡泡）＝全部叫回來；10 分鐘內有效，之後小屋選單也叫得回來
        let n = Notice()
        n.Kind = "mis-restore"; n.Text = ""; n.Pri = 1; n.By = l; n.Expire = Now + 600; n.At = DateTime.Now
        current = n
        l.SetClickableBubble(true)
        l.Say(l.MisLine("clear_done"), 8, false, "點我把視窗叫回來")
    }

    func MisClicked(_ p: Pet, _ n: Notice) -> Bool {
        if n.Kind != "mis-restore" { return false }
        MisRestore(true)
        return true
    }

    // 推走的視窗全部叫回來（後面的先，最前面那個最後、拿回焦點）
    func MisRestore(_ say: Bool) {
        if mis == nil { return }
        if misPushed.Count == 0 { if say { Lead().Say("沒有被推走的視窗喔", 1.6) }; return }
        var i = misPushed.Count - 1
        while i >= 0 { mis.Restore(misPushed[i], i == 0); i -= 1 }
        let cnt = misPushed.Count
        misPushed.Clear()
        if current != nil && current.Kind == "mis-restore" { if current.By != nil { current.By.SetClickableBubble(false) }; current = nil }
        App.LogAlways("mischief: restored " + String(cnt) + " window(s)")
        if say { let l: Pet! = Lead(); l.Say(l.MisLine("clear_restore"), 2.4) }
    }

    // ---------- 小屋選單 ----------
    func MisHouseMenu(_ m: ContextMenuStrip) {
        let sub = ToolStripMenuItem("搗蛋（惡作劇開關）")
        for f in World.MisFeatureList {
            let key = f[0]
            let mi = ToolStripMenuItem(f[1])
            mi.CheckOnClick = true
            mi.Checked = Feat(key)
            mi.Click = { [unowned mi] in self.SetFeat(key, !self.Feat(key)); mi.Checked = self.Feat(key) }
            sub.DropDownItems.Add(mi)
        }
        let gm = ToolStripMenuItem("搶游標：滑鼠停多久（現在 " + String(misGrabMin) + " 分）")
        for mm in [1, 3, 5, 10] {
            let m2 = mm
            let it = ToolStripMenuItem(String(m2) + " 分鐘", nil, { self.misGrabMin = m2; self.MisSave(); self.Lead().Say("好～滑鼠停 " + String(m2) + " 分鐘我就來搶", 2) })
            it.Checked = misGrabMin == m2
            gm.DropDownItems.Add(it)
        }
        sub.DropDownItems.Add(gm)
        m.Items.Add(sub)
        if misPushed.Count > 0 { m.Items.Add("把推走的視窗叫回來（" + String(misPushed.Count) + " 個）", nil, { self.MisRestore(true) }) }
    }

    // ---------- 離屏截圖：假視窗、假游標 ----------
    func MisSnapWins(_ g: Graphics) {
        if let fk = mis as? MisFake {
            var i = fk.Wins.Count - 1
            while i >= 0 {
                let m = fk.Wins[i]
                i -= 1
                if m.Min { continue }
                let st = g.Save()
                g.TranslateTransform(Double(m.R.X), Double(m.R.Y))
                MisWinForm.DrawWin(g, nil, m.Title, m.R.Width, m.R.Height)
                g.Restore(st)
            }
        }
        if misForm != nil && misForm.VVisible { misForm.PaintTo(g) }
    }
    static let MIS_ARROW = ["k.......", "kk......", "kwk.....", "kwwk....", "kwwwk...", "kwwwwk..", "kwwwwwk.", "kwwwkkkk", "kwkwk...", "kk.kwk..", "k...kwk.", "....kk.."]
    func MisSnapCursor(_ g: Graphics) {
        guard let fk = mis as? MisFake else { return }
        let ps = 2
        for ry in 0..<World.MIS_ARROW.count {
            let row = Array(World.MIS_ARROW[ry])
            for rx in 0..<row.count {
                let c = row[rx]
                if c == "." { continue }
                g.FillRectangle(c == "k" ? Brushes.Black : Brushes.White, fk.Cur.X + rx * ps, fk.Cur.Y + ry * ps, ps, ps)
            }
        }
    }
}
