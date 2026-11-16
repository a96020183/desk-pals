// 30_pet_a.swift — port of DeskPals.cs lines 1572–2696 (Pet partial #1: owns `final class Pet`)

final class Pet {
    var P: Pal!
    var w: World!
    var S = 0, SW = 0, SH = 0
    var k: Double = 0
    var rnd: Random!
    var Form: PetForm! = nil
    var Menu: ContextMenuStrip! = nil
    var Bub: BubbleForm! = nil

    var Out = false              // 在桌面上（含出櫃、回櫃的動畫）
    var InScene = false          // 正在演串場戲（由 World 控制）
    var x: Double = 0, y: Double = 0, vx: Double = 0, vy: Double = 0, t: Double = 0, anim: Double = 0, sense: Double = 0, z: Double = 0
    var dir = 1
    var state = "air"
    var sleepMode = false
    var sc: Double = 1, gt: Double = 0, knock: Double = 0     // 敲螢幕：放大倍率、計時、敲的晃動
    var afterGlass = ""

    // Spidey：絲的錨點／擺盪／倒吊／爬牆／噴絲
    var ax: Double = 0, ay: Double = 0, ropeL: Double = 0, th: Double = 0, om: Double = 0, targetL: Double = 0; var hangPhase = 0
    var wallSide = 0, climbDir = 0
    var shootT: Double = 0; var nextAct = ""; var zipH: IntPtr = 0; var zipRight = false
    var reelT: Double = 0, reelX: Double = 0, reelY: Double = 0
    var supH: IntPtr = 0; var supL = 0, supR = 0, supWinL = 0
    var goClimb = false
    var seekX: Double = 0

    var bubble = ""; var Bt: Double = 0; var bubbleAlert = false
    var dragging = false, dragSaid = false; var dragStart = Point(0, 0); var grabDx: Double = 0, grabDy: Double = 0, dragMoved: Double = 0, lastMx: Double = 0, lastMy: Double = 0, lastMt: Double = 0, dvx: Double = 0, dvy: Double = 0
    var hearts = List<Arr<Double>>()
    var sparks = List<Arr<Double>>()
    var notes = List<Arr<Double>>()   // 音符、驚嘆號等小圖（x 偏移, 年齡, 種類）
    var clickTimes = List<Double>()
    var flakes = List<Arr<Double>>()
    var dizzyOnLand = false, rolling = false
    var jokeT: Double = 0, tripT: Double = 0, capeT: Double = 0     // 人魚漢頓：笑話後追問、跌倒、披風
    var fetching = false
    var hoverCd: Double = 0, seekCd: Double = 20, lateCd: Double = 120, stuckRepeat: Double = 0
    var stuckLine: String? = nil

    // 公仔櫃動畫
    var flyT: Double = 0, flyDur: Double = 0, fx0: Double = 0, fy0: Double = 0, fx1: Double = 0, fy1: Double = 0, flyArc: Double = 0
    var shelfPs = 0                    // 進櫃子時縮到的大小
    var afterLand = ""                 // 落地後要做的事（wave／sniff／evil…）
    var ShelfFx: Double = 0            // 回櫃子後在格子裡的特效（Spidey 織網、小波轉圈…）0→1

    var bubblePri = 0                  // 通知的泡泡（>0）不會被閒聊蓋掉

    // 好感度
    var xp = 0; var lastPatDay = ""
    var patsToday = 0; var patsDate = ""
    var saveXpCd: Double = 0; var ballXp = 0

    var nearMiss = false
    var gotoSpeed: Double = 1
    var hideX: Double = 0
    var who = "Claude"

    //@@BODY Pet

    init(_ w: World, _ p: Pal, _ S: Int, _ seed: Int) {
        self.w = w; P = p; self.S = S
        k = Double(S) / 3.0
        SW = 12 * S; SH = 16 * S
        rnd = Random(seed)
        LoadBond()
    }
}

extension Pet {
    func EnsureForms() {
        if Form != nil { return }
        Form = PetForm(self)
        Menu = ContextMenuStrip()
        Menu.Opening = { [unowned self] in self.w.FillMenu(self, self.Menu) }
        w.HookMenu(Menu)
        Bub = BubbleForm(P.Accent)
    }

    func HideForms() {
        if Form != nil && W.Shown(Form) { Form.Hide() }
        if Bub != nil && W.Shown(Bub) { Bub.Hide() }
    }

    func CloseForms() {
        if Form != nil { Form.Close(); Bub.Close() }
    }

    var Night: Bool { return w.Night }
    func Grounded() -> Bool {
        switch state {
        case "walk", "idle", "sleep", "hug", "seek", "dizzy", "fetch", "dance", "kick", "wave", "pose", "bat", "catch", "header", "capetrip", "elvis", "chomp", "think", "hide", "nudge", "spin", "goto",
             "plop", "twirl", "hattoss", "juggle", "bagdig", "pik", "orig", "cu":
            return true
        default:
            return false
        }
    }
    func Free() -> Bool { return Out && !InScene && !dragging && Grounded() && state != "sleep" && state != "hug" && !(Bt > 0 && bubblePri > 0) && !MisBusy }
    func SetState(_ s: String, _ dur: Double) { state = s; t = dur }
    func Say(_ s: String?, _ sec: Double) { Say(s, sec, false) }
    func Say(_ s: String?, _ sec: Double, _ alert: Bool) { if string.IsNullOrEmpty(s) || muteChat { return }; bubble = s!; Bt = sec; bubbleAlert = alert; bubbleHint = nil; bubblePri = 0 }
    func Pick(_ a: [String]) -> String { return a[rnd.Next(a.count)] }
    func R(_ a: Double, _ b: Double) -> Double { return a + rnd.NextDouble() * (b - a) }
    static func Clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { return v < lo ? lo : (v > hi ? hi : v) }
    static func Ease(_ v: Double) -> Double { let v = Clamp(v, 0, 1); return v * v * (3 - 2 * v) }
    func Clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { return Pet.Clamp(v, lo, hi) }
    func Ease(_ v: Double) -> Double { return Pet.Ease(v) }
    var Cx: Double { return x + Double(SW) / 2.0 }
    func Is(_ id: String) -> Bool { return P.Id == id }

    // 台詞：夜晚優先用 key_d；{n}{who}{tool}{u} 代換
    func L(_ key: String, _ kv: String...) -> String {
        var a: [String] = []
        if Night && P.Lines.TryGetValue(key + "_d", &a) { }
        else if !P.Lines.TryGetValue(key, &a) { App.Log("missing line " + P.Id + "." + key); return "" }
        var s = Pick(a)
        var i = 0
        while i + 1 < kv.count { s = s.Replace("{" + kv[i] + "}", kv[i + 1]); i += 2 }
        return s
    }

    func Jump(_ jvx: Double, _ jvy: Double) { vx = jvx; vy = jvy; supH = IntPtr.Zero; SetState("air", 0) }
    func Hop() { Jump(Double(dir) * 60 * k, -260 * k) }
    func GoSleep() { z = 0; SetState("sleep", 1e9) }
    func WakeIfSleep() { sleepMode = false; if state == "sleep" { SetState("walk", 2) } }
    func AddHeart() { if hearts.Count < 8 { hearts.Add(Arr<Double>([R(-12, 12) * k, 0])) } }
    func Mark(_ kind: Int) { if notes.Count < 12 { notes.Add(Arr<Double>([R(-10, 10) * k, 0, Double(kind)])) } } // 0 音符 1 驚嘆號 2 問號 3 Zz 4 汗滴 5 泡泡

