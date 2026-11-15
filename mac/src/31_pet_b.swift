// C# 2697–3980：Pet partials — 角色專屬狀態、Spidey／小波／史迪仔／人魚漢頓的招牌動作、天線寶寶
import Foundation

//@@IN Pet
    var poseKind = ""           // pose 狀態畫哪個姿勢（homerun／hero／photo／grin）
    var batT = 0.0; var batHit = false       // 小波揮棒
    var scooterLost = false               // 小波的滑板車被史迪仔騎走了（串場）
    var RidingStolen = false       // 史迪仔正在騎別人的滑板車（串場）
    var crawlH: IntPtr = 0; var ceilY = 0.0, ceilL = 0.0, ceilR = 0.0 // 史迪仔爬牆／天花板
    var caped = false
    var headers = 0
    // ---- 天線寶寶 ----
    var hatLost = false                   // 迪西：帽子借給丁丁戴了（串場）
    var WearHat = false            // 戴著迪西的帽子（串場）
    var ballLost = false                  // 拉拉：球不見了（滾進丁丁的魔法袋、踢給小波）
    var RidingPo = false           // 丁丁騎小波的滑板車（串場）
    var HoldToast = false          // 吐司時間：手上拿著吐司（串場）
    var lentScooter = false               // 小波：滑板車借出去了（串場結束一定還回來）
    var bagItem = ""            // 魔法袋這次拿出來的東西
    var sT = 0.0, lastLandVy = 0.0          // 專屬動作計時、落地前的速度
    var juggles = 0
    var lastArmsUp = false
    var bagQuiet = false
//@@END

extension Pet {
    // 角色專屬狀態：回傳 true＝處理掉了
    func StepSpecial(_ dt: Double, _ wa: Rectangle) -> Bool {
        if HoldToast && rnd.NextDouble() < dt * 2.5 && notes.Count < 10 { notes.Add(Arr<Double>([R(-8, 8) * k, 0, 7])) }   // 吐司屑屑
        if P.Tubby && TubbyStep(dt) { return true }
        if P.Pik && PikStep(dt) { return true }
        switch state {
        case "plop":
            sT += dt
            if t < 0 { SetState("idle", InScene ? 30 : 1) }
            return true
        // ---- Spidey ----
        case "swing": Swing(dt, wa); return true
        case "hang": Hang(dt, wa); return true
        case "climb": Climb(dt, wa); return true
        case "shoot": Shoot(dt); return true
        case "zip": Zip(dt); return true
        case "peek": Peek(dt, wa); return true
        case "webcatch":
            if t < 0 { w.ReleaseBall(Cx, y, 0, 0); KickBallToCursor(1.0); SetState("kick", 0.4) }
            return true
        case "sling": if t < 0 { SetState("idle", 1) }; return true
        // ---- 小波 ----
        case "spin":
            if t < 0 { SetState("idle", 1); Say(Pick(["再來一次！", "再來一次！嘻嘻"]), 1.4) }
            return true
        case "bat": Bat(dt); return true
        case "catch":
            if t < 0 { SetState("throw", 0.35) }
            return true
        case "throw":
            if t < 0.15 && w.Holder === self { w.ReleaseBall(Cx + Double(dir) * 6 * k, y + 6 * k, 0, 0); KickBallToCursor(1.0) }
            if t < 0 { SetState("idle", 1) }
            return true
        // ---- 史迪仔 ----
        case "wall": Wall(dt, wa); return true
        case "ceil": Ceil(dt); return true
        case "curl": Curl(dt); return true
        case "nudge": if t < 0 { SetState("idle", 1) }; return true
        case "chomp": Chomp(dt); return true
        case "elvis":
            if rnd.NextDouble() < dt * 3 { Mark(0) }
            if t < 0 { SetState("idle", 1); if !InScene { Say(Pick(["Thank you very much ♪", "嘻嘻嘻 ♪"]), 1.6) } }
            return true
        // ---- 人魚漢頓 ----
        case "swim": Swim(dt); return true
        case "header": if t < 0 { SetState(fetching ? "fetch" : "idle", fetching ? 15 : 1) }; return true
        case "capetrip":
            capeT += dt
            if capeT >= 1.4 && capeT - dt < 1.4 { tripT = 1.1; Say(Pick(["哎呀…（跌倒）", "嗚…英雄也會跌倒的", "我、我沒事！"]), 1.8) }
            if t < 0 { SetState("idle", 1) }
            return true
        default: break
        }
        return false
    }

    // 走到視窗邊緣：0＝照預設跳下去、1＝回頭、2＝換狀態了
    func EdgeOfWindow(_ right: Bool) -> Int {
        if P.Pik { return PikEdge(right) }
        switch P.Id {
        case "spidey":
            if !goClimb && rnd.NextDouble() < 0.55 { dir = -dir; if rnd.NextDouble() < 0.3 { SpinWeb(supH, right) }; return 1 }
            return 0
        case "po":
            if rnd.NextDouble() < 0.4 { dir = -dir; return 1 }
            do {
                if let o = PickPlatform(60 * k, 700 * k), (o[0] > Cx) == (dir > 0) { BallisticTo(o[0], o[1]); Say(L("jump"), 0.9); return 2 }
            }
            x += Double(dir) * 4 * k; Jump(Double(dir) * P.Speed * k * 1.7, -280 * k); Say(L("jump"), 0.8)   // 小跳台飛出去
            return 2
        case "stitch":
            do {
                var wi: WinInfo! = nil
                if (goClimb || rnd.NextDouble() < 0.4) && w.Cands.ContainsKey(supH) { wi = w.Cands[supH] }
                if wi != nil && Math.Abs((right ? supR : supL) - (right ? wi.R : wi.L)) < 14
                    && wi.B < w.WA(Cx, y).Bottom - SH - 10
                { StartWallDown(wi, right); return 2 }
                if rnd.NextDouble() < 0.5 { dir = -dir; return 1 }
                return 0
            }
        case "hangyodon":
            if rnd.NextDouble() < 0.55 { dir = -dir; return 1 }
            do {
                if let o = PickPlatform(60 * k, 900 * k) { Say(L("jump"), 1.4); StartSwim(o[0], o[1], false); return 2 }
            }
            dir = -dir; return 1
        case "tinky":
            // 丁丁走路很小心：多半回頭；跳下去常常跌坐
            if rnd.NextDouble() < 0.7 { dir = -dir; if rnd.NextDouble() < 0.3 { Say("小心小心…", 1.2) }; return 1 }
            x += Double(dir) * 4 * k; Jump(Double(dir) * P.Speed * k * 2, -200 * k); afterLand = "plop"; Say("哎…", 0.8)
            return 2
        case "dipsy":
            if rnd.NextDouble() < 0.4 { dir = -dir; return 1 }
            x += Double(dir) * 4 * k; Jump(Double(dir) * 130 * k, -320 * k); afterLand = rnd.NextDouble() < 0.5 ? "hattip" : ""; Say("嘿！", 0.8)
            return 2
        case "laalaa":
            if rnd.NextDouble() < 0.35 { dir = -dir; return 1 }
            do {
                if let o = PickPlatform(60 * k, 700 * k), (o[0] > Cx) == (dir > 0) { BallisticTo(o[0], o[1]); afterLand = "twirl"; Say(L("jump"), 0.9); return 2 }
            }
            x += Double(dir) * 4 * k; Jump(Double(dir) * 150 * k, -360 * k); afterLand = "twirl"; Say(L("jump"), 0.8)
            return 2
        default: break
        }
        return 0
    }

    // 走到螢幕邊：true＝換狀態了（false＝回頭）
    func EdgeOfScreen() -> Bool {
        switch P.Id {
        case "spidey": if goClimb || rnd.NextDouble() < 0.35 { StartClimb(dir); return true }; return false
        case "stitch": if goClimb || rnd.NextDouble() < 0.3 { StartWallUp(dir); return true }; return false
        case "po": dir = -dir; Jump(Double(dir) * 60 * k, -220 * k); Say("嘟嘟～迴轉！", 0.9); return true
        default: break
        }
        return false
    }

    // 落地時的特別反應：true＝處理掉了
    func Landed(_ wasRolling: Bool, _ landVx: Double) -> Bool {
        if P.Pik && PikLanded(wasRolling) { return true }
        if Is("stitch") && wasRolling { vx = landVx * 0.8; if Math.Abs(vx) < 60 * k { vx = Double(dir) * 120 * k }; SetState("curl", R(0.8, 1.4)); return true }
        if Is("po") && wasRolling && state != "spin" { SetState("dizzy", 0.8); Say(Pick(["轉圈圈～", "再來一次！"]), 1.2); return true }
        if Is("po") && state == "spin" { SetState("spin", 0.4); return true }
        if Is("tinky") && lastLandVy > 650 * k && state != "plop" { afterLand = ""; Plop(Pick(["哎喲！", "哎喲…屁股好痛", "哎喲！（跌坐）"])); return true }
        if Is("laalaa") && wasRolling { afterLand = ""; SetState("twirl", 0.9); Say(Pick(["轉圈圈～", "再來一次！"]), 1.2); return true }
        return false
    }

