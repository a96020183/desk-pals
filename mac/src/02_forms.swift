// 02_forms.swift — WinForms shim on AppKit (Form, Control, Timer, Cursor, Screen, ToolStrip menus, dialog controls …)
// Coordinates: everything is GLOBAL TOP-LEFT (y down) in points, origin = top-left of the primary screen (like Windows).
// Cocoa (bottom-left) conversion uses the primary screen height.
//
// NOTE for porters — names that are BOTH a type and a Control/Form member (Size, Font, Cursor, FormBorderStyle,
// AutoScaleMode, MouseButtons): inside Form/Control subclasses, Swift resolves `Size(…)`, `Font(…)`,
// `Cursor.Position`, `FormBorderStyle.None`, `MouseButtons.Left` to the *member*. This shim adds instance-side
// mirrors (callAsFunction / same-named instance properties) so those expressions still work inside methods and
// inits. They do NOT work in stored-property initializers of a Form subclass (`let f = Font(…)`): use `lazy var`
// there, or the aliases SizeT / FontT / CursorT.

import AppKit
import QuartzCore

typealias SizeT = Size
typealias FontT = Font
typealias CursorT = Cursor
typealias GraphicsT = Graphics
typealias RectangleT = Rectangle
typealias PointT = Point
typealias ColorT = Color

// ---------------------------------------------------------------- coordinates

enum _Coords {
    static var primaryH: CGFloat { return NSScreen.screens.first?.frame.height ?? 900 }
    // global top-left rect → Cocoa screen rect
    static func toCocoa(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> NSRect {
        return NSRect(x: CGFloat(x), y: primaryH - CGFloat(y) - CGFloat(h), width: CGFloat(w), height: CGFloat(h))
    }
    static func fromCocoa(_ r: NSRect) -> (Int, Int, Int, Int) {
        let x = Int(r.origin.x.rounded()), w = Int(r.size.width.rounded()), h = Int(r.size.height.rounded())
        let y = Int((primaryH - r.origin.y - r.size.height).rounded())
        return (x, y, w, h)
    }
    static func pointToCocoa(_ x: Int, _ y: Int) -> NSPoint { return NSPoint(x: CGFloat(x), y: primaryH - CGFloat(y)) }
    static func isMain() -> Bool { return Foundation.Thread.isMainThread }
    static func onMain(_ a: @escaping () -> Void) { if Foundation.Thread.isMainThread { a() } else { DispatchQueue.main.async(execute: a) } }
}

// ---------------------------------------------------------------- instance-side mirrors (see note at top)

extension Size {
    func callAsFunction(_ w: Int, _ h: Int) -> Size { return SizeT(w, h) }
}
extension Font {
    func callAsFunction(_ name: String, _ size: Double) -> Font { return FontT(name, size) }
    func callAsFunction(_ name: String, _ size: Double, _ style: FontStyle) -> Font { return FontT(name, size, style) }
    func callAsFunction(_ name: String, _ size: Double, _ style: FontStyle, _ unit: GraphicsUnit) -> Font { return FontT(name, size, style, unit) }
    func callAsFunction(_ name: String, _ size: Double, _ unit: GraphicsUnit) -> Font { return FontT(name, size, unit) }
}

// ---------------------------------------------------------------- small enums / args

class EventArgs {
    static let Empty = EventArgs()
    init() { }
}

class CancelEventArgs: EventArgs {
    var Cancel = false
}

struct MouseButtons: Equatable, ExpressibleByIntegerLiteral, CustomStringConvertible {
    var raw: Int
    init(raw: Int) { self.raw = raw }
    init(integerLiteral v: Int) { raw = v }
    static let None = MouseButtons(raw: 0)
    static let Left = MouseButtons(raw: 0x100000)
    static let Right = MouseButtons(raw: 0x200000)
    static let Middle = MouseButtons(raw: 0x400000)
    static let XButton1 = MouseButtons(raw: 0x800000)
    static let XButton2 = MouseButtons(raw: 0x1000000)
    // instance mirrors: `MouseButtons.Left` inside a Control subclass resolves to the static Control.MouseButtons first
    var None: MouseButtons { return MouseButtons.None }
    var Left: MouseButtons { return MouseButtons.Left }
    var Right: MouseButtons { return MouseButtons.Right }
    var Middle: MouseButtons { return MouseButtons.Middle }
    static func & (a: MouseButtons, b: MouseButtons) -> MouseButtons { return MouseButtons(raw: a.raw & b.raw) }
    static func | (a: MouseButtons, b: MouseButtons) -> MouseButtons { return MouseButtons(raw: a.raw | b.raw) }
    var description: String {
        switch raw { case 0: return "None"; case 0x100000: return "Left"; case 0x200000: return "Right"; case 0x400000: return "Middle"; default: return String(raw) }
    }
    func ToString() -> String { return description }
}

class MouseEventArgs: EventArgs {
    let Button: MouseButtons
    let Clicks: Int
    let X: Int
    let Y: Int
    let Delta: Int
    init(_ button: MouseButtons, _ clicks: Int, _ x: Int, _ y: Int, _ delta: Int) {
        Button = button; Clicks = clicks; X = x; Y = y; Delta = delta
        super.init()
    }
    var Location: Point { return PointT(X, Y) }
}

struct Keys: Equatable, ExpressibleByIntegerLiteral {
    var raw: Int
    init(raw: Int) { self.raw = raw }
    init(integerLiteral v: Int) { raw = v }
    static let None = Keys(raw: 0)
    static let Back = Keys(raw: 8), Tab = Keys(raw: 9), Enter = Keys(raw: 13), Return = Keys(raw: 13)
    static let Escape = Keys(raw: 27), Space = Keys(raw: 32)
    static let PageUp = Keys(raw: 33), PageDown = Keys(raw: 34), End = Keys(raw: 35), Home = Keys(raw: 36)
    static let Left = Keys(raw: 37), Up = Keys(raw: 38), Right = Keys(raw: 39), Down = Keys(raw: 40)
    static let Delete = Keys(raw: 46)
    static let D0 = Keys(raw: 48), D1 = Keys(raw: 49), D2 = Keys(raw: 50), D3 = Keys(raw: 51), D4 = Keys(raw: 52)
    static let D5 = Keys(raw: 53), D6 = Keys(raw: 54), D7 = Keys(raw: 55), D8 = Keys(raw: 56), D9 = Keys(raw: 57)
    static let A = Keys(raw: 65), B = Keys(raw: 66), C = Keys(raw: 67), D = Keys(raw: 68), E = Keys(raw: 69), F = Keys(raw: 70)
    static let G = Keys(raw: 71), H = Keys(raw: 72), I = Keys(raw: 73), J = Keys(raw: 74), K = Keys(raw: 75), L = Keys(raw: 76)
    static let M = Keys(raw: 77), N = Keys(raw: 78), O = Keys(raw: 79), P = Keys(raw: 80), Q = Keys(raw: 81), R = Keys(raw: 82)
    static let S = Keys(raw: 83), T = Keys(raw: 84), U = Keys(raw: 85), V = Keys(raw: 86), W = Keys(raw: 87), X = Keys(raw: 88)
    static let Y = Keys(raw: 89), Z = Keys(raw: 90)
    static let F1 = Keys(raw: 112), F2 = Keys(raw: 113), F3 = Keys(raw: 114), F4 = Keys(raw: 115), F5 = Keys(raw: 116)
    static let F6 = Keys(raw: 117), F7 = Keys(raw: 118), F8 = Keys(raw: 119), F9 = Keys(raw: 120), F10 = Keys(raw: 121)
    static let F11 = Keys(raw: 122), F12 = Keys(raw: 123)
    static let KeyCode = Keys(raw: 0xFFFF), Modifiers = Keys(raw: -65536)
    static let Shift = Keys(raw: 0x10000), Control = Keys(raw: 0x20000), Alt = Keys(raw: 0x40000)
    static let ShiftKey = Keys(raw: 16), ControlKey = Keys(raw: 17), Menu = Keys(raw: 18)
    static func & (a: Keys, b: Keys) -> Keys { return Keys(raw: a.raw & b.raw) }
    static func | (a: Keys, b: Keys) -> Keys { return Keys(raw: a.raw | b.raw) }

