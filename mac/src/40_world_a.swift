// 40_world_a.swift — port of DeskPals.cs lines 5407–6817 (World partial #1)
// Owns the `final class World` declaration. Other World partials are spliced in at //@@BODY World.
import Foundation
import AppKit
import Carbon

final class World: Form {
    static var DataDir: String = World.DataDirInit()
    static func DataDirInit() -> String {
        var d = ProcessInfo.processInfo.environment["DESKPALS_DATA_DIR"] ?? ""
        // mac: ~/Library/Application Support/DeskPals（Windows 是 %LOCALAPPDATA%\DeskPals）
        if d.isEmpty { d = NSHomeDirectory() + "/Library/Application Support/DeskPals" }
        return d
    }

    let pipeName: String
    var defaultPet: String = ""
    var lineup: String = Pal.Fallback                  // 現在是哪一櫃
    var TubbyLineup: Bool { return lineup == Pal.Teletubbies }   //@fan
    let S: Int
    let k: Double
    let rnd = Random()
    let Pets = List<Pet>()
    let timer = Timer()
    let clock = Stopwatch.StartNew()
    var Now: Double = 0
    var lastT: Double = 0

    var screens = Screen.AllScreens
    var Wins = List<WinInfo>()
    var Cands = Dict<IntPtr, WinInfo>()
    var Plats = List<Plat>()
    var known: HashSet<IntPtr>! = nil
    var lastFg: IntPtr = 0
    // mac: 前景視窗＝最前面那個 App 的第一個 layer-0 視窗（Scan 時順便記下來）
    var fgWinMac: IntPtr = 0
    var fgPidMac: Int32 = 0

    var shelf: ShelfForm! = nil
    var fx: FxForm! = nil
    let webs = List<CobwebForm>()
    let clients = List<Client>()
    var closing = false

    var Night = false, Hidden = false
    var SeasonNow = ""
    var birthday = ""
    var nightChecked = -1
    var forceNight = ProcessInfo.processInfo.environment["DESKPALS_FORCE_DARK"] == "1" ? 1 : -1
    var userHidden = false, sharing = false, fsNow = false
    var CursorStill: Double = 0
    var lastCursor = Point(0, 0)
    var nextScan: Double = 0, newWinCd: Double = 3, fgCd: Double = 8, danceCd: Double = 30, waitCd: Double = 0, shelfT: Double = 0, usageT: Double = 0, proxT: Double = 5
    var typingStreak = 0
    var sysIdle = false
    var restMin: Double = 50, idleMin: Double = 5, sessionStart: Double = 0

    var active: Pet! = nil                            // 最近一隻被放出來的（側邊欄跟著他）
    let outOrder = List<Pet>()
    var favPin = ""
    let usage = Dict<String, Double>()

    // ---------- 延遲動作 ----------
    let later = List<(Double, () -> Void)>()

    // ================= 主迴圈 =================
    var perfSum: Double = 0, perfMax: Double = 0, perfT: Double = 0
    var perfN = 0, perfLogs = 0

    // ================= 球 =================
    var ballF: BallForm! = nil
    var BallOn = false
    var Bx: Double = 0, By: Double = 0, Bvx: Double = 0, Bvy: Double = 0, BallIdle: Double = 0, CatchCd: Double = 0
    var Holder: Pet! = nil
    var BallKind = "tennis"
    var foulCd: Double = 0, umpCd: Double = 0

    // ---------- 選單 ----------
    var pmenu: PixelMenu! = nil
    var menuPrevFg: IntPtr = 0
    var shelfMenu: ContextMenuStrip! = nil

    var lastBroadcast = ""
    // mac: socket 的 listen fd（收工時關掉、刪掉 socket 檔）
    var listenFd: Int32 = -1

    init(_ pipeName: String, _ pet: String, _ lineupArg: String) {
        self.pipeName = pipeName
        World.OrigMigrate()   // 舊的像素續命小隊的資料轉給新三隻（只做一次，51_original.swift）
        // 哪一櫃：有傳就用（並記住），沒傳（開機捷徑）就照上次的
        lineup = Pal.NormLineup(lineupArg.isEmpty ? World.StartLineup() : lineupArg)   // 全新安裝：續命小隊（51_original.swift）
        if !lineupArg.isEmpty { World.WriteText("lineup.txt", lineup) }
        // mac: 用 point，dpi 一律當 96
        let dpi: Double = 96
        S = Math.Max(3, CInt(Math.Round(4 * dpi / 96.0)))
        k = Double(S) / 3.0
        super.init()
        defaultPet = DefaultPetFor(pet)
        ShowInTaskbar = false
        var seed = Environment.TickCount
        for p in Pal.Lineup(lineup) { Pets.Add(Pet(self, p, S, seed)); seed += 1 }
    }

    // 只給預覽用：不開任何視窗
    init(_ S: Int, _ lineupId: String) {
        pipeName = ""; self.S = S; k = Double(S) / 3.0
        super.init()
        lineup = Pal.NormLineup(lineupId); defaultPet = "po"   //@fan
        // <public> lineup = Pal.NormLineup(lineupId); defaultPet = "duoduo"
        var seed = 1
        for p in Pal.Lineup(lineup) { Pets.Add(Pet(self, p, S, seed)); seed += 1 }
    }

    init(_ S: Int) {
        pipeName = ""; self.S = S; k = Double(S) / 3.0
        super.init()
        defaultPet = "spidey"   //@fan
        // <public> defaultPet = "duoduo"
        var seed = 1
        for p in Pal.Lineup(Pal.Fallback) { Pets.Add(Pet(self, p, S, seed)); seed += 1 }
    }

    override func SetVisibleCore(_ value: Bool) { super.SetVisibleCore(false) }

    // mac: WndProc 收 WM_HOTKEY 改成 Carbon 快速鍵（RegisterHotKeyMac），這裡不用覆寫

    //@@BODY World
}

extension World {
    func DefaultPetFor(_ pet: String) -> String {
        for id in Pal.LineupIds(lineup) { if id == pet { return pet } }
        if lineup == Pal.Mine { let mi = Pal.MineIds(); if mi.count > 0 { return mi[0] } }
        return lineup == Pal.Teletubbies ? "po" : (lineup == Pal.Pikmin ? "pkred" : (Pal.IsSquad(lineup) ? Pal.SqIds(lineup)[0] : "spidey"))   //@fan
        // <public> return Pal.IsSquad(lineup) ? Pal.SqIds(lineup)[0] : "duoduo"
    }

    // 每一櫃各自記：誰在外面、最近一隻、最愛（經典一櫃沿用原本的檔名）
    func LF(_ name: String) -> String {
        if lineup == Pal.Classic { return name }   //@fan
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        return stem + "-" + lineup + (ext.isEmpty ? "" : "." + ext)
    }

    // 換一櫃：大家先收起來（不吵）、換成另一櫃的公仔，照那一櫃上次的狀態放出來（或指定的那隻）
    func SwitchLineup(_ id0: String, _ pet: String) {
        let id = Pal.NormLineup(id0)
        if id == lineup {
            let want = Get(pet)
            if want != nil { SelectOnly(want!) }
            return
        }
        AbortScene()
        ClearProps()
        if BallOn { BallOn = false; Holder = nil; if ballF != nil { ballF.Hide() } }
        SaveUsage(); SaveOut()
        current = nil
        for p in Pets { p.Out = false; p.CloseForms() }
        for f in webs { f.Close() }
        webs.Clear()
        Pets.Clear(); outOrder.Clear(); active = nil; lastBroadcast = ""
        lineup = id
        World.WriteText("lineup.txt", lineup)
        defaultPet = DefaultPetFor(pet)
        usage.Clear()
        LoadState()
        var seed = Environment.TickCount
        for p in Pal.Lineup(lineup) { Pets.Add(Pet(self, p, S, seed)); seed += 1 }
        if shelf != nil { shelf.Place(ShelfWA()) }   // 每櫃各自的櫃子（窩伴小世界＝書包小屋），大小不一樣
        RenderShelf()
        var ids: List<String>
        if Get(pet) != nil { ids = List<String>(); ids.Add(pet) } else { ids = LoadOutIds() }
        var delay = 0.35
        for oid in ids {
            let pp = Get(oid)
            if pp == nil { continue }
            let p2: Pet = pp!
            Later(delay) { self.BringOut(p2, true) }
            delay += 0.5
        }
        active = Get(ids.Count > 0 ? ids[ids.Count - 1] : defaultPet) ?? Get(defaultPet)
        if ids.Count == 0 && active != nil { active.Say(OrigLineup ? Pal.SqName(lineup) + "，報到！" + (WobanLineup ? "🎒" : "🥤") : (TubbyLineup ? "Eh-oh! 天線寶寶一櫃 ☀" : (CuLineup ? "我的櫃！大家都在 🧸" : "經典一櫃回來囉！")), 2.4) }   //@fan
        // <public> if ids.Count == 0 && active != nil { active.Say(CuLineup ? "我的櫃！大家都在 🧸" : Pal.SqName(lineup) + "，報到！" + (WobanLineup ? "🎒" : "🥤"), 2.4) }
        Broadcast()
        lock(clients) { for c in clients { World.Send(c, "lineup " + lineup + "\n") } }   // 在桌面換櫃（小屋、設定）：VS Code 跟著改設定
        App.Log("lineup " + lineup)
    }

    func Get(_ id: String) -> Pet! { for p in Pets { if p.P.Id == id { return p } }; return nil }

