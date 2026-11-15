// 53_custom.swift — port of extension/desktop/DeskPals.Custom.cs
// Desk Pals：自己做的公仔（上傳一張圖／動作表）。資料、處理好的圖、畫法、動作、我的櫃。
// 圖片處理在 55_custom_image.swift、做公仔的視窗在 56_custom_make.swift、台詞在 54_custom_lines.swift、分享短片／匯出匯入在 57_share.swift。
// mac: GDI+ 的 Matrix → CGAffineTransform（03_shim_custom_a.swift，同樣是 prepend）；ColorMatrix 在 ImageAttributes 裡逐像素套（01_drawing／03_shim_custom_a）；
//      逐像素的白邊、晚上變暗是在 Bitmap 的裝置像素上做（Retina 的 cuOut 是 2 倍，白邊寬度跟著乘）。
import Foundation
import AppKit

// ================= 一隻自己做的公仔的設定（custom/<id>/meta.json）=================
final class CuMeta
{
    var Id = "", Name = "", Persona = "lively", Mode = "pixel", Created = ""
    var Sub = 2                  // 像素風：1＝跟內建一樣大的像素、2＝細緻（像素小一半）
    var Flip = false, Rig = false, Sheet = false, UseAlpha = true
    var Neck: Double = -1, Hip: Double = -1   // 兩條線（0～1，處理後的圖從上往下）；-1＝自動猜
    var Tol = 22                 // 去背強度 0～100
    var Strokes = List<[Double]>()   // 筆刷：x, y, 半徑（0～1）, 1＝擦掉 0＝補回

    var Pixel: Bool { return Mode != "smooth" }

    init() {}

    func Clone() -> CuMeta
    {
        // C# MemberwiseClone
        let m = CuMeta()
        m.Id = Id; m.Name = Name; m.Persona = Persona; m.Mode = Mode; m.Created = Created
        m.Sub = Sub; m.Flip = Flip; m.Rig = Rig; m.Sheet = Sheet; m.UseAlpha = UseAlpha
        m.Neck = Neck; m.Hip = Hip; m.Tol = Tol
        m.Strokes = List<[Double]>()
        for s in Strokes { m.Strokes.Add(s) }
        return m
    }

    func ToJson() -> String
    {
        let d = Dict<String, Any>()
        d["v"] = 1; d["id"] = Id; d["name"] = Name; d["persona"] = Persona; d["mode"] = Mode; d["sub"] = Sub
        d["flip"] = Flip; d["rig"] = Rig; d["sheet"] = Sheet; d["useAlpha"] = UseAlpha
        d["neck"] = Neck; d["hip"] = Hip; d["tol"] = Tol; d["created"] = Created
        var st: [Any] = []
        for s in Strokes { let row: [Any] = [Math.Round(s[0], 4), Math.Round(s[1], 4), Math.Round(s[2], 4), s[3] > 0.5 ? 1 : 0]; st.append(row) }
        d["strokes"] = st
        return JavaScriptSerializer().Serialize(d)
    }

    // mac: C# Convert.ToDouble(object)（數字、布林、字串）；轉不了＝nil（C# 會丟例外）
    static func ToD(_ o: Any?) -> Double?
    {
        guard let o = o else { return nil }
        if o is NSNull { return nil }
        if let i = o as? Int { return Double(i) }
        if let v = o as? Double { return v }
        if let b = o as? Bool { return b ? 1 : 0 }
        if let s = o as? String { var v: Double = 0; if double.TryParse(s, &v) { return v }; return nil }
        return nil
    }

    static func S(_ d: Dict<String, Any>, _ k: String, _ def: String) -> String { if let s = d.Get(k) as? String { return s }; return def }
    static func N(_ d: Dict<String, Any>, _ k: String, _ def: Double) -> Double
    {
        guard let v = ToD(d.Get(k)) else { return def }
        return v.isNaN || v.isInfinite ? def : v
    }
    static func B(_ d: Dict<String, Any>, _ k: String, _ def: Bool) -> Bool { if let b = d.Get(k) as? Bool { return b }; return def }

    // 讀 JSON（不認得的欄位不管；每個值都檢查過）
    static func FromJson(_ json: String) -> CuMeta!
    {
        let js = JavaScriptSerializer()
        js.MaxJsonLength = 1 << 20
        guard let o = try? js.DeserializeObject(json), let d = o as? Dict<String, Any> else { return nil }
        return FromDict(d)
    }

    static func FromDict(_ d: Dict<String, Any>) -> CuMeta
    {
        let m = CuMeta()
        m.Id = S(d, "id", "")
        m.Name = CleanName(S(d, "name", ""))
        m.Persona = Pal.Personas.contains(S(d, "persona", "lively")) ? S(d, "persona", "lively") : "lively"
        m.Mode = S(d, "mode", "pixel") == "smooth" ? "smooth" : "pixel"
        m.Sub = N(d, "sub", 2) >= 1.5 ? 2 : 1
        m.Flip = B(d, "flip", false); m.Rig = B(d, "rig", false); m.Sheet = B(d, "sheet", false); m.UseAlpha = B(d, "useAlpha", true)
        m.Neck = N(d, "neck", -1); m.Hip = N(d, "hip", -1)
        if m.Neck > 0.9 || m.Neck < 0.05 { m.Neck = -1 }
        if m.Hip > 0.98 || m.Hip < 0.1 { m.Hip = -1 }
        m.Tol = CInt(Math.Max(0.0, Math.Min(100.0, N(d, "tol", 22))))
        m.Created = S(d, "created", "")
        if m.Created.Length > 40 { m.Created = "" }
        if let so = d.Get("strokes") as? [Any]
        {
            for o in so
            {
                guard let a = o as? [Any] else { continue }
                if a.count < 4 || m.Strokes.Count >= 4000 { continue }
                var s = [Double](repeating: 0, count: 4)
                var bad = false
                for i in 0..<4 { if let v = ToD(a[i]) { s[i] = v } else { bad = true } }
                if bad { continue }
                if s[0] < -0.2 || s[0] > 1.2 || s[1] < -0.2 || s[1] > 1.2 || s[2] <= 0 || s[2] > 0.5 { continue }
                m.Strokes.Add(s)
            }
        }
        return m
    }

    // 名字：去掉換行、控制字元、大括號（台詞代換用）、路徑字元；最多 10 個字
    static func CleanName(_ s: String!) -> String
    {
        if s == nil { return "" }
        var u: [UInt16] = []
        for c in s.Trim().utf16
        {
            // char.IsControl：U+0000–001F、U+007F–009F
            if c < 0x20 || (c >= 0x7F && c <= 0x9F) { continue }
            switch c { case 0x7B, 0x7D, 0x5C, 0x2F, 0x3C, 0x3E, 0x7C, 0x22, 0x2A, 0x3F, 0x3A: continue; default: break }   // { } \ / < > | " * ? :
            u.append(c)
            if u.count >= 10 { break }
        }
        return String(decoding: u, as: UTF16.self).Trim()
    }

    static func ValidId(_ id: String!) -> Bool
    {
        if string.IsNullOrEmpty(id) || id.Length < 4 || id.Length > 14 || !id.StartsWith("cu") { return false }
        for c in id.utf16 { if !((c >= 97 && c <= 122) || (c >= 48 && c <= 57)) { return false } }
        return true
    }
}

// ================= 處理好、可以畫的圖 =================
final class CuSprite
{
    var Pixel = false
    var R = 1                     // 一格幾個內部像素
    var Stand: Bitmap! = nil      // 站好的樣子（已裁切）
    var W = 0, H = 0
    var Rig = false
    var Neck = 0, Hip = 0, Split = 0      // 兩條線、兩隻腳的分界（內部像素）
    var NeckF: Double = 0, HipF: Double = 0        // 0～1
    var Head: Bitmap! = nil, Body: Bitmap! = nil, LegL: Bitmap! = nil, LegR: Bitmap! = nil
    var BodyY0 = 0                // 身體那張從第幾列開始（往上多切一點，頭動的時候不會有縫）
    var HeadTop = 0, HeadCx = 0, HeadW = 0, NeckCx = 0, NeckW = 0
    var Main = Color.Gray, Outline = Color.FromArgb(0x2A, 0x2F, 0x45)
    let Frames = Dict<String, Bitmap>()   // 動作表：stand walk1 walk2 jump sleep happy held sit
    var Wc: Double { return Double(W) / Double(R) }
    var Hc: Double { return Double(H) / Double(R) }
    func HasFrame(_ k: String) -> Bool { return Frames.ContainsKey(k) }

    init() {}

    static let SheetKeys: [String] = ["stand", "walk1", "walk2", "jump", "sleep", "happy", "held", "sit"]
    static let SheetLabels: [String] = ["站", "走 1", "走 2", "跳", "睡", "開心", "被抓", "坐"]

    // 站姿圖準備好：量頭、脖子，切成頭／身體／兩隻腳
    func SetStand(_ c: CuCut, _ rig: Bool, _ neck: Double, _ hip: Double)
    {
        Stand = CuImg.ToBitmap(c); W = c.W; H = c.H
        var gn: Double = 0, gh: Double = 0; var conf = false
        CuImg.GuessLines(c, &gn, &gh, &conf)
        NeckF = neck > 0 ? neck : gn; HipF = hip > 0 ? hip : gh
        if HipF < NeckF + 0.1 { HipF = Math.Min(0.95, NeckF + 0.25) }
        Neck = Math.Max(1, Math.Min(H - 3, CInt(Math.Round(NeckF * Double(H)))))
        Hip = Math.Max(Neck + 2, Math.Min(H - 1, CInt(Math.Round(HipF * Double(H)))))
        Split = CuImg.LegSplit(c, Hip)
        Rig = rig && H >= 6
        let px: [Int] = c.Px
        // 頭頂、頭的寬度（頭最上面三格的範圍）、脖子寬度
        HeadTop = 0
        var y = 0
        while y < H
        {
            var any = false
            var x = 0
            while x < W { if ((px[y * W + x] >> 24) & 255) >= 110 { any = true; break }; x += 1 }
            if any { HeadTop = y; break }
            y += 1
        }
        var l = W, r = -1
        let band = Math.Min(Neck, HeadTop + 3 * R)
        y = HeadTop
        while y < Math.Max(HeadTop + 1, band)
        {
            var x = 0
            while x < W { if ((px[y * W + x] >> 24) & 255) >= 110 { if x < l { l = x }; if x > r { r = x } }; x += 1 }
            y += 1
        }
        if r < 0 { l = 0; r = W - 1 }
        HeadCx = (l + r + 1) / 2; HeadW = r - l + 1
        l = W; r = -1
        var x = 0
        while x < W { if ((px[Math.Min(H - 1, Neck) * W + x] >> 24) & 255) >= 110 { if x < l { l = x }; if x > r { r = x } }; x += 1 }
        if r < 0 { l = 0; r = W - 1 }
        NeckCx = (l + r + 1) / 2; NeckW = r - l + 1
        Main = CuImg.MainColor(c)
        CutParts()
    }

    func CutParts()
    {
        DisposeParts()
        let e = Math.Max(1, R / 2)
        BodyY0 = Math.Max(0, Neck - e)
        Head = Part(0, 0, W, Neck)
        Body = Part(0, BodyY0, W, Math.Min(H, Hip + e) - BodyY0)
        LegL = Part(0, Hip, Math.Max(1, Split), H - Hip)
        LegR = Part(Split, Hip, Math.Max(1, W - Split), H - Hip)
    }

    func Part(_ x: Int, _ y: Int, _ w0: Int, _ h0: Int) -> Bitmap
    {
        let w = Math.Max(1, Math.Min(w0, W - x)), h = Math.Max(1, Math.Min(h0, H - y))
        return Stand.Clone(Rectangle(x, y, w, h), PixelFormat.Format32bppArgb)
    }

    func DisposeParts() { for b in [Head, Body, LegL, LegR] { if b != nil { b!.Dispose() } } }

    func Dispose()
    {
        DisposeParts()
        for b in Frames.Values { if b !== Stand { b.Dispose() } }
        if Stand != nil { Stand.Dispose() }
    }

    // ---------- 做出來：一張圖 ----------
    static func Build(_ m: CuMeta, _ src: Bitmap!, _ err: inout String!) -> CuSprite!
    {
        err = nil
        if src == nil { err = "沒有圖"; return nil }
        if m.Sheet { return BuildSheet(m, src, &err) }
        var hadAlpha = false
        var cut: CuCut! = CuImg.Cutout(src, m.UseAlpha, m.Tol, m.Strokes, &hadAlpha)
        if cut == nil { err = "去背之後什麼都不剩了，把去背強度調低一點"; return nil }
        if m.Flip { cut = CuImg.Mirror(cut) }
        let s = CuSprite()
        s.Pixel = m.Pixel
        var fin: CuCut! = nil
        if s.Pixel { var ol = Color.Empty; fin = CuImg.ToPixel(cut, m.Sub, Double(CuImg.HCells), Double(CuImg.WCells), &ol); s.Outline = ol; s.R = m.Sub }
        else { fin = CuImg.ToSmooth(cut, Double(CuImg.HCells), Double(CuImg.WCells)); s.R = CuImg.SmoothR; s.Outline = Darker(CuImg.MainColor(fin)) }
        s.SetStand(fin, m.Rig, m.Neck, m.Hip)
        return s
    }

