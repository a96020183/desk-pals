// ===== 63_notebook_data.swift — DeskPals.NotebookData.cs（小本子的資料：NbFact／NbWord／NbThing／NbEdits／NbTodo／Nb）=====
// Desk Pals：小本子的資料（跟畫面分開；Mac 版照這支逐段移植）。
// 收集器（work-sources 分支）把做過的事寫成一行一筆 JSON：<DataDir>/notebook/log-YYYY-MM-DD.jsonl（格式見 v011 SPEC 2b）。
// 小本子只讀 log＋自己的檔（todo.json、note-*.txt、edits-*.json），合併、分組、白話狀態、複製的字都在這裡算。
// 這個檔沒有任何視窗或畫圖的東西：輸入是一串事實（NbFact），輸出是要畫的列（NbThing）和要貼出去的字。
// mac 的差別（都標了 // mac:）：
// - DateTime.TryParseExact（期限 yyyy-MM-dd／yyyy-MM-ddTHH:mm）shim 沒有：Nb.ExactDue 照 .NET 的規則自己對（位數固定、不收空白）。
// - Guid.NewGuid().ToString("N") → UUID（一樣 32 個小寫十六進位）。
// - 讀 log：FileStream＋StreamReader → File.ReadAllText（一樣去掉 BOM）；FileShare 在 mac 沒有意義。
// - Regex.Split／Replace 的樣式先編好放 static（C# 的 Regex 靜態方法有快取）；\s 補上 .NET 有、ICU 沒有的 \x0B、\x85。
// - JSON 的 null：shim 給 NSNull，當成 C# 的 null。

import Foundation

// 一筆事實（log 的一行）
final class NbFact: Hashable {
    var Id = "", Src = "", Project = "", Title = "", Status = "", Ref = "", Url = "", Key = ""
    var T = DateTime.MinValue, End = DateTime.MinValue
    var HasEnd = false
    var Ok = -1            // -1 不知道、0 沒過、1 過了
    var Todo = false, TodoSet = false     // Jira 指派給我、還沒結：todo=true（只放待辦，不放今天做了）；todo=false＝不再是了
    var Retried = false           // CI：之前沒過、重跑才過（retried=true）
    var Gone = false              // gone=true：這筆收回（例如待辦勾錯了又取消）
    var Class = false             // 學校行事曆的課（小本子自己從 ICS 算的，不寫進 log）
    var Seq = 0                   // 在檔案裡的順序（同一刻的照寫入順序）
    init() { }
    // mac: C# 的 Dictionary<NbFact, …> 用參考相等
    static func == (a: NbFact, b: NbFact) -> Bool { return a === b }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}

// 一句話的結果字：0 一般（棕）、1 好（綠）、2 壞（紅）
final class NbWord { var Text: String; var Kind: Int; init(_ t: String, _ k: Int) { Text = t; Kind = k } }

// 今天做了的一件事：主要那筆＋掛在底下的（Jira、MR／PR、CI）
final class NbThing {
    var F: NbFact! = nil
    let Kids = List<NbFact>()
    let Fold = Dict<NbFact, NbFact>()   // MR／PR → 同一個分支的 CI（接在同一句）
    var Group = "", Title = ""
    var Off = false
    init() { }
}

// 使用者在今天做了改過的：不複製、改過的標題、刪掉的（手寫的）
final class NbEdits {
    let Off = HashSet<String>()
    let Titles = Dict<String, String>()
    let Gone = HashSet<String>()
    init() { }
}

// 一件待辦（自己寫的、學校的作業）
final class NbTodo {
    var Id = "", Text = "", Due = "", Created = "", Src = "", Course = "", Ref = ""   // Due：yyyy-MM-dd 或 yyyy-MM-ddTHH:mm；Src：""＝自己寫的、school＝學校作業（Ref＝作業 id）
    init() { }
}

enum Nb {
    static let Inv = CultureInfo.InvariantCulture
    static let WeekDay: [String] = ["日", "一", "二", "三", "四", "五", "六"]
    static let Meet = "會議", Other = "其他"