    // mac virtual key code + characters → Keys (without modifiers)
    static func FromEvent(_ e: NSEvent) -> Keys {
        switch Int(e.keyCode) {
        case 53: return .Escape
        case 36, 76: return .Enter
        case 48: return .Tab
        case 49: return .Space
        case 51: return .Back
        case 117: return .Delete
        case 123: return .Left
        case 124: return .Right
        case 125: return .Down
        case 126: return .Up
        case 115: return .Home
        case 119: return .End
        case 116: return .PageUp
        case 121: return .PageDown
        case 122: return .F1
        case 120: return .F2
        case 99: return .F3
        case 118: return .F4
        case 96: return .F5
        case 97: return .F6
        case 98: return .F7
        case 100: return .F8
        case 101: return .F9
        case 109: return .F10
        case 103: return .F11
        case 111: return .F12
        default: break
        }
        if let ch = e.charactersIgnoringModifiers?.uppercased().unicodeScalars.first {
            let v = Int(ch.value)
            if (v >= 65 && v <= 90) || (v >= 48 && v <= 57) { return Keys(raw: v) }
        }
        return .None
    }
    static func ModsFrom(_ f: NSEvent.ModifierFlags) -> Keys {
        var k = Keys.None
        if f.contains(.shift) { k = k | .Shift }
        if f.contains(.control) { k = k | .Control }
        if f.contains(.option) { k = k | .Alt }
        return k
    }
}

class KeyEventArgs: EventArgs {
    let KeyData: Keys
    var Handled = false
    var SuppressKeyPress = false { didSet { if SuppressKeyPress { Handled = true } } }
    init(_ keyData: Keys) { KeyData = keyData; super.init() }
    var KeyCode: Keys { return KeyData & Keys.KeyCode }
    var Modifiers: Keys { return Keys(raw: KeyData.raw & ~0xFFFF) }
    var KeyValue: Int { return KeyCode.raw }
    var Shift: Bool { return (KeyData & Keys.Shift) != Keys.None }
    var Control: Bool { return (KeyData & Keys.Control) != Keys.None }
    var Alt: Bool { return (KeyData & Keys.Alt) != Keys.None }
}

enum CloseReason { case None, WindowsShutDown, MdiFormClosing, UserClosing, TaskManagerClosing, FormOwnerClosing, ApplicationExitCall }

class FormClosingEventArgs: CancelEventArgs {
    let CloseReason: CloseReason
    init(_ reason: CloseReason, _ cancel: Bool) { CloseReason = reason; super.init(); Cancel = cancel }
}

class PaintEventArgs: EventArgs {
    let Graphics: GraphicsT
    let ClipRectangle: Rectangle
    init(_ g: GraphicsT, _ clip: Rectangle) { Graphics = g; ClipRectangle = clip; super.init() }
}

struct Message {
    var HWnd: IntPtr = 0
    var Msg: Int = 0
    var WParam: IntPtr = 0
    var LParam: IntPtr = 0
    var Result: IntPtr = 0
    init() { }
    init(_ h: IntPtr, _ msg: Int, _ w: IntPtr, _ l: IntPtr) { HWnd = h; Msg = msg; WParam = w; LParam = l }
}

struct FormBorderStyle: Equatable {
    let v: Int
    static let None = FormBorderStyle(v: 0), FixedSingle = FormBorderStyle(v: 1), Fixed3D = FormBorderStyle(v: 2)
    static let FixedDialog = FormBorderStyle(v: 3), Sizable = FormBorderStyle(v: 4)
    static let FixedToolWindow = FormBorderStyle(v: 5), SizableToolWindow = FormBorderStyle(v: 6)
    var None: FormBorderStyle { return FormBorderStyle.None }
    var FixedSingle: FormBorderStyle { return FormBorderStyle.FixedSingle }
    var Fixed3D: FormBorderStyle { return FormBorderStyle.Fixed3D }
    var FixedDialog: FormBorderStyle { return FormBorderStyle.FixedDialog }
    var Sizable: FormBorderStyle { return FormBorderStyle.Sizable }
    var FixedToolWindow: FormBorderStyle { return FormBorderStyle.FixedToolWindow }
    var SizableToolWindow: FormBorderStyle { return FormBorderStyle.SizableToolWindow }
}

struct AutoScaleMode: Equatable {
    let v: Int
    static let None = AutoScaleMode(v: 0), Font = AutoScaleMode(v: 1), Dpi = AutoScaleMode(v: 2), Inherit = AutoScaleMode(v: 3)
    var None: AutoScaleMode { return AutoScaleMode.None }
    var Font: AutoScaleMode { return AutoScaleMode.Font }
    var Dpi: AutoScaleMode { return AutoScaleMode.Dpi }
    var Inherit: AutoScaleMode { return AutoScaleMode.Inherit }
}

enum FormStartPosition { case Manual, CenterScreen, WindowsDefaultLocation, WindowsDefaultBounds, CenterParent }
enum FormWindowState { case Normal, Minimized, Maximized }
enum DialogResult { case None, OK, Cancel, Abort, Retry, Ignore, Yes, No }
enum FlatStyle { case Flat, Popup, Standard, System }
enum DateTimePickerFormat { case Long, Short, Time, Custom }
enum ContentAlignment { case TopLeft, TopCenter, TopRight, MiddleLeft, MiddleCenter, MiddleRight, BottomLeft, BottomCenter, BottomRight }
enum MessageBoxButtons { case OK, OKCancel, YesNo, YesNoCancel, RetryCancel, AbortRetryIgnore }
enum MessageBoxIcon { case None, Information, Warning, Error, Question, Asterisk, Exclamation, Hand, Stop }

// SetStyle(ControlStyles…) is a no-op on mac (views are always double-buffered)
struct ControlStyles: OptionSet {
    let rawValue: Int
    static let UserPaint = ControlStyles(rawValue: 2)
    static let Opaque = ControlStyles(rawValue: 4)
    static let ResizeRedraw = ControlStyles(rawValue: 16)
    static let SupportsTransparentBackColor = ControlStyles(rawValue: 0x800)
    static let AllPaintingInWmPaint = ControlStyles(rawValue: 0x2000)
    static let OptimizedDoubleBuffer = ControlStyles(rawValue: 0x20000)
    static let DoubleBuffer = ControlStyles(rawValue: 0x10000)
    static let Selectable = ControlStyles(rawValue: 0x200)
}

// ---------------------------------------------------------------- Cursor

final class Cursor: Equatable {
    let ns: NSCursor
    let name: String
    init(_ ns: NSCursor, _ name: String) { self.ns = ns; self.name = name }
    static func == (a: Cursor, b: Cursor) -> Bool { return a === b }

    // global top-left
    static var Position: Point {
        get {
            if let ev = CGEvent(source: nil) {
                let p = ev.location   // CG global coords are already top-left of the primary screen
                return PointT(Int(p.x.rounded(.down)), Int(p.y.rounded(.down)))
            }
            let m = NSEvent.mouseLocation
            return PointT(Int(m.x.rounded(.down)), Int((_Coords.primaryH - m.y).rounded(.down)))
        }
        set { CGWarpMouseCursorPosition(CGPoint(x: CGFloat(newValue.X), y: CGFloat(newValue.Y))) }
    }
    // instance mirror (inside Control subclasses `Cursor.Position` resolves to the Cursor *property*)
    var Position: Point { get { return Cursor.Position } set { Cursor.Position = newValue } }
    static var Current: Cursor { get { return Cursors.Default } set { newValue.ns.set() } }
    func ToString() -> String { return "[Cursor: " + name + "]" }
}

enum Cursors {
    static let Default = Cursor(NSCursor.arrow, "Default")
    static let Arrow = Cursor(NSCursor.arrow, "Arrow")
    static let Hand = Cursor(NSCursor.pointingHand, "Hand")
    static let IBeam = Cursor(NSCursor.iBeam, "IBeam")
    static let Cross = Cursor(NSCursor.crosshair, "Cross")
    static let SizeAll = Cursor(NSCursor.openHand, "SizeAll")
    static let SizeWE = Cursor(NSCursor.resizeLeftRight, "SizeWE")
    static let SizeNS = Cursor(NSCursor.resizeUpDown, "SizeNS")
    static let No = Cursor(NSCursor.operationNotAllowed, "No")
    static let WaitCursor = Cursor(NSCursor.arrow, "WaitCursor")
}

// ---------------------------------------------------------------- Screen / SystemInformation

final class Screen: Equatable {
    let Bounds: Rectangle
    let WorkingArea: Rectangle
    let DeviceName: String
    let Primary: Bool
    let BitsPerPixel = 32
    let ns: NSScreen?

    init(_ s: NSScreen?, _ index: Int) {
        ns = s
        if let s = s {
            let b = _Coords.fromCocoa(s.frame), w = _Coords.fromCocoa(s.visibleFrame)
            Bounds = RectangleT(b.0, b.1, b.2, b.3)
            WorkingArea = RectangleT(w.0, w.1, w.2, w.3)
            var name = "\\\\.\\DISPLAY" + String(index + 1)
            if let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber { name += ":" + n.stringValue }
            DeviceName = name
        } else {
            Bounds = RectangleT(0, 0, 1440, 900); WorkingArea = RectangleT(0, 25, 1440, 875); DeviceName = "\\\\.\\DISPLAY1"
        }
        Primary = index == 0
    }
    static func == (a: Screen, b: Screen) -> Bool { return a.DeviceName == b.DeviceName && a.Bounds == b.Bounds }

    static var AllScreens: [Screen] {
        let ss = NSScreen.screens
        if ss.isEmpty { return [Screen(nil, 0)] }
        var out: [Screen] = []
        for (i, s) in ss.enumerated() { out.append(Screen(s, i)) }
        return out
    }
    static var PrimaryScreen: Screen { return AllScreens[0] }

