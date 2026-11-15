// 50_pikmin.swift — port of extension/desktop/DeskPals.Pikmin.cs
// Desk Pals：皮克敏一櫃（紅、黃、藍皮克敏＋大格的休息花）。個人用的同人像素，與任天堂無關。
import Foundation

// ================= 角色資料 =================
//@@IN Pal
    var Pik: Bool = false                      // 皮克敏（頭上的葉子／花苞／花會長大）
//@@END

extension Pal {
    static let Pikmin = "pikmin"
    static let PikminIds: [String] = ["pkred", "pkyellow", "pkblue"]

    static func PikminPals() -> List<Pal> { return List<Pal>([PikRed(), PikYellow(), PikBlue()]) }

    // 18 格寬的格子，身體在第 8～9 欄。頭上的葉子／花苞／花另外疊在莖的頂端（每隻每天各自長）
    static let PK_STEM: [String] = [
        "..........r.......",
        ".........r........",
        ".........r........",
        "........rr........" ]
    static let PK_HEAD: [String] = [
        "........oo........",
        ".......orro.......",
        "......orhrro......",
        ".....orhrrrro.....",
        "....orhrrrrrro....",
        "...orhrrrrrrrRo...",
        "...oWKWrrrrWKWo...",
        "...oWKWrrrrWKWo...",
        "...orrrrrrrrrRo...",
        "...orrrrrrrrRRo...",
        "....orrrrrrRRo....",
        ".....oorrrRoo....." ]
    static let PK_BODY: [String] = [
        ".......orRo.......",
        "......orrrRo......",
        ".....r.orRo.r.....",
        "....r..orRo..r....",
        ".......orRRo......" ]
    static let PK_BODY_UP: [String] = [
        "....r..orRo..r....",
        ".....rorrrRor.....",
        ".......orRo.......",
        ".......orRo.......",
        ".......orRRo......" ]
    static let PK_LEGS_A: [String] = [".......o...o......", "......oo...oo....."]
    static let PK_LEGS_B: [String] = ["......o.....o.....", ".....oo.....oo...."]
    static let PK_LEGS_SIT: [String] = ["......oo...oo....."]
    static let PK_LEAF: [String] = [
        "............GGGG..",
        "..........GGgGGGG.",
        ".........GgGGGGG..",
        "........GgGGGG....",
        "........GGG......." ]
    static let PK_BUD: [String] = [
        "..................",
        ".........WW.......",
        "........WWWW......",
        "........WWWw......",
        "........GWwG......" ]
    static let PK_FLOWER: [String] = [
        ".......WW..WW.....",
        "......WWWwwWWW....",
        ".......wWYYWw.....",
        "......WWWyyWWW....",
        ".......WW.gWW....." ]

    static func Dusk(_ rgb: Int) -> Int {
        let r = (rgb >> 16) & 255, g = (rgb >> 8) & 255, b = rgb & 255
        let nr = CInt(Double(r) * 0.72 + 8), ng = CInt(Double(g) * 0.70 + 12), nb = CInt(Math.Min(255.0, Double(b) * 0.75 + 40))
        return (nr << 16) | (ng << 8) | nb   // 天黑：暗一點、偏一點點藍，不要變成泥巴色
    }
    func PCol(_ c: Character, _ day: Int) { Col(c, day, Pal.Dusk(day)) }

    static func PikBase(_ id: String, _ name: String, _ r: Int, _ R: Int, _ h: Int, _ o: Int) -> Pal {
        let p = Pal()
        p.Id = id; p.Name = name; p.Pik = true; p.BallKind = "tennis"; p.NightStyle = "sleepy"; p.NightBubble = 3
        p.Halo = Color.White; p.HaloNight = C(0xB8C4F0)
        p.Art["STEM"] = PK_STEM; p.Art["HEAD"] = PK_HEAD; p.Art["BODY"] = PK_BODY; p.Art["ARMS_UP"] = PK_BODY_UP
        p.Art["LEGS_A"] = PK_LEGS_A; p.Art["LEGS_B"] = PK_LEGS_B; p.Art["LEGS_SIT"] = PK_LEGS_SIT
        p.Art["LEAF"] = PK_LEAF; p.Art["BUD"] = PK_BUD; p.Art["FLOWER"] = PK_FLOWER
        let total = PK_LEAF.count + PK_STEM.count + PK_HEAD.count + PK_BODY.count + PK_LEGS_A.count
        p.TopRows = total - 16
        p.BodyTop = 16 - PK_LEGS_A.count - PK_BODY.count
        p.HeadTop = p.BodyTop - PK_HEAD.count
        p.FaceRow = 6; p.EyeRow = -1; p.NoGlasses = true
        p.HatRow = p.HeadTop + 2; p.HatCol = 0; p.ScarfRow = p.HeadTop + 11; p.GlassRow = p.HeadTop + 6
        p.BadgeRow = p.BodyTop + 2; p.BadgeCol = 5; p.SideRow = p.BodyTop + 1
        p.PCol("r", r); p.PCol("R", R); p.PCol("h", h); p.PCol("o", o)
        p.PCol("W", 0xFFFFFF); p.PCol("w", 0xE2E6D2); p.PCol("K", 0x111111); p.PCol("G", 0x3E9E3A); p.PCol("g", 0x7CCB5A)
        p.PCol("y", 0xE09A1A); p.PCol("O", 0xF2852A); p.PCol("b", 0x5AA8E8); p.PCol("v", 0x7A4FC4); p.PCol("V", 0x56309A)
        p.PCol("k", 0x2A2A2A); p.PCol("e", 0xF2B418); p.PCol("N", 0xB81E1C); p.PCol("n", 0xFF8C7C); p.PCol("M", 0xF29AA6)
        p.Accent = C(o); p.Panel = C(0xE8F0D8)
        return p
    }

    // 共用台詞（皮克敏話很少：噗咿！嘿咻！＋短短的中文）
    func PikLines(_ me: String) {
        Say("talk", "噗咿！", "噗咿～", "嘿咻！", me + "在這裡～", "噗咿？（歪頭）", "要喝可樂嗎？噗咿！🥤")
        Say("talk_d", "噗咿…（想睡）", "天黑了…回土裡睡覺…", "噗咿…晚安…", "下班了…噗咿")
        Say("save", "噗咿！存好了！", "嘿咻！收好了～", "噗咿！👍"); Say("save_d", "存好了…噗咿…回家吧", "收好了…晚安")
        Say("pats", "噗咿～", "噗咿！（開心）", "嘿嘿…噗咿", "（葉子晃晃）噗咿！", "喜歡～噗咿！")
        Say("pats_d", "噗咿…（想睡）", "摸摸…然後回家…", "嗯…噗咿…晚安")
        Say("pats_hi", "噗咿！最喜歡你了！", "我們是好夥伴！噗咿！", "一直跟著你～噗咿！")
        Say("hugs", "噗咿～抱抱！", "抱抱！噗咿！", "(つ´ω`)つ 噗咿"); Say("hugs_d", "抱抱…晚安…噗咿", "抱完回家…")
        Say("knock", "叩叩！噗咿！", "噗咿？（敲敲）", "要出去！噗咿！"); Say("knock_d", "叩叩…天黑了…回家", "噗咿…下班了…")
        Say("newwin", "噗咿！", "噗咿？新的！", "嘿咻！去看看！"); Say("newwin_d", "噗咿…明天再看…", "天黑了…關掉吧")
        Say("hi", "噗咿！" + me + "！👋"); Say("hi_d", "噗咿…（揮手）")
        Say("wake", "噗咿？醒了！"); Say("wake_d", "噗咿…還在睡…")
        Say("dizzy", "噗咿咿咿…@@"); Say("dizzy_d", "暈…睡覺…")
        Say("dizzy_ok", "噗咿！好了！"); Say("dizzy_ok_d", "好了…回家…")
        Say("pat10", "今天第 {n} 次！噗咿！"); Say("pat10_d", "第 {n} 次…晚安…")
        Say("levelup", "好感度 Lv{n}！拿到「{u}」！噗咿！"); Say("levelup_d", "Lv{n}…「{u}」…明天戴")
        Say("missed", "好久沒摸了…噗咿…🥺"); Say("missed_d", "好久沒摸了…")
        Say("hover", "噗咿？摸摸？")
        Say("seek", "噗咿？那是什麼？"); Say("seek_lost", "噗咿…不見了"); Say("seek_got", "抓到了！噗咿！")
        Say("drag", "噗咿咿咿！"); Say("throw", "噗咿～～～！")
        Say("shelf_in", "噗咿～回土裡囉"); Say("shelf_in_d", "噗咿…回土裡睡覺…")
        Say("shelf_out", "（從土裡探頭）噗咿？", "（土裡）噗咿～"); Say("shelf_out_d", "（土裡）…天黑了耶？")
        Say("ball_go", "噗咿！球！", "嘿咻！搬回去！", "大家來搬！"); Say("ball_go_d", "最後一顆…")
        Say("ball_catch", "嘿咻嘿咻～還你！", "搬回來了！噗咿！", "噗咿！好重！"); Say("ball_catch_d", "搬回來了…回家…")
        Say("ball_end", "不玩了？噗咿～"); Say("ball_end_d", "不玩了…睡覺…")
        Say("ball_far", "球太遠了…噗咿…")
        Say("back", "噗咿！回來了！"); Say("back_d", "噗咿…回來了…")
        Say("share_end", "分享完了？噗咿！")
        Say("welcome", "噗咿！你回來了！"); Say("welcome_d", "回來了…是要回家了嗎？")
        Say("rest", "花都枯了…起來喝口可樂、走一走 🥤"); Say("rest_d", "花都枯了…喝完可樂就下班吧 🥤")
        Say("night_on", "天黑了…噗咿…回土裡睡覺"); Say("night_off", "噗咿！早安！太陽出來了 ☀")
        Say("sleep", "噗咿…zZ"); Say("sleep_d", "晚安…噗咿…")
        Say("jump", "嘿咻！"); Say("nojump", "噗咿…跳不上去")
        Say("errors", "噗咿！有 {n} 個錯誤！"); Say("errors_d", "{n} 個錯誤…明天再修…")
        Say("errors_ok", "錯誤搬光了！噗咿！"); Say("errors_ok_d", "修好了…回家吧")
        Say("typing", "嘿咻嘿咻！打好快！", "噗咿！加油！", "手指跑好快～噗咿！"); Say("typing_d", "快打完…回家…")
        Say("done", "噗咿！{who} 做完了！"); Say("done_d", "{who} 做完了…回家吧")
        Say("wait", "{who} 在等你回答！噗咿！"); Say("wait_d", "{who} 在等你…回完回家")
        Say("ask", "{who} 有問題！噗咿？"); Say("ask_d", "{who} 在問你…回完回家")
        Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了！要按允許嗎？噗咿？"); Say("stuck_tool_d", "{who} 停了 {n} 分鐘…按一下回家")
        Say("stuck", "{who} 不動了…{n} 分鐘！噗咿！"); Say("stuck_d", "{who} 卡 {n} 分鐘…看一下回家")
        Say("unstuck", "{who} 動了！噗咿！"); Say("unstuck_d", "{who} 動了…")
        Say("tag", "上版成功！噗咿！🎉"); Say("tag_dev", "測試機成功！嘿咻！"); Say("tag_prod", "正式機成功！大家噗咿！🎉"); Say("tag_d", "上版了…回家睡覺")
        Say("late23", "好晚了…噗咿…🌙"); Say("late12", "吃飯了沒？果汁！"); Say("late15", "點心時間～花蜜！")
        Say("late_d", "天黑了…回家吧"); Say("late_dd", "好晚…睡覺！")
        Say("g_late", "這麼晚…" + me + "陪你 🌙"); Say("g_morning", "噗咿！早安！"); Say("g_noon", "噗咿！午安～吃了沒？")
        Say("g_evening", "噗咿～晚上了"); Say("g_day", "噗咿！" + me + "出來了！"); Say("g_d", "天黑了…你怎麼還在？噗咿…")
        Say("app_browser", "噗咿？在看什麼？"); Say("app_code", "寫 code！噗咿！"); Say("app_excel", "好多格子…噗咿？")
        Say("app_ppt", "簡報～噗咿！"); Say("app_word", "寫字字～"); Say("app_chat", "有人找你？噗咿？"); Say("app_files", "找東西？一起搬！")
        Say("app_other", "噗咿？這是什麼？")
        Say("app_code_d", "還在寫…回家吧"); Say("app_chat_d", "明天再回…"); Say("app_office_d", "明天再做…噗咿"); Say("app_other_d", "回家…噗咿…")
        Say("s_birthday", "生日快樂！噗咿！🎂", "大家搬蛋糕來了！嘿咻！"); Say("s_cny", "新年快樂！噗咿！🧧"); Say("s_xmas", "聖誕快樂！噗咿！🎄")
        Say("s_newyear", "新年快樂！噗咿！✨"); Say("s_halloween", "不給糖就搗蛋！噗咿！🎃"); Say("s_friday", "星期五！噗咿！", "快放假了～嘿咻！")
        Say("morning", me + "！噗咿！"); Say("goodnight", "噗咿…晚安…（鑽回土裡）", "晚安～噗咿")
        Say("nag", "噗咿…下班了…", "回家吧…噗咿", "天黑了…回土裡…")
        Say("react", "噗咿？", "噗咿！", "咿？")
    }