    // ================= 啟動 =================
    func Start() {
        let h = Handle // 建立視窗代碼（收快速鍵、BeginInvoke 用）
        if h == 0 { App.Log("no handle") }
        try? FileManager.default.createDirectory(atPath: World.DataDir, withIntermediateDirectories: true)
        Migrate()
        LegacyTakeOver()   //@fan
        LoadState()
        LoadFeatures()
        MisStart()   // 搗蛋（59_mischief.swift）
        StatsStart()   // 匿名回報：滿 7 天那次（61_stats.swift；個人版什麼都不做）
        LoadMode()
        SeasonNow = Season()
        Night = NightNow()
        nightChecked = DateTime.Now.Minute
        shelf = ShelfForm(self, S)
        shelf.Night = Night
        shelf.Collapsed = Single || World.ReadText("shelf-state.txt") == "egg"   // 只要一隻：沒有櫃子，收起來的小紙箱就是家
        if shelf.Collapsed { shelf.SnapFold() }
        shelf.Place(ShelfWA())
        lastT = clock.Elapsed.TotalSeconds; Now = lastT
        sessionStart = lastT
        Scan(lastT)
        RenderShelf()
        shelf.Show()

        // 一開始誰在外面：out.txt，沒有就用 -Pet
        let outIds = LoadOutIds()
        let today = DateTime.Now.ToString("yyyy-MM-dd")
        let rollCall = outIds.Count >= 2 && !Night && Feat("rollcall") && World.ReadText("rollcall.txt") != today
        if rollCall { World.WriteText("rollcall.txt", today); StartRollCall(outIds) }
        else {
            var delay = 0.2
            for id in outIds {
                let p = Get(id)
                if p == nil { continue }
                let pp: Pet = p!
                Later(delay) { self.BringOut(pp, false); pp.Say(pp.Greeting(), 3.5); if pp.DaysSincePat() >= 2 { pp.Say(pp.L("missed"), 4.5) } }
                delay += 0.6
            }
        }
        let act = World.ReadText(LF("active.txt"))
        if Get(act) != nil { active = Get(act) }
        if active == nil { active = Get(outIds.Count > 0 ? outIds[outIds.Count - 1] : defaultPet) ?? Get(defaultPet) }

        let th = Foundation.Thread { self.PipeLoop() }; th.start()
        let cw = Foundation.Thread { self.WatchLoop() }; cw.start()
        let hl = Foundation.Thread { self.HealthLoop() }; hl.start()
        LoadReminders()
        LoadTickets()
        StartDownloadWatch()
        if !App.Offscreen && !RegisterHotKeyMac() { App.Log("hotkey ⌃⌥S is taken") }
        timer.Interval = 30
        timer.Tick = { self.Tick() }
        timer.Start()
        if !FileManager.default.fileExists(atPath: World.FilePath("profile.txt")) { Later(1.2) { self.ShowSetup(true) } }   // 第一次：設定視窗（做一隻自己的或選一櫃、擺法）
        App.Log("started pipe=" + pipeName + " lineup=" + lineup + " out=" + outIds.ToArray().joined(separator: ",") + " data=" + World.DataDir)
    }

    // ---------- 快速鍵 Ctrl+Option+S（mac：Carbon RegisterEventHotKey，取代 RegisterHotKey + WndProc）----------
    static var hotKeyWorld: World? = nil
    static var hotKeyRef: EventHotKeyRef? = nil
    static var hotKeyHandler: EventHandlerRef? = nil
    static let HotKeySig: OSType = 0x4450_4C53   // 'DPLS'

    func RegisterHotKeyMac() -> Bool {
        World.hotKeyWorld = self
        if World.hotKeyHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let st0 = InstallEventHandler(GetApplicationEventTarget(), { (_, ev, _) -> OSStatus in
                var hk = EventHotKeyID()
                if let e = ev {
                    let r = GetEventParameter(e, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
                    if r != OSStatus(noErr) || hk.signature != World.HotKeySig || hk.id != 7 { return OSStatus(eventNotHandledErr) }
                }
                DispatchQueue.main.async { World.hotKeyWorld?.ToggleHide() }   // ⌃⌥S
                return OSStatus(noErr)
            }, 1, &spec, nil, &World.hotKeyHandler)
            if st0 != OSStatus(noErr) { return false }
        }
        let hkID = EventHotKeyID(signature: World.HotKeySig, id: UInt32(7))
        let mods = UInt32(controlKey) | UInt32(optionKey)
        let st = RegisterEventHotKey(UInt32(kVK_ANSI_S), mods, hkID, GetApplicationEventTarget(), OptionBits(0), &World.hotKeyRef)
        return st == OSStatus(noErr)
    }

