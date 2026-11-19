// ===== 65_work_settings.swift — DeskPals.WorkSettings.cs =====
// WoWo Pals：「工作設定」視窗（小屋選單 → 工作 → 工作設定…、小本子的「來源」、空白頁的「接上」）。畫面照 v011/work-settings 的 D 版：
//   打開先看格子（九個來源，每格有狀態和 關｜開），點格子進清單（左邊來源、右邊要填的），左上「全部」或 Esc 回格子；右上可以切格子／清單，記住上次的。
//   要填東西的來源（Jira、開會、下雨、公司網路、工作日誌資料夾）填好才會開：按「開」先跳到要填的那一格，填好自己開。
//   GitHub／GitLab 找不到 gh／glab 不能開（寫「找不到 gh」＋怎麼裝）；CI 要先開 GitLab 或 GitHub。
//   Esc：清單 → 格子；格子 → 關掉（跟取消一樣）。儲存時開著的來源有沒填好的，跳過去標紅，不關。
// 設定讀寫都走 World 的 WC()／WorkSet()／SetJiraToken()（DeskPals.Work.cs → 62_work.swift）；看的方式記在 work-ui.txt。
// 離屏測試：pipe「work-settings open|close|save|info|press <id>|type <欄位> <字>|key esc|tab|space」，snap 時畫進虛擬螢幕。
// 掛在核心的地方：Snap → WorkSnap(g)（41_world_b.swift，CuSnap／NbSnap 後面）；WorkMsg 的 "work-settings" → WorkSettingsMsg（62_work.swift）。
// mac 的差別（都標了 // mac:）：
// - 沒有 WSL：清單的 Claude、Codex 那頁不放「別的資料夾」（claude_dir／codex_dir 兩格）；設定值留著不動。
// - 工作日誌資料夾的提示字用 Mac 的路徑。
// - C# 的欄位 view 改叫 viewKind（Form shim 已經有 view＝NSView）。
// - AutoScroll：shim 沒有。自己記捲動位置（AutoScrollPosition 跟 WinForms 一樣是負的），滾輪、拖右邊自己畫的捲軸；
//   版面、點擊、輸入框的位置照 C# 的算法（Logical()、LayoutBoxes 的 o）。另外離屏測試可用 DESKPALS_TEST_WA_H 假裝工作區比較矮
//   （mac 沒有 DESKPALS_TEST_DPI 的假 150%／200%）。
// - ProcessDialogKey → KeyPreview 的 OnKeyDown（shim：輸入框自己的 KeyDown 先、再來是表單的）；ActiveControl = null → makeFirstResponder(nil)。
// - TextBox：BorderStyle.None → CuMaker.Borderless；TextAlign.Center → NSTextField.alignment；GotFocus、UseSystemPasswordChar → WsTextBox
//   （08_shim_worksettings.swift）；EM_SETCUEBANNER → PlaceholderText。
// - FolderBrowserDialog → NSOpenPanel（WsDialogs.PickFolder）。
// - 沒有「編輯」選單：Cmd+X／C／V／A／Z 在 OnKeyDown 自己送給打字框（WsEditKeys；貼 token 要用）。

import AppKit

//@@IN World
    var workForm: WorkSettingsForm! = nil
    // 設定視窗的示範：現在帶頭那隻站好的樣子（用預覽用的 World 畫，不動到桌面上的公仔）
    var workPalPic: Bitmap! = nil
//@@END

extension World {
    // 小屋選單「工作設定…」、小本子的「來源」「接上」、pipe「work-settings open」
    func ShowWorkSettings() { ShowWorkSettings(nil) }
    func ShowWorkSettings(_ src: String?) {
        if workForm == nil || workForm.IsDisposed { workForm = WorkSettingsForm(self) }
        else { workForm.Reload() }
        if let s = src { workForm.OpenSource(s) }
        var wa: Rectangle = App.Offscreen ? screens[0].WorkingArea : Screen.FromPoint(Cursor.Position).WorkingArea
        // mac: 離屏測試沒有假的 DPI（DESKPALS_TEST_DPI）：DESKPALS_TEST_WA_H 假裝工作區比較矮，測「放不下就捲」
        if App.Offscreen, let hs = ProcessInfo.processInfo.environment["DESKPALS_TEST_WA_H"], let hh = Int(hs), hh > 0 { wa.Height = Math.Min(wa.Height, hh) }
        workForm.FitTo(wa)
        let lx: Int = wa.Left + Math.Max(0, (wa.Width - workForm.Width) / 2)
        let ly: Int = wa.Top + Math.Max(0, (wa.Height - workForm.Height) / 2)
        workForm.Location = Point(lx, ly)
        workForm.Show()
        let f: WorkSettingsForm = workForm
        // glab／gh 有沒有裝、登入了沒：打開時重新看一次（背景），看完重畫
        let job: () -> Void = { self.Try("auth", { self.DetectAuth() }); self.Post { if !f.IsDisposed { f.Invalidate() } } }
        ThreadPool.QueueUserWorkItem(job)
        if App.Offscreen { return }
        ActivateForm(workForm)
        Later(0.2) { if !f.IsDisposed && f.Visible { self.ActivateForm(f) } }
    }

    func ToolState(_ tool: String) -> String { return tool == "gh" ? ghState : glabState }
    func JiraState() -> String { return jiraStatus }
    func WorkSnap(_ g: Graphics) { if workForm != nil && !workForm.IsDisposed && workForm.VVisible { workForm.PaintTo(g) } }

    // 設定視窗的示範：現在帶頭那隻站好的樣子（用預覽用的 World 畫，不動到桌面上的公仔）
    func WorkPalPic(_ s: Int) -> Bitmap! {
        if workPalPic != nil { return workPalPic }
        // mac: C# 的 try／catch（例外寫 log）：Swift 沒有例外，先看帶頭的在不在
        let pv = World(s, lineup)
        let lead: Pet! = Lead()
        var me: Pet! = lead != nil ? pv.Get(lead.P.Id) : nil
        if me == nil && pv.Pets.Count > 0 { me = pv.Pets[0] }
        if me != nil { workPalPic = me.IconPic() }
        else { App.Log("work settings pal: no pet") }
        return workPalPic
    }

    func WorkSaved() {
        Lead()?.Say("好～工作設定存好了", 2.2)
    }

    // pipe：work-settings …（open 在 WorkMsg）
    @discardableResult func WorkSettingsMsg(_ c: Client, _ p: [String], _ line: String) -> Bool {
        if p.count < 2 { return true }
        let t = line.Trim()
        switch p[1] {
        case "open": ShowWorkSettings(p.count >= 3 ? p[2] : nil); return true
        default: break
        }
        if workForm == nil || workForm.IsDisposed { if p[1] == "info" { World.Send(c, "ws none\nend\n") }; return true }
        switch p[1] {
        case "close": workForm.Cancel()
        case "save": workForm.Save()
        case "info": World.Send(c, workForm.Info() + "end\n")
        case "press": if p.count >= 3 { workForm.Press(p[2]) }
        case "type":
            if p.count >= 3 {
                let i3 = World.NthSpace(t, 3)
                workForm.TestType(p[2], i3 > 0 ? t.Substring(i3 + 1) : "")
            }
        case "key": if p.count >= 3 { workForm.TestKey(p[2]) }
        default: break
        }
        return true
    }
}

final class WorkSettingsForm: Form {
    final class Src {
        let Id: String, Name: String, Short: String, Icon: String, Key: String
        let Sub: String?
        let Say: String
        init(_ id: String, _ name: String, _ sh: String, _ icon: String, _ key: String, _ sub: String?, _ say: String) { Id = id; Name = name; Short = sh; Icon = icon; Key = key; Sub = sub; Say = say }
    }
    static let SRC: [Src] = [
        Src("claude", "Claude Code、Codex", "Claude、Codex", "claude", "ai", "本機的對話會記進小本子", "記進小本子了"),
        Src("jira", "Jira", "Jira", "jira", "jira", nil, "PBG-2231 解決了"),
        Src("gitlab", "GitLab", "GitLab", "gitlab", "gitlab", nil, "MR !128 合併了"),
        Src("github", "GitHub", "GitHub", "github", "github", nil, "PR #17 合併了"),
        Src("ci", "CI", "CI", "tag", "ci", "推了 tag 就幫你盯", "v0.10.4 的 CI 過了"),
        Src("meet", "開會", "開會", "meet", "meet", nil, ""),
        Src("rain", "下雨", "下雨", "rain", "rain", "平日 17:30 看一次", "等下會下雨，帶傘"),
        Src("net", "公司網路", "公司網路", "net", "vpn", "連不到就提醒 VPN 斷了", "VPN 好像斷了"),
        Src("worklog", "工作日誌資料夾", "工作日誌資料夾", "folder", "worklog", "今天有新檔就提醒", "今天的工作日誌好了") ]
    static let FILL: Dict<String, String> = {
        let d = Dict<String, String>()
        d["jira"] = "填好這三格就會開始"; d["meet"] = "填好網址就會開始"; d["rain"] = "填好地點就會開始"; d["net"] = "填好主機就會開始"; d["worklog"] = "選好資料夾就會開始"
        return d
    }()
    static let NEED: Dict<String, String> = {
        let d = Dict<String, String>()
        d["jira"] = "要填網站、信箱和 token"; d["meet"] = "要填行事曆網址"; d["rain"] = "要填地點"; d["net"] = "要填主機"; d["worklog"] = "要選資料夾"
        return d
    }()
    static let HowGh = "https://cli.github.com/", HowGlab = "https://gitlab.com/gitlab-org/cli#installation", HowJira = "https://id.atlassian.com/manage-profile/security/api-tokens"
    // mac: SystemInformation.VerticalScrollBarWidth（mac 的捲軸是自己畫的，寬度照 Windows 100% 的 17）
    static let ScrollBarW = 17

