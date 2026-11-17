// 61_stats.swift — port of DeskPals.Stats.cs（匿名回報：只有公開版；個人版 App.Public＝false，什麼都不送）
// 只送 lineup_pick（第一次設定選了哪一櫃）、day7_active（滿 7 天第一次打開時開著哪一櫃，只一次）到 GA4 Measurement Protocol。
// client_id 每次都是新的亂數（本機不存 ID）；ID 打包時注入 pals/ga4.txt（沒有＝停用）；送不出去就算了（不重試、不排隊、不卡畫面）。
// 測試：DESKPALS_GA4_CONFIG＝另一份 ga4.txt、DESKPALS_GA4_URL＝假的端點（test/desktop-store.js）；離屏、CI 沒有假端點一律不送。
// mac: HttpWebRequest → URLSession（ephemeral、5 秒逾時、不跟隨轉址）。URLSession 預設會帶 User-Agent（含 macOS 版本）和
//   Accept-Language（你的語系）：這裡固定成 "DeskPals" 和 "*"，跟 Windows 一樣不帶系統資訊。Platform 一律 "mac"（.app、VS Code 擴充套件都是）。
import Foundation
import AppKit

enum Stats {
    static let DefaultUrl = "https://www.google-analytics.com/mp/collect"
    static var Platform = "mac"
    static var loaded = false
    static var mid: String? = nil
    static var secret: String? = nil
    static var ver = ""

    static func Matches(_ s: String, _ pattern: String) -> Bool { return s.range(of: pattern, options: .regularExpression) != nil }

