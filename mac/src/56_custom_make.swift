// 56_custom_make.swift — port of extension/desktop/DeskPals.CustomMake.cs
// Desk Pals：「做一隻自己的公仔」視窗。四步：選照片 → 去背 → 動起來 → 取名字。
// 全部自己畫（跟設定視窗同一套木框＋奶油色），名字用真的 TextBox（才打得了中文）。離屏測試時不顯示，用 pipe 的 custom 指令操作。
// mac: 拖檔案進來 → Form.AllowDrop／DragEnter／DragDrop（04_shim_custom_b.swift）；OpenFileDialog／SaveFileDialog → NSOpenPanel／NSSavePanel（CuDialogs）。
import Foundation
import AppKit

class CuMaker: Form {
    final class Btn { var Id = "", Text = ""; var R = Rectangle(0, 0, 0, 0); var Kind = 0; var On = false, Enabled = true }   // Kind：0 卡片 2 按鈕 3 主要按鈕 4 小按鈕
    let w: World
    let first: Bool
    let editId: String!
    let d: Double
    let U: Int
    var step = 0
    var VVisible = false
    let btns = List<Btn>()
    var hoverId = ""
    var err: String! = ""
    var titleF: FontT! = nil, qF: FontT! = nil, bigF: FontT! = nil, subF: FontT! = nil, btnF: FontT! = nil, smallF: FontT! = nil
    let nameBox: TextBox
    let timer = Timer()
    var animT = 0.0
    var anim = "walk"
    var Capture = false   // mac: 拖曳時 AppKit 本來就會一直把滑鼠事件給這個視窗；這裡只記 C# 的 Capture 狀態

    // 草稿
    var meta = CuMeta()
    var src: Bitmap! = nil               // 原圖（最長邊 640）
    var srcAlpha = false
    var srcPx: [Int] = [], autoPx: [Int] = [], viewPx: [Int] = []     // 原圖、自動去背的結果（快取）、加上筆刷的結果
    var autoKey = -999
    var viewBmp: Bitmap! = nil, srcDim: Bitmap! = nil
    var spr: CuSprite! = nil
    var draft: Pal! = nil
    var pv: Pet! = nil
    var pvw: World! = nil
    var brushOn = false; var brushErase = true; var brushSize = 1
    var painting = false, dragLine = false; var dragWhich = 0
    var lastPaint = PointT(0, 0)

    init(_ w: World, _ first: Bool, _ editId: String!) {
        self.w = w; self.first = first; self.editId = editId
        d = Double(w.S) / 4.0
        U = Math.Max(2, CInt(Math.Round(2 * d)))
        nameBox = TextBox()
        super.init()
        Text = editId != nil ? "修改我的公仔" : "做一隻自己的公仔"
        FormBorderStyle = FormBorderStyleT.FixedSingle
        MaximizeBox = false; MinimizeBox = false
        ShowInTaskbar = true; TopMost = true
        StartPosition = FormStartPosition.Manual
        BackColor = Pix.Cream
        DoubleBuffered = true
        AllowDrop = true
        titleF = FontT("Microsoft JhengHei UI", 12, FontStyle.Bold)
        qF = FontT("Microsoft JhengHei UI", 15, FontStyle.Bold)
        bigF = FontT("Microsoft JhengHei UI", 12, FontStyle.Bold)
        subF = FontT("Microsoft JhengHei UI", 9, FontStyle.Bold)
        btnF = FontT("Microsoft JhengHei UI", 11, FontStyle.Bold)
        smallF = FontT("Microsoft JhengHei UI", 8.5, FontStyle.Regular)
        ClientSize = SizeT(Sc(780), Sc(600))
        KeyPreview = true
        KeyDown = { [unowned self] (e: KeyEventArgs) in if e.KeyCode == Keys.Escape { self.Cancel() } }
        nameBox.Font = FontT("Microsoft JhengHei UI", 15, FontStyle.Bold)
        nameBox.BackColor = Color.FromArgb(0xFF, 0xFD, 0xF7)
        nameBox.ForeColor = Pix.TextC
        nameBox.MaxLength = 10
        nameBox.Visible = false
        nameBox.TextChanged = { [unowned self] in self.meta.Name = CuMeta.CleanName(self.nameBox.Text); self.RefreshDraftLines(); self.LayoutBtns(); self.Invalidate() }
        Controls.Add(nameBox)
        CuMaker.Borderless(nameBox, Color.FromArgb(0xFF, 0xFD, 0xF7))
        DragEnter = { (e: DragEventArgs) in e.Effect = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None }
        DragDrop = { [unowned self] (e: DragEventArgs) in
            guard let files = e.Data.GetData(DataFormats.FileDrop) as? [String], files.count > 0 else { return }
            if files[0].EndsWith(".deskpal", StringComparison.OrdinalIgnoreCase) { let f = self.first; let ww = self.w; self.Close(); ww.CuImportFile(files[0], f); return }
            self.LoadImage(files[0], false)
        }
        timer.Interval = 40
        timer.Tick = { [weak self] in
            guard let s = self else { return }
            s.animT += 0.04; if s.step >= 2 { s.Invalidate(s.PreviewRect()) }
        }
        FormClosed = { [weak self] in self?.timer.Stop(); self?.timer.Dispose() }
        if editId != nil { LoadExisting(editId) }
        LayoutBtns()
    }

    // mac: TextBox.BorderStyle = BorderStyle.None（NSTextField 拿掉外框、背景照 BackColor）
    static func Borderless(_ t: TextBox, _ back: Color) {
        guard let tf = t.tf else { return }
        tf.isBezeled = false; tf.isBordered = false
        tf.drawsBackground = true; tf.backgroundColor = back.ns
        tf.focusRingType = .none
    }

    func Sc(_ v: Int) -> Int { return CInt(Math.Round(Double(v) * d)) }

    override func SetVisibleCore(_ value: Bool) {
        if App.Offscreen { VVisible = value; super.SetVisibleCore(false); if value { timer.Start() }; return }
        super.SetVisibleCore(value)
        if value { _applyAllowDrop(); timer.Start() }   // mac: 視窗這時才建好，登記可以放檔案
    }
    func PaintTo(_ g: Graphics) {
        let cs = ClientSize
        if cs.Width <= 0 || cs.Height <= 0 { return }
        let b = Bitmap(cs.Width, cs.Height, PixelFormat.Format24bppRgb)
        do { let gg = Graphics.FromImage(b); OnPaint(PaintEventArgs(gg, Rectangle(0, 0, cs.Width, cs.Height))); if step == 3 { DrawNameText(gg) } }
        g.DrawImageUnscaled(b, Left, Top)
    }

    // ================= 草稿 =================
    func LoadExisting(_ id: String) {
        let m: CuMeta! = CuStore.Get(id)
        if m == nil { return }
        meta = m.Clone()
        var e2: String! = nil
        let b: Bitmap! = CuImg.LoadFile(Path.Combine(CuStore.Dir(id), "source.png"), &e2)
        if b == nil { err = e2; return }
        SetSource(b)
        Rebuild(false)
        nameBox.Text = meta.Name
        step = 1
    }

    func LoadImage(_ path: String, _ sheet: Bool) {
        var e2: String! = nil
        let b: Bitmap! = CuImg.LoadFile(path, &e2)
        if b == nil { err = e2; step = 0; LayoutBtns(); Invalidate(); return }
        err = ""
        let keepName: String = meta.Name, keepPersona: String = meta.Persona
        meta = CuMeta()
        meta.Name = keepName; meta.Persona = keepPersona
        meta.Sheet = sheet
        if !sheet && keepName == "" { let fn = CuMeta.CleanName(Path.GetFileNameWithoutExtension(path)); if fn.Length > 0 && fn.Length <= 6 && !fn.StartsWith("IMG") && !fn.StartsWith("DSC") { meta.Name = fn } }
        SetSource(b)
        // 小小的圖（多半本來就是像素圖）：像素風、跟內建一樣大的像素；照片：保留原圖（像素風可以自己切）
        if b.Width <= 64 && b.Height <= 64 { meta.Mode = "pixel"; meta.Sub = 1 }
        else if !sheet { meta.Mode = "smooth"; meta.Sub = 2 }
        Rebuild(true)
        if spr == nil { step = sheet ? 0 : 1 }
        else { step = sheet ? 2 : 1 }
        nameBox.Text = meta.Name
        LayoutBtns(); Invalidate()
    }

