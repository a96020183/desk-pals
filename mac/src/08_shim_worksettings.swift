// ===== 08_shim_worksettings.swift — 工作設定視窗（65_work_settings.swift）用到、shim 還沒有的 WinForms 東西 =====
// - TextBox.GotFocus（點進輸入框＝焦點在那一格）、TextBox.UseSystemPasswordChar（shim 的 TextBox 只記旗標、照樣顯示字）
//   → WsTextBox：自己建 NSTextField／NSSecureTextField，becomeFirstResponder 時叫 GotFocus。
//   UseSystemPasswordChar 要在 Controls.Add（建 NSTextField）之前設，跟 C# 一樣。
// - FolderBrowserDialog → WsDialogs.PickFolder（NSOpenPanel 只選資料夾）。
// - 沒有「編輯」選單：Cmd+X／C／V／A／Z → WsEditKeys（送給 first responder）。
import AppKit

/// mac: 一般輸入框：拿到焦點時通知（WinForms 的 GotFocus）
final class WsField: NSTextField {
    var onFocus: (() -> Void)? = nil
    override func becomeFirstResponder() -> Bool {
        let r = super.becomeFirstResponder()
        if r { onFocus?() }
        return r
    }
}

/// mac: 密碼框（UseSystemPasswordChar）：打的字顯示成圓點；拿到焦點時一樣通知
final class WsSecureField: NSSecureTextField {
    var onFocus: (() -> Void)? = nil
    override func becomeFirstResponder() -> Bool {
        let r = super.becomeFirstResponder()
        if r { onFocus?() }
        return r
    }
}

/// mac: WinForms TextBox ＋ GotFocus 事件 ＋ 真的會遮字的 UseSystemPasswordChar
final class WsTextBox: TextBox {
    var GotFocus: (() -> Void)? = nil
    override func _create() {
        if tf != nil { return }
        let t: NSTextField
        if UseSystemPasswordChar {
            let s = WsSecureField(string: _text)
            s.onFocus = { [weak self] in self?.GotFocus?() }
            t = s
        } else {
            let s = WsField(string: _text)
            s.onFocus = { [weak self] in self?.GotFocus?() }
            t = s
        }
        t.isBezeled = true; t.bezelStyle = .squareBezel; t.isEditable = !ReadOnly; t.isSelectable = true
        t.usesSingleLineMode = !Multiline
        t.cell?.isScrollable = true
        t.cell?.wraps = false
        t.placeholderString = PlaceholderText.isEmpty ? nil : PlaceholderText
        let tg = _ControlTarget(self)
        t.delegate = tg
        target = tg
        tf = t
    }
}

/// mac: 程式沒有「編輯」選單，Cmd+X／C／V／A／Z 不會自己到打字框（貼 Jira token 要用）→ 工作設定在 KeyDown 裡送給 first responder
enum WsEditKeys {
    static var Command: Bool {
        guard let ev = NSApp.currentEvent, ev.type == .keyDown else { return false }
        return ev.modifierFlags.contains(.command)
    }
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

/// mac: FolderBrowserDialog → NSOpenPanel（只選資料夾、可以開新資料夾）；取消回 nil
enum WsDialogs {
    static func PickFolder(_ title: String, _ dir: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel()
        p.title = title; p.message = title
        p.canChooseFiles = false; p.canChooseDirectories = true; p.allowsMultipleSelection = false
        p.canCreateDirectories = true
        if !dir.isEmpty { p.directoryURL = URL(fileURLWithPath: dir, isDirectory: true) }
        p.level = .floating
        let r = p.runModal()
        Form._maybeDeactivate()
        if r != .OK { return nil }
        return p.url?.path
    }
}
