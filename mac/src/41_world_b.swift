// 41_world_b.swift — port of DeskPals.cs lines 6820–8107
// Claude／Codex 監看、串場（Cue／scenes）、SpriteForm、小道具（Prop）、離屏測試模式（Snap／SimClick／SimDrop）

import Foundation
import AppKit

// ================= Claude／Codex 監看（背景執行緒）=================
//@@IN World
    var stuck = Dict<String, World.StuckInfo>()
    var codexSeen = Dict<String, World.CodexSeen>()
    var claudeStart = Dict<String, Double>()
    var codexFiles = List<String>()
    var busyClaude = 0, busyCodex = 0
    var stuckNow = false
    var doneUntil: Double = 0
//@@END

extension World {
    final class StuckInfo { var Episode = 0; var Alerts = 0; var NextAt = DateTime.MinValue }
    final class CodexSeen { var LastComplete = DateTime.MinValue }

    // 狀態：stuck／done／busy／""（小波的肚子螢幕、其他人頭旁邊的小圖示）
    func Status() -> String {
        if stuckNow { return "stuck" }
        if Now < doneUntil { return "done" }
        if busyClaude + busyCodex > 0 { return "busy" }
        return ""
    }

    static func ClaudeProjectsDir() -> String {
        var cfg = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR")
        if string.IsNullOrEmpty(cfg) { cfg = Path.Combine(NSHomeDirectory(), ".claude") }
        return Path.Combine(cfg!, "projects")
    }

    static func CodexSessionsDir() -> String {
        var home = Environment.GetEnvironmentVariable("CODEX_HOME")
        if string.IsNullOrEmpty(home) { home = Path.Combine(NSHomeDirectory(), ".codex") }
        return Path.Combine(home!, "sessions")
    }

    func WatchLoop() {
        Thread.Sleep(8000)
        let js = JavaScriptSerializer()
        var n = 0
        while !closing {
            do { if n % 3 == 0 { try ClaudeWatchOnce(js) } } catch { App.Log("claude watch: " + "\(error)") }
            do { try CodexWatchOnce(n % 6 == 0) } catch { App.Log("codex watch: " + "\(error)") }
            n += 1
            Thread.Sleep(5000)
        }
    }

    // 共用的卡住判斷：quiet 秒沒動靜、kind＝tool/model
    func StuckCheck(_ key: String, _ src: String, _ act: DateTime, _ kind: String?, _ tool: String?, _ title: String?, _ running: Bool) {
        let now = DateTime.UtcNow
        var si: StuckInfo! = nil
        if !stuck.TryGetValue(key, &si) || si == nil { si = StuckInfo(); stuck[key] = si }
        let quiet = (now - act).TotalSeconds
        if quiet < 85 {
            if si.Alerts > 0 { si.Alerts = 0; let s2 = src; Post { [self] in OnUnstuck(s2) } }
            return
        }
        if kind == nil || kind == "idle" || !running { si.Alerts = 0; return }
        let ask = tool == "AskUserQuestion" || tool == "ExitPlanMode" || tool == "request_user_input"
        let limit: Double = kind == "tool" ? (ask ? 90 : 180) : 300
        if quiet < limit { return }
        if si.Episode != act.Ticks { si.Episode = act.Ticks; si.Alerts = 0 }
        if si.Alerts >= 3 || (si.Alerts > 0 && now < si.NextAt) { return }
        si.Alerts += 1
        si.NextAt = now.AddMinutes(10)
        let min = Math.Max(1, CInt(Math.Round(quiet / 60)))
        let k2 = kind, t2 = tool, ti = title, sr = src
        let kindS: String = kind ?? "", toolS: String = tool ?? "", minS: String = String(min), keyS: String = Path.GetFileName(key)
        var msg: String = src + " stuck: " + kindS + " " + toolS
        msg += " " + minS + "min " + keyS
        App.Log(msg)
        Post { [self] in OnStuck(sr, k2!, t2, ti, min) }
    }

    func ClaudeWatchOnce(_ js: JavaScriptSerializer) throws {
        let root = World.ClaudeProjectsDir()
        if !Directory.Exists(root) { busyClaude = 0; return }
        let now = DateTime.UtcNow
        let seen = HashSet<String>()
        // mac: Claude Code 在 mac 上是 claude（原生執行檔）或 node 行程，名字跟 Windows 一樣
        let anyClaude = Process.GetProcessesByName("claude").Length > 0 || Process.GetProcessesByName("node").Length > 0
        var busy = 0
        for pdir in World.WatchDirs(root) {
            for fi in World.WatchFiles(pdir, ".jsonl", nil, false) {
                var act = World.WatchMtime(fi)
                if (now - act).TotalMinutes > 40 { continue }
                let key = fi
                seen.Add(key)
                let sub = Path.Combine(pdir, ((fi as NSString).lastPathComponent as NSString).deletingPathExtension)
                if Directory.Exists(sub) {
                    for f2 in World.WatchFiles(sub, nil, nil, true) {
                        let t2 = World.WatchMtime(f2)
                        if t2 > act { act = t2 }
                    }
                }
                var tool: String? = nil, title: String? = nil, kind: String? = nil
                if (now - act).TotalMinutes < 10 || (now - act).TotalSeconds >= 85 { kind = World.ClaudeState(js, fi, &tool, &title) }
                if anyClaude && (kind == "model" || kind == "tool") && (now - act).TotalMinutes < 10 { busy += 1 }
                StuckCheck(key, "Claude", act, kind, tool, title, anyClaude)
            }
        }
        busyClaude = busy
        let gone = List<String>()
        for kk in stuck.Keys { if !seen.Contains(kk) && kk.lowercased().hasPrefix(root.lowercased()) { gone.Add(kk) } }
        for kk in gone { stuck.Remove(kk) }
    }

