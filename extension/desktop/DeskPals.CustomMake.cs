// Desk Pals：「做一隻自己的公仔」視窗。四步：選照片 → 去背 → 動起來 → 取名字。
// 全部自己畫（跟設定視窗同一套木框＋奶油色），名字用真的 TextBox（才打得了中文）。離屏測試時不顯示，用 pipe 的 custom 指令操作。
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.Drawing;
    using System.Drawing.Drawing2D;
    using System.Drawing.Imaging;
    using System.IO;
    using System.Windows.Forms;

    class CuMaker : Form
    {
        class Btn { public string Id, Text; public Rectangle R; public int Kind; public bool On, Enabled = true; }   // Kind：0 卡片 2 按鈕 3 主要按鈕 4 小按鈕
        readonly World w;
        readonly bool first;
        readonly string editId;
        readonly double d;
        readonly int U;
        int step;
        public bool VVisible;
        readonly List<Btn> btns = new List<Btn>();
        string hoverId = "", err = "";
        readonly Font titleF, qF, bigF, subF, btnF, smallF;
        readonly TextBox nameBox;
        readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
        double animT;
        string anim = "walk";

        // 草稿
        CuMeta meta = new CuMeta();
        Bitmap src;                      // 原圖（最長邊 640）
        bool srcAlpha;
        int[] srcPx, autoPx, viewPx;     // 原圖、自動去背的結果（快取）、加上筆刷的結果
        int autoKey = -999;
        Bitmap viewBmp, srcDim;
        CuSprite spr;
        Pal draft;
        Pet pv;
        World pvw;
        bool brushOn; bool brushErase = true; int brushSize = 1;
        bool painting, dragLine; int dragWhich;
        Point lastPaint;

        public CuMaker(World w, bool first, string editId)
        {
            this.w = w; this.first = first; this.editId = editId;
            d = w.S / 4.0;
            U = Math.Max(2, (int)Math.Round(2 * d));
            Text = editId != null ? "修改我的公仔" : "做一隻自己的公仔";
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false; MinimizeBox = false;
            ShowInTaskbar = true; TopMost = true;
            StartPosition = FormStartPosition.Manual;
            BackColor = Pix.Cream;
            DoubleBuffered = true;
            AllowDrop = true;
            titleF = new Font("Microsoft JhengHei UI", 12f, FontStyle.Bold);
            qF = new Font("Microsoft JhengHei UI", 15f, FontStyle.Bold);
            bigF = new Font("Microsoft JhengHei UI", 12f, FontStyle.Bold);
            subF = new Font("Microsoft JhengHei UI", 9f, FontStyle.Bold);
            btnF = new Font("Microsoft JhengHei UI", 11f, FontStyle.Bold);
            smallF = new Font("Microsoft JhengHei UI", 8.5f, FontStyle.Regular);
            ClientSize = new Size(Sc(780), Sc(600));
            KeyPreview = true;
            KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Escape) Cancel(); };
            nameBox = new TextBox();
            nameBox.BorderStyle = BorderStyle.None;
            nameBox.Font = new Font("Microsoft JhengHei UI", 15f, FontStyle.Bold);
            nameBox.BackColor = Color.FromArgb(0xFF, 0xFD, 0xF7);
            nameBox.ForeColor = Pix.TextC;
            nameBox.MaxLength = 10;
            nameBox.Visible = false;
            nameBox.TextChanged += delegate { meta.Name = CuMeta.CleanName(nameBox.Text); RefreshDraftLines(); LayoutBtns(); Invalidate(); };
            Controls.Add(nameBox);
            DragEnter += delegate(object s, DragEventArgs e) { e.Effect = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None; };
            DragDrop += delegate(object s, DragEventArgs e)
            {
                string[] files = e.Data.GetData(DataFormats.FileDrop) as string[];
                if (files == null || files.Length == 0) return;
                if (files[0].EndsWith(".deskpal", StringComparison.OrdinalIgnoreCase)) { bool f = first; Close(); w.CuImportFile(files[0], f); return; }
                LoadImage(files[0], false);
            };
            timer.Interval = 40;
            timer.Tick += delegate { animT += 0.04; if (step >= 2) Invalidate(PreviewRect()); };
            FormClosed += delegate { timer.Stop(); timer.Dispose(); };
            if (editId != null) LoadExisting(editId);
            LayoutBtns();
        }

        int Sc(int v) { return (int)Math.Round(v * d); }

        protected override void SetVisibleCore(bool value)
        {
            if (App.Offscreen) { VVisible = value; base.SetVisibleCore(false); if (value) timer.Start(); return; }
            base.SetVisibleCore(value);
            if (value) timer.Start();
        }
        public void PaintTo(Graphics g)
        {
            Size cs = ClientSize;
            using (Bitmap b = new Bitmap(cs.Width, cs.Height, PixelFormat.Format24bppRgb))
            {
                using (Graphics gg = Graphics.FromImage(b)) { OnPaint(new PaintEventArgs(gg, new Rectangle(0, 0, cs.Width, cs.Height))); if (step == 3) DrawNameText(gg); }
                g.DrawImageUnscaled(b, Left, Top);
            }
        }

        // ================= 草稿 =================
        void LoadExisting(string id)
        {
            CuMeta m = CuStore.Get(id);
            if (m == null) return;
            meta = m.Clone();
            string e2;
            Bitmap b = CuImg.LoadFile(Path.Combine(CuStore.Dir(id), "source.png"), out e2);
            if (b == null) { err = e2; return; }
            SetSource(b);
            Rebuild(false);
            nameBox.Text = meta.Name;
            step = 1;
        }

        public void LoadImage(string path, bool sheet)
        {
            string e2;
            Bitmap b = CuImg.LoadFile(path, out e2);
            if (b == null) { err = e2; step = 0; LayoutBtns(); Invalidate(); return; }
            err = "";
            string keepName = meta.Name, keepPersona = meta.Persona;
            meta = new CuMeta();
            meta.Name = keepName; meta.Persona = keepPersona;
            meta.Sheet = sheet;
            if (!sheet && keepName == "") { string fn = CuMeta.CleanName(Path.GetFileNameWithoutExtension(path)); if (fn.Length > 0 && fn.Length <= 6 && !fn.StartsWith("IMG") && !fn.StartsWith("DSC")) meta.Name = fn; }
            SetSource(b);
            // 小小的圖（多半本來就是像素圖）：像素風、跟內建一樣大的像素；照片：保留原圖（像素風可以自己切）
            if (b.Width <= 64 && b.Height <= 64) { meta.Mode = "pixel"; meta.Sub = 1; }
            else if (!sheet) { meta.Mode = "smooth"; meta.Sub = 2; }
            Rebuild(true);
            if (spr == null) { step = sheet ? 0 : 1; }
            else step = sheet ? 2 : 1;
            nameBox.Text = meta.Name;
            LayoutBtns(); Invalidate();
        }

        void SetSource(Bitmap b)
        {
            if (src != null) src.Dispose();
            src = b;
            srcPx = CuImg.Pixels(b);
            srcAlpha = CuImg.HasAlpha(srcPx, b.Width, b.Height);
            autoKey = -999;
            if (srcDim != null) srcDim.Dispose();
            srcDim = (Bitmap)b.Clone();
        }

        // 去背（快取：強度沒變就不重算）→ 筆刷 → 裁切 → 像素風／原圖 → 切頭身腳
        void Rebuild(bool guessRig)
        {
            if (src == null) return;
            if (meta.Sheet)
            {
                string e2;
                spr = CuSprite.Build(meta, src, out e2);
                err = spr == null ? e2 : "";
                MakeDraft();
                return;
            }
            int key = (srcAlpha && meta.UseAlpha) ? -1 : meta.Tol;
            if (key != autoKey)
            {
                if (key == -1) { autoPx = (int[])srcPx.Clone(); for (int i = 0; i < autoPx.Length; i++) if (((autoPx[i] >> 24) & 255) < 10) autoPx[i] = 0; }
                else
                {
                    int[] solid = (int[])srcPx.Clone();
                    for (int i = 0; i < solid.Length; i++) if (((solid[i] >> 24) & 255) < 128) solid[i] = unchecked((int)0xFFFFFFFF); else solid[i] |= unchecked((int)0xFF000000);
                    autoPx = CuImg.RemoveBg(solid, src.Width, src.Height, meta.Tol);
                }
                autoKey = key;
            }
            viewPx = (int[])autoPx.Clone();
            CuImg.ApplyStrokes(viewPx, srcPx, src.Width, src.Height, meta.Strokes);
            RefreshView();
            BuildSprite(guessRig);
        }

        void RefreshView()
        {
            if (viewBmp != null) viewBmp.Dispose();
            viewBmp = CuImg.FromPixels(viewPx, src.Width, src.Height);
        }

        void BuildSprite(bool guessRig)
        {
            Rectangle bb = CuImg.Bounds(viewPx, src.Width, src.Height, 40);
            if (bb.Width < 2 || bb.Height < 2) { spr = null; err = "去背之後什麼都不剩了：把去背強度調低，或用「補回」筆刷"; MakeDraft(); return; }
            CuCut cut = CuImg.Crop(viewPx, src.Width, src.Height, bb);
            if (meta.Flip) cut = CuImg.Mirror(cut);
            CuSprite s = new CuSprite();
            s.Pixel = meta.Pixel;
            CuCut fin;
            if (s.Pixel) { Color ol; fin = CuImg.ToPixel(cut, meta.Sub, CuImg.HCells, CuImg.WCells, out ol); s.Outline = ol; s.R = meta.Sub; }
            else { fin = CuImg.ToSmooth(cut, CuImg.HCells, CuImg.WCells); s.R = CuImg.SmoothR; Color mc = CuImg.MainColor(fin); s.Outline = Color.FromArgb((int)(mc.R * 0.25 + 17), (int)(mc.G * 0.25 + 19), (int)(mc.B * 0.25 + 31)); }
            if (guessRig)
            {
                double gn, gh; bool conf;
                CuImg.GuessLines(fin, out gn, out gh, out conf);
                meta.Rig = conf; meta.Neck = -1; meta.Hip = -1;
            }
            s.SetStand(fin, meta.Rig, meta.Neck, meta.Hip);
            spr = s;
            err = "";
            MakeDraft();
        }

        void MakeDraft()
        {
            if (spr == null) { draft = null; pv = null; return; }
            CuMeta m = meta.Clone();
            if (m.Id == "") m.Id = "cudraft";
            if (m.Name == "") m.Name = "小公仔";
            draft = Pal.MakeCu(m, spr);
            if (pvw == null) pvw = new World(w.S, Pal.Fallback);
            pv = new Pet(pvw, draft, w.S, 7);
        }

        void RefreshDraftLines() { if (spr != null) MakeDraft(); }

        // ================= 按鈕 =================
        Btn Add(string id, string text, Rectangle r, int kind, bool on)
        {
            Btn b = new Btn(); b.Id = id; b.Text = text; b.R = r; b.Kind = kind; b.On = on; btns.Add(b); return b;
        }
        Btn Find(string id) { foreach (Btn b in btns) if (b.Id == id) return b; return null; }
        Btn At(Point p) { foreach (Btn b in btns) if (b.R.Contains(p) && b.Enabled) return b; return null; }

        Rectangle ContentRect() { return new Rectangle(Sc(30), Sc(150), ClientSize.Width - Sc(60), ClientSize.Height - Sc(150) - Sc(80)); }
        Rectangle LeftRect() { Rectangle c = ContentRect(); return new Rectangle(c.X, c.Y, Sc(400), c.Height); }
        Rectangle RightRect() { Rectangle c = ContentRect(); int x = c.X + Sc(418); return new Rectangle(x, c.Y, c.Right - x, c.Height); }
        Rectangle PreviewRect() { Rectangle r = RightRect(); return new Rectangle(r.X, r.Y, r.Width, Sc(210)); }
        Rectangle SliderRect() { Rectangle r = RightRect(); return new Rectangle(r.X + Sc(10), r.Y + Sc(50), r.Width - Sc(20), Sc(22)); }

        void LayoutBtns()
        {
            btns.Clear();
            int W0 = ClientSize.Width, H0 = ClientSize.Height;
            Rectangle c = ContentRect();
            nameBox.Visible = step == 3 && !App.Offscreen;
            if (step == 0)
            {
                Add("open", "", new Rectangle(c.X, c.Y, c.Width, Sc(200)), 0, false);
                int bw = (c.Width - 2 * Sc(12)) / 3, by = c.Bottom - Sc(40);
                Add("template", "下載動作表範本", new Rectangle(c.X, by, bw, Sc(36)), 4, false);
                Add("sheet", "上傳畫好的動作表…", new Rectangle(c.X + bw + Sc(12), by, bw, Sc(36)), 4, false);
                Add("importpal", "匯入朋友的公仔…", new Rectangle(c.X + 2 * (bw + Sc(12)), by, bw, Sc(36)), 4, false);
            }
            else if (step == 1)
            {
                Rectangle r = RightRect();
                int y = r.Y;
                if (meta.Sheet) { }
                else if (srcAlpha) Add("usealpha", meta.UseAlpha ? "改用自動去背" : "用原本的透明背景", new Rectangle(r.X + Sc(10), y + Sc(42), Sc(170), Sc(30)), 4, false);
                y += Sc(92);
                int bw = Sc(78);
                Add("erase", "擦掉", new Rectangle(r.X + Sc(10), y + Sc(30), bw, Sc(32)), 4, brushOn && brushErase);
                Add("restore", "補回", new Rectangle(r.X + Sc(10) + bw + Sc(8), y + Sc(30), bw, Sc(32)), 4, brushOn && !brushErase);
                Add("bsize", brushSize == 0 ? "筆刷：小" : (brushSize == 1 ? "筆刷：中" : "筆刷：大"), new Rectangle(r.X + Sc(10) + 2 * (bw + Sc(8)), y + Sc(30), Sc(100), Sc(32)), 4, false);
                Add("undo", "復原一筆", new Rectangle(r.X + Sc(10), y + Sc(68), Sc(100), Sc(30)), 4, false).Enabled = meta.Strokes.Count > 0;
                Add("clearbrush", "筆刷全部重來", new Rectangle(r.X + Sc(118), y + Sc(68), Sc(130), Sc(30)), 4, false).Enabled = meta.Strokes.Count > 0;
                if (meta.Sheet) { Btn b1 = Find("erase"); b1.Enabled = false; Find("restore").Enabled = false; Find("bsize").Enabled = false; }
                y += Sc(112);
                int cw = (r.Width - Sc(30)) / 2;
                Add("pixel", "像素風", new Rectangle(r.X + Sc(10), y + Sc(28), cw, Sc(58)), 0, meta.Pixel);
                Add("smooth", "保留原圖", new Rectangle(r.X + Sc(20) + cw, y + Sc(28), cw, Sc(58)), 0, !meta.Pixel);
                if (meta.Pixel) Add("sub", meta.Sub >= 2 ? "細緻像素 ✓" : "細緻像素", new Rectangle(r.X + Sc(10), y + Sc(94), Sc(130), Sc(30)), 4, meta.Sub >= 2);
                Add("flip", "左右翻轉", new Rectangle(r.X + Sc(148), y + Sc(94), Sc(110), Sc(30)), 4, meta.Flip);
            }
            else if (step == 2)
            {
                Rectangle l = LeftRect(), pr = PreviewRect();
                if (!meta.Sheet) Add("rig", meta.Rig ? "✓ 用兩條線分出頭、身體、腳" : "用兩條線分出頭、身體、腳", new Rectangle(l.X, l.Y, l.Width, Sc(32)), 4, meta.Rig);
                string[] an = { "walk", "jump", "sleep", "happy", "held" };
                string[] at = { "走路", "跳", "睡覺", "開心", "被抓" };
                int bw = (pr.Width - 4 * Sc(6)) / 5;
                for (int i = 0; i < an.Length; i++) Add("anim:" + an[i], at[i], new Rectangle(pr.X + i * (bw + Sc(6)), pr.Bottom + Sc(10), bw, Sc(32)), 4, anim == an[i]);
            }
            else
            {
                Rectangle r = ContentRect();
                Rectangle nf = new Rectangle(r.X + Sc(150), r.Y + Sc(6), Sc(260), Sc(40));
                nameBox.Bounds = new Rectangle(nf.X + Sc(12), nf.Y + (nf.Height - nameBox.PreferredHeight) / 2, nf.Width - Sc(24), nameBox.PreferredHeight);
                int cw = (r.Width - 2 * Sc(12)) / 3, ch = Sc(82), y0 = r.Y + Sc(84);
                for (int i = 0; i < Pal.Personas.Length; i++)
                {
                    string id = Pal.Personas[i];
                    Add("persona:" + id, Pal.PersonaName(id), new Rectangle(r.X + (i % 3) * (cw + Sc(12)), y0 + (i / 3) * (ch + Sc(12)), cw, ch), 0, meta.Persona == id);
                }
            }
            int bby = H0 - Sc(64), bh = Sc(44);
            Add(step > 0 ? "back" : "cancel", step > 0 ? "上一步" : "取消", new Rectangle(Sc(30), bby, Sc(130), bh), 2, false);
            Btn nx = Add("next", step < 3 ? "下一步" : (editId != null ? "存好了！" : "完成！"), new Rectangle(W0 - Sc(30) - Sc(160), bby, Sc(160), bh), 3, false);
            nx.Enabled = step == 0 ? spr != null : (step == 3 ? spr != null && meta.Name.Trim() != "" : spr != null);
        }

        // 按按鈕（滑鼠、測試用的 custom 指令都走這裡）
        public void Press(string id)
        {
            Btn b = Find(id);
            if (b != null && !b.Enabled) return;
            switch (id)
            {
                case "open": PickImage(false); return;
                case "sheet": PickImage(true); return;
                case "template": w.CuSaveTemplateDialog(); return;
                case "importpal": { bool f = first; Close(); w.CuImportDialog(f); } return;
                case "usealpha": meta.UseAlpha = !meta.UseAlpha; Rebuild(false); break;
                case "erase": brushOn = !(brushOn && brushErase); brushErase = true; break;
                case "restore": brushOn = !(brushOn && !brushErase); brushErase = false; break;
                case "bsize": brushSize = (brushSize + 1) % 3; break;
                case "undo": if (meta.Strokes.Count > 0) { int n = meta.Strokes.Count, keep = n - 1; while (keep > 0 && meta.Strokes[keep - 1].Length > 4 && meta.Strokes[keep - 1][4] == meta.Strokes[n - 1][4]) keep--; meta.Strokes.RemoveRange(keep, n - keep); Rebuild(false); } break;
                case "clearbrush": meta.Strokes.Clear(); Rebuild(false); break;
                case "pixel": meta.Mode = "pixel"; BuildSprite(false); break;
                case "smooth": meta.Mode = "smooth"; BuildSprite(false); break;
                case "sub": meta.Sub = meta.Sub >= 2 ? 1 : 2; BuildSprite(false); break;
                case "flip": meta.Flip = !meta.Flip; if (meta.Sheet) Rebuild(false); else BuildSprite(false); break;
                case "rig": meta.Rig = !meta.Rig; BuildSprite(false); break;
                case "back": if (step > 0) step--; if (step == 1 && meta.Sheet) step = 0; break;
                case "cancel": Cancel(); return;
                case "next":
                    if (step < 3) { step++; if (step == 1 && meta.Sheet) step = 2; }
                    else { Finish(); return; }
                    break;
                default:
                    if (id.StartsWith("anim:")) { anim = id.Substring(5); animT = 0; }
                    else if (id.StartsWith("persona:")) { meta.Persona = id.Substring(8); RefreshDraftLines(); }
                    else return;
                    break;
            }
            LayoutBtns(); hoverId = ""; Invalidate();
        }

        void PickImage(bool sheet)
        {
            if (App.Offscreen) { App.Log("custom: file dialog skipped (offscreen)"); return; }
            using (OpenFileDialog dlg = new OpenFileDialog())
            {
                dlg.Title = sheet ? "選畫好的動作表" : "選一張照片或圖片";
                dlg.Filter = "圖片（PNG、JPG、GIF、BMP）|*.png;*.jpg;*.jpeg;*.gif;*.bmp|所有檔案|*.*";
                dlg.InitialDirectory = World.UserFolder(Environment.SpecialFolder.MyPictures, "", "Pictures");
                if (dlg.ShowDialog(this) == DialogResult.OK) LoadImage(dlg.FileName, sheet);
            }
        }

        // 外面（pipe 測試指令）設定
        public void SetTol(int t) { meta.Tol = Math.Max(0, Math.Min(100, t)); if (srcAlpha) meta.UseAlpha = false; Rebuild(false); LayoutBtns(); Invalidate(); }
        public void SetLines(double neck, double hip) { meta.Neck = neck; meta.Hip = hip; meta.Rig = true; BuildSprite(false); LayoutBtns(); Invalidate(); }
        public void SetName(string s) { nameBox.Text = s; meta.Name = CuMeta.CleanName(s); RefreshDraftLines(); LayoutBtns(); Invalidate(); }
        public void Brush(bool erase, double x, double y, double r) { if (src == null) return; meta.Strokes.Add(new double[] { x, y, r, erase ? 1 : 0, meta.Strokes.Count }); Rebuild(false); LayoutBtns(); Invalidate(); }
        public void SetStep(int s) { step = Math.Max(0, Math.Min(3, s)); LayoutBtns(); Invalidate(); }
        public void SetAnim(string a, double t) { anim = a; animT = t; LayoutBtns(); Invalidate(); }
        public int Step { get { return step; } }

        void Cancel()
        {
            bool f = first;
            Close();
            if (f) w.ShowSetup(true);   // 第一次設定時按取消：回到設定視窗
        }

        void Finish()
        {
            if (spr == null || src == null) return;
            CuMeta m = meta.Clone();
            if (m.Name.Trim() == "") return;
            bool edit = editId != null;
            m.Id = edit ? editId : CuStore.NewId();
            // 筆刷：只留 x y r 擦／補（第五個數字是哪一筆，存檔不用）
            List<double[]> st = new List<double[]>();
            foreach (double[] s in m.Strokes) st.Add(new double[] { s[0], s[1], s[2], s[3] });
            m.Strokes = st;
            try
            {
                CuStore.Save(m, src, spr);
                App.Log("custom saved " + m.Id + " name=" + m.Name + " persona=" + m.Persona + " mode=" + m.Mode + " rig=" + m.Rig + " sheet=" + m.Sheet);
            }
            catch (Exception ex) { err = "存不起來：" + ex.Message; Invalidate(); return; }
            spr = null;   // 已經交給 CuStore 了
            bool f = first;
            string id = m.Id;
            Close();
            w.CuCreated(id, f, edit);
        }

        // ================= 滑鼠：按鈕、拖去背強度、筆刷、拖兩條線 =================
        Rectangle ViewRect()
        {
            Rectangle l = LeftRect();
            if (src == null) return l;
            double s = Math.Min(l.Width / (double)src.Width, l.Height / (double)src.Height);
            int vw = (int)(src.Width * s), vh = (int)(src.Height * s);
            return new Rectangle(l.X + (l.Width - vw) / 2, l.Y + (l.Height - vh) / 2, vw, vh);
        }

        Rectangle SpriteRect()
        {
            Rectangle l = LeftRect();
            l = new Rectangle(l.X, l.Y + Sc(42), l.Width, l.Height - Sc(42));
            if (spr == null) return l;
            double s = Math.Min((l.Width - Sc(80)) / (double)spr.W, (l.Height - Sc(16)) / (double)spr.H);
            if (spr.Pixel) s = Math.Max(1, Math.Floor(s));
            int vw = (int)(spr.W * s), vh = (int)(spr.H * s);
            return new Rectangle(l.X + (l.Width - vw) / 2, l.Y + (l.Height - vh) / 2, vw, vh);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left) return;
            if (step == 1 && !meta.Sheet && !(srcAlpha && meta.UseAlpha) && SliderRect().Contains(e.Location)) { SliderAt(e.X, false); Capture = true; dragWhich = -1; return; }
            if (step == 1 && brushOn && ViewRect().Contains(e.Location)) { painting = true; lastPaint = e.Location; PaintAt(e.Location, true); return; }
            if (step == 2 && meta.Rig && spr != null)
            {
                Rectangle sr = SpriteRect();
                int ny = sr.Y + (int)(spr.NeckF * sr.Height), hy = sr.Y + (int)(spr.HipF * sr.Height);
                if (e.X > sr.X - Sc(60) && e.X < sr.Right + Sc(60))
                {
                    if (Math.Abs(e.Y - ny) < Sc(10)) { dragLine = true; dragWhich = 0; return; }
                    if (Math.Abs(e.Y - hy) < Sc(10)) { dragLine = true; dragWhich = 1; return; }
                }
            }
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (Capture && dragWhich == -1 && step == 1) { SliderAt(e.X, false); return; }
            if (painting) { if (Math.Abs(e.X - lastPaint.X) + Math.Abs(e.Y - lastPaint.Y) >= Sc(3)) { lastPaint = e.Location; PaintAt(e.Location, false); } return; }
            if (dragLine && spr != null)
            {
                Rectangle sr = SpriteRect();
                double f = Math.Max(0.06, Math.Min(0.96, (e.Y - sr.Y) / (double)sr.Height));
                if (dragWhich == 0) meta.Neck = Math.Min(f, spr.HipF - 0.08); else meta.Hip = Math.Max(f, spr.NeckF + 0.08);
                if (meta.Neck < 0) meta.Neck = spr.NeckF;
                if (meta.Hip < 0) meta.Hip = spr.HipF;
                BuildSprite(false); Invalidate();
                return;
            }
            Btn b = At(e.Location);
            string h = b != null ? b.Id : "";
            if (h != hoverId) { hoverId = h; Invalidate(); }
            bool lineHot = false;
            if (step == 2 && meta.Rig && spr != null)
            {
                Rectangle sr = SpriteRect();
                int ny = sr.Y + (int)(spr.NeckF * sr.Height), hy = sr.Y + (int)(spr.HipF * sr.Height);
                lineHot = Math.Abs(e.Y - ny) < Sc(10) || Math.Abs(e.Y - hy) < Sc(10);
            }
            Cursor = h != "" ? Cursors.Hand : (lineHot ? Cursors.SizeNS : (step == 1 && brushOn && ViewRect().Contains(e.Location) ? Cursors.Cross : Cursors.Default));
            if (step == 1 && brushOn) Invalidate(LeftRect());
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (e.Button != MouseButtons.Left) return;
            if (Capture && dragWhich == -1 && step == 1) { Capture = false; dragWhich = 0; SliderAt(e.X, true); return; }
            if (painting) { painting = false; BuildSprite(false); LayoutBtns(); Invalidate(); return; }
            if (dragLine) { dragLine = false; return; }
            Btn b = At(e.Location);
            if (b != null) Press(b.Id);
        }

        void SliderAt(int x, bool commit)
        {
            Rectangle s = SliderRect();
            int t = (int)Math.Round(Math.Max(0, Math.Min(1, (x - s.X) / (double)s.Width)) * 100);
            meta.Tol = t;
            if (commit) { Rebuild(false); LayoutBtns(); }
            Invalidate();
        }

        double BrushR() { return brushSize == 0 ? 0.012 : (brushSize == 1 ? 0.028 : 0.06); }

        void PaintAt(Point p, bool newStroke)
        {
            Rectangle v = ViewRect();
            double x = (p.X - v.X) / (double)v.Width, y = (p.Y - v.Y) / (double)v.Height;
            double group = newStroke ? meta.Strokes.Count : (meta.Strokes.Count > 0 && meta.Strokes[meta.Strokes.Count - 1].Length > 4 ? meta.Strokes[meta.Strokes.Count - 1][4] : meta.Strokes.Count);
            double[] st = { x, y, BrushR(), brushErase ? 1 : 0, group };
            meta.Strokes.Add(st);
            List<double[]> one = new List<double[]>(); one.Add(st);
            CuImg.ApplyStrokes(viewPx, srcPx, src.Width, src.Height, one);
            RefreshView();
            Invalidate(LeftRect());
        }

        // ================= 畫 =================
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.None;
            int W0 = ClientSize.Width, H0 = ClientSize.Height, F = 4 * U, crown = Sc(56);
            Pix.Wood(g, 0, 0, W0, H0, U, false, 23);
            Pix.Panel(g, F, crown, W0 - 2 * F, H0 - crown - F, U, false);
            string t = editId != null ? "修改我的公仔" : "做一隻自己的公仔";
            int tw = Pix.TextW(t, titleF), plw = tw + 14 * U, plh = Sc(34);
            Rectangle pr = new Rectangle((W0 - plw) / 2, (crown - plh) / 2 + U / 2, plw, plh);
            Pix.Plate(g, t, titleF, pr, U);
            Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.X - 9 * U, pr.Y + plh / 2 - 2 * U, U);
            Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.Right + 4 * U, pr.Y + plh / 2 - 2 * U, U);
            Steps(g, W0, Sc(68));
            string q, hint;
            switch (step)
            {
                case 0: q = "選一張照片"; hint = "你家的貓、狗、娃娃、自己畫的角色都可以"; break;
                case 1: q = "去背"; hint = srcAlpha && meta.UseAlpha ? "這張本來就是透明背景，直接用 ✓（有沒去乾淨的，用筆刷修）" : "灰格子＝透明。沒去乾淨就把強度調高、或用筆刷擦掉；主角被吃掉就調低、或用「補回」"; break;
                case 2: q = "動起來"; hint = meta.Sheet ? "動作表的每一格會直接拿來用；空格會自動補動畫" : "兩條線把圖切成頭、身體、腳：走路會擺腳、點頭（拖線調位置）"; break;
                default: q = "取名字、選個性"; hint = "個性會決定他講什麼話、怎麼動"; break;
            }
            PixText.DrawText(g, q, qF, new Rectangle(0, Sc(98), W0, Sc(28)), Pix.TextC, Pix.Mid);
            PixText.DrawText(g, hint, subF, new Rectangle(Sc(20), Sc(126), W0 - Sc(40), Sc(18)), Pix.C(0x9A6338), Pix.Mid | TextFormatFlags.EndEllipsis);
            if (step == 0) PaintPick(g);
            else if (step == 1) PaintBg(g);
            else if (step == 2) PaintRig(g);
            else PaintName(g);
            foreach (Btn b in btns) DrawBtn(g, b);
            if (err != "") PixText.DrawText(g, err, subF, new Rectangle(Sc(170), H0 - Sc(64), W0 - Sc(370), Sc(44)), Pix.C(0xC0392B), TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
        }

        void Steps(Graphics g, int W0, int y)
        {
            string[] names = { "選照片", "去背", "動起來", "取名字" };
            int n = names.Length, pw = Sc(104), ph = Sc(26), gap = Sc(14), x0 = (W0 - n * pw - (n - 1) * gap) / 2;
            for (int i = 0; i < n; i++)
            {
                int x = x0 + i * (pw + gap);
                if (i > 0) for (int sx = x - gap + U; sx + U <= x - U; sx += 2 * U) Pix.Box(g, Pix.C(0xD8BF94), sx, y + ph / 2 - U / 2, U, U);
                Pix.Round(g, i == step ? Pix.C(0x8A5A2A) : Pix.C(0xC9B08A), x, y, pw, ph, U);
                Pix.Box(g, i == step ? Pix.C(0xF6C453) : (i < step ? Pix.C(0xD9F0C4) : Pix.C(0xF3EADB)), x + U, y + U, pw - 2 * U, ph - 2 * U);
                string s = (i + 1) + ". " + names[i];
                int sw = Pix.TextW(s, subF), cx = x + (pw - sw) / 2;
                if (i < step) { cx += 3 * U; Pix.Mono(g, Pix.CHECK, Pix.C(0x3F8A30), cx - 7 * U, y + ph / 2 - 3 * U, U); }
                PixText.DrawText(g, s, subF, new Rectangle(cx, y, sw + 4, ph), i <= step ? Pix.TextC : Pix.Dim, Pix.LeftMid);
            }
        }

        // 第一步：大大的「拖進來／點這裡」
        void PaintPick(Graphics g)
        {
            Btn o = Find("open");
            if (o == null) return;
            Rectangle r = o.R;
            bool hot = hoverId == "open";
            Pix.Box(g, hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0), r.X, r.Y, r.Width, r.Height);
            Color dash = Pix.C(0xC08A2C);
            for (int x = r.X; x < r.Right; x += 4 * U) { Pix.Box(g, dash, x, r.Y, 2 * U, U); Pix.Box(g, dash, x, r.Bottom - U, 2 * U, U); }
            for (int y = r.Y; y < r.Bottom; y += 4 * U) { Pix.Box(g, dash, r.X, y, U, 2 * U); Pix.Box(g, dash, r.Right - U, y, U, 2 * U); }
            Dictionary<char, Color> pal = new Dictionary<char, Color>();
            pal['k'] = Pix.Ink; pal['w'] = Pix.C(0xFFFDF7); pal['b'] = Pix.C(0xBFE3F2); pal['p'] = Pix.C(0xF27A90); pal['o'] = Pix.C(0xE8A25A); pal['y'] = Pix.C(0xF6C453); pal['g'] = Pix.C(0x7CC36A);
            int c = Math.Max(3, Sc(5)), aw = CAT[0].Length * c;
            Pix.Art(g, CAT, pal, r.X + (r.Width - aw) / 2, r.Y + Sc(22), c);
            PixText.DrawText(g, "把照片拖進來，或點這裡選一張", bigF, new Rectangle(r.X, r.Y + Sc(22) + CAT.Length * c + Sc(10), r.Width, Sc(28)), Pix.TextC, Pix.Mid);
            PixText.DrawText(g, "PNG・JPG・GIF・BMP 都可以", subF, new Rectangle(r.X, r.Y + Sc(22) + CAT.Length * c + Sc(40), r.Width, Sc(20)), Pix.C(0x9A6338), Pix.Mid);
            // 使用者指定的原字（v011 SPEC §4），不要改字
            PixText.DrawText(g, CopyrightNote, subF, new Rectangle(r.X, r.Y + Sc(22) + CAT.Length * c + Sc(62), r.Width, Sc(20)), Pix.C(0xB04040), Pix.Mid);
            if (PhotoNoAlpha()) PixText.DrawText(g, PortraitTip, subF, new Rectangle(r.X, r.Y + Sc(22) + CAT.Length * c + Sc(82), r.Width, Sc(20)), Pix.C(0x9A6338), Pix.Mid);   // 選過一張沒透明的照片
            // 小技巧
            Rectangle tip = new Rectangle(r.X, r.Bottom + Sc(14), r.Width, Sc(78));
            Pix.Round(g, Pix.C(0xE6D3B0), tip.X, tip.Y, tip.Width, tip.Height, U);
            Pix.Box(g, Pix.C(0xFFF8EA), tip.X + U, tip.Y + U, tip.Width - 2 * U, tip.Height - 2 * U);
            string[] tips = {
                "・去背好的透明 PNG 效果最好；主角站在單純的背景前（白牆、地板）也很好去背。",
                "・背景很亂的照片：可以先用免費的線上去背工具做成透明 PNG，再放進來。",
                "・照片只存在你的電腦裡，不會上傳到任何地方。" };
            for (int i = 0; i < tips.Length; i++) PixText.DrawText(g, tips[i], subF, new Rectangle(tip.X + Sc(12), tip.Y + Sc(8) + i * Sc(22), tip.Width - Sc(24), Sc(20)), Pix.TextC, Pix.LeftMid | TextFormatFlags.EndEllipsis);
            Btn tb = Find("template");
            if (tb != null) PixText.DrawText(g, "進階：自己畫每個動作（動作表）、或匯入朋友傳來的公仔", smallF, new Rectangle(r.X, tb.R.Y - Sc(22), r.Width, Sc(18)), Pix.C(0x9A6338), Pix.LeftMid);
        }

        public const string CopyrightNote = "千萬不要使用有版權的照片";
        bool PhotoNoAlpha() { return spr != null && !meta.Sheet && !srcAlpha; }
        public const string PortraitTip = "人像照先在手機去背，用胸口以上的最可愛";

        static readonly string[] CAT = {
            "..kk..........kk..",
            ".kook........kook.",
            ".kopok......kopok.",
            ".kooookkkkkkooook.",
            "kooooooooooooooook",
            "kooooooooooooooook",
            "koookkooooookkoook",
            "kookwkooooookwkook",
            "koookkooooookkoook",
            "koooooooppoooooook",
            "kooooooookoooooook",
            ".kooooookkkooooook",
            "..kkooooooooookk..",
            "....kkkkkkkkkk...." };

        // 棋盤格（透明的地方）
        static void Checker(Graphics g, Rectangle r, int cell)
        {
            using (SolidBrush a = new SolidBrush(Color.FromArgb(0xEE, 0xEA, 0xE2)))
            using (SolidBrush b = new SolidBrush(Color.FromArgb(0xD9, 0xD3, 0xC8)))
                for (int y = r.Y, j = 0; y < r.Bottom; y += cell, j++)
                    for (int x = r.X, i = 0; x < r.Right; x += cell, i++)
                        g.FillRectangle(((i + j) & 1) == 0 ? a : b, x, y, Math.Min(cell, r.Right - x), Math.Min(cell, r.Bottom - y));
        }

        // 第二步：去背
        void PaintBg(Graphics g)
        {
            Rectangle l = LeftRect();
            Pix.Round(g, Pix.C(0x8A6A4A), l.X - U, l.Y - U, l.Width + 2 * U, l.Height + 2 * U, U);
            Checker(g, l, Sc(12));
            if (meta.Sheet)
            {
                if (src != null) { Rectangle v = ViewRect(); g.DrawImage(src, v); }
            }
            else if (src != null && viewBmp != null)
            {
                Rectangle v = ViewRect();
                g.InterpolationMode = InterpolationMode.HighQualityBilinear;
                // 被去掉的部分淡淡地留著（知道哪裡可以補回）
                using (ImageAttributes ia = new ImageAttributes())
                {
                    ColorMatrix cm = new ColorMatrix(); cm.Matrix33 = 0.13f;
                    ia.SetColorMatrix(cm);
                    g.DrawImage(srcDim, v, 0, 0, src.Width, src.Height, GraphicsUnit.Pixel, ia);
                }
                g.DrawImage(viewBmp, v);
                g.InterpolationMode = InterpolationMode.Default;
                if (brushOn)
                {
                    Point cp = PointToClient(Cursor.Position);
                    if (v.Contains(cp))
                    {
                        float rr = (float)(BrushR() * Math.Max(v.Width, v.Height));
                        using (Pen pp = new Pen(brushErase ? Color.FromArgb(220, 200, 60, 60) : Color.FromArgb(220, 50, 140, 70), 2f))
                        { g.SmoothingMode = SmoothingMode.AntiAlias; g.DrawEllipse(pp, cp.X - rr, cp.Y - rr, 2 * rr, 2 * rr); g.SmoothingMode = SmoothingMode.None; }
                    }
                }
            }
            Rectangle r = RightRect();
            // 背景
            Section(g, "背景", r.X, r.Y);
            if (meta.Sheet) PixText.DrawText(g, "動作表每一格會自己去背", subF, new Rectangle(r.X + Sc(10), r.Y + Sc(30), r.Width - Sc(20), Sc(20)), Pix.TextC, Pix.LeftMid);
            else if (srcAlpha && meta.UseAlpha) PixText.DrawText(g, "本來就是透明背景 ✓", subF, new Rectangle(r.X + Sc(190), r.Y + Sc(42), r.Width - Sc(200), Sc(30)), Pix.C(0x3F8A30), Pix.LeftMid);
            else
            {
                Rectangle s = SliderRect();
                PixText.DrawText(g, "去背強度  " + meta.Tol, subF, new Rectangle(r.X + Sc(10), r.Y + Sc(26), r.Width, Sc(20)), Pix.TextC, Pix.LeftMid);
                Pix.Round(g, Pix.C(0x8A6A4A), s.X, s.Y + s.Height / 2 - 2 * U, s.Width, 4 * U, U);
                Pix.Box(g, Pix.C(0xF6C453), s.X + U, s.Y + s.Height / 2 - U, (int)((s.Width - 2 * U) * meta.Tol / 100.0), 2 * U);
                int kx = s.X + (int)(s.Width * meta.Tol / 100.0) - 4 * U;
                Pix.Round(g, Pix.Ink, kx, s.Y, 8 * U, s.Height, U);
                Pix.Box(g, Pix.C(0xFFFBF0), kx + U, s.Y + U, 6 * U, s.Height - 2 * U);
                PixText.DrawText(g, "少去一點", smallF, new Rectangle(s.X, s.Bottom + U, Sc(80), Sc(16)), Pix.C(0x9A6338), Pix.LeftMid);
                PixText.DrawText(g, "多去一點", smallF, new Rectangle(s.Right - Sc(80), s.Bottom + U, Sc(80), Sc(16)), Pix.C(0x9A6338), TextFormatFlags.Right | TextFormatFlags.VerticalCenter);
            }
            Section(g, "修一下（在左邊的圖上塗）", r.X, r.Y + Sc(92));
            Section(g, "風格", r.X, r.Y + Sc(204));
            // 沒有透明的照片（人像照直接去背常常不乾淨，人像測試 v011\humantest）：提醒先在手機去背
            if (PhotoNoAlpha()) PixText.DrawText(g, PortraitTip, subF, new Rectangle(r.X, r.Y + Sc(346), r.Width, Sc(36)), Pix.C(0x9A6338), TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.WordBreak);
            // 實際大小預覽（桌面上就是這麼大）：左邊圖的右下角一小格
            if (spr != null)
            {
                int mw = Sc(120), mh = Sc(104);
                Rectangle mini = new Rectangle(l.Right - mw - Sc(6), l.Bottom - mh - Sc(6), mw, mh);
                Pix.Round(g, Pix.C(0x8A6A4A), mini.X - U, mini.Y - U, mini.Width + 2 * U, mini.Height + 2 * U, U);
                using (LinearGradientBrush lb = new LinearGradientBrush(mini, Color.FromArgb(0x7D, 0x9E, 0xC8), Color.FromArgb(0x5B, 0x7D, 0xA8), 90f)) g.FillRectangle(lb, mini);
                using (SolidBrush bar = new SolidBrush(Color.FromArgb(0x20, 0x22, 0x2A))) g.FillRectangle(bar, mini.X, mini.Bottom - Sc(16), mini.Width, Sc(16));
                Pet.CuDrawStill(g, spr, mini.X + mini.Width / 2.0, mini.Bottom - Sc(16), w.S, false, false, Color.White);
                PixText.DrawText(g, "桌面上的大小", smallF, new Rectangle(mini.X, mini.Bottom - Sc(16), mini.Width, Sc(16)), Color.White, Pix.Mid);
            }
        }

        void Section(Graphics g, string s, int x, int y)
        {
            PixText.DrawText(g, s, btnF, new Rectangle(x, y, Sc(320), Sc(24)), Pix.TextC, Pix.LeftMid);
            Pix.Box(g, Pix.C(0xE6D3B0), x, y + Sc(24), RightRect().Width, U);
        }

        // 第三步：兩條線＋動起來的預覽
        void PaintRig(Graphics g)
        {
            Rectangle l = LeftRect();
            if (spr == null) return;
            Rectangle area = new Rectangle(l.X, l.Y + Sc(42), l.Width, l.Height - Sc(42));
            Pix.Round(g, Pix.C(0x8A6A4A), area.X - U, area.Y - U, area.Width + 2 * U, area.Height + 2 * U, U);
            Checker(g, area, Sc(12));
            if (meta.Sheet)
            {
                // 動作表：每一格的結果
                int n = CuSprite.SheetKeys.Length, cols = 4, cw = area.Width / cols, chh = area.Height / 2;
                for (int i = 0; i < n; i++)
                {
                    Rectangle c = new Rectangle(area.X + (i % cols) * cw, area.Y + (i / cols) * chh, cw, chh);
                    Bitmap fb;
                    string key = CuSprite.SheetKeys[i];
                    bool has = spr.Frames.TryGetValue(key, out fb);
                    if (has)
                    {
                        double s = Math.Min((c.Width - Sc(16)) / (double)fb.Width, (c.Height - Sc(36)) / (double)fb.Height);
                        g.InterpolationMode = spr.Pixel ? InterpolationMode.NearestNeighbor : InterpolationMode.HighQualityBicubic;
                        g.PixelOffsetMode = PixelOffsetMode.Half;
                        g.DrawImage(fb, new Rectangle(c.X + (c.Width - (int)(fb.Width * s)) / 2, c.Y + Sc(8), (int)(fb.Width * s), (int)(fb.Height * s)));
                        g.PixelOffsetMode = PixelOffsetMode.Default;
                    }
                    PixText.DrawText(g, CuSprite.SheetLabels[i] + (has ? "" : "（自動）"), subF, new Rectangle(c.X, c.Bottom - Sc(24), c.Width, Sc(20)), has ? Pix.TextC : Pix.Dim, Pix.Mid);
                }
            }
            else
            {
                Rectangle sr = SpriteRect();
                g.InterpolationMode = spr.Pixel ? InterpolationMode.NearestNeighbor : InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.Half;
                g.DrawImage(spr.Stand, sr);
                g.PixelOffsetMode = PixelOffsetMode.Default;
                if (meta.Rig)
                {
                    int ny = sr.Y + (int)(spr.NeckF * sr.Height), hy = sr.Y + (int)(spr.HipF * sr.Height);
                    Line(g, area, ny, Pix.C(0xE2557A), "頭", "身體");
                    Line(g, area, hy, Pix.C(0x3D7BD9), "身體", "腳");
                    // 兩隻腳的分界（虛線）
                    int sx = sr.X + (int)(spr.Split / (double)spr.W * sr.Width);
                    using (Pen p = new Pen(Color.FromArgb(160, 0x3D, 0x7B, 0xD9), Math.Max(1, U / 2))) { p.DashPattern = new float[] { 3, 3 }; g.DrawLine(p, sx, hy, sx, sr.Bottom); }
                }
            }
            // 右邊：動起來
            Rectangle pr = PreviewRect();
            DrawStage(g, pr);
            PixText.DrawText(g, meta.Sheet ? "空著的格子用「站」那格自動動起來" : (meta.Rig ? "上下拖粉紅線、藍線，對準脖子和腿" : "沒切線：整隻一起搖搖晃晃（也很可愛）"), subF,
                new Rectangle(pr.X, pr.Bottom + Sc(50), pr.Width, Sc(40)), Pix.C(0x9A6338), TextFormatFlags.HorizontalCenter | TextFormatFlags.Top | TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
        }

        void Line(Graphics g, Rectangle area, int y, Color c, string up, string down)
        {
            Pix.Box(g, c, area.X, y - U / 2, area.Width, Math.Max(2, U));
            int tw = Math.Max(Pix.TextW(up, smallF), Pix.TextW(down, smallF)) + Sc(14);
            Rectangle tag = new Rectangle(area.Right - tw - Sc(4), y - Sc(30), tw, Sc(58));
            Pix.Round(g, c, tag.X, tag.Y + Sc(8), tag.Width, Sc(18), U);
            Pix.Round(g, c, tag.X, tag.Y + Sc(32), tag.Width, Sc(18), U);
            PixText.DrawText(g, "▲ " + up, smallF, new Rectangle(tag.X, tag.Y + Sc(8), tag.Width, Sc(18)), Color.White, Pix.Mid);
            PixText.DrawText(g, "▼ " + down, smallF, new Rectangle(tag.X, tag.Y + Sc(32), tag.Width, Sc(18)), Color.White, Pix.Mid);
            // 左邊的把手
            Pix.Round(g, c, area.X - U, y - 3 * U, 6 * U, 6 * U, U);
            Pix.Box(g, Color.White, area.X + U, y - U, 2 * U, 2 * U);
        }

        // 小舞台：桌面色的背景＋公仔照選的動作動
        void DrawStage(Graphics g, Rectangle pr)
        {
            Pix.Round(g, Pix.C(0x8A6A4A), pr.X - U, pr.Y - U, pr.Width + 2 * U, pr.Height + 2 * U, U);
            using (LinearGradientBrush lb = new LinearGradientBrush(pr, Color.FromArgb(0x8A, 0xAB, 0xD4), Color.FromArgb(0x5B, 0x7D, 0xA8), 90f)) g.FillRectangle(lb, pr);
            using (SolidBrush fl = new SolidBrush(Color.FromArgb(0x20, 0x22, 0x2A))) g.FillRectangle(fl, pr.X, pr.Bottom - Sc(18), pr.Width, Sc(18));
            if (pv == null) return;
            GraphicsState st = g.Save();
            g.SetClip(pr);
            int ps = Math.Max(2, w.S * 2);
            pv.CuPreview(g, pr.X + pr.Width / 2.0, pr.Bottom - Sc(18), ps, anim, animT, pr.Width / 2.0 - Sc(50));
            g.Restore(st);
        }

        // 第四步：名字＋個性
        void PaintName(Graphics g)
        {
            Rectangle r = ContentRect();
            PixText.DrawText(g, "他叫什麼名字？", bigF, new Rectangle(r.X, r.Y + Sc(6), Sc(150), Sc(40)), Pix.TextC, Pix.LeftMid);
            Rectangle nf = new Rectangle(r.X + Sc(150), r.Y + Sc(6), Sc(260), Sc(40));
            Pix.Round(g, Pix.C(0x8A6A4A), nf.X, nf.Y, nf.Width, nf.Height, U);
            Pix.Box(g, Color.FromArgb(0xFF, 0xFD, 0xF7), nf.X + U, nf.Y + U, nf.Width - 2 * U, nf.Height - 2 * U);
            if (meta.Name == "") PixText.DrawText(g, "例如：小黑、麻糬、阿肥", subF, new Rectangle(nf.X + Sc(14), nf.Y, nf.Width, nf.Height), Pix.Dim, Pix.LeftMid);
            PixText.DrawText(g, "最多 10 個字", smallF, new Rectangle(nf.Right + Sc(10), nf.Y, Sc(120), nf.Height), Pix.C(0x9A6338), Pix.LeftMid);
            PixText.DrawText(g, "個性", bigF, new Rectangle(r.X, r.Y + Sc(54), Sc(150), Sc(26)), Pix.TextC, Pix.LeftMid);
            // 選到的個性：他會這樣跟你打招呼
            if (draft != null)
            {
                string[] hi;
                if (draft.Lines.TryGetValue("hi", out hi) && hi.Length > 0)
                {
                    Rectangle say = new Rectangle(r.X, r.Bottom - Sc(56), r.Width, Sc(50));
                    Pix.Round(g, Pix.C(0xE6D3B0), say.X, say.Y, say.Width, say.Height, U);
                    Pix.Box(g, Pix.C(0xFFF8EA), say.X + U, say.Y + U, say.Width - 2 * U, say.Height - 2 * U);
                    Pet.CuDrawStill(g, spr, say.X + Sc(36), say.Bottom - Sc(4), Math.Max(1, w.S / 2 + 1), false, false, Color.White);
                    PixText.DrawText(g, (meta.Name == "" ? "他" : meta.Name) + "：「" + World.NoEmoji(hi[0]) + "」", btnF, new Rectangle(say.X + Sc(70), say.Y, say.Width - Sc(80), say.Height), Pix.TextC, Pix.LeftMid | TextFormatFlags.EndEllipsis);
                }
            }
        }

        // 離屏截圖：TextBox 不會畫出來，自己畫名字
        void DrawNameText(Graphics g)
        {
            if (meta.Name == "") return;
            Rectangle r = ContentRect();
            Rectangle nf = new Rectangle(r.X + Sc(150), r.Y + Sc(6), Sc(260), Sc(40));
            PixText.DrawText(g, meta.Name, nameBox.Font, new Rectangle(nf.X + Sc(12), nf.Y, nf.Width - Sc(24), nf.Height), Pix.TextC, Pix.LeftMid);
        }

        void DrawBtn(Graphics g, Btn b)
        {
            Rectangle r = b.R;
            bool hot = b.Id == hoverId && b.Enabled;
            if (b.Id == "open") return;   // 第一步的大框自己畫
            if (b.Kind >= 2)
            {
                bool small = b.Kind == 4;
                Color face = !b.Enabled ? Pix.C(0xE9E0D0) : (b.Kind == 3 ? (hot ? Pix.C(0xFFD36A) : Pix.C(0xF6C453)) : (b.On ? Pix.C(0xFFE08A) : (hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0))));
                Color shade = !b.Enabled ? Pix.C(0xD3C7B2) : (b.Kind == 3 || b.On ? Pix.C(0xC8902C) : Pix.C(0xDCC6A2));
                Pix.Round(g, !b.Enabled ? Pix.C(0xBBA98C) : Pix.Ink, r.X, r.Y, r.Width, r.Height, U);
                Pix.Box(g, face, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
                Pix.Box(g, shade, r.X + U, r.Bottom - (small ? 2 : 3) * U, r.Width - 2 * U, (small ? 1 : 2) * U);
                Font f = small ? subF : btnF;
                PixText.DrawText(g, b.Text, f, new Rectangle(r.X, r.Y, r.Width, r.Height - (small ? U : 2 * U)), b.Enabled ? Pix.TextC : Pix.Dim, Pix.Mid);
                return;
            }
            Color edge = b.On ? Pix.C(0xC08A2C) : Pix.C(0x8A6A4A);
            Color fill = b.On ? Pix.C(0xFFEDB8) : (hot ? Pix.C(0xFFF6DE) : Pix.C(0xFFFDF7));
            Pix.Round(g, Pix.C(0xE6D3B0), r.X + 2 * U, r.Y + 2 * U, r.Width, r.Height, U);
            Pix.Round(g, edge, r.X, r.Y, r.Width, r.Height, U);
            int ins = b.On ? 2 * U : U;
            if (b.On) Pix.Box(g, edge, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U);
            Pix.Box(g, fill, r.X + ins, r.Y + ins, r.Width - 2 * ins, r.Height - 2 * ins);
            if (b.Id.StartsWith("persona:"))
            {
                string id = b.Id.Substring(8);
                PixText.DrawText(g, b.Text, bigF, new Rectangle(r.X + Sc(12), r.Y + Sc(8), r.Width - Sc(24), Sc(28)), Pix.TextC, Pix.LeftMid);
                PixText.DrawText(g, Pal.PersonaDesc(id), subF, new Rectangle(r.X + Sc(12), r.Y + Sc(38), r.Width - Sc(24), Sc(36)), Pix.C(0x9A6338), TextFormatFlags.Left | TextFormatFlags.Top | TextFormatFlags.WordBreak | TextFormatFlags.NoPrefix);
            }
            else
            {
                string sub = b.Id == "pixel" ? "跟內建公仔同畫風" : "照片原本的樣子";
                PixText.DrawText(g, b.Text, btnF, new Rectangle(r.X, r.Y + Sc(6), r.Width, Sc(24)), Pix.TextC, Pix.Mid);
                PixText.DrawText(g, sub, smallF, new Rectangle(r.X + Sc(4), r.Y + Sc(30), r.Width - Sc(8), Sc(20)), Pix.C(0x9A6338), Pix.Mid | TextFormatFlags.EndEllipsis);
            }
            if (b.On)
            {
                int s = 7 * U, bx = r.Right - s - 2 * U, by2 = r.Y + 2 * U;
                Pix.Round(g, Pix.C(0x2F6E24), bx, by2, s, s, U);
                Pix.Box(g, Pix.C(0x5FB04A), bx + U, by2 + U, s - 2 * U, s - 2 * U);
            }
        }
    }

    // ================= 預覽：做公仔視窗、分享短片用（不改真的公仔） =================
    partial class Pet
    {
        // 照指定的動作畫一格（走路左右來回、跳、睡、開心冒愛心、被抓著晃）
        public void CuPreview(Graphics g, double cx, double feetY, int ps, string act, double t, double range)
        {
            double fx = cx, fy = feetY;
            int d = 1;
            anim = t; rolling = false; cuAct = ""; cuLandT = 0; vy = 0; knock = 0;
            switch (act)
            {
                case "walk":
                    {
                        double per = 6.0, ph = (t % per) / per;          // 來回走
                        double tri = ph < 0.5 ? ph * 2 : 2 - ph * 2;
                        fx = cx - range + tri * 2 * range; d = ph < 0.5 ? 1 : -1;
                        state = "walk";
                    }
                    break;
                case "jump":
                    {
                        double c = t % 1.4;
                        if (c < 0.8) { state = "air"; double u = c / 0.8; fy -= Math.Sin(u * Math.PI) * ps * 9; vy = u < 0.5 ? -1 : 1; }
                        else { state = "idle"; cuLandT = Math.Max(0, 0.2 - (c - 0.8)); }
                    }
                    break;
                case "sleep": state = "sleep"; z = t; break;
                case "happy": state = "hug"; break;
                case "held": state = "drag"; fy -= ps * 3; break;
                default: state = "idle"; break;
            }
            dir = d;
            CuPoseNow(cuPose);
            CuDraw(g, cuPose, fx, fy, ps, d < 0);
            int hp = Math.Max(2, ps / 2);
            if (act == "sleep")
                for (int i = 0; i < 3; i++)
                {
                    double p = (t * .6 + i / 3.0) % 1;
                    if (p > 0.85) continue;
                    DrawPix(g, ZZ, (int)(fx + P.Spr.Wc / 2 * ps + p * 6 * ps), (int)(fy - P.Spr.Hc * ps - p * 10 * ps), hp, false, false, false);
                }
            if (act == "happy")
                for (int i = 0; i < 3; i++)
                {
                    double p = (t * 0.7 + i / 3.0) % 1;
                    DrawPix(g, HEART, (int)(fx + (i - 1) * 5 * ps + Math.Sin(p * 6 + i) * ps), (int)(fy - P.Spr.Hc * ps - 2 * ps - p * 9 * ps), hp, false, false, true);
                }
        }
    }

    // ================= World：開「做公仔」視窗、測試用 pipe 指令 =================
    partial class World
    {
        CuMaker maker;

        public void CuOpenMaker(string editId, bool first)
        {
            if (maker != null && !maker.IsDisposed) maker.Close();
            maker = new CuMaker(this, first, editId);
            Rectangle wa = App.Offscreen ? screens[0].WorkingArea : Screen.FromPoint(Cursor.Position).WorkingArea;
            maker.Location = new Point(wa.Left + (wa.Width - maker.Width) / 2, wa.Top + Math.Max(0, (wa.Height - maker.Height) / 2));
            maker.Show();
            if (App.Offscreen) return;
            ActivateForm(maker);
            CuMaker mk = maker;
            Later(0.2, delegate { if (!mk.IsDisposed && mk.Visible) ActivateForm(mk); });
        }

        void CuSnap(Graphics g)
        {
            if (maker != null && !maker.IsDisposed && maker.VVisible) maker.PaintTo(g);
        }

        public void CuSaveTemplateDialog()
        {
            if (App.Offscreen) { App.Log("custom: template dialog skipped (offscreen)"); return; }
            using (SaveFileDialog dlg = new SaveFileDialog())
            {
                dlg.Title = "存動作表範本";
                dlg.Filter = "PNG 圖片|*.png";
                dlg.FileName = "DeskPals動作表範本.png";
                dlg.InitialDirectory = World.UserFolder(Environment.SpecialFolder.DesktopDirectory, "", "Desktop");
                if (dlg.ShowDialog() != DialogResult.OK) return;
                CuSaveTemplate(dlg.FileName);
                Lead().Say("範本存好了：每一格畫一個動作，畫好再按「上傳畫好的動作表」🎨", 4);
            }
        }

        static void CuSaveTemplate(string path)
        {
            try { using (Bitmap b = CuSprite.Template()) b.Save(path, ImageFormat.Png); }
            catch (Exception ex) { App.Log("template: " + ex.Message); }
        }

        // pipe：custom <指令> …（測試、VS Code 用）
        void CuMsg(Client c, string line)
        {
            string t = line.Trim();
            string[] p = t.Split(' ');
            if (p.Length < 2) return;
            string cmd = p[1], rest = p.Length > 2 ? t.Substring(t.IndexOf(' ', t.IndexOf(' ') + 1) + 1) : "";
            System.Globalization.CultureInfo ci = System.Globalization.CultureInfo.InvariantCulture;
            double a0 = 0, a1 = 0, a2 = 0, a3 = 0;
            if (p.Length > 2) double.TryParse(p[2], System.Globalization.NumberStyles.Float, ci, out a0);
            if (p.Length > 3) double.TryParse(p[3], System.Globalization.NumberStyles.Float, ci, out a1);
            if (p.Length > 4) double.TryParse(p[4], System.Globalization.NumberStyles.Float, ci, out a2);
            if (p.Length > 5) double.TryParse(p[5], System.Globalization.NumberStyles.Float, ci, out a3);
            bool mk = maker != null && !maker.IsDisposed;
            switch (cmd)
            {
                case "list": Send(c, "pals " + CuPalsJson() + "\n"); return;
                case "new": CuOpenMaker(null, false); break;
                case "first": CuOpenMaker(null, true); break;
                case "edit": CuOpenMaker(rest, false); break;
                case "import": if (!mk) CuOpenMaker(null, false); maker.LoadImage(rest, false); break;
                case "sheet": if (!mk) CuOpenMaker(null, false); maker.LoadImage(rest, true); break;
                case "template": CuSaveTemplate(rest); break;
                case "tol": if (mk) maker.SetTol((int)a0); break;
                case "lines": if (mk) maker.SetLines(a0, a1); break;
                case "brush": if (mk) maker.Brush(p.Length > 2 && p[2] == "erase", a1, a2, a3); break;
                case "name": if (mk) maker.SetName(rest); break;
                case "step": if (mk) maker.SetStep((int)a0); break;
                case "anim": if (mk) maker.SetAnim(p.Length > 2 ? p[2] : "walk", a1); break;
                case "press": if (mk) maker.Press(rest); break;
                case "cancel": if (mk) maker.Press("cancel"); break;
                case "delete": CuDelete(rest); break;
                case "export": if (p.Length > 3) CuExport(p[2], t.Substring(t.IndexOf(p[2]) + p[2].Length + 1)); break;
                case "importpal": CuImportFile(rest, false); break;
                case "mine": { List<string> l = new List<string>(rest.Split(new char[] { ',' }, StringSplitOptions.RemoveEmptyEntries)); Pal.SaveMine(l); if (lineup == Pal.Mine) CuReload(l.Count > 0 ? l[0] : ""); else if (OrigLineup) CuReload(""); else CuStore.Reset(false); } break;
                case "callout": CuCallOut(rest); break;
                case "fakewin": CuSetFakeWin(new Rectangle((int)a0, (int)a1, (int)a2, (int)a3)); break;   // 測試：custom fakewin x y w h
                case "pet":
                    {
                        // 測試：custom pet <id> <動作>（loaf push ignore wag fetch return jumpwin）
                        Pet tp = Get(p.Length > 2 ? p[2] : "");
                        if (tp != null && p.Length > 3) tp.CuTest(p[3]);
                    }
                    break;
                case "share": if (rest.Trim() == "") ShareClip(null); else ShareClipTo(rest, null); break;
                case "icon":
                    {
                        // custom icon <id> <ps> <png>
                        CuMeta m = p.Length > 4 ? CuStore.Get(p[2]) : null;
                        CuSprite s = m == null ? null : CuStore.Sprite(m);
                        if (s != null) using (Bitmap b = CuStore.Icon(m, s, (int)Math.Max(1, a1))) b.Save(p[4], ImageFormat.Png);
                    }
                    break;
            }
            Send(c, "custom-ok " + cmd + "\n");
        }
    }
}