    static func Darker(_ c: Color) -> Color { return Color.FromArgb(CInt(Double(c.R) * 0.25 + Double(0x2A) * 0.4), CInt(Double(c.G) * 0.25 + Double(0x2F) * 0.4), CInt(Double(c.B) * 0.25 + Double(0x45) * 0.45)) }

    // ---------- 動作表範本：4×2 格，每格 128×128，上面有標籤 ----------
    static let TCell = 128, TLab = 26, TGap = 16, THead = 64, TCols = 4, TRows = 2
    static var TW: Int { return TGap + TCols * (TCell + TGap) }
    static var TH: Int { return THead + TRows * (TLab + TCell + TGap) }
    static func TCellRect(_ i: Int) -> Rectangle { let c = i % TCols, r = i / TCols; return Rectangle(TGap + c * (TCell + TGap), THead + r * (TLab + TCell + TGap) + TLab, TCell, TCell) }

    static func Template() -> Bitmap
    {
        let b = Bitmap(TW, TH, PixelFormat.Format32bppArgb)
        do {
            let g = Graphics.FromImage(b)
            let tf = Font("Microsoft JhengHei UI", 15, FontStyle.Bold, GraphicsUnit.Pixel)
            let hf = Font("Microsoft JhengHei UI", 11, FontStyle.Bold, GraphicsUnit.Pixel)
            let lf = Font("Microsoft JhengHei UI", 13, FontStyle.Bold, GraphicsUnit.Pixel)
            let paper = SolidBrush(Color.FromArgb(0xFF, 0xF6, 0xE4))
            let ink = SolidBrush(Color.FromArgb(0x4A, 0x30, 0x10))
            let dim = SolidBrush(Color.FromArgb(0x9A, 0x63, 0x38))
            let edge = Pen(Color.FromArgb(0xC9, 0xB0, 0x8A), 2)
            let mark = SolidBrush(Color.FromArgb(0xE2, 0x7A, 0x5A))
            g.Clear(Color.Transparent)
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit
            // 格子外面是奶油色紙；格子裡面透明（畫圖軟體不支援透明的話，白底也可以，會自動去背）
            g.FillRectangle(paper, 0, 0, TW, TH)
            g.DrawString("Desk Pals 動作表範本", tf, ink, TGap, 10)
            g.DrawString("每一格畫一個動作，腳踩在格子底部。空著的格子會自動補動畫（至少畫「站」）。", hf, dim, TGap, 36)
            for i in 0..<SheetKeys.count
            {
                let r = TCellRect(i)
                g.DrawString(SheetLabels[i] + (i == 0 ? "（必畫）" : ""), lf, ink, r.X, r.Y - TLab + 4)
                g.CompositingMode = CompositingMode.SourceCopy
                do { let clear = SolidBrush(Color.Transparent); g.FillRectangle(clear, r) }
                g.CompositingMode = CompositingMode.SourceOver
                g.DrawRectangle(edge, r.X - 2, r.Y - 2, r.Width + 3, r.Height + 3)
                // 地面記號：格子左右兩邊外面的小三角形
                g.FillPolygon(mark, [Point(r.X - 9, r.Bottom - 5), Point(r.X - 3, r.Bottom - 1), Point(r.X - 9, r.Bottom + 3)])
                g.FillPolygon(mark, [Point(r.Right + 8, r.Bottom - 5), Point(r.Right + 2, r.Bottom - 1), Point(r.Right + 8, r.Bottom + 3)])
            }
        }
        return b
    }

    // ---------- 做出來：動作表 ----------
    static func BuildSheet(_ m: CuMeta, _ src: Bitmap, _ err: inout String!) -> CuSprite!
    {
        err = nil
        let ar = Double(src.Width) / Double(src.Height), tar = Double(TW) / Double(TH)
        if Math.Abs(ar - tar) > tar * 0.04 || src.Width < TW / 3 { err = "這張不是動作表範本（尺寸對不上）。先按「下載範本」，畫好再上傳"; return nil }
        let sc = Double(src.Width) / Double(TW)
        let px: [Int] = CuImg.Pixels(src)
        var cells = [CuCut?](repeating: nil, count: SheetKeys.count)
        for i in 0..<SheetKeys.count
        {
            let r = TCellRect(i)
            let inset = CInt(Math.Ceiling(3 * sc))
            var rr = Rectangle.FromLTRB(CInt(Double(r.X) * sc) + inset, CInt(Double(r.Y) * sc) + inset, CInt(Double(r.Right) * sc) - inset, CInt(Double(r.Bottom) * sc) - inset)
            rr.Intersect(Rectangle(0, 0, src.Width, src.Height))
            if rr.Width < 4 || rr.Height < 4 { continue }
            let c: CuCut = CuImg.Crop(px, src.Width, src.Height, rr)
            var cut: [Int]
            if CuImg.HasAlpha(c.Px, c.W, c.H) && m.UseAlpha
            {
                cut = c.Px
                for k in 0..<cut.count { if ((cut[k] >> 24) & 255) < 10 { cut[k] = 0 } }
            }
            else
            {
                var solid: [Int] = c.Px
                for k in 0..<solid.count { if ((solid[k] >> 24) & 255) < 128 { solid[k] = CuSprite.ARGB_WHITE } else { solid[k] |= CuSprite.ARGB_OPAQUE } }
                cut = CuImg.RemoveBg(solid, c.W, c.H, m.Tol)
            }
            let bb = CuImg.Bounds(cut, c.W, c.H, 40)
            var area = 0; for v in cut { if ((v >> 24) & 255) >= 110 { area += 1 } }
            if bb.Width < 2 || bb.Height < 2 || area < c.W * c.H / 200 { continue }   // 空格
            var f: CuCut = CuImg.Crop(cut, c.W, c.H, bb)
            if m.Flip { f = CuImg.Mirror(f) }
            cells[i] = f
        }
        if cells[0] == nil { err = "動作表的「站」那格是空的（至少要畫「站」）"; return nil }
        let s = CuSprite()
        s.Pixel = m.Pixel
        s.R = s.Pixel ? m.Sub : CuImg.SmoothR
        // 同一個比例：「站」那格的高度＝16 格；別格也照這個比例（太大的再縮）
        let unit: Double = s.Pixel ? Double(m.Sub) : Double(CuImg.SmoothR)
        let c0: CuCut = cells[0]!
        var k0 = Math.Min((Double(CuImg.HCells) * unit - (s.Pixel ? 2.0 : 0.0)) / Double(c0.H), (Double(CuImg.WCells) * unit - (s.Pixel ? 2.0 : 0.0)) / Double(c0.W))
        for c in cells { if let c = c { k0 = Math.Min(k0, Math.Min(20 * unit / Double(c.H), 22 * unit / Double(c.W))) } }
        var outs = [CuCut?](repeating: nil, count: cells.count)
        var cw = 1, ch = 1
        for i in 0..<cells.count
        {
            guard let ci = cells[i] else { continue }
            let tw = Math.Max(1, CInt(Math.Round(Double(ci.W) * k0))), th = Math.Max(1, CInt(Math.Round(Double(ci.H) * k0)))
            var oi: CuCut! = nil
            if s.Pixel { var ol = Color.Empty; oi = CuImg.ToPixelSized(ci, tw, th, m.Sub >= 2 ? 18 : 12, false, &ol); if i == 0 { s.Outline = ol } }
            else { oi = CuImg.ToSmoothSized(ci, tw, th) }
            outs[i] = oi
            cw = Math.Max(cw, oi.W); ch = Math.Max(ch, oi.H)
        }
        if !s.Pixel { s.Outline = Darker(CuImg.MainColor(outs[0]!)) }
        // 全部放進同樣大小的框：底部置中（腳踩地）
        for i in 0..<outs.count
        {
            guard let oi = outs[i] else { continue }
            let o = CuCut(); o.W = cw; o.H = ch
            var opx = [Int](repeating: 0, count: cw * ch)
            let ox = (cw - oi.W) / 2, oy = ch - oi.H
            let ipx: [Int] = oi.Px
            for y in 0..<oi.H { for x in 0..<oi.W { opx[(oy + y) * cw + ox + x] = ipx[y * oi.W + x] } }
            o.Px = opx
            if i == 0 { s.SetStand(o, false, -1, -1) }
            else { s.Frames[SheetKeys[i]] = CuImg.ToBitmap(o) }
        }
        s.Frames["stand"] = s.Stand
        return s
    }
    // C# unchecked((int)0xFFFFFFFF)／unchecked((int)0xFF000000)（mac：像素一律存成不帶正負號的 0xAARRGGBB，跟 55_custom_image 一樣）
    static let ARGB_WHITE = 0xFFFFFFFF
    static let ARGB_OPAQUE = 0xFF000000

    // ---------- 存／讀（處理好的圖存成 PNG，下次直接讀） ----------
    func SaveTo(_ dir: String)
    {
        Stand.Save(Path.Combine(dir, "sprite.png"), ImageFormat.Png)
        for kv in Frames { if kv.Key != "stand" { kv.Value.Save(Path.Combine(dir, "frame-" + kv.Key + ".png"), ImageFormat.Png) } }
        let d = Dict<String, Any>()
        d["pixel"] = Pixel; d["r"] = R; d["neck"] = NeckF; d["hip"] = HipF; d["rig"] = Rig; d["outline"] = Outline.ToArgb()
        try? File.WriteAllText(Path.Combine(dir, "sprite.json"), JavaScriptSerializer().Serialize(d))
    }

    static func LoadFrom(_ dir: String, _ m: CuMeta) -> CuSprite!
    {
        let sj = Path.Combine(dir, "sprite.json"), sp = Path.Combine(dir, "sprite.png")
        if !File.Exists(sj) || !File.Exists(sp) { return nil }
        guard let txt = try? File.ReadAllText(sj), let o = try? JavaScriptSerializer().DeserializeObject(txt), let d = o as? Dict<String, Any> else { return nil }
        let s = CuSprite()
        s.Pixel = (d.Get("pixel") as? Bool) == true
        if s.Pixel != m.Pixel { return nil }
        // mac: C# 的 d["r"]（沒有那個 key 會丟例外 → catch → null）
        guard let r = CuMeta.ToD(d.Get("r")), let ol = CuMeta.ToD(d.Get("outline")), let neck = CuMeta.ToD(d.Get("neck")), let hip = CuMeta.ToD(d.Get("hip")) else { App.Log("custom sprite load: " + "bad sprite.json"); return nil }
        s.R = CInt(Math.Round(r))
        if s.R < 1 || s.R > 8 { return nil }
        s.Outline = Color.FromArgb(CInt(Math.Round(ol)))
        let rig = (d.Get("rig") as? Bool) == true
        var c: CuCut! = nil
        do {
            let b: Bitmap! = LoadPng(sp)
            if b == nil || b.Width > 400 || b.Height > 400 { return nil }
            c = CuImg.FromBitmap(b)
        }
        s.SetStand(c, rig, neck, hip)
        if m.Sheet
        {
            s.Frames["stand"] = s.Stand
            for i in 1..<SheetKeys.count
            {
                let fp = Path.Combine(dir, "frame-" + SheetKeys[i] + ".png")
                if !File.Exists(fp) { continue }
                let fb: Bitmap! = LoadPng(fp)
                if fb != nil && fb.Width == s.W && fb.Height == s.H { s.Frames[SheetKeys[i]] = fb } else if fb != nil { fb.Dispose() }
            }
        }
        return s
    }

    // mac: Image.FromStream → CGImageSource（Bitmap.FromFile），再複製成一張 32bppArgb
    static func LoadPng(_ path: String) -> Bitmap!
    {
        guard let img = Bitmap.FromFile(path) else { return nil }
        let b = Bitmap(img.Width, img.Height, PixelFormat.Format32bppArgb, img.Scale)
        do { let g = Graphics.FromImage(b); g.CompositingMode = CompositingMode.SourceCopy; g.DrawImage(img, Rectangle(0, 0, img.Width, img.Height)) }
        return b
    }
}

// ================= 存放：資料夾 custom/<id>/（source.png 原圖、meta.json 設定、sprite.png 處理好的圖、icon.png 給 VS Code）=================
enum CuStore
{
    static var Root: String { return Path.Combine(World.DataDir, "custom") }
    static var metas: List<CuMeta>! = nil
    static let sprites = Dict<String, CuSprite>()