    // mac: DirectoryInfo／FileInfo 的替代（直接用 FileManager）
    static func WatchDirs(_ root: String) -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        var r: [String] = []
        for nm in names {
            let p = (root as NSString).appendingPathComponent(nm)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue { r.append(p) }
        }
        return r
    }

    // 列出 dir 底下（recursive＝含子資料夾）副檔名＝ext、檔名開頭＝prefix 的檔案
    static func WatchFiles(_ dir: String, _ ext: String?, _ prefix: String?, _ recursive: Bool) -> [String] {
        let fm = FileManager.default
        var names: [String] = []
        if recursive {
            guard let en = fm.enumerator(atPath: dir) else { return [] }
            while let nm = en.nextObject() as? String { names.append(nm) }
        } else {
            guard let ns = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
            names = ns
        }
        var r: [String] = []
        for nm in names {
            let base = (nm as NSString).lastPathComponent
            if let e = ext, !base.hasSuffix(e) { continue }
            if let pf = prefix, !base.hasPrefix(pf) { continue }
            let p = (dir as NSString).appendingPathComponent(nm)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: p, isDirectory: &isDir) && !isDir.boolValue { r.append(p) }
        }
        return r
    }

    static func WatchMtime(_ path: String) -> DateTime {
        return File.GetLastWriteTimeUtc(path)
    }

    static func WatchJson(_ l: String) -> [String: Any]? {
        guard let data = l.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any]
    }

    // 讀對話紀錄最後一段，找最後一筆主對話：回傳 idle／model／tool（null＝看不出來）
    static func ClaudeState(_ js: JavaScriptSerializer, _ file: String, _ tool: inout String?, _ title: inout String?) -> String? {
        tool = nil; title = nil
        let text = Tail(file, 768 * 1024)
        let lines = text.components(separatedBy: "\n")
        var kind: String? = nil
        var i = lines.count - 1
        while i >= 0 {
            defer { i -= 1 }
            let l = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if l.count < 2 { continue }
            if title == nil && l.hasPrefix("{\"type\":\"ai-title\"") {
                if let td = WatchJson(l) { title = Str(td, "aiTitle") }
                if kind != nil { break }
                continue
            }
            if kind != nil { if i < lines.count - 400 { break }; continue }
            if !l.contains("\"isSidechain\":false") { continue }
            guard let d = WatchJson(l) else { continue }
            let type = Str(d, "type")
            if type != "user" && type != "assistant" { continue }
            if let im = d["isMeta"] as? Bool, im { continue }
            guard let m = d["message"] as? [String: Any] else { continue }
            let content: Any? = m["content"]
            if type == "assistant" {
                let sr = Str(m, "stop_reason")
                if sr == "tool_use" {
                    kind = "tool"
                    if let arr = content as? [Any] {
                        for o in arr {
                            if let c = o as? [String: Any], Str(c, "type") == "tool_use" { tool = Str(c, "name") }
                        }
                    }
                } else { kind = sr == nil ? "model" : "idle" }
            } else {
                var first = content as? String
                let arr = content as? [Any]
                if first == nil, let arr = arr, arr.count > 0 {
                    if let c = arr[0] as? [String: Any] {
                        if Str(c, "type") == "text" { first = Str(c, "text") }
                        else if Str(c, "type") == "tool_result" {
                            let tc: Any? = c["content"]
                            first = tc as? String
                            if first == nil, let tca = tc as? [Any], tca.count > 0 {
                                if let c2 = tca[0] as? [String: Any] { first = Str(c2, "text") }
                            }
                        }
                    }
                }
                let f = String((first ?? "").drop(while: { $0.isWhitespace }))
                if f.hasPrefix("[Request interrupted") || f.hasPrefix("<command-name>") || f.hasPrefix("<local-command")
                    || f.hasPrefix("<bash-input>") || f.hasPrefix("<bash-stdout>") || f.hasPrefix("<bash-stderr>") {
                    kind = "idle"
                } else { kind = "model" }
            }
        }
        return kind
    }

    static func Str(_ d: [String: Any], _ key: String) -> String? {
        return d[key] as? String
    }

    static func Tail(_ file: String, _ max: Int) -> String {
        guard let fs = FileHandle(forReadingAtPath: file) else { return "" }
        defer { try? fs.close() }
        let len = Int(fs.seekToEndOfFile()), start = Math.Max(0, len - max)
        fs.seek(toFileOffset: UInt64(start))
        let buf = fs.readData(ofLength: len - start)
        var text = String(decoding: buf, as: UTF8.self)
        if start > 0 {
            if let nl = text.firstIndex(of: "\n") { text = String(text[text.index(after: nl)...]) } else { text = "" }
        }
        return text
    }

    static func Head(_ file: String, _ max: Int) -> String {
        guard let fs = FileHandle(forReadingAtPath: file) else { return "" }
        defer { try? fs.close() }
        let buf = fs.readData(ofLength: max)
        return String(decoding: buf, as: UTF8.self)
    }

    // ---------- Codex：~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl ----------
    static let CodexRx = try! NSRegularExpression(pattern: "^\\{\"timestamp\":\"([^\"]+)\",\"type\":\"([a-z_]+)\",\"payload\":\\{\"type\":\"([a-z_]+)\"")
    static let NameRx = try! NSRegularExpression(pattern: "\"name\":\"([^\"]+)\"")
    static let CwdRx = try! NSRegularExpression(pattern: "\"cwd\":\"((?:[^\"\\\\]|\\\\.)*)\"")

    // mac: Regex.Match 的替代：成功就回傳各組字串（[0]＝整段），失敗回傳 nil
    static func RxMatch(_ rx: NSRegularExpression, _ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = rx.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        var g: [String] = []
        for gi in 0..<m.numberOfRanges {
            let r = m.range(at: gi)
            g.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return g
    }

    static let CodexIso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    static let CodexIso2: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()

    final class CodexState { var Busy = false; var Kind: String? = nil, Tool: String? = nil; var LastComplete = DateTime.MinValue, CompleteStart = DateTime.MinValue }

    static func ParseCodex(_ file: String) -> CodexState {
        let st = CodexState()
        st.Kind = "model"
        var pending = false
        var start = DateTime.MinValue
        for raw0 in Tail(file, 512 * 1024).components(separatedBy: "\n") {
            let raw = raw0
            if raw.utf16.count < 40 { continue }
            let head400 = raw.utf16.count > 400 ? String(raw.prefix(400)) : raw
            guard let m = RxMatch(CodexRx, head400) else { continue }
            var ts = DateTime.MinValue
            if !DateTime.TryParse(m[1], &ts) { continue }
            let top = m[2], pt = m[3]
            if top == "event_msg" {
                if pt == "task_started" { st.Busy = true; start = ts; pending = false }
                else if pt == "task_complete" { if st.Busy || start != DateTime.MinValue { st.CompleteStart = start }; st.Busy = false; st.LastComplete = ts; pending = false }
                else if pt == "turn_aborted" { st.Busy = false; pending = false }
            } else if top == "response_item" {
                if pt == "function_call" || pt == "custom_tool_call" {
                    pending = true
                    let nm = RxMatch(NameRx, raw.utf16.count > 800 ? String(raw.prefix(800)) : raw)
                    st.Tool = nm != nil ? nm![1] : nil
                } else if pt == "function_call_output" || pt == "custom_tool_call_output" { pending = false }
            }
        }
        st.Kind = pending ? "tool" : "model"
        return st
    }

    static func CodexTitle(_ file: String) -> String? {
        guard let m = RxMatch(CwdRx, Head(file, 16 * 1024)) else { return nil }
        let cwd = m[1].replacingOccurrences(of: "\\\\", with: "\\")
        var t = cwd
        while t.hasSuffix("\\") || t.hasSuffix("/") { t.removeLast() }
        // mac: 也接受 Windows 的反斜線路徑
        if let i = t.lastIndex(where: { $0 == "/" || $0 == "\\" }) { return String(t[t.index(after: i)...]) }
        return t
    }

    func CodexWatchOnce(_ relist: Bool) throws {
        let root = World.CodexSessionsDir()
        if !Directory.Exists(root) { busyCodex = 0; return }
        let now = DateTime.UtcNow
        if relist {
            let files = List<String>()
            for fi in World.WatchFiles(root, ".jsonl", "rollout-", true) {
                if (now - World.WatchMtime(fi)).TotalMinutes <= 40 { files.Add(fi) }
            }
            codexFiles = files
        }
        // mac: Codex CLI 是 codex（原生）或 node 行程
        let anyCodex = Process.GetProcessesByName("codex").Length > 0 || Process.GetProcessesByName("node").Length > 0
        var busy = 0
        for f in codexFiles {
            if !FileManager.default.fileExists(atPath: f) { continue }
            let act = World.WatchMtime(f)
            if (now - act).TotalMinutes > 40 { continue }
            let st = World.ParseCodex(f)
            var cs: CodexSeen! = nil
            if !codexSeen.TryGetValue(f, &cs) || cs == nil { cs = CodexSeen(); cs.LastComplete = st.LastComplete; codexSeen[f] = cs }
            else if st.LastComplete > cs.LastComplete {
                cs.LastComplete = st.LastComplete
                let dur = st.CompleteStart == DateTime.MinValue ? 0 : (st.LastComplete - st.CompleteStart).TotalSeconds
                let idle = W.IdleSeconds()
                App.Log("codex done " + String(CInt(dur)) + "s idle=" + String(CInt(idle)) + " " + Path.GetFileName(f))
                if dur >= 45 || idle >= 30 { Post { [self] in OnDone("Codex") } }
            }
            if st.Busy && anyCodex { busy += 1 }
            let title = st.Busy && (now - act).TotalSeconds >= 85 ? World.CodexTitle(f) : nil
            StuckCheck(f, "Codex", act, st.Busy ? st.Kind : "idle", st.Tool, title, anyCodex)
        }
        busyCodex = busy
    }

    // ---------- 事件 → 公仔 ----------
    func OnClaude(_ ev: String, _ sid: String) {
        if ev == "start" { claudeStart[sid] = Now; return }
        if Hidden { return }
        let idle = W.IdleSeconds()
        if ev == "done" {
            var started: Double = 0
            let elapsed = claudeStart.TryGetValue(sid, &started) ? Now - started : 0
            claudeStart.Remove(sid)
            if elapsed < 45 && idle < 30 { return } // 很快就做完、你也在看 → 不吵你
            OnDone("Claude")
        } else if ev == "wait" {
            if waitCd > 0 { return }
            waitCd = 20
            if HoldIfQuiet("wait", "Claude 在等你回答") { return }
            Lead().Wait("Claude")
        }
    }

    func OnDone(_ src: String) {
        Count("tasks")
        if HoldIfQuiet("done", src + " 做完了") { return }
        if Hidden { return }
        doneUntil = Now + 25
        let l: Pet = Lead()
        l.Done(src, true)
        for p in OutPets() { if p !== l { p.React() } }
    }

    func OnStuck(_ src: String, _ kind: String, _ tool: String?, _ title: String?, _ min: Int) {
        if sharing || fsNow { return }
        if userHidden { userHidden = false; ApplyHidden() }
        if Hidden { return }
        stuckNow = true
        let l: Pet = Lead()
        if quietOn {
            // 安靜中：只冒泡泡
            l.Say(l.L("stuck", "who", src, "n", min.ToString()), 7, true)
            return
        }
        let who: String
        if string.IsNullOrEmpty(title) { who = src }
        else { let t = title!; who = src + "（" + (t.Length > 14 ? t.Substring(0, 14) + "…" : t) + "）" }
        let text: String
        if tool == "AskUserQuestion" || tool == "ExitPlanMode" || tool == "request_user_input" { text = l.L("ask", "who", who) }
        else if kind == "tool" { text = l.L("stuck_tool", "who", who, "tool", tool ?? "工具", "n", min.ToString()) }
        else { text = l.L("stuck", "who", who, "n", min.ToString()) }
        l.Alert(text)
        for p in OutPets() { if p !== l { p.React() } }
    }

    func OnUnstuck(_ src: String) {
        stuckNow = false
        if Hidden { return }
        let l: Pet = Lead()
        l.Unstuck(src)
    }
}

