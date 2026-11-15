// 43_ui.swift — port of the last section of DeskPals.cs（公仔小屋、只要一隻、第一次設定、像素選單 PixelMenu、設定視窗 SetupForm、Pix 小工具）
import Foundation
import AppKit

// ================= 公仔小屋（蛋的右鍵）：娛樂功能開關、重新設定；只要一隻；第一次設定 =================
//@@IN World
    let feats = Dict<String, Bool>()
    // ---- 你是？（profile.txt：student｜work）、擺法（mode.txt：shelf｜single <id>）----
    var Student = false                           // 大學生（之後會有大學生的內容；現在先記著）
    var Single = false                            // 只要一隻：沒有櫃子，那隻的家是蛋，其他隻不出來
    var singleId = ""
    // ---- 設定視窗 ----
    var setupForm: SetupForm! = nil
//@@END

extension World {
    // 小屋的開關（features.txt：一行一個 key=0/1；沒寫的＝開，跟以前一樣）
    static let FeatureList: [[String]] = [
        ["scenes", "串門子劇情"],
        ["lunch", "午餐變身"],
        ["night", "下班時間（黑化／催下班）"],
        ["rollcall", "早上點名／說再見"],
        ["windows", "跟著視窗跑／跳上視窗"],
        ["season", "節日造型"],
        ["fireworks", "煙火"],
        ["chatter", "閒聊泡泡（自己閒晃時講話）"]]
    func Feat(_ key: String) -> Bool { var on = false; return !feats.TryGetValue(key, &on) || on }

    func LoadFeatures() {
        feats.Clear()
        for line in World.ReadText("features.txt").components(separatedBy: "\n") {
            let a = line.Trim().components(separatedBy: "=")
            if a.count == 2 && a[0].Trim() != "" { feats[a[0].Trim()] = a[1].Trim() != "0" }
        }
    }

    func SaveFeatures() {
        let sb = StringBuilder()
        for f in World.FeatureList { sb.Append(f[0] + "=" + (Feat(f[0]) ? "1" : "0") + "\n") }
        World.WriteText("features.txt", sb.ToString())
    }

    func SetFeat(_ key: String, _ on: Bool) {
        feats[key] = on
        SaveFeatures()
        App.Log("feature " + key + "=" + (on ? "1" : "0"))
        if key == "night" || key == "season" { nightChecked = -1; CheckNight() }   // 馬上換樣子（黑化、節日帽子）
        if key == "lunch" { LunchTick(true) }
        if key == "scenes" && !on { AbortScene() }
        var name = key
        for f in World.FeatureList { if f[0] == key { name = f[1] } }
        let cut = name.IndexOf("（")
        if cut > 0 { name = name.Substring(0, cut) }
        Lead().Say(on ? "好～「" + name + "」打開囉" : "好～「" + name + "」先關掉", 1.8)
    }

    func LoadMode() {
        Student = World.ReadText("profile.txt") == "student"
        let m = World.ReadText("mode.txt")
        Single = m.StartsWith("single")
        singleId = Single && m.Length > 6 ? m.Substring(6).Trim() : ""
    }

    // 只要一隻的那隻（換到沒有他的那一櫃：用那一櫃預設的那隻）
    func SinglePet() -> String { return Get(singleId) != nil ? singleId : defaultPet }

    // 只要一隻：點蛋＝叫他出來／回蛋裡
    func EggClick() {
        let p: Pet! = Get(SinglePet())
        if p == nil { return }
        if p.Out { if p.state != "stowfly" && p.state != "enter" && p.state != "exit" { p.StowToShelf(true) } }
        else { BringOut(p, true) }
    }

    // ---- 公仔小屋選單：開關＋小幫手＋公仔們 ----
    func HouseMenu() { HouseMenu(Cursor.Position) }
    func HouseMenu(_ at: Point) {
        let m = ContextMenuStrip()
        m.Items.Add(ToolStripLabel("開關（打勾＝開著）"))
        for f in World.FeatureList {
            let key = f[0]
            let mi = ToolStripMenuItem(f[1])
            mi.CheckOnClick = true
            mi.Checked = Feat(key)
            mi.Click = { [unowned mi] in self.SetFeat(key, !self.Feat(key)); mi.Checked = self.Feat(key) }
            m.Items.Add(mi)
        }
        m.Items.Add(ToolStripSeparator())
        let help = ToolStripMenuItem("小幫手（專注、安靜、提醒）")
        AddHelpers(help.DropDownItems)
        m.Items.Add(help)
        m.Items.Add(ToolStripSeparator())
        m.Items.Add(ToolStripLabel(Single ? "我的公仔" : "公仔們"))
        if !Single { m.Items.Add(shelf.Collapsed ? "打開公仔櫃" : "收合成蛋 🥚", nil, { self.ToggleEgg(!self.shelf.Collapsed) }) }
        m.Items.Add(Single ? "叫" + Get(SinglePet()).P.Name + "出來" : "全部出來", nil, { self.AllOut() })
        m.Items.Add(Single ? "回蛋裡" : "全部回家", nil, { self.AllHome() })
        let sw = ToolStripMenuItem("換一櫃")
        for lu in Pal.Lineups {
            let l2 = lu
            let li = ToolStripMenuItem(Pal.LineupName(lu), nil, { self.SwitchLineup(l2, self.Single ? self.singleId : "") })
            li.Checked = lu == lineup
            sw.DropDownItems.Add(li)
        }
        m.Items.Add(sw)
        m.Items.Add("重新設定…", nil, { self.ShowSetup(false) })
        m.Items.Add("讀書小幫手設定（學校行事曆、熬夜）…", nil, { self.ShowStudySettings() })
        m.Items.Add("躲起來（⌃⌥S）", nil, { self.ToggleHide() })
        m.Items.Add(ToolStripSeparator())
        m.Items.Add("收工（關掉 Desk Pals）", nil, { self.QuitAll() })
        ShowMenu(m, "公仔小屋", true, at)
    }

    // 測試用：act menu pet｜house（開在公仔／蛋旁邊，不看游標）
    func TestMenu(_ arg: String) {
        if arg == "house" {
            let e: Rectangle = shelf.Collapsed ? shelf.EggScreen() : shelf.Area
            HouseMenu(Point(e.X + e.Width / 2, e.Y + e.Height / 3))
            return
        }
        let l: Pet = Get(arg) ?? Lead()
        let m = ContextMenuStrip()
        FillMenu(l, m)
        ShowMenu(m, l.P.Name, false, Point(CInt(l.Cx), CInt(l.y)))
    }

    func ShowSetup(_ first: Bool) {
        if setupForm == nil || setupForm.IsDisposed {
            setupForm = SetupForm(self, first, World.ReadText("profile.txt"), lineup, Single, Single ? SinglePet() : "")
        }
        let wa: Rectangle = App.Offscreen ? screens[0].WorkingArea : Screen.FromPoint(Cursor.Position).WorkingArea
        setupForm.Location = Point(wa.Left + (wa.Width - setupForm.Width) / 2, wa.Top + Math.Max(0, (wa.Height - setupForm.Height) / 2))
        setupForm.Show()
        if App.Offscreen { return }
        ActivateForm(setupForm)
        let sf: SetupForm = setupForm
        Later(0.2) { if !sf.IsDisposed && sf.Visible { self.ActivateForm(sf) } }   // 再補一次，確定點得到
    }

