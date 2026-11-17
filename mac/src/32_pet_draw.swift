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
        if P.Pik { return FramePik() }   //@fan
        if P.Orig { return FrameOrig() }
        if P.Cu { return FrameCu() }
        // <fan>
        switch P.Id
        {
            case "po": return FramePo()
            case "stitch": return FrameStitch()
            case "hangyodon": return FrameHangyodon()
            case "tinky", "dipsy", "laalaa": return FrameTubby()
            default: break
        }
        return FrameSpidey()
        // </fan>
        // <public> return F(Pal.Stack(HeadRows(nil), A("BODY"), A("LEGS_A")))
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
        if lv >= 5 && !Is("spidey") { DrawAt(g, Pet.BADGE, P.BadgeCol, P.BadgeRow + dy, bx0, by0, ps, fx, false, false) }   //@fan
        // <public> if lv >= 5 { DrawAt(g, Pet.BADGE, P.BadgeCol, P.BadgeRow + dy, bx0, by0, ps, fx, false, false) }
        var hat: [String]? = w.SeasonNow == "xmas" ? Pet.SANTA : (lv >= 6 ? Pet.CROWN : (lv >= 3 ? Pet.BEANIE : nil))
        if HatOnHead() || WearHat || P.Pik { hat = nil }      // 迪西：自己的帽子不換（借戴迪西帽子時也一樣）   //@fan
        if let hat = hat
        {
            DrawAt(g, hat, P.HatCol, P.HatRow + dy - hat.count, bx0, by0, ps, fx, false, true)
            // <fan>
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
            // </fan>
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
        // <fan>
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
        // </fan>
        if P.Orig { DrawOrigBehind(g, f, bx, by, ps, fx) }
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
        // <fan>
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
        // </fan>
        if P.Orig { DrawOrigFront(g, f, bx, by, ps, fx) }
        if HoldToast && f.Rot == 0 && !f.Fy { DrawAt(g, Pet.TOAST, Is("po") ? 9.5 : 10.5, P.BodyTop + 1 + f.AccDy, bx, by, ps, fx, false, true) }   //@fan
    }

    // ================= 一格一格畫到 layered window =================
    func Grow(_ l: inout Double, _ tp: inout Double, _ r: inout Double, _ b: inout Double, _ px: Double, _ py: Double)
    {
        l = Math.Min(l, px); r = Math.Max(r, px); tp = Math.Min(tp, py); b = Math.Max(b, py)
    }
    func SilkVisible() -> Bool { return state == "swing" || state == "hang" || state == "zip" || state == "shoot" || state == "webcatch" || state == "sling" }
    func Bob() -> Double { if P.Cu { return 0 }; if P.Pik { return PikBob() }; if P.Orig { return OrigBob() }; if P.Tubby { return TubbyBob() }; return state == "dance" || state == "elvis" ? Math.Abs(Math.Sin(anim * 8)) * 6 * k : (Is("hangyodon") && state == "walk" ? (Step2(4) ? k : 0) : 0) }   //@fan
    // <public> func Bob() -> Double { if P.Cu { return 0 }; if P.Orig { return OrigBob() }; return state == "dance" || state == "elvis" ? Math.Abs(Math.Sin(anim * 8)) * 6 * k : 0 }

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
        if P.Tubby || WearHat || HoldToast || P.Pik || P.Orig { tp = Math.Min(tp, y - Double((P.TopRows + (state == "juggle" || state == "hattoss" || state == "bagdig" ? 16 : 9)) * S)) }   //@fan
        // <public> if P.Orig { tp = Math.Min(tp, y - Double((P.TopRows + (state == "juggle" || state == "hattoss" || state == "bagdig" ? 16 : 9)) * S)) }
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
            a -= ((Is("po") && OnScooter()) || RidingPo ? 4 * dS : 0)   //@fan
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
            // <fan>
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
            // </fan>
        }

        // Codex／Claude 狀態小圖示（小波在肚子上，其他人在頭旁邊）
        if !HasTv && Math.Abs(sc - 1) < 0.001 && w.Lead() === self
        {
            let st = w.Status()
            if st != "" { DrawStatusIcon(g, st, CInt(x + dSW + 2 * dS) - ox, CInt(y - 1 * dS) - oy, Math.Max(1, S / 2), false) }
        }

        DrawTicketBadge(g, ox, oy)
        MisDraw(g, ox, oy)   // 搗蛋的道具、眼淚（59_mischief.swift）
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
        if P.Cu { DrawFigureCu(g, f, sbx, sby, sps, fx, extras); return }   // 自己做的公仔（53_custom.swift）
        if P.Orig { DrawFigureOrig(g, f, sbx, sby, sps, fx, extras); return }   // 續命小隊（圖片，51_original.swift）
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
        // <fan>
        if f.Tummy && f.Rot == 0
        {
            let u = Math.Max(1, sps / 2)
            let scx = sbx + 6 * sps, scy = sby + CInt((P.TummyRow + Double(f.AccDy)) * Double(sps))
            DrawStatusIcon(g, TummyStatus(), scx, scy, u, true)
        }
        // </fan>
        if extras { DrawFront(g, f, sbx, sby, sps, fx); DrawLunch(g, f, sbx, sby, sps, fx) }
    }
}