    func SetSource(_ b: Bitmap) {
        if src != nil { src.Dispose() }
        src = b
        srcPx = CuImg.Pixels(b)
        srcAlpha = CuImg.HasAlpha(srcPx, b.Width, b.Height)
        autoKey = -999
        if srcDim != nil { srcDim.Dispose() }
        srcDim = b.Clone()
    }

    // 去背（快取：強度沒變就不重算）→ 筆刷 → 裁切 → 像素風／原圖 → 切頭身腳
    func Rebuild(_ guessRig: Bool) {
        if src == nil { return }
        if meta.Sheet {
            var e2: String! = nil
            spr = CuSprite.Build(meta, src, &e2)
            err = spr == nil ? e2 : ""
            MakeDraft()
            return
        }
        let key = (srcAlpha && meta.UseAlpha) ? -1 : meta.Tol
        if key != autoKey {
            if key == -1 { autoPx = srcPx; for i in 0..<autoPx.count { if ((autoPx[i] >> 24) & 255) < 10 { autoPx[i] = 0 } } }
            else {
                var solid = srcPx
                for i in 0..<solid.count { if ((solid[i] >> 24) & 255) < 128 { solid[i] = 0xFFFFFFFF } else { solid[i] |= 0xFF000000 } }
                autoPx = CuImg.RemoveBg(solid, src.Width, src.Height, meta.Tol)
            }
            autoKey = key
        }
        viewPx = autoPx
        CuImg.ApplyStrokes(&viewPx, srcPx, src.Width, src.Height, meta.Strokes)
        RefreshView()
        BuildSprite(guessRig)
    }

    func RefreshView() {
        if viewBmp != nil { viewBmp.Dispose() }
        viewBmp = CuImg.FromPixels(viewPx, src.Width, src.Height)
    }

    func BuildSprite(_ guessRig: Bool) {
        let bb = CuImg.Bounds(viewPx, src.Width, src.Height, 40)
        if bb.Width < 2 || bb.Height < 2 { spr = nil; err = "去背之後什麼都不剩了：把去背強度調低，或用「補回」筆刷"; MakeDraft(); return }
        var cut = CuImg.Crop(viewPx, src.Width, src.Height, bb)
        if meta.Flip { cut = CuImg.Mirror(cut) }
        let s = CuSprite()
        s.Pixel = meta.Pixel
        var fin: CuCut
        if s.Pixel { var ol = Color.Empty; fin = CuImg.ToPixel(cut, meta.Sub, CuImg.HCells, CuImg.WCells, &ol); s.Outline = ol; s.R = meta.Sub }
        else { fin = CuImg.ToSmooth(cut, CuImg.HCells, CuImg.WCells); s.R = CuImg.SmoothR; let mc = CuImg.MainColor(fin); s.Outline = Color.FromArgb(CInt(Double(mc.R) * 0.25 + 17), CInt(Double(mc.G) * 0.25 + 19), CInt(Double(mc.B) * 0.25 + 31)) }
        if guessRig {
            var gn = 0.0, gh = 0.0; var conf = false
            CuImg.GuessLines(fin, &gn, &gh, &conf)
            meta.Rig = conf; meta.Neck = -1; meta.Hip = -1
        }
        s.SetStand(fin, meta.Rig, meta.Neck, meta.Hip)
        spr = s
        err = ""
        MakeDraft()
    }

    func MakeDraft() {
        if spr == nil { draft = nil; pv = nil; return }
        let m: CuMeta = meta.Clone()
        if m.Id == "" { m.Id = "cudraft" }
        if m.Name == "" { m.Name = "小公仔" }
        draft = Pal.MakeCu(m, spr)
        if pvw == nil { pvw = World(w.S, Pal.Fallback) }
        pv = Pet(pvw, draft, w.S, 7)
    }

    func RefreshDraftLines() { if spr != nil { MakeDraft() } }

    // ================= 按鈕 =================
    @discardableResult func Add(_ id: String, _ text: String, _ r: Rectangle, _ kind: Int, _ on: Bool) -> Btn {
        let b = Btn(); b.Id = id; b.Text = text; b.R = r; b.Kind = kind; b.On = on; btns.Add(b); return b
    }
    func Find(_ id: String) -> Btn! { for b in btns { if b.Id == id { return b } }; return nil }
    func At(_ p: Point) -> Btn! { for b in btns { if b.R.Contains(p) && b.Enabled { return b } }; return nil }

    func ContentRect() -> Rectangle { return Rectangle(Sc(30), Sc(150), ClientSize.Width - Sc(60), ClientSize.Height - Sc(150) - Sc(80)) }
    func LeftRect() -> Rectangle { let c = ContentRect(); return Rectangle(c.X, c.Y, Sc(400), c.Height) }
    func RightRect() -> Rectangle { let c = ContentRect(); let x = c.X + Sc(418); return Rectangle(x, c.Y, c.Right - x, c.Height) }
    func PreviewRect() -> Rectangle { let r = RightRect(); return Rectangle(r.X, r.Y, r.Width, Sc(210)) }
    func SliderRect() -> Rectangle { let r = RightRect(); return Rectangle(r.X + Sc(10), r.Y + Sc(50), r.Width - Sc(20), Sc(22)) }

    func LayoutBtns() {
        btns.Clear()
        let W0 = ClientSize.Width, H0 = ClientSize.Height
        let c = ContentRect()
        nameBox.Visible = step == 3 && !App.Offscreen
        if step == 0 {
            Add("open", "", Rectangle(c.X, c.Y, c.Width, Sc(200)), 0, false)
            let bw = (c.Width - 2 * Sc(12)) / 3, by = c.Bottom - Sc(40)
            Add("template", "下載動作表範本", Rectangle(c.X, by, bw, Sc(36)), 4, false)
            Add("sheet", "上傳畫好的動作表…", Rectangle(c.X + bw + Sc(12), by, bw, Sc(36)), 4, false)
            Add("importpal", "匯入朋友的公仔…", Rectangle(c.X + 2 * (bw + Sc(12)), by, bw, Sc(36)), 4, false)
        }
        else if step == 1 {
            let r = RightRect()
            var y = r.Y
            if meta.Sheet { }
            else if srcAlpha { Add("usealpha", meta.UseAlpha ? "改用自動去背" : "用原本的透明背景", Rectangle(r.X + Sc(10), y + Sc(42), Sc(170), Sc(30)), 4, false) }
            y += Sc(92)
            let bw = Sc(78)
            Add("erase", "擦掉", Rectangle(r.X + Sc(10), y + Sc(30), bw, Sc(32)), 4, brushOn && brushErase)
            Add("restore", "補回", Rectangle(r.X + Sc(10) + bw + Sc(8), y + Sc(30), bw, Sc(32)), 4, brushOn && !brushErase)
            Add("bsize", brushSize == 0 ? "筆刷：小" : (brushSize == 1 ? "筆刷：中" : "筆刷：大"), Rectangle(r.X + Sc(10) + 2 * (bw + Sc(8)), y + Sc(30), Sc(100), Sc(32)), 4, false)
            Add("undo", "復原一筆", Rectangle(r.X + Sc(10), y + Sc(68), Sc(100), Sc(30)), 4, false).Enabled = meta.Strokes.Count > 0
            Add("clearbrush", "筆刷全部重來", Rectangle(r.X + Sc(118), y + Sc(68), Sc(130), Sc(30)), 4, false).Enabled = meta.Strokes.Count > 0
            if meta.Sheet { let b1: Btn = Find("erase"); b1.Enabled = false; Find("restore").Enabled = false; Find("bsize").Enabled = false }
            y += Sc(112)
            let cw = (r.Width - Sc(30)) / 2
            Add("pixel", "像素風", Rectangle(r.X + Sc(10), y + Sc(28), cw, Sc(58)), 0, meta.Pixel)
            Add("smooth", "保留原圖", Rectangle(r.X + Sc(20) + cw, y + Sc(28), cw, Sc(58)), 0, !meta.Pixel)
            if meta.Pixel { Add("sub", meta.Sub >= 2 ? "細緻像素 ✓" : "細緻像素", Rectangle(r.X + Sc(10), y + Sc(94), Sc(130), Sc(30)), 4, meta.Sub >= 2) }
            Add("flip", "左右翻轉", Rectangle(r.X + Sc(148), y + Sc(94), Sc(110), Sc(30)), 4, meta.Flip)
        }
        else if step == 2 {
            let l = LeftRect(), pr = PreviewRect()
            if !meta.Sheet { Add("rig", meta.Rig ? "✓ 用兩條線分出頭、身體、腳" : "用兩條線分出頭、身體、腳", Rectangle(l.X, l.Y, l.Width, Sc(32)), 4, meta.Rig) }
            let an: [String] = ["walk", "jump", "sleep", "happy", "held"]
            let at: [String] = ["走路", "跳", "睡覺", "開心", "被抓"]
            let bw = (pr.Width - 4 * Sc(6)) / 5
            for i in 0..<an.count { Add("anim:" + an[i], at[i], Rectangle(pr.X + i * (bw + Sc(6)), pr.Bottom + Sc(10), bw, Sc(32)), 4, anim == an[i]) }
        }
        else {
            let r = ContentRect()
            let nf = Rectangle(r.X + Sc(150), r.Y + Sc(6), Sc(260), Sc(40))
            nameBox.Bounds = Rectangle(nf.X + Sc(12), nf.Y + (nf.Height - nameBox.PreferredHeight) / 2, nf.Width - Sc(24), nameBox.PreferredHeight)
            let cw = (r.Width - 2 * Sc(12)) / 3, ch = Sc(82), y0 = r.Y + Sc(84)
            for i in 0..<Pal.Personas.count {
                let id = Pal.Personas[i]
                Add("persona:" + id, Pal.PersonaName(id), Rectangle(r.X + (i % 3) * (cw + Sc(12)), y0 + (i / 3) * (ch + Sc(12)), cw, ch), 0, meta.Persona == id)
            }
        }
        let bby = H0 - Sc(64), bh = Sc(44)
        Add(step > 0 ? "back" : "cancel", step > 0 ? "上一步" : "取消", Rectangle(Sc(30), bby, Sc(130), bh), 2, false)
        let nx = Add("next", step < 3 ? "下一步" : (editId != nil ? "存好了！" : "完成！"), Rectangle(W0 - Sc(30) - Sc(160), bby, Sc(160), bh), 3, false)
        nx.Enabled = step == 0 ? spr != nil : (step == 3 ? spr != nil && meta.Name.Trim() != "" : spr != nil)
    }