    func LandAction() {
        let a = afterLand; afterLand = ""
        if P.Pik && PikLand(a) { return }
        switch a {
        case "wave": SetState("wave", 1.8); Say("Eh-oh!", 1.6)
        case "sniff": poseKind = "grin"; SetState("pose", 1.6); Mark(2); Say(Pick(["（聞聞）ih?", "嘻嘻，這個好玩", "ih-ih! 史迪仔的！"]), 1.6)
        case "bubbles": SetState("idle", 1.6); for _ in 0..<4 { Mark(5) }
        case "plop": Plop(Pick(["哎喲！", "哎喲！（跌坐）"]))
        case "hattip": poseKind = "hattip"; SetState("pose", 1.6); Say(Pick(["Eh-oh.", "嘿。", "（扶帽子）酷。"]), 1.4)
        case "twirl": SetState("twirl", 1.2); Say(Pick(["啦啦啦～", "轉圈圈～"]), 1.4)
        default: SetState("idle", R(1, 2))
        }
    }

    func Decide(_ wa: Rectangle) {
        goClimb = false
        if Bt > 0 && bubblePri > 0 { SetState("idle", R(1, 2)); return }   // 通知還在講：先別亂跑亂聊
        if fetching && w.BallOn { SetState("fetch", 15); return }
        let r = rnd.NextDouble(), cx = Cx
        if w.LunchState == "nap" && !Quiet { GoSleep(); t = 60; return }               // 吃飽睡午覺
        if HoldingFood() && !Quiet && r < 0.3 { SetState("idle", R(2, 4)); Say(LunchLine("talk"), 2.4); return }
        if Quiet {
            // 專注中：安靜發呆、偶爾慢慢走兩步
            if r < 0.75 { SetState("idle", R(5, 10)) } else { dir = rnd.NextDouble() < 0.5 ? -1 : 1; SetState("walk", R(1, 2.5)) }
            return
        }
        if w.OutCount() > 1 && rnd.NextDouble() < 0.12 && VisitFriend() { return }
        if P.Pik { PikDecide(r, wa); return }
        let lateOk: () -> Bool = { self.lateCd <= 0 && self.LateLine() != nil }
        switch P.Id {
        case "spidey":
            if r < 0.20 { SetState("idle", R(1.5, 4)) }
            else if r < 0.48 { if !JumpToPlatform() { Hop() } }
            else if r < 0.62 { if !ShootTo("swing") { Hop() } }
            else if r < 0.70 { _ = ShootTo("hang") }
            else if r < 0.75 { goClimb = true; dir = cx < Double(wa.Left + wa.Right) / 2.0 ? -1 : 1; SetState("walk", 30) }
            else if r < 0.80 { Hug(L("hugs"), 2.2) }
            else if r < (Night ? 0.84 : 0.815) { Knock(L("knock"), "ambient") }
            else if r < 0.86 && lateOk() { LateTick() }
            else if r < 0.90 && SeasonLine() != nil { Say(SeasonLine() ?? "", 3); SetState("idle", 3) }
            else { dir = rnd.NextDouble() < 0.5 ? -1 : 1; SetState("walk", R(3, 6)) }
        case "po":
            if r < 0.16 { SetState("idle", R(1.5, 3.5)) }
            else if r < 0.44 { dir = rnd.NextDouble() < 0.5 ? -1 : 1; SetState("walk", R(3, 7)); if rnd.NextDouble() < 0.25 { Say(Pick(["嘟嘟～", "騎車車～", "咻咻～"]), 1) } }
            else if r < 0.60 { if !JumpToPlatform() { Hop() } }
            else if r < 0.66 { SetState("wave", 1.6); Say(L("talk"), 2.2) }
            else if r < 0.71 { Hug(L("hugs"), 2.2) }
            else if r < (Night ? 0.76 : 0.74) { Knock(L("knock"), "ambient") }
            else if r < 0.79 { StartBat(false); Say("揮棒練習！嘿！", 1.2) }
            else if r < 0.83 && lateOk() { LateTick() }
            else if r < 0.87 && SeasonLine() != nil { Say(SeasonLine() ?? "", 3); SetState("idle", 3) }
            else if r < 0.92 { SetState("idle", 2.5); Say(L("talk"), 2.4) }
            else { dir = -dir; SetState("walk", R(3, 6)) }
        case "stitch":
            if r < 0.14 { SetState("idle", R(1.2, 3)) }
            else if r < 0.42 { dir = rnd.NextDouble() < 0.5 ? -1 : 1; SetState("walk", R(2, 5)) }
            else if r < 0.56 { if !JumpToPlatform() { Hop() } }
            else if r < 0.64 { Signature() }
            else if r < 0.70 { poseKind = "grin"; SetState("pose", 1.8); Say(Pick(["嘻嘻嘻…", "ih-ih-ih!", "（壞笑）"]), 1.6) }
            else if r < 0.74 { Hug(L("hugs"), 2.2) }
            else if r < (Night ? 0.80 : 0.78) { Knock(L("knock"), "ambient") }
            else if r < 0.82 { SetState("elvis", 3.5); Say(Night ? "♪ 呼啊～" : "♪ Aloha～", 1.6) }
            else if r < 0.85 && lateOk() { LateTick() }
            else if r < 0.88 && SeasonLine() != nil { Say(SeasonLine() ?? "", 3); SetState("idle", 3) }
            else if r < 0.93 { SetState("idle", 2); Say(L("talk"), 2.4) }
            else { dir = -dir; SetState("walk", R(2, 4)) }
        case "hangyodon":
            if r < 0.20 { SetState("idle", R(2, 4)); if rnd.NextDouble() < 0.4 { for _ in 0..<3 { Mark(5) } } }
            else if r < 0.46 { dir = rnd.NextDouble() < 0.5 ? -1 : 1; SetState("walk", R(3, 6)) }
            else if r < 0.58 { if let o = PickPlatform(60 * k, 900 * k) { StartSwim(o[0], o[1], false); Say(L("jump"), 1.2) } else { Hop() } }
            else if r < 0.64 { SetState("idle", 2.8); Say(L("pats"), 2.4); jokeT = 2.6 }
            else if r < 0.69 { Hug(L("hugs"), 2.2) }
            else if r < (Night ? 0.75 : 0.73) { Knock(L("knock"), "ambient") }
            else if r < 0.77 { poseKind = "hero"; SetState("pose", 1.8); Say(Pick(["總有一天我會當上英雄！", "（擺英雄姿勢）帥嗎？", "英雄漢頓…還在練習中"]), 2) }
            else if r < 0.80 { GoSleep(); t = R(5, 9); Say(L("sleep"), 1.4) }
            else if r < 0.84 && lateOk() { LateTick() }
            else if r < 0.87 && SeasonLine() != nil { Say(SeasonLine() ?? "", 3); SetState("idle", 3) }
            else if r < 0.93 { SetState("idle", 2.5); Say(L("talk"), 2.6) }
            else { dir = -dir; SetState("walk", R(3, 6)) }
        case "tinky":   // 慢慢走、提著魔法袋、偶爾跌坐、喜歡跳舞
            if r < 0.22 { SetState("idle", R(2, 4.5)) }
            else if r < 0.48 { dir = rnd.NextDouble() < 0.5 ? -1 : 1; SetState("walk", R(3, 7)); if rnd.NextDouble() < 0.2 { Say(Pick(["慢慢走～", "提著袋袋去散步～"]), 1.2) } }
            else if r < 0.54 { if !JumpToPlatform() { Hop() } }
            else if r < 0.63 { TinkyBag(nil, false) }
            else if r < 0.68 { SetState("dance", 3.2); Say(Pick(["丁丁跳舞～", "嘿～轉一圈～", "跳舞時間！"]), 1.6) }
            else if r < 0.72 { Plop(Pick(["哎喲！", "哎喲…（又跌倒了）"])) }
            else if r < 0.77 { Hug(L("hugs"), 2.2) }
            else if r < (Night ? 0.82 : 0.80) { Knock(L("knock"), "ambient") }
            else if r < 0.84 && lateOk() { LateTick() }
            else if r < 0.87 && SeasonLine() != nil { Say(SeasonLine() ?? "", 3); SetState("idle", 3) }
            else if r < 0.93 { SetState("idle", 2.5); Say(L("talk"), 2.4) }
            else { dir = -dir; SetState("walk", R(3, 6)) }
        case "dipsy":   // 酷酷的、跟著節奏走、帽子是他的招牌
            if r < 0.18 { SetState("idle", R(1.5, 3.5)) }
            else if r < 0.42 { dir = rnd.NextDouble() < 0.5 ? -1 : 1; SetState("walk", R(3, 6)) }
            else if r < 0.52 { if !JumpToPlatform() { Hop() } }
            else if r < 0.58 { poseKind = "hattip"; SetState("pose", 1.8); Say(L("talk"), 2.2) }
            else if r < 0.63 { HatToss(false) }
            else if r < 0.67 { poseKind = "hatwave"; SetState("pose", 2.2); Say(Pick(["（摘帽子揮一揮）Eh-oh!", "嘿～（揮帽子）"]), 1.8) }
            else if r < 0.73 { SetState("dance", 3.4); Say(Pick(["嘿～嘿～", "跟著節奏～", "迪西的舞步，酷。"]), 1.8) }
            else if r < 0.77 { Hug(L("hugs"), 2.2) }
            else if r < (Night ? 0.82 : 0.80) { Knock(L("knock"), "ambient") }
            else if r < 0.84 && lateOk() { LateTick() }
            else if r < 0.87 && SeasonLine() != nil { Say(SeasonLine() ?? "", 3); SetState("idle", 3) }
            else if r < 0.93 { SetState("idle", 2.5); Say(L("talk"), 2.4) }
            else { dir = -dir; SetState("walk", R(3, 6)) }
        case "laalaa":  // 蹦蹦跳跳、帶著球、愛唱歌轉圈圈
            if r < 0.14 { SetState("idle", R(1.2, 3)) }
            else if r < 0.40 { dir = rnd.NextDouble() < 0.5 ? -1 : 1; SetState("walk", R(3, 6)); if rnd.NextDouble() < 0.25 { Say(Pick(["啦～啦～", "蹦蹦跳～", "踢球球～"]), 1) } }
            else if r < 0.52 { if !JumpToPlatform() { Hop() } }
            else if r < 0.60 { Juggle() }
            else if r < 0.66 { SetState("twirl", 1.6); Say(Pick(["轉圈圈～", "啦啦啦～轉～"]), 1.4) }
            else if r < 0.72 { poseKind = "sing"; SetState("pose", 3.2); Say(Pick(["啦啦啦～♪", "啦～啦啦～啦～♪", "拉拉唱歌給你聽～♪"]), 2.6) }
            else if r < 0.76 { Hug(L("hugs"), 2.2) }
            else if r < (Night ? 0.81 : 0.79) { Knock(L("knock"), "ambient") }
            else if r < 0.83 && lateOk() { LateTick() }
            else if r < 0.86 && SeasonLine() != nil { Say(SeasonLine() ?? "", 3); SetState("idle", 3) }
            else if r < 0.93 { SetState("idle", 2.5); Say(L("talk"), 2.4) }
            else { dir = -dir; SetState("walk", R(3, 6)) }
        default:
            if r < 0.3 { SetState("idle", R(1.5, 4)) }
            else if r < 0.6 { if !JumpToPlatform() { Hop() } }
            else { dir = rnd.NextDouble() < 0.5 ? -1 : 1; SetState("walk", R(3, 6)) }
        }
    }