    // ================= 檔案 =================
    static func Dir(_ dataDir: String) -> String { return Path.Combine(dataDir, "notebook") }
    static func Ymd(_ d: DateTime) -> String { return d.ToString("yyyy-MM-dd", Inv) }
    static func LogPath(_ dir: String, _ day: DateTime) -> String { return Path.Combine(dir, "log-" + Ymd(day) + ".jsonl") }
    static func NotePath(_ dir: String, _ day: DateTime) -> String { return Path.Combine(dir, "note-" + Ymd(day) + ".txt") }
    static func EditsPath(_ dir: String, _ day: DateTime) -> String { return Path.Combine(dir, "edits-" + Ymd(day) + ".json") }
    static func TodoPath(_ dir: String) -> String { return Path.Combine(dir, "todo.json") }

    // 收集器和小本子都可能寫同一個 log：一次寫一整行，同一個程式裡用這把鎖
    static let LogLock = NSObject()

    // mac: C# Convert.ToString(null) 是 ""；shim 的 JSON null 是 NSNull
    private static func Cs(_ v: Any?) -> String {
        guard let v = v, !(v is NSNull) else { return "" }
        return Convert.ToString(v, Inv)
    }

    static func Str(_ o: Dict<String, Any>, _ k: String) -> String {
        guard let v = o.Get(k), !(v is NSNull) else { return "" }
        return Convert.ToString(v, Inv).Trim()
    }
    static func Tri(_ o: Dict<String, Any>, _ k: String) -> Int {
        guard let v = o.Get(k), !(v is NSNull) else { return -1 }
        if let b = v as? Bool { return b ? 1 : 0 }
        let s = Convert.ToString(v, Inv).Trim().ToLowerInvariant()
        return s == "true" || s == "1" ? 1 : (s == "false" || s == "0" ? 0 : -1)
    }

    // ISO 時間（本地時間；有時區的換成本地）
    @discardableResult static func ParseTime(_ s: String?, _ t: inout DateTime) -> Bool {
        t = DateTime.MinValue
        if string.IsNullOrEmpty(s) { return false }
        return DateTime.TryParse(s, Inv, DateTimeStyles.AssumeLocal, &t)
    }

    static func ParseFact(_ line0: String?, _ seq: Int) -> NbFact! {
        let line = (line0 ?? "").Trim()
        if line == "" || line[0] != "{" { return nil }
        var o0: Dict<String, Any>? = nil
        do { o0 = try JavaScriptSerializer().DeserializeObject(line) as? Dict<String, Any> }
        catch { return nil }
        guard let o = o0 else { return nil }
        let f = NbFact()
        f.Id = Str(o, "id"); f.Src = Str(o, "src").ToLowerInvariant(); f.Project = Str(o, "project"); f.Title = OneLine(Str(o, "title"))
        f.Status = OneLine(Str(o, "status")); f.Ref = Str(o, "ref"); f.Url = Str(o, "url"); f.Key = Str(o, "key")
        if f.Id == "" || !ParseTime(Str(o, "t"), &f.T) { return nil }
        var end = DateTime.MinValue
        let hasEnd = ParseTime(Str(o, "end"), &end)
        f.End = end
        f.HasEnd = hasEnd && f.End >= f.T
        f.Ok = Tri(o, "ok")
        f.TodoSet = o.ContainsKey("todo"); f.Todo = Tri(o, "todo") == 1
        f.Retried = Tri(o, "retried") == 1
        f.Gone = Tri(o, "gone") == 1
        f.Seq = seq
        Normalize(f)
        return f
    }

    // 收集器寫的字 → 小本子的說法（例：「發 v0.10.4」→「發了 v0.10.4」、學校的「上課：資料結構」→ 一堂課、推 commit 的次數）
    static func Normalize(_ f: NbFact) {
        if f.Src == "ci" && f.Title.StartsWith("發 ") { f.Title = "發了 " + f.Title.Substring(2) }
        if f.Src == "school" && f.Title.StartsWith("上課：") { f.Class = true; f.Title = f.Title.Substring(3).Trim(); if f.Project == "" { f.Project = f.Title } }
        var n = 0
        if (f.Src == "gitlab" || f.Src == "github") && int.TryParse(f.Status, &n) { f.Status = n > 0 ? "推了 " + String(n) + " 個 commit" : "推上去了" }
    }

