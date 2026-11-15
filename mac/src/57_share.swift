// 57_share.swift — port of extension/desktop/DeskPals.Share.cs
// Desk Pals：一鍵分享短片（離屏畫出來、自己寫的 GIF 編碼器）＋自己做的公仔匯出／匯入（.deskpal＝JSON 包 PNG）。
// 不擷取真的螢幕（隱私）；不連網；不用任何外部套件。
// mac: 剪貼簿 → NSPasteboard（同一個項目放檔案網址＋說明文字）；打開資料夾 → NSWorkspace.activateFileViewerSelecting；
//      存檔／開檔視窗 → NSSavePanel／NSOpenPanel（04_shim_custom_b.swift 的 CuDialogs）。GIF 編碼器逐行照搬，輸出的位元組跟 Windows 一樣。
import Foundation
import AppKit

// ================= GIF89a 編碼器（減色＋LZW，只用來存分享短片） =================
enum GifWriter {
    // frames：每格 ARGB（不透明）；delayCs：每格幾個 1/100 秒
    static func Write(_ path: String, _ frames: List<[Int]>, _ w: Int, _ h: Int, _ delayCs: Int) throws {
        // 1) 全部格子共用一組 255 色（取樣做中位切割）
        let samples = List<Int>()
        let stride = Math.Max(1, (w * h * frames.Count) / 400000)
        let off = 0
        var f = 0
        while f < frames.Count {
            let fr = frames[f]
            var i = off
            while i < fr.count { samples.Add(fr[i] | 0xFF000000); i += stride }
            f += 2
        }
        let pal = CuImg.MedianCut(samples, 255)
        var cache: [Int: UInt8] = [:]
        var idx: [[UInt8]] = []
        idx.reserveCapacity(frames.Count)
        for fi in 0..<frames.Count {
            let px = frames[fi]
            var o = [UInt8](repeating: 0, count: px.count)
            for i in 0..<px.count {
                let v = px[i] & 0xFFFFFF
                if let b = cache[v] { o[i] = b }
                else { let b = UInt8(truncatingIfNeeded: Nearest(pal, v)); cache[v] = b; o[i] = b }
            }
            idx.append(o)
        }
        var bw: [UInt8] = []
        bw.reserveCapacity(1 << 20)
        func U16(_ v: Int) { bw.append(UInt8(v & 255)); bw.append(UInt8((v >> 8) & 255)) }   // BinaryWriter.Write(ushort)：little-endian
        bw.append(contentsOf: Array("GIF89a".utf8))
        U16(w); U16(h)
        bw.append(0xF7); bw.append(0); bw.append(0)
        for i in 0..<256 {
            let c = i < pal.Count ? pal[i] : 0
            bw.append(UInt8((c >> 16) & 255)); bw.append(UInt8((c >> 8) & 255)); bw.append(UInt8(c & 255))
        }
        // 一直重播
        bw.append(contentsOf: [0x21, 0xFF, 0x0B])
        bw.append(contentsOf: Array("NETSCAPE2.0".utf8))
        bw.append(contentsOf: [0x03, 0x01, 0x00, 0x00, 0x00])
        for fi in 0..<idx.count {
            // 只存跟上一格不一樣的那一塊（檔案小很多）
            var x0 = 0, y0 = 0, x1 = w - 1, y1 = h - 1
            if fi > 0 {
                let a = idx[fi], p = idx[fi - 1]
                x0 = w; y0 = h; x1 = -1; y1 = -1
                for y in 0..<h {
                    for x in 0..<w {
                        if a[y * w + x] != p[y * w + x] { if x < x0 { x0 = x }; if x > x1 { x1 = x }; if y < y0 { y0 = y }; if y > y1 { y1 = y } }
                    }
                }
                if x1 < 0 { x0 = 0; y0 = 0; x1 = 0; y1 = 0 }
            }
            let rw = x1 - x0 + 1, rh = y1 - y0 + 1
            var sub = [UInt8](repeating: 0, count: rw * rh)
            let src = idx[fi]
            for y in 0..<rh { let s0 = (y0 + y) * w + x0, d0 = y * rw; for x in 0..<rw { sub[d0 + x] = src[s0 + x] } }
            bw.append(contentsOf: [0x21, 0xF9, 0x04, 0x04])
            U16(delayCs); bw.append(0); bw.append(0)
            bw.append(0x2C)
            U16(x0); U16(y0); U16(rw); U16(rh)
            bw.append(0)
            bw.append(8)
            Lzw(&bw, sub)
        }
        bw.append(0x3B)
        try File.WriteAllBytes(path, bw)
    }

