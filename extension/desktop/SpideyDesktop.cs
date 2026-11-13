// Spidey 桌面版：整個螢幕亂跑的像素小蜘蛛人。
// 獨立程式（開機自動啟動、整台電腦都有他）；睡覺／休息提醒看整台電腦的鍵盤滑鼠。
// VS Code 擴充套件若有開，透過 named pipe 多送 save / errors / hi / config / quit。
// 平日 18:00～隔天 06:00 黑化（黑色戰衣＋催下班）。
// 刻意寫成 C# 5（PowerShell 5.1 Add-Type 的編譯器），不用 $"" / ?. / => 成員。
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

namespace SpideyDesktop
{
    public static class App
    {
        [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
        static int logged;

        public static void Log(string s)
        {
            if (logged++ > 60) return;
            try { File.AppendAllText(Path.Combine(Path.GetTempPath(), "spidey-desktop.log"), DateTime.Now.ToString("s") + " " + s + Environment.NewLine); }
            catch { }
        }

        public static void Run(string pipeName)
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
                    Application.Run(new PetForm(pipeName));
                }
                catch (Exception ex) { Log("fatal: " + ex); }
            }
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

        // 一次完成「移動＋改大小＋換畫面」，不會有拉伸的中間畫面（舊做法會把藍色衣服拉成粗條）
        public static void Present(Form f, Bitmap bmp, int x, int y)
        {
            IntPtr screen = GetDC(IntPtr.Zero), mem = CreateCompatibleDC(screen);
            IntPtr hb = bmp.GetHbitmap(Color.FromArgb(0)), old = SelectObject(mem, hb);
            try
            {
                POINT pos = new POINT(x, y), src = new POINT(0, 0);
                SIZE size = new SIZE(bmp.Width, bmp.Height);
                BLENDFUNCTION bl = new BLENDFUNCTION();
                bl.SourceConstantAlpha = 255; bl.AlphaFormat = 1; // AC_SRC_ALPHA
                if (!UpdateLayeredWindow(f.Handle, screen, ref pos, ref size, mem, ref src, 0, ref bl, 2)) // ULW_ALPHA
                    App.Log("ULW failed err=" + Marshal.GetLastWin32Error() + " ex=0x" + GetWindowLong(f.Handle, -20).ToString("X") + " size=" + size.CX + "x" + size.CY);
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
            if (DwmGetWindowAttribute(h, 9, out r, 16) == 0) return true; // DWMWA_EXTENDED_FRAME_BOUNDS：實際看得到的框
            return GetWindowRect(h, out r);
        }
        public static void KeepOnTop(Form f)
        {
            if (f.IsHandleCreated && f.Visible) SetWindowPos(f.Handle, TOPMOST, 0, 0, 0, 0, NOSIZE | NOMOVE | NOACTIVATE);
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
        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x80 | 0x08000000 | 0x8; // TOOLWINDOW | NOACTIVATE | TOPMOST
                if (clickThrough) cp.ExStyle |= 0x20 | 0x80000; // TRANSPARENT | LAYERED
                if (perPixel) cp.ExStyle |= 0x80000;              // LAYERED（UpdateLayeredWindow 用）
                return cp;
            }
        }
    }

    class BubbleForm : OverlayForm
    {
        readonly Font font = new Font("Microsoft JhengHei UI", 10f, FontStyle.Bold);
        string text = "";
        bool alert, dark;
        public BubbleForm() : base(true) { }

        public Size Measure(string s, bool a, bool d)
        {
            if (s != text || a != alert || d != dark) { text = s; alert = a; dark = d; Invalidate(); }
            Size ts = TextRenderer.MeasureText(s, font, new Size(4000, 400), TextFormatFlags.NoPadding);
            return new Size(ts.Width + 22, ts.Height + 12 + 7);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(KEY);
            int w = ClientSize.Width, h = ClientSize.Height - 7;
            Color line = alert ? Color.FromArgb(0xC9, 0x54, 0x54) : (dark ? Color.FromArgb(0x7B, 0x6B, 0xC4) : Color.FromArgb(0x2A, 0x2F, 0x45));
            Color fg = alert ? (dark ? Color.FromArgb(0xFF, 0x8A, 0x8A) : Color.FromArgb(0xA8, 0x32, 0x32)) : (dark ? Color.FromArgb(0xEE, 0xEB, 0xF8) : Color.FromArgb(0x2A, 0x2F, 0x45));
            Brush fill = dark ? (Brush)new SolidBrush(Color.FromArgb(0x16, 0x17, 0x1F)) : Brushes.White;
            using (SolidBrush lb = new SolidBrush(line))
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
            TextRenderer.DrawText(g, text, font, new Rectangle(0, 0, w, h), fg,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }
    }

    // 右下角的「窩」（困龍區）：拖進來他就只在裡面活動
    // 右下角的窩：一張張在「右牆」和「地板」之間的圓網（參考真實圓網：框絲、放射絲、中心加固圈、空白區、捕捉螺旋、露珠）
    // 用 UpdateLayeredWindow 逐像素透明，絲線平滑半透明。
    // 背後那層：框絲＋放射絲＋中心（沒鎖時連捕捉螺旋一起畫）；前面那層：鎖住時，捕捉螺旋由外往內織到他前面。
    class NestForm : OverlayForm
    {
        public bool Hot, Over, Dark, Dirty = true;
        public double Lock;           // 0～1：前面那層螺旋織到哪
        readonly double k;
        readonly bool netOnly;
        Rectangle area;
        Bitmap bmp;

        public NestForm(double k, bool netOnly) : base(true, true) { this.k = k; this.netOnly = netOnly; }

        protected override void OnPaint(PaintEventArgs e) { }
        protected override void OnPaintBackground(PaintEventArgs e) { }

        public void Sync(Rectangle a)
        {
            if (a == area && !Dirty) return;
            area = a; Dirty = false;
            if (bmp == null || bmp.Width != a.Width || bmp.Height != a.Height)
            {
                if (bmp != null) bmp.Dispose();
                bmp = new Bitmap(Math.Max(1, a.Width), Math.Max(1, a.Height), PixelFormat.Format32bppArgb);
            }
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.Transparent);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                Draw(g, a.Width, a.Height);
            }
            W.Present(this, bmp, a.X, a.Y);
        }

        // ---- 幾何：四分之一橢圓的框（中心在螢幕角落），網心偏向角落 ----
        double cx, cy, rx, ry, hx, hy;
        double[] ang, len;

        void Build(int w, int h)
        {
            cx = w - 1; cy = h - 1; rx = w * 0.97; ry = h * 0.95;
            hx = w * 0.68; hy = h * 0.64;
            Random r = new Random(7); // 固定種子：每次長得一樣，但帶一點不規則
            int n = 22;
            ang = new double[n]; len = new double[n];
            for (int i = 0; i < n; i++)
            {
                ang[i] = Math.PI * 2 * i / n + (r.NextDouble() - 0.5) * 0.12;
                len[i] = RayLen(Math.Cos(ang[i]), Math.Sin(ang[i]));
            }
        }

        // 從網心往 (dx,dy) 射出，碰到「右牆／地板／外框弧」的距離
        double RayLen(double dx, double dy)
        {
            double best = 1e9;
            if (dx > 1e-6) best = Math.Min(best, (cx - hx) / dx);
            if (dy > 1e-6) best = Math.Min(best, (cy - hy) / dy);
            double px = (hx - cx) / rx, py = (hy - cy) / ry, qx = dx / rx, qy = dy / ry;
            double A = qx * qx + qy * qy, B = 2 * (px * qx + py * qy), Cc = px * px + py * py - 1;
            double disc = B * B - 4 * A * Cc;
            if (disc >= 0) { double t = (-B + Math.Sqrt(disc)) / (2 * A); if (t > 0) best = Math.Min(best, t); }
            return Math.Max(4, best - 1.5);
        }

        PointF At(int i, double d) { return new PointF((float)(hx + Math.Cos(ang[i]) * d), (float)(hy + Math.Sin(ang[i]) * d)); }

        // 兩點之間微微往網心下垂的絲
        static void Sag(Graphics g, Pen p, PointF a, PointF b, double hx, double hy, float amt)
        {
            PointF m = new PointF((a.X + b.X) / 2, (a.Y + b.Y) / 2);
            m = new PointF(m.X + ((float)hx - m.X) * amt, m.Y + ((float)hy - m.Y) * amt);
            g.DrawBezier(p, a, new PointF((a.X + 2 * m.X) / 3, (a.Y + 2 * m.Y) / 3), new PointF((b.X + 2 * m.X) / 3, (b.Y + 2 * m.Y) / 3), b);
        }

        void Draw(Graphics g, int w, int h)
        {
            Build(w, h);
            int n = ang.Length;
            Color silkC = Over ? Color.FromArgb(240, 255, 120, 165) : (Hot ? Color.FromArgb(235, 255, 175, 200)
                : (Dark ? Color.FromArgb(225, 214, 204, 255) : Color.FromArgb(235, 255, 255, 255)));
            Color shadeC = Dark ? Color.FromArgb(110, 30, 20, 60) : Color.FromArgb(95, 50, 60, 90);
            float wR = (float)Math.Max(1.1, 1.25 * k), wS = (float)Math.Max(0.9, 0.95 * k);
            using (Pen shR = new Pen(shadeC, wR + 1.4f), siR = new Pen(silkC, wR))
            using (Pen shS = new Pen(shadeC, wS + 1.2f), siS = new Pen(silkC, wS))
            {
                Pen[] radial = { shR, siR }, spiral = { shS, siS };
                // 兩次：先畫一層淡陰影，再畫銀白絲 → 深色、淺色背景都看得到
                for (int pass = 0; pass < 2; pass++)
                {
                    if (!netOnly)
                    {
                        // 框絲：沿著放射絲的端點連成的弧（貼牆、貼地的那幾段省略）
                        for (int i = 0; i < n; i++)
                        {
                            int j = (i + 1) % n;
                            PointF a = At(i, len[i]), b = At(j, len[j]);
                            bool onEdge = (a.X >= cx - 3 && b.X >= cx - 3) || (a.Y >= cy - 3 && b.Y >= cy - 3);
                            if (!onEdge) Sag(g, radial[pass], a, b, hx, hy, 0.03f);
                        }
                        // 放射絲
                        for (int i = 0; i < n; i++) g.DrawLine(radial[pass], At(i, 0), At(i, len[i]));
                        // 中心加固圈（約五圈）
                        for (int ring = 1; ring <= 5; ring++)
                        {
                            double d = (2.2 + ring * 2.0) * k;
                            for (int i = 0; i < n; i++) { int j = (i + 1) % n; g.DrawLine(spiral[pass], At(i, Math.Min(d, len[i])), At(j, Math.Min(d, len[j]))); }
                        }
                    }
                    // 捕捉螺旋：從外往內一圈圈（鎖住時在前面那層畫、帶動畫；沒鎖時畫在背後那層）
                    bool drawSpiral = netOnly ? Lock > 0.001 : Lock <= 0.001;
                    if (drawSpiral) DrawSpiral(g, spiral[pass], netOnly ? Lock : 1, pass == 1);
                }
            }
            if (Over && !netOnly)
            {
                Heart(g, (int)(w * 0.42), (int)(h * 0.30), Math.Max(2, (int)(2 * k)), Color.FromArgb(255, 255, 111, 156));
                Heart(g, (int)(w * 0.70), (int)(h * 0.18), Math.Max(1, (int)(1.4 * k)), Color.FromArgb(255, 255, 143, 176));
            }
        }

        void DrawSpiral(Graphics g, Pen p, double prog, bool dew)
        {
            int n = ang.Length;
            const double f0 = 0.30, f1 = 0.96; // 中間留空白區，外圈貼近框
            int turns = 12;
            int total = turns * n;
            int shown = (int)Math.Ceiling(total * Math.Max(0, Math.Min(1, prog)));
            Random r = new Random(11);
            using (SolidBrush drop = new SolidBrush(Color.FromArgb(235, 255, 255, 255)), drop2 = new SolidBrush(Color.FromArgb(150, 120, 170, 230)))
                for (int s0 = 0; s0 < shown; s0++)
                {
                    // 由外往內：s0=0 是最外圈
                    int s = total - 1 - s0;
                    int i = s % n, j = (i + 1) % n;
                    double fa = f0 + (f1 - f0) * s / (double)total, fb = f0 + (f1 - f0) * (s + 1) / (double)total;
                    PointF a = At(i, len[i] * fa), b = At(j, len[j] * fb);
                    Sag(g, p, a, b, hx, hy, 0.035f);
                    if (dew && r.NextDouble() < 0.10)
                    {
                        float rr = (float)((1.1 + r.NextDouble() * 0.9) * k);
                        g.FillEllipse(drop2, a.X - rr - 0.6f, a.Y - rr - 0.6f, 2 * rr + 1.2f, 2 * rr + 1.2f);
                        g.FillEllipse(drop, a.X - rr, a.Y - rr, 2 * rr, 2 * rr);
                    }
                }
        }

        static void Heart(Graphics g, int x, int y, int q, Color c)
        {
            string[] H = { ".pp.pp.", "ppppppp", "ppppppp", ".ppppp.", "..ppp..", "...p..." };
            using (SolidBrush b = new SolidBrush(c))
                for (int r = 0; r < H.Length; r++)
                    for (int i = 0; i < H[r].Length; i++)
                        if (H[r][i] == 'p') g.FillRectangle(b, x + i * q, y + r * q, q, q);
        }
    }

    // 接球用的小球（點得到：點一下就把球丟出去）
    class BallForm : OverlayForm
    {
        public event Action Kicked;
        readonly int ps;
        static readonly string[] ART = { "..kkkk..", ".kTTTTk.", "kTTWTTTk", "kTWTTTTk", "kTTTTWTk", "kTTTWTTk", ".kTTTTk.", "..kkkk.." };
        readonly SolidBrush bk = new SolidBrush(Color.FromArgb(0x2A, 0x2F, 0x45)), bt = new SolidBrush(Color.FromArgb(0xD9, 0xE8, 0x4A)), bw = new SolidBrush(Color.White);
        public BallForm(int ps) : base(false) { this.ps = ps; Size = new Size(8 * ps, 8 * ps); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(KEY);
            for (int r = 0; r < 8; r++)
                for (int i = 0; i < 8; i++)
                {
                    char c = ART[r][i];
                    if (c == '.') continue;
                    g.FillRectangle(c == 'k' ? bk : (c == 'T' ? bt : bw), i * ps, r * ps, ps, ps);
                }
        }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Left && Kicked != null) Kicked();
        }
    }

    // 上版煙火（蓋住一整個螢幕、點得穿）
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

        public void Start(Rectangle area)
        {
            Bounds = area;
            parts.Clear(); plan.Clear(); t = 0; Active = true;
            for (int i = 0; i < 10; i++)
                plan.Add(new double[] { 0.32 * i + R(0, 0.2), R(0.12, 0.88) * area.Width, R(0.12, 0.45) * area.Height, rnd.Next(cols.Length) });
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

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.Clear(KEY);
            foreach (double[] p in parts)
            {
                bool fading = p[7] == 1 && p[4] > p[5] * 0.7;
                if (fading && Math.Floor(p[4] * 24) % 2 == 0) continue; // 快消失時閃爍
                // 十字星形火花，前半段大、後半段小
                int q = (int)Math.Max(2, (p[7] == 0 || p[4] < p[5] * 0.45 ? 2.4 : 1.5) * k);
                int px = (int)p[0], py = (int)p[1];
                SolidBrush b = cols[(int)p[6]];
                g.FillRectangle(b, px - q / 2, py - q / 2 - q, q, 3 * q);
                g.FillRectangle(b, px - q / 2 - q, py - q / 2, 3 * q, q);
            }
        }
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
                        // 往角落微微下垂，比較像網
                        PointF m = new PointF((a.X + b.X) / 2 + (ox - (a.X + b.X) / 2) * 0.12f, (a.Y + b.Y) / 2 * 0.88f);
                        g.DrawLine(p, a, m);
                        g.DrawLine(p, m, b);
                    }
            }
        }
    }

    class PetForm : OverlayForm
    {
        // ---- 像素圖（跟側邊欄版同一隻）----
        static readonly string[] HEAD = { "...kkkkkk...", "..krrrrrrk..", ".krRrrrrRrk.", ".krrrRRrrrk.", ".kwwkrrkwwk.", ".kwwwkkwwwk.", ".krwwrrwwrk.", "..krrRRrrk.." };
        static readonly string[] SLEEPY = { ".krrrrrrrrk.", ".kkkkrrkkkk.", ".krrrrrrrrk." };
        static readonly string[] HAPPY = { ".krkrrrrkrk.", ".kkrkrrkrkk.", ".kprrrrrrpk." };
        static readonly string[] DIZZY = { ".kkwkrrkwkk.", ".kwkwkkwkwk.", ".kkwkrrkwkk." };
        static readonly string[] STAR = { ".y.", "yyy", ".y." };
        // 配件（12 格寬的格線座標）
        static readonly string[] SCARF = { "..YYYYYYYY..", "......YY....", "......Y....." };
        static readonly string[] BEANIE = { ".....WW.....", "....PPPP....", "...PPPPPP...", "..WWWWWWWW.." };
        static readonly string[] CROWN = { "...Y.YY.Y...", "...YYYYYY...", "...YPYYPY..." };
        static readonly string[] SANTA = { "........WW..", ".....SSSS...", "....SSSSSS..", "...WWWWWWWW." };
        static readonly string[] GLASSES = { "..P.P..P.P..", "..PPPkkPPP..", "...P....P..." };
        static readonly string[] ENVELOPE = { "SSS", "SYS", "SSS", "SSS" };
        static readonly string[] CAKE = { ".Y..", "PPPP", "WWWW", "PPPP" };
        static readonly string[] FLAKE = { ".B.", "BBB", ".B." };
        static readonly int[] LV = { 0, 0, 15, 50, 120, 250, 500 };       // Lv1..Lv6 需要的好感度
        static readonly string[] UNLOCK = { "", "", "黃圍巾", "小毛帽", "愛心眼鏡", "金色胸章", "小皇冠" };
        static readonly string[] PATS_HI = { "能遇到你真好", "我最喜歡你了 ♥", "今天也要一起喔", "有你在，每天都很開心", "我們是最佳拍檔！" };
        static readonly string[] BODY = { "...kkkkkk...", "..kbrrrrbk..", ".kbbrkkrbbk.", ".krbrrrrbrk.", "..kbbbbbbk.." };
        static readonly string[] ARMS_UP = { "kr.kkkkkk.rk", "kbkbrrrrbkbk", ".kbbrkkrbbk.", "..kbrrrrbk..", "..kbbbbbbk.." };
        static readonly string[] ARMS_HUG = { "...kkkkkk...", ".kkbrrrrbkk.", "krrrkkkkrrrk", ".kkbrrrrbkk.", "..kbbbbbbk.." };
        static readonly string[] LEGS_A = { "..kbbkkbbk..", "..krrkkrrk..", "..kkk..kkk.." };
        static readonly string[] LEGS_B = { "..kbbkkbbk..", ".krrk..krrk.", ".kkk....kkk." };
        static readonly string[] HEART = { ".pp.pp.", "ppppppp", "ppppppp", ".ppppp.", "..ppp..", "...p..." };
        static readonly string[] ZZ = { "kkkk", "..k.", ".k..", "kkkk" };

        static readonly string[] TALK = { "嗨！今天也一起寫 code 吧", "能力越強，bug 越少！", "蜘蛛感應：你存檔了嗎？", "要不要喝口水？", "整個螢幕都是我的地盤！", "這個視窗頂端風景不錯", "Thwip! 🕸" };
        static readonly string[] SAVE = { "存好了！👍", "存檔成功，帥！", "Thwip! 已存檔", "穩穩的 👍" };
        // 點他：情緒價值
        static readonly string[] PATS = { "你今天也很棒！", "累了就休息一下，我陪你", "有我在，bug 不敢來", "我一直都在喔 ♥", "你寫的 code 很帥",
            "辛苦了，摸摸頭", "不管怎樣我都站你這邊", "今天也謝謝你陪我", "慢慢來，你可以的", "嘿嘿，再摸一下", "你笑起來一定很好看", "有你在我就很安心" };
        static readonly string[] PATS_D = { "……摸夠了就下班。", "我是擔心你才一直催你。", "你已經很努力了，剩下的明天再說。", "回家好好吃飯，聽到沒？",
            "哼，就讓你摸一下。", "我不是在撒嬌，是在叫你下班。" };
        static readonly string[] HUGS = { "抱抱～", "給你一個蜘蛛抱抱 ♥", "辛苦了，抱一下", "(つ´ω`)つ ♥" };
        static readonly string[] KNOCK = { "叩叩！你在看我嗎？👀", "嘿～螢幕外面的你！", "我可以出去玩嗎？叩叩", "你今天也很努力喔！" };
        // 黑化（平日下班後）台詞
        static readonly string[] TALK_D = { "都幾點了還不下班？", "老闆不會多給你加班費的。", "……你還在？", "這個 bug 明天還會在，你不用在。", "下班。現在。", "你的床在等你。我也在等你關機。" };
        static readonly string[] SAVE_D = { "存了就快走。", "存好了。可以關機了吧？", "……存檔。然後下班。" };
        static readonly string[] HUGS_D = { "……只抱一下。然後下班。", "抱完就回家，聽到沒？", "(つ﹏⊂) 回家啦" };
        static readonly string[] KNOCK_D = { "叩、叩。下班了沒？", "我在螢幕裡面都看到了，你還在加班。", "再不關機我要黑掉你的螢幕喔（騙你的）" };
        static readonly string[] NEWWIN_D = { "又開新視窗？想加班？", "……這個也明天再看。", "不准再開了。" };
        static readonly string[] NEWWIN = { "新視窗！Thwip!", "我來看看這是什麼～", "噴個絲黏上去！" };

        readonly string pipeName;
        readonly int S, SW, SH;
        readonly double k;
        readonly Random rnd = new Random();
        readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
        readonly Stopwatch clock = Stopwatch.StartNew();
        readonly Dictionary<char, SolidBrush> br = new Dictionary<char, SolidBrush>();
        readonly SolidBrush halo = new SolidBrush(Color.White);
        readonly BubbleForm bubbleForm = new BubbleForm();
        readonly List<CobwebForm> webs = new List<CobwebForm>();
        readonly List<Client> clients = new List<Client>();
        readonly List<double[]> hearts = new List<double[]>(); // {x 偏移, 年齡}

        Screen[] screens = Screen.AllScreens;
        List<WinInfo> wins = new List<WinInfo>();                      // 所有看得到的視窗，前面的在前
        Dictionary<IntPtr, WinInfo> cands = new Dictionary<IntPtr, WinInfo>(); // 夠大、有標題的「正經視窗」
        List<Plat> plats = new List<Plat>();                            // 可以站的視窗頂端（扣掉被擋住的段）
        HashSet<IntPtr> known;

        double lastT, nextScan, cursorStill, seekCd = 20, hoverCd, newWinCd = 3, fgCd = 8, lateCd = 120;
        IntPtr lastFg;
        bool dark, sysIdle;
        int darkChecked = -1;
        double restMin = 50, idleMin = 5, sessionStart;
        readonly Dictionary<char, SolidBrush> brDark = new Dictionary<char, SolidBrush>();
        readonly SolidBrush haloDark = new SolidBrush(Color.FromArgb(0xC8, 0xC0, 0xEC));
        double sc = 1, gt, knock;            // 敲螢幕：放大倍率、計時、敲的晃動
        string afterGlass = "";
        Point lastCursor;
        bool hidden, closing, sleepMode;

        // ---- 寵物狀態 ----
        double x, y, vx, vy, t, anim, sense, z;
        int dir = 1;
        string state = "air";
        double ax, ay, L, th, om;            // 絲的錨點／擺盪
        double targetL; int hangPhase;       // 倒吊
        int wallSide, climbDir;              // 爬牆
        double shootT; string nextAct = ""; IntPtr zipH; bool zipRight; // 噴絲
        double seekX;
        IntPtr supH; int supL, supR, supWinL; // 正站在哪個視窗上（Zero＝螢幕底）
        bool goClimb;
        string bubble = ""; double bt; bool bubbleAlert;
        bool dragging, dragSaid; Point dragStart; double grabDx, grabDy, dragMoved, lastMx, lastMy, lastMt, dvx, dvy;

        public PetForm(string pipeName) : base(false, true)
        {
            this.pipeName = pipeName;
            float dpi = 96;
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) dpi = g.DpiX;
            S = Math.Max(3, (int)Math.Round(4 * dpi / 96.0));
            k = S / 3.0;
            SW = 12 * S; SH = 16 * S;
            br['k'] = new SolidBrush(Color.FromArgb(0x2A, 0x2F, 0x45));
            br['r'] = new SolidBrush(Color.FromArgb(0xD8, 0x4A, 0x4A));
            br['R'] = new SolidBrush(Color.FromArgb(0xA8, 0x3A, 0x3A));
            br['b'] = new SolidBrush(Color.FromArgb(0x3D, 0x5F, 0xAE));
            br['w'] = new SolidBrush(Color.White);
            br['p'] = new SolidBrush(Color.FromArgb(0xFF, 0x6F, 0x9C));
            br['y'] = new SolidBrush(Color.FromArgb(0xFF, 0xD8, 0x4A));
            foreach (Dictionary<char, SolidBrush> pal in new Dictionary<char, SolidBrush>[] { br, brDark })
            {
                pal['S'] = new SolidBrush(Color.FromArgb(0xE2, 0x3B, 0x3B));
                pal['W'] = new SolidBrush(Color.White);
                pal['Y'] = new SolidBrush(Color.FromArgb(0xF5, 0xC8, 0x42));
                pal['P'] = new SolidBrush(Color.FromArgb(0xFF, 0x8F, 0xB0));
                pal['B'] = new SolidBrush(Color.FromArgb(0xB8, 0xD6, 0xFF));
            }
            brDark['k'] = new SolidBrush(Color.FromArgb(0x0B, 0x0B, 0x10));
            brDark['r'] = new SolidBrush(Color.FromArgb(0x2C, 0x2E, 0x3B));
            brDark['R'] = new SolidBrush(Color.FromArgb(0x1B, 0x1C, 0x26));
            brDark['b'] = new SolidBrush(Color.FromArgb(0x3E, 0x40, 0x55));
            brDark['w'] = new SolidBrush(Color.FromArgb(0xF6, 0xF6, 0xFA));
            brDark['p'] = new SolidBrush(Color.FromArgb(0xB0, 0x4A, 0x6E));
            brDark['y'] = new SolidBrush(Color.FromArgb(0xB9, 0xA7, 0xFF));
            LoadPats();
            try { caged = File.ReadAllText(NestFile()).Trim() == "1"; } catch { }
            LoadBond();
            seasonNow = Season();
            dark = DarkNow();
            darkChecked = DateTime.Now.Minute;

            Point c = Cursor.Position;
            Rectangle wa = WA(c.X, c.Y);
            x = Clamp(c.X - SW / 2.0, wa.Left, wa.Right - SW);
            y = wa.Top + 4;
            Bounds = new Rectangle((int)x, (int)y, SW, SH);
            ContextMenuStrip = BuildMenu();
            timer.Interval = 30;
            timer.Tick += delegate { Tick(); };
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            lastT = clock.Elapsed.TotalSeconds;
            Scan(lastT);
            Thread th = new Thread(PipeLoop);
            th.IsBackground = true;
            th.Start();
            Thread cw = new Thread(ClaudeWatchLoop);
            cw.IsBackground = true;
            cw.Start();
            sessionStart = lastT;
            if (caged) { Rectangle n = Nest(); x = n.Left + n.Width / 2.0 - SW / 2.0; y = n.Bottom - SH; SetState("walk", 2); }
            Say(Greeting(), 3.5);
            if (DaysSincePat() >= 2) Say(dark ? "……你好幾天沒摸我了。哼。" : "你最近都不理我…摸摸我好不好 🥺", 4.5);
            if (!W.RegisterHotKey(Handle, 7, 0x0001 | 0x0002 | 0x4000, 0x53)) App.Log("hotkey Ctrl+Alt+S is taken");
            timer.Start();
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            closing = true;
            timer.Stop();
            foreach (CobwebForm w in webs) w.Close();
            bubbleForm.Close();
            if (nestForm != null) { nestForm.Close(); nestNet.Close(); }
            base.OnFormClosed(e);
        }

        // ================= 主迴圈 =================
        void Tick()
        {
            try
            {
                double now = clock.Elapsed.TotalSeconds, dt = Math.Min(0.05, now - lastT);
                lastT = now;
                if (now >= nextScan) { nextScan = now + 0.3; Scan(now); }
                if (CheckClients(now) || hidden) return;
                if (!(dragging && DragUpdate(now, dt))) { Watch(dt); Step(dt); }
                UpdateBall(dt);
                if (fx != null) fx.Step(dt);
                Render();
            }
            catch (Exception ex) { App.Log("tick: " + ex); }
        }

        bool Grounded() { return state == "walk" || state == "idle" || state == "sleep" || state == "hug" || state == "seek" || state == "dizzy" || state == "tug" || state == "fetch" || state == "dance" || state == "kick"; }
        void SetState(string s, double dur) { state = s; t = dur; }
        void Say(string s, double sec) { Say(s, sec, false); }
        void Say(string s, double sec, bool alert) { bubble = s; bt = sec; bubbleAlert = alert; }
        string Pick(string[] a) { return a[rnd.Next(a.Length)]; }
        string Pick(string[] normal, string[] darkSet) { return Pick(dark ? darkSet : normal); }

        // 平日 18:00 之後到隔天 06:00
        static bool IsDarkTime(DateTime n)
        {
            if (n.Hour >= 18) return n.DayOfWeek >= DayOfWeek.Monday && n.DayOfWeek <= DayOfWeek.Friday;
            if (n.Hour < 6) { DayOfWeek y = n.AddDays(-1).DayOfWeek; return y >= DayOfWeek.Monday && y <= DayOfWeek.Friday; }
            return false;
        }
        static double Clamp(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
        double R(double a, double b) { return a + rnd.NextDouble() * (b - a); }

        void Jump(double jvx, double jvy) { vx = jvx; vy = jvy; supH = IntPtr.Zero; SetState("air", 0); }
        void Hop() { Jump(dir * 60 * k, -260 * k); }
        void GoSleep() { z = 0; SetState("sleep", 1e9); }
        void WakeIfSleep() { sleepMode = false; if (state == "sleep") SetState("walk", 2); }
        void AddHeart() { if (hearts.Count < 8) hearts.Add(new double[] { R(-12, 12) * k, 0 }); }

        readonly List<double> clickTimes = new List<double>();
        readonly List<double[]> sparks = new List<double[]>(); // {x, y, vx, vy, 年齡}（螢幕座標）
        int patsToday; string patsDate = "";
        bool dizzyOnLand;
        bool caged;                 // 在窩裡
        double lockVal;             // 網子動畫 0→1
        NestForm nestForm, nestNet; // 窩（在他後面）、網子（鎖住時在他前面）
        double reelT, reelX, reelY; // 噴絲後被拉到弧線上的過渡

        string NestFile() { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SpideyDesktop", "nest.txt"); }
        void SaveNest() { try { File.WriteAllText(NestFile(), caged ? "1" : "0"); } catch { } }

        Rectangle Nest()
        {
            // 整個桌面最右邊那台螢幕的右下角
            Rectangle wa = screens[0].WorkingArea;
            foreach (Screen sc0 in screens) { Rectangle r0 = sc0.WorkingArea; if (r0.Right > wa.Right || (r0.Right == wa.Right && r0.Bottom > wa.Bottom)) wa = r0; }
            int w = Math.Max(SW * 3, (int)(170 * k)), h = Math.Max(SH * 2 + 8, (int)(118 * k));
            return new Rectangle(wa.Right - w - 6, wa.Bottom - h, w, h);
        }

        bool InNest(double px, double py)
        {
            Rectangle n = Nest();
            n.Inflate((int)(20 * k), (int)(20 * k));
            return n.Contains((int)px, (int)py);
        }

        void UpdateNest()
        {
            if (nestForm == null)
            {
                nestForm = new NestForm(k, false);
                nestNet = new NestForm(k, true);
            }
            Rectangle n = Nest();
            bool hot = dragging && state == "drag";
            bool over = hot && InNest(x + SW / 2.0, y + SH / 2.0);
            double lk = Math.Round(lockVal, 2);
            foreach (NestForm f in new NestForm[] { nestForm, nestNet })
                if (f.Hot != hot || f.Over != over || f.Dark != dark || f.Lock != lk)
                {
                    f.Hot = hot; f.Over = over; f.Dark = dark; f.Lock = lk;
                    f.Dirty = true;
                }
            if (hidden) { if (nestForm.Visible) nestForm.Hide(); if (nestNet.Visible) nestNet.Hide(); return; }
            nestForm.Sync(n);
            if (!nestForm.Visible) nestForm.Show();
            bool net = lk > 0.001 && !hot;
            if (net) { nestNet.Sync(n); if (!nestNet.Visible) nestNet.Show(); }
            else if (nestNet.Visible) nestNet.Hide();
            // 由下到上：窩 → 他 → 網子 → 泡泡（網子點得穿，點他照樣有反應）
            W.KeepOnTop(nestForm);
            W.KeepOnTop(this);
            if (net) W.KeepOnTop(nestNet);
            W.KeepOnTop(bubbleForm);
        }

        // 拋物線跳到某一點（腳落在 footY）
        void BallisticTo(double tx, double footY)
        {
            double cx = x + SW / 2.0, foot = y + SH, g = 900 * k;
            Rectangle top = WA(cx, y);
            double apex = Math.Max(Math.Min(foot, footY) - R(60, 130) * k, top.Top + SH + 2);
            if (apex >= foot) apex = foot - 10;
            if (apex >= footY) apex = footY - 10;
            double vy0 = -Math.Sqrt(2 * g * (foot - apex));
            double tt = -vy0 / g + Math.Sqrt(2 * (footY - apex) / g);
            double vx0 = (tx - cx) / tt;
            dir = vx0 >= 0 ? 1 : -1;
            Jump(vx0, vy0);
        }

        void GoNest(bool say)
        {
            caged = true; SaveNest();
            Rectangle n = Nest();
            if (say) Say(dark ? "……好，我待在窩裡。你也早點回家。" : "好～我在窩裡乖乖待著 ♥", 2.2);
            if (Grounded() || state == "glass") { sc = 1; BallisticTo(n.Left + n.Width / 2.0, n.Bottom); }
        }

        void LeaveNest()
        {
            caged = false; SaveNest();
            Say(dark ? "……放我出來了？那我要去催你下班了。" : "自由了！出去玩囉～", 1.8);
            if (Grounded()) { Rectangle n = Nest(); BallisticTo(n.Left - R(120, 320) * k, n.Bottom); }
        }

        string PatsFile() { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SpideyDesktop", "pats.txt"); }

        void LoadPats()
        {
            try
            {
                string[] a = File.ReadAllText(PatsFile()).Trim().Split(' ');
                if (a.Length == 2 && a[0] == DateTime.Now.ToString("yyyy-MM-dd")) { patsDate = a[0]; int.TryParse(a[1], out patsToday); }
            }
            catch { }
        }

        void BumpPats()
        {
            string today = DateTime.Now.ToString("yyyy-MM-dd");
            if (today != patsDate) { patsDate = today; patsToday = 0; }
            patsToday++;
            try { Directory.CreateDirectory(Path.GetDirectoryName(PatsFile())); File.WriteAllText(PatsFile(), patsDate + " " + patsToday); } catch { }
        }

        void Burst(int n)
        {
            double cx = x + SW / 2.0, cy = y + SH * 0.35;
            for (int i = 0; i < n; i++)
            {
                double a = rnd.NextDouble() * Math.PI * 2, sp = R(120, 260) * k;
                sparks.Add(new double[] { cx, cy, Math.Cos(a) * sp, Math.Sin(a) * sp - 120 * k, 0 });
            }
        }

        // 點他一下（沒拖動）
        void Pat()
        {
            double now = clock.Elapsed.TotalSeconds;
            clickTimes.Add(now);
            clickTimes.RemoveAll(delegate(double c) { return now - c > 1.3; });
            int combo = clickTimes.Count;
            BumpPats();
            lastPatDay = DateTime.Now.ToString("yyyy-MM-dd");
            if (patsToday <= 30) AddXp(1); else SaveBond();
            Burst(combo >= 3 ? 10 : 6);
            if (state == "sleep")
            {
                WakeIfSleep();
                Hug(dark ? "……是你啊。我沒睡，只是在等你下班。" : "嗯…是你呀 ♥ 我醒了", 2.4);
                return;
            }
            if (combo >= 5)
            {
                if (Grounded()) SetState("dizzy", 1.6); else dizzyOnLand = true;
                Say(dark ? "別、別再點了……頭好暈" : "頭暈了 @@ 你好愛我喔", 2);
                return;
            }
            if (combo >= 3)
            {
                Say(dark ? "……好癢。不准笑。" : "哈哈哈好癢～", 1.6);
                AddHeart();
                if (Grounded() && state != "dizzy") Jump(dir * 40 * k, -330 * k);
                return;
            }
            if (patsToday % 10 == 0)
            {
                Hug(dark ? "今天第 " + patsToday + " 次了……我才沒有很開心。" : "今天第 " + patsToday + " 次摸我了，我好開心 ♥", 3);
                AddHeart(); AddHeart(); AddHeart();
                return;
            }
            string line = !dark && Level() >= 4 && rnd.NextDouble() < 0.4 ? Pick(PATS_HI) : Pick(PATS, PATS_D);
            if (Grounded()) Hug(line, 2.6);
            else { Say(line, 2.2); AddHeart(); }
        }

        // ---------- 好感度 ----------
        int xp; string lastPatDay = "";
        double saveXpCd; int ballXp;
        string BondFile() { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SpideyDesktop", "bond.txt"); }
        void LoadBond()
        {
            try { string[] a = File.ReadAllText(BondFile()).Trim().Split(' '); int.TryParse(a[0], out xp); if (a.Length > 1) lastPatDay = a[1]; } catch { }
        }
        void SaveBond() { try { File.WriteAllText(BondFile(), xp + " " + lastPatDay); } catch { } }
        int Level() { int lv = 1; for (int i = 2; i < LV.Length; i++) if (xp >= LV[i]) lv = i; return lv; }
        void AddXp(int n)
        {
            int before = Level();
            xp += n; SaveBond();
            int now = Level();
            if (now > before)
            {
                Hug(dark ? "……好感度 Lv" + now + "。解鎖「" + UNLOCK[now] + "」。我、我才沒有很高興。" : "好感度升到 Lv" + now + " 了！解鎖「" + UNLOCK[now] + "」♥", 4);
                AddHeart(); AddHeart(); AddHeart(); Burst(14);
            }
        }
        int DaysSincePat()
        {
            DateTime d;
            if (!DateTime.TryParse(lastPatDay, out d)) return 0;
            return (int)(DateTime.Now.Date - d.Date).TotalDays;
        }
        void ShowBond()
        {
            int lv = Level();
            List<string> got = new List<string>();
            for (int i = 2; i <= lv; i++) got.Add(UNLOCK[i]);
            string next = lv < 6 ? "（" + xp + "/" + LV[lv + 1] + "）" : "（" + xp + "，滿級！）";
            Say("好感度 Lv" + lv + next + (got.Count > 0 ? "　已解鎖：" + string.Join("、", got.ToArray()) : "　多摸摸我就會升級喔"), 4.5);
            AddHeart();
        }

        // ---------- 節日 ----------
        string seasonNow = "", birthday = "";
        static readonly string[] CNY = { "2027-02-06", "2028-01-26", "2029-02-13", "2030-02-03", "2031-01-23", "2032-02-11" };
        string Season()
        {
            DateTime n = DateTime.Now;
            if (birthday.Length == 5 && n.ToString("MM-dd") == birthday) return "birthday";
            foreach (string c in CNY)
            {
                double d = (n.Date - DateTime.Parse(c)).TotalDays;
                if (d >= -5 && d <= 14) return "cny";
            }
            if (n.Month == 12 && n.Day <= 26) return "xmas";
            if (n.Month == 1 && n.Day == 1) return "newyear";
            if (n.Month == 10 && n.Day == 31) return "halloween";
            if (n.DayOfWeek == DayOfWeek.Friday && n.Hour >= 15 && !dark) return "friday";
            return "";
        }
        string SeasonLine()
        {
            switch (seasonNow)
            {
                case "birthday": return Pick(new string[] { "生日快樂！🎂 今天你最大！", "祝你生日快樂～我做了蛋糕給你", "今天是你的日子，什麼都不准煩惱 ♥" });
                case "cny": return Pick(new string[] { "新年快樂！恭喜發財 🧧", "紅包拿來～（騙你的，這個給你）", "新的一年也一起加油！" });
                case "xmas": return Pick(new string[] { "聖誕快樂！🎄", "我想要的聖誕禮物，就是你準時下班", "叮叮噹～叮叮噹～ ❄" });
                case "newyear": return "新年快樂！今年也請多多指教 ✨";
                case "halloween": return Pick(new string[] { "不給糖就搗蛋！🎃", "我今天扮成……蜘蛛人（本來就是）" });
                case "friday": return Pick(new string[] { "週五了！！撐住！", "小週末～今天準時下班好不好", "再一下下就週末了 ✨" });
            }
            return null;
        }
        readonly List<double[]> flakes = new List<double[]>(); // 聖誕節的雪

        // ---------- 躲起來（快速鍵／分享螢幕）----------
        bool userHidden, sharing, fsNow;
        void ToggleHide()
        {
            userHidden = !userHidden;
            ApplyHidden();
            if (!userHidden && !hidden) Say(dark ? "……我回來了。" : "我回來了～", 1.6);
        }
        void ApplyHidden()
        {
            bool want = fsNow || userHidden || sharing;
            if (want == hidden) return;
            hidden = want;
            if (want)
            {
                Hide(); bubbleForm.Hide();
                foreach (CobwebForm f in webs) f.Hide();
                if (nestForm != null) { nestForm.Hide(); nestNet.Hide(); }
                if (ballForm != null) ballForm.Hide();
                if (fx != null && fx.Active) { fx.Active = false; fx.Hide(); }
            }
            else Show();
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
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x0312 && m.WParam.ToInt32() == 7) { ToggleHide(); return; } // Ctrl+Alt+S
            base.WndProc(ref m);
        }

        // ---------- 接球 ----------
        BallForm ballForm;
        bool ballOn, fetching;
        double bx, by, bvx, bvy, ballIdle, catchCd;
        void StartBall()
        {
            if (caged) { Say("我在窩裡，先放我出去才能接球～", 1.8); return; }
            if (ballForm == null) { ballForm = new BallForm(Math.Max(2, S * 3 / 4)); ballForm.Kicked += BallClicked; }
            Point c = Cursor.Position;
            bx = c.X; by = c.Y - 20 * k;
            ballOn = true;
            BallClicked();
        }
        void BallClicked()
        {
            bvx = (rnd.NextDouble() < 0.5 ? -1 : 1) * R(350, 800) * k;
            bvy = -R(500, 800) * k;
            ballIdle = 0; fetching = true; catchCd = 0.4;
            WakeIfSleep();
            if (Grounded() && !caged) SetState("fetch", 15);
            Say(dark ? "……好啦，陪你玩一下。" : Pick(new string[] { "球！我來了！", "等我～", "這次一定接到！" }), 1.2);
        }
        void EndBall(string text)
        {
            ballOn = false; fetching = false;
            if (ballForm != null) ballForm.Hide();
            if (state == "fetch") SetState("idle", 1);
            Say(text, 2);
        }
        void UpdateBall(double dt)
        {
            if (!ballOn) return;
            double g = 900 * k, r = ballForm.Width / 2.0, prevBottom = by + r;
            bvy += g * dt; bx += bvx * dt; by += bvy * dt;
            Rectangle wa = WA(bx, by);
            if (!Inside(bx - r, by) && bx - r < wa.Left) { bx = wa.Left + r; bvx = Math.Abs(bvx) * 0.6; }
            if (!Inside(bx + r, by) && bx + r > wa.Right) { bx = wa.Right - r; bvx = -Math.Abs(bvx) * 0.6; }
            if (by - r < wa.Top) { by = wa.Top + r; bvy = Math.Abs(bvy) * 0.5; }
            if (bvy > 0)
            {
                double best = wa.Bottom;
                foreach (Plat p in plats) if (bx >= p.Left && bx <= p.Right && prevBottom <= p.Top + 1 && by + r >= p.Top && p.Top < best) best = p.Top;
                if (by + r >= best)
                {
                    by = best - r;
                    if (bvy > 140 * k) { bvy = -bvy * 0.55; bvx *= 0.85; }
                    else { bvy = 0; bvx *= Math.Pow(0.15, dt); }
                }
            }
            ballIdle += dt;
            if (catchCd > 0) catchCd -= dt;
            if (ballIdle > 25 && Math.Abs(bvx) < 8 && bvy == 0) { EndBall(dark ? "……不玩了？那就下班吧。" : "不玩了嗎？好吧～下次再玩 ⚾"); return; }
            double scx = x + SW / 2.0, scy = y + SH / 2.0;
            if (fetching && catchCd <= 0 && state != "drag" && Math.Abs(bx - scx) < SW * 0.6 + r && Math.Abs(by - scy) < SH * 0.6 + r) CatchBall();
            Rectangle nb = new Rectangle((int)(bx - r), (int)(by - r), ballForm.Width, ballForm.Height);
            if (ballForm.Bounds != nb) ballForm.Bounds = nb;
            if (!ballForm.Visible) { ballForm.Show(); W.KeepOnTop(ballForm); }
        }
        void CatchBall()
        {
            catchCd = 1.0; fetching = false;
            if (ballXp < 20) { ballXp += 2; AddXp(2); }
            Burst(6);
            Say(dark ? "……接到了。還你。" : Pick(new string[] { "接到了！還你～", "好球！傳回去！", "嘿嘿，我很厲害吧" }), 1.8);
            // 踢回滑鼠的方向，等你再點球
            Point c = Cursor.Position;
            bvx = Clamp((c.X - bx) * 1.1, -900 * k, 900 * k);
            bvy = -R(450, 650) * k;
            by = Math.Min(by, y - 4 * k);
            if (Grounded()) SetState("kick", 0.5);
        }
        void Fetch(double dt)
        {
            if (!ballOn || !fetching) { SetState("idle", 1); return; }
            double cx = x + SW / 2.0, foot = y + SH, r = ballForm.Width / 2.0, dxb = bx - cx;
            bool resting = bvy == 0 && Math.Abs(bvx) < 30 * k;
            bool sameLevel = Math.Abs(by + r - foot) < 40 * k;
            if (resting && !sameLevel) { BallisticTo(bx, by + r); return; }
            if (Math.Abs(dxb) > 6) { dir = dxb > 0 ? 1 : -1; if (MoveOnGround(dt, 125 * k)) return; }
            else if (by < y && bvy > 0 && by > y - 160 * k) { Jump(0, -380 * k); return; }
            if (t < 0) { fetching = false; SetState("idle", 1); Say("球跑太遠了啦～", 1.6); }
        }

        // ---------- 煙火、跳舞、Claude ----------
        FxForm fx;
        double danceCd = 30, waitCd; int typingStreak;
        readonly Dictionary<string, double> claudeStart = new Dictionary<string, double>();
        double Bob() { return state == "dance" ? Math.Abs(Math.Sin(anim * 8)) * 6 * k : 0; }
        void Celebrate(string env)
        {
            if (hidden) return;
            WakeIfSleep();
            if (fx == null) fx = new FxForm(k);
            fx.Start(WA(x + SW / 2.0, y + SH / 2.0));
            W.KeepOnTop(fx); W.KeepOnTop(this); W.KeepOnTop(bubbleForm);
            string line = dark ? "上版成功……那現在可以下班了吧？🎆"
                : (env == "prod" ? "上正式機了！🎉 辛苦了！" : (env == "dev" ? "測試機上版成功！🎆" : "上版成功！🎆"));
            if (Grounded()) SetState("dance", 3.5);
            Say(line, 4); AddXp(5); Burst(10); AddHeart(); AddHeart();
        }
        void OnClaude(string ev, string sid)
        {
            double now = clock.Elapsed.TotalSeconds;
            if (ev == "start") { claudeStart[sid] = now; return; }
            if (hidden) return;
            double idle = W.IdleSeconds();
            if (ev == "done")
            {
                double started;
                double elapsed = claudeStart.TryGetValue(sid, out started) ? now - started : 0;
                claudeStart.Remove(sid);
                if (elapsed < 45 && idle < 30) return; // 很快就做完、你也在看 → 不吵你
                WakeIfSleep();
                string text = dark ? "Claude 做完了。你也該收工了。" : "Claude 做完了！快來看 👀";
                if (Grounded()) StartGlass(text); else Say(text, 4);
                Burst(8); AddXp(1);
            }
            else if (ev == "wait")
            {
                if (waitCd > 0) return;
                waitCd = 20;
                WakeIfSleep();
                string text = dark ? "Claude 在等你回答。快點回完快點下班。" : "Claude 在等你回答喔～ 👋";
                if (idle >= 30 && Grounded()) StartGlass(text);
                else { Say(text, 3); if (Grounded()) Jump(0, -260 * k); }
            }
        }

        // ---------- Claude 卡住偵測（看 ~/.claude/projects 的對話紀錄，不需要 hooks）----------
        // 最後一筆是「Claude 叫了工具」→ 3 分鐘沒新紀錄＝在等你按允許，或指令跑很久（問你問題時 90 秒）
        // 最後一筆是「你的訊息／工具結果」→ 5 分鐘沒回應＝Claude 卡住
        class StuckInfo { public long Episode; public int Alerts; public DateTime NextAt; }
        readonly Dictionary<string, StuckInfo> stuck = new Dictionary<string, StuckInfo>();

        static string ClaudeProjectsDir()
        {
            string cfg = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
            if (string.IsNullOrEmpty(cfg)) cfg = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude");
            return Path.Combine(cfg, "projects");
        }

        void ClaudeWatchLoop()
        {
            Thread.Sleep(20000);
            JavaScriptSerializer js = new JavaScriptSerializer();
            js.MaxJsonLength = int.MaxValue;
            while (!closing)
            {
                try { ClaudeWatchOnce(js); } catch (Exception ex) { App.Log("claude watch: " + ex.Message); }
                Thread.Sleep(15000);
            }
        }

        void ClaudeWatchOnce(JavaScriptSerializer js)
        {
            string root = ClaudeProjectsDir();
            if (!Directory.Exists(root)) return;
            DateTime now = DateTime.UtcNow;
            HashSet<string> seen = new HashSet<string>();
            bool anyClaude = Process.GetProcessesByName("claude").Length > 0 || Process.GetProcessesByName("node").Length > 0;
            foreach (string pdir in Directory.GetDirectories(root))
                foreach (FileInfo fi in new DirectoryInfo(pdir).EnumerateFiles("*.jsonl"))
                {
                    DateTime act = fi.LastWriteTimeUtc;
                    if ((now - act).TotalMinutes > 40) continue;
                    string key = fi.FullName;
                    seen.Add(key);
                    StuckInfo si;
                    if (!stuck.TryGetValue(key, out si)) { si = new StuckInfo(); stuck[key] = si; }
                    if ((now - act).TotalSeconds < 85)
                    {
                        if (si.Alerts > 0) { si.Alerts = 0; Post(delegate { OnClaudeUnstuck(); }); }
                        continue;
                    }
                    // 子代理人還在寫 → 主對話沒卡
                    string sub = Path.Combine(pdir, Path.GetFileNameWithoutExtension(fi.Name));
                    if (Directory.Exists(sub))
                        foreach (FileInfo f2 in new DirectoryInfo(sub).EnumerateFiles("*", SearchOption.AllDirectories))
                            if (f2.LastWriteTimeUtc > act) act = f2.LastWriteTimeUtc;
                    double quiet = (now - act).TotalSeconds;
                    if (quiet < 85) continue;
                    string tool, title;
                    string kind = ClaudeState(js, fi.FullName, out tool, out title);
                    if (kind == null || kind == "idle" || !anyClaude) { si.Alerts = 0; continue; }
                    bool ask = tool == "AskUserQuestion" || tool == "ExitPlanMode";
                    double limit = kind == "tool" ? (ask ? 90 : 180) : 300;
                    if (quiet < limit) continue;
                    if (si.Episode != act.Ticks) { si.Episode = act.Ticks; si.Alerts = 0; }
                    if (si.Alerts >= 3 || (si.Alerts > 0 && DateTime.UtcNow < si.NextAt)) continue;
                    si.Alerts++;
                    si.NextAt = DateTime.UtcNow.AddMinutes(10);
                    int min = Math.Max(1, (int)Math.Round(quiet / 60));
                    string k2 = kind, t2 = tool, ti = title;
                    App.Log("claude stuck: " + kind + " " + tool + " " + min + "min " + fi.Name);
                    Post(delegate { OnClaudeStuck(k2, t2, ti, min); });
                }
            List<string> gone = new List<string>();
            foreach (string k in stuck.Keys) if (!seen.Contains(k)) gone.Add(k);
            foreach (string k in gone) stuck.Remove(k);
        }

        // 讀對話紀錄最後一段，找最後一筆主對話：回傳 idle／model／tool（null＝看不出來）
        static string ClaudeState(JavaScriptSerializer js, string file, out string tool, out string title)
        {
            tool = null; title = null;
            string text;
            using (FileStream fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                long len = fs.Length, start = Math.Max(0, len - 768 * 1024);
                fs.Seek(start, SeekOrigin.Begin);
                byte[] buf = new byte[len - start];
                int got = 0;
                while (got < buf.Length) { int r = fs.Read(buf, got, buf.Length - got); if (r <= 0) break; got += r; }
                text = Encoding.UTF8.GetString(buf, 0, got);
                if (start > 0) { int nl = text.IndexOf('\n'); text = nl >= 0 ? text.Substring(nl + 1) : ""; }
            }
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

        static string Str(Dictionary<string, object> d, string k)
        {
            object v;
            return d.TryGetValue(k, out v) ? v as string : null;
        }

        string stuckLine; double stuckRepeat;
        void OnClaudeStuck(string kind, string tool, string title, int min)
        {
            if (sharing || fsNow) return; // 分享螢幕／全螢幕時不跳出來
            if (userHidden) { userHidden = false; ApplyHidden(); }
            if (hidden) return;
            WakeIfSleep();
            string who = string.IsNullOrEmpty(title) ? "Claude" : "Claude（" + (title.Length > 14 ? title.Substring(0, 14) + "…" : title) + "）";
            string text;
            if (tool == "AskUserQuestion" || tool == "ExitPlanMode")
                text = dark ? who + " 在問你問題。回完就下班。" : who + " 在問你問題，等你回答喔～ 🙋";
            else if (kind == "tool")
                text = dark ? who + " 停了 " + min + " 分鐘。去按一下，然後下班。"
                    : who + " 停在「" + (tool ?? "工具") + "」" + min + " 分鐘了，是不是在等你按允許？";
            else
                text = dark ? who + " 卡住 " + min + " 分鐘了。去看一眼，看完就下班。"
                    : who + " 好像卡住了…" + min + " 分鐘沒動靜，去看看？ 🕷️";
            sense = 2.8; // 蜘蛛感應
            if (Grounded() && state != "glass") StartGlass(text); else Say(text, 5, true);
            stuckLine = text; stuckRepeat = 3.5; // 敲完玻璃再講一次、講久一點
        }

        void OnClaudeUnstuck()
        {
            if (hidden) return;
            stuckLine = null;
            Say(dark ? "Claude 動了。" : "Claude 又動起來了！👍", 2);
        }

        void Hug(string text, double sec)
        {
            if (Grounded()) SetState("hug", sec);
            Say(text, sec);
            AddHeart(); AddHeart();
        }

        // 滑鼠：停在他身上 → 抱抱；停在他附近同一高度 → 跑過去抱滑鼠
        void Watch(double dt)
        {
            if (stuckLine != null) { stuckRepeat -= dt; if (stuckRepeat <= 0) { Say(stuckLine, 6, true); stuckLine = null; } }
            seekCd -= dt; hoverCd -= dt; newWinCd -= dt; fgCd -= dt; lateCd -= dt; danceCd -= dt; waitCd -= dt; saveXpCd -= dt;
            Point c = Cursor.Position;
            if (c == lastCursor) cursorStill += dt; else { cursorStill = 0; lastCursor = c; }
            if (!Grounded() || state == "hug" || sleepMode || state == "sleep") return;
            double cx = x + SW / 2.0;
            bool onMe = c.X >= x && c.X <= x + SW && c.Y >= y && c.Y <= y + SH;
            if (onMe && cursorStill > 1.2 && hoverCd <= 0) { hoverCd = 12; Hug("你在摸我嗎？抱抱～", 2.4); return; }
            if (!caged && !fetching && state != "seek" && seekCd <= 0 && cursorStill > 2.5 && !onMe
                && c.Y > y - 40 * k && c.Y < y + SH + 8 && Math.Abs(c.X - cx) < 380 * k && Math.Abs(c.X - cx) > 8)
            {
                seekX = c.X; seekCd = R(45, 100); SetState("seek", 8); Say("那是什麼？", 1.2);
            }
        }

        void Step(double dt)
        {
            anim += dt; t -= dt;
            if (bt > 0) bt -= dt;
            if (sense > 0) sense -= dt;
            for (int i = hearts.Count - 1; i >= 0; i--) { hearts[i][1] += dt; if (hearts[i][1] > 1.6) hearts.RemoveAt(i); }
            for (int i = sparks.Count - 1; i >= 0; i--)
            {
                double[] sp = sparks[i];
                sp[3] += 420 * k * dt; sp[0] += sp[2] * dt; sp[1] += sp[3] * dt; sp[4] += dt;
                if (sp[4] > 0.75) sparks.RemoveAt(i);
            }
            if (seasonNow == "xmas" && rnd.NextDouble() < dt * 3)
                flakes.Add(new double[] { x + SW / 2.0 + R(-70, 70) * k, y - R(30, 90) * k, R(-12, 12) * k, 0 });
            for (int i = flakes.Count - 1; i >= 0; i--)
            {
                double[] f = flakes[i];
                f[1] += 38 * k * dt; f[0] += (f[2] + Math.Sin(f[3] * 3) * 10 * k) * dt; f[3] += dt;
                if (f[3] > 2.2) flakes.RemoveAt(i);
            }
            FollowFast();
            {
                // 在窩裡而且落地 → 噴網鎖住；離開窩 → 網子收回
                bool settled = caged && state != "drag" && (state != "air" || y + SH > Nest().Top); // 在窩裡跳一下不收網
                double target = settled ? 1 : 0, prevLock = lockVal;
                lockVal = target > lockVal ? Math.Min(target, lockVal + dt / 0.6) : Math.Max(target, lockVal - dt / 0.3);
                if (prevLock < 0.5 && lockVal >= 0.5 && target == 1) Say("Thwip! Thwip! 被網住了～", 1.4);
                if (prevLock > 0.5 && lockVal <= 0.5 && target == 0 && !caged) Say("啪！", 0.8);
            }
            double cx = x + SW / 2.0, midY = y + SH / 2.0;
            Rectangle wa = WA(cx, midY);
            switch (state)
            {
                case "walk":
                    if (sleepMode) { GoSleep(); break; }
                    if (MoveOnGround(dt, 40 * k)) break;
                    if (t < 0) Decide(wa);
                    break;
                case "seek": Seek(dt); break;
                case "idle":
                    { Point cp = Cursor.Position; if (Math.Abs(cp.X - cx) > 20) dir = cp.X > cx ? 1 : -1; }
                    if (sleepMode) GoSleep();
                    else if (t < 0) SetState("walk", R(3, 6));
                    break;
                case "fetch": Fetch(dt); break;
                case "dance": if (t < 0) SetState("idle", R(1, 2)); break;
                case "kick": if (t < 0) SetState("idle", R(1.5, 3)); break;
                case "tug":
                    // 抓著網子搖
                    if (Math.Floor(anim * 10) != Math.Floor((anim - dt) * 10)) x += (Math.Floor(anim * 10) % 2 == 0 ? 2 : -2) * k;
                    if (t < 0) SetState("idle", R(1, 2));
                    break;
                case "dizzy":
                    if (Math.Floor(anim * 8) != Math.Floor((anim - dt) * 8)) dir = -dir;
                    if (t < 0) { SetState("idle", 1); Say(dark ? "……沒事。" : "好、好了，我沒事 ♥", 1.4); }
                    break;
                case "hug":
                    if (rnd.NextDouble() < dt * 2.5) AddHeart();
                    if (t < 0) SetState("walk", R(2, 4));
                    break;
                case "sleep": z += dt; if (t < 0) SetState("walk", 3); break;
                case "air": Air(dt); break;
                case "swing": Swing(dt, wa); break;
                case "hang": Hang(dt, wa); break;
                case "climb": Climb(dt, wa); break;
                case "shoot": Shoot(dt); break;
                case "zip": Zip(dt); break;
                case "glass": Glass(dt); break;
                case "peek": Peek(dt, wa); break;
            }
        }

        // 回傳 true＝離開地面或換狀態了
        bool MoveOnGround(double dt, double speed)
        {
            double nx = x + dir * speed * dt, ncx = nx + SW / 2.0, midY = y + SH / 2.0;
            if (caged)
            {
                Rectangle n = Nest();
                if (nx < n.Left + 4) { x = n.Left + 4; dir = 1; return false; }
                if (nx + SW > n.Right - 4) { x = n.Right - 4 - SW; dir = -1; return false; }
                x = nx; y = n.Bottom - SH;
                return false;
            }
            if (supH != IntPtr.Zero)
            {
                if (ncx < supL || ncx > supR)
                {
                    if (state == "walk" && !goClimb && rnd.NextDouble() < 0.55)
                    {
                        bool right = ncx > supR;
                        dir = -dir;
                        if (rnd.NextDouble() < 0.3) SpinWeb(supH, right);
                        return false;
                    }
                    x = nx;
                    Jump(dir * speed * 1.4, -140 * k);
                    return true;
                }
                x = nx;
                return false;
            }
            double lead = dir > 0 ? nx + SW - 1 : nx;
            if (!Inside(lead, midY))
            {
                if (state == "walk" && (goClimb || rnd.NextDouble() < 0.35)) { StartClimb(dir); return true; }
                dir = -dir;
                return false;
            }
            double floorY = WA(ncx, midY).Bottom - SH;
            if (floorY > y + 2) { x = nx; Jump(dir * speed, 0); return true; }
            if (floorY < y - 2) { dir = -dir; return false; }
            x = nx; y = floorY;
            return false;
        }

        void Decide(Rectangle wa)
        {
            goClimb = false;
            if (fetching && ballOn) { SetState("fetch", 15); return; }
            double r = rnd.NextDouble(), cx = x + SW / 2.0;
            if (caged)
            {
                // 窩裡：發呆、散步、抱抱、打盹、偶爾敲敲螢幕
                if (r < .35) SetState("idle", R(2, 5));
                else if (r < .72) { dir = rnd.NextDouble() < .5 ? -1 : 1; SetState("walk", R(2, 5)); }
                else if (r < .80) Hug(Pick(HUGS, HUGS_D), 2.2);
                else if (r < .86) { GoSleep(); t = R(6, 14); }
                else if (r < .88) StartGlass(Pick(KNOCK, KNOCK_D));
                else if (r < .92) Jump(0, -260 * k);
                else if (r < .97)
                {
                    SetState("tug", 1.8);
                    Say(dark ? "……把我關起來也沒用，你還是要下班。" : Pick(new string[] { "放我出去嘛～", "這張網好黏喔", "我會乖乖的，放我出去好不好 ♥" }), 2.2);
                }
                else { dir = -dir; SetState("walk", R(2, 4)); }
                return;
            }
            if (r < .20) SetState("idle", R(1.5, 4));
            else if (r < .48) { if (!JumpToPlatform()) Hop(); }
            else if (r < .62) { if (!ShootTo("swing")) Hop(); }
            else if (r < .70) ShootTo("hang");
            else if (r < .75) { goClimb = true; dir = cx < (wa.Left + wa.Right) / 2.0 ? -1 : 1; SetState("walk", 30); }
            else if (r < .80) Hug(Pick(HUGS, HUGS_D), 2.2);
            else if (r < (dark ? .84 : .815)) StartGlass(Pick(KNOCK, KNOCK_D));
            else if (r < .86 && lateCd <= 0 && LateLine() != null) { lateCd = dark ? 240 : 600; Say(LateLine(), 3.5); SetState("idle", 3.5); }
            else if (r < .90 && SeasonLine() != null) { Say(SeasonLine(), 3); SetState("idle", 3); }
            else { dir = rnd.NextDouble() < .5 ? -1 : 1; SetState("walk", R(3, 6)); }
        }

        void Seek(double dt)
        {
            Point c = Cursor.Position;
            double cx = x + SW / 2.0;
            if (Math.Abs(c.X - seekX) > 4)
            {
                if (c.Y > y - 60 * k && c.Y < y + SH + 20) seekX = c.X;
                else { SetState("walk", 2); Say("咦，跑掉了…", 1.4); return; }
            }
            if (Math.Abs(seekX - cx) < 6) { Hug("抓到你的滑鼠了！抱抱 ♥", 3); return; }
            dir = seekX > cx ? 1 : -1;
            if (MoveOnGround(dt, 95 * k)) return;
            double ncx = x + SW / 2.0;
            if ((dir > 0 && ncx > seekX) || (dir < 0 && ncx < seekX)) x = seekX - SW / 2.0;
            if (t < 0) SetState("walk", 2);
        }

        bool JumpToPlatform()
        {
            if (!Grounded() || caged) return false;
            double cx = x + SW / 2.0, foot = y + SH;
            List<double[]> opts = new List<double[]>();
            foreach (Plat p in plats)
            {
                if (p.H == supH && Math.Abs(p.Top - foot) < 2) continue;
                double tx = p.Left + SW / 2.0 + rnd.NextDouble() * Math.Max(0, p.Right - p.Left - SW);
                double dx = tx - cx, dy = p.Top - foot;
                if (Math.Abs(dx) < 40 * k || Math.Abs(dx) > 900 * k || dy < -600 * k) continue;
                opts.Add(new double[] { tx, p.Top });
            }
            if (supH != IntPtr.Zero)
            {
                Rectangle wa = WA(cx, y);
                opts.Add(new double[] { Clamp(cx + R(-400, 400) * k, wa.Left + SW, wa.Right - SW), wa.Bottom });
            }
            if (opts.Count == 0) return false;
            double[] o = opts[rnd.Next(opts.Count)];
            double g = 900 * k;
            Rectangle top = WA(cx, y);
            double apex = Math.Max(Math.Min(foot, o[1]) - R(50, 130) * k, top.Top + SH + 2);
            if (apex >= foot) apex = foot - 10;
            if (apex >= o[1]) apex = o[1] - 10;
            double vy0 = -Math.Sqrt(2 * g * (foot - apex));
            double tt = -vy0 / g + Math.Sqrt(2 * (o[1] - apex) / g);
            double vx0 = (o[0] - cx) / tt;
            dir = vx0 > 0 ? 1 : -1;
            Jump(vx0, vy0);
            if (rnd.NextDouble() < 0.3) Say("跳～", 0.8);
            return true;
        }

        // ---- 噴絲：錨點一定是真的東西（視窗底邊／角，找不到才用螢幕頂）----
        bool PointVisible(WinInfo w, double px, double py)
        {
            foreach (WinInfo o in wins)
            {
                if (o.Z >= w.Z) break;
                if (px >= o.L && px < o.R && py >= o.T && py < o.B) return false;
            }
            return true;
        }

        double[] FindAnchor(bool vertical)
        {
            double cx = x + SW / 2.0, hy = y;
            Rectangle wa = WA(cx, y + SH / 2.0);
            List<double[]> opts = new List<double[]>();
            foreach (WinInfo w in cands.Values)
            {
                if (w.B > hy - 70 * k || w.B < wa.Top + 10) continue;
                double px;
                if (vertical) { if (cx < w.L + 6 || cx > w.R - 6) continue; px = cx; }
                else
                {
                    px = Clamp(cx + dir * R(60, 220) * k, w.L + 6, w.R - 6);
                    if (Math.Abs(px - cx) > 300 * k) continue;
                }
                if (!PointVisible(w, px, w.B - 2)) continue;
                opts.Add(new double[] { px, w.B });
            }
            if (opts.Count > 0 && rnd.NextDouble() < 0.85) return opts[rnd.Next(opts.Count)];
            double dist = hy - wa.Top;
            if (dist < 90 * k) return null;
            if (vertical) return new double[] { cx, wa.Top };
            return new double[] { Clamp(cx + dir * Math.Min(dist * 0.6, 260 * k), wa.Left + 10, wa.Right - 10), wa.Top };
        }

        bool ShootTo(string mode)
        {
            if (!Grounded() || caged) return false;
            double[] a = FindAnchor(mode == "hang");
            if (a == null) return false;
            ax = a[0]; ay = a[1];
            dir = ax >= x + SW / 2.0 ? 1 : -1;
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
                double hx = x + SW / 2.0, hy = y;
                Rectangle swa = WA(hx, y + SH / 2.0);
                double maxL = (swa.Bottom - SH) - ay - 24 * k; // 最低點要離地，不然一盪就撞地鬆手
                L = Math.Min(Math.Sqrt((hx - ax) * (hx - ax) + (hy - ay) * (hy - ay)), maxL);
                if (L < 36 * k) { Jump(dir * 60 * k, -300 * k); return; }
                th = Math.Asin(Clamp((hx - ax) / L, -0.95, 0.95));
                if (Math.Abs(th) < 0.5) th = 0.9 * (hx < ax ? -1 : 1);
                om = 0;
                reelT = 0.18; reelX = x; reelY = y; // 被絲拉到弧線上
                SetState("swing", 3.2);
            }
            else if (nextAct == "hang")
            {
                Rectangle wa = WA(ax, y + SH / 2.0);
                targetL = Math.Max(10, Math.Min(wa.Height * R(0.15, 0.4), wa.Bottom - SH - 10 - ay));
                hangPhase = 0; L = 0;
                SetState("hang", 99);
            }
            else SetState("zip", 3);
        }

        void Swing(double dt, Rectangle wa)
        {
            om = (om - (900 * k / L) * Math.Sin(th) * dt) * 0.997;
            th += om * dt;
            double hx = ax + L * Math.Sin(th), hy = ay + L * Math.Cos(th), floorY = wa.Bottom - SH;
            x = hx - SW / 2.0; y = Math.Min(hy, floorY);
            if (reelT > 0)
            {
                double f = Ease(1 - reelT / 0.18);
                x = reelX + (x - reelX) * f; y = reelY + (y - reelY) * f;
                reelT -= dt;
            }
            double vxs = L * Math.Cos(th) * om;
            if (Math.Abs(vxs) > 5) dir = vxs > 0 ? 1 : -1;
            if (t < 0 || hy > floorY + 1) { Jump(vxs * .8, -L * Math.Sin(th) * om * .8); if (rnd.NextDouble() < .4) Say("呀呼～", 0.9); }
        }

        void Hang(double dt, Rectangle wa)
        {
            x = ax - SW / 2.0;
            if (hangPhase == 0)
            {
                y -= 700 * k * dt; // 收絲往上拉
                if (y <= ay + 4) { y = ay + 4; hangPhase = 1; L = 0; t = 5; Say("倒吊看世界～", 2); }
                return;
            }
            L = Math.Min(targetL, L + 160 * k * dt);
            y = ay + 4 + L + Math.Sin(anim * 2.4) * 4 * k;
            if (t < 0) { Jump(0, 0); }
        }

        void Zip(double dt)
        {
            // 被絲拉向新視窗的頂角，拉到就站上去
            double tx = ax - SW / 2.0, ty = ay - SH;
            double dx = tx - x, dy = ty - y, d = Math.Sqrt(dx * dx + dy * dy), sp = 1100 * k * dt;
            if (dx != 0) dir = dx > 0 ? 1 : -1;
            if (d > sp && t > 0) { x += dx / d * sp; y += dy / d * sp; return; }
            x = tx; y = ty;
            foreach (Plat p in plats)
                if (p.H == zipH && ax >= p.Left - 2 && ax <= p.Right + 2 && Math.Abs(p.Top - ay) < 3)
                {
                    SetSupport(p);
                    SetState("idle", 1.6);
                    AddWeb(zipH, zipRight);
                    Say("黏好了！", 1.4);
                    return;
                }
            Jump(0, 0);
        }

        // ---- 第四面牆 ----
        void StartGlass(string text)
        {
            if (!Grounded()) { Say(text, 2.5); return; }
            Rectangle wa = WA(x + SW / 2.0, y + SH / 2.0);
            if (y + SH - 3.2 * SH < wa.Top) { Say(text, 2.5); return; } // 上面空間不夠放大
            afterGlass = text; gt = 0; sc = 1; knock = 0;
            SetState("glass", 99);
        }

        void Glass(double dt)
        {
            double prev = gt;
            gt += dt;
            Point cp = Cursor.Position;
            dir = cp.X >= x + SW / 2.0 ? 1 : -1;
            if (gt < 0.5) sc = 1 + 2 * Ease(gt / 0.5);
            else if (gt < 3.4)
            {
                sc = 3;
                if (prev < 0.55 && gt >= 0.55) Say(afterGlass, 2.8);
                if (Math.Floor(gt * 2.2) != Math.Floor(prev * 2.2)) knock = 0.12;
            }
            else if (gt < 3.9) sc = 3 - 2 * Ease((gt - 3.4) / 0.5);
            else { sc = 1; SetState("idle", 1.2); }
            if (knock > 0) knock -= dt;
        }

        static double Ease(double v) { v = Clamp(v, 0, 1); return v * v * (3 - 2 * v); }

        void Peek(double dt, Rectangle wa)
        {
            // 躲到螢幕外，只露半個身體偷看
            double prev = gt;
            gt += dt;
            dir = -wallSide;
            double hideX = wallSide < 0 ? wa.Left - SW * 0.55 : wa.Right - SW * 0.45;
            double inX = wallSide < 0 ? wa.Left : wa.Right - SW;
            x = gt < 0.4 ? inX + (hideX - inX) * Ease(gt / 0.4) : hideX;
            if (prev <= 0.4 && gt > 0.4) Say("躲貓貓～", 1.2);
            if (t < 0) { x = inX; Say("找到我了嗎？嘿嘿", 1.6); climbDir = 1; SetState("climb", 99); }
        }

        string LateLine()
        {
            int h = DateTime.Now.Hour;
            if (dark) return h >= 21 || h < 5 ? "這麼晚了。關機，睡覺。" : "下班時間早就過了喔。";
            if (h >= 23 || h < 5) return "很晚了耶，早點休息好不好 🌙";
            if (h == 12) return "午餐吃了沒？";
            if (h == 15) return "下午茶時間～喝口水吧";
            return null;
        }

        string Greeting()
        {
            string sl = SeasonLine();
            if (sl != null && seasonNow != "friday") return sl;
            if (dark) return "……下班時間了。你為什麼還開著電腦？";
            int h = DateTime.Now.Hour;
            if (h >= 23 || h < 5) return "這麼晚還在寫？我陪你 🌙";
            if (h < 11) return "早安！今天也一起加油 ☀";
            if (h < 14) return "午安～吃飯了沒？我出來陪你";
            if (h >= 18) return "晚上了，辛苦啦，我陪你";
            return "我出來玩啦！整個螢幕都是我的 🕸";
        }

        string AppLine(IntPtr h)
        {
            string name = "";
            try { int pid; W.GetWindowThreadProcessId(h, out pid); name = Process.GetProcessById(pid).ProcessName.ToLowerInvariant(); }
            catch { }
            if (dark)
            {
                if (name == "code") return "還在寫 code？下班了啦。";
                if (name.Contains("teams") || name == "slack" || name == "line") return "下班了還回訊息？明天再說。";
                if (name == "excel" || name == "powerpnt" || name == "winword") return "這份明天做也不會怎樣。";
                return "……你在做什麼？不是該下班了嗎。";
            }
            if (name == "chrome" || name == "msedge" || name == "firefox") return "又在逛網頁？帶我一起看～";
            if (name == "code") return "回來寫 code 啦！我陪你";
            if (name == "excel") return "在算數字喔，加油！";
            if (name == "powerpnt") return "在做簡報？我幫你盯排版";
            if (name == "winword") return "在寫文件～慢慢來";
            if (name.Contains("teams") || name == "slack" || name == "line") return "有人找你嗎？";
            if (name == "explorer") return "在找檔案？";
            return "你在用這個呀？我也來看看";
        }

        // 噴絲把自己拉到某個視窗頂端
        bool ZipToWindow(WinInfo w, string text)
        {
            if (!Grounded() || sleepMode || state == "hug" || caged || fetching) return false;
            double cx = x + SW / 2.0;
            Plat target = null; double tx = 0, bestD = double.MaxValue;
            foreach (Plat p in plats)
            {
                if (p.H != w.H) continue;
                double[] ends = { p.Left + SW / 2.0 + 2, p.Right - SW / 2.0 - 2 };
                foreach (double e in ends) { double d = Math.Abs(e - cx); if (d < bestD) { bestD = d; tx = e; target = p; } }
            }
            if (target == null) return false;
            if (supH == w.H) { Say(text, 2); return true; }
            ax = tx; ay = target.Top; zipH = w.H; zipRight = tx > (w.L + w.R) / 2.0;
            dir = ax >= cx ? 1 : -1;
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

        void Air(double dt)
        {
            double g = 900 * k, prevFoot = y + SH;
            vy += g * dt; x += vx * dt; y += vy * dt;
            double cx = x + SW / 2.0, midY = y + SH / 2.0;
            Rectangle wa = WA(cx, midY);
            if (!Inside(x, midY) && x < wa.Left) { x = wa.Left; vx = -vx * .5; }
            if (!Inside(x + SW - 1, midY) && x + SW > wa.Right) { x = wa.Right - SW; vx = -vx * .5; }
            if (caged)
            {
                Rectangle n = Nest();
                if (y + SH > n.Top)
                {
                    if (x < n.Left + 4) { x = n.Left + 4; vx = Math.Abs(vx) * .4; }
                    if (x + SW > n.Right - 4) { x = n.Right - 4 - SW; vx = -Math.Abs(vx) * .4; }
                }
            }
            cx = x + SW / 2.0;
            if (y < wa.Top) { y = wa.Top; if (vy < 0) vy = 0; }
            if (Math.Abs(vx) > 1) dir = vx > 0 ? 1 : -1;
            if (vy <= 0) return;
            double best = wa.Bottom; Plat bp = null;
            foreach (Plat p in plats)
                if (cx >= p.Left && cx <= p.Right && prevFoot <= p.Top + 1 && y + SH >= p.Top && p.Top < best) { best = p.Top; bp = p; }
            if (y + SH >= best)
            {
                y = best - SH; vx = 0; vy = 0;
                if (bp != null) SetSupport(bp); else supH = IntPtr.Zero;
                if (sleepMode) GoSleep();
                else if (dizzyOnLand) { dizzyOnLand = false; SetState("dizzy", 1.6); }
                else if (fetching && ballOn) SetState("fetch", 15);
                else SetState("walk", R(2, 5));
            }
        }

        void SetSupport(Plat p) { supH = p.H; supL = p.Left; supR = p.Right; supWinL = p.WinLeft; }

        // 站著的那個視窗被拖動 → 跟著走
        void FollowFast()
        {
            if (supH == IntPtr.Zero || !Grounded()) return;
            W.RECT r;
            if (!W.IsWindowVisible(supH) || W.IsIconic(supH) || !W.Rect(supH, out r)) { Jump(0, 0); Say("哇！地板不見了", 1.2); return; }
            int dl = r.L - supWinL;
            if (dl != 0) { x += dl; supL += dl; supR += dl; supWinL = r.L; }
            y = r.T - SH;
        }

        // ---- 拖曳 ----
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left || state == "glass" || state == "peek") return;
            Point p = Cursor.Position;
            if (p.X < x - 6 || p.X > x + SW + 6 || p.Y < y - 6 || p.Y > y + SH + 6) return;
            dragging = true; dragSaid = false; dragStart = p; dragMoved = 0;
            grabDx = p.X - x; grabDy = p.Y - y;
            lastMx = p.X; lastMy = p.Y; lastMt = clock.Elapsed.TotalSeconds; dvx = dvy = 0;
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (e.Button == MouseButtons.Left && dragging) EndDrag();
        }

        // 回傳 true＝正在拖（不跑一般邏輯）
        bool DragUpdate(double now, double dt)
        {
            if ((Control.MouseButtons & MouseButtons.Left) == 0) { EndDrag(); return false; }
            Point p = Cursor.Position;
            double mdt = now - lastMt;
            if (mdt > 0.001) { dvx = dvx * 0.5 + 0.5 * (p.X - lastMx) / mdt; dvy = dvy * 0.5 + 0.5 * (p.Y - lastMy) / mdt; }
            lastMx = p.X; lastMy = p.Y; lastMt = now;
            dragMoved = Math.Max(dragMoved, Math.Abs(p.X - dragStart.X) + Math.Abs(p.Y - dragStart.Y));
            if (dragMoved <= 6) return false;
            if (state != "drag") { state = "drag"; supH = IntPtr.Zero; sleepMode = false; }
            x = p.X - grabDx; y = p.Y - grabDy;
            anim += dt;
            if (bt > 0) bt -= dt;
            if (!dragSaid) { dragSaid = true; Say("哇啊——放我下來！", 1.5); }
            return true;
        }

        void EndDrag()
        {
            dragging = false;
            if (state != "drag")
            {
                Pat();
                return;
            }
            if (InNest(x + SW / 2.0, y + SH / 2.0))
            {
                // 放進窩裡
                Rectangle n = Nest();
                x = Clamp(x, n.Left + 4, n.Right - 4 - SW);
                bool was = caged;
                caged = true; SaveNest();
                Jump(0, 0);
                if (!was) Say(dark ? "……好，我待在窩裡。你也早點回家。" : "好～我在窩裡乖乖待著 ♥", 2.2);
                AddHeart();
                return;
            }
            if (caged) { caged = false; SaveNest(); Say(dark ? "……放我出來了？那我要去催你下班了。" : "自由了！", 1.4); }
            double lim = 2200 * k;
            Jump(Clamp(dvx, -lim, lim), Clamp(dvy, -lim, lim));
            if (Math.Abs(dvx) + Math.Abs(dvy) > 900 * k) Say("咻——", 0.9);
        }

        // ---- 選單 ----
        ContextMenuStrip BuildMenu()
        {
            ContextMenuStrip m = new ContextMenuStrip();
            m.Items.Add("抱抱 ♥", null, delegate { Act("hug"); });
            m.Items.Add("打招呼", null, delegate { Act("hi"); });
            m.Items.Add("敲敲螢幕", null, delegate { Act("knock"); });
            m.Items.Add("噴絲擺盪", null, delegate { Act("swing"); });
            m.Items.Add("倒吊", null, delegate { Act("hang"); });
            m.Items.Add("跳到別的視窗上", null, delegate { Act("jump"); });
            m.Items.Add("去爬牆", null, delegate { Act("climb"); });
            m.Items.Add("睡覺", null, delegate { Act("sleep"); });
            m.Items.Add("丟球給他 ⚾", null, delegate { Act("ball"); });
            m.Items.Add("我們的感情 ♥", null, delegate { Act("bond"); });
            m.Items.Add("躲起來（Ctrl+Alt+S）", null, delegate { Act("hide"); });
            ToolStripItem nestItem = m.Items.Add("回窩裡待著", null, delegate { Act(caged ? "free" : "nest"); });
            m.Opening += delegate { nestItem.Text = caged ? "出去玩（離開窩）" : "回窩裡待著"; };
            m.Items.Add(new ToolStripSeparator());
            m.Items.Add("收工（關掉桌面版）", null, delegate { QuitAll(); });
            return m;
        }

        // 選單、VS Code 指令、測試共用（pipe 訊息 "act <名稱>"）
        void Act(string a)
        {
            if (a != "sleep") WakeIfSleep();
            switch (a)
            {
                case "hi":
                    if (Grounded()) Jump(0, -260 * k);
                    Say(dark ? "……嗨。下班了嗎？" : "嗨！我是你的 Spidey 👋", 2.4);
                    break;
                case "hug": Hug(Pick(HUGS, HUGS_D), 2.4); break;
                case "pat": Pat(); break;
                case "ball": StartBall(); break;
                case "bond": ShowBond(); break;
                case "hide": ToggleHide(); break;
                case "fireworks": Celebrate("dev"); break;
                case "nest": if (!caged) GoNest(true); break;
                case "free": if (caged) LeaveNest(); break;
                case "knock": StartGlass(Pick(KNOCK, KNOCK_D)); break;
                case "swing": if (!ShootTo("swing")) Say(caged ? "我在窩裡，先把我放出去～" : "這裡太低了，甩不起來", 1.6); break;
                case "hang": if (!ShootTo("hang")) Say(caged ? "我在窩裡，先把我放出去～" : "上面沒地方黏", 1.6); break;
                case "jump": if (!JumpToPlatform()) Say(caged ? "我在窩裡，先把我放出去～" : "附近沒有可以跳的視窗", 1.6); break;
                case "climb":
                    if (caged) { Say("我在窩裡，先把我放出去～", 1.6); break; }
                    if (Grounded()) { goClimb = true; double cx = x + SW / 2.0; Rectangle wa = WA(cx, y); dir = cx < (wa.Left + wa.Right) / 2.0 ? -1 : 1; SetState("walk", 30); }
                    break;
                case "sleep": if (Grounded()) { GoSleep(); t = 8; Say(dark ? "……你也該睡了。" : "晚安…", 1.2); } break;
                case "dark": forceDark = 1; darkChecked = -1; CheckDark(); break;
                case "light": forceDark = 0; darkChecked = -1; CheckDark(); break;
                case "auto": forceDark = -1; darkChecked = -1; CheckDark(); break;
            }
        }
        int forceDark = Environment.GetEnvironmentVariable("SPIDEY_FORCE_DARK") == "1" ? 1 : -1;
        bool DarkNow() { return forceDark >= 0 ? forceDark == 1 : IsDarkTime(DateTime.Now); }

        // ================= 掃描視窗 =================
        void Scan(double now)
        {
            screens = Screen.AllScreens;
            HashSet<IntPtr> own = new HashSet<IntPtr>();
            own.Add(Handle);
            if (bubbleForm.IsHandleCreated) own.Add(bubbleForm.Handle);
            foreach (CobwebForm wf in webs) if (wf.IsHandleCreated) own.Add(wf.Handle);
            if (nestForm != null && nestForm.IsHandleCreated) own.Add(nestForm.Handle);
            if (ballForm != null && ballForm.IsHandleCreated) own.Add(ballForm.Handle);
            if (fx != null && fx.IsHandleCreated) own.Add(fx.Handle);
            if (nestNet != null && nestNet.IsHandleCreated) own.Add(nestNet.Handle);

            List<WinInfo> nw = new List<WinInfo>();
            Dictionary<IntPtr, WinInfo> nc = new Dictionary<IntPtr, WinInfo>();
            bool shareFound = false;
            StringBuilder title = new StringBuilder(256);
            W.EnumWindows(delegate(IntPtr h, IntPtr l)
            {
                if (own.Contains(h) || !W.IsWindowVisible(h) || W.IsIconic(h)) return true;
                int cloaked;
                if (W.DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;
                W.RECT r;
                if (!W.Rect(h, out r) || r.R - r.L < 4 || r.B - r.T < 4) return true;
                int ex = W.GetWindowLong(h, -20);
                bool titled = W.GetWindowTextLength(h) > 0;
                if (titled && !shareFound) { title.Length = 0; W.GetWindowText(h, title, 256); if (IsShareTitle(title.ToString())) shareFound = true; }
                if ((ex & 0x20) != 0) return true;                 // 點擊穿透的覆蓋層不算
                if ((ex & 0x80000) != 0 && !titled) return true;   // 沒標題的透明層（各種 overlay）不算
                WinInfo w = new WinInfo();
                w.H = h; w.L = r.L; w.T = r.T; w.R = r.R; w.B = r.B; w.Z = nw.Count;
                nw.Add(w);
                if ((ex & 0x80) == 0 && titled && r.R - r.L >= 160 && r.B - r.T >= 80) nc[h] = w;
                return true;
            }, IntPtr.Zero);

            List<Plat> np = new List<Plat>();
            foreach (WinInfo w in nc.Values)
            {
                Rectangle wa = WA((w.L + w.R) / 2.0, w.T + 1);
                if (w.T - wa.Top < SH + 4 || w.T >= wa.Bottom - 4) continue;
                List<int[]> segs = new List<int[]>();
                segs.Add(new int[] { Math.Max(w.L, wa.Left) + 4, Math.Min(w.R, wa.Right) - 4 });
                for (int i = 0; i < w.Z && segs.Count > 0; i++)
                {
                    WinInfo f = nw[i];
                    if (f.T <= w.T - 1 && f.B > w.T - 1) segs = Cut(segs, f.L, f.R);
                }
                foreach (int[] s in segs)
                    if (s[1] - s[0] >= SW) { Plat p = new Plat(); p.H = w.H; p.Top = w.T; p.Left = s[0]; p.Right = s[1]; p.WinLeft = w.L; np.Add(p); }
            }
            wins = nw; cands = nc; plats = np;
            if (shareFound != sharing)
            {
                sharing = shareFound;
                if (!sharing && !userHidden && !fsNow) Say("分享結束了～我回來囉", 2);
                ApplyHidden();
            }

            // 站的那段被別的視窗蓋住 → 掉下來
            if (supH != IntPtr.Zero && Grounded())
            {
                Plat best = null;
                double cx = x + SW / 2.0;
                foreach (Plat p in plats) if (p.H == supH && cx >= p.Left - 2 && cx <= p.Right + 2) { best = p; break; }
                if (best == null) Jump(0, 0); else { supL = best.Left; supR = best.Right; }
            }

            // 新視窗／對話框跳出來 → 噴絲黏上去
            if (known == null) known = new HashSet<IntPtr>(nc.Keys);
            else
            {
                WinInfo fresh = null;
                foreach (KeyValuePair<IntPtr, WinInfo> kv in nc) if (!known.Contains(kv.Key)) { known.Add(kv.Key); fresh = kv.Value; }
                known.RemoveWhere(delegate(IntPtr h) { return !nc.ContainsKey(h); });
                if (fresh != null && newWinCd <= 0 && !hidden && !dragging) ReactNewWindow(fresh);
            }

            // 你切到哪個視窗，他常常跟過去
            IntPtr fgw = W.GetForegroundWindow();
            if (fgw != lastFg)
            {
                lastFg = fgw;
                WinInfo fw;
                if (fgCd <= 0 && !hidden && !dragging && cands.TryGetValue(fgw, out fw) && rnd.NextDouble() < 0.55)
                    if (ZipToWindow(fw, AppLine(fgw))) fgCd = R(20, 40);
            }

            SystemActivity(now);
            CheckDark();
            UpdateWebs(now);
            FullscreenCheck(own);
            W.KeepOnTop(this);
            UpdateNest(); // 決定網子在他前面還是後面，最後把泡泡放最上面
        }

        // 整台電腦的鍵盤滑鼠：太久沒動 → 睡覺；回來 → 敲螢幕迎接；連續用太久 → 提醒休息
        void SystemActivity(double now)
        {
            double idle = W.IdleSeconds();
            if (!sysIdle && idle > idleMin * 60)
            {
                sysIdle = true;
                sleepMode = true;
                if (Grounded() && state != "hug" && state != "glass") GoSleep();
            }
            else if (sysIdle && idle < 2)
            {
                sysIdle = false;
                sessionStart = now;
                bool was = state == "sleep";
                WakeIfSleep();
                if (was) StartGlass(dark ? "……你回來了。是要來關機的吧？" : "你回來啦！我等你好久 ♥");
            }
            if (!sysIdle && now - sessionStart >= restMin * 60)
            {
                sessionStart = now;
                WakeIfSleep();
                Hug(dark ? "連續 " + restMin + " 分鐘了。站起來。然後下班。" : "已經連續用 " + restMin + " 分鐘了，起來喝水伸展一下吧 🥤", 8);
            }
        }

        void CheckDark()
        {
            DateTime n = DateTime.Now;
            if (n.Minute == darkChecked) return;
            darkChecked = n.Minute;
            seasonNow = Season();
            bool d = DarkNow();
            if (d == dark) return;
            dark = d;
            if (d) { sense = 2.5; StartGlass("……下班時間到了。"); }
            else Say("早安，我又變回來了 ☀", 3);
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

        void ReactNewWindow(WinInfo w)
        {
            if (!Grounded() || sleepMode || state == "hug") return;
            newWinCd = 6; fgCd = Math.Max(fgCd, 6);
            if (!ZipToWindow(w, Pick(NEWWIN, NEWWIN_D))) Say("有新視窗！👀", 1.5);
        }

        // ---- 蜘蛛網 ----
        void SpinWeb(IntPtr h, bool right)
        {
            WinInfo w;
            if (!cands.TryGetValue(h, out w)) return;
            double edge = right ? supR : supL, corner = right ? w.R : w.L;
            if (Math.Abs(edge - corner) > 12) return; // 只在真正的視窗角落織
            AddWeb(h, right);
            SetState("idle", 1.4);
            Say("在這裡織個網～", 1.6);
        }

        void AddWeb(IntPtr h, bool right)
        {
            foreach (CobwebForm f in webs) if (f.H == h && f.RightCorner == right) return;
            if (webs.Count >= 4) { webs[0].Close(); webs.RemoveAt(0); }
            CobwebForm web = new CobwebForm(h, right, (int)(34 * k), Math.Max(1, (int)Math.Round(k)), clock.Elapsed.TotalSeconds);
            webs.Add(web);
            PlaceWeb(web);
        }

        void PlaceWeb(CobwebForm f)
        {
            WinInfo w = null;
            bool ok = !hidden && cands.TryGetValue(f.H, out w);
            if (ok)
            {
                int px = f.RightCorner ? w.R - f.Side : w.L, py = w.T;
                ok = PointVisible(w, f.RightCorner ? w.R - 3 : w.L + 3, w.T + 3);
                if (ok)
                {
                    Rectangle nb = new Rectangle(px, py, f.Side, f.Side);
                    if (f.Bounds != nb) f.Bounds = nb;
                    if (!f.Visible) f.Show();
                    W.KeepOnTop(f);
                }
            }
            if (!ok && f.Visible) f.Hide();
        }

        void UpdateWebs(double now)
        {
            for (int i = webs.Count - 1; i >= 0; i--)
            {
                CobwebForm f = webs[i];
                bool gone = now - f.Born > 150 || (!cands.ContainsKey(f.H) && !W.IsWindowVisible(f.H));
                if (gone) { f.Close(); webs.RemoveAt(i); continue; }
                PlaceWeb(f);
            }
        }

        // 全螢幕簡報／影片時自動躲起來
        void FullscreenCheck(HashSet<IntPtr> own)
        {
            IntPtr fg = W.GetForegroundWindow();
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

        // ================= 螢幕幾何 =================
        Rectangle WA(double px, double py)
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

        bool Inside(double px, double py)
        {
            foreach (Screen s in screens) if (s.WorkingArea.Contains((int)px, (int)py)) return true;
            return false;
        }

        // ================= 畫 =================
        void Grow(ref double l, ref double tp, ref double r, ref double b, double px, double py)
        {
            l = Math.Min(l, px); r = Math.Max(r, px); tp = Math.Min(tp, py); b = Math.Max(b, py);
        }

        bool SilkVisible() { return state == "swing" || state == "hang" || state == "zip" || state == "shoot"; }

        void Render()
        {
            double l = x, tp = y, r = x + SW, b = y + SH;
            if (sc > 1) { double cxs = x + SW / 2.0; l = cxs - SW * sc / 2; r = cxs + SW * sc / 2; tp = y + SH - SH * sc - 4 * k; }
            if (SilkVisible()) Grow(ref l, ref tp, ref r, ref b, ax, ay);
            if (state == "sleep") { r = Math.Max(r, x + SW + 26 * k); tp = Math.Min(tp, y - 36 * k); }
            if (sense > 0) { l = Math.Min(l, x + SW / 2.0 - 50 * k); r = Math.Max(r, x + SW / 2.0 + 50 * k); tp = Math.Min(tp, y - 14 * k); }
            if (hearts.Count > 0) { l = Math.Min(l, x - 14 * k); r = Math.Max(r, x + SW + 14 * k); tp = Math.Min(tp, y - 90 * k); }
            foreach (double[] sp in sparks) Grow(ref l, ref tp, ref r, ref b, sp[0], sp[1]);
            foreach (double[] f in flakes) Grow(ref l, ref tp, ref r, ref b, f[0], f[1]);
            tp = Math.Min(tp, (sc > 1 ? y + SH - SH * sc - 5 * S * sc : y - 5 * S) - Bob()); // 帽子
            int pad = 6 + (int)(5 * k) + 3 * S;                    // 紅包、蛋糕在身體旁邊
            Rectangle nb = Rectangle.FromLTRB((int)Math.Floor(l) - pad, (int)Math.Floor(tp) - pad, (int)Math.Ceiling(r) + pad, (int)Math.Ceiling(b) + pad);
            PresentFrame(nb);
            UpdateBubble();
            if (nestForm != null && (dragging || (lockVal > 0 && lockVal < 1))) UpdateNest();
        }

        void UpdateBubble()
        {
            if (bt <= 0 || string.IsNullOrEmpty(bubble)) { if (bubbleForm.Visible) bubbleForm.Hide(); return; }
            Size sz = bubbleForm.Measure(bubble, bubbleAlert, dark);
            Rectangle wa = WA(x + SW / 2.0, y + SH / 2.0);
            double above = y + SH - SH * sc - (state == "sleep" ? 30 * k : 0) - (hearts.Count > 0 ? 24 * k : 0);
            int bx = (int)(x + SW / 2.0 - sz.Width / 2.0), by = (int)(above - sz.Height - 2);
            if (state == "hang" && hangPhase == 1) by = (int)(y + SH + 6);
            bx = Math.Max(wa.Left, Math.Min(wa.Right - sz.Width, bx));
            by = Math.Max(wa.Top, Math.Min(wa.Bottom - sz.Height, by));
            Rectangle nb = new Rectangle(bx, by, sz.Width, sz.Height);
            if (bubbleForm.Bounds != nb) bubbleForm.Bounds = nb;
            if (!bubbleForm.Visible) { bubbleForm.Show(); W.KeepOnTop(bubbleForm); }
        }

        string[] Frame()
        {
            bool sleep = state == "sleep", hug = state == "hug";
            bool armsUp = state == "glass" || state == "tug" || state == "kick" || (state == "dance" && Math.Floor(anim * 4) % 2 == 0) || state == "swing" || state == "air" || state == "climb" || state == "drag" || state == "shoot" || state == "zip"
                || (state == "hang" && hangPhase == 0) || (state == "idle" && bt > 0);
            bool step = ((state == "walk" || state == "climb") && Math.Floor(anim * 6) % 2 == 1)
                || (state == "seek" && Math.Floor(anim * 11) % 2 == 1)
                || (state == "drag" && Math.Floor(anim * 12) % 2 == 1)
                || (state == "fetch" && Math.Floor(anim * 11) % 2 == 1)
                || (state == "dance" && Math.Floor(anim * 4) % 2 == 1);
            List<string> rows = new List<string>(HEAD);
            string[] face = sleep ? SLEEPY : (hug ? HAPPY : (state == "dizzy" ? DIZZY : null));
            if (face != null) { rows[4] = face[0]; rows[5] = face[1]; rows[6] = face[2]; }
            else
            {
                // 眼睛跟著滑鼠
                Point cp = Cursor.Position;
                double dx = cp.X - (x + SW / 2.0);
                int off = state == "glass" ? 0 : (dx < -30 ? -1 : (dx > 30 ? 1 : 0));
                if (dir < 0) off = -off; // 圖會左右翻，先反過來
                char[] e5 = rows[5].ToCharArray();
                e5[3 + off] = 'k'; e5[8 + off] = 'k';
                rows[5] = new string(e5);
            }
            rows.AddRange(hug ? ARMS_HUG : (armsUp ? ARMS_UP : BODY));
            rows.AddRange(step ? LEGS_B : LEGS_A);
            if (dark && !hug)
            {
                char[] chest = rows[10].ToCharArray();
                if (chest[5] == 'k' && chest[6] == 'k') { chest[5] = 'w'; chest[6] = 'w'; rows[10] = new string(chest); }
            }
            if (!hug && Level() >= 5)
            {
                char[] chest = rows[10].ToCharArray();
                if (chest[5] != 'r' && chest[6] != 'r') { chest[5] = 'Y'; chest[6] = 'Y'; rows[10] = new string(chest); } // 金色胸章
            }
            return rows.ToArray();
        }

        void DrawPix(Graphics g, string[] rows, int bx, int by, int ps, bool fx, bool fy, bool withHalo)
        {
            Dictionary<char, SolidBrush> pal = dark ? brDark : br;
            SolidBrush hb = dark ? haloDark : halo;
            int hw = Math.Max(1, ps / 3);
            int h = rows.Length;
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
                        else g.FillRectangle(pal[c], px, py, ps, ps);
                    }
                }
        }

        void DrawAcc(Graphics g, string[] art, int col, int row, int bx0, int by0, int ps, bool fx, bool fy, bool withHalo)
        {
            int aw = art[0].Length, ah = art.Length;
            int c = fx ? 12 - col - aw : col, r = fy ? 16 - row - ah : row;
            DrawPix(g, art, bx0 + c * ps, by0 + r * ps, ps, fx, fy, withHalo);
        }

        void DrawAccessories(Graphics g, int bx0, int by0, int ps, bool fx, bool fy)
        {
            int lv = Level();
            bool normalFace = state != "sleep" && state != "hug" && state != "dizzy";
            if (lv >= 2) DrawAcc(g, SCARF, 0, 8, bx0, by0, ps, fx, fy, false);
            if (lv >= 4 && normalFace) DrawAcc(g, GLASSES, 0, 4, bx0, by0, ps, fx, fy, false);
            string[] hat = seasonNow == "xmas" ? SANTA : (lv >= 6 ? CROWN : (lv >= 3 ? BEANIE : null));
            if (hat != null) DrawAcc(g, hat, 0, -hat.Length, bx0, by0, ps, fx, fy, true);
            if (seasonNow == "cny") DrawAcc(g, ENVELOPE, 11, 9, bx0, by0, ps, fx, fy, true);
            if (seasonNow == "birthday") DrawAcc(g, CAKE, 11, 8, bx0, by0, ps, fx, fy, true);
        }

        protected override void OnPaint(PaintEventArgs e) { }            // 畫面全由 UpdateLayeredWindow 提供
        protected override void OnPaintBackground(PaintEventArgs e) { }

        Bitmap frameBmp;
        void PresentFrame(Rectangle nb)
        {
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
            W.Present(this, frameBmp, nb.X, nb.Y);
        }

        void PaintPet(Graphics g, int ox, int oy)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias; // 絲線平滑；像素格都是整數座標的方塊，不受影響
            int lw = Math.Max(2, (int)Math.Round(1.5 * k));

            if (SilkVisible())
            {
                double hx = x + SW / 2.0 - ox, hy = y + 3 * k - oy, axo = ax - ox, ayo = ay - oy;
                if (state == "shoot")
                {
                    double p = Math.Min(1, shootT / 0.18);
                    axo = hx + (axo - hx) * p; ayo = hy + (ayo - hy) * p;
                }
                using (Pen silk = new Pen(dark ? Color.FromArgb(0x6A, 0x5F, 0x9E) : Color.FromArgb(0x9A, 0xA3, 0xBC), lw))
                using (Pen core = new Pen(dark ? Color.FromArgb(0x14, 0x14, 0x1C) : Color.FromArgb(0x4A, 0x52, 0x6E), Math.Max(1, lw / 2)))
                {
                    g.DrawLine(silk, (float)hx, (float)hy, (float)axo, (float)ayo);
                    g.DrawLine(core, (float)hx, (float)hy, (float)axo, (float)ayo);
                    if (state != "shoot" || shootT >= 0.18)
                    {
                        // 黏住的地方：一小團絲
                        float s = (float)(5 * k), cxs = (float)axo, cys = (float)ayo;
                        g.DrawLine(silk, cxs - s, cys, cxs + s, cys);
                        g.DrawLine(silk, cxs, cys - s, cxs, cys + s);
                        g.DrawLine(silk, cxs - s * .7f, cys - s * .7f, cxs + s * .7f, cys + s * .7f);
                        g.DrawLine(silk, cxs - s * .7f, cys + s * .7f, cxs + s * .7f, cys - s * .7f);
                    }
                }
            }

            bool fy = state == "hang" && hangPhase == 1;
            int sbx, sby, sps; bool sfy;
            if (sc > 1.001)
            {
                sps = (int)Math.Round(S * sc);
                double shake = knock > 0 ? -3 * k : 0;
                sbx = (int)Math.Round(x + SW / 2.0 - 6 * sps) - ox; sby = (int)Math.Round(y + SH - 16 * sps + shake) - oy; sfy = false;
            }
            else { sps = S; sbx = (int)Math.Round(x) - ox; sby = (int)Math.Round(y - Bob()) - oy; sfy = fy; }
            DrawPix(g, Frame(), sbx, sby, sps, dir < 0, sfy, true);
            DrawAccessories(g, sbx, sby, sps, dir < 0, sfy);
            int fps = Math.Max(1, S / 3);
            foreach (double[] f in flakes) DrawPix(g, FLAKE, (int)f[0] - ox - fps, (int)f[1] - oy - fps, fps, false, false, false);

            if (sense > 0 && !fy)
            {
                using (Pen p = new Pen(dark ? Color.FromArgb(0x9B, 0x7B, 0xFF) : Color.FromArgb(0xC9, 0x54, 0x54), (float)(2 * k)))
                {
                    double cx = x + SW / 2.0 - ox, cy = y + 10 * k - oy, wob = Math.Sin(anim * 30) * 1.5 * k;
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
            int ssz = Math.Max(2, S / 2);
            foreach (double[] sp in sparks)
                if (sp[4] < 0.6 || Math.Floor(sp[4] * 20) % 2 == 0) // 快消失時閃一閃
                    DrawPix(g, STAR, (int)(sp[0] - 1.5 * ssz) - ox, (int)(sp[1] - 1.5 * ssz) - oy, ssz, false, false, false);
            foreach (double[] h in hearts)
            {
                double age = h[1];
                int hx = (int)(x + SW / 2.0 + h[0] + Math.Sin(age * 6 + h[0]) * 3 * k - 3.5 * hp) - ox;
                int hy = (int)(y - 8 * k - age * 45 * k - 6 * hp) - oy;
                DrawPix(g, HEART, hx, hy, hp, false, false, true);
            }
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

        void Post(Action a)
        {
            try { if (!closing && !IsDisposed) BeginInvoke(a); } catch { }
        }

        // 獨立運作：沒有 VS Code 連線也不會結束，只有「收工」才關
        bool CheckClients(double now) { return false; }


        void OnMsg(Client c, string line)
        {
            string[] p = line.Trim().Split(' ');
            switch (p[0])
            {
                case "hello": break;
                case "save":
                    if (saveXpCd <= 0) { saveXpCd = 120; AddXp(1); }
                    WakeIfSleep();
                    Say(Pick(SAVE, SAVE_D), 2);
                    if (Grounded()) Jump(0, -300 * k);
                    break;
                case "errors":
                    int n = 0, prev = 0;
                    if (p.Length >= 3) { int.TryParse(p[1], out n); int.TryParse(p[2], out prev); }
                    if (n > prev)
                    {
                        WakeIfSleep();
                        sense = 2.8;
                        Say(dark ? n + " 個錯誤……明天再修，回家。" : "蜘蛛感應！有 " + n + " 個錯誤", 3, true);
                        if (state == "walk") SetState("idle", 3);
                    }
                    else if (n == 0) { WakeIfSleep(); AddXp(2); Hug(dark ? "錯誤清完了。那就可以下班了吧。" : "錯誤都清光了，抱一個！", 2.6); }
                    break;
                case "config":
                    double rm, im;
                    if (p.Length >= 3 && double.TryParse(p[1], out rm) && double.TryParse(p[2], out im)) { restMin = Math.Max(1, rm); idleMin = Math.Max(1, im); }
                    break;
                case "hi": Act("hi"); break;
                case "claude": if (p.Length >= 2) OnClaude(p[1], p.Length >= 3 ? p[2] : "x"); break;
                case "tag": Celebrate(p.Length >= 3 ? p[2] : ""); break;
                case "birthday": birthday = p.Length >= 2 ? p[1].Trim() : ""; seasonNow = Season(); break;
                case "typing":
                    int chars;
                    if (p.Length >= 2 && int.TryParse(p[1], out chars))
                    {
                        typingStreak = chars >= 30 ? typingStreak + 1 : 0;
                        if (typingStreak >= 2 && danceCd <= 0 && Grounded() && state != "hug" && state != "sleep" && !hidden)
                        {
                            danceCd = 150;
                            SetState("dance", 4);
                            Say(dark ? "打這麼快是想快點下班吧？加油。" : Pick(new string[] { "你打字好快！加油加油 ♪", "手指在冒煙了！🔥", "衝衝衝～我幫你打氣！" }), 2.5);
                        }
                    }
                    break;
                case "act": if (p.Length >= 2) Act(p[1]); break;
                case "where":
                    try { byte[] b = Encoding.UTF8.GetBytes("pos " + (int)x + " " + (int)y + " " + state + " " + (dark ? "dark" : "light") + " " + plats.Count + "\n"); c.S.Write(b, 0, b.Length); c.S.Flush(); } catch { }
                    break;
                case "quit": QuitAll(); break;
            }
        }

        void QuitAll()
        {
            byte[] bye = Encoding.UTF8.GetBytes("bye\n");
            lock (clients)
            {
                foreach (Client c in clients) { try { c.S.Write(bye, 0, bye.Length); c.S.Flush(); } catch { } }
            }
            Close();
        }
    }
}
