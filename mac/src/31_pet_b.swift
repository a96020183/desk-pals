// C# 2697–3980：Pet partials — 角色專屬狀態、Spidey／小波／史迪仔／人魚漢頓的招牌動作、天線寶寶
import Foundation

//@@IN Pet
    var poseKind = ""           // pose 狀態畫哪個姿勢（homerun／hero／photo／grin）
    var batT = 0.0; var batHit = false       // 小波揮棒
    var scooterLost = false               // 小波的滑板車被史迪仔騎走了（串場）
    var RidingStolen = false       // 史迪仔正在騎別人的滑板車（串場）
    var crawlH: IntPtr = 0; var ceilY = 0.0, ceilL = 0.0, ceilR = 0.0 // 史迪仔爬牆／天花板
    var sT = 0.0, lastLandVy = 0.0          // 專屬動作計時、落地前的速度
//@@END

extension Pet {
    // 角色專屬狀態：回傳 true＝處理掉了
    func StepSpecial(_ dt: Double, _ wa: Rectangle) -> Bool {
        if HoldToast && rnd.NextDouble() < dt * 2.5 && notes.Count < 10 { notes.Add(Arr<Double>([R(-8, 8) * k, 0, 7])) }   // 吐司屑屑
        if P.Tubby && TubbyStep(dt) { return true }
        if P.Pik && PikStep(dt) { return true }
        if P.Orig && OrigStep(dt) { return true }
        if P.Cu && CuStep(dt) { return true }
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
        if P.Orig { return OrigEdge(right) }
        if P.Cu { return CuEdge(right) }
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
        if P.Orig && OrigLanded(wasRolling) { return true }
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
        if P.Orig && OrigLand(a) { return }
        if P.Cu && CuLand(a) { return }
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
        if P.Orig { OrigDecide(r, wa); return }
        if P.Cu { CuDecide(r, wa); return }
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
        if P.Orig { OrigSignature(); return }
        if P.Cu { CuSignature(); return }
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
        if P.Orig && OrigAct(a) { return }
        if P.Cu && CuAct(a) { return }
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
        if P.Orig { OrigNewWindow(win); return }
        switch P.Id {
        case "spidey": if !ZipToWindow(win, L("newwin")) { Say("有新視窗！👀", 1.5) }
        default:
            let after: String = Is("po") || Is("tinky") ? "wave" : (Is("hangyodon") ? "bubbles" : (Is("dipsy") ? "hattip" : (Is("laalaa") ? "twirl" : (P.Cu ? "" : "sniff"))))
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
        let mul: Double = P.Tubby || o.P.Tubby ? 2.0 : (P.Orig ? 1.6 : 1.35)   // 天線寶寶比較寬（16 格＋道具）
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
    // 頭頂（帽子中間）的螢幕座標：串場丟帽子、丟球用
    func HatPoint() -> PointF { return PointF(Cx, Foot - Double(SH) + Double((P.HeadTop - 3) * S)) }
    func HandPoint() -> PointF { return PointF(Cx + Double(dir * 5 * S), Foot - Double(SH) + Double((P.BodyTop + 2) * S)) }
    func FootPoint() -> PointF { return PointF(Cx + Double(dir * 4 * S), Foot - Double(3 * S)) }
    func ClimbRace(_ side: Int) { if Is("spidey") { StartClimb(side) } else if Is("stitch") { StartWallUp(side) } }
    var Foot: Double { return y + Double(SH) }
    var OnFloor: Bool { return supH == IntPtr.Zero }
}