    static func Nearest(_ pal: List<Int>, _ v: Int) -> Int {
        let r = (v >> 16) & 255, g = (v >> 8) & 255, b = v & 255
        var best = 0, bd = int.MaxValue
        for i in 0..<pal.Count {
            let p = pal[i], dr = ((p >> 16) & 255) - r, dg = ((p >> 8) & 255) - g, db = (p & 255) - b
            let dd = 3 * dr * dr + 4 * dg * dg + 2 * db * db
            if dd < bd { bd = dd; best = i }
        }
        return best
    }

    // LZW（GIF 版：8 位元起跳、最多 12 位元、滿了就清表）
    static func Lzw(_ bw: inout [UInt8], _ data: [UInt8]) {
        let clear = 256, eoi = 257
        var codeSize = 9, next = 258
        var dict: [Int: Int] = [:]
        var outb: [UInt8] = []
        var acc = 0, nbits = 0
        func emit(_ code: Int) {
            acc |= code << nbits; nbits += codeSize
            while nbits >= 8 { outb.append(UInt8(acc & 255)); acc >>= 8; nbits -= 8 }
        }
        emit(clear)
        var prefix = data.count > 0 ? Int(data[0]) : 0
        var i = 1
        while i < data.count {
            let k = Int(data[i]), key = (prefix << 8) | k
            if let code = dict[key] { prefix = code; i += 1; continue }
            emit(prefix)
            if next < 4096 {
                if next > (1 << codeSize) - 1 && codeSize < 12 { codeSize += 1 }
                dict[key] = next; next += 1
            } else {
                emit(clear)
                dict.removeAll(keepingCapacity: true); next = 258; codeSize = 9
            }
            prefix = k
            i += 1
        }
        emit(prefix)
        if next > (1 << codeSize) - 1 && codeSize < 12 { codeSize += 1 }
        emit(eoi)
        if nbits > 0 { outb.append(UInt8(acc & 255)) }
        var j = 0
        while j < outb.count {
            let n = Math.Min(255, outb.count - j)
            bw.append(UInt8(n))
            bw.append(contentsOf: outb[j..<(j + n)])
            j += 255
        }
        bw.append(0)
    }
}

// ================= 分享短片：照劇本畫出來（走進來 → 揮手打招呼 → 開心跳兩下冒愛心） =================
extension Pet {
    // 分享短片用：在指定位置、指定大小畫一格（不動到真的公仔）
    func ShareDraw(_ g: Graphics, _ feetX: Double, _ feetY: Double, _ ps: Int, _ st: String, _ an: Double, _ d: Int, _ vyHint: Double, _ landT: Double) {
        let wasOut = Out
        Out = true; state = st; anim = an; dir = d; vy = vyHint; rolling = false; Bt = 0; knock = 0; cuAct = ""; cuLandT = landT; poseKind = ""
        sc = Double(ps) / Double(S)
        x = feetX - Double(SW) / 2.0; y = feetY - Double(SH)
        PaintPet(g, 0, 0)
        sc = 1; Out = wasOut
    }
    func ShareLine(_ key: String) -> String { return L(key) }
}

//@@IN World
    var sharing2 = false
//@@END

extension World {
    // 選單：做分享短片（存到 圖片\Desk Pals、說明文字放進剪貼簿、打開資料夾）
    func ShareClip(_ who: Pet!) {
        if sharing2 { return }
        let dir = App.Offscreen ? Path.Combine(World.DataDir, "share") : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Desk Pals")
        ShareClipTo(dir, who)
    }