// ================= 櫃子的圖：每一櫃可以有自己的櫃子（pals/<資料夾>/shelf：窩伴小世界的書包小屋），沒有就用紙箱櫃（pals/shelf，tools/shelf_art/shelf_art.py 產生）=================
// shelf.txt 的座標是 2x 圖的像素（1x 圖剛好一半）；櫃子用 S/8 換算（100% 縮放 S=4＝1x 圖原尺寸）。
// 晚上版不另外存圖：整張乘一個稍暗、稍偏藍的顏色（ShelfArt.Night）。圖讀不到就用程式畫一個簡單的紙箱，不要當掉。
// mac：一律用 2x 圖（櫃子的 Bitmap 是 Retina，畫進邏輯大小剛好 1:1）
final class ShelfArt
{
    var Dir = "shelf", ImageName = "box.png"   // pals 底下哪個資料夾、圖的檔名（shelf.txt 的 image）
    // 跟紙箱櫃 shelf.txt 一樣的預設值（檔案讀不到時用）
    var W2 = 512, H2 = 668, Crown = 88, N = 4      // N＝幾格（紙箱櫃 4 格；書包小屋 3 間）
    var Pedestal = true, Note = true               // 格 0 的展示台、大格背板的便利貼（shelf.txt 的 pedestal 0／note 0 關掉）
    var Tab: [Int] = [382, 60, 44, 22]
    // 收起來的樣子（mini.txt＋{1x,2x}/mini.png，tools/shelf_art/mini_art.py 產生）：紙箱櫃＝封好的小紙箱、書包小屋＝小書包；圖讀不到就畫以前的像素蛋
    var MiniLid = 42                               // 蓋子／提把跟下面的分界（2x 圖的像素）：吞公仔時上面那塊往上掀
    var MiniName = "小紙箱", Btn = "ink"          // 選單、泡泡裡的叫法；收合鈕的畫風（ink＝白邊黑線貼紙、clay＝黏土）
    var Cells: [[Int]] = [
        [248, 106, 178, 508, 282, 107, 144, 477, 586, 614, 344, 603, 288, 620, 98, 20],
        [48, 106, 164, 132, 82, 106, 130, 108, 216, 238, 137, 230, 83, 244, 97, 20],
        [48, 293, 164, 131, 82, 294, 130, 106, 403, 424, 137, 416, 83, 430, 97, 20],
        [48, 479, 164, 135, 82, 480, 130, 105, 587, 614, 137, 603, 83, 619, 97, 21] ]
    var imgs = [String: Bitmap]()
    var tried = Set<String>()
    static var kits = [String: ShelfArt]()
    static var dirOf = [String: String]()
    init() {}

    // 這一櫃用哪個櫃子：圖片公仔櫃的資料夾裡有 shelf/shelf.txt 就用它；沒有（或其他櫃）用紙箱櫃
    static func For(_ lineup: String) -> ShelfArt
    {
        var dir: String = "shelf"
        if let d0 = dirOf[lineup] { dir = d0 }
        else {
            if let q = SqArt.Lineup(lineup), SqArt.ReadText(q.Dir + "/shelf/shelf.txt") != nil { dir = q.Dir + "/shelf" }
            dirOf[lineup] = dir
        }
        if let k0 = kits[dir] { return k0 }
        let k = ShelfArt()
        k.Dir = dir
        k.Load()
        kits[dir] = k
        return k
    }

    func Load()
    {
        guard let meta = SqArt.ReadText(Dir + "/shelf.txt") else { App.LogAlways("shelf art missing: " + Dir + "/shelf.txt"); return }
        var n = 0
        for line in meta.components(separatedBy: "\n")
        {
            let a = line.Trim().components(separatedBy: " ")
            var v = [Int](repeating: 0, count: a.count)
            for i in 1..<Swift.max(1, a.count) { v[i] = Int(a[i]) ?? 0 }
            if a[0] == "size" && a.count >= 3 { W2 = v[1]; H2 = v[2] }
            else if a[0] == "crown" && a.count >= 2 { Crown = v[1] }
            else if a[0] == "tab" && a.count >= 5 { Tab = [v[1], v[2], v[3], v[4]] }
            else if a[0] == "image" && a.count >= 2 && a[1] != "" { ImageName = a[1] }
            else if a[0] == "pedestal" && a.count >= 2 { Pedestal = v[1] != 0 }
            else if a[0] == "note" && a.count >= 2 { Note = v[1] != 0 }
            else if a[0] == "cell" && a.count >= 18 && v[1] >= 0 && v[1] < 4 { Cells[v[1]] = Array(v[2..<18]); n = Swift.max(n, v[1] + 1) }
        }
        if n > 0 { N = n }
        guard let mm = SqArt.ReadText(Dir + "/mini.txt") else { return }
        for line in mm.components(separatedBy: "\n")
        {
            let t = line.Trim()
            let sp = t.IndexOf(" ")
            if sp <= 0 || t.StartsWith("#") { continue }
            let key = t.Substring(0, sp), v = t.Substring(sp + 1).Trim()
            var iv = 0
            if key == "lid" && int.TryParse(v, &iv) { MiniLid = iv }
            else if key == "name" && v != "" { MiniName = v }
            else if key == "btn" && v != "" { Btn = v }
        }
    }

    // 收起來的樣子：r＝1x／2x、night＝晚上版。讀不到＝nil（畫像素蛋）
    func Mini(_ r: Int, _ night: Bool) -> Bitmap!
    {
        let key = "m" + String(r) + (night ? "n" : "d")
        if let b = imgs[key] { return b }
        if tried.contains(key) { return nil }
        tried.insert(key)
        var b: Bitmap! = nil
        if night { if let d = Mini(r, false) { b = ShelfArt.Night(d) } }
        else { b = SqArt.Png(Dir + "/" + String(r) + "x/mini.png") }
        if b != nil { imgs[key] = b }
        return b
    }

    // r：1＝1x 圖、2＝2x 圖；night：晚上版（第一次用到才算）。讀不到＝nil
    func Image(_ r: Int, _ night: Bool) -> Bitmap!
    {
        let key = String(r) + (night ? "n" : "d")
        if let b = imgs[key] { return b }
        if tried.contains(key) { return nil }
        tried.insert(key)
        var b: Bitmap! = nil
        if night { if let d = Image(r, false) { b = ShelfArt.Night(d) } }
        else { b = SqArt.Png(Dir + "/" + String(r) + "x/" + ImageName); if b == nil { App.LogAlways("shelf art missing: " + Dir + "/" + String(r) + "x/" + ImageName) } }
        if b != nil { imgs[key] = b }
        return b
    }

    // 晚上：整張乘一個稍暗的顏色（紅 ×0.86、綠 ×0.83、藍 ×0.88）：暗一點、帶一點夜色，但顏色不變灰（以前往深藍紫混一半，灰濛濛的）
    static func Night(_ d: Bitmap) -> Bitmap
    {
        var px = CuImg.Pixels(d)
        for i in 0..<px.count
        {
            let v = px[i], a = (v >> 24) & 255
            if a == 0 { continue }
            let r = ((v >> 16) & 255) * 86 / 100, g = ((v >> 8) & 255) * 83 / 100, b = (v & 255) * 88 / 100
            px[i] = (a << 24) | (r << 16) | (g << 8) | b
        }
        return CuImg.FromPixels(px, d.Width, d.Height)
    }
}

