// 經典一櫃（Spidey、小波、史迪仔、人魚漢頓）與天線寶寶一櫃（丁丁、迪西、拉拉）：同人像素，個人版才有。
// 對應 DeskPals.Fan.cs；公開版（tools/variant.py public、mac/assemble.py --public）不帶這個檔。
import Foundation

//@@IN Pet
    var caped = false
    var headers = 0
    // ---- 天線寶寶 ----
    var hatLost = false                   // 迪西：帽子借給丁丁戴了（串場）
    var WearHat = false            // 戴著迪西的帽子（串場）
    var ballLost = false                  // 拉拉：球不見了（滾進丁丁的魔法袋、踢給小波）
    var RidingPo = false           // 丁丁騎小波的滑板車（串場）
    var HoldToast = false          // 吐司時間：手上拿著吐司（串場）
    var lentScooter = false               // 小波：滑板車借出去了（串場結束一定還回來）
    var bagItem = ""            // 魔法袋這次拿出來的東西
    var juggles = 0
    var lastArmsUp = false
    var bagQuiet = false
//@@END

// ================= 角色資料（從 20_pal.swift 搬來）=================
extension Pal {
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

// ================= 各角色專屬的動作（從 31_pet_b.swift、32_pet_draw.swift 搬來）=================
extension Pet {
    // ================= Spidey：噴絲 =================
    func FindAnchor(_ vertical: Bool) -> [Double]? {
        let cx = Cx, hy = y
        let wa = w.WA(cx, y + Double(SH) / 2.0)
        let opts = List<[Double]>()
        for wi in w.Cands.Values {
            if Double(wi.B) > hy - 70 * k || wi.B < wa.Top + 10 { continue }
            var px: Double
            if vertical { if cx < Double(wi.L + 6) || cx > Double(wi.R - 6) { continue }; px = cx }
            else {
                px = Pet.Clamp(cx + Double(dir) * R(60, 220) * k, Double(wi.L + 6), Double(wi.R - 6))
                if Math.Abs(px - cx) > 300 * k { continue }
            }
            if !w.PointVisible(wi, px, Double(wi.B - 2)) { continue }
            opts.Add([px, Double(wi.B)])
        }
        if opts.Count > 0 && rnd.NextDouble() < 0.85 { return opts[rnd.Next(opts.Count)] }
        let dist = hy - Double(wa.Top)
        if dist < 90 * k { return nil }
        if vertical { return [cx, Double(wa.Top)] }
        return [Pet.Clamp(cx + Double(dir) * Math.Min(dist * 0.6, 260 * k), Double(wa.Left + 10), Double(wa.Right - 10)), Double(wa.Top)]
    }

    @discardableResult
    func ShootTo(_ mode: String) -> Bool {
        if !Grounded() { return false }
        guard let a = FindAnchor(mode == "hang") else { return false }
        ax = a[0]; ay = a[1]
        dir = ax >= Cx ? 1 : -1
        nextAct = mode; shootT = 0
        SetState("shoot", 1)
        Say("Thwip!", 0.8)
        return true
    }

    func Shoot(_ dt: Double) {
        shootT += dt
        if shootT < 0.18 { return }
        supH = IntPtr.Zero
        if nextAct == "swing" {
            let hx = Cx, hy = y
            let swa = w.WA(hx, y + Double(SH) / 2.0)
            let maxL = Double(swa.Bottom - SH) - ay - 24 * k
            let ddx = hx - ax, ddy = hy - ay
            ropeL = Math.Min(Math.Sqrt(ddx * ddx + ddy * ddy), maxL)
            if ropeL < 36 * k { Jump(Double(dir) * 60 * k, -300 * k); return }
            th = asin(Pet.Clamp((hx - ax) / ropeL, -0.95, 0.95))
            if Math.Abs(th) < 0.5 { th = 0.9 * (hx < ax ? -1.0 : 1.0) }
            om = 0
            reelT = 0.18; reelX = x; reelY = y
            SetState("swing", 3.2)
        }
        else if nextAct == "hang" {
            let wa = w.WA(ax, y + Double(SH) / 2.0)
            targetL = Math.Max(10.0, Math.Min(Double(wa.Height) * R(0.15, 0.4), Double(wa.Bottom - SH - 10) - ay))
            hangPhase = 0; ropeL = 0
            SetState("hang", 99)
        }
        else { SetState("zip", 3) }
    }

    func Swing(_ dt: Double, _ wa: Rectangle) {
        let acc: Double = (900 * k / ropeL) * Math.Sin(th) * dt
        om = (om - acc) * 0.997
        th += om * dt
        let hx = ax + ropeL * Math.Sin(th), hy = ay + ropeL * Math.Cos(th), floorY = Double(wa.Bottom - SH)
        x = hx - Double(SW) / 2.0; y = Math.Min(hy, floorY)
        if reelT > 0 {
            let f = Pet.Ease(1 - reelT / 0.18)
            x = reelX + (x - reelX) * f; y = reelY + (y - reelY) * f
            reelT -= dt
        }
        let vxs = ropeL * Math.Cos(th) * om
        if Math.Abs(vxs) > 5 { dir = vxs > 0 ? 1 : -1 }
        if t < 0 || hy > floorY + 1 { Jump(vxs * 0.8, -ropeL * Math.Sin(th) * om * 0.8); if rnd.NextDouble() < 0.4 { Say("呀呼～", 0.9) } }
    }

    func Hang(_ dt: Double, _ wa: Rectangle) {
        x = ax - Double(SW) / 2.0
        if hangPhase == 0 {
            y -= 700 * k * dt
            if y <= ay + 4 { y = ay + 4; hangPhase = 1; ropeL = 0; t = 5; Say("倒吊看世界～", 2) }
            return
        }
        ropeL = Math.Min(targetL, ropeL + 160 * k * dt)
        y = ay + 4 + ropeL + Math.Sin(anim * 2.4) * 4 * k
        if t < 0 { Jump(0, 0) }
    }

    func Zip(_ dt: Double) {
        let tx = ax - Double(SW) / 2.0, ty = ay - Double(SH)
        let dx = tx - x, dy = ty - y, d = Math.Sqrt(dx * dx + dy * dy), sp = 1100 * k * dt
        if dx != 0 { dir = dx > 0 ? 1 : -1 }
        if d > sp && t > 0 { x += dx / d * sp; y += dy / d * sp; return }
        x = tx; y = ty
        for p in w.Plats {
            if p.H == zipH && ax >= Double(p.Left - 2) && ax <= Double(p.Right + 2) && Math.Abs(Double(p.Top) - ay) < 3 {
                SetSupport(p)
                SetState("idle", 1.6)
                w.AddWeb(zipH, zipRight)
                Say("黏好了！", 1.4)
                return
            }
        }
        Jump(0, 0)
    }

    func Peek(_ dt: Double, _ wa: Rectangle) {
        let prev = gt
        gt += dt
        dir = -wallSide
        let hideXp = wallSide < 0 ? Double(wa.Left) - Double(SW) * 0.55 : Double(wa.Right) - Double(SW) * 0.45
        let inX = Double(wallSide < 0 ? wa.Left : wa.Right - SW)
        x = gt < 0.4 ? inX + (hideXp - inX) * Pet.Ease(gt / 0.4) : hideXp
        if prev <= 0.4 && gt > 0.4 { Say("躲貓貓～", 1.2) }
        if t < 0 { x = inX; Say("找到我了嗎？嘿嘿", 1.6); climbDir = 1; SetState("climb", 99) }
    }

    func ZipToWindow(_ win: WinInfo, _ text: String) -> Bool {
        if !Grounded() || sleepMode || state == "hug" || fetching { return false }
        var tx = 0.0, top = 0.0
        if !PlatEnd(win, &tx, &top) { return false }
        if supH == win.H { Say(text, 2); return true }
        ax = tx; ay = top; zipH = win.H; zipRight = tx > Double(win.L + win.R) / 2.0
        dir = ax >= Cx ? 1 : -1
        nextAct = "zip"; shootT = 0
        SetState("shoot", 1)
        Say(text, 2)
        return true
    }

    func StartClimb(_ side: Int) {
        wallSide = side; climbDir = -1; dir = side; goClimb = false; supH = IntPtr.Zero
        SetState("climb", R(2, 7))
    }

    func Climb(_ dt: Double, _ wa: Rectangle) {
        x = Double(wallSide < 0 ? wa.Left : wa.Right - SW)
        if climbDir < 0 {
            y -= 50 * k * dt
            if y <= Double(wa.Top + 4) || t < 0 {
                y = Math.Max(y, Double(wa.Top + 4))
                if InScene { t = 1; return }
                let cr = rnd.NextDouble()
                if cr < 0.45 { Jump(Double(-wallSide) * R(200, 350) * k, -R(150, 300) * k); Say("喝！", 0.8) }
                else if cr < 0.75 { gt = 0; SetState("peek", R(2.5, 4)) }
                else { climbDir = 1 }
            }
        }
        else {
            y += 70 * k * dt
            if y >= Double(wa.Bottom - SH) { y = Double(wa.Bottom - SH); dir = -wallSide; SetState("walk", R(2, 5)) }
        }
    }

    func SpinWeb(_ h: IntPtr, _ right: Bool) {
        if !w.Cands.ContainsKey(h) { return }
        let wi: WinInfo = w.Cands[h]
        let edge = right ? supR : supL, corner = right ? wi.R : wi.L
        if Math.Abs(edge - corner) > 12 { return }
        w.AddWeb(h, right)
        SetState("idle", 1.4)
        Say("在這裡織個網～", 1.6)
    }

    // 多人接球：用絲把球黏住再踢回去
    func WebCatch() {
        w.HoldBall(self)
        ax = w.Bx; ay = w.By; shootT = 1
        dir = ax >= Cx ? 1 : -1
        SetState("webcatch", 0.6)
        Say(Pick(["Thwip! 接住了！", "用絲接球！", "好球！Thwip!"]), 1.4)
        w.Umpire("好球！")
    }