    func Burst(_ n: Int) {
        let cx = Cx, cy = y + Double(SH) * 0.35
        var i = 0
        while i < n {
            let a = rnd.NextDouble() * Math.PI * 2, sp = R(120, 260) * k
            let svy: Double = Math.Sin(a) * sp - 120 * k
            sparks.Add(Arr<Double>([cx, cy, Math.Cos(a) * sp, svy, 0]))
            i += 1
        }
    }

    // ---------- 好感度（每個角色各自一份）----------
    static let LV: [Int] = [0, 0, 15, 50, 120, 250, 500]
    static let UNLOCK: [String] = ["", "", "黃圍巾", "小毛帽", "愛心眼鏡", "金色胸章", "小皇冠"]
    func BondFile() -> String { return Path.Combine(World.DataDir, "bond-" + P.Id + ".txt") }
    func PatsFile() -> String { return Path.Combine(World.DataDir, "pats-" + P.Id + ".txt") }
    func LoadBond() {
        if let txt = try? File.ReadAllText(BondFile()) {
            let a = txt.Trim().Split(" ")
            if a.count > 0 { _ = int.TryParse(a[0], &xp) }
            if a.count > 1 { lastPatDay = a[1] }
        }
        if let txt = try? File.ReadAllText(PatsFile()) {
            let a = txt.Trim().Split(" ")
            if a.count == 2 && a[0] == DateTime.Now.ToString("yyyy-MM-dd") { patsDate = a[0]; _ = int.TryParse(a[1], &patsToday) }
        }
    }
    func SaveBond() { _ = try? Directory.CreateDirectory(World.DataDir); _ = try? File.WriteAllText(BondFile(), xp.ToString() + " " + lastPatDay) }
    func BumpPats() {
        let today = DateTime.Now.ToString("yyyy-MM-dd")
        if today != patsDate { patsDate = today; patsToday = 0 }
        patsToday += 1
        _ = try? Directory.CreateDirectory(World.DataDir); _ = try? File.WriteAllText(PatsFile(), patsDate + " " + patsToday.ToString())
    }
    func Level() -> Int { var lv = 1; var i = 2; while i < Pet.LV.count { if xp >= Pet.LV[i] { lv = i }; i += 1 }; return lv }
    func AddXp(_ n: Int) {
        let before = Level()
        xp += n; SaveBond()
        let now = Level()
        if now > before {
            Hug(L("levelup", "n", now.ToString(), "u", Pet.UNLOCK[now]), 4)
            AddHeart(); AddHeart(); AddHeart(); Burst(14)
        }
    }
    func DaysSincePat() -> Int {
        var d = DateTime.MinValue
        if !DateTime.TryParse(lastPatDay, &d) { return 0 }
        return CInt((DateTime.Now.Date - d.Date).TotalDays)
    }
    func ShowBond() {
        let lv = Level()
        let got = List<String>()
        var i = 2
        while i <= lv { got.Add(Pet.UNLOCK[i]); i += 1 }
        let xpS: String = xp.ToString()
        let next: String
        if lv < 6 { let nx: String = Pet.LV[lv + 1].ToString(); next = "（" + xpS + "/" + nx + "）" } else { next = "（" + xpS + "，滿級！）" }
        let tail = got.Count > 0 ? "　已解鎖：" + string.Join("、", got.ToArray()) : "　多摸摸我就會升級喔"
        Say(P.Name + " 好感度 Lv" + lv.ToString() + next + tail, 4.5)
        AddHeart()
    }

    // 被點了一下（通知優先，沒有通知就是摸摸）
    func Clicked() {
        if w.NoticeClicked(self) { return }
        Pat()
    }

    // ---------- 點他（沒拖動）----------
    func Pat() {
        let now = w.Now
        clickTimes.Add(now)
        clickTimes.RemoveAll { c in now - c > 1.3 }
        let combo = clickTimes.Count
        BumpPats()
        w.Count("pats")
        lastPatDay = DateTime.Now.ToString("yyyy-MM-dd")
        if patsToday <= 30 { AddXp(1) } else { SaveBond() }
        Burst(combo >= 3 ? 10 : 6)
        if w.quietOn {
            // 安靜中：小小回應就好
            AddHeart()
            Say(Pick(["♥", "（小聲）嗯～", "噓…♥"]), 1.0)
            return
        }
        if state == "sleep" {
            WakeIfSleep()
            Hug(L("wake"), 2.4)
            return
        }
        if combo >= 5 {
            if Grounded() { SetState("dizzy", 1.6) } else { dizzyOnLand = true }
            Say(L("dizzy"), 2)
            return
        }
        if combo >= 3 { PatCombo(); return }
        if patsToday % 10 == 0 {
            Hug(L("pat10", "n", patsToday.ToString()), 3)
            AddHeart(); AddHeart(); AddHeart()
            return
        }
        if P.Cu && CuPat() { return }
        let line = !Night && Level() >= 4 && rnd.NextDouble() < 0.4 ? L("pats_hi") : L("pats")
        if Is("hangyodon") && !Night && P.Lines["pats"].contains(line) { jokeT = 2.6 }   //@fan
        if Grounded() { Hug(line, 2.6) }
        else { Say(line, 2.2); AddHeart() }
    }

    // 連點三下：每個角色不一樣
    func PatCombo() {
        AddHeart()
        if P.Pik { PikCombo(); return }   //@fan
        if P.Orig { OrigCombo(); return }
        if P.Cu { CuCombo(); return }
        switch P.Id {
        // <fan>
        case "po":   // 咯咯笑＋原地轉一圈「再來一次！」
            Say(L("tickle"), 1.8)
            if Grounded() && state != "dizzy" { SetState("spin", 0.9); Jump(0, -340 * k); rolling = true }
        case "stitch": // 笑到捲成球滾來滾去
            Say(L("tickle"), 1.8)
            if Grounded() && state != "dizzy" { rolling = true; Jump(Double(dir) * R(120, 220) * k, -240 * k) }
        case "hangyodon": // 扮鬼臉（鬥雞眼＋嘟嘴）
            if Grounded() && state != "dizzy" { poseKind = "silly"; SetState("pose", 1.8) }
            Say(L("tickle"), 1.8)
        case "tinky":  // 跌坐在地上「哎喲！」
            Say(L("tickle"), 1.8)
            if Grounded() && state != "dizzy" { Plop(nil) }
        case "dipsy":  // 帽子不准摸：把帽子丟起來接住，或酷酷地跳一段
            Say(L("tickle"), 1.8)
            if Grounded() && state != "dizzy" { if rnd.NextDouble() < 0.5 { HatToss(true) } else { SetState("dance", 1.8) } }
        case "laalaa": // 啦啦啦～轉圈圈
            Say(L("tickle"), 1.8)
            if Grounded() && state != "dizzy" { SetState("twirl", 1.3) }
            // </fan>
        default:
            Say(L("tickle"), 1.6)
            if Grounded() && state != "dizzy" { Jump(Double(dir) * 40 * k, -330 * k) }
        }
    }

    func Hug(_ text: String, _ sec: Double) {
        if Grounded() { SetState("hug", sec) }
        Say(text, sec)
        AddHeart(); AddHeart()
    }