    // 按按鈕（滑鼠、測試用的 custom 指令都走這裡）
    func Press(_ id: String) {
        let b: Btn! = Find(id)
        if b != nil && !b.Enabled { return }
        switch id {
        case "open": PickImage(false); return
        case "sheet": PickImage(true); return
        case "template": w.CuSaveTemplateDialog(); return
        case "importpal": let f = first; let ww = w; Close(); ww.CuImportDialog(f); return
        case "usealpha": meta.UseAlpha = !meta.UseAlpha; Rebuild(false)
        case "erase": brushOn = !(brushOn && brushErase); brushErase = true
        case "restore": brushOn = !(brushOn && !brushErase); brushErase = false
        case "bsize": brushSize = (brushSize + 1) % 3
        case "undo":
            if meta.Strokes.Count > 0 {
                let n = meta.Strokes.Count
                var keep = n - 1
                while keep > 0 && meta.Strokes[keep - 1].count > 4 && meta.Strokes[keep - 1][4] == meta.Strokes[n - 1][4] { keep -= 1 }
                meta.Strokes.RemoveRange(keep, n - keep)
                Rebuild(false)
            }
        case "clearbrush": meta.Strokes.Clear(); Rebuild(false)
        case "pixel": meta.Mode = "pixel"; BuildSprite(false)
        case "smooth": meta.Mode = "smooth"; BuildSprite(false)
        case "sub": meta.Sub = meta.Sub >= 2 ? 1 : 2; BuildSprite(false)
        case "flip": meta.Flip = !meta.Flip; if meta.Sheet { Rebuild(false) } else { BuildSprite(false) }
        case "rig": meta.Rig = !meta.Rig; BuildSprite(false)
        case "back": if step > 0 { step -= 1 }; if step == 1 && meta.Sheet { step = 0 }
        case "cancel": Cancel(); return
        case "next":
            if step < 3 { step += 1; if step == 1 && meta.Sheet { step = 2 } }
            else { Finish(); return }
        default:
            if id.StartsWith("anim:") { anim = id.Substring(5); animT = 0 }
            else if id.StartsWith("persona:") { meta.Persona = id.Substring(8); RefreshDraftLines() }
            else { return }
        }
        LayoutBtns(); hoverId = ""; Invalidate()
    }

    func PickImage(_ sheet: Bool) {
        if App.Offscreen { App.Log("custom: file dialog skipped (offscreen)"); return }
        // mac: OpenFileDialog（圖片（PNG、JPG、GIF、BMP））→ NSOpenPanel
        let file = CuDialogs.Open(sheet ? "選畫好的動作表" : "選一張照片或圖片", ["png", "jpg", "jpeg", "gif", "bmp"], World.UserFolder(Environment.SpecialFolder.MyPictures, "", "Pictures"))
        if file != nil { LoadImage(file!, sheet) }
    }

    // 外面（pipe 測試指令）設定
    func SetTol(_ t: Int) { meta.Tol = Math.Max(0, Math.Min(100, t)); if srcAlpha { meta.UseAlpha = false }; Rebuild(false); LayoutBtns(); Invalidate() }
    func SetLines(_ neck: Double, _ hip: Double) { meta.Neck = neck; meta.Hip = hip; meta.Rig = true; BuildSprite(false); LayoutBtns(); Invalidate() }
    func SetName(_ s: String) { nameBox.Text = s; meta.Name = CuMeta.CleanName(s); RefreshDraftLines(); LayoutBtns(); Invalidate() }
    func Brush(_ erase: Bool, _ x: Double, _ y: Double, _ r: Double) { if src == nil { return }; meta.Strokes.Add([x, y, r, erase ? 1 : 0, Double(meta.Strokes.Count)]); Rebuild(false); LayoutBtns(); Invalidate() }
    func SetStep(_ s: Int) { step = Math.Max(0, Math.Min(3, s)); LayoutBtns(); Invalidate() }
    func SetAnim(_ a: String, _ t: Double) { anim = a; animT = t; LayoutBtns(); Invalidate() }
    var Step: Int { return step }

    func Cancel() {
        let f = first
        let ww = w
        Close()
        if f { ww.ShowSetup(true) }   // 第一次設定時按取消：回到設定視窗
    }

    func Finish() {
        if spr == nil || src == nil { return }
        let m: CuMeta = meta.Clone()
        if m.Name.Trim() == "" { return }
        let edit = editId != nil
        m.Id = edit ? editId : CuStore.NewId()
        // 筆刷：只留 x y r 擦／補（第五個數字是哪一筆，存檔不用）
        let st = List<[Double]>()
        for s in m.Strokes { st.Add([s[0], s[1], s[2], s[3]]) }
        m.Strokes = st
        do {
            try CuStore.Save(m, src, spr)
            App.Log("custom saved " + m.Id + " name=" + m.Name + " persona=" + m.Persona + " mode=" + m.Mode + " rig=" + m.Rig.ToString() + " sheet=" + m.Sheet.ToString())
        }
        catch { err = "存不起來：" + error.Message; Invalidate(); return }
        spr = nil   // 已經交給 CuStore 了
        let f = first
        let id: String = m.Id
        let ww = w
        Close()
        ww.CuCreated(id, f, edit)
    }

    // ================= 滑鼠：按鈕、拖去背強度、筆刷、拖兩條線 =================
    func ViewRect() -> Rectangle {
        let l = LeftRect()
        if src == nil { return l }
        let s = Math.Min(Double(l.Width) / Double(src.Width), Double(l.Height) / Double(src.Height))
        let vw = CInt(Double(src.Width) * s), vh = CInt(Double(src.Height) * s)
        return Rectangle(l.X + (l.Width - vw) / 2, l.Y + (l.Height - vh) / 2, vw, vh)
    }

