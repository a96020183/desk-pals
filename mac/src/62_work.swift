// 62_work.swift — port of extension/desktop/DeskPals.Work.cs
// WoWo Pals：工作來源。Jira、GitLab（glab）、GitHub（gh）、盯 CI、開會（ICS）、下雨、公司網路（VPN）、工作日誌資料夾，
// 再加上把 Claude Code／Codex 做完的對話寫進「小本子」的紀錄。以前在 VS Code 擴充套件（practical.js、ci-watch.js）做，現在桌面版自己做，不用 VS Code。
//
// 規則：
//   * 全部預設關，每個來源自己打開（Claude／Codex 的紀錄例外：只讀本機檔案、只寫本機檔案，預設開）。
//   * 收集器只寫「事實」：%DataDir%\notebook\log-YYYY-MM-DD.jsonl，一行一筆（格式見 v011 SPEC 2b；同一個 id 後寫的蓋前寫的）。
//     合併、白話句子、複製在小本子做（notebook 分支）。Jira 指派給我的未結單另外寫 notebook\jira-open.json 給待辦用。
//   * 要提醒的照舊走 OnNotify（公仔泡泡），用字跟 VS Code 版一樣。
//   * glab／gh 的 token 不碰、不讀：只叫它們自己的指令（glab api、gh api、auth status），輸出也不寫進紀錄。
//   * Jira API token 用 Windows DPAPI（目前使用者）加密存在 jira-token.dat。
//     mac: 存在 macOS 鑰匙圈（generic password，service「WoWo Pals」、account「jira」；離屏測試「jira-test:<資料資料夾>」），不寫檔。
//
// 跟 VS Code 擴充套件：連上時（hello）送「work-own <來源,…>」，設定改了再送一次；新版擴充套件看到就不再自己查、不再自己通知。
//   舊版擴充套件（還不認得 work-own）送來的 notify，桌面版已經在管的那幾種直接丟掉（WorkDropsNotify），不會講兩次。
//
// 掛在別的檔的地方（都只有一兩行，註解寫「工作來源」）：
//   DeskPals.cs：TickInner → WorkTick()、OnMsg 的 hello → WorkHello()、notify → WorkDropsNotify()、config-host → WorkOwns("vpn")、
//     default → WorkMsg()、ClaudeProjectsDir／CodexSessionsDir → AiHomeDefault()、StartDownloadWatch → DownloadsDir()、DataDirInit（離屏測試不碰真的家目錄、資料）、ClaudeWatchOnce／CodexWatchOnce → WorkClaudeRoots()／WorkCodexRoots()／WorkWslAlive()、HealthLoop → VpnReachable()、
//     小屋選單「工作」→ ShowWorkSettings()（DeskPals.WorkSettings.cs）、Snap → WorkSnap()。
//   DeskPals.Study.cs：PlanTick → WorkLogClass()（上課寫進小本子）、SchoolFetchLoop → WorkMeetUrl()（跟開會同一份行事曆不提醒兩次）。
//
// pipe 指令：
//   work-set <key> <值…|->      改設定（key 見 WorkDefaults；值「-」＝清空）。存 work-config.txt，馬上套用
//   work-token <token|->         Jira API token（DPAPI 加密存檔；「-」＝刪掉）（mac: 鑰匙圈）
//   work-poll                    每個打開的來源馬上查一次
//   work-dump                    狀態（測試用）：設定、誰管哪些來源、最近的提醒、丟掉幾則重複通知、CI 在盯哪些
//   work-settings open           打開工作設定視窗（之後小本子的「來源」按鈕也叫這個）
//   測試用（只在離屏模式）：work-clock <yyyy-MM-ddTHH:mm|off>、work-vpncheck、work-forget（忘掉「已經看過」的紀錄）
// 送回擴充套件：work-own <jira,gitlab,github,ci,meet,rain,vpn,worklog|->
//
// 連到哪裡（隱私權政策用）：你填的 Jira 網站（REST API，HTTPS）、你填的行事曆網址（ICS）、wttr.in／api.met.no（下雨：只送地點）、
//   你填的公司主機（只試開 TCP 連線）；GitLab／GitHub 由 glab／gh 自己連（用它們自己的登入）。
// 寫哪些本機檔案（都在 %DataDir%）：work-config.txt、work-seen.txt、jira-token.dat、notebook\log-*.jsonl、notebook\jira-open.json。
//   mac: 沒有 jira-token.dat（token 在鑰匙圈）。
//
// mac 差異（都標了 // mac:）：
// - Jira token：DPAPI → 鑰匙圈（Security framework：SecItemAdd／SecItemUpdate／SecItemCopyMatching／SecItemDelete）。
//   HasJiraToken 只問「有沒有這一項」（不要內容，不會跳授權視窗）。紀錄只寫狀態碼，不寫 token。
// - glab／gh：PATH（用 : 分）＋/opt/homebrew/bin、/usr/local/bin、~/.local/bin 找（沒有 .exe）；Foundation.Process、參數直接給陣列
//   （不用 Windows 的引號規則，Quote 拿掉）；stdout／stderr 各用一個背景佇列讀到底（不會因為 pipe 滿了卡住）；PATH 補上 Homebrew 的位置。
// - HTTP：HttpWebRequest → URLSession（背景執行緒等 semaphore；借 52_study 的 StudyFetchTask：最多 4 次轉址、讀到 8 MB 就停）。
//   4xx／5xx 不會丟例外，看 HTTPURLResponse.statusCode：≥ 400 跟 C# 的 WebException 一樣回 null、status＝狀態碼。
// - DateTimeOffset.TryParse → 00_compat 的 DateTime.TryParse(…, AssumeUniversal)（Z、+08:00、+0800、有沒有小數秒都吃），再不行用 ISO8601DateFormatter。
// - Path.GetFileName（Windows 版把 \ / : 都當分隔）→ WorkFileName：對話的 cwd 可能是 Windows 路徑，照 Windows 的結果取最後一段。
// - WSL：Mac 沒有。claude_dir／codex_dir 留在設定裡（設定檔兩邊通用）；「別的資料夾」是本機存在的資料夾才看，WorkWslAlive 一律 false。
// - Regex.Unescape、DateTime.TryParseExact 在 00_compat 沒有：NoteLog.Unescape、World.WorkParseYmd。
// 刻意寫成 C# 5（不用 $"" / ?. / => 成員 / nameof）。
import Foundation
import Security

// ================= 小本子的紀錄：一行一筆 JSON =================
final class NoteEntry {
    var Id: String! = nil, Src: String! = nil, Project: String! = nil, Title: String! = nil, Status: String! = nil, Ref: String! = nil, Url: String! = nil, Key: String! = nil
    var T = DateTime.MinValue, End = DateTime.MinValue
    var Ok = -1   // -1＝null、0＝false、1＝true
    var Retried = false  // src=ci：第一次沒過、重跑才過（SPEC 2b 小本子的約定），只有 true 才寫
    init() {}
}

enum NoteLog {
    static let gate = NSObject()
    static let days = Dict<String, Dict<String, String>>()   // 日期 → id → 最後寫的那一行
    static let IdRx = Regex("^\\{\"id\":\"((?:[^\"\\\\]|\\\\.)*)\"")

    static func Dir() -> String { return Path.Combine(World.DataDir, "notebook") }
    static func FileFor(_ d: DateTime) -> String { return Path.Combine(Dir(), "log-" + d.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) + ".jsonl") }
    static func Iso(_ t: DateTime) -> String { return t.ToString("yyyy-MM-dd'T'HH:mm:ss", CultureInfo.InvariantCulture) }

    static func Line(_ e: NoteEntry) -> String {
        let sb = StringBuilder("{\"id\":")
        Q(sb, e.Id)
        sb.Append(",\"t\":"); Q(sb, Iso(e.T))
        if e.End != DateTime.MinValue { sb.Append(",\"end\":"); Q(sb, Iso(e.End)) }
        Field(sb, "src", e.Src); Field(sb, "project", e.Project); Field(sb, "title", e.Title); Field(sb, "status", e.Status)
        let ok: String = e.Ok < 0 ? "null" : (e.Ok > 0 ? "true" : "false")
        sb.Append(",\"ok\":").Append(ok)
        Field(sb, "ref", e.Ref); Field(sb, "url", e.Url); Field(sb, "key", e.Key)
        if e.Retried { sb.Append(",\"retried\":true") }
        return sb.Append("}").ToString()
    }
    static func Field(_ sb: StringBuilder, _ k: String, _ v: String?) { if string.IsNullOrEmpty(v) { return }; sb.Append(",\"").Append(k).Append("\":"); Q(sb, v) }
    static func Q(_ sb: StringBuilder, _ s: String?) {
        sb.Append("\"")
        // mac: C# 一個一個 UTF-16 字元看；這裡看 Unicode scalar（BMP 以外的字原樣寫，UTF-8 結果一樣）
        for ch in (s ?? "").unicodeScalars {
            switch ch {
            case "\"": sb.Append("\\\"")
            case "\\": sb.Append("\\\\")
            case "\n": sb.Append("\\n")
            case "\r": sb.Append("\\r")
            case "\t": sb.Append("\\t")
            default:
                if ch.value < 0x20 || ch.value == 0x2028 || ch.value == 0x2029 { sb.Append("\\u" + String(format: "%04x", ch.value)) }
                else { sb.Append(String(ch)) }
            }
        }
        sb.Append("\"")
    }

    // 寫進「結束那天」（沒有結束時間＝開始那天）的檔；跟上次寫的一模一樣就不寫
    @discardableResult static func Write(_ e0: NoteEntry?) -> Bool {
        guard let e = e0 else { return false }
        if string.IsNullOrEmpty(e.Id) || string.IsNullOrEmpty(e.Title) { return false }
        e.Title = OneLine(e.Title)
        let d = (e.End != DateTime.MinValue ? e.End : e.T).Date
        return Append(d, e.Id, Line(e))
    }

    // 小本子（同一個程式）要寫手動加的、做完的待辦也可以用這個：同一把鎖，不會跟收集器的寫入交錯
    @discardableResult static func Append(_ day: DateTime, _ id: String, _ line: String) -> Bool {
        return lock(gate) { () -> Bool in
            let f = FileFor(day), k = day.ToString("yyyyMMdd")
            let m: Dict<String, String>
            if let had = days.Get(k) { m = had }
            else {
                m = Dict<String, String>()
                do {
                    if File.Exists(f) {
                        for l in try File.ReadAllLines(f) {
                            let mm = IdRx.Match(l)
                            if mm.Success { m[Unescape(mm.Groups[1].Value)] = l }
                        }
                    }
                } catch { App.Log("notebook log read: " + error.Message) }
                if days.Count > 8 { days.Clear() }
                days[k] = m
            }
            var was = ""
            if m.TryGetValue(id, &was) && was == line { return false }
            do {
                try Directory.CreateDirectory(Dir())
                let fs = try FileStream(f, FileMode.Append, FileAccess.Write, FileShare.ReadWrite)
                let b: [UInt8] = UTF8Encoding(false).GetBytes(line + "\n")
                try fs.Write(b, 0, b.count)
                fs.Close()
                m[id] = line
                return true
            } catch { App.Log("notebook log write: " + error.Message); return false }
        }
    }

    static func OneLine(_ s: String?) -> String { return Regex.Replace(s ?? "", "[\\s\\x0B\\x85]+", " ").Trim() }   // mac: .NET 的 \s 還有 \v、\x85（ICU 沒有）
    static func Cut(_ s0: String?, _ n: Int) -> String { let s = OneLine(s0); return s.Length > n ? s.Substring(0, n) + "…" : s }

    // mac: Regex.Unescape（00_compat 沒有）。Q 只會寫 \" \\ \n \r \t \uXXXX；其他「\x」＝x（跟 Regex.Unescape 一樣）
    static func Unescape(_ s: String) -> String {
        if !s.Contains("\\") { return s }
        let u = Array(s.utf16)
        var out: [UInt16] = []
        out.reserveCapacity(u.count)
        var i = 0
        while i < u.count {
            let c = u[i]
            if c != 92 || i + 1 >= u.count { out.append(c); i += 1; continue }
            let n = u[i + 1]
            switch n {
            case 110: out.append(10); i += 2   // \n
            case 114: out.append(13); i += 2   // \r
            case 116: out.append(9); i += 2    // \t
            case 117:                          // \uXXXX
                if i + 5 < u.count, let v = UInt16(String(decoding: u[(i + 2)...(i + 5)], as: UTF16.self), radix: 16) { out.append(v); i += 6 }
                else { out.append(n); i += 2 }
            default: out.append(n); i += 2
            }
        }
        return String(decoding: out, as: UTF16.self)
    }
}

