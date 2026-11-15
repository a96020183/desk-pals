// ===== 01_drawing.swift — System.Drawing shim on CoreGraphics (see mac/PORTING.md "Drawing") =====
// Coordinates: top-left origin, y down, in points (= Windows pixels at 100%).
// Bitmap(w, h) has logical size w×h, backed by a CGContext at the screen backing scale.
// Magenta KEY (255,0,255) is "transparent": Clear(KEY) and fills/strokes with KEY clear to alpha 0.
// SmoothingMode default (None) → antialiasing OFF for fills/strokes (pixel-crisp like GDI+); text is always antialiased.
import Foundation
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

// MARK: - Color

struct Color: Equatable, Hashable, CustomStringConvertible {
    let A: Int, R: Int, G: Int, B: Int
    let IsEmpty: Bool
    private init(_ a: Int, _ r: Int, _ g: Int, _ b: Int, _ empty: Bool) {
        A = Color.clamp(a); R = Color.clamp(r); G = Color.clamp(g); B = Color.clamp(b); IsEmpty = empty
    }
    @inline(__always) private static func clamp(_ v: Int) -> Int { return v < 0 ? 0 : (v > 255 ? 255 : v) }
    static func FromArgb(_ r: Int, _ g: Int, _ b: Int) -> Color { return Color(255, r, g, b, false) }
    static func FromArgb(_ a: Int, _ r: Int, _ g: Int, _ b: Int) -> Color { return Color(a, r, g, b, false) }
    static func FromArgb(_ a: Int, _ c: Color) -> Color { return Color(a, c.R, c.G, c.B, false) }
    /// 32-bit ARGB (signed or unsigned).
    static func FromArgb(_ argb: Int) -> Color {
        let v = UInt32(truncatingIfNeeded: argb)
        return Color(Int(v >> 24), Int((v >> 16) & 255), Int((v >> 8) & 255), Int(v & 255), false)
    }
    static func FromName(_ n: String) -> Color { return Color.Black }
    func ToArgb() -> Int { return Int(Int32(bitPattern: UInt32(A) << 24 | UInt32(R) << 16 | UInt32(G) << 8 | UInt32(B))) }
    var Name: String { return String(format: "%02x%02x%02x%02x", A, R, G, B) }
    var IsKnownColor: Bool { return false }
    func GetBrightness() -> Double {
        let r = Double(R) / 255, g = Double(G) / 255, b = Double(B) / 255
        return (Swift.max(r, g, b) + Swift.min(r, g, b)) / 2
    }
    func GetSaturation() -> Double {
        let r = Double(R) / 255, g = Double(G) / 255, b = Double(B) / 255
        let mx = Swift.max(r, g, b), mn = Swift.min(r, g, b)
        if mx == mn { return 0 }
        let l = (mx + mn) / 2
        return l <= 0.5 ? (mx - mn) / (mx + mn) : (mx - mn) / (2 - mx - mn)
    }
    func GetHue() -> Double {
        let r = Double(R) / 255, g = Double(G) / 255, b = Double(B) / 255
        let mx = Swift.max(r, g, b), mn = Swift.min(r, g, b)
        if mx == mn { return 0 }
        let d = mx - mn
        var h: Double
        if r == mx { h = (g - b) / d } else if g == mx { h = 2 + (b - r) / d } else { h = 4 + (r - g) / d }
        h *= 60
        if h < 0 { h += 360 }
        return h
    }
    var description: String { return IsEmpty ? "Color [Empty]" : "Color [A=\(A), R=\(R), G=\(G), B=\(B)]" }
    func ToString() -> String { return description }

    /// True for the magenta transparency key.
    var IsKey: Bool { return R == 255 && G == 0 && B == 255 && A == 255 }
    var cg: CGColor { return CGColor(srgbRed: CGFloat(R) / 255, green: CGFloat(G) / 255, blue: CGFloat(B) / 255, alpha: CGFloat(A) / 255) }
    var ns: NSColor { return NSColor(srgbRed: CGFloat(R) / 255, green: CGFloat(G) / 255, blue: CGFloat(B) / 255, alpha: CGFloat(A) / 255) }

    static let Empty = Color(0, 0, 0, 0, true)
    static let Transparent = Color(0, 255, 255, 255, false)
    static let Black = FromArgb(0, 0, 0)
    static let White = FromArgb(255, 255, 255)
    static let Red = FromArgb(255, 0, 0)
    static let Green = FromArgb(0, 128, 0)
    static let Lime = FromArgb(0, 255, 0)
    static let Blue = FromArgb(0, 0, 255)
    static let Yellow = FromArgb(255, 255, 0)
    static let Magenta = FromArgb(255, 0, 255)
    static let Fuchsia = FromArgb(255, 0, 255)
    static let Cyan = FromArgb(0, 255, 255)
    static let Aqua = FromArgb(0, 255, 255)
    static let Gray = FromArgb(128, 128, 128)
    static let DarkGray = FromArgb(169, 169, 169)
    static let LightGray = FromArgb(211, 211, 211)
    static let DimGray = FromArgb(105, 105, 105)
    static let Silver = FromArgb(192, 192, 192)
    static let Orange = FromArgb(255, 165, 0)
    static let Pink = FromArgb(255, 192, 203)
    static let Purple = FromArgb(128, 0, 128)
    static let Brown = FromArgb(165, 42, 42)
    static let Gold = FromArgb(255, 215, 0)
    static let Navy = FromArgb(0, 0, 128)
    static let WhiteSmoke = FromArgb(245, 245, 245)
    static let Gainsboro = FromArgb(220, 220, 220)
}

enum SystemColors {
    static let Control = Color.FromArgb(240, 240, 240)
    static let ControlText = Color.Black
    static let Window = Color.White
    static let WindowText = Color.Black
    static let GrayText = Color.FromArgb(109, 109, 109)
    static let Highlight = Color.FromArgb(0, 120, 215)
    static let HighlightText = Color.White
    static let ControlDark = Color.FromArgb(160, 160, 160)
    static let ControlLight = Color.FromArgb(227, 227, 227)
}

// MARK: - Geometry

struct Point: Equatable, Hashable, CustomStringConvertible {
    var X: Int, Y: Int
    init() { X = 0; Y = 0 }
    init(_ x: Int, _ y: Int) { X = x; Y = y }
    init(_ s: Size) { X = s.Width; Y = s.Height }
    static let Empty = Point(0, 0)
    var IsEmpty: Bool { return X == 0 && Y == 0 }
    mutating func Offset(_ dx: Int, _ dy: Int) { X += dx; Y += dy }
    mutating func Offset(_ p: Point) { X += p.X; Y += p.Y }
    static func Add(_ p: Point, _ s: Size) -> Point { return Point(p.X + s.Width, p.Y + s.Height) }
    static func Subtract(_ p: Point, _ s: Size) -> Point { return Point(p.X - s.Width, p.Y - s.Height) }
    static func Round(_ p: PointF) -> Point { return Point(CInt(Math.Round(p.X)), CInt(Math.Round(p.Y))) }
    static func Truncate(_ p: PointF) -> Point { return Point(CInt(p.X), CInt(p.Y)) }
    static func Ceiling(_ p: PointF) -> Point { return Point(CInt(p.X.rounded(.up)), CInt(p.Y.rounded(.up))) }
    var description: String { return "{X=\(X),Y=\(Y)}" }
    func ToString() -> String { return description }
    var cg: CGPoint { return CGPoint(x: X, y: Y) }
}

struct PointF: Equatable, Hashable, CustomStringConvertible {
    var X: Double, Y: Double
    init() { X = 0; Y = 0 }
    init(_ x: Double, _ y: Double) { X = x; Y = y }
    init(_ p: Point) { X = Double(p.X); Y = Double(p.Y) }
    static let Empty = PointF(0, 0)
    var IsEmpty: Bool { return X == 0 && Y == 0 }
    var description: String { return "{X=\(X.ToString()), Y=\(Y.ToString())}" }
    func ToString() -> String { return description }
    var cg: CGPoint { return CGPoint(x: X, y: Y) }
}

struct Size: Equatable, Hashable, CustomStringConvertible {
    var Width: Int, Height: Int
    init() { Width = 0; Height = 0 }
    init(_ w: Int, _ h: Int) { Width = w; Height = h }
    init(_ p: Point) { Width = p.X; Height = p.Y }
    static let Empty = Size(0, 0)
    var IsEmpty: Bool { return Width == 0 && Height == 0 }
    static func Round(_ s: SizeF) -> Size { return Size(CInt(Math.Round(s.Width)), CInt(Math.Round(s.Height))) }
    static func Ceiling(_ s: SizeF) -> Size { return Size(CInt(s.Width.rounded(.up)), CInt(s.Height.rounded(.up))) }
    static func Truncate(_ s: SizeF) -> Size { return Size(CInt(s.Width), CInt(s.Height)) }
    var description: String { return "{Width=\(Width), Height=\(Height)}" }
    func ToString() -> String { return description }
}

struct SizeF: Equatable, Hashable, CustomStringConvertible {
    var Width: Double, Height: Double
    init() { Width = 0; Height = 0 }
    init(_ w: Double, _ h: Double) { Width = w; Height = h }
    init(_ s: Size) { Width = Double(s.Width); Height = Double(s.Height) }
    static let Empty = SizeF(0, 0)
    var IsEmpty: Bool { return Width == 0 && Height == 0 }
    func ToSize() -> Size { return Size.Truncate(self) }
    func ToPointF() -> PointF { return PointF(Width, Height) }
    var description: String { return "{Width=\(Width.ToString()), Height=\(Height.ToString())}" }
    func ToString() -> String { return description }
}