    // ---------- 滑鼠：停在身上 → 抱抱；停在附近 → 跑過去 ----------
    func Watch(_ dt: Double) {
        if stuckLine != nil { stuckRepeat -= dt; if stuckRepeat <= 0 { Say(stuckLine, 6, true); stuckLine = nil } }
        seekCd -= dt; hoverCd -= dt; lateCd -= dt; saveXpCd -= dt
        if !Grounded() || state == "hug" || sleepMode || state == "sleep" || InScene || Quiet || MisBusy { return }   // MisBusy：搗蛋中（59_mischief.swift）
        let c = Cursor.Position
        let cx = Cx, still = w.CursorStill
        let cX = Double(c.X), cY = Double(c.Y)
        let onMe = cX >= x && cX <= x + Double(SW) && cY >= y && cY <= y + Double(SH)
        if onMe && still > 1.2 && hoverCd <= 0 { hoverCd = 12; Hug(L("hover"), 2.4); return }
        let nearY: Bool = cY > y - 40 * k && cY < y + Double(SH) + 8
        let nearX: Bool = Math.Abs(cX - cx) < 380 * k && Math.Abs(cX - cx) > 8
        if !fetching && state != "seek" && seekCd <= 0 && still > 2.5 && !onMe && nearY && nearX {
            seekX = cX; seekCd = R(45, 100)
            if Is("stitch") && rnd.NextDouble() < 0.4 { SetState("seek", 8); afterLand = "nudge"; Say("嘻嘻嘻…", 1.2) }   //@fan
            else { SetState("seek", 8); Say(L("seek"), 1.2) }   //@fan
            // <public> do { SetState("seek", 8); Say(L("seek"), 1.2) }
        }
    }

    // ================= 每一格 =================
    func Tick(_ dt: Double) {
        if !Out { return }
        if !(dragging && DragUpdate(w.Now, dt)) { Watch(dt); Step(dt) }
        Render()
    }

    func Step(_ dt: Double) {
        anim += dt; t -= dt
        if Bt > 0 { Bt -= dt }
        if sense > 0 { sense -= dt }
        if jokeT > 0 { jokeT -= dt; if jokeT <= 0 { Say("好笑嗎？好笑嗎？", 1.8); if Grounded() { Jump(0, -180 * k) } } }
        if tripT > 0 { tripT -= dt }
        var i = hearts.Count - 1
        while i >= 0 { hearts[i][1] += dt; if hearts[i][1] > 1.6 { hearts.RemoveAt(i) }; i -= 1 }
        i = notes.Count - 1
        while i >= 0 { notes[i][1] += dt; if notes[i][1] > 1.8 { notes.RemoveAt(i) }; i -= 1 }
        i = sparks.Count - 1
        while i >= 0 {
            let sp = sparks[i]
            sp[3] += 420 * k * dt; sp[0] += sp[2] * dt; sp[1] += sp[3] * dt; sp[4] += dt
            if sp[4] > 0.75 { sparks.RemoveAt(i) }
            i -= 1
        }
        if w.SeasonNow == "xmas" && rnd.NextDouble() < dt * 3 {
            let fxx: Double = Cx + R(-70, 70) * k
            let fyy: Double = y - R(30, 90) * k
            flakes.Add(Arr<Double>([fxx, fyy, R(-12, 12) * k, 0]))
        }
        i = flakes.Count - 1
        while i >= 0 {
            let f = flakes[i]
            f[1] += 38 * k * dt
            let drift: Double = f[2] + Math.Sin(f[3] * 3) * 10 * k
            f[0] += drift * dt; f[3] += dt
            if f[3] > 2.2 { flakes.RemoveAt(i) }
            i -= 1
        }
        if MisStep(dt) { return }   // 搗蛋中（59_mischief.swift）
        FollowFast()
        let wa = w.WA(Cx, y + Double(SH) / 2.0)
        if StepSpecial(dt, wa) { return }   // 角色專屬狀態
        switch state {
        case "walk":
            if sleepMode { GoSleep(); break }
            if MoveOnGround(dt, P.Speed * k) { break }
            if t < 0 { muteChat = !w.Feat("chatter"); Decide(wa); muteChat = false }   // 小屋關掉「閒聊泡泡」：自己閒晃時不講話
        case "seek": Seek(dt)
        case "idle":
            if !InScene { let cp = Cursor.Position; if Math.Abs(Double(cp.X) - Cx) > 20 { dir = Double(cp.X) > Cx ? 1 : -1 } }
            if sleepMode { GoSleep() }
            else if t < 0 && !InScene { SetState("walk", R(3, 6)) }
        case "fetch": Fetch(dt)
        case "dance", "kick", "pose", "wave", "think":
            if t < 0 && !InScene { SetState("idle", R(1, 2)); DoAfter() }
        case "dizzy":
            if Math.Floor(anim * 8) != Math.Floor((anim - dt) * 8) { dir = -dir }
            if t < 0 { SetState("idle", 1); Say(L("dizzy_ok"), 1.4) }
        case "hug":
            if rnd.NextDouble() < dt * 2.5 { AddHeart() }
            if t < 0 && !InScene { SetState("walk", R(2, 4)) }
        case "sleep": z += dt; if t < 0 { SetState("walk", 3) }
        case "air": Air(dt)
        case "glass": Glass(dt)
        case "stowfly": StowFly(dt)
        case "enter": Enter(dt)
        case "exit": Exit(dt)
        case "hide": HideBehind(dt)
        case "goto": GoTo(dt)
        case "fling": Fling(dt)
        default: break
        }
    }

    func DoAfter() {
        let a = afterLand; afterLand = ""
        if a == "trip" { tripT = 1.1; SetState("think", 1.1); Say(Pick(["哎呀…（跌倒）", "嗚…英雄也會跌倒的", "我、我沒事！"]), 1.8) }
    }

    // 回傳 true＝離開地面或換狀態了
    @discardableResult
    func MoveOnGround(_ dt: Double, _ speed: Double) -> Bool {
        let nx: Double = x + Double(dir) * speed * dt
        let ncx: Double = nx + Double(SW) / 2.0, midY: Double = y + Double(SH) / 2.0
        if supH != IntPtr.Zero {
            if ncx < Double(supL) || ncx > Double(supR) {
                if state == "walk" { let e = EdgeOfWindow(ncx > Double(supR)); if e == 2 { return true }; if e == 1 { return false } }
                x = nx
                Jump(Double(dir) * speed * 1.4, -140 * k)
                return true
            }
            x = nx
            return false
        }
        let lead: Double = dir > 0 ? nx + Double(SW) - 1 : nx
        if !w.Inside(lead, midY) {
            if state == "walk" && EdgeOfScreen() { return true }
            dir = -dir
            return false
        }
        let floorY = Double(w.WA(ncx, midY).Bottom - SH)
        if floorY > y + 2 { x = nx; Jump(Double(dir) * speed, 0); return true }
        if floorY < y - 2 { dir = -dir; return false }
        x = nx; y = floorY
        return false
    }

    func Seek(_ dt: Double) {
        let c = Cursor.Position
        let cX = Double(c.X), cY = Double(c.Y)
        if Math.Abs(cX - seekX) > 4 {
            if cY > y - 60 * k && cY < y + Double(SH) + 20 { seekX = cX }
            else { SetState("walk", 2); afterLand = ""; Say(L("seek_lost"), 1.4); return }
        }
        if Math.Abs(seekX - Cx) < 6 {
            if afterLand == "nudge" { afterLand = ""; SetState("nudge", 1.6); Say(Pick(["ih-ih-ih!（推推）", "嘻嘻，推一下～", "這個是史迪仔的！"]), 1.8); return }   //@fan
            Hug(L("seek_got"), 3); return
        }
        dir = seekX > Cx ? 1 : -1
        let spd: Double = Is("hangyodon") || Is("tinky") ? 60 : 95   //@fan
        // <public> let spd: Double = 95
        if MoveOnGround(dt, spd * k) { return }
        let ncx = Cx
        if (dir > 0 && ncx > seekX) || (dir < 0 && ncx < seekX) { x = seekX - Double(SW) / 2.0 }
        if t < 0 { SetState("walk", 2) }
    }

