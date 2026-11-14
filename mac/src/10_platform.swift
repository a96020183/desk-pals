// Desk Pals（公仔櫃）：桌面上的像素公仔們（Spidey、小波、史迪仔、人魚漢頓…）。
// 獨立程式；一個 World 管全部：視窗掃描、公仔櫃、球、煙火、Claude／Codex 監看、pipe；0～4 隻公仔同時在桌面上跑。
// 角色＝Pal（資料：調色盤、像素圖、台詞、移動風格），新增角色＝加一個 Pal（＋需要的話加專屬動作）。
// 10_platform.swift — port of DeskPals.cs lines 1–581 (App, W, WinInfo, Plat, Client, OverlayForm, BubbleForm,
// BallForm, FxForm, FlashForm, CobwebForm, PetForm, MenuHost) + program entry (App.Main, called from 99_main.swift).
// mac: pipe → Unix domain socket（argv[1]），Win32 視窗 API → CGWindowList／AppKit，RegisterHotKey → Carbon。

import AppKit
import Carbon

enum App {
    static var logged = 0
    // 測試用：DESKPALS_OFFSCREEN=1 時所有視窗都不顯示，畫面改畫進虛擬螢幕（pipe 的 snap 指令存成 PNG）
    static let Offscreen = ProcessInfo.processInfo.environment["DESKPALS_OFFSCREEN"] == "1"
    // 測試用：離屏＋DESKPALS_ISOLATED=1 時不看真的視窗（不跳上你的視窗、你全螢幕也不會躲起來），截圖比較乾淨
    static let Isolated = Offscreen && ProcessInfo.processInfo.environment["DESKPALS_ISOLATED"] == "1"

