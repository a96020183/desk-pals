// 32_pet_draw.swift — port of DeskPals.cs lines 3981–5406
// (Fr, Pet drawing partial, ShelfForm, Pet shelf-drawing partial)
import Foundation

// ================= 畫（每個角色的姿勢、配件、特效）=================
final class Fr
{
    var Rows: [String] = []
    var Top = 0, Rot = 0          // Top：圖的第一列放在 16 格框的第幾列（可負）；Rot：轉 90° 的次數
    var Fy = false, Acc = true, Tummy = false
    var AccDy = 0                 // 配件（帽子等）要跟著頭上下移多少格
}

//@@IN Pet
    var frameBmp: Bitmap! = nil
//@@END

extension Pet
{
    static let SCARF = [ "..YYYYYYYY..", "......YY....", "......Y....." ]
    static let BEANIE = [ ".....WW.....", "....PPPP....", "...PPPPPP...", "..WWWWWWWW.." ]
    static let CROWN = [ "...Y.YY.Y...", "...YYYYYY...", "...YPYYPY..." ]
    static let SANTA = [ "........WW..", ".....SSSS...", "....SSSSSS..", "...WWWWWWWW." ]
    static let GLASSES = [ "..P.P..P.P..", "..PPPkkPPP..", "...P....P..." ]
    static let ENVELOPE = [ "SSS", "SYS", "SSS", "SSS" ]
    static let CAKE = [ ".Y..", "PPPP", "WWWW", "PPPP" ]
    static let FLAKE = [ ".B.", "BBB", ".B." ]
    static let STAR = [ ".y.", "yyy", ".y." ]
    static let HEART = [ ".pp.pp.", "ppppppp", "ppppppp", ".ppppp.", "..ppp..", "...p..." ]
    static let ZZ = [ "kkkk", "..k.", ".k..", "kkkk" ]
    static let NOTE = [ "..kk", "..kk", "..k.", "..k.", "kkk.", "kk.." ]
    static let EXCL = [ "SS", "SS", "SS", "..", "SS" ]
    static let QUES = [ ".kkk.", "k...k", "...k.", "..k..", ".....", "..k.." ]
    static let DROP = [ ".B.", "BBB", "BBB", ".B." ]
    static let BADGE = [ "YY" ]
    static let BALLART = [ ".33.", "3433", "3343", ".33." ]
    static let TBALL = [ ".yy.", "yyyy", "yyyy", ".yy." ]
    // 小波的球棒（三個角度）、手套
    static let BAT_UP = [ "..11", "..12", ".12.", ".2..", "k...", "k..." ]
    static let BAT_FWD = [ "k11111122" ]
    static let BAT_FOLLOW = [ "11..", "21..", ".21.", "..2.", "...k", "...k" ]
    static let GLOVE = [ ".55.", "5665", "5565", ".55." ]

    // mac: instance accessors so the C#-style unqualified names work inside Pet methods (any file)
    var SCARF: [String] { return Pet.SCARF }
    var BEANIE: [String] { return Pet.BEANIE }
    var CROWN: [String] { return Pet.CROWN }
    var SANTA: [String] { return Pet.SANTA }
    var GLASSES: [String] { return Pet.GLASSES }
    var ENVELOPE: [String] { return Pet.ENVELOPE }
    var CAKE: [String] { return Pet.CAKE }
    var FLAKE: [String] { return Pet.FLAKE }
    var STAR: [String] { return Pet.STAR }
    var HEART: [String] { return Pet.HEART }
    var ZZ: [String] { return Pet.ZZ }
    var NOTE: [String] { return Pet.NOTE }
    var EXCL: [String] { return Pet.EXCL }
    var QUES: [String] { return Pet.QUES }
    var DROP: [String] { return Pet.DROP }
    var BADGE: [String] { return Pet.BADGE }
    var BALLART: [String] { return Pet.BALLART }
    var TBALL: [String] { return Pet.TBALL }
    var BAT_UP: [String] { return Pet.BAT_UP }
    var BAT_FWD: [String] { return Pet.BAT_FWD }
    var BAT_FOLLOW: [String] { return Pet.BAT_FOLLOW }
    var GLOVE: [String] { return Pet.GLOVE }

    func F(_ rows: [String]) -> Fr { let f = Fr(); f.Rows = rows; return f }
    func A(_ n: String) -> [String] { if P.Art.ContainsKey(n) { return P.Art[n] }; App.Log("missing art " + P.Id + "." + n); return P.Art["BODY"] }

    // mac: replace single ASCII chars in a pixel-art row (C#: ToCharArray / new string)
    static func SetPix(_ s: String, _ i: Int, _ c: UInt8) -> String
    {
        var a = Array(s.utf8)
        if i >= 0 && i < a.count { a[i] = c }
        return String(decoding: a, as: UTF8.self)
    }
    static func PixAt(_ s: String, _ i: Int) -> UInt8
    {
        let u = s.utf8
        if i < 0 || i >= u.count { return 0 }
        return u[u.index(u.startIndex, offsetBy: i)]
    }

    func HeadRows(_ face: String?) -> [String]
    {
        var head = A("HEAD")
        if let face = face, P.Art.ContainsKey(face)
        {
            let fr = A(face)
            var i = 0
            while i < fr.count && P.FaceRow + i < head.count
            {
                if fr[i].utf8.count == head[P.FaceRow + i].utf8.count { head[P.FaceRow + i] = fr[i] }
                i += 1
            }
        }
        else if P.EyeRow >= 0 && state != "glass"
        {
            // 眼睛跟著滑鼠
            let cp = Cursor.Position
            let dx = Double(cp.X) - Cx
            var off = dx < -30 ? -1 : (dx > 30 ? 1 : 0)
            if dir < 0 { off = -off }
            var e = Array(head[P.EyeRow].utf8)
            e[P.EyeL + off] = 107; e[P.EyeR + off] = 107   // 'k'
            head[P.EyeRow] = String(decoding: e, as: UTF8.self)
        }
        return head
    }

    func Step2(_ rate: Double) -> Bool { return Math.Floor(anim * rate) % 2 == 1 }

    func Frame() -> Fr
    {
        if P.Pik { return FramePik() }
        switch P.Id
        {
            case "po": return FramePo()
            case "stitch": return FrameStitch()
            case "hangyodon": return FrameHangyodon()
            case "tinky", "dipsy", "laalaa": return FrameTubby()
            default: break
        }
        return FrameSpidey()
    }

    // ---- Spidey（照舊）----
    func FrameSpidey() -> Fr
    {
        let sleep = state == "sleep", hug = state == "hug"
        var armsUp = state == "glass" || state == "kick" || (state == "dance" && Math.Floor(anim * 4) % 2 == 0) || state == "swing" || state == "air" || state == "fling" || state == "climb" || state == "drag" || state == "shoot" || state == "zip"
        armsUp = armsUp || state == "webcatch" || state == "sling" || state == "pose" || state == "stowfly" || (state == "hang" && hangPhase == 0) || (state == "idle" && Bt > 0)
        let step = ((state == "walk" || state == "climb" || state == "goto") && Step2(6))
            || ((state == "seek" || state == "fetch" || state == "hide") && Step2(11))
            || (state == "drag" && Step2(12))
            || (state == "dance" && Math.Floor(anim * 4) % 2 == 1)
        let face: String? = sleep ? "SLEEPY" : (hug ? "HAPPY" : (state == "dizzy" ? "DIZZY" : nil))
        var rows: [String] = HeadRows(face)
        rows += A(hug ? "ARMS_HUG" : (armsUp ? "ARMS_UP" : "BODY"))
        rows += A(step ? "LEGS_B" : "LEGS_A")
        if Night && !hug
        {
            if Pet.PixAt(rows[10], 5) == 107 && Pet.PixAt(rows[10], 6) == 107 { rows[10] = Pet.SetPix(Pet.SetPix(rows[10], 5, 119), 6, 119) }   // k → w
        }
        if !hug && Level() >= 5
        {
            if Pet.PixAt(rows[10], 5) != 114 && Pet.PixAt(rows[10], 6) != 114 { rows[10] = Pet.SetPix(Pet.SetPix(rows[10], 5, 89), 6, 89) }   // != r → Y
        }
        let f = F(rows)
        f.Fy = state == "hang" && hangPhase == 1
        return f
    }