    let w: World
    let d: Double
    let U: Int
    let plateF: FontT, nameF: FontT, tileNameF: FontT, labF: FontT, subF: FontT, btnF: FontT, segF: FontT, boxF: FontT, monoF: FontT
    var VVisible = false
    let v = Dict<String, String>()   // 改到一半的設定（儲存才寫回去）
    let pending = HashSet<String>(), bad = HashSet<String>()
    var viewKind = "grid", sel = "claude", hoverId = "", focusStop = "", lastOpened = ""   // mac: C# 的 view（shim 的 Form 已經有 view）
    var advOpen = false, loading = false
    let hits = Dict<String, Rectangle>()
    let stops = List<String>()   // Tab 的順序（畫的時候排）
    let boxes = Dict<String, TextBox>()
    let shown = HashSet<String>()   // 現在擺出來的輸入框（離屏時視窗沒顯示，TextBox.Visible 永遠是 false）
    static let Paper = Pix.C(0xFFFDF7), Sub = Pix.C(0x6B4E33), OkC = Pix.C(0x276A1C), BadC = Pix.C(0xB04040), WarnC = Pix.C(0x8A500C), MuteC = Pix.C(0x6E5238), LinkC = Pix.C(0x7A4A22)

    // mac: AutoScroll（WinForms 的 ScrollableControl）：自己記
    var AutoScroll = false
    var AutoScrollMinSize = SizeT(0, 0)
    var scrollY = 0
    var AutoScrollPosition: Point { return PointT(0, -scrollY) }
    var dragging = false, dragGrab = 0

    init(_ w: World) {
        self.w = w
        d = Double(w.S) / 4.0
        U = Math.Max(2, CInt(Math.Round(2 * d)))
        let jh = "Microsoft JhengHei UI"
        plateF = FontT(jh, 12, FontStyle.Bold)
        nameF = FontT(jh, 12, FontStyle.Bold)
        tileNameF = FontT(jh, 11.25, FontStyle.Bold)
        labF = FontT(jh, 10, FontStyle.Bold)
        subF = FontT(jh, 8.5, FontStyle.Bold)
        btnF = FontT(jh, 11, FontStyle.Bold)
        segF = FontT(jh, 10, FontStyle.Bold)
        boxF = FontT(jh, 10.5, FontStyle.Regular)
        monoF = FontT("Consolas", 9.5)
        super.init()
        Text = "WoWo Pals・工作設定"
        FormBorderStyle = FormBorderStyleT.FixedSingle
        MaximizeBox = false; MinimizeBox = false
        ShowInTaskbar = true; TopMost = true
        StartPosition = FormStartPosition.Manual
        BackColor = Pix.Cream
        DoubleBuffered = true
        ClientSize = SizeT(Sc(600), Sc(600))
        KeyPreview = true
        let fields: [[String]] = [["jira_site", ""], ["jira_email", ""], ["token", ""], ["meet_url", "mono"], ["meet_before", ""],
            ["rain_place", ""], ["vpn_host", "mono"], ["worklog_dir", "mono"], ["claude_dir", "mono"], ["codex_dir", "mono"]]
        for f in fields {
            let t = WsTextBox()   // mac: GotFocus、UseSystemPasswordChar（08_shim_worksettings.swift）
            t.BackColor = WorkSettingsForm.Paper; t.ForeColor = Pix.TextC
            t.Font = f[1] == "mono" ? monoF : boxF
            t.Visible = false
            if f[0] == "token" { t.UseSystemPasswordChar = true }
            let key = f[0]
            t.TextChanged = { [unowned self, unowned t] in if !self.loading { self.Typed(key, t.Text) } }
            t.GotFocus = { [unowned self] in self.focusStop = "tb:" + key; self.Invalidate() }
            boxes[key] = t
            Controls.Add(t)
            CuMaker.Borderless(t, WorkSettingsForm.Paper)   // mac: BorderStyle.None
            if f[0] == "meet_before" { t.tf?.alignment = .center }   // mac: TextAlign = HorizontalAlignment.Center
        }
        FormClosing = { [unowned self] (e: FormClosingEventArgs) in self.Remember() }
        Reload()
        let ui = World.ReadWorkUi().Split("\n")
        for l in ui {
            let kv = l.Trim().Split("=")
            if kv.count != 2 { continue }
            if kv[0] == "view" && (kv[1] == "grid" || kv[1] == "list") { viewKind = kv[1] }
            if kv[0] == "sel" && WorkSettingsForm.Find(kv[1]) != nil { sel = kv[1] }
        }
        LayoutBoxes()
    }

    func Sc(_ x: Int) -> Int { return CInt(Math.Round(Double(x) * d)) }

    // 放不進工作區（1366×768 開 125%、1080p 開 175%…）：視窗變矮、裡面可以捲，儲存和取消一定按得到
    func FitTo(_ wa: Rectangle) {
        let chrome = Height - ClientSize.Height, full = Sc(600)
        if full + chrome <= wa.Height { AutoScroll = false; scrollY = 0; ClientSize = SizeT(full, full) }
        else {
            AutoScroll = true
            AutoScrollMinSize = SizeT(full, full)
            ClientSize = SizeT(full + WorkSettingsForm.ScrollBarW, Math.Max(Sc(240), wa.Height - chrome))
            ScrollTo(scrollY)   // mac: 視窗變了，捲動位置夾回範圍內
        }
        LayoutBoxes()
        Invalidate()
    }
    func Logical(_ p: Point) -> Point { return AutoScroll ? PointT(p.X - AutoScrollPosition.X, p.Y - AutoScrollPosition.Y) : p }
    // mac: OnScroll 沒有（捲軸是自己畫的，捲的時候 ScrollTo 自己重畫）
    override func OnMouseWheel(_ e: MouseEventArgs) {
        super.OnMouseWheel(e)
        if AutoScroll { ScrollTo(scrollY - e.Delta / 2) }   // mac: WinForms 的 AutoScroll 自己會捲
        Invalidate()
    }
    static func Find(_ id: String) -> Src! { for s in SRC { if s.Id == id { return s } }; return nil }

    // ---- mac: 自己畫的捲軸（AutoScroll 時在右邊那一條）----
    func ScrollTo(_ y: Int) {
        let top = Math.Max(0, AutoScrollMinSize.Height - ClientSize.Height)
        let ny = Math.Max(0, Math.Min(top, y))
        if ny == scrollY { return }
        scrollY = ny
        LayoutBoxes()
        Invalidate()
    }
    func ThumbRect() -> Rectangle {
        let full = AutoScrollMinSize.Width, cs = ClientSize
        let total = Math.Max(1, AutoScrollMinSize.Height)
        let th = Math.Min(cs.Height, Math.Max(Sc(24), cs.Height * cs.Height / total))
        let range = Math.Max(1, AutoScrollMinSize.Height - cs.Height)
        let ty = (cs.Height - th) * scrollY / range
        return Rectangle(full + 3, ty, Math.Max(2, cs.Width - full - 6), th)
    }
    func DragTo(_ y: Int) {
        let cs = ClientSize
        let th = ThumbRect().Height
        let room = Math.Max(1, cs.Height - th)
        let range = Math.Max(0, AutoScrollMinSize.Height - cs.Height)
        ScrollTo((y - dragGrab) * range / room)
    }
    func PaintScrollBar(_ g: Graphics) {
        if !AutoScroll { return }
        let full = AutoScrollMinSize.Width, cs = ClientSize
        if cs.Width - full <= 0 { return }
        Pix.Box(g, Pix.C(0xEAD7B4), full, 0, cs.Width - full, cs.Height)
        Pix.Box(g, Pix.Ink, full, 0, Math.Max(1, U / 2), cs.Height)
        let r = ThumbRect()
        Pix.Round(g, Pix.Ink, r.X, r.Y, r.Width, r.Height, Math.Max(1, U / 2))
        Pix.Box(g, dragging ? Pix.C(0xC8902C) : Pix.C(0xF6C453), r.X + 1, r.Y + 1, r.Width - 2, r.Height - 2)
    }
    override func OnMouseDown(_ e: MouseEventArgs) {
        super.OnMouseDown(e)
        if AutoScroll && e.Button == MouseButtons.Left && e.X >= AutoScrollMinSize.Width {
            let r = ThumbRect()
            dragGrab = r.Contains(e.Location) ? e.Y - r.Y : r.Height / 2
            dragging = true
            DragTo(e.Y)
            Invalidate()
        }
    }

