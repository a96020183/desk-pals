// ================= 角色資料（Pal）=================
// 每個角色：id、名字、調色盤（白天／夜晚）、像素圖零件、台詞、移動風格、夜晚風格、球種、配件錨點。
// 像素圖是 12 格寬（也可以更寬，會置中）× 16 格高的字元格；'.' 是透明。
// 共用字元：k 外框、p 愛心粉、y 星星黃、w 白；配件用 S W Y P B（每個角色都會有）。
// C# 582–1571
import Foundation

final class Pal
{
    var Id: String! = nil, Name: String! = nil, Move: String! = nil, BallKind: String! = nil, NightStyle: String! = nil
    var NightBubble: Int = 0
    var Accent: Color = Color.Empty, Panel: Color = Color.Empty, Halo: Color = Color.Empty, HaloNight: Color = Color.Empty
    let Day = Dict<Character, Color>(), Night = Dict<Character, Color>()
    let Art = Dict<String, [String]>()
    let Lines = Dict<String, [String]>()
    var FaceRow: Int = 4                       // SLEEPY／HAPPY／DIZZY 這些臉蓋掉 FaceRow～FaceRow+2
    var EyeRow: Int = 5, EyeL: Int = 3, EyeR: Int = 8    // 眼珠跟著滑鼠（EyeRow < 0：不跟）
    var HatRow: Int = 0, HatCol: Int = 0, ScarfRow: Int = 8, GlassRow: Int = 4, BadgeRow: Int = 10, BadgeCol: Int = 5, BadgeFrom: Int = 107   // 107 = 'k'
    var SideRow: Int = 9                       // 紅包、蛋糕的高度
    var Speed: Double = 40                     // 走路速度（×k）
    var KeepAntenna: Bool = false              // 帽子戴上後把天線重畫在帽子上面（小波）
    var TopRows: Int = 0
    var NoGlasses: Bool = false                // 眼睛太開，眼鏡戴不上（史迪仔）                           // 頭頂超出 16 格框的列數（小波的天線）
    // 天線寶寶一櫃（丁丁、迪西、拉拉）用的；經典一櫃的角色都是預設值
    var Tubby: Bool = false                    // 丁丁／迪西／拉拉（小波另外寫）
    var TummyRow: Double = 10.5                // 肚子電視的中心在第幾列
    var AntRows: Int = -1                      // 戴帽子時露在帽子上面的天線列數（-1＝TopRows-1，小波）
    var AntThrough: Bool = false               // 天線從帽子中間穿出來（不墊高；丁丁太高了）
    var HeadTop: Int = -1                      // 頭頂外框那一列在 16 格框的第幾列
    var BodyTop: Int = 8                       // 身體第一列在 16 格框的第幾列
    //@@BODY Pal