    // ---------------- 紅皮克敏：勇敢、有點衝，會冒小火花 ----------------
    static func PikRed() -> Pal {
        let p = PikBase("pkred", "紅皮克敏", 0xE8312F, 0xB4201F, 0xFF7A6A, 0x7A1414)
        p.Speed = 75; p.Move = "march"
        p.PikLines("小紅")
        p.Say("talk", "噗咿！", "嘿！誰要打架！", "小紅不怕火！", "衝啊！噗咿！", "嘿咻！我最勇敢", "要喝可樂嗎？噗咿！🥤")
        p.Say("tickle", "嘿！別鬧！噗咿！", "噗咿！（冒火）", "再摸我就生氣囉！"); p.Say("tickle_d", "噗咿…不鬧了…")
        p.Say("hi", "噗咿！小紅！👋（握拳）")
        p.Say("seek", "嘿！那是什麼！衝！")
        p.Say("ball_go", "球！小紅來！", "衝啊！搬回去！")
        p.Shared()
        return p
    }

    // ---------------- 黃皮克敏：大耳朵、最愛被丟得高高的、會放小電花 ----------------
    static func PikYellow() -> Pal {
        let p = PikBase("pkyellow", "黃皮克敏", 0xF6C51E, 0xD49A0C, 0xFFE47A, 0x8A5A06)
        p.Speed = 70; p.Move = "hop"
        p.PikLines("小黃")
        p.Say("talk", "噗咿！", "丟我丟我！要飛高高！", "耳朵動動～噗咿", "滋滋～（電電）", "嘿咻！小黃最高！", "要喝可樂嗎？噗咿！🥤")
        p.Say("tickle", "噗咿咿！癢！（電電）", "滋滋滋～嘻嘻", "再丟一次！"); p.Say("tickle_d", "噗咿…不鬧了…")
        p.Say("drag", "噗咿！要丟了嗎！要丟了嗎！"); p.Say("throw", "噗咿～～～飛高高！")
        p.Say("hi", "噗咿！小黃！👋（耳朵揮揮）")
        p.Shared()
        return p
    }

    // ---------------- 藍皮克敏：冷靜、會游泳、吐泡泡 ----------------
    static func PikBlue() -> Pal {
        let p = PikBase("pkblue", "藍皮克敏", 0x2E6BE6, 0x1F4CB8, 0x6E9CFF, 0x14286E)
        p.Speed = 62; p.Move = "swim"
        p.PikLines("小藍")
        p.Say("talk", "噗咿。", "咕嚕咕嚕～", "小藍會游泳喔", "不要急，慢慢來", "水裡很舒服…噗咿", "要喝可樂嗎？噗咿 🥤")
        p.Say("tickle", "咕嚕咕嚕！（吐泡泡）", "噗咿～好癢", "嘻…泡泡～"); p.Say("tickle_d", "咕嚕…睡覺…")
        p.Say("hi", "噗咿。小藍。👋")
        p.Shared()
        return p
    }
}

// ================= 一隻皮克敏 =================
//@@IN Pet
    var pikAct = ""              // 皮克敏專屬動作（state == "pik"）
    var pikT: Double = 0, pikTarget: Double = Double.nan, flameT: Double = 0, sparkT: Double = 0
    var pikIdx = 0
    var PikCarrying = false      // 串場：一起搬東西
    var PikHold = ""             // 手上拿的（午餐水果、果汁）
    var pikStage = -1; var pikStageDay = ""
    var pendAct: String? = nil; var pendDur: Double = 0; var pendTarget: Double = Double.nan   // 在空中被叫去做事：落地再做（不然會停在半空中）
//@@END

extension Pet {
    var PikGoing: Bool { return state == "pik" && pikAct == "goto" }

    // 頭上的葉子／花苞／花：每天重新從葉子開始，喝花蜜長大（記在資料夾，一天一份）
    var PikStage: Int {
        let today = DateTime.Now.ToString("yyyy-MM-dd")
        if pikStage < 0 || pikStageDay != today {
            pikStage = 0; pikStageDay = today
            if let txt = try? File.ReadAllText(Path.Combine(World.DataDir, "pikstage-" + P.Id + ".txt")) {
                let a = txt.Trim().Split(" ")
                var s = 0
                if a.count == 2 && a[0] == today && int.TryParse(a[1], &s) { pikStage = Math.Max(0, Math.Min(2, s)) }
            }
        }
        return pikStage
    }
    func PikGrow() {
        let s = Math.Min(2, PikStage + 1)
        pikStage = s
        _ = try? Directory.CreateDirectory(World.DataDir)
        _ = try? File.WriteAllText(Path.Combine(World.DataDir, "pikstage-" + P.Id + ".txt"), pikStageDay + " " + String(s))
    }
    func PikSetStage(_ s: Int) { pikStage = Math.Max(0, Math.Min(2, s)); pikStageDay = DateTime.Now.ToString("yyyy-MM-dd") }
    func PikTop() -> [String] { let s = PikStage; return A(s == 2 ? "FLOWER" : (s == 1 ? "BUD" : "LEAF")) }

    func PikDo(_ act: String, _ dur: Double) {
        if state == "air" || state == "fling" || state == "drag" { pendAct = act; pendDur = dur; pendTarget = pikTarget; return }
        pikAct = act; pikT = 0; SetState("pik", dur)
        if act == "punch" { flameT = Math.Max(flameT, 1.0) }
    }
    func PikGoto(_ tx: Double, _ act: String, _ dur: Double) { pikTarget = tx; PikDo(act, dur) }
    func PikFollow(_ idx: Int, _ dur: Double) { pikIdx = idx; PikDo("follow", dur) }
    func PikSpark(_ sec: Double) { sparkT = Math.Max(sparkT, sec) }
    func PikFlame(_ sec: Double) { flameT = Math.Max(flameT, sec) }
    func PikPop(_ text: String?) {
        // 從土裡被拔出來：噗！
        Jump(Double(dir) * 40 * k, -380 * k); Burst(6); Say(text ?? Pick(["噗！", "噗！噗咿！", "（拔出來）噗咿！"]), 1.2)
    }

    // 連點三下
    func PikCombo() {
        Say(L("tickle"), 1.8)
        if !Grounded() || state == "dizzy" { return }
        if Is("pkred") { PikDo("punch", 1.2) }
        else if Is("pkyellow") { sparkT = 1.4; Jump(Double(dir) * 30 * k, -520 * k) }
        else { SetState("idle", 1.6); for _ in 0..<5 { Mark(5) } }
    }

    func PikSignature() {
        if !Grounded() { return }
        if Is("pkred") { PikDo("punch", 1.6); Say(Pick(["嘿！嘿！看我的！", "衝啊！噗咿！", "（冒火）嘿！"]), 1.4) }
        else if Is("pkyellow") { sparkT = 2.2; Jump(Double(dir) * 60 * k, -820 * k); Say(Pick(["噗咿～～飛高高！", "滋滋～跳！"]), 1.4) }
        else { PikDo("swim", 3.4); Say(Pick(["咕嚕咕嚕～游泳！", "小藍會游泳喔～"]), 1.6) }
    }

    func PikAct(_ a: String) -> Bool {
        switch a {
        case "whistle": w.Whistle(); return true
        case "pikfight": if Grounded() { PikDo("punch", 1.6); Say("嘿！嘿！", 1.2) }; return true
        case "pikjump": if Grounded() { sparkT = 2.2; Jump(Double(dir) * 60 * k, -820 * k); Say("噗咿～～！", 1.2) }; return true
        case "pikswim": if Grounded() { PikDo("swim", 3.4); Say("咕嚕咕嚕～", 1.2) }; return true
        case "pikmill": if Grounded() { PikDo("mill", 3.2); Say("噗咿？", 0.8) }; return true
        default: break
        }
        return false
    }

    func PikDecide(_ r: Double, _ wa: Rectangle) {
        if r < 0.16 { SetState("idle", R(1.5, 3.5)) }
        else if r < 0.42 { dir = rnd.NextDouble() < 0.5 ? -1 : 1; SetState("walk", R(2.5, 6)) }
        else if r < 0.52 { if !JumpToPlatform() { Hop() } }
        else if r < 0.60 { PikDo("mill", R(2.5, 4)) }                         // 沒事做：原地繞來繞去
        else if r < 0.66 { PikSignature() }
        else if r < 0.70 { Hug(L("hugs"), 2.2) }
        else if r < (Night ? 0.75 : 0.73) { Knock(L("knock"), "ambient") }
        else if r < 0.76 && lateCd <= 0 && LateLine() != nil { LateTick() }
        else if r < 0.79 && SeasonLine() != nil { Say(SeasonLine(), 3); SetState("idle", 3) }
        else if r < 0.90 { SetState("idle", 2.5); Say(L("talk"), 2.2) }
        else { dir = -dir; SetState("walk", R(2, 5)) }
    }