    static func All() -> List<CuMeta>
    {
        if metas != nil { return metas }
        let ms = List<CuMeta>()
        metas = ms
        if Directory.Exists(Root)
        {
            for d in Directory.GetDirectories(Root)
            {
                let id = Path.GetFileName(d)
                if !CuMeta.ValidId(id) { continue }
                let mp = Path.Combine(d, "meta.json")
                if !File.Exists(mp) || FileInfo(mp).Length > (1 << 20) { continue }
                guard let txt = try? File.ReadAllText(mp, Encoding.UTF8) else { App.Log("custom list: " + "cannot read " + mp); continue }
                let m: CuMeta! = CuMeta.FromJson(txt)
                if m == nil { continue }
                m.Id = id
                if m.Name == "" { m.Name = "小公仔" }
                ms.Add(m)
            }
        }
        ms.Sort { (a: CuMeta, b: CuMeta) -> Int in let c = string.CompareOrdinal(a.Created, b.Created); return c != 0 ? c : string.CompareOrdinal(a.Id, b.Id) }
        return ms
    }

    static func Get(_ id: String!) -> CuMeta! { for m in All() { if m.Id == id { return m } }; return nil }
    static func Dir(_ id: String) -> String { return Path.Combine(Root, id) }

    static func Sprite(_ m: CuMeta) -> CuSprite!
    {
        if let s0 = sprites.Get(m.Id) { return s0 }
        let dir = Dir(m.Id)
        var s: CuSprite! = CuSprite.LoadFrom(dir, m)
        if s == nil
        {
            // 沒有處理好的圖（或版本不對）：從原圖重做一次
            var err: String! = nil
            let src: Bitmap! = CuImg.LoadFile(Path.Combine(dir, "source.png"), &err)
            if src != nil
            {
                s = CuSprite.Build(m, src, &err)
                src.Dispose()
                if s != nil { s.SaveTo(dir) }
            }
            if s == nil { App.Log("custom sprite " + m.Id + ": " + (err ?? "")) }
        }
        if s != nil { sprites[m.Id] = s }
        return s
    }

    static func NewId() -> String
    {
        let r = Random()
        let cs = "abcdefghijkmnpqrstuvwxyz23456789"
        for _ in 0..<100
        {
            let sb = StringBuilder("cu")
            for _ in 0..<6 { sb.Append(cs[r.Next(cs.Length)]) }
            let id = sb.ToString()
            if !Directory.Exists(Dir(id)) && Pal.GetBuiltin(id) == nil { return id }
        }
        return "cu" + DateTime.Now.Ticks.ToString("x").Substring(0, 8)
    }

    // 存一隻（新的或改過的）：原圖、設定、處理好的圖、VS Code 用的小圖
    static func Save(_ m: CuMeta, _ source: Bitmap!, _ s: CuSprite) throws
    {
        let dir = Dir(m.Id)
        try Directory.CreateDirectory(dir)
        if string.IsNullOrEmpty(m.Created) { m.Created = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss") }
        if source != nil { source.Save(Path.Combine(dir, "source.png"), ImageFormat.Png) }
        try File.WriteAllText(Path.Combine(dir, "meta.json"), m.ToJson(), UTF8Encoding(false))
        for f in Directory.GetFiles(dir, "frame-*.png") { try? File.Delete(f) }
        s.SaveTo(dir)
        do { let ic = Icon(m, s, 6); ic.Save(Path.Combine(dir, "icon.png"), ImageFormat.Png) }
        if let old = sprites.Get(m.Id), old !== s { sprites.Remove(m.Id) }
        sprites[m.Id] = s
        Reset(false)
    }

    static func Delete(_ id: String)
    {
        if !CuMeta.ValidId(id) { return }
        if sprites.Get(id) != nil { sprites.Remove(id) }
        do { try Directory.Delete(Dir(id), true) } catch { App.Log("custom delete: " + error.localizedDescription) }
        Reset(false)
    }

    // 清快取（全部重讀）；all＝連處理好的圖也重讀
    static func Reset(_ all: Bool)
    {
        metas = nil
        if all { sprites.Clear() }
        Pal.CuReset()
    }

    // 站好的樣子（有白邊）畫成一張小圖：VS Code 側邊欄、設定視窗用
    static func Icon(_ m: CuMeta, _ s: CuSprite, _ ps: Int) -> Bitmap
    {
        let pad = 2 * ps
        let w = CInt(Math.Ceiling(s.Wc * Double(ps))) + 2 * pad, h = CInt(Math.Ceiling(s.Hc * Double(ps))) + 2 * pad
        let b = Bitmap(w, h, PixelFormat.Format32bppArgb)
        do {
            let g = Graphics.FromImage(b)
            g.Clear(Color.Transparent)
            Pet.CuDrawStill(g, s, Double(w) / 2.0, Double(h - pad), ps, false, false, Color.White)
        }
        return b
    }
}

// ================= Pal：自己做的公仔、我的櫃 =================
//@@IN Pal
    var Cu: Bool = false                       // 自己做的公仔
    var Meta: CuMeta! = nil
    var Spr: CuSprite! = nil
//@@END

extension Pal
{
    static let Mine = "mine"
    static let Guests: [String] = ["boba", "coffee", "onigiri", "sticky", "spidey", "po", "stitch", "hangyodon", "tinky", "dipsy", "laalaa"]   // 可以來我的櫃作客的內建公仔   //@fan
    // <public> static let Guests: [String] = ["boba", "coffee", "onigiri", "sticky"]

    static func CuReset() { all = nil }
    static func GetBuiltin(_ id: String) -> Pal! { if all == nil { return nil }; for p in all! { if p.Id == id && !p.Cu { return p } }; return nil }
    static func HasCustom() -> Bool { return CuStore.All().Count > 0 }

    static func CuPals() -> List<Pal>
    {
        let l = List<Pal>()
        for m in CuStore.All()
        {
            let s: CuSprite! = CuStore.Sprite(m)
            if s != nil { l.Add(MakeCu(m, s)) }
        }
        return l
    }

    static func MakeCu(_ m: CuMeta, _ s: CuSprite) -> Pal
    {
        let p = Pal()
        p.Cu = true; p.Meta = m; p.Spr = s
        p.Id = m.Id; p.Name = m.Name == "" ? "小公仔" : m.Name
        p.Move = "walk"; p.BallKind = "tennis"; p.NightStyle = "sleepy"; p.NightBubble = 3
        let mc = s.Main
        let lum = 0.299 * Double(mc.R) + 0.587 * Double(mc.G) + 0.114 * Double(mc.B)
        let f = lum > 150 ? 0.5 : (lum > 90 ? 0.75 : 1.0)
        p.Accent = Color.FromArgb(CInt(Double(mc.R) * f), CInt(Double(mc.G) * f), CInt(Double(mc.B) * f))
        p.Panel = Color.FromArgb(CInt(Double(mc.R) * 0.22 + 255 * 0.78), CInt(Double(mc.G) * 0.22 + 255 * 0.78), CInt(Double(mc.B) * 0.22 + 255 * 0.78))
        p.Halo = Color.White; p.HaloNight = C(0xC8C0EC)
        p.Day["k"] = s.Outline; p.Night["k"] = Color.FromArgb(s.Outline.R / 2, s.Outline.G / 2, s.Outline.B / 2 + 10)
        switch m.Persona { case "cool": p.Speed = 38; case "shy": p.Speed = 32; case "funny": p.Speed = 48; case "cat": p.Speed = 40; case "dog": p.Speed = 66; default: p.Speed = 55 }
        p.TopRows = Math.Max(0, CInt(Math.Ceiling(s.Hc)) - 16)
        p.EyeRow = -1
        // 萬一有共用的程式碼要內建的像素零件：給空白的，不會壞
        let blank: [String] = ["............"]
        for k in ["HEAD", "BODY", "ARMS_UP", "ARMS_HUG", "LEGS_A", "LEGS_B", "LEGS_SIT", "SLEEPY", "HAPPY", "DIZZY"] { p.Art[k] = blank }
        p.CuLines(m.Persona, p.Name)
        p.CuStudyLines(m.Persona, p.Name)
        p.Shared()
        return p
    }

    // 我的櫃：自己做的（最多 4 隻）＋可以請內建公仔來作客；custom/mine.txt
    static func MineIds() -> [String]
    {
        let ids = List<String>()
        let cus = CuStore.All()
        var saved = ""
        do { let f = Path.Combine(CuStore.Root, "mine.txt"); if File.Exists(f) { saved = (try? File.ReadAllText(f)) ?? "" } }
        let hasFile = saved.Trim() != ""
        let seps: [Character] = [" ", ",", "\n", "\r"]
        for t in saved.Split(seps, StringSplitOptions.RemoveEmptyEntries)
        {
            if ids.Count >= 4 || ids.Contains(t) { continue }
            if CuStore.Get(t) != nil || Guests.contains(t) { ids.Add(t) }
        }
        var anyCu = false; for t in ids { if CuStore.Get(t) != nil { anyCu = true } }
        if !hasFile || !anyCu
        {
            for m in cus { if ids.Count >= 4 { break }; if !ids.Contains(m.Id) { ids.Add(m.Id) } }
        }
        if ids.Count > 4 { ids.RemoveRange(4, ids.Count - 4) }
        return ids.ToArray()
    }

    static func SaveMine(_ ids: List<String>)
    {
        _ = try? Directory.CreateDirectory(CuStore.Root)
        try? File.WriteAllText(Path.Combine(CuStore.Root, "mine.txt"), string.Join(" ", ids.ToArray()))
    }

    // 換一櫃、設定視窗列出來的櫃子：有自己做的公仔才有「我的櫃」
    static func LineupsNow() -> [String]
    {
        if !HasCustom() { return Lineups }
        var l = Lineups; l.append(Mine)
        return l
    }
}

// ================= 一隻自己做的公仔：姿勢、畫法 =================
//@@IN Pet
    var cuPose = Pet.CuPose()
    var cuCanvas: Bitmap! = nil
    var cuAct = "", cuPrev = ""
    var cuT: Double = 0, cuLandT: Double = 0, cuX: Double = 0, cuIgnoreCd: Double = 0
    var cuOut: Bitmap! = nil
    var cuBuf: [Int]! = nil
    var cuMask: [UInt8]! = nil, cuTmp: [UInt8]! = nil
    var cuPushDir = 1; var cuPushCd: Double = 0
//@@END

extension Pet
{
    // 一格的姿勢（單位：格；+y 往下；角度：度）
    final class CuPose
    {
        var X: Double = 0, Y: Double = 0, Rot: Double = 0, PivotY: Double = 0, Sx: Double = 1, Sy: Double = 1      // 整隻：位移、旋轉（繞腳／中心／頭頂）、縮放（繞腳）
        var Rot90 = 0                                     // 像素風打滾：90° 一格一格轉
        var UpY: Double = 0, BodyRot: Double = 0, BodySy: Double = 1               // 上半身（頭＋身體）上下、身體搖、身體伸縮（繞屁股）
        var HeadX: Double = 0, HeadY: Double = 0, HeadRot: Double = 0                  // 頭
        var LX: Double = 0, LY: Double = 0, LRot: Double = 0, RX: Double = 0, RY: Double = 0, RRot: Double = 0             // 兩隻腳
        var NoLegs = false                                   // 窩著（貓貓窩）：腳收起來
        var Frame: String? = nil                                  // 動作表的哪一格
        init() {}
        func Reset() { X = 0; Y = 0; Rot = 0; PivotY = 0; UpY = 0; BodyRot = 0; HeadX = 0; HeadY = 0; HeadRot = 0; LX = 0; LY = 0; LRot = 0; RX = 0; RY = 0; RRot = 0; Sx = 1; Sy = 1; BodySy = 1; Rot90 = 0; NoLegs = false; Frame = nil }
    }
    static let CU_BLANK: [String] = ["............"]
    static let BENTO: [String] = [".kkkkkkkk.", "k22222222k", "k2WWW1YY2k", "k2WSW1PP2k", "k22222222k", ".kkkkkkkk."]
    static let MUG: [String] = ["kkkk..", "kWWkkk", "kSWk.k", "kWWkkk", ".kk..."]
    var Persona: String { return P.Meta == nil ? "lively" : P.Meta.Persona }

    // ---------- Frame()：姿勢算好，Rows 是空白（DrawFigure 交給 DrawFigureCu） ----------
    func FrameCu() -> Fr
    {
        CuPoseNow(cuPose)
        let f = F(Pet.CU_BLANK)
        f.Rot = cuPose.Rot90 != 0 || Math.Abs(cuPose.Rot) > 30 ? 1 : 0
        f.Acc = Math.Abs(cuPose.Rot) < 10 && cuPose.Rot90 == 0 && state != "sleep" && state != "drag" && state != "dizzy"
        return f
    }

    func DrawFigureCu(_ g: Graphics, _ f: Fr, _ sbx: Int, _ sby: Int, _ sps: Int, _ fx: Bool, _ extras: Bool)
    {
        CuDraw(g, cuPose, Double(sbx + 6 * sps), Double(sby + 16 * sps), sps, fx)
        if f.Acc { CuAccessories(g, cuPose, sbx, sby, sps, fx, true) }
        if extras
        {
            CuFront(g, sbx, sby, sps, fx)
            DrawLunch(g, f, sbx, sby, sps, fx)
        }
    }