// ================= 串場（兩隻碰在一起演一小段）、大合照、點名、晚安 =================
//@@IN World
    var scene: List<World.Cue>! = nil
    var cast = List<Pet>()
    var sceneT: Double = 0, sceneCd: Double = 20, groupCd: Double = 120
    var pairCd = Dict<String, Double>()
    var flash: FlashForm! = nil
//@@END

extension World {
    final class Cue { var At: Double = 0; var Do: (() -> Void)! = nil }

    func AbortScene() {
        scene = nil
        for p in cast { p.InScene = false; p.ResetSceneProps() }
        ClearProps()
        cast.Clear()
    }

    func StepScene(_ dt: Double) {
        sceneCd -= dt; groupCd -= dt
        if scene == nil { return }
        sceneT += dt
        while scene != nil && scene.Count > 0 && sceneT >= scene[0].At {
            let c = scene[0]; scene.RemoveAt(0)
            c.Do()
        }
        if scene != nil && scene.Count == 0 { AbortScene(); sceneCd = 40 }
    }

    func Begin(_ who: Pet...) { Begin(who) }
    func Begin(_ who: [Pet]) {
        AbortScene()
        scene = List<Cue>(); sceneT = 0
        for p in who { p.InScene = true; cast.Add(p); p.WakeIfSleep() }
    }
    func At(_ t: Double, _ a: @escaping () -> Void) {
        let c = Cue(); c.At = t; c.Do = a; scene.Add(c)
        // C# List.Sort 不穩定；這裡用穩定排序（同時間的照加入順序）
        let arr = scene.ToArray().enumerated().sorted { $0.element.At != $1.element.At ? $0.element.At < $1.element.At : $0.offset < $1.offset }.map { $0.element }
        scene.Clear(); for x in arr { scene.Add(x) }
    }