    // ---- 小波 ----
    func FramePo() -> Fr
    {
        if state == "plop" { let pf = F(Pal.Stack(HeadRows(sT < 0.55 ? "DIZZY" : "HAPPY"), A("ARMS_UP"), A("LEGS_SIT"))); pf.Tummy = true; return pf }
        let hug = state == "hug", sleep = state == "sleep"
        let yawn = Night && state == "idle" && (anim % 6) < 1.4
        let face: String? = sleep || yawn ? "SLEEPY" : (hug || state == "spin" || (state == "pose" && poseKind == "homerun") ? "HAPPY" : (state == "dizzy" ? "DIZZY" : (state == "glass" ? "SQUISH" : nil)))
        var armsUp = state == "glass" || state == "catch" || state == "drag" || (state == "air" && !OnScooter()) || (state == "wave" && Step2(4)) || (state == "dance" && Step2(4))
        armsUp = armsUp || (state == "pose" && poseKind != "homerun") || state == "kick" || state == "throw" && t > 0.15
        let body = A(hug ? "ARMS_HUG" : (armsUp ? "ARMS_UP" : "BODY"))
        let f: Fr
        if OnScooter() { f = F(Pal.Stack(HeadRows(face), body, A("LEGS_RIDE"))); f.Top = -4; f.AccDy = -4 }
        else if sleep { f = F(Pal.Stack(HeadRows(face), body, A("LEGS_SIT"))) }
        else
        {
            let step = (state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto") && Step2(10) || (state == "dance" && Step2(4))
            f = F(Pal.Stack(HeadRows(face), body, A(step ? "LEGS_B" : "LEGS_A")))
        }
        f.Tummy = !hug
        if rolling { f.Rot = CInt(Math.Floor(anim * 14)) % 4; f.Acc = false; f.Tummy = false }
        return f
    }

    // ---- 史迪仔 ----
    func FrameStitch() -> Fr
    {
        let hug = state == "hug"
        if RidingStolen
        {
            // 偷騎小波的滑板車：站在車上
            let rs = F(Pal.Stack(HeadRows("HAPPY"), A("ARMS_UP"), A("LEGS_A"))); rs.Top = -4; rs.AccDy = -4; return rs
        }
        if rolling || state == "curl"
        {
            let b = F(A("BALL")); b.Rot = CInt(Math.Floor(anim * 12)) % 4; b.Acc = false; return b
        }
        if state == "sleep"
        {
            let b = F(A("BALL_SLEEP")); b.Acc = false; return b
        }
        let crawl = state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto" || (state == "chomp" && w.OutCount() > 1) || state == "ceil"
        let face: String? = hug ? "HAPPY" : (state == "dizzy" ? "DIZZY" : nil)
        var head = HeadRows(face)
        if crawl
        {
            let c = F(Pal.Stack(head, A(Step2(state == "ceil" ? 8 : 12) ? "CRAWL_B" : "CRAWL_A")))
            c.AccDy = 5
            if state == "ceil" { c.Fy = true; c.Acc = false }
            return c
        }
        // 耳朵：發呆時偶爾抖一抖；晚上垂下來
        if Night && (state == "idle" || state == "hug") { let ed = A("EARS_DOWN"); for i in 0..<ed.count { head[i] = ed[i] } }
        else if (state == "idle" || state == "pose") && (anim % 2.2) < 0.5 && Step2(8) { let eu = A("EARS_UP"); for i in 0..<eu.count { head[i] = eu[i] } }
        var armsUp = state == "wall" || state == "catch" || state == "drag" || state == "air" || state == "nudge" || state == "throw"
        armsUp = armsUp || (state == "elvis" && Step2(5)) || (state == "dance" && Step2(4)) || (state == "pose" && poseKind == "photo") || state == "kick"
        let lick = state == "glass" || (state == "pose" && poseKind == "lick"), grin = state == "chomp" || (state == "pose" && poseKind == "grin")
        if lick { ReplaceFace(&head, "LICKF") } else if grin { ReplaceFace(&head, "GRIN") }
        let bodyName = hug || (Night && state == "idle") ? "ARMS_HUG" : (lick ? "LICK" : (armsUp ? "ARMS_UP" : "BODY"))
        let step = (state == "wall" && Step2(8)) || (state == "elvis" && Step2(6)) || (state == "dance" && Step2(4))
        return F(Pal.Stack(head, A(bodyName), A(step ? "LEGS_B" : "LEGS_A")))
    }

    // ---- 人魚漢頓 ----
    func FrameHangyodon() -> Fr
    {
        let hug = state == "hug", sit = state == "sleep"
        let silly = state == "pose" && poseKind == "silly"
        let sleepy = state == "sleep" || (Night && state == "idle" && (anim % 5) < 1.5)
        let face: String? = sleepy ? "SLEEPY" : (hug || (state == "pose" && poseKind == "hero") ? "HAPPY" : (state == "dizzy" || tripT > 0 ? "DIZZY" : (silly ? "SILLY" : nil)))
        let head = HeadRows(face)
        var armsUp = state == "air" || state == "fling" || state == "drag" || state == "header" || state == "capetrip" || state == "swim"
        armsUp = armsUp || (state == "dance" && Step2(3)) || (state == "pose" && poseKind != "silly") || state == "kick"
        let bodyName = hug ? "ARMS_HUG" : (silly || state == "glass" ? "POUT" : (armsUp ? "ARMS_UP" : "BODY"))
        let moving = state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto"
        let legs = sit ? "LEGS_SIT" : (moving && Step2(4) ? "LEGS_B" : "LEGS_A")
        let f = F(Pal.Stack(head, A(bodyName), A(legs)))
        if tripT > 0 { f.Rot = dir > 0 ? 1 : 3; f.Acc = false }   // 跌個狗吃屎
        if rolling { f.Rot = CInt(Math.Floor(anim * 10)) % 4; f.Acc = false }
        return f
    }

    // 把只往右延伸的圖左邊補空白，讓 12 格的身體留在框的中間
    static func PadCenter(_ rows: [String], _ extra: Int) -> [String]
    {
        let pad = String(repeating: ".", count: Swift.max(0, extra))
        return rows.map { pad + $0 }
    }

    static func Rot90(_ rows: [String], _ r0: Int) -> [String]
    {
        let r = ((r0 % 4) + 4) % 4
        var cur = rows
        var n = 0
        while n < r
        {
            let h = cur.count, wd = cur[0].utf8.count
            var o = [[UInt8]](repeating: [UInt8](repeating: 46, count: h), count: wd)
            for ry in 0..<h
            {
                let row = Array(cur[ry].utf8)
                for rx in 0..<wd { o[rx][h - 1 - ry] = rx < row.count ? row[rx] : 46 }
            }
            cur = o.map { String(decoding: $0, as: UTF8.self) }
            n += 1
        }
        return cur
    }

    func DrawPix(_ g: Graphics, _ rows: [String], _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool, _ fy: Bool, _ withHalo: Bool)
    {
        let pal = Night ? P.Night : P.Day
        let hw = Math.Max(1, ps / 3)
        let h = rows.count
        let hb = SolidBrush(Night ? P.HaloNight : P.Halo)
        let b = SolidBrush(Color.Magenta)
        // mac: per-call colour lookup table (ASCII art) instead of a Dictionary<char> lookup per pixel
        var lut = [Color?](repeating: nil, count: 128)
        var pass = withHalo ? 0 : 1
        while pass < 2
        {
            var ry = 0
            while ry < h
            {
                let row = rows[ry].utf8
                let len = row.count
                var rx = 0
                for c in row
                {
                    if c != 46
                    {
                        let px = bx + (fx ? len - 1 - rx : rx) * ps, py = by + (fy ? h - 1 - ry : ry) * ps
                        if pass == 0 { g.FillRectangle(hb, px - hw, py - hw, ps + 2 * hw, ps + 2 * hw) }
                        else
                        {
                            let ci = Int(c & 127)
                            var col: Color
                            if let cc = lut[ci] { col = cc }
                            else
                            {
                                let ch = Character(Unicode.Scalar(c))
                                col = pal.ContainsKey(ch) ? pal[ch] : Color.Magenta
                                lut[ci] = col
                            }
                            b.Color = col
                            g.FillRectangle(b, px, py, ps, ps)
                        }
                    }
                    rx += 1
                }
                ry += 1
            }
            pass += 1
        }
    }

    // 12 格框座標放一張小圖（會跟著左右翻）
    func DrawAt(_ g: Graphics, _ art: [String], _ col: Double, _ row: Double, _ bx0: Int, _ by0: Int, _ ps: Int, _ fx: Bool, _ fy: Bool, _ halo: Bool)
    {
        let aw = art[0].utf8.count, ah = art.count
        let c = fx ? 12 - col - Double(aw) : col, r = fy ? 16 - row - Double(ah) : row
        DrawPix(g, art, bx0 + CInt(Math.Round(c * Double(ps))), by0 + CInt(Math.Round(r * Double(ps))), ps, fx, fy, halo)
    }
    // mac: Int overloads (C# promoted int → double implicitly)
    func DrawAt(_ g: Graphics, _ art: [String], _ col: Int, _ row: Int, _ bx0: Int, _ by0: Int, _ ps: Int, _ fx: Bool, _ fy: Bool, _ halo: Bool)
    { DrawAt(g, art, Double(col), Double(row), bx0, by0, ps, fx, fy, halo) }
    func DrawAt(_ g: Graphics, _ art: [String], _ col: Double, _ row: Int, _ bx0: Int, _ by0: Int, _ ps: Int, _ fx: Bool, _ fy: Bool, _ halo: Bool)
    { DrawAt(g, art, col, Double(row), bx0, by0, ps, fx, fy, halo) }
    func DrawAt(_ g: Graphics, _ art: [String], _ col: Int, _ row: Double, _ bx0: Int, _ by0: Int, _ ps: Int, _ fx: Bool, _ fy: Bool, _ halo: Bool)
    { DrawAt(g, art, Double(col), row, bx0, by0, ps, fx, fy, halo) }

    func DrawAccessories(_ g: Graphics, _ bx0: Int, _ by0: Int, _ ps: Int, _ fx: Bool, _ dy: Int, _ normalFace: Bool)
    {
        let lv = Level()
        if lv >= 2 { DrawAt(g, Pet.SCARF, P.HatCol, P.ScarfRow + dy, bx0, by0, ps, fx, false, false) }
        if lv >= 4 && normalFace && !P.NoGlasses { DrawAt(g, Pet.GLASSES, P.HatCol, P.GlassRow + dy, bx0, by0, ps, fx, false, false) }
        if lv >= 5 && !Is("spidey") { DrawAt(g, Pet.BADGE, P.BadgeCol, P.BadgeRow + dy, bx0, by0, ps, fx, false, false) }
        var hat: [String]? = w.SeasonNow == "xmas" ? Pet.SANTA : (lv >= 6 ? Pet.CROWN : (lv >= 3 ? Pet.BEANIE : nil))
        if HatOnHead() || WearHat || P.Pik { hat = nil }      // 迪西：自己的帽子不換（借戴迪西帽子時也一樣）
        if let hat = hat
        {
            DrawAt(g, hat, P.HatCol, P.HatRow + dy - hat.count, bx0, by0, ps, fx, false, true)
            if P.KeepAntenna && P.AntThrough
            {
                // 丁丁：天線從帽子中間穿出來（照原位置重畫，不墊高，櫃子格子才放得下）
                let head = A("HEAD"); let n = head.count - 9
                if n > 0
                {
                    let ant = Array(head[0..<n])
                    DrawAt(g, ant, Double(12 - ant[0].utf8.count) / 2.0, P.HeadTop - n + dy, bx0, by0, ps, fx, false, true)
                }
            }
            else if P.KeepAntenna
            {
                // 小波的天線（圓圈）要露在帽子上面
                let head = A("HEAD"); let an = P.AntRows >= 0 ? P.AntRows : P.TopRows - 1
                if an > 0
                {
                    let ant = Array(head[0..<an])
                    DrawAt(g, ant, Double(12 - ant[0].utf8.count) / 2.0, P.HatRow + dy - hat.count - ant.count + 1, bx0, by0, ps, fx, false, true)
                }
            }
        }
        if w.SeasonNow == "cny" { DrawAt(g, Pet.ENVELOPE, 11, P.SideRow + dy, bx0, by0, ps, fx, false, true) }
        if w.SeasonNow == "birthday" { DrawAt(g, Pet.CAKE, 11, P.SideRow - 1 + dy, bx0, by0, ps, fx, false, true) }
    }

    // ---- Codex／Claude 狀態：小波顯示在肚子螢幕上，其他人在頭旁邊一個小圖示 ----
    static let IC_SUN = [ "y.y.y", ".yyy.", "yyyyy", ".yyy.", "y.y.y" ]
    static let IC_HEART = [ "pp.pp", "ppppp", ".ppp.", "..p.." ]
    static let IC_MOON = [ ".yyy", "yy..", "yy..", "yy..", ".yyy" ]
    static let IC_CHECK = [ "....W", "...W.", "W.W..", ".W..." ]
    static let IC_BANG = [ "S", "S", "S", ".", "S" ]

    func DrawStatusIcon(_ g: Graphics, _ st: String, _ cx: Int, _ cy: Int, _ u: Int, _ onScreen: Bool)
    {
        var art: [String]? = nil
        let pal = Night ? P.Night : P.Day
        if st == "busy"
        {
            // 三個點輪流亮
            let on = CInt(Math.Floor(w.Now * 3)) % 3
            for i in 0..<3
            {
                let b = SolidBrush(i == on ? Color.FromArgb(0x3D, 0x8B, 0xFF) : Color.FromArgb(onScreen ? 0x7A : 0x9A, 0x84, 0x90, 0xA8))
                g.FillRectangle(b, cx - 4 * u + i * 3 * u, cy - u / 2 - (i == on ? u / 2 : 0), 2 * u, 2 * u)
            }
            return
        }
        if st == "done" { art = Pet.IC_CHECK }
        else if st == "stuck" { art = Pet.IC_BANG }
        else if st == "night" { art = Pet.IC_MOON }
        else if st == "heart" { art = Pet.IC_HEART }
        else if st == "sun" { art = Pet.IC_SUN }
        guard let a = art else { return }
        let aw = a[0].utf8.count * u, ah = a.count * u
        let bg = st == "done" ? Color.FromArgb(0x2E, 0xA0, 0x5A) : (st == "stuck" ? Color.FromArgb(0xFF, 0xF1, 0xC2) : Color.Empty)
        if !onScreen && bg != Color.Empty
        { g.FillRectangle(SolidBrush(bg), cx - aw / 2 - u, cy - ah / 2 - u, aw + 2 * u, ah + 2 * u) }
        if onScreen && st == "done"
        { g.FillRectangle(SolidBrush(bg), cx - aw / 2 - u, cy - ah / 2 - u, aw + 2 * u, ah + 2 * u) }
        let b = SolidBrush(Color.White)
        for r in 0..<a.count
        {
            var c = 0
            for chb in a[r].utf8
            {
                if chb != 46
                {
                    let ch = Character(Unicode.Scalar(chb))
                    b.Color = pal.ContainsKey(ch) ? pal[ch] : Color.White
                    g.FillRectangle(b, cx - aw / 2 + c * u, cy - ah / 2 + r * u, u, u)
                }
                c += 1
            }
        }
    }

    func TummyStatus() -> String
    {
        let st = w.Status()
        if st != "" { return st }
        if Night { return "night" }
        return state == "hug" || hearts.Count > 0 ? "heart" : "sun"
    }

    // 小波的滑板車、人魚漢頓的搖椅、隱形船…（畫在身體後面的）
    func DrawBehind(_ g: Graphics, _ f: Fr, _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool)
    {
        if Is("po") && !scooterLost
        {
            if OnScooter() && !rolling { DrawAt(g, A("SCOOTER"), -1, 7, bx, by, ps, fx, false, true) }
            else if state == "idle" || state == "hug" || state == "wave" || state == "pose" || state == "dizzy" || state == "sleep" || state == "spin" || state == "think" || state == "plop"
            { DrawAt(g, A("SCOOTER"), 7, 7, bx, by, ps, !fx, false, true) } // 停在旁邊（車頭朝外）
        }
        if Is("stitch") && RidingStolen
        {
            let po = Pal.Get("po")
            if po != nil { DrawPixPal(g, po!, po!.Art["SCOOTER"], bx + (fx ? 12 - (-1) - 14 : -1) * ps, by + 7 * ps, ps, fx) }
        }
        if Is("hangyodon") && (caped || state == "capetrip" || (state == "pose" && poseKind == "hero"))
        {
            // 紅披風（飄在背後）
            let flap = Step2(caped ? 10 : 4)
            DrawAt(g, A("CAPE"), flap ? -4 : -3.5, 7, bx, by, ps, fx, false, true)
        }
        if Is("hangyodon") && state == "sleep" { DrawSleepBubble(g, bx, by, ps, false) }
        if P.Tubby { DrawTubbyBehind(g, f, bx, by, ps, fx) }
        if P.Pik { DrawPikBehind(g, f, bx, by, ps, fx) }
    }

    // 人魚漢頓睡在泡泡裡（先畫泡泡底，身體畫完再畫亮面）
    func DrawSleepBubble(_ g: Graphics, _ bx: Int, _ by: Int, _ ps: Int, _ front: Bool)
    {
        let dps = Double(ps)
        let cx = Double(bx) + 6 * dps, r = 9.5 * dps
        var cy = Double(by) + 9.5 * dps
        cy += Math.Sin(anim * 1.6) * dps * 0.5
        if !front
        { g.FillEllipse(SolidBrush(Color.FromArgb(Night ? 60 : 45, 170, 225, 255)), cx - r, cy - r, 2 * r, 2 * r) }
        else
        {
            g.DrawEllipse(Pen(Color.FromArgb(150, 200, 240, 255), Math.Max(1.5, dps * 0.45)), cx - r, cy - r, 2 * r, 2 * r)
            g.DrawArc(Pen(Color.FromArgb(200, 255, 255, 255), Math.Max(1.5, dps * 0.5)), cx - r * 0.75, cy - r * 0.75, r * 1.5, r * 1.5, 200.0, 50.0)
        }
    }

    func DrawPixPal(_ g: Graphics, _ pal: Pal, _ rows: [String], _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool)
    {
        let cols = Night ? pal.Night : pal.Day
        let b = SolidBrush(Color.Magenta)
        for ry in 0..<rows.count
        {
            let row = rows[ry].utf8
            let len = row.count
            var rx = 0
            for c in row
            {
                if c != 46
                {
                    let px = bx + (fx ? len - 1 - rx : rx) * ps
                    let ch = Character(Unicode.Scalar(c))
                    b.Color = cols.ContainsKey(ch) ? cols[ch] : Color.Magenta
                    g.FillRectangle(b, px, by + ry * ps, ps, ps)
                }
                rx += 1
            }
        }
    }

    // 球棒、手套、烏克麗麗、嘴裡的球（畫在身體前面的）
    func DrawFront(_ g: Graphics, _ f: Fr, _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool)
    {
        if Is("po")
        {
            if state == "bat"
            {
                if batT < 0.2 { DrawAt(g, Pet.BAT_UP, -1, 4, bx, by, ps, fx, false, true) }
                else if batT < 0.34 { DrawAt(g, Pet.BAT_FWD, 9, 10, bx, by, ps, fx, false, true) }
                else { DrawAt(g, Pet.BAT_FOLLOW, 9, 3, bx, by, ps, fx, false, true) }
                if w.Holder === self && batT < 0.22 { DrawAt(g, Pet.BALLART, 13 - batT * 10, 9, bx, by, ps, fx, false, true) }
            }
            if state == "pose" && poseKind == "homerun" { DrawAt(g, Pet.BAT_FOLLOW, 9, 3, bx, by, ps, fx, false, true) }
            if state == "catch" || state == "throw"
            {
                DrawAt(g, Pet.GLOVE, 11, 6, bx, by, ps, fx, false, true)
                if w.Holder === self { DrawAt(g, Pet.BALLART, 11, 5, bx, by, ps, fx, false, true) }
            }
        }
        if Is("stitch")
        {
            let uke = state == "elvis" || (Night && state == "idle") || (state == "pose" && poseKind == "uke")
            if uke { DrawAt(g, A("UKE"), 5, 8, bx, by, ps, fx, false, true) }
            if w.Holder === self && (state == "chomp" || state == "catch" || state == "throw" || state == "walk")
            { DrawAt(g, w.BallKind == "baseball" ? Pet.BALLART : Pet.TBALL, 4, state == "chomp" || state == "walk" ? (f.AccDy > 0 ? 11 : 6) : 3, bx, by, ps, fx, false, true) }
        }
        if Is("hangyodon") && state == "sleep" { DrawSleepBubble(g, bx, by, ps, true) }
        if Is("spidey") && w.Holder === self { DrawAt(g, w.BallKind == "baseball" ? Pet.BALLART : Pet.TBALL, 9, 4, bx, by, ps, fx, false, true) }
        if P.Tubby { DrawTubbyFront(g, f, bx, by, ps, fx) }
        if P.Pik { DrawPikFront(g, f, bx, by, ps, fx) }
        if HoldToast && f.Rot == 0 && !f.Fy { DrawAt(g, Pet.TOAST, Is("po") ? 9.5 : 10.5, P.BodyTop + 1 + f.AccDy, bx, by, ps, fx, false, true) }
    }

    // ================= 一格一格畫到 layered window =================
    func Grow(_ l: inout Double, _ tp: inout Double, _ r: inout Double, _ b: inout Double, _ px: Double, _ py: Double)
    {
        l = Math.Min(l, px); r = Math.Max(r, px); tp = Math.Min(tp, py); b = Math.Max(b, py)
    }
    func SilkVisible() -> Bool { return state == "swing" || state == "hang" || state == "zip" || state == "shoot" || state == "webcatch" || state == "sling" }
    func Bob() -> Double { if P.Pik { return PikBob() }; if P.Tubby { return TubbyBob() }; return state == "dance" || state == "elvis" ? Math.Abs(Math.Sin(anim * 8)) * 6 * k : (Is("hangyodon") && state == "walk" ? (Step2(4) ? k : 0) : 0) }

    func Render()
    {
        if !Out || w.Hidden { HideForms(); return }
        EnsureForms()
        let dS = Double(S), dSW = Double(SW), dSH = Double(SH)
        var l = x - 11 * dS, tp = y - 10 * dS, r = x + dSW + 11 * dS, b = y + dSH + 2 * dS
        if sc > 1 { let cxs = Cx; l = Math.Min(l, cxs - dSW * sc / 2 - 4 * dS); r = Math.Max(r, cxs + dSW * sc / 2 + 4 * dS); tp = Math.Min(tp, y + dSH - dSH * sc - 8 * dS * sc) }
        if SilkVisible() { Grow(&l, &tp, &r, &b, ax, ay) }
        if state == "sleep" { r = Math.Max(r, x + dSW + 26 * k); tp = Math.Min(tp, y - 36 * k) }
        if sense > 0 { l = Math.Min(l, Cx - 50 * k); r = Math.Max(r, Cx + 50 * k) }
        if hearts.Count > 0 || notes.Count > 0 { tp = Math.Min(tp, y - 90 * k) }
        for sp in sparks { Grow(&l, &tp, &r, &b, sp[0], sp[1]) }
        for f in flakes { Grow(&l, &tp, &r, &b, f[0], f[1]) }
        if w.Lead() === self && w.TicketCountdown() != nil { tp = Math.Min(tp, y - Double((P.TopRows + 16) * S)); l = Math.Min(l, Cx - 60 * k); r = Math.Max(r, Cx + 60 * k) }
        if P.Tubby || WearHat || HoldToast || P.Pik { tp = Math.Min(tp, y - Double((P.TopRows + (state == "juggle" || state == "hattoss" || state == "bagdig" ? 16 : 9)) * S)) }
        let pad = 6 + CInt(5 * k)
        let nb = Rectangle.FromLTRB(CInt(Math.Floor(l)) - pad, CInt(Math.Floor(tp)) - pad, CInt(Math.Ceiling(r)) + pad, CInt(Math.Ceiling(b)) + pad)
        if frameBmp == nil || frameBmp.Width != nb.Width || frameBmp.Height != nb.Height
        {
            if frameBmp != nil { frameBmp.Dispose() }
            frameBmp = Bitmap(Math.Max(1, nb.Width), Math.Max(1, nb.Height))
        }
        do
        {
            let g = Graphics.FromImage(frameBmp)
            g.Clear(Color.Transparent)
            PaintPet(g, nb.X, nb.Y)
            g.Dispose()
        }
        W.Present(Form, frameBmp, nb.X, nb.Y)
        if !W.Shown(Form) { Form.Show(); w.Zorder() }
        UpdateBubble()
    }

    func UpdateBubble()
    {
        EnsureForms()
        if Bt <= 0 || string.IsNullOrEmpty(bubble) || w.Hidden { if W.Shown(Bub) { Bub.Hide() }; return }
        let sz = Bub.Measure(bubble, bubbleAlert, Night ? P.NightBubble : 0, bubbleHint)
        var ancX: Double, above: Double
        if Out
        {
            ancX = Cx
            let dSH = Double(SH), dS = Double(S)
            var a = y + dSH - dSH * sc - Double(P.TopRows) * dS * sc
            a -= (state == "sleep" ? 30 * k : 0)
            a -= (hearts.Count > 0 ? 24 * k : 0)
            a -= ((Is("po") && OnScooter()) || RidingPo ? 4 * dS : 0)
            above = a
            if w.Lead() === self && w.TicketCountdown() != nil { above -= 11 * dS }   // 讓出搶票倒數徽章的位置
        }
        else
        {
            // 在櫃子裡：泡泡從格子上方冒出來
            var fxp = 0.0, fyp = 0.0; var ps = 0
            w.ShelfFoot(self, &fxp, &fyp, &ps)
            ancX = fxp; above = fyp - Double((17 + P.TopRows) * ps)
        }
        let wa = w.WA(ancX, above + 20)
        var bx = CInt(ancX - Double(sz.Width) / 2.0), by = CInt(above - Double(sz.Height) - 2)
        if Out && state == "hang" && hangPhase == 1 { by = CInt(y + Double(SH) + 6) }
        if Out && state == "ceil" { by = CInt(y + Double(SH) + 6) }
        bx = Math.Max(wa.Left, Math.Min(wa.Right - sz.Width, bx))
        by = Math.Max(wa.Top, Math.Min(wa.Bottom - sz.Height, by))
        let nb = Rectangle(bx, by, sz.Width, sz.Height)
        if Bub.Bounds != nb { Bub.Bounds = nb }
        if !W.Shown(Bub) { Bub.Show(); W.KeepOnTop(Bub) }
    }

    func PaintPet(_ g: Graphics, _ ox: Int, _ oy: Int)
    {
        g.SmoothingMode = SmoothingMode.AntiAlias
        let dox = Double(ox), doy = Double(oy), dS = Double(S), dSH = Double(SH), dSW = Double(SW)
        let lw = Math.Max(2, CInt(Math.Round(1.5 * k)))
        if SilkVisible()
        {
            var hx = Cx - dox, hy = y + 3 * k - doy, axo = ax - dox, ayo = ay - doy
            if state == "shoot"
            {
                let p = Math.Min(1.0, shootT / 0.18)
                axo = hx + (axo - hx) * p; ayo = hy + (ayo - hy) * p
            }
            if state == "sling" || state == "webcatch" { hy = y + 9 * k - doy; hx = Cx + Double(dir) * 5 * k - dox }
            let silk = Pen(Night ? Color.FromArgb(0x6A, 0x5F, 0x9E) : Color.FromArgb(0x9A, 0xA3, 0xBC), Double(lw))
            let core = Pen(Night ? Color.FromArgb(0x14, 0x14, 0x1C) : Color.FromArgb(0x4A, 0x52, 0x6E), Double(Math.Max(1, lw / 2)))
            g.DrawLine(silk, hx, hy, axo, ayo)
            g.DrawLine(core, hx, hy, axo, ayo)
            if state != "shoot" || shootT >= 0.18
            {
                let s = 5 * k, cxs = axo, cys = ayo
                g.DrawLine(silk, cxs - s, cys, cxs + s, cys)
                g.DrawLine(silk, cxs, cys - s, cxs, cys + s)
                g.DrawLine(silk, cxs - s * 0.7, cys - s * 0.7, cxs + s * 0.7, cys + s * 0.7)
                g.DrawLine(silk, cxs - s * 0.7, cys + s * 0.7, cxs + s * 0.7, cys - s * 0.7)
            }
        }

        let f = Frame()
        var sbx: Int, sby: Int, sps: Int
        if Math.Abs(sc - 1) > 0.001
        {
            sps = Math.Max(1, CInt(Math.Round(dS * sc)))
            let shake = knock > 0 ? -3 * k : 0
            sbx = CInt(Math.Round(Cx - 6 * Double(sps))) - ox; sby = CInt(Math.Round(y + dSH - 16 * Double(sps) + shake)) - oy
        }
        else { sps = S; sbx = CInt(Math.Round(x)) - ox; sby = CInt(Math.Round(y - Bob())) - oy }
        if state == "elvis" { sbx += (Step2(6) ? 1 : -1) * Math.Max(1, sps / 3) }
        let fx = dir < 0
        DrawFigure(g, f, sbx, sby, sps, fx, true)
        let dsps = Double(sps)

        // 原尺寸敲玻璃：手前面一圈小漣漪
        if state == "pose" && poseKind == "tap"
        {
            let ph = (anim * 1.6) % 1
            let rx = Cx - dox, ry = y + dSH * 0.45 - doy, rr = (4 + ph * 14) * k
            let rp = Pen(Color.FromArgb(CInt(170 * (1 - ph)), 255, 255, 255), Math.Max(1.5, k))
            let rp2 = Pen(Color.FromArgb(CInt(90 * (1 - ph)), 120, 150, 200), Math.Max(1.0, k * 0.6))
            g.DrawEllipse(rp2, rx - rr - 1, ry - rr * 0.6 - 1, 2 * rr + 2, rr * 1.2 + 2); g.DrawEllipse(rp, rx - rr, ry - rr * 0.6, 2 * rr, rr * 1.2)
        }
        // 第四面牆：小波臉貼玻璃起霧、史迪仔舔玻璃
        if state == "glass" && sc > 2
        {
            if HasTv
            {
                let fog = SolidBrush(Color.FromArgb(70, 255, 255, 255))
                let fo = (P.HeadTop + 1) * sps   // 小波 0；丁丁頭比較高
                g.FillEllipse(fog, sbx + 3 * sps, sby + 7 * sps + fo, 6 * sps, 3 * sps)
                g.FillEllipse(fog, sbx + 2 * sps, sby + 9 * sps + fo, 8 * sps, 3 * sps)
            }
            if Is("stitch") && gt > 0.8
            {
                let wet = SolidBrush(Color.FromArgb(55, 190, 225, 255))
                let lick = Math.Min(1.0, (gt - 0.8) / 1.2)
                g.FillEllipse(wet, Double(sbx + 3 * sps), Double(sby) + (8 - 6 * lick) * dsps, 5 * dsps, (3 + 6 * lick) * dsps)
            }
            if Is("hangyodon") && gt > 1.0
            {
                let lip = SolidBrush(Color.FromArgb(70, 245, 140, 170))   // 嘴唇印在玻璃上
                g.FillEllipse(lip, Double(sbx) + 1.5 * dsps, Double(sby) + 7.2 * dsps, 9 * dsps, 2.6 * dsps)
            }
        }

        // Codex／Claude 狀態小圖示（小波在肚子上，其他人在頭旁邊）
        if !HasTv && Math.Abs(sc - 1) < 0.001 && w.Lead() === self
        {
            let st = w.Status()
            if st != "" { DrawStatusIcon(g, st, CInt(x + dSW + 2 * dS) - ox, CInt(y - 1 * dS) - oy, Math.Max(1, S / 2), false) }
        }

        DrawTicketBadge(g, ox, oy)
        let fps = Math.Max(1, S / 3)
        for fl in flakes { DrawPix(g, Pet.FLAKE, CInt(fl[0]) - ox - fps, CInt(fl[1]) - oy - fps, fps, false, false, false) }

        if sense > 0 && !f.Fy
        {
            let p = Pen(Night ? Color.FromArgb(0x9B, 0x7B, 0xFF) : Color.FromArgb(0xC9, 0x54, 0x54), 2 * k)
            let cx = Cx - dox, cy = y + 10 * k - doy, wob = Math.Sin(anim * 30) * 1.5 * k
            for s in stride(from: -1, through: 1, by: 2)
            {
                let ds = Double(s)
                for i in 0..<3
                {
                    let di = Double(i)
                    let x1 = cx + ds * (22 + di * 5 + wob) * k, y1 = cy + (-10 + di * 6) * k
                    let x2 = cx + ds * (30 + di * 5 + wob) * k, y2 = cy + (-16 + di * 8) * k
                    g.DrawLine(p, x1, y1, x2, y2)
                }
            }
        }

        if state == "sleep"
        {
            let ps = Math.Max(2, S / 2)
            for i in 0..<3
            {
                let p = (z * 0.6 + Double(i) / 3.0) % 1
                if p > 0.85 { continue }
                DrawPix(g, Pet.ZZ, CInt(x + dSW - 4 * k + p * 16 * k) - ox, CInt(y - 2 * k - p * 30 * k) - oy, ps, false, false, false)
            }
        }

        let hp = Math.Max(2, S / 2)
        let dhp = Double(hp)
        for sp in sparks
        {
            if sp[4] < 0.6 || Math.Floor(sp[4] * 20) % 2 == 0
            { DrawPix(g, Pet.STAR, CInt(sp[0] - 1.5 * dhp) - ox, CInt(sp[1] - 1.5 * dhp) - oy, hp, false, false, false) }
        }
        for h in hearts
        {
            let age = h[1]
            let hx = CInt(Cx + h[0] + Math.Sin(age * 6 + h[0]) * 3 * k - 3.5 * dhp) - ox
            let hy = CInt(y - 8 * k - age * 45 * k - 6 * dhp) - oy
            DrawPix(g, Pet.HEART, hx, hy, hp, false, false, true)
        }
        for n in notes
        {
            let age = n[1]
            if n[2] == 7
            {
                // 史迪仔吃東西掉的屑屑
                let cb = SolidBrush(Color.FromArgb(0xC8, 0x93, 0x4E))
                g.FillRectangle(cb, (Cx + n[0]) - dox, (y + 9 * dS + age * 40 * k) - doy, Double(Math.Max(2, S / 2)), Double(Math.Max(2, S / 2)))
                continue
            }
            if n[2] == 5
            {
                let bxp = (Cx + n[0] * 1.6 + Math.Sin(age * 4 + n[0]) * 3 * k) - dox, byp = (y + 8 * k - age * 50 * k) - doy, rr = (1.6 + age * 1.2) * k
                if age < 1.5
                {
                    let bp = Pen(Color.FromArgb(200, 150, 215, 255), Math.Max(1.0, k * 0.9))
                    let hl = SolidBrush(Color.FromArgb(220, 255, 255, 255))
                    g.DrawEllipse(bp, bxp - rr, byp - rr, 2 * rr, 2 * rr); g.FillRectangle(hl, bxp - rr * 0.5, byp - rr * 0.6, Math.Max(1.0, rr * 0.4), Math.Max(1.0, rr * 0.4))
                }
                continue
            }
            let art = n[2] == 0 ? Pet.NOTE : (n[2] == 1 ? Pet.EXCL : (n[2] == 2 ? Pet.QUES : (n[2] == 3 ? Pet.ZZ : Pet.DROP)))
            let hx = CInt(Cx + n[0] + (n[2] == 0 ? Math.Sin(age * 5) * 6 * k : 0)) - ox
            let hy = CInt(y - 6 * k - age * (n[2] == 0 ? 40 : 18) * k) - oy
            if age < 1.5 || Math.Floor(age * 16) % 2 == 0 { DrawPix(g, art, hx, hy, hp, false, false, true) }
        }
    }

    // 畫一隻（身體＋前後道具＋配件＋肚子螢幕）；櫃子裡也用這個
    func DrawFigure(_ g: Graphics, _ f: Fr, _ sbx: Int, _ sby: Int, _ sps: Int, _ fx: Bool, _ extras: Bool)
    {
        // 圖一律貼齊 16 格框的底（比較高的角色往上長），Top 再額外上下移
        var rows = f.Rows
        var top = f.Top + 16 - rows.count
        var left = -(rows[0].utf8.count - 12) / 2
        if f.Rot != 0
        {
            rows = Pet.Rot90(rows, f.Rot)
            left = -(rows[0].utf8.count - 12) / 2
            top = (16 - rows.count) / 2 + 1
        }
        if extras { DrawBehind(g, f, sbx, sby, sps, fx) }
        DrawPix(g, rows, sbx + left * sps, sby + top * sps, sps, fx, f.Fy, true)
        if f.Acc && !f.Fy
        {
            let normalFace = state != "sleep" && state != "hug" && state != "dizzy"
            DrawAccessories(g, sbx, sby, sps, fx, f.AccDy, normalFace)
        }
        if f.Tummy && f.Rot == 0
        {
            let u = Math.Max(1, sps / 2)
            let scx = sbx + 6 * sps, scy = sby + CInt((P.TummyRow + Double(f.AccDy)) * Double(sps))
            DrawStatusIcon(g, TummyStatus(), scx, scy, u, true)
        }
        if extras { DrawFront(g, f, sbx, sby, sps, fx); DrawLunch(g, f, sbx, sby, sps, fx) }
    }
}

// ================= 公仔櫃 =================
// 右下角的木頭展示櫃：右邊一格高的（最愛）、左邊三格小的。點格子裡的公仔＝放出來／收回去。
final class ShelfForm: OverlayForm
{
    let w: World
    let U: Int, TU: Int           // 小格、高格的像素大小
    let k: Double
    var Hot = false, Over = false, Night = false
    var Tubby = false                   // 天線寶寶一櫃：格子裡是藍天綠山丘，大格有太陽寶寶
    //@@BODY ShelfForm
    var hover = -1
    var bmp: Bitmap! = nil, bg: Bitmap! = nil
    var bgKey = ""
    var area = Rectangle(0, 0, 0, 0)    // 螢幕座標
    var Area: Rectangle { return area }
    var cells = [Rectangle](repeating: Rectangle(0, 0, 0, 0), count: 4) // 本地座標（含名牌那條）
    var bW = 0, crown = 0, baseH = 0, div = 0, plateH = 0
    // ---- 收合成蛋 ----
    var Collapsed = false
    var fold = 0.0, gulp = 0.0, wobT = 0.0, nextWob = 4.0    // fold：0 櫃子 → 1 蛋
    var Attention = 0                     // 蛋上的小紅點（存著的通知、快到的提醒）
    var Lunch = false
    static let EGG = [
        "......kkkkkk......",
        ".....kccccssk.....",
        "....kchhYccssk....",
        "....khcYYYossk....",
        "...kchccYcccssk...",
        "...kccccccccssk...",
        "..kcccccccrrcssk..",
        "..kcccccccrrcssk..",
        "..kccccooccccssk..",
        ".kcccccoocccccssk.",
        ".kccbbccccccccssk.",
        ".kccbbcccccccossk.",
        ".kccccccccccccssk.",
        "..kcccccccggcssk..",
        "..kcccccccggcssk..",
        "..kcccrccccccssk..",
        "...kccccccccssk...",
        "...kccccccccssk...",
        "....kkkkkkkkkk...." ]
    var Animating: Bool { return (Collapsed ? fold < 1 : fold > 0) || gulp > 0 || wobT > 0 }
    var EggPs: Int { return TU }
    func EggLocal() -> Rectangle { let ps = EggPs; let ew = 18 * ps, eh = 19 * ps; return Rectangle(Area.Width - ew - 4, Area.Height - eh - 2, ew, eh) }
    func EggScreen() -> Rectangle { let r = EggLocal(); return Rectangle(r.X + Area.X, r.Y + Area.Y, r.Width, r.Height) }
    func TabLocal() -> Rectangle { let s = 5 * U; return Rectangle(Area.Width - s - 3 * U, 0, s, CInt(Double(crown) * 0.8)) }
    func Gulp() { gulp = 0.5; wobT = 0.7 }
    func SnapFold() { fold = Collapsed ? 1 : 0 }
    func Step(_ dt: Double)
    {
        let target: Double = Collapsed ? 1 : 0
        if fold < target { fold = Math.Min(target, fold + dt / 0.7) } else if fold > target { fold = Math.Max(target, fold - dt / 0.8) }
        if gulp > 0 { gulp -= dt }
        if wobT > 0 { wobT -= dt }
        if Collapsed && fold >= 1
        {
            nextWob -= dt
            if nextWob <= 0 { wobT = Attention > 0 ? 0.9 : 0.6; nextWob = Attention > 0 ? 2.5 : 6 + Random().NextDouble() * 6 }
        }
    }
    // 蛋的腳（公仔收進蛋裡的位置）
    func EggFoot() -> Point { let r = EggScreen(); return Point(r.X + r.Width / 2, r.Y + r.Height * 2 / 3) }