struct Rectangle: Equatable, Hashable, CustomStringConvertible {
    var X: Int, Y: Int, Width: Int, Height: Int
    init() { X = 0; Y = 0; Width = 0; Height = 0 }
    init(_ x: Int, _ y: Int, _ w: Int, _ h: Int) { X = x; Y = y; Width = w; Height = h }
    init(_ p: Point, _ s: Size) { X = p.X; Y = p.Y; Width = s.Width; Height = s.Height }
    static let Empty = Rectangle(0, 0, 0, 0)
    static func FromLTRB(_ l: Int, _ t: Int, _ r: Int, _ b: Int) -> Rectangle { return Rectangle(l, t, r - l, b - t) }
    var Left: Int { return X }
    var Top: Int { return Y }
    var Right: Int { return X + Width }
    var Bottom: Int { return Y + Height }
    var Location: Point { get { return Point(X, Y) } set { X = newValue.X; Y = newValue.Y } }
    var Size: Size { get { return DeskPalsSize(Width, Height) } set { Width = newValue.Width; Height = newValue.Height } }
    var IsEmpty: Bool { return X == 0 && Y == 0 && Width == 0 && Height == 0 }
    func Contains(_ x: Int, _ y: Int) -> Bool { return x >= X && x < X + Width && y >= Y && y < Y + Height }
    func Contains(_ p: Point) -> Bool { return Contains(p.X, p.Y) }
    func Contains(_ r: Rectangle) -> Bool { return X <= r.X && r.X + r.Width <= X + Width && Y <= r.Y && r.Y + r.Height <= Y + Height }
    func IntersectsWith(_ r: Rectangle) -> Bool { return r.X < X + Width && X < r.X + r.Width && r.Y < Y + Height && Y < r.Y + r.Height }
    static func Intersect(_ a: Rectangle, _ b: Rectangle) -> Rectangle {
        let x1 = Swift.max(a.X, b.X), x2 = Swift.min(a.X + a.Width, b.X + b.Width)
        let y1 = Swift.max(a.Y, b.Y), y2 = Swift.min(a.Y + a.Height, b.Y + b.Height)
        if x2 >= x1 && y2 >= y1 { return Rectangle(x1, y1, x2 - x1, y2 - y1) }
        return Empty
    }
    mutating func Intersect(_ r: Rectangle) { self = Rectangle.Intersect(self, r) }
    static func Union(_ a: Rectangle, _ b: Rectangle) -> Rectangle {
        let x1 = Swift.min(a.X, b.X), x2 = Swift.max(a.X + a.Width, b.X + b.Width)
        let y1 = Swift.min(a.Y, b.Y), y2 = Swift.max(a.Y + a.Height, b.Y + b.Height)
        return Rectangle(x1, y1, x2 - x1, y2 - y1)
    }
    mutating func Inflate(_ w: Int, _ h: Int) { X -= w; Y -= h; Width += 2 * w; Height += 2 * h }
    mutating func Inflate(_ s: Size) { Inflate(s.Width, s.Height) }
    static func Inflate(_ r: Rectangle, _ w: Int, _ h: Int) -> Rectangle { var c = r; c.Inflate(w, h); return c }
    mutating func Offset(_ dx: Int, _ dy: Int) { X += dx; Y += dy }
    mutating func Offset(_ p: Point) { X += p.X; Y += p.Y }
    static func Round(_ r: RectangleF) -> Rectangle { return Rectangle(CInt(Math.Round(r.X)), CInt(Math.Round(r.Y)), CInt(Math.Round(r.Width)), CInt(Math.Round(r.Height))) }
    static func Truncate(_ r: RectangleF) -> Rectangle { return Rectangle(CInt(r.X), CInt(r.Y), CInt(r.Width), CInt(r.Height)) }
    static func Ceiling(_ r: RectangleF) -> Rectangle { return Rectangle(CInt(r.X.rounded(.up)), CInt(r.Y.rounded(.up)), CInt(r.Width.rounded(.up)), CInt(r.Height.rounded(.up))) }
    var description: String { return "{X=\(X),Y=\(Y),Width=\(Width),Height=\(Height)}" }
    func ToString() -> String { return description }
    var cg: CGRect { return CGRect(x: X, y: Y, width: Width, height: Height) }
    init(_ r: CGRect) { X = Int(r.origin.x.rounded()); Y = Int(r.origin.y.rounded()); Width = Int(r.width.rounded()); Height = Int(r.height.rounded()) }
}
typealias DeskPalsSize = Size

struct RectangleF: Equatable, Hashable, CustomStringConvertible {
    var X: Double, Y: Double, Width: Double, Height: Double
    init() { X = 0; Y = 0; Width = 0; Height = 0 }
    init(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { X = x; Y = y; Width = w; Height = h }
    init(_ p: PointF, _ s: SizeF) { X = p.X; Y = p.Y; Width = s.Width; Height = s.Height }
    init(_ r: Rectangle) { X = Double(r.X); Y = Double(r.Y); Width = Double(r.Width); Height = Double(r.Height) }
    static let Empty = RectangleF(0, 0, 0, 0)
    static func FromLTRB(_ l: Double, _ t: Double, _ r: Double, _ b: Double) -> RectangleF { return RectangleF(l, t, r - l, b - t) }
    var Left: Double { return X }
    var Top: Double { return Y }
    var Right: Double { return X + Width }
    var Bottom: Double { return Y + Height }
    var Location: PointF { get { return PointF(X, Y) } set { X = newValue.X; Y = newValue.Y } }
    var Size: SizeF { get { return SizeF(Width, Height) } set { Width = newValue.Width; Height = newValue.Height } }
    var IsEmpty: Bool { return Width <= 0 || Height <= 0 }
    func Contains(_ x: Double, _ y: Double) -> Bool { return x >= X && x < X + Width && y >= Y && y < Y + Height }
    func Contains(_ p: PointF) -> Bool { return Contains(p.X, p.Y) }
    func Contains(_ r: RectangleF) -> Bool { return X <= r.X && r.Right <= Right && Y <= r.Y && r.Bottom <= Bottom }
    func IntersectsWith(_ r: RectangleF) -> Bool { return r.X < Right && X < r.Right && r.Y < Bottom && Y < r.Bottom }
    static func Intersect(_ a: RectangleF, _ b: RectangleF) -> RectangleF {
        let x1 = Swift.max(a.X, b.X), x2 = Swift.min(a.Right, b.Right)
        let y1 = Swift.max(a.Y, b.Y), y2 = Swift.min(a.Bottom, b.Bottom)
        if x2 >= x1 && y2 >= y1 { return RectangleF(x1, y1, x2 - x1, y2 - y1) }
        return Empty
    }
    mutating func Intersect(_ r: RectangleF) { self = RectangleF.Intersect(self, r) }
    static func Union(_ a: RectangleF, _ b: RectangleF) -> RectangleF {
        let x1 = Swift.min(a.X, b.X), x2 = Swift.max(a.Right, b.Right)
        let y1 = Swift.min(a.Y, b.Y), y2 = Swift.max(a.Bottom, b.Bottom)
        return RectangleF(x1, y1, x2 - x1, y2 - y1)
    }
    mutating func Inflate(_ w: Double, _ h: Double) { X -= w; Y -= h; Width += 2 * w; Height += 2 * h }
    static func Inflate(_ r: RectangleF, _ w: Double, _ h: Double) -> RectangleF { var c = r; c.Inflate(w, h); return c }
    mutating func Offset(_ dx: Double, _ dy: Double) { X += dx; Y += dy }
    mutating func Offset(_ p: PointF) { X += p.X; Y += p.Y }
    var description: String { return "{X=\(X.ToString()),Y=\(Y.ToString()),Width=\(Width.ToString()),Height=\(Height.ToString())}" }
    func ToString() -> String { return description }
    var cg: CGRect { return CGRect(x: X, y: Y, width: Width, height: Height) }
}

// MARK: - Enums

enum SmoothingMode { case Invalid, Default, HighSpeed, HighQuality, None, AntiAlias }
enum InterpolationMode { case Invalid, Default, Low, High, Bilinear, Bicubic, NearestNeighbor, HighQualityBilinear, HighQualityBicubic }
enum PixelOffsetMode { case Invalid, Default, HighSpeed, HighQuality, None, Half }
enum CompositingMode { case SourceOver, SourceCopy }
enum CompositingQuality { case Invalid, Default, HighSpeed, HighQuality, GammaCorrected, AssumeLinear }
enum TextRenderingHint { case SystemDefault, SingleBitPerPixelGridFit, SingleBitPerPixel, AntiAliasGridFit, AntiAlias, ClearTypeGridFit }
enum GraphicsUnit { case World, Display, Pixel, Point, Inch, Document, Millimeter }
enum PixelFormat { case Format24bppRgb, Format32bppArgb, Format32bppPArgb, Format32bppRgb, Format8bppIndexed, DontCare }
enum DashStyle { case Solid, Dash, Dot, DashDot, DashDotDot, Custom }
enum LineCap { case Flat, Square, Round, Triangle, NoAnchor, SquareAnchor, RoundAnchor, DiamondAnchor, ArrowAnchor, Custom }
enum LineJoin { case Miter, Bevel, Round, MiterClipped }
enum PenAlignment { case Center, Inset, Outset, Left, Right }
enum LinearGradientMode { case Horizontal, Vertical, ForwardDiagonal, BackwardDiagonal }
enum FillMode { case Alternate, Winding }
enum WrapMode { case Tile, TileFlipX, TileFlipY, TileFlipXY, Clamp }
enum StringAlignment { case Near, Center, Far }
enum StringTrimming { case None, Character, Word, EllipsisCharacter, EllipsisWord, EllipsisPath }
enum CombineMode { case Replace, Intersect, Union, Xor, Exclude, Complement }
enum RotateFlipType { case RotateNoneFlipNone, Rotate90FlipNone, Rotate180FlipNone, Rotate270FlipNone, RotateNoneFlipX, RotateNoneFlipY }

struct FontStyle: OptionSet, Hashable {
    let rawValue: Int
    static let Regular = FontStyle([])
    static let Bold = FontStyle(rawValue: 1)
    static let Italic = FontStyle(rawValue: 2)
    static let Underline = FontStyle(rawValue: 4)
    static let Strikeout = FontStyle(rawValue: 8)
}

struct StringFormatFlags: OptionSet {
    let rawValue: Int
    static let DirectionRightToLeft = StringFormatFlags(rawValue: 1)
    static let DirectionVertical = StringFormatFlags(rawValue: 2)
    static let FitBlackBox = StringFormatFlags(rawValue: 4)
    static let DisplayFormatControl = StringFormatFlags(rawValue: 32)
    static let NoFontFallback = StringFormatFlags(rawValue: 1024)
    static let MeasureTrailingSpaces = StringFormatFlags(rawValue: 2048)
    static let NoWrap = StringFormatFlags(rawValue: 4096)
    static let LineLimit = StringFormatFlags(rawValue: 8192)
    static let NoClip = StringFormatFlags(rawValue: 16384)
}

struct TextFormatFlags: OptionSet {
    let rawValue: Int
    static let Default = TextFormatFlags([])
    static let Left = TextFormatFlags([])
    static let Top = TextFormatFlags([])
    static let GlyphOverhangPadding = TextFormatFlags([])
    static let HorizontalCenter = TextFormatFlags(rawValue: 1)
    static let Right = TextFormatFlags(rawValue: 2)
    static let VerticalCenter = TextFormatFlags(rawValue: 4)
    static let Bottom = TextFormatFlags(rawValue: 8)
    static let WordBreak = TextFormatFlags(rawValue: 16)
    static let SingleLine = TextFormatFlags(rawValue: 32)
    static let ExpandTabs = TextFormatFlags(rawValue: 64)
    static let NoClipping = TextFormatFlags(rawValue: 256)
    static let ExternalLeading = TextFormatFlags(rawValue: 512)
    static let NoPrefix = TextFormatFlags(rawValue: 2048)
    static let Internal = TextFormatFlags(rawValue: 4096)
    static let TextBoxControl = TextFormatFlags(rawValue: 8192)
    static let PathEllipsis = TextFormatFlags(rawValue: 16384)
    static let EndEllipsis = TextFormatFlags(rawValue: 32768)
    static let ModifyString = TextFormatFlags(rawValue: 65536)
    static let RightToLeft = TextFormatFlags(rawValue: 131072)
    static let WordEllipsis = TextFormatFlags(rawValue: 262144)
    static let NoFullWidthCharacterBreak = TextFormatFlags(rawValue: 524288)
    static let HidePrefix = TextFormatFlags(rawValue: 1048576)
    static let PrefixOnly = TextFormatFlags(rawValue: 2097152)
    static let PreserveGraphicsClipping = TextFormatFlags(rawValue: 16777216)
    static let PreserveGraphicsTranslateTransform = TextFormatFlags(rawValue: 33554432)
    static let NoPadding = TextFormatFlags(rawValue: 268435456)
    static let LeftAndRightPadding = TextFormatFlags(rawValue: 536870912)
}

final class ImageFormat {
    let uti: CFString
    private init(_ u: CFString) { uti = u }
    static let Png = ImageFormat(UTType.png.identifier as CFString)
    static let Bmp = ImageFormat(UTType.bmp.identifier as CFString)
    static let Jpeg = ImageFormat(UTType.jpeg.identifier as CFString)
    static let Gif = ImageFormat(UTType.gif.identifier as CFString)
    static let Tiff = ImageFormat(UTType.tiff.identifier as CFString)
}

// MARK: - Brushes / Pens

class Brush: IDisposable {
    func Dispose() {}
}

final class SolidBrush: Brush {
    var Color: Color
    init(_ c: Color) { self.Color = c }
}
typealias DeskPalsColor = Color

final class ColorBlend {
    var Colors: [Color] = []
    var Positions: [Double] = []
    init() {}
    init(_ n: Int) { Colors = Array(repeating: DeskPalsColor.Black, count: n); Positions = Array(repeating: 0, count: n) }
}
final class Blend {
    var Factors: [Double] = []
    var Positions: [Double] = []
    init() {}
    init(_ n: Int) { Factors = Array(repeating: 0, count: n); Positions = Array(repeating: 0, count: n) }
}

final class LinearGradientBrush: Brush {
    /// gradient line in brush space
    var p1: CGPoint, p2: CGPoint
    var LinearColors: [Color]
    var InterpolationColors: ColorBlend? = nil
    var Blend: Blend? = nil
    var WrapMode: WrapMode = .Tile
    var GammaCorrection = false
    let rect: RectangleF
    init(_ a: PointF, _ b: PointF, _ c1: Color, _ c2: Color) {
        p1 = a.cg; p2 = b.cg; LinearColors = [c1, c2]
        rect = RectangleF(Swift.min(a.X, b.X), Swift.min(a.Y, b.Y), Swift.abs(b.X - a.X), Swift.abs(b.Y - a.Y))
    }
    convenience init(_ a: Point, _ b: Point, _ c1: Color, _ c2: Color) { self.init(PointF(a), PointF(b), c1, c2) }
    /// angle in degrees (0 = left→right, 90 = top→bottom).
    init(_ r: RectangleF, _ c1: Color, _ c2: Color, _ angle: Double) {
        rect = r; LinearColors = [c1, c2]
        let a = angle * Double.pi / 180
        let dx = Foundation.cos(a), dy = Foundation.sin(a)
        let cx = r.X + r.Width / 2, cy = r.Y + r.Height / 2
        // half-extent of the rect projected onto the direction
        let half = (Swift.abs(r.Width * dx) + Swift.abs(r.Height * dy)) / 2
        p1 = CGPoint(x: cx - dx * half, y: cy - dy * half)
        p2 = CGPoint(x: cx + dx * half, y: cy + dy * half)
    }
    convenience init(_ r: Rectangle, _ c1: Color, _ c2: Color, _ angle: Double) { self.init(RectangleF(r), c1, c2, angle) }
    convenience init(_ r: RectangleF, _ c1: Color, _ c2: Color, _ angle: Double, _ scalable: Bool) { self.init(r, c1, c2, angle) }
    convenience init(_ r: RectangleF, _ c1: Color, _ c2: Color, _ mode: LinearGradientMode) {
        let ang: Double
        switch mode { case .Horizontal: ang = 0; case .Vertical: ang = 90; case .ForwardDiagonal: ang = 45; case .BackwardDiagonal: ang = 135 }
        self.init(r, c1, c2, ang)
    }
    convenience init(_ r: Rectangle, _ c1: Color, _ c2: Color, _ mode: LinearGradientMode) { self.init(RectangleF(r), c1, c2, mode) }
    var Rectangle: RectangleF { return rect }