    func ShareClipTo(_ dir: String, _ who: Pet!) {
        if sharing2 { return }
        sharing2 = true
        var l0: Pet! = who
        if l0 == nil { l0 = Lead() }
        let l: Pet = l0
        l.Say("拍攝中…🎬 （大概 5 秒的小短片）", 2.5)
        Later(0.15) { [self] in
            // 主角：你點的那隻；從小屋拍的話，有自己做的公仔在外面就讓他當主角
            var star: Pet = l
            if who == nil && !l.P.Cu { for p in OutPets() { if p.P.Cu { star = p; break } } }
            let cast = List<Pal>()
            cast.Add(star.P)
            for p in OutPets() { if p !== star && cast.Count < 4 { cast.Add(p.P) } }
            let W0 = 540, H0 = 540, fps = 15, n = 5 * fps
            var caption: String! = nil
            let frames: List<[Int]> = ShareFrames(cast, W0, H0, fps, n, &caption)
            if frames.Count == 0 { App.Log("share: no frames"); sharing2 = false; l.Say("拍攝失敗了…再試一次？", 2.4); return }
            let name = "DeskPals-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".gif"
            let path = Path.Combine(dir, name)
            let cap: String = caption
            let th = Thread {
                var err: String! = nil
                do {
                    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)   // Directory.CreateDirectory
                    try GifWriter.Write(path, frames, W0, H0, 100 / fps)
                    try File.WriteAllText(Path.ChangeExtension(path, ".txt"), cap, UTF8Encoding(false))
                } catch { err = error.Message }
                let e2: String! = err
                self.Post { self.ShareDone(l, path, cap, e2) }
            }
            th.IsBackground = true
            th.Start()
        }
    }

    func ShareDone(_ l: Pet, _ path: String, _ caption: String, _ err: String!) {
        sharing2 = false
        if err != nil { App.Log("share: " + err); l.Say("存不起來…（" + err + "）", 3); return }
        let kb = FileInfo(path).Length / 1024
        App.Log("share saved " + path + " " + String(kb) + "KB")
        if !App.Offscreen {
            // 剪貼簿：同時放 GIF 檔（貼到聊天室＝傳圖）和說明文字（貼到文字框＝那句話）
            // mac: NSPasteboard，同一個項目放 public.file-url＋public.utf8-plain-text
            let pb = NSPasteboard.general
            pb.clearContents()
            let item = NSPasteboardItem()
            item.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
            item.setString(caption, forType: .string)
            if !pb.writeObjects([item]) { App.Log("share clipboard: write failed") }
            // mac: explorer /select → Finder 選取
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        l.Say("短片做好了！存在「圖片/Desk Pals」，說明文字也複製好了，直接貼上就能分享 🎬", 5)   // mac: 路徑分隔用 /
    }

    // 畫每一格：可愛的小桌面背景＋公仔照劇本動
    func ShareFrames(_ cast: List<Pal>, _ W0: Int, _ H0: Int, _ fps: Int, _ n: Int, _ caption: inout String!) -> List<[Int]> {
        let pw = World(S, Pal.Fallback)
        let pets = List<Pet>()
        var seed = 11
        for p in cast { pets.Add(Pet(pw, p, S, seed)); seed += 1 }
        let hero: Pal = cast[0]
        let heroPet: Pet = pets[0]
        caption = nil
        for p in pets { if p.P.Cu { caption = p.ShareLine("x_share"); break } }
        if string.IsNullOrEmpty(caption) { caption = "我的桌面公仔在螢幕上陪我上班 ✨ #我的桌面公仔 #DeskPals" }
        let hi = World.NoEmoji(heroPet.ShareLine("hi"))
        let ps = cast.Count == 1 ? 13 : (cast.Count == 2 ? 11 : (cast.Count == 3 ? 9 : 7))
        let frames = List<[Int]>()
        let bg = World.ShareBackground(W0, H0, hero)
        let fr = Bitmap(W0, H0, PixelFormat.Format32bppArgb, 1)   // mac: 1 倍（GIF 是 540×540 實際像素）
        let bf = FontT("Microsoft JhengHei UI", 15, FontStyle.Bold, GraphicsUnit.Pixel)
        let floor = Double(H0) * 0.80
        for i in 0..<n {
            let t = Double(i) / Double(fps)
            do {
                let g = Graphics.FromImage(fr)
                g.DrawImageUnscaled(bg, 0, 0)
                g.SmoothingMode = SmoothingMode.AntiAlias
                for j in 0..<pets.Count {
                    let tx = Double(W0 * (j + 1)) / Double(pets.Count + 1)
                    let t0 = Double(j) * 0.25, walkEnd = 1.9 + t0
                    let sx = -Double(W0) * 0.18 - Double(j) * Double(W0) * 0.1
                    var fx = tx, fy = floor, vyh = 0.0, land = 0.0
                    var st: String; var d = 1
                    if t < walkEnd {
                        let u = Math.Max(0.0, (t - t0) / (walkEnd - t0))
                        fx = sx + (tx - sx) * (1 - (1 - u) * (1 - u))
                        st = "walk"
                    }
                    else if t < 2.6 { st = "idle"; d = tx < Double(W0 / 2) ? 1 : -1 }
                    else if t < 3.5 { st = "wave"; d = tx < Double(W0 / 2) ? 1 : -1 }
                    else {
                        // 開心跳兩下
                        let c = (t - 3.5 - Double(j) * 0.08)
                        st = "hug"; d = tx < Double(W0 / 2) ? 1 : -1
                        let hc = c % 0.75
                        if c > 0 && c < 1.5 && hc < 0.5 { st = pets[j].P.Cu ? "air" : "hug"; let u = hc / 0.5; fy -= Math.Sin(u * Math.PI) * Double(ps) * 4; vyh = u < 0.5 ? -1 : 1 }
                        else if c > 0 && hc < 0.62 { land = 0.2 - (hc - 0.5) * 1.6 }
                    }
                    if pets.Count == 1 && t >= walkEnd { d = 1 }
                    pets[j].ShareDraw(g, fx, fy, ps, st, t, d, vyh, Math.Max(0.0, land))
                    // 愛心
                    if t >= 3.5 {
                        for k in 0..<3 {
                            let ph = ((t - 3.5) * 0.8 + Double(k) / 3.0) % 1
                            let hp = Math.Max(3, ps / 2)
                            let hx: Double = fx + Double((k - 1) * ps * 4) + Math.Sin(ph * 6 + Double(k)) * Double(ps)
                            let hy: Double = floor - Double(17 * ps) - ph * Double(ps) * 9
                            World.ShareHeart(g, hx, hy, hp, CInt(255 * Math.Min(1.0, (1 - ph) * 2.5)))
                        }
                    }
                }
                // 打招呼的泡泡
                if t >= 2.4 && t < 3.7 && !string.IsNullOrEmpty(hi) {
                    let tx = Double(W0) / Double(pets.Count + 1)
                    let rows: Double = hero.Cu ? hero.Spr.Hc : Double(16 + hero.TopRows)
                    World.ShareBubble(g, hi, bf, tx, floor - rows * Double(ps) - 22, W0, hero.Accent)
                }
            }
            frames.Add(CuImg.Pixels(fr))
        }
        return frames
    }

    static func ShareHeart(_ g: Graphics, _ cx: Double, _ cy: Double, _ u: Int, _ alpha: Int) {
        if alpha <= 10 { return }
        let h: [String] = [".pp.pp.", "ppppppp", "ppppppp", ".ppppp.", "..ppp..", "...p..."]
        let wb = SolidBrush(Color.FromArgb(alpha, 255, 255, 255))
        let pb = SolidBrush(Color.FromArgb(alpha, 0xFF, 0x6F, 0x9C))
        let x0 = CInt(cx - 3.5 * Double(u)), y0 = CInt(cy - 3 * Double(u))
        for pass in 0..<2 {
            for r in 0..<h.count {
                let row = Array(h[r])
                for c in 0..<row.count {
                    if row[c] == "." { continue }
                    if pass == 0 { g.FillRectangle(wb, x0 + c * u - u / 2, y0 + r * u - u / 2, 2 * u, 2 * u) }
                    else { g.FillRectangle(pb, x0 + c * u, y0 + r * u, u, u) }
                }
            }
        }
    }

    // 像素風泡泡（跟桌面上的一樣：切角方框＋往下的小尾巴）
    static func ShareBubble(_ g: Graphics, _ s: String, _ f: Font, _ cx: Double, _ bottom: Double, _ W0: Int, _ accent: Color) {
        let ts = TextRenderer.MeasureText(s, f, SizeT(4000, 400), TextFormatFlags.NoPadding)
        let w = ts.Width + 28, h = ts.Height + 18
        let x = CInt(Math.Max(10.0, Math.Min(Double(W0 - w - 10), cx - Double(w) / 2.0))), y = CInt(bottom - Double(h) - 8)
        let lb = SolidBrush(accent)
        let fill = SolidBrush(Color.White)
        g.SmoothingMode = SmoothingMode.None
        g.FillRectangle(lb, x + 3, y, w - 6, h); g.FillRectangle(lb, x, y + 3, w, h - 6); g.FillRectangle(lb, x + 1, y + 1, w - 2, h - 2)
        g.FillRectangle(fill, x + 4, y + 3, w - 8, h - 6); g.FillRectangle(fill, x + 3, y + 4, w - 6, h - 8)
        let tx = CInt(Math.Max(Double(x + 14), Math.Min(Double(x + w - 14), cx)))
        for i in 0..<9 { g.FillRectangle(lb, tx - 9 + i, y + h - 1 + i, 18 - 2 * i, 1) }
        for i in 0..<7 { g.FillRectangle(fill, tx - 7 + i, y + h - 3 + i, 14 - 2 * i, 1) }
        TextRenderer.DrawText(g, s, f, Rectangle(x, y, w, h), Color.FromArgb(0x2A, 0x2F, 0x45), [TextFormatFlags.HorizontalCenter, TextFormatFlags.VerticalCenter, TextFormatFlags.NoPadding])
    }

    // 背景：一面淡淡的牆（色帶）、窗戶、小星星、木頭桌面、右下角浮水印
    static func ShareBackground(_ W0: Int, _ H0: Int, _ hero: Pal) -> Bitmap {
        let b = Bitmap(W0, H0, PixelFormat.Format32bppArgb, 1)   // mac: 1 倍
        let g = Graphics.FromImage(b)
        let top = Pix.Mix(hero.Panel, Color.White, 0.35), bot = Pix.Mix(hero.Panel, Pix.C(0xF6D9C0), 0.45)
        let floorY = CInt(Double(H0) * 0.80), bands = 9
        for i in 0..<bands {
            let y0 = floorY * i / bands, y1 = floorY * (i + 1) / bands
            let sb = SolidBrush(Pix.Mix(top, bot, Double(i) / Double(bands - 1))); g.FillRectangle(sb, 0, y0, W0, y1 - y0)
        }
        // 窗戶（左上）
        let u = 6, wx = 46, wy = 54, ww = 22 * u, wh = 17 * u
        do { let fr = SolidBrush(Pix.C(0x9A6338)); g.FillRectangle(fr, wx - u, wy - u, ww + 2 * u, wh + 2 * u) }
        do { let sky = SolidBrush(Pix.C(0xBFE3F2)); g.FillRectangle(sky, wx, wy, ww, wh) }
        do { let cl = SolidBrush(Color.White); g.FillRectangle(cl, wx + 3 * u, wy + 4 * u, 6 * u, 2 * u); g.FillRectangle(cl, wx + 4 * u, wy + 3 * u, 3 * u, u); g.FillRectangle(cl, wx + 12 * u, wy + 9 * u, 5 * u, 2 * u) }
        do { let fr = SolidBrush(Pix.C(0x9A6338)); g.FillRectangle(fr, wx + ww / 2 - u / 2, wy, u, wh); g.FillRectangle(fr, wx, wy + wh / 2 - u / 2, ww, u) }
        // 小星星
        let r = Random(7)
        do {
            let st = SolidBrush(Color.FromArgb(200, 255, 255, 255))
            for _ in 0..<14 {
                let sx = 220 + r.Next(W0 - 250), sy = 30 + r.Next(floorY - 150)
                g.FillRectangle(st, sx, sy - 4, 4, 12); g.FillRectangle(st, sx - 4, sy, 12, 4)
            }
        }
        // 木頭桌面
        do { let d1 = SolidBrush(Pix.C(0xB97F4E)); g.FillRectangle(d1, 0, floorY, W0, H0 - floorY) }
        do { let d2 = SolidBrush(Pix.C(0xD9A06A)); g.FillRectangle(d2, 0, floorY, W0, 6) }
        do {
            let d3 = SolidBrush(Pix.C(0x9A6338))
            g.FillRectangle(d3, 0, floorY + 6, W0, 3)
            for _ in 0..<7 {
                // C# 的參數由左到右算：x、y、寬各抽一次亂數
                let rx = 30 + r.Next(W0 - 120)
                let ry = floorY + 24 + r.Next(H0 - floorY - 40)
                let rw = 40 + r.Next(60)
                g.FillRectangle(d3, rx, ry, rw, 3)
            }
        }
        // 浮水印
        do {
            let f = FontT("Microsoft JhengHei UI", 16, FontStyle.Bold, GraphicsUnit.Pixel)
            let s = "Desk Pals"
            let ts = TextRenderer.MeasureText(s, f, SizeT(4000, 400), TextFormatFlags.NoPadding)
            let tx = W0 - ts.Width - 18, ty = H0 - ts.Height - 14
            TextRenderer.DrawText(g, s, f, Point(tx + 1, ty + 1), Pix.C(0x7A4A28), TextFormatFlags.NoPadding)
            TextRenderer.DrawText(g, s, f, Point(tx, ty), Pix.C(0xFFF6E4), TextFormatFlags.NoPadding)
            do {
                let hb = SolidBrush(Pix.C(0xF27A90))
                let h: [String] = [".#.#.", "#####", ".###.", "..#.."]
                for rr in 0..<h.count { let row = Array(h[rr]); for c in 0..<row.count { if row[c] == "#" { g.FillRectangle(hb, tx - 22 + c * 3, ty + 4 + rr * 3, 3, 3) } } }
            }
        }
        return b
    }

    // ================= 匯出／匯入（.deskpal：一個 JSON，裡面是設定＋原圖 PNG 的 base64） =================
    static let MaxPalFile = 30 << 20

    func CuExportDialog(_ id: String) {
        let m: CuMeta! = CuStore.Get(id)
        if m == nil { return }
        if App.Offscreen { App.Log("custom: export dialog skipped (offscreen)"); return }
        // mac: SaveFileDialog → NSSavePanel
        guard let file = CuDialogs.Save("匯出「" + m.Name + "」", CuMeta.CleanName(m.Name) + ".deskpal", ["deskpal"], Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory)) else { return }
        if CuExport(id, file) { Lead().Say("匯出好了！把「" + Path.GetFileName(file) + "」傳給朋友，他在小屋按「匯入朋友的公仔」就能養 🧸", 5) }
    }

    @discardableResult
    func CuExport(_ id: String, _ path: String) -> Bool {
        let m: CuMeta! = CuStore.Get(id)
        if m == nil { return false }   // 只有自己做的公仔能匯出（內建的不行）
        do {
            let src = try File.ReadAllBytes(Path.Combine(CuStore.Dir(id), "source.png"))
            guard let meta = try JavaScriptSerializer().DeserializeObject(m.ToJson()) as? Dict<String, Any> else { return false }
            meta.Remove("id"); meta.Remove("created")
            let d = Dict<String, Any>()
            d["deskpal"] = 1; d["app"] = "Desk Pals"; d["meta"] = meta; d["source"] = Data(src).base64EncodedString()   // Convert.ToBase64String
            let js = JavaScriptSerializer(); js.MaxJsonLength = int.MaxValue
            try File.WriteAllText(path, js.Serialize(d), UTF8Encoding(false))
            App.Log("custom exported " + id + " -> " + path)
            return true
        }
        catch { App.Log("export: " + error.Message); Lead().Say("匯出失敗了…（" + error.Message + "）", 3); return false }
    }

    func CuImportDialog(_ first: Bool) {
        if App.Offscreen { App.Log("custom: import dialog skipped (offscreen)"); if first { ShowSetup(true) }; return }
        // mac: OpenFileDialog → NSOpenPanel（只列 .deskpal）
        guard let file = CuDialogs.Open("匯入朋友的公仔", ["deskpal"], Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory)) else { if first { ShowSetup(true) }; return }
        CuImportFile(file, first)
    }

    // Convert.ToInt32(object)
    static func CuToInt32(_ o: Any?) throws -> Int {
        guard let o = o, !(o is NSNull) else { return 0 }
        if let b = o as? Bool { return b ? 1 : 0 }
        if let i = o as? Int { return i }
        if let d = o as? Double { return CInt(Math.Round(d)) }
        if let s = o as? String { var v = 0; if int.TryParse(s, &v) { return v }; throw FormatException("Input string was not in a correct format.") }
        throw FormatException("Unable to cast object to type 'System.IConvertible'.")
    }

    // 讀進來每一樣都檢查：檔案大小、JSON、圖片解得開、名字清乾淨；id 一律重新產生（不信任檔案裡的路徑、id）
    func CuImportFile(_ path: String, _ first: Bool) {
        var err: String! = nil, newId: String! = nil
        do {
            let fi = FileInfo(path)
            if !fi.Exists { err = "找不到這個檔案" }
            else if fi.Length > World.MaxPalFile { err = "檔案太大了（超過 30MB），應該不是公仔檔" }
            else {
                let js = JavaScriptSerializer(); js.MaxJsonLength = World.MaxPalFile * 2
                let text = try File.ReadAllText(path, Encoding.UTF8)
                let d = try js.DeserializeObject(text) as? Dict<String, Any>
                var ver: Any? = nil, mo: Any? = nil, so: Any? = nil
                var isPal = false   // C#：d == null || !TryGetValue || Convert.ToInt32(ver) != 1（短路：前面不成立才轉）
                if d != nil && d!.TryGetValue("deskpal", &ver) { isPal = try World.CuToInt32(ver) == 1 }
                if !isPal { err = "這不是 Desk Pals 的公仔檔" }
                else if !d!.TryGetValue("meta", &mo) || !(mo is Dict<String, Any>) || !d!.TryGetValue("source", &so) || !(so is String) { err = "公仔檔缺東西（可能壞掉了）" }
                else {
                    let m: CuMeta = CuMeta.FromDict(mo as! Dict<String, Any>)
                    let b64 = so as! String
                    if b64.Length > World.MaxPalFile * 4 / 3 + 16 { err = "公仔檔裡的圖太大了" }
                    else {
                        // Convert.FromBase64String：空白略過，其他不合法就丟例外
                        let clean = b64.filter { !($0 == " " || $0 == "\t" || $0 == "\r" || $0 == "\n") }
                        guard let pngData = Data(base64Encoded: clean) else { throw FormatException("The input is not a valid Base-64 string as it contains a non-base 64 character, more than two padding characters, or an illegal character among the padding characters.") }
                        let png = [UInt8](pngData)
                        var e2: String! = nil
                        let src: Bitmap! = CuImg.Decode(png, m.Sheet ? 1400 : CuImg.MaxSrc, &e2)
                        if src == nil { err = e2 }
                        else {
                            let s: CuSprite! = CuSprite.Build(m, src, &e2)
                            if s == nil { err = e2; src.Dispose() }
                            else {
                                m.Id = CuStore.NewId(); m.Created = ""
                                if m.Name == "" { m.Name = "朋友的公仔" }
                                try CuStore.Save(m, src, s)
                                src.Dispose()
                                newId = m.Id
                                App.Log("custom imported " + newId + " name=" + m.Name)
                            }
                        }
                    }
                }
            }
        }
        catch { err = "這個檔案打不開（" + error.Message + "）" }
        if newId == nil {
            App.Log("import failed: " + (err ?? ""))
            Lead().Say("匯入失敗：" + (err ?? ""), 4)
            if first { ShowSetup(true) }
            return
        }
        CuCreated(newId, first, false)
    }
}
