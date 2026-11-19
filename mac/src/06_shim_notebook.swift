// ===== 06_shim_notebook.swift — 小本子（64_notebook.swift）用到的 WinForms／GDI+ shim =====
// RichTextBox（NSScrollView＋NSTextView：只打純文字、固定行高、每行底下的線由子類別畫）、
// NbTextBox（TextBox＋LostFocus）、Cmd+X／C／V／A／Z（沒有「編輯」選單）、FontFamily 的 cell ascent／descent／em、
// .NET Framework 的 string.GetHashCode（要存進 todo.json 的 id 不能每次開都不一樣）、yyyy-MM-dd 解析。
import AppKit

// MARK: - RichTextBox

enum RichTextBoxScrollBars { case None, Horizontal, Vertical, Both, ForcedHorizontal, ForcedVertical, ForcedBoth }

/// NSTextView：背景畫完後讓 RichTextBox 畫「字底下」的東西（筆記紙的線）；座標＝文件座標（左上、y 往下）
final class _RichTextView: NSTextView {
    weak var box: RichTextBox?
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let b = box, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let wd = Int(bounds.width.rounded(.up)), ht = Int(bounds.height.rounded(.up))
        let g = Graphics.FromCGContext(ctx, wd, ht)
        let y0 = Int(textContainerInset.height.rounded())
        let top = Int(rect.minY.rounded(.down)), bottom = Int(rect.maxY.rounded(.up))
        b._PaintUnder(g, y0, top, bottom, wd)
    }
    // 離開打字（WinForms LostFocus）：沒打字就離開也要通知（textDidEndEditing 只有改過字才會送）
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { let b = box; DispatchQueue.main.async { b?.LostFocus?() } }
        return ok
    }
}

/// 使用者打字 → TextChanged（離開 → LostFocus 在 _RichTextView.resignFirstResponder）
final class _RichTextDelegate: NSObject, NSTextViewDelegate {
    weak var box: RichTextBox?
    init(_ b: RichTextBox) { box = b }
    func textDidChange(_ notification: Notification) { box?._userEdited() }
}

/// System.Windows.Forms.RichTextBox（只做小本子用到的）：純文字（不帶別的地方的字型、顏色）、直的捲軸、
/// `_SetLineHeight` 固定行高（NSParagraphStyle 最小＝最大）、子類別覆寫 `_PaintUnder` 在字底下畫東西。
class RichTextBox: Control {
    var sv: NSScrollView? = nil
    var tv: _RichTextView? = nil
    var _storage: NSTextStorage? = nil
    var _del: _RichTextDelegate? = nil
    var _lineH = 0
    var ScrollBars = RichTextBoxScrollBars.Both
    var DetectUrls = true
    var ShortcutsEnabled = true
    var WordWrap = true
    var ReadOnly = false { didSet { tv?.isEditable = !ReadOnly } }
    // C# 的 LostFocus 事件（`x.LostFocus += delegate {…}` → `x.LostFocus = { … }`）
    var LostFocus: (() -> Void)? = nil

    override init() { super.init(); _w = 100; _h = 96 }
    override var _nsView: NSView? { return sv }