    // 從 World 讀回現在的設定（打開視窗時）
    func Reload() {
        loading = true
        for k in World.WorkDefaults { v[k[0]] = w.WC(k[0]) }
        pending.Clear(); bad.Clear()
        boxes["jira_site"].Text = v["jira_site"]; boxes["jira_email"].Text = v["jira_email"]; boxes["token"].Text = ""
        boxes["meet_url"].Text = v["meet_url"]; boxes["meet_before"].Text = v["meet_before"]; boxes["rain_place"].Text = v["rain_place"]
        boxes["vpn_host"].Text = v["vpn_host"]; boxes["worklog_dir"].Text = v["worklog_dir"]; boxes["claude_dir"].Text = v["claude_dir"]; boxes["codex_dir"].Text = v["codex_dir"]
        advOpen = v["claude_dir"] != "" || v["codex_dir"] != ""
        loading = false
        LayoutBoxes()
        Invalidate()
    }

    func Remember() { World.WriteWorkUi("view=" + viewKind + "\nsel=" + sel + "\n") }

    // ================= 規則 =================
    func On(_ id: String) -> Bool { guard let s = WorkSettingsForm.Find(id) else { return false }; return v[s.Key] == "1" && !Lock(id) && Missing(id).Count == 0 }
    func Lock(_ id: String) -> Bool { return id == "ci" && v["gitlab"] != "1" && v["github"] != "1" }
    func Tool(_ id: String) -> String { return id == "github" ? w.ToolState("gh") : (id == "gitlab" ? w.ToolState("glab") : "ok") }
    func ToolName(_ id: String) -> String { return id == "github" ? "gh" : "glab" }

    // 還缺什麼（欄位名稱；tool＝glab／gh 不能用）
    func Missing(_ id: String) -> List<String> {
        let m = List<String>()
        switch id {
        case "jira":
            if v["jira_site"].Trim() == "" { m.Add("jira_site") }
            if !Regex.IsMatch(v["jira_email"].Trim(), "^[^\\s\\x0B\\x85]+@[^\\s\\x0B\\x85]+$") { m.Add("jira_email") }   // mac: .NET 的 \S（ICU 的 \s 少了 \x0B、\x85）
            if boxes["token"].Text.Trim() == "" && !w.HasJiraToken() { m.Add("token") }
        case "meet":
            if World.WorkUrl(v["meet_url"]) == nil { m.Add("meet_url") }
            do { var n = 0; if !int.TryParse(v["meet_before"].Trim(), &n) || n < 1 || n > 120 { m.Add("meet_before") } }
        case "rain": if v["rain_place"].Trim() == "" { m.Add("rain_place") }
        case "net": if !Regex.IsMatch(v["vpn_host"].Trim(), "^[\\w.-]+(:\\d{1,5})?$") { m.Add("vpn_host") }
        case "worklog": if v["worklog_dir"].Trim() == "" || !Directory.Exists(v["worklog_dir"].Trim()) { m.Add("worklog_dir") }
        case "github", "gitlab": do { let ts = Tool(id); if ts == "missing" || ts == "nologin" { m.Add("tool") } }
        default: break
        }
        return m
    }

    // 一個來源的一句狀態：字、顏色（ok／bad／warn／mute）、有沒有「怎麼裝」連結
    func StateOf(_ id: String, _ text: inout String, _ kind: inout String, _ link: inout String?) {
        link = nil
        if Lock(id) { text = "先打開 GitLab 或 GitHub"; kind = "mute"; return }
        if id == "gitlab" || id == "github" {
            let ts = Tool(id), tn = ToolName(id)
            if ts == "missing" { text = "找不到 " + tn; kind = "bad"; link = id == "github" ? WorkSettingsForm.HowGh : WorkSettingsForm.HowGlab; return }
            if ts == "nologin" { text = tn + " 還沒登入"; kind = "bad"; link = id == "github" ? WorkSettingsForm.HowGh : WorkSettingsForm.HowGlab; return }
        }
        if id == "jira" && On(id) && w.JiraState() == "auth" && boxes["token"].Text.Trim() == "" { text = "連不上，檢查 token"; kind = "bad"; return }
        if WorkSettingsForm.FILL.ContainsKey(id) && Missing(id).Count > 0 { text = "要先填"; kind = "warn"; return }
        if On(id) { text = id == "worklog" ? "已選好" : "已接上"; kind = "ok"; return }
        text = "關著"; kind = "mute"
    }
    func KindC(_ k: String) -> Color {
        if k == "ok" { return WorkSettingsForm.OkC }
        if k == "bad" { return WorkSettingsForm.BadC }
        return k == "warn" ? WorkSettingsForm.WarnC : WorkSettingsForm.MuteC
    }

    // ================= 動作 =================
    func Typed(_ key: String, _ text: String) {
        if key != "token" { v[key] = text }
        if text.Trim() != "" { bad.Remove(key) }
        // 按過「開」、現在填好了：自己開
        for id in List<String>(pending.ToArray()) {
            if Missing(id).Count == 0 { if let s = WorkSettingsForm.Find(id) { v[s.Key] = "1" }; pending.Remove(id) }
        }
        Invalidate()
    }

    func OpenSource(_ id: String) {
        if WorkSettingsForm.Find(id) == nil { return }
        sel = id; bad.Clear()
        SetView("list")
    }

    func SetView(_ to: String) {
        viewKind = to
        Remember()
        LayoutBoxes()
        Invalidate()
    }

    func Toggle(_ id: String) {
        if Lock(id) { return }
        guard let s = WorkSettingsForm.Find(id) else { return }   // mac: C# 這裡會丟 NullReferenceException（測試指令打錯 id）
        if v[s.Key] == "1" || pending.Contains(id) {
            v[s.Key] = "0"; pending.Remove(id); bad.Clear()
            Invalidate()
            return
        }
        let m = Missing(id)
        if m.Count > 0 {
            // 要先填的：不偷偷打開，先跳過去填（填好自己開）；glab／gh 找不到的開不了
            if m[0] != "tool" { pending.Add(id) }
            sel = id; bad.Clear()
            SetView("list")
            if m[0] != "tool" { FocusBox(m[0]) }
            else { focusStop = "howto:" + id }
            return
        }
        v[s.Key] = "1"
        Invalidate()
    }

    func FocusBox(_ key: String) {
        guard let t = boxes.Get(key) else { return }
        LayoutBoxes()
        focusStop = "tb:" + key
        if !App.Offscreen { t.Select(); t.Focus() }
        Invalidate()
    }

    func Save() {
        // 開著的來源（不是只按了開、還在等填的）有沒填好的：跳過去、標紅、不關
        for s in WorkSettingsForm.SRC {
            if v[s.Key] != "1" || Lock(s.Id) { continue }
            let m = Missing(s.Id)
            m.Remove("tool")
            if m.Count == 0 { continue }
            sel = s.Id; bad.Clear(); for k in m { bad.Add(k) }
            SetView("list")
            FocusBox(m[0])
            return
        }
        let srcKeys: [String] = ["ai", "jira", "gitlab", "github", "ci", "meet", "rain", "vpn", "worklog"]
        for k in World.WorkDefaults {
            let key = k[0]
            var val = v[key]
            if srcKeys.contains(key) {
                let id = WorkSettingsForm.SrcOfKey(key)
                val = val == "1" && !Lock(id) && Missing(id).Count == 0 ? "1" : "0"
            }
            if val.Trim() != w.WC(key) { _ = w.WorkSet(key, val.Trim() == "" ? "-" : val.Trim()) }
        }
        if boxes["token"].Text.Trim() != "" { _ = w.SetJiraToken(boxes["token"].Text.Trim()) }
        App.Log("work settings saved")
        Remember()
        w.WorkSaved()
        Close()
    }
    static func SrcOfKey(_ key: String) -> String { for s in SRC { if s.Key == key { return s.Id } }; return key }

    func Cancel() { Remember(); Close() }

    func Esc() {
        if viewKind == "list" { let back = sel; SetView("grid"); focusStop = "tile:" + back; Invalidate() }
        else { Cancel() }
    }

    func OpenLink(_ url: String) {
        lastOpened = url
        if App.Offscreen { return }
        // mac: Process.Start（UseShellExecute → NSWorkspace.open）不丟例外；開不了也不會知道（C# 的 catch 寫 log）
        let psi = ProcessStartInfo(url)
        psi.UseShellExecute = true
        Process.Start(psi)
    }