    func PikEdge(_ right: Bool) -> Int {
        let brave: Double = Is("pkred") ? 0.7 : (Is("pkyellow") ? 0.6 : 0.4)
        if rnd.NextDouble() > brave { dir = -dir; return 1 }
        x += Double(dir) * 4 * k
        if Is("pkyellow") { Jump(Double(dir) * 120 * k, -560 * k); sparkT = 1.2; Say("噗咿～！", 0.8) }
        else { Jump(Double(dir) * 130 * k, -300 * k); Say(Is("pkred") ? "嘿！" : "噗咿。", 0.8) }
        return 2
    }

    func PikLanded(_ wasRolling: Bool) -> Bool {
        if pendAct != nil { let a = pendAct!; pendAct = nil; pikTarget = pendTarget; SetState("idle", 0.1); PikDo(a, pendDur); return true }
        if Is("pkyellow") && lastLandVy > 700 * k { SetState("pose", 1.2); poseKind = "photo"; Say(Pick(["噗咿！好高！再一次！", "再丟一次！噗咿！"]), 1.6); sparkT = 1; return true }
        if Is("pkred") && lastLandVy > 900 * k { PikDo("punch", 1.0); Say("嘿！沒事！", 1.2); return true }
        return false
    }

    func PikLand(_ a: String) -> Bool {
        if a == "pksprout" { PikDo("sprout", R(0.5, 0.8)); return true }
        return false
    }

    // 被拿起來丟：黃皮克敏最愛，飛得更高
    func PikThrown(_ tvx: inout Double, _ tvy: inout Double) {
        if !Is("pkyellow") { return }
        tvy = tvy * 1.3 - 260 * k
        sparkT = 1.6
    }

    func PikReact(_ why: String) {
        if Is("pkred") { PikDo("punch", 1.2) }
        else if Is("pkyellow") { sparkT = 1; Jump(0, -300 * k) }
        else { SetState("idle", 2); Mark(4) }
    }

    func PikLine(_ kind: String) -> String {
        switch kind {
        case "goal": return Is("pkyellow") ? "噗咿！飛進去了！再一次！🏀" : (Is("pkred") ? "嘿！進球！🏀" : "噗咿。進球～🏀")
        case "cheer": return Pick(["噗咿！", "噗咿噗咿！", "嘿咻！"])
        case "miss": return Is("pkyellow") ? "噗咿～差一點！再丟一次！" : "噗咿…沒進…"
        default: break
        }
        return "噗咿！"
    }

    // ---------- 球：大家把球搬回來給你 ----------
    func PikBall() {
        w.HoldBall(self)
        let c = Cursor.Position
        let wa = w.WA(Cx, y + Double(SH) / 2.0)
        PikGoto(Clamp(Double(c.X), Double(wa.Left + SW), Double(wa.Right - SW)), "carryball", 3.2)
        Say(Pick(["嘿咻嘿咻！", "噗咿！搬回去！", "嘿咻～"]), 1.4)
    }

    func PikStep(_ dt: Double) -> Bool {
        if flameT > 0 { flameT -= dt }
        if sparkT > 0 { sparkT -= dt }
        if P.Id == "pkblue" && state == "walk" && rnd.NextDouble() < dt * 0.3 { Mark(5) }
        if state != "pik" { return false }
        pikT += dt
        switch pikAct {
        case "sprout":
            if t < 0 { PikPop(nil) }
            return true
        case "dig":
            return true   // 世界控制何時收回櫃子
        case "follow":
            do {
                let c = Cursor.Position
                let lead: Pet! = w.Lead()
                let side: Double = (lead != nil ? lead.Cx : Cx) < Double(c.X) ? -1 : 1   // 大家排在游標同一邊，一列
                let tx = Double(c.X) + side * Double(pikIdx + 1) * Double(SW) * 1.25
                if Math.Abs(tx - Cx) > 5 { dir = tx > Cx ? 1 : -1; if MoveOnGround(dt, 170 * k) { return true } }
                if rnd.NextDouble() < dt * 0.4 { Say(Pick(["噗咿！", "嘿咻！"]), 0.7) }
                if t < 0 { SetState("idle", 1) }
                return true
            }
        case "march", "carry", "carryball", "goto":
            do {
                var sp: Double = pikAct == "march" ? 120 : (pikAct == "goto" ? 150 : 55)
                if !pikTarget.isNaN && Math.Abs(pikTarget - Cx) > Double(SW) * 0.5 && pikAct != "carryball" { sp = 150 }   // 還沒到位置：先跑過去
                if !pikTarget.isNaN && Math.Abs(pikTarget - Cx) > 3 {
                    dir = pikTarget > Cx ? 1 : -1
                    let step = Math.Min(Math.Abs(pikTarget - Cx), sp * k * dt)
                    let nx = x + Double(dir) * step
                    if w.Inside(nx + Double(dir > 0 ? SW : 0), y + Double(SH) / 2.0) { x = nx }
                }
                if pikAct == "carryball" && (t < 0 || Math.Abs(pikTarget - Cx) <= 3) {
                    if w.Holder === self { w.ReleaseBall(Cx, y + Double((P.HeadTop - 2) * S), 0, 0); KickBallToCursor(0.55) }
                    Say(L("ball_catch"), 1.6)
                    SetState("idle", 1)
                    return true
                }
                if pikAct == "carryball" && rnd.NextDouble() < dt * 0.5 && Bt <= 0 { Say("嘿咻嘿咻！", 0.8) }
                if t < 0 { SetState("idle", InScene ? 30 : 1) }
                return true
            }
        case "swim":
            x += Double(dir) * 38 * k * dt
            if !w.Inside(x + Double(dir > 0 ? SW : 0), y + Double(SH) / 2.0) { dir = -dir }
            if supH != IntPtr.Zero && (Cx < Double(supL + 4) || Cx > Double(supR - 4)) { dir = -dir }
            if rnd.NextDouble() < dt * 4 { Mark(5) }
            if t < 0 { SetState("idle", InScene ? 30 : 1) }
            return true
        case "drown":
            if rnd.NextDouble() < dt * 3 { Mark(4) }
            if t < 0 { SetState("idle", InScene ? 30 : 1) }
            return true
        case "mill":
            if Math.Floor(pikT * 1.4) != Math.Floor((pikT - dt) * 1.4) { dir = -dir }
            MoveOnGround(dt, 30 * k)
            if t < 0 { SetState("idle", 1) }
            return true
        case "drink":
            if pikT >= 0.9 && pikT - dt < 0.9 { PikGrow(); Burst(10); AddHeart(); Say(PikStage == 2 ? "噗咿！開花了！🌼" : "噗咿！（長大了）", 1.8) }
            if t < 0 { SetState("idle", InScene ? 30 : 1); if !InScene { Jump(0, -300 * k) } }
            return true
        default:   // punch／lift／tug／worry／throwup／cheer：站著做動作
            if pikAct == "worry" && rnd.NextDouble() < dt * 1.5 { Mark(4) }
            if t < 0 { SetState("idle", InScene ? 30 : 1) }
            return true
        }
    }

    func PikBob() -> Double {
        if state == "dance" { return Math.Abs(Math.Sin(anim * 8)) * 5 * k }
        if Is("pkyellow") && (state == "walk" || state == "goto") { return Math.Abs(Math.Sin(anim * 9)) * 3 * k }   // 蹦蹦跳
        if state == "pik" && pikAct == "mill" { return Math.Abs(Math.Sin(anim * 7)) * 2 * k }
        return 0
    }

    // ---------- 畫 ----------
    func PikHead(_ face: String?) -> [String] {
        var h: [String] = A("HEAD")
        var r6 = Array(h[6]), r7 = Array(h[7]), r8 = Array(h[8]), r9 = Array(h[9]), r10 = Array(h[10])
        let eyes = [4, 11]
        for e in eyes {
            if face == "SLEEPY" { r6[e] = "r"; r6[e + 1] = "r"; r6[e + 2] = "r"; r7[e] = "o"; r7[e + 1] = "o"; r7[e + 2] = "o" }
            else if face == "HAPPY" { r6[e] = "r"; r6[e + 1] = "o"; r6[e + 2] = "r"; r7[e] = "o"; r7[e + 1] = "r"; r7[e + 2] = "o" }
            else if face == "DIZZY" { r6[e] = "o"; r6[e + 1] = "r"; r6[e + 2] = "o"; r7[e] = "r"; r7[e + 1] = "o"; r7[e + 2] = "r" }
            else if face == "WORRY" { r6[e] = "W"; r6[e + 1] = "W"; r6[e + 2] = "W"; r7[e + 1] = "K" }
            else if face == "LOOKUP" { r6[e + 1] = "K"; r7[e + 1] = "W" }
        }
        if Is("pkred") { r8[8] = "n"; r8[9] = "n"; r9[8] = "N"; r9[9] = "N" }
        if Is("pkblue") { r9[8] = "M"; r9[9] = "M"; r10[7] = "M"; r10[10] = "M"; if face == "HAPPY" { r9[7] = "M"; r9[10] = "M"; r10[7] = "r"; r10[10] = "r" } }
        h[6] = String(r6); h[7] = String(r7); h[8] = String(r8); h[9] = String(r9); h[10] = String(r10)
        if Is("pkyellow") {
            // 尖尖的大耳朵（往外往上）；興奮時耳朵翹高一點
            let up = sparkT > 0 || (state == "pik" && pikAct == "cheer") || (state == "pose" && Step2(4))
            let earUp: [(Int, Int, Character)] = [(2, 0, "o"), (3, 0, "o"), (3, 1, "e"), (3, 2, "o"), (4, 0, "o"), (4, 1, "e"), (4, 2, "e"), (4, 3, "e"), (5, 1, "o"), (5, 2, "o")]
            let earDown: [(Int, Int, Character)] = [(3, 0, "o"), (4, 0, "o"), (4, 1, "e"), (4, 2, "o"), (5, 0, "o"), (5, 1, "e"), (5, 2, "e"), (5, 3, "e"), (6, 1, "o"), (6, 2, "o")]
            let ear = up ? earUp : earDown
            for e in ear {
                var row = Array(h[e.0])
                row[e.1] = e.2; row[17 - e.1] = e.2
                h[e.0] = String(row)
            }
        }
        return h
    }