    // 嘴裡叼著球（汪系撿球）
    func CuFront(_ g: Graphics, _ sbx: Int, _ sby: Int, _ sps: Int, _ fx: Bool)
    {
        if w.Holder !== self { return }
        let s: CuSprite = P.Spr
        let top: Double = 16 - s.Hc + cuPose.Y + cuPose.UpY + cuPose.HeadY
        let col: Double = 6 + (Double(s.HeadCx) + Double(s.HeadW) / 2.0 - Double(s.W) / 2.0) / Double(s.R) - 2 + cuPose.X + cuPose.HeadX
        DrawAt(g, w.BallKind == "baseball" ? Pet.BALLART : Pet.TBALL, col, top + Double(s.Neck) / Double(s.R) - 3, sbx, sby, sps, fx, false, true)
    }

    // ---------- 依狀態算姿勢 ----------
    func CuPoseNow(_ p: CuPose)
    {
        p.Reset()
        let s: CuSprite = P.Spr
        let ps = Persona
        let a = anim
        let sheet = s.Frames.Count > 0
        let legH = Double(s.H - s.Hip) / Double(s.R)
        let walking = state == "walk" || state == "goto" || state == "seek" || state == "fetch" || state == "hide"
            || (state == "cu" && (cuAct == "pushwalk" || cuAct == "fetchback" || cuAct == "comeback" || cuAct == "zoom"))
        if rolling || state == "fling"
        {
            if s.Pixel { p.Rot90 = CInt(Math.Floor(a * 14)) % 4 } else { p.Rot = (a * 760) % 360 }
            p.PivotY = 0.5
            if sheet && s.HasFrame("jump") { p.Frame = "jump" }
        }
        else if state == "drag"
        {
            // 被抓著：從頭頂晃、腳甩來甩去
            p.PivotY = 1; p.Rot = Math.Sin(a * 5.2) * 11; p.Sy = 1.05; p.Sx = 0.97
            p.LRot = Math.Sin(a * 5.2 + 0.9) * 16; p.RRot = Math.Sin(a * 5.2 + 1.6) * 16; p.LY = 0.3; p.RY = 0.3
            if sheet { p.Frame = s.HasFrame("held") ? "held" : (s.HasFrame("jump") ? "jump" : nil) }
        }
        else if state == "air" || state == "stowfly"
        {
            let up = vy < 0
            p.Sy = up ? 1.10 : 1.04; p.Sx = up ? 0.93 : 0.98
            p.LRot = -12; p.RRot = 12; p.LY = -0.4; p.RY = -0.4
            p.HeadY = up ? 0.3 : -0.3
            if sheet && s.HasFrame("jump") { p.Frame = "jump" }
        }
        else if state == "sleep"
        {
            let br = Math.Sin(a * 1.6)
            if ps == "cat"
            {
                // 貓貓窩：腳收起來、身體壓低、頭也低低的
                p.NoLegs = true; p.UpY = legH * 0.92; p.BodySy = 0.94; p.Sx = 1.04 + br * 0.012; p.HeadY = 0.3; p.HeadRot = 4
                if !s.Rig { p.Sy = 0.86 + br * 0.012; p.Sx = 1.08 }
            }
            else { p.Rot = 9; p.Sy = 0.97 + br * 0.015; p.HeadRot = 10; p.HeadY = 0.3 }
            if sheet && s.HasFrame("sleep") { p.Frame = "sleep"; p.Rot = 0; p.Sy = 1 + br * 0.012 }
        }
        else if walking
        {
            let fast = state == "seek" || state == "fetch" || cuAct == "zoom" || cuAct == "fetchback"
            let ph = a * (fast ? 2.6 : 1.8) * 2 * Math.PI, sn = Math.Sin(ph)
            let lift = Math.Max(0.6, Math.Min(1.4, legH * 0.38))
            p.LY = -Math.Max(0, sn) * lift; p.RY = -Math.Max(0, -sn) * lift
            p.LX = Math.Cos(ph) * 0.45; p.RX = -Math.Cos(ph) * 0.45
            p.UpY = -Math.Abs(sn) * 0.5; p.BodyRot = 3
            p.HeadY = -Math.Abs(Math.Sin(ph - 0.7)) * 0.35 + Math.Abs(sn) * 0.5 - 0.1; p.HeadX = -0.2
            if !s.Rig { p.Y = -Math.Abs(sn) * 0.7; p.Rot = sn * 5 }
            if sheet
            {
                let st2 = Math.Floor(a * (fast ? 7 : 5)) % 2 == 1
                if s.HasFrame("walk1") && s.HasFrame("walk2") { p.Frame = st2 ? "walk2" : "walk1"; p.Rot = 0; p.Y = -Math.Abs(sn) * 0.4 }
                else if s.HasFrame("walk1") { p.Frame = st2 ? "walk1" : "stand"; p.Rot = 0 }
            }
        }
        else if state == "hug"
        {
            // 開心：連跳兩下＋點頭
            let c = a % 1.1
            let hop = c < 0.5 ? Math.Abs(Math.Sin(c / 0.5 * Math.PI * 2)) : 0
            p.Y = -hop * 1.3; p.HeadRot = Math.Sin(a * 7) * 6
            if hop < 0.15 && c < 0.6 { p.Sy = 0.93; p.Sx = 1.05 }
            if ps == "dog" { p.BodyRot = Math.Sin(a * 22) * 4 }
            if sheet && s.HasFrame("happy") { p.Frame = "happy" }
        }
        else if state == "dance" || state == "elvis"
        {
            p.Rot = Math.Sin(a * 6) * 8; p.Y = -Math.Abs(Math.Sin(a * 6)) * 0.7
            p.LY = -Math.Max(0, Math.Sin(a * 6)) * 0.7; p.RY = -Math.Max(0, -Math.Sin(a * 6)) * 0.7; p.HeadRot = -Math.Sin(a * 6) * 6
            if sheet && s.HasFrame("happy") { p.Frame = "happy" }
        }
        else if state == "dizzy" { p.Rot = Math.Sin(a * 12) * 10; p.HeadRot = Math.Sin(a * 12 + 1) * 12 }
        else if state == "cu" { CuActPose(p, a, legH) }
        else if state == "plop" { p.UpY = legH * 0.7; p.LRot = 60; p.RRot = -60; p.Sx = 1.06; if sheet && s.HasFrame("sit") { p.Frame = "sit" } }
        else if state == "kick" { p.RRot = -38; p.RX = 0.6; p.Rot = -4 }
        else if state == "think" { p.HeadRot = 13; p.HeadY = 0.1 }
        else if state == "wave" { p.BodyRot = Math.Sin(a * 9) * 6; p.HeadRot = 6 + Math.Sin(a * 9) * 3; p.Y = -Math.Abs(Math.Sin(a * 4.5)) * 0.4; if sheet && s.HasFrame("happy") { p.Frame = "happy" } }
        else if state == "nudge" || state == "glass" { p.Rot = 6 + (knock > 0 ? 3 : 0); p.HeadX = 0.4 }
        else if state == "spin" || state == "twirl" { p.Sx = Math.Cos(a * 12); if Math.Abs(p.Sx) < 0.15 { p.Sx = p.Sx < 0 ? -0.15 : 0.15 } }
        else if state == "catch" || state == "throw" { p.Sy = 1.06; p.Rot = -5 }
        else if state == "pose"
        {
            if poseKind == "tap" { p.Rot = 7; p.HeadX = 0.5 }
            else { p.Rot = -5; p.Sy = 1.04; p.HeadRot = -6; if sheet && s.HasFrame("happy") { p.Frame = "happy" } }
        }
        else
        {
            // 發呆：呼吸、偶爾歪頭；晚上頭垂垂的
            let br = Math.Sin(a * (Night ? 1.4 : 2.2))
            p.BodySy = 1 + br * 0.03; p.UpY = 0
            let tilt = (a % 7.3) < 1.3 ? Math.Sin((a % 7.3) / 1.3 * Math.PI) : 0
            p.HeadRot = tilt * 9
            if Night { p.HeadRot += 7; p.HeadY = 0.35 }
            if ps == "dog" && (a % 5) < 1.2 { p.BodyRot = Math.Sin(a * 22) * 3 }
            if !s.Rig { p.Sy = 1 + br * 0.022; p.Sx = 1 - br * 0.012; p.Rot = tilt * 3 + (Night ? 3 : 0) }
        }
        if cuLandT > 0 { let q = cuLandT / 0.2; p.Sy *= 1 - 0.13 * q; p.Sx *= 1 + 0.1 * q }
        if !s.Rig && p.Frame == nil
        {
            // 沒有切線：整隻一起動（上半身的上下也算到整隻）
            p.Y += p.UpY * 0.6; p.Rot += p.BodyRot * 0.6 + p.HeadRot * 0.35
            if p.NoLegs { p.Y = 0 }
        }
    }

    // 自己做的公仔專屬動作的姿勢（state == "cu"）
    func CuActPose(_ p: CuPose, _ a: Double, _ legH: Double)
    {
        let s: CuSprite = P.Spr
        switch cuAct
        {
        case "wag":
            // 搖尾巴：屁股扭扭、頭跟著晃、小跳
            p.BodyRot = Math.Sin(a * 24) * 6; p.HeadRot = Math.Sin(a * 12) * 5; p.Y = -Math.Abs(Math.Sin(a * 6)) * 0.4
            if !s.Rig { p.Rot = Math.Sin(a * 24) * 5 }
        case "ignore":
            // 不理你：頭抬高、尾巴（身體）甩一下
            p.HeadRot = -10; p.HeadY = -0.2; p.BodyRot = Math.Sin(a * 3) * 2
        case "push":
            // 伸手（前腳）推推
            let k2 = Math.Sin(Math.Min(1, cuT / 0.5) * Math.PI)
            p.Rot = 6 * k2; p.RRot = -42 * k2; p.RX = 0.8 * k2; p.RY = -0.8 * k2; p.HeadX = 0.4 * k2
        case "shy":
            // 害羞：頭低低、縮起來
            p.HeadRot = 14; p.HeadY = 0.5; p.Sy = 0.95; p.Sx = 1.02; p.BodyRot = Math.Sin(a * 10) * 1.5
        case "sit":
            p.UpY = legH * 0.7; p.LRot = 60; p.RRot = -60; p.Sx = 1.05
            if !s.Rig { p.Sy = 0.9 }
            if s.HasFrame("sit") { p.Frame = "sit" }
        case "cool":
            p.Rot = -6; p.HeadRot = -8; p.Sy = 1.03
        default: break
        }
    }

    // ---------- 畫：先在小畫布上把頭／身體／腳組起來，再放大畫上去（加白邊、晚上變暗） ----------
    // 每一格：直接組在「螢幕大小」的小圖上（像素風先在格子大小組好再放大），
    // 再一次把白邊、晚上變暗、左右翻轉做完（逐像素），最後原尺寸貼上去——四隻一起跑也不會卡
    func CuDraw(_ g: Graphics, _ p: CuPose, _ feetX: Double, _ feetY: Double, _ ps: Int, _ fx: Bool)
    {
        let s: CuSprite = P.Spr
        var mb = 0, cw = 0, ch = 0
        Pet.CuCanvasSize(s, &cw, &ch, &mb)
        let sc = Double(ps) / Double(s.R)
        let hw = Math.Max(1, ps / 3), pad = hw + 1
        let tw = CInt(Math.Ceiling(Double(cw) * sc)) + 2 * pad, th = CInt(Math.Ceiling(Double(ch) * sc)) + 2 * pad
        if cuOut == nil || cuOut.Width != tw || cuOut.Height != th
        {
            if cuOut != nil { cuOut.Dispose() }
            cuOut = Bitmap(tw, th, PixelFormat.Format32bppPArgb, Pet.CuDevScale())   // mac: 裝置像素（Retina 2 倍），白邊在 CuHaloPass 跟著乘
        }
        do {
            let og = Graphics.FromImage(cuOut)
            og.Clear(Color.Transparent)
            if s.Pixel
            {
                if cuCanvas == nil || cuCanvas.Width != cw || cuCanvas.Height != ch
                {
                    if cuCanvas != nil { cuCanvas.Dispose() }
                    cuCanvas = Bitmap(cw, ch, PixelFormat.Format32bppArgb, 1)   // mac: 1 倍（CuThreshold 逐像素）
                }
                do { let cg = Graphics.FromImage(cuCanvas); cg.Clear(Color.Transparent); Pet.CuCompose(cg, s, p, cw / 2, ch - mb, nil) }
                Pet.CuThreshold(cuCanvas)
                og.InterpolationMode = InterpolationMode.NearestNeighbor
                og.PixelOffsetMode = PixelOffsetMode.Half
                og.DrawImage(cuCanvas, RectangleF(Double(pad), Double(pad), Double(cw) * sc, Double(ch) * sc), RectangleF(0, 0, Double(cw), Double(ch)), GraphicsUnit.Pixel)
            }
            else
            {
                let bm = Matrix(sc, 0, 0, sc, Double(pad), Double(pad))
                Pet.CuCompose(og, s, p, cw / 2, ch - mb, bm)
            }
        }
        CuHaloPass(cuOut, hw, Night ? P.HaloNight : P.Halo, Night, fx)
        let dx = CInt(Math.Round(feetX - Double(pad) - Double(cw) / 2.0 * sc)), dy = CInt(Math.Round(feetY - Double(pad) - Double(ch - mb) * sc))
        let im = g.InterpolationMode, pom = g.PixelOffsetMode
        g.InterpolationMode = InterpolationMode.NearestNeighbor; g.PixelOffsetMode = PixelOffsetMode.Half
        g.DrawImage(cuOut, Rectangle(dx, dy, tw, th), 0, 0, tw, th, GraphicsUnit.Pixel)
        g.InterpolationMode = im; g.PixelOffsetMode = pom
    }