    // ---- 拖著蛋（或櫃頂）搬家：右下角擋到東西時可以移開；位置存在 shelfpos.txt（相對右下角的位移） ----
    var OffX = 0, OffY = 0
    var defX = 0, defY = 0
    var lastWa = Rectangle(0, 0, 0, 0)
    var dragArm = false, dragMoved = false
    var dragFrom = Point(0, 0)
    var dragOX = 0, dragOY = 0
    var PosFile: String { return Path.Combine(World.DataDir, "shelfpos.txt") }
    func LoadOffset()
    {
        guard File.Exists(PosFile), let txt = try? File.ReadAllText(PosFile) else { return }
        let a = txt.Trim().Split(" ")
        var x = 0, y = 0
        if a.count >= 2 && int.TryParse(a[0], &x) && int.TryParse(a[1], &y) { OffX = x; OffY = y }
    }
    func SaveOffset()
    {
        _ = try? Directory.CreateDirectory(World.DataDir)
        _ = try? File.WriteAllText(PosFile, String(OffX) + " " + String(OffY))
    }
    // 蛋或櫃頂（不是收合鈕、不是格子）可以拖
    func DragSpot(_ local: Point) -> Bool { return Collapsed ? EggLocal().Contains(local) : (local.Y < crown && !TabLocal().Contains(local)) }

