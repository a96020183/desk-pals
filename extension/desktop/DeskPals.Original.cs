// Desk Pals：續命小隊（躲躲・沒電・刺刺）——原創角色。新安裝的預設一櫃，也是對外宣傳用的門面。
// 躲躲＝住在網購紙箱裡的害羞小傢伙（被嚇就縮回箱子、被發現就讓箱子長腳逃跑）、
// 沒電＝一顆很累的電池（身體裡的電量跟你的工作時間連動：一直工作就掉、休息就充，充電時是綠的）、
// 刺刺＝嘴硬心軟的盆栽仙人掌（被拆穿就開花、生氣就炸毛）。
// 圖是一張一張的 PNG（extension/desktop/pals/squad/<id>/<1x|2x>/<動作>.png，tools/squad_art 產生），用「自己做的公仔」那套畫法（DeskPals.Custom.cs 的 CuDraw）。
// 2026-11 以前的像素版續命小隊（半糖・醒醒・糰糰・貼貼）在 git 歷史裡；舊資料（好感度、櫃子、最愛）第一次啟動時轉給新三隻（OrigMigrate）。
// desk-pals.ps1 會把 DeskPals.cs 和 DeskPals.*.cs 接在一起編譯；這個檔的 using 放在 namespace 裡面，接起來才合法。
// Mac 對應：mac/src/51_original.swift（逐行對照）。
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.Drawing;
    using System.Drawing.Drawing2D;
    using System.Drawing.Imaging;
    using System.IO;
    using System.Windows.Forms;

    // desk-pals.ps1（Add-Type 沒有實體路徑）在 Run 之前設 [DeskPals.SqAssets]::Root；exe 讀內嵌的資源；也可以用環境變數 DESKPALS_ASSETS
    public static class SqAssets { public static string Root = ""; }

    // ================= 圖：讀 pals/squad =================
    static class SqArt
    {
        public static readonly string[] Keys = { "stand", "walk1", "walk2", "jump", "sleep", "happy", "held", "sit", "grab", "push", "cry", "blown", "sig1", "sig2", "surprised", "pout" };

        static string Root()
        {
            foreach (string d in new string[] { SqAssets.Root, Environment.GetEnvironmentVariable("DESKPALS_ASSETS"), Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "pals") })
                if (!string.IsNullOrEmpty(d) && File.Exists(Path.Combine(d, Path.Combine("squad", "squad.txt")))) return d;
            return "";
        }

        // 讀一個檔：資料夾有就讀資料夾，沒有就讀 exe 內嵌的資源（build.ps1 用 /resource 放進去，名字＝pals/squad/…、pals/shelf/…）
        public static byte[] Read(string rel)
        {
            string root = Root();
            try
            {
                if (root != "") { string f = Path.Combine(root, rel.Replace('/', Path.DirectorySeparatorChar)); if (File.Exists(f)) return File.ReadAllBytes(f); }
                using (Stream s = System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream("pals/" + rel))
                {
                    if (s == null) return null;
                    using (MemoryStream ms = new MemoryStream()) { s.CopyTo(ms); return ms.ToArray(); }
                }
            }
            catch { return null; }
        }

        public static Bitmap Png(string rel)
        {
            byte[] b = Read(rel);
            if (b == null) return null;
            try
            {
                using (MemoryStream ms = new MemoryStream(b))
                using (Image img = Image.FromStream(ms, false, true))
                {
                    Bitmap o = new Bitmap(img.Width, img.Height, PixelFormat.Format32bppArgb);
                    using (Graphics g = Graphics.FromImage(o)) { g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy; g.DrawImage(img, new Rectangle(0, 0, img.Width, img.Height)); }
                    return o;
                }
            }
            catch { return null; }
        }

        // 100% 縮放（一格 4 px）用 1x，其他都用 2x（跟自己做的公仔一樣一格 8 個內部像素）
        public static int Res()
        {
            try { using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) return Math.Round(4 * g.DpiX / 96.0) <= 4 ? 1 : 2; }
            catch { return 2; }
        }

        public static CuSprite Load(string id)
        {
            int r = Res();
            CuSprite s = Load(id, r);
            if (s == null && r == 1) s = Load(id, 2);
            if (s == null) { App.LogAlways("squad art missing: " + id + " (root=" + Root() + ")"); s = Placeholder(); }
            return s;
        }

        static CuSprite Load(string id, int r)
        {
            byte[] meta = Read("squad/squad.txt");
            if (meta == null) return null;
            int[] m = null;
            foreach (string line in System.Text.Encoding.UTF8.GetString(meta).Split('\n'))
            {
                string[] a = line.Trim().Split(' ');
                if (a.Length < 8 || a[0] != id || a[1] != r.ToString()) continue;
                m = new int[8];
                for (int i = 0; i < 8 && i + 2 < a.Length; i++) int.TryParse(a[i + 2], out m[i]);
            }
            if (m == null) return null;
            CuSprite s = new CuSprite();
            s.Pixel = false; s.R = r == 1 ? 4 : 8; s.Rig = false; s.NoHalo = true;
            foreach (string k in Keys)
            {
                Bitmap b = Png("squad/" + id + "/" + r + "x/" + k + ".png");
                if (b == null) { s.Dispose(); return null; }
                s.Frames[k] = b;
            }
            s.Stand = s.Frames["stand"]; s.W = s.Stand.Width; s.H = s.Stand.Height;
            s.AnchorX = m[2]; s.AnchorY = m[3] + 1; s.BodyTop = m[4]; s.BodyH = m[5];
            if (m[7] > 0) { s.BodyLeft = m[6]; s.BodyW = m[7]; }
            s.HeadTop = s.BodyTop; s.HeadCx = m[2]; s.HeadW = s.W / 4; s.NeckCx = m[2]; s.NeckW = s.W / 4;
            s.Neck = s.BodyTop + s.BodyH / 3; s.Hip = s.BodyTop + s.BodyH * 3 / 4; s.Split = m[2];
            s.Main = id == "duoduo" ? Color.FromArgb(0xD8, 0xA8, 0x6C) : (id == "meidian" ? Color.FromArgb(0xFB, 0xF0, 0xDF) : Color.FromArgb(0x90, 0xC0, 0x78));
            s.Outline = Color.FromArgb(0x1E, 0x1E, 0x24);
            if (id == "meidian")
            {
                s.Liquid = new Dictionary<string, SqLiquid>();
                foreach (string k in Keys)
                {
                    Bitmap mb = Png("squad/" + id + "/" + r + "x/" + k + ".liquid.png");
                    if (mb == null) continue;
                    s.Liquid[k] = SqLiquid.Make(k, CuImg.Pixels(s.Frames[k]), CuImg.Pixels(mb), s.W, s.H);
                    mb.Dispose();
                }
            }
            return s;
        }

        // 圖不見了：畫一個圓圓的佔位，不要當掉
        static CuSprite Placeholder()
        {
            CuSprite s = new CuSprite();
            s.Pixel = false; s.R = 8; s.NoHalo = true;
            Bitmap b = new Bitmap(96, 96, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(b))
            using (SolidBrush f = new SolidBrush(Color.FromArgb(0xE0, 0xD8, 0xC8)))
            using (Pen p = new Pen(Color.FromArgb(0x30, 0x30, 0x30), 4))
            { g.Clear(Color.Transparent); g.FillEllipse(f, 10, 10, 76, 76); g.DrawEllipse(p, 10, 10, 76, 76); }
            foreach (string k in Keys) s.Frames[k] = b;
            s.Stand = b; s.W = 96; s.H = 96; s.AnchorX = 48; s.AnchorY = 88; s.BodyTop = 8; s.BodyH = 80;
            s.HeadTop = 8; s.HeadCx = 48; s.HeadW = 24; s.NeckCx = 48; s.NeckW = 24; s.Neck = 36; s.Hip = 70; s.Split = 48;
            return s;
        }
    }

    // ================= 沒電的電量液體：遮罩＋液面表；執行時重新上色 =================
    class SqLiquid
    {
        public int[] Px;          // 底圖（液體已經清成奶油色）ARGB
        public byte[] Wt;         // 每個像素有多少是液體（0～255）
        public int Wd, Ht;
        public double[] Tab = new double[101];   // 電量 i% 的液面 y（像素，往下為正；液面以下是液體）
        public double Band;       // 液面亮帶的厚度
        public static readonly int[] Cream = { 251, 240, 223 };

        public static SqLiquid Make(string key, int[] px, int[] mask, int w, int h)
        {
            SqLiquid q = new SqLiquid();
            q.Px = px; q.Wd = w; q.Ht = h; q.Wt = new byte[w * h];
            double[] rows = new double[h];
            for (int i = 0; i < w * h && i < mask.Length; i++) { int v = (mask[i] >> 16) & 255; q.Wt[i] = (byte)v; rows[i / w] += v / 255.0; }
            double tot = 0; int top = -1, bot = -1;
            for (int y = 0; y < h; y++) if (rows[y] > 0) { tot += rows[y]; if (top < 0) top = y; bot = y + 1; }
            if (top < 0) { top = 0; bot = 0; }
            // 液面永遠水平：由下往上累積面積，電量 i% 的液面＝下面的面積剛好是 i% 的那一列（列內線性內插）
            for (int i = 0; i <= 100; i++)
            {
                double target = tot * i / 100.0, acc = 0;
                int y = bot;
                while (y > top && acc + rows[y - 1] < target) { acc += rows[y - 1]; y--; }
                double frac = (y <= top || rows[y - 1] <= 0) ? 0 : (target - acc) / rows[y - 1];
                q.Tab[i] = y - frac;
            }
            q.Band = Math.Max(1.0, (bot - top) * (key == "sleep" || key == "sig2" ? 0.10 : 0.06));
            return q;
        }

        // 低電量紅 → 黃 → 綠
        public static double[] Ramp(double L)
        {
            double[][] stops = { new double[] { 0, 232, 58, 50 }, new double[] { 0.20, 232, 58, 50 }, new double[] { 0.35, 245, 178, 35 }, new double[] { 0.55, 245, 178, 35 }, new double[] { 0.70, 76, 192, 56 }, new double[] { 1.0, 76, 192, 56 } };
            for (int i = 1; i < stops.Length; i++)
                if (L <= stops[i][0])
                {
                    double a = stops[i - 1][0], b = stops[i][0], t = b <= a ? 0 : (L - a) / (b - a);
                    return new double[] { stops[i - 1][1] + (stops[i][1] - stops[i - 1][1]) * t, stops[i - 1][2] + (stops[i][2] - stops[i - 1][2]) * t, stops[i - 1][3] + (stops[i][3] - stops[i - 1][3]) * t };
                }
            return new double[] { 76, 192, 56 };
        }

        // 上色：out = 底圖 + 覆蓋率 ×（目標色 − 奶油色）；液面那一列依比例混色（反鋸齒）
        public int[] Render(int pct, double[] col, double pulse)
        {
            double yL = Tab[Math.Max(0, Math.Min(100, pct))];
            double[] c = new double[3], hi = new double[3];
            for (int i = 0; i < 3; i++) { c[i] = Math.Min(255, col[i] * (1 + pulse)); hi[i] = c[i] + (255 - c[i]) * 0.45; }
            int[] o = (int[])Px.Clone();
            for (int y = 0; y < Ht; y++)
            {
                double cov = Math.Max(0, Math.Min(1, y + 1 - yL));
                if (cov <= 0) continue;
                double inb = Math.Max(0, Math.Min(1, yL + Band - y));
                double[] tr = new double[3];
                for (int i = 0; i < 3; i++) tr[i] = Cream[i] * (1 - cov) + (c[i] * (1 - inb) + hi[i] * inb) * cov - Cream[i];
                int row = y * Wd;
                for (int x = 0; x < Wd; x++)
                {
                    int wv = Wt[row + x];
                    if (wv == 0) continue;
                    int v = o[row + x];
                    double f = wv / 255.0;
                    int r = Clamp255(((v >> 16) & 255) + f * tr[0]), g = Clamp255(((v >> 8) & 255) + f * tr[1]), b = Clamp255((v & 255) + f * tr[2]);
                    o[row + x] = (v & unchecked((int)0xFF000000)) | (r << 16) | (g << 8) | b;
                }
            }
            return o;
        }

        static int Clamp255(double v) { return v < 0 ? 0 : (v > 255 ? 255 : (int)Math.Round(v)); }
    }

    // 電量：整台電腦一份（同一個公仔櫃只有一隻沒電；設定視窗的預覽也看得到同一個電量）
    static class SqBattery
    {
        public static double Level = 1;
        public static bool Charging, Link = true;
        public static int Pct { get { return (int)Math.Round(Math.Max(0, Math.Min(1, Level)) * 100); } }
        static readonly Dictionary<string, Bitmap> cache = new Dictionary<string, Bitmap>();
        static double reduceCheck = -100; static bool reduce;

        // 減少動態（系統設定／遠端桌面）：充電不閃
        static bool Reduce()
        {
            double now = Environment.TickCount / 1000.0;
            if (Math.Abs(now - reduceCheck) > 30) { reduceCheck = now; try { reduce = !SystemInformation.UIEffectsEnabled; } catch { reduce = false; } }
            return reduce;
        }

        public static int Phase() { return Charging && !Reduce() ? (int)((Environment.TickCount & 0x7FFFFFFF) % 840 / 105) : 0; }

        public static Bitmap Frame(CuSprite s, string key)
        {
            SqLiquid q;
            if (s.Liquid == null || key == null || !s.Liquid.TryGetValue(key, out q)) return null;
            int pct = Pct, ph = Phase();
            string ck = s.R + "|" + key + "|" + pct + "|" + (Charging ? "c" + ph : "-");
            Bitmap b;
            if (cache.TryGetValue(ck, out b)) return b;
            if (cache.Count > 40) { foreach (Bitmap old in cache.Values) old.Dispose(); cache.Clear(); }
            double[] col = Charging ? new double[] { 76, 192, 56 } : SqLiquid.Ramp(pct / 100.0);
            double pulse = Charging ? 0.10 * Math.Sin(ph / 8.0 * 2 * Math.PI) : 0;
            CuCut c = new CuCut(); c.W = q.Wd; c.H = q.Ht; c.Px = q.Render(pct, col, pulse);
            b = CuImg.ToBitmap(c);
            cache[ck] = b;
            return b;
        }

        // 測試用：某張圖在某個電量的液面 y（跟 tools/squad_art 的 levels.json 對答案）
        public static string Dump(CuSprite s)
        {
            System.Text.StringBuilder sb = new System.Text.StringBuilder();
            sb.Append("battery " + Pct + " charging=" + (Charging ? 1 : 0) + " link=" + (Link ? 1 : 0) + " R=" + (s == null ? 0 : s.R) + "\n");
            if (s != null && s.Liquid != null)
                foreach (KeyValuePair<string, SqLiquid> kv in s.Liquid)
                    sb.Append("level " + kv.Key + " " + kv.Value.Tab[10].ToString("0.00", System.Globalization.CultureInfo.InvariantCulture) + " " + kv.Value.Tab[50].ToString("0.00", System.Globalization.CultureInfo.InvariantCulture) + " " + kv.Value.Tab[90].ToString("0.00", System.Globalization.CultureInfo.InvariantCulture) + "\n");
            sb.Append("end\n");
            return sb.ToString();
        }
    }

    // ================= 角色資料 =================
    partial class Pal
    {
        public bool Orig;                    // 續命小隊
        public const string Original = "original";
        public const string OriginalName = "續命小隊";
        public static readonly string[] OriginalIds = { "duoduo", "meidian", "cici" };
        public static readonly string[] OldOriginalIds = { "boba", "coffee", "onigiri", "sticky" };   // 舊的像素版（資料轉給新三隻）

        static List<Pal> OrigPals() { return new List<Pal>(new Pal[] { Duoduo(), Meidian(), Cici() }); }

        // 這一櫃有誰：三隻＋（做過自己的公仔的話）第 4 格放你的公仔（我的櫃排第一的那隻）
        public static string[] OrigLineupIds()
        {
            List<string> l = new List<string>(OriginalIds);
            foreach (string id in MineIds()) if (CuStore.Get(id) != null) { l.Add(id); break; }
            return l.ToArray();
        }

        // 共用：圖、頭頂超出 16 格的列數、配件不戴
        static Pal OrigBase(string id, string name)
        {
            Pal p = new Pal();
            p.Id = id; p.Name = name; p.Orig = true; p.BallKind = "tennis"; p.Halo = Color.White; p.HaloNight = C(0xC8C0EC); p.EyeRow = -1; p.HatCol = 0; p.NoGlasses = true;
            p.Spr = SqArt.Load(id);
            double hc = p.Spr.BodyH / (double)p.Spr.R;
            p.TopRows = Math.Max(0, (int)Math.Ceiling(hc) - 16);
            p.HeadTop = -p.TopRows;
            p.BodyTop = (int)Math.Round(16 - hc * 0.55);
            p.Day['k'] = C(0x1E1E24); p.Night['k'] = C(0x101018);
            string[] blank = { "............" };
            foreach (string k in new string[] { "HEAD", "BODY", "ARMS_UP", "ARMS_HUG", "LEGS_A", "LEGS_B", "LEGS_SIT", "SLEEPY", "HAPPY", "DIZZY" }) p.Art[k] = blank;
            return p;
        }

        // ---------------- 躲躲：住在網購紙箱裡。好奇又害羞；口頭禪「我不在」----------------
        static Pal Duoduo()
        {
            Pal p = OrigBase("duoduo", "躲躲");
            p.Move = "shuffle"; p.NightStyle = "sleepy"; p.NightBubble = 2;
            p.Accent = C(0xB98A52); p.Panel = C(0xF6E6CF);
            p.Speed = 36;
            p.Say("talk", "（從提手洞看你）……那是什麼", "我不在。這是空箱子。", "易碎品，請輕拿輕放（指我）", "外面好亮…箱子裡剛剛好", "你在打什麼？我只是…路過…在箱子裡路過", "今天的紙箱味道很香", "我有在看喔（縮回去）", "如果我不見了，我在箱子裡");
            p.Say("talk_d", "晚上了，箱子要關門了", "天黑了…你也回自己的箱子吧", "我先睡了，你明天再來拆我", "（箱子裡傳出打呼聲）");
            p.Say("save", "存好了…（小聲）", "存起來了，跟我躲在箱子裡一樣安全", "好…好了，存了");
            p.Say("save_d", "存好了…那可以關燈了嗎", "存了，晚安（關箱子）");
            p.Say("pats", "！！（整個縮進去）", "……再一下", "被摸了…紙箱都暖起來了", "你的手是不是剛洗過，好香", "（從洞裡偷看你）嘿嘿", "摸、摸到我了…");
            p.Say("pats_d", "嗯…可以回家了喔", "摸完我就要關箱子了");
            p.Say("pats_hi", "我…我可以出來一點點了", "你是第一個看到我整隻的人", "箱子外面有你，好像也不錯");
            p.Say("hugs", "抱、抱的話…箱子會凹", "（從箱子伸出兩隻手）", "抱抱…不要拆我喔");
            p.Say("hugs_d", "抱完就關箱子囉", "晚安抱抱…（縮）");
            p.Say("knock", "叩叩…有包裹嗎？", "是在叫我嗎…我不在喔", "（從玻璃後面偷看）");
            p.Say("knock_d", "叩叩…快回家", "（箱子裡小聲）下班了啦");
            p.Say("newwin", "新、新視窗…（躲）", "那是什麼…先偷看一下");
            p.Say("newwin_d", "又開新的…明天再看好不好");
            p.Say("hi", "嗨…我是躲躲，平常住在箱子裡"); p.Say("hi_d", "嗨…天黑了，箱子要關了");
            p.Say("wake", "……（偷看）你回來了"); p.Say("wake_d", "……還沒下班嗎");
            p.Say("dizzy", "箱子在轉…我也在轉…"); p.Say("dizzy_d", "暈…想回箱子…");
            p.Say("dizzy_ok", "好了…箱子停了"); p.Say("dizzy_ok_d", "好了…回家吧");
            p.Say("tickle", "嘻嘻嘻不要戳箱子", "好癢！要縮進去了！", "（箱子在抖）"); p.Say("tickle_d", "最後一次喔…");
            p.Say("pat10", "今天第 {n} 次了…我出來一點點了"); p.Say("pat10_d", "第 {n} 次了…晚安");
            p.Say("levelup", "好感度 Lv{n}！拿到「{u}」…可以放箱子裡嗎"); p.Say("levelup_d", "Lv{n}…「{u}」明天再戴");
            p.Say("missed", "你好久沒來了…我以為你搬家了"); p.Say("missed_d", "好久沒來了…明天要來喔");
            p.Say("hover", "游標靠太近了…（縮）", "嗨…（只露眼睛）");
            p.Say("seek", "那是什麼…？"); p.Say("seek_lost", "跑掉了…還好"); p.Say("seek_got", "抓、抓到了！要收進箱子嗎");
            p.Say("drag", "箱子要倒了箱子要倒了"); p.Say("throw", "我是易碎品啊啊啊——");
            p.Say("shelf_in", "回箱子…不是，回櫃子"); p.Say("shelf_in_d", "回去睡了…");
            p.Say("shelf_out", "（箱子慢慢走出來）"); p.Say("shelf_out_d", "出來了…可是天黑了耶");
            p.Say("ball_go", "球！…會不會很可怕", "我去看看…", "等我～"); p.Say("ball_go_d", "最後一顆…");
            p.Say("ball_catch", "接到了！還你…（躲）", "嘿咻！丟回去～"); p.Say("ball_catch_d", "還你…該回家了");
            p.Say("ball_end", "不玩了嗎…好"); p.Say("ball_end_d", "不玩了…晚安");
            p.Say("ball_far", "太遠了…外面好可怕");
            p.Say("back", "我回來了…"); p.Say("back_d", "回來了…");
            p.Say("share_end", "拍、拍好了嗎…我回來了");
            p.Say("welcome", "你回來了！（探頭）"); p.Say("welcome_d", "你回來了…是要下班了吧");
            p.Say("rest", "{n} 分鐘了…起來走走？我幫你看著位子（躲好）"); p.Say("rest_d", "{n} 分鐘了…回家吧");
            p.Say("night_on", "天黑了…箱子要關門囉"); p.Say("night_off", "早…早安（打開箱子）☀");
            p.Say("sleep", "我先躲進去睡…"); p.Say("sleep_d", "晚安…（關箱子）");
            p.Say("jump", "嘿！"); p.Say("nojump", "附近沒有可以跳的…還好");
            p.Say("errors", "有 {n} 個錯誤…我先躲一下"); p.Say("errors_d", "{n} 個錯誤…明天再說好不好");
            p.Say("errors_ok", "錯誤不見了！我也可以出來了"); p.Say("errors_ok_d", "修好了…可以下班了");
            p.Say("typing", "打好快…我耳朵在抖", "鍵盤好吵…（縮）", "你好厲害…（偷看）"); p.Say("typing_d", "打這麼快…是想快點回家吧");
            p.Say("done", "{who} 做好了…可以出來看看了嗎"); p.Say("done_d", "{who} 做好了…那下班吧");
            p.Say("wait", "{who} 在等你，我陪它等（躲著）"); p.Say("wait_d", "{who} 在等你…回完就回家");
            p.Say("ask", "{who} 有問題要問你…（小聲）"); p.Say("ask_d", "{who} 在問你…回完就下班");
            p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了…要按允許嗎？"); p.Say("stuck_tool_d", "{who} 停了 {n} 分鐘…按一下就回家");
            p.Say("stuck", "{who} 好像卡住了…{n} 分鐘沒動"); p.Say("stuck_d", "{who} 卡住 {n} 分鐘了…看一眼就回家");
            p.Say("unstuck", "{who} 又動了！"); p.Say("unstuck_d", "{who} 動了…");
            p.Say("tag", "上版成功！我出箱慶祝三秒"); p.Say("tag_dev", "測試機好了…（探頭）"); p.Say("tag_prod", "正式機上線了！（整隻跳出來）🎉"); p.Say("tag_d", "上版成功…那下班吧");
            p.Say("late23", "好晚了…我已經蓋好被子（紙箱蓋）🌙"); p.Say("late12", "午餐吃了嗎…我可以幫你看包裹"); p.Say("late15", "三點了…有人送點心來嗎");
            p.Say("late_d", "早就下班了喔…"); p.Say("late_dd", "這麼晚了…快回家");
            p.Say("g_late", "這麼晚還在？我陪你…在箱子裡"); p.Say("g_morning", "早…早安 ☀"); p.Say("g_noon", "午安…吃了嗎");
            p.Say("g_evening", "晚上了…辛苦了"); p.Say("g_day", "（箱子慢慢打開）嗨"); p.Say("g_d", "天黑了…你怎麼還在");
            p.Say("app_browser", "在逛什麼…有新的箱子嗎"); p.Say("app_code", "寫 code…好多字（躲）"); p.Say("app_excel", "好多格子…像好多箱子");
            p.Say("app_ppt", "做簡報…要上台嗎（替你緊張）"); p.Say("app_word", "在寫報告…我不吵你"); p.Say("app_chat", "有人找你…是快遞嗎"); p.Say("app_files", "在找檔案嗎…會不會在箱子裡");
            p.Say("app_other", "那是什麼…（偷看）");
            p.Say("app_code_d", "還在寫…下班了啦"); p.Say("app_chat_d", "明天再回嘛"); p.Say("app_office_d", "這份明天做好不好"); p.Say("app_other_d", "下班時間到了…");
            p.Say("s_birthday", "生日快樂！我、我準備了一個箱子（裡面是我）🎂", "生日快樂…（從箱子裡丟彩帶）");
            p.Say("s_cny", "新年快樂…紅包可以放箱子裡嗎 🧧"); p.Say("s_xmas", "聖誕快樂！我是你的禮物盒 🎄"); p.Say("s_newyear", "新年快樂…今年也請多拆我 ✨");
            p.Say("s_halloween", "不給糖就…躲起來 🎃"); p.Say("s_friday", "星期五了…可以回箱子了嗎");
            p.Say("morning", "躲躲…到（小聲）", "（箱子舉手）到！");
            p.Say("goodnight", "晚安…箱子關起來囉 🌙"); p.Say("nag", "下班了…回家吧", "外面黑了，快回自己的箱子");
            p.Say("react", "嚇！", "（咻一下縮進去）", "什、什麼？");
            p.Say("o_hide", "我不在我不在我不在", "（箱子蓋起來了）", "這裡只有一個普通的箱子");
            p.Say("o_run", "被、被發現了——撤！", "箱子長腳了！跑！", "我不是躲躲！我是路過的箱子！");
            p.Shared();
            return p;
        }

        // ---------------- 沒電：一顆很累的電池。很累但還得繼續；身體裡的電量跟你的工作時間連動 ----------------
        static Pal Meidian()
        {
            Pal p = OrigBase("meidian", "沒電");
            p.Move = "shuffle"; p.NightStyle = "sleepy"; p.NightBubble = 2;
            p.Accent = C(0xC0503C); p.Panel = C(0xFBEFDC);
            p.Speed = 30;
            p.Say("talk", "電量 {p}%…還能撐（騙你的）", "我不是懶，我在省電模式", "充電五分鐘，發呆兩小時", "上班的我：低電量模式", "我的待機時間比你的耐心短", "好想被插著充電", "（打哈欠）呼啊…電又少 1%", "這不是黑眼圈，是電量指示燈");
            p.Say("talk_d", "下班了，我要關機了", "晚上的電是給明天用的", "再撐下去你明天也會沒電", "電量 {p}%…跟你一樣");
            p.Say("save", "存好了…省了一點電", "存了。（耗電 1%）", "存檔完成…可以待機了嗎");
            p.Say("save_d", "存好了，關機吧", "存了…晚安");
            p.Say("pats", "被摸了…充了 1%", "再摸一下，快到 2% 了", "嗯…這個是無線充電嗎", "好溫暖…電池怕熱，但還好", "你也很累吧", "（電量指示燈閃了一下）");
            p.Say("pats_d", "摸完就關機喔", "嗯…待機中");
            p.Say("pats_hi", "你是我的行動電源", "跟你在一起，好像不用充電", "有你在，我電量都滿的");
            p.Say("hugs", "抱抱…這是快充嗎", "好溫暖…", "（電量 +1%）");
            p.Say("hugs_d", "抱完就關機", "晚安抱抱…zZ");
            p.Say("knock", "叩叩…有人有行動電源嗎", "（臉貼玻璃）好冰…", "可以借插座嗎");
            p.Say("knock_d", "叩叩…關機時間到了", "你也沒電了吧，回家");
            p.Say("newwin", "新視窗…又要耗電了", "那是什麼…（慢慢走過去）");
            p.Say("newwin_d", "又開新的？明天再看嘛");
            p.Say("hi", "嗨…我是沒電。現在大概 {p}%"); p.Say("hi_d", "嗨…我快關機了");
            p.Say("wake", "開機中……（轉圈圈）"); p.Say("wake_d", "……還要工作嗎");
            p.Say("dizzy", "電、電在晃…"); p.Say("dizzy_d", "暈…想關機…");
            p.Say("dizzy_ok", "好了…重新開機完成"); p.Say("dizzy_ok_d", "好了…回家吧");
            p.Say("tickle", "別戳！電會漏出來", "哈哈…這樣很耗電欸", "（電量掉了 1%）"); p.Say("tickle_d", "最後一次…我沒電了");
            p.Say("pat10", "今天第 {n} 次了…電量 +{n}%（騙你的）"); p.Say("pat10_d", "第 {n} 次了…關機囉");
            p.Say("levelup", "好感度 Lv{n}！拿到「{u}」…可以拿去換電池嗎"); p.Say("levelup_d", "Lv{n}…「{u}」…明天再戴");
            p.Say("missed", "你好久沒來了…我都快放電完了"); p.Say("missed_d", "好久沒摸了…明天要記得喔");
            p.Say("hover", "電量 {p}%…還能撐", "電量 {p}%…（打哈欠）", "電量 {p}%…看什麼，我在省電");
            p.Say("seek", "那是…插座嗎？"); p.Say("seek_lost", "不是插座…"); p.Say("seek_got", "抓到了！可以拿來當枕頭嗎");
            p.Say("drag", "別晃，電會灑出來"); p.Say("throw", "我的電——！");
            p.Say("shelf_in", "回櫃子待機囉"); p.Say("shelf_in_d", "關機囉…晚安");
            p.Say("shelf_out", "（慢慢開機）……我來了"); p.Say("shelf_out_d", "出來了…可是我沒什麼電了");
            p.Say("ball_go", "球…要跑過去好耗電", "我去…慢慢去"); p.Say("ball_go_d", "最後一顆…");
            p.Say("ball_catch", "接到了…還你（喘）", "嘿…咻…丟回去"); p.Say("ball_catch_d", "還你…關機了");
            p.Say("ball_end", "不玩了？好，省電"); p.Say("ball_end_d", "不玩了…晚安");
            p.Say("ball_far", "太遠了…不划算");
            p.Say("back", "我回來了…（喘）"); p.Say("back_d", "回來了…");
            p.Say("share_end", "拍好了…我回來省電");
            p.Say("welcome", "你回來了！我充好電了 ♥"); p.Say("welcome_d", "你回來了…還要工作嗎");
            p.Say("rest", "{n} 分鐘了，我剩 {p}%…你應該也差不多，起來動一動"); p.Say("rest_d", "{n} 分鐘…我們都沒電了，下班");
            p.Say("night_on", "下班時間…我要關機了"); p.Say("night_off", "早安…充電充到一半就被叫醒 ☀");
            p.Say("sleep", "待機中…"); p.Say("sleep_d", "關機…晚安");
            p.Say("jump", "嘿…（耗電 2%）"); p.Say("nojump", "附近沒地方跳…剛好省電");
            p.Say("errors", "{n} 個錯誤…我電量掉了 {n}%（不是）"); p.Say("errors_d", "{n} 個錯誤…明天充飽電再修");
            p.Say("errors_ok", "錯誤清光了！…好，我可以待機了"); p.Say("errors_ok_d", "修好了…關機吧");
            p.Say("typing", "打太快了，我電會掉", "鍵盤好熱…我也好熱", "你的電是哪裡充的"); p.Say("typing_d", "打這麼快…是想快點下班吧");
            p.Say("done", "{who} 做完了，我也省了點電"); p.Say("done_d", "{who} 做完了…關機吧");
            p.Say("wait", "{who} 在等你…我在待機"); p.Say("wait_d", "{who} 在等你…回完就關機");
            p.Say("ask", "{who} 有問題要問你"); p.Say("ask_d", "{who} 在問你…回完就下班");
            p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，要你按允許嗎？"); p.Say("stuck_tool_d", "{who} 停了 {n} 分鐘…按一下就回家");
            p.Say("stuck", "{who} 好像沒電了…{n} 分鐘沒動"); p.Say("stuck_d", "{who} 卡住 {n} 分鐘…看一眼就回家");
            p.Say("unstuck", "{who} 又動了，有電了"); p.Say("unstuck_d", "{who} 動了…");
            p.Say("tag", "上版成功！用掉我 3% 的電來歡呼 🎉"); p.Say("tag_dev", "測試機上好了…（省電地歡呼）"); p.Say("tag_prod", "正式機上線！電量全拿去放煙火了 🎉"); p.Say("tag_d", "上版成功…關機吧");
            p.Say("late23", "好晚了…我們都該充電了 🌙"); p.Say("late12", "午餐時間！吃飯＝人類的充電"); p.Say("late15", "三點了…下午的電最難撐");
            p.Say("late_d", "早就下班了喔…"); p.Say("late_dd", "這麼晚了…關機睡覺");
            p.Say("g_late", "這麼晚還在？我陪你…（剩 {p}%）"); p.Say("g_morning", "早安…開機中 ☀"); p.Say("g_noon", "午安…吃飽充電了嗎");
            p.Say("g_evening", "晚上了…辛苦了"); p.Say("g_day", "沒電，上線（勉強）"); p.Say("g_d", "下班了…你怎麼還在");
            p.Say("app_browser", "在逛什麼…有在賣電池嗎"); p.Say("app_code", "寫 code 呀…好耗電"); p.Say("app_excel", "好多格子…像電量格");
            p.Say("app_ppt", "做簡報～記得插電"); p.Say("app_word", "在寫報告…慢慢來"); p.Say("app_chat", "有人找你…先回再說"); p.Say("app_files", "在找檔案嗎…");
            p.Say("app_other", "這是什麼…要耗電嗎");
            p.Say("app_code_d", "還在寫…關機了啦"); p.Say("app_chat_d", "明天再回嘛"); p.Say("app_office_d", "這份明天做好不好"); p.Say("app_other_d", "關機時間到了…");
            p.Say("s_birthday", "生日快樂！今天電量給你 100% 🎂", "生日快樂…我只剩一點電，全部給你");
            p.Say("s_cny", "新年快樂！紅包可以買行動電源嗎 🧧"); p.Say("s_xmas", "聖誕快樂！聖誕燈好耗電 🎄"); p.Say("s_newyear", "新年快樂！今年也要記得充電 ✨");
            p.Say("s_halloween", "不給糖就…不給電 🎃"); p.Say("s_friday", "星期五了…週末要充飽");
            p.Say("morning", "沒電…到（剩 {p}%）", "到…開機中");
            p.Say("goodnight", "晚安…去充電囉 🌙"); p.Say("nag", "下班了，回家充電吧", "我們都沒電了…回家", "再撐下去會壞掉的");
            p.Say("react", "咦？", "（電量閃了一下）", "嚇到漏電了");
            p.Say("o_low", "電量 {p}%…說話也要耗電…", "我先關掉不重要的功能（例如表情）", "低電量模式…走路變慢了");
            p.Say("o_flop", "……（靈魂在說）我沒電了，你去休息我才能充", "沒電了…（攤平）", "（鬼魂飄出來）充…電…");
            p.Say("o_charge", "插上了……嗯……這就是天堂", "充電中，請勿打擾（請打擾我，我很孤單）", "充電中…你也休息一下");
            p.Say("o_full", "100%！……好，我再睡五分鐘", "充飽了！可以再撐一小時（大概）");
            p.Shared();
            return p;
        }

        // ---------------- 刺刺：盆栽仙人掌。嘴硬心軟；被拆穿就開花、生氣就炸毛 ----------------
        static Pal Cici()
        {
            Pal p = OrigBase("cici", "刺刺");
            p.Move = "shuffle"; p.NightStyle = "sleepy"; p.NightBubble = 2;
            p.Accent = C(0x5E9A48); p.Panel = C(0xE6F2DC);
            p.Speed = 34;
            p.Say("talk", "我才沒有在等你", "看什麼看，仙人掌沒看過嗎", "OK 繃不是受傷，是時尚", "我一點都不需要澆水。……一點點就好", "你今天看起來還行。我隨便說說的", "不准靠太近，會刺（其實不會）", "我才不寂寞，我有盆", "哼");
            p.Say("talk_d", "這麼晚還不回家…我才沒擔心你", "快去睡，不然我要炸毛了", "我不睏。你睏。去睡。");
            p.Say("save", "存好了。不用謝", "存了啦，看什麼", "存檔…還算可以");
            p.Say("save_d", "存好了，快回家", "存了…晚安（小聲）");
            p.Say("pats", "摸、摸什麼摸…（花苞抖）", "再一下下而已喔", "我沒有很開心，是花苞自己動的", "…你的手不痛嗎", "哼…還不錯", "不准停…我是說，隨便你");
            p.Say("pats_d", "摸完就回家", "很晚了…（不想你走）");
            p.Say("pats_hi", "我才沒有最喜歡你。……第二喜歡", "你很煩。……明天也要來", "（花苞偷偷變粉紅）");
            p.Say("hugs", "抱我會被刺到喔！……好吧，我收起來了", "只、只准抱一下", "（刺全部收起來）");
            p.Say("hugs_d", "抱完就回家", "晚安…才沒有捨不得");
            p.Say("knock", "叩什麼叩，進來啊", "（用刺敲玻璃）叩叩", "幹嘛，想我喔");
            p.Say("knock_d", "叩叩，下班了", "還不走？我要炸毛了");
            p.Say("newwin", "新視窗？我去看看。才不是好奇", "那是什麼…哼");
            p.Say("newwin_d", "又開新的…明天再看");
            p.Say("hi", "我是刺刺。不用跟我好，我也不會跟你好（小聲：你好）"); p.Say("hi_d", "嗨…這麼晚了");
            p.Say("wake", "我沒睡。只是閉目養神"); p.Say("wake_d", "…還不下班？");
            p.Say("dizzy", "盆、盆要翻了…"); p.Say("dizzy_d", "暈…我要回盆裡");
            p.Say("dizzy_ok", "好了。剛剛什麼都沒發生"); p.Say("dizzy_ok_d", "好了…回家吧");
            p.Say("tickle", "不准搔我癢！", "哈、哈…才沒有很好笑", "再戳我就炸毛了！"); p.Say("tickle_d", "最後一次…");
            p.Say("pat10", "今天第 {n} 次了…你很閒耶（開心）"); p.Say("pat10_d", "第 {n} 次了…晚安");
            p.Say("levelup", "好感度 Lv{n}！拿到「{u}」…才沒有很想要"); p.Say("levelup_d", "Lv{n}…「{u}」明天戴給你看（才不是為了你）");
            p.Say("missed", "你好久沒來了。…我才沒數日子"); p.Say("missed_d", "好久沒來了…明天要來喔（哼）");
            p.Say("hover", "游標拿開，會被刺（不會）", "看什麼看", "幹嘛");
            p.Say("seek", "那是什麼？…我才不在意"); p.Say("seek_lost", "跑了。哼"); p.Say("seek_got", "抓到了！沒收！");
            p.Say("drag", "放我下來！盆要掉了！"); p.Say("throw", "你給我記住——");
            p.Say("shelf_in", "回櫃子了。不准想我"); p.Say("shelf_in_d", "回去睡了…晚安");
            p.Say("shelf_out", "（盆子咚一聲落地）我來了"); p.Say("shelf_out_d", "出來了…天黑了耶");
            p.Say("ball_go", "球？…我才不想玩（跑過去）", "給我！"); p.Say("ball_go_d", "最後一顆…");
            p.Say("ball_catch", "接到了！哼，簡單", "還你！才不是很好玩"); p.Say("ball_catch_d", "還你…回家了");
            p.Say("ball_end", "不玩了？…隨便你"); p.Say("ball_end_d", "不玩了…晚安");
            p.Say("ball_far", "丟那麼遠，你是故意的吧");
            p.Say("back", "我回來了。才不是想你"); p.Say("back_d", "回來了…");
            p.Say("share_end", "拍好了？…拍得還行");
            p.Say("welcome", "你回來了。…我才沒有在等"); p.Say("welcome_d", "你回來了…是要下班了吧");
            p.Say("rest", "{n} 分鐘了，起來動。不是我關心你，是椅子很累"); p.Say("rest_d", "{n} 分鐘了…回家。現在。");
            p.Say("night_on", "下班了。…回家路上小心（小聲）"); p.Say("night_off", "早。…今天也要好好的 ☀");
            p.Say("sleep", "我閉目養神一下"); p.Say("sleep_d", "晚安…（哼）");
            p.Say("jump", "嘿！"); p.Say("nojump", "附近沒地方跳。不是我不會");
            p.Say("errors", "{n} 個錯誤？…又不是我寫的"); p.Say("errors_d", "{n} 個錯誤…明天再修，回家");
            p.Say("errors_ok", "修好了。…還算可以啦"); p.Say("errors_ok_d", "修好了…快回家");
            p.Say("typing", "打那麼大力，鍵盤是欠你錢嗎", "很快嘛…哼", "鍵盤在冒煙了"); p.Say("typing_d", "打這麼快，是想快點下班吧");
            p.Say("done", "{who} 做完了。我早就知道"); p.Say("done_d", "{who} 做完了…回家");
            p.Say("wait", "{who} 在等你。快去，別讓人家等"); p.Say("wait_d", "{who} 在等你…回完就回家");
            p.Say("ask", "{who} 有問題要問你"); p.Say("ask_d", "{who} 在問你…回完就下班");
            p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，要你按允許"); p.Say("stuck_tool_d", "{who} 停了 {n} 分鐘…按一下就回家");
            p.Say("stuck", "{who} 卡住 {n} 分鐘了。…去看看啦"); p.Say("stuck_d", "{who} 卡住 {n} 分鐘…看一眼就回家");
            p.Say("unstuck", "{who} 又動了。哼，早就知道"); p.Say("unstuck_d", "{who} 動了…");
            p.Say("tag", "上版成功。…才、才沒有很感動 🎉"); p.Say("tag_dev", "測試機好了。還行"); p.Say("tag_prod", "正式機上線了！…這、這是花粉過敏 🎉"); p.Say("tag_d", "上版成功…回家");
            p.Say("late23", "幾點了你知道嗎？去睡 🌙"); p.Say("late12", "吃飯了沒？…我隨便問的"); p.Say("late15", "三點了。喝水。現在。");
            p.Say("late_d", "早就下班了"); p.Say("late_dd", "這麼晚了…快回家");
            p.Say("g_late", "這麼晚還在？…我陪你一下下"); p.Say("g_morning", "早。…今天加油（小聲）☀"); p.Say("g_noon", "午安。吃了沒");
            p.Say("g_evening", "晚上了。辛苦了…我是說，哼"); p.Say("g_day", "刺刺來了。不用歡迎"); p.Say("g_d", "下班了你怎麼還在");
            p.Say("app_browser", "在逛什麼？…給我看"); p.Say("app_code", "寫 code 呀…寫得還行"); p.Say("app_excel", "好多格子…頭好痛");
            p.Say("app_ppt", "做簡報？加油。…我沒說"); p.Say("app_word", "在寫報告…別寫錯字"); p.Say("app_chat", "在跟誰聊？…我才不在意"); p.Say("app_files", "找檔案？東西要收好啦");
            p.Say("app_other", "這是什麼？…才不好奇");
            p.Say("app_code_d", "還在寫…回家了啦"); p.Say("app_chat_d", "明天再回"); p.Say("app_office_d", "這份明天做"); p.Say("app_other_d", "下班時間到了");
            p.Say("s_birthday", "生、生日快樂。這朵花不是為你開的 🎂", "生日快樂…（花苞爆開）");
            p.Say("s_cny", "新年快樂。紅包…隨便給就好 🧧"); p.Say("s_xmas", "聖誕快樂。我才不是聖誕樹 🎄"); p.Say("s_newyear", "新年快樂。今年也…請多指教（小聲）✨");
            p.Say("s_halloween", "不給糖就刺你 🎃"); p.Say("s_friday", "星期五了。週末別熬夜");
            p.Say("morning", "刺刺。到。", "到啦，看什麼");
            p.Say("goodnight", "晚安。…明天見（小聲）🌙"); p.Say("nag", "下班了，回家", "還不走？要我炸毛嗎", "回家啦…很晚了");
            p.Say("react", "幹嘛！嚇我一跳", "（刺豎起來）", "什麼啦");
            p.Say("o_bloom", "這、這是花粉過敏！", "花是自己開的，跟你沒關係", "不准看！（花開得更大）");
            p.Say("o_bristle", "別碰我！", "現在很刺，請稍後再摸", "哼！！（刺全部豎起來）");
            p.Shared();
            return p;
        }
    }

    // ================= 一隻續命小隊 =================
    partial class Pet
    {
        string oAct = "", oPose = "";            // 專屬動作（state == "orig"）；oPose＝要擺哪一張圖
        double oT, oSulkT, oLowCd, oSigCd;
        string oPend; double oPendDur;
        bool oFull;

        public void OrigDo(string act, double dur)
        {
            if (state == "air" || state == "fling" || state == "drag" || state == "swim") { oPend = act; oPendDur = dur; return; }
            oAct = act; oT = 0; SetState("orig", dur);
        }
        // 擺一張圖（frame 名字）一段時間
        public void OPose(string frame, double dur) { if (!Grounded() && state != "air") return; oPose = frame; OrigDo("pose", dur); }

        bool BatLink { get { return Is("meidian") && SqBattery.Link; } }
        bool Flat { get { return BatLink && SqBattery.Level <= 0.001 && !SqBattery.Charging; } }

        // ---------- 連點三下 ----------
        void OrigCombo()
        {
            Say(L("tickle"), 1.8);
            if (!Grounded() || state == "dizzy") return;
            switch (P.Id)
            {
                case "duoduo": OrigDo("hide", 2.4); break;                                        // 縮回箱子
                case "meidian": OPose("surprised", 1.4); if (BatLink) SqBattery.Level = Math.Max(0, SqBattery.Level - 0.01); break;
                default: OrigDo("bristle", 2.0); break;                                            // 炸毛
            }
        }

        // ---------- 招牌動作 ----------
        void OrigSignature()
        {
            if (!Grounded()) return;
            switch (P.Id)
            {
                case "duoduo": OrigDo("hide", R(2.6, 4)); Say(L("o_hide"), 1.6); break;
                case "meidian":
                    if (SqBattery.Charging) { OrigDo("charge", 3); Say(L("o_charge"), 1.8); }
                    else { OPose("pout", 1.8); Say(L(SqBattery.Pct < 30 ? "o_low" : "talk"), 2); }
                    break;
                default: OrigDo("bloom", 3); Say(L("o_bloom"), 1.8); break;
            }
        }

        // 躲躲：箱子長腳逃跑（跑到螢幕另一邊，再探頭）
        void DuoduoRun()
        {
            Rectangle wa = w.WA(Cx, y + SH / 2.0);
            double tx = Cx < (wa.Left + wa.Right) / 2.0 ? wa.Right - SW * 2 - R(0, 120) * k : wa.Left + SW * 2 + R(0, 120) * k;
            dir = tx > Cx ? 1 : -1;
            oTx = tx;
            OrigDo("run", 4.5);
            Say(L("o_run"), 1.6);
        }
        double oTx = double.NaN;

        bool OrigAct(string a)
        {
            if (a.StartsWith("f_")) { string fr = a.Substring(2); if (Array.IndexOf(SqArt.Keys, fr) >= 0) { if (Grounded()) OPose(fr, 30); } return true; }   // 測試／截圖：擺指定的圖
            switch (a)
            {
                case "sq_hide": if (Grounded() && Is("duoduo")) { OrigDo("hide", 3.2); Say(L("o_hide"), 1.6); } return true;
                case "sq_run": if (Grounded() && Is("duoduo")) DuoduoRun(); return true;
                case "sq_charge": if (Grounded() && Is("meidian")) { OrigDo("charge", 4); Say(L("o_charge"), 1.8); } return true;
                case "sq_flop": if (Grounded() && Is("meidian")) { OrigDo("flop", 4); Say(L("o_flop"), 2); } return true;
                case "sq_battery": Say(SqBattery.Link ? L("hover") : "電量連動關著：我永遠滿電 🔋", 2.2); return true;
                case "sq_bloom": if (Grounded() && Is("cici")) { OrigDo("bloom", 3); Say(L("o_bloom"), 1.8); } return true;
                case "sq_bristle": if (Grounded() && Is("cici")) { OrigDo("bristle", 2.2); Say(L("o_bristle"), 1.6); } return true;
            }
            return false;
        }

        // ---------- 自己閒晃時決定做什麼 ----------
        void OrigDecide(double r, Rectangle wa)
        {
            if (Flat) { OrigDo("flop", 6); return; }
            if (r < .18) { SetState("idle", R(1.5, 3.5)); return; }
            if (r < .42) { dir = rnd.NextDouble() < .5 ? -1 : 1; SetState("walk", R(3, 6)); return; }
            if (r < .48) { if (!JumpToPlatform()) Hop(); return; }
            if (r < .55) { OrigSignature(); return; }
            if (r < .62)
            {
                switch (P.Id)
                {
                    case "duoduo": OPose("surprised", 1.4); Say(L("talk"), 2.2); break;
                    case "meidian": if (SqBattery.Pct < 25 && BatLink) { OPose("pout", 2); Say(L("o_low"), 2.2); } else { OPose("sit", 2.6); Say(L("talk"), 2.4); } break;
                    default: OPose("pout", 2); oSulkT = 6; Say(L("talk"), 2.2); break;
                }
                return;
            }
            if (r < .67) { Hug(L("hugs"), 2.2); return; }
            if (r < (Night ? .73 : .71)) { Knock(L("knock"), "ambient"); return; }
            if (r < .75 && lateCd <= 0 && LateLine() != null) { LateTick(); return; }
            if (r < .78 && SeasonLine() != null) { Say(SeasonLine(), 3); SetState("idle", 3); return; }
            if (r < .90) { SetState("idle", 2.5); Say(L("talk"), 2.4); if (Is("cici")) oSulkT = 6; return; }
            dir = -dir; SetState("walk", R(2, 5));
        }

        // 走到視窗邊：0 照預設跳、1 回頭、2 換狀態了
        int OrigEdge(bool right)
        {
            if (Is("meidian") || rnd.NextDouble() < 0.45) { dir = -dir; return 1; }   // 沒電：跳太耗電
            x += dir * 4 * k; Jump(dir * 120 * k, -260 * k); Say(L("jump"), 0.8);
            return 2;
        }

        bool OrigLanded(bool wasRolling)
        {
            if (oPend != null) { string a = oPend; oPend = null; SetState("idle", 0.1); OrigDo(a, oPendDur); return true; }
            if (Is("cici") && lastLandVy > 700 * k) { OrigDo("bristle", 1.8); Say(L("o_bristle"), 1.4); return true; }   // 被丟：炸毛
            if (Is("duoduo") && lastLandVy > 700 * k) { OrigDo("hide", 1.8); return true; }
            return false;
        }

        bool OrigLand(string a)
        {
            switch (a)
            {
                case "opeek": OPose("surprised", 1.2); return true;
                case "ohappy": OPose("happy", 1.4); return true;
            }
            return false;
        }

        // 從櫃子出來
        void OrigExit()
        {
            switch (P.Id)
            {
                case "duoduo": if (rnd.NextDouble() < 0.6) afterLand = "opeek"; break;
                case "cici": if (rnd.NextDouble() < 0.4) afterLand = "ohappy"; break;
            }
        }

        public void OrigNewWindow(WinInfo win)
        {
            if (Is("duoduo") && rnd.NextDouble() < 0.6) { OrigDo("hide", 2.4); Say(L("newwin"), 1.5); return; }   // 新視窗跳出來：先躲
            if (!GoToWindow(win, L("newwin"), Is("cici") ? "ohappy" : "opeek")) Say(L("newwin"), 1.5);
        }

        // 錯誤變多：躲躲躲起來、沒電嚇到、刺刺炸毛
        void OrigReact(string why)
        {
            switch (P.Id)
            {
                case "duoduo": OrigDo("hide", 2.6); break;
                case "meidian": OPose("surprised", 2.2); Mark(1); break;
                default: OrigDo("bristle", 2.2); break;
            }
        }

        // 慶祝（上版、做完）：刺刺被拆穿＝開花
        void OrigCelebrate(string line, bool lead)
        {
            if (lead) w.Fireworks(w.WA(Cx, y + SH / 2.0), 10, -1);
            if (Grounded()) { if (Is("cici")) OrigDo("bloom", 3.2); else OPose("happy", 3.2); }
            Say(line, 4);
            Burst(8);
        }

        string OrigLine(string kind)
        {
            switch (kind)
            {
                case "goal": return Is("duoduo") ? "進、進了！🏀（探頭）" : (Is("meidian") ? "進了…省電投籃 🏀" : "進了。…還好啦 🏀");
                case "cheer": return Is("duoduo") ? "好、好球！" : (Is("meidian") ? "好球…（拍手耗電 1%）" : "好球。哼，還行");
                case "miss": return Is("duoduo") ? "沒進…我先躲一下" : (Is("meidian") ? "沒電了，沒投好" : "沒進！是球的問題");
            }
            return "！";
        }

        // ---------- 球 ----------
        void OrigBall()
        {
            w.HoldBall(this);
            OrigDo("catch", 0.9);
            Say(L("ball_catch"), 1.2);
        }

        void OReleaseBall(double power)
        {
            if (w.Holder != this) return;
            w.ReleaseBall(Cx + dir * 4 * S, y + (P.BodyTop - 2) * S, 0, 0);
            KickBallToCursor(power);
        }

        // ---------- 每一格 ----------
        bool OrigStep(double dt)
        {
            if (oSulkT > 0) oSulkT -= dt;
            if (oLowCd > 0) oLowCd -= dt;
            if (oSigCd > 0) oSigCd -= dt;
            if (Is("meidian"))
            {
                // 沒電：電量越低走越慢；0% 就攤平（充電才起來）；低電量偶爾喊一下；充飽講一句
                P.Speed = 30 * (BatLink ? 0.55 + 0.45 * SqBattery.Level : 1);
                if (Flat && Out && Grounded() && state != "orig" && state != "sleep" && !InScene && !MisBusy) { OrigDo("flop", 8); Say(L("o_flop"), 2.4); }
                if (BatLink && SqBattery.Pct < 20 && SqBattery.Pct > 0 && !SqBattery.Charging && oLowCd <= 0 && Out && Grounded() && state == "idle" && !InScene) { oLowCd = 600; Say(L("o_low"), 2.4); }
                if (SqBattery.Charging) oFull = false;
                if (BatLink && SqBattery.Pct >= 100 && !oFull && Out && state == "sleep") { oFull = true; }
            }
            if (oSpaceCd > 0) oSpaceCd -= dt;
            if (Out && !InScene && !MisBusy && oSpaceCd <= 0 && (state == "walk" || state == "idle")) OrigKeepApart();
            if (state != "orig") return false;
            oT += dt;
            switch (oAct)
            {
                case "run":
                    {
                        // 躲躲：箱子長腳快跑，到了就探頭
                        if (!double.IsNaN(oTx) && Math.Abs(oTx - Cx) > 4)
                        {
                            dir = oTx > Cx ? 1 : -1;
                            double nx = x + dir * Math.Min(Math.Abs(oTx - Cx), 230 * k * dt);
                            if (w.Inside(nx + (dir > 0 ? SW : 0), y + SH / 2.0)) x = nx; else oTx = double.NaN;
                        }
                        else if (t > 0.9) t = 0.9;
                        if (t < 0) { oTx = double.NaN; OPose("surprised", 1.4); }
                    }
                    return true;
                case "flop":
                    if (t < 0) { if (Flat) { OrigDo("flop", 6); } else SetState("idle", 1); }
                    return true;
                case "charge":
                    if (t < 0) { SetState("idle", 1); if (BatLink && SqBattery.Pct >= 100) Say(L("o_full"), 2); }
                    return true;
                case "catch":
                    if (t < 0) { OReleaseBall(1.0); Say(L("ball_catch"), 1.4); SetState("idle", 1); }
                    return true;
                default:   // pose／hide／bloom／bristle：站著擺一張圖
                    if (t < 0) SetState("idle", InScene ? 30 : 1);
                    return true;
            }
        }

        // 自己閒晃時不要疊在一起：看兩隻的實際寬度，太近就轉身或停一下（串場、搗蛋時不管）
        double oSpaceCd;
        void OrigKeepApart()
        {
            foreach (Pet o in w.Pets)
            {
                if (o == this || !o.Out || o.InScene || !o.Grounded() || Math.Abs(o.Foot - Foot) > 6 * k) continue;
                double dx = o.Cx - Cx, touch = HalfW(this) + HalfW(o), need = touch + 4 * S;   // 最小間距：身體之間留 4 格
                if (Math.Abs(dx) >= need) continue;
                int toward = dx > 0 ? 1 : (dx < 0 ? -1 : (rnd.NextDouble() < 0.5 ? 1 : -1));
                // 走過去會撞到：轉身（偶爾停一下）
                if (state == "walk" && toward == dir) { oSpaceCd = 0.6; if (rnd.NextDouble() < 0.7) dir = -dir; else SetState("idle", R(0.6, 1.4)); return; }
                // 已經疊在一起（例如剛從櫃子出來、串場結束）：往另一邊走開，走到不疊為止
                if (state == "idle" && Math.Abs(dx) < touch + 2 * k)
                {
                    dir = -toward; oSpaceCd = 0.4;
                    SetState("walk", Math.Min(5, Math.Max(0.5, (need - Math.Abs(dx)) / Math.Max(1, P.Speed * k) + 0.2)));
                    return;
                }
            }
        }
        // 看起來多寬的一半（圖片公仔用 stand 的身體寬度，像素公仔用 12 格框）
        static double HalfW(Pet p)
        {
            CuSprite s = p.P.Spr;
            if (s == null) return p.SW / 2.0;
            return (s.BodyW > 0 ? s.BodyW : s.W) / (double)s.R * p.S / 2;
        }

        // 櫃子裡：依自己 stand 的身體大小撐到格子合適的大小（不限整數倍；大格、小格同一個留白規則）
        public float OrigShelfSc(Rectangle cell, int fy)
        {
            CuSprite s = P.Spr;
            double availH = fy - cell.Y - cell.Height * 0.07;
            double bw = s.BodyW > 0 ? s.BodyW : s.W;
            double sc = Math.Min(availH / Math.Max(1, s.BodyH), cell.Width * 0.86 / bw);
            return (float)Math.Max(0.1, sc);
        }
        public void OrigGhost(Graphics g, int fx, int fy, Rectangle cell, bool night) { CuGhostSc(g, fx, fy, OrigShelfSc(cell, fy), night); }

        // 刺刺嘴硬之後馬上被摸：被拆穿，開花
        public bool OrigPatted()
        {
            if (Is("cici") && oSulkT > 0 && Grounded()) { oSulkT = 0; OrigDo("bloom", 3); Say(L("o_bloom"), 2); return true; }
            if (Is("duoduo") && state == "orig" && oAct == "hide" && Grounded()) { DuoduoRun(); return true; }   // 躲著被點：被發現了，逃跑
            return false;
        }

        double OrigBob()
        {
            bool moving = state == "walk" || state == "goto" || state == "seek" || state == "fetch" || (state == "orig" && oAct == "run");
            if (state == "dance") return Math.Abs(Math.Sin(anim * 8)) * 6 * k;
            if (state == "orig" && oAct == "bristle") return (Math.Floor(anim * 20) % 2) * k;   // 炸毛：一直抖
            return moving ? Math.Abs(Math.Sin(anim * 7)) * 1.5 * k : 0;
        }

        // ---------- 畫：狀態 → 哪一張圖（其他的位移、搖晃用自己做的公仔那套 CuPoseNow）----------
        string OrigFrame()
        {
            if (MisBusy) { string mf = MisFrame(misPoseNow); if (mf != null) return mf; }
            bool walkStep = Math.Floor(anim * 5) % 2 == 1;
            if (state == "orig")
            {
                switch (oAct)
                {
                    case "pose": return oPose;
                    case "hide": return "sig1";
                    case "run": return "sig2";
                    case "charge": return "sig1";
                    case "flop": return "sig2";
                    case "bloom": return "sig1";
                    case "bristle": return "sig2";
                    case "catch": return "grab";
                }
                return "stand";
            }
            if (Is("meidian") && SqBattery.Charging && (state == "sleep" || state == "idle") && BatLink) return "sig1";   // 你去休息了：他在充電
            if (Flat && (state == "idle" || state == "sleep")) return "sig2";
            switch (state)
            {
                case "dizzy": return "blown";
                case "think": return "pout";
                case "nudge": case "kick": return "push";
                case "glass": return "surprised";
                case "catch": case "throw": return "grab";
                case "goto": return walkStep ? "walk2" : "walk1";
            }
            return null;
        }

        // 搗蛋的演法（DeskPals.Mischief.cs 的 MisPose）→ 哪一張圖；null＝照一般狀態
        string MisFrame(string what)
        {
            switch (what)
            {
                case "wind": return Is("duoduo") ? "sig1" : "pout";
                case "leap": case "fall": return "jump";
                case "hold": return Is("duoduo") ? "sig1" : "grab";                      // 躲躲：游標收進紙箱
                case "run": return Is("duoduo") ? "sig2" : (Math.Floor(anim * 5) % 2 == 1 ? "walk2" : "walk1");   // 躲躲：箱子長腳逃跑
                case "drop": return Is("meidian") ? "sleep" : (Is("cici") ? "sig1" : "happy");   // 沒電：抱著游標當枕頭
                case "caught": return Is("duoduo") ? "surprised" : (Is("cici") ? "sig2" : "surprised");
                case "brace": case "push": return "push";
                case "cry": return "cry";
                case "fly": return "blown";
                case "dizzy": return Is("meidian") ? "sig2" : (Is("cici") ? "sig2" : "blown");
                case "back": return Math.Floor(anim * 5) % 2 == 1 ? "walk2" : "walk1";
            }
            return null;
        }

        void OrigPoseNow(CuPose p)
        {
            CuPoseNow(p);
            string fr = OrigFrame();
            if (fr != null && P.Spr.Frames.ContainsKey(fr))
            {
                bool keepSpin = rolling || state == "fling" || state == "drag";
                p.Frame = fr;
                if (!keepSpin) { p.Rot = 0; p.Rot90 = 0; }
                if (state == "orig" && oAct == "run") p.Y = -Math.Abs(Math.Sin(anim * 14)) * 0.5;
            }
            if (p.Frame == null) p.Frame = "stand";
        }

        Fr FrameOrig()
        {
            OrigPoseNow(cuPose);
            Fr f = F(CU_BLANK);
            f.Rot = cuPose.Rot90 != 0 || Math.Abs(cuPose.Rot) > 30 ? 1 : 0;
            f.Acc = false; f.Top = 0; f.AccDy = 0;   // 圖片公仔：不用像素框的位移、不戴配件
            return f;
        }

        // 畫一隻：圖＋手上的球、午餐
        void DrawFigureOrig(Graphics g, Fr f, int sbx, int sby, int sps, bool fx, bool extras)
        {
            CuDraw(g, cuPose, sbx + 6 * sps, sby + 16 * sps, sps, fx);
            if (!extras) return;
            if (w.Holder == this) DrawAt(g, w.BallKind == "baseball" ? BALLART : TBALL, 8, P.BodyTop - 1 + cuPose.Y, sbx, sby, sps, fx, false, true);
            DrawLunch(g, f, sbx, sby, sps, fx);
        }

        void DrawOrigBehind(Graphics g, Fr f, int bx, int by, int ps, bool fx) { }
        void DrawOrigFront(Graphics g, Fr f, int bx, int by, int ps, bool fx) { }

        // ---------- 午餐：躲躲吃網購的便當、沒電吃飯＝人類的充電、刺刺吃沙拉（不是同類！）----------
        string OrigLunchLine(string phase)
        {
            switch (P.Id)
            {
                case "duoduo":
                    if (phase == "start") return "午餐！便當…是網購送來的嗎 🔔";
                    if (phase == "nap") return "吃飽了…躲進箱子睡一下";
                    if (phase == "end") return "下午了…（打開箱子）";
                    return Pick(new string[] { "（躲在箱子裡吃）", "便當好好吃…不要看我吃", "便當的盒子也可以住嗎" });
                case "meidian":
                    if (phase == "start") return "午餐！吃飯＝人類的充電 🔔";
                    if (phase == "nap") return "吃飽了…邊睡邊充電";
                    if (phase == "end") return "充、充好了…大概";
                    return Pick(new string[] { "（嚼）……電量 +5%", "吃飽會想睡，這是定律", "這便當幾瓦？" });
                default:
                    if (phase == "start") return "午餐時間。…我才不餓 🔔";
                    if (phase == "nap") return "吃飽了…閉目養神";
                    if (phase == "end") return "下午了。…加油（小聲）";
                    return Pick(new string[] { "才不是因為好吃才吃很快", "你也要吃飯喔。…我隨便說的", "（偷偷多吃一口）" });
            }
        }

        void DrawOrigLunch(Graphics g, Fr f, int bx, int by, int ps, bool fx, int bite)
        {
            DrawAt(g, BENTO, 8.5, P.BodyTop + bite + cuPose.Y, bx, by, ps, fx, false, true);
        }

        int OrigShelfRows()
        {
            return (int)Math.Ceiling(P.Spr.BodyH / (double)P.Spr.R * 1.04) + 1;
        }

        // ---------- 櫃子裡：躲躲偶爾躲進箱子、沒電充電中就插著、刺刺偶爾嘟嘴；晚上睡 ----------
        void DrawOrigShelf(Graphics g, int fx, int bx, int by, int ps, bool flip, double tt, bool blink, Rectangle cell)
        {
            CuPose p = new CuPose();
            double br = Math.Sin(tt * 1.9);
            p.Sy = 1 + br * 0.015; p.Sx = 1 - br * 0.008;
            string fr = "stand";
            if (Night) fr = "sleep";
            else if (Is("meidian") && SqBattery.Charging && SqBattery.Link) fr = "sig1";
            else if (Is("meidian") && SqBattery.Link && SqBattery.Pct == 0) fr = "sig2";
            else if (Is("duoduo") && (tt % 11) < 2.5) fr = "sig1";
            else if (Is("cici") && (tt % 13) < 2) fr = "pout";
            else if ((tt % 9) < 0.9) fr = "happy";
            if (w.Lunch && !Night) fr = "sit";
            p.Frame = fr;
            int fy = by + 16 * ps;
            CuDrawSc(g, p, fx, fy, OrigShelfSc(cell, fy), ps, flip);
            if (w.Lunch) DrawAt(g, BENTO, 8.5, P.BodyTop, bx, by, ps, flip, false, true);
        }
    }

    // ================= 公仔櫃：大格背板上釘一張小便利貼 =================
    partial class ShelfForm
    {
        public bool Orig;                    // 續命小隊：大格的背板右上角釘一張小便利貼（畫一顆愛心）；空的格子是「做一隻你的公仔」入口

        void DrawStickyNote(Graphics g, Rectangle bk)
        {
            int u = Math.Max(2, U * 3 / 4);
            float nx = bk.Right - 12 * u, ny = bk.Y + 4 * u;
            using (SolidBrush sh = new SolidBrush(Color.FromArgb(50, 60, 40, 10))) g.FillRectangle(sh, nx + u, ny + u, 9 * u, 9 * u);
            using (SolidBrush nb = new SolidBrush(Night ? C(0xC8B05A) : C(0xFFE45C))) g.FillRectangle(nb, nx, ny, 9 * u, 9 * u);
            using (SolidBrush gb = new SolidBrush(Night ? C(0xAC9440) : C(0xF2CC3A))) g.FillRectangle(gb, nx, ny, 9 * u, 2 * u);
            using (Pen ink = new Pen(Color.FromArgb(200, 0x1E, 0x1E, 0x24), Math.Max(1f, u * 0.5f))) g.DrawRectangle(ink, nx, ny, 9 * u, 9 * u);
            string[] heart = { ".pp.pp.", "ppppppp", ".ppppp.", "..ppp..", "...p..." };
            using (SolidBrush hb = new SolidBrush(Night ? C(0xC87A88) : C(0xFF8FA8)))
                for (int r = 0; r < heart.Length; r++) for (int c = 0; c < heart[r].Length; c++) if (heart[r][c] != '.') g.FillRectangle(hb, nx + (1 + c) * u, ny + (3 + r) * u, u, u);
            using (SolidBrush pin = new SolidBrush(Night ? C(0x9A3A3A) : C(0xE04848))) g.FillEllipse(pin, nx + 3.5f * u, ny - 0.8f * u, 2 * u, 2 * u);
        }
    }

    // 續命小隊的第 4 格：「＋ 做一隻你的公仔」入口（點了開做公仔視窗；做好了第 4 格就放那一隻）
    partial class ShelfForm
    {
        void DrawMakeSlot(Graphics g, Rectangle c, int fx, int fy)
        {
            // 背板上方一行小字＋底下淡淡的虛線剪影（圓頭＋身體，站在地板上）＋身體上一顆加號
            float h = fy - c.Y;
            float fs = Math.Max(9f, Math.Min(c.Width * 0.115f, 3.2f * TU));
            float th = fs * 1.35f, ty = c.Y + h * 0.05f;
            float top = ty + th + h * 0.02f, bot = fy - h * 0.01f, sh = bot - top;
            float hd = sh * 0.36f, gap = sh * 0.05f;
            float bw = Math.Min(c.Width * 0.56f, sh * 0.78f), bh = sh - hd - gap;
            RectangleF head = new RectangleF(fx - hd / 2, top, hd, hd);
            RectangleF body = new RectangleF(fx - bw / 2, top + hd + gap, bw, bh);
            using (SolidBrush fill = new SolidBrush(Color.FromArgb(Night ? 20 : 50, 255, 255, 255)))
            using (Pen dash = new Pen(Color.FromArgb(Night ? 110 : 150, 160, 120, 80), Math.Max(1.5f, c.Width * 0.018f)))
            using (GraphicsPath bp = RoundRect(body, bw * 0.3f))
            {
                dash.DashStyle = DashStyle.Dash;
                g.FillEllipse(fill, head); g.DrawEllipse(dash, head.X, head.Y, head.Width, head.Height);
                g.FillPath(fill, bp); g.DrawPath(dash, bp);
            }
            float cr = Math.Min(bw, bh) * 0.27f, cx = fx, cy = body.Y + bh / 2;
            using (SolidBrush cb = new SolidBrush(Night ? Color.FromArgb(200, 150, 120, 90) : Color.FromArgb(235, 236, 168, 96)))
                g.FillEllipse(cb, cx - cr, cy - cr, 2 * cr, 2 * cr);
            using (Pen pl = new Pen(Color.White, Math.Max(2f, cr * 0.32f)))
            {
                pl.StartCap = LineCap.Round; pl.EndCap = LineCap.Round;
                g.DrawLine(pl, cx - cr * 0.5f, cy, cx + cr * 0.5f, cy);
                g.DrawLine(pl, cx, cy - cr * 0.5f, cx, cy + cr * 0.5f);
            }
            using (Font f = new Font("Microsoft JhengHei UI", fs, FontStyle.Bold, GraphicsUnit.Pixel))
            using (SolidBrush tb = new SolidBrush(Night ? Color.FromArgb(220, 240, 230, 250) : Color.FromArgb(235, 110, 70, 40)))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center; sf.FormatFlags = StringFormatFlags.NoWrap;
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
                g.DrawString("做一隻你的公仔", f, tb, new RectangleF(c.X - 8, ty, c.Width + 16, th), sf);
            }
        }
    }

    // ================= World：續命小隊的串場、點名、大合照、下班、電量 =================
    partial class World
    {
        public bool OrigLineup { get { return lineup == Pal.Original; } }

        // 沒指定哪一櫃時：照上次的；全新安裝（什麼都還沒存過）就是續命小隊。舊使用者完全不變。
        string StartLineup()
        {
            string saved = ReadText("lineup.txt");
            if (saved != "") return saved;
            bool fresh = !File.Exists(FilePath("out.txt")) && !File.Exists(FilePath("profile.txt")) && !File.Exists(FilePath("usage.txt"));
            // <fan>
            if (fresh)
            {
                string old = LegacyDir();   // 離屏測試（沒指定假的舊資料夾）是空的
                if (old != "" && Directory.Exists(old)) fresh = false;   // 從舊版 Spidey 小夥伴升級的：維持經典一櫃
            }
            // </fan>
            if (!fresh) return "";
            WriteText("lineup.txt", Pal.Original);   // 記下來：下次開機（沒帶參數）還是續命小隊
            return Pal.Original;
        }

        // 舊的像素版續命小隊（半糖、醒醒、糰糰、貼貼）的資料轉給新三隻：半糖→躲躲、醒醒→沒電、糰糰→刺刺（貼貼沒有對應）。只做一次。
        public static string OrigNewId(string id)
        {
            switch (id) { case "boba": return "duoduo"; case "coffee": return "meidian"; case "onigiri": return "cici"; case "sticky": return ""; }
            return id;
        }

        static string OrigSwapIds(string text)
        {
            List<string> o = new List<string>();
            foreach (string t in text.Split(new char[] { ' ', ',', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries)) { string n = OrigNewId(t); if (n != "" && !o.Contains(n)) o.Add(n); }
            return string.Join(" ", o.ToArray());
        }

        static void OrigMigrate()
        {
            try
            {
                if (File.Exists(FilePath("migrated-squad2.txt")) || !Directory.Exists(DataDir)) return;
                for (int i = 0; i < 3; i++)
                {
                    string a = Pal.OldOriginalIds[i], b = Pal.OriginalIds[i];
                    foreach (string pre in new string[] { "bond-", "pats-" })
                    {
                        string fa = FilePath(pre + a + ".txt"), fb = FilePath(pre + b + ".txt");
                        if (File.Exists(fa) && !File.Exists(fb)) File.Copy(fa, fb);
                    }
                }
                foreach (string f in new string[] { "out-original.txt", "fav-original.txt", "active-original.txt" })
                    if (File.Exists(FilePath(f))) WriteText(f, OrigSwapIds(ReadText(f)));
                string mode = ReadText("mode.txt");
                if (mode.StartsWith("single ")) { string n = OrigNewId(mode.Substring(7).Trim()); WriteText("mode.txt", n == "" ? "shelf" : "single " + n); }
                string mine = Path.Combine(Path.Combine(DataDir, "custom"), "mine.txt");
                if (File.Exists(mine)) File.WriteAllText(mine, OrigSwapIds(File.ReadAllText(mine)));
                WriteText("migrated-squad2.txt", DateTime.Now.ToString("s"));
                App.Log("squad2: migrated old original pals");
            }
            catch (Exception ex) { App.Log("squad2 migrate: " + ex.Message); }
        }

        List<Pet> OrigOrder(List<Pet> l)
        {
            List<Pet> o = new List<Pet>();
            foreach (string id in Pal.OriginalIds) foreach (Pet p in l) if (p.P.Id == id) o.Add(p);
            return o;
        }

        // ---------- 選單 ----------
        string[][] OrigMenuItems(Pet p)
        {
            switch (p.P.Id)
            {
                case "duoduo":
                    return new string[][] { new string[] { "抱抱 ♥", "hug" }, new string[] { "打招呼", "hi" }, new string[] { "敲敲螢幕", "knock" }, new string[] { "躲進箱子", "sq_hide" },
                        new string[] { "箱子長腳逃跑", "sq_run" }, new string[] { "跳到別的視窗上", "jump" }, new string[] { "睡覺", "sleep" }, new string[] { "丟球給他 ⚾", "ball" } };
                case "meidian":
                    return new string[][] { new string[] { SqBattery.Link ? "電量 " + SqBattery.Pct + "%" + (SqBattery.Charging ? "（充電中）" : "") : "電量連動關著（滿電）", "sq_battery" },
                        new string[] { "抱抱 ♥", "hug" }, new string[] { "打招呼", "hi" }, new string[] { "敲敲螢幕", "knock" }, new string[] { "插上充電", "sq_charge" },
                        new string[] { "攤平給你看", "sq_flop" }, new string[] { "待機（睡覺）", "sleep" }, new string[] { "丟球給他 ⚾", "ball" } };
                default:
                    return new string[][] { new string[] { "抱抱 ♥", "hug" }, new string[] { "打招呼", "hi" }, new string[] { "敲敲螢幕", "knock" }, new string[] { "開花（被拆穿）", "sq_bloom" },
                        new string[] { "炸毛", "sq_bristle" }, new string[] { "跳到別的視窗上", "jump" }, new string[] { "睡覺", "sleep" }, new string[] { "丟球給她 ⚾", "ball" } };
            }
        }

        void AddOrigMenu(ContextMenuStrip m)
        {
            ToolStripMenuItem grp = new ToolStripMenuItem("續命小隊一起…");
            string[][] gs = { new string[] { "下午三點續命 ⚡", "teatime" }, new string[] { "大合照 📷", "photo" }, new string[] { "點名", "rollcall" }, new string[] { "下班說再見", "byebye" } };
            foreach (string[] gi in gs) { string key = gi[1]; grp.DropDownItems.Add(gi[0], null, delegate { OrigScene(key); }); }
            m.Items.Add(grp);
        }

        // ---------- 電量：工作中慢慢掉、休息（閒置、鎖螢幕、午餐）時充；關掉 Desk Pals 的時間算休息 ----------
        bool batLoaded; double batSaveT;
        void BatTick(double dt)
        {
            if (!batLoaded) BatLoad();
            bool link = Feat("bat_link");
            SqBattery.Link = link;
            if (!link) { SqBattery.Level = 1; SqBattery.Charging = false; return; }
            bool charge = sysIdle || LunchState == "eat" || LunchState == "nap";
            double fullMin = Math.Max(5, restMin / 5);
            if (charge) SqBattery.Level = Math.Min(1, SqBattery.Level + dt / (fullMin * 60));
            else SqBattery.Level = Math.Max(0, SqBattery.Level - dt * 0.9 / (restMin * 60) * (Night ? 1.5 : 1));
            SqBattery.Charging = charge && SqBattery.Level < 1;
            batSaveT -= dt;
            if (batSaveT <= 0) { batSaveT = 30; BatSave(); }
        }

        void BatLoad()
        {
            batLoaded = true;
            string[] a = ReadText("battery.txt").Split(' ');
            double lv, ts;
            if (a.Length >= 2 && double.TryParse(a[0], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out lv) && double.TryParse(a[1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out ts))
            {
                double away = (DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds - ts;
                double fullMin = Math.Max(5, restMin / 5);
                SqBattery.Level = Math.Max(0, Math.Min(1, lv + Math.Max(0, away) / (fullMin * 60)));   // 關著的時間算休息
            }
            else SqBattery.Level = 1;
        }

        void BatSave()
        {
            double now = (DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds;
            WriteText("battery.txt", SqBattery.Level.ToString("0.0000", System.Globalization.CultureInfo.InvariantCulture) + " " + now.ToString("0", System.Globalization.CultureInfo.InvariantCulture));
        }

        // pipe：battery-set <0～100> [charge]、battery-dump（測試用）
        bool OrigMsg(Client c, string[] p, string line)
        {
            switch (p[0])
            {
                case "battery-set":
                    {
                        double v;
                        if (p.Length >= 2 && double.TryParse(p[1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out v)) { batLoaded = true; SqBattery.Level = Math.Max(0, Math.Min(1, v / 100)); }
                        batForceCharge = p.Length >= 3 && p[2] == "charge";
                        SqBattery.Charging = batForceCharge;
                        Send(c, "battery " + SqBattery.Pct + "\n");
                    }
                    return true;
                case "battery-dump": { Pal m = Pal.Get("meidian"); Send(c, SqBattery.Dump(m == null ? null : m.Spr)); } return true;
                case "battery-link": if (p.Length >= 2) { bool on = p[1] == "1"; if (Feat("bat_link") != on) { feats["bat_link"] = on; SaveFeatures(); App.Log("feature bat_link=" + (on ? 1 : 0) + " (VS Code)"); } } return true;   // VS Code 設定推過來（安靜地改，不講話）
            }
            return false;
        }
        bool batForceCharge;

        // ---------- 每一格：電量、午餐、下午三點 ----------
        string oLunchSeen = "", oTeaDay = "";
        void OrigTick(double dt)
        {
            if (batForceCharge) { SqBattery.Charging = true; SqBattery.Level = Math.Min(1, SqBattery.Level + dt / 600); }
            else BatTick(dt);
            if (!OrigLineup) return;
            if (LunchState != oLunchSeen)
            {
                if (LunchState == "eat" && oLunchSeen == "" && OutCount() >= 2) Later(4, delegate { if (scene == null && OrigLineup) OrigScene("lunch"); });
                oLunchSeen = LunchState;
            }
            DateTime n = DateTime.Now;
            string today = n.ToString("yyyy-MM-dd");
            if (n.Hour == 15 && n.Minute < 10 && !Night && oTeaDay != today && scene == null && OutCount() >= 2 && Feat("scenes") && !focusOn && !quietOn)
            {
                oTeaDay = today;
                OrigScene("teatime");
            }
        }

        // ---------- 串場：大家一起 ----------
        void OrigGroup(int n)
        {
            if (rnd.NextDouble() < 0.5) OrigScene("teatime"); else OrigPhoto();
        }

        void OrigScene(string key)
        {
            List<Pet> outs = OrigOrder(OutPets());
            if (outs.Count < 2 && key != "rollcall" && key != "byebye") { AllOut(); Later(2.6, delegate { if (OrigLineup) OrigScene(key); }); return; }
            switch (key)
            {
                case "teatime": SceneTeaTime(outs); break;
                case "lunch": SceneOrigLunch(outs); break;
                case "photo": case "group": OrigPhoto(); break;
                case "rollcall": { List<string> ids = new List<string>(); foreach (Pet p in outs) ids.Add(p.P.Id); if (ids.Count == 0) ids.AddRange(Pal.OriginalIds); OrigRollCall(ids); } break;
                case "byebye": OrigNight(false); break;
            }
        }

        void OrigPairScene(string key)
        {
            Pet d = Get("duoduo"), m = Get("meidian"), c = Get("cici");
            switch (key)
            {
                case "cici-meidian": if (c != null && m != null) ScenePlugPot(m, c); break;
                case "duoduo-meidian": if (d != null && m != null) SceneBoxBed(d, m); break;
                case "cici-duoduo": if (c != null && d != null) SceneWhereDidHeGo(d, c); break;
            }
        }

        // ---------- 沒電 × 刺刺：插在盆土裡充電 ----------
        void ScenePlugPot(Pet m, Pet c)
        {
            Begin(m, c);
            At(0, delegate { Face(m, c); m.ScenePose("idle", 30); c.ScenePose("idle", 30); m.Say("刺刺…你的盆土看起來很導電", 2.2); });
            At(2.4, delegate { c.OPose("pout", 30); c.Say("……你想幹嘛", 1.8); });
            At(4.4, delegate { m.OrigDo("charge", 30); m.Say("插上了……嗯……", 1.8); });
            At(6.2, delegate { c.OrigDo("bristle", 2.2); c.Say("插哪裡啊！！", 1.8); });
            At(8.6, delegate { c.OPose("pout", 30); c.Say("……", 1.2); });
            At(10.0, delegate { c.OrigDo("bloom", 30); c.Say("……只准充一下", 2); if (SqBattery.Link) SqBattery.Level = Math.Min(1, SqBattery.Level + 0.05); });
            At(12.4, delegate { m.OPose("happy", 2.4); m.Say("電量 +5%…謝謝刺刺 ♥", 2.2); });
            At(15.0, delegate { Face(m, c); m.ScenePose("hug", 2.4); c.ScenePose("hug", 2.4); c.Say("不准說出去", 1.8); });
            At(17.6, delegate { });
        }

        // ---------- 躲躲 × 沒電：箱子讓給沒電當床 ----------
        void SceneBoxBed(Pet d, Pet m)
        {
            Begin(d, m);
            At(0, delegate { Face(d, m); d.ScenePose("idle", 30); m.OPose("pout", 30); m.Say("好累…有沒有地方可以躺…", 2.2); });
            At(2.6, delegate { d.OPose("surprised", 1.6); d.Say("那個…我的箱子…借你？", 2); });
            At(4.8, delegate { d.OrigDo("hide", 30); d.Say("（箱子蓋起來，變成一張床）", 2); });
            At(7.0, delegate { m.OPose("sleep", 30); m.Say("好軟的箱子…（秒睡）", 2); m.Mark(3); });
            At(9.6, delegate { d.Say("……我自己要躲哪裡", 1.8); d.Mark(2); });
            At(12.0, delegate { m.OPose("happy", 2); m.Say("睡飽了！…電量沒變就是了", 2.2); });
            At(14.4, delegate { d.OPose("happy", 2.4); d.Say("嘿嘿…箱子很好睡吧", 1.8); });
            At(16.8, delegate { Face(d, m); d.ScenePose("hug", 2.4); m.ScenePose("hug", 2.4); });
            At(19.0, delegate { });
        }

        // ---------- 躲躲 × 刺刺：他去哪了 ----------
        void SceneWhereDidHeGo(Pet d, Pet c)
        {
            Begin(d, c);
            At(0, delegate { Face(d, c); c.OPose("pout", 30); c.Say("躲躲，你又在躲什麼", 2); });
            At(2.2, delegate { d.OrigDo("hide", 30); d.Say("我不在。", 1.4); });
            At(4.0, delegate { c.OPose("pout", 30); c.Say("……哼，誰要找你", 1.8); });
            At(6.4, delegate { c.OPose("surprised", 30); c.Say("……他去哪了", 1.6); c.Mark(2); });
            At(8.4, delegate { d.OPose("surprised", 30); d.Say("（探頭）你在找我？", 1.8); });
            At(10.4, delegate { c.OrigDo("bloom", 30); c.Say("才、才沒有！這是花粉過敏！", 2.2); });
            At(13.0, delegate { d.OPose("happy", 2.4); d.Say("嘿嘿，刺刺開花了", 1.8); });
            At(15.2, delegate { Face(d, c); d.ScenePose("hug", 2.4); c.ScenePose("hug", 2.4); c.Say("……只准抱一下", 1.6); });
            At(17.6, delegate { });
        }

        // ---------- 大家：下午三點續命 ----------
        void SceneTeaTime(List<Pet> outs)
        {
            Pet m = Get("meidian");
            Pet lead = m != null && outs.Contains(m) ? m : outs[0];
            Begin(outs.ToArray());
            LineUp(outs, Lead(), 2.7);
            At(0, delegate { lead.Say("三點了…下午的電最難撐 ⚡", 2.2); });
            At(4.4, delegate { foreach (Pet p in outs) { p.FaceTo(lead); p.ScenePose("idle", 30); } });
            double d = 4.8;
            foreach (Pet p in outs)
            {
                Pet pp = p;
                string line = pp.P.Id == "duoduo" ? "點心…可以帶回箱子吃嗎" : (pp.P.Id == "meidian" ? "續命！電量 +10%（心理上）" : "我不用續命。…一口就好");
                At(d, delegate { pp.OPose(pp.P.Id == "meidian" ? "sig1" : "happy", 1.6); pp.Say(line, 1.8); if (pp.P.Id == "meidian" && SqBattery.Link) SqBattery.Level = Math.Min(1, SqBattery.Level + 0.02); });
                d += 2.0;
            }
            At(d + 0.4, delegate { foreach (Pet p in outs) { p.OPose("happy", 2.4); p.AddHeart(); p.Burst(5); } lead.Say("續命成功！乾杯～", 2.2); });
            At(d + 3.2, delegate { foreach (Pet p in outs) p.ScenePose("wave", 1.6); });
            At(d + 5.0, delegate { });
        }

        // ---------- 大家：午餐一起吃 ----------
        void SceneOrigLunch(List<Pet> outs)
        {
            Begin(outs.ToArray());
            LineUp(outs, Lead(), 2.7);
            At(0, delegate { outs[0].Say("午餐時間！大家一起吃～🔔", 2); });
            double d = 4.6;
            foreach (Pet p in outs)
            {
                Pet pp = p;
                string line = pp.P.Id == "duoduo" ? "我躲在箱子裡吃…" : (pp.P.Id == "meidian" ? "吃飯＝充電，開動" : "我才不餓。…開動");
                At(d, delegate { pp.OPose("sit", 30); pp.Say(line, 2.3); });
                d += 2.5;
            }
            At(d + 0.4, delegate { foreach (Pet p in outs) p.ScenePose("wave", 1.6); outs[outs.Count - 1].Say("開動！", 1.6); });
            At(d + 2.4, delegate { });
        }

        // ---------- 大合照 ----------
        void OrigPhoto()
        {
            List<Pet> outs = OrigOrder(OutPets());
            if (outs.Count < 2) { AllOut(); Later(2.5, delegate { if (OrigLineup) OrigPhoto(); }); return; }
            Pet l = Lead();
            Begin(outs.ToArray());
            double[] lr = LineUp(outs, l, 2.7);
            double left = lr[0], right = lr[1], foot = lr[2];
            At(0, delegate { l.Say("續命小隊，來拍照～排好排好！", 2); });
            At(5.2, delegate
            {
                foreach (Pet p in outs)
                {
                    p.dir = p.Cx < (left + right) / 2 ? 1 : -1;
                    p.OPose(p.P.Id == "duoduo" ? "surprised" : (p.P.Id == "cici" ? "pout" : "happy"), 30);
                }
                l.Say("笑一個～ 3、2、1！", 1.6);
            });
            At(6.6, delegate { Flash(Rectangle.FromLTRB((int)(left - 120 * k), (int)(foot - 220 * k), (int)(right + 120 * k), (int)(foot + 20 * k))); });
            double d = 7.4;
            foreach (Pet p in outs)
            {
                Pet pp = p;
                string line = pp.P.Id == "duoduo" ? "我、我有拍到嗎…（躲）" : (pp.P.Id == "meidian" ? "閃光燈好耗電…" : "我才沒有笑。");
                At(d, delegate { if (pp.P.Id == "duoduo") pp.OrigDo("hide", 2); else if (pp.P.Id == "cici") pp.OrigDo("bloom", 2); pp.Say(line, 1.4); });
                d += 1.4;
            }
            At(d + 0.4, delegate { });
        }

        // ---------- 早上點名：一隻一隻出來 ----------
        void OrigRollCall(List<string> ids)
        {
            List<Pet> order = new List<Pet>();
            foreach (string id in Pal.OriginalIds) if (ids.Contains(id) && Get(id) != null) order.Add(Get(id));
            double d = 0.4;
            foreach (Pet p in order)
            {
                Pet pp = p;
                string line = pp.P.Id == "duoduo" ? "躲躲…到（小聲）📦" : (pp.P.Id == "meidian" ? "沒電，到…（剩 " + SqBattery.Pct + "%）🔋" : "刺刺。到。🌵");
                Later(d, delegate { if (!pp.Out) BringOut(pp, false); });
                Later(d + 1.0, delegate { pp.Say(line, 1.8); });
                d += 1.6;
            }
            Later(d + 1.0, delegate
            {
                foreach (Pet p in order) if (p.Out && p.Grounded()) p.ScenePose("wave", 1.8);
                if (order.Count > 0) Lead().Say("續命小隊，報到！", 2.6);
            });
        }

        // ---------- 下班：一個一個回櫃子（沒電最後，因為走最慢）----------
        void OrigNight(bool nag)
        {
            List<Pet> outs = OrigOrder(OutPets());
            if (outs.Count == 0) { Lead().Say("續命小隊…下班囉～", 2.4); return; }
            outs.Sort(delegate(Pet a, Pet b) { return (a.P.Id == "meidian" ? 1 : 0).CompareTo(b.P.Id == "meidian" ? 1 : 0); });
            Begin(outs.ToArray());
            foreach (Pet p in outs) if (p.Grounded()) p.ScenePose("idle", 60);
            double d = 0.2;
            if (nag) foreach (Pet p in outs) { Pet pp = p; At(d, delegate { pp.Say(pp.L("nag"), 2.6); }); d += 2.8; }
            foreach (Pet p in outs)
            {
                Pet pp = p;
                string line = pp.P.Id == "duoduo" ? "回箱子…不是，回櫃子囉" : (pp.P.Id == "cici" ? "下班。…路上小心（小聲）" : "關機囉…明天見");
                At(d, delegate { pp.ScenePose("wave", 2); pp.Say(line, 2.2); });
                At(d + 1.6, delegate { pp.InScene = false; if (pp.Out) pp.StowToShelf(false); });
                d += 2.6;
            }
            At(d + 0.6, delegate { Pet last = outs[outs.Count - 1]; last.Say("續命小隊，下班！明天見～", 2.6); });
            At(d + 3.4, delegate { });
        }

        // ---------- 通知的開場白、搶票 ----------
        static string OrigFlavor(string id, string kind)
        {
            if (id != "duoduo" && id != "meidian" && id != "cici") return null;
            string[] keys = { "ci-run", "ci-ok", "ci-fail", "cmd-ok", "cmd-fail", "meeting", "meeting-now", "jira", "worklog",
                              "remind", "pc-cpu", "pc-ram", "pc-disk", "net-down", "net-up", "vpn", "download" };
            int i = Array.IndexOf(keys, kind);
            if (i < 0) return null;
            string[] dd = { "CI 開始跑了…（偷看）", "CI 過了！我出來一下下！", "CI 失敗了…我先躲：", "跑完了…：", "沒成功…（縮）：", "等等要開會…好緊張：", "開會了！快去（我躲好了）", "有新的 Jira…：", "今天的日誌好了：",
                            "⏰ 躲躲提醒你（小聲）：", "電腦好燙…箱子要融化了：", "記憶體快滿了…像塞爆的箱子：", "硬碟快滿了…：", "網路斷了…包裹送不到了", "網路回來了！", "連不到公司網路（VPN 斷了？）", "下載好了…是新的包裹嗎：" };
            string[] md = { "CI 開跑…好耗電：", "CI 過了！電量 +1%", "CI 掛了…我也快掛了：", "跑完了：", "失敗了…先充電再看：", "等等開會…我撐得住（騙人）：", "開會了…待機模式啟動：", "新的 Jira：", "日誌好了，可以關機了：",
                            "⏰ 沒電提醒你（剩 {p}%）：", "電腦好燙…我也好燙：", "記憶體快滿了：", "硬碟快滿了：", "網路斷了…正好省電", "網路回來了…", "連不到公司網路（VPN 斷了？）", "下載好了：" };
            string[] cc = { "CI 開跑了。看什麼：", "CI 過了。…還行啦", "CI 掛了？又不是我寫的：", "跑完了：", "失敗了。哼：", "等等要開會。別遲到：", "開會了！快去！", "新的 Jira。去看：", "日誌好了。不用謝：",
                            "⏰ 提醒你（才不是關心）：", "電腦好燙！你在幹嘛：", "記憶體快滿了：", "硬碟快滿了，東西要收：", "網路斷了！…不是我拔的", "網路回來了。哼", "連不到公司網路（VPN 斷了？）", "下載好了：" };
            string s = id == "duoduo" ? dd[i] : (id == "meidian" ? md[i] : cc[i]);
            return s.Replace("{p}", SqBattery.Pct.ToString());
        }

        static string OrigTicket(string id, int stage, string n, string h)
        {
            if (id != "duoduo" && id != "meidian" && id != "cici") return null;
            string[] dd = { "🎫 " + n + " 還有 " + h + "開賣…先登入、綁好付款喔", "🎫 " + n + " 再 30 分鐘…好緊張", "🎫 " + n + " 剩 10 分鐘！我躲好了", "🎫 準、準備…", "🎫 開搶！！（衝出箱子）" };
            string[] md = { "🎫 " + n + " 還有 " + h + "開賣。先登入、綁好付款", "🎫 " + n + " 30 分鐘後開賣…我先充電", "🎫 " + n + " 剩 10 分鐘！電量全開", "🎫 準備。手指放好。", "🎫 開搶！！用掉我最後的電！" };
            string[] cc = { "🎫 " + n + " 還有 " + h + "開賣。先登入、綁好付款，別到時候哭", "🎫 " + n + " 再 30 分鐘。我才沒有很期待", "🎫 " + n + " 剩 10 分鐘！刺都豎起來了", "🎫 準備！", "🎫 開搶！！快啊！" };
            return id == "duoduo" ? dd[stage] : (id == "meidian" ? md[stage] : cc[stage]);
        }
    }
}