    func gradient() -> CGGradient? {
        var cols: [CGColor] = []
        var locs: [CGFloat] = []
        if let ib = InterpolationColors, ib.Colors.count >= 2 {
            for (i, c) in ib.Colors.enumerated() { cols.append(c.cg); locs.append(CGFloat(i < ib.Positions.count ? ib.Positions[i] : Double(i) / Double(ib.Colors.count - 1))) }
        } else if let b = Blend, b.Factors.count >= 2 {
            for (i, f) in b.Factors.enumerated() {
                let c1 = LinearColors[0], c2 = LinearColors[1]
                func mix(_ a: Int, _ b: Int) -> Int { return Int((Double(a) + Double(b - a) * f).rounded()) }
                cols.append(DeskPalsColor.FromArgb(mix(c1.A, c2.A), mix(c1.R, c2.R), mix(c1.G, c2.G), mix(c1.B, c2.B)).cg)
                locs.append(CGFloat(i < b.Positions.count ? b.Positions[i] : Double(i) / Double(b.Factors.count - 1)))
            }
        } else {
            cols = LinearColors.map { $0.cg }; locs = [0, 1]
        }
        return CGGradient(colorsSpace: _gdiColorSpace, colors: cols as CFArray, locations: locs)
    }
}

final class PathGradientBrush: Brush {
    let path: GraphicsPath
    var CenterColor: Color = Color.White
    var SurroundColors: [Color] = [Color.White]
    var CenterPoint: PointF
    var WrapMode: WrapMode = .Clamp
    var InterpolationColors: ColorBlend? = nil
    init(_ p: GraphicsPath) {
        path = p
        let b = p.GetBounds()
        CenterPoint = PointF(b.X + b.Width / 2, b.Y + b.Height / 2)
    }
    convenience init(_ pts: [PointF]) { let gp = GraphicsPath(); gp.AddPolygon(pts); self.init(gp) }
}

final class TextureBrush: Brush {
    let image: Bitmap
    init(_ b: Bitmap) { image = b }
}

final class HatchBrush: Brush {
    let fore: Color
    init(_ style: Int, _ fore: Color, _ back: Color) { self.fore = fore }
}

final class Pen: IDisposable {
    var Color: Color
    var Width: Double
    var DashStyle: DashStyle = .Solid
    var DashPattern: [Double]? = nil
    var StartCap: LineCap = .Flat
    var EndCap: LineCap = .Flat
    var LineJoin: LineJoin = .Miter
    var Alignment: PenAlignment = .Center
    var Brush: Brush? = nil
    init(_ c: Color) { Color = c; Width = 1 }
    init(_ c: Color, _ w: Double) { Color = c; Width = w }
    init(_ c: Color, _ w: Int) { Color = c; Width = Double(w) }
    init(_ b: Brush, _ w: Double) {
        Color = (b as? SolidBrush)?.Color ?? (b as? LinearGradientBrush)?.LinearColors[0] ?? DeskPalsColor.Black
        Width = w; Brush = b
    }
    convenience init(_ b: Brush) { self.init(b, 1) }
    func Dispose() {}
    func Clone() -> Pen { let p = Pen(Color, Width); p.DashStyle = DashStyle; p.StartCap = StartCap; p.EndCap = EndCap; p.LineJoin = LineJoin; return p }
}

enum Brushes {
    static let White = SolidBrush(Color.White)
    static let Black = SolidBrush(Color.Black)
    static let Transparent = SolidBrush(Color.Transparent)
    static let Red = SolidBrush(Color.Red)
    static let Gray = SolidBrush(Color.Gray)
    static let Yellow = SolidBrush(Color.Yellow)
    static let Blue = SolidBrush(Color.Blue)
    static let Green = SolidBrush(Color.Green)
    static let Magenta = SolidBrush(Color.Magenta)
}
enum Pens {
    static let White = Pen(Color.White)
    static let Black = Pen(Color.Black)
    static let Red = Pen(Color.Red)
    static let Gray = Pen(Color.Gray)
    static let Yellow = Pen(Color.Yellow)
    static let Magenta = Pen(Color.Magenta)
}

// MARK: - Fonts

final class FontFamily {
    let Name: String
    init(_ name: String) { Name = name }
    static let GenericSansSerif = FontFamily("Segoe UI")
    static let GenericSerif = FontFamily("Times New Roman")
    static let GenericMonospace = FontFamily("Consolas")
}

/// GDI font. `Size` is in `Unit` (Point by default: 1pt = 96/72 px). Name mapping:
/// Microsoft JhengHei (UI) → PingFang TC, Segoe UI → system font, Segoe UI Emoji → Apple Color Emoji, Consolas → Menlo.
final class Font: IDisposable {
    let Name: String
    let Size: Double
    let Style: FontStyle
    let Unit: GraphicsUnit
    init(_ name: String, _ size: Double) { Name = name; Size = size; Style = .Regular; Unit = .Point }
    init(_ name: String, _ size: Double, _ style: FontStyle) { Name = name; Size = size; Style = style; Unit = .Point }
    init(_ name: String, _ size: Double, _ style: FontStyle, _ unit: GraphicsUnit) { Name = name; Size = size; Style = style; Unit = unit }
    init(_ name: String, _ size: Double, _ unit: GraphicsUnit) { Name = name; Size = size; Style = .Regular; Unit = unit }
    convenience init(_ fam: FontFamily, _ size: Double) { self.init(fam.Name, size) }
    convenience init(_ fam: FontFamily, _ size: Double, _ style: FontStyle) { self.init(fam.Name, size, style) }
    convenience init(_ fam: FontFamily, _ size: Double, _ style: FontStyle, _ unit: GraphicsUnit) { self.init(fam.Name, size, style, unit) }
    convenience init(_ proto: Font, _ style: FontStyle) { self.init(proto.Name, proto.Size, style, proto.Unit) }
    func Dispose() {}
    var Bold: Bool { return Style.contains(.Bold) }
    var Italic: Bool { return Style.contains(.Italic) }
    var Underline: Bool { return Style.contains(.Underline) }
    var FontFamily: FontFamily { return DeskPalsFontFamily(Name) }
    /// em size in logical pixels (points on mac).
    var SizePx: Double {
        switch Unit {
        case .Pixel, .World, .Display: return Size
        case .Point: return Size * 96.0 / 72.0
        case .Inch: return Size * 96.0
        case .Document: return Size * 96.0 / 300.0
        case .Millimeter: return Size * 96.0 / 25.4
        }
    }
    var SizeInPoints: Double { return SizePx * 72.0 / 96.0 }
    /// Line spacing in px (GDI Font.Height).
    var Height: Int { let f = NSFont; return Int((f.ascender - f.descender + f.leading).rounded(.up)) }
    func GetHeight() -> Double { let f = NSFont; return Double(f.ascender - f.descender + f.leading) }
    func GetHeight(_ g: Graphics) -> Double { return GetHeight() }

