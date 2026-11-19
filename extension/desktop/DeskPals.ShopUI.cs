// WoWo Pals 0.11：商店那一批的四個像素視窗（畫面照 v011\shop-ui 使用者選定的版：打卡冊 B 繪本跨頁、季節商店 A 分區、
//   輸入解鎖碼 C 票根、造型選擇 C 試穿舞台）。畫法跟 StudySettingsForm／WorkSettingsForm 一樣：FixedSingle 視窗 + Pix.* 畫木框面板、
//   PixText 畫字；離屏時不真的顯示（SetVisibleCore），snap 時 PaintTo 畫進虛擬螢幕，pipe「cui …」驅動測試。
//   邏輯都接 DeskPals.Shop.cs（打卡 StampCount、兌換 Redeem、穿 WearOf／SetWear、設定 ShopConfig），這裡只負責畫面和點擊。
// 入口：小屋選單「我的公仔」→ 打卡冊／季節商店／（圖片公仔櫃才有）造型與櫃子；「設定」→ 輸入解鎖碼；公仔右鍵（圖片公仔）→ 造型與櫃子。
//   鎖著的付費項目都是「打開商店」；shop.txt 還沒填時：季節商品顯示「即將推出」、付款區顯示香港 FPS／信箱備援。
// Mac（Swift）之後移植：版面和狀態照這支，畫字用 CoreText、合成用 SqCostume。
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.Drawing;
    using System.Drawing.Drawing2D;
    using System.Drawing.Imaging;
    using System.Text;
    using System.Windows.Forms;

    partial class World
    {
        // 一次只開一個商店視窗
        ShopWin shopWin;

        public void ShowCheckin() { OpenShopWin(new CheckinForm(this)); }
        public void ShowShop() { OpenShopWin(new ShopForm(this)); }
        public void ShowCodeEntry() { OpenShopWin(new CodeForm(this)); }
        public void ShowCostumePicker() { OpenShopWin(new PickerForm(this)); }

        void OpenShopWin(ShopWin f)
        {
            if (shopWin != null && !shopWin.IsDisposed) { try { shopWin.Close(); } catch { } }
            shopWin = f;
            Rectangle wa = App.Offscreen ? screens[0].WorkingArea : Screen.FromPoint(Cursor.Position).WorkingArea;
            f.FitTo(wa);
            f.Location = new Point(wa.Left + Math.Max(0, (wa.Width - f.Width) / 2), wa.Top + Math.Max(0, (wa.Height - f.Height) / 2));
            f.Show();
            if (App.Offscreen) return;
            ActivateForm(f);
            ShopWin ff = f;
            Later(0.2, delegate { if (!ff.IsDisposed && ff.Visible) ActivateForm(ff); });
        }

        void ShopUISnap(Graphics g) { if (shopWin != null && !shopWin.IsDisposed && shopWin.VVisible) shopWin.PaintTo(g); }

        // 公仔穿上造型（或不穿）的預覽圖：用另一個 World 畫，不動桌面上的公仔；照 (公仔, 造型, 大小) 快取
        Dictionary<string, Bitmap> costPrev;
        public Bitmap CostumePreviewPic(string palId, string costumeId, int s)
        {
            if (string.IsNullOrEmpty(palId)) return null;
            string key = palId + "|" + costumeId + "|" + s;
            if (costPrev == null) costPrev = new Dictionary<string, Bitmap>();
            Bitmap b;
            if (costPrev.TryGetValue(key, out b)) return b;
            try
            {
                World pv = new World(s, lineup);
                Pet me = pv.Get(palId) ?? (pv.Pets.Count > 0 ? pv.Pets[0] : null);
                if (me != null && me.P.Orig && me.P.Spr != null)
                {
                    me.P.Spr.Costume = string.IsNullOrEmpty(costumeId) ? null : SqCostume.Load(palId, costumeId, me.P.Spr.R <= 4 ? 1 : 2);
                    b = me.IconPic();
                }
            }
            catch (Exception ex) { App.Log("costume preview: " + ex.Message); }
            costPrev[key] = b;
            return b;
        }

        // 圖片公仔櫃「試穿」要用哪一隻當模特兒：帶頭那隻（是圖片公仔的話），否則這一櫃第一隻
        public string PreviewPalId()
        {
            Pet l = Lead();
            if (l != null && l.P.Orig) return l.P.Id;
            foreach (Pet p in Pets) if (p.P.Orig) return p.P.Id;
            return l != null ? l.P.Id : "";
        }

        // 季節櫃子外觀的預覽縮圖（商店裡「聖誕櫃／期末考櫃」那格用）：直接讀這一櫃對應的 skin/<id>/<r>x/box.png，
        //   不經過 ShelfArt 的目前狀態（才不會把現在穿的外觀改掉）。讀不到＝null
        Dictionary<string, Bitmap> skinPrev;
        public Bitmap ShelfSkinPic(string skin, int s)
        {
            if (string.IsNullOrEmpty(skin)) return null;
            string key = lineup + "|" + skin + "|" + s;
            if (skinPrev == null) skinPrev = new Dictionary<string, Bitmap>();
            Bitmap b;
            if (skinPrev.TryGetValue(key, out b)) return b;
            try
            {
                SqLineup q = SqArt.Lineup(lineup);
                string dir = q != null && SqArt.Read(q.Dir + "/shelf/shelf.txt") != null ? q.Dir + "/shelf" : "shelf";
                int r = s <= 4 ? 1 : 2;
                b = SqArt.Png(dir + "/skin/" + skin + "/" + r + "x/box.png");
                if (b == null && r == 1) b = SqArt.Png(dir + "/skin/" + skin + "/2x/box.png");
            }
            catch (Exception ex) { App.Log("shelf skin preview: " + ex.Message); }
            skinPrev[key] = b;
            return b;
        }

        public static string CostumeName(string id)
        {
            if (string.IsNullOrEmpty(id)) return "不穿";
            ShopConfig.Reward r = ShopConfig.RewardFor(id); if (r != null) return r.Name;
            ShopConfig.Sellable s = ShopConfig.SellFor("costume", id); if (s != null) return s.Name;
            return id;
        }
        public static string SkinName(string id)
        {
            if (string.IsNullOrEmpty(id)) return "原本";
            ShopConfig.Sellable s = ShopConfig.SellFor("cabinet", id); if (s != null) return s.Name;
            return id;
        }

        // pipe：cui open <checkin|shop|code|picker> [arg]｜close｜info｜press <id>｜type <key> <text>｜key <esc|tab|shifttab|space>
        bool ShopUIMsg(Client c, string[] p, string line)
        {
            if (p[0] != "cui") return false;
            if (p.Length < 2) return true;
            string t = line.Trim();
            switch (p[1])
            {
                case "open":
                    string which = p.Length >= 3 ? p[2] : "shop";
                    if (which == "checkin") ShowCheckin();
                    else if (which == "code") ShowCodeEntry();
                    else if (which == "picker") ShowCostumePicker();
                    else ShowShop();
                    return true;
            }
            if (shopWin == null || shopWin.IsDisposed) { if (p[1] == "info") Send(c, "cui none\nend\n"); return true; }
            switch (p[1])
            {
                case "close": shopWin.Cancel(); break;
                case "info": Send(c, shopWin.Info() + "end\n"); break;
                case "press": if (p.Length >= 3) shopWin.Press(p[2]); break;
                case "type": if (p.Length >= 3) { int i3 = NthSpace(t, 3); shopWin.TestType(p[2], i3 > 0 ? t.Substring(i3 + 1) : ""); } break;
                case "key": if (p.Length >= 3) shopWin.TestKey(p[2]); break;
            }
            return true;
        }
    }

    // ================= 四個視窗共用的底：木框面板、銅牌、頁腳兩顆鈕、離屏畫法、點擊與鍵盤 =================
    abstract class ShopWin : Form
    {
        protected readonly World w;
        protected readonly double d;
        protected readonly int U;
        protected readonly Font plateF, h1F, nameF, bodyF, smallF, btnF, cntF, bigF, monoF;
        public bool VVisible;
        protected string hoverId = "", focusStop = "", lastOpened = "";
        protected readonly Dictionary<string, Rectangle> hits = new Dictionary<string, Rectangle>();
        protected readonly List<string> stops = new List<string>();
        protected readonly Dictionary<string, TextBox> boxes = new Dictionary<string, TextBox>();
        protected readonly HashSet<string> shown = new HashSet<string>();
        readonly Dictionary<TextBox, string> cues = new Dictionary<TextBox, string>();
        readonly Dictionary<TextBox, string> boxKey = new Dictionary<TextBox, string>();
        readonly int LW, LH;
        protected static readonly Color Paper = Pix.C(0xFFFDF7), Sub = Pix.C(0x6B4E33), Ok = Pix.C(0x276A1C), Bad = Pix.C(0xB04040), Warn = Pix.C(0x8A500C), Mute = Pix.C(0x6E5238), Link = Pix.C(0x7A4A22), Head = Pix.C(0x7A4A22), PriceC = Pix.C(0x8A5A2A);

        protected ShopWin(World w, string title, int lw, int lh)
        {
            this.w = w;
            d = w.S / 4.0;
            U = Math.Max(2, (int)Math.Round(2 * d));
            LW = lw; LH = lh;
            Text = title;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false; MinimizeBox = false;
            ShowInTaskbar = true; TopMost = true;
            StartPosition = FormStartPosition.Manual;
            BackColor = Pix.Cream;
            DoubleBuffered = true;
            KeyPreview = true;
            string jh = "Microsoft JhengHei UI";
            plateF = new Font(jh, 12f, FontStyle.Bold);
            h1F = new Font(jh, 10.5f, FontStyle.Bold);
            nameF = new Font(jh, 11f, FontStyle.Bold);
            bodyF = new Font(jh, 10f, FontStyle.Bold);
            smallF = new Font(jh, 8.5f, FontStyle.Bold);
            btnF = new Font(jh, 11f, FontStyle.Bold);
            cntF = new Font(jh, 16f, FontStyle.Bold);
            bigF = new Font(jh, 25f, FontStyle.Bold);
            monoF = new Font("Consolas", 12f, FontStyle.Bold);
            ClientSize = new Size(Sc(lw), Sc(lh));
        }

        protected int Sc(int x) { return (int)Math.Round(x * d); }
        protected int W0 { get { return Sc(LW); } }
        protected int H0 { get { return Sc(LH); } }

        public void FitTo(Rectangle wa)
        {
            int chrome = Height - ClientSize.Height, fullW = Sc(LW), fullH = Sc(LH);
            if (fullH + chrome <= wa.Height) { AutoScroll = false; ClientSize = new Size(fullW, fullH); }
            else
            {
                AutoScroll = true;
                AutoScrollMinSize = new Size(fullW, fullH);
                ClientSize = new Size(fullW + SystemInformation.VerticalScrollBarWidth, Math.Max(Sc(240), wa.Height - chrome));
            }
            Relayout();
            Invalidate();
        }
        Point Logical(Point p) { return AutoScroll ? new Point(p.X - AutoScrollPosition.X, p.Y - AutoScrollPosition.Y) : p; }
        protected override void OnScroll(ScrollEventArgs se) { base.OnScroll(se); Invalidate(); }
        protected override void OnMouseWheel(MouseEventArgs e) { base.OnMouseWheel(e); Invalidate(); }

        // ---- 文字輸入框（只有輸入解鎖碼用）----
        protected TextBox AddBox(string key, bool mono, bool center)
        {
            TextBox t = new TextBox();
            t.BorderStyle = BorderStyle.None; t.BackColor = Paper; t.ForeColor = Pix.TextC;
            t.Font = mono ? monoF : bodyF;
            t.Visible = false;
            if (center) t.TextAlign = HorizontalAlignment.Center;
            boxes[key] = t; boxKey[t] = key;
            Controls.Add(t);
            return t;
        }
        protected void PlaceBox(string key, Rectangle r, string cue)
        {
            TextBox t;
            if (!boxes.TryGetValue(key, out t)) return;
            t.Bounds = r;
            cues[t] = cue;
            shown.Add(key);
            if (!App.Offscreen) t.Visible = true;
        }
        public void TestType(string key, string text) { TextBox t; if (boxes.TryGetValue(key, out t)) t.Text = text; }
        protected string BoxText(string key) { TextBox t; return boxes.TryGetValue(key, out t) ? t.Text : ""; }

        // ---- 畫圖小工具 ----
        protected void Txt(Graphics g, string s, Font f, Rectangle r, Color c, TextFormatFlags fl) { PixText.DrawText(g, s, f, r, c, fl | TextFormatFlags.NoPrefix); }
        protected void Hit(string id, Rectangle r, bool stop) { hits[id] = r; if (stop) stops.Add(id); }

        // 頁腳的鈕（左邊次要、右邊主要），跟 WorkSettings 一樣
        protected void Button(Graphics g, string id, string text, Rectangle r, bool main)
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
        // 畫在面板上的一張「卡片」底（圓角、奶油色、底一條陰影；可選鎖住／已擁有的配色）
        protected void CardBg(Graphics g, Rectangle r, int tone)
        {
            Color edge = tone == 2 ? Pix.Dim : (tone == 1 ? Pix.C(0x2F6E24) : Pix.Ink);
            Color fill = tone == 2 ? Pix.C(0xF3EADB) : (tone == 1 ? Pix.C(0xEAF6DC) : Paper);
            Color foot = tone == 2 ? Pix.C(0xE2D6C0) : (tone == 1 ? Pix.C(0xBFE0A6) : Pix.C(0xEAD7B4));
            Pix.Round(g, edge, r.X, r.Y, r.Width, r.Height, U);
            Pix.Box(g, fill, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            Pix.Box(g, foot, r.X + U, r.Bottom - 4 * U, r.Width - 2 * U, 3 * U);
        }
        // 虛線小標的點點分隔線
        protected void DotLine(Graphics g, int x, int y, int wdt)
        {
            for (int i = 0; i < wdt; i += 2 * U) Pix.Box(g, Pix.C(0xD8BF94), x + i, y, U, Math.Max(1, U / 2) + 1);
        }
        // 公仔預覽圖貼進一個方框（置中、像素放大、不要變形）
        protected void PalInto(Graphics g, Bitmap pic, Rectangle box)
        {
            if (pic == null) return;
            double sc = Math.Min(box.Width / (double)pic.Width, box.Height / (double)pic.Height);
            if (sc <= 0) return;
            int pw = Math.Max(1, (int)(pic.Width * sc)), ph = Math.Max(1, (int)(pic.Height * sc));
            InterpolationMode im = g.InterpolationMode; PixelOffsetMode pom = g.PixelOffsetMode;
            g.InterpolationMode = InterpolationMode.NearestNeighbor; g.PixelOffsetMode = PixelOffsetMode.Half;
            g.DrawImage(pic, new Rectangle(box.X + (box.Width - pw) / 2, box.Y + (box.Height - ph) / 2, pw, ph), new Rectangle(0, 0, pic.Width, pic.Height), GraphicsUnit.Pixel);
            g.InterpolationMode = im; g.PixelOffsetMode = pom;
        }

        // ---- chrome ----
        protected abstract string Plate { get; }          // null＝沒有銅牌（打卡冊、票根）
        protected abstract void Body(Graphics g, Rectangle panel, int footTop);
        protected abstract void FooterButtons(Graphics g, int by, int bh);
        public abstract void Press(string id);
        protected virtual void InfoExtra(StringBuilder sb) { }
        protected virtual void OnEsc() { Cancel(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.None;
            hits.Clear(); stops.Clear(); shown.Clear();
            if (AutoScroll) g.TranslateTransform(AutoScrollPosition.X, AutoScrollPosition.Y);
            int F = 4 * U;
            Pix.Wood(g, 0, 0, W0, H0, U, false, 41);
            string plate = Plate;
            int crown = plate != null ? Sc(52) : Sc(12);
            Pix.Panel(g, F, crown, W0 - 2 * F, H0 - crown - F, U, false);
            if (plate != null)
            {
                int tw = Pix.TextW(plate, plateF), plw = tw + 14 * U, plh = Sc(34);
                Rectangle pr = new Rectangle((W0 - plw) / 2, (crown - plh) / 2 + U / 2, plw, plh);
                Pix.Plate(g, plate, plateF, pr, U);
                Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.X - 9 * U, pr.Y + plh / 2 - 2 * U, U);
                Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.Right + 4 * U, pr.Y + plh / 2 - 2 * U, U);
            }
            int by = H0 - Sc(58), bh = Sc(42);
            Rectangle panel = new Rectangle(F + Sc(8), crown + Sc(6), W0 - 2 * F - Sc(16), by - Sc(10) - (crown + Sc(6)));
            Body(g, panel, by - Sc(10));
            FooterButtons(g, by, bh);
            Rectangle fr;
            if (focusStop != "" && !focusStop.StartsWith("tb:") && hits.TryGetValue(focusStop, out fr))
                using (Pen pen = new Pen(Pix.Ink, Math.Max(2, U))) { pen.DashStyle = DashStyle.Dash; g.DrawRectangle(pen, fr.X + 2 * U, fr.Y + 2 * U, fr.Width - 4 * U - 1, fr.Height - 4 * U - 1); }
        }

        // ---- 離屏：不真的顯示，snap 時畫進虛擬螢幕 ----
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
                using (Graphics gg = Graphics.FromImage(b))
                {
                    OnPaint(new PaintEventArgs(gg, new Rectangle(0, 0, cs.Width, cs.Height)));
                    foreach (TextBox t in boxes.Values)
                    {
                        if (!shown.Contains(boxKey[t])) continue;
                        using (SolidBrush bg = new SolidBrush(t.BackColor)) gg.FillRectangle(bg, t.Bounds);
                        string s = t.Text;
                        string cue;
                        if (s == "" && cues.TryGetValue(t, out cue) && cue != null)
                        { PixText.DrawText(gg, cue, t.Font, t.Bounds, Pix.C(0x866B51), (t.TextAlign == HorizontalAlignment.Center ? TextFormatFlags.HorizontalCenter : TextFormatFlags.Left) | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis); continue; }
                        PixText.DrawText(gg, s, t.Font, t.Bounds, t.ForeColor, (t.TextAlign == HorizontalAlignment.Center ? TextFormatFlags.HorizontalCenter : TextFormatFlags.Left) | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix | TextFormatFlags.EndEllipsis);
                    }
                }
                g.DrawImageUnscaled(b, Left, Top);
            }
        }
        protected void Relayout()
        {
            if (!App.Offscreen || ClientSize.Width <= 0) return;
            using (Bitmap b = new Bitmap(ClientSize.Width, ClientSize.Height, PixelFormat.Format24bppRgb))
            using (Graphics g = Graphics.FromImage(b)) OnPaint(new PaintEventArgs(g, new Rectangle(0, 0, ClientSize.Width, ClientSize.Height)));
        }

        // ---- 點擊、hover、鍵盤 ----
        string HitAt(Point p)
        {
            string best = ""; int area = int.MaxValue;
            foreach (KeyValuePair<string, Rectangle> kv in hits)
                if (kv.Value.Contains(p) && kv.Value.Width * kv.Value.Height < area) { best = kv.Key; area = kv.Value.Width * kv.Value.Height; }
            return best;
        }
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
            string best = HitAt(Logical(e.Location));
            if (best != "" && !best.StartsWith("tb:")) { focusStop = best; Press(best); }
        }
        protected override bool ProcessDialogKey(Keys k)
        {
            if (k == Keys.Escape) { OnEsc(); return true; }
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
            if (focusStop.StartsWith("tb:")) { if (!App.Offscreen) { TextBox t; if (boxes.TryGetValue(focusStop.Substring(3), out t)) t.Focus(); } }
            else if (!App.Offscreen) ActiveControl = null;
            Invalidate();
        }
        public void TestKey(string k)
        {
            if (k == "esc") OnEsc();
            else if (k == "tab") MoveFocus(1);
            else if (k == "shifttab") MoveFocus(-1);
            else if (k == "space" && focusStop != "" && !focusStop.StartsWith("tb:")) Press(focusStop);
        }

        public void Cancel() { Close(); }
        protected void OpenLink(string url)
        {
            lastOpened = url == null ? "" : url;
            if (App.Offscreen || string.IsNullOrEmpty(url)) return;
            try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true }); }
            catch (Exception ex) { App.Log("shop ui link: " + ex.Message); }
        }

        public string Info()
        {
            Relayout();
            StringBuilder sb = new StringBuilder();
            sb.Append("cui kind=" + Kind + " focus=" + (focusStop == "" ? "-" : focusStop) + " size=" + ClientSize.Width + "x" + ClientSize.Height
                + " scroll=" + (AutoScroll ? 1 : 0) + " title=" + Text.Replace(' ', '_') + " link=" + (lastOpened == "" ? "-" : lastOpened) + "\n");
            InfoExtra(sb);
            foreach (KeyValuePair<string, Rectangle> kv in hits) sb.Append("hit " + kv.Key + " " + kv.Value.X + " " + kv.Value.Y + " " + kv.Value.Width + " " + kv.Value.Height + "\n");
            foreach (KeyValuePair<string, TextBox> kv in boxes) if (shown.Contains(kv.Key)) sb.Append("tb " + kv.Key + " " + (kv.Value.Text == "" ? "-" : kv.Value.Text.Replace(' ', '_')) + "\n");
            return sb.ToString();
        }
        protected abstract string Kind { get; }
    }

    // ================= 打卡冊（B 繪本跨頁）=================
    class CheckinForm : ShopWin
    {
        public CheckinForm(World w) : base(w, "WoWo Pals・打卡冊", 720, CalcH()) { }
        protected override string Kind { get { return "checkin"; } }
        protected override string Plate { get { return null; } }

        // 視窗高度照獎勵階梯長度長：預設兩階（30／60）＝520，超過 60 格或超過兩階才加高（太高的話 FitTo 會變捲動）
        static int CalcH()
        {
            List<ShopConfig.Reward> rw = ShopConfig.Rewards();
            int last = rw.Count == 0 ? 60 : rw[rw.Count - 1].Days;
            int extraRows = Math.Max(0, (last - 60 + 5) / 6);
            int extraCards = Math.Max(0, rw.Count - 2);
            return 520 + extraRows * 40 + extraCards * 108;
        }

        protected override void Body(Graphics g, Rectangle panel, int footTop)
        {
            int cols = 6, goal = Math.Max(cols, ShopConfig.LastRewardDays());   // 畫到最後一階的格數（預設 60）
            int cx = panel.X + panel.Width / 2;
            // 書脊
            for (int y = panel.Y + Sc(6); y < footTop - Sc(6); y += Sc(7)) Pix.Box(g, Pix.C(0xD8BF94), cx - Math.Max(1, U / 2), y, Math.Max(1, U), Sc(4));
            Rectangle left = new Rectangle(panel.X + Sc(6), panel.Y + Sc(4), cx - panel.X - Sc(18), footTop - panel.Y - Sc(8));
            Rectangle right = new Rectangle(cx + Sc(12), panel.Y + Sc(4), panel.Right - cx - Sc(18), footTop - panel.Y - Sc(8));

            // 左頁：我的章
            Txt(g, "我的章", h1F, new Rectangle(left.X, left.Y, left.Width, Sc(22)), Head, Pix.LeftMid);
            int n = w.StampCount, rows = (goal + cols - 1) / cols;
            int gx = Sc(7), cell = (left.Width - (cols - 1) * gx) / cols;
            cell = Math.Min(cell, Sc(34));
            int gy0 = left.Y + Sc(28), latest = n == 0 ? -1 : Math.Min(n, goal) - 1;
            bool today = w.StampedToday;
            for (int i = 0; i < goal; i++)
            {
                int r = i / cols, col = i % cols;
                Rectangle dr = new Rectangle(left.X + col * (cell + gx), gy0 + r * (cell + Sc(6)), cell, cell);
                bool on = i < n;
                bool isToday = today && i == latest;
                Pix.Round(g, isToday ? Pix.C(0x2F6E24) : (on ? Pix.C(0xC8902C) : Pix.C(0xC9B08A)), dr.X, dr.Y, dr.Width, dr.Height, U);
                Pix.Box(g, on ? Pix.C(0xFBE7BA) : Paper, dr.X + U, dr.Y + U, dr.Width - 2 * U, dr.Height - 2 * U);
                if (isToday) Pix.Box(g, Pix.C(0xDFF0CC), dr.X + 2 * U, dr.Y + 2 * U, dr.Width - 4 * U, dr.Height - 4 * U);
                if (on) Pix.Mono(g, Pix.CHECK, isToday ? Pix.C(0x2F6E24) : Pix.C(0xC08A2C), dr.X + (dr.Width - 5 * U) / 2, dr.Y + (dr.Height - 5 * U) / 2, U);
            }
            int cnY = gy0 + rows * (cell + Sc(6)) + Sc(6);
            string big = n.ToString();
            int bw = Pix.TextW(big, bigF), suffixW = Pix.TextW(" ／" + goal, cntF);
            int tot = bw + suffixW, sx = left.X + (left.Width - tot) / 2;
            Txt(g, big, bigF, new Rectangle(sx, cnY, bw + Sc(4), Sc(40)), Pix.C(0x6E3F1A), Pix.LeftMid);
            Txt(g, " ／" + goal, cntF, new Rectangle(sx + bw, cnY + Sc(8), suffixW + Sc(4), Sc(30)), Pix.C(0x6E3F1A), Pix.LeftMid);
            // 泡泡：公仔講一句（照下一個里程碑）
            int nextR = w.NextReward(n);
            string say = nextR <= 0 ? "都蓋滿囉，好厲害！" : (n <= 0 ? "每天第一次打開就蓋一個章" : "再 " + (nextR - n) + " 個就滿 " + nextR + " 囉");
            Bitmap pal = w.CostumePreviewPic(w.PreviewPalId(), "", w.S);
            int palBoxH = Math.Min(Sc(70), footTop - (cnY + Sc(44)) - Sc(6));
            if (palBoxH > Sc(30))
            {
                Rectangle pb = new Rectangle(left.X, footTop - palBoxH - Sc(2), Sc(56), palBoxH);
                PalInto(g, pal, pb);
                Bubble(g, say, new Rectangle(pb.Right + Sc(6), pb.Y + Sc(4), left.Right - pb.Right - Sc(8), palBoxH - Sc(8)));
            }

            // 右頁：換得到的造型（照獎勵階梯，一階一張卡；美術未到的＝即將推出）
            Txt(g, "換得到的造型", h1F, new Rectangle(right.X, right.Y, right.Width, Sc(22)), Head, Pix.LeftMid);
            int cardH = Sc(96), cy = right.Y + Sc(30);
            string palId = w.PreviewPalId();
            foreach (ShopConfig.Reward rr in ShopConfig.Rewards())
            {
                bool unlocked = n >= rr.Days, ready = SqCostume.Exists(palId, rr.Id);
                int tone = !ready ? 2 : (unlocked ? 1 : 0);
                string note = ready
                    ? (unlocked ? "滿 " + rr.Days + " 章 ‧ 可以穿了" : "滿 " + rr.Days + " 章就能穿 ‧ 還差 " + (rr.Days - n) + " 個")
                    : (unlocked ? "美術即將推出" : "滿 " + rr.Days + " 章解鎖 ‧ 還差 " + (rr.Days - n) + " 個");
                RewardCard(g, new Rectangle(right.X, cy, right.Width, cardH), rr.Name, note, tone, rr.Id, !ready);
                cy += cardH + Sc(12);
            }
        }

        void RewardCard(Graphics g, Rectangle r, string name, string note, int tone, string costume, bool soon)
        {
            CardBg(g, r, tone);
            int picW = Sc(76);
            Rectangle pic = new Rectangle(r.X + Sc(8), r.Y + (r.Height - picW) / 2, picW, picW);
            if (soon)
            {
                Pix.Round(g, Pix.Dim, pic.X, pic.Y, pic.Width, pic.Width, U);
                Pix.Box(g, Pix.C(0xECE0CA), pic.X + U, pic.Y + U, pic.Width - 2 * U, pic.Width - 2 * U);
                Txt(g, "？", cntF, pic, Pix.C(0xA08963), Pix.Mid);
            }
            else PalInto(g, w.CostumePreviewPic(w.PreviewPalId(), costume, w.S), pic);
            int tx = pic.Right + Sc(12);
            Txt(g, name, nameF, new Rectangle(tx, r.Y + Sc(16), r.Right - tx - Sc(8), Sc(22)), tone == 2 ? Pix.C(0x806A50) : Pix.TextC, Pix.LeftMid);
            if (soon)
            {
                string tag = "即將推出";
                int tw = Pix.TextW(tag, smallF) + Sc(16);
                Rectangle tr = new Rectangle(tx, r.Y + Sc(42), tw, Sc(20));
                Pix.Round(g, Pix.Dim, tr.X, tr.Y, tr.Width, tr.Height, U);
                Pix.Box(g, Pix.C(0xEFE3CB), tr.X + U, tr.Y + U, tr.Width - 2 * U, tr.Height - 2 * U);
                Txt(g, tag, smallF, tr, Pix.C(0x806A50), Pix.Mid);
            }
            Txt(g, note, smallF, new Rectangle(tx, r.Bottom - Sc(28), r.Right - tx - Sc(8), Sc(20)), Mute, Pix.LeftMid);
        }

        void Bubble(Graphics g, string s, Rectangle box)
        {
            Pix.Round(g, Pix.C(0xB98A52), box.X, box.Y, box.Width, box.Height, U);
            Pix.Box(g, Color.White, box.X + U, box.Y + U, box.Width - 2 * U, box.Height - 2 * U);
            Txt(g, s, bodyF, new Rectangle(box.X + Sc(8), box.Y, box.Width - Sc(16), box.Height), Pix.C(0x1F2A44), TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak);
        }

        protected override void FooterButtons(Graphics g, int by, int bh)
        {
            Button(g, "close", "關閉", new Rectangle(Sc(30), by, Sc(130), bh), false);
            Button(g, "picker", "去我的公仔穿", new Rectangle(W0 - Sc(30) - Sc(170), by, Sc(170), bh), true);
        }
        public override void Press(string id)
        {
            if (id == "close") Cancel();
            else if (id == "picker") { World ww = w; Cancel(); ww.ShowCostumePicker(); }
        }
        protected override void InfoExtra(StringBuilder sb)
        {
            int n = w.StampCount;
            sb.Append("stamps " + n + " today=" + (w.StampedToday ? 1 : 0) + " goal30=" + (n >= 30 ? 1 : 0) + " goal60=" + (n >= 60 ? 1 : 0) + " next=" + w.NextReward(n) + "\n");
            string palId = w.PreviewPalId();
            foreach (ShopConfig.Reward rr in ShopConfig.Rewards()) sb.Append("reward " + rr.Days + " " + rr.Id + " got=" + (n >= rr.Days ? 1 : 0) + " art=" + (SqCostume.Exists(palId, rr.Id) ? 1 : 0) + "\n");
        }
    }

    // ================= 季節商店（A 分區）=================
    class ShopForm : ShopWin
    {
        public ShopForm(World w) : base(w, "WoWo Pals・季節商店", 600, ShopH()) { }
        protected override string Kind { get { return "shop"; } }
        protected override string Plate { get { return "季節商店"; } }

        // 高度照賣的項目數長（2 欄；預設 4 項＝2 列＝660）
        static int ShopH()
        {
            int rows = (ShopConfig.Sellables().Count + 1) / 2;
            return 660 + Math.Max(0, rows - 2) * (64 + 10);
        }

        string Price(string twdKey, string hkdKey)
        {
            string twd = ShopConfig.Get(twdKey), hkd = ShopConfig.Get(hkdKey);
            if (twd == "") return "即將推出";
            return "NT$" + twd + (hkd == "" ? "" : "／HK$" + hkd);
        }
        // 單項價錢（manifest 有寫就用它，沒寫就用 price_item_*）
        string ItemPrice(ShopConfig.Sellable s)
        {
            string twd = s.Twd != "" ? s.Twd : ShopConfig.Get("price_item_twd");
            string hkd = s.Hkd != "" ? s.Hkd : ShopConfig.Get("price_item_hkd");
            if (twd == "") return "即將推出";
            return "NT$" + twd + (hkd == "" ? "" : "／HK$" + hkd);
        }

        protected override void Body(Graphics g, Rectangle panel, int footTop)
        {
            int x = panel.X + Sc(6), right = panel.Right - Sc(6), y = panel.Y + Sc(4);
            // 季節限定
            y = Section(g, x, right, y, "季節限定", "各 " + Price("price_item_twd", "price_item_hkd"));
            List<ShopConfig.Sellable> sell = ShopConfig.Sellables();
            int gx = Sc(10), iw = (right - x - gx) / 2, ih = Sc(64), srows = (sell.Count + 1) / 2;
            for (int i = 0; i < sell.Count; i++)
            {
                int col = i % 2, row = i / 2;
                Rectangle r = new Rectangle(x + col * (iw + gx), y + row * (ih + gx), iw, ih);
                Item(g, r, sell[i]);
            }
            y += srows * ih + Math.Max(0, srows - 1) * gx + Sc(16);
            // 咖啡
            y = Section(g, x, right, y, "請我喝杯咖啡", "");
            y = Row(g, x, right, y, "coffee", "請喝咖啡", "一杯 " + Price("coffee_twd", "coffee_hkd"), ShopConfig.Link("coffee-1") != "" ? "1～3 杯" : "即將推出");
            // 訂做
            y += Sc(8);
            y = Section(g, x, right, y, "訂做一隻你的公仔", "");
            string cust = ShopConfig.Get("custom_early_twd") == "" ? "" : "早鳥 NT$" + ShopConfig.Get("custom_early_twd") + (ShopConfig.Get("custom_early_hkd") == "" ? "" : "・HK$" + ShopConfig.Get("custom_early_hkd"));
            y = Row(g, x, right, y, "custom", "用照片訂做 ‧ 單隻／雙人", cust == "" ? "即將推出" : cust, ShopConfig.Link("custom") != "" ? "看方案" : "即將推出");
            // 付款方式
            y += Sc(12);
            PayBlock(g, x, right, y, footTop);
        }

        int Section(Graphics g, int x, int right, int y, string title, string hint)
        {
            Txt(g, title, h1F, new Rectangle(x, y, Sc(240), Sc(22)), Head, Pix.LeftMid);
            int tw = Pix.TextW(title, h1F);
            if (hint != "")
            {
                int hw = Pix.TextW(hint, smallF);
                Txt(g, hint, smallF, new Rectangle(right - hw - Sc(2), y, hw + Sc(4), Sc(22)), PriceC, Pix.LeftMid);
                DotLine(g, x + tw + Sc(10), y + Sc(11), right - hw - Sc(14) - (x + tw + Sc(10)));
            }
            else DotLine(g, x + tw + Sc(10), y + Sc(11), right - (x + tw + Sc(10)));
            return y + Sc(28);
        }

        void Item(Graphics g, Rectangle r, ShopConfig.Sellable s)
        {
            bool owned = w.Owns(s.CodeItem);
            CardBg(g, r, owned ? 1 : 0);
            Hit("item:" + s.CodeItem, r, true);
            int pic = Sc(48);
            Rectangle pr = new Rectangle(r.X + Sc(8), r.Y + (r.Height - pic) / 2, pic, pic);
            Bitmap img = s.Kind == "costume" ? w.CostumePreviewPic(w.PreviewPalId(), s.Id, w.S) : w.ShelfSkinPic(s.Id, w.S);
            PalInto(g, img, pr);
            int tx = pr.Right + Sc(10);
            Txt(g, s.Name, nameF, new Rectangle(tx, r.Y + Sc(12), r.Right - tx - Sc(8), Sc(22)), Pix.TextC, Pix.LeftMid);
            Txt(g, owned ? "已擁有" : ItemPrice(s), smallF, new Rectangle(tx, r.Bottom - Sc(26), r.Right - tx - Sc(8), Sc(20)), owned ? Ok : PriceC, Pix.LeftMid);
            if (owned) Pix.Mono(g, Pix.CHECK, Ok, r.Right - Sc(16), r.Y + Sc(8), U);
        }

        int Row(Graphics g, int x, int right, int y, string id, string name, string price, string btn)
        {
            int h = Sc(48);
            Rectangle r = new Rectangle(x, y, right - x, h);
            CardBg(g, r, 0);
            int tx = r.X + Sc(12);
            Txt(g, name, bodyF, new Rectangle(tx, r.Y, Sc(240), h - U), Pix.TextC, Pix.LeftMid);
            int bw = Sc(92), br = r.Right - Sc(10) - bw, bh = Sc(28);
            int pw = Pix.TextW(price, smallF);
            Txt(g, price, smallF, new Rectangle(br - pw - Sc(12), r.Y, pw + Sc(4), h - U), PriceC, Pix.LeftMid);
            SmallBtn(g, "buy:" + id, btn, new Rectangle(br, r.Y + (h - bh) / 2, bw, bh), btn != "即將推出");
            return y + h + Sc(10);
        }

        void SmallBtn(Graphics g, string id, string text, Rectangle r, bool on)
        {
            bool hot = hoverId == id;
            Pix.Round(g, on ? Pix.Ink : Pix.Dim, r.X, r.Y, r.Width, r.Height, U);
            Pix.Box(g, on ? (hot ? Pix.C(0xFFD36A) : Pix.C(0xF6C453)) : Pix.C(0xECE0CA), r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            if (on) Pix.Box(g, Pix.C(0xC8902C), r.X + U, r.Bottom - 2 * U, r.Width - 2 * U, U);
            Txt(g, text, smallF, new Rectangle(r.X, r.Y, r.Width, r.Height - U), on ? Pix.TextC : Pix.C(0x806A50), Pix.Mid);
            if (on) Hit(id, r, true);
        }

        void PayBlock(Graphics g, int x, int right, int y, int footTop)
        {
            int h = Math.Min(Sc(104), footTop - y - Sc(4));
            Rectangle r = new Rectangle(x, y, right - x, h);
            Pix.Round(g, Pix.C(0xC9B08A), r.X, r.Y, r.Width, r.Height, U);
            Pix.Box(g, Pix.C(0xFBF3E2), r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            int lx = r.X + Sc(14), rr = r.Right - Sc(14), ly = r.Y + Sc(10);
            string tw = ShopConfig.Get("ecpay_xmas_costume"); // 任一條綠界連結代表「台灣綠界」是否已設
            Txt(g, "台灣", bodyF, new Rectangle(lx, ly, Sc(80), Sc(22)), Mute, Pix.LeftMid);
            Txt(g, "綠界收款連結", bodyF, new Rectangle(lx, ly, rr - lx, Sc(22)), Link, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
            ly += Sc(26);
            string fps = ShopConfig.Get("fps_id");
            Txt(g, "香港 FPS", bodyF, new Rectangle(lx, ly, Sc(120), Sc(22)), Mute, Pix.LeftMid);
            Txt(g, fps == "" ? "—" : fps, monoF, new Rectangle(lx, ly, rr - lx, Sc(22)), Pix.TextC, TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
            ly += Sc(28);
            string mail = ShopConfig.Get("mail");
            Txt(g, "付款後把截圖寄到 " + (mail == "" ? "信箱" : mail) + "，收到解鎖碼後在這裡輸入。", smallF, new Rectangle(lx, ly, rr - lx, Sc(34)), Mute, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak);
        }

        protected override void FooterButtons(Graphics g, int by, int bh)
        {
            Button(g, "close", "關閉", new Rectangle(Sc(30), by, Sc(120), bh), false);
            Button(g, "code", "輸入解鎖碼", new Rectangle(W0 - Sc(30) - Sc(150), by, Sc(150), bh), true);
        }
        public override void Press(string id)
        {
            if (id == "close") { Cancel(); return; }
            if (id == "code") { World ww = w; Cancel(); ww.ShowCodeEntry(); return; }
            string a = id, arg = "";
            int c = id.IndexOf(':');
            if (c > 0) { a = id.Substring(0, c); arg = id.Substring(c + 1); }
            if (a == "item") { if (w.Owns(arg)) { World ww = w; Cancel(); ww.ShowCostumePicker(); } else OpenLink(ShopConfig.Link(arg)); }
            else if (a == "buy") { if (arg == "coffee") OpenLink(ShopConfig.Link("coffee-1")); else if (arg == "custom") OpenLink(ShopConfig.Link("custom")); }
        }
        protected override void InfoExtra(StringBuilder sb)
        {
            foreach (ShopConfig.Sellable it in ShopConfig.Sellables()) sb.Append("item " + it.CodeItem + " owned=" + (w.Owns(it.CodeItem) ? 1 : 0) + "\n");
            sb.Append("cfg mail=" + (ShopConfig.Get("mail") == "" ? "-" : ShopConfig.Get("mail")) + " fps=" + (ShopConfig.Get("fps_id") == "" ? "-" : ShopConfig.Get("fps_id")) + " ecpay=" + (ShopConfig.Get("ecpay_xmas_costume") == "" ? "-" : "set") + "\n");
        }
    }

    // ================= 輸入解鎖碼（C 票根）=================
    class CodeForm : ShopWin
    {
        string result = "", gotItems = "";
        public CodeForm(World w) : base(w, "WoWo Pals・輸入解鎖碼", 480, 420) { AddBox("code", true, true); }
        protected override string Kind { get { return "code"; } }
        protected override string Plate { get { return null; } }

        protected override void Body(Graphics g, Rectangle panel, int footTop)
        {
            int x = panel.X + Sc(16), right = panel.Right - Sc(16);
            Rectangle tk = new Rectangle(x, panel.Y + Sc(8), right - x, Sc(130));
            CardBg(g, tk, 0);
            // 票根兩側的半圓缺口
            Pix.Box(g, Pix.Cream, tk.X - Sc(6), tk.Y + tk.Height / 2 - Sc(6), Sc(12), Sc(12));
            Pix.Box(g, Pix.Cream, tk.Right - Sc(6), tk.Y + tk.Height / 2 - Sc(6), Sc(12), Sc(12));
            Txt(g, "🎟 解鎖票根", bodyF, new Rectangle(tk.X + Sc(14), tk.Y + Sc(10), tk.Width - Sc(28), Sc(22)), Head, Pix.LeftMid);
            // 輸入框
            Rectangle fb = new Rectangle(tk.X + Sc(14), tk.Y + Sc(40), tk.Width - Sc(28), Sc(34));
            bool foc = focusStop == "tb:code";
            Pix.Round(g, foc ? Pix.Ink : Pix.C(0x8A6A4A), fb.X, fb.Y, fb.Width, fb.Height, U);
            Pix.Box(g, Paper, fb.X + U, fb.Y + U, fb.Width - 2 * U, fb.Height - 2 * U);
            Pix.Box(g, Pix.C(0xEAD7B4), fb.X + U, fb.Y + U, fb.Width - 2 * U, U);
            PlaceBox("code", new Rectangle(fb.X + Sc(8), fb.Y + U + Sc(2), fb.Width - Sc(16), fb.Height - 2 * U - Sc(4)), "XXXX-XXXX-XXXX-…");
            Hit("tb:code", fb, true);
            // 撕線
            int py = tk.Y + Sc(84);
            for (int i = tk.X + Sc(6); i < tk.Right - Sc(6); i += Sc(9)) Pix.Box(g, Pix.C(0xD8BF94), i, py, Sc(4), Math.Max(1, U / 2) + 1);
            // 結果
            string msg, col = "";
            if (result == "ok") { msg = "解鎖成功，收進櫃子了：" + ItemNames(gotItems); col = "ok"; }
            else if (result == "again") { msg = "這組之前已經解鎖過囉"; col = "warn"; }
            else if (result == "bad") { msg = "這組看起來不對，再看一下"; col = "bad"; }
            else msg = "";
            if (msg != "") Txt(g, msg, smallF, new Rectangle(tk.X + Sc(14), py + Sc(8), tk.Width - Sc(28), Sc(30)), col == "ok" ? Ok : (col == "bad" ? Bad : Warn), TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak);
            // 公仔泡泡
            Bitmap pal = w.CostumePreviewPic(w.PreviewPalId(), "", w.S);
            int palH = Math.Min(Sc(66), footTop - (tk.Bottom + Sc(10)) - Sc(2));
            if (palH > Sc(28))
            {
                Rectangle pb = new Rectangle(x, tk.Bottom + Sc(10), Sc(54), palH);
                PalInto(g, pal, pb);
                Rectangle bub = new Rectangle(pb.Right + Sc(6), pb.Y + Sc(4), right - pb.Right - Sc(6), palH - Sc(8));
                Pix.Round(g, Pix.C(0xB98A52), bub.X, bub.Y, bub.Width, bub.Height, U);
                Pix.Box(g, Color.White, bub.X + U, bub.Y + U, bub.Width - 2 * U, bub.Height - 2 * U);
                Txt(g, "貼上那一串，就幫你收進櫃子", bodyF, new Rectangle(bub.X + Sc(8), bub.Y, bub.Width - Sc(16), bub.Height), Pix.C(0x1F2A44), TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak);
            }
        }
        static string ItemNames(string csv)
        {
            if (csv == "" || csv == "-") return "";
            string[] a = csv.Split(',');
            for (int i = 0; i < a.Length; i++)
            {
                foreach (ShopConfig.Sellable s in ShopConfig.Sellables()) if (s.CodeItem == a[i]) { a[i] = s.Name + (s.Kind == "cabinet" ? "櫃" : ""); break; }
            }
            return string.Join("、", a);
        }

        protected override void FooterButtons(Graphics g, int by, int bh)
        {
            Button(g, "close", "關閉", new Rectangle(Sc(30), by, Sc(120), bh), false);
            Button(g, "unlock", "解鎖", new Rectangle(W0 - Sc(30) - Sc(130), by, Sc(130), bh), true);
        }
        public override void Press(string id)
        {
            if (id == "close") Cancel();
            else if (id == "unlock")
            {
                string[] items;
                result = w.Redeem(BoxText("code"), out items);
                gotItems = items.Length == 0 ? "-" : string.Join(",", items);
                if (result == "ok" && !App.Offscreen) w.Lead().Say("解鎖成功！收進櫃子了", 2.4);
                Invalidate();
            }
        }
        protected override void InfoExtra(StringBuilder sb)
        {
            sb.Append("result " + (result == "" ? "-" : result) + " items " + (gotItems == "" ? "-" : gotItems) + "\n");
        }
    }

    // ================= 造型選擇（C 試穿舞台）=================
    class PickerForm : ShopWin
    {
        public PickerForm(World w) : base(w, "WoWo Pals・我的公仔", 600, PickerH()) { }
        protected override string Kind { get { return "picker"; } }
        protected override string Plate { get { return "試穿"; } }

        // 高度照造型數長（一排約 6 個；預設 5 個＝1 排＝580）
        static int PickerH()
        {
            int costumes = 1 + ShopConfig.Rewards().Count;
            foreach (ShopConfig.Sellable s in ShopConfig.Sellables()) if (s.Kind == "costume") costumes++;
            int rows = (costumes + 5) / 6;
            return 580 + Math.Max(0, rows - 1) * (92 + 10);
        }

        string Lu { get { return w.LineupNow; } }

        protected override void Body(Graphics g, Rectangle panel, int footTop)
        {
            string pal = w.PreviewPalId();
            string worn = w.WearOf("costume", Lu);
            // 舞台：穿著目前造型的公仔
            Rectangle stage = new Rectangle(panel.X + Sc(4), panel.Y + Sc(4), panel.Width - Sc(8), Sc(210));
            Pix.Round(g, Pix.Ink, stage.X, stage.Y, stage.Width, stage.Height, U);
            Pix.Box(g, Pix.C(0xEAF2FB), stage.X + U, stage.Y + U, stage.Width - 2 * U, (stage.Height - 2 * U) * 3 / 5);
            Pix.Box(g, Pix.C(0xFBF3E2), stage.X + U, stage.Y + U + (stage.Height - 2 * U) * 3 / 5, stage.Width - 2 * U, (stage.Height - 2 * U) * 2 / 5);
            PalInto(g, w.CostumePreviewPic(pal, worn, w.S), new Rectangle(stage.X, stage.Y + Sc(8), stage.Width, stage.Height - Sc(20)));
            string tag = World.CostumeName(worn);
            int tgw = Pix.TextW(tag, bodyF) + Sc(20);
            Rectangle tr = new Rectangle(stage.X + Sc(12), stage.Y + Sc(10), tgw, Sc(24));
            Pix.Round(g, Pix.Ink, tr.X, tr.Y, tr.Width, tr.Height, U);
            Pix.Box(g, Pix.C(0xFFFBF0), tr.X + U, tr.Y + U, tr.Width - 2 * U, tr.Height - 2 * U);
            Txt(g, tag, bodyF, new Rectangle(tr.X, tr.Y, tr.Width, tr.Height - U), Pix.C(0x6E3F1A), Pix.Mid);

            // 造型挑選條（資料驅動、排滿一排就換行）
            int sy = stage.Bottom + Sc(14);
            List<string> cos = w.CostumeIds();   // "", 打卡獎勵…, 季節商品…, 有美術但沒列到的
            int fw = Sc(84), fh = Sc(92), gap = Sc(10);
            int perRow = Math.Max(1, (stage.Width + gap) / (fw + gap));
            for (int i = 0; i < cos.Count; i++)
            {
                Rectangle r = new Rectangle(stage.X + (i % perRow) * (fw + gap), sy + (i / perRow) * (fh + gap), fw, fh);
                CostumeTile(g, r, cos[i], pal, worn);
            }
            int crows = (cos.Count + perRow - 1) / perRow;
            // 櫃子外觀
            int cy = sy + crows * (fh + gap) + Sc(6);
            DotLine(g, stage.X, cy - Sc(8), stage.Width);
            Txt(g, "櫃子外觀", bodyF, new Rectangle(stage.X, cy, Sc(90), Sc(28)), Pix.TextC, Pix.LeftMid);
            Txt(g, w.MiniName, smallF, new Rectangle(stage.X + Sc(90), cy, Sc(90), Sc(28)), Mute, Pix.LeftMid);
            string skinWorn = w.WearOf("cabinet", Lu);
            List<string> skins = w.SkinIds();   // "", 季節櫃子外觀…
            int pyh = Sc(28);
            // 從右往左排一組分段
            int segw = Sc(72);
            Rectangle seg = new Rectangle(stage.Right - skins.Count * segw - 2 * U, cy, skins.Count * segw + 2 * U, pyh);
            Pix.Round(g, Pix.Ink, seg.X, seg.Y, seg.Width, seg.Height, U);
            for (int i = 0; i < skins.Count; i++)
            {
                Rectangle c = new Rectangle(seg.X + U + i * segw, seg.Y + U, segw - (i == skins.Count - 1 ? 2 * U : U), seg.Height - 2 * U);
                bool on = skinWorn == skins[i], locked = !w.CanWear("cabinet", skins[i]);
                Color face = on ? Pix.C(0xF6C453) : Pix.C(0xFFFBF0);
                Pix.Box(g, face, c.X, c.Y, c.Width, c.Height);
                if (on) { Pix.Box(g, Pix.C(0xFBE7BA), c.X, c.Y, c.Width, U); Pix.Box(g, Pix.C(0xC8902C), c.X, c.Bottom - U, c.Width, U); }
                string nm = World.SkinName(skins[i]) + (locked ? " 🔒" : "");
                Txt(g, nm, smallF, new Rectangle(c.X, c.Y, c.Width, c.Height), locked ? Pix.C(0x9C8A6E) : (on ? Pix.TextC : Sub), Pix.Mid);
                Hit("skin:" + skins[i], c, true);
            }
        }

        void CostumeTile(Graphics g, Rectangle r, string id, string pal, string worn)
        {
            bool on = worn == id;
            bool can = w.CanWear("costume", id);
            bool soon = w.CostumeSoon(pal, id);
            int tone = soon || !can ? 2 : (on ? 1 : 0);
            CardBg(g, r, tone);
            Hit("costume:" + id, r, true);
            Rectangle pic = new Rectangle(r.X + Sc(6), r.Y + Sc(6), r.Width - Sc(12), Sc(56));
            if (id == "")
            {
                Txt(g, "○", cntF, pic, Pix.Dim, Pix.Mid);
            }
            else if (soon || !can)
            {
                if (soon) Txt(g, "？", cntF, pic, Pix.C(0xB5A089), Pix.Mid);
                else PalInto(g, Fade(w.CostumePreviewPic(pal, ShopConfig.RewardFor(id) != null ? "" : id, w.S)), pic);   // 鎖住的打卡獎勵顯示素顏、季節造型顯示淡化的造型
            }
            else PalInto(g, w.CostumePreviewPic(pal, id, w.S), pic);
            Txt(g, World.CostumeName(id), smallF, new Rectangle(r.X + Sc(2), r.Bottom - Sc(24), r.Width - Sc(4), Sc(18)), (soon || !can) ? Pix.C(0x806A50) : Pix.TextC, Pix.Mid);
            if (on) Pix.Mono(g, Pix.CHECK, Ok, r.Right - Sc(14), r.Y + Sc(6), U);
            else if (soon) Txt(g, "即將", smallF, new Rectangle(r.Right - Sc(34), r.Y + Sc(4), Sc(32), Sc(16)), Pix.C(0x806A50), Pix.Mid);
            else if (!can) Txt(g, "🔒", smallF, new Rectangle(r.Right - Sc(20), r.Y + Sc(4), Sc(16), Sc(16)), Mute, Pix.Mid);
        }

        static Bitmap Fade(Bitmap b)
        {
            if (b == null) return null;
            Bitmap o = new Bitmap(b.Width, b.Height, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(o))
            {
                ColorMatrix cm = new ColorMatrix(); cm.Matrix33 = 0.45f;
                using (ImageAttributes ia = new ImageAttributes()) { ia.SetColorMatrix(cm); g.DrawImage(b, new Rectangle(0, 0, b.Width, b.Height), 0, 0, b.Width, b.Height, GraphicsUnit.Pixel, ia); }
            }
            return o;
        }

        protected override void FooterButtons(Graphics g, int by, int bh)
        {
            Button(g, "close", "完成", new Rectangle(Sc(30), by, Sc(120), bh), false);
            Button(g, "shop", "打開商店", new Rectangle(W0 - Sc(30) - Sc(140), by, Sc(140), bh), true);
        }
        public override void Press(string id)
        {
            if (id == "close") { Cancel(); return; }
            if (id == "shop") { World ww = w; Cancel(); ww.ShowShop(); return; }
            string a = id, arg = "";
            int c = id.IndexOf(':');
            if (c > 0) { a = id.Substring(0, c); arg = id.Substring(c + 1); }
            if (a == "costume")
            {
                if (w.CostumeSoon(w.PreviewPalId(), arg)) return;   // 美術未到＝不給選
                string r = w.SetWear("costume", arg);
                if (r == "locked") { World ww = w; Cancel(); if (ShopConfig.RewardFor(arg) != null) ww.ShowCheckin(); else ww.ShowShop(); }   // 打卡獎勵→打卡冊、季節商品→商店
                else Invalidate();
            }
            else if (a == "skin")
            {
                string r = w.SetWear("cabinet", arg);
                if (r == "locked") { World ww = w; Cancel(); ww.ShowShop(); }
                else Invalidate();
            }
        }
        protected override void InfoExtra(StringBuilder sb)
        {
            sb.Append("lineup " + Lu + " costume=" + (w.WearOf("costume", Lu) == "" ? "-" : w.WearOf("costume", Lu)) + " cabinet=" + (w.WearOf("cabinet", Lu) == "" ? "-" : w.WearOf("cabinet", Lu)) + "\n");
            string pid = w.PreviewPalId();
            foreach (string id in w.CostumeIds())
            {
                string st = w.WearOf("costume", Lu) == id ? "on" : (w.CostumeSoon(pid, id) ? "soon" : (w.CanWear("costume", id) ? "off" : "lock"));
                sb.Append("tile " + (id == "" ? "none" : id) + " " + st + "\n");
            }
            foreach (string id in w.SkinIds()) sb.Append("skin " + (id == "" ? "none" : id) + " " + (w.WearOf("cabinet", Lu) == id ? "on" : (w.CanWear("cabinet", id) ? "off" : "lock")) + "\n");
        }
    }
}