    func SpriteRect() -> Rectangle {
        var l = LeftRect()
        l = Rectangle(l.X, l.Y + Sc(42), l.Width, l.Height - Sc(42))
        if spr == nil { return l }
        var s = Math.Min(Double(l.Width - Sc(80)) / Double(spr.W), Double(l.Height - Sc(16)) / Double(spr.H))
        if spr.Pixel { s = Math.Max(1.0, Math.Floor(s)) }
        let vw = CInt(Double(spr.W) * s), vh = CInt(Double(spr.H) * s)
        return Rectangle(l.X + (l.Width - vw) / 2, l.Y + (l.Height - vh) / 2, vw, vh)
    }

    override func OnMouseDown(_ e: MouseEventArgs) {
        super.OnMouseDown(e)
        if e.Button != MouseButtons.Left { return }
        if step == 1 && !meta.Sheet && !(srcAlpha && meta.UseAlpha) && SliderRect().Contains(e.Location) { SliderAt(e.X, false); Capture = true; dragWhich = -1; return }
        if step == 1 && brushOn && ViewRect().Contains(e.Location) { painting = true; lastPaint = e.Location; PaintAt(e.Location, true); return }
        if step == 2 && meta.Rig && spr != nil {
            let sr = SpriteRect()
            let ny = sr.Y + CInt(spr.NeckF * Double(sr.Height)), hy = sr.Y + CInt(spr.HipF * Double(sr.Height))
            if e.X > sr.X - Sc(60) && e.X < sr.Right + Sc(60) {
                if Math.Abs(e.Y - ny) < Sc(10) { dragLine = true; dragWhich = 0; return }
                if Math.Abs(e.Y - hy) < Sc(10) { dragLine = true; dragWhich = 1; return }
            }
        }
    }

    override func OnMouseMove(_ e: MouseEventArgs) {
        super.OnMouseMove(e)
        if Capture && dragWhich == -1 && step == 1 { SliderAt(e.X, false); return }
        if painting { if Math.Abs(e.X - lastPaint.X) + Math.Abs(e.Y - lastPaint.Y) >= Sc(3) { lastPaint = e.Location; PaintAt(e.Location, false) }; return }
        if dragLine && spr != nil {
            let sr = SpriteRect()
            let f = Math.Max(0.06, Math.Min(0.96, Double(e.Y - sr.Y) / Double(sr.Height)))
            if dragWhich == 0 { meta.Neck = Math.Min(f, spr.HipF - 0.08) } else { meta.Hip = Math.Max(f, spr.NeckF + 0.08) }
            if meta.Neck < 0 { meta.Neck = spr.NeckF }
            if meta.Hip < 0 { meta.Hip = spr.HipF }
            BuildSprite(false); Invalidate()
            return
        }
        let b: Btn! = At(e.Location)
        let h = b != nil ? b.Id : ""
        if h != hoverId { hoverId = h; Invalidate() }
        var lineHot = false
        if step == 2 && meta.Rig && spr != nil {
            let sr = SpriteRect()
            let ny = sr.Y + CInt(spr.NeckF * Double(sr.Height)), hy = sr.Y + CInt(spr.HipF * Double(sr.Height))
            lineHot = Math.Abs(e.Y - ny) < Sc(10) || Math.Abs(e.Y - hy) < Sc(10)
        }
        Cursor = h != "" ? Cursors.Hand : (lineHot ? Cursors.SizeNS : (step == 1 && brushOn && ViewRect().Contains(e.Location) ? Cursors.Cross : Cursors.Default))
        if step == 1 && brushOn { Invalidate(LeftRect()) }
    }

    override func OnMouseUp(_ e: MouseEventArgs) {
        super.OnMouseUp(e)
        if e.Button != MouseButtons.Left { return }
        if Capture && dragWhich == -1 && step == 1 { Capture = false; dragWhich = 0; SliderAt(e.X, true); return }
        if painting { painting = false; BuildSprite(false); LayoutBtns(); Invalidate(); return }
        if dragLine { dragLine = false; return }
        let b: Btn! = At(e.Location)
        if b != nil { Press(b.Id) }
    }

    func SliderAt(_ x: Int, _ commit: Bool) {
        let s = SliderRect()
        let t = CInt(Math.Round(Math.Max(0.0, Math.Min(1.0, Double(x - s.X) / Double(s.Width))) * 100))
        meta.Tol = t
        if commit { Rebuild(false); LayoutBtns() }
        Invalidate()
    }

    func BrushR() -> Double { return brushSize == 0 ? 0.012 : (brushSize == 1 ? 0.028 : 0.06) }

    func PaintAt(_ p: Point, _ newStroke: Bool) {
        let v = ViewRect()
        let x = Double(p.X - v.X) / Double(v.Width), y = Double(p.Y - v.Y) / Double(v.Height)
        let n = meta.Strokes.Count
        let group: Double = newStroke ? Double(n) : (n > 0 && meta.Strokes[n - 1].count > 4 ? meta.Strokes[n - 1][4] : Double(n))
        let st: [Double] = [x, y, BrushR(), brushErase ? 1 : 0, group]
        meta.Strokes.Add(st)
        let one = List<[Double]>(); one.Add(st)
        CuImg.ApplyStrokes(&viewPx, srcPx, src.Width, src.Height, one)
        RefreshView()
        Invalidate(LeftRect())
    }