    // 拋物線跳到某一點（腳落在 footY）
    func BallisticTo(_ tx: Double, _ footY: Double) {
        let cx = Cx, foot: Double = y + Double(SH), g: Double = 900 * k
        let top = w.WA(cx, y)
        var apex: Double = Math.Max(Math.Min(foot, footY) - R(60, 130) * k, Double(top.Top + SH + 2))
        if apex >= foot { apex = foot - 10 }
        if apex >= footY { apex = footY - 10 }
        let vy0: Double = -Math.Sqrt(2 * g * (foot - apex))
        let tt: Double = -vy0 / g + Math.Sqrt(2 * (footY - apex) / g)
        let vx0: Double = (tx - cx) / tt
        dir = vx0 >= 0 ? 1 : -1
        Jump(vx0, vy0)
    }

    // 挑一個附近的平台（視窗頂端或螢幕底）：回傳 {x, 頂端y, 是哪個視窗}
    func PickPlatform(_ minDx: Double, _ maxDx: Double) -> [Double]? {
        let cx = Cx, foot: Double = y + Double(SH)
        let opts = List<[Double]>()
        if w.Feat("windows") {                    // 小屋關掉「跳上視窗」：只在螢幕底走
        for p in w.Plats {
            if p.H == supH && Math.Abs(Double(p.Top) - foot) < 2 { continue }
            let span: Double = Double(Math.Max(0, p.Right - p.Left - SW))
            let tx: Double = Double(p.Left) + Double(SW) / 2.0 + rnd.NextDouble() * span
            let dx: Double = tx - cx, dy: Double = Double(p.Top) - foot
            if Math.Abs(dx) < minDx || Math.Abs(dx) > maxDx || dy < -600 * k { continue }
            opts.Add([tx, Double(p.Top)])
        }
        }
        if supH != IntPtr.Zero {
            let wa = w.WA(cx, y)
            opts.Add([Clamp(cx + R(-400, 400) * k, Double(wa.Left + SW), Double(wa.Right - SW)), Double(wa.Bottom)])
        }
        if opts.Count == 0 { return nil }
        return opts[rnd.Next(opts.Count)]
    }

    @discardableResult
    func JumpToPlatform() -> Bool {
        if !Grounded() { return false }
        guard let o = PickPlatform(40 * k, 900 * k) else { return false }
        BallisticTo(o[0], o[1])
        if Is("po") { Say(L("jump"), 0.9) }   //@fan
        else if rnd.NextDouble() < 0.3 { Say(L("jump"), 0.8) }   //@fan
        // <public> if rnd.NextDouble() < 0.3 { Say(L("jump"), 0.8) }
        return true
    }

    func Air(_ dt: Double) {
        let g: Double = 900 * k, prevFoot: Double = y + Double(SH)
        vy += g * dt; x += vx * dt; y += vy * dt
        var cx = Cx
        let midY: Double = y + Double(SH) / 2.0
        let wa = w.WA(cx, midY)
        if !w.Inside(x, midY) && x < Double(wa.Left) { x = Double(wa.Left); vx = -vx * 0.5 }
        if !w.Inside(x + Double(SW) - 1, midY) && x + Double(SW) > Double(wa.Right) { x = Double(wa.Right - SW); vx = -vx * 0.5 }
        cx = Cx
        if y < Double(wa.Top) { y = Double(wa.Top); if vy < 0 { vy = 0 } }
        if Math.Abs(vx) > 1 { dir = vx > 0 ? 1 : -1 }
        if vy > 1100 * k && (Is("po") || Is("stitch") || Is("laalaa")) { rolling = true } // 摔很快 → 滾   //@fan
        if vy <= 0 { return }
        var best = Double(wa.Bottom); var bp: Plat? = nil
        for p in w.Plats {
            let pTop = Double(p.Top)
            if cx >= Double(p.Left) && cx <= Double(p.Right) && prevFoot <= pTop + 1 && y + Double(SH) >= pTop && pTop < best { best = pTop; bp = p }
        }
        if y + Double(SH) >= best {
            y = best - Double(SH)
            let landVx = vx
            lastLandVy = vy
            vx = 0; vy = 0
            if let bp = bp { SetSupport(bp) } else { supH = IntPtr.Zero }
            let wasRolling = rolling; rolling = false
            if nearMiss { nearMiss = false; Say(MissLine(), 1.8) }
            if Landed(wasRolling, landVx) { return }
            if sleepMode { GoSleep() }
            else if dizzyOnLand { dizzyOnLand = false; SetState("dizzy", 1.6) }
            else if fetching && w.BallOn { SetState("fetch", 15) }
            else if afterLand != "" { LandAction() }
            else if InScene && (w.TubbyLineup || w.PikLineup || w.OrigLineup) { SetState("idle", 30) }   // 天線寶寶串場：跳一下落地就站好，不要走掉   //@fan
            // <public> else if InScene && w.OrigLineup { SetState("idle", 30) }
            else { SetState("walk", R(2, 5)) }
        }
    }

    func SetSupport(_ p: Plat) { supH = p.H; supL = p.Left; supR = p.Right; supWinL = p.WinLeft }

    // 站著的那個視窗被拖動 → 跟著走
    func FollowFast() {
        if supH == IntPtr.Zero || !Grounded() { return }
        if w.CuFake(supH) { return }   // 測試用的假視窗（53_custom.swift）
        var r = W.RECT()
        if !W.IsWindowVisible(supH) || W.IsIconic(supH) || !W.Rect(supH, &r) { Jump(0, 0); Say(Is("hangyodon") ? "哇！地板游走了！" : "哇！地板不見了", 1.2); return }   //@fan
        // <public> if !W.IsWindowVisible(supH) || W.IsIconic(supH) || !W.Rect(supH, &r) { Jump(0, 0); Say("哇！地板不見了", 1.2); return }
        let dl = r.L - supWinL
        if dl != 0 { x += Double(dl); supL += dl; supR += dl; supWinL = r.L }
        y = Double(r.T - SH)
    }

    // World 掃描完視窗後：站的那段被蓋住 → 掉下來
    func CheckSupport() {
        if supH == IntPtr.Zero || !Grounded() { return }
        var best: Plat? = nil
        for p in w.Plats { if p.H == supH && Cx >= Double(p.Left - 2) && Cx <= Double(p.Right + 2) { best = p; break } }
        if let best = best { supL = best.Left; supR = best.Right } else { Jump(0, 0) }
    }

    // ---------- 第四面牆 ----------
    // 放大敲玻璃很搶眼，所以有全域冷卻（World.ZoomAllowed）；不能放大時改成原尺寸的小動作
    func Knock(_ text: String, _ kind: String) {
        if Out && Grounded() && state != "glass" && w.ZoomAllowed(kind) { StartGlass(text); return }
        if kind == "ambient" { Tap(text); return }
        NoZoom(text, kind == "high" || kind == "meeting" ? 6 : 3.5)
    }

    // 原尺寸：在玻璃上輕輕敲一下（小漣漪）
    func Tap(_ text: String) {
        if Out && Grounded() { poseKind = "tap"; SetState("pose", 1.5); gt = 0 }
        Say(text, 2.6)
    }

