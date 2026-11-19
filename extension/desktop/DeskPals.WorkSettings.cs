// WoWo Pals：「工作設定」視窗（小屋選單 → 工作 → 工作設定…、小本子的「來源」、空白頁的「接上」）。畫面照 v011\work-settings 的 D 版：
//   打開先看格子（九個來源，每格有狀態和 關｜開），點格子進清單（左邊來源、右邊要填的），左上「全部」或 Esc 回格子；右上可以切格子／清單，記住上次的。
//   要填東西的來源（Jira、開會、下雨、公司網路、工作日誌資料夾）填好才會開：按「開」先跳到要填的那一格，填好自己開。
//   GitHub／GitLab 找不到 gh／glab 不能開（寫「找不到 gh」＋怎麼裝）；CI 要先開 GitLab 或 GitHub。
//   Esc：清單 → 格子；格子 → 關掉（跟取消一樣）。儲存時開著的來源有沒填好的，跳過去標紅，不關。
// 設定讀寫都走 World 的 WC()／WorkSet()／SetJiraToken()（DeskPals.Work.cs）；看的方式記在 work-ui.txt。
// 離屏測試：pipe「work-settings open|close|save|info|press <id>|type <欄位> <字>|key esc|tab|space」，snap 時畫進虛擬螢幕。
// 刻意寫成 C# 5。
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.Diagnostics;
    using System.Drawing;
    using System.Drawing.Drawing2D;
    using System.Drawing.Imaging;
    using System.IO;
    using System.Text;
    using System.Text.RegularExpressions;
    using System.Threading;
    using System.Windows.Forms;

    partial class World
    {
        WorkSettingsForm workForm;

        // 小屋選單「工作設定…」、小本子的「來源」「接上」、pipe「work-settings open」
        public void ShowWorkSettings() { ShowWorkSettings(null); }
        public void ShowWorkSettings(string src)
        {
            if (workForm == null || workForm.IsDisposed) workForm = new WorkSettingsForm(this);
            else workForm.Reload();
            if (src != null) workForm.OpenSource(src);
            Rectangle wa = App.Offscreen ? screens[0].WorkingArea : Screen.FromPoint(Cursor.Position).WorkingArea;
            workForm.FitTo(wa);
            workForm.Location = new Point(wa.Left + Math.Max(0, (wa.Width - workForm.Width) / 2), wa.Top + Math.Max(0, (wa.Height - workForm.Height) / 2));
            workForm.Show();
            WorkSettingsForm f = workForm;
            // glab／gh 有沒有裝、登入了沒：打開時重新看一次（背景），看完重畫
            ThreadPool.QueueUserWorkItem(delegate { Try("auth", DetectAuth); Post(delegate { if (!f.IsDisposed) f.Invalidate(); }); });
            if (App.Offscreen) return;
            ActivateForm(workForm);
            Later(0.2, delegate { if (!f.IsDisposed && f.Visible) ActivateForm(f); });
        }

        public string ToolState(string tool) { return tool == "gh" ? ghState : glabState; }
        public string JiraState() { return jiraStatus; }
        void WorkSnap(Graphics g) { if (workForm != null && !workForm.IsDisposed && workForm.VVisible) workForm.PaintTo(g); }

        // 設定視窗的示範：現在帶頭那隻站好的樣子（用預覽用的 World 畫，不動到桌面上的公仔）
        Bitmap workPalPic;
        public Bitmap WorkPalPic(int s)
        {
            if (workPalPic != null) return workPalPic;
            try
            {
                World pv = new World(s, lineup);
                Pet me = pv.Get(Lead().P.Id) ?? (pv.Pets.Count > 0 ? pv.Pets[0] : null);
                if (me != null) workPalPic = me.IconPic();
            }
            catch (Exception ex) { App.Log("work settings pal: " + ex.Message); }
            return workPalPic;
        }

        public void WorkSaved()
        {
            Lead().Say("好～工作設定存好了", 2.2);
        }

        // pipe：work-settings …（open 在 WorkMsg）
        bool WorkSettingsMsg(Client c, string[] p, string line)
        {
            if (p.Length < 2) return true;
            string t = line.Trim();
            switch (p[1])
            {
                case "open": ShowWorkSettings(p.Length >= 3 ? p[2] : null); return true;
            }
            if (workForm == null || workForm.IsDisposed) { if (p[1] == "info") Send(c, "ws none\nend\n"); return true; }
            switch (p[1])
            {
                case "close": workForm.Cancel(); break;
                case "save": workForm.Save(); break;
                case "info": Send(c, workForm.Info() + "end\n"); break;
                case "press": if (p.Length >= 3) workForm.Press(p[2]); break;
                case "type": if (p.Length >= 3) { int i3 = NthSpace(t, 3); workForm.TestType(p[2], i3 > 0 ? t.Substring(i3 + 1) : ""); } break;
                case "key": if (p.Length >= 3) workForm.TestKey(p[2]); break;
            }
            return true;
        }
    }

    class WorkSettingsForm : Form
    {
        class Src { public string Id, Name, Short, Icon, Key, Sub, Say; public Src(string id, string name, string sh, string icon, string key, string sub, string say) { Id = id; Name = name; Short = sh; Icon = icon; Key = key; Sub = sub; Say = say; } }
        static readonly Src[] SRC = {
            new Src("claude", "Claude Code、Codex", "Claude、Codex", "claude", "ai", "本機的對話會記進小本子", "記進小本子了"),
            new Src("jira", "Jira", "Jira", "jira", "jira", null, "PBG-2231 解決了"),
            new Src("gitlab", "GitLab", "GitLab", "gitlab", "gitlab", null, "MR !128 合併了"),
            new Src("github", "GitHub", "GitHub", "github", "github", null, "PR #17 合併了"),
            new Src("ci", "CI", "CI", "tag", "ci", "推了 tag 就幫你盯", "v0.10.4 的 CI 過了"),
            new Src("meet", "開會", "開會", "meet", "meet", null, ""),
            new Src("rain", "下雨", "下雨", "rain", "rain", "平日 17:30 看一次", "等下會下雨，帶傘"),
            new Src("net", "公司網路", "公司網路", "net", "vpn", "連不到就提醒 VPN 斷了", "VPN 好像斷了"),
            new Src("worklog", "工作日誌資料夾", "工作日誌資料夾", "folder", "worklog", "今天有新檔就提醒", "今天的工作日誌好了") };
        static readonly Dictionary<string, string> FILL = new Dictionary<string, string> { { "jira", "填好這三格就會開始" }, { "meet", "填好網址就會開始" }, { "rain", "填好地點就會開始" }, { "net", "填好主機就會開始" }, { "worklog", "選好資料夾就會開始" } };
        static readonly Dictionary<string, string> NEED = new Dictionary<string, string> { { "jira", "要填網站、信箱和 token" }, { "meet", "要填行事曆網址" }, { "rain", "要填地點" }, { "net", "要填主機" }, { "worklog", "要選資料夾" } };
        const string HowGh = "https://cli.github.com/", HowGlab = "https://gitlab.com/gitlab-org/cli#installation", HowJira = "https://id.atlassian.com/manage-profile/security/api-tokens";

        readonly World w;
        readonly double d;
        readonly int U;
        readonly Font plateF, nameF, tileNameF, labF, subF, btnF, segF, boxF, monoF;
        public bool VVisible;
        readonly Dictionary<string, string> v = new Dictionary<string, string>();   // 改到一半的設定（儲存才寫回去）
        readonly HashSet<string> pending = new HashSet<string>(), bad = new HashSet<string>();
        string view = "grid", sel = "claude", hoverId = "", focusStop = "", lastOpened = "";
        bool advOpen, loading;
        readonly Dictionary<string, Rectangle> hits = new Dictionary<string, Rectangle>();
        readonly List<string> stops = new List<string>();   // Tab 的順序（畫的時候排）
        readonly Dictionary<string, TextBox> boxes = new Dictionary<string, TextBox>();
        readonly HashSet<string> shown = new HashSet<string>();   // 現在擺出來的輸入框（離屏時視窗沒顯示，TextBox.Visible 永遠是 false）
        static readonly Color Paper = Pix.C(0xFFFDF7), Sub = Pix.C(0x6B4E33), OkC = Pix.C(0x276A1C), BadC = Pix.C(0xB04040), WarnC = Pix.C(0x8A500C), MuteC = Pix.C(0x6E5238), LinkC = Pix.C(0x7A4A22);

        public WorkSettingsForm(World w)
        {
            this.w = w;
            d = w.S / 4.0;
            U = Math.Max(2, (int)Math.Round(2 * d));
            Text = "WoWo Pals・工作設定";
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false; MinimizeBox = false;
            ShowInTaskbar = true; TopMost = true;
            StartPosition = FormStartPosition.Manual;
            BackColor = Pix.Cream;
            DoubleBuffered = true;
            string jh = "Microsoft JhengHei UI";
            plateF = new Font(jh, 12f, FontStyle.Bold);
            nameF = new Font(jh, 12f, FontStyle.Bold);
            tileNameF = new Font(jh, 11.25f, FontStyle.Bold);
            labF = new Font(jh, 10f, FontStyle.Bold);
            subF = new Font(jh, 8.5f, FontStyle.Bold);
            btnF = new Font(jh, 11f, FontStyle.Bold);
            segF = new Font(jh, 10f, FontStyle.Bold);
            boxF = new Font(jh, 10.5f, FontStyle.Regular);
            monoF = new Font("Consolas", 9.5f);
            ClientSize = new Size(Sc(600), Sc(600));
            KeyPreview = true;
            string[][] fields = { new string[] { "jira_site", "" }, new string[] { "jira_email", "" }, new string[] { "token", "" }, new string[] { "meet_url", "mono" }, new string[] { "meet_before", "" },
                new string[] { "rain_place", "" }, new string[] { "vpn_host", "mono" }, new string[] { "worklog_dir", "mono" }, new string[] { "claude_dir", "mono" }, new string[] { "codex_dir", "mono" } };
            foreach (string[] f in fields)
            {
                TextBox t = new TextBox();
                t.BorderStyle = BorderStyle.None; t.BackColor = Paper; t.ForeColor = Pix.TextC;
                t.Font = f[1] == "mono" ? monoF : boxF;
                t.Visible = false;
                if (f[0] == "token") t.UseSystemPasswordChar = true;
                if (f[0] == "meet_before") t.TextAlign = HorizontalAlignment.Center;
                string key = f[0];
                t.TextChanged += delegate { if (!loading) Typed(key, t.Text); };
                t.GotFocus += delegate { focusStop = "tb:" + key; Invalidate(); };
                boxes[key] = t;
                Controls.Add(t);
            }
            FormClosing += delegate { Remember(); };
            Reload();
            string[] ui = World.ReadWorkUi().Split('\n');
            foreach (string l in ui)
            {
                string[] kv = l.Trim().Split('=');
                if (kv.Length != 2) continue;
                if (kv[0] == "view" && (kv[1] == "grid" || kv[1] == "list")) view = kv[1];
                if (kv[0] == "sel" && Find(kv[1]) != null) sel = kv[1];
            }
            LayoutBoxes();
        }

        int Sc(int x) { return (int)Math.Round(x * d); }

        // 放不進工作區（1366×768 開 125%、1080p 開 175%…）：視窗變矮、裡面可以捲，儲存和取消一定按得到
        public void FitTo(Rectangle wa)
        {
            int chrome = Height - ClientSize.Height, full = Sc(600);
            if (full + chrome <= wa.Height) { AutoScroll = false; ClientSize = new Size(full, full); }
            else
            {
                AutoScroll = true;
                AutoScrollMinSize = new Size(full, full);
                ClientSize = new Size(full + SystemInformation.VerticalScrollBarWidth, Math.Max(Sc(240), wa.Height - chrome));
            }
            LayoutBoxes();
            Invalidate();
        }
        Point Logical(Point p) { return AutoScroll ? new Point(p.X - AutoScrollPosition.X, p.Y - AutoScrollPosition.Y) : p; }
        protected override void OnScroll(ScrollEventArgs se) { base.OnScroll(se); Invalidate(); }
        protected override void OnMouseWheel(MouseEventArgs e) { base.OnMouseWheel(e); Invalidate(); }
        static Src Find(string id) { foreach (Src s in SRC) if (s.Id == id) return s; return null; }

        // 從 World 讀回現在的設定（打開視窗時）
        public void Reload()
        {
            loading = true;
            foreach (string[] k in World.WorkDefaults) v[k[0]] = w.WC(k[0]);
            pending.Clear(); bad.Clear();
            boxes["jira_site"].Text = v["jira_site"]; boxes["jira_email"].Text = v["jira_email"]; boxes["token"].Text = "";
            boxes["meet_url"].Text = v["meet_url"]; boxes["meet_before"].Text = v["meet_before"]; boxes["rain_place"].Text = v["rain_place"];
            boxes["vpn_host"].Text = v["vpn_host"]; boxes["worklog_dir"].Text = v["worklog_dir"]; boxes["claude_dir"].Text = v["claude_dir"]; boxes["codex_dir"].Text = v["codex_dir"];
            advOpen = v["claude_dir"] != "" || v["codex_dir"] != "";
            loading = false;
            LayoutBoxes();
            Invalidate();
        }

        void Remember() { World.WriteWorkUi("view=" + view + "\nsel=" + sel + "\n"); }

        // ================= 規則 =================
        bool On(string id) { Src s = Find(id); return s != null && v[s.Key] == "1" && !Lock(id) && Missing(id).Count == 0; }
        bool Lock(string id) { return id == "ci" && v["gitlab"] != "1" && v["github"] != "1"; }
        string Tool(string id) { return id == "github" ? w.ToolState("gh") : (id == "gitlab" ? w.ToolState("glab") : "ok"); }
        string ToolName(string id) { return id == "github" ? "gh" : "glab"; }

        // 還缺什麼（欄位名稱；tool＝glab／gh 不能用）
        List<string> Missing(string id)
        {
            List<string> m = new List<string>();
            switch (id)
            {
                case "jira":
                    if (v["jira_site"].Trim() == "") m.Add("jira_site");
                    if (!Regex.IsMatch(v["jira_email"].Trim(), @"^\S+@\S+$")) m.Add("jira_email");
                    if (boxes["token"].Text.Trim() == "" && !w.HasJiraToken()) m.Add("token");
                    break;
                case "meet":
                    if (World.WorkUrl(v["meet_url"]) == null) m.Add("meet_url");
                    { int n; if (!int.TryParse(v["meet_before"].Trim(), out n) || n < 1 || n > 120) m.Add("meet_before"); }
                    break;
                case "rain": if (v["rain_place"].Trim() == "") m.Add("rain_place"); break;
                case "net": if (!Regex.IsMatch(v["vpn_host"].Trim(), @"^[\w.-]+(:\d{1,5})?$")) m.Add("vpn_host"); break;
                case "worklog": if (v["worklog_dir"].Trim() == "" || !Directory.Exists(v["worklog_dir"].Trim())) m.Add("worklog_dir"); break;
                case "github": case "gitlab": { string ts = Tool(id); if (ts == "missing" || ts == "nologin") m.Add("tool"); } break;
            }
            return m;
        }

        // 一個來源的一句狀態：字、顏色（ok／bad／warn／mute）、有沒有「怎麼裝」連結
        void StateOf(string id, out string text, out string kind, out string link)
        {
            link = null;
            if (Lock(id)) { text = "先打開 GitLab 或 GitHub"; kind = "mute"; return; }
            if (id == "gitlab" || id == "github")
            {
                string ts = Tool(id), tn = ToolName(id);
                if (ts == "missing") { text = "找不到 " + tn; kind = "bad"; link = id == "github" ? HowGh : HowGlab; return; }
                if (ts == "nologin") { text = tn + " 還沒登入"; kind = "bad"; link = id == "github" ? HowGh : HowGlab; return; }
            }
            Src s = Find(id);
            if (id == "jira" && On(id) && w.JiraState() == "auth" && boxes["token"].Text.Trim() == "") { text = "連不上，檢查 token"; kind = "bad"; return; }
            if (FILL.ContainsKey(id) && Missing(id).Count > 0) { text = "要先填"; kind = "warn"; return; }
            if (On(id)) { text = id == "worklog" ? "已選好" : "已接上"; kind = "ok"; return; }
            text = "關著"; kind = "mute";
        }
        Color KindC(string k) { return k == "ok" ? OkC : (k == "bad" ? BadC : (k == "warn" ? WarnC : MuteC)); }

        // ================= 動作 =================
        void Typed(string key, string text)
        {
            if (key != "token") v[key] = text;
            if (text.Trim() != "") bad.Remove(key);
            // 按過「開」、現在填好了：自己開
            foreach (string id in new List<string>(pending))
                if (Missing(id).Count == 0) { v[Find(id).Key] = "1"; pending.Remove(id); }
            Invalidate();
        }

        public void OpenSource(string id)
        {
            if (Find(id) == null) return;
            sel = id; bad.Clear();
            SetView("list");
        }

        void SetView(string to)
        {
            view = to;
            Remember();
            LayoutBoxes();
            Invalidate();
        }

        void Toggle(string id)
        {
            if (Lock(id)) return;
            Src s = Find(id);
            if (v[s.Key] == "1" || pending.Contains(id))
            {
                v[s.Key] = "0"; pending.Remove(id); bad.Clear();
                Invalidate();
                return;
            }
            List<string> m = Missing(id);
            if (m.Count > 0)
            {
                // 要先填的：不偷偷打開，先跳過去填（填好自己開）；glab／gh 找不到的開不了
                if (m[0] != "tool") pending.Add(id);
                sel = id; bad.Clear();
                SetView("list");
                if (m[0] != "tool") FocusBox(m[0]);
                else focusStop = "howto:" + id;
                return;
            }
            v[s.Key] = "1";
            Invalidate();
        }

        void FocusBox(string key)
        {
            TextBox t;
            if (!boxes.TryGetValue(key, out t)) return;
            LayoutBoxes();
            focusStop = "tb:" + key;
            if (!App.Offscreen) { t.Select(); t.Focus(); }
            Invalidate();
        }

        public void Save()
        {
            // 開著的來源（不是只按了開、還在等填的）有沒填好的：跳過去、標紅、不關
            foreach (Src s in SRC)
            {
                if (v[s.Key] != "1" || Lock(s.Id)) continue;
                List<string> m = Missing(s.Id);
                m.Remove("tool");
                if (m.Count == 0) continue;
                sel = s.Id; bad.Clear(); foreach (string k in m) bad.Add(k);
                SetView("list");
                FocusBox(m[0]);
                return;
            }
            foreach (string[] k in World.WorkDefaults)
            {
                string key = k[0], val = v[key];
                if (key == "ai" || key == "jira" || key == "gitlab" || key == "github" || key == "ci" || key == "meet" || key == "rain" || key == "vpn" || key == "worklog")
                {
                    string id = SrcOfKey(key);
                    val = val == "1" && !Lock(id) && Missing(id).Count == 0 ? "1" : "0";
                }
                if (val.Trim() != w.WC(key)) w.WorkSet(key, val.Trim() == "" ? "-" : val.Trim());
            }
            if (boxes["token"].Text.Trim() != "") w.SetJiraToken(boxes["token"].Text.Trim());
            App.Log("work settings saved");
            Remember();
            w.WorkSaved();
            Close();
        }
        static string SrcOfKey(string key) { foreach (Src s in SRC) if (s.Key == key) return s.Id; return key; }

        public void Cancel() { Remember(); Close(); }

        void Esc()
        {
            if (view == "list") { string back = sel; SetView("grid"); focusStop = "tile:" + back; Invalidate(); }
            else Cancel();
        }

        void OpenLink(string url)
        {
            lastOpened = url;
            if (App.Offscreen) return;
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch (Exception ex) { App.Log("work settings link: " + ex.Message); }
        }

        public void Press(string id)
        {
            string a = id, arg = "";
            int c = id.IndexOf(':');
            if (c > 0) { a = id.Substring(0, c); arg = id.Substring(c + 1); }
            switch (a)
            {
                case "view": SetView(arg); break;
                case "all": SetView("grid"); focusStop = "tile:" + sel; break;
                case "tile": OpenSource(arg); break;
                case "tab": sel = arg; bad.Clear(); Remember(); LayoutBoxes(); Invalidate(); break;
                case "sw": Toggle(arg); break;
                case "howto": OpenLink(arg == "github" || arg == "gitlab" ? HowUrl(arg) : HowJira); break;
                case "adv": advOpen = !advOpen; LayoutBoxes(); Invalidate(); break;
                case "quiet": v["meet_quiet"] = v["meet_quiet"] == "1" ? "0" : "1"; Invalidate(); break;
                case "pickdir": PickDir(); break;
                case "save": Save(); break;
                case "cancel": Cancel(); break;
            }
        }

        void PickDir()
        {
            if (App.Offscreen) return;
            using (FolderBrowserDialog f = new FolderBrowserDialog())
            {
                f.Description = "工作日誌放在哪個資料夾？";
                if (Directory.Exists(v["worklog_dir"])) f.SelectedPath = v["worklog_dir"];
                if (f.ShowDialog(this) == DialogResult.OK) boxes["worklog_dir"].Text = f.SelectedPath;
            }
        }

        // ---- 鍵盤：Esc 回上一層；Tab 在按鈕、格子、輸入框之間走；空白鍵／Enter 按下 ----
        protected override bool ProcessDialogKey(Keys k)
        {
            if (k == Keys.Escape) { Esc(); return true; }
            if (k == Keys.Tab || k == (Keys.Tab | Keys.Shift)) { MoveFocus(k == Keys.Tab ? 1 : -1); return true; }
            if ((k == Keys.Space || k == Keys.Enter) && focusStop != "" && !focusStop.StartsWith("tb:")) { Press(focusStop); return true; }
            return base.ProcessDialogKey(k);
        }
        void MoveFocus(int dir)
        {
            Relayout();
            if (stops.Count == 0) return;
            int i = stops.IndexOf(focusStop);
            i = i < 0 ? (dir > 0 ? 0 : stops.Count - 1) : (i + dir + stops.Count) % stops.Count;
            focusStop = stops[i];
            if (focusStop.StartsWith("tb:")) { if (!App.Offscreen) boxes[focusStop.Substring(3)].Focus(); }
            else if (!App.Offscreen) ActiveControl = null;
            Invalidate();
        }
        public void TestKey(string k)
        {
            if (k == "esc") Esc();
            else if (k == "tab") MoveFocus(1);
            else if (k == "shifttab") MoveFocus(-1);
            else if (k == "space" && focusStop != "" && !focusStop.StartsWith("tb:")) Press(focusStop);
        }
        public void TestType(string key, string text)
        {
            TextBox t;
            if (boxes.TryGetValue(key, out t)) t.Text = text;   // TextChanged → Typed
        }

        string HitAt(Point p) { foreach (KeyValuePair<string, Rectangle> kv in hits) if (kv.Value.Contains(p)) return kv.Key; return ""; }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            string h = HitAt(Logical(e.Location));
            if (h != hoverId) { hoverId = h; Cursor = h != "" ? Cursors.Hand : Cursors.Default; Invalidate(); }
        }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); if (hoverId != "") { hoverId = ""; Invalidate(); } }
        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (e.Button != MouseButtons.Left) return;
            // 開關、連結蓋在格子上面：先看小的
            string best = "";
            int area = int.MaxValue;
            foreach (KeyValuePair<string, Rectangle> kv in hits)
                if (kv.Value.Contains(Logical(e.Location)) && kv.Value.Width * kv.Value.Height < area) { best = kv.Key; area = kv.Value.Width * kv.Value.Height; }
            if (best != "") { focusStop = best; Press(best); }
        }

        // ---- 離屏測試：不真的顯示，snap 時畫進虛擬螢幕 ----
        protected override void SetVisibleCore(bool value)
        {
            if (App.Offscreen) { VVisible = value; base.SetVisibleCore(false); return; }
            base.SetVisibleCore(value);
        }
        public void PaintTo(Graphics g)
        {
            Size cs = ClientSize;
            using (Bitmap b = new Bitmap(cs.Width, cs.Height, PixelFormat.Format24bppRgb))
            {
                using (Graphics gg = Graphics.FromImage(b))
                {
                    OnPaint(new PaintEventArgs(gg, new Rectangle(0, 0, cs.Width, cs.Height)));
                    foreach (TextBox t in boxes.Values)
                    {
                        if (!shown.Contains(KeyOf(t))) continue;
                        using (SolidBrush bg = new SolidBrush(t.BackColor)) gg.FillRectangle(bg, t.Bounds);
                        string s = t.UseSystemPasswordChar ? new string('●', t.Text.Length) : t.Text;
                        string cue;
                        if (s == "" && cues.TryGetValue(t, out cue)) { PixText.DrawText(gg, cue, t.Font, t.Bounds, Pix.C(0x866B51), TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis); continue; }
                        PixText.DrawText(gg, s, t.Font, t.Bounds, t.ForeColor, (t.TextAlign == HorizontalAlignment.Center ? TextFormatFlags.HorizontalCenter : TextFormatFlags.Left) | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);   // 離屏（含假的 150%）照同一個 DPI 畫
                    }
                }
                g.DrawImageUnscaled(b, Left, Top);
            }
        }

        // 離屏時視窗沒顯示、不會自己重畫：要知道按鈕在哪（Tab 順序、測試）之前先在記憶體裡畫一次
        void Relayout()
        {
            if (!App.Offscreen || ClientSize.Width <= 0) return;
            using (Bitmap b = new Bitmap(ClientSize.Width, ClientSize.Height, PixelFormat.Format24bppRgb))
            using (Graphics g = Graphics.FromImage(b)) OnPaint(new PaintEventArgs(g, new Rectangle(0, 0, ClientSize.Width, ClientSize.Height)));
        }

        public string Info()
        {
            Relayout();
            StringBuilder sb = new StringBuilder();
            sb.Append("ws view=" + view + " sel=" + sel + " focus=" + (focusStop == "" ? "-" : focusStop) + " pending=" + Join(pending) + " bad=" + Join(bad)
                + " link=" + (lastOpened == "" ? "-" : lastOpened) + " size=" + ClientSize.Width + "x" + ClientSize.Height + " scroll=" + (AutoScroll ? 1 : 0) + " title=" + Text.Replace(' ', '_') + "\n");
            foreach (Src s in SRC)
            {
                string t, k, l;
                StateOf(s.Id, out t, out k, out l);
                sb.Append("src " + s.Id + " want=" + v[s.Key] + " on=" + (On(s.Id) ? 1 : 0) + " lock=" + (Lock(s.Id) ? 1 : 0) + " state=" + t.Replace(' ', '_') + " kind=" + k + "\n");
            }
            foreach (KeyValuePair<string, Rectangle> kv in hits) sb.Append("hit " + kv.Key + " " + kv.Value.X + " " + kv.Value.Y + " " + kv.Value.Width + " " + kv.Value.Height + "\n");
            foreach (KeyValuePair<string, TextBox> kv in boxes) if (shown.Contains(kv.Key)) sb.Append("tb " + kv.Key + " " + kv.Value.Text.Replace(' ', '_') + "\n");
            sb.Append("lead " + LeadText(sel).Replace(' ', '_') + "\n");
            return sb.ToString();
        }
        static string Join(HashSet<string> h) { return h.Count == 0 ? "-" : string.Join(",", new List<string>(h).ToArray()); }

        // ================= 版面 =================
        // 100% 時：視窗內 600×600；冠 56；面板 18～582；格子 3×3（172×128）；清單：左邊 178 寬、右邊 366 寬
        Rectangle PaneR() { return new Rectangle(Sc(204), Sc(72), Sc(366), Sc(452)); }
        int FieldY(int i) { return PaneR().Y + Sc(108) + i * Sc(60); }
        Rectangle FieldBox(int i, int wd) { Rectangle p = PaneR(); return new Rectangle(p.X + Sc(22), FieldY(i) + Sc(20), wd > 0 ? wd : p.Width - Sc(44), Sc(28)); }

        void LayoutBoxes()
        {
            foreach (TextBox t in boxes.Values) t.Visible = false;
            shown.Clear();
            if (view != "list") return;
            bool show = v[Find(sel).Key] == "1" || pending.Contains(sel);
            List<KeyValuePair<string, Rectangle>> l = new List<KeyValuePair<string, Rectangle>>();
            switch (sel)
            {
                case "jira": if (show) { l.Add(Kv("jira_site", FieldBox(0, 0))); l.Add(Kv("jira_email", FieldBox(1, 0))); l.Add(Kv("token", FieldBox(2, 0))); } break;
                case "meet": if (show) { l.Add(Kv("meet_url", FieldBox(0, 0))); l.Add(Kv("meet_before", new Rectangle(PaneR().X + Sc(22) + Sc(56), FieldY(1) + Sc(6), Sc(56), Sc(28)))); } break;
                case "rain": if (show) l.Add(Kv("rain_place", FieldBox(0, 0))); break;
                case "net": if (show) l.Add(Kv("vpn_host", FieldBox(0, 0))); break;
                case "worklog": if (show) { Rectangle r = FieldBox(0, 0); r.Width -= Sc(88); l.Add(Kv("worklog_dir", r)); } break;
                case "claude": if (advOpen) { l.Add(Kv("claude_dir", FieldBox(1, 0))); l.Add(Kv("codex_dir", FieldBox(2, 0))); } break;
            }
            foreach (KeyValuePair<string, Rectangle> kv in l)
            {
                TextBox t = boxes[kv.Key];
                Rectangle r = kv.Value;
                int th = t.PreferredHeight;
                Point o = AutoScroll ? AutoScrollPosition : Point.Empty;   // 捲過的話，輸入框跟著位移
                t.Bounds = new Rectangle(r.X + 3 * U + o.X, r.Y + Math.Max(U, (r.Height - th) / 2) + o.Y, r.Width - 6 * U, Math.Min(th, r.Height - 2 * U));
                t.BackColor = bad.Contains(kv.Key) ? Pix.C(0xFDECEA) : Paper;
                t.Visible = true;
                shown.Add(kv.Key);
            }
        }
        // 輸入框的提示字（灰字，打字就不見）
        [System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, string l);
        readonly Dictionary<TextBox, string> cues = new Dictionary<TextBox, string>();
        void Cue(TextBox t, string text)
        {
            string was;
            if (cues.TryGetValue(t, out was) && was == text) return;
            cues[t] = text;
            if (t.IsHandleCreated) SendMessage(t.Handle, 0x1501, (IntPtr)1, text ?? "");   // EM_SETCUEBANNER，有焦點也顯示
            else t.HandleCreated += delegate { string c; if (cues.TryGetValue(t, out c)) SendMessage(t.Handle, 0x1501, (IntPtr)1, c ?? ""); };
        }
        string KeyOf(TextBox t) { foreach (KeyValuePair<string, TextBox> kv in boxes) if (kv.Value == t) return kv.Key; return ""; }
        static KeyValuePair<string, Rectangle> Kv(string k, Rectangle r) { return new KeyValuePair<string, Rectangle>(k, r); }

        // ================= 畫 =================
        void Txt(Graphics g, string s, Font f, Rectangle r, Color c, TextFormatFlags fl) { PixText.DrawText(g, World.NoEmoji(s), f, r, c, fl | TextFormatFlags.NoPrefix); }
        void Hit(string id, Rectangle r, bool stop) { hits[id] = r; if (stop) stops.Add(id); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.None;
            hits.Clear(); stops.Clear();
            if (AutoScroll) g.TranslateTransform(AutoScrollPosition.X, AutoScrollPosition.Y);   // 螢幕太矮：整個內容一起捲
            int W0 = Sc(600), H0 = Sc(600), F = 4 * U, crown = Sc(56);
            Pix.Wood(g, 0, 0, W0, H0, U, false, 23);
            Pix.Panel(g, F, crown, W0 - 2 * F, H0 - crown - F, U, false);
            string t = "工作設定";
            int tw = Pix.TextW(t, plateF), plw = tw + 14 * U, plh = Sc(34);
            Rectangle pr = new Rectangle((W0 - plw) / 2, (crown - plh) / 2 + U / 2, plw, plh);
            Pix.Plate(g, t, plateF, pr, U);
            Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.X - 9 * U, pr.Y + plh / 2 - 2 * U, U);
            Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.Right + 4 * U, pr.Y + plh / 2 - 2 * U, U);
            ViewSwitch(g, W0);
            if (view == "grid") PaintGrid(g); else PaintList(g);
            int by = H0 - Sc(64), bh = Sc(44);
            Button(g, "cancel", "取消", new Rectangle(Sc(30), by, Sc(130), bh), false);
            Button(g, "save", "儲存", new Rectangle(W0 - Sc(30) - Sc(160), by, Sc(160), bh), true);
            foreach (KeyValuePair<string, TextBox> kv in boxes) if (shown.Contains(kv.Key)) { int i = stops.IndexOf("tbpos:" + kv.Key); if (i >= 0) stops[i] = "tb:" + kv.Key; }
            stops.RemoveAll(delegate(string s) { return s.StartsWith("tbpos:"); });
            // 鍵盤焦點：虛線框
            Rectangle fr;
            if (focusStop != "" && !focusStop.StartsWith("tb:") && hits.TryGetValue(focusStop, out fr))
                using (Pen p = new Pen(Pix.Ink, Math.Max(2, U))) { p.DashStyle = DashStyle.Dash; g.DrawRectangle(p, fr.X + 2 * U, fr.Y + 2 * U, fr.Width - 4 * U - 1, fr.Height - 4 * U - 1); }   // 鍵盤焦點：往內縮的深木色虛線
        }

        void ViewSwitch(Graphics g, int W0)
        {
            string[] ids = { "grid", "list" }, names = { "格子", "清單" };
            int bw = Sc(64), bh = Sc(26), x = W0 - Sc(14) - 2 * bw - 3 * U, y = Sc(13);
            Pix.Round(g, Pix.Ink, x, y, 2 * bw + 3 * U, bh + 2 * U, U);
            for (int i = 0; i < 2; i++)
            {
                Rectangle r = new Rectangle(x + U + i * (bw + U), y + U, bw, bh);
                bool on = view == ids[i], hot = hoverId == "view:" + ids[i];
                Pix.Box(g, on ? Pix.C(0xF6C453) : (hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0)), r.X, r.Y, r.Width, r.Height);
                if (on) { Pix.Box(g, Pix.C(0xFBE7BA), r.X, r.Y, r.Width, U); Pix.Box(g, Pix.C(0xC8902C), r.X, r.Bottom - U, r.Width, U); }
                string[] art = i == 0 ? new string[] { "##.##", "##.##", ".....", "##.##", "##.##" } : new string[] { "#.###", ".....", "#.###", ".....", "#.###" };
                int aw = 5 * U, txw = Pix.TextW(names[i], segF), sx = r.X + (r.Width - aw - Sc(6) - txw) / 2;
                Pix.Mono(g, art, Pix.Ink, sx, r.Y + (r.Height - aw) / 2, U);
                Txt(g, names[i], segF, new Rectangle(sx + aw + Sc(6), r.Y, txw + 4, r.Height), on ? Pix.TextC : Sub, Pix.LeftMid);
                Hit("view:" + ids[i], r, true);
            }
        }

        // ---- 格子：3×3 ----
        void PaintGrid(Graphics g)
        {
            int W0 = Sc(600);
            Txt(g, "打開的，公仔會提醒你", labF, new Rectangle(0, Sc(66), W0, Sc(26)), Pix.C(0x7A4A22), Pix.Mid);
            int x0 = Sc(30), y0 = Sc(98), tw = Sc(172), th = Sc(132), gx = Sc(12), gy = Sc(8);
            for (int i = 0; i < SRC.Length; i++)
            {
                Rectangle r = new Rectangle(x0 + (i % 3) * (tw + gx), y0 + (i / 3) * (th + gy), tw, th);
                Tile(g, SRC[i], r);
            }
        }

        void Tile(Graphics g, Src s, Rectangle r)
        {
            bool on = On(s.Id), lk = Lock(s.Id), hot = hoverId == "tile:" + s.Id;
            Color edge = lk ? Pix.Dim : (on ? Pix.C(0x2F6E24) : Pix.Ink);
            Color fill = lk ? Pix.C(0xF3EADB) : (on ? (hot ? Pix.C(0xDFF0CC) : Pix.C(0xEAF6DC)) : (hot ? Pix.C(0xFFF3D6) : Paper));
            Color foot = lk ? Pix.C(0xE2D6C0) : (on ? Pix.C(0xBFE0A6) : Pix.C(0xEAD7B4));
            Pix.Round(g, edge, r.X, r.Y, r.Width, r.Height, U);
            Pix.Box(g, fill, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            Pix.Box(g, foot, r.X + U, r.Bottom - 4 * U, r.Width - 2 * U, 3 * U);
            Hit("tile:" + s.Id, r, true);
            Pix.Mono(g, new string[] { "#..", "##.", "###", "##.", "#.." }, Pix.C(0x8A6A4C), r.Right - Sc(16), r.Y + Sc(8), U);
            // 圖示＋名字（同一行，置中）
            string[] art; Dictionary<char, Color> pal;
            IconArt(s.Icon, out art, out pal);
            int iu = Math.Max(2, Sc(4)), iw = art[0].Length * iu, ih = art.Length * iu;
            if (lk) foreach (char ch in new List<char>(pal.Keys)) pal[ch] = Pix.Mix(pal[ch], Pix.C(0xF3EADB), 0.55);   // 鎖住：圖示變淡
            Pix.Art(g, art, pal, r.X + (r.Width - iw) / 2, r.Y + Sc(10) + (Sc(32) - ih) / 2, iu);
            string nm = s.Id == "claude" ? "Claude Code、Codex" : s.Name;
            Font nf = Pix.TextW(nm, tileNameF) > r.Width - Sc(16) ? labF : tileNameF;
            Txt(g, nm, nf, new Rectangle(r.X + Sc(4), r.Y + Sc(44), r.Width - Sc(8), Sc(22)), lk ? Pix.C(0x806A50) : Pix.TextC, Pix.Mid);
            if (lk)
            {
                Txt(g, "先打開", subF, new Rectangle(r.X, r.Y + Sc(74), r.Width, Sc(16)), MuteC, Pix.Mid);
                Txt(g, "GitLab 或 GitHub", subF, new Rectangle(r.X, r.Y + Sc(90), r.Width, Sc(16)), MuteC, Pix.Mid);
                return;
            }
            string st, kind, link;
            StateOf(s.Id, out st, out kind, out link);
            if (link != null)
            {
                string how = HowText(s.Id);
                int a = Pix.TextW(st, subF), b = Pix.TextW(how, subF), gap = Sc(8), sx = r.X + (r.Width - a - gap - b) / 2;
                Txt(g, st, subF, new Rectangle(sx, r.Y + Sc(68), a + 4, Sc(18)), KindC(kind), Pix.LeftMid);
                Rectangle lr = new Rectangle(sx + a + gap, r.Y + Sc(66), b + 2, Sc(22));
                Txt(g, how, subF, new Rectangle(lr.X, r.Y + Sc(68), b + 4, Sc(18)), LinkC, Pix.LeftMid);
                Pix.Box(g, LinkC, lr.X, r.Y + Sc(68) + Sc(16), b, Math.Max(1, U / 2));
                Hit("howto:" + s.Id, new Rectangle(sx - Sc(4), r.Y + Sc(63), a + gap + b + Sc(8), Sc(28)), true);
            }
            else Txt(g, st, subF, new Rectangle(r.X, r.Y + Sc(68), r.Width, Sc(18)), KindC(kind), Pix.Mid);
            Seg(g, s.Id, new Rectangle(r.X + (r.Width - Sc(84)) / 2, r.Bottom - Sc(44), Sc(84), Sc(30)));
        }

        // 關｜開
        void Seg(Graphics g, string id, Rectangle r)
        {
            bool on = On(id), dis = Lock(id) || Missing(id).Contains("tool"), hot = hoverId == "sw:" + id;
            Pix.Round(g, dis ? Pix.Dim : Pix.Ink, r.X, r.Y, r.Width, r.Height, U);
            int half = (r.Width - 3 * U) / 2;
            for (int i = 0; i < 2; i++)
            {
                Rectangle c = new Rectangle(r.X + U + i * (half + U), r.Y + U, half, r.Height - 2 * U);
                bool pick = (i == 1) == on;
                Color face = dis ? Pix.C(0xF3EADB) : (pick ? (i == 1 ? Pix.C(0x7CC25F) : Pix.C(0xE2D6C0)) : (hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0)));
                Pix.Box(g, face, c.X, c.Y, c.Width, c.Height);
                if (pick && !dis)
                {
                    Pix.Box(g, i == 1 ? Pix.C(0xB6E29E) : Pix.C(0xF1E8D8), c.X, c.Y, c.Width, U);
                    Pix.Box(g, i == 1 ? Pix.C(0x4E9A3A) : Pix.C(0xC9B79A), c.X, c.Bottom - U, c.Width, U);
                }
                Txt(g, i == 0 ? "關" : "開", segF, c, dis ? Pix.C(0x806A50) : (pick && i == 1 ? Pix.C(0x163D10) : (pick ? Pix.TextC : Sub)), Pix.Mid);
            }
            Hit("sw:" + id, r, true);
        }

        // ---- 清單：左邊來源、右邊要填的 ----
        void PaintList(Graphics g)
        {
            Rectangle p = PaneR();
            int x = Sc(30), wd = p.X - x + U;
            // 全部
            Rectangle all = new Rectangle(x, p.Y, wd - U, Sc(36));
            Tab(g, all, "all", "全部", null, false, "");
            int ty = p.Y + Sc(42), th = Sc(36);
            for (int i = 0; i < SRC.Length; i++)
            {
                Src s = SRC[i];
                Rectangle r = new Rectangle(x, ty + i * (th + U), wd, th);
                if (s.Id != sel) Tab(g, r, "tab:" + s.Id, s.Short, s.Icon, false, Dot(s.Id));
            }
            // 右邊的紙（先畫，選到的頁籤蓋上去接起來）
            Pix.Box(g, Pix.Ink, p.X, p.Y, p.Width, p.Height);
            Pix.Box(g, Paper, p.X + U, p.Y + U, p.Width - 2 * U, p.Height - 2 * U);
            for (int i = 0; i < SRC.Length; i++)
                if (SRC[i].Id == sel) Tab(g, new Rectangle(x, ty + i * (th + U), wd, th), "tab:" + SRC[i].Id, SRC[i].Short, SRC[i].Icon, true, Dot(SRC[i].Id));
            PaintPane(g, Find(sel), p);
        }

        string Dot(string id)
        {
            Src s = Find(id);
            if (pending.Contains(id)) return "warn";
            string st, kind, link; StateOf(id, out st, out kind, out link);
            if (v[s.Key] != "1" || Lock(id)) return kind == "bad" ? "bad" : "";
            return kind == "bad" ? "bad" : (kind == "warn" ? "warn" : (On(id) ? "on" : ""));
        }

        void Tab(Graphics g, Rectangle r, string id, string name, string icon, bool selTab, string dot)
        {
            bool hot = hoverId == id;
            if (selTab)
            {
                Pix.Box(g, Pix.Ink, r.X, r.Y, r.Width, r.Height);
                Pix.Box(g, Paper, r.X + U, r.Y + U, r.Width, r.Height - 2 * U);
                Pix.Box(g, Pix.C(0xF6C453), r.X + U, r.Y + U, 2 * U, r.Height - 2 * U);
            }
            else
            {
                Pix.Box(g, Pix.Ink, r.X, r.Y, r.Width, r.Height);
                Pix.Box(g, hot ? Pix.C(0xFFF3D6) : Pix.C(0xF3E6CC), r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
                Pix.Box(g, Pix.C(0xE2CFAE), r.X + U, r.Bottom - 2 * U, r.Width - 2 * U, U);
            }
            int tx = r.X + Sc(10);
            if (icon != null)
            {
                string[] art; Dictionary<char, Color> pal; IconArt(icon, out art, out pal);
                Pix.Art(g, art, pal, tx, r.Y + (r.Height - art.Length * U) / 2, U);
                tx += art[0].Length * U + Sc(8);
            }
            else
            {
                Pix.Mono(g, new string[] { "##.##", "##.##", ".....", "##.##", "##.##" }, Pix.Ink, tx, r.Y + (r.Height - 5 * U) / 2, U);
                tx += 5 * U + Sc(8);
            }
            Txt(g, name, labF, new Rectangle(tx, r.Y, r.Right - tx - Sc(20), r.Height), Pix.TextC, Pix.LeftMid);
            if (icon != null)
            {
                int ds = 5 * U, dx = r.Right - Sc(14) - ds, dy = r.Y + (r.Height - ds) / 2;
                Color dc = dot == "on" ? Pix.C(0x5FB04A) : (dot == "warn" ? Pix.C(0xE0A03A) : (dot == "bad" ? Pix.C(0xC95454) : Paper));
                Pix.Round(g, dot == "" ? Pix.C(0x8A6A4C) : Pix.Ink, dx, dy, ds, ds, U);
                Pix.Box(g, dc, dx + U, dy + U, ds - 2 * U, ds - 2 * U);
                if (dot == "bad") Pix.Box(g, Color.White, dx + 2 * U, dy + 2 * U, U, U);
                if (dot == "warn") Pix.Box(g, Pix.Ink, dx + 2 * U, dy + 2 * U, U, U);
            }
            Hit(id, r, true);
        }

        void PaintPane(Graphics g, Src s, Rectangle p)
        {
            int x = p.X + Sc(22), y = p.Y + Sc(18), right = p.Right - Sc(22);
            string[] art; Dictionary<char, Color> pal; IconArt(s.Icon, out art, out pal);
            int iu = Math.Max(2, Sc(3));
            Pix.Art(g, art, pal, x, y + (Sc(30) - art.Length * iu) / 2, iu);
            Txt(g, s.Name, nameF, new Rectangle(x + art[0].Length * iu + Sc(10), y, Sc(220), Sc(30)), Pix.TextC, Pix.LeftMid);
            if (!Lock(s.Id)) Seg(g, s.Id, new Rectangle(right - Sc(84), y, Sc(84), Sc(30)));
            // 一句狀態
            int ly = p.Y + Sc(58);
            string st, kind, link; StateOf(s.Id, out st, out kind, out link);
            string lead = LeadText(s.Id);
            Color lc = pending.Contains(s.Id) || kind == "warn" ? WarnC : (kind == "bad" ? BadC : (kind == "ok" && lead == st ? OkC : MuteC));
            int lw = Pix.TextW(lead, labF);
            Txt(g, lead, labF, new Rectangle(x + Sc(28), ly, lw + 4, Sc(22)), lc, Pix.LeftMid);
            if (link != null)
            {
                string how = HowText(s.Id); int b = Pix.TextW(how, labF);
                Rectangle lr = new Rectangle(x + Sc(28) + lw + Sc(10), ly, b + 2, Sc(22));
                Txt(g, how, labF, lr, LinkC, Pix.LeftMid);
                Pix.Box(g, LinkC, lr.X, lr.Y + Sc(19), b, Math.Max(1, U / 2));
                Hit("howto:" + s.Id, lr, true);
            }
            bool show = v[s.Key] == "1" || pending.Contains(s.Id);
            if (s.Id == "claude" || (show && FILL.ContainsKey(s.Id)))
            {
                for (int dx = x; dx + U <= right; dx += 3 * U) Pix.Box(g, Pix.C(0xD8BF94), dx, p.Y + Sc(90), U, U);
                PaintForm(g, s, p, x, right);
            }
            // 提醒會像這樣
            int sy = p.Bottom - Sc(86);
            string say = s.Id == "meet" ? (v["meet_before"].Trim() == "" ? "5" : v["meet_before"].Trim()) + " 分鐘後開會" : s.Say;
            Bitmap pic = w.WorkPalPic(Math.Max(3, (int)Math.Round(3 * d)));
            int pw = pic != null ? pic.Width : 0, ph = pic != null ? pic.Height : 0;
            int bw = Pix.TextW(say, labF) + Sc(20), bh = Sc(28), bx = right - pw - Sc(8) - bw, byy = p.Bottom - Sc(6) - ph / 2 - bh / 2 - Sc(4);
            if (pic == null) byy = sy + Sc(26);
            Txt(g, "提醒會像這樣", subF, new Rectangle(x, byy, Sc(120), bh), Sub, Pix.LeftMid);   // 跟泡泡同一行
            Pix.Round(g, Pix.C(0x7A4A22), bx, byy, bw, bh, U);
            Pix.Box(g, Color.White, bx + U, byy + U, bw - 2 * U, bh - 2 * U);
            for (int i = 0; i < 4; i++) Pix.Box(g, Pix.C(0x7A4A22), bx + bw - U + i * U, byy + bh / 2 - (4 - i) * U / 2, U, (4 - i) * U);
            Txt(g, say, labF, new Rectangle(bx, byy, bw, bh), Pix.TextC, Pix.Mid);
            if (pic != null) g.DrawImageUnscaled(pic, right - pw, p.Bottom - ph - Sc(6));
        }

        // 沒裝＝怎麼裝；裝了沒登入＝怎麼登入
        string HowText(string id) { return Tool(id) == "nologin" ? "怎麼登入" : "怎麼裝"; }
        string HowUrl(string id)
        {
            bool login = Tool(id) == "nologin";
            if (id == "github") return login ? "https://cli.github.com/manual/gh_auth_login" : HowGh;
            return login ? "https://gitlab.com/gitlab-org/cli/-/blob/main/docs/source/auth/login.md" : HowGlab;
        }
        // 紅色那格：空的＝要先填；填了但不對＝說哪裡不對
        string BadText()
        {
            foreach (string k in bad)
            {
                TextBox t;
                if (!boxes.TryGetValue(k, out t) || t.Text.Trim() == "") continue;
                switch (k)
                {
                    case "meet_url": return "紅色那格不是網址";
                    case "jira_email": return "紅色那格不是信箱";
                    case "vpn_host": return "紅色那格不是主機名稱";
                    case "worklog_dir": return "紅色那格的資料夾找不到";
                    case "meet_before": return "紅色那格要填 1 到 120";
                }
            }
            return "要先填紅色的格子";
        }

        string LeadText(string id)
        {
            Src s = Find(id);
            string st, kind, link; StateOf(id, out st, out kind, out link);
            if (pending.Contains(id) && Missing(id).Count > 0) return bad.Count > 0 ? BadText() : FILL[id];
            if (bad.Count > 0 && FILL.ContainsKey(id)) return BadText();
            if (link != null || kind == "bad") return st;
            if (Lock(id)) return st;
            if (kind == "warn" && NEED.ContainsKey(id)) return NEED[id];
            if (s.Sub != null) return s.Sub;
            return kind == "ok" ? st : "";
        }

        void PaintForm(Graphics g, Src s, Rectangle p, int x, int right)
        {
            switch (s.Id)
            {
                case "claude":
                    {
                        int ay = FieldY(0);
                        Pix.Mono(g, advOpen ? new string[] { "#####", ".###.", "..#.." } : new string[] { "#..", "##.", "###", "##.", "#.." }, LinkC, x, ay + (Sc(22) - 5 * U) / 2, U);
                        Rectangle ar = new Rectangle(x, ay, Pix.TextW("別的資料夾", labF) + Sc(18), Sc(22));
                        Txt(g, "別的資料夾", labF, new Rectangle(x + Sc(14), ay, ar.Width, Sc(22)), LinkC, Pix.LeftMid);
                        Hit("adv", ar, true);
                        if (advOpen) { Field(g, 1, "Claude 資料夾", "claude_dir", 0, @"\\wsl$\Ubuntu\home\me\.claude"); Field(g, 2, "Codex 資料夾", "codex_dir", 0, @"\\wsl$\Ubuntu\home\me\.codex"); }
                    }
                    break;
                case "jira":
                    Field(g, 0, "網站", "jira_site", 0, "yourteam.atlassian.net");
                    Field(g, 1, "信箱", "jira_email", 0, "you@yourteam.com");
                    Field(g, 2, "API token", "token", 0, w.HasJiraToken() ? "已經存了，要換才貼" : "貼上 token");
                    {
                        int ny = FieldY(3) - Sc(4);
                        Txt(g, "token 只存在這台電腦", subF, new Rectangle(x, ny, Sc(200), Sc(20)), Sub, Pix.LeftMid);
                        string how = "去建立 token"; int b = Pix.TextW(how, subF);
                        Rectangle lr = new Rectangle(right - b, ny, b + 2, Sc(22));
                        Txt(g, how, subF, new Rectangle(lr.X, ny, b + 4, Sc(20)), LinkC, Pix.LeftMid);
                        Pix.Box(g, LinkC, lr.X, ny + Sc(17), b, Math.Max(1, U / 2));
                        Hit("howto:jira", lr, true);
                    }
                    break;
                case "meet":
                    Field(g, 0, "行事曆網址", "meet_url", 0, "https:// 或 webcal://");
                    {
                        int ry = FieldY(1) + Sc(6);
                        Txt(g, "開會前", labF, new Rectangle(x, ry, Sc(56), Sc(28)), Pix.TextC, Pix.LeftMid);
                        Frame(g, new Rectangle(x + Sc(56), ry, Sc(56), Sc(28)), "meet_before");
                        stops.Add("tbpos:meet_before");
                        Txt(g, "分鐘提醒", labF, new Rectangle(x + Sc(122), ry, Sc(100), Sc(28)), Pix.TextC, Pix.LeftMid);
                        int cy = ry + Sc(42), cs = Sc(20);
                        bool q = v["meet_quiet"] == "1";
                        Pix.Round(g, Pix.Ink, x, cy, cs, cs, U);
                        Pix.Box(g, q ? Pix.C(0x5FB04A) : Paper, x + U, cy + U, cs - 2 * U, cs - 2 * U);
                        if (q) Pix.Mono(g, Pix.CHECK, Color.White, x + (cs - 5 * U) / 2, cy + (cs - 5 * U) / 2, U);
                        Txt(g, "開會時自動安靜", labF, new Rectangle(x + cs + Sc(10), cy - Sc(2), Sc(160), cs + Sc(4)), Pix.TextC, Pix.LeftMid);
                        Hit("quiet", new Rectangle(x, cy, cs + Sc(10) + Pix.TextW("開會時自動安靜", labF), cs), true);
                    }
                    break;
                case "rain": Field(g, 0, "地點", "rain_place", 0, "台北 或 25.03,121.56"); break;
                case "net": Field(g, 0, "主機", "vpn_host", 0, "intranet.example.com"); break;
                case "worklog":
                    Field(g, 0, "資料夾", "worklog_dir", Sc(88), @"C:\Users\me\Documents\日誌");
                    {
                        Rectangle fb = FieldBox(0, 0);
                        Rectangle br = new Rectangle(fb.Right - Sc(80), fb.Y, Sc(80), fb.Height);
                        SmallButton(g, "pickdir", "選資料夾", br);
                    }
                    break;
            }
        }

        // 一格：上面一行字、下面輸入框的像素框（空的時候畫提示字）
        void Field(Graphics g, int i, string label, string key, int cut, string ph)
        {
            Rectangle r = FieldBox(i, 0);
            if (cut > 0) r.Width -= cut;
            Txt(g, label, labF, new Rectangle(r.X, FieldY(i) - Sc(2), Sc(200), Sc(20)), bad.Contains(key) ? BadC : Pix.TextC, Pix.LeftMid);
            Frame(g, r, key);
            stops.Add("tbpos:" + key);
            TextBox t = boxes[key];
            Cue(t, ph);   // 空的時候的提示字：交給輸入框自己畫（EM_SETCUEBANNER），離屏時 PaintTo 畫
        }

        void Frame(Graphics g, Rectangle r, string key)
        {
            bool isBad = bad.Contains(key), foc = focusStop == "tb:" + key;
            Pix.Round(g, isBad ? BadC : (foc ? Pix.Ink : Pix.C(0x8A6A4A)), r.X, r.Y, r.Width, r.Height, U);
            if (foc) Pix.Round(g, Pix.Ink, r.X - U, r.Y - U, r.Width + 2 * U, r.Height + 2 * U, U);
            Pix.Box(g, isBad ? Pix.C(0xFDECEA) : Paper, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            Pix.Box(g, Pix.C(0xEAD7B4), r.X + U, r.Y + U, r.Width - 2 * U, U);
        }

        void SmallButton(Graphics g, string id, string text, Rectangle r)
        {
            bool hot = hoverId == id;
            Pix.Round(g, Pix.Ink, r.X, r.Y, r.Width, r.Height, U);
            Pix.Box(g, hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0), r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            Pix.Box(g, Pix.C(0xDCC6A2), r.X + U, r.Bottom - 2 * U, r.Width - 2 * U, U);
            Txt(g, text, subF, new Rectangle(r.X, r.Y, r.Width, r.Height - U), Pix.TextC, Pix.Mid);
            Hit(id, r, true);
        }

        void Button(Graphics g, string id, string text, Rectangle r, bool main)
        {
            bool hot = hoverId == id;
            Color face = main ? (hot ? Pix.C(0xFFD36A) : Pix.C(0xF6C453)) : (hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0));
            Color shade = main ? Pix.C(0xC8902C) : Pix.C(0xDCC6A2);
            Pix.Round(g, Pix.Ink, r.X, r.Y, r.Width, r.Height, U);
            Pix.Box(g, face, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            Pix.Box(g, shade, r.X + U, r.Bottom - 3 * U, r.Width - 2 * U, 2 * U);
            Pix.Box(g, Pix.Mix(face, Color.White, 0.6), r.X + 2 * U, r.Y + U, r.Width - 4 * U, U);
            Txt(g, text, btnF, new Rectangle(r.X, r.Y, r.Width, r.Height - 2 * U), Pix.TextC, Pix.Mid);
            Hit(id, r, true);
        }

        // ---- 圖示（8×8 以內的像素圖）----
        static void IconArt(string n, out string[] art, out Dictionary<char, Color> pal)
        {
            pal = new Dictionary<char, Color>();
            pal['k'] = Pix.Ink;
            switch (n)
            {
                case "claude": art = new string[] { "kkkkkkkk", "kddddddk", "kdgddddk", "kddgdddk", "kdgdggdk", "kddddddk", "kkkkkkkk" }; pal['d'] = Pix.C(0x5A4632); pal['g'] = Pix.C(0xF4A06A); break;
                case "jira": art = new string[] { "kkkkkkkk", "kbbbbbbk", "kbwwwwbk", ".kbbbbk.", "kbwwwbbk", "kbbbbbbk", "kkkkkkkk" }; pal['b'] = Pix.C(0x6E9BD8); pal['w'] = Pix.C(0xE4EEFA); break;
                case "gitlab": art = new string[] { ".k...k.", "kpk.kpk", ".k...k.", ".k..k..", ".k.k...", ".kk....", "kpk....", ".k....." }; pal['p'] = Pix.C(0xE2763A); break;
                case "github": art = new string[] { ".k...k.", "kpk.kpk", ".k...k.", ".k..k..", ".k.k...", ".kk....", "kpk....", ".k....." }; pal['p'] = Pix.C(0x7A8696); break;
                case "tag": art = new string[] { "kkkkk...", "kyyyyk..", "kywyyyk.", "kyyyyyyk", "kyyyyyk.", "kyyyyk..", "kkkkk..." }; pal['y'] = Pix.C(0xF0C24E); pal['w'] = Pix.C(0xFFF6E4); break;
                case "meet": art = new string[] { ".k...k..", "kkkkkkkk", "krrrrrrk", "kwwwwwwk", "kwkwkwwk", "kwwwwwwk", "kwkwwwwk", "kkkkkkkk" }; pal['r'] = Pix.C(0xE07856); pal['w'] = Pix.C(0xFFFDF7); break;
                case "rain": art = new string[] { "...kkk..", ".kkwwwk.", "kwwwwwwk", "kwwwwwwk", ".kkkkkk.", ".b..b..b", "b..b..b." }; pal['w'] = Pix.C(0xE9EEF5); pal['b'] = Pix.C(0x4F86C9); break;
                case "net": art = new string[] { "..k..k..", "..k..k..", ".kkkkkk.", ".kggggk.", ".kggggk.", "..kggk..", "...kk...", "...k...." }; pal['g'] = Pix.C(0x9FC3E6); break;
                default: art = new string[] { "kkk.....", "kyyk....", "kkkkkkkk", "kyyyyyyk", "kyyyyyyk", "kyyyyyyk", "kkkkkkkk" }; pal['y'] = Pix.C(0xF0C24E); break;   // folder
            }
        }
    }
}