    // 去找另一隻（讓串場有機會發生）
    func VisitFriend() -> Bool {
        guard let o = w.RandomOther(self), o.Grounded(), o.state != "sleep" else { return false }
        let tx = o.Cx + Double(o.Cx > Cx ? -1 : 1) * Double(SW) * 1.1, foot = o.y + Double(o.SH)
        if o.supH == supH && Math.Abs(foot - (y + Double(SH))) < 3 {
            seekX = tx; dir = tx > Cx ? 1 : -1; SetState("walk", Math.Min(8, Math.Abs(tx - Cx) / (P.Speed * k) + 0.3))
            return true
        }
        if Math.Abs(tx - Cx) > 1000 * k { return false }
        if Is("hangyodon") { StartSwim(tx, foot, false) }
        else if Is("spidey") && rnd.NextDouble() < 0.5 { BallisticTo(tx, foot); Say("Thwip!", 0.8) }
        else { BallisticTo(tx, foot); if Is("po") { Say(L("jump"), 0.8) } }
        return true
    }

    // 右鍵選單的招牌動作
    func Signature() {
        if !Out { return }
        if P.Pik { PikSignature(); return }
        switch P.Id {
        case "spidey": if !ShootTo("swing") { Say("這裡太低了，甩不起來", 1.6) }
        case "po": if !JumpToPlatform() { Jump(Double(dir) * 200 * k, -520 * k); Say("咻～～", 1) } else { Say("咻～～再來一次！", 1.4) }
        case "stitch":
            if !Grounded() { break }
            goClimb = true
            if supH == IntPtr.Zero { let wa = w.WA(Cx, y); dir = Cx < Double(wa.Left + wa.Right) / 2.0 ? -1 : 1 }
            else { dir = Cx - Double(supL) < Double(supR) - Cx ? -1 : 1 }
            SetState("walk", 30); Say("ih-ih-ih! 爬牆！", 1.4)
        case "hangyodon":
            do {
                // 招牌：披上紅披風飛！（英雄夢）
                let o = PickPlatform(80 * k, 1100 * k)
                var tx: Double, ty: Double
                if let o = o { tx = o[0]; ty = o[1] }
                else {
                    let wa = w.WA(Cx, y + Double(SH) / 2.0)
                    tx = Pet.Clamp(Cx + (rnd.NextDouble() < 0.5 ? -1.0 : 1.0) * R(280, 520) * k, Double(wa.Left + SW), Double(wa.Right - SW))
                    ty = y + Double(SH)
                }
                StartSwim(tx, ty, true)
                flyArc = Math.Max(flyArc, 150 * k)
                Say(Pick(["英雄漢頓，出發！", "看我的披風！咻～", "這次一定要帥帥地飛！"]), 1.8)
            }
        case "tinky": TinkyBag(nil, false)
        case "dipsy": HatToss(false)
        case "laalaa": Juggle()
        default: break
        }
    }

    func ActSpecial(_ a: String) {
        if P.Pik && PikAct(a) { return }
        switch a {
        case "swing": if Is("spidey") { if !ShootTo("swing") { Say("這裡太低了，甩不起來", 1.6) } } else { Signature() }
        case "hang": if Is("spidey") { if !ShootTo("hang") { Say("上面沒地方黏", 1.6) } }
        case "climb":
            if Is("spidey") && Grounded() { goClimb = true; let wa = w.WA(Cx, y); dir = Cx < Double(wa.Left + wa.Right) / 2.0 ? -1 : 1; SetState("walk", 30) }
            else if Is("stitch") { Signature() }
        case "ride": if Grounded() { dir = rnd.NextDouble() < 0.5 ? -1 : 1; SetState("walk", R(6, 10)); Say("騎車車兜風囉～嘟嘟！", 1.6) }
        case "bat": if Grounded() { StartBat(false); Say("揮棒！嘿！", 1.2) }
        case "uke": if Grounded() { SetState("elvis", 4); Say("♪ Aloha～", 1.6) }
        case "cape": Signature()
        case "joke": if Grounded() { SetState("idle", 2.8) }; Say(L("pats"), 2.4); jokeT = 2.6
        case "bubble": SetState("idle", 1.6); for _ in 0..<5 { Mark(5) }; Say("噗嚕噗嚕～", 1.2)
        // ---- 天線寶寶 ----
        case "bag": TinkyBag(nil, false)
        case "dance":
            if Grounded() { SetState("dance", 3.5); Say(Is("dipsy") ? "嘿～嘿～（帽子跟著晃）" : (Is("laalaa") ? "啦啦啦～跳舞！" : "丁丁跳舞～轉一圈～"), 1.8) }
        case "plop": if Grounded() { Plop("哎喲！") }
        case "hatwave": if Grounded() && Is("dipsy") && !hatLost { poseKind = "hatwave"; SetState("pose", 2.2); Say("Eh-oh!（揮帽子）", 1.8) }
        case "hattoss": HatToss(false)
        case "juggle": Juggle()
        case "sing": if Grounded() { poseKind = "sing"; SetState("pose", 3.2); Say("啦啦啦～啦啦～♪", 2.6) }
        case "twirl": if Grounded() { SetState("twirl", 1.6); Say("轉圈圈～啦啦啦！", 1.6) }
        default: break
        }
    }

    // 新視窗跳出來
    func ReactNewWindow(_ win: WinInfo) {
        if !Grounded() || sleepMode || state == "hug" || InScene || fetching { return }
        switch P.Id {
        case "spidey": if !ZipToWindow(win, L("newwin")) { Say("有新視窗！👀", 1.5) }
        default:
            let after: String = Is("po") || Is("tinky") ? "wave" : (Is("hangyodon") ? "bubbles" : (Is("dipsy") ? "hattip" : (Is("laalaa") ? "twirl" : "sniff")))
            if !GoToWindow(win, L("newwin"), after) { Say(L("newwin"), 1.5) }
        }
    }

    // 你切到哪個視窗，他常常跟過去
    @discardableResult
    func FollowWindow(_ win: WinInfo, _ text: String) -> Bool {
        if !Grounded() || sleepMode || state == "hug" || InScene || fetching { return false }
        if Is("spidey") { return ZipToWindow(win, text) }
        return GoToWindow(win, text, "")
    }

    func GoToWindow(_ win: WinInfo, _ text: String, _ after: String) -> Bool {
        var tx = 0.0, top = 0.0
        if !PlatEnd(win, &tx, &top) { return false }
        if supH == win.H { Say(text, 2); if after != "" { afterLand = after; LandAction() }; return true }
        Say(text, 2)
        afterLand = after
        if Is("hangyodon") { StartSwim(tx, top, false) }
        else { BallisticTo(tx, top) }
        return true
    }

    func PlatEnd(_ win: WinInfo, _ tx: inout Double, _ top: inout Double) -> Bool {
        tx = 0; top = 0
        var bestD = Double.greatestFiniteMagnitude; var found = false
        for p in w.Plats {
            if p.H != win.H { continue }
            let half = Double(SW) / 2.0
            let ends: [Double] = [Double(p.Left) + half + 2, Double(p.Right) - half - 2]
            for e in ends { let d = Math.Abs(e - Cx); if d < bestD { bestD = d; tx = e; top = Double(p.Top); found = true } }
        }
        return found && bestD < 1400 * k
    }