    // mac: ~/Library/Logs/desk-pals.log
    static let LogPath: String = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/desk-pals.log")
    static let logLock = NSLock()
    static func Append(_ line: String) {
        logLock.lock(); defer { logLock.unlock() }
        guard let data = line.data(using: .utf8) else { return }
        if let fh = FileHandle(forWritingAtPath: LogPath) {
            fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
        } else {
            try? FileManager.default.createDirectory(atPath: (LogPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: LogPath, contents: data)
        }
    }
    static func Stamp(_ fmt: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = fmt
        return f.string(from: Date())
    }

    // 診斷用：不受行數上限限制
    static func LogAlways(_ s: String) {
        Append(Stamp("HH:mm:ss.SSS") + " " + s + "\n")
    }

    static func Log(_ s: String) {
        logLock.lock(); logged += 1; let n = logged; logLock.unlock()
        if n - 1 > 80 { return }
        Append(Stamp("yyyy-MM-dd'T'HH:mm:ss") + " " + s + "\n")
    }

    static func Run(_ pipeName: String, _ pet: String) { Run(pipeName, pet, "") }
    // lineup：classic（經典一櫃）／teletubbies（天線寶寶一櫃）；空白＝照上次的
    // mac: pipeName = Unix socket 路徑；單一執行個體用 socket 旁邊的 .lock 檔 flock（取代 Mutex）
    static var lockFd: Int32 = -1
    static func Run(_ pipeName: String, _ pet: String, _ lineup: String) {
        let lockPath = pipeName + ".lock"
        try? FileManager.default.createDirectory(atPath: (lockPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        if fd < 0 || flock(fd, LOCK_EX | LOCK_NB) != 0 { Log("already running"); if fd >= 0 { close(fd) }; return }
        lockFd = fd   // 一直開著到程式結束
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        NSSetUncaughtExceptionHandler { ex in App.LogAlways("ui: " + ex.name.rawValue + " " + (ex.reason ?? "")) }
        let w = World(pipeName, pet, lineup)
        w.Start()
        app.run()
    }

    // 開發用：把每個角色的各種姿勢畫成一張圖（不會開任何視窗）
    static func Preview(_ path: String, _ night: Bool) {
        Pet.PreviewSheet(path, night)
    }
    static func PreviewShelf(_ path: String, _ night: Bool) {
        Pet.PreviewShelf(path, night)
    }
    // 開發用：天線寶寶一櫃的各種姿勢
    static func PreviewTubbies(_ path: String, _ night: Bool) {
        Pet.PreviewTubbySheet(path, night)
    }

    // mac: 程式進入點（99_main.swift 呼叫）
    // DeskPals [socket] [pet] [lineup]
    // DeskPals --preview out.png [night] | --preview-shelf out.png [night] | --preview-tubbies out.png [night]
    static func Main() {
        signal(SIGPIPE, SIG_IGN)
        let a = CommandLine.arguments
        if a.count >= 3 && (a[1] == "--preview" || a[1] == "--preview-shelf" || a[1] == "--preview-tubbies") {
            let night = a.count >= 4 && (a[3] == "night" || a[3] == "1" || a[3].lowercased() == "true")
            if a[1] == "--preview" { Preview(a[2], night) }
            else if a[1] == "--preview-shelf" { PreviewShelf(a[2], night) }
            else { PreviewTubbies(a[2], night) }
            exit(0)
        }
        let def = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/SpideyDesktop/spidey.sock")
        let sock = a.count >= 2 && !a[1].isEmpty ? a[1] : def
        let pet = a.count >= 3 ? a[2] : ""
        let lineup = a.count >= 4 ? a[3] : ""
        Run(sock, pet, lineup)
    }
}

// Win32 視窗 API 的 mac 版：IntPtr 視窗代碼＝CGWindowID（kCGWindowNumber），座標＝全域左上角原點
enum W {
    typealias EnumProc = (IntPtr, IntPtr) -> Bool
    struct RECT { var L = 0, T = 0, R = 0, B = 0; init() { }; init(_ l: Int, _ t: Int, _ r: Int, _ b: Int) { L = l; T = t; R = r; B = b } }

    // ---- 視窗快照（CGWindowListCopyWindowInfo；EnumWindows 時更新，單一視窗查詢時 0.25 秒內直接用）
    final class Snap { var H: IntPtr = 0; var Pid = 0; var Owner = ""; var Name = ""; var L = 0, T = 0, R = 0, B = 0; var Layer = 0; var Alpha = 1.0; var OnScreen = true; var At = 0.0 }
    static var snaps: [IntPtr: Snap] = [:]
    static var order: [Snap] = []          // 最近一次 EnumWindows：由前到後
    static var orderAt = -1.0
    static let snapLock = NSLock()
    static func Now() -> Double { return ProcessInfo.processInfo.systemUptime }
    static func MakeSnap(_ info: [String: Any], _ at: Double) -> Snap? {
        let s = Snap()
        s.H = (info[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
        if s.H == 0 { return nil }
        s.Pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.intValue ?? 0
        s.Owner = (info[kCGWindowOwnerName as String] as? String) ?? ""
        s.Name = (info[kCGWindowName as String] as? String) ?? ""
        s.Layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        s.Alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        s.OnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        if let bd = info[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: bd as CFDictionary) {
            s.L = Int(r.minX.rounded()); s.T = Int(r.minY.rounded()); s.R = Int(r.maxX.rounded()); s.B = Int(r.maxY.rounded())
        }
        s.At = at
        return s
    }
    static func Info(_ h: IntPtr) -> Snap? {
        if h == 0 { return nil }
        let now = Now()
        snapLock.lock()
        if let s = snaps[h], now - s.At < 0.25 { snapLock.unlock(); return s.OnScreen ? s : nil }
        snapLock.unlock()
        guard let arr = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(UInt32(truncatingIfNeeded: h))) as? [[String: Any]],
              let info = arr.first, let s = MakeSnap(info, now) else {
            snapLock.lock(); snaps.removeValue(forKey: h); snapLock.unlock()
            return nil
        }
        snapLock.lock(); snaps[h] = s; snapLock.unlock()
        return s.OnScreen ? s : nil
    }
    static func Refresh() -> [Snap] {
        let now = Now()
        var out: [Snap] = []
        let myPid = Int(ProcessInfo.processInfo.processIdentifier)
        if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in list {
                guard let s = MakeSnap(info, now) else { continue }
                s.OnScreen = true
                if s.Pid == myPid || s.Layer != 0 || s.Alpha <= 0.01 { continue }
                out.append(s)
            }
        }
        snapLock.lock()
        for s in out { snaps[s.H] = s }
        if snaps.count > 2000 { snaps = snaps.filter { now - $0.value.At < 5 } }
        order = out; orderAt = now
        snapLock.unlock()
        return out
    }

    // 由前到後列舉別的 App 的一般視窗（layer 0、略過自己的 PID）
    @discardableResult static func EnumWindows(_ cb: EnumProc, _ l: IntPtr) -> Bool {
        for s in Refresh() { if !cb(s.H, l) { break } }
        return true
    }
    static func IsWindowVisible(_ h: IntPtr) -> Bool {
        if let f = Form._FromHandle(h) { return f.Visible }
        return Info(h) != nil
    }
    // mac: 縮到 Dock 的視窗不在畫面上 → IsWindowVisible 已經是 false
    static func IsIconic(_ h: IntPtr) -> Bool { return false }
    // 視窗樣式：自己的視窗照實際狀態回報 TOOLWINDOW/NOACTIVATE/TOPMOST/LAYERED/TRANSPARENT；別人的視窗回 0
    @discardableResult static func GetWindowLong(_ h: IntPtr, _ i: Int) -> Int {
        guard let f = Form._FromHandle(h) else { return 0 }
        if i == -20 {
            var ex = 0
            if !f._isDialog { ex |= 0x80 | 0x08000000 | 0x8 }
            if let p = f.panel, p.ignoresMouseEvents { ex |= 0x80000 | 0x20 }
            return ex
        }
        if i == -16 { return f._isDialog ? 0x00C00000 : 0 }
        return 0
    }
    // 只支援 GWL_EXSTYLE 的 WS_EX_TRANSPARENT（點得穿）→ ignoresMouseEvents
    @discardableResult static func SetWindowLong(_ h: IntPtr, _ i: Int, _ v: Int) -> Int {
        let old = GetWindowLong(h, i)
        if i == -20, let f = Form._FromHandle(h), let p = f.panel { p.ignoresMouseEvents = (v & 0x20) != 0 }
        return old
    }
    // mac: 自己的對話框 → 拉到前景、變成 key；別的 App 的視窗 → 啟動那個 App；看不見的小視窗（選單宿主）→ 不用搶焦點
    @discardableResult static func SetForegroundWindow(_ h: IntPtr) -> Bool {
        if let f = Form._FromHandle(h) {
            if !f._isDialog { return true }   // mac: NSMenu 不需要宿主視窗在前景
            f.Activate()
            return true
        }
        guard let s = Info(h), let app = NSRunningApplication(processIdentifier: pid_t(s.Pid)) else { return false }
        if #available(macOS 14.0, *) { NSApp.yieldActivation(to: app); return app.activate(options: []) }
        return app.activate(options: [])
    }
    @discardableResult static func BringWindowToTop(_ h: IntPtr) -> Bool {
        if let f = Form._FromHandle(h) { f.panel?.orderFrontRegardless(); return true }
        return false
    }
    @discardableResult static func AttachThreadInput(_ idAttach: Int, _ idAttachTo: Int, _ attach: Bool) -> Bool { return false }
    // mac: 沒有視窗訊息佇列，WM_NULL 之類不用送
    @discardableResult static func PostMessage(_ h: IntPtr, _ msg: Int, _ w: IntPtr, _ l: IntPtr) -> Bool { return true }
    static func GetCurrentThreadId() -> Int { return Int(pthread_mach_thread_np(pthread_self())) }

    // 我們的視窗都是「不搶焦點」的，選單、輸入框要先把自己拉到前景才會正常顯示／能打字
    @discardableResult static func ForceForeground(_ h: IntPtr) -> Bool {
        var ok = false
        let fg = GetForegroundWindow()
        var pid = 0
        let fgThread = fg == 0 ? 0 : GetWindowThreadProcessId(fg, &pid), me = GetCurrentThreadId()
        let att = fgThread != 0 && fgThread != me && AttachThreadInput(me, fgThread, true)
        ok = SetForegroundWindow(h)
        BringWindowToTop(h)
        if att { AttachThreadInput(me, fgThread, false) }
        let after = GetForegroundWindow()
        App.LogAlways("menu: ForceForeground set=" + (ok ? "True" : "False") + " attached=" + (att ? "True" : "False") + " fgAfter=" + (after == h ? "helper" : String(after, radix: 16, uppercase: true)))
        return ok
    }

    // ---- 原生選單（TrackPopupMenuEx）→ NSMenu.popUp（同步，回傳選到的 id，沒選＝0）
    final class MenuTarget: NSObject {
        var cmd = 0
        @objc func pick(_ sender: NSMenuItem) { cmd = sender.tag }
    }
    static var menus: [IntPtr: NSMenu] = [:]
    static var nextMenu: IntPtr = 0x4D00
    static let menuTarget = MenuTarget()
    static func CreatePopupMenu() -> IntPtr {
        nextMenu += 1
        let m = NSMenu()
        m.autoenablesItems = false
        menus[nextMenu] = m
        return nextMenu
    }
    // flags：MF_GRAYED 0x1、MF_CHECKED 0x8、MF_POPUP 0x10（id＝子選單）、MF_SEPARATOR 0x800
    @discardableResult static func AppendMenu(_ hMenu: IntPtr, _ flags: Int, _ id: IntPtr, _ text: String?) -> Bool {
        guard let m = menus[hMenu] else { return false }
        if flags & 0x0800 != 0 { m.addItem(NSMenuItem.separator()); return true }
        let t = (text ?? "").replacingOccurrences(of: "&&", with: "\u{1}").replacingOccurrences(of: "&", with: "").replacingOccurrences(of: "\u{1}", with: "&")
        let it = NSMenuItem(title: t, action: nil, keyEquivalent: "")
        it.isEnabled = flags & 0x0001 == 0 && flags & 0x0002 == 0
        if flags & 0x0008 != 0 { it.state = .on }
        if flags & 0x0010 != 0 {
            it.submenu = menus[id]
        } else {
            it.tag = id
            it.target = menuTarget
            it.action = #selector(MenuTarget.pick(_:))
        }
        m.addItem(it)
        return true
    }
    // x, y：全域左上角座標；TPM_RIGHTALIGN 0x8／TPM_BOTTOMALIGN 0x20 照 Windows 對齊；回傳選到的 id
    static func TrackPopupMenuEx(_ hMenu: IntPtr, _ flags: Int, _ x: Int, _ y: Int, _ hwnd: IntPtr, _ tpm: IntPtr) -> Int {
        guard let m = menus[hMenu] else { return 0 }
        if !Foundation.Thread.isMainThread { var r = 0; DispatchQueue.main.sync { r = TrackPopupMenuEx(hMenu, flags, x, y, hwnd, tpm) }; return r }
        menuTarget.cmd = 0
        var loc = _Coords.pointToCocoa(x, y)
        let sz = m.size
        if flags & 0x0008 != 0 { loc.x -= sz.width }
        if flags & 0x0020 != 0 { loc.y += sz.height }
        m.popUp(positioning: nil, at: loc, in: nil)
        let c = menuTarget.cmd
        menuTarget.cmd = 0
        return c
    }
    @discardableResult static func DestroyMenu(_ hMenu: IntPtr) -> Bool {
        guard let m = menus.removeValue(forKey: hMenu) else { return false }
        for it in m.items { if let sm = it.submenu, let k = menus.first(where: { $0.value === sm })?.key { _ = DestroyMenu(k) } }
        return true
    }

    static func GetWindowTextLength(_ h: IntPtr) -> Int { return GetText(h).count }
    // mac: 標題（kCGWindowName）沒有「螢幕錄影」權限時是空的 → 用 App 名字代替（不然候選視窗全都沒標題）
    static func GetText(_ h: IntPtr) -> String {
        if let f = Form._FromHandle(h) { return f.Text }
        guard let s = Info(h) else { return "" }
        return s.Name.isEmpty ? s.Owner : s.Name
    }
    @discardableResult static func GetWindowRect(_ h: IntPtr, _ r: inout RECT) -> Bool {
        if let f = Form._FromHandle(h) { r = RECT(f.Left, f.Top, f.Left + f.Width, f.Top + f.Height); return true }
        guard let s = Info(h) else { return false }
        r = RECT(s.L, s.T, s.R, s.B)
        return true
    }
    // 前景視窗：自己是前景 App → 自己的 key window；否則前景 App 最前面的 layer 0 視窗
    static func GetForegroundWindow() -> IntPtr {
        if NSApp != nil && NSApp.isActive, let k = NSApp.keyWindow { return k.windowNumber }
        guard let front = NSWorkspace.shared.frontmostApplication else { return 0 }
        let pid = Int(front.processIdentifier)
        if pid == Int(ProcessInfo.processInfo.processIdentifier) { return NSApp?.keyWindow?.windowNumber ?? 0 }
        snapLock.lock()
        let fresh = Now() - orderAt < 0.5
        let cur = order
        snapLock.unlock()
        for s in (fresh ? cur : Refresh()) where s.Pid == pid { return s.H }
        return 0
    }
    // mac: 沒有視窗類別 → App 名字（Finder 的桌面不在清單裡）
    @discardableResult static func GetClassName(_ h: IntPtr, _ sb: StringBuilder, _ n: Int) -> Int {
        var s = ""
        if Form._FromHandle(h) != nil { s = "WindowsForms10.Window" } else if let i = Info(h) { s = i.Owner }
        if s.count > n - 1 { s = String(s.prefix(max(0, n - 1))) }
        sb.Clear(); sb.Append(s)
        return s.count
    }
    // 回傳值：「執行緒 id」（mac：非 0 的假值），pid：擁有者 PID
    @discardableResult static func GetWindowThreadProcessId(_ h: IntPtr, _ pid: inout Int) -> Int {
        if Form._FromHandle(h) != nil { pid = Int(ProcessInfo.processInfo.processIdentifier); return GetCurrentThreadId() }
        guard let s = Info(h) else { pid = 0; return 0 }
        pid = s.Pid
        return s.Pid + 1
    }
    @discardableResult static func GetWindowText(_ h: IntPtr, _ sb: StringBuilder, _ n: Int) -> Int {
        var s = GetText(h)
        if s.count > n - 1 { s = String(s.prefix(max(0, n - 1))) }
        sb.Clear(); sb.Append(s)
        return s.count
    }

    // ---- 快速鍵（RegisterHotKey → Carbon RegisterEventHotKey）
    // mods：MOD_ALT 1 → ⌥、MOD_CONTROL 2 → ⌃、MOD_SHIFT 4 → ⇧、MOD_WIN 8 → ⌘；vk：A–Z／0–9
    // 按下時：有設 W.OnHotKey 就呼叫它(id)；沒有就把 WM_HOTKEY（0x0312，WParam＝id）送到註冊時那個 Form 的 WndProc。
    static var OnHotKey: ((Int) -> Void)? = nil
    static var hotKeyForms: [Int: Form.WeakForm] = [:]
    static var hotKeyRefs: [Int: EventHotKeyRef] = [:]
    static var hotKeyHandler: EventHandlerRef? = nil
    static let HotKeySig: OSType = 0x4450_4B57   // 'DPKW'
    static func VkToMac(_ vk: Int) -> Int {
        let letters: [Int] = [kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I,
                              kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R,
                              kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z]
        let digits: [Int] = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        if vk >= 0x41 && vk <= 0x5A { return letters[vk - 0x41] }
        if vk >= 0x30 && vk <= 0x39 { return digits[vk - 0x30] }
        if vk == 0x20 { return kVK_Space }
        return -1
    }
    static func HotKeyFired(_ id: Int) {
        if let cb = OnHotKey { cb(id); return }
        guard let f = hotKeyForms[id]?.f else { return }
        var m = Message(f.panel?.windowNumber ?? 0, 0x0312, id, 0)
        f.WndProc(&m)
    }
    @discardableResult static func RegisterHotKey(_ h: IntPtr, _ id: Int, _ mods: Int, _ vk: Int) -> Bool {
        let key = VkToMac(vk)
        if key < 0 { return false }
        if hotKeyHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let st = InstallEventHandler(GetApplicationEventTarget(), { (_, ev, _) -> OSStatus in
                var hk = EventHotKeyID()
                guard let e = ev else { return OSStatus(eventNotHandledErr) }
                let r = GetEventParameter(e, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &hk)
                if r != OSStatus(noErr) || hk.signature != W.HotKeySig { return OSStatus(eventNotHandledErr) }
                let id = Int(hk.id)
                DispatchQueue.main.async { W.HotKeyFired(id) }
                return OSStatus(noErr)
            }, 1, &spec, nil, &hotKeyHandler)
            if st != OSStatus(noErr) { App.Log("hotkey handler install failed " + String(st)); return false }
        }
        var cm = 0
        if mods & 1 != 0 { cm |= optionKey }
        if mods & 2 != 0 { cm |= controlKey }
        if mods & 4 != 0 { cm |= shiftKey }
        if mods & 8 != 0 { cm |= cmdKey }
        if let old = hotKeyRefs.removeValue(forKey: id) { UnregisterEventHotKey(old) }
        var ref: EventHotKeyRef? = nil
        let st = RegisterEventHotKey(UInt32(key), UInt32(cm), EventHotKeyID(signature: HotKeySig, id: UInt32(id)), GetApplicationEventTarget(), OptionBits(0), &ref)
        if st != OSStatus(noErr) || ref == nil { return false }
        hotKeyRefs[id] = ref!
        if let f = Form._FromHandle(h) { hotKeyForms[id] = Form.WeakForm(f) }
        return true
    }
    @discardableResult static func UnregisterHotKey(_ h: IntPtr, _ id: Int) -> Bool {
        guard let r = hotKeyRefs.removeValue(forKey: id) else { return false }
        UnregisterEventHotKey(r); hotKeyForms.removeValue(forKey: id)
        return true
    }

    // 自己的視窗：SWP_NOMOVE/NOSIZE 以外就移動／改大小；after＝TOPMOST → 拉到最上面
    @discardableResult static func SetWindowPos(_ h: IntPtr, _ after: IntPtr, _ x: Int, _ y: Int, _ cx: Int, _ cy: Int, _ f: Int) -> Bool {
        guard let fm = Form._FromHandle(h) else { return false }
        let nomove = f & Int(NOMOVE) != 0, nosize = f & Int(NOSIZE) != 0
        if !nomove || !nosize { fm.SetBounds(nomove ? fm.Left : x, nomove ? fm.Top : y, nosize ? fm.Width : cx, nosize ? fm.Height : cy) }
        if after == TOPMOST && f & 0x0004 == 0 { fm.panel?.orderFrontRegardless() }
        return true
    }
    // mac: DWM 沒有；回傳非 0（失敗）→ 呼叫端改用 GetWindowRect／當作沒被隱藏
    static func DwmGetWindowAttribute(_ h: IntPtr, _ a: Int, _ r: inout RECT, _ n: Int) -> Int {
        if a == 9 && GetWindowRect(h, &r) { return 0 }
        return 1
    }
    static func DwmGetWindowAttribute(_ h: IntPtr, _ a: Int, _ v: inout Int, _ n: Int) -> Int { v = 0; return 1 }

    // 系統閒置秒數（整台電腦最後一次鍵盤／滑鼠）
    static func IdleSeconds() -> Double {
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
    struct POINT { var X = 0, Y = 0; init() { }; init(_ x: Int, _ y: Int) { X = x; Y = y } }
    struct SIZE { var CX = 0, CY = 0; init() { }; init(_ cx: Int, _ cy: Int) { CX = cx; CY = cy } }

    // 一次完成「移動＋改大小＋換畫面」，不會有拉伸的中間畫面
    // mac: 視窗內容換成這張圖（layer.contents，Retina 用 Bitmap 的倍率），移動＋改大小在同一個 CATransaction
    static func Present(_ f: Form, _ bmp: Bitmap, _ x: Int, _ y: Int) {
        if App.Offscreen {
            if let o = f as? OverlayForm { if o.VBmp != nil { o.VBmp.Dispose() }; o.VBmp = _formsCloneBitmap(bmp); o.VPos = Point(x, y) }
            return
        }
        if !Foundation.Thread.isMainThread { DispatchQueue.main.sync { Present(f, bmp, x, y) }; return }
        let img = _formsCGImage(bmp)
        if img == nil { App.Log("ULW failed size=" + String(bmp.Width) + "x" + String(bmp.Height)) }
        f._present(img, _formsBitmapScale(bmp), x, y, bmp.Width, bmp.Height)
    }
    static let TOPMOST: IntPtr = -1
    static let NOSIZE = 1, NOMOVE = 2, NOACTIVATE = 0x10

    @discardableResult static func Rect(_ h: IntPtr, _ r: inout RECT) -> Bool {
        if DwmGetWindowAttribute(h, 9, &r, 16) == 0 { return true } // DWMWA_EXTENDED_FRAME_BOUNDS
        return GetWindowRect(h, &r)
    }
    static var SuspendZ = false    // 原生選單開著時不要把我們的視窗拉到最上面（會蓋住選單）
    static func KeepOnTop(_ f: Form?) {
        if SuspendZ { return }
        if let f = f, f.IsHandleCreated && f.Visible { f.panel?.orderFrontRegardless() }
    }
    // 有沒有在顯示（離屏測試模式看虛擬旗標）
    static func Shown(_ f: Form?) -> Bool {
        guard let f = f else { return false }
        let o = f as? OverlayForm
        return App.Offscreen && o != nil ? o!.VVisible : f.Visible
    }
}

class WinInfo { var H: IntPtr = 0; var L = 0, T = 0, R = 0, B = 0, Z = 0 }
class Plat { var H: IntPtr = 0; var Top = 0, Left = 0, Right = 0, WinLeft = 0 }
// mac: NamedPipeServerStream → 已連線的 Unix socket（fd）
class Client { var S: Int32 = -1; var Fd: Int32 { get { return S } set { S = newValue } } }

// 透明、不搶焦點、永遠在最上層的小視窗共同設定
class OverlayForm: Form {
    static let KEY = Color.FromArgb(255, 0, 255)
    var KEY: Color { return OverlayForm.KEY }   // mac: 子類別裡可以直接寫 KEY
    let clickThrough: Bool, perPixel: Bool
    init(_ clickThrough: Bool) {
        self.clickThrough = clickThrough
        self.perPixel = false
        super.init()
        Setup()
    }
    init(_ clickThrough: Bool, _ perPixel: Bool) {
        self.clickThrough = clickThrough
        self.perPixel = perPixel
        super.init()
        Setup()
    }
    func Setup() {
        FormBorderStyle = FormBorderStyleT.None
        ShowInTaskbar = false
        TopMost = true
        StartPosition = FormStartPosition.Manual
        if !perPixel { BackColor = OverlayForm.KEY; TransparencyKey = OverlayForm.KEY }
        SetStyle([ControlStyles.OptimizedDoubleBuffer, ControlStyles.AllPaintingInWmPaint, ControlStyles.UserPaint], true)
    }
    override var ShowWithoutActivation: Bool { return true }
    // 現在要不要點得穿（泡泡有通知可以點時會關掉）；視窗重建時也照這個
    var ClickThroughNow: Bool { return true }
    // mac: 取代 CreateParams 的 WS_EX_TRANSPARENT → ignoresMouseEvents（點得到的視窗：透明像素本來就點得穿）
    override var _wantsClickThrough: Bool { return clickThrough && ClickThroughNow }

    // ---- 離屏測試模式：永遠不真的顯示，只記住「應該要顯示」 ----
    var VVisible = false
    var VBmp: Bitmap! = nil
    var VPos = Point(0, 0)
    override func SetVisibleCore(_ value: Bool) {
        if App.Offscreen { VVisible = value; super.SetVisibleCore(false); return }
        super.SetVisibleCore(value)
    }
    // 把自己（非逐像素的那種）畫到虛擬螢幕上
    func PaintTo(_ g: Graphics) {
        if Width <= 0 || Height <= 0 { return }
        // mac: KEY 色畫上去就是透明，不用 MakeTransparent
        let b = Bitmap(Width, Height)
        do { let gg = Graphics.FromImage(b); OnPaint(PaintEventArgs(gg, Rectangle(0, 0, Width, Height))) }
        if Opacity < 0.999 {
            let cm = ColorMatrix(); cm.Matrix33 = Opacity
            do { let ia = ImageAttributes(); ia.SetColorMatrix(cm); g.DrawImage(b, Rectangle(Left, Top, Width, Height), 0, 0, Width, Height, GraphicsUnit.Pixel, ia) }
        }
        else { g.DrawImageUnscaled(b, Left, Top) }
    }
}

// 對話泡泡。theme：0 白天、1 黑化（Spidey）、2 夕陽（小波）、3 夜空（史迪仔）、4 燭光（人魚漢頓）
class BubbleForm: OverlayForm {
    lazy var font = Font("Microsoft JhengHei UI", 10, FontStyle.Bold)
    lazy var hintFont = Font("Microsoft JhengHei UI", 9, FontStyle.Bold)
    var text = "", hint: String? = nil
    var alert = false
    var theme = 0, hintH = 0
    var accent = Color.FromArgb(0x2A, 0x2F, 0x45)
    var owner: Pet! = nil
    var clickable = false
    init(_ accent: Color) { super.init(true); self.accent = accent }

    func Measure(_ s: String, _ a: Bool, _ th: Int, _ h: String?) -> Size {
        if s != text || a != alert || th != theme || h != hint { text = s; alert = a; theme = th; hint = h; Invalidate() }
        let ts = TextRenderer.MeasureText(s, font, Size(4000, 400), TextFormatFlags.NoPadding)
        hintH = 0
        var wd = ts.Width
        if !string.IsNullOrEmpty(h) {
            let hs = TextRenderer.MeasureText(h!, hintFont, Size(4000, 400), TextFormatFlags.NoPadding)
            hintH = hs.Height + 2; wd = Math.Max(wd, hs.Width + hs.Height + 2)
        }
        return Size(wd + 22, ts.Height + hintH + 12 + 7)
    }

    // 有通知可以點的時候，泡泡不再點得穿（點了＝打開連結）
    override var ClickThroughNow: Bool { return !clickable }
    func SetClickable(_ on: Bool, _ p: Pet!) {
        owner = p
        clickable = on
        Cursor = on ? Cursors.Hand : Cursors.Default
        if !IsHandleCreated { return }          // 還沒建立：建立時 CreateParams 會照 clickable 設
        let ex = W.GetWindowLong(Handle, -20)
        let want = on ? (ex & ~0x20) : (ex | 0x20)
        if want != ex {
            W.SetWindowLong(Handle, -20, want)
            W.SetWindowPos(Handle, 0, 0, 0, 0, 0, W.NOSIZE | W.NOMOVE | W.NOACTIVATE | 0x0004 | 0x0020) // NOZORDER | FRAMECHANGED
        }
        if on { W.KeepOnTop(self) }
    }
    override func OnMouseDown(_ e: MouseEventArgs) {
        super.OnMouseDown(e)
        if clickable && owner != nil && e.Button == MouseButtons.Left { owner.Clicked() }
    }

    static func C(_ rgb: Int) -> Color { return Color.FromArgb((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255) }

    override func OnPaint(_ e: PaintEventArgs) {
        let C = BubbleForm.C
        let g = e.Graphics
        g.Clear(KEY)
        let w = ClientSize.Width, h = ClientSize.Height - 7
        var line: Color, fg: Color, bg: Color
        switch theme {
        case 1: line = C(0x7B6BC4); fg = C(0xEEEBF8); bg = C(0x16171F)
        case 2: line = C(0xE8935A); fg = C(0xFFEBD9); bg = C(0x3B2335)
        case 3: line = C(0x6FA8E8); fg = C(0xE4F0FF); bg = C(0x14203A)
        case 4: line = C(0xD9A050); fg = C(0xFFF1D6); bg = C(0x2E2418)
        default: line = accent; fg = C(0x2A2F45); bg = Color.White
        }
        if alert { line = C(0xC95454); fg = theme == 0 ? C(0xA83232) : C(0xFF8A8A) }
        do {
            let lb = SolidBrush(line)
            let fill = SolidBrush(bg)
            // 像素風方框（切角）＋往下的小尾巴
            g.FillRectangle(lb, 2, 0, w - 4, h)
            g.FillRectangle(lb, 0, 2, w, h - 4)
            g.FillRectangle(lb, 1, 1, w - 2, h - 2)
            g.FillRectangle(fill, 3, 2, w - 6, h - 4)
            g.FillRectangle(fill, 2, 3, w - 4, h - 6)
            let cx = w / 2
            for i in 0..<7 { g.FillRectangle(lb, cx - 7 + i, h - 2 + i, 14 - 2 * i, 1) }
            for i in 0..<5 { g.FillRectangle(fill, cx - 5 + i, h - 2 + i, 10 - 2 * i, 1) }
        }
        if text.IndexOf("\n") >= 0 {
            TextRenderer.DrawText(g, text, font, Rectangle(0, 6, w, h - hintH - 6), fg, [TextFormatFlags.HorizontalCenter, TextFormatFlags.NoPadding])
        } else {
            TextRenderer.DrawText(g, text, font, Rectangle(0, 0, w, h - hintH), fg,
                [TextFormatFlags.HorizontalCenter, TextFormatFlags.VerticalCenter, TextFormatFlags.NoPadding])
        }
        if hintH > 0 {
            // 小小的「↗」連結圖示（自己畫，不靠 emoji 字型）＋提示字
            let hint = self.hint ?? ""
            let hc = theme == 0 ? Color.FromArgb(0x3D, 0x7B, 0xD9) : Color.FromArgb(0x9F, 0xC8, 0xFF)
            let hs = TextRenderer.MeasureText(hint, hintFont, Size(4000, 400), TextFormatFlags.NoPadding)
            let ic = Math.Max(7, hs.Height - 4), tw = ic + 4 + hs.Width, x0 = (w - tw) / 2, y0 = h - hintH - 5 + (hintH - ic) / 2
            do {
                let p = Pen(hc, Math.Max(1.4, Double(ic) / 6.0))
                g.DrawRectangle(p, x0, y0 + ic / 3, ic * 2 / 3, ic * 2 / 3)
                g.DrawLine(p, x0 + ic / 3, y0 + ic * 2 / 3, x0 + ic, y0)
                g.DrawLine(p, x0 + ic / 2, y0, x0 + ic, y0)
                g.DrawLine(p, x0 + ic, y0, x0 + ic, y0 + ic / 2)
            }
            TextRenderer.DrawText(g, hint, hintFont, Point(x0 + ic + 4, h - hintH - 5 + (hintH - hs.Height) / 2), hc, TextFormatFlags.NoPadding)
        }
    }
}

// 球（點得到：點一下就把球丟出去）。kind：tennis／baseball
class BallForm: OverlayForm {
    var Kicked: (() -> Void)? = nil
    let ps: Int
    var kind = "tennis"
    static let TENNIS: [String] = ["..kkkk..", ".kTTTTk.", "kTTWTTTk", "kTWTTTTk", "kTTTTWTk", "kTTTWTTk", ".kTTTTk.", "..kkkk.."]
    static let BASEBALL: [String] = ["..gggg..", ".gWWWWg.", "gRWWWWRg", "gWRWWRWg", "gWRWWRWg", "gRWWWWRg", ".gWWWWg.", "..gggg.."]
    static let TUBBYBALL: [String] = ["..kkkk..", ".kOOYOk.", "kOYOOOOk", "kOOOOOok", "kOOOOOok", "kOOOOook", ".kooook.", "..kkkk.."]   // 天線寶寶的大橘球
    let bk = SolidBrush(Color.FromArgb(0x2A, 0x2F, 0x45)), bt = SolidBrush(Color.FromArgb(0xD9, 0xE8, 0x4A)), bw = SolidBrush(Color.White),
        bg = SolidBrush(Color.FromArgb(0x8A, 0x90, 0xA0)), brd = SolidBrush(Color.FromArgb(0xE0, 0x3A, 0x3A)),
        bo = SolidBrush(Color.FromArgb(0xF2, 0x85, 0x2A)), bod = SolidBrush(Color.FromArgb(0xC2, 0x5E, 0x14)), byl = SolidBrush(Color.FromArgb(0xFF, 0xD8, 0x4A))
    init(_ ps: Int) { self.ps = ps; super.init(false); Size = Size(8 * ps, 8 * ps) }
    var Kind: String { get { return kind } set { if kind != newValue { kind = newValue; Invalidate() } } }
    static func Art(_ kind: String) -> [String] { return kind == "baseball" ? BASEBALL : (kind == "tubby" ? TUBBYBALL : TENNIS) }
    override func OnPaint(_ e: PaintEventArgs) {
        let g = e.Graphics
        g.Clear(KEY)
        let art = BallForm.Art(kind)
        for r in 0..<8 {
            let row = Array(art[r])
            for i in 0..<8 {
                let c = row[i]
                if c == "." { continue }
                let b = c == "k" ? bk : (c == "T" ? bt : (c == "g" ? bg : (c == "R" ? brd : (c == "O" ? bo : (c == "o" ? bod : (c == "Y" ? byl : bw))))))
                g.FillRectangle(b, i * ps, r * ps, ps, ps)
            }
        }
    }
    override func OnMouseDown(_ e: MouseEventArgs) {
        super.OnMouseDown(e)
        if e.Button == MouseButtons.Left && Kicked != nil { Kicked!() }
    }
}

// 煙火（蓋住一整個螢幕、點得穿）
class FxForm: OverlayForm {
    let parts = List<Arr<Double>>() // x, y, vx, vy, 年齡, 壽命, 顏色, 種類(0 火箭 / 1 火花)
    let plan = List<Arr<Double>>()  // 時間, x, 目標 y, 顏色
    let k: Double
    let rnd = Random()
    let cols: [SolidBrush]
    var t = 0.0
    var Active = false

    init(_ k: Double) {
        self.k = k
        let rgb: [Int] = [0xFF5A5A, 0xFFD84A, 0x5AD1FF, 0xFF8FD8, 0x8CFF8C, 0xFFA64A]
        var cs: [SolidBrush] = []
        for i in 0..<rgb.count { cs.append(SolidBrush(Color.FromArgb((rgb[i] >> 16) & 255, (rgb[i] >> 8) & 255, rgb[i] & 255))) }
        cols = cs
        super.init(true)
    }

    func R(_ a: Double, _ b: Double) -> Double { return a + rnd.NextDouble() * (b - a) }

    // n 發；focusX ≥ 0 時集中在那附近（小煙火）
    func Start(_ area: Rectangle, _ n: Int, _ focusX: Int) {
        if !Active || Bounds != area { Bounds = area; parts.Clear(); plan.Clear(); t = 0 }
        Active = true
        var i = 0
        while i < n {
            let fx: Double = focusX >= 0 ? Math.Max(30.0, Math.Min(Double(area.Width - 30), Double(focusX - area.Left) + R(-160, 160) * k)) : R(0.12, 0.88) * Double(area.Width)
            let ty: Double = (focusX >= 0 ? R(0.35, 0.6) : R(0.12, 0.45)) * Double(area.Height)
            plan.Add(Arr<Double>([t + 0.32 * Double(i) + R(0, 0.2), fx, ty, Double(rnd.Next(cols.count))]))
            i += 1
        }
        if !Visible { Show() }
    }

    func Step(_ dt: Double) {
        if !Active { return }
        t += dt
        let h = Double(Height)
        var i = plan.Count - 1
        while i >= 0 {
            let q = plan[i]
            if t < q[0] { i -= 1; continue }
            parts.Add(Arr<Double>([q[1], h, 0, -(h - q[2]) / 0.45, 0, 0.45, q[3], 0]))
            plan.RemoveAt(i)
            i -= 1
        }
        i = parts.Count - 1
        while i >= 0 {
            let p = parts[i]
            p[4] += dt
            if p[7] == 0 {
                p[1] += p[3] * dt
                if p[4] >= p[5] {
                    let n = 40
                    for j in 0..<n {
                        let a = Math.PI * 2 * Double(j) / Double(n) + R(-0.1, 0.1), sp = R(170, 380) * k
                        let col: Double = rnd.NextDouble() < 0.7 ? p[6] : Double(rnd.Next(cols.count))
                        parts.Add(Arr<Double>([p[0], p[1], Math.Cos(a) * sp, Math.Sin(a) * sp, 0, R(0.7, 1.15), col, 1]))
                    }
                    parts.RemoveAt(i)
                }
            } else {
                p[3] += 260 * k * dt
                p[2] *= Math.Pow(0.35, dt); p[3] *= Math.Pow(0.6, dt)
                p[0] += p[2] * dt; p[1] += p[3] * dt
                if p[4] > p[5] { parts.RemoveAt(i) }
            }
            i -= 1
        }
        if plan.Count == 0 && parts.Count == 0 { Active = false; Hide(); return }
        Invalidate()
    }

    func Stop() { Active = false; plan.Clear(); parts.Clear(); Hide() }

    override func OnPaint(_ e: PaintEventArgs) {
        let g = e.Graphics
        g.Clear(KEY)
        for p in parts {
            let fading = p[7] == 1 && p[4] > p[5] * 0.7
            if fading && Math.Floor(p[4] * 24).truncatingRemainder(dividingBy: 2) == 0 { continue }
            let q = CInt(Math.Max(2.0, (p[7] == 0 || p[4] < p[5] * 0.45 ? 2.4 : 1.5) * k))
            let px = CInt(p[0]), py = CInt(p[1])
            let b = cols[CInt(p[6])]
            g.FillRectangle(b, px - q / 2, py - q / 2 - q, q, 3 * q)
            g.FillRectangle(b, px - q / 2 - q, py - q / 2, 3 * q, q)
        }
    }
}

// 大合照的閃光（點得穿、半透明白）
class FlashForm: OverlayForm {
    init() { super.init(true); BackColor = Color.White; TransparencyKey = Color.Empty; Opacity = 0 }
}

// 黏在視窗角落的小蜘蛛網
class CobwebForm: OverlayForm {
    let H: IntPtr
    let RightCorner: Bool
    let Born: Double
    let Side: Int
    let lw: Int

    init(_ h: IntPtr, _ right: Bool, _ side: Int, _ lw: Int, _ born: Double) {
        H = h; RightCorner = right; Side = side; self.lw = lw; Born = born
        super.init(true)
        Size = Size(side, side)
    }

    override func OnPaint(_ e: PaintEventArgs) {
        let g = e.Graphics
        g.Clear(KEY)
        let s = Side
        let ox: Double = RightCorner ? Double(s - 1) : 0, sx: Double = RightCorner ? -1 : 1
        let spokes = 5
        let rings: [Double] = [0.32, 0.58, 0.84]
        do {
            let p = Pen(Color.FromArgb(0x8E, 0x97, 0xB0), Double(lw))
            var pts = [[PointF]](repeating: [PointF](repeating: PointF(0, 0), count: rings.count), count: spokes)
            for i in 0..<spokes {
                let a = Math.PI / 2 * Double(i) / Double(spokes - 1)
                let dx = Math.Cos(a), dy = Math.Sin(a)
                let len = Double(s - lw - 1)
                g.DrawLine(p, ox, 0.0, ox + sx * dx * len, dy * len)
                for j in 0..<rings.count {
                    pts[i][j] = PointF(ox + sx * dx * len * rings[j], dy * len * rings[j])
                }
            }
            for j in 0..<rings.count {
                var i = 0
                while i + 1 < spokes {
                    let a = pts[i][j], b = pts[i + 1][j]
                    let mx: Double = (a.X + b.X) / 2 + (ox - (a.X + b.X) / 2) * 0.12
                    let my: Double = (a.Y + b.Y) / 2 * 0.88
                    let m = PointF(mx, my)
                    g.DrawLine(p, a, m)
                    g.DrawLine(p, m, b)
                    i += 1
                }
            }
        }
    }
}

// 公仔本體的視窗：畫面由 Pet 用 UpdateLayeredWindow 提供；滑鼠事件轉給 Pet
class PetForm: OverlayForm {
    let pet: Pet
    init(_ pet: Pet) { self.pet = pet; super.init(false, true) }
    override func OnPaint(_ e: PaintEventArgs) { }
    override func OnPaintBackground(_ e: PaintEventArgs) { }
    override func OnMouseDown(_ e: MouseEventArgs) { super.OnMouseDown(e); pet.MouseDown(e) }
    override func OnMouseUp(_ e: MouseEventArgs) {
        super.OnMouseUp(e)
        if e.Button == MouseButtons.Right {
            let c: Point = Cursor.Position
            let id: String = pet.P.Id ?? ""
            let at: String = "{X=" + String(c.X) + ",Y=" + String(c.Y) + "}"
            App.LogAlways("menu: right-up on pet " + id + " at " + at)
        }
        pet.MouseUp(e)
    }
}

// 選單的「宿主」：一個看不見、但可以變成前景的小視窗（不然從背景程式叫出來的選單會馬上關掉）
// mac: NSMenu 不需要宿主；留著讓 World 的程式照搬（Opacity 0、在螢幕外）
class MenuHost: Form {
    override init() {
        super.init()
        FormBorderStyle = FormBorderStyleT.None; ShowInTaskbar = false; StartPosition = FormStartPosition.Manual
        Location = Point(-32000, -32000); Size = Size(1, 1); Opacity = 0
    }
}

// ================= 角色資料（Pal）=================
// 每個角色：id、名字、調色盤（白天／夜晚）、像素圖零件、台詞、移動風格、夜晚風格、球種、配件錨點。
// 像素圖是 12 格寬（也可以更寬，會置中）× 16 格高的字元格；'.' 是透明。
// 共用字元：k 外框、p 愛心粉、y 星星黃、w 白；配件用 S W Y P B（每個角色都會有）。