    // mac: cuOut 的裝置倍率（整數，Retina＝2）
    static func CuDevScale() -> Double { return Double(Math.Max(1, CInt(Math.Round(Bitmap.DefaultScale)))) }

    // 白邊（往外 hw 像素的實心框，跟內建公仔一樣）、晚上變暗、左右翻轉：一次掃完（預乘 alpha）
    func CuHaloPass(_ b: Bitmap, _ hw0: Int, _ halo: Color, _ night: Bool, _ flip: Bool)
    {
        // mac: 在裝置像素上掃（C# 是邏輯像素）；白邊寬度乘上倍率，看起來一樣粗
        let ds = Math.Max(1, CInt(Math.Round(b.Scale)))
        let hw = hw0 * ds
        let w = b.PixelWidth, h = b.PixelHeight, n = w * h
        var buf: [Int] = b.CuReadP()
        if cuMask == nil || cuMask.count != n { cuBuf = nil; cuMask = [UInt8](repeating: 0, count: n); cuTmp = [UInt8](repeating: 0, count: n) }
        var mask: [UInt8] = cuMask, tmp: [UInt8] = cuTmp
        cuMask = nil; cuTmp = nil   // 借出來用（避免逐格複製）
        // 剪影往外長 hw（先橫再直）
        for y in 0..<h
        {
            let row = y * w
            var run = -100000
            for x in 0..<w { if ((buf[row + x] >> 24) & 255) >= 60 { run = x }; tmp[row + x] = x - run <= hw ? 1 : 0 }
            run = 100000
            var x = w - 1
            while x >= 0 { if ((buf[row + x] >> 24) & 255) >= 60 { run = x }; if run - x <= hw { tmp[row + x] = 1 }; x -= 1 }
        }
        for x in 0..<w
        {
            var run = -100000
            for y in 0..<h { if tmp[y * w + x] != 0 { run = y }; mask[y * w + x] = y - run <= hw ? 1 : 0 }
            run = 100000
            var y = h - 1
            while y >= 0 { if tmp[y * w + x] != 0 { run = y }; if run - y <= hw { mask[y * w + x] = 1 }; y -= 1 }
        }
        let hr = halo.R, hg = halo.G, hb = halo.B
        for i in 0..<n
        {
            let v = buf[i]
            var a = (v >> 24) & 255, r = (v >> 16) & 255, gg = (v >> 8) & 255, bb = v & 255
            if night && a > 0 { r = r * 58 / 100 + a * 5 / 255; gg = gg * 60 / 100 + a * 5 / 255; bb = bb * 78 / 100 + a * 18 / 255 }
            if mask[i] != 0 && a < 255 { let inv = 255 - a; r += hr * inv / 255; gg += hg * inv / 255; bb += hb * inv / 255; a = 255 }
            buf[i] = (a << 24) | (Math.Min(255, r) << 16) | (Math.Min(255, gg) << 8) | Math.Min(255, bb)
        }
        if flip
        {
            for y in 0..<h
            {
                let row = y * w
                var x = 0
                while x < w / 2 { let t = buf[row + x]; buf[row + x] = buf[row + w - 1 - x]; buf[row + w - 1 - x] = t; x += 1 }
            }
        }
        b.CuWriteP(buf)
        cuMask = mask; cuTmp = tmp
    }

    static func CuCanvasSize(_ s: CuSprite, _ cw: inout Int, _ ch: inout Int, _ mb: inout Int)
    {
        let R = s.R, m = Math.Max(s.W, s.H)
        cw = m + 6 * R + 2
        let mt = Math.Max(3 * R + s.H / 6, (s.W - s.H) / 2 + 3 * R)
        mb = Math.Max(2 * R, (s.W - s.H) / 2 + 2 * R)
        ch = s.H + mt + mb
        if cw % 2 == 1 { cw += 1 }
    }

    // 小畫布 → 螢幕：白邊（往八個方向各畫一次的剪影）＋本體；像素風用最近點放大
    static let haloIa = Dict<Int, ImageAttributes>()
    static var nightIa: ImageAttributes! = nil
    static func CuBlit(_ g: Graphics, _ canvas: Bitmap, _ s: CuSprite, _ feetX: Double, _ feetY: Double, _ cw: Int, _ ch: Int, _ mb: Int, _ ps: Int, _ fx: Bool, _ halo: Color, _ night: Bool, _ alpha: Double)
    {
        let sc = Double(ps) / Double(s.R)
        var dx = feetX - Double(cw) / 2.0 * sc, dy = feetY - Double(ch - mb) * sc
        if s.Pixel { dx = Math.Round(dx); dy = Math.Round(dy) }
        let dw = Double(cw) * sc, dh = Double(ch) * sc
        let pts: [PointF] = fx ? [PointF(dx + dw, dy), PointF(dx, dy), PointF(dx + dw, dy + dh)]
                               : [PointF(dx, dy), PointF(dx + dw, dy), PointF(dx, dy + dh)]
        let im = g.InterpolationMode, pom = g.PixelOffsetMode
        g.InterpolationMode = s.Pixel ? InterpolationMode.NearestNeighbor : InterpolationMode.HighQualityBicubic
        g.PixelOffsetMode = s.Pixel ? PixelOffsetMode.Half : PixelOffsetMode.HighQuality
        let src = RectangleF(0, 0, Double(cw), Double(ch))
        if halo.A > 0
        {
            let key = halo.ToArgb()
            var hia: ImageAttributes! = haloIa.Get(key)
            if hia == nil
            {
                let cm = ColorMatrix([
                    [0, 0, 0, 0, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0, 0],
                    [0, 0, 0, 1, 0], [Double(halo.R) / 255.0, Double(halo.G) / 255.0, Double(halo.B) / 255.0, 0, 1]])
                hia = ImageAttributes(); hia.SetColorMatrix(cm)
                if haloIa.Count > 16 { haloIa.Clear() }
                haloIa[key] = hia
            }
            let hw = Double(Math.Max(1, ps / 3))
            for oy in -1...1
            {
                for ox in -1...1
                {
                    if ox == 0 && oy == 0 { continue }
                    let q: [PointF] = [PointF(pts[0].X + Double(ox) * hw, pts[0].Y + Double(oy) * hw), PointF(pts[1].X + Double(ox) * hw, pts[1].Y + Double(oy) * hw), PointF(pts[2].X + Double(ox) * hw, pts[2].Y + Double(oy) * hw)]
                    g.DrawImage(canvas, q, src, GraphicsUnit.Pixel, hia)
                }
            }
        }
        var ia: ImageAttributes! = nil
        if night
        {
            if nightIa == nil
            {
                let nm = ColorMatrix([
                    [0.58, 0, 0, 0, 0], [0, 0.6, 0, 0, 0], [0, 0, 0.78, 0, 0],
                    [0, 0, 0, 1, 0], [0.02, 0.02, 0.07, 0, 1]])
                nightIa = ImageAttributes(); nightIa.SetColorMatrix(nm)
            }
            ia = nightIa
        }
        if alpha < 0.999
        {
            let am = ColorMatrix(); am.Matrix33 = alpha
            if night { am.Matrix00 = 0.58; am.Matrix11 = 0.6; am.Matrix22 = 0.78 }
            let aia = ImageAttributes(); aia.SetColorMatrix(am)
            g.DrawImage(canvas, pts, src, GraphicsUnit.Pixel, aia)
            aia.Dispose()
        }
        else if ia != nil { g.DrawImage(canvas, pts, src, GraphicsUnit.Pixel, ia) }
        else { g.DrawImage(canvas, pts, src, GraphicsUnit.Pixel) }
        g.InterpolationMode = im; g.PixelOffsetMode = pom
    }

    // 組裝：整隻的位移／旋轉／縮放 → 腳 → 身體 → 頭
    static func CuCompose(_ cg: Graphics, _ s: CuSprite, _ p: CuPose, _ ox: Int, _ oy: Int, _ baseM: Matrix!)
    {
        cg.InterpolationMode = s.Pixel ? InterpolationMode.NearestNeighbor : InterpolationMode.HighQualityBicubic
        cg.PixelOffsetMode = s.Pixel ? PixelOffsetMode.Half : PixelOffsetMode.HighQuality
        cg.CompositingQuality = CompositingQuality.HighQuality
        let R = Double(s.R)
        let q: (Double) -> Double = { v in s.Pixel ? Math.Round(v * R) : v * R }
        if s.Pixel
        {
            // 像素風：小角度的轉動會讓格子歪掉（看起來不像內建公仔），改成一格一格的位移
            if Math.Abs(p.HeadRot) < 8 { p.HeadY -= Math.Abs(p.HeadRot) / 8 * 0.6; p.HeadX += p.HeadRot / 8 * 0.5; p.HeadRot = 0 }
            if Math.Abs(p.BodyRot) < 8 { p.UpY -= Math.Abs(p.BodyRot) / 8 * 0.4; p.BodyRot = 0 }
            if Math.Abs(p.Rot) < 4 && p.Rot90 == 0 { p.X += p.Rot / 4 * 0.5; p.Rot = 0 }
        }
        let m: Matrix = baseM == nil ? Matrix() : baseM.Clone()
        m.Translate(Double(ox) + q(p.X), Double(oy) + q(p.Y))
        if p.Rot90 != 0 { m.Translate(0, -Double(s.H) / 2); m.Rotate(Double(90 * p.Rot90)); m.Translate(0, Double(s.H) / 2) }
        if Math.Abs(p.Rot) > 0.01 { let pv = -Double(s.H) * p.PivotY; m.Translate(0, pv); m.Rotate(p.Rot); m.Translate(0, -pv) }
        if Math.Abs(p.Sx - 1) > 0.001 || Math.Abs(p.Sy - 1) > 0.001 { m.Scale(p.Sx, p.Sy) }
        let L = Double(-(s.W / 2)), T = Double(-s.H)
        if p.Frame != nil, let fr = s.Frames.Get(p.Frame!) { CuPut(cg, m, fr, L, T, 0, 0, 0, 0, 0); return }
        if !s.Rig { CuPut(cg, m, s.Stand, L, T, 0, 0, 0, 0, 0); return }
        // 腳（踩在地上；抬腳往上、轉繞腳的最上面）
        if !p.NoLegs
        {
            let lcx = L + Double(s.Split) / 2, rcx = L + Double(s.Split) + Double(s.W - s.Split) / 2, top = T + Double(s.Hip)
            CuPut(cg, m, s.LegL, L, top, q(p.LX), q(p.LY), p.LRot, lcx, top)
            CuPut(cg, m, s.LegR, L + Double(s.Split), top, q(p.RX), q(p.RY), p.RRot, rcx, top)
        }
        // 身體：繞屁股那條線伸縮、搖
        let hipY = T + Double(s.Hip), up = q(p.UpY)
        let mb = m.Clone()
        mb.Translate(0, up)
        mb.Translate(L + Double(s.NeckCx), hipY)
        if Math.Abs(p.BodyRot) > 0.01 { mb.Rotate(p.BodyRot) }
        if Math.Abs(p.BodySy - 1) > 0.001 { mb.Scale(1, p.BodySy) }
        mb.Translate(-(L + Double(s.NeckCx)), -hipY)
        CuPut(cg, mb, s.Body, L, T + Double(s.BodyY0), 0, 0, 0, 0, 0)
        // 頭：跟著身體頂端；繞脖子轉
        let neckY = T + Double(s.Neck)
        CuPut(cg, mb, s.Head, L, T, q(p.HeadX), q(p.HeadY), p.HeadRot, L + Double(s.HeadCx), neckY)
    }

