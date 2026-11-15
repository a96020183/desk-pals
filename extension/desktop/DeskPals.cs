// Desk Pals（公仔櫃）：桌面上的像素公仔們（Spidey、小波、史迪仔、人魚漢頓…）。
// 獨立程式；一個 World 管全部：視窗掃描、公仔櫃、球、煙火、Claude／Codex 監看、pipe；0～4 隻公仔同時在桌面上跑。
// 角色＝Pal（資料：調色盤、像素圖、台詞、移動風格），新增角色＝加一個 Pal（＋需要的話加專屬動作）。
// 刻意寫成 C# 5（PowerShell 5.1 Add-Type 的編譯器），不用 $"" / ?. / => 成員 / nameof。
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

namespace DeskPals
{
    public static class App
    {
        [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
        static int logged;
        // 測試用：DESKPALS_OFFSCREEN=1 時所有視窗都不顯示，畫面改畫進虛擬螢幕（pipe 的 snap 指令存成 PNG）
        public static readonly bool Offscreen = Environment.GetEnvironmentVariable("DESKPALS_OFFSCREEN") == "1";
        // 測試用：離屏＋DESKPALS_ISOLATED=1 時不看真的視窗（不跳上你的視窗、你全螢幕也不會躲起來），截圖比較乾淨
        public static readonly bool Isolated = Offscreen && Environment.GetEnvironmentVariable("DESKPALS_ISOLATED") == "1";

        // 診斷用：不受行數上限限制
        public static void LogAlways(string s)
        {
            try { File.AppendAllText(Path.Combine(Path.GetTempPath(), "desk-pals.log"), DateTime.Now.ToString("HH:mm:ss.fff") + " " + s + Environment.NewLine); }
            catch { }
        }

        public static void Log(string s)
        {
            if (logged++ > 80) return;
            try { File.AppendAllText(Path.Combine(Path.GetTempPath(), "desk-pals.log"), DateTime.Now.ToString("s") + " " + s + Environment.NewLine); }
            catch { }
        }

        public static void Run(string pipeName, string pet) { Run(pipeName, pet, ""); }
        // lineup：classic（經典一櫃）／teletubbies（天線寶寶一櫃）；空白＝照上次的
        public static void Run(string pipeName, string pet, string lineup)
        {
            bool created;
            using (Mutex mtx = new Mutex(true, "Local\\" + pipeName, out created))
            {
                if (!created) { Log("already running"); return; }
                try
                {
                    SetProcessDPIAware();
                    try { Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException); } catch { }
                    Application.ThreadException += delegate(object s, ThreadExceptionEventArgs e) { Log("ui: " + e.Exception); };
                    Application.EnableVisualStyles();
                    World w = new World(pipeName, pet, lineup);
                    w.Start();
                    Application.Run(new ApplicationContext());
                }
                catch (Exception ex) { Log("fatal: " + ex); }
            }
        }

        // 開發用：把每個角色的各種姿勢畫成一張圖（不會開任何視窗）
        public static void Preview(string path, bool night)
        {
            Pet.PreviewSheet(path, night);
        }
        public static void PreviewShelf(string path, bool night)
        {
            Pet.PreviewShelf(path, night);
        }
        // 開發用：天線寶寶一櫃的各種姿勢
        public static void PreviewTubbies(string path, bool night)
        {
            Pet.PreviewTubbySheet(path, night);
        }
    }

    static class W
    {
        public delegate bool EnumProc(IntPtr h, IntPtr l);
        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
        [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
        [DllImport("user32.dll")] public static extern bool AttachThreadInput(int idAttach, int idAttachTo, bool attach);
        [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
        [DllImport("kernel32.dll")] public static extern int GetCurrentThreadId();

        // 我們的視窗都是「不搶焦點」的，選單、輸入框要先把自己拉到前景才會正常顯示／能打字
        public static bool ForceForeground(IntPtr h)
        {
            bool ok = false;
            try
            {
                IntPtr fg = GetForegroundWindow();
                int pid;
                int fgThread = fg == IntPtr.Zero ? 0 : GetWindowThreadProcessId(fg, out pid), me = GetCurrentThreadId();
                bool att = fgThread != 0 && fgThread != me && AttachThreadInput(me, fgThread, true);
                ok = SetForegroundWindow(h);
                BringWindowToTop(h);
                if (att) AttachThreadInput(me, fgThread, false);
                App.LogAlways("menu: ForceForeground set=" + ok + " attached=" + att + " fgAfter=" + (GetForegroundWindow() == h ? "helper" : GetForegroundWindow().ToString("X")));
            }
            catch (Exception ex) { App.LogAlways("menu: ForceForeground error " + ex.Message); }
            return ok;
        }

        // ---- 原生選單（TrackPopupMenuEx）：從背景程式叫出來也穩定 ----
        [DllImport("user32.dll")] public static extern IntPtr CreatePopupMenu();
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool AppendMenu(IntPtr hMenu, uint flags, IntPtr id, string text);
        [DllImport("user32.dll", SetLastError = true)] public static extern int TrackPopupMenuEx(IntPtr hMenu, uint flags, int x, int y, IntPtr hwnd, IntPtr tpm);
        [DllImport("user32.dll")] public static extern bool DestroyMenu(IntPtr hMenu);
        [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int n);
        [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder sb, int n);
        [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int n);
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int n);
        [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
        [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO li);
        public static double IdleSeconds()
        {
            if (App.Isolated) return World.TestIdle;   // 測試：不看真的鍵盤滑鼠（act idle <秒>）
            LASTINPUTINFO li = new LASTINPUTINFO();
            li.cbSize = 8;
            if (!GetLastInputInfo(ref li)) return 0;
            return unchecked((uint)Environment.TickCount - li.dwTime) / 1000.0;
        }
        [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; public POINT(int x, int y) { X = x; Y = y; } }
        [StructLayout(LayoutKind.Sequential)] public struct SIZE { public int CX, CY; public SIZE(int cx, int cy) { CX = cx; CY = cy; } }
        [StructLayout(LayoutKind.Sequential, Pack = 1)] public struct BLENDFUNCTION { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }
        [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
        [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
        [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr dc);
        [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr dc);
        [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
        [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr obj);
        [DllImport("user32.dll", SetLastError = true)] public static extern bool UpdateLayeredWindow(IntPtr h, IntPtr dst, ref POINT pos, ref SIZE size, IntPtr src, ref POINT srcPos, int key, ref BLENDFUNCTION blend, int flags);

        // 一次完成「移動＋改大小＋換畫面」，不會有拉伸的中間畫面
        public static void Present(Form f, Bitmap bmp, int x, int y)
        {
            if (App.Offscreen)
            {
                OverlayForm o = f as OverlayForm;
                if (o != null) { if (o.VBmp != null) o.VBmp.Dispose(); o.VBmp = (Bitmap)bmp.Clone(); o.VPos = new Point(x, y); }
                return;
            }
            IntPtr screen = GetDC(IntPtr.Zero), mem = CreateCompatibleDC(screen);
            IntPtr hb = bmp.GetHbitmap(Color.FromArgb(0)), old = SelectObject(mem, hb);
            try
            {
                POINT pos = new POINT(x, y), src = new POINT(0, 0);
                SIZE size = new SIZE(bmp.Width, bmp.Height);
                BLENDFUNCTION bl = new BLENDFUNCTION();
                bl.SourceConstantAlpha = 255; bl.AlphaFormat = 1; // AC_SRC_ALPHA
                if (!UpdateLayeredWindow(f.Handle, screen, ref pos, ref size, mem, ref src, 0, ref bl, 2)) // ULW_ALPHA
                    App.Log("ULW failed err=" + Marshal.GetLastWin32Error() + " size=" + size.CX + "x" + size.CY);
            }
            finally
            {
                SelectObject(mem, old); DeleteObject(hb); DeleteDC(mem); ReleaseDC(IntPtr.Zero, screen);
            }
        }
        public static readonly IntPtr TOPMOST = new IntPtr(-1);
        public const uint NOSIZE = 1, NOMOVE = 2, NOACTIVATE = 0x10;

        public static bool Rect(IntPtr h, out RECT r)
        {
            if (DwmGetWindowAttribute(h, 9, out r, 16) == 0) return true; // DWMWA_EXTENDED_FRAME_BOUNDS
            return GetWindowRect(h, out r);
        }
        public static volatile bool SuspendZ;    // 原生選單開著時不要把我們的視窗拉到最上面（會蓋住選單）
        public static void KeepOnTop(Form f)
        {
            if (SuspendZ) return;
            if (f != null && f.IsHandleCreated && f.Visible) SetWindowPos(f.Handle, TOPMOST, 0, 0, 0, 0, NOSIZE | NOMOVE | NOACTIVATE);
        }
        // 有沒有在顯示（離屏測試模式看虛擬旗標）
        public static bool Shown(Form f)
        {
            if (f == null) return false;
            OverlayForm o = f as OverlayForm;
            return App.Offscreen && o != null ? o.VVisible : f.Visible;
        }
    }

    class WinInfo { public IntPtr H; public int L, T, R, B, Z; }
    class Plat { public IntPtr H; public int Top, Left, Right, WinLeft; }
    class Client { public NamedPipeServerStream S; }

    // 透明、不搶焦點、永遠在最上層的小視窗共同設定
    class OverlayForm : Form
    {
        public static readonly Color KEY = Color.FromArgb(255, 0, 255);
        readonly bool clickThrough, perPixel;
        public OverlayForm(bool clickThrough) : this(clickThrough, false) { }
        public OverlayForm(bool clickThrough, bool perPixel)
        {
            this.clickThrough = clickThrough;
            this.perPixel = perPixel;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            TopMost = true;
            StartPosition = FormStartPosition.Manual;
            if (!perPixel) { BackColor = KEY; TransparencyKey = KEY; }
            SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
        }
        protected override bool ShowWithoutActivation { get { return true; } }
        // 現在要不要點得穿（泡泡有通知可以點時會關掉）；視窗重建時也照這個
        protected virtual bool ClickThroughNow { get { return true; } }

        // ---- 離屏測試模式：永遠不真的顯示，只記住「應該要顯示」 ----
        public bool VVisible;
        public Bitmap VBmp;
        public Point VPos;
        protected override void SetVisibleCore(bool value)
        {
            if (App.Offscreen) { VVisible = value; base.SetVisibleCore(false); return; }
            base.SetVisibleCore(value);
        }
        // 把自己（非逐像素的那種）畫到虛擬螢幕上
        public void PaintTo(Graphics g)
        {
            if (Width <= 0 || Height <= 0) return;
            // 24 位元底圖：GDI 文字不會把 alpha 寫成 0（不然字會糊）
            using (Bitmap b = new Bitmap(Width, Height, PixelFormat.Format24bppRgb))
            {
                using (Graphics gg = Graphics.FromImage(b)) OnPaint(new PaintEventArgs(gg, new Rectangle(0, 0, Width, Height)));
                b.MakeTransparent(KEY);
                if (Opacity < 0.999)
                {
                    ColorMatrix cm = new ColorMatrix(); cm.Matrix33 = (float)Opacity;
                    using (ImageAttributes ia = new ImageAttributes()) { ia.SetColorMatrix(cm); g.DrawImage(b, new Rectangle(Left, Top, Width, Height), 0, 0, Width, Height, GraphicsUnit.Pixel, ia); }
                }
                else g.DrawImageUnscaled(b, Left, Top);
            }
        }
        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x80 | 0x08000000 | 0x8; // TOOLWINDOW | NOACTIVATE | TOPMOST
                if (clickThrough) cp.ExStyle |= 0x80000;          // LAYERED
                if (clickThrough && ClickThroughNow) cp.ExStyle |= 0x20; // TRANSPARENT（點得穿）
                if (perPixel) cp.ExStyle |= 0x80000;              // LAYERED（UpdateLayeredWindow 用）
                return cp;
            }
        }
    }

    // 對話泡泡。theme：0 白天、1 黑化（Spidey）、2 夕陽（小波）、3 夜空（史迪仔）、4 燭光（人魚漢頓）
    class BubbleForm : OverlayForm
    {
        readonly Font font = new Font("Microsoft JhengHei UI", 10f, FontStyle.Bold);
        readonly Font hintFont = new Font("Microsoft JhengHei UI", 9f, FontStyle.Bold);
        string text = "", hint;
        bool alert;
        int theme, hintH;
        Color accent = Color.FromArgb(0x2A, 0x2F, 0x45);
        Pet owner;
        bool clickable;
        public BubbleForm(Color accent) : base(true) { this.accent = accent; }

        public Size Measure(string s, bool a, int th, string h)
        {
            if (s != text || a != alert || th != theme || h != hint) { text = s; alert = a; theme = th; hint = h; Invalidate(); }
            Size ts = TextRenderer.MeasureText(s, font, new Size(4000, 400), TextFormatFlags.NoPadding);
            hintH = 0;
            int wd = ts.Width;
            if (!string.IsNullOrEmpty(h))
            {
                Size hs = TextRenderer.MeasureText(h, hintFont, new Size(4000, 400), TextFormatFlags.NoPadding);
                hintH = hs.Height + 2; wd = Math.Max(wd, hs.Width + hs.Height + 2);
            }
            return new Size(wd + 22, ts.Height + hintH + 12 + 7);
        }

        // 有通知可以點的時候，泡泡不再點得穿（點了＝打開連結）
        protected override bool ClickThroughNow { get { return !clickable; } }
        public void SetClickable(bool on, Pet p)
        {
            owner = p;
            clickable = on;
            Cursor = on ? Cursors.Hand : Cursors.Default;
            if (!IsHandleCreated) return;          // 還沒建立：建立時 CreateParams 會照 clickable 設
            int ex = W.GetWindowLong(Handle, -20);
            int want = on ? (ex & ~0x20) : (ex | 0x20);
            if (want != ex)
            {
                W.SetWindowLong(Handle, -20, want);
                W.SetWindowPos(Handle, IntPtr.Zero, 0, 0, 0, 0, W.NOSIZE | W.NOMOVE | W.NOACTIVATE | 0x0004 | 0x0020); // NOZORDER | FRAMECHANGED
            }
            if (on) W.KeepOnTop(this);
        }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (clickable && owner != null && e.Button == MouseButtons.Left) owner.Clicked();
        }

        static Color C(int rgb) { return Color.FromArgb((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(KEY);
            int w = ClientSize.Width, h = ClientSize.Height - 7;
            Color line, fg, bg;
            switch (theme)
            {
                case 1: line = C(0x7B6BC4); fg = C(0xEEEBF8); bg = C(0x16171F); break;
                case 2: line = C(0xE8935A); fg = C(0xFFEBD9); bg = C(0x3B2335); break;
                case 3: line = C(0x6FA8E8); fg = C(0xE4F0FF); bg = C(0x14203A); break;
                case 4: line = C(0xD9A050); fg = C(0xFFF1D6); bg = C(0x2E2418); break;
                default: line = accent; fg = C(0x2A2F45); bg = Color.White; break;
            }
            if (alert) { line = C(0xC95454); fg = theme == 0 ? C(0xA83232) : C(0xFF8A8A); }
            using (SolidBrush lb = new SolidBrush(line))
            using (SolidBrush fill = new SolidBrush(bg))
            {
                // 像素風方框（切角）＋往下的小尾巴
                g.FillRectangle(lb, 2, 0, w - 4, h);
                g.FillRectangle(lb, 0, 2, w, h - 4);
                g.FillRectangle(lb, 1, 1, w - 2, h - 2);
                g.FillRectangle(fill, 3, 2, w - 6, h - 4);
                g.FillRectangle(fill, 2, 3, w - 4, h - 6);
                int cx = w / 2;
                for (int i = 0; i < 7; i++) g.FillRectangle(lb, cx - 7 + i, h - 2 + i, 14 - 2 * i, 1);
                for (int i = 0; i < 5; i++) g.FillRectangle(fill, cx - 5 + i, h - 2 + i, 10 - 2 * i, 1);
            }
            if (text.IndexOf('\n') >= 0)
                TextRenderer.DrawText(g, text, font, new Rectangle(0, 6, w, h - hintH - 6), fg, TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPadding);
            else
                TextRenderer.DrawText(g, text, font, new Rectangle(0, 0, w, h - hintH), fg,
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            if (hintH > 0)
            {
                // 小小的「↗」連結圖示（自己畫，不靠 emoji 字型）＋提示字
                Color hc = theme == 0 ? Color.FromArgb(0x3D, 0x7B, 0xD9) : Color.FromArgb(0x9F, 0xC8, 0xFF);
                Size hs = TextRenderer.MeasureText(hint, hintFont, new Size(4000, 400), TextFormatFlags.NoPadding);
                int ic = Math.Max(7, hs.Height - 4), tw = ic + 4 + hs.Width, x0 = (w - tw) / 2, y0 = h - hintH - 5 + (hintH - ic) / 2;
                using (Pen p = new Pen(hc, Math.Max(1.4f, ic / 6f)))
                {
                    g.DrawRectangle(p, x0, y0 + ic / 3, ic * 2 / 3, ic * 2 / 3);
                    g.DrawLine(p, x0 + ic / 3, y0 + ic * 2 / 3, x0 + ic, y0);
                    g.DrawLine(p, x0 + ic / 2, y0, x0 + ic, y0);
                    g.DrawLine(p, x0 + ic, y0, x0 + ic, y0 + ic / 2);
                }
                TextRenderer.DrawText(g, hint, hintFont, new Point(x0 + ic + 4, h - hintH - 5 + (hintH - hs.Height) / 2), hc, TextFormatFlags.NoPadding);
            }
        }
    }

    // 球（點得到：點一下就把球丟出去）。kind：tennis／baseball
    class BallForm : OverlayForm
    {
        public event Action Kicked;
        readonly int ps;
        string kind = "tennis";
        static readonly string[] TENNIS = { "..kkkk..", ".kTTTTk.", "kTTWTTTk", "kTWTTTTk", "kTTTTWTk", "kTTTWTTk", ".kTTTTk.", "..kkkk.." };
        static readonly string[] BASEBALL = { "..gggg..", ".gWWWWg.", "gRWWWWRg", "gWRWWRWg", "gWRWWRWg", "gRWWWWRg", ".gWWWWg.", "..gggg.." };
        static readonly string[] TUBBYBALL = { "..kkkk..", ".kOOYOk.", "kOYOOOOk", "kOOOOOok", "kOOOOOok", "kOOOOook", ".kooook.", "..kkkk.." };   // 天線寶寶的大橘球
        readonly SolidBrush bk = new SolidBrush(Color.FromArgb(0x2A, 0x2F, 0x45)), bt = new SolidBrush(Color.FromArgb(0xD9, 0xE8, 0x4A)), bw = new SolidBrush(Color.White),
            bg = new SolidBrush(Color.FromArgb(0x8A, 0x90, 0xA0)), brd = new SolidBrush(Color.FromArgb(0xE0, 0x3A, 0x3A)),
            bo = new SolidBrush(Color.FromArgb(0xF2, 0x85, 0x2A)), bod = new SolidBrush(Color.FromArgb(0xC2, 0x5E, 0x14)), byl = new SolidBrush(Color.FromArgb(0xFF, 0xD8, 0x4A));
        public BallForm(int ps) : base(false) { this.ps = ps; Size = new Size(8 * ps, 8 * ps); }
        public string Kind { get { return kind; } set { if (kind != value) { kind = value; Invalidate(); } } }
        public static string[] Art(string kind) { return kind == "baseball" ? BASEBALL : (kind == "tubby" ? TUBBYBALL : TENNIS); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(KEY);
            string[] art = Art(kind);
            for (int r = 0; r < 8; r++)
                for (int i = 0; i < 8; i++)
                {
                    char c = art[r][i];
                    if (c == '.') continue;
                    SolidBrush b = c == 'k' ? bk : (c == 'T' ? bt : (c == 'g' ? bg : (c == 'R' ? brd : (c == 'O' ? bo : (c == 'o' ? bod : (c == 'Y' ? byl : bw))))));
                    g.FillRectangle(b, i * ps, r * ps, ps, ps);
                }
        }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Left && Kicked != null) Kicked();
        }
    }

    // 煙火（蓋住一整個螢幕、點得穿）
    class FxForm : OverlayForm
    {
        readonly List<double[]> parts = new List<double[]>(); // x, y, vx, vy, 年齡, 壽命, 顏色, 種類(0 火箭 / 1 火花)
        readonly List<double[]> plan = new List<double[]>();  // 時間, x, 目標 y, 顏色
        readonly double k;
        readonly Random rnd = new Random();
        readonly SolidBrush[] cols;
        double t;
        public bool Active;

        public FxForm(double k) : base(true)
        {
            this.k = k;
            int[] rgb = { 0xFF5A5A, 0xFFD84A, 0x5AD1FF, 0xFF8FD8, 0x8CFF8C, 0xFFA64A };
            cols = new SolidBrush[rgb.Length];
            for (int i = 0; i < rgb.Length; i++) cols[i] = new SolidBrush(Color.FromArgb((rgb[i] >> 16) & 255, (rgb[i] >> 8) & 255, rgb[i] & 255));
        }

        double R(double a, double b) { return a + rnd.NextDouble() * (b - a); }

        // n 發；focusX ≥ 0 時集中在那附近（小煙火）
        public void Start(Rectangle area, int n, int focusX)
        {
            if (!Active || Bounds != area) { Bounds = area; parts.Clear(); plan.Clear(); t = 0; }
            Active = true;
            for (int i = 0; i < n; i++)
            {
                double fx = focusX >= 0 ? Math.Max(30, Math.Min(area.Width - 30, focusX - area.Left + R(-160, 160) * k)) : R(0.12, 0.88) * area.Width;
                plan.Add(new double[] { t + 0.32 * i + R(0, 0.2), fx, (focusX >= 0 ? R(0.35, 0.6) : R(0.12, 0.45)) * area.Height, rnd.Next(cols.Length) });
            }
            if (!Visible) Show();
        }

        public void Step(double dt)
        {
            if (!Active) return;
            t += dt;
            int h = Height;
            for (int i = plan.Count - 1; i >= 0; i--)
            {
                double[] q = plan[i];
                if (t < q[0]) continue;
                parts.Add(new double[] { q[1], h, 0, -(h - q[2]) / 0.45, 0, 0.45, q[3], 0 });
                plan.RemoveAt(i);
            }
            for (int i = parts.Count - 1; i >= 0; i--)
            {
                double[] p = parts[i];
                p[4] += dt;
                if (p[7] == 0)
                {
                    p[1] += p[3] * dt;
                    if (p[4] >= p[5])
                    {
                        int n = 40;
                        for (int j = 0; j < n; j++)
                        {
                            double a = Math.PI * 2 * j / n + R(-0.1, 0.1), sp = R(170, 380) * k;
                            parts.Add(new double[] { p[0], p[1], Math.Cos(a) * sp, Math.Sin(a) * sp, 0, R(0.7, 1.15), rnd.NextDouble() < 0.7 ? p[6] : rnd.Next(cols.Length), 1 });
                        }
                        parts.RemoveAt(i);
                    }
                }
                else
                {
                    p[3] += 260 * k * dt;
                    p[2] *= Math.Pow(0.35, dt); p[3] *= Math.Pow(0.6, dt);
                    p[0] += p[2] * dt; p[1] += p[3] * dt;
                    if (p[4] > p[5]) parts.RemoveAt(i);
                }
            }
            if (plan.Count == 0 && parts.Count == 0) { Active = false; Hide(); return; }
            Invalidate();
        }

        public void Stop() { Active = false; plan.Clear(); parts.Clear(); Hide(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(KEY);
            foreach (double[] p in parts)
            {
                bool fading = p[7] == 1 && p[4] > p[5] * 0.7;
                if (fading && Math.Floor(p[4] * 24) % 2 == 0) continue;
                int q = (int)Math.Max(2, (p[7] == 0 || p[4] < p[5] * 0.45 ? 2.4 : 1.5) * k);
                int px = (int)p[0], py = (int)p[1];
                SolidBrush b = cols[(int)p[6]];
                g.FillRectangle(b, px - q / 2, py - q / 2 - q, q, 3 * q);
                g.FillRectangle(b, px - q / 2 - q, py - q / 2, 3 * q, q);
            }
        }
    }

    // 大合照的閃光（點得穿、半透明白）
    class FlashForm : OverlayForm
    {
        public FlashForm() : base(true) { BackColor = Color.White; TransparencyKey = Color.Empty; Opacity = 0; }
    }

    // 黏在視窗角落的小蜘蛛網
    class CobwebForm : OverlayForm
    {
        public readonly IntPtr H;
        public readonly bool RightCorner;
        public readonly double Born;
        public readonly int Side;
        readonly int lw;

        public CobwebForm(IntPtr h, bool right, int side, int lw, double born) : base(true)
        {
            H = h; RightCorner = right; Side = side; this.lw = lw; Born = born;
            Size = new Size(side, side);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(KEY);
            int s = Side;
            float ox = RightCorner ? s - 1 : 0, sx = RightCorner ? -1 : 1;
            const int spokes = 5;
            float[] rings = { 0.32f, 0.58f, 0.84f };
            using (Pen p = new Pen(Color.FromArgb(0x8E, 0x97, 0xB0), lw))
            {
                PointF[,] pts = new PointF[spokes, rings.Length];
                for (int i = 0; i < spokes; i++)
                {
                    double a = Math.PI / 2 * i / (spokes - 1);
                    float dx = (float)Math.Cos(a), dy = (float)Math.Sin(a);
                    float len = s - lw - 1;
                    g.DrawLine(p, ox, 0, ox + sx * dx * len, dy * len);
                    for (int j = 0; j < rings.Length; j++)
                        pts[i, j] = new PointF(ox + sx * dx * len * rings[j], dy * len * rings[j]);
                }
                for (int j = 0; j < rings.Length; j++)
                    for (int i = 0; i + 1 < spokes; i++)
                    {
                        PointF a = pts[i, j], b = pts[i + 1, j];
                        PointF m = new PointF((a.X + b.X) / 2 + (ox - (a.X + b.X) / 2) * 0.12f, (a.Y + b.Y) / 2 * 0.88f);
                        g.DrawLine(p, a, m);
                        g.DrawLine(p, m, b);
                    }
            }
        }
    }

    // 公仔本體的視窗：畫面由 Pet 用 UpdateLayeredWindow 提供；滑鼠事件轉給 Pet
    class PetForm : OverlayForm
    {
        readonly Pet pet;
        public PetForm(Pet pet) : base(false, true) { this.pet = pet; }
        protected override void OnPaint(PaintEventArgs e) { }
        protected override void OnPaintBackground(PaintEventArgs e) { }
        protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); pet.MouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (e.Button == MouseButtons.Right) App.LogAlways("menu: right-up on pet " + pet.P.Id + " at " + Cursor.Position);
            pet.MouseUp(e);
        }
    }

    // ================= 角色資料（Pal）=================
    // 每個角色：id、名字、調色盤（白天／夜晚）、像素圖零件、台詞、移動風格、夜晚風格、球種、配件錨點。
    // 像素圖是 12 格寬（也可以更寬，會置中）× 16 格高的字元格；'.' 是透明。
    // 共用字元：k 外框、p 愛心粉、y 星星黃、w 白；配件用 S W Y P B（每個角色都會有）。
    partial class Pal
    {
        public string Id, Name, Move, BallKind, NightStyle;
        public int NightBubble;
        public Color Accent, Panel, Halo, HaloNight;
        public readonly Dictionary<char, Color> Day = new Dictionary<char, Color>(), Night = new Dictionary<char, Color>();
        public readonly Dictionary<string, string[]> Art = new Dictionary<string, string[]>();
        public readonly Dictionary<string, string[]> Lines = new Dictionary<string, string[]>();
        public int FaceRow = 4;                       // SLEEPY／HAPPY／DIZZY 這些臉蓋掉 FaceRow～FaceRow+2
        public int EyeRow = 5, EyeL = 3, EyeR = 8;    // 眼珠跟著滑鼠（EyeRow < 0：不跟）
        public int HatRow = 0, HatCol = 0, ScarfRow = 8, GlassRow = 4, BadgeRow = 10, BadgeCol = 5, BadgeFrom = 'k';
        public int SideRow = 9;                       // 紅包、蛋糕的高度
        public double Speed = 40;                     // 走路速度（×k）
        public bool KeepAntenna;                      // 帽子戴上後把天線重畫在帽子上面（小波）
        public int TopRows;
        public bool NoGlasses;                        // 眼睛太開，眼鏡戴不上（史迪仔）                           // 頭頂超出 16 格框的列數（小波的天線）
        // 天線寶寶一櫃（丁丁、迪西、拉拉）用的；經典一櫃的角色都是預設值
        public bool Tubby;                            // 丁丁／迪西／拉拉（小波另外寫）
        public double TummyRow = 10.5;                // 肚子電視的中心在第幾列
        public int AntRows = -1;                      // 戴帽子時露在帽子上面的天線列數（-1＝TopRows-1，小波）
        public bool AntThrough;                       // 天線從帽子中間穿出來（不墊高；丁丁太高了）
        public int HeadTop = -1;                      // 頭頂外框那一列在 16 格框的第幾列
        public int BodyTop = 8;                       // 身體第一列在 16 格框的第幾列

        static Color C(int rgb) { return Color.FromArgb((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255); }
        void Col(char c, int day, int night) { Day[c] = C(day); Night[c] = C(night); }
        void Say(string key, params string[] lines) { Lines[key] = lines; }

        static List<Pal> all;
        public static List<Pal> All { get { if (all == null) { all = new List<Pal>(new Pal[] { Spidey(), Po(), Stitch(), Hangyodon(), Tinky(), Dipsy(), LaaLaa() }); all.AddRange(PikminPals()); all.AddRange(OrigPals()); } return all; } }
        public static Pal Get(string id)
        {
            foreach (Pal p in All) if (p.Id == id) return p;
            return null;
        }

        // ---- 兩櫃：經典（Spidey、小波、史迪仔、人魚漢頓）／天線寶寶（丁丁、迪西、拉拉、小波；大格是小波）----
        public const string Classic = "classic", Teletubbies = "teletubbies";
        public static string NormLineup(string s) { string t = s == null ? "" : s.Trim().ToLowerInvariant(); return t == Teletubbies || t == Pikmin || t == Original ? t : Classic; }
        public static string[] LineupIds(string lineup)
        {
            if (NormLineup(lineup) == Pikmin) return (string[])PikminIds.Clone();   // 皮克敏一櫃：大格是休息花（DeskPals.Pikmin.cs）
            if (NormLineup(lineup) == Original) return (string[])OriginalIds.Clone();   // 續命小隊（DeskPals.Original.cs）
            return NormLineup(lineup) == Teletubbies ? new string[] { "tinky", "dipsy", "laalaa", "po" } : new string[] { "spidey", "po", "stitch", "hangyodon" };
        }
        public static List<Pal> Lineup(string lineup)
        {
            List<Pal> l = new List<Pal>();
            foreach (string id in LineupIds(lineup)) l.Add(Get(id));
            return l;
        }
        // 這一櫃預設放在大格的（經典一櫃照用最久的那隻）
        public static string LineupFav(string lineup) { return NormLineup(lineup) == Teletubbies ? "po" : (NormLineup(lineup) == Original ? "boba" : null); }
        // 設定視窗、小屋「換一櫃」列出來的櫃子（之後新增一櫃：這裡加一個 id、LineupIds／LineupName 加一行）
        public static readonly string[] Lineups = { Original, Classic, Teletubbies, Pikmin };
        public static string LineupName(string lineup) { string n = NormLineup(lineup); return n == Original ? OriginalName : (n == Teletubbies ? "天線寶寶一櫃" : (n == Pikmin ? "皮克敏一櫃" : "經典一櫃")); }

        void Shared()
        {
            foreach (Dictionary<char, Color> d in new Dictionary<char, Color>[] { Day, Night })
            {
                d['S'] = C(0xE23B3B); d['W'] = Color.White; d['Y'] = C(0xF5C842); d['P'] = C(0xFF8FB0); d['B'] = C(0xB8D6FF);
                if (!d.ContainsKey('p')) d['p'] = C(0xFF6F9C);
                if (!d.ContainsKey('y')) d['y'] = C(0xFFD84A);
                if (!d.ContainsKey('w')) d['w'] = Color.White;
                d['1'] = C(0xD9A55B); d['2'] = C(0xA8743A);   // 木頭（球棒、搖椅、烏克麗麗）
                d['3'] = C(0xF4F1EA);                          // 棒球白
                d['4'] = C(0xE03A3A);                          // 棒球縫線
                d['5'] = C(0xA0703F); d['6'] = C(0x6E4524);   // 手套皮革
                d['7'] = C(0x8E97B0); d['8'] = C(0xFFFFFF);   // 絲、閃光
            }
            if (Lines.ContainsKey("talk") && !Lines.ContainsKey("talk_d")) Lines["talk_d"] = Lines["talk"];
        }

        // 把幾段零件疊成一張圖（每段寬度不同時置中補齊）
        public static string[] Stack(params string[][] parts)
        {
            List<string> rows = new List<string>();
            int w = 0;
            foreach (string[] p in parts) foreach (string r in p) w = Math.Max(w, r.Length);
            foreach (string[] p in parts)
                foreach (string r in p)
                {
                    int l = (w - r.Length) / 2;
                    rows.Add(new string('.', l) + r + new string('.', w - r.Length - l));
                }
            return rows.ToArray();
        }

        // ---------------- Spidey（原本那隻，外觀台詞完全照舊）----------------
        static Pal Spidey()
        {
            Pal p = new Pal();
            p.Id = "spidey"; p.Name = "Spidey"; p.Move = "web"; p.BallKind = "tennis"; p.NightStyle = "dark"; p.NightBubble = 1;
            p.Accent = C(0x2A2F45); p.Panel = C(0xF3D9D6); p.Halo = Color.White; p.HaloNight = C(0xC8C0EC);
            p.Col('k', 0x2A2F45, 0x0B0B10); p.Col('r', 0xD84A4A, 0x2C2E3B); p.Col('R', 0xA83A3A, 0x1B1C26); p.Col('b', 0x3D5FAE, 0x3E4055);
            p.Col('w', 0xFFFFFF, 0xF6F6FA); p.Col('p', 0xFF6F9C, 0xB04A6E); p.Col('y', 0xFFD84A, 0xB9A7FF);
            p.Art["HEAD"] = new string[] { "...kkkkkk...", "..krrrrrrk..", ".krRrrrrRrk.", ".krrrRRrrrk.", ".kwwkrrkwwk.", ".kwwwkkwwwk.", ".krwwrrwwrk.", "..krrRRrrk.." };
            p.Art["SLEEPY"] = new string[] { ".krrrrrrrrk.", ".kkkkrrkkkk.", ".krrrrrrrrk." };
            p.Art["HAPPY"] = new string[] { ".krkrrrrkrk.", ".kkrkrrkrkk.", ".kprrrrrrpk." };
            p.Art["DIZZY"] = new string[] { ".kkwkrrkwkk.", ".kwkwkkwkwk.", ".kkwkrrkwkk." };
            p.Art["BODY"] = new string[] { "...kkkkkk...", "..kbrrrrbk..", ".kbbrkkrbbk.", ".krbrrrrbrk.", "..kbbbbbbk.." };
            p.Art["ARMS_UP"] = new string[] { "kr.kkkkkk.rk", "kbkbrrrrbkbk", ".kbbrkkrbbk.", "..kbrrrrbk..", "..kbbbbbbk.." };
            p.Art["ARMS_HUG"] = new string[] { "...kkkkkk...", ".kkbrrrrbkk.", "krrrkkkkrrrk", ".kkbrrrrbkk.", "..kbbbbbbk.." };
            p.Art["LEGS_A"] = new string[] { "..kbbkkbbk..", "..krrkkrrk..", "..kkk..kkk.." };
            p.Art["LEGS_B"] = new string[] { "..kbbkkbbk..", ".krrk..krrk.", ".kkk....kkk." };
            p.FaceRow = 4; p.EyeRow = 5; p.EyeL = 3; p.EyeR = 8;
            p.HatRow = 0; p.ScarfRow = 8; p.GlassRow = 4; p.BadgeRow = 10; p.BadgeCol = 5; p.SideRow = 9;
            p.Speed = 40;
            p.Say("talk", "嗨！今天也一起寫 code 吧", "能力越強，bug 越少！", "蜘蛛感應：你存檔了嗎？", "要不要喝口可樂？", "整個螢幕都是我的地盤！", "這個視窗頂端風景不錯", "Thwip! 🕸");
            p.Say("talk_d", "都幾點了還不下班？", "老闆不會多給你加班費的。", "……你還在？", "這個 bug 明天還會在，你不用在。", "下班。現在。", "你的床在等你。我也在等你關機。");
            p.Say("save", "存好了！👍", "存檔成功，帥！", "Thwip! 已存檔", "穩穩的 👍");
            p.Say("save_d", "存了就快走。", "存好了。可以關機了吧？", "……存檔。然後下班。");
            p.Say("pats", "你今天也很棒！", "累了就休息一下，我陪你", "有我在，bug 不敢來", "我一直都在喔 ♥", "你寫的 code 很帥",
                "辛苦了，摸摸頭", "不管怎樣我都站你這邊", "今天也謝謝你陪我", "慢慢來，你可以的", "嘿嘿，再摸一下", "你笑起來一定很好看", "有你在我就很安心");
            p.Say("pats_d", "……摸夠了就下班。", "我是擔心你才一直催你。", "你已經很努力了，剩下的明天再說。", "回家好好吃飯，聽到沒？", "哼，就讓你摸一下。", "我不是在撒嬌，是在叫你下班。");
            p.Say("pats_hi", "能遇到你真好", "我最喜歡你了 ♥", "今天也要一起喔", "有你在，每天都很開心", "我們是最佳拍檔！");
            p.Say("hugs", "抱抱～", "給你一個蜘蛛抱抱 ♥", "辛苦了，抱一下", "(つ´ω`)つ ♥");
            p.Say("hugs_d", "……只抱一下。然後下班。", "抱完就回家，聽到沒？", "(つ﹏⊂) 回家啦");
            p.Say("knock", "叩叩！你在看我嗎？👀", "嘿～螢幕外面的你！", "我可以出去玩嗎？叩叩", "你今天也很努力喔！");
            p.Say("knock_d", "叩、叩。下班了沒？", "我在螢幕裡面都看到了，你還在加班。", "再不關機我要黑掉你的螢幕喔（騙你的）");
            p.Say("newwin", "新視窗！Thwip!", "我來看看這是什麼～", "噴個絲黏上去！");
            p.Say("newwin_d", "又開新視窗？想加班？", "……這個也明天再看。", "不准再開了。");
            p.Say("hi", "嗨！我是你的 Spidey 👋"); p.Say("hi_d", "……嗨。下班了嗎？");
            p.Say("wake", "嗯…是你呀 ♥ 我醒了"); p.Say("wake_d", "……是你啊。我沒睡，只是在等你下班。");
            p.Say("dizzy", "頭暈了 @@ 你好愛我喔"); p.Say("dizzy_d", "別、別再點了……頭好暈");
            p.Say("dizzy_ok", "好、好了，我沒事 ♥"); p.Say("dizzy_ok_d", "……沒事。");
            p.Say("tickle", "哈哈哈好癢～"); p.Say("tickle_d", "……好癢。不准笑。");
            p.Say("pat10", "今天第 {n} 次摸我了，我好開心 ♥"); p.Say("pat10_d", "今天第 {n} 次了……我才沒有很開心。");
            p.Say("levelup", "好感度升到 Lv{n} 了！解鎖「{u}」♥"); p.Say("levelup_d", "……好感度 Lv{n}。解鎖「{u}」。我、我才沒有很高興。");
            p.Say("missed", "你最近都不理我…摸摸我好不好 🥺"); p.Say("missed_d", "……你好幾天沒摸我了。哼。");
            p.Say("hover", "你在摸我嗎？抱抱～");
            p.Say("seek", "那是什麼？"); p.Say("seek_lost", "咦，跑掉了…"); p.Say("seek_got", "抓到你的滑鼠了！抱抱 ♥");
            p.Say("drag", "哇啊——放我下來！"); p.Say("throw", "咻——");
            p.Say("shelf_in", "好～我回公仔櫃乖乖待著 ♥"); p.Say("shelf_in_d", "……好，我回櫃子裡待著。你也早點回家。");
            p.Say("shelf_out", "自由了！出去玩囉～"); p.Say("shelf_out_d", "……放我出來了？那我要去催你下班了。");
            p.Say("ball_go", "球！我來了！", "等我～", "這次一定接到！"); p.Say("ball_go_d", "……好啦，陪你玩一下。");
            p.Say("ball_catch", "接到了！還你～", "好球！傳回去！", "嘿嘿，我很厲害吧"); p.Say("ball_catch_d", "……接到了。還你。");
            p.Say("ball_end", "不玩了嗎？好吧～下次再玩 ⚾"); p.Say("ball_end_d", "……不玩了？那就下班吧。");
            p.Say("ball_far", "球跑太遠了啦～");
            p.Say("back", "我回來了～"); p.Say("back_d", "……我回來了。");
            p.Say("share_end", "分享結束了～我回來囉");
            p.Say("welcome", "你回來啦！我等你好久 ♥"); p.Say("welcome_d", "……你回來了。是要來關機的吧？");
            p.Say("rest", "已經連續用 {n} 分鐘了，起來喝口可樂、伸展一下！🥤"); p.Say("rest_d", "……喝完可樂就下班。");
            p.Say("night_on", "……下班時間到了。"); p.Say("night_off", "早安，我又變回來了 ☀");
            p.Say("sleep", "晚安…"); p.Say("sleep_d", "……你也該睡了。");
            p.Say("jump", "跳～"); p.Say("nojump", "附近沒有可以跳的視窗");
            p.Say("errors", "蜘蛛感應！有 {n} 個錯誤"); p.Say("errors_d", "{n} 個錯誤……明天再修，回家。");
            p.Say("errors_ok", "錯誤都清光了，抱一個！"); p.Say("errors_ok_d", "錯誤清完了。那就可以下班了吧。");
            p.Say("typing", "你打字好快！加油加油 ♪", "手指在冒煙了！🔥", "衝衝衝～我幫你打氣！"); p.Say("typing_d", "打這麼快是想快點下班吧？加油。");
            p.Say("done", "{who} 做完了！快來看 👀"); p.Say("done_d", "{who} 做完了。你也該收工了。");
            p.Say("wait", "{who} 在等你回答喔～ 👋"); p.Say("wait_d", "{who} 在等你回答。快點回完快點下班。");
            p.Say("ask", "{who} 在問你問題，等你回答喔～ 🙋"); p.Say("ask_d", "{who} 在問你問題。回完就下班。");
            p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，是不是在等你按允許？"); p.Say("stuck_tool_d", "{who} 停了 {n} 分鐘。去按一下，然後下班。");
            p.Say("stuck", "{who} 好像卡住了…{n} 分鐘沒動靜，去看看？ 🕷️"); p.Say("stuck_d", "{who} 卡住 {n} 分鐘了。去看一眼，看完就下班。");
            p.Say("unstuck", "{who} 又動起來了！👍"); p.Say("unstuck_d", "{who} 動了。");
            p.Say("tag", "上版成功！🎆"); p.Say("tag_dev", "測試機上版成功！🎆"); p.Say("tag_prod", "上正式機了！🎉 辛苦了！"); p.Say("tag_d", "上版成功……那現在可以下班了吧？🎆");
            p.Say("late23", "很晚了耶，早點休息好不好 🌙"); p.Say("late12", "午餐吃了沒？"); p.Say("late15", "下午茶時間～來罐可樂吧 🥤");
            p.Say("late_d", "下班時間早就過了喔。"); p.Say("late_dd", "這麼晚了。關機，睡覺。");
            p.Say("g_late", "這麼晚還在寫？我陪你 🌙"); p.Say("g_morning", "早安！今天也一起加油 ☀"); p.Say("g_noon", "午安～吃飯了沒？我出來陪你");
            p.Say("g_evening", "晚上了，辛苦啦，我陪你"); p.Say("g_day", "我出來玩啦！整個螢幕都是我的 🕸"); p.Say("g_d", "……下班時間了。你為什麼還開著電腦？");
            p.Say("app_browser", "又在逛網頁？帶我一起看～"); p.Say("app_code", "回來寫 code 啦！我陪你"); p.Say("app_excel", "在算數字喔，加油！");
            p.Say("app_ppt", "在做簡報？我幫你盯排版"); p.Say("app_word", "在寫文件～慢慢來"); p.Say("app_chat", "有人找你嗎？"); p.Say("app_files", "在找檔案？");
            p.Say("app_other", "你在用這個呀？我也來看看");
            p.Say("app_code_d", "還在寫 code？下班了啦。"); p.Say("app_chat_d", "下班了還回訊息？明天再說。"); p.Say("app_office_d", "這份明天做也不會怎樣。"); p.Say("app_other_d", "……你在做什麼？不是該下班了嗎。");
            p.Say("s_birthday", "生日快樂！🎂 今天你最大！", "祝你生日快樂～我做了蛋糕給你", "今天是你的日子，什麼都不准煩惱 ♥");
            p.Say("s_cny", "新年快樂！恭喜發財 🧧", "紅包拿來～（騙你的，這個給你）", "新的一年也一起加油！");
            p.Say("s_xmas", "聖誕快樂！🎄", "我想要的聖誕禮物，就是你準時下班", "叮叮噹～叮叮噹～ ❄");
            p.Say("s_newyear", "新年快樂！今年也請多多指教 ✨");
            p.Say("s_halloween", "不給糖就搗蛋！🎃", "我今天扮成……蜘蛛人（本來就是）");
            p.Say("s_friday", "週五了！！撐住！", "小週末～今天準時下班好不好", "再一下下就週末了 ✨");
            p.Say("morning", "早安！Spidey 報到 🕸", "早安～今天也要一起守護城市（的 code）");
            p.Say("goodnight", "晚安，我先回櫃子裡巡邏… 🕸", "……今天辛苦了。晚安。");
            p.Say("nag", "下班。現在。", "你的床在等你。", "……還不走？");
            p.Say("react", "！", "怎麼了？", "蜘蛛感應！");
            p.Shared();
            return p;
        }

        // ---------------- 小波（紅色天線寶寶，同人像素）----------------
        static Pal Po()
        {
            Pal p = new Pal();
            p.Id = "po"; p.Name = "小波"; p.Move = "scooter"; p.BallKind = "baseball"; p.NightStyle = "sunset"; p.NightBubble = 2;
            p.Accent = C(0xE7836A); p.Panel = C(0xFFE3CF); p.Halo = Color.White; p.HaloNight = C(0xFFC58F);
            // 夜晚：太陽寶寶下山 → 整體暗一點、偏夕陽橘紫
            p.Col('k', 0x3A1A1A, 0x2A1220); p.Col('r', 0xE3262B, 0xB4303A); p.Col('R', 0xA8161C, 0x7E1A2A); p.Col('h', 0xFF5A5E, 0xD8505A); p.Col('e', 0xF4CDBE, 0xD3A79C);
            p.Col('f', 0xF6D2B0, 0xD9AE92); p.Col('F', 0xE8B892, 0xBF907A); p.Col('m', 0xB8323C, 0x8E2E40); p.Col('p', 0xF29A9A, 0xC97A84);
            p.Col('g', 0xC9CDD3, 0x8F8CA6); p.Col('G', 0x8E949C, 0x5F5C78); p.Col('w', 0xFFFFFF, 0xFFE4CC); p.Col('y', 0xFFD84A, 0xFFB45E);
            p.Col('s', 0x55C7BE, 0x3F8F95); p.Col('q', 0x2F8F88, 0x266A70); p.Col('o', 0x6B6F7A, 0x4E4A5E); // 滑板車：踏板、深色、輪子
            // 天線（中空圓圈）＋大圓頭：紅色頭套框住一張很大的膚色平臉，兩邊小耳朵
            p.Art["HEAD"] = new string[] {
                ".......rr.......",
                "......r..r......",
                ".......rr.......",
                ".......rr.......",
                ".....kkkkkk.....",
                "...kkrrrrrrkk...",
                ".kkhrffffffrRkk.",
                "kehrffffffffrRek",
                "kehrfkffffkfrRek",
                "kehrfkffffkfrRek",
                "kehrpfmffmfprRek",
                ".kkhrffmmffrRkk.",
                "...kkrrrrrrkk..." };
            p.Art["SLEEPY"] = new string[] {
                "kehrffffffffrRek",
                "kehrffffffffrRek",
                "kehrkkffffkkrRek",
                "kehrpffffffprRek",
                ".kkhrffmmffrRkk." };
            p.Art["HAPPY"] = new string[] {
                "kehrffffffffrRek",
                "kehrfkffffkfrRek",
                "kehrkfkffkfkrRek",
                "kehrpmffffmprRek",
                ".kkhrfmmmmfrRkk." };
            p.Art["DIZZY"] = new string[] {
                "kehrffffffffrRek",
                "kehrkfkffkfkrRek",
                "kehrfkffffkfrRek",
                "kehrkfkffkfkrRek",
                ".kkhrffmmffrRkk." };
            p.Art["SQUISH"] = new string[] {
                "kehrffffffffrRek",
                "kehrkkffffkkrRek",
                "kehrkkffffkkrRek",
                "kehrpffmmffprRek",
                ".kkhrffmmffrRkk." };
            p.Art["BODY"] = new string[] {
                "..khGGGGGGGGRk..",
                "rkhrGwggggggGRkr",
                "rkhrGggggggGrRkr",
                ".khrGggggggGrRk.",
                "..khGGGGGGGGRk..",
                "...kRrrrrrrrRk.." };
            p.Art["ARMS_UP"] = new string[] {
                "rkkhGGGGGGGGRkkr",
                ".khrGwgggggGrRk.",
                ".khrGggggggGrRk.",
                ".khrGggggggGrRk.",
                "..khGGGGGGGGRk..",
                "...kRrrrrrrrRk.." };
            p.Art["ARMS_HUG"] = new string[] {
                "....khGGGGGGGGRk....",
                "rrrkhrGwgggggGrRkrrr",
                "kkkkhrGggggggGrRkkkk",
                "...khrGggggggGrRk...",
                "....khGGGGGGGGRk....",
                ".....kRrrrrrrrRk...." };
            p.Art["LEGS_A"] = new string[] {
                "...krrk..krrk...",
                "...kkkk..kkkk..." };
            p.Art["LEGS_B"] = new string[] {
                "..krrk....krrk..",
                "..kkkk....kkkk.." };
            p.Art["LEGS_RIDE"] = new string[] {
                "....krrkkrrk....",
                "....kkkkkkkk...." };
            p.Art["LEGS_SIT"] = new string[] {
                "..krrkkkkkkrrk..",
                ".kkkk......kkkk." };
            // 滑板車（面向右；拉到 14 格寬，車頭在右邊）
            p.Art["SCOOTER"] = new string[] {
                "...........kk.",
                "...........ks.",
                "...........ks.",
                "...........ks.",
                "...........ks.",
                ".kkkkkkkkkkks.",
                ".kssssssssssk.",
                ".kooq....kooq.",
                "..oo......oo.." };
            p.HatRow = 0; p.HatCol = 0; p.ScarfRow = 7; p.GlassRow = 3; p.BadgeRow = 12; p.BadgeCol = 5; p.SideRow = 9;
            p.EyeRow = -1; p.FaceRow = 7; p.Speed = 95; p.KeepAntenna = true; p.TopRows = 5;
            p.Say("talk", "Eh-oh!", "我們一起騎車車～", "抱抱時間到了沒？", "今天天氣好好喔 ☀", "小波最喜歡你了", "要喝可樂樂喔 🥤", "嘟嘟～小波來囉");
            p.Say("talk_d", "太陽寶寶下山了，該說再見囉", "小波想睡覺覺了…你也回家好不好", "天黑黑了，明天再玩", "晚安晚安～該回家囉", "再見再見～（揮揮手）");
            p.Say("save", "存好了！好棒棒 👏", "存起來了～再來一次！", "Eh-oh! 存檔成功", "小波幫你收好囉");
            p.Say("save_d", "存好了…那我們回家好不好", "存好了，太陽寶寶也下山囉", "收好了～該說再見囉");
            p.Say("pats", "嘻嘻，好舒服", "你好棒棒！", "小波喜歡你 ♥", "摸摸頭～你也辛苦了", "Eh-oh! 再摸一下", "你笑一個嘛 😊", "有小波陪你喔", "慢慢來，小波等你");
            p.Say("pats_d", "嗯…小波想睡覺覺了", "摸摸…然後我們回家好不好", "太陽寶寶下山了，你也該休息囉", "嘿嘿…明天再陪你玩");
            p.Say("pats_hi", "能遇到你真好 ♥", "小波最最最喜歡你了", "我們是好朋友！", "每天都要一起玩喔");
            p.Say("hugs", "大抱抱！", "大抱抱～ ♥", "Eh-oh! 大抱抱！", "(つ´ω`)つ 大抱抱");
            p.Say("hugs_d", "大抱抱…然後回家睡覺覺", "晚安大抱抱 ♥", "抱完就說再見囉");
            p.Say("knock", "叩叩！Eh-oh! 👀", "嗨嗨～螢幕外面的你！", "小波可以出去玩嗎？", "肚肚貼玻璃～嘿嘿");
            p.Say("knock_d", "叩叩…太陽寶寶下山了喔", "該說再見囉，回家吧～", "小波看到你還在加班…");
            p.Say("newwin", "Eh-oh!", "Eh-oh! 新視窗！", "咻～我來看看！");
            p.Say("newwin_d", "Eh-oh…又開新的了？明天再看嘛", "天黑黑了，不要再開了啦");
            p.Say("hi", "Eh-oh! 我是小波 👋"); p.Say("hi_d", "Eh-oh…太陽寶寶下山了耶");
            p.Say("wake", "嗯…Eh-oh? 是你呀 ♥"); p.Say("wake_d", "嗯…小波在睡覺覺…你也去睡嘛");
            p.Say("dizzy", "轉圈圈～頭暈暈 @@"); p.Say("dizzy_d", "暈暈…小波要睡覺覺了…");
            p.Say("dizzy_ok", "好了！再來一次！"); p.Say("dizzy_ok_d", "好了…該回家囉");
            p.Say("tickle", "再來一次！", "再來一次！再來一次！", "嘻嘻嘻好癢～再來一次！"); p.Say("tickle_d", "嘻嘻…最後一次喔");
            p.Say("pat10", "今天第 {n} 次摸摸了！小波好開心 ♥"); p.Say("pat10_d", "第 {n} 次了…摸完就回家喔");
            p.Say("levelup", "好感度 Lv{n}！小波拿到「{u}」了 ♥"); p.Say("levelup_d", "Lv{n}…拿到「{u}」…明天再戴給你看");
            p.Say("missed", "你好久沒摸摸小波了…🥺"); p.Say("missed_d", "好久沒摸摸了…明天要記得喔");
            p.Say("hover", "Eh-oh? 你在摸摸我嗎～");
            p.Say("seek", "咦？那是什麼？"); p.Say("seek_lost", "跑掉了…"); p.Say("seek_got", "抓到滑鼠了！大抱抱！");
            p.Say("drag", "哇～飛高高！"); p.Say("throw", "咻～～");
            p.Say("shelf_in", "小波回家家囉，掰掰 👋"); p.Say("shelf_in_d", "太陽寶寶下山了，小波回家睡覺覺");
            p.Say("shelf_out", "Eh-oh! 小波出來玩囉！"); p.Say("shelf_out_d", "Eh-oh…天黑黑了耶，你怎麼還在？");
            p.Say("ball_go", "棒球！小波來了！", "我接我接！", "看我的手套！"); p.Say("ball_go_d", "最後一球喔…");
            p.Say("ball_catch", "接到了！傳回去～", "好球！", "嘿嘿，手套好厲害"); p.Say("ball_catch_d", "接到了…還你，該回家囉");
            p.Say("ball_end", "不玩了嗎？下次再來一次！⚾"); p.Say("ball_end_d", "不玩了…那我們回家吧");
            p.Say("ball_far", "球球跑好遠喔～");
            p.Say("back", "Eh-oh! 小波回來了"); p.Say("back_d", "小波回來了…");
            p.Say("share_end", "分享完了～Eh-oh!");
            p.Say("welcome", "Eh-oh! 你回來了！大抱抱！"); p.Say("welcome_d", "你回來了…是要回家了嗎？");
            p.Say("rest", "已經 {n} 分鐘了，起來動一動、喝口可樂樂 🥤"); p.Say("rest_d", "{n} 分鐘了…太陽寶寶都下山了，回家吧");
            p.Say("night_on", "太陽寶寶下山了…該說再見囉"); p.Say("night_off", "太陽寶寶起床了！Eh-oh! ☀");
            p.Say("sleep", "睡覺覺…晚安"); p.Say("sleep_d", "晚安晚安…你也去睡覺覺");
            p.Say("jump", "咻～"); p.Say("nojump", "附近沒有可以飛的地方耶");
            p.Say("errors", "嗚…有 {n} 個錯誤，好可怕"); p.Say("errors_d", "{n} 個錯誤…明天再修啦，回家");
            p.Say("errors_ok", "錯誤都不見了！大抱抱！"); p.Say("errors_ok_d", "都修好了！那我們回家吧");
            p.Say("typing", "打好快喔！嘟嘟嘟～", "加油加油！再來一次！", "手指在跳舞耶 ♪"); p.Say("typing_d", "打好快…是想快點回家吧");
            p.Say("done", "全壘打！{who} 做完了！"); p.Say("done_d", "全壘打！{who} 做完了～太陽寶寶下山了，回家吧");
            p.Say("wait", "{who} 在等你回答喔 👋"); p.Say("wait_d", "{who} 在等你…回完就回家喔");
            p.Say("ask", "{who} 有問題要問你喔 🙋"); p.Say("ask_d", "{who} 在問你問題…回完就回家");
            p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，要你按按看嗎？"); p.Say("stuck_tool_d", "{who} 停了 {n} 分鐘…按一下就回家");
            p.Say("stuck", "{who} 不動了…{n} 分鐘了耶，去看看？"); p.Say("stuck_d", "{who} 卡住 {n} 分鐘了…看完就說再見囉");
            p.Say("unstuck", "{who} 又動了！好棒棒 👏"); p.Say("unstuck_d", "{who} 動了…");
            p.Say("tag", "全壘打！上版成功！⚾"); p.Say("tag_dev", "測試機全壘打！⚾"); p.Say("tag_prod", "正式機全壘打！好棒棒 🎉"); p.Say("tag_d", "全壘打…上完了，回家吧");
            p.Say("late23", "好晚了…小波想睡覺覺 🌙"); p.Say("late12", "吃飯飯了沒？"); p.Say("late15", "點心時間～吐司要不要？");
            p.Say("late_d", "太陽寶寶早就下山了喔"); p.Say("late_dd", "好晚好晚了…晚安，回家吧");
            p.Say("g_late", "這麼晚了…小波陪你一下下 🌙"); p.Say("g_morning", "Eh-oh! 早安！太陽寶寶起床了 ☀"); p.Say("g_noon", "Eh-oh! 午安～吃飯飯了沒？");
            p.Say("g_evening", "Eh-oh～晚上了，辛苦了"); p.Say("g_day", "Eh-oh! 小波來玩囉！"); p.Say("g_d", "太陽寶寶下山了…你怎麼還在？");
            p.Say("app_browser", "在看什麼？小波也要看～"); p.Say("app_code", "寫 code 時間！小波陪你"); p.Say("app_excel", "好多格子喔～");
            p.Say("app_ppt", "做簡報～要畫太陽寶寶嗎？"); p.Say("app_word", "寫字字～慢慢來"); p.Say("app_chat", "有人找你玩嗎？"); p.Say("app_files", "在找東西嗎？");
            p.Say("app_other", "Eh-oh! 這是什麼？");
            p.Say("app_code_d", "還在寫…太陽寶寶下山了啦"); p.Say("app_chat_d", "天黑了，明天再回嘛"); p.Say("app_office_d", "明天再做好不好～"); p.Say("app_other_d", "該說再見囉～");
            p.Say("s_birthday", "生日快樂！小波唱歌給你聽 🎂", "今天你最大！大抱抱！");
            p.Say("s_cny", "新年快樂！恭喜恭喜 🧧", "紅包…小波可以拿嗎？");
            p.Say("s_xmas", "聖誕快樂！🎄", "叮叮噹～小波想要新車車");
            p.Say("s_newyear", "新年快樂！Eh-oh! ✨");
            p.Say("s_halloween", "不給糖就搗蛋！🎃", "小波扮成…番茄！");
            p.Say("s_friday", "星期五了！再來一次週末！", "快放假了～騎車車去玩！");
            p.Say("morning", "Eh-oh! 早安～小波來了！", "太陽寶寶起床囉！早安！");
            p.Say("goodnight", "太陽寶寶下山了，小波說再見囉 👋", "晚安晚安～大抱抱");
            p.Say("nag", "太陽寶寶下山了，該說再見囉", "回家家囉～", "小波想睡覺覺了…");
            p.Say("react", "Eh-oh?", "咦？", "怎麼了怎麼了？");
            p.Shared();
            return p;
        }

        // ---------------- 史迪仔（藍色小外星人，同人像素）----------------
        static Pal Stitch()
        {
            Pal p = new Pal();
            p.Id = "stitch"; p.Name = "史迪仔"; p.Move = "crawl"; p.BallKind = "tennis"; p.NightStyle = "sleepy"; p.NightBubble = 3;
            p.Accent = C(0x3461B4); p.Panel = C(0xD8E7FA); p.Halo = Color.White; p.HaloNight = C(0xA9C8F5);
            // 使用者核准的母版 D（22×25）：槳狀大耳朵（粉紅內側、左耳缺口）、寬頭沒脖子、細淺框大黑眼、圓圓深藍大鼻子、露牙笑、梨形身體大淺肚
            p.Col('k', 0x1B2A4A, 0x111A30); p.Col('b', 0x3D6BB3, 0x33598F); p.Col('d', 0x2B4F86, 0x22406C); p.Col('l', 0x8FB6E6, 0x7092BE);
            p.Col('p', 0xE58FB8, 0xB57090); p.Col('e', 0x0A0A14, 0x0A0A14); p.Col('w', 0xFFFFFF, 0xDDEBFF); p.Col('n', 0x1C2A55, 0x151F40);
            p.Col('h', 0x5B6FA8, 0x46588A); p.Col('m', 0x5A1A2A, 0x441420); p.Col('t', 0xE86A8A, 0xB85670); p.Col('q', 0xF4EFD8, 0xCFCAB4); p.Col('y', 0xFFD84A, 0xC9D8FF);
            p.Art["HEAD"] = new string[] {
                "..kkkk..........kkkk..",
                "..bppk..........kppbk.",
                ".kpppbk........kbpppk.",
                ".kpppbk........kbpppk.",
                ".kpppk.....k....kpppk.",
                ".kpppk....kk....kpppk.",
                ".kppbk.kkkbbkkk.kbppk.",
                "..kbbbkbbbbbbbbkbbbk..",
                "...kbbbllbbbbllbbbk...",
                "...kbbllwebblewlbbk...",
                "....kbleeennleeebk....",
                "....kbleenhnneeebk....",
                "....kbllennnneelbk....",
                ".....kbmbbbbbbmbk.....",
                "......kmmqmmqmmk......",
                ".....kbbbbttbbbbk....." };
            p.Art["EARS_UP"] = new string[] {
                "..kkkk..........kkkk..",
                "..bppk..........kppbk.",
                ".kpppbk........kbpppk.",
                ".kpppbk........kbpppk.",
                ".kpppk.....k....kpppk.",
                ".kpppk....kk....kpppk.",
                ".kppbk.kkkbbkkk.kbppk.",
                "..kbbbkbbbbbbbbkbbbk.." };
            p.Art["EARS_DOWN"] = new string[] {
                "......................",
                "......................",
                "......................",
                "......................",
                "...........k..........",
                "..kkk.....kk.....kkkk.",
                "kpppbkkkkkbbkkkkkbpppk",
                ".kkbbbkbbbbbbbbkbbbkk." };
            p.Art["SLEEPY"] = new string[] {
                "...kbbllllbbllllbbk...",
                "....kbllllnnllllbk....",
                "....kbleenhnnleebk....",
                "....kblllnnnnlllbk....",
                ".....kbmbbbbbbmbk.....",
                "......kmmqmmqmmk......" };
            p.Art["HAPPY"] = new string[] {
                "...kbbllllbbllllbbk...",
                "....kbllelnnllelbk....",
                "....kblelnhnnelebk....",
                "....kblllnnnnlllbk....",
                ".....kbmbbbbbbmbk.....",
                "......kmmqmmqmmk......" };
            p.Art["DIZZY"] = new string[] {
                "...kbblelebblelebbk...",
                "....kbllelnnllelbk....",
                "....kblelehnnelebk....",
                "....kblllnnnnlllbk....",
                ".....kbmbbbbbbmbk.....",
                "......kmmqmmqmmk......" };
            p.Art["GRIN"] = new string[] {
                "...kbbllwebblewlbbk...",
                "....kbleeennleeebk....",
                "....kbleenhnneeebk....",
                "....kbllennnneelbk....",
                ".....kbmbbbbbbmbk.....",
                "......kmqmqmqmmk......" };
            p.Art["LICKF"] = new string[] {
                "...kbbllllbbllllbbk...",
                "....kbllelnnllelbk....",
                "....kblelnhnnelebk....",
                "....kblllnnnnlllbk....",
                ".....kbmbbbbbbmbk.....",
                "......kmmqmmqmmk......" };
            p.Art["BODY"] = new string[] {
                ".....kbdbbllbbdbk.....",
                ".....kbdlllllldbk.....",
                "....kbbdlllllldbbk....",
                "....kbbdlllllldbbk....",
                "....kkbbllllllbbkk....",
                ".....kbbbkkkkbbbk....." };
            p.Art["ARMS_UP"] = new string[] {
                ".....kbbbbllbbbbk.....",
                "..kkkbbbllllllbbbkkk..",
                "..kbbkbllllllllbkbbk..",
                "..kkkbbllllllllbbkkk..",
                "....kbbllllllllbbk....",
                "....kkbbllllllbbkk...." };
            p.Art["ARMS_HUG"] = new string[] {
                ".....kbdbbllbbdbk.....",
                ".....kbdlllllldbk.....",
                "....kbbddddddddbbk....",
                "....kbbbllllllbbbk....",
                "....kbbllllllllbbk....",
                "....kkbbllllllbbkk...." };
            p.Art["LICK"] = new string[] {
                ".....kbdbtttbbdbk.....",
                ".....kbdltttlldbk.....",
                "....kbbdllttlldbbk....",
                "....kbbdlllllldbbk....",
                "....kkbbllllllbbkk....",
                ".....kbbbkkkkbbbk....." };
            p.Art["LEGS_A"] = new string[] {
                ".....kbbk....kbbk.....",
                "......kk......kk......" };
            p.Art["LEGS_B"] = new string[] {
                ".....kbbk.....kbbk....",
                "......kk.......kk....." };
            p.Art["CRAWL_A"] = new string[] {
                ".....kbbbllllbbbk.....",
                "....kbbk.kkkk.kbbk....",
                "....kkk........kkk...." };
            p.Art["CRAWL_B"] = new string[] {
                ".....kbbbllllbbbk.....",
                ".....kbbkkkkkkbbk.....",
                ".....kkk......kkk....." };
            p.Art["BALL"] = new string[] {
                ".kkk......kkk.",
                "kppbk....kbppk",
                "kpppbkkkkbpppk",
                ".kbbbbbbbbbbk.",
                "kbbllbbbbllbbk",
                "kbleeennneelbk",
                "kbleenhnneelbk",
                "kbbmqmmmqmbbbk",
                ".kbbbllllbbbk.",
                "..kkkkkkkkkk.." };
            p.Art["BALL_SLEEP"] = new string[] {
                ".kkk......kkk.",
                "kppbk....kbppk",
                "kpppbkkkkbpppk",
                ".kbbbbbbbbbbk.",
                "kbbllbbbbllbbk",
                "kbllllnnnlllbk",
                "kbleeenhneeebk",
                "kbbbmmmmmmbbbk",
                ".kbbbllllbbbk.",
                "..kkkkkkkkkk.." };
            p.Art["UKE"] = new string[] {
                ".....2",
                "....22",
                "...12.",
                ".111..",
                "11k1..",
                "1111..",
                ".11..." };
            p.FaceRow = 9; p.EyeRow = -1; p.TopRows = 8; p.NoGlasses = true;
            p.HatRow = -1; p.HatCol = 0; p.ScarfRow = 8; p.GlassRow = 1; p.BadgeRow = 10; p.BadgeCol = 5; p.SideRow = 10;
            p.Speed = 120;
            p.Say("talk", "Aloha!", "ih-ih-ih!", "Ohana 就是一家人，一家人不會丟下任何人", "嘻嘻嘻～", "meega nala kweesta!", "史迪仔，好孩子！");
            p.Say("talk_d", "Ohana 在家等你喔…", "呼啊～（打哈欠）", "回家，Ohana 在等", "ih…想睡…");
            p.Say("save", "ih! 存好了！", "存檔～嘻嘻嘻", "好孩子！存好了 👍");
            p.Say("save_d", "存好了…回家，Ohana 在等", "存了。呼啊～回家");
            p.Say("pats", "嘻嘻嘻～", "ih-ih-ih!", "好孩子！史迪仔是好孩子！", "Ohana ♥", "再摸！再摸！", "嘿嘿嘿（搖耳朵）", "你是 Ohana！");
            p.Say("pats_d", "呼啊…好舒服…", "摸完…回家", "Ohana 在家等你喔");
            p.Say("pats_hi", "你是史迪仔最重要的 Ohana ♥", "一家人不會丟下任何人！", "史迪仔最喜歡你！");
            p.Say("hugs", "Ohana～抱抱！", "抱抱！ih-ih!", "(つ´ω`)つ Ohana"); p.Say("hugs_d", "抱抱…然後回家", "Ohana 抱抱…晚安");
            p.Say("knock", "（舔舔玻璃）嘻嘻嘻", "ih! 你在裡面嗎？", "Aloha～放我出去！", "叩叩叩叩叩叩！");
            p.Say("knock_d", "（舔）…回家啦", "Ohana 在家等你喔", "呼啊～下班！");
            p.Say("newwin", "ih?! 新的！", "嘻嘻，那是什麼？", "（聞聞）ih-ih!"); p.Say("newwin_d", "又開？回家啦…", "不要了，睡覺！");
            p.Say("hi", "Aloha! 史迪仔 👋"); p.Say("hi_d", "Aloha…呼啊～");
            p.Say("wake", "ih?! 醒了醒了！"); p.Say("wake_d", "呼啊…Ohana？");
            p.Say("dizzy", "轉轉轉～ih-ih-ih @@"); p.Say("dizzy_d", "暈…睡覺…");
            p.Say("dizzy_ok", "好了！嘻嘻嘻"); p.Say("dizzy_ok_d", "…好了");
            p.Say("tickle", "ih-ih-ih! 好癢！", "嘻嘻嘻嘻嘻！"); p.Say("tickle_d", "嘻…好癢…");
            p.Say("pat10", "第 {n} 次！Ohana ♥"); p.Say("pat10_d", "第 {n} 次…回家啦");
            p.Say("levelup", "Lv{n}！史迪仔拿到「{u}」！嘻嘻嘻"); p.Say("levelup_d", "Lv{n}…「{u}」…明天戴");
            p.Say("missed", "你都不理史迪仔…Ohana 不會丟下任何人的 🥺"); p.Say("missed_d", "好久沒摸了…");
            p.Say("hover", "ih? 摸摸？");
            p.Say("seek", "ih! 那是什麼！"); p.Say("seek_lost", "跑了？！"); p.Say("seek_got", "抓到了！嘻嘻嘻");
            p.Say("drag", "ih-ih! 放開！"); p.Say("throw", "嗚哇哇哇～");
            p.Say("shelf_in", "史迪仔回窩囉，Aloha～"); p.Say("shelf_in_d", "呼啊～史迪仔回家睡覺");
            p.Say("shelf_out", "自由了！ih-ih-ih!"); p.Say("shelf_out_d", "ih…你還沒回家？");
            p.Say("ball_go", "球！史迪仔的！", "ih-ih! 等我！", "我抓我抓！"); p.Say("ball_go_d", "球…好吧，一下下");
            p.Say("ball_catch", "抓到！還你～", "嘻嘻嘻，好球", "史迪仔最快！"); p.Say("ball_catch_d", "抓到…還你");
            p.Say("ball_end", "不玩了？Aloha～"); p.Say("ball_end_d", "不玩了…睡覺");
            p.Say("ball_far", "跑太遠了！");
            p.Say("back", "Aloha～我回來了"); p.Say("back_d", "…回來了");
            p.Say("share_end", "分享完了？Aloha!");
            p.Say("welcome", "你回來了！Ohana！抱抱！"); p.Say("welcome_d", "回來了…要回家了嗎？");
            p.Say("rest", "{n} 分鐘了！起來喝可樂！咕嚕咕嚕 ih-ih! 🥤"); p.Say("rest_d", "{n} 分鐘了…喝完可樂就回家，Ohana 在等你");
            p.Say("night_on", "呼啊～天黑了…Ohana 在家等你喔"); p.Say("night_off", "Aloha! 早安！");
            p.Say("sleep", "呼…呼…"); p.Say("sleep_d", "晚安…Ohana…");
            p.Say("jump", "嘿咻！"); p.Say("nojump", "沒地方跳…");
            p.Say("errors", "ih-ih-ih! 有 {n} 個錯誤！史迪仔去咬它！"); p.Say("errors_d", "{n} 個錯誤…明天咬，回家");
            p.Say("errors_ok", "錯誤吃光光了！嘻嘻嘻"); p.Say("errors_ok_d", "吃光了…回家");
            p.Say("typing", "打好快！嘻嘻嘻♪", "ih-ih-ih! 快快快！"); p.Say("typing_d", "快打完…回家");
            p.Say("done", "{who} 做完了！Aloha～來看！"); p.Say("done_d", "{who} 做完了…回家，Ohana 在等");
            p.Say("wait", "{who} 在等你！ih!"); p.Say("wait_d", "{who} 在等…回完就回家");
            p.Say("ask", "{who} 有問題！快去！"); p.Say("ask_d", "{who} 在問…回完回家");
            p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了！要按允許嗎？"); p.Say("stuck_tool_d", "{who} 停 {n} 分鐘了…按一下回家");
            p.Say("stuck", "{who} 卡住了！{n} 分鐘！ih-ih!"); p.Say("stuck_d", "{who} 卡 {n} 分鐘…看一下回家");
            p.Say("unstuck", "{who} 動了！嘻嘻嘻"); p.Say("unstuck_d", "{who} 動了…");
            p.Say("tag", "上版了！Aloha～ 🎸"); p.Say("tag_dev", "測試機！嘻嘻嘻 🎸"); p.Say("tag_prod", "正式機！Thank you very much 🎸"); p.Say("tag_d", "上版了…回家睡覺");
            p.Say("late23", "好晚了…呼啊～ 🌙"); p.Say("late12", "吃飯！史迪仔要吃蛋糕！"); p.Say("late15", "點心！咖啡！");
            p.Say("late_d", "天黑了…Ohana 在等你"); p.Say("late_dd", "好晚…睡覺！");
            p.Say("g_late", "這麼晚？史迪仔陪你 🌙"); p.Say("g_morning", "Aloha! 早安！"); p.Say("g_noon", "Aloha～吃飯了嗎？");
            p.Say("g_evening", "Aloha～晚上好"); p.Say("g_day", "Aloha! 史迪仔來搗蛋啦！"); p.Say("g_d", "呼啊…天黑了，你怎麼還在？");
            p.Say("app_browser", "在看什麼？史迪仔也要！"); p.Say("app_code", "寫 code！史迪仔幫你咬 bug"); p.Say("app_excel", "好多格子…可以咬嗎？");
            p.Say("app_ppt", "簡報！放史迪仔照片！"); p.Say("app_word", "寫字字～"); p.Say("app_chat", "誰？Ohana 嗎？"); p.Say("app_files", "找東西？史迪仔聞聞！");
            p.Say("app_other", "ih? 這個是什麼？");
            p.Say("app_code_d", "還寫？回家！"); p.Say("app_chat_d", "明天再回…睡覺"); p.Say("app_office_d", "明天…呼啊～"); p.Say("app_other_d", "回家，Ohana 在等");
            p.Say("s_birthday", "生日快樂！史迪仔要吃蛋糕！🎂", "Ohana 生日快樂！");
            p.Say("s_cny", "新年快樂！紅包！ih-ih!", "恭喜發財 🧧");
            p.Say("s_xmas", "聖誕快樂！Aloha 🎄", "史迪仔想要新的烏克麗麗");
            p.Say("s_newyear", "新年快樂！Aloha ✨");
            p.Say("s_halloween", "不給糖就搗蛋！史迪仔本來就在搗蛋 🎃");
            p.Say("s_friday", "星期五！衝浪去！🏄", "快放假了！ih-ih-ih!");
            p.Say("morning", "Aloha! 早安！史迪仔來了！", "ih-ih! 早安 Ohana！");
            p.Say("goodnight", "呼啊～史迪仔回家睡覺了，Aloha", "晚安…Ohana 在家等你喔");
            p.Say("nag", "Ohana 在家等你喔", "回家！回家！", "呼啊～下班！");
            p.Say("react", "ih?!", "嘻嘻？", "什麼什麼？");
            p.Shared();
            return p;
        }

        // ---------------- 人魚漢頓（Hangyodon，三麗鷗的藍綠色魚男孩，同人像素）----------------
        static Pal Hangyodon()
        {
            Pal p = new Pal();
            p.Id = "hangyodon"; p.Name = "人魚漢頓"; p.Move = "swim"; p.BallKind = "tennis"; p.NightStyle = "lonely"; p.NightBubble = 4;
            p.Accent = C(0x1F9BA3); p.Panel = C(0xD6F2F0); p.Halo = Color.White; p.HaloNight = C(0xA6E3F0);
            // 參考三麗鷗原作：藍綠身體、黑線、上半部白色大眼、粉紅厚嘴唇帶、亮藍頭鰭和耳鰭、身上波浪鱗紋
            p.Col('k', 0x1B1F24, 0x101318); p.Col('b', 0x25B3BA, 0x1E8F9C); p.Col('d', 0x137F87, 0x10666F); p.Col('w', 0xFFFFFF, 0xE6F2F8);
            p.Col('K', 0x111111, 0x111111); p.Col('m', 0xF5A9C0, 0xD08AA4); p.Col('M', 0xD8708F, 0xA95A76); p.Col('f', 0x2D9BE3, 0x2678B8);
            p.Col('F', 0x1E74B5, 0x1A5C90); p.Col('c', 0xE23B3B, 0xB73838); p.Col('C', 0xA82828, 0x862A2A); p.Col('y', 0xFFD84A, 0xBFE8FF);
            p.Art["HEAD"] = new string[] {
                "...fff........",
                "..fFfFkkkk....",
                "..kfkbbbbbkk..",
                ".kbwwbbbbwwbk.",
                "fkwwwKbbKwwwkf",
                "fkwwwKbbKwwwkf",
                "fkbwwbbbbwwbkf",
                "kmmmmmmmmmmmmk" };
            p.Art["SLEEPY"] = new string[] {
                ".kbbbbbbbbbbk.",
                "fkbbbbbbbbbbkf",
                "fkbkkkbbkkkbkf",
                "fkbbbbbbbbbbkf" };
            p.Art["HAPPY"] = new string[] {
                ".kbbbbbbbbbbk.",
                "fkbbkbbbbkbbkf",
                "fkbkbkbbkbkbkf",
                "fkbbbbbbbbbbkf" };
            p.Art["DIZZY"] = new string[] {
                ".kbbbbbbbbbbk.",
                "fkbkbkbbkbkbkf",
                "fkbbkbbbbkbbkf",
                "fkbkbkbbkbkbkf" };
            p.Art["SILLY"] = new string[] {
                ".kbwwbbbbwwbk.",
                "fkKwwwbbwwwKkf",
                "fkwwwwbbwwwwkf",
                "fkbwwbbbbwwbkf" };
            p.Art["BODY"] = new string[] {
                "kmMMMMMMMMMMmk",
                ".kmmmmmmmmmmk.",
                "kbkbbbbbbbbkbk",
                ".kbdbbdbbdbbk.",
                ".kbbbbbbbbbbk." };
            p.Art["POUT"] = new string[] {
                ".kmmMMMMMMmmk.",
                "..kmmmmmmmmk..",
                "kbkbbbbbbbbkbk",
                ".kbdbbdbbdbbk.",
                ".kbbbbbbbbbbk." };
            p.Art["ARMS_UP"] = new string[] {
                "bmMMMMMMMMMMmb",
                "bkmmmmmmmmmmkb",
                ".kbbbbbbbbbbk.",
                ".kbdbbdbbdbbk.",
                ".kbbbbbbbbbbk." };
            p.Art["ARMS_HUG"] = new string[] {
                "..kmMMMMMMMMMMmk..",
                "...kmmmmmmmmmmk...",
                "bbkkbbbbbbbbbbkkbb",
                "...kbdbbdbbdbbk...",
                "...kbbbbbbbbbbk..." };
            p.Art["LEGS_A"] = new string[] {
                ".kbkbbbbbbkbk.",
                "..kbbk..kbbk..",
                "..kkkk..kkkk.." };
            p.Art["LEGS_B"] = new string[] {
                ".kbkbbbbbbkbk.",
                ".kbbk....kbbk.",
                ".kkkk....kkkk." };
            p.Art["LEGS_SIT"] = new string[] {
                ".kbkbbbbbbkbk.",
                "kbbbkk..kkbbbk",
                "kkkk......kkkk" };
            p.Art["CAPE"] = new string[] {
                "....cc",
                "...ccC",
                "..cccC",
                ".ccccC",
                "cccccC",
                "ccccC.",
                "cccCC.",
                ".cCC..",
                "..C..." };
            p.FaceRow = 3; p.EyeRow = -1;
            p.HatRow = 2; p.HatCol = 0; p.ScarfRow = 8; p.GlassRow = 3; p.BadgeRow = 11; p.BadgeCol = 5; p.SideRow = 9;
            p.Speed = 32;
            p.Say("talk", "今天也要『魚』快喔！", "我游泳從來不累，因為『魚』刃有餘～", "我們是『鰻』好的朋友吧？", "我在『潛』心思考人生…", "我以後一定會當上英雄的！", "要不要聽笑話？…好啦我自己先笑", "莎莉說我很有趣喔（是真的！）");
            p.Say("talk_d", "大家都回家了……你也回家吧，不要像我一樣一個人", "天黑了，魚也要睡覺了", "你回家的話我會想你…但還是回家吧", "今天辛苦了，明天見好不好？");
            p.Say("save", "存好了！英雄任務完成～", "存檔成功！好笑嗎？…啊這不是笑話", "存起來了，『魚』快！"); p.Say("save_d", "存好了…那就回家吧", "存了，晚上的海很冷，快回家");
            p.Say("pats", "為什麼魚不打網球？因為怕碰到網子！", "我游泳不累，『魚』刃有餘！", "這個 bug 真是『鯊』很大", "我們是『鰻』好的朋友～", "年年有『魚』，天天有你！", "我不是胖，是『魚』肉多一點", "你今天很『鮮』喔！");
            p.Say("pats_d", "大家都回家了……摸完你也回家吧", "謝謝你陪我…但你也要休息喔", "晚上的笑話比較冷…像海水一樣");
            p.Say("pats_hi", "有你在，我就不寂寞了", "你是我最重要的觀眾！", "跟你在一起，每天都很好笑（好的那種）");
            p.Say("hugs", "抱抱～有點濕濕的，不好意思", "被抱抱的感覺…真好", "嘿嘿，抱抱 ♥"); p.Say("hugs_d", "抱一下…然後回家喔", "你回家我會想你，但還是要回家");
            p.Say("knock", "叩叩～有人在嗎？我是漢頓！", "（嘴唇貼玻璃）啵～", "要聽笑話嗎？叩叩！", "玻璃外面的你，今天開心嗎？");
            p.Say("knock_d", "叩叩…你還沒回家嗎？", "大家都走了…你也回家吧", "不要像我一樣一個人待到這麼晚喔");
            p.Say("newwin", "哇，新的海域！", "咕嚕咕嚕～我游過去看看！", "新視窗！有新觀眾嗎？"); p.Say("newwin_d", "又開新的？明天再看吧…", "晚上的海很冷，關掉吧");
            p.Say("hi", "嗨～我是漢頓，今天也要『魚』快喔！👋"); p.Say("hi_d", "嗨…你還在呀");
            p.Say("wake", "咕嚕…啊，我醒了！"); p.Say("wake_d", "嗯…是你呀，你也還沒睡？");
            p.Say("dizzy", "頭好暈…像在漩渦裡 @@"); p.Say("dizzy_d", "暈暈的…該睡了");
            p.Say("dizzy_ok", "好了好了，我沒事！"); p.Say("dizzy_ok_d", "沒事…回家吧");
            p.Say("tickle", "（扮鬼臉）噗嚕嚕嚕～", "看我的鬼臉！好笑嗎？", "（嘴唇噗噗噗）"); p.Say("tickle_d", "（小小的鬼臉）…好啦，回家");
            p.Say("pat10", "今天第 {n} 次了！有人一直陪我，好開心 ♥"); p.Say("pat10_d", "第 {n} 次了…謝謝你，但要回家喔");
            p.Say("levelup", "好感度 Lv{n}！拿到「{u}」了，像英雄一樣！"); p.Say("levelup_d", "Lv{n}…「{u}」…明天戴給你看");
            p.Say("missed", "你好幾天沒來看我了…還以為你忘記我了 🥺"); p.Say("missed_d", "好久沒摸我了…沒關係，回家吧");
            p.Say("hover", "咦？你在摸我嗎？好癢～");
            p.Say("seek", "那是什麼？游過去看看！"); p.Say("seek_lost", "咦，游走了…"); p.Say("seek_got", "抓到了！我很厲害吧？");
            p.Say("drag", "哇～我在飛！像英雄一樣！"); p.Say("throw", "我會飛——啊不會——");
            p.Say("shelf_in", "我回櫃子裡休息囉，掰掰～"); p.Say("shelf_in_d", "大家都回家了…我也回櫃子裡");
            p.Say("shelf_out", "漢頓登場！今天要讓你笑！"); p.Say("shelf_out_d", "出來了…天黑了耶，你怎麼還在？");
            p.Say("ball_go", "球！我用頭頂！", "看我的海豹頂球！", "來吧！"); p.Say("ball_go_d", "最後一顆喔…");
            p.Say("ball_catch", "頂到了！好看嗎？", "嘿咻！海豹式！", "我很厲害吧？"); p.Say("ball_catch_d", "頂回去…然後回家");
            p.Say("ball_end", "不玩了？下次我練好再頂給你看"); p.Say("ball_end_d", "不玩了…那就回家吧");
            p.Say("ball_far", "球游太遠了～");
            p.Say("back", "我回來了～"); p.Say("back_d", "我回來了…");
            p.Say("share_end", "分享完了？漢頓回來了！");
            p.Say("welcome", "你回來了！我一個人好寂寞喔 ♥"); p.Say("welcome_d", "你回來了…是要回家了嗎？");
            p.Say("rest", "已經 {n} 分鐘了，起來喝口可樂、伸伸鰭…啊，伸伸手 🥤"); p.Say("rest_d", "{n} 分鐘了…喝完可樂就回家吧，不要一個人待太晚");
            p.Say("night_on", "天黑了…大家都回家了，你也回家吧"); p.Say("night_off", "早安！今天也要『魚』快喔 ☀");
            p.Say("sleep", "我去泡泡裡睡一下…"); p.Say("sleep_d", "晚安…不要像我一樣熬夜喔");
            p.Say("jump", "咕嚕咕嚕～游過去！"); p.Say("nojump", "附近沒有可以游的地方耶");
            p.Say("errors", "交給我這個英雄！有 {n} 個錯誤！"); p.Say("errors_d", "{n} 個錯誤…明天再修，回家吧");
            p.Say("errors_ok", "錯誤都不見了！我…我有幫到忙嗎？"); p.Say("errors_ok_d", "都修好了…回家吧");
            p.Say("typing", "打好快！我的鰭都跟不上了", "好厲害！比我游泳還快！"); p.Say("typing_d", "打快一點，早點回家");
            p.Say("done", "{who} 做完了！我終於當上英雄了！"); p.Say("done_d", "{who} 做完了…你也回家吧");
            p.Say("wait", "{who} 在等你回答喔～"); p.Say("wait_d", "{who} 在等你…回完就回家");
            p.Say("ask", "{who} 有問題要問你！"); p.Say("ask_d", "{who} 在問你…回完就回家");
            p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，要不要去按一下？"); p.Say("stuck_tool_d", "{who} 停了 {n} 分鐘…按一下就回家");
            p.Say("stuck", "{who} 好像卡住了…{n} 分鐘了，英雄去看看？"); p.Say("stuck_d", "{who} 卡住 {n} 分鐘…看一下就回家");
            p.Say("unstuck", "{who} 動起來了！太好了～"); p.Say("unstuck_d", "{who} 動了…");
            p.Say("tag", "上版成功！我終於當上英雄了！"); p.Say("tag_dev", "測試機成功！英雄練習中！"); p.Say("tag_prod", "正式機！這次真的是英雄了！"); p.Say("tag_d", "上版成功…大家都回家了，你也回家吧");
            p.Say("late23", "好晚了…你不要像我一樣熬夜喔 🌙"); p.Say("late12", "吃飯了嗎？我吃海草沙拉"); p.Say("late15", "點心時間～要不要聽個笑話配茶？");
            p.Say("late_d", "天都黑了…大家都回家了喔"); p.Say("late_dd", "好晚了…回家吧，不要一個人待著");
            p.Say("g_late", "這麼晚還在？我陪你，你就不是一個人了 🌙"); p.Say("g_morning", "早安！今天也要『魚』快喔 ☀"); p.Say("g_noon", "午安～吃飯了嗎？");
            p.Say("g_evening", "晚上好～今天辛苦了"); p.Say("g_day", "漢頓登場！今天要讓你笑！"); p.Say("g_d", "天黑了…你怎麼還在？");
            p.Say("app_browser", "在逛網頁？有好笑的給我看！"); p.Say("app_code", "寫 code 呀，我幫你加油！"); p.Say("app_excel", "好多格子，像魚網一樣…");
            p.Say("app_ppt", "做簡報？放一個我的笑話吧！"); p.Say("app_word", "在寫文件～慢慢來"); p.Say("app_chat", "有人找你？是莎莉嗎？"); p.Say("app_files", "在找東西？我幫你一起找");
            p.Say("app_other", "這是什麼？我游過去看看");
            p.Say("app_code_d", "還在寫…回家吧"); p.Say("app_chat_d", "明天再回吧"); p.Say("app_office_d", "明天再做也可以的"); p.Say("app_other_d", "大家都回家了…");
            p.Say("s_birthday", "生日快樂！我準備了一個笑話當禮物 🎂", "生日快樂！今天你是主角！");
            p.Say("s_cny", "新年快樂！年年有『魚』🧧");
            p.Say("s_xmas", "聖誕快樂！🎄", "聖誕老人會不會送我一件披風？");
            p.Say("s_newyear", "新年快樂！今年也要『魚』快 ✨");
            p.Say("s_halloween", "不給糖就…講冷笑話給你聽 🎃");
            p.Say("s_friday", "星期五了！週末要『魚』快喔！", "快放假了～要不要一起去海邊？");
            p.Say("morning", "早安！漢頓報到，今天也要『魚』快！", "早安～今天我想了新笑話！");
            p.Say("goodnight", "大家都回家了……我也回櫃子裡，晚安", "晚安…明天也要來看我喔");
            p.Say("nag", "大家都回家了……你也回家吧，不要像我一樣一個人", "回家吧，有人在等你吧？", "晚上的海好安靜…回家吧");
            p.Say("react", "咦？", "怎麼了？", "咕嚕？");
            p.Shared();
            return p;
        }

        // ================= 天線寶寶一櫃：丁丁、迪西、拉拉（同人像素）=================
        // 完全用小波核准過的母版（頭、臉、身體、腿、字元都一樣），只換顏色、換天線；丁丁多一列身體、一列腿（最高）。
        static string[] Taller(string[] rows, int dup, int extra)
        {
            List<string> l = new List<string>(rows);
            for (int i = 0; i < extra; i++) l.Insert(dup, rows[dup]);
            return l.ToArray();
        }

        static Pal TubbyBase(string id, string name, string[] ant, int extraBody, int extraLeg)
        {
            Pal po = Po();
            Pal p = new Pal();
            p.Id = id; p.Name = name; p.Tubby = true; p.BallKind = "tubby"; p.NightStyle = "sunset"; p.NightBubble = 2;
            p.Halo = Color.White; p.HaloNight = C(0xFFC58F);
            List<string> head = new List<string>(ant);
            string[] ph = po.Art["HEAD"];
            for (int i = 4; i < ph.Length; i++) head.Add(ph[i]);    // 小波的頭（去掉她的圓圈天線）
            p.Art["HEAD"] = head.ToArray();
            foreach (string f in new string[] { "SLEEPY", "HAPPY", "DIZZY", "SQUISH", "LEGS_SIT" }) p.Art[f] = po.Art[f];
            // 「哎喲！」：眼睛擠成一條線、嘴巴張開
            p.Art["OUCH"] = new string[] {
                "kehrffffffffrRek",
                "kehrkkffffkkrRek",
                "kehrffffffffrRek",
                "kehrpffmmffprRek",
                ".kkhrffmmffrRkk." };
            foreach (string b in new string[] { "BODY", "ARMS_UP", "ARMS_HUG" }) p.Art[b] = Taller(po.Art[b], 3, extraBody);
            foreach (string l in new string[] { "LEGS_A", "LEGS_B", "LEGS_RIDE" }) p.Art[l] = Taller(po.Art[l], 0, extraLeg);
            // 道具：迪西的乳牛紋高帽、丁丁的魔法袋、拉拉的大橘球、吐司、嘟嘟糊
            p.Art["HAT"] = new string[] {
                "....kkkkkkkk....",
                "....kWWWWKKk....",
                "....kKKWWWKk....",
                "....kKWWWWWk....",
                "....kWWWKKWk....",
                "..kkkkkkkkkkkk..",
                "..kWWWKKWWWWWk..",
                "...kkkkkkkkkk..." };
            p.Art["HAT_HAND"] = new string[] { ".kkkkkk.", ".kWKKWk.", ".kKWWWk.", ".kWWKKk.", "kkkkkkkk", "kWKWWKWk", ".kkkkkk." };
            p.Art["BAG"] = new string[] { "..kkkk..", ".k....k.", "kkkkkkkk", "kaWaaaAk", "kaaaaaAk", "kaaaaAAk", ".kAAAAk." };
            p.Art["BAG_OPEN"] = new string[] { "k......k", "kk....kk", "kAkkkkAk", "kaaaaaAk", "kaWaaaAk", "kaaaaAAk", ".kAAAAk." };
            p.Art["BALL"] = new string[] { "..kkkk..", ".kcYccck", "kcYccccC", "kccccccC", "kcccccCk", ".kcCCCk.", "..kkkk.." };
            p.Art["DUDU"] = new string[] { "..2.....", ".P2PPP..", "PPPPPPP.", "khhhhhk.", ".khhhk.." };
            p.Art["DUDU_CUP"] = new string[] { "PPPP", "kWWk", ".kk." };
            p.FaceRow = ant.Length + 3; p.EyeRow = -1; p.KeepAntenna = true; p.AntRows = 4;
            int total = head.Count + p.Art["BODY"].Length + p.Art["LEGS_A"].Length;
            p.TopRows = total - 16;
            p.HeadTop = 16 - total + ant.Length;
            p.BodyTop = 16 - p.Art["LEGS_A"].Length - p.Art["BODY"].Length;
            p.TummyRow = p.BodyTop + 2.5 + extraBody * 0.5;
            p.HatRow = p.HeadTop + 1; p.HatCol = 0; p.ScarfRow = p.HeadTop + 8; p.GlassRow = p.HeadTop + 4;
            p.BadgeRow = p.BodyTop + 4 + extraBody; p.BadgeCol = 5; p.SideRow = p.BodyTop + 1;
            // 共用色：膚色、嘴、肚子螢幕、滑板車（借騎時用）、帽子黑、袋子紅、球橘、吸吸藍
            p.Col('e', 0xF4CDBE, 0xD3A79C); p.Col('f', 0xF6D2B0, 0xD9AE92); p.Col('F', 0xE8B892, 0xBF907A); p.Col('m', 0xB8323C, 0x8E2E40); p.Col('p', 0xF29A9A, 0xC97A84);
            p.Col('g', 0xC9CDD3, 0x8F8CA6); p.Col('G', 0x8E949C, 0x5F5C78); p.Col('w', 0xFFFFFF, 0xFFE4CC); p.Col('y', 0xFFD84A, 0xFFB45E);
            p.Col('s', 0x55C7BE, 0x3F8F95); p.Col('q', 0x2F8F88, 0x266A70); p.Col('o', 0x6B6F7A, 0x4E4A5E);
            p.Col('K', 0x222222, 0x1A1A1A); p.Col('a', 0xD8323A, 0xAB313F); p.Col('A', 0x9E1F27, 0x761C2F); p.Col('c', 0xF2852A, 0xE07541); p.Col('C', 0xC25E14, 0xAE522D);
            p.Col('v', 0x7FD3E0, 0x649AA9); p.Col('V', 0x4A9FB8, 0x2F6D8A); p.Col('O', 0x4E4A5E, 0x2E304E);
            return p;
        }

        // 天線寶寶共用的台詞（每隻再蓋掉自己的）
        void TubbyLines(string me)
        {
            Say("rest", "已經 {n} 分鐘了，起來動一動、喝口可樂 🥤", "{n} 分鐘了！可樂時間～咕嚕咕嚕 🥤"); Say("rest_d", "{n} 分鐘了…喝完可樂，太陽寶寶下山了，回家吧");
            Say("night_on", "太陽寶寶下山了…" + me + "說再見囉"); Say("night_off", "太陽寶寶起床了！Eh-oh! ☀");
            Say("wait", "{who} 在等你回答喔 👋"); Say("wait_d", "{who} 在等你…回完就回家喔");
            Say("ask", "{who} 有問題要問你喔 🙋"); Say("ask_d", "{who} 在問你問題…回完就回家");
            Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，要你按按看嗎？"); Say("stuck_tool_d", "{who} 停了 {n} 分鐘…按一下就回家");
            Say("stuck", "{who} 不動了…{n} 分鐘了耶，去看看？"); Say("stuck_d", "{who} 卡住 {n} 分鐘了…看完就說再見囉");
            Say("unstuck", "{who} 又動了！好棒棒 👏"); Say("unstuck_d", "{who} 動了…");
            Say("late23", "好晚了…" + me + "想睡覺覺 🌙"); Say("late12", "吃飯飯了沒？吐司要不要？"); Say("late15", "點心時間～嘟嘟糊！");
            Say("late_d", "太陽寶寶早就下山了喔"); Say("late_dd", "好晚好晚了…晚安，回家吧");
            Say("app_browser", "在看什麼？" + me + "也要看～"); Say("app_code", "寫 code 時間！" + me + "陪你"); Say("app_excel", "好多格子喔～");
            Say("app_ppt", "做簡報～要畫太陽寶寶嗎？"); Say("app_word", "寫字字～慢慢來"); Say("app_chat", "有人找你玩嗎？"); Say("app_files", "在找東西嗎？");
            Say("app_other", "Eh-oh! 這是什麼？");
            Say("app_code_d", "還在寫…太陽寶寶下山了啦"); Say("app_chat_d", "天黑了，明天再回嘛"); Say("app_office_d", "明天再做好不好～"); Say("app_other_d", "該說再見囉～");
            Say("s_newyear", "新年快樂！Eh-oh! ✨");
            Say("react", "Eh-oh?", "咦？", "怎麼了怎麼了？");
            Say("pat10", "今天第 {n} 次摸摸了！" + me + "好開心 ♥"); Say("pat10_d", "第 {n} 次了…摸完就回家喔");
            Say("levelup", "好感度 Lv{n}！" + me + "拿到「{u}」了 ♥"); Say("levelup_d", "Lv{n}…拿到「{u}」…明天再戴給你看");
            Say("missed", "你好久沒摸摸" + me + "了…🥺"); Say("missed_d", "好久沒摸摸了…明天要記得喔");
            Say("hover", "Eh-oh? 你在摸摸" + me + "嗎～");
            Say("share_end", "分享完了～Eh-oh!");
            Say("back", "Eh-oh! " + me + "回來了"); Say("back_d", me + "回來了…");
            Say("welcome", "Eh-oh! 你回來了！大抱抱！"); Say("welcome_d", "你回來了…是要回家了嗎？");
            Say("hugs_d", "大抱抱…然後回家睡覺覺", "晚安大抱抱 ♥", "抱完就說再見囉");
        }

        // ---------------- 丁丁（紫色、最高、倒三角天線、紅色魔法袋）----------------
        static Pal Tinky()
        {
            Pal p = TubbyBase("tinky", "丁丁", new string[] {
                "....rrrrrrrr....",
                ".....r....r.....",
                "......r..r......",
                ".......rr.......",
                ".......rr......." }, 1, 1);
            p.Move = "bag"; p.Accent = C(0x7A52B0); p.Panel = C(0xE6DCF5);
            p.Col('k', 0x2E1A3A, 0x1E1028); p.Col('r', 0x8A5CC2, 0x6A4A9E); p.Col('R', 0x5E3A92, 0x45296E); p.Col('h', 0xA884DA, 0x8A6CB8);
            p.Speed = 30; p.AntThrough = true;
            p.TubbyLines("丁丁");
            p.Say("talk", "Eh-oh!", "丁丁的魔法袋裡有什麼呢？", "大抱抱時間到了沒？", "丁丁想跳舞～", "今天天氣好好喔 ☀", "要喝可樂嗎？丁丁袋子裡有 🥤", "慢慢走，慢慢走～");
            p.Say("talk_d", "太陽寶寶下山了，丁丁說再見囉", "丁丁抱著袋袋想睡覺…你也回家好不好", "天黑黑了，明天再玩", "晚安晚安～該回家囉");
            p.Say("save", "存好了！放進魔法袋 👜", "存起來了～好棒棒！", "Eh-oh! 存檔成功", "丁丁幫你收好囉");
            p.Save_d();
            p.Say("pats", "嘻嘻，好舒服", "丁丁喜歡你 ♥", "摸摸頭～你也辛苦了", "Eh-oh! 再摸一下", "有丁丁陪你喔", "慢慢來，丁丁等你", "大大的丁丁給你靠 ♥");
            p.Say("pats_d", "嗯…丁丁想睡覺覺了", "摸摸…然後我們回家好不好", "太陽寶寶下山了，你也該休息囉");
            p.Say("pats_hi", "丁丁最最最喜歡你了", "我們是好朋友！", "能遇到你真好 ♥", "每天都要一起跳舞喔");
            p.Say("hugs", "大抱抱！", "丁丁的大大抱抱 ♥", "Eh-oh! 大抱抱！", "(つ´ω`)つ 大抱抱");
            p.Say("knock", "叩叩！Eh-oh! 👀", "丁丁可以出去玩嗎？", "肚肚貼玻璃～嘿嘿", "魔法袋敲敲～叩叩");
            p.Say("knock_d", "叩叩…太陽寶寶下山了喔", "該說再見囉，回家吧～", "丁丁看到你還在加班…");
            p.Say("newwin", "Eh-oh!", "Eh-oh! 新視窗！", "丁丁慢慢走過去看～");
            p.Say("newwin_d", "Eh-oh…又開新的了？明天再看嘛", "天黑黑了，不要再開了啦");
            p.Say("hi", "Eh-oh! 我是丁丁 👋"); p.Say("hi_d", "Eh-oh…太陽寶寶下山了耶");
            p.Say("wake", "嗯…Eh-oh? 是你呀 ♥"); p.Say("wake_d", "嗯…丁丁在睡覺覺…你也去睡嘛");
            p.Say("dizzy", "轉圈圈～頭暈暈 @@"); p.Say("dizzy_d", "暈暈…丁丁要睡覺覺了…");
            p.Say("dizzy_ok", "好了！再來一次！"); p.Say("dizzy_ok_d", "好了…該回家囉");
            p.Say("tickle", "哎喲！", "哎喲！（又跌倒了）", "哎喲～嘻嘻嘻"); p.Say("tickle_d", "哎喲…最後一次喔");
            p.Say("seek", "咦？那是什麼？"); p.Say("seek_lost", "跑掉了…"); p.Say("seek_got", "抓到滑鼠了！放進魔法袋～");
            p.Say("drag", "哇～丁丁好重喔！"); p.Say("throw", "哎——喲——");
            p.Say("shelf_in", "丁丁回家家囉，掰掰 👋"); p.Say("shelf_in_d", "太陽寶寶下山了，丁丁說再見");
            p.Say("shelf_out", "Eh-oh! 丁丁出來玩囉！"); p.Say("shelf_out_d", "Eh-oh…天黑黑了耶，你怎麼還在？");
            p.Say("ball_go", "球！丁丁來了！", "魔法袋準備好了！", "慢慢來～我接我接"); p.Say("ball_go_d", "最後一球喔…");
            p.Say("ball_catch", "收進魔法袋！", "接到了！在袋子裡～", "嘿嘿，袋子好厲害"); p.Say("ball_catch_d", "收好了…還你，該回家囉");
            p.Say("ball_end", "不玩了嗎？下次再來一次！"); p.Say("ball_end_d", "不玩了…那我們回家吧");
            p.Say("ball_far", "球球跑好遠喔～丁丁走不快");
            p.Say("sleep", "抱著袋袋睡覺覺…晚安"); p.Say("sleep_d", "晚安晚安…你也去睡覺覺");
            p.Say("jump", "嘿咻～"); p.Say("nojump", "附近沒有可以跳的地方耶");
            p.Say("errors", "哎喲！有 {n} 個錯誤"); p.Say("errors_d", "{n} 個錯誤…明天再修啦，回家");
            p.Say("errors_ok", "錯誤都不見了！大抱抱！"); p.Say("errors_ok_d", "都修好了！那我們回家吧");
            p.Say("typing", "打好快喔！丁丁跳舞給你看～", "加油加油！", "手指在跳舞耶 ♪"); p.Say("typing_d", "打好快…是想快點回家吧");
            p.Say("done", "Eh-oh! {who} 做完了！丁丁跳舞！"); p.Say("done_d", "{who} 做完了～太陽寶寶下山了，回家吧");
            p.Say("tag", "上版成功！魔法袋變出星星了 ✨"); p.Say("tag_dev", "測試機成功！丁丁跳舞～"); p.Say("tag_prod", "正式機成功！大抱抱 🎉"); p.Say("tag_d", "上完了…丁丁說再見，回家吧");
            p.Say("g_late", "這麼晚了…丁丁陪你一下下 🌙"); p.Say("g_morning", "Eh-oh! 早安！丁丁來了 ☀"); p.Say("g_noon", "Eh-oh! 午安～吃吐司了沒？");
            p.Say("g_evening", "Eh-oh～晚上了，辛苦了"); p.Say("g_day", "Eh-oh! 丁丁來玩囉！"); p.Say("g_d", "太陽寶寶下山了…你怎麼還在？");
            p.Say("s_birthday", "生日快樂！丁丁從魔法袋變出蛋糕 🎂", "今天你最大！大抱抱！");
            p.Say("s_cny", "新年快樂！恭喜恭喜 🧧", "紅包…放進魔法袋！");
            p.Say("s_xmas", "聖誕快樂！🎄", "丁丁的魔法袋要裝禮物～");
            p.Say("s_halloween", "不給糖就搗蛋！🎃", "丁丁扮成…大茄子！");
            p.Say("s_friday", "星期五了！丁丁跳舞！", "快放假了～大抱抱！");
            p.Say("morning", "丁丁！", "丁丁！Eh-oh!");
            p.Say("goodnight", "丁丁說再見！👋", "晚安晚安～大抱抱");
            p.Say("nag", "太陽寶寶下山了，該說再見囉", "回家家囉～", "丁丁想睡覺覺了…");
            p.Shared();
            return p;
        }

        // ---------------- 迪西（綠色、直直的天線、黑白乳牛紋高帽、有點酷）----------------
        static Pal Dipsy()
        {
            Pal p = TubbyBase("dipsy", "迪西", new string[] {
                ".......rr.......",
                ".......rr.......",
                ".......rr.......",
                ".......rr.......",
                ".......rr......." }, 0, 0);
            p.Move = "groove"; p.Accent = C(0x4F8A27); p.Panel = C(0xE0F2D2);
            p.Col('k', 0x22301A, 0x141E10); p.Col('r', 0x7DC242, 0x66984A); p.Col('R', 0x4F8A27, 0x3E6A2E); p.Col('h', 0xA2D86C, 0x88B266);
            p.Col('f', 0xD9A77C, 0xBC8A68); p.Col('F', 0xC08D63, 0xA27254); p.Col('e', 0xE2B08E, 0xC29076); p.Col('p', 0xE28A78, 0xB8707A);   // 迪西的臉比較深
            p.Speed = 60;
            p.TopRows = 6 - p.HeadTop;   // 算到帽子頂（頭頂外框上面 6 列）
            p.TubbyLines("迪西");
            p.Say("talk", "Eh-oh.", "這頂帽子是我的。", "嘿～（扶帽子）", "酷。", "跳舞嗎？我很會。", "要喝可樂嗎？冰的比較酷 🥤", "帽子不能借喔。");
            p.Say("talk_d", "太陽寶寶下山了…帽子拉低，睡覺", "迪西說再見囉…你也回家吧", "天黑了，酷的人都回家了", "晚安。帽子我戴著睡。");
            p.Say("save", "存好了。酷。", "存檔成功，嘿～", "Eh-oh. 存好了", "存了，帥。");
            p.Save_d();
            p.Say("pats", "嘿嘿…別碰帽子就好", "酷。再一下。", "迪西也喜歡你啦", "摸摸頭…欸，是摸帽子", "嘿～你很酷", "有迪西在，不用怕");
            p.Say("pats_d", "嗯…迪西想睡了", "摸完就回家吧", "太陽寶寶下山了，你也該休息");
            p.Say("pats_hi", "你是最酷的", "迪西最喜歡你了（小聲）", "我們是好朋友。", "帽子…可以給你摸一下");
            p.Say("hugs", "大抱抱。", "大抱抱！（帽子扶好）", "Eh-oh! 大抱抱", "(つ´ω`)つ 酷酷的抱抱");
            p.Say("knock", "叩叩。Eh-oh. 👀", "嘿～螢幕外面的你", "迪西可以出去跳舞嗎？", "（帽子敲玻璃）叩叩");
            p.Say("knock_d", "叩叩…太陽寶寶下山了", "該說再見了，回家吧", "還在加班？不酷。");
            p.Say("newwin", "Eh-oh.", "嘿～新視窗", "迪西去看看，酷。");
            p.Say("newwin_d", "又開新的？明天再看", "天黑了，關掉吧");
            p.Say("hi", "Eh-oh. 我是迪西 🎩"); p.Say("hi_d", "Eh-oh…太陽寶寶下山了");
            p.Say("wake", "嗯…（推帽子）是你啊"); p.Say("wake_d", "嗯…迪西在睡覺…你也去睡");
            p.Say("dizzy", "頭暈了…帽子還在吧？@@"); p.Say("dizzy_d", "暈…睡覺…");
            p.Say("dizzy_ok", "好了。帽子還在。酷。"); p.Say("dizzy_ok_d", "好了…該回家了");
            p.Say("tickle", "嘿～嘿～（跳起來）", "帽子不能摸啦！", "嘻…好啦好啦"); p.Say("tickle_d", "嘿…最後一次");
            p.Say("seek", "嗯？那是什麼？"); p.Say("seek_lost", "跑了…不酷"); p.Say("seek_got", "抓到滑鼠了。大抱抱。");
            p.Say("drag", "欸欸，帽子要掉了！"); p.Say("throw", "嘿——（扶帽子）");
            p.Say("shelf_in", "迪西回去了，掰。 👋"); p.Say("shelf_in_d", "太陽寶寶下山了，迪西說再見");
            p.Say("shelf_out", "Eh-oh. 迪西出來了。"); p.Say("shelf_out_d", "Eh-oh…天黑了，你怎麼還在？");
            p.Say("ball_go", "球！用帽子頂！", "看我的！", "嘿～來了"); p.Say("ball_go_d", "最後一球。");
            p.Say("ball_catch", "帽子頂！", "頂回去～酷。", "帽子是最好的球拍"); p.Say("ball_catch_d", "頂回去…然後回家");
            p.Say("ball_end", "不玩了？下次再頂給你看"); p.Say("ball_end_d", "不玩了…回家吧");
            p.Say("ball_far", "球跑太遠了，帽子頂不到");
            p.Say("sleep", "帽子拉低…晚安"); p.Say("sleep_d", "晚安…你也去睡");
            p.Say("jump", "嘿！"); p.Say("nojump", "附近沒有可以跳的地方");
            p.Say("errors", "有 {n} 個錯誤…不看不看（拉帽子）"); p.Say("errors_d", "{n} 個錯誤…明天再修，回家");
            p.Say("errors_ok", "錯誤都清光了。酷。"); p.Say("errors_ok_d", "修好了…那就回家吧");
            p.Say("typing", "打好快！迪西跳舞～嘿～", "節奏不錯喔", "嘿～嘿～手指在跳舞"); p.Say("typing_d", "打快一點，早點回家");
            p.Say("done", "{who} 做完了。酷。"); p.Say("done_d", "{who} 做完了～回家吧");
            p.Say("tag", "上版成功！帽子丟起來 🎩"); p.Say("tag_dev", "測試機成功。嘿～"); p.Say("tag_prod", "正式機成功！酷斃了 🎉"); p.Say("tag_d", "上完了…迪西說再見，回家吧");
            p.Say("g_late", "這麼晚…迪西陪你一下 🌙"); p.Say("g_morning", "Eh-oh. 早安。帽子戴好了 ☀"); p.Say("g_noon", "Eh-oh. 午安，吃了沒？");
            p.Say("g_evening", "晚上了，辛苦了。"); p.Say("g_day", "Eh-oh. 迪西來了，酷。"); p.Say("g_d", "太陽寶寶下山了…你怎麼還在？");
            p.Say("s_birthday", "生日快樂！迪西跳舞給你看 🎂", "今天你最酷！");
            p.Say("s_cny", "新年快樂 🧧", "紅包…放帽子裡。");
            p.Say("s_xmas", "聖誕快樂 🎄", "聖誕帽？不用，我有帽子了。");
            p.Say("s_halloween", "不給糖就搗蛋 🎃", "我扮成…戴帽子的迪西。");
            p.Say("s_friday", "星期五了。跳舞吧。", "快放假了～嘿～");
            p.Say("morning", "迪西！", "迪西！Eh-oh.");
            p.Say("goodnight", "迪西說再見！👋", "晚安。帽子我戴著睡。");
            p.Say("nag", "太陽寶寶下山了，該說再見了", "回家吧。", "迪西想睡了…");
            p.Say("react", "嗯？", "Eh-oh?", "（扶帽子）怎麼了？");
            p.Shared();
            return p;
        }

        // ---------------- 拉拉（黃色、捲捲天線、大橘球、愛唱歌）----------------
        static Pal LaaLaa()
        {
            Pal p = TubbyBase("laalaa", "拉拉", new string[] {
                "......rrr.......",
                ".....r...r......",
                ".......r.r......",
                "........rr......",
                ".......rr......." }, 0, 0);
            p.Move = "skip"; p.Accent = C(0xD9A116); p.Panel = C(0xFFF4C8);
            p.Col('k', 0x3E2A10, 0x2A1A0C); p.Col('r', 0xF7D23A, 0xD9A84A); p.Col('R', 0xC9A116, 0xA27A2C); p.Col('h', 0xFFE67A, 0xE8C46E);
            p.Speed = 80;
            p.TubbyLines("拉拉");
            p.Say("talk", "啦啦啦～", "Eh-oh!", "拉拉的球圓圓的～", "我們來唱歌！", "今天天氣好好喔 ☀", "要喝可樂嗎？啦～ 🥤", "轉圈圈～轉圈圈～");
            p.Say("talk_d", "太陽寶寶下山了…啦…", "拉拉抱著球想睡覺…你也回家好不好", "天黑黑了，明天再唱", "晚安晚安～該回家囉");
            p.Save_d();
            p.Say("save", "存好了！啦啦啦～", "存起來了～好棒棒！", "Eh-oh! 存檔成功", "拉拉幫你收好囉 ♪");
            p.Say("pats", "嘻嘻，好舒服～", "拉拉喜歡你 ♥", "啦啦～再摸一下", "你好棒棒！", "有拉拉陪你喔 ♪", "摸摸頭～你也辛苦了");
            p.Say("pats_d", "嗯…拉拉想睡覺覺了", "摸摸…然後回家好不好", "太陽寶寶下山了，你也該休息囉");
            p.Say("pats_hi", "拉拉最最最喜歡你了 ♪", "我們是好朋友！", "能遇到你真好 ♥", "每天都要一起唱歌喔");
            p.Say("hugs", "大抱抱！", "啦啦～大抱抱 ♥", "Eh-oh! 大抱抱！", "(つ´ω`)つ 大抱抱");
            p.Say("knock", "叩叩！Eh-oh! 👀", "啦啦啦～有人在嗎？", "拉拉可以出去玩球嗎？", "肚肚貼玻璃～嘻嘻");
            p.Say("knock_d", "叩叩…太陽寶寶下山了喔", "該說再見囉，回家吧～", "拉拉看到你還在加班…");
            p.Say("newwin", "Eh-oh!", "啦啦～新視窗！", "拉拉跳過去看～");
            p.Say("newwin_d", "Eh-oh…又開新的了？明天再看嘛", "天黑黑了，不要再開了啦");
            p.Say("hi", "Eh-oh! 我是拉拉 👋"); p.Say("hi_d", "Eh-oh…太陽寶寶下山了耶");
            p.Say("wake", "嗯…啦？是你呀 ♥"); p.Say("wake_d", "嗯…拉拉在睡覺覺…你也去睡嘛");
            p.Say("dizzy", "轉太多圈了～頭暈暈 @@"); p.Say("dizzy_d", "暈暈…拉拉要睡覺覺了…");
            p.Say("dizzy_ok", "好了！再來一次！"); p.Say("dizzy_ok_d", "好了…該回家囉");
            p.Say("tickle", "啦啦啦～轉圈圈！", "再來一次！再來一次！", "嘻嘻嘻～好癢"); p.Say("tickle_d", "嘻…最後一次喔");
            p.Say("seek", "咦？那是什麼？"); p.Say("seek_lost", "跑掉了…"); p.Say("seek_got", "抓到滑鼠了！大抱抱！");
            p.Say("drag", "哇～飛高高！啦～"); p.Say("throw", "啦～～～");
            p.Say("shelf_in", "拉拉回家家囉，掰掰 👋"); p.Say("shelf_in_d", "太陽寶寶下山了，拉拉說再見");
            p.Say("shelf_out", "Eh-oh! 拉拉出來玩囉！"); p.Say("shelf_out_d", "Eh-oh…天黑黑了耶，你怎麼還在？");
            p.Say("ball_go", "球！拉拉來踢！", "啦～我來了！", "看我的腳！"); p.Say("ball_go_d", "最後一球喔…");
            p.Say("ball_catch", "踢回去！啦～", "好球！", "嘿嘿，拉拉很會踢吧"); p.Say("ball_catch_d", "踢回去…該回家囉");
            p.Say("ball_end", "不玩了嗎？下次再來一次！"); p.Say("ball_end_d", "不玩了…那我們回家吧");
            p.Say("ball_far", "球球跑好遠喔～");
            p.Say("sleep", "抱著球球睡覺覺…晚安"); p.Say("sleep_d", "晚安晚安…你也去睡覺覺");
            p.Say("jump", "啦～跳！"); p.Say("nojump", "附近沒有可以跳的地方耶");
            p.Say("errors", "哎呀…有 {n} 個錯誤，拉拉躲起來"); p.Say("errors_d", "{n} 個錯誤…明天再修啦，回家");
            p.Say("errors_ok", "錯誤都不見了！啦啦啦～"); p.Say("errors_ok_d", "都修好了！那我們回家吧");
            p.Say("typing", "打好快喔！啦啦啦～", "加油加油！拉拉唱歌給你聽 ♪", "手指在跳舞耶 ♪"); p.Say("typing_d", "打好快…是想快點回家吧");
            p.Say("done", "啦啦啦～{who} 做完了！"); p.Say("done_d", "{who} 做完了～太陽寶寶下山了，回家吧");
            p.Say("tag", "上版成功！啦啦啦～ 🎉"); p.Say("tag_dev", "測試機成功！轉圈圈～"); p.Say("tag_prod", "正式機成功！再來一次！🎉"); p.Say("tag_d", "上完了…拉拉說再見，回家吧");
            p.Say("g_late", "這麼晚了…拉拉輕輕唱歌陪你 🌙"); p.Say("g_morning", "Eh-oh! 早安！啦啦啦～ ☀"); p.Say("g_noon", "Eh-oh! 午安～吃飯飯了沒？");
            p.Say("g_evening", "Eh-oh～晚上了，辛苦了"); p.Say("g_day", "Eh-oh! 拉拉來玩球囉！"); p.Say("g_d", "太陽寶寶下山了…你怎麼還在？");
            p.Say("s_birthday", "生日快樂！拉拉唱歌給你聽 🎂 啦啦～", "今天你最大！大抱抱！");
            p.Say("s_cny", "新年快樂！恭喜恭喜 🧧", "紅包…拉拉可以拿嗎？");
            p.Say("s_xmas", "聖誕快樂！🎄 叮叮噹～啦啦啦～", "拉拉想要新球球");
            p.Say("s_halloween", "不給糖就搗蛋！🎃", "拉拉扮成…南瓜球！");
            p.Say("s_friday", "星期五了！唱歌跳舞！", "快放假了～啦啦啦！");
            p.Say("morning", "拉拉！", "拉拉！Eh-oh!");
            p.Say("goodnight", "拉拉說再見！👋", "晚安晚安～啦～");
            p.Say("nag", "太陽寶寶下山了，該說再見囉", "回家家囉～啦～", "拉拉想睡覺覺了…");
            p.Shared();
            return p;
        }

        void Save_d() { Say("save_d", "存好了…那我們回家好不好", "存好了，太陽寶寶也下山囉", "收好了～該說再見囉"); }
    }

    // ================= 一隻公仔（狀態＋行為）=================
    // 共用的物理／互動在這裡；各角色專屬的動作在後面的 partial（Spidey 噴絲、小波滑板車、史迪仔爬牆、人魚漢頓隱形船）。
    partial class Pet
    {
        public readonly Pal P;
        readonly World w;
        public readonly int S, SW, SH;
        readonly double k;
        readonly Random rnd;
        public PetForm Form;
        public ContextMenuStrip Menu;
        public BubbleForm Bub;

        public bool Out;              // 在桌面上（含出櫃、回櫃的動畫）
        public bool InScene;          // 正在演串場戲（由 World 控制）
        public double x, y, vx, vy, t, anim, sense, z;
        public int dir = 1;
        public string state = "air";
        public bool sleepMode;
        double sc = 1, gt, knock;     // 敲螢幕：放大倍率、計時、敲的晃動
        string afterGlass = "";

        // Spidey：絲的錨點／擺盪／倒吊／爬牆／噴絲
        double ax, ay, ropeL, th, om, targetL; int hangPhase;
        int wallSide, climbDir;
        double shootT; string nextAct = ""; IntPtr zipH; bool zipRight;
        double reelT, reelX, reelY;
        public IntPtr supH; int supL, supR, supWinL;
        bool goClimb;
        double seekX;

        string bubble = ""; public double Bt; bool bubbleAlert;
        bool dragging, dragSaid; Point dragStart; double grabDx, grabDy, dragMoved, lastMx, lastMy, lastMt, dvx, dvy;
        readonly List<double[]> hearts = new List<double[]>();
        readonly List<double[]> sparks = new List<double[]>();
        readonly List<double[]> notes = new List<double[]>();   // 音符、驚嘆號等小圖（x 偏移, 年齡, 種類）
        readonly List<double> clickTimes = new List<double>();
        readonly List<double[]> flakes = new List<double[]>();
        bool dizzyOnLand, rolling;
        double jokeT, tripT, capeT;     // 人魚漢頓：笑話後追問、跌倒、披風
        public bool fetching;
        double hoverCd, seekCd = 20, lateCd = 120, stuckRepeat;
        string stuckLine;

        // 公仔櫃動畫
        double flyT, flyDur, fx0, fy0, fx1, fy1, flyArc;
        int shelfPs;                    // 進櫃子時縮到的大小
        string afterLand = "";          // 落地後要做的事（wave／sniff／evil…）
        public double ShelfFx;          // 回櫃子後在格子裡的特效（Spidey 織網、小波轉圈…）0→1

        public Pet(World w, Pal p, int S, int seed)
        {
            this.w = w; P = p; this.S = S;
            k = S / 3.0;
            SW = 12 * S; SH = 16 * S;
            rnd = new Random(seed);
            LoadBond();
        }

        void EnsureForms()
        {
            if (Form != null) return;
            Form = new PetForm(this);
            Menu = new ContextMenuStrip();
            Menu.Opening += delegate(object s, System.ComponentModel.CancelEventArgs e) { w.FillMenu(this, Menu); };
            w.HookMenu(Menu);
            Bub = new BubbleForm(P.Accent);
        }

        public void HideForms()
        {
            if (Form != null && W.Shown(Form)) Form.Hide();
            if (Bub != null && W.Shown(Bub)) Bub.Hide();
        }

        public void CloseForms()
        {
            if (Form != null) { Form.Close(); Bub.Close(); }
        }

        bool Night { get { return w.Night; } }
        public bool Grounded() { return state == "walk" || state == "idle" || state == "sleep" || state == "hug" || state == "seek" || state == "dizzy" || state == "fetch" || state == "dance" || state == "kick" || state == "wave" || state == "pose" || state == "bat" || state == "catch" || state == "header" || state == "capetrip" || state == "elvis" || state == "chomp" || state == "think" || state == "hide" || state == "nudge" || state == "spin" || state == "goto"
            || state == "plop" || state == "twirl" || state == "hattoss" || state == "juggle" || state == "bagdig" || state == "pik" || state == "orig"; }
        public bool Free() { return Out && !InScene && !dragging && Grounded() && state != "sleep" && state != "hug" && !(Bt > 0 && bubblePri > 0); }
        void SetState(string s, double dur) { state = s; t = dur; }
        public void Say(string s, double sec) { Say(s, sec, false); }
        bool muteChat;
        public void Say(string s, double sec, bool alert) { if (string.IsNullOrEmpty(s) || muteChat) return; bubble = s; Bt = sec; bubbleAlert = alert; bubbleHint = null; bubblePri = 0; }
        int bubblePri;                  // 通知的泡泡（>0）不會被閒聊蓋掉
        string Pick(string[] a) { return a[rnd.Next(a.Length)]; }
        double R(double a, double b) { return a + rnd.NextDouble() * (b - a); }
        static double Clamp(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
        static double Ease(double v) { v = Clamp(v, 0, 1); return v * v * (3 - 2 * v); }
        public double Cx { get { return x + SW / 2.0; } }
        bool Is(string id) { return P.Id == id; }

        // 台詞：夜晚優先用 key_d；{n}{who}{tool}{u} 代換
        public string L(string key, params string[] kv)
        {
            string[] a = null;
            if (Night && P.Lines.TryGetValue(key + "_d", out a)) { }
            else if (!P.Lines.TryGetValue(key, out a)) { App.Log("missing line " + P.Id + "." + key); return ""; }
            string s = Pick(a);
            for (int i = 0; i + 1 < kv.Length; i += 2) s = s.Replace("{" + kv[i] + "}", kv[i + 1]);
            return s;
        }

        public void Jump(double jvx, double jvy) { vx = jvx; vy = jvy; supH = IntPtr.Zero; SetState("air", 0); }
        void Hop() { Jump(dir * 60 * k, -260 * k); }
        void GoSleep() { z = 0; SetState("sleep", 1e9); }
        public void WakeIfSleep() { sleepMode = false; if (state == "sleep") SetState("walk", 2); }
        public void AddHeart() { if (hearts.Count < 8) hearts.Add(new double[] { R(-12, 12) * k, 0 }); }
        public void Mark(int kind) { if (notes.Count < 12) notes.Add(new double[] { R(-10, 10) * k, 0, kind }); } // 0 音符 1 驚嘆號 2 問號 3 Zz 4 汗滴 5 泡泡

        public void Burst(int n)
        {
            double cx = Cx, cy = y + SH * 0.35;
            for (int i = 0; i < n; i++)
            {
                double a = rnd.NextDouble() * Math.PI * 2, sp = R(120, 260) * k;
                sparks.Add(new double[] { cx, cy, Math.Cos(a) * sp, Math.Sin(a) * sp - 120 * k, 0 });
            }
        }

        // ---------- 好感度（每個角色各自一份）----------
        static readonly int[] LV = { 0, 0, 15, 50, 120, 250, 500 };
        static readonly string[] UNLOCK = { "", "", "黃圍巾", "小毛帽", "愛心眼鏡", "金色胸章", "小皇冠" };
        int xp; string lastPatDay = "";
        int patsToday; string patsDate = "";
        double saveXpCd; int ballXp;
        string BondFile() { return Path.Combine(World.DataDir, "bond-" + P.Id + ".txt"); }
        string PatsFile() { return Path.Combine(World.DataDir, "pats-" + P.Id + ".txt"); }
        void LoadBond()
        {
            try { string[] a = File.ReadAllText(BondFile()).Trim().Split(' '); int.TryParse(a[0], out xp); if (a.Length > 1) lastPatDay = a[1]; } catch { }
            try
            {
                string[] a = File.ReadAllText(PatsFile()).Trim().Split(' ');
                if (a.Length == 2 && a[0] == DateTime.Now.ToString("yyyy-MM-dd")) { patsDate = a[0]; int.TryParse(a[1], out patsToday); }
            }
            catch { }
        }
        void SaveBond() { try { Directory.CreateDirectory(World.DataDir); File.WriteAllText(BondFile(), xp + " " + lastPatDay); } catch { } }
        void BumpPats()
        {
            string today = DateTime.Now.ToString("yyyy-MM-dd");
            if (today != patsDate) { patsDate = today; patsToday = 0; }
            patsToday++;
            try { Directory.CreateDirectory(World.DataDir); File.WriteAllText(PatsFile(), patsDate + " " + patsToday); } catch { }
        }
        public int Level() { int lv = 1; for (int i = 2; i < LV.Length; i++) if (xp >= LV[i]) lv = i; return lv; }
        public void AddXp(int n)
        {
            int before = Level();
            xp += n; SaveBond();
            int now = Level();
            if (now > before)
            {
                Hug(L("levelup", "n", now.ToString(), "u", UNLOCK[now]), 4);
                AddHeart(); AddHeart(); AddHeart(); Burst(14);
            }
        }
        public int DaysSincePat()
        {
            DateTime d;
            if (!DateTime.TryParse(lastPatDay, out d)) return 0;
            return (int)(DateTime.Now.Date - d.Date).TotalDays;
        }
        public void ShowBond()
        {
            int lv = Level();
            List<string> got = new List<string>();
            for (int i = 2; i <= lv; i++) got.Add(UNLOCK[i]);
            string next = lv < 6 ? "（" + xp + "/" + LV[lv + 1] + "）" : "（" + xp + "，滿級！）";
            Say(P.Name + " 好感度 Lv" + lv + next + (got.Count > 0 ? "　已解鎖：" + string.Join("、", got.ToArray()) : "　多摸摸我就會升級喔"), 4.5);
            AddHeart();
        }

        // 被點了一下（通知優先，沒有通知就是摸摸）
        public void Clicked()
        {
            if (w.NoticeClicked(this)) return;
            Pat();
        }

        // ---------- 點他（沒拖動）----------
        public void Pat()
        {
            double now = w.Now;
            clickTimes.Add(now);
            clickTimes.RemoveAll(delegate(double c) { return now - c > 1.3; });
            int combo = clickTimes.Count;
            BumpPats();
            w.Count("pats");
            lastPatDay = DateTime.Now.ToString("yyyy-MM-dd");
            if (patsToday <= 30) AddXp(1); else SaveBond();
            Burst(combo >= 3 ? 10 : 6);
            if (w.quietOn)
            {
                // 安靜中：小小回應就好
                AddHeart();
                Say(Pick(new string[] { "♥", "（小聲）嗯～", "噓…♥" }), 1.0);
                return;
            }
            if (state == "sleep")
            {
                WakeIfSleep();
                Hug(L("wake"), 2.4);
                return;
            }
            if (combo >= 5)
            {
                if (Grounded()) SetState("dizzy", 1.6); else dizzyOnLand = true;
                Say(L("dizzy"), 2);
                return;
            }
            if (combo >= 3) { PatCombo(); return; }
            if (patsToday % 10 == 0)
            {
                Hug(L("pat10", "n", patsToday.ToString()), 3);
                AddHeart(); AddHeart(); AddHeart();
                return;
            }
            string line = !Night && Level() >= 4 && rnd.NextDouble() < 0.4 ? L("pats_hi") : L("pats");
            if (Is("hangyodon") && !Night && Array.IndexOf(P.Lines["pats"], line) >= 0) jokeT = 2.6;
            if (Grounded()) Hug(line, 2.6);
            else { Say(line, 2.2); AddHeart(); }
        }

        // 連點三下：每個角色不一樣
        void PatCombo()
        {
            AddHeart();
            if (P.Pik) { PikCombo(); return; }
            if (P.Orig) { OrigCombo(); return; }
            switch (P.Id)
            {
                case "po":   // 咯咯笑＋原地轉一圈「再來一次！」
                    Say(L("tickle"), 1.8);
                    if (Grounded() && state != "dizzy") { SetState("spin", 0.9); Jump(0, -340 * k); rolling = true; }
                    break;
                case "stitch": // 笑到捲成球滾來滾去
                    Say(L("tickle"), 1.8);
                    if (Grounded() && state != "dizzy") { rolling = true; Jump(dir * R(120, 220) * k, -240 * k); }
                    break;
                case "hangyodon": // 扮鬼臉（鬥雞眼＋嘟嘴）
                    if (Grounded() && state != "dizzy") { poseKind = "silly"; SetState("pose", 1.8); }
                    Say(L("tickle"), 1.8);
                    break;
                case "tinky":  // 跌坐在地上「哎喲！」
                    Say(L("tickle"), 1.8);
                    if (Grounded() && state != "dizzy") Plop(null);
                    break;
                case "dipsy":  // 帽子不准摸：把帽子丟起來接住，或酷酷地跳一段
                    Say(L("tickle"), 1.8);
                    if (Grounded() && state != "dizzy") { if (rnd.NextDouble() < 0.5) HatToss(true); else SetState("dance", 1.8); }
                    break;
                case "laalaa": // 啦啦啦～轉圈圈
                    Say(L("tickle"), 1.8);
                    if (Grounded() && state != "dizzy") SetState("twirl", 1.3);
                    break;
                default:
                    Say(L("tickle"), 1.6);
                    if (Grounded() && state != "dizzy") Jump(dir * 40 * k, -330 * k);
                    break;
            }
        }

        public void Hug(string text, double sec)
        {
            if (Grounded()) SetState("hug", sec);
            Say(text, sec);
            AddHeart(); AddHeart();
        }

        // ---------- 滑鼠：停在身上 → 抱抱；停在附近 → 跑過去 ----------
        void Watch(double dt)
        {
            if (stuckLine != null) { stuckRepeat -= dt; if (stuckRepeat <= 0) { Say(stuckLine, 6, true); stuckLine = null; } }
            seekCd -= dt; hoverCd -= dt; lateCd -= dt; saveXpCd -= dt;
            if (!Grounded() || state == "hug" || sleepMode || state == "sleep" || InScene || Quiet) return;
            Point c = Cursor.Position;
            double cx = Cx, still = w.CursorStill;
            bool onMe = c.X >= x && c.X <= x + SW && c.Y >= y && c.Y <= y + SH;
            if (onMe && still > 1.2 && hoverCd <= 0) { hoverCd = 12; Hug(L("hover"), 2.4); return; }
            if (!fetching && state != "seek" && seekCd <= 0 && still > 2.5 && !onMe
                && c.Y > y - 40 * k && c.Y < y + SH + 8 && Math.Abs(c.X - cx) < 380 * k && Math.Abs(c.X - cx) > 8)
            {
                seekX = c.X; seekCd = R(45, 100);
                if (Is("stitch") && rnd.NextDouble() < 0.4) { SetState("seek", 8); afterLand = "nudge"; Say("嘻嘻嘻…", 1.2); }
                else { SetState("seek", 8); Say(L("seek"), 1.2); }
            }
        }

        // ================= 每一格 =================
        public void Tick(double dt)
        {
            if (!Out) return;
            if (!(dragging && DragUpdate(w.Now, dt))) { Watch(dt); Step(dt); }
            Render();
        }

        void Step(double dt)
        {
            anim += dt; t -= dt;
            if (Bt > 0) Bt -= dt;
            if (sense > 0) sense -= dt;
            if (jokeT > 0) { jokeT -= dt; if (jokeT <= 0) { Say("好笑嗎？好笑嗎？", 1.8); if (Grounded()) Jump(0, -180 * k); } }
            if (tripT > 0) tripT -= dt;
            for (int i = hearts.Count - 1; i >= 0; i--) { hearts[i][1] += dt; if (hearts[i][1] > 1.6) hearts.RemoveAt(i); }
            for (int i = notes.Count - 1; i >= 0; i--) { notes[i][1] += dt; if (notes[i][1] > 1.8) notes.RemoveAt(i); }
            for (int i = sparks.Count - 1; i >= 0; i--)
            {
                double[] sp = sparks[i];
                sp[3] += 420 * k * dt; sp[0] += sp[2] * dt; sp[1] += sp[3] * dt; sp[4] += dt;
                if (sp[4] > 0.75) sparks.RemoveAt(i);
            }
            if (w.SeasonNow == "xmas" && rnd.NextDouble() < dt * 3)
                flakes.Add(new double[] { Cx + R(-70, 70) * k, y - R(30, 90) * k, R(-12, 12) * k, 0 });
            for (int i = flakes.Count - 1; i >= 0; i--)
            {
                double[] f = flakes[i];
                f[1] += 38 * k * dt; f[0] += (f[2] + Math.Sin(f[3] * 3) * 10 * k) * dt; f[3] += dt;
                if (f[3] > 2.2) flakes.RemoveAt(i);
            }
            FollowFast();
            Rectangle wa = w.WA(Cx, y + SH / 2.0);
            if (StepSpecial(dt, wa)) return;   // 角色專屬狀態
            switch (state)
            {
                case "walk":
                    if (sleepMode) { GoSleep(); break; }
                    if (MoveOnGround(dt, P.Speed * k)) break;
                    if (t < 0) { muteChat = !w.Feat("chatter"); Decide(wa); muteChat = false; }   // 小屋關掉「閒聊泡泡」：自己閒晃時不講話
                    break;
                case "seek": Seek(dt); break;
                case "idle":
                    if (!InScene) { Point cp = Cursor.Position; if (Math.Abs(cp.X - Cx) > 20) dir = cp.X > Cx ? 1 : -1; }
                    if (sleepMode) GoSleep();
                    else if (t < 0 && !InScene) SetState("walk", R(3, 6));
                    break;
                case "fetch": Fetch(dt); break;
                case "dance": case "kick": case "pose": case "wave": case "think":
                    if (t < 0 && !InScene) { SetState("idle", R(1, 2)); DoAfter(); }
                    break;
                case "dizzy":
                    if (Math.Floor(anim * 8) != Math.Floor((anim - dt) * 8)) dir = -dir;
                    if (t < 0) { SetState("idle", 1); Say(L("dizzy_ok"), 1.4); }
                    break;
                case "hug":
                    if (rnd.NextDouble() < dt * 2.5) AddHeart();
                    if (t < 0 && !InScene) SetState("walk", R(2, 4));
                    break;
                case "sleep": z += dt; if (t < 0) SetState("walk", 3); break;
                case "air": Air(dt); break;
                case "glass": Glass(dt); break;
                case "stowfly": StowFly(dt); break;
                case "enter": Enter(dt); break;
                case "exit": Exit(dt); break;
                case "hide": HideBehind(dt); break;
                case "goto": GoTo(dt); break;
                case "fling": Fling(dt); break;
            }
        }

        void DoAfter()
        {
            string a = afterLand; afterLand = "";
            if (a == "trip") { tripT = 1.1; SetState("think", 1.1); Say(Pick(new string[] { "哎呀…（跌倒）", "嗚…英雄也會跌倒的", "我、我沒事！" }), 1.8); }
        }

        // 回傳 true＝離開地面或換狀態了
        bool MoveOnGround(double dt, double speed)
        {
            double nx = x + dir * speed * dt, ncx = nx + SW / 2.0, midY = y + SH / 2.0;
            if (supH != IntPtr.Zero)
            {
                if (ncx < supL || ncx > supR)
                {
                    if (state == "walk") { int e = EdgeOfWindow(ncx > supR); if (e == 2) return true; if (e == 1) return false; }
                    x = nx;
                    Jump(dir * speed * 1.4, -140 * k);
                    return true;
                }
                x = nx;
                return false;
            }
            double lead = dir > 0 ? nx + SW - 1 : nx;
            if (!w.Inside(lead, midY))
            {
                if (state == "walk" && EdgeOfScreen()) return true;
                dir = -dir;
                return false;
            }
            double floorY = w.WA(ncx, midY).Bottom - SH;
            if (floorY > y + 2) { x = nx; Jump(dir * speed, 0); return true; }
            if (floorY < y - 2) { dir = -dir; return false; }
            x = nx; y = floorY;
            return false;
        }

        void Seek(double dt)
        {
            Point c = Cursor.Position;
            if (Math.Abs(c.X - seekX) > 4)
            {
                if (c.Y > y - 60 * k && c.Y < y + SH + 20) seekX = c.X;
                else { SetState("walk", 2); afterLand = ""; Say(L("seek_lost"), 1.4); return; }
            }
            if (Math.Abs(seekX - Cx) < 6)
            {
                if (afterLand == "nudge") { afterLand = ""; SetState("nudge", 1.6); Say(Pick(new string[] { "ih-ih-ih!（推推）", "嘻嘻，推一下～", "這個是史迪仔的！" }), 1.8); return; }
                Hug(L("seek_got"), 3); return;
            }
            dir = seekX > Cx ? 1 : -1;
            if (MoveOnGround(dt, (Is("hangyodon") || Is("tinky") ? 60 : 95) * k)) return;
            double ncx = Cx;
            if ((dir > 0 && ncx > seekX) || (dir < 0 && ncx < seekX)) x = seekX - SW / 2.0;
            if (t < 0) SetState("walk", 2);
        }

        // 拋物線跳到某一點（腳落在 footY）
        public void BallisticTo(double tx, double footY)
        {
            double cx = Cx, foot = y + SH, g = 900 * k;
            Rectangle top = w.WA(cx, y);
            double apex = Math.Max(Math.Min(foot, footY) - R(60, 130) * k, top.Top + SH + 2);
            if (apex >= foot) apex = foot - 10;
            if (apex >= footY) apex = footY - 10;
            double vy0 = -Math.Sqrt(2 * g * (foot - apex));
            double tt = -vy0 / g + Math.Sqrt(2 * (footY - apex) / g);
            double vx0 = (tx - cx) / tt;
            dir = vx0 >= 0 ? 1 : -1;
            Jump(vx0, vy0);
        }

        // 挑一個附近的平台（視窗頂端或螢幕底）：回傳 {x, 頂端y, 是哪個視窗}
        double[] PickPlatform(double minDx, double maxDx)
        {
            double cx = Cx, foot = y + SH;
            List<double[]> opts = new List<double[]>();
            if (w.Feat("windows"))                    // 小屋關掉「跳上視窗」：只在螢幕底走
            foreach (Plat p in w.Plats)
            {
                if (p.H == supH && Math.Abs(p.Top - foot) < 2) continue;
                double tx = p.Left + SW / 2.0 + rnd.NextDouble() * Math.Max(0, p.Right - p.Left - SW);
                double dx = tx - cx, dy = p.Top - foot;
                if (Math.Abs(dx) < minDx || Math.Abs(dx) > maxDx || dy < -600 * k) continue;
                opts.Add(new double[] { tx, p.Top });
            }
            if (supH != IntPtr.Zero)
            {
                Rectangle wa = w.WA(cx, y);
                opts.Add(new double[] { Clamp(cx + R(-400, 400) * k, wa.Left + SW, wa.Right - SW), wa.Bottom });
            }
            if (opts.Count == 0) return null;
            return opts[rnd.Next(opts.Count)];
        }

        bool JumpToPlatform()
        {
            if (!Grounded()) return false;
            double[] o = PickPlatform(40 * k, 900 * k);
            if (o == null) return false;
            BallisticTo(o[0], o[1]);
            if (Is("po")) { Say(L("jump"), 0.9); }
            else if (rnd.NextDouble() < 0.3) Say(L("jump"), 0.8);
            return true;
        }

        void Air(double dt)
        {
            double g = 900 * k, prevFoot = y + SH;
            vy += g * dt; x += vx * dt; y += vy * dt;
            double cx = Cx, midY = y + SH / 2.0;
            Rectangle wa = w.WA(cx, midY);
            if (!w.Inside(x, midY) && x < wa.Left) { x = wa.Left; vx = -vx * .5; }
            if (!w.Inside(x + SW - 1, midY) && x + SW > wa.Right) { x = wa.Right - SW; vx = -vx * .5; }
            cx = Cx;
            if (y < wa.Top) { y = wa.Top; if (vy < 0) vy = 0; }
            if (Math.Abs(vx) > 1) dir = vx > 0 ? 1 : -1;
            if (vy > 1100 * k && (Is("po") || Is("stitch") || Is("laalaa"))) rolling = true; // 摔很快 → 滾
            if (vy <= 0) return;
            double best = wa.Bottom; Plat bp = null;
            foreach (Plat p in w.Plats)
                if (cx >= p.Left && cx <= p.Right && prevFoot <= p.Top + 1 && y + SH >= p.Top && p.Top < best) { best = p.Top; bp = p; }
            if (y + SH >= best)
            {
                y = best - SH;
                double landVx = vx;
                lastLandVy = vy;
                vx = 0; vy = 0;
                if (bp != null) SetSupport(bp); else supH = IntPtr.Zero;
                bool wasRolling = rolling; rolling = false;
                if (nearMiss) { nearMiss = false; Say(MissLine(), 1.8); }
                if (Landed(wasRolling, landVx)) return;
                if (sleepMode) GoSleep();
                else if (dizzyOnLand) { dizzyOnLand = false; SetState("dizzy", 1.6); }
                else if (fetching && w.BallOn) SetState("fetch", 15);
                else if (afterLand != "") LandAction();
                else if (InScene && (w.TubbyLineup || w.PikLineup || w.OrigLineup)) SetState("idle", 30);   // 天線寶寶串場：跳一下落地就站好，不要走掉
                else SetState("walk", R(2, 5));
            }
        }

        public void SetSupport(Plat p) { supH = p.H; supL = p.Left; supR = p.Right; supWinL = p.WinLeft; }

        // 站著的那個視窗被拖動 → 跟著走
        void FollowFast()
        {
            if (supH == IntPtr.Zero || !Grounded()) return;
            W.RECT r;
            if (!W.IsWindowVisible(supH) || W.IsIconic(supH) || !W.Rect(supH, out r)) { Jump(0, 0); Say(Is("hangyodon") ? "哇！地板游走了！" : "哇！地板不見了", 1.2); return; }
            int dl = r.L - supWinL;
            if (dl != 0) { x += dl; supL += dl; supR += dl; supWinL = r.L; }
            y = r.T - SH;
        }

        // World 掃描完視窗後：站的那段被蓋住 → 掉下來
        public void CheckSupport()
        {
            if (supH == IntPtr.Zero || !Grounded()) return;
            Plat best = null;
            foreach (Plat p in w.Plats) if (p.H == supH && Cx >= p.Left - 2 && Cx <= p.Right + 2) { best = p; break; }
            if (best == null) Jump(0, 0); else { supL = best.Left; supR = best.Right; }
        }

        // ---------- 第四面牆 ----------
        // 放大敲玻璃很搶眼，所以有全域冷卻（World.ZoomAllowed）；不能放大時改成原尺寸的小動作
        public void Knock(string text, string kind)
        {
            if (Out && Grounded() && state != "glass" && w.ZoomAllowed(kind)) { StartGlass(text); return; }
            if (kind == "ambient") { Tap(text); return; }
            NoZoom(text, kind == "high" || kind == "meeting" ? 6 : 3.5);
        }

        // 原尺寸：在玻璃上輕輕敲一下（小漣漪）
        void Tap(string text)
        {
            if (Out && Grounded()) { poseKind = "tap"; SetState("pose", 1.5); gt = 0; }
            Say(text, 2.6);
        }

        // 不放大：朝滑鼠跳一下＋泡泡
        public void NoZoom(string text, double sec)
        {
            if (Out && Grounded())
            {
                double dx = Cursor.Position.X - Cx;
                dir = dx >= 0 ? 1 : -1;
                if (Math.Abs(dx) > 40 * k && Math.Abs(dx) < 500 * k && supH == IntPtr.Zero) Jump(Clamp(dx * 0.8, -320 * k, 320 * k), -300 * k);
                else Jump(0, -280 * k);
            }
            Say(text, sec);
        }

        // ---------- 第四面牆：放大敲螢幕 ----------
        public void StartGlass(string text)
        {
            if (!Grounded() || !Out) { Say(text, 2.5); return; }
            Rectangle wa = w.WA(Cx, y + SH / 2.0);
            if (y + SH - 3.2 * SH < wa.Top) { Say(text, 2.5); return; }
            afterGlass = text; gt = 0; sc = 1; knock = 0;
            SetState("glass", 99);
        }

        void Glass(double dt)
        {
            double prev = gt;
            gt += dt;
            Point cp = Cursor.Position;
            dir = cp.X >= Cx ? 1 : -1;
            if (gt < 0.5) sc = 1 + 2 * Ease(gt / 0.5);
            else if (gt < 3.4)
            {
                sc = 3;
                if (prev < 0.55 && gt >= 0.55) { if (bubble == afterGlass && Bt > 0) Bt = Math.Max(Bt, 2.8); else Say(afterGlass, 2.8); }
                if (Math.Floor(gt * 2.2) != Math.Floor(prev * 2.2)) knock = 0.12;
            }
            else if (gt < 3.9) sc = 3 - 2 * Ease((gt - 3.4) / 0.5);
            else { sc = 1; SetState("idle", 1.2); }
            if (knock > 0) knock -= dt;
        }

        // ---------- 拖曳 ----------
        public void MouseDown(MouseEventArgs e)
        {
            // 有通知在等你點：一按下去就算（就算他在走路、在敲玻璃）
            if (e.Button == MouseButtons.Left && w.NoticeClicked(this)) { dragging = false; return; }
            if (e.Button != MouseButtons.Left || state == "glass" || state == "peek" || state == "stowfly" || state == "enter" || state == "exit" || state == "fling") return;
            Point p = Cursor.Position;
            if (p.X < x - 6 - 9 * S || p.X > x + SW + 6 + 9 * S || p.Y < y - 6 - (P.TopRows + 3) * S || p.Y > y + SH + 6) return;
            dragging = true; dragSaid = false; dragStart = p; dragMoved = 0;
            grabDx = p.X - x; grabDy = p.Y - y;
            lastMx = p.X; lastMy = p.Y; lastMt = w.Now; dvx = dvy = 0;
        }

        public void MouseUp(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left && dragging) EndDrag();
            else if (e.Button == MouseButtons.Right && Menu != null) { w.FillMenu(this, Menu); w.ShowMenu(Menu, P.Name, false); }
        }

        public bool Dragging { get { return dragging && state == "drag"; } }

        bool DragUpdate(double now, double dt)
        {
            if ((Control.MouseButtons & MouseButtons.Left) == 0) { EndDrag(); return false; }
            Point p = Cursor.Position;
            double mdt = now - lastMt;
            if (mdt > 0.001) { dvx = dvx * 0.5 + 0.5 * (p.X - lastMx) / mdt; dvy = dvy * 0.5 + 0.5 * (p.Y - lastMy) / mdt; }
            lastMx = p.X; lastMy = p.Y; lastMt = now;
            dragMoved = Math.Max(dragMoved, Math.Abs(p.X - dragStart.X) + Math.Abs(p.Y - dragStart.Y));
            if (dragMoved <= 6) return false;
            if (state != "drag") { state = "drag"; supH = IntPtr.Zero; sleepMode = false; sc = 1; if (InScene) w.AbortScene(); }
            x = p.X - grabDx; y = p.Y - grabDy;
            anim += dt;
            if (Bt > 0) Bt -= dt;
            if (!dragSaid) { dragSaid = true; Say(L("drag"), 1.5); }
            return true;
        }

        void EndDrag()
        {
            dragging = false;
            if (state != "drag") { Clicked(); return; }
            double lim = 2200 * k;
            Throw(Clamp(dvx, -lim, lim), Clamp(dvy, -lim, lim));
        }

        // ================= 丟回櫃子（像投籃）=================
        bool nearMiss;

        // 測試用：在 (px,py) 放手、給一個速度
        public void SimThrow(double px, double py, double tvx, double tvy)
        {
            if (!Out) return;
            dragging = false;
            x = px - SW / 2.0; y = py - SH / 2.0;
            Throw(tvx, tvy);
        }

        void Throw(double tvx, double tvy)
        {
            if (P.Pik) PikThrown(ref tvx, ref tvy);
            Rectangle zone = w.ShelfZone(SW, SH);
            double cx = Cx, cy = y + SH / 2.0, speed = Math.Abs(tvx) + Math.Abs(tvy);
            nearMiss = false;
            // 在櫃子附近放手：直接收進去（有甩的話算投進）
            if (zone.Contains((int)cx, (int)cy))
            {
                if (speed > 700 * k) StartFling(tvx * 0.5, tvy * 0.5); else StowToShelf(true);
                return;
            }
            // 模擬飛行路線：有穿過櫃子（加大範圍）就被吸進去
            double px = cx, py = cy, pvx = tvx, pvy = tvy, g = 900 * k, best = double.MaxValue, step = 1 / 60.0;
            bool hit = false;
            for (int i = 0; i < 240; i++)
            {
                pvy += g * step; px += pvx * step; py += pvy * step;
                if (zone.Contains((int)px, (int)py)) { hit = true; break; }
                double dx = Math.Max(0, Math.Max(zone.Left - px, px - zone.Right)), dy = Math.Max(0, Math.Max(zone.Top - py, py - zone.Bottom));
                best = Math.Min(best, Math.Sqrt(dx * dx + dy * dy));
                if (!w.Inside(px, Math.Min(py, cy)) && !w.Inside(px, py)) break;   // 飛出所有螢幕
            }
            if (hit && speed > 300 * k) { StartFling(tvx, tvy); return; }
            nearMiss = speed > 600 * k && best < SW * 2.5;
            Jump(tvx, tvy);
            if (speed > 900 * k)
            {
                Say(L("throw"), 0.9);
                if (Is("po") || Is("stitch") || Is("laalaa")) rolling = true;
            }
        }

        // 照丟出去的速度飛，越飛越被自己的格子吸過去
        void StartFling(double tvx, double tvy)
        {
            double tfx, tfy; int ps;
            w.ShelfFoot(this, out tfx, out tfy, out ps);
            shelfPs = ps;
            fx1 = tfx - SW / 2.0; fy1 = tfy - SH;
            vx = tvx; vy = tvy; flyT = 0;
            supH = IntPtr.Zero; sc = 1; fetching = false; InScene = false;
            rolling = Is("po") || Is("stitch") || Is("laalaa");
            SetState("fling", 99);
        }

        void Fling(double dt)
        {
            flyT += dt;
            double f = Math.Min(1, flyT / 0.7);
            double ax2 = (fx1 - x) * 26 * f * f - vx * 9.5 * f;
            double ay2 = (fy1 - y) * 26 * f * f - vy * 9.5 * f + 900 * k * (1 - f);
            vx += ax2 * dt; vy += ay2 * dt; x += vx * dt; y += vy * dt;
            if (Math.Abs(vx) > 5) dir = vx > 0 ? 1 : -1;
            double d = Math.Sqrt((fx1 - x) * (fx1 - x) + (fy1 - y) * (fy1 - y));
            if ((d < 10 * k && flyT > 0.25) || flyT > 2.2)
            {
                x = fx1; y = fy1; rolling = false;
                GoalCheer();
                gt = 0; SetState("enter", 99);
            }
        }

        void GoalCheer()
        {
            string line;
            switch (P.Id)
            {
                case "po": line = "進球！🏀 再來一次！"; break;
                case "stitch": line = "嘻嘻嘻～進球！🏀"; break;
                case "hangyodon": line = "英雄……降落成功 🏀"; break;
                case "tinky": line = "進球！🏀 丁丁回家家～"; break;
                case "dipsy": line = "進球。🏀 帽子還在，酷。"; break;
                case "laalaa": line = "進球！🏀 啦啦啦～"; break;
                case "pkred": case "pkyellow": case "pkblue": line = PikLine("goal"); break;
                case "boba": case "coffee": case "onigiri": case "sticky": line = OrigLine("goal"); break;
                default: line = "進球！🏀 Thwip!"; break;
            }
            Say(line, 2.4);
            Burst(14);
            w.GoalCheer(this);
        }

        // 別人投進了：小小歡呼
        public void Cheer()
        {
            if (!Out || InScene) return;
            string line;
            switch (P.Id)
            {
                case "po": line = "Eh-oh! 進了！"; break;
                case "stitch": line = "ih-ih! 嘻嘻嘻"; break;
                case "hangyodon": line = "好、好厲害！"; break;
                case "tinky": line = "好棒棒！大抱抱！"; break;
                case "dipsy": line = "酷！"; break;
                case "laalaa": line = "啦啦～進了！"; break;
                case "pkred": case "pkyellow": case "pkblue": line = PikLine("cheer"); break;
                case "boba": case "coffee": case "onigiri": case "sticky": line = OrigLine("cheer"); break;
                default: line = "好球！"; break;
            }
            Say(line, 1.4);
            Mark(0);
            if (Grounded() && state != "sleep") Jump(0, -220 * k);
        }

        string MissLine()
        {
            switch (P.Id)
            {
                case "po": return "差一點點！再來一次！";
                case "stitch": return "ih! 沒進！嘻嘻";
                case "hangyodon": return "偏、偏了…英雄也會失手";
                case "tinky": return "哎喲，差一點點…";
                case "dipsy": return "沒進…但帽子很帥";
                case "laalaa": return "差一點！再來一次！";
                case "pkred": case "pkyellow": case "pkblue": return PikLine("miss");
                case "boba": case "coffee": case "onigiri": case "sticky": return OrigLine("miss");
            }
            return "差一點！再一次？";
        }

        // ================= 公仔櫃：回櫃子／出來 =================
        // 回櫃子：飛到自己那格（每個角色飛法不同），到了縮小、櫃子接手畫
        public void StowToShelf(bool say)
        {
            if (!Out) return;
            double tfx, tfy; int ps;
            w.ShelfFoot(this, out tfx, out tfy, out ps);
            shelfPs = ps;
            if (say) Say(L("shelf_in"), 2.2);
            fetching = false; sc = 1; rolling = false; InScene = false;
            fx0 = x; fy0 = y; fx1 = tfx - SW / 2.0; fy1 = tfy - SH;
            double d = Math.Sqrt((fx1 - fx0) * (fx1 - fx0) + (fy1 - fy0) * (fy1 - fy0));
            flyDur = Clamp(d / (Is("hangyodon") ? 560 * k : 900 * k), 0.35, 1.6);
            flyArc = Math.Min(160 * k, 40 * k + d * 0.25);
            flyT = 0; supH = IntPtr.Zero;
            SetState("stowfly", 99);
        }

        void StowFly(double dt)
        {
            flyT += dt;
            double f = Math.Min(1, flyT / flyDur), e = Is("hangyodon") ? Ease(f) : f;
            if (Is("hangyodon") && rnd.NextDouble() < 0.25) Mark(5);
            x = fx0 + (fx1 - fx0) * e;
            y = fy0 + (fy1 - fy0) * e - Math.Sin(Math.PI * f) * flyArc;
            dir = fx1 >= fx0 ? 1 : -1;
            if (f >= 1) { x = fx1; y = fy1; gt = 0; SetState("enter", 99); }
        }

        void Enter(double dt)
        {
            gt += dt;
            double target = shelfPs / (double)S;
            sc = 1 + (target - 1) * Ease(gt / 0.35);
            if (gt >= 0.35) { sc = 1; Out = false; HideForms(); state = "shelf"; ShelfFx = 0; w.PetStowed(this); }
        }

        // 從格子裡出來：先在格子裡變大，再跳到桌面
        public void ComeOut(bool say)
        {
            EnsureForms();
            double tfx, tfy; int ps;
            w.ShelfFoot(this, out tfx, out tfy, out ps);
            shelfPs = ps;
            x = tfx - SW / 2.0; y = tfy - SH;
            sc = ps / (double)S; gt = 0;
            Out = true; InScene = false; dragging = false; sleepMode = false;
            SetState("exit", 99);
            if (say) Say(L("shelf_out"), 1.8);
        }

        void Exit(double dt)
        {
            gt += dt;
            double from = shelfPs / (double)S;
            sc = from + (1 - from) * Ease(gt / 0.3);
            if (gt < 0.3) return;
            sc = 1;
            Rectangle wa = w.WA(Cx, y + SH);
            double tx = Clamp(Cx - R(140, 360) * k, wa.Left + SW, wa.Right - SW);
            if (Is("hangyodon")) { StartSwim(tx, wa.Bottom, false); return; }
            BallisticTo(tx, wa.Bottom);
            if (Is("stitch")) rolling = true;
            if (P.Orig) OrigExit();
            if (P.Pik) afterLand = "pksprout";                                     // 皮克敏：落地先種在土裡，再「噗！」拔出來
            if (Is("tinky") && rnd.NextDouble() < 0.3) afterLand = "plop";          // 丁丁跳出來常常跌坐
            else if (Is("laalaa") && rnd.NextDouble() < 0.4) afterLand = "twirl";   // 拉拉落地轉一圈
            else if (Is("dipsy") && rnd.NextDouble() < 0.4) afterLand = "hattip";   // 迪西落地扶帽子
        }

        // ---------- 走到指定位置（串場、大合照用）----------
        double gotoSpeed = 1;
        void GoTo(double dt)
        {
            if (Math.Abs(seekX - Cx) < 4) { x = seekX - SW / 2.0; SetState("idle", InScene ? 30 : 1); return; }
            dir = seekX > Cx ? 1 : -1;
            if (MoveOnGround(dt, Math.Max(P.Speed, 60) * k * gotoSpeed)) return;
            if ((dir > 0 && Cx > seekX) || (dir < 0 && Cx < seekX)) x = seekX - SW / 2.0;
            if (t < 0) SetState("idle", InScene ? 30 : 1);
        }

        // ---------- 躲到別人後面（小波怕錯誤）----------
        double hideX;
        public void HideBehindPet(Pet other)
        {
            if (!Grounded()) return;
            hideX = other.Cx + (other.Cx > Cx ? 1 : -1) * SW * 0.45;
            SetState("hide", 4);
        }
        void HideBehind(double dt)
        {
            if (Math.Abs(hideX - Cx) > 4) { dir = hideX > Cx ? 1 : -1; if (MoveOnGround(dt, 110 * k)) return; }
            if (t < 0) SetState("idle", 1);
        }

        // ================= 球 =================
        public void BallStarted()
        {
            if (!Out || InScene) return;
            fetching = true;
            WakeIfSleep();
            if (Grounded() && state != "hug") SetState("fetch", 15);
        }

        void Fetch(double dt)
        {
            if (!w.BallOn || !fetching) { fetching = false; SetState("idle", 1); return; }
            if (w.Holder != null) { SetState("idle", 0.5); return; }
            double r = w.BallR(), dxb = w.Bx - Cx, foot = y + SH;
            bool resting = w.Bvy == 0 && Math.Abs(w.Bvx) < 30 * k;
            bool sameLevel = Math.Abs(w.By + r - foot) < 40 * k;
            if (resting && !sameLevel) { BallisticTo(w.Bx, w.By + r); return; }
            double sp = (P.Tubby ? (Is("tinky") ? 90 : (Is("laalaa") ? 150 : 125)) : (Is("hangyodon") ? 70 : (Is("stitch") ? 170 : (Is("po") ? 150 : 125)))) * k;
            if (Math.Abs(dxb) > 6) { dir = dxb > 0 ? 1 : -1; if (MoveOnGround(dt, sp)) return; }
            else if (w.By < y && w.Bvy > 0 && w.By > y - 160 * k) { Jump(0, -380 * k); return; }
            if (t < 0) { fetching = false; SetState("idle", 1); Say(L("ball_far"), 1.6); }
        }

        // 球碰到他（World 判斷）：回傳 true＝處理掉了
        public bool TouchBall()
        {
            if (!fetching || state == "drag" || !Out) return false;
            fetching = false;
            if (ballXp < 20) { ballXp += 2; AddXp(2); }
            Burst(6);
            if (P.Pik) { PikBall(); return true; }
            if (P.Orig) { OrigBall(); return true; }
            switch (P.Id)
            {
                case "po": PoBall(); return true;
                case "stitch": StitchBall(); return true;
                case "hangyodon": HangyodonBall(); return true;
                case "tinky": TinkyBall(); return true;
                case "dipsy": DipsyBall(); return true;
                case "laalaa": LaaLaaBall(); return true;
            }
            // Spidey：踢回滑鼠的方向（多人時用絲接住）
            if (w.OutCount() > 1 && rnd.NextDouble() < 0.6) { WebCatch(); return true; }
            Say(L("ball_catch"), 1.8);
            KickBallToCursor(1.0);
            if (Grounded()) SetState("kick", 0.5);
            return true;
        }

        void KickBallToCursor(double power)
        {
            Point c = Cursor.Position;
            w.Bvx = Clamp((c.X - w.Bx) * 1.1 * power, -900 * k, 900 * k);
            w.Bvy = -R(450, 650) * k * power;
            w.By = Math.Min(w.By, y - 4 * k);
            w.BallIdle = 0; w.CatchCd = 1.0;
        }

        // ================= 外部事件 =================
        public void OnSave(bool lead)
        {
            if (saveXpCd <= 0) { saveXpCd = 120; AddXp(1); }
            WakeIfSleep();
            if (lead) Say(L("save"), 2);
            if (Grounded() && (lead || rnd.NextDouble() < 0.3)) Jump(0, -300 * k);
        }

        public void OnErrors(int n, int prev, Pet hideFrom)
        {
            WakeIfSleep();
            if (n > prev)
            {
                sense = Is("spidey") ? 2.8 : 0;
                string line = L("errors", "n", n.ToString());
                if (Is("hangyodon") && Grounded()) { capeT = 0; SetState("capetrip", 2.6); }
                else if (Is("stitch") && Grounded()) { Jump(0, -360 * k); Mark(1); }
                else if (Is("po") && hideFrom != null && Grounded()) HideBehindPet(hideFrom);
                else if (Is("tinky") && Grounded()) Plop(null);
                else if (Is("dipsy") && Grounded()) { poseKind = "hatdown"; SetState("pose", 2.6); }
                else if (Is("laalaa") && hideFrom != null && Grounded()) HideBehindPet(hideFrom);
                else if (P.Pik && Grounded()) PikReact("errors");
                else if (P.Orig && Grounded()) OrigReact("errors");
                else if (state == "walk") SetState("idle", 3);
                Say(line, 3, true);
            }
            else if (n == 0) { AddXp(2); Hug(L("errors_ok"), 2.6); }
        }

        public void OnTyping()
        {
            if (!Grounded() || state == "hug" || state == "sleep" || InScene || Quiet) return;
            if (Is("stitch")) { SetState("elvis", 4); }
            else if (Is("laalaa")) { SetState("dance", 4); Mark(0); Mark(0); }
            else SetState("dance", 4);
            Say(L("typing"), 2.5);
        }

        public void React()
        {
            if (!Out || InScene) return;
            WakeIfSleep();
            if (Grounded()) { Jump(0, -240 * k); }
            Mark(1);
            Say(L("react"), 1.4);
        }

        string who = "Claude";
        // 卡住提醒（文字已組好）
        public void Alert(string text)
        {
            WakeIfSleep();
            if (Is("spidey")) sense = 2.8;
            Knock(text, "high");
            Say(text, 5, true);
            bubblePri = 2;
            stuckLine = text; stuckRepeat = 3.5;
        }
        public void ClearAlert() { stuckLine = null; }

        public void SystemIdle(bool idle)
        {
            if (idle) { sleepMode = true; if (Out && Grounded() && state != "hug" && state != "glass") GoSleep(); }
            else
            {
                bool was = state == "sleep";
                WakeIfSleep();
                if (was && Out) Knock(L("welcome"), "ambient");
            }
        }

        public void Rest(double restMin)
        {
            WakeIfSleep();
            Hug(L("rest", "n", restMin.ToString()), 8);
        }

        public void NightChanged(bool d)
        {
            if (!Out) return;
            if (d) { if (Is("spidey")) sense = 2.5; NoZoom(L("night_on"), 3.5); }
            else Say(L("night_off"), 3);
        }

        public string Greeting()
        {
            string sl = SeasonLine();
            if (sl != null && w.SeasonNow != "friday") return sl;
            if (Night) return L("g_d");
            int h = DateTime.Now.Hour;
            if (h >= 23 || h < 5) return L("g_late");
            if (h < 11) return L("g_morning");
            if (h < 14) return L("g_noon");
            if (h >= 18) return L("g_evening");
            return L("g_day");
        }

        string SeasonLine()
        {
            if (w.SeasonNow == "") return null;
            string s = L("s_" + w.SeasonNow);
            return s == "" ? null : s;
        }

        string LateLine()
        {
            int h = DateTime.Now.Hour;
            if (Night) return h >= 21 || h < 5 ? L("late_dd") : L("late_d");
            if (h >= 23 || h < 5) return L("late23");
            if (h == 12) return L("late12");
            if (h == 15) return L("late15");
            return null;
        }

        public string AppLine(IntPtr h)
        {
            string name = "";
            try { int pid; W.GetWindowThreadProcessId(h, out pid); name = Process.GetProcessById(pid).ProcessName.ToLowerInvariant(); }
            catch { }
            bool chat = name.Contains("teams") || name == "slack" || name == "line";
            if (Night)
            {
                if (name == "code") return L("app_code_d");
                if (chat) return L("app_chat_d");
                if (name == "excel" || name == "powerpnt" || name == "winword") return L("app_office_d");
                return L("app_other_d");
            }
            if (name == "chrome" || name == "msedge" || name == "firefox") return L("app_browser");
            if (name == "code") return L("app_code");
            if (name == "excel") return L("app_excel");
            if (name == "powerpnt") return L("app_ppt");
            if (name == "winword") return L("app_word");
            if (chat) return L("app_chat");
            if (name == "explorer") return L("app_files");
            return L("app_other");
        }

        // ---------- 選單／指令 ----------
        public void Act(string a)
        {
            if (a != "sleep") WakeIfSleep();
            if (!Out && a != "bond" && a != "hi") { Say(Pick(new string[] { "我在櫃子裡，先放我出去～", "點一下櫃子裡的我，我就出來囉" }), 1.8); return; }
            switch (a)
            {
                case "hi":
                    if (Out && Grounded()) { if (Is("po")) SetState("wave", 1.6); else if (Is("hangyodon")) { poseKind = "hero"; SetState("pose", 1.4); } else if (Is("dipsy")) { poseKind = "hattip"; SetState("pose", 1.6); } else if (P.Tubby || P.Orig) SetState("wave", 1.6); else Jump(0, -260 * k); }
                    Say(L("hi"), 2.4);
                    break;
                case "hug": Hug(L("hugs"), 2.4); break;
                case "pat": Pat(); break;
                case "bond": ShowBond(); break;
                case "knock": Knock(L("knock"), "user"); break;
                case "jump": if (!JumpToPlatform()) Say(L("nojump"), 1.6); break;
                case "sleep": if (Grounded()) { GoSleep(); t = 8; Say(L("sleep"), 1.2); } break;
                case "sig": Signature(); break;
                case "celebrate": Celebrate("", true); break;
                default: ActSpecial(a); break;
            }
        }

        // 慶祝（上版 tag／Codex、Claude 做完）：每個角色自己的方式
        public void Celebrate(string env, bool lead)
        {
            if (Quiet && w.quietOn) return;
            WakeIfSleep();
            if (!Out) { if (lead) Say(env == "prod" ? L("tag_prod") : (env == "dev" ? L("tag_dev") : L("tag")), 4); return; }
            string line = Night ? L("tag") : (env == "prod" ? L("tag_prod") : (env == "dev" ? L("tag_dev") : L("tag")));
            CelebrateWith(line, lead);
            AddXp(lead ? 5 : 2);
        }

        public void CelebrateWith(string line, bool lead)
        {
            switch (P.Id)
            {
                case "po": HomeRun(line, lead); break;
                case "stitch": if (Grounded()) SetState("elvis", 4.5); Say(line, 4); for (int i = 0; i < 3; i++) Mark(0); break;
                case "hangyodon": if (Grounded()) { poseKind = "hero"; SetState("pose", 3.4); } Say(line, 4); for (int i = 0; i < 6; i++) Mark(5); Burst(6); break;
                case "tinky": if (Grounded()) TinkyBag("star", true); Say(line, 4); Burst(10); break;
                case "dipsy": if (Grounded()) HatToss(true); Say(line, 4); Burst(8); break;
                case "laalaa": if (Grounded()) SetState("twirl", 2.4); Say(line, 4); for (int i = 0; i < 4; i++) Mark(0); Burst(8); break;
                case "boba": case "coffee": case "onigiri": case "sticky": OrigCelebrate(line, lead); break;
                default:
                    if (lead) w.Fireworks(w.WA(Cx, y + SH / 2.0), 10, -1);
                    if (Grounded()) SetState("dance", 3.5);
                    Say(line, 4); Burst(10);
                    break;
            }
            AddHeart(); AddHeart();
        }

        // Codex／Claude 做完：Spidey 敲玻璃；小波全壘打；其他人照自己的慶祝
        public void Done(string src, bool lead)
        {
            WakeIfSleep();
            who = src;
            string text = L("done", "who", src);
            if (!lead) { React(); return; }
            if (!Out) { Say(text, 4); return; }
            if (Is("spidey")) { NoZoom(text, 4); Burst(8); }
            else CelebrateWith(text, true);
            AddXp(1);
        }

        public void Wait(string src)
        {
            WakeIfSleep();
            string text = L("wait", "who", src);
            NoZoom(text, 3);
        }

        public void Unstuck(string src)
        {
            stuckLine = null;
            Say(L("unstuck", "who", src), 2);
        }

        public void LateTick()
        {
            if (lateCd > 0 || !Out || !Free() || Quiet) return;
            string l = LateLine();
            if (l == null) return;
            lateCd = Night ? 240 : 600;
            Say(l, 3.5); SetState("idle", 3.5);
        }
    }

    // ================= 各角色專屬的動作 =================
    partial class Pet
    {
        string poseKind = "";           // pose 狀態畫哪個姿勢（homerun／hero／photo／grin）
        double batT; bool batHit;       // 小波揮棒
        bool scooterLost;               // 小波的滑板車被史迪仔騎走了（串場）
        public bool RidingStolen;       // 史迪仔正在騎別人的滑板車（串場）
        IntPtr crawlH; double ceilY, ceilL, ceilR; // 史迪仔爬牆／天花板

        // 角色專屬狀態：回傳 true＝處理掉了
        bool StepSpecial(double dt, Rectangle wa)
        {
            if (HoldToast && rnd.NextDouble() < dt * 2.5 && notes.Count < 10) notes.Add(new double[] { R(-8, 8) * k, 0, 7 });   // 吐司屑屑
            if (P.Tubby && TubbyStep(dt)) return true;
            if (P.Pik && PikStep(dt)) return true;
            if (P.Orig && OrigStep(dt)) return true;
            switch (state)
            {
                case "plop":
                    sT += dt;
                    if (t < 0) SetState("idle", InScene ? 30 : 1);
                    return true;
                // ---- Spidey ----
                case "swing": Swing(dt, wa); return true;
                case "hang": Hang(dt, wa); return true;
                case "climb": Climb(dt, wa); return true;
                case "shoot": Shoot(dt); return true;
                case "zip": Zip(dt); return true;
                case "peek": Peek(dt, wa); return true;
                case "webcatch":
                    if (t < 0) { w.ReleaseBall(Cx, y, 0, 0); KickBallToCursor(1.0); SetState("kick", 0.4); }
                    return true;
                case "sling": if (t < 0) SetState("idle", 1); return true;
                // ---- 小波 ----
                case "spin":
                    if (t < 0) { SetState("idle", 1); Say(Pick(new string[] { "再來一次！", "再來一次！嘻嘻" }), 1.4); }
                    return true;
                case "bat": Bat(dt); return true;
                case "catch":
                    if (t < 0) { SetState("throw", 0.35); }
                    return true;
                case "throw":
                    if (t < 0.15 && w.Holder == this) { w.ReleaseBall(Cx + dir * 6 * k, y + 6 * k, 0, 0); KickBallToCursor(1.0); }
                    if (t < 0) SetState("idle", 1);
                    return true;
                // ---- 史迪仔 ----
                case "wall": Wall(dt, wa); return true;
                case "ceil": Ceil(dt); return true;
                case "curl": Curl(dt); return true;
                case "nudge": if (t < 0) SetState("idle", 1); return true;
                case "chomp": Chomp(dt); return true;
                case "elvis":
                    if (rnd.NextDouble() < dt * 3) Mark(0);
                    if (t < 0) { SetState("idle", 1); if (!InScene) Say(Pick(new string[] { "Thank you very much ♪", "嘻嘻嘻 ♪" }), 1.6); }
                    return true;
                // ---- 人魚漢頓 ----
                case "swim": Swim(dt); return true;
                case "header": if (t < 0) SetState(fetching ? "fetch" : "idle", fetching ? 15 : 1); return true;
                case "capetrip":
                    capeT += dt;
                    if (capeT >= 1.4 && capeT - dt < 1.4) { tripT = 1.1; Say(Pick(new string[] { "哎呀…（跌倒）", "嗚…英雄也會跌倒的", "我、我沒事！" }), 1.8); }
                    if (t < 0) SetState("idle", 1);
                    return true;
            }
            return false;
        }

        // 走到視窗邊緣：0＝照預設跳下去、1＝回頭、2＝換狀態了
        int EdgeOfWindow(bool right)
        {
            if (P.Pik) return PikEdge(right);
            if (P.Orig) return OrigEdge(right);
            switch (P.Id)
            {
                case "spidey":
                    if (!goClimb && rnd.NextDouble() < 0.55) { dir = -dir; if (rnd.NextDouble() < 0.3) SpinWeb(supH, right); return 1; }
                    return 0;
                case "po":
                    if (rnd.NextDouble() < 0.4) { dir = -dir; return 1; }
                    {
                        double[] o = PickPlatform(60 * k, 700 * k);
                        if (o != null && (o[0] > Cx) == (dir > 0)) { BallisticTo(o[0], o[1]); Say(L("jump"), 0.9); return 2; }
                    }
                    x += dir * 4 * k; Jump(dir * P.Speed * k * 1.7, -280 * k); Say(L("jump"), 0.8);   // 小跳台飛出去
                    return 2;
                case "stitch":
                    {
                        WinInfo wi;
                        if ((goClimb || rnd.NextDouble() < 0.4) && w.Cands.TryGetValue(supH, out wi) && Math.Abs((right ? supR : supL) - (right ? wi.R : wi.L)) < 14
                            && wi.B < w.WA(Cx, y).Bottom - SH - 10)
                        { StartWallDown(wi, right); return 2; }
                        if (rnd.NextDouble() < 0.5) { dir = -dir; return 1; }
                        return 0;
                    }
                case "hangyodon":
                    if (rnd.NextDouble() < 0.55) { dir = -dir; return 1; }
                    {
                        double[] o = PickPlatform(60 * k, 900 * k);
                        if (o != null) { Say(L("jump"), 1.4); StartSwim(o[0], o[1], false); return 2; }
                    }
                    dir = -dir; return 1;
                case "tinky":
                    // 丁丁走路很小心：多半回頭；跳下去常常跌坐
                    if (rnd.NextDouble() < 0.7) { dir = -dir; if (rnd.NextDouble() < 0.3) Say("小心小心…", 1.2); return 1; }
                    x += dir * 4 * k; Jump(dir * P.Speed * k * 2, -200 * k); afterLand = "plop"; Say("哎…", 0.8);
                    return 2;
                case "dipsy":
                    if (rnd.NextDouble() < 0.4) { dir = -dir; return 1; }
                    x += dir * 4 * k; Jump(dir * 130 * k, -320 * k); afterLand = rnd.NextDouble() < 0.5 ? "hattip" : ""; Say("嘿！", 0.8);
                    return 2;
                case "laalaa":
                    if (rnd.NextDouble() < 0.35) { dir = -dir; return 1; }
                    {
                        double[] o = PickPlatform(60 * k, 700 * k);
                        if (o != null && (o[0] > Cx) == (dir > 0)) { BallisticTo(o[0], o[1]); afterLand = "twirl"; Say(L("jump"), 0.9); return 2; }
                    }
                    x += dir * 4 * k; Jump(dir * 150 * k, -360 * k); afterLand = "twirl"; Say(L("jump"), 0.8);
                    return 2;
            }
            return 0;
        }

        // 走到螢幕邊：true＝換狀態了（false＝回頭）
        bool EdgeOfScreen()
        {
            switch (P.Id)
            {
                case "spidey": if (goClimb || rnd.NextDouble() < 0.35) { StartClimb(dir); return true; } return false;
                case "stitch": if (goClimb || rnd.NextDouble() < 0.3) { StartWallUp(dir); return true; } return false;
                case "po": dir = -dir; Jump(dir * 60 * k, -220 * k); Say("嘟嘟～迴轉！", 0.9); return true;
            }
            return false;
        }

        // 落地時的特別反應：true＝處理掉了
        bool Landed(bool wasRolling, double landVx)
        {
            if (P.Pik && PikLanded(wasRolling)) return true;
            if (P.Orig && OrigLanded(wasRolling)) return true;
            if (Is("stitch") && wasRolling) { vx = landVx * 0.8; if (Math.Abs(vx) < 60 * k) vx = dir * 120 * k; SetState("curl", R(0.8, 1.4)); return true; }
            if (Is("po") && wasRolling && state != "spin") { SetState("dizzy", 0.8); Say(Pick(new string[] { "轉圈圈～", "再來一次！" }), 1.2); return true; }
            if (Is("po") && state == "spin") { SetState("spin", 0.4); return true; }
            if (Is("tinky") && lastLandVy > 650 * k && state != "plop") { afterLand = ""; Plop(Pick(new string[] { "哎喲！", "哎喲…屁股好痛", "哎喲！（跌坐）" })); return true; }
            if (Is("laalaa") && wasRolling) { afterLand = ""; SetState("twirl", 0.9); Say(Pick(new string[] { "轉圈圈～", "再來一次！" }), 1.2); return true; }
            return false;
        }

        void LandAction()
        {
            string a = afterLand; afterLand = "";
            if (P.Pik && PikLand(a)) return;
            if (P.Orig && OrigLand(a)) return;
            switch (a)
            {
                case "wave": SetState("wave", 1.8); Say("Eh-oh!", 1.6); break;
                case "sniff": poseKind = "grin"; SetState("pose", 1.6); Mark(2); Say(Pick(new string[] { "（聞聞）ih?", "嘻嘻，這個好玩", "ih-ih! 史迪仔的！" }), 1.6); break;
                case "bubbles": SetState("idle", 1.6); for (int i = 0; i < 4; i++) Mark(5); break;
                case "plop": Plop(Pick(new string[] { "哎喲！", "哎喲！（跌坐）" })); break;
                case "hattip": poseKind = "hattip"; SetState("pose", 1.6); Say(Pick(new string[] { "Eh-oh.", "嘿。", "（扶帽子）酷。" }), 1.4); break;
                case "twirl": SetState("twirl", 1.2); Say(Pick(new string[] { "啦啦啦～", "轉圈圈～" }), 1.4); break;
                default: SetState("idle", R(1, 2)); break;
            }
        }

        void Decide(Rectangle wa)
        {
            goClimb = false;
            if (Bt > 0 && bubblePri > 0) { SetState("idle", R(1, 2)); return; }   // 通知還在講：先別亂跑亂聊
            if (fetching && w.BallOn) { SetState("fetch", 15); return; }
            double r = rnd.NextDouble(), cx = Cx;
            if (w.LunchState == "nap" && !Quiet) { GoSleep(); t = 60; return; }               // 吃飽睡午覺
            if (HoldingFood() && !Quiet && r < .3) { SetState("idle", R(2, 4)); Say(LunchLine("talk"), 2.4); return; }
            if (Quiet)
            {
                // 專注中：安靜發呆、偶爾慢慢走兩步
                if (r < .75) SetState("idle", R(5, 10)); else { dir = rnd.NextDouble() < .5 ? -1 : 1; SetState("walk", R(1, 2.5)); }
                return;
            }
            if (w.OutCount() > 1 && rnd.NextDouble() < 0.12 && VisitFriend()) return;
            if (P.Pik) { PikDecide(r, wa); return; }
            if (P.Orig) { OrigDecide(r, wa); return; }
            switch (P.Id)
            {
                case "spidey":
                    if (r < .20) SetState("idle", R(1.5, 4));
                    else if (r < .48) { if (!JumpToPlatform()) Hop(); }
                    else if (r < .62) { if (!ShootTo("swing")) Hop(); }
                    else if (r < .70) ShootTo("hang");
                    else if (r < .75) { goClimb = true; dir = cx < (wa.Left + wa.Right) / 2.0 ? -1 : 1; SetState("walk", 30); }
                    else if (r < .80) Hug(L("hugs"), 2.2);
                    else if (r < (Night ? .84 : .815)) Knock(L("knock"), "ambient");
                    else if (r < .86 && lateCd <= 0 && LateLine() != null) LateTick();
                    else if (r < .90 && SeasonLine() != null) { Say(SeasonLine(), 3); SetState("idle", 3); }
                    else { dir = rnd.NextDouble() < .5 ? -1 : 1; SetState("walk", R(3, 6)); }
                    break;
                case "po":
                    if (r < .16) SetState("idle", R(1.5, 3.5));
                    else if (r < .44) { dir = rnd.NextDouble() < .5 ? -1 : 1; SetState("walk", R(3, 7)); if (rnd.NextDouble() < .25) Say(Pick(new string[] { "嘟嘟～", "騎車車～", "咻咻～" }), 1); }
                    else if (r < .60) { if (!JumpToPlatform()) Hop(); }
                    else if (r < .66) { SetState("wave", 1.6); Say(L("talk"), 2.2); }
                    else if (r < .71) Hug(L("hugs"), 2.2);
                    else if (r < (Night ? .76 : .74)) Knock(L("knock"), "ambient");
                    else if (r < .79) { StartBat(false); Say("揮棒練習！嘿！", 1.2); }
                    else if (r < .83 && lateCd <= 0 && LateLine() != null) LateTick();
                    else if (r < .87 && SeasonLine() != null) { Say(SeasonLine(), 3); SetState("idle", 3); }
                    else if (r < .92) { SetState("idle", 2.5); Say(L("talk"), 2.4); }
                    else { dir = -dir; SetState("walk", R(3, 6)); }
                    break;
                case "stitch":
                    if (r < .14) SetState("idle", R(1.2, 3));
                    else if (r < .42) { dir = rnd.NextDouble() < .5 ? -1 : 1; SetState("walk", R(2, 5)); }
                    else if (r < .56) { if (!JumpToPlatform()) Hop(); }
                    else if (r < .64) Signature();
                    else if (r < .70) { poseKind = "grin"; SetState("pose", 1.8); Say(Pick(new string[] { "嘻嘻嘻…", "ih-ih-ih!", "（壞笑）" }), 1.6); }
                    else if (r < .74) Hug(L("hugs"), 2.2);
                    else if (r < (Night ? .80 : .78)) Knock(L("knock"), "ambient");
                    else if (r < .82) { SetState("elvis", 3.5); Say(Night ? "♪ 呼啊～" : "♪ Aloha～", 1.6); }
                    else if (r < .85 && lateCd <= 0 && LateLine() != null) LateTick();
                    else if (r < .88 && SeasonLine() != null) { Say(SeasonLine(), 3); SetState("idle", 3); }
                    else if (r < .93) { SetState("idle", 2); Say(L("talk"), 2.4); }
                    else { dir = -dir; SetState("walk", R(2, 4)); }
                    break;
                case "hangyodon":
                    if (r < .20) { SetState("idle", R(2, 4)); if (rnd.NextDouble() < .4) for (int i = 0; i < 3; i++) Mark(5); }
                    else if (r < .46) { dir = rnd.NextDouble() < .5 ? -1 : 1; SetState("walk", R(3, 6)); }
                    else if (r < .58) { double[] o = PickPlatform(60 * k, 900 * k); if (o != null) { StartSwim(o[0], o[1], false); Say(L("jump"), 1.2); } else Hop(); }
                    else if (r < .64) { SetState("idle", 2.8); Say(L("pats"), 2.4); jokeT = 2.6; }
                    else if (r < .69) Hug(L("hugs"), 2.2);
                    else if (r < (Night ? .75 : .73)) Knock(L("knock"), "ambient");
                    else if (r < .77) { poseKind = "hero"; SetState("pose", 1.8); Say(Pick(new string[] { "總有一天我會當上英雄！", "（擺英雄姿勢）帥嗎？", "英雄漢頓…還在練習中" }), 2); }
                    else if (r < .80) { GoSleep(); t = R(5, 9); Say(L("sleep"), 1.4); }
                    else if (r < .84 && lateCd <= 0 && LateLine() != null) LateTick();
                    else if (r < .87 && SeasonLine() != null) { Say(SeasonLine(), 3); SetState("idle", 3); }
                    else if (r < .93) { SetState("idle", 2.5); Say(L("talk"), 2.6); }
                    else { dir = -dir; SetState("walk", R(3, 6)); }
                    break;
                case "tinky":   // 慢慢走、提著魔法袋、偶爾跌坐、喜歡跳舞
                    if (r < .22) SetState("idle", R(2, 4.5));
                    else if (r < .48) { dir = rnd.NextDouble() < .5 ? -1 : 1; SetState("walk", R(3, 7)); if (rnd.NextDouble() < .2) Say(Pick(new string[] { "慢慢走～", "提著袋袋去散步～" }), 1.2); }
                    else if (r < .54) { if (!JumpToPlatform()) Hop(); }
                    else if (r < .63) TinkyBag(null, false);
                    else if (r < .68) { SetState("dance", 3.2); Say(Pick(new string[] { "丁丁跳舞～", "嘿～轉一圈～", "跳舞時間！" }), 1.6); }
                    else if (r < .72) Plop(Pick(new string[] { "哎喲！", "哎喲…（又跌倒了）" }));
                    else if (r < .77) Hug(L("hugs"), 2.2);
                    else if (r < (Night ? .82 : .80)) Knock(L("knock"), "ambient");
                    else if (r < .84 && lateCd <= 0 && LateLine() != null) LateTick();
                    else if (r < .87 && SeasonLine() != null) { Say(SeasonLine(), 3); SetState("idle", 3); }
                    else if (r < .93) { SetState("idle", 2.5); Say(L("talk"), 2.4); }
                    else { dir = -dir; SetState("walk", R(3, 6)); }
                    break;
                case "dipsy":   // 酷酷的、跟著節奏走、帽子是他的招牌
                    if (r < .18) SetState("idle", R(1.5, 3.5));
                    else if (r < .42) { dir = rnd.NextDouble() < .5 ? -1 : 1; SetState("walk", R(3, 6)); }
                    else if (r < .52) { if (!JumpToPlatform()) Hop(); }
                    else if (r < .58) { poseKind = "hattip"; SetState("pose", 1.8); Say(L("talk"), 2.2); }
                    else if (r < .63) HatToss(false);
                    else if (r < .67) { poseKind = "hatwave"; SetState("pose", 2.2); Say(Pick(new string[] { "（摘帽子揮一揮）Eh-oh!", "嘿～（揮帽子）" }), 1.8); }
                    else if (r < .73) { SetState("dance", 3.4); Say(Pick(new string[] { "嘿～嘿～", "跟著節奏～", "迪西的舞步，酷。" }), 1.8); }
                    else if (r < .77) Hug(L("hugs"), 2.2);
                    else if (r < (Night ? .82 : .80)) Knock(L("knock"), "ambient");
                    else if (r < .84 && lateCd <= 0 && LateLine() != null) LateTick();
                    else if (r < .87 && SeasonLine() != null) { Say(SeasonLine(), 3); SetState("idle", 3); }
                    else if (r < .93) { SetState("idle", 2.5); Say(L("talk"), 2.4); }
                    else { dir = -dir; SetState("walk", R(3, 6)); }
                    break;
                case "laalaa":  // 蹦蹦跳跳、帶著球、愛唱歌轉圈圈
                    if (r < .14) SetState("idle", R(1.2, 3));
                    else if (r < .40) { dir = rnd.NextDouble() < .5 ? -1 : 1; SetState("walk", R(3, 6)); if (rnd.NextDouble() < .25) Say(Pick(new string[] { "啦～啦～", "蹦蹦跳～", "踢球球～" }), 1); }
                    else if (r < .52) { if (!JumpToPlatform()) Hop(); }
                    else if (r < .60) Juggle();
                    else if (r < .66) { SetState("twirl", 1.6); Say(Pick(new string[] { "轉圈圈～", "啦啦啦～轉～" }), 1.4); }
                    else if (r < .72) { poseKind = "sing"; SetState("pose", 3.2); Say(Pick(new string[] { "啦啦啦～♪", "啦～啦啦～啦～♪", "拉拉唱歌給你聽～♪" }), 2.6); }
                    else if (r < .76) Hug(L("hugs"), 2.2);
                    else if (r < (Night ? .81 : .79)) Knock(L("knock"), "ambient");
                    else if (r < .83 && lateCd <= 0 && LateLine() != null) LateTick();
                    else if (r < .86 && SeasonLine() != null) { Say(SeasonLine(), 3); SetState("idle", 3); }
                    else if (r < .93) { SetState("idle", 2.5); Say(L("talk"), 2.4); }
                    else { dir = -dir; SetState("walk", R(3, 6)); }
                    break;
                default:
                    if (r < .3) SetState("idle", R(1.5, 4));
                    else if (r < .6) { if (!JumpToPlatform()) Hop(); }
                    else { dir = rnd.NextDouble() < .5 ? -1 : 1; SetState("walk", R(3, 6)); }
                    break;
            }
        }

        // 去找另一隻（讓串場有機會發生）
        bool VisitFriend()
        {
            Pet o = w.RandomOther(this);
            if (o == null || !o.Grounded() || o.state == "sleep") return false;
            double tx = o.Cx + (o.Cx > Cx ? -1 : 1) * SW * 1.1, foot = o.y + o.SH;
            if (o.supH == supH && Math.Abs(foot - (y + SH)) < 3)
            {
                seekX = tx; dir = tx > Cx ? 1 : -1; SetState("walk", Math.Min(8, Math.Abs(tx - Cx) / (P.Speed * k) + 0.3));
                return true;
            }
            if (Math.Abs(tx - Cx) > 1000 * k) return false;
            if (Is("hangyodon")) StartSwim(tx, foot, false);
            else if (Is("spidey") && rnd.NextDouble() < 0.5) { BallisticTo(tx, foot); Say("Thwip!", 0.8); }
            else { BallisticTo(tx, foot); if (Is("po")) Say(L("jump"), 0.8); }
            return true;
        }

        // 右鍵選單的招牌動作
        public void Signature()
        {
            if (!Out) return;
            if (P.Pik) { PikSignature(); return; }
            if (P.Orig) { OrigSignature(); return; }
            switch (P.Id)
            {
                case "spidey": if (!ShootTo("swing")) Say("這裡太低了，甩不起來", 1.6); break;
                case "po": if (!JumpToPlatform()) { Jump(dir * 200 * k, -520 * k); Say("咻～～", 1); } else Say("咻～～再來一次！", 1.4); break;
                case "stitch":
                    if (!Grounded()) break;
                    goClimb = true;
                    if (supH == IntPtr.Zero) { Rectangle wa = w.WA(Cx, y); dir = Cx < (wa.Left + wa.Right) / 2.0 ? -1 : 1; }
                    else dir = Cx - supL < supR - Cx ? -1 : 1;
                    SetState("walk", 30); Say("ih-ih-ih! 爬牆！", 1.4);
                    break;
                case "hangyodon":
                    {
                        // 招牌：披上紅披風飛！（英雄夢）
                        double[] o = PickPlatform(80 * k, 1100 * k);
                        double tx, ty;
                        if (o != null) { tx = o[0]; ty = o[1]; }
                        else
                        {
                            Rectangle wa = w.WA(Cx, y + SH / 2.0);
                            tx = Clamp(Cx + (rnd.NextDouble() < 0.5 ? -1 : 1) * R(280, 520) * k, wa.Left + SW, wa.Right - SW);
                            ty = y + SH;
                        }
                        StartSwim(tx, ty, true);
                        flyArc = Math.Max(flyArc, 150 * k);
                        Say(Pick(new string[] { "英雄漢頓，出發！", "看我的披風！咻～", "這次一定要帥帥地飛！" }), 1.8);
                    }
                    break;
                case "tinky": TinkyBag(null, false); break;
                case "dipsy": HatToss(false); break;
                case "laalaa": Juggle(); break;
            }
        }

        void ActSpecial(string a)
        {
            if (P.Pik && PikAct(a)) return;
            if (P.Orig && OrigAct(a)) return;
            switch (a)
            {
                case "swing": if (Is("spidey")) { if (!ShootTo("swing")) Say("這裡太低了，甩不起來", 1.6); } else Signature(); break;
                case "hang": if (Is("spidey")) { if (!ShootTo("hang")) Say("上面沒地方黏", 1.6); } break;
                case "climb":
                    if (Is("spidey") && Grounded()) { goClimb = true; Rectangle wa = w.WA(Cx, y); dir = Cx < (wa.Left + wa.Right) / 2.0 ? -1 : 1; SetState("walk", 30); }
                    else if (Is("stitch")) Signature();
                    break;
                case "ride": if (Grounded()) { dir = rnd.NextDouble() < .5 ? -1 : 1; SetState("walk", R(6, 10)); Say("騎車車兜風囉～嘟嘟！", 1.6); } break;
                case "bat": if (Grounded()) { StartBat(false); Say("揮棒！嘿！", 1.2); } break;
                case "uke": if (Grounded()) { SetState("elvis", 4); Say("♪ Aloha～", 1.6); } break;
                case "cape": Signature(); break;
                case "joke": if (Grounded()) { SetState("idle", 2.8); } Say(L("pats"), 2.4); jokeT = 2.6; break;
                case "bubble": SetState("idle", 1.6); for (int i = 0; i < 5; i++) Mark(5); Say("噗嚕噗嚕～", 1.2); break;
                // ---- 天線寶寶 ----
                case "bag": TinkyBag(null, false); break;
                case "dance":
                    if (Grounded()) { SetState("dance", 3.5); Say(Is("dipsy") ? "嘿～嘿～（帽子跟著晃）" : (Is("laalaa") ? "啦啦啦～跳舞！" : "丁丁跳舞～轉一圈～"), 1.8); }
                    break;
                case "plop": if (Grounded()) Plop("哎喲！"); break;
                case "hatwave": if (Grounded() && Is("dipsy") && !hatLost) { poseKind = "hatwave"; SetState("pose", 2.2); Say("Eh-oh!（揮帽子）", 1.8); } break;
                case "hattoss": HatToss(false); break;
                case "juggle": Juggle(); break;
                case "sing": if (Grounded()) { poseKind = "sing"; SetState("pose", 3.2); Say("啦啦啦～啦啦～♪", 2.6); } break;
                case "twirl": if (Grounded()) { SetState("twirl", 1.6); Say("轉圈圈～啦啦啦！", 1.6); } break;
            }
        }

        // 新視窗跳出來
        public void ReactNewWindow(WinInfo win)
        {
            if (!Grounded() || sleepMode || state == "hug" || InScene || fetching) return;
            if (P.Orig) { OrigNewWindow(win); return; }
            switch (P.Id)
            {
                case "spidey": if (!ZipToWindow(win, L("newwin"))) Say("有新視窗！👀", 1.5); break;
                default:
                    if (!GoToWindow(win, L("newwin"), Is("po") || Is("tinky") ? "wave" : (Is("hangyodon") ? "bubbles" : (Is("dipsy") ? "hattip" : (Is("laalaa") ? "twirl" : "sniff"))))) Say(L("newwin"), 1.5);
                    break;
            }
        }

        // 你切到哪個視窗，他常常跟過去
        public bool FollowWindow(WinInfo win, string text)
        {
            if (!Grounded() || sleepMode || state == "hug" || InScene || fetching) return false;
            if (Is("spidey")) return ZipToWindow(win, text);
            return GoToWindow(win, text, "");
        }

        bool GoToWindow(WinInfo win, string text, string after)
        {
            double tx, top;
            if (!PlatEnd(win, out tx, out top)) return false;
            if (supH == win.H) { Say(text, 2); if (after != "") { afterLand = after; LandAction(); } return true; }
            Say(text, 2);
            afterLand = after;
            if (Is("hangyodon")) StartSwim(tx, top, false);
            else BallisticTo(tx, top);
            return true;
        }

        bool PlatEnd(WinInfo win, out double tx, out double top)
        {
            tx = 0; top = 0;
            double bestD = double.MaxValue; bool found = false;
            foreach (Plat p in w.Plats)
            {
                if (p.H != win.H) continue;
                double[] ends = { p.Left + SW / 2.0 + 2, p.Right - SW / 2.0 - 2 };
                foreach (double e in ends) { double d = Math.Abs(e - Cx); if (d < bestD) { bestD = d; tx = e; top = p.Top; found = true; } }
            }
            return found && bestD < 1400 * k;
        }

        // ================= Spidey：噴絲 =================
        double[] FindAnchor(bool vertical)
        {
            double cx = Cx, hy = y;
            Rectangle wa = w.WA(cx, y + SH / 2.0);
            List<double[]> opts = new List<double[]>();
            foreach (WinInfo wi in w.Cands.Values)
            {
                if (wi.B > hy - 70 * k || wi.B < wa.Top + 10) continue;
                double px;
                if (vertical) { if (cx < wi.L + 6 || cx > wi.R - 6) continue; px = cx; }
                else
                {
                    px = Clamp(cx + dir * R(60, 220) * k, wi.L + 6, wi.R - 6);
                    if (Math.Abs(px - cx) > 300 * k) continue;
                }
                if (!w.PointVisible(wi, px, wi.B - 2)) continue;
                opts.Add(new double[] { px, wi.B });
            }
            if (opts.Count > 0 && rnd.NextDouble() < 0.85) return opts[rnd.Next(opts.Count)];
            double dist = hy - wa.Top;
            if (dist < 90 * k) return null;
            if (vertical) return new double[] { cx, wa.Top };
            return new double[] { Clamp(cx + dir * Math.Min(dist * 0.6, 260 * k), wa.Left + 10, wa.Right - 10), wa.Top };
        }

        bool ShootTo(string mode)
        {
            if (!Grounded()) return false;
            double[] a = FindAnchor(mode == "hang");
            if (a == null) return false;
            ax = a[0]; ay = a[1];
            dir = ax >= Cx ? 1 : -1;
            nextAct = mode; shootT = 0;
            SetState("shoot", 1);
            Say("Thwip!", 0.8);
            return true;
        }

        void Shoot(double dt)
        {
            shootT += dt;
            if (shootT < 0.18) return;
            supH = IntPtr.Zero;
            if (nextAct == "swing")
            {
                double hx = Cx, hy = y;
                Rectangle swa = w.WA(hx, y + SH / 2.0);
                double maxL = (swa.Bottom - SH) - ay - 24 * k;
                ropeL = Math.Min(Math.Sqrt((hx - ax) * (hx - ax) + (hy - ay) * (hy - ay)), maxL);
                if (ropeL < 36 * k) { Jump(dir * 60 * k, -300 * k); return; }
                th = Math.Asin(Clamp((hx - ax) / ropeL, -0.95, 0.95));
                if (Math.Abs(th) < 0.5) th = 0.9 * (hx < ax ? -1 : 1);
                om = 0;
                reelT = 0.18; reelX = x; reelY = y;
                SetState("swing", 3.2);
            }
            else if (nextAct == "hang")
            {
                Rectangle wa = w.WA(ax, y + SH / 2.0);
                targetL = Math.Max(10, Math.Min(wa.Height * R(0.15, 0.4), wa.Bottom - SH - 10 - ay));
                hangPhase = 0; ropeL = 0;
                SetState("hang", 99);
            }
            else SetState("zip", 3);
        }

        void Swing(double dt, Rectangle wa)
        {
            om = (om - (900 * k / ropeL) * Math.Sin(th) * dt) * 0.997;
            th += om * dt;
            double hx = ax + ropeL * Math.Sin(th), hy = ay + ropeL * Math.Cos(th), floorY = wa.Bottom - SH;
            x = hx - SW / 2.0; y = Math.Min(hy, floorY);
            if (reelT > 0)
            {
                double f = Ease(1 - reelT / 0.18);
                x = reelX + (x - reelX) * f; y = reelY + (y - reelY) * f;
                reelT -= dt;
            }
            double vxs = ropeL * Math.Cos(th) * om;
            if (Math.Abs(vxs) > 5) dir = vxs > 0 ? 1 : -1;
            if (t < 0 || hy > floorY + 1) { Jump(vxs * .8, -ropeL * Math.Sin(th) * om * .8); if (rnd.NextDouble() < .4) Say("呀呼～", 0.9); }
        }

        void Hang(double dt, Rectangle wa)
        {
            x = ax - SW / 2.0;
            if (hangPhase == 0)
            {
                y -= 700 * k * dt;
                if (y <= ay + 4) { y = ay + 4; hangPhase = 1; ropeL = 0; t = 5; Say("倒吊看世界～", 2); }
                return;
            }
            ropeL = Math.Min(targetL, ropeL + 160 * k * dt);
            y = ay + 4 + ropeL + Math.Sin(anim * 2.4) * 4 * k;
            if (t < 0) { Jump(0, 0); }
        }

        void Zip(double dt)
        {
            double tx = ax - SW / 2.0, ty = ay - SH;
            double dx = tx - x, dy = ty - y, d = Math.Sqrt(dx * dx + dy * dy), sp = 1100 * k * dt;
            if (dx != 0) dir = dx > 0 ? 1 : -1;
            if (d > sp && t > 0) { x += dx / d * sp; y += dy / d * sp; return; }
            x = tx; y = ty;
            foreach (Plat p in w.Plats)
                if (p.H == zipH && ax >= p.Left - 2 && ax <= p.Right + 2 && Math.Abs(p.Top - ay) < 3)
                {
                    SetSupport(p);
                    SetState("idle", 1.6);
                    w.AddWeb(zipH, zipRight);
                    Say("黏好了！", 1.4);
                    return;
                }
            Jump(0, 0);
        }

        void Peek(double dt, Rectangle wa)
        {
            double prev = gt;
            gt += dt;
            dir = -wallSide;
            double hideXp = wallSide < 0 ? wa.Left - SW * 0.55 : wa.Right - SW * 0.45;
            double inX = wallSide < 0 ? wa.Left : wa.Right - SW;
            x = gt < 0.4 ? inX + (hideXp - inX) * Ease(gt / 0.4) : hideXp;
            if (prev <= 0.4 && gt > 0.4) Say("躲貓貓～", 1.2);
            if (t < 0) { x = inX; Say("找到我了嗎？嘿嘿", 1.6); climbDir = 1; SetState("climb", 99); }
        }

        bool ZipToWindow(WinInfo win, string text)
        {
            if (!Grounded() || sleepMode || state == "hug" || fetching) return false;
            double tx, top;
            if (!PlatEnd(win, out tx, out top)) return false;
            if (supH == win.H) { Say(text, 2); return true; }
            ax = tx; ay = top; zipH = win.H; zipRight = tx > (win.L + win.R) / 2.0;
            dir = ax >= Cx ? 1 : -1;
            nextAct = "zip"; shootT = 0;
            SetState("shoot", 1);
            Say(text, 2);
            return true;
        }

        void StartClimb(int side)
        {
            wallSide = side; climbDir = -1; dir = side; goClimb = false; supH = IntPtr.Zero;
            SetState("climb", R(2, 7));
        }

        void Climb(double dt, Rectangle wa)
        {
            x = wallSide < 0 ? wa.Left : wa.Right - SW;
            if (climbDir < 0)
            {
                y -= 50 * k * dt;
                if (y <= wa.Top + 4 || t < 0)
                {
                    y = Math.Max(y, wa.Top + 4);
                    if (InScene) { t = 1; return; }
                    double cr = rnd.NextDouble();
                    if (cr < 0.45) { Jump(-wallSide * R(200, 350) * k, -R(150, 300) * k); Say("喝！", 0.8); }
                    else if (cr < 0.75) { gt = 0; SetState("peek", R(2.5, 4)); }
                    else climbDir = 1;
                }
            }
            else
            {
                y += 70 * k * dt;
                if (y >= wa.Bottom - SH) { y = wa.Bottom - SH; dir = -wallSide; SetState("walk", R(2, 5)); }
            }
        }

        void SpinWeb(IntPtr h, bool right)
        {
            WinInfo wi;
            if (!w.Cands.TryGetValue(h, out wi)) return;
            double edge = right ? supR : supL, corner = right ? wi.R : wi.L;
            if (Math.Abs(edge - corner) > 12) return;
            w.AddWeb(h, right);
            SetState("idle", 1.4);
            Say("在這裡織個網～", 1.6);
        }

        // 多人接球：用絲把球黏住再踢回去
        void WebCatch()
        {
            w.HoldBall(this);
            ax = w.Bx; ay = w.By; shootT = 1;
            dir = ax >= Cx ? 1 : -1;
            SetState("webcatch", 0.6);
            Say(Pick(new string[] { "Thwip! 接住了！", "用絲接球！", "好球！Thwip!" }), 1.4);
            w.Umpire("好球！");
        }

        // 串場：把小波甩上去
        public void SlingAt(Pet o)
        {
            ax = o.Cx; ay = o.y + 6 * k; shootT = 1; dir = ax >= Cx ? 1 : -1;
            SetState("sling", 1.0);
        }

        // ================= 小波：滑板車、棒球 =================
        bool OnScooter()
        {
            if (!Is("po") || scooterLost) return false;
            if (state == "fling") return !rolling;
            return state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto" || (state == "air" && !rolling) || state == "stowfly" || state == "idle" && t > 0 && (anim % 7) > 3.5;
        }

        void StartBat(bool hitBall)
        {
            batT = 0; batHit = !hitBall;
            SetState("bat", 1.1);
        }

        void Bat(double dt)
        {
            double prev = batT;
            batT += dt;
            if (!batHit && prev < 0.22 && batT >= 0.22 && w.Holder == this)
            {
                batHit = true;
                bool homer = rnd.NextDouble() < 0.45;
                w.ReleaseBall(Cx + dir * 14 * k, y + 8 * k, dir * (homer ? R(1300, 1700) : R(650, 950)) * k, -(homer ? R(950, 1200) : R(450, 650)) * k);
                w.CatchCd = 1.2;
                Burst(8);
                if (homer)
                {
                    Say("全壘打！", 2.2);
                    w.Fireworks(w.WA(Cx, y), 3, (int)(Cx + dir * 260 * k));
                    w.Umpire("全壘打！");
                    AddXp(1);
                }
                else { Say(Pick(new string[] { "安打！", "打到了！再來一次！" }), 1.6); w.Umpire("好球！"); }
            }
            if (t < 0) SetState("idle", 1);
        }

        void PoBall()
        {
            bool group = w.OutCount() > 1;
            w.HoldBall(this);
            if (rnd.NextDouble() < (group ? 0.6 : 0.3)) { StartBat(true); Say("看我的！", 0.8); return; }
            SetState("catch", 0.6);
            Say(L("ball_catch"), 1.8);
            w.Umpire("好球！");
        }

        // 全壘打慶祝（Codex／Claude 做完、上版）
        void HomeRun(string line, bool lead)
        {
            if (Grounded()) { poseKind = "homerun"; SetState("pose", 3.4); }
            if (lead) w.Fireworks(w.WA(Cx, y), 6, (int)Cx);
            Say(line, 4); Burst(12);
        }

        // ================= 史迪仔：爬牆、天花板、咬球 =================
        void StartWallUp(int side)
        {
            wallSide = side; climbDir = -1; dir = side; goClimb = false; supH = IntPtr.Zero; crawlH = IntPtr.Zero;
            SetState("wall", 99);
        }

        void StartWallDown(WinInfo wi, bool right)
        {
            crawlH = wi.H; wallSide = right ? -1 : 1; climbDir = 1; goClimb = false; supH = IntPtr.Zero;
            x = right ? wi.R : wi.L - SW;
            ceilY = wi.B; ceilL = wi.L; ceilR = wi.R - SW;
            SetState("wall", 99);
            Say("ih-ih! 爬下去～", 1.2);
        }

        void Wall(double dt, Rectangle wa)
        {
            if (crawlH == IntPtr.Zero)
            {
                // 螢幕邊：往上爬到頂，然後倒掛在天花板上走
                x = wallSide < 0 ? wa.Left : wa.Right - SW;
                y -= 130 * k * dt;
                if (y <= wa.Top + 2)
                {
                    y = wa.Top; ceilY = wa.Top; ceilL = wa.Left; ceilR = wa.Right - SW;
                    dir = -wallSide; SetState("ceil", R(1.5, 3.5)); Say("倒立走路！嘻嘻嘻", 1.4);
                }
                return;
            }
            // 視窗側邊：往下爬到視窗底，然後倒掛在視窗底下走
            W.RECT r;
            if (!W.IsWindowVisible(crawlH) || !W.Rect(crawlH, out r)) { Jump(0, 0); rolling = true; return; }
            x = wallSide < 0 ? r.R : r.L - SW;
            ceilY = r.B; ceilL = r.L; ceilR = r.R - SW;
            y += 120 * k * dt;
            if (y >= ceilY - SH * 0.3)
            {
                y = ceilY; x = wallSide < 0 ? ceilR : ceilL;
                dir = wallSide < 0 ? -1 : 1; SetState("ceil", R(1.5, 3));
            }
        }

        void Ceil(double dt)
        {
            if (crawlH != IntPtr.Zero)
            {
                W.RECT r;
                if (!W.IsWindowVisible(crawlH) || !W.Rect(crawlH, out r)) { Jump(0, 0); rolling = true; return; }
                ceilY = r.B; ceilL = r.L; ceilR = r.R - SW;
            }
            y = ceilY;
            x += dir * 110 * k * dt;
            if (x < ceilL) { x = ceilL; dir = 1; }
            if (x > ceilR) { x = ceilR; dir = -1; }
            if (t < 0) { crawlH = IntPtr.Zero; Jump(0, 60 * k); rolling = true; Say(Pick(new string[] { "跳！嗚哇～", "ih-ih-ih!", "放手！嘻嘻嘻" }), 1); }
        }

        void Curl(double dt)
        {
            x += vx * dt; vx *= Math.Pow(0.25, dt);
            rolling = true;
            double nx = x;
            if (!w.Inside(nx, y + SH / 2.0) || !w.Inside(nx + SW, y + SH / 2.0)) { vx = -vx; }
            if (supH != IntPtr.Zero && (Cx < supL || Cx > supR)) { Jump(vx, -60 * k); return; }
            if (t < 0) { rolling = false; SetState("idle", 1); if (rnd.NextDouble() < 0.5) Say("嘻嘻嘻～", 1); }
        }

        void StitchBall()
        {
            bool group = w.OutCount() > 1;
            w.HoldBall(this);
            if (rnd.NextDouble() < (group ? 0.7 : 0.35))
            {
                SetState("chomp", group ? R(2, 3) : 1.2);
                Say(group ? "嘻嘻嘻！球是史迪仔的！" : Pick(new string[] { "（咬）嘻嘻嘻", "ih-ih! 史迪仔的！", "（咬咬）好吃" }), 1.8);
                if (group) w.Umpire("出局！…吧？");
                return;
            }
            SetState("catch", 0.5);
            Say(L("ball_catch"), 1.6);
            w.Umpire("好球！");
        }

        void Chomp(double dt)
        {
            if (w.OutCount() > 1)
            {
                // 叼著球逃跑
                Pet o = w.Nearest(this);
                if (o != null) dir = o.Cx > Cx ? -1 : 1;
                if (MoveOnGround(dt, 160 * k)) { return; }
            }
            if (t < 0)
            {
                if (w.Holder == this) { w.ReleaseBall(Cx + dir * 6 * k, y + 8 * k, 0, 0); KickBallToCursor(0.8); }
                Say(Pick(new string[] { "噗！還你～", "呸！嘻嘻嘻" }), 1.2);
                SetState("idle", 1);
            }
        }

        // ================= 人魚漢頓：在空中「游泳」（波浪路線＋泡泡）、披風飛行、頂球 =================
        bool caped;
        public void StartSwim(double tx, double footY, bool cape)
        {
            fx0 = x; fy0 = y; fx1 = tx - SW / 2.0; fy1 = footY - SH;
            double d = Math.Sqrt((fx1 - fx0) * (fx1 - fx0) + (fy1 - fy0) * (fy1 - fy0));
            flyDur = Clamp(d / ((cape ? 520 : 300) * k), 0.9, 4);
            flyArc = 30 * k + Math.Min(140 * k, d * 0.18);
            flyT = 0; supH = IntPtr.Zero; caped = cape;
            dir = fx1 >= fx0 ? 1 : -1;
            SetState("swim", 99);
        }

        void Swim(double dt)
        {
            flyT += dt;
            double f = Math.Min(1, flyT / flyDur), e = Ease(f);
            x = fx0 + (fx1 - fx0) * e;
            y = fy0 + (fy1 - fy0) * e - Math.Sin(Math.PI * f) * flyArc + (caped ? 0 : Math.Sin(flyT * 7) * 9 * k * Math.Sin(Math.PI * f));
            if (rnd.NextDouble() < dt * (caped ? 4 : 9)) Mark(5);
            if (f < 1) return;
            x = fx1; y = fy1;
            supH = IntPtr.Zero;
            foreach (Plat p in w.Plats) if (Cx >= p.Left && Cx <= p.Right && Math.Abs(p.Top - (y + SH)) < 3) { SetSupport(p); break; }
            if (supH == IntPtr.Zero)
            {
                Rectangle wa = w.WA(Cx, y + SH / 2.0);
                if (Math.Abs(wa.Bottom - (y + SH)) > 3) { caped = false; Jump(0, 0); return; }
            }
            bool wasCape = caped; caped = false;
            if (afterLand != "") LandAction();
            else if (wasCape) { poseKind = "hero"; SetState("pose", 1.4); Say(Pick(new string[] { "（落地）帥嗎？帥嗎？", "英雄著陸！…有點晃" }), 1.6); }
            else SetState("idle", 1.2);
        }

        // 像海豹一樣用頭頂球；偶爾連頂幾下
        int headers;
        void HangyodonBall()
        {
            SetState("header", 0.45);
            w.By = y - 2 * k; w.Bx = Cx;
            headers++;
            if (headers < 3 && rnd.NextDouble() < 0.45)
            {
                w.Bvx = R(-60, 60) * k; w.Bvy = -R(520, 620) * k; w.CatchCd = 0.5;
                fetching = true;
                Say(Pick(new string[] { "嘿咻！", "頂！頂！", "海豹式～" }), 0.9);
                return;
            }
            headers = 0;
            Point c = Cursor.Position;
            w.Bvx = Clamp((c.X - w.Bx) * 0.9, -800 * k, 800 * k); w.Bvy = -R(600, 760) * k; w.CatchCd = 1.0; w.BallIdle = 0;
            Say(L("ball_catch"), 1.6);
            w.Umpire("好球！");
        }

        // 裁判喊聲（多人打棒球時由人魚漢頓喊）
        public void Call(string s)
        {
            if (!Out || InScene) return;
            Say(s, 1.6);
            if (Grounded() && state != "header") { poseKind = Is("dipsy") ? "hattip" : "hero"; SetState("pose", 0.9); }
        }

        // 串場用：直接設狀態／姿勢
        public void ScenePose(string kind, double dur)
        {
            if (!Grounded() && kind != "fly") return;
            switch (kind)
            {
                case "hero": poseKind = "hero"; SetState("pose", dur); Burst(6); break;
                case "photo": poseKind = "photo"; SetState("pose", dur); break;
                case "grin": poseKind = "grin"; SetState("pose", dur); break;
                case "silly": poseKind = "silly"; SetState("pose", dur); break;
                case "cape": poseKind = "hero"; SetState("pose", dur); for (int i = 0; i < 3; i++) Mark(5); break;
                case "wave": SetState("wave", dur); break;
                case "hug": SetState("hug", dur); AddHeart(); AddHeart(); break;
                case "elvis": SetState("elvis", dur); break;
                case "hop": Jump(0, -260 * k); break;
                case "idle": SetState("idle", dur); break;
                case "dizzy": SetState("dizzy", dur); break;
                case "lick": poseKind = "lick"; SetState("pose", dur); break;
                // ---- 天線寶寶 ----
                case "plop": SetState("plop", dur); sT = 0; Burst(4); Mark(4); break;
                case "hattip": case "hatwave": case "hatdown": case "sing": poseKind = kind; SetState("pose", dur); break;
                case "twirl": case "dance": case "kick": case "catch": case "spin": SetState(kind, dur); break;
                case "juggle": juggles = 0; sT = 0; SetState("juggle", dur); break;
                case "hattoss": sT = 0; SetState("hattoss", dur); break;
                case "bat": StartBat(false); break;
                default: if (kind.StartsWith("bag")) TinkyBag(kind.Length > 4 ? kind.Substring(4) : "", true, dur); break;
            }
        }
        public void FaceTo(Pet o) { dir = o.Cx > Cx ? 1 : -1; }
        public void WalkTo(double tx, double dur) { seekX = tx; dir = tx > Cx ? 1 : -1; gotoSpeed = 1.5; SetState("goto", Math.Max(dur, 8)); }
        public void RaceTo(double tx) { seekX = tx; dir = tx > Cx ? 1 : -1; gotoSpeed = Is("po") || Is("stitch") ? 1.4 : 1.1; SetState("goto", 10); }
        // 走到／跳到另一隻旁邊（串場前先湊在一起）；回傳大概要幾秒
        public double ComeNear(Pet o)
        {
            double tx = o.Cx + (Cx > o.Cx ? 1 : -1) * o.SW * (P.Tubby || o.P.Tubby ? 2.0 : (P.Orig ? 1.6 : 1.35));   // 天線寶寶比較寬（16 格＋道具）
            Rectangle wa = w.WA(o.Cx, o.Foot - 4);
            tx = Clamp(tx, wa.Left + SW, wa.Right - SW);
            if (supH == o.supH && Math.Abs(Foot - o.Foot) < 3)
            {
                double d = Math.Abs(tx - Cx);
                if (d < SW * 0.6) return 0;
                if (d < 700 * k) { WalkTo(tx, 10); return Math.Min(6, d / (Math.Max(P.Speed, 60) * k * 1.5) + 0.3); }
            }
            if (Is("hangyodon")) { StartSwim(tx, o.Foot, false); return flyDur + 0.4; }
            BallisticTo(tx, o.Foot); return 1.6;
        }
        public void JumpTo(double tx, double footY) { BallisticTo(tx, footY); }
        public void LoseScooter(bool lost) { scooterLost = lost; }
        public void ClimbRace(int side) { if (Is("spidey")) StartClimb(side); else if (Is("stitch")) StartWallUp(side); }
        public double Foot { get { return y + SH; } }
        public bool OnFloor { get { return supH == IntPtr.Zero; } }
    }

    // ================= 天線寶寶：丁丁（魔法袋）、迪西（乳牛紋帽子）、拉拉（大橘球）=================
    partial class Pet
    {
        bool hatLost;                   // 迪西：帽子借給丁丁戴了（串場）
        public bool WearHat;            // 戴著迪西的帽子（串場）
        bool ballLost;                  // 拉拉：球不見了（滾進丁丁的魔法袋、踢給小波）
        public bool RidingPo;           // 丁丁騎小波的滑板車（串場）
        public bool HoldToast;          // 吐司時間：手上拿著吐司（串場）
        bool lentScooter;               // 小波：滑板車借出去了（串場結束一定還回來）
        string bagItem = "";            // 魔法袋這次拿出來的東西
        double sT, lastLandVy;          // 專屬動作計時、落地前的速度
        int juggles;
        bool lastArmsUp;
        bool HasTv { get { return Is("po") || P.Tubby; } }

        static readonly string[] TOAST = { ".2222.", "211112", "2k11k2", "211112", "21kk12", ".2222." };
        static readonly string[] STAR5 = { "..y..", ".yyy.", "yyyyy", ".yyy.", ".y.y." };

        // 串場要用的小開關
        public void LendHat(bool lent) { hatLost = lent; }
        public void LoseBall(bool lost) { ballLost = lost; }
        public void LendScooter(bool lent) { lentScooter = lent; LoseScooter(lent); }
        public void ResetSceneProps()
        {
            if (lentScooter) { lentScooter = false; LoseScooter(false); }
            hatLost = false; WearHat = false; ballLost = false; RidingPo = false; HoldToast = false;
            if (state == "bagdig") bagItem = "";
        }
        // 頭頂（帽子中間）的螢幕座標：串場丟帽子、丟球用
        public PointF HatPoint() { return new PointF((float)Cx, (float)(Foot - SH + (P.HeadTop - 3) * S)); }
        public PointF HandPoint() { return new PointF((float)(Cx + dir * 5 * S), (float)(Foot - SH + (P.BodyTop + 2) * S)); }
        public PointF FootPoint() { return new PointF((float)(Cx + dir * 4 * S), (float)(Foot - 3 * S)); }
        public PointF BagPoint() { return new PointF((float)(Cx + dir * 9 * S), (float)(Foot - SH + (P.BodyTop + 3) * S)); }   // 打開的袋口（提在身體旁邊）
        public void ClearCrumbs() { notes.RemoveAll(delegate(double[] n) { return n[2] == 7; }); }

        bool HatOnHead() { return Is("dipsy") && !hatLost && state != "hattoss" && !(state == "pose" && poseKind == "hatwave"); }

        // 丁丁：跌坐在地上「哎喲！」（小波在大家一起跌倒的串場也會）
        public void Plop(string text)
        {
            SetState("plop", 1.5); sT = 0;
            Burst(4); Mark(4);
            if (text != null) Say(text, 1.4);
        }

        // 丁丁的魔法袋：打開、翻一翻、拿出東西（catch＝剛接住的球）
        bool bagQuiet;
        void TinkyBag(string item, bool quiet) { TinkyBag(item, quiet, 2.4); }
        void TinkyBag(string item, bool quiet, double dur)
        {
            if (!Is("tinky") || !Grounded()) return;
            if (item == null)
            {
                string[] items = { "toast", "heart", "star", "toast", "ball" };
                item = items[rnd.Next(items.Length)];
                if (item == "ball" && (w.Get("laalaa") == null || !w.Get("laalaa").Out)) item = "heart";
            }
            bagItem = item; bagQuiet = quiet; sT = 0;
            SetState("bagdig", Math.Max(1.4, dur));
            if (!quiet) Say(Pick(new string[] { "魔法袋裡有什麼呢？", "丁丁找一找…", "（翻翻袋子）嗯…" }), 1.2);
        }

        void BagReveal()
        {
            switch (bagItem)
            {
                case "catch":
                    if (w.Holder == this) { w.ReleaseBall(Cx + dir * 8 * k, y + 6 * k, 0, 0); KickBallToCursor(0.9); }
                    if (!bagQuiet) Say(Pick(new string[] { "找到了！還你～", "從魔法袋拿出來囉！" }), 1.6);
                    break;
                case "toast": if (!bagQuiet) Say(Pick(new string[] { "是吐司！", "吐司！要吃嗎？" }), 1.6); break;
                case "heart": AddHeart(); AddHeart(); if (!bagQuiet) Say("是愛心！送給你 ♥", 1.8); break;
                case "star": Burst(10); if (!bagQuiet) Say("是星星！✨", 1.6); break;
                case "ball": if (!bagQuiet) Say("咦？拉拉的球怎麼在這裡？", 2); break;
            }
        }

        // 迪西：帽子丟上去轉一圈、接回頭上
        void HatToss(bool quiet)
        {
            if (!Is("dipsy") || !Grounded() || hatLost) return;
            sT = 0; SetState("hattoss", 1.6);
            if (!quiet) Say(Pick(new string[] { "看我的帽子！", "帽子戲法！", "嘿～" }), 1.2);
        }

        // 拉拉：顛球（球在腳和頭頂之間跳）
        void Juggle()
        {
            if (!Is("laalaa") || !Grounded() || ballLost) return;
            juggles = 0; sT = 0;
            SetState("juggle", R(2.6, 3.6));
            Say(Pick(new string[] { "看我的球！啦～", "顛球！1、2、3～", "球球跳跳～" }), 1.2);
        }
        double JugglePhase() { return (sT * 1.5) % 1; }

        bool TubbyStep(double dt)
        {
            if (state == "pose" && poseKind == "sing" && rnd.NextDouble() < dt * 3) Mark(0);
            if (state == "dance" && Is("laalaa") && rnd.NextDouble() < dt * 2) Mark(0);
            switch (state)
            {
                case "twirl":
                    sT += dt;
                    if (Math.Floor(anim * 9) != Math.Floor((anim - dt) * 9)) dir = -dir;
                    if (rnd.NextDouble() < dt * 3) Mark(0);
                    if (t < 0) { SetState("idle", InScene ? 30 : 1); if (!InScene && Is("laalaa") && rnd.NextDouble() < 0.5) Say("啦啦啦～", 1.2); }
                    return true;
                case "hattoss":
                    {
                        double prev = sT; sT += dt;
                        if (prev < 1.25 && sT >= 1.25) { Burst(6); if (!InScene) Say(Pick(new string[] { "帥！", "接到了。酷。", "嘿～" }), 1.4); }
                        if (t < 0) SetState("idle", InScene ? 30 : 1);
                    }
                    return true;
                case "juggle":
                    {
                        double prev = JugglePhase(); sT += dt;
                        if (JugglePhase() < prev) { juggles++; Mark(0); if (!InScene) Say(juggles + "！", 0.6); }
                        if (t < 0) { SetState("idle", InScene ? 30 : 1); if (!InScene) Say(juggles >= 3 ? "啦～！" + juggles + " 下！" : "再來一次！", 1.4); }
                    }
                    return true;
                case "bagdig":
                    {
                        double prev = sT; sT += dt;
                        if (prev < 0.9 && sT >= 0.9) BagReveal();
                        if (t < 0) { if (bagItem == "catch" && w.Holder == this) BagReveal(); bagItem = ""; SetState("idle", InScene ? 30 : 1); }
                    }
                    return true;
            }
            return false;
        }

        // ---------- 球（大家的球；小波在的話是棒球）----------
        void TinkyBall()
        {
            w.HoldBall(this);
            TinkyBag("catch", true, 1.8);
            if (state != "bagdig") { w.ReleaseBall(Cx, y, 0, 0); KickBallToCursor(0.9); }   // 在空中接到：直接丟回去
            Say(L("ball_catch"), 1.6);
            w.Umpire("好球！");
        }

        // 迪西：用帽子頂球（偶爾連頂幾下）
        void DipsyBall()
        {
            SetState("header", 0.45);
            w.By = y + SH - 16 * S + (P.HeadTop - 7) * S; w.Bx = Cx;
            headers++;
            if (headers < 3 && rnd.NextDouble() < 0.4)
            {
                w.Bvx = R(-60, 60) * k; w.Bvy = -R(520, 620) * k; w.CatchCd = 0.5;
                fetching = true;
                Say(Pick(new string[] { "帽子頂！", "嘿！再一下", "酷～" }), 0.9);
                return;
            }
            headers = 0;
            Point c = Cursor.Position;
            w.Bvx = Clamp((c.X - w.Bx) * 0.9, -800 * k, 800 * k); w.Bvy = -R(600, 760) * k; w.CatchCd = 1.0; w.BallIdle = 0;
            Say(L("ball_catch"), 1.6);
        }

        // 拉拉：用腳踢（偶爾先顛幾下）
        void LaaLaaBall()
        {
            SetState("kick", 0.45);
            w.By = y + SH - w.BallR() - 2 * k; w.Bx = Cx + dir * 4 * k;
            headers++;
            if (headers < 3 && rnd.NextDouble() < 0.45)
            {
                w.Bvx = R(-40, 40) * k; w.Bvy = -R(480, 600) * k; w.CatchCd = 0.5;
                fetching = true;
                Say(Pick(new string[] { "1、2…", "啦～顛球！", "嘿咻！" }), 0.9);
                return;
            }
            headers = 0;
            Point c = Cursor.Position;
            w.Bvx = Clamp((c.X - w.Bx) * 1.1, -950 * k, 950 * k); w.Bvy = -R(500, 700) * k; w.CatchCd = 1.0; w.BallIdle = 0;
            Say(L("ball_catch"), 1.6);
            w.Umpire("好球！");
        }

        // ---------- 畫 ----------
        Fr FrameTubby()
        {
            bool hug = state == "hug", sleep = state == "sleep", plop = state == "plop";
            bool nightIdle = Night && state == "idle" && !InScene && !HoldingFood();
            bool sit = sleep || plop || (Is("laalaa") && nightIdle);
            bool yawn = Night && state == "idle" && (anim % 6) < 1.4;
            string face;
            if (plop) face = sT < 0.55 ? "OUCH" : "HAPPY";
            else if (sleep || yawn || (Is("dipsy") && nightIdle) || (state == "pose" && poseKind == "hatdown")) face = "SLEEPY";
            else if (hug || state == "twirl" || state == "juggle" || (state == "dance" && Step2(2)) || (state == "bagdig" && sT > 0.9)
                || (state == "pose" && (poseKind == "photo" || poseKind == "sing" || poseKind == "hatwave"))) face = "HAPPY";
            else if (state == "dizzy") face = "DIZZY";
            else if (state == "glass") face = "SQUISH";
            else face = null;
            bool armsUp = state == "glass" || state == "catch" || state == "drag" || state == "air" || state == "fling" || state == "kick" || state == "header" || (state == "throw" && t > 0.15)
                || (state == "wave" && Step2(4)) || (state == "dance" && Step2(4)) || state == "twirl" || (state == "hattoss" && (sT < 0.3 || (sT > 1.1 && sT < 1.5)))
                || (state == "pose" && (poseKind == "photo" || poseKind == "hatwave" || poseKind == "hattip" || (poseKind == "sing" && Step2(3))))
                || (state == "bagdig" && sT > 0.9 && sT < 1.7);
            if (RidingPo) armsUp = state == "air" || state == "drag";
            lastArmsUp = armsUp;
            string bodyName = hug || (nightIdle && !Is("dipsy")) ? "ARMS_HUG" : (armsUp ? "ARMS_UP" : "BODY");
            string legs;
            bool ride = RidingPo && !rolling;
            if (ride) legs = "LEGS_RIDE";
            else if (sit) legs = "LEGS_SIT";
            else
            {
                bool moving = state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto";
                bool step = (moving && Step2(Is("tinky") ? 5 : (Is("laalaa") ? 9 : 7))) || (state == "dance" && Step2(4))
                    || (state == "juggle" && JugglePhase() < 0.2) || (state == "kick" && t > 0.15);
                legs = step ? "LEGS_B" : "LEGS_A";
            }
            Fr f = F(Pal.Stack(HeadRows(face), A(bodyName), A(legs)));
            if (ride) { f.Top = -4; f.AccDy = -4; }
            else if (sit) f.AccDy = A("LEGS_A").Length - A("LEGS_SIT").Length;
            f.Tummy = !hug;
            if (rolling) { f.Rot = (int)Math.Floor(anim * 14) % 4; f.Acc = false; f.Tummy = false; }
            return f;
        }

        double TubbyBob()
        {
            if (state == "dance" || state == "elvis") return Math.Abs(Math.Sin(anim * (Is("dipsy") ? 6 : 8))) * 6 * k;
            bool moving = state == "walk" || state == "goto" || state == "seek" || state == "fetch";
            if (moving && !RidingPo)
            {
                if (Is("laalaa")) return Math.Abs(Math.Sin(anim * 7)) * 5 * k;      // 蹦蹦跳跳
                if (Is("dipsy")) return Math.Abs(Math.Sin(anim * 5)) * 2.5 * k;     // 跟著節奏
            }
            if (Is("dipsy") && state == "idle" && !Night) return (Math.Floor(anim * 2) % 2) * k;   // 點頭打拍子
            return 0;
        }

        // 拉拉的球現在在哪裡：none／floor（腳邊）／dribble（往前帶）／juggle／hold（抱著）／raised（舉高高）
        string BallSpot(Fr f)
        {
            if (!Is("laalaa") || ballLost || w.BallOn || f.Rot != 0 || f.Fy) return "none";
            if (w.Lunch && HoldingFood() && state != "sleep") return "none";
            if (state == "juggle") return "juggle";
            if (state == "pose" && poseKind == "photo") return "raised";
            if (Night && state == "idle" && !InScene) return "hold";
            if (state == "air" || state == "fling" || state == "drag" || state == "stowfly") return "hold";
            if (state == "walk" || state == "goto" || state == "seek" || state == "hide") return "dribble";
            return "floor";
        }

        // 丁丁的袋子在哪裡：floor（放地上）／hand（提著）／up（舉起來）／hug（抱著）／open（打開翻找）
        string BagSpot(Fr f)
        {
            if (!Is("tinky") || f.Rot != 0 || f.Fy) return "none";
            if (state == "bagdig") return "open";
            if (state == "hug" || state == "sleep" || state == "plop" || RidingPo || HoldToast || (w.Lunch && HoldingFood())) return "floor";
            if (Night && state == "idle" && !InScene) return "hug";
            return lastArmsUp ? "up" : "hand";
        }

        void DrawTubbyBehind(Graphics g, Fr f, int bx, int by, int ps, bool fx)
        {
            if (RidingPo && !rolling)
            {
                Pal po = Pal.Get("po");
                if (po != null) DrawPixPal(g, po, po.Art["SCOOTER"], bx + (fx ? 12 - (-1) - 14 : -1) * ps, by + 7 * ps, ps, fx);
            }
            if (BagSpot(f) == "floor") DrawAt(g, A("BAG"), HoldToast || w.Lunch ? -8.5 : 12.5, 9, bx, by, ps, fx, false, true);   // 手上拿吃的：袋子放另一邊
            if (BallSpot(f) == "floor") DrawAt(g, A("BALL"), 12, 9, bx, by, ps, fx, false, true);
        }

        void DrawTubbyFront(Graphics g, Fr f, int bx, int by, int ps, bool fx)
        {
            if (f.Rot != 0 || f.Fy) return;
            int dy = f.AccDy;
            // 迪西的帽子
            if (Is("dipsy") && !hatLost)
            {
                string[] hat = A("HAT");
                double row = P.HeadTop - 6 + dy, col = -2;
                if (state == "hattoss" && sT < 1.25)
                {
                    double ff = Clamp(sT / 1.25, 0, 1);
                    row -= Math.Sin(Math.PI * ff) * 11;
                    bool side = Math.Floor(sT * 10) % 2 == 1;                       // 轉呀轉：正面、側面輪流
                    DrawAt(g, side ? A("HAT_HAND") : hat, side ? 2 : col, row, bx, by, ps, fx ^ (Math.Floor(sT * 5) % 2 == 1), false, true);
                }
                else if (state == "pose" && poseKind == "hatwave")
                    DrawAt(g, A("HAT_HAND"), 11 + (Step2(4) ? 1 : 0), P.BodyTop - 8 + dy, bx, by, ps, fx, false, true);
                else
                {
                    if (state == "pose" && poseKind == "hattip") { row -= 2; col += 1; }
                    else if (state == "header") row -= 1;
                    else if ((state == "pose" && poseKind == "hatdown") || state == "sleep" || (Night && state == "idle" && !InScene)) row += 3;   // 帽子拉低蓋住眼睛
                    DrawAt(g, hat, col, row, bx, by, ps, fx, false, true);
                }
            }
            // 借戴迪西的帽子（串場）
            if (WearHat) DrawAt(g, A("HAT"), -2, P.HeadTop - 6 + dy, bx, by, ps, fx, false, true);
            // 丁丁的魔法袋
            switch (BagSpot(f))
            {
                case "hand": DrawAt(g, A("BAG"), 12 + (state == "walk" && Step2(5) ? 0.5 : 0), P.BodyTop + 1 + dy, bx, by, ps, fx, false, true); break;
                case "up": DrawAt(g, A("BAG"), 12.5, P.BodyTop - 5 + dy, bx, by, ps, fx, false, true); break;
                case "hug": DrawAt(g, A("BAG"), 2, P.BodyTop + 2 + dy, bx, by, ps, fx, false, true); break;
                case "open":
                    {
                        // 袋子打開提在身體旁邊，東西從袋口冒出來（不擋到臉）
                        double bagRow = P.BodyTop + 2 + dy;
                        string[] item = BagItemArt();
                        if (item != null && sT > 0.9)
                        {
                            double rise = Clamp((sT - 0.9) / 0.35, 0, 1) * (item.Length + 2);
                            if (!(bagItem == "catch" && w.Holder != this && sT > 1.3))
                                DrawAt(g, item, 15 - item[0].Length / 2.0, bagRow + 2 - rise, bx, by, ps, fx, false, true);
                        }
                        DrawAt(g, A("BAG_OPEN"), 11, bagRow, bx, by, ps, fx, false, true);
                    }
                    break;
            }
            // 拉拉的球
            string[] ball = A("BALL");
            switch (BallSpot(f))
            {
                case "juggle":
                    {
                        double h = Math.Sin(Math.PI * JugglePhase()) * 12;
                        DrawAt(g, ball, 10, 9 - h, bx, by, ps, fx, false, true);   // 在身體前側顛，不擋臉
                    }
                    break;
                case "dribble": DrawAt(g, ball, 11.5, 9 - Math.Abs(Math.Sin(anim * 8)) * 2, bx, by, ps, fx, false, true); break;
                case "hold": DrawAt(g, ball, 2, P.BodyTop + 2 + dy, bx, by, ps, fx, false, true); break;
                case "raised": DrawAt(g, ball, 2, P.HeadTop - 8 + dy, bx, by, ps, fx, false, true); break;
            }
        }

        string[] BagItemArt()
        {
            switch (bagItem)
            {
                case "toast": return TOAST;
                case "heart": return HEART;
                case "star": return STAR5;
                case "ball": return A("BALL");
                case "catch": return w.BallKind == "baseball" ? BALLART : (w.BallKind == "tubby" ? A("BALL") : TBALL);
            }
            return null;
        }

        // ---------- 櫃子裡：丁丁翻魔法袋、迪西抬帽子打拍子、拉拉拍球；晚上抱著自己的東西睡 ----------
        void DrawTubbyShelf(Graphics g, string[] head, int fx, int bx, int by, int ps, bool flip, double tt, bool blink)
        {
            string body = "BODY", legs = "LEGS_A";
            bool normalFace = true, sit = false;
            int groove = 0;
            if (Is("tinky"))
            {
                if (Night) { body = "ARMS_HUG"; if ((tt % 5) < 3) { ReplaceFace(head, "SLEEPY"); normalFace = false; } }
                else if ((tt % 8) < 2.4 && !w.Lunch && (tt % 8) > 0.9) { ReplaceFace(head, "HAPPY"); normalFace = false; }
                else if (blink) { ReplaceFace(head, "SLEEPY"); normalFace = false; }
            }
            else if (Is("dipsy"))
            {
                if (Night) { ReplaceFace(head, "SLEEPY"); normalFace = false; }
                else
                {
                    groove = Math.Floor(tt * 2.2) % 2 == 0 ? 0 : 1;
                    if ((tt % 5) < 0.9) { ReplaceFace(head, "HAPPY"); normalFace = false; }
                    else if (blink) { ReplaceFace(head, "SLEEPY"); normalFace = false; }
                }
            }
            else
            {
                if (Night) { sit = true; body = "ARMS_HUG"; legs = "LEGS_SIT"; if ((tt % 6) < 4) { ReplaceFace(head, "SLEEPY"); normalFace = false; } }
                else if (Math.Abs(Math.Sin(tt * 3.2)) > 0.8) { ReplaceFace(head, "HAPPY"); normalFace = false; }
                else if (blink) { ReplaceFace(head, "SLEEPY"); normalFace = false; }
            }
            by += groove;
            int dy = sit ? A("LEGS_A").Length - A("LEGS_SIT").Length : 0;
            string[] rows = Pal.Stack(head, A(body), A(legs));
            if (Is("tinky") && w.Lunch) DrawAt(g, A("BAG"), 9.5, 9, bx, by, ps, flip, false, true);
            DrawPix(g, rows, bx - (rows[0].Length - 12) / 2 * ps, by + (16 - rows.Length) * ps, ps, flip, false, true);
            DrawAccessories(g, bx, by, ps, flip, dy, normalFace);
            DrawStatusIcon(g, TummyStatus(), bx + 6 * ps, by + (int)((P.TummyRow + dy) * ps), Math.Max(1, ps / 2), true);
            if (Is("tinky") && !w.Lunch)
            {
                if (Night) DrawAt(g, A("BAG"), 2, P.BodyTop + 2, bx, by, ps, flip, false, true);
                else if ((tt % 8) < 2.4)
                {
                    double ph = tt % 8;
                    string[][] items = { TOAST, HEART, STAR5 };
                    string[] item = items[(int)Math.Floor(tt / 8) % 3];
                    if (ph > 0.9) DrawAt(g, item, 13.5 - item[0].Length / 2.0, P.BodyTop + 5 - Clamp((ph - 0.9) / 0.35, 0, 1) * (item.Length + 2), bx, by, ps, flip, false, true);
                    DrawAt(g, A("BAG_OPEN"), 9.5, P.BodyTop + 3, bx, by, ps, flip, false, true);
                }
                else DrawAt(g, A("BAG"), 9, P.BodyTop + 3, bx, by, ps, flip, false, true);
            }
            if (Is("dipsy")) DrawAt(g, A("HAT"), -2, P.HeadTop - 6 + (Night ? 3 : ((tt % 5) < 0.9 ? -1 : 0)), bx, by, ps, flip, false, true);
            if (Is("laalaa") && Night) DrawAt(g, A("BALL"), 2, P.BodyTop + 2 + dy, bx, by, ps, flip, false, true);
            else if (Is("laalaa") && !w.Lunch) DrawAt(g, A("BALL"), 9.5, 9 - Math.Abs(Math.Sin(tt * 3.2)) * 4, bx, by, ps, flip, false, true);   // 在旁邊拍球（格子窄，靠近一點）
        }
    }

    // ================= 畫（每個角色的姿勢、配件、特效）=================
    class Fr
    {
        public string[] Rows;
        public int Top, Rot;          // Top：圖的第一列放在 16 格框的第幾列（可負）；Rot：轉 90° 的次數
        public bool Fy, Acc = true, Tummy;
        public int AccDy;             // 配件（帽子等）要跟著頭上下移多少格
    }

    partial class Pet
    {
        static readonly string[] SCARF = { "..YYYYYYYY..", "......YY....", "......Y....." };
        static readonly string[] BEANIE = { ".....WW.....", "....PPPP....", "...PPPPPP...", "..WWWWWWWW.." };
        static readonly string[] CROWN = { "...Y.YY.Y...", "...YYYYYY...", "...YPYYPY..." };
        static readonly string[] SANTA = { "........WW..", ".....SSSS...", "....SSSSSS..", "...WWWWWWWW." };
        static readonly string[] GLASSES = { "..P.P..P.P..", "..PPPkkPPP..", "...P....P..." };
        static readonly string[] ENVELOPE = { "SSS", "SYS", "SSS", "SSS" };
        static readonly string[] CAKE = { ".Y..", "PPPP", "WWWW", "PPPP" };
        static readonly string[] FLAKE = { ".B.", "BBB", ".B." };
        static readonly string[] STAR = { ".y.", "yyy", ".y." };
        static readonly string[] HEART = { ".pp.pp.", "ppppppp", "ppppppp", ".ppppp.", "..ppp..", "...p..." };
        static readonly string[] ZZ = { "kkkk", "..k.", ".k..", "kkkk" };
        static readonly string[] NOTE = { "..kk", "..kk", "..k.", "..k.", "kkk.", "kk.." };
        static readonly string[] EXCL = { "SS", "SS", "SS", "..", "SS" };
        static readonly string[] QUES = { ".kkk.", "k...k", "...k.", "..k..", ".....", "..k.." };
        static readonly string[] DROP = { ".B.", "BBB", "BBB", ".B." };
        static readonly string[] BADGE = { "YY" };
        static readonly string[] BALLART = { ".33.", "3433", "3343", ".33." };
        static readonly string[] TBALL = { ".yy.", "yyyy", "yyyy", ".yy." };
        // 小波的球棒（三個角度）、手套
        static readonly string[] BAT_UP = { "..11", "..12", ".12.", ".2..", "k...", "k..." };
        static readonly string[] BAT_FWD = { "k11111122" };
        static readonly string[] BAT_FOLLOW = { "11..", "21..", ".21.", "..2.", "...k", "...k" };
        static readonly string[] GLOVE = { ".55.", "5665", "5565", ".55." };

        Fr F(string[] rows) { Fr f = new Fr(); f.Rows = rows; return f; }
        string[] A(string n) { string[] a; if (P.Art.TryGetValue(n, out a)) return a; App.Log("missing art " + P.Id + "." + n); return P.Art["BODY"]; }

        string[] HeadRows(string face)
        {
            string[] head = (string[])A("HEAD").Clone();
            if (face != null && P.Art.ContainsKey(face))
            {
                string[] fr = A(face);
                for (int i = 0; i < fr.Length && P.FaceRow + i < head.Length; i++)
                    if (fr[i].Length == head[P.FaceRow + i].Length) head[P.FaceRow + i] = fr[i];
            }
            else if (P.EyeRow >= 0 && state != "glass")
            {
                // 眼睛跟著滑鼠
                Point cp = Cursor.Position;
                double dx = cp.X - Cx;
                int off = dx < -30 ? -1 : (dx > 30 ? 1 : 0);
                if (dir < 0) off = -off;
                char[] e = head[P.EyeRow].ToCharArray();
                e[P.EyeL + off] = 'k'; e[P.EyeR + off] = 'k';
                head[P.EyeRow] = new string(e);
            }
            return head;
        }

        bool Step2(double rate) { return Math.Floor(anim * rate) % 2 == 1; }

        Fr Frame()
        {
            if (P.Pik) return FramePik();
            if (P.Orig) return FrameOrig();
            switch (P.Id)
            {
                case "po": return FramePo();
                case "stitch": return FrameStitch();
                case "hangyodon": return FrameHangyodon();
                case "tinky": case "dipsy": case "laalaa": return FrameTubby();
            }
            return FrameSpidey();
        }

        // ---- Spidey（照舊）----
        Fr FrameSpidey()
        {
            bool sleep = state == "sleep", hug = state == "hug";
            bool armsUp = state == "glass" || state == "kick" || (state == "dance" && Math.Floor(anim * 4) % 2 == 0) || state == "swing" || state == "air" || state == "fling" || state == "climb" || state == "drag" || state == "shoot" || state == "zip"
                || state == "webcatch" || state == "sling" || state == "pose" || state == "stowfly" || (state == "hang" && hangPhase == 0) || (state == "idle" && Bt > 0);
            bool step = ((state == "walk" || state == "climb" || state == "goto") && Step2(6))
                || ((state == "seek" || state == "fetch" || state == "hide") && Step2(11))
                || (state == "drag" && Step2(12))
                || (state == "dance" && Math.Floor(anim * 4) % 2 == 1);
            string face = sleep ? "SLEEPY" : (hug ? "HAPPY" : (state == "dizzy" ? "DIZZY" : null));
            List<string> rows = new List<string>(HeadRows(face));
            rows.AddRange(A(hug ? "ARMS_HUG" : (armsUp ? "ARMS_UP" : "BODY")));
            rows.AddRange(A(step ? "LEGS_B" : "LEGS_A"));
            if (Night && !hug)
            {
                char[] chest = rows[10].ToCharArray();
                if (chest[5] == 'k' && chest[6] == 'k') { chest[5] = 'w'; chest[6] = 'w'; rows[10] = new string(chest); }
            }
            if (!hug && Level() >= 5)
            {
                char[] chest = rows[10].ToCharArray();
                if (chest[5] != 'r' && chest[6] != 'r') { chest[5] = 'Y'; chest[6] = 'Y'; rows[10] = new string(chest); }
            }
            Fr f = F(rows.ToArray());
            f.Fy = state == "hang" && hangPhase == 1;
            return f;
        }

        // ---- 小波 ----
        Fr FramePo()
        {
            if (state == "plop") { Fr pf = F(Pal.Stack(HeadRows(sT < 0.55 ? "DIZZY" : "HAPPY"), A("ARMS_UP"), A("LEGS_SIT"))); pf.Tummy = true; return pf; }
            bool hug = state == "hug", sleep = state == "sleep";
            bool yawn = Night && state == "idle" && (anim % 6) < 1.4;
            string face = sleep || yawn ? "SLEEPY" : (hug || state == "spin" || (state == "pose" && poseKind == "homerun") ? "HAPPY" : (state == "dizzy" ? "DIZZY" : (state == "glass" ? "SQUISH" : null)));
            bool armsUp = state == "glass" || state == "catch" || state == "drag" || (state == "air" && !OnScooter()) || (state == "wave" && Step2(4)) || (state == "dance" && Step2(4))
                || (state == "pose" && poseKind != "homerun") || state == "kick" || state == "throw" && t > 0.15;
            string[] body = A(hug ? "ARMS_HUG" : (armsUp ? "ARMS_UP" : "BODY"));
            Fr f;
            if (OnScooter()) { f = F(Pal.Stack(HeadRows(face), body, A("LEGS_RIDE"))); f.Top = -4; f.AccDy = -4; }
            else if (sleep) { f = F(Pal.Stack(HeadRows(face), body, A("LEGS_SIT"))); }
            else
            {
                bool step = (state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto") && Step2(10) || (state == "dance" && Step2(4));
                f = F(Pal.Stack(HeadRows(face), body, A(step ? "LEGS_B" : "LEGS_A")));
            }
            f.Tummy = !hug;
            if (rolling) { f.Rot = (int)Math.Floor(anim * 14) % 4; f.Acc = false; f.Tummy = false; }
            return f;
        }

        // ---- 史迪仔 ----
        Fr FrameStitch()
        {
            bool hug = state == "hug";
            if (RidingStolen)
            {
                // 偷騎小波的滑板車：站在車上
                Fr rs = F(Pal.Stack(HeadRows("HAPPY"), A("ARMS_UP"), A("LEGS_A"))); rs.Top = -4; rs.AccDy = -4; return rs;
            }
            if (rolling || state == "curl")
            {
                Fr b = F(A("BALL")); b.Rot = (int)Math.Floor(anim * 12) % 4; b.Acc = false; return b;
            }
            if (state == "sleep")
            {
                Fr b = F(A("BALL_SLEEP")); b.Acc = false; return b;
            }
            bool crawl = state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto" || (state == "chomp" && w.OutCount() > 1) || state == "ceil";
            string face = hug ? "HAPPY" : (state == "dizzy" ? "DIZZY" : null);
            string[] head = HeadRows(face);
            if (crawl)
            {
                Fr c = F(Pal.Stack(head, A(Step2(state == "ceil" ? 8 : 12) ? "CRAWL_B" : "CRAWL_A")));
                c.AccDy = 5;
                if (state == "ceil") { c.Fy = true; c.Acc = false; }
                return c;
            }
            // 耳朵：發呆時偶爾抖一抖；晚上垂下來
            if (Night && (state == "idle" || state == "hug")) { string[] ed = A("EARS_DOWN"); for (int i = 0; i < ed.Length; i++) head[i] = ed[i]; }
            else if ((state == "idle" || state == "pose") && (anim % 2.2) < 0.5 && Step2(8)) { string[] eu = A("EARS_UP"); for (int i = 0; i < eu.Length; i++) head[i] = eu[i]; }
            bool armsUp = state == "wall" || state == "catch" || state == "drag" || state == "air" || state == "nudge" || state == "throw" || (state == "elvis" && Step2(5)) || (state == "dance" && Step2(4)) || (state == "pose" && poseKind == "photo") || state == "kick";
            bool lick = state == "glass" || (state == "pose" && poseKind == "lick"), grin = state == "chomp" || (state == "pose" && poseKind == "grin");
            if (lick) ReplaceFace(head, "LICKF"); else if (grin) ReplaceFace(head, "GRIN");
            string bodyName = hug || (Night && state == "idle") ? "ARMS_HUG" : (lick ? "LICK" : (armsUp ? "ARMS_UP" : "BODY"));
            bool step = (state == "wall" && Step2(8)) || (state == "elvis" && Step2(6)) || (state == "dance" && Step2(4));
            return F(Pal.Stack(head, A(bodyName), A(step ? "LEGS_B" : "LEGS_A")));
        }

        // ---- 人魚漢頓 ----
        Fr FrameHangyodon()
        {
            bool hug = state == "hug", sit = state == "sleep";
            bool silly = state == "pose" && poseKind == "silly";
            string face = state == "sleep" || (Night && state == "idle" && (anim % 5) < 1.5) ? "SLEEPY" : (hug || (state == "pose" && poseKind == "hero") ? "HAPPY" : (state == "dizzy" || tripT > 0 ? "DIZZY" : (silly ? "SILLY" : null)));
            string[] head = HeadRows(face);
            bool armsUp = state == "air" || state == "fling" || state == "drag" || state == "header" || state == "capetrip" || state == "swim" || (state == "dance" && Step2(3)) || (state == "pose" && poseKind != "silly") || state == "kick";
            string bodyName = hug ? "ARMS_HUG" : (silly || state == "glass" ? "POUT" : (armsUp ? "ARMS_UP" : "BODY"));
            string legs = sit ? "LEGS_SIT" : ((state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto") && Step2(4) ? "LEGS_B" : "LEGS_A");
            Fr f = F(Pal.Stack(head, A(bodyName), A(legs)));
            if (tripT > 0) { f.Rot = dir > 0 ? 1 : 3; f.Acc = false; }   // 跌個狗吃屎
            if (rolling) { f.Rot = (int)Math.Floor(anim * 10) % 4; f.Acc = false; }
            return f;
        }

        // 把只往右延伸的圖左邊補空白，讓 12 格的身體留在框的中間
        static string[] PadCenter(string[] rows, int extra)
        {
            string[] o = new string[rows.Length];
            for (int i = 0; i < rows.Length; i++) o[i] = new string('.', extra) + rows[i];
            return o;
        }

        static string[] Rot90(string[] rows, int r)
        {
            r = ((r % 4) + 4) % 4;
            string[] cur = rows;
            for (int n = 0; n < r; n++)
            {
                int h = cur.Length, wd = cur[0].Length;
                char[][] o = new char[wd][];
                for (int i = 0; i < wd; i++) o[i] = new char[h];
                for (int ry = 0; ry < h; ry++)
                    for (int rx = 0; rx < wd; rx++)
                        o[rx][h - 1 - ry] = rx < cur[ry].Length ? cur[ry][rx] : '.';
                string[] nr = new string[wd];
                for (int i = 0; i < wd; i++) nr[i] = new string(o[i]);
                cur = nr;
            }
            return cur;
        }

        public void DrawPix(Graphics g, string[] rows, int bx, int by, int ps, bool fx, bool fy, bool withHalo)
        {
            Dictionary<char, Color> pal = Night ? P.Night : P.Day;
            int hw = Math.Max(1, ps / 3);
            int h = rows.Length;
            using (SolidBrush hb = new SolidBrush(Night ? P.HaloNight : P.Halo))
                for (int pass = withHalo ? 0 : 1; pass < 2; pass++)
                    for (int ry = 0; ry < h; ry++)
                    {
                        string row = rows[ry];
                        for (int rx = 0; rx < row.Length; rx++)
                        {
                            char c = row[rx];
                            if (c == '.') continue;
                            int px = bx + (fx ? row.Length - 1 - rx : rx) * ps, py = by + (fy ? h - 1 - ry : ry) * ps;
                            if (pass == 0) g.FillRectangle(hb, px - hw, py - hw, ps + 2 * hw, ps + 2 * hw);
                            else
                            {
                                Color col;
                                if (!pal.TryGetValue(c, out col)) col = Color.Magenta;
                                using (SolidBrush b = new SolidBrush(col)) g.FillRectangle(b, px, py, ps, ps);
                            }
                        }
                    }
        }

        // 12 格框座標放一張小圖（會跟著左右翻）
        void DrawAt(Graphics g, string[] art, double col, double row, int bx0, int by0, int ps, bool fx, bool fy, bool halo)
        {
            int aw = art[0].Length, ah = art.Length;
            double c = fx ? 12 - col - aw : col, r = fy ? 16 - row - ah : row;
            DrawPix(g, art, bx0 + (int)Math.Round(c * ps), by0 + (int)Math.Round(r * ps), ps, fx, fy, halo);
        }

        void DrawAccessories(Graphics g, int bx0, int by0, int ps, bool fx, int dy, bool normalFace)
        {
            int lv = Level();
            if (lv >= 2) DrawAt(g, SCARF, P.HatCol, P.ScarfRow + dy, bx0, by0, ps, fx, false, false);
            if (lv >= 4 && normalFace && !P.NoGlasses) DrawAt(g, GLASSES, P.HatCol, P.GlassRow + dy, bx0, by0, ps, fx, false, false);
            if (lv >= 5 && !Is("spidey")) DrawAt(g, BADGE, P.BadgeCol, P.BadgeRow + dy, bx0, by0, ps, fx, false, false);
            string[] hat = w.SeasonNow == "xmas" ? SANTA : (lv >= 6 ? CROWN : (lv >= 3 ? BEANIE : null));
            if (HatOnHead() || WearHat || P.Pik) hat = null;      // 迪西：自己的帽子不換（借戴迪西帽子時也一樣）
            if (hat != null)
            {
                DrawAt(g, hat, P.HatCol, P.HatRow + dy - hat.Length, bx0, by0, ps, fx, false, true);
                if (P.KeepAntenna && P.AntThrough)
                {
                    // 丁丁：天線從帽子中間穿出來（照原位置重畫，不墊高，櫃子格子才放得下）
                    string[] head = A("HEAD"); int n = head.Length - 9;
                    string[] ant = new string[n];
                    for (int i = 0; i < n; i++) ant[i] = head[i];
                    DrawAt(g, ant, (12 - ant[0].Length) / 2.0, P.HeadTop - n + dy, bx0, by0, ps, fx, false, true);
                }
                else if (P.KeepAntenna)
                {
                    // 小波的天線（圓圈）要露在帽子上面
                    string[] head = A("HEAD"), ant = new string[P.AntRows >= 0 ? P.AntRows : P.TopRows - 1];
                    for (int i = 0; i < ant.Length; i++) ant[i] = head[i];
                    DrawAt(g, ant, (12 - ant[0].Length) / 2.0, P.HatRow + dy - hat.Length - ant.Length + 1, bx0, by0, ps, fx, false, true);
                }
            }
            if (w.SeasonNow == "cny") DrawAt(g, ENVELOPE, 11, P.SideRow + dy, bx0, by0, ps, fx, false, true);
            if (w.SeasonNow == "birthday") DrawAt(g, CAKE, 11, P.SideRow - 1 + dy, bx0, by0, ps, fx, false, true);
        }

        // ---- Codex／Claude 狀態：小波顯示在肚子螢幕上，其他人在頭旁邊一個小圖示 ----
        static readonly string[] IC_SUN = { "y.y.y", ".yyy.", "yyyyy", ".yyy.", "y.y.y" };
        static readonly string[] IC_HEART = { "pp.pp", "ppppp", ".ppp.", "..p.." };
        static readonly string[] IC_MOON = { ".yyy", "yy..", "yy..", "yy..", ".yyy" };
        static readonly string[] IC_CHECK = { "....W", "...W.", "W.W..", ".W..." };
        static readonly string[] IC_BANG = { "S", "S", "S", ".", "S" };

        void DrawStatusIcon(Graphics g, string st, int cx, int cy, int u, bool onScreen)
        {
            string[] art = null;
            Dictionary<char, Color> pal = Night ? P.Night : P.Day;
            if (st == "busy")
            {
                // 三個點輪流亮
                int on = (int)Math.Floor(w.Now * 3) % 3;
                for (int i = 0; i < 3; i++)
                    using (SolidBrush b = new SolidBrush(i == on ? Color.FromArgb(0x3D, 0x8B, 0xFF) : Color.FromArgb(onScreen ? 0x7A : 0x9A, 0x84, 0x90, 0xA8)))
                        g.FillRectangle(b, cx - 4 * u + i * 3 * u, cy - u / 2 - (i == on ? u / 2 : 0), 2 * u, 2 * u);
                return;
            }
            if (st == "done") art = IC_CHECK;
            else if (st == "stuck") art = IC_BANG;
            else if (st == "night") art = IC_MOON;
            else if (st == "heart") art = IC_HEART;
            else if (st == "sun") art = IC_SUN;
            if (art == null) return;
            int aw = art[0].Length * u, ah = art.Length * u;
            Color bg = st == "done" ? Color.FromArgb(0x2E, 0xA0, 0x5A) : (st == "stuck" ? Color.FromArgb(0xFF, 0xF1, 0xC2) : Color.Empty);
            if (!onScreen && bg != Color.Empty)
                using (SolidBrush b = new SolidBrush(bg)) g.FillRectangle(b, cx - aw / 2 - u, cy - ah / 2 - u, aw + 2 * u, ah + 2 * u);
            if (onScreen && st == "done")
                using (SolidBrush b = new SolidBrush(bg)) g.FillRectangle(b, cx - aw / 2 - u, cy - ah / 2 - u, aw + 2 * u, ah + 2 * u);
            for (int r = 0; r < art.Length; r++)
                for (int c = 0; c < art[r].Length; c++)
                {
                    char ch = art[r][c]; if (ch == '.') continue;
                    Color col = pal.ContainsKey(ch) ? pal[ch] : Color.White;
                    using (SolidBrush b = new SolidBrush(col)) g.FillRectangle(b, cx - aw / 2 + c * u, cy - ah / 2 + r * u, u, u);
                }
        }

        string TummyStatus()
        {
            string st = w.Status();
            if (st != "") return st;
            if (Night) return "night";
            return state == "hug" || hearts.Count > 0 ? "heart" : "sun";
        }

        // 小波的滑板車、人魚漢頓的搖椅、隱形船…（畫在身體後面的）
        void DrawBehind(Graphics g, Fr f, int bx, int by, int ps, bool fx)
        {
            if (Is("po") && !scooterLost)
            {
                if (OnScooter() && !rolling) DrawAt(g, A("SCOOTER"), -1, 7, bx, by, ps, fx, false, true);
                else if (state == "idle" || state == "hug" || state == "wave" || state == "pose" || state == "dizzy" || state == "sleep" || state == "spin" || state == "think" || state == "plop")
                    DrawAt(g, A("SCOOTER"), 7, 7, bx, by, ps, !fx, false, true); // 停在旁邊（車頭朝外）
            }
            if (Is("stitch") && RidingStolen)
            {
                Pal po = Pal.Get("po");
                if (po != null) DrawPixPal(g, po, po.Art["SCOOTER"], bx + (fx ? 12 - (-1) - 14 : -1) * ps, by + 7 * ps, ps, fx);
            }
            if (Is("hangyodon") && (caped || state == "capetrip" || (state == "pose" && poseKind == "hero")))
            {
                // 紅披風（飄在背後）
                bool flap = Step2(caped ? 10 : 4);
                DrawAt(g, A("CAPE"), flap ? -4 : -3.5, 7, bx, by, ps, fx, false, true);
            }
            if (Is("hangyodon") && state == "sleep") DrawSleepBubble(g, bx, by, ps, false);
            if (P.Tubby) DrawTubbyBehind(g, f, bx, by, ps, fx);
            if (P.Pik) DrawPikBehind(g, f, bx, by, ps, fx);
            if (P.Orig) DrawOrigBehind(g, f, bx, by, ps, fx);
        }

        // 人魚漢頓睡在泡泡裡（先畫泡泡底，身體畫完再畫亮面）
        void DrawSleepBubble(Graphics g, int bx, int by, int ps, bool front)
        {
            float cx = bx + 6 * ps, cy = by + 9.5f * ps, r = 9.5f * ps;
            cy += (float)Math.Sin(anim * 1.6) * ps * 0.5f;
            if (!front)
                using (SolidBrush b = new SolidBrush(Color.FromArgb(Night ? 60 : 45, 170, 225, 255))) g.FillEllipse(b, cx - r, cy - r, 2 * r, 2 * r);
            else
            {
                using (Pen p = new Pen(Color.FromArgb(150, 200, 240, 255), Math.Max(1.5f, ps * 0.45f))) g.DrawEllipse(p, cx - r, cy - r, 2 * r, 2 * r);
                using (Pen p = new Pen(Color.FromArgb(200, 255, 255, 255), Math.Max(1.5f, ps * 0.5f))) g.DrawArc(p, cx - r * 0.75f, cy - r * 0.75f, r * 1.5f, r * 1.5f, 200, 50);
            }
        }

        void DrawPixPal(Graphics g, Pal pal, string[] rows, int bx, int by, int ps, bool fx)
        {
            Dictionary<char, Color> cols = Night ? pal.Night : pal.Day;
            for (int ry = 0; ry < rows.Length; ry++)
                for (int rx = 0; rx < rows[ry].Length; rx++)
                {
                    char c = rows[ry][rx]; if (c == '.') continue;
                    int px = bx + (fx ? rows[ry].Length - 1 - rx : rx) * ps;
                    Color col; if (!cols.TryGetValue(c, out col)) col = Color.Magenta;
                    using (SolidBrush b = new SolidBrush(col)) g.FillRectangle(b, px, by + ry * ps, ps, ps);
                }
        }

        // 球棒、手套、烏克麗麗、嘴裡的球（畫在身體前面的）
        void DrawFront(Graphics g, Fr f, int bx, int by, int ps, bool fx)
        {
            if (Is("po"))
            {
                if (state == "bat")
                {
                    string[] bat = batT < 0.2 ? BAT_UP : (batT < 0.34 ? BAT_FWD : BAT_FOLLOW);
                    if (bat == BAT_UP) DrawAt(g, bat, -1, 4, bx, by, ps, fx, false, true);
                    else if (bat == BAT_FWD) DrawAt(g, bat, 9, 10, bx, by, ps, fx, false, true);
                    else DrawAt(g, bat, 9, 3, bx, by, ps, fx, false, true);
                    if (w.Holder == this && batT < 0.22) DrawAt(g, BALLART, 13 - batT * 10, 9, bx, by, ps, fx, false, true);
                }
                if (state == "pose" && poseKind == "homerun") DrawAt(g, BAT_FOLLOW, 9, 3, bx, by, ps, fx, false, true);
                if (state == "catch" || state == "throw")
                {
                    DrawAt(g, GLOVE, 11, 6, bx, by, ps, fx, false, true);
                    if (w.Holder == this) DrawAt(g, BALLART, 11, 5, bx, by, ps, fx, false, true);
                }
            }
            if (Is("stitch"))
            {
                bool uke = state == "elvis" || (Night && state == "idle") || (state == "pose" && poseKind == "uke");
                if (uke) DrawAt(g, A("UKE"), 5, 8, bx, by, ps, fx, false, true);
                if (w.Holder == this && (state == "chomp" || state == "catch" || state == "throw" || state == "walk"))
                    DrawAt(g, w.BallKind == "baseball" ? BALLART : TBALL, 4, state == "chomp" || state == "walk" ? (f.AccDy > 0 ? 11 : 6) : 3, bx, by, ps, fx, false, true);
            }
            if (Is("hangyodon") && state == "sleep") DrawSleepBubble(g, bx, by, ps, true);
            if (Is("spidey") && w.Holder == this) DrawAt(g, w.BallKind == "baseball" ? BALLART : TBALL, 9, 4, bx, by, ps, fx, false, true);
            if (P.Tubby) DrawTubbyFront(g, f, bx, by, ps, fx);
            if (P.Pik) DrawPikFront(g, f, bx, by, ps, fx);
            if (P.Orig) DrawOrigFront(g, f, bx, by, ps, fx);
            if (HoldToast && f.Rot == 0 && !f.Fy) DrawAt(g, TOAST, Is("po") ? 9.5 : 10.5, P.BodyTop + 1 + f.AccDy, bx, by, ps, fx, false, true);
        }

        // ================= 一格一格畫到 layered window =================
        Bitmap frameBmp;
        void Grow(ref double l, ref double tp, ref double r, ref double b, double px, double py)
        {
            l = Math.Min(l, px); r = Math.Max(r, px); tp = Math.Min(tp, py); b = Math.Max(b, py);
        }
        bool SilkVisible() { return state == "swing" || state == "hang" || state == "zip" || state == "shoot" || state == "webcatch" || state == "sling"; }
        double Bob() { if (P.Pik) return PikBob(); if (P.Orig) return OrigBob(); if (P.Tubby) return TubbyBob(); return state == "dance" || state == "elvis" ? Math.Abs(Math.Sin(anim * 8)) * 6 * k : (Is("hangyodon") && state == "walk" ? (Step2(4) ? k : 0) : 0); }

        public void Render()
        {
            if (!Out || w.Hidden) { HideForms(); return; }
            EnsureForms();
            double l = x - 11 * S, tp = y - 10 * S, r = x + SW + 11 * S, b = y + SH + 2 * S;
            if (sc > 1) { double cxs = Cx; l = Math.Min(l, cxs - SW * sc / 2 - 4 * S); r = Math.Max(r, cxs + SW * sc / 2 + 4 * S); tp = Math.Min(tp, y + SH - SH * sc - 8 * S * sc); }
            if (SilkVisible()) Grow(ref l, ref tp, ref r, ref b, ax, ay);
            if (state == "sleep") { r = Math.Max(r, x + SW + 26 * k); tp = Math.Min(tp, y - 36 * k); }
            if (sense > 0) { l = Math.Min(l, Cx - 50 * k); r = Math.Max(r, Cx + 50 * k); }
            if (hearts.Count > 0 || notes.Count > 0) { tp = Math.Min(tp, y - 90 * k); }
            foreach (double[] sp in sparks) Grow(ref l, ref tp, ref r, ref b, sp[0], sp[1]);
            foreach (double[] f in flakes) Grow(ref l, ref tp, ref r, ref b, f[0], f[1]);
            if (w.Lead() == this && w.TicketCountdown() != null) { tp = Math.Min(tp, y - (P.TopRows + 16) * S); l = Math.Min(l, Cx - 60 * k); r = Math.Max(r, Cx + 60 * k); }
            if (P.Tubby || WearHat || HoldToast || P.Pik || P.Orig) tp = Math.Min(tp, y - (P.TopRows + (state == "juggle" || state == "hattoss" || state == "bagdig" ? 16 : 9)) * S);
            int pad = 6 + (int)(5 * k);
            Rectangle nb = Rectangle.FromLTRB((int)Math.Floor(l) - pad, (int)Math.Floor(tp) - pad, (int)Math.Ceiling(r) + pad, (int)Math.Ceiling(b) + pad);
            if (frameBmp == null || frameBmp.Width != nb.Width || frameBmp.Height != nb.Height)
            {
                if (frameBmp != null) frameBmp.Dispose();
                frameBmp = new Bitmap(Math.Max(1, nb.Width), Math.Max(1, nb.Height), PixelFormat.Format32bppArgb);
            }
            using (Graphics g = Graphics.FromImage(frameBmp))
            {
                g.Clear(Color.Transparent);
                PaintPet(g, nb.X, nb.Y);
            }
            W.Present(Form, frameBmp, nb.X, nb.Y);
            if (!W.Shown(Form)) { Form.Show(); w.Zorder(); }
            UpdateBubble();
        }

        public void UpdateBubble()
        {
            EnsureForms();
            if (Bt <= 0 || string.IsNullOrEmpty(bubble) || w.Hidden) { if (W.Shown(Bub)) Bub.Hide(); return; }
            Size sz = Bub.Measure(bubble, bubbleAlert, Night ? P.NightBubble : 0, bubbleHint);
            double ancX, above;
            if (Out)
            {
                ancX = Cx;
                above = y + SH - SH * sc - P.TopRows * S * sc - (state == "sleep" ? 30 * k : 0) - (hearts.Count > 0 ? 24 * k : 0) - ((Is("po") && OnScooter()) || RidingPo ? 4 * S : 0);
                if (w.Lead() == this && w.TicketCountdown() != null) above -= 11 * S;   // 讓出搶票倒數徽章的位置
            }
            else
            {
                // 在櫃子裡：泡泡從格子上方冒出來
                double fxp, fyp; int ps;
                w.ShelfFoot(this, out fxp, out fyp, out ps);
                ancX = fxp; above = fyp - (17 + P.TopRows) * ps;
            }
            Rectangle wa = w.WA(ancX, above + 20);
            int bx = (int)(ancX - sz.Width / 2.0), by = (int)(above - sz.Height - 2);
            if (Out && state == "hang" && hangPhase == 1) by = (int)(y + SH + 6);
            if (Out && state == "ceil") by = (int)(y + SH + 6);
            bx = Math.Max(wa.Left, Math.Min(wa.Right - sz.Width, bx));
            by = Math.Max(wa.Top, Math.Min(wa.Bottom - sz.Height, by));
            Rectangle nb = new Rectangle(bx, by, sz.Width, sz.Height);
            if (Bub.Bounds != nb) Bub.Bounds = nb;
            if (!W.Shown(Bub)) { Bub.Show(); W.KeepOnTop(Bub); }
        }

        void PaintPet(Graphics g, int ox, int oy)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int lw = Math.Max(2, (int)Math.Round(1.5 * k));
            if (SilkVisible())
            {
                double hx = Cx - ox, hy = y + 3 * k - oy, axo = ax - ox, ayo = ay - oy;
                if (state == "shoot")
                {
                    double p = Math.Min(1, shootT / 0.18);
                    axo = hx + (axo - hx) * p; ayo = hy + (ayo - hy) * p;
                }
                if (state == "sling" || state == "webcatch") { hy = y + 9 * k - oy; hx = Cx + dir * 5 * k - ox; }
                using (Pen silk = new Pen(Night ? Color.FromArgb(0x6A, 0x5F, 0x9E) : Color.FromArgb(0x9A, 0xA3, 0xBC), lw))
                using (Pen core = new Pen(Night ? Color.FromArgb(0x14, 0x14, 0x1C) : Color.FromArgb(0x4A, 0x52, 0x6E), Math.Max(1, lw / 2)))
                {
                    g.DrawLine(silk, (float)hx, (float)hy, (float)axo, (float)ayo);
                    g.DrawLine(core, (float)hx, (float)hy, (float)axo, (float)ayo);
                    if (state != "shoot" || shootT >= 0.18)
                    {
                        float s = (float)(5 * k), cxs = (float)axo, cys = (float)ayo;
                        g.DrawLine(silk, cxs - s, cys, cxs + s, cys);
                        g.DrawLine(silk, cxs, cys - s, cxs, cys + s);
                        g.DrawLine(silk, cxs - s * .7f, cys - s * .7f, cxs + s * .7f, cys + s * .7f);
                        g.DrawLine(silk, cxs - s * .7f, cys + s * .7f, cxs + s * .7f, cys - s * .7f);
                    }
                }
            }

            Fr f = Frame();
            int sbx, sby, sps;
            if (Math.Abs(sc - 1) > 0.001)
            {
                sps = Math.Max(1, (int)Math.Round(S * sc));
                double shake = knock > 0 ? -3 * k : 0;
                sbx = (int)Math.Round(Cx - 6 * sps) - ox; sby = (int)Math.Round(y + SH - 16 * sps + shake) - oy;
            }
            else { sps = S; sbx = (int)Math.Round(x) - ox; sby = (int)Math.Round(y - Bob()) - oy; }
            if (state == "elvis") sbx += (Step2(6) ? 1 : -1) * Math.Max(1, sps / 3);
            bool fx = dir < 0;
            DrawFigure(g, f, sbx, sby, sps, fx, true);

            // 原尺寸敲玻璃：手前面一圈小漣漪
            if (state == "pose" && poseKind == "tap")
            {
                double ph = (anim * 1.6) % 1;
                float rx = (float)(Cx - ox), ry = (float)(y + SH * 0.45 - oy), rr = (float)((4 + ph * 14) * k);
                using (Pen rp = new Pen(Color.FromArgb((int)(170 * (1 - ph)), 255, 255, 255), Math.Max(1.5f, (float)k)))
                using (Pen rp2 = new Pen(Color.FromArgb((int)(90 * (1 - ph)), 120, 150, 200), Math.Max(1f, (float)k * 0.6f)))
                { g.DrawEllipse(rp2, rx - rr - 1, ry - rr * 0.6f - 1, 2 * rr + 2, rr * 1.2f + 2); g.DrawEllipse(rp, rx - rr, ry - rr * 0.6f, 2 * rr, rr * 1.2f); }
            }
            // 第四面牆：小波臉貼玻璃起霧、史迪仔舔玻璃
            if (state == "glass" && sc > 2)
            {
                if (HasTv)
                    using (SolidBrush fog = new SolidBrush(Color.FromArgb(70, 255, 255, 255)))
                    {
                        int fo = (P.HeadTop + 1) * sps;   // 小波 0；丁丁頭比較高
                        g.FillEllipse(fog, sbx + 3 * sps, sby + 7 * sps + fo, 6 * sps, 3 * sps);
                        g.FillEllipse(fog, sbx + 2 * sps, sby + 9 * sps + fo, 8 * sps, 3 * sps);
                    }
                if (Is("stitch") && gt > 0.8)
                    using (SolidBrush wet = new SolidBrush(Color.FromArgb(55, 190, 225, 255)))
                    {
                        float lick = (float)Math.Min(1, (gt - 0.8) / 1.2);
                        g.FillEllipse(wet, sbx + 3 * sps, sby + (float)(8 - 6 * lick) * sps, 5 * sps, (float)(3 + 6 * lick) * sps);
                    }
                if (Is("hangyodon") && gt > 1.0)
                    using (SolidBrush lip = new SolidBrush(Color.FromArgb(70, 245, 140, 170)))   // 嘴唇印在玻璃上
                        g.FillEllipse(lip, sbx + 1.5f * sps, sby + 7.2f * sps, 9 * sps, 2.6f * sps);
            }

            // Codex／Claude 狀態小圖示（小波在肚子上，其他人在頭旁邊）
            if (!HasTv && Math.Abs(sc - 1) < 0.001 && w.Lead() == this)
            {
                string st = w.Status();
                if (st != "") DrawStatusIcon(g, st, (int)(x + SW + 2 * S) - ox, (int)(y - 1 * S) - oy, Math.Max(1, S / 2), false);
            }

            DrawTicketBadge(g, ox, oy);
            int fps = Math.Max(1, S / 3);
            foreach (double[] fl in flakes) DrawPix(g, FLAKE, (int)fl[0] - ox - fps, (int)fl[1] - oy - fps, fps, false, false, false);

            if (sense > 0 && !f.Fy)
            {
                using (Pen p = new Pen(Night ? Color.FromArgb(0x9B, 0x7B, 0xFF) : Color.FromArgb(0xC9, 0x54, 0x54), (float)(2 * k)))
                {
                    double cx = Cx - ox, cy = y + 10 * k - oy, wob = Math.Sin(anim * 30) * 1.5 * k;
                    for (int s = -1; s <= 1; s += 2)
                        for (int i = 0; i < 3; i++)
                            g.DrawLine(p, (float)(cx + s * (22 + i * 5 + wob) * k), (float)(cy + (-10 + i * 6) * k),
                                          (float)(cx + s * (30 + i * 5 + wob) * k), (float)(cy + (-16 + i * 8) * k));
                }
            }

            if (state == "sleep")
            {
                int ps = Math.Max(2, S / 2);
                for (int i = 0; i < 3; i++)
                {
                    double p = (z * .6 + i / 3.0) % 1;
                    if (p > 0.85) continue;
                    DrawPix(g, ZZ, (int)(x + SW - 4 * k + p * 16 * k) - ox, (int)(y - 2 * k - p * 30 * k) - oy, ps, false, false, false);
                }
            }

            int hp = Math.Max(2, S / 2);
            foreach (double[] sp in sparks)
                if (sp[4] < 0.6 || Math.Floor(sp[4] * 20) % 2 == 0)
                    DrawPix(g, STAR, (int)(sp[0] - 1.5 * hp) - ox, (int)(sp[1] - 1.5 * hp) - oy, hp, false, false, false);
            foreach (double[] h in hearts)
            {
                double age = h[1];
                int hx = (int)(Cx + h[0] + Math.Sin(age * 6 + h[0]) * 3 * k - 3.5 * hp) - ox;
                int hy = (int)(y - 8 * k - age * 45 * k - 6 * hp) - oy;
                DrawPix(g, HEART, hx, hy, hp, false, false, true);
            }
            foreach (double[] n in notes)
            {
                double age = n[1];
                if (n[2] == 7)
                {
                    // 史迪仔吃東西掉的屑屑
                    using (SolidBrush cb = new SolidBrush(Color.FromArgb(0xC8, 0x93, 0x4E)))
                        g.FillRectangle(cb, (float)(Cx + n[0]) - ox, (float)(y + 9 * S + age * 40 * k) - oy, Math.Max(2, S / 2), Math.Max(2, S / 2));
                    continue;
                }
                if (n[2] == 5)
                {
                    float bxp = (float)(Cx + n[0] * 1.6 + Math.Sin(age * 4 + n[0]) * 3 * k) - ox, byp = (float)(y + 8 * k - age * 50 * k) - oy, rr = (float)((1.6 + age * 1.2) * k);
                    if (age < 1.5)
                        using (Pen bp = new Pen(Color.FromArgb(200, 150, 215, 255), Math.Max(1f, (float)k * 0.9f)))
                        using (SolidBrush hl = new SolidBrush(Color.FromArgb(220, 255, 255, 255)))
                        { g.DrawEllipse(bp, bxp - rr, byp - rr, 2 * rr, 2 * rr); g.FillRectangle(hl, bxp - rr * 0.5f, byp - rr * 0.6f, Math.Max(1f, rr * 0.4f), Math.Max(1f, rr * 0.4f)); }
                    continue;
                }
                string[] art = n[2] == 0 ? NOTE : (n[2] == 1 ? EXCL : (n[2] == 2 ? QUES : (n[2] == 3 ? ZZ : DROP)));
                int hx = (int)(Cx + n[0] + (n[2] == 0 ? Math.Sin(age * 5) * 6 * k : 0)) - ox;
                int hy = (int)(y - 6 * k - age * (n[2] == 0 ? 40 : 18) * k) - oy;
                if (age < 1.5 || Math.Floor(age * 16) % 2 == 0) DrawPix(g, art, hx, hy, hp, false, false, true);
            }
        }

        // 畫一隻（身體＋前後道具＋配件＋肚子螢幕）；櫃子裡也用這個
        void DrawFigure(Graphics g, Fr f, int sbx, int sby, int sps, bool fx, bool extras)
        {
            // 圖一律貼齊 16 格框的底（比較高的角色往上長），Top 再額外上下移
            string[] rows = f.Rows;
            int top = f.Top + 16 - rows.Length;
            int left = -(rows[0].Length - 12) / 2;
            if (f.Rot != 0)
            {
                rows = Rot90(rows, f.Rot);
                left = -(rows[0].Length - 12) / 2;
                top = (16 - rows.Length) / 2 + 1;
            }
            if (extras) DrawBehind(g, f, sbx, sby, sps, fx);
            DrawPix(g, rows, sbx + left * sps, sby + top * sps, sps, fx, f.Fy, true);
            if (f.Acc && !f.Fy)
            {
                bool normalFace = state != "sleep" && state != "hug" && state != "dizzy";
                DrawAccessories(g, sbx, sby, sps, fx, f.AccDy, normalFace);
            }
            if (f.Tummy && f.Rot == 0)
            {
                int u = Math.Max(1, sps / 2);
                int scx = sbx + 6 * sps, scy = sby + (int)((P.TummyRow + f.AccDy) * sps);
                DrawStatusIcon(g, TummyStatus(), scx, scy, u, true);
            }
            if (extras) { DrawFront(g, f, sbx, sby, sps, fx); DrawLunch(g, f, sbx, sby, sps, fx); }
        }
    }

    // ================= 公仔櫃 =================
    // 右下角的木頭展示櫃：右邊一格高的（最愛）、左邊三格小的。點格子裡的公仔＝放出來／收回去。
    partial class ShelfForm : OverlayForm
    {
        readonly World w;
        public readonly int U, TU;           // 小格、高格的像素大小
        readonly double k;
        public bool Hot, Over, Night;
        public bool Tubby;                   // 天線寶寶一櫃：格子裡是藍天綠山丘，大格有太陽寶寶
        int hover = -1;
        Bitmap bmp, bg;
        string bgKey = "";
        Rectangle area;                      // 螢幕座標
        public Rectangle Area { get { return area; } }
        readonly Rectangle[] cells = new Rectangle[4]; // 本地座標（含名牌那條）
        int bW, crown, baseH, div, plateH;
        // ---- 收合成蛋 ----
        public bool Collapsed;
        double fold, gulp, wobT, nextWob = 4;    // fold：0 櫃子 → 1 蛋
        public int Attention;                     // 蛋上的小紅點（存著的通知、快到的提醒）
        public bool Lunch;
        public static readonly string[] EGG = {
            "......kkkkkk......",
            ".....kccccssk.....",
            "....kchhYccssk....",
            "....khcYYYossk....",
            "...kchccYcccssk...",
            "...kccccccccssk...",
            "..kcccccccrrcssk..",
            "..kcccccccrrcssk..",
            "..kccccooccccssk..",
            ".kcccccoocccccssk.",
            ".kccbbccccccccssk.",
            ".kccbbcccccccossk.",
            ".kccccccccccccssk.",
            "..kcccccccggcssk..",
            "..kcccccccggcssk..",
            "..kcccrccccccssk..",
            "...kccccccccssk...",
            "...kccccccccssk...",
            "....kkkkkkkkkk...." };
        public bool Animating { get { return (Collapsed ? fold < 1 : fold > 0) || gulp > 0 || wobT > 0; } }
        int EggPs { get { return TU; } }
        public Rectangle EggLocal() { int ps = EggPs; int ew = 18 * ps, eh = 19 * ps; return new Rectangle(Area.Width - ew - 4, Area.Height - eh - 2, ew, eh); }
        public Rectangle EggScreen() { Rectangle r = EggLocal(); r.Offset(Area.Location); return r; }
        Rectangle TabLocal() { int s = 5 * U; return new Rectangle(Area.Width - s - 3 * U, 0, s, (int)(crown * 0.8)); }
        public void Gulp() { gulp = 0.5; wobT = 0.7; }
        public void SnapFold() { fold = Collapsed ? 1 : 0; }
        public void Step(double dt)
        {
            double target = Collapsed ? 1 : 0;
            if (fold < target) fold = Math.Min(target, fold + dt / 0.7); else if (fold > target) fold = Math.Max(target, fold - dt / 0.8);
            if (gulp > 0) gulp -= dt;
            if (wobT > 0) wobT -= dt;
            if (Collapsed && fold >= 1)
            {
                nextWob -= dt;
                if (nextWob <= 0) { wobT = Attention > 0 ? 0.9 : 0.6; nextWob = Attention > 0 ? 2.5 : 6 + new Random().NextDouble() * 6; }
            }
        }
        // 蛋的腳（公仔收進蛋裡的位置）
        public Point EggFoot() { Rectangle r = EggScreen(); return new Point(r.X + r.Width / 2, r.Y + r.Height * 2 / 3); }

        // ---- 拖著蛋（或櫃頂）搬家：右下角擋到東西時可以移開；位置存在 shelfpos.txt（相對右下角的位移） ----
        public int OffX, OffY;
        int defX, defY;
        Rectangle lastWa;
        bool dragArm, dragMoved;
        Point dragFrom;
        int dragOX, dragOY;
        string PosFile { get { return Path.Combine(World.DataDir, "shelfpos.txt"); } }
        void LoadOffset()
        {
            try
            {
                if (!File.Exists(PosFile)) return;
                string[] a = File.ReadAllText(PosFile).Trim().Split(' ');
                int x, y;
                if (a.Length >= 2 && int.TryParse(a[0], out x) && int.TryParse(a[1], out y)) { OffX = x; OffY = y; }
            }
            catch { }
        }
        void SaveOffset()
        {
            try { Directory.CreateDirectory(World.DataDir); File.WriteAllText(PosFile, OffX + " " + OffY); } catch { }
        }
        // 蛋或櫃頂（不是收合鈕、不是格子）可以拖
        bool DragSpot(Point local) { return Collapsed ? EggLocal().Contains(local) : (local.Y < crown && !TabLocal().Contains(local)); }

        public ShelfForm(World w, int S) : base(false, true)
        {
            this.w = w;
            U = Math.Max(2, S * 3 / 4); TU = S;
            k = S / 3.0;
            Cursor = Cursors.Hand;
            LoadOffset();
        }

        protected override void OnPaint(PaintEventArgs e) { }
        protected override void OnPaintBackground(PaintEventArgs e) { }

        public void Place(Rectangle wa)
        {
            bW = 3 * U; crown = 5 * U; baseH = 5 * U; div = 2 * U; plateH = 5 * U;
            int smallW = 24 * U, smallH = 33 * U, tallW = 24 * TU, tallH = 3 * smallH + 2 * div;
            int W = bW * 2 + smallW + div + tallW, H = crown + tallH + baseH;
            defX = wa.Right - W - 6; defY = wa.Bottom - H; lastWa = wa;
            int ax = Math.Max(wa.Left, Math.Min(defX, defX + OffX)), ay = Math.Max(wa.Top, Math.Min(defY, defY + OffY));
            area = new Rectangle(ax, ay, W, H);
            cells[0] = new Rectangle(bW + smallW + div, crown, tallW, tallH);
            for (int i = 0; i < 3; i++) cells[i + 1] = new Rectangle(bW, crown + i * (smallH + div), smallW, smallH);
        }

        public int CellPs(int i) { return i == 0 ? TU : U; }
        // 依公仔實際高度（天線、耳朵、頭鰭、帽子、晃動）縮放，保證離格子頂端至少 2px
        public int FitPs(int i, Pet p)
        {
            int ps = CellPs(i);
            if (p == null) return ps;
            int avail = cells[i].Height - plateH - U - (i == 0 ? PedH() : 0) - 2 - 2;
            while (ps > 2 && p.ShelfRows() * ps > avail) ps--;
            return ps;
        }
        public Rectangle CellScreen(int i) { Rectangle c = cells[i]; c.Offset(Area.Location); return c; }
        // 公仔腳踩的位置（螢幕座標）
        public Point Foot(int i) { Rectangle c = CellScreen(i); return new Point(c.X + c.Width / 2, c.Bottom - plateH - U - (i == 0 ? PedH() : 0)); }
        int PedH() { return (int)((cells[0].Height - plateH) * 0.2); }

        public int CellAt(Point screen)
        {
            if (Collapsed) return -1;
            for (int i = 0; i < 4; i++) if (CellScreen(i).Contains(screen)) return i;
            return -1;
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left) return;
            Point cp = Cursor.Position;
            if (DragSpot(new Point(cp.X - Area.X, cp.Y - Area.Y))) { dragArm = true; dragMoved = false; dragFrom = cp; dragOX = OffX; dragOY = OffY; return; }   // 放開時才決定是點還是拖
            ClickAt(cp, e.Button);
        }
        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (e.Button == MouseButtons.Left && dragArm)
            {
                dragArm = false;
                if (dragMoved) { OffX = Area.X - defX; OffY = Area.Y - defY; SaveOffset(); }   // 貼邊時存實際位置
                else ClickAt(Cursor.Position, e.Button);
                return;
            }
            if (e.Button == MouseButtons.Right) { App.LogAlways("menu: right-up on shelf at " + Cursor.Position + " collapsed=" + Collapsed); ClickAt(Cursor.Position, e.Button); }   // 右鍵放開才叫選單
        }

        // 點櫃子（真的滑鼠或測試用 act click 都走這裡）
        public void ClickAt(Point screen, MouseButtons b)
        {
            Point p = new Point(screen.X - Area.X, screen.Y - Area.Y);
            if (Collapsed)
            {
                if (!EggLocal().Contains(p)) return;
                if (b == MouseButtons.Left) { if (w.Single) w.EggClick(); else w.ToggleEgg(false); }
                else if (b == MouseButtons.Right) w.HouseMenu();   // 蛋＝公仔小屋：開關、設定
                return;
            }
            if (b == MouseButtons.Left && TabLocal().Contains(p)) { w.ToggleEgg(true); return; }
            int c = CellAt(screen);
            if (c < 0) return;
            if (b == MouseButtons.Left) w.ShelfClick(c);
            else if (b == MouseButtons.Right) w.ShelfMenu(c, this);
        }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            Point cp = Cursor.Position;
            if (dragArm && (Control.MouseButtons & MouseButtons.Left) != 0)
            {
                int dx = cp.X - dragFrom.X, dy = cp.Y - dragFrom.Y;
                if (!dragMoved && Math.Abs(dx) + Math.Abs(dy) > 4) dragMoved = true;
                if (dragMoved) { OffX = dragOX + dx; OffY = dragOY + dy; Place(lastWa); w.RepaintShelf(); }
                return;
            }
            hover = CellAt(cp);
        }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); hover = -1; }

        static Color C(int rgb) { return Color.FromArgb((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255); }
        static Color Mix(Color a, Color b, double f) { return Color.FromArgb((int)(a.R + (b.R - a.R) * f), (int)(a.G + (b.G - a.G) * f), (int)(a.B + (b.B - a.B) * f)); }

        static GraphicsPath RoundRect(RectangleF r, float rad)
        {
            GraphicsPath p = new GraphicsPath();
            float d = rad * 2;
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        // 櫃子本體（不會動的部分）先畫好存起來
        void BuildBg(Pet[] who, bool[] outNow)
        {
            int W = Area.Width, H = Area.Height;
            if (bg == null || bg.Width != W || bg.Height != H) { if (bg != null) bg.Dispose(); bg = new Bitmap(W, H, PixelFormat.Format32bppArgb); }
            using (Graphics g = Graphics.FromImage(bg))
            {
                g.Clear(Color.Transparent);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                Color w1 = Night ? C(0x5C3B24) : C(0x9A6338), w2 = Night ? C(0x3C2617) : C(0x6B4024), w3 = Night ? C(0x74503A) : C(0xB97F4E);
                // 影子
                using (GraphicsPath sh = RoundRect(new RectangleF(3, 4, W - 4, H - 4), 5 * U))
                using (SolidBrush b = new SolidBrush(Color.FromArgb(60, 0, 0, 0))) g.FillPath(b, sh);
                // 櫃身
                RectangleF body = new RectangleF(1, crown * 0.35f, W - 3, H - crown * 0.35f - 2);
                using (GraphicsPath p = RoundRect(body, 3 * U))
                using (LinearGradientBrush lb = new LinearGradientBrush(body, w1, w2, 90f)) g.FillPath(lb, p);
                // 木紋
                Random r = new Random(5);
                using (Pen grain = new Pen(Color.FromArgb(Night ? 26 : 34, 40, 20, 8), Math.Max(1f, U * 0.35f)))
                    for (int i = 0; i < 14; i++)
                    {
                        float gx = (float)(r.NextDouble() * W), gy = (float)(crown + r.NextDouble() * (H - crown * 2));
                        g.DrawBezier(grain, gx, gy, gx + 6 * U, gy - U, gx + 12 * U, gy + U, gx + 18 * U, gy);
                    }
                // 頂蓋（冠線）
                RectangleF top = new RectangleF(0, 0, W - 1, crown);
                using (GraphicsPath p = RoundRect(top, 2 * U))
                using (LinearGradientBrush lb = new LinearGradientBrush(top, w3, w1, 90f)) g.FillPath(lb, p);
                using (Pen hi = new Pen(Color.FromArgb(Night ? 50 : 90, 255, 230, 200), Math.Max(1f, U * 0.5f))) g.DrawLine(hi, 3 * U, U, W - 3 * U, U);
                using (Pen dk = new Pen(Color.FromArgb(120, 30, 15, 5), Math.Max(1f, U * 0.5f))) g.DrawLine(dk, U, crown - U * 0.3f, W - U, crown - U * 0.3f);
                // 底座＋小腳
                RectangleF bas = new RectangleF(0, H - baseH - 1, W - 1, baseH - U);
                using (GraphicsPath p = RoundRect(bas, 1.5f * U))
                using (LinearGradientBrush lb = new LinearGradientBrush(bas, w3, w2, 90f)) g.FillPath(lb, p);
                using (SolidBrush ft = new SolidBrush(w2))
                {
                    g.FillRectangle(ft, 3 * U, H - 2 * U, 4 * U, 2 * U);
                    g.FillRectangle(ft, W - 7 * U, H - 2 * U, 4 * U, 2 * U);
                }
                // 每一格
                for (int i = 0; i < 4; i++)
                {
                    Rectangle c = cells[i];
                    Pet pet = who[i];
                    Color panel = pet != null ? pet.P.Panel : C(0xEDE6DA);
                    if (Night) panel = Mix(panel, C(0x2A2238), 0.55);
                    RectangleF inner = new RectangleF(c.X, c.Y, c.Width, c.Height - plateH);
                    using (LinearGradientBrush lb = new LinearGradientBrush(inner, Mix(panel, Color.White, 0.35), Mix(panel, C(0x6B4A30), 0.25), 90f)) g.FillRectangle(lb, inner);
                    if (Tubby) DrawHills(g, inner, i == 0);
                    if (Pik) DrawSoil(g, inner, i == 0);
                    if (Orig) DrawGridPaper(g, inner, i == 0);
                    // 頂上的展示燈
                    using (GraphicsPath gp = new GraphicsPath())
                    {
                        RectangleF glow = new RectangleF(inner.X - inner.Width * 0.2f, inner.Y - inner.Height * 0.25f, inner.Width * 1.4f, inner.Height * 0.75f);
                        gp.AddEllipse(glow);
                        using (PathGradientBrush pg = new PathGradientBrush(gp))
                        {
                            pg.CenterColor = Night ? Color.FromArgb(120, 255, 214, 150) : Color.FromArgb(110, 255, 250, 235);
                            pg.SurroundColors = new Color[] { Color.FromArgb(0, 255, 240, 220) };
                            g.SetClip(inner);
                            g.FillPath(pg, gp);
                            g.ResetClip();
                        }
                    }
                    // 內側陰影（凹進去的感覺）
                    using (LinearGradientBrush s1 = new LinearGradientBrush(new RectangleF(inner.X, inner.Y, inner.Width, 3 * U + 1), Color.FromArgb(90, 40, 20, 5), Color.FromArgb(0, 40, 20, 5), 90f))
                        g.FillRectangle(s1, inner.X, inner.Y, inner.Width, 3 * U);
                    using (LinearGradientBrush s2 = new LinearGradientBrush(new RectangleF(inner.X, inner.Y, 2 * U + 1, inner.Height), Color.FromArgb(70, 40, 20, 5), Color.FromArgb(0, 40, 20, 5), 0f))
                        g.FillRectangle(s2, inner.X, inner.Y, 2 * U, inner.Height);
                    if (i == 0 && Pik) DrawFlowerBed(g, c);
                    else if (i == 0) DrawPedestal(g, c, panel);
                    // 層板（公仔站的地方）＋名牌那條
                    RectangleF board = new RectangleF(c.X - U, c.Bottom - plateH, c.Width + 2 * U, plateH);
                    using (LinearGradientBrush lb = new LinearGradientBrush(board, w3, w1, 90f)) g.FillRectangle(lb, board);
                    using (Pen edge = new Pen(Color.FromArgb(Night ? 60 : 110, 255, 235, 205), Math.Max(1f, U * 0.4f))) g.DrawLine(edge, board.X, board.Y + 0.5f, board.Right, board.Y + 0.5f);
                    // 名牌
                    string name = pet == null ? (i == 0 && Pik ? "★ 休息花" : "？") : (i == 0 ? "★ " + pet.P.Name : pet.P.Name);
                    using (Font f = new Font("Microsoft JhengHei UI", (float)Math.Max(9, 6.6 * k), FontStyle.Bold, GraphicsUnit.Pixel))
                    {
                        SizeF ts = g.MeasureString(name, f);
                        float pw = Math.Min(c.Width - 2 * U, ts.Width + 3 * U), ph = plateH - 1.6f * U;
                        RectangleF pr = new RectangleF(c.X + (c.Width - pw) / 2, c.Bottom - plateH + 0.9f * U, pw, ph);
                        using (GraphicsPath pp = RoundRect(pr, U * 0.8f))
                        using (LinearGradientBrush brass = new LinearGradientBrush(pr, i == 0 ? C(0xF6D77A) : C(0xEBCB7E), i == 0 ? C(0xC08A2C) : C(0xB48A45), 90f))
                        using (Pen rim = new Pen(Color.FromArgb(160, 90, 60, 15), 1f))
                        {
                            g.FillPath(brass, pp);
                            g.DrawPath(rim, pp);
                        }
                        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
                        using (StringFormat sf = new StringFormat())
                        using (SolidBrush tb = new SolidBrush(C(0x4A3010)))
                        {
                            sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center; sf.Trimming = StringTrimming.None;
                            g.DrawString(name, f, tb, new RectangleF(pr.X - 4, pr.Y + 0.5f, pr.Width + 8, pr.Height), sf);
                        }
                    }
                }
                // 左右小格和高格之間的隔板線
                using (Pen dk = new Pen(Color.FromArgb(90, 30, 15, 5), 1f))
                    g.DrawLine(dk, cells[0].X - div / 2f, crown, cells[0].X - div / 2f, H - baseH);
            }
        }


        // ---- 天線寶寶一櫃的格子：藍天、綠色小山丘、小花；大格有太陽寶寶（晚上下山）----
        float HillTop(RectangleF inner, bool tall) { return inner.Bottom - inner.Height * (tall ? 0.30f : 0.27f); }
        void DrawHills(Graphics g, RectangleF inner, bool tall)
        {
            GraphicsState st = g.Save();
            g.SetClip(inner);
            Color sky1 = Night ? C(0x4A3A6A) : C(0xB8E0FF), sky2 = Night ? C(0xA8707A) : C(0xEEF8FF);
            using (LinearGradientBrush sb = new LinearGradientBrush(inner, sky1, sky2, 90f)) g.FillRectangle(sb, inner);
            float hy = HillTop(inner, tall);
            Color h1 = Night ? C(0x557E4C) : C(0x92D46C), h2 = Night ? C(0x3A5C36) : C(0x66B248), rim = Night ? C(0x74A066) : C(0xC0EC98);
            // 後面一座淡淡的
            using (SolidBrush b = new SolidBrush(Mix(h1, sky2, 0.5))) g.FillEllipse(b, inner.X - inner.Width * 0.55f, hy - inner.Height * 0.07f, inner.Width * 1.25f, inner.Height * 0.5f);
            RectangleF hill = new RectangleF(inner.X - inner.Width * 0.25f, hy, inner.Width * 1.5f, inner.Height * 0.62f);
            using (LinearGradientBrush hb = new LinearGradientBrush(new RectangleF(hill.X, hill.Y - 1, hill.Width, hill.Height + 2), h1, h2, 90f)) g.FillEllipse(hb, hill);
            using (Pen rp = new Pen(rim, Math.Max(1f, U * 0.5f))) g.DrawArc(rp, hill, 215, 110);
            // 小花（像素點）
            Random r = new Random(tall ? 3 : 11);
            Color[] fl = { Color.White, C(0xFFD84A), C(0xFF8FB0), C(0xE8E0FF) };
            float u = Math.Max(1f, U * 0.6f), a = hill.Width / 2, bb = hill.Height / 2, cxh = hill.X + a, cyh = hill.Y + bb;
            int n = tall ? 7 : 4;
            for (int i = 0; i < n; i++)
            {
                float fx = inner.X + (float)(0.08 + 0.84 * (i + r.NextDouble() * 0.8) / n) * inner.Width;
                double q = (fx - cxh) / a; if (Math.Abs(q) >= 1) continue;
                float top = cyh - bb * (float)Math.Sqrt(1 - q * q);
                float fy = top + (float)(0.25 + r.NextDouble() * 0.55) * (inner.Bottom - top);
                Color c0 = fl[r.Next(fl.Length)];
                using (SolidBrush pb = new SolidBrush(Night ? Mix(c0, C(0x3A3050), 0.45) : c0))
                {
                    g.FillRectangle(pb, fx - u, fy, u, u); g.FillRectangle(pb, fx + u, fy, u, u);
                    g.FillRectangle(pb, fx, fy - u, u, u); g.FillRectangle(pb, fx, fy + u, u, u);
                }
                using (SolidBrush cb = new SolidBrush(Night ? C(0xB08A3C) : C(0xF5A623))) g.FillRectangle(cb, fx, fy, u, u);
            }
            g.Restore(st);
        }

        // 太陽寶寶：白天在天上笑，晚上一半沉到山丘後面
        void DrawSunBaby(Graphics g, Rectangle c, float cx, float sy, float sr)
        {
            RectangleF inner = new RectangleF(c.X, c.Y, c.Width, c.Height - plateH);
            float hy = HillTop(inner, true);
            float r = sr * 0.5f, y0 = Night ? hy - r * 0.15f : sy;
            if (Night) cx -= c.Width * 0.24f;   // 晚上在山丘邊慢慢下山（不要躲在圓台後面）
            GraphicsState st = g.Save();
            g.SetClip(new RectangleF(inner.X, inner.Y, inner.Width, hy + 1 - inner.Y));
            Color ray = Night ? Color.FromArgb(150, 255, 150, 90) : Color.FromArgb(170, 255, 214, 74);
            using (Pen rp = new Pen(ray, Math.Max(1.5f, U * 0.9f)))
                for (int i = 0; i < 12; i++)
                {
                    double ang = i * Math.PI / 6 + 0.13;
                    g.DrawLine(rp, cx + (float)Math.Cos(ang) * r * 1.25f, y0 + (float)Math.Sin(ang) * r * 1.25f, cx + (float)Math.Cos(ang) * r * 1.65f, y0 + (float)Math.Sin(ang) * r * 1.65f);
                }
            using (SolidBrush sb = new SolidBrush(Night ? C(0xF0965A) : C(0xFFD84A))) g.FillEllipse(sb, cx - r, y0 - r, 2 * r, 2 * r);
            float fr = r * 0.66f;
            using (SolidBrush fb = new SolidBrush(Night ? C(0xE8B892) : C(0xFBE3C6))) g.FillEllipse(fb, cx - fr, y0 - fr, 2 * fr, 2 * fr);
            float e = Math.Max(1.5f, fr * 0.16f);
            using (SolidBrush kb = new SolidBrush(C(0x5A3A2A)))
            {
                if (Night) using (Pen sp = new Pen(C(0x5A3A2A), Math.Max(1f, e * 0.6f))) { g.DrawLine(sp, cx - fr * 0.5f, y0 - fr * 0.15f, cx - fr * 0.2f, y0 - fr * 0.15f); g.DrawLine(sp, cx + fr * 0.2f, y0 - fr * 0.15f, cx + fr * 0.5f, y0 - fr * 0.15f); }
                else { g.FillEllipse(kb, cx - fr * 0.42f - e / 2, y0 - fr * 0.25f, e, e * 1.2f); g.FillEllipse(kb, cx + fr * 0.42f - e / 2, y0 - fr * 0.25f, e, e * 1.2f); }
            }
            using (Pen mp = new Pen(C(0xC0504A), Math.Max(1f, e * 0.6f))) g.DrawArc(mp, cx - fr * 0.35f, y0 - fr * 0.05f, fr * 0.7f, fr * 0.55f, 20, 140);
            using (SolidBrush pk = new SolidBrush(Color.FromArgb(110, 255, 130, 130))) { g.FillEllipse(pk, cx - fr * 0.78f, y0 + fr * 0.1f, fr * 0.3f, fr * 0.2f); g.FillEllipse(pk, cx + fr * 0.48f, y0 + fr * 0.1f, fr * 0.3f, fr * 0.2f); }
            g.Restore(st);
        }

        // 高格：最愛站的小圓台＋背板上淡淡的大星星
        void DrawPedestal(Graphics g, Rectangle c, Color panel)
        {
            float cx = c.X + c.Width / 2f, ph = PedH(), floor = c.Bottom - plateH, top = floor - ph;
            float pw = c.Width * 0.62f, eh = 4 * U;
            // 星星
            PointF[] star = new PointF[10];
            float sr = c.Width * 0.36f, sy = c.Y + (top - c.Y) * 0.42f;
            for (int i = 0; i < 10; i++)
            {
                double a = -Math.PI / 2 + i * Math.PI / 5, rr = i % 2 == 0 ? sr : sr * 0.45;
                star[i] = new PointF(cx + (float)(Math.Cos(a) * rr), sy + (float)(Math.Sin(a) * rr));
            }
            if (Tubby) DrawSunBaby(g, c, cx, sy, sr);
            else
                using (SolidBrush sb = new SolidBrush(Night ? Color.FromArgb(40, 255, 220, 150) : Color.FromArgb(70, 255, 236, 180))) g.FillPolygon(sb, star);
            // 圓台
            Color m1 = Night ? C(0x8A7A70) : C(0xFFF6E8), m2 = Night ? C(0x4E443F) : C(0xD9C7AE);
            RectangleF bodyR = new RectangleF(cx - pw / 2, top, pw, ph - U * 0.5f);
            using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(bodyR.X - 1, bodyR.Y, bodyR.Width + 2, bodyR.Height), m2, m1, 0f))
            {
                ColorBlend cb = new ColorBlend();
                cb.Colors = new Color[] { m2, m1, m1, m2 };
                cb.Positions = new float[] { 0f, 0.35f, 0.55f, 1f };
                lb.InterpolationColors = cb;
                g.FillRectangle(lb, bodyR);
                g.FillEllipse(lb, bodyR.X, bodyR.Bottom - eh / 2, bodyR.Width, eh);
            }
            using (SolidBrush gold = new SolidBrush(Night ? C(0xB08A3C) : C(0xE2B550))) g.FillRectangle(gold, bodyR.X, top + eh * 0.45f, bodyR.Width, U * 0.9f);
            using (SolidBrush tp = new SolidBrush(Night ? C(0x9C8B80) : C(0xFFFBF3))) g.FillEllipse(tp, bodyR.X, top - eh / 2, bodyR.Width, eh);
            using (Pen rim = new Pen(Night ? C(0xB08A3C) : C(0xD9A944), Math.Max(1f, U * 0.5f))) g.DrawEllipse(rim, bodyR.X, top - eh / 2, bodyR.Width, eh);
        }

        // 每 0.1 秒左右重畫（公仔會呼吸、眨眼、晃一下）
        public void Render(Pet[] who, bool[] outNow, double t)
        {
            Bitmap b = Snapshot(who, outNow, t);
            W.Present(this, b, Area.X, Area.Y);
        }

        Bitmap cab;
        public Bitmap Snapshot(Pet[] who, bool[] outNow, double t)
        {
            if (fold <= 0.001) { Bitmap b0 = Cabinet(who, outNow, t); DrawTab(b0); return b0; }
            Bitmap full = Cabinet(who, outNow, t);
            if (cab == null || cab.Width != full.Width || cab.Height != full.Height) { if (cab != null) cab.Dispose(); cab = new Bitmap(full.Width, full.Height, PixelFormat.Format32bppArgb); }
            using (Graphics g = Graphics.FromImage(cab))
            {
                g.Clear(Color.Transparent);
                double e = fold * fold * (3 - 2 * fold);
                // 櫃子往下折、變淡
                if (e < 0.999)
                {
                    int h = (int)Math.Round(full.Height * (1 - e));
                    if (h > 0)
                    {
                        ColorMatrix cm = new ColorMatrix(); cm.Matrix33 = (float)(1 - e);
                        using (ImageAttributes ia = new ImageAttributes())
                        {
                            ia.SetColorMatrix(cm);
                            g.InterpolationMode = InterpolationMode.NearestNeighbor;
                            g.DrawImage(full, new Rectangle(0, full.Height - h, full.Width, h), 0, 0, full.Width, full.Height, GraphicsUnit.Pixel, ia);
                        }
                    }
                }
                // 蛋：慢慢出現、上半部蓋下來
                DrawEgg(g, t, e);
            }
            return cab;
        }

        // 收合鈕「－」（櫃子頂上右邊的小牌子）
        void DrawTab(Bitmap b)
        {
            using (Graphics g = Graphics.FromImage(b))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                Rectangle r = TabLocal();
                using (GraphicsPath p = RoundRect(new RectangleF(r.X, r.Y + 1, r.Width, r.Height - 2), U))
                using (SolidBrush bg2 = new SolidBrush(Color.FromArgb(220, 255, 246, 226)))
                using (Pen rim = new Pen(Color.FromArgb(160, 120, 80, 40), 1f)) { g.FillPath(bg2, p); g.DrawPath(rim, p); }
                using (Pen mp = new Pen(Color.FromArgb(0x8A, 0x5A, 0x2A), Math.Max(1.5f, U * 0.6f)))
                    g.DrawLine(mp, r.X + r.Width * 0.28f, r.Y + r.Height / 2f, r.X + r.Width * 0.72f, r.Y + r.Height / 2f);
            }
        }

        void DrawEgg(Graphics g, double t, double appear)
        {
            if (appear <= 0.02) return;
            int ps = EggPs;
            Rectangle er = EggLocal();
            // 搖一搖（有通知存著時搖比較大）
            double ang = 0;
            if (wobT > 0) ang = Math.Sin(wobT * 26) * (Attention > 0 ? 11 : 6) * Math.Min(1, wobT * 2);
            // 打開的程度：收合動畫的頭尾、吞公仔時裂開
            double open = Math.Max(Math.Max(0, 1 - appear) * 1.6, gulp > 0 ? Math.Sin(gulp / 0.5 * Math.PI) * 0.6 : 0);
            open = Math.Min(1, open);
            GraphicsState st = g.Save();
            g.TranslateTransform(er.X + er.Width / 2f, er.Bottom);
            g.RotateTransform((float)ang);
            g.TranslateTransform(-er.Width / 2f, -er.Height);
            int crack = 8;
            Dictionary<char, Color> pal = new Dictionary<char, Color>();
            pal['k'] = Color.FromArgb(0x6B, 0x4A, 0x2E); pal['c'] = Night ? Color.FromArgb(0xE6, 0xDA, 0xC4) : Color.FromArgb(0xFF, 0xF4, 0xDC);
            pal['s'] = Night ? Color.FromArgb(0xC2, 0xAE, 0x92) : Color.FromArgb(0xE8, 0xD3, 0xB0); pal['h'] = Color.White;
            pal['r'] = Color.FromArgb(0xD8, 0x4A, 0x4A); pal['o'] = Color.FromArgb(0xE7, 0x83, 0x6A); pal['b'] = Color.FromArgb(0x3D, 0x6B, 0xB3);
            pal['g'] = Color.FromArgb(0x25, 0xB3, 0xBA); pal['Y'] = Color.FromArgb(0xF5, 0xC8, 0x42);
            int alpha = (int)(255 * Math.Min(1, appear * 1.4));
            // 下半部
            for (int r = crack; r < EGG.Length; r++) DrawEggRow(g, r, 0, 0, ps, pal, alpha);
            // 上半部：打開時往上抬、往旁邊歪
            float lift = (float)(open * 7 * ps), tilt = (float)(open * 4 * ps);
            for (int r = 0; r < crack; r++) DrawEggRow(g, r, -tilt, -lift, ps, pal, alpha);
            // 裂痕
            if (open > 0.05 || appear < 0.95)
                using (Pen cp = new Pen(Color.FromArgb(alpha, 0x6B, 0x4A, 0x2E), Math.Max(1.5f, ps * 0.45f)))
                {
                    PointF[] z = new PointF[8];
                    for (int i = 0; i < 8; i++) z[i] = new PointF(2 * ps + i * 2 * ps, (crack + (i % 2 == 0 ? 0f : 0.7f)) * ps);
                    g.DrawLines(cp, z);
                }
            // 午餐時間：小餐巾
            if (Lunch)
                using (SolidBrush nb = new SolidBrush(Color.FromArgb(alpha, 255, 255, 255)))
                using (SolidBrush ck = new SolidBrush(Color.FromArgb(alpha, 0xE2, 0x4A, 0x4A)))
                {
                    PointF[] tri = { new PointF(5 * ps, 9 * ps), new PointF(13 * ps, 9 * ps), new PointF(9 * ps, 14 * ps) };
                    g.FillPolygon(nb, tri);
                    using (Pen np = new Pen(Color.FromArgb(alpha, 0xB8, 0xA8, 0x90), Math.Max(1f, ps * 0.3f))) g.DrawPolygon(np, tri);
                    for (int i = 0; i < 4; i++) g.FillRectangle(ck, (6 + i * 2) * ps, 9 * ps, ps, ps);
                    g.FillRectangle(ck, 8 * ps, 11 * ps, ps, ps); g.FillRectangle(ck, 10 * ps, 11 * ps, ps, ps);
                }
            g.Restore(st);
            // 小紅點：有存著的通知／快到的提醒
            if (Attention > 0 && appear > 0.9)
            {
                float d = 6 * U, bx = er.Right - d * 0.8f, by = er.Y + d * 0.2f;
                using (SolidBrush rb = new SolidBrush(Color.FromArgb(0xE2, 0x3B, 0x3B))) g.FillEllipse(rb, bx, by, d, d);
                using (Pen wp = new Pen(Color.White, 1.5f)) g.DrawEllipse(wp, bx, by, d, d);
                using (Font f = new Font("Arial", d * 0.62f, FontStyle.Bold, GraphicsUnit.Pixel))
                using (StringFormat sf = new StringFormat())
                {
                    sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center;
                    g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
                    g.DrawString(Attention > 9 ? "9+" : Attention.ToString(), f, Brushes.White, new RectangleF(bx, by + 0.5f, d, d), sf);
                }
            }
            if (Hot && appear > 0.9)
                using (Pen hp = new Pen(Over ? Color.FromArgb(230, 255, 120, 165) : Color.FromArgb(170, 255, 200, 120), Math.Max(2f, U)))
                    g.DrawEllipse(hp, er.X - 2 * U, er.Y - 2 * U, er.Width + 4 * U, er.Height + 4 * U);
            // 番茄／安靜徽章掛在蛋上面
            int left = w.FocusLeft(), qleft = w.QuietLeft();
            float bcx = er.X + er.Width / 2f, bcy = er.Y - 3 * U;
            if (left >= 0 && qleft >= 0) { DrawBadgeAt(g, qleft, true, bcx, bcy); DrawBadgeAt(g, left, false, bcx, bcy - 8 * U); }
            else if (left >= 0) DrawBadgeAt(g, left, false, bcx, bcy);
            else if (qleft >= 0) DrawBadgeAt(g, qleft, true, bcx, bcy);
        }

        void DrawEggRow(Graphics g, int r, float dx, float dy, int ps, Dictionary<char, Color> pal, int alpha)
        {
            string row = EGG[r];
            for (int c = 0; c < row.Length; c++)
            {
                char ch = row[c]; if (ch == '.') continue;
                Color col = pal[ch];
                using (SolidBrush b = new SolidBrush(Color.FromArgb(alpha, col))) g.FillRectangle(b, dx + c * ps, dy + r * ps, ps, ps);
            }
        }

        Bitmap Cabinet(Pet[] who, bool[] outNow, double t)
        {
            string key = Night + "|" + Tubby + "|" + Pik + "|" + Orig + "|" + Area.Size;
            for (int i = 0; i < 4; i++) key += "|" + (who[i] == null ? "-" : who[i].P.Id);
            if (key != bgKey || bg == null) { bgKey = key; BuildBg(who, outNow); }
            if (bmp == null || bmp.Width != bg.Width || bmp.Height != bg.Height) { if (bmp != null) bmp.Dispose(); bmp = new Bitmap(bg.Width, bg.Height, PixelFormat.Format32bppArgb); }
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.Transparent);
                g.DrawImageUnscaled(bg, 0, 0);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                for (int i = 0; i < 4; i++)
                {
                    Rectangle c = cells[i];
                    Pet pet = who[i];
                    int ps = FitPs(i, pet);
                    int fx = c.X + c.Width / 2, fy = c.Bottom - plateH - U - (i == 0 ? PedH() : 0);
                    g.SetClip(new Rectangle(c.X, c.Y, c.Width, c.Height - plateH));
                    if (pet == null && i == 0 && Pik) DrawRestFlower(g, c, t);
                    else if (pet == null) DrawUnknown(g, fx, fy, ps);
                    else if (outNow[i]) { pet.DrawGhost(g, fx, fy, ps, Night); DrawAway(g, c, ps); }
                    else pet.DrawOnShelf(g, fx, fy, ps, c, t);
                    g.ResetClip();
                    if (hover == i && pet != null)
                        using (Pen hp = new Pen(Color.FromArgb(150, 255, 236, 160), Math.Max(2f, U * 0.7f)))
                            g.DrawRectangle(hp, c.X + 1, c.Y + 1, c.Width - 3, c.Height - plateH - 2);
                }
                // 玻璃門的反光
                using (Pen gl = new Pen(Color.FromArgb(Night ? 14 : 26, 255, 255, 255), 3 * U))
                    for (int i = 0; i < 4; i++)
                    {
                        Rectangle c = cells[i];
                        g.SetClip(new Rectangle(c.X, c.Y, c.Width, c.Height - plateH));
                        g.DrawLine(gl, c.X + c.Width * 0.15f, c.Bottom, c.X + c.Width * 0.95f, c.Y - c.Width * 0.2f);
                        g.ResetClip();
                    }
                int left = w.FocusLeft(), qleft = w.QuietLeft();
                if (left >= 0 && qleft >= 0) { DrawBadge(g, left, false, -1); DrawBadge(g, qleft, true, 1); }
                else if (left >= 0) DrawBadge(g, left, false, 0);
                else if (qleft >= 0) DrawBadge(g, qleft, true, 0);
                if (Hot)
                    using (Pen hp = new Pen(Over ? Color.FromArgb(230, 255, 120, 165) : Color.FromArgb(170, 255, 200, 120), Math.Max(2f, U)))
                    using (GraphicsPath p = RoundRect(new RectangleF(U * 0.5f, U * 0.5f, Area.Width - U - 2, Area.Height - U - 2), 3 * U))
                        g.DrawPath(hp, p);
            }
            return bmp;
        }

        void DrawBadge(Graphics g, int left, bool quiet, int side)
        {
            float cxb = side == 0 ? Area.Width / 2f : (side < 0 ? Area.Width * 0.28f : Area.Width * 0.72f);
            DrawBadgeAt(g, left, quiet, cxb, crown * 0.5f);
        }

        // 小徽章：番茄（專注）或月亮＋zz（安靜）＋剩幾分鐘，中心在 (cxb, cyb)
        void DrawBadgeAt(Graphics g, int left, bool quiet, float cxb, float cyb)
        {
            string[] tom = quiet ? new string[] { "..yyy...", ".yy..zzz", "yy....z.", "yy...zzz", "yy......", ".yy.....", "..yyy...", "........" }
                                 : new string[] { "...gg...", "..gggg..", ".rrrrrr.", "rrhrrrrr", "rhrrrrrr", "rrrrrrrr", ".rrrrrr.", "..rrrr.." };
            int ps = Math.Max(2, U * 2 / 3);
            string txt = left + " 分";
            using (Font f = new Font("Microsoft JhengHei UI", (float)Math.Max(10, 7.5 * k), FontStyle.Bold, GraphicsUnit.Pixel))
            {
                SizeF ts = g.MeasureString(txt, f);
                float bw = 8 * ps + ts.Width + 3 * U, bh = Math.Max(8 * ps, ts.Height) + U;
                RectangleF br = new RectangleF(cxb - bw / 2f, cyb - bh / 2f, bw, bh);
                using (GraphicsPath p = RoundRect(br, bh / 2f))
                using (SolidBrush bg2 = new SolidBrush(quiet ? Color.FromArgb(235, 44, 48, 78) : Color.FromArgb(235, 255, 248, 236)))
                using (Pen rim = new Pen(quiet ? Color.FromArgb(180, 150, 160, 230) : Color.FromArgb(180, 200, 80, 60), 1f)) { g.FillPath(bg2, p); g.DrawPath(rim, p); }
                for (int r = 0; r < 8; r++)
                    for (int c = 0; c < 8; c++)
                    {
                        char ch = tom[r][c]; if (ch == '.') continue;
                        using (SolidBrush b = new SolidBrush(ch == 'g' ? Color.FromArgb(0x3C, 0xA0, 0x48) : (ch == 'h' ? Color.FromArgb(0xFF, 0x9A, 0x8A) : (ch == 'y' ? Color.FromArgb(0xFF, 0xDB, 0x6E) : (ch == 'z' ? Color.FromArgb(0xC8, 0xD0, 0xFF) : Color.FromArgb(0xE2, 0x3B, 0x2E))))))
                            g.FillRectangle(b, br.X + U + c * ps, br.Y + (bh - 8 * ps) / 2f + r * ps, ps, ps);
                    }
                using (SolidBrush tb = new SolidBrush(quiet ? Color.FromArgb(0xE6, 0xE8, 0xFF) : Color.FromArgb(0x8A, 0x2A, 0x1E)))
                    g.DrawString(txt, f, tb, br.X + U * 1.5f + 8 * ps, br.Y + (bh - ts.Height) / 2f);
            }
        }

        // 空格：淡淡的問號剪影
        void DrawUnknown(Graphics g, int fx, int fy, int ps)
        {
            string[] sil = { "...kkkkkk...", "..kkkkkkkk..", ".kkkkkkkkkk.", ".kkkkkkkkkk.", ".kkkkkkkkkk.", ".kkkkkkkkkk.", "..kkkkkkkk..", "...kkkkkk...",
                "...kkkkkk...", "..kkkkkkkk..", ".kkkkkkkkkk.", ".kkkkkkkkkk.", "..kkkkkkkk..", "..kkk..kkk..", "..kkk..kkk..", "..kkk..kkk.." };
            using (SolidBrush b = new SolidBrush(Color.FromArgb(Night ? 40 : 34, 60, 40, 20)))
                for (int r = 0; r < 16; r++)
                    for (int c = 0; c < 12; c++)
                        if (sil[r][c] != '.') g.FillRectangle(b, fx - 6 * ps + c * ps, fy - 16 * ps + r * ps, ps, ps);
            using (Font f = new Font("Arial", 7 * ps, FontStyle.Bold, GraphicsUnit.Pixel))
            using (SolidBrush b = new SolidBrush(Color.FromArgb(Night ? 70 : 80, 255, 255, 255)))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center;
                g.DrawString("?", f, b, new RectangleF(fx - 6 * ps, fy - 16 * ps, 12 * ps, 9 * ps), sf);
            }
        }

        // 外出中：空的展示台＋掛著的小牌子
        void DrawAway(Graphics g, Rectangle c, int ps)
        {
            int fx = c.X + c.Width / 2, fy = c.Bottom - plateH - U;
            using (SolidBrush st = new SolidBrush(Color.FromArgb(70, 80, 50, 25)))
                g.FillEllipse(st, fx - 5 * ps, fy - ps, 10 * ps, 2 * ps);
            float tagW = Math.Max(13 * ps * 0.9f, 15 * U), tagH = Math.Max(4.6f * ps, 5.2f * U), ty = c.Y + c.Height * 0.32f;
            using (Pen str = new Pen(Color.FromArgb(150, 110, 80, 50), 1f))
            {
                g.DrawLine(str, fx - tagW * 0.3f, c.Y + 2, fx - tagW * 0.25f, ty);
                g.DrawLine(str, fx + tagW * 0.3f, c.Y + 2, fx + tagW * 0.25f, ty);
            }
            RectangleF tr = new RectangleF(fx - tagW / 2, ty, tagW, tagH);
            using (GraphicsPath p = RoundRect(tr, ps))
            using (SolidBrush b = new SolidBrush(Night ? Color.FromArgb(235, 70, 58, 80) : Color.FromArgb(240, 255, 250, 238)))
            using (Pen rim = new Pen(Color.FromArgb(160, 150, 110, 70), 1f))
            {
                g.FillPath(b, p); g.DrawPath(rim, p);
            }
            using (Font f = new Font("Microsoft JhengHei UI", (float)Math.Max(10, 2.7 * ps), FontStyle.Bold, GraphicsUnit.Pixel))
            using (SolidBrush tb = new SolidBrush(Night ? Color.FromArgb(0xFF, 0xE6, 0xC8) : Color.FromArgb(0x8A, 0x5A, 0x2A)))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center;
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
                g.DrawString("外出中", f, tb, new RectangleF(tr.X - 6, tr.Y, tr.Width + 12, tr.Height), sf);
            }
        }
    }

    partial class Pet
    {
        int ShelfSeed { get { return P.Id.Length * 7 + (int)P.Id[0]; } }

        // 在櫃子格子裡：小小地動（呼吸、眨眼、各自的招牌小動作）
        public void DrawOnShelf(Graphics g, int fx, int fy, int ps, Rectangle cell, double t)
        {
            double tt = t + ShelfSeed * 0.37;
            bool blink = (tt % 4.3) < 0.14;
            int breathe = (tt * 0.8 % 1) < 0.5 ? 0 : 1;
            int bx = fx - 6 * ps, by = fy - 16 * ps + breathe;
            bool flip = (Math.Floor(tt / 9) % 2) == 1;
            string[] head = (string[])A("HEAD").Clone();
            Fr f;
            switch (P.Id)
            {
                case "spidey":
                    {
                        // 從格子頂端垂一條絲倒吊著晃；偶爾跳下來擺個噴絲姿勢
                        bool dangle = (tt % 11) < 8;
                        if (blink) ReplaceFace(head, "SLEEPY");
                        string[] rows = Pal.Stack(head, A(dangle ? "BODY" : "ARMS_UP"), A("LEGS_A"));   // Spidey 剛好 16 列
                        if (Night) { char[] ch = rows[10].ToCharArray(); if (ch[5] == 'k' && ch[6] == 'k') { ch[5] = 'w'; ch[6] = 'w'; rows[10] = new string(ch); } }
                        if (dangle)
                        {
                            int sway = (int)Math.Round(Math.Sin(tt * 1.3) * ps * 0.8);
                            int topY = Math.Max(cell.Y + 3 * ps, fy - 19 * ps) + (int)Math.Round(Math.Sin(tt * 2.1) * ps * 0.7);
                            using (Pen silk = new Pen(Night ? Color.FromArgb(200, 150, 140, 210) : Color.FromArgb(220, 255, 255, 255), Math.Max(1f, ps * 0.4f)))
                                g.DrawLine(silk, fx, cell.Y, fx + sway, topY + 2);
                            DrawPix(g, rows, bx + sway, topY, ps, flip, true, true);
                        }
                        else
                        {
                            DrawPix(g, rows, bx, by, ps, flip, false, true);
                            using (Pen silk = new Pen(Color.FromArgb(200, 255, 255, 255), Math.Max(1f, ps * 0.4f)))
                                g.DrawLine(silk, bx + (flip ? 1 : 11) * ps, by + 8 * ps, flip ? cell.X + 2 : cell.Right - 2, cell.Y + 4);
                            DrawAccessories(g, bx, by, ps, flip, 0, true);
                        }
                        DrawShelfWeb(g, cell, ps);
                    }
                    break;
                case "po":
                    {
                        // 扶著停在旁邊的滑板車，跟車子一起前後搖
                        if (blink || Night && (tt % 5) < 2) ReplaceFace(head, "SLEEPY");
                        f = F(Pal.Stack(head, A("BODY"), A("LEGS_A"))); f.Tummy = true;
                        int rock = (int)Math.Round(Math.Sin(tt * 2.2) * ps * 0.6);
                        DrawAt(g, A("SCOOTER"), 3, 7, bx + rock, by - breathe, ps, !flip, false, true);
                        DrawPix(g, f.Rows, bx + rock - (f.Rows[0].Length - 12) / 2 * ps, by + (16 - f.Rows.Length) * ps, ps, flip, false, true);
                        DrawAccessories(g, bx + rock, by, ps, flip, f.AccDy, true);
                        DrawStatusIcon(g, TummyStatus(), bx + rock + 6 * ps, by + (int)((10.5 + f.AccDy) * ps), Math.Max(1, ps / 2), true);
                    }
                    break;
                case "stitch":
                    {
                        // 耳朵抖抖、壞壞地笑；晚上耳朵垂下來抱著烏克麗麗
                        string body = "BODY";
                        if (Night) { string[] ed = A("EARS_DOWN"); for (int i = 0; i < ed.Length; i++) head[i] = ed[i]; body = "ARMS_HUG"; if ((tt % 6) < 3) ReplaceFace(head, "SLEEPY"); }
                        else
                        {
                            if ((tt % 1.7) < 0.35) { string[] eu = A("EARS_UP"); for (int i = 0; i < eu.Length; i++) head[i] = eu[i]; }
                            if ((tt % 7) < 3) ReplaceFace(head, "GRIN");
                            if (blink) ReplaceFace(head, "SLEEPY");
                        }
                        string[] rows = Pal.Stack(head, A(body), A("LEGS_A"));
                        DrawPix(g, rows, bx - (rows[0].Length - 12) / 2 * ps, by + (16 - rows.Length) * ps, ps, flip, false, true);
                        DrawAccessories(g, bx, by, ps, flip, 0, true);
                        if (Night) DrawAt(g, A("UKE"), 5, 8, bx, by, ps, flip, false, true);
                    }
                    break;
                case "hangyodon":
                    {
                        // 像海草一樣在水裡輕輕搖、吐泡泡；晚上睡在泡泡裡
                        if (Night || blink) ReplaceFace(head, "SLEEPY");
                        string[] rows = Pal.Stack(head, A(Night ? "BODY" : ((tt % 6) < 1.2 ? "POUT" : "BODY")), A(Night ? "LEGS_SIT" : "LEGS_A"));
                        int sway = (int)Math.Round(Math.Sin(tt * 1.4) * ps * 0.8);
                        int lx = bx - (rows[0].Length - 12) / 2 * ps + sway;
                        if (Night) DrawSleepBubble(g, bx, by, ps, false);
                        DrawPix(g, rows, lx, by + (16 - rows.Length) * ps, ps, flip, false, true);
                        DrawAccessories(g, bx + sway, by, ps, flip, 0, !Night);
                        if (Night) DrawSleepBubble(g, bx, by, ps, true);
                        // 泡泡從嘴巴冒上去
                        using (Pen bp = new Pen(Color.FromArgb(190, 150, 215, 255), Math.Max(1f, ps * 0.35f)))
                            for (int i = 0; i < 3; i++)
                            {
                                double ph = (tt * 0.45 + i / 3.0) % 1;
                                float r = (float)(ps * (0.5 + ph * 0.9)), px = fx + sway + (float)(Math.Sin(ph * 9 + i) * ps) + (flip ? -3 : 3) * ps, py = by + 8 * ps - (float)(ph * 9 * ps);
                                if (py > cell.Y + r) g.DrawEllipse(bp, px - r, py - r, 2 * r, 2 * r);
                            }
                    }
                    break;
                case "tinky": case "dipsy": case "laalaa":
                    DrawTubbyShelf(g, head, fx, bx, by, ps, flip, tt, blink);
                    break;
                case "pkred": case "pkyellow": case "pkblue":
                    DrawPikShelf(g, fx, bx, by, ps, flip, tt, blink, cell);
                    break;
                case "boba": case "coffee": case "onigiri": case "sticky":
                    DrawOrigShelf(g, fx, bx, by, ps, flip, tt, blink, cell);
                    break;
                default:
                    if (blink) ReplaceFace(head, "SLEEPY");
                    { string[] rows = Pal.Stack(head, A("BODY"), A("LEGS_A")); DrawPix(g, rows, bx - (rows[0].Length - 12) / 2 * ps, by + (16 - rows.Length) * ps, ps, flip, false, true); }
                    DrawAccessories(g, bx, by, ps, flip, 0, true);
                    break;
            }
            // 午餐時間：櫃子裡的公仔也拿著午餐
            if (w.Lunch && !(Is("spidey") && (tt % 11) < 8)) DrawLunchShelf(g, bx, by, ps, flip);
            // 剛回櫃子：一圈小星星
            if (ShelfFx < 1)
            {
                int sp = Math.Max(1, ps / 2);
                for (int i = 0; i < 6; i++)
                {
                    double a = i * Math.PI / 3 + ShelfFx * 2, rr = (4 + ShelfFx * 7) * ps;
                    if (Math.Floor(ShelfFx * 18 + i) % 2 == 0)
                        DrawPix(g, STAR, (int)(fx + Math.Cos(a) * rr) - sp, (int)(fy - 8 * ps + Math.Sin(a) * rr * 0.8) - sp, sp, false, false, false);
                }
            }
        }

        void ReplaceFace(string[] head, string face)
        {
            if (!P.Art.ContainsKey(face)) return;
            string[] fr = A(face);
            for (int i = 0; i < fr.Length && P.FaceRow + i < head.Length; i++) if (fr[i].Length == head[P.FaceRow + i].Length) head[P.FaceRow + i] = fr[i];
        }

        // Spidey 回櫃子時在格子左上角織一張小圓網（ShelfFx 0→1 織完）
        void DrawShelfWeb(Graphics g, Rectangle cell, int ps)
        {
            double prog = Math.Min(1, ShelfFx * 1.3);
            float cx = cell.X + 1, cy = cell.Y + 1, R0 = 11 * ps;
            int spokes = 6;
            using (Pen sh = new Pen(Color.FromArgb(70, 40, 30, 60), Math.Max(1.6f, ps * 0.55f)))
            using (Pen silk = new Pen(Night ? Color.FromArgb(220, 214, 204, 255) : Color.FromArgb(235, 255, 255, 255), Math.Max(1f, ps * 0.35f)))
            {
                Pen[] pens = { sh, silk };
                foreach (Pen p in pens)
                {
                    for (int i = 0; i < spokes; i++)
                    {
                        double a = Math.PI / 2 * i / (spokes - 1);
                        g.DrawLine(p, cx, cy, cx + (float)(Math.Cos(a) * R0 * Math.Min(1, prog * 2)), cy + (float)(Math.Sin(a) * R0 * Math.Min(1, prog * 2)));
                    }
                    int rings = 4, shown = (int)Math.Floor(rings * Math.Max(0, prog * 2 - 1) + 0.001);
                    for (int r = 0; r < shown; r++)
                    {
                        double rr = R0 * (0.3 + 0.7 * (r + 1) / rings);
                        for (int i = 0; i + 1 < spokes; i++)
                        {
                            double a1 = Math.PI / 2 * i / (spokes - 1), a2 = Math.PI / 2 * (i + 1) / (spokes - 1), am = (a1 + a2) / 2;
                            PointF p1 = new PointF(cx + (float)(Math.Cos(a1) * rr), cy + (float)(Math.Sin(a1) * rr));
                            PointF p2 = new PointF(cx + (float)(Math.Cos(a2) * rr), cy + (float)(Math.Sin(a2) * rr));
                            PointF pm = new PointF(cx + (float)(Math.Cos(am) * rr * 0.9), cy + (float)(Math.Sin(am) * rr * 0.9));
                            g.DrawLine(p, p1, pm); g.DrawLine(p, pm, p2);
                        }
                    }
                }
            }
        }
    }

    // ================= World：整個桌面共用的東西 =================
    // 一個 30ms 計時器帶全部公仔；一次視窗掃描大家共用；櫃子、球、煙火、Claude／Codex 監看、pipe 都在這裡。
    partial class World : Form
    {
        public static string DataDir = DataDirInit();
        static string DataDirInit()
        {
            string d = Environment.GetEnvironmentVariable("DESKPALS_DATA_DIR");
            if (string.IsNullOrEmpty(d)) d = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DeskPals");
            return d;
        }

        readonly string pipeName;
        string defaultPet;
        string lineup = Pal.Classic;                  // 現在是哪一櫃
        public bool TubbyLineup { get { return lineup == Pal.Teletubbies; } }
        public readonly int S;
        public readonly double k;
        readonly Random rnd = new Random();
        public readonly List<Pet> Pets = new List<Pet>();
        readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
        readonly Stopwatch clock = Stopwatch.StartNew();
        public double Now;
        double lastT;

        Screen[] screens = Screen.AllScreens;
        public List<WinInfo> Wins = new List<WinInfo>();
        public Dictionary<IntPtr, WinInfo> Cands = new Dictionary<IntPtr, WinInfo>();
        public List<Plat> Plats = new List<Plat>();
        HashSet<IntPtr> known;
        IntPtr lastFg;

        ShelfForm shelf;
        FxForm fx;
        readonly List<CobwebForm> webs = new List<CobwebForm>();
        readonly List<Client> clients = new List<Client>();
        bool closing;

        public bool Night, Hidden;
        public string SeasonNow = "";
        string birthday = "";
        int nightChecked = -1;
        int forceNight = Environment.GetEnvironmentVariable("SPIDEY_FORCE_DARK") == "1" ? 1 : -1;
        bool userHidden, sharing, fsNow;
        public double CursorStill;
        Point lastCursor;
        double nextScan, newWinCd = 3, fgCd = 8, danceCd = 30, waitCd, shelfT, usageT, proxT = 5;
        int typingStreak;
        bool sysIdle;
        double restMin = 50, idleMin = 5, sessionStart;

        Pet active;                                   // 最近一隻被放出來的（側邊欄跟著他）
        readonly List<Pet> outOrder = new List<Pet>();
        string favPin = "";
        readonly Dictionary<string, double> usage = new Dictionary<string, double>();

        public World(string pipeName, string pet, string lineupArg)
        {
            this.pipeName = pipeName;
            // 哪一櫃：有傳就用（並記住），沒傳（開機捷徑）就照上次的
            lineup = Pal.NormLineup(string.IsNullOrEmpty(lineupArg) ? StartLineup() : lineupArg);   // 全新安裝：續命小隊（DeskPals.Original.cs）
            if (!string.IsNullOrEmpty(lineupArg)) WriteText("lineup.txt", lineup);
            defaultPet = DefaultPetFor(pet);
            ShowInTaskbar = false;
            float dpi = 96;
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) dpi = g.DpiX;
            S = Math.Max(3, (int)Math.Round(4 * dpi / 96.0));
            k = S / 3.0;
            int seed = Environment.TickCount;
            foreach (Pal p in Pal.Lineup(lineup)) Pets.Add(new Pet(this, p, S, seed++));
        }

        string DefaultPetFor(string pet)
        {
            foreach (string id in Pal.LineupIds(lineup)) if (id == pet) return pet;
            return lineup == Pal.Teletubbies ? "po" : (lineup == Pal.Pikmin ? "pkred" : (lineup == Pal.Original ? "boba" : "spidey"));
        }

        // 每一櫃各自記：誰在外面、最近一隻、最愛（經典一櫃沿用原本的檔名）
        string LF(string name) { return lineup == Pal.Classic ? name : Path.GetFileNameWithoutExtension(name) + "-" + lineup + Path.GetExtension(name); }

        // 換一櫃：大家先收起來（不吵）、換成另一櫃的公仔，照那一櫃上次的狀態放出來（或指定的那隻）
        public void SwitchLineup(string id, string pet)
        {
            id = Pal.NormLineup(id);
            if (id == lineup)
            {
                Pet want = Get(pet);
                if (want != null) SelectOnly(want);
                return;
            }
            AbortScene();
            ClearProps();
            if (BallOn) { BallOn = false; Holder = null; if (ballF != null) ballF.Hide(); }
            SaveUsage(); SaveOut();
            current = null;
            foreach (Pet p in Pets) { p.Out = false; p.CloseForms(); }
            foreach (CobwebForm f in webs) f.Close();
            webs.Clear();
            Pets.Clear(); outOrder.Clear(); active = null; lastBroadcast = "";
            lineup = id;
            WriteText("lineup.txt", lineup);
            defaultPet = DefaultPetFor(pet);
            usage.Clear();
            LoadState();
            int seed = Environment.TickCount;
            foreach (Pal p in Pal.Lineup(lineup)) Pets.Add(new Pet(this, p, S, seed++));
            RenderShelf();
            List<string> ids = Get(pet) != null ? new List<string>(new string[] { pet }) : LoadOutIds();
            double delay = 0.35;
            foreach (string oid in ids)
            {
                Pet pp = Get(oid);
                if (pp == null) continue;
                Later(delay, delegate { BringOut(pp, true); });
                delay += 0.5;
            }
            active = Get(ids.Count > 0 ? ids[ids.Count - 1] : defaultPet) ?? Get(defaultPet);
            if (ids.Count == 0 && active != null) active.Say(OrigLineup ? "續命小隊，報到！🥤" : (TubbyLineup ? "Eh-oh! 天線寶寶一櫃 ☀" : "經典一櫃回來囉！"), 2.4);
            Broadcast();
            lock (clients) foreach (Client c in clients) Send(c, "lineup " + lineup + "\n");   // 在桌面換櫃（小屋、設定）：VS Code 跟著改設定
            App.Log("lineup " + lineup);
        }

        // 只給預覽用：不開任何視窗
        public World(int S, string lineupId)
        {
            pipeName = ""; lineup = Pal.NormLineup(lineupId); defaultPet = "po"; this.S = S; k = S / 3.0;
            int seed = 1;
            foreach (Pal p in Pal.Lineup(lineup)) Pets.Add(new Pet(this, p, S, seed++));
        }

        public World(int S)
        {
            pipeName = ""; defaultPet = "spidey"; this.S = S; k = S / 3.0;
            int seed = 1;
            foreach (Pal p in Pal.Lineup(Pal.Classic)) Pets.Add(new Pet(this, p, S, seed++));
        }

        public Pet Get(string id) { foreach (Pet p in Pets) if (p.P.Id == id) return p; return null; }

        // ================= 啟動 =================
        public void Start()
        {
            IntPtr h = Handle; // 建立視窗代碼（收快速鍵、BeginInvoke 用）
            if (h == IntPtr.Zero) App.Log("no handle");
            try { Directory.CreateDirectory(DataDir); } catch { }
            Migrate();
            LoadState();
            LoadFeatures();
            LoadMode();
            SeasonNow = Season();
            Night = NightNow();
            nightChecked = DateTime.Now.Minute;
            shelf = new ShelfForm(this, S);
            shelf.Night = Night;
            shelf.Collapsed = Single || ReadText("shelf-state.txt") == "egg";   // 只要一隻：沒有櫃子，蛋就是家
            if (shelf.Collapsed) shelf.SnapFold();
            shelf.Place(ShelfWA());
            lastT = clock.Elapsed.TotalSeconds; Now = lastT;
            sessionStart = lastT;
            Scan(lastT);
            RenderShelf();
            shelf.Show();

            // 一開始誰在外面：out.txt，沒有就用 -Pet
            List<string> outIds = LoadOutIds();
            string today = DateTime.Now.ToString("yyyy-MM-dd");
            bool rollCall = outIds.Count >= 2 && !Night && Feat("rollcall") && ReadText("rollcall.txt") != today;
            if (rollCall) { WriteText("rollcall.txt", today); StartRollCall(outIds); }
            else
            {
                double delay = 0.2;
                foreach (string id in outIds)
                {
                    Pet p = Get(id);
                    if (p == null) continue;
                    Pet pp = p;
                    Later(delay, delegate { BringOut(pp, false); pp.Say(pp.Greeting(), 3.5); if (pp.DaysSincePat() >= 2) pp.Say(pp.L("missed"), 4.5); });
                    delay += 0.6;
                }
            }
            string act = ReadText(LF("active.txt"));
            if (Get(act) != null) active = Get(act);
            if (active == null) active = Get(outIds.Count > 0 ? outIds[outIds.Count - 1] : defaultPet) ?? Get(defaultPet);

            Thread th = new Thread(PipeLoop); th.IsBackground = true; th.Start();
            Thread cw = new Thread(WatchLoop); cw.IsBackground = true; cw.Start();
            Thread hl = new Thread(HealthLoop); hl.IsBackground = true; hl.Start();
            LoadReminders();
            LoadTickets();
            StartDownloadWatch();
            if (!App.Offscreen && !W.RegisterHotKey(Handle, 7, 0x0001 | 0x0002 | 0x4000, 0x53)) App.Log("hotkey Ctrl+Alt+S is taken");
            timer.Interval = 30;
            timer.Tick += delegate { Tick(); };
            timer.Start();
            if (!File.Exists(FilePath("profile.txt"))) Later(1.2, delegate { ShowSetup(true); });   // 第一次：設定視窗（你是？選一櫃、擺法）
            App.Log("started pipe=" + pipeName + " lineup=" + lineup + " out=" + string.Join(",", outIds.ToArray()) + " data=" + DataDir);
        }

        protected override void SetVisibleCore(bool value) { base.SetVisibleCore(false); }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x0312 && m.WParam.ToInt32() == 7) { ToggleHide(); return; } // Ctrl+Alt+S
            base.WndProc(ref m);
        }

        // ---------- 存檔 ----------
        static string FilePath(string name) { return Path.Combine(DataDir, name); }
        static string ReadText(string name) { try { return File.ReadAllText(FilePath(name)).Trim(); } catch { return ""; } }
        static void WriteText(string name, string s) { try { Directory.CreateDirectory(DataDir); File.WriteAllText(FilePath(name), s); } catch { } }

        void Migrate()
        {
            // 舊的 Spidey 桌面版好感度搬過來（只複製，不動原檔）
            string old = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SpideyDesktop");
            string[,] map = { { "bond.txt", "bond-spidey.txt" }, { "pats.txt", "pats-spidey.txt" } };
            for (int i = 0; i < 2; i++)
            {
                string src = Path.Combine(old, map[i, 0]), dst = FilePath(map[i, 1]);
                try { if (File.Exists(src) && !File.Exists(dst)) { File.Copy(src, dst); App.Log("migrated " + map[i, 0]); } } catch { }
            }
            foreach (Pet p in Pets) p.Reload();
        }

        void LoadState()
        {
            favPin = ReadText(LF("fav.txt"));
            foreach (string line in ReadText(LF("usage.txt")).Split('\n'))
            {
                string[] a = line.Trim().Split(' ');
                double v;
                if (a.Length == 2 && double.TryParse(a[1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out v)) usage[a[0]] = v;
            }
        }

        List<string> LoadOutIds()
        {
            List<string> ids = new List<string>();
            if (File.Exists(FilePath(LF("out.txt"))))
            {
                foreach (string s in ReadText(LF("out.txt")).Split(new char[] { ' ', ',', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries))
                    if (Get(s) != null && !ids.Contains(s)) ids.Add(s);
            }
            else ids.Add(Single ? SinglePet() : defaultPet);
            if (Single) ids.RemoveAll(delegate(string x) { return x != SinglePet(); });   // 只要一隻：其他隻都不出來
            return ids;
        }

        void SaveOut()
        {
            List<string> ids = new List<string>();
            foreach (Pet p in outOrder) if (p.Out && p.state != "stowfly" && p.state != "enter") ids.Add(p.P.Id);
            WriteText(LF("out.txt"), string.Join(" ", ids.ToArray()));
            if (active != null) WriteText(LF("active.txt"), active.P.Id);
        }

        void SaveUsage()
        {
            StringBuilder sb = new StringBuilder();
            foreach (KeyValuePair<string, double> kv in usage) sb.Append(kv.Key + " " + kv.Value.ToString("0", System.Globalization.CultureInfo.InvariantCulture) + "\n");
            WriteText(LF("usage.txt"), sb.ToString());   // 每一櫃各自算誰用最久（小波在天線寶寶一櫃的時間不算進經典一櫃）
        }

        // ---------- 櫃子的格子：最愛（釘選 > 用最久）在高格，其他照順序 ----------
        public string FavId()
        {
            if (PikLineup) return "";   // 皮克敏一櫃：大格固定是休息花
            if (Get(favPin) != null) return favPin;
            string lf = Pal.LineupFav(lineup);
            if (lf != null && Get(lf) != null) return lf;                 // 天線寶寶一櫃：大格是小波
            string best = Pets[0].P.Id; double bv = -1;
            foreach (Pet p in Pets) { double v; usage.TryGetValue(p.P.Id, out v); if (v > bv + 0.5) { bv = v; best = p.P.Id; } }
            return best;
        }

        Pet[] CellPets()
        {
            Pet[] c = new Pet[4];
            string fav = FavId();
            c[0] = Get(fav);
            int i = 1;
            foreach (Pet p in Pets) if (p != c[0] && i < 4) c[i++] = p;
            return c;
        }

        int CellOf(Pet p) { Pet[] c = CellPets(); for (int i = 0; i < 4; i++) if (c[i] == p) return i; return 1; }

        public void ShelfFoot(Pet p, out double fxp, out double fyp, out int ps)
        {
            if (shelf.Collapsed) { Point ef = shelf.EggFoot(); fxp = ef.X; fyp = ef.Y; ps = 2; return; }
            int i = CellOf(p);
            Point f = shelf.Foot(i);
            fxp = f.X; fyp = f.Y; ps = shelf.FitPs(i, p);
        }

        // 丟回櫃子的「籃框」：櫃子左右各加一隻寬、上面加兩隻高
        public Rectangle ShelfZone(int sw, int sh)
        {
            Rectangle a = shelf.Collapsed ? shelf.EggScreen() : shelf.Area;
            return Rectangle.FromLTRB(a.Left - sw, a.Top - 2 * sh, a.Right + sw, a.Bottom + sh / 2);
        }

        public void GoalCheer(Pet scorer)
        {
            foreach (Pet p in OutPets()) if (p != scorer) p.Cheer();
        }

        public bool InShelf(double px, double py)
        {
            Rectangle a = shelf.Collapsed ? shelf.EggScreen() : shelf.Area;
            a.Inflate((int)(20 * k), (int)(20 * k));
            return a.Contains((int)px, (int)py);
        }

        Rectangle ShelfWA()
        {
            Rectangle wa = screens[0].WorkingArea;
            foreach (Screen sc0 in screens) { Rectangle r0 = sc0.WorkingArea; if (r0.Right > wa.Right || (r0.Right == wa.Right && r0.Bottom > wa.Bottom)) wa = r0; }
            return wa;
        }

        public void RepaintShelf() { RenderShelf(); }
        void RenderShelf()
        {
            if (shelf == null) return;
            if (Hidden) { if (W.Shown(shelf)) shelf.Hide(); return; }
            Pet[] c = CellPets();
            bool[] o = new bool[4];
            for (int i = 0; i < 4; i++) o[i] = c[i] != null && c[i].Out;
            bool hot = false, over = false;
            foreach (Pet p in Pets) if (p.Out && p.Dragging) { hot = true; if (InShelf(p.Cx, p.y + p.SH / 2.0)) over = true; }
            shelf.Hot = hot; shelf.Over = over; shelf.Night = Night; shelf.Tubby = TubbyLineup; shelf.Pik = PikLineup; shelf.Orig = OrigLineup; shelf.Lunch = Lunch; shelf.Attention = EggAttention();
            shelf.Render(c, o, Now);
            if (!W.Shown(shelf)) { shelf.Show(); Zorder(); }
        }

        // ---------- 放出來／收回去 ----------
        public void BringOut(Pet p, bool say)
        {
            if (!Pets.Contains(p)) return;          // 換櫃之前排好的延遲動作
            if (Single && p.P.Id != SinglePet()) return;   // 只要一隻：其他隻待在家
            if (p.Out) { active = p; Broadcast(); return; }
            p.ComeOut(say);
            if (shelf.Collapsed) shelf.Gulp();
            outOrder.Remove(p); outOrder.Add(p);
            active = p;
            if (fetchingBall()) p.BallStarted();
            SaveOut(); Broadcast();
            Zorder();
        }

        bool fetchingBall() { return BallOn; }

        public void PetStowed(Pet p)
        {
            if (shelf.Collapsed) shelf.Gulp();   // 蛋把公仔吞進去、晃一下
            outOrder.Remove(p);
            if (Holder == p) ReleaseBall(p.Cx, p.y, 0, 0);
            if (active == p) { for (int i = outOrder.Count - 1; i >= 0; i--) if (outOrder[i].Out) { active = outOrder[i]; break; } }
            SaveOut(); Broadcast();
        }

        public void ShelfClick(int cell)
        {
            Pet p = CellPets()[cell];
            if (p == null) { if (cell == 0 && PikLineup) FlowerClicked(); return; }
            if (p.Out) { if (p.state != "stowfly" && p.state != "enter" && p.state != "exit") p.StowToShelf(true); }
            else BringOut(p, true);
        }

        public void SelectOnly(Pet p)
        {
            AbortScene();
            foreach (Pet o in Pets) if (o != p && o.Out && o.state != "stowfly" && o.state != "enter") o.StowToShelf(false);
            if (!p.Out) Later(0.35, delegate { BringOut(p, true); });
            else { active = p; Broadcast(); SaveOut(); }
        }

        public void AllOut()
        {
            double d = 0;
            foreach (Pet p in Pets) if (!p.Out) { Pet pp = p; Later(d, delegate { BringOut(pp, true); }); d += 0.45; }
        }

        public void AllHome()
        {
            AbortScene();
            double d = 0;
            foreach (Pet p in Pets) if (p.Out) { Pet pp = p; Later(d, delegate { if (pp.Out && pp.state != "stowfly" && pp.state != "enter") pp.StowToShelf(true); }); d += 0.35; }
        }

        public void SetFav(Pet p)
        {
            if (PikLineup) { p.Say("大格種的是休息花，花不能搬喔 🌸", 2.2); return; }
            favPin = favPin == p.P.Id ? "" : p.P.Id;
            WriteText(LF("fav.txt"), favPin);
            p.Say(favPin == "" ? "好～不當最愛也沒關係" : "我是最愛！★ 謝謝你 ♥", 2);
        }

        public Pet Lead()
        {
            if (active != null && active.Out) return active;
            for (int i = outOrder.Count - 1; i >= 0; i--) if (outOrder[i].Out) return outOrder[i];
            return active ?? Get(defaultPet);
        }

        public List<Pet> OutPets() { List<Pet> l = new List<Pet>(); foreach (Pet p in Pets) if (p.Out && p.state != "stowfly" && p.state != "enter") l.Add(p); return l; }
        public int OutCount() { return OutPets().Count; }
        public Pet RandomOther(Pet me) { List<Pet> l = OutPets(); l.Remove(me); return l.Count == 0 ? null : l[rnd.Next(l.Count)]; }
        public Pet Nearest(Pet me)
        {
            Pet best = null; double bd = double.MaxValue;
            foreach (Pet p in OutPets()) if (p != me) { double d = Math.Abs(p.Cx - me.Cx) + Math.Abs(p.y - me.y); if (d < bd) { bd = d; best = p; } }
            return best;
        }

        // ---------- 延遲動作 ----------
        readonly List<KeyValuePair<double, Action>> later = new List<KeyValuePair<double, Action>>();
        public void Later(double sec, Action a) { later.Add(new KeyValuePair<double, Action>(Now + sec, a)); }
        void RunLater()
        {
            for (int i = 0; i < later.Count; i++)
                if (Now >= later[i].Key) { Action a = later[i].Value; later.RemoveAt(i); i--; try { a(); } catch (Exception ex) { App.Log("later: " + ex.Message); } }
        }

        // ================= 主迴圈 =================
        double perfSum, perfMax, perfT; int perfN, perfLogs;
        void Tick()
        {
            double t0 = clock.Elapsed.TotalMilliseconds;
            try { TickInner(); }
            finally
            {
                double ms = clock.Elapsed.TotalMilliseconds - t0;
                perfSum += ms; perfN++; if (ms > perfMax) perfMax = ms;
                if (Now - perfT > 60 && perfLogs < 6) { perfLogs++; App.Log("perf: tick avg " + (perfSum / Math.Max(1, perfN)).ToString("0.0") + "ms max " + perfMax.ToString("0") + "ms out=" + OutCount()); perfT = Now; perfSum = 0; perfN = 0; perfMax = 0; }
            }
        }

        void TickInner()
        {
            try
            {
                double now = clock.Elapsed.TotalSeconds, dt = Math.Min(0.05, now - lastT);
                lastT = now; Now = now;
                if (now >= nextScan) { nextScan = now + 0.3; Scan(now); }
                Point c = Cursor.Position;
                if (c == lastCursor) CursorStill += dt; else { CursorStill = 0; lastCursor = c; }
                newWinCd -= dt; fgCd -= dt; danceCd -= dt; waitCd -= dt;
                RunLater();
                FocusTick();
                LunchTick(false);
                QuietTick();
                ReminderTick();
                TicketTick();
                DownloadTick(dt);
                ExpireNotice();
                MenuWatch();
                if (Hidden) return;
                foreach (Pet p in Pets)
                {
                    try { if (p.Out) p.Tick(dt); else if (p.Bt > 0) { p.Bt -= dt; p.UpdateBubble(); } else p.HideForms(); }
                    catch (Exception ex) { App.Log("pet " + p.P.Id + ": " + ex); }
                    if (!p.Out && p.ShelfFx < 1) p.ShelfFx = Math.Min(1, p.ShelfFx + dt / 0.9);
                    if (p.Out && !sysIdle) { double v; usage.TryGetValue(p.P.Id, out v); usage[p.P.Id] = v + dt; }
                }
                UpdateBall(dt);
                StepProps(dt);
                PikTick(dt);
                OrigTick(dt);
                if (fx != null) fx.Step(dt);
                StepScene(dt);
                proxT -= dt;
                if (proxT <= 0) { proxT = 0.5; CheckCrossover(); }
                shelfT -= dt;
                bool dragHot = false;
                foreach (Pet p in Pets) if (p.Out && p.Dragging) dragHot = true;
                if (shelf != null) shelf.Step(dt);
                if (shelfT <= 0 || dragHot || (shelf != null && shelf.Animating)) { shelfT = 0.1; RenderShelf(); }
                usageT += dt;
                if (usageT > 60) { usageT = 0; SaveUsage(); }
            }
            catch (Exception ex) { App.Log("tick: " + ex); }
        }

        // 由下到上：櫃子 → 公仔 → 球 → 泡泡
        public void Zorder()
        {
            W.KeepOnTop(shelf);
            foreach (CobwebForm f in webs) W.KeepOnTop(f);
            foreach (Pet p in Pets) if (p.Form != null) W.KeepOnTop(p.Form);
            W.KeepOnTop(ballF);
            foreach (Prop pr in props) W.KeepOnTop(pr.F);
            if (fx != null && fx.Active) W.KeepOnTop(fx);
            foreach (Pet p in Pets) if (p.Bub != null) W.KeepOnTop(p.Bub);
            W.KeepOnTop(flowerBub);
        }

        // ================= 掃描視窗 =================
        void Scan(double now)
        {
            screens = Screen.AllScreens;
            HashSet<IntPtr> own = new HashSet<IntPtr>();
            own.Add(Handle);
            foreach (Pet p in Pets) { if (p.Form != null && p.Form.IsHandleCreated) own.Add(p.Form.Handle); if (p.Bub != null && p.Bub.IsHandleCreated) own.Add(p.Bub.Handle); }
            foreach (CobwebForm wf in webs) if (wf.IsHandleCreated) own.Add(wf.Handle);
            if (shelf != null && shelf.IsHandleCreated) own.Add(shelf.Handle);
            if (ballF != null && ballF.IsHandleCreated) own.Add(ballF.Handle);
            if (fx != null && fx.IsHandleCreated) own.Add(fx.Handle);
            if (flash != null && flash.IsHandleCreated) own.Add(flash.Handle);
            foreach (Prop pr in props) if (pr.F.IsHandleCreated) own.Add(pr.F.Handle);
            if (flowerBub != null && flowerBub.IsHandleCreated) own.Add(flowerBub.Handle);

            List<WinInfo> nw = new List<WinInfo>();
            Dictionary<IntPtr, WinInfo> nc = new Dictionary<IntPtr, WinInfo>();
            bool shareFound = false;
            StringBuilder title = new StringBuilder(256);
            W.EnumWindows(delegate(IntPtr h, IntPtr l)
            {
                if (App.Isolated || own.Contains(h) || !W.IsWindowVisible(h) || W.IsIconic(h)) return true;
                int cloaked;
                if (W.DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;
                W.RECT r;
                if (!W.Rect(h, out r) || r.R - r.L < 4 || r.B - r.T < 4) return true;
                int ex = W.GetWindowLong(h, -20);
                bool titled = W.GetWindowTextLength(h) > 0;
                if (titled && !shareFound) { title.Length = 0; W.GetWindowText(h, title, 256); if (IsShareTitle(title.ToString())) shareFound = true; }
                if ((ex & 0x20) != 0) return true;
                if ((ex & 0x80000) != 0 && !titled) return true;
                WinInfo wi = new WinInfo();
                wi.H = h; wi.L = r.L; wi.T = r.T; wi.R = r.R; wi.B = r.B; wi.Z = nw.Count;
                nw.Add(wi);
                if ((ex & 0x80) == 0 && titled && r.R - r.L >= 160 && r.B - r.T >= 80) nc[h] = wi;
                return true;
            }, IntPtr.Zero);

            int SH = 16 * S, SW = 12 * S;
            List<Plat> np = new List<Plat>();
            foreach (WinInfo wi in nc.Values)
            {
                Rectangle wa = WA((wi.L + wi.R) / 2.0, wi.T + 1);
                if (wi.T - wa.Top < SH + 4 || wi.T >= wa.Bottom - 4) continue;
                List<int[]> segs = new List<int[]>();
                segs.Add(new int[] { Math.Max(wi.L, wa.Left) + 4, Math.Min(wi.R, wa.Right) - 4 });
                for (int i = 0; i < wi.Z && segs.Count > 0; i++)
                {
                    WinInfo f = nw[i];
                    if (f.T <= wi.T - 1 && f.B > wi.T - 1) segs = Cut(segs, f.L, f.R);
                }
                foreach (int[] s in segs)
                    if (s[1] - s[0] >= SW) { Plat p = new Plat(); p.H = wi.H; p.Top = wi.T; p.Left = s[0]; p.Right = s[1]; p.WinLeft = wi.L; np.Add(p); }
            }
            Wins = nw; Cands = nc; Plats = np;
            if (shareFound != sharing)
            {
                sharing = shareFound;
                if (!sharing && !userHidden && !fsNow) Lead().Say(Lead().L("share_end"), 2);
                ApplyHidden();
            }
            foreach (Pet p in Pets) if (p.Out) p.CheckSupport();

            // 新視窗／對話框 → 一隻跑去看
            if (known == null) known = new HashSet<IntPtr>(nc.Keys);
            else
            {
                WinInfo fresh = null;
                foreach (KeyValuePair<IntPtr, WinInfo> kv in nc) if (!known.Contains(kv.Key)) { known.Add(kv.Key); fresh = kv.Value; }
                known.RemoveWhere(delegate(IntPtr h) { return !nc.ContainsKey(h); });
                if (fresh != null && newWinCd <= 0 && !Hidden && !focusOn && !quietOn && Feat("windows"))
                {
                    Pet p = PickFree();
                    if (p != null) { newWinCd = 6; fgCd = Math.Max(fgCd, 6); p.ReactNewWindow(fresh); }
                }
            }

            // 你切到哪個視窗，常常有一隻跟過去
            IntPtr fgw = W.GetForegroundWindow();
            if (fgw != lastFg)
            {
                lastFg = fgw;
                WinInfo fw;
                if (fgCd <= 0 && !Hidden && !focusOn && !quietOn && Feat("windows") && Cands.TryGetValue(fgw, out fw) && rnd.NextDouble() < 0.55)
                {
                    Pet p = PickFree();
                    if (p != null && p.FollowWindow(fw, p.AppLine(fgw))) fgCd = 20 + rnd.NextDouble() * 20;
                }
            }

            if (shelf != null)
            {
                Rectangle swa = ShelfWA();
                shelf.Place(swa);
            }
            SystemActivity(now);
            CheckNight();
            UpdateWebs(now);
            FullscreenCheck(own);
            Zorder();
        }

        Pet PickFree()
        {
            Pet l = Lead();
            if (l != null && l.Free()) return l;
            List<Pet> fr = new List<Pet>();
            foreach (Pet p in OutPets()) if (p.Free()) fr.Add(p);
            return fr.Count == 0 ? null : fr[rnd.Next(fr.Count)];
        }

        static List<int[]> Cut(List<int[]> segs, int a, int b)
        {
            List<int[]> res = new List<int[]>();
            foreach (int[] s in segs)
            {
                if (b <= s[0] || a >= s[1]) { res.Add(s); continue; }
                if (a > s[0]) res.Add(new int[] { s[0], a - 1 });
                if (b < s[1]) res.Add(new int[] { b + 1, s[1] });
            }
            return res;
        }

        public bool PointVisible(WinInfo wi, double px, double py)
        {
            foreach (WinInfo o in Wins)
            {
                if (o.Z >= wi.Z) break;
                if (px >= o.L && px < o.R && py >= o.T && py < o.B) return false;
            }
            return true;
        }

        public Rectangle WA(double px, double py)
        {
            Rectangle best = screens[0].WorkingArea;
            double bd = double.MaxValue;
            foreach (Screen s in screens)
            {
                Rectangle r = s.WorkingArea;
                if (r.Contains((int)px, (int)py)) return r;
                double dx = Math.Max(0, Math.Max(r.Left - px, px - r.Right)), dy = Math.Max(0, Math.Max(r.Top - py, py - r.Bottom));
                if (dx * dx + dy * dy < bd) { bd = dx * dx + dy * dy; best = r; }
            }
            return best;
        }

        public bool Inside(double px, double py)
        {
            foreach (Screen s in screens) if (s.WorkingArea.Contains((int)px, (int)py)) return true;
            return false;
        }

        // ---------- 蜘蛛網（Spidey 織在視窗角落）----------
        public void AddWeb(IntPtr h, bool right)
        {
            foreach (CobwebForm f in webs) if (f.H == h && f.RightCorner == right) return;
            if (webs.Count >= 4) { webs[0].Close(); webs.RemoveAt(0); }
            CobwebForm web = new CobwebForm(h, right, (int)(34 * k), Math.Max(1, (int)Math.Round(k)), Now);
            webs.Add(web);
            PlaceWeb(web);
        }

        void PlaceWeb(CobwebForm f)
        {
            WinInfo wi = null;
            bool ok = !Hidden && Cands.TryGetValue(f.H, out wi);
            if (ok)
            {
                int px = f.RightCorner ? wi.R - f.Side : wi.L, py = wi.T;
                ok = PointVisible(wi, f.RightCorner ? wi.R - 3 : wi.L + 3, wi.T + 3);
                if (ok)
                {
                    Rectangle nb = new Rectangle(px, py, f.Side, f.Side);
                    if (f.Bounds != nb) f.Bounds = nb;
                    if (!W.Shown(f)) f.Show();
                }
            }
            if (!ok && W.Shown(f)) f.Hide();
        }

        void UpdateWebs(double now)
        {
            for (int i = webs.Count - 1; i >= 0; i--)
            {
                CobwebForm f = webs[i];
                bool gone = now - f.Born > 150 || (!Cands.ContainsKey(f.H) && !W.IsWindowVisible(f.H));
                if (gone) { f.Close(); webs.RemoveAt(i); continue; }
                PlaceWeb(f);
            }
        }

        // ---------- 煙火 ----------
        public void Fireworks(Rectangle area, int n, int focusX)
        {
            if (Hidden || !Feat("fireworks")) return;   // 小屋可以關掉煙火
            if (fx == null) fx = new FxForm(k);
            fx.Start(area, n, focusX);
            Zorder();
        }

        // ---------- 躲起來（快速鍵／分享螢幕／全螢幕）----------
        void ToggleHide()
        {
            userHidden = !userHidden;
            ApplyHidden();
            if (!userHidden && !Hidden) { Pet l = Lead(); l.Say(l.L("back"), 1.6); }
        }

        void ApplyHidden()
        {
            bool want = fsNow || userHidden || sharing;
            if (!sharing && !fsNow) FlushShareHeld();
            if (want == Hidden) return;
            Hidden = want;
            if (want)
            {
                foreach (Pet p in Pets) p.HideForms();
                foreach (CobwebForm f in webs) f.Hide();
                if (shelf != null) shelf.Hide();
                if (ballF != null) ballF.Hide();
                foreach (Prop pr in props) pr.F.Hide();
                if (flowerBub != null) flowerBub.Hide();
                if (fx != null && fx.Active) fx.Stop();
            }
            else RenderShelf();
        }

        static bool IsShareTitle(string t)
        {
            string l = t.ToLowerInvariant();
            if (l.Contains("sharing your screen") || l.Contains("is sharing a window") || l.Contains("is sharing this tab") || l.Contains("you are screen sharing")
                || l.Contains("sharing control bar") || l.Contains("screen sharing toolbar")) return true;
            bool verb = t.Contains("分享") || t.Contains("共用") || t.Contains("共享");
            bool obj = t.Contains("螢幕") || t.Contains("畫面") || t.Contains("視窗") || t.Contains("分頁");
            return (t.Contains("正在") && verb && obj) || t.Contains("共用控制列") || t.Contains("共享控制列");
        }

        void FullscreenCheck(HashSet<IntPtr> own)
        {
            IntPtr fg = App.Isolated ? IntPtr.Zero : W.GetForegroundWindow();
            bool fs = false;
            if (fg != IntPtr.Zero && !own.Contains(fg))
            {
                StringBuilder sb = new StringBuilder(64);
                W.GetClassName(fg, sb, 64);
                string cls = sb.ToString();
                W.RECT r;
                if (cls != "Progman" && cls != "WorkerW" && cls != "Shell_TrayWnd" && W.GetWindowRect(fg, out r))
                {
                    Rectangle b = Screen.FromHandle(fg).Bounds;
                    int style = W.GetWindowLong(fg, -16);
                    fs = r.L <= b.Left && r.T <= b.Top && r.R >= b.Right && r.B >= b.Bottom && (style & 0x00C00000) != 0x00C00000;
                }
            }
            fsNow = fs;
            ApplyHidden();
        }

        // ---------- 整台電腦的鍵盤滑鼠：太久沒動 → 睡；回來 → 敲螢幕；用太久 → 提醒休息 ----------
        void SystemActivity(double now)
        {
            double idle = W.IdleSeconds();
            if (!sysIdle && idle > idleMin * 60)
            {
                sysIdle = true;
                foreach (Pet p in Pets) p.SystemIdle(true);
            }
            else if (sysIdle && idle < 2)
            {
                sysIdle = false;
                if (PikLineup) PikRested();       // 休息花：休息回來才恢復
                sessionStart = now;
                Pet l = Lead();
                foreach (Pet p in Pets) if (p == l) p.SystemIdle(false); else p.WakeIfSleep();
            }
            if (!sysIdle && now - sessionStart >= restMin * 60)
            {
                sessionStart = now;
                if (HoldIfQuiet("rest", "該起來動一動了")) return;
                if (PikLineup) PikWiltAlarm(); else Lead().Rest(restMin);
            }
        }

        // ---------- 夜晚（平日 18:00～隔天 06:00）、節日 ----------
        static bool IsNightTime(DateTime n)
        {
            if (n.Hour >= 18) return n.DayOfWeek >= DayOfWeek.Monday && n.DayOfWeek <= DayOfWeek.Friday;
            if (n.Hour < 6) { DayOfWeek y = n.AddDays(-1).DayOfWeek; return y >= DayOfWeek.Monday && y <= DayOfWeek.Friday; }
            return false;
        }
        bool NightNow() { return forceNight >= 0 ? forceNight == 1 : Feat("night") && IsNightTime(DateTime.Now); }   // 小屋可以關掉「下班時間」

        void CheckNight()
        {
            DateTime n = DateTime.Now;
            if (n.Minute == nightChecked) return;
            nightChecked = n.Minute;
            SeasonNow = Season();
            bool d = NightNow();
            if (d == Night) return;
            Night = d;
            if (quietOn) return;   // 安靜中：只換夜晚的樣子，不催
            if (d && n.DayOfWeek >= DayOfWeek.Monday && n.DayOfWeek <= DayOfWeek.Friday && n.Hour == 18) Later(OutCount() >= 2 ? 30 : 8, delegate { DailyWrap(false); });
            List<Pet> outs = OutPets();
            if (d && outs.Count >= 2 && Feat("rollcall")) { NightRitual(); return; }
            Pet l = Lead();
            foreach (Pet p in outs) if (p == l) p.NightChanged(d); else if (!d) p.Say(p.L("night_off"), 3);
            if (outs.Count == 0) l.Say(l.L(d ? "night_on" : "night_off"), 3);
        }

        static readonly string[] CNY = { "2027-02-06", "2028-01-26", "2029-02-13", "2030-02-03", "2031-01-23", "2032-02-11" };
        string Season()
        {
            DateTime n = DateTime.Now;
            if (!Feat("season")) return "";          // 小屋關掉「節日造型」
            if (birthday.Length == 5 && n.ToString("MM-dd") == birthday) return "birthday";
            foreach (string c in CNY)
            {
                double d = (n.Date - DateTime.Parse(c)).TotalDays;
                if (d >= -5 && d <= 14) return "cny";
            }
            if (n.Month == 12 && n.Day <= 26) return "xmas";
            if (n.Month == 1 && n.Day == 1) return "newyear";
            if (n.Month == 10 && n.Day == 31) return "halloween";
            if (n.DayOfWeek == DayOfWeek.Friday && n.Hour >= 15 && !Night) return "friday";
            return "";
        }

        // ================= 球 =================
        BallForm ballF;
        public bool BallOn;
        public double Bx, By, Bvx, Bvy, BallIdle, CatchCd;
        public Pet Holder;
        public string BallKind = "tennis";
        double foulCd, umpCd;

        public double BallR() { return ballF == null ? 8 * S * 0.75 / 2 : ballF.Width / 2.0; }

        void StartBall() { StartBall(false); }

        void StartBall(bool nearPet)
        {
            List<Pet> outs = OutPets();
            if (outs.Count == 0) { Lead().Say("先放一隻出來陪你玩球～", 1.8); return; }
            Pet po = Get("po");
            BallKind = po != null && po.Out ? "baseball" : Lead().P.BallKind;
            if (ballF == null) { ballF = new BallForm(Math.Max(2, S * 3 / 4)); ballF.Kicked += BallClicked; }
            ballF.Kind = BallKind;
            Point c = Cursor.Position;
            Bx = c.X; By = c.Y - 20 * k;
            BallOn = true; Holder = null;
            if (nearPet)
            {
                // 測試用：從公仔前上方丟過來
                Pet l = Lead();
                Bx = l.Cx + l.dir * 260 * k; By = l.y - 160 * k;
                Bvx = -l.dir * 260 * k; Bvy = -200 * k; BallIdle = 0; CatchCd = 0.2;
                foreach (Pet p in OutPets()) p.BallStarted();
                return;
            }
            BallClicked();
        }

        void BallClicked()
        {
            if (Holder != null) return;
            Bvx = (rnd.NextDouble() < 0.5 ? -1 : 1) * (350 + rnd.NextDouble() * 450) * k;
            Bvy = -(500 + rnd.NextDouble() * 300) * k;
            BallIdle = 0; CatchCd = 0.4;
            Pet l = Lead();
            foreach (Pet p in OutPets()) p.BallStarted();
            l.Say(l.L("ball_go"), 1.2);
        }

        void EndBall(string text)
        {
            BallOn = false; Holder = null;
            foreach (Pet p in Pets) p.fetching = false;
            if (ballF != null) ballF.Hide();
            Lead().Say(text, 2);
        }

        public void HoldBall(Pet p) { Holder = p; if (ballF != null) ballF.Hide(); }

        public void ReleaseBall(double x, double y, double vx, double vy)
        {
            Holder = null; Bx = x; By = y; Bvx = vx; Bvy = vy; BallIdle = 0;
            foreach (Pet p in OutPets()) p.BallStarted();
        }

        public void Umpire(string call)
        {
            if (OutCount() < 2 || umpCd > 0) return;
            Pet mm = Get("hangyodon") ?? Get("dipsy");   // 天線寶寶一櫃：迪西扶帽子當裁判
            if (mm == null || !mm.Out || Holder == mm) return;
            umpCd = 1.5;
            mm.Call(call);
        }

        void UpdateBall(double dt)
        {
            if (foulCd > 0) foulCd -= dt;
            if (umpCd > 0) umpCd -= dt;
            if (!BallOn) return;
            if (Holder != null)
            {
                if (!Holder.Out) { ReleaseBall(Holder.Cx, Holder.y, 0, 0); return; }
                Bx = Holder.Cx; By = Holder.y;
                BallIdle = 0;
                return;
            }
            double g = 900 * k, r = BallR(), prevBottom = By + r;
            Bvy += g * dt; Bx += Bvx * dt; By += Bvy * dt;
            Rectangle wa = WA(Bx, By);
            bool foul = false;
            if (!Inside(Bx - r, By) && Bx - r < wa.Left) { Bx = wa.Left + r; Bvx = Math.Abs(Bvx) * 0.6; foul = true; }
            if (!Inside(Bx + r, By) && Bx + r > wa.Right) { Bx = wa.Right - r; Bvx = -Math.Abs(Bvx) * 0.6; foul = true; }
            if (foul && foulCd <= 0 && Math.Abs(Bvx) > 200 * k) { foulCd = 4; Umpire("界外！"); }
            if (By - r < wa.Top) { By = wa.Top + r; Bvy = Math.Abs(Bvy) * 0.5; }
            if (Bvy > 0)
            {
                double best = wa.Bottom;
                foreach (Plat p in Plats) if (Bx >= p.Left && Bx <= p.Right && prevBottom <= p.Top + 1 && By + r >= p.Top && p.Top < best) best = p.Top;
                if (By + r >= best)
                {
                    By = best - r;
                    if (Bvy > 140 * k) { Bvy = -Bvy * 0.55; Bvx *= 0.85; }
                    else { Bvy = 0; Bvx *= Math.Pow(0.15, dt); }
                }
            }
            BallIdle += dt;
            if (CatchCd > 0) CatchCd -= dt;
            Pet l = Lead();
            if (BallIdle > 25 && Math.Abs(Bvx) < 8 && Bvy == 0) { EndBall(l.L("ball_end")); return; }
            if (CatchCd <= 0)
                foreach (Pet p in OutPets())
                {
                    if (!p.fetching) continue;
                    double scx = p.Cx, scy = p.y + p.SH / 2.0;
                    if (Math.Abs(Bx - scx) < p.SW * 0.6 + r && Math.Abs(By - scy) < p.SH * 0.6 + r && p.TouchBall()) { CatchCd = 1.0; break; }
                }
            if (Holder != null) return;
            Rectangle nb = new Rectangle((int)(Bx - r), (int)(By - r), ballF.Width, ballF.Height);
            if (ballF.Bounds != nb) ballF.Bounds = nb;
            if (!W.Shown(ballF) && !Hidden) { ballF.Show(); W.KeepOnTop(ballF); }
        }

        // ================= 右鍵選單 =================
        public void FillMenu(Pet p, ContextMenuStrip m)
        {
            m.Items.Clear();
            string[][] items = p.P.Pik ? PikMenuItems(p) : (p.P.Orig ? OrigMenuItems(p) : null);
            if (items == null) switch (p.P.Id)
            {
                case "po":
                    items = new string[][] { new string[] { "大抱抱 ♥", "hug" }, new string[] { "打招呼 Eh-oh!", "hi" }, new string[] { "敲敲螢幕", "knock" }, new string[] { "騎車兜風", "ride" },
                        new string[] { "滑板車飛跳", "sig" }, new string[] { "揮棒", "bat" }, new string[] { "睡覺", "sleep" }, new string[] { "丟棒球給她 ⚾", "ball" } };
                    break;
                case "stitch":
                    items = new string[][] { new string[] { "抱抱 ♥", "hug" }, new string[] { "Aloha! 打招呼", "hi" }, new string[] { "舔舔螢幕", "knock" }, new string[] { "爬牆上天花板", "sig" },
                        new string[] { "彈烏克麗麗 ♪", "uke" }, new string[] { "跳到別的視窗上", "jump" }, new string[] { "睡覺", "sleep" }, new string[] { "丟球給他 ⚾", "ball" } };
                    break;
                case "hangyodon":
                    items = new string[][] { new string[] { "抱抱 ♥", "hug" }, new string[] { "打招呼", "hi" }, new string[] { "講個笑話", "joke" }, new string[] { "敲敲螢幕（啵～）", "knock" },
                        new string[] { "披風英雄飛行", "sig" }, new string[] { "吐泡泡", "bubble" }, new string[] { "在泡泡裡睡覺", "sleep" }, new string[] { "丟球給他 ⚾", "ball" } };
                    break;
                case "tinky":
                    items = new string[][] { new string[] { "大抱抱 ♥", "hug" }, new string[] { "打招呼 Eh-oh!", "hi" }, new string[] { "敲敲螢幕", "knock" }, new string[] { "翻翻魔法袋", "bag" },
                        new string[] { "跳舞", "dance" }, new string[] { "跌一跤（哎喲！）", "plop" }, new string[] { "抱著袋袋睡覺", "sleep" }, new string[] { "丟球給他 ⚾", "ball" } };
                    break;
                case "dipsy":
                    items = new string[][] { new string[] { "大抱抱 ♥", "hug" }, new string[] { "打招呼 Eh-oh.", "hi" }, new string[] { "敲敲螢幕", "knock" }, new string[] { "帽子戲法", "sig" },
                        new string[] { "摘帽子揮一揮", "hatwave" }, new string[] { "酷酷地跳舞", "dance" }, new string[] { "帽子拉低睡覺", "sleep" }, new string[] { "丟球給他 ⚾", "ball" } };
                    break;
                case "laalaa":
                    items = new string[][] { new string[] { "大抱抱 ♥", "hug" }, new string[] { "打招呼 Eh-oh!", "hi" }, new string[] { "敲敲螢幕", "knock" }, new string[] { "顛球", "sig" },
                        new string[] { "唱歌 啦啦啦 ♪", "sing" }, new string[] { "轉圈圈", "twirl" }, new string[] { "抱著球睡覺", "sleep" }, new string[] { "丟球給她 ⚾", "ball" } };
                    break;
                default:
                    items = new string[][] { new string[] { "抱抱 ♥", "hug" }, new string[] { "打招呼", "hi" }, new string[] { "敲敲螢幕", "knock" }, new string[] { "噴絲擺盪", "swing" },
                        new string[] { "倒吊", "hang" }, new string[] { "跳到別的視窗上", "jump" }, new string[] { "去爬牆", "climb" }, new string[] { "睡覺", "sleep" }, new string[] { "丟球給他 ⚾", "ball" } };
                    break;
            }
            m.Items.Add(new ToolStripLabel("一起玩"));
            foreach (string[] it in items)
            {
                string a = it[1];
                m.Items.Add(it[0], null, delegate { if (a == "ball") StartBall(); else p.Act(a); });
            }
            m.Items.Add(p.P.Name + " 的好感度 ♥", null, delegate { p.ShowBond(); });
            m.Items.Add(new ToolStripSeparator());
            ToolStripMenuItem help = new ToolStripMenuItem("小幫手（專注、安靜、提醒）");
            AddHelpers(help.DropDownItems);
            m.Items.Add(help);
            m.Items.Add("公仔小屋（開關、設定）…", null, delegate { HouseMenu(); });
            m.Items.Add(new ToolStripSeparator());
            m.Items.Add(new ToolStripLabel(Single ? "我的公仔" : "公仔們"));
            if (TubbyLineup && !Single)
            {
                ToolStripMenuItem grp = new ToolStripMenuItem("天線寶寶一起…");
                string[][] gs = { new string[] { "大抱抱 ♥", "bighug" }, new string[] { "啦啦啦一起唱", "sing" }, new string[] { "一起跌倒（哎喲！）", "fall" },
                    new string[] { "吐司時間 🍞", "toast" }, new string[] { "大合照 📷", "photo" }, new string[] { "天線寶寶說再見", "byebye" } };
                foreach (string[] gi in gs) { string key = gi[1]; grp.DropDownItems.Add(gi[0], null, delegate { PlayScene(key); }); }
                m.Items.Add(grp);
            }
            if (PikLineup) AddPikMenu(m);
            if (OrigLineup && !Single) AddOrigMenu(m);
            if (!Single)
            {
                ToolStripMenuItem sw = new ToolStripMenuItem("換角色");
                foreach (Pet o in Pets)
                {
                    Pet oo = o;
                    ToolStripMenuItem mi = new ToolStripMenuItem(o.P.Name + (o.Out ? "（在外面）" : ""), null, delegate { SelectOnly(oo); });
                    mi.Checked = o == p;
                    sw.DropDownItems.Add(mi);
                }
                m.Items.Add(sw);
                m.Items.Add("只留" + p.P.Name, null, delegate { SelectOnly(p); });
                m.Items.Add("全部放出來", null, delegate { AllOut(); });
                m.Items.Add("全部回櫃子", null, delegate { AllHome(); });
                m.Items.Add(favPin == p.P.Id ? "取消最愛" : "設為最愛 ★", null, delegate { SetFav(p); });
            }
            m.Items.Add(Single ? "回蛋裡待著" : "回櫃子裡待著", null, delegate { p.StowToShelf(true); });
            m.Items.Add("躲起來（Ctrl+Alt+S）", null, delegate { ToggleHide(); });
            m.Items.Add(new ToolStripSeparator());
            m.Items.Add("收工（關掉 Desk Pals）", null, delegate { QuitAll(); });
        }

        // 專注、安靜、提醒、搶票、今天的小結（公仔、櫃子、小屋的選單都有）
        void AddHelpers(ToolStripItemCollection items)
        {
            if (focusOn) items.Add("結束專注（還剩 " + FocusLeft() + " 分）", null, delegate { StopFocus(false); });
            else items.Add("專注 25 分鐘 🍅", null, delegate { StartFocus(25); });
            AddQuietMenu(items);
            AddReminderMenus(items);
            AddTicketMenus(items);
            items.Add("今天的小結", null, delegate { DailyWrap(true); });
        }

        void AddQuietMenu(ToolStripItemCollection items)
        {
            if (quietOn) { items.Add("結束安靜（還剩 " + QuietLeft() + " 分）", null, delegate { StopQuiet(); }); return; }
            ToolStripMenuItem q = new ToolStripMenuItem("安靜一下");
            q.DropDownItems.Add("30 分鐘", null, delegate { StartQuiet(30); });
            q.DropDownItems.Add("2 小時", null, delegate { StartQuiet(120); });
            q.DropDownItems.Add("到今天下班", null, delegate { StartQuiet(MinutesToOffWork()); });
            items.Add(q);
        }

        // 收合成蛋／打開公仔櫃
        public void ToggleEgg(bool collapse)
        {
            if (shelf.Collapsed == collapse) return;
            if (Single && !collapse) { Lead().Say("現在是「只要一隻」，蛋就是我家～（小屋 → 重新設定 可以換）", 3); return; }
            shelf.Collapsed = collapse;
            WriteText("shelf-state.txt", collapse ? "egg" : "open");
            Pet l = Lead();
            if (collapse) l.Say(Pick2("公仔櫃收起來囉～變成一顆蛋 🥚", "收合！大家住進蛋裡"), 1.8);
            else l.Say(Pick2("蛋打開了！公仔櫃登場 ✨", "喀啦喀啦～櫃子打開囉"), 1.8);
            RenderShelf();
        }
        string Pick2(string a, string b) { return rnd.NextDouble() < 0.5 ? a : b; }

        // 蛋上的小紅點：專注／安靜時存著的通知，加上 10 分鐘內要到的提醒、搶票
        int EggAttention()
        {
            int n = heldQuiet.Count + heldFocus.Count;
            long now = UnixMs(DateTime.Now);
            foreach (Reminder r in reminders) if (r.At - now <= 10 * 60000) n++;
            foreach (Ticket t in tickets) if (t.At - now <= 10 * 60000 && t.At > now) n++;
            return n;
        }

        // ---------- 選單：自己畫的像素選單（PixelMenu），開在游標旁邊 ----------
        PixelMenu pmenu;
        IntPtr menuPrevFg;
        // 以前要幫原生選單善後（宿主視窗、還焦點）；像素選單自己會處理，留著給公仔的 Menu 用
        public void HookMenu(ContextMenuStrip m) { }
        public void ShowMenu(ContextMenuStrip m) { ShowMenu(m, "", false, Cursor.Position); }
        public void ShowMenu(ContextMenuStrip m, string title, bool house) { ShowMenu(m, title, house, Cursor.Position); }
        // 選單內容還是用 ToolStrip 項目寫，這裡畫成像素選單，按下後呼叫原本的 Click
        public void ShowMenu(ContextMenuStrip m, string title, bool house, Point at)
        {
            App.LogAlways("menu: requested, items=" + m.Items.Count + " house=" + house);
            try
            {
                if (pmenu != null) pmenu.CloseMenu();
                if (!App.Offscreen) menuPrevFg = W.GetForegroundWindow();
                PixelMenu pm = new PixelMenu(this, m, title, house);
                pmenu = pm;
                W.SuspendZ = true;                    // 開著時不要把公仔、櫃子拉到選單上面
                pm.Popup(at);
                if (!App.Offscreen) { W.ForceForeground(pm.Handle); pm.Activate(); }
            }
            catch (Exception ex) { App.LogAlways("menu: error " + ex); W.SuspendZ = false; }
        }
        // 選單關掉了（選了、Esc、點外面、失去焦點）：焦點還給原本的視窗
        public void MenuClosed(PixelMenu pm)
        {
            if (pm != pmenu) return;
            pmenu = null;
            W.SuspendZ = false;
            if (!App.Offscreen && pm.IsHandleCreated && W.GetForegroundWindow() == pm.Handle && menuPrevFg != IntPtr.Zero) W.SetForegroundWindow(menuPrevFg);
        }
        // 點到選單外面就關：直接看滑鼠按鍵（我們是背景程式，點別的程式也看得到）；選單開了之後要先放開過一次
        void MenuWatch()
        {
            PixelMenu pm = pmenu;
            if (pm == null || pm.Done || App.Offscreen) return;
            if ((Control.MouseButtons & (MouseButtons.Left | MouseButtons.Right | MouseButtons.Middle)) == MouseButtons.None) { pm.Armed = true; return; }
            if (pm.Armed && !pm.Bounds.Contains(Cursor.Position)) pm.CloseMenu();
        }

        // 像素選單用的字：拿掉 BMP 以外的字（彩色 emoji）和變體選擇符；★ ♥ ⏰ 這類保留
        public static string NoEmoji(string s)
        {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < s.Length; i++)
            {
                char ch = s[i];
                if (char.IsHighSurrogate(ch) || char.IsLowSurrogate(ch) || ch == '️' || ch == '‍') continue;
                sb.Append(ch);
            }
            return sb.ToString().Replace("  ", " ").Trim();
        }

        // 輸入框：拉到前景、可以直接打字
        public void ActivateForm(Form f)
        {
            W.ForceForeground(f.Handle);
            f.BringToFront();
            f.Activate();
            f.Focus();
            App.LogAlways("dialog: activate " + f.Text + " foreground=" + (W.GetForegroundWindow() == f.Handle));
        }

        ContextMenuStrip shelfMenu;
        public void ShelfMenu(int cell, Control at)
        {
            Pet p = cell >= 0 ? CellPets()[cell] : null;
            if (shelfMenu == null) { shelfMenu = new ContextMenuStrip(); HookMenu(shelfMenu); }
            ContextMenuStrip m = shelfMenu;
            m.Items.Clear();
            if (p != null)
            {
                m.Items.Add(p.Out ? "收回櫃子" : "放出來", null, delegate { ShelfClick(cell); });
                m.Items.Add("只留" + p.P.Name, null, delegate { SelectOnly(p); });
                m.Items.Add(favPin == p.P.Id ? "取消最愛" : "設為最愛 ★", null, delegate { SetFav(p); });
                m.Items.Add(p.P.Name + " 的好感度 ♥", null, delegate { p.ShowBond(); });
                m.Items.Add(new ToolStripSeparator());
            }
            if (PikLineup) m.Items.Add("休息花：還能撐多久？🌸", null, delegate { FlowerClicked(); });
            m.Items.Add(shelf.Collapsed ? "打開公仔櫃" : "收合成蛋 🥚", null, delegate { ToggleEgg(!shelf.Collapsed); });
            m.Items.Add("全部放出來", null, delegate { AllOut(); });
            m.Items.Add("全部回櫃子", null, delegate { AllHome(); });
            ToolStripMenuItem help = new ToolStripMenuItem("小幫手（專注、安靜、提醒）");
            AddHelpers(help.DropDownItems);
            m.Items.Add(help);
            m.Items.Add("公仔小屋（開關、設定）…", null, delegate { HouseMenu(); });
            m.Items.Add("躲起來（Ctrl+Alt+S）", null, delegate { ToggleHide(); });
            m.Items.Add(new ToolStripSeparator());
            m.Items.Add("收工（關掉 Desk Pals）", null, delegate { QuitAll(); });
            ShowMenu(m, p != null ? p.P.Name : "公仔櫃", false);
        }

        // ================= pipe（跟 VS Code 溝通）=================
        void PipeLoop()
        {
            while (!closing)
            {
                NamedPipeServerStream s = null;
                try
                {
                    s = new NamedPipeServerStream(pipeName, PipeDirection.InOut, NamedPipeServerStream.MaxAllowedServerInstances,
                        PipeTransmissionMode.Byte, PipeOptions.Asynchronous);
                    s.WaitForConnection();
                }
                catch (Exception ex)
                {
                    App.Log("pipe: " + ex.Message);
                    if (s != null) s.Dispose();
                    Thread.Sleep(500);
                    continue;
                }
                Client c = new Client();
                c.S = s;
                lock (clients) clients.Add(c);
                Thread th = new Thread(delegate() { ClientLoop(c); });
                th.IsBackground = true;
                th.Start();
            }
        }

        void ClientLoop(Client c)
        {
            try
            {
                StreamReader r = new StreamReader(c.S, new UTF8Encoding(false));
                string line;
                while ((line = r.ReadLine()) != null)
                {
                    string l = line;
                    Post(delegate { OnMsg(c, l); });
                }
            }
            catch { }
            lock (clients) clients.Remove(c);
            try { c.S.Dispose(); } catch { }
        }

        public void Post(Action a)
        {
            try { if (!closing && !IsDisposed && IsHandleCreated) BeginInvoke(a); } catch { }
        }

        static void Send(Client c, string s)
        {
            try { byte[] b = Encoding.UTF8.GetBytes(s); c.S.Write(b, 0, b.Length); c.S.Flush(); } catch { }
        }

        string lastBroadcast = "";
        void Broadcast()
        {
            if (active == null) return;
            string id = active.P.Id;
            if (id == lastBroadcast) return;
            lastBroadcast = id;
            lock (clients) foreach (Client c in clients) Send(c, "active " + id + "\n");
        }

        void OnMsg(Client c, string line)
        {
            string[] p = line.Trim().Split(' ');
            Pet l = Lead();
            List<Pet> outs = OutPets();
            switch (p[0])
            {
                case "hello": if (active != null) Send(c, "active " + active.P.Id + "\n"); Send(c, "lineup " + lineup + "\n"); break;   // 櫃子以桌面版為準（第一次設定在桌面做）
                case "save":
                    Count("saves");
                    foreach (Pet x in outs) x.OnSave(x == l);
                    if (outs.Count == 0) l.OnSave(true);
                    break;
                case "errors":
                    {
                        int n = 0, prev = 0;
                        if (p.Length >= 3) { int.TryParse(p[1], out n); int.TryParse(p[2], out prev); }
                        if (n <= prev && n != 0) break;
                        foreach (Pet x in outs) x.OnErrors(n, prev, x.P.Id == "po" || x.P.Id == "laalaa" ? Nearest(x) : null);
                        if (outs.Count == 0) l.OnErrors(n, prev, null);
                    }
                    break;
                case "config":
                    double rm, im;
                    if (p.Length >= 3 && double.TryParse(p[1], out rm) && double.TryParse(p[2], out im)) { restMin = Math.Max(1, rm); idleMin = Math.Max(1, im); }
                    break;
                case "hi": l.Act("hi"); break;
                case "claude": if (p.Length >= 2) OnClaude(p[1], p.Length >= 3 ? p[2] : "x"); break;
                case "tag":
                    {
                        Count("deploys");
                        if (HoldIfQuiet("tag", "上版成功" + (p.Length >= 3 && p[2] == "prod" ? "（正式機）" : ""))) break;
                        string env = p.Length >= 3 ? p[2] : "";
                        bool fired = false;
                        foreach (Pet x in outs) { x.Celebrate(env, !fired && (x.P.Id == "spidey" || x.P.Id == "po" || x == l)); if (x.P.Id == "spidey" || x.P.Id == "po") fired = true; }
                        if (!fired && outs.Count > 0) Fireworks(WA(l.Cx, l.y), 8, -1);
                        if (outs.Count == 0) l.Celebrate(env, true);
                    }
                    break;
                case "birthday": birthday = p.Length >= 2 ? p[1].Trim() : ""; SeasonNow = Season(); break;
                case "typing":
                    int chars;
                    if (p.Length >= 2 && int.TryParse(p[1], out chars))
                    {
                        typingStreak = chars >= 30 ? typingStreak + 1 : 0;
                        if (typingStreak >= 2 && danceCd <= 0 && !Hidden)
                        {
                            danceCd = 150;
                            foreach (Pet x in outs) if (x == l || rnd.NextDouble() < 0.5) x.OnTyping();
                        }
                    }
                    break;
                case "act": if (p.Length >= 2) Act(p[1], p.Length >= 3 ? p[2] : ""); break;
                case "where":
                    {
                        StringBuilder sb = new StringBuilder();
                        foreach (Pet x in Pets) if (x.Out) sb.Append("pos " + x.P.Id + " " + (int)x.x + " " + (int)x.y + " " + x.state + "\n");
                        sb.Append("end\n");
                        Send(c, sb.ToString());
                    }
                    break;
                case "notify":
                    if (p.Length >= 4)
                    {
                        // 文字可以有空白：取第三個空白之後全部
                        string t = line.Trim();
                        int i1 = t.IndexOf(' '), i2 = t.IndexOf(' ', i1 + 1), i3 = t.IndexOf(' ', i2 + 1);
                        OnNotify(p[1], p[2], i3 > 0 ? t.Substring(i3 + 1) : "");
                    }
                    break;
                case "remind":
                    if (p.Length >= 3)
                    {
                        long ms;
                        string t = line.Trim();
                        int i1 = t.IndexOf(' '), i2 = t.IndexOf(' ', i1 + 1);
                        if (long.TryParse(p[1], out ms)) AddReminder(ms, i2 > 0 ? t.Substring(i2 + 1) : "");
                    }
                    break;
                case "ticket":
                    if (p.Length >= 5)
                    {
                        // ticket <unixMs> <提前分鐘> <url|-> <名稱…>
                        long ms; int lead;
                        string t = line.Trim();
                        int i1 = t.IndexOf(' '), i2 = t.IndexOf(' ', i1 + 1), i3 = t.IndexOf(' ', i2 + 1), i4 = t.IndexOf(' ', i3 + 1);
                        if (long.TryParse(p[1], out ms) && int.TryParse(p[2], out lead)) AddTicket(ms, lead, p[3], i4 > 0 ? t.Substring(i4 + 1) : "");
                    }
                    break;
                case "lineup": SwitchLineup(p.Length >= 2 ? p[1] : "", p.Length >= 3 ? p[2] : ""); Send(c, "lineup " + lineup + "\n"); break;   // 回報現在是哪一櫃（VS Code 用來判斷桌面版是不是舊版）
                case "config-host": companyHost = p.Length >= 2 ? p[1].Trim() : ""; break;
                case "snap": if (p.Length >= 2) Snap(p[1], ParseRect(p, 2)); Send(c, "snapped\n"); break;
                case "snaps":
                    {
                        // snaps <資料夾> <張數> <間隔ms> [x y w h]
                        int n, ms;
                        if (p.Length >= 4 && int.TryParse(p[2], out n) && int.TryParse(p[3], out ms))
                        {
                            string dir = p[1]; Rectangle rr = ParseRect(p, 4);
                            for (int i = 0; i < n; i++) { int ii = i; Later(i * ms / 1000.0, delegate { Snap(Path.Combine(dir, "f" + ii.ToString("00") + ".png"), rr); }); }
                        }
                    }
                    break;
                case "quit": QuitAll(); break;
            }
        }

        // 選單、VS Code 指令、測試共用（pipe 訊息 "act <名稱> [參數]"）
        void Act(string a, string arg)
        {
            Pet l = Lead();
            Pet target = Get(arg);
            switch (a)
            {
                case "select": if (target != null) SelectOnly(target); return;
                case "out": if (target != null) BringOut(target, true); return;
                case "in": if (target != null && target.Out) target.StowToShelf(true); return;
                case "all": AllOut(); return;
                case "home": AllHome(); return;
                case "shelf": if (l.Out) l.StowToShelf(true); return;
                case "ball": StartBall(arg == "here"); return;
                case "hide": ToggleHide(); return;
                case "fireworks": foreach (Pet x in OutPets()) x.Celebrate("dev", x == l); if (OutCount() == 0) l.Celebrate("dev", true); return;
                case "dark": case "night": forceNight = 1; nightChecked = -1; CheckNight(); return;
                case "light": case "day": forceNight = 0; nightChecked = -1; CheckNight(); return;
                case "auto": forceNight = -1; nightChecked = -1; CheckNight(); forceLunch = -1; LunchTick(true); return;
                case "lunch": forceLunch = 1; LunchTick(true); return;
                case "egg": ToggleEgg(true); return;
                case "unegg": ToggleEgg(false); return;
                case "lunchnap": forceLunch = 2; LunchTick(true); return;
                case "lunchsoon": forceLunch = -1; LunchState = "nap"; foreach (Pet x in OutPets()) x.WakeIfSleep(); LunchState = "soon"; Lead().Say("午休快結束囉～", 3); return;
                case "lunchend": forceLunch = 0; LunchTick(true); return;
                case "fav": SetFav(target ?? l); return;
                case "scene": PlayScene(arg); return;
                case "flower": PikFlowerAct(arg); return;
                case "whistle": Whistle(); return;
                case "photo": GroupPhoto(); return;
                case "rollcall": { List<string> ids = new List<string>(); foreach (Pet x in OutPets()) ids.Add(x.P.Id); if (ids.Count == 0) foreach (Pet x in Pets) ids.Add(x.P.Id); StartRollCall(ids); } return;
                case "done": OnDone(arg == "" ? "Codex" : arg); return;
                case "stuck": OnStuck(arg == "" ? "Codex" : arg, "tool", "exec_command", "", 3); return;
                case "focus": { int fm; StartFocus(int.TryParse(arg, out fm) ? fm : 25); } return;
                case "focusstop": StopFocus(false); return;
                case "wrap": DailyWrap(true); return;
                case "dlseen": DlSeen(arg); return;   // 測試用：假裝下載資料夾出現這個檔
                case "quiet": { int qm; if (!int.TryParse(arg, out qm)) qm = 30; StartQuiet(qm); } return;
                case "click": { string[] q = arg.Split(','); int cx2, cy2; if (q.Length == 2 && int.TryParse(q[0], out cx2) && int.TryParse(q[1], out cy2)) SimClick(cx2, cy2); } return;
                case "throw":
                    {
                        // act throw <id>,x,y,vx,vy（測試用：模擬拖著丟出去）
                        string[] q = arg.Split(',');
                        double tx2, ty2, tvx2, tvy2;
                        if (q.Length == 5 && double.TryParse(q[1], out tx2) && double.TryParse(q[2], out ty2) && double.TryParse(q[3], out tvx2) && double.TryParse(q[4], out tvy2))
                        { Pet tp = Get(q[0]); if (tp != null) tp.SimThrow(tx2, ty2, tvx2, tvy2); }
                    }
                    return;
                case "drop": { string[] q = arg.Split(','); int cx2, cy2; if (q.Length == 3 && int.TryParse(q[1], out cx2) && int.TryParse(q[2], out cy2)) SimDrop(Get(q[0]), cx2, cy2); } return;
                // 測試用：act menu pet|house|shelf、act menuhover <列>、act menuclick <列>、act menuclose、act setup [按鈕]
                case "menu": TestMenu(arg); return;
                case "menuhover": { int mi; if (pmenu != null && int.TryParse(arg, out mi)) pmenu.SetHover(mi); } return;
                case "menuclick": { int mi; if (pmenu != null && int.TryParse(arg, out mi)) pmenu.Pick(mi); } return;
                case "menuclose": if (pmenu != null) pmenu.CloseMenu(); return;
                case "setup": if (arg == "") ShowSetup(false); else if (setupForm != null && !setupForm.IsDisposed) setupForm.Press(arg); return;
                case "feature": { string[] q = arg.Split('='); if (q.Length == 2) SetFeat(q[0], q[1] == "1"); } return;
            }
            if (target != null && arg != "") target.Act(a); else l.Act(a);
        }

        void QuitAll()
        {
            closing = true;
            SaveUsage(); SaveOut();
            lock (clients) foreach (Client c in clients) Send(c, "bye\n");
            timer.Stop();
            foreach (Pet p in Pets) p.CloseForms();
            foreach (CobwebForm f in webs) f.Close();
            if (shelf != null) shelf.Close();
            if (ballF != null) ballF.Close();
            if (fx != null) fx.Close();
            if (flash != null) flash.Close();
            ClearProps();
            Application.ExitThread();
        }
    }

    // ================= Claude／Codex 監看（背景執行緒）=================
    partial class World
    {
        class StuckInfo { public long Episode; public int Alerts; public DateTime NextAt; }
        class CodexSeen { public DateTime LastComplete; }
        readonly Dictionary<string, StuckInfo> stuck = new Dictionary<string, StuckInfo>();
        readonly Dictionary<string, CodexSeen> codexSeen = new Dictionary<string, CodexSeen>();
        readonly Dictionary<string, double> claudeStart = new Dictionary<string, double>();
        List<string> codexFiles = new List<string>();
        volatile int busyClaude, busyCodex;
        bool stuckNow;
        double doneUntil;

        // 狀態：stuck／done／busy／""（小波的肚子螢幕、其他人頭旁邊的小圖示）
        public string Status()
        {
            if (stuckNow) return "stuck";
            if (Now < doneUntil) return "done";
            if (busyClaude + busyCodex > 0) return "busy";
            return "";
        }

        static string ClaudeProjectsDir()
        {
            string cfg = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
            if (string.IsNullOrEmpty(cfg)) cfg = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude");
            return Path.Combine(cfg, "projects");
        }

        static string CodexSessionsDir()
        {
            string home = Environment.GetEnvironmentVariable("CODEX_HOME");
            if (string.IsNullOrEmpty(home)) home = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex");
            return Path.Combine(home, "sessions");
        }

        void WatchLoop()
        {
            Thread.Sleep(8000);
            JavaScriptSerializer js = new JavaScriptSerializer();
            js.MaxJsonLength = int.MaxValue;
            int n = 0;
            while (!closing)
            {
                try { if (n % 3 == 0) ClaudeWatchOnce(js); } catch (Exception ex) { App.Log("claude watch: " + ex.Message); }
                try { CodexWatchOnce(n % 6 == 0); } catch (Exception ex) { App.Log("codex watch: " + ex.Message); }
                n++;
                Thread.Sleep(5000);
            }
        }

        // 共用的卡住判斷：quiet 秒沒動靜、kind＝tool/model
        void StuckCheck(string key, string src, DateTime act, string kind, string tool, string title, bool running)
        {
            DateTime now = DateTime.UtcNow;
            StuckInfo si;
            if (!stuck.TryGetValue(key, out si)) { si = new StuckInfo(); stuck[key] = si; }
            double quiet = (now - act).TotalSeconds;
            if (quiet < 85)
            {
                if (si.Alerts > 0) { si.Alerts = 0; string s2 = src; Post(delegate { OnUnstuck(s2); }); }
                return;
            }
            if (kind == null || kind == "idle" || !running) { si.Alerts = 0; return; }
            bool ask = tool == "AskUserQuestion" || tool == "ExitPlanMode" || tool == "request_user_input";
            double limit = kind == "tool" ? (ask ? 90 : 180) : 300;
            if (quiet < limit) return;
            if (si.Episode != act.Ticks) { si.Episode = act.Ticks; si.Alerts = 0; }
            if (si.Alerts >= 3 || (si.Alerts > 0 && now < si.NextAt)) return;
            si.Alerts++;
            si.NextAt = now.AddMinutes(10);
            int min = Math.Max(1, (int)Math.Round(quiet / 60));
            string k2 = kind, t2 = tool, ti = title, sr = src;
            App.Log(src + " stuck: " + kind + " " + tool + " " + min + "min " + Path.GetFileName(key));
            Post(delegate { OnStuck(sr, k2, t2, ti, min); });
        }

        void ClaudeWatchOnce(JavaScriptSerializer js)
        {
            string root = ClaudeProjectsDir();
            if (!Directory.Exists(root)) { busyClaude = 0; return; }
            DateTime now = DateTime.UtcNow;
            HashSet<string> seen = new HashSet<string>();
            bool anyClaude = Process.GetProcessesByName("claude").Length > 0 || Process.GetProcessesByName("node").Length > 0;
            int busy = 0;
            foreach (string pdir in Directory.GetDirectories(root))
                foreach (FileInfo fi in new DirectoryInfo(pdir).EnumerateFiles("*.jsonl"))
                {
                    DateTime act = fi.LastWriteTimeUtc;
                    if ((now - act).TotalMinutes > 40) continue;
                    string key = fi.FullName;
                    seen.Add(key);
                    string sub = Path.Combine(pdir, Path.GetFileNameWithoutExtension(fi.Name));
                    if (Directory.Exists(sub))
                        foreach (FileInfo f2 in new DirectoryInfo(sub).EnumerateFiles("*", SearchOption.AllDirectories))
                            if (f2.LastWriteTimeUtc > act) act = f2.LastWriteTimeUtc;
                    string tool = null, title = null, kind = null;
                    if ((now - act).TotalMinutes < 10 || (now - act).TotalSeconds >= 85) kind = ClaudeState(js, fi.FullName, out tool, out title);
                    if (anyClaude && (kind == "model" || kind == "tool") && (now - act).TotalMinutes < 10) busy++;
                    StuckCheck(key, "Claude", act, kind, tool, title, anyClaude);
                }
            busyClaude = busy;
            List<string> gone = new List<string>();
            foreach (string kk in stuck.Keys) if (!seen.Contains(kk) && kk.StartsWith(root, StringComparison.OrdinalIgnoreCase)) gone.Add(kk);
            foreach (string kk in gone) stuck.Remove(kk);
        }

        // 讀對話紀錄最後一段，找最後一筆主對話：回傳 idle／model／tool（null＝看不出來）
        static string ClaudeState(JavaScriptSerializer js, string file, out string tool, out string title)
        {
            tool = null; title = null;
            string text = Tail(file, 768 * 1024);
            string[] lines = text.Split('\n');
            string kind = null;
            for (int i = lines.Length - 1; i >= 0; i--)
            {
                string l = lines[i].Trim();
                if (l.Length < 2) continue;
                if (title == null && l.StartsWith("{\"type\":\"ai-title\""))
                {
                    try
                    {
                        Dictionary<string, object> td = js.DeserializeObject(l) as Dictionary<string, object>;
                        if (td != null) title = Str(td, "aiTitle");
                    }
                    catch { }
                    if (kind != null) break;
                    continue;
                }
                if (kind != null) { if (i < lines.Length - 400) break; continue; }
                if (l.IndexOf("\"isSidechain\":false", StringComparison.Ordinal) < 0) continue;
                Dictionary<string, object> d;
                try { d = js.DeserializeObject(l) as Dictionary<string, object>; } catch { continue; }
                if (d == null) continue;
                string type = Str(d, "type");
                if (type != "user" && type != "assistant") continue;
                if (d.ContainsKey("isMeta") && d["isMeta"] is bool && (bool)d["isMeta"]) continue;
                Dictionary<string, object> m = d.ContainsKey("message") ? d["message"] as Dictionary<string, object> : null;
                if (m == null) continue;
                object content = m.ContainsKey("content") ? m["content"] : null;
                if (type == "assistant")
                {
                    string sr = Str(m, "stop_reason");
                    if (sr == "tool_use")
                    {
                        kind = "tool";
                        object[] arr = content as object[];
                        if (arr != null)
                            foreach (object o in arr)
                            {
                                Dictionary<string, object> c = o as Dictionary<string, object>;
                                if (c != null && Str(c, "type") == "tool_use") tool = Str(c, "name");
                            }
                    }
                    else kind = sr == null ? "model" : "idle";
                }
                else
                {
                    string first = content as string;
                    object[] arr = content as object[];
                    if (first == null && arr != null && arr.Length > 0)
                    {
                        Dictionary<string, object> c = arr[0] as Dictionary<string, object>;
                        if (c != null)
                        {
                            if (Str(c, "type") == "text") first = Str(c, "text");
                            else if (Str(c, "type") == "tool_result")
                            {
                                object tc = c.ContainsKey("content") ? c["content"] : null;
                                first = tc as string;
                                object[] tca = tc as object[];
                                if (first == null && tca != null && tca.Length > 0)
                                {
                                    Dictionary<string, object> c2 = tca[0] as Dictionary<string, object>;
                                    if (c2 != null) first = Str(c2, "text");
                                }
                            }
                        }
                    }
                    first = (first ?? "").TrimStart();
                    if (first.StartsWith("[Request interrupted") || first.StartsWith("<command-name>") || first.StartsWith("<local-command")
                        || first.StartsWith("<bash-input>") || first.StartsWith("<bash-stdout>") || first.StartsWith("<bash-stderr>"))
                        kind = "idle";
                    else kind = "model";
                }
            }
            return kind;
        }

        static string Str(Dictionary<string, object> d, string key)
        {
            object v;
            return d.TryGetValue(key, out v) ? v as string : null;
        }

        static string Tail(string file, int max)
        {
            using (FileStream fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                long len = fs.Length, start = Math.Max(0, len - max);
                fs.Seek(start, SeekOrigin.Begin);
                byte[] buf = new byte[len - start];
                int got = 0;
                while (got < buf.Length) { int r = fs.Read(buf, got, buf.Length - got); if (r <= 0) break; got += r; }
                string text = Encoding.UTF8.GetString(buf, 0, got);
                if (start > 0) { int nl = text.IndexOf('\n'); text = nl >= 0 ? text.Substring(nl + 1) : ""; }
                return text;
            }
        }

        static string Head(string file, int max)
        {
            using (FileStream fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                byte[] buf = new byte[Math.Min(max, fs.Length)];
                int got = fs.Read(buf, 0, buf.Length);
                return Encoding.UTF8.GetString(buf, 0, Math.Max(0, got));
            }
        }

        // ---------- Codex：~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl ----------
        static readonly System.Text.RegularExpressions.Regex CodexRx = new System.Text.RegularExpressions.Regex(
            "^\\{\"timestamp\":\"([^\"]+)\",\"type\":\"([a-z_]+)\",\"payload\":\\{\"type\":\"([a-z_]+)\"");
        static readonly System.Text.RegularExpressions.Regex NameRx = new System.Text.RegularExpressions.Regex("\"name\":\"([^\"]+)\"");
        static readonly System.Text.RegularExpressions.Regex CwdRx = new System.Text.RegularExpressions.Regex("\"cwd\":\"((?:[^\"\\\\]|\\\\.)*)\"");

        class CodexState { public bool Busy; public string Kind, Tool; public DateTime LastComplete, CompleteStart; }

        static CodexState ParseCodex(string file)
        {
            CodexState st = new CodexState();
            st.Kind = "model";
            bool pending = false;
            DateTime start = DateTime.MinValue;
            foreach (string raw in Tail(file, 512 * 1024).Split('\n'))
            {
                if (raw.Length < 40) continue;
                System.Text.RegularExpressions.Match m = CodexRx.Match(raw.Length > 400 ? raw.Substring(0, 400) : raw);
                if (!m.Success) continue;
                DateTime ts;
                if (!DateTime.TryParse(m.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.AdjustToUniversal | System.Globalization.DateTimeStyles.AssumeUniversal, out ts)) continue;
                string top = m.Groups[2].Value, pt = m.Groups[3].Value;
                if (top == "event_msg")
                {
                    if (pt == "task_started") { st.Busy = true; start = ts; pending = false; }
                    else if (pt == "task_complete") { if (st.Busy || start != DateTime.MinValue) st.CompleteStart = start; st.Busy = false; st.LastComplete = ts; pending = false; }
                    else if (pt == "turn_aborted") { st.Busy = false; pending = false; }
                }
                else if (top == "response_item")
                {
                    if (pt == "function_call" || pt == "custom_tool_call")
                    {
                        pending = true;
                        System.Text.RegularExpressions.Match nm = NameRx.Match(raw.Length > 800 ? raw.Substring(0, 800) : raw);
                        st.Tool = nm.Success ? nm.Groups[1].Value : null;
                    }
                    else if (pt == "function_call_output" || pt == "custom_tool_call_output") pending = false;
                }
            }
            st.Kind = pending ? "tool" : "model";
            return st;
        }

        static string CodexTitle(string file)
        {
            try
            {
                System.Text.RegularExpressions.Match m = CwdRx.Match(Head(file, 16 * 1024));
                if (!m.Success) return null;
                string cwd = m.Groups[1].Value.Replace("\\\\", "\\");
                return Path.GetFileName(cwd.TrimEnd('\\', '/'));
            }
            catch { return null; }
        }

        void CodexWatchOnce(bool relist)
        {
            string root = CodexSessionsDir();
            if (!Directory.Exists(root)) { busyCodex = 0; return; }
            DateTime now = DateTime.UtcNow;
            if (relist)
            {
                List<string> files = new List<string>();
                foreach (FileInfo fi in new DirectoryInfo(root).EnumerateFiles("rollout-*.jsonl", SearchOption.AllDirectories))
                    if ((now - fi.LastWriteTimeUtc).TotalMinutes <= 40) files.Add(fi.FullName);
                codexFiles = files;
            }
            bool anyCodex = Process.GetProcessesByName("codex").Length > 0 || Process.GetProcessesByName("node").Length > 0;
            int busy = 0;
            foreach (string f in codexFiles)
            {
                DateTime act;
                try { act = File.GetLastWriteTimeUtc(f); } catch { continue; }
                if ((now - act).TotalMinutes > 40) continue;
                CodexState st = ParseCodex(f);
                CodexSeen cs;
                if (!codexSeen.TryGetValue(f, out cs)) { cs = new CodexSeen(); cs.LastComplete = st.LastComplete; codexSeen[f] = cs; }
                else if (st.LastComplete > cs.LastComplete)
                {
                    cs.LastComplete = st.LastComplete;
                    double dur = st.CompleteStart == DateTime.MinValue ? 0 : (st.LastComplete - st.CompleteStart).TotalSeconds;
                    double idle = W.IdleSeconds();
                    App.Log("codex done " + (int)dur + "s idle=" + (int)idle + " " + Path.GetFileName(f));
                    if (dur >= 45 || idle >= 30) Post(delegate { OnDone("Codex"); });
                }
                if (st.Busy && anyCodex) busy++;
                string title = st.Busy && (now - act).TotalSeconds >= 85 ? CodexTitle(f) : null;
                StuckCheck(f, "Codex", act, st.Busy ? st.Kind : "idle", st.Tool, title, anyCodex);
            }
            busyCodex = busy;
        }

        // ---------- 事件 → 公仔 ----------
        void OnClaude(string ev, string sid)
        {
            if (ev == "start") { claudeStart[sid] = Now; return; }
            if (Hidden) return;
            double idle = W.IdleSeconds();
            if (ev == "done")
            {
                double started;
                double elapsed = claudeStart.TryGetValue(sid, out started) ? Now - started : 0;
                claudeStart.Remove(sid);
                if (elapsed < 45 && idle < 30) return; // 很快就做完、你也在看 → 不吵你
                OnDone("Claude");
            }
            else if (ev == "wait")
            {
                if (waitCd > 0) return;
                waitCd = 20;
                if (HoldIfQuiet("wait", "Claude 在等你回答")) return;
                Lead().Wait("Claude");
            }
        }

        void OnDone(string src)
        {
            Count("tasks");
            if (HoldIfQuiet("done", src + " 做完了")) return;
            if (Hidden) return;
            doneUntil = Now + 25;
            Pet l = Lead();
            l.Done(src, true);
            foreach (Pet p in OutPets()) if (p != l) p.React();
        }

        void OnStuck(string src, string kind, string tool, string title, int min)
        {
            if (sharing || fsNow) return;
            if (userHidden) { userHidden = false; ApplyHidden(); }
            if (Hidden) return;
            stuckNow = true;
            Pet l = Lead();
            if (quietOn)
            {
                // 安靜中：只冒泡泡
                l.Say(l.L("stuck", "who", src, "n", min.ToString()), 7, true);
                return;
            }
            string who = string.IsNullOrEmpty(title) ? src : src + "（" + (title.Length > 14 ? title.Substring(0, 14) + "…" : title) + "）";
            string text;
            if (tool == "AskUserQuestion" || tool == "ExitPlanMode" || tool == "request_user_input") text = l.L("ask", "who", who);
            else if (kind == "tool") text = l.L("stuck_tool", "who", who, "tool", tool ?? "工具", "n", min.ToString());
            else text = l.L("stuck", "who", who, "n", min.ToString());
            l.Alert(text);
            foreach (Pet p in OutPets()) if (p != l) p.React();
        }

        void OnUnstuck(string src)
        {
            stuckNow = false;
            if (Hidden) return;
            Pet l = Lead();
            l.Unstuck(src);
        }
    }

    // ================= 串場（兩隻碰在一起演一小段）、大合照、點名、晚安 =================
    partial class World
    {
        class Cue { public double At; public Action Do; }
        List<Cue> scene;
        List<Pet> cast = new List<Pet>();
        double sceneT, sceneCd = 20, groupCd = 120;
        readonly Dictionary<string, double> pairCd = new Dictionary<string, double>();
        FlashForm flash;

        public void AbortScene()
        {
            scene = null;
            foreach (Pet p in cast) { p.InScene = false; p.ResetSceneProps(); }
            ClearProps();
            cast.Clear();
        }

        void StepScene(double dt)
        {
            sceneCd -= dt; groupCd -= dt;
            if (scene == null) return;
            sceneT += dt;
            while (scene != null && scene.Count > 0 && sceneT >= scene[0].At)
            {
                Cue c = scene[0]; scene.RemoveAt(0);
                try { c.Do(); } catch (Exception ex) { App.Log("scene: " + ex.Message); }
            }
            if (scene != null && scene.Count == 0) { AbortScene(); sceneCd = 40; }
        }

        void Begin(params Pet[] who)
        {
            AbortScene();
            scene = new List<Cue>(); sceneT = 0;
            foreach (Pet p in who) { p.InScene = true; cast.Add(p); p.WakeIfSleep(); }
        }
        void At(double t, Action a) { Cue c = new Cue(); c.At = t; c.Do = a; scene.Add(c); scene.Sort(delegate(Cue x, Cue y) { return x.At.CompareTo(y.At); }); }

        void CheckCrossover()
        {
            if (scene != null || sceneCd > 0 || Hidden || focusOn || quietOn || !Feat("scenes")) return;
            List<Pet> outs = OutPets();
            if (outs.Count < 2) return;
            List<Pet> free = new List<Pet>();
            foreach (Pet p in outs) if (p.Free()) free.Add(p);
            if (free.Count >= 3 && groupCd <= 0 && rnd.NextDouble() < (TubbyLineup && free.Count >= 4 ? 0.04 : 0.02)) { groupCd = 600; if (TubbyLineup) TubbyGroup(free.Count); else if (PikLineup) PikGroup(free.Count); else if (OrigLineup) OrigGroup(free.Count); else if (rnd.NextDouble() < 0.6) GroupPhoto(); else GroupHug(); return; }
            for (int i = 0; i < free.Count; i++)
                for (int j = i + 1; j < free.Count; j++)
                {
                    Pet a = free[i], b = free[j];
                    if (a.supH != b.supH || Math.Abs(a.Foot - b.Foot) > 3 || Math.Abs(a.Cx - b.Cx) > a.SW * 2.5) continue;
                    string key = PairKey(a, b);
                    double until;
                    if (pairCd.TryGetValue(key, out until) && Now < until) continue;
                    pairCd[key] = Now + 180 + rnd.NextDouble() * 120;
                    PlayScene(key);
                    return;
                }
        }

        static string PairKey(Pet a, Pet b)
        {
            string x = a.P.Id, y = b.P.Id;
            return string.CompareOrdinal(x, y) < 0 ? x + "-" + y : y + "-" + x;
        }

        // 也可以從 pipe 叫：act scene hangyodon-spidey
        void PlayScene(string key)
        {
            string[] ids = key.Split('-');
            if (ids.Length == 1 && (key == "photo" || key == "group")) { GroupPhoto(); return; }
            if (ids.Length == 1 && PikLineup) { PikScene(key); return; }
            if (ids.Length == 1 && OrigLineup) { OrigScene(key); return; }
            if (ids.Length == 1)
            {
                switch (key)
                {
                    case "bighug": SceneBigHug(); return;
                    case "sing": SceneSing(); return;
                    case "fall": SceneFall(); return;
                    case "toast": SceneToast(); return;
                    case "byebye": SceneByeBye(false); return;
                }
                return;
            }
            if (ids.Length != 2) return;
            Array.Sort(ids, string.CompareOrdinal);
            Pet a = Get(ids[0]), b = Get(ids[1]);
            if (a == null || b == null) return;
            if (!a.Out) BringOut(a, false);
            if (!b.Out) BringOut(b, false);
            string k2 = ids[0] + "-" + ids[1];
            pairCd[k2] = Now + 180 + rnd.NextDouble() * 120;
            double d0 = a.Out && b.Out && a.state != "exit" && b.state != "exit" ? 0 : 1.6;
            // 離太遠：先湊到一起再演
            if (TubbyLineup || PikLineup || OrigLineup) { Later(d0, delegate { GatherPair(k2, a, b, 0); }); return; }
            Later(d0, delegate
            {
                if (!Pets.Contains(a) || !Pets.Contains(b)) return;   // 中間換櫃了
                AbortScene();
                double wait = b.ComeNear(a);
                b.InScene = true; a.InScene = true; cast.Add(a); cast.Add(b);
                if (a.Grounded()) a.ScenePose("idle", 30);
                Later(wait + 0.3, delegate { RunScene(k2, a, b); });
            });
        }

        // 天線寶寶一櫃：等兩隻都站穩了才湊過去（剛出櫃還在空中時，算出來的位置會疊在一起），站好後再開演
        void GatherPair(string key, Pet a, Pet b, int tries)
        {
            if (!Pets.Contains(a) || !Pets.Contains(b) || !a.Out || !b.Out) return;
            if ((!a.Grounded() || !b.Grounded()) && tries < 12) { Later(0.35, delegate { GatherPair(key, a, b, tries + 1); }); return; }
            AbortScene();
            b.InScene = true; a.InScene = true; cast.Add(a); cast.Add(b);
            if (a.Grounded()) a.ScenePose("idle", 30);
            double wait = b.ComeNear(a);
            Later(wait + 0.3, delegate { WaitStill(key, a, b, 0); });
        }
        void WaitStill(string key, Pet a, Pet b, int tries)
        {
            if (!Pets.Contains(a) || !Pets.Contains(b) || !a.Out || !b.Out) return;
            if ((!a.Grounded() || !b.Grounded() || b.state == "goto") && tries < 10) { Later(0.3, delegate { WaitStill(key, a, b, tries + 1); }); return; }
            RunScene(key, a, b);
        }

        void RunScene(string key, Pet a, Pet b)
        {
            switch (key)
            {
                case "hangyodon-spidey": SceneHeroes(Get("spidey"), Get("hangyodon")); break;
                case "po-spidey": SceneSling(Get("spidey"), Get("po")); break;
                case "spidey-stitch": SceneClimbRace(Get("spidey"), Get("stitch")); break;
                case "po-stitch": SceneScooterThief(Get("stitch"), Get("po")); break;
                case "hangyodon-stitch": SceneBlueBrothers(Get("stitch"), Get("hangyodon")); break;
                case "hangyodon-po": SceneJoke(Get("po"), Get("hangyodon")); break;
                // 天線寶寶一櫃
                case "dipsy-tinky": SceneHatSwap(Get("tinky"), Get("dipsy")); break;
                case "laalaa-tinky": SceneBallBag(Get("tinky"), Get("laalaa")); break;
                case "dipsy-laalaa": SceneDanceOff(Get("dipsy"), Get("laalaa")); break;
                case "po-tinky": SceneScooterRide(Get("po"), Get("tinky")); break;
                case "dipsy-po": SceneHatBaseball(Get("po"), Get("dipsy")); break;
                case "laalaa-po": SceneBallFetch(Get("laalaa"), Get("po")); break;
                default: if (PikLineup) PikPairScene(key); else if (OrigLineup) OrigPairScene(key); break;
            }
        }

        void Face(Pet a, Pet b) { a.FaceTo(b); b.FaceTo(a); }

        // Spidey × 人魚漢頓：想當英雄的漢頓、鼓勵他的 Spidey
        void SceneHeroes(Pet s, Pet h)
        {
            Begin(s, h);
            At(0, delegate { Face(s, h); s.ScenePose("idle", 13); h.ScenePose("idle", 13); h.Say("你、你是真的英雄耶！", 2); });
            At(2.1, delegate { h.ScenePose("cape", 1.8); h.Say("我也想當英雄…可是我只有一件披風", 2.6); });
            At(4.9, delegate { s.ScenePose("hop", 0); s.Say("英雄不是看披風的", 2.2); });
            At(7.2, delegate { s.Say("你每天逗大家笑，已經是英雄了", 2.6); });
            At(9.9, delegate { h.Say("真、真的嗎？嗚嗚…", 1.8); h.Mark(4); });
            At(11.6, delegate { if (s.Cx < h.Cx) { s.dir = 1; h.dir = -1; } else { s.dir = -1; h.dir = 1; } s.ScenePose("hero", 2.6); h.ScenePose("cape", 2.6); s.Say("英雄合體！", 2.4); h.Say("英雄合體！（好帥！）", 2.4); });
            At(14.4, delegate { });
        }

        // Spidey × 小波：用絲把小波（連車）甩上去
        void SceneSling(Pet s, Pet po)
        {
            Begin(s, po);
            At(0, delegate { Face(s, po); s.ScenePose("idle", 8); po.ScenePose("idle", 8); s.Say("小波，要不要飛高高？", 2); });
            At(2.1, delegate { po.ScenePose("wave", 1.2); po.Say("要要要！Eh-oh!", 1.6); });
            At(3.5, delegate
            {
                s.SlingAt(po);
                Plat best = null;
                foreach (Plat p in Plats) if (p.Top < po.Foot - 80 * k && p.Top > po.Foot - 600 * k && Math.Abs((p.Left + p.Right) / 2.0 - po.Cx) < 700 * k && p.Right - p.Left > po.SW * 2) { best = p; break; }
                if (best != null) po.JumpTo(Math.Max(best.Left + po.SW, Math.Min(best.Right - po.SW, po.Cx)), best.Top);
                else po.Jump(0, -820 * k);
                po.Say("咻～～～", 1.4);
            });
            At(5.6, delegate { po.Say("再來一次！再來一次！", 2); });
            At(7.8, delegate { s.Say("……下次再說 😅", 1.8); });
            At(9.5, delegate { });
        }

        // Spidey × 史迪仔：比賽爬牆
        void SceneClimbRace(Pet s, Pet st)
        {
            Begin(s, st);
            At(0, delegate { Face(s, st); s.ScenePose("idle", 6); st.ScenePose("grin", 1.6); st.Say("ih! 史迪仔也會爬牆！", 1.8); });
            At(1.9, delegate { s.Say("喔？比賽啊！預備…", 1.6); });
            At(3.4, delegate { s.InScene = false; st.InScene = false; s.Act("climb"); st.Signature(); s.Say("開始！", 1); });
            At(9, delegate { if (rnd.NextDouble() < 0.5) st.Say("史迪仔贏了！嘻嘻嘻", 2); else s.Say("Spidey 贏了！Thwip!", 2); });
            At(9.2, delegate { });
        }

        // 史迪仔 × 小波：偷騎滑板車
        void SceneScooterThief(Pet st, Pet po)
        {
            Begin(st, po);
            At(0, delegate { Face(st, po); po.ScenePose("idle", 10); st.ScenePose("grin", 1.2); st.Say("嘻嘻嘻…", 1.2); });
            At(1.3, delegate
            {
                po.LoseScooter(true); st.RidingStolen = true;
                double away = st.Cx > po.Cx ? 1 : -1;
                st.RaceTo(st.Cx + away * 260 * k);
                st.Say("ih-ih-ih! 滑板車！", 1.6);
            });
            At(1.8, delegate { po.Say("我的滑板車！", 2); po.WalkTo(st.Cx, 3); });
            At(4.6, delegate { st.ScenePose("idle", 6); st.FaceTo(po); st.Say("Ohana！一家人不會丟下任何人！", 2.6); st.RidingStolen = false; po.LoseScooter(false); });
            At(5.2, delegate { po.WalkTo(st.Cx + (po.Cx < st.Cx ? -1 : 1) * st.SW * 0.9, 1.5); });
            At(7.4, delegate { Face(st, po); st.ScenePose("hug", 2.4); po.ScenePose("hug", 2.4); po.Say("大抱抱！", 2.2); });
            At(10, delegate { });
        }

        // 史迪仔 × 人魚漢頓：「我們都是藍色的，是兄弟吧？」
        void SceneBlueBrothers(Pet st, Pet h)
        {
            Begin(st, h);
            At(0, delegate { Face(st, h); st.ScenePose("idle", 10); h.ScenePose("idle", 10); h.Say("我們都是藍色的，是兄弟吧？", 2.4); });
            At(2.5, delegate { st.Say("ih?（歪頭）", 1.2); st.Mark(2); });
            At(3.8, delegate { st.WalkTo(h.Cx + (st.Cx < h.Cx ? -1 : 1) * h.SW * 0.8, 1.0); });
            At(5.0, delegate { Face(st, h); st.ScenePose("lick", 1.4); st.Say("（舔）", 1.2); h.Mark(4); });
            At(6.5, delegate { h.Say("嘻嘻…好癢！這是兄弟的打招呼嗎？", 2.4); });
            At(9.0, delegate { st.ScenePose("hug", 2.4); h.ScenePose("hug", 2.4); st.Say("Ohana！", 2.2); h.Say("Ohana…我有家人了 ♥", 2.4); });
            At(11.6, delegate { });
        }

        // 小波 × 人魚漢頓：笑話讓小波笑了，漢頓超開心
        void SceneJoke(Pet po, Pet h)
        {
            Begin(po, h);
            At(0, delegate { Face(po, h); po.ScenePose("idle", 11); h.ScenePose("idle", 11); h.Say("小波，要聽笑話嗎？", 1.8); });
            At(1.9, delegate { po.ScenePose("wave", 1); po.Say("要！Eh-oh!", 1.4); });
            At(3.4, delegate { h.Say("為什麼魚不會打網球？…因為怕碰到網子！", 3); });
            At(6.6, delegate { po.ScenePose("hop", 0); po.Say("嘻嘻嘻！再來一次！再來一次！", 2.2); });
            At(8.9, delegate { h.ScenePose("cape", 2); h.Say("她笑了！有人笑了！我、我好開心！", 2.6); for (int i = 0; i < 4; i++) h.Mark(5); });
            At(11.6, delegate { Face(po, h); po.ScenePose("hug", 2.2); h.ScenePose("hug", 2.2); po.Say("大抱抱！", 2); });
            At(14, delegate { });
        }

        // 三隻以上：大合照（排一排、閃光、笑一個）
        void GroupPhoto()
        {
            if (OrigLineup) { OrigPhoto(); return; }
            List<Pet> outs = OutPets();
            if (outs.Count < 2) { AllOut(); Later(2.5, GroupPhoto); return; }
            Pet l = Lead();
            Begin(outs.ToArray());
            double gap = TubbyLineup ? 1.9 : 1.6;   // 天線寶寶比較寬（帽子、袋子、球）
            double foot = l.Foot, left = l.Cx - (outs.Count - 1) * l.SW * gap / 2, right = left + (outs.Count - 1) * l.SW * gap;
            if (!l.OnFloor) foreach (Plat p in Plats) if (p.H == l.supH) { left = Math.Max(left, p.Left + l.SW / 2.0); right = Math.Min(right, p.Right - l.SW / 2.0); }
            Rectangle wa = WA(l.Cx, foot - 4);
            left = Math.Max(left, wa.Left + l.SW); right = Math.Min(Math.Max(right, left), wa.Right - l.SW);
            At(0, delegate { l.Say("大家來拍照～排好排好！", 2); });
            for (int i = 0; i < outs.Count; i++)
            {
                Pet p = outs[i];
                double tx = outs.Count == 1 ? left : left + (right - left) * i / (outs.Count - 1);
                At(0.4 + i * 0.35, delegate
                {
                    if (Math.Abs(p.Foot - foot) < 3 && p.supH == l.supH && Math.Abs(tx - p.Cx) < 600 * k) p.WalkTo(tx, 10);
                    else if (p.P.Id == "hangyodon") p.StartSwim(tx, foot, false);
                    else p.JumpTo(tx, foot);
                });
            }
            At(5.2, delegate
            {
                foreach (Pet p in outs)
                {
                    p.dir = p.Cx < (left + right) / 2 ? 1 : -1;
                    if (p.P.Id == "hangyodon") p.ScenePose("cape", 3); else if (p.P.Id == "stitch") p.ScenePose("grin", 3); else if (p.P.Id == "dipsy") p.ScenePose("hattip", 3); else p.ScenePose("photo", 3);
                }
                l.Say("笑一個～ 3、2、1！", 1.6);
            });
            At(6.6, delegate { Flash(Rectangle.FromLTRB((int)(left - 120 * k), (int)(foot - 200 * k), (int)(right + 120 * k), (int)(foot + 20 * k))); });
            if (TubbyLineup)
            {
                // 天線寶寶一櫃：一隻一隻講（站很近，同時講泡泡會疊在一起）
                double d = 7.4;
                foreach (Pet p in ShowOrder(outs))
                {
                    Pet pp = p;
                    string line = pp.P.Id == "tinky" ? "魔法袋有拍進去嗎？" : (pp.P.Id == "dipsy" ? "帽子有拍到吧？酷。" : (pp.P.Id == "laalaa" ? "啦啦～好好看！" : "再拍一次！"));
                    At(d, delegate { pp.Say(line, 1.15); });
                    d += 1.2;
                }
                At(d + 0.4, delegate { });
                return;
            }
            At(7.4, delegate
            {
                foreach (Pet p in outs)
                    switch (p.P.Id)
                    {
                        case "po": p.Say("再拍一次！", 1.8); break;
                        case "stitch": p.Say("Ohana！", 1.8); break;
                        case "hangyodon": p.Say("我有被拍進去嗎？嘴唇太大了嗎？", 1.8); break;
                        case "pkred": case "pkyellow": case "pkblue": p.Say("噗咿！", 1.8); break;
                        default: p.Say("帥！", 1.8); break;
                    }
            });
            At(9.5, delegate { });
        }

        // 大家一起抱抱滑鼠
        void GroupHug()
        {
            List<Pet> outs = OutPets();
            Begin(outs.ToArray());
            At(0, delegate { foreach (Pet p in outs) { p.InScene = false; p.Hug(p.L("hugs"), 2.6); } });
            At(0.2, delegate { });
        }

        void Flash(Rectangle r)
        {
            if (Hidden) return;
            if (flash == null) flash = new FlashForm();
            flash.Bounds = r;
            flash.Opacity = 0.8;
            flash.Show(); W.KeepOnTop(flash);
            Later(0.08, delegate { flash.Opacity = 0.5; });
            Later(0.16, delegate { flash.Opacity = 0.25; });
            Later(0.26, delegate { flash.Hide(); });
        }

        // 早上第一次：一隻一隻從櫃子跳出來點名
        void StartRollCall(List<string> ids)
        {
            if (TubbyLineup) { TubbyRollCall(ids); return; }
            if (PikLineup) { PikRollCall(ids); return; }
            if (OrigLineup) { OrigRollCall(ids); return; }
            double d = 0.4;
            foreach (string id in ids)
            {
                Pet p = Get(id);
                if (p == null) continue;
                Pet pp = p;
                Later(d, delegate { if (!pp.Out) BringOut(pp, false); });
                Later(d + 0.6, delegate { pp.Say(pp.L("morning"), 2.6); });
                d += 1.6;
            }
        }

        // 下班了：輪流催你回家，然後一隻一隻回櫃子（人魚漢頓先在泡泡裡睡著）
        void NightRitual()
        {
            if (TubbyLineup) { SceneByeBye(true); return; }
            if (PikLineup) { PikNight(true); return; }
            if (OrigLineup) { OrigNight(true); return; }
            List<Pet> outs = OutPets();
            outs.Sort(delegate(Pet a, Pet b) { return (a.P.Id == "hangyodon" ? 0 : 1).CompareTo(b.P.Id == "hangyodon" ? 0 : 1); });
            Begin(outs.ToArray());
            foreach (Pet p in outs) if (p.Grounded()) p.ScenePose("idle", 60);
            double d = 0.2;
            foreach (Pet p in outs) { Pet pp = p; At(d, delegate { pp.Say(pp.L("nag"), 2.6); }); d += 2.8; }
            foreach (Pet p in outs)
            {
                Pet pp = p;
                if (pp.P.Id == "hangyodon") { At(d, delegate { pp.InScene = false; pp.Act("sleep"); pp.InScene = true; pp.Say("我先在泡泡裡睡了…你也不要一個人待太晚喔", 2.6); }); d += 2.8; }
                At(d, delegate { pp.Say(pp.L("goodnight"), 2.4); });
                At(d + 1.2, delegate { pp.InScene = false; if (pp.Out) pp.StowToShelf(false); });
                d += 2.6;
            }
            At(d + 0.5, delegate { });
        }
    }

    // 串場用的小道具（丟來丟去的帽子、球、吐司）和小幫手「吸吸」：一張像素圖，點得穿
    class SpriteForm : OverlayForm
    {
        string[] art; Dictionary<char, Color> pal; int ps; bool flip;
        public SpriteForm() : base(true) { }
        int Halo { get { return Math.Max(1, ps / 3); } }
        public void Set(string[] a, Dictionary<char, Color> p, int pixel, bool fx)
        {
            if (a == art && p == pal && pixel == ps && fx == flip) return;
            bool resize = art == null || a.Length != art.Length || a[0].Length != art[0].Length || pixel != ps;
            art = a; pal = p; ps = pixel; flip = fx;
            if (resize) Size = new Size(a[0].Length * ps + 2 * Halo, a.Length * ps + 2 * Halo);
            Invalidate();
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(KEY);
            if (art == null) return;
            int hw = Halo;
            using (SolidBrush hb = new SolidBrush(Color.White))
                for (int pass = 0; pass < 2; pass++)
                    for (int ry = 0; ry < art.Length; ry++)
                        for (int rx = 0; rx < art[ry].Length; rx++)
                        {
                            char c = art[ry][rx];
                            if (c == '.') continue;
                            int px = hw + (flip ? art[ry].Length - 1 - rx : rx) * ps, py = hw + ry * ps;
                            if (pass == 0) { g.FillRectangle(hb, px - hw, py - hw, ps + 2 * hw, ps + 2 * hw); continue; }
                            Color col;
                            if (!pal.TryGetValue(c, out col)) col = Color.Magenta;
                            using (SolidBrush b = new SolidBrush(col)) g.FillRectangle(b, px, py, ps, ps);
                        }
        }
    }

    // ================= 天線寶寶一櫃的串場（兩隻、大家一起）、點名、說再見 =================
    partial class World
    {
        class Prop
        {
            public SpriteForm F; public string[] A, A2; public Pal Owner; public int Ps; public bool Spin, Fx;
            public double X0, Y0, X, Y, T, Hold;
            public readonly List<double[]> Legs = new List<double[]>();     // 目標 x、y、秒數、拋物線高度
            public readonly List<Action> Then = new List<Action>();
            public Prop Go(double x1, double y1, double dur, double arc, Action then) { Legs.Add(new double[] { x1, y1, Math.Max(0.05, dur), arc }); Then.Add(then); return this; }
        }
        readonly List<Prop> props = new List<Prop>();
        static readonly string[] BASEBALL_ART = { ".33.", "3433", "3343", ".33." };
        static readonly string[] TOAST_ART = { ".2222.", "211112", "2k11k2", "211112", "21kk12", ".2222." };
        // 吸吸：原創的圓圓掃地小機器人（前面一根短短的吸管鼻子），兩格輪流＝輪子在轉
        static readonly string[] BOT_A = { "....kkkkkk......", "..kkvvvvvvkk....", ".kvvWvvvvvvvk...", ".kvkWvvkWvvvkkkk", "kvvkkvvkkvvvkvVk", "kvvvvvvvvvvvkkkk", "kVVVVVVVVVVVk...", ".kkkkkkkkkkkk...", "..kOk....kOk...." };
        static readonly string[] BOT_B = { "....kkkkkk......", "..kkvvvvvvkk....", ".kvvWvvvvvvvk...", ".kvkWvvkWvvvk...", "kvvkkvvkkvvvkkkk", "kvvvvvvvvvvvkvVk", "kVVVVVVVVVVVkkkk", ".kkkkkkkkkkkk...", "...kOk..kOk....." };

        Prop NewProp(string[] a, string[] a2, Pal owner, int ps, double x, double y, bool spin)
        {
            Prop p = new Prop();
            p.F = new SpriteForm(); p.A = a; p.A2 = a2; p.Owner = owner; p.Ps = ps; p.Spin = spin;
            p.X0 = p.X = x; p.Y0 = p.Y = y;
            props.Add(p);
            PlaceProp(p);
            return p;
        }

        // 丟一個小道具：從 a 拋物線飛到 b（中心點），到了做 done，停 hold 秒再消失
        Prop Toss(string[] art, Pal owner, PointF a, PointF b, double dur, double arc, bool spin, double hold, Action done)
        {
            if (owner == null || Hidden) { if (done != null) done(); return null; }
            Prop p = NewProp(art, null, owner, S, a.X, a.Y, spin);
            p.Go(b.X, b.Y, dur, arc, done);
            p.Hold = hold;
            return p;
        }

        void RemoveProp(Prop p) { if (p == null) return; props.Remove(p); p.F.Close(); }
        void ClearProps() { foreach (Prop p in props) p.F.Close(); props.Clear(); }

        void PlaceProp(Prop p)
        {
            bool alt = p.A2 != null && Math.Floor(p.T * 7) % 2 == 1;
            bool fx = p.Spin ? Math.Floor(p.T * 8) % 2 == 1 : p.Fx;
            p.F.Set(alt ? p.A2 : p.A, Night ? p.Owner.Night : p.Owner.Day, p.Ps, fx);
            p.F.Location = new Point((int)Math.Round(p.X - p.F.Width / 2.0), (int)Math.Round(p.Y - p.F.Height / 2.0));
            if (Hidden) { if (W.Shown(p.F)) p.F.Hide(); }
            else if (!W.Shown(p.F)) { p.F.Show(); W.KeepOnTop(p.F); }
        }

        void StepProps(double dt)
        {
            for (int i = props.Count - 1; i >= 0; i--)
            {
                if (i >= props.Count) continue;
                Prop p = props[i];
                if (p.Legs.Count > 0)
                {
                    double[] leg = p.Legs[0];
                    p.T += dt;
                    double f = Math.Min(1, p.T / leg[2]);
                    if (Math.Abs(leg[0] - p.X0) > 1) p.Fx = leg[0] < p.X0;
                    p.X = p.X0 + (leg[0] - p.X0) * f;
                    p.Y = p.Y0 + (leg[1] - p.Y0) * f - Math.Sin(Math.PI * f) * leg[3];
                    PlaceProp(p);
                    if (f >= 1)
                    {
                        p.X0 = leg[0]; p.Y0 = leg[1]; p.T = 0;
                        p.Legs.RemoveAt(0);
                        Action then = p.Then[0]; p.Then.RemoveAt(0);
                        if (then != null) { try { then(); } catch (Exception ex) { App.Log("prop: " + ex.Message); } }
                    }
                    continue;
                }
                p.Hold -= dt;
                if (p.Hold <= 0) { props.Remove(p); p.F.Close(); }
                else PlaceProp(p);
            }
        }

        static double Mid(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }

        // 大家排成一排（走過去或跳過去）：回傳 {左, 右, 腳}
        double[] LineUp(List<Pet> outs, Pet l, double spacing)
        {
            double foot = l.Foot, left = l.Cx - (outs.Count - 1) * l.SW * spacing / 2, right = left + (outs.Count - 1) * l.SW * spacing;
            if (!l.OnFloor) foreach (Plat p in Plats) if (p.H == l.supH) { left = Math.Max(left, p.Left + l.SW / 2.0); right = Math.Min(right, p.Right - l.SW / 2.0); }
            Rectangle wa = WA(l.Cx, foot - 4);
            left = Math.Max(left, wa.Left + l.SW); right = Math.Min(Math.Max(right, left), wa.Right - l.SW);
            for (int i = 0; i < outs.Count; i++)
            {
                Pet p = outs[i];
                double tx = outs.Count == 1 ? left : left + (right - left) * i / (outs.Count - 1);
                At(0.4 + i * 0.35, delegate
                {
                    if (Math.Abs(p.Foot - foot) < 3 && p.supH == l.supH && Math.Abs(tx - p.Cx) < 600 * k) p.WalkTo(tx, 10);
                    else p.JumpTo(tx, foot);
                });
            }
            return new double[] { left, right, foot };
        }

        // 照節目的順序：丁丁、迪西、拉拉、小波
        List<Pet> ShowOrder(List<Pet> l)
        {
            List<Pet> o = new List<Pet>();
            foreach (string id in Pal.LineupIds(Pal.Teletubbies)) foreach (Pet p in l) if (p.P.Id == id) o.Add(p);
            foreach (Pet p in l) if (!o.Contains(p)) o.Add(p);
            return o;
        }

        void TubbyGroup(int n)
        {
            double r = rnd.NextDouble();
            if (n >= 4)
            {
                if (r < .30) SceneBigHug(); else if (r < .50) SceneSing(); else if (r < .70) SceneToast(); else if (r < .85) SceneFall(); else GroupPhoto();
            }
            else
            {
                if (r < .25) SceneSing(); else if (r < .50) SceneToast(); else if (r < .70) SceneFall(); else if (r < .90) GroupPhoto(); else SceneBigHug();
            }
        }

        // ---------- 丁丁 × 迪西：帽子借我戴 ----------
        void SceneHatSwap(Pet ti, Pet di)
        {
            Begin(ti, di);
            At(0, delegate { Face(ti, di); ti.ScenePose("idle", 30); di.ScenePose("hattip", 1.8); ti.Say("迪西，你的帽子好好看喔…", 2.2); });
            At(2.3, delegate { ti.Say("可以借丁丁戴一下嗎？", 2); ti.AddHeart(); });
            At(4.4, delegate { di.ScenePose("idle", 30); di.Say("不行。這是我的帽子。", 2); });
            At(6.5, delegate { ti.ScenePose("hug", 1.8); ti.Say("拜託～一下下就好", 1.8); });
            At(8.5, delegate
            {
                di.Say("……好啦，一下下喔。", 1.8);
                di.LendHat(true);
                Toss(Pal.Get("dipsy").Art["HAT"], Pal.Get("dipsy"), di.HatPoint(), ti.HatPoint(), 0.7, 70 * k, true, 0, delegate { ti.WearHat = true; ti.Burst(6); });
            });
            At(9.6, delegate { ti.ScenePose("dance", 3); ti.Say("我是迪西！嘿～嘿～", 2.4); });
            At(10.4, delegate { di.Say("（頭頂涼涼的）", 1.8); di.Mark(2); });
            At(12.7, delegate
            {
                ti.ScenePose("plop", 1.8); ti.Say("哎喲！", 1.4);
                ti.WearHat = false;
                Toss(Pal.Get("dipsy").Art["HAT"], Pal.Get("dipsy"), ti.HatPoint(), di.HatPoint(), 0.75, 90 * k, true, 0, delegate { di.LendHat(false); });
            });
            At(14.2, delegate { di.ScenePose("hattip", 2); di.Say("還是我戴最帥。", 2); });
            At(16.4, delegate { Face(ti, di); ti.ScenePose("hug", 2.4); di.ScenePose("hug", 2.4); ti.Say("大抱抱！", 2.2); di.Say("…大抱抱。", 2.2); });
            At(19, delegate { });
        }

        // ---------- 丁丁 × 拉拉：球滾進魔法袋 ----------
        void SceneBallBag(Pet ti, Pet la)
        {
            Begin(ti, la);
            string[] ball = la.P.Art["BALL"];
            At(0, delegate { Face(ti, la); ti.ScenePose("idle", 30); la.ScenePose("juggle", 2.6); la.Say("丁丁看！拉拉的球～啦啦啦", 2.4); });
            At(2.8, delegate
            {
                la.ScenePose("kick", 0.5); la.Say("踢～！", 1); la.LoseBall(true);
                ti.ScenePose("bag:", 3.4);
                Toss(ball, la.P, la.FootPoint(), ti.BagPoint(), 0.8, 90 * k, false, 0, delegate { ti.Say("喔？（咕嘟）", 1.2); ti.Mark(2); });
            });
            At(5.0, delegate { la.ScenePose("idle", 30); la.Say("咦？我的球呢？", 1.8); la.Mark(2); });
            At(7.0, delegate { ti.ScenePose("bag:toast", 2.4); ti.Say("丁丁找找看…", 1.2); });
            At(8.2, delegate { ti.Say("是吐司！", 1.6); });
            At(9.8, delegate { la.Say("不是這個啦～", 1.8); });
            At(11.6, delegate { ti.ScenePose("bag:ball", 2.2); ti.Say("再找找…", 1.2); });
            At(12.8, delegate { ti.Say("找到了！", 1.4); });
            At(13.85, delegate
            {
                PointF a = ti.BagPoint(); a.Y -= 6 * S;
                Toss(ball, la.P, a, la.HandPoint(), 0.7, 70 * k, false, 0, delegate { la.LoseBall(false); la.ScenePose("twirl", 1.6); la.Say("再來一次！再來一次！", 2); });
            });
            At(16.6, delegate { Face(ti, la); ti.ScenePose("hug", 2.4); la.ScenePose("hug", 2.4); ti.Say("大抱抱！", 2.2); la.Say("大抱抱！", 2.2); });
            At(19.2, delegate { });
        }

        // ---------- 迪西 × 拉拉：跳舞比賽，最後一起唱 ----------
        void SceneDanceOff(Pet di, Pet la)
        {
            Begin(di, la);
            At(0, delegate { Face(di, la); di.ScenePose("idle", 30); la.ScenePose("idle", 30); di.Say("拉拉，來比跳舞。", 2); });
            At(2.2, delegate { di.ScenePose("dance", 2.6); di.Say("嘿～嘿～（帽子跟著晃）", 2.4); });
            At(5.0, delegate { di.ScenePose("idle", 30); la.ScenePose("twirl", 2.2); la.Say("換我！啦啦啦～", 2.2); });
            At(7.5, delegate { la.ScenePose("idle", 30); di.ScenePose("hattoss", 1.6); di.Say("帽子戲法！", 1.6); });
            At(9.4, delegate { la.ScenePose("juggle", 2.7); la.Say("球球戲法！1、2、3～", 2.4); });
            At(12.3, delegate { di.ScenePose("dance", 3); la.ScenePose("dance", 3); la.Say("一起跳！啦啦啦～♪", 2.6); di.Say("嘿～♪", 1.6); di.Mark(0); la.Mark(0); });
            At(15.5, delegate { Face(di, la); di.ScenePose("wave", 1.8); la.ScenePose("wave", 1.8); di.Say("Eh-oh.", 1.6); la.Say("Eh-oh!", 1.6); });
            At(17.6, delegate { });
        }

        // ---------- 小波 × 丁丁：借騎滑板車，太大了跌坐 ----------
        void SceneScooterRide(Pet po, Pet ti)
        {
            Begin(po, ti);
            At(0, delegate { Face(po, ti); po.ScenePose("idle", 30); ti.ScenePose("idle", 30); ti.Say("小波，丁丁可以騎你的滑板車嗎？", 2.4); });
            At(2.5, delegate { po.ScenePose("wave", 1.2); po.Say("好啊！Eh-oh!", 1.6); });
            At(4.0, delegate
            {
                po.LendScooter(true); ti.RidingPo = true;
                double away = ti.Cx > po.Cx ? 1 : -1;
                Rectangle wa = WA(ti.Cx, ti.Foot - 4);
                ti.RaceTo(Mid(ti.Cx + away * 200 * k, wa.Left + ti.SW, wa.Right - ti.SW));
                ti.Say("嘟嘟～丁丁騎車車！", 1.8);
            });
            At(6.4, delegate { ti.Say("哎…哎…好晃…", 1.4); ti.Mark(4); });
            At(7.8, delegate { ti.RidingPo = false; po.LendScooter(false); ti.ScenePose("plop", 1.8); ti.Say("哎喲！", 1.4); });
            At(9.2, delegate { po.ScenePose("hop", 0); po.Say("再來一次！再來一次！", 2); });
            At(11.4, delegate { ti.Say("…丁丁太大了啦，嘻嘻", 2); });
            At(13.2, delegate { po.WalkTo(ti.Cx + (po.Cx < ti.Cx ? -1 : 1) * ti.SW * 0.9, 1.5); });
            At(15.2, delegate { Face(po, ti); po.ScenePose("hug", 2.4); ti.ScenePose("hug", 2.4); po.Say("大抱抱！", 2.2); ti.Say("大抱抱！", 2.2); });
            At(17.8, delegate { });
        }

        // ---------- 小波 × 迪西：棒球用帽子頂、用帽子接 ----------
        void SceneHatBaseball(Pet po, Pet di)
        {
            Begin(po, di);
            At(0, delegate { Face(po, di); po.ScenePose("idle", 30); di.ScenePose("idle", 30); po.Say("迪西，接球！", 1.6); });
            At(1.6, delegate { po.ScenePose("bat", 0); });
            At(1.85, delegate
            {
                PointF top = di.HatPoint(); top.Y -= 4 * S;
                Toss(BASEBALL_ART, po.P, po.HandPoint(), top, 0.7, 60 * k, false, 0, delegate
                {
                    di.ScenePose("header", 0.6); di.Say("帽子頂！", 1.2);
                    PointF t2 = di.HatPoint(); t2.Y -= 4 * S;
                    Toss(BASEBALL_ART, po.P, t2, po.HandPoint(), 0.8, 80 * k, false, 0, delegate { po.ScenePose("catch", 0.7); po.Say("好球！", 1.4); });
                });
            });
            At(5.4, delegate { po.Say("這次全壘打！", 1.4); });
            At(6.6, delegate { po.ScenePose("bat", 0); di.ScenePose("hatwave", 3.2); });
            At(6.85, delegate
            {
                PointF hand = new PointF((float)(di.Cx + di.dir * 5 * S), (float)(di.Foot - di.SH + (di.P.BodyTop - 5) * S));
                Toss(BASEBALL_ART, po.P, po.HandPoint(), hand, 1.1, 170 * k, false, 0, delegate { di.Say("（用帽子接住）酷。", 2); di.Burst(6); });
            });
            At(10.4, delegate { po.ScenePose("hop", 0); po.Say("再來一次！再來一次！", 2); });
            At(12.6, delegate { di.ScenePose("hattip", 1.8); di.Say("好啦，明天再來一次。", 2); });
            At(14.8, delegate { Face(po, di); po.ScenePose("wave", 1.8); di.ScenePose("wave", 1.8); po.Say("Eh-oh!", 1.6); di.Say("Eh-oh.", 1.6); });
            At(16.8, delegate { });
        }

        // ---------- 拉拉 × 小波：踢球、小波騎車去撿 ----------
        void SceneBallFetch(Pet la, Pet po)
        {
            Begin(la, po);
            string[] ball = la.P.Art["BALL"];
            double tx = po.Cx;
            Prop lying = null;
            At(0, delegate { Face(la, po); la.ScenePose("idle", 30); po.ScenePose("idle", 30); la.Say("小波！我們來踢球！", 2); });
            At(2.0, delegate { po.ScenePose("wave", 1.0); po.Say("好！Eh-oh!", 1.4); });
            At(3.4, delegate
            {
                la.ScenePose("kick", 0.5); la.Say("踢～！", 1); la.LoseBall(true);
                Rectangle wa = WA(la.Cx, la.Foot - 4);
                double side = po.Cx >= la.Cx ? 1 : -1;
                tx = Mid(po.Cx + side * 220 * k, wa.Left + po.SW, wa.Right - po.SW);
                lying = Toss(ball, la.P, la.FootPoint(), new PointF((float)tx, (float)(la.Foot - 3.5 * S)), 1.0, 130 * k, false, 30, null);
            });
            At(3.9, delegate { po.RaceTo(tx); po.Say("我去撿！嘟嘟～", 1.6); });
            At(6.4, delegate { RemoveProp(lying); po.FaceTo(la); po.Say("找到了！", 1.4); });
            At(7.2, delegate { Toss(ball, la.P, po.HandPoint(), la.HandPoint(), 0.9, 110 * k, false, 0, delegate { la.LoseBall(false); la.ScenePose("twirl", 1.6); la.Say("再來一次！", 1.6); po.Say("再來一次！", 1.6); }); });
            At(9.8, delegate { po.WalkTo(la.Cx + (po.Cx < la.Cx ? -1 : 1) * la.SW * 1.0, 1.5); });
            At(12.0, delegate { Face(la, po); la.ScenePose("hug", 2.4); po.ScenePose("hug", 2.4); la.Say("大抱抱！", 2.2); po.Say("大抱抱！", 2.2); });
            At(14.6, delegate { });
        }

        // ---------- 大家：大抱抱 ----------
        void SceneBigHug()
        {
            List<Pet> outs = OutPets();
            if (outs.Count < 2) { AllOut(); Later(2.5, SceneBigHug); return; }
            Pet l = Lead();
            Begin(outs.ToArray());
            double[] lr = LineUp(ShowOrder(outs), l, 1.05);
            bool all4 = outs.Count >= 4;
            At(0, delegate { l.Say(all4 ? "大家都到齊了！" : "大家過來～", 1.8); });
            At(4.8, delegate
            {
                foreach (Pet p in outs) { p.dir = p.Cx < (lr[0] + lr[1]) / 2 ? 1 : -1; p.ScenePose("hug", 3.4); p.Burst(5); }
                l.Say(all4 ? "四個一起，大～抱抱！" : "大抱抱！", 2.6);
            });
            At(8.6, delegate { foreach (Pet p in outs) p.ScenePose("wave", 1.6); l.Say("Eh-oh! ♥", 1.6); });
            At(10.4, delegate { });
        }

        static string SingLine(Pet p)
        {
            switch (p.P.Id)
            {
                case "tinky": return "啦～啦～（丁丁跳舞）";
                case "dipsy": return "嘿～嘿～（打拍子）";
                case "laalaa": return "啦啦啦～♪";
                case "po": return "啦啦！再來一次！";
            }
            return "♪～";
        }

        // ---------- 大家：拉拉起頭，一隻一隻加入唱歌跳舞 ----------
        void SceneSing()
        {
            List<Pet> outs = OutPets();
            if (outs.Count < 2) { AllOut(); Later(2.5, SceneSing); return; }
            Pet la = Get("laalaa");
            Pet starter = la != null && la.Out && outs.Contains(la) ? la : Lead();
            Begin(outs.ToArray());
            LineUp(ShowOrder(outs), Lead(), 1.8);
            At(0, delegate { starter.Say("大家過來～我們來唱歌！", 2); });
            At(4.6, delegate { foreach (Pet p in outs) { p.FaceTo(starter); p.ScenePose("idle", 30); } starter.ScenePose("sing", 30); starter.Say("啦啦啦～大家一起唱！♪", 2.4); });
            double d = 7.2;
            foreach (Pet p in ShowOrder(outs))
            {
                if (p == starter) continue;
                Pet pp = p;
                At(d, delegate { pp.ScenePose(pp.P.Id == "po" ? "spin" : "dance", 30); pp.Say(SingLine(pp), 2); pp.Mark(0); });
                d += 1.9;
            }
            At(d + 0.4, delegate { foreach (Pet p in outs) { p.ScenePose(p.P.Id == "laalaa" ? "twirl" : "dance", 2.6); p.Mark(0); p.Mark(0); } starter.Say("啦啦啦～大家一起～♪", 2.4); });
            At(d + 3.2, delegate { foreach (Pet p in outs) p.ScenePose("wave", 1.6); starter.Say("再來一次！", 1.6); });
            At(d + 5.0, delegate { });
        }

        // ---------- 大家：一、二、三，一起跌倒「哎喲！」 ----------
        void SceneFall()
        {
            List<Pet> outs = OutPets();
            if (outs.Count < 2) { AllOut(); Later(2.5, SceneFall); return; }
            Pet l = Lead();
            Begin(outs.ToArray());
            LineUp(ShowOrder(outs), l, 1.6);
            At(0, delegate { l.Say("大家排好～", 1.6); });
            At(4.6, delegate { foreach (Pet p in outs) p.ScenePose("idle", 30); l.Say("大家一起…一、二、三！", 2); });
            At(6.6, delegate { foreach (Pet p in outs) p.ScenePose("hop", 0); });
            At(7.3, delegate { foreach (Pet p in outs) { p.ScenePose("plop", 2.2); p.Mark(4); } l.Say("哎喲！", 1.4); });
            At(9.5, delegate { foreach (Pet p in outs) p.ScenePose("idle", 30); l.Say("嘻嘻嘻～大家都跌倒了", 1.8); });
            At(11.4, delegate { l.Say("再來一次！", 1.6); foreach (Pet p in outs) p.ScenePose("hop", 0); });
            At(12.8, delegate { });
        }

        // ---------- 大家：吐司時間（吐司彈出來，屑屑掉滿地，吸吸來打掃）----------
        void SceneToast()
        {
            List<Pet> outs = OutPets();
            if (outs.Count < 2) { AllOut(); Later(2.5, SceneToast); return; }
            Pet l = Lead();
            Begin(outs.ToArray());
            List<Pet> order = ShowOrder(outs);
            double[] lr = LineUp(order, l, 1.75);
            double cx = (lr[0] + lr[1]) / 2, foot = lr[2];
            At(0, delegate { l.Say("吐司時間！🍞", 1.8); });
            At(4.2, delegate { foreach (Pet p in outs) { p.FaceTo(l); p.ScenePose("idle", 30); } l.Say("吐司！吐司！吐司！", 2); });
            double d = 4.6;
            foreach (Pet p in order)
            {
                Pet pp = p;
                At(d, delegate
                {
                    Toss(TOAST_ART, pp.P, new PointF((float)cx, (float)(foot - 2 * S)), pp.HandPoint(), 0.75, 170 * k, true, 0, delegate { pp.HoldToast = true; pp.Say("吐司！", 0.65); });
                });
                d += 0.7;
            }
            At(d + 0.8, delegate { l.Say("好好吃～屑屑掉滿地了", 2); });
            At(d + 3.0, delegate { order[order.Count - 1].Say("糟糕…要打掃了！", 1.8); });
            At(d + 3.6, delegate { StartBot(cx, foot); });
            At(d + 4.6, delegate { order[0].Say("吸吸來了！", 1.6); foreach (Pet p in outs) p.Mark(1); });
            At(d + 6.8, delegate { foreach (Pet p in outs) { p.HoldToast = false; p.ClearCrumbs(); } l.Say("吸～吸～好乾淨！", 2); });
            At(d + 9.4, delegate { foreach (Pet p in outs) p.ScenePose("wave", 1.6); l.Say("吸吸，謝謝你！Eh-oh!", 2); });
            At(d + 11.6, delegate { });
        }

        // 吸吸：從比較近的螢幕邊滾進來，在大家腳邊來回吸，再滾出去
        void StartBot(double cx, double foot)
        {
            if (Hidden) return;
            Rectangle wa = WA(cx, foot - 4);
            int ps = Math.Max(2, S * 3 / 4);
            bool fromLeft = cx - wa.Left < wa.Right - cx;
            double sx = fromLeft ? wa.Left - 8 * ps : wa.Right + 8 * ps, ex = fromLeft ? wa.Right + 10 * ps : wa.Left - 10 * ps;
            double by = foot - 4.5 * ps - Math.Max(1, ps / 3);
            Pal owner = Pal.Get("tinky");
            Prop b = NewProp(BOT_A, BOT_B, owner, ps, sx, by, false);
            double sweep = 90 * k, side = fromLeft ? 1 : -1;
            double t1 = Math.Min(3.0, Math.Abs(cx - sx) / (260 * k) + 0.6);
            b.Go(cx - side * sweep, by, t1, 0, null)
             .Go(cx + side * sweep, by, 1.4, 0, null)
             .Go(cx - side * sweep * 0.5, by, 1.0, 0, null)
             .Go(cx + side * sweep * 0.3, by, 0.7, 0, null)
             .Go(ex, by, Math.Min(3.0, Math.Abs(ex - cx) / (260 * k) + 0.6), 0, null);
            b.Hold = 0;
        }

        // ---------- 早上點名：丁丁！迪西！拉拉！小波！天線寶寶，Eh-oh! ----------
        void TubbyRollCall(List<string> ids)
        {
            List<Pet> order = new List<Pet>();
            foreach (string id in Pal.LineupIds(lineup)) if (ids.Contains(id) && Get(id) != null) order.Add(Get(id));
            double d = 0.4;
            foreach (Pet p in order)
            {
                Pet pp = p;
                Later(d, delegate { if (!pp.Out) BringOut(pp, false); });
                Later(d + 0.7, delegate { pp.Say(pp.P.Name + "！", 1.8); });
                d += 1.5;
            }
            Later(d + 0.8, delegate
            {
                foreach (Pet p in order) if (p.Out && p.Grounded()) { p.ScenePose("wave", 1.8); p.Say("Eh-oh!", 2); }
                if (order.Count > 0) Lead().Say("天線寶寶，Eh-oh! ☀", 2.6);
            });
        }

        // ---------- 天線寶寶說再見：一隻一隻揮手回櫃子；最後從櫃子裡再說一次再見 ----------
        void SceneByeBye(bool night)
        {
            List<Pet> outs = ShowOrder(OutPets());
            if (outs.Count == 0) { Pet l0 = Lead(); l0.Say("天線寶寶說再見！再見～", 3); return; }
            Pet lead = Lead();
            Begin(outs.ToArray());
            foreach (Pet p in outs) if (p.Grounded()) p.ScenePose("idle", 60);
            double d = 0.2;
            if (night) foreach (Pet p in outs) { Pet pp = p; At(d, delegate { pp.Say(pp.L("nag"), 2.6); }); d += 2.8; }
            At(d, delegate { lead.Say("天線寶寶，說再見的時間到了～", 2.6); });
            d += 2.8;
            foreach (Pet p in outs)
            {
                Pet pp = p;
                At(d, delegate { pp.ScenePose("wave", 2.2); pp.Say(pp.P.Name + "說再見！👋", 2.2); });
                At(d + 1.7, delegate { pp.InScene = false; if (pp.Out) pp.StowToShelf(false); });
                d += 2.6;
            }
            Pet last = outs[outs.Count - 1];
            At(d + 0.4, delegate { last.Say("天線寶寶說再見！再見～", 3); });
            At(d + 3.8, delegate { Pet po = Get("po") ?? last; po.Say("……再見～（偷偷揮手）", 2.2); });
            At(d + 6.2, delegate { });
        }
    }

    // ================= 離屏測試模式（DESKPALS_OFFSCREEN=1）=================
    // 不顯示任何視窗；pipe 下 snap 把「本來會畫在螢幕上的東西」疊到一張假桌面上存成 PNG。
    partial class World
    {
        // snap <path> [x y w h]
        void Snap(string path, Rectangle region)
        {
            Rectangle vs = SystemInformation.VirtualScreen;
            if (region.Width <= 0 || region.Height <= 0) region = vs;
            using (Bitmap b = new Bitmap(region.Width, region.Height, PixelFormat.Format32bppArgb))
            using (Graphics g = Graphics.FromImage(b))
            {
                g.TranslateTransform(-region.X, -region.Y);
                g.Clear(Color.FromArgb(0x3A, 0x55, 0x7A));
                using (SolidBrush desk = new SolidBrush(Color.FromArgb(0x5B, 0x7D, 0xA8)))
                    foreach (Screen s in screens) g.FillRectangle(desk, s.WorkingArea);
                using (SolidBrush bar = new SolidBrush(Color.FromArgb(0x20, 0x22, 0x2A)))
                    foreach (Screen s in screens) g.FillRectangle(bar, Rectangle.FromLTRB(s.Bounds.Left, s.WorkingArea.Bottom, s.Bounds.Right, s.Bounds.Bottom));
                // 真的視窗位置（只畫框，不擷取內容）：後面的先畫
                using (SolidBrush body = new SolidBrush(Color.FromArgb(0xF4, 0xF5, 0xF8)))
                using (SolidBrush title = new SolidBrush(Color.FromArgb(0xD6, 0xDB, 0xE4)))
                using (Pen edge = new Pen(Color.FromArgb(0x9A, 0xA3, 0xB5)))
                    for (int i = Wins.Count - 1; i >= 0; i--)
                    {
                        WinInfo wi = Wins[i];
                        if (!Cands.ContainsKey(wi.H)) continue;
                        Rectangle r = Rectangle.FromLTRB(wi.L, wi.T, wi.R, wi.B);
                        g.FillRectangle(body, r);
                        g.FillRectangle(title, r.X, r.Y, r.Width, Math.Min(r.Height, 30));
                        g.DrawRectangle(edge, r.X, r.Y, r.Width - 1, r.Height - 1);
                    }
                // 由下到上：櫃子 → 蜘蛛網 → 公仔 → 球 → 煙火 → 泡泡 → 閃光
                if (shelf != null && shelf.VVisible && shelf.VBmp != null) g.DrawImageUnscaled(shelf.VBmp, shelf.VPos);
                foreach (CobwebForm f in webs) if (f.VVisible) f.PaintTo(g);
                foreach (Pet p in Pets) if (p.Form != null && p.Form.VVisible && p.Form.VBmp != null) g.DrawImageUnscaled(p.Form.VBmp, p.Form.VPos);
                foreach (Prop pr in props) if (pr.F.VVisible) pr.F.PaintTo(g);
                if (ballF != null && ballF.VVisible) ballF.PaintTo(g);
                if (fx != null && fx.VVisible) fx.PaintTo(g);
                foreach (Pet p in Pets) if (p.Bub != null && p.Bub.VVisible) p.Bub.PaintTo(g);
                if (flowerBub != null && flowerBub.VVisible) flowerBub.PaintTo(g);
                if (flash != null && flash.VVisible) flash.PaintTo(g);
                if (setupForm != null && !setupForm.IsDisposed && setupForm.VVisible) setupForm.PaintTo(g);
                if (pmenu != null && pmenu.VVisible) pmenu.PaintTo(g);
                // 游標位置（只畫一個小十字，方便看）
                Point c = Cursor.Position;
                using (Pen cp = new Pen(Color.FromArgb(200, 255, 255, 0), 2)) { g.DrawLine(cp, c.X - 6, c.Y, c.X + 6, c.Y); g.DrawLine(cp, c.X, c.Y - 6, c.X, c.Y + 6); }
                g.ResetTransform();
                try { Directory.CreateDirectory(Path.GetDirectoryName(path)); } catch { }
                b.Save(path, ImageFormat.Png);
            }
        }

        static Rectangle ParseRect(string[] p, int i)
        {
            int x, y, wd, ht;
            if (p.Length >= i + 4 && int.TryParse(p[i], out x) && int.TryParse(p[i + 1], out y) && int.TryParse(p[i + 2], out wd) && int.TryParse(p[i + 3], out ht))
                return new Rectangle(x, y, wd, ht);
            return Rectangle.Empty;
        }

        // 模擬點一下（測試用）：點公仔＝摸他／點通知；點櫃子格子＝放出來／收回去
        void SimClick(int x, int y)
        {
            for (int i = Pets.Count - 1; i >= 0; i--)
            {
                Pet p = Pets[i];
                if (!p.Out) continue;
                if (x >= p.x - 9 * S && x <= p.x + p.SW + 9 * S && y >= p.y - p.P.TopRows * S - 6 && y <= p.y + p.SH + 6) { p.Clicked(); return; }
            }
            if (shelf != null) shelf.ClickAt(new Point(x, y), MouseButtons.Left);
        }

        // 模擬拖到某處放開
        void SimDrop(Pet p, int x, int y)
        {
            if (p == null || !p.Out) return;
            p.x = x - p.SW / 2.0; p.y = y - p.SH / 2.0;
            if (InShelf(x, y)) p.StowToShelf(true);
            else p.Jump(0, 0);
        }
    }

    // ================= 通知（CI、會議、Jira、工作日誌…）與番茄鐘 =================
    partial class World
    {
        class Notice { public string Kind, Url, Text; public int Pri; public DateTime At; public Pet By; public double Expire; public bool Repeated; public bool NextRound; }
        readonly List<Notice> heldShare = new List<Notice>();   // 分享螢幕／全螢幕時先存著
        readonly List<Notice> heldFocus = new List<Notice>();   // 專注時先存著（低／一般）
        Notice current;

        static int Priority(string kind)
        {
            switch (kind)
            {
                case "ci-fail": case "meeting": case "meeting-now": case "remind": return 2;
                case "ci-ok": case "cmd-fail": case "jira": case "pc-cpu": case "pc-ram": case "pc-disk": case "net-down": case "vpn": return 1;
            }
            return 0;
        }

        // 只接受 http/https，或指向本機存在檔案的 file:///
        static string SafeUrl(string u)
        {
            if (string.IsNullOrEmpty(u) || u == "-") return null;
            Uri uri;
            if (!Uri.TryCreate(u, UriKind.Absolute, out uri)) return null;
            if (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps) return uri.AbsoluteUri;
            if (uri.Scheme == Uri.UriSchemeFile && uri.IsFile && File.Exists(uri.LocalPath)) return uri.LocalPath;
            return null;
        }

        // notify <kind> <url|-> <text...>
        void OnNotify(string kind, string url, string text)
        {
            Notice n = new Notice();
            n.Kind = kind; n.Url = SafeUrl(url); n.Text = text; n.Pri = Priority(kind); n.At = DateTime.Now;
            if (kind.StartsWith("meeting")) Count("meetings");
            if (kind == "ci-ok" || kind == "ci-fail") Count("deploys");
            if (url != "-" && n.Url == null) App.Log("notify: rejected url " + url);
            if (sharing || fsNow) { heldShare.Add(n); return; }
            if (quietOn)
            {
                // 安靜中：會議、CI 失敗還是說，但只冒泡泡；其他先存著
                if (n.Kind.StartsWith("meeting") || n.Kind == "ci-fail") { DeliverGentle(n); return; }
                heldQuiet.Add(n); return;
            }
            if (focusOn && n.Pri < 2) { heldFocus.Add(n); return; }
            Deliver(n, false);
        }

        // 分享／全螢幕結束 → 補送（太舊的丟掉；會議過了就不提）
        void FlushShareHeld()
        {
            if (sharing || fsNow || heldShare.Count == 0) return;
            List<Notice> l = new List<Notice>(heldShare); heldShare.Clear();
            double d = 1.5;
            foreach (Notice n in l)
            {
                double age = (DateTime.Now - n.At).TotalMinutes;
                if (age > 10 || (n.Kind == "meeting-now" && age > 2) || (n.Kind == "meeting" && age > 5)) continue;
                Notice nn = n;
                Later(d, delegate { if (focusOn && nn.Pri < 2) heldFocus.Add(nn); else Deliver(nn, false); });
                d += 4;
            }
        }

        static string Flavor(string id, string kind, bool night)
        {
            string pk = PikFlavor(id, kind) ?? OrigFlavor(id, kind); if (pk != null) return pk;
            string extra = FlavorExtra(id, kind);
            if (extra != null) return extra;
            if (night && kind == "worklog")
                switch (id)
                {
                    case "po": return "日誌好了…太陽寶寶下山了，回家吧：";
                    case "stitch": return "日誌好了…Ohana 在家等你：";
                    case "hangyodon": return "日誌好了…大家都回家了，你也回家吧：";
                    case "tinky": return "日誌好了…太陽寶寶下山了，丁丁說再見：";
                    case "dipsy": return "日誌好了…帽子戴好，回家吧：";
                    case "laalaa": return "日誌好了…啦…該回家囉：";
                    default: return "日誌好了。然後下班：";
                }
            string[] keys = { "ci-run", "ci-ok", "ci-fail", "cmd-ok", "cmd-fail", "meeting", "meeting-now", "jira", "worklog" };
            string[] sp = { "Thwip～CI 跑起來了：", "CI 過了！帥！", "蜘蛛感應！CI 掛了：", "指令跑完了：", "嗯？指令失敗了：", "等等要開會喔：", "會議開始了！快去：", "有新的 Jira：", "今天的工作日誌好了：" };
            string[] po = { "嘟嘟～CI 出發：", "全壘打！", "嗚…CI 摔倒了：", "好棒棒，跑完了：", "咦？沒成功：", "等一下要開會會喔：", "要開會了！快快：", "有新任務喔：", "今天的日誌寫好了～" };
            string[] st = { "ih! CI 在跑：", "CI 過了！嘻嘻嘻", "ih-ih-ih! CI 壞掉了：", "跑完了！", "失敗！史迪仔去咬它：", "等等開會！", "開會！快去！", "新的 Jira！", "日誌好了，Aloha：" };
            string[] hg = { "英雄報告：CI 出發了", "英雄報告：", "交給我這個英雄…CI 失敗了：", "英雄報告：指令跑完", "嗚，指令失敗了：", "等一下有會議喔：", "會議開始了！快去吧：", "有新的 Jira 喔：", "今天的日誌好了，辛苦了：" };
            string[] ti = { "丁丁的魔法袋：CI 出發囉：", "CI 過了！丁丁跳舞～", "哎喲！CI 跌倒了：", "跑完了，好棒棒：", "哎喲，指令失敗了：", "等一下要開會喔：", "開會了！丁丁陪你去：", "魔法袋裡有新的 Jira：", "今天的日誌寫好了～" };
            string[] di = { "CI 跑起來了，酷：", "CI 過了。酷。", "CI 掛了…帽子先扶好：", "跑完了，嘿～", "指令失敗了，別慌：", "等等要開會：", "開會了，走吧：", "新的 Jira：", "日誌好了：" };
            string[] la = { "啦啦～CI 出發：", "CI 過了！啦啦啦～", "哎呀，CI 摔倒了：", "跑完了！啦～", "咦？指令沒成功：", "等一下要開會喔：", "開會了！快快快：", "有新的 Jira 喔：", "今天的日誌好了～啦啦：" };
            int i = Array.IndexOf(keys, kind);
            if (i < 0) return "";
            switch (id) { case "po": return po[i]; case "stitch": return st[i]; case "hangyodon": return hg[i]; case "tinky": return ti[i]; case "dipsy": return di[i]; case "laalaa": return la[i]; }
            return sp[i];
        }

        void Deliver(Notice n, bool repeat)
        {
            if (Hidden && n.Pri >= 2 && userHidden && !sharing && !fsNow) { userHidden = false; ApplyHidden(); }
            if (Hidden) { heldShare.Add(n); return; }
            Pet l = Lead();
            n.By = l;
            string text = Flavor(l.P.Id, n.Kind, Night) + " " + n.Text;
            string hint = n.Url != null ? "點我打開" : null;
            if (n.Pri >= 2)
            {
                l.Notify(text, hint, 2, focusOn, n.Kind.StartsWith("meeting"));
                foreach (Pet p in OutPets()) if (p != l && !focusOn) p.React();
                if (!repeat && !n.Repeated)
                {
                    Notice nn = n;
                    Later(60, delegate { if (current == nn && !nn.Repeated) { nn.Repeated = true; Deliver(nn, true); } });
                }
            }
            else if (n.Pri == 1)
            {
                l.Notify(text, hint, 1, focusOn, false);
                foreach (Pet p in OutPets()) if (p != l && rnd.NextDouble() < 0.4 && !focusOn) p.React();
            }
            else l.Notify(text, hint, 0, focusOn, false);
            if (n.Url != null || n.Pri >= 1) { n.Expire = Now + 120; current = n; l.SetClickableBubble(n.Url != null); }
        }

        // 點了正在通知的那隻（或他的泡泡）：有網址就打開
        public bool NoticeClicked(Pet p)
        {
            if (current == null || current.By != p || Now > current.Expire) return false;
            Notice n = current; current = null;
            p.SetClickableBubble(false);
            if (n.NextRound) { StartFocus(focusMin); return true; }
            if (ReminderClicked(p, n)) return true;
            if (n.Url != null)
            {
                try { Process.Start(new ProcessStartInfo(n.Url) { UseShellExecute = true }); p.Say("好～幫你打開了 👍", 1.4); }
                catch (Exception ex) { App.Log("open url: " + ex.Message); p.Say("打不開耶…", 1.4); }
            }
            else p.Say("收到～", 1.0);
            return true;
        }

        void ExpireNotice()
        {
            if (current != null && Now > current.Expire) { if (current.By != null) current.By.SetClickableBubble(false); current = null; }
        }

        // ---------- 放大敲玻璃的全域冷卻（所有公仔共用一個）----------
        double lastZoom = -1e9, lastAmbientZoom = -1e9;
        public bool ZoomAllowed(string kind)
        {
            double idle = W.IdleSeconds();
            bool ok;
            if (quietOn && kind != "user") return false;
            if (Lunch && kind != "user" && kind != "meeting") return false;   // 午餐時間不放大（會議除外）
            switch (kind)
            {
                case "user": ok = true; break;                                        // 選單「敲敲螢幕」：你自己叫的
                case "meeting": ok = Now - lastZoom >= 900; break;
                case "high": ok = Now - lastZoom >= 900 && idle >= 20; break;
                case "ambient": ok = Now - lastAmbientZoom >= 7200 && Now - lastZoom >= 900 && idle >= 120; break;
                default: ok = false; break;
            }
            if (ok) { lastZoom = Now; if (kind == "ambient") lastAmbientZoom = Now; }
            return ok;
        }

        // ---------- 安靜一下（勿擾）----------
        public bool quietOn;
        double quietEnd;
        int lastQuietLeft = -1;
        readonly List<Notice> heldQuiet = new List<Notice>();

        public int QuietLeft() { return quietOn ? Math.Max(0, (int)Math.Ceiling((quietEnd - Now - 0.5) / 60.0)) : -1; }

        // 到今天下班（18:00）；已經過了就兩小時
        static int MinutesToOffWork()
        {
            DateTime n = DateTime.Now, off = n.Date.AddHours(18);
            return n < off ? Math.Max(1, (int)Math.Ceiling((off - n).TotalMinutes)) : 120;
        }

        void StartQuiet(int min)
        {
            if (min <= 0) { StopQuiet(); return; }
            bool was = quietOn;
            // 只延長、不縮短（會議自動安靜不會把你手動設的兩小時變短）
            double end = Now + Math.Min(min, 24 * 60) * 60;
            quietEnd = was ? Math.Max(quietEnd, end) : end;
            quietOn = true;
            AbortScene();
            foreach (Pet p in OutPets()) p.QuietDown();
            if (!was)
            {
                Pet l = Lead();
                string line;
                switch (l.P.Id)
                {
                    case "po": line = "噓～小波安靜陪你 🤫"; break;
                    case "stitch": line = "噓…史迪仔乖乖的"; break;
                    case "hangyodon": line = "好，我安靜待著…有事再叫我"; break;
                    case "tinky": line = "噓～丁丁抱著袋袋安靜陪你 🤫"; break;
                    case "dipsy": line = "噓。帽子拉低，安靜。"; break;
                    case "laalaa": line = "噓～拉拉小小聲 🤫"; break;
                    default: line = "好，我安靜待著。"; break;
                }
                l.Say(line, 2.2);
            }
            lastQuietLeft = QuietLeft();
            BroadcastQuiet();
        }

        void StopQuiet()
        {
            if (!quietOn) return;
            quietOn = false;
            BroadcastQuiet();
            Pet l = Lead();
            string line;
            switch (l.P.Id)
            {
                case "po": line = "安靜時間結束～Eh-oh!"; break;
                case "stitch": line = "安靜結束！ih-ih!（小聲）"; break;
                case "hangyodon": line = "安靜時間結束了…我好想講笑話"; break;
                case "tinky": line = "安靜時間結束～Eh-oh!"; break;
                case "dipsy": line = "安靜結束。嘿～"; break;
                case "laalaa": line = "安靜時間結束～啦啦啦！"; break;
                default: line = "安靜時間結束～"; break;
            }
            if (heldQuiet.Count == 0) { l.Say(line, 2.4); return; }
            // 一次說完：最新一則有網址就可以點
            List<Notice> held = new List<Notice>(heldQuiet); heldQuiet.Clear();
            List<string> parts = new List<string>();
            Notice withUrl = null;
            foreach (Notice n in held) { string t = n.Text.Length > 18 ? n.Text.Substring(0, 18) + "…" : n.Text; parts.Add(t); if (n.Url != null) withUrl = n; }
            string text = "安靜時間結束～剛剛有 " + held.Count + " 件事：" + string.Join("、", parts.ToArray());
            if (text.Length > 70) text = text.Substring(0, 70) + "…";
            l.Say(text, 8, false, withUrl != null ? "點我打開最新那則" : null);
            if (withUrl != null) { withUrl.By = l; withUrl.Expire = Now + 120; current = withUrl; l.SetClickableBubble(true); }
        }

        // 安靜時用的：只冒泡泡、不敲玻璃、不放大
        void DeliverGentle(Notice n)
        {
            Pet l = Lead();
            n.By = l;
            l.Say(Flavor(l.P.Id, n.Kind, Night) + " " + n.Text, 7, n.Pri >= 2, n.Url != null ? "點我打開" : null);
            if (n.Url != null) { n.Expire = Now + 120; current = n; l.SetClickableBubble(true); }
        }

        // 安靜時把「做完了」「上版了」「休息一下」這類也先存起來
        public bool HoldIfQuiet(string kind, string text)
        {
            if (!quietOn) return false;
            Notice n = new Notice(); n.Kind = kind; n.Text = text; n.At = DateTime.Now; n.Pri = 0;
            heldQuiet.Add(n);
            return true;
        }

        void QuietTick()
        {
            if (!quietOn) return;
            if (Now >= quietEnd) { StopQuiet(); return; }
            int left = QuietLeft();
            if (left != lastQuietLeft) { lastQuietLeft = left; BroadcastQuiet(); }
        }

        void BroadcastQuiet()
        {
            string msg = quietOn ? "quiet on " + QuietLeft() + "\n" : "quiet off\n";
            lock (clients) foreach (Client c in clients) Send(c, msg);
        }

        // ---------- 番茄鐘 ----------
        public bool focusOn;
        bool breakOn;
        double focusEnd, breakEnd;
        int focusMin = 25, lastFocusLeft = -1;

        public int FocusLeft() { return focusOn ? Math.Max(0, (int)Math.Ceiling((focusEnd - Now - 0.5) / 60.0)) : -1; }

        void StartFocus(int min)
        {
            focusMin = Math.Max(1, Math.Min(120, min));
            focusOn = true; breakOn = false;
            focusEnd = Now + focusMin * 60;
            AbortScene();
            foreach (Pet p in OutPets()) p.QuietDown();
            Pet l = Lead();
            l.Say(focusMin + " 分鐘專注開始 🍅 我們安靜陪你", 2.4);
            lastFocusLeft = FocusLeft();
            BroadcastFocus();
        }

        void StopFocus(bool done)
        {
            if (!focusOn) return;
            focusOn = false;
            BroadcastFocus();
            Pet l = Lead();
            if (!done) { l.Say("好，先不專注了～", 1.6); FlushFocusHeld(1); return; }
            int n = BumpTomato();
            string end;
            switch (l.P.Id)
            {
                case "po": end = "專注結束！休息 5 分鐘 ☕ 好棒棒！"; break;
                case "stitch": end = "專注結束！休息 5 分鐘 ☕ 嘻嘻嘻，史迪仔有乖乖"; break;
                case "hangyodon": end = "專注結束！休息 5 分鐘 ☕ 你才是真正的英雄"; break;
                case "tinky": end = "專注結束！休息 5 分鐘 ☕ 丁丁跳舞給你看"; break;
                case "dipsy": end = "專注結束。休息 5 分鐘 ☕ 你很酷"; break;
                case "laalaa": end = "專注結束！休息 5 分鐘 ☕ 啦啦啦～好棒棒"; break;
                default: end = "專注結束！休息 5 分鐘 ☕ 你超強的"; break;
            }
            l.Knock(end + "　今天第 " + n + " 顆 🍅", "high");
            foreach (Pet p in OutPets()) if (p != l) p.React();
            breakOn = true; breakEnd = Now + 300;
            FlushFocusHeld(5);
        }

        void FlushFocusHeld(double delay)
        {
            if (heldFocus.Count == 0) return;
            List<Notice> l = new List<Notice>(heldFocus); heldFocus.Clear();
            Pet lead = Lead();
            Later(delay, delegate { lead.Say("專注的時候來了 " + l.Count + " 則通知，一則一則跟你說～", 2.4); });
            double d = delay + 2.8;
            foreach (Notice n in l) { Notice nn = n; Later(d, delegate { Deliver(nn, false); }); d += 4.5; }
        }

        int BumpTomato()
        {
            string f = "tomato-" + DateTime.Now.ToString("yyyyMMdd") + ".txt";
            int n; int.TryParse(ReadText(f), out n);
            n++;
            WriteText(f, n.ToString());
            return n;
        }

        void FocusTick()
        {
            if (focusOn)
            {
                if (Now >= focusEnd) { StopFocus(true); return; }
                int left = FocusLeft();
                if (left != lastFocusLeft) { lastFocusLeft = left; BroadcastFocus(); }
            }
            else if (breakOn && Now >= breakEnd)
            {
                breakOn = false;
                Pet l = Lead();
                Notice n = new Notice(); n.Kind = "focus"; n.Text = ""; n.Pri = 1; n.NextRound = true; n.By = l; n.Expire = Now + 120;
                current = n;
                l.SetClickableBubble(true);
                l.Say("休息結束～要再來一輪嗎？🍅", 6, false, "點我開始");
            }
        }

        void BroadcastFocus()
        {
            string msg = focusOn ? "focus on " + FocusLeft() + "\n" : "focus off\n";
            lock (clients) foreach (Client c in clients) Send(c, msg);
        }
    }

    partial class Pet
    {
        string bubbleHint;
        public void Say(string s, double sec, bool alert, string hint) { Say(s, sec, alert); bubbleHint = hint; }

        // 通知：pri 2 高（敲玻璃＋感應＋長泡泡）、1 一般（走向滑鼠＋泡泡）、0 低（短泡泡）；專注時溫柔一點
        public void Notify(string text, string hint, int pri, bool gentle, bool meeting)
        {
            WakeIfSleep();
            if (pri >= 2)
            {
                sense = gentle ? 1.2 : 2.8;
                if (!gentle) Knock(text, meeting ? "meeting" : "high");
                else if (Out && Grounded()) Jump(0, -180 * k);
                Say(text, gentle ? 6 : 9, true, hint);
            }
            else if (pri == 1)
            {
                if (Out && Grounded() && !gentle) { Rectangle wa = w.WA(Cx, y + SH / 2.0); seekX = Clamp(Cursor.Position.X, wa.Left + SW, wa.Right - SW); gotoSpeed = 1.6; SetState("goto", 3); }
                Say(text, 6, false, hint);
            }
            else Say(text, 3, false, hint);
            Bt = Math.Max(Bt, pri >= 2 ? 9 : (pri == 1 ? 6 : 3));
            bubblePri = Math.Max(1, pri);
        }

        public void SetClickableBubble(bool on) { EnsureForms(); Bub.SetClickable(on, this); if (!on) bubbleHint = null; }

        // 專注時：安靜、不亂跑
        public void QuietDown()
        {
            if (!Out) return;
            if (Grounded() && state != "sleep") SetState("idle", R(4, 8));
            fetching = false;
        }
        bool Quiet { get { return w.focusOn || w.quietOn; } }
    }

    // ================= 提醒我、電腦健康、下載完成、今天的小結 =================
    partial class World
    {
        // ---------- 共用：每個角色的開場白 ----------
        static string FlavorExtra(string id, string kind)
        {
            string pk = PikFlavor(id, kind) ?? OrigFlavor(id, kind); if (pk != null) return pk;
            string[] keys = { "remind", "pc-cpu", "pc-ram", "pc-disk", "net-down", "net-up", "vpn", "download" };
            string[] sp = { "⏰ 提醒你：", "蜘蛛感應！電腦好燙：", "蜘蛛感應！記憶體快滿了：", "硬碟快滿了：", "網路斷了！", "網路回來了 👍", "連不到公司網路（VPN 斷了？）", "下載好了：" };
            string[] po = { "⏰ 小波提醒你：", "電腦好忙好熱喔：", "記憶體要滿滿了：", "硬碟快塞滿了：", "網路斷掉了！嗚…", "網路回來了！Eh-oh!", "連不到公司網路耶（VPN 斷了？）", "下載好了！" };
            string[] st = { "⏰ ih! 提醒你：", "ih-ih! 電腦在冒煙：", "記憶體快爆了：", "硬碟要滿了：", "網路斷了！史迪仔去咬線！", "網路回來了！嘻嘻嘻", "公司網路連不到（VPN 斷了？）", "下載好了！ih!" };
            string[] hg = { "⏰ 英雄提醒你：", "電腦好像很累了：", "記憶體快滿了喔：", "硬碟快滿了：", "網路斷了…交給我這個英雄！", "網路回來了～太好了", "連不到公司網路（VPN 斷了嗎？）", "下載好了喔：" };
            string[] ti = { "⏰ 丁丁提醒你：", "電腦好燙…丁丁幫你扇扇：", "記憶體要滿了，跟魔法袋一樣：", "硬碟快塞滿了：", "網路斷了！哎喲…", "網路回來了！Eh-oh!", "連不到公司網路耶（VPN 斷了？）", "下載好了！放進魔法袋～" };
            string[] di = { "⏰ 迪西提醒你：", "電腦很燙，酷不起來：", "記憶體快滿了：", "硬碟快滿了：", "網路斷了，冷靜：", "網路回來了，酷。", "連不到公司網路（VPN 斷了？）", "下載好了，嘿：" };
            string[] la = { "⏰ 拉拉提醒你：", "電腦好熱喔：", "記憶體快滿滿了：", "硬碟快塞滿了：", "網路斷掉了！嗚…", "網路回來了！啦啦啦～", "連不到公司網路耶（VPN 斷了？）", "下載好了！啦～" };
            int i = Array.IndexOf(keys, kind);
            if (i < 0) return null;
            switch (id) { case "po": return po[i]; case "stitch": return st[i]; case "hangyodon": return hg[i]; case "tinky": return ti[i]; case "dipsy": return di[i]; case "laalaa": return la[i]; }
            return sp[i];
        }

        // ================= 1) 提醒我 =================
        class Reminder { public long At; public string Text; }
        readonly List<Reminder> reminders = new List<Reminder>();
        static long UnixMs(DateTime t) { return (long)(t.ToUniversalTime() - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalMilliseconds; }
        static DateTime FromUnixMs(long ms) { return new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc).AddMilliseconds(ms).ToLocalTime(); }

        void LoadReminders()
        {
            reminders.Clear();
            foreach (string line in ReadText("reminders.txt").Split('\n'))
            {
                int tab = line.IndexOf('\t');
                long ms;
                if (tab > 0 && long.TryParse(line.Substring(0, tab), out ms)) { Reminder r = new Reminder(); r.At = ms; r.Text = line.Substring(tab + 1).Trim(); reminders.Add(r); }
            }
        }

        void SaveReminders()
        {
            StringBuilder sb = new StringBuilder();
            foreach (Reminder r in reminders) sb.Append(r.At + "\t" + r.Text.Replace("\t", " ").Replace("\n", " ") + "\n");
            WriteText("reminders.txt", sb.ToString());
        }

        public void AddReminder(long at, string text)
        {
            if (string.IsNullOrEmpty(text)) text = "（提醒）";
            Reminder r = new Reminder(); r.At = at; r.Text = text;
            reminders.Add(r);
            reminders.Sort(delegate(Reminder a, Reminder b) { return a.At.CompareTo(b.At); });
            SaveReminders();
            Pet l = Lead();
            l.Say("好～" + FromUnixMs(at).ToString("HH:mm") + " 提醒你：" + text, 2.4);
        }

        Reminder dueReminder;
        void ReminderTick()
        {
            if (reminders.Count == 0) return;
            long now = UnixMs(DateTime.Now);
            if (reminders[0].At > now) return;
            Reminder r = reminders[0]; reminders.RemoveAt(0); SaveReminders();
            dueReminder = r;
            Count("reminders");
            OnNotify("remind", "-", r.Text);
        }

        // 提醒的泡泡被點了：好了／10 分鐘後再提醒
        bool ReminderClicked(Pet p, Notice n)
        {
            if (n.Kind != "remind") return false;
            string text = n.Text;
            if (App.Offscreen) { p.Say("好了～", 1.2); App.Log("reminder done (offscreen): " + text); return true; }
            ContextMenuStrip m = new ContextMenuStrip();
            m.Items.Add("好了 👍", null, delegate { p.Say("好～辦好了！", 1.4); });
            m.Items.Add("10 分鐘後再提醒", null, delegate { AddReminder(UnixMs(DateTime.Now.AddMinutes(10)), text); });
            ShowMenu(m, "提醒", false);
            return true;
        }

        void AddReminderMenus(ToolStripItemCollection items)
        {
            items.Add("提醒我…", null, delegate { ShowReminderForm(); });
            if (reminders.Count > 0)
            {
                ToolStripMenuItem my = new ToolStripMenuItem("我的提醒（" + reminders.Count + "）");
                foreach (Reminder r in reminders)
                {
                    Reminder rr = r;
                    string label = FromUnixMs(r.At).ToString("MM/dd HH:mm") + "　" + (r.Text.Length > 20 ? r.Text.Substring(0, 20) + "…" : r.Text) + "　（點一下取消）";
                    my.DropDownItems.Add(label, null, delegate { reminders.Remove(rr); SaveReminders(); Lead().Say("取消了：" + rr.Text, 1.8); });
                }
                items.Add(my);
            }
        }

        // 解析「15:30」或「45」（分鐘）
        public static long ParseWhen(string s)
        {
            s = (s ?? "").Trim().Replace("：", ":");
            int min;
            if (int.TryParse(s, out min) && min > 0) return UnixMs(DateTime.Now.AddMinutes(min));
            DateTime t;
            if (s.Contains(":") && DateTime.TryParse(DateTime.Now.ToString("yyyy-MM-dd ") + s, out t))
            {
                if (t < DateTime.Now) t = t.AddDays(1);
                return UnixMs(t);
            }
            return 0;
        }

        ReminderForm remForm;
        void ShowReminderForm()
        {
            if (App.Offscreen) return;
            if (remForm == null || remForm.IsDisposed) remForm = new ReminderForm(this, Lead().P.Accent);
            remForm.StartPosition = FormStartPosition.Manual;
            Point c = Cursor.Position;
            Rectangle wa = WA(c.X, c.Y);
            remForm.Location = new Point(Math.Max(wa.Left, Math.Min(wa.Right - remForm.Width, c.X - remForm.Width / 2)), Math.Max(wa.Top, Math.Min(wa.Bottom - remForm.Height, c.Y - remForm.Height - 10)));
            remForm.Show();
            ActivateForm(remForm);
            remForm.FocusFirst();
            ReminderForm rf = remForm;
            Later(0.2, delegate { if (rf.Visible) { ActivateForm(rf); rf.FocusFirst(); } });   // 再補一次，確定拿到鍵盤
        }

        // ================= 2) 電腦健康（背景執行緒，每 5 秒）=================
        [StructLayout(LayoutKind.Sequential)]
        class MEMSTAT { public uint dwLength = 64, dwMemoryLoad; public ulong ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile, ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual; }
        [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx([In, Out] MEMSTAT m);
        volatile string companyHost = "";
        readonly Dictionary<string, DateTime> healthCd = new Dictionary<string, DateTime>();

        void HealthLoop()
        {
            Thread.Sleep(15000);
            PerformanceCounter cpu = null;
            try { cpu = new PerformanceCounter("Processor", "% Processor Time", "_Total"); cpu.NextValue(); } catch (Exception ex) { App.Log("cpu counter: " + ex.Message); }
            DateTime cpuHighSince = DateTime.MaxValue, ramHighSince = DateTime.MaxValue, netDownSince = DateTime.MaxValue, vpnDownSince = DateTime.MaxValue, nextDisk = DateTime.Now, nextNet = DateTime.Now;
            bool netAlerted = false;
            while (!closing)
            {
                try
                {
                    DateTime now = DateTime.Now;
                    if (cpu != null)
                    {
                        float v = cpu.NextValue();
                        if (v > 90) { if (cpuHighSince == DateTime.MaxValue) cpuHighSince = now; } else cpuHighSince = DateTime.MaxValue;
                        if (cpuHighSince != DateTime.MaxValue && (now - cpuHighSince).TotalSeconds >= 180 && HealthReady("pc-cpu"))
                        {
                            string top = TopProcess();
                            string t = "CPU 一直在 90% 以上" + (top != null ? "（" + top + " 最忙）" : "");
                            Post(delegate { OnNotify("pc-cpu", "-", t); });
                        }
                    }
                    MEMSTAT m = new MEMSTAT();
                    if (GlobalMemoryStatusEx(m))
                    {
                        if (m.dwMemoryLoad > 90) { if (ramHighSince == DateTime.MaxValue) ramHighSince = now; } else ramHighSince = DateTime.MaxValue;
                        if (ramHighSince != DateTime.MaxValue && (now - ramHighSince).TotalSeconds >= 120 && HealthReady("pc-ram"))
                        { uint load = m.dwMemoryLoad; Post(delegate { OnNotify("pc-ram", "-", "記憶體用了 " + load + "%，關幾個分頁或程式吧"); }); }
                    }
                    if (now >= nextDisk)
                    {
                        nextDisk = now.AddMinutes(10);
                        DriveInfo d = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory));
                        double freeGb = d.AvailableFreeSpace / 1073741824.0, pct = d.AvailableFreeSpace * 100.0 / Math.Max(1, d.TotalSize);
                        if ((freeGb < 10 || pct < 5) && HealthReady("pc-disk"))
                        { string t = d.Name.TrimEnd('\\') + " 只剩 " + freeGb.ToString("0.0") + " GB"; Post(delegate { OnNotify("pc-disk", "-", t); }); }
                    }
                    if (now >= nextNet)
                    {
                        nextNet = now.AddSeconds(10);
                        bool up = TcpOk("1.1.1.1", 443) || TcpOk("8.8.8.8", 443);
                        if (!up)
                        {
                            if (netDownSince == DateTime.MaxValue) netDownSince = now;
                            if (!netAlerted && (now - netDownSince).TotalSeconds > 30 && HealthReady("net-down")) { netAlerted = true; Post(delegate { OnNotify("net-down", "-", "兩個地方都連不上"); }); }
                        }
                        else
                        {
                            if (netAlerted) { netAlerted = false; Post(delegate { OnNotify("net-up", "-", "可以上網了"); }); }
                            netDownSince = DateTime.MaxValue;
                            string host = companyHost;
                            if (host != "")
                            {
                                bool ok = TcpOk(host, 443) || TcpOk(host, 80);
                                if (!ok) { if (vpnDownSince == DateTime.MaxValue) vpnDownSince = now; } else vpnDownSince = DateTime.MaxValue;
                                if (vpnDownSince != DateTime.MaxValue && (now - vpnDownSince).TotalSeconds > 30 && HealthReady("vpn"))
                                { string h2 = host; Post(delegate { OnNotify("vpn", "-", h2 + " 連不到"); }); }
                            }
                        }
                    }
                }
                catch (Exception ex) { App.Log("health: " + ex.Message); }
                Thread.Sleep(5000);
            }
        }

        bool HealthReady(string kind)
        {
            DateTime until;
            lock (healthCd)
            {
                if (healthCd.TryGetValue(kind, out until) && DateTime.Now < until) return false;
                healthCd[kind] = DateTime.Now.AddMinutes(30);
            }
            return true;
        }

        static bool TcpOk(string host, int port)
        {
            try
            {
                using (System.Net.Sockets.TcpClient c = new System.Net.Sockets.TcpClient())
                {
                    IAsyncResult ar = c.BeginConnect(host, port, null, null);
                    bool done = ar.AsyncWaitHandle.WaitOne(2500);
                    if (!done) return false;
                    c.EndConnect(ar);
                    return c.Connected;
                }
            }
            catch { return false; }
        }

        // 最忙的程式（只在要提醒時才算一次）
        static string TopProcess()
        {
            try
            {
                Dictionary<int, TimeSpan> a = new Dictionary<int, TimeSpan>();
                foreach (Process p in Process.GetProcesses()) { try { a[p.Id] = p.TotalProcessorTime; } catch { } }
                Thread.Sleep(800);
                string best = null; double bd = 0;
                foreach (Process p in Process.GetProcesses())
                {
                    try
                    {
                        TimeSpan t0;
                        if (!a.TryGetValue(p.Id, out t0)) continue;
                        double d = (p.TotalProcessorTime - t0).TotalMilliseconds;
                        if (d > bd && p.ProcessName != "Idle") { bd = d; best = p.ProcessName; }
                    }
                    catch { }
                }
                return best;
            }
            catch { return null; }
        }

        // ================= 3) 下載完成 =================
        FileSystemWatcher dlWatch;
        readonly Dictionary<string, long[]> dlPending = new Dictionary<string, long[]>();   // 路徑 → {大小, 穩定起點 ticks}
        double dlCheck;

        void StartDownloadWatch()
        {
            try
            {
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
                if (!Directory.Exists(dir)) return;
                dlWatch = new FileSystemWatcher(dir);
                dlWatch.IncludeSubdirectories = false;
                dlWatch.NotifyFilter = NotifyFilters.FileName | NotifyFilters.Size | NotifyFilters.LastWrite;
                FileSystemEventHandler h = delegate(object s, FileSystemEventArgs e) { string p = e.FullPath; Post(delegate { DlSeen(p); }); };
                dlWatch.Created += h; dlWatch.Changed += h;
                dlWatch.Renamed += delegate(object s, RenamedEventArgs e) { string p = e.FullPath; Post(delegate { DlSeen(p); }); };
                dlWatch.EnableRaisingEvents = true;
            }
            catch (Exception ex) { App.Log("download watch: " + ex.Message); }
        }

        static bool DlIgnore(string p)
        {
            string ext = Path.GetExtension(p).ToLowerInvariant();
            string name = Path.GetFileName(p);
            return ext == ".crdownload" || ext == ".part" || ext == ".tmp" || ext == ".download" || ext == ".partial" || name.StartsWith("~") || name.StartsWith(".");
        }

        void DlSeen(string p)
        {
            if (DlIgnore(p)) return;
            dlPending[p] = new long[] { -1, DateTime.Now.Ticks };
        }

        void DownloadTick(double dt)
        {
            dlCheck -= dt;
            if (dlCheck > 0 || dlPending.Count == 0) return;
            dlCheck = 1;
            List<string> done = new List<string>();
            foreach (KeyValuePair<string, long[]> kv in dlPending)
            {
                try
                {
                    FileInfo fi = new FileInfo(kv.Key);
                    if (!fi.Exists) { done.Add(kv.Key); continue; }
                    if (fi.Length != kv.Value[0]) { kv.Value[0] = fi.Length; kv.Value[1] = DateTime.Now.Ticks; continue; }
                    if (fi.Length <= 0 || (DateTime.Now - new DateTime(kv.Value[1])).TotalSeconds < 3) continue;
                    using (FileStream fs = new FileStream(kv.Key, FileMode.Open, FileAccess.Read, FileShare.Read)) { }
                    done.Add(kv.Key);
                    string uri = new Uri(kv.Key).AbsoluteUri, name = fi.Name;
                    OnNotify("download", uri, name);
                }
                catch (IOException) { }
                catch (Exception) { done.Add(kv.Key); }
            }
            foreach (string d in done) dlPending.Remove(d);
        }

        // ================= 4) 今天的我們 =================
        readonly Dictionary<string, int> day = new Dictionary<string, int>();
        string dayKey = "";
        bool wrapShown;

        void LoadDay()
        {
            string k = DateTime.Now.ToString("yyyyMMdd");
            if (k == dayKey) return;
            dayKey = k; day.Clear(); wrapShown = false;
            foreach (string line in ReadText("day-" + k + ".txt").Split('\n'))
            {
                string[] a = line.Trim().Split('=');
                int v;
                if (a.Length == 2 && int.TryParse(a[1], out v)) { if (a[0] == "wrap") wrapShown = v > 0; else day[a[0]] = v; }
            }
        }

        public void Count(string key)
        {
            LoadDay();
            int v; day.TryGetValue(key, out v); day[key] = v + 1;
            SaveDay();
        }

        void SaveDay()
        {
            StringBuilder sb = new StringBuilder();
            foreach (KeyValuePair<string, int> kv in day) sb.Append(kv.Key + "=" + kv.Value + "\n");
            if (wrapShown) sb.Append("wrap=1\n");
            WriteText("day-" + dayKey + ".txt", sb.ToString());
        }

        int Day(string k) { LoadDay(); int v; day.TryGetValue(k, out v); return v; }

        // 下班那一刻（或右鍵「今天的小結」）：一張小卡
        void DailyWrap(bool fromMenu)
        {
            LoadDay();
            if (!fromMenu && wrapShown) return;
            wrapShown = true; SaveDay();
            int tom = 0; int.TryParse(ReadText("tomato-" + DateTime.Now.ToString("yyyyMMdd") + ".txt"), out tom);
            List<string> parts = new List<string>();
            if (Day("meetings") > 0) parts.Add("開了 " + Day("meetings") + " 場會");
            if (tom > 0) parts.Add("吃了 " + tom + " 顆番茄🍅");
            if (Day("deploys") > 0) parts.Add("上版／CI " + Day("deploys") + " 次");
            if (Day("tasks") > 0) parts.Add("Claude／Codex 幫你做完 " + Day("tasks") + " 件事");
            if (Day("saves") > 0) parts.Add("存檔 " + Day("saves") + " 次");
            if (Day("reminders") > 0) parts.Add("完成 " + Day("reminders") + " 個提醒");
            if (Day("pats") > 0) parts.Add("摸了我們 " + Day("pats") + " 下");
            List<Pet> outs = OutPets();
            Pet l = Lead();
            if (parts.Count == 0) { l.Say("今天很安靜呢～今天辛苦了 ♥", 4); return; }
            string intro;
            switch (l.P.Id)
            {
                case "po": intro = "Eh-oh! 今天的我們："; break;
                case "stitch": intro = "Aloha～今天的 Ohana 紀錄："; break;
                case "hangyodon": intro = "英雄報告：今天的我們"; break;
                case "tinky": intro = "Eh-oh! 丁丁的魔法袋裝了今天的我們："; break;
                case "dipsy": intro = "嘿，今天的我們："; break;
                case "laalaa": intro = "啦啦～今天的我們："; break;
                default: intro = "今天的我們："; break;
            }
            if (outs.Count >= 2 && !quietOn)
            {
                // 大家輪流講一句
                Begin(outs.ToArray());
                At(0, delegate { l.Say(intro, 2.2); });
                double t = 2.4;
                for (int i = 0; i < parts.Count; i++) { Pet p = outs[(i + 1) % outs.Count]; string s = parts[i]; At(t, delegate { p.Say(s, 2.6); }); t += 2.6; }
                At(t, delegate { foreach (Pet p in outs) p.Say("今天辛苦了 ♥", 3); });
                At(t + 3, delegate { });
                return;
            }
            StringBuilder sb = new StringBuilder(intro);
            sb.Append("\n");
            for (int i = 0; i < parts.Count; i++) sb.Append((i % 2 == 0 ? "" : "、") + parts[i] + (i % 2 == 1 && i + 1 < parts.Count ? "\n" : ""));
            sb.Append("\n今天辛苦了 ♥");
            l.Say(sb.ToString(), 9);
        }
    }

    // 「提醒我…」的小視窗（自己畫的樣子，不用 VB InputBox）
    class ReminderForm : Form
    {
        readonly World w;
        readonly TextBox what = new TextBox(), when = new TextBox();
        readonly Label hint = new Label();
        long pick;
        public ReminderForm(World w, Color accent)
        {
            this.w = w;
            Text = "提醒我…";
            FormBorderStyle = FormBorderStyle.FixedToolWindow;
            ShowInTaskbar = false; TopMost = true; MaximizeBox = false; MinimizeBox = false;
            BackColor = Color.FromArgb(0xFF, 0xFB, 0xF4);
            Font = new Font("Microsoft JhengHei UI", 10f);
            AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(340, 190);
            Label l1 = new Label(); l1.Text = "要提醒什麼？"; l1.Location = new Point(14, 12); l1.AutoSize = true;
            what.Location = new Point(14, 34); what.Width = 312;
            Label l2 = new Label(); l2.Text = "什麼時候？（可以打 15:30 或 45 分鐘）"; l2.Location = new Point(14, 66); l2.AutoSize = true;
            Controls.Add(l1); Controls.Add(what); Controls.Add(l2);
            string[] labels = { "10 分", "30 分", "1 小時", "下班前" };
            int[] mins = { 10, 30, 60, -1 };
            for (int i = 0; i < 4; i++)
            {
                Button b = new Button(); b.Text = labels[i]; b.Location = new Point(14 + i * 79, 90); b.Size = new Size(74, 28);
                b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderColor = accent; b.BackColor = Color.White;
                int m = mins[i];
                b.Click += delegate
                {
                    DateTime t = m > 0 ? DateTime.Now.AddMinutes(m) : DateTime.Now.Date.AddHours(17).AddMinutes(50);
                    if (t < DateTime.Now) t = t.AddDays(1);
                    pick = (long)(t.ToUniversalTime() - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalMilliseconds;
                    when.Text = t.ToString("HH:mm");
                };
                Controls.Add(b);
            }
            when.Location = new Point(14, 126); when.Width = 120;
            when.TextChanged += delegate { pick = 0; };
            Button ok = new Button(); ok.Text = "好，提醒我"; ok.Location = new Point(206, 122); ok.Size = new Size(120, 32);
            ok.FlatStyle = FlatStyle.Flat; ok.BackColor = accent; ok.ForeColor = Color.White; ok.FlatAppearance.BorderSize = 0;
            ok.Click += delegate { Submit(); };
            hint.Location = new Point(14, 162); hint.AutoSize = true; hint.ForeColor = Color.FromArgb(0xB0, 0x40, 0x40);
            Controls.Add(when); Controls.Add(ok); Controls.Add(hint);
            AcceptButton = ok;
            KeyPreview = true;
            KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Escape) Hide(); };
            FormClosing += delegate(object s, FormClosingEventArgs e) { if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); } };
        }

        public void FocusFirst() { what.Select(); what.Focus(); }

        void Submit()
        {
            if (what.Text.Trim() == "") { hint.Text = "要提醒什麼呢？"; what.Focus(); return; }
            long at = pick > 0 ? pick : World.ParseWhen(when.Text);
            if (at <= 0) { hint.Text = "時間看不懂耶，試試 15:30 或 45"; return; }
            w.AddReminder(at, what.Text.Trim());
            what.Text = ""; when.Text = ""; hint.Text = ""; pick = 0;
            Hide();
        }
    }

    // ================= 搶票提醒 =================
    // 你自己排的：不受安靜／專注影響。開賣前 1～2 小時、30 分、10 分（對時）、1 分、開賣當下，一段一段提醒。
    partial class World
    {
        class Ticket { public long At; public int Lead; public string Url, Name; public int Stage; }
        readonly List<Ticket> tickets = new List<Ticket>();

        void LoadTickets()
        {
            tickets.Clear();
            foreach (string line in ReadText("tickets.txt").Split('\n'))
            {
                string[] a = line.TrimEnd('\r').Split('\t');
                long at; int lead, stage;
                if (a.Length >= 5 && long.TryParse(a[0], out at) && int.TryParse(a[1], out lead) && int.TryParse(a[3], out stage))
                {
                    Ticket t = new Ticket(); t.At = at; t.Lead = lead; t.Url = a[2] == "-" ? null : a[2]; t.Stage = stage; t.Name = a[4];
                    tickets.Add(t);
                }
            }
        }

        void SaveTickets()
        {
            StringBuilder sb = new StringBuilder();
            foreach (Ticket t in tickets) sb.Append(t.At + "\t" + t.Lead + "\t" + (t.Url ?? "-") + "\t" + t.Stage + "\t" + t.Name.Replace("\t", " ").Replace("\n", " ") + "\n");
            WriteText("tickets.txt", sb.ToString());
        }

        public void AddTicket(long at, int lead, string url, string name)
        {
            Ticket t = new Ticket();
            t.At = at; t.Lead = lead == 60 ? 60 : 120; t.Name = string.IsNullOrEmpty(name) ? "搶票" : name;
            t.Url = SafeUrl(url);
            if (t.Url != null && !t.Url.StartsWith("http")) t.Url = null;   // 購票頁只收 http/https
            // 已經過了的階段就不補（例如只剩 20 分鐘才設定，就從 10 分鐘那段開始）
            int[] st = StagesOf(t);
            double left = (at - UnixMs(DateTime.Now)) / 60000.0;
            t.Stage = 0;
            for (int s = 0; s < st.Length; s++) if (left <= st[s]) t.Stage = s + 1;
            if (t.Stage - 1 >= 2) t.Stage--;   // 已經進到 10 分鐘內：最近那段馬上講（含對時、倒數）
            tickets.Add(t);
            tickets.Sort(delegate(Ticket a, Ticket b) { return a.At.CompareTo(b.At); });
            SaveTickets();
            Lead().Say("🎫 記住了：" + t.Name + "，" + FromUnixMs(at).ToString("MM/dd HH:mm") + " 開賣，提前 " + (t.Lead / 60) + " 小時叫你", 3);
        }

        static int[] StagesOf(Ticket t) { return new int[] { t.Lead, 30, 10, 1, 0 }; }

        static string TicketLine(string id, int stage, Ticket t)
        {
            string h = (t.Lead / 60) + " 小時", n = t.Name;
            string pk = PikTicket(id, stage, n, h) ?? OrigTicket(id, stage, n, h); if (pk != null) return pk;
            string[] sp = { "🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款", "🎫 " + n + " 再 30 分鐘開賣，網頁先開好", "🎫 " + n + " 剩 10 分鐘！蜘蛛感應全開", "🎫 準備！手指放在按鈕上", "🎫 開搶！！Thwip!" };
            string[] po = { "🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款喔", "🎫 " + n + " 再 30 分鐘！小波陪你等", "🎫 " + n + " 剩 10 分鐘！好緊張～", "🎫 準備！深呼吸～", "🎫 開搶！！衝衝衝！" };
            string[] st = { "🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款！ih!", "🎫 " + n + " 30 分鐘！史迪仔幫你顧著", "🎫 " + n + " 10 分鐘！ih-ih-ih!", "🎫 準備！史迪仔也準備好了", "🎫 開搶！！衝啊！" };
            string[] hg = { "🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款", "🎫 " + n + " 30 分鐘後開賣，英雄陪你等", "🎫 " + n + " 剩 10 分鐘！英雄出動準備", "🎫 準備！這次一定搶到！", "🎫 開搶！！祝你搶到！" };
            string[] ti = { "🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款喔", "🎫 " + n + " 再 30 分鐘！丁丁陪你等", "🎫 " + n + " 剩 10 分鐘！魔法袋準備好了", "🎫 準備！深呼吸～", "🎫 開搶！！衝衝衝！" };
            string[] di = { "🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款", "🎫 " + n + " 30 分鐘後開賣，網頁先開好", "🎫 " + n + " 剩 10 分鐘！帽子戴好", "🎫 準備。冷靜，酷。", "🎫 開搶！！嘿！" };
            string[] la = { "🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款喔", "🎫 " + n + " 再 30 分鐘！拉拉唱歌陪你等", "🎫 " + n + " 剩 10 分鐘！好緊張～", "🎫 準備！啦…啦…", "🎫 開搶！！衝啊～啦！" };
            switch (id) { case "po": return po[stage]; case "stitch": return st[stage]; case "hangyodon": return hg[stage]; case "tinky": return ti[stage]; case "dipsy": return di[stage]; case "laalaa": return la[stage]; }
            return sp[stage];
        }

        void TicketTick()
        {
            if (tickets.Count == 0) return;
            long now = UnixMs(DateTime.Now);
            bool changed = false;
            for (int i = tickets.Count - 1; i >= 0; i--)
            {
                Ticket t = tickets[i];
                int[] st = StagesOf(t);
                double left = (t.At - now) / 60000.0;
                // 找出「已經到了、還沒講過」的最後一段（中間錯過的就跳過）
                int fire = -1;
                for (int s = t.Stage; s < st.Length; s++) if (left <= st[s]) fire = s;
                if (fire >= 0) { t.Stage = fire + 1; changed = true; FireTicket(t, fire); }
                if (t.Stage >= st.Length && left < -10) { tickets.RemoveAt(i); changed = true; }
            }
            if (changed) SaveTickets();
        }

        void FireTicket(Ticket t, int stage)
        {
            App.Log("ticket stage " + stage + " " + t.Name);
            if (sharing) return;                                  // 分享螢幕時不跳（畫面隱私）
            if (userHidden) { userHidden = false; ApplyHidden(); }
            Pet l = Lead();
            string text = TicketLine(l.P.Id, stage, t);
            string hint = t.Url != null ? "點我打開購票頁" : null;
            if (stage == 1) l.Notify(text, hint, 1, false, false);
            else if (stage == 0 || stage == 2) l.Notify(text, hint, 2, false, false);
            else
            {
                // 1 分鐘、開賣：不管冷卻一定放大
                lastZoom = Now;
                l.ForceGlass(text, hint, stage == 4);
                if (stage == 4) { Fireworks(WA(l.Cx, l.y), 4, (int)l.Cx); foreach (Pet p in OutPets()) if (p != l) p.React(); }
            }
            if (stage == 2) CheckClock(t.Url);
            Notice n = new Notice(); n.Kind = "ticket"; n.Url = t.Url; n.Text = t.Name; n.Pri = 2; n.By = l; n.Expire = Now + 600;
            if (t.Url != null) { current = n; l.SetClickableBubble(true); }
        }

        // 開賣前 10 分鐘以內：倒數（給公仔頭上的大徽章用）；開賣後 1 分鐘顯示「開搶中」
        public string TicketCountdown()
        {
            if (tickets.Count == 0) return null;
            long now = UnixMs(DateTime.Now);
            foreach (Ticket t in tickets)
            {
                long ms = t.At - now;
                if (ms > 0 && ms <= 10 * 60000) { long s = (ms + 999) / 1000; return (s / 60).ToString("00") + ":" + (s % 60).ToString("00"); }
                if (ms <= 0 && ms > -60000) return "開搶中！";
            }
            return null;
        }

        // 對時：拿 HTTP 回應的 Date 標頭跟電腦時間比
        void CheckClock(string url)
        {
            string target = "https://www.google.com/";
            Uri u;
            if (url != null && Uri.TryCreate(url, UriKind.Absolute, out u)) target = u.Scheme + "://" + u.Host + "/";
            Thread th = new Thread(delegate()
            {
                double off = ClockOffset(target);
                if (double.IsNaN(off) && target != "https://www.google.com/") off = ClockOffset("https://www.google.com/");
                if (double.IsNaN(off)) { App.Log("clock check failed"); return; }
                App.Log("clock offset " + off.ToString("0.0") + "s via " + target);
                if (Math.Abs(off) <= 2) return;
                int sec = (int)Math.Round(Math.Abs(off));
                string msg = off < 0 ? "電腦時間比標準時間慢 " + sec + " 秒" : "電腦時間比標準時間快 " + sec + " 秒";
                Post(delegate { Lead().Say("⏱ " + msg + "，搶票要看標準時間喔", 6, true); });
            });
            th.IsBackground = true; th.Start();
        }

        // 回傳「電腦時間 − 標準時間」秒數（NaN＝查不到）
        static double ClockOffset(string url)
        {
            try
            {
                System.Net.ServicePointManager.SecurityProtocol |= (System.Net.SecurityProtocolType)3072; // TLS 1.2
                System.Net.HttpWebRequest req = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(url);
                req.Method = "HEAD"; req.Timeout = 5000; req.AllowAutoRedirect = false; req.UserAgent = "DeskPals";
                DateTime t0 = DateTime.UtcNow;
                using (System.Net.HttpWebResponse resp = (System.Net.HttpWebResponse)req.GetResponse())
                {
                    DateTime t1 = DateTime.UtcNow;
                    string d = resp.Headers["Date"];
                    DateTime server;
                    if (d == null || !DateTime.TryParse(d, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.AdjustToUniversal | System.Globalization.DateTimeStyles.AssumeUniversal, out server)) return double.NaN;
                    DateTime mid = t0.AddTicks((t1 - t0).Ticks / 2);
                    // Date 只到秒：標準時間大約在 server 到 server+1 秒之間，取中間
                    return (mid - server.AddMilliseconds(500)).TotalSeconds;
                }
            }
            catch (System.Net.WebException ex)
            {
                // 3xx／4xx 也有 Date 標頭
                System.Net.HttpWebResponse r = ex.Response as System.Net.HttpWebResponse;
                if (r != null)
                {
                    string d = r.Headers["Date"];
                    DateTime server;
                    if (d != null && DateTime.TryParse(d, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.AdjustToUniversal | System.Globalization.DateTimeStyles.AssumeUniversal, out server))
                        return (DateTime.UtcNow - server.AddMilliseconds(500)).TotalSeconds;
                }
                return double.NaN;
            }
            catch { return double.NaN; }
        }

        void AddTicketMenus(ToolStripItemCollection items)
        {
            items.Add("搶票提醒…", null, delegate { ShowTicketForm(); });
            if (tickets.Count > 0)
            {
                ToolStripMenuItem my = new ToolStripMenuItem("我的搶票（" + tickets.Count + "）");
                foreach (Ticket t in tickets)
                {
                    Ticket tt = t;
                    my.DropDownItems.Add(FromUnixMs(t.At).ToString("MM/dd HH:mm") + "　" + (t.Name.Length > 18 ? t.Name.Substring(0, 18) + "…" : t.Name) + "　（點一下取消）", null,
                        delegate { tickets.Remove(tt); SaveTickets(); Lead().Say("取消搶票提醒：" + tt.Name, 1.8); });
                }
                items.Add(my);
            }
        }

        TicketForm ticketForm;
        void ShowTicketForm()
        {
            if (App.Offscreen) return;
            if (ticketForm == null || ticketForm.IsDisposed) ticketForm = new TicketForm(this, Lead().P.Accent);
            Point c = Cursor.Position;
            Rectangle wa = WA(c.X, c.Y);
            ticketForm.StartPosition = FormStartPosition.Manual;
            ticketForm.Location = new Point(Math.Max(wa.Left, Math.Min(wa.Right - ticketForm.Width, c.X - ticketForm.Width / 2)), Math.Max(wa.Top, Math.Min(wa.Bottom - ticketForm.Height, c.Y - ticketForm.Height - 10)));
            ticketForm.Show();
            ActivateForm(ticketForm);
            ticketForm.FocusFirst();
            TicketForm tf = ticketForm;
            Later(0.2, delegate { if (tf.Visible) { ActivateForm(tf); tf.FocusFirst(); } });
        }
    }

    partial class Pet
    {
        // 一定放大敲玻璃（搶票最後一分鐘、開賣當下）
        public void ForceGlass(string text, string hint, bool loud)
        {
            WakeIfSleep();
            sense = loud ? 3.5 : 2.5;
            if (Out && Grounded() && state != "glass") StartGlass(text);
            Say(text, loud ? 10 : 8, true, hint);
            bubblePri = 2;
            if (loud) { Burst(14); AddHeart(); AddHeart(); }
        }

        // 搶票倒數的大徽章（畫在頭頂上）
        void DrawTicketBadge(Graphics g, int ox, int oy)
        {
            string cd = w.TicketCountdown();
            if (cd == null || w.Lead() != this) return;
            using (Font f = new Font("Consolas", (float)Math.Max(13, 11 * k), FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font f2 = new Font("Microsoft JhengHei UI", (float)Math.Max(12, 9.5 * k), FontStyle.Bold, GraphicsUnit.Pixel))
            {
                Font use = cd.Contains(":") ? f : f2;
                SizeF ts = g.MeasureString(cd, use);
                float iw = 9 * (float)k, bw = ts.Width + iw + 10 * (float)k, bh = ts.Height + 4 * (float)k;
                float bx = (float)(Cx - bw / 2) - ox, by = (float)(y - (P.TopRows + 6) * S - bh) - oy;
                bool hot = !cd.Contains(":") || cd.StartsWith("00");
                using (GraphicsPath p = new GraphicsPath())
                {
                    float r = bh / 2;
                    p.AddArc(bx, by, 2 * r, 2 * r, 90, 180); p.AddArc(bx + bw - 2 * r, by, 2 * r, 2 * r, 270, 180); p.CloseFigure();
                    using (SolidBrush b = new SolidBrush(hot ? Color.FromArgb(240, 0xD8, 0x3A, 0x3A) : Color.FromArgb(235, 0x2A, 0x2F, 0x45))) g.FillPath(b, p);
                    using (Pen rim = new Pen(Color.FromArgb(220, 255, 255, 255), Math.Max(1.5f, (float)k))) g.DrawPath(rim, p);
                }
                // 小票券圖示
                float tx = bx + 5 * (float)k, ty = by + bh / 2 - 3.5f * (float)k;
                using (SolidBrush tb = new SolidBrush(Color.FromArgb(0xFF, 0xD8, 0x4A))) g.FillRectangle(tb, tx, ty, iw - 2 * (float)k, 7 * (float)k);
                using (SolidBrush hole = new SolidBrush(hot ? Color.FromArgb(0xD8, 0x3A, 0x3A) : Color.FromArgb(0x2A, 0x2F, 0x45))) g.FillEllipse(hole, tx - 1.5f * (float)k, ty + 2.2f * (float)k, 3 * (float)k, 2.6f * (float)k);
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
                using (SolidBrush wb = new SolidBrush(Color.White)) g.DrawString(cd, use, wb, bx + iw + 7 * (float)k, by + 2 * (float)k);
            }
        }
    }

    // 「搶票提醒…」的小視窗
    class TicketForm : Form
    {
        readonly World w;
        readonly TextBox name = new TextBox(), time = new TextBox(), url = new TextBox();
        readonly DateTimePicker date = new DateTimePicker();
        readonly RadioButton lead1 = new RadioButton(), lead2 = new RadioButton();
        readonly Label hint = new Label();
        public TicketForm(World w, Color accent)
        {
            this.w = w;
            Text = "🎫 搶票提醒";
            FormBorderStyle = FormBorderStyle.FixedToolWindow;
            ShowInTaskbar = false; TopMost = true; MaximizeBox = false; MinimizeBox = false;
            BackColor = Color.FromArgb(0xFF, 0xFB, 0xF4);
            Font = new Font("Microsoft JhengHei UI", 10f);
            AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(360, 268);
            int y0 = 12;
            AddLabel("要搶什麼？（例如：五月天 演唱會）", y0); name.Location = new Point(14, y0 + 22); name.Width = 332; Controls.Add(name);
            AddLabel("開賣日期與時間", y0 + 56);
            date.Format = DateTimePickerFormat.Custom; date.CustomFormat = "yyyy-MM-dd"; date.Location = new Point(14, y0 + 78); date.Width = 150; Controls.Add(date);
            time.Location = new Point(176, y0 + 78); time.Width = 80; time.Text = "12:00"; Controls.Add(time);
            AddLabel("購票網址（可以不填）", y0 + 112); url.Location = new Point(14, y0 + 134); url.Width = 332; Controls.Add(url);
            lead2.Text = "提前 2 小時"; lead2.Checked = true; lead2.Location = new Point(14, y0 + 168); lead2.AutoSize = true; Controls.Add(lead2);
            lead1.Text = "提前 1 小時"; lead1.Location = new Point(130, y0 + 168); lead1.AutoSize = true; Controls.Add(lead1);
            Button ok = new Button(); ok.Text = "好，幫我盯著"; ok.Location = new Point(206, y0 + 200); ok.Size = new Size(140, 34);
            ok.FlatStyle = FlatStyle.Flat; ok.BackColor = accent; ok.ForeColor = Color.White; ok.FlatAppearance.BorderSize = 0;
            ok.Click += delegate { Submit(); };
            Controls.Add(ok);
            hint.Location = new Point(14, y0 + 208); hint.AutoSize = true; hint.ForeColor = Color.FromArgb(0xB0, 0x40, 0x40); Controls.Add(hint);
            AcceptButton = ok;
            KeyPreview = true;
            KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Escape) Hide(); };
            FormClosing += delegate(object s, FormClosingEventArgs e) { if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); } };
        }

        public void FocusFirst() { name.Select(); name.Focus(); }

        void AddLabel(string s, int y) { Label l = new Label(); l.Text = s; l.Location = new Point(14, y); l.AutoSize = true; Controls.Add(l); }

        void Submit()
        {
            DateTime t;
            string tm = time.Text.Trim().Replace("：", ":");
            if (!DateTime.TryParse(date.Value.ToString("yyyy-MM-dd") + " " + tm, out t)) { hint.Text = "時間看不懂，例如 12:00"; return; }
            if (t < DateTime.Now) { hint.Text = "這個時間已經過了喔"; return; }
            string u = url.Text.Trim();
            if (u != "" && !(u.StartsWith("http://") || u.StartsWith("https://"))) { hint.Text = "網址要 http:// 或 https:// 開頭"; return; }
            long ms = (long)(t.ToUniversalTime() - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalMilliseconds;
            w.AddTicket(ms, lead1.Checked ? 60 : 120, u == "" ? "-" : u, name.Text.Trim());
            name.Text = ""; url.Text = ""; hint.Text = "";
            Hide();
        }
    }

    // ================= 午餐時間（平日 12:00～13:30）=================
    // 12:00 開飯（拿著自己的午餐）→ 13:00 吃飽睡午覺 → 13:25 提醒快結束 → 13:30 變回來工作
    partial class World
    {
        public string LunchState = "";          // "" / eat / nap / soon
        int forceLunch = -1;                    // -1 照時間、1 強制開飯、2 強制午睡、0 強制結束
        int lunchChecked = -1;
        public bool Lunch { get { return LunchState != ""; } }

        string LunchByClock()
        {
            DateTime n = DateTime.Now;
            if (n.DayOfWeek == DayOfWeek.Saturday || n.DayOfWeek == DayOfWeek.Sunday) return "";
            int m = n.Hour * 60 + n.Minute;
            if (m >= 12 * 60 && m < 13 * 60) return "eat";
            if (m >= 13 * 60 && m < 13 * 60 + 25) return "nap";
            if (m >= 13 * 60 + 25 && m < 13 * 60 + 30) return "soon";
            return "";
        }

        void LunchTick(bool force)
        {
            int minute = DateTime.Now.Minute;
            if (!force && minute == lunchChecked) return;
            lunchChecked = minute;
            string want = forceLunch == 1 ? "eat" : (forceLunch == 2 ? "nap" : (forceLunch == 0 || !Feat("lunch") ? "" : LunchByClock()));
            if (want == LunchState) return;
            string was = LunchState;
            LunchState = want;
            List<Pet> outs = OutPets();
            Pet l = Lead();
            double d = 0;
            if (want == "eat" && was == "")
            {
                foreach (Pet p in outs) { Pet pp = p; Later(d, delegate { pp.LunchStart(); }); d += 0.8; }
                if (outs.Count == 0) l.Say(l.LunchLine("start"), 3);
            }
            else if (want == "nap")
            {
                foreach (Pet p in outs) { Pet pp = p; Later(d, delegate { pp.LunchNap(); }); d += 0.6; }
            }
            else if (want == "soon")
            {
                foreach (Pet p in outs) p.WakeIfSleep();
                l.Say("午休快結束囉～", 3);
            }
            else if (want == "")
            {
                foreach (Pet p in outs) { Pet pp = p; Later(d, delegate { pp.LunchEnd(); }); d += 0.7; }
                if (outs.Count == 0) l.Say(l.LunchLine("end"), 3);
            }
        }
    }

    partial class Pet
    {
        // 每個角色的午餐
        static readonly string[] PIZZA = { "1111", "1YSY", ".YYS", ".YY.", "..Y." };
        static readonly string[] CUSTARD = { "..2...", ".P2PP.", "PPPPPP", "kWWWWk", ".kWWk." };
        static readonly string[] SANDWICH = { ".11111.", "1PPPPP1", "SSSSSSS", "YYYYYYY", ".11111." };
        static readonly string[] MILKTEA = { "kkkk", "k22k", "k12k", "k22k", ".kk." };
        static readonly string[] BUN = { ".YY.", "Y1YY", "YWWY", "YYYY" };
        static readonly string[] PLATE = { "..1....", "kWWWWWk", ".kkkkk." };

        public string LunchLine(string phase)
        {
            if (P.Pik) return PikLunchLine(phase);
            if (P.Orig) return OrigLunchLine(phase);
            switch (P.Id)
            {
                case "po":
                    if (phase == "start") return "嘟嘟糊！午餐時間！🔔";
                    if (phase == "nap") return "吃飽飽…小波想睡覺覺";
                    if (phase == "end") return "Eh-oh! 回來工作囉！";
                    return Pick(new string[] { "嘟嘟糊！再來一碗！", "嘟嘟糊黏在臉上了嘻嘻", "好好吃～再來一次！" });
                case "stitch":
                    if (phase == "start") return "午餐！好吃！ih-ih! 🔔";
                    if (phase == "nap") return "呼…吃太飽…";
                    if (phase == "end") return "回來工作！嘻嘻嘻";
                    return Pick(new string[] { "好吃！ih-ih!", "（屑屑掉滿地）嘻嘻嘻", "史迪仔還要一個！" });
                case "hangyodon":
                    if (phase == "start") return "午餐時間！港式奶茶＋菠蘿油 🔔";
                    if (phase == "nap") return "吃飽了…在泡泡裡睡一下";
                    if (phase == "end") return "回來工作！英雄也要上班";
                    return Pick(new string[] { "奶茶要走冰…我自己就很冰了（魚嘛）", "菠蘿油的牛油要厚切！", "茶走、少甜，謝謝老闆～" });
                case "tinky":
                    if (phase == "start") return "吐司時間！丁丁從魔法袋拿出吐司 🔔";
                    if (phase == "nap") return "吃飽飽…丁丁抱著袋袋睡覺覺";
                    if (phase == "end") return "Eh-oh! 回來工作囉！";
                    return Pick(new string[] { "吐司！好香～", "吐司屑屑掉進袋子了", "再一片！再來一次！" });
                case "dipsy":
                    if (phase == "start") return "嘟嘟糊時間！帽子不用拿下來 🔔";
                    if (phase == "nap") return "吃飽了…帽子拉低睡一下";
                    if (phase == "end") return "Eh-oh. 回來工作。";
                    return Pick(new string[] { "嘟嘟糊，酷。", "（帽子沾到嘟嘟糊了）…沒事。", "再一碗。" });
                case "laalaa":
                    if (phase == "start") return "午餐時間！吐司沾嘟嘟糊～啦啦啦 🔔";
                    if (phase == "nap") return "吃飽飽…拉拉抱著球球睡覺覺";
                    if (phase == "end") return "Eh-oh! 回來工作囉！啦～";
                    return Pick(new string[] { "吐司沾嘟嘟糊～好好吃！", "啦啦啦～吃飯飯～", "嘟嘟糊黏在臉上了嘻嘻" });
            }
            if (phase == "start") return "Pizza time! 🍕 午餐時間！";
            if (phase == "nap") return "吃飽了…蜘蛛也要午睡 zZ";
            if (phase == "end") return "回來工作！能力越強，吃得越多 🕸";
            return Pick(new string[] { "嗯～起司拉好長", "Pizza time! 🍕", "Thwip! 接到掉下來的臘腸了" });
        }

        public void LunchStart()
        {
            if (!Out) return;
            WakeIfSleep();
            Say(LunchLine("start"), 3);
            Mark(0); Mark(0); Burst(6);
            if (Grounded()) Jump(0, -240 * k);
        }

        public void LunchNap()
        {
            if (!Out) return;
            if (Grounded()) { GoSleep(); t = 25 * 60; }
            Say(LunchLine("nap"), 2.6);
        }

        public void LunchEnd()
        {
            if (!Out) return;
            WakeIfSleep();
            Say(LunchLine("end"), 2.8);
            if (Grounded()) Jump(0, -260 * k);
        }

        bool HoldingFood()
        {
            return w.LunchState == "eat" || w.LunchState == "soon";
        }

        // 吃東西：手上的午餐（睡午覺時擺在旁邊的空盤子）
        void DrawLunch(Graphics g, Fr f, int bx, int by, int ps, bool fx)
        {
            if (!w.Lunch || f.Rot != 0 || f.Fy) return;
            if (state == "sleep") { DrawAt(g, PLATE, 12, 13, bx, by, ps, fx, false, true); return; }
            if (!HoldingFood() || state == "glass" || state == "hug") return;
            int bite = Step2(2.5) ? 1 : 0;   // 一口一口：手上的食物上下動
            if (P.Pik) { DrawPikLunch(g, f, bx, by, ps, fx, bite); return; }
            if (P.Orig) { DrawOrigLunch(g, f, bx, by, ps, fx, bite); return; }
            switch (P.Id)
            {
                case "po":
                    DrawAt(g, CUSTARD, 9, 8 + bite + f.AccDy, bx, by, ps, fx, false, true);
                    // 嘟嘟糊沾在臉上
                    using (SolidBrush cu = new SolidBrush(Night ? Color.FromArgb(0xC9, 0x7A, 0x96) : Color.FromArgb(0xFF, 0x9C, 0xC0)))
                    {
                        int cx = fx ? bx + 4 * ps : bx + 7 * ps;
                        g.FillRectangle(cu, cx, by + (5 + f.AccDy) * ps, ps, ps);
                    }
                    break;
                case "stitch":
                    DrawAt(g, SANDWICH, 3, 6 + bite + f.AccDy, bx, by, ps, fx, false, true);
                    if (rnd.NextDouble() < 0.05 && notes.Count < 10) notes.Add(new double[] { R(-8, 8) * k, 0, 7 });
                    break;
                case "hangyodon":
                    DrawAt(g, MILKTEA, 10.5, 8 + f.AccDy, bx, by, ps, fx, false, true);
                    DrawAt(g, BUN, -2.5, 8 + bite + f.AccDy, bx, by, ps, fx, false, true);
                    break;
                case "tinky": DrawAt(g, TOAST, 10.5, P.BodyTop + 1 + bite + f.AccDy, bx, by, ps, fx, false, true); break;
                case "dipsy": DrawAt(g, A("DUDU"), 9, P.BodyTop + bite + f.AccDy, bx, by, ps, fx, false, true); break;
                case "laalaa":
                    DrawAt(g, TOAST, -1.5, P.BodyTop + 1 + bite + f.AccDy, bx, by, ps, fx, false, true);
                    DrawAt(g, A("DUDU_CUP"), 11, P.BodyTop + 2 + f.AccDy, bx, by, ps, fx, false, true);
                    break;
                default:
                    DrawAt(g, PIZZA, 10, 7 + bite, bx, by, ps, fx, false, true);
                    break;
            }
        }

        // 櫃子裡的公仔也拿著午餐
        void DrawLunchShelf(Graphics g, int bx, int by, int ps, bool flip)
        {
            if (!w.Lunch) return;
            if (P.Pik || P.Orig) return;   // 皮克敏、續命小隊在自己的櫃子畫法裡拿午餐
            string[] food; double col, row;
            switch (P.Id)
            {
                case "po": food = CUSTARD; col = 9; row = 8; break;
                case "stitch": food = SANDWICH; col = 3; row = 6; break;
                case "hangyodon": food = MILKTEA; col = 10.5; row = 8; break;
                case "tinky": food = TOAST; col = 10.5; row = P.BodyTop + 1; break;
                case "dipsy": food = A("DUDU"); col = 9; row = P.BodyTop; break;
                case "laalaa": food = TOAST; col = -1.5; row = P.BodyTop + 1; break;
                default: food = PIZZA; col = 10; row = 7; break;
            }
            DrawAt(g, food, col, row, bx, by, ps, flip, false, true);
        }
    }

    partial class Pet
    {
        // 外出中的格子：淡淡的剪影，櫃子還是他的位置
        public void DrawGhost(Graphics g, int fx, int fy, int ps, bool night)
        {
            string[] rows = Pal.Stack(A("HEAD"), A("BODY"), A("LEGS_A"));
            int bx = fx - rows[0].Length * ps / 2, by = fy - rows.Length * ps;
            Color c = P.Accent;
            using (SolidBrush b = new SolidBrush(Color.FromArgb(night ? 34 : 42, c.R, c.G, c.B)))
                for (int r = 0; r < rows.Length; r++)
                    for (int i = 0; i < rows[r].Length; i++)
                        if (rows[r][i] != '.') g.FillRectangle(b, bx + i * ps, by + r * ps, ps, ps);
        }

        // 在櫃子裡要佔幾列高（腳到最高點：天線、耳朵、帽子、滑板車墊高、晃動）
        public int ShelfRows()
        {
            if (P.Pik) return PikShelfRows();
            if (P.Orig) return OrigShelfRows();
            int hat = (w.SeasonNow == "xmas" || Level() >= 3) ? 4 : 0;
            switch (P.Id)
            {
                case "po": return 16 + P.TopRows + 1;                             // 扶著停在旁邊的滑板車
                case "stitch": return 16 + Math.Max(P.TopRows, hat > 0 ? 3 : 0) + 1;
                case "hangyodon": return 16 + (hat > 0 ? 2 : 0) + 1;
                case "tinky": return 16 + P.TopRows + 1;                           // 天線從帽子穿出來，不會更高
                case "dipsy": return 16 + P.TopRows + 2;                           // 高帽子＋偶爾抬一下
                case "laalaa": return 16 + Math.Max(P.TopRows, hat > 0 ? 7 : 0) + 1;
            }
            return 16 + hat + 1;
        }

        public void PreviewLevel(int x) { xp = x; }

        public void Reload() { xp = 0; lastPatDay = ""; patsToday = 0; patsDate = ""; LoadBond(); }

        // 開發用預覽：每個角色各種姿勢排成一張圖
        public static void PreviewSheet(string path, bool night)
        {
            World w = new World(6);
            w.Night = night;
            string[][] poses = {
                new string[] { "spidey", "idle", "walk", "hug", "glass", "sleep", "hang", "swing", "dizzy" },
                new string[] { "po", "idle", "walk", "hug", "glass", "sleep", "bat1", "bat2", "bat3", "catch", "homerun", "wave", "roll" },
                new string[] { "stitch", "idle", "walk", "hug", "glass", "sleep", "ceil", "curl", "elvis", "grin", "wall", "chomp" },
                new string[] { "hangyodon", "idle", "walk", "hug", "glass", "sleep", "silly", "hero", "swim", "cape", "trip", "header" } };
            int cw = 34 * 6, ch = 30 * 6;
            using (Bitmap b = new Bitmap(cw * 12, ch * 4))
            using (Graphics g = Graphics.FromImage(b))
            using (Font f = new Font("Arial", 10))
            {
                g.Clear(night ? Color.FromArgb(0x30, 0x34, 0x44) : Color.FromArgb(0xE6, 0xEA, 0xF0));
                for (int r = 0; r < poses.Length; r++)
                {
                    Pet p = w.Get(poses[r][0]);
                    p.Out = true;
                    for (int c = 1; c < poses[r].Length; c++)
                    {
                        string s = poses[r][c];
                        p.state = s; p.anim = 0.3; p.t = 1; p.Bt = 0; p.rolling = false; p.hangPhase = 1; p.poseKind = ""; p.dir = 1; p.tripT = 0; p.caped = false;
                        if (s == "walk") { p.anim = 0.05; }
                        if (s.StartsWith("bat")) { p.state = "bat"; p.batT = s == "bat1" ? 0.1 : (s == "bat2" ? 0.28 : 0.5); }
                        if (s == "homerun" || s == "grin") { p.state = "pose"; p.poseKind = s; }
                        if (s == "roll") { p.state = "air"; p.rolling = true; p.anim = 0.1; }
                        if (s == "silly" || s == "hero") { p.state = "pose"; p.poseKind = s; }
                        if (s == "swim") { p.Mark(5); p.Mark(5); }
                        if (s == "cape") { p.state = "swim"; p.caped = true; }
                        if (s == "trip") { p.state = "capetrip"; p.tripT = 1; }
                        p.x = (c - 1) * cw + 11 * 6; p.y = r * ch + 11 * 6;
                        g.DrawString(s, f, night ? Brushes.White : Brushes.Black, (c - 1) * cw + 4, r * ch + 2);
                        p.PaintPet(g, 0, 0);
                        p.notes.Clear();
                    }
                }
                b.Save(path, ImageFormat.Png);
            }
        }

        public static void PreviewTubbySheet(string path, bool night)
        {
            World w = new World(6, Pal.Teletubbies);
            w.Night = night;
            string[] ids = { "tinky", "dipsy", "laalaa", "po" };
            string[] poses = { "idle", "walk", "hug", "glass", "sleep", "plop", "dance", "wave", "photo", "special1", "special2", "special3", "ride", "wearhat", "toast", "lunch", "nightidle" };
            int cw = 30 * 6, ch = 40 * 6;
            using (Bitmap b = new Bitmap(cw * poses.Length, ch * ids.Length))
            using (Graphics g = Graphics.FromImage(b))
            using (Font f = new Font("Arial", 10))
            {
                g.Clear(night ? Color.FromArgb(0x30, 0x34, 0x44) : Color.FromArgb(0xE6, 0xEA, 0xF0));
                for (int r = 0; r < ids.Length; r++)
                {
                    Pet p = w.Get(ids[r]);
                    p.Out = true;
                    for (int c = 0; c < poses.Length; c++)
                    {
                        string s = poses[c];
                        p.state = s; p.anim = 0.3; p.t = 1; p.Bt = 0; p.rolling = false; p.poseKind = ""; p.dir = 1; p.sT = 0; p.bagItem = "";
                        p.RidingPo = false; p.WearHat = false; p.HoldToast = false; p.InScene = false; w.LunchState = "";
                        bool nightIdle = false;
                        if (s == "walk") p.anim = 0.05;
                        if (s == "plop") p.sT = 0.2;
                        if (s == "photo") { p.state = "pose"; p.poseKind = "photo"; }
                        if (s == "special1") { if (ids[r] == "tinky") { p.state = "bagdig"; p.bagItem = "toast"; p.sT = 1.5; } else if (ids[r] == "dipsy") { p.state = "hattoss"; p.sT = 0.6; } else if (ids[r] == "laalaa") { p.state = "juggle"; p.sT = 0.33; } else p.state = "spin"; }
                        if (s == "special2") { if (ids[r] == "dipsy") { p.state = "pose"; p.poseKind = "hatwave"; } else if (ids[r] == "laalaa") { p.state = "twirl"; } else if (ids[r] == "tinky") { p.state = "bagdig"; p.bagItem = ""; p.sT = 0.4; } else p.state = "catch"; }
                        if (s == "special3") { if (ids[r] == "dipsy") { p.state = "pose"; p.poseKind = "hattip"; } else if (ids[r] == "laalaa") { p.state = "kick"; p.t = 0.3; } else if (ids[r] == "tinky") { p.state = "pose"; p.poseKind = "sing"; } else p.state = "dizzy"; }
                        if (s == "ride") { p.state = "walk"; p.RidingPo = ids[r] == "tinky"; }
                        if (s == "wearhat") { p.state = "idle"; p.WearHat = ids[r] == "tinky"; }
                        if (s == "toast") { p.state = "idle"; p.HoldToast = true; }
                        if (s == "lunch") { p.state = "idle"; w.LunchState = "eat"; }
                        if (s == "nightidle") { p.state = "idle"; nightIdle = true; p.anim = 2; }
                        bool wasNight = w.Night; if (nightIdle) w.Night = true;
                        p.x = c * cw + 9 * 6; p.y = r * ch + 20 * 6;
                        g.DrawString(s, f, night ? Brushes.White : Brushes.Black, c * cw + 4, r * ch + 2);
                        p.PaintPet(g, 0, 0);
                        p.notes.Clear(); p.sparks.Clear(); p.hearts.Clear();
                        w.Night = wasNight;
                    }
                }
                b.Save(path, ImageFormat.Png);
            }
        }

        // 開發用：櫃子畫成圖
        public static void PreviewShelf(string path, bool night)
        {
            World w = new World(4);
            w.Night = night;
            w.PreviewShelfTo(path);
        }
    }

    partial class World
    {
        public void PreviewShelfTo(string path)
        {
            shelf = new ShelfForm(this, S);
            shelf.Place(new Rectangle(0, 0, 400, 400));
            string[] favs = { "spidey", "po", "stitch", "hangyodon", "po" };
            int W0 = shelf.Area.Width + 16, H0 = shelf.Area.Height + 16;
            using (Bitmap b = new Bitmap(W0 * favs.Length, H0))
            using (Graphics g = Graphics.FromImage(b))
            {
                g.Clear(Night ? Color.FromArgb(0x25, 0x2A, 0x38) : Color.FromArgb(0xD8, 0xE0, 0xEA));
                shelf.Night = Night;
                for (int v = 0; v < favs.Length; v++)
                {
                    favPin = favs[v];
                    foreach (Pet p in Pets) p.PreviewLevel(v == 4 ? 0 : 600);   // 前四張戴最大的帽子（最壞情況）
                    Pet[] c = CellPets();
                    bool[] o = new bool[4];
                    if (v == 4) for (int i = 0; i < 4; i++) o[i] = true;       // 最後一張：全部外出（剪影）
                    g.DrawImageUnscaled(shelf.Snapshot(c, o, 1.0 + v * 0.7), v * W0 + 8, 8);
                }
                b.Save(path, ImageFormat.Png);
            }
        }
    }

    // ================= 公仔小屋（蛋的右鍵）：娛樂功能開關、重新設定；只要一隻；第一次設定 =================
    partial class World
    {
        // 小屋的開關（features.txt：一行一個 key=0/1；沒寫的＝開，跟以前一樣）
        public static readonly string[][] FeatureList = {
            new string[] { "scenes", "串門子劇情" },
            new string[] { "lunch", "午餐變身" },
            new string[] { "night", "下班時間（黑化／催下班）" },
            new string[] { "rollcall", "早上點名／說再見" },
            new string[] { "windows", "跟著視窗跑／跳上視窗" },
            new string[] { "season", "節日造型" },
            new string[] { "fireworks", "煙火" },
            new string[] { "chatter", "閒聊泡泡（自己閒晃時講話）" } };
        readonly Dictionary<string, bool> feats = new Dictionary<string, bool>();
        public bool Feat(string key) { bool on; return !feats.TryGetValue(key, out on) || on; }

        void LoadFeatures()
        {
            feats.Clear();
            foreach (string line in ReadText("features.txt").Split('\n'))
            {
                string[] a = line.Trim().Split('=');
                if (a.Length == 2 && a[0].Trim() != "") feats[a[0].Trim()] = a[1].Trim() != "0";
            }
        }

        void SaveFeatures()
        {
            StringBuilder sb = new StringBuilder();
            foreach (string[] f in FeatureList) sb.Append(f[0] + "=" + (Feat(f[0]) ? "1" : "0") + "\n");
            WriteText("features.txt", sb.ToString());
        }

        public void SetFeat(string key, bool on)
        {
            feats[key] = on;
            SaveFeatures();
            App.Log("feature " + key + "=" + (on ? "1" : "0"));
            if (key == "night" || key == "season") { nightChecked = -1; CheckNight(); }   // 馬上換樣子（黑化、節日帽子）
            if (key == "lunch") LunchTick(true);
            if (key == "scenes" && !on) AbortScene();
            string name = key;
            foreach (string[] f in FeatureList) if (f[0] == key) name = f[1];
            int cut = name.IndexOf('（');
            if (cut > 0) name = name.Substring(0, cut);
            Lead().Say(on ? "好～「" + name + "」打開囉" : "好～「" + name + "」先關掉", 1.8);
        }

        // ---- 你是？（profile.txt：student｜work）、擺法（mode.txt：shelf｜single <id>）----
        public bool Student;                          // 大學生（之後會有大學生的內容；現在先記著）
        public bool Single;                           // 只要一隻：沒有櫃子，那隻的家是蛋，其他隻不出來
        string singleId = "";

        void LoadMode()
        {
            Student = ReadText("profile.txt") == "student";
            string m = ReadText("mode.txt");
            Single = m.StartsWith("single");
            singleId = Single && m.Length > 6 ? m.Substring(6).Trim() : "";
        }

        // 只要一隻的那隻（換到沒有他的那一櫃：用那一櫃預設的那隻）
        public string SinglePet() { return Get(singleId) != null ? singleId : defaultPet; }

        // 只要一隻：點蛋＝叫他出來／回蛋裡
        public void EggClick()
        {
            Pet p = Get(SinglePet());
            if (p == null) return;
            if (p.Out) { if (p.state != "stowfly" && p.state != "enter" && p.state != "exit") p.StowToShelf(true); }
            else BringOut(p, true);
        }

        // ---- 公仔小屋選單：開關＋小幫手＋公仔們 ----
        public void HouseMenu() { HouseMenu(Cursor.Position); }
        public void HouseMenu(Point at)
        {
            ContextMenuStrip m = new ContextMenuStrip();
            m.Items.Add(new ToolStripLabel("開關（打勾＝開著）"));
            foreach (string[] f in FeatureList)
            {
                string key = f[0];
                ToolStripMenuItem mi = new ToolStripMenuItem(f[1]);
                mi.CheckOnClick = true;
                mi.Checked = Feat(key);
                mi.Click += delegate { SetFeat(key, !Feat(key)); mi.Checked = Feat(key); };
                m.Items.Add(mi);
            }
            m.Items.Add(new ToolStripSeparator());
            ToolStripMenuItem help = new ToolStripMenuItem("小幫手（專注、安靜、提醒）");
            AddHelpers(help.DropDownItems);
            m.Items.Add(help);
            m.Items.Add(new ToolStripSeparator());
            m.Items.Add(new ToolStripLabel(Single ? "我的公仔" : "公仔們"));
            if (!Single) m.Items.Add(shelf.Collapsed ? "打開公仔櫃" : "收合成蛋 🥚", null, delegate { ToggleEgg(!shelf.Collapsed); });
            m.Items.Add(Single ? "叫" + Get(SinglePet()).P.Name + "出來" : "全部出來", null, delegate { AllOut(); });
            m.Items.Add(Single ? "回蛋裡" : "全部回家", null, delegate { AllHome(); });
            ToolStripMenuItem sw = new ToolStripMenuItem("換一櫃");
            foreach (string lu in Pal.Lineups)
            {
                string l2 = lu;
                ToolStripMenuItem li = new ToolStripMenuItem(Pal.LineupName(lu), null, delegate { SwitchLineup(l2, Single ? singleId : ""); });
                li.Checked = lu == lineup;
                sw.DropDownItems.Add(li);
            }
            m.Items.Add(sw);
            m.Items.Add("重新設定…", null, delegate { ShowSetup(false); });
            m.Items.Add("躲起來（Ctrl+Alt+S）", null, delegate { ToggleHide(); });
            m.Items.Add(new ToolStripSeparator());
            m.Items.Add("收工（關掉 Desk Pals）", null, delegate { QuitAll(); });
            ShowMenu(m, "公仔小屋", true, at);
        }

        // 測試用：act menu pet｜house（開在公仔／蛋旁邊，不看游標）
        void TestMenu(string arg)
        {
            if (arg == "house")
            {
                Rectangle e = shelf.Collapsed ? shelf.EggScreen() : shelf.Area;
                HouseMenu(new Point(e.X + e.Width / 2, e.Y + e.Height / 3));
                return;
            }
            Pet l = Get(arg) ?? Lead();
            ContextMenuStrip m = new ContextMenuStrip();
            FillMenu(l, m);
            ShowMenu(m, l.P.Name, false, new Point((int)l.Cx, (int)l.y));
        }

        // ---- 設定視窗 ----
        SetupForm setupForm;
        public void ShowSetup(bool first)
        {
            if (setupForm == null || setupForm.IsDisposed)
                setupForm = new SetupForm(this, first, ReadText("profile.txt"), lineup, Single, Single ? SinglePet() : "");
            Rectangle wa = App.Offscreen ? screens[0].WorkingArea : Screen.FromPoint(Cursor.Position).WorkingArea;
            setupForm.Location = new Point(wa.Left + (wa.Width - setupForm.Width) / 2, wa.Top + Math.Max(0, (wa.Height - setupForm.Height) / 2));
            setupForm.Show();
            if (App.Offscreen) return;
            ActivateForm(setupForm);
            SetupForm sf = setupForm;
            Later(0.2, delegate { if (!sf.IsDisposed && sf.Visible) ActivateForm(sf); });   // 再補一次，確定點得到
        }

        // 設定好了：馬上套用（不用重開）
        public void ApplySetup(string prof, string lu, bool single, string pet, bool first)
        {
            WriteText("profile.txt", prof == "student" ? "student" : "work");
            Student = prof == "student";
            lu = Pal.NormLineup(lu);
            bool wasSingle = Single;
            Single = single;
            singleId = single ? pet : "";
            WriteText("mode.txt", single ? "single " + pet : "shelf");
            App.Log("setup profile=" + prof + " lineup=" + lu + " mode=" + (single ? "single " + pet : "shelf"));
            if (single)
            {
                if (!shelf.Collapsed) { shelf.Collapsed = true; WriteText("shelf-state.txt", "egg"); }
                if (lu != lineup) SwitchLineup(lu, pet);
                else { Pet p = Get(pet); if (p != null) SelectOnly(p); }
                Pet sp = Get(SinglePet());
                if (sp != null) Later(1.6, delegate { sp.Say("以後我住在右下角的蛋裡～點一下蛋就叫我 🥚", 3.5); });
            }
            else
            {
                if (lu != lineup) SwitchLineup(lu, "");
                if (shelf.Collapsed && (wasSingle || first)) { shelf.Collapsed = false; WriteText("shelf-state.txt", "open"); }
                if (wasSingle || first) Later(0.6, delegate { AllOut(); });
            }
            RenderShelf();
        }

        // 設定視窗用：這一櫃的櫃子縮圖（預覽用的 World 才叫這個，不開視窗）
        public Bitmap SetupShelfPic()
        {
            shelf = new ShelfForm(this, S);
            shelf.Tubby = TubbyLineup; shelf.Pik = PikLineup; shelf.Orig = OrigLineup;
            shelf.Night = false;
            shelf.Place(new Rectangle(0, 0, 2000, 2000));
            Bitmap b = shelf.Snapshot(CellPets(), new bool[4], 1.0);
            return (Bitmap)b.Clone();
        }
    }

    partial class Pet
    {
        // 設定視窗用：站好的樣子畫成一張小圖（預覽用的 World 才叫這個）
        public Bitmap IconPic()
        {
            int pad = 3 * S, top = P.TopRows * S;
            Bitmap b = new Bitmap(SW + 2 * pad, SH + top + 2 * pad, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(b))
            {
                g.Clear(Color.Transparent);
                Out = true; state = "idle"; anim = 0.3; t = 1; Bt = 0; dir = 1;
                x = pad; y = pad + top;
                PaintPet(g, 0, 0);
                Out = false;
            }
            return b;
        }
    }

    // 像素風的小工具（像素選單、設定視窗共用）：方塊、缺角方塊、木框、奶油色面板、銅牌、勾勾、愛心、像素圖
    static class Pix
    {
        public static Color C(int rgb) { return Color.FromArgb((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255); }
        public static Color Mix(Color a, Color b, double f) { return Color.FromArgb((int)(a.R + (b.R - a.R) * f), (int)(a.G + (b.G - a.G) * f), (int)(a.B + (b.B - a.B) * f)); }
        public static readonly Color Ink = C(0x4A2C17), Cream = C(0xFFF6E4), TextC = C(0x4A3010), Dim = C(0xB5A089), Gold = C(0xE2B550);
        public static readonly TextFormatFlags Mid = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix;
        public static readonly TextFormatFlags LeftMid = TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix;
        public static readonly string[] HEART = { ".#.#.", "#####", ".###.", "..#.." };
        public static readonly string[] CHECK = { "....#", "...##", "#.##.", "###..", ".#..." };

        public static void Box(Graphics g, Color c, int x, int y, int w, int h)
        {
            if (w <= 0 || h <= 0) return;
            using (SolidBrush b = new SolidBrush(c)) g.FillRectangle(b, x, y, w, h);
        }
        // 像素圓角：四個角各缺一格
        public static void Round(Graphics g, Color c, int x, int y, int w, int h, int u)
        {
            Box(g, c, x + u, y, w - 2 * u, h);
            Box(g, c, x, y + u, w, h - 2 * u);
        }
        public static void Art(Graphics g, string[] art, Dictionary<char, Color> pal, int x, int y, int c)
        {
            for (int ry = 0; ry < art.Length; ry++)
                for (int rx = 0; rx < art[ry].Length; rx++)
                {
                    Color col;
                    if (pal.TryGetValue(art[ry][rx], out col)) Box(g, col, x + rx * c, y + ry * c, c, c);
                }
        }
        public static void Mono(Graphics g, string[] art, Color c, int x, int y, int u)
        {
            Dictionary<char, Color> pal = new Dictionary<char, Color>();
            pal['#'] = c;
            Art(g, art, pal, x, y, u);
        }
        // 木框（跟公仔櫃同一套木頭色）：深色外框、亮的上緣、暗的下緣、木紋、四角小釘子
        public static void Wood(Graphics g, int x, int y, int w, int h, int u, bool night, int seed)
        {
            Color wl = night ? C(0x74503A) : C(0xB97F4E), wm = night ? C(0x5C3B24) : C(0x9A6338), wd = night ? C(0x3C2617) : C(0x6B4024);
            Round(g, Ink, x, y, w, h, u);
            Box(g, wm, x + u, y + u, w - 2 * u, h - 2 * u);
            Box(g, wl, x + 2 * u, y + u, w - 4 * u, u);
            Box(g, wd, x + 2 * u, y + h - 2 * u, w - 4 * u, u);
            Random r = new Random(seed);
            Color grain = Mix(wm, wd, 0.45);
            int gh = Math.Max(1, u / 2), n = 10 + w * h / (40 * 40);
            for (int i = 0; i < n; i++)
            {
                int gx = x + 2 * u + r.Next(Math.Max(1, w - 10 * u)), gy = y + 2 * u + r.Next(Math.Max(1, h - 4 * u));
                Box(g, grain, gx, gy, 3 * u + r.Next(5 * u), gh);
            }
            Color nail = night ? C(0xB08A3C) : Gold;
            Box(g, nail, x + 2 * u, y + 2 * u, u, u); Box(g, nail, x + w - 3 * u, y + 2 * u, u, u);
            Box(g, nail, x + 2 * u, y + h - 3 * u, u, u); Box(g, nail, x + w - 3 * u, y + h - 3 * u, u, u);
        }
        // 奶油色面板：凹進去（外圈深木色、上面和左邊一條陰影）
        public static void Panel(Graphics g, int x, int y, int w, int h, int u, bool night)
        {
            Box(g, night ? C(0x3C2617) : C(0x6B4024), x - u, y - u, w + 2 * u, h + 2 * u);
            Box(g, Cream, x, y, w, h);
            Box(g, C(0xEAD7B4), x, y, w, u);
            Box(g, C(0xF3E6CC), x, y + u, u, h - u);
        }
        // 銅牌（跟櫃子的名牌一樣）
        public static void Plate(Graphics g, string s, Font f, Rectangle r, int u)
        {
            Round(g, Ink, r.X, r.Y, r.Width, r.Height, u);
            Box(g, C(0xEBC56A), r.X + u, r.Y + u, r.Width - 2 * u, r.Height - 2 * u);
            Box(g, C(0xF8DE8E), r.X + 2 * u, r.Y + u, r.Width - 4 * u, u);
            Box(g, C(0xC08A2C), r.X + 2 * u, r.Bottom - 2 * u, r.Width - 4 * u, u);
            Box(g, C(0x8A5A2A), r.X + 2 * u, r.Y + r.Height / 2 - u / 2, u, u);
            Box(g, C(0x8A5A2A), r.Right - 3 * u, r.Y + r.Height / 2 - u / 2, u, u);
            TextRenderer.DrawText(g, s, f, new Rectangle(r.X, r.Y, r.Width, r.Height - u / 2), TextC, Mid);
        }
        public static int TextW(string s, Font f) { return TextRenderer.MeasureText(s, f, new Size(4000, 400), TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix).Width; }
    }

    // ================= 像素選單（取代原生右鍵選單）=================
    // 木框＋奶油色面板（跟公仔櫃同一套顏色）；小屋的選單上面是屋頂和煙囪、下面有門和窗。
    // 內容照樣用 ToolStrip 項目寫：ToolStripLabel＝小標題、子選單原地展開、CheckOnClick（開關）按了不關選單。
    // 可以變成前景（收得到 Esc、失去焦點就關）；點到外面由 World 的計時器看滑鼠按鍵來關。
    class PixelMenu : OverlayForm
    {
        class Row { public ToolStripItem It; public int Depth, Y, H; public bool Header, Sep, Sub, Check; }
        readonly World w;
        readonly ContextMenuStrip menu;
        readonly string title;
        public readonly bool House;
        readonly List<Row> rows = new List<Row>();
        readonly List<ToolStripItem> opened = new List<ToolStripItem>();
        readonly Font font, small, titleFont;
        readonly int U, F, rowH;
        readonly bool night;
        int topH, botH, smokeH, roofH, wallX, hover = -1;
        bool anyCheck, up;
        Point anchor;
        public bool Done, Armed;

        public PixelMenu(World w, ContextMenuStrip menu, string title, bool house) : base(false)
        {
            this.w = w; this.menu = menu; this.title = title ?? ""; House = house;
            double d = w.S / 4.0;
            U = Math.Max(2, (int)Math.Round(2 * d));
            F = 4 * U;
            rowH = Math.Max(22, (int)Math.Round(25 * d));
            night = w.Night;
            font = new Font("Microsoft JhengHei UI", 10f, FontStyle.Bold);
            small = new Font("Microsoft JhengHei UI", 8.5f, FontStyle.Bold);
            titleFont = new Font("Microsoft JhengHei UI", house ? 11f : 10f, FontStyle.Bold);
            KeyPreview = true;
            Deactivate += delegate { CloseMenu(); };
        }

        // 跟其他小視窗不一樣：要能變成前景（收 Esc、失去焦點時關掉）
        protected override bool ShowWithoutActivation { get { return false; } }
        protected override CreateParams CreateParams { get { CreateParams cp = base.CreateParams; cp.ExStyle &= ~0x08000000; return cp; } }

        public void Popup(Point at) { anchor = at; Reflow(true); Show(); }

        void BuildRows()
        {
            rows.Clear();
            anyCheck = false;
            AddRows(menu.Items, 0);
            // 頭尾、連在一起的分隔線拿掉
            for (int i = rows.Count - 1; i >= 0; i--)
                if (rows[i].Sep && (i == 0 || i == rows.Count - 1 || rows[i - 1].Sep)) rows.RemoveAt(i);
        }

        void AddRows(ToolStripItemCollection items, int depth)
        {
            foreach (ToolStripItem it in items)
            {
                if (!it.Available) continue;
                Row r = new Row();
                r.It = it; r.Depth = depth;
                ToolStripMenuItem mi = it as ToolStripMenuItem;
                if (it is ToolStripSeparator) { r.Sep = true; r.H = 3 * U; }
                else if (it is ToolStripLabel) { r.Header = true; r.H = rowH * 4 / 5; }
                else
                {
                    r.H = rowH;
                    r.Sub = mi != null && mi.DropDownItems.Count > 0;
                    r.Check = mi != null && (mi.Checked || mi.CheckOnClick);
                    if (r.Check) anyCheck = true;
                }
                rows.Add(r);
                if (r.Sub && opened.Contains(it)) AddRows(mi.DropDownItems, depth + 1);
            }
        }

        string RowText(Row r) { return World.NoEmoji(r.It.Text ?? ""); }

        // 算大小、擺位置：開在游標右下，放不下就往左／往上（子選單展開時往上開的就往上長）
        void Reflow(bool place)
        {
            BuildRows();
            int inner = 0;
            foreach (Row r in rows)
            {
                if (r.Sep) continue;
                int tw = Pix.TextW(RowText(r), r.Header ? small : font) + r.Depth * 5 * U;
                if (r.Header) tw += 10 * U; else { if (anyCheck) tw += 9 * U; tw += 8 * U; }
                inner = Math.Max(inner, tw);
            }
            int tTitle = title == "" ? 0 : Pix.TextW(title, titleFont);
            if (House)
            {
                smokeH = 10 * U; roofH = 22 * U;
                wallX = 4 * U;
                topH = smokeH + roofH + 3 * U;
                botH = 22 * U;
                inner = Math.Max(inner, tTitle + 16 * U);
            }
            else
            {
                smokeH = 0; roofH = 0; wallX = 0;
                topH = title == "" ? F : rowH + 5 * U;
                botH = F;
                inner = Math.Max(inner, tTitle + 14 * U);
            }
            int wd = Math.Max((int)(180 * w.S / 4.0), inner + 2 * (F + 3 * U + wallX));
            int y = topH + U;
            foreach (Row r in rows) { r.Y = y; y += r.H; }
            int ht = y + U + botH;
            Rectangle wa = Screen.FromPoint(anchor).WorkingArea;
            int x, yy;
            if (place)
            {
                x = anchor.X + 2; yy = anchor.Y + 2; up = false;
                if (x + wd > wa.Right) x = anchor.X - wd - 2;
                if (yy + ht > wa.Bottom) { yy = anchor.Y - ht - 2; up = true; }
            }
            else { x = Left; yy = up ? Bottom - ht : Top; }
            x = Math.Max(wa.Left, Math.Min(x, wa.Right - wd));
            yy = Math.Max(wa.Top, Math.Min(yy, wa.Bottom - ht));
            Bounds = new Rectangle(x, yy, wd, ht);
            Invalidate();
        }

        bool Selectable(int i) { Row r = rows[i]; return !r.Sep && !r.Header && r.It.Enabled; }

        int RowAt(Point p)
        {
            int px = wallX + F;
            if (p.X < px || p.X >= ClientSize.Width - px) return -1;
            for (int i = 0; i < rows.Count; i++)
                if (p.Y >= rows[i].Y && p.Y < rows[i].Y + rows[i].H) return Selectable(i) ? i : -1;
            return -1;
        }

        public void SetHover(int i) { hover = i >= 0 && i < rows.Count && Selectable(i) ? i : -1; Invalidate(); }

        void MoveHover(int dir)
        {
            int n = rows.Count;
            int i = hover;
            for (int j = 0; j < n; j++)
            {
                i = i < 0 ? (dir > 0 ? 0 : n - 1) : (i + dir + n) % n;
                if (Selectable(i)) { hover = i; Invalidate(); return; }
            }
        }

        // 按下一列：子選單＝展開／收起來；開關＝打勾換一下（選單不關）；其他＝關掉選單再做
        public void Pick(int i)
        {
            if (Done || i < 0 || i >= rows.Count || !Selectable(i)) return;
            Row r = rows[i];
            ToolStripMenuItem mi = r.It as ToolStripMenuItem;
            if (r.Sub)
            {
                bool open = opened.Contains(r.It);
                for (int j = opened.Count - 1; j >= 0; j--) if (DepthOf(opened[j]) >= r.Depth) opened.RemoveAt(j);   // 同一層只開一個
                if (!open) opened.Add(r.It);
                ToolStripItem keep = r.It;
                Reflow(false);
                hover = -1;
                for (int j = 0; j < rows.Count; j++) if (rows[j].It == keep) hover = j;
                return;
            }
            if (mi != null && mi.CheckOnClick) { mi.PerformClick(); Invalidate(); return; }
            ToolStripItem pick = r.It;
            App.LogAlways("menu: picked \"" + pick.Text + "\"");
            CloseMenu();
            w.BeginInvoke((Action)delegate { pick.PerformClick(); });   // 等選單關掉再做（開輸入框才拿得到焦點）
        }

        int DepthOf(ToolStripItem it) { foreach (Row r in rows) if (r.It == it) return r.Depth; return 0; }

        public void CloseMenu()
        {
            if (Done) return;
            Done = true;
            App.LogAlways("menu: closed");
            w.MenuClosed(this);
            Hide();
            w.BeginInvoke((Action)delegate { Close(); });
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (e.KeyCode == Keys.Escape) { CloseMenu(); e.Handled = true; }
            else if (e.KeyCode == Keys.Down || e.KeyCode == Keys.Up) { MoveHover(e.KeyCode == Keys.Down ? 1 : -1); e.Handled = true; }
            else if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space) { if (hover >= 0) Pick(hover); e.Handled = true; }
        }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            int h = RowAt(e.Location);
            if (h != hover) { hover = h; Invalidate(); }
        }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); if (hover != -1) { hover = -1; Invalidate(); } }
        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (e.Button != MouseButtons.Left && e.Button != MouseButtons.Right) return;
            int i = RowAt(e.Location);
            if (i >= 0) Pick(i);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(KEY);
            g.SmoothingMode = SmoothingMode.None;
            int W0 = ClientSize.Width, H0 = ClientSize.Height;
            int bodyY = House ? smokeH + roofH - U : 0, bodyH = H0 - bodyY - (House ? 2 * U : 0);
            Pix.Wood(g, wallX, bodyY, W0 - 2 * wallX, bodyH, U, night, 7);
            int px = wallX + F, pw = W0 - 2 * px, ph = H0 - topH - botH;
            Pix.Panel(g, px, topH, pw, ph, U, night);
            if (House) PaintHouse(g, W0, H0);
            else if (title != "")
            {
                int tw = Pix.TextW(title, titleFont), plw = Math.Min(pw, tw + 12 * U), plh = rowH;
                Pix.Plate(g, title, titleFont, new Rectangle((W0 - plw) / 2, (topH - plh) / 2 + U / 2, plw, plh), U);
            }
            for (int i = 0; i < rows.Count; i++) PaintRow(g, i, px, pw);
        }

        void PaintRow(Graphics g, int i, int px, int pw)
        {
            Row r = rows[i];
            int x = px + 3 * U + r.Depth * 5 * U, right = px + pw - 3 * U;
            if (r.Depth > 0) Pix.Box(g, Pix.C(0xF7EBD2), px + U, r.Y, pw - U, r.H);     // 展開的子選單：底色淡一點
            if (r.Sep)
            {
                int sy = r.Y + r.H / 2 - U / 2;
                for (int sx = px + 2 * U; sx + U <= px + pw - 2 * U; sx += 2 * U) Pix.Box(g, Pix.C(0xD8BF94), sx, sy, U, U);
                return;
            }
            if (r.Header)
            {
                string s = RowText(r);
                int cy = r.Y + r.H / 2, tw = Pix.TextW(s, small);
                Pix.Box(g, Pix.Gold, x + U, cy - U - U / 2, U, 3 * U); Pix.Box(g, Pix.Gold, x, cy - U / 2, 3 * U, U);   // 小星星
                TextRenderer.DrawText(g, s, small, new Rectangle(x + 4 * U, r.Y, tw + 4, r.H), night ? Pix.C(0x8A5A2A) : Pix.C(0x9A6338), Pix.LeftMid);
                for (int sx = x + 6 * U + tw; sx + U <= right; sx += 2 * U) Pix.Box(g, Pix.C(0xE4D0AC), sx, cy, U, U);
                return;
            }
            bool en = r.It.Enabled, hot = i == hover && en;
            if (hot)
            {
                Pix.Round(g, Pix.C(0xD9A944), px + U, r.Y + 1, pw - 2 * U, r.H - 2, U);
                Pix.Box(g, Pix.C(0xFFE29A), px + 2 * U, r.Y + 1 + U, pw - 4 * U, r.H - 2 - 2 * U);
                Pix.Box(g, Pix.C(0xFFF1C9), px + 3 * U, r.Y + 1 + U, pw - 6 * U, Math.Max(1, U / 2));
            }
            int tx = x;
            ToolStripMenuItem mi = r.It as ToolStripMenuItem;
            if (anyCheck)
            {
                if (r.Check && mi != null)
                {
                    int s = 7 * U, cy = r.Y + (r.H - s) / 2;
                    if (mi.CheckOnClick)
                    {
                        Pix.Round(g, Pix.C(0x9A6338), tx, cy, s, s, U);
                        Pix.Box(g, mi.Checked ? Pix.C(0xDDF2C8) : Pix.C(0xFFFDF7), tx + U, cy + U, s - 2 * U, s - 2 * U);
                    }
                    if (mi.Checked) Pix.Mono(g, Pix.CHECK, Pix.C(0x3F8A30), tx + U, cy + U, U);
                }
                tx += 9 * U;
            }
            TextRenderer.DrawText(g, RowText(r), font, new Rectangle(tx, r.Y, Math.Max(1, right - tx), r.H), en ? Pix.TextC : Pix.Dim, Pix.LeftMid);
            if (r.Sub) PaintArrow(g, right - 2 * U, r.Y + r.H / 2, opened.Contains(r.It), hot ? Pix.C(0x8A5A2A) : Pix.C(0xB08A5A));
            else if (hot) Pix.Mono(g, Pix.HEART, Pix.C(0xE8607A), right - 5 * U, r.Y + r.H / 2 - 2 * U, U);
        }

        // ▶（收著）／▼（展開了）
        void PaintArrow(Graphics g, int cx, int cy, bool open, Color c)
        {
            if (open) { Pix.Box(g, c, cx - 2 * U, cy - U, 5 * U, U); Pix.Box(g, c, cx - U, cy, 3 * U, U); Pix.Box(g, c, cx, cy + U, U, U); }
            else { Pix.Box(g, c, cx - U, cy - 2 * U, U, 5 * U); Pix.Box(g, c, cx, cy - U, U, 3 * U); Pix.Box(g, c, cx + U, cy, U, U); }
        }

        // 小屋：煙囪冒煙、一階一階的屋頂（名字寫在屋頂上）、下面一排窗戶和愛心門、草地
        void PaintHouse(Graphics g, int W0, int H0)
        {
            Color ink = Pix.Ink;
            int roofBot = smokeH + roofH, rh = 2 * U, n = roofH / rh;
            int half = W0 / 2, ridge = Math.Max(10 * U, W0 / 7);
            int step = Math.Max(U, (half - U - ridge) / n / U * U);
            // 煙囪（屋頂蓋住下半截）＋煙
            int cw = 5 * U, cx = W0 - W0 / 4 - cw / 2, capY = smokeH - 2 * U;
            Pix.Box(g, ink, cx - 2 * U, capY - U, cw + 4 * U, 4 * U);
            Pix.Box(g, ink, cx - U, capY, cw + 2 * U, roofBot - capY);
            Pix.Box(g, night ? Pix.C(0x8E4A35) : Pix.C(0xC0603F), cx, capY + 2 * U, cw, roofBot - capY - 2 * U);
            Pix.Box(g, night ? Pix.C(0x5E2E22) : Pix.C(0x7A3B28), cx - U, capY, cw + 2 * U, 2 * U);
            Pix.Box(g, night ? Pix.C(0x6E3628) : Pix.C(0x9A4A32), cx + U, capY + 4 * U, 2 * U, U / 2 + 1);
            Color sm = night ? Pix.C(0xB8B2C8) : Pix.C(0xF4F0EA), se = night ? Pix.C(0x7C7690) : Pix.C(0xC8BFB4);
            Puff(g, cx + cw / 2 + U, capY - 3 * U, 2 * U, sm, se);
            Puff(g, cx + cw + 3 * U, capY - 6 * U, 2 * U, sm, se);
            // 屋頂：先畫深色外框（每一階往外一格），再一排一排畫瓦片
            for (int i = 0; i < n; i++)
            {
                int x0 = U + i * step, x1 = W0 - U - i * step, y0 = roofBot - (i + 1) * rh;
                Pix.Box(g, ink, x0 - U, y0 - U, x1 - x0 + 2 * U, rh + 2 * U);
            }
            Color t1 = night ? Pix.C(0x9A4636) : Pix.C(0xD0583F), t2 = night ? Pix.C(0x873B2E) : Pix.C(0xB8472F), tk = night ? Pix.C(0x5E2A22) : Pix.C(0x8E3424), hi = night ? Pix.C(0xB86A55) : Pix.C(0xF08A68);
            for (int i = 0; i < n; i++)
            {
                int x0 = U + i * step, x1 = W0 - U - i * step, y0 = roofBot - (i + 1) * rh;
                Pix.Box(g, i % 2 == 0 ? t1 : t2, x0, y0, x1 - x0, rh);
                for (int tx = x0 + (i % 2) * 2 * U + 3 * U; tx < x1 - U; tx += 4 * U) Pix.Box(g, tk, tx, y0 + U, U, U);
                Pix.Box(g, hi, x0, y0, x1 - x0, Math.Max(1, U / 2));
            }
            Pix.Box(g, ink, wallX, roofBot, W0 - 2 * wallX, U);   // 屋簷下的陰影
            // 屋頂上的小圓窗
            int aw = 6 * U, ax = (W0 - aw) / 2, ay = smokeH + roofH / 6;
            Pix.Round(g, ink, ax, ay, aw, aw, U);
            Pix.Box(g, night ? Pix.C(0xFFD36A) : Pix.C(0xFFF3DA), ax + U, ay + U, aw - 2 * U, aw - 2 * U);
            Pix.Box(g, ink, ax + aw / 2 - U / 2, ay + U, U, aw - 2 * U);
            Pix.Box(g, ink, ax + U, ay + aw / 2 - U / 2, aw - 2 * U, U);
            // 名字寫在屋頂上（深色描邊＋奶油色字）
            if (title != "")
            {
                Rectangle tr = new Rectangle(0, smokeH + roofH * 2 / 5, W0, roofH * 3 / 5 - U);
                Color sh = night ? Pix.C(0x3A1A12) : Pix.C(0x5E2418);
                TextRenderer.DrawText(g, title, titleFont, new Rectangle(tr.X + 1, tr.Y + 1, tr.Width, tr.Height), sh, Pix.Mid);
                TextRenderer.DrawText(g, title, titleFont, new Rectangle(tr.X - 1, tr.Y + 1, tr.Width, tr.Height), sh, Pix.Mid);
                TextRenderer.DrawText(g, title, titleFont, new Rectangle(tr.X, tr.Y + 2, tr.Width, tr.Height), sh, Pix.Mid);
                TextRenderer.DrawText(g, title, titleFont, tr, Pix.C(0xFFF3DA), Pix.Mid);
            }
            // 窗戶（白天淡藍、晚上亮黃燈）＋花台
            int ww = 7 * U, wy = H0 - botH + 5 * U;
            int[] wxs = { W0 / 4 - ww / 2 - U, W0 - W0 / 4 - ww / 2 + U };
            foreach (int wx in wxs)
            {
                Pix.Round(g, ink, wx, wy, ww, ww, U);
                Pix.Box(g, night ? Pix.C(0xFFD36A) : Pix.C(0xBFE3F2), wx + U, wy + U, ww - 2 * U, ww - 2 * U);
                Pix.Box(g, night ? Pix.C(0xFFF0B0) : Color.White, wx + U, wy + U, U, U);
                Pix.Box(g, ink, wx + 3 * U, wy + U, U, ww - 2 * U);
                Pix.Box(g, ink, wx + U, wy + 3 * U, ww - 2 * U, U);
                Pix.Box(g, ink, wx - U, wy + ww, ww + 2 * U, 2 * U);
                Pix.Box(g, Pix.C(0x8E5A34), wx, wy + ww, ww, U);
                Pix.Box(g, Pix.C(0xE8607A), wx + U, wy + ww - U, U, U);
                Pix.Box(g, Pix.C(0xFFD84A), wx + 3 * U, wy + ww - U, U, U);
                Pix.Box(g, Pix.C(0xE8607A), wx + 5 * U, wy + ww - U, U, U);
                Pix.Box(g, Pix.C(0x5AA040), wx + 2 * U, wy + ww - U, U, U);
                Pix.Box(g, Pix.C(0x5AA040), wx + 4 * U, wy + ww - U, U, U);
            }
            // 門：圓頂、木板、愛心小窗、門把、門前一塊石板
            int dw = 9 * U, dh = 14 * U, dx = (W0 - dw) / 2, dy = H0 - 2 * U - dh;
            Pix.Box(g, ink, dx, dy + 2 * U, dw, dh - 2 * U); Pix.Box(g, ink, dx + U, dy + U, dw - 2 * U, U); Pix.Box(g, ink, dx + 2 * U, dy, dw - 4 * U, U);
            Color door = night ? Pix.C(0x7A4A2A) : Pix.C(0xA8693C), plank = night ? Pix.C(0x5E3820) : Pix.C(0x8A5530);
            Pix.Box(g, door, dx + U, dy + 2 * U, dw - 2 * U, dh - 2 * U); Pix.Box(g, door, dx + 2 * U, dy + U, dw - 4 * U, U);
            Pix.Box(g, plank, dx + 3 * U, dy + 7 * U, Math.Max(1, U / 2), dh - 7 * U);
            Pix.Box(g, plank, dx + 6 * U, dy + 7 * U, Math.Max(1, U / 2), dh - 7 * U);
            Pix.Mono(g, Pix.HEART, night ? Pix.C(0xFFD36A) : Pix.C(0xF27A90), dx + 2 * U, dy + 2 * U, U);
            Pix.Box(g, Pix.Gold, dx + dw - 3 * U, dy + 8 * U, U, U);
            // 草地
            Color grass = night ? Pix.C(0x4E7A44) : Pix.C(0x7CC45A), grassD = night ? Pix.C(0x3A5C36) : Pix.C(0x5AA040);
            Pix.Box(g, grass, U, H0 - 2 * U, W0 - 2 * U, 2 * U);
            Pix.Box(g, grassD, U, H0 - U, W0 - 2 * U, U);
            for (int gx = 2 * U; gx < W0 - 2 * U; gx += 5 * U) if (gx + U < dx - U || gx > dx + dw + U) Pix.Box(g, grassD, gx, H0 - 3 * U, U, U);
            Pix.Box(g, night ? Pix.C(0x8A8278) : Pix.C(0xC9BFB3), dx - U, H0 - 2 * U, dw + 2 * U, U);
        }

        void Puff(Graphics g, int cx, int cy, int r, Color fill, Color edge)
        {
            Pix.Box(g, edge, cx - r - U, cy - r, 2 * r + 2 * U, 2 * r);
            Pix.Box(g, edge, cx - r, cy - r - U, 2 * r, 2 * r + 2 * U);
            Pix.Box(g, fill, cx - r, cy - r, 2 * r, 2 * r);
            Pix.Box(g, Color.White, cx - r + U / 2, cy - r + U / 2, U, U);
        }
    }

    // ================= 設定視窗（第一次打開、小屋 → 重新設定）=================
    // 一個視窗、三步：你是？→ 選一櫃 → 怎麼擺（整櫃／只要一隻）。全部自己畫（木框＋大按鈕），點哪裡自己算。
    class SetupForm : Form
    {
        class Btn { public string Id, Text, Sub; public Rectangle R; public int Kind; public bool On, Enabled = true; }   // Kind：0 大卡片 1 公仔小卡 2 普通按鈕 3 主要按鈕
        readonly World w;
        readonly bool first;
        readonly double d;
        readonly int U;
        int step;
        string prof, lu, mode, pet;
        readonly List<Btn> btns = new List<Btn>();
        string hoverId = "";
        readonly Font titleF, qF, bigF, subF, btnF;
        readonly Dictionary<string, Bitmap> shelfPics = new Dictionary<string, Bitmap>();
        readonly Dictionary<string, Bitmap> petPics = new Dictionary<string, Bitmap>();
        public bool VVisible;

        static readonly string[] STUDENT = {
            "......kkkk......",
            "....kkddddkk....",
            "..kkddddddddkk..",
            "kkddddddddddddkk",
            "..kkddddddddkkY.",
            "....kkddddkk..Y.",
            "....kDDDDDDk..Y.",
            "....kDDDDDDk.YYY",
            "....kkkkkkkk.YYY",
            "................",
            "kkkkkkk..kkkkkkk",
            "kwwwwwwkkwwwwwwk",
            "kwlllwwkkwlllwwk",
            "kwwwwwwkkwwwwwwk",
            "kwllwwwkkwllwwwk",
            "kkkkkkkkkkkkkkkk" };
        static readonly string[] WORK = {
            "................",
            ".....kkkkkk.....",
            "....kk....kk....",
            "....k......k....",
            ".kkkkkkkkkkkkkk.",
            "kBBBBBBBBBBBBBBk",
            "kbbbbbbbbbbbbbbk",
            "kbbbbbbYYbbbbbbk",
            "kkkkkkkYYkkkkkkk",
            "kbbbbbbbbbbbbbbk",
            "kbbbbbbbbbbbbbbk",
            "kbbbbbbbbbbbbbbk",
            "kbbbbbbbbbbbbbbk",
            "kssssssssssssssk",
            ".kkkkkkkkkkkkkk.",
            "................" };

        public SetupForm(World w, bool first, string prof, string lu, bool single, string pet)
        {
            this.w = w; this.first = first;
            this.prof = prof == "student" || prof == "work" ? prof : "";
            this.lu = Pal.NormLineup(lu);
            mode = single ? "single" : "shelf";
            this.pet = pet ?? "";
            d = w.S / 4.0;
            U = Math.Max(2, (int)Math.Round(2 * d));
            Text = first ? "歡迎來到公仔櫃" : "公仔櫃・重新設定";
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false; MinimizeBox = false;
            ShowInTaskbar = true; TopMost = true;
            StartPosition = FormStartPosition.Manual;
            BackColor = Pix.Cream;
            DoubleBuffered = true;
            titleF = new Font("Microsoft JhengHei UI", 12f, FontStyle.Bold);
            qF = new Font("Microsoft JhengHei UI", 15f, FontStyle.Bold);
            bigF = new Font("Microsoft JhengHei UI", 13f, FontStyle.Bold);
            subF = new Font("Microsoft JhengHei UI", 9f, FontStyle.Bold);
            btnF = new Font("Microsoft JhengHei UI", 11f, FontStyle.Bold);
            ClientSize = new Size(Sc(580), Sc(520));
            KeyPreview = true;
            KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Escape) Close(); };
            LayoutBtns();
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

        bool InLineup(string id) { foreach (string x in Pal.LineupIds(lu)) if (x == id) return true; return false; }
        static string Members(string id)
        {
            List<string> names = new List<string>();
            foreach (string x in Pal.LineupIds(id)) names.Add(Pal.Get(x).Name);
            if (Pal.NormLineup(id) == Pal.Pikmin) names.Add("休息花");
            return string.Join("・", names.ToArray());
        }
        bool CanNext() { return step == 0 ? prof != "" : (step == 1 || mode == "shelf" || InLineup(pet)); }

        Btn Add(string id, string text, string sub, Rectangle r, int kind, bool on)
        {
            Btn b = new Btn();
            b.Id = id; b.Text = text; b.Sub = sub; b.R = r; b.Kind = kind; b.On = on;
            btns.Add(b);
            return b;
        }

        // 這一步有哪些按鈕、擺在哪
        void LayoutBtns()
        {
            btns.Clear();
            int W0 = ClientSize.Width, H0 = ClientSize.Height, top = Sc(154), bottom = H0 - Sc(72);
            if (step == 0)
            {
                int cw = Sc(220), ch = Sc(230), gap = Sc(28), x0 = (W0 - 2 * cw - gap) / 2;
                Add("student", "大學生", "上課・報告・期末考", new Rectangle(x0, top, cw, ch), 0, prof == "student");
                Add("work", "上班族", "上班・開會・準時下班", new Rectangle(x0 + cw + gap, top, cw, ch), 0, prof == "work");
            }
            else if (step == 1)
            {
                int n = Pal.Lineups.Length, gap = Sc(24), cw = Math.Min(Sc(240), (W0 - Sc(48) - (n - 1) * gap) / n), ch = bottom - top - Sc(8);
                int x0 = (W0 - n * cw - (n - 1) * gap) / 2;
                for (int i = 0; i < n; i++)
                {
                    string id = Pal.Lineups[i];
                    EnsurePics(id);
                    Add("lu:" + id, Pal.LineupName(id), Members(id), new Rectangle(x0 + i * (cw + gap), top, cw, ch), 0, lu == id);
                }
            }
            else
            {
                EnsurePics(lu);
                int cw = Sc(230), ch = Sc(116), gap = Sc(24), x0 = (W0 - 2 * cw - gap) / 2;
                Add("mode:shelf", lu == Pal.Pikmin ? "整櫃（三隻＋花）" : "整櫃（四隻）", lu == Pal.Pikmin ? "三隻皮克敏和休息花住在櫃子裡" : "四隻住在公仔櫃裡", new Rectangle(x0, top, cw, ch), 0, mode == "shelf");
                Add("mode:single", "只要一隻", "沒有櫃子，他住在蛋裡", new Rectangle(x0 + cw + gap, top, cw, ch), 0, mode == "single");
                if (mode == "single")
                {
                    string[] ids = Pal.LineupIds(lu);
                    int pw = Sc(100), pg = Sc(14), px0 = (W0 - ids.Length * pw - (ids.Length - 1) * pg) / 2, py = top + ch + Sc(34);
                    for (int i = 0; i < ids.Length; i++)
                        Add("pet:" + ids[i], Pal.Get(ids[i]).Name, "", new Rectangle(px0 + i * (pw + pg), py, pw, Math.Min(Sc(118), bottom - py - Sc(4))), 1, pet == ids[i]);
                }
            }
            int by = H0 - Sc(64), bh = Sc(44);
            if (step > 0) Add("back", "上一步", "", new Rectangle(Sc(30), by, Sc(130), bh), 2, false);
            else if (first) Add("skip", "以後再說", "", new Rectangle(Sc(30), by, Sc(130), bh), 2, false);
            Btn nx = Add("next", step < 2 ? "下一步" : "完成！", "", new Rectangle(W0 - Sc(30) - Sc(160), by, Sc(160), bh), 3, false);
            nx.Enabled = CanNext();
        }

        // 每一櫃：櫃子縮圖、每一隻的小照片（用預覽用的 World 畫，不開視窗）
        void EnsurePics(string id)
        {
            if (shelfPics.ContainsKey(id)) return;
            World pv = new World(Math.Max(3, (int)Math.Round(3 * d)), id);
            shelfPics[id] = pv.SetupShelfPic();
            foreach (Pet p in pv.Pets) petPics[id + ":" + p.P.Id] = p.IconPic();
        }

        Btn Find(string id) { foreach (Btn b in btns) if (b.Id == id) return b; return null; }
        Btn At(Point p) { foreach (Btn b in btns) if (b.R.Contains(p)) return b; return null; }

        // 按按鈕（滑鼠、測試用的 act setup <按鈕> 都走這裡）
        public void Press(string id)
        {
            Btn b = Find(id);
            if (b != null && !b.Enabled) return;
            if (id == "student" || id == "work") prof = id;
            else if (id.StartsWith("lu:")) { lu = Pal.NormLineup(id.Substring(3)); if (!InLineup(pet)) pet = ""; }
            else if (id == "mode:shelf") mode = "shelf";
            else if (id == "mode:single") { mode = "single"; if (!InLineup(pet)) pet = Pal.LineupIds(lu)[0]; }
            else if (id.StartsWith("pet:")) { pet = id.Substring(4); mode = "single"; }
            else if (id == "back") { if (step > 0) step--; }
            else if (id == "next") { if (step < 2) step++; else { w.ApplySetup(prof, lu, mode == "single", pet, first); Close(); return; } }
            else if (id == "skip" || id == "close") { Close(); return; }
            else return;
            LayoutBtns();
            hoverId = "";
            Invalidate();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            Btn b = At(e.Location);
            string h = b != null && b.Enabled ? b.Id : "";
            if (h != hoverId) { hoverId = h; Cursor = h != "" ? Cursors.Hand : Cursors.Default; Invalidate(); }
        }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); if (hoverId != "") { hoverId = ""; Invalidate(); } }
        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (e.Button != MouseButtons.Left) return;
            Btn b = At(e.Location);
            if (b != null) Press(b.Id);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.None;
            int W0 = ClientSize.Width, H0 = ClientSize.Height, F = 4 * U, crown = Sc(56);
            Pix.Wood(g, 0, 0, W0, H0, U, false, 11);
            Pix.Panel(g, F, crown, W0 - 2 * F, H0 - crown - F, U, false);
            // 頂上的銅牌＋兩邊小愛心
            string t = first ? "歡迎來到公仔櫃！" : "公仔櫃・重新設定";
            int tw = Pix.TextW(t, titleF), plw = tw + 14 * U, plh = Sc(34);
            Rectangle pr = new Rectangle((W0 - plw) / 2, (crown - plh) / 2 + U / 2, plw, plh);
            Pix.Plate(g, t, titleF, pr, U);
            Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.X - 9 * U, pr.Y + plh / 2 - 2 * U, U);
            Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.Right + 4 * U, pr.Y + plh / 2 - 2 * U, U);
            Steps(g, W0, Sc(68));
            string q = step == 0 ? "你是？" : (step == 1 ? "選一櫃公仔" : "怎麼擺？");
            string hint = step == 0 ? "公仔們會照你的生活陪你（之後在小屋可以改）" : (step == 1 ? "每一櫃都很可愛，之後隨時能換" : (mode == "single" ? "選一隻，他會住在右下角的蛋裡" : "公仔櫃放在右下角，點格子就叫他們出來"));
            TextRenderer.DrawText(g, q, qF, new Rectangle(0, Sc(100), W0, Sc(30)), Pix.TextC, Pix.Mid);
            TextRenderer.DrawText(g, hint, subF, new Rectangle(0, Sc(130), W0, Sc(18)), Pix.C(0x9A6338), Pix.Mid);
            if (step == 2 && mode == "single")
            {
                Btn first2 = Find("mode:shelf");
                if (first2 != null) TextRenderer.DrawText(g, "選哪一隻？", btnF, new Rectangle(0, first2.R.Bottom + Sc(6), W0, Sc(26)), Pix.TextC, Pix.Mid);
            }
            foreach (Btn b in btns) DrawBtn(g, b);
        }

        // 上面的三個步驟：現在這步黃色、做完的綠色打勾
        void Steps(Graphics g, int W0, int y)
        {
            string[] names = { "你是？", "選一櫃", "怎麼擺" };
            int pw = Sc(112), ph = Sc(26), gap = Sc(18), x0 = (W0 - 3 * pw - 2 * gap) / 2;
            for (int i = 0; i < 3; i++)
            {
                int x = x0 + i * (pw + gap);
                if (i > 0) for (int sx = x - gap + U; sx + U <= x - U; sx += 2 * U) Pix.Box(g, Pix.C(0xD8BF94), sx, y + ph / 2 - U / 2, U, U);
                Pix.Round(g, i == step ? Pix.C(0x8A5A2A) : Pix.C(0xC9B08A), x, y, pw, ph, U);
                Pix.Box(g, i == step ? Pix.C(0xF6C453) : (i < step ? Pix.C(0xD9F0C4) : Pix.C(0xF3EADB)), x + U, y + U, pw - 2 * U, ph - 2 * U);
                string s = (i + 1) + ". " + names[i];
                int sw = Pix.TextW(s, subF), cx = x + (pw - sw) / 2;
                if (i < step) { cx += 3 * U; Pix.Mono(g, Pix.CHECK, Pix.C(0x3F8A30), cx - 7 * U, y + ph / 2 - 3 * U, U); }
                TextRenderer.DrawText(g, s, subF, new Rectangle(cx, y, sw + 4, ph), i <= step ? Pix.TextC : Pix.Dim, Pix.LeftMid);
            }
        }

        void DrawBtn(Graphics g, Btn b)
        {
            Rectangle r = b.R;
            bool hot = b.Id == hoverId && b.Enabled;
            if (b.Kind >= 2)
            {
                // 下面的按鈕：有厚度的像素按鈕（主要按鈕是蜂蜜色）
                Color face = !b.Enabled ? Pix.C(0xE9E0D0) : (b.Kind == 3 ? (hot ? Pix.C(0xFFD36A) : Pix.C(0xF6C453)) : (hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0)));
                Color shade = !b.Enabled ? Pix.C(0xD3C7B2) : (b.Kind == 3 ? Pix.C(0xC8902C) : Pix.C(0xDCC6A2));
                Pix.Round(g, !b.Enabled ? Pix.C(0xBBA98C) : Pix.Ink, r.X, r.Y, r.Width, r.Height, U);
                Pix.Box(g, face, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
                Pix.Box(g, shade, r.X + U, r.Bottom - 3 * U, r.Width - 2 * U, 2 * U);
                if (b.Enabled) Pix.Box(g, Pix.Mix(face, Color.White, 0.6), r.X + 2 * U, r.Y + U, r.Width - 4 * U, U);
                int tw = Pix.TextW(b.Text, btnF), ax = 7 * U, tx = r.X + (r.Width - tw - (b.Id == "back" || b.Id == "next" ? ax : 0)) / 2, cy = r.Y + (r.Height - 2 * U) / 2;
                Color tc = b.Enabled ? Pix.TextC : Pix.Dim;
                if (b.Id == "back") { Arrow(g, tx + U, cy, -1, tc); tx += ax; }
                TextRenderer.DrawText(g, b.Text, btnF, new Rectangle(tx, r.Y, tw + 4, r.Height - 2 * U), tc, Pix.LeftMid);
                if (b.Id == "next" && step < 2) Arrow(g, tx + tw + 2 * U, cy, 1, tc);
                return;
            }
            // 卡片：底下一層影子；選到的是金色粗框、右上角綠色勾勾
            Color edge = b.On ? Pix.C(0xC08A2C) : Pix.C(0x8A6A4A);
            Color fill = b.On ? Pix.C(0xFFEDB8) : (hot ? Pix.C(0xFFF6DE) : Pix.C(0xFFFDF7));
            Pix.Round(g, Pix.C(0xE6D3B0), r.X + 2 * U, r.Y + 2 * U, r.Width, r.Height, U);
            Pix.Round(g, edge, r.X, r.Y, r.Width, r.Height, U);
            int ins = b.On ? 2 * U : U;
            if (b.On) Pix.Box(g, edge, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            Pix.Box(g, fill, r.X + ins, r.Y + ins, r.Width - 2 * ins, r.Height - 2 * ins);
            if (hot && !b.On) Pix.Box(g, Pix.C(0xF6C453), r.X + ins, r.Bottom - ins - U, r.Width - 2 * ins, U);
            if (b.Kind == 1) DrawPetCard(g, b);
            else if (b.Id == "student" || b.Id == "work") DrawIconCard(g, b, b.Id == "student" ? STUDENT : WORK);
            else if (b.Id.StartsWith("lu:")) DrawShelfCard(g, b, b.Id.Substring(3));
            else DrawModeCard(g, b);
            if (b.On)
            {
                int s = 9 * U, bx = r.Right - s - 2 * U, by2 = r.Y + 2 * U;
                Pix.Round(g, Pix.C(0x2F6E24), bx, by2, s, s, U);
                Pix.Box(g, Pix.C(0x5FB04A), bx + U, by2 + U, s - 2 * U, s - 2 * U);
                Pix.Mono(g, Pix.CHECK, Color.White, bx + 2 * U, by2 + 2 * U, U);
            }
        }

        void Arrow(Graphics g, int x, int cy, int dir, Color c)
        {
            for (int i = 0; i < 3; i++)
            {
                int col = dir > 0 ? x + i * U : x + (2 - i) * U;
                Pix.Box(g, c, col, cy - (2 - i) * U - U / 2, U, (2 - i) * 2 * U + U);
            }
        }

        Dictionary<char, Color> IconPal()
        {
            Dictionary<char, Color> p = new Dictionary<char, Color>();
            p['k'] = Pix.Ink; p['d'] = Pix.C(0x3D4A6B); p['D'] = Pix.C(0x2C3550); p['Y'] = Pix.C(0xF2C14E);
            p['w'] = Pix.C(0xFFFDF7); p['l'] = Pix.C(0xA9B8D0); p['b'] = Pix.C(0xA0643A); p['B'] = Pix.C(0xC8844E); p['s'] = Pix.C(0x7E4A28);
            return p;
        }

        void DrawIconCard(Graphics g, Btn b, string[] art)
        {
            Rectangle r = b.R;
            int c = Math.Max(3, Sc(6)), aw = art[0].Length * c;
            Pix.Art(g, art, IconPal(), r.X + (r.Width - aw) / 2, r.Y + Sc(26), c);
            TextRenderer.DrawText(g, b.Text, bigF, new Rectangle(r.X, r.Y + Sc(140), r.Width, Sc(32)), Pix.TextC, Pix.Mid);
            TextRenderer.DrawText(g, b.Sub, subF, new Rectangle(r.X, r.Y + Sc(174), r.Width, Sc(22)), Pix.C(0x9A6338), Pix.Mid);
        }

        void DrawShelfCard(Graphics g, Btn b, string id)
        {
            Rectangle r = b.R;
            Bitmap pic;
            int textY = r.Y + Sc(12);
            if (shelfPics.TryGetValue(id, out pic))
            {
                int avail = r.Height - Sc(72), ph = Math.Min(pic.Height, avail), pw = pic.Width * ph / pic.Height;
                g.DrawImage(pic, r.X + (r.Width - pw) / 2, r.Y + Sc(12), pw, ph);
                textY = r.Y + Sc(16) + ph;
            }
            TextRenderer.DrawText(g, b.Text, bigF, new Rectangle(r.X, textY, r.Width, Sc(30)), Pix.TextC, Pix.Mid);
            TextRenderer.DrawText(g, b.Sub, subF, new Rectangle(r.X + Sc(6), textY + Sc(28), r.Width - Sc(12), Sc(38)), Pix.C(0x9A6338), TextFormatFlags.HorizontalCenter | TextFormatFlags.Top | TextFormatFlags.WordBreak | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);   // 四櫃並排時名單換行，不要被切掉
        }

        void DrawModeCard(Graphics g, Btn b)
        {
            Rectangle r = b.R;
            int iconW = Sc(76), ix = r.X + Sc(14);
            if (b.Id == "mode:shelf")
            {
                Bitmap pic;
                if (shelfPics.TryGetValue(lu, out pic))
                {
                    int ph = r.Height - Sc(24), pw = pic.Width * ph / pic.Height;
                    InterpolationMode im = g.InterpolationMode;
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.DrawImage(pic, ix + (iconW - pw) / 2, r.Y + Sc(12), pw, ph);
                    g.InterpolationMode = im;
                }
            }
            else
            {
                Dictionary<char, Color> pal = new Dictionary<char, Color>();
                pal['k'] = Pix.C(0x6B4A2E); pal['c'] = Pix.C(0xFFF4DC); pal['s'] = Pix.C(0xE8D3B0); pal['h'] = Color.White;
                pal['r'] = Pix.C(0xD84A4A); pal['o'] = Pix.C(0xE7836A); pal['b'] = Pix.C(0x3D6BB3); pal['g'] = Pix.C(0x25B3BA); pal['Y'] = Pix.C(0xF5C842);
                int c = Math.Max(2, Sc(4)), ew = ShelfForm.EGG[0].Length * c, eh = ShelfForm.EGG.Length * c;
                Pix.Art(g, ShelfForm.EGG, pal, ix + (iconW - ew) / 2, r.Y + (r.Height - eh) / 2, c);
            }
            int tx = ix + iconW + Sc(8);
            TextRenderer.DrawText(g, b.Text, bigF, new Rectangle(tx, r.Y + r.Height / 2 - Sc(30), r.Right - tx - Sc(8), Sc(30)), Pix.TextC, Pix.LeftMid);
            TextRenderer.DrawText(g, b.Sub, subF, new Rectangle(tx, r.Y + r.Height / 2 + Sc(2), r.Right - tx - Sc(8), Sc(22)), Pix.C(0x9A6338), Pix.LeftMid);
        }

        void DrawPetCard(Graphics g, Btn b)
        {
            Rectangle r = b.R;
            Bitmap pic;
            int nameH = Sc(24);
            if (petPics.TryGetValue(lu + ":" + b.Id.Substring(4), out pic))
            {
                int avail = r.Height - nameH - Sc(8), ph = Math.Min(pic.Height, avail), pw = pic.Width * ph / pic.Height;
                g.DrawImage(pic, r.X + (r.Width - pw) / 2, r.Y + Sc(6) + (avail - ph), pw, ph);
            }
            TextRenderer.DrawText(g, b.Text, btnF, new Rectangle(r.X, r.Bottom - nameH - Sc(4), r.Width, nameH), Pix.TextC, Pix.Mid);
        }
    }
}