    static func C(_ rgb: Int) -> Color { return Color.FromArgb((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255) }
    func Col(_ c: Character, _ day: Int, _ night: Int) { Day[c] = Pal.C(day); Night[c] = Pal.C(night) }
    func Say(_ key: String, _ lines: String...) { Lines[key] = lines }

    static var all: List<Pal>! = nil
    static var All: List<Pal> {
        if all == nil {
            let l = List<Pal>()
            for x in [Spidey(), Po(), Stitch(), Hangyodon(), Tinky(), Dipsy(), LaaLaa()] { l.Add(x) }
            l.AddRange(PikminPals())
            all = l
        }
        return all
    }
    static func Get(_ id: String!) -> Pal!
    {
        for p in All { if p.Id == id { return p } }
        return nil
    }

    // ---- 兩櫃：經典（Spidey、小波、史迪仔、人魚漢頓）／天線寶寶（丁丁、迪西、拉拉、小波；大格是小波）----
    static let Classic = "classic", Teletubbies = "teletubbies"
    static func NormLineup(_ s: String!) -> String { let t = s == nil ? "" : s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(); return t == Teletubbies || t == Pikmin ? t : Classic }
    static func LineupIds(_ lineup: String!) -> [String]
    {
        if NormLineup(lineup) == Pikmin { return PikminIds }   // 皮克敏一櫃：大格是休息花（50_pikmin.swift）
        return NormLineup(lineup) == Teletubbies ? ["tinky", "dipsy", "laalaa", "po"] : ["spidey", "po", "stitch", "hangyodon"]
    }
    static func Lineup(_ lineup: String!) -> List<Pal>
    {
        let l = List<Pal>()
        for id in LineupIds(lineup) { l.Add(Get(id)) }
        return l
    }
    // 這一櫃預設放在大格的（經典一櫃照用最久的那隻）
    static func LineupFav(_ lineup: String!) -> String! { return NormLineup(lineup) == Teletubbies ? "po" : nil }
    // 設定視窗、小屋「換一櫃」列出來的櫃子（之後新增一櫃：這裡加一個 id、LineupIds／LineupName 加一行）
    static let Lineups: [String] = [Classic, Teletubbies, Pikmin]
    static func LineupName(_ lineup: String) -> String { let n = NormLineup(lineup); return n == Teletubbies ? "天線寶寶一櫃" : (n == Pikmin ? "皮克敏一櫃" : "經典一櫃") }

    func Shared()
    {
        for d in [Day, Night]
        {
            d["S"] = Pal.C(0xE23B3B); d["W"] = Color.White; d["Y"] = Pal.C(0xF5C842); d["P"] = Pal.C(0xFF8FB0); d["B"] = Pal.C(0xB8D6FF)
            if !d.ContainsKey("p") { d["p"] = Pal.C(0xFF6F9C) }
            if !d.ContainsKey("y") { d["y"] = Pal.C(0xFFD84A) }
            if !d.ContainsKey("w") { d["w"] = Color.White }
            d["1"] = Pal.C(0xD9A55B); d["2"] = Pal.C(0xA8743A)   // 木頭（球棒、搖椅、烏克麗麗）
            d["3"] = Pal.C(0xF4F1EA)                          // 棒球白
            d["4"] = Pal.C(0xE03A3A)                          // 棒球縫線
            d["5"] = Pal.C(0xA0703F); d["6"] = Pal.C(0x6E4524)   // 手套皮革
            d["7"] = Pal.C(0x8E97B0); d["8"] = Pal.C(0xFFFFFF)   // 絲、閃光
        }
        if Lines.ContainsKey("talk") && !Lines.ContainsKey("talk_d") { Lines["talk_d"] = Lines["talk"] }
    }

    // 把幾段零件疊成一張圖（每段寬度不同時置中補齊）
    static func Stack(_ parts: [String]...) -> [String]
    {
        var rows: [String] = []
        var w = 0
        for p in parts { for r in p { w = max(w, r.utf16.count) } }
        for p in parts {
            for r in p
            {
                let n = r.utf16.count
                let l = (w - n) / 2
                rows.append(String(repeating: ".", count: l) + r + String(repeating: ".", count: w - n - l))
            }
        }
        return rows
    }

    // ---------------- Spidey（原本那隻，外觀台詞完全照舊）----------------
    static func Spidey() -> Pal
    {
        let p = Pal()
        p.Id = "spidey"; p.Name = "Spidey"; p.Move = "web"; p.BallKind = "tennis"; p.NightStyle = "dark"; p.NightBubble = 1
        p.Accent = C(0x2A2F45); p.Panel = C(0xF3D9D6); p.Halo = Color.White; p.HaloNight = C(0xC8C0EC)
        p.Col("k", 0x2A2F45, 0x0B0B10); p.Col("r", 0xD84A4A, 0x2C2E3B); p.Col("R", 0xA83A3A, 0x1B1C26); p.Col("b", 0x3D5FAE, 0x3E4055)
        p.Col("w", 0xFFFFFF, 0xF6F6FA); p.Col("p", 0xFF6F9C, 0xB04A6E); p.Col("y", 0xFFD84A, 0xB9A7FF)
        p.Art["HEAD"] = ["...kkkkkk...", "..krrrrrrk..", ".krRrrrrRrk.", ".krrrRRrrrk.", ".kwwkrrkwwk.", ".kwwwkkwwwk.", ".krwwrrwwrk.", "..krrRRrrk.."]
        p.Art["SLEEPY"] = [".krrrrrrrrk.", ".kkkkrrkkkk.", ".krrrrrrrrk."]
        p.Art["HAPPY"] = [".krkrrrrkrk.", ".kkrkrrkrkk.", ".kprrrrrrpk."]
        p.Art["DIZZY"] = [".kkwkrrkwkk.", ".kwkwkkwkwk.", ".kkwkrrkwkk."]
        p.Art["BODY"] = ["...kkkkkk...", "..kbrrrrbk..", ".kbbrkkrbbk.", ".krbrrrrbrk.", "..kbbbbbbk.."]
        p.Art["ARMS_UP"] = ["kr.kkkkkk.rk", "kbkbrrrrbkbk", ".kbbrkkrbbk.", "..kbrrrrbk..", "..kbbbbbbk.."]
        p.Art["ARMS_HUG"] = ["...kkkkkk...", ".kkbrrrrbkk.", "krrrkkkkrrrk", ".kkbrrrrbkk.", "..kbbbbbbk.."]
        p.Art["LEGS_A"] = ["..kbbkkbbk..", "..krrkkrrk..", "..kkk..kkk.."]
        p.Art["LEGS_B"] = ["..kbbkkbbk..", ".krrk..krrk.", ".kkk....kkk."]
        p.FaceRow = 4; p.EyeRow = 5; p.EyeL = 3; p.EyeR = 8
        p.HatRow = 0; p.ScarfRow = 8; p.GlassRow = 4; p.BadgeRow = 10; p.BadgeCol = 5; p.SideRow = 9
        p.Speed = 40
        p.Say("talk", "嗨！今天也一起寫 code 吧", "能力越強，bug 越少！", "蜘蛛感應：你存檔了嗎？", "要不要喝口可樂？", "整個螢幕都是我的地盤！", "這個視窗頂端風景不錯", "Thwip! 🕸")
        p.Say("talk_d", "都幾點了還不下班？", "老闆不會多給你加班費的。", "……你還在？", "這個 bug 明天還會在，你不用在。", "下班。現在。", "你的床在等你。我也在等你關機。")
        p.Say("save", "存好了！👍", "存檔成功，帥！", "Thwip! 已存檔", "穩穩的 👍")
        p.Say("save_d", "存了就快走。", "存好了。可以關機了吧？", "……存檔。然後下班。")
        p.Say("pats", "你今天也很棒！", "累了就休息一下，我陪你", "有我在，bug 不敢來", "我一直都在喔 ♥", "你寫的 code 很帥",
            "辛苦了，摸摸頭", "不管怎樣我都站你這邊", "今天也謝謝你陪我", "慢慢來，你可以的", "嘿嘿，再摸一下", "你笑起來一定很好看", "有你在我就很安心")
        p.Say("pats_d", "……摸夠了就下班。", "我是擔心你才一直催你。", "你已經很努力了，剩下的明天再說。", "回家好好吃飯，聽到沒？", "哼，就讓你摸一下。", "我不是在撒嬌，是在叫你下班。")
        p.Say("pats_hi", "能遇到你真好", "我最喜歡你了 ♥", "今天也要一起喔", "有你在，每天都很開心", "我們是最佳拍檔！")
        p.Say("hugs", "抱抱～", "給你一個蜘蛛抱抱 ♥", "辛苦了，抱一下", "(つ´ω`)つ ♥")
        p.Say("hugs_d", "……只抱一下。然後下班。", "抱完就回家，聽到沒？", "(つ﹏⊂) 回家啦")
        p.Say("knock", "叩叩！你在看我嗎？👀", "嘿～螢幕外面的你！", "我可以出去玩嗎？叩叩", "你今天也很努力喔！")
        p.Say("knock_d", "叩、叩。下班了沒？", "我在螢幕裡面都看到了，你還在加班。", "再不關機我要黑掉你的螢幕喔（騙你的）")
        p.Say("newwin", "新視窗！Thwip!", "我來看看這是什麼～", "噴個絲黏上去！")
        p.Say("newwin_d", "又開新視窗？想加班？", "……這個也明天再看。", "不准再開了。")
        p.Say("hi", "嗨！我是你的 Spidey 👋"); p.Say("hi_d", "……嗨。下班了嗎？")
        p.Say("wake", "嗯…是你呀 ♥ 我醒了"); p.Say("wake_d", "……是你啊。我沒睡，只是在等你下班。")
        p.Say("dizzy", "頭暈了 @@ 你好愛我喔"); p.Say("dizzy_d", "別、別再點了……頭好暈")
        p.Say("dizzy_ok", "好、好了，我沒事 ♥"); p.Say("dizzy_ok_d", "……沒事。")
        p.Say("tickle", "哈哈哈好癢～"); p.Say("tickle_d", "……好癢。不准笑。")
        p.Say("pat10", "今天第 {n} 次摸我了，我好開心 ♥"); p.Say("pat10_d", "今天第 {n} 次了……我才沒有很開心。")
        p.Say("levelup", "好感度升到 Lv{n} 了！解鎖「{u}」♥"); p.Say("levelup_d", "……好感度 Lv{n}。解鎖「{u}」。我、我才沒有很高興。")
        p.Say("missed", "你最近都不理我…摸摸我好不好 🥺"); p.Say("missed_d", "……你好幾天沒摸我了。哼。")
        p.Say("hover", "你在摸我嗎？抱抱～")
        p.Say("seek", "那是什麼？"); p.Say("seek_lost", "咦，跑掉了…"); p.Say("seek_got", "抓到你的滑鼠了！抱抱 ♥")
        p.Say("drag", "哇啊——放我下來！"); p.Say("throw", "咻——")
        p.Say("shelf_in", "好～我回公仔櫃乖乖待著 ♥"); p.Say("shelf_in_d", "……好，我回櫃子裡待著。你也早點回家。")
        p.Say("shelf_out", "自由了！出去玩囉～"); p.Say("shelf_out_d", "……放我出來了？那我要去催你下班了。")
        p.Say("ball_go", "球！我來了！", "等我～", "這次一定接到！"); p.Say("ball_go_d", "……好啦，陪你玩一下。")
        p.Say("ball_catch", "接到了！還你～", "好球！傳回去！", "嘿嘿，我很厲害吧"); p.Say("ball_catch_d", "……接到了。還你。")
        p.Say("ball_end", "不玩了嗎？好吧～下次再玩 ⚾"); p.Say("ball_end_d", "……不玩了？那就下班吧。")
        p.Say("ball_far", "球跑太遠了啦～")
        p.Say("back", "我回來了～"); p.Say("back_d", "……我回來了。")
        p.Say("share_end", "分享結束了～我回來囉")
        p.Say("welcome", "你回來啦！我等你好久 ♥"); p.Say("welcome_d", "……你回來了。是要來關機的吧？")
        p.Say("rest", "已經連續用 {n} 分鐘了，起來喝口可樂、伸展一下！🥤"); p.Say("rest_d", "……喝完可樂就下班。")
        p.Say("night_on", "……下班時間到了。"); p.Say("night_off", "早安，我又變回來了 ☀")
        p.Say("sleep", "晚安…"); p.Say("sleep_d", "……你也該睡了。")
        p.Say("jump", "跳～"); p.Say("nojump", "附近沒有可以跳的視窗")
        p.Say("errors", "蜘蛛感應！有 {n} 個錯誤"); p.Say("errors_d", "{n} 個錯誤……明天再修，回家。")
        p.Say("errors_ok", "錯誤都清光了，抱一個！"); p.Say("errors_ok_d", "錯誤清完了。那就可以下班了吧。")
        p.Say("typing", "你打字好快！加油加油 ♪", "手指在冒煙了！🔥", "衝衝衝～我幫你打氣！"); p.Say("typing_d", "打這麼快是想快點下班吧？加油。")
        p.Say("done", "{who} 做完了！快來看 👀"); p.Say("done_d", "{who} 做完了。你也該收工了。")
        p.Say("wait", "{who} 在等你回答喔～ 👋"); p.Say("wait_d", "{who} 在等你回答。快點回完快點下班。")
        p.Say("ask", "{who} 在問你問題，等你回答喔～ 🙋"); p.Say("ask_d", "{who} 在問你問題。回完就下班。")
        p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，是不是在等你按允許？"); p.Say("stuck_tool_d", "{who} 停了 {n} 分鐘。去按一下，然後下班。")
        p.Say("stuck", "{who} 好像卡住了…{n} 分鐘沒動靜，去看看？ 🕷️"); p.Say("stuck_d", "{who} 卡住 {n} 分鐘了。去看一眼，看完就下班。")
        p.Say("unstuck", "{who} 又動起來了！👍"); p.Say("unstuck_d", "{who} 動了。")
        p.Say("tag", "上版成功！🎆"); p.Say("tag_dev", "測試機上版成功！🎆"); p.Say("tag_prod", "上正式機了！🎉 辛苦了！"); p.Say("tag_d", "上版成功……那現在可以下班了吧？🎆")
        p.Say("late23", "很晚了耶，早點休息好不好 🌙"); p.Say("late12", "午餐吃了沒？"); p.Say("late15", "下午茶時間～來罐可樂吧 🥤")
        p.Say("late_d", "下班時間早就過了喔。"); p.Say("late_dd", "這麼晚了。關機，睡覺。")
        p.Say("g_late", "這麼晚還在寫？我陪你 🌙"); p.Say("g_morning", "早安！今天也一起加油 ☀"); p.Say("g_noon", "午安～吃飯了沒？我出來陪你")
        p.Say("g_evening", "晚上了，辛苦啦，我陪你"); p.Say("g_day", "我出來玩啦！整個螢幕都是我的 🕸"); p.Say("g_d", "……下班時間了。你為什麼還開著電腦？")
        p.Say("app_browser", "又在逛網頁？帶我一起看～"); p.Say("app_code", "回來寫 code 啦！我陪你"); p.Say("app_excel", "在算數字喔，加油！")
        p.Say("app_ppt", "在做簡報？我幫你盯排版"); p.Say("app_word", "在寫文件～慢慢來"); p.Say("app_chat", "有人找你嗎？"); p.Say("app_files", "在找檔案？")
        p.Say("app_other", "你在用這個呀？我也來看看")
        p.Say("app_code_d", "還在寫 code？下班了啦。"); p.Say("app_chat_d", "下班了還回訊息？明天再說。"); p.Say("app_office_d", "這份明天做也不會怎樣。"); p.Say("app_other_d", "……你在做什麼？不是該下班了嗎。")
        p.Say("s_birthday", "生日快樂！🎂 今天你最大！", "祝你生日快樂～我做了蛋糕給你", "今天是你的日子，什麼都不准煩惱 ♥")
        p.Say("s_cny", "新年快樂！恭喜發財 🧧", "紅包拿來～（騙你的，這個給你）", "新的一年也一起加油！")
        p.Say("s_xmas", "聖誕快樂！🎄", "我想要的聖誕禮物，就是你準時下班", "叮叮噹～叮叮噹～ ❄")
        p.Say("s_newyear", "新年快樂！今年也請多多指教 ✨")
        p.Say("s_halloween", "不給糖就搗蛋！🎃", "我今天扮成……蜘蛛人（本來就是）")
        p.Say("s_friday", "週五了！！撐住！", "小週末～今天準時下班好不好", "再一下下就週末了 ✨")
        p.Say("morning", "早安！Spidey 報到 🕸", "早安～今天也要一起守護城市（的 code）")
        p.Say("goodnight", "晚安，我先回櫃子裡巡邏… 🕸", "……今天辛苦了。晚安。")
        p.Say("nag", "下班。現在。", "你的床在等你。", "……還不走？")
        p.Say("react", "！", "怎麼了？", "蜘蛛感應！")
        p.Shared()
        return p
    }

    // ---------------- 小波（紅色天線寶寶，同人像素）----------------
    static func Po() -> Pal
    {
        let p = Pal()
        p.Id = "po"; p.Name = "小波"; p.Move = "scooter"; p.BallKind = "baseball"; p.NightStyle = "sunset"; p.NightBubble = 2
        p.Accent = C(0xE7836A); p.Panel = C(0xFFE3CF); p.Halo = Color.White; p.HaloNight = C(0xFFC58F)
        // 夜晚：太陽寶寶下山 → 整體暗一點、偏夕陽橘紫
        p.Col("k", 0x3A1A1A, 0x2A1220); p.Col("r", 0xE3262B, 0xB4303A); p.Col("R", 0xA8161C, 0x7E1A2A); p.Col("h", 0xFF5A5E, 0xD8505A); p.Col("e", 0xF4CDBE, 0xD3A79C)
        p.Col("f", 0xF6D2B0, 0xD9AE92); p.Col("F", 0xE8B892, 0xBF907A); p.Col("m", 0xB8323C, 0x8E2E40); p.Col("p", 0xF29A9A, 0xC97A84)
        p.Col("g", 0xC9CDD3, 0x8F8CA6); p.Col("G", 0x8E949C, 0x5F5C78); p.Col("w", 0xFFFFFF, 0xFFE4CC); p.Col("y", 0xFFD84A, 0xFFB45E)
        p.Col("s", 0x55C7BE, 0x3F8F95); p.Col("q", 0x2F8F88, 0x266A70); p.Col("o", 0x6B6F7A, 0x4E4A5E) // 滑板車：踏板、深色、輪子
        // 天線（中空圓圈）＋大圓頭：紅色頭套框住一張很大的膚色平臉，兩邊小耳朵
        p.Art["HEAD"] = [
            ".......rr.......",
            "......r..r......",
            ".......rr.......",
            ".......rr.......",
            ".....kkkkkk.....",
            "...kkrrrrrrkk...",
            ".kkhrffffffrRkk.",
            "kehrffffffffrRek",
            "kehrfkffffkfrRek",
            "kehrfkffffkfrRek",
            "kehrpfmffmfprRek",
            ".kkhrffmmffrRkk.",
            "...kkrrrrrrkk..."]
        p.Art["SLEEPY"] = [
            "kehrffffffffrRek",
            "kehrffffffffrRek",
            "kehrkkffffkkrRek",
            "kehrpffffffprRek",
            ".kkhrffmmffrRkk."]
        p.Art["HAPPY"] = [
            "kehrffffffffrRek",
            "kehrfkffffkfrRek",
            "kehrkfkffkfkrRek",
            "kehrpmffffmprRek",
            ".kkhrfmmmmfrRkk."]
        p.Art["DIZZY"] = [
            "kehrffffffffrRek",
            "kehrkfkffkfkrRek",
            "kehrfkffffkfrRek",
            "kehrkfkffkfkrRek",
            ".kkhrffmmffrRkk."]
        p.Art["SQUISH"] = [
            "kehrffffffffrRek",
            "kehrkkffffkkrRek",
            "kehrkkffffkkrRek",
            "kehrpffmmffprRek",
            ".kkhrffmmffrRkk."]
        p.Art["BODY"] = [
            "..khGGGGGGGGRk..",
            "rkhrGwggggggGRkr",
            "rkhrGggggggGrRkr",
            ".khrGggggggGrRk.",
            "..khGGGGGGGGRk..",
            "...kRrrrrrrrRk.."]
        p.Art["ARMS_UP"] = [
            "rkkhGGGGGGGGRkkr",
            ".khrGwgggggGrRk.",
            ".khrGggggggGrRk.",
            ".khrGggggggGrRk.",
            "..khGGGGGGGGRk..",
            "...kRrrrrrrrRk.."]
        p.Art["ARMS_HUG"] = [
            "....khGGGGGGGGRk....",
            "rrrkhrGwgggggGrRkrrr",
            "kkkkhrGggggggGrRkkkk",
            "...khrGggggggGrRk...",
            "....khGGGGGGGGRk....",
            ".....kRrrrrrrrRk...."]
        p.Art["LEGS_A"] = [
            "...krrk..krrk...",
            "...kkkk..kkkk..."]
        p.Art["LEGS_B"] = [
            "..krrk....krrk..",
            "..kkkk....kkkk.."]
        p.Art["LEGS_RIDE"] = [
            "....krrkkrrk....",
            "....kkkkkkkk...."]
        p.Art["LEGS_SIT"] = [
            "..krrkkkkkkrrk..",
            ".kkkk......kkkk."]
        // 滑板車（面向右；拉到 14 格寬，車頭在右邊）
        p.Art["SCOOTER"] = [
            "...........kk.",
            "...........ks.",
            "...........ks.",
            "...........ks.",
            "...........ks.",
            ".kkkkkkkkkkks.",
            ".kssssssssssk.",
            ".kooq....kooq.",
            "..oo......oo.."]
        p.HatRow = 0; p.HatCol = 0; p.ScarfRow = 7; p.GlassRow = 3; p.BadgeRow = 12; p.BadgeCol = 5; p.SideRow = 9
        p.EyeRow = -1; p.FaceRow = 7; p.Speed = 95; p.KeepAntenna = true; p.TopRows = 5
        p.Say("talk", "Eh-oh!", "我們一起騎車車～", "抱抱時間到了沒？", "今天天氣好好喔 ☀", "小波最喜歡你了", "要喝可樂樂喔 🥤", "嘟嘟～小波來囉")
        p.Say("talk_d", "太陽寶寶下山了，該說再見囉", "小波想睡覺覺了…你也回家好不好", "天黑黑了，明天再玩", "晚安晚安～該回家囉", "再見再見～（揮揮手）")
        p.Say("save", "存好了！好棒棒 👏", "存起來了～再來一次！", "Eh-oh! 存檔成功", "小波幫你收好囉")
        p.Say("save_d", "存好了…那我們回家好不好", "存好了，太陽寶寶也下山囉", "收好了～該說再見囉")
        p.Say("pats", "嘻嘻，好舒服", "你好棒棒！", "小波喜歡你 ♥", "摸摸頭～你也辛苦了", "Eh-oh! 再摸一下", "你笑一個嘛 😊", "有小波陪你喔", "慢慢來，小波等你")
        p.Say("pats_d", "嗯…小波想睡覺覺了", "摸摸…然後我們回家好不好", "太陽寶寶下山了，你也該休息囉", "嘿嘿…明天再陪你玩")
        p.Say("pats_hi", "能遇到你真好 ♥", "小波最最最喜歡你了", "我們是好朋友！", "每天都要一起玩喔")
        p.Say("hugs", "大抱抱！", "大抱抱～ ♥", "Eh-oh! 大抱抱！", "(つ´ω`)つ 大抱抱")
        p.Say("hugs_d", "大抱抱…然後回家睡覺覺", "晚安大抱抱 ♥", "抱完就說再見囉")
        p.Say("knock", "叩叩！Eh-oh! 👀", "嗨嗨～螢幕外面的你！", "小波可以出去玩嗎？", "肚肚貼玻璃～嘿嘿")
        p.Say("knock_d", "叩叩…太陽寶寶下山了喔", "該說再見囉，回家吧～", "小波看到你還在加班…")
        p.Say("newwin", "Eh-oh!", "Eh-oh! 新視窗！", "咻～我來看看！")
        p.Say("newwin_d", "Eh-oh…又開新的了？明天再看嘛", "天黑黑了，不要再開了啦")
        p.Say("hi", "Eh-oh! 我是小波 👋"); p.Say("hi_d", "Eh-oh…太陽寶寶下山了耶")
        p.Say("wake", "嗯…Eh-oh? 是你呀 ♥"); p.Say("wake_d", "嗯…小波在睡覺覺…你也去睡嘛")
        p.Say("dizzy", "轉圈圈～頭暈暈 @@"); p.Say("dizzy_d", "暈暈…小波要睡覺覺了…")
        p.Say("dizzy_ok", "好了！再來一次！"); p.Say("dizzy_ok_d", "好了…該回家囉")
        p.Say("tickle", "再來一次！", "再來一次！再來一次！", "嘻嘻嘻好癢～再來一次！"); p.Say("tickle_d", "嘻嘻…最後一次喔")
        p.Say("pat10", "今天第 {n} 次摸摸了！小波好開心 ♥"); p.Say("pat10_d", "第 {n} 次了…摸完就回家喔")
        p.Say("levelup", "好感度 Lv{n}！小波拿到「{u}」了 ♥"); p.Say("levelup_d", "Lv{n}…拿到「{u}」…明天再戴給你看")
        p.Say("missed", "你好久沒摸摸小波了…🥺"); p.Say("missed_d", "好久沒摸摸了…明天要記得喔")
        p.Say("hover", "Eh-oh? 你在摸摸我嗎～")
        p.Say("seek", "咦？那是什麼？"); p.Say("seek_lost", "跑掉了…"); p.Say("seek_got", "抓到滑鼠了！大抱抱！")
        p.Say("drag", "哇～飛高高！"); p.Say("throw", "咻～～")
        p.Say("shelf_in", "小波回家家囉，掰掰 👋"); p.Say("shelf_in_d", "太陽寶寶下山了，小波回家睡覺覺")
        p.Say("shelf_out", "Eh-oh! 小波出來玩囉！"); p.Say("shelf_out_d", "Eh-oh…天黑黑了耶，你怎麼還在？")
        p.Say("ball_go", "棒球！小波來了！", "我接我接！", "看我的手套！"); p.Say("ball_go_d", "最後一球喔…")
        p.Say("ball_catch", "接到了！傳回去～", "好球！", "嘿嘿，手套好厲害"); p.Say("ball_catch_d", "接到了…還你，該回家囉")
        p.Say("ball_end", "不玩了嗎？下次再來一次！⚾"); p.Say("ball_end_d", "不玩了…那我們回家吧")
        p.Say("ball_far", "球球跑好遠喔～")
        p.Say("back", "Eh-oh! 小波回來了"); p.Say("back_d", "小波回來了…")
        p.Say("share_end", "分享完了～Eh-oh!")
        p.Say("welcome", "Eh-oh! 你回來了！大抱抱！"); p.Say("welcome_d", "你回來了…是要回家了嗎？")
        p.Say("rest", "已經 {n} 分鐘了，起來動一動、喝口可樂樂 🥤"); p.Say("rest_d", "{n} 分鐘了…太陽寶寶都下山了，回家吧")
        p.Say("night_on", "太陽寶寶下山了…該說再見囉"); p.Say("night_off", "太陽寶寶起床了！Eh-oh! ☀")
        p.Say("sleep", "睡覺覺…晚安"); p.Say("sleep_d", "晚安晚安…你也去睡覺覺")
        p.Say("jump", "咻～"); p.Say("nojump", "附近沒有可以飛的地方耶")
        p.Say("errors", "嗚…有 {n} 個錯誤，好可怕"); p.Say("errors_d", "{n} 個錯誤…明天再修啦，回家")
        p.Say("errors_ok", "錯誤都不見了！大抱抱！"); p.Say("errors_ok_d", "都修好了！那我們回家吧")
        p.Say("typing", "打好快喔！嘟嘟嘟～", "加油加油！再來一次！", "手指在跳舞耶 ♪"); p.Say("typing_d", "打好快…是想快點回家吧")
        p.Say("done", "全壘打！{who} 做完了！"); p.Say("done_d", "全壘打！{who} 做完了～太陽寶寶下山了，回家吧")
        p.Say("wait", "{who} 在等你回答喔 👋"); p.Say("wait_d", "{who} 在等你…回完就回家喔")
        p.Say("ask", "{who} 有問題要問你喔 🙋"); p.Say("ask_d", "{who} 在問你問題…回完就回家")
        p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，要你按按看嗎？"); p.Say("stuck_tool_d", "{who} 停了 {n} 分鐘…按一下就回家")
        p.Say("stuck", "{who} 不動了…{n} 分鐘了耶，去看看？"); p.Say("stuck_d", "{who} 卡住 {n} 分鐘了…看完就說再見囉")
        p.Say("unstuck", "{who} 又動了！好棒棒 👏"); p.Say("unstuck_d", "{who} 動了…")
        p.Say("tag", "全壘打！上版成功！⚾"); p.Say("tag_dev", "測試機全壘打！⚾"); p.Say("tag_prod", "正式機全壘打！好棒棒 🎉"); p.Say("tag_d", "全壘打…上完了，回家吧")
        p.Say("late23", "好晚了…小波想睡覺覺 🌙"); p.Say("late12", "吃飯飯了沒？"); p.Say("late15", "點心時間～吐司要不要？")
        p.Say("late_d", "太陽寶寶早就下山了喔"); p.Say("late_dd", "好晚好晚了…晚安，回家吧")
        p.Say("g_late", "這麼晚了…小波陪你一下下 🌙"); p.Say("g_morning", "Eh-oh! 早安！太陽寶寶起床了 ☀"); p.Say("g_noon", "Eh-oh! 午安～吃飯飯了沒？")
        p.Say("g_evening", "Eh-oh～晚上了，辛苦了"); p.Say("g_day", "Eh-oh! 小波來玩囉！"); p.Say("g_d", "太陽寶寶下山了…你怎麼還在？")
        p.Say("app_browser", "在看什麼？小波也要看～"); p.Say("app_code", "寫 code 時間！小波陪你"); p.Say("app_excel", "好多格子喔～")
        p.Say("app_ppt", "做簡報～要畫太陽寶寶嗎？"); p.Say("app_word", "寫字字～慢慢來"); p.Say("app_chat", "有人找你玩嗎？"); p.Say("app_files", "在找東西嗎？")
        p.Say("app_other", "Eh-oh! 這是什麼？")
        p.Say("app_code_d", "還在寫…太陽寶寶下山了啦"); p.Say("app_chat_d", "天黑了，明天再回嘛"); p.Say("app_office_d", "明天再做好不好～"); p.Say("app_other_d", "該說再見囉～")
        p.Say("s_birthday", "生日快樂！小波唱歌給你聽 🎂", "今天你最大！大抱抱！")
        p.Say("s_cny", "新年快樂！恭喜恭喜 🧧", "紅包…小波可以拿嗎？")
        p.Say("s_xmas", "聖誕快樂！🎄", "叮叮噹～小波想要新車車")
        p.Say("s_newyear", "新年快樂！Eh-oh! ✨")
        p.Say("s_halloween", "不給糖就搗蛋！🎃", "小波扮成…番茄！")
        p.Say("s_friday", "星期五了！再來一次週末！", "快放假了～騎車車去玩！")
        p.Say("morning", "Eh-oh! 早安～小波來了！", "太陽寶寶起床囉！早安！")
        p.Say("goodnight", "太陽寶寶下山了，小波說再見囉 👋", "晚安晚安～大抱抱")
        p.Say("nag", "太陽寶寶下山了，該說再見囉", "回家家囉～", "小波想睡覺覺了…")
        p.Say("react", "Eh-oh?", "咦？", "怎麼了怎麼了？")
        p.Shared()
        return p
    }

    // ---------------- 史迪仔（藍色小外星人，同人像素）----------------
    static func Stitch() -> Pal
    {
        let p = Pal()
        p.Id = "stitch"; p.Name = "史迪仔"; p.Move = "crawl"; p.BallKind = "tennis"; p.NightStyle = "sleepy"; p.NightBubble = 3
        p.Accent = C(0x3461B4); p.Panel = C(0xD8E7FA); p.Halo = Color.White; p.HaloNight = C(0xA9C8F5)
        // 使用者核准的母版 D（22×25）：槳狀大耳朵（粉紅內側、左耳缺口）、寬頭沒脖子、細淺框大黑眼、圓圓深藍大鼻子、露牙笑、梨形身體大淺肚
        p.Col("k", 0x1B2A4A, 0x111A30); p.Col("b", 0x3D6BB3, 0x33598F); p.Col("d", 0x2B4F86, 0x22406C); p.Col("l", 0x8FB6E6, 0x7092BE)
        p.Col("p", 0xE58FB8, 0xB57090); p.Col("e", 0x0A0A14, 0x0A0A14); p.Col("w", 0xFFFFFF, 0xDDEBFF); p.Col("n", 0x1C2A55, 0x151F40)
        p.Col("h", 0x5B6FA8, 0x46588A); p.Col("m", 0x5A1A2A, 0x441420); p.Col("t", 0xE86A8A, 0xB85670); p.Col("q", 0xF4EFD8, 0xCFCAB4); p.Col("y", 0xFFD84A, 0xC9D8FF)
        p.Art["HEAD"] = [
            "..kkkk..........kkkk..",
            "..bppk..........kppbk.",
            ".kpppbk........kbpppk.",
            ".kpppbk........kbpppk.",
            ".kpppk.....k....kpppk.",
            ".kpppk....kk....kpppk.",
            ".kppbk.kkkbbkkk.kbppk.",
            "..kbbbkbbbbbbbbkbbbk..",
            "...kbbbllbbbbllbbbk...",
            "...kbbllwebblewlbbk...",
            "....kbleeennleeebk....",
            "....kbleenhnneeebk....",
            "....kbllennnneelbk....",
            ".....kbmbbbbbbmbk.....",
            "......kmmqmmqmmk......",
            ".....kbbbbttbbbbk....."]
        p.Art["EARS_UP"] = [
            "..kkkk..........kkkk..",
            "..bppk..........kppbk.",
            ".kpppbk........kbpppk.",
            ".kpppbk........kbpppk.",
            ".kpppk.....k....kpppk.",
            ".kpppk....kk....kpppk.",
            ".kppbk.kkkbbkkk.kbppk.",
            "..kbbbkbbbbbbbbkbbbk.."]
        p.Art["EARS_DOWN"] = [
            "......................",
            "......................",
            "......................",
            "......................",
            "...........k..........",
            "..kkk.....kk.....kkkk.",
            "kpppbkkkkkbbkkkkkbpppk",
            ".kkbbbkbbbbbbbbkbbbkk."]
        p.Art["SLEEPY"] = [
            "...kbbllllbbllllbbk...",
            "....kbllllnnllllbk....",
            "....kbleenhnnleebk....",
            "....kblllnnnnlllbk....",
            ".....kbmbbbbbbmbk.....",
            "......kmmqmmqmmk......"]
        p.Art["HAPPY"] = [
            "...kbbllllbbllllbbk...",
            "....kbllelnnllelbk....",
            "....kblelnhnnelebk....",
            "....kblllnnnnlllbk....",
            ".....kbmbbbbbbmbk.....",
            "......kmmqmmqmmk......"]
        p.Art["DIZZY"] = [
            "...kbblelebblelebbk...",
            "....kbllelnnllelbk....",
            "....kblelehnnelebk....",
            "....kblllnnnnlllbk....",
            ".....kbmbbbbbbmbk.....",
            "......kmmqmmqmmk......"]
        p.Art["GRIN"] = [
            "...kbbllwebblewlbbk...",
            "....kbleeennleeebk....",
            "....kbleenhnneeebk....",
            "....kbllennnneelbk....",
            ".....kbmbbbbbbmbk.....",
            "......kmqmqmqmmk......"]
        p.Art["LICKF"] = [
            "...kbbllllbbllllbbk...",
            "....kbllelnnllelbk....",
            "....kblelnhnnelebk....",
            "....kblllnnnnlllbk....",
            ".....kbmbbbbbbmbk.....",
            "......kmmqmmqmmk......"]
        p.Art["BODY"] = [
            ".....kbdbbllbbdbk.....",
            ".....kbdlllllldbk.....",
            "....kbbdlllllldbbk....",
            "....kbbdlllllldbbk....",
            "....kkbbllllllbbkk....",
            ".....kbbbkkkkbbbk....."]
        p.Art["ARMS_UP"] = [
            ".....kbbbbllbbbbk.....",
            "..kkkbbbllllllbbbkkk..",
            "..kbbkbllllllllbkbbk..",
            "..kkkbbllllllllbbkkk..",
            "....kbbllllllllbbk....",
            "....kkbbllllllbbkk...."]
        p.Art["ARMS_HUG"] = [
            ".....kbdbbllbbdbk.....",
            ".....kbdlllllldbk.....",
            "....kbbddddddddbbk....",
            "....kbbbllllllbbbk....",
            "....kbbllllllllbbk....",
            "....kkbbllllllbbkk...."]
        p.Art["LICK"] = [
            ".....kbdbtttbbdbk.....",
            ".....kbdltttlldbk.....",
            "....kbbdllttlldbbk....",
            "....kbbdlllllldbbk....",
            "....kkbbllllllbbkk....",
            ".....kbbbkkkkbbbk....."]
        p.Art["LEGS_A"] = [
            ".....kbbk....kbbk.....",
            "......kk......kk......"]
        p.Art["LEGS_B"] = [
            ".....kbbk.....kbbk....",
            "......kk.......kk....."]
        p.Art["CRAWL_A"] = [
            ".....kbbbllllbbbk.....",
            "....kbbk.kkkk.kbbk....",
            "....kkk........kkk...."]
        p.Art["CRAWL_B"] = [
            ".....kbbbllllbbbk.....",
            ".....kbbkkkkkkbbk.....",
            ".....kkk......kkk....."]
        p.Art["BALL"] = [
            ".kkk......kkk.",
            "kppbk....kbppk",
            "kpppbkkkkbpppk",
            ".kbbbbbbbbbbk.",
            "kbbllbbbbllbbk",
            "kbleeennneelbk",
            "kbleenhnneelbk",
            "kbbmqmmmqmbbbk",
            ".kbbbllllbbbk.",
            "..kkkkkkkkkk.."]
        p.Art["BALL_SLEEP"] = [
            ".kkk......kkk.",
            "kppbk....kbppk",
            "kpppbkkkkbpppk",
            ".kbbbbbbbbbbk.",
            "kbbllbbbbllbbk",
            "kbllllnnnlllbk",
            "kbleeenhneeebk",
            "kbbbmmmmmmbbbk",
            ".kbbbllllbbbk.",
            "..kkkkkkkkkk.."]
        p.Art["UKE"] = [
            ".....2",
            "....22",
            "...12.",
            ".111..",
            "11k1..",
            "1111..",
            ".11..."]
        p.FaceRow = 9; p.EyeRow = -1; p.TopRows = 8; p.NoGlasses = true
        p.HatRow = -1; p.HatCol = 0; p.ScarfRow = 8; p.GlassRow = 1; p.BadgeRow = 10; p.BadgeCol = 5; p.SideRow = 10
        p.Speed = 120
        p.Say("talk", "Aloha!", "ih-ih-ih!", "Ohana 就是一家人，一家人不會丟下任何人", "嘻嘻嘻～", "meega nala kweesta!", "史迪仔，好孩子！")
        p.Say("talk_d", "Ohana 在家等你喔…", "呼啊～（打哈欠）", "回家，Ohana 在等", "ih…想睡…")
        p.Say("save", "ih! 存好了！", "存檔～嘻嘻嘻", "好孩子！存好了 👍")
        p.Say("save_d", "存好了…回家，Ohana 在等", "存了。呼啊～回家")
        p.Say("pats", "嘻嘻嘻～", "ih-ih-ih!", "好孩子！史迪仔是好孩子！", "Ohana ♥", "再摸！再摸！", "嘿嘿嘿（搖耳朵）", "你是 Ohana！")
        p.Say("pats_d", "呼啊…好舒服…", "摸完…回家", "Ohana 在家等你喔")
        p.Say("pats_hi", "你是史迪仔最重要的 Ohana ♥", "一家人不會丟下任何人！", "史迪仔最喜歡你！")
        p.Say("hugs", "Ohana～抱抱！", "抱抱！ih-ih!", "(つ´ω`)つ Ohana"); p.Say("hugs_d", "抱抱…然後回家", "Ohana 抱抱…晚安")
        p.Say("knock", "（舔舔玻璃）嘻嘻嘻", "ih! 你在裡面嗎？", "Aloha～放我出去！", "叩叩叩叩叩叩！")
        p.Say("knock_d", "（舔）…回家啦", "Ohana 在家等你喔", "呼啊～下班！")
        p.Say("newwin", "ih?! 新的！", "嘻嘻，那是什麼？", "（聞聞）ih-ih!"); p.Say("newwin_d", "又開？回家啦…", "不要了，睡覺！")
        p.Say("hi", "Aloha! 史迪仔 👋"); p.Say("hi_d", "Aloha…呼啊～")
        p.Say("wake", "ih?! 醒了醒了！"); p.Say("wake_d", "呼啊…Ohana？")
        p.Say("dizzy", "轉轉轉～ih-ih-ih @@"); p.Say("dizzy_d", "暈…睡覺…")
        p.Say("dizzy_ok", "好了！嘻嘻嘻"); p.Say("dizzy_ok_d", "…好了")
        p.Say("tickle", "ih-ih-ih! 好癢！", "嘻嘻嘻嘻嘻！"); p.Say("tickle_d", "嘻…好癢…")
        p.Say("pat10", "第 {n} 次！Ohana ♥"); p.Say("pat10_d", "第 {n} 次…回家啦")
        p.Say("levelup", "Lv{n}！史迪仔拿到「{u}」！嘻嘻嘻"); p.Say("levelup_d", "Lv{n}…「{u}」…明天戴")
        p.Say("missed", "你都不理史迪仔…Ohana 不會丟下任何人的 🥺"); p.Say("missed_d", "好久沒摸了…")
        p.Say("hover", "ih? 摸摸？")
        p.Say("seek", "ih! 那是什麼！"); p.Say("seek_lost", "跑了？！"); p.Say("seek_got", "抓到了！嘻嘻嘻")
        p.Say("drag", "ih-ih! 放開！"); p.Say("throw", "嗚哇哇哇～")
        p.Say("shelf_in", "史迪仔回窩囉，Aloha～"); p.Say("shelf_in_d", "呼啊～史迪仔回家睡覺")
        p.Say("shelf_out", "自由了！ih-ih-ih!"); p.Say("shelf_out_d", "ih…你還沒回家？")
        p.Say("ball_go", "球！史迪仔的！", "ih-ih! 等我！", "我抓我抓！"); p.Say("ball_go_d", "球…好吧，一下下")
        p.Say("ball_catch", "抓到！還你～", "嘻嘻嘻，好球", "史迪仔最快！"); p.Say("ball_catch_d", "抓到…還你")
        p.Say("ball_end", "不玩了？Aloha～"); p.Say("ball_end_d", "不玩了…睡覺")
        p.Say("ball_far", "跑太遠了！")
        p.Say("back", "Aloha～我回來了"); p.Say("back_d", "…回來了")
        p.Say("share_end", "分享完了？Aloha!")
        p.Say("welcome", "你回來了！Ohana！抱抱！"); p.Say("welcome_d", "回來了…要回家了嗎？")
        p.Say("rest", "{n} 分鐘了！起來喝可樂！咕嚕咕嚕 ih-ih! 🥤"); p.Say("rest_d", "{n} 分鐘了…喝完可樂就回家，Ohana 在等你")
        p.Say("night_on", "呼啊～天黑了…Ohana 在家等你喔"); p.Say("night_off", "Aloha! 早安！")
        p.Say("sleep", "呼…呼…"); p.Say("sleep_d", "晚安…Ohana…")
        p.Say("jump", "嘿咻！"); p.Say("nojump", "沒地方跳…")
        p.Say("errors", "ih-ih-ih! 有 {n} 個錯誤！史迪仔去咬它！"); p.Say("errors_d", "{n} 個錯誤…明天咬，回家")
        p.Say("errors_ok", "錯誤吃光光了！嘻嘻嘻"); p.Say("errors_ok_d", "吃光了…回家")
        p.Say("typing", "打好快！嘻嘻嘻♪", "ih-ih-ih! 快快快！"); p.Say("typing_d", "快打完…回家")
        p.Say("done", "{who} 做完了！Aloha～來看！"); p.Say("done_d", "{who} 做完了…回家，Ohana 在等")
        p.Say("wait", "{who} 在等你！ih!"); p.Say("wait_d", "{who} 在等…回完就回家")
        p.Say("ask", "{who} 有問題！快去！"); p.Say("ask_d", "{who} 在問…回完回家")
        p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了！要按允許嗎？"); p.Say("stuck_tool_d", "{who} 停 {n} 分鐘了…按一下回家")
        p.Say("stuck", "{who} 卡住了！{n} 分鐘！ih-ih!"); p.Say("stuck_d", "{who} 卡 {n} 分鐘…看一下回家")
        p.Say("unstuck", "{who} 動了！嘻嘻嘻"); p.Say("unstuck_d", "{who} 動了…")
        p.Say("tag", "上版了！Aloha～ 🎸"); p.Say("tag_dev", "測試機！嘻嘻嘻 🎸"); p.Say("tag_prod", "正式機！Thank you very much 🎸"); p.Say("tag_d", "上版了…回家睡覺")
        p.Say("late23", "好晚了…呼啊～ 🌙"); p.Say("late12", "吃飯！史迪仔要吃蛋糕！"); p.Say("late15", "點心！咖啡！")
        p.Say("late_d", "天黑了…Ohana 在等你"); p.Say("late_dd", "好晚…睡覺！")
        p.Say("g_late", "這麼晚？史迪仔陪你 🌙"); p.Say("g_morning", "Aloha! 早安！"); p.Say("g_noon", "Aloha～吃飯了嗎？")
        p.Say("g_evening", "Aloha～晚上好"); p.Say("g_day", "Aloha! 史迪仔來搗蛋啦！"); p.Say("g_d", "呼啊…天黑了，你怎麼還在？")
        p.Say("app_browser", "在看什麼？史迪仔也要！"); p.Say("app_code", "寫 code！史迪仔幫你咬 bug"); p.Say("app_excel", "好多格子…可以咬嗎？")
        p.Say("app_ppt", "簡報！放史迪仔照片！"); p.Say("app_word", "寫字字～"); p.Say("app_chat", "誰？Ohana 嗎？"); p.Say("app_files", "找東西？史迪仔聞聞！")
        p.Say("app_other", "ih? 這個是什麼？")
        p.Say("app_code_d", "還寫？回家！"); p.Say("app_chat_d", "明天再回…睡覺"); p.Say("app_office_d", "明天…呼啊～"); p.Say("app_other_d", "回家，Ohana 在等")
        p.Say("s_birthday", "生日快樂！史迪仔要吃蛋糕！🎂", "Ohana 生日快樂！")
        p.Say("s_cny", "新年快樂！紅包！ih-ih!", "恭喜發財 🧧")
        p.Say("s_xmas", "聖誕快樂！Aloha 🎄", "史迪仔想要新的烏克麗麗")
        p.Say("s_newyear", "新年快樂！Aloha ✨")
        p.Say("s_halloween", "不給糖就搗蛋！史迪仔本來就在搗蛋 🎃")
        p.Say("s_friday", "星期五！衝浪去！🏄", "快放假了！ih-ih-ih!")
        p.Say("morning", "Aloha! 早安！史迪仔來了！", "ih-ih! 早安 Ohana！")
        p.Say("goodnight", "呼啊～史迪仔回家睡覺了，Aloha", "晚安…Ohana 在家等你喔")
        p.Say("nag", "Ohana 在家等你喔", "回家！回家！", "呼啊～下班！")
        p.Say("react", "ih?!", "嘻嘻？", "什麼什麼？")
        p.Shared()
        return p
    }

    // ---------------- 人魚漢頓（Hangyodon，三麗鷗的藍綠色魚男孩，同人像素）----------------
    static func Hangyodon() -> Pal
    {
        let p = Pal()
        p.Id = "hangyodon"; p.Name = "人魚漢頓"; p.Move = "swim"; p.BallKind = "tennis"; p.NightStyle = "lonely"; p.NightBubble = 4
        p.Accent = C(0x1F9BA3); p.Panel = C(0xD6F2F0); p.Halo = Color.White; p.HaloNight = C(0xA6E3F0)
        // 參考三麗鷗原作：藍綠身體、黑線、上半部白色大眼、粉紅厚嘴唇帶、亮藍頭鰭和耳鰭、身上波浪鱗紋
        p.Col("k", 0x1B1F24, 0x101318); p.Col("b", 0x25B3BA, 0x1E8F9C); p.Col("d", 0x137F87, 0x10666F); p.Col("w", 0xFFFFFF, 0xE6F2F8)
        p.Col("K", 0x111111, 0x111111); p.Col("m", 0xF5A9C0, 0xD08AA4); p.Col("M", 0xD8708F, 0xA95A76); p.Col("f", 0x2D9BE3, 0x2678B8)
        p.Col("F", 0x1E74B5, 0x1A5C90); p.Col("c", 0xE23B3B, 0xB73838); p.Col("C", 0xA82828, 0x862A2A); p.Col("y", 0xFFD84A, 0xBFE8FF)
        p.Art["HEAD"] = [
            "...fff........",
            "..fFfFkkkk....",
            "..kfkbbbbbkk..",
            ".kbwwbbbbwwbk.",
            "fkwwwKbbKwwwkf",
            "fkwwwKbbKwwwkf",
            "fkbwwbbbbwwbkf",
            "kmmmmmmmmmmmmk"]
        p.Art["SLEEPY"] = [
            ".kbbbbbbbbbbk.",
            "fkbbbbbbbbbbkf",
            "fkbkkkbbkkkbkf",
            "fkbbbbbbbbbbkf"]
        p.Art["HAPPY"] = [
            ".kbbbbbbbbbbk.",
            "fkbbkbbbbkbbkf",
            "fkbkbkbbkbkbkf",
            "fkbbbbbbbbbbkf"]
        p.Art["DIZZY"] = [
            ".kbbbbbbbbbbk.",
            "fkbkbkbbkbkbkf",
            "fkbbkbbbbkbbkf",
            "fkbkbkbbkbkbkf"]
        p.Art["SILLY"] = [
            ".kbwwbbbbwwbk.",
            "fkKwwwbbwwwKkf",
            "fkwwwwbbwwwwkf",
            "fkbwwbbbbwwbkf"]
        p.Art["BODY"] = [
            "kmMMMMMMMMMMmk",
            ".kmmmmmmmmmmk.",
            "kbkbbbbbbbbkbk",
            ".kbdbbdbbdbbk.",
            ".kbbbbbbbbbbk."]
        p.Art["POUT"] = [
            ".kmmMMMMMMmmk.",
            "..kmmmmmmmmk..",
            "kbkbbbbbbbbkbk",
            ".kbdbbdbbdbbk.",
            ".kbbbbbbbbbbk."]
        p.Art["ARMS_UP"] = [
            "bmMMMMMMMMMMmb",
            "bkmmmmmmmmmmkb",
            ".kbbbbbbbbbbk.",
            ".kbdbbdbbdbbk.",
            ".kbbbbbbbbbbk."]
        p.Art["ARMS_HUG"] = [
            "..kmMMMMMMMMMMmk..",
            "...kmmmmmmmmmmk...",
            "bbkkbbbbbbbbbbkkbb",
            "...kbdbbdbbdbbk...",
            "...kbbbbbbbbbbk..."]
        p.Art["LEGS_A"] = [
            ".kbkbbbbbbkbk.",
            "..kbbk..kbbk..",
            "..kkkk..kkkk.."]
        p.Art["LEGS_B"] = [
            ".kbkbbbbbbkbk.",
            ".kbbk....kbbk.",
            ".kkkk....kkkk."]
        p.Art["LEGS_SIT"] = [
            ".kbkbbbbbbkbk.",
            "kbbbkk..kkbbbk",
            "kkkk......kkkk"]
        p.Art["CAPE"] = [
            "....cc",
            "...ccC",
            "..cccC",
            ".ccccC",
            "cccccC",
            "ccccC.",
            "cccCC.",
            ".cCC..",
            "..C..."]
        p.FaceRow = 3; p.EyeRow = -1
        p.HatRow = 2; p.HatCol = 0; p.ScarfRow = 8; p.GlassRow = 3; p.BadgeRow = 11; p.BadgeCol = 5; p.SideRow = 9
        p.Speed = 32
        p.Say("talk", "今天也要『魚』快喔！", "我游泳從來不累，因為『魚』刃有餘～", "我們是『鰻』好的朋友吧？", "我在『潛』心思考人生…", "我以後一定會當上英雄的！", "要不要聽笑話？…好啦我自己先笑", "莎莉說我很有趣喔（是真的！）")
        p.Say("talk_d", "大家都回家了……你也回家吧，不要像我一樣一個人", "天黑了，魚也要睡覺了", "你回家的話我會想你…但還是回家吧", "今天辛苦了，明天見好不好？")
        p.Say("save", "存好了！英雄任務完成～", "存檔成功！好笑嗎？…啊這不是笑話", "存起來了，『魚』快！"); p.Say("save_d", "存好了…那就回家吧", "存了，晚上的海很冷，快回家")
        p.Say("pats", "為什麼魚不打網球？因為怕碰到網子！", "我游泳不累，『魚』刃有餘！", "這個 bug 真是『鯊』很大", "我們是『鰻』好的朋友～", "年年有『魚』，天天有你！", "我不是胖，是『魚』肉多一點", "你今天很『鮮』喔！")
        p.Say("pats_d", "大家都回家了……摸完你也回家吧", "謝謝你陪我…但你也要休息喔", "晚上的笑話比較冷…像海水一樣")
        p.Say("pats_hi", "有你在，我就不寂寞了", "你是我最重要的觀眾！", "跟你在一起，每天都很好笑（好的那種）")
        p.Say("hugs", "抱抱～有點濕濕的，不好意思", "被抱抱的感覺…真好", "嘿嘿，抱抱 ♥"); p.Say("hugs_d", "抱一下…然後回家喔", "你回家我會想你，但還是要回家")
        p.Say("knock", "叩叩～有人在嗎？我是漢頓！", "（嘴唇貼玻璃）啵～", "要聽笑話嗎？叩叩！", "玻璃外面的你，今天開心嗎？")
        p.Say("knock_d", "叩叩…你還沒回家嗎？", "大家都走了…你也回家吧", "不要像我一樣一個人待到這麼晚喔")
        p.Say("newwin", "哇，新的海域！", "咕嚕咕嚕～我游過去看看！", "新視窗！有新觀眾嗎？"); p.Say("newwin_d", "又開新的？明天再看吧…", "晚上的海很冷，關掉吧")
        p.Say("hi", "嗨～我是漢頓，今天也要『魚』快喔！👋"); p.Say("hi_d", "嗨…你還在呀")
        p.Say("wake", "咕嚕…啊，我醒了！"); p.Say("wake_d", "嗯…是你呀，你也還沒睡？")
        p.Say("dizzy", "頭好暈…像在漩渦裡 @@"); p.Say("dizzy_d", "暈暈的…該睡了")
        p.Say("dizzy_ok", "好了好了，我沒事！"); p.Say("dizzy_ok_d", "沒事…回家吧")
        p.Say("tickle", "（扮鬼臉）噗嚕嚕嚕～", "看我的鬼臉！好笑嗎？", "（嘴唇噗噗噗）"); p.Say("tickle_d", "（小小的鬼臉）…好啦，回家")
        p.Say("pat10", "今天第 {n} 次了！有人一直陪我，好開心 ♥"); p.Say("pat10_d", "第 {n} 次了…謝謝你，但要回家喔")
        p.Say("levelup", "好感度 Lv{n}！拿到「{u}」了，像英雄一樣！"); p.Say("levelup_d", "Lv{n}…「{u}」…明天戴給你看")
        p.Say("missed", "你好幾天沒來看我了…還以為你忘記我了 🥺"); p.Say("missed_d", "好久沒摸我了…沒關係，回家吧")
        p.Say("hover", "咦？你在摸我嗎？好癢～")
        p.Say("seek", "那是什麼？游過去看看！"); p.Say("seek_lost", "咦，游走了…"); p.Say("seek_got", "抓到了！我很厲害吧？")
        p.Say("drag", "哇～我在飛！像英雄一樣！"); p.Say("throw", "我會飛——啊不會——")
        p.Say("shelf_in", "我回櫃子裡休息囉，掰掰～"); p.Say("shelf_in_d", "大家都回家了…我也回櫃子裡")
        p.Say("shelf_out", "漢頓登場！今天要讓你笑！"); p.Say("shelf_out_d", "出來了…天黑了耶，你怎麼還在？")
        p.Say("ball_go", "球！我用頭頂！", "看我的海豹頂球！", "來吧！"); p.Say("ball_go_d", "最後一顆喔…")
        p.Say("ball_catch", "頂到了！好看嗎？", "嘿咻！海豹式！", "我很厲害吧？"); p.Say("ball_catch_d", "頂回去…然後回家")
        p.Say("ball_end", "不玩了？下次我練好再頂給你看"); p.Say("ball_end_d", "不玩了…那就回家吧")
        p.Say("ball_far", "球游太遠了～")
        p.Say("back", "我回來了～"); p.Say("back_d", "我回來了…")
        p.Say("share_end", "分享完了？漢頓回來了！")
        p.Say("welcome", "你回來了！我一個人好寂寞喔 ♥"); p.Say("welcome_d", "你回來了…是要回家了嗎？")
        p.Say("rest", "已經 {n} 分鐘了，起來喝口可樂、伸伸鰭…啊，伸伸手 🥤"); p.Say("rest_d", "{n} 分鐘了…喝完可樂就回家吧，不要一個人待太晚")
        p.Say("night_on", "天黑了…大家都回家了，你也回家吧"); p.Say("night_off", "早安！今天也要『魚』快喔 ☀")
        p.Say("sleep", "我去泡泡裡睡一下…"); p.Say("sleep_d", "晚安…不要像我一樣熬夜喔")
        p.Say("jump", "咕嚕咕嚕～游過去！"); p.Say("nojump", "附近沒有可以游的地方耶")
        p.Say("errors", "交給我這個英雄！有 {n} 個錯誤！"); p.Say("errors_d", "{n} 個錯誤…明天再修，回家吧")
        p.Say("errors_ok", "錯誤都不見了！我…我有幫到忙嗎？"); p.Say("errors_ok_d", "都修好了…回家吧")
        p.Say("typing", "打好快！我的鰭都跟不上了", "好厲害！比我游泳還快！"); p.Say("typing_d", "打快一點，早點回家")
        p.Say("done", "{who} 做完了！我終於當上英雄了！"); p.Say("done_d", "{who} 做完了…你也回家吧")
        p.Say("wait", "{who} 在等你回答喔～"); p.Say("wait_d", "{who} 在等你…回完就回家")
        p.Say("ask", "{who} 有問題要問你！"); p.Say("ask_d", "{who} 在問你…回完就回家")
        p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，要不要去按一下？"); p.Say("stuck_tool_d", "{who} 停了 {n} 分鐘…按一下就回家")
        p.Say("stuck", "{who} 好像卡住了…{n} 分鐘了，英雄去看看？"); p.Say("stuck_d", "{who} 卡住 {n} 分鐘…看一下就回家")
        p.Say("unstuck", "{who} 動起來了！太好了～"); p.Say("unstuck_d", "{who} 動了…")
        p.Say("tag", "上版成功！我終於當上英雄了！"); p.Say("tag_dev", "測試機成功！英雄練習中！"); p.Say("tag_prod", "正式機！這次真的是英雄了！"); p.Say("tag_d", "上版成功…大家都回家了，你也回家吧")
        p.Say("late23", "好晚了…你不要像我一樣熬夜喔 🌙"); p.Say("late12", "吃飯了嗎？我吃海草沙拉"); p.Say("late15", "點心時間～要不要聽個笑話配茶？")
        p.Say("late_d", "天都黑了…大家都回家了喔"); p.Say("late_dd", "好晚了…回家吧，不要一個人待著")
        p.Say("g_late", "這麼晚還在？我陪你，你就不是一個人了 🌙"); p.Say("g_morning", "早安！今天也要『魚』快喔 ☀"); p.Say("g_noon", "午安～吃飯了嗎？")
        p.Say("g_evening", "晚上好～今天辛苦了"); p.Say("g_day", "漢頓登場！今天要讓你笑！"); p.Say("g_d", "天黑了…你怎麼還在？")
        p.Say("app_browser", "在逛網頁？有好笑的給我看！"); p.Say("app_code", "寫 code 呀，我幫你加油！"); p.Say("app_excel", "好多格子，像魚網一樣…")
        p.Say("app_ppt", "做簡報？放一個我的笑話吧！"); p.Say("app_word", "在寫文件～慢慢來"); p.Say("app_chat", "有人找你？是莎莉嗎？"); p.Say("app_files", "在找東西？我幫你一起找")
        p.Say("app_other", "這是什麼？我游過去看看")
        p.Say("app_code_d", "還在寫…回家吧"); p.Say("app_chat_d", "明天再回吧"); p.Say("app_office_d", "明天再做也可以的"); p.Say("app_other_d", "大家都回家了…")
        p.Say("s_birthday", "生日快樂！我準備了一個笑話當禮物 🎂", "生日快樂！今天你是主角！")
        p.Say("s_cny", "新年快樂！年年有『魚』🧧")
        p.Say("s_xmas", "聖誕快樂！🎄", "聖誕老人會不會送我一件披風？")
        p.Say("s_newyear", "新年快樂！今年也要『魚』快 ✨")
        p.Say("s_halloween", "不給糖就…講冷笑話給你聽 🎃")
        p.Say("s_friday", "星期五了！週末要『魚』快喔！", "快放假了～要不要一起去海邊？")
        p.Say("morning", "早安！漢頓報到，今天也要『魚』快！", "早安～今天我想了新笑話！")
        p.Say("goodnight", "大家都回家了……我也回櫃子裡，晚安", "晚安…明天也要來看我喔")
        p.Say("nag", "大家都回家了……你也回家吧，不要像我一樣一個人", "回家吧，有人在等你吧？", "晚上的海好安靜…回家吧")
        p.Say("react", "咦？", "怎麼了？", "咕嚕？")
        p.Shared()
        return p
    }

    // ================= 天線寶寶一櫃：丁丁、迪西、拉拉（同人像素）=================
    // 完全用小波核准過的母版（頭、臉、身體、腿、字元都一樣），只換顏色、換天線；丁丁多一列身體、一列腿（最高）。
    static func Taller(_ rows: [String], _ dup: Int, _ extra: Int) -> [String]
    {
        var l = rows
        var i = 0
        while i < extra { l.insert(rows[dup], at: dup); i += 1 }
        return l
    }

    static func TubbyBase(_ id: String, _ name: String, _ ant: [String], _ extraBody: Int, _ extraLeg: Int) -> Pal
    {
        let po = Po()
        let p = Pal()
        p.Id = id; p.Name = name; p.Tubby = true; p.BallKind = "tubby"; p.NightStyle = "sunset"; p.NightBubble = 2
        p.Halo = Color.White; p.HaloNight = C(0xFFC58F)
        var head = ant
        let ph = po.Art["HEAD"]
        var i = 4
        while i < ph.count { head.append(ph[i]); i += 1 }    // 小波的頭（去掉她的圓圈天線）
        p.Art["HEAD"] = head
        for f in ["SLEEPY", "HAPPY", "DIZZY", "SQUISH", "LEGS_SIT"] { p.Art[f] = po.Art[f] }
        // 「哎喲！」：眼睛擠成一條線、嘴巴張開
        p.Art["OUCH"] = [
            "kehrffffffffrRek",
            "kehrkkffffkkrRek",
            "kehrffffffffrRek",
            "kehrpffmmffprRek",
            ".kkhrffmmffrRkk."]
        for b in ["BODY", "ARMS_UP", "ARMS_HUG"] { p.Art[b] = Taller(po.Art[b], 3, extraBody) }
        for l in ["LEGS_A", "LEGS_B", "LEGS_RIDE"] { p.Art[l] = Taller(po.Art[l], 0, extraLeg) }
        // 道具：迪西的乳牛紋高帽、丁丁的魔法袋、拉拉的大橘球、吐司、嘟嘟糊
        p.Art["HAT"] = [
            "....kkkkkkkk....",
            "....kWWWWKKk....",
            "....kKKWWWKk....",
            "....kKWWWWWk....",
            "....kWWWKKWk....",
            "..kkkkkkkkkkkk..",
            "..kWWWKKWWWWWk..",
            "...kkkkkkkkkk..."]
        p.Art["HAT_HAND"] = [".kkkkkk.", ".kWKKWk.", ".kKWWWk.", ".kWWKKk.", "kkkkkkkk", "kWKWWKWk", ".kkkkkk."]
        p.Art["BAG"] = ["..kkkk..", ".k....k.", "kkkkkkkk", "kaWaaaAk", "kaaaaaAk", "kaaaaAAk", ".kAAAAk."]
        p.Art["BAG_OPEN"] = ["k......k", "kk....kk", "kAkkkkAk", "kaaaaaAk", "kaWaaaAk", "kaaaaAAk", ".kAAAAk."]
        p.Art["BALL"] = ["..kkkk..", ".kcYccck", "kcYccccC", "kccccccC", "kcccccCk", ".kcCCCk.", "..kkkk.."]
        p.Art["DUDU"] = ["..2.....", ".P2PPP..", "PPPPPPP.", "khhhhhk.", ".khhhk.."]
        p.Art["DUDU_CUP"] = ["PPPP", "kWWk", ".kk."]
        p.FaceRow = ant.count + 3; p.EyeRow = -1; p.KeepAntenna = true; p.AntRows = 4
        let total = head.count + p.Art["BODY"].count + p.Art["LEGS_A"].count
        p.TopRows = total - 16
        p.HeadTop = 16 - total + ant.count
        p.BodyTop = 16 - p.Art["LEGS_A"].count - p.Art["BODY"].count
        p.TummyRow = Double(p.BodyTop) + 2.5 + Double(extraBody) * 0.5
        p.HatRow = p.HeadTop + 1; p.HatCol = 0; p.ScarfRow = p.HeadTop + 8; p.GlassRow = p.HeadTop + 4
        p.BadgeRow = p.BodyTop + 4 + extraBody; p.BadgeCol = 5; p.SideRow = p.BodyTop + 1
        // 共用色：膚色、嘴、肚子螢幕、滑板車（借騎時用）、帽子黑、袋子紅、球橘、吸吸藍
        p.Col("e", 0xF4CDBE, 0xD3A79C); p.Col("f", 0xF6D2B0, 0xD9AE92); p.Col("F", 0xE8B892, 0xBF907A); p.Col("m", 0xB8323C, 0x8E2E40); p.Col("p", 0xF29A9A, 0xC97A84)
        p.Col("g", 0xC9CDD3, 0x8F8CA6); p.Col("G", 0x8E949C, 0x5F5C78); p.Col("w", 0xFFFFFF, 0xFFE4CC); p.Col("y", 0xFFD84A, 0xFFB45E)
        p.Col("s", 0x55C7BE, 0x3F8F95); p.Col("q", 0x2F8F88, 0x266A70); p.Col("o", 0x6B6F7A, 0x4E4A5E)
        p.Col("K", 0x222222, 0x1A1A1A); p.Col("a", 0xD8323A, 0xAB313F); p.Col("A", 0x9E1F27, 0x761C2F); p.Col("c", 0xF2852A, 0xE07541); p.Col("C", 0xC25E14, 0xAE522D)
        p.Col("v", 0x7FD3E0, 0x649AA9); p.Col("V", 0x4A9FB8, 0x2F6D8A); p.Col("O", 0x4E4A5E, 0x2E304E)
        return p
    }

    // 天線寶寶共用的台詞（每隻再蓋掉自己的）
    func TubbyLines(_ me: String)
    {
        Say("rest", "已經 {n} 分鐘了，起來動一動、喝口可樂 🥤", "{n} 分鐘了！可樂時間～咕嚕咕嚕 🥤"); Say("rest_d", "{n} 分鐘了…喝完可樂，太陽寶寶下山了，回家吧")
        Say("night_on", "太陽寶寶下山了…" + me + "說再見囉"); Say("night_off", "太陽寶寶起床了！Eh-oh! ☀")
        Say("wait", "{who} 在等你回答喔 👋"); Say("wait_d", "{who} 在等你…回完就回家喔")
        Say("ask", "{who} 有問題要問你喔 🙋"); Say("ask_d", "{who} 在問你問題…回完就回家")
        Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，要你按按看嗎？"); Say("stuck_tool_d", "{who} 停了 {n} 分鐘…按一下就回家")
        Say("stuck", "{who} 不動了…{n} 分鐘了耶，去看看？"); Say("stuck_d", "{who} 卡住 {n} 分鐘了…看完就說再見囉")
        Say("unstuck", "{who} 又動了！好棒棒 👏"); Say("unstuck_d", "{who} 動了…")
        Say("late23", "好晚了…" + me + "想睡覺覺 🌙"); Say("late12", "吃飯飯了沒？吐司要不要？"); Say("late15", "點心時間～嘟嘟糊！")
        Say("late_d", "太陽寶寶早就下山了喔"); Say("late_dd", "好晚好晚了…晚安，回家吧")
        Say("app_browser", "在看什麼？" + me + "也要看～"); Say("app_code", "寫 code 時間！" + me + "陪你"); Say("app_excel", "好多格子喔～")
        Say("app_ppt", "做簡報～要畫太陽寶寶嗎？"); Say("app_word", "寫字字～慢慢來"); Say("app_chat", "有人找你玩嗎？"); Say("app_files", "在找東西嗎？")
        Say("app_other", "Eh-oh! 這是什麼？")
        Say("app_code_d", "還在寫…太陽寶寶下山了啦"); Say("app_chat_d", "天黑了，明天再回嘛"); Say("app_office_d", "明天再做好不好～"); Say("app_other_d", "該說再見囉～")
        Say("s_newyear", "新年快樂！Eh-oh! ✨")
        Say("react", "Eh-oh?", "咦？", "怎麼了怎麼了？")
        Say("pat10", "今天第 {n} 次摸摸了！" + me + "好開心 ♥"); Say("pat10_d", "第 {n} 次了…摸完就回家喔")
        Say("levelup", "好感度 Lv{n}！" + me + "拿到「{u}」了 ♥"); Say("levelup_d", "Lv{n}…拿到「{u}」…明天再戴給你看")
        Say("missed", "你好久沒摸摸" + me + "了…🥺"); Say("missed_d", "好久沒摸摸了…明天要記得喔")
        Say("hover", "Eh-oh? 你在摸摸" + me + "嗎～")
        Say("share_end", "分享完了～Eh-oh!")
        Say("back", "Eh-oh! " + me + "回來了"); Say("back_d", me + "回來了…")
        Say("welcome", "Eh-oh! 你回來了！大抱抱！"); Say("welcome_d", "你回來了…是要回家了嗎？")
        Say("hugs_d", "大抱抱…然後回家睡覺覺", "晚安大抱抱 ♥", "抱完就說再見囉")
    }

    // ---------------- 丁丁（紫色、最高、倒三角天線、紅色魔法袋）----------------
    static func Tinky() -> Pal
    {
        let p = TubbyBase("tinky", "丁丁", [
            "....rrrrrrrr....",
            ".....r....r.....",
            "......r..r......",
            ".......rr.......",
            ".......rr......."], 1, 1)
        p.Move = "bag"; p.Accent = C(0x7A52B0); p.Panel = C(0xE6DCF5)
        p.Col("k", 0x2E1A3A, 0x1E1028); p.Col("r", 0x8A5CC2, 0x6A4A9E); p.Col("R", 0x5E3A92, 0x45296E); p.Col("h", 0xA884DA, 0x8A6CB8)
        p.Speed = 30; p.AntThrough = true
        p.TubbyLines("丁丁")
        p.Say("talk", "Eh-oh!", "丁丁的魔法袋裡有什麼呢？", "大抱抱時間到了沒？", "丁丁想跳舞～", "今天天氣好好喔 ☀", "要喝可樂嗎？丁丁袋子裡有 🥤", "慢慢走，慢慢走～")
        p.Say("talk_d", "太陽寶寶下山了，丁丁說再見囉", "丁丁抱著袋袋想睡覺…你也回家好不好", "天黑黑了，明天再玩", "晚安晚安～該回家囉")
        p.Say("save", "存好了！放進魔法袋 👜", "存起來了～好棒棒！", "Eh-oh! 存檔成功", "丁丁幫你收好囉")
        p.Save_d()
        p.Say("pats", "嘻嘻，好舒服", "丁丁喜歡你 ♥", "摸摸頭～你也辛苦了", "Eh-oh! 再摸一下", "有丁丁陪你喔", "慢慢來，丁丁等你", "大大的丁丁給你靠 ♥")
        p.Say("pats_d", "嗯…丁丁想睡覺覺了", "摸摸…然後我們回家好不好", "太陽寶寶下山了，你也該休息囉")
        p.Say("pats_hi", "丁丁最最最喜歡你了", "我們是好朋友！", "能遇到你真好 ♥", "每天都要一起跳舞喔")
        p.Say("hugs", "大抱抱！", "丁丁的大大抱抱 ♥", "Eh-oh! 大抱抱！", "(つ´ω`)つ 大抱抱")
        p.Say("knock", "叩叩！Eh-oh! 👀", "丁丁可以出去玩嗎？", "肚肚貼玻璃～嘿嘿", "魔法袋敲敲～叩叩")
        p.Say("knock_d", "叩叩…太陽寶寶下山了喔", "該說再見囉，回家吧～", "丁丁看到你還在加班…")
        p.Say("newwin", "Eh-oh!", "Eh-oh! 新視窗！", "丁丁慢慢走過去看～")
        p.Say("newwin_d", "Eh-oh…又開新的了？明天再看嘛", "天黑黑了，不要再開了啦")
        p.Say("hi", "Eh-oh! 我是丁丁 👋"); p.Say("hi_d", "Eh-oh…太陽寶寶下山了耶")
        p.Say("wake", "嗯…Eh-oh? 是你呀 ♥"); p.Say("wake_d", "嗯…丁丁在睡覺覺…你也去睡嘛")
        p.Say("dizzy", "轉圈圈～頭暈暈 @@"); p.Say("dizzy_d", "暈暈…丁丁要睡覺覺了…")
        p.Say("dizzy_ok", "好了！再來一次！"); p.Say("dizzy_ok_d", "好了…該回家囉")
        p.Say("tickle", "哎喲！", "哎喲！（又跌倒了）", "哎喲～嘻嘻嘻"); p.Say("tickle_d", "哎喲…最後一次喔")
        p.Say("seek", "咦？那是什麼？"); p.Say("seek_lost", "跑掉了…"); p.Say("seek_got", "抓到滑鼠了！放進魔法袋～")
        p.Say("drag", "哇～丁丁好重喔！"); p.Say("throw", "哎——喲——")
        p.Say("shelf_in", "丁丁回家家囉，掰掰 👋"); p.Say("shelf_in_d", "太陽寶寶下山了，丁丁說再見")
        p.Say("shelf_out", "Eh-oh! 丁丁出來玩囉！"); p.Say("shelf_out_d", "Eh-oh…天黑黑了耶，你怎麼還在？")
        p.Say("ball_go", "球！丁丁來了！", "魔法袋準備好了！", "慢慢來～我接我接"); p.Say("ball_go_d", "最後一球喔…")
        p.Say("ball_catch", "收進魔法袋！", "接到了！在袋子裡～", "嘿嘿，袋子好厲害"); p.Say("ball_catch_d", "收好了…還你，該回家囉")
        p.Say("ball_end", "不玩了嗎？下次再來一次！"); p.Say("ball_end_d", "不玩了…那我們回家吧")
        p.Say("ball_far", "球球跑好遠喔～丁丁走不快")
        p.Say("sleep", "抱著袋袋睡覺覺…晚安"); p.Say("sleep_d", "晚安晚安…你也去睡覺覺")
        p.Say("jump", "嘿咻～"); p.Say("nojump", "附近沒有可以跳的地方耶")
        p.Say("errors", "哎喲！有 {n} 個錯誤"); p.Say("errors_d", "{n} 個錯誤…明天再修啦，回家")
        p.Say("errors_ok", "錯誤都不見了！大抱抱！"); p.Say("errors_ok_d", "都修好了！那我們回家吧")
        p.Say("typing", "打好快喔！丁丁跳舞給你看～", "加油加油！", "手指在跳舞耶 ♪"); p.Say("typing_d", "打好快…是想快點回家吧")
        p.Say("done", "Eh-oh! {who} 做完了！丁丁跳舞！"); p.Say("done_d", "{who} 做完了～太陽寶寶下山了，回家吧")
        p.Say("tag", "上版成功！魔法袋變出星星了 ✨"); p.Say("tag_dev", "測試機成功！丁丁跳舞～"); p.Say("tag_prod", "正式機成功！大抱抱 🎉"); p.Say("tag_d", "上完了…丁丁說再見，回家吧")
        p.Say("g_late", "這麼晚了…丁丁陪你一下下 🌙"); p.Say("g_morning", "Eh-oh! 早安！丁丁來了 ☀"); p.Say("g_noon", "Eh-oh! 午安～吃吐司了沒？")
        p.Say("g_evening", "Eh-oh～晚上了，辛苦了"); p.Say("g_day", "Eh-oh! 丁丁來玩囉！"); p.Say("g_d", "太陽寶寶下山了…你怎麼還在？")
        p.Say("s_birthday", "生日快樂！丁丁從魔法袋變出蛋糕 🎂", "今天你最大！大抱抱！")
        p.Say("s_cny", "新年快樂！恭喜恭喜 🧧", "紅包…放進魔法袋！")
        p.Say("s_xmas", "聖誕快樂！🎄", "丁丁的魔法袋要裝禮物～")
        p.Say("s_halloween", "不給糖就搗蛋！🎃", "丁丁扮成…大茄子！")
        p.Say("s_friday", "星期五了！丁丁跳舞！", "快放假了～大抱抱！")
        p.Say("morning", "丁丁！", "丁丁！Eh-oh!")
        p.Say("goodnight", "丁丁說再見！👋", "晚安晚安～大抱抱")
        p.Say("nag", "太陽寶寶下山了，該說再見囉", "回家家囉～", "丁丁想睡覺覺了…")
        p.Shared()
        return p
    }

    // ---------------- 迪西（綠色、直直的天線、黑白乳牛紋高帽、有點酷）----------------
    static func Dipsy() -> Pal
    {
        let p = TubbyBase("dipsy", "迪西", [
            ".......rr.......",
            ".......rr.......",
            ".......rr.......",
            ".......rr.......",
            ".......rr......."], 0, 0)
        p.Move = "groove"; p.Accent = C(0x4F8A27); p.Panel = C(0xE0F2D2)
        p.Col("k", 0x22301A, 0x141E10); p.Col("r", 0x7DC242, 0x66984A); p.Col("R", 0x4F8A27, 0x3E6A2E); p.Col("h", 0xA2D86C, 0x88B266)
        p.Col("f", 0xD9A77C, 0xBC8A68); p.Col("F", 0xC08D63, 0xA27254); p.Col("e", 0xE2B08E, 0xC29076); p.Col("p", 0xE28A78, 0xB8707A)   // 迪西的臉比較深
        p.Speed = 60
        p.TopRows = 6 - p.HeadTop   // 算到帽子頂（頭頂外框上面 6 列）
        p.TubbyLines("迪西")
        p.Say("talk", "Eh-oh.", "這頂帽子是我的。", "嘿～（扶帽子）", "酷。", "跳舞嗎？我很會。", "要喝可樂嗎？冰的比較酷 🥤", "帽子不能借喔。")
        p.Say("talk_d", "太陽寶寶下山了…帽子拉低，睡覺", "迪西說再見囉…你也回家吧", "天黑了，酷的人都回家了", "晚安。帽子我戴著睡。")
        p.Say("save", "存好了。酷。", "存檔成功，嘿～", "Eh-oh. 存好了", "存了，帥。")
        p.Save_d()
        p.Say("pats", "嘿嘿…別碰帽子就好", "酷。再一下。", "迪西也喜歡你啦", "摸摸頭…欸，是摸帽子", "嘿～你很酷", "有迪西在，不用怕")
        p.Say("pats_d", "嗯…迪西想睡了", "摸完就回家吧", "太陽寶寶下山了，你也該休息")
        p.Say("pats_hi", "你是最酷的", "迪西最喜歡你了（小聲）", "我們是好朋友。", "帽子…可以給你摸一下")
        p.Say("hugs", "大抱抱。", "大抱抱！（帽子扶好）", "Eh-oh! 大抱抱", "(つ´ω`)つ 酷酷的抱抱")
        p.Say("knock", "叩叩。Eh-oh. 👀", "嘿～螢幕外面的你", "迪西可以出去跳舞嗎？", "（帽子敲玻璃）叩叩")
        p.Say("knock_d", "叩叩…太陽寶寶下山了", "該說再見了，回家吧", "還在加班？不酷。")
        p.Say("newwin", "Eh-oh.", "嘿～新視窗", "迪西去看看，酷。")
        p.Say("newwin_d", "又開新的？明天再看", "天黑了，關掉吧")
        p.Say("hi", "Eh-oh. 我是迪西 🎩"); p.Say("hi_d", "Eh-oh…太陽寶寶下山了")
        p.Say("wake", "嗯…（推帽子）是你啊"); p.Say("wake_d", "嗯…迪西在睡覺…你也去睡")
        p.Say("dizzy", "頭暈了…帽子還在吧？@@"); p.Say("dizzy_d", "暈…睡覺…")
        p.Say("dizzy_ok", "好了。帽子還在。酷。"); p.Say("dizzy_ok_d", "好了…該回家了")
        p.Say("tickle", "嘿～嘿～（跳起來）", "帽子不能摸啦！", "嘻…好啦好啦"); p.Say("tickle_d", "嘿…最後一次")
        p.Say("seek", "嗯？那是什麼？"); p.Say("seek_lost", "跑了…不酷"); p.Say("seek_got", "抓到滑鼠了。大抱抱。")
        p.Say("drag", "欸欸，帽子要掉了！"); p.Say("throw", "嘿——（扶帽子）")
        p.Say("shelf_in", "迪西回去了，掰。 👋"); p.Say("shelf_in_d", "太陽寶寶下山了，迪西說再見")
        p.Say("shelf_out", "Eh-oh. 迪西出來了。"); p.Say("shelf_out_d", "Eh-oh…天黑了，你怎麼還在？")
        p.Say("ball_go", "球！用帽子頂！", "看我的！", "嘿～來了"); p.Say("ball_go_d", "最後一球。")
        p.Say("ball_catch", "帽子頂！", "頂回去～酷。", "帽子是最好的球拍"); p.Say("ball_catch_d", "頂回去…然後回家")
        p.Say("ball_end", "不玩了？下次再頂給你看"); p.Say("ball_end_d", "不玩了…回家吧")
        p.Say("ball_far", "球跑太遠了，帽子頂不到")
        p.Say("sleep", "帽子拉低…晚安"); p.Say("sleep_d", "晚安…你也去睡")
        p.Say("jump", "嘿！"); p.Say("nojump", "附近沒有可以跳的地方")
        p.Say("errors", "有 {n} 個錯誤…不看不看（拉帽子）"); p.Say("errors_d", "{n} 個錯誤…明天再修，回家")
        p.Say("errors_ok", "錯誤都清光了。酷。"); p.Say("errors_ok_d", "修好了…那就回家吧")
        p.Say("typing", "打好快！迪西跳舞～嘿～", "節奏不錯喔", "嘿～嘿～手指在跳舞"); p.Say("typing_d", "打快一點，早點回家")
        p.Say("done", "{who} 做完了。酷。"); p.Say("done_d", "{who} 做完了～回家吧")
        p.Say("tag", "上版成功！帽子丟起來 🎩"); p.Say("tag_dev", "測試機成功。嘿～"); p.Say("tag_prod", "正式機成功！酷斃了 🎉"); p.Say("tag_d", "上完了…迪西說再見，回家吧")
        p.Say("g_late", "這麼晚…迪西陪你一下 🌙"); p.Say("g_morning", "Eh-oh. 早安。帽子戴好了 ☀"); p.Say("g_noon", "Eh-oh. 午安，吃了沒？")
        p.Say("g_evening", "晚上了，辛苦了。"); p.Say("g_day", "Eh-oh. 迪西來了，酷。"); p.Say("g_d", "太陽寶寶下山了…你怎麼還在？")
        p.Say("s_birthday", "生日快樂！迪西跳舞給你看 🎂", "今天你最酷！")
        p.Say("s_cny", "新年快樂 🧧", "紅包…放帽子裡。")
        p.Say("s_xmas", "聖誕快樂 🎄", "聖誕帽？不用，我有帽子了。")
        p.Say("s_halloween", "不給糖就搗蛋 🎃", "我扮成…戴帽子的迪西。")
        p.Say("s_friday", "星期五了。跳舞吧。", "快放假了～嘿～")
        p.Say("morning", "迪西！", "迪西！Eh-oh.")
        p.Say("goodnight", "迪西說再見！👋", "晚安。帽子我戴著睡。")
        p.Say("nag", "太陽寶寶下山了，該說再見了", "回家吧。", "迪西想睡了…")
        p.Say("react", "嗯？", "Eh-oh?", "（扶帽子）怎麼了？")
        p.Shared()
        return p
    }

    // ---------------- 拉拉（黃色、捲捲天線、大橘球、愛唱歌）----------------
    static func LaaLaa() -> Pal
    {
        let p = TubbyBase("laalaa", "拉拉", [
            "......rrr.......",
            ".....r...r......",
            ".......r.r......",
            "........rr......",
            ".......rr......."], 0, 0)
        p.Move = "skip"; p.Accent = C(0xD9A116); p.Panel = C(0xFFF4C8)
        p.Col("k", 0x3E2A10, 0x2A1A0C); p.Col("r", 0xF7D23A, 0xD9A84A); p.Col("R", 0xC9A116, 0xA27A2C); p.Col("h", 0xFFE67A, 0xE8C46E)
        p.Speed = 80
        p.TubbyLines("拉拉")
        p.Say("talk", "啦啦啦～", "Eh-oh!", "拉拉的球圓圓的～", "我們來唱歌！", "今天天氣好好喔 ☀", "要喝可樂嗎？啦～ 🥤", "轉圈圈～轉圈圈～")
        p.Say("talk_d", "太陽寶寶下山了…啦…", "拉拉抱著球想睡覺…你也回家好不好", "天黑黑了，明天再唱", "晚安晚安～該回家囉")
        p.Save_d()
        p.Say("save", "存好了！啦啦啦～", "存起來了～好棒棒！", "Eh-oh! 存檔成功", "拉拉幫你收好囉 ♪")
        p.Say("pats", "嘻嘻，好舒服～", "拉拉喜歡你 ♥", "啦啦～再摸一下", "你好棒棒！", "有拉拉陪你喔 ♪", "摸摸頭～你也辛苦了")
        p.Say("pats_d", "嗯…拉拉想睡覺覺了", "摸摸…然後回家好不好", "太陽寶寶下山了，你也該休息囉")
        p.Say("pats_hi", "拉拉最最最喜歡你了 ♪", "我們是好朋友！", "能遇到你真好 ♥", "每天都要一起唱歌喔")
        p.Say("hugs", "大抱抱！", "啦啦～大抱抱 ♥", "Eh-oh! 大抱抱！", "(つ´ω`)つ 大抱抱")
        p.Say("knock", "叩叩！Eh-oh! 👀", "啦啦啦～有人在嗎？", "拉拉可以出去玩球嗎？", "肚肚貼玻璃～嘻嘻")
        p.Say("knock_d", "叩叩…太陽寶寶下山了喔", "該說再見囉，回家吧～", "拉拉看到你還在加班…")
        p.Say("newwin", "Eh-oh!", "啦啦～新視窗！", "拉拉跳過去看～")
        p.Say("newwin_d", "Eh-oh…又開新的了？明天再看嘛", "天黑黑了，不要再開了啦")
        p.Say("hi", "Eh-oh! 我是拉拉 👋"); p.Say("hi_d", "Eh-oh…太陽寶寶下山了耶")
        p.Say("wake", "嗯…啦？是你呀 ♥"); p.Say("wake_d", "嗯…拉拉在睡覺覺…你也去睡嘛")
        p.Say("dizzy", "轉太多圈了～頭暈暈 @@"); p.Say("dizzy_d", "暈暈…拉拉要睡覺覺了…")
        p.Say("dizzy_ok", "好了！再來一次！"); p.Say("dizzy_ok_d", "好了…該回家囉")
        p.Say("tickle", "啦啦啦～轉圈圈！", "再來一次！再來一次！", "嘻嘻嘻～好癢"); p.Say("tickle_d", "嘻…最後一次喔")
        p.Say("seek", "咦？那是什麼？"); p.Say("seek_lost", "跑掉了…"); p.Say("seek_got", "抓到滑鼠了！大抱抱！")
        p.Say("drag", "哇～飛高高！啦～"); p.Say("throw", "啦～～～")
        p.Say("shelf_in", "拉拉回家家囉，掰掰 👋"); p.Say("shelf_in_d", "太陽寶寶下山了，拉拉說再見")
        p.Say("shelf_out", "Eh-oh! 拉拉出來玩囉！"); p.Say("shelf_out_d", "Eh-oh…天黑黑了耶，你怎麼還在？")
        p.Say("ball_go", "球！拉拉來踢！", "啦～我來了！", "看我的腳！"); p.Say("ball_go_d", "最後一球喔…")
        p.Say("ball_catch", "踢回去！啦～", "好球！", "嘿嘿，拉拉很會踢吧"); p.Say("ball_catch_d", "踢回去…該回家囉")
        p.Say("ball_end", "不玩了嗎？下次再來一次！"); p.Say("ball_end_d", "不玩了…那我們回家吧")
        p.Say("ball_far", "球球跑好遠喔～")
        p.Say("sleep", "抱著球球睡覺覺…晚安"); p.Say("sleep_d", "晚安晚安…你也去睡覺覺")
        p.Say("jump", "啦～跳！"); p.Say("nojump", "附近沒有可以跳的地方耶")
        p.Say("errors", "哎呀…有 {n} 個錯誤，拉拉躲起來"); p.Say("errors_d", "{n} 個錯誤…明天再修啦，回家")
        p.Say("errors_ok", "錯誤都不見了！啦啦啦～"); p.Say("errors_ok_d", "都修好了！那我們回家吧")
        p.Say("typing", "打好快喔！啦啦啦～", "加油加油！拉拉唱歌給你聽 ♪", "手指在跳舞耶 ♪"); p.Say("typing_d", "打好快…是想快點回家吧")
        p.Say("done", "啦啦啦～{who} 做完了！"); p.Say("done_d", "{who} 做完了～太陽寶寶下山了，回家吧")
        p.Say("tag", "上版成功！啦啦啦～ 🎉"); p.Say("tag_dev", "測試機成功！轉圈圈～"); p.Say("tag_prod", "正式機成功！再來一次！🎉"); p.Say("tag_d", "上完了…拉拉說再見，回家吧")
        p.Say("g_late", "這麼晚了…拉拉輕輕唱歌陪你 🌙"); p.Say("g_morning", "Eh-oh! 早安！啦啦啦～ ☀"); p.Say("g_noon", "Eh-oh! 午安～吃飯飯了沒？")
        p.Say("g_evening", "Eh-oh～晚上了，辛苦了"); p.Say("g_day", "Eh-oh! 拉拉來玩球囉！"); p.Say("g_d", "太陽寶寶下山了…你怎麼還在？")
        p.Say("s_birthday", "生日快樂！拉拉唱歌給你聽 🎂 啦啦～", "今天你最大！大抱抱！")
        p.Say("s_cny", "新年快樂！恭喜恭喜 🧧", "紅包…拉拉可以拿嗎？")
        p.Say("s_xmas", "聖誕快樂！🎄 叮叮噹～啦啦啦～", "拉拉想要新球球")
        p.Say("s_halloween", "不給糖就搗蛋！🎃", "拉拉扮成…南瓜球！")
        p.Say("s_friday", "星期五了！唱歌跳舞！", "快放假了～啦啦啦！")
        p.Say("morning", "拉拉！", "拉拉！Eh-oh!")
        p.Say("goodnight", "拉拉說再見！👋", "晚安晚安～啦～")
        p.Say("nag", "太陽寶寶下山了，該說再見囉", "回家家囉～啦～", "拉拉想睡覺覺了…")
        p.Shared()
        return p
    }

    func Save_d() { Say("save_d", "存好了…那我們回家好不好", "存好了，太陽寶寶也下山囉", "收好了～該說再見囉") }
}