    // 不放大：朝滑鼠跳一下＋泡泡
    func NoZoom(_ text: String, _ sec: Double) {
        if Out && Grounded() {
            let dx: Double = Double(Cursor.Position.X) - Cx
            dir = dx >= 0 ? 1 : -1
            if Math.Abs(dx) > 40 * k && Math.Abs(dx) < 500 * k && supH == IntPtr.Zero { Jump(Clamp(dx * 0.8, -320 * k, 320 * k), -300 * k) }
            else { Jump(0, -280 * k) }
        }
        Say(text, sec)
    }

    // ---------- 第四面牆：放大敲螢幕 ----------
    func StartGlass(_ text: String) {
        if !Grounded() || !Out { Say(text, 2.5); return }
        let wa = w.WA(Cx, y + Double(SH) / 2.0)
        if y + Double(SH) - 3.2 * Double(SH) < Double(wa.Top) { Say(text, 2.5); return }
        afterGlass = text; gt = 0; sc = 1; knock = 0
        SetState("glass", 99)
    }

    func Glass(_ dt: Double) {
        let prev = gt
        gt += dt
        let cp = Cursor.Position
        dir = Double(cp.X) >= Cx ? 1 : -1
        if gt < 0.5 { sc = 1 + 2 * Ease(gt / 0.5) }
        else if gt < 3.4 {
            sc = 3
            if prev < 0.55 && gt >= 0.55 { if bubble == afterGlass && Bt > 0 { Bt = Math.Max(Bt, 2.8) } else { Say(afterGlass, 2.8) } }
            if Math.Floor(gt * 2.2) != Math.Floor(prev * 2.2) { knock = 0.12 }
        }
        else if gt < 3.9 { sc = 3 - 2 * Ease((gt - 3.4) / 0.5) }
        else { sc = 1; SetState("idle", 1.2) }
        if knock > 0 { knock -= dt }
    }

    // ---------- 拖曳 ----------
    func MouseDown(_ e: MouseEventArgs) {
        // 有通知在等你點：一按下去就算（就算他在走路、在敲玻璃）
        if e.Button == MouseButtons.Left && w.NoticeClicked(self) { dragging = false; return }
        if e.Button != MouseButtons.Left || state == "glass" || state == "peek" || state == "stowfly" || state == "enter" || state == "exit" || state == "fling" { return }
        let p = Cursor.Position
        let pX = Double(p.X), pY = Double(p.Y)
        let left: Double = x - 6 - Double(9 * S), right: Double = x + Double(SW) + 6 + Double(9 * S)
        let top: Double = y - 6 - Double((P.TopRows + 3) * S), bottom: Double = y + Double(SH) + 6
        if pX < left || pX > right || pY < top || pY > bottom { return }
        dragging = true; dragSaid = false; dragStart = p; dragMoved = 0
        grabDx = pX - x; grabDy = pY - y
        lastMx = pX; lastMy = pY; lastMt = w.Now; dvx = 0; dvy = 0
    }

    func MouseUp(_ e: MouseEventArgs) {
        if e.Button == MouseButtons.Left && dragging { EndDrag() }
        else if e.Button == MouseButtons.Right && Menu != nil { w.FillMenu(self, Menu); w.ShowMenu(Menu, P.Name, false) }
    }

    var Dragging: Bool { return dragging && state == "drag" }

    func DragUpdate(_ now: Double, _ dt: Double) -> Bool {
        if (Control.MouseButtons & MouseButtons.Left) == MouseButtons.None { EndDrag(); return false }
        let p = Cursor.Position
        let pX = Double(p.X), pY = Double(p.Y)
        let mdt = now - lastMt
        if mdt > 0.001 {
            let ivx: Double = (pX - lastMx) / mdt, ivy: Double = (pY - lastMy) / mdt
            dvx = dvx * 0.5 + 0.5 * ivx; dvy = dvy * 0.5 + 0.5 * ivy
        }
        lastMx = pX; lastMy = pY; lastMt = now
        dragMoved = Math.Max(dragMoved, Double(Math.Abs(p.X - dragStart.X) + Math.Abs(p.Y - dragStart.Y)))
        if dragMoved <= 6 { return false }
        if state != "drag" { state = "drag"; supH = IntPtr.Zero; sleepMode = false; sc = 1; if InScene { w.AbortScene() } }
        x = pX - grabDx; y = pY - grabDy
        anim += dt
        if Bt > 0 { Bt -= dt }
        if !dragSaid { dragSaid = true; Say(L("drag"), 1.5) }
        return true
    }

    func EndDrag() {
        dragging = false
        if state != "drag" { Clicked(); return }
        let lim: Double = 2200 * k
        Throw(Clamp(dvx, -lim, lim), Clamp(dvy, -lim, lim))
    }

    // ================= 丟回櫃子（像投籃）=================

    // 測試用：在 (px,py) 放手、給一個速度
    func SimThrow(_ px: Double, _ py: Double, _ tvx: Double, _ tvy: Double) {
        if !Out { return }
        dragging = false
        x = px - Double(SW) / 2.0; y = py - Double(SH) / 2.0
        Throw(tvx, tvy)
    }

    func Throw(_ tvx: Double, _ tvy: Double) {
        var tvx = tvx, tvy = tvy
        if P.Pik { PikThrown(&tvx, &tvy) }   //@fan
        let zone = w.ShelfZone(SW, SH)
        let cx = Cx, cy: Double = y + Double(SH) / 2.0, speed: Double = Math.Abs(tvx) + Math.Abs(tvy)
        nearMiss = false
        // 在櫃子附近放手：直接收進去（有甩的話算投進）
        if zone.Contains(CInt(cx), CInt(cy)) {
            if speed > 700 * k { StartFling(tvx * 0.5, tvy * 0.5) } else { StowToShelf(true) }
            return
        }
        // 模擬飛行路線：有穿過櫃子（加大範圍）就被吸進去
        var px = cx, py = cy, pvx = tvx, pvy = tvy
        let g: Double = 900 * k, step: Double = 1 / 60.0
        var best = Double.greatestFiniteMagnitude
        var hit = false
        let zL = Double(zone.Left), zR = Double(zone.Right), zT = Double(zone.Top), zB = Double(zone.Bottom)
        var i = 0
        while i < 240 {
            pvy += g * step; px += pvx * step; py += pvy * step
            if zone.Contains(CInt(px), CInt(py)) { hit = true; break }
            let dx: Double = Math.Max(0, Math.Max(zL - px, px - zR)), dy: Double = Math.Max(0, Math.Max(zT - py, py - zB))
            best = Math.Min(best, Math.Sqrt(dx * dx + dy * dy))
            if !w.Inside(px, Math.Min(py, cy)) && !w.Inside(px, py) { break }   // 飛出所有螢幕
            i += 1
        }
        if hit && speed > 300 * k { StartFling(tvx, tvy); return }
        nearMiss = speed > 600 * k && best < Double(SW) * 2.5
        Jump(tvx, tvy)
        if speed > 900 * k {
            Say(L("throw"), 0.9)
            if Is("po") || Is("stitch") || Is("laalaa") || P.Cu { rolling = true }   //@fan
            // <public> if P.Cu { rolling = true }
        }
    }

    // 照丟出去的速度飛，越飛越被自己的格子吸過去
    func StartFling(_ tvx: Double, _ tvy: Double) {
        var tfx: Double = 0, tfy: Double = 0; var ps = 0
        w.ShelfFoot(self, &tfx, &tfy, &ps)
        shelfPs = ps
        fx1 = tfx - Double(SW) / 2.0; fy1 = tfy - Double(SH)
        vx = tvx; vy = tvy; flyT = 0
        supH = IntPtr.Zero; sc = 1; fetching = false; InScene = false
        rolling = Is("po") || Is("stitch") || Is("laalaa") || P.Cu   //@fan
        // <public> rolling = P.Cu
        SetState("fling", 99)
    }