    init(_ w: World, _ S: Int)
    {
        self.w = w
        U = Math.Max(2, S * 3 / 4); TU = S
        k = Double(S) / 3.0
        super.init(false, true)
        Cursor = Cursors.Hand
        LoadOffset()
    }

    override func OnPaint(_ e: PaintEventArgs) { }
    override func OnPaintBackground(_ e: PaintEventArgs) { }

    func Place(_ wa: Rectangle)
    {
        bW = 3 * U; crown = 5 * U; baseH = 5 * U; div = 2 * U; plateH = 5 * U
        let smallW = 24 * U, smallH = 33 * U, tallW = 24 * TU, tallH = 3 * smallH + 2 * div
        let W = bW * 2 + smallW + div + tallW, H = crown + tallH + baseH
        defX = wa.Right - W - 6; defY = wa.Bottom - H; lastWa = wa
        let ax = Math.Max(wa.Left, Math.Min(defX, defX + OffX)), ay = Math.Max(wa.Top, Math.Min(defY, defY + OffY))
        area = Rectangle(ax, ay, W, H)
        cells[0] = Rectangle(bW + smallW + div, crown, tallW, tallH)
        for i in 0..<3 { cells[i + 1] = Rectangle(bW, crown + i * (smallH + div), smallW, smallH) }
    }