    // 放一張零件：先位移 (dx,dy)，再繞 (px,py) 轉 rot 度
    static func CuPut(_ cg: Graphics, _ baseM: Matrix, _ img: Bitmap!, _ x: Double, _ y: Double, _ dx: Double, _ dy: Double, _ rot: Double, _ px: Double, _ py: Double)
    {
        if img == nil { return }
        let m = baseM.Clone()
        m.Translate(dx, dy)
        if Math.Abs(rot) > 0.01 { m.Translate(px, py); m.Rotate(rot); m.Translate(-px, -py) }
        cg.Transform = m
        cg.DrawImage(img, RectangleF(x, y, Double(img.Width), Double(img.Height)), RectangleF(0, 0, Double(img.Width), Double(img.Height)), GraphicsUnit.Pixel)
        cg.ResetTransform()
    }

    // 像素風：組完之後半透明的一律變成全有或全無（才會一格一格）
    // mac: 畫布是 1 倍的 Bitmap，直接讀寫預乘的像素（C# 用不預乘的 32bppArgb：結果一樣）
    static func CuThreshold(_ b: Bitmap)
    {
        var px: [Int] = b.CuReadP()
        var ch = false
        for i in 0..<px.count
        {
            let v = px[i]
            let a = (v >> 24) & 255
            if a == 0 || a == 255 { continue }
            if a < 128 { px[i] = 0 }
            else
            {
                let r = Math.Min(255, ((v >> 16) & 255) * 255 / a), g = Math.Min(255, ((v >> 8) & 255) * 255 / a), bb = Math.Min(255, (v & 255) * 255 / a)
                px[i] = (255 << 24) | (r << 16) | (g << 8) | bb
            }
            ch = true
        }
        if !ch { return }
        b.CuWriteP(px)
    }

    // 不用 Pet 的地方（設定視窗、VS Code 小圖、分享短片的預覽）：站好的樣子
    static func CuDrawStill(_ g: Graphics, _ s: CuSprite, _ feetX: Double, _ feetY: Double, _ ps: Int, _ fx: Bool, _ night: Bool, _ halo: Color)
    {
        var mb = 0, cw = 0, ch = 0
        CuCanvasSize(s, &cw, &ch, &mb)
        let c = Bitmap(cw, ch, s.Pixel ? PixelFormat.Format32bppArgb : PixelFormat.Format32bppPArgb)
        do { let cg = Graphics.FromImage(c); cg.Clear(Color.Transparent); let p = CuPose(); CuCompose(cg, s, p, cw / 2, ch - mb, nil) }
        CuBlit(g, c, s, feetX, feetY, cw, ch, mb, ps, fx, halo, night, 1)
    }

    // ---------- 配件：帽子戴在頭頂（頭太小／太歪就不戴）、圍巾圍在脖子那條線、節日的紅包蛋糕放旁邊 ----------
    func CuAccessories(_ g: Graphics, _ p: CuPose, _ sbx: Int, _ sby: Int, _ ps: Int, _ fx: Bool, _ sides: Bool)
    {
        let s: CuSprite = P.Spr
        let lv = Level()
        let hc = s.Hc
        let sy = p.Sy
        let top: Double = 16 - hc * sy + p.Y + (s.Rig ? p.UpY + p.HeadY : 0)
        let headTop: Double = top + Double(s.HeadTop) / Double(s.R) * sy
        let headCol: Double = 6 + (Double(s.HeadCx) - Double(s.W) / 2.0) / Double(s.R) + p.X + (s.Rig ? p.HeadX : 0)
        let headW = Double(s.HeadW) / Double(s.R)
        if lv >= 2 && s.Rig && p.Frame == nil
        {
            let nw = Double(s.NeckW) / Double(s.R)
            if nw >= 4 && nw <= 12
            {
                let neckRow: Double = top + Double(s.Neck) / Double(s.R) * sy - (s.Rig ? p.HeadY : 0) - 0.5
                DrawAt(g, Pet.SCARF, 6 + (Double(s.NeckCx) - Double(s.W) / 2.0) / Double(s.R) + p.X - 6, neckRow, sbx, sby, ps, fx, false, false)
            }
        }
        let hat: [String]? = w.SeasonNow == "xmas" && w.Feat("season") ? Pet.SANTA : (lv >= 6 ? Pet.CROWN : (lv >= 3 ? Pet.BEANIE : nil))
        if let hat = hat, headW >= 5 && headW <= 18 { DrawAt(g, hat, headCol - 6, headTop - Double(hat.count) + 1, sbx, sby, ps, fx, false, true) }
        if !sides { return }
        let side: Double = 6 + s.Wc / 2 + 0.2, mid: Double = 16 - hc * 0.5
        if w.SeasonNow == "cny" { DrawAt(g, Pet.ENVELOPE, side, mid, sbx, sby, ps, fx, false, true) }
        if w.SeasonNow == "birthday" { DrawAt(g, Pet.CAKE, side, mid - 1, sbx, sby, ps, fx, false, true) }
    }

    // ---------- 午餐：手上拿便當（睡午覺時擺旁邊的空盤子） ----------
    func CuLunch(_ g: Graphics, _ f: Fr, _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool, _ bite: Int)
    {
        let s: CuSprite = P.Spr
        let mid: Double = s.Rig ? Double(s.Neck + s.Hip) / 2.0 : Double(s.H) * 0.55
        let row: Double = 16 - s.Hc + mid / Double(s.R) - 2 + cuPose.Y + cuPose.UpY
        DrawAt(g, Pet.BENTO, 6 + s.Wc / 2 - 2.5 + cuPose.X, row + Double(bite), bx, by, ps, fx, false, true)
    }

    func CuLunchShelf(_ g: Graphics, _ bx: Int, _ by: Int, _ ps: Int, _ flip: Bool)
    {
        let s: CuSprite = P.Spr
        let mid: Double = s.Rig ? Double(s.Neck + s.Hip) / 2.0 : Double(s.H) * 0.55
        let row: Double = 16 - s.Hc + mid / Double(s.R) - 2
        DrawAt(g, Pet.BENTO, 6 + s.Wc / 2 - 2.5, row, bx, by, ps, flip, false, true)
    }

    func CuLunchLine(_ phase: String) -> String
    {
        if phase == "start" { return L("x_lunch_start") }
        if phase == "nap" { return L("x_lunch_nap") }
        if phase == "end" { return L("x_lunch_end") }
        return L("x_lunch_talk")
    }

    // ---------- 櫃子裡：輕輕呼吸、偶爾歪頭、換邊看；晚上睡（貓窩著） ----------
    func DrawCuShelf(_ g: Graphics, _ fx: Int, _ fy: Int, _ ps: Int, _ cell: Rectangle, _ tt: Double)
    {
        let p = CuPose()
        let s: CuSprite = P.Spr
        let br = Math.Sin(tt * 1.9)
        p.BodySy = 1 + br * 0.03
        if !s.Rig { p.Sy = 1 + br * 0.02; p.Sx = 1 - br * 0.01 }
        let tilt = (tt % 6.1) < 1.1 ? Math.Sin((tt % 6.1) / 1.1 * Math.PI) : 0
        p.HeadRot = tilt * 8; if !s.Rig { p.Rot = tilt * 3 }
        if Night
        {
            let legH = Double(s.H - s.Hip) / Double(s.R)
            if Persona == "cat" && s.Rig { p.NoLegs = true; p.UpY = legH * 0.92; p.HeadY = 0.3; p.HeadRot = 4 }
            else { p.HeadRot = 10; p.HeadY = 0.3; if !s.Rig { p.Rot = 5 } }
            if s.HasFrame("sleep") { p.Frame = "sleep"; p.Rot = 0 }
        }
        let flip = (Math.Floor(tt / 9) % 2) == 1
        CuDraw(g, p, Double(fx), Double(fy), ps, flip)
        CuAccessories(g, p, fx - 6 * ps, fy - 16 * ps, ps, flip, false)
        if w.Lunch { CuLunchShelf(g, fx - 6 * ps, fy - 16 * ps, ps, flip) }
    }

    // 外出中的格子：淡淡的剪影
    func CuGhost(_ g: Graphics, _ fx: Int, _ fy: Int, _ ps: Int, _ night: Bool)
    {
        let s: CuSprite = P.Spr
        var mb = 0, cw = 0, ch = 0
        Pet.CuCanvasSize(s, &cw, &ch, &mb)
        let c = Bitmap(cw, ch, PixelFormat.Format32bppArgb)
        do { let cg = Graphics.FromImage(c); cg.Clear(Color.Transparent); Pet.CuCompose(cg, s, CuPose(), cw / 2, ch - mb, nil) }
        let a = P.Accent
        let cm = ColorMatrix([
            [0, 0, 0, 0, 0], [0, 0, 0, 0, 0], [0, 0, 0, 0, 0],
            [0, 0, 0, Double(night ? 34 : 42) / 255.0, 0], [Double(a.R) / 255.0, Double(a.G) / 255.0, Double(a.B) / 255.0, 0, 1]])
        do {
            let ia = ImageAttributes()
            ia.SetColorMatrix(cm)
            let sc = Double(ps) / Double(s.R)
            let im = g.InterpolationMode
            g.InterpolationMode = s.Pixel ? InterpolationMode.NearestNeighbor : InterpolationMode.HighQualityBilinear
            g.DrawImage(c, Rectangle(CInt(Double(fx) - Double(cw) / 2.0 * sc), CInt(Double(fy) - Double(ch - mb) * sc), CInt(Double(cw) * sc), CInt(Double(ch) * sc)), 0, 0, cw, ch, GraphicsUnit.Pixel, ia)
            g.InterpolationMode = im
        }
    }

    func CuShelfRows() -> Int
    {
        let hat = (w.SeasonNow == "xmas" || Level() >= 3) && Double(P.Spr.HeadW) / Double(P.Spr.R) >= 5 ? 3 : 0
        return CInt(Math.Ceiling(P.Spr.Hc * 1.04)) + hat + 1
    }
}

// ================= 一隻自己做的公仔：個性和動作 =================
extension Pet
{
    func CuDo(_ act: String, _ dur: Double) { cuAct = act; cuT = 0; SetState("cu", dur) }

    // 每一格（StepSpecial 最前面）：落地壓扁、專屬動作
    func CuStep(_ dt: Double) -> Bool
    {
        if cuLandT > 0 { cuLandT -= dt }
        if cuIgnoreCd > 0 { cuIgnoreCd -= dt }
        if cuPushCd > 0 { cuPushCd -= dt }
        if cuPrev == "air" && state != "air" && state != "drag" { cuLandT = 0.2 }
        cuPrev = state
        if state != "cu" { return false }
        cuT += dt
        let cp = Cursor.Position
        switch cuAct
        {
        case "pushwalk":
            if Math.Abs(cuX - Cx) > 4
            {
                dir = cuX > Cx ? 1 : -1
                if MoveOnGround(dt, P.Speed * k) { return true }
                if (dir > 0 && Cx > cuX) || (dir < 0 && Cx < cuX) { x = cuX - Double(SW) / 2.0 }
            }
            else { dir = cuPushDir; CuDo("push", 1.5) }
            if t < 0 { SetState("idle", 1) }
            return true
        case "push":
            if cuT - dt < 0.55 && cuT >= 0.55 { CuPushItem() }
            if t < 0 { SetState("idle", R(1.5, 3)) }
            return true
        case "ignore":
            if t < 0 { CuDo("comeback", 4.5) }
            return true
        case "comeback":
            do {
                let dx = Double(cp.X) - Cx
                if Math.Abs(dx) < 14 * k || t < 0 { dir = dx >= 0 ? 1 : -1; Hug(L("x_comeback"), 2.6); return true }
                dir = dx > 0 ? 1 : -1
                _ = MoveOnGround(dt, P.Speed * 1.3 * k)
            }
            return true
        case "fetchback":
            do {
                let dx = Double(cp.X) - Cx
                if w.Holder !== self { SetState("idle", 1); return true }
                if Math.Abs(dx) < 16 * k || t < 0
                {
                    w.ReleaseBall(Cx + Double(dir) * 7 * k, y + Double(SH) - 8 * k, Double(dir) * 30 * k, -60 * k)
                    Say(L("x_fetch_back"), 2.2); AddHeart()
                    CuDo("wag", 1.8)
                    return true
                }
                dir = dx > 0 ? 1 : -1
                if MoveOnGround(dt, 150 * k) { return true }
            }
            return true
        case "zoom":
            if Math.Floor(cuT / 0.8) != Math.Floor((cuT - dt) / 0.8) { dir = -dir }
            if MoveOnGround(dt, 210 * k) { return true }
            if t < 0 { CuDo("wag", 1.4); Say(L("x_wag"), 1.6) }
            return true
        default:
            if cuAct == "wag" && rnd.NextDouble() < dt * 2 { AddHeart() }
            if t < 0 && !InScene { SetState("idle", R(1, 2)) }
            return true
        }
    }

