// 03_shim_custom_a.swift — System.Drawing bits the custom-pal renderer (53_custom.swift) needs:
// - Matrix(m11, m12, m21, m22, dx, dy) and Matrix.Clone() (Translate/Rotate/Scale already prepend like GDI+, see 01_drawing.swift)
// - Graphics.DrawImage(img, PointF[3] destParallelogram, srcRect, unit[, ImageAttributes]) — GDI+'s three-point overload
// - ImageAttributes with a full ColorMatrix: applied per pixel (un-premultiplied, clamped, re-premultiplied) like GDI+
// - Bitmap.CuReadP / CuWriteP: raw premultiplied ARGB of the device pixels (= C# LockBits Format32bppPArgb on a 1× bitmap)
import Foundation
import CoreGraphics

extension Matrix {
    /// GDI+ `new Matrix(m11, m12, m21, m22, dx, dy)`: (x, y) → (x·m11 + y·m21 + dx, x·m12 + y·m22 + dy)
    convenience init(_ m11: Double, _ m12: Double, _ m21: Double, _ m22: Double, _ dx: Double, _ dy: Double) {
        self.init(CGAffineTransform(a: CGFloat(m11), b: CGFloat(m12), c: CGFloat(m21), d: CGFloat(m22), tx: CGFloat(dx), ty: CGFloat(dy)))
    }
    func Clone() -> Matrix { return Matrix(t) }
}

extension Graphics {
    /// `g.DrawImage(img, new PointF[] { upperLeft, upperRight, lowerLeft }, srcRect, GraphicsUnit.Pixel)`
    func DrawImage(_ b: Bitmap?, _ pts: [PointF], _ src: RectangleF, _ unit: GraphicsUnit) { DrawImage(b, pts, src, unit, nil) }
    func DrawImage(_ b: Bitmap?, _ pts: [PointF], _ src: RectangleF, _ unit: GraphicsUnit, _ ia: ImageAttributes?) {
        guard let b = b, pts.count >= 3, src.Width > 0, src.Height > 0 else { return }
        let p0 = pts[0], p1 = pts[1], p2 = pts[2]
        // 把 (0,0)-(w,h) 對到平行四邊形（左上、右上、左下），再接上目前的世界座標
        let a = CGAffineTransform(a: CGFloat((p1.X - p0.X) / src.Width), b: CGFloat((p1.Y - p0.Y) / src.Width),
                                  c: CGFloat((p2.X - p0.X) / src.Height), d: CGFloat((p2.Y - p0.Y) / src.Height),
                                  tx: CGFloat(p0.X), ty: CGFloat(p0.Y))
        let old = Transform
        Transform = Matrix(a.concatenating(old.t))
        DrawImage(b, RectangleF(0, 0, src.Width, src.Height), src.X, src.Y, src.Width, src.Height, unit, ia)
        Transform = old
    }
}

extension ImageAttributes {
    /// 只有 Matrix33（透明度）不是 1 的話照舊用 setAlpha；其他的（上色、變暗）逐像素算
    var CuNeedsPixelPass: Bool {
        guard let m = matrix else { return false }
        for i in 0..<5 {
            for j in 0..<5 {
                if i == 3 && j == 3 { continue }
                let want: Double = i == j ? 1 : 0
                if m.M[i][j] != want { return true }
            }
        }
        return false
    }

    /// GDI+ ColorMatrix: out = [r g b a 1] · M（0…1、不預乘），超出 0…1 就截掉
    func CuApply(_ img: CGImage) -> CGImage? {
        guard let m = matrix else { return img }
        let w = img.width, h = img.height
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: _gdiColorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        c.setBlendMode(.copy)
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = c.data else { return nil }
        let p = data.assumingMemoryBound(to: UInt8.self)
        let bpr = c.bytesPerRow
        let M = m.M
        func cl(_ v: Double) -> Double { return v < 0 ? 0 : (v > 1 ? 1 : v) }
        for y in 0..<h {
            var o = y * bpr
            for _ in 0..<w {
                let a0 = Double(p[o + 3]) / 255
                var r = 0.0, g = 0.0, b = 0.0
                if a0 > 0 { b = Double(p[o]) / 255 / a0; g = Double(p[o + 1]) / 255 / a0; r = Double(p[o + 2]) / 255 / a0 }
                let nr = cl(r * M[0][0] + g * M[1][0] + b * M[2][0] + a0 * M[3][0] + M[4][0])
                let ng = cl(r * M[0][1] + g * M[1][1] + b * M[2][1] + a0 * M[3][1] + M[4][1])
                let nb = cl(r * M[0][2] + g * M[1][2] + b * M[2][2] + a0 * M[3][2] + M[4][2])
                let na = cl(r * M[0][3] + g * M[1][3] + b * M[2][3] + a0 * M[3][3] + M[4][3])
                p[o] = UInt8((nb * na * 255).rounded()); p[o + 1] = UInt8((ng * na * 255).rounded()); p[o + 2] = UInt8((nr * na * 255).rounded()); p[o + 3] = UInt8((na * 255).rounded())
                o += 4
            }
        }
        return c.makeImage()
    }
}

extension Bitmap {
    /// 裝置像素（寬 PixelWidth × 高 PixelHeight，第 0 列＝最上面），預乘的 0xAARRGGBB
    func CuReadP() -> [Int] {
        let w = ctx.width, h = ctx.height
        var out = [Int](repeating: 0, count: w * h)
        guard let d = ctx.data else { return out }
        let p = d.assumingMemoryBound(to: UInt8.self)
        let bpr = ctx.bytesPerRow
        for y in 0..<h {
            var o = y * bpr
            for x in 0..<w {
                out[y * w + x] = (Int(p[o + 3]) << 24) | (Int(p[o + 2]) << 16) | (Int(p[o + 1]) << 8) | Int(p[o])
                o += 4
            }
        }
        return out
    }
    func CuWriteP(_ px: [Int]) {
        let w = ctx.width, h = ctx.height
        guard let d = ctx.data, px.count >= w * h else { return }
        let p = d.assumingMemoryBound(to: UInt8.self)
        let bpr = ctx.bytesPerRow
        for y in 0..<h {
            var o = y * bpr
            for x in 0..<w {
                let v = px[y * w + x]
                p[o] = UInt8(v & 255); p[o + 1] = UInt8((v >> 8) & 255); p[o + 2] = UInt8((v >> 16) & 255); p[o + 3] = UInt8((v >> 24) & 255)
                o += 4
            }
        }
    }
}