    func FramePik() -> Fr {
        let sleep = state == "sleep", hug = state == "hug"
        let nightIdle = Night && state == "idle" && !InScene && !HoldingFood()
        let act = state == "pik" ? pikAct : ""
        var face: String? = nil
        let happy = hug || state == "dance" || act == "drink" || act == "cheer" || (state == "pose" && poseKind == "photo")
        if sleep || nightIdle || (state == "pik" && act == "dig") { face = "SLEEPY" }
        else if happy { face = "HAPPY" }
        else if state == "dizzy" || act == "drown" { face = "DIZZY" }
        else if act == "worry" { face = "WORRY" }
        else if act == "lift" || act == "carry" || act == "carryball" || act == "tug" { face = "LOOKUP" }
        var rows: [String] = PikTop()
        rows += A("STEM")
        rows += PikHead(face)
        var armsUp = state == "air" || state == "fling" || state == "drag" || state == "kick" || state == "catch" || hug
        armsUp = armsUp || (state == "dance" && Step2(4)) || (state == "wave" && Step2(4)) || (state == "pose" && poseKind == "photo")
        armsUp = armsUp || act == "lift" || act == "carry" || act == "carryball" || act == "tug" || act == "cheer" || act == "throwup" || act == "drown"
        armsUp = armsUp || (act == "punch" && Step2(6))
        rows += A(armsUp ? "ARMS_UP" : "BODY")
        let sit = sleep || nightIdle
        var moving = state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto"
        moving = moving || act == "follow" || act == "march" || act == "carry" || act == "carryball" || act == "goto" || act == "mill"
        let step = (moving && Step2(Is("pkyellow") ? 9 : 8)) || (state == "dance" && Step2(4))
        if sit { rows += A("LEGS_SIT") }
        else { rows += A(step ? "LEGS_B" : "LEGS_A") }
        let all = rows
        var f: Fr
        if act == "sprout" || act == "dig" {
            // 埋在土裡：只露出頭頂的葉子和一點點頭
            var show = PikTop().count + A("STEM").count + 3
            if act == "dig" { show = Math.Max(PikTop().count + 1, CInt(Math.Round(Double(all.count) - pikT / 0.8 * Double(all.count - PikTop().count - 1)))) }
            let cut = Array(all[0..<Math.Max(0, Math.Min(show, all.count))])
            f = F(cut); f.Acc = false
            return f
        }
        if act == "swim" || act == "drown" {
            // 泡在水裡：下半身沒入水面
            let cut = Array(all[0..<(all.count - 5)])
            f = F(cut); f.Top = act == "drown" ? 3 + (Step2(5) ? 1 : 0) : 2
            return f
        }
        f = F(all)
        if sit { f.AccDy = 1 }
        if rolling { f.Rot = CInt(Math.Floor(anim * 14)) % 4; f.Acc = false }
        return f
    }

    static let PK_FLAME: [String] = ["..Y..", ".YOY.", "YOOOY", ".OOO."]
    static let PK_SPARK: [String] = ["Y.", ".Y", "Y.", ".Y"]
    static let PK_PUDDLE_FRONT: [String] = [".bBBBBBBBBBBBBb.", "bBBbbBBBBBbbBBBb"]
    static let PK_STRAW: [String] = [".G.G.", "SSSSS", "SYSYS", ".SSS.", "..S.."]
    static let PK_BANANA: [String] = ["....1", "..YY1", ".YYY.", "YYY..", ".Y..."]
    static let PK_GRAPE: [String] = ["..G..", ".vv..", "vVvv.", ".vVv.", "..v.."]
    static let PK_JUICE: [String] = [".G..", "WWWW", "WOOW", "WOOW", ".WW."]
    static let PK_MOUND: [String] = ["....1111111111....", "..11222222222211..", ".1222222222222221."]

    func DrawPikBehind(_ g: Graphics, _ f: Fr, _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool) {
        let act = state == "pik" ? pikAct : ""
        if act == "swim" || act == "drown" {
            let wb = SolidBrush(Color.FromArgb(Night ? 120 : 140, 90, 168, 232))
            g.FillEllipse(wb, bx - 4 * ps, by + 12 * ps, 20 * ps, 5 * ps)
        }
    }

    func DrawPikFront(_ g: Graphics, _ f: Fr, _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool) {
        let act = state == "pik" ? pikAct : ""
        if act == "sprout" || act == "dig" { DrawAt(g, Pet.PK_MOUND, -3, 13, bx, by, ps, fx, false, true); return }
        if act == "swim" || act == "drown" { DrawAt(g, Pet.PK_PUDDLE_FRONT, -2, 14 - (Step2(3) ? 1 : 0) * 0, bx, by, ps, Step2(3), false, false) }
        if f.Rot != 0 || f.Fy { return }
        let top = f.Top + 16 - f.Rows.count   // 圖的第一列在框的第幾列
        let headRow = top + PikTop().count + A("STEM").count
        if Is("pkred") && (flameT > 0 || act == "punch") && Step2(10) { DrawAt(g, Pet.PK_FLAME, 9.5, headRow - 1, bx, by, ps, fx, false, true) }
        if Is("pkyellow") && sparkT > 0 {
            let flip = Step2(12)
            DrawAt(g, Pet.PK_SPARK, flip ? -4 : -5, headRow + 3, bx, by, ps, false, false, true)
            DrawAt(g, Pet.PK_SPARK, flip ? 14 : 15, headRow + 3, bx, by, ps, false, false, true)
        }
        if (act == "carryball" || pendAct == "carryball") && w.Holder === self {
            let ball = w.BallKind == "baseball" ? Pet.BALLART : Pet.TBALL
            DrawAt(g, ball, 4, headRow - 3, bx, by, ps, fx, false, true)
        }
        if PikHold != "" { DrawAt(g, PikHoldArt(PikHold), 9.5, P.BodyTop - 2 + f.AccDy, bx, by, ps, fx, false, true) }
    }

    func PikHoldArt(_ what: String) -> [String] {
        switch what {
        case "straw": return Pet.PK_STRAW
        case "banana": return Pet.PK_BANANA
        case "grape": return Pet.PK_GRAPE
        default: break
        }
        return Pet.PK_JUICE
    }

    func PikFruit() -> String { return Is("pkred") ? "straw" : (Is("pkyellow") ? "banana" : "grape") }

    func PikLunchLine(_ phase: String) -> String {
        let fruit = Is("pkred") ? "草莓" : (Is("pkyellow") ? "香蕉" : "葡萄")
        if phase == "start" { return "噗咿！午餐！" + fruit + "汁 🔔" }
        if phase == "nap" { return "吃飽了…噗咿…zZ" }
        if phase == "end" { return "噗咿！回來工作！" }
        return Pick([fruit + "！好甜！噗咿！", "果汁～咕嘟咕嘟", "嘿咻！再一口！"])
    }

    func DrawPikLunch(_ g: Graphics, _ f: Fr, _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool, _ bite: Int) {
        if PikHold != "" { return }   // 串場已經拿著水果了
        DrawAt(g, PikHoldArt(PikFruit()), 9.5, P.BodyTop - 2 + bite + f.AccDy, bx, by, ps, fx, false, true)
        DrawAt(g, Pet.PK_JUICE, -2.5, P.BodyTop - 1 + f.AccDy, bx, by, ps, fx, false, true)
    }

    func PikShelfRows() -> Int { return 16 + P.TopRows + 1 }

    // 櫃子裡：站在土上；紅的握拳冒火、黃的耳朵動動跳一下、藍的吐泡泡；晚上坐著睡
    func DrawPikShelf(_ g: Graphics, _ fx: Int, _ bx: Int, _ by: Int, _ ps: Int, _ flip: Bool, _ tt: Double, _ blink: Bool, _ cell: Rectangle) {
        var face: String? = nil
        var up = false
        var hop = 0
        if Night { face = "SLEEPY" }
        else if Is("pkred") && (tt % 7) < 1.2 { up = Step2(6); face = "LOOKUP" }
        else if Is("pkyellow") && (tt % 5) < 0.5 { hop = -ps * 2; up = true; face = "HAPPY" }
        else if blink { face = "SLEEPY" }
        let keepSpark = sparkT
        if Is("pkyellow") && !Night && (tt % 5) < 0.9 { sparkT = 1 }   // 耳朵翹起來
        var rows: [String] = PikTop()
        rows += A("STEM")
        rows += PikHead(face)
        rows += A(up ? "ARMS_UP" : "BODY")
        rows += A(Night ? "LEGS_SIT" : "LEGS_A")
        sparkT = keepSpark
        let r = rows
        let dy = Night ? 1 : 0
        DrawPix(g, r, bx - (r[0].Length - 12) / 2 * ps, by + (16 - r.count) * ps + hop, ps, flip, false, true)
        DrawAccessories(g, bx, by + hop, ps, flip, dy, face == nil)
        let headRow = 16 - r.count + PikTop().count + A("STEM").count
        if Is("pkred") && !Night && (tt % 7) < 1.2 && Step2(10) { DrawAt(g, Pet.PK_FLAME, 9.5, headRow - 1, bx, by, ps, flip, false, true) }
        if Is("pkyellow") && !Night && (tt % 5) < 0.9 {
            DrawAt(g, Pet.PK_SPARK, -5, headRow + 3, bx, by + hop, ps, false, false, true)
            DrawAt(g, Pet.PK_SPARK, 15, headRow + 3, bx, by + hop, ps, false, false, true)
        }
        if Is("pkblue") && !Night {
            let dps = Double(ps)
            let bp = Pen(Color.FromArgb(190, 150, 215, 255), Math.Max(1.0, dps * 0.35))
            for i in 0..<3 {
                let ph = (tt * 0.5 + Double(i) / 3.0) % 1
                let rr = dps * (0.5 + ph * 0.9)
                let px = Double(fx) + Math.Sin(ph * 9 + Double(i)) * dps + Double((flip ? -3 : 3) * ps)
                let py = Double(by + (headRow + 7) * ps) - ph * 10 * dps
                if py > Double(cell.Y) + rr { g.DrawEllipse(bp, px - rr, py - rr, 2 * rr, 2 * rr) }
            }
        }
        if w.Lunch { DrawAt(g, PikHoldArt(PikFruit()), 9.5, P.BodyTop - 2, bx, by, ps, flip, false, true) }
    }
}

// ================= 公仔櫃：土、大格的休息花 =================
//@@IN ShelfForm
    var Pik = false                     // 皮克敏一櫃：格子底下是土和草，大格種一朵休息花
//@@END

extension ShelfForm {
    // 每一格底下一層土＋小草（公仔站在土上）
    func DrawSoil(_ g: Graphics, _ inner: RectangleF, _ tall: Bool) {
        let st = g.Save()
        g.SetClip(inner)
        let dU = Double(U)
        let soil: Double = tall ? inner.Height * 0.16 : inner.Height * 0.09
        let band = RectangleF(inner.X, inner.Bottom - soil, inner.Width, soil + 1)
        let s1 = Night ? C(0x4A3828) : C(0x8A5E3A), s2 = Night ? C(0x2E2218) : C(0x5E3E24)
        g.FillRectangle(LinearGradientBrush(RectangleF(band.X, band.Y - 1, band.Width, band.Height + 2), s1, s2, 90.0), band)
        // 土粒
        let r = Random(tall ? 4 : 9)
        let pb = SolidBrush(Color.FromArgb(70, 30, 18, 8))
        for _ in 0..<(tall ? 26 : 10) {
            let px = band.X + r.NextDouble() * band.Width
            let py = band.Y + 2 + r.NextDouble() * (band.Height - 3)
            g.FillRectangle(pb, px, py, Math.Max(1.0, dU * 0.5), Math.Max(1.0, dU * 0.5))
        }
        // 草
        let gp = Pen(Night ? C(0x3E6A3A) : C(0x5CB04A), Math.Max(1.0, dU * 0.45))
        let n = tall ? 14 : 7
        for i in 0..<n {
            let gx = band.X + ((Double(i) + r.NextDouble() * 0.7) / Double(n)) * band.Width
            let h = dU * (1.2 + r.NextDouble() * 1.4)
            g.DrawLine(gp, gx, band.Y + 1, gx - dU * 0.4, band.Y - h)
            g.DrawLine(gp, gx + dU * 0.6, band.Y + 1, gx + dU * 0.9, band.Y - h * 0.8)
        }
        g.Restore(st)
    }

