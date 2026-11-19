// ===== 05_shim_work.swift — 0.11（工作來源、小本子、工作設定）共用的 .NET／WinForms shim =====
// AutoResetEvent、Convert、Clipboard、PixText（Windows 的 GDI+ 字；Mac 照舊用 TextRenderer＝CoreText，只給同名的薄殼）。

// MARK: - AutoResetEvent

/// System.Threading.AutoResetEvent: Set() 放行一個 WaitOne（沒人在等就留著，下一個 WaitOne 馬上回來）。
final class AutoResetEvent {
    private let cond = NSCondition()
    private var signaled: Bool
    init(_ initialState: Bool) { signaled = initialState }
    @discardableResult func Set() -> Bool {
        cond.lock(); signaled = true; cond.signal(); cond.unlock()
        return true
    }
    @discardableResult func Reset() -> Bool { cond.lock(); signaled = false; cond.unlock(); return true }
    @discardableResult func WaitOne() -> Bool {
        cond.lock(); defer { cond.unlock() }
        while !signaled { cond.wait() }
        signaled = false
        return true
    }
    @discardableResult func WaitOne(_ ms: Int) -> Bool {
        cond.lock(); defer { cond.unlock() }
        let until = Date(timeIntervalSinceNow: Double(Swift.max(0, ms)) / 1000.0)
        while !signaled { if !cond.wait(until: until) { break } }
        let r = signaled
        signaled = false
        return r
    }
    func Dispose() {}
}

// MARK: - Convert

enum Convert {
    static func ToString(_ v: Any?) -> String { return csToString(v) }
    static func ToString(_ v: Any?, _ c: CultureInfo) -> String { return csToString(v) }
    static func ToBase64String(_ b: [UInt8]) -> String { return Data(b).base64EncodedString() }
    static func FromBase64String(_ s: String) throws -> [UInt8] {
        guard let d = Data(base64Encoded: s, options: [.ignoreUnknownCharacters]) else { throw FormatException("bad base64") }
        return [UInt8](d)
    }
    static func ToInt32(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d.rounded(.toNearestOrEven)) }
        if let b = v as? Bool { return b ? 1 : 0 }
        return Int(csToString(v).Trim()) ?? 0
    }
    static func ToBoolean(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let i = v as? Int { return i != 0 }
        return csToString(v).lowercased() == "true"
    }
}

// MARK: - Clipboard

/// System.Windows.Forms.Clipboard（文字）→ NSPasteboard.general
enum Clipboard {
    static func SetText(_ s: String) {
        let put = {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(s, forType: .string)
        }
        if Foundation.Thread.isMainThread { put() } else { DispatchQueue.main.sync(execute: put) }
    }
    static func GetText() -> String {
        var r = ""
        let get = { r = NSPasteboard.general.string(forType: .string) ?? "" }
        if Foundation.Thread.isMainThread { get() } else { DispatchQueue.main.sync(execute: get) }
        return r
    }
    static func ContainsText() -> Bool { return !GetText().isEmpty }
    static func Clear() { NSPasteboard.general.clearContents() }
}

// MARK: - PixText

/// DeskPals.PixText.cs 在 Windows 修 GDI 的糊字（整數像素字型、量跟畫同一套、Heft 加粗）；CoreText 沒有這個問題，
/// mac: 名字照 C#，量和畫都交給 TextRenderer（跟 0.10 一樣的字）。
enum PixText {
    static let Heft = 0.5
    /// 測試用的 DPI（DESKPALS_TEST_DPI）；mac 一律 96（PORTING.md：點＝Windows 100% 的像素）
    static func TestDpi(_ real: Double) -> Double { return real }
    static func Px(_ f: Font) -> Font { return f }
    static func LineH(_ f: Font) -> Int { return TextRenderer.MeasureText("Ag", f, Size(4000, 400), TextFormatFlags.NoPadding).Height }
    static func LineW(_ s: String?, _ f: Font) -> Int { return TextRenderer.MeasureText(s ?? "", f, Size(4000, 400), [TextFormatFlags.NoPadding, TextFormatFlags.SingleLine, TextFormatFlags.NoPrefix]).Width }
    static func MeasureText(_ s: String?, _ f: Font) -> Size { return TextRenderer.MeasureText(s, f, Size(4000, 400), TextFormatFlags.NoPadding) }
    static func MeasureText(_ s: String?, _ f: Font, _ proposed: Size, _ fl: TextFormatFlags) -> Size { return TextRenderer.MeasureText(s, f, proposed, fl) }
    static func DrawText(_ g: Graphics, _ s: String?, _ f: Font, _ p: Point, _ c: Color, _ fl: TextFormatFlags) { TextRenderer.DrawText(g, s, f, p, c, fl) }
    static func DrawText(_ g: Graphics, _ s: String?, _ f: Font, _ r: Rectangle, _ c: Color, _ fl: TextFormatFlags) { TextRenderer.DrawText(g, s, f, r, c, fl) }
}