    func Press(_ id: String) {
        var a = id, arg = ""
        let c = id.IndexOf(Character(":"))
        if c > 0 { a = id.Substring(0, c); arg = id.Substring(c + 1) }
        switch a {
        case "view": SetView(arg)
        case "all": SetView("grid"); focusStop = "tile:" + sel
        case "tile": OpenSource(arg)
        case "tab": sel = arg; bad.Clear(); Remember(); LayoutBoxes(); Invalidate()
        case "sw": Toggle(arg)
        case "howto": OpenLink(arg == "github" || arg == "gitlab" ? HowUrl(arg) : WorkSettingsForm.HowJira)
        case "adv": advOpen = !advOpen; LayoutBoxes(); Invalidate()
        case "quiet": v["meet_quiet"] = v["meet_quiet"] == "1" ? "0" : "1"; Invalidate()
        case "pickdir": PickDir()
        case "save": Save()
        case "cancel": Cancel()
        default: break
        }
    }

    func PickDir() {
        if App.Offscreen { return }
        // mac: FolderBrowserDialog → NSOpenPanel（只選資料夾）
        let start: String = Directory.Exists(v["worklog_dir"]) ? v["worklog_dir"] : ""
        if let picked = WsDialogs.PickFolder("工作日誌放在哪個資料夾？", start) { boxes.Get("worklog_dir")?.Text = picked }
    }

    // ---- 鍵盤：Esc 回上一層；Tab 在按鈕、格子、輸入框之間走；空白鍵／Enter 按下 ----
    // mac: WinForms 的 ProcessDialogKey → KeyPreview 的 OnKeyDown（打字框自己的 KeyDown 先跑，沒處理才到這裡）
    override func OnKeyDown(_ e: KeyEventArgs) {
        // mac: 沒有「編輯」選單：Cmd+X／C／V／A／Z 自己送給打字框（08_shim_worksettings.swift）；其他 Cmd 鍵不當成 Tab／空白鍵
        if WsEditKeys.Command { if WsEditKeys.Handle() { e.Handled = true }; return }
        if ProcessDialogKey(e.KeyData) { e.Handled = true; return }
        super.OnKeyDown(e)
    }
    func ProcessDialogKey(_ k: Keys) -> Bool {
        if k == Keys.Escape { Esc(); return true }
        if k == Keys.Tab || k == (Keys.Tab | Keys.Shift) { MoveFocus(k == Keys.Tab ? 1 : -1); return true }
        if (k == Keys.Space || k == Keys.Enter) && focusStop != "" && !focusStop.StartsWith("tb:") { Press(focusStop); return true }
        return false   // mac: base.ProcessDialogKey(k)＝讓按鍵照常往下（打進輸入框）
    }
    func MoveFocus(_ dir: Int) {
        Relayout()
        if stops.Count == 0 { return }
        var i = stops.IndexOf(focusStop)
        i = i < 0 ? (dir > 0 ? 0 : stops.Count - 1) : (i + dir + stops.Count) % stops.Count
        focusStop = stops[i]
        if focusStop.StartsWith("tb:") { if !App.Offscreen { boxes.Get(focusStop.Substring(3))?.Focus() } }
        else if !App.Offscreen { panel?.makeFirstResponder(nil) }   // mac: ActiveControl = null
        Invalidate()
    }
    func TestKey(_ k: String) {
        if k == "esc" { Esc() }
        else if k == "tab" { MoveFocus(1) }
        else if k == "shifttab" { MoveFocus(-1) }
        else if k == "space" && focusStop != "" && !focusStop.StartsWith("tb:") { Press(focusStop) }
    }
    func TestType(_ key: String, _ text: String) {
        if let t = boxes.Get(key) { t.Text = text }   // TextChanged → Typed
    }

    func HitAt(_ p: Point) -> String { for kv in hits { if kv.Value.Contains(p) { return kv.Key } }; return "" }
    override func OnMouseMove(_ e: MouseEventArgs) {
        super.OnMouseMove(e)
        if dragging { DragTo(e.Y); return }   // mac: 拖捲軸
        let h = HitAt(Logical(e.Location))
        if h != hoverId { hoverId = h; Cursor = h != "" ? Cursors.Hand : Cursors.Default; Invalidate() }
    }
    override func OnMouseLeave(_ e: EventArgs) { super.OnMouseLeave(e); if hoverId != "" { hoverId = ""; Invalidate() } }
    override func OnMouseUp(_ e: MouseEventArgs) {
        super.OnMouseUp(e)
        if dragging { dragging = false; Invalidate(); return }   // mac: 放開捲軸
        if e.Button != MouseButtons.Left { return }
        // 開關、連結蓋在格子上面：先看小的
        var best = ""
        var area = int.MaxValue
        let lp = Logical(e.Location)
        for kv in hits {
            if kv.Value.Contains(lp) && kv.Value.Width * kv.Value.Height < area { best = kv.Key; area = kv.Value.Width * kv.Value.Height }
        }
        if best != "" { focusStop = best; Press(best) }
    }

    // ---- 離屏測試：不真的顯示，snap 時畫進虛擬螢幕 ----
    override func SetVisibleCore(_ value: Bool) {
        if App.Offscreen { VVisible = value; super.SetVisibleCore(false); return }
        super.SetVisibleCore(value)
    }
    func PaintTo(_ g: Graphics) {
        let cs = ClientSize
        if cs.Width <= 0 || cs.Height <= 0 { return }
        let b = Bitmap(cs.Width, cs.Height, PixelFormat.Format24bppRgb)
        do {
            let gg = Graphics.FromImage(b)
            OnPaint(PaintEventArgs(gg, Rectangle(0, 0, cs.Width, cs.Height)))
            for t in boxes.Values {
                if !shown.Contains(KeyOf(t)) { continue }
                do { let bg = SolidBrush(t.BackColor); gg.FillRectangle(bg, t.Bounds) }
                let s: String = t.UseSystemPasswordChar ? String(repeating: "●", count: t.Text.Length) : t.Text
                if s == "", let cue = cues.Get(ObjectIdentifier(t)) {
                    PixText.DrawText(gg, cue, t.Font, t.Bounds, Pix.C(0x866B51), [TextFormatFlags.Left, TextFormatFlags.VerticalCenter, TextFormatFlags.EndEllipsis])
                    continue
                }
                let centered: Bool = t.tf?.alignment == NSTextAlignment.center   // mac: t.TextAlign == HorizontalAlignment.Center
                let al: TextFormatFlags = centered ? TextFormatFlags.HorizontalCenter : TextFormatFlags.Left
                PixText.DrawText(gg, s, t.Font, t.Bounds, t.ForeColor, al.union([TextFormatFlags.VerticalCenter, TextFormatFlags.NoPrefix, TextFormatFlags.EndEllipsis]))   // 離屏（含假的 150%）照同一個 DPI 畫
            }
        }
        g.DrawImageUnscaled(b, Left, Top)
    }

    // 離屏時視窗沒顯示、不會自己重畫：要知道按鈕在哪（Tab 順序、測試）之前先在記憶體裡畫一次
    func Relayout() {
        if !App.Offscreen || ClientSize.Width <= 0 || ClientSize.Height <= 0 { return }
        let b = Bitmap(ClientSize.Width, ClientSize.Height, PixelFormat.Format24bppRgb)
        let g = Graphics.FromImage(b)
        OnPaint(PaintEventArgs(g, Rectangle(0, 0, ClientSize.Width, ClientSize.Height)))
    }

    func Info() -> String {
        Relayout()
        let sb = StringBuilder()
        let focusS: String = focusStop == "" ? "-" : focusStop
        let linkS: String = lastOpened == "" ? "-" : lastOpened
        sb.Append("ws view=" + viewKind + " sel=" + sel + " focus=" + focusS)
        sb.Append(" pending=" + WorkSettingsForm.Join(pending) + " bad=" + WorkSettingsForm.Join(bad))
        sb.Append(" link=" + linkS + " size=" + String(ClientSize.Width) + "x" + String(ClientSize.Height))
        sb.Append(" scroll=" + (AutoScroll ? "1" : "0") + " title=" + Text.Replace(" ", "_") + "\n")
        for s in WorkSettingsForm.SRC {
            var t = "", k = ""
            var l: String? = nil
            StateOf(s.Id, &t, &k, &l)
            let onS: String = On(s.Id) ? "1" : "0"
            let lockS: String = Lock(s.Id) ? "1" : "0"
            sb.Append("src " + s.Id + " want=" + v[s.Key] + " on=" + onS + " lock=" + lockS + " state=" + t.Replace(" ", "_") + " kind=" + k + "\n")
        }
        for kv in hits { sb.Append("hit " + kv.Key + " " + String(kv.Value.X) + " " + String(kv.Value.Y) + " " + String(kv.Value.Width) + " " + String(kv.Value.Height) + "\n") }
        for kv in boxes { if shown.Contains(kv.Key) { sb.Append("tb " + kv.Key + " " + kv.Value.Text.Replace(" ", "_") + "\n") } }
        sb.Append("lead " + LeadText(sel).Replace(" ", "_") + "\n")
        return sb.ToString()
    }
    static func Join(_ h: HashSet<String>) -> String { return h.Count == 0 ? "-" : string.Join(",", h.ToArray()) }