    // ================= Spidey：噴絲 =================
    func FindAnchor(_ vertical: Bool) -> [Double]? {
        let cx = Cx, hy = y
        let wa = w.WA(cx, y + Double(SH) / 2.0)
        let opts = List<[Double]>()
        for wi in w.Cands.Values {
            if Double(wi.B) > hy - 70 * k || wi.B < wa.Top + 10 { continue }
            var px: Double
            if vertical { if cx < Double(wi.L + 6) || cx > Double(wi.R - 6) { continue }; px = cx }
            else {
                px = Pet.Clamp(cx + Double(dir) * R(60, 220) * k, Double(wi.L + 6), Double(wi.R - 6))
                if Math.Abs(px - cx) > 300 * k { continue }
            }
            if !w.PointVisible(wi, px, Double(wi.B - 2)) { continue }
            opts.Add([px, Double(wi.B)])
        }
        if opts.Count > 0 && rnd.NextDouble() < 0.85 { return opts[rnd.Next(opts.Count)] }
        let dist = hy - Double(wa.Top)
        if dist < 90 * k { return nil }
        if vertical { return [cx, Double(wa.Top)] }
        return [Pet.Clamp(cx + Double(dir) * Math.Min(dist * 0.6, 260 * k), Double(wa.Left + 10), Double(wa.Right - 10)), Double(wa.Top)]
    }

    @discardableResult
    func ShootTo(_ mode: String) -> Bool {
        if !Grounded() { return false }
        guard let a = FindAnchor(mode == "hang") else { return false }
        ax = a[0]; ay = a[1]
        dir = ax >= Cx ? 1 : -1
        nextAct = mode; shootT = 0
        SetState("shoot", 1)
        Say("Thwip!", 0.8)
        return true
    }

    func Shoot(_ dt: Double) {
        shootT += dt
        if shootT < 0.18 { return }
        supH = IntPtr.Zero
        if nextAct == "swing" {
            let hx = Cx, hy = y
            let swa = w.WA(hx, y + Double(SH) / 2.0)
            let maxL = Double(swa.Bottom - SH) - ay - 24 * k
            let ddx = hx - ax, ddy = hy - ay
            ropeL = Math.Min(Math.Sqrt(ddx * ddx + ddy * ddy), maxL)
            if ropeL < 36 * k { Jump(Double(dir) * 60 * k, -300 * k); return }
            th = asin(Pet.Clamp((hx - ax) / ropeL, -0.95, 0.95))
            if Math.Abs(th) < 0.5 { th = 0.9 * (hx < ax ? -1.0 : 1.0) }
            om = 0
            reelT = 0.18; reelX = x; reelY = y
            SetState("swing", 3.2)
        }
        else if nextAct == "hang" {
            let wa = w.WA(ax, y + Double(SH) / 2.0)
            targetL = Math.Max(10.0, Math.Min(Double(wa.Height) * R(0.15, 0.4), Double(wa.Bottom - SH - 10) - ay))
            hangPhase = 0; ropeL = 0
            SetState("hang", 99)
        }
        else { SetState("zip", 3) }
    }

    func Swing(_ dt: Double, _ wa: Rectangle) {
        let acc: Double = (900 * k / ropeL) * Math.Sin(th) * dt
        om = (om - acc) * 0.997
        th += om * dt
        let hx = ax + ropeL * Math.Sin(th), hy = ay + ropeL * Math.Cos(th), floorY = Double(wa.Bottom - SH)
        x = hx - Double(SW) / 2.0; y = Math.Min(hy, floorY)
        if reelT > 0 {
            let f = Pet.Ease(1 - reelT / 0.18)
            x = reelX + (x - reelX) * f; y = reelY + (y - reelY) * f
            reelT -= dt
        }
        let vxs = ropeL * Math.Cos(th) * om
        if Math.Abs(vxs) > 5 { dir = vxs > 0 ? 1 : -1 }
        if t < 0 || hy > floorY + 1 { Jump(vxs * 0.8, -ropeL * Math.Sin(th) * om * 0.8); if rnd.NextDouble() < 0.4 { Say("呀呼～", 0.9) } }
    }

    func Hang(_ dt: Double, _ wa: Rectangle) {
        x = ax - Double(SW) / 2.0
        if hangPhase == 0 {
            y -= 700 * k * dt
            if y <= ay + 4 { y = ay + 4; hangPhase = 1; ropeL = 0; t = 5; Say("倒吊看世界～", 2) }
            return
        }
        ropeL = Math.Min(targetL, ropeL + 160 * k * dt)
        y = ay + 4 + ropeL + Math.Sin(anim * 2.4) * 4 * k
        if t < 0 { Jump(0, 0) }
    }

    func Zip(_ dt: Double) {
        let tx = ax - Double(SW) / 2.0, ty = ay - Double(SH)
        let dx = tx - x, dy = ty - y, d = Math.Sqrt(dx * dx + dy * dy), sp = 1100 * k * dt
        if dx != 0 { dir = dx > 0 ? 1 : -1 }
        if d > sp && t > 0 { x += dx / d * sp; y += dy / d * sp; return }
        x = tx; y = ty
        for p in w.Plats {
            if p.H == zipH && ax >= Double(p.Left - 2) && ax <= Double(p.Right + 2) && Math.Abs(Double(p.Top) - ay) < 3 {
                SetSupport(p)
                SetState("idle", 1.6)
                w.AddWeb(zipH, zipRight)
                Say("黏好了！", 1.4)
                return
            }
        }
        Jump(0, 0)
    }

    func Peek(_ dt: Double, _ wa: Rectangle) {
        let prev = gt
        gt += dt
        dir = -wallSide
        let hideXp = wallSide < 0 ? Double(wa.Left) - Double(SW) * 0.55 : Double(wa.Right) - Double(SW) * 0.45
        let inX = Double(wallSide < 0 ? wa.Left : wa.Right - SW)
        x = gt < 0.4 ? inX + (hideXp - inX) * Pet.Ease(gt / 0.4) : hideXp
        if prev <= 0.4 && gt > 0.4 { Say("躲貓貓～", 1.2) }
        if t < 0 { x = inX; Say("找到我了嗎？嘿嘿", 1.6); climbDir = 1; SetState("climb", 99) }
    }

    func ZipToWindow(_ win: WinInfo, _ text: String) -> Bool {
        if !Grounded() || sleepMode || state == "hug" || fetching { return false }
        var tx = 0.0, top = 0.0
        if !PlatEnd(win, &tx, &top) { return false }
        if supH == win.H { Say(text, 2); return true }
        ax = tx; ay = top; zipH = win.H; zipRight = tx > Double(win.L + win.R) / 2.0
        dir = ax >= Cx ? 1 : -1
        nextAct = "zip"; shootT = 0
        SetState("shoot", 1)
        Say(text, 2)
        return true
    }

    func StartClimb(_ side: Int) {
        wallSide = side; climbDir = -1; dir = side; goClimb = false; supH = IntPtr.Zero
        SetState("climb", R(2, 7))
    }

    func Climb(_ dt: Double, _ wa: Rectangle) {
        x = Double(wallSide < 0 ? wa.Left : wa.Right - SW)
        if climbDir < 0 {
            y -= 50 * k * dt
            if y <= Double(wa.Top + 4) || t < 0 {
                y = Math.Max(y, Double(wa.Top + 4))
                if InScene { t = 1; return }
                let cr = rnd.NextDouble()
                if cr < 0.45 { Jump(Double(-wallSide) * R(200, 350) * k, -R(150, 300) * k); Say("喝！", 0.8) }
                else if cr < 0.75 { gt = 0; SetState("peek", R(2.5, 4)) }
                else { climbDir = 1 }
            }
        }
        else {
            y += 70 * k * dt
            if y >= Double(wa.Bottom - SH) { y = Double(wa.Bottom - SH); dir = -wallSide; SetState("walk", R(2, 5)) }
        }
    }

    func SpinWeb(_ h: IntPtr, _ right: Bool) {
        if !w.Cands.ContainsKey(h) { return }
        let wi: WinInfo = w.Cands[h]
        let edge = right ? supR : supL, corner = right ? wi.R : wi.L
        if Math.Abs(edge - corner) > 12 { return }
        w.AddWeb(h, right)
        SetState("idle", 1.4)
        Say("在這裡織個網～", 1.6)
    }

    // 多人接球：用絲把球黏住再踢回去
    func WebCatch() {
        w.HoldBall(self)
        ax = w.Bx; ay = w.By; shootT = 1
        dir = ax >= Cx ? 1 : -1
        SetState("webcatch", 0.6)
        Say(Pick(["Thwip! 接住了！", "用絲接球！", "好球！Thwip!"]), 1.4)
        w.Umpire("好球！")
    }

    // 串場：把小波甩上去
    func SlingAt(_ o: Pet) {
        ax = o.Cx; ay = o.y + 6 * k; shootT = 1; dir = ax >= Cx ? 1 : -1
        SetState("sling", 1.0)
    }

    // ================= 小波：滑板車、棒球 =================
    func OnScooter() -> Bool {
        if !Is("po") || scooterLost { return false }
        if state == "fling" { return !rolling }
        if state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto" { return true }
        if (state == "air" && !rolling) || state == "stowfly" { return true }
        return state == "idle" && t > 0 && (anim % 7) > 3.5
    }