    // 串場：把小波甩上去
    func SlingAt(_ o: Pet) {
        ax = o.Cx; ay = o.y + 6 * k; shootT = 1; dir = ax >= Cx ? 1 : -1
        SetState("sling", 1.0)
    }

    // ================= 小波：滑板車、棒球 =================
    func OnScooter() -> Bool {
        if !Is("po") || scooterLost { return false }
        if state == "fling" { return !rolling }
        if state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto" { return true }
        if (state == "air" && !rolling) || state == "stowfly" { return true }
        return state == "idle" && t > 0 && (anim % 7) > 3.5
    }

    func StartBat(_ hitBall: Bool) {
        batT = 0; batHit = !hitBall
        SetState("bat", 1.1)
    }

    func Bat(_ dt: Double) {
        let prev = batT
        batT += dt
        if !batHit && prev < 0.22 && batT >= 0.22 && w.Holder === self {
            batHit = true
            let homer = rnd.NextDouble() < 0.45
            let bvx: Double = Double(dir) * (homer ? R(1300, 1700) : R(650, 950)) * k
            let bvy: Double = -(homer ? R(950, 1200) : R(450, 650)) * k
            w.ReleaseBall(Cx + Double(dir) * 14 * k, y + 8 * k, bvx, bvy)
            w.CatchCd = 1.2
            Burst(8)
            if homer {
                Say("全壘打！", 2.2)
                w.Fireworks(w.WA(Cx, y), 3, CInt(Cx + Double(dir) * 260 * k))
                w.Umpire("全壘打！")
                AddXp(1)
            }
            else { Say(Pick(["安打！", "打到了！再來一次！"]), 1.6); w.Umpire("好球！") }
        }
        if t < 0 { SetState("idle", 1) }
    }

    func PoBall() {
        let group = w.OutCount() > 1
        w.HoldBall(self)
        if rnd.NextDouble() < (group ? 0.6 : 0.3) { StartBat(true); Say("看我的！", 0.8); return }
        SetState("catch", 0.6)
        Say(L("ball_catch"), 1.8)
        w.Umpire("好球！")
    }

    // 全壘打慶祝（Codex／Claude 做完、上版）
    func HomeRun(_ line: String, _ lead: Bool) {
        if Grounded() { poseKind = "homerun"; SetState("pose", 3.4) }
        if lead { w.Fireworks(w.WA(Cx, y), 6, CInt(Cx)) }
        Say(line, 4); Burst(12)
    }

    // ================= 史迪仔：爬牆、天花板、咬球 =================
    func StartWallUp(_ side: Int) {
        wallSide = side; climbDir = -1; dir = side; goClimb = false; supH = IntPtr.Zero; crawlH = IntPtr.Zero
        SetState("wall", 99)
    }

    func StartWallDown(_ wi: WinInfo, _ right: Bool) {
        crawlH = wi.H; wallSide = right ? -1 : 1; climbDir = 1; goClimb = false; supH = IntPtr.Zero
        x = Double(right ? wi.R : wi.L - SW)
        ceilY = Double(wi.B); ceilL = Double(wi.L); ceilR = Double(wi.R - SW)
        SetState("wall", 99)
        Say("ih-ih! 爬下去～", 1.2)
    }

    func Wall(_ dt: Double, _ wa: Rectangle) {
        if crawlH == IntPtr.Zero {
            // 螢幕邊：往上爬到頂，然後倒掛在天花板上走
            x = Double(wallSide < 0 ? wa.Left : wa.Right - SW)
            y -= 130 * k * dt
            if y <= Double(wa.Top + 2) {
                y = Double(wa.Top); ceilY = Double(wa.Top); ceilL = Double(wa.Left); ceilR = Double(wa.Right - SW)
                dir = -wallSide; SetState("ceil", R(1.5, 3.5)); Say("倒立走路！嘻嘻嘻", 1.4)
            }
            return
        }
        // 視窗側邊：往下爬到視窗底，然後倒掛在視窗底下走
        var r = W.RECT()
        if !W.IsWindowVisible(crawlH) || !W.Rect(crawlH, &r) { Jump(0, 0); rolling = true; return }
        x = Double(wallSide < 0 ? r.R : r.L - SW)
        ceilY = Double(r.B); ceilL = Double(r.L); ceilR = Double(r.R - SW)
        y += 120 * k * dt
        if y >= ceilY - Double(SH) * 0.3 {
            y = ceilY; x = wallSide < 0 ? ceilR : ceilL
            dir = wallSide < 0 ? -1 : 1; SetState("ceil", R(1.5, 3))
        }
    }

    func Ceil(_ dt: Double) {
        if crawlH != IntPtr.Zero {
            var r = W.RECT()
            if !W.IsWindowVisible(crawlH) || !W.Rect(crawlH, &r) { Jump(0, 0); rolling = true; return }
            ceilY = Double(r.B); ceilL = Double(r.L); ceilR = Double(r.R - SW)
        }
        y = ceilY
        x += Double(dir) * 110 * k * dt
        if x < ceilL { x = ceilL; dir = 1 }
        if x > ceilR { x = ceilR; dir = -1 }
        if t < 0 { crawlH = IntPtr.Zero; Jump(0, 60 * k); rolling = true; Say(Pick(["跳！嗚哇～", "ih-ih-ih!", "放手！嘻嘻嘻"]), 1) }
    }

    func Curl(_ dt: Double) {
        x += vx * dt; vx *= Math.Pow(0.25, dt)
        rolling = true
        let nx = x
        let midY = y + Double(SH) / 2.0
        if !w.Inside(nx, midY) || !w.Inside(nx + Double(SW), midY) { vx = -vx }
        if supH != IntPtr.Zero && (Cx < Double(supL) || Cx > Double(supR)) { Jump(vx, -60 * k); return }
        if t < 0 { rolling = false; SetState("idle", 1); if rnd.NextDouble() < 0.5 { Say("嘻嘻嘻～", 1) } }
    }

    func StitchBall() {
        let group = w.OutCount() > 1
        w.HoldBall(self)
        if rnd.NextDouble() < (group ? 0.7 : 0.35) {
            SetState("chomp", group ? R(2, 3) : 1.2)
            Say(group ? "嘻嘻嘻！球是史迪仔的！" : Pick(["（咬）嘻嘻嘻", "ih-ih! 史迪仔的！", "（咬咬）好吃"]), 1.8)
            if group { w.Umpire("出局！…吧？") }
            return
        }
        SetState("catch", 0.5)
        Say(L("ball_catch"), 1.6)
        w.Umpire("好球！")
    }

    func Chomp(_ dt: Double) {
        if w.OutCount() > 1 {
            // 叼著球逃跑
            if let o = w.Nearest(self) { dir = o.Cx > Cx ? -1 : 1 }
            if MoveOnGround(dt, 160 * k) { return }
        }
        if t < 0 {
            if w.Holder === self { w.ReleaseBall(Cx + Double(dir) * 6 * k, y + 8 * k, 0, 0); KickBallToCursor(0.8) }
            Say(Pick(["噗！還你～", "呸！嘻嘻嘻"]), 1.2)
            SetState("idle", 1)
        }
    }

    // ================= 人魚漢頓：在空中「游泳」（波浪路線＋泡泡）、披風飛行、頂球 =================
    func StartSwim(_ tx: Double, _ footY: Double, _ cape: Bool) {
        fx0 = x; fy0 = y; fx1 = tx - Double(SW) / 2.0; fy1 = footY - Double(SH)
        let ddx = fx1 - fx0, ddy = fy1 - fy0
        let d = Math.Sqrt(ddx * ddx + ddy * ddy)
        flyDur = Pet.Clamp(d / ((cape ? 520 : 300) * k), 0.9, 4)
        flyArc = 30 * k + Math.Min(140 * k, d * 0.18)
        flyT = 0; supH = IntPtr.Zero; caped = cape
        dir = fx1 >= fx0 ? 1 : -1
        SetState("swim", 99)
    }

    func Swim(_ dt: Double) {
        flyT += dt
        let f = Math.Min(1, flyT / flyDur), e = Pet.Ease(f)
        let arc: Double = Math.Sin(Math.PI * f) * flyArc
        let wave: Double = caped ? 0 : Math.Sin(flyT * 7) * 9 * k * Math.Sin(Math.PI * f)
        x = fx0 + (fx1 - fx0) * e
        y = fy0 + (fy1 - fy0) * e - arc + wave
        if rnd.NextDouble() < dt * (caped ? 4 : 9) { Mark(5) }
        if f < 1 { return }
        x = fx1; y = fy1
        supH = IntPtr.Zero
        for p in w.Plats { if Cx >= Double(p.Left) && Cx <= Double(p.Right) && Math.Abs(Double(p.Top) - (y + Double(SH))) < 3 { SetSupport(p); break } }
        if supH == IntPtr.Zero {
            let wa = w.WA(Cx, y + Double(SH) / 2.0)
            if Math.Abs(Double(wa.Bottom) - (y + Double(SH))) > 3 { caped = false; Jump(0, 0); return }
        }
        let wasCape = caped; caped = false
        if afterLand != "" { LandAction() }
        else if wasCape { poseKind = "hero"; SetState("pose", 1.4); Say(Pick(["（落地）帥嗎？帥嗎？", "英雄著陸！…有點晃"]), 1.6) }
        else { SetState("idle", 1.2) }
    }

    // 像海豹一樣用頭頂球；偶爾連頂幾下
    func HangyodonBall() {
        SetState("header", 0.45)
        w.By = y - 2 * k; w.Bx = Cx
        headers += 1
        if headers < 3 && rnd.NextDouble() < 0.45 {
            w.Bvx = R(-60, 60) * k; w.Bvy = -R(520, 620) * k; w.CatchCd = 0.5
            fetching = true
            Say(Pick(["嘿咻！", "頂！頂！", "海豹式～"]), 0.9)
            return
        }
        headers = 0
        let c = Cursor.Position
        w.Bvx = Pet.Clamp((Double(c.X) - w.Bx) * 0.9, -800 * k, 800 * k); w.Bvy = -R(600, 760) * k; w.CatchCd = 1.0; w.BallIdle = 0
        Say(L("ball_catch"), 1.6)
        w.Umpire("好球！")
    }