    static func FromPoint(_ p: Point) -> Screen {
        let all = AllScreens
        var best = all[0]
        var bestD = Int.max
        for s in all {
            let b = s.Bounds
            if p.X >= b.X && p.X < b.X + b.Width && p.Y >= b.Y && p.Y < b.Y + b.Height { return s }
            let dx = p.X < b.X ? b.X - p.X : (p.X >= b.X + b.Width ? p.X - (b.X + b.Width - 1) : 0)
            let dy = p.Y < b.Y ? b.Y - p.Y : (p.Y >= b.Y + b.Height ? p.Y - (b.Y + b.Height - 1) : 0)
            let d = dx * dx + dy * dy
            if d < bestD { bestD = d; best = s }
        }
        return best
    }
    static func FromRectangle(_ r: Rectangle) -> Screen {
        let all = AllScreens
        var best: Screen? = nil
        var bestA = 0
        for s in all {
            let b = s.Bounds
            let l = max(b.X, r.X), t = max(b.Y, r.Y), rr = min(b.X + b.Width, r.X + r.Width), bb = min(b.Y + b.Height, r.Y + r.Height)
            let a = rr > l && bb > t ? (rr - l) * (bb - t) : 0
            if a > bestA { bestA = a; best = s }
        }
        return best ?? FromPoint(PointT(r.X + r.Width / 2, r.Y + r.Height / 2))
    }
    static func FromHandle(_ h: IntPtr) -> Screen {
        if let f = Form._FromHandle(h) { return FromRectangle(f.Bounds) }
        var r = W.RECT()
        if W.GetWindowRect(h, &r) { return FromRectangle(RectangleT(r.L, r.T, r.R - r.L, r.B - r.T)) }
        return PrimaryScreen
    }
    static func FromControl(_ c: Control) -> Screen {
        if let f = c as? Form { return FromRectangle(f.Bounds) }
        return PrimaryScreen
    }
    static func GetBounds(_ p: Point) -> Rectangle { return FromPoint(p).Bounds }
    static func GetWorkingArea(_ p: Point) -> Rectangle { return FromPoint(p).WorkingArea }
}

enum SystemInformation {
    static var VirtualScreen: Rectangle {
        var l = Int.max, t = Int.max, r = Int.min, b = Int.min
        for s in Screen.AllScreens {
            let x = s.Bounds
            l = min(l, x.X); t = min(t, x.Y); r = max(r, x.X + x.Width); b = max(b, x.Y + x.Height)
        }
        return RectangleT(l, t, r - l, b - t)
    }
    static var PrimaryMonitorSize: Size { let b = Screen.PrimaryScreen.Bounds; return SizeT(b.Width, b.Height) }
    static var WorkingArea: Rectangle { return Screen.PrimaryScreen.WorkingArea }
    static var MonitorCount: Int { return max(1, NSScreen.screens.count) }
    static var DoubleClickTime: Int { return Int(NSEvent.doubleClickInterval * 1000) }
}

// ---------------------------------------------------------------- Timer (WinForms timer: main run loop, .common modes)

final class Timer {
    private var t: Foundation.Timer? = nil
    private var _interval = 100
    var Tick: (() -> Void)? = nil
    var Tag: Any? = nil
    init() { }
    init(_ interval: Int) { _interval = interval }
    var Interval: Int {
        get { return _interval }
        set { _interval = max(1, newValue); if t != nil { Stop(); Start() } }
    }
    var Enabled: Bool {
        get { return t != nil }
        set { if newValue { Start() } else { Stop() } }
    }
    func Start() {
        if t != nil { return }
        let make = { [weak self] () -> Void in
            guard let self = self, self.t == nil else { return }
            let tm = Foundation.Timer(timeInterval: Double(self._interval) / 1000.0, repeats: true) { [weak self] _ in
                self?.Tick?()
            }
            tm.tolerance = 0
            RunLoop.main.add(tm, forMode: .common)   // keeps firing during menu tracking / window drags
            self.t = tm
        }
        if Foundation.Thread.isMainThread { make() } else { DispatchQueue.main.async(execute: make) }
    }
    func Stop() { t?.invalidate(); t = nil }
    func Dispose() { Stop() }
}

// ---------------------------------------------------------------- Control

final class ControlCollection: Sequence {
    private(set) var items: [Control] = []
    unowned let owner: Control
    init(_ owner: Control) { self.owner = owner }
    func Add(_ c: Control) {
        if c.Parent === owner { return }
        if let p = c.Parent { p.Controls.Remove(c) }
        items.append(c)
        c.Parent = owner
        owner._childAdded(c)
    }
    func AddRange(_ cs: [Control]) { for c in cs { Add(c) } }
    func Remove(_ c: Control) {
        if let i = items.firstIndex(where: { $0 === c }) { items.remove(at: i); c.Parent = nil; c._nsView?.removeFromSuperview() }
    }
    func Clear() { for c in items { c.Parent = nil; c._nsView?.removeFromSuperview() }; items.removeAll() }
    func Contains(_ c: Control) -> Bool { return items.contains { $0 === c } }
    var Count: Int { return items.count }
    subscript(_ i: Int) -> Control { return items[i] }
    func makeIterator() -> IndexingIterator<[Control]> { return items.makeIterator() }
}

class Control {
    // bounds: global top-left for Forms, parent-client-relative for child controls
    var _x = 0, _y = 0, _w = 100, _h = 23
    var _text = ""
    var _font: FontT? = nil
    var _foreColor: Color? = nil
    var _backColor: Color? = nil
    var _visible = true
    var _enabled = true
    var Tag: Any? = nil
    var Name = ""
    var TabIndex = 0
    var TabStop = true
    var AutoSize = false { didSet { _autoSize() } }
    var Dock = 0
    var Anchor = 0
    weak var Parent: Control? = nil
    lazy var Controls = ControlCollection(self)
    var Cursor: CursorT! = Cursors.Default { didSet { _cursorChanged() } }
    var _disposed = false

    init() { }

    // ---- statics (WinForms Control.MouseButtons / ModifierKeys / MousePosition)
    static var MouseButtons: MouseButtons {
        let b = NSEvent.pressedMouseButtons
        var r = 0
        if b & 1 != 0 { r |= 0x100000 }
        if b & 2 != 0 { r |= 0x200000 }
        if b & 4 != 0 { r |= 0x400000 }
        return MouseButtonsT(raw: r)
    }
    static var ModifierKeys: Keys { return Keys.ModsFrom(NSEvent.modifierFlags) }
    static var MousePosition: Point { return CursorT.Position }
    // instance mirrors (so `MouseButtons.Left` / `ModifierKeys` work unqualified inside subclasses)
    var MouseButtons: MouseButtons { return Control.MouseButtons }
    var ModifierKeys: Keys { return Control.ModifierKeys }
    var MousePosition: Point { return Control.MousePosition }

    // ---- geometry
    var Left: Int { get { return _x } set { SetBounds(newValue, _y, _w, _h) } }
    var Top: Int { get { return _y } set { SetBounds(_x, newValue, _w, _h) } }
    var Width: Int { get { return _w } set { SetBounds(_x, _y, newValue, _h) } }
    var Height: Int { get { return _h } set { SetBounds(_x, _y, _w, newValue) } }
    var Right: Int { return _x + _w }
    var Bottom: Int { return _y + _h }
    var Location: Point { get { return PointT(_x, _y) } set { SetBounds(newValue.X, newValue.Y, _w, _h) } }
    var Size: SizeT { get { return SizeT(_w, _h) } set { SetBounds(_x, _y, newValue.Width, newValue.Height) } }
    var Bounds: Rectangle { get { return RectangleT(_x, _y, _w, _h) } set { SetBounds(newValue.X, newValue.Y, newValue.Width, newValue.Height) } }
    var ClientSize: SizeT { get { return SizeT(_w, _h) } set { SetBounds(_x, _y, newValue.Width, newValue.Height) } }
    var ClientRectangle: Rectangle { let c = ClientSize; return RectangleT(0, 0, c.Width, c.Height) }
    func SetBounds(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        _x = x; _y = y; _w = max(0, w); _h = max(0, h)
        _applyBounds()
    }

    // ---- appearance
    var Text: String { get { return _text } set { if _text != newValue { _text = newValue; _textChanged() } } }
    var Font: FontT {
        get { return _font ?? Parent?.Font ?? Control.DefaultFont }
        set { _font = newValue; _styleChanged() }
    }
    static let DefaultFont: FontT = FontT("Microsoft JhengHei UI", 9)
    var ForeColor: Color { get { return _foreColor ?? Parent?.ForeColor ?? Color.FromArgb(0, 0, 0) } set { _foreColor = newValue; _styleChanged() } }
    var BackColor: Color { get { return _backColor ?? Parent?.BackColor ?? Color.FromArgb(0xF0, 0xF0, 0xF0) } set { _backColor = newValue; _styleChanged() } }
    var Enabled: Bool { get { return _enabled } set { _enabled = newValue; _styleChanged() } }

