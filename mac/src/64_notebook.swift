// 64_notebook.swift — port of extension/desktop/DeskPals.Notebook.cs
// Desk Pals：小本子（待辦／今天做了／筆記）。446 寬、停在公仔櫃左邊；上緣三個索引頁籤，「攤開」變成左右兩頁（待辦＋筆記｜今天做了）。
// 資料、合併、要貼出去的字都在 DeskPals.NotebookData.cs；這支只管畫、點、打字、跟 World 接（學校行事曆、泡泡、剪貼簿、pipe）。
// 畫法跟像素選單、設定視窗同一套（Pix.*、木框、奶油色面板、銅牌、像素按鈕），字型 Microsoft JhengHei UI。
// 打字用真的 TextBox／RichTextBox（中文輸入法才打得了），其他全部自己畫；離屏測試（DESKPALS_OFFSCREEN=1）時字也自己畫，snap 才看得到。
//
// 掛在 DeskPals.cs 的地方（都只有一行，標 // 小本子）：HouseMenu「工作」→「小本子…」、公仔右鍵 →「小本子…」、OnMsg 的 default → NbMsg()、Snap → NbSnap()。
// pipe 指令（測試用的只在離屏模式）：
//   nb-open [todo|done|note]、nb-close、nb-info（現在畫了什麼）、nb-clip（剛剛「複製」了什麼字，不碰真的剪貼簿）
//   nb-text simple|detail|links（現在會貼出去的字）、nb-act <動作> [參數]（跟滑鼠點一樣，見 Do()）、nb-click <x> <y>、nb-hover <x> <y>
//   nb-type todo|done|edit|note <字…>（打字）、nb-key todo|done|edit enter|esc、nb-key alt-up|alt-down
//   時間用 study-clock（跟讀書小幫手同一個假時鐘）
//
// mac 差異（都標了 // mac:）：
// - RichTextBox → 06_shim_notebook.swift（NSScrollView＋NSTextView，純文字、固定行高、線畫在字底下）；PARAFORMAT2／SendMessage 不用。
// - TextBox 的 LostFocus → NbTextBox（06_shim_notebook.swift）；外框 BorderStyle.None → CuMaker.Borderless；提示字 EM_SETCUEBANNER → placeholder。
// - ProcessCmdKey（Esc、Alt+↑↓ 先給表單）→ 打字框自己的 KeyDown 一開始、表單的 OnKeyDown（KeyPreview）都先問 ProcessCmdKey(keyData)。
// - 沒有「編輯」選單：Cmd+X／C／V／A／Z 在表單的 OnKeyDown 送給 first responder（NbEditKeys）。
// - 字：Windows 用 GDI+ 畫兩次（第二次右移 PixText.Heft 加粗）；mac 用 CoreText 畫一次。
// - 無框視窗要能打字：_overlayKeyable；不是最上層（C# 沒設 TopMost）：_overlayLevel = .normal。
// - 拖上面的木框搬家：ReleaseCapture＋WM_NCLBUTTONDOWN → NSWindow.performDrag。
// - 滾輪：mac 的 delta 很小（觸控板），用 Double 算，不用 C# 的整數 /120。
// - 減少動態：SystemInformation.UIEffectsEnabled → NSWorkspace.accessibilityDisplayShouldReduceMotion。
// - 剪貼簿：Clipboard.SetText（NSPasteboard），換行照 mac 用 \n。
import Foundation
import AppKit

// 筆記用的紙：固定 28px 一行（RichEdit 的固定行高），每行底下一條線
final class NbNoteBox: RichTextBox {
    // mac: PARAFORMAT2／SendMessage(EM_SETPARAFORMAT) 不用：固定行高＝NSParagraphStyle（06_shim_notebook.swift 的 _SetLineHeight）
    var LineH = 28
    var LineC = Pix.C(0xEFE0C4)
    override init() {
        super.init()
        // mac: BorderStyle = BorderStyle.None → NSScrollView 本來就沒有外框
        ScrollBars = RichTextBoxScrollBars.Vertical
        DetectUrls = false
        ShortcutsEnabled = true
    }
    // mac: OnHandleCreated → NSTextView 建好的時候（Controls.Add）
    override func _create() { super._create(); Spacing() }
    // 整篇固定行高（新打的字照前一段的格式，貼上的也是）
    func Spacing() {
        if !IsHandleCreated { return }
        _SetLineHeight(LineH)   // mac: PFM_LINESPACING（固定）→ 段落最小＝最大行高＝LineH，打字、貼上的字都照 typingAttributes
    }
    // mac: WndProc(WM_PAINT) 字畫完再畫線 → NSTextView 畫背景時（字底下）畫；座標是文件座標，捲動時線跟著字走（OnVScroll 不用）
    override func _PaintUnder(_ g: Graphics, _ y0: Int, _ top: Int, _ bottom: Int, _ width: Int) { Lines2(g, y0, top, bottom, width) }
    func Lines2(_ g: Graphics, _ y0: Int, _ top: Int, _ bottom: Int, _ width: Int) {
        let b = SolidBrush(LineC)
        var y = y0 + LineH - 2
        while y < bottom { if y >= top - 1 { g.FillRectangle(b, 0, y, width, 1) }; y += LineH }
    }
    override func OnTextChanged(_ e: EventArgs) { super.OnTextChanged(e); Invalidate() }
    // mac: ProcessCmdKey(Ctrl+V／Shift+Insert)「只貼純文字」→ NSTextView.isRichText = false 本來就只貼純文字（Cmd+V 見 NbEditKeys）
}

final class NotebookForm: Form {
    // ---- 顏色（mockup：C:\tmp\dp\worklog-ui\v5-tabs-b）----
    static let CText = Pix.C(0x4A3010), CSub = Pix.C(0x6B5238), CTime = Pix.C(0x8F6B44), COk = Pix.C(0x2F7A22), COkHot = Pix.C(0x24661A)
    static let CBad = Pix.C(0xB8433F), CPh = Pix.C(0x8A6A4C), COff = Pix.C(0x8C7B62), CGh = Pix.C(0x7A4A22), CGhLine = Pix.C(0xE2CFAE), CBar = Pix.C(0xF7EBD2)
    static let CBarEdge = Pix.C(0xD8BF94), CPaper = Pix.C(0xFFFDF7), CNote = Pix.C(0x3A2A18), CTabText = Pix.C(0x5A3E22), CField = Pix.C(0xC9B08A), CBtn = Pix.C(0xFFFBF0)
    static let TabC: [Color] = [Pix.C(0xF6C453), Pix.C(0xA9D394), Pix.C(0xF3B3BE)], TabBg: [Color] = [Pix.C(0xF9E2A4), Pix.C(0xD5EAC8), Pix.C(0xF8D5DB)]
    static let TabKey: [String] = ["todo", "done", "note"], TabName: [String] = ["待辦", "今天做了", "筆記"]
    static let KEY = Color.FromArgb(255, 0, 255)

    // ---- 像素小圖（8×8 以內；k＝深色描邊）----
    static let ICLAUDE: [String] = ["kkkkkkkk", "kddddddk", "kdgddddk", "kddgdddk", "kdgdggdk", "kddddddk", "kkkkkkkk"]
    static let IJIRA: [String] = ["kkkkkkkk", "kbbbbbbk", "kbwwwwbk", ".kbbbbk.", "kbwwwbbk", "kbbbbbbk", "kkkkkkkk"]
    static let IMR: [String] = [".k...k.", "kpk.kpk", ".k...k.", ".k..k..", ".k.k...", ".kk....", "kpk....", ".k....."]
    static let IMEET: [String] = [".k...k..", "kkkkkkkk", "krrrrrrk", "kwwwwwwk", "kwkwkwwk", "kwwwwwwk", "kwkwwwwk", "kkkkkkkk"]
    static let ICLASS: [String] = ["kkkkkkk.", "kggggggk", "kgwwwwgk", "kggggggk", "kggggggk", "kggggggk", "kwwwwwwk", "kkkkkkkk"]
    static let IHW: [String] = ["kkkkk...", "kwwwwk..", "kwkkwwk.", "kwwwwwwk", "kwkkkkwk", "kwwwwwwk", "kwkkkwwk", "kkkkkkkk"]
    static let ICAL: [String] = [".k...k.", "kkkkkkk", "kwwwwwk", "kwkwkwk", "kwwwwwk", "kkkkkkk"]
    static let IGEAR: [String] = [".k.k.", "kkkkk", "kk.kk", "kkkkk", ".k.k."]
    static let IPLUS: [String] = ["..k..", "..k..", "kkkkk", "..k..", "..k.."]
    static let ILEFT: [String] = ["..k", ".kk", "kkk", ".kk", "..k"], IRIGHT: [String] = ["k..", "kk.", "kkk", "kk.", "k.."], IDOWN: [String] = ["kkkkk", ".kkk.", "..k.."]
    static let IX: [String] = ["k...k", ".k.k.", "..k..", ".k.k.", "k...k"]
    static let IGRIP: [String] = ["k.k", "...", "k.k", "...", "k.k"]

    let w: World
    let d: Double
    let U: Int
    let fPlate: FontT, fBody: FontT, fWord: FontT, fSmall: FontT, fBar: FontT, fBtn: FontT, fBtnS: FontT, fNote: FontT, fPv: FontT, fPvB: FontT, fField: FontT
    var VVisible = false

    // ---- 狀態 ----
    var Tab = "done", LastTab = "done"
    var Spread = false, Preview = false, Links = false
    var PvKind = "detail"
    var Day = DateTime.MinValue
    var copied = ""; var copiedUntil = 0.0
    var things = List<NbThing>()
    var todos = List<NbTodo>()
    var jira = List<NbFact>()
    var edits = NbEdits()
    var savedAt = ""
    var noteDirty = false; var noteSaveAt = 0.0
    var logStamp = ""
    var nextRefresh = 0.0
    // 剛勾掉的待辦：先留在原地畫刪除線＋「▶ 今天做了」，一下子再消失（這段時間再點一次＝取消）
    final class Just { var T: NbTodo! = nil; var Index = 0; var LogId = ""; var Until = 0.0; init() {} }
    let justDone = List<Just>()
    // 滑鼠、編輯、拖曳
    var hoverThing = "", hoverTodo = "", hoverAct = "", editThing = "", editTodo = "", lastTodo = ""
    var dragTodo = ""; var dragY = 0, dragStartY = 0; var dragging = false
    let scroll = Dict<String, Int>()
    let contentH = Dict<String, Int>()
    let clipR = Dict<String, RectangleT>()
    // 待辦的期限（新增那一行右邊的小日曆）
    var duePick = false; var dueDay = DateTime.MinValue; var dueMin = -1
    final class Hit { var Act = "", Arg = ""; var R = RectangleT.Empty; var Hover: String? = nil; init() {} }
    let hits = List<Hit>()
    let todoRows = Dict<String, RectangleT>()
    let Drawn = List<String>()   // 測試用（nb-info）：這次畫了哪些東西

    // 打字的地方
    var tbTodo: NbTextBox! = nil, tbDone: NbTextBox! = nil, tbEdit: NbTextBox! = nil   // mac: NbTextBox＝TextBox＋LostFocus
    let note: NbNoteBox
    var rTodo = RectangleT.Empty, rDone = RectangleT.Empty, rEdit = RectangleT.Empty, rNote = RectangleT.Empty   // 這次畫出來的位置（看不到＝Empty）
    var noteFor = ""                    // 筆記框現在是哪一天的
    let timer = Timer()

    init(_ w: World) {
        self.w = w
        let dd = Double(w.S) / 4.0
        d = dd
        U = Math.Max(2, CInt(Math.Round(2 * dd)))
        let jh = "Microsoft JhengHei UI"
        // 自己畫的字：像素大小（跟 mockup 一樣 14.7／13.3／11.3／12px），用 GDI+ 反鋸齒畫（見 DT）
        fPlate = NotebookForm.Px(jh, 14.667 * dd, FontStyle.Bold)
        fBody = NotebookForm.Px(jh, 14.667 * dd, FontStyle.Bold)
        fWord = NotebookForm.Px(jh, 13.333 * dd, FontStyle.Bold)
        fSmall = NotebookForm.Px(jh, 11.333 * dd, FontStyle.Bold)
        fBar = NotebookForm.Px(jh, 12 * dd, FontStyle.Bold)
        fBtn = NotebookForm.Px(jh, 13.333 * dd, FontStyle.Bold)
        fBtnS = NotebookForm.Px(jh, 11.333 * dd, FontStyle.Bold)
        fNote = NotebookForm.Px(jh, 14.667 * dd, FontStyle.Regular)
        fPv = NotebookForm.Px(jh, 13.333 * dd, FontStyle.Regular)
        fPvB = NotebookForm.Px(jh, 13.333 * dd, FontStyle.Bold)
        fField = NotebookForm.Px(jh, 13.333 * dd, FontStyle.Bold)
        note = NbNoteBox()
        super.init()
        Text = "小本子"
        FormBorderStyle = FormBorderStyleT.None
        ShowInTaskbar = true
        StartPosition = FormStartPosition.Manual
        BackColor = NotebookForm.KEY; TransparencyKey = NotebookForm.KEY      // 左邊的線圈凸出木框外面
        KeyPreview = true
        SetStyle([ControlStyles.OptimizedDoubleBuffer, ControlStyles.AllPaintingInWmPaint, ControlStyles.UserPaint, ControlStyles.ResizeRedraw], true)
        // 真的打字框（TextBox／RichTextBox）用 pt 字型，跟系統縮放走
        tbTodo = MakeBox(FontT(jh, 10, FontStyle.Bold), "寫一件要做的事，按 Enter")
        tbDone = MakeBox(FontT(jh, 10, FontStyle.Bold), "補一件做過的事，按 Enter")
        tbEdit = MakeBox(FontT(jh, 11, FontStyle.Bold), "")
        note.Font = FontT(jh, 11, FontStyle.Regular); note.BackColor = NotebookForm.CPaper; note.ForeColor = NotebookForm.CNote; note.LineH = Sc(28); note.Visible = false
        note.TextChanged = { [weak self] in guard let s = self else { return }; if s.note.Tag == nil { s.noteDirty = true; s.noteSaveAt = s.w.Now + 0.7 } }
        note.LostFocus = { [weak self] in self?.Invalidate() }
        Controls.Add(note)
        tbTodo.KeyDown = { [weak self] (e: KeyEventArgs) in
            guard let s = self else { return }
            if s.ProcessCmdKey(e.KeyData) { e.Handled = true; return }   // mac: C# 的表單 ProcessCmdKey 比 TextBox 的 KeyDown 先拿到 Esc、Alt+↑↓
            if e.KeyCode == Keys.Enter { e.SuppressKeyPress = true; s.Key("todo", "enter") } else if e.KeyCode == Keys.Escape { e.SuppressKeyPress = true; s.Key("todo", "esc") }
        }
        tbDone.KeyDown = { [weak self] (e: KeyEventArgs) in
            guard let s = self else { return }
            if s.ProcessCmdKey(e.KeyData) { e.Handled = true; return }   // mac: 同上
            if e.KeyCode == Keys.Enter { e.SuppressKeyPress = true; s.Key("done", "enter") } else if e.KeyCode == Keys.Escape { e.SuppressKeyPress = true; s.Key("done", "esc") }
        }
        tbEdit.KeyDown = { [weak self] (e: KeyEventArgs) in
            guard let s = self else { return }
            if s.ProcessCmdKey(e.KeyData) { e.Handled = true; return }   // mac: 同上
            if e.KeyCode == Keys.Enter { e.SuppressKeyPress = true; s.Key("edit", "enter") } else if e.KeyCode == Keys.Escape { e.SuppressKeyPress = true; s.Key("edit", "esc") }
        }
        tbEdit.LostFocus = { [weak self] in guard let s = self else { return }; if s.editThing != "" || s.editTodo != "" { s.Key("edit", "enter") } }
        tbTodo.TextChanged = { [weak self] in self?.Invalidate() }
        tbDone.TextChanged = { [weak self] in self?.Invalidate() }
        timer.Interval = 250
        timer.Tick = { [weak self] in self?.Tick() }
        timer.Start()
        Day = w.NbNow().Date
        FormClosed = { [weak self] in guard let s = self else { return }; s.timer.Stop(); s.SaveNote(); s.w.NbClosed(s) }
    }

    // mac: 無框視窗（C#：沒有 WS_EX_NOACTIVATE 的一般視窗）要能拿鍵盤焦點才打得了字；C# 沒設 TopMost → 一般視窗那一層
    override var _overlayKeyable: Bool { return true }
    override var _overlayLevel: NSWindow.Level { return .normal }

