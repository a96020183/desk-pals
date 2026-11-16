// 95_standalone.swift — 獨立版 Desk Pals.app（不用 VS Code）的開場：只有從 .app 包裡跑的時候才做事，
// VS Code 擴充套件編出來的那支（desk-pals.sh）、CI 的離屏測試（DESKPALS_OFFSCREEN=1）都不受影響。
//   ・已經開著：叫它出來打個招呼就結束（不會開兩個）
//   ・寫 ~/Library/Application Support/DeskPals/standalone.json：VS Code 擴充套件看到就不再自己編一份、不建開機啟動，只負責連上
//   ・開機自動啟動：~/Library/LaunchAgents/local.desk-pals.plist（跟擴充套件同一個 Label → 直接換成 .app 版，不會開兩次）
//     擴充套件那份還開著的話先請它收工，再換這個上來
//   ・還在「下載項目」／DMG 裡直接打開（App Translocation）：提醒先拖進「應用程式」，這次不設開機啟動
//   ・在 Finder／Launchpad 再點一次：叫公仔打招呼
// 由 99_main.swift 在 App.Main() 之前呼叫。
import AppKit
import Carbon

enum Standalone {
    static let Label = "local.desk-pals"
    static var home: String { return NSHomeDirectory() + "/Library/Application Support/DeskPals" }
    static var reopen: ReopenHandler? = nil

    static func Prepare() {
        let bundle = Bundle.main.bundlePath
        if !bundle.hasSuffix(".app") || App.Offscreen { return }
        let a = CommandLine.arguments   // （macOS 13 以後 Finder 不會再帶 -psn_ 參數）
        if a.count >= 2 && a[1].hasPrefix("--") { return }   // --preview 之類的開發用指令
        let sock = a.count >= 2 && !a[1].isEmpty ? a[1] : home + "/desk-pals.sock"
        let exe = Bundle.main.executablePath ?? (bundle + "/Contents/MacOS/DeskPals")
        let translocated = bundle.contains("/AppTranslocation/") || bundle.hasPrefix("/Volumes/")
        var tookOver = false
        if !translocated {
            WriteMarker(bundle, exe)
            CopyHooks()
            tookOver = EnsureLaunchAgent(exe)
        }
        if Send(sock, "act hi") {
            if !tookOver { exit(0) }
            // 擴充套件編的那份還開著：請它收工，換 .app 版上來
            _ = Send(sock, "quit")
            WaitUnlocked(sock + ".lock", 10)
        }
        if translocated { AskToMove() }
        reopen = ReopenHandler(sock)
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in reopen?.Install() }
    }

    static func WriteMarker(_ bundle: String, _ exe: String) {
        let ver = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
        let j: [String: String] = ["kind": "app", "app": bundle, "exe": exe, "version": ver]
        guard let data = try? JSONSerialization.data(withJSONObject: j, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: home + "/standalone.json"))
    }

    // Claude Code hooks 的設定指著 DeskPals/claude-hook.js（Mac安裝說明這樣寫）：放一份過去
    static func CopyHooks() {
        for f in ["claude-hook.js", "ci-watch.js"] {
            guard let from = Bundle.main.path(forResource: (f as NSString).deletingPathExtension, ofType: "js"),
                  let a = FileManager.default.contents(atPath: from) else { continue }
            let to = home + "/" + f
            if FileManager.default.contents(atPath: to) != a { try? a.write(to: URL(fileURLWithPath: to)) }
        }
    }

    // 回傳 true＝原本是擴充套件的（desk-pals.sh），這次換成 .app 版
    @discardableResult
    static func EnsureLaunchAgent(_ exe: String) -> Bool {
        let dir = NSHomeDirectory() + "/Library/LaunchAgents"
        let plist = dir + "/" + Label + ".plist"
        let have = (try? String(contentsOfFile: plist, encoding: .utf8)) ?? ""
        if have.contains("<string>" + Esc(exe) + "</string>") { return false }   // 已經是我（使用者在系統設定關掉的話也還是這份，尊重他）
        let bid = Bundle.main.bundleIdentifier ?? ""
        let want = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>Label</key><string>\(Label)</string>
          <key>ProgramArguments</key><array><string>\(Esc(exe))</string></array>
          <key>RunAtLoad</key><true/>
          <key>LimitLoadToSessionType</key><string>Aqua</string>
          <key>AssociatedBundleIdentifiers</key><string>\(Esc(bid))</string>
        </dict></plist>

        """
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? want.write(toFile: plist, atomically: true, encoding: .utf8)
        return have.contains("desk-pals.sh")
    }

    static func Esc(_ s: String) -> String {
        return s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    static func AskToMove() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)
        let al = NSAlert()
        al.messageText = "先把「Desk Pals」拖進「應用程式」資料夾"
        al.informativeText = "現在是直接從下載的地方（或磁碟映像檔）打開的：這次也能玩，但開機不會自動出現。\n\n把它拖進「應用程式」資料夾，再從那裡打開一次就好了。"
        al.addButton(withTitle: "好")
        al.runModal()
    }

    // 送一行給開著的公仔櫃（unix socket）；沒開回 false
    static func Send(_ path: String, _ line: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { return false }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        if bytes.count >= MemoryLayout.size(ofValue: addr.sun_path) { return false }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if rc != 0 { return false }
        let d = Array((line + "\n").utf8)
        _ = d.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
        usleep(150_000)
        return true
    }

    // 等舊的那個放掉單一執行個體的鎖（App.Run 用 sock.lock 的 flock）
    static func WaitUnlocked(_ lockPath: String, _ secs: Double) {
        let end = Date().addingTimeInterval(secs)
        while Date() < end {
            let fd = open(lockPath, O_RDWR)
            if fd < 0 { return }
            let free = flock(fd, LOCK_EX | LOCK_NB) == 0
            if free { flock(fd, LOCK_UN) }
            close(fd)
            if free { return }
            usleep(200_000)
        }
    }
}

// 在 Finder／Launchpad／Spotlight 再打開一次（App 已經開著）：系統送 reopen 事件 → 叫公仔打招呼
final class ReopenHandler: NSObject {
    let sock: String
    init(_ sock: String) { self.sock = sock }
    func Install() {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(onReopen(_:withReply:)),
                                                     forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEReopenApplication))
    }
    @objc func onReopen(_ e: NSAppleEventDescriptor, withReply r: NSAppleEventDescriptor) {
        let s = sock
        DispatchQueue.global().async { _ = Standalone.Send(s, "act hi") }
    }
}