    // ================= 畫 =================
    override func OnPaint(_ e: PaintEventArgs) {
        let g = e.Graphics
        g.SmoothingMode = SmoothingMode.None
        let W0 = ClientSize.Width, H0 = ClientSize.Height, F = 4 * U, crown = Sc(56)
        Pix.Wood(g, 0, 0, W0, H0, U, false, 23)
        Pix.Panel(g, F, crown, W0 - 2 * F, H0 - crown - F, U, false)
        let t = editId != nil ? "修改我的公仔" : "做一隻自己的公仔"
        let tw = Pix.TextW(t, titleF), plw = tw + 14 * U, plh = Sc(34)
        let pr = Rectangle((W0 - plw) / 2, (crown - plh) / 2 + U / 2, plw, plh)
        Pix.Plate(g, t, titleF, pr, U)
        Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.X - 9 * U, pr.Y + plh / 2 - 2 * U, U)
        Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.Right + 4 * U, pr.Y + plh / 2 - 2 * U, U)
        Steps(g, W0, Sc(68))
        var q: String, hint: String
        switch step {
        case 0: q = "選一張照片"; hint = "你家的貓、狗、娃娃、自己畫的角色都可以"
        case 1: q = "去背"; hint = srcAlpha && meta.UseAlpha ? "這張本來就是透明背景，直接用 ✓（有沒去乾淨的，用筆刷修）" : "灰格子＝透明。沒去乾淨就把強度調高、或用筆刷擦掉；主角被吃掉就調低、或用「補回」"
        case 2: q = "動起來"; hint = meta.Sheet ? "動作表的每一格會直接拿來用；空格會自動補動畫" : "兩條線把圖切成頭、身體、腳：走路會擺腳、點頭（拖線調位置）"
        default: q = "取名字、選個性"; hint = "個性會決定他講什麼話、怎麼動"
        }
        TextRenderer.DrawText(g, q, qF, Rectangle(0, Sc(98), W0, Sc(28)), Pix.TextC, Pix.Mid)
        TextRenderer.DrawText(g, hint, subF, Rectangle(Sc(20), Sc(126), W0 - Sc(40), Sc(18)), Pix.C(0x9A6338), [Pix.Mid, TextFormatFlags.EndEllipsis])
        if step == 0 { PaintPick(g) }
        else if step == 1 { PaintBg(g) }
        else if step == 2 { PaintRig(g) }
        else { PaintName(g) }
        for b in btns { DrawBtn(g, b) }
        if err != nil && err != "" { TextRenderer.DrawText(g, err, subF, Rectangle(Sc(170), H0 - Sc(64), W0 - Sc(370), Sc(44)), Pix.C(0xC0392B), [TextFormatFlags.HorizontalCenter, TextFormatFlags.VerticalCenter, TextFormatFlags.WordBreak, TextFormatFlags.NoPrefix]) }
    }

    func Steps(_ g: Graphics, _ W0: Int, _ y: Int) {
        let names: [String] = ["選照片", "去背", "動起來", "取名字"]
        let n = names.count, pw = Sc(104), ph = Sc(26), gap = Sc(14), x0 = (W0 - n * pw - (n - 1) * gap) / 2
        for i in 0..<n {
            let x = x0 + i * (pw + gap)
            if i > 0 { var sx = x - gap + U; while sx + U <= x - U { Pix.Box(g, Pix.C(0xD8BF94), sx, y + ph / 2 - U / 2, U, U); sx += 2 * U } }
            Pix.Round(g, i == step ? Pix.C(0x8A5A2A) : Pix.C(0xC9B08A), x, y, pw, ph, U)
            Pix.Box(g, i == step ? Pix.C(0xF6C453) : (i < step ? Pix.C(0xD9F0C4) : Pix.C(0xF3EADB)), x + U, y + U, pw - 2 * U, ph - 2 * U)
            let s = String(i + 1) + ". " + names[i]
            let sw = Pix.TextW(s, subF)
            var cx = x + (pw - sw) / 2
            if i < step { cx += 3 * U; Pix.Mono(g, Pix.CHECK, Pix.C(0x3F8A30), cx - 7 * U, y + ph / 2 - 3 * U, U) }
            TextRenderer.DrawText(g, s, subF, Rectangle(cx, y, sw + 4, ph), i <= step ? Pix.TextC : Pix.Dim, Pix.LeftMid)
        }
    }

    // 第一步：大大的「拖進來／點這裡」
    func PaintPick(_ g: Graphics) {
        let o: Btn! = Find("open")
        if o == nil { return }
        let r = o.R
        let hot = hoverId == "open"
        Pix.Box(g, hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0), r.X, r.Y, r.Width, r.Height)
        let dash = Pix.C(0xC08A2C)
        var x = r.X
        while x < r.Right { Pix.Box(g, dash, x, r.Y, 2 * U, U); Pix.Box(g, dash, x, r.Bottom - U, 2 * U, U); x += 4 * U }
        var y = r.Y
        while y < r.Bottom { Pix.Box(g, dash, r.X, y, U, 2 * U); Pix.Box(g, dash, r.Right - U, y, U, 2 * U); y += 4 * U }
        let pal = Dict<Character, Color>()
        pal["k"] = Pix.Ink; pal["w"] = Pix.C(0xFFFDF7); pal["b"] = Pix.C(0xBFE3F2); pal["p"] = Pix.C(0xF27A90); pal["o"] = Pix.C(0xE8A25A); pal["y"] = Pix.C(0xF6C453); pal["g"] = Pix.C(0x7CC36A)
        let c = Math.Max(3, Sc(5)), aw = CuMaker.CAT[0].Length * c
        Pix.Art(g, CuMaker.CAT, pal, r.X + (r.Width - aw) / 2, r.Y + Sc(22), c)
        TextRenderer.DrawText(g, "把照片拖進來，或點這裡選一張", bigF, Rectangle(r.X, r.Y + Sc(22) + CuMaker.CAT.count * c + Sc(10), r.Width, Sc(28)), Pix.TextC, Pix.Mid)
        TextRenderer.DrawText(g, "PNG・JPG・GIF・BMP 都可以", subF, Rectangle(r.X, r.Y + Sc(22) + CuMaker.CAT.count * c + Sc(40), r.Width, Sc(20)), Pix.C(0x9A6338), Pix.Mid)
        // 使用者指定的原字（v011 SPEC §4），不要改字
        let artH: Int = CuMaker.CAT.count * c
        TextRenderer.DrawText(g, CuMaker.CopyrightNote, subF, Rectangle(r.X, r.Y + Sc(22) + artH + Sc(62), r.Width, Sc(20)), Pix.C(0xB04040), Pix.Mid)
        if PhotoNoAlpha() { TextRenderer.DrawText(g, CuMaker.PortraitTip, subF, Rectangle(r.X, r.Y + Sc(22) + artH + Sc(82), r.Width, Sc(20)), Pix.C(0x9A6338), Pix.Mid) }   // 選過一張沒透明的照片
        // 小技巧
        let tip = Rectangle(r.X, r.Bottom + Sc(14), r.Width, Sc(78))
        Pix.Round(g, Pix.C(0xE6D3B0), tip.X, tip.Y, tip.Width, tip.Height, U)
        Pix.Box(g, Pix.C(0xFFF8EA), tip.X + U, tip.Y + U, tip.Width - 2 * U, tip.Height - 2 * U)
        let tips: [String] = [
            "・去背好的透明 PNG 效果最好；主角站在單純的背景前（白牆、地板）也很好去背。",
            "・背景很亂的照片：可以先用免費的線上去背工具做成透明 PNG，再放進來。",
            "・照片只存在你的電腦裡，不會上傳到任何地方。"]
        for i in 0..<tips.count { TextRenderer.DrawText(g, tips[i], subF, Rectangle(tip.X + Sc(12), tip.Y + Sc(8) + i * Sc(22), tip.Width - Sc(24), Sc(20)), Pix.TextC, [Pix.LeftMid, TextFormatFlags.EndEllipsis]) }
        let tb: Btn! = Find("template")
        if tb != nil { TextRenderer.DrawText(g, "進階：自己畫每個動作（動作表）、或匯入朋友傳來的公仔", smallF, Rectangle(r.X, tb.R.Y - Sc(22), r.Width, Sc(18)), Pix.C(0x9A6338), Pix.LeftMid) }
    }

    static let CopyrightNote = "千萬不要使用有版權的照片"
    func PhotoNoAlpha() -> Bool { return spr != nil && !meta.Sheet && !srcAlpha }
    static let PortraitTip = "人像照先在手機去背，用胸口以上的最可愛"

    static let CAT: [String] = [
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
        "....kkkkkkkkkk...."]

    // 棋盤格（透明的地方）
    static func Checker(_ g: Graphics, _ r: Rectangle, _ cell: Int) {
        let a = SolidBrush(Color.FromArgb(0xEE, 0xEA, 0xE2))
        let b = SolidBrush(Color.FromArgb(0xD9, 0xD3, 0xC8))
        var y = r.Y, j = 0
        while y < r.Bottom {
            var x = r.X, i = 0
            while x < r.Right {
                g.FillRectangle(((i + j) & 1) == 0 ? a : b, x, y, Math.Min(cell, r.Right - x), Math.Min(cell, r.Bottom - y))
                x += cell; i += 1
            }
            y += cell; j += 1
        }
    }

    // 第二步：去背
    func PaintBg(_ g: Graphics) {
        let l = LeftRect()
        Pix.Round(g, Pix.C(0x8A6A4A), l.X - U, l.Y - U, l.Width + 2 * U, l.Height + 2 * U, U)
        CuMaker.Checker(g, l, Sc(12))
        if meta.Sheet {
            if src != nil { let v = ViewRect(); g.DrawImage(src, v) }
        }
        else if src != nil && viewBmp != nil {
            let v = ViewRect()
            g.InterpolationMode = InterpolationMode.HighQualityBilinear
            // 被去掉的部分淡淡地留著（知道哪裡可以補回）
            do {
                let ia = ImageAttributes()
                let cm = ColorMatrix(); cm.Matrix33 = 0.13
                ia.SetColorMatrix(cm)
                g.DrawImage(srcDim, v, 0, 0, src.Width, src.Height, GraphicsUnit.Pixel, ia)
            }
            g.DrawImage(viewBmp, v)
            g.InterpolationMode = InterpolationMode.Default
            if brushOn {
                let cp = PointToClient(Cursor.Position)
                if v.Contains(cp) {
                    let rr = BrushR() * Double(Math.Max(v.Width, v.Height))
                    let pp = Pen(brushErase ? Color.FromArgb(220, 200, 60, 60) : Color.FromArgb(220, 50, 140, 70), 2.0)
                    g.SmoothingMode = SmoothingMode.AntiAlias; g.DrawEllipse(pp, Double(cp.X) - rr, Double(cp.Y) - rr, 2 * rr, 2 * rr); g.SmoothingMode = SmoothingMode.None
                }
            }
        }
        let r = RightRect()
        // 背景
        Section(g, "背景", r.X, r.Y)
        if meta.Sheet { TextRenderer.DrawText(g, "動作表每一格會自己去背", subF, Rectangle(r.X + Sc(10), r.Y + Sc(30), r.Width - Sc(20), Sc(20)), Pix.TextC, Pix.LeftMid) }
        else if srcAlpha && meta.UseAlpha { TextRenderer.DrawText(g, "本來就是透明背景 ✓", subF, Rectangle(r.X + Sc(190), r.Y + Sc(42), r.Width - Sc(200), Sc(30)), Pix.C(0x3F8A30), Pix.LeftMid) }
        else {
            let s = SliderRect()
            TextRenderer.DrawText(g, "去背強度  " + String(meta.Tol), subF, Rectangle(r.X + Sc(10), r.Y + Sc(26), r.Width, Sc(20)), Pix.TextC, Pix.LeftMid)
            Pix.Round(g, Pix.C(0x8A6A4A), s.X, s.Y + s.Height / 2 - 2 * U, s.Width, 4 * U, U)
            Pix.Box(g, Pix.C(0xF6C453), s.X + U, s.Y + s.Height / 2 - U, CInt(Double(s.Width - 2 * U) * Double(meta.Tol) / 100.0), 2 * U)
            let kx = s.X + CInt(Double(s.Width) * Double(meta.Tol) / 100.0) - 4 * U
            Pix.Round(g, Pix.Ink, kx, s.Y, 8 * U, s.Height, U)
            Pix.Box(g, Pix.C(0xFFFBF0), kx + U, s.Y + U, 6 * U, s.Height - 2 * U)
            TextRenderer.DrawText(g, "少去一點", smallF, Rectangle(s.X, s.Bottom + U, Sc(80), Sc(16)), Pix.C(0x9A6338), Pix.LeftMid)
            TextRenderer.DrawText(g, "多去一點", smallF, Rectangle(s.Right - Sc(80), s.Bottom + U, Sc(80), Sc(16)), Pix.C(0x9A6338), [TextFormatFlags.Right, TextFormatFlags.VerticalCenter])
        }
        Section(g, "修一下（在左邊的圖上塗）", r.X, r.Y + Sc(92))
        Section(g, "風格", r.X, r.Y + Sc(204))
        // 沒有透明的照片（人像照直接去背常常不乾淨，人像測試 v011\humantest）：提醒先在手機去背
        if PhotoNoAlpha() { TextRenderer.DrawText(g, CuMaker.PortraitTip, subF, Rectangle(r.X, r.Y + Sc(346), r.Width, Sc(36)), Pix.C(0x9A6338), [TextFormatFlags.Left, TextFormatFlags.Top, TextFormatFlags.WordBreak]) }
        // 實際大小預覽（桌面上就是這麼大）：左邊圖的右下角一小格
        if spr != nil {
            let mw = Sc(120), mh = Sc(104)
            let mini = Rectangle(l.Right - mw - Sc(6), l.Bottom - mh - Sc(6), mw, mh)
            Pix.Round(g, Pix.C(0x8A6A4A), mini.X - U, mini.Y - U, mini.Width + 2 * U, mini.Height + 2 * U, U)
            do { let lb = LinearGradientBrush(mini, Color.FromArgb(0x7D, 0x9E, 0xC8), Color.FromArgb(0x5B, 0x7D, 0xA8), 90.0); g.FillRectangle(lb, mini) }
            do { let bar = SolidBrush(Color.FromArgb(0x20, 0x22, 0x2A)); g.FillRectangle(bar, mini.X, mini.Bottom - Sc(16), mini.Width, Sc(16)) }
            Pet.CuDrawStill(g, spr, Double(mini.X) + Double(mini.Width) / 2.0, Double(mini.Bottom - Sc(16)), w.S, false, false, Color.White)
            TextRenderer.DrawText(g, "桌面上的大小", smallF, Rectangle(mini.X, mini.Bottom - Sc(16), mini.Width, Sc(16)), Color.White, Pix.Mid)
        }
    }

    func Section(_ g: Graphics, _ s: String, _ x: Int, _ y: Int) {
        TextRenderer.DrawText(g, s, btnF, Rectangle(x, y, Sc(320), Sc(24)), Pix.TextC, Pix.LeftMid)
        Pix.Box(g, Pix.C(0xE6D3B0), x, y + Sc(24), RightRect().Width, U)
    }

    // 第三步：兩條線＋動起來的預覽
    func PaintRig(_ g: Graphics) {
        let l = LeftRect()
        if spr == nil { return }
        let area = Rectangle(l.X, l.Y + Sc(42), l.Width, l.Height - Sc(42))
        Pix.Round(g, Pix.C(0x8A6A4A), area.X - U, area.Y - U, area.Width + 2 * U, area.Height + 2 * U, U)
        CuMaker.Checker(g, area, Sc(12))
        if meta.Sheet {
            // 動作表：每一格的結果
            let n = CuSprite.SheetKeys.count, cols = 4, cw = area.Width / cols, chh = area.Height / 2
            for i in 0..<n {
                let c = Rectangle(area.X + (i % cols) * cw, area.Y + (i / cols) * chh, cw, chh)
                var fb: Bitmap? = nil
                let key = CuSprite.SheetKeys[i]
                let has = spr.Frames.TryGetValue(key, &fb) && fb != nil
                if has {
                    let f: Bitmap = fb!
                    let s = Math.Min(Double(c.Width - Sc(16)) / Double(f.Width), Double(c.Height - Sc(36)) / Double(f.Height))
                    g.InterpolationMode = spr.Pixel ? InterpolationMode.NearestNeighbor : InterpolationMode.HighQualityBicubic
                    g.PixelOffsetMode = PixelOffsetMode.Half
                    g.DrawImage(f, Rectangle(c.X + (c.Width - CInt(Double(f.Width) * s)) / 2, c.Y + Sc(8), CInt(Double(f.Width) * s), CInt(Double(f.Height) * s)))
                    g.PixelOffsetMode = PixelOffsetMode.Default
                }
                TextRenderer.DrawText(g, CuSprite.SheetLabels[i] + (has ? "" : "（自動）"), subF, Rectangle(c.X, c.Bottom - Sc(24), c.Width, Sc(20)), has ? Pix.TextC : Pix.Dim, Pix.Mid)
            }
        }
        else {
            let sr = SpriteRect()
            g.InterpolationMode = spr.Pixel ? InterpolationMode.NearestNeighbor : InterpolationMode.HighQualityBicubic
            g.PixelOffsetMode = PixelOffsetMode.Half
            g.DrawImage(spr.Stand, sr)
            g.PixelOffsetMode = PixelOffsetMode.Default
            if meta.Rig {
                let ny = sr.Y + CInt(spr.NeckF * Double(sr.Height)), hy = sr.Y + CInt(spr.HipF * Double(sr.Height))
                Line(g, area, ny, Pix.C(0xE2557A), "頭", "身體")
                Line(g, area, hy, Pix.C(0x3D7BD9), "身體", "腳")
                // 兩隻腳的分界（虛線）
                let sx = sr.X + CInt(Double(spr.Split) / Double(spr.W) * Double(sr.Width))
                do { let p = Pen(Color.FromArgb(160, 0x3D, 0x7B, 0xD9), Math.Max(1, U / 2)); p.DashPattern = [3, 3]; p.DashStyle = DashStyle.Custom; g.DrawLine(p, sx, hy, sx, sr.Bottom) }
            }
        }
        // 右邊：動起來
        let pr = PreviewRect()
        DrawStage(g, pr)
        TextRenderer.DrawText(g, meta.Sheet ? "空著的格子用「站」那格自動動起來" : (meta.Rig ? "上下拖粉紅線、藍線，對準脖子和腿" : "沒切線：整隻一起搖搖晃晃（也很可愛）"), subF,
            Rectangle(pr.X, pr.Bottom + Sc(50), pr.Width, Sc(40)), Pix.C(0x9A6338), [TextFormatFlags.HorizontalCenter, TextFormatFlags.Top, TextFormatFlags.WordBreak, TextFormatFlags.NoPrefix])
    }

    func Line(_ g: Graphics, _ area: Rectangle, _ y: Int, _ c: Color, _ up: String, _ down: String) {
        Pix.Box(g, c, area.X, y - U / 2, area.Width, Math.Max(2, U))
        let tw = Math.Max(Pix.TextW(up, smallF), Pix.TextW(down, smallF)) + Sc(14)
        let tag = Rectangle(area.Right - tw - Sc(4), y - Sc(30), tw, Sc(58))
        Pix.Round(g, c, tag.X, tag.Y + Sc(8), tag.Width, Sc(18), U)
        Pix.Round(g, c, tag.X, tag.Y + Sc(32), tag.Width, Sc(18), U)
        TextRenderer.DrawText(g, "▲ " + up, smallF, Rectangle(tag.X, tag.Y + Sc(8), tag.Width, Sc(18)), Color.White, Pix.Mid)
        TextRenderer.DrawText(g, "▼ " + down, smallF, Rectangle(tag.X, tag.Y + Sc(32), tag.Width, Sc(18)), Color.White, Pix.Mid)
        // 左邊的把手
        Pix.Round(g, c, area.X - U, y - 3 * U, 6 * U, 6 * U, U)
        Pix.Box(g, Color.White, area.X + U, y - U, 2 * U, 2 * U)
    }

    // 小舞台：桌面色的背景＋公仔照選的動作動
    func DrawStage(_ g: Graphics, _ pr: Rectangle) {
        Pix.Round(g, Pix.C(0x8A6A4A), pr.X - U, pr.Y - U, pr.Width + 2 * U, pr.Height + 2 * U, U)
        do { let lb = LinearGradientBrush(pr, Color.FromArgb(0x8A, 0xAB, 0xD4), Color.FromArgb(0x5B, 0x7D, 0xA8), 90.0); g.FillRectangle(lb, pr) }
        do { let fl = SolidBrush(Color.FromArgb(0x20, 0x22, 0x2A)); g.FillRectangle(fl, pr.X, pr.Bottom - Sc(18), pr.Width, Sc(18)) }
        if pv == nil { return }
        let st = g.Save()
        g.SetClip(pr)
        let ps = Math.Max(2, w.S * 2)
        pv.CuPreview(g, Double(pr.X) + Double(pr.Width) / 2.0, Double(pr.Bottom - Sc(18)), ps, anim, animT, Double(pr.Width) / 2.0 - Double(Sc(50)))
        g.Restore(st)
    }

    // 第四步：名字＋個性
    func PaintName(_ g: Graphics) {
        let r = ContentRect()
        TextRenderer.DrawText(g, "他叫什麼名字？", bigF, Rectangle(r.X, r.Y + Sc(6), Sc(150), Sc(40)), Pix.TextC, Pix.LeftMid)
        let nf = Rectangle(r.X + Sc(150), r.Y + Sc(6), Sc(260), Sc(40))
        Pix.Round(g, Pix.C(0x8A6A4A), nf.X, nf.Y, nf.Width, nf.Height, U)
        Pix.Box(g, Color.FromArgb(0xFF, 0xFD, 0xF7), nf.X + U, nf.Y + U, nf.Width - 2 * U, nf.Height - 2 * U)
        if meta.Name == "" { TextRenderer.DrawText(g, "例如：小黑、麻糬、阿肥", subF, Rectangle(nf.X + Sc(14), nf.Y, nf.Width, nf.Height), Pix.Dim, Pix.LeftMid) }
        TextRenderer.DrawText(g, "最多 10 個字", smallF, Rectangle(nf.Right + Sc(10), nf.Y, Sc(120), nf.Height), Pix.C(0x9A6338), Pix.LeftMid)
        TextRenderer.DrawText(g, "個性", bigF, Rectangle(r.X, r.Y + Sc(54), Sc(150), Sc(26)), Pix.TextC, Pix.LeftMid)
        // 選到的個性：他會這樣跟你打招呼
        if draft != nil {
            var hi: [String]? = nil
            if draft.Lines.TryGetValue("hi", &hi) && hi != nil && hi!.count > 0 {
                let say = Rectangle(r.X, r.Bottom - Sc(56), r.Width, Sc(50))
                Pix.Round(g, Pix.C(0xE6D3B0), say.X, say.Y, say.Width, say.Height, U)
                Pix.Box(g, Pix.C(0xFFF8EA), say.X + U, say.Y + U, say.Width - 2 * U, say.Height - 2 * U)
                Pet.CuDrawStill(g, spr, Double(say.X + Sc(36)), Double(say.Bottom - Sc(4)), Math.Max(1, w.S / 2 + 1), false, false, Color.White)
                TextRenderer.DrawText(g, (meta.Name == "" ? "他" : meta.Name) + "：「" + World.NoEmoji(hi![0]) + "」", btnF, Rectangle(say.X + Sc(70), say.Y, say.Width - Sc(80), say.Height), Pix.TextC, [Pix.LeftMid, TextFormatFlags.EndEllipsis])
            }
        }
    }

    // 離屏截圖：TextBox 不會畫出來，自己畫名字
    func DrawNameText(_ g: Graphics) {
        if meta.Name == "" { return }
        let r = ContentRect()
        let nf = Rectangle(r.X + Sc(150), r.Y + Sc(6), Sc(260), Sc(40))
        TextRenderer.DrawText(g, meta.Name, nameBox.Font, Rectangle(nf.X + Sc(12), nf.Y, nf.Width - Sc(24), nf.Height), Pix.TextC, Pix.LeftMid)
    }

    func DrawBtn(_ g: Graphics, _ b: Btn) {
        let r = b.R
        let hot = b.Id == hoverId && b.Enabled
        if b.Id == "open" { return }   // 第一步的大框自己畫
        if b.Kind >= 2 {
            let small = b.Kind == 4
            let face: Color = !b.Enabled ? Pix.C(0xE9E0D0) : (b.Kind == 3 ? (hot ? Pix.C(0xFFD36A) : Pix.C(0xF6C453)) : (b.On ? Pix.C(0xFFE08A) : (hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0))))
            let shade: Color = !b.Enabled ? Pix.C(0xD3C7B2) : (b.Kind == 3 || b.On ? Pix.C(0xC8902C) : Pix.C(0xDCC6A2))
            Pix.Round(g, !b.Enabled ? Pix.C(0xBBA98C) : Pix.Ink, r.X, r.Y, r.Width, r.Height, U)
            Pix.Box(g, face, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U)
            Pix.Box(g, shade, r.X + U, r.Bottom - (small ? 2 : 3) * U, r.Width - 2 * U, (small ? 1 : 2) * U)
            let f: FontT = small ? subF : btnF
            TextRenderer.DrawText(g, b.Text, f, Rectangle(r.X, r.Y, r.Width, r.Height - (small ? U : 2 * U)), b.Enabled ? Pix.TextC : Pix.Dim, Pix.Mid)
            return
        }
        let edge = b.On ? Pix.C(0xC08A2C) : Pix.C(0x8A6A4A)
        let fill = b.On ? Pix.C(0xFFEDB8) : (hot ? Pix.C(0xFFF6DE) : Pix.C(0xFFFDF7))
        Pix.Round(g, Pix.C(0xE6D3B0), r.X + 2 * U, r.Y + 2 * U, r.Width, r.Height, U)
        Pix.Round(g, edge, r.X, r.Y, r.Width, r.Height, U)
        let ins = b.On ? 2 * U : U
        if b.On { Pix.Box(g, edge, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U) }
        Pix.Box(g, fill, r.X + ins, r.Y + ins, r.Width - 2 * ins, r.Height - 2 * ins)
        if b.Id.StartsWith("persona:") {
            let id = b.Id.Substring(8)
            TextRenderer.DrawText(g, b.Text, bigF, Rectangle(r.X + Sc(12), r.Y + Sc(8), r.Width - Sc(24), Sc(28)), Pix.TextC, Pix.LeftMid)
            TextRenderer.DrawText(g, Pal.PersonaDesc(id), subF, Rectangle(r.X + Sc(12), r.Y + Sc(38), r.Width - Sc(24), Sc(36)), Pix.C(0x9A6338), [TextFormatFlags.Left, TextFormatFlags.Top, TextFormatFlags.WordBreak, TextFormatFlags.NoPrefix])
        }
        else {
            let sub = b.Id == "pixel" ? "跟內建公仔同畫風" : "照片原本的樣子"
            TextRenderer.DrawText(g, b.Text, btnF, Rectangle(r.X, r.Y + Sc(6), r.Width, Sc(24)), Pix.TextC, Pix.Mid)
            TextRenderer.DrawText(g, sub, smallF, Rectangle(r.X + Sc(4), r.Y + Sc(30), r.Width - Sc(8), Sc(20)), Pix.C(0x9A6338), [Pix.Mid, TextFormatFlags.EndEllipsis])
        }
        if b.On {
            let s = 7 * U, bx = r.Right - s - 2 * U, by2 = r.Y + 2 * U
            Pix.Round(g, Pix.C(0x2F6E24), bx, by2, s, s, U)
            Pix.Box(g, Pix.C(0x5FB04A), bx + U, by2 + U, s - 2 * U, s - 2 * U)
        }
    }
}