    func CellPs(_ i: Int) -> Int { return i == 0 ? TU : U }
    // 依公仔實際高度（天線、耳朵、頭鰭、帽子、晃動）縮放，保證離格子頂端至少 2px
    func FitPs(_ i: Int, _ p: Pet?) -> Int
    {
        var ps = CellPs(i)
        guard let p = p else { return ps }
        let avail = cells[i].Height - plateH - U - (i == 0 ? PedH() : 0) - 2 - 2
        let rows = p.ShelfRows()
        while ps > 2 && rows * ps > avail { ps -= 1 }
        return ps
    }
    func CellScreen(_ i: Int) -> Rectangle { let c = cells[i]; return Rectangle(c.X + Area.X, c.Y + Area.Y, c.Width, c.Height) }
    // 公仔腳踩的位置（螢幕座標）
    func Foot(_ i: Int) -> Point { let c = CellScreen(i); return Point(c.X + c.Width / 2, c.Bottom - plateH - U - (i == 0 ? PedH() : 0)) }
    func PedH() -> Int { return CInt(Double(cells[0].Height - plateH) * 0.2) }

    func CellAt(_ screen: Point) -> Int
    {
        if Collapsed { return -1 }
        for i in 0..<4 { if CellScreen(i).Contains(screen) { return i } }
        return -1
    }

    override func OnMouseDown(_ e: MouseEventArgs)
    {
        super.OnMouseDown(e)
        if e.Button != MouseButtons.Left { return }
        let cp = ShelfForm.CursorPos()
        if DragSpot(Point(cp.X - Area.X, cp.Y - Area.Y)) { dragArm = true; dragMoved = false; dragFrom = cp; dragOX = OffX; dragOY = OffY; return }   // 放開時才決定是點還是拖
        ClickAt(cp, e.Button)
    }
    override func OnMouseUp(_ e: MouseEventArgs)
    {
        super.OnMouseUp(e)
        if e.Button == MouseButtons.Left && dragArm
        {
            dragArm = false
            if dragMoved { OffX = Area.X - defX; OffY = Area.Y - defY; SaveOffset() }   // 貼邊時存實際位置
            else { ClickAt(ShelfForm.CursorPos(), e.Button) }
            return
        }
        if e.Button == MouseButtons.Right { let cp = ShelfForm.CursorPos(); App.LogAlways("menu: right-up on shelf at {X=\(cp.X),Y=\(cp.Y)} collapsed=\(Collapsed ? "True" : "False")"); ClickAt(cp, e.Button) }   // 右鍵放開才叫選單
    }
    // mac: inside a Form, `Cursor` names the instance property; reach the static Cursor.Position here
    static func CursorPos() -> Point { return CursorT.Position }

    // 點櫃子（真的滑鼠或測試用 act click 都走這裡）
    func ClickAt(_ screen: Point, _ b: MouseButtons)
    {
        let p = Point(screen.X - Area.X, screen.Y - Area.Y)
        if Collapsed
        {
            if !EggLocal().Contains(p) { return }
            if b == MouseButtons.Left { if w.Single { w.EggClick() } else { w.ToggleEgg(false) } }
            else if b == MouseButtons.Right { w.HouseMenu() }   // 蛋＝公仔小屋：開關、設定
            return
        }
        if b == MouseButtons.Left && TabLocal().Contains(p) { w.ToggleEgg(true); return }
        let c = CellAt(screen)
        if c < 0 { return }
        if b == MouseButtons.Left { w.ShelfClick(c) }
        else if b == MouseButtons.Right { w.ShelfMenu(c, self) }
    }
    override func OnMouseMove(_ e: MouseEventArgs)
    {
        super.OnMouseMove(e)
        let cp = ShelfForm.CursorPos()
        if dragArm && (Control.MouseButtons.raw & MouseButtons.Left.raw) != 0
        {
            let dx = cp.X - dragFrom.X, dy = cp.Y - dragFrom.Y
            if !dragMoved && Math.Abs(dx) + Math.Abs(dy) > 4 { dragMoved = true }
            if dragMoved { OffX = dragOX + dx; OffY = dragOY + dy; Place(lastWa); w.RepaintShelf() }
            return
        }
        hover = CellAt(cp)
    }
    override func OnMouseLeave(_ e: EventArgs) { super.OnMouseLeave(e); hover = -1 }