    // ---- visibility (Visible setter routes through the overridable SetVisibleCore like WinForms)
    var Visible: Bool { get { return _visible } set { SetVisibleCore(newValue) } }
    func SetVisibleCore(_ value: Bool) { _visible = value; _nsView?.isHidden = !value }
    func Show() { Visible = true }
    func Hide() { Visible = false }
    func SetStyle(_ s: ControlStyles, _ on: Bool) { }
    func UpdateStyles() { }
    func SuspendLayout() { }
    func ResumeLayout() { }
    func ResumeLayout(_ b: Bool) { }
    func PerformLayout() { }

    var IsDisposed: Bool { return _disposed }
    var Disposing: Bool { return false }
    func Dispose() { _disposed = true; _nsView?.removeFromSuperview() }

    // ---- painting / threading
    func Invalidate() { _Coords.onMain { [weak self] in self?._nsView?.needsDisplay = true } }
    func Invalidate(_ r: Rectangle) { Invalidate() }
    func Refresh() { Invalidate(); if Foundation.Thread.isMainThread { _nsView?.displayIfNeeded() } }
    func Update() { if Foundation.Thread.isMainThread { _nsView?.displayIfNeeded() } }
    func BeginInvoke(_ a: @escaping () -> Void) { DispatchQueue.main.async(execute: a) }
    func Invoke(_ a: @escaping () -> Void) { if Foundation.Thread.isMainThread { a() } else { DispatchQueue.main.sync(execute: a) } }
    var InvokeRequired: Bool { return !Foundation.Thread.isMainThread }
    var Handle: IntPtr { return 0 }
    var IsHandleCreated: Bool { return _nsView != nil }
    var Focused: Bool { return false }
    @discardableResult func Focus() -> Bool { return false }
    func Select() { _ = Focus() }
    func BringToFront() { }
    func SendToBack() { }
    func PointToScreen(_ p: Point) -> Point {
        var x = p.X, y = p.Y
        var c: Control? = self
        while let cc = c { if cc is Form { let cl = (cc as! Form)._clientOrigin(); x += cl.0; y += cl.1; break }; x += cc._x; y += cc._y; c = cc.Parent }
        return PointT(x, y)
    }
    func PointToClient(_ p: Point) -> Point {
        let o = PointToScreen(PointT(0, 0))
        return PointT(p.X - o.X, p.Y - o.Y)
    }

    // ---- overridable events
    func OnPaint(_ e: PaintEventArgs) { Paint?(e) }
    func OnPaintBackground(_ e: PaintEventArgs) { e.Graphics.Clear(BackColor) }
    func OnMouseDown(_ e: MouseEventArgs) { MouseDown?(e) }
    func OnMouseUp(_ e: MouseEventArgs) { MouseUp?(e) }
    func OnMouseMove(_ e: MouseEventArgs) { MouseMove?(e) }
    func OnMouseClick(_ e: MouseEventArgs) { MouseClick?(e) }
    func OnMouseDoubleClick(_ e: MouseEventArgs) { }
    func OnMouseWheel(_ e: MouseEventArgs) { MouseWheel?(e) }
    func OnMouseEnter(_ e: EventArgs) { MouseEnter?() }
    func OnMouseLeave(_ e: EventArgs) { MouseLeave?() }
    func OnClick(_ e: EventArgs) { Click?() }
    func OnKeyDown(_ e: KeyEventArgs) { KeyDown?(e) }
    func OnKeyUp(_ e: KeyEventArgs) { KeyUp?(e) }
    func OnTextChanged(_ e: EventArgs) { TextChanged?() }
    func OnResize(_ e: EventArgs) { Resize?() }
    func OnVisibleChanged(_ e: EventArgs) { VisibleChanged?() }

    // ---- events (C# `x += delegate { }` → `x = { }`; handlers with (sender, e) take just `e`)
    var Paint: ((PaintEventArgs) -> Void)? = nil
    var MouseDown: ((MouseEventArgs) -> Void)? = nil
    var MouseUp: ((MouseEventArgs) -> Void)? = nil
    var MouseMove: ((MouseEventArgs) -> Void)? = nil
    var MouseClick: ((MouseEventArgs) -> Void)? = nil
    var MouseWheel: ((MouseEventArgs) -> Void)? = nil
    var MouseEnter: (() -> Void)? = nil
    var MouseLeave: (() -> Void)? = nil
    var Click: (() -> Void)? = nil
    var KeyDown: ((KeyEventArgs) -> Void)? = nil
    var KeyUp: ((KeyEventArgs) -> Void)? = nil
    var TextChanged: (() -> Void)? = nil
    var Resize: (() -> Void)? = nil
    var VisibleChanged: (() -> Void)? = nil

    // ---- mac internals
    var _nsView: NSView? { return nil }
    func _applyBounds() { _nsView?.frame = NSRect(x: CGFloat(_x), y: CGFloat(_y), width: CGFloat(_w), height: CGFloat(_h)) }
    func _textChanged() { _autoSize(); OnTextChanged(EventArgs.Empty) }
    func _styleChanged() { for c in Controls { c._styleChanged() } }
    func _autoSize() { }
    func _cursorChanged() { }
    func _childAdded(_ c: Control) { }
    func _hostView() -> NSView? { return _nsView }
    func _create() { }   // child controls build their NSView lazily (when added to a form)
}
typealias MouseButtonsT = MouseButtons

// ---------------------------------------------------------------- Form

final class FormPanel: NSPanel {
    weak var form: Form?
    var allowKey = false
    override var canBecomeKey: Bool { return allowKey }
    override var canBecomeMain: Bool { return allowKey }

    // KeyPreview / AcceptButton / CancelButton (skip while an input method is composing — 注音/速成 use Enter/Esc)
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let f = form, allowKey {
            var composing = false
            if let tv = firstResponder as? NSTextView, tv.hasMarkedText() { composing = true }
            if !composing {
                let kc = Keys.FromEvent(event)
                if f.KeyPreview {
                    let e = KeyEventArgs(kc | Keys.ModsFrom(event.modifierFlags))
                    f.OnKeyDown(e)
                    if e.Handled { return }
                }
                if kc == Keys.Enter, let b = f.AcceptButton { b.PerformClick(); return }
                if kc == Keys.Escape, let b = f.CancelButton { b.PerformClick(); return }
            }
        }
        super.sendEvent(event)
    }
}

final class FormWindowDelegate: NSObject, NSWindowDelegate {
    weak var form: Form?
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let f = form else { return true }
        let e = FormClosingEventArgs(.UserClosing, false)
        f.OnFormClosing(e)
        if e.Cancel { return false }
        f._closedByUser()
        return false   // we close ourselves (keeps panel alive for IsDisposed bookkeeping)
    }
    func windowDidMove(_ notification: Notification) { form?._syncFromWindow() }
    func windowDidResize(_ notification: Notification) { form?._syncFromWindow() }
    // WinForms Activated / Deactivate（mac：視窗拿到／失去鍵盤焦點）
    func windowDidBecomeKey(_ notification: Notification) { form?.Activated?() }
    func windowDidResignKey(_ notification: Notification) { form?.Deactivate?() }
}

final class FormView: NSView {
    weak var form: Form?
    var tracking: NSTrackingArea? = nil
    var presented: CGImage? = nil
    var presentedScale: CGFloat = 1
    var ctrlRight = false

    override var isFlipped: Bool { return true }
    override var isOpaque: Bool { return false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }
    override var wantsUpdateLayer: Bool { return presented != nil }
    override func updateLayer() {
        guard let l = layer, let img = presented else { return }
        l.contents = img
        l.contentsScale = presentedScale
        l.contentsGravity = .topLeft
        l.magnificationFilter = .nearest
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let f = form, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        if presented != nil { return }
        let w = Int(bounds.width.rounded()), h = Int(bounds.height.rounded())
        guard let g = _formsGraphics(ctx, w, h) else { return }
        let e = PaintEventArgs(g, RectangleT(0, 0, w, h))
        f.OnPaintBackground(e)
        f.OnPaint(e)
    }

    override func updateTrackingAreas() {
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
        super.updateTrackingAreas()
    }

    func args(_ e: NSEvent, _ b: MouseButtons, _ delta: Int = 0) -> MouseEventArgs {
        let p = convert(e.locationInWindow, from: nil)
        let clicks = (e.type == .mouseMoved || e.type == .scrollWheel || e.type == .leftMouseDragged || e.type == .rightMouseDragged) ? 0 : e.clickCount
        return MouseEventArgs(b, clicks, Int(p.x.rounded(.down)), Int(p.y.rounded(.down)), delta)
    }

