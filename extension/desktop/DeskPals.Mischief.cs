// Desk Pals：搗蛋（四個惡作劇）——搶游標、下班清場、購物警察、打字太兇。會讓人想錄螢幕分享的那種瞬間。
// 開關在公仔小屋 →「搗蛋（惡作劇開關）」（VS Code 設定 deskPals.mischief.* 有填的話以 VS Code 為準）；搶游標、打字太兇預設關著。
// 公開版（App.Public，上架／公開下載）：四個全部預設關；你在小屋第一次打開某一個時，先跳說明（MisAskForm：會做什麼、怎麼叫回來、
//   不會記錄什麼），按「好，打開」才真的打開。打開過（或 VS Code 設定裡自己打開）的記在 mischief-consent.txt，之後不再問。
//   舊使用者（這一版之前就裝了）第一次開這一版時照原本的開關狀態寫進去（原本開著的照開、也不再問），不會被打擾。個人版維持原樣。
//
// 安全（寫死的規則，測試也照這個驗）：
// - 不關閉、不結束任何程式。下班清場只把視窗「縮小」（Mac：隱藏那個 App），點公仔／點泡泡／小屋選單一鍵全部叫回來；
//   收工（關掉 Desk Pals）前也會先全部叫回來。
// - 打字太兇只數「放開按鍵」的次數（Windows：低階鍵盤掛鉤只把次數加一，不讀是哪個鍵；Mac：系統的按鍵計數器），
//   不記錄按了哪些鍵、不存任何內容。
// - 搶游標：你一動（滑鼠移動、按鍵、任何鍵盤滑鼠輸入）就放手；全螢幕程式、簡報、遊戲、分享螢幕、按著滑鼠鍵、躲起來、
//   安靜／專注時都不會開始；整段最多 6.5 秒。
// - 會動到真實電腦的事（移游標、縮小／叫回視窗、數按鍵、擷取視窗畫面）全部經過 MisSys；離屏測試（DESKPALS_OFFSCREEN）
//   一律換成 MisFake（只記錄呼叫）。DESKPALS_MISCHIEF_REAL=1 才會在離屏模式用真的（只給 CI runner 用）。
//
// 掛在核心的地方（都只有一行）：Pet.Step → MisStep()、Pet.Watch／Free → MisBusy、Pet.PaintPet → MisDraw()、
//   World.TickInner → MisTick()、OnMsg 的 default → MisMsg()、Act → "mischief"、Start → MisStart()、QuitAll → MisQuit()、
//   NoticeClicked → MisClicked()、Feat／SaveFeatures／SetFeat → MisFeatureList、HouseMenu → MisHouseMenu()、
//   Snap → MisSnapWins()／MisSnapCursor()。
// 動畫邏輯跟角色造型分開：演法用現有的狀態（走路、跳、抱、暈、跳舞）；角色專屬的演法、道具在 Pet.MisCharPose／MisPropArt。
//
// pipe 指令：
//   act mischief cursor|clear|shop|typing   馬上演一次（測試、錄宣傳片；不看開關和冷卻，安全檢查照做）
//   act mischief restore|stop               把推走的視窗叫回來／停掉正在演的
//   mischief-set grab|clear|shop|typing 0|1、mischief-set grabmin <分>     VS Code 推設定
//   mischief-dump                            目前狀態（測試用）；mischief-site <標題…> → site <網站|->（購物網站清單測試）
//   測試用（只有 MisFake）：mischief-fake cursor <x> <y>｜input｜button 0|1｜fs 0|1｜idle <秒>｜fg <標題…>｜
//     typing <每秒幾下> <秒>｜win <x> <y> <w> <h> <標題…>｜clock <yyyy-MM-ddTHH:mm|off>｜reset
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.Diagnostics;
    using System.Drawing;
    using System.Drawing.Drawing2D;
    using System.Drawing.Imaging;
    using System.Runtime.InteropServices;
    using System.Text;
    using System.Windows.Forms;

    // 一個視窗（真的：視窗代碼；假的：測試用的編號）
    class MisWin { public IntPtr H; public Rectangle R; public string Title = ""; public bool Min; }

    // ================= 會動到真實電腦的事都在這裡（離屏測試換成 MisFake）=================
    class MisSys
    {
        [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
        [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr h, int cmd);
        [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
        [DllImport("user32.dll")] static extern bool IsHungAppWindow(IntPtr h);
        [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref W.LASTINPUTINFO li);
        [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
        delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetWindowsHookEx(int id, HookProc fn, IntPtr mod, uint thread);
        [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr h);
        [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int code, IntPtr wParam, IntPtr lParam);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
        static readonly int MyPid = Process.GetCurrentProcess().Id;

        public virtual bool Fake { get { return false; } }
        public virtual DateTime Clock() { return DateTime.Now; }
        public virtual double Idle() { return W.IdleSeconds(); }
        public virtual Point CursorPos() { return Cursor.Position; }
        public virtual bool Buttons() { return Control.MouseButtons != MouseButtons.None; }
        public virtual bool Fullscreen() { return false; }   // 真的全螢幕由 World.FullscreenCheck 判斷
        // 最後一次鍵盤滑鼠輸入的時間戳：變了＝你動了
        public virtual long InputStamp()
        {
            W.LASTINPUTINFO li = new W.LASTINPUTINFO();
            li.cbSize = 8;
            return GetLastInputInfo(ref li) ? li.dwTime : 0;
        }
        public virtual void Warp(int x, int y) { SetCursorPos(x, y); }
        // 搶游標期間：你有沒有按鍵盤。不能用最後輸入時間（SetCursorPos 之後系統會非同步地更新它，會被誤當成你動了），
        // 改成只在搶游標那幾秒掃一輪按鍵狀態（GetAsyncKeyState：只看有沒有按，不記是哪個鍵）；滑鼠鍵另外看、滑鼠移動看游標偏離
        public virtual void KeyPrime() { for (int vk = 8; vk < 256; vk++) GetAsyncKeyState(vk); }   // 清掉「上次呼叫之後按過」的記號
        public virtual bool KeyPressed()
        {
            for (int vk = 8; vk < 256; vk++) if ((GetAsyncKeyState(vk) & 0x8001) != 0) return true;   // 1～6 是滑鼠鍵，不在這裡看
            return false;
        }

        // 前景視窗的標題（購物警察用；自己的視窗不算）
        public virtual string FgTitle()
        {
            IntPtr h = W.GetForegroundWindow();
            if (h == IntPtr.Zero) return "";
            int pid;
            W.GetWindowThreadProcessId(h, out pid);
            if (pid == MyPid) return "";
            StringBuilder sb = new StringBuilder(512);
            W.GetWindowText(h, sb, 512);
            return sb.ToString();
        }

        // 前面幾個一般視窗（由前到後）：不含自己、桌面、工作列、永遠在最上層的
        public virtual List<MisWin> Windows(World w, int max)
        {
            List<MisWin> l = new List<MisWin>();
            StringBuilder sb = new StringBuilder(256);
            foreach (WinInfo wi in w.Wins)
            {
                if (l.Count >= max) break;
                if (!w.Cands.ContainsKey(wi.H) || !W.IsWindowVisible(wi.H) || W.IsIconic(wi.H) || IsHungAppWindow(wi.H)) continue;   // 沒回應的程式不碰（擷取畫面會卡住）
                int pid;
                W.GetWindowThreadProcessId(wi.H, out pid);
                if (pid == MyPid) continue;
                sb.Length = 0;
                W.GetClassName(wi.H, sb, 64);
                string cls = sb.ToString();
                if (cls == "Progman" || cls == "WorkerW" || cls.StartsWith("Shell_")) continue;
                if ((W.GetWindowLong(wi.H, -20) & 0x8) != 0) continue;   // WS_EX_TOPMOST
                MisWin m = new MisWin();
                m.H = wi.H; m.R = Rectangle.FromLTRB(wi.L, wi.T, wi.R, wi.B);
                sb.Length = 0;
                W.GetWindowText(wi.H, sb, 256);
                m.Title = sb.ToString();
                l.Add(m);
            }
            return l;
        }

        // 視窗現在的樣子（只放在記憶體裡給假視窗用，演完就丟；不存檔、不送出去）。拿不到＝null（畫卡通視窗）
        public virtual Bitmap Capture(MisWin m)
        {
            W.RECT wr;
            if (!W.GetWindowRect(m.H, out wr)) return null;
            int ww = wr.R - wr.L, wh = wr.B - wr.T;
            if (ww <= 0 || wh <= 0 || ww > 12000 || wh > 12000) return null;
            using (Bitmap full = new Bitmap(ww, wh, PixelFormat.Format24bppRgb))
            {
                bool ok;
                using (Graphics g = Graphics.FromImage(full))
                {
                    IntPtr dc = g.GetHdc();
                    try { ok = PrintWindow(m.H, dc, 2); }   // PW_RENDERFULLCONTENT
                    finally { g.ReleaseHdc(dc); }
                }
                if (!ok) return null;
                Rectangle crop = new Rectangle(m.R.X - wr.L, m.R.Y - wr.T, m.R.Width, m.R.Height);
                crop.Intersect(new Rectangle(0, 0, ww, wh));
                if (crop.Width <= 0 || crop.Height <= 0) return null;
                int lit = 0;
                for (int i = 0; i < 64; i++)
                {
                    Color c = full.GetPixel(crop.X + (int)((i % 8 + 0.5) * crop.Width / 8), crop.Y + (int)((i / 8 + 0.5) * crop.Height / 8));
                    if (c.R + c.G + c.B > 24) lit++;
                }
                if (lit == 0) return null;   // 全黑＝沒畫出來（有些程式不支援）
                return full.Clone(crop, PixelFormat.Format24bppRgb);
            }
        }

        // 只是縮小（不關閉）；Mac 版是隱藏那個 App
        public virtual bool Minimize(MisWin m) { return ShowWindowAsync(m.H, 7); }   // SW_SHOWMINNOACTIVE
        public virtual void Restore(MisWin m, bool activate) { if (W.IsIconic(m.H)) ShowWindowAsync(m.H, 9); }   // SW_RESTORE（原本放大的會回到放大）；後面的先叫回來，最前面那個最後、拿回焦點

        // ---- 打字太兇：只數「放開按鍵」幾次。掛鉤裡不讀 lParam（哪個鍵），也不存任何東西 ----
        HookProc keyProc;
        IntPtr keyHook = IntPtr.Zero;
        long keyUps;
        public virtual long KeyCount() { return keyUps; }
        public virtual bool KeyWatching { get { return keyHook != IntPtr.Zero; } }
        public virtual void KeyWatch(bool on)
        {
            if (on == (keyHook != IntPtr.Zero)) return;
            if (on)
            {
                if (keyProc == null) keyProc = OnKey;
                keyHook = SetWindowsHookEx(13, keyProc, GetModuleHandle(null), 0);   // WH_KEYBOARD_LL
                App.Log("mischief: key counter " + (keyHook != IntPtr.Zero ? "on" : "failed " + Marshal.GetLastWin32Error()));
            }
            else
            {
                UnhookWindowsHookEx(keyHook);
                keyHook = IntPtr.Zero;
                App.Log("mischief: key counter off");
            }
        }
        IntPtr OnKey(int code, IntPtr wParam, IntPtr lParam)
        {
            if (code >= 0) { int m = wParam.ToInt32(); if (m == 0x101 || m == 0x105) keyUps++; }   // WM_KEYUP／WM_SYSKEYUP
            return CallNextHookEx(keyHook, code, wParam, lParam);
        }
        // Mac 要「輸入監控」權限（使用者自己打開開關時才問一次）；Windows 不用
        public virtual void AskKeyPermission() { }
        public virtual string Dump() { return ""; }
    }

    // ================= 測試用：什麼都不真的做，只記錄 =================
    class MisFake : MisSys
    {
        public Point Cur = new Point(700, 420);
        public bool Btn, Fs, Watching;
        public long Stamp;
        public double IdleSec, T, Rate, RateUntil, RateLast, RateAcc;
        public string Fg = "";
        public TimeSpan Shift = TimeSpan.Zero;
        public int Warps, Asked;
        public Point LastWarp;
        public readonly List<MisWin> Wins = new List<MisWin>();      // 最前面的在 [0]
        public readonly List<string> Calls = new List<string>();
        int nextH = 0x7100;

        public override bool Fake { get { return true; } }
        public override DateTime Clock() { return DateTime.Now + Shift; }
        public override double Idle() { return IdleSec; }
        public override Point CursorPos() { return Cur; }
        public override bool Buttons() { return Btn; }
        public override bool Fullscreen() { return Fs; }
        // 跟真的系統一樣：移游標之後「最後輸入時間」會（晚一點、非同步地）被更新——第一次讀還是舊的，下一次就變新的
        int warpPending;
        public override long InputStamp() { if (warpPending == 1) warpPending = 2; else if (warpPending == 2) { Stamp += 50; warpPending = 0; } return Stamp; }
        public override void Warp(int x, int y) { Cur = new Point(x, y); LastWarp = Cur; Warps++; warpPending = 1; }
        public bool KeyDown;                                      // mischief-fake input：假裝你按了鍵盤
        public override void KeyPrime() { KeyDown = false; }
        public override bool KeyPressed() { return KeyDown; }
        public override string FgTitle() { return Fg; }
        public void AddWin(Rectangle r, string title)
        {
            MisWin m = new MisWin();
            m.H = new IntPtr(nextH++); m.R = r; m.Title = title;
            Wins.Insert(0, m);
        }
        public override List<MisWin> Windows(World w, int max)
        {
            List<MisWin> l = new List<MisWin>();
            foreach (MisWin m in Wins) if (!m.Min && l.Count < max) l.Add(m);
            return l;
        }
        public override Bitmap Capture(MisWin m) { Calls.Add("capture " + m.Title); return null; }
        public override bool Minimize(MisWin m) { m.Min = true; Calls.Add("minimize " + m.Title); return true; }
        public override void Restore(MisWin m, bool activate) { if (m.Min) { m.Min = false; Calls.Add("restore " + m.Title + (activate ? " (front)" : "")); } }
        public override long KeyCount()
        {
            double end = Math.Min(T, RateUntil);
            if (end > RateLast) { if (Watching) RateAcc += (end - RateLast) * Rate; RateLast = end; }
            return (long)RateAcc;
        }
        public override bool KeyWatching { get { return Watching; } }
        public override void KeyWatch(bool on) { if (on != Watching) { Watching = on; Calls.Add("keywatch " + (on ? "on" : "off")); } }
        public override void AskKeyPermission() { Asked++; Calls.Add("ask-permission"); }
        public override string Dump()
        {
            StringBuilder sb = new StringBuilder();
            sb.Append("fake cursor=" + Cur.X + "," + Cur.Y + " warps=" + Warps + " lastwarp=" + LastWarp.X + "," + LastWarp.Y + " keys=" + KeyCount() + " watching=" + (Watching ? 1 : 0) + " asked=" + Asked + "\n");
            foreach (MisWin m in Wins) sb.Append("win " + m.R.X + "," + m.R.Y + "," + m.R.Width + "," + m.R.Height + " min=" + (m.Min ? 1 : 0) + " " + m.Title + "\n");
            foreach (string c in Calls) sb.Append("call " + c + "\n");
            return sb.ToString();
        }
    }

    // 公開版：搗蛋第一次打開前的說明（像素風，跟第一次設定視窗同一套）。按「好，打開」才打開；「先不要」、Esc、關掉視窗＝不打開
    class MisAskForm : Form
    {
        readonly World w;
        public readonly string Key;
        readonly string name;
        readonly string[][] parts;
        readonly double d;
        readonly int U;
        readonly Font titleF, qF, headF, bodyF, btnF;
        readonly Rectangle okR, noR;
        string hoverId = "";
        bool done;
        public bool VVisible;

        public MisAskForm(World w, string key, string name, string[][] parts)
        {
            this.w = w; Key = key; this.name = name; this.parts = parts;
            d = w.S / 4.0;
            U = Math.Max(2, (int)Math.Round(2 * d));
            Text = "公仔櫃・搗蛋說明";
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false; MinimizeBox = false;
            ShowInTaskbar = true; TopMost = true;
            StartPosition = FormStartPosition.Manual;
            BackColor = Pix.Cream;
            DoubleBuffered = true;
            titleF = new Font("Microsoft JhengHei UI", 12f, FontStyle.Bold);
            qF = new Font("Microsoft JhengHei UI", 15f, FontStyle.Bold);
            headF = new Font("Microsoft JhengHei UI", 10f, FontStyle.Bold);
            bodyF = new Font("Microsoft JhengHei UI", 10f, FontStyle.Regular);
            btnF = new Font("Microsoft JhengHei UI", 11f, FontStyle.Bold);
            ClientSize = new Size(Sc(540), Sc(500));
            int by = ClientSize.Height - Sc(64), bh = Sc(44);
            noR = new Rectangle(Sc(30), by, Sc(150), bh);
            okR = new Rectangle(ClientSize.Width - Sc(30) - Sc(180), by, Sc(180), bh);
            KeyPreview = true;
            KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Escape) Press("no"); };
            FormClosed += delegate { if (!done) { done = true; w.MisAskDone(this, false); } };   // 按右上角關掉＝先不要
        }

        int Sc(int v) { return (int)Math.Round(v * d); }

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
                g.DrawImageUnscaled(b, Left, Top);
            }
        }

        // ok＝好，打開；no＝先不要（滑鼠、Esc、測試的 act mischief consent:ok|no）
        public void Press(string id)
        {
            if (done) return;
            done = true;
            Close();
            w.MisAskDone(this, id == "ok");
        }

        string At(Point p) { return okR.Contains(p) ? "ok" : (noR.Contains(p) ? "no" : ""); }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            string h = At(e.Location);
            if (h != hoverId) { hoverId = h; Cursor = h != "" ? Cursors.Hand : Cursors.Default; Invalidate(); }
        }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); if (hoverId != "") { hoverId = ""; Invalidate(); } }
        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (e.Button != MouseButtons.Left) return;
            string h = At(e.Location);
            if (h != "") Press(h);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.None;
            int W0 = ClientSize.Width, H0 = ClientSize.Height, F = 4 * U, crown = Sc(56);
            Pix.Wood(g, 0, 0, W0, H0, U, false, 23);
            Pix.Panel(g, F, crown, W0 - 2 * F, H0 - crown - F, U, false);
            string t = "搗蛋說明";
            int tw = Pix.TextW(t, titleF), plw = tw + 14 * U, plh = Sc(34);
            Pix.Plate(g, t, titleF, new Rectangle((W0 - plw) / 2, (crown - plh) / 2 + U / 2, plw, plh), U);
            TextRenderer.DrawText(g, "打開「" + name + "」？", qF, new Rectangle(0, Sc(72), W0, Sc(32)), Pix.TextC, Pix.Mid);
            int y = Sc(116);
            foreach (string[] part in parts)
            {
                int hw = Pix.TextW(part[0], headF) + Sc(20);
                Pix.Round(g, Pix.C(0x8A5A2A), Sc(34), y, hw, Sc(26), U);
                Pix.Box(g, Pix.C(0xF6C453), Sc(34) + U, y + U, hw - 2 * U, Sc(26) - 2 * U);
                TextRenderer.DrawText(g, part[0], headF, new Rectangle(Sc(34), y, hw, Sc(26)), Pix.TextC, Pix.Mid);
                TextRenderer.DrawText(g, part[1], bodyF, new Rectangle(Sc(38), y + Sc(32), W0 - Sc(76), Sc(66)), Pix.TextC, TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.WordBreak | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
                y += Sc(104);
            }
            DrawButton(g, noR, "先不要", false, hoverId == "no");
            DrawButton(g, okR, "好，打開", true, hoverId == "ok");
        }

        // 有厚度的像素按鈕（主要按鈕是蜂蜜色；跟設定視窗一樣）
        void DrawButton(Graphics g, Rectangle r, string text, bool main, bool hot)
        {
            Color face = main ? (hot ? Pix.C(0xFFD36A) : Pix.C(0xF6C453)) : (hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0));
            Color shade = main ? Pix.C(0xC8902C) : Pix.C(0xDCC6A2);
            Pix.Round(g, Pix.Ink, r.X, r.Y, r.Width, r.Height, U);
            Pix.Box(g, face, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            Pix.Box(g, shade, r.X + U, r.Bottom - 3 * U, r.Width - 2 * U, 2 * U);
            Pix.Box(g, Pix.Mix(face, Color.White, 0.6), r.X + 2 * U, r.Y + U, r.Width - 4 * U, U);
            TextRenderer.DrawText(g, text, btnF, new Rectangle(r.X, r.Y, r.Width, r.Height - 2 * U), Pix.TextC, Pix.Mid);
        }
    }

    // 下班清場的假視窗：原本那個視窗的樣子（擷取到的畫面；擷取不到就畫一個卡通視窗）。點得穿。
    class MisWinForm : OverlayForm
    {
        Bitmap img;
        readonly string title;
        static readonly Font TitleFont = new Font("Microsoft JhengHei UI", 10f, FontStyle.Bold);
        public MisWinForm(Bitmap b, string t, Rectangle r) : base(true) { img = b; title = t ?? ""; Bounds = r; }
        protected override void OnPaint(PaintEventArgs e) { DrawWin(e.Graphics, img, title, ClientSize.Width, ClientSize.Height); }
        public static void DrawWin(Graphics g, Bitmap img, string title, int wd, int ht)
        {
            if (img != null) { g.DrawImageUnscaled(img, 0, 0); return; }
            using (SolidBrush body = new SolidBrush(Color.FromArgb(0xF4, 0xF5, 0xF8)))
            using (SolidBrush bar = new SolidBrush(Color.FromArgb(0xD6, 0xDB, 0xE4)))
            using (SolidBrush line = new SolidBrush(Color.FromArgb(0xC9, 0xCF, 0xDB)))
            using (Pen edge = new Pen(Color.FromArgb(0x7A, 0x84, 0x98)))
            {
                g.FillRectangle(body, 0, 0, wd, ht);
                g.FillRectangle(bar, 0, 0, wd, Math.Min(ht, 30));
                for (int i = 0; i < 8; i++)
                {
                    int ly = 52 + i * 26;
                    if (ly + 10 > ht) break;
                    g.FillRectangle(line, 24, ly, Math.Max(10, (wd - 48) * (i % 3 == 2 ? 55 : 85) / 100), 10);
                }
                g.DrawRectangle(edge, 0, 0, wd - 1, ht - 1);
            }
            // 標題（DrawString 才會跟著 Graphics 的位移；太長就截掉）
            int max = Math.Max(1, (wd - 20) / 14);
            string tt = title.Length > max ? title.Substring(0, Math.Max(1, max - 1)) + "…" : title;
            using (SolidBrush tb = new SolidBrush(Color.FromArgb(0x2A, 0x2F, 0x45))) g.DrawString(tt, TitleFont, tb, 10, 6);
        }
        protected override void Dispose(bool disposing)
        {
            if (disposing && img != null) { img.Dispose(); img = null; }
            base.Dispose(disposing);
        }
    }

    // ================= 公仔這邊：演法（用現有的狀態）＋角色專屬的接口 =================
    partial class Pet
    {
        string misAct = "";              // 正在演哪一個：grab／cry／fly／puppet（""＝沒有）
        string misPoseNow = "idle";
        int misPh;
        double misT, misX0, misY0, misX1, misY1, misDur, misArc, misHome;
        Point misCur;                    // 搶游標：游標「應該」在的位置（不在＝你動了）
        public bool MisBusy { get { return misAct != ""; } }

        // Step 一開始呼叫：演到一半就由這裡控制（回傳 true＝這格處理完了）
        bool MisStep(double dt)
        {
            if (misAct == "") return false;
            if (dragging || state == "drag" || state == "fling" || state == "stowfly" || state == "enter" || state == "exit") { MisRelease(); return false; }
            misT += dt;
            switch (misAct)
            {
                case "grab": MisGrabStep(); break;
                case "cry": MisCryStep(dt); break;
                case "fly": MisFlyStep(dt); break;
            }
            if (misAct != "") MisPose(misPoseNow);   // 每格都套一次（別的地方改了狀態也拉回來）
            return true;
        }

        // ---- 角色專屬版本的接口 ----
        // 新角色要自己的演法就加在這裡（例如之後的「躲躲」：搶游標的 hold／run 改成把游標藏進紙箱）。
        // what：wind 準備／leap 飛撲／hold 抓到／fall、run 拖著跑／drop 放下／caught 被抓到／brace、push 推視窗／
        //       cry 抱錢包哭／fly 被震飛／dizzy 暈／back 爬回來／idle
        // 回傳 true＝這隻自己設好了狀態；false＝用通用演法
        bool MisCharPose(string what)
        {
            // 續命小隊（躲躲、沒電、刺刺）：狀態照通用的走（移動、物理不變），畫哪一張圖由 Pet.MisFrame 決定（DeskPals.Original.cs）：
            // 躲躲抓到游標收進紙箱、拖著跑用「箱子長腳逃跑」；沒電搶到游標抱著當枕頭；刺刺抱錢包哭（圖上已經有錢包和眼淚）
            return false;
        }
        // 抱著的小道具（預設：錢包）；角色專屬的道具也從這裡換
        string[] MisPropArt(string what) { return what == "cry" && !P.Orig ? MIS_WALLET : null; }   // 續命小隊的哭圖已經畫了錢包

        // 通用演法：只用現有的狀態，每個角色都畫得出來
        public void MisPose(string what)
        {
            misPoseNow = what;
            if (MisCharPose(what)) return;
            switch (what)
            {
                case "wind": poseKind = "grin"; state = "pose"; break;
                case "leap": case "fall": case "fly": state = "air"; break;
                case "hold": state = "hug"; break;
                case "run": case "push": case "back": state = "goto"; break;
                case "brace": state = "kick"; break;
                case "drop": state = "dance"; break;
                case "caught": case "dizzy": state = "dizzy"; break;
                case "cry": state = "think"; break;
                default: state = "idle"; break;
            }
        }

        public string MisLine(string key) { return Pick(World.MisLinesFor(P.Id, key)); }
        bool MisOnFloor() { return Math.Abs(y - (w.WA(Cx, y + SH / 2.0).Bottom - SH)) < 3; }

        // 演完：交還給平常的狀態（在半空中就掉下來）
        void MisFinish(string pose, double dur)
        {
            misAct = ""; rolling = false;
            w.MisPetDone(this);
            if (supH == IntPtr.Zero && !MisOnFloor()) { dizzyOnLand = pose == "caught" || pose == "dizzy"; Jump(0, 0); return; }
            MisPose(pose);
            t = dur;
        }
        // 被拖走、丟回櫃子：直接放掉
        void MisRelease() { misAct = ""; rolling = false; w.MisPetDone(this); }
        // World 叫停（全螢幕、躲起來、安靜…）
        public void MisAbort() { if (misAct != "") MisFinish("idle", 1); }

        // ---------- 搶游標 ----------
        public void MisGrab(Point c)
        {
            misAct = "grab"; misPh = 0; misT = 0; misCur = c;
            supH = IntPtr.Zero; sc = 1; rolling = false;
            dir = c.X >= Cx ? 1 : -1;
            MisPose("wind"); Mark(1);
            Say(MisLine("grab_start"), 2.6);
        }

        void MisGrabStep()
        {
            if (misT > 6.5 && misPh < 4) { MisFinish("idle", 1); return; }   // 最長幾秒：時間到就放手
            if (misPh <= 3 && w.MisUserMoved(misCur)) { MisCaught(); return; }
            switch (misPh)
            {
                case 0:   // 準備（盯著游標）
                    dir = misCur.X >= Cx ? 1 : -1;
                    if (misT >= 0.6)
                    {
                        misPh = 1; misT = 0; misX0 = x; misY0 = y;
                        misX1 = misCur.X - SW / 2.0; misY1 = misCur.Y - SH * 0.45;
                        double d = Math.Sqrt((misX1 - x) * (misX1 - x) + (misY1 - y) * (misY1 - y));
                        misDur = Clamp(d / (1100 * k), 0.45, 1.1); misArc = Math.Min(160 * k, d * 0.35);
                        MisPose("leap");
                    }
                    break;
                case 1:   // 飛撲過去
                    {
                        double f = Math.Min(1, misT / misDur);
                        x = misX0 + (misX1 - misX0) * f; y = misY0 + (misY1 - misY0) * f - Math.Sin(Math.PI * f) * misArc;
                        if (f >= 1) { misPh = 2; misT = 0; MisPose("hold"); Mark(1); Burst(6); MisHoldCursor(); }
                    }
                    break;
                case 2:   // 抓到了
                    if (!MisHoldCursor()) return;
                    if (misT >= 0.3)
                    {
                        Rectangle wa = w.WA(Cx, y + SH / 2.0);
                        int d2 = Cx - wa.Left > wa.Right - Cx ? -1 : 1;   // 往空間大的那邊跑
                        dir = d2;
                        misPh = 3; misT = 0; misX0 = x; misY0 = y; misY1 = wa.Bottom - SH;
                        misX1 = Clamp(x + d2 * 520 * k, wa.Left + 4, wa.Right - SW - 4);
                        misDur = 2.6;
                        MisPose(y < misY1 - 4 ? "fall" : "run");
                        Say(MisLine("grab_carry"), 2.2);
                    }
                    break;
                case 3:   // 拖著游標跑
                    {
                        double f = Math.Min(1, misT / misDur), fy = Math.Min(1, misT / 0.55);
                        x = misX0 + (misX1 - misX0) * Ease(f);
                        y = misY0 + (misY1 - misY0) * fy * fy;
                        if (fy >= 1 && misPoseNow != "run") MisPose("run");
                        if (!MisHoldCursor()) return;
                        if (f >= 1) { misPh = 4; misT = 0; MisPose("drop"); Burst(6); Say(MisLine("grab_drop"), 2.4); }   // 放手（游標留在這）
                    }
                    break;
                case 4:   // 嗆聲
                    if (misT >= 1.8) MisFinish("idle", 1.5);
                    break;
            }
        }

        // 游標放在手上（World 只有搶游標進行中、你沒按著滑鼠才會真的移）
        bool MisHoldCursor()
        {
            int hx = (int)Math.Round(Cx + dir * 4 * S), hy = (int)Math.Round(y + SH * 0.45);
            if (!w.MisWarp(hx, hy)) { MisCaught(); return false; }
            misCur = w.MisCursor();
            return true;
        }

        void MisCaught()
        {
            bool held = misPh >= 2;
            Say(MisLine(held ? "grab_caught" : "grab_seen"), 2.4);
            Mark(1);
            MisFinish("caught", 1.4);
        }

        // ---------- 購物警察：抱著錢包大哭 ----------
        public void MisCry(string site, int n)
        {
            misAct = "cry"; misPh = 0; misT = 0;
            MisPose("cry");
            Say(MisLine(n >= 2 ? "shop_n" : "shop").Replace("{n}", World.MisNum(n)).Replace("{site}", site), 4.5);
            Mark(4);
            if (Is("meidian") && SqBattery.Link) SqBattery.Level = Math.Max(0, SqBattery.Level - 0.02);   // 錢包痛，電也痛
        }
        void MisCryStep(double dt)
        {
            if (rnd.NextDouble() < dt * 2.5) Mark(4);
            if (misT >= 4.6) MisFinish("idle", 1.2);
        }

        // ---------- 打字太兇：被震飛、暈一下、爬回來 ----------
        public void MisFly()
        {
            misAct = "fly"; misPh = 0; misT = 0;
            Rectangle wa = w.WA(Cx, y + SH / 2.0);
            int d = Cx - wa.Left > wa.Right - Cx ? -1 : 1;
            misHome = x;
            misX0 = x; misY0 = y;
            misX1 = Clamp(x + d * R(380, 620) * k, wa.Left + 4, wa.Right - SW - 4);
            misY1 = wa.Bottom - SH;
            misDur = 1.1; misArc = 260 * k;
            supH = IntPtr.Zero; sc = 1; dir = d; rolling = true;
            MisPose("fly"); Burst(10); Mark(1);
            Say(MisLine("typing"), 2.4);
            if (Is("meidian") && SqBattery.Link) SqBattery.Level = Math.Max(0, SqBattery.Level - 0.03);   // 被震掉 3% 的電
        }
        void MisFlyStep(double dt)
        {
            switch (misPh)
            {
                case 0:
                    {
                        double f = Math.Min(1, misT / misDur);
                        x = misX0 + (misX1 - misX0) * f; y = misY0 + (misY1 - misY0) * f - Math.Sin(Math.PI * f) * misArc;
                        if (f >= 1) { rolling = false; misPh = 1; misT = 0; MisPose("dizzy"); Burst(6); }
                    }
                    break;
                case 1:
                    if (misT >= 1.3) { misPh = 2; misT = 0; dir = misHome > x ? 1 : -1; MisPose("back"); Say(MisLine("typing_back"), 2.4); }
                    break;
                case 2:
                    {
                        double sp = 70 * k * dt;
                        if (Math.Abs(misHome - x) <= sp || misT > 5) { MisFinish("idle", 1.2); break; }
                        dir = misHome > x ? 1 : -1;
                        x += dir * sp;
                    }
                    break;
            }
        }

        // ---------- 下班清場：位置由 World 控制（推視窗） ----------
        public void MisPuppet(bool on)
        {
            if (on) { misAct = "puppet"; misT = 0; supH = IntPtr.Zero; sc = 1; rolling = false; return; }
            if (misAct == "puppet") MisFinish("idle", 1.2);
        }

        // ---------- 畫：抱著的道具、眼淚（PaintPet 裡呼叫） ----------
        static readonly string[] MIS_WALLET = { ".kkkkkkk.", "kbbbbbbbk", "kbmmmmmbk", "kbbbbbggk", "kBBBBBggk", "kbbbbbbbk", ".kkkkkkk." };
        static Color MisCol(char c)
        {
            switch (c)
            {
                case 'k': return Color.FromArgb(0x2A, 0x22, 0x1E);
                case 'b': return Color.FromArgb(0xB9, 0x7A, 0x45);
                case 'B': return Color.FromArgb(0x8A, 0x55, 0x2E);
                case 'g': return Color.FromArgb(0xF2, 0xC9, 0x4C);
                case 'm': return Color.FromArgb(0x7C, 0xC6, 0x7A);
                case 't': return Color.FromArgb(0x7F, 0xC8, 0xFF);
            }
            return Color.White;
        }
        static void MisPix(Graphics g, string[] art, int bx, int by, int ps)
        {
            int hw = Math.Max(1, ps / 3);
            for (int pass = 0; pass < 2; pass++)
                for (int ry = 0; ry < art.Length; ry++)
                    for (int rx = 0; rx < art[ry].Length; rx++)
                    {
                        char c = art[ry][rx];
                        if (c == '.') continue;
                        using (SolidBrush b = new SolidBrush(pass == 0 ? Color.White : MisCol(c)))
                        {
                            if (pass == 0) g.FillRectangle(b, bx + rx * ps - hw, by + ry * ps - hw, ps + 2 * hw, ps + 2 * hw);
                            else g.FillRectangle(b, bx + rx * ps, by + ry * ps, ps, ps);
                        }
                    }
        }
        void MisDraw(Graphics g, int ox, int oy)
        {
            if (misAct != "cry" || P.Orig) return;   // 續命小隊的哭圖已經有錢包和眼淚
            string[] art = MisPropArt("cry");
            if (art != null)
            {
                int ps = Math.Max(1, S * 2 / 3), aw = art[0].Length * ps, ah = art.Length * ps;
                MisPix(g, art, (int)Math.Round(Cx - aw / 2.0) - ox, (int)Math.Round(y + SH * 0.58 - ah / 2.0) - oy, ps);
            }
            // 眼淚：兩邊往下滴
            int tp = Math.Max(1, S / 2);
            double fall = (anim * 30 * k) % (7 * S);
            using (SolidBrush tb = new SolidBrush(MisCol('t')))
                for (int s = -1; s <= 1; s += 2)
                {
                    int tx = (int)Math.Round(Cx + s * 3.5 * S) - ox, ty = (int)Math.Round(y + (P.BodyTop - 3) * S + fall) - oy;
                    g.FillRectangle(tb, tx, ty, tp, tp * 2);
                    g.FillRectangle(tb, tx, ty - 3 * tp, tp, tp);
                }
        }
    }

    // ================= World：什麼時候演、安全檢查、下班清場、設定、pipe =================
    partial class World
    {
        // 小屋「搗蛋」的開關（存在 features.txt，跟其他開關一起）；搶游標預設關著
        public static readonly string[][] MisFeatureList = {
            new string[] { "mis_grab", "搶游標（滑鼠停太久就被叼走）" },
            new string[] { "mis_clear", "下班清場（把視窗推出螢幕）" },
            new string[] { "mis_shop", "購物警察（逛購物網站會哭）" },
            new string[] { "mis_typing", "打字太兇（會被震飛）" } };
        static bool MisDefaultOff(string key) { return key.StartsWith("mis_") && (App.Public || key == "mis_grab" || key == "mis_typing"); }   // 搶游標、打字太兇預設關；公開版四個都關
        static bool MisOldDefaultOff(string key) { return key == "mis_grab" || key == "mis_typing"; }   // 這一版以前的預設（舊使用者照這個轉）

        // 購物網站：{ 顯示的名字, 視窗標題裡會出現的字… }（不分大小寫、不看空白；要加網站就加一行）
        public static readonly string[][] MisShops = {
            new string[] { "蝦皮", "蝦皮購物", "shopee" },
            new string[] { "momo", "momo購物", "momoshop" },
            new string[] { "PChome", "pchome24h", "24h購物", "pchome商店街" },
            new string[] { "露天", "露天拍賣", "露天市集", "ruten" },
            new string[] { "淘寶", "淘寶", "淘宝", "taobao", "天貓", "天猫", "tmall" },
            new string[] { "Amazon", "amazon.com", "amazon.co.jp", "amazon.co.uk", "amazon.de", "amazon.ca", "amazon.sg", "亞馬遜購物" },
            new string[] { "樂天", "樂天市場", "楽天市場", "rakutenichiba" },
            new string[] { "博客來", "博客來", "books.com.tw" },
            new string[] { "Yahoo 購物中心", "yahoo購物", "yahoo奇摩購物", "yahoo!奇摩購物", "yahoo奇摩超級商城" },
            new string[] { "AliExpress", "aliexpress", "速賣通" },
            new string[] { "酷澎", "酷澎", "coupang" },
            new string[] { "SHEIN", "shein" },
            new string[] { "Temu", "temu" },
            new string[] { "東森購物", "東森購物", "etmall" },
            new string[] { "誠品線上", "誠品線上", "eslite.com" } };

        public static string MisShopSite(string title)
        {
            string t = (title ?? "").ToLowerInvariant().Replace(" ", "");
            if (t == "") return null;
            foreach (string[] s in MisShops)
                for (int i = 1; i < s.Length; i++)
                    if (t.Contains(s[i].ToLowerInvariant().Replace(" ", ""))) return s[0];
            return null;
        }

        // 簡報播放中（就算沒有全螢幕）也不搗蛋
        static bool MisPresenting(string t)
        {
            string l = (t ?? "").ToLowerInvariant();
            return l.Contains("投影片放映") || l.Contains("簡報者檢視") || l.Contains("簡報播放") || l.Contains("slide show") || l.Contains("presenter view") || l.Contains("keynote");
        }

        // ---- 台詞（寫死、無厘頭）：先找「角色 id.key」，沒有就用通用的 ----
        static readonly Dictionary<string, string[]> MisLines = MisLinesInit();
        static Dictionary<string, string[]> MisLinesInit()
        {
            Dictionary<string, string[]> d = new Dictionary<string, string[]>();
            d["grab_start"] = new string[] { "你的游標我先保管", "這個游標沒人用？那我帶走囉", "游標借我玩一下下", "嘿嘿…游標是我的了" };
            d["grab_carry"] = new string[] { "嘿咻嘿咻～", "來追我啊～", "游標好重喔…", "快跑快跑！" };
            d["grab_drop"] = new string[] { "放這邊，自己來拿～", "游標寄放在這，不用謝", "好啦還你，我只是帶它散散步", "游標說它玩得很開心" };
            d["grab_caught"] = new string[] { "被抓到了！還你還你", "好快！還給你啦", "我只是幫你擦擦游標…", "哎呀被發現了" };
            d["grab_seen"] = new string[] { "咦！你在喔？", "沒、沒有要拿你的游標啦", "（假裝路過）" };
            d["clear_start"] = new string[] { "下班了！視窗們也該回家了", "清場時間到～", "叮咚，今天的視窗營業到這裡", "下班囉，大家收工！" };
            d["clear_push"] = new string[] { "嘿咻～推推推", "視窗們回家囉～", "這個也下班！" };
            d["clear_done"] = new string[] { "下班了，視窗都回家了", "清乾淨了！快回家吧", "桌面好乾淨～明天見", "視窗都下班了，換你了" };
            d["clear_restore"] = new string[] { "好啦好啦，視窗都回來了", "視窗回來加班了…你也辛苦了", "全部叫回來了～" };
            d["shop"] = new string[] { "{site}…錢包在哭，我也在哭", "購物車放著就好，不要結帳啊～", "這個真的需要嗎…（抱緊錢包）", "{site}又在叫你了對不對" };
            d["shop_n"] = new string[] { "這個月已經買第{n}次了欸", "第{n}次了…錢包要離家出走了", "{site}第{n}次…我的錢包好痛" };
            d["typing"] = new string[] { "哇啊啊！鍵盤地震！", "打太兇了啦～", "鍵盤要冒煙了！", "你是在跟鍵盤吵架嗎" };
            d["typing_back"] = new string[] { "呼…爬回來了", "我回來了…輕一點打好嗎", "飛好遠…先喘一下", "鍵盤颱風過了嗎…" };
            // 續命小隊
            d["duoduo.grab_start"] = new string[] { "游標…我先收進箱子保管", "這個游標…可以住我的箱子嗎", "（箱子打開）游標，進來" };
            d["duoduo.grab_carry"] = new string[] { "箱子長腳了！跑！", "（箱子咚咚咚跑走）", "不、不要追我！" };
            d["duoduo.grab_drop"] = new string[] { "還、還你…放這裡了", "游標在箱子裡睡著了…還你", "（從箱子裡把游標推出來）" };
            d["duoduo.grab_caught"] = new string[] { "被發現了！還你還你", "我、我只是幫你保管！" };
            d["duoduo.clear_start"] = new string[] { "下班了…視窗們也該回箱子了", "（推推）視窗回家…" };
            d["duoduo.shop"] = new string[] { "{site}的箱子…會送來跟我搶位子嗎", "又要買新的箱子嗎…（抱緊錢包）" };
            d["duoduo.shop_n"] = new string[] { "這個月第{n}個包裹了…家裡箱子比我還多", "第{n}次了…我的箱子要被比下去了" };
            d["duoduo.typing"] = new string[] { "鍵盤地震！我的箱子要塌了", "哇啊啊箱子飛起來了！" };
            d["duoduo.typing_back"] = new string[] { "呼…箱子還在…我回來了", "（箱子長腳慢慢走回來）" };
            d["meidian.grab_start"] = new string[] { "借你的游標當枕頭", "這游標看起來很好睡", "游標借我充電一下" };
            d["meidian.grab_carry"] = new string[] { "嘿…咻…（好耗電）", "拖著游標好累…" };
            d["meidian.grab_drop"] = new string[] { "（抱著游標睡著了）zZ", "游標當枕頭剛剛好…還你", "睡飽了…游標還你" };
            d["meidian.clear_start"] = new string[] { "我快沒電了，視窗們也一起關機吧", "下班了…大家都去充電" };
            d["meidian.shop_n"] = new string[] { "第{n}次了…我的電跟你的錢一起在掉", "這個月第{n}次…電量和存款都紅了" };
            d["meidian.typing"] = new string[] { "震掉我 3% 了！", "哇啊！電要灑出來了！" };
            d["meidian.typing_back"] = new string[] { "呼…電還在…爬回來了", "（慢慢走回來）剩一點電了" };
            d["cici.grab_start"] = new string[] { "這游標我沒收了", "游標借我。不還", "哼，游標歸我" };
            d["cici.grab_caught"] = new string[] { "哼，誰要你的游標", "拿去！才不稀罕" };
            d["cici.grab_drop"] = new string[] { "放這裡了。不是故意的", "還你。…才沒有很好玩" };
            d["cici.clear_done"] = new string[] { "下班。不是為了你，是視窗很吵", "清乾淨了。快回家" };
            d["cici.shop"] = new string[] { "買那個幹嘛…（偷看）多少錢", "{site}？…錢包在哭，我才沒有" };
            d["cici.typing"] = new string[] { "再打那麼大力我要炸毛了", "盆、盆要翻了！" };
            d["cici.typing_back"] = new string[] { "哼，我自己走回來的", "土都灑出來了…" };
            // 窩伴小世界（溫柔版的搗蛋）
            d["fanfan.grab_start"] = new string[] { "游標借我當書籤一下下", "你休息一下，游標我幫你顧著", "（把游標夾進書裡）" };
            d["fanfan.grab_drop"] = new string[] { "游標還你～剛剛有好好休息嗎", "書籤用完了，還你" };
            d["fanfan.grab_caught"] = new string[] { "被找到了～還你還你", "我只是想讓你休息一下" };
            d["fanfan.clear_start"] = new string[] { "下班了，書闔起來，視窗也收一收", "今天的頁數夠了，我們收工" };
            d["fanfan.clear_done"] = new string[] { "桌面整理好了，今天辛苦了", "收好了，明天從這裡繼續" };
            d["fanfan.shop"] = new string[] { "{site}…這個真的需要嗎？先放購物車一晚", "要不要先想一下下再買？" };
            d["fanfan.typing"] = new string[] { "哇，書頁被吹走了～", "打字好用力，手會痛喔" };
            d["fanfan.typing_back"] = new string[] { "書籤撿回來了，我回來了", "（抱著書走回來）輕輕打就好" };
            d["bobo.grab_start"] = new string[] { "游標先放旁邊，喝口水吧", "（把游標收進圍裙口袋）休息一下", "游標我先保管，你去倒杯水" };
            d["bobo.grab_drop"] = new string[] { "喝完水了嗎？游標還你", "放這裡了～" };
            d["bobo.grab_caught"] = new string[] { "被發現了～還你，記得喝水", "好啦還你" };
            d["bobo.clear_start"] = new string[] { "下班了，視窗們也該吃晚餐了", "收工囉，去吃飯吧" };
            d["bobo.clear_done"] = new string[] { "收好了，快去吃飯", "桌面乾乾淨淨，晚餐吃什麼呢" };
            d["bobo.shop"] = new string[] { "{site}…錢包說它有點累", "買之前先喝口水，冷靜一下" };
            d["bobo.shop_n"] = new string[] { "這個月第{n}次了，錢包也要休息喔", "第{n}次了…今天先不要好不好" };
            d["bobo.typing"] = new string[] { "哇，水杯差點翻了～", "輕一點點，手腕會酸" };
            d["bobo.typing_back"] = new string[] { "水沒灑，我回來了", "（端著水杯走回來）慢慢打" };
            d["mian.grab_start"] = new string[] { "游標也想休息一下", "（抱著游標）一起放空一分鐘", "游標借我抱一下下" };
            d["mian.grab_drop"] = new string[] { "游標休息好了，還你", "抱完了～還你" };
            d["mian.grab_caught"] = new string[] { "被找到了～還你", "好，還你，記得深呼吸" };
            d["mian.clear_start"] = new string[] { "下班了，讓視窗也休息吧", "今天就到這裡，慢慢收" };
            d["mian.clear_done"] = new string[] { "都收好了，好好休息", "桌面空空的，心也輕輕的" };
            d["mian.shop"] = new string[] { "{site}…想買的話，明天再看一次好嗎", "深呼吸～真的需要嗎" };
            d["mian.typing"] = new string[] { "哇～被吹得軟軟地飛走了", "打字好用力，肩膀放鬆" };
            d["mian.typing_back"] = new string[] { "飄回來了～輕輕打就好", "（慢慢飄回來）呼…" };
            return d;
        }
        public static string[] MisLinesFor(string id, string key)
        {
            string[] a;
            if (MisLines.TryGetValue(id + "." + key, out a)) return a;
            if (MisLines.TryGetValue(key, out a)) return a;
            return new string[] { "嘿嘿" };
        }
        static readonly string[] MisZh = { "零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十" };
        public static string MisNum(int n) { return n >= 0 && n <= 10 ? MisZh[n] : n.ToString(); }

        // ---- 狀態 ----
        MisSys mis;
        int misGrabMin = 3;                  // 搶游標：滑鼠鍵盤都沒動幾分鐘
        string misClearDay = "", misShopMonth = "";
        int misShopN;
        double misGrabCd, misShopCd, misTypeCd, misCheckT, misShopSince;
        bool misGrabArmed = true;
        string misShopSite = "";
        public string MisKind = "";          // 正在演哪一個：grab／clear／shop／typing（""＝沒有）
        Pet misPet;
        long misKeysLast = -1;
        readonly double[] misBuckets = new double[6];   // 最近幾秒，每秒放開幾個按鍵（只有次數）
        int misBucket;
        double misBucketT;
        string misPending = ""; double misPendingT;     // 測試指令要演但公仔還在半空中：等一下再試
        readonly HashSet<string> misAck = new HashSet<string>();   // 公開版：看過說明、自己打開過的搗蛋（mischief-consent.txt）
        MisAskForm misAsk;                                         // 公開版：第一次打開時的說明視窗
        // 下班清場
        readonly List<MisWin> misPushed = new List<MisWin>();     // 縮小了的（還原用）
        readonly List<MisWin> misQueue = new List<MisWin>();
        MisWinForm misForm;
        MisWin misWin;
        Rectangle misWa;
        int misPh, misPushDir = 1, misDone;
        double misT, misJx0, misJy0, misJx1, misJy1;

        void MisStart()
        {
            bool real = !App.Offscreen || Environment.GetEnvironmentVariable("DESKPALS_MISCHIEF_REAL") == "1";
            mis = real ? new MisSys() : new MisFake();
            MisLoad();
            MisConsentLoad();
            App.Log("mischief: " + (real ? "real" : "fake") + " grab=" + (Feat("mis_grab") ? 1 : 0) + " clear=" + (Feat("mis_clear") ? 1 : 0)
                + " shop=" + (Feat("mis_shop") ? 1 : 0) + " typing=" + (Feat("mis_typing") ? 1 : 0) + " grabmin=" + misGrabMin);
        }

        // 收工前：停掉、把視窗全部叫回來、拿掉按鍵計數
        void MisQuit()
        {
            if (mis == null) return;
            try { MisStop(); MisRestore(false); mis.KeyWatch(false); } catch (Exception ex) { App.Log("mischief quit: " + ex.Message); }
        }

        void MisLoad()
        {
            foreach (string line in ReadText("mischief.txt").Split('\n'))
            {
                string[] a = line.Trim().Split('=');
                if (a.Length != 2) continue;
                string v = a[1].Trim();
                int n;
                switch (a[0].Trim())
                {
                    case "grabmin": if (int.TryParse(v, out n)) misGrabMin = Math.Max(1, Math.Min(60, n)); break;
                    case "clearday": misClearDay = v; break;
                    case "shopmonth": misShopMonth = v; break;
                    case "shopn": int.TryParse(v, out misShopN); break;
                }
            }
        }
        void MisSave()
        {
            WriteText("mischief.txt", "grabmin=" + misGrabMin + "\nclearday=" + misClearDay + "\nshopmonth=" + misShopMonth + "\nshopn=" + misShopN + "\n");
        }

        // ---- 公開版：打開前先說明（mischief-consent.txt：第一行 v1，之後一行一個看過說明、打開過的開關）----
        void MisConsentLoad()
        {
            misAck.Clear();
            if (!App.Public) return;
            string t = ReadText("mischief-consent.txt");
            if (t != "")
            {
                foreach (string line in t.Split('\n')) { string k2 = line.Trim(); if (k2.StartsWith("mis_")) misAck.Add(k2); }
                return;
            }
            // 第一次跑這一版：舊使用者（已經有設定）照原本的開關狀態寫死，原本開著的算你打開過（不再問）；全新安裝＝四個都關
            bool old = File.Exists(FilePath("profile.txt")) || File.Exists(FilePath("features.txt")) || File.Exists(FilePath("out.txt"));
            if (old)
            {
                foreach (string[] f in MisFeatureList)
                {
                    bool on;
                    if (!feats.TryGetValue(f[0], out on)) on = !MisOldDefaultOff(f[0]);
                    feats[f[0]] = on;
                    if (on) misAck.Add(f[0]);
                }
                SaveFeatures();
            }
            MisConsentSave();
            App.Log("mischief: consent " + (old ? "migrated" : "fresh") + " ack=" + MisAckList());
        }
        void MisConsentSave()
        {
            StringBuilder sb = new StringBuilder("v1\n");
            foreach (string[] f in MisFeatureList) if (misAck.Contains(f[0])) sb.Append(f[0] + "\n");
            WriteText("mischief-consent.txt", sb.ToString());
        }
        string MisAckList()
        {
            List<string> l = new List<string>();
            foreach (string[] f in MisFeatureList) if (misAck.Contains(f[0])) l.Add(f[0].Substring(4));
            return l.Count == 0 ? "-" : string.Join(",", l.ToArray());
        }

        // 小屋選單按搗蛋的開關（測試：act mischief toggle:grab|clear|shop|typing）：公開版第一次打開先跳說明
        public void MisToggle(string key)
        {
            bool on = !Feat(key);
            if (on && App.Public && !misAck.Contains(key)) { MisAskOpen(key); return; }
            SetFeat(key, on);
        }
        void MisAskOpen(string key)
        {
            MisAskClose();
            string name = key;
            foreach (string[] f in MisFeatureList) if (f[0] == key) name = f[1];
            int cut = name.IndexOf('（');
            if (cut > 0) name = name.Substring(0, cut);
            misAsk = new MisAskForm(this, key, name, MisAskText(key));
            Rectangle wa = App.Offscreen ? screens[0].WorkingArea : Screen.FromPoint(Cursor.Position).WorkingArea;
            misAsk.Location = new Point(wa.Left + (wa.Width - misAsk.Width) / 2, wa.Top + Math.Max(0, (wa.Height - misAsk.Height) / 2));
            misAsk.Show();
            App.Log("mischief: ask " + key);
            if (App.Offscreen) return;
            ActivateForm(misAsk);
        }
        void MisAskClose() { if (misAsk != null) { MisAskForm f = misAsk; misAsk = null; if (!f.IsDisposed) f.Close(); } }
        // 說明視窗的按鈕（滑鼠、Esc、測試的 act mischief consent:ok|no）；ok＝好，打開
        public void MisAskDone(MisAskForm f, bool ok)
        {
            if (f != misAsk) return;
            string key = f.Key;
            misAsk = null;   // 視窗自己已經關了
            if (!ok) { App.Log("mischief: ask " + key + " declined"); return; }
            misAck.Add(key);
            MisConsentSave();
            SetFeat(key, true);
        }
        // 每一種：會做什麼、怎麼停／怎麼叫回來、不會做的事
        static string[][] MisAskText(string key)
        {
            switch (key)
            {
                case "mis_grab":
                    return new string[][] {
                        new string[] { "會做什麼", "滑鼠和鍵盤都沒動一陣子（預設 3 分鐘），公仔會跑來把滑鼠游標「叼走」，拖著移動一小段，最多幾秒。" },
                        new string[] { "怎麼停", "你一動滑鼠或按任何鍵，他就立刻放手。全螢幕、簡報、分享螢幕、按著滑鼠鍵、躲起來時都不會開始。" },
                        new string[] { "不會做的事", "只移動游標的位置：不會點任何東西、不會打字，也不記錄你在做什麼。" } };
                case "mis_clear":
                    return new string[][] {
                        new string[] { "會做什麼", "平日 18:00 以後（一天一次），公仔把你最前面的幾個視窗（最多 3 個）縮小到工作列，演一段「推出螢幕」。動畫會在記憶體裡擷取那幾個視窗的畫面。" },
                        new string[] { "怎麼叫回來", "點公仔或泡泡，或小屋選單「把推走的視窗叫回來」，一鍵全部回來；關掉 Desk Pals 前也會先全部叫回來。" },
                        new string[] { "不會做的事", "不會關閉任何視窗或程式；擷取的畫面不存檔、不傳出去，演完就丟掉。" } };
                case "mis_shop":
                    return new string[][] {
                        new string[] { "會做什麼", "會一直讀「最前面那個視窗的標題」，標題是購物網站時，公仔抱著錢包大哭（哭過 20 分鐘內不會再哭）。" },
                        new string[] { "怎麼停", "回小屋選單把這個開關關掉就好。" },
                        new string[] { "不會做的事", "視窗標題只在記憶體裡比對，不記錄、不存檔、不傳出去；只記「這個月哭了幾次」一個數字。" } };
                default:
                    return new string[][] {
                        new string[] { "會做什麼", "連續好幾秒打字很快，公仔會被震飛再爬回來。為了知道你打多快，會在系統裡計算按鍵次數（鍵盤掛鉤，只在這個開關打開時才裝）。" },
                        new string[] { "怎麼停", "回小屋選單把這個開關關掉，掛鉤馬上拿掉。全螢幕（遊戲）、躲起來時也不數。" },
                        new string[] { "不會做的事", "只計算按鍵次數，不記錄按了哪個鍵，也不會傳出去。" } };
            }
        }

        // 開關改了（小屋＝你自己按的；VS Code 推的不算）
        void MisFeatChanged(string key, bool on, bool user)
        {
            if (!key.StartsWith("mis_") || mis == null) return;
            if (on && App.Public && !misAck.Contains(key)) { misAck.Add(key); MisConsentSave(); }   // 自己打開的（VS Code 設定、測試指令）：之後不再問
            if (key == "mis_typing" && on && user) mis.AskKeyPermission();   // Mac：只在你自己打開時問一次「輸入監控」
            if (!on && MisKind != "" && "mis_" + MisKind == key) MisStop();
            misCheckT = 0;
        }

        // VS Code 推設定：mischief-set grab|clear|shop|typing 0|1、grabmin <分>
        void MisSet(string key, string val)
        {
            if (key == "grabmin") { int m; if (int.TryParse(val, out m)) { misGrabMin = Math.Max(1, Math.Min(60, m)); MisSave(); } return; }
            string fk = "mis_" + key;
            bool known = false;
            foreach (string[] f in MisFeatureList) if (f[0] == fk) known = true;
            if (!known) return;
            bool on = val != "0";
            if (Feat(fk) == on) return;
            feats[fk] = on;
            SaveFeatures();
            App.Log("feature " + fk + "=" + (on ? "1" : "0") + " (VS Code)");
            MisFeatChanged(fk, on, false);
        }

        bool MisMsg(Client c, string[] p, string line)
        {
            switch (p[0])
            {
                case "mischief-set": if (p.Length >= 3) MisSet(p[1], p[2]); return true;
                case "mischief-dump": Send(c, MisDump()); return true;
                case "mischief-fake": MisFakeCmd(p, line); return true;
                case "mischief-site": Send(c, "site " + (MisShopSite(MisRest(line, 1)) ?? "-") + "\n"); return true;   // 測試：這個標題算哪個購物網站
            }
            return false;
        }

        void MisAct(string arg)
        {
            switch (arg)
            {
                case "cursor": case "grab": case "clear": case "shop": case "typing": misPending = arg; misPendingT = Now + 6; MisRunPending(); break;
                case "restore": MisRestore(true); break;
                case "stop": misPending = ""; MisStop(); break;
                default:
                    if (arg.StartsWith("toggle:")) { string fk = "mis_" + arg.Substring(7); foreach (string[] f in MisFeatureList) if (f[0] == fk) MisToggle(fk); }   // 測試：等於在小屋按這個開關
                    else if (arg == "consent:ok" || arg == "consent:no") { if (misAsk != null) misAsk.Press(arg == "consent:ok" ? "ok" : "no"); }
                    break;
            }
        }

        // 測試指令：公仔準備好（在地上、沒在演別的）就演
        void MisRunPending()
        {
            if (misPending == "") return;
            if (Now > misPendingT) { App.Log("mischief: " + misPending + " not ready, skipped"); misPending = ""; return; }
            if (MisKind != "" || !MisReady(Lead(), true)) return;
            string a = misPending; misPending = "";
            switch (a)
            {
                case "cursor": case "grab": MisStartGrab(true); break;
                case "clear": MisStartClear(true); break;
                case "shop": MisStartShop(MisShopSite(mis.FgTitle()) ?? "購物網站"); break;
                case "typing": MisStartTyping(); break;
            }
        }

        void MisFakeCmd(string[] p, string line)
        {
            MisFake f = mis as MisFake;
            if (f == null || p.Length < 2) return;
            int a, b, c, d;
            double v;
            switch (p[1])
            {
                case "cursor": if (p.Length >= 4 && int.TryParse(p[2], out a) && int.TryParse(p[3], out b)) f.Cur = new Point(a, b); break;
                case "input": f.Stamp += 1000; f.IdleSec = 0; f.KeyDown = true; break;
                case "button": f.Btn = p.Length >= 3 && p[2] == "1"; break;
                case "fs": f.Fs = p.Length >= 3 && p[2] == "1"; break;
                case "idle": if (p.Length >= 3 && double.TryParse(p[2], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out v)) f.IdleSec = v; break;
                case "fg": f.Fg = MisRest(line, 2); break;
                case "typing":
                    if (p.Length >= 4 && double.TryParse(p[2], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out v) && int.TryParse(p[3], out a))
                    { f.KeyCount(); f.Rate = v; f.RateLast = f.T; f.RateUntil = f.T + a; }
                    break;
                case "win":
                    if (p.Length >= 6 && int.TryParse(p[2], out a) && int.TryParse(p[3], out b) && int.TryParse(p[4], out c) && int.TryParse(p[5], out d))
                        f.AddWin(new Rectangle(a, b, c, d), MisRest(line, 6));
                    break;
                case "clock":
                    {
                        DateTime want;
                        if (p.Length >= 3 && DateTime.TryParse(p[2], out want)) f.Shift = want - DateTime.Now; else f.Shift = TimeSpan.Zero;
                    }
                    break;
                case "reset": f.Wins.Clear(); f.Calls.Clear(); f.Warps = 0; f.Fg = ""; f.Btn = false; f.Fs = false; f.IdleSec = 0; f.Rate = 0; break;
            }
        }
        // 第 n 個空白之後的全部（標題可以有空白）
        static string MisRest(string line, int n)
        {
            string t = line.Trim();
            int i = -1;
            for (int k2 = 0; k2 < n; k2++) { i = t.IndexOf(' ', i + 1); if (i < 0) return ""; }
            return t.Substring(i + 1);
        }

        string MisDump()
        {
            StringBuilder sb = new StringBuilder();
            Pet l = Lead();
            sb.Append("mischief backend=" + (mis.Fake ? "fake" : "real") + " kind=" + (MisKind == "" ? "-" : MisKind) + " grab=" + (Feat("mis_grab") ? 1 : 0) + " clear=" + (Feat("mis_clear") ? 1 : 0)
                + " shop=" + (Feat("mis_shop") ? 1 : 0) + " typing=" + (Feat("mis_typing") ? 1 : 0) + " grabmin=" + misGrabMin + " pushed=" + misPushed.Count
                + " form=" + (misForm != null ? 1 : 0) + " clearday=" + (misClearDay == "" ? "-" : misClearDay) + " shopn=" + misShopN + " notice=" + (current != null && current.Kind == "mis-restore" ? 1 : 0)
                + " lead=" + (l != null ? l.P.Id + ":" + l.state + (l.MisBusy ? ":busy" : "") : "-")
                + " edition=" + (App.Public ? "public" : "personal") + " ask=" + (misAsk != null ? misAsk.Key.Substring(4) : "-") + " ack=" + MisAckList() + "\n");
            sb.Append(mis.Dump());
            sb.Append("end\n");
            return sb.ToString();
        }

        // ---- 安全檢查 ----
        bool MisReady(Pet l, bool allowSleep)
        {
            if (l == null || !l.Out || l.InScene || l.Dragging || l.MisBusy || !l.Grounded()) return false;
            return allowSleep || l.state != "sleep";
        }
        // 絕對不搗蛋：全螢幕（遊戲、影片）、簡報、分享螢幕、躲起來、按著滑鼠鍵、選單開著
        bool MisSafeCore()
        {
            if (Hidden || fsNow || sharing || pmenu != null || mis.Fullscreen() || mis.Buttons()) return false;
            return !MisPresenting(mis.FgTitle());
        }
        // 平常（自己跑出來搗蛋）再加上：安靜、專注時不搗蛋
        bool MisSafe() { return !quietOn && !focusOn && MisSafeCore(); }

        void MisTick(double dt)
        {
            if (mis == null) return;
            MisFake fk = mis as MisFake;
            if (fk != null) fk.T = Now;
            misGrabCd -= dt; misShopCd -= dt; misTypeCd -= dt;
            if (MisKind == "clear") MisClearStep(dt);
            if (MisKind != "" && (Hidden || fsNow || sharing || quietOn || focusOn || mis.Fullscreen())) { App.Log("mischief: stopped (" + MisKind + ")"); MisStop(); }
            if (MisKind != "" && MisKind != "clear" && (misPet == null || !misPet.MisBusy)) { MisKind = ""; misPet = null; }
            MisKeys(dt);
            MisRunPending();
            misCheckT -= dt;
            if (misCheckT > 0) return;
            misCheckT = 0.5;
            mis.KeyWatch(Feat("mis_typing") && !Hidden && !fsNow);   // 全螢幕（遊戲）、躲起來時不數
            if (MisKind != "" || !MisSafe()) return;
            if (Feat("mis_clear") && MisClearDue()) { MisStartClear(false); return; }
            if (Feat("mis_shop")) MisShopCheck();
            if (MisKind == "" && Feat("mis_grab")) MisGrabCheck();
        }

        void MisStop()
        {
            if (MisKind == "clear") { MisClearEnd(); return; }
            Pet p = misPet;
            MisKind = ""; misPet = null;
            if (p != null && p.MisBusy) p.MisAbort();
        }

        // 公仔演完了（自己結束、被抓到、被拖走）
        public void MisPetDone(Pet p)
        {
            if (p != misPet || MisKind == "clear") return;
            MisKind = ""; misPet = null;
        }

        // ---------- 搶游標 ----------
        void MisGrabCheck()
        {
            if (misGrabCd > 0) return;
            if (mis.Idle() < misGrabMin * 60.0) { misGrabArmed = true; return; }
            if (!misGrabArmed) return;   // 同一段沒動只搶一次
            if (MisStartGrab(false)) misGrabArmed = false;
        }

        bool MisStartGrab(bool force)
        {
            Pet l = Lead();
            if (!MisReady(l, true) || !MisSafeCore()) return false;
            Point c = mis.CursorPos();
            if (!Inside(c.X, c.Y)) return false;
            l.WakeIfSleep();
            MisKind = "grab"; misPet = l; misGrabCd = 15 * 60;
            mis.KeyPrime();
            l.MisGrab(c);
            App.Log("mischief grab" + (force ? " (asked)" : ""));
            return true;
        }

        // 公仔要移游標：只有搶游標進行中、你沒按著滑鼠時才會真的移；一定在螢幕裡面
        public bool MisWarp(int x, int y)
        {
            if (MisKind != "grab" || mis.Buttons()) return false;
            Rectangle wa = WA(x, y);
            x = Math.Max(wa.Left + 1, Math.Min(wa.Right - 2, x));
            y = Math.Max(wa.Top + 1, Math.Min(wa.Bottom - 2, y));
            mis.Warp(x, y);
            return true;
        }
        public Point MisCursor() { return mis.CursorPos(); }
        // 你動了嗎：按著滑鼠鍵、按了鍵盤、游標不在公仔放的地方（容忍 DPI 四捨五入 4 px）。
        // 不看「最後輸入時間」：公仔自己移游標之後系統也會更新它（非同步），會被當成你動了，拖不到半秒就放手
        public bool MisUserMoved(Point expect)
        {
            if (mis.Buttons() || mis.KeyPressed()) return true;
            Point c = mis.CursorPos();
            return Math.Abs(c.X - expect.X) > 4 || Math.Abs(c.Y - expect.Y) > 4;
        }

        // ---------- 購物警察 ----------
        void MisShopCheck()
        {
            string site = MisShopSite(mis.FgTitle());
            if (site == null) { misShopSite = ""; return; }
            if (site != misShopSite) { misShopSite = site; misShopSince = Now; return; }
            if (Now - misShopSince < 2 || misShopCd > 0) return;   // 停在購物網站 2 秒以上才算；哭過之後 20 分鐘內不再哭
            MisStartShop(site);
        }

        void MisStartShop(string site)
        {
            Pet l = Lead();
            if (!MisReady(l, true) || !MisSafeCore()) return;
            l.WakeIfSleep();
            misShopCd = 20 * 60;
            string month = mis.Clock().ToString("yyyy-MM");
            if (month != misShopMonth) { misShopMonth = month; misShopN = 0; }
            misShopN++;
            MisSave();
            MisKind = "shop"; misPet = l;
            l.MisCry(site, misShopN);
            App.Log("mischief shop #" + misShopN);
        }

        // ---------- 打字太兇（只有每秒幾下的次數） ----------
        void MisKeys(double dt)
        {
            long kc = mis.KeyCount();
            if (misKeysLast < 0 || kc < misKeysLast) misKeysLast = kc;
            misBuckets[misBucket] += kc - misKeysLast;
            misKeysLast = kc;
            if (Now - misBucketT < 1) return;   // 每一格是牆上時間的 1 秒（主迴圈卡住也一樣）
            misBucketT = Now;
            // 最近 4 秒：每一秒都 ≥ 6 下、加起來 ≥ 36 下 → 震飛
            bool fast = true;
            double sum = 0;
            for (int i = 0; i < 4; i++) { double v = misBuckets[(misBucket - i + 6) % 6]; sum += v; if (v < 6) fast = false; }
            misBucket = (misBucket + 1) % 6;
            misBuckets[misBucket] = 0;
            if (fast && sum >= 36 && misTypeCd <= 0 && MisKind == "" && Feat("mis_typing") && MisSafe()) MisStartTyping();
        }

        void MisStartTyping()
        {
            Pet l = Lead();
            if (!MisReady(l, true) || !MisSafeCore()) return;
            l.WakeIfSleep();
            misTypeCd = 10 * 60;
            for (int i = 0; i < misBuckets.Length; i++) misBuckets[i] = 0;
            MisKind = "typing"; misPet = l;
            l.MisFly();
            App.Log("mischief typing");
        }

        // ---------- 下班清場 ----------
        bool MisClearDue()
        {
            if (!Feat("night") || forceNight == 0) return false;   // 跟「下班時間」同一套：平日 18:00 之後
            DateTime n = mis.Clock();
            if (n.DayOfWeek == DayOfWeek.Saturday || n.DayOfWeek == DayOfWeek.Sunday) return false;
            if (n.Hour < 18 || n.Hour >= 21 || (n.Hour == 18 && n.Minute < 1)) return false;   // 18:00 那一分鐘先讓「今天的小結」講
            if (misClearDay == n.ToString("yyyy-MM-dd")) return false;   // 一天一次
            return mis.Idle() < 60;   // 人在電腦前才演（不在就等你回來）
        }

        void MisStartClear(bool force)
        {
            Pet l = Lead();
            if (!MisReady(l, true) || !MisSafeCore()) return;
            misClearDay = mis.Clock().ToString("yyyy-MM-dd");
            MisSave();
            List<MisWin> wins = mis.Windows(this, 3);
            if (wins.Count == 0) { if (force) l.Say("下班了！桌面已經很乾淨了，快回家吧", 3); return; }
            l.WakeIfSleep();
            MisKind = "clear"; misPet = l;
            misQueue.Clear(); misQueue.AddRange(wins); misDone = 0;
            l.MisPuppet(true);
            l.MisPose("wind"); l.Mark(1);
            l.Say(l.MisLine("clear_start"), 2.6);
            misPh = 0; misT = 0;
            App.Log("mischief clear " + wins.Count + " window(s)" + (force ? " (asked)" : ""));
        }

        void MisClearStep(double dt)
        {
            Pet l = misPet;
            if (l == null || !l.MisBusy || !l.Out) { MisClearEnd(); return; }
            misT += dt;
            switch (misPh)
            {
                case 0: if (misT >= 1.3) MisClearNext(); break;
                case 1:   // 跳到視窗邊
                    {
                        double f = Math.Min(1, misT / 0.7);
                        l.x = misJx0 + (misJx1 - misJx0) * f;
                        l.y = misJy0 + (misJy1 - misJy0) * f - Math.Sin(Math.PI * f) * 120 * k;
                        l.dir = misJx1 >= misJx0 ? 1 : -1;
                        if (f >= 1) { misPh = 2; misT = 0; l.dir = misPushDir; l.MisPose("brace"); }
                    }
                    break;
                case 2:   // 頂住
                    if (misT >= 0.45) { misPh = 3; misT = 0; l.MisPose("push"); if (misDone == 0) l.Say(l.MisLine("clear_push"), 1.8); }
                    break;
                case 3:   // 推出去（越推越快）
                    {
                        double f = Math.Min(1, misT / 1.5), e = f * f;
                        Rectangle r = misWin.R;
                        double dist = misPushDir < 0 ? r.Right - misWa.Left + 30 : misWa.Right - r.Left + 30;
                        int fx = (int)Math.Round(r.X + misPushDir * dist * e);
                        if (misForm != null) misForm.Location = new Point(fx, r.Y);
                        double edge = misPushDir < 0 ? fx + r.Width : fx;
                        l.x = Mid(misPushDir < 0 ? edge - l.SW * 0.25 : edge - l.SW * 0.75, misWa.Left, misWa.Right - l.SW);
                        if (rnd.NextDouble() < dt * 2) l.Mark(4);
                        if (f >= 1) { MisCloseForm(); misDone++; misPh = 4; misT = 0; l.MisPose("idle"); }
                    }
                    break;
                case 4: if (misT >= 0.35) MisClearNext(); break;
            }
        }

        // 下一個視窗：先蓋上假視窗（擷取的樣子）→ 真的縮小 → 公仔跳到要推的那一邊
        void MisClearNext()
        {
            Pet l = misPet;
            while (misQueue.Count > 0)
            {
                MisWin mw = misQueue[0];
                misQueue.RemoveAt(0);
                Rectangle wa = WA(mw.R.X + mw.R.Width / 2.0, mw.R.Y + mw.R.Height / 2.0);
                Bitmap b = null;
                try { b = mis.Capture(mw); } catch (Exception ex) { App.Log("mischief capture: " + ex.Message); }
                MisWinForm f = new MisWinForm(b, mw.Title, mw.R);
                f.Show(); f.Refresh();
                Zorder();
                bool ok = false;
                try { ok = mis.Minimize(mw); } catch (Exception ex) { App.Log("mischief minimize: " + ex.Message); }
                if (!ok) { f.Close(); continue; }
                misPushed.Add(mw);
                misForm = f; misWin = mw; misWa = wa;
                misPushDir = mw.R.X + mw.R.Width / 2.0 < wa.X + wa.Width / 2.0 ? -1 : 1;   // 往近的那一邊推
                double edge = misPushDir < 0 ? mw.R.Right : mw.R.Left;
                misJx0 = l.x; misJy0 = l.y;
                misJx1 = Mid(misPushDir < 0 ? edge - l.SW * 0.25 : edge - l.SW * 0.75, wa.Left, wa.Right - l.SW);
                misJy1 = Math.Min(mw.R.Bottom, wa.Bottom) - l.SH;
                misPh = 1; misT = 0;
                l.MisPose("leap");
                return;
            }
            MisClearEnd();
        }

        void MisCloseForm() { if (misForm != null) { misForm.Close(); misForm = null; } }

        void MisClearEnd()
        {
            MisCloseForm();
            misQueue.Clear();
            Pet l = misPet;
            MisKind = ""; misPet = null;
            if (l != null && l.MisBusy) l.MisPuppet(false);
            if (misPushed.Count == 0 || l == null) return;
            // 點公仔（或泡泡）＝全部叫回來；10 分鐘內有效，之後小屋選單也叫得回來
            Notice n = new Notice();
            n.Kind = "mis-restore"; n.Text = ""; n.Pri = 1; n.By = l; n.Expire = Now + 600; n.At = DateTime.Now;
            current = n;
            l.SetClickableBubble(true);
            l.Say(l.MisLine("clear_done"), 8, false, "點我把視窗叫回來");
        }

        bool MisClicked(Pet p, Notice n)
        {
            if (n.Kind != "mis-restore") return false;
            MisRestore(true);
            return true;
        }

        // 推走的視窗全部叫回來（後面的先，最前面那個最後、拿回焦點）
        public void MisRestore(bool say)
        {
            if (mis == null) return;
            if (misPushed.Count == 0) { if (say) Lead().Say("沒有被推走的視窗喔", 1.6); return; }
            for (int i = misPushed.Count - 1; i >= 0; i--)
            {
                try { mis.Restore(misPushed[i], i == 0); } catch (Exception ex) { App.Log("mischief restore: " + ex.Message); }
            }
            int cnt = misPushed.Count;
            misPushed.Clear();
            if (current != null && current.Kind == "mis-restore") { if (current.By != null) current.By.SetClickableBubble(false); current = null; }
            App.LogAlways("mischief: restored " + cnt + " window(s)");
            if (say) { Pet l = Lead(); l.Say(l.MisLine("clear_restore"), 2.4); }
        }

        // ---------- 小屋選單 ----------
        void MisHouseMenu(ContextMenuStrip m)
        {
            ToolStripMenuItem sub = new ToolStripMenuItem("搗蛋（惡作劇開關）");
            foreach (string[] f in MisFeatureList)
            {
                string key = f[0];
                ToolStripMenuItem mi = new ToolStripMenuItem(f[1]);
                mi.CheckOnClick = true;
                mi.Checked = Feat(key);
                mi.Click += delegate { MisToggle(key); mi.Checked = Feat(key); };   // 公開版第一次打開：先跳說明
                sub.DropDownItems.Add(mi);
            }
            ToolStripMenuItem gm = new ToolStripMenuItem("搶游標：滑鼠停多久（現在 " + misGrabMin + " 分）");
            foreach (int mm in new int[] { 1, 3, 5, 10 })
            {
                int m2 = mm;
                ToolStripMenuItem it = new ToolStripMenuItem(m2 + " 分鐘", null, delegate { misGrabMin = m2; MisSave(); Lead().Say("好～滑鼠停 " + m2 + " 分鐘我就來搶", 2); });
                it.Checked = misGrabMin == m2;
                gm.DropDownItems.Add(it);
            }
            sub.DropDownItems.Add(gm);
            m.Items.Add(sub);
            if (misPushed.Count > 0) m.Items.Add("把推走的視窗叫回來（" + misPushed.Count + " 個）", null, delegate { MisRestore(true); });
        }

        // ---------- 離屏截圖：假視窗、假游標 ----------
        void MisSnapWins(Graphics g)
        {
            MisFake fk = mis as MisFake;
            if (fk != null)
                for (int i = fk.Wins.Count - 1; i >= 0; i--)
                {
                    MisWin m = fk.Wins[i];
                    if (m.Min) continue;
                    GraphicsState st = g.Save();
                    g.TranslateTransform(m.R.X, m.R.Y);
                    MisWinForm.DrawWin(g, null, m.Title, m.R.Width, m.R.Height);
                    g.Restore(st);
                }
            if (misForm != null && misForm.VVisible) misForm.PaintTo(g);
        }
        // 說明視窗（離屏截圖畫在最上面）
        void MisSnapAsk(Graphics g) { if (misAsk != null && !misAsk.IsDisposed && misAsk.VVisible) misAsk.PaintTo(g); }
        static readonly string[] MIS_ARROW = { "k.......", "kk......", "kwk.....", "kwwk....", "kwwwk...", "kwwwwk..", "kwwwwwk.", "kwwwkkkk", "kwkwk...", "kk.kwk..", "k...kwk.", "....kk.." };
        void MisSnapCursor(Graphics g)
        {
            MisFake fk = mis as MisFake;
            if (fk == null) return;
            int ps = 2;
            for (int ry = 0; ry < MIS_ARROW.Length; ry++)
                for (int rx = 0; rx < MIS_ARROW[ry].Length; rx++)
                {
                    char c = MIS_ARROW[ry][rx];
                    if (c == '.') continue;
                    g.FillRectangle(c == 'k' ? Brushes.Black : Brushes.White, fk.Cur.X + rx * ps, fk.Cur.Y + ry * ps, ps, ps);
                }
        }
    }
}