    // 從 ICS 算的課：log 裡已經有同一堂（收集器上課時寫的，同名、開始時間差 15 分鐘內）就不再加
    static func AddClasses(_ facts: List<NbFact>, _ classes: List<NbFact>) {
        let have = List<NbFact>()
        for f in facts { if f.Class { have.Add(f) } }
        for c in classes {
            var dup = false
            for h in have { if h.Title == c.Title && Math.Abs((h.T - c.T).TotalMinutes) <= 15 { dup = true; if !h.HasEnd && c.HasEnd { h.End = c.End; h.HasEnd = true } } }
            if !dup { facts.Add(c) }
        }
    }

    static func FactJson(_ f: NbFact) -> String {
        let o = Dict<String, Any>()
        o["id"] = f.Id; o["t"] = f.T.ToString("yyyy-MM-ddTHH:mm:ss", Inv)
        if f.HasEnd { o["end"] = f.End.ToString("yyyy-MM-ddTHH:mm:ss", Inv) }
        o["src"] = f.Src
        if f.Project != "" { o["project"] = f.Project }
        o["title"] = f.Title
        if f.Status != "" { o["status"] = f.Status }
        if f.Ok >= 0 { o["ok"] = f.Ok == 1 }
        if f.Ref != "" { o["ref"] = f.Ref }
        if f.Url != "" { o["url"] = f.Url }
        if f.Key != "" { o["key"] = f.Key }
        if f.Gone { o["gone"] = true }
        return JavaScriptSerializer().Serialize(o)
    }

    // 一天的 log：同一個 id 後寫的蓋前寫的（位置照第一次出現）
    static func ReadLog(_ dir: String, _ day: DateTime) -> List<NbFact> {
        let list = List<NbFact>()
        let path = LogPath(dir, day)
        var lines: [String] = []
        do {
            if !File.Exists(path) { return list }
            // mac: FileStream（FileShare.ReadWrite | Delete）＋StreamReader → File.ReadAllText（一樣去掉 BOM）
            try lock(LogLock) { () throws -> Void in
                lines = try File.ReadAllText(path, Encoding.UTF8).Split("\n")
            }
        }
        catch { return list }
        let at = Dict<String, Int>()
        var i = 0
        while i < lines.count {
            let f: NbFact! = ParseFact(lines[i], i)
            if f != nil {
                if let j = at.Get(f.Id) { f.Seq = list[j].Seq; list[j] = f }
                else { at[f.Id] = list.Count; list.Add(f) }
            }
            i += 1
        }
        return list
    }

    static func AppendLog(_ dir: String, _ f: NbFact) {
        do {
            try Directory.CreateDirectory(dir)
            let b: [UInt8] = UTF8Encoding(false).GetBytes(FactJson(f) + "\n")
            try lock(LogLock) { () throws -> Void in
                let fs = try FileStream(LogPath(dir, f.T.Date), FileMode.Append, FileAccess.Write, FileShare.ReadWrite)   // 跟收集器（DeskPals.Work.cs 的 NoteLog）同一種開法
                try fs.Write(b, 0, b.count)
                fs.Close()
            }
        }
        catch { }
    }

    static func ReadFile(_ path: String) -> String {
        do {
            if !File.Exists(path) { return "" }
            return try File.ReadAllText(path, Encoding.UTF8)
        }
        catch { return "" }
    }
    static func WriteFile(_ path: String, _ s: String) {
        do { try Directory.CreateDirectory(Path.GetDirectoryName(path)); try File.WriteAllText(path, s, UTF8Encoding(false)) } catch { }
    }

    static func LoadEdits(_ dir: String, _ day: DateTime) -> NbEdits {
        let e = NbEdits()
        let s = ReadFile(EditsPath(dir, day))
        if s.Trim() == "" { return e }
        do {
            guard let o = try JavaScriptSerializer().DeserializeObject(s) as? Dict<String, Any> else { return e }
            if let v = o.Get("off") as? [Any] { for x in v { e.Off.Add(Cs(x)) } }
            if let v = o.Get("gone") as? [Any] { for x in v { e.Gone.Add(Cs(x)) } }
            if let v = o.Get("titles") as? Dict<String, Any> {
                for kv in v { e.Titles[kv.Key] = OneLine(Cs(kv.Value)) }
            }
        }
        catch { }
        return e
    }

    static func SaveEdits(_ dir: String, _ day: DateTime, _ e: NbEdits) {
        let o = Dict<String, Any>()
        o["off"] = e.Off.ToArray()
        o["titles"] = e.Titles
        o["gone"] = e.Gone.ToArray()
        WriteFile(EditsPath(dir, day), JavaScriptSerializer().Serialize(o))
    }

