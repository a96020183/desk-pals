// Desk Pals：一鍵分享短片（離屏畫出來、自己寫的 GIF 編碼器）＋自己做的公仔匯出／匯入（.deskpal＝JSON 包 PNG）。
// 不擷取真的螢幕（隱私）；不連網；不用任何外部套件。
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
    using System.Threading;
    using System.Web.Script.Serialization;
    using System.Windows.Forms;

    // ================= GIF89a 編碼器（減色＋LZW，只用來存分享短片） =================
    static class GifWriter
    {
        // frames：每格 ARGB（不透明）；delayCs：每格幾個 1/100 秒
        public static void Write(string path, List<int[]> frames, int w, int h, int delayCs)
        {
            // 1) 全部格子共用一組 255 色（取樣做中位切割）
            List<int> samples = new List<int>();
            int stride = Math.Max(1, (w * h * frames.Count) / 400000);
            int off = 0;
            for (int f = 0; f < frames.Count; f += 2)
                for (int i = off; i < frames[f].Length; i += stride) samples.Add(frames[f][i] | unchecked((int)0xFF000000));
            List<int> pal = CuImg.MedianCut(samples, 255);
            Dictionary<int, byte> cache = new Dictionary<int, byte>();
            byte[][] idx = new byte[frames.Count][];
            for (int f = 0; f < frames.Count; f++)
            {
                int[] px = frames[f];
                byte[] o = new byte[px.Length];
                for (int i = 0; i < px.Length; i++)
                {
                    int v = px[i] & 0xFFFFFF;
                    byte b;
                    if (!cache.TryGetValue(v, out b)) { b = (byte)Nearest(pal, v); cache[v] = b; }
                    o[i] = b;
                }
                idx[f] = o;
            }
            using (FileStream fs = new FileStream(path, FileMode.Create, FileAccess.Write))
            using (BinaryWriter bw = new BinaryWriter(fs))
            {
                bw.Write(Encoding.ASCII.GetBytes("GIF89a"));
                bw.Write((ushort)w); bw.Write((ushort)h);
                bw.Write((byte)0xF7); bw.Write((byte)0); bw.Write((byte)0);
                for (int i = 0; i < 256; i++)
                {
                    int c = i < pal.Count ? pal[i] : 0;
                    bw.Write((byte)((c >> 16) & 255)); bw.Write((byte)((c >> 8) & 255)); bw.Write((byte)(c & 255));
                }
                // 一直重播
                bw.Write(new byte[] { 0x21, 0xFF, 0x0B });
                bw.Write(Encoding.ASCII.GetBytes("NETSCAPE2.0"));
                bw.Write(new byte[] { 0x03, 0x01, 0x00, 0x00, 0x00 });
                for (int f = 0; f < idx.Length; f++)
                {
                    // 只存跟上一格不一樣的那一塊（檔案小很多）
                    int x0 = 0, y0 = 0, x1 = w - 1, y1 = h - 1;
                    if (f > 0)
                    {
                        byte[] a = idx[f], p = idx[f - 1];
                        x0 = w; y0 = h; x1 = -1; y1 = -1;
                        for (int y = 0; y < h; y++)
                            for (int x = 0; x < w; x++)
                                if (a[y * w + x] != p[y * w + x]) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
                        if (x1 < 0) { x0 = 0; y0 = 0; x1 = 0; y1 = 0; }
                    }
                    int rw = x1 - x0 + 1, rh = y1 - y0 + 1;
                    byte[] sub = new byte[rw * rh];
                    for (int y = 0; y < rh; y++) Array.Copy(idx[f], (y0 + y) * w + x0, sub, y * rw, rw);
                    bw.Write(new byte[] { 0x21, 0xF9, 0x04, 0x04 });
                    bw.Write((ushort)delayCs); bw.Write((byte)0); bw.Write((byte)0);
                    bw.Write((byte)0x2C);
                    bw.Write((ushort)x0); bw.Write((ushort)y0); bw.Write((ushort)rw); bw.Write((ushort)rh);
                    bw.Write((byte)0);
                    bw.Write((byte)8);
                    Lzw(bw, sub);
                }
                bw.Write((byte)0x3B);
            }
        }

        static int Nearest(List<int> pal, int v)
        {
            int r = (v >> 16) & 255, g = (v >> 8) & 255, b = v & 255, best = 0, bd = int.MaxValue;
            for (int i = 0; i < pal.Count; i++)
            {
                int p = pal[i], dr = ((p >> 16) & 255) - r, dg = ((p >> 8) & 255) - g, db = (p & 255) - b;
                int dd = 3 * dr * dr + 4 * dg * dg + 2 * db * db;
                if (dd < bd) { bd = dd; best = i; }
            }
            return best;
        }

        // LZW（GIF 版：8 位元起跳、最多 12 位元、滿了就清表）
        static void Lzw(BinaryWriter bw, byte[] data)
        {
            const int clear = 256, eoi = 257;
            int codeSize = 9, next = 258;
            Dictionary<int, int> dict = new Dictionary<int, int>();
            List<byte> outb = new List<byte>();
            int acc = 0, nbits = 0;
            Action<int> emit = delegate(int code)
            {
                acc |= code << nbits; nbits += codeSize;
                while (nbits >= 8) { outb.Add((byte)(acc & 255)); acc >>= 8; nbits -= 8; }
            };
            emit(clear);
            int prefix = data.Length > 0 ? data[0] : 0;
            for (int i = 1; i < data.Length; i++)
            {
                int k = data[i], key = (prefix << 8) | k, code;
                if (dict.TryGetValue(key, out code)) { prefix = code; continue; }
                emit(prefix);
                if (next < 4096)
                {
                    if (next > (1 << codeSize) - 1 && codeSize < 12) codeSize++;
                    dict[key] = next++;
                }
                else
                {
                    emit(clear);
                    dict.Clear(); next = 258; codeSize = 9;
                }
                prefix = k;
            }
            emit(prefix);
            if (next > (1 << codeSize) - 1 && codeSize < 12) codeSize++;
            emit(eoi);
            if (nbits > 0) outb.Add((byte)(acc & 255));
            for (int i = 0; i < outb.Count; i += 255)
            {
                int n = Math.Min(255, outb.Count - i);
                bw.Write((byte)n);
                for (int j = 0; j < n; j++) bw.Write(outb[i + j]);
            }
            bw.Write((byte)0);
        }
    }

    // ================= 分享短片：照劇本畫出來（走進來 → 揮手打招呼 → 開心跳兩下冒愛心） =================
    partial class Pet
    {
        // 分享短片用：在指定位置、指定大小畫一格（不動到真的公仔）
        public void ShareDraw(Graphics g, double feetX, double feetY, int ps, string st, double an, int d, double vyHint, double landT)
        {
            bool wasOut = Out;
            Out = true; state = st; anim = an; dir = d; vy = vyHint; rolling = false; Bt = 0; knock = 0; cuAct = ""; cuLandT = landT; poseKind = "";
            sc = ps / (double)S;
            x = feetX - SW / 2.0; y = feetY - SH;
            PaintPet(g, 0, 0);
            sc = 1; Out = wasOut;
        }
        public string ShareLine(string key) { return L(key); }
    }

    partial class World
    {
        bool sharing2;

        // 選單：做分享短片（存到 圖片\Desk Pals、說明文字放進剪貼簿、打開資料夾）
        public void ShareClip(Pet who)
        {
            if (sharing2) return;
            string dir = App.Offscreen ? Path.Combine(DataDir, "share") : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "WoWo Pals");
            ShareClipTo(dir, who);
        }

        public void ShareClipTo(string dir, Pet who)
        {
            if (sharing2) return;
            sharing2 = true;
            Pet l = who ?? Lead();
            l.Say("拍攝中…🎬 （大概 5 秒的小短片）", 2.5);
            Later(0.15, delegate
            {
                // 主角：你點的那隻；從小屋拍的話，有自己做的公仔在外面就讓他當主角
                Pet star = l;
                if (who == null && !l.P.Cu) foreach (Pet p in OutPets()) if (p.P.Cu) { star = p; break; }
                List<Pal> cast = new List<Pal>();
                cast.Add(star.P);
                foreach (Pet p in OutPets()) if (p != star && cast.Count < 4) cast.Add(p.P);
                int W0 = 540, H0 = 540, fps = 15, n = 5 * fps;
                List<int[]> frames;
                string caption;
                try { frames = ShareFrames(cast, W0, H0, fps, n, out caption); }
                catch (Exception ex) { App.Log("share: " + ex); sharing2 = false; l.Say("拍攝失敗了…再試一次？", 2.4); return; }
                string name = "DeskPals-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".gif";
                string path = Path.Combine(dir, name);
                Thread th = new Thread(delegate()
                {
                    string err = null;
                    try { Directory.CreateDirectory(dir); GifWriter.Write(path, frames, W0, H0, 100 / fps); File.WriteAllText(Path.ChangeExtension(path, ".txt"), caption, new UTF8Encoding(false)); }
                    catch (Exception ex) { err = ex.Message; }
                    Post(delegate { ShareDone(l, path, caption, err); });
                });
                th.IsBackground = true;
                th.Start();
            });
        }

        void ShareDone(Pet l, string path, string caption, string err)
        {
            sharing2 = false;
            if (err != null) { App.Log("share: " + err); l.Say("存不起來…（" + err + "）", 3); return; }
            long kb = 0; try { kb = new FileInfo(path).Length / 1024; } catch { }
            App.Log("share saved " + path + " " + kb + "KB");
            if (!App.Offscreen)
            {
                try
                {
                    // 剪貼簿：同時放 GIF 檔（貼到聊天室＝傳圖）和說明文字（貼到文字框＝那句話）
                    DataObject d = new DataObject();
                    System.Collections.Specialized.StringCollection files = new System.Collections.Specialized.StringCollection();
                    files.Add(path);
                    d.SetFileDropList(files);
                    d.SetText(caption, TextDataFormat.UnicodeText);
                    Clipboard.SetDataObject(d, true);
                }
                catch (Exception ex) { App.Log("share clipboard: " + ex.Message); }
                try { Process.Start("explorer.exe", "/select,\"" + path + "\""); } catch { }
            }
            l.Say("短片做好了！存在「圖片\\WoWo Pals」，說明文字也複製好了，直接貼上就能分享 🎬", 5);
        }

        // 畫每一格：可愛的小桌面背景＋公仔照劇本動
        List<int[]> ShareFrames(List<Pal> cast, int W0, int H0, int fps, int n, out string caption)
        {
            World pw = new World(S, Pal.Fallback);
            bool bdayClip = SeasonNow == "birthday";   // 生日：短片拍成生日版（捧蛋糕、戴派對帽、灑彩帶），所以驚喜能被錄下來分享
            if (bdayClip) { pw.SeasonNow = "birthday"; pw.BdayHatOn = true; }
            List<Pet> pets = new List<Pet>();
            int seed = 11;
            foreach (Pal p in cast) pets.Add(new Pet(pw, p, S, seed++));
            Pal hero = cast[0];
            Pet heroPet = pets[0];
            caption = null;
            foreach (Pet p in pets) if (p.P.Cu) { caption = p.ShareLine("x_share"); break; }
            if (string.IsNullOrEmpty(caption)) caption = bdayClip ? "生日快樂！我的桌面公仔一起幫我慶生 🎂 #我的桌面公仔 #WoWoPals" : "我的桌面公仔在螢幕上陪我上班 ✨ #我的桌面公仔 #WoWoPals";
            string hi = NoEmoji(heroPet.ShareLine("hi"));
            int ps = cast.Count == 1 ? 13 : (cast.Count == 2 ? 11 : (cast.Count == 3 ? 9 : 7));
            List<int[]> frames = new List<int[]>();
            using (Bitmap bg = ShareBackground(W0, H0, hero))
            using (Bitmap fr = new Bitmap(W0, H0, PixelFormat.Format32bppArgb))
            using (Font bf = new Font("Microsoft JhengHei UI", 15f, FontStyle.Bold, GraphicsUnit.Pixel))
            {
                double floor = H0 * 0.80;
                for (int i = 0; i < n; i++)
                {
                    double t = i / (double)fps;
                    using (Graphics g = Graphics.FromImage(fr))
                    {
                        g.DrawImageUnscaled(bg, 0, 0);
                        if (bdayClip) ShareConfetti(g, W0, H0, t, ps);   // 生日：灑彩帶
                        g.SmoothingMode = SmoothingMode.AntiAlias;
                        for (int j = 0; j < pets.Count; j++)
                        {
                            double tx = W0 * (j + 1) / (double)(pets.Count + 1);
                            double t0 = j * 0.25, walkEnd = 1.9 + t0;
                            double sx = -W0 * 0.18 - j * W0 * 0.1;
                            double fx = tx, fy = floor, vyh = 0, land = 0;
                            string st; int d = 1;
                            if (t < walkEnd)
                            {
                                double u = Math.Max(0, (t - t0) / (walkEnd - t0));
                                fx = sx + (tx - sx) * (1 - (1 - u) * (1 - u));
                                st = "walk";
                            }
                            else if (t < 2.6) { st = "idle"; d = tx < W0 / 2 ? 1 : -1; }
                            else if (t < 3.5) { st = "wave"; d = tx < W0 / 2 ? 1 : -1; }
                            else
                            {
                                // 開心跳兩下
                                double c = (t - 3.5 - j * 0.08);
                                st = "hug"; d = tx < W0 / 2 ? 1 : -1;
                                double hc = c % 0.75;
                                if (c > 0 && c < 1.5 && hc < 0.5) { st = pets[j].P.Cu ? "air" : "hug"; double u = hc / 0.5; fy -= Math.Sin(u * Math.PI) * ps * 4; vyh = u < 0.5 ? -1 : 1; }
                                else if (c > 0 && hc < 0.62) land = 0.2 - (hc - 0.5) * 1.6;
                            }
                            if (pets.Count == 1 && t >= walkEnd) d = 1;
                            pets[j].ShareDraw(g, fx, fy, ps, st, t, d, vyh, Math.Max(0, land));
                            // 愛心
                            if (t >= 3.5)
                                for (int k = 0; k < 3; k++)
                                {
                                    double ph = ((t - 3.5) * 0.8 + k / 3.0) % 1;
                                    int hp = Math.Max(3, ps / 2);
                                    ShareHeart(g, fx + (k - 1) * ps * 4 + Math.Sin(ph * 6 + k) * ps, floor - 17 * ps - ph * ps * 9, hp, (int)(255 * Math.Min(1, (1 - ph) * 2.5)));
                                }
                        }
                        // 打招呼的泡泡
                        if (t >= 2.4 && t < 3.7 && !string.IsNullOrEmpty(hi))
                        {
                            double tx = W0 / (double)(pets.Count + 1);
                            ShareBubble(g, hi, bf, tx, floor - (hero.Cu ? hero.Spr.Hc : 16 + hero.TopRows) * ps - 22, W0, hero.Accent);
                        }
                    }
                    frames.Add(CuImg.Pixels(fr));
                }
            }
            return frames;
        }

        // 生日：短片裡飄落的彩帶（固定亂數，每格位置連續）
        static readonly int[] ConfettiCols = { 0xFF5A5A, 0xFFD84A, 0x5AD1FF, 0xFF8FD8, 0x8CFF8C, 0xFFA64A };
        static void ShareConfetti(Graphics g, int W0, int H0, double t, int ps)
        {
            Random r = new Random(23);
            int sz = Math.Max(4, ps);
            for (int i = 0; i < 48; i++)
            {
                double x0 = r.NextDouble() * W0, speed = (0.35 + r.NextDouble() * 0.5) * H0;
                double sway = Math.Sin(t * (1.5 + r.NextDouble()) + i) * sz * 2;
                double y = ((r.NextDouble() * H0) + t * speed) % (H0 + sz) - sz;
                int x = (int)(x0 + sway);
                using (SolidBrush b = new SolidBrush(Pix.C(ConfettiCols[i % ConfettiCols.Length])))
                    g.FillRectangle(b, x, (int)y, sz, (i % 2 == 0) ? sz : sz / 2);
            }
        }

        static void ShareHeart(Graphics g, double cx, double cy, int u, int alpha)
        {
            if (alpha <= 10) return;
            string[] h = { ".pp.pp.", "ppppppp", "ppppppp", ".ppppp.", "..ppp..", "...p..." };
            using (SolidBrush wb = new SolidBrush(Color.FromArgb(alpha, 255, 255, 255)))
            using (SolidBrush pb = new SolidBrush(Color.FromArgb(alpha, 0xFF, 0x6F, 0x9C)))
            {
                int x0 = (int)(cx - 3.5 * u), y0 = (int)(cy - 3 * u);
                for (int pass = 0; pass < 2; pass++)
                    for (int r = 0; r < h.Length; r++)
                        for (int c = 0; c < h[r].Length; c++)
                        {
                            if (h[r][c] == '.') continue;
                            if (pass == 0) g.FillRectangle(wb, x0 + c * u - u / 2, y0 + r * u - u / 2, 2 * u, 2 * u);
                            else g.FillRectangle(pb, x0 + c * u, y0 + r * u, u, u);
                        }
            }
        }

        // 像素風泡泡（跟桌面上的一樣：切角方框＋往下的小尾巴）
        static void ShareBubble(Graphics g, string s, Font f, double cx, double bottom, int W0, Color accent)
        {
            Size ts = PixText.MeasureText(s, f, new Size(4000, 400), TextFormatFlags.NoPadding);
            int w = ts.Width + 28, h = ts.Height + 18;
            int x = (int)Math.Max(10, Math.Min(W0 - w - 10, cx - w / 2.0)), y = (int)(bottom - h - 8);
            using (SolidBrush lb = new SolidBrush(accent))
            using (SolidBrush fill = new SolidBrush(Color.White))
            {
                g.SmoothingMode = SmoothingMode.None;
                g.FillRectangle(lb, x + 3, y, w - 6, h); g.FillRectangle(lb, x, y + 3, w, h - 6); g.FillRectangle(lb, x + 1, y + 1, w - 2, h - 2);
                g.FillRectangle(fill, x + 4, y + 3, w - 8, h - 6); g.FillRectangle(fill, x + 3, y + 4, w - 6, h - 8);
                int tx = (int)Math.Max(x + 14, Math.Min(x + w - 14, cx));
                for (int i = 0; i < 9; i++) g.FillRectangle(lb, tx - 9 + i, y + h - 1 + i, 18 - 2 * i, 1);
                for (int i = 0; i < 7; i++) g.FillRectangle(fill, tx - 7 + i, y + h - 3 + i, 14 - 2 * i, 1);
            }
            PixText.DrawText(g, s, f, new Rectangle(x, y, w, h), Color.FromArgb(0x2A, 0x2F, 0x45), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
        }

        // 背景：一面淡淡的牆（色帶）、窗戶、小星星、木頭桌面、右下角浮水印
        static Bitmap ShareBackground(int W0, int H0, Pal hero)
        {
            Bitmap b = new Bitmap(W0, H0, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(b))
            {
                Color top = Pix.Mix(hero.Panel, Color.White, 0.35), bot = Pix.Mix(hero.Panel, Pix.C(0xF6D9C0), 0.45);
                int floorY = (int)(H0 * 0.80), bands = 9;
                for (int i = 0; i < bands; i++)
                {
                    int y0 = floorY * i / bands, y1 = floorY * (i + 1) / bands;
                    using (SolidBrush sb = new SolidBrush(Pix.Mix(top, bot, i / (double)(bands - 1)))) g.FillRectangle(sb, 0, y0, W0, y1 - y0);
                }
                // 窗戶（左上）
                int u = 6, wx = 46, wy = 54, ww = 22 * u, wh = 17 * u;
                using (SolidBrush fr = new SolidBrush(Pix.C(0x9A6338))) g.FillRectangle(fr, wx - u, wy - u, ww + 2 * u, wh + 2 * u);
                using (SolidBrush sky = new SolidBrush(Pix.C(0xBFE3F2))) g.FillRectangle(sky, wx, wy, ww, wh);
                using (SolidBrush cl = new SolidBrush(Color.White)) { g.FillRectangle(cl, wx + 3 * u, wy + 4 * u, 6 * u, 2 * u); g.FillRectangle(cl, wx + 4 * u, wy + 3 * u, 3 * u, u); g.FillRectangle(cl, wx + 12 * u, wy + 9 * u, 5 * u, 2 * u); }
                using (SolidBrush fr = new SolidBrush(Pix.C(0x9A6338))) { g.FillRectangle(fr, wx + ww / 2 - u / 2, wy, u, wh); g.FillRectangle(fr, wx, wy + wh / 2 - u / 2, ww, u); }
                // 小星星
                Random r = new Random(7);
                using (SolidBrush st = new SolidBrush(Color.FromArgb(200, 255, 255, 255)))
                    for (int i = 0; i < 14; i++)
                    {
                        int sx = 220 + r.Next(W0 - 250), sy = 30 + r.Next(floorY - 150);
                        g.FillRectangle(st, sx, sy - 4, 4, 12); g.FillRectangle(st, sx - 4, sy, 12, 4);
                    }
                // 木頭桌面
                using (SolidBrush d1 = new SolidBrush(Pix.C(0xB97F4E))) g.FillRectangle(d1, 0, floorY, W0, H0 - floorY);
                using (SolidBrush d2 = new SolidBrush(Pix.C(0xD9A06A))) g.FillRectangle(d2, 0, floorY, W0, 6);
                using (SolidBrush d3 = new SolidBrush(Pix.C(0x9A6338)))
                {
                    g.FillRectangle(d3, 0, floorY + 6, W0, 3);
                    for (int i = 0; i < 7; i++) g.FillRectangle(d3, 30 + r.Next(W0 - 120), floorY + 24 + r.Next(H0 - floorY - 40), 40 + r.Next(60), 3);
                }
                // 浮水印
                using (Font f = new Font("Microsoft JhengHei UI", 16f, FontStyle.Bold, GraphicsUnit.Pixel))
                {
                    string s = "WoWo Pals";
                    Size ts = PixText.MeasureText(s, f, new Size(4000, 400), TextFormatFlags.NoPadding);
                    int tx = W0 - ts.Width - 18, ty = H0 - ts.Height - 14;
                    PixText.DrawText(g, s, f, new Point(tx + 1, ty + 1), Pix.C(0x7A4A28), TextFormatFlags.NoPadding);
                    PixText.DrawText(g, s, f, new Point(tx, ty), Pix.C(0xFFF6E4), TextFormatFlags.NoPadding);
                    using (SolidBrush hb = new SolidBrush(Pix.C(0xF27A90)))
                    {
                        string[] h = { ".#.#.", "#####", ".###.", "..#.." };
                        for (int rr = 0; rr < h.Length; rr++) for (int c = 0; c < h[rr].Length; c++) if (h[rr][c] == '#') g.FillRectangle(hb, tx - 22 + c * 3, ty + 4 + rr * 3, 3, 3);
                    }
                }
            }
            return b;
        }

        // ================= 匯出／匯入（.deskpal：一個 JSON，裡面是設定＋原圖 PNG 的 base64） =================
        const long MaxPalFile = 30L << 20;

        public void CuExportDialog(string id)
        {
            CuMeta m = CuStore.Get(id);
            if (m == null) return;
            if (App.Offscreen) { App.Log("custom: export dialog skipped (offscreen)"); return; }
            using (SaveFileDialog dlg = new SaveFileDialog())
            {
                dlg.Title = "匯出「" + m.Name + "」";
                dlg.Filter = "WoWo Pals 公仔|*.deskpal";
                dlg.FileName = CuMeta.CleanName(m.Name) + ".deskpal";
                dlg.InitialDirectory = World.UserFolder(Environment.SpecialFolder.DesktopDirectory, "", "Desktop");
                if (dlg.ShowDialog() != DialogResult.OK) return;
                if (CuExport(id, dlg.FileName)) Lead().Say("匯出好了！把「" + Path.GetFileName(dlg.FileName) + "」傳給朋友，他在小屋按「匯入朋友的公仔」就能養 🧸", 5);
            }
        }

        public bool CuExport(string id, string path)
        {
            CuMeta m = CuStore.Get(id);
            if (m == null) return false;   // 只有自己做的公仔能匯出（內建的不行）
            try
            {
                byte[] src = File.ReadAllBytes(Path.Combine(CuStore.Dir(id), "source.png"));
                Dictionary<string, object> meta = new JavaScriptSerializer().DeserializeObject(m.ToJson()) as Dictionary<string, object>;
                if (meta == null) return false;
                meta.Remove("id"); meta.Remove("created");
                Dictionary<string, object> d = new Dictionary<string, object>();
                d["deskpal"] = 1; d["app"] = "WoWo Pals"; d["meta"] = meta; d["source"] = Convert.ToBase64String(src);
                JavaScriptSerializer js = new JavaScriptSerializer(); js.MaxJsonLength = int.MaxValue;
                File.WriteAllText(path, js.Serialize(d), new UTF8Encoding(false));
                App.Log("custom exported " + id + " -> " + path);
                return true;
            }
            catch (Exception ex) { App.Log("export: " + ex.Message); Lead().Say("匯出失敗了…（" + ex.Message + "）", 3); return false; }
        }

        public void CuImportDialog(bool first)
        {
            if (App.Offscreen) { App.Log("custom: import dialog skipped (offscreen)"); if (first) ShowSetup(true); return; }
            using (OpenFileDialog dlg = new OpenFileDialog())
            {
                dlg.Title = "匯入朋友的公仔";
                dlg.Filter = "WoWo Pals 公仔|*.deskpal|所有檔案|*.*";
                dlg.InitialDirectory = World.UserFolder(Environment.SpecialFolder.DesktopDirectory, "", "Desktop");
                if (dlg.ShowDialog() != DialogResult.OK) { if (first) ShowSetup(true); return; }
                CuImportFile(dlg.FileName, first);
            }
        }

        // 讀進來每一樣都檢查：檔案大小、JSON、圖片解得開、名字清乾淨；id 一律重新產生（不信任檔案裡的路徑、id）
        public void CuImportFile(string path, bool first)
        {
            string err = null, newId = null;
            try
            {
                FileInfo fi = new FileInfo(path);
                if (!fi.Exists) err = "找不到這個檔案";
                else if (fi.Length > MaxPalFile) err = "檔案太大了（超過 30MB），應該不是公仔檔";
                else
                {
                    JavaScriptSerializer js = new JavaScriptSerializer(); js.MaxJsonLength = (int)MaxPalFile * 2;
                    Dictionary<string, object> d = js.DeserializeObject(File.ReadAllText(path, Encoding.UTF8)) as Dictionary<string, object>;
                    object ver, mo, so;
                    if (d == null || !d.TryGetValue("deskpal", out ver) || Convert.ToInt32(ver) != 1) err = "這不是 WoWo Pals 的公仔檔";
                    else if (!d.TryGetValue("meta", out mo) || !(mo is Dictionary<string, object>) || !d.TryGetValue("source", out so) || !(so is string)) err = "公仔檔缺東西（可能壞掉了）";
                    else
                    {
                        CuMeta m = CuMeta.FromDict((Dictionary<string, object>)mo);
                        string b64 = (string)so;
                        if (b64.Length > MaxPalFile * 4 / 3 + 16) err = "公仔檔裡的圖太大了";
                        else
                        {
                            byte[] png = Convert.FromBase64String(b64);
                            string e2;
                            Bitmap src = CuImg.Decode(png, m.Sheet ? 1400 : CuImg.MaxSrc, out e2);
                            if (src == null) err = e2;
                            else
                            {
                                CuSprite s = CuSprite.Build(m, src, out e2);
                                if (s == null) { err = e2; src.Dispose(); }
                                else
                                {
                                    m.Id = CuStore.NewId(); m.Created = "";
                                    if (m.Name == "") m.Name = "朋友的公仔";
                                    CuStore.Save(m, src, s);
                                    src.Dispose();
                                    newId = m.Id;
                                    App.Log("custom imported " + newId + " name=" + m.Name);
                                }
                            }
                        }
                    }
                }
            }
            catch (Exception ex) { err = "這個檔案打不開（" + ex.Message + "）"; }
            if (newId == null)
            {
                App.Log("import failed: " + err);
                Lead().Say("匯入失敗：" + err, 4);
                if (first) ShowSetup(true);
                return;
            }
            CuCreated(newId, first, false);
        }
    }
}
