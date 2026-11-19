// Desk Pals：小本子的資料（跟畫面分開；Mac 版照這支逐段移植）。
// 收集器（work-sources 分支）把做過的事寫成一行一筆 JSON：<DataDir>\notebook\log-YYYY-MM-DD.jsonl（格式見 v011 SPEC 2b）。
// 小本子只讀 log＋自己的檔（todo.json、note-*.txt、edits-*.json），合併、分組、白話狀態、複製的字都在這裡算。
// 這個檔沒有任何視窗或畫圖的東西：輸入是一串事實（NbFact），輸出是要畫的列（NbThing）和要貼出去的字。
// 刻意寫成 C# 5（不用 $"" / ?. / => 成員 / nameof）；using 放在 namespace 裡面（desk-pals.ps1 會把檔案接在一起編譯）。
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.Globalization;
    using System.IO;
    using System.Text;
    using System.Text.RegularExpressions;
    using System.Web.Script.Serialization;

    // 一筆事實（log 的一行）
    class NbFact
    {
        public string Id = "", Src = "", Project = "", Title = "", Status = "", Ref = "", Url = "", Key = "";
        public DateTime T, End;
        public bool HasEnd;
        public int Ok = -1;            // -1 不知道、0 沒過、1 過了
        public bool Todo, TodoSet;     // Jira 指派給我、還沒結：todo=true（只放待辦，不放今天做了）；todo=false＝不再是了
        public bool Retried;           // CI：之前沒過、重跑才過（retried=true）
        public bool Gone;              // gone=true：這筆收回（例如待辦勾錯了又取消）
        public bool Class;             // 學校行事曆的課（小本子自己從 ICS 算的，不寫進 log）
        public int Seq;                // 在檔案裡的順序（同一刻的照寫入順序）
    }

    // 一句話的結果字：0 一般（棕）、1 好（綠）、2 壞（紅）
    class NbWord { public string Text; public int Kind; public NbWord(string t, int k) { Text = t; Kind = k; } }

    // 今天做了的一件事：主要那筆＋掛在底下的（Jira、MR／PR、CI）
    class NbThing
    {
        public NbFact F;
        public readonly List<NbFact> Kids = new List<NbFact>();
        public readonly Dictionary<NbFact, NbFact> Fold = new Dictionary<NbFact, NbFact>();   // MR／PR → 同一個分支的 CI（接在同一句）
        public string Group = "", Title = "";
        public bool Off;
    }

    // 使用者在今天做了改過的：不複製、改過的標題、刪掉的（手寫的）
    class NbEdits
    {
        public readonly HashSet<string> Off = new HashSet<string>();
        public readonly Dictionary<string, string> Titles = new Dictionary<string, string>();
        public readonly HashSet<string> Gone = new HashSet<string>();
    }

    // 一件待辦（自己寫的、學校的作業）
    class NbTodo
    {
        public string Id = "", Text = "", Due = "", Created = "", Src = "", Course = "", Ref = "";   // Due：yyyy-MM-dd 或 yyyy-MM-ddTHH:mm；Src：""＝自己寫的、school＝學校作業（Ref＝作業 id）
    }

    static class Nb
    {
        public static readonly CultureInfo Inv = CultureInfo.InvariantCulture;
        static readonly string[] WeekDay = { "日", "一", "二", "三", "四", "五", "六" };
        public const string Meet = "會議", Other = "其他";

        // ================= 檔案 =================
        public static string Dir(string dataDir) { return Path.Combine(dataDir, "notebook"); }
        public static string Ymd(DateTime d) { return d.ToString("yyyy-MM-dd", Inv); }
        public static string LogPath(string dir, DateTime day) { return Path.Combine(dir, "log-" + Ymd(day) + ".jsonl"); }
        public static string NotePath(string dir, DateTime day) { return Path.Combine(dir, "note-" + Ymd(day) + ".txt"); }
        public static string EditsPath(string dir, DateTime day) { return Path.Combine(dir, "edits-" + Ymd(day) + ".json"); }
        public static string TodoPath(string dir) { return Path.Combine(dir, "todo.json"); }

        // 收集器和小本子都可能寫同一個 log：一次寫一整行，同一個程式裡用這把鎖
        public static readonly object LogLock = new object();

        public static string Str(Dictionary<string, object> o, string k)
        {
            object v;
            if (!o.TryGetValue(k, out v) || v == null) return "";
            return Convert.ToString(v, Inv).Trim();
        }
        static int Tri(Dictionary<string, object> o, string k)
        {
            object v;
            if (!o.TryGetValue(k, out v) || v == null) return -1;
            if (v is bool) return (bool)v ? 1 : 0;
            string s = Convert.ToString(v, Inv).Trim().ToLowerInvariant();
            return s == "true" || s == "1" ? 1 : (s == "false" || s == "0" ? 0 : -1);
        }

        // ISO 時間（本地時間；有時區的換成本地）
        public static bool ParseTime(string s, out DateTime t)
        {
            t = DateTime.MinValue;
            if (string.IsNullOrEmpty(s)) return false;
            return DateTime.TryParse(s, Inv, DateTimeStyles.AssumeLocal, out t);
        }

        public static NbFact ParseFact(string line, int seq)
        {
            line = (line ?? "").Trim();
            if (line == "" || line[0] != '{') return null;
            Dictionary<string, object> o;
            try { o = new JavaScriptSerializer().DeserializeObject(line) as Dictionary<string, object>; }
            catch { return null; }
            if (o == null) return null;
            NbFact f = new NbFact();
            f.Id = Str(o, "id"); f.Src = Str(o, "src").ToLowerInvariant(); f.Project = Str(o, "project"); f.Title = OneLine(Str(o, "title"));
            f.Status = OneLine(Str(o, "status")); f.Ref = Str(o, "ref"); f.Url = Str(o, "url"); f.Key = Str(o, "key");
            if (f.Id == "" || !ParseTime(Str(o, "t"), out f.T)) return null;
            f.HasEnd = ParseTime(Str(o, "end"), out f.End) && f.End >= f.T;
            f.Ok = Tri(o, "ok");
            f.TodoSet = o.ContainsKey("todo"); f.Todo = Tri(o, "todo") == 1;
            f.Retried = Tri(o, "retried") == 1;
            f.Gone = Tri(o, "gone") == 1;
            f.Seq = seq;
            return f;
        }

        public static string FactJson(NbFact f)
        {
            Dictionary<string, object> o = new Dictionary<string, object>();
            o["id"] = f.Id; o["t"] = f.T.ToString("yyyy-MM-ddTHH:mm:ss", Inv);
            if (f.HasEnd) o["end"] = f.End.ToString("yyyy-MM-ddTHH:mm:ss", Inv);
            o["src"] = f.Src;
            if (f.Project != "") o["project"] = f.Project;
            o["title"] = f.Title;
            if (f.Status != "") o["status"] = f.Status;
            if (f.Ok >= 0) o["ok"] = f.Ok == 1;
            if (f.Ref != "") o["ref"] = f.Ref;
            if (f.Url != "") o["url"] = f.Url;
            if (f.Key != "") o["key"] = f.Key;
            if (f.Gone) o["gone"] = true;
            return new JavaScriptSerializer().Serialize(o);
        }

        // 一天的 log：同一個 id 後寫的蓋前寫的（位置照第一次出現）
        public static List<NbFact> ReadLog(string dir, DateTime day)
        {
            List<NbFact> list = new List<NbFact>();
            string path = LogPath(dir, day);
            string[] lines;
            try { if (!File.Exists(path)) return list; lock (LogLock) lines = File.ReadAllLines(path, Encoding.UTF8); }
            catch { return list; }
            Dictionary<string, int> at = new Dictionary<string, int>();
            for (int i = 0; i < lines.Length; i++)
            {
                NbFact f = ParseFact(lines[i], i);
                if (f == null) continue;
                int j;
                if (at.TryGetValue(f.Id, out j)) { f.Seq = list[j].Seq; list[j] = f; }
                else { at[f.Id] = list.Count; list.Add(f); }
            }
            return list;
        }

        public static void AppendLog(string dir, NbFact f)
        {
            try
            {
                Directory.CreateDirectory(dir);
                lock (LogLock) File.AppendAllText(LogPath(dir, f.T.Date), FactJson(f) + "\n", new UTF8Encoding(false));
            }
            catch { }
        }

        public static string ReadFile(string path) { try { return File.Exists(path) ? File.ReadAllText(path, Encoding.UTF8) : ""; } catch { return ""; } }
        public static void WriteFile(string path, string s)
        {
            try { Directory.CreateDirectory(Path.GetDirectoryName(path)); File.WriteAllText(path, s, new UTF8Encoding(false)); } catch { }
        }

        public static NbEdits LoadEdits(string dir, DateTime day)
        {
            NbEdits e = new NbEdits();
            string s = ReadFile(EditsPath(dir, day));
            if (s.Trim() == "") return e;
            try
            {
                Dictionary<string, object> o = new JavaScriptSerializer().DeserializeObject(s) as Dictionary<string, object>;
                if (o == null) return e;
                object v;
                if (o.TryGetValue("off", out v) && v is object[]) foreach (object x in (object[])v) e.Off.Add(Convert.ToString(x, Inv));
                if (o.TryGetValue("gone", out v) && v is object[]) foreach (object x in (object[])v) e.Gone.Add(Convert.ToString(x, Inv));
                if (o.TryGetValue("titles", out v) && v is Dictionary<string, object>)
                    foreach (KeyValuePair<string, object> kv in (Dictionary<string, object>)v) e.Titles[kv.Key] = OneLine(Convert.ToString(kv.Value, Inv));
            }
            catch { }
            return e;
        }

        public static void SaveEdits(string dir, DateTime day, NbEdits e)
        {
            Dictionary<string, object> o = new Dictionary<string, object>();
            o["off"] = new List<string>(e.Off).ToArray();
            o["titles"] = e.Titles;
            o["gone"] = new List<string>(e.Gone).ToArray();
            WriteFile(EditsPath(dir, day), new JavaScriptSerializer().Serialize(o));
        }

        public static List<NbTodo> LoadTodos(string dir)
        {
            List<NbTodo> list = new List<NbTodo>();
            string s = ReadFile(TodoPath(dir));
            if (s.Trim() == "") return list;
            try
            {
                Dictionary<string, object> o = new JavaScriptSerializer().DeserializeObject(s) as Dictionary<string, object>;
                object v;
                if (o == null || !o.TryGetValue("items", out v) || !(v is object[])) return list;
                foreach (object x in (object[])v)
                {
                    Dictionary<string, object> d = x as Dictionary<string, object>;
                    if (d == null) continue;
                    NbTodo t = new NbTodo();
                    t.Id = Str(d, "id"); t.Text = OneLine(Str(d, "text")); t.Due = Str(d, "due"); t.Created = Str(d, "created");
                    t.Src = Str(d, "src"); t.Course = Str(d, "course"); t.Ref = Str(d, "ref");
                    if (t.Id != "" && t.Text != "") list.Add(t);
                }
            }
            catch { }
            return list;
        }

        public static void SaveTodos(string dir, List<NbTodo> list)
        {
            List<object> items = new List<object>();
            foreach (NbTodo t in list)
            {
                Dictionary<string, object> d = new Dictionary<string, object>();
                d["id"] = t.Id; d["text"] = t.Text; d["created"] = t.Created;
                if (t.Due != "") d["due"] = t.Due;
                if (t.Src != "") { d["src"] = t.Src; d["course"] = t.Course; d["ref"] = t.Ref; }
                items.Add(d);
            }
            Dictionary<string, object> o = new Dictionary<string, object>();
            o["items"] = items;
            WriteFile(TodoPath(dir), new JavaScriptSerializer().Serialize(o));
        }

        // Jira 指派給我、還沒結的：最近一天有寫 todo 欄位的 log（收集器每次更新就把整份寫進當天的 log）
        public static List<NbFact> JiraTodos(string dir, DateTime today)
        {
            for (int back = 0; back < 14; back++)
            {
                List<NbFact> day = ReadLog(dir, today.AddDays(-back));
                bool any = false;
                List<NbFact> open = new List<NbFact>();
                foreach (NbFact f in day)
                {
                    if (!f.TodoSet) continue;
                    any = true;
                    if (f.Todo && !f.Gone) open.Add(f);
                }
                if (any) return open;
            }
            return new List<NbFact>();
        }

        // ================= 合併、分組 =================
        static bool IsSession(NbFact f) { return f.Src == "claude" || f.Src == "codex"; }
        static bool Attachable(NbFact f) { return f.Src == "jira" || f.Src == "gitlab" || f.Src == "github" || f.Src == "ci"; }
        static bool IsCode(NbFact f) { return f.Src == "gitlab" || f.Src == "github"; }

        static List<string> Tokens(string s)
        {
            List<string> l = new List<string>();
            foreach (string x in Regex.Split(s ?? "", @"[\s,;|，、]+")) if (x.Trim() != "") l.Add(x.Trim().ToLowerInvariant());
            return l;
        }
        static bool SharedKey(NbFact f, NbFact s)
        {
            List<string> a = Tokens(f.Key + " " + f.Ref.Replace(" ", "")), b = Tokens(s.Key + " " + s.Ref.Replace(" ", ""));
            foreach (string x in a) if (b.Contains(x)) return true;
            if (f.Ref != "" && s.Title.IndexOf(f.Ref, StringComparison.OrdinalIgnoreCase) >= 0) return true;   // 對話標題裡就寫了單號
            return false;
        }
        static bool SameProject(NbFact a, NbFact b) { return a.Project != "" && string.Equals(a.Project, b.Project, StringComparison.OrdinalIgnoreCase); }

        // 一件事要掛在哪個對話底下：同一個單號／分支（key），或同一個專案、在對話期間（到結束後 15 分鐘）發生的
        static NbFact FindParent(NbFact f, List<NbFact> sessions)
        {
            NbFact best = null;
            double bestScore = double.MaxValue;
            foreach (NbFact s in sessions)
            {
                DateTime end = s.HasEnd ? s.End : s.T;
                bool key = SharedKey(f, s);
                bool near = SameProject(f, s) && f.T >= s.T.AddMinutes(-5) && f.T <= end.AddMinutes(15);
                if (!key && !near) continue;
                double score = Math.Abs((f.T - s.T).TotalMinutes) + (key ? 0 : 100000);
                if (score < bestScore) { bestScore = score; best = s; }
            }
            return best;
        }

        public static string GroupOf(NbFact f)
        {
            if (f.Src == "calendar") return f.Project != "" ? f.Project : Meet;
            return f.Project != "" ? f.Project : Other;
        }

        public static List<NbThing> Build(List<NbFact> facts, NbEdits ed)
        {
            List<NbFact> list = new List<NbFact>();
            foreach (NbFact f in facts)
            {
                if (f.Gone || f.Todo || (f.TodoSet && f.Src == "jira")) continue;   // 指派給我的單只放待辦
                if (ed != null && ed.Gone.Contains(f.Id)) continue;
                list.Add(f);
            }
            list.Sort(delegate(NbFact a, NbFact b) { int c = a.T.CompareTo(b.T); return c != 0 ? c : a.Seq.CompareTo(b.Seq); });
            List<NbFact> sessions = new List<NbFact>();
            foreach (NbFact f in list) if (IsSession(f)) sessions.Add(f);
            List<NbThing> things = new List<NbThing>();
            Dictionary<NbFact, NbThing> of = new Dictionary<NbFact, NbThing>();
            foreach (NbFact f in list)
            {
                NbFact parent = Attachable(f) ? FindParent(f, sessions) : null;
                if (parent != null && of.ContainsKey(parent)) { of[parent].Kids.Add(f); continue; }
                NbThing t = new NbThing();
                t.F = f;
                things.Add(t);
                of[f] = t;
            }
            // 同一張單、一天裡改了好幾次狀態：只留最後那次
            Dictionary<string, NbThing> lastJira = new Dictionary<string, NbThing>();
            for (int i = things.Count - 1; i >= 0; i--)
            {
                NbThing t = things[i];
                if (t.F.Src != "jira" || t.F.Ref == "") continue;
                string k = t.F.Ref.ToLowerInvariant();
                if (lastJira.ContainsKey(k)) things.RemoveAt(i); else lastJira[k] = t;
            }
            foreach (NbThing t in things)
            {
                Dictionary<string, NbFact> lastKid = new Dictionary<string, NbFact>();
                for (int i = t.Kids.Count - 1; i >= 0; i--)
                {
                    NbFact k = t.Kids[i];
                    if (k.Src != "jira" || k.Ref == "") continue;
                    string key = k.Ref.ToLowerInvariant();
                    if (lastKid.ContainsKey(key)) t.Kids.RemoveAt(i); else lastKid[key] = k;
                }
                // CI 跟同一個分支的 MR／PR 接成一句（「MR !128，CI 過了」）
                for (int i = t.Kids.Count - 1; i >= 0; i--)
                {
                    NbFact c = t.Kids[i];
                    if (c.Src != "ci") continue;
                    foreach (NbFact m in t.Kids)
                        if (IsCode(m) && m.Ref != "" && !t.Fold.ContainsKey(m) && SharedKey(c, m) && !HasCiWord(m.Status)) { t.Fold[m] = c; t.Kids.RemoveAt(i); break; }
                }
                if (IsCode(t.F) && t.F.Ref != "")
                    for (int i = 0; i < t.Kids.Count; i++)
                        if (t.Kids[i].Src == "ci" && SharedKey(t.Kids[i], t.F) && !HasCiWord(t.F.Status)) { t.Fold[t.F] = t.Kids[i]; t.Kids.RemoveAt(i); break; }
                t.Group = GroupOf(t.F);
                string nt;
                t.Title = ed != null && ed.Titles.TryGetValue(t.F.Id, out nt) && nt != "" ? nt : t.F.Title;
                t.Off = ed != null && ed.Off.Contains(t.F.Id);
            }
            // 分組：照第一件的時間；會議、其他放最後
            List<string> order = Groups(things);
            List<NbThing> sorted = new List<NbThing>();
            foreach (string g in order) foreach (NbThing t in things) if (t.Group == g) sorted.Add(t);
            return sorted;
        }

        public static List<string> Groups(List<NbThing> things)
        {
            List<string> order = new List<string>();
            foreach (NbThing t in things) if (!order.Contains(t.Group)) order.Add(t.Group);
            List<string> head = new List<string>(), tail = new List<string>();
            foreach (string g in order) if (g != Meet && g != Other) head.Add(g);
            if (order.Contains(Meet)) tail.Add(Meet);
            if (order.Contains(Other)) tail.Add(Other);
            head.AddRange(tail);
            return head;
        }

        // ================= 白話的字 =================
        static string OneLine(string s) { return Regex.Replace(s ?? "", @"[\r\n\t]+", " ").Trim(); }
        public static string Hm(DateTime t) { return t.ToString("HH':'mm", Inv); }
        public static string Span(NbFact f) { return f.HasEnd && f.End > f.T && f.Src != "ci" ? Hm(f.T) + "–" + Hm(f.End) : Hm(f.T); }
        public static string DayLabel(DateTime d) { return d.Month + "/" + d.Day + "（" + WeekDay[(int)d.DayOfWeek] + "）"; }
        public static string WeekName(DateTime d) { return "週" + WeekDay[(int)d.DayOfWeek]; }

        static bool HasCiWord(string s) { return s.StartsWith("CI") || s.IndexOf("測試") >= 0; }
        // Jira 的狀態：拿掉「工單」兩個字
        static string JiraCore(string s)
        {
            s = (s ?? "").Trim();
            if (s.StartsWith("工單")) s = s.Substring(2).Trim();
            return s;
        }
        static bool IsNew(string core) { return core == "新開" || core == "開了單" || core == "開單" || core == "建立" || core == "新建"; }

        static readonly Regex Bad = new Regex("沒過|失敗|不過|錯誤|退回|掛了|壞了");
        static readonly Regex Good = new Regex("過了|合併了|解決了|通過|完成|上線了|發了");
        public static int KindOf(string w, int ok)
        {
            if (Bad.IsMatch(w)) return 2;
            if (Good.IsMatch(w)) return 1;
            return 0;
        }

        static List<string> Split(string s)
        {
            List<string> l = new List<string>();
            foreach (string x in Regex.Split(s ?? "", "[，,]")) if (x.Trim() != "") l.Add(x.Trim());
            return l;
        }

        static string CiWord(NbFact f)
        {
            if (f.Retried && f.Ok == 1) return "CI 重跑後過了";
            if (f.Status != "") return f.Status;
            return f.Ok == 1 ? "CI 過了" : (f.Ok == 0 ? "CI 沒過" : "");
        }
        static string CiDetail(NbFact f)
        {
            if (f.Retried && f.Ok == 1) return "CI 第一次沒過，" + Hm(f.HasEnd ? f.End : f.T) + " 重跑過了";
            return CiWord(f);
        }

        static void AddWords(List<NbWord> l, NbFact f, bool top, NbThing t)
        {
            if (f.Src == "jira")
            {
                string core = JiraCore(f.Status);
                if (IsNew(core)) l.Add(new NbWord("開了單", 0));
                else if (core != "") l.Add(new NbWord(top ? core : "工單" + core, KindOf(core, f.Ok)));
                return;
            }
            if (f.Src == "ci") { string w = CiWord(f); if (w != "") l.Add(new NbWord(w, KindOf(w, f.Ok))); return; }
            foreach (string w in Split(f.Status)) l.Add(new NbWord(w, KindOf(w, f.Ok)));
            NbFact c;
            if (t != null && t.Fold.TryGetValue(f, out c)) { string w = CiWord(c); if (w != "") l.Add(new NbWord(w, KindOf(w, c.Ok))); }
        }

        // 頁面上那一句：做了什麼
        public static string PageText(NbThing t)
        {
            NbFact f = t.F;
            if (f.Src == "calendar") return t.Group == Meet ? t.Title : "開會：" + t.Title;
            if (f.Class) return t.Group == t.Title ? "上課" : "上課：" + t.Title;
            return t.Title;
        }

        // 頁面上句尾的結果字（自己的＋底下的）
        public static List<NbWord> Words(NbThing t)
        {
            List<NbWord> l = new List<NbWord>();
            AddWords(l, t.F, true, t);
            foreach (NbFact k in t.Kids) AddWords(l, k, false, t);
            return l;
        }

        // 滑過才出現的：單號、MR、時間
        public static string Ids(NbThing t)
        {
            List<string> l = new List<string>();
            if (t.F.Ref != "") l.Add(t.F.Ref);
            foreach (NbFact k in t.Kids) if (k.Ref != "" && !l.Contains(k.Ref)) l.Add(k.Ref);
            l.Add(Span(t.F));
            return string.Join("　", l.ToArray());
        }

        // 最上面一行：今天 N 件＋整體結果
        public static NbWord SumWord(List<NbThing> things)
        {
            List<string> badGroups = new List<string>();
            string badWord = "";
            bool ci = false, test = false;
            foreach (NbThing t in things)
            {
                if (t.Off) continue;
                foreach (NbWord w in Words(t))
                {
                    if (w.Text.StartsWith("CI")) ci = true;
                    if (w.Text.IndexOf("測試") >= 0) test = true;
                    if (w.Kind != 2) continue;
                    if (!badGroups.Contains(t.Group)) badGroups.Add(t.Group);
                    if (badWord == "") badWord = Regex.Replace(w.Text, @"^CI\s*", "CI ");
                }
            }
            if (badGroups.Count > 0) return new NbWord(string.Join("、", badGroups.ToArray()) + " " + badWord, 2);
            if (ci) return new NbWord("CI 都過了", 1);
            if (test) return new NbWord("測試都過了", 1);
            return null;
        }

        public static int OnCount(List<NbThing> things) { int n = 0; foreach (NbThing t in things) if (!t.Off) n++; return n; }

        // ================= 貼出去的字 =================
        static string JoinStatus(string s)
        {
            if (s == "") return "";
            char c = s[0];
            return s.StartsWith("CI") || s.StartsWith("測試") || (c < 128 && char.IsLetterOrDigit(c)) ? "，" + s : " " + s;
        }

        static string FoldText(NbThing t, NbFact f)
        {
            NbFact c;
            return t.Fold.TryGetValue(f, out c) ? CiWord(c) : "";
        }

        // 詳細的主行（不含時間）
        static string DetailTop(NbThing t)
        {
            NbFact f = t.F;
            string title = t.Title;
            if (f.Src == "calendar") return t.Group == Meet ? title : "開會：" + title;
            if (f.Class) return "上課：" + title;
            if (f.Src == "jira")
            {
                string core = JiraCore(f.Status);
                if (IsNew(core)) return ("新開 " + f.Ref + " " + title).Replace("  ", " ").Trim();
                return ((f.Ref != "" ? f.Ref + " " : "") + title + (core != "" ? "，" + core : "")).Trim();
            }
            if (IsCode(f))
            {
                string st = f.Status, fold = FoldText(t, f);
                if (fold != "") st = st == "" ? fold : st + "，" + fold;
                return (f.Ref != "" ? f.Ref + " " : "") + title + (st != "" ? "，" + st : "");
            }
            return title;
        }

        static string KidLine(NbThing t, NbFact k)
        {
            if (k.Src == "jira")
            {
                string core = JiraCore(k.Status);
                if (IsNew(core)) return "新開 " + k.Ref;
                return (k.Ref + " " + core).Trim();
            }
            if (k.Src == "ci") return CiDetail(k);
            string st = k.Status, fold = FoldText(t, k);
            if (fold != "") st = st == "" ? fold : st + "，" + fold;
            if (st == "") return (k.Ref + " " + k.Title).Trim();
            return k.Ref != "" ? k.Ref + JoinStatus(st) : st;
        }

        static string Link(bool links, string url) { return links && url != "" ? " " + url : ""; }

        public static string Simple(List<NbThing> things)
        {
            StringBuilder sb = new StringBuilder();
            foreach (NbThing t in things)
            {
                if (t.Off) continue;
                string s;
                if (t.F.Src == "calendar") s = "開會：" + t.Title;
                else if (t.F.Class) s = "上課：" + t.Title;
                else s = DetailTop(t) + (t.Group != Meet && t.Group != Other ? "（" + t.Group + "）" : "");
                if (sb.Length > 0) sb.Append("\n");
                sb.Append("・" + s);
            }
            return sb.ToString();
        }

        public static string Detail(List<NbThing> things, DateTime day, bool links)
        {
            StringBuilder sb = new StringBuilder(DayLabel(day) + "進度\n");
            string group = null;
            foreach (NbThing t in things)
            {
                if (t.Off) continue;
                if (t.Group != group) { group = t.Group; sb.Append("\n【" + group + "】\n"); }
                sb.Append("・" + Span(t.F) + " " + DetailTop(t) + Link(links, t.F.Url) + "\n");
                if (t.F.Src == "ci") { string cd = CiDetail(t.F); if (cd != "") sb.Append("　- " + cd + "\n"); }
                foreach (NbFact k in t.Kids) sb.Append("　- " + KidLine(t, k) + Link(links, k.Url) + "\n");
            }
            return sb.ToString().TrimEnd('\n');
        }

        // ================= 待辦的期限 =================
        public static bool ParseDue(string s, out DateTime due, out bool hasTime)
        {
            hasTime = s != null && s.IndexOf('T') > 0;
            due = DateTime.MinValue;
            if (string.IsNullOrEmpty(s)) return false;
            return DateTime.TryParseExact(s, hasTime ? "yyyy-MM-ddTHH:mm" : "yyyy-MM-dd", Inv, DateTimeStyles.None, out due);
        }
        public static string DueValue(DateTime day, int minute) { return minute < 0 ? Ymd(day) : Ymd(day) + "T" + (minute / 60).ToString("00", Inv) + ":" + (minute % 60).ToString("00", Inv); }

        // 「今天 18:00」「明天」「週五 23:59」「11/30」；今天以前（含今天）要紅字
        public static string DueText(string due, DateTime now, out bool urgent)
        {
            urgent = false;
            DateTime d; bool hasTime;
            if (!ParseDue(due, out d, out hasTime)) return "";
            int days = (d.Date - now.Date).Days;
            urgent = days <= 0;
            string day = days == 0 ? "今天" : (days == 1 ? "明天" : (days == -1 ? "昨天" : (days > 1 && days < 7 ? WeekName(d) : d.Month + "/" + d.Day)));
            return hasTime ? day + " " + Hm(d) : day;
        }

        public static string NewId(string prefix) { return prefix + Guid.NewGuid().ToString("N").Substring(0, 10); }
    }
}