    // 設定好了：馬上套用（不用重開）
    func ApplySetup(_ prof: String, _ lu0: String, _ single: Bool, _ pet: String, _ first: Bool) {
        World.WriteText("profile.txt", prof == "student" ? "student" : "work")
        Student = prof == "student"
        let lu = Pal.NormLineup(lu0)
        let wasSingle = Single
        Single = single
        singleId = single ? pet : ""
        World.WriteText("mode.txt", single ? "single " + pet : "shelf")
        App.Log("setup profile=" + prof + " lineup=" + lu + " mode=" + (single ? "single " + pet : "shelf"))
        if single {
            if !shelf.Collapsed { shelf.Collapsed = true; World.WriteText("shelf-state.txt", "egg") }
            if lu != lineup { SwitchLineup(lu, pet) }
            else { let p: Pet! = Get(pet); if p != nil { SelectOnly(p) } }
            let sp: Pet! = Get(SinglePet())
            if sp != nil { Later(1.6) { sp.Say("以後我住在右下角的蛋裡～點一下蛋就叫我 🥚", 3.5) } }
        }
        else {
            if lu != lineup { SwitchLineup(lu, "") }
            if shelf.Collapsed && (wasSingle || first) { shelf.Collapsed = false; World.WriteText("shelf-state.txt", "open") }
            if wasSingle || first { Later(0.6) { self.AllOut() } }
        }
        RenderShelf()
    }

    // 設定視窗用：這一櫃的櫃子縮圖（預覽用的 World 才叫這個，不開視窗）
    func SetupShelfPic() -> Bitmap {
        shelf = ShelfForm(self, S)
        shelf.Tubby = TubbyLineup; shelf.Pik = PikLineup; shelf.Orig = OrigLineup
        shelf.Night = false
        shelf.Place(Rectangle(0, 0, 2000, 2000))
        let b = shelf.Snapshot(CellPets(), [false, false, false, false], 1.0)
        return b.Clone()
    }
}

//@@IN Pet
    var muteChat = false
//@@END

extension Pet {
    // 設定視窗用：站好的樣子畫成一張小圖（預覽用的 World 才叫這個）
    func IconPic() -> Bitmap {
        let pad = 3 * S, top = P.TopRows * S
        let b = Bitmap(SW + 2 * pad, SH + top + 2 * pad, PixelFormat.Format32bppArgb)
        do {
            let g = Graphics.FromImage(b)
            g.Clear(Color.Transparent)
            Out = true; state = "idle"; anim = 0.3; t = 1; Bt = 0; dir = 1
            x = Double(pad); y = Double(pad + top)
            PaintPet(g, 0, 0)
            Out = false
        }
        return b
    }
}

// 像素風的小工具（像素選單、設定視窗共用）：方塊、缺角方塊、木框、奶油色面板、銅牌、勾勾、愛心、像素圖
enum Pix {
    static func C(_ rgb: Int) -> Color { return Color.FromArgb((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255) }
    static func Mix(_ a: Color, _ b: Color, _ f: Double) -> Color {
        return Color.FromArgb(CInt(Double(a.R) + Double(b.R - a.R) * f), CInt(Double(a.G) + Double(b.G - a.G) * f), CInt(Double(a.B) + Double(b.B - a.B) * f))
    }
    static let Ink = C(0x4A2C17), Cream = C(0xFFF6E4), TextC = C(0x4A3010), Dim = C(0xB5A089), Gold = C(0xE2B550)
    static let Mid: TextFormatFlags = [TextFormatFlags.HorizontalCenter, TextFormatFlags.VerticalCenter, TextFormatFlags.SingleLine, TextFormatFlags.NoPadding, TextFormatFlags.NoPrefix]
    static let LeftMid: TextFormatFlags = [TextFormatFlags.Left, TextFormatFlags.VerticalCenter, TextFormatFlags.SingleLine, TextFormatFlags.NoPadding, TextFormatFlags.NoPrefix]
    static let HEART: [String] = [".#.#.", "#####", ".###.", "..#.."]
    static let CHECK: [String] = ["....#", "...##", "#.##.", "###..", ".#..."]

    static func Box(_ g: Graphics, _ c: Color, _ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        if w <= 0 || h <= 0 { return }
        g.FillRectangle(SolidBrush(c), x, y, w, h)
    }
    // 像素圓角：四個角各缺一格
    static func Round(_ g: Graphics, _ c: Color, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ u: Int) {
        Box(g, c, x + u, y, w - 2 * u, h)
        Box(g, c, x, y + u, w, h - 2 * u)
    }
    static func Art(_ g: Graphics, _ art: [String], _ pal: Dict<Character, Color>, _ x: Int, _ y: Int, _ c: Int) {
        for ry in 0..<art.count {
            let row = Array(art[ry])
            for rx in 0..<row.count {
                var col = Color.Empty
                if pal.TryGetValue(row[rx], &col) { Box(g, col, x + rx * c, y + ry * c, c, c) }
            }
        }
    }
    static func Mono(_ g: Graphics, _ art: [String], _ c: Color, _ x: Int, _ y: Int, _ u: Int) {
        let pal = Dict<Character, Color>()
        pal["#"] = c
        Art(g, art, pal, x, y, u)
    }
    // 木框（跟公仔櫃同一套木頭色）：深色外框、亮的上緣、暗的下緣、木紋、四角小釘子
    static func Wood(_ g: Graphics, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ u: Int, _ night: Bool, _ seed: Int) {
        let wl = night ? C(0x74503A) : C(0xB97F4E), wm = night ? C(0x5C3B24) : C(0x9A6338), wd = night ? C(0x3C2617) : C(0x6B4024)
        Round(g, Ink, x, y, w, h, u)
        Box(g, wm, x + u, y + u, w - 2 * u, h - 2 * u)
        Box(g, wl, x + 2 * u, y + u, w - 4 * u, u)
        Box(g, wd, x + 2 * u, y + h - 2 * u, w - 4 * u, u)
        let r = Random(seed)
        let grain = Mix(wm, wd, 0.45)
        let gh = Math.Max(1, u / 2), n = 10 + w * h / (40 * 40)
        var i = 0
        while i < n {
            let gx = x + 2 * u + r.Next(Math.Max(1, w - 10 * u)), gy = y + 2 * u + r.Next(Math.Max(1, h - 4 * u))
            Box(g, grain, gx, gy, 3 * u + r.Next(5 * u), gh)
            i += 1
        }
        let nail = night ? C(0xB08A3C) : Gold
        Box(g, nail, x + 2 * u, y + 2 * u, u, u); Box(g, nail, x + w - 3 * u, y + 2 * u, u, u)
        Box(g, nail, x + 2 * u, y + h - 3 * u, u, u); Box(g, nail, x + w - 3 * u, y + h - 3 * u, u, u)
    }
    // 奶油色面板：凹進去（外圈深木色、上面和左邊一條陰影）
    static func Panel(_ g: Graphics, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ u: Int, _ night: Bool) {
        Box(g, night ? C(0x3C2617) : C(0x6B4024), x - u, y - u, w + 2 * u, h + 2 * u)
        Box(g, Cream, x, y, w, h)
        Box(g, C(0xEAD7B4), x, y, w, u)
        Box(g, C(0xF3E6CC), x, y + u, u, h - u)
    }
    // 銅牌（跟櫃子的名牌一樣）
    static func Plate(_ g: Graphics, _ s: String, _ f: Font, _ r: Rectangle, _ u: Int) {
        Round(g, Ink, r.X, r.Y, r.Width, r.Height, u)
        Box(g, C(0xEBC56A), r.X + u, r.Y + u, r.Width - 2 * u, r.Height - 2 * u)
        Box(g, C(0xF8DE8E), r.X + 2 * u, r.Y + u, r.Width - 4 * u, u)
        Box(g, C(0xC08A2C), r.X + 2 * u, r.Bottom - 2 * u, r.Width - 4 * u, u)
        Box(g, C(0x8A5A2A), r.X + 2 * u, r.Y + r.Height / 2 - u / 2, u, u)
        Box(g, C(0x8A5A2A), r.Right - 3 * u, r.Y + r.Height / 2 - u / 2, u, u)
        TextRenderer.DrawText(g, s, f, Rectangle(r.X, r.Y, r.Width, r.Height - u / 2), TextC, Mid)
    }
    static func TextW(_ s: String, _ f: Font) -> Int { return TextRenderer.MeasureText(s, f, SizeT(4000, 400), [TextFormatFlags.NoPadding, TextFormatFlags.SingleLine, TextFormatFlags.NoPrefix]).Width }
}

// ================= 像素選單（取代原生右鍵選單）=================
// 木框＋奶油色面板（跟公仔櫃同一套顏色）；小屋的選單上面是屋頂和煙囪、下面有門和窗。
// 內容照樣用 ToolStrip 項目寫：ToolStripLabel＝小標題、子選單原地展開、CheckOnClick（開關）按了不關選單。
// 可以變成前景（收得到 Esc、失去焦點就關）；點到外面由 World 的計時器看滑鼠按鍵來關。
class PixelMenu: OverlayForm {
    final class Row { var It: ToolStripItem! = nil; var Depth = 0, Y = 0, H = 0; var Header = false, Sep = false, Sub = false, Check = false }
    let w: World
    let menu: ContextMenuStrip
    let title: String
    let House: Bool
    let rows = List<Row>()
    let opened = List<ToolStripItem>()
    var font: FontT! = nil, small: FontT! = nil, titleFont: FontT! = nil
    let U: Int, F: Int, rowH: Int
    let night: Bool
    var topH = 0, botH = 0, smokeH = 0, roofH = 0, wallX = 0, hover = -1
    var anyCheck = false, up = false
    var anchor = Point(0, 0)
    var Done = false, Armed = false