    static func LoadTodos(_ dir: String) -> List<NbTodo> {
        let list = List<NbTodo>()
        let s = ReadFile(TodoPath(dir))
        if s.Trim() == "" { return list }
        do {
            guard let o = try JavaScriptSerializer().DeserializeObject(s) as? Dict<String, Any>, let v = o.Get("items") as? [Any] else { return list }
            for x in v {
                guard let d = x as? Dict<String, Any> else { continue }
                let t = NbTodo()
                t.Id = Str(d, "id"); t.Text = OneLine(Str(d, "text")); t.Due = Str(d, "due"); t.Created = Str(d, "created")
                t.Src = Str(d, "src"); t.Course = Str(d, "course"); t.Ref = Str(d, "ref")
                if t.Id != "" && t.Text != "" { list.Add(t) }
            }
        }
        catch { }
        return list
    }

    static func SaveTodos(_ dir: String, _ list: List<NbTodo>) {
        var items: [Any] = []
        for t in list {
            let d = Dict<String, Any>()
            d["id"] = t.Id; d["text"] = t.Text; d["created"] = t.Created
            if t.Due != "" { d["due"] = t.Due }
            if t.Src != "" { d["src"] = t.Src; d["course"] = t.Course; d["ref"] = t.Ref }
            items.append(d)
        }
        let o = Dict<String, Any>()
        o["items"] = items
        WriteFile(TodoPath(dir), JavaScriptSerializer().Serialize(o))
    }

    // Jira 指派給我、還沒結的：收集器每次查完整份寫進 notebook/jira-open.json（[{"key","title","status","url"}]）
    static func JiraTodos(_ dir: String) -> List<NbFact> {
        let list = List<NbFact>()
        let s = ReadFile(Path.Combine(dir, "jira-open.json"))
        if s.Trim() == "" { return list }
        do {
            guard let a = try JavaScriptSerializer().DeserializeObject(s) as? [Any] else { return list }
            for x in a {
                guard let d = x as? Dict<String, Any>, Str(d, "key") != "" else { continue }
                let f = NbFact()
                f.Id = "jira:" + Str(d, "key") + ":open"; f.Src = "jira"; f.Ref = Str(d, "key"); f.Title = OneLine(Str(d, "title")); f.Status = OneLine(Str(d, "status")); f.Url = Str(d, "url")
                f.Todo = true
                list.Add(f)
            }
        }
        catch { }
        return list
    }

    // ================= 合併、分組 =================
    static func IsSession(_ f: NbFact) -> Bool { return f.Src == "claude" || f.Src == "codex" }
    static func Attachable(_ f: NbFact) -> Bool { return f.Src == "jira" || f.Src == "gitlab" || f.Src == "github" || f.Src == "ci" }
    static func IsCode(_ f: NbFact) -> Bool { return f.Src == "gitlab" || f.Src == "github" }

    // mac: .NET 的 \s 還多 \x0B、\x85（ICU 的 \s 沒有）
    private static let TokSplit = Regex("[\\s\\x0B\\x85,;|，、]+")
    static func Tokens(_ s: String?) -> List<String> {
        let l = List<String>()
        for x in TokSplit.Split(s ?? "") { if x.Trim() != "" { l.Add(x.Trim().ToLowerInvariant()) } }
        return l
    }
    static func SharedKey(_ f: NbFact, _ s: NbFact) -> Bool {
        let a = Tokens(f.Key + " " + f.Ref.Replace(" ", "")), b = Tokens(s.Key + " " + s.Ref.Replace(" ", ""))
        let pa = f.Project.ToLowerInvariant(), pb = s.Project.ToLowerInvariant()
        for x in a {
            let skipA: Bool = x == pa || (pa != "" && x.EndsWith("/" + pa))
            let skipB: Bool = x == pb || (pb != "" && x.EndsWith("/" + pb))
            if skipA || skipB { continue }   // 收集器把 repo 名也放進 key：同一個專案不算同一件事（交給時間判斷）
            if b.Contains(x) { return true }
        }
        if f.Ref != "" && s.Title.IndexOf(f.Ref, StringComparison.OrdinalIgnoreCase) >= 0 { return true }   // 對話標題裡就寫了單號
        return false
    }
    static func SameProject(_ a: NbFact, _ b: NbFact) -> Bool { return a.Project != "" && string.Equals(a.Project, b.Project, StringComparison.OrdinalIgnoreCase) }