    private var _ns: AppKit.NSFont? = nil
    private let lk = NSLock()
    var NSFont: AppKit.NSFont {
        lk.lock(); defer { lk.unlock() }
        if let f = _ns { return f }
        let f = Font.makeNSFont(Name, CGFloat(SizePx), Style)
        _ns = f
        return f
    }
    static func mapName(_ n: String) -> String? {
        let l = n.lowercased()
        if l.hasPrefix("microsoft jhenghei") || l.hasPrefix("microsoft yahei") || l == "pmingliu" || l == "mingliu" || l.hasPrefix("新細明體") || l.hasPrefix("微軟正黑體") { return "PingFang TC" }
        if l == "segoe ui emoji" || l == "segoe ui symbol" { return "Apple Color Emoji" }
        if l.hasPrefix("segoe ui") || l == "tahoma" || l == "microsoft sans serif" || l == "ms sans serif" { return nil }  // system font
        if l == "consolas" || l == "courier new" || l == "lucida console" { return "Menlo" }
        if l == "arial" { return "Arial" }
        return n
    }
    private static func makeNSFont(_ name: String, _ size: CGFloat, _ style: FontStyle) -> AppKit.NSFont {
        let bold = style.contains(.Bold)
        let fam = mapName(name)
        var f: AppKit.NSFont? = nil
        if let fam = fam {
            if fam == "PingFang TC" {
                f = AppKit.NSFont(name: bold ? "PingFangTC-Semibold" : "PingFangTC-Regular", size: size)
            } else if fam == "Apple Color Emoji" {
                f = AppKit.NSFont(name: "AppleColorEmoji", size: size)
            } else {
                var traits: NSFontTraitMask = []
                if bold { traits.insert(.boldFontMask) }
                if style.contains(.Italic) { traits.insert(.italicFontMask) }
                f = NSFontManager.shared.font(withFamily: fam, traits: traits, weight: bold ? 9 : 5, size: size)
                if f == nil { f = AppKit.NSFont(name: fam, size: size) }
            }
        }
        if f == nil { f = AppKit.NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular) }
        if style.contains(.Italic), let ff = f { f = NSFontManager.shared.convert(ff, toHaveTrait: .italicFontMask) }
        return f!
    }
}
typealias DeskPalsFontFamily = FontFamily

final class StringFormat: IDisposable {
    var Alignment: StringAlignment = .Near
    var LineAlignment: StringAlignment = .Near
    var Trimming: StringTrimming = .Character
    var FormatFlags: StringFormatFlags = []
    let typographic: Bool
    init() { typographic = false }
    init(_ flags: StringFormatFlags) { FormatFlags = flags; typographic = false }
    private init(typographic: Bool) { self.typographic = typographic }
    static var GenericDefault: StringFormat { return StringFormat() }
    static var GenericTypographic: StringFormat { let s = StringFormat(typographic: true); s.FormatFlags = [.NoClip, .LineLimit]; s.Trimming = .None; return s }
    func Dispose() {}
}

// MARK: - Images

let _gdiColorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

/// Bitmap with logical size Width×Height (points), backed by RGBA pixels at `Scale` device pixels per point.
class Bitmap: IDisposable {
    let Width: Int
    let Height: Int
    let Scale: Double
    let ctx: CGContext
    let PixelFormat: PixelFormat

    /// Backing scale for new bitmaps: DESKPALS_BMP_SCALE env, else the largest screen backing factor (≥1).
    static var DefaultScale: Double = {
        if let s = ProcessInfo.processInfo.environment["DESKPALS_BMP_SCALE"], let v = Double(s), v > 0 { return v }
        let m = NSScreen.screens.map { Double($0.backingScaleFactor) }.max() ?? 2
        return Swift.max(1, m)
    }()
    /// Save(...) writes logical-size PNGs by default (like Windows); set true (or DESKPALS_SAVE_NATIVE=1) for native pixels.
    static var SaveNative: Bool = ProcessInfo.processInfo.environment["DESKPALS_SAVE_NATIVE"] == "1"

    init(_ w: Int, _ h: Int, _ fmt: PixelFormat, _ scale: Double) {
        Width = Swift.max(1, w); Height = Swift.max(1, h); Scale = scale; PixelFormat = fmt
        let pw = Swift.max(1, Int((Double(Width) * scale).rounded())), ph = Swift.max(1, Int((Double(Height) * scale).rounded()))
        ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: _gdiColorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        if fmt == .Format24bppRgb || fmt == .Format32bppRgb {
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
        } else {
            ctx.clear(CGRect(x: 0, y: 0, width: pw, height: ph))
        }
    }
    convenience init(_ w: Int, _ h: Int) { self.init(w, h, .Format32bppArgb, Bitmap.DefaultScale) }
    convenience init(_ w: Int, _ h: Int, _ fmt: PixelFormat) { self.init(w, h, fmt, Bitmap.DefaultScale) }
    convenience init(_ src: Bitmap) { self.init(src.Width, src.Height, src.PixelFormat, src.Scale); copyPixels(from: src) }
    convenience init(_ src: Bitmap, _ w: Int, _ h: Int) {
        self.init(w, h, .Format32bppArgb, src.Scale)
        let g = Graphics.FromImage(self); g.InterpolationMode = .HighQualityBicubic; g.DrawImage(src, DeskPalsRectangle(0, 0, w, h))
    }
    /// Wrap an existing CGImage (logical size = pixels / scale).
    convenience init(_ img: CGImage, _ scale: Double) {
        self.init(Swift.max(1, Int((Double(img.width) / scale).rounded())), Swift.max(1, Int((Double(img.height) / scale).rounded())), .Format32bppArgb, scale)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
    }
    static func FromFile(_ path: String) -> Bitmap? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return Bitmap(img, 1)
    }

    private func copyPixels(from src: Bitmap) {
        if let d = ctx.data, let s = src.ctx.data, ctx.bytesPerRow == src.ctx.bytesPerRow, ctx.height == src.ctx.height {
            memcpy(d, s, ctx.bytesPerRow * ctx.height)
        } else if let img = src.ctx.makeImage() {
            ctx.setBlendMode(.copy)
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
            ctx.setBlendMode(.normal)
        }
    }
    var Size: Size { return DeskPalsSize(Width, Height) }
    var PixelWidth: Int { return ctx.width }
    var PixelHeight: Int { return ctx.height }
    var HorizontalResolution: Double { return 96 }
    var VerticalResolution: Double { return 96 }
    func Dispose() {}
    func Clone() -> Bitmap { return Bitmap(self) }
    func Clone(_ r: Rectangle, _ fmt: PixelFormat) -> Bitmap {
        let b = Bitmap(r.Width, r.Height, fmt, Scale)
        let g = Graphics.FromImage(b)
        g.CompositingMode = .SourceCopy
        g.DrawImage(self, DeskPalsRectangle(0, 0, r.Width, r.Height), r, .Pixel)
        return b
    }
    /// Snapshot as CGImage (pixel size = logical × Scale; origin top-left as an image).
    var cgImage: CGImage? { return ctx.makeImage() }

    // pixel access (logical coordinates; samples the top-left device pixel of the logical pixel)
    private func devOffset(_ x: Int, _ y: Int) -> Int? {
        if x < 0 || y < 0 || x >= Width || y >= Height { return nil }
        let px = Int(Double(x) * Scale), py = Int(Double(y) * Scale)
        // CGBitmapContext memory row 0 is the TOP row
        return py * ctx.bytesPerRow + px * 4
    }
    func GetPixel(_ x: Int, _ y: Int) -> Color {
        guard let o = devOffset(x, y), let d = ctx.data else { return Color.Empty }
        let p = d.assumingMemoryBound(to: UInt8.self)
        let b = Int(p[o]), g = Int(p[o + 1]), r = Int(p[o + 2]), a = Int(p[o + 3])
        if a == 0 { return Color.FromArgb(0, 0, 0, 0) }
        return Color.FromArgb(a, r * 255 / a, g * 255 / a, b * 255 / a)
    }
    func SetPixel(_ x: Int, _ y: Int, _ c: Color) {
        if x < 0 || y < 0 || x >= Width || y >= Height { return }
        ctx.saveGState()
        ctx.setBlendMode(.copy)
        let cc = c.IsKey ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0) : c.cg
        ctx.setFillColor(cc)
        let s = CGFloat(Scale)
        ctx.fill(CGRect(x: CGFloat(x) * s, y: CGFloat(ctx.height) - CGFloat(y + 1) * s, width: s, height: s))
        ctx.restoreGState()
    }
    /// Pixels exactly equal (opaque) to `c` become fully transparent.
    func MakeTransparent(_ c: Color) {
        guard let d = ctx.data else { return }
        let p = d.assumingMemoryBound(to: UInt8.self)
        let bpr = ctx.bytesPerRow
        let b0 = UInt8(c.B), g0 = UInt8(c.G), r0 = UInt8(c.R)
        for y in 0..<ctx.height {
            var o = y * bpr
            for _ in 0..<ctx.width {
                if p[o + 3] == 255 && p[o] == b0 && p[o + 1] == g0 && p[o + 2] == r0 { p[o] = 0; p[o + 1] = 0; p[o + 2] = 0; p[o + 3] = 0 }
                o += 4
            }
        }
    }
    func MakeTransparent() { MakeTransparent(GetPixel(0, Height - 1)) }

    func Save(_ path: String) { Save(path, ImageFormat.Png) }
    func Save(_ path: String, _ fmt: ImageFormat) {
        guard var img = ctx.makeImage() else { return }
        if !Bitmap.SaveNative && Scale != 1 {
            if let c = CGContext(data: nil, width: Width, height: Height, bitsPerComponent: 8, bytesPerRow: 0, space: _gdiColorSpace,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                c.interpolationQuality = .high
                c.draw(img, in: CGRect(x: 0, y: 0, width: Width, height: Height))
                if let i2 = c.makeImage() { img = i2 }
            }
        }
        let url = URL(fileURLWithPath: path) as CFURL
        guard let dest = CGImageDestinationCreateWithURL(url, fmt.uti, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}
typealias Image = Bitmap
typealias DeskPalsRectangle = Rectangle

final class ColorMatrix {
    var Matrix00 = 1.0, Matrix11 = 1.0, Matrix22 = 1.0, Matrix33 = 1.0, Matrix44 = 1.0
    init() {}
}
final class ImageAttributes: IDisposable {
    var alpha = 1.0
    var key: Color? = nil
    init() {}
    func SetColorMatrix(_ m: ColorMatrix) { alpha = m.Matrix33 }
    func SetColorKey(_ lo: Color, _ hi: Color) { key = lo }
    func SetWrapMode(_ m: WrapMode) {}
    func Dispose() {}
}

// MARK: - GraphicsPath

final class GraphicsPath: IDisposable {
    private(set) var path = CGMutablePath()
    var FillMode: FillMode = .Alternate
    private var figureOpen = false
    init() {}
    init(_ mode: FillMode) { FillMode = mode }
    func Dispose() {}

    private func lineOrMove(_ p: CGPoint) {
        if figureOpen && !path.isEmpty { if path.currentPoint != p { path.addLine(to: p) } }
        else { path.move(to: p); figureOpen = true }
    }
    /// Point on ellipse at GDI (geometric) angle.
    private static func paramAngle(_ deg: Double, _ rx: Double, _ ry: Double) -> Double {
        let a = deg * Double.pi / 180
        if rx == ry { return a }
        return Foundation.atan2(rx * Foundation.sin(a), ry * Foundation.cos(a))
    }
    func AddArc(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ start: Double, _ sweep: Double) {
        let rx = w / 2, ry = h / 2, cx = x + rx, cy = y + ry
        if rx <= 0 || ry <= 0 { lineOrMove(CGPoint(x: cx, y: cy)); return }
        let t0 = GraphicsPath.paramAngle(start, rx, ry)
        var t1: Double
        if Swift.abs(sweep) >= 360 { t1 = t0 + (sweep > 0 ? 2 : -2) * Double.pi }
        else {
            t1 = GraphicsPath.paramAngle(start + sweep, rx, ry)
            if sweep > 0 { while t1 <= t0 { t1 += 2 * Double.pi }; while t1 - t0 > 2 * Double.pi { t1 -= 2 * Double.pi } }
            else if sweep < 0 { while t1 >= t0 { t1 -= 2 * Double.pi }; while t0 - t1 > 2 * Double.pi { t1 += 2 * Double.pi } }
            else { t1 = t0 }
        }
        let tr = CGAffineTransform(translationX: cx, y: cy).scaledBy(x: rx, y: ry)
        let startPt = CGPoint(x: Foundation.cos(t0), y: Foundation.sin(t0)).applying(tr)
        lineOrMove(startPt)
        path.addArc(center: .zero, radius: 1, startAngle: t0, endAngle: t1, clockwise: sweep < 0, transform: tr)
    }
    func AddArc(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ start: Double, _ sweep: Double) { AddArc(Double(x), Double(y), Double(w), Double(h), start, sweep) }
    func AddArc(_ r: RectangleF, _ start: Double, _ sweep: Double) { AddArc(r.X, r.Y, r.Width, r.Height, start, sweep) }
    func AddArc(_ r: Rectangle, _ start: Double, _ sweep: Double) { AddArc(RectangleF(r), start, sweep) }
    func AddLine(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        lineOrMove(CGPoint(x: x1, y: y1)); path.addLine(to: CGPoint(x: x2, y: y2))
    }
    func AddLine(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) { AddLine(Double(x1), Double(y1), Double(x2), Double(y2)) }
    func AddLine(_ a: PointF, _ b: PointF) { AddLine(a.X, a.Y, b.X, b.Y) }
    func AddLine(_ a: Point, _ b: Point) { AddLine(Double(a.X), Double(a.Y), Double(b.X), Double(b.Y)) }
    func AddLines(_ pts: [PointF]) { for (i, p) in pts.enumerated() { if i == 0 { lineOrMove(p.cg) } else { path.addLine(to: p.cg) } } }
    func AddLines(_ pts: [Point]) { AddLines(pts.map { PointF($0) }) }
    func AddBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double, _ x4: Double, _ y4: Double) {
        lineOrMove(CGPoint(x: x1, y: y1))
        path.addCurve(to: CGPoint(x: x4, y: y4), control1: CGPoint(x: x2, y: y2), control2: CGPoint(x: x3, y: y3))
    }
    func AddBezier(_ a: PointF, _ b: PointF, _ c: PointF, _ d: PointF) { AddBezier(a.X, a.Y, b.X, b.Y, c.X, c.Y, d.X, d.Y) }
    func AddRectangle(_ r: RectangleF) { path.addRect(r.cg); figureOpen = false }
    func AddRectangle(_ r: Rectangle) { AddRectangle(RectangleF(r)) }
    func AddEllipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { path.addEllipse(in: CGRect(x: x, y: y, width: w, height: h)); figureOpen = false }
    func AddEllipse(_ x: Int, _ y: Int, _ w: Int, _ h: Int) { AddEllipse(Double(x), Double(y), Double(w), Double(h)) }
    func AddEllipse(_ r: RectangleF) { AddEllipse(r.X, r.Y, r.Width, r.Height) }
    func AddEllipse(_ r: Rectangle) { AddEllipse(RectangleF(r)) }
    func AddPolygon(_ pts: [PointF]) {
        guard pts.count >= 2 else { return }
        path.addLines(between: pts.map { $0.cg }); path.closeSubpath(); figureOpen = false
    }
    func AddPolygon(_ pts: [Point]) { AddPolygon(pts.map { PointF($0) }) }
    func AddPath(_ p: GraphicsPath, _ connect: Bool) { path.addPath(p.path); figureOpen = false }
    func AddPie(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ start: Double, _ sweep: Double) {
        StartFigure(); path.move(to: CGPoint(x: x + w / 2, y: y + h / 2)); figureOpen = true
        AddArc(x, y, w, h, start, sweep); CloseFigure()
    }
    func StartFigure() { figureOpen = false }
    func CloseFigure() { if !path.isEmpty && figureOpen { path.closeSubpath() }; figureOpen = false }
    func CloseAllFigures() { CloseFigure() }
    func Reset() { path = CGMutablePath(); figureOpen = false }
    func GetBounds() -> RectangleF {
        let b = cgPath.boundingBoxOfPath
        if b.isNull { return RectangleF.Empty }
        return RectangleF(Double(b.origin.x), Double(b.origin.y), Double(b.width), Double(b.height))
    }
    var cgPath: CGPath { return path }
    func IsVisible(_ x: Double, _ y: Double) -> Bool { return cgPath.contains(CGPoint(x: x, y: y), using: FillMode == .Alternate ? .evenOdd : .winding) }
    func IsVisible(_ p: PointF) -> Bool { return IsVisible(p.X, p.Y) }
    func IsVisible(_ p: Point) -> Bool { return IsVisible(Double(p.X), Double(p.Y)) }
    var PointCount: Int { var n = 0; cgPath.applyWithBlock { _ in n += 1 }; return n }
}