    func StartBat(_ hitBall: Bool) {
        batT = 0; batHit = !hitBall
        SetState("bat", 1.1)
    }

    func Bat(_ dt: Double) {
        let prev = batT
        batT += dt
        if !batHit && prev < 0.22 && batT >= 0.22 && w.Holder === self {
            batHit = true
            let homer = rnd.NextDouble() < 0.45
            let bvx: Double = Double(dir) * (homer ? R(1300, 1700) : R(650, 950)) * k
            let bvy: Double = -(homer ? R(950, 1200) : R(450, 650)) * k
            w.ReleaseBall(Cx + Double(dir) * 14 * k, y + 8 * k, bvx, bvy)
            w.CatchCd = 1.2
            Burst(8)
            if homer {
                Say("全壘打！", 2.2)
                w.Fireworks(w.WA(Cx, y), 3, CInt(Cx + Double(dir) * 260 * k))
                w.Umpire("全壘打！")
                AddXp(1)
            }
            else { Say(Pick(["安打！", "打到了！再來一次！"]), 1.6); w.Umpire("好球！") }
        }
        if t < 0 { SetState("idle", 1) }
    }

    func PoBall() {
        let group = w.OutCount() > 1
        w.HoldBall(self)
        if rnd.NextDouble() < (group ? 0.6 : 0.3) { StartBat(true); Say("看我的！", 0.8); return }
        SetState("catch", 0.6)
        Say(L("ball_catch"), 1.8)
        w.Umpire("好球！")
    }

    // 全壘打慶祝（Codex／Claude 做完、上版）
    func HomeRun(_ line: String, _ lead: Bool) {
        if Grounded() { poseKind = "homerun"; SetState("pose", 3.4) }
        if lead { w.Fireworks(w.WA(Cx, y), 6, CInt(Cx)) }
        Say(line, 4); Burst(12)
    }

    // ================= 史迪仔：爬牆、天花板、咬球 =================
    func StartWallUp(_ side: Int) {
        wallSide = side; climbDir = -1; dir = side; goClimb = false; supH = IntPtr.Zero; crawlH = IntPtr.Zero
        SetState("wall", 99)
    }

    func StartWallDown(_ wi: WinInfo, _ right: Bool) {
        crawlH = wi.H; wallSide = right ? -1 : 1; climbDir = 1; goClimb = false; supH = IntPtr.Zero
        x = Double(right ? wi.R : wi.L - SW)
        ceilY = Double(wi.B); ceilL = Double(wi.L); ceilR = Double(wi.R - SW)
        SetState("wall", 99)
        Say("ih-ih! 爬下去～", 1.2)
    }

    func Wall(_ dt: Double, _ wa: Rectangle) {
        if crawlH == IntPtr.Zero {
            // 螢幕邊：往上爬到頂，然後倒掛在天花板上走
            x = Double(wallSide < 0 ? wa.Left : wa.Right - SW)
            y -= 130 * k * dt
            if y <= Double(wa.Top + 2) {
                y = Double(wa.Top); ceilY = Double(wa.Top); ceilL = Double(wa.Left); ceilR = Double(wa.Right - SW)
                dir = -wallSide; SetState("ceil", R(1.5, 3.5)); Say("倒立走路！嘻嘻嘻", 1.4)
            }
            return
        }
        // 視窗側邊：往下爬到視窗底，然後倒掛在視窗底下走
        var r = W.RECT()
        if !W.IsWindowVisible(crawlH) || !W.Rect(crawlH, &r) { Jump(0, 0); rolling = true; return }
        x = Double(wallSide < 0 ? r.R : r.L - SW)
        ceilY = Double(r.B); ceilL = Double(r.L); ceilR = Double(r.R - SW)
        y += 120 * k * dt
        if y >= ceilY - Double(SH) * 0.3 {
            y = ceilY; x = wallSide < 0 ? ceilR : ceilL
            dir = wallSide < 0 ? -1 : 1; SetState("ceil", R(1.5, 3))
        }
    }

    func Ceil(_ dt: Double) {
        if crawlH != IntPtr.Zero {
            var r = W.RECT()
            if !W.IsWindowVisible(crawlH) || !W.Rect(crawlH, &r) { Jump(0, 0); rolling = true; return }
            ceilY = Double(r.B); ceilL = Double(r.L); ceilR = Double(r.R - SW)
        }
        y = ceilY
        x += Double(dir) * 110 * k * dt
        if x < ceilL { x = ceilL; dir = 1 }
        if x > ceilR { x = ceilR; dir = -1 }
        if t < 0 { crawlH = IntPtr.Zero; Jump(0, 60 * k); rolling = true; Say(Pick(["跳！嗚哇～", "ih-ih-ih!", "放手！嘻嘻嘻"]), 1) }
    }

    func Curl(_ dt: Double) {
        x += vx * dt; vx *= Math.Pow(0.25, dt)
        rolling = true
        let nx = x
        let midY = y + Double(SH) / 2.0
        if !w.Inside(nx, midY) || !w.Inside(nx + Double(SW), midY) { vx = -vx }
        if supH != IntPtr.Zero && (Cx < Double(supL) || Cx > Double(supR)) { Jump(vx, -60 * k); return }
        if t < 0 { rolling = false; SetState("idle", 1); if rnd.NextDouble() < 0.5 { Say("嘻嘻嘻～", 1) } }
    }

    func StitchBall() {
        let group = w.OutCount() > 1
        w.HoldBall(self)
        if rnd.NextDouble() < (group ? 0.7 : 0.35) {
            SetState("chomp", group ? R(2, 3) : 1.2)
            Say(group ? "嘻嘻嘻！球是史迪仔的！" : Pick(["（咬）嘻嘻嘻", "ih-ih! 史迪仔的！", "（咬咬）好吃"]), 1.8)
            if group { w.Umpire("出局！…吧？") }
            return
        }
        SetState("catch", 0.5)
        Say(L("ball_catch"), 1.6)
        w.Umpire("好球！")
    }

    func Chomp(_ dt: Double) {
        if w.OutCount() > 1 {
            // 叼著球逃跑
            if let o = w.Nearest(self) { dir = o.Cx > Cx ? -1 : 1 }
            if MoveOnGround(dt, 160 * k) { return }
        }
        if t < 0 {
            if w.Holder === self { w.ReleaseBall(Cx + Double(dir) * 6 * k, y + 8 * k, 0, 0); KickBallToCursor(0.8) }
            Say(Pick(["噗！還你～", "呸！嘻嘻嘻"]), 1.2)
            SetState("idle", 1)
        }
    }

    // ================= 人魚漢頓：在空中「游泳」（波浪路線＋泡泡）、披風飛行、頂球 =================
    func StartSwim(_ tx: Double, _ footY: Double, _ cape: Bool) {
        fx0 = x; fy0 = y; fx1 = tx - Double(SW) / 2.0; fy1 = footY - Double(SH)
        let ddx = fx1 - fx0, ddy = fy1 - fy0
        let d = Math.Sqrt(ddx * ddx + ddy * ddy)
        flyDur = Pet.Clamp(d / ((cape ? 520 : 300) * k), 0.9, 4)
        flyArc = 30 * k + Math.Min(140 * k, d * 0.18)
        flyT = 0; supH = IntPtr.Zero; caped = cape
        dir = fx1 >= fx0 ? 1 : -1
        SetState("swim", 99)
    }

    func Swim(_ dt: Double) {
        flyT += dt
        let f = Math.Min(1, flyT / flyDur), e = Pet.Ease(f)
        let arc: Double = Math.Sin(Math.PI * f) * flyArc
        let wave: Double = caped ? 0 : Math.Sin(flyT * 7) * 9 * k * Math.Sin(Math.PI * f)
        x = fx0 + (fx1 - fx0) * e
        y = fy0 + (fy1 - fy0) * e - arc + wave
        if rnd.NextDouble() < dt * (caped ? 4 : 9) { Mark(5) }
        if f < 1 { return }
        x = fx1; y = fy1
        supH = IntPtr.Zero
        for p in w.Plats { if Cx >= Double(p.Left) && Cx <= Double(p.Right) && Math.Abs(Double(p.Top) - (y + Double(SH))) < 3 { SetSupport(p); break } }
        if supH == IntPtr.Zero {
            let wa = w.WA(Cx, y + Double(SH) / 2.0)
            if Math.Abs(Double(wa.Bottom) - (y + Double(SH))) > 3 { caped = false; Jump(0, 0); return }
        }
        let wasCape = caped; caped = false
        if afterLand != "" { LandAction() }
        else if wasCape { poseKind = "hero"; SetState("pose", 1.4); Say(Pick(["（落地）帥嗎？帥嗎？", "英雄著陸！…有點晃"]), 1.6) }
        else { SetState("idle", 1.2) }
    }