    // 一件事要掛在哪個對話底下：同一個單號／分支（key），或同一個專案、在對話期間（到結束後 15 分鐘）發生的
    static func FindParent(_ f: NbFact, _ sessions: List<NbFact>) -> NbFact! {
        var best: NbFact! = nil
        var bestScore = double.MaxValue
        for s in sessions {
            let end: DateTime = s.HasEnd ? s.End : s.T
            let key = SharedKey(f, s)
            let near: Bool = SameProject(f, s) && f.T >= s.T.AddMinutes(-5) && f.T <= end.AddMinutes(15)
            if !key && !near { continue }
            let score: Double = Math.Abs((f.T - s.T).TotalMinutes) + (key ? 0.0 : 100000.0)
            if score < bestScore { bestScore = score; best = s }
        }
        return best
    }

    static func GroupOf(_ f: NbFact) -> String {
        if f.Src == "calendar" { return f.Project != "" ? f.Project : Meet }
        return f.Project != "" ? f.Project : Other
    }

    static func Build(_ facts: List<NbFact>, _ ed: NbEdits!) -> List<NbThing> {
        let list = List<NbFact>()
        for f in facts {
            if f.Gone || f.Todo || (f.TodoSet && f.Src == "jira") { continue }   // 指派給我的單只放待辦
            if ed != nil && ed.Gone.Contains(f.Id) { continue }
            list.Add(f)
        }
        list.Sort { (a: NbFact, b: NbFact) -> Int in let c = a.T.CompareTo(b.T); return c != 0 ? c : a.Seq.CompareTo(b.Seq) }
        let sessions = List<NbFact>()
        for f in list { if IsSession(f) { sessions.Add(f) } }
        let things = List<NbThing>()
        let of = Dict<NbFact, NbThing>()
        for f in list {
            let parent: NbFact! = Attachable(f) ? FindParent(f, sessions) : nil
            if parent != nil, let pt = of.Get(parent) { pt.Kids.Add(f); continue }
            let t = NbThing()
            t.F = f
            things.Add(t)
            of[f] = t
        }
        // 同一張單、一天裡改了好幾次狀態：只留最後那次
        let lastJira = Dict<String, NbThing>()
        for i in stride(from: things.Count - 1, through: 0, by: -1) {
            let t = things[i]
            if t.F.Src != "jira" || t.F.Ref == "" { continue }
            let k = t.F.Ref.ToLowerInvariant()
            if lastJira.ContainsKey(k) { things.RemoveAt(i) } else { lastJira[k] = t }
        }
        for t in things {
            let lastKid = Dict<String, NbFact>()
            for i in stride(from: t.Kids.Count - 1, through: 0, by: -1) {
                let k = t.Kids[i]
                if k.Src != "jira" || k.Ref == "" { continue }
                let key = k.Ref.ToLowerInvariant()
                if lastKid.ContainsKey(key) { t.Kids.RemoveAt(i) } else { lastKid[key] = k }
            }
            // CI 跟同一個分支的 MR／PR 接成一句（「MR !128，CI 過了」）
            for i in stride(from: t.Kids.Count - 1, through: 0, by: -1) {
                let c = t.Kids[i]
                if c.Src != "ci" { continue }
                for m in t.Kids {
                    if IsCode(m) && m.Ref != "" && !t.Fold.ContainsKey(m) && SharedKey(c, m) && !HasCiWord(m.Status) { t.Fold[m] = c; t.Kids.RemoveAt(i); break }
                }
            }
            if IsCode(t.F) && t.F.Ref != "" {
                var i = 0
                while i < t.Kids.Count {
                    if t.Kids[i].Src == "ci" && SharedKey(t.Kids[i], t.F) && !HasCiWord(t.F.Status) { t.Fold[t.F] = t.Kids[i]; t.Kids.RemoveAt(i); break }
                    i += 1
                }
            }
            t.Group = GroupOf(t.F)
            var nt: String? = nil
            var has = false
            if ed != nil { has = ed.Titles.TryGetValue(t.F.Id, &nt) }
            t.Title = has && nt != nil && nt! != "" ? nt! : t.F.Title
            t.Off = ed != nil && ed.Off.Contains(t.F.Id)
        }
        // 分組：照第一件的時間；會議、其他放最後
        let order = Groups(things)
        let sorted = List<NbThing>()
        for g in order { for t in things { if t.Group == g { sorted.Add(t) } } }
        return sorted
    }