    static func C(_ rgb: Int) -> Color { return Color.FromArgb((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255) }
    static func Mix(_ a: Color, _ b: Color, _ f: Double) -> Color
    {
        let r = CInt(Double(a.R) + Double(b.R - a.R) * f), gg = CInt(Double(a.G) + Double(b.G - a.G) * f), bb = CInt(Double(a.B) + Double(b.B - a.B) * f)
        return Color.FromArgb(r, gg, bb)
    }
    func C(_ rgb: Int) -> Color { return ShelfForm.C(rgb) }
    func Mix(_ a: Color, _ b: Color, _ f: Double) -> Color { return ShelfForm.Mix(a, b, f) }

    static func RoundRect(_ r: RectangleF, _ rad: Double) -> GraphicsPath
    {
        let p = GraphicsPath()
        let d = rad * 2
        p.AddArc(r.X, r.Y, d, d, 180, 90)
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90)
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90)
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90)
        p.CloseFigure()
        return p
    }
    func RoundRect(_ r: RectangleF, _ rad: Double) -> GraphicsPath { return ShelfForm.RoundRect(r, rad) }

    // 櫃子本體（不會動的部分）先畫好存起來
    func BuildBg(_ who: [Pet?], _ outNow: [Bool])
    {
        let W = Area.Width, H = Area.Height
        let dW = Double(W), dH = Double(H), dU = Double(U), dcrown = Double(crown), dplateH = Double(plateH)
        if bg == nil || bg.Width != W || bg.Height != H { if bg != nil { bg.Dispose() }; bg = Bitmap(W, H) }
        let g = Graphics.FromImage(bg)
        defer { g.Dispose() }
        g.Clear(Color.Transparent)
        g.SmoothingMode = SmoothingMode.AntiAlias
        let w1 = Night ? C(0x5C3B24) : C(0x9A6338), w2 = Night ? C(0x3C2617) : C(0x6B4024), w3 = Night ? C(0x74503A) : C(0xB97F4E)
        // 影子
        g.FillPath(SolidBrush(Color.FromArgb(60, 0, 0, 0)), RoundRect(RectangleF(3, 4, dW - 4, dH - 4), 5 * dU))
        // 櫃身
        let body = RectangleF(1, dcrown * 0.35, dW - 3, dH - dcrown * 0.35 - 2)
        g.FillPath(LinearGradientBrush(body, w1, w2, 90.0), RoundRect(body, 3 * dU))
        // 木紋
        let r = Random(5)
        do
        {
            let grain = Pen(Color.FromArgb(Night ? 26 : 34, 40, 20, 8), Math.Max(1.0, dU * 0.35))
            for _ in 0..<14
            {
                let gx = r.NextDouble() * dW, gy = dcrown + r.NextDouble() * (dH - dcrown * 2)
                g.DrawBezier(grain, gx, gy, gx + 6 * dU, gy - dU, gx + 12 * dU, gy + dU, gx + 18 * dU, gy)
            }
        }
        // 頂蓋（冠線）
        let top = RectangleF(0, 0, dW - 1, dcrown)
        g.FillPath(LinearGradientBrush(top, w3, w1, 90.0), RoundRect(top, 2 * dU))
        g.DrawLine(Pen(Color.FromArgb(Night ? 50 : 90, 255, 230, 200), Math.Max(1.0, dU * 0.5)), 3 * dU, dU, dW - 3 * dU, dU)
        g.DrawLine(Pen(Color.FromArgb(120, 30, 15, 5), Math.Max(1.0, dU * 0.5)), dU, dcrown - dU * 0.3, dW - dU, dcrown - dU * 0.3)
        // 底座＋小腳
        let bas = RectangleF(0, dH - Double(baseH) - 1, dW - 1, Double(baseH - U))
        g.FillPath(LinearGradientBrush(bas, w3, w2, 90.0), RoundRect(bas, 1.5 * dU))
        do
        {
            let ft = SolidBrush(w2)
            g.FillRectangle(ft, 3 * U, H - 2 * U, 4 * U, 2 * U)
            g.FillRectangle(ft, W - 7 * U, H - 2 * U, 4 * U, 2 * U)
        }
        // 每一格
        for i in 0..<4
        {
            let c = cells[i]
            let pet = who[i]
            var panel = pet != nil ? pet!.P.Panel : C(0xEDE6DA)
            if Night { panel = Mix(panel, C(0x2A2238), 0.55) }
            let inner = RectangleF(Double(c.X), Double(c.Y), Double(c.Width), Double(c.Height - plateH))
            g.FillRectangle(LinearGradientBrush(inner, Mix(panel, Color.White, 0.35), Mix(panel, C(0x6B4A30), 0.25), 90.0), inner)
            if Tubby { DrawHills(g, inner, i == 0) }
            if Pik { DrawSoil(g, inner, i == 0) }
            // 頂上的展示燈
            do
            {
                let gp = GraphicsPath()
                let glow = RectangleF(inner.X - inner.Width * 0.2, inner.Y - inner.Height * 0.25, inner.Width * 1.4, inner.Height * 0.75)
                gp.AddEllipse(glow)
                let pg = PathGradientBrush(gp)
                pg.CenterColor = Night ? Color.FromArgb(120, 255, 214, 150) : Color.FromArgb(110, 255, 250, 235)
                pg.SurroundColors = [ Color.FromArgb(0, 255, 240, 220) ]
                g.SetClip(inner)
                g.FillPath(pg, gp)
                g.ResetClip()
            }
            // 內側陰影（凹進去的感覺）
            g.FillRectangle(LinearGradientBrush(RectangleF(inner.X, inner.Y, inner.Width, 3 * dU + 1), Color.FromArgb(90, 40, 20, 5), Color.FromArgb(0, 40, 20, 5), 90.0), inner.X, inner.Y, inner.Width, 3 * dU)
            g.FillRectangle(LinearGradientBrush(RectangleF(inner.X, inner.Y, 2 * dU + 1, inner.Height), Color.FromArgb(70, 40, 20, 5), Color.FromArgb(0, 40, 20, 5), 0.0), inner.X, inner.Y, 2 * dU, inner.Height)
            if i == 0 && Pik { DrawFlowerBed(g, c) }
            else if i == 0 { DrawPedestal(g, c, panel) }
            // 層板（公仔站的地方）＋名牌那條
            let board = RectangleF(Double(c.X - U), Double(c.Bottom - plateH), Double(c.Width + 2 * U), dplateH)
            g.FillRectangle(LinearGradientBrush(board, w3, w1, 90.0), board)
            g.DrawLine(Pen(Color.FromArgb(Night ? 60 : 110, 255, 235, 205), Math.Max(1.0, dU * 0.4)), board.X, board.Y + 0.5, board.Right, board.Y + 0.5)
            // 名牌
            let name = pet == nil ? (i == 0 && Pik ? "★ 休息花" : "？") : (i == 0 ? "★ " + pet!.P.Name : pet!.P.Name)
            do
            {
                let f = Font("Microsoft JhengHei UI", Math.Max(9.0, 6.6 * k), FontStyle.Bold, GraphicsUnit.Pixel)
                let ts = g.MeasureString(name, f)
                let pw = Math.Min(Double(c.Width) - 2 * dU, ts.Width + 3 * dU), ph = dplateH - 1.6 * dU
                let pr = RectangleF(Double(c.X) + (Double(c.Width) - pw) / 2, Double(c.Bottom - plateH) + 0.9 * dU, pw, ph)
                let pp = RoundRect(pr, dU * 0.8)
                let brass = LinearGradientBrush(pr, i == 0 ? C(0xF6D77A) : C(0xEBCB7E), i == 0 ? C(0xC08A2C) : C(0xB48A45), 90.0)
                let rim = Pen(Color.FromArgb(160, 90, 60, 15), 1.0)
                g.FillPath(brass, pp)
                g.DrawPath(rim, pp)
                g.TextRenderingHint = TextRenderingHint.AntiAlias
                let sf = StringFormat()
                let tb = SolidBrush(C(0x4A3010))
                sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center; sf.Trimming = StringTrimming.None
                g.DrawString(name, f, tb, RectangleF(pr.X - 4, pr.Y + 0.5, pr.Width + 8, pr.Height), sf)
            }
        }
        // 左右小格和高格之間的隔板線
        let dk = Pen(Color.FromArgb(90, 30, 15, 5), 1.0)
        g.DrawLine(dk, Double(cells[0].X) - Double(div) / 2, dcrown, Double(cells[0].X) - Double(div) / 2, Double(H - baseH))
    }


    // ---- 天線寶寶一櫃的格子：藍天、綠色小山丘、小花；大格有太陽寶寶（晚上下山）----
    func HillTop(_ inner: RectangleF, _ tall: Bool) -> Double { return inner.Bottom - inner.Height * (tall ? 0.30 : 0.27) }
    func DrawHills(_ g: Graphics, _ inner: RectangleF, _ tall: Bool)
    {
        let st = g.Save()
        g.SetClip(inner)
        let sky1 = Night ? C(0x4A3A6A) : C(0xB8E0FF), sky2 = Night ? C(0xA8707A) : C(0xEEF8FF)
        g.FillRectangle(LinearGradientBrush(inner, sky1, sky2, 90.0), inner)
        let hy = HillTop(inner, tall)
        let h1 = Night ? C(0x557E4C) : C(0x92D46C), h2 = Night ? C(0x3A5C36) : C(0x66B248), rim = Night ? C(0x74A066) : C(0xC0EC98)
        // 後面一座淡淡的
        g.FillEllipse(SolidBrush(Mix(h1, sky2, 0.5)), inner.X - inner.Width * 0.55, hy - inner.Height * 0.07, inner.Width * 1.25, inner.Height * 0.5)
        let hill = RectangleF(inner.X - inner.Width * 0.25, hy, inner.Width * 1.5, inner.Height * 0.62)
        g.FillEllipse(LinearGradientBrush(RectangleF(hill.X, hill.Y - 1, hill.Width, hill.Height + 2), h1, h2, 90.0), hill)
        g.DrawArc(Pen(rim, Math.Max(1.0, Double(U) * 0.5)), hill, 215, 110)
        // 小花（像素點）
        let r = Random(tall ? 3 : 11)
        let fl = [ Color.White, C(0xFFD84A), C(0xFF8FB0), C(0xE8E0FF) ]
        let u = Math.Max(1.0, Double(U) * 0.6), a = hill.Width / 2, bb = hill.Height / 2, cxh = hill.X + a, cyh = hill.Y + bb
        let n = tall ? 7 : 4
        for i in 0..<n
        {
            let fx = inner.X + (0.08 + 0.84 * (Double(i) + r.NextDouble() * 0.8) / Double(n)) * inner.Width
            let q = (fx - cxh) / a; if Math.Abs(q) >= 1 { continue }
            let top = cyh - bb * Math.Sqrt(1 - q * q)
            let fy = top + (0.25 + r.NextDouble() * 0.55) * (inner.Bottom - top)
            let c0 = fl[r.Next(fl.count)]
            let pb = SolidBrush(Night ? Mix(c0, C(0x3A3050), 0.45) : c0)
            g.FillRectangle(pb, fx - u, fy, u, u); g.FillRectangle(pb, fx + u, fy, u, u)
            g.FillRectangle(pb, fx, fy - u, u, u); g.FillRectangle(pb, fx, fy + u, u, u)
            g.FillRectangle(SolidBrush(Night ? C(0xB08A3C) : C(0xF5A623)), fx, fy, u, u)
        }
        g.Restore(st)
    }

    // 太陽寶寶：白天在天上笑，晚上一半沉到山丘後面
    func DrawSunBaby(_ g: Graphics, _ c: Rectangle, _ cx0: Double, _ sy: Double, _ sr: Double)
    {
        var cx = cx0
        let inner = RectangleF(Double(c.X), Double(c.Y), Double(c.Width), Double(c.Height - plateH))
        let hy = HillTop(inner, true)
        let r = sr * 0.5, y0 = Night ? hy - r * 0.15 : sy
        if Night { cx -= Double(c.Width) * 0.24 }   // 晚上在山丘邊慢慢下山（不要躲在圓台後面）
        let st = g.Save()
        g.SetClip(RectangleF(inner.X, inner.Y, inner.Width, hy + 1 - inner.Y))
        let ray = Night ? Color.FromArgb(150, 255, 150, 90) : Color.FromArgb(170, 255, 214, 74)
        let rp = Pen(ray, Math.Max(1.5, Double(U) * 0.9))
        for i in 0..<12
        {
            let ang = Double(i) * Math.PI / 6 + 0.13
            g.DrawLine(rp, cx + Math.Cos(ang) * r * 1.25, y0 + Math.Sin(ang) * r * 1.25, cx + Math.Cos(ang) * r * 1.65, y0 + Math.Sin(ang) * r * 1.65)
        }
        g.FillEllipse(SolidBrush(Night ? C(0xF0965A) : C(0xFFD84A)), cx - r, y0 - r, 2 * r, 2 * r)
        let fr = r * 0.66
        g.FillEllipse(SolidBrush(Night ? C(0xE8B892) : C(0xFBE3C6)), cx - fr, y0 - fr, 2 * fr, 2 * fr)
        let e = Math.Max(1.5, fr * 0.16)
        let kb = SolidBrush(C(0x5A3A2A))
        if Night
        {
            let sp = Pen(C(0x5A3A2A), Math.Max(1.0, e * 0.6))
            g.DrawLine(sp, cx - fr * 0.5, y0 - fr * 0.15, cx - fr * 0.2, y0 - fr * 0.15); g.DrawLine(sp, cx + fr * 0.2, y0 - fr * 0.15, cx + fr * 0.5, y0 - fr * 0.15)
        }
        else { g.FillEllipse(kb, cx - fr * 0.42 - e / 2, y0 - fr * 0.25, e, e * 1.2); g.FillEllipse(kb, cx + fr * 0.42 - e / 2, y0 - fr * 0.25, e, e * 1.2) }
        g.DrawArc(Pen(C(0xC0504A), Math.Max(1.0, e * 0.6)), cx - fr * 0.35, y0 - fr * 0.05, fr * 0.7, fr * 0.55, 20.0, 140.0)
        let pk = SolidBrush(Color.FromArgb(110, 255, 130, 130))
        g.FillEllipse(pk, cx - fr * 0.78, y0 + fr * 0.1, fr * 0.3, fr * 0.2); g.FillEllipse(pk, cx + fr * 0.48, y0 + fr * 0.1, fr * 0.3, fr * 0.2)
        g.Restore(st)
    }

    // 高格：最愛站的小圓台＋背板上淡淡的大星星
    func DrawPedestal(_ g: Graphics, _ c: Rectangle, _ panel: Color)
    {
        let dU = Double(U)
        let cx = Double(c.X) + Double(c.Width) / 2, ph = Double(PedH()), floor = Double(c.Bottom - plateH), top = floor - ph
        let pw = Double(c.Width) * 0.62, eh = 4 * dU
        // 星星
        var star = [PointF]()
        let sr = Double(c.Width) * 0.36, sy = Double(c.Y) + (top - Double(c.Y)) * 0.42
        for i in 0..<10
        {
            let a = -Math.PI / 2 + Double(i) * Math.PI / 5, rr = i % 2 == 0 ? sr : sr * 0.45
            star.append(PointF(cx + Math.Cos(a) * rr, sy + Math.Sin(a) * rr))
        }
        if Tubby { DrawSunBaby(g, c, cx, sy, sr) }
        else
        { g.FillPolygon(SolidBrush(Night ? Color.FromArgb(40, 255, 220, 150) : Color.FromArgb(70, 255, 236, 180)), star) }
        // 圓台
        let m1 = Night ? C(0x8A7A70) : C(0xFFF6E8), m2 = Night ? C(0x4E443F) : C(0xD9C7AE)
        let bodyR = RectangleF(cx - pw / 2, top, pw, ph - dU * 0.5)
        do
        {
            let lb = LinearGradientBrush(RectangleF(bodyR.X - 1, bodyR.Y, bodyR.Width + 2, bodyR.Height), m2, m1, 0.0)
            let cb = ColorBlend()
            cb.Colors = [ m2, m1, m1, m2 ]
            cb.Positions = [ 0.0, 0.35, 0.55, 1.0 ]
            lb.InterpolationColors = cb
            g.FillRectangle(lb, bodyR)
            g.FillEllipse(lb, bodyR.X, bodyR.Bottom - eh / 2, bodyR.Width, eh)
        }
        g.FillRectangle(SolidBrush(Night ? C(0xB08A3C) : C(0xE2B550)), bodyR.X, top + eh * 0.45, bodyR.Width, dU * 0.9)
        g.FillEllipse(SolidBrush(Night ? C(0x9C8B80) : C(0xFFFBF3)), bodyR.X, top - eh / 2, bodyR.Width, eh)
        g.DrawEllipse(Pen(Night ? C(0xB08A3C) : C(0xD9A944), Math.Max(1.0, dU * 0.5)), bodyR.X, top - eh / 2, bodyR.Width, eh)
    }

    // 每 0.1 秒左右重畫（公仔會呼吸、眨眼、晃一下）
    func Render(_ who: [Pet?], _ outNow: [Bool], _ t: Double)
    {
        let b = Snapshot(who, outNow, t)
        W.Present(self, b, Area.X, Area.Y)
    }

    var cab: Bitmap! = nil
    @discardableResult
    func Snapshot(_ who: [Pet?], _ outNow: [Bool], _ t: Double) -> Bitmap
    {
        if fold <= 0.001 { let b0 = Cabinet(who, outNow, t); DrawTab(b0); return b0 }
        let full = Cabinet(who, outNow, t)
        if cab == nil || cab.Width != full.Width || cab.Height != full.Height { if cab != nil { cab.Dispose() }; cab = Bitmap(full.Width, full.Height) }
        let g = Graphics.FromImage(cab)
        defer { g.Dispose() }
        g.Clear(Color.Transparent)
        let e = fold * fold * (3 - 2 * fold)
        // 櫃子往下折、變淡
        if e < 0.999
        {
            let h = CInt(Math.Round(Double(full.Height) * (1 - e)))
            if h > 0
            {
                let cm = ColorMatrix(); cm.Matrix33 = 1 - e
                let ia = ImageAttributes()
                ia.SetColorMatrix(cm)
                g.InterpolationMode = InterpolationMode.NearestNeighbor
                g.DrawImage(full, Rectangle(0, full.Height - h, full.Width, h), 0, 0, full.Width, full.Height, GraphicsUnit.Pixel, ia)
            }
        }
        // 蛋：慢慢出現、上半部蓋下來
        DrawEgg(g, t, e)
        return cab
    }

    // 收合鈕「－」（櫃子頂上右邊的小牌子）
    func DrawTab(_ b: Bitmap)
    {
        let g = Graphics.FromImage(b)
        defer { g.Dispose() }
        g.SmoothingMode = SmoothingMode.AntiAlias
        let r = TabLocal()
        let p = RoundRect(RectangleF(Double(r.X), Double(r.Y + 1), Double(r.Width), Double(r.Height - 2)), Double(U))
        g.FillPath(SolidBrush(Color.FromArgb(220, 255, 246, 226)), p); g.DrawPath(Pen(Color.FromArgb(160, 120, 80, 40), 1.0), p)
        let mp = Pen(Color.FromArgb(0x8A, 0x5A, 0x2A), Math.Max(1.5, Double(U) * 0.6))
        g.DrawLine(mp, Double(r.X) + Double(r.Width) * 0.28, Double(r.Y) + Double(r.Height) / 2, Double(r.X) + Double(r.Width) * 0.72, Double(r.Y) + Double(r.Height) / 2)
    }

    func DrawEgg(_ g: Graphics, _ t: Double, _ appear: Double)
    {
        if appear <= 0.02 { return }
        let ps = EggPs
        let dps = Double(ps), dU = Double(U)
        let er = EggLocal()
        // 搖一搖（有通知存著時搖比較大）
        var ang = 0.0
        if wobT > 0 { ang = Math.Sin(wobT * 26) * Double(Attention > 0 ? 11 : 6) * Math.Min(1.0, wobT * 2) }
        // 打開的程度：收合動畫的頭尾、吞公仔時裂開
        var open = Math.Max(Math.Max(0.0, 1 - appear) * 1.6, gulp > 0 ? Math.Sin(gulp / 0.5 * Math.PI) * 0.6 : 0)
        open = Math.Min(1.0, open)
        let st = g.Save()
        g.TranslateTransform(Double(er.X) + Double(er.Width) / 2, Double(er.Bottom))
        g.RotateTransform(ang)
        g.TranslateTransform(-Double(er.Width) / 2, -Double(er.Height))
        let crack = 8
        var pal = [Character: Color]()
        pal["k"] = Color.FromArgb(0x6B, 0x4A, 0x2E); pal["c"] = Night ? Color.FromArgb(0xE6, 0xDA, 0xC4) : Color.FromArgb(0xFF, 0xF4, 0xDC)
        pal["s"] = Night ? Color.FromArgb(0xC2, 0xAE, 0x92) : Color.FromArgb(0xE8, 0xD3, 0xB0); pal["h"] = Color.White
        pal["r"] = Color.FromArgb(0xD8, 0x4A, 0x4A); pal["o"] = Color.FromArgb(0xE7, 0x83, 0x6A); pal["b"] = Color.FromArgb(0x3D, 0x6B, 0xB3)
        pal["g"] = Color.FromArgb(0x25, 0xB3, 0xBA); pal["Y"] = Color.FromArgb(0xF5, 0xC8, 0x42)
        let alpha = CInt(255 * Math.Min(1.0, appear * 1.4))
        // 下半部
        for r in crack..<ShelfForm.EGG.count { DrawEggRow(g, r, 0, 0, ps, pal, alpha) }
        // 上半部：打開時往上抬、往旁邊歪
        let lift = open * 7 * dps, tilt = open * 4 * dps
        for r in 0..<crack { DrawEggRow(g, r, -tilt, -lift, ps, pal, alpha) }
        // 裂痕
        if open > 0.05 || appear < 0.95
        {
            let cp = Pen(Color.FromArgb(alpha, 0x6B, 0x4A, 0x2E), Math.Max(1.5, dps * 0.45))
            var z = [PointF]()
            for i in 0..<8 { z.append(PointF(Double(2 * ps + i * 2 * ps), (Double(crack) + (i % 2 == 0 ? 0 : 0.7)) * dps)) }
            g.DrawLines(cp, z)
        }
        // 午餐時間：小餐巾
        if Lunch
        {
            let nb = SolidBrush(Color.FromArgb(alpha, 255, 255, 255))
            let ck = SolidBrush(Color.FromArgb(alpha, 0xE2, 0x4A, 0x4A))
            let tri = [ PointF(5 * dps, 9 * dps), PointF(13 * dps, 9 * dps), PointF(9 * dps, 14 * dps) ]
            g.FillPolygon(nb, tri)
            g.DrawPolygon(Pen(Color.FromArgb(alpha, 0xB8, 0xA8, 0x90), Math.Max(1.0, dps * 0.3)), tri)
            for i in 0..<4 { g.FillRectangle(ck, (6 + i * 2) * ps, 9 * ps, ps, ps) }
            g.FillRectangle(ck, 8 * ps, 11 * ps, ps, ps); g.FillRectangle(ck, 10 * ps, 11 * ps, ps, ps)
        }
        g.Restore(st)
        // 小紅點：有存著的通知／快到的提醒
        if Attention > 0 && appear > 0.9
        {
            let d = 6 * dU, bx = Double(er.Right) - d * 0.8, by = Double(er.Y) + d * 0.2
            g.FillEllipse(SolidBrush(Color.FromArgb(0xE2, 0x3B, 0x3B)), bx, by, d, d)
            g.DrawEllipse(Pen(Color.White, 1.5), bx, by, d, d)
            let f = Font("Arial", d * 0.62, FontStyle.Bold, GraphicsUnit.Pixel)
            let sf = StringFormat()
            sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center
            g.TextRenderingHint = TextRenderingHint.AntiAlias
            g.DrawString(Attention > 9 ? "9+" : String(Attention), f, Brushes.White, RectangleF(bx, by + 0.5, d, d), sf)
        }
        if Hot && appear > 0.9
        {
            let hp = Pen(Over ? Color.FromArgb(230, 255, 120, 165) : Color.FromArgb(170, 255, 200, 120), Math.Max(2.0, dU))
            g.DrawEllipse(hp, Double(er.X - 2 * U), Double(er.Y - 2 * U), Double(er.Width + 4 * U), Double(er.Height + 4 * U))
        }
        // 番茄／安靜徽章掛在蛋上面
        let left = w.FocusLeft(), qleft = w.QuietLeft()
        let bcx = Double(er.X) + Double(er.Width) / 2, bcy = Double(er.Y) - 3 * dU
        if left >= 0 && qleft >= 0 { DrawBadgeAt(g, qleft, true, bcx, bcy); DrawBadgeAt(g, left, false, bcx, bcy - 8 * dU) }
        else if left >= 0 { DrawBadgeAt(g, left, false, bcx, bcy) }
        else if qleft >= 0 { DrawBadgeAt(g, qleft, true, bcx, bcy) }
    }

    func DrawEggRow(_ g: Graphics, _ r: Int, _ dx: Double, _ dy: Double, _ ps: Int, _ pal: [Character: Color], _ alpha: Int)
    {
        let row = ShelfForm.EGG[r]
        let dps = Double(ps)
        let b = SolidBrush(Color.White)
        var c = 0
        for ch in row
        {
            if ch != "."
            {
                let col = pal[ch]!
                b.Color = Color.FromArgb(alpha, col)
                g.FillRectangle(b, dx + Double(c) * dps, dy + Double(r) * dps, dps, dps)
            }
            c += 1
        }
    }

    func Cabinet(_ who: [Pet?], _ outNow: [Bool], _ t: Double) -> Bitmap
    {
        var key = "\(Night)|\(Tubby)|\(Pik)|\(Area.Width)x\(Area.Height)"
        for i in 0..<4 { key += "|" + (who[i] == nil ? "-" : who[i]!.P.Id) }
        if key != bgKey || bg == nil { bgKey = key; BuildBg(who, outNow) }
        if bmp == nil || bmp.Width != bg.Width || bmp.Height != bg.Height { if bmp != nil { bmp.Dispose() }; bmp = Bitmap(bg.Width, bg.Height) }
        let g = Graphics.FromImage(bmp)
        defer { g.Dispose() }
        let dU = Double(U)
        g.Clear(Color.Transparent)
        g.DrawImageUnscaled(bg, 0, 0)
        g.SmoothingMode = SmoothingMode.AntiAlias
        for i in 0..<4
        {
            let c = cells[i]
            let pet = who[i]
            let ps = FitPs(i, pet)
            let fx = c.X + c.Width / 2, fy = c.Bottom - plateH - U - (i == 0 ? PedH() : 0)
            g.SetClip(Rectangle(c.X, c.Y, c.Width, c.Height - plateH))
            if pet == nil && i == 0 && Pik { DrawRestFlower(g, c, t) }
            else if pet == nil { DrawUnknown(g, fx, fy, ps) }
            else if outNow[i] { pet!.DrawGhost(g, fx, fy, ps, Night); DrawAway(g, c, ps) }
            else { pet!.DrawOnShelf(g, fx, fy, ps, c, t) }
            g.ResetClip()
            if hover == i && pet != nil
            {
                let hp = Pen(Color.FromArgb(150, 255, 236, 160), Math.Max(2.0, dU * 0.7))
                g.DrawRectangle(hp, c.X + 1, c.Y + 1, c.Width - 3, c.Height - plateH - 2)
            }
        }
        // 玻璃門的反光
        do
        {
            let gl = Pen(Color.FromArgb(Night ? 14 : 26, 255, 255, 255), 3 * dU)
            for i in 0..<4
            {
                let c = cells[i]
                g.SetClip(Rectangle(c.X, c.Y, c.Width, c.Height - plateH))
                g.DrawLine(gl, Double(c.X) + Double(c.Width) * 0.15, Double(c.Bottom), Double(c.X) + Double(c.Width) * 0.95, Double(c.Y) - Double(c.Width) * 0.2)
                g.ResetClip()
            }
        }
        let left = w.FocusLeft(), qleft = w.QuietLeft()
        if left >= 0 && qleft >= 0 { DrawBadge(g, left, false, -1); DrawBadge(g, qleft, true, 1) }
        else if left >= 0 { DrawBadge(g, left, false, 0) }
        else if qleft >= 0 { DrawBadge(g, qleft, true, 0) }
        if Hot
        {
            let hp = Pen(Over ? Color.FromArgb(230, 255, 120, 165) : Color.FromArgb(170, 255, 200, 120), Math.Max(2.0, dU))
            let p = RoundRect(RectangleF(dU * 0.5, dU * 0.5, Double(Area.Width - U - 2), Double(Area.Height - U - 2)), 3 * dU)
            g.DrawPath(hp, p)
        }
        return bmp
    }

    func DrawBadge(_ g: Graphics, _ left: Int, _ quiet: Bool, _ side: Int)
    {
        let cxb = side == 0 ? Double(Area.Width) / 2 : (side < 0 ? Double(Area.Width) * 0.28 : Double(Area.Width) * 0.72)
        DrawBadgeAt(g, left, quiet, cxb, Double(crown) * 0.5)
    }

    static let TOM_QUIET = [ "..yyy...", ".yy..zzz", "yy....z.", "yy...zzz", "yy......", ".yy.....", "..yyy...", "........" ]
    static let TOM_FOCUS = [ "...gg...", "..gggg..", ".rrrrrr.", "rrhrrrrr", "rhrrrrrr", "rrrrrrrr", ".rrrrrr.", "..rrrr.." ]
    // 小徽章：番茄（專注）或月亮＋zz（安靜）＋剩幾分鐘，中心在 (cxb, cyb)
    func DrawBadgeAt(_ g: Graphics, _ left: Int, _ quiet: Bool, _ cxb: Double, _ cyb: Double)
    {
        let tom = quiet ? ShelfForm.TOM_QUIET : ShelfForm.TOM_FOCUS
        let ps = Math.Max(2, U * 2 / 3)
        let dps = Double(ps), dU = Double(U)
        let txt = String(left) + " 分"
        let f = Font("Microsoft JhengHei UI", Math.Max(10.0, 7.5 * k), FontStyle.Bold, GraphicsUnit.Pixel)
        let ts = g.MeasureString(txt, f)
        let bw = 8 * dps + ts.Width + 3 * dU, bh = Math.Max(8 * dps, ts.Height) + dU
        let br = RectangleF(cxb - bw / 2, cyb - bh / 2, bw, bh)
        let p = RoundRect(br, bh / 2)
        g.FillPath(SolidBrush(quiet ? Color.FromArgb(235, 44, 48, 78) : Color.FromArgb(235, 255, 248, 236)), p)
        g.DrawPath(Pen(quiet ? Color.FromArgb(180, 150, 160, 230) : Color.FromArgb(180, 200, 80, 60), 1.0), p)
        let b = SolidBrush(Color.White)
        for r in 0..<8
        {
            var c = 0
            for ch in tom[r]
            {
                if ch != "."
                {
                    b.Color = ch == "g" ? Color.FromArgb(0x3C, 0xA0, 0x48) : (ch == "h" ? Color.FromArgb(0xFF, 0x9A, 0x8A) : (ch == "y" ? Color.FromArgb(0xFF, 0xDB, 0x6E) : (ch == "z" ? Color.FromArgb(0xC8, 0xD0, 0xFF) : Color.FromArgb(0xE2, 0x3B, 0x2E))))
                    g.FillRectangle(b, br.X + dU + Double(c) * dps, br.Y + (bh - 8 * dps) / 2 + Double(r) * dps, dps, dps)
                }
                c += 1
            }
        }
        g.DrawString(txt, f, SolidBrush(quiet ? Color.FromArgb(0xE6, 0xE8, 0xFF) : Color.FromArgb(0x8A, 0x2A, 0x1E)), br.X + dU * 1.5 + 8 * dps, br.Y + (bh - ts.Height) / 2)
    }

    static let SIL = [ "...kkkkkk...", "..kkkkkkkk..", ".kkkkkkkkkk.", ".kkkkkkkkkk.", ".kkkkkkkkkk.", ".kkkkkkkkkk.", "..kkkkkkkk..", "...kkkkkk...",
        "...kkkkkk...", "..kkkkkkkk..", ".kkkkkkkkkk.", ".kkkkkkkkkk.", "..kkkkkkkk..", "..kkk..kkk..", "..kkk..kkk..", "..kkk..kkk.." ]
    // 空格：淡淡的問號剪影
    func DrawUnknown(_ g: Graphics, _ fx: Int, _ fy: Int, _ ps: Int)
    {
        let b = SolidBrush(Color.FromArgb(Night ? 40 : 34, 60, 40, 20))
        for r in 0..<16
        {
            var c = 0
            for ch in ShelfForm.SIL[r].utf8
            {
                if ch != 46 { g.FillRectangle(b, fx - 6 * ps + c * ps, fy - 16 * ps + r * ps, ps, ps) }
                c += 1
            }
        }
        let f = Font("Arial", Double(7 * ps), FontStyle.Bold, GraphicsUnit.Pixel)
        let b2 = SolidBrush(Color.FromArgb(Night ? 70 : 80, 255, 255, 255))
        let sf = StringFormat()
        sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center
        g.DrawString("?", f, b2, RectangleF(Double(fx - 6 * ps), Double(fy - 16 * ps), Double(12 * ps), Double(9 * ps)), sf)
    }

    // 外出中：空的展示台＋掛著的小牌子
    func DrawAway(_ g: Graphics, _ c: Rectangle, _ ps: Int)
    {
        let fx = c.X + c.Width / 2, fy = c.Bottom - plateH - U
        let dps = Double(ps), dU = Double(U), dfx = Double(fx)
        g.FillEllipse(SolidBrush(Color.FromArgb(70, 80, 50, 25)), fx - 5 * ps, fy - ps, 10 * ps, 2 * ps)
        let tagW = Math.Max(13 * dps * 0.9, 15 * dU), tagH = Math.Max(4.6 * dps, 5.2 * dU), ty = Double(c.Y) + Double(c.Height) * 0.32
        let str = Pen(Color.FromArgb(150, 110, 80, 50), 1.0)
        g.DrawLine(str, dfx - tagW * 0.3, Double(c.Y + 2), dfx - tagW * 0.25, ty)
        g.DrawLine(str, dfx + tagW * 0.3, Double(c.Y + 2), dfx + tagW * 0.25, ty)
        let tr = RectangleF(dfx - tagW / 2, ty, tagW, tagH)
        let p = RoundRect(tr, dps)
        g.FillPath(SolidBrush(Night ? Color.FromArgb(235, 70, 58, 80) : Color.FromArgb(240, 255, 250, 238)), p)
        g.DrawPath(Pen(Color.FromArgb(160, 150, 110, 70), 1.0), p)
        let f = Font("Microsoft JhengHei UI", Math.Max(10.0, 2.7 * dps), FontStyle.Bold, GraphicsUnit.Pixel)
        let tb = SolidBrush(Night ? Color.FromArgb(0xFF, 0xE6, 0xC8) : Color.FromArgb(0x8A, 0x5A, 0x2A))
        let sf = StringFormat()
        sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center
        g.TextRenderingHint = TextRenderingHint.AntiAlias
        g.DrawString("外出中", f, tb, RectangleF(tr.X - 6, tr.Y, tr.Width + 12, tr.Height), sf)
    }
}