    func CheckCrossover() {
        if scene != nil || sceneCd > 0 || Hidden || focusOn || quietOn || !Feat("scenes") { return }
        let outs = OutPets()
        if outs.Count < 2 { return }
        let free = List<Pet>()
        for p in outs { if p.Free() { free.Add(p) } }
        if free.Count >= 3 && groupCd <= 0 && rnd.NextDouble() < (TubbyLineup && free.Count >= 4 ? 0.04 : 0.02) { groupCd = 600; if TubbyLineup { TubbyGroup(free.Count) } else if PikLineup { PikGroup(free.Count) } else if OrigLineup { OrigGroup(free.Count) } else if rnd.NextDouble() < 0.6 { GroupPhoto() } else { GroupHug() }; return }
        var i = 0
        while i < free.Count {
            var j = i + 1
            while j < free.Count {
                let a = free[i], b = free[j]
                j += 1
                if a.supH != b.supH || Math.Abs(a.Foot - b.Foot) > 3 || Math.Abs(a.Cx - b.Cx) > Double(a.SW) * 2.5 { continue }
                let key = World.PairKey(a, b)
                var until: Double = 0
                if pairCd.TryGetValue(key, &until) && Now < until { continue }
                pairCd[key] = Now + 180 + rnd.NextDouble() * 120
                PlayScene(key)
                return
            }
            i += 1
        }
    }

    static func PairKey(_ a: Pet, _ b: Pet) -> String {
        let x = a.P.Id!, y = b.P.Id!
        return x.utf16.lexicographicallyPrecedes(y.utf16) ? x + "-" + y : y + "-" + x
    }

    // 也可以從 pipe 叫：act scene hangyodon-spidey
    func PlayScene(_ key: String) {
        var ids = key.components(separatedBy: "-")
        if ids.count == 1 && (key == "photo" || key == "group") { GroupPhoto(); return }
        if ids.count == 1 && PikLineup { PikScene(key); return }
        if ids.count == 1 && OrigLineup { OrigScene(key); return }
        if ids.count == 1 {
            switch key {
            case "bighug": SceneBigHug(); return
            case "sing": SceneSing(); return
            case "fall": SceneFall(); return
            case "toast": SceneToast(); return
            case "byebye": SceneByeBye(false); return
            default: break
            }
            return
        }
        if ids.count != 2 { return }
        ids.sort { $0.utf16.lexicographicallyPrecedes($1.utf16) }
        guard let a = Get(ids[0]), let b = Get(ids[1]) else { return }
        if !a.Out { BringOut(a, false) }
        if !b.Out { BringOut(b, false) }
        let k2 = ids[0] + "-" + ids[1]
        pairCd[k2] = Now + 180 + rnd.NextDouble() * 120
        let d0: Double = a.Out && b.Out && a.state != "exit" && b.state != "exit" ? 0 : 1.6
        // 離太遠：先湊到一起再演
        if TubbyLineup || PikLineup || OrigLineup { Later(d0) { [self] in GatherPair(k2, a, b, 0) }; return }
        Later(d0) { [self] in
            if !Pets.Contains(a) || !Pets.Contains(b) { return }   // 中間換櫃了
            AbortScene()
            let wait = b.ComeNear(a)
            b.InScene = true; a.InScene = true; cast.Add(a); cast.Add(b)
            if a.Grounded() { a.ScenePose("idle", 30) }
            Later(wait + 0.3) { [self] in RunScene(k2, a, b) }
        }
    }