    // ---- Spidey（照舊）----
    func FrameSpidey() -> Fr
    {
        let sleep = state == "sleep", hug = state == "hug"
        var armsUp = state == "glass" || state == "kick" || (state == "dance" && Math.Floor(anim * 4) % 2 == 0) || state == "swing" || state == "air" || state == "fling" || state == "climb" || state == "drag" || state == "shoot" || state == "zip"
        armsUp = armsUp || state == "webcatch" || state == "sling" || state == "pose" || state == "stowfly" || (state == "hang" && hangPhase == 0) || (state == "idle" && Bt > 0)
        let step = ((state == "walk" || state == "climb" || state == "goto") && Step2(6))
            || ((state == "seek" || state == "fetch" || state == "hide") && Step2(11))
            || (state == "drag" && Step2(12))
            || (state == "dance" && Math.Floor(anim * 4) % 2 == 1)
        let face: String? = sleep ? "SLEEPY" : (hug ? "HAPPY" : (state == "dizzy" ? "DIZZY" : nil))
        var rows: [String] = HeadRows(face)
        rows += A(hug ? "ARMS_HUG" : (armsUp ? "ARMS_UP" : "BODY"))
        rows += A(step ? "LEGS_B" : "LEGS_A")
        if Night && !hug
        {
            if Pet.PixAt(rows[10], 5) == 107 && Pet.PixAt(rows[10], 6) == 107 { rows[10] = Pet.SetPix(Pet.SetPix(rows[10], 5, 119), 6, 119) }   // k → w
        }
        if !hug && Level() >= 5
        {
            if Pet.PixAt(rows[10], 5) != 114 && Pet.PixAt(rows[10], 6) != 114 { rows[10] = Pet.SetPix(Pet.SetPix(rows[10], 5, 89), 6, 89) }   // != r → Y
        }
        let f = F(rows)
        f.Fy = state == "hang" && hangPhase == 1
        return f
    }

    // ---- 小波 ----
    func FramePo() -> Fr
    {
        if state == "plop" { let pf = F(Pal.Stack(HeadRows(sT < 0.55 ? "DIZZY" : "HAPPY"), A("ARMS_UP"), A("LEGS_SIT"))); pf.Tummy = true; return pf }
        let hug = state == "hug", sleep = state == "sleep"
        let yawn = Night && state == "idle" && (anim % 6) < 1.4
        let face: String? = sleep || yawn ? "SLEEPY" : (hug || state == "spin" || (state == "pose" && poseKind == "homerun") ? "HAPPY" : (state == "dizzy" ? "DIZZY" : (state == "glass" ? "SQUISH" : nil)))
        var armsUp = state == "glass" || state == "catch" || state == "drag" || (state == "air" && !OnScooter()) || (state == "wave" && Step2(4)) || (state == "dance" && Step2(4))
        armsUp = armsUp || (state == "pose" && poseKind != "homerun") || state == "kick" || state == "throw" && t > 0.15
        let body = A(hug ? "ARMS_HUG" : (armsUp ? "ARMS_UP" : "BODY"))
        let f: Fr
        if OnScooter() { f = F(Pal.Stack(HeadRows(face), body, A("LEGS_RIDE"))); f.Top = -4; f.AccDy = -4 }
        else if sleep { f = F(Pal.Stack(HeadRows(face), body, A("LEGS_SIT"))) }
        else
        {
            let step = (state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto") && Step2(10) || (state == "dance" && Step2(4))
            f = F(Pal.Stack(HeadRows(face), body, A(step ? "LEGS_B" : "LEGS_A")))
        }
        f.Tummy = !hug
        if rolling { f.Rot = CInt(Math.Floor(anim * 14)) % 4; f.Acc = false; f.Tummy = false }
        return f
    }

    // ---- 史迪仔 ----
    func FrameStitch() -> Fr
    {
        let hug = state == "hug"
        if RidingStolen
        {
            // 偷騎小波的滑板車：站在車上
            let rs = F(Pal.Stack(HeadRows("HAPPY"), A("ARMS_UP"), A("LEGS_A"))); rs.Top = -4; rs.AccDy = -4; return rs
        }
        if rolling || state == "curl"
        {
            let b = F(A("BALL")); b.Rot = CInt(Math.Floor(anim * 12)) % 4; b.Acc = false; return b
        }
        if state == "sleep"
        {
            let b = F(A("BALL_SLEEP")); b.Acc = false; return b
        }
        let crawl = state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto" || (state == "chomp" && w.OutCount() > 1) || state == "ceil"
        let face: String? = hug ? "HAPPY" : (state == "dizzy" ? "DIZZY" : nil)
        var head = HeadRows(face)
        if crawl
        {
            let c = F(Pal.Stack(head, A(Step2(state == "ceil" ? 8 : 12) ? "CRAWL_B" : "CRAWL_A")))
            c.AccDy = 5
            if state == "ceil" { c.Fy = true; c.Acc = false }
            return c
        }
        // 耳朵：發呆時偶爾抖一抖；晚上垂下來
        if Night && (state == "idle" || state == "hug") { let ed = A("EARS_DOWN"); for i in 0..<ed.count { head[i] = ed[i] } }
        else if (state == "idle" || state == "pose") && (anim % 2.2) < 0.5 && Step2(8) { let eu = A("EARS_UP"); for i in 0..<eu.count { head[i] = eu[i] } }
        var armsUp = state == "wall" || state == "catch" || state == "drag" || state == "air" || state == "nudge" || state == "throw"
        armsUp = armsUp || (state == "elvis" && Step2(5)) || (state == "dance" && Step2(4)) || (state == "pose" && poseKind == "photo") || state == "kick"
        let lick = state == "glass" || (state == "pose" && poseKind == "lick"), grin = state == "chomp" || (state == "pose" && poseKind == "grin")
        if lick { ReplaceFace(&head, "LICKF") } else if grin { ReplaceFace(&head, "GRIN") }
        let bodyName = hug || (Night && state == "idle") ? "ARMS_HUG" : (lick ? "LICK" : (armsUp ? "ARMS_UP" : "BODY"))
        let step = (state == "wall" && Step2(8)) || (state == "elvis" && Step2(6)) || (state == "dance" && Step2(4))
        return F(Pal.Stack(head, A(bodyName), A(step ? "LEGS_B" : "LEGS_A")))
    }

    // ---- 人魚漢頓 ----
    func FrameHangyodon() -> Fr
    {
        let hug = state == "hug", sit = state == "sleep"
        let silly = state == "pose" && poseKind == "silly"
        let sleepy = state == "sleep" || (Night && state == "idle" && (anim % 5) < 1.5)
        let face: String? = sleepy ? "SLEEPY" : (hug || (state == "pose" && poseKind == "hero") ? "HAPPY" : (state == "dizzy" || tripT > 0 ? "DIZZY" : (silly ? "SILLY" : nil)))
        let head = HeadRows(face)
        var armsUp = state == "air" || state == "fling" || state == "drag" || state == "header" || state == "capetrip" || state == "swim"
        armsUp = armsUp || (state == "dance" && Step2(3)) || (state == "pose" && poseKind != "silly") || state == "kick"
        let bodyName = hug ? "ARMS_HUG" : (silly || state == "glass" ? "POUT" : (armsUp ? "ARMS_UP" : "BODY"))
        let moving = state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto"
        let legs = sit ? "LEGS_SIT" : (moving && Step2(4) ? "LEGS_B" : "LEGS_A")
        let f = F(Pal.Stack(head, A(bodyName), A(legs)))
        if tripT > 0 { f.Rot = dir > 0 ? 1 : 3; f.Acc = false }   // 跌個狗吃屎
        if rolling { f.Rot = CInt(Math.Floor(anim * 10)) % 4; f.Acc = false }
        return f
    }

}

// ================= 天線寶寶：丁丁（魔法袋）、迪西（乳牛紋帽子）、拉拉（大橘球）=================
extension Pet {
    var HasTv: Bool { return Is("po") || P.Tubby }

    static let TOAST: [String] = [".2222.", "211112", "2k11k2", "211112", "21kk12", ".2222."]
    static let STAR5: [String] = ["..y..", ".yyy.", "yyyyy", ".yyy.", ".y.y."]

    // 串場要用的小開關
    func LendHat(_ lent: Bool) { hatLost = lent }
    func LoseBall(_ lost: Bool) { ballLost = lost }
    func LendScooter(_ lent: Bool) { lentScooter = lent; LoseScooter(lent) }
    func ResetSceneProps() {
        if lentScooter { lentScooter = false; LoseScooter(false) }
        hatLost = false; WearHat = false; ballLost = false; RidingPo = false; HoldToast = false
        if state == "bagdig" { bagItem = "" }
    }
    func BagPoint() -> PointF { return PointF(Cx + Double(dir * 9 * S), Foot - Double(SH) + Double((P.BodyTop + 3) * S)) }   // 打開的袋口（提在身體旁邊）
    func ClearCrumbs() { _ = notes.RemoveAll { n in n[2] == 7 } }

    func HatOnHead() -> Bool { return Is("dipsy") && !hatLost && state != "hattoss" && !(state == "pose" && poseKind == "hatwave") }

    // 丁丁：跌坐在地上「哎喲！」（小波在大家一起跌倒的串場也會）
    func Plop(_ text: String?) {
        SetState("plop", 1.5); sT = 0
        Burst(4); Mark(4)
        if let text = text { Say(text, 1.4) }
    }

    // 丁丁的魔法袋：打開、翻一翻、拿出東西（catch＝剛接住的球）
    func TinkyBag(_ item: String?, _ quiet: Bool) { TinkyBag(item, quiet, 2.4) }
    func TinkyBag(_ item: String?, _ quiet: Bool, _ dur: Double) {
        if !Is("tinky") || !Grounded() { return }
        var item = item
        if item == nil {
            let items: [String] = ["toast", "heart", "star", "toast", "ball"]
            item = items[rnd.Next(items.count)]
            let ll = w.Get("laalaa")
            if item == "ball" && (ll == nil || !ll!.Out) { item = "heart" }
        }
        bagItem = item ?? ""; bagQuiet = quiet; sT = 0
        SetState("bagdig", Math.Max(1.4, dur))
        if !quiet { Say(Pick(["魔法袋裡有什麼呢？", "丁丁找一找…", "（翻翻袋子）嗯…"]), 1.2) }
    }