    override func mouseDown(with e: NSEvent) {
        guard let f = form else { return }
        // mac: Control+click = right click (trackpads without a secondary click setting)
        ctrlRight = e.modifierFlags.contains(.control)
        f._cursorSet()
        f.OnMouseDown(args(e, ctrlRight ? MouseButtons.Right : MouseButtons.Left))
    }
    override func mouseUp(with e: NSEvent) {
        guard let f = form else { return }
        let b = ctrlRight ? MouseButtons.Right : MouseButtons.Left
        ctrlRight = false
        let a = args(e, b)
        f.OnMouseUp(a)
        if a.X >= 0 && a.Y >= 0 && a.X < f.ClientSize.Width && a.Y < f.ClientSize.Height {
            f.OnClick(EventArgs.Empty)
            f.OnMouseClick(a)
        }
    }
    override func mouseDragged(with e: NSEvent) { form?.OnMouseMove(args(e, ctrlRight ? MouseButtons.Right : MouseButtons.Left)) }
    override func rightMouseDown(with e: NSEvent) { form?.OnMouseDown(args(e, MouseButtons.Right)) }
    override func rightMouseUp(with e: NSEvent) {
        guard let f = form else { return }
        let a = args(e, MouseButtons.Right)
        f.OnMouseUp(a)
        f.OnMouseClick(a)
    }
    override func rightMouseDragged(with e: NSEvent) { form?.OnMouseMove(args(e, MouseButtons.Right)) }
    override func otherMouseDown(with e: NSEvent) { form?.OnMouseDown(args(e, e.buttonNumber == 2 ? MouseButtons.Middle : MouseButtons.XButton1)) }
    override func otherMouseUp(with e: NSEvent) { form?.OnMouseUp(args(e, e.buttonNumber == 2 ? MouseButtons.Middle : MouseButtons.XButton1)) }
    override func mouseMoved(with e: NSEvent) { form?._cursorSet(); form?.OnMouseMove(args(e, MouseButtons.None)) }
    override func mouseEntered(with e: NSEvent) { form?._cursorSet(); form?.OnMouseEnter(EventArgs.Empty) }
    override func mouseExited(with e: NSEvent) { NSCursor.arrow.set(); form?.OnMouseLeave(EventArgs.Empty) }
    override func cursorUpdate(with e: NSEvent) { form?._cursorSet() }
    override func scrollWheel(with e: NSEvent) {
        let d = Int((e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 4 : 40)).rounded())
        form?.OnMouseWheel(args(e, MouseButtons.None, d))
    }
}

class Form: Control {
    var panel: FormPanel? = nil
    var view: FormView? = nil
    var winDelegate: FormWindowDelegate? = nil
    var _handleCreated = false
    var _shownOnce = false
    var _visibleFlag = false
    var _opacity = 1.0
    var _transparencyKey: Color? = nil
    var _borderStyle = FormBorderStyleT.Sizable

    var StartPosition = FormStartPosition.WindowsDefaultLocation
    var ShowInTaskbar = true
    var TopMost = false { didSet { _applyLevel() } }
    var MaximizeBox = true
    var MinimizeBox = true
    var ControlBox = true
    var KeyPreview = false
    var AutoScaleMode = AutoScaleModeT.Font
    var AutoScaleDimensions = SizeT(0, 0)
    var WindowState = FormWindowState.Normal
    var DialogResult = DialogResultT.None
    var AcceptButton: Button? = nil
    var CancelButton: Button? = nil
    var Owner: Form? = nil
    var Icon: Any? = nil
    var DoubleBuffered = true

    // events (C# `FormClosing += delegate(object s, FormClosingEventArgs e) {…}` → `FormClosing = { e in … }`)
    var FormClosing: ((FormClosingEventArgs) -> Void)? = nil
    var FormClosed: (() -> Void)? = nil
    var Shown: (() -> Void)? = nil
    var Load: (() -> Void)? = nil
    var Activated: (() -> Void)? = nil
    var Deactivate: (() -> Void)? = nil

    override init() {
        super.init()
        _w = 300; _h = 300
        _visible = false
    }

    // ---- registry handle → form (for W.*)
    static var _registry: [Int: WeakForm] = [:]
    final class WeakForm { weak var f: Form?; init(_ f: Form) { self.f = f } }
    static func _FromHandle(_ h: IntPtr) -> Form? { return h == 0 ? nil : _registry[h]?.f }
    static var _all: [Form] { return _registry.values.compactMap { $0.f } }

    // ---- border style / overlay-ness
    var FormBorderStyle: FormBorderStyleT {
        get { return _borderStyle }
        set {
            let cs = ClientSize
            _borderStyle = newValue
            if panel == nil { ClientSize = cs }
        }
    }
    var _isDialog: Bool { return _borderStyle != FormBorderStyleT.None }
    // overridable by OverlayForm
    var ShowWithoutActivation: Bool { return false }
    var _wantsClickThrough: Bool { return false }
    var _overlayLevel: NSWindow.Level { return .statusBar }
    // borderless overlay that may become key without activating the app (C#: CreateParams without WS_EX_NOACTIVATE,
    // e.g. the pixel popup menu: gets Esc / arrow keys, Deactivate fires when it loses focus)
    var _overlayKeyable: Bool { return false }

    var _styleMask: NSWindow.StyleMask {
        if !_isDialog { return [.borderless, .nonactivatingPanel] }
        // mac: dialogs are titled panels that can become key even while another app stays active (no activation needed to type)
        var m: NSWindow.StyleMask = [.titled, .closable, .nonactivatingPanel]
        if _borderStyle == FormBorderStyleT.FixedToolWindow || _borderStyle == FormBorderStyleT.SizableToolWindow { m.insert(.utilityWindow) }
        if _borderStyle == FormBorderStyleT.Sizable || _borderStyle == FormBorderStyleT.SizableToolWindow { m.insert(.resizable) }
        if MinimizeBox && !m.contains(.utilityWindow) { m.insert(.miniaturizable) }
        return m
    }

    // client area ↔ outer frame (dialogs have a title bar)
    override var ClientSize: SizeT {
        get {
            if !_isDialog { return SizeT(_w, _h) }
            let c = NSWindow.contentRect(forFrameRect: NSRect(x: 0, y: 0, width: _w, height: _h), styleMask: _styleMask)
            return SizeT(Int(c.width.rounded()), Int(c.height.rounded()))
        }
        set {
            if !_isDialog { SetBounds(_x, _y, newValue.Width, newValue.Height); return }
            let fr = NSWindow.frameRect(forContentRect: NSRect(x: 0, y: 0, width: newValue.Width, height: newValue.Height), styleMask: _styleMask)
            SetBounds(_x, _y, Int(fr.width.rounded()), Int(fr.height.rounded()))
        }
    }
    func _clientOrigin() -> (Int, Int) {
        if !_isDialog { return (_x, _y) }
        let cs = ClientSize
        return (_x + (_w - cs.Width) / 2, _y + (_h - cs.Height))
    }

    // ---- window creation
    override var Handle: IntPtr { _ensure(); return panel?.windowNumber ?? 0 }
    override var IsHandleCreated: Bool { return _handleCreated && !_disposed }
    override var _nsView: NSView? { return view }
    override func _hostView() -> NSView? { return view }

    func _ensure() {
        if panel != nil || _disposed { return }
        if !Foundation.Thread.isMainThread { DispatchQueue.main.sync { self._ensure() }; return }
        let frame = _Coords.toCocoa(_x, _y, max(1, _w), max(1, _h))
        let p = FormPanel(contentRect: NSWindow.contentRect(forFrameRect: frame, styleMask: _styleMask), styleMask: _styleMask, backing: .buffered, defer: false)
        p.form = self
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false
        p.animationBehavior = .none
        if _isDialog {
            p.allowKey = true
            p.becomesKeyOnlyIfNeeded = false
            p.isFloatingPanel = false
            p.title = _text
            p.backgroundColor = _formsNSColor(BackColor)
            p.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            p.hasShadow = true
            p.appearance = NSAppearance(named: .aqua)   // C# dialogs are light (cream background, black text)
        } else {
            p.allowKey = _overlayKeyable
            p.becomesKeyOnlyIfNeeded = !_overlayKeyable
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            p.ignoresMouseEvents = _wantsClickThrough
        }
        let v = FormView(frame: NSRect(origin: .zero, size: p.contentRect(forFrameRect: p.frame).size))
        v.form = self
        v.wantsLayer = true
        v.layerContentsRedrawPolicy = .onSetNeedsDisplay
        v.autoresizingMask = [.width, .height]
        p.contentView = v
        p.acceptsMouseMovedEvents = true
        let d = FormWindowDelegate()
        d.form = self
        p.delegate = d
        winDelegate = d
        panel = p
        view = v
        p.alphaValue = CGFloat(_opacity)
        p.setFrame(frame, display: false)
        _applyLevel()
        for c in Controls { _attach(c) }
        _handleCreated = true
        Form._registry[p.windowNumber] = WeakForm(self)
    }

    func _applyLevel() {
        guard let p = panel else { return }
        if _isDialog { p.level = TopMost ? .floating : .normal } else { p.level = _overlayLevel }   // set last (other props reset level)
    }

    func _attach(_ c: Control) {
        guard let v = view, let cv = c._nsView else { return }
        if cv.superview !== v { v.addSubview(cv) }
        c._applyBounds()
        c._styleChanged()
    }
    override func _childAdded(_ c: Control) { c._create(); _attach(c) }

    override func _applyBounds() {
        guard let p = panel else { return }
        let fr = _Coords.toCocoa(_x, _y, max(1, _w), max(1, _h))
        if p.frame != fr { p.setFrame(fr, display: _visibleFlag) }
        view?.needsDisplay = true
    }
    func _syncFromWindow() {
        guard let p = panel else { return }
        let r = _Coords.fromCocoa(p.frame)
        _x = r.0; _y = r.1; _w = r.2; _h = r.3
    }