    func Fling(_ dt: Double) {
        flyT += dt
        let f: Double = Math.Min(1, flyT / 0.7)
        let ax2: Double = (fx1 - x) * 26 * f * f - vx * 9.5 * f
        let ay2a: Double = (fy1 - y) * 26 * f * f - vy * 9.5 * f
        let ay2: Double = ay2a + 900 * k * (1 - f)
        vx += ax2 * dt; vy += ay2 * dt; x += vx * dt; y += vy * dt
        if Math.Abs(vx) > 5 { dir = vx > 0 ? 1 : -1 }
        let ddx: Double = fx1 - x, ddy: Double = fy1 - y
        let d: Double = Math.Sqrt(ddx * ddx + ddy * ddy)
        if (d < 10 * k && flyT > 0.25) || flyT > 2.2 {
            x = fx1; y = fy1; rolling = false
            GoalCheer()
            gt = 0; SetState("enter", 99)
        }
    }

    func GoalCheer() {
        let line: String
        switch P.Id {
        // <fan>
        case "po": line = "進球！🏀 再來一次！"
        case "stitch": line = "嘻嘻嘻～進球！🏀"
        case "hangyodon": line = "英雄……降落成功 🏀"
        case "tinky": line = "進球！🏀 丁丁回家家～"
        case "dipsy": line = "進球。🏀 帽子還在，酷。"
        case "laalaa": line = "進球！🏀 啦啦啦～"
        case "pkred", "pkyellow", "pkblue": line = PikLine("goal")
        // </fan>
        case "boba", "coffee", "onigiri", "sticky": line = OrigLine("goal")
        default: line = P.Cu ? L("x_goal") : "進球！🏀 Thwip!"   //@fan
        // <public> default: line = P.Cu ? L("x_goal") : "進球！🏀"
        }
        Say(line, 2.4)
        Burst(14)
        w.GoalCheer(self)
    }

    // 別人投進了：小小歡呼
    func Cheer() {
        if !Out || InScene { return }
        let line: String
        switch P.Id {
        // <fan>
        case "po": line = "Eh-oh! 進了！"
        case "stitch": line = "ih-ih! 嘻嘻嘻"
        case "hangyodon": line = "好、好厲害！"
        case "tinky": line = "好棒棒！大抱抱！"
        case "dipsy": line = "酷！"
        case "laalaa": line = "啦啦～進了！"
        case "pkred", "pkyellow", "pkblue": line = PikLine("cheer")
        // </fan>
        case "boba", "coffee", "onigiri", "sticky": line = OrigLine("cheer")
        default: line = P.Cu ? L("x_cheer") : "好球！"
        }
        Say(line, 1.4)
        Mark(0)
        if Grounded() && state != "sleep" { Jump(0, -220 * k) }
    }

    func MissLine() -> String {
        switch P.Id {
        // <fan>
        case "po": return "差一點點！再來一次！"
        case "stitch": return "ih! 沒進！嘻嘻"
        case "hangyodon": return "偏、偏了…英雄也會失手"
        case "tinky": return "哎喲，差一點點…"
        case "dipsy": return "沒進…但帽子很帥"
        case "laalaa": return "差一點！再來一次！"
        case "pkred", "pkyellow", "pkblue": return PikLine("miss")
        // </fan>
        case "boba", "coffee", "onigiri", "sticky": return OrigLine("miss")
        default: break
        }
        return P.Cu ? L("x_miss") : "差一點！再一次？"
    }

    // ================= 公仔櫃：回櫃子／出來 =================
    // 回櫃子：飛到自己那格（每個角色飛法不同），到了縮小、櫃子接手畫
    func StowToShelf(_ say: Bool) {
        if !Out { return }
        var tfx: Double = 0, tfy: Double = 0; var ps = 0
        w.ShelfFoot(self, &tfx, &tfy, &ps)
        shelfPs = ps
        if say { Say(L("shelf_in"), 2.2) }
        fetching = false; sc = 1; rolling = false; InScene = false
        fx0 = x; fy0 = y; fx1 = tfx - Double(SW) / 2.0; fy1 = tfy - Double(SH)
        let ddx: Double = fx1 - fx0, ddy: Double = fy1 - fy0
        let d: Double = Math.Sqrt(ddx * ddx + ddy * ddy)
        let flySpeed: Double = Is("hangyodon") ? 560 * k : 900 * k   //@fan
        // <public> let flySpeed: Double = 900 * k
        flyDur = Clamp(d / flySpeed, 0.35, 1.6)
        flyArc = Math.Min(160 * k, 40 * k + d * 0.25)
        flyT = 0; supH = IntPtr.Zero
        SetState("stowfly", 99)
    }

    func StowFly(_ dt: Double) {
        flyT += dt
        let f: Double = Math.Min(1, flyT / flyDur), e: Double = Is("hangyodon") ? Ease(f) : f   //@fan
        // <public> let f: Double = Math.Min(1, flyT / flyDur), e: Double = f
        if Is("hangyodon") && rnd.NextDouble() < 0.25 { Mark(5) }   //@fan
        x = fx0 + (fx1 - fx0) * e
        let arc: Double = Math.Sin(Math.PI * f) * flyArc
        y = fy0 + (fy1 - fy0) * e - arc
        dir = fx1 >= fx0 ? 1 : -1
        if f >= 1 { x = fx1; y = fy1; gt = 0; SetState("enter", 99) }
    }

    func Enter(_ dt: Double) {
        gt += dt
        let target: Double = Double(shelfPs) / Double(S)
        sc = 1 + (target - 1) * Ease(gt / 0.35)
        if gt >= 0.35 { sc = 1; Out = false; HideForms(); state = "shelf"; ShelfFx = 0; w.PetStowed(self) }
    }

    // 從格子裡出來：先在格子裡變大，再跳到桌面
    func ComeOut(_ say: Bool) {
        EnsureForms()
        var tfx: Double = 0, tfy: Double = 0; var ps = 0
        w.ShelfFoot(self, &tfx, &tfy, &ps)
        shelfPs = ps
        x = tfx - Double(SW) / 2.0; y = tfy - Double(SH)
        sc = Double(ps) / Double(S); gt = 0
        Out = true; InScene = false; dragging = false; sleepMode = false
        SetState("exit", 99)
        if say { Say(L("shelf_out"), 1.8) }
    }

    func Exit(_ dt: Double) {
        gt += dt
        let from: Double = Double(shelfPs) / Double(S)
        sc = from + (1 - from) * Ease(gt / 0.3)
        if gt < 0.3 { return }
        sc = 1
        let wa = w.WA(Cx, y + Double(SH))
        let tx: Double = Clamp(Cx - R(140, 360) * k, Double(wa.Left + SW), Double(wa.Right - SW))
        if Is("hangyodon") { StartSwim(tx, Double(wa.Bottom), false); return }   //@fan
        BallisticTo(tx, Double(wa.Bottom))
        if Is("stitch") { rolling = true }   //@fan
        if P.Orig { OrigExit() }
        if P.Pik { afterLand = "pksprout" }                                     // 皮克敏：落地先種在土裡，再「噗！」拔出來   //@fan
        // <fan>
        if Is("tinky") && rnd.NextDouble() < 0.3 { afterLand = "plop" }          // 丁丁跳出來常常跌坐
        else if Is("laalaa") && rnd.NextDouble() < 0.4 { afterLand = "twirl" }   // 拉拉落地轉一圈
        else if Is("dipsy") && rnd.NextDouble() < 0.4 { afterLand = "hattip" }   // 迪西落地扶帽子
        // </fan>
    }