    func BagReveal() {
        switch bagItem {
        case "catch":
            if w.Holder === self { w.ReleaseBall(Cx + Double(dir) * 8 * k, y + 6 * k, 0, 0); KickBallToCursor(0.9) }
            if !bagQuiet { Say(Pick(["找到了！還你～", "從魔法袋拿出來囉！"]), 1.6) }
        case "toast": if !bagQuiet { Say(Pick(["是吐司！", "吐司！要吃嗎？"]), 1.6) }
        case "heart": AddHeart(); AddHeart(); if !bagQuiet { Say("是愛心！送給你 ♥", 1.8) }
        case "star": Burst(10); if !bagQuiet { Say("是星星！✨", 1.6) }
        case "ball": if !bagQuiet { Say("咦？拉拉的球怎麼在這裡？", 2) }
        default: break
        }
    }

    // 迪西：帽子丟上去轉一圈、接回頭上
    func HatToss(_ quiet: Bool) {
        if !Is("dipsy") || !Grounded() || hatLost { return }
        sT = 0; SetState("hattoss", 1.6)
        if !quiet { Say(Pick(["看我的帽子！", "帽子戲法！", "嘿～"]), 1.2) }
    }

    // 拉拉：顛球（球在腳和頭頂之間跳）
    func Juggle() {
        if !Is("laalaa") || !Grounded() || ballLost { return }
        juggles = 0; sT = 0
        SetState("juggle", R(2.6, 3.6))
        Say(Pick(["看我的球！啦～", "顛球！1、2、3～", "球球跳跳～"]), 1.2)
    }
    func JugglePhase() -> Double { return (sT * 1.5) % 1.0 }

    func TubbyStep(_ dt: Double) -> Bool {
        if state == "pose" && poseKind == "sing" && rnd.NextDouble() < dt * 3 { Mark(0) }
        if state == "dance" && Is("laalaa") && rnd.NextDouble() < dt * 2 { Mark(0) }
        switch state {
        case "twirl":
            sT += dt
            if Math.Floor(anim * 9) != Math.Floor((anim - dt) * 9) { dir = -dir }
            if rnd.NextDouble() < dt * 3 { Mark(0) }
            if t < 0 { SetState("idle", InScene ? 30 : 1); if !InScene && Is("laalaa") && rnd.NextDouble() < 0.5 { Say("啦啦啦～", 1.2) } }
            return true
        case "hattoss":
            do {
                let prev = sT; sT += dt
                if prev < 1.25 && sT >= 1.25 { Burst(6); if !InScene { Say(Pick(["帥！", "接到了。酷。", "嘿～"]), 1.4) } }
                if t < 0 { SetState("idle", InScene ? 30 : 1) }
            }
            return true
        case "juggle":
            do {
                let prev = JugglePhase(); sT += dt
                if JugglePhase() < prev { juggles += 1; Mark(0); if !InScene { Say(String(juggles) + "！", 0.6) } }
                if t < 0 { SetState("idle", InScene ? 30 : 1); if !InScene { Say(juggles >= 3 ? "啦～！" + String(juggles) + " 下！" : "再來一次！", 1.4) } }
            }
            return true
        case "bagdig":
            do {
                let prev = sT; sT += dt
                if prev < 0.9 && sT >= 0.9 { BagReveal() }
                if t < 0 { if bagItem == "catch" && w.Holder === self { BagReveal() }; bagItem = ""; SetState("idle", InScene ? 30 : 1) }
            }
            return true
        default: break
        }
        return false
    }

    // ---------- 球（大家的球；小波在的話是棒球）----------
    func TinkyBall() {
        w.HoldBall(self)
        TinkyBag("catch", true, 1.8)
        if state != "bagdig" { w.ReleaseBall(Cx, y, 0, 0); KickBallToCursor(0.9) }   // 在空中接到：直接丟回去
        Say(L("ball_catch"), 1.6)
        w.Umpire("好球！")
    }

    // 迪西：用帽子頂球（偶爾連頂幾下）
    func DipsyBall() {
        SetState("header", 0.45)
        w.By = y + Double(SH) - Double(16 * S) + Double((P.HeadTop - 7) * S); w.Bx = Cx
        headers += 1
        if headers < 3 && rnd.NextDouble() < 0.4 {
            w.Bvx = R(-60, 60) * k; w.Bvy = -R(520, 620) * k; w.CatchCd = 0.5
            fetching = true
            Say(Pick(["帽子頂！", "嘿！再一下", "酷～"]), 0.9)
            return
        }
        headers = 0
        let c = Cursor.Position
        w.Bvx = Pet.Clamp((Double(c.X) - w.Bx) * 0.9, -800 * k, 800 * k); w.Bvy = -R(600, 760) * k; w.CatchCd = 1.0; w.BallIdle = 0
        Say(L("ball_catch"), 1.6)
    }

    // 拉拉：用腳踢（偶爾先顛幾下）
    func LaaLaaBall() {
        SetState("kick", 0.45)
        w.By = y + Double(SH) - w.BallR() - 2 * k; w.Bx = Cx + Double(dir) * 4 * k
        headers += 1
        if headers < 3 && rnd.NextDouble() < 0.45 {
            w.Bvx = R(-40, 40) * k; w.Bvy = -R(480, 600) * k; w.CatchCd = 0.5
            fetching = true
            Say(Pick(["1、2…", "啦～顛球！", "嘿咻！"]), 0.9)
            return
        }
        headers = 0
        let c = Cursor.Position
        w.Bvx = Pet.Clamp((Double(c.X) - w.Bx) * 1.1, -950 * k, 950 * k); w.Bvy = -R(500, 700) * k; w.CatchCd = 1.0; w.BallIdle = 0
        Say(L("ball_catch"), 1.6)
        w.Umpire("好球！")
    }

    // ---------- 畫 ----------
    func FrameTubby() -> Fr {
        let hug = state == "hug", sleep = state == "sleep", plop = state == "plop"
        let nightIdle = Night && state == "idle" && !InScene && !HoldingFood()
        let sit = sleep || plop || (Is("laalaa") && nightIdle)
        let yawn = Night && state == "idle" && (anim % 6) < 1.4
        var face: String?
        let posePhotoSingWave = state == "pose" && (poseKind == "photo" || poseKind == "sing" || poseKind == "hatwave")
        let happyA = hug || state == "twirl" || state == "juggle" || (state == "dance" && Step2(2))
        let happyB = (state == "bagdig" && sT > 0.9) || posePhotoSingWave
        if plop { face = sT < 0.55 ? "OUCH" : "HAPPY" }
        else if sleep || yawn || (Is("dipsy") && nightIdle) || (state == "pose" && poseKind == "hatdown") { face = "SLEEPY" }
        else if happyA || happyB { face = "HAPPY" }
        else if state == "dizzy" { face = "DIZZY" }
        else if state == "glass" { face = "SQUISH" }
        else { face = nil }
        var armsUp = state == "glass" || state == "catch" || state == "drag" || state == "air" || state == "fling"
        armsUp = armsUp || state == "kick" || state == "header" || (state == "throw" && t > 0.15)
        armsUp = armsUp || (state == "wave" && Step2(4)) || (state == "dance" && Step2(4)) || state == "twirl"
        armsUp = armsUp || (state == "hattoss" && (sT < 0.3 || (sT > 1.1 && sT < 1.5)))
        let poseArms = poseKind == "photo" || poseKind == "hatwave" || poseKind == "hattip" || (poseKind == "sing" && Step2(3))
        armsUp = armsUp || (state == "pose" && poseArms)
        armsUp = armsUp || (state == "bagdig" && sT > 0.9 && sT < 1.7)
        if RidingPo { armsUp = state == "air" || state == "drag" }
        lastArmsUp = armsUp
        let bodyName = hug || (nightIdle && !Is("dipsy")) ? "ARMS_HUG" : (armsUp ? "ARMS_UP" : "BODY")
        var legs: String
        let ride = RidingPo && !rolling
        if ride { legs = "LEGS_RIDE" }
        else if sit { legs = "LEGS_SIT" }
        else {
            let moving = state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto"
            let rate: Double = Is("tinky") ? 5 : (Is("laalaa") ? 9 : 7)
            var step = (moving && Step2(rate)) || (state == "dance" && Step2(4))
            step = step || (state == "juggle" && JugglePhase() < 0.2) || (state == "kick" && t > 0.15)
            legs = step ? "LEGS_B" : "LEGS_A"
        }
        let f = F(Pal.Stack(HeadRows(face), A(bodyName), A(legs)))
        if ride { f.Top = -4; f.AccDy = -4 }
        else if sit { f.AccDy = A("LEGS_A").count - A("LEGS_SIT").count }
        f.Tummy = !hug
        if rolling { f.Rot = CInt(Math.Floor(anim * 14)) % 4; f.Acc = false; f.Tummy = false }
        return f
    }

    func TubbyBob() -> Double {
        if state == "dance" || state == "elvis" { return Math.Abs(Math.Sin(anim * (Is("dipsy") ? 6 : 8))) * 6 * k }
        let moving = state == "walk" || state == "goto" || state == "seek" || state == "fetch"
        if moving && !RidingPo {
            if Is("laalaa") { return Math.Abs(Math.Sin(anim * 7)) * 5 * k }      // 蹦蹦跳跳
            if Is("dipsy") { return Math.Abs(Math.Sin(anim * 5)) * 2.5 * k }     // 跟著節奏
        }
        if Is("dipsy") && state == "idle" && !Night { return (Math.Floor(anim * 2) % 2) * k }   // 點頭打拍子
        return 0
    }

