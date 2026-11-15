// 55_custom_image.swift — port of extension/desktop/DeskPals.CustomImage.cs
// Desk Pals：自己做公仔（上傳圖片）的影像處理——讀圖、去背、裁切、像素風／保留原圖、切頭身腳。
// 全部在本機算，不連網、不用任何外部套件；只用 System.Drawing。
// mac: C# 的 int ARGB（有號 32 位元）在這裡是 Int，存成 0…0xFFFFFFFF（不預乘）；只用 `>> 24 & 255`、`& 255`、`== 0` 這幾種運算，
//      所以跟 C# 的有號值一樣。LockBits／Marshal.Copy → 直接讀寫 CGBitmapContext（BGRA 預乘，換算成不預乘）；
//      Image.FromStream＋EXIF → CGImageSource（照 kCGImagePropertyOrientation 轉正）。
import Foundation
import AppKit
import ImageIO

// 去背、像素化的結果（內部像素：像素風一格＝Sub 個像素，保留原圖一格＝8 個像素）
final class CuCut {
    var W = 0, H = 0
    var Px: [Int] = []            // ARGB（不預乘）
    var A: [Int] { var a = [Int](repeating: 0, count: Px.count); for i in 0..<Px.count { a[i] = (Px[i] >> 24) & 255 }; return a }
    init() {}
}

enum CuImg {
    static let MaxSrc = 640              // 處理用的原圖最長邊（照片太大先縮）
    static let MaxFileBytes = 40 << 20   // 40MB 以上的檔案不讀
    static let HCells = 16, WCells = 22  // 公仔最高 16 格、最寬 22 格（跟內建的差不多大）
    static let SmoothR = 8               // 保留原圖：一格 8 個像素

    // ---------- 像素陣列 ----------
    // mac: 處理用的 Bitmap 一律 1 倍（邏輯像素＝實際像素）；Retina 的 Bitmap 先縮回邏輯大小再讀
    static func NewBmp(_ w: Int, _ h: Int) -> Bitmap { return Bitmap(Math.Max(1, w), Math.Max(1, h), PixelFormat.Format32bppArgb, 1) }