    static func Groups(_ things: List<NbThing>) -> List<String> {
        let order = List<String>()
        for t in things { if !order.Contains(t.Group) { order.Add(t.Group) } }
        let head = List<String>(), tail = List<String>()
        for g in order { if g != Meet && g != Other { head.Add(g) } }
        if order.Contains(Meet) { tail.Add(Meet) }
        if order.Contains(Other) { tail.Add(Other) }
        head.AddRange(tail)
        return head
    }

    // ================= 白話的字 =================
    private static let OneLineRx = Regex("[\\r\\n\\t]+")
    static func OneLine(_ s: String?) -> String { return OneLineRx.Replace(s ?? "", " ").Trim() }
    static func Hm(_ t: DateTime) -> String { return t.ToString("HH':'mm", Inv) }
    static func Span(_ f: NbFact) -> String { return f.HasEnd && f.End > f.T && f.Src != "ci" ? Hm(f.T) + "–" + Hm(f.End) : Hm(f.T) }
    static func DayLabel(_ d: DateTime) -> String { return String(d.Month) + "/" + String(d.Day) + "（" + WeekDay[d.DayOfWeek.rawValue] + "）" }
    static func WeekName(_ d: DateTime) -> String { return "週" + WeekDay[d.DayOfWeek.rawValue] }

    static func HasCiWord(_ s: String) -> Bool { return s.StartsWith("CI") || s.IndexOf("測試") >= 0 }
    // Jira 的狀態：拿掉「工單」兩個字
    static func JiraCore(_ s0: String?) -> String {
        var s = (s0 ?? "").Trim()
        if s.StartsWith("工單") { s = s.Substring(2).Trim() }
        return s
    }
    static func IsNew(_ core: String) -> Bool { return core == "新開" || core == "開了單" || core == "開單" || core == "建立" || core == "新建" }

    static let Bad = Regex("沒過|失敗|不過|錯誤|退回|掛了|壞了")
    static let Good = Regex("過了|合併了|解決了|通過|完成|上線了|發了")
    static func KindOf(_ w: String, _ ok: Int) -> Int {
        if Bad.IsMatch(w) { return 2 }
        if Good.IsMatch(w) { return 1 }
        return 0
    }

    private static let ListSplit = Regex("[，,]")
    static func Split(_ s: String?) -> List<String> {
        let l = List<String>()
        for x in ListSplit.Split(s ?? "") { if x.Trim() != "" { l.Add(x.Trim()) } }
        return l
    }

    static func CiWord(_ f: NbFact) -> String {
        if f.Retried && f.Ok == 1 { return "CI 重跑後過了" }
        if f.Status != "" { return f.Status }
        return f.Ok == 1 ? "CI 過了" : (f.Ok == 0 ? "CI 沒過" : "")
    }
    static func CiDetail(_ f: NbFact) -> String {
        if f.Retried && f.Ok == 1 { return "CI 第一次沒過，" + Hm(f.HasEnd ? f.End : f.T) + " 重跑過了" }
        return CiWord(f)
    }

    static func AddWords(_ l: List<NbWord>, _ f: NbFact, _ top: Bool, _ t: NbThing!) {
        if f.Src == "jira" {
            let core = JiraCore(f.Status)
            if IsNew(core) { l.Add(NbWord("開了單", 0)) }
            else if core != "" { l.Add(NbWord(top ? core : "工單" + core, KindOf(core, f.Ok))) }
            return
        }
        if f.Src == "ci" { let w = CiWord(f); if w != "" { l.Add(NbWord(w, KindOf(w, f.Ok))) }; return }
        for w in Split(f.Status) { l.Add(NbWord(w, KindOf(w, f.Ok))) }
        if t != nil, let c = t.Fold.Get(f) { let w = CiWord(c); if w != "" { l.Add(NbWord(w, KindOf(w, c.Ok))) } }
    }

    // 頁面上那一句：做了什麼
    static func PageText(_ t: NbThing) -> String {
        let f: NbFact = t.F
        if f.Src == "calendar" { return t.Group == Meet ? t.Title : "開會：" + t.Title }
        if f.Class { return t.Group == t.Title ? "上課" : "上課：" + t.Title }
        return t.Title
    }