    // 招牌動作（右鍵選單）
    func CuSignature()
    {
        if !Grounded() && state != "cu" { return }
        switch Persona
        {
        case "cool": CuDo("cool", 2.2); Say(L("x_sig"), 1.8)
        case "shy":
            do {
                let o: Pet! = w.Nearest(self)
                if o != nil && Math.Abs(o.Cx - Cx) < 500 * k && Math.Abs(o.Foot - Foot) < 3 { HideBehindPet(o) } else { CuDo("shy", 2.4) }
                Say(L("x_sig"), 1.8); Mark(4)
            }
        case "funny": Say(L("x_sig"), 1.6); rolling = true; dizzyOnLand = true; Jump(Double(dir) * 60 * k, -400 * k)
        case "cat": GoSleep(); t = R(8, 14); Say(L("x_loaf"), 1.8)
        case "dog": CuDo("zoom", 2.6); Say(L("x_sig"), 1.4)
        default:
            Say(L("x_sig"), 1.4)
            if !JumpToPlatform() { Jump(Double(dir) * 90 * k, -460 * k) }
            afterLand = "cuhop"
        }
    }

    func CuAct(_ a: String) -> Bool
    {
        switch a
        {
        case "sit": if Grounded() { CuDo("sit", R(3, 5)); Say(L("x_sit"), 1.6) }; return true
        case "wag": if Grounded() { CuDo("wag", 2.2); Say(L("x_wag"), 1.6) }; return true
        case "loaf": if Grounded() { GoSleep(); t = R(8, 14); Say(L("x_loaf"), 1.8) }; return true
        case "push": if !CuPushStart() { Say(L("x_ignore"), 1.6) }; return true
        case "ignore": if Grounded() { CuDo("ignore", 2.5); Say(L("x_ignore"), 1.8) }; return true
        default: break
        }
        return false
    }

    // 連點三下
    func CuCombo()
    {
        Say(L("tickle"), 1.8)
        if !Grounded() || state == "dizzy" { return }
        switch Persona
        {
        case "cool": CuDo("cool", 1.6)
        case "shy": CuDo("shy", 2); Mark(4)
        case "funny": SetState("spin", 0.9); Jump(0, -320 * k); rolling = true
        case "cat": CuDo("ignore", 2)
        case "dog": CuDo("wag", 2)
        default: Jump(Double(dir) * 40 * k, -360 * k); afterLand = "cuhop"
        }
    }

    // 摸一下：喵系偶爾不理你（過一下又自己跑回來）
    func CuPat() -> Bool
    {
        if Persona != "cat" || Night || !Grounded() || state == "dizzy" || state == "sleep" || cuIgnoreCd > 0 || rnd.NextDouble() > 0.3 { return false }
        cuIgnoreCd = 60
        dir = Double(Cursor.Position.X) > Cx ? -1 : 1
        CuDo("ignore", R(2.2, 3.4))
        Say(L("x_ignore"), 2.0)
        return true
    }

    // 從閒置回來：汪系開心地跳兩下
    func CuWelcome() -> Bool
    {
        if Persona != "dog" || !Grounded() { return false }
        Jump(0, -380 * k); afterLand = "cuhop"
        Say(L("x_return"), 3); AddHeart(); AddHeart()
        return true
    }

    func CuLand(_ a: String) -> Bool
    {
        if a == "cuhop" { Jump(Double(dir) * 20 * k, -260 * k); AddHeart(); return true }
        if a == "cufetch" { if w.Holder === self { CuDo("fetchback", 5) } else { SetState("idle", 1) }; return true }
        return false
    }

    // 球碰到他：汪系叼回來給你；喵系撥一下；其他人踢回去
    func CuBall()
    {
        if Persona == "dog"
        {
            // 叼住；在空中接到的話落地再叼回來
            w.HoldBall(self)
            if Grounded() { CuDo("fetchback", 5) } else { afterLand = "cufetch" }
            Say(L("ball_catch"), 1.6)
            return
        }
        Say(L("ball_catch"), 1.8)
        KickBallToCursor(Persona == "cat" ? 0.6 : 1.0)
        if Grounded() { SetState("kick", 0.5) }
    }

    // 出錯了：害羞的躲起來、喵系不理、汪系跳起來、搞笑的轉暈
    func CuReact(_ why: String)
    {
        if why != "errors" { return }
        switch Persona
        {
        case "shy": do { let o: Pet! = w.Nearest(self); if o != nil { HideBehindPet(o) } else { CuDo("shy", 2.6) }; Mark(4) }
        case "cat": CuDo("ignore", 2.4)
        case "funny": SetState("dizzy", 1.6)
        case "cool": CuDo("cool", 2)
        default: Jump(0, -340 * k); Mark(1)
        }
    }

    // 走到視窗邊：喵系常常坐在邊邊，偶爾把東西推下去
    func CuEdge(_ right: Bool) -> Int
    {
        switch Persona
        {
        case "cat":
            if rnd.NextDouble() < 0.25 && cuPushCd <= 0 { cuPushDir = right ? 1 : -1; dir = cuPushDir; CuDo("push", 1.5); return 2 }
            if rnd.NextDouble() < 0.7 { dir = -dir; SetState("idle", R(2, 5)); return 2 }
            return 0
        case "shy": if rnd.NextDouble() < 0.75 { dir = -dir; return 1 }; return 0
        case "cool": if rnd.NextDouble() < 0.5 { dir = -dir; return 1 }; return 0
        case "dog": if rnd.NextDouble() < 0.3 { dir = -dir; return 1 }; return 0
        default: break
        }
        if rnd.NextDouble() < 0.4 { dir = -dir; return 1 }
        return 0
    }

    // 喵系：走到視窗邊，把一個小杯子推下去
    func CuPushStart() -> Bool
    {
        if supH == IntPtr.Zero || !Grounded() { return false }
        let right = (Double(supR) - Cx) < (Cx - Double(supL)) ? true : (rnd.NextDouble() < 0.5)
        cuPushDir = right ? 1 : -1
        cuX = right ? Double(supR) - Double(SW) * 0.15 : Double(supL) + Double(SW) * 0.15
        if cuX < Double(supL) + Double(SW) * 0.3 && cuX > Double(supR) - Double(SW) * 0.3 { return false }
        CuDo("pushwalk", 8)
        return true
    }

    func CuPushItem()
    {
        cuPushCd = 90
        let ex = cuPushDir > 0 ? Math.Max(Cx + Double(SW) * 0.4, Double(supR) + 6 * k) : Math.Min(Cx - Double(SW) * 0.4, Double(supL) - 6 * k)
        let wa = w.WA(ex, y + Double(SH))
        let from = PointF(Cx + Double(cuPushDir) * Double(SW) * 0.45, Foot - 3 * Double(S))
        let to = PointF(ex + Double(cuPushDir) * 30 * k, Double(wa.Bottom) - 3 * Double(S))
        w.CuToss(Pet.MUG, P, from, to)
        Say(L("x_push"), 2.4)
    }

    func CuDecide(_ r: Double, _ wa: Rectangle)
    {
        let ps = Persona
        if ps == "cat"
        {
            if supH != IntPtr.Zero
            {
                // 在視窗上：坐著看風景、窩著睡、偶爾推東西
                if r < 0.32 { SetState("idle", R(4, 9)); return }
                if r < 0.46 { GoSleep(); t = R(10, 20); if rnd.NextDouble() < 0.4 { Say(L("x_loaf"), 1.8) }; return }
                if r < 0.56 && cuPushCd <= 0 && CuPushStart() { return }
            }
            else if r < 0.28 && JumpToPlatform() { return }
        }
        if ps == "dog" && r < 0.12 { CuDo("wag", R(1.4, 2.4)); if rnd.NextDouble() < 0.4 { Say(L("x_wag"), 1.4) }; return }
        if ps == "dog" && r < 0.17 { CuDo("zoom", R(1.8, 3)); return }
        if ps == "shy" && r < 0.10 { CuDo("shy", R(2, 3.5)); return }
        let r2 = rnd.NextDouble()
        let idle = ps == "cool" || ps == "shy" || ps == "cat" ? 0.30 : (ps == "dog" ? 0.10 : 0.15)
        let hop = ps == "lively" ? 0.24 : (ps == "funny" ? 0.16 : (ps == "cool" || ps == "shy" ? 0.08 : 0.14))
        let sig = ps == "funny" || ps == "lively" ? 0.08 : 0.05
        var c = idle
        if r2 < c { SetState("idle", R(1.5, 4.5)); return }
        c += hop
        if r2 < c { if !JumpToPlatform() { Hop() }; return }
        c += sig
        if r2 < c { CuSignature(); return }
        c += 0.05
        if r2 < c { Hug(L("hugs"), 2.2); return }
        c += Night ? 0.05 : 0.03
        if r2 < c { Knock(L("knock"), "ambient"); return }
        c += 0.04
        if r2 < c && lateCd <= 0 && LateLine() != nil { LateTick(); return }
        c += 0.03
        if r2 < c && SeasonLine() != nil { Say(SeasonLine(), 3); SetState("idle", 3); return }
        c += 0.08
        if r2 < c { SetState("idle", 2.5); Say(L("talk"), 2.4); return }
        dir = rnd.NextDouble() < 0.5 ? -1 : 1; SetState("walk", R(3, 6))
    }

    // 測試用：直接叫某個專屬動作
    func CuTest(_ a: String)
    {
        switch a
        {
        case "jumpwin": _ = JumpToPlatform()
        case "push": if !CuPushStart() { Say("（不在視窗上）", 1) }
        case "ignore": CuDo("ignore", 2.5); Say(L("x_ignore"), 2)
        case "return": _ = CuWelcome()
        case "loaf": GoSleep(); t = 12
        default: _ = CuAct(a)
        }
    }

    // 右鍵選單「一起玩」
    func CuMenuItems() -> [[String]]
    {
        var sig: String
        switch Persona
        {
        case "cool": sig = "耍帥一下"
        case "shy": sig = "躲起來偷看"
        case "funny": sig = "表演翻跟斗"
        case "cat": sig = "窩成貓貓窩"
        case "dog": sig = "暴衝跑一圈"
        default: sig = "蹦蹦跳"
        }
        var l: [[String]] = []
        l.append(["抱抱 ♥", "hug"]); l.append(["打招呼", "hi"]); l.append(["敲敲螢幕", "knock"])
        l.append([sig, "sig"])
        if Persona == "dog" { l.append(["搖尾巴", "wag"]) }
        if Persona == "cat" { l.append(["把東西推下去", "push"]) }
        l.append(["跳到別的視窗上", "jump"]); l.append(["坐下", "sit"]); l.append(["睡覺", "sleep"])
        l.append([Persona == "dog" ? "丟球給他（會撿回來）" : "丟球給他", "ball"])
        return l
    }
}

// ================= World：我的櫃、選單、pipe 指令、重新載入 =================
//@@IN World
    let cuFakeH: IntPtr = 0x7FFF0F01
    var cuFakeR = Rectangle.Empty
//@@END

extension World
{
    var CuLineup: Bool { return lineup == Pal.Mine }

    // 小道具（喵系推下去的杯子）
    func CuToss(_ art: [String], _ owner: Pal, _ a: PointF, _ b: PointF) { Toss(art, owner, a, b, 0.75, 14 * k, true, 1.6, nil) }

    // 串場：自己做的公仔 × 任何一隻（打招呼抱抱、聊天、傳球）
    func CuPairScene(_ key: String, _ a0: Pet!, _ b0: Pet!)
    {
        if a0 == nil || b0 == nil { return }
        var a: Pet = a0, b: Pet = b0
        if !a.P.Cu && b.P.Cu { let t = a; a = b; b = t }
        if !a.P.Cu { return }
        let A: Pet = a, B: Pet = b
        let pick = rnd.Next(3)
        Begin(A, B)
        let on: String = B.P.Name
        if pick == 0
        {
            At(0) { [self] in Face(A, B); A.ScenePose("idle", 8); B.ScenePose("idle", 8); A.Say(A.L("x_pair_hi", "o", on), 2.2) }
            At(2.3) { B.ScenePose("wave", 1.4); B.Say(B.P.Cu ? B.L("x_pair_hi", "o", A.P.Name) : B.L("hi"), 2.2) }
            At(4.8) { [self] in Face(A, B); A.ScenePose("hug", 2.4); B.ScenePose("hug", 2.4); A.Say(A.L("hugs"), 2.2) }
            At(7.6) { }
        }
        else if pick == 1
        {
            At(0) { [self] in Face(A, B); A.ScenePose("idle", 10); B.ScenePose("idle", 10); A.Say(A.L("x_pair_ask", "o", on), 2.4) }
            At(2.6) { B.ScenePose("hop", 0); B.Say(B.L("talk"), 2.4) }
            At(5.2) { A.ScenePose("dance", 1.6); A.Say(A.L("x_pair_react", "o", on), 2.2) }
            At(7.6) { A.Say(A.L("x_pair_bye", "o", on), 1.8) }
            At(9.6) { }
        }
        else
        {
            let ball: [String] = [".yy.", "yyyy", "yyyy", ".yy."]
            At(0) { [self] in Face(A, B); A.ScenePose("idle", 12); B.ScenePose("idle", 12); A.Say(A.L("x_pair_ball", "o", on), 2) }
            var tt = 1.6
            for i in 0..<4
            {
                let from: Pet = i % 2 == 0 ? A : B, to: Pet = i % 2 == 0 ? B : A
                At(tt) { [self] in from.ScenePose("kick", 0.4); Toss(ball, A.P, from.HandPoint(), to.HandPoint(), 0.7, 40 * k, true, 0, { to.ScenePose("hop", 0) }) }
                tt += 1.1
            }
            At(tt + 0.4) { [self] in Face(A, B); B.Say(B.P.Cu ? B.L("x_pair_ball_end", "o", A.P.Name) : B.L("ball_catch"), 2); A.ScenePose("hug", 2); A.Say(A.L("x_pair_ball_end", "o", on), 2) }
            At(tt + 3) { }
        }
    }