    init(_ w: World, _ menu: ContextMenuStrip, _ title: String?, _ house: Bool) {
        self.w = w; self.menu = menu; self.title = title ?? ""; House = house
        let d = Double(w.S) / 4.0
        U = Math.Max(2, CInt(Math.Round(2 * d)))
        F = 4 * U
        rowH = Math.Max(22, CInt(Math.Round(25 * d)))
        night = w.Night
        super.init(false)
        font = FontT("Microsoft JhengHei UI", 10, FontStyle.Bold)
        small = FontT("Microsoft JhengHei UI", 8.5, FontStyle.Bold)
        titleFont = FontT("Microsoft JhengHei UI", house ? 11 : 10, FontStyle.Bold)
        KeyPreview = true
        Deactivate = { [unowned self] in self.CloseMenu() }
    }

    // 跟其他小視窗不一樣：要能變成前景（收 Esc、失去焦點時關掉）
    override var ShowWithoutActivation: Bool { return false }
    // mac: 取代 CreateParams 拿掉 WS_EX_NOACTIVATE → 不搶前景、但可以拿鍵盤焦點的面板；放在選單那一層（蓋過公仔、櫃子）
    override var _overlayKeyable: Bool { return true }
    override var _overlayLevel: NSWindow.Level { return .popUpMenu }

    func Popup(_ at: Point) { anchor = at; Reflow(true); Show() }

    func BuildRows() {
        rows.Clear()
        anyCheck = false
        AddRows(menu.Items, 0)
        // 頭尾、連在一起的分隔線拿掉
        var i = rows.Count - 1
        while i >= 0 {
            if i < rows.Count && rows[i].Sep && (i == 0 || i == rows.Count - 1 || rows[i - 1].Sep) { rows.RemoveAt(i) }
            i -= 1
        }
    }

    func AddRows(_ items: ToolStripItemCollection, _ depth: Int) {
        for it in items {
            if !it.Available { continue }
            let r = Row()
            r.It = it; r.Depth = depth
            let mi = it as? ToolStripMenuItem
            if it is ToolStripSeparator { r.Sep = true; r.H = 3 * U }
            else if it is ToolStripLabel { r.Header = true; r.H = rowH * 4 / 5 }
            else {
                r.H = rowH
                r.Sub = mi != nil && mi!.DropDownItems.Count > 0
                r.Check = mi != nil && (mi!.Checked || mi!.CheckOnClick)
                if r.Check { anyCheck = true }
            }
            rows.Add(r)
            if r.Sub && opened.Exists({ $0 === it }) { AddRows(mi!.DropDownItems, depth + 1) }
        }
    }

    func RowText(_ r: Row) -> String { return World.NoEmoji(r.It.Text) }

    // 算大小、擺位置：開在游標右下，放不下就往左／往上（子選單展開時往上開的就往上長）
    func Reflow(_ place: Bool) {
        BuildRows()
        var inner = 0
        for r in rows {
            if r.Sep { continue }
            var tw = Pix.TextW(RowText(r), r.Header ? small : font) + r.Depth * 5 * U
            if r.Header { tw += 10 * U } else { if anyCheck { tw += 9 * U }; tw += 8 * U }
            inner = Math.Max(inner, tw)
        }
        let tTitle = title == "" ? 0 : Pix.TextW(title, titleFont)
        if House {
            smokeH = 10 * U; roofH = 22 * U
            wallX = 4 * U
            topH = smokeH + roofH + 3 * U
            botH = 22 * U
            inner = Math.Max(inner, tTitle + 16 * U)
        }
        else {
            smokeH = 0; roofH = 0; wallX = 0
            topH = title == "" ? F : rowH + 5 * U
            botH = F
            inner = Math.Max(inner, tTitle + 14 * U)
        }
        let wd = Math.Max(CInt(180.0 * Double(w.S) / 4.0), inner + 2 * (F + 3 * U + wallX))
        var y = topH + U
        for r in rows { r.Y = y; y += r.H }
        let ht = y + U + botH
        let wa = Screen.FromPoint(anchor).WorkingArea
        var x: Int, yy: Int
        if place {
            x = anchor.X + 2; yy = anchor.Y + 2; up = false
            if x + wd > wa.Right { x = anchor.X - wd - 2 }
            if yy + ht > wa.Bottom { yy = anchor.Y - ht - 2; up = true }
        }
        else { x = Left; yy = up ? Bottom - ht : Top }
        x = Math.Max(wa.Left, Math.Min(x, wa.Right - wd))
        yy = Math.Max(wa.Top, Math.Min(yy, wa.Bottom - ht))
        Bounds = Rectangle(x, yy, wd, ht)
        Invalidate()
    }

    func Selectable(_ i: Int) -> Bool { let r = rows[i]; return !r.Sep && !r.Header && r.It.Enabled }

    func RowAt(_ p: Point) -> Int {
        let px = wallX + F
        if p.X < px || p.X >= ClientSize.Width - px { return -1 }
        for i in 0..<rows.Count {
            if p.Y >= rows[i].Y && p.Y < rows[i].Y + rows[i].H { return Selectable(i) ? i : -1 }
        }
        return -1
    }

    func SetHover(_ i: Int) { hover = i >= 0 && i < rows.Count && Selectable(i) ? i : -1; Invalidate() }

    func MoveHover(_ dir: Int) {
        let n = rows.Count
        var i = hover
        var j = 0
        while j < n {
            i = i < 0 ? (dir > 0 ? 0 : n - 1) : (i + dir + n) % n
            if Selectable(i) { hover = i; Invalidate(); return }
            j += 1
        }
    }

    // 按下一列：子選單＝展開／收起來；開關＝打勾換一下（選單不關）；其他＝關掉選單再做
    func Pick(_ i: Int) {
        if Done || i < 0 || i >= rows.Count || !Selectable(i) { return }
        let r = rows[i]
        let mi = r.It as? ToolStripMenuItem
        if r.Sub {
            let open = opened.Exists({ $0 === r.It })
            var j = opened.Count - 1
            while j >= 0 { if DepthOf(opened[j]) >= r.Depth { opened.RemoveAt(j) }; j -= 1 }   // 同一層只開一個
            if !open { opened.Add(r.It) }
            let keep: ToolStripItem = r.It
            Reflow(false)
            hover = -1
            for j2 in 0..<rows.Count { if rows[j2].It === keep { hover = j2 } }
            return
        }
        if mi != nil && mi!.CheckOnClick { mi!.PerformClick(); Invalidate(); return }
        let pick: ToolStripItem = r.It
        App.LogAlways("menu: picked \"" + pick.Text + "\"")
        CloseMenu()
        w.BeginInvoke { pick.PerformClick() }   // 等選單關掉再做（開輸入框才拿得到焦點）
    }

