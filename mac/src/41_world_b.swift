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

    // Spidey × 人魚漢頓：想當英雄的漢頓、鼓勵他的 Spidey
    func SceneHeroes(_ s: Pet, _ h: Pet) {
        Begin(s, h)
        At(0) { [self] in Face(s, h); s.ScenePose("idle", 13); h.ScenePose("idle", 13); h.Say("你、你是真的英雄耶！", 2) }
        At(2.1) { h.ScenePose("cape", 1.8); h.Say("我也想當英雄…可是我只有一件披風", 2.6) }
        At(4.9) { s.ScenePose("hop", 0); s.Say("英雄不是看披風的", 2.2) }
        At(7.2) { s.Say("你每天逗大家笑，已經是英雄了", 2.6) }
        At(9.9) { h.Say("真、真的嗎？嗚嗚…", 1.8); h.Mark(4) }
        At(11.6) { if s.Cx < h.Cx { s.dir = 1; h.dir = -1 } else { s.dir = -1; h.dir = 1 }; s.ScenePose("hero", 2.6); h.ScenePose("cape", 2.6); s.Say("英雄合體！", 2.4); h.Say("英雄合體！（好帥！）", 2.4) }
        At(14.4) { }
    }

    // Spidey × 小波：用絲把小波（連車）甩上去
    func SceneSling(_ s: Pet, _ po: Pet) {
        Begin(s, po)
        At(0) { [self] in Face(s, po); s.ScenePose("idle", 8); po.ScenePose("idle", 8); s.Say("小波，要不要飛高高？", 2) }
        At(2.1) { po.ScenePose("wave", 1.2); po.Say("要要要！Eh-oh!", 1.6) }
        At(3.5) { [self] in
            s.SlingAt(po)
            var best: Plat! = nil
            for p in Plats { if Double(p.Top) < po.Foot - 80 * k && Double(p.Top) > po.Foot - 600 * k && Math.Abs(Double(p.Left + p.Right) / 2.0 - po.Cx) < 700 * k && p.Right - p.Left > po.SW * 2 { best = p; break } }
            if best != nil { po.JumpTo(Math.Max(Double(best.Left + po.SW), Math.Min(Double(best.Right - po.SW), po.Cx)), Double(best.Top)) }
            else { po.Jump(0, -820 * k) }
            po.Say("咻～～～", 1.4)
        }
        At(5.6) { po.Say("再來一次！再來一次！", 2) }
        At(7.8) { s.Say("……下次再說 😅", 1.8) }
        At(9.5) { }
    }

    // Spidey × 史迪仔：比賽爬牆
    func SceneClimbRace(_ s: Pet, _ st: Pet) {
        Begin(s, st)
        At(0) { [self] in Face(s, st); s.ScenePose("idle", 6); st.ScenePose("grin", 1.6); st.Say("ih! 史迪仔也會爬牆！", 1.8) }
        At(1.9) { s.Say("喔？比賽啊！預備…", 1.6) }
        At(3.4) { s.InScene = false; st.InScene = false; s.Act("climb"); st.Signature(); s.Say("開始！", 1) }
        At(9) { [self] in if rnd.NextDouble() < 0.5 { st.Say("史迪仔贏了！嘻嘻嘻", 2) } else { s.Say("Spidey 贏了！Thwip!", 2) } }
        At(9.2) { }
    }

    // 史迪仔 × 小波：偷騎滑板車
    func SceneScooterThief(_ st: Pet, _ po: Pet) {
        Begin(st, po)
        At(0) { [self] in Face(st, po); po.ScenePose("idle", 10); st.ScenePose("grin", 1.2); st.Say("嘻嘻嘻…", 1.2) }
        At(1.3) { [self] in
            po.LoseScooter(true); st.RidingStolen = true
            let away: Double = st.Cx > po.Cx ? 1 : -1
            st.RaceTo(st.Cx + away * 260 * k)
            st.Say("ih-ih-ih! 滑板車！", 1.6)
        }
        At(1.8) { po.Say("我的滑板車！", 2); po.WalkTo(st.Cx, 3) }
        At(4.6) { st.ScenePose("idle", 6); st.FaceTo(po); st.Say("Ohana！一家人不會丟下任何人！", 2.6); st.RidingStolen = false; po.LoseScooter(false) }
        At(5.2) { po.WalkTo(st.Cx + (po.Cx < st.Cx ? -1 : 1) * Double(st.SW) * 0.9, 1.5) }
        At(7.4) { [self] in Face(st, po); st.ScenePose("hug", 2.4); po.ScenePose("hug", 2.4); po.Say("大抱抱！", 2.2) }
        At(10) { }
    }

    // 史迪仔 × 人魚漢頓：「我們都是藍色的，是兄弟吧？」
    func SceneBlueBrothers(_ st: Pet, _ h: Pet) {
        Begin(st, h)
        At(0) { [self] in Face(st, h); st.ScenePose("idle", 10); h.ScenePose("idle", 10); h.Say("我們都是藍色的，是兄弟吧？", 2.4) }
        At(2.5) { st.Say("ih?（歪頭）", 1.2); st.Mark(2) }
        At(3.8) { st.WalkTo(h.Cx + (st.Cx < h.Cx ? -1 : 1) * Double(h.SW) * 0.8, 1.0) }
        At(5.0) { [self] in Face(st, h); st.ScenePose("lick", 1.4); st.Say("（舔）", 1.2); h.Mark(4) }
        At(6.5) { h.Say("嘻嘻…好癢！這是兄弟的打招呼嗎？", 2.4) }
        At(9.0) { st.ScenePose("hug", 2.4); h.ScenePose("hug", 2.4); st.Say("Ohana！", 2.2); h.Say("Ohana…我有家人了 ♥", 2.4) }
        At(11.6) { }
    }

    // 小波 × 人魚漢頓：笑話讓小波笑了，漢頓超開心
    func SceneJoke(_ po: Pet, _ h: Pet) {
        Begin(po, h)
        At(0) { [self] in Face(po, h); po.ScenePose("idle", 11); h.ScenePose("idle", 11); h.Say("小波，要聽笑話嗎？", 1.8) }
        At(1.9) { po.ScenePose("wave", 1); po.Say("要！Eh-oh!", 1.4) }
        At(3.4) { h.Say("為什麼魚不會打網球？…因為怕碰到網子！", 3) }
        At(6.6) { po.ScenePose("hop", 0); po.Say("嘻嘻嘻！再來一次！再來一次！", 2.2) }
        At(8.9) { h.ScenePose("cape", 2); h.Say("她笑了！有人笑了！我、我好開心！", 2.6); for _ in 0..<4 { h.Mark(5) } }
        At(11.6) { [self] in Face(po, h); po.ScenePose("hug", 2.2); h.ScenePose("hug", 2.2); po.Say("大抱抱！", 2) }
        At(14) { }
    }

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
    // 吸吸：原創的圓圓掃地小機器人（前面一根短短的吸管鼻子），兩格輪流＝輪子在轉
    static let BOT_A = ["....kkkkkk......", "..kkvvvvvvkk....", ".kvvWvvvvvvvk...", ".kvkWvvkWvvvkkkk", "kvvkkvvkkvvvkvVk", "kvvvvvvvvvvvkkkk", "kVVVVVVVVVVVk...", ".kkkkkkkkkkkk...", "..kOk....kOk...."]
    static let BOT_B = ["....kkkkkk......", "..kkvvvvvvkk....", ".kvvWvvvvvvvk...", ".kvkWvvkWvvvk...", "kvvkkvvkkvvvkkkk", "kvvvvvvvvvvvkvVk", "kVVVVVVVVVVVkkkk", ".kkkkkkkkkkkk...", "...kOk..kOk....."]

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

    // 照節目的順序：丁丁、迪西、拉拉、小波
    func ShowOrder(_ l: List<Pet>) -> List<Pet> {
        let o = List<Pet>()
        for id in Pal.LineupIds(Pal.Teletubbies) { for p in l { if p.P.Id == id { o.Add(p) } } }
        for p in l { if !o.Contains(p) { o.Add(p) } }
        return o
    }

    func TubbyGroup(_ n: Int) {
        let r = rnd.NextDouble()
        if n >= 4 {
            if r < 0.30 { SceneBigHug() } else if r < 0.50 { SceneSing() } else if r < 0.70 { SceneToast() } else if r < 0.85 { SceneFall() } else { GroupPhoto() }
        } else {
            if r < 0.25 { SceneSing() } else if r < 0.50 { SceneToast() } else if r < 0.70 { SceneFall() } else if r < 0.90 { GroupPhoto() } else { SceneBigHug() }
        }
    }

    // ---------- 丁丁 × 迪西：帽子借我戴 ----------
    func SceneHatSwap(_ ti: Pet, _ di: Pet) {
        Begin(ti, di)
        At(0) { [self] in Face(ti, di); ti.ScenePose("idle", 30); di.ScenePose("hattip", 1.8); ti.Say("迪西，你的帽子好好看喔…", 2.2) }
        At(2.3) { ti.Say("可以借丁丁戴一下嗎？", 2); ti.AddHeart() }
        At(4.4) { di.ScenePose("idle", 30); di.Say("不行。這是我的帽子。", 2) }
        At(6.5) { ti.ScenePose("hug", 1.8); ti.Say("拜託～一下下就好", 1.8) }
        At(8.5) { [self] in
            di.Say("……好啦，一下下喔。", 1.8)
            di.LendHat(true)
            Toss(Pal.Get("dipsy").Art["HAT"], Pal.Get("dipsy"), di.HatPoint(), ti.HatPoint(), 0.7, 70 * k, true, 0) { ti.WearHat = true; ti.Burst(6) }
        }
        At(9.6) { ti.ScenePose("dance", 3); ti.Say("我是迪西！嘿～嘿～", 2.4) }
        At(10.4) { di.Say("（頭頂涼涼的）", 1.8); di.Mark(2) }
        At(12.7) { [self] in
            ti.ScenePose("plop", 1.8); ti.Say("哎喲！", 1.4)
            ti.WearHat = false
            Toss(Pal.Get("dipsy").Art["HAT"], Pal.Get("dipsy"), ti.HatPoint(), di.HatPoint(), 0.75, 90 * k, true, 0) { di.LendHat(false) }
        }
        At(14.2) { di.ScenePose("hattip", 2); di.Say("還是我戴最帥。", 2) }
        At(16.4) { [self] in Face(ti, di); ti.ScenePose("hug", 2.4); di.ScenePose("hug", 2.4); ti.Say("大抱抱！", 2.2); di.Say("…大抱抱。", 2.2) }
        At(19) { }
    }

    // ---------- 丁丁 × 拉拉：球滾進魔法袋 ----------
    func SceneBallBag(_ ti: Pet, _ la: Pet) {
        Begin(ti, la)
        let ball: [String] = la.P.Art["BALL"]
        At(0) { [self] in Face(ti, la); ti.ScenePose("idle", 30); la.ScenePose("juggle", 2.6); la.Say("丁丁看！拉拉的球～啦啦啦", 2.4) }
        At(2.8) { [self] in
            la.ScenePose("kick", 0.5); la.Say("踢～！", 1); la.LoseBall(true)
            ti.ScenePose("bag:", 3.4)
            Toss(ball, la.P, la.FootPoint(), ti.BagPoint(), 0.8, 90 * k, false, 0) { ti.Say("喔？（咕嘟）", 1.2); ti.Mark(2) }
        }
        At(5.0) { la.ScenePose("idle", 30); la.Say("咦？我的球呢？", 1.8); la.Mark(2) }
        At(7.0) { ti.ScenePose("bag:toast", 2.4); ti.Say("丁丁找找看…", 1.2) }
        At(8.2) { ti.Say("是吐司！", 1.6) }
        At(9.8) { la.Say("不是這個啦～", 1.8) }
        At(11.6) { ti.ScenePose("bag:ball", 2.2); ti.Say("再找找…", 1.2) }
        At(12.8) { ti.Say("找到了！", 1.4) }
        At(13.85) { [self] in
            var a = ti.BagPoint(); a.Y -= Double(6 * S)
            Toss(ball, la.P, a, la.HandPoint(), 0.7, 70 * k, false, 0) { la.LoseBall(false); la.ScenePose("twirl", 1.6); la.Say("再來一次！再來一次！", 2) }
        }
        At(16.6) { [self] in Face(ti, la); ti.ScenePose("hug", 2.4); la.ScenePose("hug", 2.4); ti.Say("大抱抱！", 2.2); la.Say("大抱抱！", 2.2) }
        At(19.2) { }
    }

    // ---------- 迪西 × 拉拉：跳舞比賽，最後一起唱 ----------
    func SceneDanceOff(_ di: Pet, _ la: Pet) {
        Begin(di, la)
        At(0) { [self] in Face(di, la); di.ScenePose("idle", 30); la.ScenePose("idle", 30); di.Say("拉拉，來比跳舞。", 2) }
        At(2.2) { di.ScenePose("dance", 2.6); di.Say("嘿～嘿～（帽子跟著晃）", 2.4) }
        At(5.0) { di.ScenePose("idle", 30); la.ScenePose("twirl", 2.2); la.Say("換我！啦啦啦～", 2.2) }
        At(7.5) { la.ScenePose("idle", 30); di.ScenePose("hattoss", 1.6); di.Say("帽子戲法！", 1.6) }
        At(9.4) { la.ScenePose("juggle", 2.7); la.Say("球球戲法！1、2、3～", 2.4) }
        At(12.3) { di.ScenePose("dance", 3); la.ScenePose("dance", 3); la.Say("一起跳！啦啦啦～♪", 2.6); di.Say("嘿～♪", 1.6); di.Mark(0); la.Mark(0) }
        At(15.5) { [self] in Face(di, la); di.ScenePose("wave", 1.8); la.ScenePose("wave", 1.8); di.Say("Eh-oh.", 1.6); la.Say("Eh-oh!", 1.6) }
        At(17.6) { }
    }

    // ---------- 小波 × 丁丁：借騎滑板車，太大了跌坐 ----------
    func SceneScooterRide(_ po: Pet, _ ti: Pet) {
        Begin(po, ti)
        At(0) { [self] in Face(po, ti); po.ScenePose("idle", 30); ti.ScenePose("idle", 30); ti.Say("小波，丁丁可以騎你的滑板車嗎？", 2.4) }
        At(2.5) { po.ScenePose("wave", 1.2); po.Say("好啊！Eh-oh!", 1.6) }
        At(4.0) { [self] in
            po.LendScooter(true); ti.RidingPo = true
            let away: Double = ti.Cx > po.Cx ? 1 : -1
            let wa = WA(ti.Cx, ti.Foot - 4)
            ti.RaceTo(World.Mid(ti.Cx + away * 200 * k, Double(wa.Left + ti.SW), Double(wa.Right - ti.SW)))
            ti.Say("嘟嘟～丁丁騎車車！", 1.8)
        }
        At(6.4) { ti.Say("哎…哎…好晃…", 1.4); ti.Mark(4) }
        At(7.8) { ti.RidingPo = false; po.LendScooter(false); ti.ScenePose("plop", 1.8); ti.Say("哎喲！", 1.4) }
        At(9.2) { po.ScenePose("hop", 0); po.Say("再來一次！再來一次！", 2) }
        At(11.4) { ti.Say("…丁丁太大了啦，嘻嘻", 2) }
        At(13.2) { po.WalkTo(ti.Cx + (po.Cx < ti.Cx ? -1 : 1) * Double(ti.SW) * 0.9, 1.5) }
        At(15.2) { [self] in Face(po, ti); po.ScenePose("hug", 2.4); ti.ScenePose("hug", 2.4); po.Say("大抱抱！", 2.2); ti.Say("大抱抱！", 2.2) }
        At(17.8) { }
    }

    // ---------- 小波 × 迪西：棒球用帽子頂、用帽子接 ----------
    func SceneHatBaseball(_ po: Pet, _ di: Pet) {
        Begin(po, di)
        At(0) { [self] in Face(po, di); po.ScenePose("idle", 30); di.ScenePose("idle", 30); po.Say("迪西，接球！", 1.6) }
        At(1.6) { po.ScenePose("bat", 0) }
        At(1.85) { [self] in
            var top = di.HatPoint(); top.Y -= Double(4 * S)
            Toss(World.BASEBALL_ART, po.P, po.HandPoint(), top, 0.7, 60 * k, false, 0) { [self] in
                di.ScenePose("header", 0.6); di.Say("帽子頂！", 1.2)
                var t2 = di.HatPoint(); t2.Y -= Double(4 * S)
                Toss(World.BASEBALL_ART, po.P, t2, po.HandPoint(), 0.8, 80 * k, false, 0) { po.ScenePose("catch", 0.7); po.Say("好球！", 1.4) }
            }
        }
        At(5.4) { po.Say("這次全壘打！", 1.4) }
        At(6.6) { po.ScenePose("bat", 0); di.ScenePose("hatwave", 3.2) }
        At(6.85) { [self] in
            let hx: Double = di.Cx + Double(di.dir * 5 * S)
            let hy: Double = di.Foot - Double(di.SH) + Double((di.P.BodyTop - 5) * S)
            let hand = PointF(hx, hy)
            Toss(World.BASEBALL_ART, po.P, po.HandPoint(), hand, 1.1, 170 * k, false, 0) { di.Say("（用帽子接住）酷。", 2); di.Burst(6) }
        }
        At(10.4) { po.ScenePose("hop", 0); po.Say("再來一次！再來一次！", 2) }
        At(12.6) { di.ScenePose("hattip", 1.8); di.Say("好啦，明天再來一次。", 2) }
        At(14.8) { [self] in Face(po, di); po.ScenePose("wave", 1.8); di.ScenePose("wave", 1.8); po.Say("Eh-oh!", 1.6); di.Say("Eh-oh.", 1.6) }
        At(16.8) { }
    }

    // ---------- 拉拉 × 小波：踢球、小波騎車去撿 ----------
    func SceneBallFetch(_ la: Pet, _ po: Pet) {
        Begin(la, po)
        let ball: [String] = la.P.Art["BALL"]
        // C# 的 tx／lying 是被 lambda 抓住的區域變數（共用）：用一個小盒子裝
        final class Box { var tx: Double = 0; var lying: Prop? = nil }
        let bx = Box()
        bx.tx = po.Cx
        At(0) { [self] in Face(la, po); la.ScenePose("idle", 30); po.ScenePose("idle", 30); la.Say("小波！我們來踢球！", 2) }
        At(2.0) { po.ScenePose("wave", 1.0); po.Say("好！Eh-oh!", 1.4) }
        At(3.4) { [self] in
            la.ScenePose("kick", 0.5); la.Say("踢～！", 1); la.LoseBall(true)
            let wa = WA(la.Cx, la.Foot - 4)
            let side: Double = po.Cx >= la.Cx ? 1 : -1
            bx.tx = World.Mid(po.Cx + side * 220 * k, Double(wa.Left + po.SW), Double(wa.Right - po.SW))
            bx.lying = Toss(ball, la.P, la.FootPoint(), PointF(bx.tx, la.Foot - 3.5 * Double(S)), 1.0, 130 * k, false, 30, nil)
        }
        At(3.9) { po.RaceTo(bx.tx); po.Say("我去撿！嘟嘟～", 1.6) }
        At(6.4) { [self] in RemoveProp(bx.lying); po.FaceTo(la); po.Say("找到了！", 1.4) }
        At(7.2) { [self] in Toss(ball, la.P, po.HandPoint(), la.HandPoint(), 0.9, 110 * k, false, 0) { la.LoseBall(false); la.ScenePose("twirl", 1.6); la.Say("再來一次！", 1.6); po.Say("再來一次！", 1.6) } }
        At(9.8) { po.WalkTo(la.Cx + (po.Cx < la.Cx ? -1 : 1) * Double(la.SW) * 1.0, 1.5) }
        At(12.0) { [self] in Face(la, po); la.ScenePose("hug", 2.4); po.ScenePose("hug", 2.4); la.Say("大抱抱！", 2.2); po.Say("大抱抱！", 2.2) }
        At(14.6) { }
    }

    // ---------- 大家：大抱抱 ----------
    func SceneBigHug() {
        let outs = OutPets()
        if outs.Count < 2 { AllOut(); Later(2.5) { [self] in SceneBigHug() }; return }
        let l: Pet = Lead()
        Begin(outs.ToArray())
        let lr = LineUp(ShowOrder(outs), l, 1.05)
        let all4 = outs.Count >= 4
        At(0) { l.Say(all4 ? "大家都到齊了！" : "大家過來～", 1.8) }
        At(4.8) {
            for p in outs { p.dir = p.Cx < (lr[0] + lr[1]) / 2 ? 1 : -1; p.ScenePose("hug", 3.4); p.Burst(5) }
            l.Say(all4 ? "四個一起，大～抱抱！" : "大抱抱！", 2.6)
        }
        At(8.6) { for p in outs { p.ScenePose("wave", 1.6) }; l.Say("Eh-oh! ♥", 1.6) }
        At(10.4) { }
    }

    static func SingLine(_ p: Pet) -> String {
        switch p.P.Id! {
        case "tinky": return "啦～啦～（丁丁跳舞）"
        case "dipsy": return "嘿～嘿～（打拍子）"
        case "laalaa": return "啦啦啦～♪"
        case "po": return "啦啦！再來一次！"
        default: break
        }
        return "♪～"
    }

    // ---------- 大家：拉拉起頭，一隻一隻加入唱歌跳舞 ----------
    func SceneSing() {
        let outs = OutPets()
        if outs.Count < 2 { AllOut(); Later(2.5) { [self] in SceneSing() }; return }
        let la = Get("laalaa")
        let starter: Pet = la != nil && la!.Out && outs.Contains(la!) ? la! : Lead()
        Begin(outs.ToArray())
        LineUp(ShowOrder(outs), Lead(), 1.8)
        At(0) { starter.Say("大家過來～我們來唱歌！", 2) }
        At(4.6) { for p in outs { p.FaceTo(starter); p.ScenePose("idle", 30) }; starter.ScenePose("sing", 30); starter.Say("啦啦啦～大家一起唱！♪", 2.4) }
        var d = 7.2
        for p in ShowOrder(outs) {
            if p === starter { continue }
            let pp = p
            At(d) { pp.ScenePose(pp.P.Id == "po" ? "spin" : "dance", 30); pp.Say(World.SingLine(pp), 2); pp.Mark(0) }
            d += 1.9
        }
        At(d + 0.4) { for p in outs { p.ScenePose(p.P.Id == "laalaa" ? "twirl" : "dance", 2.6); p.Mark(0); p.Mark(0) }; starter.Say("啦啦啦～大家一起～♪", 2.4) }
        At(d + 3.2) { for p in outs { p.ScenePose("wave", 1.6) }; starter.Say("再來一次！", 1.6) }
        At(d + 5.0) { }
    }

    // ---------- 大家：一、二、三，一起跌倒「哎喲！」 ----------
    func SceneFall() {
        let outs = OutPets()
        if outs.Count < 2 { AllOut(); Later(2.5) { [self] in SceneFall() }; return }
        let l: Pet = Lead()
        Begin(outs.ToArray())
        LineUp(ShowOrder(outs), l, 1.6)
        At(0) { l.Say("大家排好～", 1.6) }
        At(4.6) { for p in outs { p.ScenePose("idle", 30) }; l.Say("大家一起…一、二、三！", 2) }
        At(6.6) { for p in outs { p.ScenePose("hop", 0) } }
        At(7.3) { for p in outs { p.ScenePose("plop", 2.2); p.Mark(4) }; l.Say("哎喲！", 1.4) }
        At(9.5) { for p in outs { p.ScenePose("idle", 30) }; l.Say("嘻嘻嘻～大家都跌倒了", 1.8) }
        At(11.4) { l.Say("再來一次！", 1.6); for p in outs { p.ScenePose("hop", 0) } }
        At(12.8) { }
    }

    // ---------- 大家：吐司時間（吐司彈出來，屑屑掉滿地，吸吸來打掃）----------
    func SceneToast() {
        let outs = OutPets()
        if outs.Count < 2 { AllOut(); Later(2.5) { [self] in SceneToast() }; return }
        let l: Pet = Lead()
        Begin(outs.ToArray())
        let order = ShowOrder(outs)
        let lr = LineUp(order, l, 1.75)
        let cx = (lr[0] + lr[1]) / 2, foot = lr[2]
        At(0) { l.Say("吐司時間！🍞", 1.8) }
        At(4.2) { for p in outs { p.FaceTo(l); p.ScenePose("idle", 30) }; l.Say("吐司！吐司！吐司！", 2) }
        var d = 4.6
        for p in order {
            let pp = p
            At(d) { [self] in
                Toss(World.TOAST_ART, pp.P, PointF(cx, foot - 2 * Double(S)), pp.HandPoint(), 0.75, 170 * k, true, 0) { pp.HoldToast = true; pp.Say("吐司！", 0.65) }
            }
            d += 0.7
        }
        At(d + 0.8) { l.Say("好好吃～屑屑掉滿地了", 2) }
        At(d + 3.0) { order[order.Count - 1].Say("糟糕…要打掃了！", 1.8) }
        At(d + 3.6) { [self] in StartBot(cx, foot) }
        At(d + 4.6) { order[0].Say("吸吸來了！", 1.6); for p in outs { p.Mark(1) } }
        At(d + 6.8) { for p in outs { p.HoldToast = false; p.ClearCrumbs() }; l.Say("吸～吸～好乾淨！", 2) }
        At(d + 9.4) { for p in outs { p.ScenePose("wave", 1.6) }; l.Say("吸吸，謝謝你！Eh-oh!", 2) }
        At(d + 11.6) { }
    }

    // 吸吸：從比較近的螢幕邊滾進來，在大家腳邊來回吸，再滾出去
    func StartBot(_ cx: Double, _ foot: Double) {
        if Hidden { return }
        let wa = WA(cx, foot - 4)
        let ps = Math.Max(2, S * 3 / 4)
        let fromLeft = cx - Double(wa.Left) < Double(wa.Right) - cx
        let sx: Double = fromLeft ? Double(wa.Left - 8 * ps) : Double(wa.Right + 8 * ps)
        let ex: Double = fromLeft ? Double(wa.Right + 10 * ps) : Double(wa.Left - 10 * ps)
        let by: Double = foot - 4.5 * Double(ps) - Double(Math.Max(1, ps / 3))
        let owner = Pal.Get("tinky")!
        let b = NewProp(World.BOT_A, World.BOT_B, owner, ps, sx, by, false)
        let sweep = 90 * k, side: Double = fromLeft ? 1 : -1
        let t1 = Math.Min(3.0, Math.Abs(cx - sx) / (260 * k) + 0.6)
        b.Go(cx - side * sweep, by, t1, 0, nil)
         .Go(cx + side * sweep, by, 1.4, 0, nil)
         .Go(cx - side * sweep * 0.5, by, 1.0, 0, nil)
         .Go(cx + side * sweep * 0.3, by, 0.7, 0, nil)
         .Go(ex, by, Math.Min(3.0, Math.Abs(ex - cx) / (260 * k) + 0.6), 0, nil)
        b.Hold = 0
    }

    // ---------- 早上點名：丁丁！迪西！拉拉！小波！天線寶寶，Eh-oh! ----------
    func TubbyRollCall(_ ids: List<String>) {
        let order = List<Pet>()
        for id in Pal.LineupIds(lineup) { if ids.Contains(id) && Get(id) != nil { order.Add(Get(id)!) } }
        var d = 0.4
        for p in order {
            let pp = p
            Later(d) { [self] in if !pp.Out { BringOut(pp, false) } }
            Later(d + 0.7) { pp.Say(pp.P.Name + "！", 1.8) }
            d += 1.5
        }
        Later(d + 0.8) { [self] in
            for p in order { if p.Out && p.Grounded() { p.ScenePose("wave", 1.8); p.Say("Eh-oh!", 2) } }
            if order.Count > 0 { Lead().Say("天線寶寶，Eh-oh! ☀", 2.6) }
        }
    }

    // ---------- 天線寶寶說再見：一隻一隻揮手回櫃子；最後從櫃子裡再說一次再見 ----------
    func SceneByeBye(_ night: Bool) {
        let outs = ShowOrder(OutPets())
        if outs.Count == 0 { let l0: Pet = Lead(); l0.Say("天線寶寶說再見！再見～", 3); return }
        let lead: Pet = Lead()
        Begin(outs.ToArray())
        for p in outs { if p.Grounded() { p.ScenePose("idle", 60) } }
        var d = 0.2
        if night { for p in outs { let pp = p; At(d) { pp.Say(pp.L("nag"), 2.6) }; d += 2.8 } }
        At(d) { lead.Say("天線寶寶，說再見的時間到了～", 2.6) }
        d += 2.8
        for p in outs {
            let pp = p
            At(d) { pp.ScenePose("wave", 2.2); pp.Say(pp.P.Name + "說再見！👋", 2.2) }
            At(d + 1.7) { pp.InScene = false; if pp.Out { pp.StowToShelf(false) } }
            d += 2.6
        }
        let last = outs[outs.Count - 1]
        At(d + 0.4) { last.Say("天線寶寶說再見！再見～", 3) }
        At(d + 3.8) { [self] in let po: Pet = Get("po") ?? last; po.Say("……再見～（偷偷揮手）", 2.2) }
        At(d + 6.2) { }
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