    override func _create() {
        if sv != nil { return }
        let s = NSScrollView(frame: NSRect(x: 0, y: 0, width: CGFloat(Swift.max(1, _w)), height: CGFloat(Swift.max(1, _h))))
        s.borderType = .noBorder
        s.hasVerticalScroller = ScrollBars != .None && ScrollBars != .Horizontal && ScrollBars != .ForcedHorizontal
        s.hasHorizontalScroller = false
        s.autohidesScrollers = true
        s.drawsBackground = false
        // TextKit 1（自己建 storage／layout manager／container）：段落樣式的固定行高兩種版本都吃，這樣比較確定
        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let cs = s.contentSize
        let tc = NSTextContainer(containerSize: NSSize(width: cs.width, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        tc.lineFragmentPadding = 0
        lm.addTextContainer(tc)
        let t = _RichTextView(frame: NSRect(x: 0, y: 0, width: cs.width, height: cs.height), textContainer: tc)
        t.box = self
        t.minSize = NSSize(width: 0, height: cs.height)
        t.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        t.isVerticallyResizable = true
        t.isHorizontallyResizable = false
        t.autoresizingMask = [.width]
        t.isRichText = false            // 只貼純文字
        t.importsGraphics = false
        t.allowsUndo = true
        t.usesFindPanel = false
        t.isEditable = !ReadOnly
        t.isSelectable = true
        t.isAutomaticLinkDetectionEnabled = DetectUrls
        t.isAutomaticQuoteSubstitutionEnabled = false
        t.isAutomaticDashSubstitutionEnabled = false
        t.isAutomaticTextReplacementEnabled = false
        t.isAutomaticSpellingCorrectionEnabled = false
        t.isContinuousSpellCheckingEnabled = false
        t.textContainerInset = NSSize(width: 0, height: 0)
        t.string = _text
        let dg = _RichTextDelegate(self)
        t.delegate = dg
        s.documentView = t
        sv = s; tv = t; _storage = storage; _del = dg
        s.isHidden = !_visible
        _styleChanged()
    }

    override func _applyBounds() {
        super._applyBounds()
        guard let s = sv, let t = tv else { return }
        let cs = s.contentSize
        t.minSize = NSSize(width: 0, height: cs.height)
        t.setFrameSize(NSSize(width: cs.width, height: Swift.max(t.frame.height, cs.height)))
        t.sizeToFit()
    }

    override func _styleChanged() {
        guard let t = tv else { return }
        t.backgroundColor = BackColor.ns
        t.drawsBackground = true
        t.insertionPointColor = ForeColor.ns
        t.isEditable = Enabled && !ReadOnly
        _applyAttrs()
    }

    func _attrs() -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [.font: _formsNSFont(Font), .foregroundColor: ForeColor.ns]
        if _lineH > 0 {
            let ps = NSMutableParagraphStyle()
            ps.minimumLineHeight = CGFloat(_lineH)
            ps.maximumLineHeight = CGFloat(_lineH)
            a[.paragraphStyle] = ps
        }
        return a
    }
    /// 整篇套同一個字型、顏色、段落樣式；之後打的字（typingAttributes）也一樣
    func _applyAttrs() {
        guard let t = tv else { return }
        let a = _attrs()
        if let ps = a[.paragraphStyle] as? NSParagraphStyle { t.defaultParagraphStyle = ps }
        t.typingAttributes = a
        if let st = t.textStorage, st.length > 0 {
            st.beginEditing()
            st.setAttributes(a, range: NSRange(location: 0, length: st.length))
            st.endEditing()
        }
        t.needsDisplay = true
    }
    /// mac：EM_SETPARAFORMAT（PFM_LINESPACING、固定）→ 固定行高（px＝pt）
    func _SetLineHeight(_ h: Int) { _lineH = h; _applyAttrs() }

    /// 子類別覆寫：在字底下畫（y0＝第一行上緣；top／bottom＝這次要畫的範圍；都是文件座標）
    func _PaintUnder(_ g: Graphics, _ y0: Int, _ top: Int, _ bottom: Int, _ width: Int) { }

    override var Text: String {
        get { if let t = tv { _text = t.string }; return _text }
        set {
            let old = Text
            _text = newValue
            if let t = tv { t.string = newValue; _applyAttrs() }
            if old != newValue { OnTextChanged(EventArgs.Empty) }
        }
    }
    var TextLength: Int { return Text.utf16.count }
    func _userEdited() { _text = tv?.string ?? _text; OnTextChanged(EventArgs.Empty) }

    override func Invalidate() { _Coords.onMain { [weak self] in self?.tv?.needsDisplay = true } }
    @discardableResult override func Focus() -> Bool {
        guard let t = tv, let w = t.window else { return false }
        return w.makeFirstResponder(t)
    }
    override var Focused: Bool { guard let t = tv else { return false }; return t.window?.firstResponder === t }
    override func _ownsResponder(_ r: NSResponder) -> Bool { guard let t = tv else { return false }; return r === t }

    // 選取（NSRange 跟 .NET 一樣是 UTF-16 位置）
    var SelectionStart: Int {
        get { return tv?.selectedRange().location ?? 0 }
        set { guard let t = tv else { return }; let n = (t.string as NSString).length; t.setSelectedRange(NSRange(location: Swift.max(0, Swift.min(newValue, n)), length: 0)) }
    }
    var SelectionLength: Int {
        get { return tv?.selectedRange().length ?? 0 }
        set { guard let t = tv else { return }; let r = t.selectedRange(); let n = (t.string as NSString).length; t.setSelectedRange(NSRange(location: r.location, length: Swift.max(0, Swift.min(newValue, n - r.location)))) }
    }
    func SelectAll() { tv?.selectAll(nil) }
    func Select(_ start: Int, _ length: Int) {
        guard let t = tv else { return }
        let n = (t.string as NSString).length
        let s = Swift.max(0, Swift.min(start, n))
        t.setSelectedRange(NSRange(location: s, length: Swift.max(0, Swift.min(length, n - s))))
    }
    var SelectedText: String {
        get { guard let t = tv else { return "" }; return (t.string as NSString).substring(with: t.selectedRange()) }
        set {
            guard let t = tv else { return }
            let r = t.selectedRange()
            if t.shouldChangeText(in: r, replacementString: newValue) { t.replaceCharacters(in: r, with: newValue); t.didChangeText() }
        }
    }
}

// MARK: - TextBox with LostFocus

/// mac：WinForms TextBox 的 LostFocus（NSTextField 的 controlTextDidEndEditing＝離開打字）；打字照樣通知 TextBox
class NbTextBox: TextBox {
    var LostFocus: (() -> Void)? = nil
    var nbDel: _NbBoxDelegate? = nil
    override func _create() {
        super._create()
        guard let t = tf, nbDel == nil else { return }
        t.isHidden = !_visible   // Controls.Add 之前設的 Visible = false（TextBox._create 沒有套）
        let dg = _NbBoxDelegate(self)
        t.delegate = dg
        nbDel = dg
    }
}
final class _NbBoxDelegate: NSObject, NSTextFieldDelegate {
    weak var box: NbTextBox?
    init(_ b: NbTextBox) { box = b }
    func controlTextDidChange(_ obj: Notification) { box?._userEdited() }
    func controlTextDidEndEditing(_ obj: Notification) { box?.LostFocus?() }
}

// MARK: - Cmd+X／C／V／A／Z

/// mac：程式沒有「編輯」選單，Cmd+X／C／V／A／Z 不會自己到打字框 → 小本子在 KeyDown 裡送給 first responder
enum NbEditKeys {
    static func Handle() -> Bool {
        guard let ev = NSApp.currentEvent, ev.type == .keyDown, ev.modifierFlags.contains(.command) else { return false }
        let ch = (ev.charactersIgnoringModifiers ?? "").lowercased()
        var sel: Selector? = nil
        switch ch {
        case "x": sel = #selector(NSText.cut(_:))
        case "c": sel = #selector(NSText.copy(_:))
        case "v": sel = #selector(NSText.paste(_:))
        case "a": sel = #selector(NSText.selectAll(_:))
        case "z": sel = ev.modifierFlags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
        default: break
        }
        guard let s = sel else { return false }
        return NSApp.sendAction(s, to: nil, from: nil)
    }
}

// MARK: - FontFamily metrics（GDI+ 的設計單位）

/// mac：em 高＝1000，ascent／descent 從 CoreText 的 ascender／descender 換算（同一個 NSFont，畫跟量才對得上）
extension FontFamily {
    static var _nbMetrics: [String: (Int, Int)] = [:]
    func _nbMetric(_ st: FontStyle) -> (Int, Int) {
        let k = Name + "|" + String(st.rawValue)
        if let v = FontFamily._nbMetrics[k] { return v }
        let f = FontT(Name, 1000, st, GraphicsUnit.Pixel).NSFont
        let v = (Int(f.ascender.rounded()), Int((-f.descender).rounded()))
        FontFamily._nbMetrics[k] = v
        return v
    }
    func GetEmHeight(_ st: FontStyle) -> Int { return 1000 }
    func GetCellAscent(_ st: FontStyle) -> Int { return _nbMetric(st).0 }
    func GetCellDescent(_ st: FontStyle) -> Int { return _nbMetric(st).1 }
}

// MARK: - misc

/// mac：.NET Framework（64 位元）的 string.GetHashCode。Swift 的 hashValue 每次開程式都不一樣，
/// 學校作業進待辦的 id（"s" + hash）會存進 todo.json，要每次都一樣。
func _NbNetHash(_ s: String) -> Int {
    var h1: Int32 = 5381
    var h2: Int32 = 5381
    let u = Array(s.utf16)
    var i = 0
    while i < u.count {
        h1 = ((h1 &<< 5) &+ h1) ^ Int32(u[i])
        if i + 1 >= u.count { break }
        h2 = ((h2 &<< 5) &+ h2) ^ Int32(u[i + 1])
        i += 2
    }
    return Int(h1 &+ (h2 &* 1566083941))
}

/// mac：DateTime.TryParseExact(s, "yyyy-MM-dd", Inv, DateTimeStyles.None, out d)
func _NbParseYmd(_ s: String, _ v: inout DateTime) -> Bool {
    let a = s.Split("-")
    var y = 0, m = 0, d = 0
    if s.Length != 10 || a.count != 3 || a[0].Length != 4 || a[1].Length != 2 || a[2].Length != 2 { return false }
    if !int.TryParse(a[0], &y) || !int.TryParse(a[1], &m) || !int.TryParse(a[2], &d) { return false }
    if y < 1 || m < 1 || m > 12 || d < 1 || d > DateTime.DaysInMonth(y, m) { return false }
    v = DateTime(y, m, d)
    return true
}