    // 像海豹一樣用頭頂球；偶爾連頂幾下
    func HangyodonBall() {
        SetState("header", 0.45)
        w.By = y - 2 * k; w.Bx = Cx
        headers += 1
        if headers < 3 && rnd.NextDouble() < 0.45 {
            w.Bvx = R(-60, 60) * k; w.Bvy = -R(520, 620) * k; w.CatchCd = 0.5
            fetching = true
            Say(Pick(["嘿咻！", "頂！頂！", "海豹式～"]), 0.9)
            return
        }
        headers = 0
        let c = Cursor.Position
        w.Bvx = Pet.Clamp((Double(c.X) - w.Bx) * 0.9, -800 * k, 800 * k); w.Bvy = -R(600, 760) * k; w.CatchCd = 1.0; w.BallIdle = 0
        Say(L("ball_catch"), 1.6)
        w.Umpire("好球！")
    }

    // 裁判喊聲（多人打棒球時由人魚漢頓喊）
    func Call(_ s: String) {
        if !Out || InScene { return }
        Say(s, 1.6)
        if Grounded() && state != "header" { poseKind = Is("dipsy") ? "hattip" : "hero"; SetState("pose", 0.9) }
    }

    // 串場用：直接設狀態／姿勢
    func ScenePose(_ kind: String, _ dur: Double) {
        if !Grounded() && kind != "fly" { return }
        switch kind {
        case "hero": poseKind = "hero"; SetState("pose", dur); Burst(6)
        case "photo": poseKind = "photo"; SetState("pose", dur)
        case "grin": poseKind = "grin"; SetState("pose", dur)
        case "silly": poseKind = "silly"; SetState("pose", dur)
        case "cape": poseKind = "hero"; SetState("pose", dur); for _ in 0..<3 { Mark(5) }
        case "wave": SetState("wave", dur)
        case "hug": SetState("hug", dur); AddHeart(); AddHeart()
        case "elvis": SetState("elvis", dur)
        case "hop": Jump(0, -260 * k)
        case "idle": SetState("idle", dur)
        case "dizzy": SetState("dizzy", dur)
        case "lick": poseKind = "lick"; SetState("pose", dur)
        // ---- 天線寶寶 ----
        case "plop": SetState("plop", dur); sT = 0; Burst(4); Mark(4)
        case "hattip", "hatwave", "hatdown", "sing": poseKind = kind; SetState("pose", dur)
        case "twirl", "dance", "kick", "catch", "spin": SetState(kind, dur)
        case "juggle": juggles = 0; sT = 0; SetState("juggle", dur)
        case "hattoss": sT = 0; SetState("hattoss", dur)
        case "bat": StartBat(false)
        default: if kind.StartsWith("bag") { TinkyBag(kind.Length > 4 ? kind.Substring(4) : "", true, dur) }
        }
    }
    func FaceTo(_ o: Pet) { dir = o.Cx > Cx ? 1 : -1 }
    func WalkTo(_ tx: Double, _ dur: Double) { seekX = tx; dir = tx > Cx ? 1 : -1; gotoSpeed = 1.5; SetState("goto", Math.Max(dur, 8)) }
    func RaceTo(_ tx: Double) { seekX = tx; dir = tx > Cx ? 1 : -1; gotoSpeed = Is("po") || Is("stitch") ? 1.4 : 1.1; SetState("goto", 10) }
    // 走到／跳到另一隻旁邊（串場前先湊在一起）；回傳大概要幾秒
    @discardableResult
    func ComeNear(_ o: Pet) -> Double {
        let mul: Double = P.Tubby || o.P.Tubby ? 2.0 : 1.35   // 天線寶寶比較寬（16 格＋道具）
        var tx = o.Cx + (Cx > o.Cx ? 1.0 : -1.0) * Double(o.SW) * mul
        let wa = w.WA(o.Cx, o.Foot - 4)
        tx = Pet.Clamp(tx, Double(wa.Left + SW), Double(wa.Right - SW))
        if supH == o.supH && Math.Abs(Foot - o.Foot) < 3 {
            let d = Math.Abs(tx - Cx)
            if d < Double(SW) * 0.6 { return 0 }
            if d < 700 * k { WalkTo(tx, 10); return Math.Min(6, d / (Math.Max(P.Speed, 60.0) * k * 1.5) + 0.3) }
        }
        if Is("hangyodon") { StartSwim(tx, o.Foot, false); return flyDur + 0.4 }
        BallisticTo(tx, o.Foot); return 1.6
    }
    func JumpTo(_ tx: Double, _ footY: Double) { BallisticTo(tx, footY) }
    func LoseScooter(_ lost: Bool) { scooterLost = lost }
    func ClimbRace(_ side: Int) { if Is("spidey") { StartClimb(side) } else if Is("stitch") { StartWallUp(side) } }
    var Foot: Double { return y + Double(SH) }
    var OnFloor: Bool { return supH == IntPtr.Zero }
}

// ================= 天線寶寶：丁丁（魔法袋）、迪西（乳牛紋帽子）、拉拉（大橘球）=================
extension Pet {
    var HasTv: Bool { return Is("po") || P.Tubby }

    static let TOAST: [String] = [".2222.", "211112", "2k11k2", "211112", "21kk12", ".2222."]
    static let STAR5: [String] = ["..y..", ".yyy.", "yyyyy", ".yyy.", ".y.y."]

    // 串場要用的小開關
    func LendHat(_ lent: Bool) { hatLost = lent }
    func LoseBall(_ lost: Bool) { ballLost = lost }
    func LendScooter(_ lent: Bool) { lentScooter = lent; LoseScooter(lent) }
    func ResetSceneProps() {
        if lentScooter { lentScooter = false; LoseScooter(false) }
        hatLost = false; WearHat = false; ballLost = false; RidingPo = false; HoldToast = false
        if state == "bagdig" { bagItem = "" }
    }
    // 頭頂（帽子中間）的螢幕座標：串場丟帽子、丟球用
    func HatPoint() -> PointF { return PointF(Cx, Foot - Double(SH) + Double((P.HeadTop - 3) * S)) }
    func HandPoint() -> PointF { return PointF(Cx + Double(dir * 5 * S), Foot - Double(SH) + Double((P.BodyTop + 2) * S)) }
    func FootPoint() -> PointF { return PointF(Cx + Double(dir * 4 * S), Foot - Double(3 * S)) }
    func BagPoint() -> PointF { return PointF(Cx + Double(dir * 9 * S), Foot - Double(SH) + Double((P.BodyTop + 3) * S)) }   // 打開的袋口（提在身體旁邊）
    func ClearCrumbs() { _ = notes.RemoveAll { n in n[2] == 7 } }

    func HatOnHead() -> Bool { return Is("dipsy") && !hatLost && state != "hattoss" && !(state == "pose" && poseKind == "hatwave") }

    // 丁丁：跌坐在地上「哎喲！」（小波在大家一起跌倒的串場也會）
    func Plop(_ text: String?) {
        SetState("plop", 1.5); sT = 0
        Burst(4); Mark(4)
        if let text = text { Say(text, 1.4) }
    }

    // 丁丁的魔法袋：打開、翻一翻、拿出東西（catch＝剛接住的球）
    func TinkyBag(_ item: String?, _ quiet: Bool) { TinkyBag(item, quiet, 2.4) }
    func TinkyBag(_ item: String?, _ quiet: Bool, _ dur: Double) {
        if !Is("tinky") || !Grounded() { return }
        var item = item
        if item == nil {
            let items: [String] = ["toast", "heart", "star", "toast", "ball"]
            item = items[rnd.Next(items.count)]
            let ll = w.Get("laalaa")
            if item == "ball" && (ll == nil || !ll!.Out) { item = "heart" }
        }
        bagItem = item ?? ""; bagQuiet = quiet; sT = 0
        SetState("bagdig", Math.Max(1.4, dur))
        if !quiet { Say(Pick(["魔法袋裡有什麼呢？", "丁丁找一找…", "（翻翻袋子）嗯…"]), 1.2) }
    }

    func BagReveal() {
        switch bagItem {
        case "catch":
            if w.Holder === self { w.ReleaseBall(Cx + Double(dir) * 8 * k, y + 6 * k, 0, 0); KickBallToCursor(0.9) }
            if !bagQuiet { Say(Pick(["找到了！還你～", "從魔法袋拿出來囉！"]), 1.6) }
        case "toast": if !bagQuiet { Say(Pick(["是吐司！", "吐司！要吃嗎？"]), 1.6) }
        case "heart": AddHeart(); AddHeart(); if !bagQuiet { Say("是愛心！送給你 ♥", 1.8) }
        case "star": Burst(10); if !bagQuiet { Say("是星星！✨", 1.6) }
        case "ball": if !bagQuiet { Say("咦？拉拉的球怎麼在這裡？", 2) }
        default: break
        }
    }

    // 迪西：帽子丟上去轉一圈、接回頭上
    func HatToss(_ quiet: Bool) {
        if !Is("dipsy") || !Grounded() || hatLost { return }
        sT = 0; SetState("hattoss", 1.6)
        if !quiet { Say(Pick(["看我的帽子！", "帽子戲法！", "嘿～"]), 1.2) }
    }

    // 拉拉：顛球（球在腳和頭頂之間跳）
    func Juggle() {
        if !Is("laalaa") || !Grounded() || ballLost { return }
        juggles = 0; sT = 0
        SetState("juggle", R(2.6, 3.6))
        Say(Pick(["看我的球！啦～", "顛球！1、2、3～", "球球跳跳～"]), 1.2)
    }
    func JugglePhase() -> Double { return (sT * 1.5) % 1.0 }