    func DepthOf(_ it: ToolStripItem) -> Int { for r in rows { if r.It === it { return r.Depth } }; return 0 }

    func CloseMenu() {
        if Done { return }
        Done = true
        App.LogAlways("menu: closed")
        w.MenuClosed(self)
        Hide()
        w.BeginInvoke { self.Close() }
    }

    override func OnKeyDown(_ e: KeyEventArgs) {
        super.OnKeyDown(e)
        if e.KeyCode == Keys.Escape { CloseMenu(); e.Handled = true }
        else if e.KeyCode == Keys.Down || e.KeyCode == Keys.Up { MoveHover(e.KeyCode == Keys.Down ? 1 : -1); e.Handled = true }
        else if e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space { if hover >= 0 { Pick(hover) }; e.Handled = true }
    }
    override func OnMouseMove(_ e: MouseEventArgs) {
        super.OnMouseMove(e)
        let h = RowAt(e.Location)
        if h != hover { hover = h; Invalidate() }
    }
    override func OnMouseLeave(_ e: EventArgs) { super.OnMouseLeave(e); if hover != -1 { hover = -1; Invalidate() } }
    override func OnMouseUp(_ e: MouseEventArgs) {
        super.OnMouseUp(e)
        if e.Button != MouseButtons.Left && e.Button != MouseButtons.Right { return }
        let i = RowAt(e.Location)
        if i >= 0 { Pick(i) }
    }

    override func OnPaint(_ e: PaintEventArgs) {
        let g = e.Graphics
        g.Clear(KEY)
        g.SmoothingMode = SmoothingMode.None
        let W0 = ClientSize.Width, H0 = ClientSize.Height
        let bodyY = House ? smokeH + roofH - U : 0, bodyH = H0 - bodyY - (House ? 2 * U : 0)
        Pix.Wood(g, wallX, bodyY, W0 - 2 * wallX, bodyH, U, night, 7)
        let px = wallX + F, pw = W0 - 2 * px, ph = H0 - topH - botH
        Pix.Panel(g, px, topH, pw, ph, U, night)
        if House { PaintHouse(g, W0, H0) }
        else if title != "" {
            let tw = Pix.TextW(title, titleFont), plw = Math.Min(pw, tw + 12 * U), plh = rowH
            Pix.Plate(g, title, titleFont, Rectangle((W0 - plw) / 2, (topH - plh) / 2 + U / 2, plw, plh), U)
        }
        for i in 0..<rows.Count { PaintRow(g, i, px, pw) }
    }

    func PaintRow(_ g: Graphics, _ i: Int, _ px: Int, _ pw: Int) {
        let r = rows[i]
        let x = px + 3 * U + r.Depth * 5 * U, right = px + pw - 3 * U
        if r.Depth > 0 { Pix.Box(g, Pix.C(0xF7EBD2), px + U, r.Y, pw - U, r.H) }     // 展開的子選單：底色淡一點
        if r.Sep {
            let sy = r.Y + r.H / 2 - U / 2
            var sx = px + 2 * U
            while sx + U <= px + pw - 2 * U { Pix.Box(g, Pix.C(0xD8BF94), sx, sy, U, U); sx += 2 * U }
            return
        }
        if r.Header {
            let s = RowText(r)
            let cy = r.Y + r.H / 2, tw = Pix.TextW(s, small)
            Pix.Box(g, Pix.Gold, x + U, cy - U - U / 2, U, 3 * U); Pix.Box(g, Pix.Gold, x, cy - U / 2, 3 * U, U)   // 小星星
            TextRenderer.DrawText(g, s, small, Rectangle(x + 4 * U, r.Y, tw + 4, r.H), night ? Pix.C(0x8A5A2A) : Pix.C(0x9A6338), Pix.LeftMid)
            var sx = x + 6 * U + tw
            while sx + U <= right { Pix.Box(g, Pix.C(0xE4D0AC), sx, cy, U, U); sx += 2 * U }
            return
        }
        let en = r.It.Enabled, hot = i == hover && en
        if hot {
            Pix.Round(g, Pix.C(0xD9A944), px + U, r.Y + 1, pw - 2 * U, r.H - 2, U)
            Pix.Box(g, Pix.C(0xFFE29A), px + 2 * U, r.Y + 1 + U, pw - 4 * U, r.H - 2 - 2 * U)
            Pix.Box(g, Pix.C(0xFFF1C9), px + 3 * U, r.Y + 1 + U, pw - 6 * U, Math.Max(1, U / 2))
        }
        var tx = x
        let mi = r.It as? ToolStripMenuItem
        if anyCheck {
            if r.Check && mi != nil {
                let s = 7 * U, cy = r.Y + (r.H - s) / 2
                if mi!.CheckOnClick {
                    Pix.Round(g, Pix.C(0x9A6338), tx, cy, s, s, U)
                    Pix.Box(g, mi!.Checked ? Pix.C(0xDDF2C8) : Pix.C(0xFFFDF7), tx + U, cy + U, s - 2 * U, s - 2 * U)
                }
                if mi!.Checked { Pix.Mono(g, Pix.CHECK, Pix.C(0x3F8A30), tx + U, cy + U, U) }
            }
            tx += 9 * U
        }
        TextRenderer.DrawText(g, RowText(r), font, Rectangle(tx, r.Y, Math.Max(1, right - tx), r.H), en ? Pix.TextC : Pix.Dim, Pix.LeftMid)
        if r.Sub { PaintArrow(g, right - 2 * U, r.Y + r.H / 2, opened.Exists({ $0 === r.It }), hot ? Pix.C(0x8A5A2A) : Pix.C(0xB08A5A)) }
        else if hot { Pix.Mono(g, Pix.HEART, Pix.C(0xE8607A), right - 5 * U, r.Y + r.H / 2 - 2 * U, U) }
    }

    // ▶（收著）／▼（展開了）
    func PaintArrow(_ g: Graphics, _ cx: Int, _ cy: Int, _ open: Bool, _ c: Color) {
        if open { Pix.Box(g, c, cx - 2 * U, cy - U, 5 * U, U); Pix.Box(g, c, cx - U, cy, 3 * U, U); Pix.Box(g, c, cx, cy + U, U, U) }
        else { Pix.Box(g, c, cx - U, cy - 2 * U, U, 5 * U); Pix.Box(g, c, cx, cy - U, U, 3 * U); Pix.Box(g, c, cx + U, cy, U, U) }
    }