    func MakeBox(_ f: FontT, _ cue: String) -> NbTextBox {
        let t = NbTextBox()
        t.Font = f; t.BackColor = NotebookForm.CPaper; t.ForeColor = NotebookForm.CText; t.Visible = false
        t.Tag = cue
        Controls.Add(t)
        CuMaker.Borderless(t, NotebookForm.CPaper)   // mac: BorderStyle = BorderStyle.None
        // mac: EM_SETCUEBANNER（打字時也留著提示）→ NSTextField 的 placeholder（空的時候一直都在，打字才消失）
        if cue != "" {
            t.PlaceholderText = cue
            t.tf?.placeholderAttributedString = NSAttributedString(string: cue, attributes: [.foregroundColor: NotebookForm.CPh.ns, .font: _formsNSFont(f)])
        }
        return t
    }

    func Sc(_ v: Int) -> Int { return CInt(Math.Round(Double(v) * d)) }
    var OV: Int { return Sc(10) }                  // 左邊凸出去的線圈
    var FrameW: Int { return Sc(Spread ? 760 : 446) }
    var FrameH: Int { return Sc(Spread ? 636 : 670) }
    var Want: SizeT { return SizeT(FrameW + OV, FrameH) }

    // ---- 離屏測試模式：不真的顯示，snap 時畫到虛擬螢幕上 ----
    override func SetVisibleCore(_ value: Bool) {
        if App.Offscreen { VVisible = value; super.SetVisibleCore(false); return }
        super.SetVisibleCore(value)
    }
    func PaintTo(_ g: Graphics) {
        let cs = ClientSize
        if cs.Width <= 0 || cs.Height <= 0 { return }
        let b = Bitmap(cs.Width, cs.Height, PixelFormat.Format24bppRgb)
        do { let gg = Graphics.FromImage(b); OnPaint(PaintEventArgs(gg, RectangleT(0, 0, cs.Width, cs.Height))) }
        // mac: KEY 色畫上去就是透明，不用 MakeTransparent
        g.DrawImageUnscaled(b, Left, Top)
    }

    // ================= 資料 =================
    var Dir: String { return Nb.Dir(World.DataDir) }
    var IsToday: Bool { return Day == w.NbNow().Date }

    func Reload() {
        let facts = Nb.ReadLog(Dir, Day)
        Nb.AddClasses(facts, w.NbClasses(Day))
        edits = Nb.LoadEdits(Dir, Day)
        things = Nb.Build(facts, edits)
        todos = w.NbTodos()
        jira = Nb.JiraTodos(Dir)
        logStamp = Stamp()
        if noteFor != Nb.Ymd(Day) { LoadNote() }
        Invalidate()
    }
    func Stamp() -> String {
        let a = FileInfo(Nb.LogPath(Dir, Day)), b = FileInfo(Nb.TodoPath(Dir))
        let sa: String = a.Exists ? String(a.LastWriteTimeUtc.Ticks) + ":" + String(a.Length) : "-"
        let sb: String = b.Exists ? String(b.LastWriteTimeUtc.Ticks) + ":" + String(b.Length) : "-"
        return sa + "|" + sb + "|" + w.NbSchoolStamp()
    }

    func LoadNote() {
        SaveNote()
        noteFor = Nb.Ymd(Day)
        note.Tag = "loading"
        note.Text = Nb.ReadFile(Nb.NotePath(Dir, Day)).Replace("\r\n", "\n")
        note.Tag = nil
        note.Spacing()
        noteDirty = false
        savedAt = ""
        let fi = FileInfo(Nb.NotePath(Dir, Day))
        if fi.Exists && note.Text != "" { savedAt = Nb.Hm(fi.LastWriteTime) }
    }
    func SaveNote() {
        if !noteDirty || noteFor == "" { return }
        noteDirty = false
        var day = DateTime.MinValue
        if !_NbParseYmd(noteFor, &day) { return }   // mac: DateTime.TryParseExact(noteFor, "yyyy-MM-dd", …)
        let path = Nb.NotePath(Dir, day), text = note.Text.Replace("\r\n", "\n")
        if text.Trim() == "" { if File.Exists(path) { try? File.Delete(path) }; savedAt = "" }
        else { Nb.WriteFile(path, text); savedAt = Nb.Hm(w.NbNow()) }
        Invalidate()
    }

    func Tick() {
        let now = w.Now
        if noteDirty && now >= noteSaveAt { SaveNote() }
        if copied != "" && now >= copiedUntil { copied = ""; Invalidate() }
        var drop = false
        var i = justDone.Count - 1
        while i >= 0 { if now >= justDone[i].Until { justDone.RemoveAt(i); drop = true }; i -= 1 }
        if drop { Invalidate() }
        if now >= nextRefresh {
            nextRefresh = now + 3
            if Stamp() != logStamp && editThing == "" && editTodo == "" && !dragging { Reload() }
        }
    }

    // ================= 動作（滑鼠、鍵盤、測試都走這裡）=================
    func Do(_ act: String, _ arg: String) {
        switch act {
        case "close": Close(); return
        case "tab": if NotebookForm.TabKey.IndexOf(arg) >= 0 { Tab = arg; LastTab = arg; Preview = false; duePick = false; EndEdit(true); w.NbSaveUi(self); FocusFor() }
        case "spread":
            EndEdit(true)
            if !Spread { LastTab = Tab; Spread = true } else { Spread = false; Tab = LastTab }
            duePick = false
            w.NbPlace(self)
            w.NbSaveUi(self)
        case "prev": GoDay(Day.AddDays(-1)); return
        case "next": if !IsToday { GoDay(Day.AddDays(1)) }; return
        case "today": GoDay(w.NbNow().Date); return
        case "sources": w.OpenWorkSettings(); return
        case "connect": w.OpenWorkSettings(arg); return   // 直接打開那個來源（學校行事曆＝讀書小幫手設定）
        case "pv": Preview = !Preview; if !Spread { Tab = "done" }
        case "kind": PvKind = arg == "simple" ? "simple" : "detail"; Preview = true
        case "links": Links = !Links
        case "copy": Copy(arg)
        case "off": SetOff(arg, true)
        case "on": SetOff(arg, false)
        case "edit": StartEdit(arg, "")
        case "tedit": StartEdit("", arg)
        case "tick": Tick(arg)
        case "untick": Untick(arg)
        case "due": duePick = !duePick
        case "dueday": do { var n = 0; if int.TryParse(arg, &n) { dueDay = w.NbNow().Date.AddDays(n); if dueMin < 0 { dueMin = -1 } } }
        case "duetime": do { var m = 0; if int.TryParse(arg, &m) { if dueDay == DateTime.MinValue { dueDay = w.NbNow().Date }; dueMin = m; duePick = false } }
        case "duenotime": if dueDay == DateTime.MinValue { dueDay = w.NbNow().Date }; dueMin = -1; duePick = false
        case "dueclear": dueDay = DateTime.MinValue; dueMin = -1; duePick = false
        case "move": MoveTodo(lastTodo, arg == "up" ? -1 : 1)
        case "notefocus": ShowNote(true)
        case "focus": FocusFor()
        default: return
        }
        Invalidate()
    }

    func GoDay(_ day: DateTime) {
        EndEdit(true)
        SaveNote()
        let today = w.NbNow().Date
        Day = day > today ? today : day
        justDone.Clear()
        scroll.Clear()
        Reload()
    }

    // 打字的地方：Enter／Esc
    func Key(_ box: String, _ k: String) {
        if box == "todo" {
            if k == "esc" { tbTodo.Text = ""; duePick = false; dueDay = DateTime.MinValue; dueMin = -1; Invalidate(); return }
            let s = tbTodo.Text.Trim()
            if s == "" { return }
            let t = NbTodo()
            t.Id = Nb.NewId("t"); t.Text = s; t.Created = Nb.Ymd(w.NbNow())
            if dueDay != DateTime.MinValue { t.Due = Nb.DueValue(dueDay, dueMin) }
            todos.Add(t)
            scroll["todo"] = 1 << 20
            w.NbSaveTodos(todos)
            lastTodo = t.Id
            tbTodo.Text = ""; dueDay = DateTime.MinValue; dueMin = -1; duePick = false
            logStamp = Stamp()
            Invalidate()
            return
        }
        if box == "done" {
            if k == "esc" { tbDone.Text = ""; return }
            let s = tbDone.Text.Trim()
            if s == "" { return }
            let f = NbFact()
            f.Id = Nb.NewId("manual:"); f.Src = "manual"; f.Title = s
            f.T = IsToday ? w.NbNow() : Day.Date + w.NbNow().TimeOfDay
            Nb.AppendLog(Dir, f)
            tbDone.Text = ""
            scroll["done"] = 1 << 20   // 捲到最下面：看得到剛加的那件
            Reload()
            return
        }
        if box == "edit" { EndEdit(k == "enter"); return }
    }

    func StartEdit(_ thingId: String, _ todoId: String) {
        EndEdit(true)
        if thingId != "" { guard let t = FindThing(thingId) else { return }; editThing = thingId; tbEdit.Text = t.Title }
        else { guard let t = FindTodo(todoId), t.Src != "jira" else { return }; editTodo = todoId; lastTodo = todoId; tbEdit.Text = t.Text }
        tbEdit.Tag = ""
        Invalidate()
        if !App.Offscreen {
            BeginInvoke { [weak self] in
                guard let s = self else { return }
                if !s.tbEdit.Visible { s.Update() }   // mac: 先畫一次（PlaceBoxes 才會把打字框放上去）
                if s.tbEdit.Visible { s.tbEdit.Focus(); s.tbEdit.SelectAll() }
            }
        }
    }

    func EndEdit(_ save: Bool) {
        if editThing == "" && editTodo == "" { return }
        let th = editThing, td = editTodo, s = tbEdit.Text.Trim()
        editThing = ""; editTodo = ""
        tbEdit.Visible = false
        MacDropFocus(tbEdit)   // mac: 藏起來的打字框不能還留著鍵盤焦點
        if !save { Invalidate(); return }
        if th != "" {
            if let t = FindThing(th) {
                let mine = t.F.Src == "manual" || t.F.Src == "todo"
                if s == "" { edits.Titles.Remove(th); if mine { edits.Gone.Add(th) } }
                else if s == t.F.Title { edits.Titles.Remove(th) }
                else { edits.Titles[th] = s }
                Nb.SaveEdits(Dir, Day, edits)
                Reload()
            }
        } else {
            if let t = FindTodo(td) {
                if s == "" { todos.Remove(t) } else { t.Text = s }
                if s == "" && t.Src == "school" { w.NbForgetSchool(t.Ref) }   // 學校的作業刪掉＝不想看到（當成交了，但不記進今天做了）
                w.NbSaveTodos(todos)
                logStamp = Stamp()
            }
        }
        Invalidate()
    }

    func FindThing(_ id: String) -> NbThing? { for t in things { if t.F.Id == id { return t } }; return nil }
    func FindTodo(_ id: String) -> NbTodo? { for t in todos { if t.Id == id { return t } }; return nil }

    func SetOff(_ id: String, _ off: Bool) {
        guard let t = FindThing(id) else { return }
        t.Off = off
        if off { edits.Off.Add(id) } else { edits.Off.Remove(id) }
        Nb.SaveEdits(Dir, Day, edits)
    }

    // 勾掉＝做完：移到今天做了（學校作業＝交了）
    func Tick(_ id: String) {
        guard let t = FindTodo(id) else { return }
        let idx = todos.IndexOf(t)
        let now = w.NbNow()
        let f = NbFact()
        f.T = now
        if t.Src == "school" { f.Id = "school:" + t.Ref + ":done"; f.Src = "school"; f.Project = t.Course; f.Title = "交了 " + t.Text; w.NbSchoolDone(t.Ref, true) }
        else { f.Id = "todo:" + t.Id; f.Src = "todo"; f.Title = t.Text }
        Nb.AppendLog(Dir, f)
        todos.Remove(t)
        w.NbSaveTodos(todos)
        let j = Just(); j.T = t; j.Index = idx; j.LogId = f.Id; j.Until = w.Now + (w.NbReduced() ? 1.2 : 1.6)
        justDone.Add(j)
        lastTodo = ""
        Reload()
    }

    func Untick(_ id: String) {
        var j: Just? = nil
        for x in justDone { if x.T.Id == id { j = x } }
        guard let jj = j else { return }
        justDone.Remove(jj)
        let g = NbFact(); g.Id = jj.LogId; g.T = w.NbNow(); g.Gone = true; g.Src = jj.T.Src == "school" ? "school" : "todo"; g.Title = jj.T.Text
        Nb.AppendLog(Dir, g)
        if jj.T.Src == "school" { w.NbSchoolDone(jj.T.Ref, false) }
        todos.Insert(Math.Min(jj.Index, todos.Count), jj.T)
        w.NbSaveTodos(todos)
        Reload()
    }

    func MoveTodo(_ id: String, _ dir: Int) {
        guard let t = FindTodo(id) else { return }
        let i = todos.IndexOf(t), j = i + dir
        if j < 0 || j >= todos.Count { return }
        todos.RemoveAt(i); todos.Insert(j, t)
        w.NbSaveTodos(todos)
        logStamp = Stamp()
        Invalidate()
    }
    func DragTo(_ id: String, _ index: Int) {
        guard let t = FindTodo(id) else { return }
        todos.Remove(t)
        todos.Insert(Math.Max(0, Math.Min(index, todos.Count)), t)
        lastTodo = id
        w.NbSaveTodos(todos)
        logStamp = Stamp()
        Invalidate()
    }

    func CopyText(_ kind: String) -> String {
        if kind == "simple" { return Nb.Simple(things) }
        if kind == "note" { return note.Text.Replace("\r\n", "\n").TrimEnd() }
        return Nb.Detail(things, Day, kind == "links" || Links)
    }

    func Copy(_ kind: String) {
        let s = CopyText(kind)
        if s.Trim() == "" { return }
        w.NbClipboard(s)
        copied = kind; copiedUntil = w.Now + 3
        w.NbSay("好了，去貼上吧")
    }

    func FocusFor() {
        if App.Offscreen { return }
        BeginInvoke { [weak self] in
            guard let s = self else { return }
            if s.IsDisposed { return }
            if (s.Spread || s.Tab == "todo") && !s.tbTodo.Visible { s.Update() }   // mac: 先畫一次（PlaceBoxes 才會把打字框放上去）
            if (s.Spread || s.Tab == "todo") && s.tbTodo.Visible { s.tbTodo.Focus() }
            else if !s.Spread && s.Tab == "note" { s.ShowNote(true) }
        }
    }

    func ShowNote(_ focus: Bool) {
        if rNote.IsEmpty { return }
        note.Visible = true
        if focus && !App.Offscreen { note.Focus() }
        Invalidate()
    }

    // mac: C# 的 ProcessCmdKey(ref Message, Keys)（表單比打字框先拿到）→ 打字框的 KeyDown、表單的 OnKeyDown 一開始都先問這裡
    func ProcessCmdKey(_ keyData: Keys) -> Bool {
        if keyData == (Keys.Alt | Keys.Up) || keyData == (Keys.Alt | Keys.Down) {
            let id = editTodo != "" ? editTodo : (hoverTodo != "" ? hoverTodo : lastTodo)
            if id != "" { lastTodo = id; MoveTodo(id, keyData == (Keys.Alt | Keys.Up) ? -1 : 1) }
            return true
        }
        if keyData == Keys.Escape {
            if editThing != "" || editTodo != "" { Key("edit", "esc") }
            else if duePick { duePick = false; Invalidate() }
            else if Preview { Preview = false; Invalidate() }
            else { Close() }
            return true
        }
        return false
    }
    // mac: KeyPreview：打字框沒處理的鍵（筆記框、或焦點在表單上）
    override func OnKeyDown(_ e: KeyEventArgs) {
        super.OnKeyDown(e)
        if e.Handled { return }
        if NbEditKeys.Handle() { e.Handled = true; return }   // mac: Cmd+X／C／V／A／Z（沒有「編輯」選單）
        if ProcessCmdKey(e.KeyData) { e.Handled = true }
    }