    override func _textChanged() { panel?.title = _text; super._textChanged() }
    override func _styleChanged() {
        if let p = panel, _isDialog { p.backgroundColor = _formsNSColor(BackColor) }
        view?.needsDisplay = true
        super._styleChanged()
    }
    override func _cursorChanged() { }
    func _cursorSet() { (Cursor ?? Cursors.Default).ns.set() }

    // ---- opacity / transparency
    var Opacity: Double {
        get { return _opacity }
        set { _opacity = max(0, min(1, newValue)); _Coords.onMain { [weak self] in if let s = self { s.panel?.alphaValue = CGFloat(s._opacity) } } }
    }
    var TransparencyKey: Color {
        get { return _transparencyKey ?? Color.Empty }
        set { _transparencyKey = newValue; view?.needsDisplay = true }
    }
    var AllowTransparency = true

    // ---- visibility
    override var Visible: Bool { get { return _visibleFlag } set { SetVisibleCore(newValue) } }
    override func SetVisibleCore(_ value: Bool) {
        if !Foundation.Thread.isMainThread { DispatchQueue.main.async { self.SetVisibleCore(value) }; return }
        if _disposed { return }
        let was = _visibleFlag
        _visibleFlag = value
        _visible = value
        if value {
            _ensure()
            guard let p = panel else { return }
            if !_shownOnce && StartPosition == .CenterScreen {
                let wa = Screen.FromPoint(CursorT.Position).WorkingArea
                SetBounds(wa.X + (wa.Width - _w) / 2, wa.Y + (wa.Height - _h) / 2, _w, _h)
            }
            _applyBounds()
            if (_isDialog || _overlayKeyable) && !ShowWithoutActivation {
                p.makeKeyAndOrderFront(nil)   // nonactivating panel: becomes key without activating the app
                p.orderFrontRegardless()
            } else {
                p.orderFrontRegardless()
            }
            view?.needsDisplay = true
            if !_shownOnce {
                _shownOnce = true
                Load?()
                DispatchQueue.main.async { [weak self] in self?.OnShown(EventArgs.Empty) }
            }
        } else {
            panel?.orderOut(nil)
            if _isDialog { Form._maybeDeactivate() }
        }
        if was != value { OnVisibleChanged(EventArgs.Empty) }
    }
    func OnShown(_ e: EventArgs) { Shown?() }
    func OnFormClosing(_ e: FormClosingEventArgs) { FormClosing?(e) }
    func OnFormClosed(_ e: EventArgs) { FormClosed?() }
    func OnLoad(_ e: EventArgs) { Load?() }
    // C# WndProc(ref Message m) — on mac only W.RegisterHotKey delivers WM_HOTKEY (0x0312) here
    func WndProc(_ m: inout Message) { }
    func DefWndProc(_ m: inout Message) { }

    func _activateApp() {
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }
    // a dialog went away: give focus back to whoever was before (we're an accessory app)
    static func _maybeDeactivate() {
        DispatchQueue.main.async {
            for f in Form._all where f._isDialog && f._visibleFlag { return }
            if NSApp.isActive { NSApp.deactivate() }
        }
    }

    func Activate() {
        _ensure()
        guard let p = panel else { return }
        if _isDialog || _overlayKeyable { p.makeKeyAndOrderFront(nil); p.orderFrontRegardless() } else { p.orderFrontRegardless() }
    }
    override func BringToFront() { panel?.orderFrontRegardless() }
    override func SendToBack() { panel?.orderBack(nil) }
    override var Focused: Bool { return panel?.isKeyWindow ?? false }
    @discardableResult override func Focus() -> Bool {
        guard let p = panel, _isDialog else { return false }
        p.makeKey()
        return p.isKeyWindow
    }
    var ContainsFocus: Bool { return Focused }

    func Close() {
        if _disposed { return }
        let e = FormClosingEventArgs(.UserClosing, false)
        OnFormClosing(e)
        if e.Cancel { return }
        _closedByUser()
    }
    func _closedByUser() {
        _visibleFlag = false; _visible = false
        if let p = panel {
            p.orderOut(nil)
            Form._registry.removeValue(forKey: p.windowNumber)
            p.delegate = nil
            p.close()
        }
        _disposed = true
        OnFormClosed(EventArgs.Empty)
        if _isDialog { Form._maybeDeactivate() }
    }
    override func Dispose() {
        if _disposed { return }
        if let p = panel { p.orderOut(nil); Form._registry.removeValue(forKey: p.windowNumber); p.delegate = nil; p.close() }
        _visibleFlag = false; _visible = false
        _disposed = true
    }

    // modal dialog (NSApp.runModal)
    @discardableResult func ShowDialog() -> DialogResultT {
        _ensure()
        guard let p = panel else { return .Cancel }
        DialogResult = .None
        Visible = true
        _modal = true
        NSApp.runModal(for: p)
        _modal = false
        Visible = false
        return DialogResult == .None ? .Cancel : DialogResult
    }
    var _modal = false
    func _endModalIfNeeded() { if _modal { NSApp.stopModal() } }

    // ---- per-pixel present (used by W.Present): image + move/resize in one CA transaction
    func _present(_ img: CGImage?, _ scale: CGFloat, _ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        _ensure()
        guard let p = panel, let v = view else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        v.presented = img
        v.presentedScale = scale
        _x = x; _y = y; _w = max(1, w); _h = max(1, h)
        let fr = _Coords.toCocoa(_x, _y, _w, _h)
        if p.frame != fr { p.setFrame(fr, display: false) }
        if let l = v.layer {
            l.contents = img
            l.contentsScale = scale
            l.contentsGravity = .topLeft
            l.magnificationFilter = .nearest
        }
        CATransaction.commit()
    }
}
typealias FormBorderStyleT = FormBorderStyle
typealias AutoScaleModeT = AutoScaleMode
typealias DialogResultT = DialogResult

// ---------------------------------------------------------------- dialog controls (real AppKit views)

final class _ControlTarget: NSObject, NSTextFieldDelegate {
    weak var c: Control?
    init(_ c: Control) { self.c = c }
    @objc func fire(_ sender: Any?) { (c as? Button)?.PerformClick(); (c as? RadioButton)?._clicked(); (c as? CheckBox)?._clicked() }
    func controlTextDidChange(_ obj: Notification) { (c as? TextBox)?._userEdited() }
    @objc func dateChanged(_ sender: Any?) { (c as? DateTimePicker)?.ValueChanged?() }
}

class Label: Control {
    var tf: NSTextField? = nil
    var TextAlign = ContentAlignment.TopLeft
    override init() { super.init(); _w = 100; _h = 23 }
    override var _nsView: NSView? { return tf }
    override func _create() {
        if tf != nil { return }
        let t = NSTextField(labelWithString: _text)
        t.isBezeled = false; t.drawsBackground = false; t.isEditable = false; t.isSelectable = false
        t.lineBreakMode = .byWordWrapping
        tf = t
    }
    override func _styleChanged() {
        guard let t = tf else { return }
        t.font = _formsNSFont(Font)
        t.textColor = _formsNSColor(ForeColor)
        t.isEnabled = Enabled
        _autoSize()
    }
    override func _textChanged() { tf?.stringValue = _text; super._textChanged() }
    override func _autoSize() {
        guard AutoSize else { return }
        if let t = tf {
            let s = t.fittingSize
            _w = Int(ceil(s.width)) + 1; _h = Int(ceil(s.height))
        } else {
            let s = (_text as NSString).size(withAttributes: [.font: _formsNSFont(Font)])
            _w = Int(ceil(s.width)) + 6; _h = Int(ceil(s.height)) + 2
        }
        _applyBounds()
    }
}

class TextBox: Control {
    var tf: NSTextField? = nil
    var target: _ControlTarget? = nil
    var Multiline = false
    var ReadOnly = false { didSet { tf?.isEditable = !ReadOnly } }
    var MaxLength = 32767
    var PlaceholderText = "" { didSet { tf?.placeholderString = PlaceholderText } }
    var UseSystemPasswordChar = false
    override init() { super.init(); _w = 100; _h = 24 }
    override var _nsView: NSView? { return tf }
    override func _create() {
        if tf != nil { return }
        let t = NSTextField(string: _text)
        t.isBezeled = true; t.bezelStyle = .squareBezel; t.isEditable = !ReadOnly; t.isSelectable = true
        t.usesSingleLineMode = !Multiline
        t.cell?.isScrollable = true
        t.cell?.wraps = false
        let tg = _ControlTarget(self)
        t.delegate = tg
        target = tg
        tf = t
    }
    override func _styleChanged() {
        guard let t = tf else { return }
        t.font = _formsNSFont(Font)
        t.textColor = _formsNSColor(ForeColor)
        t.isEnabled = Enabled
    }
    override var Text: String {
        get { if let t = tf { _text = t.stringValue }; return _text }
        set { let old = Text; _text = newValue; tf?.stringValue = newValue; if old != newValue { OnTextChanged(EventArgs.Empty) } }
    }
    func _userEdited() { _text = tf?.stringValue ?? _text; OnTextChanged(EventArgs.Empty) }
    @discardableResult override func Focus() -> Bool {
        guard let t = tf, let w = t.window else { return false }
        return w.makeFirstResponder(t)
    }
    override func Select() { _ = Focus(); tf?.currentEditor()?.selectAll(nil) }
    func SelectAll() { tf?.currentEditor()?.selectAll(nil) }
    func Clear() { Text = "" }
    override var Focused: Bool { guard let t = tf, let ed = t.currentEditor() else { return false }; return t.window?.firstResponder === ed }
}