    // 小屋：煙囪冒煙、一階一階的屋頂（名字寫在屋頂上）、下面一排窗戶和愛心門、草地
    func PaintHouse(_ g: Graphics, _ W0: Int, _ H0: Int) {
        let ink = Pix.Ink
        let roofBot = smokeH + roofH, rh = 2 * U, n = roofH / rh
        let half = W0 / 2, ridge = Math.Max(10 * U, W0 / 7)
        let step = Math.Max(U, (half - U - ridge) / n / U * U)
        // 煙囪（屋頂蓋住下半截）＋煙
        let cw = 5 * U, cx = W0 - W0 / 4 - cw / 2, capY = smokeH - 2 * U
        Pix.Box(g, ink, cx - 2 * U, capY - U, cw + 4 * U, 4 * U)
        Pix.Box(g, ink, cx - U, capY, cw + 2 * U, roofBot - capY)
        Pix.Box(g, night ? Pix.C(0x8E4A35) : Pix.C(0xC0603F), cx, capY + 2 * U, cw, roofBot - capY - 2 * U)
        Pix.Box(g, night ? Pix.C(0x5E2E22) : Pix.C(0x7A3B28), cx - U, capY, cw + 2 * U, 2 * U)
        Pix.Box(g, night ? Pix.C(0x6E3628) : Pix.C(0x9A4A32), cx + U, capY + 4 * U, 2 * U, U / 2 + 1)
        let sm = night ? Pix.C(0xB8B2C8) : Pix.C(0xF4F0EA), se = night ? Pix.C(0x7C7690) : Pix.C(0xC8BFB4)
        Puff(g, cx + cw / 2 + U, capY - 3 * U, 2 * U, sm, se)
        Puff(g, cx + cw + 3 * U, capY - 6 * U, 2 * U, sm, se)
        // 屋頂：先畫深色外框（每一階往外一格），再一排一排畫瓦片
        for i in 0..<n {
            let x0 = U + i * step, x1 = W0 - U - i * step, y0 = roofBot - (i + 1) * rh
            Pix.Box(g, ink, x0 - U, y0 - U, x1 - x0 + 2 * U, rh + 2 * U)
        }
        let t1 = night ? Pix.C(0x9A4636) : Pix.C(0xD0583F), t2 = night ? Pix.C(0x873B2E) : Pix.C(0xB8472F), tk = night ? Pix.C(0x5E2A22) : Pix.C(0x8E3424), hi = night ? Pix.C(0xB86A55) : Pix.C(0xF08A68)
        for i in 0..<n {
            let x0 = U + i * step, x1 = W0 - U - i * step, y0 = roofBot - (i + 1) * rh
            Pix.Box(g, i % 2 == 0 ? t1 : t2, x0, y0, x1 - x0, rh)
            var tx = x0 + (i % 2) * 2 * U + 3 * U
            while tx < x1 - U { Pix.Box(g, tk, tx, y0 + U, U, U); tx += 4 * U }
            Pix.Box(g, hi, x0, y0, x1 - x0, Math.Max(1, U / 2))
        }
        Pix.Box(g, ink, wallX, roofBot, W0 - 2 * wallX, U)   // 屋簷下的陰影
        // 屋頂上的小圓窗
        let aw = 6 * U, ax = (W0 - aw) / 2, ay = smokeH + roofH / 6
        Pix.Round(g, ink, ax, ay, aw, aw, U)
        Pix.Box(g, night ? Pix.C(0xFFD36A) : Pix.C(0xFFF3DA), ax + U, ay + U, aw - 2 * U, aw - 2 * U)
        Pix.Box(g, ink, ax + aw / 2 - U / 2, ay + U, U, aw - 2 * U)
        Pix.Box(g, ink, ax + U, ay + aw / 2 - U / 2, aw - 2 * U, U)
        // 名字寫在屋頂上（深色描邊＋奶油色字）
        if title != "" {
            let tr = Rectangle(0, smokeH + roofH * 2 / 5, W0, roofH * 3 / 5 - U)
            let sh = night ? Pix.C(0x3A1A12) : Pix.C(0x5E2418)
            TextRenderer.DrawText(g, title, titleFont, Rectangle(tr.X + 1, tr.Y + 1, tr.Width, tr.Height), sh, Pix.Mid)
            TextRenderer.DrawText(g, title, titleFont, Rectangle(tr.X - 1, tr.Y + 1, tr.Width, tr.Height), sh, Pix.Mid)
            TextRenderer.DrawText(g, title, titleFont, Rectangle(tr.X, tr.Y + 2, tr.Width, tr.Height), sh, Pix.Mid)
            TextRenderer.DrawText(g, title, titleFont, tr, Pix.C(0xFFF3DA), Pix.Mid)
        }
        // 窗戶（白天淡藍、晚上亮黃燈）＋花台
        let ww = 7 * U, wy = H0 - botH + 5 * U
        let wxs: [Int] = [W0 / 4 - ww / 2 - U, W0 - W0 / 4 - ww / 2 + U]
        for wx in wxs {
            Pix.Round(g, ink, wx, wy, ww, ww, U)
            Pix.Box(g, night ? Pix.C(0xFFD36A) : Pix.C(0xBFE3F2), wx + U, wy + U, ww - 2 * U, ww - 2 * U)
            Pix.Box(g, night ? Pix.C(0xFFF0B0) : Color.White, wx + U, wy + U, U, U)
            Pix.Box(g, ink, wx + 3 * U, wy + U, U, ww - 2 * U)
            Pix.Box(g, ink, wx + U, wy + 3 * U, ww - 2 * U, U)
            Pix.Box(g, ink, wx - U, wy + ww, ww + 2 * U, 2 * U)
            Pix.Box(g, Pix.C(0x8E5A34), wx, wy + ww, ww, U)
            Pix.Box(g, Pix.C(0xE8607A), wx + U, wy + ww - U, U, U)
            Pix.Box(g, Pix.C(0xFFD84A), wx + 3 * U, wy + ww - U, U, U)
            Pix.Box(g, Pix.C(0xE8607A), wx + 5 * U, wy + ww - U, U, U)
            Pix.Box(g, Pix.C(0x5AA040), wx + 2 * U, wy + ww - U, U, U)
            Pix.Box(g, Pix.C(0x5AA040), wx + 4 * U, wy + ww - U, U, U)
        }
        // 門：圓頂、木板、愛心小窗、門把、門前一塊石板
        let dw = 9 * U, dh = 14 * U, dx = (W0 - dw) / 2, dy = H0 - 2 * U - dh
        Pix.Box(g, ink, dx, dy + 2 * U, dw, dh - 2 * U); Pix.Box(g, ink, dx + U, dy + U, dw - 2 * U, U); Pix.Box(g, ink, dx + 2 * U, dy, dw - 4 * U, U)
        let door = night ? Pix.C(0x7A4A2A) : Pix.C(0xA8693C), plank = night ? Pix.C(0x5E3820) : Pix.C(0x8A5530)
        Pix.Box(g, door, dx + U, dy + 2 * U, dw - 2 * U, dh - 2 * U); Pix.Box(g, door, dx + 2 * U, dy + U, dw - 4 * U, U)
        Pix.Box(g, plank, dx + 3 * U, dy + 7 * U, Math.Max(1, U / 2), dh - 7 * U)
        Pix.Box(g, plank, dx + 6 * U, dy + 7 * U, Math.Max(1, U / 2), dh - 7 * U)
        Pix.Mono(g, Pix.HEART, night ? Pix.C(0xFFD36A) : Pix.C(0xF27A90), dx + 2 * U, dy + 2 * U, U)
        Pix.Box(g, Pix.Gold, dx + dw - 3 * U, dy + 8 * U, U, U)
        // 草地
        let grass = night ? Pix.C(0x4E7A44) : Pix.C(0x7CC45A), grassD = night ? Pix.C(0x3A5C36) : Pix.C(0x5AA040)
        Pix.Box(g, grass, U, H0 - 2 * U, W0 - 2 * U, 2 * U)
        Pix.Box(g, grassD, U, H0 - U, W0 - 2 * U, U)
        var gx = 2 * U
        while gx < W0 - 2 * U { if gx + U < dx - U || gx > dx + dw + U { Pix.Box(g, grassD, gx, H0 - 3 * U, U, U) }; gx += 5 * U }
        Pix.Box(g, night ? Pix.C(0x8A8278) : Pix.C(0xC9BFB3), dx - U, H0 - 2 * U, dw + 2 * U, U)
    }