    // 拉拉的球現在在哪裡：none／floor（腳邊）／dribble（往前帶）／juggle／hold（抱著）／raised（舉高高）
    func BallSpot(_ f: Fr) -> String {
        if !Is("laalaa") || ballLost || w.BallOn || f.Rot != 0 || f.Fy { return "none" }
        if w.Lunch && HoldingFood() && state != "sleep" { return "none" }
        if state == "juggle" { return "juggle" }
        if state == "pose" && poseKind == "photo" { return "raised" }
        if Night && state == "idle" && !InScene { return "hold" }
        if state == "air" || state == "fling" || state == "drag" || state == "stowfly" { return "hold" }
        if state == "walk" || state == "goto" || state == "seek" || state == "hide" { return "dribble" }
        return "floor"
    }

    // 丁丁的袋子在哪裡：floor（放地上）／hand（提著）／up（舉起來）／hug（抱著）／open（打開翻找）
    func BagSpot(_ f: Fr) -> String {
        if !Is("tinky") || f.Rot != 0 || f.Fy { return "none" }
        if state == "bagdig" { return "open" }
        if state == "hug" || state == "sleep" || state == "plop" || RidingPo || HoldToast || (w.Lunch && HoldingFood()) { return "floor" }
        if Night && state == "idle" && !InScene { return "hug" }
        return lastArmsUp ? "up" : "hand"
    }

    func DrawTubbyBehind(_ g: Graphics, _ f: Fr, _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool) {
        if RidingPo && !rolling {
            if let po = Pal.Get("po") { DrawPixPal(g, po, po.Art["SCOOTER"], bx + (fx ? 12 - (-1) - 14 : -1) * ps, by + 7 * ps, ps, fx) }
        }
        if BagSpot(f) == "floor" { DrawAt(g, A("BAG"), HoldToast || w.Lunch ? -8.5 : 12.5, 9, bx, by, ps, fx, false, true) }   // 手上拿吃的：袋子放另一邊
        if BallSpot(f) == "floor" { DrawAt(g, A("BALL"), 12, 9, bx, by, ps, fx, false, true) }
    }

    func DrawTubbyFront(_ g: Graphics, _ f: Fr, _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool) {
        if f.Rot != 0 || f.Fy { return }
        let dy = f.AccDy
        // 迪西的帽子
        if Is("dipsy") && !hatLost {
            let hat = A("HAT")
            var row = Double(P.HeadTop - 6 + dy), col = -2.0
            if state == "hattoss" && sT < 1.25 {
                let ff = Pet.Clamp(sT / 1.25, 0, 1)
                row -= Math.Sin(Math.PI * ff) * 11
                let side = Math.Floor(sT * 10) % 2 == 1                       // 轉呀轉：正面、側面輪流
                let flipNow = fx != (Math.Floor(sT * 5) % 2 == 1)
                DrawAt(g, side ? A("HAT_HAND") : hat, side ? 2 : col, row, bx, by, ps, flipNow, false, true)
            }
            else if state == "pose" && poseKind == "hatwave" {
                DrawAt(g, A("HAT_HAND"), 11.0 + (Step2(4) ? 1.0 : 0.0), Double(P.BodyTop - 8 + dy), bx, by, ps, fx, false, true)
            }
            else {
                if state == "pose" && poseKind == "hattip" { row -= 2; col += 1 }
                else if state == "header" { row -= 1 }
                else if (state == "pose" && poseKind == "hatdown") || state == "sleep" || (Night && state == "idle" && !InScene) { row += 3 }   // 帽子拉低蓋住眼睛
                DrawAt(g, hat, col, row, bx, by, ps, fx, false, true)
            }
        }
        // 借戴迪西的帽子（串場）
        if WearHat { DrawAt(g, A("HAT"), -2, Double(P.HeadTop - 6 + dy), bx, by, ps, fx, false, true) }
        // 丁丁的魔法袋
        switch BagSpot(f) {
        case "hand": DrawAt(g, A("BAG"), 12 + (state == "walk" && Step2(5) ? 0.5 : 0), Double(P.BodyTop + 1 + dy), bx, by, ps, fx, false, true)
        case "up": DrawAt(g, A("BAG"), 12.5, Double(P.BodyTop - 5 + dy), bx, by, ps, fx, false, true)
        case "hug": DrawAt(g, A("BAG"), 2, Double(P.BodyTop + 2 + dy), bx, by, ps, fx, false, true)
        case "open":
            do {
                // 袋子打開提在身體旁邊，東西從袋口冒出來（不擋到臉）
                let bagRow = Double(P.BodyTop + 2 + dy)
                if let item = BagItemArt(), sT > 0.9 {
                    let rise = Pet.Clamp((sT - 0.9) / 0.35, 0, 1) * Double(item.count + 2)
                    if !(bagItem == "catch" && w.Holder !== self && sT > 1.3) {
                        DrawAt(g, item, 15 - Double(item[0].count) / 2.0, bagRow + 2 - rise, bx, by, ps, fx, false, true)
                    }
                }
                DrawAt(g, A("BAG_OPEN"), 11, bagRow, bx, by, ps, fx, false, true)
            }
        default: break
        }
        // 拉拉的球
        let ball = A("BALL")
        switch BallSpot(f) {
        case "juggle":
            do {
                let h = Math.Sin(Math.PI * JugglePhase()) * 12
                DrawAt(g, ball, 10, 9 - h, bx, by, ps, fx, false, true)   // 在身體前側顛，不擋臉
            }
        case "dribble": DrawAt(g, ball, 11.5, 9 - Math.Abs(Math.Sin(anim * 8)) * 2, bx, by, ps, fx, false, true)
        case "hold": DrawAt(g, ball, 2, Double(P.BodyTop + 2 + dy), bx, by, ps, fx, false, true)
        case "raised": DrawAt(g, ball, 2, Double(P.HeadTop - 8 + dy), bx, by, ps, fx, false, true)
        default: break
        }
    }

    func BagItemArt() -> [String]? {
        switch bagItem {
        case "toast": return Pet.TOAST
        case "heart": return Pet.HEART
        case "star": return Pet.STAR5
        case "ball": return A("BALL")
        case "catch": return w.BallKind == "baseball" ? Pet.BALLART : (w.BallKind == "tubby" ? A("BALL") : Pet.TBALL)
        default: break
        }
        return nil
    }

    // ---------- 櫃子裡：丁丁翻魔法袋、迪西抬帽子打拍子、拉拉拍球；晚上抱著自己的東西睡 ----------
    // mac: head 在 C# 是共用參考、ReplaceFace 會改它；這裡複製一份再用 inout 改（呼叫端之後不再用 head）
    func DrawTubbyShelf(_ g: Graphics, _ head: [String], _ fx: Int, _ bx: Int, _ by: Int, _ ps: Int, _ flip: Bool, _ tt: Double, _ blink: Bool) {
        var head = head
        var by = by
        var body = "BODY", legs = "LEGS_A"
        var normalFace = true, sit = false
        var groove = 0
        if Is("tinky") {
            if Night { body = "ARMS_HUG"; if (tt % 5) < 3 { ReplaceFace(&head, "SLEEPY"); normalFace = false } }
            else if (tt % 8) < 2.4 && !w.Lunch && (tt % 8) > 0.9 { ReplaceFace(&head, "HAPPY"); normalFace = false }
            else if blink { ReplaceFace(&head, "SLEEPY"); normalFace = false }
        }
        else if Is("dipsy") {
            if Night { ReplaceFace(&head, "SLEEPY"); normalFace = false }
            else {
                groove = Math.Floor(tt * 2.2) % 2 == 0 ? 0 : 1
                if (tt % 5) < 0.9 { ReplaceFace(&head, "HAPPY"); normalFace = false }
                else if blink { ReplaceFace(&head, "SLEEPY"); normalFace = false }
            }
        }
        else {
            if Night { sit = true; body = "ARMS_HUG"; legs = "LEGS_SIT"; if (tt % 6) < 4 { ReplaceFace(&head, "SLEEPY"); normalFace = false } }
            else if Math.Abs(Math.Sin(tt * 3.2)) > 0.8 { ReplaceFace(&head, "HAPPY"); normalFace = false }
            else if blink { ReplaceFace(&head, "SLEEPY"); normalFace = false }
        }
        by += groove
        let dy = sit ? A("LEGS_A").count - A("LEGS_SIT").count : 0
        let rows = Pal.Stack(head, A(body), A(legs))
        if Is("tinky") && w.Lunch { DrawAt(g, A("BAG"), 9.5, 9, bx, by, ps, flip, false, true) }
        DrawPix(g, rows, bx - (rows[0].count - 12) / 2 * ps, by + (16 - rows.count) * ps, ps, flip, false, true)
        DrawAccessories(g, bx, by, ps, flip, dy, normalFace)
        DrawStatusIcon(g, TummyStatus(), bx + 6 * ps, by + CInt((P.TummyRow + Double(dy)) * Double(ps)), Math.Max(1, ps / 2), true)
        if Is("tinky") && !w.Lunch {
            if Night { DrawAt(g, A("BAG"), 2, Double(P.BodyTop + 2), bx, by, ps, flip, false, true) }
            else if (tt % 8) < 2.4 {
                let ph = tt % 8
                let items: [[String]] = [Pet.TOAST, Pet.HEART, Pet.STAR5]
                let item = items[CInt(Math.Floor(tt / 8)) % 3]
                if ph > 0.9 {
                    let rise = Pet.Clamp((ph - 0.9) / 0.35, 0, 1) * Double(item.count + 2)
                    DrawAt(g, item, 13.5 - Double(item[0].count) / 2.0, Double(P.BodyTop + 5) - rise, bx, by, ps, flip, false, true)
                }
                DrawAt(g, A("BAG_OPEN"), 9.5, Double(P.BodyTop + 3), bx, by, ps, flip, false, true)
            }
            else { DrawAt(g, A("BAG"), 9, Double(P.BodyTop + 3), bx, by, ps, flip, false, true) }
        }
        if Is("dipsy") { DrawAt(g, A("HAT"), -2, Double(P.HeadTop - 6 + (Night ? 3 : ((tt % 5) < 0.9 ? -1 : 0))), bx, by, ps, flip, false, true) }
        if Is("laalaa") && Night { DrawAt(g, A("BALL"), 2, Double(P.BodyTop + 2 + dy), bx, by, ps, flip, false, true) }
        else if Is("laalaa") && !w.Lunch { DrawAt(g, A("BALL"), 9.5, 9 - Math.Abs(Math.Sin(tt * 3.2)) * 4, bx, by, ps, flip, false, true) }   // 在旁邊拍球（格子窄，靠近一點）
    }
}

// ================= 串場（從 41_world_b.swift 搬來）=================
extension World {
    // 吸吸：原創的圓圓掃地小機器人（前面一根短短的吸管鼻子），兩格輪流＝輪子在轉
    static let BOT_A = ["....kkkkkk......", "..kkvvvvvvkk....", ".kvvWvvvvvvvk...", ".kvkWvvkWvvvkkkk", "kvvkkvvkkvvvkvVk", "kvvvvvvvvvvvkkkk", "kVVVVVVVVVVVk...", ".kkkkkkkkkkkk...", "..kOk....kOk...."]
    static let BOT_B = ["....kkkkkk......", "..kkvvvvvvkk....", ".kvvWvvvvvvvk...", ".kvkWvvkWvvvk...", "kvvkkvvkkvvvkkkk", "kvvvvvvvvvvvkvVk", "kVVVVVVVVVVVkkkk", ".kkkkkkkkkkkk...", "...kOk..kOk....."]