final class Region: IDisposable {
    let path: CGPath
    init(_ r: Rectangle) { path = CGPath(rect: r.cg, transform: nil) }
    init(_ r: RectangleF) { path = CGPath(rect: r.cg, transform: nil) }
    init(_ p: GraphicsPath) { path = p.cgPath.copy()! }
    func Dispose() {}
}

// MARK: - Graphics

final class GraphicsState {
    let index: Int
    init(_ i: Int) { index = i }
}
final class GraphicsContainer {
    let index: Int
    init(_ i: Int) { index = i }
}

final class Matrix {
    var t: CGAffineTransform
    init() { t = .identity }
    init(_ t: CGAffineTransform) { self.t = t }
    var OffsetX: Double { return Double(t.tx) }
    var OffsetY: Double { return Double(t.ty) }
    func Translate(_ x: Double, _ y: Double) { t = t.translatedBy(x: x, y: y) }
    func Scale(_ x: Double, _ y: Double) { t = t.scaledBy(x: x, y: y) }
    func Rotate(_ deg: Double) { t = t.rotated(by: deg * Double.pi / 180) }
    func Dispose() {}
}

/// GDI+ Graphics on a CGContext. World transform / clip are tracked here and applied per call,
/// so several Graphics on one Bitmap never interfere.
final class Graphics: IDisposable {
    let ctx: CGContext
    /// logical (top-left, y-down points) → device
    private let base: CGAffineTransform
    let Width: Int, Height: Int
    let target: Bitmap?

    private struct State {
        var transform: CGAffineTransform = .identity
        var clip: CGPath? = nil          // in logical (base) coordinates
        var smoothing: SmoothingMode = .None
        var interpolation: InterpolationMode = .Bilinear
        var pixelOffset: PixelOffsetMode = .Default
        var compositing: CompositingMode = .SourceOver
        var compQuality: CompositingQuality = .Default
        var textHint: TextRenderingHint = .SystemDefault
    }
    private var st = State()
    private var saved: [State] = []

    init(_ ctx: CGContext, _ base: CGAffineTransform, _ w: Int, _ h: Int, _ target: Bitmap?) {
        self.ctx = ctx; self.base = base; Width = w; Height = h; self.target = target
    }
    static func FromImage(_ b: Bitmap) -> Graphics {
        let s = CGFloat(b.Scale)
        let base = CGAffineTransform(a: s, b: 0, c: 0, d: -s, tx: 0, ty: CGFloat(b.ctx.height))
        return Graphics(b.ctx, base, b.Width, b.Height, b)
    }
    /// Wrap a context whose CTM already maps top-left/y-down points (e.g. a flipped NSView's context).
    static func FromCGContext(_ ctx: CGContext, _ w: Int, _ h: Int) -> Graphics {
        return Graphics(ctx, .identity, w, h, nil)
    }
    /// Screen DC stand-in (DpiX = 96).
    static func FromHwnd(_ h: IntPtr) -> Graphics { return FromImage(Bitmap(1, 1)) }
    func Dispose() {}
    func Flush() {}
    var DpiX: Double { return 96 }
    var DpiY: Double { return 96 }

    var SmoothingMode: SmoothingMode { get { return st.smoothing } set { st.smoothing = newValue } }
    var InterpolationMode: InterpolationMode { get { return st.interpolation } set { st.interpolation = newValue } }
    var PixelOffsetMode: PixelOffsetMode { get { return st.pixelOffset } set { st.pixelOffset = newValue } }
    var CompositingMode: CompositingMode { get { return st.compositing } set { st.compositing = newValue } }
    var CompositingQuality: CompositingQuality { get { return st.compQuality } set { st.compQuality = newValue } }
    var TextRenderingHint: TextRenderingHint { get { return st.textHint } set { st.textHint = newValue } }
    var TextContrast = 4
    var PageUnit: GraphicsUnit = .Pixel
    var Transform: Matrix { get { return Matrix(st.transform) } set { st.transform = newValue.t } }
    private var aa: Bool { return st.smoothing == .AntiAlias || st.smoothing == .HighQuality }