    // ================= 版面 =================
    // 100% 時：視窗內 600×600；冠 56；面板 18～582；格子 3×3（172×128）；清單：左邊 178 寬、右邊 366 寬
    func PaneR() -> Rectangle { return Rectangle(Sc(204), Sc(72), Sc(366), Sc(452)) }
    func FieldY(_ i: Int) -> Int { return PaneR().Y + Sc(108) + i * Sc(60) }
    func FieldBox(_ i: Int, _ wd: Int) -> Rectangle { let p = PaneR(); return Rectangle(p.X + Sc(22), FieldY(i) + Sc(20), wd > 0 ? wd : p.Width - Sc(44), Sc(28)) }

    func LayoutBoxes() {
        for t in boxes.Values { t.Visible = false }
        shown.Clear()
        if viewKind != "list" { return }
        guard let cur = WorkSettingsForm.Find(sel) else { return }
        let show = v[cur.Key] == "1" || pending.Contains(sel)
        let l = List<KeyValuePair<String, Rectangle>>()
        switch sel {
        case "jira": if show { l.Add(WorkSettingsForm.Kv("jira_site", FieldBox(0, 0))); l.Add(WorkSettingsForm.Kv("jira_email", FieldBox(1, 0))); l.Add(WorkSettingsForm.Kv("token", FieldBox(2, 0))) }
        case "meet": if show { l.Add(WorkSettingsForm.Kv("meet_url", FieldBox(0, 0))); l.Add(WorkSettingsForm.Kv("meet_before", Rectangle(PaneR().X + Sc(22) + Sc(56), FieldY(1) + Sc(6), Sc(56), Sc(28)))) }
        case "rain": if show { l.Add(WorkSettingsForm.Kv("rain_place", FieldBox(0, 0))) }
        case "net": if show { l.Add(WorkSettingsForm.Kv("vpn_host", FieldBox(0, 0))) }
        case "worklog": if show { var r = FieldBox(0, 0); r.Width -= Sc(88); l.Add(WorkSettingsForm.Kv("worklog_dir", r)) }
        case "claude": break   // mac: 沒有 WSL：不擺「別的資料夾」的 claude_dir／codex_dir（C#：advOpen 時擺 FieldBox(1)、FieldBox(2)）
        default: break
        }
        for kv in l {
            guard let t = boxes.Get(kv.Key) else { continue }
            let r = kv.Value
            let th = t.PreferredHeight
            let o: Point = AutoScroll ? AutoScrollPosition : Point.Empty   // 捲過的話，輸入框跟著位移
            t.Bounds = Rectangle(r.X + 3 * U + o.X, r.Y + Math.Max(U, (r.Height - th) / 2) + o.Y, r.Width - 6 * U, Math.Min(th, r.Height - 2 * U))
            t.BackColor = bad.Contains(kv.Key) ? Pix.C(0xFDECEA) : WorkSettingsForm.Paper
            t.tf?.backgroundColor = t.BackColor.ns   // mac: TextBox 的 BackColor 不會自己套到 NSTextField
            t.Visible = true
            shown.Add(kv.Key)
        }
    }
    // 輸入框的提示字（灰字，打字就不見）
    // mac: EM_SETCUEBANNER → NSTextField 的 placeholder（TextBox.PlaceholderText）；Dictionary<TextBox, string> → 用 ObjectIdentifier 當 key
    let cues = Dict<ObjectIdentifier, String>()
    func Cue(_ t: TextBox, _ text: String?) {
        let k = ObjectIdentifier(t)
        if let was = cues.Get(k), was == (text ?? "") { return }
        cues[k] = text ?? ""
        t.PlaceholderText = text ?? ""
    }
    func KeyOf(_ t: TextBox) -> String { for kv in boxes { if kv.Value === t { return kv.Key } }; return "" }
    static func Kv(_ k: String, _ r: Rectangle) -> KeyValuePair<String, Rectangle> { return KeyValuePair<String, Rectangle>(k, r) }

    // ================= 畫 =================
    func Txt(_ g: Graphics, _ s: String, _ f: FontT, _ r: Rectangle, _ c: Color, _ fl: TextFormatFlags) { PixText.DrawText(g, World.NoEmoji(s), f, r, c, fl.union(TextFormatFlags.NoPrefix)) }
    func Hit(_ id: String, _ r: Rectangle, _ stop: Bool) { hits[id] = r; if stop { stops.Add(id) } }

