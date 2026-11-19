// Desk Pals：自己做公仔（上傳圖片）的影像處理——讀圖、去背、裁切、像素風／保留原圖、切頭身腳。
// 全部在本機算，不連網、不用任何外部套件；只用 System.Drawing。
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.Drawing;
    using System.Drawing.Drawing2D;
    using System.Drawing.Imaging;
    using System.IO;
    using System.Runtime.InteropServices;

    // 去背、像素化的結果（內部像素：像素風一格＝Sub 個像素，保留原圖一格＝8 個像素）
    class CuCut
    {
        public int W, H;
        public int[] Px;            // ARGB（不預乘）
        public byte[] A { get { byte[] a = new byte[Px.Length]; for (int i = 0; i < Px.Length; i++) a[i] = (byte)((Px[i] >> 24) & 255); return a; } }
    }

    static class CuImg
    {
        public const int MaxSrc = 640;              // 處理用的原圖最長邊（照片太大先縮）
        public const long MaxFileBytes = 40L << 20; // 40MB 以上的檔案不讀
        public const int HCells = 16, WCells = 22;  // 公仔最高 16 格、最寬 22 格（跟內建的差不多大）
        public const int SmoothR = 8;               // 保留原圖：一格 8 個像素

        // ---------- 像素陣列 ----------
        public static int[] Pixels(Bitmap b)
        {
            int w = b.Width, h = b.Height;
            int[] a = new int[w * h];
            BitmapData d = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try { for (int y = 0; y < h; y++) Marshal.Copy(new IntPtr(d.Scan0.ToInt64() + (long)y * d.Stride), a, y * w, w); }
            finally { b.UnlockBits(d); }
            return a;
        }

        public static Bitmap FromPixels(int[] px, int w, int h)
        {
            Bitmap b = new Bitmap(Math.Max(1, w), Math.Max(1, h), PixelFormat.Format32bppArgb);
            if (w <= 0 || h <= 0) return b;
            BitmapData d = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            try { for (int y = 0; y < h; y++) Marshal.Copy(px, y * w, new IntPtr(d.Scan0.ToInt64() + (long)y * d.Stride), w); }
            finally { b.UnlockBits(d); }
            return b;
        }

        static int Argb(int a, int r, int g, int b) { return (Clamp255(a) << 24) | (Clamp255(r) << 16) | (Clamp255(g) << 8) | Clamp255(b); }
        static int Clamp255(int v) { return v < 0 ? 0 : (v > 255 ? 255 : v); }
        static int Clamp255(double v) { return v < 0 ? 0 : (v > 255 ? 255 : (int)Math.Round(v)); }

        // ---------- 讀圖：PNG／JPG／GIF（第一格）／BMP；照 EXIF 轉正；太大先縮 ----------
        public static Bitmap LoadFile(string path, out string err)
        {
            err = null;
            try
            {
                FileInfo fi = new FileInfo(path);
                if (!fi.Exists) { err = "找不到這個檔案"; return null; }
                if (fi.Length > MaxFileBytes) { err = "這張圖太大了（超過 40MB），換一張小一點的"; return null; }
                return Decode(File.ReadAllBytes(path), MaxSrc, out err);
            }
            catch (Exception ex) { err = "打不開這張圖（" + ex.Message + "）"; return null; }
        }

        public static Bitmap Decode(byte[] bytes, int maxDim, out string err)
        {
            err = null;
            try
            {
                using (MemoryStream ms = new MemoryStream(bytes))
                using (Image img = Image.FromStream(ms, false, true))
                {
                    if ((long)img.Width * img.Height > 60000000L || img.Width < 1 || img.Height < 1) { err = "這張圖的尺寸太誇張了，換一張吧"; return null; }
                    using (Bitmap full = new Bitmap(img.Width, img.Height, PixelFormat.Format32bppArgb))
                    {
                        using (Graphics g = Graphics.FromImage(full)) { g.Clear(Color.Transparent); g.CompositingMode = CompositingMode.SourceCopy; g.DrawImage(img, 0, 0, img.Width, img.Height); }
                        RotateFlipType rf = ExifFix(img);
                        if (rf != RotateFlipType.RotateNoneFlipNone) full.RotateFlip(rf);
                        return Shrink(full, maxDim);
                    }
                }
            }
            catch (Exception ex) { err = "這個檔案不是看得懂的圖片（" + ex.Message + "）"; return null; }
        }

        // 手機照片常常是「躺著存、EXIF 說要轉」
        static RotateFlipType ExifFix(Image img)
        {
            try
            {
                foreach (int id in img.PropertyIdList)
                {
                    if (id != 0x0112) continue;
                    PropertyItem p = img.GetPropertyItem(id);
                    int o = p.Value != null && p.Value.Length > 0 ? p.Value[0] : 1;
                    switch (o)
                    {
                        case 2: return RotateFlipType.RotateNoneFlipX;
                        case 3: return RotateFlipType.Rotate180FlipNone;
                        case 4: return RotateFlipType.Rotate180FlipX;
                        case 5: return RotateFlipType.Rotate90FlipX;
                        case 6: return RotateFlipType.Rotate90FlipNone;
                        case 7: return RotateFlipType.Rotate270FlipX;
                        case 8: return RotateFlipType.Rotate270FlipNone;
                    }
                }
            }
            catch { }
            return RotateFlipType.RotateNoneFlipNone;
        }

        public static Bitmap Shrink(Bitmap src, int maxDim)
        {
            double s = Math.Min(1.0, maxDim / (double)Math.Max(src.Width, src.Height));
            int nw = Math.Max(1, (int)Math.Round(src.Width * s)), nh = Math.Max(1, (int)Math.Round(src.Height * s));
            Bitmap b = new Bitmap(nw, nh, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(b))
            {
                g.Clear(Color.Transparent);
                g.CompositingMode = CompositingMode.SourceCopy;
                g.InterpolationMode = s < 1 ? InterpolationMode.HighQualityBicubic : InterpolationMode.NearestNeighbor;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                using (ImageAttributes ia = new ImageAttributes())
                {
                    ia.SetWrapMode(WrapMode.TileFlipXY);   // 邊緣不要糊出一圈半透明
                    g.DrawImage(src, new Rectangle(0, 0, nw, nh), 0, 0, src.Width, src.Height, GraphicsUnit.Pixel, ia);
                }
            }
            return b;
        }

        // 這張圖本來就有透明背景嗎？
        public static bool HasAlpha(int[] px, int w, int h)
        {
            int clear = 0, edgeClear = 0, edge = 0;
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    int a = (px[y * w + x] >> 24) & 255;
                    if (a < 128) clear++;
                    if (x == 0 || y == 0 || x == w - 1 || y == h - 1) { edge++; if (a < 128) edgeClear++; }
                }
            return clear > px.Length / 100 && edgeClear * 5 > edge;
        }

        // ---------- 顏色距離（紅均值加權，接近人眼） ----------
        static double Dist(int r1, int g1, int b1, int r2, int g2, int b2)
        {
            double rm = (r1 + r2) / 2.0, dr = r1 - r2, dg = g1 - g2, db = b1 - b2;
            return Math.Sqrt((2 + rm / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256) * db * db) / 3.0;
        }
        public static double TolToT(int tol) { return 6 + Math.Max(0, Math.Min(100, tol)) * 0.9; }   // 去背強度 0～100 → 顏色距離門檻

        // ---------- 自動去背：從四邊取背景色（分群），從邊往內長；毛邊半透明、去掉背景色暈；只留最大的那塊 ----------
        public static int[] RemoveBg(int[] px, int w, int h, int tol)
        {
            int n = w * h;
            int[] R = new int[n], G = new int[n], B = new int[n];
            for (int i = 0; i < n; i++) { R[i] = (px[i] >> 16) & 255; G[i] = (px[i] >> 8) & 255; B[i] = px[i] & 255; }
            double T = TolToT(tol);
            // 1) 邊框兩圈像素分群（最多 5 群），太少的群丟掉
            // 背景色只從上、左、右三邊取（寵物照常常被下緣切到，下緣多半是主角）；下緣只拿來當起點
            List<int> border = new List<int>(), side = new List<int>();
            int bw = Math.Max(1, Math.Min(3, Math.Min(w, h) / 40 + 1));
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    if (x < bw || y < bw || x >= w - bw || y >= h - bw)
                    {
                        border.Add(y * w + x);
                        if (y < h - bw) side.Add(y * w + x);
                    }
            List<double[]> cen = KMeans(side, R, G, B, 5);
            // 主角也碰到邊的時候，那一群其實是主角：中間那塊很多這個顏色的群（除了最大的那群）不算背景
            if (cen.Count > 1)
            {
                int cx0 = w * 35 / 100, cx1 = w * 65 / 100, cy0 = h * 35 / 100, cy1 = h * 65 / 100, tot = 0;
                int[] hit = new int[cen.Count];
                for (int y = cy0; y < cy1; y += 2)
                    for (int x = cx0; x < cx1; x += 2)
                    {
                        int i = y * w + x; tot++;
                        for (int k = 0; k < cen.Count; k++) if (Dist(R[i], G[i], B[i], (int)cen[k][0], (int)cen[k][1], (int)cen[k][2]) < T) hit[k]++;
                    }
                List<double[]> keep = new List<double[]>();
                for (int k = 0; k < cen.Count; k++) if (k == 0 || tot == 0 || hit[k] * 100 < tot * 10) keep.Add(cen[k]);
                cen = keep;
            }
            // 2) 每個像素到最近背景色的距離
            double[] dmin = new double[n];
            for (int i = 0; i < n; i++)
            {
                double best = 1e9;
                foreach (double[] c in cen) { double d = Dist(R[i], G[i], B[i], (int)c[0], (int)c[1], (int)c[2]); if (d < best) best = d; }
                dmin[i] = best;
            }
            // 3) 從邊框往內長：像背景色的、或跟旁邊背景很接近（漸層、陰影）的都算背景
            bool[] bg = new bool[n];
            int[] q = new int[n]; int qh = 0, qt = 0;
            foreach (int i in border) if (dmin[i] < T && !bg[i]) { bg[i] = true; q[qt++] = i; }
            while (qh < qt)
            {
                int p = q[qh++], x = p % w, y = p / w;
                for (int k = 0; k < 4; k++)
                {
                    int nx = x + (k == 0 ? 1 : (k == 1 ? -1 : 0)), ny = y + (k == 2 ? 1 : (k == 3 ? -1 : 0));
                    if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                    int o = ny * w + nx;
                    if (bg[o]) continue;
                    bool ok = dmin[o] < T || (dmin[o] < T * 1.6 && Dist(R[o], G[o], B[o], R[p], G[p], B[p]) < T * 0.22);
                    if (ok) { bg[o] = true; q[qt++] = o; }
                }
            }
            // 4) alpha：背景 0；靠近背景的那一圈照「跟旁邊背景色差多少」給半透明（毛邊），並把背景色暈掉
            int[] outPx = new int[n];
            for (int i = 0; i < n; i++) outPx[i] = bg[i] ? 0 : (px[i] | unchecked((int)0xFF000000));
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    int i = y * w + x;
                    if (bg[i]) continue;
                    double sr = 0, sg = 0, sb = 0; int cnt = 0;
                    for (int dy = -2; dy <= 2; dy++)
                        for (int dx = -2; dx <= 2; dx++)
                        {
                            int xx = x + dx, yy = y + dy;
                            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
                            int o = yy * w + xx;
                            if (!bg[o]) continue;
                            sr += R[o]; sg += G[o]; sb += B[o]; cnt++;
                        }
                    if (cnt == 0) continue;
                    double br = sr / cnt, bgc = sg / cnt, bb = sb / cnt;
                    double dl = Dist(R[i], G[i], B[i], (int)br, (int)bgc, (int)bb);
                    double a = Math.Max(0, Math.Min(1, (dl - T * 0.45) / (T * 1.1)));
                    if (a <= 0.02) { outPx[i] = 0; continue; }
                    // 去掉背景色暈：c = (c - (1-a)·bg) / a
                    double cr = (R[i] - (1 - a) * br) / a, cg = (G[i] - (1 - a) * bgc) / a, cb = (B[i] - (1 - a) * bb) / a;
                    outPx[i] = Argb((int)Math.Round(a * 255), (int)Math.Round(cr), (int)Math.Round(cg), (int)Math.Round(cb));
                }
            KeepMain(outPx, w, h);
            return outPx;
        }

        // 邊框色分群（最遠點初始化＋幾輪 k-means）
        static List<double[]> KMeans(List<int> idx, int[] R, int[] G, int[] B, int kmax)
        {
            List<double[]> c = new List<double[]>();
            if (idx.Count == 0) { c.Add(new double[] { 255, 255, 255 }); return c; }
            double mr = 0, mg = 0, mb = 0;
            foreach (int i in idx) { mr += R[i]; mg += G[i]; mb += B[i]; }
            c.Add(new double[] { mr / idx.Count, mg / idx.Count, mb / idx.Count });
            int step = Math.Max(1, idx.Count / 4000);
            while (c.Count < kmax)
            {
                double far = 0; int fi = -1;
                for (int s = 0; s < idx.Count; s += step)
                {
                    int i = idx[s]; double best = 1e9;
                    foreach (double[] cc in c) best = Math.Min(best, Dist(R[i], G[i], B[i], (int)cc[0], (int)cc[1], (int)cc[2]));
                    if (best > far) { far = best; fi = i; }
                }
                if (fi < 0 || far < 14) break;
                c.Add(new double[] { R[fi], G[fi], B[fi] });
            }
            int[] cnt = new int[c.Count];
            for (int it = 0; it < 6; it++)
            {
                double[][] sum = new double[c.Count][];
                for (int k = 0; k < c.Count; k++) sum[k] = new double[3];
                cnt = new int[c.Count];
                foreach (int i in idx)
                {
                    int bk = 0; double best = 1e9;
                    for (int k = 0; k < c.Count; k++) { double d = Dist(R[i], G[i], B[i], (int)c[k][0], (int)c[k][1], (int)c[k][2]); if (d < best) { best = d; bk = k; } }
                    sum[bk][0] += R[i]; sum[bk][1] += G[i]; sum[bk][2] += B[i]; cnt[bk]++;
                }
                for (int k = 0; k < c.Count; k++) if (cnt[k] > 0) c[k] = new double[] { sum[k][0] / cnt[k], sum[k][1] / cnt[k], sum[k][2] / cnt[k] };
            }
            // 太少的群是剛好碰到邊的主角，不算背景
            // 由多到少排好（第一群＝最大的背景色）
            List<int> order = new List<int>();
            for (int k = 0; k < c.Count; k++) if (cnt[k] * 100 >= idx.Count * 4) order.Add(k);
            order.Sort(delegate(int a, int b) { return cnt[b].CompareTo(cnt[a]); });
            List<double[]> keep = new List<double[]>();
            foreach (int k in order) keep.Add(c[k]);
            if (keep.Count == 0) keep.Add(c[0]);
            return keep;
        }

        // 只留主角那塊（和夠大的旁支，例如分開的耳朵、尾巴）。
        // 主角＝包住畫面中央的那塊（夠大的話）；中央沒有才用最大的那塊。背景很亂的照片，最大的那塊常常是背景（人像測試 v011\humantest）
        public static void KeepMain(int[] px, int w, int h)
        {
            int n = w * h;
            int[] lab = new int[n];
            List<int> sizes = new List<int>(); sizes.Add(0);
            int[] q = new int[n];
            for (int s = 0; s < n; s++)
            {
                if (lab[s] != 0 || ((px[s] >> 24) & 255) < 96) continue;
                int id = sizes.Count, qh = 0, qt = 0, size = 0;
                lab[s] = id; q[qt++] = s;
                while (qh < qt)
                {
                    int p = q[qh++], x = p % w, y = p / w; size++;
                    for (int dy = -1; dy <= 1; dy++)
                        for (int dx = -1; dx <= 1; dx++)
                        {
                            int xx = x + dx, yy = y + dy;
                            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
                            int o = yy * w + xx;
                            if (lab[o] != 0 || ((px[o] >> 24) & 255) < 96) continue;
                            lab[o] = id; q[qt++] = o;
                        }
                }
                sizes.Add(size);
            }
            int big = 0;
            for (int i = 1; i < sizes.Count; i++) big = Math.Max(big, sizes[i]);
            if (big == 0) return;
            int main = CentreLabel(lab, w, h);
            if (main > 0 && sizes[main] * 20 >= big) big = sizes[main];   // 中央那塊至少有最大那塊的 5%：當主角
            else main = 0;
            bool[] keep = new bool[sizes.Count];
            for (int i = 1; i < sizes.Count; i++) keep[i] = sizes[i] * 8 >= big && (main == 0 || i == main || sizes[i] <= sizes[main]);   // 比主角還大的（背景）不留
            for (int i = 0; i < n; i++)
            {
                int a = (px[i] >> 24) & 255;
                if (a == 0) continue;
                int l = lab[i];
                if (l == 0)
                {
                    // 半透明的毛邊：旁邊有留下來的才留
                    bool near = false;
                    int x = i % w, y = i / w;
                    for (int dy = -1; dy <= 1 && !near; dy++)
                        for (int dx = -1; dx <= 1 && !near; dx++)
                        {
                            int xx = x + dx, yy = y + dy;
                            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
                            int ll = lab[yy * w + xx];
                            if (ll != 0 && keep[ll]) near = true;
                        }
                    if (!near) px[i] = 0;
                }
                else if (!keep[l]) px[i] = 0;
            }
        }

        // 畫面中央（往外一圈一圈找，最多找到短邊的 1/6）碰到的第一塊；0＝沒有
        static int CentreLabel(int[] lab, int w, int h)
        {
            int cx = w / 2, cy = h / 2, max = Math.Max(1, Math.Min(w, h) / 6);
            for (int r = 0; r <= max; r++)
                for (int dy = -r; dy <= r; dy++)
                    for (int dx = -r; dx <= r; dx++)
                    {
                        if (Math.Max(Math.Abs(dx), Math.Abs(dy)) != r) continue;
                        int x = cx + dx, y = cy + dy;
                        if (x < 0 || y < 0 || x >= w || y >= h) continue;
                        int l = lab[y * w + x];
                        if (l != 0) return l;
                    }
            return 0;
        }

        // 筆刷：擦掉／補回（座標都是 0～1；補回＝原圖的顏色）
        public static void ApplyStrokes(int[] px, int[] orig, int w, int h, List<double[]> strokes)
        {
            if (strokes == null) return;
            double m = Math.Max(w, h);
            foreach (double[] s in strokes)
            {
                if (s == null || s.Length < 4) continue;
                double cx = s[0] * w, cy = s[1] * h, r = Math.Max(0.6, s[2] * m);
                bool erase = s[3] > 0.5;
                int x0 = Math.Max(0, (int)(cx - r - 1)), x1 = Math.Min(w - 1, (int)(cx + r + 1)), y0 = Math.Max(0, (int)(cy - r - 1)), y1 = Math.Min(h - 1, (int)(cy + r + 1));
                for (int y = y0; y <= y1; y++)
                    for (int x = x0; x <= x1; x++)
                    {
                        double d = Math.Sqrt((x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy));
                        if (d > r) continue;
                        int i = y * w + x;
                        if (erase) px[i] = 0;
                        else px[i] = orig[i] | unchecked((int)0xFF000000);
                    }
            }
        }

        // 透明的地方裁掉（四邊留 pad）
        public static Rectangle Bounds(int[] px, int w, int h, int thr)
        {
            int l = w, t = h, r = -1, b = -1;
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                    if (((px[y * w + x] >> 24) & 255) >= thr) { if (x < l) l = x; if (x > r) r = x; if (y < t) t = y; if (y > b) b = y; }
            if (r < 0) return Rectangle.Empty;
            return Rectangle.FromLTRB(l, t, r + 1, b + 1);
        }

        public static CuCut Crop(int[] px, int w, int h, Rectangle r)
        {
            CuCut c = new CuCut(); c.W = r.Width; c.H = r.Height; c.Px = new int[r.Width * r.Height];
            for (int y = 0; y < r.Height; y++) Array.Copy(px, (r.Y + y) * w + r.X, c.Px, y * r.Width, r.Width);
            return c;
        }

        // 去背＋筆刷＋裁切：從原圖做出「主角」
        public static CuCut Cutout(Bitmap src, bool useAlpha, int tol, List<double[]> strokes, out bool hadAlpha)
        {
            int w = src.Width, h = src.Height;
            int[] orig = Pixels(src);
            hadAlpha = HasAlpha(orig, w, h);
            int[] px;
            if (hadAlpha && useAlpha)
            {
                px = (int[])orig.Clone();
                for (int i = 0; i < px.Length; i++) if (((px[i] >> 24) & 255) < 10) px[i] = 0;
            }
            else
            {
                int[] solid = (int[])orig.Clone();
                for (int i = 0; i < solid.Length; i++) if (((solid[i] >> 24) & 255) < 128) solid[i] = unchecked((int)0xFFFFFFFF); else solid[i] |= unchecked((int)0xFF000000);
                px = RemoveBg(solid, w, h, tol);
            }
            ApplyStrokes(px, orig, w, h, strokes);
            Rectangle bb = Bounds(px, w, h, 40);
            if (bb.Width < 2 || bb.Height < 2) return null;
            return Crop(px, w, h, bb);
        }

        // ---------- 大小：最高 16 格、最寬 20 格 ----------
        public static void Fit(int w, int h, double maxW, double maxH, out int cw, out int ch)
        {
            double s = Math.Min(maxH / h, maxW / w);
            cw = Math.Max(1, (int)Math.Round(w * s)); ch = Math.Max(1, (int)Math.Round(h * s));
        }

        // ---------- 保留原圖：平滑縮放（一格 8 像素） ----------
        public static CuCut ToSmooth(CuCut c, double hCells, double wCells)
        {
            int cw, ch;
            Fit(c.W, c.H, wCells * SmoothR, hCells * SmoothR, out cw, out ch);
            return ToSmoothSized(c, cw, ch);
        }

        public static CuCut ToSmoothSized(CuCut c, int cw, int ch)
        {
            CuCut o = new CuCut(); o.W = cw; o.H = ch;
            o.Px = Resample(c, cw, ch);
            for (int i = 0; i < o.Px.Length; i++) if (((o.Px[i] >> 24) & 255) < 14) o.Px[i] = 0;
            return o;
        }

        // 預乘平均的超取樣縮放（不會有黑邊）
        static int[] Resample(CuCut c, int tw, int th)
        {
            int[] o = new int[tw * th];
            double sx = c.W / (double)tw, sy = c.H / (double)th;
            int nx = Math.Max(1, Math.Min(8, (int)Math.Ceiling(sx * 2))), ny = Math.Max(1, Math.Min(8, (int)Math.Ceiling(sy * 2)));
            for (int y = 0; y < th; y++)
                for (int x = 0; x < tw; x++)
                {
                    double a = 0, r = 0, g = 0, b = 0; int cnt = 0;
                    for (int j = 0; j < ny; j++)
                        for (int i = 0; i < nx; i++)
                        {
                            int px = Math.Min(c.W - 1, (int)((x + (i + 0.5) / nx) * sx)), py = Math.Min(c.H - 1, (int)((y + (j + 0.5) / ny) * sy));
                            int v = c.Px[py * c.W + px];
                            double av = ((v >> 24) & 255) / 255.0;
                            a += av; r += av * ((v >> 16) & 255); g += av * ((v >> 8) & 255); b += av * (v & 255); cnt++;
                        }
                    if (a <= 0.0001) { o[y * tw + x] = 0; continue; }
                    o[y * tw + x] = Argb((int)Math.Round(a / cnt * 255), (int)Math.Round(r / a), (int)Math.Round(g / a), (int)Math.Round(b / a));
                }
            return o;
        }

        // ---------- 像素風：縮到格子、減色、深色外框（跟內建公仔同一種畫法） ----------
        public static CuCut ToPixel(CuCut c, int sub, double hCells, double wCells, out Color outline)
        {
            int cw, ch;
            double maxH = hCells * sub - 2, maxW = wCells * sub - 2;
            // 本來就很小的圖（多半是像素圖）：用整數倍放大，才不會一格大一格小
            if (c.H <= maxH && c.W <= maxW)
            {
                int k = Math.Max(1, (int)Math.Floor(Math.Min(maxH / c.H, maxW / c.W)));
                cw = c.W * k; ch = c.H * k;
            }
            else Fit(c.W, c.H, maxW, maxH, out cw, out ch);
            return ToPixelSized(c, cw, ch, sub >= 2 ? 18 : 12, true, out outline);
        }

        // 縮到 cw×ch（外框另外加一圈）；quant＝要不要減色（動作表是使用者自己畫的，不減）
        public static CuCut ToPixelSized(CuCut c, int cw, int ch, int K, bool quant, out Color outline)
        {
            int[] small = Resample(c, cw, ch);
            int gw = cw + 2, gh = ch + 2;
            int[] g = new int[gw * gh];
            List<int> cols = new List<int>();
            for (int y = 0; y < ch; y++)
                for (int x = 0; x < cw; x++)
                {
                    int v = small[y * cw + x];
                    if (((v >> 24) & 255) < 110) continue;
                    if (quant) v = Punch(v); else v |= unchecked((int)0xFF000000);
                    g[(y + 1) * gw + x + 1] = v;
                    cols.Add(v);
                }
            // 減色（中位切割）
            List<int> pal = MedianCut(cols, quant ? K : 64);
            int[] use = new int[pal.Count];
            for (int i = 0; i < g.Length; i++)
            {
                if (g[i] == 0) continue;
                int best = Nearest(pal, g[i]);
                if (quant) g[i] = pal[best] | unchecked((int)0xFF000000);
                use[best]++;
            }
            // 孤零零的一個像素拿掉（雜點）
            int[] g2 = (int[])g.Clone();
            for (int y = 1; y < gh - 1; y++)
                for (int x = 1; x < gw - 1; x++)
                {
                    int i = y * gw + x;
                    if (g[i] == 0) continue;
                    int nb = (g[i - 1] != 0 ? 1 : 0) + (g[i + 1] != 0 ? 1 : 0) + (g[i - gw] != 0 ? 1 : 0) + (g[i + gw] != 0 ? 1 : 0);
                    if (nb == 0) g2[i] = 0;
                }
            g = g2;
            // 外框色：最多的那個顏色壓暗、帶一點藏青（內建公仔的 k 都是很深的有色黑）
            int dom = 0; for (int i = 1; i < use.Length; i++) if (use[i] > use[dom]) dom = i;
            Color dc = pal.Count > 0 ? Color.FromArgb(pal[dom]) : Color.Gray;
            outline = Color.FromArgb(255, Clamp255(dc.R * 0.22 + 0x2A * 0.45), Clamp255(dc.G * 0.22 + 0x2F * 0.45), Clamp255(dc.B * 0.22 + 0x45 * 0.5));
            // 原圖邊緣本來就有深色外框（多半是像素圖、貼圖）：不要再多加一圈
            long el = 0, en = 0;
            for (int y = 1; y < gh - 1; y++)
                for (int x = 1; x < gw - 1; x++)
                {
                    int i = y * gw + x;
                    if (g[i] == 0 || (g[i - 1] != 0 && g[i + 1] != 0 && g[i - gw] != 0 && g[i + gw] != 0)) continue;
                    int v = g[i]; el += (((v >> 16) & 255) * 299 + ((v >> 8) & 255) * 587 + (v & 255) * 114) / 1000; en++;
                }
            if (en > 0 && el / en < 75) { CuCut r0 = new CuCut(); r0.W = gw; r0.H = gh; r0.Px = g; return r0; }
            int ok = outline.ToArgb();
            int[] o2 = (int[])g.Clone();
            for (int y = 0; y < gh; y++)
                for (int x = 0; x < gw; x++)
                {
                    int i = y * gw + x;
                    if (g[i] != 0) continue;
                    bool edge = (x > 0 && g[i - 1] != 0) || (x < gw - 1 && g[i + 1] != 0) || (y > 0 && g[i - gw] != 0) || (y < gh - 1 && g[i + gw] != 0);
                    if (edge) o2[i] = ok;
                }
            CuCut r = new CuCut(); r.W = gw; r.H = gh; r.Px = o2;
            return r;
        }

        // 像素風顏色稍微飽和一點（照片縮小後會灰灰的）
        static int Punch(int v)
        {
            int r = (v >> 16) & 255, g = (v >> 8) & 255, b = v & 255;
            double l = 0.299 * r + 0.587 * g + 0.114 * b, s = 1.18;
            return Argb(255, (int)(l + (r - l) * s), (int)(l + (g - l) * s), (int)(l + (b - l) * s));
        }

        static int Nearest(List<int> pal, int v)
        {
            int r = (v >> 16) & 255, g = (v >> 8) & 255, b = v & 255, best = 0; double bd = 1e9;
            for (int i = 0; i < pal.Count; i++)
            {
                int p = pal[i];
                double d = Dist(r, g, b, (p >> 16) & 255, (p >> 8) & 255, p & 255);
                if (d < bd) { bd = d; best = i; }
            }
            return best;
        }

        // 中位切割減色（K 色）
        public static List<int> MedianCut(List<int> cols, int K)
        {
            List<int> pal = new List<int>();
            if (cols.Count == 0) { pal.Add(unchecked((int)0xFF808080)); return pal; }
            List<List<int>> boxes = new List<List<int>>();
            boxes.Add(new List<int>(cols));
            while (boxes.Count < K)
            {
                int bi = -1, ch = 0; double bestScore = 0;
                for (int i = 0; i < boxes.Count; i++)
                {
                    List<int> bx = boxes[i];
                    if (bx.Count < 2) continue;
                    int[] mn = { 255, 255, 255 }, mx = { 0, 0, 0 };
                    foreach (int v in bx) for (int c = 0; c < 3; c++) { int cv = (v >> (16 - 8 * c)) & 255; if (cv < mn[c]) mn[c] = cv; if (cv > mx[c]) mx[c] = cv; }
                    double[] wgt = { 1.0, 1.25, 0.9 };
                    for (int c = 0; c < 3; c++)
                    {
                        double score = (mx[c] - mn[c]) * wgt[c] * Math.Sqrt(bx.Count);
                        if (score > bestScore) { bestScore = score; bi = i; ch = c; }
                    }
                }
                if (bi < 0 || bestScore < 1) break;
                List<int> box = boxes[bi];
                int sh = 16 - 8 * ch;
                box.Sort(delegate(int a, int b) { return ((a >> sh) & 255).CompareTo((b >> sh) & 255); });
                int mid = box.Count / 2;
                boxes[bi] = box.GetRange(0, mid);
                boxes.Add(box.GetRange(mid, box.Count - mid));
            }
            foreach (List<int> bx in boxes)
            {
                if (bx.Count == 0) continue;
                long r = 0, g = 0, b = 0;
                foreach (int v in bx) { r += (v >> 16) & 255; g += (v >> 8) & 255; b += v & 255; }
                pal.Add(Argb(255, (int)(r / bx.Count), (int)(g / bx.Count), (int)(b / bx.Count)));
            }
            return pal;
        }

        // ---------- 切頭身腳：猜兩條線的位置（0～1） ----------
        // 頭／身體：中段最窄的那列（脖子）；身體／腳：從下面往上，中間開始有空隙（兩隻腳）的那列
        public static void GuessLines(CuCut c, out double neck, out double hip, out bool confident)
        {
            int w = c.W, h = c.H;
            int[] width = new int[h], left = new int[h], right = new int[h];
            for (int y = 0; y < h; y++)
            {
                int l = -1, r = -1;
                for (int x = 0; x < w; x++) if (((c.Px[y * w + x] >> 24) & 255) >= 110) { if (l < 0) l = x; r = x; }
                left[y] = l; right[y] = r; width[y] = l < 0 ? 0 : r - l + 1;
            }
            // 脖子
            neck = 0.42; bool neckOk = false;
            bool tall = h > 2 * w;   // 全身照這種瘦長的：頭在很上面（人像測試：22–60% 會找到腰）
            int y0 = (int)(h * (tall ? 0.08 : 0.22)), y1 = (int)(h * (tall ? 0.30 : 0.6));
            if (tall)
            {
                // 頭頂也很窄：從頭最寬的那列以下才開始找脖子
                int top = 0;
                while (top < h - 1 && width[top] == 0) top++;
                int hy = top, hw = -1;
                for (int y = top; y <= top + (int)(h * 0.09) && y < h; y++) if (width[y] > hw) { hw = width[y]; hy = y; }   // 頭大約佔全身 12%：頂端往下 9% 內最寬的＝臉
                y0 = Math.Max(y0, hy + 1);
            }
            int best = -1; double bv = 1e9;
            for (int y = y0; y <= y1 && y < h; y++)
            {
                double sm = 0; int cnt = 0;
                for (int d = -1; d <= 1; d++) if (y + d >= 0 && y + d < h) { sm += width[y + d]; cnt++; }
                sm /= cnt;
                if (sm < bv) { bv = sm; best = y; }
            }
            if (best > 0)
            {
                int above = 0, below = 0;
                for (int y = 0; y < best; y++) above = Math.Max(above, width[y]);
                for (int y = best; y < h; y++) below = Math.Max(below, width[y]);
                if (bv < above * 0.86 && bv < below * 0.9) { neck = best / (double)h; neckOk = true; }
            }
            // 腳：中間有空隙
            hip = 0.78; bool hipOk = false;
            int run = 0;
            for (int y = h - 1; y >= (int)(h * 0.55); y--)
            {
                bool gap = false;
                if (width[y] > 2)
                {
                    int l = left[y], r = right[y], m0 = l + (r - l) / 5, m1 = r - (r - l) / 5, firstOn = -1;
                    bool seenGap = false;
                    for (int x = l; x <= r; x++)
                    {
                        bool on = ((c.Px[y * w + x] >> 24) & 255) >= 110;
                        if (on && firstOn < 0) firstOn = x;
                        if (!on && firstOn >= 0 && x >= m0 && x <= m1) seenGap = true;
                        if (on && seenGap) { gap = true; break; }
                    }
                }
                if (gap) run++;
                else if (run > 0) break;
            }
            if (run >= Math.Max(2, h * 0.07))
            {
                double hp = 1 - (run + 0.5) / h;
                if (hp > neck + 0.12 && hp < 0.95) { hip = hp; hipOk = true; }
            }
            if (!hipOk)
            {
                int widest = 0, bottom = 0;
                for (int y = 0; y < h; y++) widest = Math.Max(widest, width[y]);
                for (int y = h - 1; y >= 0 && bottom == 0; y--) bottom = width[y];
                if (widest > 0 && bottom >= widest * 0.85) hip = 0.97;   // 半身照：整塊都是身體，腳只留最下面一點點
            }
            if (hip < neck + 0.15) hip = Math.Min(0.92, neck + 0.3);
            confident = hipOk && neckOk || (hipOk && run >= h * 0.12);
        }

        // 兩隻腳的分界（腳那一段最空的那一欄）
        public static int LegSplit(CuCut c, int hipRow)
        {
            int w = c.W, h = c.H, l = w, r = -1;
            for (int y = hipRow; y < h; y++) for (int x = 0; x < w; x++) if (((c.Px[y * w + x] >> 24) & 255) >= 110) { if (x < l) l = x; if (x > r) r = x; }
            if (r < 0) return w / 2;
            int m0 = l + (r - l) / 4, m1 = r - (r - l) / 4, best = (l + r + 1) / 2, bv = int.MaxValue;
            for (int x = m0; x <= m1; x++)
            {
                int cnt = 0;
                for (int y = hipRow; y < h; y++) if (((c.Px[y * w + x] >> 24) & 255) >= 110) cnt++;
                int score = cnt * 4 + Math.Abs(x - (l + r) / 2);
                if (score < bv) { bv = score; best = x; }
            }
            return best;
        }

        public static Bitmap ToBitmap(CuCut c) { return FromPixels(c.Px, c.W, c.H); }
        public static CuCut FromBitmap(Bitmap b) { CuCut c = new CuCut(); c.W = b.Width; c.H = b.Height; c.Px = Pixels(b); return c; }
        public static CuCut Mirror(CuCut c)
        {
            CuCut o = new CuCut(); o.W = c.W; o.H = c.H; o.Px = new int[c.Px.Length];
            for (int y = 0; y < c.H; y++) for (int x = 0; x < c.W; x++) o.Px[y * c.W + x] = c.Px[y * c.W + c.W - 1 - x];
            return o;
        }
        // 主要顏色（不透明像素的平均，忽略外框）
        public static Color MainColor(CuCut c)
        {
            long r = 0, g = 0, b = 0, n = 0;
            foreach (int v in c.Px)
            {
                if (((v >> 24) & 255) < 200) continue;
                int rr = (v >> 16) & 255, gg = (v >> 8) & 255, bb = v & 255;
                if (rr + gg + bb < 120) continue;
                r += rr; g += gg; b += bb; n++;
            }
            if (n == 0) return Color.FromArgb(0x8A, 0x9A, 0xB8);
            return Color.FromArgb((int)(r / n), (int)(g / n), (int)(b / n));
        }
    }
}