    // ================= 滑鼠 =================
    func HitAt(_ p: Point) -> Hit? {
        var i = hits.Count - 1
        while i >= 0 { if hits[i].R.Contains(p) { return hits[i] }; i -= 1 }
        return nil
    }
    func SimHover(_ p: Point) {
        if App.Offscreen { Render() }
        let h = HitAt(p)
        var th = "", td = "", act = ""
        if let h = h {
            act = h.Act + ":" + h.Arg
            if let hv = h.Hover, hv.StartsWith("thing:") { th = hv.Substring(6) }
            if let hv = h.Hover, hv.StartsWith("todo:") { td = hv.Substring(5) }
        }
        if th != hoverThing || td != hoverTodo || act != hoverAct { hoverThing = th; hoverTodo = td; hoverAct = act; Invalidate() }
    }
    func SimClick(_ p: Point) {
        if App.Offscreen { Render() }
        guard let h = HitAt(p) else { return }
        DoHit(h)
    }
    // 點整列（不在按鈕上）＝改字
    func DoHit(_ h: Hit) {
        if h.Act == "row" {
            if let hv = h.Hover, hv.StartsWith("thing:") { Do("edit", h.Arg) } else if let hv = h.Hover, hv.StartsWith("todo:") { Do("tedit", h.Arg) }
            return
        }
        Do(h.Act, h.Arg)
    }
    func HoverThing(_ id: String) { hoverThing = id; hoverTodo = ""; Invalidate() }
    func HoverTodo(_ id: String) { hoverTodo = id; hoverThing = ""; if id != "" { lastTodo = id }; Invalidate() }

    override func OnMouseMove(_ e: MouseEventArgs) {
        super.OnMouseMove(e)
        if dragTodo != "" && (e.Button & MouseButtonsT.Left).raw != 0 {
            if !dragging && Math.Abs(e.Y - dragStartY) > Sc(4) { dragging = true }
            if dragging { dragY = e.Y; Invalidate() }
            return
        }
        SimHover(e.Location)
        let h = HitAt(e.Location)
        Cursor = h != nil && h!.Act != "row" ? Cursors.Hand : Cursors.Default
    }
    override func OnMouseLeave(_ e: EventArgs) {
        super.OnMouseLeave(e)
        if !dragging && (hoverThing != "" || hoverTodo != "" || hoverAct != "") { hoverThing = ""; hoverTodo = ""; hoverAct = ""; Invalidate() }
    }
    var downAt = PointT(0, 0)
    override func OnMouseDown(_ e: MouseEventArgs) {
        super.OnMouseDown(e)
        downAt = e.Location
        let h = HitAt(e.Location)
        if e.Button == MouseButtonsT.Left, let hh = h, hh.Act == "grip" || hh.Act == "tedit" { dragTodo = hh.Arg; dragStartY = e.Y; dragY = e.Y; dragging = false; lastTodo = hh.Arg }
        if e.Button == MouseButtonsT.Left && h == nil && e.Y < Sc(46) { DragWindow() }
    }
    override func OnMouseUp(_ e: MouseEventArgs) {
        super.OnMouseUp(e)
        if dragTodo != "" {
            let id = dragTodo, was = dragging
            dragTodo = ""; dragging = false
            if was { DragTo(id, DropIndex(id)); return }
        }
        if e.Button != MouseButtonsT.Left { return }
        guard let h = HitAt(e.Location) else { return }
        if h.Act == "grip" { return }
        DoHit(h)
        FocusAfterClick(h.Act)
    }
    func FocusAfterClick(_ act: String) {
        if App.Offscreen { return }
        if act == "addtodo" && tbTodo.Visible { tbTodo.Focus() }
        if act == "adddone" && tbDone.Visible { tbDone.Focus() }
    }
    override func OnMouseWheel(_ e: MouseEventArgs) {
        super.OnMouseWheel(e)
        for kv in clipR {
            // mac: 觸控板的 delta 很小，C# 的整數 -Delta / 120 會變 0 → 用 Double 算
            if kv.Value.Contains(e.Location) { ScrollBy(kv.Key, -CInt(Double(e.Delta) / 120.0 * Double(Sc(28)) * 2)); return }
        }
    }
    func ScrollBy(_ key: String, _ dy: Int) {
        var s = 0, h = 0
        var c = RectangleT.Empty
        scroll.TryGetValue(key, &s)
        contentH.TryGetValue(key, &h)
        clipR.TryGetValue(key, &c)
        s = Math.Max(0, Math.Min(Math.Max(0, h - c.Height), s + dy))
        scroll[key] = s
        Invalidate()
    }
    func DropIndex(_ id: String) -> Int {
        var idx = 0
        for t in todos {
            if t.Id == id { continue }
            var r = RectangleT.Empty
            if todoRows.TryGetValue(t.Id, &r) && dragY > r.Y + r.Height / 2 { idx += 1 }
        }
        return idx
    }

    // 拖上面的木框搬家
    // mac: ReleaseCapture＋SendMessage(WM_NCLBUTTONDOWN, HTCAPTION) → NSWindow.performDrag（放開滑鼠才回來，跟 Windows 一樣吃掉 mouse up）
    func DragWindow() { if App.Offscreen { return }; if let p = panel, let ev = NSApp.currentEvent { p.performDrag(with: ev) } }
    // mac: 藏起來的打字框如果還拿著鍵盤焦點（NSTextField 的 field editor），還給視窗（C#：藏起來的控制項自己會交出焦點）
    func MacDropFocus(_ c: Control) {
        BeginInvoke { [weak self] in
            guard let s = self else { return }
            if !c.Visible && c.Focused { _ = s.panel?.makeFirstResponder(nil) }
        }
    }

    // ================= 畫 =================
    func AddHit(_ act: String, _ arg: String, _ r: Rectangle) { AddHit(act, arg, r, nil) }
    var hitClip = RectangleT.Empty   // 捲動的紙：紙外面（看不到的）不能點
    var again = false, inAgain = false
    // 捲到哪：不超過內容（內容變短時往回拉，下一輪重畫一次）
    func ScrollOf(_ key: String, _ clip: Rectangle) -> Int {
        var s = 0
        scroll.TryGetValue(key, &s)
        s = Math.Max(0, s)   // 太大的（剛加一件、要捲到底）由 ScrollDone 拉回來再畫一次
        scroll[key] = s
        return s
    }
    func ScrollDone(_ key: String, _ h: Int, _ clip: Rectangle) {
        var s = 0; scroll.TryGetValue(key, &s)
        contentH[key] = h
        let max = Math.Max(0, h - clip.Height)
        if s > max { scroll[key] = max; again = true }
    }
    func AddHit(_ act: String, _ arg: String, _ r: Rectangle, _ hover: String?) { AddHit(act, arg, r, hover, false) }
    func AddHit(_ act: String, _ arg: String, _ r0: Rectangle, _ hover: String?, _ low: Bool) {
        var r = r0
        if !hitClip.IsEmpty { r = RectangleT.Intersect(r, hitClip); if r.Width <= 0 || r.Height <= 0 { return } }
        let h = Hit(); h.Act = act; h.Arg = arg; h.R = r; h.Hover = hover
        if low { hits.Insert(0, h) } else { hits.Add(h) }
    }
    func Hot(_ act: String, _ arg: String) -> Bool { return hoverAct == act + ":" + arg }

    override func OnPaint(_ e: PaintEventArgs) {
        let g = e.Graphics
        g.SmoothingMode = SmoothingMode.None
        g.Clear(NotebookForm.KEY)
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit   // 字見 DT()
        hits.Clear(); todoRows.Clear(); clipR.Clear(); Drawn.Clear()
        again = false; hitClip = RectangleT.Empty
        rTodo = RectangleT.Empty; rDone = RectangleT.Empty; rEdit = RectangleT.Empty; rNote = RectangleT.Empty
        let night = w.Night
        let X = OV, W0 = FrameW, H0 = FrameH
        Pix.Wood(g, X, 0, W0, H0, U, night, 31)
        Pix.Panel(g, X + Sc(8), Sc(46), W0 - Sc(16), H0 - Sc(46) - Sc(8), U, night)
        Crown(g, X, W0)
        DayBar(g, X + Sc(18), Sc(54), W0 - Sc(36))
        if Spread {
            let top = Sc(92), colW = (W0 - Sc(36) - Sc(22)) / 2, areaH = Sc(526)
            let left = RectangleT(X + Sc(18), top, colW, areaH), right = RectangleT(X + Sc(18) + colW + Sc(22), top, colW, areaH)
            LeftSpread(g, left)
            DoneArea(g, right, Sc(22), false)
        } else {
            let top = Sc(126), areaH = Sc(526)
            Tabs(g, X, Sc(92))
            let area = RectangleT(X + Sc(18), top, W0 - Sc(36), areaH)
            let ti = NotebookForm.TabKey.IndexOf(Tab)
            if Tab == "todo" { TodoArea(g, area) }
            else if Tab == "note" { NoteArea(g, area) }
            else { DoneArea(g, area, Sc(44), true) }
            Drawn.Add("tab " + Tab + " " + String(ti))
        }
        PlaceBoxes()
        if again && !inAgain { inAgain = true; OnPaint(e); inAgain = false }   // 捲動往回拉了：照新的位置再畫一次
    }