    // 天線寶寶一櫃：等兩隻都站穩了才湊過去（剛出櫃還在空中時，算出來的位置會疊在一起），站好後再開演
    func GatherPair(_ key: String, _ a: Pet, _ b: Pet, _ tries: Int) {
        if !Pets.Contains(a) || !Pets.Contains(b) || !a.Out || !b.Out { return }
        if (!a.Grounded() || !b.Grounded()) && tries < 12 { Later(0.35) { [self] in GatherPair(key, a, b, tries + 1) }; return }
        AbortScene()
        b.InScene = true; a.InScene = true; cast.Add(a); cast.Add(b)
        if a.Grounded() { a.ScenePose("idle", 30) }
        let wait = b.ComeNear(a)
        Later(wait + 0.3) { [self] in WaitStill(key, a, b, 0) }
    }
    func WaitStill(_ key: String, _ a: Pet, _ b: Pet, _ tries: Int) {
        if !Pets.Contains(a) || !Pets.Contains(b) || !a.Out || !b.Out { return }
        if (!a.Grounded() || !b.Grounded() || b.state == "goto") && tries < 10 { Later(0.3) { [self] in WaitStill(key, a, b, tries + 1) }; return }
        RunScene(key, a, b)
    }

    func RunScene(_ key: String, _ a: Pet, _ b: Pet) {
        // mac: C# 傳 null 進去會在 Begin 丟例外被 Later 吞掉；這裡少一隻就不演
        func g(_ id: String) -> Pet? { return Get(id) }
        switch key {
        case "hangyodon-spidey": if let x = g("spidey"), let y = g("hangyodon") { SceneHeroes(x, y) }
        case "po-spidey": if let x = g("spidey"), let y = g("po") { SceneSling(x, y) }
        case "spidey-stitch": if let x = g("spidey"), let y = g("stitch") { SceneClimbRace(x, y) }
        case "po-stitch": if let x = g("stitch"), let y = g("po") { SceneScooterThief(x, y) }
        case "hangyodon-stitch": if let x = g("stitch"), let y = g("hangyodon") { SceneBlueBrothers(x, y) }
        case "hangyodon-po": if let x = g("po"), let y = g("hangyodon") { SceneJoke(x, y) }
        // 天線寶寶一櫃
        case "dipsy-tinky": if let x = g("tinky"), let y = g("dipsy") { SceneHatSwap(x, y) }
        case "laalaa-tinky": if let x = g("tinky"), let y = g("laalaa") { SceneBallBag(x, y) }
        case "dipsy-laalaa": if let x = g("dipsy"), let y = g("laalaa") { SceneDanceOff(x, y) }
        case "po-tinky": if let x = g("po"), let y = g("tinky") { SceneScooterRide(x, y) }
        case "dipsy-po": if let x = g("po"), let y = g("dipsy") { SceneHatBaseball(x, y) }
        case "laalaa-po": if let x = g("laalaa"), let y = g("po") { SceneBallFetch(x, y) }
        default: if PikLineup { PikPairScene(key) } else if OrigLineup { OrigPairScene(key) } else if a.P.Cu || b.P.Cu { CuPairScene(key, a, b) }
        }
    }

    func Face(_ a: Pet, _ b: Pet) { a.FaceTo(b); b.FaceTo(a) }

    // 三隻以上：大合照（排一排、閃光、笑一個）
    func GroupPhoto() {
        if OrigLineup { OrigPhoto(); return }
        let outs = OutPets()
        if outs.Count < 2 { AllOut(); Later(2.5) { [self] in GroupPhoto() }; return }
        let l: Pet = Lead()
        Begin(outs.ToArray())
        let gap: Double = TubbyLineup ? 1.9 : 1.6   // 天線寶寶比較寬（帽子、袋子、球）
        let foot = l.Foot
        var left = l.Cx - Double(outs.Count - 1) * Double(l.SW) * gap / 2
        var right = left + Double(outs.Count - 1) * Double(l.SW) * gap
        if !l.OnFloor { for p in Plats { if p.H == l.supH { left = Math.Max(left, Double(p.Left) + Double(l.SW) / 2.0); right = Math.Min(right, Double(p.Right) - Double(l.SW) / 2.0) } } }
        let wa = WA(l.Cx, foot - 4)
        left = Math.Max(left, Double(wa.Left + l.SW)); right = Math.Min(Math.Max(right, left), Double(wa.Right - l.SW))
        let L0 = left, R0 = right
        At(0) { l.Say("大家來拍照～排好排好！", 2) }
        for i in 0..<outs.Count {
            let p = outs[i]
            let tx: Double = outs.Count == 1 ? L0 : L0 + (R0 - L0) * Double(i) / Double(outs.Count - 1)
            At(0.4 + Double(i) * 0.35) { [self] in
                if Math.Abs(p.Foot - foot) < 3 && p.supH == l.supH && Math.Abs(tx - p.Cx) < 600 * k { p.WalkTo(tx, 10) }
                else if p.P.Id == "hangyodon" { p.StartSwim(tx, foot, false) }
                else { p.JumpTo(tx, foot) }
            }
        }
        At(5.2) {
            for p in outs {
                p.dir = p.Cx < (L0 + R0) / 2 ? 1 : -1
                if p.P.Id == "hangyodon" { p.ScenePose("cape", 3) } else if p.P.Id == "stitch" { p.ScenePose("grin", 3) } else if p.P.Id == "dipsy" { p.ScenePose("hattip", 3) } else { p.ScenePose("photo", 3) }
            }
            l.Say("笑一個～ 3、2、1！", 1.6)
        }
        At(6.6) { [self] in Flash(Rectangle.FromLTRB(CInt(L0 - 120 * k), CInt(foot - 200 * k), CInt(R0 + 120 * k), CInt(foot + 20 * k))) }
        if TubbyLineup {
            // 天線寶寶一櫃：一隻一隻講（站很近，同時講泡泡會疊在一起）
            var d = 7.4
            for p in ShowOrder(outs) {
                let pp = p
                let line = pp.P.Id == "tinky" ? "魔法袋有拍進去嗎？" : (pp.P.Id == "dipsy" ? "帽子有拍到吧？酷。" : (pp.P.Id == "laalaa" ? "啦啦～好好看！" : "再拍一次！"))
                At(d) { pp.Say(line, 1.15) }
                d += 1.2
            }
            At(d + 0.4) { }
            return
        }
        At(7.4) {
            for p in outs {
                switch p.P.Id! {
                case "po": p.Say("再拍一次！", 1.8)
                case "stitch": p.Say("Ohana！", 1.8)
                case "hangyodon": p.Say("我有被拍進去嗎？嘴唇太大了嗎？", 1.8)
                case "pkred", "pkyellow", "pkblue": p.Say("噗咿！", 1.8)
                default: p.Say(p.P.Cu ? p.L("x_photo") : "帥！", 1.8)
                }
            }
        }
        At(9.5) { }
    }