    // 打包時注入的 ID（pals/ga4.txt；測試可用 DESKPALS_GA4_CONFIG 指另一份）
    static func Load() {
        if loaded { return }
        loaded = true
        if !App.Public { return }
        var text: String? = nil
        let cfg: String = ProcessInfo.processInfo.environment["DESKPALS_GA4_CONFIG"] ?? ""
        if !cfg.isEmpty { if File.Exists(cfg) { text = try? File.ReadAllText(cfg) } }
        else { text = SqArt.ReadText("ga4.txt") }
        guard let all = text else { return }
        var m: String? = nil
        var s: String? = nil
        for line in all.components(separatedBy: "\n") {
            let t: String = line.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eq = t.firstIndex(of: "=") else { continue }
            if eq == t.startIndex { continue }
            let k: String = String(t[t.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            let v: String = String(t[t.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if k == "measurement_id" { m = v }
            else if k == "api_secret" { s = v }
            else if k == "version" { ver = v }
        }
        guard let mm = m, let ss = s, Matches(mm, "^G-[A-Z0-9]{4,20}$"), Matches(ss, "^[A-Za-z0-9_-]{8,64}$") else { App.Log("stats: ga4.txt incomplete, disabled"); return }
        if !Matches(ver, "^[0-9A-Za-z.+-]{1,32}$") { ver = "unknown" }
        mid = mm
        secret = ss
    }

    // 這一份能回報嗎（公開版＋有 ID）
    static var Available: Bool { Load(); return mid != nil }
    static var AppVersion: String { Load(); return ver }

    // 櫃的名字（只有這三種；其他一律 other）
    static func LineupKey(_ lu: String) -> String {
        if lu == Pal.Mine { return "custom" }
        if lu == "original" || lu == "woban" { return lu }
        return "other"
    }

    // 每次都是新的亂數（GA4 要的格式：數字.數字），不存。mac: SystemRandomNumberGenerator（系統的密碼學亂數）
    static func NewClientId() -> String {
        let a: UInt32 = UInt32.random(in: 0..<1000000000) + 100000000
        let c: UInt32 = UInt32.random(in: 0..<1000000000) + 100000000
        return String(a) + "." + String(c)
    }

    static func J(_ s: String) -> String {
        var o = "\""
        for u in s.unicodeScalars {
            if u == "\"" || u == "\\" { o += "\\"; o.unicodeScalars.append(u) }
            else if u.value < 0x20 { o += String(format: "\\u%04x", u.value) }
            else { o.unicodeScalars.append(u) }
        }
        return o + "\""
    }

    // 要送的內容（全部就這些）
    static func Payload(_ ev: String, _ lineup: String) -> String {
        let a: String = "{\"client_id\":" + J(NewClientId()) + ",\"non_personalized_ads\":true,\"events\":[{\"name\":" + J(ev)
        let b: String = ",\"params\":{\"lineup\":" + J(LineupKey(lineup)) + ",\"app_version\":" + J(AppVersion)
        let c: String = ",\"platform\":" + J(Platform) + "}}]}"
        return a + b + c
    }

    // 測試／CI 不能送到 Google：離屏模式、CI 上一定要指定假端點
    static func Url() -> String? {
        let env = ProcessInfo.processInfo.environment
        let u: String = env["DESKPALS_GA4_URL"] ?? ""
        if !u.isEmpty { return u }
        let ci: Bool = !(env["GITHUB_ACTIONS"] ?? "").isEmpty || !(env["CI"] ?? "").isEmpty
        if App.Offscreen || ci { return nil }
        return DefaultUrl
    }

    final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.timeoutIntervalForResource = 5
        cfg.httpCookieStorage = nil
        cfg.urlCache = nil
        return URLSession(configuration: cfg, delegate: NoRedirect(), delegateQueue: nil)
    }()

    // 背景送一次；失敗就算了。回傳 false＝沒有送（沒有 ID、測試環境沒有假端點）
    @discardableResult static func Send(_ ev: String, _ lineup: String) -> Bool {
        if !Available { return false }
        guard let base = Url() else { App.Log("stats: " + ev + " skipped (test environment)"); return false }
        guard let m = mid, let s = secret else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let q: String = base.contains("?") ? "&" : "?"
        let em: String = m.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let es: String = s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let full: String = base + q + "measurement_id=" + em + "&api_secret=" + es
        guard let url = URL(string: full) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("DeskPals", forHTTPHeaderField: "User-Agent")
        req.setValue("*", forHTTPHeaderField: "Accept-Language")
        req.httpBody = Payload(ev, lineup).data(using: .utf8)
        let task = session.dataTask(with: req) { _, resp, err in
            if let h = resp as? HTTPURLResponse { App.Log("stats: " + ev + " sent (" + String(h.statusCode) + ")") }
            else { let why: String = err != nil ? "error" : "no response"; App.Log("stats: " + ev + " not sent (" + why + ")") }
        }
        task.resume()
        return true
    }
}

//@@IN World
    let statsState = Dict<String, String>()
//@@END

extension World {
    func StatsLoad() {
        statsState.Clear()
        for line in World.ReadText("anon-stats.txt").components(separatedBy: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            if eq == line.startIndex { continue }
            let k: String = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            let v: String = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            statsState[k] = v
        }
    }
    func StatsSave() {
        let sb = StringBuilder()
        for k in ["on", "installed", "pick", "day7"] {
            var v = ""
            if statsState.TryGetValue(k, &v) { sb.Append(k + "=" + v + "\n") }
        }
        World.WriteText("anon-stats.txt", sb.ToString())
    }
    func StatsGet(_ k: String) -> String { var v = ""; return statsState.TryGetValue(k, &v) ? v : "" }
    var StatsOn: Bool { return Stats.Available && StatsGet("on") != "0" }

    // mac: DateTime.ParseExact／ToString("yyyy-MM-dd") → DateFormatter（公曆、本地時間的那一天）
    static func StatsFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    // Start 裡：滿 7 天後第一次打開 → day7_active（只送一次）
    func StatsStart() {
        if !App.Public { return }
        StatsLoad()
        if StatsGet("day7") != "" || StatsGet("pick") != "sent" { return }
        guard let inst = World.StatsFormatter().date(from: StatsGet("installed")) else { return }
        let cal = Calendar(identifier: .gregorian)
        let days: Int = cal.dateComponents([.day], from: cal.startOfDay(for: inst), to: cal.startOfDay(for: Date())).day ?? 0
        if days < 7 { return }
        if StatsOn && !Stats.Send("day7_active", lineup) { return }   // 測試環境沒假端點：下次再看
        statsState["day7"] = "done"
        StatsSave()
    }

    // 第一次設定完成（ApplySetup）：記下日期、送 lineup_pick
    func StatsPicked(_ lu: String) {
        if !App.Public { return }
        StatsLoad()
        if StatsGet("installed") == "" { statsState["installed"] = World.StatsFormatter().string(from: Date()) }
        if StatsGet("pick") == "" && StatsOn && Stats.Send("lineup_pick", lu) { statsState["pick"] = "sent" }
        StatsSave()
    }

    // 小屋的開關（有 ID 的公開版才有）
    func StatsHouseMenu(_ items: ToolStripItemCollection) {
        if !Stats.Available { return }
        let mi = ToolStripMenuItem("匿名回報選了哪一櫃（幫我們決定下一櫃）")
        mi.CheckOnClick = true
        mi.Checked = StatsOn
        mi.Click = { [unowned mi] in self.StatsSet(!self.StatsOn); mi.Checked = self.StatsOn }
        items.Add(mi)
    }
    func StatsSet(_ on: Bool) {
        if !Stats.Available { return }
        StatsLoad()
        statsState["on"] = on ? "1" : "0"
        StatsSave()
        App.Log("stats: " + (on ? "on" : "off"))
        Lead().Say(on ? "好～會匿名回報你選了哪一櫃" : "好～不回報了，什麼都不會送出去", 2)
    }
    func StatsAct(_ arg: String) { if arg == "0" || arg == "1" { StatsSet(arg == "1") } }

    static func StatsDash(_ s: String) -> String { return s == "" ? "-" : s }

    // 測試用：stats-dump、stats-payload <事件> <櫃>
    func StatsMsg(_ c: Client, _ p: [String], _ line: String) -> Bool {
        switch p[0] {
        case "stats-dump":
            StatsLoad()
            // mac: 拆成好幾段（Swift 型別推斷吃不下一整串 + 和 ?:）
            var s: String = "stats public=" + (App.Public ? "1" : "0")
            s += " available=" + (Stats.Available ? "1" : "0")
            s += " on=" + (StatsOn ? "1" : "0")
            s += " installed=" + World.StatsDash(StatsGet("installed")) + " pick=" + World.StatsDash(StatsGet("pick")) + " day7=" + World.StatsDash(StatsGet("day7"))
            let ver: String = Stats.Available ? Stats.AppVersion : "-"
            s += " platform=" + Stats.Platform + " version=" + ver + "\nend\n"
            World.Send(c, s)
            return true
        case "stats-payload":
            let body: String = p.count >= 3 && Stats.Available ? Stats.Payload(p[1], p[2]) : "-"
            World.Send(c, body + "\nend\n")
            return true
        default:
            return false
        }
    }
}