    func TubbyStep(_ dt: Double) -> Bool {
        if state == "pose" && poseKind == "sing" && rnd.NextDouble() < dt * 3 { Mark(0) }
        if state == "dance" && Is("laalaa") && rnd.NextDouble() < dt * 2 { Mark(0) }
        switch state {
        case "twirl":
            sT += dt
            if Math.Floor(anim * 9) != Math.Floor((anim - dt) * 9) { dir = -dir }
            if rnd.NextDouble() < dt * 3 { Mark(0) }
            if t < 0 { SetState("idle", InScene ? 30 : 1); if !InScene && Is("laalaa") && rnd.NextDouble() < 0.5 { Say("啦啦啦～", 1.2) } }
            return true
        case "hattoss":
            do {
                let prev = sT; sT += dt
                if prev < 1.25 && sT >= 1.25 { Burst(6); if !InScene { Say(Pick(["帥！", "接到了。酷。", "嘿～"]), 1.4) } }
                if t < 0 { SetState("idle", InScene ? 30 : 1) }
            }
            return true
        case "juggle":
            do {
                let prev = JugglePhase(); sT += dt
                if JugglePhase() < prev { juggles += 1; Mark(0); if !InScene { Say(String(juggles) + "！", 0.6) } }
                if t < 0 { SetState("idle", InScene ? 30 : 1); if !InScene { Say(juggles >= 3 ? "啦～！" + String(juggles) + " 下！" : "再來一次！", 1.4) } }
            }
            return true
        case "bagdig":
            do {
                let prev = sT; sT += dt
                if prev < 0.9 && sT >= 0.9 { BagReveal() }
                if t < 0 { if bagItem == "catch" && w.Holder === self { BagReveal() }; bagItem = ""; SetState("idle", InScene ? 30 : 1) }
            }
            return true
        default: break
        }
        return false
    }

    // ---------- 球（大家的球；小波在的話是棒球）----------
    func TinkyBall() {
        w.HoldBall(self)
        TinkyBag("catch", true, 1.8)
        if state != "bagdig" { w.ReleaseBall(Cx, y, 0, 0); KickBallToCursor(0.9) }   // 在空中接到：直接丟回去
        Say(L("ball_catch"), 1.6)
        w.Umpire("好球！")
    }

    // 迪西：用帽子頂球（偶爾連頂幾下）
    func DipsyBall() {
        SetState("header", 0.45)
        w.By = y + Double(SH) - Double(16 * S) + Double((P.HeadTop - 7) * S); w.Bx = Cx
        headers += 1
        if headers < 3 && rnd.NextDouble() < 0.4 {
            w.Bvx = R(-60, 60) * k; w.Bvy = -R(520, 620) * k; w.CatchCd = 0.5
            fetching = true
            Say(Pick(["帽子頂！", "嘿！再一下", "酷～"]), 0.9)
            return
        }
        headers = 0
        let c = Cursor.Position
        w.Bvx = Pet.Clamp((Double(c.X) - w.Bx) * 0.9, -800 * k, 800 * k); w.Bvy = -R(600, 760) * k; w.CatchCd = 1.0; w.BallIdle = 0
        Say(L("ball_catch"), 1.6)
    }

    // 拉拉：用腳踢（偶爾先顛幾下）
    func LaaLaaBall() {
        SetState("kick", 0.45)
        w.By = y + Double(SH) - w.BallR() - 2 * k; w.Bx = Cx + Double(dir) * 4 * k
        headers += 1
        if headers < 3 && rnd.NextDouble() < 0.45 {
            w.Bvx = R(-40, 40) * k; w.Bvy = -R(480, 600) * k; w.CatchCd = 0.5
            fetching = true
            Say(Pick(["1、2…", "啦～顛球！", "嘿咻！"]), 0.9)
            return
        }
        headers = 0
        let c = Cursor.Position
        w.Bvx = Pet.Clamp((Double(c.X) - w.Bx) * 1.1, -950 * k, 950 * k); w.Bvy = -R(500, 700) * k; w.CatchCd = 1.0; w.BallIdle = 0
        Say(L("ball_catch"), 1.6)
        w.Umpire("好球！")
    }

    // ---------- 畫 ----------
    func FrameTubby() -> Fr {
        let hug = state == "hug", sleep = state == "sleep", plop = state == "plop"
        let nightIdle = Night && state == "idle" && !InScene && !HoldingFood()
        let sit = sleep || plop || (Is("laalaa") && nightIdle)
        let yawn = Night && state == "idle" && (anim % 6) < 1.4
        var face: String?
        let posePhotoSingWave = state == "pose" && (poseKind == "photo" || poseKind == "sing" || poseKind == "hatwave")
        let happyA = hug || state == "twirl" || state == "juggle" || (state == "dance" && Step2(2))
        let happyB = (state == "bagdig" && sT > 0.9) || posePhotoSingWave
        if plop { face = sT < 0.55 ? "OUCH" : "HAPPY" }
        else if sleep || yawn || (Is("dipsy") && nightIdle) || (state == "pose" && poseKind == "hatdown") { face = "SLEEPY" }
        else if happyA || happyB { face = "HAPPY" }
        else if state == "dizzy" { face = "DIZZY" }
        else if state == "glass" { face = "SQUISH" }
        else { face = nil }
        var armsUp = state == "glass" || state == "catch" || state == "drag" || state == "air" || state == "fling"
        armsUp = armsUp || state == "kick" || state == "header" || (state == "throw" && t > 0.15)
        armsUp = armsUp || (state == "wave" && Step2(4)) || (state == "dance" && Step2(4)) || state == "twirl"
        armsUp = armsUp || (state == "hattoss" && (sT < 0.3 || (sT > 1.1 && sT < 1.5)))
        let poseArms = poseKind == "photo" || poseKind == "hatwave" || poseKind == "hattip" || (poseKind == "sing" && Step2(3))
        armsUp = armsUp || (state == "pose" && poseArms)
        armsUp = armsUp || (state == "bagdig" && sT > 0.9 && sT < 1.7)
        if RidingPo { armsUp = state == "air" || state == "drag" }
        lastArmsUp = armsUp
        let bodyName = hug || (nightIdle && !Is("dipsy")) ? "ARMS_HUG" : (armsUp ? "ARMS_UP" : "BODY")
        var legs: String
        let ride = RidingPo && !rolling
        if ride { legs = "LEGS_RIDE" }
        else if sit { legs = "LEGS_SIT" }
        else {
            let moving = state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto"
            let rate: Double = Is("tinky") ? 5 : (Is("laalaa") ? 9 : 7)
            var step = (moving && Step2(rate)) || (state == "dance" && Step2(4))
            step = step || (state == "juggle" && JugglePhase() < 0.2) || (state == "kick" && t > 0.15)
            legs = step ? "LEGS_B" : "LEGS_A"
        }
        let f = F(Pal.Stack(HeadRows(face), A(bodyName), A(legs)))
        if ride { f.Top = -4; f.AccDy = -4 }
        else if sit { f.AccDy = A("LEGS_A").count - A("LEGS_SIT").count }
        f.Tummy = !hug
        if rolling { f.Rot = CInt(Math.Floor(anim * 14)) % 4; f.Acc = false; f.Tummy = false }
        return f
    }

    func TubbyBob() -> Double {
        if state == "dance" || state == "elvis" { return Math.Abs(Math.Sin(anim * (Is("dipsy") ? 6 : 8))) * 6 * k }
        let moving = state == "walk" || state == "goto" || state == "seek" || state == "fetch"
        if moving && !RidingPo {
            if Is("laalaa") { return Math.Abs(Math.Sin(anim * 7)) * 5 * k }      // 蹦蹦跳跳
            if Is("dipsy") { return Math.Abs(Math.Sin(anim * 5)) * 2.5 * k }     // 跟著節奏
        }
        if Is("dipsy") && state == "idle" && !Night { return (Math.Floor(anim * 2) % 2) * k }   // 點頭打拍子
        return 0
    }

    // 拉拉的球現在在哪裡：none／floor（腳邊）／dribble（往前帶）／juggle／hold（抱著）／raised（舉高高）
    func BallSpot(_ f: Fr) -> String {
        if !Is("laalaa") || ballLost || w.BallOn || f.Rot != 0 || f.Fy { return "none" }
        if w.Lunch && HoldingFood() && state != "sleep" { return "none" }
        if state == "juggle" { return "juggle" }
        if state == "pose" && poseKind == "photo" { return "raised" }
        if Night && state == "idle" && !InScene { return "hold" }
        if state == "air" || state == "fling" || state == "drag" || state == "stowfly" { return "hold" }
        if state == "walk" || state == "goto" || state == "seek" || state == "hide" { return "dribble" }
        return "floor"
    }

    // 丁丁的袋子在哪裡：floor（放地上）／hand（提著）／up（舉起來）／hug（抱著）／open（打開翻找）
    func BagSpot(_ f: Fr) -> String {
        if !Is("tinky") || f.Rot != 0 || f.Fy { return "none" }
        if state == "bagdig" { return "open" }
        if state == "hug" || state == "sleep" || state == "plop" || RidingPo || HoldToast || (w.Lunch && HoldingFood()) { return "floor" }
        if Night && state == "idle" && !InScene { return "hug" }
        return lastArmsUp ? "up" : "hand"
    }

