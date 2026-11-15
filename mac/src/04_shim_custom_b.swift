// 04_shim_custom_b.swift — WinForms bits the custom-pal maker / share / .deskpal port needs (55–57).
// - Form drag-and-drop (AllowDrop, DragEnter, DragDrop, DragEventArgs, DataFormats.FileDrop, DragDropEffects):
//   FormView (02_forms.swift) forwards draggingEntered / performDragOperation to Form._dragEntered / _performDrag below.
//   Form has no room for stored properties in an extension, so the drag settings live in a side table.
// - OpenFileDialog / SaveFileDialog → NSOpenPanel / NSSavePanel (CuDialogs).
// - TextBox.PreferredHeight.
import AppKit
import UniformTypeIdentifiers

// ---------------------------------------------------------------- drag & drop

enum DataFormats {
    static let FileDrop = "FileDrop"
    static let UnicodeText = "UnicodeText"
}
enum DragDropEffects { case None, Copy, Move, Link, All }

/// e.Data：只有拖進來的檔案（WinForms 的 FileDrop＝string[] 完整路徑）
final class DragData {
    let files: [String]
    init(_ files: [String]) { self.files = files }
    func GetDataPresent(_ format: String) -> Bool { return format == DataFormats.FileDrop && files.count > 0 }
    func GetData(_ format: String) -> Any? { return format == DataFormats.FileDrop ? files : nil }
}

final class DragEventArgs: EventArgs {
    let Data: DragData
    var Effect = DragDropEffects.None
    init(_ d: DragData) { Data = d; super.init() }
}

final class _FormDragInfo {
    var allow = false
    var enter: ((DragEventArgs) -> Void)? = nil
    var drop: ((DragEventArgs) -> Void)? = nil
    var lastEffect = DragDropEffects.None
}
var _formDragTable: [ObjectIdentifier: _FormDragInfo] = [:]

extension Form {
    var _drag: _FormDragInfo {
        let k = ObjectIdentifier(self)
        if let d = _formDragTable[k] { return d }
        let d = _FormDragInfo(); _formDragTable[k] = d
        return d
    }
    var AllowDrop: Bool {
        get { return _drag.allow }
        set { _drag.allow = newValue; _applyAllowDrop() }
    }
    // C# `DragEnter += delegate(object s, DragEventArgs e) {…}` → `DragEnter = { e in … }`
    var DragEnter: ((DragEventArgs) -> Void)? {
        get { return _drag.enter }
        set { _drag.enter = newValue }
    }
    var DragDrop: ((DragEventArgs) -> Void)? {
        get { return _drag.drop }
        set { _drag.drop = newValue }
    }
    /// 視窗是 Show 的時候才建（_ensure）：顯示之後再呼叫一次，把 FormView 登記成可以放檔案
    func _applyAllowDrop() {
        guard let v = view else { return }
        if _drag.allow { v.registerForDraggedTypes([.fileURL]) } else { v.unregisterDraggedTypes() }
    }
    static func _dragFiles(_ s: NSDraggingInfo) -> [String] {
        let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.map { $0.path }
    }
    func _dragEntered(_ s: NSDraggingInfo) -> NSDragOperation {
        if !_drag.allow { return [] }
        let e = DragEventArgs(DragData(Form._dragFiles(s)))
        _drag.enter?(e)
        _drag.lastEffect = e.Effect
        switch e.Effect {
        case .Copy, .All: return .copy
        case .Move: return .move
        case .Link: return .link
        default: return []
        }
    }
    func _performDrag(_ s: NSDraggingInfo) -> Bool {
        if !_drag.allow || _drag.lastEffect == .None { return false }
        let e = DragEventArgs(DragData(Form._dragFiles(s)))
        e.Effect = _drag.lastEffect
        // 跟 WinForms 一樣：放下的那一刻在 UI 執行緒上處理（下一輪，讓拖曳動畫先結束）
        let h = _drag.drop
        DispatchQueue.main.async { h?(e) }
        return true
    }
}

// ---------------------------------------------------------------- file dialogs

/// mac: OpenFileDialog / SaveFileDialog（Filter 的副檔名 → allowedContentTypes；InitialDirectory → directoryURL）
enum CuDialogs {
    static func Types(_ exts: [String]) -> [UTType] {
        var out: [UTType] = []
        for e in exts { if let t = UTType(filenameExtension: e) { out.append(t) } }
        return out
    }
    /// 回傳選到的完整路徑；取消回 nil
    static func Open(_ title: String, _ exts: [String], _ dir: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.title = title; p.message = title
        p.canChooseFiles = true; p.canChooseDirectories = false; p.allowsMultipleSelection = false
        let ts = Types(exts)
        if ts.count > 0 { p.allowedContentTypes = ts }
        if !dir.isEmpty { p.directoryURL = URL(fileURLWithPath: dir, isDirectory: true) }
        p.level = .floating
        let r = p.runModal()
        Form._maybeDeactivate()
        if r != .OK { return nil }
        return p.url?.path
    }
    static func Save(_ title: String, _ fileName: String, _ exts: [String], _ dir: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSSavePanel()
        p.title = title; p.message = title
        p.nameFieldStringValue = fileName
        let ts = Types(exts)
        if ts.count > 0 { p.allowedContentTypes = ts }
        if !dir.isEmpty { p.directoryURL = URL(fileURLWithPath: dir, isDirectory: true) }
        p.level = .floating
        let r = p.runModal()
        Form._maybeDeactivate()
        if r != .OK { return nil }
        return p.url?.path
    }
}

// ---------------------------------------------------------------- TextBox

extension TextBox {
    /// WinForms：字型行高（BorderStyle.None 時沒有外框的空間）
    var PreferredHeight: Int {
        let f = _formsNSFont(Font)
        return Int((f.ascender - f.descender + f.leading).rounded(.up)) + 2
    }
}