final class FlatButtonAppearance {
    weak var owner: Button?
    var BorderColor: Color = Color.Empty { didSet { owner?._styleChanged() } }
    var BorderSize = 1 { didSet { owner?._styleChanged() } }
    var MouseOverBackColor: Color = Color.Empty
    var MouseDownBackColor: Color = Color.Empty
}

class Button: Control {
    var bt: NSButton? = nil
    var target: _ControlTarget? = nil
    let FlatAppearance = FlatButtonAppearance()
    var FlatStyle = FlatStyleT.Standard { didSet { _styleChanged() } }
    var UseVisualStyleBackColor = true
    var DialogResult = DialogResultT.None
    override init() { super.init(); _w = 75; _h = 23; FlatAppearance.owner = self }
    override var _nsView: NSView? { return bt }
    override func _create() {
        if bt != nil { return }
        let tg = _ControlTarget(self)
        let b = NSButton(title: _text, target: tg, action: #selector(_ControlTarget.fire(_:)))
        b.bezelStyle = .rounded
        b.wantsLayer = true
        target = tg
        bt = b
    }
    override func _textChanged() { super._textChanged(); _styleChanged() }
    override func _styleChanged() {
        guard let b = bt else { return }
        b.isEnabled = Enabled
        let font = _formsNSFont(Font)
        let para = NSMutableParagraphStyle(); para.alignment = .center
        b.attributedTitle = NSAttributedString(string: _text, attributes: [.font: font, .foregroundColor: _formsNSColor(ForeColor), .paragraphStyle: para])
        if FlatStyle == .Flat || FlatStyle == .Popup {
            b.isBordered = false
            b.layer?.backgroundColor = _formsNSColor(BackColor).cgColor
            b.layer?.cornerRadius = 0
            let bc = FlatAppearance.BorderColor
            b.layer?.borderWidth = CGFloat(FlatAppearance.BorderSize)
            b.layer?.borderColor = (bc == Color.Empty ? NSColor.darkGray : _formsNSColor(bc)).cgColor
        } else {
            b.isBordered = true
            b.bezelStyle = .rounded
            b.layer?.backgroundColor = nil
            b.layer?.borderWidth = 0
        }
    }
    func PerformClick() {
        if !Enabled { return }
        OnClick(EventArgs.Empty)
        if DialogResult != .None, let f = _form() { f.DialogResult = DialogResult; f._endModalIfNeeded() }
    }
    func _form() -> Form? { var c: Control? = Parent; while let cc = c { if let f = cc as? Form { return f }; c = cc.Parent }; return nil }
    @discardableResult override func Focus() -> Bool { guard let b = bt, let w = b.window else { return false }; return w.makeFirstResponder(b) }
}
typealias FlatStyleT = FlatStyle

class RadioButton: Control {
    var bt: NSButton? = nil
    var target: _ControlTarget? = nil
    var _checked = false
    var CheckedChanged: (() -> Void)? = nil
    var AutoCheck = true
    override init() { super.init(); _w = 104; _h = 24 }
    override var _nsView: NSView? { return bt }
    override func _create() {
        if bt != nil { return }
        let tg = _ControlTarget(self)
        let b = NSButton(radioButtonWithTitle: _text, target: tg, action: #selector(_ControlTarget.fire(_:)))
        b.state = _checked ? .on : .off
        target = tg
        bt = b
    }
    var Checked: Bool {
        get { return _checked }
        set {
            if _checked == newValue { bt?.state = newValue ? .on : .off; return }
            _checked = newValue
            bt?.state = newValue ? .on : .off
            if newValue, let p = Parent { for c in p.Controls { if let r = c as? RadioButton, r !== self, r._checked { r.Checked = false } } }
            CheckedChanged?()
        }
    }
    func _clicked() { if AutoCheck { Checked = true } else { bt?.state = _checked ? .on : .off }; OnClick(EventArgs.Empty) }
    func PerformClick() { _clicked() }
    override func _textChanged() { bt?.title = _text; super._textChanged(); _styleChanged() }
    override func _styleChanged() {
        guard let b = bt else { return }
        b.isEnabled = Enabled
        b.attributedTitle = NSAttributedString(string: _text, attributes: [.font: _formsNSFont(Font), .foregroundColor: _formsNSColor(ForeColor)])
        _autoSize()
    }
    override func _autoSize() {
        guard AutoSize, let b = bt else { return }
        let s = b.fittingSize
        _w = Int(ceil(s.width)) + 2; _h = max(_h, Int(ceil(s.height)))
        _applyBounds()
    }
}

class CheckBox: Control {
    var bt: NSButton? = nil
    var target: _ControlTarget? = nil
    var _checked = false
    var CheckedChanged: (() -> Void)? = nil
    override init() { super.init(); _w = 104; _h = 24 }
    override var _nsView: NSView? { return bt }
    override func _create() {
        if bt != nil { return }
        let tg = _ControlTarget(self)
        let b = NSButton(checkboxWithTitle: _text, target: tg, action: #selector(_ControlTarget.fire(_:)))
        b.state = _checked ? .on : .off
        target = tg
        bt = b
    }
    var Checked: Bool {
        get { return _checked }
        set { let ch = _checked != newValue; _checked = newValue; bt?.state = newValue ? .on : .off; if ch { CheckedChanged?() } }
    }
    func _clicked() { Checked = bt?.state == .on; OnClick(EventArgs.Empty) }
    override func _styleChanged() {
        guard let b = bt else { return }
        b.isEnabled = Enabled
        b.attributedTitle = NSAttributedString(string: _text, attributes: [.font: _formsNSFont(Font), .foregroundColor: _formsNSColor(ForeColor)])
        if AutoSize { let s = b.fittingSize; _w = Int(ceil(s.width)) + 2; _applyBounds() }
    }
}

class Panel: Control {
    final class FlippedView: NSView { override var isFlipped: Bool { return true } }
    var pv: FlippedView? = nil
    override var _nsView: NSView? { return pv }
    override func _create() {
        if pv != nil { return }
        let v = FlippedView(); v.wantsLayer = true
        pv = v
        for c in Controls { c._create(); if let cv = c._nsView { v.addSubview(cv) }; c._applyBounds(); c._styleChanged() }
    }
    override func _childAdded(_ c: Control) {
        c._create()
        if let v = pv, let cv = c._nsView { v.addSubview(cv); c._applyBounds(); c._styleChanged() }
    }
    override func _styleChanged() {
        if let b = _backColor { pv?.layer?.backgroundColor = _formsNSColor(b).cgColor }
        super._styleChanged()
    }
}

class DateTimePicker: Control {
    var dp: NSDatePicker? = nil
    var target: _ControlTarget? = nil
    var Format = DateTimePickerFormat.Long
    var CustomFormat = ""
    var ShowUpDown = false
    var ValueChanged: (() -> Void)? = nil
    var _date = Date()
    override init() { super.init(); _w = 200; _h = 24 }
    override var _nsView: NSView? { return dp }
    override func _create() {
        if dp != nil { return }
        let d = NSDatePicker()
        d.datePickerStyle = .textFieldAndStepper
        d.datePickerElements = .yearMonthDay
        d.dateValue = _date
        d.isBezeled = true
        let tg = _ControlTarget(self)
        d.target = tg
        d.action = #selector(_ControlTarget.dateChanged(_:))
        target = tg
        dp = d
    }
    override func _styleChanged() {
        guard let d = dp else { return }
        d.font = _formsNSFont(Font)
        d.isEnabled = Enabled
        d.datePickerElements = (Format == .Time) ? .hourMinuteSecond : (CustomFormat.contains("H") || CustomFormat.contains("m") && CustomFormat.contains(":") ? [.yearMonthDay, .hourMinute] : .yearMonthDay)
    }
    // Value as compat DateTime (local time)
    var Value: DateTime {
        get {
            let d = dp?.dateValue ?? _date
            let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
            return DateTime(c.year ?? 2000, c.month ?? 1, c.day ?? 1, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        }
        set {
            var c = DateComponents()
            c.year = newValue.Year; c.month = newValue.Month; c.day = newValue.Day
            c.hour = newValue.Hour; c.minute = newValue.Minute; c.second = newValue.Second
            _date = Calendar.current.date(from: c) ?? Date()
            dp?.dateValue = _date
            ValueChanged?()
        }
    }
}

// ---------------------------------------------------------------- ToolStrip menus → NSMenu

class ToolStripItem {
    var _text = ""
    var Text: String { get { return _text } set { _text = newValue } }
    var Enabled = true
    var Visible = true
    var Available: Bool { get { return Visible } set { Visible = newValue } }
    var Tag: Any? = nil
    var Name = ""
    var ToolTipText = ""
    var Image: Any? = nil
    var Font: FontT? = nil
    var ForeColor: Color? = nil
    var Click: (() -> Void)? = nil
    weak var Owner: ContextMenuStrip? = nil
    init() { }
    init(_ text: String) { _text = text }
    func PerformClick() { if Enabled { OnClick(EventArgs.Empty) } }
    func OnClick(_ e: EventArgs) { Click?() }
    func Dispose() { }
}

final class ToolStripSeparator: ToolStripItem {
    override init() { super.init() }
}

// a non-clickable label row (the pixel menu draws it as a small section header)
final class ToolStripLabel: ToolStripItem {
    override init() { super.init() }
    override init(_ text: String) { super.init(text) }
}

class ToolStripMenuItem: ToolStripItem {
    var Checked = false
    var CheckOnClick = false
    var ShortcutKeyDisplayString = ""
    lazy var DropDownItems = ToolStripItemCollection()
    var DropDownOpening: (() -> Void)? = nil
    override init() { super.init() }
    override init(_ text: String) { super.init(text) }
    init(_ text: String, _ image: Any?, _ onClick: (() -> Void)?) { super.init(text); Image = image; Click = onClick }
    init(_ text: String, _ image: Any?, _ items: [ToolStripItem]) { super.init(text); Image = image; DropDownItems.AddRange(items) }
    var HasDropDownItems: Bool { return DropDownItems.Count > 0 }
    override func OnClick(_ e: EventArgs) { if CheckOnClick { Checked = !Checked }; super.OnClick(e) }
}

final class ToolStripItemCollection: Sequence {
    private(set) var items: [ToolStripItem] = []
    init() { }
    @discardableResult func Add(_ item: ToolStripItem) -> Int { items.append(item); return items.count - 1 }
    @discardableResult func Add(_ text: String) -> ToolStripItem { let it = ToolStripMenuItem(text); items.append(it); return it }
    @discardableResult func Add(_ text: String, _ image: Any?, _ onClick: (() -> Void)?) -> ToolStripItem {
        let it = ToolStripMenuItem(text, image, onClick); items.append(it); return it
    }
    func AddRange(_ its: [ToolStripItem]) { items.append(contentsOf: its) }
    func Insert(_ i: Int, _ item: ToolStripItem) { items.insert(item, at: Swift.max(0, Swift.min(items.count, i))) }
    func Remove(_ item: ToolStripItem) { if let i = items.firstIndex(where: { $0 === item }) { items.remove(at: i) } }
    func RemoveAt(_ i: Int) { if i >= 0 && i < items.count { items.remove(at: i) } }
    func Clear() { items.removeAll() }
    func Contains(_ item: ToolStripItem) -> Bool { return items.contains { $0 === item } }
    func IndexOf(_ item: ToolStripItem) -> Int { return items.firstIndex { $0 === item } ?? -1 }
    var Count: Int { return items.count }
    subscript(_ i: Int) -> ToolStripItem { return items[i] }
    func makeIterator() -> IndexingIterator<[ToolStripItem]> { return items.makeIterator() }
}

final class _MenuBridge: NSObject, NSMenuDelegate {
    var picked: ToolStripItem? = nil
    var onClose: (() -> Void)? = nil
    @objc func fire(_ sender: NSMenuItem) { picked = sender.representedObject as? ToolStripItem }
    func menuDidClose(_ menu: NSMenu) { }