    // 頂上：銅牌＋兩邊小愛心＋右上角的叉叉
    func Crown(_ g: Graphics, _ X: Int, _ W0: Int) {
        let t = "小本子"
        let tw = TW(t, fPlate), plw = tw + Sc(44), plh = Sc(25)
        let pr = RectangleT(X + (W0 - plw) / 2, Sc(10), plw, plh)
        Pix.Plate(g, "", fPlate, pr, U)
        NotebookForm.DT(g, t, fPlate, RectangleT(pr.X, pr.Y, pr.Width, pr.Height - U / 2), NotebookForm.CText, Pix.Mid)
        Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.X - Sc(8) - 5 * U, pr.Y + plh / 2 - 2 * U, U)
        Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.Right + Sc(8), pr.Y + plh / 2 - 2 * U, U)
        let xr = RectangleT(X + W0 - Sc(10) - Sc(20), Sc(12), Sc(20), Sc(20))
        let hot = Hot("close", "")
        Pix.Round(g, Pix.Ink, xr.X, xr.Y, xr.Width, xr.Height, U)
        Pix.Box(g, hot ? Pix.C(0xFFF3D6) : NotebookForm.CBtn, xr.X + U, xr.Y + U, xr.Width - 2 * U, xr.Height - 2 * U)
        Pix.Box(g, Pix.C(0xDCC6A2), xr.X + U, xr.Bottom - U - Sc(3) + 1, xr.Width - 2 * U, Sc(3) - 1)
        Pix.Mono(g, NotebookForm.Mono(NotebookForm.IX), Pix.Ink, xr.X + (xr.Width - 5 * U) / 2, xr.Y + (xr.Height - 5 * U) / 2 - 1, U)
        AddHit("close", "", xr)
    }
    static func Mono(_ a: [String]) -> [String] { var r: [String] = []; for s in a { r.append(s.Replace("k", "#")) }; return r }

    // ◀ 11/19（四）［今天］ ▶ ……［攤開］［⚙ 來源］
    func DayBar(_ g: Graphics, _ x: Int, _ y: Int, _ w0: Int) {
        let bh = Sc(24), by = y + (Sc(30) - bh) / 2
        let l = RectangleT(x, by, bh, bh)
        SmallBtn(g, l, "", false, Hot("prev", ""))
        Pix.Mono(g, NotebookForm.Mono(NotebookForm.ILEFT), Pix.Ink, l.X + (bh - 3 * U) / 2, l.Y + (bh - Sc(3) - 5 * U) / 2 + 1, U)
        AddHit("prev", "", l)
        let ds = Nb.DayLabel(Day)
        let dx = l.Right + Sc(8) + Sc(4), dw = TW(ds, fBody)
        NotebookForm.DT(g, ds, fBody, RectangleT(dx, y, dw + 4, Sc(30)), NotebookForm.CText, Pix.LeftMid)
        let px = dx + dw + Sc(2) + Sc(8)
        var pr: Rectangle
        if IsToday {
            let pw = TW("今天", fSmall) + Sc(12), ph = Sc(18)
            pr = RectangleT(px, y + (Sc(30) - ph) / 2, pw, ph)
            Pix.Round(g, Pix.C(0x8A5A2A), pr.X, pr.Y, pr.Width, pr.Height, U)
            Pix.Box(g, Pix.C(0xF6C453), pr.X + U, pr.Y + U, pr.Width - 2 * U, pr.Height - 2 * U)
            NotebookForm.DT(g, "今天", fSmall, RectangleT(pr.X, pr.Y, pr.Width, pr.Height - 1), NotebookForm.CText, Pix.Mid)
        } else {
            pr = RectangleT(px, by, TW("回今天", fBtnS) + Sc(18), bh)
            SmallBtn(g, pr, "回今天", false, Hot("today", ""))
            AddHit("today", "", pr)
        }
        let r = RectangleT(pr.Right + Sc(8), by, bh, bh)
        SmallBtn(g, r, "", IsToday, Hot("next", ""))
        Pix.Mono(g, NotebookForm.Mono(NotebookForm.IRIGHT), IsToday ? Pix.C(0xBBA98C) : Pix.Ink, r.X + (bh - 3 * U) / 2 + 1, r.Y + (bh - Sc(3) - 5 * U) / 2 + 1, U)
        if !IsToday { AddHit("next", "", r) }
        // 右邊：來源、攤開／收起
        let src = "來源"
        let sw = TW(src, fBtnS) + Sc(18) + 5 * U + Sc(5)
        let sr = RectangleT(x + w0 - sw, by, sw, bh)
        SmallBtn(g, sr, "", false, Hot("sources", ""))
        Pix.Mono(g, NotebookForm.Mono(NotebookForm.IGEAR), Pix.Ink, sr.X + Sc(9), sr.Y + (bh - Sc(3) - 5 * U) / 2 + 1, U)
        NotebookForm.DT(g, src, fBtnS, RectangleT(sr.X + Sc(9) + 5 * U + Sc(5), sr.Y, sw, bh - Sc(3)), NotebookForm.CText, Pix.LeftMid)
        AddHit("sources", "", sr)
        let sp = Spread ? "收起" : "攤開"
        let spw = TW(sp, fBtnS) + Sc(18)
        let spr = RectangleT(sr.X - Sc(8) - spw, by, spw, bh)
        SmallBtn(g, spr, sp, false, Hot("spread", ""))
        AddHit("spread", "", spr)
        Drawn.Add("day " + Nb.Ymd(Day) + " " + (IsToday ? "today" : "past"))
    }

    // 上緣的三個索引頁籤：選中的比較高、接進紙張、紙色底、上緣一條頁籤色
    func Tabs(_ g: Graphics, _ X: Int, _ y: Int) {
        var x = X + Sc(48)
        let n0 = todos.Count + jira.Count, n1 = things.Count
        for i in 0..<3 {
            let on = Tab == NotebookForm.TabKey[i]
            let cnt: String = i == 0 ? n0.ToString() : (i == 1 ? n1.ToString() : "")
            let nameW = TW(NotebookForm.TabName[i], fBody)
            let tw: Int = nameW + (cnt != "" ? Sc(8) + TW(cnt, fWord) : 0)
            let wd = Math.Max(Sc(on ? 104 : 96), tw + Sc(28))
            var ht = on ? Sc(36) : Sc(32)
            let ty: Int = y + Sc(34) - Sc(32) - (on ? Sc(2) : 0)
            if on { ht = Sc(36) }
            _ = ht
            let rh: Int = on ? Sc(34) + Sc(2) - (ty - y) + Sc(0) : Sc(32)
            var r = RectangleT(x, ty, wd, rh)
            if on { r.Height = y + Sc(34) + Sc(2) - ty }
            Pix.Box(g, Pix.Ink, r.X + U, r.Y, r.Width - 2 * U, U)
            Pix.Box(g, Pix.Ink, r.X, r.Y + U, U, r.Height - U)
            Pix.Box(g, Pix.Ink, r.Right - U, r.Y + U, U, r.Height - U)
            Pix.Box(g, on ? NotebookForm.CPaper : NotebookForm.TabBg[i], r.X + U, r.Y + U, r.Width - 2 * U, r.Height - U)
            if on { Pix.Box(g, NotebookForm.TabC[i], r.X + U, r.Y + U, r.Width - 2 * U, Sc(6)) }
            else { Pix.Box(g, Pix.C(0xC9A777), r.X + U, r.Bottom - U, r.Width - 2 * U, U) }
            let hot = Hot("tab", NotebookForm.TabKey[i]) && !on
            if hot { Pix.Box(g, Pix.Mix(NotebookForm.TabBg[i], Color.White, 0.5), r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U) }
            let cy = on ? r.Y + Sc(6) : r.Y, ch = on ? r.Height - Sc(6) - Sc(2) : r.Height
            let tx = r.X + (r.Width - tw) / 2
            NotebookForm.DT(g, NotebookForm.TabName[i], fBody, RectangleT(tx, cy, tw + 4, ch), on ? NotebookForm.CText : NotebookForm.CTabText, Pix.LeftMid)
            if cnt != "" { NotebookForm.DT(g, cnt, fWord, RectangleT(tx + nameW + Sc(8), cy, TW(cnt, fWord) + 4, ch), on ? NotebookForm.CText : NotebookForm.CSub, Pix.LeftMid) }
            AddHit("tab", NotebookForm.TabKey[i], r)
            let geo = String(r.X) + " " + String(r.Y) + " " + String(r.Width) + " " + String(r.Height)
            Drawn.Add("tabbtn " + NotebookForm.TabKey[i] + " " + (on ? "1" : "0") + " " + cnt + " " + geo)
            x += wd + Sc(4)
        }
    }

    // 紙：深色外框（2px，畫在外面）、紙色、右緣頁籤色、左邊線圈
    @discardableResult func Paper(_ g: Graphics, _ r: Rectangle, _ bg: Color, _ stripe: Int, _ rings: Bool) -> Rectangle {
        Pix.Box(g, Pix.Ink, r.X - U, r.Y - U, r.Width + 2 * U, r.Height + 2 * U)
        Pix.Box(g, bg, r.X, r.Y, r.Width, r.Height)
        if stripe >= 0 { Pix.Box(g, NotebookForm.TabC[stripe], r.Right - Sc(6), r.Y, Sc(6), r.Height) }
        return r
    }
    func Rings(_ g: Graphics, _ paper: Rectangle) {
        for i in 0..<6 {
            let y = paper.Y + Sc(30) + i * Sc(80)
            if y > paper.Bottom - Sc(16) { break }
            let x = paper.X - Sc(28)
            Pix.Round(g, Pix.Ink, x, y, Sc(34), Sc(8), U)
            Pix.Box(g, Pix.C(0xCFC8BC), x + U, y + U, Sc(34) - 2 * U, Sc(8) - 2 * U)
            Pix.Box(g, Pix.C(0xF1EDE6), x + U, y + U, Sc(34) - 2 * U, U)
            let hx = paper.X + Sc(2), hy = y + Sc(1)
            Pix.Box(g, Pix.C(0xA88A64), hx, hy, Sc(6), Sc(6))
            Pix.Box(g, Pix.C(0xD9C6A4), hx + U, hy + U, Sc(6) - U, Sc(6) - U)
        }
    }
    func Scrollbar(_ g: Graphics, _ key: String, _ paper: Rectangle, _ clip: Rectangle) {
        var h = 0, s = 0
        contentH.TryGetValue(key, &h)
        scroll.TryGetValue(key, &s)
        if h <= clip.Height + Sc(4) { return }
        let tr = RectangleT(paper.Right - Sc(8), paper.Y + Sc(6), Sc(6), paper.Height - Sc(12))
        Pix.Box(g, Pix.C(0xEFE3CB), tr.X, tr.Y, tr.Width, tr.Height)
        let th = Math.Max(Sc(20), tr.Height * clip.Height / h)
        let ty = tr.Y + (tr.Height - th) * s / Math.Max(1, h - clip.Height)
        Pix.Box(g, Pix.C(0xC9A777), tr.X, ty, tr.Width, th)
    }

    // ---- 今天做了（一頁，或攤開的右頁）----
    func DoneArea(_ g: Graphics, _ area: Rectangle, _ padL: Int, _ single: Bool) {
        let foot = Sc(32), bar = Sc(28)
        let paper = RectangleT(area.X, area.Y, area.Width, area.Height - bar - Sc(8) - foot - Sc(10))
        Paper(g, paper, Preview ? Color.White : NotebookForm.CPaper, single ? 1 : -1, true)
        let clip = RectangleT(paper.X + padL - Sc(8), paper.Y + Sc(6), paper.Width - padL + Sc(8) - Sc(14) + Sc(12), paper.Height - Sc(12))
        clipR[Preview ? "preview" : "done"] = clip
        let tx = paper.X + padL, right = paper.Right - Sc(14)
        // 「補一件做過的事」：清單放得下就接在後面；放不下就釘在紙的最下面（捲動時不會被切一半）
        let fieldH = Sc(28) + Sc(4)
        var prev = 0
        contentH.TryGetValue("donelist", &prev)
        let pin = !Preview && prev + fieldH > clip.Height
        let lclip = pin ? RectangleT(clip.X, clip.Y, clip.Width, clip.Height - fieldH - Sc(4)) : clip
        clipR[Preview ? "preview" : "done"] = lclip
        let st = g.Save()
        g.SetClip(RectangleT(paper.X, paper.Y, paper.Width - (single ? Sc(6) : 0), pin ? lclip.Bottom - paper.Y : paper.Height))
        let s = ScrollOf(Preview ? "preview" : "done", lclip)
        hitClip = RectangleT(paper.X - Sc(12), paper.Y, paper.Width + Sc(12), pin ? lclip.Bottom - paper.Y : paper.Height)
        let y0 = paper.Y + Sc(6) - s
        var h = Preview ? PreviewPage(g, tx, y0, right) : DonePage(g, tx, y0, right, lclip)
        if !Preview {
            contentH["donelist"] = h
            if (h + fieldH > clip.Height) != pin { again = true }
            let fr = pin ? RectangleT(tx - Sc(8), lclip.Bottom + Sc(4), right - tx + Sc(8), Sc(28)) : RectangleT(tx - Sc(8), y0 + h, right - tx + Sc(8), Sc(28))
            if pin { g.ResetClip(); hitClip = RectangleT.Empty }
            Field(g, fr, tbDone, "補一件做過的事，按 Enter", false, clip)
            rDone = NotebookForm.Inside(fr, clip) ? fr : RectangleT.Empty
            AddHit("adddone", "", fr)
            if !pin { h += fieldH }
        }
        hitClip = RectangleT.Empty
        ScrollDone(Preview ? "preview" : "done", h, lclip)
        g.Restore(st)
        Rings(g, paper)
        Scrollbar(g, Preview ? "preview" : "done", paper, lclip)
        // 貼出去會長這樣
        var br = RectangleT(area.X, paper.Bottom + U + Sc(8) - U, area.Width, bar)
        br.Y = paper.Bottom + Sc(8)
        PvBar(g, br)
        // 會複製 N 件、複製簡單、複製詳細
        let fy = br.Bottom + Sc(10)
        let empty = things.Count == 0 || Nb.OnCount(things) == 0
        if things.Count > 0 { NotebookForm.DT(g, "會複製 " + String(Nb.OnCount(things)) + " 件", fSmall, RectangleT(area.X, fy, Sc(160), foot), NotebookForm.CSub, Pix.LeftMid) }
        let cD = copied == "detail" || copied == "links", cS = copied == "simple"
        let dt = cD ? "已複製詳細" : "複製詳細", stx = cS ? "已複製簡單" : "複製簡單"
        let dw: Int = TW(dt, fBtn) + Sc(28) + (cD ? 5 * U + Sc(6) : 0)
        let sw: Int = TW(stx, fBtn) + Sc(28) + (cS ? 5 * U + Sc(6) : 0)
        let dr = RectangleT(area.Right - dw, fy, dw, foot)
        let sr = RectangleT(dr.X - Sc(8) - sw, fy, sw, foot)
        BigBtn(g, sr, stx, empty ? 3 : (cS ? 2 : 0), Hot("copy", "simple"))
        BigBtn(g, dr, dt, empty ? 3 : (cD ? 2 : 1), Hot("copy", "detail"))
        if !empty { AddHit("copy", "simple", sr); AddHit("copy", "detail", dr) }
        let fn = things.Count > 0 ? Nb.OnCount(things) : -1
        let cpS: String = copied == "" ? "-" : copied, onS: String = empty ? "off" : "on"
        Drawn.Add("foot " + String(fn) + " copied=" + cpS + " " + onS)
    }

    // 貼出去會長這樣：▶／▼、附上連結、簡單｜詳細
    func PvBar(_ g: Graphics, _ r: Rectangle) {
        Pix.Round(g, NotebookForm.CBarEdge, r.X, r.Y, r.Width, r.Height, U)
        Pix.Box(g, NotebookForm.CBar, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U)
        let x = r.X + Sc(8), cy = r.Y + r.Height / 2
        let ac = Pix.C(0x8A5A2A)
        if Preview { Pix.Mono(g, NotebookForm.Mono(NotebookForm.IDOWN), ac, x, cy - U - U / 2, U) }
        else { Pix.Mono(g, NotebookForm.Mono(NotebookForm.IRIGHT), ac, x + U, cy - 5 * U / 2, U) }
        let t = "貼出去會長這樣"
        NotebookForm.DT(g, t, fBar, RectangleT(x + 5 * U + Sc(8), r.Y, TW(t, fBar) + 4, r.Height), NotebookForm.CGh, Pix.LeftMid)
        AddHit("pv", "", RectangleT(r.X, r.Y, x + 5 * U + Sc(8) + TW(t, fBar) + Sc(8) - r.X, r.Height))
        if !Preview { Drawn.Add("pvbar closed"); return }
        // 簡單｜詳細
        let sw = Sc(40), sh = Sc(20), segW = 2 * sw + 3 * U
        let seg = RectangleT(r.Right - Sc(6) - segW, cy - sh / 2, segW, sh)
        Pix.Round(g, Pix.Ink, seg.X, seg.Y, seg.Width, seg.Height, U)
        for i in 0..<2 {
            let on = (i == 0) == (PvKind == "simple")
            let c = RectangleT(seg.X + U + i * (sw + U), seg.Y + U, sw, sh - 2 * U)
            Pix.Box(g, on ? Pix.C(0xF6C453) : NotebookForm.CBtn, c.X, c.Y, c.Width, c.Height)
            if on { Pix.Box(g, Pix.C(0xFBE7BA), c.X, c.Y, c.Width, U); Pix.Box(g, Pix.C(0xC8902C), c.X, c.Bottom - U, c.Width, U) }
            NotebookForm.DT(g, i == 0 ? "簡單" : "詳細", fSmall, c, on ? NotebookForm.CText : NotebookForm.CPh, Pix.Mid)
            AddHit("kind", i == 0 ? "simple" : "detail", c)
        }
        // 附上連結（只有詳細用得到）
        let lk = "附上連結"
        let lw = TW(lk, fSmall), cs = Sc(14)
        let lx = seg.X - Sc(8) - lw - Sc(5) - cs
        Chk(g, lx, cy - cs / 2, Links, Hot("links", ""))
        NotebookForm.DT(g, lk, fSmall, RectangleT(lx + cs + Sc(5), r.Y, lw + 4, r.Height), NotebookForm.CSub, Pix.LeftMid)
        AddHit("links", "", RectangleT(lx - Sc(2), r.Y, cs + Sc(5) + lw + Sc(4), r.Height))
        Drawn.Add("pvbar open " + PvKind + " links=" + (Links ? "1" : "0"))
    }

    func DonePage(_ g: Graphics, _ tx: Int, _ y0: Int, _ right: Int, _ clip: Rectangle) -> Int {
        var y = y0
        let bx = tx - Sc(8), bw = right - bx
        if things.Count == 0 { return EmptyDone(g, tx, y, right, clip) - y0 }
        // 今天 N 件　CI 都過了
        let sr = RectangleT(bx, y, bw, Sc(32))
        Pix.Round(g, NotebookForm.CBarEdge, sr.X, sr.Y, sr.Width, sr.Height, U)
        Pix.Box(g, NotebookForm.CBar, sr.X + U, sr.Y + U, sr.Width - 2 * U, sr.Height - 2 * U)
        let today = w.NbNow().Date
        let which = Day == today ? "今天 " : (Day == today.AddDays(-1) ? "昨天 " : "這天 ")
        let head = which + String(things.Count) + " 件"
        NotebookForm.DT(g, head, fBody, RectangleT(sr.X + Sc(10), sr.Y, sr.Width, sr.Height), NotebookForm.CText, Pix.LeftMid)
        let sum: NbWord? = Nb.SumWord(things)
        if let sm = sum { let ww = TW(sm.Text, fWord); NotebookForm.DT(g, sm.Text, fWord, RectangleT(sr.Right - Sc(10) - ww - 2, sr.Y, ww + 4, sr.Height), WordC(sm.Kind, false), Pix.LeftMid) }
        let sumS: String = sum != nil ? " | " + sum!.Text : ""
        Drawn.Add("sum " + head + sumS)
        y += Sc(32) + Sc(4)
        var group: String? = nil
        for t in things {
            if group == nil || t.Group != group! {
                group = t.Group
                let gr = RectangleT(tx, y, right - tx, Sc(28))
                NotebookForm.DT(g, t.Group, fBody, RectangleT(gr.X, gr.Y, gr.Width, gr.Height - Sc(4)), NotebookForm.CGh, [TextFormatFlags.Left, TextFormatFlags.Bottom, TextFormatFlags.SingleLine, TextFormatFlags.NoPadding, TextFormatFlags.NoPrefix])
                Pix.Box(g, NotebookForm.CGhLine, gr.X, gr.Bottom - Sc(2), gr.Width, Sc(2))
                Drawn.Add("group " + t.Group)
                y += Sc(28) + Sc(4)
            }
            y += ThingRow(g, t, bx, y, right, clip)
        }
        y += Sc(4)   // 「補一件做過的事」由 DoneArea 畫
        return y - y0
    }

    func WordC(_ kind: Int, _ hot: Bool) -> Color { return kind == 2 ? NotebookForm.CBad : (kind == 1 ? (hot ? NotebookForm.COkHot : NotebookForm.COk) : NotebookForm.CSub) }

    func ThingRow(_ g: Graphics, _ t: NbThing, _ bx: Int, _ y: Int, _ right: Int, _ clip: Rectangle) -> Int {
        let hot = t.F.Id == hoverThing && !t.Off && editThing != t.F.Id, editing = editThing == t.F.Id
        let tx = bx + Sc(8)
        let words = Nb.Words(t)
        let runs = List<Run>()
        let main = t.Off ? NotebookForm.COff : NotebookForm.CText
        runs.Add(Run(Nb.PageText(t), fBody, main))
        for wd in words {
            let cm = Run("，", fWord, t.Off ? NotebookForm.COff : NotebookForm.CSub); cm.KeepNext = true; runs.Add(cm)
            let wr = Run(wd.Text, fWord, t.Off ? NotebookForm.COff : WordC(wd.Kind, hot)); wr.Keep = true; runs.Add(wr)
        }
        let back = "要複製"
        let avail: Int = right - Sc(6) - tx - (t.Off ? TW(back, fSmall) + Sc(10) : 0)
        let lines = Flow(g, runs, tx, y + Sc(3), avail, Sc(22), false, false)   // 先量（跟畫用同一個 Graphics，換行才一樣）
        let h: Int = Sc(6) + lines * Sc(22) + (hot ? Sc(16) : 0)
        let row = RectangleT(bx, y, right - bx, h)
        if hot {
            Pix.Round(g, Pix.C(0xD9A944), row.X, row.Y, row.Width, row.Height, U)
            Pix.Box(g, Pix.C(0xFFE29A), row.X + U, row.Y + U, row.Width - 2 * U, row.Height - 2 * U)
            Pix.Box(g, Pix.C(0xFFF1C9), row.X + U, row.Y + U, row.Width - 2 * U, Sc(3) - U)
        }
        if editing {
            rEdit = RectangleT(tx, y + Sc(3), avail, Sc(22))
            Pix.Round(g, Pix.Ink, rEdit.X - Sc(4), rEdit.Y - Sc(2), rEdit.Width + Sc(8), rEdit.Height + Sc(4), U)
            Pix.Box(g, NotebookForm.CPaper, rEdit.X - Sc(4) + U, rEdit.Y - Sc(2) + U, rEdit.Width + Sc(8) - 2 * U, rEdit.Height + Sc(4) - 2 * U)
            if App.Offscreen { NotebookForm.DT(g, tbEdit.Text, fBody, rEdit, NotebookForm.CText, Pix.LeftMid) }
            if !NotebookForm.Inside(rEdit, clip) { rEdit = RectangleT.Empty }
        } else { Flow(g, runs, tx, y + Sc(3), avail, Sc(22), t.Off) }
        AddHit("edit", t.F.Id, RectangleT(tx, y, Math.Max(Sc(20), Math.Min(avail, FlowW(runs))), Sc(6) + lines * Sc(22)), "thing:" + t.F.Id)
        if hot {
            NotebookForm.DT(g, Nb.Ids(t), fSmall, RectangleT(tx, y + Sc(3) + lines * Sc(22), right - tx, Sc(16)), NotebookForm.CSub, [TextFormatFlags.Left, TextFormatFlags.Top, TextFormatFlags.SingleLine, TextFormatFlags.NoPadding, TextFormatFlags.NoPrefix])
            let nc = "不複製"
            let bw = TW(nc, fBtnS) + Sc(18)
            let br = RectangleT(row.Right - Sc(6) - bw, row.Bottom - Sc(3) - Sc(20), bw, Sc(20))
            SmallBtn(g, br, nc, false, Hot("off", t.F.Id))
            AddHit("off", t.F.Id, br, "thing:" + t.F.Id)
        }
        if t.Off {
            let bw = TW(back, fSmall)
            let br = RectangleT(row.Right - Sc(6) - bw, y + Sc(6), bw, Sc(16))
            NotebookForm.DT(g, back, fSmall, RectangleT(br.X, br.Y, br.Width + 4, br.Height), Hot("on", t.F.Id) ? NotebookForm.CText : NotebookForm.CSub, [TextFormatFlags.Left, TextFormatFlags.Top, TextFormatFlags.SingleLine, TextFormatFlags.NoPadding, TextFormatFlags.NoPrefix])
            AddHit("on", t.F.Id, RectangleT(br.X - Sc(4), y, br.Width + Sc(8), h), "thing:" + t.F.Id)
        }
        AddHit("row", t.F.Id, row, "thing:" + t.F.Id, true)   // 整列只管 hover，放最下面
        let onS: String = t.Off ? "off" : "on", hotS: String = hot ? " hot" : ""
        let idsS: String = hot ? " | " + Nb.Ids(t) : ""
        Drawn.Add("thing " + t.F.Id + " " + onS + hotS + " | " + NotebookForm.RunsText(runs) + idsS)
        return h
    }

    // 空白：接上之後，做過的事會自己記下來
    func EmptyDone(_ g: Graphics, _ tx: Int, _ y0: Int, _ right: Int, _ clip: Rectangle) -> Int {
        var y = y0
        NotebookForm.DT(g, "接上之後，做過的事會自己記下來", fWord, RectangleT(tx, y, right - tx, Sc(32)), NotebookForm.CSub, Pix.LeftMid)
        Drawn.Add("empty done")
        y += Sc(32)
        let rows: [[String]] = [
            ["claude", "Claude Code／Codex", "本機紀錄"], ["school", "學校行事曆", "上課、作業"], ["calendar", "行事曆", "會議"],
            ["github", "GitHub", "PR、CI"], ["gitlab", "GitLab", "MR、CI"], ["jira", "Jira", "工單"] ]
        let bx = tx - Sc(8)
        _ = bx
        for r in rows {
            DrawIcon(g, r[0], tx, y + Sc(16) - 4 * U)
            NotebookForm.DT(g, r[1], fWord, RectangleT(tx + 8 * U + Sc(8), y, Sc(150), Sc(32)), NotebookForm.CText, Pix.LeftMid)
            NotebookForm.DT(g, r[2], fSmall, RectangleT(tx + 8 * U + Sc(8) + Sc(150) + Sc(8), y, Sc(120), Sc(32)), NotebookForm.CSub, Pix.LeftMid)
            if w.WorkSourceOn(r[0]) {
                let ok = "已接上"
                let ow = TW(ok, fSmall)
                NotebookForm.DT(g, ok, fSmall, RectangleT(right - ow - 2, y, ow + 4, Sc(32)), NotebookForm.COk, Pix.LeftMid)
                Pix.Mono(g, Pix.CHECK, NotebookForm.COk, right - ow - Sc(4) - 5 * U, y + Sc(16) - 5 * U / 2, U)
            } else {
                let c = "接上"
                let cw = TW(c, fBtnS) + Sc(18)
                let br = RectangleT(right - cw, y + Sc(4), cw, Sc(24))
                SmallBtn(g, br, c, false, Hot("connect", r[0]))
                AddHit("connect", r[0], br)
            }
            y += Sc(32)
        }
        return y + Sc(14)   // 「補一件做過的事」由 DoneArea 畫
    }

    // 預覽：白紙上就是要貼出去的字（簡單／詳細、附不附連結）
    func PreviewPage(_ g: Graphics, _ tx: Int, _ y0: Int, _ right: Int) -> Int {
        let text = PvKind == "simple" ? Nb.Simple(things) : Nb.Detail(things, Day, Links)
        var y = y0
        let lh = Sc(19), ind = Sc(14)
        for raw in text.Split("\n") {
            let head = raw.StartsWith("【") || raw.EndsWith("進度")
            let kid = raw.StartsWith("　")
            let s = kid ? raw.Substring(1) : raw
            let x = tx + (kid ? ind : 0), hang = s.StartsWith("・") || s.StartsWith("- ") ? ind : 0
            if s == "" { y += lh; continue }
            let runs = List<Run>()
            runs.Add(Run(s, head ? fPvB : fPv, NotebookForm.CNote))
            let n = FlowHang(g, runs, x, y, right - x, lh, hang)
            y += n * lh
        }
        Drawn.Add("preview " + PvKind + " links=" + (Links ? "1" : "0"))
        return y - y0 + Sc(8)
    }

    // ---- 待辦（一頁）----
    func TodoArea(_ g: Graphics, _ area: Rectangle) {
        let paper = Paper(g, area, NotebookForm.CPaper, 0, true)
        let clip = RectangleT(paper.X + Sc(36), paper.Y + Sc(6), paper.Width - Sc(36) - Sc(2), paper.Height - Sc(12))
        clipR["todo"] = clip
        var pin = false
        let lclip = TodoClip(clip, &pin)
        clipR["todo"] = lclip
        let st = g.Save()
        g.SetClip(RectangleT(paper.X, paper.Y, paper.Width - Sc(6), lclip.Bottom - paper.Y + (pin ? 0 : Sc(6))))
        let s = ScrollOf("todo", lclip)
        hitClip = RectangleT(paper.X - Sc(12), paper.Y, paper.Width + Sc(12), lclip.Bottom - paper.Y + (pin ? 0 : Sc(6)))
        todoPin = pin
        let h = TodoPage(g, paper.X + Sc(44), paper.Y + Sc(6) - s, paper.Right - Sc(14), lclip)
        todoPin = false
        hitClip = RectangleT.Empty
        TodoMeasured(h, pin, clip)
        ScrollDone("todo", h, lclip)
        g.Restore(st)
        if pin { TodoField(g, RectangleT(paper.X + Sc(36), lclip.Bottom + Sc(4), paper.Right - Sc(14) - paper.X - Sc(36), Sc(28)), clip) }
        Rings(g, paper)
        Scrollbar(g, "todo", paper, lclip)
        DuePopup(g, clip)
    }

    func TodoPage(_ g: Graphics, _ tx: Int, _ y0: Int, _ right: Int, _ clip: Rectangle) -> Int {
        var y = y0
        let bx = tx - Sc(8)
        let now = w.NbNow()
        if todos.Count == 0 && jira.Count == 0 && justDone.Count == 0 {
            NotebookForm.DT(g, "還沒有待辦", fWord, RectangleT(tx, y, right - tx, Sc(32)), NotebookForm.CSub, Pix.LeftMid)
            Drawn.Add("empty todo")
            y += Sc(32)
        } else {
            let shown = List<NbTodo>()
            for t in todos { if !(dragging && t.Id == dragTodo) { shown.Add(t) } }
            let drop = dragging ? DropIndex(dragTodo) : -1
            var dragAt = -1
            var i = 0
            while i <= shown.Count {
                if i == drop {
                    Pix.Box(g, Pix.C(0xFFF6D8), bx, y + Sc(1), right - bx + Sc(4), Sc(28) - Sc(2))
                    var dx = bx
                    while dx < right + Sc(4) { Pix.Box(g, Pix.C(0xD9A944), dx, y + Sc(1), Sc(4), Sc(2)); Pix.Box(g, Pix.C(0xD9A944), dx, y + Sc(25), Sc(4), Sc(2)); dx += Sc(8) }
                    dragAt = y
                    y += Sc(28)
                }
                if i == shown.Count { break }
                y += TodoRow(g, shown[i], bx, y, right, now, false)
                i += 1
            }
            _ = dragAt
            for j in justDone {
                let r = RectangleT(bx, y, right - bx, Sc(28))
                Chk(g, r.X + Sc(8), y + (Sc(28) - Sc(14)) / 2, true, false)
                let mv = "今天做了"
                let mw = TW(mv, fWord)
                let tx2 = r.X + Sc(8) + Sc(14) + Sc(8)
                let avail = right - Sc(6) - tx2 - mw - 3 * U - Sc(12)
                let txt = Ellipsis(j.T.Text, fBody, avail)
                NotebookForm.DT(g, txt, fBody, RectangleT(tx2, y, avail + 4, Sc(28)), NotebookForm.COff, Pix.LeftMid)
                Pix.Box(g, NotebookForm.COff, tx2, y + Sc(14), TW(txt, fBody), Sc(2))
                let ax = right - Sc(6) - mw
                Pix.Mono(g, NotebookForm.Mono(NotebookForm.IRIGHT), NotebookForm.COk, ax - 3 * U - Sc(4), y + Sc(14) - 5 * U / 2, U)
                NotebookForm.DT(g, mv, fWord, RectangleT(ax, y, mw + 4, Sc(28)), NotebookForm.COk, Pix.LeftMid)
                AddHit("untick", j.T.Id, RectangleT(r.X, y, Sc(8) + Sc(14) + Sc(8), Sc(28)))
                Drawn.Add("justdone " + j.T.Text)
                y += Sc(28)
            }
            if dragging {
                if let dt = FindTodo(dragTodo) {
                    let ly = Math.Max(clip.Y - Sc(10), Math.Min(clip.Bottom - Sc(20), dragY - Sc(14)))
                    TodoRow(g, dt, bx + Sc(8), ly - Sc(3), right + Sc(4), now, true)
                }
            }
        }
        // 新增一行（右邊小日曆：期限）；放不下時由呼叫的地方釘在最下面
        if !todoPin {
            y += Sc(4)
            TodoField(g, RectangleT(bx, y, right - bx, Sc(28)), clip)
            y += Sc(28) + Sc(4)
        }
        if jira.Count > 0 {
            let gr = RectangleT(tx, y, right - tx, Sc(40))
            NotebookForm.DT(g, "Jira 指派給我", fBody, RectangleT(gr.X, gr.Y, gr.Width, gr.Height - Sc(4)), NotebookForm.CGh, [TextFormatFlags.Left, TextFormatFlags.Bottom, TextFormatFlags.SingleLine, TextFormatFlags.NoPadding, TextFormatFlags.NoPrefix])
            Pix.Box(g, NotebookForm.CGhLine, gr.X, gr.Bottom - Sc(2), gr.Width, Sc(2))
            y += Sc(40) + Sc(4)
            for j in jira {
                DrawIcon(g, "jira", tx, y + Sc(14) - 7 * U / 2)
                let st = j.Status != "" ? j.Status : "待處理"
                let sw = TW(st, fWord), x2 = tx + 8 * U + Sc(8)
                let avail = right - Sc(6) - sw - Sc(8) - x2
                NotebookForm.DT(g, Ellipsis((j.Ref + " " + j.Title).Trim(), fBody, avail), fBody, RectangleT(x2, y, avail + 4, Sc(28)), NotebookForm.CText, Pix.LeftMid)
                NotebookForm.DT(g, st, fWord, RectangleT(right - Sc(6) - sw - 2, y, sw + 4, Sc(28)), NotebookForm.CTime, Pix.LeftMid)
                Drawn.Add("jira " + j.Ref + " " + j.Title + " | " + st)
                y += Sc(28)
            }
        }
        return y - y0
    }
    var dueAnchor = RectangleT.Empty
    var todoPin = false
    func TodoField(_ g: Graphics, _ fr: Rectangle, _ clip: Rectangle) {
        let chip = dueDay != DateTime.MinValue ? DueChip() : ""
        Field(g, fr, tbTodo, "寫一件要做的事，按 Enter", true, clip, chip)
        let cw0: Int = chip != "" ? TW(chip, fWord) + Sc(8) : 7 * U + Sc(4)
        rTodo = NotebookForm.Inside(fr, clip) ? RectangleT(fr.X, fr.Y, fr.Width - Sc(8) - cw0, fr.Height) : RectangleT.Empty
        AddHit("addtodo", "", fr)
        let cw1: Int = chip != "" ? TW(chip, fWord) : 7 * U
        let cal = RectangleT(fr.Right - Sc(8) - cw1 - Sc(4), fr.Y, cw1 + Sc(12), fr.Height)
        AddHit("due", "", cal)
        dueAnchor = fr
    }
    // 待辦清單（不含新增那一行）有多高：上一輪量的；放得下＝新增那一行接在清單裡
    func TodoClip(_ clip: Rectangle, _ pin: inout Bool) -> Rectangle {
        let fieldH = Sc(28) + Sc(8)
        var prev = 0
        contentH.TryGetValue("todolist", &prev)
        pin = prev + fieldH > clip.Height
        return pin ? RectangleT(clip.X, clip.Y, clip.Width, clip.Height - fieldH - Sc(4)) : clip
    }
    func TodoMeasured(_ h: Int, _ pin: Bool, _ clip: Rectangle) {
        let listH = pin ? h : h - Sc(28) - Sc(8)
        contentH["todolist"] = listH
        if (listH + Sc(28) + Sc(8) > clip.Height) != pin { again = true }
    }

    func DueChip() -> String {
        let today = w.NbNow().Date
        let days = (dueDay - today).Days
        let day = days == 0 ? "今天" : (days == 1 ? "明天" : Nb.WeekName(dueDay))
        return dueMin >= 0 ? day + " " + (dueMin / 60).ToString("00") + ":" + (dueMin % 60).ToString("00") : day
    }

    @discardableResult func TodoRow(_ g: Graphics, _ t: NbTodo, _ bx: Int, _ y: Int, _ right: Int, _ now: DateTime, _ lifted: Bool) -> Int {
        let hot = t.Id == hoverTodo && !lifted && !dragging, editing = editTodo == t.Id
        let row = RectangleT(bx, y, right - bx, Sc(28))
        if lifted {
            Pix.Box(g, Color.FromArgb(46, 74, 44, 23), row.X + Sc(4), row.Bottom, row.Width, Sc(4))
            Pix.Round(g, Pix.Ink, row.X, row.Y, row.Width, row.Height, U)
            Pix.Box(g, Color.White, row.X + U, row.Y + U, row.Width - 2 * U, row.Height - 2 * U)
        } else if hot {
            Pix.Round(g, Pix.C(0xD9A944), row.X, row.Y, row.Width, row.Height, U)
            Pix.Box(g, Pix.C(0xFFE29A), row.X + U, row.Y + U, row.Width - 2 * U, row.Height - 2 * U)
            Pix.Box(g, Pix.C(0xFFF1C9), row.X + U, row.Y + U, row.Width - 2 * U, Sc(3) - U)
        }
        if hot || lifted {
            let gp = Dict<Character, Color>(); gp["k"] = Pix.C(0xB08A5A)
            Pix.Art(g, NotebookForm.IGRIP, gp, bx - Sc(6), y + Sc(9), U)
        }
        if !lifted { AddHit("grip", t.Id, RectangleT(bx - Sc(10), y, Sc(16), Sc(28)), "todo:" + t.Id) }
        var x = bx + Sc(8)
        Chk(g, x, y + (Sc(28) - Sc(14)) / 2, false, Hot("tick", t.Id))
        if !lifted { AddHit("tick", t.Id, RectangleT(x - Sc(4), y, Sc(14) + Sc(8), Sc(28)), "todo:" + t.Id) }
        x += Sc(14) + Sc(8)
        if t.Src == "school" { DrawIcon(g, "hw", x, y + Sc(14) - 4 * U); x += 8 * U + Sc(8) }
        var urgent = false
        let due = Nb.DueText(t.Due, now, &urgent)
        let dw = due != "" ? TW(due, fWord) : 0
        let carried = t.Src != "school" && t.Created != "" && string.CompareOrdinal(t.Created, Nb.Ymd(now)) < 0
        let pw = carried ? TW("從昨天", fSmall) + Sc(12) : 0
        let end: Int = right - Sc(6) - dw - (dw > 0 ? Sc(8) : 0) - (carried ? pw + Sc(8) : 0)
        let cw = t.Src == "school" && t.Course != "" ? TW(t.Course, fSmall) + Sc(6) : 0
        let txt = Ellipsis(t.Text, fBody, end - x - cw)
        let tw = TW(txt, fBody)
        if editing {
            rEdit = RectangleT(x, y + Sc(3), end - x, Sc(22))
            Pix.Round(g, Pix.Ink, rEdit.X - Sc(4), rEdit.Y - Sc(2), rEdit.Width + Sc(8), rEdit.Height + Sc(4), U)
            Pix.Box(g, NotebookForm.CPaper, rEdit.X - Sc(4) + U, rEdit.Y - Sc(2) + U, rEdit.Width + Sc(8) - 2 * U, rEdit.Height + Sc(4) - 2 * U)
            if App.Offscreen { NotebookForm.DT(g, tbEdit.Text, fBody, rEdit, NotebookForm.CText, Pix.LeftMid) }
        } else {
            NotebookForm.DT(g, txt, fBody, RectangleT(x, y, tw + 4, Sc(28)), NotebookForm.CText, Pix.LeftMid)
            if cw > 0 { NotebookForm.DT(g, t.Course, fSmall, RectangleT(x + tw + Sc(6), y + Sc(1), cw + 4, Sc(28)), NotebookForm.CSub, Pix.LeftMid) }
        }
        if !lifted { AddHit("tedit", t.Id, RectangleT(x, y, Math.Max(Sc(20), end - x), Sc(28)), "todo:" + t.Id) }
        var rx = right - Sc(6)
        if dw > 0 { NotebookForm.DT(g, due, fWord, RectangleT(rx - dw - 2, y, dw + 4, Sc(28)), urgent ? NotebookForm.CBad : NotebookForm.CTime, Pix.LeftMid); rx -= dw + Sc(8) }
        if carried {
            let pr = RectangleT(rx - pw, y + (Sc(28) - Sc(18)) / 2, pw, Sc(18))
            Pix.Round(g, Pix.C(0xC9B08A), pr.X, pr.Y, pr.Width, pr.Height, U)
            Pix.Box(g, Pix.C(0xF3EADB), pr.X + U, pr.Y + U, pr.Width - 2 * U, pr.Height - 2 * U)
            NotebookForm.DT(g, "從昨天", fSmall, RectangleT(pr.X, pr.Y, pr.Width, pr.Height - 1), NotebookForm.CSub, Pix.Mid)
        }
        if !lifted { todoRows[t.Id] = row; AddHit("row", t.Id, row, "todo:" + t.Id, true) }
        if !lifted {
            let srcS: String = t.Src == "school" ? "school" : "mine"
            let carS: String = carried ? " carried" : "", hotS: String = hot ? " hot" : ""
            let courseS: String = t.Course != "" ? " | " + t.Course : ""
            let bang: String = urgent && due != "" ? " !" : ""
            Drawn.Add("todo " + t.Id + " " + srcS + carS + hotS + " | " + t.Text + courseS + " | " + due + bang)
        }
        else { Drawn.Add("lifted " + t.Id) }
        return Sc(28)
    }

    // 期限：今天、明天、週X…；不設時間、12:00、18:00、22:00、23:59；不設期限
    func DuePopup(_ g: Graphics, _ clip: Rectangle) {
        if !duePick || dueAnchor.IsEmpty { return }
        let today = w.NbNow().Date
        var dayChips: [[String]] = []
        for i in 0..<7 { dayChips.append([i == 0 ? "今天" : (i == 1 ? "明天" : Nb.WeekName(today.AddDays(i))), String(i)]) }
        let times: [[String]] = [["不設時間", "-1"], ["12:00", "720"], ["18:00", "1080"], ["22:00", "1320"], ["23:59", "1439"]]
        let pad = Sc(8), ch = Sc(24), gap = Sc(6), wdt = Sc(250)
        let rowsH: Int = pad + ch * 4 + gap * 3 + pad
        var box = RectangleT(dueAnchor.Right - wdt, dueAnchor.Bottom + Sc(4), wdt, rowsH)
        if box.Bottom > clip.Bottom { box.Y = dueAnchor.Y - Sc(4) - rowsH }
        Pix.Round(g, Pix.Ink, box.X, box.Y, box.Width, box.Height, U)
        Pix.Box(g, Pix.Cream, box.X + U, box.Y + U, box.Width - 2 * U, box.Height - 2 * U)
        var x = box.X + pad, y = box.Y + pad
        for i in 0..<dayChips.count {
            if i == 4 { x = box.X + pad; y += ch + gap }
            let t = dayChips[i][0]
            let cw = TW(t, fBtnS) + Sc(18)
            let r = RectangleT(x, y, cw, ch)
            let on = dueDay != DateTime.MinValue && (dueDay - today).Days.ToString() == dayChips[i][1]
            SmallBtn(g, r, t, false, on || Hot("dueday", dayChips[i][1]))
            AddHit("dueday", dayChips[i][1], r)
            x += cw + gap
        }
        x = box.X + pad; y += ch + gap
        for i in 0..<times.count {
            if i == 3 { x = box.X + pad; y += ch + gap }
            let cw = TW(times[i][0], fBtnS) + Sc(18)
            let r = RectangleT(x, y, cw, ch)
            let none = times[i][1] == "-1"
            SmallBtn(g, r, times[i][0], false, Hot(none ? "duenotime" : "duetime", none ? "" : times[i][1]))
            if none { AddHit("duenotime", "", r) } else { AddHit("duetime", times[i][1], r) }
            x += cw + gap
        }
        let cl = "不設期限"
        let clw = TW(cl, fBtnS) + Sc(18)
        let cr = RectangleT(box.Right - pad - clw, y, clw, ch)
        SmallBtn(g, cr, cl, false, Hot("dueclear", ""))
        AddHit("dueclear", "", cr)
        Drawn.Add("duepick")
    }

    // ---- 筆記（一頁）----
    func NoteArea(_ g: Graphics, _ area: Rectangle) {
        let foot = Sc(34)
        let paper = Paper(g, RectangleT(area.X, area.Y, area.Width, area.Height - Sc(8) - foot), NotebookForm.CPaper, 2, true)
        let box = RectangleT(paper.X + Sc(44), paper.Y + Sc(6), paper.Width - Sc(44) - Sc(14), paper.Height - Sc(12))
        NoteLines(g, paper, box)
        NoteText(g, box)
        Rings(g, paper)
        AddHit("notefocus", "", box)
        rNote = box
        let fy = paper.Bottom + U + Sc(8) - U
        let empty = note.Text.Trim() == ""
        if !empty && savedAt != "" {
            Pix.Mono(g, Pix.CHECK, NotebookForm.COk, area.X, fy + foot / 2 - 5 * U / 2, U)
            NotebookForm.DT(g, "已存 " + savedAt, fSmall, RectangleT(area.X + 5 * U + Sc(6), fy, Sc(160), foot), NotebookForm.CSub, Pix.LeftMid)
        }
        let ct = copied == "note" ? "已複製筆記" : "複製筆記"
        let cw: Int = TW(ct, fBtn) + Sc(28) + (copied == "note" ? 5 * U + Sc(6) : 0)
        let cr = RectangleT(area.Right - cw, fy + (foot - Sc(32)) / 2, cw, Sc(32))
        BigBtn(g, cr, ct, empty ? 3 : (copied == "note" ? 2 : 0), Hot("copy", "note"))
        if !empty { AddHit("copy", "note", cr) }
        let svS: String = savedAt == "" ? "-" : savedAt, emS: String = empty ? "empty" : "text"
        Drawn.Add("note saved=" + svS + " " + emS)
    }

    // 28px 一行、每行底下一條線（跟 RichEdit 的固定行高對齊）
    func NoteLines(_ g: Graphics, _ paper: Rectangle, _ box: Rectangle) {
        var y = box.Y + Sc(28) - Sc(2)
        while y < paper.Bottom - Sc(2) { Pix.Box(g, Pix.C(0xEFE0C4), paper.X, y, paper.Width - Sc(6), 1); y += Sc(28) }
    }
    func NoteText(_ g: Graphics, _ box: Rectangle) {
        let text = note.Text.Replace("\r\n", "\n")
        if text.Trim() == "" && !(note.Visible && note.Focused) {
            NotebookForm.DT(g, "隨手寫，會自己存", fNote, RectangleT(box.X, box.Y, box.Width, Sc(28) - Sc(2)), NotebookForm.CPh, [TextFormatFlags.Left, TextFormatFlags.Bottom, TextFormatFlags.SingleLine, TextFormatFlags.NoPadding, TextFormatFlags.NoPrefix])
            return
        }
        if !App.Offscreen && note.Visible { return }
        // 離屏（或還沒點進去）：自己照 28px 一行畫，換行跟 RichEdit 一樣一個字一個字斷
        var y = box.Y
        for para in text.Split("\n") {
            let runs = List<Run>()
            runs.Add(Run(para == "" ? " " : para, fNote, NotebookForm.CNote))
            let n = FlowLines(g, runs, box.X, y, box.Width, Sc(28), y + Sc(28) - Sc(4))
            y += Math.Max(1, n) * Sc(28)
            if y > box.Bottom { break }
        }
    }

    // ---- 攤開的左頁：待辦＋筆記 ----
    func LeftSpread(_ g: Graphics, _ area: Rectangle) {
        let paper = Paper(g, area, NotebookForm.CPaper, -1, false)
        let tx = paper.X + Sc(14), right = paper.Right - Sc(14)
        let noteMin = Sc(40) + Sc(28) * 4 + Sc(6)
        var clip = RectangleT(paper.X + Sc(6), paper.Y + Sc(6), paper.Width - Sc(8), paper.Height - Sc(12) - noteMin)
        var pin = false
        let lclip = TodoClip(clip, &pin)
        let s = ScrollOf("todo", lclip)
        let st = g.Save()
        g.SetClip(lclip)
        hitClip = RectangleT(paper.X - Sc(12), lclip.Y, paper.Width + Sc(12), lclip.Height)
        todoPin = pin
        let h = TodoPage(g, tx, paper.Y + Sc(6) - s, right, lclip)
        todoPin = false
        hitClip = RectangleT.Empty
        g.Restore(st)
        TodoMeasured(h, pin, clip)
        ScrollDone("todo", h, lclip)
        if pin { TodoField(g, RectangleT(tx - Sc(8), lclip.Bottom + Sc(4), right - tx + Sc(8), Sc(28)), clip) }
        let used = pin ? clip.Height : Math.Min(h, clip.Height)
        clip.Height = used
        clipR["todo"] = pin ? lclip : clip
        Scrollbar(g, "todo", RectangleT(paper.X, clip.Y - Sc(6), paper.Width, clip.Height + Sc(12)), clip)
        // 筆記：標題列（已存、複製）＋下面的紙
        let ny = clip.Bottom
        let gr = RectangleT(tx, ny, right - tx, Sc(40))
        NotebookForm.DT(g, "筆記", fBody, RectangleT(gr.X, gr.Y, gr.Width, gr.Height - Sc(4)), NotebookForm.CGh, [TextFormatFlags.Left, TextFormatFlags.Bottom, TextFormatFlags.SingleLine, TextFormatFlags.NoPadding, TextFormatFlags.NoPrefix])
        Pix.Box(g, NotebookForm.CGhLine, gr.X, gr.Bottom - Sc(2), gr.Width, Sc(2))
        let empty = note.Text.Trim() == ""
        let ct = copied == "note" ? "已複製" : "複製"
        let cw = TW(ct, fBtnS) + Sc(18)
        let cr = RectangleT(right - cw, gr.Bottom - Sc(4) - Sc(24) - Sc(2), cw, Sc(24))
        if empty { SmallBtnOff(g, cr, ct) } else { SmallBtn(g, cr, ct, false, Hot("copy", "note")) }
        if !empty { AddHit("copy", "note", cr) }
        if !empty && savedAt != "" {
            let sv = "已存 " + savedAt
            let sw = TW(sv, fSmall)
            NotebookForm.DT(g, sv, fSmall, RectangleT(cr.X - Sc(8) - sw - 2, cr.Y, sw + 4, cr.Height), NotebookForm.CSub, Pix.LeftMid)
            Pix.Mono(g, Pix.CHECK, NotebookForm.COk, cr.X - Sc(8) - sw - Sc(6) - 5 * U, cr.Y + cr.Height / 2 - 5 * U / 2, U)
        }
        let box = RectangleT(tx, gr.Bottom + Sc(4), right - tx, paper.Bottom - Sc(6) - gr.Bottom - Sc(4))
        NoteText(g, box)
        AddHit("notefocus", "", box)
        rNote = box
        let svS: String = savedAt == "" ? "-" : savedAt, emS: String = empty ? "empty" : "text"
        Drawn.Add("note saved=" + svS + " " + emS)
        DuePopup(g, RectangleT(paper.X, paper.Y, paper.Width, paper.Height))
    }

    // ================= 打字框放到畫出來的位置 =================
    func PlaceBoxes() {
        let pad = Sc(8) + 5 * U + Sc(8)
        Place(tbTodo, rTodo.IsEmpty ? RectangleT.Empty : RectangleT(rTodo.X + pad, rTodo.Y + (rTodo.Height - tbTodo.PreferredHeight) / 2, rTodo.Width - pad, tbTodo.PreferredHeight))
        Place(tbDone, rDone.IsEmpty ? RectangleT.Empty : RectangleT(rDone.X + pad, rDone.Y + (rDone.Height - tbDone.PreferredHeight) / 2, rDone.Width - pad - Sc(8), tbDone.PreferredHeight))
        Place(tbEdit, rEdit.IsEmpty ? RectangleT.Empty : RectangleT(rEdit.X, rEdit.Y + (rEdit.Height - tbEdit.PreferredHeight) / 2, rEdit.Width, tbEdit.PreferredHeight))
        let noteOn = !rNote.IsEmpty && (note.Text != "" || note.Focused || note.Visible)
        if rNote.IsEmpty { if note.Visible { note.Visible = false; MacDropFocus(note) } }   // mac: MacDropFocus
        else {
            let nr = RectangleT(rNote.X, rNote.Y, rNote.Width + Sc(10), rNote.Height)
            if note.Bounds != nr { note.Bounds = nr }
            if noteOn != note.Visible { note.Visible = noteOn }
        }
    }
    func Place(_ c: Control, _ r: Rectangle) {
        if r.IsEmpty { if c.Visible { c.Visible = false; MacDropFocus(c) }; return }   // mac: MacDropFocus
        if c.Bounds != r { c.Bounds = r }
        if !c.Visible { c.Visible = true }
    }
    static func Inside(_ r: Rectangle, _ clip: Rectangle) -> Bool { return r.Y >= clip.Y - 2 && r.Bottom <= clip.Bottom + 2 }

    // ================= 小零件 =================
    // 輸入框：奶油白、淺棕邊（打字中＝深色邊）；左邊 ＋、右邊小日曆或期限
    func Field(_ g: Graphics, _ r: Rectangle, _ tb: TextBox, _ ph: String, _ cal: Bool, _ clip: Rectangle) { Field(g, r, tb, ph, cal, clip, "") }
    func Field(_ g: Graphics, _ r: Rectangle, _ tb: TextBox, _ ph: String, _ cal: Bool, _ clip: Rectangle, _ chip: String) {
        let focus = tb.Focused || (App.Offscreen && tb.Text != "")
        Pix.Round(g, focus ? Pix.Ink : NotebookForm.CField, r.X, r.Y, r.Width, r.Height, U)
        Pix.Box(g, NotebookForm.CPaper, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U)
        Pix.Box(g, Pix.C(0xF1E6D0), r.X + U, r.Y + U, r.Width - 2 * U, U)
        let x = r.X + Sc(8)
        if !focus || tb.Text == "" { Pix.Mono(g, NotebookForm.Mono(NotebookForm.IPLUS), NotebookForm.CTime, x, r.Y + (r.Height - 5 * U) / 2, U) }
        let tx = x + 5 * U + Sc(8)
        if App.Offscreen || !tb.Visible {
            if tb.Text == "" { NotebookForm.DT(g, ph, fField, RectangleT(tx, r.Y, r.Width - (tx - r.X), r.Height), NotebookForm.CPh, Pix.LeftMid) }
            else {
                let tw = TW(tb.Text, fField)
                NotebookForm.DT(g, tb.Text, fField, RectangleT(tx, r.Y, tw + 4, r.Height), NotebookForm.CText, Pix.LeftMid)
                if App.Offscreen { Pix.Box(g, NotebookForm.CText, tx + tw + 1, r.Y + Sc(7), 1, r.Height - Sc(14)) }   // 游標
            }
        }
        if chip != "" {
            let cw = TW(chip, fWord)
            NotebookForm.DT(g, chip, fWord, RectangleT(r.Right - Sc(8) - cw - 2, r.Y, cw + 4, r.Height), Pix.C(0x35577F), Pix.LeftMid)
        } else if cal {
            let p = Dict<Character, Color>(); p["k"] = Pix.C(0x9A6338); p["w"] = NotebookForm.CPaper
            Pix.Art(g, NotebookForm.ICAL, p, r.Right - Sc(8) - 7 * U, r.Y + (r.Height - 6 * U) / 2, U)
        }
        let which: String = tb === tbTodo ? "todo" : "done"
        let typed: String = tb.Text == "" ? "-" : tb.Text
        let chipS: String = chip != "" ? " | " + chip : ""
        Drawn.Add("field " + which + " " + typed + chipS)
    }

    func Chk(_ g: Graphics, _ x: Int, _ y: Int, _ on: Bool, _ hot: Bool) {
        let s = Sc(14)
        Pix.Round(g, Pix.C(0x9A6338), x, y, s, s, U)
        Pix.Box(g, on ? Pix.C(0xDDF2C8) : (hot ? Pix.C(0xFFF3D6) : NotebookForm.CPaper), x + U, y + U, s - 2 * U, s - 2 * U)
        if on { Pix.Mono(g, Pix.CHECK, Pix.C(0x3F8A30), x + U, y + U, U) }
    }

    // 小按鈕（24 高）：奶油色、深色邊、下緣一條陰影
    func SmallBtn(_ g: Graphics, _ r: Rectangle, _ t: String, _ off: Bool, _ hot: Bool) {
        if off { SmallBtnOff(g, r, t); return }
        Pix.Round(g, Pix.Ink, r.X, r.Y, r.Width, r.Height, U)
        let face = hot ? Pix.C(0xFFF3D6) : NotebookForm.CBtn
        Pix.Box(g, face, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U)
        let sh = r.Height >= Sc(24) ? Sc(4) - U : Sc(3) - U
        Pix.Box(g, Pix.C(0xDCC6A2), r.X + U, r.Bottom - U - sh, r.Width - 2 * U, sh)
        if t != "" { NotebookForm.DT(g, t, fBtnS, RectangleT(r.X, r.Y, r.Width, r.Height - sh), NotebookForm.CText, Pix.Mid) }
    }
    func SmallBtnOff(_ g: Graphics, _ r: Rectangle, _ t: String) {
        Pix.Round(g, Pix.C(0xBBA98C), r.X, r.Y, r.Width, r.Height, U)
        Pix.Box(g, Pix.C(0xE9E0D0), r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U)
        Pix.Box(g, Pix.C(0xD3C7B2), r.X + U, r.Bottom - U - (Sc(4) - U), r.Width - 2 * U, Sc(4) - U)
        if t != "" { NotebookForm.DT(g, t, fBtnS, RectangleT(r.X, r.Y, r.Width, r.Height - Sc(3)), Pix.Dim, Pix.Mid) }
    }
    // 大按鈕（32 高）：kind 0 一般、1 主要（蜂蜜色）、2 已複製（綠＋勾）、3 不能按
    func BigBtn(_ g: Graphics, _ r: Rectangle, _ t: String, _ kind: Int, _ hot: Bool) {
        let edge: Color = kind == 2 ? Pix.C(0x2F6E24) : (kind == 3 ? Pix.C(0xBBA98C) : Pix.Ink)
        var face: Color = hot ? Pix.C(0xFFF3D6) : NotebookForm.CBtn
        if kind == 1 { face = hot ? Pix.C(0xFFD36A) : Pix.C(0xF6C453) } else if kind == 2 { face = Pix.C(0xD9F0C4) } else if kind == 3 { face = Pix.C(0xE9E0D0) }
        let shade: Color = kind == 1 ? Pix.C(0xC8902C) : (kind == 2 ? Pix.C(0xA9CF90) : (kind == 3 ? Pix.C(0xD3C7B2) : Pix.C(0xDCC6A2)))
        let hi: Color = kind == 1 ? Pix.C(0xFBE7BA) : (kind == 2 ? Pix.C(0xF0F9E8) : Pix.C(0xFFFEF9))
        Pix.Round(g, edge, r.X, r.Y, r.Width, r.Height, U)
        Pix.Box(g, face, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U)
        Pix.Box(g, shade, r.X + U, r.Bottom - U - Sc(4), r.Width - 2 * U, Sc(4))
        if kind != 3 { Pix.Box(g, hi, r.X + U, r.Y + U, r.Width - 2 * U, U) }
        let tc: Color = kind == 2 ? Pix.C(0x2B5420) : (kind == 3 ? Pix.Dim : NotebookForm.CText)
        let tw = TW(t, fBtn)
        var x = r.X + (r.Width - tw) / 2
        if kind == 2 { x += (5 * U + Sc(6)) / 2; Pix.Mono(g, Pix.CHECK, Pix.C(0x2F6E24), x - Sc(6) - 5 * U, r.Y + (r.Height - Sc(4)) / 2 - 5 * U / 2, U) }
        NotebookForm.DT(g, t, fBtn, RectangleT(x, r.Y, tw + 4, r.Height - Sc(4)), tc, Pix.LeftMid)
    }

    func DrawIcon(_ g: Graphics, _ src: String, _ x: Int, _ y: Int) {
        let p = Dict<Character, Color>()
        p["k"] = Pix.Ink
        var a: [String]
        switch src {
        case "claude", "codex": a = NotebookForm.ICLAUDE; p["d"] = Pix.C(0x5A4632); p["g"] = Pix.C(0xF4A06A)
        case "jira": a = NotebookForm.IJIRA; p["b"] = Pix.C(0x6E9BD8); p["w"] = Pix.C(0xE4EEFA)
        case "github", "gitlab": a = NotebookForm.IMR; p["p"] = Pix.C(0xA585D4)
        case "calendar": a = NotebookForm.IMEET; p["r"] = Pix.C(0xE07856); p["w"] = NotebookForm.CPaper
        case "school": a = NotebookForm.ICLASS; p["g"] = Pix.C(0x6FB25C); p["w"] = NotebookForm.CPaper
        default: a = NotebookForm.IHW; p["w"] = NotebookForm.CPaper
        }
        Pix.Art(g, a, p, x, y, U)
    }

    // ---- 字 ----
    final class Run { var S: String; var F: FontT; var C: Color; var Keep = false, KeepNext = false; init(_ s: String, _ f: FontT, _ c: Color) { S = s; F = f; C = c } }   // Keep：結果字不拆開；KeepNext：逗號跟下一個字一起換行
    let tw = Dict<String, Int>()
    func TW(_ s: String, _ f: FontT) -> Int {
        let k = f.Size.ToString() + (f.Bold ? "b" : "r") + "|" + s
        var v = 0
        if tw.TryGetValue(k, &v) { return v }
        if tw.Count > 4000 { tw.Clear() }
        v = s == "" ? 0 : CInt(Math.Ceiling(NotebookForm.Measure(s, f) - 0.01))
        tw[k] = v
        return v
    }
    // TextRenderer 預設不管 Graphics 的裁切：捲動的紙上要保留裁切，字才不會畫到紙外面
    // 字一律用 GDI+ 反鋸齒（AntiAliasGridFit）畫：
    //   TextRenderer（GDI）畫正黑體粗體 11pt 這種小字會用字型裡內嵌的點陣字，筆畫擠成一團（遠端桌面、截圖都一樣）；
    //   GDI+ 一定畫外框、灰階反鋸齒，跟系統的字型平滑設定無關，所以螢幕上跟離屏截圖長得一樣。起點對齊整數像素，筆畫才不會糊。
    // mac: Graphics.DrawString／MeasureString（typographic）＝CoreText，螢幕跟離屏一樣
    static let SF: StringFormat = MakeSF()
    static func MakeSF() -> StringFormat {
        let f = StringFormat.GenericTypographic   // mac: 每次回新的一個（＝C# 的 Clone()）
        f.FormatFlags = f.FormatFlags.union([StringFormatFlags.MeasureTrailingSpaces, StringFormatFlags.NoWrap, StringFormatFlags.NoClip])
        return f
    }
    static func Px(_ family: String, _ px: Double, _ st: FontStyle) -> FontT { return FontT(family, px, st, GraphicsUnit.Pixel) }
    static func CellH(_ f: FontT) -> Double {
        let ff = f.FontFamily
        return f.Size * Double(ff.GetCellAscent(f.Style) + ff.GetCellDescent(f.Style)) / Double(ff.GetEmHeight(f.Style))
    }
    static func DT(_ g: Graphics, _ s: String, _ f: FontT, _ r: Rectangle, _ c: Color, _ fl: TextFormatFlags) {
        if string.IsNullOrEmpty(s) { return }
        let w = Measure(s, f), h = CellH(f)
        var x = Double(r.X), y = Double(r.Y)
        if fl.contains(TextFormatFlags.HorizontalCenter) { x = Double(r.X) + (Double(r.Width) - w) / 2 }
        else if fl.contains(TextFormatFlags.Right) { x = Double(r.Right) - w }
        if fl.contains(TextFormatFlags.VerticalCenter) { y = Double(r.Y) + (Double(r.Height) - h) / 2 }
        else if fl.contains(TextFormatFlags.Bottom) { y = Double(r.Bottom) - h }
        Draw(g, s, f, c, x, y)
    }
    static func DT(_ g: Graphics, _ s: String, _ f: FontT, _ p: Point, _ c: Color, _ fl: TextFormatFlags) { if !string.IsNullOrEmpty(s) { Draw(g, s, f, c, Double(p.X), Double(p.Y)) } }
    static func Draw(_ g: Graphics, _ s: String, _ f: FontT, _ c: Color, _ x: Double, _ y: Double) {
        let was = g.TextRenderingHint
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit
        do {
            let b = SolidBrush(c)
            g.DrawString(s, f, b, Math.Round(x), Math.Round(y), SF)
            // mac: 不畫第二次（C# 右移 PixText.Heft 再畫一次，補 GDI+ 的細字；CoreText 的粗體本來就夠粗）
        }
        g.TextRenderingHint = was
    }
    static var measureBmp: Bitmap! = nil
    static var measureG: Graphics! = nil
    static func Measure(_ s: String, _ f: FontT) -> Double {
        if measureG == nil { measureBmp = Bitmap(1, 1); measureG = Graphics.FromImage(measureBmp); measureG.TextRenderingHint = TextRenderingHint.AntiAliasGridFit }
        // mac: CoreText 量字不算最後的空白（GDI+ 有 MeasureTrailingSpaces）→ 後面補一個字再扣掉
        if s.hasSuffix(" ") || s.hasSuffix("\u{3000}") {
            let a = measureG.MeasureString(s + "|", f, PointF.Empty, SF).Width, b = measureG.MeasureString("|", f, PointF.Empty, SF).Width
            return a - b
        }
        return measureG.MeasureString(s, f, PointF.Empty, SF).Width
    }
    // 畫的時候用同一個 Graphics 量（螢幕跟離屏點陣圖的字寬可能差一點，不然字跟字之間會空一格）
    func TWg(_ g: Graphics?, _ s: String, _ f: FontT) -> Int {
        return TW(s, f)   // GDI+ 的像素字型：量出來跟在哪裡畫無關
    }
    func Ellipsis(_ s: String, _ f: FontT, _ w0: Int) -> String {
        if TW(s, f) <= w0 { return s }
        var n = s.Length - 1
        while n > 0 { let t = s.Substring(0, n) + "…"; if TW(t, f) <= w0 { return t }; n -= 1 }
        return "…"
    }
    static func RunsText(_ runs: List<Run>) -> String { let sb = StringBuilder(); for r in runs { sb.Append(r.S) }; return sb.ToString() }
    func FlowW(_ runs: List<Run>) -> Int { var x = 0; for r in runs { x += TW(r.S, r.F) }; return x }

    // 字的上緣到基準線（GDI 的 cell ascent）
    let asc = Dict<ObjectIdentifier, Int>()   // mac: C# 用 Font 當 key（參考相等）→ ObjectIdentifier
    func Asc(_ f: FontT) -> Int {
        var v = 0
        if asc.TryGetValue(ObjectIdentifier(f), &v) { return v }
        let ff = f.FontFamily
        let px: Double = f.Unit == GraphicsUnit.Pixel ? f.Size : f.SizeInPoints * 96.0 * d / 72.0
        v = CInt(Math.Round(px * Double(ff.GetCellAscent(f.Style)) / Double(ff.GetEmHeight(f.Style))))
        asc[ObjectIdentifier(f)] = v
        return v
    }

    // 一串不同字型的字照寬度排，超過就換行（中文一個字一個字斷、英文盡量在空白斷）；回傳幾行。g＝null 只量不畫
    @discardableResult func Flow(_ g: Graphics?, _ runs: List<Run>, _ x0: Int, _ y0: Int, _ w0: Int, _ lineH: Int, _ strike: Bool) -> Int { return Flow(g, runs, x0, y0, w0, lineH, strike, true) }
    @discardableResult func Flow(_ g: Graphics?, _ runs: List<Run>, _ x0: Int, _ y0: Int, _ w0: Int, _ lineH: Int, _ strike: Bool, _ paint: Bool) -> Int {
        let mainAsc = runs.Count > 0 ? Asc(runs[0].F) : 0
        let baseOff = (lineH + mainAsc - CInt(Math.Round(Double(mainAsc) * 0.32))) / 2
        return FlowCore(g, runs, x0, y0, w0, lineH, strike, 0, baseOff, paint)
    }
    func FlowHang(_ g: Graphics?, _ runs: List<Run>, _ x0: Int, _ y0: Int, _ w0: Int, _ lineH: Int, _ hang: Int) -> Int {
        let mainAsc = runs.Count > 0 ? Asc(runs[0].F) : 0
        let baseOff = (lineH + mainAsc - CInt(Math.Round(Double(mainAsc) * 0.32))) / 2
        return FlowCore(g, runs, x0, y0, w0, lineH, false, hang, baseOff, true)
    }
    func FlowLines(_ g: Graphics?, _ runs: List<Run>, _ x0: Int, _ y0: Int, _ w0: Int, _ lineH: Int, _ baseline: Int) -> Int {
        return FlowCore(g, runs, x0, y0, w0, lineH, false, 0, baseline - y0, true)
    }
    func FlowCore(_ g: Graphics?, _ runs: List<Run>, _ x0: Int, _ y0: Int, _ w0: Int, _ lineH: Int, _ strike: Bool, _ hang: Int, _ baseOff: Int, _ paint: Bool) -> Int {
        var x = x0, line = 0
        var ri = 0
        while ri < runs.Count {
            let r = runs[ri]
            var s = r.S
            if r.Keep || r.KeepNext {
                let nextW: Int = r.KeepNext && ri + 1 < runs.Count ? TWg(g, runs[ri + 1].S, runs[ri + 1].F) : 0
                let need = TWg(g, s, r.F) + nextW
                if x + need > x0 + w0 && x > x0 + hang && need <= w0 - hang { line += 1; x = x0 + hang }
            }
            while s.Length > 0 {
                let room = x0 + w0 - x
                var n = Fit(g, s, r.F, room)
                if n == 0 {
                    if x == x0 + (line > 0 ? hang : 0) { n = 1 }   // 一個字都放不下：硬放
                    else { line += 1; x = x0 + hang; if s.StartsWith(" ") { s = s.TrimStart(" ") }; continue }
                }
                let part = s.Substring(0, n)
                let pw = TWg(g, part, r.F)
                if let gg = g, paint {
                    let top = y0 + line * lineH + baseOff - Asc(r.F)
                    NotebookForm.DT(gg, part, r.F, PointT(x, top), r.C, [TextFormatFlags.NoPadding, TextFormatFlags.NoPrefix, TextFormatFlags.SingleLine])
                    if strike { Pix.Box(gg, r.C, x, y0 + line * lineH + baseOff - CInt(Math.Round(Double(Asc(runs[0].F)) * 0.36)), pw, Sc(2)) }
                }
                x += pw
                s = s.Substring(n)
                if s.Length > 0 { line += 1; x = x0 + hang; s = s.TrimStart(" ") }
            }
            ri += 1
        }
        return line + 1
    }
    // 放得下幾個字（英文單字不從中間切，除非整個字就比一行長）
    func Fit(_ g: Graphics?, _ s: String, _ f: FontT, _ room: Int) -> Int {
        if room <= 0 { return 0 }
        if TWg(g, s, f) <= room { return s.Length }
        var lo = 0, hi = s.Length
        while lo < hi { let mid = (lo + hi + 1) / 2; if TWg(g, s.Substring(0, mid), f) <= room { lo = mid } else { hi = mid - 1 } }
        if lo > 0 && lo < s.Length && NotebookForm.IsWord(s[lo]) && NotebookForm.IsWord(s[lo - 1]) {
            var b = lo
            while b > 0 && NotebookForm.IsWord(s[b - 1]) { b -= 1 }
            if b > 0 { lo = b }
        }
        return lo
    }
    static func IsWord(_ c: Character) -> Bool {
        guard c.unicodeScalars.count == 1, let u = c.unicodeScalars.first, u.value < 128 else { return false }
        return char.IsLetterOrDigit(c) || c == "." || c == "-" || c == "_" || c == "/" || c == "#" || c == "!"
    }

    // ================= 測試用：現在畫了什麼 =================
    // 離屏：沒有 WM_PAINT，要先畫一次才知道東西在哪（點擊、nb-info）
    func Render() {
        if Width <= 0 || Height <= 0 { return }
        let b = Bitmap(Width, Height, PixelFormat.Format24bppRgb)
        do { let g = Graphics.FromImage(b); OnPaint(PaintEventArgs(g, RectangleT(0, 0, Width, Height))) }
    }
    func Info() -> String {
        Render()
        let sb = StringBuilder()
        let sp: String = Spread ? "1" : "0", pv: String = Preview ? "1" : "0", lk: String = Links ? "1" : "0"
        sb.Append("nb open=1 tab=" + Tab + " spread=" + sp + " preview=" + pv + " kind=" + PvKind)
        sb.Append(" links=" + lk + " day=" + Nb.Ymd(Day))
        sb.Append(" x=" + String(Left) + " y=" + String(Top) + " w=" + String(Width) + " h=" + String(Height) + " frame=" + String(Left + OV))
        sb.Append(" todos=" + String(todos.Count) + " jira=" + String(jira.Count) + " things=" + String(things.Count) + " on=" + String(Nb.OnCount(things)))
        let cp: String = copied == "" ? "-" : copied, sv: String = savedAt == "" ? "-" : savedAt
        let ed: String = editThing != "" ? editThing : (editTodo != "" ? editTodo : "-")
        sb.Append(" copied=" + cp + " saved=" + sv)
        sb.Append(" edit=" + ed + "\n")
        for s in Drawn { sb.Append(s + "\n") }
        for h in hits {
            if h.Act == "row" { continue }
            let arg: String = h.Arg == "" ? "-" : h.Arg
            let geo: String = String(h.R.X + Left) + " " + String(h.R.Y + Top) + " " + String(h.R.Width) + " " + String(h.R.Height)
            sb.Append("hit " + h.Act + " " + arg + " " + geo + "\n")
        }
        for t in todos {
            let due: String = t.Due == "" ? "-" : t.Due
            let src: String = t.Src == "" ? "mine" : t.Src
            sb.Append("todoitem " + t.Id + " " + src + " " + due + " " + t.Created + " " + t.Text + "\n")
        }
        sb.Append("notetext " + JavaScriptSerializer().Serialize(note.Text.Replace("\r\n", "\n")) + "\n")
        return sb.ToString()
    }
    // mac: `Type` 要加反引號（Swift 的成員不能直接叫 Type）
    func `Type`(_ box: String, _ s: String) {
        if box == "todo" { tbTodo.Text = s }
        else if box == "done" { tbDone.Text = s }
        else if box == "edit" { tbEdit.Text = s }
        else if box == "note" { note.Text = s; noteDirty = true; noteSaveAt = w.Now + 0.7 }   // 沒有 handle 的 RichTextBox 不一定會送 TextChanged
        Invalidate()
    }
}