    // --- state ---
    func Save() -> GraphicsState { saved.append(st); return GraphicsState(saved.count - 1) }
    func Restore(_ s: GraphicsState) {
        if s.index >= 0 && s.index < saved.count { st = saved[s.index]; saved.removeSubrange(s.index..<saved.count) }
    }
    func BeginContainer() -> GraphicsContainer { let s = Save(); st.transform = .identity; return GraphicsContainer(s.index) }
    func EndContainer(_ c: GraphicsContainer) { Restore(GraphicsState(c.index)) }
    func TranslateTransform(_ dx: Double, _ dy: Double) { st.transform = st.transform.translatedBy(x: dx, y: dy) }
    func ScaleTransform(_ sx: Double, _ sy: Double) { st.transform = st.transform.scaledBy(x: sx, y: sy) }
    func RotateTransform(_ deg: Double) { st.transform = st.transform.rotated(by: deg * Double.pi / 180) }
    func ResetTransform() { st.transform = .identity }
    func SetClip(_ r: Rectangle) { SetClip(RectangleF(r)) }
    func SetClip(_ r: RectangleF) { var t = st.transform; st.clip = CGPath(rect: r.cg, transform: &t) }
    func SetClip(_ p: GraphicsPath) { var t = st.transform; st.clip = p.cgPath.copy(using: &t) }
    func SetClip(_ r: Rectangle, _ mode: CombineMode) { if mode == .Intersect { IntersectClip(r) } else { SetClip(r) } }
    func SetClip(_ r: RectangleF, _ mode: CombineMode) { if mode == .Intersect { IntersectClip(r) } else { SetClip(r) } }
    func IntersectClip(_ r: Rectangle) { IntersectClip(RectangleF(r)) }
    func IntersectClip(_ r: RectangleF) {
        var t = st.transform
        let newRect = CGPath(rect: r.cg, transform: &t)
        guard let old = st.clip else { st.clip = newRect; return }
        st.clip = old.intersection(newRect)
    }
    func ResetClip() { st.clip = nil }
    var ClipBounds: RectangleF {
        guard let c = st.clip else { return RectangleF(0, 0, Double(Width), Double(Height)) }
        let b = c.boundingBoxOfPath.applying(st.transform.inverted())
        return RectangleF(Double(b.origin.x), Double(b.origin.y), Double(b.width), Double(b.height))
    }
    var VisibleClipBounds: RectangleF { return ClipBounds }
    var IsClipEmpty: Bool { return st.clip?.boundingBoxOfPath.isEmpty ?? false }

    /// Runs `body` with base transform, clip, world transform and AA applied. `stroke` adds GDI's half-pixel stroke offset.
    private func draw(_ antialias: Bool, _ halfPixel: Bool = false, _ body: (CGContext) -> Void) {
        ctx.saveGState()
        ctx.concatenate(base)
        if let c = st.clip { ctx.addPath(c); ctx.clip() }
        if halfPixel && !antialias { ctx.translateBy(x: 0.5, y: 0.5) }
        ctx.concatenate(st.transform)
        ctx.setShouldAntialias(antialias)
        ctx.setAllowsAntialiasing(antialias)
        if st.compositing == .SourceCopy { ctx.setBlendMode(.copy) }
        body(ctx)
        ctx.restoreGState()
    }

