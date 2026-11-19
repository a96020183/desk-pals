// WoWo Pals：像素介面的字（小屋選單、設定視窗、做公仔、搗蛋說明、泡泡、分享短片）一律用這裡畫。
// 為什麼不用 TextRenderer（GDI）：正黑體粗體 10～11pt 這種小字，GDI 會用字型裡內嵌的點陣字，筆畫擠成一團（開了 ClearType、遠端桌面、截圖都一樣）。
// 這裡改用 GDI+ 反鋸齒（AntiAliasGridFit）畫外框字：
//   * 字型換成整數像素大小（點數 × 螢幕 DPI ÷ 72，四捨五入），量跟畫用同一個字型、同一個 StringFormat，所以量出來多寬就畫多寬；
//   * 每一行的起點對齊整數像素，筆畫才不會糊；
//   * GDI+ 畫不出 BMP 以外的 emoji（🍅 👍 會變方框）：那幾個字（代理字組、變體選擇符、ZWJ）改用 TextRenderer 跟 Segoe UI Emoji 畫，寬度也照它量。
// 用法跟 TextRenderer 一樣：PixText.DrawText(g, 字, 字型, 方框或起點, 顏色, TextFormatFlags)、PixText.MeasureText(字, 字型[, 大小, 旗標])。
//   支援的旗標：HorizontalCenter／Right、VerticalCenter／Bottom、WordBreak（中文一個字一個字斷、英文在空白斷）、EndEllipsis、SingleLine；
//   其他（NoPadding、NoPrefix…）當作有設。不裁切（跟 NoClipping 一樣），EndEllipsis 會先把字剪短。
// Mac 版：CoreText 本來就畫外框字，不用移植這支。刻意寫成 C# 5。
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.Drawing;
    using System.Drawing.Text;
    using System.Text;
    using System.Windows.Forms;

    static class PixText
    {
        static readonly StringFormat SF = MakeSF();
        static StringFormat MakeSF()
        {
            StringFormat f = (StringFormat)StringFormat.GenericTypographic.Clone();
            f.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces | StringFormatFlags.NoWrap | StringFormatFlags.NoClip;
            return f;
        }

        static float dpi;
        static float Dpi()
        {
            if (dpi <= 0)
            {
                try { using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) dpi = g.DpiY; } catch { dpi = 96; }
                if (dpi <= 0) dpi = 96;
            }
            return dpi;
        }

        // 點數字型 → 整數像素字型（快取）
        static readonly Dictionary<string, Font> pxFonts = new Dictionary<string, Font>();
        public static Font Px(Font f)
        {
            if (f.Unit == GraphicsUnit.Pixel && f.Size == (float)Math.Round(f.Size)) return f;
            float px = (float)Math.Max(1, Math.Round(f.Unit == GraphicsUnit.Pixel ? f.Size : f.SizeInPoints * Dpi() / 72f));
            string k = f.FontFamily.Name + "|" + (int)f.Style + "|" + px;
            lock (pxFonts)
            {
                Font v;
                if (!pxFonts.TryGetValue(k, out v)) { v = new Font(f.FontFamily, px, f.Style, GraphicsUnit.Pixel); pxFonts[k] = v; }
                return v;
            }
        }
        static readonly Dictionary<float, Font> emojiFonts = new Dictionary<float, Font>();
        static Font Emoji(Font px)
        {
            lock (emojiFonts)
            {
                Font v;
                if (!emojiFonts.TryGetValue(px.Size, out v)) { v = new Font("Segoe UI Emoji", px.Size, FontStyle.Regular, GraphicsUnit.Pixel); emojiFonts[px.Size] = v; }
                return v;
            }
        }

        // 一行的高度＝字型的 ascent＋descent（跟 TextRenderer 一樣）
        public static int LineH(Font f)
        {
            Font p = Px(f);
            FontFamily ff = p.FontFamily;
            return (int)Math.Ceiling(p.Size * (ff.GetCellAscent(p.Style) + ff.GetCellDescent(p.Style)) / ff.GetEmHeight(p.Style));
        }

        // GDI+ 畫不出來、要交給 GDI 的字：代理字組（emoji）、變體選擇符、ZWJ
        static bool IsEmojiChar(char c) { return char.IsSurrogate(c) || c == (char)0xFE0F || c == (char)0xFE0E || c == (char)0x200D; }

        // 切成「一般字／emoji」兩種段
        static List<KeyValuePair<string, bool>> Runs(string s)
        {
            List<KeyValuePair<string, bool>> l = new List<KeyValuePair<string, bool>>();
            int i = 0;
            while (i < s.Length)
            {
                bool e = IsEmojiChar(s[i]);
                int j = i;
                while (j < s.Length && IsEmojiChar(s[j]) == e) j++;
                l.Add(new KeyValuePair<string, bool>(s.Substring(i, j - i), e));
                i = j;
            }
            return l;
        }

        static Bitmap mBmp;
        static Graphics mG;
        static float RunW(string s, Font px, bool emoji)
        {
            if (s.Length == 0) return 0;
            if (emoji) return TextRenderer.MeasureText(s, Emoji(px), new Size(4000, 400), TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine).Width;
            lock (SF)
            {
                if (mG == null) { mBmp = new Bitmap(1, 1); mG = Graphics.FromImage(mBmp); mG.TextRenderingHint = TextRenderingHint.AntiAliasGridFit; }
                return mG.MeasureString(s, px, PointF.Empty, SF).Width;
            }
        }
        // 一行字的寬（像素，往上取整）
        public static int LineW(string s, Font f)
        {
            Font px = Px(f);
            float w = 0;
            foreach (KeyValuePair<string, bool> r in Runs(s ?? "")) w += RunW(r.Key, px, r.Value);
            return (int)Math.Ceiling(w - 0.01f);
        }

        // 照寬度換行：\n 一定換；中文一個字一個字斷，英文、數字盡量在空白斷
        static List<string> Wrap(string s, Font f, int width, bool wrap)
        {
            List<string> lines = new List<string>();
            foreach (string para in (s ?? "").Replace("\r\n", "\n").Split('\n'))
            {
                if (!wrap || width <= 0 || LineW(para, f) <= width) { lines.Add(para); continue; }
                int start = 0;
                while (start < para.Length)
                {
                    int end = start + 1;
                    while (end < para.Length && char.IsLowSurrogate(para[end])) end++;
                    int lastSpace = -1;
                    while (end < para.Length)
                    {
                        int next = end + 1;
                        while (next < para.Length && char.IsLowSurrogate(para[next])) next++;
                        if (LineW(para.Substring(start, next - start), f) > width) break;
                        if (para[end] == ' ') lastSpace = end;
                        end = next;
                    }
                    // 斷在英文字中間：退回上一個空白
                    if (end < para.Length && lastSpace > start && IsWordChar(para[end]) && IsWordChar(para[end - 1])) end = lastSpace + 1;
                    // 標點不放在行首
                    if (end < para.Length && end - start > 1 && "，。、；：！？）」』…,.;:!?)".IndexOf(para[end]) >= 0) end++;
                    lines.Add(para.Substring(start, end - start).TrimEnd(' '));
                    start = end;
                    while (start < para.Length && para[start] == ' ') start++;
                }
            }
            return lines;
        }
        static bool IsWordChar(char c) { return c < 0x2E80 && (char.IsLetterOrDigit(c) || c == '_' || c == '-' || c == '.' || c == '/'); }

        static string Ellipsis(string s, Font f, int width)
        {
            if (width <= 0 || LineW(s, f) <= width) return s;
            for (int n = s.Length - 1; n > 0; n--)
            {
                if (char.IsLowSurrogate(s[n])) continue;
                string t = s.Substring(0, n).TrimEnd() + "…";
                if (LineW(t, f) <= width) return t;
            }
            return "…";
        }

        public static Size MeasureText(string s, Font f) { return MeasureText(s, f, new Size(4000, 400), TextFormatFlags.NoPadding); }
        public static Size MeasureText(string s, Font f, Size proposed, TextFormatFlags fl)
        {
            bool wrap = (fl & TextFormatFlags.WordBreak) != 0 && (fl & TextFormatFlags.SingleLine) == 0;
            List<string> lines = (fl & TextFormatFlags.SingleLine) != 0 ? new List<string> { (s ?? "").Replace("\r", "").Replace("\n", " ") } : Wrap(s, f, wrap ? proposed.Width : 0, wrap);
            int w = 0;
            foreach (string l in lines) w = Math.Max(w, LineW(l, f));
            return new Size(w, LineH(f) * Math.Max(1, lines.Count));
        }

        public static void DrawText(Graphics g, string s, Font f, Point p, Color c, TextFormatFlags fl)
        {
            DrawText(g, s, f, new Rectangle(p.X, p.Y, 0, 0), c, fl & ~(TextFormatFlags.HorizontalCenter | TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.Bottom | TextFormatFlags.WordBreak | TextFormatFlags.EndEllipsis));
        }

        public static void DrawText(Graphics g, string s, Font f, Rectangle r, Color c, TextFormatFlags fl)
        {
            if (string.IsNullOrEmpty(s)) return;
            Font px = Px(f);
            bool single = (fl & TextFormatFlags.SingleLine) != 0;
            bool wrap = (fl & TextFormatFlags.WordBreak) != 0 && !single;
            List<string> lines = single ? new List<string> { s.Replace("\r", "").Replace("\n", " ") } : Wrap(s, f, wrap ? r.Width : 0, wrap);
            if ((fl & TextFormatFlags.EndEllipsis) != 0)
            {
                int lh0 = LineH(f);
                int max = r.Height > 0 ? Math.Max(1, r.Height / lh0) : lines.Count;
                if (lines.Count > max) { lines = lines.GetRange(0, max); lines[max - 1] = lines[max - 1] + "…"; }
                for (int i = 0; i < lines.Count; i++) lines[i] = Ellipsis(lines[i], f, r.Width);
            }
            int lh = LineH(f), total = lh * lines.Count;
            float y = r.Y;
            if ((fl & TextFormatFlags.VerticalCenter) != 0) y = r.Y + (r.Height - total) / 2f;
            else if ((fl & TextFormatFlags.Bottom) != 0) y = r.Bottom - total;
            TextRenderingHint was = g.TextRenderingHint;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            try
            {
                using (SolidBrush b = new SolidBrush(c))
                    foreach (string line in lines)
                    {
                        float w = LineW(line, f), x = r.X;
                        if ((fl & TextFormatFlags.HorizontalCenter) != 0) x = r.X + (r.Width - w) / 2f;
                        else if ((fl & TextFormatFlags.Right) != 0) x = r.Right - w;
                        float cx = (float)Math.Round(x);
                        int cy = (int)Math.Round(y);
                        foreach (KeyValuePair<string, bool> run in Runs(line))
                        {
                            if (run.Value)
                            {
                                Font ef = Emoji(px);
                                Size es = TextRenderer.MeasureText(run.Key, ef, new Size(4000, 400), TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine);
                                TextRenderer.DrawText(g, run.Key, ef, new Point((int)cx, cy + (lh - es.Height) / 2), c, TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine);
                                cx += es.Width;
                            }
                            else
                            {
                                g.DrawString(run.Key, px, b, cx, cy, SF);
                                cx = (float)Math.Round(cx + RunW(run.Key, px, false));
                            }
                        }
                        y += lh;
                    }
            }
            finally { g.TextRenderingHint = was; }
        }
    }
}