    // Spidey × 人魚漢頓：想當英雄的漢頓、鼓勵他的 Spidey
    func SceneHeroes(_ s: Pet, _ h: Pet) {
        Begin(s, h)
        At(0) { [self] in Face(s, h); s.ScenePose("idle", 13); h.ScenePose("idle", 13); h.Say("你、你是真的英雄耶！", 2) }
        At(2.1) { h.ScenePose("cape", 1.8); h.Say("我也想當英雄…可是我只有一件披風", 2.6) }
        At(4.9) { s.ScenePose("hop", 0); s.Say("英雄不是看披風的", 2.2) }
        At(7.2) { s.Say("你每天逗大家笑，已經是英雄了", 2.6) }
        At(9.9) { h.Say("真、真的嗎？嗚嗚…", 1.8); h.Mark(4) }
        At(11.6) { if s.Cx < h.Cx { s.dir = 1; h.dir = -1 } else { s.dir = -1; h.dir = 1 }; s.ScenePose("hero", 2.6); h.ScenePose("cape", 2.6); s.Say("英雄合體！", 2.4); h.Say("英雄合體！（好帥！）", 2.4) }
        At(14.4) { }
    }

    // Spidey × 小波：用絲把小波（連車）甩上去
    func SceneSling(_ s: Pet, _ po: Pet) {
        Begin(s, po)
        At(0) { [self] in Face(s, po); s.ScenePose("idle", 8); po.ScenePose("idle", 8); s.Say("小波，要不要飛高高？", 2) }
        At(2.1) { po.ScenePose("wave", 1.2); po.Say("要要要！Eh-oh!", 1.6) }
        At(3.5) { [self] in
            s.SlingAt(po)
            var best: Plat! = nil
            for p in Plats { if Double(p.Top) < po.Foot - 80 * k && Double(p.Top) > po.Foot - 600 * k && Math.Abs(Double(p.Left + p.Right) / 2.0 - po.Cx) < 700 * k && p.Right - p.Left > po.SW * 2 { best = p; break } }
            if best != nil { po.JumpTo(Math.Max(Double(best.Left + po.SW), Math.Min(Double(best.Right - po.SW), po.Cx)), Double(best.Top)) }
            else { po.Jump(0, -820 * k) }
            po.Say("咻～～～", 1.4)
        }
        At(5.6) { po.Say("再來一次！再來一次！", 2) }
        At(7.8) { s.Say("……下次再說 😅", 1.8) }
        At(9.5) { }
    }

    // Spidey × 史迪仔：比賽爬牆
    func SceneClimbRace(_ s: Pet, _ st: Pet) {
        Begin(s, st)
        At(0) { [self] in Face(s, st); s.ScenePose("idle", 6); st.ScenePose("grin", 1.6); st.Say("ih! 史迪仔也會爬牆！", 1.8) }
        At(1.9) { s.Say("喔？比賽啊！預備…", 1.6) }
        At(3.4) { s.InScene = false; st.InScene = false; s.Act("climb"); st.Signature(); s.Say("開始！", 1) }
        At(9) { [self] in if rnd.NextDouble() < 0.5 { st.Say("史迪仔贏了！嘻嘻嘻", 2) } else { s.Say("Spidey 贏了！Thwip!", 2) } }
        At(9.2) { }
    }

    // 史迪仔 × 小波：偷騎滑板車
    func SceneScooterThief(_ st: Pet, _ po: Pet) {
        Begin(st, po)
        At(0) { [self] in Face(st, po); po.ScenePose("idle", 10); st.ScenePose("grin", 1.2); st.Say("嘻嘻嘻…", 1.2) }
        At(1.3) { [self] in
            po.LoseScooter(true); st.RidingStolen = true
            let away: Double = st.Cx > po.Cx ? 1 : -1
            st.RaceTo(st.Cx + away * 260 * k)
            st.Say("ih-ih-ih! 滑板車！", 1.6)
        }
        At(1.8) { po.Say("我的滑板車！", 2); po.WalkTo(st.Cx, 3) }
        At(4.6) { st.ScenePose("idle", 6); st.FaceTo(po); st.Say("Ohana！一家人不會丟下任何人！", 2.6); st.RidingStolen = false; po.LoseScooter(false) }
        At(5.2) { po.WalkTo(st.Cx + (po.Cx < st.Cx ? -1 : 1) * Double(st.SW) * 0.9, 1.5) }
        At(7.4) { [self] in Face(st, po); st.ScenePose("hug", 2.4); po.ScenePose("hug", 2.4); po.Say("大抱抱！", 2.2) }
        At(10) { }
    }

    // 史迪仔 × 人魚漢頓：「我們都是藍色的，是兄弟吧？」
    func SceneBlueBrothers(_ st: Pet, _ h: Pet) {
        Begin(st, h)
        At(0) { [self] in Face(st, h); st.ScenePose("idle", 10); h.ScenePose("idle", 10); h.Say("我們都是藍色的，是兄弟吧？", 2.4) }
        At(2.5) { st.Say("ih?（歪頭）", 1.2); st.Mark(2) }
        At(3.8) { st.WalkTo(h.Cx + (st.Cx < h.Cx ? -1 : 1) * Double(h.SW) * 0.8, 1.0) }
        At(5.0) { [self] in Face(st, h); st.ScenePose("lick", 1.4); st.Say("（舔）", 1.2); h.Mark(4) }
        At(6.5) { h.Say("嘻嘻…好癢！這是兄弟的打招呼嗎？", 2.4) }
        At(9.0) { st.ScenePose("hug", 2.4); h.ScenePose("hug", 2.4); st.Say("Ohana！", 2.2); h.Say("Ohana…我有家人了 ♥", 2.4) }
        At(11.6) { }
    }

    // 小波 × 人魚漢頓：笑話讓小波笑了，漢頓超開心
    func SceneJoke(_ po: Pet, _ h: Pet) {
        Begin(po, h)
        At(0) { [self] in Face(po, h); po.ScenePose("idle", 11); h.ScenePose("idle", 11); h.Say("小波，要聽笑話嗎？", 1.8) }
        At(1.9) { po.ScenePose("wave", 1); po.Say("要！Eh-oh!", 1.4) }
        At(3.4) { h.Say("為什麼魚不會打網球？…因為怕碰到網子！", 3) }
        At(6.6) { po.ScenePose("hop", 0); po.Say("嘻嘻嘻！再來一次！再來一次！", 2.2) }
        At(8.9) { h.ScenePose("cape", 2); h.Say("她笑了！有人笑了！我、我好開心！", 2.6); for _ in 0..<4 { h.Mark(5) } }
        At(11.6) { [self] in Face(po, h); po.ScenePose("hug", 2.2); h.ScenePose("hug", 2.2); po.Say("大抱抱！", 2) }
        At(14) { }
    }

    // 照節目的順序：丁丁、迪西、拉拉、小波
    func ShowOrder(_ l: List<Pet>) -> List<Pet> {
        let o = List<Pet>()
        for id in Pal.LineupIds(Pal.Teletubbies) { for p in l { if p.P.Id == id { o.Add(p) } } }
        for p in l { if !o.Contains(p) { o.Add(p) } }
        return o
    }

    func TubbyGroup(_ n: Int) {
        let r = rnd.NextDouble()
        if n >= 4 {
            if r < 0.30 { SceneBigHug() } else if r < 0.50 { SceneSing() } else if r < 0.70 { SceneToast() } else if r < 0.85 { SceneFall() } else { GroupPhoto() }
        } else {
            if r < 0.25 { SceneSing() } else if r < 0.50 { SceneToast() } else if r < 0.70 { SceneFall() } else if r < 0.90 { GroupPhoto() } else { SceneBigHug() }
        }
    }

    // ---------- 丁丁 × 迪西：帽子借我戴 ----------
    func SceneHatSwap(_ ti: Pet, _ di: Pet) {
        Begin(ti, di)
        At(0) { [self] in Face(ti, di); ti.ScenePose("idle", 30); di.ScenePose("hattip", 1.8); ti.Say("迪西，你的帽子好好看喔…", 2.2) }
        At(2.3) { ti.Say("可以借丁丁戴一下嗎？", 2); ti.AddHeart() }
        At(4.4) { di.ScenePose("idle", 30); di.Say("不行。這是我的帽子。", 2) }
        At(6.5) { ti.ScenePose("hug", 1.8); ti.Say("拜託～一下下就好", 1.8) }
        At(8.5) { [self] in
            di.Say("……好啦，一下下喔。", 1.8)
            di.LendHat(true)
            Toss(Pal.Get("dipsy").Art["HAT"], Pal.Get("dipsy"), di.HatPoint(), ti.HatPoint(), 0.7, 70 * k, true, 0) { ti.WearHat = true; ti.Burst(6) }
        }
        At(9.6) { ti.ScenePose("dance", 3); ti.Say("我是迪西！嘿～嘿～", 2.4) }
        At(10.4) { di.Say("（頭頂涼涼的）", 1.8); di.Mark(2) }
        At(12.7) { [self] in
            ti.ScenePose("plop", 1.8); ti.Say("哎喲！", 1.4)
            ti.WearHat = false
            Toss(Pal.Get("dipsy").Art["HAT"], Pal.Get("dipsy"), ti.HatPoint(), di.HatPoint(), 0.75, 90 * k, true, 0) { di.LendHat(false) }
        }
        At(14.2) { di.ScenePose("hattip", 2); di.Say("還是我戴最帥。", 2) }
        At(16.4) { [self] in Face(ti, di); ti.ScenePose("hug", 2.4); di.ScenePose("hug", 2.4); ti.Say("大抱抱！", 2.2); di.Say("…大抱抱。", 2.2) }
        At(19) { }
    }