    func build(_ items: ToolStripItemCollection) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        for it in items {
            if it is ToolStripSeparator { m.addItem(NSMenuItem.separator()); continue }
            if !it.Available { continue }
            let ni = NSMenuItem(title: it.Text, action: nil, keyEquivalent: "")
            ni.isEnabled = it.Enabled
            if let mi = it as? ToolStripMenuItem {
                if mi.Checked { ni.state = .on }
                if mi.DropDownItems.Count > 0 { mi.DropDownOpening?(); ni.submenu = build(mi.DropDownItems); m.addItem(ni); continue }
            }
            ni.representedObject = it
            ni.target = self
            ni.action = #selector(_MenuBridge.fire(_:))
            m.addItem(ni)
        }
        return m
    }
}

class ContextMenuStrip {
    let Items = ToolStripItemCollection()
    // events: C# `Opening += delegate(object s, CancelEventArgs e) {…}` → `Opening = { … }`
    var Opening: (() -> Void)? = nil
    var Closed: (() -> Void)? = nil
    var ItemClicked: ((ToolStripItem) -> Void)? = nil
    var ShowImageMargin = true
    var ShowCheckMargin = false
    var Renderer: Any? = nil
    var Font: FontT? = nil
    var Tag: Any? = nil
    var _visible = false
    var Visible: Bool { return _visible }
    var IsDisposed = false
    init() { }

    // shows synchronously at a global top-left screen point; Click runs after the menu has closed (main thread)
    func Show(_ p: Point) {
        if !Foundation.Thread.isMainThread { DispatchQueue.main.async { self.Show(p) }; return }
        Opening?()
        let br = _MenuBridge()
        let m = br.build(Items)
        _visible = true
        m.popUp(positioning: nil, at: _Coords.pointToCocoa(p.X, p.Y), in: nil)
        _visible = false
        Closed?()
        if let it = br.picked {
            ItemClicked?(it)
            DispatchQueue.main.async { it.PerformClick() }
        }
    }
    func Show(_ x: Int, _ y: Int) { Show(PointT(x, y)) }
    func Show(_ c: Control, _ p: Point) { Show(c.PointToScreen(p)) }
    func Close() { }
    func Dispose() { IsDisposed = true }
}

// ---------------------------------------------------------------- Application / MessageBox

enum Application {
    static func Run() { NSApp.run() }
    static func Run(_ f: Form) { f.Show(); NSApp.run() }
    static func Exit() { _Coords.onMain { NSApp.terminate(nil) } }
    static func ExitThread() { Exit() }
    static func EnableVisualStyles() { }
    static func SetCompatibleTextRenderingDefault(_ b: Bool) { }
    // pump pending events once (like WinForms DoEvents)
    static func DoEvents() {
        guard Foundation.Thread.isMainThread else { return }
        while let e = NSApp.nextEvent(matching: .any, until: Date.distantPast, inMode: .default, dequeue: true) { NSApp.sendEvent(e) }
        RunLoop.current.run(mode: .default, before: Date())
    }
    static var OpenForms: [Form] { return Form._all }
    static var StartupPath: String { return (Bundle.main.executablePath as NSString?)?.deletingLastPathComponent ?? FileManager.default.currentDirectoryPath }
    static var ExecutablePath: String { return Bundle.main.executablePath ?? CommandLine.arguments[0] }
}

enum MessageBox {
    @discardableResult static func Show(_ text: String) -> DialogResult { return Show(text, "", .OK, .None) }
    @discardableResult static func Show(_ text: String, _ caption: String) -> DialogResult { return Show(text, caption, .OK, .None) }
    @discardableResult static func Show(_ text: String, _ caption: String, _ buttons: MessageBoxButtons) -> DialogResult { return Show(text, caption, buttons, .None) }
    @discardableResult static func Show(_ text: String, _ caption: String, _ buttons: MessageBoxButtons, _ icon: MessageBoxIcon) -> DialogResult {
        if !Foundation.Thread.isMainThread { var r = DialogResult.None; DispatchQueue.main.sync { r = Show(text, caption, buttons, icon) }; return r }
        let a = NSAlert()
        a.messageText = caption.isEmpty ? text : caption
        if !caption.isEmpty { a.informativeText = text }
        a.alertStyle = (icon == .Warning || icon == .Exclamation || icon == .Error || icon == .Hand || icon == .Stop) ? .warning : .informational
        var res: [DialogResult] = []
        switch buttons {
        case .OK: a.addButton(withTitle: "OK"); res = [.OK]
        case .OKCancel: a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel"); res = [.OK, .Cancel]
        case .YesNo: a.addButton(withTitle: "Yes"); a.addButton(withTitle: "No"); res = [.Yes, .No]
        case .YesNoCancel: a.addButton(withTitle: "Yes"); a.addButton(withTitle: "No"); a.addButton(withTitle: "Cancel"); res = [.Yes, .No, .Cancel]
        case .RetryCancel: a.addButton(withTitle: "Retry"); a.addButton(withTitle: "Cancel"); res = [.Retry, .Cancel]
        case .AbortRetryIgnore: a.addButton(withTitle: "Abort"); a.addButton(withTitle: "Retry"); a.addButton(withTitle: "Ignore"); res = [.Abort, .Retry, .Ignore]
        }
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        let r = a.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return r >= 0 && r < res.count ? res[r] : .Cancel
    }
}

// ---------------------------------------------------------------- drawing interop (adapts to 01_drawing.swift)

func _formsNSColor(_ c: Color) -> NSColor {
    return NSColor(srgbRed: CGFloat(c.R) / 255.0, green: CGFloat(c.G) / 255.0, blue: CGFloat(c.B) / 255.0, alpha: CGFloat(c.A) / 255.0)
}