extension Pet
{
    var ShelfSeed: Int { return P.Id.utf8.count * 7 + Int(P.Id.utf8.first ?? 0) }

    // 在櫃子格子裡：小小地動（呼吸、眨眼、各自的招牌小動作）
    func DrawOnShelf(_ g: Graphics, _ fx: Int, _ fy: Int, _ ps: Int, _ cell: Rectangle, _ t: Double)
    {
        let tt = t + Double(ShelfSeed) * 0.37
        let blink = (tt % 4.3) < 0.14
        let breathe = (tt * 0.8 % 1) < 0.5 ? 0 : 1
        let bx = fx - 6 * ps, by = fy - 16 * ps + breathe
        let flip = (Math.Floor(tt / 9) % 2) == 1
        let dps = Double(ps)
        var head = A("HEAD")
        switch P.Id
        {
            case "spidey":
                // 從格子頂端垂一條絲倒吊著晃；偶爾跳下來擺個噴絲姿勢
                let dangle = (tt % 11) < 8
                if blink { ReplaceFace(&head, "SLEEPY") }
                var rows = Pal.Stack(head, A(dangle ? "BODY" : "ARMS_UP"), A("LEGS_A"))   // Spidey 剛好 16 列
                if Night { if Pet.PixAt(rows[10], 5) == 107 && Pet.PixAt(rows[10], 6) == 107 { rows[10] = Pet.SetPix(Pet.SetPix(rows[10], 5, 119), 6, 119) } }
                if dangle
                {
                    let sway = CInt(Math.Round(Math.Sin(tt * 1.3) * dps * 0.8))
                    let topY = Math.Max(cell.Y + 3 * ps, fy - 19 * ps) + CInt(Math.Round(Math.Sin(tt * 2.1) * dps * 0.7))
                    let silk = Pen(Night ? Color.FromArgb(200, 150, 140, 210) : Color.FromArgb(220, 255, 255, 255), Math.Max(1.0, dps * 0.4))
                    g.DrawLine(silk, Double(fx), Double(cell.Y), Double(fx + sway), Double(topY + 2))
                    DrawPix(g, rows, bx + sway, topY, ps, flip, true, true)
                }
                else
                {
                    DrawPix(g, rows, bx, by, ps, flip, false, true)
                    let silk = Pen(Color.FromArgb(200, 255, 255, 255), Math.Max(1.0, dps * 0.4))
                    g.DrawLine(silk, Double(bx + (flip ? 1 : 11) * ps), Double(by + 8 * ps), Double(flip ? cell.X + 2 : cell.Right - 2), Double(cell.Y + 4))
                    DrawAccessories(g, bx, by, ps, flip, 0, true)
                }
                DrawShelfWeb(g, cell, ps)
            case "po":
                // 扶著停在旁邊的滑板車，跟車子一起前後搖
                if blink || Night && (tt % 5) < 2 { ReplaceFace(&head, "SLEEPY") }
                let f = F(Pal.Stack(head, A("BODY"), A("LEGS_A"))); f.Tummy = true
                let rock = CInt(Math.Round(Math.Sin(tt * 2.2) * dps * 0.6))
                DrawAt(g, A("SCOOTER"), 3, 7, bx + rock, by - breathe, ps, !flip, false, true)
                DrawPix(g, f.Rows, bx + rock - (f.Rows[0].utf8.count - 12) / 2 * ps, by + (16 - f.Rows.count) * ps, ps, flip, false, true)
                DrawAccessories(g, bx + rock, by, ps, flip, f.AccDy, true)
                DrawStatusIcon(g, TummyStatus(), bx + rock + 6 * ps, by + CInt((10.5 + Double(f.AccDy)) * dps), Math.Max(1, ps / 2), true)
            case "stitch":
                // 耳朵抖抖、壞壞地笑；晚上耳朵垂下來抱著烏克麗麗
                var body = "BODY"
                if Night { let ed = A("EARS_DOWN"); for i in 0..<ed.count { head[i] = ed[i] }; body = "ARMS_HUG"; if (tt % 6) < 3 { ReplaceFace(&head, "SLEEPY") } }
                else
                {
                    if (tt % 1.7) < 0.35 { let eu = A("EARS_UP"); for i in 0..<eu.count { head[i] = eu[i] } }
                    if (tt % 7) < 3 { ReplaceFace(&head, "GRIN") }
                    if blink { ReplaceFace(&head, "SLEEPY") }
                }
                let rows = Pal.Stack(head, A(body), A("LEGS_A"))
                DrawPix(g, rows, bx - (rows[0].utf8.count - 12) / 2 * ps, by + (16 - rows.count) * ps, ps, flip, false, true)
                DrawAccessories(g, bx, by, ps, flip, 0, true)
                if Night { DrawAt(g, A("UKE"), 5, 8, bx, by, ps, flip, false, true) }
            case "hangyodon":
                // 像海草一樣在水裡輕輕搖、吐泡泡；晚上睡在泡泡裡
                if Night || blink { ReplaceFace(&head, "SLEEPY") }
                let rows = Pal.Stack(head, A(Night ? "BODY" : ((tt % 6) < 1.2 ? "POUT" : "BODY")), A(Night ? "LEGS_SIT" : "LEGS_A"))
                let sway = CInt(Math.Round(Math.Sin(tt * 1.4) * dps * 0.8))
                let lx = bx - (rows[0].utf8.count - 12) / 2 * ps + sway
                if Night { DrawSleepBubble(g, bx, by, ps, false) }
                DrawPix(g, rows, lx, by + (16 - rows.count) * ps, ps, flip, false, true)
                DrawAccessories(g, bx + sway, by, ps, flip, 0, !Night)
                if Night { DrawSleepBubble(g, bx, by, ps, true) }
                // 泡泡從嘴巴冒上去
                let bp = Pen(Color.FromArgb(190, 150, 215, 255), Math.Max(1.0, dps * 0.35))
                for i in 0..<3
                {
                    let ph = (tt * 0.45 + Double(i) / 3.0) % 1
                    let r = dps * (0.5 + ph * 0.9)
                    let px = Double(fx + sway) + Math.Sin(ph * 9 + Double(i)) * dps + Double((flip ? -3 : 3) * ps)
                    let py = Double(by + 8 * ps) - ph * 9 * dps
                    if py > Double(cell.Y) + r { g.DrawEllipse(bp, px - r, py - r, 2 * r, 2 * r) }
                }
            case "tinky", "dipsy", "laalaa":
                DrawTubbyShelf(g, head, fx, bx, by, ps, flip, tt, blink)
            case "pkred", "pkyellow", "pkblue":
                DrawPikShelf(g, fx, bx, by, ps, flip, tt, blink, cell)
            default:
                if blink { ReplaceFace(&head, "SLEEPY") }
                do { let rows = Pal.Stack(head, A("BODY"), A("LEGS_A")); DrawPix(g, rows, bx - (rows[0].utf8.count - 12) / 2 * ps, by + (16 - rows.count) * ps, ps, flip, false, true) }
                DrawAccessories(g, bx, by, ps, flip, 0, true)
        }
        // 午餐時間：櫃子裡的公仔也拿著午餐
        if w.Lunch && !(Is("spidey") && (tt % 11) < 8) { DrawLunchShelf(g, bx, by, ps, flip) }
        // 剛回櫃子：一圈小星星
        if ShelfFx < 1
        {
            let sp = Math.Max(1, ps / 2)
            for i in 0..<6
            {
                let a = Double(i) * Math.PI / 3 + ShelfFx * 2, rr = (4 + ShelfFx * 7) * dps
                if Math.Floor(ShelfFx * 18 + Double(i)) % 2 == 0
                { DrawPix(g, Pet.STAR, CInt(Double(fx) + Math.Cos(a) * rr) - sp, CInt(Double(fy) - 8 * dps + Math.Sin(a) * rr * 0.8) - sp, sp, false, false, false) }
            }
        }
    }