    // 通知、提醒、搶票：自己做的公仔用自己個性的開場白
    static func CuFlavor(_ id: String, _ kind: String, _ night: Bool) -> String?
    {
        let p: Pal! = Pal.Get(id)
        if p == nil || !p.Cu { return nil }
        var a: [String] = []
        if night && p.Lines.TryGetValue("x_" + kind + "_d", &a) && a.count > 0 { return a[Random().Next(a.count)] }
        if p.Lines.TryGetValue("x_" + kind, &a) && a.count > 0 { return a[Random().Next(a.count)] }
        return nil
    }

    // 讀書小幫手：自己做的公仔用自己個性的句子（52_study.swift 的 ExamPrefix／ExamTail／LateNightLine／CourseLine 會先問這裡）
    static func CuStudy(_ id: String, _ key: String, _ hm: String?, _ t: String?, _ h: String?) -> String?
    {
        let p: Pal! = Pal.Get(id)
        var a: [String] = []
        if p == nil || !p.Cu || !p.Lines.TryGetValue(key, &a) || a.count == 0 { return nil }
        return a[Random().Next(a.count)].Replace("{hm}", hm ?? "").Replace("{t}", t ?? "").Replace("{h}", h ?? "")
    }

    static func CuTicket(_ id: String, _ stage: Int, _ n: String, _ h: String) -> String?
    {
        let p: Pal! = Pal.Get(id)
        var a: [String] = []
        if p == nil || !p.Cu || !p.Lines.TryGetValue("x_ticket" + String(stage), &a) || a.count == 0 { return nil }
        return a[Random().Next(a.count)].Replace("{t}", n).Replace("{h}", h)
    }

    // ---------- 重新載入（新做／改過／刪掉一隻之後） ----------
    func CuReload(_ pet: String)
    {
        CuStore.Reset(false)
        if lineup == Pal.Mine && !Pal.HasCustom() { SwitchLineup(Pal.Fallback, ""); return }
        if lineup != Pal.Mine { return }
        // 跟 SwitchLineup 一樣，只是同一櫃也要重建（公仔的資料換了）
        AbortScene()
        ClearProps()
        if BallOn { BallOn = false; Holder = nil; if ballF != nil { ballF.Hide() } }
        SaveUsage(); SaveOut()
        let outIds = List<String>()
        for p in outOrder { if p.Out { outIds.Add(p.P.Id) } }
        current = nil
        for p in Pets { p.Out = false; p.CloseForms() }
        Pets.Clear(); outOrder.Clear(); active = nil; lastBroadcast = ""
        defaultPet = DefaultPetFor(pet)
        var seed = Environment.TickCount
        for p in Pal.Lineup(lineup) { Pets.Add(Pet(self, p, S, seed)); seed += 1 }
        RenderShelf()
        if Get(pet) != nil && !outIds.Contains(pet) { outIds.Add(pet) }
        if Single { let sp = SinglePet(); outIds.RemoveAll { (x: String) -> Bool in x != sp } }
        var delay = 0.3
        for oid in outIds
        {
            let pp: Pet! = Get(oid)
            if pp == nil { continue }
            let p2: Pet = pp
            Later(delay) { [self] in BringOut(p2, oid == pet) }
            delay += 0.45
        }
        active = Get(pet) ?? Get(defaultPet)
        Broadcast()
        CuBroadcast()
    }

    // 新做好一隻（或改好）：住進我的櫃、叫他出來
    func CuCreated(_ id: String, _ first: Bool, _ edit: Bool)
    {
        CuStore.Reset(false)
        let mine = List<String>(Pal.MineIds())
        if !mine.Contains(id)
        {
            if mine.Count >= 4
            {
                // 滿了：換掉一隻作客的（沒有就換掉最後一隻）
                var gi = -1
                var i = mine.Count - 1
                while i >= 0 { if CuStore.Get(mine[i]) == nil { gi = i; break }; i -= 1 }
                mine.RemoveAt(gi >= 0 ? gi : mine.Count - 1)
            }
            mine.Insert(0, id)
            Pal.SaveMine(mine)
        }
        CuBroadcast()   // 先讓 VS Code 知道有「我的櫃」，等一下換櫃的通知它才認得
        if first || Single
        {
            ApplySetup(Pal.Mine, true, id, first)
            if lineup == Pal.Mine { CuReload(id) }
        }
        else if lineup != Pal.Mine { SwitchLineup(Pal.Mine, id) }
        else { CuReload(id) }
        let p: Pet! = Get(id)
        if p != nil && !edit { let pp: Pet = p; Later(1.4) { if pp.Out { pp.Say(pp.L("hi"), 3) } } }
        CuBroadcast()
    }

    func CuDeleted(_ id: String)
    {
        if Single && singleId == id { singleId = ""; World.WriteText("mode.txt", "single ") }
        let mine = List<String>(Pal.MineIds()); mine.Remove(id); Pal.SaveMine(mine)
        if lineup == Pal.Mine { let l: Pet! = Lead(); CuReload(l != nil && l.P.Id != id ? l.P.Id : "") }
        else { CuStore.Reset(false) }
        CuBroadcast()
    }

    // ---------- 小屋選單：做一隻自己的公仔、我的公仔（編輯／匯出／刪除）、我的櫃放誰、分享短片 ----------
    func CuHouseMenu(_ m: ContextMenuStrip)
    {
        m.Items.Add(ToolStripSeparator())
        m.Items.Add(ToolStripLabel("自己做的公仔"))
        m.Items.Add("做一隻自己的公仔（貓狗照片也可以）…", nil, { [self] in CuOpenMaker(nil, false) })
        let cus = CuStore.All()
        if cus.Count > 0
        {
            let my = ToolStripMenuItem("我的公仔")
            for cm in cus
            {
                let mm: CuMeta = cm
                let it = ToolStripMenuItem(mm.Name)
                it.DropDownItems.Add("叫他出來", nil, { [self] in CuCallOut(mm.Id) })
                it.DropDownItems.Add("修改（去背、動作、個性）…", nil, { [self] in CuOpenMaker(mm.Id, false) })
                it.DropDownItems.Add("匯出成檔案（傳給朋友）…", nil, { [self] in CuExportDialog(mm.Id) })
                let del = ToolStripMenuItem("刪除…")
                del.DropDownItems.Add("確定刪除「" + mm.Name + "」（不能復原）", nil, { [self] in CuDelete(mm.Id) })
                it.DropDownItems.Add(del)
                my.DropDownItems.Add(it)
            }
            m.Items.Add(my)
            let room = ToolStripMenuItem("我的櫃要放誰（最多 4 隻）")
            let mine = List<String>(Pal.MineIds())
            for cm in cus { CuMineItem(room, cm.Id, cm.Name, mine) }
            let guests = ToolStripMenuItem("請內建公仔來作客")
            for gid in Pal.Guests { let gp: Pal! = Pal.Get(gid); if gp != nil { CuMineItem(guests, gid, gp.Name, mine) } }
            room.DropDownItems.Add(guests)
            m.Items.Add(room)
        }
        m.Items.Add("匯入朋友的公仔（.deskpal）…", nil, { [self] in CuImportDialog(false) })
        m.Items.Add("做分享短片（GIF）…", nil, { [self] in ShareClip(nil) })
    }

    func CuMineItem(_ parent: ToolStripMenuItem, _ id: String, _ name: String, _ mine: List<String>)
    {
        let it = ToolStripMenuItem(name)
        it.CheckOnClick = true
        it.Checked = mine.Contains(id)
        it.Click = { [self] in CuToggleMine(id); it.Checked = List<String>(Pal.MineIds()).Contains(id) }
        parent.DropDownItems.Add(it)
    }

    func CuToggleMine(_ id: String)
    {
        let mine = List<String>(Pal.MineIds())
        let l: Pet! = Lead()
        if mine.Contains(id)
        {
            var cus = 0; for x in mine { if CuStore.Get(x) != nil { cus += 1 } }
            if cus <= 1 && CuStore.Get(id) != nil { l.Say("我的櫃至少要有一隻自己做的公仔喔", 2.4); return }
            mine.Remove(id)
        }
        else
        {
            if mine.Count >= 4 { l.Say("我的櫃只有 4 格，先拿掉一隻再放", 2.4); return }
            mine.Add(id)
        }
        Pal.SaveMine(mine)
        if lineup == Pal.Mine { CuReload(l != nil && mine.Contains(l.P.Id) ? l.P.Id : "") }
    }

    func CuCallOut(_ id: String)
    {
        let mine = List<String>(Pal.MineIds())
        if !mine.Contains(id) { if mine.Count >= 4 { mine.RemoveAt(mine.Count - 1) }; mine.Insert(0, id); Pal.SaveMine(mine) }
        if Single { singleId = id; World.WriteText("mode.txt", "single " + id) }
        if lineup != Pal.Mine { SwitchLineup(Pal.Mine, id) }
        else { CuReload(id) }
    }

    func CuDelete(_ id: String)
    {
        let m: CuMeta! = CuStore.Get(id)
        if m == nil { return }
        CuStore.Delete(id)
        CuDeleted(id)
        Lead().Say("「" + m.Name + "」刪掉了。想他的話可以再做一隻 🧸", 2.8)
    }

    // 右鍵選單：分享短片；自己做的公仔可以直接修改
    func CuPetMenu(_ p: Pet, _ m: ContextMenuStrip)
    {
        m.Items.Add("做分享短片（GIF）…", nil, { [self] in ShareClip(p) })
        if p.P.Cu { m.Items.Add("修改 " + p.P.Name + "（去背、動作、個性）…", nil, { [self] in CuOpenMaker(p.P.Id, false) }) }
    }

    // ---------- 跟 VS Code 說：自己做的公仔有誰（名字、狀態列圖示、側邊欄小圖） ----------
    func CuPalsJson() -> String
    {
        var l: [Any] = []
        for m in CuStore.All()
        {
            let d = Dict<String, Any>()
            d["id"] = m.Id; d["name"] = m.Name; d["emoji"] = Pal.PersonaEmoji(m.Persona)
            let ic = Path.Combine(CuStore.Dir(m.Id), "icon.png")
            d["img"] = File.Exists(ic) ? ic : ""
            // 側邊欄的小公仔要講的話（跟桌面上同一套個性）
            let p: Pal! = Pal.Get(m.Id)
            if p != nil
            {
                let lines = Dict<String, Any>()
                for k in ["hi", "hi_d", "save", "save_d", "pats", "pats_d", "tickle", "errors", "errors_d", "errors_ok", "errors_ok_d", "rest", "rest_d", "wake", "wake_d", "sleep", "night_on", "night_off", "x_sig"]
                { var a: [String] = []; if p.Lines.TryGetValue(k, &a) { lines[k] = a.map { $0 as Any } } }
                d["lines"] = lines
            }
            l.append(d)
        }
        let o = Dict<String, Any>()
        o["pals"] = l; o["mine"] = Pal.MineIds().map { $0 as Any }
        return JavaScriptSerializer().Serialize(o)
    }
    // ---------- 測試用：離屏隔離模式下放一個假視窗（喵系坐視窗、推東西要用） ----------
    func CuFake(_ h: IntPtr) -> Bool { return App.Isolated && h == cuFakeH }
    func CuFakeWins(_ nw: List<WinInfo>, _ nc: Dict<IntPtr, WinInfo>, _ np: List<Plat>)
    {
        if !App.Isolated || cuFakeR.IsEmpty { return }
        let wi = WinInfo(); wi.H = cuFakeH; wi.L = cuFakeR.Left; wi.T = cuFakeR.Top; wi.R = cuFakeR.Right; wi.B = cuFakeR.Bottom; wi.Z = nw.Count
        nw.Add(wi); nc[cuFakeH] = wi
        let p = Plat(); p.H = cuFakeH; p.Top = wi.T; p.Left = wi.L + 4; p.Right = wi.R - 4; p.WinLeft = wi.L; np.Add(p)
    }
    func CuSetFakeWin(_ r: Rectangle) { cuFakeR = App.Isolated ? r : Rectangle.Empty }

    func CuHello(_ c: Client) { World.Send(c, "pals " + CuPalsJson() + "\n") }
    func CuBroadcast() { let s = "pals " + CuPalsJson() + "\n"; lock(clients) { for c in clients { World.Send(c, s) } } }
}