// ================= 公仔櫃 =================
// 右下角的紙箱櫃（網購紙箱疊成的，跟續命小隊同一種粗黑線貼紙畫風）：右邊一格高的（最愛）、左邊三格小的，每格底下一塊名牌。
// 櫃子本體是一張圖（ShelfArt）；格子裡的公仔、名牌上的字、第 4 格入口、收合鈕、最愛的展示台都是程式畫在上面。點格子裡的公仔＝放出來／收回去。
final class ShelfForm: OverlayForm
{
    let w: World
    let U: Int, TU: Int           // 小格、高格的像素大小（像素公仔；TU＝S）
    let k: Double
    var Hot = false, Over = false, Night = false
    var Tubby = false                   // 天線寶寶一櫃：格子裡是藍天綠山丘，大格有太陽寶寶   //@fan
    var Kit: ShelfArt = ShelfArt.For("")   // 這一櫃的櫃子（Place 時照 World 現在的櫃換）
    //@@BODY ShelfForm
    var hover = -1
    var tabHover = false, miniHover = false        // 滑鼠在收合鈕上／在收起來的小紙箱上
    var bmp: Bitmap! = nil, bg: Bitmap! = nil
    var bgKey = ""
    var area = Rectangle(0, 0, 0, 0)    // 螢幕座標
    var Area: Rectangle { return area }
    var cells = [Rectangle](repeating: Rectangle(0, 0, 0, 0), count: 4) // 本地座標：開口＋名牌（點這裡＝點這一格）
    var opening = [Rectangle](repeating: Rectangle(0, 0, 0, 0), count: 4), back = [Rectangle](repeating: Rectangle(0, 0, 0, 0), count: 4), plate = [Rectangle](repeating: Rectangle(0, 0, 0, 0), count: 4)   // 開口（公仔畫在裡面）、背板、名牌
    var foot = [Point](repeating: Point(0, 0), count: 4)          // 公仔腳踩的地方（地板中間）
    var tab = Rectangle(0, 0, 0, 0)                                // 收合鈕的位置（shelf.txt 的 tab：按鈕畫在它的中心，大小照 S 算）
    var crown = 0                                                  // 箱子正面的上緣：再上面是蓋子（可以拖著搬家、掛徽章）
    // ---- 收起來（以前是一顆蛋；現在是每一櫃自己的小紙箱／小書包，Kit.Mini；圖讀不到才畫 EGG）----
    var Collapsed = false
    var fold = 0.0, gulp = 0.0, wobT = 0.0, nextWob = 4.0    // fold：0 櫃子 → 1 收起來
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
    // 收起來的大小：小紙箱／小書包的 2x 圖 × S/8（100% 縮放＝1x 圖原尺寸）；圖讀不到＝以前的像素蛋（18×19 格）
    func EggLocal() -> Rectangle
    {
        let m: Bitmap! = Kit.Mini(2, false)
        let ew = m != nil ? Sc(m.Width) : 18 * EggPs, eh = m != nil ? Sc(m.Height) : 19 * EggPs
        return Rectangle(Area.Width - ew - 4, Area.Height - eh - 2, ew, eh)
    }
    func EggScreen() -> Rectangle { let r = EggLocal(); return Rectangle(r.X + Area.X, r.Y + Area.Y, r.Width, r.Height) }
    // 收合鈕：一張看得出來是按鈕的小貼紙（圖示＋「收起」），中心在 shelf.txt 的 tab，大小照 S 算（100% 縮放 60×22）；
    // 太低就往上挪，按鈕和點擊範圍都不蓋到格子的開口（書包小屋的 tab 在提把下面，貼著房間）
    func TabLocal() -> Rectangle
    {
        let bw = 15 * TU, bh = 5 * TU + 2
        let x = Math.Max(2, Math.Min(Area.Width - bw - 2, tab.X + tab.Width / 2 - bw / 2))
        var y = tab.Y + tab.Height / 2 - bh / 2
        y = Math.Max(2, Math.Min(y, OpenTop() - bh - TU - 2))
        return Rectangle(x, y, bw, bh)
    }
    func OpenTop() -> Int { var top = Int.max; for i in 0..<Kit.N { top = Math.Min(top, opening[i].Y) }; return top }
    // 點擊範圍：按鈕四周再放大一圈（比按鈕大、好點），但不蓋到格子的開口
    func TabHit() -> Rectangle
    {
        let b = TabLocal()
        var t = b
        t.Inflate(TU + 2, TU + 2)
        let top = OpenTop()
        if t.Bottom > top - 1 && top - 1 > b.Bottom { t.Height = top - 1 - t.Y }
        return t
    }
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
    // 收起來的腳（公仔收進小紙箱裡的位置）
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
    // 收起來的小紙箱或櫃頂（不是收合鈕、不是格子）可以拖
    func DragSpot(_ local: Point) -> Bool { return Collapsed ? EggLocal().Contains(local) : (local.Y < crown && !TabHit().Contains(local)) }

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
        Kit = ShelfArt.For(w.LineupNow)
        let W = Sc(Kit.W2), H = Sc(Kit.H2)
        defX = wa.Right - W - 6; defY = wa.Bottom - H; lastWa = wa
        let ax = Math.Max(wa.Left, Math.Min(defX, defX + OffX)), ay = Math.Max(wa.Top, Math.Min(defY, defY + OffY))
        area = Rectangle(ax, ay, W, H)
        for i in 0..<4
        {
            let v = Kit.Cells[i]
            opening[i] = Rc(v, 0); back[i] = Rc(v, 4); plate[i] = Rc(v, 12)
            foot[i] = Point(Sc(v[10]), Sc(v[11]))
            cells[i] = Rectangle.Union(opening[i], plate[i])
        }
        tab = Rc(Kit.Tab, 0)
        crown = Sc(Kit.Crown)
    }
    // shelf.txt 的 2x 座標 → 這個櫃子的像素（S=4 剛好一半）
    func Sc(_ v: Int) -> Int { return CInt(Math.Floor(Double(v * TU) / 8.0 + 0.5)) }
    func Rc(_ v: [Int], _ o: Int) -> Rectangle { let x = Sc(v[o]), y = Sc(v[o + 1]); return Rectangle(x, y, Sc(v[o] + v[o + 2]) - x, Sc(v[o + 1] + v[o + 3]) - y) }

    func CellPs(_ i: Int) -> Int { return i == 0 ? TU : U }
    // 依公仔實際高度（天線、耳朵、頭鰭、帽子、晃動）縮放，保證離格子頂端至少 2px
    func FitPs(_ i: Int, _ p: Pet?) -> Int
    {
        var ps = CellPs(i)
        guard let p = p else { return ps }
        let avail = foot[i].Y - (i == 0 ? PedH() : 0) - opening[i].Y - 2 - 2
        let rows = p.ShelfRows()
        while ps > 2 && rows * ps > avail { ps -= 1 }
        return ps
    }
    func CellScreen(_ i: Int) -> Rectangle { let c = cells[i]; return Rectangle(c.X + Area.X, c.Y + Area.Y, c.Width, c.Height) }
    // 公仔腳踩的位置（螢幕座標）：地板中間；高格站在展示台上
    func Foot(_ i: Int) -> Point { return Point(Area.X + foot[i].X, Area.Y + foot[i].Y - (i == 0 ? PedH() : 0)) }
    func PedH() -> Int { return Kit.Pedestal ? CInt(Double(opening[0].Height) * 0.13) : 0 }
    // 測試用（pipe「shelf-info」）：櫃子、每一格的開口和名牌、腳底、收合鈕（螢幕座標）
    func Info() -> String
    {
        let col: String = Collapsed ? "1" : "0", hasArt: String = Kit.Image(2, false) != nil ? "1" : "0"
        var sb: String = "shelf " + String(Area.X) + " " + String(Area.Y) + " " + String(Area.Width) + " " + String(Area.Height)
        sb += " " + col + " " + String(TU) + " " + hasArt + " " + String(Kit.N) + " " + Kit.Dir + "\n"
        for i in 0..<Kit.N
        {
            let f = Foot(i)
            let o = opening[i], pl = plate[i]
            let a: String = "cell " + String(i) + " " + String(Area.X + o.X) + " " + String(Area.Y + o.Y) + " " + String(o.Width) + " " + String(o.Height)
            let b: String = " " + String(Area.X + pl.X) + " " + String(Area.Y + pl.Y) + " " + String(pl.Width) + " " + String(pl.Height) + " " + String(f.X) + " " + String(f.Y) + "\n"
            sb += a + b
        }
        let tl = TabLocal(), th = TabHit(), er = EggScreen()
        sb += "tab " + String(Area.X + tl.X) + " " + String(Area.Y + tl.Y) + " " + String(tl.Width) + " " + String(tl.Height) + "\n"
        sb += "tabhit " + String(Area.X + th.X) + " " + String(Area.Y + th.Y) + " " + String(th.Width) + " " + String(th.Height) + " " + (tabHover ? "1" : "0") + "\n"
        let hasMini: String = Kit.Mini(2, false) != nil ? "1" : "0"
        sb += "mini " + String(er.X) + " " + String(er.Y) + " " + String(er.Width) + " " + String(er.Height) + " " + hasMini + " " + (miniHover ? "1" : "0") + " " + Kit.MiniName + "\n"
        return sb
    }

    func CellAt(_ screen: Point) -> Int
    {
        if Collapsed { return -1 }
        for i in 0..<Kit.N { if CellScreen(i).Contains(screen) { return i } }
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
        if b == MouseButtons.Left && TabHit().Contains(p) { w.ToggleEgg(true); return }
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
        SimHover(cp)
    }
    override func OnMouseLeave(_ e: EventArgs) { super.OnMouseLeave(e); hover = -1; SetHot(false, false) }
    // 滑鼠在哪（真的滑鼠或測試用 act shelfhover 都走這裡）：格子亮一圈、收合鈕變黃浮起來、收起來的小紙箱浮起來
    func SimHover(_ screen: Point)
    {
        hover = CellAt(screen)
        let p = Point(screen.X - Area.X, screen.Y - Area.Y)
        SetHot(!Collapsed && fold <= 0.001 && TabHit().Contains(p), Collapsed && EggLocal().Contains(p))
    }
    func SetHot(_ tabOn: Bool, _ miniOn: Bool)
    {
        if tabOn == tabHover && miniOn == miniHover { return }
        tabHover = tabOn; miniHover = miniOn
        w.RepaintShelf()
    }

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

    // 櫃子本體（不會動的部分）先畫好存起來：紙箱櫃的圖（晚上是調暗的版本）＋每一格的背景、展示台、名牌上的字
    func BuildBg(_ who: [Pet?], _ outNow: [Bool])
    {
        let W = Area.Width, H = Area.Height
        if bg == nil || bg.Width != W || bg.Height != H { if bg != nil { bg.Dispose() }; bg = Bitmap(W, H) }
        let g = Graphics.FromImage(bg)
        defer { g.Dispose() }
        g.Clear(Color.Transparent)
        g.SmoothingMode = SmoothingMode.AntiAlias
        let art: Bitmap! = Kit.Image(2, Night)   // mac：一律 2x
        if art != nil
        {
            let ia = ImageAttributes()
            ia.SetWrapMode(WrapMode.TileFlipXY)   // 縮放時外框不要變淡
            g.InterpolationMode = InterpolationMode.HighQualityBicubic
            g.PixelOffsetMode = PixelOffsetMode.HighQuality
            g.DrawImage(art, Rectangle(0, 0, W, H), 0, 0, art.Width, art.Height, GraphicsUnit.Pixel, ia)
            g.PixelOffsetMode = PixelOffsetMode.Default
        }
        else { DrawPlainBox(g) }
        // 每一格
        for i in 0..<Kit.N
        {
            let pet = who[i]
            let c = opening[i]
            if Tubby { DrawHills(g, RectangleF(c), i == 0) }   //@fan
            if Pik { DrawSoil(g, RectangleF(c), i == 0) }   //@fan
            if Orig && Kit.Note && i == 0 { DrawStickyNote(g, back[0]) }
            if Night { DrawLamp(g, c) }
            if i == 0 && Pik { DrawFlowerBed(g, c) }   //@fan
            else if i == 0 && Kit.Pedestal { DrawPedestal(g, c) }   //@fan
            // <public> if i == 0 && Kit.Pedestal { DrawPedestal(g, c) }
            // 名牌
            let name = pet == nil ? (i == 0 && Pik ? "★ 休息花" : (Orig ? "＋ 做公仔" : "？")) : (i == 0 ? "★ " + pet!.P.Name : pet!.P.Name)   //@fan
            // <public> let name = pet == nil ? (Orig ? "＋ 做公仔" : "？") : (i == 0 ? "★ " + pet!.P.Name : pet!.P.Name)
            DrawPlate(g, plate[i], name ?? "", i == 0)   // mac: P.Name 是 String!，三元運算的結果是 String?
        }
    }

    // 圖讀不到：程式畫一個簡單的紙箱（格子、名牌的位置一樣）
    func DrawPlainBox(_ g: Graphics)
    {
        let lw = Math.Max(1.5, Double(TU) * 0.5)
        let cb = SolidBrush(Night ? C(0x6E5440) : C(0xD9A066))
        let wb = SolidBrush(Night ? C(0x8A8290) : C(0xFAF2E2))
        let ink = Pen(C(0x1E1E24), lw)
        let dcrown = Double(crown)
        let bp = RoundRect(RectangleF(lw, dcrown * 0.5, Double(Area.Width) - 2 * lw, Double(Area.Height) - dcrown * 0.5 - lw), Double(3 * U))
        g.FillPath(cb, bp); g.DrawPath(ink, bp)
        for i in 0..<Kit.N
        {
            g.FillRectangle(wb, opening[i])
            g.DrawRectangle(ink, opening[i].X, opening[i].Y, opening[i].Width, opening[i].Height)
            let pp = RoundRect(RectangleF(Double(plate[i].X), Double(plate[i].Y), Double(plate[i].Width), Double(plate[i].Height)), Double(plate[i].Height) * 0.3)
            g.FillPath(wb, pp); g.DrawPath(ink, pp)
        }
    }

    // 晚上：格子裡亮著一盞暖暖的小燈（公仔看得清楚）
    func DrawLamp(_ g: Graphics, _ c: Rectangle)
    {
        let cx = Double(c.X), cy = Double(c.Y), cw = Double(c.Width), ch = Double(c.Height)
        let gp = GraphicsPath()
        gp.AddEllipse(RectangleF(cx - cw * 0.2, cy - cw * 0.35, cw * 1.4, Math.Min(ch * 0.8, cw * 1.3)))
        let pg = PathGradientBrush(gp)
        pg.CenterColor = Color.FromArgb(150, 255, 214, 150)
        pg.SurroundColors = [ Color.FromArgb(0, 255, 240, 220) ]
        g.SetClip(c)
        g.FillPath(pg, gp)
        g.ResetClip()
    }

    // 名牌：圖上那塊空白的牌子寫名字（字太長就縮小；晚上牌子補一點亮，字才看得清楚）
    func DrawPlate(_ g: Graphics, _ pr: Rectangle, _ name: String, _ fav: Bool)
    {
        let px = Double(pr.X), py = Double(pr.Y), pw = Double(pr.Width), ph = Double(pr.Height)
        if Night
        {
            let pp = RoundRect(RectangleF(px + 0.5, py + 0.5, pw - 1, ph - 1), ph * 0.3)
            g.FillPath(SolidBrush(Color.FromArgb(140, 255, 236, 200)), pp)
        }
        var fs = Math.Max(9.0, Math.Min(ph * 0.95, 3.4 * Double(TU)))
        g.TextRenderingHint = TextRenderingHint.AntiAlias
        var f = Font("Microsoft JhengHei UI", fs, FontStyle.Bold, GraphicsUnit.Pixel)
        while fs > 7.5 && g.MeasureString(name, f).Width - fs * 0.3 > pw { fs -= 0.5; f = Font("Microsoft JhengHei UI", fs, FontStyle.Bold, GraphicsUnit.Pixel) }
        let sf = StringFormat()
        let tb = SolidBrush(fav ? C(0x8A3A12) : C(0x3A2A1E))
        sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center; sf.Trimming = StringTrimming.None; sf.FormatFlags = StringFormatFlags.NoWrap
        g.DrawString(name, f, tb, RectangleF(px - 8, py + 0.5, pw + 16, ph), sf)
    }

    // <fan>
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

    // 太陽寶寶：白天在天上笑，晚上一半沉到山丘後面（c＝高格的開口）
    func DrawSunBaby(_ g: Graphics, _ c: Rectangle, _ cx0: Double, _ sy: Double, _ sr: Double)
    {
        var cx = cx0
        let inner = RectangleF(Double(c.X), Double(c.Y), Double(c.Width), Double(c.Height))
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
    // </fan>

    // 高格：最愛站的小圓台（貼紙畫風：奶油色＋粗黑邊）＋背板上淡淡的大星星；c＝開口
    func DrawPedestal(_ g: Graphics, _ c: Rectangle)
    {
        let cx = Double(foot[0].X), ph = Double(PedH()), floor = Double(foot[0].Y), top = floor - ph
        let pw = Double(c.Width) * 0.56, eh = Math.Max(4.0, pw * 0.22)
        // 星星
        var star = [PointF]()
        let sr = Double(c.Width) * 0.36, sy = Double(c.Y) + (top - Double(c.Y)) * 0.42
        for i in 0..<10
        {
            let a = -Math.PI / 2 + Double(i) * Math.PI / 5, rr = i % 2 == 0 ? sr : sr * 0.45
            star.append(PointF(cx + Math.Cos(a) * rr, sy + Math.Sin(a) * rr))
        }
        if Tubby { DrawSunBaby(g, c, cx, sy, sr) }   //@fan
        else   //@fan
        { g.FillPolygon(SolidBrush(Night ? Color.FromArgb(50, 255, 220, 150) : Color.FromArgb(90, 255, 214, 120)), star) }   //@fan
        // <public> do { g.FillPolygon(SolidBrush(Night ? Color.FromArgb(50, 255, 220, 150) : Color.FromArgb(90, 255, 214, 120)), star) }
        // 圓台：側面（下緣是半個橢圓）＋金色細帶＋頂面，都描粗黑邊
        let m1 = Night ? C(0xD6CCBE) : C(0xFFF6E8), m2 = Night ? C(0xA8988A) : C(0xD9C7AE)
        let lw = Math.Max(1.5, Double(TU) * 0.5), x0 = cx - pw / 2
        let ink = Pen(Night ? C(0x221E28) : C(0x1E1E24), lw)
        let side = GraphicsPath()
        side.AddLine(x0 + pw, top, x0 + pw, floor)
        side.AddArc(x0, floor - eh / 2, pw, eh, 0, 180)
        side.AddLine(x0, floor, x0, top)
        side.CloseFigure()
        do
        {
            let lb = LinearGradientBrush(RectangleF(x0 - 1, top, pw + 2, ph + eh), m2, m1, 0.0)
            let cb = ColorBlend()
            cb.Colors = [ m2, m1, m1, m2 ]
            cb.Positions = [ 0.0, 0.35, 0.55, 1.0 ]
            lb.InterpolationColors = cb
            g.FillPath(lb, side)
        }
        g.FillRectangle(SolidBrush(Night ? C(0xB08A3C) : C(0xE2B550)), x0, top + eh * 0.55, pw, Math.Max(1.0, eh * 0.28))
        g.DrawPath(ink, side)
        g.FillEllipse(SolidBrush(Night ? C(0xDCD2C4) : C(0xFFFBF3)), x0, top - eh / 2, pw, eh)
        g.DrawEllipse(ink, x0, top - eh / 2, pw, eh)
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

    // 收合鈕：大箱子蓋子上一張貼紙按鈕（白色貼紙邊＋粗黑線、往下收的箭頭＋「收起」）；書包小屋是紫色黏土小牌子（沒有黑線）。
    // 滑過：變黃（黏土版變亮）、浮起來一點，下面多一張小牌子「收成小紙箱」
    func DrawTab(_ b: Bitmap)
    {
        let g = Graphics.FromImage(b)
        defer { g.Dispose() }
        g.SmoothingMode = SmoothingMode.AntiAlias
        g.TextRenderingHint = TextRenderingHint.AntiAlias
        let r = TabLocal()
        let clay = Kit.Btn == "clay", hot = tabHover
        let dTU = Double(TU)
        let lift: Double = hot ? Math.Max(1.0, dTU * 0.4) : 0.0, lw = Math.Max(1.5, dTU * 0.45)
        let rf = RectangleF(Double(r.X), Double(r.Y) - lift, Double(r.Width), Double(r.Height))
        // 影子（浮起來時大一點）
        let sp = RoundRect(RectangleF(Double(r.X) + 1, Double(r.Y) + Math.Max(1.5, dTU * 0.45), Double(r.Width), Double(r.Height)), Double(r.Height) / 2)
        g.FillPath(SolidBrush(Color.FromArgb(hot ? 110 : 70, 30, 20, 40)), sp)
        var text: Color
        if clay
        {
            var top = hot ? C(0xC9B6F6) : C(0xB8A2EE), bot = hot ? C(0x9C80E2) : C(0x8C70D4)
            if Night { top = Mix(top, C(0x2A2238), 0.15); bot = Mix(bot, C(0x2A2238), 0.15) }
            let p = RoundRect(rf, rf.Height / 2)
            g.FillPath(LinearGradientBrush(RectangleF(rf.X, rf.Y - 1, rf.Width, rf.Height + 2), top, bot, 90.0), p)
            g.DrawPath(Pen(Color.FromArgb(160, 0x6E, 0x55, 0xB0), Math.Max(1.0, dTU * 0.25)), p)
            let hp = RoundRect(RectangleF(rf.X + rf.Height * 0.35, rf.Y + rf.Height * 0.12, rf.Width - rf.Height * 0.7, rf.Height * 0.3), rf.Height * 0.15)
            g.FillPath(SolidBrush(Color.FromArgb(hot ? 120 : 90, 255, 255, 255)), hp)   // 黏土的亮面
            text = Color.White
        }
        else
        {
            let wp = RoundRect(RectangleF(rf.X - lw, rf.Y - lw, rf.Width + 2 * lw, rf.Height + 2 * lw), rf.Height / 2 + lw)
            g.FillPath(SolidBrush(Night ? C(0xE4E0EA) : Color.White), wp)   // 白色貼紙邊
            let ir = RectangleF(rf.X + lw / 2, rf.Y + lw / 2, rf.Width - lw, rf.Height - lw)
            let p = RoundRect(ir, ir.Height / 2)
            g.FillPath(SolidBrush(hot ? C(0xFFD95A) : (Night ? C(0xF2E6CC) : C(0xFFF6E0))), p); g.DrawPath(Pen(C(0x1E1E24), lw), p)
            text = C(0x2A1E16)
        }
        // 圖示（往下收：∨ 加一條底線）＋「收起」
        let fs = Math.Max(10.0, dTU * 2.9)
        let f = Font("Microsoft JhengHei UI", fs, FontStyle.Bold, GraphicsUnit.Pixel)
        let sf = StringFormat()
        let s = "收起"
        let tw = g.MeasureString(s, f).Width - fs * 0.25, iw = dTU * 2.4, gap = dTU * 0.7
        let x0 = rf.X + (rf.Width - iw - gap - tw) / 2, cy = rf.Y + rf.Height / 2
        let ip = Pen(text, Math.Max(1.5, dTU * 0.5))
        ip.StartCap = LineCap.Round; ip.EndCap = LineCap.Round; ip.LineJoin = LineJoin.Round
        g.DrawLines(ip, [ PointF(x0, cy - iw * 0.42), PointF(x0 + iw / 2, cy + iw * 0.08), PointF(x0 + iw, cy - iw * 0.42) ])
        g.DrawLine(ip, x0, cy + iw * 0.45, x0 + iw, cy + iw * 0.45)
        sf.Alignment = StringAlignment.Near; sf.LineAlignment = StringAlignment.Center; sf.FormatFlags = StringFormatFlags.NoWrap
        if clay { g.DrawString(s, f, SolidBrush(Color.FromArgb(120, 0x5A, 0x40, 0x9A)), RectangleF(x0 + iw + gap - fs * 0.1, rf.Y + 1.5, tw + fs, rf.Height), sf) }
        g.DrawString(s, f, SolidBrush(text), RectangleF(x0 + iw + gap - fs * 0.1, rf.Y + 0.5, tw + fs, rf.Height), sf)
        if hot { DrawTip(g, "收成" + Kit.MiniName, rf.X + rf.Width / 2, rf.Bottom + lw + dTU, clay) }
    }

    // 滑過收合鈕時的小牌子（中心 cx、上緣 y；不超出櫃子）
    func DrawTip(_ g: Graphics, _ s: String, _ cx: Double, _ y: Double, _ clay: Bool)
    {
        let fs = Math.Max(9.5, Double(TU) * 2.6)
        let f = Font("Microsoft JhengHei UI", fs, FontStyle.Bold, GraphicsUnit.Pixel)
        let sf = StringFormat()
        let ts = g.MeasureString(s, f)
        let w2 = ts.Width + Double(TU) * 1.5, h2 = ts.Height + Double(TU) * 0.6
        let x = Math.Max(2.0, Math.Min(Double(Area.Width) - w2 - 2.0, cx - w2 / 2))
        let tr = RectangleF(x, y, w2, h2)
        g.FillPath(SolidBrush(clay ? Color.FromArgb(245, 255, 255, 255) : Color.FromArgb(245, 0x2A, 0x1E, 0x16)), RoundRect(tr, h2 * 0.3))
        sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center; sf.FormatFlags = StringFormatFlags.NoWrap
        g.DrawString(s, f, SolidBrush(clay ? C(0x6E55B0) : C(0xFFF6E0)), RectangleF(tr.X - 4, tr.Y + 0.5, tr.Width + 8, tr.Height), sf)
    }

    // 收起來的樣子：小紙箱／小書包（Kit.Mini）；圖讀不到才畫以前的像素蛋
    func DrawEgg(_ g: Graphics, _ t: Double, _ appear: Double)
    {
        if appear <= 0.02 { return }
        let ps = EggPs
        let dps = Double(ps)
        let er = EggLocal()
        // 搖一搖（有通知存著時搖比較大）
        var ang = 0.0
        if wobT > 0 { ang = Math.Sin(wobT * 26) * Double(Attention > 0 ? 11 : 6) * Math.Min(1.0, wobT * 2) }
        // 打開的程度：收合動畫的頭尾、吞公仔時蓋子掀開
        var open = Math.Max(Math.Max(0.0, 1 - appear) * 1.6, gulp > 0 ? Math.Sin(gulp / 0.5 * Math.PI) * 0.6 : 0)
        open = Math.Min(1.0, open)
        let mini: Bitmap! = Kit.Mini(2, Night)   // mac：一律 2x
        let st = g.Save()
        let hoverLift: Double = miniHover && appear > 0.9 ? Math.Max(1.0, Double(TU) * 0.5) : 0.0   // 滑過：浮起來一點
        g.TranslateTransform(Double(er.X) + Double(er.Width) / 2, Double(er.Bottom) - hoverLift)
        g.RotateTransform(ang)
        g.TranslateTransform(-Double(er.Width) / 2, -Double(er.Height))
        if mini != nil
        {
            let a2 = CInt(255 * Math.Min(1.0, appear * 1.4))
            DrawMini(g, mini, er.Width, er.Height, open, a2)
            if Lunch { DrawNapkin(g, Double(er.Width) / 18.0, Double(er.Height) / 19.0, a2) }
            g.Restore(st)
            DrawEggMarks(g, er, appear)
            return
        }
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
        if Lunch { DrawNapkin(g, dps, dps, alpha) }
        g.Restore(st)
        DrawEggMarks(g, er, appear)
    }

    // 小紙箱／小書包：下面那塊照放；蓋子（Kit.MiniLid 以上）打開時往上抬、以左邊為軸往上掀（吞公仔、收合動畫）
    func DrawMini(_ g: Graphics, _ m: Bitmap, _ ew: Int, _ eh: Int, _ open: Double, _ alpha: Int)
    {
        let m2: Bitmap! = Kit.Mini(2, false)
        let f: Double = m2 == nil ? 0.3 : Math.Max(0.1, Math.Min(0.9, Double(Kit.MiniLid) / Double(m2.Height)))
        let sy = CInt(Math.Round(Double(m.Height) * f)), dy = CInt(Math.Round(Double(eh) * f))
        let st = g.Save()
        let ia = ImageAttributes()
        let cm = ColorMatrix(); cm.Matrix33 = Double(alpha) / 255.0
        ia.SetColorMatrix(cm)
        ia.SetWrapMode(WrapMode.TileFlipXY)   // 縮放時邊緣不要變淡
        g.InterpolationMode = InterpolationMode.HighQualityBicubic
        g.PixelOffsetMode = PixelOffsetMode.HighQuality
        g.DrawImage(m, Rectangle(0, dy, ew, eh - dy), 0, sy, m.Width, m.Height - sy, GraphicsUnit.Pixel, ia)
        if open > 0.01
        {
            g.TranslateTransform(0, Double(dy) - open * Double(eh) * 0.18)
            g.RotateTransform(-open * 16)
            g.TranslateTransform(0, -Double(dy))
        }
        g.DrawImage(m, Rectangle(0, 0, ew, dy), 0, 0, m.Width, sy, GraphicsUnit.Pixel, ia)
        g.Restore(st)
    }

    // 午餐時間：收起來的正面掛一條小餐巾（sx、sy＝蛋的一格多大；小紙箱照 18×19 格換算）
    func DrawNapkin(_ g: Graphics, _ sx: Double, _ sy: Double, _ alpha: Int)
    {
        let nb = SolidBrush(Color.FromArgb(alpha, 255, 255, 255))
        let ck = SolidBrush(Color.FromArgb(alpha, 0xE2, 0x4A, 0x4A))
        let tri = [ PointF(5 * sx, 9 * sy), PointF(13 * sx, 9 * sy), PointF(9 * sx, 14 * sy) ]
        g.FillPolygon(nb, tri)
        g.DrawPolygon(Pen(Color.FromArgb(alpha, 0xB8, 0xA8, 0x90), Math.Max(1.0, sx * 0.3)), tri)
        for i in 0..<4 { g.FillRectangle(ck, Double(6 + i * 2) * sx, 9 * sy, sx, sy) }
        g.FillRectangle(ck, 8 * sx, 11 * sy, sx, sy); g.FillRectangle(ck, 10 * sx, 11 * sy, sx, sy)
    }

    // 收起來的上面：小紅點、拖著公仔時的光圈、番茄／安靜徽章
    func DrawEggMarks(_ g: Graphics, _ er: Rectangle, _ appear: Double)
    {
        let dU = Double(U)
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
        // 番茄／安靜徽章掛在收起來的小紙箱上面
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
        var key = "\(Night)|\(Tubby)|\(Pik)|\(Orig)|\(Kit.Dir)|\(Area.Width)x\(Area.Height)"   //@fan
        // <public> var key = "\(Night)|\(Orig)|\(Kit.Dir)|\(Area.Width)x\(Area.Height)"
        for i in 0..<4 { key += "|" + (who[i] == nil ? "-" : who[i]!.P.Id) }
        if key != bgKey || bg == nil { bgKey = key; BuildBg(who, outNow) }
        if bmp == nil || bmp.Width != bg.Width || bmp.Height != bg.Height { if bmp != nil { bmp.Dispose() }; bmp = Bitmap(bg.Width, bg.Height) }
        let g = Graphics.FromImage(bmp)
        defer { g.Dispose() }
        let dU = Double(U)
        g.Clear(Color.Transparent)
        g.DrawImageUnscaled(bg, 0, 0)
        g.SmoothingMode = SmoothingMode.AntiAlias
        for i in 0..<Kit.N
        {
            let c = opening[i]
            let pet = who[i]
            let ps = FitPs(i, pet)
            let fx = foot[i].X, fy = foot[i].Y - (i == 0 ? PedH() : 0)
            g.SetClip(c)
            if pet == nil && i == 0 && Pik { DrawRestFlower(g, c, t) }   //@fan
            else if pet == nil { if Orig { DrawMakeSlot(g, c, fx, fy) } else { DrawUnknown(g, fx, fy, ps) } }   //@fan
            // <public> if pet == nil { if Orig { DrawMakeSlot(g, c, fx, fy) } else { DrawUnknown(g, fx, fy, ps) } }
            else if outNow[i] { if pet!.P.Orig { pet!.OrigGhost(g, fx, fy, c, Night) } else { pet!.DrawGhost(g, fx, fy, ps, Night) }; DrawAway(g, c, fx, fy, ps) }
            else { pet!.DrawOnShelf(g, fx, fy, ps, c, t) }
            g.ResetClip()
            // 滑過：格子開口亮一圈
            if hover == i && (pet != nil || Orig)
            {
                let hp = Pen(Color.FromArgb(200, 255, 214, 90), Math.Max(2.0, Double(TU) * 0.7))
                g.DrawPath(hp, RoundRect(RectangleF(Double(c.X + 1), Double(c.Y + 1), Double(c.Width - 2), Double(c.Height - 2)), Double(TU)))
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

    // 外出中：空的地板（展示台）上一圈影子＋從格子頂上掛下來的小牌子；c＝開口，(fx, fy)＝公仔平常站的地方
    func DrawAway(_ g: Graphics, _ c: Rectangle, _ fx: Int, _ fy: Int, _ ps: Int)
    {
        let dps = Double(ps), dU = Double(U), dfx = Double(fx), cy = Double(c.Y)
        g.FillEllipse(SolidBrush(Color.FromArgb(70, 80, 50, 25)), fx - 5 * ps, fy - ps, 10 * ps, 2 * ps)
        let tagW = Math.Min(Double(c.Width - 6), Math.Max(13 * dps * 0.9, 15 * dU)), tagH = Math.Max(4.6 * dps, 5.2 * dU), ty = cy + Double(c.Height) * 0.3
        let lw = Math.Max(1.0, Double(TU) * 0.35)
        let str = Pen(Color.FromArgb(200, 0x3A, 0x2A, 0x1E), lw)
        g.DrawLine(str, dfx - tagW * 0.3, cy, dfx - tagW * 0.25, ty)
        g.DrawLine(str, dfx + tagW * 0.3, cy, dfx + tagW * 0.25, ty)
        let tr = RectangleF(dfx - tagW / 2, ty, tagW, tagH)
        let p = RoundRect(tr, dps)
        g.FillPath(SolidBrush(Night ? Color.FromArgb(235, 70, 58, 80) : Color.FromArgb(245, 255, 250, 238)), p)
        g.DrawPath(Pen(C(0x1E1E24), Math.Max(1.5, Double(TU) * 0.4)), p)
        let f = Font("Microsoft JhengHei UI", Math.Max(10.0, 2.7 * dps), FontStyle.Bold, GraphicsUnit.Pixel)
        let tb = SolidBrush(Night ? Color.FromArgb(0xFF, 0xE6, 0xC8) : Color.FromArgb(0x3A, 0x2A, 0x1E))
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
        if P.Cu { DrawCuShelf(g, fx, fy, ps, cell, tt) } else {
        switch P.Id
        {
            // <fan>
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
                // </fan>
            default:
                if P.Orig { DrawOrigShelf(g, fx, bx, by, ps, flip, tt, blink, cell); break }
                if blink { ReplaceFace(&head, "SLEEPY") }
                do { let rows = Pal.Stack(head, A("BODY"), A("LEGS_A")); DrawPix(g, rows, bx - (rows[0].utf8.count - 12) / 2 * ps, by + (16 - rows.count) * ps, ps, flip, false, true) }
                DrawAccessories(g, bx, by, ps, flip, 0, true)
        }
        }
        // 午餐時間：櫃子裡的公仔也拿著午餐
        if w.Lunch && !P.Cu && !(Is("spidey") && (tt % 11) < 8) { DrawLunchShelf(g, bx, by, ps, flip) }   //@fan
        // <public> if w.Lunch && !P.Cu { DrawLunchShelf(g, bx, by, ps, flip) }
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
