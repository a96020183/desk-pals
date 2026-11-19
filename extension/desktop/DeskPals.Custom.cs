// Desk Pals：自己做的公仔（上傳一張圖／動作表）。資料、處理好的圖、畫法、動作、我的櫃。
// desk-pals.ps1 會把 DeskPals.cs 和 DeskPals.*.cs 接在一起編譯；這個檔的 using 放在 namespace 裡面。
// 圖片處理在 DeskPals.CustomImage.cs、做公仔的視窗在 DeskPals.CustomMake.cs、台詞在 DeskPals.CustomLines.cs、分享短片／匯出匯入在 DeskPals.Share.cs。
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.Drawing;
    using System.Drawing.Drawing2D;
    using System.Drawing.Imaging;
    using System.IO;
    using System.Text;
    using System.Web.Script.Serialization;
    using System.Windows.Forms;

    // ================= 一隻自己做的公仔的設定（custom\<id>\meta.json）=================
    class CuMeta
    {
        public string Id = "", Name = "", Persona = "lively", Mode = "pixel", Created = "";
        public int Sub = 2;                  // 像素風：1＝跟內建一樣大的像素、2＝細緻（像素小一半）
        public bool Flip, Rig, Sheet, UseAlpha = true;
        public double Neck = -1, Hip = -1;   // 兩條線（0～1，處理後的圖從上往下）；-1＝自動猜
        public int Tol = 22;                 // 去背強度 0～100
        public List<double[]> Strokes = new List<double[]>();   // 筆刷：x, y, 半徑（0～1）, 1＝擦掉 0＝補回

        public bool Pixel { get { return Mode != "smooth"; } }

        public CuMeta Clone()
        {
            CuMeta m = (CuMeta)MemberwiseClone();
            m.Strokes = new List<double[]>();
            foreach (double[] s in Strokes) m.Strokes.Add((double[])s.Clone());
            return m;
        }

        public string ToJson()
        {
            Dictionary<string, object> d = new Dictionary<string, object>();
            d["v"] = 1; d["id"] = Id; d["name"] = Name; d["persona"] = Persona; d["mode"] = Mode; d["sub"] = Sub;
            d["flip"] = Flip; d["rig"] = Rig; d["sheet"] = Sheet; d["useAlpha"] = UseAlpha;
            d["neck"] = Neck; d["hip"] = Hip; d["tol"] = Tol; d["created"] = Created;
            List<object> st = new List<object>();
            foreach (double[] s in Strokes) st.Add(new object[] { Math.Round(s[0], 4), Math.Round(s[1], 4), Math.Round(s[2], 4), s[3] > 0.5 ? 1 : 0 });
            d["strokes"] = st;
            return new JavaScriptSerializer().Serialize(d);
        }

        static string S(Dictionary<string, object> d, string k, string def) { object o; return d.TryGetValue(k, out o) && o is string ? (string)o : def; }
        static double N(Dictionary<string, object> d, string k, double def)
        {
            object o; if (!d.TryGetValue(k, out o) || o == null) return def;
            try { double v = Convert.ToDouble(o, System.Globalization.CultureInfo.InvariantCulture); return double.IsNaN(v) || double.IsInfinity(v) ? def : v; } catch { return def; }
        }
        static bool B(Dictionary<string, object> d, string k, bool def) { object o; return d.TryGetValue(k, out o) && o is bool ? (bool)o : def; }

        // 讀 JSON（不認得的欄位不管；每個值都檢查過）
        public static CuMeta FromJson(string json)
        {
            try
            {
                JavaScriptSerializer js = new JavaScriptSerializer();
                js.MaxJsonLength = 1 << 20;
                Dictionary<string, object> d = js.DeserializeObject(json) as Dictionary<string, object>;
                if (d == null) return null;
                return FromDict(d);
            }
            catch { return null; }
        }

        public static CuMeta FromDict(Dictionary<string, object> d)
        {
            CuMeta m = new CuMeta();
            m.Id = S(d, "id", "");
            m.Name = CleanName(S(d, "name", ""));
            m.Persona = Array.IndexOf(Pal.Personas, S(d, "persona", "lively")) >= 0 ? S(d, "persona", "lively") : "lively";
            m.Mode = S(d, "mode", "pixel") == "smooth" ? "smooth" : "pixel";
            m.Sub = N(d, "sub", 2) >= 1.5 ? 2 : 1;
            m.Flip = B(d, "flip", false); m.Rig = B(d, "rig", false); m.Sheet = B(d, "sheet", false); m.UseAlpha = B(d, "useAlpha", true);
            m.Neck = N(d, "neck", -1); m.Hip = N(d, "hip", -1);
            if (m.Neck > 0.9 || m.Neck < 0.05) m.Neck = -1;
            if (m.Hip > 0.98 || m.Hip < 0.1) m.Hip = -1;
            m.Tol = (int)Math.Max(0, Math.Min(100, N(d, "tol", 22)));
            m.Created = S(d, "created", "");
            if (m.Created.Length > 40) m.Created = "";
            object so;
            if (d.TryGetValue("strokes", out so) && so is object[])
                foreach (object o in (object[])so)
                {
                    object[] a = o as object[];
                    if (a == null || a.Length < 4 || m.Strokes.Count >= 4000) continue;
                    try
                    {
                        double[] s = new double[4];
                        for (int i = 0; i < 4; i++) s[i] = Convert.ToDouble(a[i], System.Globalization.CultureInfo.InvariantCulture);
                        if (s[0] < -0.2 || s[0] > 1.2 || s[1] < -0.2 || s[1] > 1.2 || s[2] <= 0 || s[2] > 0.5) continue;
                        m.Strokes.Add(s);
                    }
                    catch { }
                }
            return m;
        }

        // 名字：去掉換行、控制字元、大括號（台詞代換用）、路徑字元；最多 10 個字
        public static string CleanName(string s)
        {
            if (s == null) return "";
            StringBuilder sb = new StringBuilder();
            foreach (char c in s.Trim())
            {
                if (char.IsControl(c) || c == '{' || c == '}' || c == '\\' || c == '/' || c == '<' || c == '>' || c == '|' || c == '"' || c == '*' || c == '?' || c == ':') continue;
                sb.Append(c);
                if (sb.Length >= 10) break;
            }
            return sb.ToString().Trim();
        }

        public static bool ValidId(string id)
        {
            if (string.IsNullOrEmpty(id) || id.Length < 4 || id.Length > 14 || !id.StartsWith("cu")) return false;
            foreach (char c in id) if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))) return false;
            return true;
        }
    }

    // ================= 處理好、可以畫的圖 =================
    class CuSprite
    {
        public bool Pixel;
        public int R;                     // 一格幾個內部像素
        public Bitmap Stand;              // 站好的樣子（已裁切）
        public int W, H;
        public bool Rig;
        public int Neck, Hip, Split;      // 兩條線、兩隻腳的分界（內部像素）
        public double NeckF, HipF;        // 0～1
        public Bitmap Head, Body, LegL, LegR;
        public int BodyY0;                // 身體那張從第幾列開始（往上多切一點，頭動的時候不會有縫）
        public int HeadTop, HeadCx, HeadW, NeckCx, NeckW;
        public Color Main = Color.Gray, Outline = Color.FromArgb(0x2A, 0x2F, 0x45);
        public readonly Dictionary<string, Bitmap> Frames = new Dictionary<string, Bitmap>();   // 動作表：stand walk1 walk2 jump sleep happy held sit
        public double Wc { get { return W / (double)R; } }
        public double Hc { get { return H / (double)R; } }
        // 內建的圖片公仔（續命小隊，DeskPals.Original.cs）：腳底不在畫布底（AnchorX／AnchorY，-1＝底部置中）、圖本身有白邊（NoHalo）、
        // 身體的範圍（BodyTop／BodyH，stand 的不透明範圍；泡泡、櫃子高度用）、沒電的電量液體（Liquid）
        public double AnchorX = -1, AnchorY = -1;
        public bool NoHalo;
        public bool Shadow;          // 腳下畫一層很淡的落地陰影（窩伴小世界：圖沒有白邊，淺色桌布上輪廓偏弱；<資料夾>.txt 的 shadow 1）
        public int BodyTop = -1, BodyH = -1, BodyLeft = -1, BodyW = -1;
        public Dictionary<string, SqLiquid> Liquid;
        public double AX { get { return AnchorX >= 0 ? AnchorX : W / 2.0; } }
        public double AY { get { return AnchorY >= 0 ? AnchorY : H; } }
        public bool HasFrame(string k) { return Frames.ContainsKey(k); }

        public static readonly string[] SheetKeys = { "stand", "walk1", "walk2", "jump", "sleep", "happy", "held", "sit" };
        public static readonly string[] SheetLabels = { "站", "走 1", "走 2", "跳", "睡", "開心", "被抓", "坐" };

        // 站姿圖準備好：量頭、脖子，切成頭／身體／兩隻腳
        public void SetStand(CuCut c, bool rig, double neck, double hip)
        {
            Stand = CuImg.ToBitmap(c); W = c.W; H = c.H;
            double gn, gh; bool conf;
            CuImg.GuessLines(c, out gn, out gh, out conf);
            NeckF = neck > 0 ? neck : gn; HipF = hip > 0 ? hip : gh;
            if (HipF < NeckF + 0.1) HipF = Math.Min(0.95, NeckF + 0.25);
            Neck = Math.Max(1, Math.Min(H - 3, (int)Math.Round(NeckF * H)));
            Hip = Math.Max(Neck + 2, Math.Min(H - 1, (int)Math.Round(HipF * H)));
            Split = CuImg.LegSplit(c, Hip);
            Rig = rig && H >= 6;
            // 頭頂、頭的寬度（頭最上面三格的範圍）、脖子寬度
            HeadTop = 0;
            for (int y = 0; y < H; y++) { bool any = false; for (int x = 0; x < W; x++) if (((c.Px[y * W + x] >> 24) & 255) >= 110) { any = true; break; } if (any) { HeadTop = y; break; } }
            int l = W, r = -1, band = Math.Min(Neck, HeadTop + 3 * R);
            for (int y = HeadTop; y < Math.Max(HeadTop + 1, band); y++) for (int x = 0; x < W; x++) if (((c.Px[y * W + x] >> 24) & 255) >= 110) { if (x < l) l = x; if (x > r) r = x; }
            if (r < 0) { l = 0; r = W - 1; }
            HeadCx = (l + r + 1) / 2; HeadW = r - l + 1;
            l = W; r = -1;
            for (int x = 0; x < W; x++) if (((c.Px[Math.Min(H - 1, Neck) * W + x] >> 24) & 255) >= 110) { if (x < l) l = x; if (x > r) r = x; }
            if (r < 0) { l = 0; r = W - 1; }
            NeckCx = (l + r + 1) / 2; NeckW = r - l + 1;
            Main = CuImg.MainColor(c);
            CutParts();
        }

        void CutParts()
        {
            DisposeParts();
            int e = Math.Max(1, R / 2);
            BodyY0 = Math.Max(0, Neck - e);
            Head = Part(0, 0, W, Neck);
            Body = Part(0, BodyY0, W, Math.Min(H, Hip + e) - BodyY0);
            LegL = Part(0, Hip, Math.Max(1, Split), H - Hip);
            LegR = Part(Split, Hip, Math.Max(1, W - Split), H - Hip);
        }

        Bitmap Part(int x, int y, int w, int h)
        {
            w = Math.Max(1, Math.Min(w, W - x)); h = Math.Max(1, Math.Min(h, H - y));
            return Stand.Clone(new Rectangle(x, y, w, h), PixelFormat.Format32bppArgb);
        }

        void DisposeParts() { foreach (Bitmap b in new Bitmap[] { Head, Body, LegL, LegR }) if (b != null) b.Dispose(); }

        public void Dispose()
        {
            DisposeParts();
            foreach (Bitmap b in Frames.Values) if (b != null && b != Stand) b.Dispose();
            if (Stand != null) Stand.Dispose();
        }

        // ---------- 做出來：一張圖 ----------
        public static CuSprite Build(CuMeta m, Bitmap src, out string err)
        {
            err = null;
            if (src == null) { err = "沒有圖"; return null; }
            if (m.Sheet) return BuildSheet(m, src, out err);
            bool hadAlpha;
            CuCut cut = CuImg.Cutout(src, m.UseAlpha, m.Tol, m.Strokes, out hadAlpha);
            if (cut == null) { err = "去背之後什麼都不剩了，把去背強度調低一點"; return null; }
            if (m.Flip) cut = CuImg.Mirror(cut);
            CuSprite s = new CuSprite();
            s.Pixel = m.Pixel;
            CuCut fin;
            if (s.Pixel) { Color ol; fin = CuImg.ToPixel(cut, m.Sub, CuImg.HCells, CuImg.WCells, out ol); s.Outline = ol; s.R = m.Sub; }
            else { fin = CuImg.ToSmooth(cut, CuImg.HCells, CuImg.WCells); s.R = CuImg.SmoothR; s.Outline = Darker(CuImg.MainColor(fin)); }
            s.SetStand(fin, m.Rig, m.Neck, m.Hip);
            return s;
        }

        static Color Darker(Color c) { return Color.FromArgb((int)(c.R * 0.25 + 0x2A * 0.4), (int)(c.G * 0.25 + 0x2F * 0.4), (int)(c.B * 0.25 + 0x45 * 0.45)); }

        // ---------- 動作表範本：4×2 格，每格 128×128，上面有標籤 ----------
        public const int TCell = 128, TLab = 26, TGap = 16, THead = 64, TCols = 4, TRows = 2;
        public static int TW { get { return TGap + TCols * (TCell + TGap); } }
        public static int TH { get { return THead + TRows * (TLab + TCell + TGap); } }
        public static Rectangle TCellRect(int i) { int c = i % TCols, r = i / TCols; return new Rectangle(TGap + c * (TCell + TGap), THead + r * (TLab + TCell + TGap) + TLab, TCell, TCell); }

        public static Bitmap Template()
        {
            Bitmap b = new Bitmap(TW, TH, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(b))
            using (Font tf = new Font("Microsoft JhengHei UI", 15f, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font hf = new Font("Microsoft JhengHei UI", 11f, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font lf = new Font("Microsoft JhengHei UI", 13f, FontStyle.Bold, GraphicsUnit.Pixel))
            using (SolidBrush paper = new SolidBrush(Color.FromArgb(0xFF, 0xF6, 0xE4)))
            using (SolidBrush ink = new SolidBrush(Color.FromArgb(0x4A, 0x30, 0x10)))
            using (SolidBrush dim = new SolidBrush(Color.FromArgb(0x9A, 0x63, 0x38)))
            using (Pen edge = new Pen(Color.FromArgb(0xC9, 0xB0, 0x8A), 2f))
            using (SolidBrush mark = new SolidBrush(Color.FromArgb(0xE2, 0x7A, 0x5A)))
            {
                g.Clear(Color.Transparent);
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                // 格子外面是奶油色紙；格子裡面透明（畫圖軟體不支援透明的話，白底也可以，會自動去背）
                g.FillRectangle(paper, 0, 0, TW, TH);
                g.DrawString("WoWo Pals 動作表範本", tf, ink, TGap, 10);
                g.DrawString("每一格畫一個動作，腳踩在格子底部。空著的格子會自動補動畫（至少畫「站」）。", hf, dim, TGap, 36);
                for (int i = 0; i < SheetKeys.Length; i++)
                {
                    Rectangle r = TCellRect(i);
                    g.DrawString(SheetLabels[i] + (i == 0 ? "（必畫）" : ""), lf, ink, r.X, r.Y - TLab + 4);
                    g.CompositingMode = CompositingMode.SourceCopy;
                    using (SolidBrush clear = new SolidBrush(Color.Transparent)) g.FillRectangle(clear, r);
                    g.CompositingMode = CompositingMode.SourceOver;
                    g.DrawRectangle(edge, r.X - 2, r.Y - 2, r.Width + 3, r.Height + 3);
                    // 地面記號：格子左右兩邊外面的小三角形
                    g.FillPolygon(mark, new Point[] { new Point(r.X - 9, r.Bottom - 5), new Point(r.X - 3, r.Bottom - 1), new Point(r.X - 9, r.Bottom + 3) });
                    g.FillPolygon(mark, new Point[] { new Point(r.Right + 8, r.Bottom - 5), new Point(r.Right + 2, r.Bottom - 1), new Point(r.Right + 8, r.Bottom + 3) });
                }
            }
            return b;
        }

        // ---------- 做出來：動作表 ----------
        static CuSprite BuildSheet(CuMeta m, Bitmap src, out string err)
        {
            err = null;
            double ar = src.Width / (double)src.Height, tar = TW / (double)TH;
            if (Math.Abs(ar - tar) > tar * 0.04 || src.Width < TW / 3) { err = "這張不是動作表範本（尺寸對不上）。先按「下載範本」，畫好再上傳"; return null; }
            double sc = src.Width / (double)TW;
            int[] px = CuImg.Pixels(src);
            CuCut[] cells = new CuCut[SheetKeys.Length];
            for (int i = 0; i < SheetKeys.Length; i++)
            {
                Rectangle r = TCellRect(i);
                int inset = (int)Math.Ceiling(3 * sc);
                Rectangle rr = Rectangle.FromLTRB((int)(r.X * sc) + inset, (int)(r.Y * sc) + inset, (int)(r.Right * sc) - inset, (int)(r.Bottom * sc) - inset);
                rr.Intersect(new Rectangle(0, 0, src.Width, src.Height));
                if (rr.Width < 4 || rr.Height < 4) continue;
                CuCut c = CuImg.Crop(px, src.Width, src.Height, rr);
                int[] cut;
                if (CuImg.HasAlpha(c.Px, c.W, c.H) && m.UseAlpha) { cut = c.Px; for (int k = 0; k < cut.Length; k++) if (((cut[k] >> 24) & 255) < 10) cut[k] = 0; }
                else
                {
                    int[] solid = (int[])c.Px.Clone();
                    for (int k = 0; k < solid.Length; k++) if (((solid[k] >> 24) & 255) < 128) solid[k] = unchecked((int)0xFFFFFFFF); else solid[k] |= unchecked((int)0xFF000000);
                    cut = CuImg.RemoveBg(solid, c.W, c.H, m.Tol);
                }
                Rectangle bb = CuImg.Bounds(cut, c.W, c.H, 40);
                int area = 0; foreach (int v in cut) if (((v >> 24) & 255) >= 110) area++;
                if (bb.Width < 2 || bb.Height < 2 || area < c.W * c.H / 200) continue;   // 空格
                CuCut f = CuImg.Crop(cut, c.W, c.H, bb);
                if (m.Flip) f = CuImg.Mirror(f);
                cells[i] = f;
            }
            if (cells[0] == null) { err = "動作表的「站」那格是空的（至少要畫「站」）"; return null; }
            CuSprite s = new CuSprite();
            s.Pixel = m.Pixel;
            s.R = s.Pixel ? m.Sub : CuImg.SmoothR;
            // 同一個比例：「站」那格的高度＝16 格；別格也照這個比例（太大的再縮）
            double unit = s.Pixel ? m.Sub : CuImg.SmoothR;
            double k0 = Math.Min((CuImg.HCells * unit - (s.Pixel ? 2 : 0)) / cells[0].H, (CuImg.WCells * unit - (s.Pixel ? 2 : 0)) / cells[0].W);
            foreach (CuCut c in cells) if (c != null) k0 = Math.Min(k0, Math.Min(20 * unit / c.H, 22 * unit / c.W));
            CuCut[] outs = new CuCut[cells.Length];
            int cw = 1, ch = 1;
            for (int i = 0; i < cells.Length; i++)
            {
                if (cells[i] == null) continue;
                int tw = Math.Max(1, (int)Math.Round(cells[i].W * k0)), th = Math.Max(1, (int)Math.Round(cells[i].H * k0));
                if (s.Pixel) { Color ol; outs[i] = CuImg.ToPixelSized(cells[i], tw, th, m.Sub >= 2 ? 18 : 12, false, out ol); if (i == 0) s.Outline = ol; }
                else outs[i] = CuImg.ToSmoothSized(cells[i], tw, th);
                cw = Math.Max(cw, outs[i].W); ch = Math.Max(ch, outs[i].H);
            }
            if (!s.Pixel) s.Outline = Darker(CuImg.MainColor(outs[0]));
            // 全部放進同樣大小的框：底部置中（腳踩地）
            for (int i = 0; i < outs.Length; i++)
            {
                if (outs[i] == null) continue;
                CuCut o = new CuCut(); o.W = cw; o.H = ch; o.Px = new int[cw * ch];
                int ox = (cw - outs[i].W) / 2, oy = ch - outs[i].H;
                for (int y = 0; y < outs[i].H; y++) Array.Copy(outs[i].Px, y * outs[i].W, o.Px, (oy + y) * cw + ox, outs[i].W);
                if (i == 0) s.SetStand(o, false, -1, -1);
                else s.Frames[SheetKeys[i]] = CuImg.ToBitmap(o);
            }
            s.Frames["stand"] = s.Stand;
            return s;
        }

        // ---------- 存／讀（處理好的圖存成 PNG，下次直接讀） ----------
        public void SaveTo(string dir)
        {
            Stand.Save(Path.Combine(dir, "sprite.png"), ImageFormat.Png);
            foreach (KeyValuePair<string, Bitmap> kv in Frames) if (kv.Key != "stand") kv.Value.Save(Path.Combine(dir, "frame-" + kv.Key + ".png"), ImageFormat.Png);
            Dictionary<string, object> d = new Dictionary<string, object>();
            d["pixel"] = Pixel; d["r"] = R; d["neck"] = NeckF; d["hip"] = HipF; d["rig"] = Rig; d["outline"] = Outline.ToArgb();
            File.WriteAllText(Path.Combine(dir, "sprite.json"), new JavaScriptSerializer().Serialize(d));
        }

        public static CuSprite LoadFrom(string dir, CuMeta m)
        {
            try
            {
                string sj = Path.Combine(dir, "sprite.json"), sp = Path.Combine(dir, "sprite.png");
                if (!File.Exists(sj) || !File.Exists(sp)) return null;
                Dictionary<string, object> d = new JavaScriptSerializer().DeserializeObject(File.ReadAllText(sj)) as Dictionary<string, object>;
                if (d == null) return null;
                CuSprite s = new CuSprite();
                s.Pixel = d.ContainsKey("pixel") && d["pixel"] is bool && (bool)d["pixel"];
                if (s.Pixel != m.Pixel) return null;
                s.R = Convert.ToInt32(d["r"]);
                if (s.R < 1 || s.R > 8) return null;
                s.Outline = Color.FromArgb(Convert.ToInt32(d["outline"]));
                double neck = Convert.ToDouble(d["neck"]), hip = Convert.ToDouble(d["hip"]);
                bool rig = d.ContainsKey("rig") && d["rig"] is bool && (bool)d["rig"];
                CuCut c;
                using (Bitmap b = LoadPng(sp)) { if (b == null || b.Width > 400 || b.Height > 400) return null; c = CuImg.FromBitmap(b); }
                s.SetStand(c, rig, neck, hip);
                if (m.Sheet)
                {
                    s.Frames["stand"] = s.Stand;
                    for (int i = 1; i < SheetKeys.Length; i++)
                    {
                        string fp = Path.Combine(dir, "frame-" + SheetKeys[i] + ".png");
                        if (!File.Exists(fp)) continue;
                        Bitmap fb = LoadPng(fp);
                        if (fb != null && fb.Width == s.W && fb.Height == s.H) s.Frames[SheetKeys[i]] = fb; else if (fb != null) fb.Dispose();
                    }
                }
                return s;
            }
            catch (Exception ex) { App.Log("custom sprite load: " + ex.Message); return null; }
        }

        public static Bitmap LoadPng(string path)
        {
            try
            {
                using (MemoryStream ms = new MemoryStream(File.ReadAllBytes(path)))
                using (Image img = Image.FromStream(ms, false, true))
                {
                    Bitmap b = new Bitmap(img.Width, img.Height, PixelFormat.Format32bppArgb);
                    using (Graphics g = Graphics.FromImage(b)) { g.CompositingMode = CompositingMode.SourceCopy; g.DrawImage(img, new Rectangle(0, 0, img.Width, img.Height)); }
                    return b;
                }
            }
            catch { return null; }
        }
    }

    // ================= 存放：資料夾 custom\<id>\（source.png 原圖、meta.json 設定、sprite.png 處理好的圖、icon.png 給 VS Code）=================
    static class CuStore
    {
        public static string Root { get { return Path.Combine(World.DataDir, "custom"); } }
        static List<CuMeta> metas;
        static readonly Dictionary<string, CuSprite> sprites = new Dictionary<string, CuSprite>();

        public static List<CuMeta> All()
        {
            if (metas != null) return metas;
            metas = new List<CuMeta>();
            try
            {
                if (Directory.Exists(Root))
                    foreach (string d in Directory.GetDirectories(Root))
                    {
                        string id = Path.GetFileName(d);
                        if (!CuMeta.ValidId(id)) continue;
                        string mp = Path.Combine(d, "meta.json");
                        if (!File.Exists(mp) || new FileInfo(mp).Length > (1 << 20)) continue;
                        CuMeta m = CuMeta.FromJson(File.ReadAllText(mp, Encoding.UTF8));
                        if (m == null) continue;
                        m.Id = id;
                        if (m.Name == "") m.Name = "小公仔";
                        metas.Add(m);
                    }
            }
            catch (Exception ex) { App.Log("custom list: " + ex.Message); }
            metas.Sort(delegate(CuMeta a, CuMeta b) { int c = string.CompareOrdinal(a.Created, b.Created); return c != 0 ? c : string.CompareOrdinal(a.Id, b.Id); });
            return metas;
        }

        public static CuMeta Get(string id) { foreach (CuMeta m in All()) if (m.Id == id) return m; return null; }
        public static string Dir(string id) { return Path.Combine(Root, id); }

        public static CuSprite Sprite(CuMeta m)
        {
            CuSprite s;
            if (sprites.TryGetValue(m.Id, out s)) return s;
            string dir = Dir(m.Id);
            s = CuSprite.LoadFrom(dir, m);
            if (s == null)
            {
                // 沒有處理好的圖（或版本不對）：從原圖重做一次
                string err;
                Bitmap src = CuImg.LoadFile(Path.Combine(dir, "source.png"), out err);
                if (src != null)
                {
                    s = CuSprite.Build(m, src, out err);
                    src.Dispose();
                    if (s != null) try { s.SaveTo(dir); } catch { }
                }
                if (s == null) App.Log("custom sprite " + m.Id + ": " + err);
            }
            if (s != null) sprites[m.Id] = s;
            return s;
        }

        public static string NewId()
        {
            Random r = new Random();
            const string cs = "abcdefghijkmnpqrstuvwxyz23456789";
            for (int tries = 0; tries < 100; tries++)
            {
                StringBuilder sb = new StringBuilder("cu");
                for (int i = 0; i < 6; i++) sb.Append(cs[r.Next(cs.Length)]);
                string id = sb.ToString();
                if (!Directory.Exists(Dir(id)) && Pal.GetBuiltin(id) == null) return id;
            }
            return "cu" + DateTime.Now.Ticks.ToString("x").Substring(0, 8);
        }

        // 存一隻（新的或改過的）：原圖、設定、處理好的圖、VS Code 用的小圖
        public static void Save(CuMeta m, Bitmap source, CuSprite s)
        {
            string dir = Dir(m.Id);
            Directory.CreateDirectory(dir);
            if (string.IsNullOrEmpty(m.Created)) m.Created = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss");
            if (source != null) source.Save(Path.Combine(dir, "source.png"), ImageFormat.Png);
            File.WriteAllText(Path.Combine(dir, "meta.json"), m.ToJson(), new UTF8Encoding(false));
            foreach (string f in Directory.GetFiles(dir, "frame-*.png")) try { File.Delete(f); } catch { }
            s.SaveTo(dir);
            try { using (Bitmap ic = Icon(m, s, 6)) ic.Save(Path.Combine(dir, "icon.png"), ImageFormat.Png); } catch { }
            CuSprite old;
            if (sprites.TryGetValue(m.Id, out old) && old != s) sprites.Remove(m.Id);
            sprites[m.Id] = s;
            Reset(false);
        }

        public static void Delete(string id)
        {
            if (!CuMeta.ValidId(id)) return;
            CuSprite s;
            if (sprites.TryGetValue(id, out s)) sprites.Remove(id);
            try { Directory.Delete(Dir(id), true); } catch (Exception ex) { App.Log("custom delete: " + ex.Message); }
            Reset(false);
        }

        // 清快取（全部重讀）；all＝連處理好的圖也重讀
        public static void Reset(bool all)
        {
            metas = null;
            if (all) sprites.Clear();
            Pal.CuReset();
        }

        // 站好的樣子（有白邊）畫成一張小圖：VS Code 側邊欄、設定視窗用
        public static Bitmap Icon(CuMeta m, CuSprite s, int ps)
        {
            int pad = 2 * ps;
            int w = (int)Math.Ceiling(s.Wc * ps) + 2 * pad, h = (int)Math.Ceiling(s.Hc * ps) + 2 * pad;
            Bitmap b = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(b))
            {
                g.Clear(Color.Transparent);
                Pet.CuDrawStill(g, s, w / 2.0, h - pad, ps, false, false, Color.White);
            }
            return b;
        }
    }

    // ================= Pal：自己做的公仔、我的櫃 =================
    partial class Pal
    {
        public bool Cu;                       // 自己做的公仔
        public CuMeta Meta;
        public CuSprite Spr;
        public const string Mine = "mine";
        public static readonly string[] Guests = { "duoduo", "meidian", "cici", "fanfan", "bobo", "mian", "spidey", "po", "stitch", "hangyodon", "tinky", "dipsy", "laalaa" };   // 可以來我的櫃作客的內建公仔   //@fan
        // <public> public static readonly string[] Guests = { "duoduo", "meidian", "cici", "fanfan", "bobo", "mian" };

        public static void CuReset() { all = null; }
        public static Pal GetBuiltin(string id) { if (all == null) return null; foreach (Pal p in all) if (p.Id == id && !p.Cu) return p; return null; }
        public static bool HasCustom() { return CuStore.All().Count > 0; }

        static List<Pal> CuPals()
        {
            List<Pal> l = new List<Pal>();
            foreach (CuMeta m in CuStore.All())
            {
                CuSprite s = CuStore.Sprite(m);
                if (s != null) l.Add(MakeCu(m, s));
            }
            return l;
        }

        public static Pal MakeCu(CuMeta m, CuSprite s)
        {
            Pal p = new Pal();
            p.Cu = true; p.Meta = m; p.Spr = s;
            p.Id = m.Id; p.Name = m.Name == "" ? "小公仔" : m.Name;
            p.Move = "walk"; p.BallKind = "tennis"; p.NightStyle = "sleepy"; p.NightBubble = 3;
            Color mc = s.Main;
            double lum = 0.299 * mc.R + 0.587 * mc.G + 0.114 * mc.B;
            double f = lum > 150 ? 0.5 : (lum > 90 ? 0.75 : 1.0);
            p.Accent = Color.FromArgb((int)(mc.R * f), (int)(mc.G * f), (int)(mc.B * f));
            p.Panel = Color.FromArgb((int)(mc.R * 0.22 + 255 * 0.78), (int)(mc.G * 0.22 + 255 * 0.78), (int)(mc.B * 0.22 + 255 * 0.78));
            p.Halo = Color.White; p.HaloNight = C(0xC8C0EC);
            p.Day['k'] = s.Outline; p.Night['k'] = Color.FromArgb(s.Outline.R / 2, s.Outline.G / 2, s.Outline.B / 2 + 10);
            switch (m.Persona) { case "cool": p.Speed = 38; break; case "shy": p.Speed = 32; break; case "funny": p.Speed = 48; break; case "cat": p.Speed = 40; break; case "dog": p.Speed = 66; break; default: p.Speed = 55; break; }
            p.TopRows = Math.Max(0, (int)Math.Ceiling(s.Hc) - 16);
            p.EyeRow = -1;
            // 萬一有共用的程式碼要內建的像素零件：給空白的，不會壞
            string[] blank = { "............" };
            foreach (string k in new string[] { "HEAD", "BODY", "ARMS_UP", "ARMS_HUG", "LEGS_A", "LEGS_B", "LEGS_SIT", "SLEEPY", "HAPPY", "DIZZY" }) p.Art[k] = blank;
            p.CuLines(m.Persona, p.Name);
            p.CuStudyLines(m.Persona, p.Name);
            p.Shared();
            return p;
        }

        // 我的櫃：自己做的（最多 4 隻）＋可以請內建公仔來作客；custom\mine.txt
        public static string[] MineIds()
        {
            List<string> ids = new List<string>();
            List<CuMeta> cus = CuStore.All();
            string saved = "";
            try { string f = Path.Combine(CuStore.Root, "mine.txt"); if (File.Exists(f)) saved = File.ReadAllText(f); } catch { }
            bool hasFile = saved.Trim() != "";
            foreach (string t in saved.Split(new char[] { ' ', ',', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries))
            {
                if (ids.Count >= 4 || ids.Contains(t)) continue;
                if (CuStore.Get(t) != null || Array.IndexOf(Guests, t) >= 0) ids.Add(t);
            }
            bool anyCu = false; foreach (string t in ids) if (CuStore.Get(t) != null) anyCu = true;
            if (!hasFile || !anyCu)
                foreach (CuMeta m in cus) { if (ids.Count >= 4) break; if (!ids.Contains(m.Id)) ids.Add(m.Id); }
            if (ids.Count > 4) ids.RemoveRange(4, ids.Count - 4);
            return ids.ToArray();
        }

        public static void SaveMine(List<string> ids)
        {
            try { Directory.CreateDirectory(CuStore.Root); File.WriteAllText(Path.Combine(CuStore.Root, "mine.txt"), string.Join(" ", ids.ToArray())); } catch { }
        }

        // 換一櫃、設定視窗列出來的櫃子：有自己做的公仔才有「我的櫃」
        public static string[] LineupsNow()
        {
            if (!HasCustom()) return Lineups;
            List<string> l = new List<string>(Lineups); l.Add(Mine);
            return l.ToArray();
        }
    }

    // ================= 一隻自己做的公仔：姿勢、畫法 =================
    partial class Pet
    {
        // 一格的姿勢（單位：格；+y 往下；角度：度）
        class CuPose
        {
            public double X, Y, Rot, PivotY, Sx = 1, Sy = 1;      // 整隻：位移、旋轉（繞腳／中心／頭頂）、縮放（繞腳）
            public int Rot90;                                     // 像素風打滾：90° 一格一格轉
            public double UpY, BodyRot, BodySy = 1;               // 上半身（頭＋身體）上下、身體搖、身體伸縮（繞屁股）
            public double HeadX, HeadY, HeadRot;                  // 頭
            public double LX, LY, LRot, RX, RY, RRot;             // 兩隻腳
            public bool NoLegs;                                   // 窩著（貓貓窩）：腳收起來
            public string Frame;                                  // 動作表的哪一格
            public void Reset() { X = Y = Rot = PivotY = UpY = BodyRot = HeadX = HeadY = HeadRot = LX = LY = LRot = RX = RY = RRot = 0; Sx = Sy = BodySy = 1; Rot90 = 0; NoLegs = false; Frame = null; }
        }
        readonly CuPose cuPose = new CuPose();
        Bitmap cuCanvas;
        string cuAct = "", cuPrev = "";
        double cuT, cuLandT, cuX, cuIgnoreCd;
        static readonly string[] CU_BLANK = { "............" };
        static readonly string[] BENTO = { ".kkkkkkkk.", "k22222222k", "k2WWW1YY2k", "k2WSW1PP2k", "k22222222k", ".kkkkkkkk." };
        static readonly string[] MUG = { "kkkk..", "kWWkkk", "kSWk.k", "kWWkkk", ".kk..." };
        string Persona { get { return P.Meta == null ? "lively" : P.Meta.Persona; } }

        // ---------- Frame()：姿勢算好，Rows 是空白（DrawFigure 交給 DrawFigureCu） ----------
        Fr FrameCu()
        {
            CuPoseNow(cuPose);
            Fr f = F(CU_BLANK);
            f.Rot = cuPose.Rot90 != 0 || Math.Abs(cuPose.Rot) > 30 ? 1 : 0;
            f.Acc = Math.Abs(cuPose.Rot) < 10 && cuPose.Rot90 == 0 && state != "sleep" && state != "drag" && state != "dizzy";
            return f;
        }

        void DrawFigureCu(Graphics g, Fr f, int sbx, int sby, int sps, bool fx, bool extras)
        {
            CuDraw(g, cuPose, sbx + 6 * sps, sby + 16 * sps, sps, fx);
            if (f.Acc) CuAccessories(g, cuPose, sbx, sby, sps, fx, true);
            if (extras)
            {
                CuFront(g, sbx, sby, sps, fx);
                DrawLunch(g, f, sbx, sby, sps, fx);
            }
        }

        // 嘴裡叼著球（汪系撿球）
        void CuFront(Graphics g, int sbx, int sby, int sps, bool fx)
        {
            if (w.Holder != this) return;
            CuSprite s = P.Spr;
            double top = 16 - s.Hc + cuPose.Y + cuPose.UpY + cuPose.HeadY;
            double col = 6 + (s.HeadCx + s.HeadW / 2.0 - s.W / 2.0) / s.R - 2 + cuPose.X + cuPose.HeadX;
            DrawAt(g, w.BallKind == "baseball" ? BALLART : TBALL, col, top + s.Neck / (double)s.R - 3, sbx, sby, sps, fx, false, true);
        }

        // ---------- 依狀態算姿勢 ----------
        void CuPoseNow(CuPose p)
        {
            p.Reset();
            CuSprite s = P.Spr;
            string ps = Persona;
            double a = anim;
            bool sheet = s.Frames.Count > 0;
            double legH = (s.H - s.Hip) / (double)s.R, bodyH = (s.Hip - s.Neck) / (double)s.R;
            bool walking = state == "walk" || state == "goto" || state == "seek" || state == "fetch" || state == "hide"
                || (state == "cu" && (cuAct == "pushwalk" || cuAct == "fetchback" || cuAct == "comeback" || cuAct == "zoom"));
            if (rolling || state == "fling")
            {
                if (s.Pixel) p.Rot90 = (int)Math.Floor(a * 14) % 4; else p.Rot = (a * 760) % 360;
                p.PivotY = 0.5;
                if (sheet && s.HasFrame("jump")) p.Frame = "jump";
            }
            else if (state == "drag")
            {
                // 被抓著：從頭頂晃、腳甩來甩去
                p.PivotY = 1; p.Rot = Math.Sin(a * 5.2) * 11; p.Sy = 1.05; p.Sx = 0.97;
                p.LRot = Math.Sin(a * 5.2 + 0.9) * 16; p.RRot = Math.Sin(a * 5.2 + 1.6) * 16; p.LY = 0.3; p.RY = 0.3;
                if (sheet) p.Frame = s.HasFrame("held") ? "held" : (s.HasFrame("jump") ? "jump" : null);
            }
            else if (state == "air" || state == "stowfly")
            {
                bool up = vy < 0;
                p.Sy = up ? 1.10 : 1.04; p.Sx = up ? 0.93 : 0.98;
                p.LRot = -12; p.RRot = 12; p.LY = -0.4; p.RY = -0.4;
                p.HeadY = up ? 0.3 : -0.3;
                if (sheet && s.HasFrame("jump")) p.Frame = "jump";
            }
            else if (state == "sleep")
            {
                double br = Math.Sin(a * 1.6);
                if (ps == "cat")
                {
                    // 貓貓窩：腳收起來、身體壓低、頭也低低的
                    p.NoLegs = true; p.UpY = legH * 0.92; p.BodySy = 0.94; p.Sx = 1.04 + br * 0.012; p.HeadY = 0.3; p.HeadRot = 4;
                    if (!s.Rig) { p.Sy = 0.86 + br * 0.012; p.Sx = 1.08; }
                }
                else { p.Rot = 9; p.Sy = 0.97 + br * 0.015; p.HeadRot = 10; p.HeadY = 0.3; }
                if (sheet && s.HasFrame("sleep")) { p.Frame = "sleep"; p.Rot = 0; p.Sy = 1 + br * 0.012; }
            }
            else if (walking)
            {
                bool fast = state == "seek" || state == "fetch" || cuAct == "zoom" || cuAct == "fetchback";
                double ph = a * (fast ? 2.6 : 1.8) * 2 * Math.PI, sn = Math.Sin(ph);
                double lift = Math.Max(0.6, Math.Min(1.4, legH * 0.38));
                p.LY = -Math.Max(0, sn) * lift; p.RY = -Math.Max(0, -sn) * lift;
                p.LX = Math.Cos(ph) * 0.45; p.RX = -Math.Cos(ph) * 0.45;
                p.UpY = -Math.Abs(sn) * 0.5; p.BodyRot = 3;
                p.HeadY = -Math.Abs(Math.Sin(ph - 0.7)) * 0.35 + Math.Abs(sn) * 0.5 - 0.1; p.HeadX = -0.2;
                if (!s.Rig) { p.Y = -Math.Abs(sn) * 0.7; p.Rot = sn * 5; }
                if (sheet)
                {
                    bool st2 = Math.Floor(a * (fast ? 7 : 5)) % 2 == 1;
                    if (s.HasFrame("walk1") && s.HasFrame("walk2")) { p.Frame = st2 ? "walk2" : "walk1"; p.Rot = 0; p.Y = -Math.Abs(sn) * 0.4; }
                    else if (s.HasFrame("walk1")) { p.Frame = st2 ? "walk1" : "stand"; p.Rot = 0; }
                }
            }
            else if (state == "hug")
            {
                // 開心：連跳兩下＋點頭
                double c = a % 1.1;
                double hop = c < 0.5 ? Math.Abs(Math.Sin(c / 0.5 * Math.PI * 2)) : 0;
                p.Y = -hop * 1.3; p.HeadRot = Math.Sin(a * 7) * 6;
                if (hop < 0.15 && c < 0.6) { p.Sy = 0.93; p.Sx = 1.05; }
                if (ps == "dog") p.BodyRot = Math.Sin(a * 22) * 4;
                if (sheet && s.HasFrame("happy")) p.Frame = "happy";
            }
            else if (state == "dance" || state == "elvis")
            {
                p.Rot = Math.Sin(a * 6) * 8; p.Y = -Math.Abs(Math.Sin(a * 6)) * 0.7;
                p.LY = -Math.Max(0, Math.Sin(a * 6)) * 0.7; p.RY = -Math.Max(0, -Math.Sin(a * 6)) * 0.7; p.HeadRot = -Math.Sin(a * 6) * 6;
                if (sheet && s.HasFrame("happy")) p.Frame = "happy";
            }
            else if (state == "dizzy") { p.Rot = Math.Sin(a * 12) * 10; p.HeadRot = Math.Sin(a * 12 + 1) * 12; }
            else if (state == "cu") CuActPose(p, a, legH);
            else if (state == "plop") { p.UpY = legH * 0.7; p.LRot = 60; p.RRot = -60; p.Sx = 1.06; if (sheet && s.HasFrame("sit")) p.Frame = "sit"; }
            else if (state == "kick") { p.RRot = -38; p.RX = 0.6; p.Rot = -4; }
            else if (state == "think") { p.HeadRot = 13; p.HeadY = 0.1; }
            else if (state == "wave") { p.BodyRot = Math.Sin(a * 9) * 6; p.HeadRot = 6 + Math.Sin(a * 9) * 3; p.Y = -Math.Abs(Math.Sin(a * 4.5)) * 0.4; if (sheet && s.HasFrame("happy")) p.Frame = "happy"; }
            else if (state == "nudge" || state == "glass") { p.Rot = 6 + (knock > 0 ? 3 : 0); p.HeadX = 0.4; }
            else if (state == "spin" || state == "twirl") { p.Sx = Math.Cos(a * 12); if (Math.Abs(p.Sx) < 0.15) p.Sx = p.Sx < 0 ? -0.15 : 0.15; }
            else if (state == "catch" || state == "throw") { p.Sy = 1.06; p.Rot = -5; }
            else if (state == "pose")
            {
                if (poseKind == "tap") { p.Rot = 7; p.HeadX = 0.5; }
                else { p.Rot = -5; p.Sy = 1.04; p.HeadRot = -6; if (sheet && s.HasFrame("happy")) p.Frame = "happy"; }
            }
            else
            {
                // 發呆：呼吸、偶爾歪頭；晚上頭垂垂的
                double br = Math.Sin(a * (Night ? 1.4 : 2.2));
                p.BodySy = 1 + br * 0.03; p.UpY = 0;
                double tilt = (a % 7.3) < 1.3 ? Math.Sin((a % 7.3) / 1.3 * Math.PI) : 0;
                p.HeadRot = tilt * 9;
                if (Night) { p.HeadRot += 7; p.HeadY = 0.35; }
                if (ps == "dog" && (a % 5) < 1.2) p.BodyRot = Math.Sin(a * 22) * 3;
                if (!s.Rig) { p.Sy = 1 + br * 0.022; p.Sx = 1 - br * 0.012; p.Rot = tilt * 3 + (Night ? 3 : 0); }
            }
            if (cuLandT > 0) { double q = cuLandT / 0.2; p.Sy *= 1 - 0.13 * q; p.Sx *= 1 + 0.1 * q; }
            if (!s.Rig && p.Frame == null)
            {
                // 沒有切線：整隻一起動（上半身的上下也算到整隻）
                p.Y += p.UpY * 0.6; p.Rot += p.BodyRot * 0.6 + p.HeadRot * 0.35;
                if (p.NoLegs) { p.Y = 0; }
            }
        }

        // 自己做的公仔專屬動作的姿勢（state == "cu"）
        void CuActPose(CuPose p, double a, double legH)
        {
            CuSprite s = P.Spr;
            switch (cuAct)
            {
                case "wag":
                    // 搖尾巴：屁股扭扭、頭跟著晃、小跳
                    p.BodyRot = Math.Sin(a * 24) * 6; p.HeadRot = Math.Sin(a * 12) * 5; p.Y = -Math.Abs(Math.Sin(a * 6)) * 0.4;
                    if (!s.Rig) p.Rot = Math.Sin(a * 24) * 5;
                    break;
                case "ignore":
                    // 不理你：頭抬高、尾巴（身體）甩一下
                    p.HeadRot = -10; p.HeadY = -0.2; p.BodyRot = Math.Sin(a * 3) * 2;
                    break;
                case "push":
                    // 伸手（前腳）推推
                    double k2 = Math.Sin(Math.Min(1, cuT / 0.5) * Math.PI);
                    p.Rot = 6 * k2; p.RRot = -42 * k2; p.RX = 0.8 * k2; p.RY = -0.8 * k2; p.HeadX = 0.4 * k2;
                    break;
                case "shy":
                    // 害羞：頭低低、縮起來
                    p.HeadRot = 14; p.HeadY = 0.5; p.Sy = 0.95; p.Sx = 1.02; p.BodyRot = Math.Sin(a * 10) * 1.5;
                    break;
                case "sit":
                    p.UpY = legH * 0.7; p.LRot = 60; p.RRot = -60; p.Sx = 1.05;
                    if (!s.Rig) p.Sy = 0.9;
                    if (s.HasFrame("sit")) p.Frame = "sit";
                    break;
                case "cool":
                    p.Rot = -6; p.HeadRot = -8; p.Sy = 1.03;
                    break;
            }
        }

        // ---------- 畫：先在小畫布上把頭／身體／腳組起來，再放大畫上去（加白邊、晚上變暗） ----------
        // 每一格：直接組在「螢幕大小」的小圖上（像素風先在格子大小組好再放大），
        // 再一次把白邊、晚上變暗、左右翻轉做完（逐像素），最後原尺寸貼上去——四隻一起跑也不會卡
        Bitmap cuOut;
        int[] cuBuf;
        byte[] cuMask, cuTmp;
        void CuDraw(Graphics g, CuPose p, double feetX, double feetY, int ps, bool fx) { CuDrawSc(g, p, feetX, feetY, ps / (float)P.Spr.R, ps, fx); }
        // sc 自己給：續命小隊在櫃子裡依格子大小縮放（不限整數倍）
        void CuDrawSc(Graphics g, CuPose p, double feetX, double feetY, float sc, int ps, bool fx)
        {
            CuSprite s = P.Spr;
            int mb, cw, ch;
            CuCanvasSize(s, out cw, out ch, out mb);
            int hw = Math.Max(1, ps / 3), pad = hw + 1;
            int tw = (int)Math.Ceiling(cw * sc) + 2 * pad, th = (int)Math.Ceiling(ch * sc) + 2 * pad;
            if (cuOut == null || cuOut.Width != tw || cuOut.Height != th)
            {
                if (cuOut != null) cuOut.Dispose();
                cuOut = new Bitmap(tw, th, PixelFormat.Format32bppPArgb);
            }
            using (Graphics og = Graphics.FromImage(cuOut))
            {
                og.Clear(Color.Transparent);
                if (s.Pixel)
                {
                    if (cuCanvas == null || cuCanvas.Width != cw || cuCanvas.Height != ch)
                    {
                        if (cuCanvas != null) cuCanvas.Dispose();
                        cuCanvas = new Bitmap(cw, ch, PixelFormat.Format32bppArgb);
                    }
                    using (Graphics cg = Graphics.FromImage(cuCanvas)) { cg.Clear(Color.Transparent); CuCompose(cg, s, p, cw / 2, ch - mb, null); }
                    CuThreshold(cuCanvas);
                    og.InterpolationMode = InterpolationMode.NearestNeighbor;
                    og.PixelOffsetMode = PixelOffsetMode.Half;
                    og.DrawImage(cuCanvas, new RectangleF(pad, pad, cw * sc, ch * sc), new RectangleF(0, 0, cw, ch), GraphicsUnit.Pixel);
                }
                else
                    using (Matrix bm = new Matrix(sc, 0, 0, sc, pad, pad)) CuCompose(og, s, p, cw / 2, ch - mb, bm);
            }
            CuHaloPass(cuOut, hw, Night ? P.HaloNight : P.Halo, Night, fx, !s.NoHalo);
            int dx = (int)Math.Round(feetX - pad - cw / 2.0 * sc), dy = (int)Math.Round(feetY - pad - (ch - mb) * sc);
            InterpolationMode im = g.InterpolationMode; PixelOffsetMode pom = g.PixelOffsetMode;
            g.InterpolationMode = InterpolationMode.NearestNeighbor; g.PixelOffsetMode = PixelOffsetMode.Half;
            g.DrawImage(cuOut, new Rectangle(dx, dy, tw, th), 0, 0, tw, th, GraphicsUnit.Pixel);
            g.InterpolationMode = im; g.PixelOffsetMode = pom;
        }

        // 白邊（往外 hw 像素的實心框，跟內建公仔一樣）、晚上變暗、左右翻轉：一次掃完（預乘 alpha）
        void CuHaloPass(Bitmap b, int hw, Color halo, bool night, bool flip, bool ring)
        {
            int w = b.Width, h = b.Height, n = w * h;
            if (cuBuf == null || cuBuf.Length != n) { cuBuf = new int[n]; cuMask = new byte[n]; cuTmp = new byte[n]; }
            BitmapData d = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadWrite, PixelFormat.Format32bppPArgb);
            try
            {
                for (int y = 0; y < h; y++) System.Runtime.InteropServices.Marshal.Copy(new IntPtr(d.Scan0.ToInt64() + (long)y * d.Stride), cuBuf, y * w, w);
                // 剪影往外長 hw（先橫再直）；圖本身有白邊的（ring＝false）不加
                if (ring)
                for (int y = 0; y < h; y++)
                {
                    int row = y * w, run = -100000;
                    for (int x = 0; x < w; x++) { if (((cuBuf[row + x] >> 24) & 255) >= 60) run = x; cuTmp[row + x] = (byte)(x - run <= hw ? 1 : 0); }
                    run = 100000;
                    for (int x = w - 1; x >= 0; x--) { if (((cuBuf[row + x] >> 24) & 255) >= 60) run = x; if (run - x <= hw) cuTmp[row + x] = 1; }
                }
                if (ring)
                for (int x = 0; x < w; x++)
                {
                    int run = -100000;
                    for (int y = 0; y < h; y++) { if (cuTmp[y * w + x] != 0) run = y; cuMask[y * w + x] = (byte)(y - run <= hw ? 1 : 0); }
                    run = 100000;
                    for (int y = h - 1; y >= 0; y--) { if (cuTmp[y * w + x] != 0) run = y; if (run - y <= hw) cuMask[y * w + x] = 1; }
                }
                int hr = halo.R, hg = halo.G, hb = halo.B;
                for (int i = 0; i < n; i++)
                {
                    int v = cuBuf[i], a = (v >> 24) & 255, r = (v >> 16) & 255, gg = (v >> 8) & 255, bb = v & 255;
                    // 晚上：程式畫的公仔（有加白邊的）整隻暗下來偏藍；圖片公仔（續命小隊、窩伴小世界，圖本身有白邊或沒有邊）顏色照白天，只暗一點點，晚上靠動作、台詞
                    if (night && a > 0) { if (ring) { r = r * 58 / 100 + a * 5 / 255; gg = gg * 60 / 100 + a * 5 / 255; bb = bb * 78 / 100 + a * 18 / 255; } else { r = r * 93 / 100; gg = gg * 93 / 100; bb = bb * 94 / 100; } }
                    if (ring && cuMask[i] != 0 && a < 255) { int inv = 255 - a; r += hr * inv / 255; gg += hg * inv / 255; bb += hb * inv / 255; a = 255; }
                    cuBuf[i] = (a << 24) | (Math.Min(255, r) << 16) | (Math.Min(255, gg) << 8) | Math.Min(255, bb);
                }
                if (flip)
                    for (int y = 0; y < h; y++)
                    {
                        int row = y * w;
                        for (int x = 0; x < w / 2; x++) { int t = cuBuf[row + x]; cuBuf[row + x] = cuBuf[row + w - 1 - x]; cuBuf[row + w - 1 - x] = t; }
                    }
                for (int y = 0; y < h; y++) System.Runtime.InteropServices.Marshal.Copy(cuBuf, y * w, new IntPtr(d.Scan0.ToInt64() + (long)y * d.Stride), w);
            }
            finally { b.UnlockBits(d); }
        }

        static void CuCanvasSize(CuSprite s, out int cw, out int ch, out int mb)
        {
            int R = s.R, ext = (int)Math.Ceiling(2 * Math.Max(s.AX, s.W - s.AX)), m = Math.Max(ext, s.H);
            cw = m + 6 * R + 2;
            int mt = Math.Max(3 * R + s.H / 6, (ext - s.H) / 2 + 3 * R);
            int below = (int)Math.Ceiling(s.H - s.AY);   // 腳底以下還有圖（跳的動作線、垂下來的電線）
            mb = Math.Max(2 * R, (ext - s.H) / 2 + 2 * R) + below;
            ch = (int)Math.Ceiling(s.AY) + mt + mb;
            if (cw % 2 == 1) cw++;
        }

        // 小畫布 → 螢幕：白邊（往八個方向各畫一次的剪影）＋本體；像素風用最近點放大
        static readonly Dictionary<int, ImageAttributes> haloIa = new Dictionary<int, ImageAttributes>();
        static ImageAttributes nightIa;
        static void CuBlit(Graphics g, Bitmap canvas, CuSprite s, double feetX, double feetY, int cw, int ch, int mb, int ps, bool fx, Color halo, bool night, float alpha)
        {
            float sc = ps / (float)s.R;
            float dx = (float)(feetX - cw / 2.0 * sc), dy = (float)(feetY - (ch - mb) * sc);
            if (s.Pixel) { dx = (float)Math.Round(dx); dy = (float)Math.Round(dy); }
            float dw = cw * sc, dh = ch * sc;
            PointF[] pts = fx ? new PointF[] { new PointF(dx + dw, dy), new PointF(dx, dy), new PointF(dx + dw, dy + dh) }
                              : new PointF[] { new PointF(dx, dy), new PointF(dx + dw, dy), new PointF(dx, dy + dh) };
            InterpolationMode im = g.InterpolationMode; PixelOffsetMode pom = g.PixelOffsetMode;
            g.InterpolationMode = s.Pixel ? InterpolationMode.NearestNeighbor : InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = s.Pixel ? PixelOffsetMode.Half : PixelOffsetMode.HighQuality;
            RectangleF src = new RectangleF(0, 0, cw, ch);
            if (halo.A > 0)
            {
                ImageAttributes hia;
                int key = halo.ToArgb();
                if (!haloIa.TryGetValue(key, out hia))
                {
                    ColorMatrix cm = new ColorMatrix(new float[][] {
                        new float[] { 0, 0, 0, 0, 0 }, new float[] { 0, 0, 0, 0, 0 }, new float[] { 0, 0, 0, 0, 0 },
                        new float[] { 0, 0, 0, 1, 0 }, new float[] { halo.R / 255f, halo.G / 255f, halo.B / 255f, 0, 1 } });
                    hia = new ImageAttributes(); hia.SetColorMatrix(cm);
                    if (haloIa.Count > 16) haloIa.Clear();
                    haloIa[key] = hia;
                }
                float hw = Math.Max(1, ps / 3);
                for (int oy = -1; oy <= 1; oy++)
                    for (int ox = -1; ox <= 1; ox++)
                    {
                        if (ox == 0 && oy == 0) continue;
                        PointF[] q = { new PointF(pts[0].X + ox * hw, pts[0].Y + oy * hw), new PointF(pts[1].X + ox * hw, pts[1].Y + oy * hw), new PointF(pts[2].X + ox * hw, pts[2].Y + oy * hw) };
                        g.DrawImage(canvas, q, src, GraphicsUnit.Pixel, hia);
                    }
            }
            ImageAttributes ia = null;
            if (night)
            {
                if (nightIa == null)
                {
                    ColorMatrix nm = new ColorMatrix(new float[][] {
                        new float[] { 0.58f, 0, 0, 0, 0 }, new float[] { 0, 0.6f, 0, 0, 0 }, new float[] { 0, 0, 0.78f, 0, 0 },
                        new float[] { 0, 0, 0, 1, 0 }, new float[] { 0.02f, 0.02f, 0.07f, 0, 1 } });
                    nightIa = new ImageAttributes(); nightIa.SetColorMatrix(nm);
                }
                ia = nightIa;
            }
            if (alpha < 0.999f)
            {
                ColorMatrix am = new ColorMatrix(); am.Matrix33 = alpha;
                if (night) { am.Matrix00 = 0.58f; am.Matrix11 = 0.6f; am.Matrix22 = 0.78f; }
                ImageAttributes aia = new ImageAttributes(); aia.SetColorMatrix(am);
                g.DrawImage(canvas, pts, src, GraphicsUnit.Pixel, aia);
                aia.Dispose();
            }
            else if (ia != null) g.DrawImage(canvas, pts, src, GraphicsUnit.Pixel, ia);
            else g.DrawImage(canvas, pts, src, GraphicsUnit.Pixel);
            g.InterpolationMode = im; g.PixelOffsetMode = pom;
        }

        // 組裝：整隻的位移／旋轉／縮放 → 腳 → 身體 → 頭
        static void CuCompose(Graphics cg, CuSprite s, CuPose p, int ox, int oy, Matrix baseM)
        {
            cg.InterpolationMode = s.Pixel ? InterpolationMode.NearestNeighbor : InterpolationMode.HighQualityBicubic;
            cg.PixelOffsetMode = s.Pixel ? PixelOffsetMode.Half : PixelOffsetMode.HighQuality;
            cg.CompositingQuality = CompositingQuality.HighQuality;
            double R = s.R;
            Func<double, float> q = delegate(double v) { return s.Pixel ? (float)Math.Round(v * R) : (float)(v * R); };
            if (s.Pixel)
            {
                // 像素風：小角度的轉動會讓格子歪掉（看起來不像內建公仔），改成一格一格的位移
                if (Math.Abs(p.HeadRot) < 8) { p.HeadY -= Math.Abs(p.HeadRot) / 8 * 0.6; p.HeadX += p.HeadRot / 8 * 0.5; p.HeadRot = 0; }
                if (Math.Abs(p.BodyRot) < 8) { p.UpY -= Math.Abs(p.BodyRot) / 8 * 0.4; p.BodyRot = 0; }
                if (Math.Abs(p.Rot) < 4 && p.Rot90 == 0) { p.X += p.Rot / 4 * 0.5; p.Rot = 0; }
            }
            using (Matrix m = baseM == null ? new Matrix() : baseM.Clone())
            {
                m.Translate(ox + q(p.X), oy + q(p.Y));
                float ay = (float)s.AY;
                if (p.Rot90 != 0) { m.Translate(0, -ay / 2f); m.Rotate(90 * p.Rot90); m.Translate(0, ay / 2f); }
                if (Math.Abs(p.Rot) > 0.01) { float pv = (float)(-ay * p.PivotY); m.Translate(0, pv); m.Rotate((float)p.Rot); m.Translate(0, -pv); }
                if (Math.Abs(p.Sx - 1) > 0.001 || Math.Abs(p.Sy - 1) > 0.001) m.Scale((float)p.Sx, (float)p.Sy);
                float L = s.AnchorX >= 0 ? (float)-s.AnchorX : -(s.W / 2), T = -ay;
                Bitmap fr;
                if (p.Frame != null && s.Frames.TryGetValue(p.Frame, out fr)) { if (s.Liquid != null) { Bitmap lq = SqBattery.Frame(s, p.Frame); if (lq != null) fr = lq; } CuPut(cg, m, fr, L, T, 0, 0, 0, 0, 0); return; }
                if (!s.Rig) { Bitmap st = s.Stand; if (s.Liquid != null) { Bitmap lq = SqBattery.Frame(s, "stand"); if (lq != null) st = lq; } CuPut(cg, m, st, L, T, 0, 0, 0, 0, 0); return; }
                // 腳（踩在地上；抬腳往上、轉繞腳的最上面）
                if (!p.NoLegs)
                {
                    float lcx = L + s.Split / 2f, rcx = L + s.Split + (s.W - s.Split) / 2f, top = T + s.Hip;
                    CuPut(cg, m, s.LegL, L, top, q(p.LX), q(p.LY), (float)p.LRot, lcx, top);
                    CuPut(cg, m, s.LegR, L + s.Split, top, q(p.RX), q(p.RY), (float)p.RRot, rcx, top);
                }
                // 身體：繞屁股那條線伸縮、搖
                float hipY = T + s.Hip, up = q(p.UpY);
                using (Matrix mb = m.Clone())
                {
                    mb.Translate(0, up);
                    mb.Translate(L + s.NeckCx, hipY);
                    if (Math.Abs(p.BodyRot) > 0.01) mb.Rotate((float)p.BodyRot);
                    if (Math.Abs(p.BodySy - 1) > 0.001) mb.Scale(1, (float)p.BodySy);
                    mb.Translate(-(L + s.NeckCx), -hipY);
                    CuPut(cg, mb, s.Body, L, T + s.BodyY0, 0, 0, 0, 0, 0);
                    // 頭：跟著身體頂端；繞脖子轉
                    float neckY = T + s.Neck;
                    CuPut(cg, mb, s.Head, L, T, q(p.HeadX), q(p.HeadY), (float)p.HeadRot, L + s.HeadCx, neckY);
                }
            }
        }

        // 放一張零件：先位移 (dx,dy)，再繞 (px,py) 轉 rot 度
        static void CuPut(Graphics cg, Matrix baseM, Bitmap img, float x, float y, float dx, float dy, float rot, float px, float py)
        {
            if (img == null) return;
            using (Matrix m = baseM.Clone())
            {
                m.Translate(dx, dy);
                if (Math.Abs(rot) > 0.01) { m.Translate(px, py); m.Rotate(rot); m.Translate(-px, -py); }
                cg.Transform = m;
                cg.DrawImage(img, new RectangleF(x, y, img.Width, img.Height), new RectangleF(0, 0, img.Width, img.Height), GraphicsUnit.Pixel);
            }
            cg.ResetTransform();
        }

        // 像素風：組完之後半透明的一律變成全有或全無（才會一格一格）
        static void CuThreshold(Bitmap b)
        {
            int[] px = CuImg.Pixels(b);
            bool ch = false;
            for (int i = 0; i < px.Length; i++)
            {
                int a = (px[i] >> 24) & 255;
                if (a == 0 || a == 255) continue;
                px[i] = a < 128 ? 0 : (px[i] | unchecked((int)0xFF000000));
                ch = true;
            }
            if (!ch) return;
            BitmapData d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            try { for (int y = 0; y < b.Height; y++) System.Runtime.InteropServices.Marshal.Copy(px, y * b.Width, new IntPtr(d.Scan0.ToInt64() + (long)y * d.Stride), b.Width); }
            finally { b.UnlockBits(d); }
        }

        // 不用 Pet 的地方（設定視窗、VS Code 小圖、分享短片的預覽）：站好的樣子
        public static void CuDrawStill(Graphics g, CuSprite s, double feetX, double feetY, int ps, bool fx, bool night, Color halo)
        {
            int mb, cw, ch;
            CuCanvasSize(s, out cw, out ch, out mb);
            using (Bitmap c = new Bitmap(cw, ch, s.Pixel ? PixelFormat.Format32bppArgb : PixelFormat.Format32bppPArgb))
            {
                using (Graphics cg = Graphics.FromImage(c)) { cg.Clear(Color.Transparent); CuPose p = new CuPose(); CuCompose(cg, s, p, cw / 2, ch - mb, null); }
                CuBlit(g, c, s, feetX, feetY, cw, ch, mb, ps, fx, s.NoHalo ? Color.Transparent : halo, night, 1f);
            }
        }

        // ---------- 配件：帽子戴在頭頂（頭太小／太歪就不戴）、圍巾圍在脖子那條線、節日的紅包蛋糕放旁邊 ----------
        void CuAccessories(Graphics g, CuPose p, int sbx, int sby, int ps, bool fx, bool sides)
        {
            CuSprite s = P.Spr;
            if (s.NoHalo) return;   // 續命小隊：不戴帽子圍巾
            int lv = Level();
            double hc = s.Hc;
            double sy = p.Sy;
            double top = 16 - hc * sy + p.Y + (s.Rig ? p.UpY + p.HeadY : 0);
            double headTop = top + s.HeadTop / (double)s.R * sy;
            double headCol = 6 + (s.HeadCx - s.W / 2.0) / s.R + p.X + (s.Rig ? p.HeadX : 0);
            double headW = s.HeadW / (double)s.R;
            if (lv >= 2 && s.Rig && p.Frame == null)
            {
                double nw = s.NeckW / (double)s.R;
                if (nw >= 4 && nw <= 12)
                {
                    double neckRow = top + s.Neck / (double)s.R * sy - (s.Rig ? p.HeadY : 0) - 0.5;
                    DrawAt(g, SCARF, 6 + (s.NeckCx - s.W / 2.0) / s.R + p.X - 6, neckRow, sbx, sby, ps, fx, false, false);
                }
            }
            string[] hat = w.SeasonNow == "xmas" && w.Feat("season") ? SANTA : (lv >= 6 ? CROWN : (lv >= 3 ? BEANIE : null));
            if (hat != null && headW >= 5 && headW <= 18) DrawAt(g, hat, headCol - 6, headTop - hat.Length + 1, sbx, sby, ps, fx, false, true);
            if (!sides) return;
            double side = 6 + s.Wc / 2 + 0.2, mid = 16 - hc * 0.5;
            if (w.SeasonNow == "cny") DrawAt(g, ENVELOPE, side, mid, sbx, sby, ps, fx, false, true);
            if (w.SeasonNow == "birthday") DrawAt(g, CAKE, side, mid - 1, sbx, sby, ps, fx, false, true);
        }

        // ---------- 午餐：手上拿便當（睡午覺時擺旁邊的空盤子） ----------
        void CuLunch(Graphics g, Fr f, int bx, int by, int ps, bool fx, int bite)
        {
            CuSprite s = P.Spr;
            double row = 16 - s.Hc + (s.Rig ? (s.Neck + s.Hip) / 2.0 : s.H * 0.55) / s.R - 2 + cuPose.Y + cuPose.UpY;
            DrawAt(g, BENTO, 6 + s.Wc / 2 - 2.5 + cuPose.X, row + bite, bx, by, ps, fx, false, true);
        }

        void CuLunchShelf(Graphics g, int bx, int by, int ps, bool flip)
        {
            CuSprite s = P.Spr;
            double row = 16 - s.Hc + (s.Rig ? (s.Neck + s.Hip) / 2.0 : s.H * 0.55) / s.R - 2;
            DrawAt(g, BENTO, 6 + s.Wc / 2 - 2.5, row, bx, by, ps, flip, false, true);
        }

        string CuLunchLine(string phase)
        {
            if (phase == "start") return L("x_lunch_start");
            if (phase == "nap") return L("x_lunch_nap");
            if (phase == "end") return L("x_lunch_end");
            return L("x_lunch_talk");
        }

        // ---------- 櫃子裡：輕輕呼吸、偶爾歪頭、換邊看；晚上睡（貓窩著） ----------
        void DrawCuShelf(Graphics g, int fx, int fy, int ps, Rectangle cell, double tt)
        {
            CuPose p = new CuPose();
            CuSprite s = P.Spr;
            double br = Math.Sin(tt * 1.9);
            p.BodySy = 1 + br * 0.03;
            if (!s.Rig) { p.Sy = 1 + br * 0.02; p.Sx = 1 - br * 0.01; }
            double tilt = (tt % 6.1) < 1.1 ? Math.Sin((tt % 6.1) / 1.1 * Math.PI) : 0;
            p.HeadRot = tilt * 8; if (!s.Rig) p.Rot = tilt * 3;
            if (Night)
            {
                double legH = (s.H - s.Hip) / (double)s.R;
                if (Persona == "cat" && s.Rig) { p.NoLegs = true; p.UpY = legH * 0.92; p.HeadY = 0.3; p.HeadRot = 4; }
                else { p.HeadRot = 10; p.HeadY = 0.3; if (!s.Rig) p.Rot = 5; }
                if (s.HasFrame("sleep")) { p.Frame = "sleep"; p.Rot = 0; }
            }
            bool flip = (Math.Floor(tt / 9) % 2) == 1;
            CuDraw(g, p, fx, fy, ps, flip);
            CuAccessories(g, p, fx - 6 * ps, fy - 16 * ps, ps, flip, false);
            if (w.Lunch) CuLunchShelf(g, fx - 6 * ps, fy - 16 * ps, ps, flip);
        }

        // 外出中的格子：淡淡的剪影
        void CuGhost(Graphics g, int fx, int fy, int ps, bool night) { CuGhostSc(g, fx, fy, ps / (float)P.Spr.R, night); }
        void CuGhostSc(Graphics g, int fx, int fy, float sc, bool night)
        {
            CuSprite s = P.Spr;
            int mb, cw, ch;
            CuCanvasSize(s, out cw, out ch, out mb);
            using (Bitmap c = new Bitmap(cw, ch, PixelFormat.Format32bppArgb))
            {
                using (Graphics cg = Graphics.FromImage(c)) { cg.Clear(Color.Transparent); CuCompose(cg, s, new CuPose(), cw / 2, ch - mb, null); }
                Color a = P.Accent;
                ColorMatrix cm = new ColorMatrix(new float[][] {
                    new float[] { 0, 0, 0, 0, 0 }, new float[] { 0, 0, 0, 0, 0 }, new float[] { 0, 0, 0, 0, 0 },
                    new float[] { 0, 0, 0, (night ? 34 : 42) / 255f, 0 }, new float[] { a.R / 255f, a.G / 255f, a.B / 255f, 0, 1 } });
                using (ImageAttributes ia = new ImageAttributes())
                {
                    ia.SetColorMatrix(cm);
                    InterpolationMode im = g.InterpolationMode;
                    g.InterpolationMode = s.Pixel ? InterpolationMode.NearestNeighbor : InterpolationMode.HighQualityBilinear;
                    g.DrawImage(c, new Rectangle((int)(fx - cw / 2.0 * sc), (int)(fy - (ch - mb) * sc), (int)(cw * sc), (int)(ch * sc)), 0, 0, cw, ch, GraphicsUnit.Pixel, ia);
                    g.InterpolationMode = im;
                }
            }
        }

        int CuShelfRows()
        {
            int hat = (w.SeasonNow == "xmas" || Level() >= 3) && P.Spr.HeadW / (double)P.Spr.R >= 5 ? 3 : 0;
            return (int)Math.Ceiling(P.Spr.Hc * 1.04) + hat + 1;
        }
    }

    // ================= 一隻自己做的公仔：個性和動作 =================
    partial class Pet
    {
        void CuDo(string act, double dur) { cuAct = act; cuT = 0; SetState("cu", dur); }

        // 每一格（StepSpecial 最前面）：落地壓扁、專屬動作
        bool CuStep(double dt)
        {
            if (cuLandT > 0) cuLandT -= dt;
            if (cuIgnoreCd > 0) cuIgnoreCd -= dt;
            if (cuPushCd > 0) cuPushCd -= dt;
            if (cuPrev == "air" && state != "air" && state != "drag") cuLandT = 0.2;
            cuPrev = state;
            if (state != "cu") return false;
            cuT += dt;
            Point cp = Cursor.Position;
            switch (cuAct)
            {
                case "pushwalk":
                    if (Math.Abs(cuX - Cx) > 4)
                    {
                        dir = cuX > Cx ? 1 : -1;
                        if (MoveOnGround(dt, P.Speed * k)) return true;
                        if ((dir > 0 && Cx > cuX) || (dir < 0 && Cx < cuX)) x = cuX - SW / 2.0;
                    }
                    else { dir = cuPushDir; CuDo("push", 1.5); }
                    if (t < 0) SetState("idle", 1);
                    return true;
                case "push":
                    if (cuT - dt < 0.55 && cuT >= 0.55) CuPushItem();
                    if (t < 0) { SetState("idle", R(1.5, 3)); }
                    return true;
                case "ignore":
                    if (t < 0) { CuDo("comeback", 4.5); }
                    return true;
                case "comeback":
                    {
                        double dx = cp.X - Cx;
                        if (Math.Abs(dx) < 14 * k || t < 0) { dir = dx >= 0 ? 1 : -1; Hug(L("x_comeback"), 2.6); return true; }
                        dir = dx > 0 ? 1 : -1;
                        MoveOnGround(dt, P.Speed * 1.3 * k);
                    }
                    return true;
                case "fetchback":
                    {
                        double dx = cp.X - Cx;
                        if (w.Holder != this) { SetState("idle", 1); return true; }
                        if (Math.Abs(dx) < 16 * k || t < 0)
                        {
                            w.ReleaseBall(Cx + dir * 7 * k, y + SH - 8 * k, dir * 30 * k, -60 * k);
                            Say(L("x_fetch_back"), 2.2); AddHeart();
                            CuDo("wag", 1.8);
                            return true;
                        }
                        dir = dx > 0 ? 1 : -1;
                        if (MoveOnGround(dt, 150 * k)) return true;
                    }
                    return true;
                case "zoom":
                    if (Math.Floor(cuT / 0.8) != Math.Floor((cuT - dt) / 0.8)) dir = -dir;
                    if (MoveOnGround(dt, 210 * k)) return true;
                    if (t < 0) { CuDo("wag", 1.4); Say(L("x_wag"), 1.6); }
                    return true;
                default:
                    if (cuAct == "wag" && rnd.NextDouble() < dt * 2) AddHeart();
                    if (t < 0 && !InScene) SetState("idle", R(1, 2));
                    return true;
            }
        }

        // 招牌動作（右鍵選單）
        void CuSignature()
        {
            if (!Grounded() && state != "cu") return;
            switch (Persona)
            {
                case "cool": CuDo("cool", 2.2); Say(L("x_sig"), 1.8); break;
                case "shy":
                    {
                        Pet o = w.Nearest(this);
                        if (o != null && Math.Abs(o.Cx - Cx) < 500 * k && Math.Abs(o.Foot - Foot) < 3) HideBehindPet(o); else CuDo("shy", 2.4);
                        Say(L("x_sig"), 1.8); Mark(4);
                    }
                    break;
                case "funny": Say(L("x_sig"), 1.6); rolling = true; dizzyOnLand = true; Jump(dir * 60 * k, -400 * k); break;
                case "cat": GoSleep(); t = R(8, 14); Say(L("x_loaf"), 1.8); break;
                case "dog": CuDo("zoom", 2.6); Say(L("x_sig"), 1.4); break;
                default:
                    Say(L("x_sig"), 1.4);
                    if (!JumpToPlatform()) Jump(dir * 90 * k, -460 * k);
                    afterLand = "cuhop"; break;
            }
        }

        bool CuAct(string a)
        {
            switch (a)
            {
                case "sit": if (Grounded()) { CuDo("sit", R(3, 5)); Say(L("x_sit"), 1.6); } return true;
                case "wag": if (Grounded()) { CuDo("wag", 2.2); Say(L("x_wag"), 1.6); } return true;
                case "loaf": if (Grounded()) { GoSleep(); t = R(8, 14); Say(L("x_loaf"), 1.8); } return true;
                case "push": if (!CuPushStart()) Say(L("x_ignore"), 1.6); return true;
                case "ignore": if (Grounded()) { CuDo("ignore", 2.5); Say(L("x_ignore"), 1.8); } return true;
            }
            return false;
        }

        // 連點三下
        void CuCombo()
        {
            Say(L("tickle"), 1.8);
            if (!Grounded() || state == "dizzy") return;
            switch (Persona)
            {
                case "cool": CuDo("cool", 1.6); break;
                case "shy": CuDo("shy", 2); Mark(4); break;
                case "funny": SetState("spin", 0.9); Jump(0, -320 * k); rolling = true; break;
                case "cat": CuDo("ignore", 2); break;
                case "dog": CuDo("wag", 2); break;
                default: Jump(dir * 40 * k, -360 * k); afterLand = "cuhop"; break;
            }
        }

        // 摸一下：喵系偶爾不理你（過一下又自己跑回來）
        bool CuPat()
        {
            if (Persona != "cat" || Night || !Grounded() || state == "dizzy" || state == "sleep" || cuIgnoreCd > 0 || rnd.NextDouble() > 0.3) return false;
            cuIgnoreCd = 60;
            dir = Cursor.Position.X > Cx ? -1 : 1;
            CuDo("ignore", R(2.2, 3.4));
            Say(L("x_ignore"), 2.0);
            return true;
        }

        // 從閒置回來：汪系開心地跳兩下
        bool CuWelcome()
        {
            if (Persona != "dog" || !Grounded()) return false;
            Jump(0, -380 * k); afterLand = "cuhop";
            Say(L("x_return"), 3); AddHeart(); AddHeart();
            return true;
        }

        bool CuLand(string a)
        {
            if (a == "cuhop") { Jump(dir * 20 * k, -260 * k); AddHeart(); return true; }
            if (a == "cufetch") { if (w.Holder == this) CuDo("fetchback", 5); else SetState("idle", 1); return true; }
            return false;
        }

        // 球碰到他：汪系叼回來給你；喵系撥一下；其他人踢回去
        void CuBall()
        {
            if (Persona == "dog")
            {
                // 叼住；在空中接到的話落地再叼回來
                w.HoldBall(this);
                if (Grounded()) CuDo("fetchback", 5); else afterLand = "cufetch";
                Say(L("ball_catch"), 1.6);
                return;
            }
            Say(L("ball_catch"), 1.8);
            KickBallToCursor(Persona == "cat" ? 0.6 : 1.0);
            if (Grounded()) SetState("kick", 0.5);
        }

        // 出錯了：害羞的躲起來、喵系不理、汪系跳起來、搞笑的轉暈
        void CuReact(string why)
        {
            if (why != "errors") return;
            switch (Persona)
            {
                case "shy": { Pet o = w.Nearest(this); if (o != null) HideBehindPet(o); else CuDo("shy", 2.6); Mark(4); } break;
                case "cat": CuDo("ignore", 2.4); break;
                case "funny": SetState("dizzy", 1.6); break;
                case "cool": CuDo("cool", 2); break;
                default: Jump(0, -340 * k); Mark(1); break;
            }
        }

        // 走到視窗邊：喵系常常坐在邊邊，偶爾把東西推下去
        int CuEdge(bool right)
        {
            switch (Persona)
            {
                case "cat":
                    if (rnd.NextDouble() < 0.25 && cuPushCd <= 0) { cuPushDir = right ? 1 : -1; dir = cuPushDir; CuDo("push", 1.5); return 2; }
                    if (rnd.NextDouble() < 0.7) { dir = -dir; SetState("idle", R(2, 5)); return 2; }
                    return 0;
                case "shy": if (rnd.NextDouble() < 0.75) { dir = -dir; return 1; } return 0;
                case "cool": if (rnd.NextDouble() < 0.5) { dir = -dir; return 1; } return 0;
                case "dog": if (rnd.NextDouble() < 0.3) { dir = -dir; return 1; } return 0;
            }
            if (rnd.NextDouble() < 0.4) { dir = -dir; return 1; }
            return 0;
        }

        // 喵系：走到視窗邊，把一個小杯子推下去
        int cuPushDir = 1; double cuPushCd;
        bool CuPushStart()
        {
            if (supH == IntPtr.Zero || !Grounded()) return false;
            bool right = (supR - Cx) < (Cx - supL) ? true : (rnd.NextDouble() < 0.5);
            cuPushDir = right ? 1 : -1;
            cuX = right ? supR - SW * 0.15 : supL + SW * 0.15;
            if (cuX < supL + SW * 0.3 && cuX > supR - SW * 0.3) return false;
            CuDo("pushwalk", 8);
            return true;
        }

        void CuPushItem()
        {
            cuPushCd = 90;
            double ex = cuPushDir > 0 ? Math.Max(Cx + SW * 0.4, supR + 6 * k) : Math.Min(Cx - SW * 0.4, supL - 6 * k);
            Rectangle wa = w.WA(ex, y + SH);
            PointF from = new PointF((float)(Cx + cuPushDir * SW * 0.45), (float)(Foot - 3 * S));
            PointF to = new PointF((float)(ex + cuPushDir * 30 * k), (float)(wa.Bottom - 3 * S));
            w.CuToss(MUG, P, from, to);
            Say(L("x_push"), 2.4);
        }

        void CuDecide(double r, Rectangle wa)
        {
            string ps = Persona;
            if (ps == "cat")
            {
                if (supH != IntPtr.Zero)
                {
                    // 在視窗上：坐著看風景、窩著睡、偶爾推東西
                    if (r < .32) { SetState("idle", R(4, 9)); return; }
                    if (r < .46) { GoSleep(); t = R(10, 20); if (rnd.NextDouble() < 0.4) Say(L("x_loaf"), 1.8); return; }
                    if (r < .56 && cuPushCd <= 0 && CuPushStart()) return;
                }
                else if (r < .28 && JumpToPlatform()) return;
            }
            if (ps == "dog" && r < .12) { CuDo("wag", R(1.4, 2.4)); if (rnd.NextDouble() < 0.4) Say(L("x_wag"), 1.4); return; }
            if (ps == "dog" && r < .17) { CuDo("zoom", R(1.8, 3)); return; }
            if (ps == "shy" && r < .10) { CuDo("shy", R(2, 3.5)); return; }
            double r2 = rnd.NextDouble();
            double idle = ps == "cool" || ps == "shy" || ps == "cat" ? .30 : (ps == "dog" ? .10 : .15);
            double hop = ps == "lively" ? .24 : (ps == "funny" ? .16 : (ps == "cool" || ps == "shy" ? .08 : .14));
            double sig = ps == "funny" || ps == "lively" ? .08 : .05;
            double c = idle;
            if (r2 < c) { SetState("idle", R(1.5, 4.5)); return; }
            if (r2 < (c += hop)) { if (!JumpToPlatform()) Hop(); return; }
            if (r2 < (c += sig)) { CuSignature(); return; }
            if (r2 < (c += .05)) { Hug(L("hugs"), 2.2); return; }
            if (r2 < (c += Night ? .05 : .03)) { Knock(L("knock"), "ambient"); return; }
            if (r2 < (c += .04) && lateCd <= 0 && LateLine() != null) { LateTick(); return; }
            if (r2 < (c += .03) && SeasonLine() != null) { Say(SeasonLine(), 3); SetState("idle", 3); return; }
            if (r2 < (c += .08)) { SetState("idle", 2.5); Say(L("talk"), 2.4); return; }
            dir = rnd.NextDouble() < .5 ? -1 : 1; SetState("walk", R(3, 6));
        }

        // 測試用：直接叫某個專屬動作
        public void CuTest(string a)
        {
            switch (a)
            {
                case "jumpwin": JumpToPlatform(); break;
                case "push": if (!CuPushStart()) Say("（不在視窗上）", 1); break;
                case "ignore": CuDo("ignore", 2.5); Say(L("x_ignore"), 2); break;
                case "return": CuWelcome(); break;
                case "loaf": GoSleep(); t = 12; break;
                default: CuAct(a); break;
            }
        }

        // 右鍵選單「一起玩」
        public string[][] CuMenuItems()
        {
            string sig;
            switch (Persona)
            {
                case "cool": sig = "耍帥一下"; break;
                case "shy": sig = "躲起來偷看"; break;
                case "funny": sig = "表演翻跟斗"; break;
                case "cat": sig = "窩成貓貓窩"; break;
                case "dog": sig = "暴衝跑一圈"; break;
                default: sig = "蹦蹦跳"; break;
            }
            List<string[]> l = new List<string[]>();
            l.Add(new string[] { "抱抱 ♥", "hug" }); l.Add(new string[] { "打招呼", "hi" }); l.Add(new string[] { "敲敲螢幕", "knock" });
            l.Add(new string[] { sig, "sig" });
            if (Persona == "dog") l.Add(new string[] { "搖尾巴", "wag" });
            if (Persona == "cat") l.Add(new string[] { "把東西推下去", "push" });
            l.Add(new string[] { "跳到別的視窗上", "jump" }); l.Add(new string[] { "坐下", "sit" }); l.Add(new string[] { "睡覺", "sleep" });
            l.Add(new string[] { Persona == "dog" ? "丟球給他（會撿回來）" : "丟球給他", "ball" });
            return l.ToArray();
        }
    }

    // ================= World：我的櫃、選單、pipe 指令、重新載入 =================
    partial class World
    {
        public bool CuLineup { get { return lineup == Pal.Mine; } }

        // 小道具（喵系推下去的杯子）
        public void CuToss(string[] art, Pal owner, PointF a, PointF b) { Toss(art, owner, a, b, 0.75, 14 * k, true, 1.6, null); }

        // 串場：自己做的公仔 × 任何一隻（打招呼抱抱、聊天、傳球）
        void CuPairScene(string key, Pet a, Pet b)
        {
            if (a == null || b == null) return;
            if (!a.P.Cu && b.P.Cu) { Pet t = a; a = b; b = t; }
            if (!a.P.Cu) return;
            int pick = rnd.Next(3);
            Begin(a, b);
            string on = b.P.Name;
            if (pick == 0)
            {
                At(0, delegate { Face(a, b); a.ScenePose("idle", 8); b.ScenePose("idle", 8); a.Say(a.L("x_pair_hi", "o", on), 2.2); });
                At(2.3, delegate { b.ScenePose("wave", 1.4); b.Say(b.P.Cu ? b.L("x_pair_hi", "o", a.P.Name) : b.L("hi"), 2.2); });
                At(4.8, delegate { Face(a, b); a.ScenePose("hug", 2.4); b.ScenePose("hug", 2.4); a.Say(a.L("hugs"), 2.2); });
                At(7.6, delegate { });
            }
            else if (pick == 1)
            {
                At(0, delegate { Face(a, b); a.ScenePose("idle", 10); b.ScenePose("idle", 10); a.Say(a.L("x_pair_ask", "o", on), 2.4); });
                At(2.6, delegate { b.ScenePose("hop", 0); b.Say(b.L("talk"), 2.4); });
                At(5.2, delegate { a.ScenePose("dance", 1.6); a.Say(a.L("x_pair_react", "o", on), 2.2); });
                At(7.6, delegate { a.Say(a.L("x_pair_bye", "o", on), 1.8); });
                At(9.6, delegate { });
            }
            else
            {
                string[] ball = { ".yy.", "yyyy", "yyyy", ".yy." };
                At(0, delegate { Face(a, b); a.ScenePose("idle", 12); b.ScenePose("idle", 12); a.Say(a.L("x_pair_ball", "o", on), 2); });
                double tt = 1.6;
                for (int i = 0; i < 4; i++)
                {
                    Pet from = i % 2 == 0 ? a : b, to = i % 2 == 0 ? b : a;
                    At(tt, delegate { from.ScenePose("kick", 0.4); Toss(ball, a.P, from.HandPoint(), to.HandPoint(), 0.7, 40 * k, true, 0, delegate { to.ScenePose("hop", 0); }); });
                    tt += 1.1;
                }
                At(tt + 0.4, delegate { Face(a, b); b.Say(b.P.Cu ? b.L("x_pair_ball_end", "o", a.P.Name) : b.L("ball_catch"), 2); a.ScenePose("hug", 2); a.Say(a.L("x_pair_ball_end", "o", on), 2); });
                At(tt + 3, delegate { });
            }
        }

        // 通知、提醒、搶票：自己做的公仔用自己個性的開場白
        static string CuFlavor(string id, string kind, bool night)
        {
            Pal p = Pal.Get(id);
            if (p == null || !p.Cu) return null;
            string[] a;
            if (night && p.Lines.TryGetValue("x_" + kind + "_d", out a) && a.Length > 0) return a[new Random().Next(a.Length)];
            if (p.Lines.TryGetValue("x_" + kind, out a) && a.Length > 0) return a[new Random().Next(a.Length)];
            return null;
        }

        // 讀書小幫手：自己做的公仔用自己個性的句子（DeskPals.Study.cs 的 ExamPrefix／ExamTail／LateNightLine／CourseLine 會先問這裡）
        static string CuStudy(string id, string key, string hm, string t, string h)
        {
            Pal p = Pal.Get(id);
            string[] a;
            if (p == null || !p.Cu || !p.Lines.TryGetValue(key, out a) || a.Length == 0) return null;
            return a[new Random().Next(a.Length)].Replace("{hm}", hm ?? "").Replace("{t}", t ?? "").Replace("{h}", h ?? "");
        }

        static string CuTicket(string id, int stage, string n, string h)
        {
            Pal p = Pal.Get(id);
            string[] a;
            if (p == null || !p.Cu || !p.Lines.TryGetValue("x_ticket" + stage, out a) || a.Length == 0) return null;
            return a[new Random().Next(a.Length)].Replace("{t}", n).Replace("{h}", h);
        }

        // ---------- 重新載入（新做／改過／刪掉一隻之後） ----------
        public void CuReload(string pet)
        {
            CuStore.Reset(false);
            if (lineup == Pal.Mine && !Pal.HasCustom()) { SwitchLineup(Pal.Fallback, ""); return; }
            if (lineup != Pal.Mine && !OrigLineup) return;   // 續命小隊的第 4 格也放自己的公仔：一起重建
            // 跟 SwitchLineup 一樣，只是同一櫃也要重建（公仔的資料換了）
            AbortScene();
            ClearProps();
            if (BallOn) { BallOn = false; Holder = null; if (ballF != null) ballF.Hide(); }
            SaveUsage(); SaveOut();
            List<string> outIds = new List<string>();
            foreach (Pet p in outOrder) if (p.Out) outIds.Add(p.P.Id);
            current = null;
            foreach (Pet p in Pets) { p.Out = false; p.CloseForms(); }
            Pets.Clear(); outOrder.Clear(); active = null; lastBroadcast = "";
            defaultPet = DefaultPetFor(pet);
            int seed = Environment.TickCount;
            foreach (Pal p in Pal.Lineup(lineup)) if (p != null) Pets.Add(new Pet(this, p, S, seed++));
            RenderShelf();
            if (Get(pet) != null && !outIds.Contains(pet)) outIds.Add(pet);
            if (Single) outIds.RemoveAll(delegate(string x) { return x != SinglePet(); });
            double delay = 0.3;
            foreach (string oid in outIds)
            {
                Pet pp = Get(oid);
                if (pp == null) continue;
                Later(delay, delegate { BringOut(pp, oid == pet); });
                delay += 0.45;
            }
            active = Get(pet) ?? Get(defaultPet);
            Broadcast();
            CuBroadcast();
        }

        // 新做好一隻（或改好）：住進我的櫃、叫他出來
        public void CuCreated(string id, bool first, bool edit)
        {
            CuStore.Reset(false);
            List<string> mine = new List<string>(Pal.MineIds());
            if (!mine.Contains(id))
            {
                if (mine.Count >= 4)
                {
                    // 滿了：換掉一隻作客的（沒有就換掉最後一隻）
                    int gi = -1;
                    for (int i = mine.Count - 1; i >= 0; i--) if (CuStore.Get(mine[i]) == null) { gi = i; break; }
                    mine.RemoveAt(gi >= 0 ? gi : mine.Count - 1);
                }
                mine.Insert(0, id);
                Pal.SaveMine(mine);
            }
            CuBroadcast();   // 先讓 VS Code 知道有「我的櫃」，等一下換櫃的通知它才認得
            if (first || Single)
            {
                ApplySetup(Pal.Mine, true, id, first);
                if (lineup == Pal.Mine) CuReload(id);
            }
            else if (lineup != Pal.Mine) SwitchLineup(Pal.Mine, id);
            else CuReload(id);
            Pet p = Get(id);
            if (p != null && !edit) Later(1.4, delegate { if (p.Out) p.Say(p.L("hi"), 3); });
            CuBroadcast();
        }

        public void CuDeleted(string id)
        {
            if (Single && singleId == id) { singleId = ""; WriteText("mode.txt", "single "); }
            List<string> mine = new List<string>(Pal.MineIds()); mine.Remove(id); Pal.SaveMine(mine);
            if (lineup == Pal.Mine || OrigLineup) { Pet l = Lead(); CuReload(l != null && l.P.Id != id ? l.P.Id : ""); }
            else CuStore.Reset(false);
            CuBroadcast();
        }

        // ---------- 小屋「我的公仔」子選單：做一隻自己的公仔、我的公仔（編輯／匯出／刪除）、我的櫃放誰、匯入、分享短片 ----------
        void CuHouseMenu(ToolStripItemCollection items)
        {
            items.Add("做一隻自己的公仔（貓狗照片也可以）…", null, delegate { CuOpenMaker(null, false); });
            List<CuMeta> cus = CuStore.All();
            if (cus.Count > 0)
            {
                ToolStripMenuItem my = new ToolStripMenuItem("我的公仔");
                foreach (CuMeta cm in cus)
                {
                    CuMeta mm = cm;
                    ToolStripMenuItem it = new ToolStripMenuItem(mm.Name);
                    it.DropDownItems.Add("叫他出來", null, delegate { CuCallOut(mm.Id); });
                    it.DropDownItems.Add("修改（去背、動作、個性）…", null, delegate { CuOpenMaker(mm.Id, false); });
                    it.DropDownItems.Add("匯出成檔案（傳給朋友）…", null, delegate { CuExportDialog(mm.Id); });
                    ToolStripMenuItem del = new ToolStripMenuItem("刪除…");
                    del.DropDownItems.Add("確定刪除「" + mm.Name + "」（不能復原）", null, delegate { CuDelete(mm.Id); });
                    it.DropDownItems.Add(del);
                    my.DropDownItems.Add(it);
                }
                items.Add(my);
                ToolStripMenuItem room = new ToolStripMenuItem("我的櫃要放誰（最多 4 隻）");
                List<string> mine = new List<string>(Pal.MineIds());
                foreach (CuMeta cm in cus) CuMineItem(room, cm.Id, cm.Name, mine);
                ToolStripMenuItem guests = new ToolStripMenuItem("請內建公仔來作客");
                foreach (string gid in Pal.Guests) { Pal gp = Pal.Get(gid); if (gp != null) CuMineItem(guests, gid, gp.Name, mine); }
                room.DropDownItems.Add(guests);
                items.Add(room);
            }
            items.Add("匯入朋友的公仔（.deskpal）…", null, delegate { CuImportDialog(false); });
            items.Add("做分享短片（GIF）…", null, delegate { ShareClip(null); });
        }

        void CuMineItem(ToolStripMenuItem parent, string id, string name, List<string> mine)
        {
            ToolStripMenuItem it = new ToolStripMenuItem(name);
            it.CheckOnClick = true;
            it.Checked = mine.Contains(id);
            it.Click += delegate { CuToggleMine(id); it.Checked = new List<string>(Pal.MineIds()).Contains(id); };
            parent.DropDownItems.Add(it);
        }

        void CuToggleMine(string id)
        {
            List<string> mine = new List<string>(Pal.MineIds());
            Pet l = Lead();
            if (mine.Contains(id))
            {
                int cus = 0; foreach (string x in mine) if (CuStore.Get(x) != null) cus++;
                if (cus <= 1 && CuStore.Get(id) != null) { l.Say("我的櫃至少要有一隻自己做的公仔喔", 2.4); return; }
                mine.Remove(id);
            }
            else
            {
                if (mine.Count >= 4) { l.Say("我的櫃只有 4 格，先拿掉一隻再放", 2.4); return; }
                mine.Add(id);
            }
            Pal.SaveMine(mine);
            if (lineup == Pal.Mine) CuReload(l != null && mine.Contains(l.P.Id) ? l.P.Id : "");
        }

        void CuCallOut(string id)
        {
            List<string> mine = new List<string>(Pal.MineIds());
            if (!mine.Contains(id)) { if (mine.Count >= 4) mine.RemoveAt(mine.Count - 1); mine.Insert(0, id); Pal.SaveMine(mine); }
            if (Single) { singleId = id; WriteText("mode.txt", "single " + id); }
            if (lineup != Pal.Mine) SwitchLineup(Pal.Mine, id);
            else { CuReload(id); }
        }

        void CuDelete(string id)
        {
            CuMeta m = CuStore.Get(id);
            if (m == null) return;
            CuStore.Delete(id);
            CuDeleted(id);
            Lead().Say("「" + m.Name + "」刪掉了。想他的話可以再做一隻 🧸", 2.8);
        }

        // 右鍵選單：分享短片；自己做的公仔可以直接修改
        void CuPetMenu(Pet p, ContextMenuStrip m)
        {
            m.Items.Add("做分享短片（GIF）…", null, delegate { ShareClip(p); });
            if (p.P.Cu) m.Items.Add("修改 " + p.P.Name + "（去背、動作、個性）…", null, delegate { CuOpenMaker(p.P.Id, false); });
        }

        // ---------- 跟 VS Code 說：自己做的公仔有誰（名字、狀態列圖示、側邊欄小圖） ----------
        string CuPalsJson()
        {
            List<object> l = new List<object>();
            foreach (CuMeta m in CuStore.All())
            {
                Dictionary<string, object> d = new Dictionary<string, object>();
                d["id"] = m.Id; d["name"] = m.Name; d["emoji"] = Pal.PersonaEmoji(m.Persona);
                string ic = Path.Combine(CuStore.Dir(m.Id), "icon.png");
                d["img"] = File.Exists(ic) ? ic : "";
                // 側邊欄的小公仔要講的話（跟桌面上同一套個性）
                Pal p = Pal.Get(m.Id);
                if (p != null)
                {
                    Dictionary<string, object> lines = new Dictionary<string, object>();
                    foreach (string k in new string[] { "hi", "hi_d", "save", "save_d", "pats", "pats_d", "tickle", "errors", "errors_d", "errors_ok", "errors_ok_d", "rest", "rest_d", "wake", "wake_d", "sleep", "night_on", "night_off", "x_sig" })
                    { string[] a; if (p.Lines.TryGetValue(k, out a)) lines[k] = a; }
                    d["lines"] = lines;
                }
                l.Add(d);
            }
            Dictionary<string, object> o = new Dictionary<string, object>();
            o["pals"] = l; o["mine"] = Pal.MineIds();
            return new JavaScriptSerializer().Serialize(o);
        }
        // ---------- 測試用：離屏隔離模式下放一個假視窗（喵系坐視窗、推東西要用） ----------
        readonly IntPtr cuFakeH = new IntPtr(0x7FFF0F01);
        Rectangle cuFakeR = Rectangle.Empty;
        public bool CuFake(IntPtr h) { return App.Isolated && h == cuFakeH; }
        void CuFakeWins(List<WinInfo> nw, Dictionary<IntPtr, WinInfo> nc, List<Plat> np)
        {
            if (!App.Isolated || cuFakeR.IsEmpty) return;
            WinInfo wi = new WinInfo(); wi.H = cuFakeH; wi.L = cuFakeR.Left; wi.T = cuFakeR.Top; wi.R = cuFakeR.Right; wi.B = cuFakeR.Bottom; wi.Z = nw.Count;
            nw.Add(wi); nc[cuFakeH] = wi;
            Plat p = new Plat(); p.H = cuFakeH; p.Top = wi.T; p.Left = wi.L + 4; p.Right = wi.R - 4; p.WinLeft = wi.L; np.Add(p);
        }
        public void CuSetFakeWin(Rectangle r) { cuFakeR = App.Isolated ? r : Rectangle.Empty; }

        void CuHello(Client c) { Send(c, "pals " + CuPalsJson() + "\n"); }
        public void CuBroadcast() { string s = "pals " + CuPalsJson() + "\n"; lock (clients) foreach (Client c in clients) Send(c, s); }
    }
}