// ================= Windows DPAPI（目前使用者）：Jira token 加密存檔 =================
// mac: DPAPI → macOS 鑰匙圈（generic password）。只放在鑰匙圈，不寫檔；離屏（測試）用另一個 account，絕不碰你真的那一項。
enum Secret {
    static let Service = "WoWo Pals"
    static let JiraLabel = "WoWo Pals Jira API token"
    static func JiraAccount() -> String { return App.Offscreen ? "jira-test:" + World.DataDir : "jira" }

    static func Query(_ account: String) -> [String: Any] {
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Service, kSecAttrAccount as String: account]
    }
    // 只問有沒有（要屬性、不要內容：不會跳「要使用鑰匙圈裡的機密資訊」的視窗）
    static func Exists(_ account: String) -> Bool {
        var q = Query(account)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnAttributes as String] = true
        var out: CFTypeRef? = nil
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        if st != errSecSuccess && st != errSecItemNotFound { App.Log("keychain exists: " + String(st)) }
        return st == errSecSuccess
    }
    @discardableResult static func Set(_ account: String, _ value: String, _ label: String) -> Bool {
        let data = Data(value.utf8)
        let q = Query(account)
        let upd: [String: Any] = [kSecValueData as String: data, kSecAttrLabel as String: label]
        var st = SecItemUpdate(q as CFDictionary, upd as CFDictionary)
        if st == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = label
            st = SecItemAdd(add as CFDictionary, nil)
        }
        if st != errSecSuccess { App.Log("keychain set: " + String(st)) }
        return st == errSecSuccess
    }
    static func Get(_ account: String) -> String? {
        var q = Query(account)
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnData as String] = true
        var out: CFTypeRef? = nil
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        if st != errSecSuccess { if st != errSecItemNotFound { App.Log("keychain get: " + String(st)) }; return nil }
        guard let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    @discardableResult static func Delete(_ account: String) -> Bool {
        let st = SecItemDelete(Query(account) as CFDictionary)
        if st != errSecSuccess && st != errSecItemNotFound { App.Log("keychain delete: " + String(st)) }
        return st == errSecSuccess || st == errSecItemNotFound
    }
}