    static func Pixels(_ b: Bitmap) -> [Int] {
        let w = b.Width, h = b.Height
        var a = [Int](repeating: 0, count: w * h)
        var ctx: CGContext = b.ctx
        if ctx.width != w || ctx.height != h {
            guard let img = b.ctx.makeImage(),
                  let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: _gdiColorSpace,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return a }
            c.interpolationQuality = .high
            c.setBlendMode(.copy)
            c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            ctx = c
        }
        guard let data = ctx.data else { return a }
        let p = data.assumingMemoryBound(to: UInt8.self)
        let bpr = ctx.bytesPerRow
        for y in 0..<h {
            var o = y * bpr   // CGBitmapContext 記憶體第 0 列＝最上面那列
            for x in 0..<w {
                let bb = Int(p[o]), gg = Int(p[o + 1]), rr = Int(p[o + 2]), aa = Int(p[o + 3])
                if aa == 0 { a[y * w + x] = 0 }
                else if aa == 255 { a[y * w + x] = (255 << 24) | (rr << 16) | (gg << 8) | bb }
                else {
                    let r2 = Swift.min(255, (rr * 255 + aa / 2) / aa), g2 = Swift.min(255, (gg * 255 + aa / 2) / aa), b2 = Swift.min(255, (bb * 255 + aa / 2) / aa)
                    a[y * w + x] = (aa << 24) | (r2 << 16) | (g2 << 8) | b2
                }
                o += 4
            }
        }
        return a
    }

    static func FromPixels(_ px: [Int], _ w: Int, _ h: Int) -> Bitmap {
        let b = NewBmp(w, h)
        if w <= 0 || h <= 0 { return b }
        let ctx = b.ctx
        guard let data = ctx.data, ctx.width == w, ctx.height == h else { return b }
        let p = data.assumingMemoryBound(to: UInt8.self)
        let bpr = ctx.bytesPerRow
        for y in 0..<h {
            var o = y * bpr
            for x in 0..<w {
                let v = px[y * w + x]
                let aa = (v >> 24) & 255
                if aa == 0 { p[o] = 0; p[o + 1] = 0; p[o + 2] = 0; p[o + 3] = 0 }
                else {
                    let rr = (v >> 16) & 255, gg = (v >> 8) & 255, bb = v & 255
                    p[o] = UInt8((bb * aa + 127) / 255); p[o + 1] = UInt8((gg * aa + 127) / 255); p[o + 2] = UInt8((rr * aa + 127) / 255); p[o + 3] = UInt8(aa)
                }
                o += 4
            }
        }
        return b
    }

    static func Argb(_ a: Int, _ r: Int, _ g: Int, _ b: Int) -> Int { return (Clamp255(a) << 24) | (Clamp255(r) << 16) | (Clamp255(g) << 8) | Clamp255(b) }
    static func Clamp255(_ v: Int) -> Int { return v < 0 ? 0 : (v > 255 ? 255 : v) }
    static func Clamp255(_ v: Double) -> Int { return v < 0 ? 0 : (v > 255 ? 255 : CInt(Math.Round(v))) }

    // ---------- 讀圖：PNG／JPG／GIF（第一格）／BMP；照 EXIF 轉正；太大先縮 ----------
    static func LoadFile(_ path: String, _ err: inout String!) -> Bitmap! {
        err = nil
        let fi = FileInfo(path)
        if !fi.Exists { err = "找不到這個檔案"; return nil }
        if fi.Length > MaxFileBytes { err = "這張圖太大了（超過 40MB），換一張小一點的"; return nil }
        do { let bytes = try File.ReadAllBytes(path); return Decode(bytes, MaxSrc, &err) }
        catch { err = "打不開這張圖（" + error.Message + "）"; return nil }
    }

    static func Decode(_ bytes: [UInt8], _ maxDim: Int, _ err: inout String!) -> Bitmap! {
        err = nil
        // mac: Image.FromStream → CGImageSource（GIF 取第一格）
        guard let src = CGImageSourceCreateWithData(Data(bytes) as CFData, nil), CGImageSourceGetCount(src) > 0,
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { err = "這個檔案不是看得懂的圖片（格式不支援）"; return nil }
        let iw = img.width, ih = img.height
        if iw * ih > 60000000 || iw < 1 || ih < 1 { err = "這張圖的尺寸太誇張了，換一張吧"; return nil }
        let full = NewBmp(iw, ih)
        do {
            let c = full.ctx
            c.saveGState()
            c.setBlendMode(.copy)
            c.interpolationQuality = .none
            c.draw(img, in: CGRect(x: 0, y: 0, width: iw, height: ih))
            c.restoreGState()
        }
        let fixed = ExifFix(full, ExifOrientation(src))
        return Shrink(fixed, maxDim)
    }

    // 手機照片常常是「躺著存、EXIF 說要轉」
    // mac: EXIF 0x0112 → kCGImagePropertyOrientation（同一個值）
    static func ExifOrientation(_ src: CGImageSource) -> Int {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return 1 }
        if let o = props[kCGImagePropertyOrientation] as? Int { return o }
        if let n = props[kCGImagePropertyOrientation] as? NSNumber { return n.intValue }
        return 1
    }

    // C# 的 RotateFlip（2 RotateNoneFlipX、3 Rotate180FlipNone、4 Rotate180FlipX、5 Rotate90FlipX、6 Rotate90FlipNone、7 Rotate270FlipX、8 Rotate270FlipNone）
    // mac: 直接搬（預乘的）像素，不經過換算，跟 GDI+ 的 RotateFlip 一樣是無損的
    static func ExifFix(_ b: Bitmap, _ o: Int) -> Bitmap {
        if o < 2 || o > 8 { return b }
        let w = b.Width, h = b.Height
        let swap = o >= 5
        let ow = swap ? h : w, oh = swap ? w : h
        let r = NewBmp(ow, oh)
        guard let sd = b.ctx.data, let dd = r.ctx.data, b.ctx.width == w, b.ctx.height == h, r.ctx.width == ow, r.ctx.height == oh else { return b }
        let sp = sd.assumingMemoryBound(to: UInt32.self), dp = dd.assumingMemoryBound(to: UInt32.self)
        let sbpr = b.ctx.bytesPerRow / 4, dbpr = r.ctx.bytesPerRow / 4
        for y in 0..<oh {
            for x in 0..<ow {
                var ix = x, iy = y
                switch o {
                case 2: ix = w - 1 - x; iy = y
                case 3: ix = w - 1 - x; iy = h - 1 - y
                case 4: ix = x; iy = h - 1 - y
                case 5: ix = y; iy = x
                case 6: ix = y; iy = h - 1 - x
                case 7: ix = w - 1 - y; iy = h - 1 - x
                default: ix = w - 1 - y; iy = x   // 8
                }
                dp[y * dbpr + x] = sp[iy * sbpr + ix]
            }
        }
        return r
    }

    static func Shrink(_ src: Bitmap, _ maxDim: Int) -> Bitmap {
        let s = Math.Min(1.0, Double(maxDim) / Double(Math.Max(src.Width, src.Height)))
        let nw = Math.Max(1, CInt(Math.Round(Double(src.Width) * s))), nh = Math.Max(1, CInt(Math.Round(Double(src.Height) * s)))
        let b = NewBmp(nw, nh)
        // mac: HighQualityBicubic → interpolationQuality .high；NearestNeighbor → .none；邊緣不會糊出一圈半透明（CG 取樣不出界）
        guard let img = src.ctx.makeImage() else { return b }
        let c = b.ctx
        c.saveGState()
        c.setBlendMode(.copy)
        c.interpolationQuality = s < 1 ? .high : .none
        c.draw(img, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        c.restoreGState()
        return b
    }

    // 這張圖本來就有透明背景嗎？
    static func HasAlpha(_ px: [Int], _ w: Int, _ h: Int) -> Bool {
        var clear = 0, edgeClear = 0, edge = 0
        for y in 0..<Math.Max(0, h) {
            for x in 0..<Math.Max(0, w) {
                let a = (px[y * w + x] >> 24) & 255
                if a < 128 { clear += 1 }
                if x == 0 || y == 0 || x == w - 1 || y == h - 1 { edge += 1; if a < 128 { edgeClear += 1 } }
            }
        }
        return clear > px.count / 100 && edgeClear * 5 > edge
    }

    // ---------- 顏色距離（紅均值加權，接近人眼） ----------
    @inline(__always) static func Dist(_ r1: Int, _ g1: Int, _ b1: Int, _ r2: Int, _ g2: Int, _ b2: Int) -> Double {
        let rm = Double(r1 + r2) / 2.0, dr = Double(r1 - r2), dg = Double(g1 - g2), db = Double(b1 - b2)
        let t1: Double = (2 + rm / 256) * dr * dr
        let t2: Double = 4 * dg * dg
        let t3: Double = (2 + (255 - rm) / 256) * db * db
        return Math.Sqrt(t1 + t2 + t3) / 3.0
    }
    static func TolToT(_ tol: Int) -> Double { return 6 + Double(Math.Max(0, Math.Min(100, tol))) * 0.9 }   // 去背強度 0～100 → 顏色距離門檻

    // ---------- 自動去背：從四邊取背景色（分群），從邊往內長；毛邊半透明、去掉背景色暈；只留最大的那塊 ----------
    static func RemoveBg(_ px: [Int], _ w: Int, _ h: Int, _ tol: Int) -> [Int] {
        let n = w * h
        var R = [Int](repeating: 0, count: n), G = [Int](repeating: 0, count: n), B = [Int](repeating: 0, count: n)
        for i in 0..<n { R[i] = (px[i] >> 16) & 255; G[i] = (px[i] >> 8) & 255; B[i] = px[i] & 255 }
        let T = TolToT(tol)
        // 1) 邊框兩圈像素分群（最多 5 群），太少的群丟掉
        // 背景色只從上、左、右三邊取（寵物照常常被下緣切到，下緣多半是主角）；下緣只拿來當起點
        var border: [Int] = [], side: [Int] = []
        let bw = Math.Max(1, Math.Min(3, Math.Min(w, h) / 40 + 1))
        for y in 0..<h {
            for x in 0..<w {
                if x < bw || y < bw || x >= w - bw || y >= h - bw {
                    border.append(y * w + x)
                    if y < h - bw { side.append(y * w + x) }
                }
            }
        }
        var cen: List<[Double]> = KMeans(side, R, G, B, 5)
        // 主角也碰到邊的時候，那一群其實是主角：中間那塊很多這個顏色的群（除了最大的那群）不算背景
        if cen.Count > 1 {
            let cx0 = w * 35 / 100, cx1 = w * 65 / 100, cy0 = h * 35 / 100, cy1 = h * 65 / 100
            var tot = 0
            var hit = [Int](repeating: 0, count: cen.Count)
            var y = cy0
            while y < cy1 {
                var x = cx0
                while x < cx1 {
                    let i = y * w + x; tot += 1
                    for k in 0..<cen.Count { if Dist(R[i], G[i], B[i], CInt(cen[k][0]), CInt(cen[k][1]), CInt(cen[k][2])) < T { hit[k] += 1 } }
                    x += 2
                }
                y += 2
            }
            let keep = List<[Double]>()
            for k in 0..<cen.Count { if k == 0 || tot == 0 || hit[k] * 100 < tot * 10 { keep.Add(cen[k]) } }
            cen = keep
        }
        // 2) 每個像素到最近背景色的距離
        let cens: [[Int]] = cen.ToArray().map { [CInt($0[0]), CInt($0[1]), CInt($0[2])] }
        var dmin = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var best = 1e9
            for c in cens { let d = Dist(R[i], G[i], B[i], c[0], c[1], c[2]); if d < best { best = d } }
            dmin[i] = best
        }
        // 3) 從邊框往內長：像背景色的、或跟旁邊背景很接近（漸層、陰影）的都算背景
        var bg = [Bool](repeating: false, count: n)
        var q = [Int](repeating: 0, count: n); var qh = 0, qt = 0
        for i in border { if dmin[i] < T && !bg[i] { bg[i] = true; q[qt] = i; qt += 1 } }
        while qh < qt {
            let p = q[qh]; qh += 1
            let x = p % w, y = p / w
            for k in 0..<4 {
                let nx = x + (k == 0 ? 1 : (k == 1 ? -1 : 0)), ny = y + (k == 2 ? 1 : (k == 3 ? -1 : 0))
                if nx < 0 || ny < 0 || nx >= w || ny >= h { continue }
                let o = ny * w + nx
                if bg[o] { continue }
                let ok = dmin[o] < T || (dmin[o] < T * 1.6 && Dist(R[o], G[o], B[o], R[p], G[p], B[p]) < T * 0.22)
                if ok { bg[o] = true; q[qt] = o; qt += 1 }
            }
        }
        // 4) alpha：背景 0；靠近背景的那一圈照「跟旁邊背景色差多少」給半透明（毛邊），並把背景色暈掉
        var outPx = [Int](repeating: 0, count: n)
        for i in 0..<n { outPx[i] = bg[i] ? 0 : (px[i] | 0xFF000000) }
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if bg[i] { continue }
                var sr = 0.0, sg = 0.0, sb = 0.0; var cnt = 0
                for dy in -2...2 {
                    for dx in -2...2 {
                        let xx = x + dx, yy = y + dy
                        if xx < 0 || yy < 0 || xx >= w || yy >= h { continue }
                        let o = yy * w + xx
                        if !bg[o] { continue }
                        sr += Double(R[o]); sg += Double(G[o]); sb += Double(B[o]); cnt += 1
                    }
                }
                if cnt == 0 { continue }
                let br = sr / Double(cnt), bgc = sg / Double(cnt), bb = sb / Double(cnt)
                let dl = Dist(R[i], G[i], B[i], CInt(br), CInt(bgc), CInt(bb))
                let a = Math.Max(0.0, Math.Min(1.0, (dl - T * 0.45) / (T * 1.1)))
                if a <= 0.02 { outPx[i] = 0; continue }
                // 去掉背景色暈：c = (c - (1-a)·bg) / a
                let cr = (Double(R[i]) - (1 - a) * br) / a, cg = (Double(G[i]) - (1 - a) * bgc) / a, cb = (Double(B[i]) - (1 - a) * bb) / a
                outPx[i] = Argb(CInt(Math.Round(a * 255)), CInt(Math.Round(cr)), CInt(Math.Round(cg)), CInt(Math.Round(cb)))
            }
        }
        KeepMain(&outPx, w, h)
        return outPx
    }

    // 邊框色分群（最遠點初始化＋幾輪 k-means）
    static func KMeans(_ idx: [Int], _ R: [Int], _ G: [Int], _ B: [Int], _ kmax: Int) -> List<[Double]> {
        let c = List<[Double]>()
        if idx.count == 0 { c.Add([255, 255, 255]); return c }
        var mr = 0.0, mg = 0.0, mb = 0.0
        for i in idx { mr += Double(R[i]); mg += Double(G[i]); mb += Double(B[i]) }
        let nIdx = Double(idx.count)
        c.Add([mr / nIdx, mg / nIdx, mb / nIdx])
        let step = Math.Max(1, idx.count / 4000)
        while c.Count < kmax {
            var far = 0.0; var fi = -1
            var s = 0
            while s < idx.count {
                let i = idx[s]; var best = 1e9
                for cc in c { best = Math.Min(best, Dist(R[i], G[i], B[i], CInt(cc[0]), CInt(cc[1]), CInt(cc[2]))) }
                if best > far { far = best; fi = i }
                s += step
            }
            if fi < 0 || far < 14 { break }
            c.Add([Double(R[fi]), Double(G[fi]), Double(B[fi])])
        }
        var cnt = [Int](repeating: 0, count: c.Count)
        for _ in 0..<6 {
            var sum = [[Double]](repeating: [0, 0, 0], count: c.Count)
            cnt = [Int](repeating: 0, count: c.Count)
            let ci: [[Int]] = c.ToArray().map { [CInt($0[0]), CInt($0[1]), CInt($0[2])] }
            for i in idx {
                var bk = 0; var best = 1e9
                for k in 0..<ci.count { let d = Dist(R[i], G[i], B[i], ci[k][0], ci[k][1], ci[k][2]); if d < best { best = d; bk = k } }
                sum[bk][0] += Double(R[i]); sum[bk][1] += Double(G[i]); sum[bk][2] += Double(B[i]); cnt[bk] += 1
            }
            for k in 0..<c.Count { if cnt[k] > 0 { c[k] = [sum[k][0] / Double(cnt[k]), sum[k][1] / Double(cnt[k]), sum[k][2] / Double(cnt[k])] } }
        }
        // 太少的群是剛好碰到邊的主角，不算背景
        // 由多到少排好（第一群＝最大的背景色）
        let order = List<Int>()
        for k in 0..<c.Count { if cnt[k] * 100 >= idx.count * 4 { order.Add(k) } }
        let cntF = cnt
        order.Sort { (a: Int, b: Int) -> Int in cntF[b].CompareTo(cntF[a]) }
        let keep = List<[Double]>()
        for k in order { keep.Add(c[k]) }
        if keep.Count == 0 { keep.Add(c[0]) }
        return keep
    }

    // 只留最大的那塊（和夠大的旁支，例如分開的耳朵、尾巴）
    static func KeepMain(_ px: inout [Int], _ w: Int, _ h: Int) {
        let n = w * h
        var lab = [Int](repeating: 0, count: n)
        var sizes: [Int] = [0]
        var q = [Int](repeating: 0, count: n)
        for s in 0..<n {
            if lab[s] != 0 || ((px[s] >> 24) & 255) < 96 { continue }
            let id = sizes.count
            var qh = 0, qt = 0, size = 0
            lab[s] = id; q[qt] = s; qt += 1
            while qh < qt {
                let p = q[qh]; qh += 1
                let x = p % w, y = p / w; size += 1
                for dy in -1...1 {
                    for dx in -1...1 {
                        let xx = x + dx, yy = y + dy
                        if xx < 0 || yy < 0 || xx >= w || yy >= h { continue }
                        let o = yy * w + xx
                        if lab[o] != 0 || ((px[o] >> 24) & 255) < 96 { continue }
                        lab[o] = id; q[qt] = o; qt += 1
                    }
                }
            }
            sizes.append(size)
        }
        var big = 0
        for i in 1..<sizes.count { big = Math.Max(big, sizes[i]) }
        if big == 0 { return }
        for i in 0..<n {
            let a = (px[i] >> 24) & 255
            if a == 0 { continue }
            let l = lab[i]
            if l == 0 {
                // 半透明的毛邊：旁邊有留下來的才留
                var near = false
                let x = i % w, y = i / w
                var dy = -1
                while dy <= 1 && !near {
                    var dx = -1
                    while dx <= 1 && !near {
                        let xx = x + dx, yy = y + dy
                        if !(xx < 0 || yy < 0 || xx >= w || yy >= h) {
                            let ll = lab[yy * w + xx]
                            if ll != 0 && sizes[ll] * 8 >= big { near = true }
                        }
                        dx += 1
                    }
                    dy += 1
                }
                if !near { px[i] = 0 }
            }
            else if sizes[l] * 8 < big { px[i] = 0 }
        }
    }

    // 筆刷：擦掉／補回（座標都是 0～1；補回＝原圖的顏色）
    static func ApplyStrokes(_ px: inout [Int], _ orig: [Int], _ w: Int, _ h: Int, _ strokes: List<[Double]>!) {
        if strokes == nil { return }
        let m = Double(Math.Max(w, h))
        for s in strokes! {
            if s.count < 4 { continue }
            let cx = s[0] * Double(w), cy = s[1] * Double(h), r = Math.Max(0.6, s[2] * m)
            let erase = s[3] > 0.5
            let x0 = Math.Max(0, CInt(cx - r - 1)), x1 = Math.Min(w - 1, CInt(cx + r + 1)), y0 = Math.Max(0, CInt(cy - r - 1)), y1 = Math.Min(h - 1, CInt(cy + r + 1))
            if y1 < y0 || x1 < x0 { continue }
            for y in y0...y1 {
                for x in x0...x1 {
                    let ddx = Double(x) + 0.5 - cx, ddy = Double(y) + 0.5 - cy
                    let d = Math.Sqrt(ddx * ddx + ddy * ddy)
                    if d > r { continue }
                    let i = y * w + x
                    if erase { px[i] = 0 }
                    else { px[i] = orig[i] | 0xFF000000 }
                }
            }
        }
    }

    // 透明的地方裁掉（四邊留 pad）
    static func Bounds(_ px: [Int], _ w: Int, _ h: Int, _ thr: Int) -> Rectangle {
        var l = w, t = h, r = -1, b = -1
        for y in 0..<Math.Max(0, h) {
            for x in 0..<Math.Max(0, w) {
                if ((px[y * w + x] >> 24) & 255) >= thr { if x < l { l = x }; if x > r { r = x }; if y < t { t = y }; if y > b { b = y } }
            }
        }
        if r < 0 { return Rectangle.Empty }
        return Rectangle.FromLTRB(l, t, r + 1, b + 1)
    }

    static func Crop(_ px: [Int], _ w: Int, _ h: Int, _ r: Rectangle) -> CuCut {
        let c = CuCut(); c.W = r.Width; c.H = r.Height; c.Px = [Int](repeating: 0, count: r.Width * r.Height)
        for y in 0..<Math.Max(0, r.Height) {
            let s0 = (r.Y + y) * w + r.X, d0 = y * r.Width
            for x in 0..<r.Width { c.Px[d0 + x] = px[s0 + x] }
        }
        return c
    }

    // 去背＋筆刷＋裁切：從原圖做出「主角」
    static func Cutout(_ src: Bitmap, _ useAlpha: Bool, _ tol: Int, _ strokes: List<[Double]>!, _ hadAlpha: inout Bool) -> CuCut! {
        let w = src.Width, h = src.Height
        let orig = Pixels(src)
        hadAlpha = HasAlpha(orig, w, h)
        var px: [Int]
        if hadAlpha && useAlpha {
            px = orig
            for i in 0..<px.count { if ((px[i] >> 24) & 255) < 10 { px[i] = 0 } }
        } else {
            var solid = orig
            for i in 0..<solid.count { if ((solid[i] >> 24) & 255) < 128 { solid[i] = 0xFFFFFFFF } else { solid[i] |= 0xFF000000 } }
            px = RemoveBg(solid, w, h, tol)
        }
        ApplyStrokes(&px, orig, w, h, strokes)
        let bb = Bounds(px, w, h, 40)
        if bb.Width < 2 || bb.Height < 2 { return nil }
        return Crop(px, w, h, bb)
    }

    // ---------- 大小：最高 16 格、最寬 20 格 ----------
    static func Fit(_ w: Int, _ h: Int, _ maxW: Double, _ maxH: Double, _ cw: inout Int, _ ch: inout Int) {
        let s = Math.Min(maxH / Double(h), maxW / Double(w))
        cw = Math.Max(1, CInt(Math.Round(Double(w) * s))); ch = Math.Max(1, CInt(Math.Round(Double(h) * s)))
    }

    // ---------- 保留原圖：平滑縮放（一格 8 像素） ----------
    static func ToSmooth(_ c: CuCut, _ hCells: Double, _ wCells: Double) -> CuCut {
        var cw = 0, ch = 0
        Fit(c.W, c.H, wCells * Double(SmoothR), hCells * Double(SmoothR), &cw, &ch)
        return ToSmoothSized(c, cw, ch)
    }
    static func ToSmooth(_ c: CuCut, _ hCells: Int, _ wCells: Int) -> CuCut { return ToSmooth(c, Double(hCells), Double(wCells)) }

    static func ToSmoothSized(_ c: CuCut, _ cw: Int, _ ch: Int) -> CuCut {
        let o = CuCut(); o.W = cw; o.H = ch
        o.Px = Resample(c, cw, ch)
        for i in 0..<o.Px.count { if ((o.Px[i] >> 24) & 255) < 14 { o.Px[i] = 0 } }
        return o
    }

    // 預乘平均的超取樣縮放（不會有黑邊）
    static func Resample(_ c: CuCut, _ tw: Int, _ th: Int) -> [Int] {
        var o = [Int](repeating: 0, count: Math.Max(0, tw * th))
        let sx = Double(c.W) / Double(tw), sy = Double(c.H) / Double(th)
        let nx = Math.Max(1, Math.Min(8, CInt(Math.Ceiling(sx * 2)))), ny = Math.Max(1, Math.Min(8, CInt(Math.Ceiling(sy * 2))))
        for y in 0..<Math.Max(0, th) {
            for x in 0..<Math.Max(0, tw) {
                var a = 0.0, r = 0.0, g = 0.0, b = 0.0; var cnt = 0
                for j in 0..<ny {
                    for i in 0..<nx {
                        let fx: Double = (Double(x) + (Double(i) + 0.5) / Double(nx)) * sx
                        let fy: Double = (Double(y) + (Double(j) + 0.5) / Double(ny)) * sy
                        let px = Math.Min(c.W - 1, CInt(fx)), py = Math.Min(c.H - 1, CInt(fy))
                        let v = c.Px[py * c.W + px]
                        let av = Double((v >> 24) & 255) / 255.0
                        a += av; r += av * Double((v >> 16) & 255); g += av * Double((v >> 8) & 255); b += av * Double(v & 255); cnt += 1
                    }
                }
                if a <= 0.0001 { o[y * tw + x] = 0; continue }
                o[y * tw + x] = Argb(CInt(Math.Round(a / Double(cnt) * 255)), CInt(Math.Round(r / a)), CInt(Math.Round(g / a)), CInt(Math.Round(b / a)))
            }
        }
        return o
    }

    // ---------- 像素風：縮到格子、減色、深色外框（跟內建公仔同一種畫法） ----------
    static func ToPixel(_ c: CuCut, _ sub: Int, _ hCells: Double, _ wCells: Double, _ outline: inout Color) -> CuCut {
        var cw = 0, ch = 0
        let maxH = hCells * Double(sub) - 2, maxW = wCells * Double(sub) - 2
        // 本來就很小的圖（多半是像素圖）：用整數倍放大，才不會一格大一格小
        if Double(c.H) <= maxH && Double(c.W) <= maxW {
            let k = Math.Max(1, CInt(Math.Floor(Math.Min(maxH / Double(c.H), maxW / Double(c.W)))))
            cw = c.W * k; ch = c.H * k
        }
        else { Fit(c.W, c.H, maxW, maxH, &cw, &ch) }
        return ToPixelSized(c, cw, ch, sub >= 2 ? 18 : 12, true, &outline)
    }
    static func ToPixel(_ c: CuCut, _ sub: Int, _ hCells: Int, _ wCells: Int, _ outline: inout Color) -> CuCut { return ToPixel(c, sub, Double(hCells), Double(wCells), &outline) }

    // 縮到 cw×ch（外框另外加一圈）；quant＝要不要減色（動作表是使用者自己畫的，不減）
    static func ToPixelSized(_ c: CuCut, _ cw: Int, _ ch: Int, _ K: Int, _ quant: Bool, _ outline: inout Color) -> CuCut {
        let small = Resample(c, cw, ch)
        let gw = cw + 2, gh = ch + 2
        var g = [Int](repeating: 0, count: gw * gh)
        let cols = List<Int>()
        for y in 0..<ch {
            for x in 0..<cw {
                var v = small[y * cw + x]
                if ((v >> 24) & 255) < 110 { continue }
                if quant { v = Punch(v) } else { v |= 0xFF000000 }
                g[(y + 1) * gw + x + 1] = v
                cols.Add(v)
            }
        }
        // 減色（中位切割）
        let pal = MedianCut(cols, quant ? K : 64)
        var use = [Int](repeating: 0, count: pal.Count)
        for i in 0..<g.count {
            if g[i] == 0 { continue }
            let best = Nearest(pal, g[i])
            if quant { g[i] = pal[best] | 0xFF000000 }
            use[best] += 1
        }
        // 孤零零的一個像素拿掉（雜點）
        var g2 = g
        if gh > 2 && gw > 2 {
            for y in 1..<(gh - 1) {
                for x in 1..<(gw - 1) {
                    let i = y * gw + x
                    if g[i] == 0 { continue }
                    let nb = (g[i - 1] != 0 ? 1 : 0) + (g[i + 1] != 0 ? 1 : 0) + (g[i - gw] != 0 ? 1 : 0) + (g[i + gw] != 0 ? 1 : 0)
                    if nb == 0 { g2[i] = 0 }
                }
            }
        }
        g = g2
        // 外框色：最多的那個顏色壓暗、帶一點藏青（內建公仔的 k 都是很深的有色黑）
        var dom = 0; for i in Loop(1, use.count) { if use[i] > use[dom] { dom = i } }
        let dc: Color = pal.Count > 0 ? Color.FromArgb(pal[dom]) : Color.Gray
        outline = Color.FromArgb(255, Clamp255(Double(dc.R) * 0.22 + Double(0x2A) * 0.45), Clamp255(Double(dc.G) * 0.22 + Double(0x2F) * 0.45), Clamp255(Double(dc.B) * 0.22 + Double(0x45) * 0.5))
        // 原圖邊緣本來就有深色外框（多半是像素圖、貼圖）：不要再多加一圈
        var el = 0, en = 0
        if gh > 2 && gw > 2 {
            for y in 1..<(gh - 1) {
                for x in 1..<(gw - 1) {
                    let i = y * gw + x
                    if g[i] == 0 || (g[i - 1] != 0 && g[i + 1] != 0 && g[i - gw] != 0 && g[i + gw] != 0) { continue }
                    let v = g[i]; el += (((v >> 16) & 255) * 299 + ((v >> 8) & 255) * 587 + (v & 255) * 114) / 1000; en += 1
                }
            }
        }
        if en > 0 && el / en < 75 { let r0 = CuCut(); r0.W = gw; r0.H = gh; r0.Px = g; return r0 }
        let ok = outline.ToArgb() & 0xFFFFFFFF
        var o2 = g
        for y in 0..<gh {
            for x in 0..<gw {
                let i = y * gw + x
                if g[i] != 0 { continue }
                let edge = (x > 0 && g[i - 1] != 0) || (x < gw - 1 && g[i + 1] != 0) || (y > 0 && g[i - gw] != 0) || (y < gh - 1 && g[i + gw] != 0)
                if edge { o2[i] = ok }
            }
        }
        let r = CuCut(); r.W = gw; r.H = gh; r.Px = o2
        return r
    }

    // 像素風顏色稍微飽和一點（照片縮小後會灰灰的）
    static func Punch(_ v: Int) -> Int {
        let r = (v >> 16) & 255, g = (v >> 8) & 255, b = v & 255
        let l = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b), s = 1.18
        return Argb(255, CInt(l + (Double(r) - l) * s), CInt(l + (Double(g) - l) * s), CInt(l + (Double(b) - l) * s))
    }

    static func Nearest(_ pal: List<Int>, _ v: Int) -> Int {
        let r = (v >> 16) & 255, g = (v >> 8) & 255, b = v & 255
        var best = 0; var bd = 1e9
        for i in 0..<pal.Count {
            let p = pal[i]
            let d = Dist(r, g, b, (p >> 16) & 255, (p >> 8) & 255, p & 255)
            if d < bd { bd = d; best = i }
        }
        return best
    }

    // 中位切割減色（K 色）
    static func MedianCut(_ cols: List<Int>, _ K: Int) -> List<Int> {
        let pal = List<Int>()
        if cols.Count == 0 { pal.Add(0xFF808080); return pal }
        let boxes = List<List<Int>>()
        boxes.Add(List<Int>(cols))
        let wgt: [Double] = [1.0, 1.25, 0.9]
        while boxes.Count < K {
            var bi = -1, ch = 0; var bestScore = 0.0
            for i in 0..<boxes.Count {
                let bx = boxes[i]
                if bx.Count < 2 { continue }
                var mn = [255, 255, 255], mx = [0, 0, 0]
                for v in bx.items {
                    for c in 0..<3 { let cv = (v >> (16 - 8 * c)) & 255; if cv < mn[c] { mn[c] = cv }; if cv > mx[c] { mx[c] = cv } }
                }
                let sq = Math.Sqrt(Double(bx.Count))
                for c in 0..<3 {
                    let score = Double(mx[c] - mn[c]) * wgt[c] * sq
                    if score > bestScore { bestScore = score; bi = i; ch = c }
                }
            }
            if bi < 0 || bestScore < 1 { break }
            let box = boxes[bi]
            let sh = 16 - 8 * ch
            box.Sort { (a: Int, b: Int) -> Int in ((a >> sh) & 255).CompareTo((b >> sh) & 255) }
            let mid = box.Count / 2
            boxes[bi] = box.GetRange(0, mid)
            boxes.Add(box.GetRange(mid, box.Count - mid))
        }
        for bx in boxes {
            if bx.Count == 0 { continue }
            var r = 0, g = 0, b = 0
            for v in bx.items { r += (v >> 16) & 255; g += (v >> 8) & 255; b += v & 255 }
            pal.Add(Argb(255, r / bx.Count, g / bx.Count, b / bx.Count))
        }
        return pal
    }

    // ---------- 切頭身腳：猜兩條線的位置（0～1） ----------
    // 頭／身體：中段最窄的那列（脖子）；身體／腳：從下面往上，中間開始有空隙（兩隻腳）的那列
    static func GuessLines(_ c: CuCut, _ neck: inout Double, _ hip: inout Double, _ confident: inout Bool) {
        let w = c.W, h = c.H
        var width = [Int](repeating: 0, count: h), left = [Int](repeating: 0, count: h), right = [Int](repeating: 0, count: h)
        for y in 0..<h {
            var l = -1, r = -1
            for x in 0..<w { if ((c.Px[y * w + x] >> 24) & 255) >= 110 { if l < 0 { l = x }; r = x } }
            left[y] = l; right[y] = r; width[y] = l < 0 ? 0 : r - l + 1
        }
        // 脖子
        neck = 0.42; var neckOk = false
        let y0 = CInt(Double(h) * 0.22), y1 = CInt(Double(h) * 0.6)
        var best = -1; var bv = 1e9
        var y = y0
        while y <= y1 && y < h {
            var sm = 0.0; var cnt = 0
            for d in -1...1 { if y + d >= 0 && y + d < h { sm += Double(width[y + d]); cnt += 1 } }
            sm /= Double(cnt)
            if sm < bv { bv = sm; best = y }
            y += 1
        }
        if best > 0 {
            var above = 0, below = 0
            for y2 in 0..<best { above = Math.Max(above, width[y2]) }
            for y2 in best..<h { below = Math.Max(below, width[y2]) }
            if bv < Double(above) * 0.86 && bv < Double(below) * 0.9 { neck = Double(best) / Double(h); neckOk = true }
        }
        // 腳：中間有空隙
        hip = 0.78; var hipOk = false
        var run = 0
        var yy = h - 1
        let yStop = CInt(Double(h) * 0.55)
        while yy >= yStop {
            var gap = false
            if width[yy] > 2 {
                let l = left[yy], r = right[yy], m0 = l + (r - l) / 5, m1 = r - (r - l) / 5
                var firstOn = -1
                var seenGap = false
                for x in l...r {
                    let on = ((c.Px[yy * w + x] >> 24) & 255) >= 110
                    if on && firstOn < 0 { firstOn = x }
                    if !on && firstOn >= 0 && x >= m0 && x <= m1 { seenGap = true }
                    if on && seenGap { gap = true; break }
                }
            }
            if gap { run += 1 }
            else if run > 0 { break }
            yy -= 1
        }
        if Double(run) >= Math.Max(2.0, Double(h) * 0.07) {
            let hp = 1 - (Double(run) + 0.5) / Double(h)
            if hp > neck + 0.12 && hp < 0.95 { hip = hp; hipOk = true }
        }
        if hip < neck + 0.15 { hip = Math.Min(0.92, neck + 0.3) }
        confident = hipOk && neckOk || (hipOk && Double(run) >= Double(h) * 0.12)
    }

    // 兩隻腳的分界（腳那一段最空的那一欄）
    static func LegSplit(_ c: CuCut, _ hipRow: Int) -> Int {
        let w = c.W, h = c.H
        var l = w, r = -1
        for y in Loop(Math.Max(0, hipRow), h) { for x in 0..<w { if ((c.Px[y * w + x] >> 24) & 255) >= 110 { if x < l { l = x }; if x > r { r = x } } } }
        if r < 0 { return w / 2 }
        let m0 = l + (r - l) / 4, m1 = r - (r - l) / 4
        var best = (l + r + 1) / 2, bv = int.MaxValue
        var x = m0
        while x <= m1 {
            var cnt = 0
            for y in Loop(Math.Max(0, hipRow), h) { if ((c.Px[y * w + x] >> 24) & 255) >= 110 { cnt += 1 } }
            let score = cnt * 4 + Math.Abs(x - (l + r) / 2)
            if score < bv { bv = score; best = x }
            x += 1
        }
        return best
    }

    static func ToBitmap(_ c: CuCut) -> Bitmap { return FromPixels(c.Px, c.W, c.H) }
    static func FromBitmap(_ b: Bitmap) -> CuCut { let c = CuCut(); c.W = b.Width; c.H = b.Height; c.Px = Pixels(b); return c }
    static func Mirror(_ c: CuCut) -> CuCut {
        let o = CuCut(); o.W = c.W; o.H = c.H; o.Px = [Int](repeating: 0, count: c.Px.count)
        for y in 0..<c.H { for x in 0..<c.W { o.Px[y * c.W + x] = c.Px[y * c.W + c.W - 1 - x] } }
        return o
    }
    // 主要顏色（不透明像素的平均，忽略外框）
    static func MainColor(_ c: CuCut) -> Color {
        var r = 0, g = 0, b = 0, n = 0
        for v in c.Px {
            if ((v >> 24) & 255) < 200 { continue }
            let rr = (v >> 16) & 255, gg = (v >> 8) & 255, bb = v & 255
            if rr + gg + bb < 120 { continue }
            r += rr; g += gg; b += bb; n += 1
        }
        if n == 0 { return Color.FromArgb(0x8A, 0x9A, 0xB8) }
        return Color.FromArgb(r / n, g / n, b / n)
    }
}