    // 大格：花圃（土堆比較高）
    func DrawFlowerBed(_ g: Graphics, _ c: Rectangle) {
        let inner = RectangleF(Double(c.X), Double(c.Y), Double(c.Width), Double(c.Height - plateH))
        let top = inner.Bottom - inner.Height * 0.16
        g.FillEllipse(SolidBrush(Night ? C(0x3E2E20) : C(0x6E4A2C)), inner.X + inner.Width * 0.12, top - inner.Height * 0.035, inner.Width * 0.76, inner.Height * 0.09)
        g.FillEllipse(SolidBrush(Color.FromArgb(50, 255, 230, 200)), inner.X + inner.Width * 0.25, top - inner.Height * 0.03, inner.Width * 0.4, inner.Height * 0.025)
    }

    // 休息花（像素畫）：越久沒休息越垂、花瓣一片一片掉、顏色變淡；休息回來會慢慢恢復、滴出花蜜
    func DrawRestFlower(_ g: Graphics, _ c: Rectangle, _ t: Double) {
        var wilt: Double = 0; var petals = 0; var regrow: Double = 0; var nectar = false; var bubble: Double = 0
        w.FlowerLook(&wilt, &petals, &regrow, &nectar, &bubble)
        let inner = RectangleF(Double(c.X), Double(c.Y), Double(c.Width), Double(c.Height - plateH))
        let u = Math.Max(2, TU)
        let du = Double(u)
        let soilTop = inner.Bottom - inner.Height * 0.16 - inner.Height * 0.03
        let baseX = inner.X + inner.Width / 2.0
        let L = inner.Height * 0.52
        let sway: Double = wilt < 0.4 ? Math.Sin(t * 1.3) * 0.05 : 0
        let theta = Math.Pow(Math.Min(1.0, wilt), 1.3) * 2.5 + sway     // 0 直直的 → 約 143°（花整個垂下來）
        let stemC = Mix(Night ? C(0x3E7A3A) : C(0x4CA040), C(0x8A7A48), Math.Max(0.0, (wilt - 0.5) / 0.5))
        let leafC = Mix(Night ? C(0x4C8A44) : C(0x62BE4E), C(0x9A8A50), Math.Max(0.0, (wilt - 0.5) / 0.5))
        // 莖：沿著越來越彎的曲線一格一格點
        var x = baseX, y = soilTop
        let n = CInt(L / du)
        var pts = [PointF](repeating: PointF(0, 0), count: n + 1)
        pts[0] = PointF(x, y)
        for i in Loop(1, n + 1) {
            let s = Double(i) / Double(n)
            let q = Math.Max(0.0, Math.Min(1.0, (s - 0.42) / 0.58))
            let a = theta * q * q * (3 - 2 * q) * Math.Min(1.0, s / 0.42 * 0.25 + 0.75)   // 只有上半段彎：像真的花垂下來
            x += Math.Sin(a) * du; y -= Math.Cos(a) * du
            pts[i] = PointF(x, y)
        }
        // 垂下來的花不要超出格子：往旁邊的位移照比例收一點
        var maxDx: Double = 0
        for p in pts { maxDx = Math.Max(maxDx, p.X - baseX) }
        let allowed = inner.Right - 6.5 * du - baseX
        if maxDx > allowed && maxDx > 0 { for i in 0...n { pts[i] = PointF(baseX + (pts[i].X - baseX) * allowed / maxDx, pts[i].Y) } }
        let sb = SolidBrush(stemC)
        for p in pts { g.FillRectangle(sb, ShelfForm.Snap(p.X - du, u), ShelfForm.Snap(p.Y, u), Double(2 * u), du) }
        // 兩片葉子（枯了就垂下來）
        let droop = wilt > 0.6
        let leafR: [String] = droop ? ["LL...", ".LLL.", "..LLL"] : ["..LLL", ".LLL.", "LL..."]
        let lp1 = pts[Math.Max(1, n / 4)], lp2 = pts[Math.Max(1, n / 2)]
        ShelfForm.PixelArt(g, leafR, lp1.X + du, lp1.Y - (droop ? 0 : 2 * du), u, leafC, false)
        ShelfForm.PixelArt(g, leafR, lp2.X - 6 * du, lp2.Y - (droop ? 0 : 2 * du), u, leafC, true)
        // 掉在土上的花瓣
        let petalC = Mix(Night ? C(0xD898B8) : C(0xFFA6CC), C(0xA8805A), Math.Max(0.0, Math.Min(1.0, (wilt - 0.25) / 0.65)))
        let fallen = 6 - petals
        for i in Loop(0, fallen) {
            let fb = SolidBrush(Mix(C(0xC89070), C(0x8A6A4A), Double(i) / 6.0))
            let fxp = baseX + Double(i % 2 == 0 ? 1 : -1) * (3 + Double(i) * 2.2) * du
            g.FillRectangle(fb, ShelfForm.Snap(fxp, u), ShelfForm.Snap(soilTop + du * Double(1 + i % 2), u), Double(2 * u), du)
        }
        // 花：六片圓圓的花瓣（有外框）＋中心，跟著莖的方向轉
        let head = pts[n]
        let tilt = theta
        let R = 3.6 * du * regrow
        let petal: [String] = regrow < 0.75 ? [".P.", "PPP", ".P."] : [".PP.", "PPPP", "PPPP", ".PP."]
        let outline = Mix(petalC, C(0x5A2A3A), 0.55)
        for pass in 0..<2 {
            for i in 0..<6 {
                if i >= petals { continue }
                let a = tilt + Double(i) * Math.PI / 3 - Math.PI / 2
                let px = head.X + Math.Cos(a) * R - Double(petal[0].Length * u) / 2.0
                let py = head.Y + Math.Sin(a) * R - Double(petal.count * u) / 2.0
                if pass == 0 {
                    ShelfForm.PixelArt(g, petal, px - du, py, u, outline, false); ShelfForm.PixelArt(g, petal, px + du, py, u, outline, false)
                    ShelfForm.PixelArt(g, petal, px, py - du, u, outline, false); ShelfForm.PixelArt(g, petal, px, py + du, u, outline, false)
                }
                else { ShelfForm.PixelArt(g, petal, px, py, u, petalC, false); ShelfForm.PixelArt(g, ["P"], px + du, py + du, u, Mix(petalC, Color.White, 0.45), false) }
            }
        }
        let cen = Mix(Night ? C(0xE0B840) : C(0xFFD84A), C(0x9A7A3A), Math.Max(0.0, (wilt - 0.4) / 0.6))
        let disc: [String] = [".ccc.", "ccccc", "ccccc", "ccccc", ".ccc."]
        let rim = Mix(cen, C(0x7A4A10), 0.5)
        ShelfForm.PixelArt(g, disc, head.X - 2.5 * du - du, head.Y - 2.5 * du, u, rim, false)
        ShelfForm.PixelArt(g, disc, head.X - 2.5 * du + du, head.Y - 2.5 * du, u, rim, false)
        ShelfForm.PixelArt(g, disc, head.X - 2.5 * du, head.Y - 2.5 * du - du, u, rim, false)
        ShelfForm.PixelArt(g, disc, head.X - 2.5 * du, head.Y - 2.5 * du + du, u, rim, false)
        ShelfForm.PixelArt(g, disc, head.X - 2.5 * du, head.Y - 2.5 * du, u, cen, false)
        // 小臉：精神好＝笑、快枯了＝難過、枯了＝閉眼
        let face: [String] = wilt >= 0.99 || Night ? [".....", ".....", ".k.k.", ".....", "....."]
            : (wilt < 0.5 ? [".....", ".k.k.", ".....", ".k.k.", "..k.."] : [".....", ".k.k.", ".....", "..k..", ".k.k."])
        ShelfForm.PixelArt(g, face, head.X - 2.5 * du, head.Y - 2.5 * du, u, C(0x5A3A1A), false)
        // 花蜜：恢復後在花心閃閃、往下滴
        if nectar {
            let ph = (t * 1.2) % 1
            let nb = SolidBrush(Color.FromArgb(230, 255, 196, 40))
            let hl = SolidBrush(Color.FromArgb(240, 255, 255, 220))
            let dy = ph * (soilTop - head.Y - 4 * du)
            g.FillEllipse(nb, head.X - du, head.Y + 2 * du + dy, 2 * du, 2.6 * du)
            g.FillRectangle(hl, head.X - du / 2.0, head.Y + 2.4 * du + dy, Double(Math.Max(1, u / 2)), Double(Math.Max(1, u / 2)))
        }
    }

    static func Snap(_ v: Double, _ u: Int) -> Double { return Math.Floor(v / Double(u)) * Double(u) }
    static func Snap2(_ v: Double, _ u: Int) -> Double { return Math.Max(Double(u), Math.Round(v / Double(u)) * Double(u)) }
    static func PixelArt(_ g: Graphics, _ art: [String], _ x: Double, _ y: Double, _ u: Int, _ c: Color, _ flip: Bool) {
        let b = SolidBrush(c)
        for r in 0..<art.count {
            let row = Array(art[r])
            for i in 0..<row.count {
                if row[flip ? row.count - 1 - i : i] != "." { g.FillRectangle(b, Snap(x, u) + Double(i * u), Snap(y, u) + Double(r * u), Double(u), Double(u)) }
            }
        }
    }
}

// ================= World：休息花、吹哨子、皮克敏的串場 =================
//@@IN World
    var flowerStart: Double = Double.nan       // 這一段連續使用從哪時開始（真的休息過才重算；提醒過不重算）
    var flowerFrom: Double = 0, flowerRecover: Double = -1
    var petalsShown = 6
    var nectarReady = false
    var flowerBub: BubbleForm! = nil
    var flowerBubT: Double = 0
    var lastFlowerSent = -1
    var flowerSendT: Double = 0
    var lastLunchSeen = ""
    var flowerBubSize = Size(0, 0)
    let nectarDrops = List<World.Prop>()
    let nectarFor = Dict<ObjectIdentifier, Pet>()   // mac: Prop 不是 Hashable，用物件身分當 key（同 C# 的參考相等）
    var carryProp: World.Prop! = nil; var carriers: List<Pet>! = nil
    var carryX: Double = 0, carryTarget: Double = 0, carryLift: Double = 0; var carryWhat = ""
    var marchX: Double = 0, marchDir: Double = 0; var marchOn = false
//@@END

extension World {
    var PikLineup: Bool { return lineup == Pal.Pikmin }
    static var TestIdle: Double = 0      // 測試用（DESKPALS_ISOLATED）：假裝鍵盤滑鼠閒置了幾秒

    func FlowerRaw() -> Double {
        if flowerStart.isNaN { flowerStart = sessionStart }
        let end = sysIdle ? Now - W.IdleSeconds() : Now   // 你離開的時候花不會繼續枯
        return Math.Max(0.0, Math.Min(1.0, (end - flowerStart) / Math.Max(60.0, restMin * 60)))
    }
    func FlowerShown() -> Double {
        if flowerRecover >= 0 { var e = Math.Min(1.0, flowerRecover / 4.0); e = e * e * (3 - 2 * e); return flowerFrom * (1 - e) }
        return FlowerRaw()
    }
    static func PetalsFor(_ wv: Double) -> Int { return 6 - CInt(Math.Min(6.0, Math.Floor(Math.Max(0.0, wv - 0.42) / 0.095))) }