    override func OnPaint(_ e: PaintEventArgs) {
        let g = e.Graphics
        g.SmoothingMode = SmoothingMode.None
        hits.Clear(); stops.Clear()
        if AutoScroll { g.TranslateTransform(Double(AutoScrollPosition.X), Double(AutoScrollPosition.Y)) }   // 螢幕太矮：整個內容一起捲
        let W0 = Sc(600), H0 = Sc(600), F = 4 * U, crown = Sc(56)
        Pix.Wood(g, 0, 0, W0, H0, U, false, 23)
        Pix.Panel(g, F, crown, W0 - 2 * F, H0 - crown - F, U, false)
        let t = "工作設定"
        let tw = Pix.TextW(t, plateF)
        let plw = tw + 14 * U, plh = Sc(34)
        let pr = Rectangle((W0 - plw) / 2, (crown - plh) / 2 + U / 2, plw, plh)
        Pix.Plate(g, t, plateF, pr, U)
        Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.X - 9 * U, pr.Y + plh / 2 - 2 * U, U)
        Pix.Mono(g, Pix.HEART, Pix.C(0xF27A90), pr.Right + 4 * U, pr.Y + plh / 2 - 2 * U, U)
        ViewSwitch(g, W0)
        if viewKind == "grid" { PaintGrid(g) } else { PaintList(g) }
        let by = H0 - Sc(64), bh = Sc(44)
        self.Button(g, "cancel", "取消", Rectangle(Sc(30), by, Sc(130), bh), false)
        self.Button(g, "save", "儲存", Rectangle(W0 - Sc(30) - Sc(160), by, Sc(160), bh), true)
        for kv in boxes { if shown.Contains(kv.Key) { let i = stops.IndexOf("tbpos:" + kv.Key); if i >= 0 { stops[i] = "tb:" + kv.Key } } }
        stops.RemoveAll { (s: String) -> Bool in s.StartsWith("tbpos:") }
        // 鍵盤焦點：虛線框
        if focusStop != "" && !focusStop.StartsWith("tb:"), let fr = hits.Get(focusStop) {
            let p = Pen(Pix.Ink, Math.Max(2, U))
            p.DashStyle = DashStyle.Dash
            g.DrawRectangle(p, fr.X + 2 * U, fr.Y + 2 * U, fr.Width - 4 * U - 1, fr.Height - 4 * U - 1)   // 鍵盤焦點：往內縮的深木色虛線
        }
        // mac: 捲軸（Windows 是系統畫的）
        if AutoScroll { g.TranslateTransform(Double(-AutoScrollPosition.X), Double(-AutoScrollPosition.Y)); PaintScrollBar(g) }
    }

    func ViewSwitch(_ g: Graphics, _ W0: Int) {
        let ids: [String] = ["grid", "list"], names: [String] = ["格子", "清單"]
        let bw = Sc(64), bh = Sc(26)
        let x = W0 - Sc(14) - 2 * bw - 3 * U, y = Sc(13)
        Pix.Round(g, Pix.Ink, x, y, 2 * bw + 3 * U, bh + 2 * U, U)
        for i in 0..<2 {
            let r = Rectangle(x + U + i * (bw + U), y + U, bw, bh)
            let on = viewKind == ids[i], hot = hoverId == "view:" + ids[i]
            let face: Color = on ? Pix.C(0xF6C453) : (hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0))
            Pix.Box(g, face, r.X, r.Y, r.Width, r.Height)
            if on { Pix.Box(g, Pix.C(0xFBE7BA), r.X, r.Y, r.Width, U); Pix.Box(g, Pix.C(0xC8902C), r.X, r.Bottom - U, r.Width, U) }
            let art: [String] = i == 0 ? ["##.##", "##.##", ".....", "##.##", "##.##"] : ["#.###", ".....", "#.###", ".....", "#.###"]
            let aw = 5 * U, txw = Pix.TextW(names[i], segF)
            let sx = r.X + (r.Width - aw - Sc(6) - txw) / 2
            Pix.Mono(g, art, Pix.Ink, sx, r.Y + (r.Height - aw) / 2, U)
            Txt(g, names[i], segF, Rectangle(sx + aw + Sc(6), r.Y, txw + 4, r.Height), on ? Pix.TextC : WorkSettingsForm.Sub, Pix.LeftMid)
            Hit("view:" + ids[i], r, true)
        }
    }

    // ---- 格子：3×3 ----
    func PaintGrid(_ g: Graphics) {
        let W0 = Sc(600)
        Txt(g, "打開的，公仔會提醒你", labF, Rectangle(0, Sc(66), W0, Sc(26)), Pix.C(0x7A4A22), Pix.Mid)
        let x0 = Sc(30), y0 = Sc(98), tw = Sc(172), th = Sc(132), gx = Sc(12), gy = Sc(8)
        for i in 0..<WorkSettingsForm.SRC.count {
            let r = Rectangle(x0 + (i % 3) * (tw + gx), y0 + (i / 3) * (th + gy), tw, th)
            Tile(g, WorkSettingsForm.SRC[i], r)
        }
    }

    func Tile(_ g: Graphics, _ s: Src, _ r: Rectangle) {
        let on = On(s.Id), lk = Lock(s.Id), hot = hoverId == "tile:" + s.Id
        let edge: Color = lk ? Pix.Dim : (on ? Pix.C(0x2F6E24) : Pix.Ink)
        var fill: Color
        if lk { fill = Pix.C(0xF3EADB) }
        else if on { fill = hot ? Pix.C(0xDFF0CC) : Pix.C(0xEAF6DC) }
        else { fill = hot ? Pix.C(0xFFF3D6) : WorkSettingsForm.Paper }
        let foot: Color = lk ? Pix.C(0xE2D6C0) : (on ? Pix.C(0xBFE0A6) : Pix.C(0xEAD7B4))
        Pix.Round(g, edge, r.X, r.Y, r.Width, r.Height, U)
        Pix.Box(g, fill, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U)
        Pix.Box(g, foot, r.X + U, r.Bottom - 4 * U, r.Width - 2 * U, 3 * U)
        Hit("tile:" + s.Id, r, true)
        Pix.Mono(g, ["#..", "##.", "###", "##.", "#.."], Pix.C(0x8A6A4C), r.Right - Sc(16), r.Y + Sc(8), U)
        // 圖示＋名字（同一行，置中）
        var art: [String] = []
        var pal = Dict<Character, Color>()
        WorkSettingsForm.IconArt(s.Icon, &art, &pal)
        let iu = Math.Max(2, Sc(4))
        let iw = art[0].Length * iu, ih = art.count * iu
        if lk { for ch in pal.Keys { pal[ch] = Pix.Mix(pal[ch], Pix.C(0xF3EADB), 0.55) } }   // 鎖住：圖示變淡
        Pix.Art(g, art, pal, r.X + (r.Width - iw) / 2, r.Y + Sc(10) + (Sc(32) - ih) / 2, iu)
        let nm = s.Id == "claude" ? "Claude Code、Codex" : s.Name
        let nf: FontT = Pix.TextW(nm, tileNameF) > r.Width - Sc(16) ? labF : tileNameF
        Txt(g, nm, nf, Rectangle(r.X + Sc(4), r.Y + Sc(44), r.Width - Sc(8), Sc(22)), lk ? Pix.C(0x806A50) : Pix.TextC, Pix.Mid)
        if lk {
            Txt(g, "先打開", subF, Rectangle(r.X, r.Y + Sc(74), r.Width, Sc(16)), WorkSettingsForm.MuteC, Pix.Mid)
            Txt(g, "GitLab 或 GitHub", subF, Rectangle(r.X, r.Y + Sc(90), r.Width, Sc(16)), WorkSettingsForm.MuteC, Pix.Mid)
            return
        }
        var st = "", kind = ""
        var link: String? = nil
        StateOf(s.Id, &st, &kind, &link)
        if link != nil {
            let how = HowText(s.Id)
            let a = Pix.TextW(st, subF), b = Pix.TextW(how, subF), gap = Sc(8)
            let sx = r.X + (r.Width - a - gap - b) / 2
            Txt(g, st, subF, Rectangle(sx, r.Y + Sc(68), a + 4, Sc(18)), KindC(kind), Pix.LeftMid)
            let lr = Rectangle(sx + a + gap, r.Y + Sc(66), b + 2, Sc(22))
            Txt(g, how, subF, Rectangle(lr.X, r.Y + Sc(68), b + 4, Sc(18)), WorkSettingsForm.LinkC, Pix.LeftMid)
            Pix.Box(g, WorkSettingsForm.LinkC, lr.X, r.Y + Sc(68) + Sc(16), b, Math.Max(1, U / 2))
            Hit("howto:" + s.Id, Rectangle(sx - Sc(4), r.Y + Sc(63), a + gap + b + Sc(8), Sc(28)), true)
        }
        else { Txt(g, st, subF, Rectangle(r.X, r.Y + Sc(68), r.Width, Sc(18)), KindC(kind), Pix.Mid) }
        Seg(g, s.Id, Rectangle(r.X + (r.Width - Sc(84)) / 2, r.Bottom - Sc(44), Sc(84), Sc(30)))
    }

    // 關｜開
    func Seg(_ g: Graphics, _ id: String, _ r: Rectangle) {
        let on = On(id), dis = Lock(id) || Missing(id).Contains("tool"), hot = hoverId == "sw:" + id
        Pix.Round(g, dis ? Pix.Dim : Pix.Ink, r.X, r.Y, r.Width, r.Height, U)
        let half = (r.Width - 3 * U) / 2
        for i in 0..<2 {
            let c = Rectangle(r.X + U + i * (half + U), r.Y + U, half, r.Height - 2 * U)
            let pick = (i == 1) == on
            var face: Color
            if dis { face = Pix.C(0xF3EADB) }
            else if pick { face = i == 1 ? Pix.C(0x7CC25F) : Pix.C(0xE2D6C0) }
            else { face = hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0) }
            Pix.Box(g, face, c.X, c.Y, c.Width, c.Height)
            if pick && !dis {
                Pix.Box(g, i == 1 ? Pix.C(0xB6E29E) : Pix.C(0xF1E8D8), c.X, c.Y, c.Width, U)
                Pix.Box(g, i == 1 ? Pix.C(0x4E9A3A) : Pix.C(0xC9B79A), c.X, c.Bottom - U, c.Width, U)
            }
            var tc: Color
            if dis { tc = Pix.C(0x806A50) }
            else if pick && i == 1 { tc = Pix.C(0x163D10) }
            else { tc = pick ? Pix.TextC : WorkSettingsForm.Sub }
            Txt(g, i == 0 ? "關" : "開", segF, c, tc, Pix.Mid)
        }
        Hit("sw:" + id, r, true)
    }

    // ---- 清單：左邊來源、右邊要填的 ----
    func PaintList(_ g: Graphics) {
        let p = PaneR()
        let x = Sc(30), wd = p.X - x + U
        // 全部
        let all = Rectangle(x, p.Y, wd - U, Sc(36))
        Tab(g, all, "all", "全部", nil, false, "")
        let ty = p.Y + Sc(42), th = Sc(36)
        for i in 0..<WorkSettingsForm.SRC.count {
            let s = WorkSettingsForm.SRC[i]
            let r = Rectangle(x, ty + i * (th + U), wd, th)
            if s.Id != sel { Tab(g, r, "tab:" + s.Id, s.Short, s.Icon, false, Dot(s.Id)) }
        }
        // 右邊的紙（先畫，選到的頁籤蓋上去接起來）
        Pix.Box(g, Pix.Ink, p.X, p.Y, p.Width, p.Height)
        Pix.Box(g, WorkSettingsForm.Paper, p.X + U, p.Y + U, p.Width - 2 * U, p.Height - 2 * U)
        for i in 0..<WorkSettingsForm.SRC.count {
            let s = WorkSettingsForm.SRC[i]
            if s.Id == sel { Tab(g, Rectangle(x, ty + i * (th + U), wd, th), "tab:" + s.Id, s.Short, s.Icon, true, Dot(s.Id)) }
        }
        if let cur = WorkSettingsForm.Find(sel) { PaintPane(g, cur, p) }
    }

    func Dot(_ id: String) -> String {
        guard let s = WorkSettingsForm.Find(id) else { return "" }
        if pending.Contains(id) { return "warn" }
        var st = "", kind = ""
        var link: String? = nil
        StateOf(id, &st, &kind, &link)
        if v[s.Key] != "1" || Lock(id) { return kind == "bad" ? "bad" : "" }
        if kind == "bad" { return "bad" }
        return kind == "warn" ? "warn" : (On(id) ? "on" : "")
    }

    func Tab(_ g: Graphics, _ r: Rectangle, _ id: String, _ name: String, _ icon: String?, _ selTab: Bool, _ dot: String) {
        let hot = hoverId == id
        if selTab {
            Pix.Box(g, Pix.Ink, r.X, r.Y, r.Width, r.Height)
            Pix.Box(g, WorkSettingsForm.Paper, r.X + U, r.Y + U, r.Width, r.Height - 2 * U)
            Pix.Box(g, Pix.C(0xF6C453), r.X + U, r.Y + U, 2 * U, r.Height - 2 * U)
        }
        else {
            Pix.Box(g, Pix.Ink, r.X, r.Y, r.Width, r.Height)
            Pix.Box(g, hot ? Pix.C(0xFFF3D6) : Pix.C(0xF3E6CC), r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U)
            Pix.Box(g, Pix.C(0xE2CFAE), r.X + U, r.Bottom - 2 * U, r.Width - 2 * U, U)
        }
        var tx = r.X + Sc(10)
        if let ic = icon {
            var art: [String] = []
            var pal = Dict<Character, Color>()
            WorkSettingsForm.IconArt(ic, &art, &pal)
            Pix.Art(g, art, pal, tx, r.Y + (r.Height - art.count * U) / 2, U)
            tx += art[0].Length * U + Sc(8)
        }
        else {
            Pix.Mono(g, ["##.##", "##.##", ".....", "##.##", "##.##"], Pix.Ink, tx, r.Y + (r.Height - 5 * U) / 2, U)
            tx += 5 * U + Sc(8)
        }
        Txt(g, name, labF, Rectangle(tx, r.Y, r.Right - tx - Sc(20), r.Height), Pix.TextC, Pix.LeftMid)
        if icon != nil {
            let ds = 5 * U, dx = r.Right - Sc(14) - ds, dy = r.Y + (r.Height - ds) / 2
            var dc: Color
            if dot == "on" { dc = Pix.C(0x5FB04A) }
            else if dot == "warn" { dc = Pix.C(0xE0A03A) }
            else { dc = dot == "bad" ? Pix.C(0xC95454) : WorkSettingsForm.Paper }
            Pix.Round(g, dot == "" ? Pix.C(0x8A6A4C) : Pix.Ink, dx, dy, ds, ds, U)
            Pix.Box(g, dc, dx + U, dy + U, ds - 2 * U, ds - 2 * U)
            if dot == "bad" { Pix.Box(g, Color.White, dx + 2 * U, dy + 2 * U, U, U) }
            if dot == "warn" { Pix.Box(g, Pix.Ink, dx + 2 * U, dy + 2 * U, U, U) }
        }
        Hit(id, r, true)
    }

    func PaintPane(_ g: Graphics, _ s: Src, _ p: Rectangle) {
        let x = p.X + Sc(22), y = p.Y + Sc(18), right = p.Right - Sc(22)
        var art: [String] = []
        var pal = Dict<Character, Color>()
        WorkSettingsForm.IconArt(s.Icon, &art, &pal)
        let iu = Math.Max(2, Sc(3))
        Pix.Art(g, art, pal, x, y + (Sc(30) - art.count * iu) / 2, iu)
        Txt(g, s.Name, nameF, Rectangle(x + art[0].Length * iu + Sc(10), y, Sc(220), Sc(30)), Pix.TextC, Pix.LeftMid)
        if !Lock(s.Id) { Seg(g, s.Id, Rectangle(right - Sc(84), y, Sc(84), Sc(30))) }
        // 一句狀態
        let ly = p.Y + Sc(58)
        var st = "", kind = ""
        var link: String? = nil
        StateOf(s.Id, &st, &kind, &link)
        let lead = LeadText(s.Id)
        var lc: Color
        if pending.Contains(s.Id) || kind == "warn" { lc = WorkSettingsForm.WarnC }
        else if kind == "bad" { lc = WorkSettingsForm.BadC }
        else { lc = kind == "ok" && lead == st ? WorkSettingsForm.OkC : WorkSettingsForm.MuteC }
        let lw = Pix.TextW(lead, labF)
        Txt(g, lead, labF, Rectangle(x + Sc(28), ly, lw + 4, Sc(22)), lc, Pix.LeftMid)
        if link != nil {
            let how = HowText(s.Id)
            let b = Pix.TextW(how, labF)
            let lr = Rectangle(x + Sc(28) + lw + Sc(10), ly, b + 2, Sc(22))
            Txt(g, how, labF, lr, WorkSettingsForm.LinkC, Pix.LeftMid)
            Pix.Box(g, WorkSettingsForm.LinkC, lr.X, lr.Y + Sc(19), b, Math.Max(1, U / 2))
            Hit("howto:" + s.Id, lr, true)
        }
        let show = v[s.Key] == "1" || pending.Contains(s.Id)
        // mac: 沒有 WSL：Claude、Codex 那頁沒有「別的資料夾」，也就不畫分隔的點線（C#：s.Id == "claude" || …）
        if show && WorkSettingsForm.FILL.ContainsKey(s.Id) {
            var dx = x
            while dx + U <= right { Pix.Box(g, Pix.C(0xD8BF94), dx, p.Y + Sc(90), U, U); dx += 3 * U }
            PaintForm(g, s, p, x, right)
        }
        // 提醒會像這樣
        let sy = p.Bottom - Sc(86)
        var say: String = s.Say
        if s.Id == "meet" { let mb = v["meet_before"].Trim(); say = (mb == "" ? "5" : mb) + " 分鐘後開會" }
        let pic: Bitmap! = w.WorkPalPic(Math.Max(3, CInt(Math.Round(3 * d))))
        let pw = pic != nil ? pic.Width : 0, ph = pic != nil ? pic.Height : 0
        let bw = Pix.TextW(say, labF) + Sc(20), bh = Sc(28)
        let bx = right - pw - Sc(8) - bw
        var byy = p.Bottom - Sc(6) - ph / 2 - bh / 2 - Sc(4)
        if pic == nil { byy = sy + Sc(26) }
        Txt(g, "提醒會像這樣", subF, Rectangle(x, byy, Sc(120), bh), WorkSettingsForm.Sub, Pix.LeftMid)   // 跟泡泡同一行
        Pix.Round(g, Pix.C(0x7A4A22), bx, byy, bw, bh, U)
        Pix.Box(g, Color.White, bx + U, byy + U, bw - 2 * U, bh - 2 * U)
        for i in 0..<4 { Pix.Box(g, Pix.C(0x7A4A22), bx + bw - U + i * U, byy + bh / 2 - (4 - i) * U / 2, U, (4 - i) * U) }
        Txt(g, say, labF, Rectangle(bx, byy, bw, bh), Pix.TextC, Pix.Mid)
        if pic != nil { g.DrawImageUnscaled(pic, right - pw, p.Bottom - ph - Sc(6)) }
    }

    // 沒裝＝怎麼裝；裝了沒登入＝怎麼登入
    func HowText(_ id: String) -> String { return Tool(id) == "nologin" ? "怎麼登入" : "怎麼裝" }
    func HowUrl(_ id: String) -> String {
        let login = Tool(id) == "nologin"
        if id == "github" { return login ? "https://cli.github.com/manual/gh_auth_login" : WorkSettingsForm.HowGh }
        return login ? "https://gitlab.com/gitlab-org/cli/-/blob/main/docs/source/auth/login.md" : WorkSettingsForm.HowGlab
    }
    // 紅色那格：空的＝要先填；填了但不對＝說哪裡不對
    func BadText() -> String {
        for k in bad {
            guard let t = boxes.Get(k), t.Text.Trim() != "" else { continue }
            switch k {
            case "meet_url": return "紅色那格不是網址"
            case "jira_email": return "紅色那格不是信箱"
            case "vpn_host": return "紅色那格不是主機名稱"
            case "worklog_dir": return "紅色那格的資料夾找不到"
            case "meet_before": return "紅色那格要填 1 到 120"
            default: break
            }
        }
        return "要先填紅色的格子"
    }

    func LeadText(_ id: String) -> String {
        guard let s = WorkSettingsForm.Find(id) else { return "" }
        var st = "", kind = ""
        var link: String? = nil
        StateOf(id, &st, &kind, &link)
        if pending.Contains(id) && Missing(id).Count > 0 { return bad.Count > 0 ? BadText() : (WorkSettingsForm.FILL.Get(id) ?? "") }
        if bad.Count > 0 && WorkSettingsForm.FILL.ContainsKey(id) { return BadText() }
        if link != nil || kind == "bad" { return st }
        if Lock(id) { return st }
        if kind == "warn", let need = WorkSettingsForm.NEED.Get(id) { return need }
        if let sub = s.Sub { return sub }
        return kind == "ok" ? st : ""
    }

    func PaintForm(_ g: Graphics, _ s: Src, _ p: Rectangle, _ x: Int, _ right: Int) {
        switch s.Id {
        case "claude":
            // mac: 沒有 WSL：不放「別的資料夾」（C# 在這裡畫展開箭頭、「別的資料夾」連結 Hit("adv")，展開時 Claude／Codex 資料夾兩格）
            break
        case "jira":
            Field(g, 0, "網站", "jira_site", 0, "yourteam.atlassian.net")
            Field(g, 1, "信箱", "jira_email", 0, "you@yourteam.com")
            Field(g, 2, "API token", "token", 0, w.HasJiraToken() ? "已經存了，要換才貼" : "貼上 token")
            do {
                let ny = FieldY(3) - Sc(4)
                Txt(g, "token 只存在這台電腦", subF, Rectangle(x, ny, Sc(200), Sc(20)), WorkSettingsForm.Sub, Pix.LeftMid)
                let how = "去建立 token"
                let b = Pix.TextW(how, subF)
                let lr = Rectangle(right - b, ny, b + 2, Sc(22))
                Txt(g, how, subF, Rectangle(lr.X, ny, b + 4, Sc(20)), WorkSettingsForm.LinkC, Pix.LeftMid)
                Pix.Box(g, WorkSettingsForm.LinkC, lr.X, ny + Sc(17), b, Math.Max(1, U / 2))
                Hit("howto:jira", lr, true)
            }
        case "meet":
            Field(g, 0, "行事曆網址", "meet_url", 0, "https:// 或 webcal://")
            do {
                let ry = FieldY(1) + Sc(6)
                Txt(g, "開會前", labF, Rectangle(x, ry, Sc(56), Sc(28)), Pix.TextC, Pix.LeftMid)
                Frame(g, Rectangle(x + Sc(56), ry, Sc(56), Sc(28)), "meet_before")
                stops.Add("tbpos:meet_before")
                Txt(g, "分鐘提醒", labF, Rectangle(x + Sc(122), ry, Sc(100), Sc(28)), Pix.TextC, Pix.LeftMid)
                let cy = ry + Sc(42), cs = Sc(20)
                let q = v["meet_quiet"] == "1"
                Pix.Round(g, Pix.Ink, x, cy, cs, cs, U)
                Pix.Box(g, q ? Pix.C(0x5FB04A) : WorkSettingsForm.Paper, x + U, cy + U, cs - 2 * U, cs - 2 * U)
                if q { Pix.Mono(g, Pix.CHECK, Color.White, x + (cs - 5 * U) / 2, cy + (cs - 5 * U) / 2, U) }
                Txt(g, "開會時自動安靜", labF, Rectangle(x + cs + Sc(10), cy - Sc(2), Sc(160), cs + Sc(4)), Pix.TextC, Pix.LeftMid)
                Hit("quiet", Rectangle(x, cy, cs + Sc(10) + Pix.TextW("開會時自動安靜", labF), cs), true)
            }
        case "rain": Field(g, 0, "地點", "rain_place", 0, "台北 或 25.03,121.56")
        case "net": Field(g, 0, "主機", "vpn_host", 0, "intranet.example.com")
        case "worklog":
            Field(g, 0, "資料夾", "worklog_dir", Sc(88), "/Users/me/Documents/日誌")   // mac: C# 是 C:\Users\me\Documents\日誌
            do {
                let fb = FieldBox(0, 0)
                let br = Rectangle(fb.Right - Sc(80), fb.Y, Sc(80), fb.Height)
                SmallButton(g, "pickdir", "選資料夾", br)
            }
        default: break
        }
    }

    // 一格：上面一行字、下面輸入框的像素框（空的時候畫提示字）
    func Field(_ g: Graphics, _ i: Int, _ label: String, _ key: String, _ cut: Int, _ ph: String) {
        var r = FieldBox(i, 0)
        if cut > 0 { r.Width -= cut }
        Txt(g, label, labF, Rectangle(r.X, FieldY(i) - Sc(2), Sc(200), Sc(20)), bad.Contains(key) ? WorkSettingsForm.BadC : Pix.TextC, Pix.LeftMid)
        Frame(g, r, key)
        stops.Add("tbpos:" + key)
        if let t = boxes.Get(key) { Cue(t, ph) }   // 空的時候的提示字：交給輸入框自己畫（mac: placeholder），離屏時 PaintTo 畫
    }

    func Frame(_ g: Graphics, _ r: Rectangle, _ key: String) {
        let isBad = bad.Contains(key), foc = focusStop == "tb:" + key
        Pix.Round(g, isBad ? WorkSettingsForm.BadC : (foc ? Pix.Ink : Pix.C(0x8A6A4A)), r.X, r.Y, r.Width, r.Height, U)
        if foc { Pix.Round(g, Pix.Ink, r.X - U, r.Y - U, r.Width + 2 * U, r.Height + 2 * U, U) }
        Pix.Box(g, isBad ? Pix.C(0xFDECEA) : WorkSettingsForm.Paper, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U)
        Pix.Box(g, Pix.C(0xEAD7B4), r.X + U, r.Y + U, r.Width - 2 * U, U)
    }

    func SmallButton(_ g: Graphics, _ id: String, _ text: String, _ r: Rectangle) {
        let hot = hoverId == id
        Pix.Round(g, Pix.Ink, r.X, r.Y, r.Width, r.Height, U)
        Pix.Box(g, hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0), r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U)
        Pix.Box(g, Pix.C(0xDCC6A2), r.X + U, r.Bottom - 2 * U, r.Width - 2 * U, U)
        Txt(g, text, subF, Rectangle(r.X, r.Y, r.Width, r.Height - U), Pix.TextC, Pix.Mid)
        Hit(id, r, true)
    }

    func Button(_ g: Graphics, _ id: String, _ text: String, _ r: Rectangle, _ main: Bool) {
        let hot = hoverId == id
        var face: Color
        if main { face = hot ? Pix.C(0xFFD36A) : Pix.C(0xF6C453) }
        else { face = hot ? Pix.C(0xFFF3D6) : Pix.C(0xFFFBF0) }
        let shade: Color = main ? Pix.C(0xC8902C) : Pix.C(0xDCC6A2)
        Pix.Round(g, Pix.Ink, r.X, r.Y, r.Width, r.Height, U)
        Pix.Box(g, face, r.X + U, r.Y + U, r.Width - 2 * U, r.Height - 2 * U)
        Pix.Box(g, shade, r.X + U, r.Bottom - 3 * U, r.Width - 2 * U, 2 * U)
        Pix.Box(g, Pix.Mix(face, Color.White, 0.6), r.X + 2 * U, r.Y + U, r.Width - 4 * U, U)
        Txt(g, text, btnF, Rectangle(r.X, r.Y, r.Width, r.Height - 2 * U), Pix.TextC, Pix.Mid)
        Hit(id, r, true)
    }

    // ---- 圖示（8×8 以內的像素圖）----
    static func IconArt(_ n: String, _ art: inout [String], _ pal: inout Dict<Character, Color>) {
        pal = Dict<Character, Color>()
        pal["k"] = Pix.Ink
        switch n {
        case "claude": art = ["kkkkkkkk", "kddddddk", "kdgddddk", "kddgdddk", "kdgdggdk", "kddddddk", "kkkkkkkk"]; pal["d"] = Pix.C(0x5A4632); pal["g"] = Pix.C(0xF4A06A)
        case "jira": art = ["kkkkkkkk", "kbbbbbbk", "kbwwwwbk", ".kbbbbk.", "kbwwwbbk", "kbbbbbbk", "kkkkkkkk"]; pal["b"] = Pix.C(0x6E9BD8); pal["w"] = Pix.C(0xE4EEFA)
        case "gitlab": art = [".k...k.", "kpk.kpk", ".k...k.", ".k..k..", ".k.k...", ".kk....", "kpk....", ".k....."]; pal["p"] = Pix.C(0xE2763A)
        case "github": art = [".k...k.", "kpk.kpk", ".k...k.", ".k..k..", ".k.k...", ".kk....", "kpk....", ".k....."]; pal["p"] = Pix.C(0x7A8696)
        case "tag": art = ["kkkkk...", "kyyyyk..", "kywyyyk.", "kyyyyyyk", "kyyyyyk.", "kyyyyk..", "kkkkk..."]; pal["y"] = Pix.C(0xF0C24E); pal["w"] = Pix.C(0xFFF6E4)
        case "meet": art = [".k...k..", "kkkkkkkk", "krrrrrrk", "kwwwwwwk", "kwkwkwwk", "kwwwwwwk", "kwkwwwwk", "kkkkkkkk"]; pal["r"] = Pix.C(0xE07856); pal["w"] = Pix.C(0xFFFDF7)
        case "rain": art = ["...kkk..", ".kkwwwk.", "kwwwwwwk", "kwwwwwwk", ".kkkkkk.", ".b..b..b", "b..b..b."]; pal["w"] = Pix.C(0xE9EEF5); pal["b"] = Pix.C(0x4F86C9)
        case "net": art = ["..k..k..", "..k..k..", ".kkkkkk.", ".kggggk.", ".kggggk.", "..kggk..", "...kk...", "...k...."]; pal["g"] = Pix.C(0x9FC3E6)
        default: art = ["kkk.....", "kyyk....", "kkkkkkkk", "kyyyyyyk", "kyyyyyyk", "kyyyyyyk", "kkkkkkkk"]; pal["y"] = Pix.C(0xF0C24E)   // folder
        }
    }
}