    // 大家一起抱抱滑鼠
    func GroupHug() {
        let outs = OutPets()
        Begin(outs.ToArray())
        At(0) { for p in outs { p.InScene = false; p.Hug(p.L("hugs"), 2.6) } }
        At(0.2) { }
    }

    func Flash(_ r: Rectangle) {
        if Hidden { return }
        if flash == nil { flash = FlashForm() }
        flash.Bounds = r
        flash.Opacity = 0.8
        flash.Show(); W.KeepOnTop(flash)
        Later(0.08) { [self] in flash.Opacity = 0.5 }
        Later(0.16) { [self] in flash.Opacity = 0.25 }
        Later(0.26) { [self] in flash.Hide() }
    }

    // 早上第一次：一隻一隻從櫃子跳出來點名
    func StartRollCall(_ ids: List<String>) {
        if TubbyLineup { TubbyRollCall(ids); return }
        if PikLineup { PikRollCall(ids); return }
        if OrigLineup { OrigRollCall(ids); return }
        var d = 0.4
        for id in ids {
            guard let p = Get(id) else { continue }
            let pp = p
            Later(d) { [self] in if !pp.Out { BringOut(pp, false) } }
            Later(d + 0.6) { pp.Say(pp.L("morning"), 2.6) }
            d += 1.6
        }
    }

    // 下班了：輪流催你回家，然後一隻一隻回櫃子（人魚漢頓先在泡泡裡睡著）
    func NightRitual() {
        if TubbyLineup { SceneByeBye(true); return }
        if PikLineup { PikNight(true); return }
        if OrigLineup { OrigNight(true); return }
        let outs = OutPets()
        // C# List.Sort（不穩定）；這裡穩定排序：人魚漢頓排第一
        let sorted = outs.ToArray().enumerated().sorted { a, b in
            let ka = a.element.P.Id == "hangyodon" ? 0 : 1, kb = b.element.P.Id == "hangyodon" ? 0 : 1
            return ka != kb ? ka < kb : a.offset < b.offset
        }.map { $0.element }
        outs.Clear(); for p in sorted { outs.Add(p) }
        Begin(outs.ToArray())
        for p in outs { if p.Grounded() { p.ScenePose("idle", 60) } }
        var d = 0.2
        for p in outs { let pp = p; At(d) { pp.Say(pp.L("nag"), 2.6) }; d += 2.8 }
        for p in outs {
            let pp = p
            if pp.P.Id == "hangyodon" { At(d) { pp.InScene = false; pp.Act("sleep"); pp.InScene = true; pp.Say("我先在泡泡裡睡了…你也不要一個人待太晚喔", 2.6) }; d += 2.8 }
            At(d) { pp.Say(pp.L("goodnight"), 2.4) }
            At(d + 1.2) { pp.InScene = false; if pp.Out { pp.StowToShelf(false) } }
            d += 2.6
        }
        At(d + 0.5) { }
    }
}

// 串場用的小道具（丟來丟去的帽子、球、吐司）和小幫手「吸吸」：一張像素圖，點得穿
class SpriteForm: OverlayForm {
    var art: [String]! = nil; var pal: Dict<Character, Color>! = nil; var ps = 0; var flip = false
    init() { super.init(true) }
    var Halo: Int { return Math.Max(1, ps / 3) }
    func Set(_ a: [String], _ p: Dict<Character, Color>, _ pixel: Int, _ fx: Bool) {
        if art != nil && a == art && p === pal && pixel == ps && fx == flip { return }
        let resize = art == nil || a.count != art.count || a[0].Length != art[0].Length || pixel != ps
        art = a; pal = p; ps = pixel; flip = fx
        // mac: Size 在 Form 裡同時是屬性名，改設 Width／Height
        if resize { Width = a[0].Length * ps + 2 * Halo; Height = a.count * ps + 2 * Halo }
        Invalidate()
    }
    override func OnPaint(_ e: PaintEventArgs) {
        let g = e.Graphics
        g.Clear(OverlayForm.KEY)
        if art == nil { return }
        let hw = Halo
        let hb = SolidBrush(Color.White)
        for pass in 0..<2 {
            for ry in 0..<art.count {
                let row = Array(art[ry])
                for rx in 0..<row.count {
                    let c = row[rx]
                    if c == "." { continue }
                    let px = hw + (flip ? row.count - 1 - rx : rx) * ps, py = hw + ry * ps
                    if pass == 0 { g.FillRectangle(hb, px - hw, py - hw, ps + 2 * hw, ps + 2 * hw); continue }
                    var col = Color.Magenta
                    if !pal.TryGetValue(c, &col) { col = Color.Magenta }
                    let b = SolidBrush(col); g.FillRectangle(b, px, py, ps, ps)
                }
            }
        }
    }
}