    // ---------- 存檔 ----------
    static func FilePath(_ name: String) -> String { return (DataDir as NSString).appendingPathComponent(name) }
    static func ReadText(_ name: String) -> String {
        guard let s = try? String(contentsOfFile: FilePath(name), encoding: .utf8) else { return "" }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func WriteText(_ name: String, _ s: String) {
        try? FileManager.default.createDirectory(atPath: DataDir, withIntermediateDirectories: true)
        try? s.write(toFile: FilePath(name), atomically: true, encoding: .utf8)
    }

    func Migrate() {
        // <fan>
        // 舊的 Spidey 桌面版好感度搬過來（只複製，不動原檔）
        // mac: 舊的 mac 版 SpideyDesktop.swift 存在 ~/Library/Application Support/SpideyDesktop（bond.txt「xp 日期」、pats.txt「日期 次數」，格式一樣）
        let old = World.LegacyDir()
        let map: [[String]] = [["bond.txt", "bond-spidey.txt"], ["pats.txt", "pats-spidey.txt"]]
        let fm = FileManager.default
        for i in 0..<(old.isEmpty ? 0 : 2) {
            let src = (old as NSString).appendingPathComponent(map[i][0]), dst = World.FilePath(map[i][1])
            if fm.fileExists(atPath: src) && !fm.fileExists(atPath: dst) {
                if (try? fm.copyItem(atPath: src, toPath: dst)) != nil { App.Log("migrated " + map[i][0]) }
            }
        }
        // </fan>
        for p in Pets { p.Reload() }
    }

    func LoadState() {
        favPin = World.ReadText(LF("fav.txt"))
        for line in World.ReadText(LF("usage.txt")).components(separatedBy: "\n") {
            let a = line.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
            if a.count == 2, let v = Double(a[1]) { usage[a[0]] = v }
        }
    }

    func LoadOutIds() -> List<String> {
        let ids = List<String>()
        if FileManager.default.fileExists(atPath: World.FilePath(LF("out.txt"))) {
            let seps = CharacterSet(charactersIn: " ,\n\r")
            for s in World.ReadText(LF("out.txt")).components(separatedBy: seps) where !s.isEmpty {
                if Get(s) != nil && !ids.Contains(s) { ids.Add(s) }
            }
        }
        else { ids.Add(Single ? SinglePet() : defaultPet) }
        if Single { ids.RemoveAll { x in x != self.SinglePet() } }   // 只要一隻：其他隻都不出來
        return ids
    }

    func SaveOut() {
        var ids: [String] = []
        for p in outOrder { if p.Out && p.state != "stowfly" && p.state != "enter" { ids.append(p.P.Id) } }
        World.WriteText(LF("out.txt"), ids.joined(separator: " "))
        if active != nil { World.WriteText(LF("active.txt"), active.P.Id) }
    }

    func SaveUsage() {
        var sb = ""
        for kv in usage { sb += kv.Key + " " + String(format: "%.0f", kv.Value) + "\n" }
        World.WriteText(LF("usage.txt"), sb)   // 每一櫃各自算誰用最久（小波在天線寶寶一櫃的時間不算進經典一櫃）
    }

    // ---------- 櫃子的格子：最愛（釘選 > 用最久）在高格，其他照順序 ----------
    func FavId() -> String {
        if PikLineup { return "" }   // 皮克敏一櫃：大格固定是休息花   //@fan
        if Get(favPin) != nil { return favPin }
        if let lf = Pal.LineupFav(lineup) as String?, Get(lf) != nil { return lf }                 // 天線寶寶一櫃：大格是小波
        var best: String = Pets[0].P.Id; var bv: Double = -1
        for p in Pets { var v: Double = 0; _ = usage.TryGetValue(p.P.Id, &v); if v > bv + 0.5 { bv = v; best = p.P.Id } }
        return best
    }

    func CellPets() -> [Pet?] {
        var c = [Pet?](repeating: nil, count: 4)
        let fav = FavId()
        c[0] = Get(fav)
        var i = 1
        for p in Pets { if p !== c[0] && i < 4 { c[i] = p; i += 1 } }
        return c
    }

    func CellOf(_ p: Pet) -> Int { let c = CellPets(); for i in 0..<4 { if c[i] === p { return i } }; return 1 }

    func ShelfFoot(_ p: Pet, _ fxp: inout Double, _ fyp: inout Double, _ ps: inout Int) {
        if shelf.Collapsed { let ef = shelf.EggFoot(); fxp = Double(ef.X); fyp = Double(ef.Y); ps = 2; return }
        let i = CellOf(p)
        let f = shelf.Foot(i)
        fxp = Double(f.X); fyp = Double(f.Y); ps = shelf.FitPs(i, p)
    }

    // 丟回櫃子的「籃框」：櫃子左右各加一隻寬、上面加兩隻高
    func ShelfZone(_ sw: Int, _ sh: Int) -> Rectangle {
        let a = shelf.Collapsed ? shelf.EggScreen() : shelf.Area
        return Rectangle.FromLTRB(a.Left - sw, a.Top - 2 * sh, a.Right + sw, a.Bottom + sh / 2)
    }

    func GoalCheer(_ scorer: Pet) {
        for p in OutPets() { if p !== scorer { p.Cheer() } }
    }

    func InShelf(_ px: Double, _ py: Double) -> Bool {
        var a = shelf.Collapsed ? shelf.EggScreen() : shelf.Area
        a.Inflate(CInt(20 * k), CInt(20 * k))
        return a.Contains(CInt(px), CInt(py))
    }

    func ShelfWA() -> Rectangle {
        var wa = screens[0].WorkingArea
        for sc0 in screens { let r0 = sc0.WorkingArea; if r0.Right > wa.Right || (r0.Right == wa.Right && r0.Bottom > wa.Bottom) { wa = r0 } }
        return wa
    }

    func RepaintShelf() { RenderShelf() }
    func RenderShelf() {
        if shelf == nil { return }
        if Hidden { if W.Shown(shelf) { shelf.Hide() }; return }
        let c = CellPets()
        var o = [Bool](repeating: false, count: 4)
        for i in 0..<4 { o[i] = c[i] != nil && c[i]!.Out }
        var hot = false, over = false
        for p in Pets { if p.Out && p.Dragging { hot = true; if InShelf(p.Cx, p.y + Double(p.SH) / 2.0) { over = true } } }
        shelf.Hot = hot; shelf.Over = over; shelf.Night = Night; shelf.Tubby = TubbyLineup; shelf.Pik = PikLineup; shelf.Orig = OrigLineup; shelf.Lunch = Lunch; shelf.Attention = EggAttention()   //@fan
        // <public> shelf.Hot = hot; shelf.Over = over; shelf.Night = Night; shelf.Orig = OrigLineup; shelf.Lunch = Lunch; shelf.Attention = EggAttention()
        shelf.Render(c, o, Now)
        if !W.Shown(shelf) { shelf.Show(); Zorder() }
    }

    // ---------- 放出來／收回去 ----------
    func BringOut(_ p: Pet, _ say: Bool) {
        if !Pets.Contains(p) { return }          // 換櫃之前排好的延遲動作
        if Single && p.P.Id != SinglePet() { return }   // 只要一隻：其他隻待在家
        if p.Out { active = p; Broadcast(); return }
        p.ComeOut(say)
        if shelf.Collapsed { shelf.Gulp() }
        outOrder.Remove(p); outOrder.Add(p)
        active = p
        if fetchingBall() { p.BallStarted() }
        SaveOut(); Broadcast()
        Zorder()
    }

    func fetchingBall() -> Bool { return BallOn }

    func PetStowed(_ p: Pet) {
        if shelf.Collapsed { shelf.Gulp() }   // 蛋把公仔吞進去、晃一下
        outOrder.Remove(p)
        if Holder === p { ReleaseBall(p.Cx, p.y, 0, 0) }
        if active === p {
            var i = outOrder.Count - 1
            while i >= 0 { if outOrder[i].Out { active = outOrder[i]; break }; i -= 1 }
        }
        SaveOut(); Broadcast()
    }

    func ShelfClick(_ cell: Int) {
        let p0 = CellPets()[cell]
        guard let p = p0 else { if cell == 0 && PikLineup { FlowerClicked() } else if OrigLineup { CuOpenMaker(nil, false) }; return }   //@fan
        // <public> guard let p = p0 else { if OrigLineup { CuOpenMaker(nil, false) }; return }   // 續命小隊的空格＝做一隻自己的公仔
        if p.Out { if p.state != "stowfly" && p.state != "enter" && p.state != "exit" { p.StowToShelf(true) } }
        else { BringOut(p, true) }
    }

    func SelectOnly(_ p: Pet) {
        AbortScene()
        for o in Pets { if o !== p && o.Out && o.state != "stowfly" && o.state != "enter" { o.StowToShelf(false) } }
        if !p.Out { Later(0.35) { self.BringOut(p, true) } }
        else { active = p; Broadcast(); SaveOut() }
    }

    func AllOut() {
        var d: Double = 0
        for p in Pets { if !p.Out { let pp = p; Later(d) { self.BringOut(pp, true) }; d += 0.45 } }
    }

    func AllHome() {
        AbortScene()
        var d: Double = 0
        for p in Pets { if p.Out { let pp = p; Later(d) { if pp.Out && pp.state != "stowfly" && pp.state != "enter" { pp.StowToShelf(true) } }; d += 0.35 } }
    }

    func SetFav(_ p: Pet) {
        if PikLineup { p.Say("大格種的是休息花，花不能搬喔 🌸", 2.2); return }   //@fan
        favPin = favPin == p.P.Id ? "" : p.P.Id
        World.WriteText(LF("fav.txt"), favPin)
        p.Say(favPin == "" ? "好～不當最愛也沒關係" : "我是最愛！★ 謝謝你 ♥", 2)
    }

    func Lead() -> Pet! {
        if active != nil && active.Out { return active }
        var i = outOrder.Count - 1
        while i >= 0 { if outOrder[i].Out { return outOrder[i] }; i -= 1 }
        return active ?? Get(defaultPet)
    }

    func OutPets() -> List<Pet> { let l = List<Pet>(); for p in Pets { if p.Out && p.state != "stowfly" && p.state != "enter" { l.Add(p) } }; return l }
    func OutCount() -> Int { return OutPets().Count }
    func RandomOther(_ me: Pet) -> Pet! { let l = OutPets(); l.Remove(me); return l.Count == 0 ? nil : l[rnd.Next(l.Count)] }
    func Nearest(_ me: Pet) -> Pet! {
        var best: Pet! = nil; var bd = Double.greatestFiniteMagnitude
        for p in OutPets() { if p !== me { let d = Math.Abs(p.Cx - me.Cx) + Math.Abs(p.y - me.y); if d < bd { bd = d; best = p } } }
        return best
    }

    // ---------- 延遲動作 ----------
    func Later(_ sec: Double, _ a: @escaping () -> Void) { later.Add((Now + sec, a)) }
    func RunLater() {
        var i = 0
        while i < later.Count {
            if Now >= later[i].0 { let a = later[i].1; later.RemoveAt(i); i -= 1; a() }
            i += 1
        }
    }

    // ================= 主迴圈 =================
    func Tick() {
        let t0 = clock.Elapsed.TotalMilliseconds
        defer {
            let ms = clock.Elapsed.TotalMilliseconds - t0
            perfSum += ms; perfN += 1; if ms > perfMax { perfMax = ms }
            if Now - perfT > 60 && perfLogs < 6 {
                perfLogs += 1
                App.Log("perf: tick avg " + String(format: "%.1f", perfSum / Double(Math.Max(1, perfN))) + "ms max " + String(format: "%.0f", perfMax) + "ms out=" + String(OutCount()))
                perfT = Now; perfSum = 0; perfN = 0; perfMax = 0
            }
        }
        TickInner()
    }

    func TickInner() {
        let now = clock.Elapsed.TotalSeconds, dt = Math.Min(0.05, now - lastT)
        lastT = now; Now = now
        if now >= nextScan { nextScan = now + 0.3; Scan(now) }
        let c = Cursor.Position
        if c == lastCursor { CursorStill += dt } else { CursorStill = 0; lastCursor = c }
        newWinCd -= dt; fgCd -= dt; danceCd -= dt; waitCd -= dt
        RunLater()
        FocusTick()
        LunchTick(false)
        QuietTick()
        ReminderTick()
        TicketTick()
        StudyTick()          // 讀書小幫手（52_study.swift）：學校行事曆、作業死線、考試倒數、熬夜
        MisTick(dt)          // 搗蛋（59_mischief.swift）：搶游標、下班清場、購物警察、打字太兇
        DownloadTick(dt)
        ExpireNotice()
        MenuWatch()
        if Hidden { return }
        for p in Pets {
            if p.Out { p.Tick(dt) } else if p.Bt > 0 { p.Bt -= dt; p.UpdateBubble() } else { p.HideForms() }
            if !p.Out && p.ShelfFx < 1 { p.ShelfFx = Math.Min(1.0, p.ShelfFx + dt / 0.9) }
            if p.Out && !sysIdle { var v: Double = 0; _ = usage.TryGetValue(p.P.Id, &v); usage[p.P.Id] = v + dt }
        }
        UpdateBall(dt)
        StepProps(dt)
        PikTick(dt)   //@fan
        OrigTick(dt)
        if fx != nil { fx.Step(dt) }
        StepScene(dt)
        proxT -= dt
        if proxT <= 0 { proxT = 0.5; CheckCrossover() }
        shelfT -= dt
        var dragHot = false
        for p in Pets { if p.Out && p.Dragging { dragHot = true } }
        if shelf != nil { shelf.Step(dt) }
        if shelfT <= 0 || dragHot || (shelf != nil && shelf.Animating) { shelfT = 0.1; RenderShelf() }
        usageT += dt
        if usageT > 60 { usageT = 0; SaveUsage() }
    }

    // 由下到上：櫃子 → 公仔 → 球 → 泡泡
    func Zorder() {
        W.KeepOnTop(shelf)
        for f in webs { W.KeepOnTop(f) }
        for p in Pets { if p.Form != nil { W.KeepOnTop(p.Form) } }
        W.KeepOnTop(ballF)
        for pr in props { W.KeepOnTop(pr.F) }
        if fx != nil && fx.Active { W.KeepOnTop(fx) }
        for p in Pets { if p.Bub != nil { W.KeepOnTop(p.Bub) } }
        W.KeepOnTop(flowerBub)   //@fan
    }

    // ================= 掃描視窗 =================
    // mac: EnumWindows → CGWindowListCopyWindowInfo（由前到後＝z-order），只看 layer 0、略過自己的 PID；
    // 標題（kCGWindowName）沒有「螢幕錄影」權限時是空的 → 候選視窗只看大小（跟 mac 版 Spidey 一樣）。
    func Scan(_ now: Double) {
        screens = Screen.AllScreens
        let own = HashSet<IntPtr>()
        own.Add(Handle)
        for p in Pets { if p.Form != nil && p.Form.IsHandleCreated { own.Add(p.Form.Handle) }; if p.Bub != nil && p.Bub.IsHandleCreated { own.Add(p.Bub.Handle) } }
        for wf in webs { if wf.IsHandleCreated { own.Add(wf.Handle) } }
        if shelf != nil && shelf.IsHandleCreated { own.Add(shelf.Handle) }
        if ballF != nil && ballF.IsHandleCreated { own.Add(ballF.Handle) }
        if fx != nil && fx.IsHandleCreated { own.Add(fx.Handle) }
        if flash != nil && flash.IsHandleCreated { own.Add(flash.Handle) }
        for pr in props { if pr.F.IsHandleCreated { own.Add(pr.F.Handle) } }
        if flowerBub != nil && flowerBub.IsHandleCreated { own.Add(flowerBub.Handle) }   //@fan

        let nw = List<WinInfo>()
        let nc = Dict<IntPtr, WinInfo>()
        var shareFound = false
        let myPid = ProcessInfo.processInfo.processIdentifier
        var fgPid: Int32 = -1
        if let front = NSWorkspace.shared.frontmostApplication { fgPid = front.processIdentifier }
        var fgw: IntPtr = 0
        if !App.Isolated, let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in list {
                let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
                let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
                let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
                let num = (info[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
                let h: IntPtr = num
                if num == 0 || pid == myPid || own.Contains(h) { continue }
                let title = (info[kCGWindowName as String] as? String) ?? ""
                let titled = !title.isEmpty
                if titled && !shareFound && World.IsShareTitle(title) { shareFound = true }   // 分享工具列常在別的 layer，先看標題
                if layer != 0 || alpha <= 0.01 { continue }
                guard let bd = info[kCGWindowBounds as String] as? NSDictionary, let rc = CGRect(dictionaryRepresentation: bd as CFDictionary) else { continue }
                let L = Int(rc.minX.rounded()), T = Int(rc.minY.rounded()), R = Int(rc.maxX.rounded()), B = Int(rc.maxY.rounded())
                if R - L < 4 || B - T < 4 { continue }
                let wi = WinInfo()
                wi.H = h; wi.L = L; wi.T = T; wi.R = R; wi.B = B; wi.Z = nw.Count
                nw.Add(wi)
                if fgw == 0 && pid == fgPid { fgw = h }
                if R - L >= 160 && B - T >= 80 { nc[h] = wi }   // mac: 拿不到標題／工具視窗樣式，只看大小
            }
        }
        fgWinMac = fgw; fgPidMac = fgPid

        let SH = 16 * S, SW = 12 * S
        let np = List<Plat>()
        for wi in nc.Values {
            let wa = WA(Double(wi.L + wi.R) / 2.0, Double(wi.T + 1))
            if wi.T - wa.Top < SH + 4 || wi.T >= wa.Bottom - 4 { continue }
            var segs = List<[Int]>()
            segs.Add([Math.Max(wi.L, wa.Left) + 4, Math.Min(wi.R, wa.Right) - 4])
            var i = 0
            while i < wi.Z && segs.Count > 0 {
                let f = nw[i]
                if f.T <= wi.T - 1 && f.B > wi.T - 1 { segs = World.Cut(segs, f.L, f.R) }
                i += 1
            }
            for s in segs {
                if s[1] - s[0] >= SW { let p = Plat(); p.H = wi.H; p.Top = wi.T; p.Left = s[0]; p.Right = s[1]; p.WinLeft = wi.L; np.Add(p) }
            }
        }
        CuFakeWins(nw, nc, np)   // 測試用的假視窗（只有離屏隔離模式）
        Wins = nw; Cands = nc; Plats = np
        if shareFound != sharing {
            sharing = shareFound
            if !sharing && !userHidden && !fsNow { Lead().Say(Lead().L("share_end"), 2) }
            ApplyHidden()
        }
        for p in Pets { if p.Out { p.CheckSupport() } }

        // 新視窗／對話框 → 一隻跑去看
        if known == nil { known = HashSet<IntPtr>(); for h in nc.Keys { known.Add(h) } }
        else {
            var fresh: WinInfo! = nil
            for kv in nc { if !known.Contains(kv.Key) { known.Add(kv.Key); fresh = kv.Value } }
            var gone: [IntPtr] = []
            for h in known { if !nc.ContainsKey(h) { gone.append(h) } }
            for h in gone { known.Remove(h) }
            if fresh != nil && newWinCd <= 0 && !Hidden && !focusOn && !quietOn && Feat("windows") {
                let p = PickFree()
                if p != nil { newWinCd = 6; fgCd = Math.Max(fgCd, 6.0); p!.ReactNewWindow(fresh) }
            }
        }

        // 你切到哪個視窗，常常有一隻跟過去
        if fgw != lastFg {
            lastFg = fgw
            var fw: WinInfo! = nil
            if fgCd <= 0 && !Hidden && !focusOn && !quietOn && Feat("windows") && Cands.TryGetValue(fgw, &fw) && rnd.NextDouble() < 0.55 {
                let p = PickFree()
                if p != nil && p!.FollowWindow(fw, p!.AppLine(fgw)) { fgCd = 20 + rnd.NextDouble() * 20 }
            }
        }

        if shelf != nil {
            let swa = ShelfWA()
            shelf.Place(swa)
        }
        SystemActivity(now)
        CheckNight()
        UpdateWebs(now)
        FullscreenCheck(own)
        Zorder()
    }

    func PickFree() -> Pet! {
        let l = Lead()
        if l != nil && l!.Free() { return l }
        let fr = List<Pet>()
        for p in OutPets() { if p.Free() { fr.Add(p) } }
        return fr.Count == 0 ? nil : fr[rnd.Next(fr.Count)]
    }

    static func Cut(_ segs: List<[Int]>, _ a: Int, _ b: Int) -> List<[Int]> {
        let res = List<[Int]>()
        for s in segs {
            if b <= s[0] || a >= s[1] { res.Add(s); continue }
            if a > s[0] { res.Add([s[0], a - 1]) }
            if b < s[1] { res.Add([b + 1, s[1]]) }
        }
        return res
    }

    func PointVisible(_ wi: WinInfo, _ px: Double, _ py: Double) -> Bool {
        for o in Wins {
            if o.Z >= wi.Z { break }
            if px >= Double(o.L) && px < Double(o.R) && py >= Double(o.T) && py < Double(o.B) { return false }
        }
        return true
    }

    func WA(_ px: Double, _ py: Double) -> Rectangle {
        var best = screens[0].WorkingArea
        var bd = Double.greatestFiniteMagnitude
        for s in screens {
            let r = s.WorkingArea
            if r.Contains(CInt(px), CInt(py)) { return r }
            let dx = Math.Max(0.0, Math.Max(Double(r.Left) - px, px - Double(r.Right))), dy = Math.Max(0.0, Math.Max(Double(r.Top) - py, py - Double(r.Bottom)))
            if dx * dx + dy * dy < bd { bd = dx * dx + dy * dy; best = r }
        }
        return best
    }

    func Inside(_ px: Double, _ py: Double) -> Bool {
        for s in screens { if s.WorkingArea.Contains(CInt(px), CInt(py)) { return true } }
        return false
    }

    // ---------- 蜘蛛網（Spidey 織在視窗角落）----------
    func AddWeb(_ h: IntPtr, _ right: Bool) {
        for f in webs { if f.H == h && f.RightCorner == right { return } }
        if webs.Count >= 4 { webs[0].Close(); webs.RemoveAt(0) }
        let web = CobwebForm(h, right, CInt(34 * k), Math.Max(1, CInt(Math.Round(k))), Now)
        webs.Add(web)
        PlaceWeb(web)
    }

    func PlaceWeb(_ f: CobwebForm) {
        var wi: WinInfo! = nil
        var ok = !Hidden && Cands.TryGetValue(f.H, &wi)
        if ok {
            let px = f.RightCorner ? wi.R - f.Side : wi.L, py = wi.T
            ok = PointVisible(wi, Double(f.RightCorner ? wi.R - 3 : wi.L + 3), Double(wi.T + 3))
            if ok {
                let nb = Rectangle(px, py, f.Side, f.Side)
                if f.Bounds != nb { f.Bounds = nb }
                if !W.Shown(f) { f.Show() }
            }
        }
        if !ok && W.Shown(f) { f.Hide() }
    }

    // mac: IsWindowVisible(h) → 這次掃描的 layer-0 視窗裡還有它
    func WinVisibleMac(_ h: IntPtr) -> Bool { for o in Wins { if o.H == h { return true } }; return false }

    func UpdateWebs(_ now: Double) {
        var i = webs.Count - 1
        while i >= 0 {
            let f = webs[i]
            let gone = now - f.Born > 150 || (!Cands.ContainsKey(f.H) && !WinVisibleMac(f.H))
            if gone { f.Close(); webs.RemoveAt(i); i -= 1; continue }
            PlaceWeb(f)
            i -= 1
        }
    }

    // ---------- 煙火 ----------
    func Fireworks(_ area: Rectangle, _ n: Int, _ focusX: Int) {
        if Hidden || !Feat("fireworks") { return }   // 小屋可以關掉煙火
        if fx == nil { fx = FxForm(k) }
        fx.Start(area, n, focusX)
        Zorder()
    }

    // ---------- 躲起來（快速鍵／分享螢幕／全螢幕）----------
    func ToggleHide() {
        userHidden = !userHidden
        ApplyHidden()
        if !userHidden && !Hidden { let l: Pet = Lead(); l.Say(l.L("back"), 1.6) }
    }

    func ApplyHidden() {
        let want = fsNow || userHidden || sharing
        if !sharing && !fsNow { FlushShareHeld() }
        if want == Hidden { return }
        Hidden = want
        if want {
            for p in Pets { p.HideForms() }
            for f in webs { f.Hide() }
            if shelf != nil { shelf.Hide() }
            if ballF != nil { ballF.Hide() }
            for pr in props { pr.F.Hide() }
            if flowerBub != nil { flowerBub.Hide() }   //@fan
            if fx != nil && fx.Active { fx.Stop() }
        }
        else { RenderShelf() }
    }

    static func IsShareTitle(_ t: String) -> Bool {
        let l = t.lowercased()
        if l.contains("sharing your screen") || l.contains("is sharing a window") || l.contains("is sharing this tab") || l.contains("you are screen sharing")
            || l.contains("sharing control bar") || l.contains("screen sharing toolbar") { return true }
        let verb = t.contains("分享") || t.contains("共用") || t.contains("共享")
        let obj = t.contains("螢幕") || t.contains("畫面") || t.contains("視窗") || t.contains("分頁")
        return (t.contains("正在") && verb && obj) || t.contains("共用控制列") || t.contains("共享控制列")
    }

    // mac: 前景＝最前面 App 的第一個 layer-0 視窗；蓋滿整個螢幕（含選單列）＝全螢幕
    func FullscreenCheck(_ own: HashSet<IntPtr>) {
        let fg: IntPtr = App.Isolated ? 0 : fgWinMac
        var fs = false
        if fg != 0 && !own.Contains(fg) {
            var r: WinInfo! = nil
            for o in Wins { if o.H == fg { r = o; break } }
            if r != nil {
                let b = Screen.FromRectangle(Rectangle.FromLTRB(r.L, r.T, r.R, r.B)).Bounds
                fs = r.L <= b.Left && r.T <= b.Top && r.R >= b.Right && r.B >= b.Bottom
            }
        }
        fsNow = fs
        ApplyHidden()
    }

    // ---------- 整台電腦的鍵盤滑鼠：太久沒動 → 睡；回來 → 敲螢幕；用太久 → 提醒休息 ----------
    func SystemActivity(_ now: Double) {
        let idle = W.IdleSeconds()   // mac: GetLastInputInfo → CGEventSource（在 W.IdleSeconds 裡）
        if !sysIdle && idle > idleMin * 60 {
            sysIdle = true
            for p in Pets { p.SystemIdle(true) }
        }
        else if sysIdle && idle < 2 {
            sysIdle = false
            if PikLineup { PikRested() }       // 休息花：休息回來才恢復   //@fan
            sessionStart = now
            let l = Lead()
            for p in Pets { if p === l { p.SystemIdle(false) } else { p.WakeIfSleep() } }
        }
        if !sysIdle && now - sessionStart >= restMin * 60 {
            sessionStart = now
            if HoldIfQuiet("rest", "該起來動一動了") { return }
            if PikLineup { PikWiltAlarm() } else { WbRest(RestPet(), restMin) }   //@fan
            // <public> WbRest(RestPet(), restMin)
        }
    }

    // ---------- 夜晚（平日 18:00～隔天 06:00）、節日 ----------
    // mac: DayOfWeek 用 Foundation 的 weekday（1＝星期日 … 7＝星期六）；平日＝2…6
    static func IsWeekday(_ d: Date) -> Bool { let wd = Calendar.current.component(.weekday, from: d); return wd >= 2 && wd <= 6 }
    static func IsNightTime(_ n: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: n)
        if hour >= 18 { return IsWeekday(n) }
        if hour < 6 { return IsWeekday(n.addingTimeInterval(-86400)) }
        return false
    }
    func NightNow() -> Bool { return forceNight >= 0 ? forceNight == 1 : Feat("night") && World.IsNightTime(Date()) }   // 小屋可以關掉「下班時間」

    func CheckNight() {
        let n = Date()
        let minute = Calendar.current.component(.minute, from: n)
        if minute == nightChecked { return }
        nightChecked = minute
        SeasonNow = Season()
        let d = NightNow()
        if d == Night { return }
        Night = d
        if quietOn { return }   // 安靜中：只換夜晚的樣子，不催
        if d && World.IsWeekday(n) && Calendar.current.component(.hour, from: n) == 18 { Later(OutCount() >= 2 ? 30 : 8) { self.DailyWrap(false) } }
        let outs = OutPets()
        if d && outs.Count >= 2 && Feat("rollcall") { NightRitual(); return }
        let l: Pet = Lead()
        for p in outs { if p === l { p.NightChanged(d) } else if !d { p.Say(p.L("night_off"), 3) } }
        if outs.Count == 0 { l.Say(l.L(d ? "night_on" : "night_off"), 3) }
    }

    static let CNY: [String] = ["2027-02-06", "2028-01-26", "2029-02-13", "2030-02-03", "2031-01-23", "2032-02-11"]
    func Season() -> String {
        let n = Date()
        let cal = Calendar.current
        let month = cal.component(.month, from: n), day = cal.component(.day, from: n), hour = cal.component(.hour, from: n)
        if !Feat("season") { return "" }          // 小屋關掉「節日造型」
        if birthday.count == 5 && String(format: "%02d-%02d", month, day) == birthday { return "birthday" }
        let fmt = DateFormatter(); fmt.locale = Locale(identifier: "en_US_POSIX"); fmt.dateFormat = "yyyy-MM-dd"
        let today = cal.startOfDay(for: n)
        for c in World.CNY {
            guard let cd = fmt.date(from: c) else { continue }
            let d = today.timeIntervalSince(cal.startOfDay(for: cd)) / 86400.0
            if d >= -5 && d <= 14 { return "cny" }
        }
        if month == 12 && day <= 26 { return "xmas" }
        if month == 1 && day == 1 { return "newyear" }
        if month == 10 && day == 31 { return "halloween" }
        if cal.component(.weekday, from: n) == 6 && hour >= 15 && !Night { return "friday" }
        return ""
    }

    // ================= 球 =================
    func BallR() -> Double { return ballF == nil ? Double(8 * S) * 0.75 / 2 : Double(ballF.Width) / 2.0 }

    func StartBall() { StartBall(false) }

    func StartBall(_ nearPet: Bool) {
        let outs = OutPets()
        if outs.Count == 0 { Lead().Say("先放一隻出來陪你玩球～", 1.8); return }
        let po = Get("po")   //@fan
        BallKind = po != nil && po!.Out ? "baseball" : Lead().P.BallKind   //@fan
        // <public> BallKind = Lead().P.BallKind
        if ballF == nil { ballF = BallForm(Math.Max(2, S * 3 / 4)); ballF.Kicked = { self.BallClicked() } }
        ballF.Kind = BallKind
        let c = Cursor.Position
        Bx = Double(c.X); By = Double(c.Y) - 20 * k
        BallOn = true; Holder = nil
        if nearPet {
            // 測試用：從公仔前上方丟過來
            let l: Pet = Lead()
            Bx = l.Cx + Double(l.dir) * 260 * k; By = l.y - 160 * k
            Bvx = -Double(l.dir) * 260 * k; Bvy = -200 * k; BallIdle = 0; CatchCd = 0.2
            for p in OutPets() { p.BallStarted() }
            return
        }
        BallClicked()
    }

    func BallClicked() {
        if Holder != nil { return }
        Bvx = (rnd.NextDouble() < 0.5 ? -1.0 : 1.0) * (350 + rnd.NextDouble() * 450) * k
        Bvy = -(500 + rnd.NextDouble() * 300) * k
        BallIdle = 0; CatchCd = 0.4
        let l: Pet = Lead()
        for p in OutPets() { p.BallStarted() }
        l.Say(l.L("ball_go"), 1.2)
    }

    func EndBall(_ text: String) {
        BallOn = false; Holder = nil
        for p in Pets { p.fetching = false }
        if ballF != nil { ballF.Hide() }
        Lead().Say(text, 2)
    }

    func HoldBall(_ p: Pet) { Holder = p; if ballF != nil { ballF.Hide() } }

    func ReleaseBall(_ x: Double, _ y: Double, _ vx: Double, _ vy: Double) {
        Holder = nil; Bx = x; By = y; Bvx = vx; Bvy = vy; BallIdle = 0
        for p in OutPets() { p.BallStarted() }
    }

    func Umpire(_ call: String) {
        if OutCount() < 2 || umpCd > 0 { return }
        // <fan>
        let mm = Get("hangyodon") ?? Get("dipsy")   // 天線寶寶一櫃：迪西扶帽子當裁判
        if mm == nil || !mm!.Out || Holder === mm! { return }
        umpCd = 1.5
        mm!.Call(call)
        // </fan>
    }

    func UpdateBall(_ dt: Double) {
        if foulCd > 0 { foulCd -= dt }
        if umpCd > 0 { umpCd -= dt }
        if !BallOn { return }
        if Holder != nil {
            if !Holder.Out { ReleaseBall(Holder.Cx, Holder.y, 0, 0); return }
            Bx = Holder.Cx; By = Holder.y
            BallIdle = 0
            return
        }
        let g = 900 * k, r = BallR(), prevBottom = By + r
        Bvy += g * dt; Bx += Bvx * dt; By += Bvy * dt
        let wa = WA(Bx, By)
        var foul = false
        if !Inside(Bx - r, By) && Bx - r < Double(wa.Left) { Bx = Double(wa.Left) + r; Bvx = Math.Abs(Bvx) * 0.6; foul = true }
        if !Inside(Bx + r, By) && Bx + r > Double(wa.Right) { Bx = Double(wa.Right) - r; Bvx = -Math.Abs(Bvx) * 0.6; foul = true }
        if foul && foulCd <= 0 && Math.Abs(Bvx) > 200 * k { foulCd = 4; Umpire("界外！") }
        if By - r < Double(wa.Top) { By = Double(wa.Top) + r; Bvy = Math.Abs(Bvy) * 0.5 }
        if Bvy > 0 {
            var best = Double(wa.Bottom)
            for p in Plats {
                let top = Double(p.Top)
                if Bx >= Double(p.Left) && Bx <= Double(p.Right) && prevBottom <= top + 1 && By + r >= top && top < best { best = top }
            }
            if By + r >= best {
                By = best - r
                if Bvy > 140 * k { Bvy = -Bvy * 0.55; Bvx *= 0.85 }
                else { Bvy = 0; Bvx *= Math.Pow(0.15, dt) }
            }
        }
        BallIdle += dt
        if CatchCd > 0 { CatchCd -= dt }
        let l: Pet = Lead()
        if BallIdle > 25 && Math.Abs(Bvx) < 8 && Bvy == 0 { EndBall(l.L("ball_end")); return }
        if CatchCd <= 0 {
            for p in OutPets() {
                if !p.fetching { continue }
                let scx = p.Cx, scy = p.y + Double(p.SH) / 2.0
                if Math.Abs(Bx - scx) < Double(p.SW) * 0.6 + r && Math.Abs(By - scy) < Double(p.SH) * 0.6 + r && p.TouchBall() { CatchCd = 1.0; break }
            }
        }
        if Holder != nil { return }
        let nb = Rectangle(CInt(Bx - r), CInt(By - r), ballF.Width, ballF.Height)
        if ballF.Bounds != nb { ballF.Bounds = nb }
        if !W.Shown(ballF) && !Hidden { ballF.Show(); W.KeepOnTop(ballF) }
    }

    // ================= 右鍵選單 =================
    func FillMenu(_ p: Pet, _ m: ContextMenuStrip) {
        m.Items.Clear()
        var items: [[String]]! = p.P.Pik ? PikMenuItems(p) : (p.P.Orig ? OrigMenuItems(p) : (p.P.Cu ? p.CuMenuItems() : nil))   //@fan
        // <public> var items: [[String]]! = p.P.Orig ? OrigMenuItems(p) : (p.P.Cu ? p.CuMenuItems() : nil)
        // <fan>
        if items == nil { switch p.P.Id {
        case "po":
            items = [["大抱抱 ♥", "hug"], ["打招呼 Eh-oh!", "hi"], ["敲敲螢幕", "knock"], ["騎車兜風", "ride"],
                     ["滑板車飛跳", "sig"], ["揮棒", "bat"], ["睡覺", "sleep"], ["丟棒球給她 ⚾", "ball"]]
        case "stitch":
            items = [["抱抱 ♥", "hug"], ["Aloha! 打招呼", "hi"], ["舔舔螢幕", "knock"], ["爬牆上天花板", "sig"],
                     ["彈烏克麗麗 ♪", "uke"], ["跳到別的視窗上", "jump"], ["睡覺", "sleep"], ["丟球給他 ⚾", "ball"]]
        case "hangyodon":
            items = [["抱抱 ♥", "hug"], ["打招呼", "hi"], ["講個笑話", "joke"], ["敲敲螢幕（啵～）", "knock"],
                     ["披風英雄飛行", "sig"], ["吐泡泡", "bubble"], ["在泡泡裡睡覺", "sleep"], ["丟球給他 ⚾", "ball"]]
        case "tinky":
            items = [["大抱抱 ♥", "hug"], ["打招呼 Eh-oh!", "hi"], ["敲敲螢幕", "knock"], ["翻翻魔法袋", "bag"],
                     ["跳舞", "dance"], ["跌一跤（哎喲！）", "plop"], ["抱著袋袋睡覺", "sleep"], ["丟球給他 ⚾", "ball"]]
        case "dipsy":
            items = [["大抱抱 ♥", "hug"], ["打招呼 Eh-oh.", "hi"], ["敲敲螢幕", "knock"], ["帽子戲法", "sig"],
                     ["摘帽子揮一揮", "hatwave"], ["酷酷地跳舞", "dance"], ["帽子拉低睡覺", "sleep"], ["丟球給他 ⚾", "ball"]]
        case "laalaa":
            items = [["大抱抱 ♥", "hug"], ["打招呼 Eh-oh!", "hi"], ["敲敲螢幕", "knock"], ["顛球", "sig"],
                     ["唱歌 啦啦啦 ♪", "sing"], ["轉圈圈", "twirl"], ["抱著球睡覺", "sleep"], ["丟球給她 ⚾", "ball"]]
        default:
            items = [["抱抱 ♥", "hug"], ["打招呼", "hi"], ["敲敲螢幕", "knock"], ["噴絲擺盪", "swing"],
                     ["倒吊", "hang"], ["跳到別的視窗上", "jump"], ["去爬牆", "climb"], ["睡覺", "sleep"], ["丟球給他 ⚾", "ball"]]
        } }
        // </fan>
        // <public> if items == nil { items = [["抱抱 ♥", "hug"], ["打招呼", "hi"], ["敲敲螢幕", "knock"], ["睡覺", "sleep"], ["丟球給他 ⚾", "ball"]] }
        m.Items.Add(ToolStripLabel("一起玩"))
        for it in items! {
            let a = it[1]
            m.Items.Add(it[0], nil, { if a == "ball" { self.StartBall() } else { p.Act(a) } })
        }
        m.Items.Add(p.P.Name + " 的好感度 ♥", nil, { p.ShowBond() })
        CuPetMenu(p, m)
        m.Items.Add(ToolStripSeparator())
        let help = ToolStripMenuItem("小幫手（專注、安靜、提醒）")
        AddHelpers(help.DropDownItems)
        m.Items.Add(help)
        m.Items.Add("公仔小屋（開關、設定）…", nil, { self.HouseMenu() })
        m.Items.Add(ToolStripSeparator())
        m.Items.Add(ToolStripLabel(Single ? "我的公仔" : "公仔們"))
        // <fan>
        if TubbyLineup && !Single {
            let grp = ToolStripMenuItem("天線寶寶一起…")
            let gs: [[String]] = [["大抱抱 ♥", "bighug"], ["啦啦啦一起唱", "sing"], ["一起跌倒（哎喲！）", "fall"],
                                  ["吐司時間 🍞", "toast"], ["大合照 📷", "photo"], ["天線寶寶說再見", "byebye"]]
            for gi in gs { let key = gi[1]; grp.DropDownItems.Add(gi[0], nil, { self.PlayScene(key) }) }
            m.Items.Add(grp)
        }
        // </fan>
        if PikLineup { AddPikMenu(m) }   //@fan
        if OrigLineup && !Single { AddOrigMenu(m) }
        if !Single {
            let sw = ToolStripMenuItem("換角色")
            for o in Pets {
                let oo = o
                let mi = ToolStripMenuItem(o.P.Name + (o.Out ? "（在外面）" : ""), nil, { self.SelectOnly(oo) })
                mi.Checked = o === p
                sw.DropDownItems.Add(mi)
            }
            m.Items.Add(sw)
            m.Items.Add("只留" + p.P.Name, nil, { self.SelectOnly(p) })
            m.Items.Add("全部放出來", nil, { self.AllOut() })
            m.Items.Add("全部回櫃子", nil, { self.AllHome() })
            m.Items.Add(favPin == p.P.Id ? "取消最愛" : "設為最愛 ★", nil, { self.SetFav(p) })
        }
        m.Items.Add(Single ? "回" + MiniName + "裡待著" : "回櫃子裡待著", nil, { p.StowToShelf(true) })
        m.Items.Add("躲起來（⌃⌥S）", nil, { self.ToggleHide() })
        m.Items.Add(ToolStripSeparator())
        m.Items.Add("收工（關掉 Desk Pals）", nil, { self.QuitAll() })
    }

    // 專注、安靜、提醒、搶票、今天的小結（公仔、櫃子、小屋的選單都有）
    func AddHelpers(_ items: ToolStripItemCollection) {
        if focusOn { items.Add("結束專注（還剩 " + String(FocusLeft()) + " 分）", nil, { self.StopFocus(false) }) }
        else { items.Add(ExamNear() ? "讀書 25 分鐘 📚" : "專注 25 分鐘 🍅", nil, { self.StartFocus(25) }) }   // 7 天內有考試：讀書
        AddQuietMenu(items)
        AddReminderMenus(items)
        AddTicketMenus(items)
        AddStudyMenus(items)   // 搶課、考試倒數、這週要交的
        items.Add("今天的小結", nil, { self.DailyWrap(true) })
    }

    func AddQuietMenu(_ items: ToolStripItemCollection) {
        if quietOn { items.Add("結束安靜（還剩 " + String(QuietLeft()) + " 分）", nil, { self.StopQuiet() }); return }
        let q = ToolStripMenuItem("安靜一下")
        q.DropDownItems.Add("30 分鐘", nil, { self.StartQuiet(30) })
        q.DropDownItems.Add("2 小時", nil, { self.StartQuiet(120) })
        q.DropDownItems.Add("到今天下班", nil, { self.StartQuiet(World.MinutesToOffWork()) })
        items.Add(q)
    }

    // 收起公仔櫃（變成小紙箱／小書包）／打開公仔櫃（shelf-state.txt 的值沿用以前的 egg／open）
    func ToggleEgg(_ collapse: Bool) {
        if shelf.Collapsed == collapse { return }
        if Single && !collapse { Lead().Say("現在是「只要一隻」，" + MiniName + "就是我家～（小屋 → 重新設定 可以換成整櫃）", 3); return }
        shelf.Collapsed = collapse
        World.WriteText("shelf-state.txt", collapse ? "egg" : "open")
        let l: Pet = Lead()
        if collapse { l.Say(Pick2("公仔櫃收起來囉～變成" + MiniName + " 📦", "收合！大家住進" + MiniName + "裡"), 1.8) }
        else { l.Say(Pick2("打開了！公仔櫃登場 ✨", "喀啦喀啦～櫃子打開囉"), 1.8) }
        RenderShelf()
    }
    // 收起來叫什麼（選單、泡泡用）：紙箱櫃＝小紙箱、書包小屋＝小書包
    var MiniName: String { return shelf != nil ? shelf.Kit.MiniName : "小紙箱" }
    var MenuFold: String { return "收起公仔櫃（變成" + MiniName + "）" }
    func Pick2(_ a: String, _ b: String) -> String { return rnd.NextDouble() < 0.5 ? a : b }

    // 蛋上的小紅點：專注／安靜時存著的通知，加上 10 分鐘內要到的提醒、搶票
    func EggAttention() -> Int {
        var n = heldQuiet.Count + heldFocus.Count
        let now = World.UnixMs(DateTime.Now)
        for r in reminders { if r.At - now <= 10 * 60000 { n += 1 } }
        for t in tickets { if t.At - now <= 10 * 60000 && t.At > now { n += 1 } }
        return n
    }

    // ---------- 選單：自己畫的像素選單（PixelMenu），開在游標旁邊 ----------
    // 以前要幫原生選單善後（宿主視窗、還焦點）；像素選單自己會處理，留著給公仔的 Menu 用
    func HookMenu(_ m: ContextMenuStrip) { }
    func ShowMenu(_ m: ContextMenuStrip) { ShowMenu(m, "", false, Cursor.Position) }
    func ShowMenu(_ m: ContextMenuStrip, _ title: String, _ house: Bool) { ShowMenu(m, title, house, Cursor.Position) }
    // 選單內容還是用 ToolStrip 項目寫，這裡畫成像素選單，按下後呼叫原本的 Click
    func ShowMenu(_ m: ContextMenuStrip, _ title: String, _ house: Bool, _ at: Point) {
        App.LogAlways("menu: requested, items=" + String(m.Items.Count) + " house=" + (house ? "True" : "False"))
        if pmenu != nil { pmenu.CloseMenu() }
        if !App.Offscreen { menuPrevFg = W.GetForegroundWindow() }
        let pm = PixelMenu(self, m, title, house)
        pmenu = pm
        W.SuspendZ = true                    // 開著時不要把公仔、櫃子拉到選單上面
        pm.Popup(at)
        if !App.Offscreen { pm.Activate() }  // mac: 不搶前景的面板直接拿鍵盤焦點（不用 ForceForeground）
    }
    // 選單關掉了（選了、Esc、點外面、失去焦點）：焦點還給原本的視窗
    // mac: 不搶前景的面板關掉後，鍵盤焦點自己回到原本的 App
    func MenuClosed(_ pm: PixelMenu) {
        if pm !== pmenu { return }
        pmenu = nil
        W.SuspendZ = false
    }
    // 點到選單外面就關：直接看滑鼠按鍵（我們是背景程式，點別的程式也看得到）；選單開了之後要先放開過一次
    func MenuWatch() {
        let pm: PixelMenu! = pmenu
        if pm == nil || pm.Done || App.Offscreen { return }
        if (Control.MouseButtons & (MouseButtons.Left | MouseButtons.Right | MouseButtons.Middle)) == MouseButtons.None { pm.Armed = true; return }
        if pm.Armed && !pm.Bounds.Contains(Cursor.Position) { pm.CloseMenu() }
    }

    // 像素選單用的字：拿掉 BMP 以外的字（彩色 emoji）和變體選擇符；★ ♥ ⏰ 這類保留
    static func NoEmoji(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            if u.value > 0xFFFF || u.value == 0xFE0F || u.value == 0x200D { continue }
            out.append(u)
        }
        return String(out).replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // 輸入框：拉到前景、可以直接打字
    func ActivateForm(_ f: Form) {
        NSApp.activate(ignoringOtherApps: true)   // mac: ForceForeground
        f.BringToFront()
        f.Activate()
        f.Focus()
        App.LogAlways("dialog: activate " + f.Text)
    }

    func ShelfMenu(_ cell: Int, _ at: AnyObject?) {
        let p: Pet! = cell >= 0 ? CellPets()[cell] : nil
        if shelfMenu == nil { shelfMenu = ContextMenuStrip(); HookMenu(shelfMenu) }
        let m: ContextMenuStrip = shelfMenu
        m.Items.Clear()
        if p != nil {
            m.Items.Add(p.Out ? "收回櫃子" : "放出來", nil, { self.ShelfClick(cell) })
            m.Items.Add("只留" + p.P.Name, nil, { self.SelectOnly(p) })
            m.Items.Add(favPin == p.P.Id ? "取消最愛" : "設為最愛 ★", nil, { self.SetFav(p) })
            m.Items.Add(p.P.Name + " 的好感度 ♥", nil, { p.ShowBond() })
            m.Items.Add(ToolStripSeparator())
        }
        if PikLineup { m.Items.Add("休息花：還能撐多久？🌸", nil, { self.FlowerClicked() }) }   //@fan
        m.Items.Add(shelf.Collapsed ? "打開公仔櫃" : MenuFold, nil, { self.ToggleEgg(!self.shelf.Collapsed) })
        m.Items.Add("全部放出來", nil, { self.AllOut() })
        m.Items.Add("全部回櫃子", nil, { self.AllHome() })
        let help = ToolStripMenuItem("小幫手（專注、安靜、提醒）")
        AddHelpers(help.DropDownItems)
        m.Items.Add(help)
        m.Items.Add("公仔小屋（開關、設定）…", nil, { self.HouseMenu() })
        m.Items.Add("躲起來（⌃⌥S）", nil, { self.ToggleHide() })
        m.Items.Add(ToolStripSeparator())
        m.Items.Add("收工（關掉 Desk Pals）", nil, { self.QuitAll() })
        ShowMenu(m, p != nil ? p.P.Name : "公仔櫃", false)
    }

    // ================= pipe（跟 VS Code 溝通）=================
    // mac: named pipe → Unix domain socket，路徑＝pipeName；同樣一行一個指令
    func ListenSocket() -> Int32 {
        let path = pipeName
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        unlink(path)   // 上次沒清掉的 socket 檔
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { App.Log("pipe: socket() errno " + String(errno)); return -1 }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let cap = MemoryLayout.size(ofValue: addr.sun_path)
        if bytes.count >= cap { App.Log("pipe: socket path too long: " + path); close(fd); return -1 }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, len) }
        }
        if rc != 0 { App.Log("pipe: bind errno " + String(errno)); close(fd); return -1 }
        chmod(path, 0o600)
        if Darwin.listen(fd, 16) != 0 { App.Log("pipe: listen errno " + String(errno)); close(fd); return -1 }
        return fd
    }

    func PipeLoop() {
        while !closing {
            if listenFd < 0 {
                listenFd = ListenSocket()
                if listenFd < 0 { usleep(500_000); continue }
            }
            let s = Darwin.accept(listenFd, nil, nil)
            if s < 0 {
                if errno == EINTR { continue }
                if closing { break }
                App.Log("pipe: accept errno " + String(errno))
                usleep(500_000)
                continue
            }
            var one: Int32 = 1
            _ = setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            let c = Client()
            c.S = s
            lock(clients) { clients.Add(c) }
            let th = Foundation.Thread { self.ClientLoop(c) }
            th.start()
        }
    }

    func ClientLoop(_ c: Client) {
        var buf = [UInt8](repeating: 0, count: 4096)
        var pending: [UInt8] = []
        while true {
            let n = read(c.S, &buf, buf.count)
            if n <= 0 { break }
            pending.append(contentsOf: buf[0..<n])
            while let idx = pending.firstIndex(of: 10) {
                var lineBytes = Array(pending[0..<idx])
                if lineBytes.last == 13 { lineBytes.removeLast() }   // ReadLine 會吃掉 \r\n
                pending.removeSubrange(0...idx)
                let l = String(decoding: lineBytes, as: UTF8.self)
                Post { self.OnMsg(c, l) }
            }
        }
        if !pending.isEmpty {   // 最後一行沒有換行也算一行（ReadLine 一樣）
            let l = String(decoding: pending, as: UTF8.self)
            Post { self.OnMsg(c, l) }
        }
        lock(clients) { clients.Remove(c) }
        close(c.S)
    }

    func Post(_ a: @escaping () -> Void) {
        if !closing { DispatchQueue.main.async { if !self.closing { a() } } }   // mac: BeginInvoke
    }

    static func Send(_ c: Client, _ s: String) {
        let b = Array(s.utf8)
        b.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var off = 0
            while off < raw.count {
                let n = write(c.S, base + off, raw.count - off)
                if n <= 0 { break }
                off += n
            }
        }
    }

    func Broadcast() {
        if active == nil { return }
        let id: String = active.P.Id
        if id == lastBroadcast { return }
        lastBroadcast = id
        lock(clients) { for c in clients { World.Send(c, "active " + id + "\n") } }
    }

    // C# 的 IndexOf(' ', start)：找不到回 -1
    static func IdxSpace(_ t: [Character], _ from: Int) -> Int {
        var i = Math.Max(0, from)
        while i < t.count { if t[i] == " " { return i }; i += 1 }
        return -1
    }
    static func AfterIdx(_ t: [Character], _ from: Int) -> String { return from >= t.count ? "" : String(t[from...]) }

    func OnMsg(_ c: Client, _ line: String) {
        let p = line.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        let l: Pet = Lead()
        let outs = OutPets()
        switch p[0] {
        case "hello": CuHello(c); if active != nil { World.Send(c, "active " + active.P.Id + "\n") }; World.Send(c, "lineup " + lineup + "\n")   // 櫃子以桌面版為準（第一次設定在桌面做）
        case "custom": CuMsg(c, line)   // 自己做的公仔（53_custom.swift／56_custom_make.swift）
        case "save":
            Count("saves")
            for x in outs { x.OnSave(x === l) }
            if outs.Count == 0 { l.OnSave(true) }
        case "errors":
            var n = 0, prev = 0
            if p.count >= 3 { n = Int(p[1]) ?? 0; prev = Int(p[2]) ?? 0 }
            if n <= prev && n != 0 { break }
            for x in outs { x.OnErrors(n, prev, x.P.Id == "po" || x.P.Id == "laalaa" ? Nearest(x) : nil) }   //@fan
            // <public> for x in outs { x.OnErrors(n, prev, nil) }
            if outs.Count == 0 { l.OnErrors(n, prev, nil) }
        case "config":
            if p.count >= 3, let rm = Double(p[1]), let im = Double(p[2]) { restMin = Math.Max(1.0, rm); idleMin = Math.Max(1.0, im) }
        case "hi": l.Act("hi")
        case "claude": if p.count >= 2 { OnClaude(p[1], p.count >= 3 ? p[2] : "x") }
        case "tag":
            Count("deploys")
            if HoldIfQuiet("tag", "上版成功" + (p.count >= 3 && p[2] == "prod" ? "（正式機）" : "")) { break }
            let env = p.count >= 3 ? p[2] : ""
            var fired = false
            for x in outs { x.Celebrate(env, !fired && (x.P.Id == "spidey" || x.P.Id == "po" || x === l)); if x.P.Id == "spidey" || x.P.Id == "po" { fired = true } }   //@fan
            // <public> for x in outs { x.Celebrate(env, !fired && x === l) }
            if !fired && outs.Count > 0 { Fireworks(WA(l.Cx, l.y), 8, -1) }
            if outs.Count == 0 { l.Celebrate(env, true) }
        case "birthday": birthday = p.count >= 2 ? p[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""; SeasonNow = Season()
        case "typing":
            if p.count >= 2, let chars = Int(p[1]) {
                typingStreak = chars >= 30 ? typingStreak + 1 : 0
                if typingStreak >= 2 && danceCd <= 0 && !Hidden {
                    danceCd = 150
                    for x in outs { if x === l || rnd.NextDouble() < 0.5 { x.OnTyping() } }
                }
            }
        case "act": if p.count >= 2 { Act(p[1], p.count >= 3 ? p[2] : "") }
        case "where":
            var sb = ""
            for x in Pets { if x.Out { let pid: String = x.P.Id; let px: String = String(CInt(x.x)), py: String = String(CInt(x.y)); sb += "pos " + pid + " " + px + " " + py + " " + x.state + "\n" } }
            sb += "end\n"
            World.Send(c, sb)
        case "shelf-info":   // 測試用（test/desktop-shelf.js）
            let si: String = shelf == nil ? "" : shelf.Info()
            let mk: Bool = maker != nil && !maker.IsDisposed && maker.VVisible
            World.Send(c, si + "maker " + (mk ? "1" : "0") + "\nend\n")
        case "feat-info":   // 測試用（test/desktop-egg.js）
            var fb = "feat"
            for f in World.FeatureList { fb += " " + f[0] + "=" + (Feat(f[0]) ? "1" : "0") }
            let nn: String = NightNow() ? "1" : "0"
            World.Send(c, fb + " nightnow=" + nn + " set=" + featSet.ToArray().joined(separator: ",") + "\nend\n")
        case "mode-info":   // 測試用（test/desktop-egg.js）
            let md: String = Single ? "single " + SinglePet() : "shelf -"
            let col: String = shelf != nil && shelf.Collapsed ? "1" : "0", prof: String = File.Exists(World.FilePath("profile.txt")) ? "1" : "0", hint: String = World.ReadText("egg-hint.txt") == "" ? "0" : "1"
            World.Send(c, "mode " + md + " collapsed=" + col + " profile=" + prof + " hint=" + hint + "\nend\n")
        case "setup-info":   // 測試用（test/desktop-woban.js）：設定視窗現在有哪些按鈕
            let sv: Bool = setupForm != nil && !setupForm.IsDisposed && (setupForm.VVisible || setupForm.Visible)
            World.Send(c, (sv ? setupForm.Info() : "setup none\n") + "end\n")
        case "notify":
            if p.count >= 4 {
                // 文字可以有空白：取第三個空白之後全部
                let t = Array(line.trimmingCharacters(in: .whitespacesAndNewlines))
                let i1 = World.IdxSpace(t, 0), i2 = World.IdxSpace(t, i1 + 1), i3 = World.IdxSpace(t, i2 + 1)
                OnNotify(p[1], p[2], i3 > 0 ? World.AfterIdx(t, i3 + 1) : "")
            }
        case "remind":
            if p.count >= 3 {
                let t = Array(line.trimmingCharacters(in: .whitespacesAndNewlines))
                let i1 = World.IdxSpace(t, 0), i2 = World.IdxSpace(t, i1 + 1)
                if let ms = Int(p[1]) { AddReminder(ms, i2 > 0 ? World.AfterIdx(t, i2 + 1) : "") }
            }
        case "ticket":
            if p.count >= 5 {
                // ticket <unixMs> <提前分鐘> <url|-> <名稱…>
                let t = Array(line.trimmingCharacters(in: .whitespacesAndNewlines))
                let i1 = World.IdxSpace(t, 0), i2 = World.IdxSpace(t, i1 + 1), i3 = World.IdxSpace(t, i2 + 1), i4 = World.IdxSpace(t, i3 + 1)
                if let ms = Int(p[1]), let lead = Int(p[2]) { AddTicket(ms, lead, p[3], i4 > 0 ? World.AfterIdx(t, i4 + 1) : "") }
            }
        case "lineup": SwitchLineup(p.count >= 2 ? p[1] : "", p.count >= 3 ? p[2] : ""); World.Send(c, "lineup " + lineup + "\n")   // 回報現在是哪一櫃（VS Code 用來判斷桌面版是不是舊版）
        case "config-host": companyHost = p.count >= 2 ? p[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        case "snap": if p.count >= 2 { Snap(p[1], World.ParseRect(p, 2)) }; World.Send(c, "snapped\n")
        case "snaps":
            // snaps <資料夾> <張數> <間隔ms> [x y w h]
            if p.count >= 4, let n = Int(p[2]), let ms = Int(p[3]) {
                let dir = p[1]; let rr = World.ParseRect(p, 4)
                var i = 0
                while i < n {
                    let ii = i
                    Later(Double(i * ms) / 1000.0) { self.Snap((dir as NSString).appendingPathComponent("f" + String(format: "%02d", ii) + ".png"), rr) }
                    i += 1
                }
            }
        case "quit": QuitAll()
        default: if !MisMsg(c, p, line) && !OrigMsg(c, p, line) && !StatsMsg(c, p, line) { StudyMsg(c, p, line) }   // mischief-…（59_mischief.swift）；stats-…（61_stats.swift）；course／exam／study-…（52_study.swift）
        }
    }

    // 選單、VS Code 指令、測試共用（pipe 訊息 "act <名稱> [參數]"）
    func Act(_ a: String, _ arg: String) {
        let l: Pet = Lead()
        let target = Get(arg)
        switch a {
        case "select": if target != nil { SelectOnly(target!) }; return
        case "out": if target != nil { BringOut(target!, true) }; return
        case "in": if target != nil && target!.Out { target!.StowToShelf(true) }; return
        case "all": AllOut(); return
        case "home": AllHome(); return
        case "shelf": if l.Out { l.StowToShelf(true) }; return
        case "ball": StartBall(arg == "here"); return
        case "hide": ToggleHide(); return
        case "show": if userHidden { ToggleHide() } else { l.Act("hi") }; return   // 獨立版又被打開一次（Dock）：躲起來的就出來，不然打個招呼
        case "fireworks": for x in OutPets() { x.Celebrate("dev", x === l) }; if OutCount() == 0 { l.Celebrate("dev", true) }; return
        case "dark", "night": forceNight = 1; nightChecked = -1; CheckNight(); return
        case "light", "day": forceNight = 0; nightChecked = -1; CheckNight(); return
        case "auto": forceNight = -1; nightChecked = -1; CheckNight(); forceLunch = -1; LunchTick(true); return
        case "lunch": forceLunch = 1; LunchTick(true); return
        case "egg": ToggleEgg(true); return
        case "unegg": ToggleEgg(false); return
        case "shelfhover":   // 測試用：滑鼠移到櫃子上的這一點
            let q = arg.components(separatedBy: ",")
            if shelf != nil, q.count == 2, let hx = Int(q[0]), let hy = Int(q[1]) { shelf.SimHover(Point(hx, hy)) }
            return
        case "lunchnap": forceLunch = 2; LunchTick(true); return
        case "lunchsoon": forceLunch = -1; LunchState = "nap"; for x in OutPets() { x.WakeIfSleep() }; LunchState = "soon"; Lead().Say("午休快結束囉～", 3); return
        case "lunchend": forceLunch = 0; LunchTick(true); return
        case "fav": SetFav(target ?? l); return
        case "scene": PlayScene(arg); return
        case "flower": PikFlowerAct(arg); return   //@fan
        case "whistle": Whistle(); return   //@fan
        case "photo": GroupPhoto(); return
        case "rollcall":
            let ids = List<String>(); for x in OutPets() { ids.Add(x.P.Id) }; if ids.Count == 0 { for x in Pets { ids.Add(x.P.Id) } }; StartRollCall(ids); return
        case "done": OnDone(arg == "" ? "Codex" : arg); return
        case "stuck": OnStuck(arg == "" ? "Codex" : arg, "tool", "exec_command", "", 3); return
        case "focus": StartFocus(Int(arg) ?? 25); return
        case "focusstop": StopFocus(false); return
        case "wrap": DailyWrap(true); return
        case "dlseen": DlSeen(arg); return   // 測試用：假裝下載資料夾出現這個檔
        case "quiet": StartQuiet(Int(arg) ?? 30); return
        case "click":
            let q = arg.components(separatedBy: ",")
            if q.count == 2, let cx2 = Int(q[0]), let cy2 = Int(q[1]) { SimClick(cx2, cy2) }
            return
        case "throw":
            // act throw <id>,x,y,vx,vy（測試用：模擬拖著丟出去）
            let q = arg.components(separatedBy: ",")
            if q.count == 5, let tx2 = Double(q[1]), let ty2 = Double(q[2]), let tvx2 = Double(q[3]), let tvy2 = Double(q[4]) {
                let tp = Get(q[0]); if tp != nil { tp!.SimThrow(tx2, ty2, tvx2, tvy2) }
            }
            return
        case "drop":
            let q = arg.components(separatedBy: ",")
            if q.count == 3, let cx2 = Int(q[1]), let cy2 = Int(q[2]) { SimDrop(Get(q[0]), cx2, cy2) }
            return
        // 測試用：act menu pet|house、act menuhover <列>、act menuclick <列>、act menuclose、act setup [按鈕]
        case "menu": TestMenu(arg); return
        case "menuhover": if pmenu != nil, let mi = Int(arg) { pmenu.SetHover(mi) }; return
        case "menuclick": if pmenu != nil, let mi = Int(arg) { pmenu.Pick(mi) }; return
        case "menuclose": if pmenu != nil { pmenu.CloseMenu() }; return
        case "setup": if arg == "" { ShowSetup(false) } else if setupForm != nil && !setupForm.IsDisposed { setupForm.Press(arg) }; return
        case "feature": do { let q = arg.components(separatedBy: "="); if q.count == 2 { SetFeat(q[0], q[1] == "1") } }; return
        case "mischief": MisAct(arg); return   // 搗蛋：act mischief cursor|clear|shop|typing|restore|stop（59_mischief.swift）
        case "stats": StatsAct(arg); return   // 匿名回報的開關：act stats 0|1（61_stats.swift）
        default: break
        }
        if target != nil && arg != "" { target!.Act(a) } else { l.Act(a) }
    }

    func QuitAll() {
        MisQuit()   // 推走的視窗先全部叫回來、不再數按鍵（59_mischief.swift）
        closing = true
        SaveUsage(); SaveOut()
        lock(clients) { for c in clients { World.Send(c, "bye\n") } }
        timer.Stop()
        for p in Pets { p.CloseForms() }
        for f in webs { f.Close() }
        if shelf != nil { shelf.Close() }
        if ballF != nil { ballF.Close() }
        if fx != nil { fx.Close() }
        if flash != nil { flash.Close() }
        ClearProps()
        // mac: 關掉 socket、刪掉 socket 檔、放掉快速鍵
        if listenFd >= 0 { close(listenFd); listenFd = -1 }
        if !pipeName.isEmpty { unlink(pipeName) }
        if let hk = World.hotKeyRef { UnregisterEventHotKey(hk); World.hotKeyRef = nil }
        Application.Exit()
    }
}