    func DrawTubbyBehind(_ g: Graphics, _ f: Fr, _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool) {
        if RidingPo && !rolling {
            if let po = Pal.Get("po") { DrawPixPal(g, po, po.Art["SCOOTER"], bx + (fx ? 12 - (-1) - 14 : -1) * ps, by + 7 * ps, ps, fx) }
        }
        if BagSpot(f) == "floor" { DrawAt(g, A("BAG"), HoldToast || w.Lunch ? -8.5 : 12.5, 9, bx, by, ps, fx, false, true) }   // 手上拿吃的：袋子放另一邊
        if BallSpot(f) == "floor" { DrawAt(g, A("BALL"), 12, 9, bx, by, ps, fx, false, true) }
    }

    func DrawTubbyFront(_ g: Graphics, _ f: Fr, _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool) {
        if f.Rot != 0 || f.Fy { return }
        let dy = f.AccDy
        // 迪西的帽子
        if Is("dipsy") && !hatLost {
            let hat = A("HAT")
            var row = Double(P.HeadTop - 6 + dy), col = -2.0
            if state == "hattoss" && sT < 1.25 {
                let ff = Pet.Clamp(sT / 1.25, 0, 1)
                row -= Math.Sin(Math.PI * ff) * 11
                let side = Math.Floor(sT * 10) % 2 == 1                       // 轉呀轉：正面、側面輪流
                let flipNow = fx != (Math.Floor(sT * 5) % 2 == 1)
                DrawAt(g, side ? A("HAT_HAND") : hat, side ? 2 : col, row, bx, by, ps, flipNow, false, true)
            }
            else if state == "pose" && poseKind == "hatwave" {
                DrawAt(g, A("HAT_HAND"), 11.0 + (Step2(4) ? 1.0 : 0.0), Double(P.BodyTop - 8 + dy), bx, by, ps, fx, false, true)
            }
            else {
                if state == "pose" && poseKind == "hattip" { row -= 2; col += 1 }
                else if state == "header" { row -= 1 }
                else if (state == "pose" && poseKind == "hatdown") || state == "sleep" || (Night && state == "idle" && !InScene) { row += 3 }   // 帽子拉低蓋住眼睛
                DrawAt(g, hat, col, row, bx, by, ps, fx, false, true)
            }
        }
        // 借戴迪西的帽子（串場）
        if WearHat { DrawAt(g, A("HAT"), -2, Double(P.HeadTop - 6 + dy), bx, by, ps, fx, false, true) }
        // 丁丁的魔法袋
        switch BagSpot(f) {
        case "hand": DrawAt(g, A("BAG"), 12 + (state == "walk" && Step2(5) ? 0.5 : 0), Double(P.BodyTop + 1 + dy), bx, by, ps, fx, false, true)
        case "up": DrawAt(g, A("BAG"), 12.5, Double(P.BodyTop - 5 + dy), bx, by, ps, fx, false, true)
        case "hug": DrawAt(g, A("BAG"), 2, Double(P.BodyTop + 2 + dy), bx, by, ps, fx, false, true)
        case "open":
            do {
                // 袋子打開提在身體旁邊，東西從袋口冒出來（不擋到臉）
                let bagRow = Double(P.BodyTop + 2 + dy)
                if let item = BagItemArt(), sT > 0.9 {
                    let rise = Pet.Clamp((sT - 0.9) / 0.35, 0, 1) * Double(item.count + 2)
                    if !(bagItem == "catch" && w.Holder !== self && sT > 1.3) {
                        DrawAt(g, item, 15 - Double(item[0].count) / 2.0, bagRow + 2 - rise, bx, by, ps, fx, false, true)
                    }
                }
                DrawAt(g, A("BAG_OPEN"), 11, bagRow, bx, by, ps, fx, false, true)
            }
        default: break
        }
        // 拉拉的球
        let ball = A("BALL")
        switch BallSpot(f) {
        case "juggle":
            do {
                let h = Math.Sin(Math.PI * JugglePhase()) * 12
                DrawAt(g, ball, 10, 9 - h, bx, by, ps, fx, false, true)   // 在身體前側顛，不擋臉
            }
        case "dribble": DrawAt(g, ball, 11.5, 9 - Math.Abs(Math.Sin(anim * 8)) * 2, bx, by, ps, fx, false, true)
        case "hold": DrawAt(g, ball, 2, Double(P.BodyTop + 2 + dy), bx, by, ps, fx, false, true)
        case "raised": DrawAt(g, ball, 2, Double(P.HeadTop - 8 + dy), bx, by, ps, fx, false, true)
        default: break
        }
    }

    func BagItemArt() -> [String]? {
        switch bagItem {
        case "toast": return Pet.TOAST
        case "heart": return Pet.HEART
        case "star": return Pet.STAR5
        case "ball": return A("BALL")
        case "catch": return w.BallKind == "baseball" ? Pet.BALLART : (w.BallKind == "tubby" ? A("BALL") : Pet.TBALL)
        default: break
        }
        return nil
    }

    // ---------- 櫃子裡：丁丁翻魔法袋、迪西抬帽子打拍子、拉拉拍球；晚上抱著自己的東西睡 ----------
    // mac: head 在 C# 是共用參考、ReplaceFace 會改它；這裡複製一份再用 inout 改（呼叫端之後不再用 head）
    func DrawTubbyShelf(_ g: Graphics, _ head: [String], _ fx: Int, _ bx: Int, _ by: Int, _ ps: Int, _ flip: Bool, _ tt: Double, _ blink: Bool) {
        var head = head
        var by = by
        var body = "BODY", legs = "LEGS_A"
        var normalFace = true, sit = false
        var groove = 0
        if Is("tinky") {
            if Night { body = "ARMS_HUG"; if (tt % 5) < 3 { ReplaceFace(&head, "SLEEPY"); normalFace = false } }
            else if (tt % 8) < 2.4 && !w.Lunch && (tt % 8) > 0.9 { ReplaceFace(&head, "HAPPY"); normalFace = false }
            else if blink { ReplaceFace(&head, "SLEEPY"); normalFace = false }
        }
        else if Is("dipsy") {
            if Night { ReplaceFace(&head, "SLEEPY"); normalFace = false }
            else {
                groove = Math.Floor(tt * 2.2) % 2 == 0 ? 0 : 1
                if (tt % 5) < 0.9 { ReplaceFace(&head, "HAPPY"); normalFace = false }
                else if blink { ReplaceFace(&head, "SLEEPY"); normalFace = false }
            }
        }
        else {
            if Night { sit = true; body = "ARMS_HUG"; legs = "LEGS_SIT"; if (tt % 6) < 4 { ReplaceFace(&head, "SLEEPY"); normalFace = false } }
            else if Math.Abs(Math.Sin(tt * 3.2)) > 0.8 { ReplaceFace(&head, "HAPPY"); normalFace = false }
            else if blink { ReplaceFace(&head, "SLEEPY"); normalFace = false }
        }
        by += groove
        let dy = sit ? A("LEGS_A").count - A("LEGS_SIT").count : 0
        let rows = Pal.Stack(head, A(body), A(legs))
        if Is("tinky") && w.Lunch { DrawAt(g, A("BAG"), 9.5, 9, bx, by, ps, flip, false, true) }
        DrawPix(g, rows, bx - (rows[0].count - 12) / 2 * ps, by + (16 - rows.count) * ps, ps, flip, false, true)
        DrawAccessories(g, bx, by, ps, flip, dy, normalFace)
        DrawStatusIcon(g, TummyStatus(), bx + 6 * ps, by + CInt((P.TummyRow + Double(dy)) * Double(ps)), Math.Max(1, ps / 2), true)
        if Is("tinky") && !w.Lunch {
            if Night { DrawAt(g, A("BAG"), 2, Double(P.BodyTop + 2), bx, by, ps, flip, false, true) }
            else if (tt % 8) < 2.4 {
                let ph = tt % 8
                let items: [[String]] = [Pet.TOAST, Pet.HEART, Pet.STAR5]
                let item = items[CInt(Math.Floor(tt / 8)) % 3]
                if ph > 0.9 {
                    let rise = Pet.Clamp((ph - 0.9) / 0.35, 0, 1) * Double(item.count + 2)
                    DrawAt(g, item, 13.5 - Double(item[0].count) / 2.0, Double(P.BodyTop + 5) - rise, bx, by, ps, flip, false, true)
                }
                DrawAt(g, A("BAG_OPEN"), 9.5, Double(P.BodyTop + 3), bx, by, ps, flip, false, true)
            }
            else { DrawAt(g, A("BAG"), 9, Double(P.BodyTop + 3), bx, by, ps, flip, false, true) }
        }
        if Is("dipsy") { DrawAt(g, A("HAT"), -2, Double(P.HeadTop - 6 + (Night ? 3 : ((tt % 5) < 0.9 ? -1 : 0))), bx, by, ps, flip, false, true) }
        if Is("laalaa") && Night { DrawAt(g, A("BALL"), 2, Double(P.BodyTop + 2 + dy), bx, by, ps, flip, false, true) }
        else if Is("laalaa") && !w.Lunch { DrawAt(g, A("BALL"), 9.5, 9 - Math.Abs(Math.Sin(tt * 3.2)) * 4, bx, by, ps, flip, false, true) }   // 在旁邊拍球（格子窄，靠近一點）
    }
}