    func FlowerLook(_ wilt: inout Double, _ petals: inout Int, _ regrow: inout Double, _ nectar: inout Bool, _ bubble: inout Double) {
        wilt = FlowerShown()
        petals = petalsShown
        regrow = flowerRecover >= 0 && flowerFrom > 0.42 ? 0.5 + 0.5 * Math.Min(1.0, flowerRecover / 4.0) : 1
        nectar = nectarReady
        bubble = flowerBubT
    }

    func UsedMinutes() -> Int { if flowerStart.isNaN { flowerStart = sessionStart }; return CInt(Math.Floor((Now - flowerStart) / 60)) }

    // 點花：連續用了多久、還有多久會枯
    func FlowerClicked() {
        let used = UsedMinutes(), limit = CInt(Math.Round(restMin))
        var text: String
        if FlowerRaw() >= 1 { text = "花都枯了…起來喝口可樂、走一走 🥤\n（已經連續用 " + String(used) + " 分鐘了）" }
        else if used < 1 { text = "剛休息過，花開得好好的 🌸\n再 " + String(limit) + " 分鐘會開始累喔" }
        else { text = "已經連續用電腦 " + String(used) + " 分鐘了\n再 " + String(Math.Max(1, limit - used)) + " 分鐘花就要枯了 🌸" }
        ShowFlowerBubble(text, 5)
    }

    func ShowFlowerBubble(_ text: String, _ sec: Double) {
        if shelf == nil || Hidden { return }
        if flowerBub == nil { flowerBub = BubbleForm(Color.FromArgb(0x5C, 0xB0, 0x4A)) }
        flowerBubSize = flowerBub.Measure(text, FlowerRaw() >= 1, Night ? 3 : 0, nil)
        flowerBubT = sec
        PlaceFlowerBub()
        if !W.Shown(flowerBub) { flowerBub.Show() }
        W.KeepOnTop(flowerBub)
    }
    // 泡泡跟著花（櫃子收成蛋時改在蛋上面）
    func PlaceFlowerBub() {
        if flowerBub == nil || shelf == nil { return }
        let sz = flowerBubSize
        let c = shelf.Collapsed ? shelf.EggScreen() : shelf.CellScreen(0)
        let wa = WA(Double(c.X) + Double(c.Width) / 2.0, Double(c.Y))
        let bx = Math.Max(wa.Left, Math.Min(wa.Right - sz.Width, c.X + c.Width / 2 - sz.Width / 2))
        let by = Math.Max(wa.Top, shelf.Collapsed ? c.Y - sz.Height - 4 : c.Y + c.Height / 4 - sz.Height)
        let nb = Rectangle(bx, by, sz.Width, sz.Height)
        if flowerBub.Bounds != nb { flowerBub.Bounds = nb }
    }

    // 休息時間到了（取代一般的休息提醒）：花枯了，皮克敏跑來擔心、拉你的游標
    func PikWiltAlarm() {
        if flowerStart.isNaN { flowerStart = sessionStart }
        if FlowerRaw() < 1 { flowerStart = Math.Min(flowerStart, Now - restMin * 60) }   // 設定改短了：直接枯
        ShowFlowerBubble("花都枯了…起來喝口可樂、走一走 🥤", 9)
        sceneCd = Math.Max(sceneCd, 20)
        let outs = OutPets()
        if outs.Count == 0 { return }
        AbortScene()
        let a = shelf.Area
        let wa = WA(Double(a.Left) - 100 * k, Double(a.Bottom - 4))
        for i in 0..<outs.Count {
            let p = outs[i]
            let tx = Math.Max(Double(wa.Left + p.SW), Double(a.Left) - Double(60 + i * 70) * k)
            p.WakeIfSleep()
            if i == 0 && outs.Count > 1 {
                // 第一隻跑去拉你的游標
                p.Say("噗咿…！（拉拉你）休息一下嘛…", 4)
                let c = World.CursorPos()
                if p.Grounded() { p.PikGoto(Double(Math.Max(wa.Left + p.SW, Math.Min(wa.Right - p.SW, c.X))), "goto", 3) }
                let pp = p
                Later(3.2) { if pp.Out && pp.Grounded() { pp.PikDo("tug", 3); pp.Say("休息…噗咿…", 2) } }
                continue
            }
            let q = p; let qx = tx; let line = i % 2 == 0 ? "花…噗咿…" : "枯掉了…噗咿…"
            if q.OnFloor && Math.Abs(q.Foot - Double(wa.Bottom)) < 3 { q.PikGoto(qx, "goto", 4) }
            else { q.JumpTo(qx, Double(wa.Bottom)) }
            Later(2.8 + Double(i) * 0.3) { if q.Out && q.Grounded() { q.dir = 1; q.PikDo("worry", 4); q.Say(line, 2.4) } }
        }
    }

    // 真的休息回來了（閒置超過設定的分鐘數）：花慢慢恢復，然後滴花蜜
    func PikRested() {
        if flowerStart.isNaN { flowerStart = sessionStart }
        let from = FlowerShown()
        flowerStart = Now
        if from < 0.08 { return }
        flowerFrom = from; flowerRecover = 0
        nectarReady = false
    }

    func PikTick(_ dt: Double) {
        if !PikLineup {
            if flowerBub != nil && W.Shown(flowerBub) { flowerBub.Hide() }
            return
        }
        if flowerBubT > 0 { flowerBubT -= dt; if flowerBubT <= 0 || Hidden { flowerBubT = 0; if flowerBub != nil { flowerBub.Hide() } } else { PlaceFlowerBub() } }
        if flowerRecover >= 0 {
            let before = flowerRecover
            flowerRecover += dt
            if before < 4 && flowerRecover >= 4 { flowerRecover = -1; if flowerFrom > 0.15 { Nectar() } }
        }
        petalsShown = World.PetalsFor(FlowerShown())
        // 給 VS Code 狀態列：花的狀態（每 5% 一格）
        flowerSendT -= dt
        if flowerSendT <= 0 {
            flowerSendT = 2
            let pct = CInt(Math.Round(FlowerShown() * 20)) * 5
            if pct != lastFlowerSent { lastFlowerSent = pct; lock(clients) { for c in clients { World.Send(c, "flower " + String(pct) + "\n") } } }
        }
        StepCarry(dt)
        StepNectar()
        // 午餐：兩隻以上在外面時一起切大水果
        if LunchState != lastLunchSeen { if LunchState == "eat" && lastLunchSeen == "" && OutCount() >= 2 { Later(4) { [self] in if scene == nil { PikScene("fruit") } } }; lastLunchSeen = LunchState }
    }

    // ---------- 花蜜：休息回來，花滴出花蜜；外面的皮克敏跑過去喝 → 葉子→花苞→花 ----------
    static let NECTAR_ART: [String] = ["..y..", ".yYy.", "yYWYy", "yYYYy", ".yyy."]

    func Nectar() {
        nectarReady = true
        Later(6) { [self] in nectarReady = false }
        let outs = OutPets()
        if outs.Count == 0 || Hidden {
            // 都在櫃子裡：在櫃子裡喝
            for p in Pets { p.PikGrow() }
            ShowFlowerBubble("休息回來了！花蜜滴下來 🍯\n大家在櫃子裡喝到了，噗咿！", 4.5)
            return
        }
        ShowFlowerBubble("休息回來了！花又開了 🌸\n花蜜滴下來囉，噗咿！", 4)
        AbortScene()
        sceneCd = Math.Max(sceneCd, 25)   // 喝完花蜜之前不要開始別的串場
        let a = shelf.Area, c0 = shelf.CellScreen(0)
        let wa = WA(Double(a.Left) - 60 * k, Double(a.Bottom - 4))
        let owner = Pal.Get("pkyellow")
        for i in 0..<outs.Count {
            let p = outs[i]
            let dx = Math.Max(Double(wa.Left + p.SW), Double(a.Left) - Double(40 + i * 75) * k)
            let from = PointF(Double(c0.X) + Double(c0.Width) / 2.0, Double(c0.Y) + Double(c0.Height) / 3.0)
            let d: World.Prop! = Toss(World.NECTAR_ART, owner, from, PointF(dx, Double(wa.Bottom - 3 * S)), 0.9 + Double(i) * 0.15, 120 * k, false, 40, nil)
            if d == nil { p.PikGrow(); continue }
            nectarDrops.Add(d); nectarFor[ObjectIdentifier(d)] = p
            let pp = p; let tx = dx
            Later(0.6 + Double(i) * 0.2) {
                if !pp.Out { return }
                pp.WakeIfSleep()
                pp.Say("噗咿！花蜜！", 1.2)
                if pp.OnFloor && Math.Abs(pp.Foot - Double(wa.Bottom)) < 3 { pp.PikGoto(tx, "goto", 6) }
                else { pp.JumpTo(tx, Double(wa.Bottom)) }
            }
        }
    }

    func StepNectar() {
        var i = nectarDrops.Count - 1
        while i >= 0 {
            defer { i -= 1 }
            let d = nectarDrops[i]
            var p: Pet! = nil
            if !nectarFor.TryGetValue(ObjectIdentifier(d), &p) || !props.Contains(d) { nectarDrops.RemoveAt(i); nectarFor.Remove(ObjectIdentifier(d)); continue }
            if d.Legs.Count > 0 || !p.Out { continue }
            let near = Math.Abs(p.Foot - (d.Y + Double(3 * S))) < 30 * k
            if Math.Abs(p.Cx - d.X) < Double(p.SW) * 0.6 && near && p.Grounded() && (p.state != "pik" || p.PikGoing) {
                RemoveProp(d); nectarDrops.RemoveAt(i); nectarFor.Remove(ObjectIdentifier(d))
                p.PikDo("drink", 1.8)
            }
            else if p.Grounded() && p.state != "pik" && p.state != "air" && Math.Abs(p.Cx - d.X) >= Double(p.SW) * 0.6 && near { p.PikGoto(d.X, "goto", 5) }
        }
    }

    // ---------- 吹哨子：外面的皮克敏全部跑來跟著游標 ----------
    func Whistle() {
        let outs = OutPets()
        if outs.Count == 0 { Lead().Say("（大家都在土裡）噗咿？", 1.6); return }
        AbortScene()
        let l: Pet = Lead()
        sceneCd = Math.Max(sceneCd, 12)
        l.Say("嗶——！（吹哨子）", 1.4)
        for i in 0..<outs.Count {
            let p = outs[i]; let idx = i
            p.WakeIfSleep()
            Later(0.3 + Double(i) * 0.45) { if p.Out && p.Grounded() { p.PikFollow(idx, 9); if p !== l { p.Say("噗咿！", 0.6) } } }
        }
    }

