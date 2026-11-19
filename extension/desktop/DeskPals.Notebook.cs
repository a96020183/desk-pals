// Desk Pals：小本子（待辦／今天做了／筆記）。446 寬、停在公仔櫃左邊；上緣三個索引頁籤，「攤開」變成左右兩頁（待辦＋筆記｜今天做了）。
// 資料、合併、要貼出去的字都在 DeskPals.NotebookData.cs；這支只管畫、點、打字、跟 World 接（學校行事曆、泡泡、剪貼簿、pipe）。
// 畫法跟像素選單、設定視窗同一套（Pix.*、木框、奶油色面板、銅牌、像素按鈕），字型 Microsoft JhengHei UI。
// 打字用真的 TextBox／RichTextBox（中文輸入法才打得了），其他全部自己畫；離屏測試（DESKPALS_OFFSCREEN=1）時字也自己畫，snap 才看得到。
// 刻意寫成 C# 5（不用 $"" / ?. / => 成員 / nameof）；using 放在 namespace 裡面（desk-pals.ps1 會把檔案接在一起編譯）。
//
// 掛在 DeskPals.cs 的地方（都只有一行，標 // 小本子）：HouseMenu「工作」→「小本子…」、公仔右鍵 →「小本子…」、OnMsg 的 default → NbMsg()、Snap → NbSnap()。
// pipe 指令（測試用的只在離屏模式）：
//   nb-open [todo|done|note]、nb-close、nb-info（現在畫了什麼）、nb-clip（剛剛「複製」了什麼字，不碰真的剪貼簿）
//   nb-text simple|detail|links（現在會貼出去的字）、nb-act <動作> [參數]（跟滑鼠點一樣，見 Do()）、nb-click <x> <y>、nb-hover <x> <y>
//   nb-type todo|done|edit|note <字…>（打字）、nb-key todo|done|edit enter|esc、nb-key alt-up|alt-down
//   時間用 study-clock（跟讀書小幫手同一個假時鐘）
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.Drawing;
    using System.Drawing.Drawing2D;
    using System.Drawing.Imaging;
    using System.Drawing.Text;
    using System.IO;
    using System.Runtime.InteropServices;
    using System.Text;
    using System.Web.Script.Serialization;
    using System.Windows.Forms;

    // 筆記用的紙：固定 28px 一行（RichEdit 的固定行高），每行底下一條線
    class NbNoteBox : RichTextBox
    {
        [StructLayout(LayoutKind.Sequential)]
        struct PARAFORMAT2
        {
            public int cbSize; public uint dwMask; public short wNumbering, wReserved; public int dxStartIndent, dxRightIndent, dxOffset;
            public short wAlignment, cTabCount;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)] public int[] rgxTabs;
            public int dySpaceBefore, dySpaceAfter, dyLineSpacing; public short sStyle; public byte bLineSpacingRule, bOutlineLevel;
            public short wShadingWeight, wShadingStyle, wNumberingStart, wNumberingStyle, wNumberingTab, wBorderSpace, wBorderWidth, wBorders;
        }
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, ref PARAFORMAT2 p);
        public int LineH = 28;
        public Color LineC = Pix.C(0xEFE0C4);
        public NbNoteBox()
        {
            BorderStyle = BorderStyle.None;
            ScrollBars = RichTextBoxScrollBars.Vertical;
            DetectUrls = false;
            ShortcutsEnabled = true;
        }
        protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); Spacing(); }
        // 整篇固定行高（新打的字照前一段的格式，貼上的也是）
        public void Spacing()
        {
            if (!IsHandleCreated) return;
            PARAFORMAT2 p = new PARAFORMAT2();
            p.cbSize = Marshal.SizeOf(typeof(PARAFORMAT2));
            p.rgxTabs = new int[32];
            p.dwMask = 0x100;                        // PFM_LINESPACING
            p.bLineSpacingRule = 4;                  // 固定（twips）
            using (Graphics g = CreateGraphics()) p.dyLineSpacing = (int)Math.Round(LineH * 1440.0 / g.DpiY);
            int s = SelectionStart, l = SelectionLength;
            SelectAll();
            SendMessage(Handle, 0x447, IntPtr.Zero, ref p);   // EM_SETPARAFORMAT
            Select(s, l);
        }
        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
            if (m.Msg == 0x000F) Lines2();           // WM_PAINT：字畫完再畫線
        }
        void Lines2()
        {
            try
            {
                int y0 = TextLength > 0 ? GetPositionFromCharIndex(0).Y : 1;
                using (Graphics g = CreateGraphics())
                using (Pen pen = new Pen(LineC, 1))
                    for (int y = y0 + LineH - 2; y < ClientSize.Height; y += LineH) if (y >= 0) g.DrawLine(pen, 0, y, ClientSize.Width, y);
            }
            catch { }
        }
        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Invalidate(); }
        protected override void OnVScroll(EventArgs e) { base.OnVScroll(e); Invalidate(); }
        // 只貼純文字（不帶別的地方的字型、顏色）
        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (keyData == (Keys.Control | Keys.V) || keyData == (Keys.Shift | Keys.Insert))
            {
                try { if (Clipboard.ContainsText()) { SelectedText = Clipboard.GetText().Replace("\r\n", "\n"); Spacing(); } } catch { }
                return true;
            }
            return base.ProcessCmdKey(ref msg, keyData);
        }
    }

    class NotebookForm : Form
    {
        // ---- 顏色（mockup：C:\tmp\dp\worklog-ui\v5-tabs-b）----
        static readonly Color CText = Pix.C(0x4A3010), CSub = Pix.C(0x6B5238), CTime = Pix.C(0x8F6B44), COk = Pix.C(0x2F7A22), COkHot = Pix.C(0x24661A),
            CBad = Pix.C(0xB8433F), CPh = Pix.C(0x8A6A4C), COff = Pix.C(0x8C7B62), CGh = Pix.C(0x7A4A22), CGhLine = Pix.C(0xE2CFAE), CBar = Pix.C(0xF7EBD2),
            CBarEdge = Pix.C(0xD8BF94), CPaper = Pix.C(0xFFFDF7), CNote = Pix.C(0x3A2A18), CTabText = Pix.C(0x5A3E22), CField = Pix.C(0xC9B08A), CBtn = Pix.C(0xFFFBF0);
        static readonly Color[] TabC = { Pix.C(0xF6C453), Pix.C(0xA9D394), Pix.C(0xF3B3BE) }, TabBg = { Pix.C(0xF9E2A4), Pix.C(0xD5EAC8), Pix.C(0xF8D5DB) };
        static readonly string[] TabKey = { "todo", "done", "note" }, TabName = { "待辦", "今天做了", "筆記" };
        static readonly Color KEY = Color.FromArgb(255, 0, 255);

        // ---- 像素小圖（8×8 以內；k＝深色描邊）----
        static readonly string[] ICLAUDE = { "kkkkkkkk", "kddddddk", "kdgddddk", "kddgdddk", "kdgdggdk", "kddddddk", "kkkkkkkk" };
        static readonly string[] IJIRA = { "kkkkkkkk", "kbbbbbbk", "kbwwwwbk", ".kbbbbk.", "kbwwwbbk", "kbbbbbbk", "kkkkkkkk" };
        static readonly string[] IMR = { ".k...k.", "kpk.kpk", ".k...k.", ".k..k..", ".k.k...", ".kk....", "kpk....", ".k....." };
        static readonly string[] IMEET = { ".k...k..", "kkkkkkkk", "krrrrrrk", "kwwwwwwk", "kwkwkwwk", "kwwwwwwk", "kwkwwwwk", "kkkkkkkk" };
        static readonly string[] ICLASS = { "kkkkkkk.", "kggggggk", "kgwwwwgk", "kggggggk", "kggggggk", "kggggggk", "kwwwwwwk", "kkkkkkkk" };
        static readonly string[] IHW = { "kkkkk...", "kwwwwk..", "kwkkwwk.", "kwwwwwwk", "kwkkkkwk", "kwwwwwwk", "kwkkkwwk", "kkkkkkkk" };
        static readonly string[] ICAL = { ".k...k.", "kkkkkkk", "kwwwwwk", "kwkwkwk", "kwwwwwk", "kkkkkkk" };
        static readonly string[] IGEAR = { ".k.k.", "kkkkk", "kk.kk", "kkkkk", ".k.k." };
        static readonly string[] IPLUS = { "..k..", "..k..", "kkkkk", "..k..", "..k.." };
        static readonly string[] ILEFT = { "..k", ".kk", "kkk", ".kk", "..k" }, IRIGHT = { "k..", "kk.", "kkk", "kk.", "k.." }, IDOWN = { "kkkkk", ".kkk.", "..k.." };
        static readonly string[] IX = { "k...k", ".k.k.", "..k..", ".k.k.", "k...k" };
        static readonly string[] IGRIP = { "k.k", "...", "k.k", "...", "k.k" };

        readonly World w;
        readonly double d;
        readonly int U;
        readonly Font fPlate, fBody, fWord, fSmall, fBar, fBtn, fBtnS, fNote, fPv, fPvB, fField;
        public bool VVisible;

        // ---- 狀態 ----
        public string Tab = "done", LastTab = "done";
        public bool Spread, Preview, Links;
        public string PvKind = "detail";
        public DateTime Day;
        string copied = ""; double copiedUntil;
        List<NbThing> things = new List<NbThing>();
        List<NbTodo> todos = new List<NbTodo>();
        List<NbFact> jira = new List<NbFact>();
        NbEdits edits = new NbEdits();
        string savedAt = "";
        bool noteDirty; double noteSaveAt;
        string logStamp = "";
        double nextRefresh;
        // 剛勾掉的待辦：先留在原地畫刪除線＋「▶ 今天做了」，一下子再消失（這段時間再點一次＝取消）
        class Just { public NbTodo T; public int Index; public string LogId; public double Until; }
        readonly List<Just> justDone = new List<Just>();
        // 滑鼠、編輯、拖曳
        string hoverThing = "", hoverTodo = "", hoverAct = "", editThing = "", editTodo = "", lastTodo = "";
        string dragTodo = ""; int dragY, dragStartY; bool dragging;
        readonly Dictionary<string, int> scroll = new Dictionary<string, int>();
        readonly Dictionary<string, int> contentH = new Dictionary<string, int>();
        readonly Dictionary<string, Rectangle> clipR = new Dictionary<string, Rectangle>();
        // 待辦的期限（新增那一行右邊的小日曆）
        bool duePick; DateTime dueDay = DateTime.MinValue; int dueMin = -1;
        class Hit { public string Act, Arg; public Rectangle R; public string Hover; }
        readonly List<Hit> hits = new List<Hit>();
        readonly Dictionary<string, Rectangle> todoRows = new Dictionary<string, Rectangle>();
        public readonly List<string> Drawn = new List<string>();   // 測試用（nb-info）：這次畫了哪些東西

        // 打字的地方
        readonly TextBox tbTodo, tbDone, tbEdit;
        readonly NbNoteBox note;
        Rectangle rTodo, rDone, rEdit, rNote;   // 這次畫出來的位置（看不到＝Empty）
        string noteFor = "";                    // 筆記框現在是哪一天的
        readonly Timer timer = new Timer();

        public NotebookForm(World w)
        {
            this.w = w;
            d = w.S / 4.0;
            U = Math.Max(2, (int)Math.Round(2 * d));
            Text = "小本子";
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = true;
            StartPosition = FormStartPosition.Manual;
            BackColor = KEY; TransparencyKey = KEY;      // 左邊的線圈凸出木框外面
            KeyPreview = true;
            SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            string jh = "Microsoft JhengHei UI";
            // 自己畫的字：像素大小（跟 mockup 一樣 14.7／13.3／11.3／12px），用 GDI+ 反鋸齒畫（見 DT）
            fPlate = Px(jh, 14.667f * (float)d, FontStyle.Bold);
            fBody = Px(jh, 14.667f * (float)d, FontStyle.Bold);
            fWord = Px(jh, 13.333f * (float)d, FontStyle.Bold);
            fSmall = Px(jh, 11.333f * (float)d, FontStyle.Bold);
            fBar = Px(jh, 12f * (float)d, FontStyle.Bold);
            fBtn = Px(jh, 13.333f * (float)d, FontStyle.Bold);
            fBtnS = Px(jh, 11.333f * (float)d, FontStyle.Bold);
            fNote = Px(jh, 14.667f * (float)d, FontStyle.Regular);
            fPv = Px(jh, 13.333f * (float)d, FontStyle.Regular);
            fPvB = Px(jh, 13.333f * (float)d, FontStyle.Bold);
            fField = Px(jh, 13.333f * (float)d, FontStyle.Bold);
            // 真的打字框（TextBox／RichTextBox）用 pt 字型，跟系統縮放走
            tbTodo = MakeBox(new Font(jh, 10f, FontStyle.Bold), "寫一件要做的事，按 Enter");
            tbDone = MakeBox(new Font(jh, 10f, FontStyle.Bold), "補一件做過的事，按 Enter");
            tbEdit = MakeBox(new Font(jh, 11f, FontStyle.Bold), "");
            note = new NbNoteBox();
            note.Font = new Font(jh, 11f, FontStyle.Regular); note.BackColor = CPaper; note.ForeColor = CNote; note.LineH = Sc(28); note.Visible = false;
            note.TextChanged += delegate { if (note.Tag == null) { noteDirty = true; noteSaveAt = w.Now + 0.7; } };
            note.LostFocus += delegate { Invalidate(); };
            Controls.Add(note);
            tbTodo.KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; Key("todo", "enter"); } else if (e.KeyCode == Keys.Escape) { e.SuppressKeyPress = true; Key("todo", "esc"); } };
            tbDone.KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; Key("done", "enter"); } else if (e.KeyCode == Keys.Escape) { e.SuppressKeyPress = true; Key("done", "esc"); } };
            tbEdit.KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; Key("edit", "enter"); } else if (e.KeyCode == Keys.Escape) { e.SuppressKeyPress = true; Key("edit", "esc"); } };
            tbEdit.LostFocus += delegate { if (editThing != "" || editTodo != "") Key("edit", "enter"); };
            tbTodo.TextChanged += delegate { Invalidate(); };
            tbDone.TextChanged += delegate { Invalidate(); };
            timer.Interval = 250;
            timer.Tick += delegate { Tick(); };
            timer.Start();
            Day = w.NbNow().Date;
            FormClosed += delegate { timer.Stop(); SaveNote(); w.NbClosed(this); };
        }

        TextBox MakeBox(Font f, string cue)
        {
            TextBox t = new TextBox();
            t.BorderStyle = BorderStyle.None; t.Font = f; t.BackColor = CPaper; t.ForeColor = CText; t.Visible = false;
            t.Tag = cue;
            t.HandleCreated += delegate { if (cue != "") SendMessage(t.Handle, 0x1501, new IntPtr(1), cue); };   // EM_SETCUEBANNER（打字時也留著提示）
            Controls.Add(t);
            return t;
        }
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, string l);

        int Sc(int v) { return (int)Math.Round(v * d); }
        int OV { get { return Sc(10); } }                  // 左邊凸出去的線圈
        public int FrameW { get { return Sc(Spread ? 760 : 446); } }
        public int FrameH { get { return Sc(Spread ? 636 : 670); } }
        public Size Want { get { return new Size(FrameW + OV, FrameH); } }

        // ---- 離屏測試模式：不真的顯示，snap 時畫到虛擬螢幕上 ----
        protected override void SetVisibleCore(bool value)
        {
            if (App.Offscreen) { VVisible = value; base.SetVisibleCore(false); return; }
            base.SetVisibleCore(value);
        }
        public void PaintTo(Graphics g)
        {
            Size cs = ClientSize;
            if (cs.Width <= 0 || cs.Height <= 0) return;
            using (Bitmap b = new Bitmap(cs.Width, cs.Height, PixelFormat.Format24bppRgb))
            {
                using (Graphics gg = Graphics.FromImage(b)) OnPaint(new PaintEventArgs(gg, new Rectangle(0, 0, cs.Width, cs.Height)));
                b.MakeTransparent(KEY);
                g.DrawImageUnscaled(b, Left, Top);
            }
        }

        // ================= 資料 =================
        string Dir { get { return Nb.Dir(World.DataDir); } }
        bool IsToday { get { return Day == w.NbNow().Date; } }

        public void Reload()
        {
            List<NbFact> facts = Nb.ReadLog(Dir, Day);
            Nb.AddClasses(facts, w.NbClasses(Day));
            edits = Nb.LoadEdits(Dir, Day);
            things = Nb.Build(facts, edits);
            todos = w.NbTodos();
            jira = Nb.JiraTodos(Dir);
            logStamp = Stamp();
            if (noteFor != Nb.Ymd(Day)) LoadNote();
            Invalidate();
        }
        string Stamp()
        {
            try
            {
                FileInfo a = new FileInfo(Nb.LogPath(Dir, Day)), b = new FileInfo(Nb.TodoPath(Dir));
                return (a.Exists ? a.LastWriteTimeUtc.Ticks + ":" + a.Length : "-") + "|" + (b.Exists ? b.LastWriteTimeUtc.Ticks + ":" + b.Length : "-") + "|" + w.NbSchoolStamp();
            }
            catch { return ""; }
        }

        void LoadNote()
        {
            SaveNote();
            noteFor = Nb.Ymd(Day);
            note.Tag = "loading";
            note.Text = Nb.ReadFile(Nb.NotePath(Dir, Day)).Replace("\r\n", "\n");
            note.Tag = null;
            note.Spacing();
            noteDirty = false;
            savedAt = "";
            try { FileInfo fi = new FileInfo(Nb.NotePath(Dir, Day)); if (fi.Exists && note.Text != "") savedAt = Nb.Hm(fi.LastWriteTime); } catch { }
        }
        public void SaveNote()
        {
            if (!noteDirty || noteFor == "") return;
            noteDirty = false;
            DateTime day;
            if (!DateTime.TryParseExact(noteFor, "yyyy-MM-dd", Nb.Inv, System.Globalization.DateTimeStyles.None, out day)) return;
            string path = Nb.NotePath(Dir, day), text = note.Text.Replace("\r\n", "\n");
            if (text.Trim() == "") { try { if (File.Exists(path)) File.Delete(path); } catch { } savedAt = ""; }
            else { Nb.WriteFile(path, text); savedAt = Nb.Hm(w.NbNow()); }
            Invalidate();
        }

        void Tick()
        {
            double now = w.Now;
            if (noteDirty && now >= noteSaveAt) SaveNote();
            if (copied != "" && now >= copiedUntil) { copied = ""; Invalidate(); }
            bool drop = false;
            for (int i = justDone.Count - 1; i >= 0; i--) if (now >= justDone[i].Until) { justDone.RemoveAt(i); drop = true; }
            if (drop) Invalidate();
            if (now >= nextRefresh)
            {
                nextRefresh = now + 3;
                if (Stamp() != logStamp && editThing == "" && editTodo == "" && !dragging) Reload();
            }
        }

        // ================= 動作（滑鼠、鍵盤、測試都走這裡）=================
        public void Do(string act, string arg)
        {
            switch (act)
            {
                case "close": Close(); return;
                case "tab": if (Array.IndexOf(TabKey, arg) >= 0) { Tab = arg; LastTab = arg; Preview = false; duePick = false; EndEdit(true); w.NbSaveUi(this); FocusFor(); } break;
                case "spread":
                    EndEdit(true);
                    if (!Spread) { LastTab = Tab; Spread = true; } else { Spread = false; Tab = LastTab; }
                    duePick = false;
                    w.NbPlace(this);
                    w.NbSaveUi(this);
                    break;
                case "prev": GoDay(Day.AddDays(-1)); return;
                case "next": if (!IsToday) GoDay(Day.AddDays(1)); return;
                case "today": GoDay(w.NbNow().Date); return;
                case "sources": w.OpenWorkSettings(); return;
                case "connect": w.OpenWorkSettings(arg); return;   // 直接打開那個來源（學校行事曆＝讀書小幫手設定）
                case "pv": Preview = !Preview; if (!Spread) Tab = "done"; break;
                case "kind": PvKind = arg == "simple" ? "simple" : "detail"; Preview = true; break;
                case "links": Links = !Links; break;
                case "copy": Copy(arg); break;
                case "off": SetOff(arg, true); break;
                case "on": SetOff(arg, false); break;
                case "edit": StartEdit(arg, ""); break;
                case "tedit": StartEdit("", arg); break;
                case "tick": Tick(arg); break;
                case "untick": Untick(arg); break;
                case "due": duePick = !duePick; break;
                case "dueday": { int n; if (int.TryParse(arg, out n)) { dueDay = w.NbNow().Date.AddDays(n); if (dueMin < 0) dueMin = -1; } } break;
                case "duetime": { int m; if (int.TryParse(arg, out m)) { if (dueDay == DateTime.MinValue) dueDay = w.NbNow().Date; dueMin = m; duePick = false; } } break;
                case "duenotime": if (dueDay == DateTime.MinValue) dueDay = w.NbNow().Date; dueMin = -1; duePick = false; break;
                case "dueclear": dueDay = DateTime.MinValue; dueMin = -1; duePick = false; break;
                case "move": MoveTodo(lastTodo, arg == "up" ? -1 : 1); break;
                case "notefocus": ShowNote(true); break;
                case "focus": FocusFor(); break;
                default: return;
            }
            Invalidate();
        }

        void GoDay(DateTime day)
        {
            EndEdit(true);
            SaveNote();
            DateTime today = w.NbNow().Date;
            Day = day > today ? today : day;
            justDone.Clear();
            scroll.Clear();
            Reload();
        }

        // 打字的地方：Enter／Esc
        public void Key(string box, string k)
        {
            if (box == "todo")
            {
                if (k == "esc") { tbTodo.Text = ""; duePick = false; dueDay = DateTime.MinValue; dueMin = -1; Invalidate(); return; }
                string s = tbTodo.Text.Trim();
                if (s == "") return;
                NbTodo t = new NbTodo();
                t.Id = Nb.NewId("t"); t.Text = s; t.Created = Nb.Ymd(w.NbNow());
                if (dueDay != DateTime.MinValue) t.Due = Nb.DueValue(dueDay, dueMin);
                todos.Add(t);
                scroll["todo"] = 1 << 20;
                w.NbSaveTodos(todos);
                lastTodo = t.Id;
                tbTodo.Text = ""; dueDay = DateTime.MinValue; dueMin = -1; duePick = false;
                logStamp = Stamp();
                Invalidate();
                return;
            }
            if (box == "done")
            {
                if (k == "esc") { tbDone.Text = ""; return; }
                string s = tbDone.Text.Trim();
                if (s == "") return;
                NbFact f = new NbFact();
                f.Id = Nb.NewId("manual:"); f.Src = "manual"; f.Title = s;
                f.T = IsToday ? w.NbNow() : Day.Date + w.NbNow().TimeOfDay;
                Nb.AppendLog(Dir, f);
                tbDone.Text = "";
                scroll["done"] = 1 << 20;   // 捲到最下面：看得到剛加的那件
                Reload();
                return;
            }
            if (box == "edit") { EndEdit(k == "enter"); return; }
        }

        void StartEdit(string thingId, string todoId)
        {
            EndEdit(true);
            if (thingId != "") { NbThing t = FindThing(thingId); if (t == null) return; editThing = thingId; tbEdit.Text = t.Title; }
            else { NbTodo t = FindTodo(todoId); if (t == null || t.Src == "jira") return; editTodo = todoId; lastTodo = todoId; tbEdit.Text = t.Text; }
            tbEdit.Tag = "";
            Invalidate();
            if (!App.Offscreen) BeginInvoke((Action)delegate { if (tbEdit.Visible) { tbEdit.Focus(); tbEdit.SelectAll(); } });
        }

        void EndEdit(bool save)
        {
            if (editThing == "" && editTodo == "") return;
            string th = editThing, td = editTodo, s = tbEdit.Text.Trim();
            editThing = ""; editTodo = "";
            tbEdit.Visible = false;
            if (!save) { Invalidate(); return; }
            if (th != "")
            {
                NbThing t = FindThing(th);
                if (t != null)
                {
                    bool mine = t.F.Src == "manual" || t.F.Src == "todo";
                    if (s == "") { edits.Titles.Remove(th); if (mine) edits.Gone.Add(th); }
                    else if (s == t.F.Title) edits.Titles.Remove(th);
                    else edits.Titles[th] = s;
                    Nb.SaveEdits(Dir, Day, edits);
                    Reload();
                }
            }
            else
            {
                NbTodo t = FindTodo(td);
                if (t != null)
                {
                    if (s == "") todos.Remove(t); else t.Text = s;
                    if (s == "" && t.Src == "school") w.NbForgetSchool(t.Ref);   // 學校的作業刪掉＝不想看到（當成交了，但不記進今天做了）
                    w.NbSaveTodos(todos);
                    logStamp = Stamp();
                }
            }
            Invalidate();
        }

        NbThing FindThing(string id) { foreach (NbThing t in things) if (t.F.Id == id) return t; return null; }
        NbTodo FindTodo(string id) { foreach (NbTodo t in todos) if (t.Id == id) return t; return null; }

        void SetOff(string id, bool off)
        {
            NbThing t = FindThing(id);
            if (t == null) return;
            t.Off = off;
            if (off) edits.Off.Add(id); else edits.Off.Remove(id);
            Nb.SaveEdits(Dir, Day, edits);
        }

        // 勾掉＝做完：移到今天做了（學校作業＝交了）
        void Tick(string id)
        {
            NbTodo t = FindTodo(id);
            if (t == null) return;
            int idx = todos.IndexOf(t);
            DateTime now = w.NbNow();
            NbFact f = new NbFact();
            f.T = now;
            if (t.Src == "school") { f.Id = "school:" + t.Ref + ":done"; f.Src = "school"; f.Project = t.Course; f.Title = "交了 " + t.Text; w.NbSchoolDone(t.Ref, true); }
            else { f.Id = "todo:" + t.Id; f.Src = "todo"; f.Title = t.Text; }
            Nb.AppendLog(Dir, f);
            todos.Remove(t);
            w.NbSaveTodos(todos);
            Just j = new Just(); j.T = t; j.Index = idx; j.LogId = f.Id; j.Until = w.Now + (w.NbReduced() ? 1.2 : 1.6);
            justDone.Add(j);
            lastTodo = "";
            Reload();
        }

        void Untick(string id)
        {
            Just j = null;
            foreach (Just x in justDone) if (x.T.Id == id) j = x;
            if (j == null) return;
            justDone.Remove(j);
            NbFact g = new NbFact(); g.Id = j.LogId; g.T = w.NbNow(); g.Gone = true; g.Src = j.T.Src == "school" ? "school" : "todo"; g.Title = j.T.Text;
            Nb.AppendLog(Dir, g);
            if (j.T.Src == "school") w.NbSchoolDone(j.T.Ref, false);
            todos.Insert(Math.Min(j.Index, todos.Count), j.T);
            w.NbSaveTodos(todos);
            Reload();
        }

        void MoveTodo(string id, int dir)
        {
            NbTodo t = FindTodo(id);
            if (t == null) return;
            int i = todos.IndexOf(t), j = i + dir;
            if (j < 0 || j >= todos.Count) return;
            todos.RemoveAt(i); todos.Insert(j, t);
            w.NbSaveTodos(todos);
            logStamp = Stamp();
            Invalidate();
        }
        public void DragTo(string id, int index)
        {
            NbTodo t = FindTodo(id);
            if (t == null) return;
            todos.Remove(t);
            todos.Insert(Math.Max(0, Math.Min(index, todos.Count)), t);
            lastTodo = id;
            w.NbSaveTodos(todos);
            logStamp = Stamp();
            Invalidate();
        }

        public string CopyText(string kind)
        {
            if (kind == "simple") return Nb.Simple(things);
            if (kind == "note") return note.Text.Replace("\r\n", "\n").TrimEnd();
            return Nb.Detail(things, Day, kind == "links" || Links);
        }

        void Copy(string kind)
        {
            string s = CopyText(kind);
            if (s.Trim() == "") return;
            w.NbClipboard(s);
            copied = kind; copiedUntil = w.Now + 3;
            w.NbSay("好了，去貼上吧");
        }

        void FocusFor()
        {
            if (App.Offscreen) return;
            BeginInvoke((Action)delegate
            {
                if (IsDisposed) return;
                if ((Spread || Tab == "todo") && tbTodo.Visible) tbTodo.Focus();
                else if (!Spread && Tab == "note") ShowNote(true);
            });
        }

        void ShowNote(bool focus)
        {
            if (rNote.IsEmpty) return;
            note.Visible = true;
            if (focus && !App.Offscreen) note.Focus();
            Invalidate();
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (keyData == (Keys.Alt | Keys.Up) || keyData == (Keys.Alt | Keys.Down))
            {
                string id = editTodo != "" ? editTodo : (hoverTodo != "" ? hoverTodo : lastTodo);
                if (id != "") { lastTodo = id; MoveTodo(id, keyData == (Keys.Alt | Keys.Up) ? -1 : 1); }
                return true;
            }
            if (keyData == Keys.Escape)
            {
                if (editThing != "" || editTodo != "") Key("edit", "esc");
                else if (duePick) { duePick = false; Invalidate(); }
                else if (Preview) { Preview = false; Invalidate(); }
                else Close();
                return true;
            }
            return base.ProcessCmdKey(ref msg, keyData);
        }

        // ================= 滑鼠 =================
        Hit HitAt(Point p)
        {
            for (int i = hits.Count - 1; i >= 0; i--) if (hits[i].R.Contains(p)) return hits[i];
            return null;
        }
        public void SimHover(Point p)
        {
            if (App.Offscreen) Render();
            Hit h = HitAt(p);
            string th = "", td = "", act = "";
            if (h != null) { act = h.Act + ":" + h.Arg; if (h.Hover != null && h.Hover.StartsWith("thing:")) th = h.Hover.Substring(6); if (h.Hover != null && h.Hover.StartsWith("todo:")) td = h.Hover.Substring(5); }
            if (th != hoverThing || td != hoverTodo || act != hoverAct) { hoverThing = th; hoverTodo = td; hoverAct = act; Invalidate(); }
        }
        public void SimClick(Point p)
        {
            if (App.Offscreen) Render();
            Hit h = HitAt(p);
            if (h == null) return;
            DoHit(h);
        }
        // 點整列（不在按鈕上）＝改字
        void DoHit(Hit h)
        {
            if (h.Act == "row") { if (h.Hover != null && h.Hover.StartsWith("thing:")) Do("edit", h.Arg); else if (h.Hover != null && h.Hover.StartsWith("todo:")) Do("tedit", h.Arg); return; }
            Do(h.Act, h.Arg);
        }
        public void HoverThing(string id) { hoverThing = id; hoverTodo = ""; Invalidate(); }
        public void HoverTodo(string id) { hoverTodo = id; hoverThing = ""; if (id != "") lastTodo = id; Invalidate(); }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (dragTodo != "" && (e.Button & MouseButtons.Left) != 0)
            {
                if (!dragging && Math.Abs(e.Y - dragStartY) > Sc(4)) dragging = true;
                if (dragging) { dragY = e.Y; Invalidate(); }
                return;
            }
            SimHover(e.Location);
            Hit h = HitAt(e.Location);
            Cursor = h != null && h.Act != "row" ? Cursors.Hand : Cursors.Default;
        }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); if (!dragging && (hoverThing != "" || hoverTodo != "" || hoverAct != "")) { hoverThing = ""; hoverTodo = ""; hoverAct = ""; Invalidate(); } }
        Point downAt;
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            downAt = e.Location;
            Hit h = HitAt(e.Location);
            if (e.Button == MouseButtons.Left && h != null && (h.Act == "grip" || h.Act == "tedit")) { dragTodo = h.Arg; dragStartY = e.Y; dragY = e.Y; dragging = false; lastTodo = h.Arg; }
            if (e.Button == MouseButtons.Left && h == null && e.Y < Sc(46)) { DragWindow(); }
        }
        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (dragTodo != "")
            {
                string id = dragTodo; bool was = dragging;
                dragTodo = ""; dragging = false;
                if (was) { DragTo(id, DropIndex(id)); return; }
            }
            if (e.Button != MouseButtons.Left) return;
            Hit h = HitAt(e.Location);
            if (h == null) return;
            if (h.Act == "grip") return;
            DoHit(h);
            FocusAfterClick(h.Act);
        }
        void FocusAfterClick(string act)
        {
            if (App.Offscreen) return;
            if (act == "addtodo" && tbTodo.Visible) tbTodo.Focus();
            if (act == "adddone" && tbDone.Visible) tbDone.Focus();
        }
        protected override void OnMouseWheel(MouseEventArgs e)
        {
            base.OnMouseWheel(e);
            foreach (KeyValuePair<string, Rectangle> kv in clipR)
                if (kv.Value.Contains(e.Location)) { ScrollBy(kv.Key, -e.Delta / 120 * Sc(28) * 2); return; }
        }
        public void ScrollBy(string key, int dy)
        {
            int s, h; Rectangle c;
            scroll.TryGetValue(key, out s);
            contentH.TryGetValue(key, out h);
            clipR.TryGetValue(key, out c);
            s = Math.Max(0, Math.Min(Math.Max(0, h - c.Height), s + dy));
            scroll[key] = s;
            Invalidate();
        }
        int DropIndex(string id)
        {
            int idx = 0;
            foreach (NbTodo t in todos)
            {
                if (t.Id == id) continue;
                Rectangle r;
                if (todoRows.TryGetValue(t.Id, out r) && dragY > r.Y + r.Height / 2) idx++;
            }
            return idx;
        }

        [DllImport("user32.dll")] static extern bool ReleaseCapture();
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
        void DragWindow() { if (App.Offscreen) return; ReleaseCapture(); SendMessage(Handle, 0xA1, new IntPtr(2), IntPtr.Zero); }   // 拖上面的木框搬家

        // ================= 畫 =================
        void AddHit(string act, string arg, Rectangle r) { AddHit(act, arg, r, null); }
        Rectangle hitClip = Rectangle.Empty;   // 捲動的紙：紙外面（看不到的）不能點
        bool again, inAgain;
        // 捲到哪：不超過內容（內容變短時往回拉，下一輪重畫一次）
        int ScrollOf(string key, Rectangle clip)
        {
            int s;
            scroll.TryGetValue(key, out s);
            s = Math.Max(0, s);   // 太大的（剛加一件、要捲到底）由 ScrollDone 拉回來再畫一次
            scroll[key] = s;
            return s;
        }
        void ScrollDone(string key, int h, Rectangle clip)
        {
            int s; scroll.TryGetValue(key, out s);
            contentH[key] = h;
            int max = Math.Max(0, h - clip.Height);
            if (s > max) { scroll[key] = max; again = true; }
        }
        void AddHit(string act, string arg, Rectangle r, string hover) { AddHit(act, arg, r, hover, false); }
        void AddHit(string act, string arg, Rectangle r, string hover, bool low)
        {
            if (!hitClip.IsEmpty) { r = Rectangle.Intersect(r, hitClip); if (r.Width <= 0 || r.Height <= 0) return; }
            Hit h = new Hit(); h.Act = act; h.Arg = arg; h.R = r; h.Hover = hover;
            if (low) hits.Insert(0, h); else hits.Add(h);
        }
        bool Hot(string act, string arg) { return hoverAct == act + ":" + arg; }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.None;
            g.Clear(KEY);
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;   // 字見 DT()
            hits.Clear(); todoRows.Clear(); clipR.Clear(); Drawn.Clear();
            again = false; hitClip = Rectangle.Empty;
            rTodo = Rectangle.Empty; rDone = Rectangle.Empty; rEdit = Rectangle.Empty; rNote = Rectangle.Empty;
            bool night = w.Night;
            int X = OV, W0 = FrameW, H0 = FrameH;
            Pix.Wood(g, X, 0, W0, H0, U, night, 31);
            Pix.Panel(g, X + Sc(8), Sc(46), W0 - Sc(16), H0 - Sc(46) - Sc(8), U, night);
            Crown(g, X, W0);
            DayBar(g, X + Sc(18), Sc(54), W0 - Sc(36));
            if (Spread)
            {
                int top = Sc(92), colW = (W0 - Sc(36) - Sc(22)) / 2, areaH = Sc(526);
                Rectangle left = new Rectangle(X + Sc(18), top, colW, areaH), right = new Rectangle(X + Sc(18) + colW + Sc(22), top, colW, areaH);
                LeftSpread(g, left);
                DoneArea(g, right, Sc(22), false);
            }
            else
            {
                int top = Sc(126), areaH = Sc(526);
                Tabs(g, X, Sc(92));
                Rectangle area = new Rectangle(X + Sc(18), top, W0 - Sc(36), areaH);
                int ti = Array.IndexOf(TabKey, Tab);
                if (Tab == "todo") TodoArea(g, area);
                else if (Tab == "note") NoteArea(g, area);
                else DoneArea(g, area, Sc(44), true);
                Drawn.Add("tab " + Tab + " " + ti);
            }
            PlaceBoxes();
            if (again && !inAgain) { inAgain = true; OnPaint(e); inAgain = false; }   // 捲動往回拉了：照新的位置再畫一次
        }

        // 頂上：銅牌＋兩邊小愛心＋右上角的叉叉
        void Crown(Graphics g, int X, int W0)
        {
            string t = "小本子";
            int tw = TW(t, fPlate), plw = tw + Sc(44), plh = Sc(25);
            Rectangle pr = new Rectangle(X + (W0 - plw) / 2, Sc(10), plw, plh);
            Pix.Plate(g, "", fPlate, pr, U);
            DT(g, t, fPlate, new Rectangle(pr.X, pr.Y, pr.Width, pr.Height - U / 2), CText, Pix.Mid);
            Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.X - Sc(8) - 5 * U, pr.Y + plh / 2 - 2 * U, U);
            Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.Right + Sc(8), pr.Y + plh / 2 - 2 * U, U);
            Rectangle xr = new Rectangle(X + W0 - Sc(10) - Sc(20), Sc(12), Sc(20), Sc(20));
            bool hot = Hot("close", "");
            Pix.Round(g, Pix.Ink, xr.X, xr.Y, xr.Width, xr.Height, U);
            Pix.Box(g, hot ? Pix.C(0xFFF3D6) : CBtn, xr.X + U, xr.Y + U, xr.Width - 2 * U, xr.Height - 2 * U);
            Pix.Box(g, Pix.C(0xDCC6A2), xr.X + U, xr.Bottom - U - Sc(3) + 1, xr.Width - 2 * U, Sc(3) - 1);
            Pix.Mono(g, Mono(IX), Pix.Ink, xr.X + (xr.Width - 5 * U) / 2, xr.Y + (xr.Height - 5 * U) / 2 - 1, U);
            AddHit("close", "", xr);
        }
        static string[] Mono(string[] a) { string[] r = new string[a.Length]; for (int i = 0; i < a.Length; i++) r[i] = a[i].Replace('k', '#'); return r; }

        // ◀ 11/19（四）［今天］ ▶ ……［攤開］［⚙ 來源］
        void DayBar(Graphics g, int x, int y, int w0)
        {
            int bh = Sc(24), by = y + (Sc(30) - bh) / 2;
            Rectangle l = new Rectangle(x, by, bh, bh);
            SmallBtn(g, l, "", false, Hot("prev", ""));
            Pix.Mono(g, Mono(ILEFT), Pix.Ink, l.X + (bh - 3 * U) / 2, l.Y + (bh - Sc(3) - 5 * U) / 2 + 1, U);
            AddHit("prev", "", l);
            string ds = Nb.DayLabel(Day);
            int dx = l.Right + Sc(8) + Sc(4), dw = TW(ds, fBody);
            DT(g, ds, fBody, new Rectangle(dx, y, dw + 4, Sc(30)), CText, Pix.LeftMid);
            int px = dx + dw + Sc(2) + Sc(8);
            Rectangle pr;
            if (IsToday)
            {
                int pw = TW("今天", fSmall) + Sc(12), ph = Sc(18);
                pr = new Rectangle(px, y + (Sc(30) - ph) / 2, pw, ph);
                Pix.Round(g, Pix.C(0x8A5A2A), pr.X, pr.Y, pr.Width, pr.Height, U);
                Pix.Box(g, Pix.C(0xF6C453), pr.X + U, pr.Y + U, pr.Width - 2 * U, pr.Height - 2 * U);
                DT(g, "今天", fSmall, new Rectangle(pr.X, pr.Y, pr.Width, pr.Height - 1), CText, Pix.Mid);
            }
            else
            {
                pr = new Rectangle(px, by, TW("回今天", fBtnS) + Sc(18), bh);
                SmallBtn(g, pr, "回今天", false, Hot("today", ""));
                AddHit("today", "", pr);
            }
            Rectangle r = new Rectangle(pr.Right + Sc(8), by, bh, bh);
            SmallBtn(g, r, "", IsToday, Hot("next", ""));
            Pix.Mono(g, Mono(IRIGHT), IsToday ? Pix.C(0xBBA98C) : Pix.Ink, r.X + (bh - 3 * U) / 2 + 1, r.Y + (bh - Sc(3) - 5 * U) / 2 + 1, U);
            if (!IsToday) AddHit("next", "", r);
            // 右邊：來源、攤開／收起
            string src = "來源";
            int sw = TW(src, fBtnS) + Sc(18) + 5 * U + Sc(5);
            Rectangle sr = new Rectangle(x + w0 - sw, by, sw, bh);
            SmallBtn(g, sr, "", false, Hot("sources", ""));
            Pix.Mono(g, Mono(IGEAR), Pix.Ink, sr.X + Sc(9), sr.Y + (bh - Sc(3) - 5 * U) / 2 + 1, U);
            DT(g, src, fBtnS, new Rectangle(sr.X + Sc(9) + 5 * U + Sc(5), sr.Y, sw, bh - Sc(3)), CText, Pix.LeftMid);
            AddHit("sources", "", sr);
            string sp = Spread ? "收起" : "攤開";
            int spw = TW(sp, fBtnS) + Sc(18);
            Rectangle spr = new Rectangle(sr.X - Sc(8) - spw, by, spw, bh);
            SmallBtn(g, spr, sp, false, Hot("spread", ""));
            AddHit("spread", "", spr);
            Drawn.Add("day " + Nb.Ymd(Day) + " " + (IsToday ? "today" : "past"));
        }

        // 上緣的三個索引頁籤：選中的比較高、接進紙張、紙色底、上緣一條頁籤色
        void Tabs(Graphics g, int X, int y)
        {
            int x = X + Sc(48), n0 = todos.Count + jira.Count, n1 = things.Count;
            for (int i = 0; i < 3; i++)
            {
                bool on = Tab == TabKey[i];
                string cnt = i == 0 ? n0.ToString() : (i == 1 ? n1.ToString() : "");
                int tw = TW(TabName[i], fBody) + (cnt != "" ? Sc(8) + TW(cnt, fWord) : 0);
                int wd = Math.Max(Sc(on ? 104 : 96), tw + Sc(28)), ht = on ? Sc(36) : Sc(32), ty = y + Sc(34) - Sc(32) - (on ? Sc(2) : 0);
                if (on) ht = Sc(36);
                Rectangle r = new Rectangle(x, ty, wd, on ? Sc(34) + Sc(2) - (ty - y) + Sc(0) : Sc(32));
                if (on) r.Height = y + Sc(34) + Sc(2) - ty;
                Pix.Box(g, Pix.Ink, r.X + U, r.Y, r.Width - 2 * U, U);
                Pix.Box(g, Pix.Ink, r.X, r.Y + U, U, r.Height - U);
                Pix.Box(g, Pix.Ink, r.Right - U, r.Y + U, U, r.Height - U);
                Pix.Box(g, on ? CPaper : TabBg[i], r.X + U, r.Y + U, r.Width - 2 * U, r.Height - U);
                if (on) Pix.Box(g, TabC[i], r.X + U, r.Y + U, r.Width - 2 * U, Sc(6));
                else Pix.Box(g, Pix.C(0xC9A777), r.X + U, r.Bottom - U, r.Width - 2 * U, U);
                bool hot = Hot("tab", TabKey[i]) && !on;
                if (hot) Pix.Box(g, Pix.Mix(TabBg[i], Color.White, 0.5), r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
                int cy = on ? r.Y + Sc(6) : r.Y, ch = on ? r.Height - Sc(6) - Sc(2) : r.Height;
                int tx = r.X + (r.Width - tw) / 2;
                DT(g, TabName[i], fBody, new Rectangle(tx, cy, tw + 4, ch), on ? CText : CTabText, Pix.LeftMid);
                if (cnt != "") DT(g, cnt, fWord, new Rectangle(tx + TW(TabName[i], fBody) + Sc(8), cy, TW(cnt, fWord) + 4, ch), on ? CText : CSub, Pix.LeftMid);
                AddHit("tab", TabKey[i], r);
                Drawn.Add("tabbtn " + TabKey[i] + " " + (on ? 1 : 0) + " " + cnt + " " + r.X + " " + r.Y + " " + r.Width + " " + r.Height);
                x += wd + Sc(4);
            }
        }

        // 紙：深色外框（2px，畫在外面）、紙色、右緣頁籤色、左邊線圈
        Rectangle Paper(Graphics g, Rectangle r, Color bg, int stripe, bool rings)
        {
            Pix.Box(g, Pix.Ink, r.X - U, r.Y - U, r.Width + 2 * U, r.Height + 2 * U);
            Pix.Box(g, bg, r.X, r.Y, r.Width, r.Height);
            if (stripe >= 0) Pix.Box(g, TabC[stripe], r.Right - Sc(6), r.Y, Sc(6), r.Height);
            return r;
        }
        void Rings(Graphics g, Rectangle paper)
        {
            for (int i = 0; i < 6; i++)
            {
                int y = paper.Y + Sc(30) + i * Sc(80);
                if (y > paper.Bottom - Sc(16)) break;
                int x = paper.X - Sc(28);
                Pix.Round(g, Pix.Ink, x, y, Sc(34), Sc(8), U);
                Pix.Box(g, Pix.C(0xCFC8BC), x + U, y + U, Sc(34) - 2 * U, Sc(8) - 2 * U);
                Pix.Box(g, Pix.C(0xF1EDE6), x + U, y + U, Sc(34) - 2 * U, U);
                int hx = paper.X + Sc(2), hy = y + Sc(1);
                Pix.Box(g, Pix.C(0xA88A64), hx, hy, Sc(6), Sc(6));
                Pix.Box(g, Pix.C(0xD9C6A4), hx + U, hy + U, Sc(6) - U, Sc(6) - U);
            }
        }
        void Scrollbar(Graphics g, string key, Rectangle paper, Rectangle clip)
        {
            int h, s;
            contentH.TryGetValue(key, out h);
            scroll.TryGetValue(key, out s);
            if (h <= clip.Height + Sc(4)) return;
            Rectangle tr = new Rectangle(paper.Right - Sc(8), paper.Y + Sc(6), Sc(6), paper.Height - Sc(12));
            Pix.Box(g, Pix.C(0xEFE3CB), tr.X, tr.Y, tr.Width, tr.Height);
            int th = Math.Max(Sc(20), tr.Height * clip.Height / h), ty = tr.Y + (tr.Height - th) * s / Math.Max(1, h - clip.Height);
            Pix.Box(g, Pix.C(0xC9A777), tr.X, ty, tr.Width, th);
        }

        // ---- 今天做了（一頁，或攤開的右頁）----
        void DoneArea(Graphics g, Rectangle area, int padL, bool single)
        {
            int foot = Sc(32), bar = Sc(28);
            Rectangle paper = new Rectangle(area.X, area.Y, area.Width, area.Height - bar - Sc(8) - foot - Sc(10));
            Paper(g, paper, Preview ? Color.White : CPaper, single ? 1 : -1, true);
            Rectangle clip = new Rectangle(paper.X + padL - Sc(8), paper.Y + Sc(6), paper.Width - padL + Sc(8) - Sc(14) + Sc(12), paper.Height - Sc(12));
            clipR[Preview ? "preview" : "done"] = clip;
            int tx = paper.X + padL, right = paper.Right - Sc(14);
            // 「補一件做過的事」：清單放得下就接在後面；放不下就釘在紙的最下面（捲動時不會被切一半）
            int fieldH = Sc(28) + Sc(4), prev;
            contentH.TryGetValue("donelist", out prev);
            bool pin = !Preview && prev + fieldH > clip.Height;
            Rectangle lclip = pin ? new Rectangle(clip.X, clip.Y, clip.Width, clip.Height - fieldH - Sc(4)) : clip;
            clipR[Preview ? "preview" : "done"] = lclip;
            GraphicsState st = g.Save();
            g.SetClip(new Rectangle(paper.X, paper.Y, paper.Width - (single ? Sc(6) : 0), pin ? lclip.Bottom - paper.Y : paper.Height));
            int s = ScrollOf(Preview ? "preview" : "done", lclip);
            hitClip = new Rectangle(paper.X - Sc(12), paper.Y, paper.Width + Sc(12), pin ? lclip.Bottom - paper.Y : paper.Height);
            int y0 = paper.Y + Sc(6) - s;
            int h = Preview ? PreviewPage(g, tx, y0, right) : DonePage(g, tx, y0, right, lclip);
            if (!Preview)
            {
                contentH["donelist"] = h;
                if ((h + fieldH > clip.Height) != pin) again = true;
                Rectangle fr = pin ? new Rectangle(tx - Sc(8), lclip.Bottom + Sc(4), right - tx + Sc(8), Sc(28)) : new Rectangle(tx - Sc(8), y0 + h, right - tx + Sc(8), Sc(28));
                if (pin) { g.ResetClip(); hitClip = Rectangle.Empty; }
                Field(g, fr, tbDone, "補一件做過的事，按 Enter", false, clip);
                rDone = Inside(fr, clip) ? fr : Rectangle.Empty;
                AddHit("adddone", "", fr);
                if (!pin) h += fieldH;
            }
            hitClip = Rectangle.Empty;
            ScrollDone(Preview ? "preview" : "done", h, lclip);
            g.Restore(st);
            Rings(g, paper);
            Scrollbar(g, Preview ? "preview" : "done", paper, lclip);
            // 貼出去會長這樣
            Rectangle br = new Rectangle(area.X, paper.Bottom + U + Sc(8) - U, area.Width, bar);
            br.Y = paper.Bottom + Sc(8);
            PvBar(g, br);
            // 會複製 N 件、複製簡單、複製詳細
            int fy = br.Bottom + Sc(10);
            bool empty = things.Count == 0 || Nb.OnCount(things) == 0;
            if (things.Count > 0) DT(g, "會複製 " + Nb.OnCount(things) + " 件", fSmall, new Rectangle(area.X, fy, Sc(160), foot), CSub, Pix.LeftMid);
            bool cD = copied == "detail" || copied == "links", cS = copied == "simple";
            string dt = cD ? "已複製詳細" : "複製詳細", stx = cS ? "已複製簡單" : "複製簡單";
            int dw = TW(dt, fBtn) + Sc(28) + (cD ? 5 * U + Sc(6) : 0), sw = TW(stx, fBtn) + Sc(28) + (cS ? 5 * U + Sc(6) : 0);
            Rectangle dr = new Rectangle(area.Right - dw, fy, dw, foot), sr = new Rectangle(dr.X - Sc(8) - sw, fy, sw, foot);
            BigBtn(g, sr, stx, empty ? 3 : (cS ? 2 : 0), Hot("copy", "simple"));
            BigBtn(g, dr, dt, empty ? 3 : (cD ? 2 : 1), Hot("copy", "detail"));
            if (!empty) { AddHit("copy", "simple", sr); AddHit("copy", "detail", dr); }
            Drawn.Add("foot " + (things.Count > 0 ? Nb.OnCount(things) : -1) + " copied=" + (copied == "" ? "-" : copied) + " " + (empty ? "off" : "on"));
        }

        // 貼出去會長這樣：▶／▼、附上連結、簡單｜詳細
        void PvBar(Graphics g, Rectangle r)
        {
            Pix.Round(g, CBarEdge, r.X, r.Y, r.Width, r.Height, U);
            Pix.Box(g, CBar, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            int x = r.X + Sc(8), cy = r.Y + r.Height / 2;
            Color ac = Pix.C(0x8A5A2A);
            if (Preview) Pix.Mono(g, Mono(IDOWN), ac, x, cy - U - U / 2, U);
            else Pix.Mono(g, Mono(IRIGHT), ac, x + U, cy - 5 * U / 2, U);
            string t = "貼出去會長這樣";
            DT(g, t, fBar, new Rectangle(x + 5 * U + Sc(8), r.Y, TW(t, fBar) + 4, r.Height), CGh, Pix.LeftMid);
            AddHit("pv", "", new Rectangle(r.X, r.Y, x + 5 * U + Sc(8) + TW(t, fBar) + Sc(8) - r.X, r.Height));
            if (!Preview) { Drawn.Add("pvbar closed"); return; }
            // 簡單｜詳細
            int sw = Sc(40), sh = Sc(20), segW = 2 * sw + 3 * U;
            Rectangle seg = new Rectangle(r.Right - Sc(6) - segW, cy - sh / 2, segW, sh);
            Pix.Round(g, Pix.Ink, seg.X, seg.Y, seg.Width, seg.Height, U);
            for (int i = 0; i < 2; i++)
            {
                bool on = (i == 0) == (PvKind == "simple");
                Rectangle c = new Rectangle(seg.X + U + i * (sw + U), seg.Y + U, sw, sh - 2 * U);
                Pix.Box(g, on ? Pix.C(0xF6C453) : CBtn, c.X, c.Y, c.Width, c.Height);
                if (on) { Pix.Box(g, Pix.C(0xFBE7BA), c.X, c.Y, c.Width, U); Pix.Box(g, Pix.C(0xC8902C), c.X, c.Bottom - U, c.Width, U); }
                DT(g, i == 0 ? "簡單" : "詳細", fSmall, c, on ? CText : CPh, Pix.Mid);
                AddHit("kind", i == 0 ? "simple" : "detail", c);
            }
            // 附上連結（只有詳細用得到）
            string lk = "附上連結";
            int lw = TW(lk, fSmall), cs = Sc(14), lx = seg.X - Sc(8) - lw - Sc(5) - cs;
            Chk(g, lx, cy - cs / 2, Links, Hot("links", ""));
            DT(g, lk, fSmall, new Rectangle(lx + cs + Sc(5), r.Y, lw + 4, r.Height), CSub, Pix.LeftMid);
            AddHit("links", "", new Rectangle(lx - Sc(2), r.Y, cs + Sc(5) + lw + Sc(4), r.Height));
            Drawn.Add("pvbar open " + PvKind + " links=" + (Links ? 1 : 0));
        }

        int DonePage(Graphics g, int tx, int y0, int right, Rectangle clip)
        {
            int y = y0, bx = tx - Sc(8), bw = right - bx;
            if (things.Count == 0) return EmptyDone(g, tx, y, right, clip) - y0;
            // 今天 N 件　CI 都過了
            Rectangle sr = new Rectangle(bx, y, bw, Sc(32));
            Pix.Round(g, CBarEdge, sr.X, sr.Y, sr.Width, sr.Height, U);
            Pix.Box(g, CBar, sr.X + U, sr.Y + U, sr.Width - 2 * U, sr.Height - 2 * U);
            DateTime today = w.NbNow().Date;
            string head = (Day == today ? "今天 " : (Day == today.AddDays(-1) ? "昨天 " : "這天 ")) + things.Count + " 件";
            DT(g, head, fBody, new Rectangle(sr.X + Sc(10), sr.Y, sr.Width, sr.Height), CText, Pix.LeftMid);
            NbWord sum = Nb.SumWord(things);
            if (sum != null) { int ww = TW(sum.Text, fWord); DT(g, sum.Text, fWord, new Rectangle(sr.Right - Sc(10) - ww - 2, sr.Y, ww + 4, sr.Height), WordC(sum.Kind, false), Pix.LeftMid); }
            Drawn.Add("sum " + head + (sum != null ? " | " + sum.Text : ""));
            y += Sc(32) + Sc(4);
            string group = null;
            foreach (NbThing t in things)
            {
                if (t.Group != group)
                {
                    group = t.Group;
                    Rectangle gr = new Rectangle(tx, y, right - tx, Sc(28));
                    DT(g, group, fBody, new Rectangle(gr.X, gr.Y, gr.Width, gr.Height - Sc(4)), CGh, TextFormatFlags.Left | TextFormatFlags.Bottom | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
                    Pix.Box(g, CGhLine, gr.X, gr.Bottom - Sc(2), gr.Width, Sc(2));
                    Drawn.Add("group " + group);
                    y += Sc(28) + Sc(4);
                }
                y += ThingRow(g, t, bx, y, right, clip);
            }
            y += Sc(4);   // 「補一件做過的事」由 DoneArea 畫
            return y - y0;
        }

        Color WordC(int kind, bool hot) { return kind == 2 ? CBad : (kind == 1 ? (hot ? COkHot : COk) : CSub); }

        int ThingRow(Graphics g, NbThing t, int bx, int y, int right, Rectangle clip)
        {
            bool hot = t.F.Id == hoverThing && !t.Off && editThing != t.F.Id, editing = editThing == t.F.Id;
            int tx = bx + Sc(8);
            List<NbWord> words = Nb.Words(t);
            List<Run> runs = new List<Run>();
            Color main = t.Off ? COff : CText;
            runs.Add(new Run(Nb.PageText(t), fBody, main));
            foreach (NbWord wd in words)
            {
                Run cm = new Run("，", fWord, t.Off ? COff : CSub); cm.KeepNext = true; runs.Add(cm);
                Run wr = new Run(wd.Text, fWord, t.Off ? COff : WordC(wd.Kind, hot)); wr.Keep = true; runs.Add(wr);
            }
            string back = "要複製";
            int avail = right - Sc(6) - tx - (t.Off ? TW(back, fSmall) + Sc(10) : 0);
            int lines = Flow(g, runs, tx, y + Sc(3), avail, Sc(22), false, false);   // 先量（跟畫用同一個 Graphics，換行才一樣）
            int h = Sc(6) + lines * Sc(22) + (hot ? Sc(16) : 0);
            Rectangle row = new Rectangle(bx, y, right - bx, h);
            if (hot)
            {
                Pix.Round(g, Pix.C(0xD9A944), row.X, row.Y, row.Width, row.Height, U);
                Pix.Box(g, Pix.C(0xFFE29A), row.X + U, row.Y + U, row.Width - 2 * U, row.Height - 2 * U);
                Pix.Box(g, Pix.C(0xFFF1C9), row.X + U, row.Y + U, row.Width - 2 * U, Sc(3) - U);
            }
            if (editing)
            {
                rEdit = new Rectangle(tx, y + Sc(3), avail, Sc(22));
                Pix.Round(g, Pix.Ink, rEdit.X - Sc(4), rEdit.Y - Sc(2), rEdit.Width + Sc(8), rEdit.Height + Sc(4), U);
                Pix.Box(g, CPaper, rEdit.X - Sc(4) + U, rEdit.Y - Sc(2) + U, rEdit.Width + Sc(8) - 2 * U, rEdit.Height + Sc(4) - 2 * U);
                if (App.Offscreen) DT(g, tbEdit.Text, fBody, rEdit, CText, Pix.LeftMid);
                if (!Inside(rEdit, clip)) rEdit = Rectangle.Empty;
            }
            else Flow(g, runs, tx, y + Sc(3), avail, Sc(22), t.Off);
            AddHit("edit", t.F.Id, new Rectangle(tx, y, Math.Max(Sc(20), Math.Min(avail, FlowW(runs))), Sc(6) + lines * Sc(22)), "thing:" + t.F.Id);
            if (hot)
            {
                DT(g, Nb.Ids(t), fSmall, new Rectangle(tx, y + Sc(3) + lines * Sc(22), right - tx, Sc(16)), CSub, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
                string nc = "不複製";
                int bw = TW(nc, fBtnS) + Sc(18);
                Rectangle br = new Rectangle(row.Right - Sc(6) - bw, row.Bottom - Sc(3) - Sc(20), bw, Sc(20));
                SmallBtn(g, br, nc, false, Hot("off", t.F.Id));
                AddHit("off", t.F.Id, br, "thing:" + t.F.Id);
            }
            if (t.Off)
            {
                int bw = TW(back, fSmall);
                Rectangle br = new Rectangle(row.Right - Sc(6) - bw, y + Sc(6), bw, Sc(16));
                DT(g, back, fSmall, new Rectangle(br.X, br.Y, br.Width + 4, br.Height), Hot("on", t.F.Id) ? CText : CSub, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
                AddHit("on", t.F.Id, new Rectangle(br.X - Sc(4), y, br.Width + Sc(8), h), "thing:" + t.F.Id);
            }
            AddHit("row", t.F.Id, row, "thing:" + t.F.Id, true);   // 整列只管 hover，放最下面
            Drawn.Add("thing " + t.F.Id + " " + (t.Off ? "off" : "on") + (hot ? " hot" : "") + " | " + RunsText(runs) + (hot ? " | " + Nb.Ids(t) : ""));
            return h;
        }

        // 空白：接上之後，做過的事會自己記下來
        int EmptyDone(Graphics g, int tx, int y, int right, Rectangle clip)
        {
            DT(g, "接上之後，做過的事會自己記下來", fWord, new Rectangle(tx, y, right - tx, Sc(32)), CSub, Pix.LeftMid);
            Drawn.Add("empty done");
            y += Sc(32);
            string[][] rows = {
                new string[] { "claude", "Claude Code／Codex", "本機紀錄" }, new string[] { "school", "學校行事曆", "上課、作業" }, new string[] { "calendar", "行事曆", "會議" },
                new string[] { "github", "GitHub", "PR、CI" }, new string[] { "gitlab", "GitLab", "MR、CI" }, new string[] { "jira", "Jira", "工單" } };
            int bx = tx - Sc(8);
            foreach (string[] r in rows)
            {
                DrawIcon(g, r[0], tx, y + Sc(16) - 4 * U);
                DT(g, r[1], fWord, new Rectangle(tx + 8 * U + Sc(8), y, Sc(150), Sc(32)), CText, Pix.LeftMid);
                DT(g, r[2], fSmall, new Rectangle(tx + 8 * U + Sc(8) + Sc(150) + Sc(8), y, Sc(120), Sc(32)), CSub, Pix.LeftMid);
                if (w.WorkSourceOn(r[0]))
                {
                    string ok = "已接上";
                    int ow = TW(ok, fSmall);
                    DT(g, ok, fSmall, new Rectangle(right - ow - 2, y, ow + 4, Sc(32)), COk, Pix.LeftMid);
                    Pix.Mono(g, Pix.CHECK, COk, right - ow - Sc(4) - 5 * U, y + Sc(16) - 5 * U / 2, U);
                }
                else
                {
                    string c = "接上";
                    int cw = TW(c, fBtnS) + Sc(18);
                    Rectangle br = new Rectangle(right - cw, y + Sc(4), cw, Sc(24));
                    SmallBtn(g, br, c, false, Hot("connect", r[0]));
                    AddHit("connect", r[0], br);
                }
                y += Sc(32);
            }
            return y + Sc(14);   // 「補一件做過的事」由 DoneArea 畫
        }

        // 預覽：白紙上就是要貼出去的字（簡單／詳細、附不附連結）
        int PreviewPage(Graphics g, int tx, int y0, int right)
        {
            string text = PvKind == "simple" ? Nb.Simple(things) : Nb.Detail(things, Day, Links);
            int y = y0, lh = Sc(19), ind = Sc(14);
            foreach (string raw in text.Split('\n'))
            {
                bool head = raw.StartsWith("【") || raw.EndsWith("進度");
                bool kid = raw.StartsWith("　");
                string s = kid ? raw.Substring(1) : raw;
                int x = tx + (kid ? ind : 0), hang = s.StartsWith("・") || s.StartsWith("- ") ? ind : 0;
                if (s == "") { y += lh; continue; }
                List<Run> runs = new List<Run>();
                runs.Add(new Run(s, head ? fPvB : fPv, CNote));
                int n = FlowHang(g, runs, x, y, right - x, lh, hang);
                y += n * lh;
            }
            Drawn.Add("preview " + PvKind + " links=" + (Links ? 1 : 0));
            return y - y0 + Sc(8);
        }

        // ---- 待辦（一頁）----
        void TodoArea(Graphics g, Rectangle area)
        {
            Rectangle paper = Paper(g, area, CPaper, 0, true);
            Rectangle clip = new Rectangle(paper.X + Sc(36), paper.Y + Sc(6), paper.Width - Sc(36) - Sc(2), paper.Height - Sc(12));
            clipR["todo"] = clip;
            bool pin;
            Rectangle lclip = TodoClip(clip, out pin);
            clipR["todo"] = lclip;
            GraphicsState st = g.Save();
            g.SetClip(new Rectangle(paper.X, paper.Y, paper.Width - Sc(6), lclip.Bottom - paper.Y + (pin ? 0 : Sc(6))));
            int s = ScrollOf("todo", lclip);
            hitClip = new Rectangle(paper.X - Sc(12), paper.Y, paper.Width + Sc(12), lclip.Bottom - paper.Y + (pin ? 0 : Sc(6)));
            todoPin = pin;
            int h = TodoPage(g, paper.X + Sc(44), paper.Y + Sc(6) - s, paper.Right - Sc(14), lclip);
            todoPin = false;
            hitClip = Rectangle.Empty;
            TodoMeasured(h, pin, clip);
            ScrollDone("todo", h, lclip);
            g.Restore(st);
            if (pin) TodoField(g, new Rectangle(paper.X + Sc(36), lclip.Bottom + Sc(4), paper.Right - Sc(14) - paper.X - Sc(36), Sc(28)), clip);
            Rings(g, paper);
            Scrollbar(g, "todo", paper, lclip);
            DuePopup(g, clip);
        }

        int TodoPage(Graphics g, int tx, int y0, int right, Rectangle clip)
        {
            int y = y0, bx = tx - Sc(8);
            DateTime now = w.NbNow();
            if (todos.Count == 0 && jira.Count == 0 && justDone.Count == 0)
            {
                DT(g, "還沒有待辦", fWord, new Rectangle(tx, y, right - tx, Sc(32)), CSub, Pix.LeftMid);
                Drawn.Add("empty todo");
                y += Sc(32);
            }
            else
            {
                List<NbTodo> shown = new List<NbTodo>();
                foreach (NbTodo t in todos) if (!(dragging && t.Id == dragTodo)) shown.Add(t);
                int drop = dragging ? DropIndex(dragTodo) : -1;
                int dragAt = -1;
                for (int i = 0; i <= shown.Count; i++)
                {
                    if (i == drop)
                    {
                        Pix.Box(g, Pix.C(0xFFF6D8), bx, y + Sc(1), right - bx + Sc(4), Sc(28) - Sc(2));
                        for (int dx = bx; dx < right + Sc(4); dx += Sc(8)) { Pix.Box(g, Pix.C(0xD9A944), dx, y + Sc(1), Sc(4), Sc(2)); Pix.Box(g, Pix.C(0xD9A944), dx, y + Sc(25), Sc(4), Sc(2)); }
                        dragAt = y;
                        y += Sc(28);
                    }
                    if (i == shown.Count) break;
                    y += TodoRow(g, shown[i], bx, y, right, now, false);
                }
                foreach (Just j in justDone)
                {
                    Rectangle r = new Rectangle(bx, y, right - bx, Sc(28));
                    Chk(g, r.X + Sc(8), y + (Sc(28) - Sc(14)) / 2, true, false);
                    string mv = "今天做了";
                    int mw = TW(mv, fWord);
                    int tx2 = r.X + Sc(8) + Sc(14) + Sc(8);
                    int avail = right - Sc(6) - tx2 - mw - 3 * U - Sc(12);
                    string txt = Ellipsis(j.T.Text, fBody, avail);
                    DT(g, txt, fBody, new Rectangle(tx2, y, avail + 4, Sc(28)), COff, Pix.LeftMid);
                    Pix.Box(g, COff, tx2, y + Sc(14), TW(txt, fBody), Sc(2));
                    int ax = right - Sc(6) - mw;
                    Pix.Mono(g, Mono(IRIGHT), COk, ax - 3 * U - Sc(4), y + Sc(14) - 5 * U / 2, U);
                    DT(g, mv, fWord, new Rectangle(ax, y, mw + 4, Sc(28)), COk, Pix.LeftMid);
                    AddHit("untick", j.T.Id, new Rectangle(r.X, y, Sc(8) + Sc(14) + Sc(8), Sc(28)));
                    Drawn.Add("justdone " + j.T.Text);
                    y += Sc(28);
                }
                if (dragging)
                {
                    NbTodo dt = FindTodo(dragTodo);
                    if (dt != null) { int ly = Math.Max(clip.Y - Sc(10), Math.Min(clip.Bottom - Sc(20), dragY - Sc(14))); TodoRow(g, dt, bx + Sc(8), ly - Sc(3), right + Sc(4), now, true); }
                }
            }
            // 新增一行（右邊小日曆：期限）；放不下時由呼叫的地方釘在最下面
            if (!todoPin)
            {
                y += Sc(4);
                TodoField(g, new Rectangle(bx, y, right - bx, Sc(28)), clip);
                y += Sc(28) + Sc(4);
            }
            if (jira.Count > 0)
            {
                Rectangle gr = new Rectangle(tx, y, right - tx, Sc(40));
                DT(g, "Jira 指派給我", fBody, new Rectangle(gr.X, gr.Y, gr.Width, gr.Height - Sc(4)), CGh, TextFormatFlags.Left | TextFormatFlags.Bottom | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
                Pix.Box(g, CGhLine, gr.X, gr.Bottom - Sc(2), gr.Width, Sc(2));
                y += Sc(40) + Sc(4);
                foreach (NbFact j in jira)
                {
                    DrawIcon(g, "jira", tx, y + Sc(14) - 7 * U / 2);
                    string st = j.Status != "" ? j.Status : "待處理";
                    int sw = TW(st, fWord), x2 = tx + 8 * U + Sc(8), avail = right - Sc(6) - sw - Sc(8) - x2;
                    DT(g, Ellipsis((j.Ref + " " + j.Title).Trim(), fBody, avail), fBody, new Rectangle(x2, y, avail + 4, Sc(28)), CText, Pix.LeftMid);
                    DT(g, st, fWord, new Rectangle(right - Sc(6) - sw - 2, y, sw + 4, Sc(28)), CTime, Pix.LeftMid);
                    Drawn.Add("jira " + j.Ref + " " + j.Title + " | " + st);
                    y += Sc(28);
                }
            }
            return y - y0;
        }
        Rectangle dueAnchor;
        bool todoPin;
        void TodoField(Graphics g, Rectangle fr, Rectangle clip)
        {
            string chip = dueDay != DateTime.MinValue ? DueChip() : "";
            Field(g, fr, tbTodo, "寫一件要做的事，按 Enter", true, clip, chip);
            rTodo = Inside(fr, clip) ? new Rectangle(fr.X, fr.Y, fr.Width - Sc(8) - (chip != "" ? TW(chip, fWord) + Sc(8) : 7 * U + Sc(4)), fr.Height) : Rectangle.Empty;
            AddHit("addtodo", "", fr);
            Rectangle cal = new Rectangle(fr.Right - Sc(8) - (chip != "" ? TW(chip, fWord) : 7 * U) - Sc(4), fr.Y, (chip != "" ? TW(chip, fWord) : 7 * U) + Sc(12), fr.Height);
            AddHit("due", "", cal);
            dueAnchor = fr;
        }
        // 待辦清單（不含新增那一行）有多高：上一輪量的；放得下＝新增那一行接在清單裡
        Rectangle TodoClip(Rectangle clip, out bool pin)
        {
            int fieldH = Sc(28) + Sc(8), prev;
            contentH.TryGetValue("todolist", out prev);
            pin = prev + fieldH > clip.Height;
            return pin ? new Rectangle(clip.X, clip.Y, clip.Width, clip.Height - fieldH - Sc(4)) : clip;
        }
        void TodoMeasured(int h, bool pin, Rectangle clip)
        {
            int listH = pin ? h : h - Sc(28) - Sc(8);
            contentH["todolist"] = listH;
            if ((listH + Sc(28) + Sc(8) > clip.Height) != pin) again = true;
        }

        string DueChip()
        {
            DateTime today = w.NbNow().Date;
            int days = (dueDay - today).Days;
            string day = days == 0 ? "今天" : (days == 1 ? "明天" : Nb.WeekName(dueDay));
            return dueMin >= 0 ? day + " " + (dueMin / 60).ToString("00") + ":" + (dueMin % 60).ToString("00") : day;
        }

        int TodoRow(Graphics g, NbTodo t, int bx, int y, int right, DateTime now, bool lifted)
        {
            bool hot = t.Id == hoverTodo && !lifted && !dragging, editing = editTodo == t.Id;
            Rectangle row = new Rectangle(bx, y, right - bx, Sc(28));
            if (lifted)
            {
                Pix.Box(g, Color.FromArgb(46, 74, 44, 23), row.X + Sc(4), row.Bottom, row.Width, Sc(4));
                Pix.Round(g, Pix.Ink, row.X, row.Y, row.Width, row.Height, U);
                Pix.Box(g, Color.White, row.X + U, row.Y + U, row.Width - 2 * U, row.Height - 2 * U);
            }
            else if (hot)
            {
                Pix.Round(g, Pix.C(0xD9A944), row.X, row.Y, row.Width, row.Height, U);
                Pix.Box(g, Pix.C(0xFFE29A), row.X + U, row.Y + U, row.Width - 2 * U, row.Height - 2 * U);
                Pix.Box(g, Pix.C(0xFFF1C9), row.X + U, row.Y + U, row.Width - 2 * U, Sc(3) - U);
            }
            if (hot || lifted)
            {
                Dictionary<char, Color> gp = new Dictionary<char, Color>(); gp['k'] = Pix.C(0xB08A5A);
                Pix.Art(g, IGRIP, gp, bx - Sc(6), y + Sc(9), U);
            }
            if (!lifted) AddHit("grip", t.Id, new Rectangle(bx - Sc(10), y, Sc(16), Sc(28)), "todo:" + t.Id);
            int x = bx + Sc(8);
            Chk(g, x, y + (Sc(28) - Sc(14)) / 2, false, Hot("tick", t.Id));
            if (!lifted) AddHit("tick", t.Id, new Rectangle(x - Sc(4), y, Sc(14) + Sc(8), Sc(28)), "todo:" + t.Id);
            x += Sc(14) + Sc(8);
            if (t.Src == "school") { DrawIcon(g, "hw", x, y + Sc(14) - 4 * U); x += 8 * U + Sc(8); }
            bool urgent;
            string due = Nb.DueText(t.Due, now, out urgent);
            int dw = due != "" ? TW(due, fWord) : 0;
            bool carried = t.Src != "school" && t.Created != "" && string.CompareOrdinal(t.Created, Nb.Ymd(now)) < 0;
            int pw = carried ? TW("從昨天", fSmall) + Sc(12) : 0;
            int end = right - Sc(6) - dw - (dw > 0 ? Sc(8) : 0) - (carried ? pw + Sc(8) : 0);
            int cw = t.Src == "school" && t.Course != "" ? TW(t.Course, fSmall) + Sc(6) : 0;
            string txt = Ellipsis(t.Text, fBody, end - x - cw);
            int tw = TW(txt, fBody);
            if (editing)
            {
                rEdit = new Rectangle(x, y + Sc(3), end - x, Sc(22));
                Pix.Round(g, Pix.Ink, rEdit.X - Sc(4), rEdit.Y - Sc(2), rEdit.Width + Sc(8), rEdit.Height + Sc(4), U);
                Pix.Box(g, CPaper, rEdit.X - Sc(4) + U, rEdit.Y - Sc(2) + U, rEdit.Width + Sc(8) - 2 * U, rEdit.Height + Sc(4) - 2 * U);
                if (App.Offscreen) DT(g, tbEdit.Text, fBody, rEdit, CText, Pix.LeftMid);
            }
            else
            {
                DT(g, txt, fBody, new Rectangle(x, y, tw + 4, Sc(28)), CText, Pix.LeftMid);
                if (cw > 0) DT(g, t.Course, fSmall, new Rectangle(x + tw + Sc(6), y + Sc(1), cw + 4, Sc(28)), CSub, Pix.LeftMid);
            }
            if (!lifted) AddHit("tedit", t.Id, new Rectangle(x, y, Math.Max(Sc(20), end - x), Sc(28)), "todo:" + t.Id);
            int rx = right - Sc(6);
            if (dw > 0) { DT(g, due, fWord, new Rectangle(rx - dw - 2, y, dw + 4, Sc(28)), urgent ? CBad : CTime, Pix.LeftMid); rx -= dw + Sc(8); }
            if (carried)
            {
                Rectangle pr = new Rectangle(rx - pw, y + (Sc(28) - Sc(18)) / 2, pw, Sc(18));
                Pix.Round(g, Pix.C(0xC9B08A), pr.X, pr.Y, pr.Width, pr.Height, U);
                Pix.Box(g, Pix.C(0xF3EADB), pr.X + U, pr.Y + U, pr.Width - 2 * U, pr.Height - 2 * U);
                DT(g, "從昨天", fSmall, new Rectangle(pr.X, pr.Y, pr.Width, pr.Height - 1), CSub, Pix.Mid);
            }
            if (!lifted) { todoRows[t.Id] = row; AddHit("row", t.Id, row, "todo:" + t.Id, true); }
            if (!lifted) Drawn.Add("todo " + t.Id + " " + (t.Src == "school" ? "school" : "mine") + (carried ? " carried" : "") + (hot ? " hot" : "") + " | " + t.Text + (t.Course != "" ? " | " + t.Course : "") + " | " + due + (urgent && due != "" ? " !" : ""));
            else Drawn.Add("lifted " + t.Id);
            return Sc(28);
        }

        // 期限：今天、明天、週X…；不設時間、12:00、18:00、22:00、23:59；不設期限
        void DuePopup(Graphics g, Rectangle clip)
        {
            if (!duePick || dueAnchor.IsEmpty) return;
            DateTime today = w.NbNow().Date;
            List<string[]> dayChips = new List<string[]>();
            for (int i = 0; i < 7; i++) dayChips.Add(new string[] { i == 0 ? "今天" : (i == 1 ? "明天" : Nb.WeekName(today.AddDays(i))), i.ToString() });
            string[][] times = { new string[] { "不設時間", "-1" }, new string[] { "12:00", "720" }, new string[] { "18:00", "1080" }, new string[] { "22:00", "1320" }, new string[] { "23:59", "1439" } };
            int pad = Sc(8), ch = Sc(24), gap = Sc(6), wdt = Sc(250);
            int rowsH = pad + ch * 4 + gap * 3 + pad;
            Rectangle box = new Rectangle(dueAnchor.Right - wdt, dueAnchor.Bottom + Sc(4), wdt, rowsH);
            if (box.Bottom > clip.Bottom) box.Y = dueAnchor.Y - Sc(4) - rowsH;
            Pix.Round(g, Pix.Ink, box.X, box.Y, box.Width, box.Height, U);
            Pix.Box(g, Pix.Cream, box.X + U, box.Y + U, box.Width - 2 * U, box.Height - 2 * U);
            int x = box.X + pad, y = box.Y + pad;
            for (int i = 0; i < dayChips.Count; i++)
            {
                if (i == 4) { x = box.X + pad; y += ch + gap; }
                string t = dayChips[i][0];
                int cw = TW(t, fBtnS) + Sc(18);
                Rectangle r = new Rectangle(x, y, cw, ch);
                bool on = dueDay != DateTime.MinValue && (dueDay - today).Days.ToString() == dayChips[i][1];
                SmallBtn(g, r, t, false, on || Hot("dueday", dayChips[i][1]));
                AddHit("dueday", dayChips[i][1], r);
                x += cw + gap;
            }
            x = box.X + pad; y += ch + gap;
            for (int i = 0; i < times.Length; i++)
            {
                if (i == 3) { x = box.X + pad; y += ch + gap; }
                int cw = TW(times[i][0], fBtnS) + Sc(18);
                Rectangle r = new Rectangle(x, y, cw, ch);
                SmallBtn(g, r, times[i][0], false, Hot(times[i][1] == "-1" ? "duenotime" : "duetime", times[i][1] == "-1" ? "" : times[i][1]));
                if (times[i][1] == "-1") AddHit("duenotime", "", r); else AddHit("duetime", times[i][1], r);
                x += cw + gap;
            }
            string cl = "不設期限";
            int clw = TW(cl, fBtnS) + Sc(18);
            Rectangle cr = new Rectangle(box.Right - pad - clw, y, clw, ch);
            SmallBtn(g, cr, cl, false, Hot("dueclear", ""));
            AddHit("dueclear", "", cr);
            Drawn.Add("duepick");
        }

        // ---- 筆記（一頁）----
        void NoteArea(Graphics g, Rectangle area)
        {
            int foot = Sc(34);
            Rectangle paper = Paper(g, new Rectangle(area.X, area.Y, area.Width, area.Height - Sc(8) - foot), CPaper, 2, true);
            Rectangle box = new Rectangle(paper.X + Sc(44), paper.Y + Sc(6), paper.Width - Sc(44) - Sc(14), paper.Height - Sc(12));
            NoteLines(g, paper, box);
            NoteText(g, box);
            Rings(g, paper);
            AddHit("notefocus", "", box);
            rNote = box;
            int fy = paper.Bottom + U + Sc(8) - U;
            bool empty = note.Text.Trim() == "";
            if (!empty && savedAt != "")
            {
                Pix.Mono(g, Pix.CHECK, COk, area.X, fy + foot / 2 - 5 * U / 2, U);
                DT(g, "已存 " + savedAt, fSmall, new Rectangle(area.X + 5 * U + Sc(6), fy, Sc(160), foot), CSub, Pix.LeftMid);
            }
            string ct = copied == "note" ? "已複製筆記" : "複製筆記";
            int cw = TW(ct, fBtn) + Sc(28) + (copied == "note" ? 5 * U + Sc(6) : 0);
            Rectangle cr = new Rectangle(area.Right - cw, fy + (foot - Sc(32)) / 2, cw, Sc(32));
            BigBtn(g, cr, ct, empty ? 3 : (copied == "note" ? 2 : 0), Hot("copy", "note"));
            if (!empty) AddHit("copy", "note", cr);
            Drawn.Add("note saved=" + (savedAt == "" ? "-" : savedAt) + " " + (empty ? "empty" : "text"));
        }

        // 28px 一行、每行底下一條線（跟 RichEdit 的固定行高對齊）
        void NoteLines(Graphics g, Rectangle paper, Rectangle box)
        {
            for (int y = box.Y + Sc(28) - Sc(2); y < paper.Bottom - Sc(2); y += Sc(28)) Pix.Box(g, Pix.C(0xEFE0C4), paper.X, y, paper.Width - Sc(6), 1);
        }
        void NoteText(Graphics g, Rectangle box)
        {
            string text = note.Text.Replace("\r\n", "\n");
            if (text.Trim() == "" && !(note.Visible && note.Focused))
            {
                DT(g, "隨手寫，會自己存", fNote, new Rectangle(box.X, box.Y, box.Width, Sc(28) - Sc(2)), CPh, TextFormatFlags.Left | TextFormatFlags.Bottom | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
                return;
            }
            if (!App.Offscreen && note.Visible) return;
            // 離屏（或還沒點進去）：自己照 28px 一行畫，換行跟 RichEdit 一樣一個字一個字斷
            int y = box.Y;
            foreach (string para in text.Split('\n'))
            {
                List<Run> runs = new List<Run>();
                runs.Add(new Run(para == "" ? " " : para, fNote, CNote));
                int n = FlowLines(g, runs, box.X, y, box.Width, Sc(28), y + Sc(28) - Sc(4));
                y += Math.Max(1, n) * Sc(28);
                if (y > box.Bottom) break;
            }
        }

        // ---- 攤開的左頁：待辦＋筆記 ----
        void LeftSpread(Graphics g, Rectangle area)
        {
            Rectangle paper = Paper(g, area, CPaper, -1, false);
            int tx = paper.X + Sc(14), right = paper.Right - Sc(14);
            int noteMin = Sc(40) + Sc(28) * 4 + Sc(6);
            Rectangle clip = new Rectangle(paper.X + Sc(6), paper.Y + Sc(6), paper.Width - Sc(8), paper.Height - Sc(12) - noteMin);
            bool pin;
            Rectangle lclip = TodoClip(clip, out pin);
            int s = ScrollOf("todo", lclip);
            GraphicsState st = g.Save();
            g.SetClip(lclip);
            hitClip = new Rectangle(paper.X - Sc(12), lclip.Y, paper.Width + Sc(12), lclip.Height);
            todoPin = pin;
            int h = TodoPage(g, tx, paper.Y + Sc(6) - s, right, lclip);
            todoPin = false;
            hitClip = Rectangle.Empty;
            g.Restore(st);
            TodoMeasured(h, pin, clip);
            ScrollDone("todo", h, lclip);
            if (pin) TodoField(g, new Rectangle(tx - Sc(8), lclip.Bottom + Sc(4), right - tx + Sc(8), Sc(28)), clip);
            int used = pin ? clip.Height : Math.Min(h, clip.Height);
            clip.Height = used;
            clipR["todo"] = pin ? lclip : clip;
            Scrollbar(g, "todo", new Rectangle(paper.X, clip.Y - Sc(6), paper.Width, clip.Height + Sc(12)), clip);
            // 筆記：標題列（已存、複製）＋下面的紙
            int ny = clip.Bottom;
            Rectangle gr = new Rectangle(tx, ny, right - tx, Sc(40));
            DT(g, "筆記", fBody, new Rectangle(gr.X, gr.Y, gr.Width, gr.Height - Sc(4)), CGh, TextFormatFlags.Left | TextFormatFlags.Bottom | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
            Pix.Box(g, CGhLine, gr.X, gr.Bottom - Sc(2), gr.Width, Sc(2));
            bool empty = note.Text.Trim() == "";
            string ct = copied == "note" ? "已複製" : "複製";
            int cw = TW(ct, fBtnS) + Sc(18);
            Rectangle cr = new Rectangle(right - cw, gr.Bottom - Sc(4) - Sc(24) - Sc(2), cw, Sc(24));
            if (empty) SmallBtnOff(g, cr, ct); else SmallBtn(g, cr, ct, false, Hot("copy", "note"));
            if (!empty) AddHit("copy", "note", cr);
            if (!empty && savedAt != "")
            {
                string sv = "已存 " + savedAt;
                int sw = TW(sv, fSmall);
                DT(g, sv, fSmall, new Rectangle(cr.X - Sc(8) - sw - 2, cr.Y, sw + 4, cr.Height), CSub, Pix.LeftMid);
                Pix.Mono(g, Pix.CHECK, COk, cr.X - Sc(8) - sw - Sc(6) - 5 * U, cr.Y + cr.Height / 2 - 5 * U / 2, U);
            }
            Rectangle box = new Rectangle(tx, gr.Bottom + Sc(4), right - tx, paper.Bottom - Sc(6) - gr.Bottom - Sc(4));
            NoteText(g, box);
            AddHit("notefocus", "", box);
            rNote = box;
            Drawn.Add("note saved=" + (savedAt == "" ? "-" : savedAt) + " " + (empty ? "empty" : "text"));
            DuePopup(g, new Rectangle(paper.X, paper.Y, paper.Width, paper.Height));
        }

        // ================= 打字框放到畫出來的位置 =================
        void PlaceBoxes()
        {
            int pad = Sc(8) + 5 * U + Sc(8);
            Place(tbTodo, rTodo.IsEmpty ? Rectangle.Empty : new Rectangle(rTodo.X + pad, rTodo.Y + (rTodo.Height - tbTodo.PreferredHeight) / 2, rTodo.Width - pad, tbTodo.PreferredHeight));
            Place(tbDone, rDone.IsEmpty ? Rectangle.Empty : new Rectangle(rDone.X + pad, rDone.Y + (rDone.Height - tbDone.PreferredHeight) / 2, rDone.Width - pad - Sc(8), tbDone.PreferredHeight));
            Place(tbEdit, rEdit.IsEmpty ? Rectangle.Empty : new Rectangle(rEdit.X, rEdit.Y + (rEdit.Height - tbEdit.PreferredHeight) / 2, rEdit.Width, tbEdit.PreferredHeight));
            bool noteOn = !rNote.IsEmpty && (note.Text != "" || note.Focused || note.Visible);
            if (rNote.IsEmpty) { if (note.Visible) note.Visible = false; }
            else
            {
                Rectangle nr = new Rectangle(rNote.X, rNote.Y, rNote.Width + Sc(10), rNote.Height);
                if (note.Bounds != nr) note.Bounds = nr;
                if (noteOn != note.Visible) note.Visible = noteOn;
            }
        }
        void Place(Control c, Rectangle r)
        {
            if (r.IsEmpty) { if (c.Visible) c.Visible = false; return; }
            if (c.Bounds != r) c.Bounds = r;
            if (!c.Visible) c.Visible = true;
        }
        static bool Inside(Rectangle r, Rectangle clip) { return r.Y >= clip.Y - 2 && r.Bottom <= clip.Bottom + 2; }

        // ================= 小零件 =================
        // 輸入框：奶油白、淺棕邊（打字中＝深色邊）；左邊 ＋、右邊小日曆或期限
        void Field(Graphics g, Rectangle r, TextBox tb, string ph, bool cal, Rectangle clip) { Field(g, r, tb, ph, cal, clip, ""); }
        void Field(Graphics g, Rectangle r, TextBox tb, string ph, bool cal, Rectangle clip, string chip)
        {
            bool focus = tb.Focused || (App.Offscreen && tb.Text != "");
            Pix.Round(g, focus ? Pix.Ink : CField, r.X, r.Y, r.Width, r.Height, U);
            Pix.Box(g, CPaper, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            Pix.Box(g, Pix.C(0xF1E6D0), r.X + U, r.Y + U, r.Width - 2 * U, U);
            int x = r.X + Sc(8);
            if (!focus || tb.Text == "") Pix.Mono(g, Mono(IPLUS), CTime, x, r.Y + (r.Height - 5 * U) / 2, U);
            int tx = x + 5 * U + Sc(8);
            if (App.Offscreen || !tb.Visible)
            {
                if (tb.Text == "") DT(g, ph, fField, new Rectangle(tx, r.Y, r.Width - (tx - r.X), r.Height), CPh, Pix.LeftMid);
                else
                {
                    int tw = TW(tb.Text, fField);
                    DT(g, tb.Text, fField, new Rectangle(tx, r.Y, tw + 4, r.Height), CText, Pix.LeftMid);
                    if (App.Offscreen) Pix.Box(g, CText, tx + tw + 1, r.Y + Sc(7), 1, r.Height - Sc(14));   // 游標
                }
            }
            if (chip != "")
            {
                int cw = TW(chip, fWord);
                DT(g, chip, fWord, new Rectangle(r.Right - Sc(8) - cw - 2, r.Y, cw + 4, r.Height), Pix.C(0x35577F), Pix.LeftMid);
            }
            else if (cal)
            {
                Dictionary<char, Color> p = new Dictionary<char, Color>(); p['k'] = Pix.C(0x9A6338); p['w'] = CPaper;
                Pix.Art(g, ICAL, p, r.Right - Sc(8) - 7 * U, r.Y + (r.Height - 6 * U) / 2, U);
            }
            Drawn.Add("field " + (tb == tbTodo ? "todo" : "done") + " " + (tb.Text == "" ? "-" : tb.Text) + (chip != "" ? " | " + chip : ""));
        }

        void Chk(Graphics g, int x, int y, bool on, bool hot)
        {
            int s = Sc(14);
            Pix.Round(g, Pix.C(0x9A6338), x, y, s, s, U);
            Pix.Box(g, on ? Pix.C(0xDDF2C8) : (hot ? Pix.C(0xFFF3D6) : CPaper), x + U, y + U, s - 2 * U, s - 2 * U);
            if (on) Pix.Mono(g, Pix.CHECK, Pix.C(0x3F8A30), x + U, y + U, U);
        }

        // 小按鈕（24 高）：奶油色、深色邊、下緣一條陰影
        void SmallBtn(Graphics g, Rectangle r, string t, bool off, bool hot)
        {
            if (off) { SmallBtnOff(g, r, t); return; }
            Pix.Round(g, Pix.Ink, r.X, r.Y, r.Width, r.Height, U);
            Color face = hot ? Pix.C(0xFFF3D6) : CBtn;
            Pix.Box(g, face, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            int sh = r.Height >= Sc(24) ? Sc(4) - U : Sc(3) - U;
            Pix.Box(g, Pix.C(0xDCC6A2), r.X + U, r.Bottom - U - sh, r.Width - 2 * U, sh);
            if (t != "") DT(g, t, fBtnS, new Rectangle(r.X, r.Y, r.Width, r.Height - sh), CText, Pix.Mid);
        }
        void SmallBtnOff(Graphics g, Rectangle r, string t)
        {
            Pix.Round(g, Pix.C(0xBBA98C), r.X, r.Y, r.Width, r.Height, U);
            Pix.Box(g, Pix.C(0xE9E0D0), r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            Pix.Box(g, Pix.C(0xD3C7B2), r.X + U, r.Bottom - U - (Sc(4) - U), r.Width - 2 * U, Sc(4) - U);
            if (t != "") DT(g, t, fBtnS, new Rectangle(r.X, r.Y, r.Width, r.Height - Sc(3)), Pix.Dim, Pix.Mid);
        }
        // 大按鈕（32 高）：kind 0 一般、1 主要（蜂蜜色）、2 已複製（綠＋勾）、3 不能按
        void BigBtn(Graphics g, Rectangle r, string t, int kind, bool hot)
        {
            Color edge = kind == 2 ? Pix.C(0x2F6E24) : (kind == 3 ? Pix.C(0xBBA98C) : Pix.Ink);
            Color face = kind == 1 ? (hot ? Pix.C(0xFFD36A) : Pix.C(0xF6C453)) : (kind == 2 ? Pix.C(0xD9F0C4) : (kind == 3 ? Pix.C(0xE9E0D0) : (hot ? Pix.C(0xFFF3D6) : CBtn)));
            Color shade = kind == 1 ? Pix.C(0xC8902C) : (kind == 2 ? Pix.C(0xA9CF90) : (kind == 3 ? Pix.C(0xD3C7B2) : Pix.C(0xDCC6A2)));
            Color hi = kind == 1 ? Pix.C(0xFBE7BA) : (kind == 2 ? Pix.C(0xF0F9E8) : Pix.C(0xFFFEF9));
            Pix.Round(g, edge, r.X, r.Y, r.Width, r.Height, U);
            Pix.Box(g, face, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            Pix.Box(g, shade, r.X + U, r.Bottom - U - Sc(4), r.Width - 2 * U, Sc(4));
            if (kind != 3) Pix.Box(g, hi, r.X + U, r.Y + U, r.Width - 2 * U, U);
            Color tc = kind == 2 ? Pix.C(0x2B5420) : (kind == 3 ? Pix.Dim : CText);
            int tw = TW(t, fBtn), x = r.X + (r.Width - tw) / 2;
            if (kind == 2) { x += (5 * U + Sc(6)) / 2; Pix.Mono(g, Pix.CHECK, Pix.C(0x2F6E24), x - Sc(6) - 5 * U, r.Y + (r.Height - Sc(4)) / 2 - 5 * U / 2, U); }
            DT(g, t, fBtn, new Rectangle(x, r.Y, tw + 4, r.Height - Sc(4)), tc, Pix.LeftMid);
        }

        void DrawIcon(Graphics g, string src, int x, int y)
        {
            Dictionary<char, Color> p = new Dictionary<char, Color>();
            p['k'] = Pix.Ink;
            string[] a;
            switch (src)
            {
                case "claude": case "codex": a = ICLAUDE; p['d'] = Pix.C(0x5A4632); p['g'] = Pix.C(0xF4A06A); break;
                case "jira": a = IJIRA; p['b'] = Pix.C(0x6E9BD8); p['w'] = Pix.C(0xE4EEFA); break;
                case "github": case "gitlab": a = IMR; p['p'] = Pix.C(0xA585D4); break;
                case "calendar": a = IMEET; p['r'] = Pix.C(0xE07856); p['w'] = CPaper; break;
                case "school": a = ICLASS; p['g'] = Pix.C(0x6FB25C); p['w'] = CPaper; break;
                default: a = IHW; p['w'] = CPaper; break;
            }
            Pix.Art(g, a, p, x, y, U);
        }

        // ---- 字 ----
        class Run { public string S; public Font F; public Color C; public bool Keep, KeepNext; public Run(string s, Font f, Color c) { S = s; F = f; C = c; } }   // Keep：結果字不拆開；KeepNext：逗號跟下一個字一起換行
        readonly Dictionary<string, int> tw = new Dictionary<string, int>();
        int TW(string s, Font f)
        {
            string k = f.Size + (f.Bold ? "b" : "r") + "|" + s;
            int v;
            if (tw.TryGetValue(k, out v)) return v;
            if (tw.Count > 4000) tw.Clear();
            v = s == "" ? 0 : (int)Math.Ceiling(Measure(s, f) - 0.01f);
            tw[k] = v;
            return v;
        }
        // TextRenderer 預設不管 Graphics 的裁切：捲動的紙上要保留裁切，字才不會畫到紙外面
        // 字一律用 GDI+ 反鋸齒（AntiAliasGridFit）畫：
        //   TextRenderer（GDI）畫正黑體粗體 11pt 這種小字會用字型裡內嵌的點陣字，筆畫擠成一團（遠端桌面、截圖都一樣）；
        //   GDI+ 一定畫外框、灰階反鋸齒，跟系統的字型平滑設定無關，所以螢幕上跟離屏截圖長得一樣。起點對齊整數像素，筆畫才不會糊。
        static readonly StringFormat SF = MakeSF();
        static StringFormat MakeSF()
        {
            StringFormat f = (StringFormat)StringFormat.GenericTypographic.Clone();
            f.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces | StringFormatFlags.NoWrap | StringFormatFlags.NoClip;
            return f;
        }
        static Font Px(string family, float px, FontStyle st) { return new Font(family, px, st, GraphicsUnit.Pixel); }
        static float CellH(Font f)
        {
            FontFamily ff = f.FontFamily;
            return f.Size * (ff.GetCellAscent(f.Style) + ff.GetCellDescent(f.Style)) / ff.GetEmHeight(f.Style);
        }
        static void DT(Graphics g, string s, Font f, Rectangle r, Color c, TextFormatFlags fl)
        {
            if (string.IsNullOrEmpty(s)) return;
            float w = Measure(s, f), h = CellH(f), x = r.X, y = r.Y;
            if ((fl & TextFormatFlags.HorizontalCenter) != 0) x = r.X + (r.Width - w) / 2f;
            else if ((fl & TextFormatFlags.Right) != 0) x = r.Right - w;
            if ((fl & TextFormatFlags.VerticalCenter) != 0) y = r.Y + (r.Height - h) / 2f;
            else if ((fl & TextFormatFlags.Bottom) != 0) y = r.Bottom - h;
            Draw(g, s, f, c, x, y);
        }
        static void DT(Graphics g, string s, Font f, Point p, Color c, TextFormatFlags fl) { if (!string.IsNullOrEmpty(s)) Draw(g, s, f, c, p.X, p.Y); }
        static void Draw(Graphics g, string s, Font f, Color c, float x, float y)
        {
            TextRenderingHint was = g.TextRenderingHint;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            using (SolidBrush b = new SolidBrush(c))
            {
                g.DrawString(s, f, b, (float)Math.Round(x), (float)Math.Round(y), SF);
                g.DrawString(s, f, b, (float)Math.Round(x) + PixText.Heft, (float)Math.Round(y), SF);   // 粗細跟 mockup 一樣（DeskPals.PixText.cs）
            }
            g.TextRenderingHint = was;
        }
        static Bitmap measureBmp;
        static Graphics measureG;
        static float Measure(string s, Font f)
        {
            if (measureG == null) { measureBmp = new Bitmap(1, 1); measureG = Graphics.FromImage(measureBmp); measureG.TextRenderingHint = TextRenderingHint.AntiAliasGridFit; }
            return measureG.MeasureString(s, f, PointF.Empty, SF).Width;
        }
        // 畫的時候用同一個 Graphics 量（螢幕跟離屏點陣圖的字寬可能差一點，不然字跟字之間會空一格）
        int TWg(Graphics g, string s, Font f)
        {
            return TW(s, f);   // GDI+ 的像素字型：量出來跟在哪裡畫無關
        }
        string Ellipsis(string s, Font f, int w0)
        {
            if (TW(s, f) <= w0) return s;
            for (int n = s.Length - 1; n > 0; n--) { string t = s.Substring(0, n) + "…"; if (TW(t, f) <= w0) return t; }
            return "…";
        }
        static string RunsText(List<Run> runs) { StringBuilder sb = new StringBuilder(); foreach (Run r in runs) sb.Append(r.S); return sb.ToString(); }
        int FlowW(List<Run> runs) { int x = 0; foreach (Run r in runs) x += TW(r.S, r.F); return x; }

        // 字的上緣到基準線（GDI 的 cell ascent）
        readonly Dictionary<Font, int> asc = new Dictionary<Font, int>();
        int Asc(Font f)
        {
            int v;
            if (asc.TryGetValue(f, out v)) return v;
            FontFamily ff = f.FontFamily;
            double px = f.Unit == GraphicsUnit.Pixel ? f.Size : f.SizeInPoints * 96.0 * d / 72.0;
            v = (int)Math.Round(px * ff.GetCellAscent(f.Style) / ff.GetEmHeight(f.Style));
            asc[f] = v;
            return v;
        }

        // 一串不同字型的字照寬度排，超過就換行（中文一個字一個字斷、英文盡量在空白斷）；回傳幾行。g＝null 只量不畫
        int Flow(Graphics g, List<Run> runs, int x0, int y0, int w0, int lineH, bool strike) { return Flow(g, runs, x0, y0, w0, lineH, strike, true); }
        int Flow(Graphics g, List<Run> runs, int x0, int y0, int w0, int lineH, bool strike, bool paint)
        {
            int mainAsc = runs.Count > 0 ? Asc(runs[0].F) : 0;
            int baseOff = (lineH + mainAsc - (int)Math.Round(mainAsc * 0.32)) / 2;
            return FlowCore(g, runs, x0, y0, w0, lineH, strike, 0, baseOff, paint);
        }
        int FlowHang(Graphics g, List<Run> runs, int x0, int y0, int w0, int lineH, int hang)
        {
            int mainAsc = runs.Count > 0 ? Asc(runs[0].F) : 0;
            return FlowCore(g, runs, x0, y0, w0, lineH, false, hang, (lineH + mainAsc - (int)Math.Round(mainAsc * 0.32)) / 2, true);
        }
        int FlowLines(Graphics g, List<Run> runs, int x0, int y0, int w0, int lineH, int baseline)
        {
            return FlowCore(g, runs, x0, y0, w0, lineH, false, 0, baseline - y0, true);
        }
        int FlowCore(Graphics g, List<Run> runs, int x0, int y0, int w0, int lineH, bool strike, int hang, int baseOff, bool paint)
        {
            int x = x0, line = 0;
            for (int ri = 0; ri < runs.Count; ri++)
            {
                Run r = runs[ri];
                string s = r.S;
                if (r.Keep || r.KeepNext)
                {
                    int need = TWg(g, s, r.F) + (r.KeepNext && ri + 1 < runs.Count ? TWg(g, runs[ri + 1].S, runs[ri + 1].F) : 0);
                    if (x + need > x0 + w0 && x > x0 + hang && need <= w0 - hang) { line++; x = x0 + hang; }
                }
                while (s.Length > 0)
                {
                    int room = x0 + w0 - x, n = Fit(g, s, r.F, room);
                    if (n == 0)
                    {
                        if (x == x0 + (line > 0 ? hang : 0)) n = 1;   // 一個字都放不下：硬放
                        else { line++; x = x0 + hang; if (s.StartsWith(" ")) s = s.TrimStart(' '); continue; }
                    }
                    string part = s.Substring(0, n);
                    int pw = TWg(g, part, r.F);
                    if (g != null && paint)
                    {
                        int top = y0 + line * lineH + baseOff - Asc(r.F);
                        DT(g, part, r.F, new Point(x, top), r.C, TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine);
                        if (strike) Pix.Box(g, r.C, x, y0 + line * lineH + baseOff - (int)Math.Round(Asc(runs[0].F) * 0.36), pw, Sc(2));
                    }
                    x += pw;
                    s = s.Substring(n);
                    if (s.Length > 0) { line++; x = x0 + hang; s = s.TrimStart(' '); }
                }
            }
            return line + 1;
        }
        // 放得下幾個字（英文單字不從中間切，除非整個字就比一行長）
        int Fit(Graphics g, string s, Font f, int room)
        {
            if (room <= 0) return 0;
            if (TWg(g, s, f) <= room) return s.Length;
            int lo = 0, hi = s.Length;
            while (lo < hi) { int mid = (lo + hi + 1) / 2; if (TWg(g, s.Substring(0, mid), f) <= room) lo = mid; else hi = mid - 1; }
            if (lo > 0 && lo < s.Length && IsWord(s[lo]) && IsWord(s[lo - 1]))
            {
                int b = lo;
                while (b > 0 && IsWord(s[b - 1])) b--;
                if (b > 0) lo = b;
            }
            return lo;
        }
        static bool IsWord(char c) { return c < 128 && (char.IsLetterOrDigit(c) || c == '.' || c == '-' || c == '_' || c == '/' || c == '#' || c == '!'); }

        // ================= 測試用：現在畫了什麼 =================
        // 離屏：沒有 WM_PAINT，要先畫一次才知道東西在哪（點擊、nb-info）
        public void Render()
        {
            if (Width <= 0 || Height <= 0) return;
            using (Bitmap b = new Bitmap(Width, Height, PixelFormat.Format24bppRgb))
            using (Graphics g = Graphics.FromImage(b)) OnPaint(new PaintEventArgs(g, new Rectangle(0, 0, Width, Height)));
        }
        public string Info()
        {
            Render();
            StringBuilder sb = new StringBuilder();
            sb.Append("nb open=1 tab=" + Tab + " spread=" + (Spread ? 1 : 0) + " preview=" + (Preview ? 1 : 0) + " kind=" + PvKind + " links=" + (Links ? 1 : 0) + " day=" + Nb.Ymd(Day)
                + " x=" + Left + " y=" + Top + " w=" + Width + " h=" + Height + " frame=" + (Left + OV) + " todos=" + todos.Count + " jira=" + jira.Count + " things=" + things.Count + " on=" + Nb.OnCount(things)
                + " copied=" + (copied == "" ? "-" : copied) + " saved=" + (savedAt == "" ? "-" : savedAt) + " edit=" + (editThing != "" ? editThing : (editTodo != "" ? editTodo : "-")) + "\n");
            foreach (string s in Drawn) sb.Append(s + "\n");
            foreach (Hit h in hits) if (h.Act != "row") sb.Append("hit " + h.Act + " " + (h.Arg == "" ? "-" : h.Arg) + " " + (h.R.X + Left) + " " + (h.R.Y + Top) + " " + h.R.Width + " " + h.R.Height + "\n");
            foreach (NbTodo t in todos) sb.Append("todoitem " + t.Id + " " + (t.Src == "" ? "mine" : t.Src) + " " + (t.Due == "" ? "-" : t.Due) + " " + t.Created + " " + t.Text + "\n");
            sb.Append("notetext " + new JavaScriptSerializer().Serialize(note.Text.Replace("\r\n", "\n")) + "\n");
            return sb.ToString();
        }
        public void Type(string box, string s)
        {
            if (box == "todo") tbTodo.Text = s;
            else if (box == "done") tbDone.Text = s;
            else if (box == "edit") tbEdit.Text = s;
            else if (box == "note") { note.Text = s; noteDirty = true; noteSaveAt = w.Now + 0.7; }   // 沒有 handle 的 RichTextBox 不一定會送 TextChanged
            Invalidate();
        }
    }

    partial class World
    {
        NotebookForm nbForm;
        string nbClip = "", nbSaid = "";
        public DateTime NbNow() { return SNow(); }
        public bool NbReduced() { return !SystemInformation.UIEffectsEnabled; }   // 減少動態：勾掉的那一行留短一點

        // 小屋選單／公仔選單「小本子…」
        public void ShowNotebook() { ShowNotebook(""); }
        public void ShowNotebook(string tab)
        {
            bool fresh = nbForm == null || nbForm.IsDisposed;
            if (fresh)
            {
                nbForm = new NotebookForm(this);
                Dictionary<string, string> ui = NbUi();
                string t;
                nbForm.Tab = ui.TryGetValue("tab", out t) && (t == "todo" || t == "done" || t == "note") ? t : "done";   // 第一次打開停在今天做了
                nbForm.LastTab = nbForm.Tab;
                nbForm.Spread = ui.TryGetValue("spread", out t) && t == "1";
            }
            if (tab == "todo" || tab == "done" || tab == "note") { nbForm.Tab = tab; nbForm.LastTab = tab; nbForm.Spread = false; }
            nbForm.Day = NbNow().Date;
            nbForm.Reload();
            NbPlace(nbForm);
            nbForm.Show();
            App.LogAlways("notebook: open tab=" + nbForm.Tab + " spread=" + (nbForm.Spread ? 1 : 0));
            if (App.Offscreen) return;
            ActivateForm(nbForm);
            nbForm.Do("focus", "");
        }

        // 停在公仔櫃左邊（櫃子收起來：小紙箱左邊），底部離工作列 8px；攤開時往左長
        public void NbPlace(NotebookForm f)
        {
            Rectangle anchor = shelf == null ? Rectangle.Empty : (shelf.Collapsed ? shelf.EggScreen() : shelf.Area);
            Rectangle wa = anchor.IsEmpty ? screens[0].WorkingArea : Screen.FromPoint(new Point(anchor.X + anchor.Width / 2, anchor.Y + anchor.Height / 2)).WorkingArea;
            Size sz = f.Want;
            int gap = (int)Math.Round(16 * S / 4.0), ov = sz.Width - f.FrameW;
            int right = anchor.IsEmpty ? wa.Right - gap : anchor.X - gap;
            int x = right - sz.Width, y = wa.Bottom - (int)Math.Round(8 * S / 4.0) - sz.Height;
            x = Math.Max(wa.Left - ov, Math.Min(x, wa.Right - sz.Width));
            y = Math.Max(wa.Top, y);
            f.Bounds = new Rectangle(x, y, sz.Width, sz.Height);
            f.Invalidate();
        }

        public void NbClosed(NotebookForm f) { if (nbForm == f) nbForm = null; }

        Dictionary<string, string> NbUi()
        {
            Dictionary<string, string> d = new Dictionary<string, string>();
            foreach (string line in Nb.ReadFile(Path.Combine(Nb.Dir(DataDir), "ui.txt")).Split('\n'))
            {
                int i = line.IndexOf('=');
                if (i > 0) d[line.Substring(0, i).Trim()] = line.Substring(i + 1).Trim();
            }
            return d;
        }
        public void NbSaveUi(NotebookForm f) { Nb.WriteFile(Path.Combine(Nb.Dir(DataDir), "ui.txt"), "tab=" + (f.Spread ? f.LastTab : f.Tab) + "\nspread=" + (f.Spread ? 1 : 0) + "\n"); }

        // 複製：真的剪貼簿（離屏測試只記住，不碰測試機的剪貼簿）
        public void NbClipboard(string s)
        {
            nbClip = s;
            App.LogAlways("notebook: copied " + s.Length + " chars");
            if (App.Offscreen) return;
            try { Clipboard.SetText(s.Replace("\n", "\r\n")); } catch (Exception ex) { App.Log("notebook clipboard: " + ex.Message); }
        }

        // 櫃子裡的公仔冒泡泡（櫃子收起來、或大家都在外面：帶頭那隻）
        public void NbSay(string s)
        {
            Pet p = null;
            if (shelf != null && !shelf.Collapsed && !Single) foreach (Pet x in Pets) if (!x.Out) { p = x; break; }
            if (p == null) p = Lead();
            if (p == null) return;
            nbSaid = s;
            p.Say(s, 3);
        }

        // ---- 學校行事曆：今天上過的課（從 ICS 算，不寫進 log）----
        readonly Dictionary<string, SchoolFeed> nbFeeds = new Dictionary<string, SchoolFeed>();
        List<KeyValuePair<string, string>> NbFeedTexts()
        {
            List<KeyValuePair<string, string>> l = new List<KeyValuePair<string, string>>();
            if (testFeeds.Count > 0) { l.AddRange(testFeeds); return l; }
            List<string> urls;
            lock (schoolUrls) urls = new List<string>(schoolUrls);
            foreach (string u in urls)
            {
                if (u == workCal) continue;
                string tx = ReadText(CacheName(u));
                if (tx != "") l.Add(new KeyValuePair<string, string>(u, tx));
            }
            return l;
        }
        public string NbSchoolStamp()
        {
            if (!studyLoaded) LoadStudy();
            return deadlines.Count + ":" + studyDone.Count + ":" + testFeeds.Count + ":" + (int)(NbNow() - NbNow().Date).TotalMinutes / 5;
        }
        public List<NbFact> NbClasses(DateTime day)
        {
            List<NbFact> list = new List<NbFact>();
            if (!studyLoaded) LoadStudy();
            DateTime now = NbNow();
            long from = UnixMs(day.Date), to = UnixMs(day.Date.AddDays(1) < now ? day.Date.AddDays(1) : now);
            if (to <= from) return list;
            foreach (KeyValuePair<string, string> kv in NbFeedTexts())
            {
                SchoolFeed feed;
                string key = kv.Key + "|" + kv.Value.Length + "|" + kv.Value.GetHashCode();
                if (!nbFeeds.TryGetValue(key, out feed))
                {
                    try { feed = School.Feed(kv.Key, kv.Value); } catch (Exception ex) { App.Log("notebook ics: " + ex.Message); continue; }
                    if (nbFeeds.Count > 20) nbFeeds.Clear();
                    nbFeeds[key] = feed;
                }
                foreach (IcsOcc o in Ics.Occurrences(feed.Events, from, to))
                {
                    if (o.Start < from || o.Start > to || School.Classify(o.Ev, feed, o.Parent) != "class") continue;
                    NbFact f = new NbFact();
                    string name = System.Text.RegularExpressions.Regex.Replace(System.Text.RegularExpressions.Regex.Replace(o.Summary ?? "", @"[\r\n]+", " ").Trim(), @"\s*\[([^\]]+)\]$", feed.Kind == "canvas" ? "（$1）" : " [$1]");
                    if (name == "") continue;
                    f.Id = "class:" + o.Uid + "@" + o.Start; f.Src = "school"; f.Class = true; f.Title = name; f.Project = name;
                    f.T = FromUnixMs(o.Start); f.End = FromUnixMs(o.End); f.HasEnd = o.End > o.Start;
                    list.Add(f);
                }
            }
            return list;
        }

        // ---- 待辦：自己寫的＋學校的作業（還沒交、14 天內）；新的作業放最上面（照截止時間）----
        public List<NbTodo> NbTodos()
        {
            if (!studyLoaded) LoadStudy();
            string dir = Nb.Dir(DataDir);
            List<NbTodo> list = Nb.LoadTodos(dir);
            bool changed = false;
            for (int i = list.Count - 1; i >= 0; i--)
                if (list[i].Src == "school" && studyDone.Contains(list[i].Ref)) { list.RemoveAt(i); changed = true; }   // 在別的地方標成交了
            List<NbTodo> fresh = new List<NbTodo>();
            foreach (Deadline dl in deadlines)
            {
                if (studyDone.Contains(dl.Id)) continue;
                bool have = false;
                foreach (NbTodo t in list) if (t.Src == "school" && t.Ref == dl.Id) { have = true; if (t.Due != Nb.DueValue(FromUnixMs(dl.Due).Date, (int)FromUnixMs(dl.Due).TimeOfDay.TotalMinutes)) { t.Due = Nb.DueValue(FromUnixMs(dl.Due).Date, (int)FromUnixMs(dl.Due).TimeOfDay.TotalMinutes); changed = true; } }
                if (have) continue;
                NbTodo n = new NbTodo();
                DateTime due = FromUnixMs(dl.Due);
                n.Id = "s" + Math.Abs(dl.Id.GetHashCode()).ToString("x"); n.Src = "school"; n.Ref = dl.Id; n.Text = dl.Title; n.Course = dl.Course;
                n.Due = Nb.DueValue(due.Date, (int)due.TimeOfDay.TotalMinutes); n.Created = Nb.Ymd(NbNow());
                fresh.Add(n);
            }
            if (fresh.Count > 0) { list.InsertRange(0, fresh); changed = true; }
            if (changed) Nb.SaveTodos(dir, list);
            return list;
        }
        public void NbSaveTodos(List<NbTodo> list) { Nb.SaveTodos(Nb.Dir(DataDir), list); }

        // 學校的作業：勾掉＝交了（跟泡泡上點「交了」同一套，VS Code 也會知道）；取消勾＝還沒交
        public void NbSchoolDone(string id, bool done)
        {
            if (!studyLoaded) LoadStudy();
            if (done) { MarkDone(id, true); return; }
            studyDone.Remove(id);
            WriteText("study-done.txt", string.Join("\n", new List<string>(studyDone).ToArray()));
            if (testFeeds.Count > 0) RescanNow(); else replan = true;
        }
        public void NbForgetSchool(string id) { if (!studyLoaded) LoadStudy(); MarkDone(id, true); }

        // ---- 離屏截圖 ----
        void NbSnap(Graphics g) { if (nbForm != null && !nbForm.IsDisposed && nbForm.VVisible) nbForm.PaintTo(g); }

        // ---- pipe ----
        bool NbMsg(Client c, string[] p, string line)
        {
            if (!p[0].StartsWith("nb-")) return false;
            string t = line.Trim();
            NotebookForm f = nbForm != null && !nbForm.IsDisposed ? nbForm : null;
            switch (p[0])
            {
                case "nb-open": ShowNotebook(p.Length >= 2 ? p[1] : ""); break;
                case "nb-close": if (f != null) f.Close(); break;
                case "nb-info": Send(c, (f != null ? f.Info() : "nb open=0\n") + "said " + (nbSaid == "" ? "-" : nbSaid) + "\nend\n"); break;
                case "nb-clip": Send(c, "clip " + new JavaScriptSerializer().Serialize(nbClip) + "\nend\n"); break;
                case "nb-text": if (f != null) Send(c, "text " + new JavaScriptSerializer().Serialize(f.CopyText(p.Length >= 2 ? p[1] : "detail")) + "\nend\n"); else Send(c, "text \"\"\nend\n"); break;
                case "nb-reload": if (f != null) f.Reload(); break;
                default:
                    if (f == null || !App.Offscreen) break;
                    switch (p[0])
                    {
                        case "nb-act": if (p.Length >= 2) f.Do(p[1], p.Length >= 3 ? t.Substring(NthSpace(t, 2) + 1) : ""); break;
                        case "nb-click": { int x, y; if (p.Length >= 3 && int.TryParse(p[1], out x) && int.TryParse(p[2], out y)) { f.SimHover(new Point(x - f.Left, y - f.Top)); f.SimClick(new Point(x - f.Left, y - f.Top)); } } break;
                        case "nb-hover": { int x, y; if (p.Length >= 3 && int.TryParse(p[1], out x) && int.TryParse(p[2], out y)) f.SimHover(new Point(x - f.Left, y - f.Top)); } break;
                        case "nb-hoverthing": f.HoverThing(p.Length >= 2 ? p[1] : ""); break;
                        case "nb-hovertodo": f.HoverTodo(p.Length >= 2 ? p[1] : ""); break;
                        case "nb-type": if (p.Length >= 2) f.Type(p[1], p.Length >= 3 ? t.Substring(NthSpace(t, 2) + 1).Replace("\\n", "\n") : ""); break;
                        case "nb-key":
                            if (p.Length >= 2 && p[1] == "alt-up") f.Do("move", "up");
                            else if (p.Length >= 2 && p[1] == "alt-down") f.Do("move", "down");
                            else if (p.Length >= 3) f.Key(p[1], p[2]);
                            break;
                        case "nb-drag": { int to; if (p.Length >= 3 && int.TryParse(p[2], out to)) f.DragTo(p[1], to); } break;
                        case "nb-scroll": { int dy; if (p.Length >= 3 && int.TryParse(p[2], out dy)) f.ScrollBy(p[1], dy); } break;
                    }
                    break;
            }
            return true;
        }
    }
}