    func Puff(_ g: Graphics, _ cx: Int, _ cy: Int, _ r: Int, _ fill: Color, _ edge: Color) {
        Pix.Box(g, edge, cx - r - U, cy - r, 2 * r + 2 * U, 2 * r)
        Pix.Box(g, edge, cx - r, cy - r - U, 2 * r, 2 * r + 2 * U)
        Pix.Box(g, fill, cx - r, cy - r, 2 * r, 2 * r)
        Pix.Box(g, Color.White, cx - r + U / 2, cy - r + U / 2, U, U)
    }
}

// ================= 設定視窗（第一次打開、小屋 → 重新設定）=================
// 一個視窗、三步：你是？→ 選一櫃 → 怎麼擺（整櫃／只要一隻）。全部自己畫（木框＋大按鈕），點哪裡自己算。
// mac: FormBorderStyle 不是 None → shim 的對話框（有標題列、不搶前景但拿得到鍵盤和滑鼠）
class SetupForm: Form {
    final class Btn { var Id = "", Text = "", Sub = ""; var R = Rectangle(0, 0, 0, 0); var Kind = 0; var On = false, Enabled = true }   // Kind：0 大卡片 1 公仔小卡 2 普通按鈕 3 主要按鈕
    let w: World
    let first: Bool
    let d: Double
    let U: Int
    var step = 0
    var prof: String, lu: String, mode: String, pet: String
    let btns = List<Btn>()
    var hoverId = ""
    var titleF: FontT! = nil, qF: FontT! = nil, bigF: FontT! = nil, subF: FontT! = nil, btnF: FontT! = nil
    let shelfPics = Dict<String, Bitmap>()
    let petPics = Dict<String, Bitmap>()
    var VVisible = false

    static let STUDENT: [String] = [
        "......kkkk......",
        "....kkddddkk....",
        "..kkddddddddkk..",
        "kkddddddddddddkk",
        "..kkddddddddkkY.",
        "....kkddddkk..Y.",
        "....kDDDDDDk..Y.",
        "....kDDDDDDk.YYY",
        "....kkkkkkkk.YYY",
        "................",
        "kkkkkkk..kkkkkkk",
        "kwwwwwwkkwwwwwwk",
        "kwlllwwkkwlllwwk",
        "kwwwwwwkkwwwwwwk",
        "kwllwwwkkwllwwwk",
        "kkkkkkkkkkkkkkkk"]
    static let WORK: [String] = [
        "................",
        ".....kkkkkk.....",
        "....kk....kk....",
        "....k......k....",
        ".kkkkkkkkkkkkkk.",
        "kBBBBBBBBBBBBBBk",
        "kbbbbbbbbbbbbbbk",
        "kbbbbbbYYbbbbbbk",
        "kkkkkkkYYkkkkkkk",
        "kbbbbbbbbbbbbbbk",
        "kbbbbbbbbbbbbbbk",
        "kbbbbbbbbbbbbbbk",
        "kbbbbbbbbbbbbbbk",
        "kssssssssssssssk",
        ".kkkkkkkkkkkkkk.",
        "................"]

    init(_ w: World, _ first: Bool, _ prof: String, _ lu: String, _ single: Bool, _ pet: String?) {
        self.w = w; self.first = first
        self.prof = prof == "student" || prof == "work" ? prof : ""
        self.lu = Pal.NormLineup(lu)
        mode = single ? "single" : "shelf"
        self.pet = pet ?? ""
        d = Double(w.S) / 4.0
        U = Math.Max(2, CInt(Math.Round(2 * d)))
        super.init()
        Text = first ? "歡迎來到公仔櫃" : "公仔櫃・重新設定"
        FormBorderStyle = FormBorderStyleT.FixedSingle
        MaximizeBox = false; MinimizeBox = false
        ShowInTaskbar = true; TopMost = true
        StartPosition = FormStartPosition.Manual
        BackColor = Pix.Cream
        DoubleBuffered = true
        titleF = FontT("Microsoft JhengHei UI", 12, FontStyle.Bold)
        qF = FontT("Microsoft JhengHei UI", 15, FontStyle.Bold)
        bigF = FontT("Microsoft JhengHei UI", 13, FontStyle.Bold)
        subF = FontT("Microsoft JhengHei UI", 9, FontStyle.Bold)
        btnF = FontT("Microsoft JhengHei UI", 11, FontStyle.Bold)
        ClientSize = SizeT(Sc(580), Sc(520))
        KeyPreview = true
        KeyDown = { [unowned self] (e: KeyEventArgs) in if e.KeyCode == Keys.Escape { self.Close() } }
        LayoutBtns()
    }

    func Sc(_ v: Int) -> Int { return CInt(Math.Round(Double(v) * d)) }

    // ---- 離屏測試模式：不真的顯示，snap 時畫到虛擬螢幕上 ----
    override func SetVisibleCore(_ value: Bool) {
        if App.Offscreen { VVisible = value; super.SetVisibleCore(false); return }
        super.SetVisibleCore(value)
    }
    func PaintTo(_ g: Graphics) {
        let cs = ClientSize
        if cs.Width <= 0 || cs.Height <= 0 { return }
        let b = Bitmap(cs.Width, cs.Height, PixelFormat.Format24bppRgb)
        do { let gg = Graphics.FromImage(b); OnPaint(PaintEventArgs(gg, Rectangle(0, 0, cs.Width, cs.Height))) }
        g.DrawImageUnscaled(b, Left, Top)
    }

    func InLineup(_ id: String) -> Bool { for x in Pal.LineupIds(lu) { if x == id { return true } }; return false }
    static func Members(_ id: String) -> String {
        var names: [String] = []
        for x in Pal.LineupIds(id) { names.append(Pal.Get(x).Name) }
        if Pal.NormLineup(id) == Pal.Pikmin { names.append("休息花") }
        return names.joined(separator: "・")
    }
    func CanNext() -> Bool { return step == 0 ? prof != "" : (step == 1 || mode == "shelf" || InLineup(pet)) }

    @discardableResult func Add(_ id: String, _ text: String, _ sub: String, _ r: Rectangle, _ kind: Int, _ on: Bool) -> Btn {
        let b = Btn()
        b.Id = id; b.Text = text; b.Sub = sub; b.R = r; b.Kind = kind; b.On = on
        btns.Add(b)
        return b
    }

    // 這一步有哪些按鈕、擺在哪
    func LayoutBtns() {
        btns.Clear()
        let W0 = ClientSize.Width, H0 = ClientSize.Height, top = Sc(154), bottom = H0 - Sc(72)
        if step == 0 {
            let cw = Sc(220), ch = Sc(230), gap = Sc(28), x0 = (W0 - 2 * cw - gap) / 2
            Add("student", "大學生", "上課・報告・期末考", Rectangle(x0, top, cw, ch), 0, prof == "student")
            Add("work", "上班族", "上班・開會・準時下班", Rectangle(x0 + cw + gap, top, cw, ch), 0, prof == "work")
        }
        else if step == 1 {
            let n = Pal.Lineups.count, gap = Sc(24), cw = Math.Min(Sc(240), (W0 - Sc(48) - (n - 1) * gap) / n), ch = bottom - top - Sc(8)
            let x0 = (W0 - n * cw - (n - 1) * gap) / 2
            for i in 0..<n {
                let id = Pal.Lineups[i]
                EnsurePics(id)
                Add("lu:" + id, Pal.LineupName(id), SetupForm.Members(id), Rectangle(x0 + i * (cw + gap), top, cw, ch), 0, lu == id)
            }
        }
        else {
            EnsurePics(lu)
            let cw = Sc(230), ch = Sc(116), gap = Sc(24), x0 = (W0 - 2 * cw - gap) / 2
            Add("mode:shelf", lu == Pal.Pikmin ? "整櫃（三隻）" : "整櫃（四隻）", lu == Pal.Pikmin ? "三隻＋一朵休息花" : "四隻住在公仔櫃裡", Rectangle(x0, top, cw, ch), 0, mode == "shelf")
            Add("mode:single", "只要一隻", "沒有櫃子，他住在蛋裡", Rectangle(x0 + cw + gap, top, cw, ch), 0, mode == "single")
            if mode == "single" {
                let ids = Pal.LineupIds(lu)
                let pw = Sc(100), pg = Sc(14), px0 = (W0 - ids.count * pw - (ids.count - 1) * pg) / 2, py = top + ch + Sc(34)
                for i in 0..<ids.count {
                    Add("pet:" + ids[i], Pal.Get(ids[i]).Name, "", Rectangle(px0 + i * (pw + pg), py, pw, Math.Min(Sc(118), bottom - py - Sc(4))), 1, pet == ids[i])
                }
            }
        }
        let by = H0 - Sc(64), bh = Sc(44)
        if step > 0 { Add("back", "上一步", "", Rectangle(Sc(30), by, Sc(130), bh), 2, false) }
        else if first { Add("skip", "以後再說", "", Rectangle(Sc(30), by, Sc(130), bh), 2, false) }
        let nx = Add("next", step < 2 ? "下一步" : "完成！", "", Rectangle(W0 - Sc(30) - Sc(160), by, Sc(160), bh), 3, false)
        nx.Enabled = CanNext()
    }