// ================= 叫 glab／gh（token 交給它們自己）=================
enum Cli {
    // PATH 裡找，再看常見的安裝位置（開機自動啟動時 PATH 可能是舊的）
    // mac: PATH 用 : 分、沒有 .exe；Finder／登入項目開的 App 的 PATH 只有 /usr/bin:/bin…，所以再看 Homebrew、~/.local/bin
    static func Find(_ name: String) -> String? {
        let fm = FileManager.default
        for d in (Environment.GetEnvironmentVariable("PATH") ?? "").components(separatedBy: ":") {
            let t = d.Trim().Trim("\"")
            if t == "" { continue }
            let p = Path.Combine(t, name)
            if File.Exists(p) && fm.isExecutableFile(atPath: p) { return p }
        }
        let extra: [String] = ["/opt/homebrew/bin", "/usr/local/bin", Path.Combine(NSHomeDirectory(), ".local/bin")]
        for dir in extra {
            let p = Path.Combine(dir, name)
            if File.Exists(p) && fm.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    // 測試（只在離屏模式）：DESKPALS_FAKE_CLI＝一支 node 小程式，「node <它> glab|gh <參數…>」假裝是 glab／gh
    static func Fake() -> String? { return App.Offscreen ? Environment.GetEnvironmentVariable("DESKPALS_FAKE_CLI") : nil }

    static func Available(_ tool: String) -> Bool { return !string.IsNullOrEmpty(Fake()) || (!App.Offscreen && Find(tool) != nil) }

    final class Buf { var data = Data() }

    // 回傳結束碼（-1＝沒裝、跑不起來或超時）；stdout／stderr 只給呼叫的人解析，不寫進紀錄
    static func Run(_ tool: String, _ args: [String], _ timeoutMs: Int, _ stdout: inout String, _ stderr: inout String) -> Int {
        stdout = ""; stderr = ""
        var exe: String? = nil
        var a: [String] = []
        let fake = Fake()
        if !string.IsNullOrEmpty(fake) { exe = Find("node") ?? "node"; a.append(fake!); a.append(tool) }
        else if App.Offscreen { return -1 }   // 離屏（測試）沒給假的：絕不叫你真的 glab／gh（它們會用你的登入）
        else { exe = Find(tool) }
        guard let exe0 = exe else { return -1 }
        a.append(contentsOf: args)
        // mac: 參數直接給陣列（不用 Windows 命令列的引號規則，C# 的 Quote 拿掉）；只有名字（PATH 裡找不到 node）交給 /usr/bin/env 找
        var path = exe0
        if !exe0.Contains("/") { a.insert(exe0, at: 0); path = "/usr/bin/env" }
        let p = Foundation.Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = a
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        env["GH_PROMPT_DISABLED"] = "1"
        env["GH_NO_UPDATE_NOTIFIER"] = "1"
        env["GLAB_CHECK_UPDATE"] = "false"
        env["GLAB_NO_PROMPT"] = "1"
        let path0: String = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = path0 + ":/opt/homebrew/bin:/usr/local/bin"   // mac: glab／gh 自己可能還要叫 git
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        let po = Pipe(), pe = Pipe()
        p.standardOutput = po
        p.standardError = pe
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        do { try p.run() } catch { App.Log("cli " + tool + ": " + error.Message); return -1 }
        // mac: stdout／stderr 各一個背景佇列讀到底（C# 的 ReadToEndAsync），不然輸出多的時候 pipe 滿了兩邊互等
        let ob = Buf(), eb = Buf()
        let g = DispatchGroup()
        g.enter()
        DispatchQueue.global(qos: .utility).async { ob.data = po.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        g.enter()
        DispatchQueue.global(qos: .utility).async { eb.data = pe.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        let until: DispatchTime = DispatchTime.now() + DispatchTimeInterval.milliseconds(Swift.max(0, timeoutMs))
        if exited.wait(timeout: until) == .timedOut {
            p.terminate()
            return -1
        }
        let until2: DispatchTime = DispatchTime.now() + DispatchTimeInterval.seconds(3)
        if g.wait(timeout: until2) == .success {
            stdout = String(decoding: ob.data, as: UTF8.self)
            stderr = String(decoding: eb.data, as: UTF8.self)
        }
        return Int(p.terminationStatus)
    }
    // mac: Quote（Windows 命令列的引號規則，CommandLineToArgvW）不需要：Foundation.Process 直接收參數陣列
}

//@@IN World
    // ================= 設定（work-config.txt：key=value）=================
    let wcfg = Dict<String, String>()
    var workLoaded = false, workStarted = false
    var jiraTokenCache: Bool? = nil
    // 舊版擴充套件（或 ci-watch.js）送來的通知：桌面版已經在管的就丟掉（不講兩次）
    var workDropped = 0
    var lastOwn = "", appliedVpn = ""
    // ---- 假時鐘（測試）----
    var workShift = TimeSpan.Zero
    // ---- 看過了沒（work-seen.txt）----
    let wseen = Dict<String, String>()
    var seenDirty = false
    // ---- 提醒：離屏測試記下來 ----
    let workNotices = List<String>()
    // ---- 背景執行緒 ----
    var workWake: AutoResetEvent! = nil
    var workPollNow = false   // C#：volatile
    var workPolled = 0
    // ---- glab／gh 有沒有登入 ----
    let glabHosts = List<String>()
    var ghUser = "", glabState = "", ghState = ""
    // ---- Jira ----
    var jiraStatus = "", jiraMe: String? = nil
    // ---- GitLab ----
    let glProjects = Dict<String, Any>()   // host#id → projects/:id
    // ---- 盯 CI ----
    let ciWatches = List<CiWatch>()
    // ---- 開會 ----
    var meetPlan = List<MeetItem>()
    let meetFired = HashSet<String>()
    var meetText = "", meetErr = ""
    // ---- Claude／Codex → 小本子 ----
    let aiLogged = Dict<String, DateTime>()
    var aiWritten = 0
//@@END

extension World {
    // ================= 設定（work-config.txt：key=value）=================
    static let WorkDefaults: [[String]] = [
        ["ai", "1"],            // Claude Code／Codex 做完的對話寫進小本子（只讀寫本機檔案）
        ["claude_dir", ""],     // 進階：別的 Claude 資料夾（WSL：\\wsl$\Ubuntu\home\me\.claude）（mac: 沒有 WSL；本機存在的資料夾才看）
        ["codex_dir", ""],      // 進階：別的 Codex 資料夾
        ["jira", "0"], ["jira_site", ""], ["jira_email", ""],
        ["gitlab", "0"], ["github", "0"], ["ci", "0"],
        ["meet", "0"], ["meet_url", ""], ["meet_before", "5"], ["meet_quiet", "1"],
        ["rain", "0"], ["rain_place", ""],
        ["vpn", "0"], ["vpn_host", ""],
        ["worklog", "0"], ["worklog_dir", ""]]
    static let WorkSources: [String] = ["jira", "gitlab", "github", "ci", "meet", "rain", "vpn", "worklog"]

    func WorkLoad() {
        lock(wcfg) {
            if workLoaded { return }
            workLoaded = true
            for d in World.WorkDefaults { wcfg[d[0]] = d[1] }
            for line in World.ReadText("work-config.txt").Split("\n") {
                let i = line.IndexOf("=")
                if i <= 0 { continue }
                let k = line.Substring(0, i).Trim(), v = line.Substring(i + 1).Trim()
                if wcfg.ContainsKey(k) { wcfg[k] = v }
            }
            for line in World.ReadText("work-seen.txt").Split("\n") {
                let i = line.IndexOf("\t")
                if i > 0 { wseen[line.Substring(0, i)] = line.Substring(i + 1).TrimEnd("\r") }
            }
        }
    }

    func WorkSave() {
        let sb = StringBuilder()
        lock(wcfg) { for d in World.WorkDefaults { sb.Append(d[0] + "=" + (wcfg.Get(d[0]) ?? "") + "\n") } }
        World.WriteText("work-config.txt", sb.ToString())
    }

    func WC(_ k: String) -> String { WorkLoad(); return lock(wcfg) { () -> String in wcfg.Get(k) ?? "" } }
    func WOn(_ k: String) -> Bool { return WC(k) == "1" }

    // 設定視窗、pipe 共用：改一項（回傳 false＝沒有這一項或值不對）
    @discardableResult func WorkSet(_ k: String, _ v0: String?) -> Bool {
        WorkLoad()
        var v = NoteLog.OneLine(v0 ?? "")
        if v == "-" { v = "" }
        let has: Bool = lock(wcfg) { () -> Bool in wcfg.ContainsKey(k) }
        if !has { return false }
        switch k {
        case "ai", "jira", "gitlab", "github", "ci", "meet", "meet_quiet", "rain", "vpn", "worklog":
            v = v == "1" || v == "on" || v == "true" ? "1" : "0"
        case "meet_before":
            var n = 0
            if !int.TryParse(v, &n) || n < 1 || n > 120 { return false }
            v = n.ToString()
        case "meet_url": if v != "" && World.WorkUrl(v) == nil { return false }
        case "vpn_host": if v != "" && !Regex.IsMatch(v, "^[\\w.-]+(:\\d{1,5})?$") { return false }
        default: break
        }
        let v1 = v
        lock(wcfg) { wcfg[k] = v1 }
        WorkSave()
        WorkApply()
        let hidden = k.EndsWith("_url") || k == "jira_email"
        let state: String = v == "" ? "empty" : "set"
        let shown: String = hidden ? " (" + state + ")" : "=" + v
        App.Log("work set " + k + shown)
        return true
    }

    // ---- Jira token：DPAPI ----（mac: 鑰匙圈）
    func HasJiraToken() -> Bool {
        if jiraTokenCache == nil { jiraTokenCache = Secret.Exists(Secret.JiraAccount()) }
        return jiraTokenCache!
    }
    @discardableResult func SetJiraToken(_ token0: String?) -> Bool {
        let token = (token0 ?? "").Trim()
        if token == "" || token == "-" { Secret.Delete(Secret.JiraAccount()); jiraTokenCache = false; WorkApply(); return true }
        // mac: 不用建資料夾、不寫檔：直接放進鑰匙圈
        if !Secret.Set(Secret.JiraAccount(), token, Secret.JiraLabel) { App.Log("jira token: keychain failed"); return false }
        jiraTokenCache = true
        WorkApply()
        return true
    }
    func JiraToken() -> String? {
        return Secret.Get(Secret.JiraAccount())
    }

    // ---- 誰管哪個來源 ----
    func WorkOwns(_ src: String) -> Bool {
        switch src {
        case "jira": return WOn("jira") && WC("jira_site") != "" && WC("jira_email") != "" && HasJiraToken()
        case "gitlab", "github", "ci": return WOn(src)
        case "meet": return WOn("meet") && WC("meet_url") != ""
        case "rain": return WOn("rain") && WC("rain_place") != ""
        case "vpn": return WOn("vpn") && WC("vpn_host") != ""
        case "worklog": return WOn("worklog") && WC("worklog_dir") != ""
        default: break
        }
        return false
    }
    func WorkOwnLine() -> String {
        let l = List<String>()
        for s in World.WorkSources { if WorkOwns(s) { l.Add(s) } }
        let list: String = l.Count == 0 ? "-" : string.Join(",", l.ToArray())
        return "work-own " + list + "\n"
    }
    func WorkHello(_ c: Client) { World.Send(c, WorkOwnLine()) }

    // 舊版擴充套件（或 ci-watch.js）送來的通知：桌面版已經在管的就丟掉（不講兩次）
    func WorkDropsNotify(_ kind: String) -> Bool {
        var src: String? = nil
        switch kind {
        case "jira": src = "jira"
        case "gitlab": src = "gitlab"
        case "ci-run", "ci-ok", "ci-fail": src = "ci"
        case "meeting", "meeting-now": src = "meet"
        case "rain": src = "rain"
        case "worklog": src = "worklog"
        default: break
        }
        guard let s = src else { return false }
        if !WorkOwns(s) { return false }
        workDropped += 1
        App.Log("work: dropped a " + kind + " notice from VS Code (the desktop handles " + s + ")")
        return true
    }

    func WorkApply() {
        let own = WorkOwnLine()
        if own != lastOwn { lastOwn = own; lock(clients) { for c in clients { World.Send(c, own) } } }
        // 公司網路：桌面版有設就用桌面版的（VS Code 的 deskPals.companyHost 不再蓋過來）
        let vh = WorkOwns("vpn") ? WC("vpn_host") : ""
        if vh != appliedVpn { if vh != "" || companyHost == appliedVpn { companyHost = vh }; appliedVpn = vh }
        workPollNow = true
        if workWake != nil { workWake.Set() }
    }

    // ---- 公司網路：host 或 host:port ----
    static func VpnReachable(_ host: String) -> Bool {
        let c = host.LastIndexOf(":")
        var port = 0
        if c > 0 && int.TryParse(host.Substring(c + 1), &port) { return World.TcpOk(host.Substring(0, c), port) }
        return World.TcpOk(host, 443) || World.TcpOk(host, 80)
    }

    // ---- 網址：只收 https（webcal 當 https）；測試時（離屏）才收本機的 http ----
    static func WorkUrl(_ s0: String?) -> String? {
        var s = (s0 ?? "").Trim()
        if s.StartsWith("webcal://", StringComparison.OrdinalIgnoreCase) { s = "https://" + s.Substring(9) }
        else if s.StartsWith("webcals://", StringComparison.OrdinalIgnoreCase) { s = "https://" + s.Substring(10) }
        var u: Uri? = nil
        if !Uri.TryCreate(s, UriKind.Absolute, &u) || u == nil { return nil }
        if u!.Scheme == Uri.UriSchemeHttps { return s }
        if App.Offscreen && u!.Scheme == Uri.UriSchemeHttp && (u!.Host == "127.0.0.1" || u!.Host == "localhost") { return s }
        return nil
    }

    // ---- 假時鐘（測試）----
    func WNow() -> DateTime { return DateTime.Now + workShift }
    static let Epoch0 = DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)
    func WNowMs() -> Int { return CInt((WNow().ToUniversalTime() - World.Epoch0).TotalMilliseconds) }
    static func LocalOfMs(_ ms: Int) -> DateTime { return World.Epoch0.AddMilliseconds(ms).ToLocalTime() }

    // ---- 看過了沒（work-seen.txt：key\tvalue；重開也不會再講一次）----
    func Seen(_ k: String) -> String? { return lock(wcfg) { () -> String? in wseen.Get(k) } }
    func SetSeen(_ k: String, _ v: String) { lock(wcfg) { wseen[k] = v; seenDirty = true } }
    func SaveSeen() {
        let sb = StringBuilder()
        let go: Bool = lock(wcfg) { () -> Bool in
            if !seenDirty { return false }
            seenDirty = false
            // 一天一次的旗子只留最近幾天
            let keep = WNow().AddDays(-3).ToString("yyyyMMdd")
            let drop = List<String>()
            for kv in wseen {
                let m = Regex.Match(kv.Key, ":(\\d{8})(:|$)")
                if m.Success && string.CompareOrdinal(m.Groups[1].Value, keep) < 0 { drop.Add(kv.Key) }
            }
            for k in drop { wseen.Remove(k) }
            for kv in wseen { sb.Append(kv.Key + "\t" + kv.Value + "\n") }
            return true
        }
        if !go { return }
        World.WriteText("work-seen.txt", sb.ToString())
    }
    static func SeenList(_ v: String?) -> List<String> { let l = List<String>(); if v != nil { for x in v!.Split(",") { if x != "" { l.Add(x) } } }; return l }
    static func SeenJoin(_ l0: List<String>) -> String { var l = l0; if l.Count > 500 { l = l.GetRange(l.Count - 500, 500) }; return string.Join(",", l.ToArray()) }

    // ---- 提醒：照舊走 OnNotify（公仔泡泡）；離屏測試記下來 ----
    func WNotify(_ kind: String, _ url: String?, _ text0: String?) {
        let text = NoteLog.OneLine(text0)
        let rec: String = kind + " " + (url ?? "-") + " " + text
        lock(workNotices) { workNotices.Add(rec); if workNotices.Count > 60 { workNotices.RemoveAt(0) } }
        App.Log("work notify " + kind)
        let k = kind, u: String = string.IsNullOrEmpty(url) ? "-" : url!, t = text
        Post { self.OnNotify(k, u, t) }
    }

    // ================= 開始（TickInner 每一輪叫；第一次才開背景執行緒）=================
    func WorkTick() {
        if workStarted { return }
        workStarted = true
        WorkLoad()
        let vh = WorkOwns("vpn") ? WC("vpn_host") : ""
        if vh != "" { companyHost = vh; appliedVpn = vh }
        lastOwn = WorkOwnLine()
        workWake = AutoResetEvent(false)
        let th = Thread { self.WorkLoop() }; th.IsBackground = true; th.Start()
    }

    func WorkLoop() {
        Thread.Sleep(App.Offscreen ? 300 : 6000)
        let off = App.Offscreen
        let s20: Int = off ? 0 : 20, s25: Int = off ? 0 : 25, s30: Int = off ? 0 : 30
        var nAi = DateTime.MinValue, nAuth = DateTime.MinValue, nJira = DateTime.Now.AddSeconds(s20), nGl = DateTime.Now.AddSeconds(s25)
        var nGh = DateTime.Now.AddSeconds(s30), nMeet = DateTime.MinValue, nRain = DateTime.Now.AddSeconds(s30), nWl = DateTime.MinValue, nSave = DateTime.MinValue
        let js = JavaScriptSerializer()
        js.MaxJsonLength = int.MaxValue
        while !closing {
            let force = workPollNow
            if force {
                workPollNow = false
                nAi = DateTime.MinValue; nAuth = nAi; nJira = nAi; nGl = nAi; nGh = nAi; nMeet = nAi; nRain = nAi; nWl = nAi
            }
            let now = DateTime.Now
            if WOn("ai") && now >= nAi { nAi = now.AddSeconds(30); Try("ai") { self.AiScan(js) } }
            if (WOn("gitlab") || WOn("github") || WOn("ci")) && now >= nAuth { nAuth = now.AddMinutes(10); Try("auth") { self.DetectAuth() } }
            if WorkOwns("jira") && now >= nJira { nJira = now.AddMinutes(3); Try("jira") { try self.JiraCheck(js) } }
            if (WOn("gitlab") || WOn("ci")) && now >= nGl { let s: Int = WOn("ci") ? 60 : 180; nGl = now.AddSeconds(s); Try("gitlab") { self.GitLabCheck(js) } }
            if (WOn("github") || WOn("ci")) && now >= nGh { let s: Int = WOn("ci") ? 60 : 180; nGh = now.AddSeconds(s); Try("github") { self.GitHubCheck(js) } }
            if WOn("ci") { Try("ci") { self.CiStep(js, force) } }
            if WorkOwns("meet") {
                if now >= nMeet { nMeet = now.AddMinutes(10); Try("meet") { self.MeetFetch() } }
                Try("meet") { self.MeetTick() }
            }
            if WorkOwns("rain") && now >= nRain { nRain = now.AddMinutes(10); Try("rain") { self.RainCheck(js) } }
            if WorkOwns("worklog") && now >= nWl { nWl = now.AddSeconds(60); Try("worklog") { self.WorklogCheck() } }
            if now >= nSave || force { nSave = now.AddSeconds(20); SaveSeen() }
            if force { workPolled += 1 }
            workWake.WaitOne(1000)
        }
    }
    // mac: C# 的 catch (Exception) 只接得到 throw 的；Swift 會當掉的地方（nil、索引）都先擋掉了
    func Try(_ what: String, _ a: () throws -> Void) { do { try a() } catch { App.Log("work " + what + ": " + error.Message) } }

    // ================= JSON 小工具 =================
    // mac: JavaScriptSerializer（00_compat）：物件＝Dict<String, Any>、陣列＝[Any]、null＝NSNull（這裡當成 null）
    static func J(_ o: Any?, _ path: String...) -> Any? { return JPath(o, path) }
    static func JPath(_ o0: Any?, _ path: [String]) -> Any? {
        var o: Any? = o0
        for k in path {
            guard let d = o as? Dict<String, Any> else { return nil }
            guard let v = d.Get(k) else { return nil }
            o = v
        }
        if o is NSNull { return nil }
        return o
    }
    static func JS(_ o: Any?, _ path: String...) -> String? { return JSPath(o, path) }
    static func JSPath(_ o: Any?, _ path: [String]) -> String? { guard let v = JPath(o, path) else { return nil }; return Convert.ToString(v, CultureInfo.InvariantCulture) }
    static func JA(_ o: Any?, _ path: String...) -> [Any] { if let a = JPath(o, path) as? [Any] { return a }; return [] }
    static func JI(_ o: Any?, _ path: String...) -> Int { var n = 0; return int.TryParse(JSPath(o, path) ?? "", &n) ? n : 0 }
    // C# JA(new Dictionary<string, object> { { "a", list } }, "a")：glab／gh 回的是整個陣列
    static func JArr(_ o: Any?) -> [Any] { let d = Dict<String, Any>(); if let v = o { d["a"] = v }; return JA(d, "a") }
    static func JT(_ s: String?) -> DateTime {
        // mac: DateTimeOffset.TryParse(…, AssumeUniversal) → 00_compat 的 DateTime.TryParse(…, AssumeUniversal)：
        //      Z、+08:00、Jira 的 +0800（時區沒有冒號）、有沒有小數秒都吃；有時區＝換成本地時間，沒有＝當 UTC。再不行用 ISO8601DateFormatter 試一次。
        if s == nil { return DateTime.MinValue }
        var t = DateTime.MinValue
        if DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, &t) { return t.Kind == DateTimeKind.Local ? t : t.ToLocalTime() }
        if let d = World.WorkIsoDate(s!) { return DateTime(d) }
        return DateTime.MinValue
    }
    static let WorkIsoF1: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    static let WorkIsoF2: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    static func WorkIsoDate(_ s: String) -> Foundation.Date? {
        if let d = WorkIsoF1.date(from: s) { return d }
        return WorkIsoF2.date(from: s)
    }
    // mac: DateTime.TryParseExact(s, "yyyy-MM-dd", …)（00_compat 沒有）：先看格式，再交給 TryParse
    static func WorkParseYmd(_ s: String, _ d: inout DateTime) -> Bool {
        if !Regex.IsMatch(s, "^[0-9]{4}-[0-9]{2}-[0-9]{2}$") { d = DateTime.MinValue; return false }
        return DateTime.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.None, &d)
    }
    func ParseJson(_ js: JavaScriptSerializer, _ s: String?) -> Any? { if string.IsNullOrEmpty(s) { return nil }; return try? js.DeserializeObject(s) }

    // ================= HTTP（Jira、天氣、行事曆）=================
    // 回傳內容；status＝HTTP 狀態（0＝連不上）
    // mac: URLSession（StudyFetchTask：最多 4 次轉址、8 MB 就停；gzip 自己解）。4xx／5xx 不丟例外：看狀態碼，≥ 400 回 null（C# 的 WebException）
    static func HttpGet(_ url: String, _ auth: String?, _ timeoutMs: Int, _ status: inout Int) -> String? {
        status = 0
        // 離屏（測試）：只連本機的假伺服器，真的網址一律不連（測試不能碰網路、也不能拿使用者的 token 去試）
        if App.Offscreen {
            var u: Uri? = nil
            if !Uri.TryCreate(url, UriKind.Absolute, &u) || u == nil || (u!.Host != "127.0.0.1" && u!.Host != "localhost") {
                let h: String = u != nil ? u!.Host : "?"
                App.Log("work: offscreen, not fetching " + h)
                return nil
            }
        }
        guard let nu = URL(string: url) else { return nil }
        let secs = Double(Swift.max(1000, timeoutMs)) / 1000.0
        var req = URLRequest(url: nu, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: secs)
        req.setValue("WoWoPals", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let a = auth { req.setValue(a, forHTTPHeaderField: "Authorization") }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = secs
        cfg.timeoutIntervalForResource = secs * 6
        let ft = StudyFetchTask()
        let session = URLSession(configuration: cfg, delegate: ft, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        session.dataTask(with: req).resume()
        let deadline: DispatchTime = DispatchTime.now() + (secs * 6.0 + 5.0)
        if ft.done.wait(timeout: deadline) == .timedOut { session.invalidateAndCancel(); return nil }
        status = ft.status
        if ft.failed != nil { return nil }
        if status >= 400 { return nil }
        var s = String(decoding: ft.data, as: UTF8.self)
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }   // StreamReader 會吃掉 BOM
        return s
    }

    // ================= glab／gh 有沒有登入（只看「Logged in to <host> as <user>」那幾行）=================
    static let GlabLogin = Regex("Logged in to (\\S+) as (\\S+)")
    static let GhLogin = Regex("Logged in to (\\S+) (?:account|as) (\\S+)")
    func DetectAuth() {
        var o = "", e = ""
        let hosts = List<String>()
        var rc = Cli.Run("glab", ["auth", "status"], 30000, &o, &e)
        for m in World.GlabLogin.Matches(o + "\n" + e) { if !hosts.Contains(m.Groups[1].Value) { hosts.Add(m.Groups[1].Value) } }
        lock(glabHosts) { glabHosts.Clear(); glabHosts.AddRange(hosts) }
        let glabMissing = (rc == -1 && !Cli.Available("glab")) || rc == 9009
        glabState = glabMissing ? "missing" : (hosts.Count > 0 ? "ok" : "nologin")
        rc = Cli.Run("gh", ["auth", "status"], 30000, &o, &e)
        let g = World.GhLogin.Match(o + "\n" + e)
        ghUser = g.Success ? g.Groups[2].Value.Trim("(", ")") : ""
        let ghMissing = (rc == -1 && !Cli.Available("gh")) || rc == 9009
        ghState = ghMissing ? "missing" : (ghUser != "" ? "ok" : "nologin")
        App.Log("work auth: glab=" + glabState + " (" + String(hosts.Count) + " host) gh=" + ghState)
    }
    func GlabHosts() -> List<String> { if glabState == "" { DetectAuth() }; return lock(glabHosts) { () -> List<String> in List<String>(glabHosts) } }

    func Glab(_ js: JavaScriptSerializer, _ host: String, _ path: String) -> Any? {
        var o = "", e = ""
        let rc = Cli.Run("glab", ["api", "--hostname", host, path], 30000, &o, &e)
        return rc == 0 ? ParseJson(js, o) : nil
    }
    func Gh(_ js: JavaScriptSerializer, _ path: String) -> Any? {
        var o = "", e = ""
        let rc = Cli.Run("gh", ["api", path], 30000, &o, &e)
        return rc == 0 ? ParseJson(js, o) : nil
    }

    // ================= Jira =================
    func JiraBase() -> String? {
        var s = WC("jira_site").Trim().TrimEnd("/")
        if s == "" { return nil }
        if s.StartsWith("http://", StringComparison.OrdinalIgnoreCase) { return World.WorkUrl(s) != nil ? s : nil }   // 只有測試（離屏、本機）
        if s.StartsWith("https://", StringComparison.OrdinalIgnoreCase) { s = s.Substring(8) }
        let sl = s.IndexOf("/")
        if sl >= 0 { s = s.Substring(0, sl) }
        return "https://" + s
    }
    func JiraGet(_ js: JavaScriptSerializer, _ path: String) throws -> Any? {
        let b = JiraBase(), tok = JiraToken()
        if b == nil || tok == nil { return nil }
        let auth = "Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes(WC("jira_email") + ":" + tok!))
        var st = 0
        let body = World.HttpGet(b! + path, auth, 20000, &st)
        let other: String = st == 0 ? "down" : "http " + String(st)
        jiraStatus = st == 200 ? "ok" : (st == 401 || st == 403 ? "auth" : other)
        if body == nil { throw Exception("jira " + jiraStatus) }
        return ParseJson(js, body)
    }
    func JiraSearch(_ js: JavaScriptSerializer, _ jql: String, _ fields: String, _ max: Int) throws -> [Any] {
        let path: String = "/rest/api/3/search/jql?jql=" + Uri.EscapeDataString(jql) + "&fields=" + fields + "&maxResults=" + String(max)
        let r = try JiraGet(js, path)
        return World.JA(r, "issues")
    }
    static func AdfText(_ n: Any?) -> String {
        if n == nil { return "" }
        let type = JS(n, "type")
        if type == "text" { return JS(n, "text") ?? "" }
        if type == "mention" { return JS(n, "attrs", "text") ?? "@" }
        let sb = StringBuilder()
        for c in JA(n, "content") { sb.Append(AdfText(c)); if type == "paragraph" { sb.Append(" ") } }
        return sb.ToString()
    }

    func JiraCheck(_ js: JavaScriptSerializer) throws {
        guard let b = JiraBase() else { throw Exception("jira: no site") }   // mac: C# 這裡是 new Uri(null) 丟例外
        let host = Uri(b).Authority
        // 1) 新單指派給你（第一次只記下來）＋給小本子待辦的未結單
        let jql = "assignee = currentUser() AND statusCategory != Done ORDER BY created DESC"
        let open_ = try JiraSearch(js, jql, "summary,status", 100)   // mac: open 是 Swift 的存取修飾字（也是 Darwin 的 open()），改叫 open_
        let oj = StringBuilder("[")
        let keys = List<String>()
        for i in open_ {
            guard let k = World.JS(i, "key") else { continue }
            keys.Add(k)
            if oj.Length > 1 { oj.Append(",") }
            oj.Append("{\"key\":"); NoteLog.Q(oj, k)
            oj.Append(",\"title\":"); NoteLog.Q(oj, NoteLog.OneLine(World.JS(i, "fields", "summary")))
            oj.Append(",\"status\":"); NoteLog.Q(oj, World.JS(i, "fields", "status", "name") ?? "")
            oj.Append(",\"url\":"); NoteLog.Q(oj, b + "/browse/" + k)
            oj.Append("}")
        }
        oj.Append("]\n")
        do { try Directory.CreateDirectory(NoteLog.Dir()); try File.WriteAllText(Path.Combine(NoteLog.Dir(), "jira-open.json"), oj.ToString()) } catch {}
        let sk = "jira-seen:" + host
        let seen0 = Seen(sk)
        let seen = World.SeenList(seen0)
        if seen0 == nil { SetSeen(sk, World.SeenJoin(keys)) }
        else {
            let fresh = List<Any>()
            for i in open_ { let k = World.JS(i, "key"); if k == nil || !seen.Contains(k!) { fresh.Add(i) } }
            var n = 0
            while n < fresh.Count && n < 3 {
                let fk = World.JS(fresh[n], "key") ?? ""
                let msg: String = fk + " 指派給你了：" + NoteLog.Cut(World.JS(fresh[n], "fields", "summary"), 40)
                WNotify("jira", b + "/browse/" + fk, msg)
                n += 1
            }
            if fresh.Count > 3 { WNotify("jira", b + "/issues/?jql=" + Uri.EscapeDataString(jql), "還有 " + String(fresh.Count - 3) + " 張新單指派給你") }
            for k in keys { if !seen.Contains(k) { seen.Add(k) } }
            SetSeen(sk, World.SeenJoin(seen))
        }

        // 2) 到期：平日 09:30、16:30 各看一次
        let d = WNow()
        let hm = d.Hour * 60 + d.Minute
        let slot: String? = hm >= 16 * 60 + 30 ? "pm" : (hm >= 9 * 60 + 30 ? "am" : nil)
        let dk: String = "jira-due:" + host + ":" + d.ToString("yyyyMMdd") + ":" + (slot ?? "")
        let weekday = d.DayOfWeek != DayOfWeek.Saturday && d.DayOfWeek != DayOfWeek.Sunday
        if slot != nil && weekday && Seen(dk) == nil {
            SetSeen(dk, "1")
            let djql = "assignee = currentUser() AND statusCategory != Done AND duedate >= -14d AND duedate <= endOfDay(1) ORDER BY duedate ASC"
            let due = try JiraSearch(js, djql, "summary,duedate", 50)
            let over = List<String>(), today = List<String>(), tmr = List<String>()
            for i in due {
                var dd = DateTime.MinValue
                if !World.WorkParseYmd(World.JS(i, "fields", "duedate") ?? "", &dd) { continue }
                let diff = CInt(Math.Round((dd - d.Date).TotalDays))
                let bucket: List<String> = diff < 0 ? over : (diff == 0 ? today : tmr)
                bucket.Add(World.JS(i, "key") ?? "")
            }
            let parts = List<String>()
            if today.Count > 0 {
                let more: String = today.Count > 3 ? " 等 " + String(today.Count) + " 張" : ""
                let ks: String = string.Join("、", today.GetRange(0, Math.Min(3, today.Count)).ToArray())
                parts.Add("今天到期：" + ks + more)
            }
            if tmr.Count > 0 {
                let more: String = tmr.Count > 3 ? " 等 " + String(tmr.Count) + " 張" : ""
                let ks: String = string.Join("、", tmr.GetRange(0, Math.Min(3, tmr.Count)).ToArray())
                parts.Add("明天到期：" + ks + more)
            }
            if over.Count > 0 { parts.Add("已經逾期 " + String(over.Count) + " 張") }
            if parts.Count > 0 {
                let one: String = b + "/browse/" + (due.count > 0 ? (World.JS(due[0], "key") ?? "") : "")
                let url: String = due.count == 1 ? one : b + "/issues/?jql=" + Uri.EscapeDataString(djql)
                WNotify("jira", url, string.Join("；", parts.ToArray()))
            }
        }

        // 3) 有人在留言 @你
        if jiraMe == nil { let me0 = try JiraGet(js, "/rest/api/3/myself"); jiraMe = World.JS(me0, "accountId") }
        if let me = jiraMe {
            let mk = "jira-mention:" + host
            var since = 0
            let nowMs = WNowMs()
            if !long.TryParse(Seen(mk) ?? "", &since) { SetSeen(mk, String(nowMs)) }
            else {
                var newest = since
                let recent = try JiraSearch(js, "updated >= -20m AND (watcher = currentUser() OR assignee = currentUser() OR reporter = currentUser()) ORDER BY updated DESC", "summary", 20)
                for i in recent {
                    let k = World.JS(i, "key") ?? ""
                    let cr = try JiraGet(js, "/rest/api/3/issue/" + k + "/comment?orderBy=-created&maxResults=5")
                    for x in World.JA(cr, "comments") {
                        let ct = World.JT(World.JS(x, "created"))
                        let t: Int = ct == DateTime.MinValue ? 0 : CInt((ct.ToUniversalTime() - World.Epoch0).TotalMilliseconds)
                        if t <= since || World.JS(x, "author", "accountId") == me { continue }
                        let body: Any = World.J(x, "body") ?? ""
                        if JavaScriptSerializer().Serialize(body).IndexOf("\"id\":\"" + me + "\"", StringComparison.Ordinal) < 0 { continue }
                        newest = Math.Max(newest, t)
                        let who: String = World.JS(x, "author", "displayName") ?? "有人"
                        let url: String = b + "/browse/" + k + "?focusedCommentId=" + (World.JS(x, "id") ?? "")
                        let msg: String = who + " 在 " + k + " @你：" + NoteLog.Cut(World.AdfText(World.J(x, "body")), 40)
                        WNotify("jira", url, msg)
                    }
                }
                SetSeen(mk, String(Math.Max(newest, nowMs - 60000)))
            }
        }

        // 4) 小本子：今天你動過狀態的單、今天解決的單
        let mine = try JiraSearch(js, "(status changed BY currentUser() AFTER startOfDay()) OR (assignee = currentUser() AND resolved >= startOfDay()) ORDER BY updated DESC", "summary,status,project,updated", 50)
        for i in mine {
            guard let k = World.JS(i, "key") else { continue }
            let done = World.JS(i, "fields", "status", "statusCategory", "key") == "done"
            let e = NoteEntry()
            e.Id = "jira:" + k + (done ? ":resolved" : ":status")
            e.T = World.JT(World.JS(i, "fields", "updated")); if e.T == DateTime.MinValue { e.T = WNow() }
            e.Src = "jira"; e.Project = World.JS(i, "fields", "project", "name"); e.Title = World.JS(i, "fields", "summary")
            e.Status = done ? "工單解決了" : World.JS(i, "fields", "status", "name")
            e.Ok = done ? 1 : -1; e.Ref = k; e.Url = b + "/browse/" + k; e.Key = k
            NoteLog.Write(e)
        }
    }

    // ================= GitLab（glab）：待辦提醒＋今天做的事＋推了 tag（盯 CI 用）=================
    static let TodoText: Dict<String, String> = {
        let d = Dict<String, String>()
        let rows: [(String, String)] = [
            ("review_requested", "請你 review"), ("assigned", "指派給你"), ("mentioned", "@你"), ("directly_addressed", "@你"),
            ("build_failed", "pipeline 失敗"), ("approval_required", "需要你核准"), ("unmergeable", "沒辦法合併了"), ("marked", "加了待辦")]
        for r in rows { d[r.0] = r.1 }
        return d
    }()

    func GitLabCheck(_ js: JavaScriptSerializer) {
        for host in GlabHosts() {
            if WOn("gitlab") {
                let list = Glab(js, host, "todos?state=pending&per_page=20")
                if list != nil {
                    let todos = World.JArr(list)
                    let sk = "gl-todo:" + host
                    let seen0 = Seen(sk)
                    let seen = World.SeenList(seen0), ids = List<String>()
                    for t in todos { ids.Add(World.JS(t, "id") ?? "") }
                    if seen0 != nil {
                        let fresh = List<Any>()
                        for t in todos { if !seen.Contains(World.JS(t, "id") ?? "") { fresh.Add(t) } }
                        var n = 0
                        while n < fresh.Count && n < 3 {
                            let t = fresh[n]
                            let act = World.JS(t, "action_name") ?? ""
                            var what = ""
                            if !World.TodoText.TryGetValue(act, &what) { what = act }
                            let tt = World.JS(t, "target_type")
                            let rf: String = tt == "MergeRequest" ? "MR" : (tt == "Issue" ? "Issue" : "")
                            let kind: String = act == "build_failed" ? "ci-fail" : "gitlab"
                            let who: String = World.JS(t, "author", "name") ?? "有人"
                            let msg: String = who + " " + what + "：" + rf + " " + NoteLog.Cut(World.JS(t, "target", "title"), 36)
                            WNotify(kind, World.JS(t, "target_url"), msg)
                            n += 1
                        }
                        if fresh.Count > 3 { WNotify("gitlab", "https://" + host + "/dashboard/todos", "GitLab 還有 " + String(fresh.Count - 3) + " 件新待辦") }
                    }
                    for id in ids { if !seen.Contains(id) { seen.Add(id) } }
                    SetSeen(sk, World.SeenJoin(seen))
                }
            }
            // 你自己的動態（推 commit、開／合併 MR、推 tag）
            let ev = Glab(js, host, "events?after=" + WNow().AddDays(-2).ToString("yyyy-MM-dd") + "&per_page=100&sort=desc")
            if ev == nil { continue }
            let today = WNow().Date
            let pushes = Dict<String, NoteEntry>()
            for x in World.JArr(ev) {
                let at = World.JT(World.JS(x, "created_at"))
                if at == DateTime.MinValue { continue }
                let act = World.JS(x, "action_name") ?? "", pid = World.JS(x, "project_id")
                let proj = GlProject(js, host, pid)
                guard let path = World.JS(proj, "path_with_namespace") else { continue }
                let web = World.JS(proj, "web_url"), name = World.JS(proj, "name") ?? World.JS(proj, "path")
                let pd = World.J(x, "push_data")
                // 推了 tag → 盯 CI
                if pd != nil && World.JS(pd, "ref_type") == "tag" && act == "pushed new" {
                    if WOn("ci") { CiCandidate("gitlab", host, pid, path, name, World.JS(pd, "ref"), at) }
                    continue
                }
                if WOn("gitlab") == false || at.Date != today { continue }
                if pd != nil && World.JS(pd, "ref_type") == "branch" && (act == "pushed to" || act == "pushed new") {
                    let br = World.JS(pd, "ref") ?? ""
                    let id = "gitlab:" + path + ":push:" + br
                    let e: NoteEntry
                    if let had = pushes.Get(id) { e = had }
                    else {
                        e = NoteEntry(); e.Id = id; e.Src = "gitlab"; e.Project = name; e.Key = br; e.End = at; e.T = at; e.Ref = br
                        e.Title = World.JS(pd, "commit_title") ?? ("推到 " + br); e.Url = (web ?? "") + "/-/commits/" + br; e.Ok = -1; e.Status = "0"
                        pushes[id] = e
                    }
                    if at < e.T { e.T = at }
                    if at > e.End { e.End = at; e.Title = World.JS(pd, "commit_title") ?? e.Title }
                    e.Status = String(int.Parse(e.Status) + Math.Max(1, World.JI(pd, "commit_count")))
                    continue
                }
                if World.JS(x, "target_type") == "MergeRequest" && (act == "opened" || act == "accepted" || act == "approved") {
                    let iid = World.JS(x, "target_iid") ?? ""
                    let e = NoteEntry()
                    let what: String = act == "opened" ? "opened" : (act == "accepted" ? "merged" : "approved")
                    e.Id = "gitlab:" + path + "!" + iid + ":" + what; e.T = at; e.Src = "gitlab"; e.Project = name
                    e.Title = World.JS(x, "target_title"); e.Status = act == "opened" ? "開了 MR" : (act == "accepted" ? "合併了" : "核准了")
                    e.Ok = act == "accepted" ? 1 : -1; e.Ref = "MR !" + iid; e.Url = (web ?? "") + "/-/merge_requests/" + iid; e.Key = path
                    NoteLog.Write(e)
                }
            }
            for e in pushes.Values {
                let n = int.Parse(e.Status)
                e.Status = "推了 " + String(n) + " 個 commit"
                if e.End == e.T { e.End = DateTime.MinValue }
                NoteLog.Write(e)
            }
        }
    }
    func GlProject(_ js: JavaScriptSerializer, _ host: String, _ id0: String?) -> Any? {
        guard let id = id0 else { return nil }
        let k = host + "#" + id
        let had: Any? = lock(glProjects) { () -> Any? in glProjects.Get(k) }
        if had != nil { return had }
        let p = Glab(js, host, "projects/" + id)
        if let pv = p { lock(glProjects) { glProjects[k] = pv } }
        return p
    }

    // ================= GitHub（gh）：通知提醒＋今天做的事＋推了 tag =================
    static let GhReason: Dict<String, String> = {
        let d = Dict<String, String>()
        let rows: [(String, String)] = [
            ("review_requested", "請你 review"), ("mention", "@你"), ("team_mention", "@你的團隊"), ("assign", "指派給你"),
            ("ci_activity", "CI 沒過"), ("author", "有新回覆"), ("comment", "有新留言"), ("approval_requested", "需要你核准")]
        for r in rows { d[r.0] = r.1 }
        return d
    }()

    static func GhWeb(_ api: String?) -> String? {
        // https://api.github.com/repos/o/r/pulls/17 → https://github.com/o/r/pull/17
        if string.IsNullOrEmpty(api) { return nil }
        let m = Regex.Match(api, "^https://api\\.github\\.com/repos/([^/]+/[^/]+)/(pulls|issues|commits)/(\\w+)")
        if !m.Success { return nil }
        let kind = m.Groups[2].Value
        let seg: String = kind == "pulls" ? "pull" : (kind.TrimEnd("s") == "commit" ? "commit" : "issues")
        return "https://github.com/" + m.Groups[1].Value + "/" + seg + "/" + m.Groups[3].Value
    }

    func GitHubCheck(_ js: JavaScriptSerializer) {
        if ghState == "" { DetectAuth() }
        if ghUser == "" { return }
        if WOn("github") {
            let list = Gh(js, "notifications?per_page=30")
            if list != nil {
                let ns = World.JArr(list)
                let sk = "gh-note"
                let seen0 = Seen(sk)
                let seen = World.SeenList(seen0)
                let fresh = List<Any>()
                for n in ns {
                    let key: String = (World.JS(n, "id") ?? "") + "@" + (World.JS(n, "updated_at") ?? "")
                    if seen0 != nil && !seen.Contains(key) && World.GhReason.ContainsKey(World.JS(n, "reason") ?? "") { fresh.Add(n) }
                    if !seen.Contains(key) { seen.Add(key) }
                }
                SetSeen(sk, World.SeenJoin(seen))
                var i = 0
                while i < fresh.Count && i < 3 {
                    let n = fresh[i]
                    let reason = World.JS(n, "reason") ?? "", type = World.JS(n, "subject", "type")
                    let rf: String = type == "PullRequest" ? "PR" : (type == "Issue" ? "Issue" : "")
                    let url: String = World.GhWeb(World.JS(n, "subject", "url")) ?? ("https://github.com/" + (World.JS(n, "repository", "full_name") ?? ""))
                    var why = ""
                    World.GhReason.TryGetValue(reason, &why)
                    let kind: String = reason == "ci_activity" ? "ci-fail" : "github"
                    let msg: String = (World.JS(n, "repository", "name") ?? "") + " " + why + "：" + rf + " " + NoteLog.Cut(World.JS(n, "subject", "title"), 36)
                    WNotify(kind, url, msg)
                    i += 1
                }
                if fresh.Count > 3 { WNotify("github", "https://github.com/notifications", "GitHub 還有 " + String(fresh.Count - 3) + " 則新通知") }
            }
        }
        let ev = Gh(js, "users/" + ghUser + "/events?per_page=100")
        if ev == nil { return }
        let today = WNow().Date
        let pushes = Dict<String, NoteEntry>()
        for x in World.JArr(ev) {
            let at = World.JT(World.JS(x, "created_at"))
            if at == DateTime.MinValue { continue }
            let type = World.JS(x, "type")
            guard let repo = World.JS(x, "repo", "name") else { continue }
            let name = repo.Substring(repo.IndexOf("/") + 1)
            let pl = World.J(x, "payload")
            if type == "CreateEvent" && World.JS(pl, "ref_type") == "tag" {
                if WOn("ci") { CiCandidate("github", "github.com", nil, repo, name, World.JS(pl, "ref"), at) }
                continue
            }
            if !WOn("github") || at.Date != today { continue }
            if type == "PushEvent" {
                let ref0 = World.JS(pl, "ref") ?? ""
                let br = ref0.Replace("refs/heads/", "")
                if br == "" || ref0.StartsWith("refs/tags/") { continue }
                let commits = World.JA(pl, "commits")
                let n: Int = commits.count > 0 ? commits.count : Math.Max(World.JI(pl, "size"), World.JI(pl, "distinct_size"))
                let msg: String? = commits.count > 0 ? (World.JS(commits[commits.count - 1], "message") ?? "").Split("\n")[0] : nil
                let id = "github:" + repo + ":push:" + br
                let e: NoteEntry
                if let had = pushes.Get(id) { e = had }
                else {
                    e = NoteEntry(); e.Id = id; e.Src = "github"; e.Project = name; e.Key = br; e.Ref = br; e.T = at; e.End = at
                    e.Title = string.IsNullOrEmpty(msg) ? "推到 " + br : msg!; e.Url = "https://github.com/" + repo + "/commits/" + br; e.Status = "0"
                    pushes[id] = e
                }
                if at < e.T { e.T = at }
                if at > e.End { e.End = at; if !string.IsNullOrEmpty(msg) { e.Title = msg! } }
                e.Status = String(int.Parse(e.Status) + Math.Max(0, n))
            }
            else if type == "PullRequestEvent" {
                let act = World.JS(pl, "action")
                let merged = act == "closed" && World.JS(pl, "pull_request", "merged") == "True"
                if act != "opened" && !merged { continue }
                let num = World.JS(pl, "pull_request", "number") ?? World.JS(pl, "number") ?? ""
                let e = NoteEntry()
                e.Id = "github:" + repo + "#" + num + ":" + (merged ? "merged" : "opened"); e.T = at; e.Src = "github"; e.Project = name
                e.Title = World.JS(pl, "pull_request", "title") ?? ("PR #" + num); e.Status = merged ? "合併了" : "開了 PR"; e.Ok = merged ? 1 : -1
                e.Ref = "PR #" + num; e.Url = World.JS(pl, "pull_request", "html_url") ?? ("https://github.com/" + repo + "/pull/" + num)
                e.Key = World.JS(pl, "pull_request", "head", "ref") ?? repo
                NoteLog.Write(e)
            }
        }
        for e in pushes.Values {
            let n = int.Parse(e.Status)
            e.Status = n > 0 ? "推了 " + String(n) + " 個 commit" : "推上去了"
            if e.End == e.T { e.End = DateTime.MinValue }
            NoteLog.Write(e)
        }
    }

    // ================= 盯 CI：從 glab／gh 看到你推了 tag（哪個終端機、哪台電腦推的都算）→ 查 pipeline／workflow 直到跑完 =================
    // 為什麼用「你自己的動態」找：不用設定資料夾、不用在 VS Code 推，只看你真的推過的 repo；GitHub 的動態偶爾會晚一兩分鐘。
    final class CiWatch {
        var Kind = "", Host = "", Repo = "", Name = "", Tag = "", Last = ""
        var Pid: String? = nil, Url: String? = nil
        var Pushed = DateTime.MinValue, NextAt = DateTime.MinValue, Until = DateTime.MinValue
        var Misses = 0
        var Announced = false, Failed = false
        init() {}
    }

    func CiCandidate(_ kind: String, _ host: String, _ pid: String?, _ repo: String, _ name: String?, _ tag: String?, _ pushed: DateTime) {
        if string.IsNullOrEmpty(tag) || (WNow() - pushed).TotalMinutes > 30 { return }
        let key = kind + ":" + repo + ":" + tag!
        let seen = World.SeenList(Seen("ci-seen"))
        if seen.Contains(key) { return }
        seen.Add(key); SetSeen("ci-seen", World.SeenJoin(seen))
        let w = CiWatch()
        w.Kind = kind; w.Host = host; w.Pid = pid; w.Repo = repo; w.Name = name ?? ""; w.Tag = tag!; w.Pushed = pushed
        let s0: Int = App.Offscreen ? 0 : 15
        w.NextAt = DateTime.Now.AddSeconds(s0); w.Until = DateTime.Now.AddMinutes(90)
        lock(ciWatches) { ciWatches.Add(w) }
        App.Log("work ci: watching " + kind + " " + tag!)
    }

    func CiStep(_ js: JavaScriptSerializer, _ force: Bool) {
        let l: List<CiWatch> = lock(ciWatches) { () -> List<CiWatch> in List<CiWatch>(ciWatches) }
        for w in l {
            if DateTime.Now < w.NextAt && !force { continue }
            w.NextAt = DateTime.Now.AddSeconds(20)
            var status: String? = nil, url: String? = nil
            var tool = true
            if w.Kind == "gitlab" {
                let r = Glab(js, w.Host, "projects/" + (w.Pid ?? "") + "/pipelines?ref=" + Uri.EscapeDataString(w.Tag) + "&per_page=1")
                if r == nil { tool = false }
                else { let a = World.JArr(r); if a.count > 0 { status = World.JS(a[0], "status"); url = World.JS(a[0], "web_url") } }
            }
            else {
                let r = Gh(js, "repos/" + w.Repo + "/actions/runs?per_page=20")
                if r == nil { tool = false }
                else {
                    for run in World.JA(r, "workflow_runs") {
                        if World.JS(run, "head_branch") != w.Tag { continue }
                        status = World.JS(run, "status") != "completed" ? "running" : (World.JS(run, "conclusion") == "success" ? "success" : "failed")
                        url = World.JS(run, "html_url")
                        break
                    }
                }
            }
            var end = false
            if !tool || DateTime.Now > w.Until { end = true }
            else if status == nil { w.Misses += 1; if w.Misses > 12 { end = true } }   // 4 分鐘都沒有 pipeline：這個 tag 不跑 CI
            else {
                let st = status!
                w.Url = url
                // mac: where 是 Swift 的關鍵字，改叫 whereS
                let whereS: String = Regex.IsMatch(w.Tag, "Production", RegexOptions.IgnoreCase) ? "正式機" : (Regex.IsMatch(w.Tag, "Development", RegexOptions.IgnoreCase) ? "測試機" : "")
                let failed = st == "failed" || st == "canceled" || st == "cancelled"
                let now: String = st == "success" ? "success" : (failed ? "failed" : "running")
                let head: String = w.Name + " " + w.Tag + " " + whereS
                if now != w.Last {
                    w.Last = now
                    if now == "success" {
                        WNotify("ci-ok", url, head + "部署成功！"); CiLog(w, "CI 過了", 1, true, w.Failed); end = true
                    }
                    else if failed {
                        // 沒過：先講，再多看 3 小時（重跑 pipeline／re-run workflow 之後過了，小本子要寫「第一次沒過，重跑過了」）
                        WNotify("ci-fail", url, head + "部署失敗（" + st + "），點我看 pipeline"); CiLog(w, "CI 沒過", 0, true, false)
                        w.Failed = true; w.Until = DateTime.Now.AddHours(3)
                    }
                    else if !w.Announced && !w.Failed {   // 重跑中不另外講，過了或又沒過才講
                        w.Announced = true; WNotify("ci-run", url, head + "CI 開始跑了，好了叫你"); CiLog(w, "CI 跑起來了", -1, false, false)
                    }
                }
                if w.Failed && !end { w.NextAt = DateTime.Now.AddSeconds(60) }   // 等重跑：慢慢看就好
            }
            if end { lock(ciWatches) { ciWatches.Remove(w) } }
        }
    }
    func CiLog(_ w: CiWatch, _ status: String, _ ok: Int, _ done: Bool, _ retried: Bool) {
        let e = NoteEntry()
        e.Retried = retried
        e.Id = "ci:" + w.Repo + ":" + w.Tag; e.T = w.Pushed; if done { e.End = WNow() }
        e.Src = "ci"; e.Project = w.Name; e.Title = "發 " + w.Tag; e.Status = status; e.Ok = ok; e.Ref = w.Tag; e.Url = w.Url; e.Key = w.Repo
        NoteLog.Write(e)
    }

    // ================= 開會（ICS）：開會前 N 分鐘、開始時提醒；開會中自動安靜 =================
    final class MeetItem {
        var At = 0, End = 0
        var Kind = "", Text = "", Url = "", Key = "", Uid = "", Summary = ""
        var Start = 0
        init() {}
    }
    func WorkMeetUrl() -> String { return WorkOwns("meet") ? (World.WorkUrl(WC("meet_url")) ?? "") : "" }

    func MeetFetch() {
        guard let url = World.WorkUrl(WC("meet_url")) else { return }
        if App.Offscreen && !Regex.IsMatch(url, "^https?://(127\\.0\\.0\\.1|localhost)[:/]") { return }   // 測試不連真的行事曆
        var err = ""
        let text: String? = World.Fetch(url, &err)
        meetErr = err
        if text == nil { return }
        meetText = text!
        MeetPlan()
    }

    func MeetPlan() {
        let url = WC("meet_url")
        let om = Regex.Match(url, "/ical/([^/]+)/")
        let owner: String = om.Success ? Uri.UnescapeDataString(om.Groups[1].Value) : ""
        var cal = ""
        var before = 0
        if !int.TryParse(WC("meet_before"), &before) || before < 1 { before = 5 }
        let now = WNowMs()
        let occ = Ics.Occurrences(Ics.Parse(meetText, owner, &cal), now - 60000, now + 26 * 3600000)
        // 同一時間好幾場 → 合成一則
        let groups = Dict<Int, List<IcsOcc>>()
        let order = List<Int>()
        for o in occ {
            var g: List<IcsOcc>! = groups.Get(o.Start)
            if g == nil { g = List<IcsOcc>(); groups[o.Start] = g; order.Add(o.Start) }
            g.Add(o)
        }
        let plan = List<MeetItem>()
        for start in order {
            guard let g = groups.Get(start), g.Count > 0 else { continue }
            var uid = "", link = ""
            var end = start
            for o in g { uid += (uid == "" ? "" : "+") + (o.Uid ?? ""); if link == "" { link = o.Link ?? "" }; end = Math.Max(end, o.End) }
            let s0: String = g[0].Summary ?? ""
            var summary: String = s0
            if g.Count > 1 {
                let more: String = g.Count > 2 ? " 等 " + String(g.Count) + " 場" : ""
                summary = s0 + "、" + (g[1].Summary ?? "") + more
            }
            let hhmm = World.LocalOfMs(start).ToString("HH:mm")
            let key = uid + "@" + String(start)
            let pre = MeetItem(); pre.At = start - before * 60000; pre.Kind = "meeting"; pre.Url = link; pre.Key = key + "-pre"; pre.Start = start; pre.End = end; pre.Uid = uid; pre.Summary = summary
            pre.Text = hhmm + " 有會：" + summary + "（" + String(before) + " 分鐘後）"
            let go = MeetItem(); go.At = start; go.Kind = "meeting-now"; go.Url = link; go.Key = key + "-now"; go.Start = start; go.End = end; go.Uid = uid; go.Summary = summary
            go.Text = summary + " 開始了！" + (link != "" ? "點我進會議" : "")
            if pre.At > now - 60000 { plan.Add(pre) }
            plan.Add(go)
        }
        lock(meetFired) { meetPlan = plan }
    }

    func MeetTick() {
        let now = WNowMs()
        let fire = List<MeetItem>()
        lock(meetFired) {
            for it in meetPlan {
                if it.At > now || meetFired.Contains(it.Key) { continue }
                meetFired.Add(it.Key)
                if now - it.At > 3 * 60000 { continue }   // 電腦睡著錯過太久的就不補
                fire.Add(it)
            }
        }
        for it in fire {
            WNotify(it.Kind, it.Url, it.Text)
            if it.Kind != "meeting-now" { continue }
            let e = NoteEntry()
            e.Id = "calendar:" + it.Uid + "@" + String(it.Start); e.T = World.LocalOfMs(it.Start); e.End = World.LocalOfMs(it.End)
            e.Src = "calendar"; e.Title = it.Summary; e.Url = it.Url != "" ? it.Url : nil
            NoteLog.Write(e)
            if WOn("meet_quiet") {
                let mins = CInt(Math.Round(Double(it.End - now) / 60000.0))
                if mins > 0 { let q = Math.Min(mins, 240); Post { self.Later(1.5) { self.StartQuiet(q) } } }
            }
        }
    }

    // ================= 下雨：平日 17:30 看一次（等一下下班、下一個上班日）=================
    static let RainCity: Dict<String, [Double]> = {
        let d = Dict<String, [Double]>()
        let rows: [(String, Double, Double)] = [
            ("台北", 25.05, 121.53), ("臺北", 25.05, 121.53), ("新北", 25.01, 121.47), ("桃園", 24.99, 121.31),
            ("新竹", 24.80, 120.97), ("台中", 24.15, 120.67), ("臺中", 24.15, 120.67), ("台南", 22.99, 120.21),
            ("臺南", 22.99, 120.21), ("高雄", 22.63, 120.30), ("基隆", 25.13, 121.74), ("宜蘭", 24.76, 121.75),
            ("花蓮", 23.99, 121.60), ("台東", 22.76, 121.14), ("臺東", 22.76, 121.14), ("嘉義", 23.48, 120.45),
            ("彰化", 24.08, 120.54), ("苗栗", 24.56, 120.82), ("屏東", 22.67, 120.49), ("南投", 23.91, 120.68),
            ("雲林", 23.71, 120.54), ("香港", 22.32, 114.17), ("九龍", 22.32, 114.18), ("澳門", 22.20, 113.55)]
        for r in rows { d[r.0] = [r.1, r.2] }
        return d
    }()
    static let RainCityEn: Dict<String, String> = {
        let d = Dict<String, String>()
        let rows: [(String, String)] = [
            ("台北", "Taipei"), ("臺北", "Taipei"), ("新北", "New Taipei"), ("桃園", "Taoyuan"), ("新竹", "Hsinchu"), ("台中", "Taichung"), ("臺中", "Taichung"),
            ("台南", "Tainan"), ("臺南", "Tainan"), ("高雄", "Kaohsiung"), ("基隆", "Keelung"), ("宜蘭", "Yilan"), ("花蓮", "Hualien"), ("台東", "Taitung"),
            ("臺東", "Taitung"), ("嘉義", "Chiayi"), ("彰化", "Changhua"), ("苗栗", "Miaoli"), ("屏東", "Pingtung"), ("南投", "Nantou"), ("雲林", "Yunlin"),
            ("香港", "Hong Kong"), ("九龍", "Kowloon"), ("澳門", "Macau")]
        for r in rows { d[r.0] = r.1 }
        return d
    }()

    // 測試（只在離屏模式）：DESKPALS_FAKE_WEB＝本機假伺服器，代替 wttr.in／api.met.no
    static func WeatherBase(_ real: String, _ fakePath: String) -> String {
        let f: String? = App.Offscreen ? Environment.GetEnvironmentVariable("DESKPALS_FAKE_WEB") : nil
        return string.IsNullOrEmpty(f) ? real : f!.TrimEnd("/") + fakePath
    }
    static func NextWorkday(_ d: DateTime) -> DateTime {
        var n = d.Date
        repeat { n = n.AddDays(1) } while n.DayOfWeek == DayOfWeek.Saturday || n.DayOfWeek == DayOfWeek.Sunday
        return n
    }

    func RainCheck(_ js: JavaScriptSerializer) {
        let d = WNow()
        let hm = d.Hour * 60 + d.Minute
        if d.DayOfWeek == DayOfWeek.Saturday || d.DayOfWeek == DayOfWeek.Sunday || hm < 17 * 60 + 30 || hm > 19 * 60 { return }
        let k = "rain:" + d.ToString("yyyyMMdd")
        if Seen(k) != nil { return }
        let loc = WC("rain_place").Trim()
        var lat = Double.nan, lon = Double.nan
        var q = loc
        let m = Regex.Match(loc, "^(-?\\d+(?:\\.\\d+)?)\\s*,\\s*(-?\\d+(?:\\.\\d+)?)$")
        if m.Success { lat = double.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture); lon = double.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture); q = m.Groups[1].Value + "," + m.Groups[2].Value }
        else {
            let c = Regex.Replace(loc, "[市縣]$", "")
            if let ll = World.RainCity.Get(c), ll.count >= 2 { lat = ll[0]; lon = ll[1] }
            if let en = World.RainCityEn.Get(c) { q = en }
        }
        var st = 0
        var unit = "%"
        var tonight = -1, next = -1
        var tonightMm: Double = -1, nextMm: Double = -1
        var body = World.HttpGet(World.WeatherBase("https://wttr.in", "/wttr") + "/" + Uri.EscapeDataString(q) + "?format=j1&lang=zh-tw", nil, 20000, &st)
        var j = ParseJson(js, body)
        if j != nil && World.JA(j, "weather").count > 0 {
            tonight = World.WttrMax(j, d, 18, 21)
            next = World.WttrMax(j, World.NextWorkday(d), 6, 21)
        }
        else if !lat.isNaN {
            unit = "mm"
            let la: String = lat.ToString("0.00", CultureInfo.InvariantCulture), lo: String = lon.ToString("0.00", CultureInfo.InvariantCulture)
            body = World.HttpGet(World.WeatherBase("https://api.met.no", "/metno") + "/weatherapi/locationforecast/2.0/compact?lat=" + la + "&lon=" + lo, nil, 20000, &st)
            j = ParseJson(js, body)
            if j == nil { return }
            let nx = World.NextWorkday(d)
            tonightMm = World.MetSum(j, d.Date.AddHours(18), d.Date.AddHours(22))
            nextMm = World.MetSum(j, nx.AddHours(6), nx.AddHours(22))
        }
        else { return }
        SetSeen(k, "1")
        let label: String = d.DayOfWeek == DayOfWeek.Friday ? "下週一" : "明天"
        let parts = List<String>()
        if unit == "%" {
            if tonight >= 50 { parts.Add("等一下下班可能會下雨（降雨機率 " + String(tonight) + "%）") }
            if next >= 50 { parts.Add(label + "降雨機率 " + String(next) + "%") }
        }
        else {
            if tonightMm >= 1 { parts.Add("等一下下班可能會下雨（預估雨量 " + tonightMm.ToString("0.#", CultureInfo.InvariantCulture) + " mm）") }
            if nextMm >= 1 { parts.Add(label + "可能下雨，預估雨量 " + nextMm.ToString("0.#", CultureInfo.InvariantCulture) + " mm") }
        }
        if parts.Count > 0 { WNotify("rain", "-", string.Join("，", parts.ToArray()) + "，記得帶傘 ☔") }
    }
    static func WttrMax(_ j: Any?, _ day: DateTime, _ from: Int, _ to: Int) -> Int {
        let ymd = day.ToString("yyyy-MM-dd")
        var mx = -1
        for w in JA(j, "weather") {
            if JS(w, "date") != ymd { continue }
            for h in JA(w, "hourly") {
                let hr = JI(h, "time") / 100
                if hr >= from && hr <= to { mx = Math.Max(mx, Math.Max(0, JI(h, "chanceofrain"))) }
            }
        }
        return mx
    }
    static func MetSum(_ j: Any?, _ from: DateTime, _ to: DateTime) -> Double {
        var mm = 0.0
        var anyMm = false   // mac: any 是 Swift 的關鍵字，改叫 anyMm
        for t in JA(j, "properties", "timeseries") {
            let at = JT(JS(t, "time"))
            if at < from || at >= to { continue }
            let v = JS(t, "data", "next_1_hours", "details", "precipitation_amount")
            var x = 0.0
            if v != nil && double.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, &x) { mm += x; anyMm = true }
        }
        return anyMm ? Math.Round(mm * 10) / 10 : -1
    }

    // ================= 工作日誌資料夾：今天出現新檔就說 =================
    func WorklogCheck() {
        let dir = WC("worklog_dir")
        if !Directory.Exists(dir) { return }
        var newest: FileInfo? = nil
        for f in DirectoryInfo(dir).EnumerateFiles() {
            if Regex.IsMatch(f.Name, "\\.(md|txt|docx?|xlsx?)$", RegexOptions.IgnoreCase) && (newest == nil || f.LastWriteTimeUtc > newest!.LastWriteTimeUtc) { newest = f }
        }
        guard let nf = newest else { return }
        let k = "worklog:" + dir, t = String(nf.LastWriteTimeUtc.Ticks)
        let last = Seen(k)
        SetSeen(k, t)
        if last == nil || string.CompareOrdinal(t.PadLeft(20, "0"), last!.PadLeft(20, "0")) <= 0 { return }
        if nf.LastWriteTime.Date == DateTime.Now.Date { WNotify("worklog", Uri(nf.FullName).AbsoluteUri, "今天的工作日誌好了：" + nf.Name) }
    }

    // ================= Claude Code／Codex：做完的對話寫進小本子 =================
    // ~/.claude、~/.codex 的預設位置（CLAUDE_CONFIG_DIR／CODEX_HOME 沒設時）。
    // 離屏（測試，含 DESKPALS_ISOLATED）一律改成資料資料夾裡的空資料夾：測試絕不讀使用者真的對話紀錄
    static func AiHomeDefault(_ name: String) -> String { return UserFolder(Environment.SpecialFolder.UserProfile, name, name) }

    // 使用者的資料夾（家目錄、下載、圖片、桌面）。離屏（測試）一律換成資料資料夾裡的 test-home 底下的空資料夾，絕不碰真的
    // mac: GetFolderPath → ~、~/Pictures、~/Desktop（00_compat）
    static func UserFolder(_ f: Environment.SpecialFolder, _ sub: String?, _ testName: String) -> String {
        if !App.Offscreen {
            let real = Environment.GetFolderPath(f)
            return string.IsNullOrEmpty(sub) ? real : Path.Combine(real, sub!)
        }
        let d = Path.Combine(World.DataDir, "test-home", testName)
        do { try Directory.CreateDirectory(d) } catch {}
        return d
    }

    // 「下載好了」看的資料夾：DESKPALS_DOWNLOADS_DIR 有設就用它，不然是家目錄的 Downloads（離屏：test-home 的 Downloads）
    static func DownloadsDir() -> String {
        let e = Environment.GetEnvironmentVariable("DESKPALS_DOWNLOADS_DIR")
        return !string.IsNullOrEmpty(e) ? e! : UserFolder(Environment.SpecialFolder.UserProfile, "Downloads", "Downloads")
    }

    // 進階：別的資料夾（WSL 裡的 Claude／Codex）。給 .claude 或 .claude\projects 都可以
    // mac: 沒有 WSL；有填、而且是本機存在的資料夾才多看這一個（設定視窗不顯示這一欄）
    func WorkClaudeRoots() -> List<String> {
        let l = List<String>()
        l.Add(World.ClaudeProjectsDir())
        let c = WC("claude_dir")
        if c != "" && Directory.Exists(c) {
            let p = Directory.Exists(Path.Combine(c, "projects")) ? Path.Combine(c, "projects") : c
            if !l.Exists({ (x: String) -> Bool in string.Equals(x.TrimEnd("\\", "/"), p.TrimEnd("\\", "/"), StringComparison.OrdinalIgnoreCase) }) { l.Add(p) }
        }
        return l.FindAll { (x: String) -> Bool in Directory.Exists(x) }
    }
    func WorkCodexRoots() -> List<String> {
        let l = List<String>()
        l.Add(World.CodexSessionsDir())
        let c = WC("codex_dir")
        if c != "" && Directory.Exists(c) {
            let p = Directory.Exists(Path.Combine(c, "sessions")) ? Path.Combine(c, "sessions") : c
            if !l.Exists({ (x: String) -> Bool in string.Equals(x.TrimEnd("\\", "/"), p.TrimEnd("\\", "/"), StringComparison.OrdinalIgnoreCase) }) { l.Add(p) }
        }
        return l.FindAll { (x: String) -> Bool in Directory.Exists(x) }
    }
    // WSL 裡跑的 claude／codex 在 Windows 這邊看不到行程：有設別的資料夾、WSL 開著就當作有在跑
    // mac: 沒有 WSL，一律 false
    func WorkWslAlive(_ key: String) -> Bool {
        _ = key
        return false
    }

    func AiScan(_ js: JavaScriptSerializer) {
        let now = DateTime.Now
        for root in WorkClaudeRoots() {
            for pdir in Directory.GetDirectories(root) {
                for fi in DirectoryInfo(pdir).EnumerateFiles("*.jsonl") {
                    if fi.Name.StartsWith("agent-") { continue }
                    let mt = fi.LastWriteTime
                    if mt.Date != now.Date || (now - mt).TotalSeconds < 60 { continue }   // 還在寫的先不記
                    var was = DateTime.MinValue
                    if aiLogged.TryGetValue(fi.FullName, &was) && was == mt { continue }
                    var tool: String? = nil, title: String? = nil
                    let kind = World.ClaudeState(js, fi.FullName, &tool, &title)
                    if kind != "idle" && (now - mt).TotalMinutes < 10 { continue }      // 還沒講完（等工具、在想）：晚點再看
                    aiLogged[fi.FullName] = mt
                    if NoteLog.Write(ClaudeEntry(js, fi)) { aiWritten += 1 }
                }
            }
        }
        for root in WorkCodexRoots() {
            for back in 0..<7 {
                let dd = now.Date.AddDays(-back)
                let dir = Path.Combine(root, dd.ToString("yyyy"), dd.ToString("MM"), dd.ToString("dd"))
                if !Directory.Exists(dir) { continue }
                for fi in DirectoryInfo(dir).EnumerateFiles("rollout-*.jsonl") {
                    let mt = fi.LastWriteTime
                    if mt.Date != now.Date || (now - mt).TotalSeconds < 60 { continue }
                    var was = DateTime.MinValue
                    if aiLogged.TryGetValue(fi.FullName, &was) && was == mt { continue }
                    let st = World.ParseCodex(fi.FullName)
                    if st.Busy || st.LastComplete == DateTime.MinValue { if (now - mt).TotalMinutes < 10 { continue } }
                    aiLogged[fi.FullName] = mt
                    if NoteLog.Write(CodexEntry(js, fi, st)) { aiWritten += 1 }
                }
            }
        }
        if aiLogged.Count > 2000 { aiLogged.Clear() }
    }

    static let TsRx = Regex("\"timestamp\":\"([^\"]+)\"")
    static let AiTitleRx = Regex("^\\{\"type\":\"ai-title\"")

    // 對話的第一句需求（去掉指令、系統訊息、IDE 附帶的標籤），太長就剪
    static func FirstAsk(_ s0: String?) -> String? {
        guard var s = s0 else { return nil }
        s = Regex.Replace(s, "<(ide_[a-z_]+|system-reminder|environment_context|user_instructions|command-[a-z]+)>[\\s\\S]*?</\\1>", " ")
        s = NoteLog.OneLine(s)
        if s == "" || s.StartsWith("<") || s.StartsWith("[Request interrupted") || s.StartsWith("Caveat:") { return nil }
        return NoteLog.Cut(s, 40)
    }
    static func UserText(_ content: Any?) -> String? {
        if let s = content as? String { return FirstAsk(s) }
        guard let arr = content as? [Any] else { return nil }
        for o in arr {
            if JS(o, "type") != "text" { continue }
            if let t = FirstAsk(JS(o, "text")) { return t }
        }
        return nil
    }
    static func UtcLocal(_ iso: String?) -> DateTime {
        var t = DateTime.MinValue
        if iso != nil && DateTime.TryParse(iso, CultureInfo.InvariantCulture, [DateTimeStyles.AdjustToUniversal, DateTimeStyles.AssumeUniversal], &t) { return t.ToLocalTime() }
        return DateTime.MinValue
    }
    // mac: C# 的 Path.GetFileName（Windows）把 \ / : 都當分隔字元；對話的 cwd 可能是 Windows 路徑，照 Windows 的結果取最後一段
    static func WorkFileName(_ p: String) -> String {
        if let i = p.lastIndex(where: { $0 == "/" || $0 == "\\" || $0 == ":" }) { return String(p[p.index(after: i)...]) }
        return p
    }

    func ClaudeEntry(_ js: JavaScriptSerializer, _ fi: FileInfo) -> NoteEntry? {
        let big = 3 * 1024 * 1024, mb = 1024 * 1024
        let text: String = fi.Length <= big ? World.Tail(fi.FullName, big) : World.Head(fi.FullName, mb) + "\n" + World.Tail(fi.FullName, mb)
        let lines = text.Split("\n")
        var cwd: String? = nil, ask: String? = nil, aiTitle: String? = nil
        var t0 = DateTime.MinValue, t1 = DateTime.MinValue
        let firstOn = Dict<DateTime, DateTime>()   // 每一天的第一筆（同一個對話開好幾天：那天的紀錄從那天開始算）
        for raw in lines {
            let l = raw.Trim()
            if l.Length < 2 { continue }
            if World.AiTitleRx.IsMatch(l) { let at = World.JS(ParseJson(js, l), "aiTitle"); if !string.IsNullOrEmpty(at) { aiTitle = at }; continue }
            let probe: String = l.Length > 4000 ? l.Substring(0, 4000) + l.Substring(Math.Max(4000, l.Length - 4000)) : l
            let tm = World.TsRx.Match(probe)
            if tm.Success {
                let t = World.UtcLocal(tm.Groups[1].Value)
                if t != DateTime.MinValue { if t0 == DateTime.MinValue { t0 = t }; if !firstOn.ContainsKey(t.Date) { firstOn[t.Date] = t }; t1 = t }
            }
            if ask != nil && cwd != nil { continue }
            if l.IndexOf("\"type\":\"user\"", StringComparison.Ordinal) < 0 || l.IndexOf("\"isSidechain\":true", StringComparison.Ordinal) >= 0 { continue }
            let d = ParseJson(js, l.Length > 400000 ? nil : l)
            if d == nil || World.JS(d, "type") != "user" || World.JS(d, "isMeta") == "True" { continue }
            if cwd == nil { cwd = World.JS(d, "cwd") }
            if ask == nil { ask = World.UserText(World.J(d, "message", "content")) }
        }
        let title: String? = !string.IsNullOrEmpty(aiTitle) ? NoteLog.Cut(aiTitle, 60) : ask
        if title == nil || t0 == DateTime.MinValue { return nil }
        var td = DateTime.MinValue
        if t1.Date != t0.Date && firstOn.TryGetValue(t1.Date, &td) { t0 = td }
        let e = NoteEntry()
        e.Id = "claude:" + Path.GetFileNameWithoutExtension(fi.Name); e.T = t0; e.End = t1 > t0 ? t1 : DateTime.MinValue
        e.Src = "claude"; e.Title = title
        e.Project = cwd != nil ? World.WorkFileName(cwd!.TrimEnd("\\", "/")) : World.ProjectFromFolder(fi.Directory.Name)
        e.Key = e.Project
        return e
    }
    // Claude 的資料夾名字是把路徑的 \ / : 換成 -（c--tmp-dp-wt-work）：取最後一段（不完美，只在讀不到 cwd 時用）
    static func ProjectFromFolder(_ n: String) -> String { let i = n.LastIndexOf("-"); return i >= 0 && i < n.Length - 1 ? n.Substring(i + 1) : n }

    func CodexEntry(_ js: JavaScriptSerializer, _ fi: FileInfo, _ st: CodexState) -> NoteEntry? {
        let head = World.Head(fi.FullName, 2 * 1024 * 1024)
        var id: String? = nil, cwd: String? = nil, ask: String? = nil
        var t0 = DateTime.MinValue
        for raw in head.Split("\n") {
            let l = raw.Trim()
            if l.Length < 2 { continue }
            if id == nil && l.IndexOf("\"type\":\"session_meta\"", StringComparison.Ordinal) >= 0 {
                let d = ParseJson(js, l)
                id = World.JS(d, "payload", "id"); cwd = World.JS(d, "payload", "cwd")
                t0 = World.UtcLocal(World.JS(d, "payload", "timestamp") ?? World.JS(d, "timestamp"))
                continue
            }
            if ask == nil && l.IndexOf("\"user_message\"", StringComparison.Ordinal) >= 0 && l.Length < 400000 {
                let d = ParseJson(js, l)
                if World.JS(d, "payload", "type") == "user_message" { ask = World.FirstAsk(World.JS(d, "payload", "message")) }
            }
            if id != nil && ask != nil { break }
        }
        if ask == nil { return nil }
        if t0 == DateTime.MinValue { let tm = World.TsRx.Match(head); if tm.Success { t0 = World.UtcLocal(tm.Groups[1].Value) } }
        if t0 == DateTime.MinValue { return nil }
        if id == nil { let m = Regex.Match(fi.Name, "([0-9a-f]{8}-[0-9a-f-]{27,})\\.jsonl$"); id = m.Success ? m.Groups[1].Value : Path.GetFileNameWithoutExtension(fi.Name) }
        let e = NoteEntry()
        e.Id = "codex:" + id!; e.T = t0
        e.End = st.LastComplete != DateTime.MinValue ? st.LastComplete.ToLocalTime() : fi.LastWriteTime
        if e.End != DateTime.MinValue && e.End.Date != e.T.Date {
            // 同一個對話開好幾天：那天的紀錄從那天的第一筆開始算
            for raw in World.Tail(fi.FullName, 1024 * 1024).Split("\n") {
                // mac: CodexRx 在 41_world_b 是 NSRegularExpression，用 RxMatch（[1]＝時間）
                let probe: String = raw.Length > 400 ? raw.Substring(0, 400) : raw
                guard let tm = World.RxMatch(World.CodexRx, probe) else { continue }
                let t = World.UtcLocal(tm[1])
                if t.Date == e.End.Date { e.T = t; break }
            }
        }
        if e.End <= e.T { e.End = DateTime.MinValue }
        e.Src = "codex"; e.Title = ask
        e.Project = cwd != nil ? World.WorkFileName(cwd!.TrimEnd("\\", "/")) : nil; e.Key = e.Project
        return e
    }

    // ================= 學校行事曆的上課也進小本子（DeskPals.Study.cs 的 PlanTick 叫）=================
    func WorkLogClass(_ it: SchoolPlanItem) {
        let e = NoteEntry()
        let name = Regex.Replace(it.Text ?? "", "（點我打開）$", "")
        e.Id = "school:" + (it.Key ?? ""); e.T = World.LocalOfMs(it.At); if it.QuietMin > 0 { e.End = World.LocalOfMs(it.At + it.QuietMin * 60000) }
        e.Src = "school"; e.Project = name; e.Title = "上課：" + name; e.Url = it.Url != "" ? it.Url : nil
        NoteLog.Write(e)
    }

    // ================= 設定視窗（畫面還在挑版：先留入口，給小屋選單和小本子的「來源」按鈕叫）=================
    // 工作設定視窗在 DeskPals.WorkSettings.cs（ShowWorkSettings）；看的方式（格子／清單、上次選的來源）記在 work-ui.txt
    static func ReadWorkUi() -> String { return World.ReadText("work-ui.txt") }
    static func WriteWorkUi(_ s: String) { World.WriteText("work-ui.txt", s) }

    // 小本子（DeskPals.Notebook.cs）用的兩個接點（v011 SPEC 2b）：「來源」按鈕、空白頁的「接上」
    func OpenWorkSettings() { ShowWorkSettings() }
    // 空白頁的「接上」：直接打開那個來源（calendar＝開會；school 在讀書小幫手設定）
    func OpenWorkSettings(_ key: String?) {
        if key == "school" { ShowStudySettings(); return }
        let src: String? = key == "calendar" ? "meet" : key
        ShowWorkSettings(src)
    }

    // 空白頁那張清單：這個來源接上了沒（claude｜school｜calendar｜github｜gitlab｜jira）
    func WorkSourceOn(_ key: String) -> Bool {
        switch key {
        case "claude": return WOn("ai")
        case "school": if !studyLoaded { LoadStudy() }; return haveSchool
        case "calendar": return WorkOwns("meet")
        case "github", "gitlab", "jira": return WorkOwns(key)
        default: break
        }
        return false
    }

    // ================= pipe =================
    func WorkMsg(_ c: Client, _ p: [String], _ line: String) -> Bool {
        if p.count == 0 || !p[0].StartsWith("work-") { return false }
        WorkLoad()
        let t = line.Trim()
        let sp = t.IndexOf(" ")
        let rest: String = sp > 0 ? t.Substring(sp + 1) : ""
        switch p[0] {
        case "work-set":
            if p.count >= 2 {
                let s2 = rest.IndexOf(" ")
                let v: String = s2 > 0 ? rest.Substring(s2 + 1) : ""
                if !WorkSet(p[1], v) { World.Send(c, "work-set bad " + p[1] + "\n") }
            }
            return true
        case "work-token": SetJiraToken(rest); return true
        case "work-poll": workPollNow = true; if workWake != nil { workWake.Set() }; return true
        case "work-dump": World.Send(c, WorkDump()); return true
        case "work-settings": return WorkSettingsMsg(c, p, line)   // 設定視窗（DeskPals.WorkSettings.cs）
        case "work-clock":
            if !App.Offscreen { return true }
            do {
                var want = DateTime.MinValue
                var ok = false
                if p.count >= 2 { ok = DateTime.TryParse(p[1], CultureInfo.InvariantCulture, DateTimeStyles.None, &want) }
                workShift = ok ? want - DateTime.Now : TimeSpan.Zero
            }
            if meetText != "" { MeetPlan() }
            return true
        case "work-vpncheck":
            if !App.Offscreen { return true }
            do {
                let h = companyHost
                let r: String = h == "" ? "none" : (World.VpnReachable(h) ? "ok" : "down")
                World.Send(c, "work-vpn " + r + " " + h + "\n")
            }
            return true
        case "work-forget":
            if !App.Offscreen { return true }
            lock(wcfg) { wseen.Clear(); seenDirty = true }
            lock(meetFired) { meetFired.Clear() }
            aiLogged.Clear()
            return true
        default: break
        }
        return true
    }

    func WorkDump() -> String {
        let sb = StringBuilder("work")
        lock(wcfg) {
            for d in World.WorkDefaults {
                let v = wcfg.Get(d[0]) ?? ""
                let shown: String = v == "" ? "-" : v.Replace(" ", "_")
                sb.Append(" " + d[0] + "=" + shown)
            }
        }
        let tok: String = HasJiraToken() ? "1" : "0"
        let nowS: String = WNow().ToString("yyyy-MM-ddTHH:mm", CultureInfo.InvariantCulture)
        let tl: String = " token=" + tok + " now=" + nowS + "\n"
        sb.Append(tl)
        sb.Append(WorkOwnLine())
        let hostS: String = companyHost == "" ? "-" : companyHost
        let jiraS: String = jiraStatus == "" ? "-" : jiraStatus.Replace(" ", "_")
        let glabS: String = glabState == "" ? "-" : glabState
        let ghS: String = ghState == "" ? "-" : ghState
        let ghU: String = ghUser == "" ? "-" : ghUser
        let quietS: Int = quietOn ? QuietLeft() : 0
        let meetE: String = meetErr != "" ? " meeterr=" + meetErr.Replace(" ", "_") : ""
        var st: String = "work-state host=" + hostS + " jira=" + jiraS + " glab=" + glabS
        st += " gh=" + ghS + " ghuser=" + ghU + " dropped=" + String(workDropped)
        st += " polled=" + String(workPolled) + " ai=" + String(aiWritten)
        st += " quiet=" + String(quietS) + " meets=" + String(meetPlan.Count) + meetE + "\n"
        sb.Append(st)
        let cr: String = string.Join("|", WorkClaudeRoots().ToArray()).Replace(" ", "_")
        let xr: String = string.Join("|", WorkCodexRoots().ToArray()).Replace(" ", "_")
        let hc: String = World.ClaudeProjectsDir().Replace(" ", "_")
        let hx: String = World.CodexSessionsDir().Replace(" ", "_")
        let dl: String = World.DownloadsDir().Replace(" ", "_")
        let pic: String = World.UserFolder(Environment.SpecialFolder.MyPictures, "", "Pictures").Replace(" ", "_")
        let desk: String = World.UserFolder(Environment.SpecialFolder.DesktopDirectory, "", "Desktop").Replace(" ", "_")
        let dat: String = World.DataDir.Replace(" ", "_")
        var rt: String = "work-roots claude=" + cr + " codex=" + xr
        rt += " home-claude=" + hc + " home-codex=" + hx
        rt += " downloads=" + dl + " pictures=" + pic + " desktop=" + desk + " data=" + dat + "\n"
        sb.Append(rt)
        lock(ciWatches) {
            for w in ciWatches {
                let run: String = w.Announced ? " running" : ""
                let wl: String = "watch " + w.Kind + " " + w.Repo + " " + w.Tag + run + "\n"
                sb.Append(wl)
            }
        }
        lock(workNotices) { for n in workNotices { sb.Append("notice " + n + "\n") } }
        sb.Append("end\n")
        return sb.ToString()
    }
}