    // ---------- 一起搬東西（顆粒、可樂、球）：數字＝要幾隻 ----------
    static let DIGITS: [[String]] = [
        ["WWW", "W.W", "W.W", "W.W", "WWW"], [".W.", "WW.", ".W.", ".W.", "WWW"], ["WWW", "..W", "WWW", "W..", "WWW"],
        ["WWW", "..W", ".WW", "..W", "WWW"], ["W.W", "W.W", "WWW", "..W", "..W"], ["WWW", "W..", "WWW", "..W", "WWW"] ]
    static func PelletArt(_ n: Int) -> [String] {
        let o: [String] = ["...ooooo...", ".oorrrrroo.", ".orhrrrrrRo", "orhrrrrrrRo", "orrrrrrrrRo", "orrrrrrrrRo", "orrrrrrrrRo", "orrrrrrrRRo", ".orrrrrRRo.", ".ooRRRRRoo.", "...ooooo..."]
        var g: [[Character]] = o.map { Array($0) }
        let d = DIGITS[Math.Max(0, Math.Min(5, n))]
        for r in 0..<5 { let dr = Array(d[r]); for c in 0..<3 { if dr[c] == "W" { g[3 + r][4 + c] = "W" } } }
        return g.map { String($0) }
    }
    static let COLA_ART: [String] = [".7777.", "777777", "SSSSSS", "SWWSSS", "SSWWWS", "SSSSWS", "SSSSSS", "777777", ".7777."]

    func StartCarry(_ who: List<Pet>, _ what: String, _ fromX: Double, _ toX: Double) {
        carriers = who; carryWhat = what; carryX = fromX; carryTarget = toX; carryLift = 0
        let owner: Pal = Pal.Get(what == "pellet" ? "pkred" : "pkblue")
        let art = what == "pellet" ? World.PelletArt(who.Count) : World.COLA_ART
        let wa = WA(fromX, who[0].Foot - 4)
        carryProp = NewProp(art, nil, owner, S, fromX, Double(wa.Bottom) - Double(art.count * S) / 2.0, false)
        carryProp.Hold = 999
    }

    func StepCarry(_ dt: Double) {
        if carryProp == nil { return }
        if !props.Contains(carryProp) || carriers == nil { carryProp = nil; return }
        let live = List<Pet>()
        for p in carriers! { if p.Out && p.PikCarrying { live.Add(p) } }
        var headY = Double.greatestFiniteMagnitude
        for p in carriers! { if p.Out { headY = Math.Min(headY, p.Foot - Double(p.SH) + Double((p.P.HeadTop - 1) * p.S)) } }
        if live.Count > 0 {
            carryLift = Math.Min(1.0, carryLift + dt * 1.2)
            var ready = true
            for i in 0..<live.Count {
                let slot = carryX + (Double(i) - Double(live.Count - 1) / 2.0) * Double(live[i].SW) * 1.1
                if Math.Abs(live[i].Cx - slot) > Double(live[i].SW) * 0.4 { ready = false }
            }
            if !ready { for i in 0..<live.Count { live[i].PikGoto(carryX + (Double(i) - Double(live.Count - 1) / 2.0) * Double(live[i].SW) * 1.1, "carry", 30) } }
            if carryLift >= 1 && ready {
                let sp = 55 * k * dt * Math.Min(1.0, Double(live.Count) / Double(carriers.Count))
                carryX += Double(Math.Sign(carryTarget - carryX)) * Math.Min(Math.Abs(carryTarget - carryX), sp)
                for i in 0..<live.Count { live[i].PikGoto(carryX + (Double(i) - Double(live.Count - 1) / 2.0) * Double(live[i].SW) * 1.1, "carry", 30) }
            }
        }
        let wa = WA(carryX, carriers[0].Foot - 4)
        let ground = Double(wa.Bottom) - Double(carryProp.F.Height) / 2.0
        let above = headY == Double.greatestFiniteMagnitude ? ground : headY - Double(carryProp.F.Height) / 2.0 + Double(S)
        carryProp.X = carryX; carryProp.Y = ground + (above - ground) * carryLift
        PlaceProp(carryProp)
    }

    func EndCarry() {
        if carryProp != nil {
            let cp: World.Prop = carryProp; carryProp = nil
            let c0 = shelf.CellScreen(0)
            cp.Hold = 0
            cp.Go(Double(c0.X) + Double(c0.Width) / 2.0, Double(c0.Y) + Double(c0.Height) / 2.0, 0.7, 60 * k, { [self] in if shelf.Collapsed { shelf.Gulp() } })
        }
        if carriers != nil { for p in carriers! { p.PikCarrying = false } }
        carriers = nil
    }

    // ---------- 右鍵選單 ----------
    func PikMenuItems(_ p: Pet) -> [[String]]? {
        let sig = p.P.Id == "pkred" ? "握拳冒火 🔥" : (p.P.Id == "pkyellow" ? "跳高高 ⚡" : "游泳 💧")
        return [["抱抱 ♥", "hug"], ["打招呼 噗咿！", "hi"], ["敲敲螢幕", "knock"], ["吹哨子（大家跟著游標）", "whistle"],
                [sig, "sig"], ["跳到別的視窗上", "jump"], ["睡覺", "sleep"], ["丟球給他（大家搬回來）⚾", "ball"]]
    }

    func AddPikMenu(_ m: ContextMenuStrip) {
        let grp = ToolStripMenuItem("皮克敏一起…")
        let gs: [[String]] = [["一起搬顆粒", "carry"], ["排隊遊行", "march"], ["花蜜派對 🍯", "party"], ["一起切大草莓", "fruit"],
                              ["大合照 📷", "photo"], ["點名", "rollcall"], ["回土裡睡覺", "byebye"]]
        for gi in gs { let key = gi[1]; grp.DropDownItems.Add(gi[0], nil, { [self] in if key == "photo" { GroupPhoto() } else { PikScene(key) } }) }
        m.Items.Add(grp)
        m.Items.Add("休息花：還能撐多久？🌸", nil, { [self] in FlowerClicked() })
    }

    // ---------- 串場 ----------
    func PikGroup(_ n: Int) {
        let r = rnd.NextDouble()
        if r < 0.3 { PikScene("carry") } else if r < 0.55 { PikScene("march") } else if r < 0.75 { PikScene("party") } else { GroupPhoto() }
    }

    func PikOrder(_ l: List<Pet>) -> List<Pet> {
        let o = List<Pet>()
        for id in Pal.PikminIds { for p in l { if p.P.Id == id { o.Add(p) } } }
        return o
    }

    // 大家排到櫃子左邊的地板上（不管原本在哪個視窗上）
    // 大家排到地板上（在帶頭那隻附近；nearShelf＝排到櫃子左邊）；離太遠就用跳的
    @discardableResult
    func PikGather(_ outs: List<Pet>, _ spacing: Double, _ startAt: Double) -> [Double] { return PikGather(outs, spacing, startAt, false) }
    @discardableResult
    func PikGather(_ outs: List<Pet>, _ spacing: Double, _ startAt: Double, _ nearShelf: Bool) -> [Double] {
        let a = shelf.Area
        let l = outs[0]
        let wa = WA(nearShelf ? Double(a.Left) - 200 * k : l.Cx, Double(a.Bottom - 4))
        let foot = Double(wa.Bottom), width = Double(outs.Count - 1) * Double(outs[0].SW) * spacing
        var center = nearShelf ? Double(a.Left) - 80 * k - width / 2 - Double(outs[0].SW) : l.Cx
        let maxRight = Double(Math.Min(wa.Right, a.Left)) - Double(outs[0].SW) * 0.8
        center = Math.Max(Double(wa.Left + outs[0].SW) + width / 2, Math.Min(maxRight - width / 2, center))
        let first = center - width / 2
        for i in 0..<outs.Count {
            let p = outs[i]
            let tx = first + Double(i) * Double(p.SW) * spacing
            At(startAt + Double(i) * 0.3) { [self] in
                if p.OnFloor && Math.Abs(p.Foot - foot) < 3 && Math.Abs(tx - p.Cx) < 320 * k { p.WalkTo(tx, 10) }
                else { p.JumpTo(tx, foot) }
            }
        }
        return [first, first + width, foot]
    }

    func PikScene(_ key: String) {
        let outs = PikOrder(OutPets())
        if outs.Count < 2 && key != "rollcall" && key != "byebye" { AllOut(); Later(2.6) { [self] in PikScene(key) }; return }
        switch key {
        case "carry": SceneCarry(outs, "pellet")
        case "cola": SceneCarry(outs, "cola")
        case "march": SceneMarch(outs)
        case "party": SceneNectarParty(outs)
        case "fruit": SceneFruit(outs)
        case "rollcall": PikRollCall(List<String>(Pal.PikminIds))
        case "byebye": PikNight(false)
        default: break
        }
    }

    // mac: C# 傳 null 進去會在 Begin 丟例外被 Later 吞掉；這裡少一隻就不演（跟 RunScene 一樣）
    func PikPairScene(_ key: String) {
        func g(_ id: String) -> Pet? { return Get(id) }
        switch key {
        case "pkred-pkyellow": if let x = g("pkred"), let y = g("pkyellow") { SceneToss(x, y) }
        case "pkblue-pkred": if let x = g("pkblue"), let y = g("pkred") { SceneRescue(x, y) }
        case "pkblue-pkyellow": if let x = g("pkyellow"), let y = g("pkblue") { SceneCarry(List<Pet>([x, y]), "cola") }
        default: break
        }
    }

    // 紅丟黃：紅皮克敏把黃皮克敏丟到高高的地方
    func SceneToss(_ red: Pet, _ yel: Pet) {
        Begin(red, yel)
        At(0) { [self] in Face(red, yel); red.ScenePose("idle", 30); yel.ScenePose("idle", 30); yel.Say("小紅！丟我！要飛高高！", 2); yel.PikSpark(1.5) }
        At(2.1) { red.Say("嘿！準備好了！", 1.4); red.WalkTo(yel.Cx + Double(red.Cx < yel.Cx ? -1 : 1) * Double(yel.SW) * 0.7, 1) }
        At(3.4) { red.FaceTo(yel); red.PikDo("throwup", 0.8); red.Say("嘿咻——！", 1) }
        At(3.7) { [self] in
            var best: Plat? = nil
            for p in Plats {
                if Double(p.Top) < yel.Foot - 120 * k && Double(p.Top) > yel.Foot - 700 * k && Math.Abs(Double(p.Left + p.Right) / 2.0 - yel.Cx) < 700 * k && p.Right - p.Left > yel.SW * 2 { best = p; break }
            }
            yel.InScene = false
            if let b = best { yel.JumpTo(Math.Max(Double(b.Left + yel.SW), Math.Min(Double(b.Right - yel.SW), yel.Cx)), Double(b.Top)) }
            else { yel.Jump(Double(red.dir) * 90 * k, -900 * k) }
            yel.InScene = true
            yel.PikSpark(2.2); yel.Say("噗咿～～～！", 1.6)
        }
        At(6.4) { yel.Say("好高！再一次！噗咿！", 2); red.ScenePose("hop", 0) }
        At(8.6) { red.Say("嘿嘿，小紅力氣最大！", 2); red.PikFlame(1.2) }
        At(10.8) { }
    }