    // 每一櫃：櫃子縮圖、每一隻的小照片（用預覽用的 World 畫，不開視窗）
    func EnsurePics(_ id: String) {
        if shelfPics.ContainsKey(id) { return }
        let pv = World(Math.Max(3, CInt(Math.Round(3 * d))), id)
        shelfPics[id] = pv.SetupShelfPic()
        for p in pv.Pets { petPics[id + ":" + p.P.Id] = p.IconPic() }
    }

    func Find(_ id: String) -> Btn? { for b in btns { if b.Id == id { return b } }; return nil }
    func At(_ p: Point) -> Btn? { for b in btns { if b.R.Contains(p) { return b } }; return nil }

    // 按按鈕（滑鼠、測試用的 act setup <按鈕> 都走這裡）
    func Press(_ id: String) {
        let b = Find(id)
        if b != nil && !b!.Enabled { return }
        if id == "student" || id == "work" { prof = id }
        else if id.StartsWith("lu:") { lu = Pal.NormLineup(id.Substring(3)); if !InLineup(pet) { pet = "" } }
        else if id == "mode:shelf" { mode = "shelf" }
        else if id == "mode:single" { mode = "single"; if !InLineup(pet) { pet = Pal.LineupIds(lu)[0] } }
        else if id.StartsWith("pet:") { pet = id.Substring(4); mode = "single" }
        else if id == "back" { if step > 0 { step -= 1 } }
        else if id == "next" { if step < 2 { step += 1 } else { w.ApplySetup(prof, lu, mode == "single", pet, first); Close(); return } }
        else if id == "skip" || id == "close" { Close(); return }
        else { return }
        LayoutBtns()
        hoverId = ""
        Invalidate()
    }

    override func OnMouseMove(_ e: MouseEventArgs) {
        super.OnMouseMove(e)
        let b = At(e.Location)
        let h = b != nil && b!.Enabled ? b!.Id : ""
        if h != hoverId { hoverId = h; Cursor = h != "" ? Cursors.Hand : Cursors.Default; Invalidate() }
    }
    override func OnMouseLeave(_ e: EventArgs) { super.OnMouseLeave(e); if hoverId != "" { hoverId = ""; Invalidate() } }
    override func OnMouseUp(_ e: MouseEventArgs) {
        super.OnMouseUp(e)
        if e.Button != MouseButtons.Left { return }
        let b = At(e.Location)
        if b != nil { Press(b!.Id) }
    }