// ================= 預覽：做公仔視窗、分享短片用（不改真的公仔） =================
extension Pet {
    // 照指定的動作畫一格（走路左右來回、跳、睡、開心冒愛心、被抓著晃）
    func CuPreview(_ g: Graphics, _ cx: Double, _ feetY: Double, _ ps: Int, _ act: String, _ t: Double, _ range: Double) {
        var fx = cx, fy = feetY
        var d = 1
        anim = t; rolling = false; cuAct = ""; cuLandT = 0; vy = 0; knock = 0
        switch act {
        case "walk":
            let per = 6.0, ph = (t % per) / per          // 來回走
            let tri = ph < 0.5 ? ph * 2 : 2 - ph * 2
            fx = cx - range + tri * 2 * range; d = ph < 0.5 ? 1 : -1
            state = "walk"
        case "jump":
            let c = t % 1.4
            if c < 0.8 { state = "air"; let u = c / 0.8; fy -= Math.Sin(u * Math.PI) * Double(ps) * 9; vy = u < 0.5 ? -1 : 1 }
            else { state = "idle"; cuLandT = Math.Max(0.0, 0.2 - (c - 0.8)) }
        case "sleep": state = "sleep"; z = t
        case "happy": state = "hug"
        case "held": state = "drag"; fy -= Double(ps * 3)
        default: state = "idle"
        }
        dir = d
        CuPoseNow(cuPose)
        CuDraw(g, cuPose, fx, fy, ps, d < 0)
        let hp = Math.Max(2, ps / 2)
        if act == "sleep" {
            for i in 0..<3 {
                let p = (t * 0.6 + Double(i) / 3.0) % 1
                if p > 0.85 { continue }
                DrawPix(g, Pet.ZZ, CInt(fx + P.Spr.Wc / 2 * Double(ps) + p * 6 * Double(ps)), CInt(fy - P.Spr.Hc * Double(ps) - p * 10 * Double(ps)), hp, false, false, false)
            }
        }
        if act == "happy" {
            for i in 0..<3 {
                let p = (t * 0.7 + Double(i) / 3.0) % 1
                DrawPix(g, Pet.HEART, CInt(fx + Double((i - 1) * 5 * ps) + Math.Sin(p * 6 + Double(i)) * Double(ps)), CInt(fy - P.Spr.Hc * Double(ps) - Double(2 * ps) - p * 9 * Double(ps)), hp, false, false, true)
            }
        }
    }
}