    // 頁面上句尾的結果字（自己的＋底下的）
    static func Words(_ t: NbThing) -> List<NbWord> {
        let l = List<NbWord>()
        AddWords(l, t.F, true, t)
        for k in t.Kids { AddWords(l, k, false, t) }
        return l
    }

    // 滑過才出現的：單號、MR、時間
    static func Ids(_ t: NbThing) -> String {
        let l = List<String>()
        if t.F.Ref != "" { l.Add(t.F.Ref) }
        for k in t.Kids { if k.Ref != "" && !l.Contains(k.Ref) { l.Add(k.Ref) } }
        l.Add(Span(t.F))
        return string.Join("　", l.ToArray())
    }

    // 最上面一行：今天 N 件＋整體結果
    private static let CiHead = Regex("^CI\\s*")
    static func SumWord(_ things: List<NbThing>) -> NbWord! {
        let badGroups = List<String>()
        var badWord = ""
        var ci = false, test = false
        for t in things {
            if t.Off { continue }
            for w in Words(t) {
                if w.Text.StartsWith("CI") { ci = true }
                if w.Text.IndexOf("測試") >= 0 { test = true }
                if w.Kind != 2 { continue }
                if !badGroups.Contains(t.Group) { badGroups.Add(t.Group) }
                if badWord == "" { badWord = CiHead.Replace(w.Text, "CI ") }
            }
        }
        if badGroups.Count > 0 { return NbWord(string.Join("、", badGroups.ToArray()) + " " + badWord, 2) }
        if ci { return NbWord("CI 都過了", 1) }
        if test { return NbWord("測試都過了", 1) }
        return nil
    }

    static func OnCount(_ things: List<NbThing>) -> Int { var n = 0; for t in things { if !t.Off { n += 1 } }; return n }

    // ================= 貼出去的字 =================
    static func JoinStatus(_ s: String) -> String {
        if s == "" { return "" }
        let c: Character = s[0]
        let ascii: Bool = c.Code < 128 && char.IsLetterOrDigit(c)
        return s.StartsWith("CI") || s.StartsWith("測試") || ascii ? "，" + s : " " + s
    }

    static func FoldText(_ t: NbThing, _ f: NbFact) -> String {
        if let c = t.Fold.Get(f) { return CiWord(c) }
        return ""
    }

    // 詳細的主行（不含時間）
    static func DetailTop(_ t: NbThing) -> String {
        let f: NbFact = t.F
        let title = t.Title
        if f.Src == "calendar" { return t.Group == Meet ? title : "開會：" + title }
        if f.Class { return "上課：" + title }
        if f.Src == "jira" {
            let core = JiraCore(f.Status)
            if IsNew(core) { return ("新開 " + f.Ref + " " + title).Replace("  ", " ").Trim() }
            let head: String = f.Ref != "" ? f.Ref + " " : ""
            let tailS: String = core != "" ? "，" + core : ""
            return (head + title + tailS).Trim()
        }
        if IsCode(f) {
            var st = f.Status
            let fold = FoldText(t, f)
            if fold != "" { st = st == "" ? fold : st + "，" + fold }
            let head: String = f.Ref != "" ? f.Ref + " " : ""
            let tailS: String = st != "" ? "，" + st : ""
            return head + title + tailS
        }
        return title
    }

    static func KidLine(_ t: NbThing, _ k: NbFact) -> String {
        if k.Src == "jira" {
            let core = JiraCore(k.Status)
            if IsNew(core) { return "新開 " + k.Ref }
            return (k.Ref + " " + core).Trim()
        }
        if k.Src == "ci" { return CiDetail(k) }
        var st = k.Status
        let fold = FoldText(t, k)
        if fold != "" { st = st == "" ? fold : st + "，" + fold }
        if st == "" { return (k.Ref + " " + k.Title).Trim() }
        return k.Ref != "" ? k.Ref + JoinStatus(st) : st
    }

    static func Link(_ links: Bool, _ url: String) -> String { return links && url != "" ? " " + url : "" }