// ================= 天線寶寶一櫃的串場（兩隻、大家一起）、點名、說再見 =================
//@@IN World
    var props = List<World.Prop>()
//@@END

extension World {
    final class Prop {
        var F: SpriteForm! = nil; var A: [String]! = nil, A2: [String]! = nil; var Owner: Pal! = nil; var Ps = 0; var Spin = false, Fx = false
        var X0: Double = 0, Y0: Double = 0, X: Double = 0, Y: Double = 0, T: Double = 0, Hold: Double = 0
        let Legs = List<[Double]>()     // 目標 x、y、秒數、拋物線高度
        let Then = List<(() -> Void)?>()
        @discardableResult
        func Go(_ x1: Double, _ y1: Double, _ dur: Double, _ arc: Double, _ then: (() -> Void)?) -> Prop { Legs.Add([x1, y1, Math.Max(0.05, dur), arc]); Then.Add(then); return self }
    }
    static let BASEBALL_ART = [".33.", "3433", "3343", ".33."]
    static let TOAST_ART = [".2222.", "211112", "2k11k2", "211112", "21kk12", ".2222."]

    func NewProp(_ a: [String], _ a2: [String]?, _ owner: Pal, _ ps: Int, _ x: Double, _ y: Double, _ spin: Bool) -> Prop {
        let p = Prop()
        p.F = SpriteForm(); p.A = a; p.A2 = a2; p.Owner = owner; p.Ps = ps; p.Spin = spin
        p.X0 = x; p.X = x; p.Y0 = y; p.Y = y
        props.Add(p)
        PlaceProp(p)
        return p
    }

    // 丟一個小道具：從 a 拋物線飛到 b（中心點），到了做 done，停 hold 秒再消失
    @discardableResult
    func Toss(_ art: [String], _ owner: Pal?, _ a: PointF, _ b: PointF, _ dur: Double, _ arc: Double, _ spin: Bool, _ hold: Double, _ done: (() -> Void)?) -> Prop! {
        if owner == nil || Hidden { if done != nil { done!() }; return nil }
        let p = NewProp(art, nil, owner!, S, Double(a.X), Double(a.Y), spin)
        p.Go(Double(b.X), Double(b.Y), dur, arc, done)
        p.Hold = hold
        return p
    }

    func RemoveProp(_ p: Prop?) { guard let p = p else { return }; props.Remove(p); p.F.Close() }
    func ClearProps() { for p in props { p.F.Close() }; props.Clear() }

    func PlaceProp(_ p: Prop) {
        let alt = p.A2 != nil && Int(Math.Floor(p.T * 7)) % 2 == 1
        let fx = p.Spin ? Int(Math.Floor(p.T * 8)) % 2 == 1 : p.Fx
        p.F.Set(alt ? p.A2 : p.A, Night ? p.Owner.Night : p.Owner.Day, p.Ps, fx)
        p.F.Location = Point(CInt(Math.Round(p.X - Double(p.F.Width) / 2.0)), CInt(Math.Round(p.Y - Double(p.F.Height) / 2.0)))
        if Hidden { if W.Shown(p.F) { p.F.Hide() } }
        else if !W.Shown(p.F) { p.F.Show(); W.KeepOnTop(p.F) }
    }

    func StepProps(_ dt: Double) {
        var i = props.Count - 1
        while i >= 0 {
            defer { i -= 1 }
            if i >= props.Count { continue }
            let p = props[i]
            if p.Legs.Count > 0 {
                let leg = p.Legs[0]
                p.T += dt
                let f = Math.Min(1, p.T / leg[2])
                if Math.Abs(leg[0] - p.X0) > 1 { p.Fx = leg[0] < p.X0 }
                p.X = p.X0 + (leg[0] - p.X0) * f
                p.Y = p.Y0 + (leg[1] - p.Y0) * f - Math.Sin(Math.PI * f) * leg[3]
                PlaceProp(p)
                if f >= 1 {
                    p.X0 = leg[0]; p.Y0 = leg[1]; p.T = 0
                    p.Legs.RemoveAt(0)
                    let then = p.Then[0]; p.Then.RemoveAt(0)
                    if then != nil { then!() }
                }
                continue
            }
            p.Hold -= dt
            if p.Hold <= 0 { props.Remove(p); p.F.Close() }
            else { PlaceProp(p) }
        }
    }

    static func Mid(_ v: Double, _ lo: Double, _ hi: Double) -> Double { return v < lo ? lo : (v > hi ? hi : v) }

    // 大家排成一排（走過去或跳過去）：回傳 {左, 右, 腳}
    @discardableResult
    func LineUp(_ outs: List<Pet>, _ l: Pet, _ spacing: Double) -> [Double] {
        let foot = l.Foot
        var left = l.Cx - Double(outs.Count - 1) * Double(l.SW) * spacing / 2
        var right = left + Double(outs.Count - 1) * Double(l.SW) * spacing
        if !l.OnFloor { for p in Plats { if p.H == l.supH { left = Math.Max(left, Double(p.Left) + Double(l.SW) / 2.0); right = Math.Min(right, Double(p.Right) - Double(l.SW) / 2.0) } } }
        let wa = WA(l.Cx, foot - 4)
        left = Math.Max(left, Double(wa.Left + l.SW)); right = Math.Min(Math.Max(right, left), Double(wa.Right - l.SW))
        let L0 = left, R0 = right
        for i in 0..<outs.Count {
            let p = outs[i]
            let tx: Double = outs.Count == 1 ? L0 : L0 + (R0 - L0) * Double(i) / Double(outs.Count - 1)
            At(0.4 + Double(i) * 0.35) { [self] in
                if Math.Abs(p.Foot - foot) < 3 && p.supH == l.supH && Math.Abs(tx - p.Cx) < 600 * k { p.WalkTo(tx, 10) }
                else { p.JumpTo(tx, foot) }
            }
        }
        return [left, right, foot]
    }

}