    // ---------- 走到指定位置（串場、大合照用）----------
    func GoTo(_ dt: Double) {
        if Math.Abs(seekX - Cx) < 4 { x = seekX - Double(SW) / 2.0; SetState("idle", InScene ? 30 : 1); return }
        dir = seekX > Cx ? 1 : -1
        if MoveOnGround(dt, Math.Max(P.Speed, 60) * k * gotoSpeed) { return }
        if (dir > 0 && Cx > seekX) || (dir < 0 && Cx < seekX) { x = seekX - Double(SW) / 2.0 }
        if t < 0 { SetState("idle", InScene ? 30 : 1) }
    }

    // ---------- 躲到別人後面（小波怕錯誤）----------
    func HideBehindPet(_ other: Pet) {
        if !Grounded() { return }
        let side: Double = other.Cx > Cx ? 1 : -1
        hideX = other.Cx + side * Double(SW) * 0.45
        SetState("hide", 4)
    }
    func HideBehind(_ dt: Double) {
        if Math.Abs(hideX - Cx) > 4 { dir = hideX > Cx ? 1 : -1; if MoveOnGround(dt, 110 * k) { return } }
        if t < 0 { SetState("idle", 1) }
    }

    // ================= 球 =================
    func BallStarted() {
        if !Out || InScene { return }
        fetching = true
        WakeIfSleep()
        if Grounded() && state != "hug" { SetState("fetch", 15) }
    }

    func Fetch(_ dt: Double) {
        if !w.BallOn || !fetching { fetching = false; SetState("idle", 1); return }
        if w.Holder != nil { SetState("idle", 0.5); return }
        let r: Double = w.BallR(), dxb: Double = w.Bx - Cx, foot: Double = y + Double(SH)
        let resting = w.Bvy == 0 && Math.Abs(w.Bvx) < 30 * k
        let sameLevel = Math.Abs(w.By + r - foot) < 40 * k
        if resting && !sameLevel { BallisticTo(w.Bx, w.By + r); return }
        let base: Double = P.Tubby ? (Is("tinky") ? 90 : (Is("laalaa") ? 150 : 125)) : (Is("hangyodon") ? 70 : (Is("stitch") ? 170 : (Is("po") ? 150 : 125)))   //@fan
        // <public> let base: Double = 125
        let sp: Double = base * k
        if Math.Abs(dxb) > 6 { dir = dxb > 0 ? 1 : -1; if MoveOnGround(dt, sp) { return } }
        else if w.By < y && w.Bvy > 0 && w.By > y - 160 * k { Jump(0, -380 * k); return }
        if t < 0 { fetching = false; SetState("idle", 1); Say(L("ball_far"), 1.6) }
    }

    // 球碰到他（World 判斷）：回傳 true＝處理掉了
    @discardableResult
    func TouchBall() -> Bool {
        if !fetching || state == "drag" || !Out { return false }
        fetching = false
        if ballXp < 20 { ballXp += 2; AddXp(2) }
        Burst(6)
        if P.Pik { PikBall(); return true }   //@fan
        if P.Orig { OrigBall(); return true }
        if P.Cu { CuBall(); return true }
        // <fan>
        switch P.Id {
        case "po": PoBall(); return true
        case "stitch": StitchBall(); return true
        case "hangyodon": HangyodonBall(); return true
        case "tinky": TinkyBall(); return true
        case "dipsy": DipsyBall(); return true
        case "laalaa": LaaLaaBall(); return true
        default: break
        }
        // Spidey：踢回滑鼠的方向（多人時用絲接住）
        if w.OutCount() > 1 && rnd.NextDouble() < 0.6 { WebCatch(); return true }
        // </fan>
        Say(L("ball_catch"), 1.8)
        KickBallToCursor(1.0)
        if Grounded() { SetState("kick", 0.5) }
        return true
    }

    func KickBallToCursor(_ power: Double) {
        let c = Cursor.Position
        let kvx: Double = (Double(c.X) - w.Bx) * 1.1 * power
        w.Bvx = Clamp(kvx, -900 * k, 900 * k)
        w.Bvy = -R(450, 650) * k * power
        w.By = Math.Min(w.By, y - 4 * k)
        w.BallIdle = 0; w.CatchCd = 1.0
    }

    // ================= 外部事件 =================
    func OnSave(_ lead: Bool) {
        if saveXpCd <= 0 { saveXpCd = 120; AddXp(1) }
        WakeIfSleep()
        if lead { Say(L("save"), 2) }
        if Grounded() && (lead || rnd.NextDouble() < 0.3) { Jump(0, -300 * k) }
    }

    func OnErrors(_ n: Int, _ prev: Int, _ hideFrom: Pet?) {
        WakeIfSleep()
        if n > prev {
            sense = Is("spidey") ? 2.8 : 0   //@fan
            // <public> sense = 0
            let line = L("errors", "n", n.ToString())
            // <fan>
            if Is("hangyodon") && Grounded() { capeT = 0; SetState("capetrip", 2.6) }
            else if Is("stitch") && Grounded() { Jump(0, -360 * k); Mark(1) }
            else if Is("po") && hideFrom != nil && Grounded() { HideBehindPet(hideFrom!) }
            else if Is("tinky") && Grounded() { Plop(nil) }
            else if Is("dipsy") && Grounded() { poseKind = "hatdown"; SetState("pose", 2.6) }
            else if Is("laalaa") && hideFrom != nil && Grounded() { HideBehindPet(hideFrom!) }
            else if P.Pik && Grounded() { PikReact("errors") }
            // </fan>
            else if P.Orig && Grounded() { OrigReact("errors") }   //@fan
            // <public> if P.Orig && Grounded() { OrigReact("errors") }
            else if P.Cu && Grounded() { CuReact("errors") }
            else if state == "walk" { SetState("idle", 3) }
            Say(line, 3, true)
        }
        else if n == 0 { AddXp(2); Hug(L("errors_ok"), 2.6) }
    }

    func OnTyping() {
        if !Grounded() || state == "hug" || state == "sleep" || InScene || Quiet { return }
        // <fan>
        if Is("stitch") { SetState("elvis", 4) }
        else if Is("laalaa") { SetState("dance", 4); Mark(0); Mark(0) }
        // </fan>
        else { SetState("dance", 4) }   //@fan
        // <public> SetState("dance", 4)
        Say(L("typing"), 2.5)
    }

    func React() {
        if !Out || InScene { return }
        WakeIfSleep()
        if Grounded() { Jump(0, -240 * k) }
        Mark(1)
        Say(L("react"), 1.4)
    }

    // 卡住提醒（文字已組好）
    func Alert(_ text: String) {
        WakeIfSleep()
        if Is("spidey") { sense = 2.8 }   //@fan
        Knock(text, "high")
        Say(text, 5, true)
        bubblePri = 2
        stuckLine = text; stuckRepeat = 3.5
    }
    func ClearAlert() { stuckLine = nil }

    func SystemIdle(_ idle: Bool) {
        if idle { sleepMode = true; if Out && Grounded() && state != "hug" && state != "glass" { GoSleep() } }
        else {
            let was = state == "sleep"
            WakeIfSleep()
            if was && Out && !(P.Cu && CuWelcome()) { Knock(L("welcome"), "ambient") }
        }
    }

    func Rest(_ restMin: Double) {
        WakeIfSleep()
        Hug(L("rest", "n", restMin.ToString()), 8)
    }