    // 藍救紅：紅掉進水窪，藍游過去拉他上來
    func SceneRescue(_ blue: Pet, _ red: Pet) {
        Begin(blue, red)
        At(0) { [self] in Face(blue, red); blue.ScenePose("idle", 30); red.ScenePose("idle", 30); red.Say("嘿！我也要玩水！", 1.8) }
        At(1.9) { red.ScenePose("hop", 0) }
        At(2.6) { red.PikDo("drown", 30); red.Say("噗咿！噗咿！（不會游泳）", 2.4) }
        At(4.6) { blue.Say("別怕，我來！", 1.4); blue.WalkTo(red.Cx + Double(blue.Cx < red.Cx ? -1 : 1) * Double(red.SW) * 0.9, 1) }
        At(6.2) { blue.FaceTo(red); blue.PikDo("swim", 30); blue.Say("咕嚕咕嚕～", 1.4) }
        At(7.8) { blue.PikDo("lift", 30); red.ScenePose("idle", 30); red.PikPop("噗哈！") }
        At(9.4) { [self] in blue.ScenePose("idle", 30); Face(blue, red); red.Say("謝謝小藍…（滴水）", 2); red.Mark(4) }
        At(11.6) { blue.Say("小紅怕水，小藍怕火，剛剛好。", 2.4) }
        At(14.2) { blue.ScenePose("hug", 2.2); red.ScenePose("hug", 2.2); red.Say("噗咿！", 1.4) }
        At(16.6) { }
    }

    // 大家一起搬顆粒（或可樂）回櫃子：嘿咻嘿咻
    func SceneCarry(_ who0: List<Pet>, _ what: String) {
        let who = PikOrder(who0)
        for p in who { if !p.Out { return } }
        if who.Count == 0 { return }   // mac: C# 在 who[0] 丟例外；這裡直接不演
        let l = who[0]
        Begin(who.ToArray())
        let lr = PikGather(who, 1.2, 0.3)
        let cx = (lr[0] + lr[1]) / 2
        At(0) { l.Say(what == "cola" ? "噗咿！可樂罐！一起搬！" : "噗咿！顆粒！數字是 " + String(who.Count) + "，要 " + String(who.Count) + " 隻！", 2.4) }
        At(3.8) { [self] in StartCarry(who, what, cx, Double(shelf.Area.Left) - 30 * k); for p in who { p.FaceTo(l); p.ScenePose("idle", 30) } }
        At(4.6) { for p in who { p.PikCarrying = true; p.PikDo("lift", 30) }; l.Say("嘿咻！", 1.2) }
        for s3 in 0..<10 { let idx = s3; At(5.6 + Double(s3) * 2.6) { [self] in if carryProp != nil { who[idx % who.Count].Say("嘿咻嘿咻！", 1.4) } } }
        for s2 in 0..<120 {
            At(6.0 + Double(s2) * 0.25) { [self] in
                if carryProp == nil || Math.Abs(carryX - carryTarget) > 2 { return }
                EndCarry(); for p in who { p.ScenePose("idle", 30); p.Burst(4) }; l.Say("搬回去了！噗咿！", 2)
                let tEnd = sceneT
                At(tEnd + 2.0) { for p in who { p.ScenePose("hop", 0) } }
                At(tEnd + 3.2) { [self] in if scene != nil { scene.Clear() } }
            }
        }
        At(36) { [self] in EndCarry() }
    }

    // 吹哨子排隊遊行
    func SceneMarch(_ outs: List<Pet>) {
        let l = outs[0]
        Begin(outs.ToArray())
        let lr = PikGather(outs, 1.3, 0.3)
        At(0) { l.Say("嗶——！排隊！", 1.8) }
        At(4.2) { [self] in
            marchX = lr[1] + 20 * k; marchDir = -1; marchOn = true
            for p in outs { p.Say("噗咿！", 0.8) }
        }
        for s in 0..<40 {
            let at = 4.4 + Double(s) * 0.2
            At(at) { [self] in
                if !marchOn { return }
                let wa = WA(marchX, lr[2] - 4)
                marchX += marchDir * 120 * k * 0.2
                if marchX < Double(wa.Left) + 60 * k { marchDir = 1 }
                if marchX > Double(shelf.Area.Left) - 40 * k { marchDir = -1 }
                for i in 0..<outs.Count { outs[i].PikGoto(marchX - marchDir * Double(i + 1) * Double(outs[i].SW) * 1.3, "march", 30) }
            }
        }
        At(6.4) { l.Say("一、二！一、二！", 1.6) }
        At(9.4) { outs[outs.Count - 1].Say("噗咿！噗咿！", 1.4) }
        At(12.6) { [self] in marchOn = false; for p in outs { p.ScenePose("idle", 30); p.ScenePose("hop", 0) }; l.Say("解散！噗咿！", 1.6) }
        At(14) { }
    }

    // 花蜜派對：在花前面集合，花滴下花蜜
    func SceneNectarParty(_ outs: List<Pet>) {
        Begin(outs.ToArray())
        PikGather(outs, 1.5, 0.3, true)
        At(0) { outs[0].Say("噗咿！去花那邊！", 1.6) }
        At(4.4) { [self] in for p in outs { p.dir = 1; p.ScenePose("idle", 30) }; ShowFlowerBubble("花蜜派對！噗咿！🍯", 3) }
        At(5.2) { [self] in AbortScene(); Nectar() }
    }

    // 午餐：大家一起切一顆大水果
    static let BIGFRUIT: [String] = ["....GgG....", "...GGgGG...", ".SSSSSSSSS.", "SSYSSSSYSSS", "SSSSSYSSSSS", "SYSSSSSSYSS", "SSSSYSSSSSS", ".SSSSSSYSS.", "..SSSSSSS..", "....SSS...."]
    func SceneFruit(_ outs: List<Pet>) {
        let l = outs[0]
        Begin(outs.ToArray())
        let lr = PikGather(outs, 1.6, 0.3)
        let cx = (lr[0] + lr[1]) / 2
        var fruit: World.Prop? = nil
        At(0) { l.Say("噗咿！午餐！大草莓！", 2) }
        At(3.6) { [self] in fruit = Toss(World.BIGFRUIT, Pal.Get("pkred"), PointF(cx, lr[2] - 300 * k), PointF(cx, lr[2] - Double(5 * S)), 0.8, 0, false, 30, { l.Say("咚！", 0.8) }) }
        At(4.8) { for p in outs { p.FaceTo(l); p.dir = p.Cx < cx ? 1 : -1; p.PikDo("punch", 1.2) }; l.Say("嘿！嘿！切開！", 1.4) }
        At(6.4) { [self] in RemoveProp(fruit); for p in outs { p.PikHold = "straw"; p.ScenePose("idle", 30); p.Burst(4) }; l.Say("一人一塊！噗咿！", 1.8) }
        At(8.6) { l.Say("好甜！咕嘟咕嘟～", 1.6); for p in outs { p.Mark(0) } }
        At(11) { for p in outs { p.PikHold = ""; p.ScenePose("hop", 0) } }
        At(12) { }
    }

    // 早上點名：一隻一隻從土裡拔出來
    func PikRollCall(_ ids: List<String>) {
        let order = List<Pet>()
        for id in Pal.PikminIds { if ids.Contains(id) && Get(id) != nil { order.Add(Get(id)) } }
        var d = 0.4
        for p in order {
            let pp = p
            Later(d) { [self] in if !pp.Out { BringOut(pp, false) } }
            Later(d + 1.9) { pp.Say(pp.P.Name.Substring(0, 1) + "！噗咿！", 1.6) }
            d += 1.5
        }
        Later(d + 1.6) { [self] in if order.Count > 0 { Lead().Say("全員到齊！噗咿！", 2.4) }; for p in order { if p.Out && p.Grounded() { p.ScenePose("wave", 1.6) } } }
    }

    // 下班：一隻一隻鑽回櫃子的土裡
    func PikNight(_ nag: Bool) {
        let outs = PikOrder(OutPets())
        if outs.Count == 0 { Lead().Say("噗咿…晚安…", 2.4); return }
        Begin(outs.ToArray())
        for p in outs { if p.Grounded() { p.ScenePose("idle", 60) } }
        var d = 0.2
        if nag { for p in outs { let pp = p; At(d) { pp.Say(pp.L("nag"), 2.4) }; d += 2.6 } }
        for p in outs {
            let pp = p
            At(d) { pp.Say("噗咿…晚安…", 1.6); pp.PikDo("dig", 30) }
            At(d + 1.0) { pp.InScene = false; if pp.Out { pp.StowToShelf(false) } }
            d += 1.8
        }
        At(d + 0.5) { let last = outs[outs.Count - 1]; last.Say("（土裡）噗咿…zZ", 2.6) }
        At(d + 3.2) { }
    }

    // ---------- 皮克敏一櫃的開場白 ----------
    static func PikFlavor(_ id: String, _ kind: String) -> String? {
        if id != "pkred" && id != "pkyellow" && id != "pkblue" { return nil }
        let keys: [String] = ["ci-run", "ci-ok", "ci-fail", "cmd-ok", "cmd-fail", "meeting", "meeting-now", "jira", "worklog",
                              "remind", "pc-cpu", "pc-ram", "pc-disk", "net-down", "net-up", "vpn", "download"]
        let t: [String] = ["噗咿！CI 出發：", "CI 過了！噗咿！", "噗咿！CI 倒了：", "跑完了！嘿咻：", "噗咿？失敗了：", "等等要開會：", "開會了！噗咿！快去：", "有新的 Jira！噗咿：", "日誌好了，噗咿：",
                           "⏰ 噗咿！提醒你：", "電腦好燙！噗咿：", "記憶體快滿了：", "硬碟快滿了：", "網路斷了！噗咿…", "網路回來了！噗咿！", "連不到公司網路（VPN 斷了？）", "下載好了！大家搬回來了："]
        let i = keys.IndexOf(kind)
        return i < 0 ? nil : t[i]
    }
    static func PikTicket(_ id: String, _ stage: Int, _ n: String, _ h: String) -> String? {
        if id != "pkred" && id != "pkyellow" && id != "pkblue" { return nil }
        let t: [String] = ["🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款！噗咿！", "🎫 " + n + " 再 30 分鐘！噗咿！", "🎫 " + n + " 剩 10 分鐘！嘿咻！", "🎫 準備！噗咿…", "🎫 開搶！！衝啊！噗咿！"]
        return t[stage]
    }

    // 測試用（只在離屏模式）：act flower <快轉分鐘>｜rest｜click
    func PikFlowerAct(_ arg: String) {
        if arg == "click" { FlowerClicked(); return }
        if !App.Offscreen { return }
        var m: Double = 0
        if arg == "rest" { PikRested(); return }
        if arg.StartsWith("idle") && double.TryParse(arg.Substring(4), NumberStyles.Float, CultureInfo.InvariantCulture, &m) { World.TestIdle = m; return }
        if arg == "wilt" { PikWiltAlarm(); return }
        if arg.StartsWith("stage") && arg.Length == 6 { let s = Int(Array(arg)[5].asciiValue ?? 48) - 48; for p in Pets { p.PikSetStage(s) }; return }
        if double.TryParse(arg, NumberStyles.Float, CultureInfo.InvariantCulture, &m) { flowerRecover = -1; flowerStart = Now - m * 60 }
    }
}