    static func Simple(_ things: List<NbThing>) -> String {
        let sb = StringBuilder()
        for t in things {
            if t.Off { continue }
            var s: String
            if t.F.Src == "calendar" { s = "開會：" + t.Title }
            else if t.F.Class { s = "上課：" + t.Title }
            else {
                let grp: String = t.Group != Meet && t.Group != Other ? "（" + t.Group + "）" : ""
                s = DetailTop(t) + grp
            }
            if sb.Length > 0 { sb.Append("\n") }
            sb.Append("・" + s)
        }
        return sb.ToString()
    }

    static func Detail(_ things: List<NbThing>, _ day: DateTime, _ links: Bool) -> String {
        let sb = StringBuilder(DayLabel(day) + "進度\n")
        var group: String? = nil
        for t in things {
            if t.Off { continue }
            if group == nil || t.Group != group! { group = t.Group; sb.Append("\n【" + t.Group + "】\n") }
            let top: String = "・" + Span(t.F) + " " + DetailTop(t)
            sb.Append(top + Link(links, t.F.Url) + "\n")
            if t.F.Src == "ci" { let cd = CiDetail(t.F); if cd != "" { sb.Append("　- " + cd + "\n") } }
            for k in t.Kids { sb.Append("　- " + KidLine(t, k) + Link(links, k.Url) + "\n") }
        }
        return sb.ToString().TrimEnd(Character("\n"))
    }

    // ================= 待辦的期限 =================
    @discardableResult static func ParseDue(_ s: String?, _ due: inout DateTime, _ hasTime: inout Bool) -> Bool {
        hasTime = s != nil && s!.IndexOf(Character("T")) > 0
        due = DateTime.MinValue
        if string.IsNullOrEmpty(s) { return false }
        return ExactDue(s!, hasTime, &due)
    }
    // mac: DateTime.TryParseExact(s, hasTime ? "yyyy-MM-ddTHH:mm" : "yyyy-MM-dd", Inv, DateTimeStyles.None, out due)：
    // shim 沒有 ParseExact，照 .NET 的規則對：yyyy 四位、MM／dd／HH／mm 兩位、只收 ASCII 數字、前後不能有空白、日期要存在
    private static func ExactDue(_ s: String, _ hasTime: Bool, _ due: inout DateTime) -> Bool {
        let u: [UInt16] = Array(s.utf16)
        let n = hasTime ? 16 : 10
        if u.count != n { return false }
        func dig(_ i: Int, _ len: Int) -> Int {
            var v = 0
            var k = i
            while k < i + len { let c = Int(u[k]); if c < 48 || c > 57 { return -1 }; v = v * 10 + c - 48; k += 1 }
            return v
        }
        if u[4] != 45 || u[7] != 45 { return false }   // '-'
        let y = dig(0, 4), mo = dig(5, 2), d = dig(8, 2)
        var h = 0, mi = 0
        if hasTime {
            if u[10] != 84 || u[13] != 58 { return false }   // 'T'、':'
            h = dig(11, 2); mi = dig(14, 2)
        }
        if y < 1 || mo < 1 || mo > 12 || d < 1 || h < 0 || h > 23 || mi < 0 || mi > 59 { return false }
        if d > DateTime.DaysInMonth(y, mo) { return false }
        due = DateTime(y, mo, d, h, mi, 0)
        return true
    }
    static func DueValue(_ day: DateTime, _ minute: Int) -> String { return minute < 0 ? Ymd(day) : Ymd(day) + "T" + (minute / 60).ToString("00", Inv) + ":" + (minute % 60).ToString("00", Inv) }

    // 「今天 18:00」「明天」「週五 23:59」「11/30」；今天以前（含今天）要紅字
    static func DueText(_ due: String?, _ now: DateTime, _ urgent: inout Bool) -> String {
        urgent = false
        var d = DateTime.MinValue
        var hasTime = false
        if !ParseDue(due, &d, &hasTime) { return "" }
        let days = (d.Date - now.Date).Days
        urgent = days <= 0
        var day: String
        if days == 0 { day = "今天" }
        else if days == 1 { day = "明天" }
        else if days == -1 { day = "昨天" }
        else if days > 1 && days < 7 { day = WeekName(d) }
        else { day = String(d.Month) + "/" + String(d.Day) }
        return hasTime ? day + " " + Hm(d) : day
    }

    // mac: Guid.NewGuid().ToString("N") → UUID（一樣 32 個小寫十六進位）
    static func NewId(_ prefix: String) -> String { return prefix + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().Substring(0, 10) }
}