    func NightChanged(_ d: Bool) {
        if !Out { return }
        if d { if Is("spidey") { sense = 2.5 }; NoZoom(L("night_on"), 3.5) }   //@fan
        // <public> if d { NoZoom(L("night_on"), 3.5) }
        else { Say(L("night_off"), 3) }
    }

    func Greeting() -> String {
        let sl = SeasonLine()
        if sl != nil && w.SeasonNow != "friday" { return sl! }
        if Night { return L("g_d") }
        let h = DateTime.Now.Hour
        if h >= 23 || h < 5 { return L("g_late") }
        if h < 11 { return L("g_morning") }
        if h < 14 { return L("g_noon") }
        if h >= 18 { return L("g_evening") }
        return L("g_day")
    }

    func SeasonLine() -> String? {
        if w.SeasonNow == "" { return nil }
        let s = L("s_" + w.SeasonNow)
        return s == "" ? nil : s
    }

    func LateLine() -> String? {
        let h = DateTime.Now.Hour
        if Night { return h >= 21 || h < 5 ? L("late_dd") : L("late_d") }
        if h >= 23 || h < 5 { return L("late23") }
        if h == 12 { return L("late12") }
        if h == 15 { return L("late15") }
        return nil
    }

    func AppLine(_ h: IntPtr) -> String {
        var name = ""
        // mac: Windows 用 Process.GetProcessById(pid).ProcessName；這裡用 NSRunningApplication，
        // 再把常見 App 的 bundle id 對應回 Windows 的行程名（code／chrome／excel…）
        var pid = 0
        _ = W.GetWindowThreadProcessId(h, &pid)
        if pid > 0, let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            let bid = (app.bundleIdentifier ?? "").lowercased()
            if bid.hasPrefix("com.microsoft.vscode") || bid.hasPrefix("com.visualstudio.code") { name = "code" }
            else if bid.hasPrefix("com.google.chrome") { name = "chrome" }
            else if bid.hasPrefix("com.microsoft.edgemac") { name = "msedge" }
            else if bid.hasPrefix("org.mozilla.firefox") { name = "firefox" }
            else if bid == "com.apple.safari" || bid.hasPrefix("company.thebrowser") { name = "chrome" }   // mac: Safari／Arc 當瀏覽器
            else if bid == "com.microsoft.excel" { name = "excel" }
            else if bid == "com.microsoft.powerpoint" { name = "powerpnt" }
            else if bid == "com.microsoft.word" { name = "winword" }
            else if bid.hasPrefix("com.microsoft.teams") { name = "teams" }
            else if bid == "com.tinyspeck.slackmacgap" { name = "slack" }
            else if bid == "jp.naver.line.mac" { name = "line" }
            else if bid == "com.apple.finder" { name = "explorer" }
            else { name = (app.localizedName ?? "").lowercased() }
        }
        let chat = name.Contains("teams") || name == "slack" || name == "line"
        if Night {
            if name == "code" { return L("app_code_d") }
            if chat { return L("app_chat_d") }
            if name == "excel" || name == "powerpnt" || name == "winword" { return L("app_office_d") }
            return L("app_other_d")
        }
        if name == "chrome" || name == "msedge" || name == "firefox" { return L("app_browser") }
        if name == "code" { return L("app_code") }
        if name == "excel" { return L("app_excel") }
        if name == "powerpnt" { return L("app_ppt") }
        if name == "winword" { return L("app_word") }
        if chat { return L("app_chat") }
        if name == "explorer" { return L("app_files") }
        return L("app_other")
    }

    // ---------- 選單／指令 ----------
    func Act(_ a: String) {
        if a != "sleep" { WakeIfSleep() }
        if !Out && a != "bond" && a != "hi" { Say(Pick(["我在櫃子裡，先放我出去～", "點一下櫃子裡的我，我就出來囉"]), 1.8); return }
        switch a {
        case "hi":
            if Out && Grounded() {
                // <fan>
                if Is("po") { SetState("wave", 1.6) }
                else if Is("hangyodon") { poseKind = "hero"; SetState("pose", 1.4) }
                else if Is("dipsy") { poseKind = "hattip"; SetState("pose", 1.6) }
                // </fan>
                else if P.Tubby || P.Orig { SetState("wave", 1.6) }   //@fan
                // <public> if P.Orig { SetState("wave", 1.6) }
                else { Jump(0, -260 * k) }
            }
            Say(L("hi"), 2.4)
        case "hug": Hug(L("hugs"), 2.4)
        case "pat": Pat()
        case "bond": ShowBond()
        case "knock": Knock(L("knock"), "user")
        case "jump": if !JumpToPlatform() { Say(L("nojump"), 1.6) }
        case "sleep": if Grounded() { GoSleep(); t = 8; Say(L("sleep"), 1.2) }
        case "sig": Signature()
        case "celebrate": Celebrate("", true)
        default: ActSpecial(a)
        }
    }

    // 慶祝（上版 tag／Codex、Claude 做完）：每個角色自己的方式
    func Celebrate(_ env: String, _ lead: Bool) {
        if Quiet && w.quietOn { return }
        WakeIfSleep()
        if !Out { if lead { Say(env == "prod" ? L("tag_prod") : (env == "dev" ? L("tag_dev") : L("tag")), 4) }; return }
        let line = Night ? L("tag") : (env == "prod" ? L("tag_prod") : (env == "dev" ? L("tag_dev") : L("tag")))
        CelebrateWith(line, lead)
        AddXp(lead ? 5 : 2)
    }

    func CelebrateWith(_ line: String, _ lead: Bool) {
        switch P.Id {
        // <fan>
        case "po": HomeRun(line, lead)
        case "stitch": if Grounded() { SetState("elvis", 4.5) }; Say(line, 4); for _ in 0..<3 { Mark(0) }
        case "hangyodon": if Grounded() { poseKind = "hero"; SetState("pose", 3.4) }; Say(line, 4); for _ in 0..<6 { Mark(5) }; Burst(6)
        case "tinky": if Grounded() { TinkyBag("star", true) }; Say(line, 4); Burst(10)
        case "dipsy": if Grounded() { HatToss(true) }; Say(line, 4); Burst(8)
        case "laalaa": if Grounded() { SetState("twirl", 2.4) }; Say(line, 4); for _ in 0..<4 { Mark(0) }; Burst(8)
        // </fan>
        case "boba", "coffee", "onigiri", "sticky": OrigCelebrate(line, lead)
        default:
            if lead { w.Fireworks(w.WA(Cx, y + Double(SH) / 2.0), 10, -1) }
            if Grounded() { SetState("dance", 3.5) }
            Say(line, 4); Burst(10)
        }
        AddHeart(); AddHeart()
    }

    // Codex／Claude 做完：Spidey 敲玻璃；小波全壘打；其他人照自己的慶祝
    func Done(_ src: String, _ lead: Bool) {
        WakeIfSleep()
        who = src
        let text = L("done", "who", src)
        if !lead { React(); return }
        if !Out { Say(text, 4); return }
        if Is("spidey") { NoZoom(text, 4); Burst(8) }   //@fan
        else { CelebrateWith(text, true) }   //@fan
        // <public> CelebrateWith(text, true)
        AddXp(1)
    }

    func Wait(_ src: String) {
        WakeIfSleep()
        let text = L("wait", "who", src)
        NoZoom(text, 3)
    }

    func Unstuck(_ src: String) {
        stuckLine = nil
        Say(L("unstuck", "who", src), 2)
    }

    func LateTick() {
        if lateCd > 0 || !Out || !Free() || Quiet { return }
        guard let l = LateLine() else { return }
        lateCd = Night ? 240 : 600
        Say(l, 3.5); SetState("idle", 3.5)
    }
}