    // ---------- 丁丁 × 拉拉：球滾進魔法袋 ----------
    func SceneBallBag(_ ti: Pet, _ la: Pet) {
        Begin(ti, la)
        let ball: [String] = la.P.Art["BALL"]
        At(0) { [self] in Face(ti, la); ti.ScenePose("idle", 30); la.ScenePose("juggle", 2.6); la.Say("丁丁看！拉拉的球～啦啦啦", 2.4) }
        At(2.8) { [self] in
            la.ScenePose("kick", 0.5); la.Say("踢～！", 1); la.LoseBall(true)
            ti.ScenePose("bag:", 3.4)
            Toss(ball, la.P, la.FootPoint(), ti.BagPoint(), 0.8, 90 * k, false, 0) { ti.Say("喔？（咕嘟）", 1.2); ti.Mark(2) }
        }
        At(5.0) { la.ScenePose("idle", 30); la.Say("咦？我的球呢？", 1.8); la.Mark(2) }
        At(7.0) { ti.ScenePose("bag:toast", 2.4); ti.Say("丁丁找找看…", 1.2) }
        At(8.2) { ti.Say("是吐司！", 1.6) }
        At(9.8) { la.Say("不是這個啦～", 1.8) }
        At(11.6) { ti.ScenePose("bag:ball", 2.2); ti.Say("再找找…", 1.2) }
        At(12.8) { ti.Say("找到了！", 1.4) }
        At(13.85) { [self] in
            var a = ti.BagPoint(); a.Y -= Double(6 * S)
            Toss(ball, la.P, a, la.HandPoint(), 0.7, 70 * k, false, 0) { la.LoseBall(false); la.ScenePose("twirl", 1.6); la.Say("再來一次！再來一次！", 2) }
        }
        At(16.6) { [self] in Face(ti, la); ti.ScenePose("hug", 2.4); la.ScenePose("hug", 2.4); ti.Say("大抱抱！", 2.2); la.Say("大抱抱！", 2.2) }
        At(19.2) { }
    }

    // ---------- 迪西 × 拉拉：跳舞比賽，最後一起唱 ----------
    func SceneDanceOff(_ di: Pet, _ la: Pet) {
        Begin(di, la)
        At(0) { [self] in Face(di, la); di.ScenePose("idle", 30); la.ScenePose("idle", 30); di.Say("拉拉，來比跳舞。", 2) }
        At(2.2) { di.ScenePose("dance", 2.6); di.Say("嘿～嘿～（帽子跟著晃）", 2.4) }
        At(5.0) { di.ScenePose("idle", 30); la.ScenePose("twirl", 2.2); la.Say("換我！啦啦啦～", 2.2) }
        At(7.5) { la.ScenePose("idle", 30); di.ScenePose("hattoss", 1.6); di.Say("帽子戲法！", 1.6) }
        At(9.4) { la.ScenePose("juggle", 2.7); la.Say("球球戲法！1、2、3～", 2.4) }
        At(12.3) { di.ScenePose("dance", 3); la.ScenePose("dance", 3); la.Say("一起跳！啦啦啦～♪", 2.6); di.Say("嘿～♪", 1.6); di.Mark(0); la.Mark(0) }
        At(15.5) { [self] in Face(di, la); di.ScenePose("wave", 1.8); la.ScenePose("wave", 1.8); di.Say("Eh-oh.", 1.6); la.Say("Eh-oh!", 1.6) }
        At(17.6) { }
    }

    // ---------- 小波 × 丁丁：借騎滑板車，太大了跌坐 ----------
    func SceneScooterRide(_ po: Pet, _ ti: Pet) {
        Begin(po, ti)
        At(0) { [self] in Face(po, ti); po.ScenePose("idle", 30); ti.ScenePose("idle", 30); ti.Say("小波，丁丁可以騎你的滑板車嗎？", 2.4) }
        At(2.5) { po.ScenePose("wave", 1.2); po.Say("好啊！Eh-oh!", 1.6) }
        At(4.0) { [self] in
            po.LendScooter(true); ti.RidingPo = true
            let away: Double = ti.Cx > po.Cx ? 1 : -1
            let wa = WA(ti.Cx, ti.Foot - 4)
            ti.RaceTo(World.Mid(ti.Cx + away * 200 * k, Double(wa.Left + ti.SW), Double(wa.Right - ti.SW)))
            ti.Say("嘟嘟～丁丁騎車車！", 1.8)
        }
        At(6.4) { ti.Say("哎…哎…好晃…", 1.4); ti.Mark(4) }
        At(7.8) { ti.RidingPo = false; po.LendScooter(false); ti.ScenePose("plop", 1.8); ti.Say("哎喲！", 1.4) }
        At(9.2) { po.ScenePose("hop", 0); po.Say("再來一次！再來一次！", 2) }
        At(11.4) { ti.Say("…丁丁太大了啦，嘻嘻", 2) }
        At(13.2) { po.WalkTo(ti.Cx + (po.Cx < ti.Cx ? -1 : 1) * Double(ti.SW) * 0.9, 1.5) }
        At(15.2) { [self] in Face(po, ti); po.ScenePose("hug", 2.4); ti.ScenePose("hug", 2.4); po.Say("大抱抱！", 2.2); ti.Say("大抱抱！", 2.2) }
        At(17.8) { }
    }

    // ---------- 小波 × 迪西：棒球用帽子頂、用帽子接 ----------
    func SceneHatBaseball(_ po: Pet, _ di: Pet) {
        Begin(po, di)
        At(0) { [self] in Face(po, di); po.ScenePose("idle", 30); di.ScenePose("idle", 30); po.Say("迪西，接球！", 1.6) }
        At(1.6) { po.ScenePose("bat", 0) }
        At(1.85) { [self] in
            var top = di.HatPoint(); top.Y -= Double(4 * S)
            Toss(World.BASEBALL_ART, po.P, po.HandPoint(), top, 0.7, 60 * k, false, 0) { [self] in
                di.ScenePose("header", 0.6); di.Say("帽子頂！", 1.2)
                var t2 = di.HatPoint(); t2.Y -= Double(4 * S)
                Toss(World.BASEBALL_ART, po.P, t2, po.HandPoint(), 0.8, 80 * k, false, 0) { po.ScenePose("catch", 0.7); po.Say("好球！", 1.4) }
            }
        }
        At(5.4) { po.Say("這次全壘打！", 1.4) }
        At(6.6) { po.ScenePose("bat", 0); di.ScenePose("hatwave", 3.2) }
        At(6.85) { [self] in
            let hx: Double = di.Cx + Double(di.dir * 5 * S)
            let hy: Double = di.Foot - Double(di.SH) + Double((di.P.BodyTop - 5) * S)
            let hand = PointF(hx, hy)
            Toss(World.BASEBALL_ART, po.P, po.HandPoint(), hand, 1.1, 170 * k, false, 0) { di.Say("（用帽子接住）酷。", 2); di.Burst(6) }
        }
        At(10.4) { po.ScenePose("hop", 0); po.Say("再來一次！再來一次！", 2) }
        At(12.6) { di.ScenePose("hattip", 1.8); di.Say("好啦，明天再來一次。", 2) }
        At(14.8) { [self] in Face(po, di); po.ScenePose("wave", 1.8); di.ScenePose("wave", 1.8); po.Say("Eh-oh!", 1.6); di.Say("Eh-oh.", 1.6) }
        At(16.8) { }
    }

    // ---------- 拉拉 × 小波：踢球、小波騎車去撿 ----------
    func SceneBallFetch(_ la: Pet, _ po: Pet) {
        Begin(la, po)
        let ball: [String] = la.P.Art["BALL"]
        // C# 的 tx／lying 是被 lambda 抓住的區域變數（共用）：用一個小盒子裝
        final class Box { var tx: Double = 0; var lying: Prop? = nil }
        let bx = Box()
        bx.tx = po.Cx
        At(0) { [self] in Face(la, po); la.ScenePose("idle", 30); po.ScenePose("idle", 30); la.Say("小波！我們來踢球！", 2) }
        At(2.0) { po.ScenePose("wave", 1.0); po.Say("好！Eh-oh!", 1.4) }
        At(3.4) { [self] in
            la.ScenePose("kick", 0.5); la.Say("踢～！", 1); la.LoseBall(true)
            let wa = WA(la.Cx, la.Foot - 4)
            let side: Double = po.Cx >= la.Cx ? 1 : -1
            bx.tx = World.Mid(po.Cx + side * 220 * k, Double(wa.Left + po.SW), Double(wa.Right - po.SW))
            bx.lying = Toss(ball, la.P, la.FootPoint(), PointF(bx.tx, la.Foot - 3.5 * Double(S)), 1.0, 130 * k, false, 30, nil)
        }
        At(3.9) { po.RaceTo(bx.tx); po.Say("我去撿！嘟嘟～", 1.6) }
        At(6.4) { [self] in RemoveProp(bx.lying); po.FaceTo(la); po.Say("找到了！", 1.4) }
        At(7.2) { [self] in Toss(ball, la.P, po.HandPoint(), la.HandPoint(), 0.9, 110 * k, false, 0) { la.LoseBall(false); la.ScenePose("twirl", 1.6); la.Say("再來一次！", 1.6); po.Say("再來一次！", 1.6) } }
        At(9.8) { po.WalkTo(la.Cx + (po.Cx < la.Cx ? -1 : 1) * Double(la.SW) * 1.0, 1.5) }
        At(12.0) { [self] in Face(la, po); la.ScenePose("hug", 2.4); po.ScenePose("hug", 2.4); la.Say("大抱抱！", 2.2); po.Say("大抱抱！", 2.2) }
        At(14.6) { }
    }