// ================= 離屏測試模式（DESKPALS_OFFSCREEN=1）=================
// 不顯示任何視窗；pipe 下 snap 把「本來會畫在螢幕上的東西」疊到一張假桌面上存成 PNG。
extension World {
    // snap <path> [x y w h]
    func Snap(_ path: String, _ region0: Rectangle) {
        var region = region0
        let vs = SystemInformation.VirtualScreen
        if region.Width <= 0 || region.Height <= 0 { region = vs }
        let b = Bitmap(region.Width, region.Height)
        let g = Graphics.FromImage(b)
        g.TranslateTransform(Double(-region.X), Double(-region.Y))
        g.Clear(Color.FromArgb(0x3A, 0x55, 0x7A))
        let desk = SolidBrush(Color.FromArgb(0x5B, 0x7D, 0xA8))
        for s in screens { g.FillRectangle(desk, s.WorkingArea) }
        let bar = SolidBrush(Color.FromArgb(0x20, 0x22, 0x2A))
        for s in screens { g.FillRectangle(bar, Rectangle.FromLTRB(s.Bounds.Left, s.WorkingArea.Bottom, s.Bounds.Right, s.Bounds.Bottom)) }
        // 真的視窗位置（只畫框，不擷取內容）：後面的先畫
        let body = SolidBrush(Color.FromArgb(0xF4, 0xF5, 0xF8))
        let title = SolidBrush(Color.FromArgb(0xD6, 0xDB, 0xE4))
        let edge = Pen(Color.FromArgb(0x9A, 0xA3, 0xB5))
        var i = Wins.Count - 1
        while i >= 0 {
            defer { i -= 1 }
            let wi = Wins[i]
            if !Cands.ContainsKey(wi.H) { continue }
            let r = Rectangle.FromLTRB(wi.L, wi.T, wi.R, wi.B)
            g.FillRectangle(body, r)
            g.FillRectangle(title, r.X, r.Y, r.Width, Math.Min(r.Height, 30))
            g.DrawRectangle(edge, r.X, r.Y, r.Width - 1, r.Height - 1)
        }
        // 由下到上：櫃子 → 蜘蛛網 → 公仔 → 球 → 煙火 → 泡泡 → 閃光
        if shelf != nil && shelf.VVisible && shelf.VBmp != nil { g.DrawImageUnscaled(shelf.VBmp, shelf.VPos) }
        for f in webs { if f.VVisible { f.PaintTo(g) } }
        for p in Pets { if p.Form != nil && p.Form.VVisible && p.Form.VBmp != nil { g.DrawImageUnscaled(p.Form.VBmp, p.Form.VPos) } }
        for pr in props { if pr.F.VVisible { pr.F.PaintTo(g) } }
        if ballF != nil && ballF.VVisible { ballF.PaintTo(g) }
        if fx != nil && fx.VVisible { fx.PaintTo(g) }
        for p in Pets { if p.Bub != nil && p.Bub.VVisible { p.Bub.PaintTo(g) } }
        if flowerBub != nil && flowerBub.VVisible { flowerBub.PaintTo(g) }
        if flash != nil && flash.VVisible { flash.PaintTo(g) }
        if setupForm != nil && !setupForm.IsDisposed && setupForm.VVisible { setupForm.PaintTo(g) }
        StudySnap(g)
        CuSnap(g)
        if pmenu != nil && pmenu.VVisible { pmenu.PaintTo(g) }
        // 游標位置（只畫一個小十字，方便看）
        let c = World.CursorPos()
        let cp = Pen(Color.FromArgb(200, 255, 255, 0), 2); g.DrawLine(cp, c.X - 6, c.Y, c.X + 6, c.Y); g.DrawLine(cp, c.X, c.Y - 6, c.X, c.Y + 6)
        g.ResetTransform()
        _ = try? FileManager.default.createDirectory(atPath: Path.GetDirectoryName(path), withIntermediateDirectories: true)
        b.Save(path, ImageFormat.Png)
    }

    // mac: World 也是 Form（有 Cursor 屬性），所以靜態的 Cursor.Position 要從這裡拿
    static func CursorPos() -> Point { return CursorT.Position }

    static func ParseRect(_ p: [String], _ i: Int) -> Rectangle {
        var x = 0, y = 0, wd = 0, ht = 0
        if p.count >= i + 4 && int.TryParse(p[i], &x) && int.TryParse(p[i + 1], &y) && int.TryParse(p[i + 2], &wd) && int.TryParse(p[i + 3], &ht) {
            return Rectangle(x, y, wd, ht)
        }
        return Rectangle.Empty
    }

    // 模擬點一下（測試用）：點公仔＝摸他／點通知；點櫃子格子＝放出來／收回去
    func SimClick(_ x: Int, _ y: Int) {
        var i = Pets.Count - 1
        while i >= 0 {
            defer { i -= 1 }
            let p = Pets[i]
            if !p.Out { continue }
            let X = Double(x), Y = Double(y)
            if X >= p.x - Double(9 * S) && X <= p.x + Double(p.SW + 9 * S) && Y >= p.y - Double(p.P.TopRows * S) - 6 && Y <= p.y + Double(p.SH + 6) { p.Clicked(); return }
        }
        if shelf != nil { shelf.ClickAt(Point(x, y), MouseButtons.Left) }
    }

    // 模擬拖到某處放開
    func SimDrop(_ p: Pet?, _ x: Int, _ y: Int) {
        guard let p = p, p.Out else { return }
        p.x = Double(x) - Double(p.SW) / 2.0; p.y = Double(y) - Double(p.SH) / 2.0
        if InShelf(Double(x), Double(y)) { p.StowToShelf(true) }
        else { p.Jump(0, 0) }
    }
}
