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
//
// 跟 VS Code 擴充套件：連上時（hello）送「work-own <來源,…>」，設定改了再送一次；新版擴充套件看到就不再自己查、不再自己通知。
//   舊版擴充套件（還不認得 work-own）送來的 notify，桌面版已經在管的那幾種直接丟掉（WorkDropsNotify），不會講兩次。
//
// 掛在別的檔的地方（都只有一兩行，註解寫「工作來源」）：
//   DeskPals.cs：TickInner → WorkTick()、OnMsg 的 hello → WorkHello()、notify → WorkDropsNotify()、config-host → WorkOwns("vpn")、
//     default → WorkMsg()、ClaudeProjectsDir／CodexSessionsDir → AiHomeDefault()（離屏測試不讀真的家目錄）、ClaudeWatchOnce／CodexWatchOnce → WorkClaudeRoots()／WorkCodexRoots()／WorkWslAlive()、HealthLoop → VpnReachable()、
//     小屋選單「工作」→ ShowWorkSettings()（設定視窗做好後才掛）。
//   DeskPals.Study.cs：PlanTick → WorkLogClass()（上課寫進小本子）、SchoolFetchLoop → WorkMeetUrl()（跟開會同一份行事曆不提醒兩次）。
//
// pipe 指令：
//   work-set <key> <值…|->      改設定（key 見 WorkDefaults；值「-」＝清空）。存 work-config.txt，馬上套用
//   work-token <token|->         Jira API token（DPAPI 加密存檔；「-」＝刪掉）
//   work-poll                    每個打開的來源馬上查一次
//   work-dump                    狀態（測試用）：設定、誰管哪些來源、最近的提醒、丟掉幾則重複通知、CI 在盯哪些
//   work-settings open           打開工作設定視窗（之後小本子的「來源」按鈕也叫這個）
//   測試用（只在離屏模式）：work-clock <yyyy-MM-ddTHH:mm|off>、work-vpncheck、work-forget（忘掉「已經看過」的紀錄）
// 送回擴充套件：work-own <jira,gitlab,github,ci,meet,rain,vpn,worklog|->
//
// 連到哪裡（隱私權政策用）：你填的 Jira 網站（REST API，HTTPS）、你填的行事曆網址（ICS）、wttr.in／api.met.no（下雨：只送地點）、
//   你填的公司主機（只試開 TCP 連線）；GitLab／GitHub 由 glab／gh 自己連（用它們自己的登入）。
// 寫哪些本機檔案（都在 %DataDir%）：work-config.txt、work-seen.txt、jira-token.dat、notebook\log-*.jsonl、notebook\jira-open.json。
//
// Mac 版移植（之後另外做）：DPAPI → 鑰匙圈（SecItemAdd／SecItemCopyMatching）；找 glab／gh 多看 /opt/homebrew/bin、/usr/local/bin；
//   Process → Foundation.Process；WSL 的部分不用。其他（解析、排程、紀錄格式）照搬。
// 刻意寫成 C# 5（不用 $"" / ?. / => 成員 / nameof）。
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.Diagnostics;
    using System.Globalization;
    using System.IO;
    using System.Net.Sockets;
    using System.Runtime.InteropServices;
    using System.Text;
    using System.Text.RegularExpressions;
    using System.Threading;
    using System.Web.Script.Serialization;

    // ================= 小本子的紀錄：一行一筆 JSON =================
    class NoteEntry
    {
        public string Id, Src, Project, Title, Status, Ref, Url, Key;
        public DateTime T, End = DateTime.MinValue;
        public int Ok = -1;   // -1＝null、0＝false、1＝true
    }

    static class NoteLog
    {
        static readonly object gate = new object();
        static readonly Dictionary<string, Dictionary<string, string>> days = new Dictionary<string, Dictionary<string, string>>();   // 日期 → id → 最後寫的那一行
        static readonly Regex IdRx = new Regex("^\\{\"id\":\"((?:[^\"\\\\]|\\\\.)*)\"");

        public static string Dir() { return Path.Combine(World.DataDir, "notebook"); }
        public static string FileFor(DateTime d) { return Path.Combine(Dir(), "log-" + d.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) + ".jsonl"); }
        public static string Iso(DateTime t) { return t.ToString("yyyy-MM-dd'T'HH:mm:ss", CultureInfo.InvariantCulture); }

        public static string Line(NoteEntry e)
        {
            StringBuilder sb = new StringBuilder("{\"id\":");
            Q(sb, e.Id);
            sb.Append(",\"t\":"); Q(sb, Iso(e.T));
            if (e.End != DateTime.MinValue) { sb.Append(",\"end\":"); Q(sb, Iso(e.End)); }
            Field(sb, "src", e.Src); Field(sb, "project", e.Project); Field(sb, "title", e.Title); Field(sb, "status", e.Status);
            sb.Append(",\"ok\":").Append(e.Ok < 0 ? "null" : (e.Ok > 0 ? "true" : "false"));
            Field(sb, "ref", e.Ref); Field(sb, "url", e.Url); Field(sb, "key", e.Key);
            return sb.Append('}').ToString();
        }
        static void Field(StringBuilder sb, string k, string v) { if (string.IsNullOrEmpty(v)) return; sb.Append(",\"").Append(k).Append("\":"); Q(sb, v); }
        public static void Q(StringBuilder sb, string s)
        {
            sb.Append('"');
            foreach (char ch in s ?? "")
            {
                switch (ch)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (ch < 0x20 || ch == (char)0x2028 || ch == (char)0x2029) sb.Append("\\u").Append(((int)ch).ToString("x4"));
                        else sb.Append(ch);
                        break;
                }
            }
            sb.Append('"');
        }

        // 寫進「結束那天」（沒有結束時間＝開始那天）的檔；跟上次寫的一模一樣就不寫
        public static bool Write(NoteEntry e)
        {
            if (e == null || string.IsNullOrEmpty(e.Id) || string.IsNullOrEmpty(e.Title)) return false;
            e.Title = OneLine(e.Title);
            DateTime d = (e.End != DateTime.MinValue ? e.End : e.T).Date;
            return Append(d, e.Id, Line(e));
        }

        // 小本子（同一個程式）要寫手動加的、做完的待辦也可以用這個：同一把鎖，不會跟收集器的寫入交錯
        public static bool Append(DateTime day, string id, string line)
        {
            lock (gate)
            {
                string f = FileFor(day), k = day.ToString("yyyyMMdd");
                Dictionary<string, string> m;
                if (!days.TryGetValue(k, out m))
                {
                    m = new Dictionary<string, string>();
                    try
                    {
                        if (File.Exists(f))
                            foreach (string l in File.ReadAllLines(f, Encoding.UTF8))
                            {
                                Match mm = IdRx.Match(l);
                                if (mm.Success) m[Regex.Unescape(mm.Groups[1].Value)] = l;
                            }
                    }
                    catch (Exception ex) { App.Log("notebook log read: " + ex.Message); }
                    if (days.Count > 8) days.Clear();
                    days[k] = m;
                }
                string was;
                if (m.TryGetValue(id, out was) && was == line) return false;
                try
                {
                    Directory.CreateDirectory(Dir());
                    using (FileStream fs = new FileStream(f, FileMode.Append, FileAccess.Write, FileShare.ReadWrite))
                    {
                        byte[] b = new UTF8Encoding(false).GetBytes(line + "\n");
                        fs.Write(b, 0, b.Length);
                    }
                    m[id] = line;
                    return true;
                }
                catch (Exception ex) { App.Log("notebook log write: " + ex.Message); return false; }
            }
        }

        public static string OneLine(string s) { return Regex.Replace(s ?? "", @"\s+", " ").Trim(); }
        public static string Cut(string s, int n) { s = OneLine(s); return s.Length > n ? s.Substring(0, n) + "…" : s; }
    }

    // ================= Windows DPAPI（目前使用者）：Jira token 加密存檔 =================
    // 跟 .NET 的 ProtectedData.Protect(…, DataProtectionScope.CurrentUser) 一樣（直接叫 crypt32，不用多參考 System.Security.dll）
    static class Secret
    {
        [StructLayout(LayoutKind.Sequential)]
        struct Blob { public int Size; public IntPtr Data; }
        [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CryptProtectData(ref Blob dataIn, string descr, ref Blob entropy, IntPtr reserved, IntPtr prompt, int flags, ref Blob dataOut);
        [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CryptUnprotectData(ref Blob dataIn, IntPtr descr, ref Blob entropy, IntPtr reserved, IntPtr prompt, int flags, ref Blob dataOut);
        [DllImport("kernel32.dll")]
        static extern IntPtr LocalFree(IntPtr p);

        public static readonly byte[] JiraEntropy = Encoding.UTF8.GetBytes("WoWoPals.jira.v1");
        public static byte[] Protect(byte[] plain, byte[] entropy) { return Run(plain, entropy, true); }
        public static byte[] Unprotect(byte[] blob, byte[] entropy) { return Run(blob, entropy, false); }

        static byte[] Run(byte[] input, byte[] entropy, bool protect)
        {
            if (input == null || input.Length == 0) return null;
            Blob i = new Blob(), e = new Blob(), o = new Blob();
            GCHandle hi = GCHandle.Alloc(input, GCHandleType.Pinned), he = GCHandle.Alloc(entropy, GCHandleType.Pinned);
            try
            {
                i.Size = input.Length; i.Data = hi.AddrOfPinnedObject();
                e.Size = entropy.Length; e.Data = he.AddrOfPinnedObject();
                const int UiForbidden = 1;
                bool ok = protect ? CryptProtectData(ref i, "WoWo Pals", ref e, IntPtr.Zero, IntPtr.Zero, UiForbidden, ref o)
                    : CryptUnprotectData(ref i, IntPtr.Zero, ref e, IntPtr.Zero, IntPtr.Zero, UiForbidden, ref o);
                if (!ok || o.Data == IntPtr.Zero) return null;
                byte[] r = new byte[o.Size];
                Marshal.Copy(o.Data, r, 0, o.Size);
                return r;
            }
            finally
            {
                hi.Free(); he.Free();
                if (o.Data != IntPtr.Zero) LocalFree(o.Data);
            }
        }
    }

    // ================= 叫 glab／gh（token 交給它們自己）=================
    static class Cli
    {
        // PATH 裡找，再看常見的安裝位置（開機自動啟動時 PATH 可能是舊的）
        public static string Find(string name)
        {
            string exe = name + ".exe";
            foreach (string d in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';'))
            {
                try { string p = Path.Combine(d.Trim().Trim('"'), exe); if (d.Trim() != "" && File.Exists(p)) return p; } catch { }
            }
            string la = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            string[] extra = name == "glab"
                ? new string[] { Path.Combine(la, "Programs", "glab", exe), Path.Combine(pf, "glab", exe), Path.Combine(la, "Microsoft", "WinGet", "Links", exe) }
                : new string[] { Path.Combine(pf, "GitHub CLI", exe), Path.Combine(la, "Programs", "GitHub CLI", exe), Path.Combine(la, "Microsoft", "WinGet", "Links", exe) };
            foreach (string p in extra) if (File.Exists(p)) return p;
            return null;
        }

        // 測試（只在離屏模式）：DESKPALS_FAKE_CLI＝一支 node 小程式，「node <它> glab|gh <參數…>」假裝是 glab／gh
        static string Fake() { return App.Offscreen ? Environment.GetEnvironmentVariable("DESKPALS_FAKE_CLI") : null; }

        public static bool Available(string tool) { return !string.IsNullOrEmpty(Fake()) || Find(tool) != null; }

        // 回傳結束碼（-1＝沒裝、跑不起來或超時）；stdout／stderr 只給呼叫的人解析，不寫進紀錄
        public static int Run(string tool, string[] args, int timeoutMs, out string stdout, out string stderr)
        {
            stdout = ""; stderr = "";
            string exe;
            List<string> a = new List<string>();
            string fake = Fake();
            if (!string.IsNullOrEmpty(fake)) { exe = Find("node") ?? "node"; a.Add(fake); a.Add(tool); }
            else exe = Find(tool);
            if (exe == null) return -1;
            a.AddRange(args);
            StringBuilder cmd = new StringBuilder();
            foreach (string x in a) { if (cmd.Length > 0) cmd.Append(' '); cmd.Append(Quote(x)); }
            ProcessStartInfo psi = new ProcessStartInfo(exe, cmd.ToString());
            psi.UseShellExecute = false; psi.CreateNoWindow = true;
            psi.RedirectStandardOutput = true; psi.RedirectStandardError = true; psi.RedirectStandardInput = true;
            psi.StandardOutputEncoding = Encoding.UTF8; psi.StandardErrorEncoding = Encoding.UTF8;
            psi.EnvironmentVariables["NO_COLOR"] = "1";
            psi.EnvironmentVariables["GH_PROMPT_DISABLED"] = "1";
            psi.EnvironmentVariables["GH_NO_UPDATE_NOTIFIER"] = "1";
            psi.EnvironmentVariables["GLAB_CHECK_UPDATE"] = "false";
            psi.EnvironmentVariables["GLAB_NO_PROMPT"] = "1";
            try
            {
                using (Process p = Process.Start(psi))
                {
                    try { p.StandardInput.Close(); } catch { }
                    System.Threading.Tasks.Task<string> o = p.StandardOutput.ReadToEndAsync(), e = p.StandardError.ReadToEndAsync();
                    if (!p.WaitForExit(timeoutMs)) { try { p.Kill(); } catch { } return -1; }
                    o.Wait(3000); e.Wait(3000);
                    stdout = o.IsCompleted ? o.Result : ""; stderr = e.IsCompleted ? e.Result : "";
                    return p.ExitCode;
                }
            }
            catch (Exception ex) { App.Log("cli " + tool + ": " + ex.Message); return -1; }
        }

        // Windows 命令列的引號規則（CommandLineToArgvW）
        static string Quote(string s)
        {
            if (s.Length > 0 && s.IndexOfAny(new char[] { ' ', '\t', '"' }) < 0) return s;
            StringBuilder b = new StringBuilder("\"");
            int bs = 0;
            foreach (char ch in s)
            {
                if (ch == '\\') { bs++; continue; }
                if (ch == '"') { b.Append('\\', bs * 2 + 1); b.Append('"'); bs = 0; continue; }
                b.Append('\\', bs); bs = 0; b.Append(ch);
            }
            b.Append('\\', bs * 2);
            return b.Append('"').ToString();
        }
    }

    partial class World
    {
        // ================= 設定（work-config.txt：key=value）=================
        public static readonly string[][] WorkDefaults = {
            new string[] { "ai", "1" },            // Claude Code／Codex 做完的對話寫進小本子（只讀寫本機檔案）
            new string[] { "claude_dir", "" },     // 進階：別的 Claude 資料夾（WSL：\\wsl$\Ubuntu\home\me\.claude）
            new string[] { "codex_dir", "" },      // 進階：別的 Codex 資料夾
            new string[] { "jira", "0" }, new string[] { "jira_site", "" }, new string[] { "jira_email", "" },
            new string[] { "gitlab", "0" }, new string[] { "github", "0" }, new string[] { "ci", "0" },
            new string[] { "meet", "0" }, new string[] { "meet_url", "" }, new string[] { "meet_before", "5" }, new string[] { "meet_quiet", "1" },
            new string[] { "rain", "0" }, new string[] { "rain_place", "" },
            new string[] { "vpn", "0" }, new string[] { "vpn_host", "" },
            new string[] { "worklog", "0" }, new string[] { "worklog_dir", "" } };
        public static readonly string[] WorkSources = { "jira", "gitlab", "github", "ci", "meet", "rain", "vpn", "worklog" };

        readonly Dictionary<string, string> wcfg = new Dictionary<string, string>();
        bool workLoaded, workStarted;
        bool? jiraTokenCache;

        void WorkLoad()
        {
            lock (wcfg)
            {
                if (workLoaded) return;
                workLoaded = true;
                foreach (string[] d in WorkDefaults) wcfg[d[0]] = d[1];
                foreach (string line in ReadText("work-config.txt").Split('\n'))
                {
                    int i = line.IndexOf('=');
                    if (i <= 0) continue;
                    string k = line.Substring(0, i).Trim(), v = line.Substring(i + 1).Trim();
                    if (wcfg.ContainsKey(k)) wcfg[k] = v;
                }
                foreach (string line in ReadText("work-seen.txt").Split('\n'))
                {
                    int i = line.IndexOf('\t');
                    if (i > 0) wseen[line.Substring(0, i)] = line.Substring(i + 1).TrimEnd('\r');
                }
            }
        }

        void WorkSave()
        {
            StringBuilder sb = new StringBuilder();
            lock (wcfg) foreach (string[] d in WorkDefaults) sb.Append(d[0] + "=" + wcfg[d[0]] + "\n");
            WriteText("work-config.txt", sb.ToString());
        }

        public string WC(string k) { WorkLoad(); lock (wcfg) { string v; return wcfg.TryGetValue(k, out v) ? v : ""; } }
        public bool WOn(string k) { return WC(k) == "1"; }

        // 設定視窗、pipe 共用：改一項（回傳 false＝沒有這一項或值不對）
        public bool WorkSet(string k, string v)
        {
            WorkLoad();
            v = NoteLog.OneLine(v ?? "");
            if (v == "-") v = "";
            lock (wcfg) if (!wcfg.ContainsKey(k)) return false;
            switch (k)
            {
                case "ai": case "jira": case "gitlab": case "github": case "ci": case "meet": case "meet_quiet": case "rain": case "vpn": case "worklog":
                    v = v == "1" || v == "on" || v == "true" ? "1" : "0"; break;
                case "meet_before": { int n; if (!int.TryParse(v, out n) || n < 1 || n > 120) return false; v = n.ToString(); } break;
                case "meet_url": if (v != "" && WorkUrl(v) == null) return false; break;
                case "vpn_host": if (v != "" && !Regex.IsMatch(v, @"^[\w.-]+(:\d{1,5})?$")) return false; break;
            }
            lock (wcfg) wcfg[k] = v;
            WorkSave();
            WorkApply();
            App.Log("work set " + k + (k.EndsWith("_url") || k == "jira_email" ? " (" + (v == "" ? "empty" : "set") + ")" : "=" + v));
            return true;
        }

        // ---- Jira token：DPAPI ----
        public bool HasJiraToken()
        {
            if (jiraTokenCache == null) jiraTokenCache = File.Exists(FilePath("jira-token.dat"));
            return jiraTokenCache.Value;
        }
        public bool SetJiraToken(string token)
        {
            token = (token ?? "").Trim();
            try
            {
                if (token == "" || token == "-") { File.Delete(FilePath("jira-token.dat")); jiraTokenCache = false; WorkApply(); return true; }
                byte[] blob = Secret.Protect(Encoding.UTF8.GetBytes(token), Secret.JiraEntropy);
                if (blob == null) { App.Log("jira token: DPAPI failed"); return false; }
                Directory.CreateDirectory(DataDir);
                File.WriteAllBytes(FilePath("jira-token.dat"), blob);
                jiraTokenCache = true;
                WorkApply();
                return true;
            }
            catch (Exception ex) { App.Log("jira token: " + ex.Message); return false; }
        }
        string JiraToken()
        {
            try
            {
                if (!File.Exists(FilePath("jira-token.dat"))) return null;
                byte[] plain = Secret.Unprotect(File.ReadAllBytes(FilePath("jira-token.dat")), Secret.JiraEntropy);
                return plain == null ? null : Encoding.UTF8.GetString(plain);
            }
            catch { return null; }
        }

        // ---- 誰管哪個來源 ----
        public bool WorkOwns(string src)
        {
            switch (src)
            {
                case "jira": return WOn("jira") && WC("jira_site") != "" && WC("jira_email") != "" && HasJiraToken();
                case "gitlab": case "github": case "ci": return WOn(src);
                case "meet": return WOn("meet") && WC("meet_url") != "";
                case "rain": return WOn("rain") && WC("rain_place") != "";
                case "vpn": return WOn("vpn") && WC("vpn_host") != "";
                case "worklog": return WOn("worklog") && WC("worklog_dir") != "";
            }
            return false;
        }
        string WorkOwnLine()
        {
            List<string> l = new List<string>();
            foreach (string s in WorkSources) if (WorkOwns(s)) l.Add(s);
            return "work-own " + (l.Count == 0 ? "-" : string.Join(",", l.ToArray())) + "\n";
        }
        void WorkHello(Client c) { Send(c, WorkOwnLine()); }

        // 舊版擴充套件（或 ci-watch.js）送來的通知：桌面版已經在管的就丟掉（不講兩次）
        int workDropped;
        public bool WorkDropsNotify(string kind)
        {
            string src = null;
            switch (kind)
            {
                case "jira": src = "jira"; break;
                case "gitlab": src = "gitlab"; break;
                case "ci-run": case "ci-ok": case "ci-fail": src = "ci"; break;
                case "meeting": case "meeting-now": src = "meet"; break;
                case "rain": src = "rain"; break;
                case "worklog": src = "worklog"; break;
            }
            if (src == null || !WorkOwns(src)) return false;
            workDropped++;
            App.Log("work: dropped a " + kind + " notice from VS Code (the desktop handles " + src + ")");
            return true;
        }

        string lastOwn = "", appliedVpn = "";
        void WorkApply()
        {
            string own = WorkOwnLine();
            if (own != lastOwn) { lastOwn = own; lock (clients) foreach (Client c in clients) Send(c, own); }
            // 公司網路：桌面版有設就用桌面版的（VS Code 的 deskPals.companyHost 不再蓋過來）
            string vh = WorkOwns("vpn") ? WC("vpn_host") : "";
            if (vh != appliedVpn) { if (vh != "" || companyHost == appliedVpn) companyHost = vh; appliedVpn = vh; }
            workPollNow = true;
            if (workWake != null) workWake.Set();
        }

        // ---- 公司網路：host 或 host:port ----
        public static bool VpnReachable(string host)
        {
            int c = host.LastIndexOf(':'), port;
            if (c > 0 && int.TryParse(host.Substring(c + 1), out port)) return TcpOk(host.Substring(0, c), port);
            return TcpOk(host, 443) || TcpOk(host, 80);
        }

        // ---- 網址：只收 https（webcal 當 https）；測試時（離屏）才收本機的 http ----
        public static string WorkUrl(string s)
        {
            s = (s ?? "").Trim();
            if (s.StartsWith("webcal://", StringComparison.OrdinalIgnoreCase)) s = "https://" + s.Substring(9);
            else if (s.StartsWith("webcals://", StringComparison.OrdinalIgnoreCase)) s = "https://" + s.Substring(10);
            Uri u;
            if (!Uri.TryCreate(s, UriKind.Absolute, out u)) return null;
            if (u.Scheme == Uri.UriSchemeHttps) return s;
            if (App.Offscreen && u.Scheme == Uri.UriSchemeHttp && (u.Host == "127.0.0.1" || u.Host == "localhost")) return s;
            return null;
        }

        // ---- 假時鐘（測試）----
        TimeSpan workShift = TimeSpan.Zero;
        DateTime WNow() { return DateTime.Now + workShift; }
        static readonly DateTime Epoch0 = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        long WNowMs() { return (long)(WNow().ToUniversalTime() - Epoch0).TotalMilliseconds; }
        static DateTime LocalOfMs(long ms) { return Epoch0.AddMilliseconds(ms).ToLocalTime(); }

        // ---- 看過了沒（work-seen.txt：key\tvalue；重開也不會再講一次）----
        readonly Dictionary<string, string> wseen = new Dictionary<string, string>();
        bool seenDirty;
        string Seen(string k) { lock (wcfg) { string v; return wseen.TryGetValue(k, out v) ? v : null; } }
        void SetSeen(string k, string v) { lock (wcfg) { wseen[k] = v; seenDirty = true; } }
        void SaveSeen()
        {
            StringBuilder sb = new StringBuilder();
            lock (wcfg)
            {
                if (!seenDirty) return;
                seenDirty = false;
                // 一天一次的旗子只留最近幾天
                string keep = WNow().AddDays(-3).ToString("yyyyMMdd");
                List<string> drop = new List<string>();
                foreach (KeyValuePair<string, string> kv in wseen)
                {
                    Match m = Regex.Match(kv.Key, @":(\d{8})(:|$)");
                    if (m.Success && string.CompareOrdinal(m.Groups[1].Value, keep) < 0) drop.Add(kv.Key);
                }
                foreach (string k in drop) wseen.Remove(k);
                foreach (KeyValuePair<string, string> kv in wseen) sb.Append(kv.Key + "\t" + kv.Value + "\n");
            }
            WriteText("work-seen.txt", sb.ToString());
        }
        static List<string> SeenList(string v) { List<string> l = new List<string>(); if (v != null) foreach (string x in v.Split(',')) if (x != "") l.Add(x); return l; }
        static string SeenJoin(List<string> l) { if (l.Count > 500) l = l.GetRange(l.Count - 500, 500); return string.Join(",", l.ToArray()); }

        // ---- 提醒：照舊走 OnNotify（公仔泡泡）；離屏測試記下來 ----
        readonly List<string> workNotices = new List<string>();
        void WNotify(string kind, string url, string text)
        {
            text = NoteLog.OneLine(text);
            lock (workNotices) { workNotices.Add(kind + " " + (url ?? "-") + " " + text); if (workNotices.Count > 60) workNotices.RemoveAt(0); }
            App.Log("work notify " + kind);
            string k = kind, u = string.IsNullOrEmpty(url) ? "-" : url, t = text;
            Post(delegate { OnNotify(k, u, t); });
        }

        // ================= 開始（TickInner 每一輪叫；第一次才開背景執行緒）=================
        AutoResetEvent workWake;
        volatile bool workPollNow;
        void WorkTick()
        {
            if (workStarted) return;
            workStarted = true;
            WorkLoad();
            string vh = WorkOwns("vpn") ? WC("vpn_host") : "";
            if (vh != "") { companyHost = vh; appliedVpn = vh; }
            lastOwn = WorkOwnLine();
            workWake = new AutoResetEvent(false);
            Thread th = new Thread(WorkLoop); th.IsBackground = true; th.Start();
        }

        void WorkLoop()
        {
            Thread.Sleep(App.Offscreen ? 300 : 6000);
            DateTime nAi = DateTime.MinValue, nAuth = DateTime.MinValue, nJira = DateTime.Now.AddSeconds(App.Offscreen ? 0 : 20), nGl = DateTime.Now.AddSeconds(App.Offscreen ? 0 : 25),
                nGh = DateTime.Now.AddSeconds(App.Offscreen ? 0 : 30), nMeet = DateTime.MinValue, nRain = DateTime.Now.AddSeconds(App.Offscreen ? 0 : 30), nWl = DateTime.MinValue, nSave = DateTime.MinValue;
            JavaScriptSerializer js = new JavaScriptSerializer();
            js.MaxJsonLength = int.MaxValue;
            while (!closing)
            {
                bool force = workPollNow;
                if (force) { workPollNow = false; nAi = nAuth = nJira = nGl = nGh = nMeet = nRain = nWl = DateTime.MinValue; }
                DateTime now = DateTime.Now;
                if (WOn("ai") && now >= nAi) { nAi = now.AddSeconds(30); Try("ai", delegate { AiScan(js); }); }
                if ((WOn("gitlab") || WOn("github") || WOn("ci")) && now >= nAuth) { nAuth = now.AddMinutes(10); Try("auth", DetectAuth); }
                if (WorkOwns("jira") && now >= nJira) { nJira = now.AddMinutes(3); Try("jira", delegate { JiraCheck(js); }); }
                if ((WOn("gitlab") || WOn("ci")) && now >= nGl) { nGl = now.AddSeconds(WOn("ci") ? 60 : 180); Try("gitlab", delegate { GitLabCheck(js); }); }
                if ((WOn("github") || WOn("ci")) && now >= nGh) { nGh = now.AddSeconds(WOn("ci") ? 60 : 180); Try("github", delegate { GitHubCheck(js); }); }
                if (WOn("ci")) Try("ci", delegate { CiStep(js, force); });
                if (WorkOwns("meet"))
                {
                    if (now >= nMeet) { nMeet = now.AddMinutes(10); Try("meet", MeetFetch); }
                    Try("meet", MeetTick);
                }
                if (WorkOwns("rain") && now >= nRain) { nRain = now.AddMinutes(10); Try("rain", delegate { RainCheck(js); }); }
                if (WorkOwns("worklog") && now >= nWl) { nWl = now.AddSeconds(60); Try("worklog", WorklogCheck); }
                if (now >= nSave || force) { nSave = now.AddSeconds(20); SaveSeen(); }
                if (force) workPolled++;
                workWake.WaitOne(1000);
            }
        }
        int workPolled;
        void Try(string what, Action a) { try { a(); } catch (Exception ex) { App.Log("work " + what + ": " + ex.Message); } }

        // ================= JSON 小工具 =================
        static object J(object o, params string[] path)
        {
            foreach (string k in path)
            {
                Dictionary<string, object> d = o as Dictionary<string, object>;
                if (d == null || !d.TryGetValue(k, out o)) return null;
            }
            return o;
        }
        static string JS(object o, params string[] path) { object v = J(o, path); return v == null ? null : Convert.ToString(v, CultureInfo.InvariantCulture); }
        static object[] JA(object o, params string[] path) { object v = J(o, path); object[] a = v as object[]; if (a != null) return a; System.Collections.ArrayList al = v as System.Collections.ArrayList; return al != null ? al.ToArray() : new object[0]; }
        static int JI(object o, params string[] path) { int n; return int.TryParse(JS(o, path) ?? "", out n) ? n : 0; }
        static DateTime JT(string s)
        {
            DateTimeOffset t;
            if (s != null && DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out t)) return t.LocalDateTime;
            // Jira：2026-11-19T10:02:00.000+0800（時區沒有冒號）
            if (s != null && Regex.IsMatch(s, @"[+-]\d{4}$") && DateTimeOffset.TryParse(s.Substring(0, s.Length - 2) + ":" + s.Substring(s.Length - 2), CultureInfo.InvariantCulture, DateTimeStyles.None, out t)) return t.LocalDateTime;
            return DateTime.MinValue;
        }
        object ParseJson(JavaScriptSerializer js, string s) { try { return string.IsNullOrEmpty(s) ? null : js.DeserializeObject(s); } catch { return null; } }

        // ================= HTTP（Jira、天氣、行事曆）=================
        // 回傳內容；status＝HTTP 狀態（0＝連不上）
        static string HttpGet(string url, string auth, int timeoutMs, out int status)
        {
            status = 0;
            try
            {
                System.Net.ServicePointManager.SecurityProtocol |= (System.Net.SecurityProtocolType)3072;   // TLS 1.2
                System.Net.HttpWebRequest req = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(url);
                req.Timeout = timeoutMs; req.ReadWriteTimeout = timeoutMs; req.UserAgent = "WoWoPals"; req.Accept = "application/json";
                req.AutomaticDecompression = System.Net.DecompressionMethods.GZip | System.Net.DecompressionMethods.Deflate;
                if (auth != null) req.Headers["Authorization"] = auth;
                using (System.Net.HttpWebResponse resp = (System.Net.HttpWebResponse)req.GetResponse())
                using (StreamReader r = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                {
                    status = (int)resp.StatusCode;
                    char[] buf = new char[8192];
                    StringBuilder sb = new StringBuilder();
                    int n;
                    while ((n = r.Read(buf, 0, buf.Length)) > 0) { sb.Append(buf, 0, n); if (sb.Length > 8000000) break; }
                    return sb.ToString();
                }
            }
            catch (System.Net.WebException ex)
            {
                System.Net.HttpWebResponse r = ex.Response as System.Net.HttpWebResponse;
                status = r != null ? (int)r.StatusCode : 0;
                return null;
            }
            catch { return null; }
        }

        // ================= glab／gh 有沒有登入（只看「Logged in to <host> as <user>」那幾行）=================
        readonly List<string> glabHosts = new List<string>();
        string ghUser = "", glabState = "", ghState = "";
        static readonly Regex GlabLogin = new Regex(@"Logged in to (\S+) as (\S+)");
        static readonly Regex GhLogin = new Regex(@"Logged in to (\S+) (?:account|as) (\S+)");
        void DetectAuth()
        {
            string o, e;
            List<string> hosts = new List<string>();
            int rc = Cli.Run("glab", new string[] { "auth", "status" }, 30000, out o, out e);
            foreach (Match m in GlabLogin.Matches(o + "\n" + e)) if (!hosts.Contains(m.Groups[1].Value)) hosts.Add(m.Groups[1].Value);
            lock (glabHosts) { glabHosts.Clear(); glabHosts.AddRange(hosts); }
            glabState = rc == -1 && !Cli.Available("glab") ? "missing" : (hosts.Count > 0 ? "ok" : "nologin");
            rc = Cli.Run("gh", new string[] { "auth", "status" }, 30000, out o, out e);
            Match g = GhLogin.Match(o + "\n" + e);
            ghUser = g.Success ? g.Groups[2].Value.Trim('(', ')') : "";
            ghState = rc == -1 && !Cli.Available("gh") ? "missing" : (ghUser != "" ? "ok" : "nologin");
            App.Log("work auth: glab=" + glabState + " (" + hosts.Count + " host) gh=" + ghState);
        }
        List<string> GlabHosts() { if (glabState == "") DetectAuth(); lock (glabHosts) return new List<string>(glabHosts); }

        object Glab(JavaScriptSerializer js, string host, string path)
        {
            string o, e;
            int rc = Cli.Run("glab", new string[] { "api", "--hostname", host, path }, 30000, out o, out e);
            return rc == 0 ? ParseJson(js, o) : null;
        }
        object Gh(JavaScriptSerializer js, string path)
        {
            string o, e;
            int rc = Cli.Run("gh", new string[] { "api", path }, 30000, out o, out e);
            return rc == 0 ? ParseJson(js, o) : null;
        }

        // ================= Jira =================
        string jiraStatus = "", jiraMe;
        string JiraBase()
        {
            string s = WC("jira_site").Trim().TrimEnd('/');
            if (s == "") return null;
            if (s.StartsWith("http://", StringComparison.OrdinalIgnoreCase)) return WorkUrl(s) != null ? s : null;   // 只有測試（離屏、本機）
            if (s.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) s = s.Substring(8);
            int sl = s.IndexOf('/');
            if (sl >= 0) s = s.Substring(0, sl);
            return "https://" + s;
        }
        object JiraGet(JavaScriptSerializer js, string path)
        {
            string b = JiraBase(), tok = JiraToken();
            if (b == null || tok == null) return null;
            string auth = "Basic " + Convert.ToBase64String(Encoding.UTF8.GetBytes(WC("jira_email") + ":" + tok));
            int st;
            string body = HttpGet(b + path, auth, 20000, out st);
            jiraStatus = st == 200 ? "ok" : (st == 401 || st == 403 ? "auth" : (st == 0 ? "down" : "http " + st));
            if (body == null) throw new Exception("jira " + jiraStatus);
            return ParseJson(js, body);
        }
        object[] JiraSearch(JavaScriptSerializer js, string jql, string fields, int max)
        {
            return JA(JiraGet(js, "/rest/api/3/search/jql?jql=" + Uri.EscapeDataString(jql) + "&fields=" + fields + "&maxResults=" + max), "issues");
        }
        static string AdfText(object n)
        {
            if (n == null) return "";
            string type = JS(n, "type");
            if (type == "text") return JS(n, "text") ?? "";
            if (type == "mention") return JS(n, "attrs", "text") ?? "@";
            StringBuilder sb = new StringBuilder();
            foreach (object c in JA(n, "content")) { sb.Append(AdfText(c)); if (type == "paragraph") sb.Append(' '); }
            return sb.ToString();
        }

        void JiraCheck(JavaScriptSerializer js)
        {
            string b = JiraBase();
            string host = new Uri(b).Authority;
            // 1) 新單指派給你（第一次只記下來）＋給小本子待辦的未結單
            string jql = "assignee = currentUser() AND statusCategory != Done ORDER BY created DESC";
            object[] open = JiraSearch(js, jql, "summary,status", 100);
            StringBuilder oj = new StringBuilder("[");
            List<string> keys = new List<string>();
            foreach (object i in open)
            {
                string k = JS(i, "key");
                if (k == null) continue;
                keys.Add(k);
                if (oj.Length > 1) oj.Append(',');
                oj.Append("{\"key\":"); NoteLog.Q(oj, k);
                oj.Append(",\"title\":"); NoteLog.Q(oj, NoteLog.OneLine(JS(i, "fields", "summary")));
                oj.Append(",\"status\":"); NoteLog.Q(oj, JS(i, "fields", "status", "name") ?? "");
                oj.Append(",\"url\":"); NoteLog.Q(oj, b + "/browse/" + k);
                oj.Append('}');
            }
            oj.Append("]\n");
            try { Directory.CreateDirectory(NoteLog.Dir()); File.WriteAllText(Path.Combine(NoteLog.Dir(), "jira-open.json"), oj.ToString(), new UTF8Encoding(false)); } catch { }
            string sk = "jira-seen:" + host;
            string seen0 = Seen(sk);
            List<string> seen = SeenList(seen0);
            if (seen0 == null) SetSeen(sk, SeenJoin(keys));
            else
            {
                List<object> fresh = new List<object>();
                foreach (object i in open) if (!seen.Contains(JS(i, "key"))) fresh.Add(i);
                for (int n = 0; n < fresh.Count && n < 3; n++)
                    WNotify("jira", b + "/browse/" + JS(fresh[n], "key"), JS(fresh[n], "key") + " 指派給你了：" + NoteLog.Cut(JS(fresh[n], "fields", "summary"), 40));
                if (fresh.Count > 3) WNotify("jira", b + "/issues/?jql=" + Uri.EscapeDataString(jql), "還有 " + (fresh.Count - 3) + " 張新單指派給你");
                foreach (string k in keys) if (!seen.Contains(k)) seen.Add(k);
                SetSeen(sk, SeenJoin(seen));
            }

            // 2) 到期：平日 09:30、16:30 各看一次
            DateTime d = WNow();
            int hm = d.Hour * 60 + d.Minute;
            string slot = hm >= 16 * 60 + 30 ? "pm" : (hm >= 9 * 60 + 30 ? "am" : null);
            string dk = "jira-due:" + host + ":" + d.ToString("yyyyMMdd") + ":" + slot;
            if (slot != null && d.DayOfWeek != DayOfWeek.Saturday && d.DayOfWeek != DayOfWeek.Sunday && Seen(dk) == null)
            {
                SetSeen(dk, "1");
                string djql = "assignee = currentUser() AND statusCategory != Done AND duedate >= -14d AND duedate <= endOfDay(1) ORDER BY duedate ASC";
                object[] due = JiraSearch(js, djql, "summary,duedate", 50);
                List<string> over = new List<string>(), today = new List<string>(), tmr = new List<string>();
                foreach (object i in due)
                {
                    DateTime dd;
                    if (!DateTime.TryParseExact(JS(i, "fields", "duedate") ?? "", "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out dd)) continue;
                    int diff = (int)Math.Round((dd - d.Date).TotalDays);
                    (diff < 0 ? over : (diff == 0 ? today : tmr)).Add(JS(i, "key"));
                }
                List<string> parts = new List<string>();
                if (today.Count > 0) parts.Add("今天到期：" + string.Join("、", today.GetRange(0, Math.Min(3, today.Count)).ToArray()) + (today.Count > 3 ? " 等 " + today.Count + " 張" : ""));
                if (tmr.Count > 0) parts.Add("明天到期：" + string.Join("、", tmr.GetRange(0, Math.Min(3, tmr.Count)).ToArray()) + (tmr.Count > 3 ? " 等 " + tmr.Count + " 張" : ""));
                if (over.Count > 0) parts.Add("已經逾期 " + over.Count + " 張");
                if (parts.Count > 0)
                    WNotify("jira", due.Length == 1 ? b + "/browse/" + JS(due[0], "key") : b + "/issues/?jql=" + Uri.EscapeDataString(djql), string.Join("；", parts.ToArray()));
            }

            // 3) 有人在留言 @你
            if (jiraMe == null) jiraMe = JS(JiraGet(js, "/rest/api/3/myself"), "accountId");
            if (jiraMe != null)
            {
                string mk = "jira-mention:" + host;
                long since, nowMs = WNowMs();
                if (!long.TryParse(Seen(mk) ?? "", out since)) SetSeen(mk, nowMs.ToString());
                else
                {
                    long newest = since;
                    foreach (object i in JiraSearch(js, "updated >= -20m AND (watcher = currentUser() OR assignee = currentUser() OR reporter = currentUser()) ORDER BY updated DESC", "summary", 20))
                    {
                        string k = JS(i, "key");
                        foreach (object x in JA(JiraGet(js, "/rest/api/3/issue/" + k + "/comment?orderBy=-created&maxResults=5"), "comments"))
                        {
                            DateTime ct = JT(JS(x, "created"));
                            long t = ct == DateTime.MinValue ? 0 : (long)(ct.ToUniversalTime() - Epoch0).TotalMilliseconds;
                            if (t <= since || JS(x, "author", "accountId") == jiraMe) continue;
                            if (new JavaScriptSerializer().Serialize(J(x, "body") ?? "").IndexOf("\"id\":\"" + jiraMe + "\"", StringComparison.Ordinal) < 0) continue;
                            newest = Math.Max(newest, t);
                            WNotify("jira", b + "/browse/" + k + "?focusedCommentId=" + JS(x, "id"), (JS(x, "author", "displayName") ?? "有人") + " 在 " + k + " @你：" + NoteLog.Cut(AdfText(J(x, "body")), 40));
                        }
                    }
                    SetSeen(mk, Math.Max(newest, nowMs - 60000).ToString());
                }
            }

            // 4) 小本子：今天你動過狀態的單、今天解決的單
            foreach (object i in JiraSearch(js, "(status changed BY currentUser() AFTER startOfDay()) OR (assignee = currentUser() AND resolved >= startOfDay()) ORDER BY updated DESC", "summary,status,project,updated", 50))
            {
                string k = JS(i, "key");
                if (k == null) continue;
                bool done = JS(i, "fields", "status", "statusCategory", "key") == "done";
                NoteEntry e = new NoteEntry();
                e.Id = "jira:" + k + (done ? ":resolved" : ":status");
                e.T = JT(JS(i, "fields", "updated")); if (e.T == DateTime.MinValue) e.T = WNow();
                e.Src = "jira"; e.Project = JS(i, "fields", "project", "name"); e.Title = JS(i, "fields", "summary");
                e.Status = done ? "工單解決了" : JS(i, "fields", "status", "name");
                e.Ok = done ? 1 : -1; e.Ref = k; e.Url = b + "/browse/" + k; e.Key = k;
                NoteLog.Write(e);
            }
        }

        // ================= GitLab（glab）：待辦提醒＋今天做的事＋推了 tag（盯 CI 用）=================
        static readonly Dictionary<string, string> TodoText = new Dictionary<string, string> {
            { "review_requested", "請你 review" }, { "assigned", "指派給你" }, { "mentioned", "@你" }, { "directly_addressed", "@你" },
            { "build_failed", "pipeline 失敗" }, { "approval_required", "需要你核准" }, { "unmergeable", "沒辦法合併了" }, { "marked", "加了待辦" } };
        readonly Dictionary<string, object> glProjects = new Dictionary<string, object>();   // host#id → projects/:id

        void GitLabCheck(JavaScriptSerializer js)
        {
            foreach (string host in GlabHosts())
            {
                if (WOn("gitlab"))
                {
                    object list = Glab(js, host, "todos?state=pending&per_page=20");
                    if (list != null)
                    {
                        object[] todos = JA(new Dictionary<string, object> { { "a", list } }, "a");
                        string sk = "gl-todo:" + host;
                        string seen0 = Seen(sk);
                        List<string> seen = SeenList(seen0), ids = new List<string>();
                        foreach (object t in todos) ids.Add(JS(t, "id"));
                        if (seen0 != null)
                        {
                            List<object> fresh = new List<object>();
                            foreach (object t in todos) if (!seen.Contains(JS(t, "id"))) fresh.Add(t);
                            for (int n = 0; n < fresh.Count && n < 3; n++)
                            {
                                object t = fresh[n];
                                string act = JS(t, "action_name") ?? "", what;
                                if (!TodoText.TryGetValue(act, out what)) what = act;
                                string tt = JS(t, "target_type"), rf = tt == "MergeRequest" ? "MR" : (tt == "Issue" ? "Issue" : "");
                                WNotify(act == "build_failed" ? "ci-fail" : "gitlab", JS(t, "target_url"), (JS(t, "author", "name") ?? "有人") + " " + what + "：" + rf + " " + NoteLog.Cut(JS(t, "target", "title"), 36));
                            }
                            if (fresh.Count > 3) WNotify("gitlab", "https://" + host + "/dashboard/todos", "GitLab 還有 " + (fresh.Count - 3) + " 件新待辦");
                        }
                        foreach (string id in ids) if (!seen.Contains(id)) seen.Add(id);
                        SetSeen(sk, SeenJoin(seen));
                    }
                }
                // 你自己的動態（推 commit、開／合併 MR、推 tag）
                object ev = Glab(js, host, "events?after=" + WNow().AddDays(-2).ToString("yyyy-MM-dd") + "&per_page=100&sort=desc");
                if (ev == null) continue;
                DateTime today = WNow().Date;
                Dictionary<string, NoteEntry> pushes = new Dictionary<string, NoteEntry>();
                foreach (object x in JA(new Dictionary<string, object> { { "a", ev } }, "a"))
                {
                    DateTime at = JT(JS(x, "created_at"));
                    if (at == DateTime.MinValue) continue;
                    string act = JS(x, "action_name") ?? "", pid = JS(x, "project_id");
                    object proj = GlProject(js, host, pid);
                    string path = JS(proj, "path_with_namespace"), web = JS(proj, "web_url"), name = JS(proj, "name") ?? JS(proj, "path");
                    if (path == null) continue;
                    object pd = J(x, "push_data");
                    // 推了 tag → 盯 CI
                    if (pd != null && JS(pd, "ref_type") == "tag" && act == "pushed new")
                    {
                        if (WOn("ci")) CiCandidate("gitlab", host, pid, path, name, JS(pd, "ref"), at);
                        continue;
                    }
                    if (WOn("gitlab") == false || at.Date != today) continue;
                    if (pd != null && JS(pd, "ref_type") == "branch" && (act == "pushed to" || act == "pushed new"))
                    {
                        string br = JS(pd, "ref");
                        string id = "gitlab:" + path + ":push:" + br;
                        NoteEntry e;
                        if (!pushes.TryGetValue(id, out e))
                        {
                            e = new NoteEntry(); e.Id = id; e.Src = "gitlab"; e.Project = name; e.Key = br; e.End = at; e.T = at; e.Ref = br;
                            e.Title = JS(pd, "commit_title") ?? ("推到 " + br); e.Url = web + "/-/commits/" + br; e.Ok = -1; e.Status = "0";
                            pushes[id] = e;
                        }
                        if (at < e.T) e.T = at;
                        if (at > e.End) { e.End = at; e.Title = JS(pd, "commit_title") ?? e.Title; }
                        e.Status = (int.Parse(e.Status) + Math.Max(1, JI(pd, "commit_count"))).ToString();
                        continue;
                    }
                    if (JS(x, "target_type") == "MergeRequest" && (act == "opened" || act == "accepted" || act == "approved"))
                    {
                        string iid = JS(x, "target_iid");
                        NoteEntry e = new NoteEntry();
                        string what = act == "opened" ? "opened" : (act == "accepted" ? "merged" : "approved");
                        e.Id = "gitlab:" + path + "!" + iid + ":" + what; e.T = at; e.Src = "gitlab"; e.Project = name;
                        e.Title = JS(x, "target_title"); e.Status = act == "opened" ? "開了 MR" : (act == "accepted" ? "合併了" : "核准了");
                        e.Ok = act == "accepted" ? 1 : -1; e.Ref = "MR !" + iid; e.Url = web + "/-/merge_requests/" + iid; e.Key = path;
                        NoteLog.Write(e);
                    }
                }
                foreach (NoteEntry e in pushes.Values)
                {
                    int n = int.Parse(e.Status);
                    e.Status = "推了 " + n + " 個 commit";
                    if (e.End == e.T) e.End = DateTime.MinValue;
                    NoteLog.Write(e);
                }
            }
        }
        object GlProject(JavaScriptSerializer js, string host, string id)
        {
            if (id == null) return null;
            string k = host + "#" + id;
            lock (glProjects) { object o; if (glProjects.TryGetValue(k, out o)) return o; }
            object p = Glab(js, host, "projects/" + id);
            if (p != null) lock (glProjects) glProjects[k] = p;
            return p;
        }

        // ================= GitHub（gh）：通知提醒＋今天做的事＋推了 tag =================
        static readonly Dictionary<string, string> GhReason = new Dictionary<string, string> {
            { "review_requested", "請你 review" }, { "mention", "@你" }, { "team_mention", "@你的團隊" }, { "assign", "指派給你" },
            { "ci_activity", "CI 沒過" }, { "author", "有新回覆" }, { "comment", "有新留言" }, { "approval_requested", "需要你核准" } };

        static string GhWeb(string api)
        {
            // https://api.github.com/repos/o/r/pulls/17 → https://github.com/o/r/pull/17
            if (string.IsNullOrEmpty(api)) return null;
            Match m = Regex.Match(api, @"^https://api\.github\.com/repos/([^/]+/[^/]+)/(pulls|issues|commits)/(\w+)");
            if (!m.Success) return null;
            return "https://github.com/" + m.Groups[1].Value + "/" + (m.Groups[2].Value == "pulls" ? "pull" : m.Groups[2].Value.TrimEnd('s') == "commit" ? "commit" : "issues") + "/" + m.Groups[3].Value;
        }

        void GitHubCheck(JavaScriptSerializer js)
        {
            if (ghState == "") DetectAuth();
            if (ghUser == "") return;
            if (WOn("github"))
            {
                object list = Gh(js, "notifications?per_page=30");
                if (list != null)
                {
                    object[] ns = JA(new Dictionary<string, object> { { "a", list } }, "a");
                    string sk = "gh-note";
                    string seen0 = Seen(sk);
                    List<string> seen = SeenList(seen0);
                    List<object> fresh = new List<object>();
                    foreach (object n in ns)
                    {
                        string key = JS(n, "id") + "@" + JS(n, "updated_at");
                        if (seen0 != null && !seen.Contains(key) && GhReason.ContainsKey(JS(n, "reason") ?? "")) fresh.Add(n);
                        if (!seen.Contains(key)) seen.Add(key);
                    }
                    SetSeen(sk, SeenJoin(seen));
                    for (int i = 0; i < fresh.Count && i < 3; i++)
                    {
                        object n = fresh[i];
                        string reason = JS(n, "reason"), type = JS(n, "subject", "type");
                        string rf = type == "PullRequest" ? "PR" : (type == "Issue" ? "Issue" : "");
                        string url = GhWeb(JS(n, "subject", "url")) ?? ("https://github.com/" + JS(n, "repository", "full_name"));
                        WNotify(reason == "ci_activity" ? "ci-fail" : "github", url, JS(n, "repository", "name") + " " + GhReason[reason] + "：" + rf + " " + NoteLog.Cut(JS(n, "subject", "title"), 36));
                    }
                    if (fresh.Count > 3) WNotify("github", "https://github.com/notifications", "GitHub 還有 " + (fresh.Count - 3) + " 則新通知");
                }
            }
            object ev = Gh(js, "users/" + ghUser + "/events?per_page=100");
            if (ev == null) return;
            DateTime today = WNow().Date;
            Dictionary<string, NoteEntry> pushes = new Dictionary<string, NoteEntry>();
            foreach (object x in JA(new Dictionary<string, object> { { "a", ev } }, "a"))
            {
                DateTime at = JT(JS(x, "created_at"));
                if (at == DateTime.MinValue) continue;
                string type = JS(x, "type"), repo = JS(x, "repo", "name");
                if (repo == null) continue;
                string name = repo.Substring(repo.IndexOf('/') + 1);
                object pl = J(x, "payload");
                if (type == "CreateEvent" && JS(pl, "ref_type") == "tag")
                {
                    if (WOn("ci")) CiCandidate("github", "github.com", null, repo, name, JS(pl, "ref"), at);
                    continue;
                }
                if (!WOn("github") || at.Date != today) continue;
                if (type == "PushEvent")
                {
                    string br = (JS(pl, "ref") ?? "").Replace("refs/heads/", "");
                    if (br == "" || (JS(pl, "ref") ?? "").StartsWith("refs/tags/")) continue;
                    object[] commits = JA(pl, "commits");
                    int n = commits.Length > 0 ? commits.Length : Math.Max(JI(pl, "size"), JI(pl, "distinct_size"));
                    string msg = commits.Length > 0 ? (JS(commits[commits.Length - 1], "message") ?? "").Split('\n')[0] : null;
                    string id = "github:" + repo + ":push:" + br;
                    NoteEntry e;
                    if (!pushes.TryGetValue(id, out e))
                    {
                        e = new NoteEntry(); e.Id = id; e.Src = "github"; e.Project = name; e.Key = br; e.Ref = br; e.T = at; e.End = at;
                        e.Title = string.IsNullOrEmpty(msg) ? "推到 " + br : msg; e.Url = "https://github.com/" + repo + "/commits/" + br; e.Status = "0";
                        pushes[id] = e;
                    }
                    if (at < e.T) e.T = at;
                    if (at > e.End) { e.End = at; if (!string.IsNullOrEmpty(msg)) e.Title = msg; }
                    e.Status = (int.Parse(e.Status) + Math.Max(0, n)).ToString();
                }
                else if (type == "PullRequestEvent")
                {
                    string act = JS(pl, "action");
                    bool merged = act == "closed" && JS(pl, "pull_request", "merged") == "True";
                    if (act != "opened" && !merged) continue;
                    string num = JS(pl, "pull_request", "number") ?? JS(pl, "number");
                    NoteEntry e = new NoteEntry();
                    e.Id = "github:" + repo + "#" + num + ":" + (merged ? "merged" : "opened"); e.T = at; e.Src = "github"; e.Project = name;
                    e.Title = JS(pl, "pull_request", "title") ?? ("PR #" + num); e.Status = merged ? "合併了" : "開了 PR"; e.Ok = merged ? 1 : -1;
                    e.Ref = "PR #" + num; e.Url = JS(pl, "pull_request", "html_url") ?? ("https://github.com/" + repo + "/pull/" + num);
                    e.Key = JS(pl, "pull_request", "head", "ref") ?? repo;
                    NoteLog.Write(e);
                }
            }
            foreach (NoteEntry e in pushes.Values)
            {
                int n = int.Parse(e.Status);
                e.Status = n > 0 ? "推了 " + n + " 個 commit" : "推上去了";
                if (e.End == e.T) e.End = DateTime.MinValue;
                NoteLog.Write(e);
            }
        }

        // ================= 盯 CI：從 glab／gh 看到你推了 tag（哪個終端機、哪台電腦推的都算）→ 查 pipeline／workflow 直到跑完 =================
        // 為什麼用「你自己的動態」找：不用設定資料夾、不用在 VS Code 推，只看你真的推過的 repo；GitHub 的動態偶爾會晚一兩分鐘。
        class CiWatch { public string Kind, Host, Pid, Repo, Name, Tag, Url, Last = ""; public DateTime Pushed, NextAt, Until; public int Misses; public bool Announced; }
        readonly List<CiWatch> ciWatches = new List<CiWatch>();

        void CiCandidate(string kind, string host, string pid, string repo, string name, string tag, DateTime pushed)
        {
            if (string.IsNullOrEmpty(tag) || (WNow() - pushed).TotalMinutes > 30) return;
            string key = kind + ":" + repo + ":" + tag;
            List<string> seen = SeenList(Seen("ci-seen"));
            if (seen.Contains(key)) return;
            seen.Add(key); SetSeen("ci-seen", SeenJoin(seen));
            CiWatch w = new CiWatch();
            w.Kind = kind; w.Host = host; w.Pid = pid; w.Repo = repo; w.Name = name; w.Tag = tag; w.Pushed = pushed;
            w.NextAt = DateTime.Now.AddSeconds(App.Offscreen ? 0 : 15); w.Until = DateTime.Now.AddMinutes(90);
            lock (ciWatches) ciWatches.Add(w);
            App.Log("work ci: watching " + kind + " " + tag);
        }

        void CiStep(JavaScriptSerializer js, bool force)
        {
            List<CiWatch> l;
            lock (ciWatches) l = new List<CiWatch>(ciWatches);
            foreach (CiWatch w in l)
            {
                if (DateTime.Now < w.NextAt && !force) continue;
                w.NextAt = DateTime.Now.AddSeconds(20);
                string status = null, url = null;
                bool tool = true;
                if (w.Kind == "gitlab")
                {
                    object r = Glab(js, w.Host, "projects/" + w.Pid + "/pipelines?ref=" + Uri.EscapeDataString(w.Tag) + "&per_page=1");
                    if (r == null) tool = false;
                    else { object[] a = JA(new Dictionary<string, object> { { "a", r } }, "a"); if (a.Length > 0) { status = JS(a[0], "status"); url = JS(a[0], "web_url"); } }
                }
                else
                {
                    object r = Gh(js, "repos/" + w.Repo + "/actions/runs?per_page=20");
                    if (r == null) tool = false;
                    else
                        foreach (object run in JA(r, "workflow_runs"))
                        {
                            if (JS(run, "head_branch") != w.Tag) continue;
                            status = JS(run, "status") != "completed" ? "running" : (JS(run, "conclusion") == "success" ? "success" : "failed");
                            url = JS(run, "html_url");
                            break;
                        }
                }
                bool end = false;
                if (!tool || DateTime.Now > w.Until) end = true;
                else if (status == null) { if (++w.Misses > 12) end = true; }   // 4 分鐘都沒有 pipeline：這個 tag 不跑 CI
                else
                {
                    w.Url = url;
                    string where = Regex.IsMatch(w.Tag, "Production", RegexOptions.IgnoreCase) ? "正式機" : (Regex.IsMatch(w.Tag, "Development", RegexOptions.IgnoreCase) ? "測試機" : "");
                    if (status == "success")
                    { WNotify("ci-ok", url, w.Name + " " + w.Tag + " " + where + "部署成功！"); CiLog(w, "CI 過了", 1, true); end = true; }
                    else if (status == "failed" || status == "canceled" || status == "cancelled")
                    { WNotify("ci-fail", url, w.Name + " " + w.Tag + " " + where + "部署失敗（" + status + "），點我看 pipeline"); CiLog(w, "CI 沒過", 0, true); end = true; }
                    else if (!w.Announced)
                    { w.Announced = true; WNotify("ci-run", url, w.Name + " " + w.Tag + " " + where + "CI 開始跑了，好了叫你"); CiLog(w, "CI 跑起來了", -1, false); }
                }
                if (end) lock (ciWatches) ciWatches.Remove(w);
            }
        }
        void CiLog(CiWatch w, string status, int ok, bool done)
        {
            NoteEntry e = new NoteEntry();
            e.Id = "ci:" + w.Repo + ":" + w.Tag; e.T = w.Pushed; if (done) e.End = WNow();
            e.Src = "ci"; e.Project = w.Name; e.Title = "發 " + w.Tag; e.Status = status; e.Ok = ok; e.Ref = w.Tag; e.Url = w.Url; e.Key = w.Repo;
            NoteLog.Write(e);
        }

        // ================= 開會（ICS）：開會前 N 分鐘、開始時提醒；開會中自動安靜 =================
        class MeetItem { public long At, End; public string Kind, Text, Url, Key, Uid, Summary; public long Start; }
        List<MeetItem> meetPlan = new List<MeetItem>();
        readonly HashSet<string> meetFired = new HashSet<string>();
        string meetText = "", meetErr = "";
        public string WorkMeetUrl() { return WorkOwns("meet") ? WorkUrl(WC("meet_url")) ?? "" : ""; }

        void MeetFetch()
        {
            string url = WorkUrl(WC("meet_url"));
            if (url == null) return;
            string err = "";
            string text = Fetch(url, ref err);
            meetErr = err;
            if (text == null) return;
            meetText = text;
            MeetPlan();
        }

        void MeetPlan()
        {
            string url = WC("meet_url");
            Match om = Regex.Match(url, "/ical/([^/]+)/");
            string owner = om.Success ? Uri.UnescapeDataString(om.Groups[1].Value) : "", cal;
            int before;
            if (!int.TryParse(WC("meet_before"), out before) || before < 1) before = 5;
            long now = WNowMs();
            List<IcsOcc> occ = Ics.Occurrences(Ics.Parse(meetText, owner, out cal), now - 60000, now + 26 * 3600000L);
            // 同一時間好幾場 → 合成一則
            Dictionary<long, List<IcsOcc>> groups = new Dictionary<long, List<IcsOcc>>();
            List<long> order = new List<long>();
            foreach (IcsOcc o in occ) { List<IcsOcc> g; if (!groups.TryGetValue(o.Start, out g)) { g = new List<IcsOcc>(); groups[o.Start] = g; order.Add(o.Start); } g.Add(o); }
            List<MeetItem> plan = new List<MeetItem>();
            foreach (long start in order)
            {
                List<IcsOcc> g = groups[start];
                string uid = "", link = "", summary;
                long end = start;
                foreach (IcsOcc o in g) { uid += (uid == "" ? "" : "+") + o.Uid; if (link == "") link = o.Link ?? ""; end = Math.Max(end, o.End); }
                summary = g.Count > 1 ? g[0].Summary + "、" + g[1].Summary + (g.Count > 2 ? " 等 " + g.Count + " 場" : "") : g[0].Summary;
                string hhmm = LocalOfMs(start).ToString("HH:mm");
                string key = uid + "@" + start;
                MeetItem pre = new MeetItem(); pre.At = start - before * 60000L; pre.Kind = "meeting"; pre.Url = link; pre.Key = key + "-pre"; pre.Start = start; pre.End = end; pre.Uid = uid; pre.Summary = summary;
                pre.Text = hhmm + " 有會：" + summary + "（" + before + " 分鐘後）";
                MeetItem go = new MeetItem(); go.At = start; go.Kind = "meeting-now"; go.Url = link; go.Key = key + "-now"; go.Start = start; go.End = end; go.Uid = uid; go.Summary = summary;
                go.Text = summary + " 開始了！" + (link != "" ? "點我進會議" : "");
                if (pre.At > now - 60000) plan.Add(pre);
                plan.Add(go);
            }
            lock (meetFired) meetPlan = plan;
        }

        void MeetTick()
        {
            long now = WNowMs();
            List<MeetItem> fire = new List<MeetItem>();
            lock (meetFired)
                foreach (MeetItem it in meetPlan)
                {
                    if (it.At > now || meetFired.Contains(it.Key)) continue;
                    meetFired.Add(it.Key);
                    if (now - it.At > 3 * 60000L) continue;   // 電腦睡著錯過太久的就不補
                    fire.Add(it);
                }
            foreach (MeetItem it in fire)
            {
                WNotify(it.Kind, it.Url, it.Text);
                if (it.Kind != "meeting-now") continue;
                NoteEntry e = new NoteEntry();
                e.Id = "calendar:" + it.Uid + "@" + it.Start; e.T = LocalOfMs(it.Start); e.End = LocalOfMs(it.End);
                e.Src = "calendar"; e.Title = it.Summary; e.Url = it.Url != "" ? it.Url : null;
                NoteLog.Write(e);
                if (WOn("meet_quiet"))
                {
                    int mins = (int)Math.Round((it.End - now) / 60000.0);
                    if (mins > 0) { int q = Math.Min(mins, 240); Post(delegate { Later(1.5, delegate { StartQuiet(q); }); }); }
                }
            }
        }

        // ================= 下雨：平日 17:30 看一次（等一下下班、下一個上班日）=================
        static readonly Dictionary<string, double[]> RainCity = new Dictionary<string, double[]> {
            { "台北", new double[] { 25.05, 121.53 } }, { "臺北", new double[] { 25.05, 121.53 } }, { "新北", new double[] { 25.01, 121.47 } }, { "桃園", new double[] { 24.99, 121.31 } },
            { "新竹", new double[] { 24.80, 120.97 } }, { "台中", new double[] { 24.15, 120.67 } }, { "臺中", new double[] { 24.15, 120.67 } }, { "台南", new double[] { 22.99, 120.21 } },
            { "臺南", new double[] { 22.99, 120.21 } }, { "高雄", new double[] { 22.63, 120.30 } }, { "基隆", new double[] { 25.13, 121.74 } }, { "宜蘭", new double[] { 24.76, 121.75 } },
            { "花蓮", new double[] { 23.99, 121.60 } }, { "台東", new double[] { 22.76, 121.14 } }, { "臺東", new double[] { 22.76, 121.14 } }, { "嘉義", new double[] { 23.48, 120.45 } },
            { "彰化", new double[] { 24.08, 120.54 } }, { "苗栗", new double[] { 24.56, 120.82 } }, { "屏東", new double[] { 22.67, 120.49 } }, { "南投", new double[] { 23.91, 120.68 } },
            { "雲林", new double[] { 23.71, 120.54 } }, { "香港", new double[] { 22.32, 114.17 } }, { "九龍", new double[] { 22.32, 114.18 } }, { "澳門", new double[] { 22.20, 113.55 } } };
        static readonly Dictionary<string, string> RainCityEn = new Dictionary<string, string> {
            { "台北", "Taipei" }, { "臺北", "Taipei" }, { "新北", "New Taipei" }, { "桃園", "Taoyuan" }, { "新竹", "Hsinchu" }, { "台中", "Taichung" }, { "臺中", "Taichung" },
            { "台南", "Tainan" }, { "臺南", "Tainan" }, { "高雄", "Kaohsiung" }, { "基隆", "Keelung" }, { "宜蘭", "Yilan" }, { "花蓮", "Hualien" }, { "台東", "Taitung" },
            { "臺東", "Taitung" }, { "嘉義", "Chiayi" }, { "彰化", "Changhua" }, { "苗栗", "Miaoli" }, { "屏東", "Pingtung" }, { "南投", "Nantou" }, { "雲林", "Yunlin" },
            { "香港", "Hong Kong" }, { "九龍", "Kowloon" }, { "澳門", "Macau" } };

        // 測試（只在離屏模式）：DESKPALS_FAKE_WEB＝本機假伺服器，代替 wttr.in／api.met.no
        static string WeatherBase(string real, string fakePath)
        {
            string f = App.Offscreen ? Environment.GetEnvironmentVariable("DESKPALS_FAKE_WEB") : null;
            return string.IsNullOrEmpty(f) ? real : f.TrimEnd('/') + fakePath;
        }
        static DateTime NextWorkday(DateTime d) { DateTime n = d.Date; do n = n.AddDays(1); while (n.DayOfWeek == DayOfWeek.Saturday || n.DayOfWeek == DayOfWeek.Sunday); return n; }

        void RainCheck(JavaScriptSerializer js)
        {
            DateTime d = WNow();
            int hm = d.Hour * 60 + d.Minute;
            if (d.DayOfWeek == DayOfWeek.Saturday || d.DayOfWeek == DayOfWeek.Sunday || hm < 17 * 60 + 30 || hm > 19 * 60) return;
            string k = "rain:" + d.ToString("yyyyMMdd");
            if (Seen(k) != null) return;
            string loc = WC("rain_place").Trim();
            double lat = double.NaN, lon = double.NaN;
            string q = loc;
            Match m = Regex.Match(loc, @"^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$");
            if (m.Success) { lat = double.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture); lon = double.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture); q = m.Groups[1].Value + "," + m.Groups[2].Value; }
            else
            {
                string c = Regex.Replace(loc, "[市縣]$", "");
                double[] ll; string en;
                if (RainCity.TryGetValue(c, out ll)) { lat = ll[0]; lon = ll[1]; }
                if (RainCityEn.TryGetValue(c, out en)) q = en;
            }
            int st;
            string unit = "%";
            int tonight = -1, next = -1;
            double tonightMm = -1, nextMm = -1;
            string body = HttpGet(WeatherBase("https://wttr.in", "/wttr") + "/" + Uri.EscapeDataString(q) + "?format=j1&lang=zh-tw", null, 20000, out st);
            object j = ParseJson(js, body);
            if (j != null && JA(j, "weather").Length > 0)
            {
                tonight = WttrMax(j, d, 18, 21);
                next = WttrMax(j, NextWorkday(d), 6, 21);
            }
            else if (!double.IsNaN(lat))
            {
                unit = "mm";
                body = HttpGet(WeatherBase("https://api.met.no", "/metno") + "/weatherapi/locationforecast/2.0/compact?lat=" + lat.ToString("0.00", CultureInfo.InvariantCulture) + "&lon=" + lon.ToString("0.00", CultureInfo.InvariantCulture), null, 20000, out st);
                j = ParseJson(js, body);
                if (j == null) return;
                DateTime nx = NextWorkday(d);
                tonightMm = MetSum(j, d.Date.AddHours(18), d.Date.AddHours(22));
                nextMm = MetSum(j, nx.AddHours(6), nx.AddHours(22));
            }
            else return;
            SetSeen(k, "1");
            string label = d.DayOfWeek == DayOfWeek.Friday ? "下週一" : "明天";
            List<string> parts = new List<string>();
            if (unit == "%")
            {
                if (tonight >= 50) parts.Add("等一下下班可能會下雨（降雨機率 " + tonight + "%）");
                if (next >= 50) parts.Add(label + "降雨機率 " + next + "%");
            }
            else
            {
                if (tonightMm >= 1) parts.Add("等一下下班可能會下雨（預估雨量 " + tonightMm.ToString("0.#", CultureInfo.InvariantCulture) + " mm）");
                if (nextMm >= 1) parts.Add(label + "可能下雨，預估雨量 " + nextMm.ToString("0.#", CultureInfo.InvariantCulture) + " mm");
            }
            if (parts.Count > 0) WNotify("rain", "-", string.Join("，", parts.ToArray()) + "，記得帶傘 ☔");
        }
        static int WttrMax(object j, DateTime day, int from, int to)
        {
            string ymd = day.ToString("yyyy-MM-dd");
            int mx = -1;
            foreach (object w in JA(j, "weather"))
            {
                if (JS(w, "date") != ymd) continue;
                foreach (object h in JA(w, "hourly"))
                {
                    int hr = JI(h, "time") / 100;
                    if (hr >= from && hr <= to) mx = Math.Max(mx, Math.Max(0, JI(h, "chanceofrain")));
                }
            }
            return mx;
        }
        static double MetSum(object j, DateTime from, DateTime to)
        {
            double mm = 0; bool any = false;
            foreach (object t in JA(j, "properties", "timeseries"))
            {
                DateTime at = JT(JS(t, "time"));
                if (at < from || at >= to) continue;
                string v = JS(t, "data", "next_1_hours", "details", "precipitation_amount");
                double x;
                if (v != null && double.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, out x)) { mm += x; any = true; }
            }
            return any ? Math.Round(mm * 10) / 10 : -1;
        }

        // ================= 工作日誌資料夾：今天出現新檔就說 =================
        void WorklogCheck()
        {
            string dir = WC("worklog_dir");
            if (!Directory.Exists(dir)) return;
            FileInfo newest = null;
            foreach (FileInfo f in new DirectoryInfo(dir).EnumerateFiles())
                if (Regex.IsMatch(f.Name, @"\.(md|txt|docx?|xlsx?)$", RegexOptions.IgnoreCase) && (newest == null || f.LastWriteTimeUtc > newest.LastWriteTimeUtc)) newest = f;
            if (newest == null) return;
            string k = "worklog:" + dir, t = newest.LastWriteTimeUtc.Ticks.ToString();
            string last = Seen(k);
            SetSeen(k, t);
            if (last == null || string.CompareOrdinal(t.PadLeft(20, '0'), last.PadLeft(20, '0')) <= 0) return;
            if (newest.LastWriteTime.Date == DateTime.Now.Date) WNotify("worklog", new Uri(newest.FullName).AbsoluteUri, "今天的工作日誌好了：" + newest.Name);
        }

        // ================= Claude Code／Codex：做完的對話寫進小本子 =================
        // ~/.claude、~/.codex 的預設位置（CLAUDE_CONFIG_DIR／CODEX_HOME 沒設時）。
        // 離屏（測試，含 DESKPALS_ISOLATED）一律改成資料資料夾裡的空資料夾：測試絕不讀使用者真的對話紀錄
        static string AiHomeDefault(string name)
        {
            if (!App.Offscreen) return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), name);
            string d = Path.Combine(DataDir, "test-home", name);
            try { Directory.CreateDirectory(d); } catch { }
            return d;
        }

        // 進階：別的資料夾（WSL 裡的 Claude／Codex）。給 .claude 或 .claude\projects 都可以
        public List<string> WorkClaudeRoots()
        {
            List<string> l = new List<string>();
            l.Add(ClaudeProjectsDir());
            string c = WC("claude_dir");
            if (c != "")
            {
                string p = Directory.Exists(Path.Combine(c, "projects")) ? Path.Combine(c, "projects") : c;
                if (!l.Exists(delegate(string x) { return string.Equals(x.TrimEnd('\\'), p.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase); })) l.Add(p);
            }
            return l.FindAll(delegate(string x) { try { return Directory.Exists(x); } catch { return false; } });
        }
        public List<string> WorkCodexRoots()
        {
            List<string> l = new List<string>();
            l.Add(CodexSessionsDir());
            string c = WC("codex_dir");
            if (c != "")
            {
                string p = Directory.Exists(Path.Combine(c, "sessions")) ? Path.Combine(c, "sessions") : c;
                if (!l.Exists(delegate(string x) { return string.Equals(x.TrimEnd('\\'), p.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase); })) l.Add(p);
            }
            return l.FindAll(delegate(string x) { try { return Directory.Exists(x); } catch { return false; } });
        }
        // WSL 裡跑的 claude／codex 在 Windows 這邊看不到行程：有設別的資料夾、WSL 開著就當作有在跑
        public bool WorkWslAlive(string key)
        {
            if (WC(key) == "") return false;
            foreach (string n in new string[] { "wsl", "wslhost", "vmmemWSL", "vmmem" }) if (Process.GetProcessesByName(n).Length > 0) return true;
            return false;
        }

        readonly Dictionary<string, DateTime> aiLogged = new Dictionary<string, DateTime>();
        int aiWritten;

        void AiScan(JavaScriptSerializer js)
        {
            DateTime now = DateTime.Now;
            foreach (string root in WorkClaudeRoots())
                foreach (string pdir in Directory.GetDirectories(root))
                    foreach (FileInfo fi in new DirectoryInfo(pdir).EnumerateFiles("*.jsonl"))
                    {
                        if (fi.Name.StartsWith("agent-")) continue;
                        DateTime mt = fi.LastWriteTime;
                        if (mt.Date != now.Date || (now - mt).TotalSeconds < 60) continue;   // 還在寫的先不記
                        DateTime was;
                        if (aiLogged.TryGetValue(fi.FullName, out was) && was == mt) continue;
                        string tool, title;
                        string kind = ClaudeState(js, fi.FullName, out tool, out title);
                        if (kind != "idle" && (now - mt).TotalMinutes < 10) continue;      // 還沒講完（等工具、在想）：晚點再看
                        aiLogged[fi.FullName] = mt;
                        if (NoteLog.Write(ClaudeEntry(js, fi))) aiWritten++;
                    }
            foreach (string root in WorkCodexRoots())
                for (int back = 0; back < 7; back++)
                {
                    DateTime dd = now.Date.AddDays(-back);
                    string dir = Path.Combine(root, dd.ToString("yyyy"), dd.ToString("MM"), dd.ToString("dd"));
                    if (!Directory.Exists(dir)) continue;
                    foreach (FileInfo fi in new DirectoryInfo(dir).EnumerateFiles("rollout-*.jsonl"))
                    {
                        DateTime mt = fi.LastWriteTime;
                        if (mt.Date != now.Date || (now - mt).TotalSeconds < 60) continue;
                        DateTime was;
                        if (aiLogged.TryGetValue(fi.FullName, out was) && was == mt) continue;
                        CodexState st = ParseCodex(fi.FullName);
                        if (st.Busy || st.LastComplete == DateTime.MinValue) { if ((now - mt).TotalMinutes < 10) continue; }
                        aiLogged[fi.FullName] = mt;
                        if (NoteLog.Write(CodexEntry(js, fi, st))) aiWritten++;
                    }
                }
            if (aiLogged.Count > 2000) aiLogged.Clear();
        }

        static readonly Regex TsRx = new Regex("\"timestamp\":\"([^\"]+)\"");
        static readonly Regex AiTitleRx = new Regex("^\\{\"type\":\"ai-title\"");

        // 對話的第一句需求（去掉指令、系統訊息、IDE 附帶的標籤），太長就剪
        static string FirstAsk(string s)
        {
            if (s == null) return null;
            s = Regex.Replace(s, @"<(ide_[a-z_]+|system-reminder|environment_context|user_instructions|command-[a-z]+)>[\s\S]*?</\1>", " ");
            s = NoteLog.OneLine(s);
            if (s == "" || s.StartsWith("<") || s.StartsWith("[Request interrupted") || s.StartsWith("Caveat:")) return null;
            return NoteLog.Cut(s, 40);
        }
        static string UserText(object content)
        {
            string s = content as string;
            if (s != null) return FirstAsk(s);
            object[] arr = content as object[];
            if (arr == null) { System.Collections.ArrayList al = content as System.Collections.ArrayList; if (al != null) arr = al.ToArray(); }
            if (arr == null) return null;
            foreach (object o in arr)
            {
                if (JS(o, "type") != "text") continue;
                string t = FirstAsk(JS(o, "text"));
                if (t != null) return t;
            }
            return null;
        }
        static DateTime UtcLocal(string iso)
        {
            DateTime t;
            if (iso != null && DateTime.TryParse(iso, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal, out t)) return t.ToLocalTime();
            return DateTime.MinValue;
        }

        NoteEntry ClaudeEntry(JavaScriptSerializer js, FileInfo fi)
        {
            string text = fi.Length <= 3 * 1024 * 1024 ? Tail(fi.FullName, 3 * 1024 * 1024) : Head(fi.FullName, 1024 * 1024) + "\n" + Tail(fi.FullName, 1024 * 1024);
            string[] lines = text.Split('\n');
            string cwd = null, ask = null, aiTitle = null;
            DateTime t0 = DateTime.MinValue, t1 = DateTime.MinValue;
            Dictionary<DateTime, DateTime> firstOn = new Dictionary<DateTime, DateTime>();   // 每一天的第一筆（同一個對話開好幾天：那天的紀錄從那天開始算）
            foreach (string raw in lines)
            {
                string l = raw.Trim();
                if (l.Length < 2) continue;
                if (AiTitleRx.IsMatch(l)) { string at = JS(ParseJson(js, l), "aiTitle"); if (!string.IsNullOrEmpty(at)) aiTitle = at; continue; }
                Match tm = TsRx.Match(l.Length > 4000 ? l.Substring(0, 4000) + l.Substring(Math.Max(4000, l.Length - 4000)) : l);
                if (tm.Success) { DateTime t = UtcLocal(tm.Groups[1].Value); if (t != DateTime.MinValue) { if (t0 == DateTime.MinValue) t0 = t; if (!firstOn.ContainsKey(t.Date)) firstOn[t.Date] = t; t1 = t; } }
                if (ask != null && cwd != null) continue;
                if (l.IndexOf("\"type\":\"user\"", StringComparison.Ordinal) < 0 || l.IndexOf("\"isSidechain\":true", StringComparison.Ordinal) >= 0) continue;
                object d = ParseJson(js, l.Length > 400000 ? null : l);
                if (d == null || JS(d, "type") != "user" || JS(d, "isMeta") == "True") continue;
                if (cwd == null) cwd = JS(d, "cwd");
                if (ask == null) ask = UserText(J(d, "message", "content"));
            }
            string title = !string.IsNullOrEmpty(aiTitle) ? NoteLog.Cut(aiTitle, 60) : ask;
            if (title == null || t0 == DateTime.MinValue) return null;
            DateTime td;
            if (t1.Date != t0.Date && firstOn.TryGetValue(t1.Date, out td)) t0 = td;
            NoteEntry e = new NoteEntry();
            e.Id = "claude:" + Path.GetFileNameWithoutExtension(fi.Name); e.T = t0; e.End = t1 > t0 ? t1 : DateTime.MinValue;
            e.Src = "claude"; e.Title = title;
            e.Project = cwd != null ? Path.GetFileName(cwd.TrimEnd('\\', '/')) : ProjectFromFolder(fi.Directory.Name);
            e.Key = e.Project;
            return e;
        }
        // Claude 的資料夾名字是把路徑的 \ / : 換成 -（c--tmp-dp-wt-work）：取最後一段（不完美，只在讀不到 cwd 時用）
        static string ProjectFromFolder(string n) { int i = n.LastIndexOf('-'); return i >= 0 && i < n.Length - 1 ? n.Substring(i + 1) : n; }

        NoteEntry CodexEntry(JavaScriptSerializer js, FileInfo fi, CodexState st)
        {
            string head = Head(fi.FullName, 2 * 1024 * 1024);
            string id = null, cwd = null, ask = null;
            DateTime t0 = DateTime.MinValue;
            foreach (string raw in head.Split('\n'))
            {
                string l = raw.Trim();
                if (l.Length < 2) continue;
                if (id == null && l.IndexOf("\"type\":\"session_meta\"", StringComparison.Ordinal) >= 0)
                {
                    object d = ParseJson(js, l);
                    id = JS(d, "payload", "id"); cwd = JS(d, "payload", "cwd");
                    t0 = UtcLocal(JS(d, "payload", "timestamp") ?? JS(d, "timestamp"));
                    continue;
                }
                if (ask == null && l.IndexOf("\"user_message\"", StringComparison.Ordinal) >= 0 && l.Length < 400000)
                {
                    object d = ParseJson(js, l);
                    if (JS(d, "payload", "type") == "user_message") ask = FirstAsk(JS(d, "payload", "message"));
                }
                if (id != null && ask != null) break;
            }
            if (ask == null) return null;
            if (t0 == DateTime.MinValue) { Match tm = TsRx.Match(head); if (tm.Success) t0 = UtcLocal(tm.Groups[1].Value); }
            if (t0 == DateTime.MinValue) return null;
            if (id == null) { Match m = Regex.Match(fi.Name, @"([0-9a-f]{8}-[0-9a-f-]{27,})\.jsonl$"); id = m.Success ? m.Groups[1].Value : Path.GetFileNameWithoutExtension(fi.Name); }
            NoteEntry e = new NoteEntry();
            e.Id = "codex:" + id; e.T = t0;
            e.End = st.LastComplete != DateTime.MinValue ? st.LastComplete.ToLocalTime() : fi.LastWriteTime;
            if (e.End != DateTime.MinValue && e.End.Date != e.T.Date)
            {
                // 同一個對話開好幾天：那天的紀錄從那天的第一筆開始算
                foreach (string raw in Tail(fi.FullName, 1024 * 1024).Split('\n'))
                {
                    Match tm = CodexRx.Match(raw.Length > 400 ? raw.Substring(0, 400) : raw);
                    if (!tm.Success) continue;
                    DateTime t = UtcLocal(tm.Groups[1].Value);
                    if (t.Date == e.End.Date) { e.T = t; break; }
                }
            }
            if (e.End <= e.T) e.End = DateTime.MinValue;
            e.Src = "codex"; e.Title = ask;
            e.Project = cwd != null ? Path.GetFileName(cwd.TrimEnd('\\', '/')) : null; e.Key = e.Project;
            return e;
        }

        // ================= 學校行事曆的上課也進小本子（DeskPals.Study.cs 的 PlanTick 叫）=================
        void WorkLogClass(SchoolPlanItem it)
        {
            NoteEntry e = new NoteEntry();
            string name = Regex.Replace(it.Text ?? "", "（點我打開）$", "");
            e.Id = "school:" + it.Key; e.T = LocalOfMs(it.At); if (it.QuietMin > 0) e.End = LocalOfMs(it.At + it.QuietMin * 60000L);
            e.Src = "school"; e.Project = name; e.Title = "上課：" + name; e.Url = it.Url != "" ? it.Url : null;
            NoteLog.Write(e);
        }

        // ================= 設定視窗（畫面還在挑版：先留入口，給小屋選單和小本子的「來源」按鈕叫）=================
        public void ShowWorkSettings()
        {
            App.Log("work settings: dialog not built yet");
        }

        // ================= pipe =================
        bool WorkMsg(Client c, string[] p, string line)
        {
            if (!p[0].StartsWith("work-")) return false;
            WorkLoad();
            string t = line.Trim();
            int sp = t.IndexOf(' ');
            string rest = sp > 0 ? t.Substring(sp + 1) : "";
            switch (p[0])
            {
                case "work-set":
                    if (p.Length >= 2)
                    {
                        int s2 = rest.IndexOf(' ');
                        string v = s2 > 0 ? rest.Substring(s2 + 1) : "";
                        if (!WorkSet(p[1], v)) Send(c, "work-set bad " + p[1] + "\n");
                    }
                    return true;
                case "work-token": SetJiraToken(rest); return true;
                case "work-poll": workPollNow = true; if (workWake != null) workWake.Set(); return true;
                case "work-dump": Send(c, WorkDump()); return true;
                case "work-settings": if (p.Length >= 2 && p[1] == "open") ShowWorkSettings(); return true;
                case "work-clock":
                    if (!App.Offscreen) return true;
                    { DateTime want; workShift = p.Length >= 2 && DateTime.TryParse(p[1], CultureInfo.InvariantCulture, DateTimeStyles.None, out want) ? want - DateTime.Now : TimeSpan.Zero; }
                    if (meetText != "") MeetPlan();
                    return true;
                case "work-vpncheck":
                    if (!App.Offscreen) return true;
                    { string h = companyHost; Send(c, "work-vpn " + (h == "" ? "none" : (VpnReachable(h) ? "ok" : "down")) + " " + h + "\n"); }
                    return true;
                case "work-forget":
                    if (!App.Offscreen) return true;
                    lock (wcfg) { wseen.Clear(); seenDirty = true; }
                    lock (meetFired) meetFired.Clear();
                    aiLogged.Clear();
                    return true;
            }
            return true;
        }

        string WorkDump()
        {
            StringBuilder sb = new StringBuilder("work");
            lock (wcfg) foreach (string[] d in WorkDefaults) sb.Append(" " + d[0] + "=" + (wcfg[d[0]] == "" ? "-" : wcfg[d[0]].Replace(' ', '_')));
            sb.Append(" token=" + (HasJiraToken() ? 1 : 0) + " now=" + WNow().ToString("yyyy-MM-ddTHH:mm", CultureInfo.InvariantCulture) + "\n");
            sb.Append(WorkOwnLine());
            sb.Append("work-state host=" + (companyHost == "" ? "-" : companyHost) + " jira=" + (jiraStatus == "" ? "-" : jiraStatus.Replace(' ', '_')) + " glab=" + (glabState == "" ? "-" : glabState)
                + " gh=" + (ghState == "" ? "-" : ghState) + " ghuser=" + (ghUser == "" ? "-" : ghUser) + " dropped=" + workDropped + " polled=" + workPolled + " ai=" + aiWritten
                + " quiet=" + (quietOn ? QuietLeft() : 0) + " meets=" + meetPlan.Count + (meetErr != "" ? " meeterr=" + meetErr.Replace(' ', '_') : "") + "\n");
            sb.Append("work-roots claude=" + string.Join("|", WorkClaudeRoots().ToArray()).Replace(' ', '_') + " codex=" + string.Join("|", WorkCodexRoots().ToArray()).Replace(' ', '_')
                + " home-claude=" + ClaudeProjectsDir().Replace(' ', '_') + " home-codex=" + CodexSessionsDir().Replace(' ', '_') + "\n");
            lock (ciWatches) foreach (CiWatch w in ciWatches) sb.Append("watch " + w.Kind + " " + w.Repo + " " + w.Tag + (w.Announced ? " running" : "") + "\n");
            lock (workNotices) foreach (string n in workNotices) sb.Append("notice " + n + "\n");
            sb.Append("end\n");
            return sb.ToString();
        }
    }
}