    // mac: C# mutated the array in place → inout (call as ReplaceFace(&head, "SLEEPY"))
    func ReplaceFace(_ head: inout [String], _ face: String)
    {
        if !P.Art.ContainsKey(face) { return }
        let fr = A(face)
        var i = 0
        while i < fr.count && P.FaceRow + i < head.count
        {
            if fr[i].utf8.count == head[P.FaceRow + i].utf8.count { head[P.FaceRow + i] = fr[i] }
            i += 1
        }
    }

    // Spidey 回櫃子時在格子左上角織一張小圓網（ShelfFx 0→1 織完）
    func DrawShelfWeb(_ g: Graphics, _ cell: Rectangle, _ ps: Int)
    {
        let prog = Math.Min(1.0, ShelfFx * 1.3)
        let cx = Double(cell.X + 1), cy = Double(cell.Y + 1), R0 = 11 * Double(ps)
        let spokes = 6
        let sh = Pen(Color.FromArgb(70, 40, 30, 60), Math.Max(1.6, Double(ps) * 0.55))
        let silk = Pen(Night ? Color.FromArgb(220, 214, 204, 255) : Color.FromArgb(235, 255, 255, 255), Math.Max(1.0, Double(ps) * 0.35))
        let pens = [ sh, silk ]
        for p in pens
        {
            for i in 0..<spokes
            {
                let a = Math.PI / 2 * Double(i) / Double(spokes - 1)
                g.DrawLine(p, cx, cy, cx + Math.Cos(a) * R0 * Math.Min(1.0, prog * 2), cy + Math.Sin(a) * R0 * Math.Min(1.0, prog * 2))
            }
            let rings = 4, shown = CInt(Math.Floor(Double(rings) * Math.Max(0.0, prog * 2 - 1) + 0.001))
            var r = 0
            while r < shown
            {
                let rr = R0 * (0.3 + 0.7 * Double(r + 1) / Double(rings))
                var i = 0
                while i + 1 < spokes
                {
                    let a1 = Math.PI / 2 * Double(i) / Double(spokes - 1), a2 = Math.PI / 2 * Double(i + 1) / Double(spokes - 1), am = (a1 + a2) / 2
                    let p1 = PointF(cx + Math.Cos(a1) * rr, cy + Math.Sin(a1) * rr)
                    let p2 = PointF(cx + Math.Cos(a2) * rr, cy + Math.Sin(a2) * rr)
                    let pm = PointF(cx + Math.Cos(am) * rr * 0.9, cy + Math.Sin(am) * rr * 0.9)
                    g.DrawLine(p, p1, pm); g.DrawLine(p, pm, p2)
                    i += 1
                }
                r += 1
            }
        }
    }
}