// ================= World：開「做公仔」視窗、測試用 pipe 指令 =================
//@@IN World
    var maker: CuMaker! = nil
//@@END

extension World {
    func CuOpenMaker(_ editId: String!, _ first: Bool) {
        if maker != nil && !maker.IsDisposed { maker.Close() }
        maker = CuMaker(self, first, editId)
        let wa: Rectangle = App.Offscreen ? screens[0].WorkingArea : Screen.FromPoint(Cursor.Position).WorkingArea
        maker.Location = Point(wa.Left + (wa.Width - maker.Width) / 2, wa.Top + Math.Max(0, (wa.Height - maker.Height) / 2))
        maker.Show()
        if App.Offscreen { return }
        ActivateForm(maker)
        let mk: CuMaker = maker
        Later(0.2) { if !mk.IsDisposed && mk.Visible { self.ActivateForm(mk) } }
    }

    func CuSnap(_ g: Graphics) {
        if maker != nil && !maker.IsDisposed && maker.VVisible { maker.PaintTo(g) }
    }

    func CuSaveTemplateDialog() {
        if App.Offscreen { App.Log("custom: template dialog skipped (offscreen)"); return }
        // mac: SaveFileDialog（PNG 圖片）→ NSSavePanel
        guard let file = CuDialogs.Save("存動作表範本", "DeskPals動作表範本.png", ["png"], World.UserFolder(Environment.SpecialFolder.DesktopDirectory, "", "Desktop")) else { return }
        World.CuSaveTemplate(file)
        Lead().Say("範本存好了：每一格畫一個動作，畫好再按「上傳畫好的動作表」🎨", 4)
    }