    override func OnPaint(_ e: PaintEventArgs) {
        let g = e.Graphics
        g.SmoothingMode = SmoothingMode.None
        let W0 = ClientSize.Width, H0 = ClientSize.Height, F = 4 * U, crown = Sc(56)
        Pix.Wood(g, 0, 0, W0, H0, U, false, 11)
        Pix.Panel(g, F, crown, W0 - 2 * F, H0 - crown - F, U, false)
        // 頂上的銅牌＋兩邊小愛心
        let t = first ? "歡迎來到公仔櫃！" : "公仔櫃・重新設定"
        let tw = Pix.TextW(t, titleF), plw = tw + 14 * U, plh = Sc(34)
        let pr = Rectangle((W0 - plw) / 2, (crown - plh) / 2 + U / 2, plw, plh)
        Pix.Plate(g, t, titleF, pr, U)
        Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.X - 9 * U, pr.Y + plh / 2 - 2 * U, U)
        Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.Right + 4 * U, pr.Y + plh / 2 - 2 * U, U)
        Steps(g, W0, Sc(68))
        let q = step == 0 ? "你是？" : (step == 1 ? "選一櫃公仔" : "怎麼擺？")
        let hint = step == 0 ? "公仔們會照你的生活陪你（之後在小屋可以改）" : (step == 1 ? "每一櫃都很可愛，之後隨時能換" : (mode == "single" ? "選一隻，他會住在右下角的蛋裡" : "公仔櫃放在右下角，點格子就叫他們出來"))
        TextRenderer.DrawText(g, q, qF, Rectangle(0, Sc(100), W0, Sc(30)), Pix.TextC, Pix.Mid)
        TextRenderer.DrawText(g, hint, subF, Rectangle(0, Sc(130), W0, Sc(18)), Pix.C(0x9A6338), Pix.Mid)
        if step == 2 && mode == "single" {
            let first2 = Find("mode:shelf")
            if first2 != nil { TextRenderer.DrawText(g, "選哪一隻？", btnF, Rectangle(0, first2!.R.Bottom + Sc(6), W0, Sc(26)), Pix.TextC, Pix.Mid) }
        }
        for b in btns { DrawBtn(g, b) }
    }

    // 上面的三個步驟：現在這步黃色、做完的綠色打勾
    func Steps(_ g: Graphics, _ W0: Int, _ y: Int) {
        let names: [String] = ["你是？", "選一櫃", "怎麼擺"]
        let pw = Sc(112), ph = Sc(26), gap = Sc(18), x0 = (W0 - 3 * pw - 2 * gap) / 2
        for i in 0..<3 {
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

    func DrawBtn(_ g: Graphics, _ b: Btn) {
        let r = b.R
        let hot = b.Id == hoverId && b.Enabled
        if b.Kind >= 2 {
            // 下面的按鈕：有厚度的像素按鈕（主要按鈕是蜂蜜色）
            let face = !b.Enabled ? Pix.C(0xE9E0D0) : (b.Kind == 3 ? (hot ? Pix.C(0xFFD36A) : Pix.C(0xF6C453)) : (hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0)))
            let shade = !b.Enabled ? Pix.C(0xD3C7B2) : (b.Kind == 3 ? Pix.C(0xC8902C) : Pix.C(0xDCC6A2))
            Pix.Round(g, !b.Enabled ? Pix.C(0xBBA98C) : Pix.Ink, r.X, r.Y, r.Width, r.Height, U)
            Pix.Box(g, face, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U)
            Pix.Box(g, shade, r.X + U, r.Bottom - 3 * U, r.Width - 2 * U, 2 * U)
            if b.Enabled { Pix.Box(g, Pix.Mix(face, Color.White, 0.6), r.X + 2 * U, r.Y + U, r.Width - 4 * U, U) }
            let tw = Pix.TextW(b.Text, btnF), ax = 7 * U
            var tx = r.X + (r.Width - tw - (b.Id == "back" || b.Id == "next" ? ax : 0)) / 2
            let cy = r.Y + (r.Height - 2 * U) / 2
            let tc = b.Enabled ? Pix.TextC : Pix.Dim
            if b.Id == "back" { Arrow(g, tx + U, cy, -1, tc); tx += ax }
            TextRenderer.DrawText(g, b.Text, btnF, Rectangle(tx, r.Y, tw + 4, r.Height - 2 * U), tc, Pix.LeftMid)
            if b.Id == "next" && step < 2 { Arrow(g, tx + tw + 2 * U, cy, 1, tc) }
            return
        }
        // 卡片：底下一層影子；選到的是金色粗框、右上角綠色勾勾
        let edge = b.On ? Pix.C(0xC08A2C) : Pix.C(0x8A6A4A)
        let fill = b.On ? Pix.C(0xFFEDB8) : (hot ? Pix.C(0xFFF6DE) : Pix.C(0xFFFDF7))
        Pix.Round(g, Pix.C(0xE6D3B0), r.X + 2 * U, r.Y + 2 * U, r.Width, r.Height, U)
        Pix.Round(g, edge, r.X, r.Y, r.Width, r.Height, U)
        let ins = b.On ? 2 * U : U
        if b.On { Pix.Box(g, edge, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U) }
        Pix.Box(g, fill, r.X + ins, r.Y + ins, r.Width - 2 * ins, r.Height - 2 * ins)
        if hot && !b.On { Pix.Box(g, Pix.C(0xF6C453), r.X + ins, r.Bottom - ins - U, r.Width - 2 * ins, U) }
        if b.Kind == 1 { DrawPetCard(g, b) }
        else if b.Id == "student" || b.Id == "work" { DrawIconCard(g, b, b.Id == "student" ? SetupForm.STUDENT : SetupForm.WORK) }
        else if b.Id.StartsWith("lu:") { DrawShelfCard(g, b, b.Id.Substring(3)) }
        else { DrawModeCard(g, b) }
        if b.On {
            let s = 9 * U, bx = r.Right - s - 2 * U, by2 = r.Y + 2 * U
            Pix.Round(g, Pix.C(0x2F6E24), bx, by2, s, s, U)
            Pix.Box(g, Pix.C(0x5FB04A), bx + U, by2 + U, s - 2 * U, s - 2 * U)
            Pix.Mono(g, Pix.CHECK, Color.White, bx + 2 * U, by2 + 2 * U, U)
        }
    }

    func Arrow(_ g: Graphics, _ x: Int, _ cy: Int, _ dir: Int, _ c: Color) {
        for i in 0..<3 {
            let col = dir > 0 ? x + i * U : x + (2 - i) * U
            Pix.Box(g, c, col, cy - (2 - i) * U - U / 2, U, (2 - i) * 2 * U + U)
        }
    }

    func IconPal() -> Dict<Character, Color> {
        let p = Dict<Character, Color>()
        p["k"] = Pix.Ink; p["d"] = Pix.C(0x3D4A6B); p["D"] = Pix.C(0x2C3550); p["Y"] = Pix.C(0xF2C14E)
        p["w"] = Pix.C(0xFFFDF7); p["l"] = Pix.C(0xA9B8D0); p["b"] = Pix.C(0xA0643A); p["B"] = Pix.C(0xC8844E); p["s"] = Pix.C(0x7E4A28)
        return p
    }

    func DrawIconCard(_ g: Graphics, _ b: Btn, _ art: [String]) {
        let r = b.R
        let c = Math.Max(3, Sc(6)), aw = art[0].count * c
        Pix.Art(g, art, IconPal(), r.X + (r.Width - aw) / 2, r.Y + Sc(26), c)
        TextRenderer.DrawText(g, b.Text, bigF, Rectangle(r.X, r.Y + Sc(140), r.Width, Sc(32)), Pix.TextC, Pix.Mid)
        TextRenderer.DrawText(g, b.Sub, subF, Rectangle(r.X, r.Y + Sc(174), r.Width, Sc(22)), Pix.C(0x9A6338), Pix.Mid)
    }

    func DrawShelfCard(_ g: Graphics, _ b: Btn, _ id: String) {
        let r = b.R
        var pic: Bitmap! = nil
        var textY = r.Y + Sc(12)
        if shelfPics.TryGetValue(id, &pic) {
            let avail = r.Height - Sc(72), ph = Math.Min(pic.Height, avail), pw = pic.Width * ph / pic.Height
            g.DrawImage(pic, r.X + (r.Width - pw) / 2, r.Y + Sc(12), pw, ph)
            textY = r.Y + Sc(16) + ph
        }
        TextRenderer.DrawText(g, b.Text, bigF, Rectangle(r.X, textY, r.Width, Sc(30)), Pix.TextC, Pix.Mid)
        TextRenderer.DrawText(g, b.Sub, subF, Rectangle(r.X + Sc(6), textY + Sc(28), r.Width - Sc(12), Sc(38)), Pix.C(0x9A6338), [TextFormatFlags.HorizontalCenter, TextFormatFlags.Top, TextFormatFlags.WordBreak, TextFormatFlags.NoPadding, TextFormatFlags.NoPrefix])   // 四櫃並排時名單換行，不要被切掉
    }

    func DrawModeCard(_ g: Graphics, _ b: Btn) {
        let r = b.R
        let iconW = Sc(76), ix = r.X + Sc(14)
        if b.Id == "mode:shelf" {
            var pic: Bitmap! = nil
            if shelfPics.TryGetValue(lu, &pic) {
                let ph = r.Height - Sc(24), pw = pic.Width * ph / pic.Height
                let im = g.InterpolationMode
                g.InterpolationMode = InterpolationMode.HighQualityBicubic
                g.DrawImage(pic, ix + (iconW - pw) / 2, r.Y + Sc(12), pw, ph)
                g.InterpolationMode = im
            }
        }
        else {
            let pal = Dict<Character, Color>()
            pal["k"] = Pix.C(0x6B4A2E); pal["c"] = Pix.C(0xFFF4DC); pal["s"] = Pix.C(0xE8D3B0); pal["h"] = Color.White
            pal["r"] = Pix.C(0xD84A4A); pal["o"] = Pix.C(0xE7836A); pal["b"] = Pix.C(0x3D6BB3); pal["g"] = Pix.C(0x25B3BA); pal["Y"] = Pix.C(0xF5C842)
            let c = Math.Max(2, Sc(4)), ew = ShelfForm.EGG[0].count * c, eh = ShelfForm.EGG.count * c
            Pix.Art(g, ShelfForm.EGG, pal, ix + (iconW - ew) / 2, r.Y + (r.Height - eh) / 2, c)
        }
        let tx = ix + iconW + Sc(8)
        TextRenderer.DrawText(g, b.Text, bigF, Rectangle(tx, r.Y + r.Height / 2 - Sc(30), r.Right - tx - Sc(8), Sc(30)), Pix.TextC, Pix.LeftMid)
        TextRenderer.DrawText(g, b.Sub, subF, Rectangle(tx, r.Y + r.Height / 2 + Sc(2), r.Right - tx - Sc(8), Sc(22)), Pix.C(0x9A6338), Pix.LeftMid)
    }

    func DrawPetCard(_ g: Graphics, _ b: Btn) {
        let r = b.R
        var pic: Bitmap! = nil
        let nameH = Sc(24)
        if petPics.TryGetValue(lu + ":" + b.Id.Substring(4), &pic) {
            let avail = r.Height - nameH - Sc(8), ph = Math.Min(pic.Height, avail), pw = pic.Width * ph / pic.Height
            g.DrawImage(pic, r.X + (r.Width - pw) / 2, r.Y + Sc(6) + (avail - ph), pw, ph)
        }
        TextRenderer.DrawText(g, b.Text, btnF, Rectangle(r.X, r.Bottom - nameH - Sc(4), r.Width, nameH), Pix.TextC, Pix.Mid)
    }
}