    // --- brush application ---
    /// Fills the current path (already added to ctx) with brush.
    private func fillCurrent(_ c: CGContext, _ b: Brush, _ evenOdd: Bool) {
        let rule: CGPathFillRule = evenOdd ? .evenOdd : .winding
        if let sb = b as? SolidBrush {
            if sb.Color.IsKey {
                c.setBlendMode(.clear); c.fillPath(using: rule)
            } else {
                c.setFillColor(sb.Color.cg); c.fillPath(using: rule)
            }
        } else if let lb = b as? LinearGradientBrush {
            c.clip(using: rule)
            if let g = lb.gradient() { c.drawLinearGradient(g, start: lb.p1, end: lb.p2, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]) }
        } else if let pb = b as? PathGradientBrush {
            c.clip(using: rule)
            let bounds = pb.path.GetBounds()
            let rx = Swift.max(0.001, bounds.Width / 2), ry = Swift.max(0.001, bounds.Height / 2)
            let surround = pb.SurroundColors.first ?? pb.CenterColor
            var cols: [CGColor] = [pb.CenterColor.cg, surround.cg]
            var locs: [CGFloat] = [0, 1]
            if let ib = pb.InterpolationColors, ib.Colors.count >= 2 {
                // GDI: position 0 = outer edge, 1 = center
                cols = ib.Colors.reversed().map { $0.cg }
                locs = ib.Positions.reversed().map { CGFloat(1 - $0) }
            }
            if let g = CGGradient(colorsSpace: _gdiColorSpace, colors: cols as CFArray, locations: locs) {
                c.translateBy(x: CGFloat(pb.CenterPoint.X), y: CGFloat(pb.CenterPoint.Y))
                c.scaleBy(x: CGFloat(rx), y: CGFloat(ry))
                c.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [.drawsAfterEndLocation])
            }
        } else if let tb = b as? TextureBrush {
            c.clip(using: rule)
            if let img = tb.image.cgImage {
                c.scaleBy(x: 1, y: -1)
                c.draw(img, in: CGRect(x: 0, y: -tb.image.Height, width: tb.image.Width, height: tb.image.Height), byTiling: true)
            }
        } else if let hb = b as? HatchBrush {
            c.setFillColor(hb.fore.cg); c.fillPath(using: rule)
        }
    }
    private func fill(_ b: Brush, _ evenOdd: Bool, _ build: (CGContext) -> Void) {
        draw(aa) { c in build(c); fillCurrent(c, b, evenOdd) }
    }
    private func stroke(_ p: Pen, _ build: (CGContext) -> Void) {
        let thin = p.Width <= 1.5
        draw(aa, true) { c in
            build(c)
            c.setLineWidth(CGFloat(Swift.max(p.Width, aa ? 0.01 : 1)))
            switch p.LineJoin { case .Miter, .MiterClipped: c.setLineJoin(.miter); case .Bevel: c.setLineJoin(.bevel); case .Round: c.setLineJoin(.round) }
            let cap: CGLineCap
            switch p.StartCap {
            case .Round, .RoundAnchor: cap = .round
            case .Square, .SquareAnchor: cap = .square
            default: cap = (!aa && thin) ? .square : .butt   // aliased GDI+ lines include both end pixels
            }
            c.setLineCap(cap)
            let w = CGFloat(Swift.max(1, p.Width))
            switch p.DashStyle {
            case .Dash: c.setLineDash(phase: 0, lengths: [3 * w, 1 * w])
            case .Dot: c.setLineDash(phase: 0, lengths: [1 * w, 1 * w])
            case .DashDot: c.setLineDash(phase: 0, lengths: [3 * w, w, w, w])
            case .DashDotDot: c.setLineDash(phase: 0, lengths: [3 * w, w, w, w, w, w])
            case .Custom: if let d = p.DashPattern { c.setLineDash(phase: 0, lengths: d.map { CGFloat($0) * w }) }
            case .Solid: break
            }
            if let lb = p.Brush as? LinearGradientBrush, !(p.Brush is SolidBrush) {
                c.replacePathWithStrokedPath()
                c.clip()
                if let g = lb.gradient() { c.drawLinearGradient(g, start: lb.p1, end: lb.p2, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]) }
                return
            }
            if p.Color.IsKey { c.setBlendMode(.clear); c.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)) }
            else { c.setStrokeColor(p.Color.cg) }
            c.strokePath()
        }
    }

    // --- Clear ---
    func Clear(_ col: Color) {
        ctx.saveGState()
        ctx.concatenate(base)
        if let c = st.clip { ctx.addPath(c); ctx.clip() }
        let r = CGRect(x: -1, y: -1, width: Width + 2, height: Height + 2)
        if col.IsKey || col.A == 0 { ctx.clear(r) }
        else { ctx.setBlendMode(.copy); ctx.setFillColor(col.cg); ctx.fill(r) }
        ctx.restoreGState()
    }

    // --- rectangles ---
    func FillRectangle(_ b: Brush, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        if w <= 0 || h <= 0 { return }
        fill(b, false) { $0.addRect(CGRect(x: x, y: y, width: w, height: h)) }
    }
    func FillRectangle(_ b: Brush, _ x: Int, _ y: Int, _ w: Int, _ h: Int) { FillRectangle(b, Double(x), Double(y), Double(w), Double(h)) }
    func FillRectangle(_ b: Brush, _ r: Rectangle) { FillRectangle(b, Double(r.X), Double(r.Y), Double(r.Width), Double(r.Height)) }
    func FillRectangle(_ b: Brush, _ r: RectangleF) { FillRectangle(b, r.X, r.Y, r.Width, r.Height) }
    func FillRectangles(_ b: Brush, _ rs: [Rectangle]) { for r in rs { FillRectangle(b, r) } }
    func FillRectangles(_ b: Brush, _ rs: [RectangleF]) { for r in rs { FillRectangle(b, r) } }
    func DrawRectangle(_ p: Pen, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        stroke(p) { $0.addRect(CGRect(x: x, y: y, width: w, height: h)) }
    }
    func DrawRectangle(_ p: Pen, _ x: Int, _ y: Int, _ w: Int, _ h: Int) { DrawRectangle(p, Double(x), Double(y), Double(w), Double(h)) }
    func DrawRectangle(_ p: Pen, _ r: Rectangle) { DrawRectangle(p, Double(r.X), Double(r.Y), Double(r.Width), Double(r.Height)) }
    func DrawRectangle(_ p: Pen, _ r: RectangleF) { DrawRectangle(p, r.X, r.Y, r.Width, r.Height) }

    // --- ellipses / arcs / pies ---
    func FillEllipse(_ b: Brush, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        if w <= 0 || h <= 0 { return }
        fill(b, false) { $0.addEllipse(in: CGRect(x: x, y: y, width: w, height: h)) }
    }
    func FillEllipse(_ b: Brush, _ x: Int, _ y: Int, _ w: Int, _ h: Int) { FillEllipse(b, Double(x), Double(y), Double(w), Double(h)) }
    func FillEllipse(_ b: Brush, _ r: Rectangle) { FillEllipse(b, Double(r.X), Double(r.Y), Double(r.Width), Double(r.Height)) }
    func FillEllipse(_ b: Brush, _ r: RectangleF) { FillEllipse(b, r.X, r.Y, r.Width, r.Height) }
    func DrawEllipse(_ p: Pen, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        stroke(p) { $0.addEllipse(in: CGRect(x: x, y: y, width: w, height: h)) }
    }
    func DrawEllipse(_ p: Pen, _ x: Int, _ y: Int, _ w: Int, _ h: Int) { DrawEllipse(p, Double(x), Double(y), Double(w), Double(h)) }
    func DrawEllipse(_ p: Pen, _ r: Rectangle) { DrawEllipse(p, Double(r.X), Double(r.Y), Double(r.Width), Double(r.Height)) }
    func DrawEllipse(_ p: Pen, _ r: RectangleF) { DrawEllipse(p, r.X, r.Y, r.Width, r.Height) }
    func DrawArc(_ p: Pen, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ start: Double, _ sweep: Double) {
        let gp = GraphicsPath(); gp.AddArc(x, y, w, h, start, sweep)
        stroke(p) { $0.addPath(gp.cgPath) }
    }
    func DrawArc(_ p: Pen, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ start: Double, _ sweep: Double) { DrawArc(p, Double(x), Double(y), Double(w), Double(h), start, sweep) }
    func DrawArc(_ p: Pen, _ r: Rectangle, _ start: Double, _ sweep: Double) { DrawArc(p, Double(r.X), Double(r.Y), Double(r.Width), Double(r.Height), start, sweep) }
    func DrawArc(_ p: Pen, _ r: RectangleF, _ start: Double, _ sweep: Double) { DrawArc(p, r.X, r.Y, r.Width, r.Height, start, sweep) }
    func FillPie(_ b: Brush, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ start: Double, _ sweep: Double) {
        let gp = GraphicsPath(); gp.AddPie(x, y, w, h, start, sweep)
        fill(b, false) { $0.addPath(gp.cgPath) }
    }
    func FillPie(_ b: Brush, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ start: Double, _ sweep: Double) { FillPie(b, Double(x), Double(y), Double(w), Double(h), start, sweep) }
    func FillPie(_ b: Brush, _ r: Rectangle, _ start: Double, _ sweep: Double) { FillPie(b, Double(r.X), Double(r.Y), Double(r.Width), Double(r.Height), start, sweep) }
    func DrawPie(_ p: Pen, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ start: Double, _ sweep: Double) {
        let gp = GraphicsPath(); gp.AddPie(x, y, w, h, start, sweep)
        stroke(p) { $0.addPath(gp.cgPath) }
    }

    // --- lines / polygons / curves ---
    func DrawLine(_ p: Pen, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        stroke(p) { c in c.move(to: CGPoint(x: x1, y: y1)); c.addLine(to: CGPoint(x: x2, y: y2)) }
    }
    func DrawLine(_ p: Pen, _ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) { DrawLine(p, Double(x1), Double(y1), Double(x2), Double(y2)) }
    func DrawLine(_ p: Pen, _ a: Point, _ b: Point) { DrawLine(p, Double(a.X), Double(a.Y), Double(b.X), Double(b.Y)) }
    func DrawLine(_ p: Pen, _ a: PointF, _ b: PointF) { DrawLine(p, a.X, a.Y, b.X, b.Y) }
    func DrawLines(_ p: Pen, _ pts: [PointF]) {
        guard pts.count >= 2 else { return }
        stroke(p) { $0.addLines(between: pts.map { $0.cg }) }
    }
    func DrawLines(_ p: Pen, _ pts: [Point]) { DrawLines(p, pts.map { PointF($0) }) }
    func DrawPolygon(_ p: Pen, _ pts: [PointF]) {
        guard pts.count >= 2 else { return }
        stroke(p) { c in c.addLines(between: pts.map { $0.cg }); c.closePath() }
    }
    func DrawPolygon(_ p: Pen, _ pts: [Point]) { DrawPolygon(p, pts.map { PointF($0) }) }
    func FillPolygon(_ b: Brush, _ pts: [PointF]) {
        guard pts.count >= 3 else { return }
        fill(b, true) { c in c.addLines(between: pts.map { $0.cg }); c.closePath() }
    }
    func FillPolygon(_ b: Brush, _ pts: [Point]) { FillPolygon(b, pts.map { PointF($0) }) }
    func FillPolygon(_ b: Brush, _ pts: [PointF], _ mode: FillMode) {
        guard pts.count >= 3 else { return }
        fill(b, mode == .Alternate) { c in c.addLines(between: pts.map { $0.cg }); c.closePath() }
    }
    func DrawBezier(_ p: Pen, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double, _ x4: Double, _ y4: Double) {
        stroke(p) { c in
            c.move(to: CGPoint(x: x1, y: y1))
            c.addCurve(to: CGPoint(x: x4, y: y4), control1: CGPoint(x: x2, y: y2), control2: CGPoint(x: x3, y: y3))
        }
    }
    func DrawBezier(_ p: Pen, _ a: PointF, _ b: PointF, _ c: PointF, _ d: PointF) { DrawBezier(p, a.X, a.Y, b.X, b.Y, c.X, c.Y, d.X, d.Y) }
    func DrawBezier(_ p: Pen, _ a: Point, _ b: Point, _ c: Point, _ d: Point) { DrawBezier(p, PointF(a), PointF(b), PointF(c), PointF(d)) }
    func DrawCurve(_ p: Pen, _ pts: [PointF]) { DrawLines(p, pts) }
    func FillPath(_ b: Brush, _ gp: GraphicsPath) { fill(b, gp.FillMode == .Alternate) { $0.addPath(gp.cgPath) } }
    func DrawPath(_ p: Pen, _ gp: GraphicsPath) { stroke(p) { $0.addPath(gp.cgPath) } }
    func FillRegion(_ b: Brush, _ r: Region) { fill(b, true) { $0.addPath(r.path) } }

    // --- images ---
    private func drawImage(_ img: CGImage, _ dest: CGRect, _ alpha: Double) {
        draw(true) { c in
            c.interpolationQuality = st.interpolation == .NearestNeighbor ? .none : (st.interpolation == .Low ? .low : .high)
            if alpha < 1 { c.setAlpha(CGFloat(Swift.max(0, alpha))) }
            // images are y-up in CG: flip locally
            c.translateBy(x: dest.origin.x, y: dest.origin.y + dest.height)
            c.scaleBy(x: 1, y: -1)
            c.draw(img, in: CGRect(x: 0, y: 0, width: dest.width, height: dest.height))
        }
    }
    private func crop(_ b: Bitmap, _ src: RectangleF) -> CGImage? {
        guard let img = b.cgImage else { return nil }
        if src.X == 0 && src.Y == 0 && Int(src.Width) == b.Width && Int(src.Height) == b.Height { return img }
        let s = b.Scale
        return img.cropping(to: CGRect(x: src.X * s, y: src.Y * s, width: src.Width * s, height: src.Height * s))
    }
    func DrawImageUnscaled(_ b: Bitmap?, _ x: Int, _ y: Int) {
        guard let b = b, let img = b.cgImage else { return }
        drawImage(img, CGRect(x: x, y: y, width: b.Width, height: b.Height), 1)
    }
    func DrawImageUnscaled(_ b: Bitmap?, _ p: Point) { DrawImageUnscaled(b, p.X, p.Y) }
    func DrawImageUnscaled(_ b: Bitmap?, _ r: Rectangle) { DrawImageUnscaled(b, r.X, r.Y) }
    func DrawImage(_ b: Bitmap?, _ x: Int, _ y: Int) { DrawImageUnscaled(b, x, y) }
    func DrawImage(_ b: Bitmap?, _ x: Double, _ y: Double) {
        guard let b = b, let img = b.cgImage else { return }
        drawImage(img, CGRect(x: x, y: y, width: Double(b.Width), height: Double(b.Height)), 1)
    }
    func DrawImage(_ b: Bitmap?, _ p: Point) { DrawImageUnscaled(b, p.X, p.Y) }
    func DrawImage(_ b: Bitmap?, _ p: PointF) { DrawImage(b, p.X, p.Y) }
    func DrawImage(_ b: Bitmap?, _ x: Int, _ y: Int, _ w: Int, _ h: Int) { DrawImage(b, RectangleF(Double(x), Double(y), Double(w), Double(h))) }
    func DrawImage(_ b: Bitmap?, _ x: Double, _ y: Double, _ w: Double, _ h: Double) { DrawImage(b, RectangleF(x, y, w, h)) }
    func DrawImage(_ b: Bitmap?, _ r: Rectangle) { DrawImage(b, RectangleF(r)) }
    func DrawImage(_ b: Bitmap?, _ r: RectangleF) {
        guard let b = b, let img = b.cgImage else { return }
        drawImage(img, r.cg, 1)
    }
    func DrawImage(_ b: Bitmap?, _ dest: Rectangle, _ src: Rectangle, _ unit: GraphicsUnit) { DrawImage(b, RectangleF(dest), RectangleF(src), unit) }
    func DrawImage(_ b: Bitmap?, _ dest: RectangleF, _ src: RectangleF, _ unit: GraphicsUnit) {
        guard let b = b, let img = crop(b, src) else { return }
        drawImage(img, dest.cg, 1)
    }
    /// DrawImage(img, destRect, srcX, srcY, srcW, srcH, GraphicsUnit.Pixel, imageAttributes) — only the alpha (Matrix33) is honoured.
    func DrawImage(_ b: Bitmap?, _ dest: Rectangle, _ sx: Int, _ sy: Int, _ sw: Int, _ sh: Int, _ unit: GraphicsUnit, _ ia: ImageAttributes?) {
        DrawImage(b, RectangleF(dest), Double(sx), Double(sy), Double(sw), Double(sh), unit, ia)
    }
    func DrawImage(_ b: Bitmap?, _ dest: Rectangle, _ sx: Double, _ sy: Double, _ sw: Double, _ sh: Double, _ unit: GraphicsUnit, _ ia: ImageAttributes?) {
        DrawImage(b, RectangleF(dest), sx, sy, sw, sh, unit, ia)
    }
    func DrawImage(_ b: Bitmap?, _ dest: RectangleF, _ sx: Double, _ sy: Double, _ sw: Double, _ sh: Double, _ unit: GraphicsUnit, _ ia: ImageAttributes?) {
        guard let b = b, let img = crop(b, RectangleF(sx, sy, sw, sh)) else { return }
        drawImage(img, dest.cg, ia?.alpha ?? 1)
    }
    func DrawImage(_ b: Bitmap?, _ dest: Rectangle, _ sx: Int, _ sy: Int, _ sw: Int, _ sh: Int, _ unit: GraphicsUnit) {
        DrawImage(b, dest, sx, sy, sw, sh, unit, nil)
    }
    /// Draw with constant opacity (convenience for ImageAttributes alpha).
    func DrawImageAlpha(_ b: Bitmap?, _ x: Int, _ y: Int, _ alpha: Double) {
        guard let b = b, let img = b.cgImage else { return }
        drawImage(img, CGRect(x: x, y: y, width: b.Width, height: b.Height), alpha)
    }

    // --- text ---
    /// GDI+ DrawString/MeasureString add ~1/6 em padding left and right (GenericDefault).
    fileprivate static func gdipPad(_ f: Font) -> Double { return f.SizePx / 6.0 }

    fileprivate func drawText(_ s: String, _ f: Font, _ col: Color, _ layout: CGRect, _ hAlign: NSTextAlignment, _ vAlign: Int, _ wrap: Bool, _ clipToRect: Bool) {
        if s.isEmpty { return }
        let ps = NSMutableParagraphStyle()
        ps.alignment = hAlign
        ps.lineBreakMode = wrap ? .byWordWrapping : .byClipping
        let colr = col.IsKey ? NSColor.clear : col.ns
        let attrs: [NSAttributedString.Key: Any] = [.font: f.NSFont, .foregroundColor: colr, .paragraphStyle: ps]
        let a = NSAttributedString(string: s, attributes: attrs)
        let measureW = wrap ? layout.width : CGFloat.greatestFiniteMagnitude
        let br = a.boundingRect(with: CGSize(width: measureW, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
        let th = ceil(br.height)
        var y = layout.origin.y
        if vAlign == 1 { y += (layout.height - th) / 2 } else if vAlign == 2 { y += layout.height - th }
        var r = CGRect(x: layout.origin.x, y: y, width: layout.width, height: th)
        if !wrap {
            // no wrapping: give each line enough room, positioned by alignment
            let tw = ceil(br.width) + 1
            if tw > r.width {
                switch hAlign {
                case .center: r.origin.x -= (tw - r.width) / 2
                case .right: r.origin.x -= tw - r.width
                default: break
                }
                r.size.width = tw
            }
        }
        draw(true) { c in
            if clipToRect { c.clip(to: layout) }
            if col.IsKey { c.setBlendMode(.clear) }
            let prev = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
            a.draw(with: r, options: [.usesLineFragmentOrigin])
            NSGraphicsContext.current = prev
        }
    }
    fileprivate static func measure(_ s: String, _ f: Font, _ maxW: CGFloat?) -> CGSize {
        if s.isEmpty { let fn = f.NSFont; return CGSize(width: 0, height: ceil(fn.ascender - fn.descender + fn.leading)) }
        let a = NSAttributedString(string: s, attributes: [.font: f.NSFont])
        let br = a.boundingRect(with: CGSize(width: maxW ?? CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
        return br.size
    }

    private static func nsAlign(_ a: StringAlignment) -> NSTextAlignment { return a == .Center ? .center : (a == .Far ? .right : .left) }
    private static func vAlign(_ a: StringAlignment) -> Int { return a == .Center ? 1 : (a == .Far ? 2 : 0) }
    private static func brushColor(_ b: Brush) -> Color {
        if let s = b as? SolidBrush { return s.Color }
        if let l = b as? LinearGradientBrush { return l.LinearColors[0] }
        if let p = b as? PathGradientBrush { return p.CenterColor }
        return Color.Black
    }

    func DrawString(_ s: String?, _ f: Font, _ b: Brush, _ x: Double, _ y: Double) { DrawString(s, f, b, x, y, nil) }
    func DrawString(_ s: String?, _ f: Font, _ b: Brush, _ x: Double, _ y: Double, _ sf: StringFormat?) {
        guard let s = s else { return }
        let pad = (sf?.typographic ?? false) ? 0 : Graphics.gdipPad(f)
        let sz = Graphics.measure(s, f, nil)
        var ox = x + pad
        let al = sf?.Alignment ?? .Near
        if al == .Center { ox = x - Double(sz.width) / 2 } else if al == .Far { ox = x - Double(sz.width) - pad }
        var oy = y
        let va = sf?.LineAlignment ?? .Near
        if va == .Center { oy = y - Double(sz.height) / 2 } else if va == .Far { oy = y - Double(sz.height) }
        drawText(s, f, Graphics.brushColor(b), CGRect(x: ox, y: oy, width: Double(sz.width) + 1, height: Double(sz.height)), Graphics.nsAlign(al), 0, false, false)
    }
    func DrawString(_ s: String?, _ f: Font, _ b: Brush, _ x: Int, _ y: Int) { DrawString(s, f, b, Double(x), Double(y), nil) }
    func DrawString(_ s: String?, _ f: Font, _ b: Brush, _ p: PointF) { DrawString(s, f, b, p.X, p.Y, nil) }
    func DrawString(_ s: String?, _ f: Font, _ b: Brush, _ p: PointF, _ sf: StringFormat?) { DrawString(s, f, b, p.X, p.Y, sf) }
    func DrawString(_ s: String?, _ f: Font, _ b: Brush, _ r: RectangleF) { DrawString(s, f, b, r, nil) }
    func DrawString(_ s: String?, _ f: Font, _ b: Brush, _ r: Rectangle) { DrawString(s, f, b, RectangleF(r), nil) }
    func DrawString(_ s: String?, _ f: Font, _ b: Brush, _ r: Rectangle, _ sf: StringFormat?) { DrawString(s, f, b, RectangleF(r), sf) }
    func DrawString(_ s: String?, _ f: Font, _ b: Brush, _ r: RectangleF, _ sf: StringFormat?) {
        guard let s = s else { return }
        let pad = (sf?.typographic ?? false) ? 0 : Graphics.gdipPad(f)
        let wrap = !(sf?.FormatFlags.contains(.NoWrap) ?? false)
        let clip = !(sf?.FormatFlags.contains(.NoClip) ?? false)
        let lay = CGRect(x: r.X + pad, y: r.Y, width: Swift.max(0, r.Width - 2 * pad), height: r.Height)
        drawText(s, f, Graphics.brushColor(b), lay, Graphics.nsAlign(sf?.Alignment ?? .Near), Graphics.vAlign(sf?.LineAlignment ?? .Near), wrap, false)
        _ = clip
    }
    func MeasureString(_ s: String?, _ f: Font) -> SizeF {
        let sz = Graphics.measure(s ?? "", f, nil)
        return SizeF(Double(sz.width) + 2 * Graphics.gdipPad(f), Double(sz.height))
    }
    func MeasureString(_ s: String?, _ f: Font, _ width: Int) -> SizeF {
        let pad = Graphics.gdipPad(f)
        let sz = Graphics.measure(s ?? "", f, CGFloat(Swift.max(1, Double(width) - 2 * pad)))
        return SizeF(Double(sz.width) + 2 * pad, Double(sz.height))
    }
    func MeasureString(_ s: String?, _ f: Font, _ layout: SizeF) -> SizeF { return MeasureString(s, f, CInt(layout.Width)) }
    func MeasureString(_ s: String?, _ f: Font, _ p: PointF, _ sf: StringFormat?) -> SizeF {
        if sf?.typographic ?? false { let sz = Graphics.measure(s ?? "", f, nil); return SizeF(Double(sz.width), Double(sz.height)) }
        return MeasureString(s, f)
    }
    func MeasureString(_ s: String?, _ f: Font, _ width: Int, _ sf: StringFormat?) -> SizeF {
        if sf?.typographic ?? false { let sz = Graphics.measure(s ?? "", f, CGFloat(width)); return SizeF(Double(sz.width), Double(sz.height)) }
        return MeasureString(s, f, width)
    }
}

// MARK: - TextRenderer (GDI text)

enum TextRenderer {
    /// GDI left/right padding when NoPadding isn't given (≈ 1/6 of the font height).
    private static func pad(_ f: Font, _ flags: TextFormatFlags) -> Int {
        if flags.contains(.NoPadding) { return 0 }
        let h = Double(f.Height)
        return flags.contains(.LeftAndRightPadding) ? Int((h / 6 * 2).rounded(.up)) : Int((h / 6).rounded(.up))
    }
    private static func lineH(_ f: Font) -> CGFloat { let n = f.NSFont; return ceil(n.ascender - n.descender) }
    static func MeasureText(_ s: String?, _ f: Font) -> Size { return MeasureText(s, f, Size(Int.max / 4, Int.max / 4), []) }
    static func MeasureText(_ s: String?, _ f: Font, _ proposed: Size) -> Size { return MeasureText(s, f, proposed, []) }
    static func MeasureText(_ s: String?, _ f: Font, _ proposed: Size, _ flags: TextFormatFlags) -> Size {
        let str = s ?? ""
        let p = pad(f, flags)
        if str.isEmpty { return Size(0, Int(lineH(f))) }
        let text = flags.contains(.SingleLine) ? str.replacingOccurrences(of: "\n", with: " ") : str
        let maxW: CGFloat? = flags.contains(.WordBreak) && proposed.Width > 0 && proposed.Width < Int.max / 8 ? CGFloat(proposed.Width - 2 * p) : nil
        let sz = Graphics.measure(text, f, maxW)
        let lines = Swift.max(1, Int((sz.height / lineH(f)).rounded()))
        return Size(Int(ceil(sz.width)) + 2 * p, Swift.max(Int(ceil(sz.height)), lines * Int(lineH(f))))
    }
    static func MeasureText(_ g: Graphics?, _ s: String?, _ f: Font) -> Size { return MeasureText(s, f) }
    static func MeasureText(_ g: Graphics?, _ s: String?, _ f: Font, _ proposed: Size, _ flags: TextFormatFlags) -> Size { return MeasureText(s, f, proposed, flags) }

    static func DrawText(_ g: Graphics, _ s: String?, _ f: Font, _ r: Rectangle, _ col: Color) { DrawText(g, s, f, r, col, []) }
    static func DrawText(_ g: Graphics, _ s: String?, _ f: Font, _ r: Rectangle, _ col: Color, _ flags: TextFormatFlags) {
        guard let s0 = s, !s0.isEmpty else { return }
        let s = flags.contains(.SingleLine) ? s0.replacingOccurrences(of: "\n", with: " ") : s0
        let p = pad(f, flags)
        let lay = CGRect(x: r.X + p, y: r.Y, width: Swift.max(0, r.Width - 2 * p), height: r.Height)
        let h: NSTextAlignment = flags.contains(.HorizontalCenter) ? .center : (flags.contains(.Right) ? .right : .left)
        let v = flags.contains(.VerticalCenter) ? 1 : (flags.contains(.Bottom) ? 2 : 0)
        g.drawText(s, f, col, lay, h, v, flags.contains(.WordBreak), !flags.contains(.NoClipping))
    }
    static func DrawText(_ g: Graphics, _ s: String?, _ f: Font, _ r: Rectangle, _ col: Color, _ back: Color, _ flags: TextFormatFlags) {
        if !back.IsEmpty && back.A > 0 { g.FillRectangle(SolidBrush(back), r) }
        DrawText(g, s, f, r, col, flags)
    }
    static func DrawText(_ g: Graphics, _ s: String?, _ f: Font, _ pt: Point, _ col: Color) { DrawText(g, s, f, pt, col, []) }
    static func DrawText(_ g: Graphics, _ s: String?, _ f: Font, _ pt: Point, _ col: Color, _ flags: TextFormatFlags) {
        guard let s = s, !s.isEmpty else { return }
        let sz = MeasureText(s, f, Size(Int.max / 4, Int.max / 4), flags)
        DrawText(g, s, f, Rectangle(pt.X, pt.Y, sz.Width + 1, sz.Height), col, flags.subtracting([.HorizontalCenter, .VerticalCenter, .Right, .Bottom]).union(.NoClipping))
    }
}

// MARK: - Interop helpers used by 02_forms.swift / 10_platform.swift

/// Graphics over a flipped NSView context (CTM already top-left, y-down, in points).
func _formsGraphics(_ ctx: CGContext, _ w: Int, _ h: Int) -> Graphics? { return Graphics.FromCGContext(ctx, w, h) }
func _formsNSFont(_ f: Font?) -> NSFont { return f?.NSFont ?? NSFont.systemFont(ofSize: 13) }
func _formsCGImage(_ b: Bitmap?) -> CGImage? { return b?.cgImage }
func _formsBitmapScale(_ b: Bitmap?) -> CGFloat { return CGFloat(b?.Scale ?? 1) }
func _formsCloneBitmap(_ b: Bitmap) -> Bitmap { return b.Clone() }
func _formsDrawImageAlpha(_ g: Graphics, _ b: Bitmap?, _ x: Int, _ y: Int, _ alpha: Double) { g.DrawImageAlpha(b, x, y, alpha) }