    static func CuSaveTemplate(_ path: String) {
        let b: Bitmap! = CuSprite.Template()
        if b == nil { App.Log("template: failed"); return }
        b.Save(path, ImageFormat.Png)
    }

    // pipe：custom <指令> …（測試、VS Code 用）
    func CuMsg(_ c: Client, _ line: String) {
        let t = line.Trim()
        let p = t.Split(" ")
        if p.count < 2 { return }
        let cmd = p[1]
        let rest = p.count > 2 ? t.Substring(t.IndexOf(" ", t.IndexOf(" ") + 1) + 1) : ""
        var a0 = 0.0, a1 = 0.0, a2 = 0.0, a3 = 0.0
        if p.count > 2 { _ = double.TryParse(p[2], &a0) }   // NumberStyles.Float, InvariantCulture
        if p.count > 3 { _ = double.TryParse(p[3], &a1) }
        if p.count > 4 { _ = double.TryParse(p[4], &a2) }
        if p.count > 5 { _ = double.TryParse(p[5], &a3) }
        let mk = maker != nil && !maker.IsDisposed
        switch cmd {
        case "list": World.Send(c, "pals " + CuPalsJson() + "\n"); return
        case "new": CuOpenMaker(nil, false)
        case "first": CuOpenMaker(nil, true)
        case "edit": CuOpenMaker(rest, false)
        case "import": if !mk { CuOpenMaker(nil, false) }; maker.LoadImage(rest, false)
        case "sheet": if !mk { CuOpenMaker(nil, false) }; maker.LoadImage(rest, true)
        case "template": World.CuSaveTemplate(rest)
        case "tol": if mk { maker.SetTol(CInt(a0)) }
        case "lines": if mk { maker.SetLines(a0, a1) }
        case "brush": if mk { maker.Brush(p.count > 2 && p[2] == "erase", a1, a2, a3) }
        case "name": if mk { maker.SetName(rest) }
        case "step": if mk { maker.SetStep(CInt(a0)) }
        case "anim": if mk { maker.SetAnim(p.count > 2 ? p[2] : "walk", a1) }
        case "press": if mk { maker.Press(rest) }
        case "cancel": if mk { maker.Press("cancel") }
        case "delete": CuDelete(rest)
        case "export": if p.count > 3 { CuExport(p[2], t.Substring(t.IndexOf(p[2]) + p[2].Length + 1)) }
        case "importpal": CuImportFile(rest, false)
        case "mine":
            let l = List<String>(rest.Split(Character(","), StringSplitOptions.RemoveEmptyEntries))
            Pal.SaveMine(l)
            if lineup == Pal.Mine { CuReload(l.Count > 0 ? l[0] : "") } else if OrigLineup { CuReload("") } else { CuStore.Reset(false) }
        case "callout": CuCallOut(rest)
        case "fakewin": CuSetFakeWin(Rectangle(CInt(a0), CInt(a1), CInt(a2), CInt(a3)))   // 測試：custom fakewin x y w h
        case "pet":
            // 測試：custom pet <id> <動作>（loaf push ignore wag fetch return jumpwin）
            let tp: Pet! = Get(p.count > 2 ? p[2] : "")
            if tp != nil && p.count > 3 { tp.CuTest(p[3]) }
        case "share": if rest.Trim() == "" { ShareClip(nil) } else { ShareClipTo(rest, nil) }
        case "icon":
            // custom icon <id> <ps> <png>
            let m: CuMeta! = p.count > 4 ? CuStore.Get(p[2]) : nil
            let s: CuSprite! = m == nil ? nil : CuStore.Sprite(m)
            if s != nil { let b: Bitmap! = CuStore.Icon(m, s, CInt(Math.Max(1.0, a1))); if b != nil { b.Save(p[4], ImageFormat.Png) } }
        default: break
        }
        World.Send(c, "custom-ok " + cmd + "\n")
    }
}