    // ---------- 大家：大抱抱 ----------
    func SceneBigHug() {
        let outs = OutPets()
        if outs.Count < 2 { AllOut(); Later(2.5) { [self] in SceneBigHug() }; return }
        let l: Pet = Lead()
        Begin(outs.ToArray())
        let lr = LineUp(ShowOrder(outs), l, 1.05)
        let all4 = outs.Count >= 4
        At(0) { l.Say(all4 ? "大家都到齊了！" : "大家過來～", 1.8) }
        At(4.8) {
            for p in outs { p.dir = p.Cx < (lr[0] + lr[1]) / 2 ? 1 : -1; p.ScenePose("hug", 3.4); p.Burst(5) }
            l.Say(all4 ? "四個一起，大～抱抱！" : "大抱抱！", 2.6)
        }
        At(8.6) { for p in outs { p.ScenePose("wave", 1.6) }; l.Say("Eh-oh! ♥", 1.6) }
        At(10.4) { }
    }

    static func SingLine(_ p: Pet) -> String {
        switch p.P.Id! {
        case "tinky": return "啦～啦～（丁丁跳舞）"
        case "dipsy": return "嘿～嘿～（打拍子）"
        case "laalaa": return "啦啦啦～♪"
        case "po": return "啦啦！再來一次！"
        default: break
        }
        return "♪～"
    }

    // ---------- 大家：拉拉起頭，一隻一隻加入唱歌跳舞 ----------
    func SceneSing() {
        let outs = OutPets()
        if outs.Count < 2 { AllOut(); Later(2.5) { [self] in SceneSing() }; return }
        let la = Get("laalaa")
        let starter: Pet = la != nil && la!.Out && outs.Contains(la!) ? la! : Lead()
        Begin(outs.ToArray())
        LineUp(ShowOrder(outs), Lead(), 1.8)
        At(0) { starter.Say("大家過來～我們來唱歌！", 2) }
        At(4.6) { for p in outs { p.FaceTo(starter); p.ScenePose("idle", 30) }; starter.ScenePose("sing", 30); starter.Say("啦啦啦～大家一起唱！♪", 2.4) }
        var d = 7.2
        for p in ShowOrder(outs) {
            if p === starter { continue }
            let pp = p
            At(d) { pp.ScenePose(pp.P.Id == "po" ? "spin" : "dance", 30); pp.Say(World.SingLine(pp), 2); pp.Mark(0) }
            d += 1.9
        }
        At(d + 0.4) { for p in outs { p.ScenePose(p.P.Id == "laalaa" ? "twirl" : "dance", 2.6); p.Mark(0); p.Mark(0) }; starter.Say("啦啦啦～大家一起～♪", 2.4) }
        At(d + 3.2) { for p in outs { p.ScenePose("wave", 1.6) }; starter.Say("再來一次！", 1.6) }
        At(d + 5.0) { }
    }

    // ---------- 大家：一、二、三，一起跌倒「哎喲！」 ----------
    func SceneFall() {
        let outs = OutPets()
        if outs.Count < 2 { AllOut(); Later(2.5) { [self] in SceneFall() }; return }
        let l: Pet = Lead()
        Begin(outs.ToArray())
        LineUp(ShowOrder(outs), l, 1.6)
        At(0) { l.Say("大家排好～", 1.6) }
        At(4.6) { for p in outs { p.ScenePose("idle", 30) }; l.Say("大家一起…一、二、三！", 2) }
        At(6.6) { for p in outs { p.ScenePose("hop", 0) } }
        At(7.3) { for p in outs { p.ScenePose("plop", 2.2); p.Mark(4) }; l.Say("哎喲！", 1.4) }
        At(9.5) { for p in outs { p.ScenePose("idle", 30) }; l.Say("嘻嘻嘻～大家都跌倒了", 1.8) }
        At(11.4) { l.Say("再來一次！", 1.6); for p in outs { p.ScenePose("hop", 0) } }
        At(12.8) { }
    }

    // ---------- 大家：吐司時間（吐司彈出來，屑屑掉滿地，吸吸來打掃）----------
    func SceneToast() {
        let outs = OutPets()
        if outs.Count < 2 { AllOut(); Later(2.5) { [self] in SceneToast() }; return }
        let l: Pet = Lead()
        Begin(outs.ToArray())
        let order = ShowOrder(outs)
        let lr = LineUp(order, l, 1.75)
        let cx = (lr[0] + lr[1]) / 2, foot = lr[2]
        At(0) { l.Say("吐司時間！🍞", 1.8) }
        At(4.2) { for p in outs { p.FaceTo(l); p.ScenePose("idle", 30) }; l.Say("吐司！吐司！吐司！", 2) }
        var d = 4.6
        for p in order {
            let pp = p
            At(d) { [self] in
                Toss(World.TOAST_ART, pp.P, PointF(cx, foot - 2 * Double(S)), pp.HandPoint(), 0.75, 170 * k, true, 0) { pp.HoldToast = true; pp.Say("吐司！", 0.65) }
            }
            d += 0.7
        }
        At(d + 0.8) { l.Say("好好吃～屑屑掉滿地了", 2) }
        At(d + 3.0) { order[order.Count - 1].Say("糟糕…要打掃了！", 1.8) }
        At(d + 3.6) { [self] in StartBot(cx, foot) }
        At(d + 4.6) { order[0].Say("吸吸來了！", 1.6); for p in outs { p.Mark(1) } }
        At(d + 6.8) { for p in outs { p.HoldToast = false; p.ClearCrumbs() }; l.Say("吸～吸～好乾淨！", 2) }
        At(d + 9.4) { for p in outs { p.ScenePose("wave", 1.6) }; l.Say("吸吸，謝謝你！Eh-oh!", 2) }
        At(d + 11.6) { }
    }

    // 吸吸：從比較近的螢幕邊滾進來，在大家腳邊來回吸，再滾出去
    func StartBot(_ cx: Double, _ foot: Double) {
        if Hidden { return }
        let wa = WA(cx, foot - 4)
        let ps = Math.Max(2, S * 3 / 4)
        let fromLeft = cx - Double(wa.Left) < Double(wa.Right) - cx
        let sx: Double = fromLeft ? Double(wa.Left - 8 * ps) : Double(wa.Right + 8 * ps)
        let ex: Double = fromLeft ? Double(wa.Right + 10 * ps) : Double(wa.Left - 10 * ps)
        let by: Double = foot - 4.5 * Double(ps) - Double(Math.Max(1, ps / 3))
        let owner = Pal.Get("tinky")!
        let b = NewProp(World.BOT_A, World.BOT_B, owner, ps, sx, by, false)
        let sweep = 90 * k, side: Double = fromLeft ? 1 : -1
        let t1 = Math.Min(3.0, Math.Abs(cx - sx) / (260 * k) + 0.6)
        b.Go(cx - side * sweep, by, t1, 0, nil)
         .Go(cx + side * sweep, by, 1.4, 0, nil)
         .Go(cx - side * sweep * 0.5, by, 1.0, 0, nil)
         .Go(cx + side * sweep * 0.3, by, 0.7, 0, nil)
         .Go(ex, by, Math.Min(3.0, Math.Abs(ex - cx) / (260 * k) + 0.6), 0, nil)
        b.Hold = 0
    }

    // ---------- 早上點名：丁丁！迪西！拉拉！小波！天線寶寶，Eh-oh! ----------
    func TubbyRollCall(_ ids: List<String>) {
        let order = List<Pet>()
        for id in Pal.LineupIds(lineup) { if ids.Contains(id) && Get(id) != nil { order.Add(Get(id)!) } }
        var d = 0.4
        for p in order {
            let pp = p
            Later(d) { [self] in if !pp.Out { BringOut(pp, false) } }
            Later(d + 0.7) { pp.Say(pp.P.Name + "！", 1.8) }
            d += 1.5
        }
        Later(d + 0.8) { [self] in
            for p in order { if p.Out && p.Grounded() { p.ScenePose("wave", 1.8); p.Say("Eh-oh!", 2) } }
            if order.Count > 0 { Lead().Say("天線寶寶，Eh-oh! ☀", 2.6) }
        }
    }

    // ---------- 天線寶寶說再見：一隻一隻揮手回櫃子；最後從櫃子裡再說一次再見 ----------
    func SceneByeBye(_ night: Bool) {
        let outs = ShowOrder(OutPets())
        if outs.Count == 0 { let l0: Pet = Lead(); l0.Say("天線寶寶說再見！再見～", 3); return }
        let lead: Pet = Lead()
        Begin(outs.ToArray())
        for p in outs { if p.Grounded() { p.ScenePose("idle", 60) } }
        var d = 0.2
        if night { for p in outs { let pp = p; At(d) { pp.Say(pp.L("nag"), 2.6) }; d += 2.8 } }
        At(d) { lead.Say("天線寶寶，說再見的時間到了～", 2.6) }
        d += 2.8
        for p in outs {
            let pp = p
            At(d) { pp.ScenePose("wave", 2.2); pp.Say(pp.P.Name + "說再見！👋", 2.2) }
            At(d + 1.7) { pp.InScene = false; if pp.Out { pp.StowToShelf(false) } }
            d += 2.6
        }
        let last = outs[outs.Count - 1]
        At(d + 0.4) { last.Say("天線寶寶說再見！再見～", 3) }
        At(d + 3.8) { [self] in let po: Pet = Get("po") ?? last; po.Say("……再見～（偷偷揮手）", 2.2) }
        At(d + 6.2) { }
    }
}