//@@IN World
    var nbForm: NotebookForm! = nil
    var nbClip = "", nbSaid = ""
    // ---- 學校行事曆：今天上過的課（從 ICS 算，不寫進 log）----
    let nbFeeds = Dict<String, SchoolFeed>()
//@@END

extension World {
    func NbNow() -> DateTime { return SNow() }
    // 減少動態：勾掉的那一行留短一點
    // mac: SystemInformation.UIEffectsEnabled → 輔助使用「減少動態效果」
    func NbReduced() -> Bool { return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // 小屋選單／公仔選單「小本子…」
    func ShowNotebook() { ShowNotebook("") }
    func ShowNotebook(_ tab: String) {
        let fresh = nbForm == nil || nbForm.IsDisposed
        if fresh {
            nbForm = NotebookForm(self)
            let ui = NbUi()
            var t = ""
            let okTab = ui.TryGetValue("tab", &t) && (t == "todo" || t == "done" || t == "note")
            nbForm.Tab = okTab ? t : "done"   // 第一次打開停在今天做了
            nbForm.LastTab = nbForm.Tab
            var sp = ""
            nbForm.Spread = ui.TryGetValue("spread", &sp) && sp == "1"
        }
        if tab == "todo" || tab == "done" || tab == "note" { nbForm.Tab = tab; nbForm.LastTab = tab; nbForm.Spread = false }
        nbForm.Day = NbNow().Date
        nbForm.Reload()
        NbPlace(nbForm)
        nbForm.Show()
        App.LogAlways("notebook: open tab=" + nbForm.Tab + " spread=" + (nbForm.Spread ? "1" : "0"))
        if App.Offscreen { return }
        ActivateForm(nbForm)
        nbForm.Do("focus", "")
    }

    // 停在公仔櫃左邊（櫃子收起來：小紙箱左邊），底部離工作列 8px；攤開時往左長
    func NbPlace(_ f: NotebookForm) {
        let anchor: Rectangle = shelf == nil ? RectangleT.Empty : (shelf.Collapsed ? shelf.EggScreen() : shelf.Area)
        let wa: Rectangle = anchor.IsEmpty ? screens[0].WorkingArea : Screen.FromPoint(PointT(anchor.X + anchor.Width / 2, anchor.Y + anchor.Height / 2)).WorkingArea
        let sz = f.Want
        let gap = CInt(Math.Round(Double(16 * S) / 4.0)), ov = sz.Width - f.FrameW
        let right = anchor.IsEmpty ? wa.Right - gap : anchor.X - gap
        var x = right - sz.Width
        var y = wa.Bottom - CInt(Math.Round(Double(8 * S) / 4.0)) - sz.Height
        x = Math.Max(wa.Left - ov, Math.Min(x, wa.Right - sz.Width))
        y = Math.Max(wa.Top, y)
        f.Bounds = RectangleT(x, y, sz.Width, sz.Height)
        f.Invalidate()
    }

    func NbClosed(_ f: NotebookForm) { if nbForm === f { nbForm = nil } }

    func NbUi() -> Dict<String, String> {
        let d = Dict<String, String>()
        for line in Nb.ReadFile(Path.Combine(Nb.Dir(World.DataDir), "ui.txt")).Split("\n") {
            let i = line.IndexOf("=")
            if i > 0 { d[line.Substring(0, i).Trim()] = line.Substring(i + 1).Trim() }
        }
        return d
    }
    func NbSaveUi(_ f: NotebookForm) {
        let tab: String = f.Spread ? f.LastTab : f.Tab, sp: String = f.Spread ? "1" : "0"
        Nb.WriteFile(Path.Combine(Nb.Dir(World.DataDir), "ui.txt"), "tab=" + tab + "\nspread=" + sp + "\n")
    }

    // 複製：真的剪貼簿（離屏測試只記住，不碰測試機的剪貼簿）
    func NbClipboard(_ s: String) {
        nbClip = s
        App.LogAlways("notebook: copied " + String(s.Length) + " chars")
        if App.Offscreen { return }
        Clipboard.SetText(s)   // mac: NSPasteboard，換行照 mac 用 \n（C# 換成 \r\n）；不會丟例外
    }

    // 櫃子裡的公仔冒泡泡（櫃子收起來、或大家都在外面：帶頭那隻）
    func NbSay(_ s: String) {
        var p: Pet! = nil
        if shelf != nil && !shelf.Collapsed && !Single { for x in Pets { if !x.Out { p = x; break } } }
        if p == nil { p = Lead() }
        if p == nil { return }
        nbSaid = s
        p.Say(s, 3)
    }

    // ---- 學校行事曆：今天上過的課（從 ICS 算，不寫進 log）----
    func NbFeedTexts() -> List<KeyValuePair<String, String>> {
        let l = List<KeyValuePair<String, String>>()
        if testFeeds.Count > 0 { l.AddRange(testFeeds); return l }
        var urls = List<String>()
        lock(schoolUrls) { urls = List<String>(schoolUrls.ToArray()) }
        for u in urls {
            if u == workCal { continue }
            let tx = World.ReadText(World.CacheName(u))
            if tx != "" { l.Add(KeyValuePair<String, String>(u, tx)) }
        }
        return l
    }
    func NbSchoolStamp() -> String {
        if !studyLoaded { LoadStudy() }
        let mins = CInt((NbNow() - NbNow().Date).TotalMinutes) / 5
        return String(deadlines.Count) + ":" + String(studyDone.Count) + ":" + String(testFeeds.Count) + ":" + String(mins)
    }
    func NbClasses(_ day: DateTime) -> List<NbFact> {
        let list = List<NbFact>()
        if !studyLoaded { LoadStudy() }
        let now = NbNow()
        let next = day.Date.AddDays(1)
        let from = World.UnixMs(day.Date), to = World.UnixMs(next < now ? next : now)
        if to <= from { return list }
        for kv in NbFeedTexts() {
            // mac: string.GetHashCode → hashValue（只當這次執行的快取 key）
            let key = kv.Key + "|" + String(kv.Value.Length) + "|" + String(kv.Value.hashValue)
            var feed: SchoolFeed? = nil
            if !nbFeeds.TryGetValue(key, &feed) || feed == nil {
                feed = School.Feed(kv.Key, kv.Value)   // mac: Swift 的 School.Feed 不丟例外（C# 的 try／catch 記 log 跳過）
                if nbFeeds.Count > 20 { nbFeeds.Clear() }
                nbFeeds[key] = feed!
            }
            guard let fd = feed else { continue }
            for o in Ics.Occurrences(fd.Events, from, to) {
                if o.Start < from || o.Start > to || School.Classify(o.Ev, fd, o.Parent) != "class" { continue }
                let f = NbFact()
                let one = Regex.Replace(o.Summary ?? "", #"[\r\n]+"#, " ").Trim()
                let name = Regex.Replace(one, #"\s*\[([^\]]+)\]$"#, fd.Kind == "canvas" ? "（$1）" : " [$1]")
                if name == "" { continue }
                f.Id = "class:" + (o.Uid ?? "") + "@" + String(o.Start); f.Src = "school"; f.Class = true; f.Title = name; f.Project = name
                f.T = World.FromUnixMs(o.Start); f.End = World.FromUnixMs(o.End); f.HasEnd = o.End > o.Start
                list.Add(f)
            }
        }
        return list
    }

    // ---- 待辦：自己寫的＋學校的作業（還沒交、14 天內）；新的作業放最上面（照截止時間）----
    func NbTodos() -> List<NbTodo> {
        if !studyLoaded { LoadStudy() }
        let dir = Nb.Dir(World.DataDir)
        let list = Nb.LoadTodos(dir)
        var changed = false
        var i = list.Count - 1
        while i >= 0 {
            if list[i].Src == "school" && studyDone.Contains(list[i].Ref) { list.RemoveAt(i); changed = true }   // 在別的地方標成交了
            i -= 1
        }
        let fresh = List<NbTodo>()
        for dl in deadlines {
            let dlId: String = dl.Id ?? ""
            if studyDone.Contains(dlId) { continue }
            let dd = World.FromUnixMs(dl.Due)
            let dv = Nb.DueValue(dd.Date, CInt(dd.TimeOfDay.TotalMinutes))
            var have = false
            for t in list { if t.Src == "school" && t.Ref == dlId { have = true; if t.Due != dv { t.Due = dv; changed = true } } }
            if have { continue }
            let n = NbTodo()
            let due = World.FromUnixMs(dl.Due)
            n.Id = "s" + Math.Abs(_NbNetHash(dlId)).ToString("x"); n.Src = "school"; n.Ref = dlId; n.Text = dl.Title ?? ""; n.Course = dl.Course ?? ""   // mac: string.GetHashCode → _NbNetHash（每次一樣）
            n.Due = Nb.DueValue(due.Date, CInt(due.TimeOfDay.TotalMinutes)); n.Created = Nb.Ymd(NbNow())
            fresh.Add(n)
        }
        if fresh.Count > 0 { list.InsertRange(0, fresh.ToArray()); changed = true }
        if changed { Nb.SaveTodos(dir, list) }
        return list
    }
    func NbSaveTodos(_ list: List<NbTodo>) { Nb.SaveTodos(Nb.Dir(World.DataDir), list) }

    // 學校的作業：勾掉＝交了（跟泡泡上點「交了」同一套，VS Code 也會知道）；取消勾＝還沒交
    func NbSchoolDone(_ id: String, _ done: Bool) {
        if !studyLoaded { LoadStudy() }
        if done { MarkDone(id, true); return }
        studyDone.Remove(id)
        World.WriteText("study-done.txt", string.Join("\n", studyDone.ToArray()))
        if testFeeds.Count > 0 { RescanNow() } else { replan = true }
    }
    func NbForgetSchool(_ id: String) { if !studyLoaded { LoadStudy() }; MarkDone(id, true) }

    // ---- 離屏截圖 ----
    func NbSnap(_ g: Graphics) { if nbForm != nil && !nbForm.IsDisposed && nbForm.VVisible { nbForm.PaintTo(g) } }

    // ---- pipe ----
    func NbMsg(_ c: Client, _ p: [String], _ line: String) -> Bool {
        if p.count == 0 || !p[0].StartsWith("nb-") { return false }
        let t = line.Trim()
        let f: NotebookForm? = nbForm != nil && !nbForm.IsDisposed ? nbForm : nil
        switch p[0] {
        case "nb-open": ShowNotebook(p.count >= 2 ? p[1] : "")
        case "nb-close": if let ff = f { ff.Close() }
        case "nb-info":
            let head: String = f != nil ? f!.Info() : "nb open=0\n"
            let said: String = nbSaid == "" ? "-" : nbSaid
            World.Send(c, head + "said " + said + "\nend\n")
        case "nb-clip": World.Send(c, "clip " + JavaScriptSerializer().Serialize(nbClip) + "\nend\n")
        case "nb-text":
            if let ff = f { World.Send(c, "text " + JavaScriptSerializer().Serialize(ff.CopyText(p.count >= 2 ? p[1] : "detail")) + "\nend\n") } else { World.Send(c, "text \"\"\nend\n") }
        case "nb-reload": if let ff = f { ff.Reload() }
        default:
            guard let ff = f, App.Offscreen else { break }
            switch p[0] {
            case "nb-act": if p.count >= 2 { ff.Do(p[1], p.count >= 3 ? t.Substring(World.NthSpace(t, 2) + 1) : "") }
            case "nb-click":
                var x = 0, y = 0
                if p.count >= 3 && int.TryParse(p[1], &x) && int.TryParse(p[2], &y) { ff.SimHover(PointT(x - ff.Left, y - ff.Top)); ff.SimClick(PointT(x - ff.Left, y - ff.Top)) }
            case "nb-hover":
                var x = 0, y = 0
                if p.count >= 3 && int.TryParse(p[1], &x) && int.TryParse(p[2], &y) { ff.SimHover(PointT(x - ff.Left, y - ff.Top)) }
            case "nb-hoverthing": ff.HoverThing(p.count >= 2 ? p[1] : "")
            case "nb-hovertodo": ff.HoverTodo(p.count >= 2 ? p[1] : "")
            case "nb-type": if p.count >= 2 { ff.`Type`(p[1], p.count >= 3 ? t.Substring(World.NthSpace(t, 2) + 1).Replace("\\n", "\n") : "") }
            case "nb-key":
                if p.count >= 2 && p[1] == "alt-up" { ff.Do("move", "up") }
                else if p.count >= 2 && p[1] == "alt-down" { ff.Do("move", "down") }
                else if p.count >= 3 { ff.Key(p[1], p[2]) }
            case "nb-drag": do { var to = 0; if p.count >= 3 && int.TryParse(p[2], &to) { ff.DragTo(p[1], to) } }
            case "nb-scroll": do { var dy = 0; if p.count >= 3 && int.TryParse(p[2], &dy) { ff.ScrollBy(p[1], dy) } }
            default: break
            }
        }
        return true
    }
}
