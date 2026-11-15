// 51_original.swift — port of extension/desktop/DeskPals.Original.cs
// Desk Pals：續命小隊（半糖・醒醒・糰糰・貼貼）——原創角色。新安裝的預設一櫃，也是對外宣傳用的門面。
// 半糖＝珍奶（吸管撐竿跳、噗珍珠）、醒醒＝咖啡馬克杯（白天想睡、續杯就衝、晚上反而清醒）、
// 糰糰＝三角飯糰（海苔衝浪、飯匙打球、滾來滾去）、貼貼＝便利貼（貼在視窗上、寫便條、像紙一樣飄下來）。
// 像素圖的原始檔在 tools/original_art/final_art.py（C# 那份由 export_cs.py 產生；這裡的「像素圖」一段是照 C# 逐字轉過來的，別手改）。
import Foundation

// ================= 角色資料 =================
//@@IN Pal
    var Orig: Bool = false                     // 續命小隊
//@@END

extension Pal {
    static let Original = "original"
    static let OriginalName = "續命小隊"
    static let OriginalIds: [String] = ["boba", "coffee", "onigiri", "sticky"]

    static func OrigPals() -> List<Pal> { return List<Pal>([Boba(), Coffee(), Onigiri(), Sticky()]) }

    // 共用：算出頭頂超出 16 格的列數、頭和身體在 16 格框的哪一列
    static func OrigBase(_ id: String, _ name: String, _ headTopInArt: Int) -> Pal
    {
        let p = Pal()
        p.Id = id; p.Name = name; p.Orig = true; p.BallKind = "tennis"; p.Halo = Color.White; p.EyeRow = -1; p.HatCol = 0
        switch id
        {
        case "boba": ArtBoba(p)
        case "coffee": ArtCoffee(p)
        case "onigiri": ArtOnigiri(p)
        default: ArtSticky(p)
        }
        let total = p.Art["HEAD"].count + p.Art["BODY"].count + p.Art["LEGS_A"].count
        p.TopRows = Math.Max(0, total - 16)
        p.HeadTop = headTopInArt - p.TopRows
        p.BodyTop = p.Art["HEAD"].count - p.TopRows
        return p
    }

    // ---------------- 半糖：珍奶。甜甜的、愛揪團；粗吸管是她的招牌（撐竿跳、噗珍珠）----------------
    static func Boba() -> Pal
    {
        let p = OrigBase("boba", "半糖", 4)
        p.Move = "hop"; p.NightStyle = "sleepy"; p.NightBubble = 2
        p.Accent = C(0xC98E55); p.Panel = C(0xFFE6CC); p.HaloNight = C(0xFFC58F)
        p.HatRow = 1; p.ScarfRow = 8; p.GlassRow = 3; p.BadgeRow = 9; p.BadgeCol = 5; p.SideRow = 9
        p.Speed = 50
        p.Say("talk", "今天也要甜甜的～", "半糖剛剛好，人生也是～", "要不要揪一杯？我請客（騙你的）", "珍珠 Q 彈 Q 彈～", "微糖去冰，是我的人生態度", "喝口水再繼續吧 🥤", "你是我最喜歡的客人～")
        p.Say("talk_d", "冰塊都融化了…你也該回家了", "半糖要打烊了喔～", "下班了！明天再揪～", "天黑了，甜度降一點，早點睡", "再待下去珍珠都要變硬了…")
        p.Say("save", "存好了！甜度滿分 🥤", "Q 彈存檔～", "收好了！給你一顆珍珠當獎勵", "存檔成功～半糖少冰！")
        p.Say("save_d", "存好了～那就打烊吧", "存了！快回家喝杯熱的", "收好了…晚安～")
        p.Say("pats", "嘿嘿～好甜", "被摸摸，珍珠都在跳～", "你今天也很努力喔", "半糖最喜歡你了 ♥", "辛苦了，給你吸一口（不行）", "慢慢來，甜度剛好就好", "摸摸頭～你也是半糖的寶", "有我在，不會苦的")
        p.Say("pats_d", "嗯…半糖想打烊了", "摸完就回家喔～", "晚上喝太多會睡不著，回家吧", "你辛苦了，明天見～")
        p.Say("pats_hi", "能遇到你，是今天最甜的事", "你是我的全糖 ♥", "我們是最佳組合！", "每天都想跟你揪～")
        p.Say("hugs", "抱抱～冰冰涼涼的", "Q 彈抱抱！", "(つ´ω`)つ 半糖抱抱", "抱緊一點～珍珠會掉")
        p.Say("hugs_d", "抱抱…然後回家喔", "晚安抱抱～", "抱完就打烊囉")
        p.Say("knock", "叩叩！外送到了～🥤", "嗨嗨～玻璃外面的你！", "半糖可以出去玩嗎？", "（用吸管敲敲）叩叩～")
        p.Say("knock_d", "叩叩…打烊時間到囉", "還在加班？甜度不夠了啦", "回家吧～明天再揪")
        p.Say("newwin", "新視窗！去看看～", "咦～這是什麼新口味？", "半糖來了～")
        p.Say("newwin_d", "又開新的？明天再看嘛～", "打烊了，不要再開了啦")
        p.Say("hi", "嗨～我是半糖，甜度剛好的那種 🥤"); p.Say("hi_d", "嗨…打烊時間到了耶")
        p.Say("wake", "嗯…是你呀～半糖醒了 ♥"); p.Say("wake_d", "嗯…還沒打烊嗎？")
        p.Say("dizzy", "轉轉轉～珍珠都暈了 @@"); p.Say("dizzy_d", "暈…想打烊了…")
        p.Say("dizzy_ok", "好了好了～珍珠歸位！"); p.Say("dizzy_ok_d", "好了…回家吧")
        p.Say("tickle", "噗噗噗！珍珠噴出來了～", "哈哈好癢～Q 彈 Q 彈", "再搖下去要變奶泡了啦"); p.Say("tickle_d", "噗…最後一次喔")
        p.Say("pat10", "今天第 {n} 次摸摸了！甜度破表 ♥"); p.Say("pat10_d", "第 {n} 次了…摸完就回家喔")
        p.Say("levelup", "好感度 Lv{n}！半糖拿到「{u}」了～加料！"); p.Say("levelup_d", "Lv{n}…「{u}」…明天戴給你看")
        p.Say("missed", "你好久沒來點我了…珍珠都要硬掉了 🥺"); p.Say("missed_d", "好久沒摸了…明天要記得喔")
        p.Say("hover", "要點餐嗎？還是摸摸～")
        p.Say("seek", "咦？那是什麼？"); p.Say("seek_lost", "跑掉了…"); p.Say("seek_got", "抓到滑鼠了！吸～（不是啦）")
        p.Say("drag", "哇～要灑出來了！"); p.Say("throw", "珍珠～～飛～")
        p.Say("shelf_in", "半糖回櫃子冰著囉～"); p.Say("shelf_in_d", "打烊囉，半糖回櫃子睡覺")
        p.Say("shelf_out", "半糖出杯囉！🥤"); p.Say("shelf_out_d", "出來了…天黑了耶，你怎麼還在？")
        p.Say("ball_go", "球！好像一顆大珍珠！", "我來吸！", "等我～"); p.Say("ball_go_d", "最後一顆喔…")
        p.Say("ball_catch", "吸～噗！還你～", "好大的珍珠！噴回去～", "Q 彈回擊！"); p.Say("ball_catch_d", "噗…還你，該回家囉")
        p.Say("ball_end", "不玩了嗎？下次再揪 🥤"); p.Say("ball_end_d", "不玩了…那就打烊吧")
        p.Say("ball_far", "球滾太遠了啦～")
        p.Say("back", "半糖回來了～"); p.Say("back_d", "回來了…")
        p.Say("share_end", "分享完了～半糖回來囉")
        p.Say("welcome", "你回來了！要不要來一杯？♥"); p.Say("welcome_d", "你回來了…是要來打烊的吧？")
        p.Say("rest", "已經 {n} 分鐘了，起來喝口水、伸個懶腰～🥤"); p.Say("rest_d", "{n} 分鐘了…喝完這杯就下班吧")
        p.Say("night_on", "打烊時間到了～下班囉"); p.Say("night_off", "早安～今天也要甜甜的 ☀")
        p.Say("sleep", "半糖要瞇一下…"); p.Say("sleep_d", "晚安…你也去睡")
        p.Say("jump", "嘿！"); p.Say("nojump", "附近沒有可以跳的地方耶")
        p.Say("errors", "嗚…有 {n} 個錯誤，甜度不夠了"); p.Say("errors_d", "{n} 個錯誤…明天再修，回家吧")
        p.Say("errors_ok", "錯誤都清光了！加珍珠慶祝～"); p.Say("errors_ok_d", "修好了！那就打烊吧")
        p.Say("typing", "打好快！手搖都沒你快～", "加油加油！給你加料！", "鍵盤在跳舞耶 ♪"); p.Say("typing_d", "打這麼快，是想快點下班吧")
        p.Say("done", "{who} 做完了！來一杯慶祝 🥤"); p.Say("done_d", "{who} 做完了～那就下班吧")
        p.Say("wait", "{who} 在等你回答喔～"); p.Say("wait_d", "{who} 在等你…回完就回家")
        p.Say("ask", "{who} 有問題要問你喔 🙋"); p.Say("ask_d", "{who} 在問你…回完就下班")
        p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，要你按允許嗎？"); p.Say("stuck_tool_d", "{who} 停了 {n} 分鐘…按一下就回家")
        p.Say("stuck", "{who} 好像卡住了…{n} 分鐘沒動，去看看？"); p.Say("stuck_d", "{who} 卡住 {n} 分鐘了…看一眼就回家")
        p.Say("unstuck", "{who} 又動了！甜～"); p.Say("unstuck_d", "{who} 動了…")
        p.Say("tag", "上版成功！加珍珠慶祝 🎉"); p.Say("tag_dev", "測試機上好了～半糖少冰！"); p.Say("tag_prod", "正式機上線！全糖慶祝 🎉"); p.Say("tag_d", "上版成功…那就打烊吧")
        p.Say("late23", "好晚了…喝杯熱的去睡覺吧 🌙"); p.Say("late12", "午餐吃了沒？配一杯？"); p.Say("late15", "三點了！下午茶時間 🥤")
        p.Say("late_d", "早就打烊了喔"); p.Say("late_dd", "這麼晚了…回家睡覺")
        p.Say("g_late", "這麼晚還在？半糖陪你一下 🌙"); p.Say("g_morning", "早安～今天也要甜甜的 ☀"); p.Say("g_noon", "午安～吃飽了嗎？")
        p.Say("g_evening", "晚上了～辛苦了"); p.Say("g_day", "半糖出杯囉～🥤"); p.Say("g_d", "打烊時間了…你怎麼還在？")
        p.Say("app_browser", "在逛什麼？有新的飲料店嗎？"); p.Say("app_code", "寫 code 呀～半糖陪你"); p.Say("app_excel", "好多格子…像在算飲料錢")
        p.Say("app_ppt", "做簡報～記得配一杯"); p.Say("app_word", "在寫報告～慢慢來"); p.Say("app_chat", "有人揪飲料嗎？"); p.Say("app_files", "在找檔案嗎？")
        p.Say("app_other", "這是什麼？半糖也要看～")
        p.Say("app_code_d", "還在寫…打烊了啦"); p.Say("app_chat_d", "下班了，明天再回嘛"); p.Say("app_office_d", "這份明天做好不好～"); p.Say("app_other_d", "打烊時間到囉～")
        p.Say("s_birthday", "生日快樂！今天全糖加滿 🎂", "生日快樂～半糖請你喝一杯！")
        p.Say("s_cny", "新年快樂！紅包拿來買飲料 🧧", "恭喜發財，杯杯大杯！")
        p.Say("s_xmas", "聖誕快樂！🎄 熱的半糖好溫暖", "叮叮噹～聖誕限定口味！")
        p.Say("s_newyear", "新年快樂！今年也甜甜的 ✨")
        p.Say("s_halloween", "不給糖就…給我半糖！🎃", "我扮成…全糖！")
        p.Say("s_friday", "星期五了！下班揪一杯！", "小週末～甜度加倍！")
        p.Say("morning", "半糖！早安～🥤", "半糖報到！")
        p.Say("goodnight", "打烊囉～半糖回櫃子睡覺 🌙", "晚安～明天再揪！")
        p.Say("nag", "打烊了，回家吧～", "冰塊都融了…下班！", "回家喝杯熱的，早點睡")
        p.Say("react", "咦？", "怎麼了？", "珍珠嚇一跳！")
        p.Shared()
        return p
    }

    // ---------------- 醒醒：咖啡馬克杯。白天永遠沒睡醒，續杯才開機；晚上反而精神超好（但會叫你去睡）----------------
    static func Coffee() -> Pal
    {
        let p = OrigBase("coffee", "醒醒", 4)
        p.Move = "shuffle"; p.NightStyle = "wired"; p.NightBubble = 1
        p.Accent = C(0x2F8AA0); p.Panel = C(0xD6F0F4); p.HaloNight = C(0xA8D8F0)
        p.HatRow = 2; p.ScarfRow = 11; p.GlassRow = 6; p.BadgeRow = 11; p.BadgeCol = 4; p.SideRow = 9; p.NoGlasses = true
        p.Speed = 28
        p.Say("talk", "……還沒開機", "讓我先醒醒…", "續杯，拜託", "人生需要咖啡因", "我醒了。大概。", "早上的會議…是夢吧", "（打哈欠）呼啊～")
        p.Say("talk_d", "晚上我反而精神超好…但你要睡", "熬夜是我的工作，不是你的", "我是咖啡，我不用睡。你要。", "再撐下去，明天會更累喔", "關機。去睡。")
        p.Say("save", "存好了。（點頭）", "……存了。很好。", "存檔完成，可以續杯了吧", "穩。")
        p.Say("save_d", "存了就快睡", "存好了。關機吧。", "……存了。晚安。")
        p.Say("pats", "……（瞇眼）好舒服", "摸摸…讓我醒一點", "你今天也辛苦了", "嗯…再一下", "有你在，我比較醒", "慢慢來，我陪你熬…不對，陪你做", "被摸了，咖啡因 +1")
        p.Say("pats_d", "……摸完就去睡", "我不睏，但你很睏", "晚上的你需要的是床，不是我", "好啦…晚安")
        p.Say("pats_hi", "你比咖啡還讓我清醒", "跟你在一起，不用續杯", "我們是最佳搭檔", "……謝謝你每天陪我")
        p.Say("hugs", "抱抱…暖暖的", "小心燙～抱抱", "(つ´ω`)つ 熱咖啡抱抱", "……再抱一下，我還沒醒")
        p.Say("hugs_d", "抱完去睡", "熱抱抱…然後關機", "晚安抱抱")
        p.Say("knock", "叩叩…你醒著嗎？我不太醒", "（蒸氣貼玻璃）呼～", "可以出去曬太陽嗎…", "續杯！叩叩！")
        p.Say("knock_d", "叩叩。睡覺時間。", "我看到了，你還在熬夜", "關機。現在。")
        p.Say("newwin", "……又一個視窗", "新的？讓我醒醒再看", "（慢慢晃過去）")
        p.Say("newwin_d", "這個明天再開", "不准再開了，去睡")
        p.Say("hi", "……嗨。我是醒醒。還沒醒。☕"); p.Say("hi_d", "嗨！晚上我很清醒——但你該睡了")
        p.Say("wake", "……嗯？我沒睡，我在閉目養神"); p.Say("wake_d", "我沒睡！咖啡從來不睡！")
        p.Say("dizzy", "轉、轉太多圈…咖啡要灑了 @@"); p.Say("dizzy_d", "暈…但還是很清醒…")
        p.Say("dizzy_ok", "……好了。醒了。"); p.Say("dizzy_ok_d", "好了。去睡。")
        p.Say("tickle", "醒了醒了！我醒了！", "哈…哈啾！（蒸氣噴出來）", "別搖！會灑出來！"); p.Say("tickle_d", "……好癢。不准笑。")
        p.Say("pat10", "今天第 {n} 次了…我好像真的醒了 ♥"); p.Say("pat10_d", "第 {n} 次…晚上就別一直摸了，去睡")
        p.Say("levelup", "好感度 Lv{n}…拿到「{u}」。醒了，真的醒了"); p.Say("levelup_d", "Lv{n}。「{u}」。明天戴。")
        p.Say("missed", "你好幾天沒來了…我差點睡死 🥺"); p.Say("missed_d", "好久沒摸了…")
        p.Say("hover", "……是你在摸我嗎？")
        p.Say("seek", "……那是什麼？"); p.Say("seek_lost", "跑了。算了。"); p.Say("seek_got", "抓到了…可以回去睡了嗎")
        p.Say("drag", "哇、哇！會灑出來！"); p.Say("throw", "咖～啡～灑～了～")
        p.Say("shelf_in", "我回櫃子補眠了…"); p.Say("shelf_in_d", "回櫃子了。你也去睡。")
        p.Say("shelf_out", "……（被叫醒）我出來了"); p.Say("shelf_out_d", "出來了！晚上我精神很好——但你不該在")
        p.Say("ball_go", "球…好吧，我追", "等、等我醒一下", "我接…我接"); p.Say("ball_go_d", "最後一顆。")
        p.Say("ball_catch", "接到了…（咖啡濺出來）", "掉進杯子裡了，還你", "好球…我醒了"); p.Say("ball_catch_d", "還你。去睡。")
        p.Say("ball_end", "不玩了？太好了，補眠"); p.Say("ball_end_d", "不玩了就去睡")
        p.Say("ball_far", "太遠了…不想動")
        p.Say("back", "……我回來了"); p.Say("back_d", "回來了。")
        p.Say("share_end", "分享完了？我醒著喔（假的）")
        p.Say("welcome", "你回來了…我剛剛沒有睡"); p.Say("welcome_d", "你回來了。來關機的吧？")
        p.Say("rest", "{n} 分鐘了，站起來走走、喝口水 ☕（不是叫你續杯）"); p.Say("rest_d", "{n} 分鐘了…不要再熬了")
        p.Say("night_on", "下班了。……我反而醒了。"); p.Say("night_off", "早安…（還沒醒）☀")
        p.Say("sleep", "補眠…zZ"); p.Say("sleep_d", "我不睏…zZ…（睡著了）")
        p.Say("jump", "嘿…咻"); p.Say("nojump", "沒地方跳…也不想跳")
        p.Say("errors", "{n} 個錯誤。……我醒了。"); p.Say("errors_d", "{n} 個錯誤…明天精神好再修")
        p.Say("errors_ok", "錯誤清光了。可以續杯了"); p.Say("errors_ok_d", "修完了。去睡。")
        p.Say("typing", "打這麼快…你喝了幾杯？", "手速驚人，我醒了", "加油，咖啡因與你同在"); p.Say("typing_d", "打快一點，早點睡")
        p.Say("done", "{who} 做完了。……我醒著看到了"); p.Say("done_d", "{who} 做完了。你也收工吧")
        p.Say("wait", "{who} 在等你回答…"); p.Say("wait_d", "{who} 在等你。回完去睡")
        p.Say("ask", "{who} 在問你問題…"); p.Say("ask_d", "{who} 在問你。回完關機")
        p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，是不是在等你按允許？"); p.Say("stuck_tool_d", "{who} 停 {n} 分鐘了。按一下，然後睡")
        p.Say("stuck", "{who} 好像睡著了…{n} 分鐘沒動靜，跟我一樣"); p.Say("stuck_d", "{who} 卡 {n} 分鐘了。看一眼就去睡")
        p.Say("unstuck", "{who} 醒了。比我早"); p.Say("unstuck_d", "{who} 動了。")
        p.Say("tag", "上版成功。乾杯 ☕"); p.Say("tag_dev", "測試機上好了…續一杯慶祝"); p.Say("tag_prod", "正式機上線！我徹底醒了 🎉"); p.Say("tag_d", "上版成功。那現在可以睡了吧")
        p.Say("late23", "很晚了。咖啡因留給明天，你去睡 🌙"); p.Say("late12", "午餐…吃了嗎？我只喝咖啡（不要學）"); p.Say("late15", "三點…續杯時間 ☕")
        p.Say("late_d", "下班時間過了喔"); p.Say("late_dd", "這麼晚了。關機。睡覺。")
        p.Say("g_late", "這麼晚…我精神很好，但你不行 🌙"); p.Say("g_morning", "早…安…（開機中）☕"); p.Say("g_noon", "午安…吃飽會想睡，我懂")
        p.Say("g_evening", "晚上了…我開始醒了"); p.Say("g_day", "我出來了…慢慢的 ☕"); p.Say("g_d", "下班時間了。你為什麼還開著電腦？")
        p.Say("app_browser", "在逛什麼…我也看看"); p.Say("app_code", "寫 code…需要續杯嗎"); p.Say("app_excel", "好多數字…我眼睛花了")
        p.Say("app_ppt", "簡報…開會的時候我會睡著"); p.Say("app_word", "寫報告…慢慢來"); p.Say("app_chat", "有人找你…不是找我吧"); p.Say("app_files", "在找檔案…")
        p.Say("app_other", "……這是什麼？")
        p.Say("app_code_d", "還在寫？去睡"); p.Say("app_chat_d", "訊息明天再回"); p.Say("app_office_d", "這份明天做"); p.Say("app_other_d", "……關機吧")
        p.Say("s_birthday", "生日快樂…我醒著幫你唱 🎂", "生日快樂！今天我請你一杯")
        p.Say("s_cny", "新年快樂…紅包可以買很多咖啡 🧧", "恭喜發財，杯杯都醒")
        p.Say("s_xmas", "聖誕快樂…熱咖啡配聖誕節 🎄", "聖誕老公公也需要咖啡")
        p.Say("s_newyear", "新年快樂…今年也要醒著 ✨")
        p.Say("s_halloween", "不給糖就…給我咖啡 🎃", "我扮成…睡飽的人（很難）")
        p.Say("s_friday", "星期五…撐住，快醒了", "週末可以睡到自然醒")
        p.Say("morning", "醒醒…（還沒醒）報到 ☕", "醒醒報到…呼啊～")
        p.Say("goodnight", "晚安…我回櫃子補眠了", "……今天辛苦了。晚安。")
        p.Say("nag", "關機。睡覺。", "熬夜交給我，你去睡", "咖啡不能代替睡覺喔")
        p.Say("react", "……！", "醒、醒了！", "嗯？")
        p.Shared()
        return p
    }

    // ---------------- 糰糰：三角飯糰。憨厚、愛吃、力氣大，見人就問「吃飽沒？」----------------
    static func Onigiri() -> Pal
    {
        let p = OrigBase("onigiri", "糰糰", 0)
        p.Move = "waddle"; p.NightStyle = "sleepy"; p.NightBubble = 4
        p.Accent = C(0x45604F); p.Panel = C(0xE0ECD6); p.HaloNight = C(0xC8D8B8)
        p.HatRow = 4; p.ScarfRow = 10; p.GlassRow = 5; p.BadgeRow = 12; p.BadgeCol = 5; p.SideRow = 9
        p.Speed = 40
        p.Say("talk", "吃飽沒？", "嘿嘿，飯糰最強！", "今天的海苔很脆喔", "吃飽才有力氣寫 code！", "鮪魚口味是我的驕傲", "我圓圓的…啊不對，三角形的", "肚子餓的話，要說喔")
        p.Say("talk_d", "天黑了…該回家吃晚餐了", "晚餐吃了沒？回家吃熱的", "糰糰想睡了…你也回家吧", "吃飽、睡飽，明天再拚", "海苔要軟掉了…下班吧")
        p.Say("save", "存好了！嘿嘿", "收好了，跟海苔包一樣緊", "存檔！飯糰力 +1", "穩穩的～")
        p.Say("save_d", "存好了！回家吃飯吧", "存了～那就下班吧", "收好了…晚安")
        p.Say("pats", "嘿嘿～好開心", "飯粒都在笑了", "你今天吃飽了嗎？", "辛苦了，摸摸～", "糰糰最喜歡你了 ♥", "加油！吃飽再拚！", "慢慢來，我一直都在", "被摸摸，海苔都捲起來了")
        p.Say("pats_d", "嗯…糰糰想睡了", "摸完就回家吃飯喔", "你已經很努力了，休息吧", "晚安…明天見")
        p.Say("pats_hi", "你是我最重要的配料 ♥", "跟你在一起，每天都飽飽的", "我們是最佳拍檔！", "我會一直陪你的！")
        p.Say("hugs", "大抱抱！軟綿綿的", "抱抱～（飯粒黏到你了）", "(つ´ω`)つ 飯糰抱抱", "抱緊緊！")
        p.Say("hugs_d", "抱抱…然後回家吃飯", "晚安抱抱～", "抱完就下班囉")
        p.Say("knock", "叩叩！吃飽沒？👀", "嗨～玻璃外面的你！", "糰糰可以出去玩嗎？", "（臉貼玻璃）飯粒黏上去了")
        p.Say("knock_d", "叩叩…該回家吃晚餐了", "還在加班？肚子會餓喔", "回家吧～明天再拚")
        p.Say("newwin", "新視窗！我去看看！", "咦？那是什麼？", "糰糰出動！")
        p.Say("newwin_d", "又開新的？明天再看吧", "天黑了，關掉吧")
        p.Say("hi", "嗨！我是糰糰，吃飽沒？🍙"); p.Say("hi_d", "嗨…天黑了耶，吃晚餐了嗎？")
        p.Say("wake", "嗯…是你呀！吃飽沒？"); p.Say("wake_d", "嗯…糰糰在睡覺…你也去睡")
        p.Say("dizzy", "滾太多圈了…頭暈 @@"); p.Say("dizzy_d", "暈…想睡…")
        p.Say("dizzy_ok", "好了！嘿嘿"); p.Say("dizzy_ok_d", "好了…回家吧")
        p.Say("tickle", "咕嚕咕嚕～滾滾滾！", "哈哈好癢！飯粒要掉了", "嘿嘿嘿～再一次！"); p.Say("tickle_d", "嘿…最後一次喔")
        p.Say("pat10", "今天第 {n} 次摸摸！糰糰好開心 ♥"); p.Say("pat10_d", "第 {n} 次了…摸完回家吃飯喔")
        p.Say("levelup", "好感度 Lv{n}！糰糰拿到「{u}」了！"); p.Say("levelup_d", "Lv{n}…「{u}」…明天戴給你看")
        p.Say("missed", "你好幾天沒來了…糰糰都要變冷飯了 🥺"); p.Say("missed_d", "好久沒摸了…明天要記得喔")
        p.Say("hover", "嘿嘿，你在摸我嗎？")
        p.Say("seek", "咦？那是什麼？"); p.Say("seek_lost", "跑掉了…"); p.Say("seek_got", "抓到了！糰糰最強！")
        p.Say("drag", "哇～飯粒要掉了！"); p.Say("throw", "咕嚕咕嚕咕嚕～～")
        p.Say("shelf_in", "糰糰回櫃子保溫囉～"); p.Say("shelf_in_d", "回櫃子睡覺了，晚安")
        p.Say("shelf_out", "糰糰出爐！吃飽沒？"); p.Say("shelf_out_d", "出來了…天黑了，你吃晚餐了嗎？")
        p.Say("ball_go", "球！我來打！", "飯匙準備好了！", "看我的！"); p.Say("ball_go_d", "最後一球喔…")
        p.Say("ball_catch", "殺球！還你～", "飯匙回擊！", "嘿嘿，好球吧？"); p.Say("ball_catch_d", "打回去…然後回家")
        p.Say("ball_end", "不玩了？下次再打！"); p.Say("ball_end_d", "不玩了…回家吃飯吧")
        p.Say("ball_far", "球滾太遠了～")
        p.Say("back", "糰糰回來了！"); p.Say("back_d", "回來了…")
        p.Say("share_end", "分享完了？糰糰回來了！")
        p.Say("welcome", "你回來了！吃飽沒？"); p.Say("welcome_d", "你回來了…晚餐吃了嗎？")
        p.Say("rest", "已經 {n} 分鐘了！起來走走、喝口水、吃點東西 🍙"); p.Say("rest_d", "{n} 分鐘了…回家吃飯吧")
        p.Say("night_on", "天黑了…該回家吃晚餐囉"); p.Say("night_off", "早安！早餐吃了沒？☀")
        p.Say("sleep", "吃飽睡覺覺…zZ"); p.Say("sleep_d", "晚安…你也去睡")
        p.Say("jump", "嘿咻！"); p.Say("nojump", "附近沒有可以跳的地方耶")
        p.Say("errors", "有 {n} 個錯誤！糰糰來打！"); p.Say("errors_d", "{n} 個錯誤…明天吃飽再修")
        p.Say("errors_ok", "錯誤都打光了！嘿嘿"); p.Say("errors_ok_d", "修好了！回家吃飯吧")
        p.Say("typing", "打好快！吃飽的力量！", "加油加油！", "手指好有力～"); p.Say("typing_d", "打快一點，早點回家吃飯")
        p.Say("done", "{who} 做完了！吃個飯慶祝！"); p.Say("done_d", "{who} 做完了～回家吃飯吧")
        p.Say("wait", "{who} 在等你回答喔～"); p.Say("wait_d", "{who} 在等你…回完回家吃飯")
        p.Say("ask", "{who} 有問題要問你！"); p.Say("ask_d", "{who} 在問你…回完就下班")
        p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，要不要按一下？"); p.Say("stuck_tool_d", "{who} 停 {n} 分鐘…按一下就回家")
        p.Say("stuck", "{who} 好像卡住了…{n} 分鐘了，是不是餓了？"); p.Say("stuck_d", "{who} 卡 {n} 分鐘…看一下就回家")
        p.Say("unstuck", "{who} 動了！吃飽了吧"); p.Say("unstuck_d", "{who} 動了…")
        p.Say("tag", "上版成功！加一顆滷蛋慶祝 🎉"); p.Say("tag_dev", "測試機上好了！嘿嘿"); p.Say("tag_prod", "正式機上線！今晚加菜 🎉"); p.Say("tag_d", "上版成功…回家吃飯吧")
        p.Say("late23", "好晚了…宵夜少吃，早點睡 🌙"); p.Say("late12", "午餐時間！吃飽沒？"); p.Say("late15", "下午了～肚子餓的話吃點東西")
        p.Say("late_d", "下班時間過了喔"); p.Say("late_dd", "好晚了…回家睡覺")
        p.Say("g_late", "這麼晚了…糰糰陪你 🌙"); p.Say("g_morning", "早安！早餐吃了沒？☀"); p.Say("g_noon", "午安～吃飽沒？")
        p.Say("g_evening", "晚上了！晚餐吃了沒？"); p.Say("g_day", "糰糰來了！吃飽沒？🍙"); p.Say("g_d", "天黑了…你怎麼還在？")
        p.Say("app_browser", "在看什麼？美食嗎？"); p.Say("app_code", "寫 code！糰糰幫你加油"); p.Say("app_excel", "好多格子，像便當盒")
        p.Say("app_ppt", "做簡報～加油！"); p.Say("app_word", "寫文件～慢慢來"); p.Say("app_chat", "有人約吃飯嗎？"); p.Say("app_files", "在找東西嗎？我幫你")
        p.Say("app_other", "這是什麼？")
        p.Say("app_code_d", "還在寫…回家吃飯吧"); p.Say("app_chat_d", "明天再回吧"); p.Say("app_office_d", "明天再做也可以的"); p.Say("app_other_d", "回家吧～")
        p.Say("s_birthday", "生日快樂！今天加兩顆滷蛋 🎂", "生日快樂！糰糰請你吃大餐！")
        p.Say("s_cny", "新年快樂！年菜吃飽飽 🧧", "恭喜發財！紅包換飯糰！")
        p.Say("s_xmas", "聖誕快樂！🎄", "聖誕大餐要吃飽喔")
        p.Say("s_newyear", "新年快樂！今年也要吃飽飽 ✨")
        p.Say("s_halloween", "不給糖就…給我飯糰！🎃", "我扮成…御飯糰（本來就是）")
        p.Say("s_friday", "星期五了！週末吃好料！", "快放假了～嘿嘿")
        p.Say("morning", "糰糰！早餐吃了沒？", "糰糰報到！")
        p.Say("goodnight", "晚安～糰糰回櫃子保溫", "今天辛苦了，晚安！")
        p.Say("nag", "回家吃晚餐吧", "下班了！吃飽睡飽", "天黑了，回家囉")
        p.Say("react", "咦？", "怎麼了？", "嘿？")
        p.Shared()
        return p
    }

    // ---------------- 貼貼：便利貼。黏人、細心、什麼都幫你記下來（有點容易緊張）----------------
    static func Sticky() -> Pal
    {
        let p = OrigBase("sticky", "貼貼", 2)
        p.Move = "flutter"; p.NightStyle = "sleepy"; p.NightBubble = 3
        p.Accent = C(0xC9A62A); p.Panel = C(0xE6E2F6); p.HaloNight = C(0xF0E0A0)
        p.HatRow = 3; p.ScarfRow = 10; p.GlassRow = 5; p.BadgeRow = 12; p.BadgeCol = 5; p.SideRow = 10
        p.Speed = 45
        p.Say("talk", "貼貼～", "有什麼要我記下來的嗎？", "別忘了喝水喔！", "今天的待辦，一起完成！", "我的背面有黏膠，所以很黏人", "截止日我都記得喔", "做完一件，撕掉一張～")
        p.Say("talk_d", "今天的待辦…明天再說", "下班！我已經寫好了", "回家吧～我幫你記著", "天黑了，黏膠也要休息", "明天的事，我都記下來了")
        p.Say("save", "存好了！我也記下來了 ✍", "存檔 ✓ 打勾！", "收好了～貼貼！", "記住了！")
        p.Say("save_d", "存好了～下班吧", "存了！我幫你記著，回家吧", "收好了…晚安")
        p.Say("pats", "貼貼～♥", "嘿嘿，被摸摸了", "你今天也很努力喔", "辛苦了，我都記得", "貼緊緊～", "慢慢來，一件一件做", "有我在，不會忘記的", "被摸摸，角都翹起來了")
        p.Say("pats_d", "嗯…貼貼想睡了", "摸完就回家喔", "你已經很棒了，剩下明天", "晚安貼貼～")
        p.Say("pats_hi", "想一直貼著你 ♥", "你是我最重要的待辦事項", "我們是最佳拍檔！", "每天都要一起喔")
        p.Say("hugs", "貼貼～！", "抱緊緊，黏住了！", "(つ´ω`)つ 貼貼", "抱抱～撕不下來了")
        p.Say("hugs_d", "貼貼…然後回家", "晚安貼貼～", "抱完就下班囉")
        p.Say("knock", "叩叩！有事要提醒你！👀", "嗨～玻璃外面的你！", "我可以貼在你的螢幕上嗎？", "（貼在玻璃上）黏住了～")
        p.Say("knock_d", "叩叩…下班時間到了", "還在加班？我要寫你名字了", "回家吧～待辦明天再做")
        p.Say("newwin", "新視窗！要記下來嗎？", "咦？新的！", "貼過去看看～")
        p.Say("newwin_d", "又開新的？明天再看嘛", "天黑了，不要再開了")
        p.Say("hi", "嗨！我是貼貼，什麼都幫你記 📝"); p.Say("hi_d", "嗨…下班時間到了喔")
        p.Say("wake", "嗯…是你呀！有什麼要記的嗎？"); p.Say("wake_d", "嗯…貼貼在睡覺…你也去睡")
        p.Say("dizzy", "轉轉轉～黏膠要掉了 @@"); p.Say("dizzy_d", "暈…想睡…")
        p.Say("dizzy_ok", "好了！重新貼好！"); p.Say("dizzy_ok_d", "好了…回家吧")
        p.Say("tickle", "哈哈好癢！角翹起來了～", "貼貼貼貼～！", "不要撕我啦～嘻嘻"); p.Say("tickle_d", "嘻…最後一次喔")
        p.Say("pat10", "今天第 {n} 次摸摸！我記下來了 ♥"); p.Say("pat10_d", "第 {n} 次了…摸完就回家喔")
        p.Say("levelup", "好感度 Lv{n}！貼貼拿到「{u}」了！記下來！"); p.Say("levelup_d", "Lv{n}…「{u}」…明天戴給你看")
        p.Say("missed", "你好幾天沒來了…我的黏膠都快乾了 🥺"); p.Say("missed_d", "好久沒摸了…明天要記得喔")
        p.Say("hover", "你在摸我嗎？貼貼～")
        p.Say("seek", "咦？那是什麼？"); p.Say("seek_lost", "跑掉了…記下來"); p.Say("seek_got", "抓到滑鼠了！貼住！")
        p.Say("drag", "哇～要被風吹走了！"); p.Say("throw", "飄～～～")
        p.Say("shelf_in", "貼貼回櫃子囉～"); p.Say("shelf_in_d", "回櫃子睡覺了，晚安")
        p.Say("shelf_out", "貼貼出來了！有事要提醒嗎？"); p.Say("shelf_out_d", "出來了…下班時間到了耶")
        p.Say("ball_go", "球！我來黏！", "等我～", "看我的！"); p.Say("ball_go_d", "最後一球喔…")
        p.Say("ball_catch", "黏住了！撕下來還你～", "接到了！貼貼！", "嘿嘿，黏得好吧"); p.Say("ball_catch_d", "還你…回家吧")
        p.Say("ball_end", "不玩了嗎？我記下來，下次再玩"); p.Say("ball_end_d", "不玩了…回家吧")
        p.Say("ball_far", "球跑太遠了～")
        p.Say("back", "貼貼回來了！"); p.Say("back_d", "回來了…")
        p.Say("share_end", "分享完了～貼貼回來了")
        p.Say("welcome", "你回來了！我都幫你記著喔"); p.Say("welcome_d", "你回來了…是要下班了嗎？")
        p.Say("rest", "已經 {n} 分鐘了！提醒：起來喝水、伸展一下 📝"); p.Say("rest_d", "{n} 分鐘了…今天的待辦先到這裡吧")
        p.Say("night_on", "下班時間到了！待辦明天再說"); p.Say("night_off", "早安！今天的待辦我都寫好了 ☀")
        p.Say("sleep", "貼貼睡一下…zZ"); p.Say("sleep_d", "晚安…你也去睡")
        p.Say("jump", "飄～"); p.Say("nojump", "附近沒有可以貼的地方耶")
        p.Say("errors", "有 {n} 個錯誤！我先記下來！"); p.Say("errors_d", "{n} 個錯誤…記下來了，明天修")
        p.Say("errors_ok", "錯誤清光了！打勾 ✓"); p.Say("errors_ok_d", "修好了！回家吧")
        p.Say("typing", "打好快！我記都記不完！", "加油加油！", "手指在飛耶！"); p.Say("typing_d", "打快一點，早點下班")
        p.Say("done", "{who} 做完了！打勾 ✓"); p.Say("done_d", "{who} 做完了～打勾，下班！")
        p.Say("wait", "{who} 在等你回答！記得喔"); p.Say("wait_d", "{who} 在等你…回完就回家")
        p.Say("ask", "{who} 有問題要問你！別忘了！"); p.Say("ask_d", "{who} 在問你…回完就下班")
        p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，是不是在等你按允許？"); p.Say("stuck_tool_d", "{who} 停 {n} 分鐘了…按一下就回家")
        p.Say("stuck", "{who} 好像卡住了…{n} 分鐘了，去看看？"); p.Say("stuck_d", "{who} 卡 {n} 分鐘了…看一下就回家")
        p.Say("unstuck", "{who} 又動了！打勾 ✓"); p.Say("unstuck_d", "{who} 動了…")
        p.Say("tag", "上版成功！打勾 ✓🎉"); p.Say("tag_dev", "測試機上好了！記下來！"); p.Say("tag_prod", "正式機上線！今天的待辦全打勾 🎉"); p.Say("tag_d", "上版成功…那就下班吧")
        p.Say("late23", "很晚了…提醒：該睡了 🌙"); p.Say("late12", "提醒：午餐時間！"); p.Say("late15", "提醒：下午三點，喝水時間 💧")
        p.Say("late_d", "提醒：下班時間過了"); p.Say("late_dd", "提醒：這麼晚了，關機睡覺")
        p.Say("g_late", "這麼晚了…貼貼陪你 🌙"); p.Say("g_morning", "早安！今天的待辦我寫好了 ☀"); p.Say("g_noon", "午安～午餐吃了嗎？")
        p.Say("g_evening", "晚上了～辛苦了"); p.Say("g_day", "貼貼來了！有事要提醒嗎？📝"); p.Say("g_d", "下班時間了…你怎麼還在？")
        p.Say("app_browser", "在逛網頁？要記下什麼嗎？"); p.Say("app_code", "寫 code！TODO 我幫你記"); p.Say("app_excel", "好多格子…我也是方的")
        p.Say("app_ppt", "做簡報？我幫你記重點"); p.Say("app_word", "在寫報告～截止日我記得"); p.Say("app_chat", "有人找你？要回喔！"); p.Say("app_files", "在找檔案？我記得你上次放在…")
        p.Say("app_other", "這是什麼？記下來！")
        p.Say("app_code_d", "還在寫？TODO 明天再做"); p.Say("app_chat_d", "明天再回吧，我記著"); p.Say("app_office_d", "這份明天做也來得及"); p.Say("app_other_d", "下班了喔～")
        p.Say("s_birthday", "生日快樂！今天的待辦只有一件：開心 🎂", "生日快樂！我早就記在行事曆了")
        p.Say("s_cny", "新年快樂！紅包記得收好 🧧", "恭喜發財！")
        p.Say("s_xmas", "聖誕快樂！🎄", "聖誕願望清單我幫你寫好了")
        p.Say("s_newyear", "新年快樂！新年新希望寫好了嗎？✨")
        p.Say("s_halloween", "不給糖就…把你貼起來！🎃", "我扮成…待辦清單（好可怕）")
        p.Say("s_friday", "星期五了！週末的待辦只有休息", "快放假了！撐住！")
        p.Say("morning", "貼貼！今天的待辦寫好了！", "貼貼報到！")
        p.Say("goodnight", "晚安～貼貼回櫃子了 📝", "今天辛苦了，晚安！")
        p.Say("nag", "提醒：下班時間到了", "回家吧～我幫你記著", "待辦明天再做，現在去休息")
        p.Say("react", "！", "咦？", "要記下來嗎？")
        p.Shared()
        return p
    }

    // ==== 像素圖（由 tools/original_art/final_art.py 產生，別手改）====
    static func ArtBoba(_ p: Pal)
    {
        p.Col("F", 0xFF8FB5, 0xC77AA0)
        p.Col("G", 0xF0B248, 0xC08A40)
        p.Col("H", 0xF3D2A8, 0xC2A488)
        p.Col("M", 0xC98E55, 0x946A44)
        p.Col("N", 0xBFA27A, 0x8E785C)
        p.Col("O", 0xB8742A, 0x8A5420)
        p.Col("Q", 0xA58472, 0x7A6458)
        p.Col("b", 0xF79A9A, 0xC07A86)
        p.Col("e", 0x2A1810, 0x1E120E)
        p.Col("f", 0xFFFFFF, 0xE6DDF0)
        p.Col("h", 0xFBEBD4, 0xD8C2AE)
        p.Col("j", 0x2E1C16, 0x1E120E)
        p.Col("k", 0x4A2C1C, 0x2E1A14)
        p.Col("m", 0xE8B57C, 0xB98A62)
        p.Col("n", 0xE2C8A0, 0xB49E80)
        p.Col("o", 0x7A3A2A, 0x5A2A20)
        p.Col("s", 0xFF7AAE, 0xD86A9A)
        p.Col("w", 0xFFFFFF, 0xF0E8F4)
        p.Col("x", 0xFF6F9C, 0xC85A80)
        p.Col("z", 0xD2508A, 0xA84878)
        p.Art["HEAD"] = ["...........sz..", "..........sz...", ".........sz....", "........sz.....", "kkkkkkkkszkkkkk", "kfFfFfFszFfFfFk", "kkkkkkkkkkkkkkk", ".khmmmmmmmmmMk.", ".khmwemmmwemMk.", ".khmeemmmeemMk.", ".khbmmooommbMk.", ".khmmmmxmmmmMk."]
        p.Art["HEAD_UP"] = ["...........sz..", "..........sz...", ".........sz....", "........sz.....", "kkkkkkkkszkkkkk", "kfFfFfFszFfFfFk", "kkkkkkkkkkkkkkk", ".khmmmmmmmmmMk.", "kkhmwemmmwemMkk", "kkhmeemmmeemMkk", ".khbmmooommbMk.", ".khmmmmxmmmmMk."]
        p.Art["BODY"] = ["kkhmmmmmmmmmMkk", ".khmmmmmmmmmMk.", ".khjQmjQmjQmMk.", ".khjjmjjmjjmMk.", ".kHHHHHHHHHHHk.", "..kkkkkkkkkkk.."]
        p.Art["BODY_J"] = ["kkhmmmmmmmmmMkk", ".khjQmjQmjQmMk.", ".khjjmjjmjjmMk.", ".khmmmmmmmmmMk.", ".kHHHHHHHHHHHk.", "..kkkkkkkkkkk.."]
        p.Art["BODY_UP"] = [".khmmmmmmmmmMk.", ".khmmmmmmmmmMk.", ".khjQmjQmjQmMk.", ".khjjmjjmjjmMk.", ".kHHHHHHHHHHHk.", "..kkkkkkkkkkk.."]
        p.Art["BODY_HUG"] = ["kkhmmmmmmmmmMkk", "kkhmmmmmmmmmMkk", ".khjQmjQmjQmMk.", ".khjjmjjmjjmMk.", ".kHHHHHHHHHHHk.", "..kkkkkkkkkkk.."]
        p.Art["LEGS_A"] = ["...kk.....kk...", "...kk.....kk..."]
        p.Art["LEGS_B"] = ["..kk.......kk..", "..kk.......kk.."]
        p.Art["LEGS_SIT"] = ["..kkk.....kkk..", "..............."]
        p.Art["F_SLEEPY"] = [".khmmmmmmmmmMk.", ".khmkkmmmkkmMk.", ".khbmmmmmmmbMk.", ".khmmmmommmmMk."]
        p.Art["F_HAPPY"] = [".khmemmmmmemMk.", ".khememmmemeMk.", ".khbmmooommbMk.", ".khmmmmxmmmmMk."]
        p.Art["F_DIZZY"] = [".khmemmmmmemMk.", ".khmmemmmemmMk.", ".khbemmmmmebMk.", ".khmmmooommmMk."]
        p.Art["F_SQUISH"] = [".khmkkmmmkkmMk.", ".khmmkmmmkmmMk.", ".khbmmooommbMk.", ".khmmmooommmMk."]
        p.Art["F_BLOW"] = [".khmwemmmwemMk.", ".khmeemmmeemMk.", ".khbmmmommmbMk.", ".khmmmmommmmMk."]
        p.Art["F_WORRY"] = [".khmwemmmwemMk.", ".khmeemmmeemMk.", ".khbmmmommmbMk.", ".khmmmomommmMk."]
        p.Art["PEARL"] = [".jj.", "jQjj", "jjjj", ".jj."]
        p.Art["CHICKEN"] = [".GOGGG..", "GGGOGGG.", "GOGGGOGk", ".GGOGGGk", "knnnnnnk", "knNnnNnk", "knnnnnnk", ".kkkkkk."]
        p.Art["DRINK"] = ["....s.", "...s..", "kkkskk", "kfFfFk", "kmmmMk", "kjmjMk", ".kkkk."]
        p.Art["TAG"] = [".kkkkkkkkkkkk", "kSSSSSSSSSSSk", "kSSSWSWSWWWSk", "kSSSWSWSWSWSk", "kwSSWWWSWWWSk", "kSSSSSWSSSWSk", "kSSSSSWSWWWSk", "kSSSSSSSSSSSk", ".kkkkkkkkkkkk"]
        p.FaceRow = 8
    }
    static func ArtCoffee(_ p: Pal)
    {
        p.Col("C", 0x5A3018, 0x402212)
        p.Col("G", 0x9FB8C8, 0x7088A0)
        p.Col("O", 0xBC7A30, 0x8A5428)
        p.Col("T", 0x2F8AA0, 0x245E70)
        p.Col("V", 0xC8D4E2, 0x8E98B8)
        p.Col("b", 0xF2A0A0, 0xB87A8A)
        p.Col("c", 0x8A5432, 0x6A4026)
        p.Col("d", 0x2A5A6E, 0x14303E)
        p.Col("e", 0x1E2A3A, 0x0E1420)
        p.Col("g", 0xDCEBF2, 0xA8B8D0)
        p.Col("k", 0x1E2A3A, 0x101824)
        p.Col("l", 0xA8E6EE, 0x7CB4C4)
        p.Col("o", 0xF2B25E, 0xC08A50)
        p.Col("p", 0xFFE2C8, 0xD8C0A8)
        p.Col("t", 0x4FB6C8, 0x3A8A9E)
        p.Col("v", 0xF2F6FA, 0xC8D0E8)
        p.Col("w", 0xFFFFFF, 0xE8F0F8)
        p.Col("z", 0x6A4ADA, 0x5A3ABA)
        p.Art["HEAD"] = [".....v.....v.....", "....v.....v......", ".....V.....V.....", "......V.....V....", "..kkkkkkkkkkkk...", ".kwcccccccccCwk..", ".kwccpppcccCCwk..", ".kwwCCpcccCCwwk..", ".kltttttttttttkkk", ".klttttttttttTkTk", ".klttwwttttwwtkTk", ".klttetttttettkTk"]
        p.Art["HEAD_UP"] = [".....v.....v.....", "....v.....v......", ".....V.....V.....", "......V.....V....", "..kkkkkkkkkkkk...", ".kwcccccccccCwk..", ".kwccpppcccCCwk..", ".kwwCCpcccCCwwk..", "kkltttttttttttkkk", "ktltttttttttTTkTk", "kklttwwttttwwtkTk", ".klttetttttettkTk"]
        p.Art["STEAM_B"] = ["....v.....v......", ".....v.....v.....", "....V.....V......", ".....V.....V....."]
        p.Art["BODY"] = [".kltbtttttttbtkkk", ".kltttttkktttTk..", ".klttttttttttTk..", "..kTTTTTTTTTTk...", "...kkkkkkkkkk...."]
        p.Art["BODY_UP"] = [".kltbtttttttbtkkk", ".kltttttkktttTk..", ".klttttttttttTk..", "..kTTTTTTTTTTk...", "...kkkkkkkkkk...."]
        p.Art["BODY_HUG"] = [".kktbtttttttbkkkk", ".ktkkttttttkkTk..", ".klttttttttttTk..", "..kTTTTTTTTTTk...", "...kkkkkkkkkk...."]
        p.Art["ARMS_UP_L"] = ["k.", "tk", "kt"]
        p.Art["LEGS_A"] = ["....kk....kk.....", "....kk....kk....."]
        p.Art["LEGS_B"] = ["...kk......kk....", "...kk......kk...."]
        p.Art["LEGS_SIT"] = ["...kkk....kkk....", "................."]
        p.Art["F_WIDE"] = [".klttwettttwetkTk", ".kltteetttteetkTk", ".kltbtttttttbtkkk"]
        p.Art["F_PANDA"] = [".klttwettttwetkTk", ".kltteetttteetkTk", ".kltbddttttddtkkk"]
        p.Art["F_SLEEPY"] = [".kltttttttttttkTk", ".klttkkttttkktkTk", ".kltbtttttttbtkkk"]
        p.Art["F_HAPPY"] = [".kltteetttteetkTk", ".kltettettettekTk", ".kltbtttttttbtkkk"]
        p.Art["F_DIZZY"] = [".kltteetttttetkTk", ".kltttetttteetkTk", ".kltbtttttttbtkkk"]
        p.Art["F_SQUISH"] = [".klttettttttetkTk", ".kltttettttettkTk", ".kltbtttttttbtkkk"]
        p.Art["POT"] = ["..kkkk...", ".kkddkk..", "kggggggkk", "kgCCCCgk.k", "kgCCCCgk.k", "kgggggkk..", ".kkkkkk..."]
        p.Art["CROISSANT"] = ["..kkkk..", ".kooOok.", "koOooOok", "kOooOooO", ".kkkkkk."]
        p.FaceRow = 10
    }
    static func ArtOnigiri(_ p: Pal)
    {
        p.Col("G", 0x6AB04C, 0x4A8040)
        p.Col("N", 0x45604F, 0x2E4036)
        p.Col("O", 0x9A5420, 0x6E3C18)
        p.Col("X", 0x8A3E26, 0x62301E)
        p.Col("b", 0xF4A0A0, 0xB87A90)
        p.Col("e", 0x2B2B33, 0x16161C)
        p.Col("g", 0xE3DCC8, 0xB4B0C4)
        p.Col("k", 0x2B2B33, 0x16161C)
        p.Col("m", 0xC04050, 0x903040)
        p.Col("n", 0x22302A, 0x141C18)
        p.Col("o", 0xD88A3C, 0xA86A34)
        p.Col("r", 0xFCF9F0, 0xD6D4E2)
        p.Col("u", 0xE8607E, 0xB04A68)
        p.Col("w", 0xFFFFFF, 0xECEAF6)
        p.Col("x", 0xB85A3A, 0x8A4430)
        p.Col("y", 0xFFD84A, 0xD8B040)
        p.Art["HEAD"] = [".......kk.......", "......krrk......", ".....krrrrk.....", "....krrgrrrk....", "...krrrrrrrrk...", "...krrrrrrgrk...", "..krreerreerrk..", "..krreerreerrk..", ".krrbrrrrrrbrrk.", ".krrrrrmmrrrrrk."]
        p.Art["HEAD_UP"] = [".......kk.......", "......krrk......", ".....krrrrk.....", ".kk.krrgrrrk.kk.", "krrkrrrrrrrrkrrk", ".kkkrrrrrrgrkkk.", "..krreerreerrk..", "..krreerreerrk..", ".krrbrrrrrrbrrk.", ".krrrrrmmrrrrrk."]
        p.Art["BODY"] = ["krrrrrrrrrrrrrrk", "knnnnnnnnnnnnnnk", "knNnnnnnnnnnNnnk", ".kkkkkkkkkkkkkk."]
        p.Art["BODY_BARE"] = ["krrrrrrrrrrrrrrk", "krrrrgrrrrrrrgrk", "krrgrrrrrgrrrrrk", ".kkkkkkkkkkkkkk."]
        p.Art["BODY_HUG"] = ["kkkrrrrrrrrrrkkk", "krrkknnnnnnkkrrk", "knNnnnnnnnnnNnnk", ".kkkkkkkkkkkkkk."]
        p.Art["LEGS_A"] = ["....kk....kk....", "....kk....kk...."]
        p.Art["LEGS_B"] = ["...kk......kk...", "...kk......kk..."]
        p.Art["LEGS_SIT"] = ["...kkk....kkk...", "................"]
        p.Art["F_SLEEPY"] = ["..krrrrrrrrrrk..", "..krkkrrrrkkrk..", ".krrbrrrrrrbrrk.", ".krrrrrrrrrrrrk."]
        p.Art["F_HAPPY"] = ["..krrerrrrerrk..", "..krerrrrrrerk..", ".krrbrrrrrrbrrk.", ".krrrrrmmrrrrrk."]
        p.Art["F_DIZZY"] = ["..krekrrrekrrk..", "..krrerrrrerrk..", ".krrbrrrrrrbrrk.", ".krrrrrmmrrrrrk."]
        p.Art["F_SQUISH"] = ["..krkkrrrrkkrk..", "..krrkrrrrkrrk..", ".krrbrrmmrrbrrk.", ".krrrrrmmrrrrrk."]
        p.Art["F_CHEW"] = ["..krrewrrewrrk..", "..krreerreerrk..", ".krrbrrrrrrbrrk.", ".krrrrmmmmrrrrk."]
        p.Art["PADDLE"] = [".kkk.", "k111k", "k111k", "k112k", ".k2k.", "..2..", "..2..", "..k.."]
        p.Art["BENTO"] = [".kkkkkkkk.", "kxrrroOrxk", "kxrrroooxk", "kxGGyyrrxk", "kXXXXXXXXk", ".kkkkkkkk."]
        p.Art["MINI_ONIGIRI"] = ["..k..", ".krk.", "krrrk", "knnnk", ".kkk."]
        p.Art["NORI"] = ["kkkkkkkkkkkkkk", "knnnnnnnnnnnNk", "kkkkkkkkkkkkkk"]
        p.FaceRow = 6
    }
    static func ArtSticky(_ p: Pal)
    {
        p.Col("C", 0x6E3E22, 0x4E2C18)
        p.Col("L", 0xE8D890, 0xC4B680)
        p.Col("b", 0x2A4FA8, 0x203E80)
        p.Col("c", 0xA0623A, 0x7A4A2E)
        p.Col("d", 0x3A3020, 0x221C10)
        p.Col("g", 0xF2CC3A, 0xBCA040)
        p.Col("k", 0x6A5418, 0x3A2E10)
        p.Col("l", 0xFFF6C8, 0xE6DCB0)
        p.Col("o", 0xE89A4A, 0xB87A3A)
        p.Col("p", 0xFF9AA8, 0xC87A88)
        p.Col("r", 0xFCF9F0, 0xD6D4E2)
        p.Col("u", 0x3F6FD8, 0x3458A8)
        p.Col("w", 0xFFFFFF, 0xE8E4F0)
        p.Col("y", 0xFFE45C, 0xD8BC5A)
        p.Art["HEAD"] = ["..............kk", "............kklk", "..kkkkkkkkkkllk.", "..kggggggggklk..", "..kyyyyyyyyykk..", "..kyyyyyyyyyyk..", "..kyydyyyydyyk..", "..kyydyyyydyyk..", "..kypyyyyyypyk..", "..kyyyyddyyyyk.."]
        p.Art["HEAD_UP"] = ["..............kk", "............kklk", "..kkkkkkkkkkllk.", "..kggggggggklk..", "..kyyyyyyyyykk..", "kkkyyyyyyyyyykkk", "kykyydyyyydyykyk", ".kkyydyyyydyykk.", "..kypyyyyyypyk..", "..kyyyyddyyyyk.."]
        p.Art["FLAP"] = ["................", "................", "..kkkkkkkkkkkk..", "..kggggggggggk..", "..kyyyyyyyyyyk.."]
        p.Art["BODY"] = ["..kyyyyyyyyyyk..", ".kkyyyyyyyyyykk.", "..kyyyyyyyyyyk..", "..kkkkkkkkkkkk.."]
        p.Art["BODY_HUG"] = ["..kyyyyyyyyyyk..", "kkkkyyyyyyyykkkk", "..kyyyyyyyyyyk..", "..kkkkkkkkkkkk.."]
        p.Art["LEGS_A"] = ["....kk...kk.....", "....kk...kk....."]
        p.Art["LEGS_B"] = ["...kk.....kk....", "...kk.....kk...."]
        p.Art["LEGS_SIT"] = ["...kkk...kkk....", "................"]
        p.Art["F_SLEEPY"] = ["..kyyyyyyyyyyk..", "..kyddyyyddyyk..", "..kypyyyyyypyk..", "..kyyyyddyyyyk.."]
        p.Art["F_HAPPY"] = ["..kyydyyyydyyk..", "..kydydyydydyk..", "..kypyyyyyypyk..", "..kyyyddddyyyk.."]
        p.Art["F_DIZZY"] = ["..kydydyydydyk..", "..kyydyyyydyyk..", "..kydydyydydyk..", "..kyyyyddyyyyk.."]
        p.Art["F_SQUISH"] = ["..kyddyyyddyyk..", "..kyydyyyydyyk..", "..kypyyddyypyk..", "..kyyyyddyyyyk.."]
        p.Art["F_PANIC"] = ["..kyydyyyydyyk..", "..kyydyyyydyyk..", "..kypyyddyypyk..", "..kyyyddddyyyk.."]
        p.Art["MARKER"] = ["kuuuubk", "kwwwwbk", ".kkkkk."]
        p.Art["MINI_NOTE"] = ["kkkkkkkkk", "kgggggggk", "kyppyppyk", "kpppppppk", "kpppppppk", "kyppppyyk", "kyyppyyyk", "kkkkkkkkk"]
        p.Art["NOTE_BANG"] = ["kkkkkkkkk", "kgggggggk", "kyyyuyyyk", "kyyyuyyyk", "kyyyuyyyk", "kyyyyyyyk", "kyyyuyyyk", "kkkkkkkkk"]
        p.Art["NOTE_HOME"] = ["kkkkkkkkk", "kgggggggk", "kyyyuyyyk", "kyyuyuyyk", "kyuyyyuyk", "kyuyuyuyk", "kyuuuuuyk", "kkkkkkkkk"]
        p.Art["NOTE_ZZ"] = ["kkkkkkkkk", "kgggggggk", "kuuuuyyyk", "kyyuyyyyk", "kyuyyuuuk", "kuuuuyuyk", "kyyyyuuuk", "kkkkkkkkk"]
        p.Art["NOTE_CHECK"] = ["kkkkkkkkk", "kgggggggk", "kyyyyyyuk", "kyyyyyuyk", "kuyyyuyyk", "kyuyuyyyk", "kyyuyyyyk", "kkkkkkkkk"]
        p.Art["NOTE_DRINK"] = ["kkkkkkkkk", "kgggggggk", "kyuuuuuyk", "kyyyyyyyk", "kyuuuuyyk", "kyyyyyyyk", "kyuuuyyyk", "kkkkkkkkk"]
        p.Art["RICEBOWL"] = ["..cCcC..", ".rcCcCr.", "kwwwwwwk", ".kwuuwk.", "..kkkk.."]
        p.FaceRow = 6
    }
    // ==== 像素圖結束 ====
}

// ================= 一隻續命小隊 =================
//@@IN Pet
    var oAct = "", oPose = ""            // 專屬動作（state == "orig"）、串場的姿勢
    var oT: Double = 0, oWired: Double = 0, oVaultT: Double = 0, oLatteT: Double = 0, oNoteT: Double = 0, oFlyDur: Double = 0
    var oTx: Double = Double.nan, oFx0: Double = 0, oFy0: Double = 0, oFx1: Double = 0, oFy1: Double = 0, oGlideVx: Double = 0
    var oGliding = false
    var oStuckH: IntPtr = 0; var oStuckDx = 0, oStuckDy = 0
    var oPend: String? = nil; var oPendDur: Double = 0
    var OHold = ""                       // 手上拿的（串場：mini 小飯糰、paddle 飯匙、marker 麥克筆）
    var ONoteFace = false                // 醒醒：臉上被貼了「先睡覺」的便條
    var OPearlLatte = false              // 醒醒：被加了珍珠（珍珠拿鐵）
//@@END

extension Pet {
    var OGoing: Bool { return state == "orig" && oAct == "goto" }

    func OrigDo(_ act: String, _ dur: Double) {
        if state == "air" || state == "fling" || state == "drag" || state == "swim" { oPend = act; oPendDur = dur; return }
        oAct = act; oT = 0; SetState("orig", dur)
    }
    func OPose(_ kind: String, _ dur: Double) { if !Grounded() && state != "air" { return }; oPose = kind; OrigDo("pose", dur) }
    func OGoto(_ tx: Double, _ dur: Double) { oTx = tx; OrigDo("goto", dur) }
    func OWire(_ sec: Double) { oWired = Math.Max(oWired, sec) }
    func OLatte(_ sec: Double) { OPearlLatte = true; oLatteT = sec }
    func ONote(_ sec: Double) { ONoteFace = true; oNoteT = sec }

    // 畫面上的幾個點（串場丟東西用；螢幕座標）
    func OStrawTip() -> PointF { return PointF(Cx + Double(dir) * 4.5 * Double(S), y - 4 * Double(S)) }
    func OHandPoint() -> PointF { return PointF(Cx + Double(dir) * 6 * Double(S), y + Double((P.BodyTop + 1) * S)) }
    func OFacePoint() -> PointF { return PointF(Cx - Double(dir) * 0.5 * Double(S), y + Double((P.BodyTop - 3) * S)) }
    func OTopPoint() -> PointF { return PointF(Cx, y + Double((P.HeadTop + 1) * S)) }

    // ---------- 連點三下 ----------
    func OrigCombo() {
        Say(L("tickle"), 1.8)
        if !Grounded() || state == "dizzy" { return }
        switch P.Id {
        case "boba": OrigDo("shoot", 1.1)                                                                      // 噗噗噗：珍珠噴出來
        case "coffee": OWire(3.5); Jump(0, -340 * k); Burst(6)                                                 // 嚇醒：跳起來、開始抖
        case "onigiri": rolling = true; Jump(Double(dir) * R(120, 200) * k, -260 * k)                          // 笑到滾來滾去
        default: OrigDo("write", 1.2); w.OrigNotes(self, 3)                                                    // 撒愛心便條
        }
    }

    // ---------- 招牌動作 ----------
    func OrigSignature() {
        if !Grounded() { return }
        switch P.Id {
        case "boba": BobaVault()
        case "coffee": OrigDo("pour", 2.6); Say(Pick(["續杯…拜託…", "（咖啡壺出現）續杯！", "開機需要咖啡因…"]), 1.6)
        case "onigiri": OrigDo("surf", 3.4); Say(Pick(["海苔衝浪～咻！", "看我的海苔板！", "糰糰出發～"]), 1.6)
        default: StickyFly()
        }
    }

    // 半糖：把吸管拔下來當撐竿，跳上附近的視窗（沒有就跳高高）
    func BobaVault() {
        let o = PickPlatform(80 * k, 800 * k)
        if let o = o { oFx1 = o[0]; oFy1 = o[1]; dir = o[0] > Cx ? 1 : -1 }
        else { oFx1 = Double.nan }
        OrigDo("vault", 0.5)
        Say(Pick(["吸管撐竿跳！", "看我的～嘿！", "半糖起跳！"]), 1.4)
    }

    // 貼貼：飛到附近視窗的正面貼著（沒有視窗：直接貼在你的螢幕上）
    func StickyFly() {
        var tx = Double.nan, ty: Double = 0; var h: IntPtr = IntPtr.Zero
        var bd = Double.greatestFiniteMagnitude
        for wi in w.Cands.Values {
            if Double(wi.R - wi.L) < 160 * k || Double(wi.B - wi.T) < 140 * k { continue }
            let cx = Clamp(Cx, Double(wi.L + SW), Double(wi.R - SW)), cy = Double(wi.T) + Math.Min(110 * k, Double(wi.B - wi.T) * 0.3)
            if !w.PointVisible(wi, cx, cy) || !w.PointVisible(wi, cx, cy + Double(SH) * 0.6) { continue }
            let d = Math.Abs(cx - Cx) + Math.Abs(cy - y)
            if d < bd && d < 1200 * k { bd = d; tx = cx; ty = cy; h = wi.H }
        }
        if tx.isNaN {
            let wa = w.WA(Cx, y + Double(SH) / 2.0)
            tx = Clamp(Cx + Double(dir) * R(40, 160) * k, Double(wa.Left + SW), Double(wa.Right - SW))
            ty = Math.Max(Double(wa.Top + SH), y - R(170, 300) * k)
        }
        oFx0 = x; oFy0 = y; oFx1 = tx - Double(SW) / 2.0; oFy1 = ty - Double(SH) * 0.35
        let ddx = oFx1 - oFx0, ddy = oFy1 - oFy0
        let dist = Math.Sqrt(ddx * ddx + ddy * ddy)
        oFlyDur = Clamp(dist / (300 * k), 0.8, 2.6)
        oStuckH = h
        supH = IntPtr.Zero
        dir = oFx1 >= oFx0 ? 1 : -1
        OrigDo("fly", 99)
        Say(Pick(["貼過去囉～", "飄～貼！", "我去貼在那邊！"]), 1.4)
    }

    func OrigAct(_ a: String) -> Bool {
        switch a {
        case "shoot": if Grounded() && Is("boba") { OrigDo("shoot", 1.1); Say("噗噗噗！", 1.2) }; return true
        case "yawn": if Grounded() && Is("coffee") { OrigDo("yawn", 1.8); Say("呼啊～～", 1.4) }; return true
        case "tumble": if Grounded() { rolling = true; Jump(Double(dir) * 180 * k, -280 * k); Say("咕嚕咕嚕～", 1.2) }; return true
        case "paddle": if Grounded() && Is("onigiri") { OrigDo("paddle", 0.9); Say("嘿！揮一揮！", 1.2) }; return true
        case "write": if Grounded() && Is("sticky") { OrigDo("write", 1.6); Say("寫一張給你～", 1.4); w.OrigNoteToCursor(self, 1.2) }; return true
        default: break
        }
        return false
    }

    // ---------- 自己閒晃時決定做什麼 ----------
    func OrigDecide(_ r: Double, _ wa: Rectangle) {
        if r < 0.16 { SetState("idle", R(1.5, 3.5)); return }
        if r < 0.40 { dir = rnd.NextDouble() < 0.5 ? -1 : 1; SetState("walk", R(3, 6)); return }
        if r < 0.48 { if !JumpToPlatform() { Hop() }; return }
        if r < 0.54 { OrigSignature(); return }
        if r < 0.62 {
            switch P.Id {
            case "boba": OPose("cheer", 1.8); Say(Pick(["Q 彈～Q 彈～", "珍珠在跳舞 ♪", "今天的甜度剛剛好～"]), 1.8)
            case "coffee": if !Night && oWired <= 0 { OrigDo("yawn", 1.8); Say(Pick(["呼啊～～", "（打哈欠）好睏…", "……需要續杯"]), 1.6) } else { SetState("idle", 2); Say(L("talk"), 2.2) }
            case "onigiri": OrigDo("paddle", 0.9); Say(Pick(["揮棒練習！嘿！", "飯匙素振り～", "嘿咻！"]), 1.2)
            default: OrigDo("write", 1.6); Say(Pick(["（寫寫寫）記下來～", "今天的待辦…", "這個也要記！"]), 1.6)
            }
            return
        }
        if r < 0.67 { Hug(L("hugs"), 2.2); return }
        if r < (Night ? 0.73 : 0.71) { Knock(L("knock"), "ambient"); return }
        if r < 0.75 && lateCd <= 0 && LateLine() != nil { LateTick(); return }
        if r < 0.78 && SeasonLine() != nil { Say(SeasonLine(), 3); SetState("idle", 3); return }
        if r < 0.90 { SetState("idle", 2.5); Say(L("talk"), 2.4); return }
        dir = -dir; SetState("walk", R(2, 5))
    }

    // 走到視窗邊：0 照預設跳、1 回頭、2 換狀態了
    func OrigEdge(_ right: Bool) -> Int {
        switch P.Id {
        case "boba":
            if rnd.NextDouble() < 0.4 { dir = -dir; return 1 }
            x += Double(dir) * 4 * k; Jump(Double(dir) * 140 * k, -320 * k); Say(Pick(["嘿！", "跳～"]), 0.8)
            return 2
        case "coffee":
            if rnd.NextDouble() < 0.75 { dir = -dir; if rnd.NextDouble() < 0.3 { Say("……不想跳", 1.2) }; return 1 }
            x += Double(dir) * 4 * k; Jump(Double(dir) * 60 * k, -80 * k); Say("哎…（沒醒，踩空了）", 1.2)
            return 2
        case "onigiri":
            if rnd.NextDouble() < 0.45 { dir = -dir; return 1 }
            x += Double(dir) * 4 * k; rolling = true; Jump(Double(dir) * 160 * k, -160 * k); Say("咕嚕咕嚕～", 1.0)    // 三角飯糰滾下去
            return 2
        default:
            if rnd.NextDouble() < 0.35 { dir = -dir; return 1 }
            x += Double(dir) * 4 * k; Jump(Double(dir) * 120 * k, -220 * k); Say("飄～", 0.8)                       // 像紙一樣飄下去
            return 2
        }
    }

    func OrigLanded(_ wasRolling: Bool) -> Bool {
        oGliding = false
        if oPend != nil { let a = oPend!; oPend = nil; SetState("idle", 0.1); OrigDo(a, oPendDur); return true }
        if oVaultT > 0 || (Is("boba") && oAct == "vaultair") {
            oVaultT = 0; oAct = ""
            OPose("cheer", 1.4); Say(Pick(["（落地）甜度剛好！", "十分！滿分！", "吸管插回去～"]), 1.6)
            return true
        }
        if Is("onigiri") && wasRolling { SetState("dizzy", 0.8); Say(Pick(["滾太快了～", "咕嚕…頭暈", "嘿嘿，滾到了"]), 1.2); return true }
        if Is("sticky") && lastLandVy < 320 * k && rnd.NextDouble() < 0.25 { SetState("idle", 1.2); Say("（輕輕飄下來）", 1.2); return true }
        return false
    }

    func OrigLand(_ a: String) -> Bool {
        switch a {
        case "oyawn": OrigDo("yawn", 1.6); Say("呼啊～～", 1.2); return true
        case "ocheer": OPose("cheer", 1.4); Say(Pick(["半糖出杯！", "Q 彈落地～"]), 1.4); return true
        case "osniff": OPose("think", 1.4); Mark(2); return true
        default: break
        }
        return false
    }

    // 從櫃子出來：每隻出場方式不一樣
    func OrigExit() {
        switch P.Id {
        case "boba": if rnd.NextDouble() < 0.5 { afterLand = "ocheer" }
        case "coffee": if !Night && rnd.NextDouble() < 0.6 { afterLand = "oyawn" }
        case "onigiri": rolling = true                // 滾出來
        default: break
        }
    }

    func OrigNewWindow(_ win: WinInfo) {
        let after = Is("boba") ? "ocheer" : (Is("coffee") ? "oyawn" : "osniff")
        if Is("sticky") && rnd.NextDouble() < 0.5 { Say(L("newwin"), 1.5); StickyFly(); return }
        if !GoToWindow(win, L("newwin"), after) { Say(L("newwin"), 1.5) }
    }

    // 錯誤變多：半糖擔心、醒醒瞬間清醒、糰糰抄起飯匙、貼貼慌張貼一張「！」
    func OrigReact(_ why: String) {
        switch P.Id {
        case "boba": OPose("worry", 2.6); Mark(4)
        case "coffee": OWire(4); OPose("wide", 2.4); Mark(1)
        case "onigiri": OHold = "paddle"; OPose("ready", 2.6)
        default: OPose("panic", 2.4); w.OrigNoteAbove(self, "NOTE_BANG")
        }
    }

    // 慶祝（上版、做完）
    func OrigCelebrate(_ line: String, _ lead: Bool) {
        if lead { w.Fireworks(w.WA(Cx, y + Double(SH) / 2.0), 10, -1) }
        if Grounded() { OPose("cheer", 3.2) }
        Say(line, 4)
        switch P.Id {
        case "boba": w.OrigPearls(self, 6)
        case "coffee": OWire(5); Mark(0); Mark(0); Burst(8)
        case "onigiri": Burst(14); Jump(0, -300 * k)
        default: w.OrigNotes(self, 4)
        }
    }

    func OrigLine(_ kind: String) -> String {
        switch kind {
        case "goal": return Is("boba") ? "進杯！🏀 甜度剛好～" : (Is("coffee") ? "……進了？我醒了 🏀" : (Is("onigiri") ? "好球！🏀 飯糰入櫃！" : "貼上去了！🏀 貼貼～"))
        case "cheer": return Is("boba") ? "好球～加珍珠！" : (Is("coffee") ? "……好球" : (Is("onigiri") ? "嘿嘿！好厲害！" : "記下來：好球 ✓"))
        case "miss": return Is("boba") ? "差一點～再一杯！" : (Is("coffee") ? "……沒進。我還沒醒" : (Is("onigiri") ? "滾、滾過頭了！" : "飄走了～再一次！"))
        default: break
        }
        return "！"
    }

    // ---------- 球 ----------
    func OrigBall() {
        switch P.Id {
        case "boba": w.HoldBall(self); OrigDo("slurp", 0.9); Say(Pick(["吸～～", "好大的珍珠！吸～"]), 1.0)
        case "coffee": w.HoldBall(self); OrigDo("dunk", 0.9); OWire(2.5); Say(Pick(["噗通！（掉進杯子裡）", "誰…丟的…（醒了）"]), 1.2)
        case "onigiri":
            OrigDo("paddle", 0.5)
            w.By = y + 6 * Double(S); w.Bx = Cx + Double(dir) * 6 * Double(S)
            do {
                let c = Cursor.Position
                w.Bvx = Clamp((Double(c.X) - w.Bx) * 1.2, -1000 * k, 1000 * k); w.Bvy = -R(560, 720) * k; w.CatchCd = 1.0; w.BallIdle = 0
            }
            Say(L("ball_catch"), 1.6)
        default: w.HoldBall(self); OrigDo("stickball", 1.0); Say("黏住了！", 1.0)
        }
    }

    func OReleaseBall(_ power: Double) {
        if w.Holder !== self { return }
        w.ReleaseBall(Cx + Double(dir) * 4 * Double(S), y + Double((P.BodyTop - 2) * S), 0, 0)
        KickBallToCursor(power)
    }

    // ---------- 每一格 ----------
    func OrigStep(_ dt: Double) -> Bool {
        if oWired > 0 { oWired -= dt }
        if oVaultT > 0 { oVaultT -= dt }
        if oLatteT > 0 { oLatteT -= dt; if oLatteT <= 0 { OPearlLatte = false } }
        if oNoteT > 0 { oNoteT -= dt; if oNoteT <= 0 { ONoteFace = false } }
        // 貼貼：像紙一樣飄下來（左右晃、慢慢掉）
        if Is("sticky") && state == "air" && !rolling {
            if vy > 0 {
                if !oGliding { oGliding = true; oGlideVx = vx }
                oGlideVx *= Math.Pow(0.35, dt)
                vy = Math.Min(vy, 210 * k)
                vx = oGlideVx + Math.Sin(anim * 4.2) * 120 * k
            }
        }
        else { oGliding = false }
        // 醒醒續杯後：走路變很快、一直抖
        if Is("coffee") && oWired > 0 && state == "walk" && !InScene {
            if MoveOnGround(dt, 170 * k) { return true }
            if rnd.NextDouble() < dt * 2 { Mark(0) }
        }
        if Is("coffee") && state == "walk" && oWired <= 0 && !Night && rnd.NextDouble() < dt * 0.08 && !InScene { OrigDo("yawn", 1.6); Say("呼啊～", 1.0); return true }
        if state != "orig" { return false }
        oT += dt
        switch oAct {
        case "goto":
            if !oTx.isNaN && Math.Abs(oTx - Cx) > 3 {
                dir = oTx > Cx ? 1 : -1
                let step = Math.Min(Math.Abs(oTx - Cx), Math.Max(P.Speed, 70.0) * 1.6 * k * dt)
                let nx = x + Double(dir) * step
                if w.Inside(nx + Double(dir > 0 ? SW : 0), y + Double(SH) / 2.0) { x = nx }
            }
            else if t > 1 && InScene { t = Math.Min(t, 0.2) }
            if t < 0 { SetState("idle", InScene ? 30 : 1) }
            return true
        case "vault":
            if t < 0 {
                if !oFx1.isNaN { BallisticTo(oFx1, oFy1) } else { Jump(Double(dir) * 90 * k, -760 * k) }
                oAct = "vaultair"; oVaultT = 0.5; Burst(5)
            }
            return true
        case "slurp":
            if t < 0 { OReleaseBall(1.0); Say(Pick(["噗！還你～", "Q 彈回擊！"]), 1.4); SetState("idle", 1) }
            return true
        case "dunk":
            if oT > 0.3 && oT - dt <= 0.3 { for _ in 0..<3 { Mark(4) } }
            if t < 0 { OReleaseBall(0.9); Say(L("ball_catch"), 1.6); SetState("idle", 1) }
            return true
        case "stickball":
            if t < 0 { OReleaseBall(1.0); Say(Pick(["撕下來～還你！", "啪！還你～"]), 1.4); SetState("idle", 1) }
            return true
        case "shoot":
            for i in 0..<3 { let at = 0.15 + Double(i) * 0.3; if oT >= at && oT - dt < at { w.OrigPearlShot(self, i) } }
            if t < 0 { SetState("idle", InScene ? 30 : 1) }
            return true
        case "pour":
            if oT >= 1.6 && oT - dt < 1.6 { OWire(8); Burst(8); Say(Pick(["……！！醒了！！", "開機完成！衝！", "咖啡因注入！！"]), 1.6) }
            if t < 0 { dir = rnd.NextDouble() < 0.5 ? -1 : 1; SetState("walk", 4.5) }
            return true
        case "yawn":
            if oT > 0.4 && oT - dt <= 0.4 { Mark(3) }
            if t < 0 { SetState("idle", InScene ? 30 : 1.2) }
            return true
        case "surf":
            do {
                let nx = x + Double(dir) * 240 * k * dt
                let ok = supH != IntPtr.Zero ? (nx + Double(SW) / 2.0 >= Double(supL) && nx + Double(SW) / 2.0 <= Double(supR)) : w.Inside(nx + Double(dir > 0 ? SW : 0), y + Double(SH) / 2.0)
                if ok { x = nx } else { dir = -dir }
                if rnd.NextDouble() < dt * 8 { sparks.Add(Arr<Double>([Cx - Double(dir) * 6 * Double(S), y + Double(SH) - 2 * Double(S), -Double(dir) * R(40, 120) * k, -R(60, 160) * k, 0])) }
                if t < 0 { SetState("idle", 1.4); Say(Pick(["（穿回海苔）不、不要看！", "好爽～海苔穿回去！", "嘿嘿，衝浪完畢"]), 1.6) }
            }
            return true
        case "fly":
            do {
                let f = Math.Min(1.0, oT / oFlyDur), e = Ease(f)
                x = oFx0 + (oFx1 - oFx0) * e + Math.Sin(oT * 6) * 6 * k * (1 - f)
                y = oFy0 + (oFy1 - oFy0) * e - Math.Sin(Math.PI * f) * 50 * k
                if f >= 1 {
                    var r = W.RECT()
                    if oStuckH != IntPtr.Zero && W.Rect(oStuckH, &r) { oStuckDx = CInt(Math.Round(x)) - r.L; oStuckDy = CInt(Math.Round(y)) - r.T }
                    else { oStuckH = IntPtr.Zero }
                    OrigDo("stick", R(6, 9)); Burst(4)
                    Say(Pick(["貼好了！貼貼～", "黏住了！你看得到我嗎？", "（貼在這裡提醒你）📝"]), 2)
                }
            }
            return true
        case "stick":
            do {
                if oStuckH != IntPtr.Zero {
                    var r = W.RECT()
                    if !W.IsWindowVisible(oStuckH) || W.IsIconic(oStuckH) || !W.Rect(oStuckH, &r) { oStuckH = IntPtr.Zero; StickyPeel("哇！視窗不見了～"); return true }
                    x = Double(r.L + oStuckDx); y = Double(r.T + oStuckDy)
                }
                if t < 0 { StickyPeel(Pick(["黏膠沒力了～飄～", "被冷氣吹下來了～", "（啪）掉下來囉～"])) }
            }
            return true
        case "write":
            if t < 0 { SetState("idle", InScene ? 30 : 1) }
            return true
        case "paddle":
            if t < 0 { SetState("idle", InScene ? 30 : 1) }
            return true
        default:   // pose：站著擺姿勢
            if oPose == "think" && rnd.NextDouble() < dt * 0.8 { Mark(2) }
            if t < 0 { if oPose == "ready" { OHold = "" }; SetState("idle", InScene ? 30 : 1) }
            return true
        }
    }

    func StickyPeel(_ line: String) {
        oStuckH = IntPtr.Zero
        Jump(Double(dir) * 30 * k, -60 * k)
        Say(line, 1.6)
    }

    func OrigBob() -> Double {
        let moving = state == "walk" || state == "goto" || state == "seek" || state == "fetch" || (state == "orig" && (oAct == "goto" || oAct == "surf"))
        if state == "dance" { return Math.Abs(Math.Sin(anim * 8)) * 6 * k }
        if state == "orig" && oAct == "stick" { return Math.Sin(anim * 2.2) * 1.5 * k }                       // 貼著被冷氣吹得晃
        switch P.Id {
        case "boba": if moving { return Math.Abs(Math.Sin(anim * 9)) * 4 * k }                            // 蹦蹦跳（Q 彈）
        case "coffee": if oWired > 0 && Grounded() { return (Math.Floor(anim * 24) % 2) * k }              // 咖啡因：一直抖
        case "onigiri": if moving { return Math.Abs(Math.Sin(anim * 6)) * 2 * k }                        // 搖搖擺擺
        default: if moving { return (Math.Floor(anim * 7) % 2) * k }
        }
        return 0
    }

    // ---------- 畫 ----------
    func ORows(_ head: String, _ body: String, _ legs: String, _ face: String?) -> [String] {
        var rows: [String] = A(P.Art.ContainsKey(head) ? head : "HEAD")
        rows += A(P.Art.ContainsKey(body) ? body : "BODY")
        rows += A(P.Art.ContainsKey(legs) ? legs : "LEGS_A")
        if let face = face, P.Art.ContainsKey("F_" + face) {
            let fr = A("F_" + face)
            for i in 0..<fr.count {
                let ri = P.FaceRow + i
                let fi = Array(fr[i])
                if ri >= rows.count || fi.count != rows[ri].count { continue }
                var c = Array(rows[ri])
                for j in 0..<c.count { if fi[j] != "." { c[j] = fi[j] } }   // 舉手的手留著
                rows[ri] = String(c)
            }
        }
        return rows
    }

    // 半糖的吸管拔下來當撐竿時：頭上沒有吸管
    static func NoStraw(_ rows: [String]) -> [String] {
        var o = rows
        var i = 0
        while i < 6 && i < o.count {
            var c = Array(o[i])
            for j in 0..<c.count { if c[j] == "s" || c[j] == "z" { c[j] = i < 4 ? "." : (i == 4 ? "k" : (j % 2 == 0 ? "F" : "f")) } }
            o[i] = String(c)
            i += 1
        }
        return o
    }

    func FrameOrig() -> Fr {
        let act = state == "orig" ? oAct : ""
        let pose = act == "pose" ? oPose : ""
        let sleep = state == "sleep", hug = state == "hug"
        let nightIdle = Night && state == "idle" && !InScene && !HoldingFood()
        var moving = state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto"
        moving = moving || act == "goto"
        var face: String? = nil
        if sleep || pose == "doze" { face = "SLEEPY" }
        else if hug || state == "dance" || pose == "cheer" || (state == "pose" && poseKind == "photo") || act == "stick" || act == "surf" { face = "HAPPY" }
        else if state == "dizzy" { face = "DIZZY" }
        else if state == "glass" { face = "SQUISH" }
        else if act == "yawn" { face = "SLEEPY" }
        switch P.Id {
        case "boba":
            if act == "shoot" || act == "slurp" || pose == "blow" { face = "BLOW" }
            else if pose == "worry" { face = "WORRY" }
            else if face == nil && nightIdle && (anim % 5) < 2 { face = "SLEEPY" }
        case "coffee":
            if face == "SLEEPY" && (act == "yawn" || sleep) { }
            else if pose == "wide" || act == "dunk" || (act == "pour" && oT > 1.6) || oWired > 0 { face = face == "HAPPY" ? "HAPPY" : "WIDE" }
            else if face == nil && Night && !sleep { face = "PANDA" }                 // 晚上：熬夜冠軍（黑眼圈）
            if ONoteFace && !sleep { face = "SLEEPY" }
        case "onigiri":
            if pose == "eat" || (HoldingFood() && state == "idle") { face = Step2(3) ? "CHEW" : nil }
            else if face == nil && nightIdle && (anim % 5) < 2.5 { face = "SLEEPY" }
        default:
            if pose == "panic" { face = "PANIC" }
            else if face == nil && nightIdle && (anim % 5) < 2.5 { face = "SLEEPY" }
        }
        var armsUp = state == "air" || state == "fling" || state == "drag" || state == "kick" || state == "catch" || state == "glass"
        armsUp = armsUp || (state == "wave" && Step2(4)) || (state == "dance" && Step2(4))
        armsUp = armsUp || (state == "pose" && poseKind == "photo") || pose == "cheer" || pose == "panic" || pose == "wide"
        armsUp = armsUp || act == "surf" || act == "vault" || act == "vaultair" || act == "fly" || act == "stick"
        armsUp = armsUp || (act == "pour" && oT > 1.6) || act == "dunk" || act == "stickball" || (act == "paddle" && oT < 0.25) || pose == "ready"
        if Is("sticky") && state == "air" { armsUp = true }
        let head = armsUp ? "HEAD_UP" : "HEAD"
        var body = hug ? "BODY_HUG" : (armsUp ? "BODY_UP" : "BODY")
        if Is("onigiri") && act == "surf" { body = "BODY_BARE" }
        let sit = sleep || (nightIdle && !Is("coffee")) || pose == "sit"
        let rate: Double = Is("boba") ? 9 : (Is("coffee") ? (oWired > 0 ? 14 : 4) : 7)
        let step = (moving && Step2(rate)) || (state == "dance" && Step2(4))
        let legs = sit ? "LEGS_SIT" : (step ? "LEGS_B" : "LEGS_A")
        // 半糖蹦跳時珍珠跟著彈
        if Is("boba") && body == "BODY" && ((moving && Step2(9)) || (pose == "cheer" && Step2(5)) || state == "air") { body = "BODY_J" }
        var rows = ORows(head, body, legs, face)
        if Is("boba") && (act == "vault" || act == "vaultair" || oVaultT > 0) { rows = Pet.NoStraw(rows) }
        // 醒醒的蒸氣飄來飄去；貼貼走路時角一翹一翹
        if Is("coffee") && Step2(2.2) { let sb = A("STEAM_B"); for i in 0..<sb.count { rows[i] = sb[i] } }
        if Is("coffee") && sleep { for i in 0..<4 { rows[i] = String(repeating: ".", count: rows[i].count) } }
        if Is("sticky") && ((moving && Step2(7)) || (state == "air" && Step2(5))) { let fl = A("FLAP"); for i in 0..<fl.count { rows[i] = fl[i] } }
        let f = F(rows)
        if sit { f.AccDy = 0 }
        if Is("onigiri") && act == "surf" { f.Top = -2 }
        if rolling { f.Rot = CInt(Math.Floor(anim * 12)) % 4; f.Acc = false }
        return f
    }

    static let O_POLE: [String] = ["....sz", "....sz", "...sz.", "...sz.", "..sz..", "..sz..", ".sz...", ".sz...", "sz....", "sz...."]
    static let O_STREAM: [String] = ["c", "C", "c", "C", "c", "C"]
    static let O_SPEED: [String] = ["vvv.", "....", ".vvv", "....", "vvv."]

    func DrawOrigBehind(_ g: Graphics, _ f: Fr, _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool) {
        let act = state == "orig" ? oAct : ""
        if Is("onigiri") && act == "surf" { DrawAt(g, A("NORI"), -1, 14, bx, by, ps, fx, false, true) }   // 海苔衝浪板
        if Is("boba") && act == "vault" { DrawAt(g, Pet.O_POLE, 10, 6, bx, by, ps, !fx, false, true) }         // 吸管撐在前面地上
        if Is("boba") && oVaultT > 0.2 { DrawAt(g, ["sz", "sz", "sz", "sz", "sz", "sz"], 5, 14, bx, by, ps, fx, false, true) }
        if Is("coffee") && oWired > 0 && (state == "walk" || state == "goto") && f.Rot == 0 {
            DrawAt(g, Pet.O_SPEED, -4, 7, bx, by, ps, fx, false, false)                                      // 速度線（在背後）
        }
    }

    func DrawOrigFront(_ g: Graphics, _ f: Fr, _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool) {
        if f.Rot != 0 || f.Fy { return }
        let act = state == "orig" ? oAct : ""
        let dy = f.Top
        switch P.Id {
        case "boba":
            do {
                // 戴帽子時吸管要插在帽子上面
                let hat = w.SeasonNow == "xmas" || Level() >= 3
                if hat && f.Acc && act != "vault" && act != "vaultair" && oVaultT <= 0 {
                    let h = A("HEAD")
                    var st = [String](repeating: "", count: 5)
                    for i in 0..<5 { var c = Array(h[i]); for j in 0..<c.count { if c[j] != "s" && c[j] != "z" { c[j] = "." } }; st[i] = String(c) }
                    DrawAt(g, st, -(h[0].count - 12) / 2, -P.TopRows + dy, bx, by, ps, fx, false, false)
                }
                if act == "slurp" && w.Holder === self {
                    let up = Clamp(oT / 0.6, 0, 1)
                    DrawAt(g, TBALL, 8.5 - up * 1.5, Double(-P.TopRows - 1 + dy) - up * 3, bx, by, ps, fx, false, true)
                }
            }
        case "coffee":
            if act == "pour" {
                // 咖啡壺從上面倒下來
                let drop = Clamp(oT / 0.4, 0, 1)
                let pot = A("POT")
                DrawAt(g, pot, 5.0, -12 + drop * 2 + Double(dy), bx, by, ps, !fx, false, true)
                if oT > 0.45 && oT < 1.7 { DrawAt(g, Pet.O_STREAM, 5, -6 + dy, bx, by, ps, fx, false, false) }
            }
            if act == "dunk" && w.Holder === self { DrawAt(g, TBALL, 3, -1 + dy, bx, by, ps, fx, false, true) }
            if OPearlLatte { DrawAt(g, ["kv.", "kk."], 2, 2 + dy, bx, by, ps, fx, false, false); DrawAt(g, [".kv", ".kk"], 6, 2 + dy, bx, by, ps, fx, false, false) }
            if ONoteFace { let st: Pal! = Pal.Get("sticky"); if st != nil { DrawPixPalAt(g, st, st.Art["NOTE_ZZ"], 1.5, Double(5 + dy), bx, by, ps, fx) } }
        case "onigiri":
            if act == "paddle" || OHold == "paddle" {
                let pd = A("PADDLE")
                if act == "paddle" && oT < 0.25 { DrawAt(g, pd, 12, 1 + dy, bx, by, ps, fx, false, true) }             // 舉起來
                else if act == "paddle" { DrawAt(g, Pet.Rot90(pd, 1), 11, 8 + dy, bx, by, ps, fx, false, true) }    // 揮出去
                else { DrawAt(g, pd, 12.5, 4 + dy, bx, by, ps, fx, false, true) }                                     // 拿著準備
            }
        default:
            if act == "write" || (state == "orig" && oPose == "write") {
                let wob = Math.Sin(oT * 18) * 0.6
                DrawAt(g, A("MARKER"), 11 + wob, 9 + dy, bx, by, ps, fx, false, true)
            }
            if act == "stickball" && w.Holder === self { DrawAt(g, TBALL, 4, 6 + dy, bx, by, ps, fx, false, true) }
            if act == "stick" || act == "fly" {
                let tb = SolidBrush(Color.FromArgb(150, 240, 236, 220))       // 一小段透明膠帶
                g.FillRectangle(tb, bx + 4 * ps, by + (P.HeadTop - 1 + dy) * ps, 5 * ps, 2 * ps)
            }
        }
        if OHold == "mini" { let o: Pal! = Pal.Get("onigiri"); DrawPixPalAt(g, o, o.Art["MINI_ONIGIRI"], 10.5, Double(P.BodyTop - 1 + dy), bx, by, ps, fx) }
    }

    // 用別隻的調色盤畫一張小圖（12 格框座標，會跟著左右翻）
    func DrawPixPalAt(_ g: Graphics, _ pal: Pal!, _ art: [String], _ col: Double, _ row: Double, _ bx0: Int, _ by0: Int, _ ps: Int, _ fx: Bool) {
        if pal == nil { return }
        let aw = art[0].count
        let c = fx ? 12 - col - Double(aw) : col
        DrawPixPal(g, pal, art, bx0 + CInt(Math.Round(c * Double(ps))), by0 + CInt(Math.Round(row * Double(ps))), ps, fx)
    }

    // ---------- 午餐：半糖雞排、醒醒可頌、糰糰雞腿便當、貼貼滷肉飯 ----------
    func OrigLunchLine(_ phase: String) -> String {
        switch P.Id {
        case "boba":
            if phase == "start" { return "午餐！雞排配珍奶，人生巔峰 🔔" }
            if phase == "nap" { return "吃飽了…半糖瞇一下" }
            if phase == "end" { return "回來工作囉～甜度補滿了！" }
            return Pick(["雞排好香～要不要辣？", "咬一口雞排，吸一口珍珠～", "雞排配珍奶，熱量不算數"])
        case "coffee":
            if phase == "start" { return "午餐…可頌配咖啡（我自己）🔔" }
            if phase == "nap" { return "吃飽…更想睡了…zZ" }
            if phase == "end" { return "……下午了。需要續杯。" }
            return Pick(["可頌屑屑掉進杯子裡了…", "（嚼）……還是想睡", "吃飽會想睡，這是定律"])
        case "onigiri":
            if phase == "start" { return "午餐時間！雞腿便當！🔔" }
            if phase == "nap" { return "吃飽飽…糰糰睡午覺" }
            if phase == "end" { return "吃飽了！下午繼續拚！" }
            return Pick(["飯糰吃便當很奇怪嗎？嘿嘿", "雞腿好大！", "白飯配白飯，我可以"])
        default:
            if phase == "start" { return "提醒：午餐時間！滷肉飯 🔔" }
            if phase == "nap" { return "吃飽了…貼貼睡一下" }
            if phase == "end" { return "午休結束！下午的待辦寫好了" }
            return Pick(["滷肉飯！記下來：好吃 ✓", "肥瘦剛好～", "加一顆滷蛋，記下來！"])
        }
    }

    func DrawOrigLunch(_ g: Graphics, _ f: Fr, _ bx: Int, _ by: Int, _ ps: Int, _ fx: Bool, _ bite: Int) {
        let dy = f.Top
        switch P.Id {
        case "boba": DrawAt(g, A("CHICKEN"), 11, P.BodyTop - 1 + bite + dy, bx, by, ps, fx, false, true)
        case "coffee": DrawAt(g, A("CROISSANT"), -5, P.BodyTop + bite + dy, bx, by, ps, fx, false, true)
        case "onigiri": DrawAt(g, A("BENTO"), 9.5, P.BodyTop + 1 + bite + dy, bx, by, ps, fx, false, true)
        default: DrawAt(g, A("RICEBOWL"), 9.5, P.BodyTop + 1 + bite + dy, bx, by, ps, fx, false, true)
        }
    }

    func OrigShelfRows() -> Int {
        let hat = (w.SeasonNow == "xmas" || Level() >= 3) ? Math.Max(0, 4 - P.HatRow) : 0
        return 16 + Math.Max(P.TopRows, hat) + 1
    }

    // ---------- 櫃子裡：半糖彈彈、醒醒打瞌睡（晚上反而醒著）、糰糰嚼嚼、貼貼角翹翹寫便條 ----------
    func DrawOrigShelf(_ g: Graphics, _ fx: Int, _ bx: Int, _ by: Int, _ ps: Int, _ flip: Bool, _ tt: Double, _ blink: Bool, _ cell: Rectangle) {
        var head = "HEAD", body = "BODY", legs = "LEGS_A"
        var face: String? = nil
        var hop = 0
        var marker = false, zz = false
        switch P.Id {
        case "boba":
            if Night { legs = "LEGS_SIT"; face = (tt % 6) < 4 ? "SLEEPY" : nil }
            else if (tt % 4.5) < 0.6 { hop = -ps * ((tt % 4.5) < 0.3 ? 2 : 1); body = "BODY_J"; face = "HAPPY" }
            else if blink { face = "SLEEPY" }
        case "coffee":
            if Night { face = "PANDA" }
            else if (tt % 9) < 1.3 { face = "WIDE"; head = "HEAD_UP"; body = "BODY_UP" }   // 突然醒來
            else { face = "SLEEPY"; zz = true }
        case "onigiri":
            if Night { legs = "LEGS_SIT"; face = (tt % 5) < 3.5 ? "SLEEPY" : nil }
            else if (tt % 7) < 1.6 { face = Math.Floor(tt * 3) % 2 == 0 ? "CHEW" : nil }
            else if (tt % 7) > 5.8 { head = "HEAD_UP"; face = "HAPPY" }                        // 伸懶腰
            else if blink { face = "SLEEPY" }
        default:
            if Night { legs = "LEGS_SIT"; face = (tt % 6) < 4 ? "SLEEPY" : nil }
            else if (tt % 8) < 2.2 { marker = true }
            else if blink { face = "SLEEPY" }
        }
        var rows = ORows(head, body, legs, face)
        if Is("coffee") && Math.Floor(tt * 1.6) % 2 == 1 { let sb = A("STEAM_B"); for i in 0..<sb.count { rows[i] = sb[i] } }
        if Is("sticky") && !Night && (tt % 3.1) < 0.35 { let fl = A("FLAP"); for i in 0..<fl.count { rows[i] = fl[i] } }
        DrawPix(g, rows, bx - (rows[0].count - 12) / 2 * ps, by + (16 - rows.count) * ps + hop, ps, flip, false, true)
        DrawAccessories(g, bx, by + hop, ps, flip, 0, face == nil)
        if marker { DrawAt(g, A("MARKER"), 11 + Math.Sin(tt * 16) * 0.5, 9, bx, by, ps, flip, false, true) }
        if zz {
            let zp = Math.Max(1, ps / 2)
            let ph = (tt * 0.5) % 1
            if ph < 0.85 { DrawPix(g, Pet.ZZ, bx + 12 * ps + CInt(ph * 4 * Double(ps)), by - CInt(ph * 6 * Double(ps)), zp, false, false, false) }
        }
        if w.Lunch {
            switch P.Id {
            case "boba": DrawAt(g, A("CHICKEN"), 10, P.BodyTop - 1, bx, by, ps, flip, false, true)
            case "coffee": DrawAt(g, A("CROISSANT"), -4, P.BodyTop, bx, by, ps, flip, false, true)
            case "onigiri": DrawAt(g, A("BENTO"), 8.5, P.BodyTop + 1, bx, by, ps, flip, false, true)
            default: DrawAt(g, A("RICEBOWL"), 9, P.BodyTop + 1, bx, by, ps, flip, false, true)
            }
        }
    }
}

// ================= 公仔櫃：方格紙背板（像筆記本）=================
//@@IN ShelfForm
    var Orig = false                    // 續命小隊：格子背板是淡淡的方格紙，大格釘一張小便利貼
//@@END

extension ShelfForm {
    func DrawGridPaper(_ g: Graphics, _ inner: RectangleF, _ tall: Bool) {
        let st = g.Save()
        g.SetClip(inner)
        let step = Math.Max(4.0, Double(U) * 2.6)
        let gp = Pen(Night ? Color.FromArgb(26, 200, 210, 255) : Color.FromArgb(40, 80, 120, 170), 1.0)
        var gx = inner.X + step * 0.5
        while gx < inner.Right { g.DrawLine(gp, gx, inner.Y, gx, inner.Bottom); gx += step }
        var gy = inner.Y + step * 0.5
        while gy < inner.Bottom { g.DrawLine(gp, inner.X, gy, inner.Right, gy); gy += step }
        if tall {
            // 大格右上角釘一張小便利貼（畫一顆愛心）
            let u = Math.Max(2, U * 3 / 4)
            let du = Double(u)
            let nx = inner.Right - 13 * du, ny = inner.Y + 4 * du
            g.FillRectangle(SolidBrush(Color.FromArgb(50, 60, 40, 10)), nx + du, ny + du, 9 * du, 9 * du)
            g.FillRectangle(SolidBrush(Night ? C(0xC8B05A) : C(0xFFE45C)), nx, ny, 9 * du, 9 * du)
            g.FillRectangle(SolidBrush(Night ? C(0xAC9440) : C(0xF2CC3A)), nx, ny, 9 * du, 2 * du)
            let heart: [String] = [".pp.pp.", "ppppppp", ".ppppp.", "..ppp..", "...p..."]
            let hb = SolidBrush(Night ? C(0xC87A88) : C(0xFF8FA8))
            for r in 0..<heart.count {
                let row = Array(heart[r])
                for c in 0..<row.count { if row[c] != "." { g.FillRectangle(hb, nx + Double(1 + c) * du, ny + Double(3 + r) * du, du, du) } }
            }
            g.FillEllipse(SolidBrush(Night ? C(0x9A3A3A) : C(0xE04848)), nx + 3.5 * du, ny - 0.8 * du, 2 * du, 2 * du)
        }
        g.Restore(st)
    }
}

// ================= World：續命小隊的串場、點名、大合照、下班 =================
//@@IN World
    var oLunchSeen = "", oTeaDay = ""
//@@END

extension World {
    var OrigLineup: Bool { return lineup == Pal.Original }

    // 沒指定哪一櫃時：照上次的；全新安裝（什麼都還沒存過）就是續命小隊。舊使用者完全不變。
    // mac: World.init 在 super.init 之前就要用，所以是 static（只用到 static 的 ReadText／WriteText／FilePath）
    static func StartLineup() -> String {
        let saved = World.ReadText("lineup.txt")
        if saved != "" { return saved }
        let fm = FileManager.default
        var fresh = !fm.fileExists(atPath: World.FilePath("out.txt")) && !fm.fileExists(atPath: World.FilePath("profile.txt")) && !fm.fileExists(atPath: World.FilePath("usage.txt"))
        // <fan>
        if fresh && !App.Isolated {
            // mac: 舊版 Spidey（SpideyDesktop.swift）的資料在 ~/Library/Application Support/SpideyDesktop（bond.txt／pats.txt，見 Migrate）。
            //      這個資料夾現在也是 VS Code 放程式和 socket 的地方，一定存在，所以看舊的資料檔在不在（Windows 是看資料夾在不在）。
            let old = NSHomeDirectory() + "/Library/Application Support/SpideyDesktop"
            if fm.fileExists(atPath: old + "/bond.txt") || fm.fileExists(atPath: old + "/pats.txt") { fresh = false }   // 從舊版 Spidey 小夥伴升級的：維持經典一櫃
        }
        // </fan>
        if !fresh { return "" }
        World.WriteText("lineup.txt", Pal.Original)   // 記下來：下次開機（沒帶參數）還是續命小隊
        return Pal.Original
    }

    func OrigOrder(_ l: List<Pet>) -> List<Pet> {
        let o = List<Pet>()
        for id in Pal.OriginalIds { for p in l { if p.P.Id == id { o.Add(p) } } }
        return o
    }

    func OPal(_ id: String) -> Pal! { return Pal.Get(id) }
    func OArt(_ owner: String, _ name: String) -> [String]! { let p: Pal! = Pal.Get(owner); return p != nil && p.Art.ContainsKey(name) ? p.Art[name] : nil }

    // ---------- 道具：珍珠、便條 ----------
    func OrigPearlShot(_ b: Pet, _ i: Int) {
        let a = b.OStrawTip()
        let wa = WA(b.Cx, b.Foot - 4)
        let tx = World.Mid(b.Cx + Double(b.dir) * Double(90 + i * 60) * k, Double(wa.Left + 10), Double(wa.Right - 10))
        Toss(OArt("boba", "PEARL"), OPal("boba"), a, PointF(tx, b.Foot - 2 * Double(S)), 0.55 + Double(i) * 0.08, Double(70 + i * 20) * k, false, 0.8, nil)
    }

    func OrigPearls(_ b: Pet, _ n: Int) {
        let a = b.OStrawTip()
        let wa = WA(b.Cx, b.Foot - 4)
        for i in Loop(0, n) {
            let side: Double = i % 2 == 0 ? -1 : 1
            let tx = World.Mid(b.Cx + side * (40 + rnd.NextDouble() * 160) * k, Double(wa.Left + 10), Double(wa.Right - 10))
            Toss(OArt("boba", "PEARL"), OPal("boba"), a, PointF(tx, b.Foot - 2 * Double(S)), 0.6 + rnd.NextDouble() * 0.4, (120 + rnd.NextDouble() * 120) * k, false, 0.9, nil)
        }
    }

    func OrigNotes(_ s: Pet, _ n: Int) {
        let a = s.OHandPoint()
        let wa = WA(s.Cx, s.Foot - 4)
        let kinds: [String] = ["MINI_NOTE", "NOTE_CHECK", "MINI_NOTE", "NOTE_DRINK"]
        for i in Loop(0, n) {
            let side: Double = i % 2 == 0 ? -1 : 1
            let tx = World.Mid(s.Cx + side * (50 + rnd.NextDouble() * 150) * k, Double(wa.Left + 10), Double(wa.Right - 10))
            Toss(OArt("sticky", kinds[i % kinds.count]), OPal("sticky"), a, PointF(tx, s.Foot - 4 * Double(S)), 0.7 + rnd.NextDouble() * 0.4, (90 + rnd.NextDouble() * 90) * k, true, 1.2, nil)
        }
    }

    func OrigNoteToCursor(_ s: Pet, _ delay: Double) {
        let ss = s
        Later(delay) { [self] in
            if !ss.Out { return }
            let c = Cursor.Position
            let wa = WA(Double(c.X), Double(c.Y))
            let to = PointF(World.Mid(Double(c.X) + 30 * k, Double(wa.Left + 20), Double(wa.Right - 20)), World.Mid(Double(c.Y) - 30 * k, Double(wa.Top + 20), Double(wa.Bottom - 20)))
            Toss(OArt("sticky", rnd.NextDouble() < 0.5 ? "MINI_NOTE" : "NOTE_CHECK"), OPal("sticky"), ss.OHandPoint(), to, 0.8, 80 * k, false, 3.5, nil)
            ss.Say(Pick2("貼給你！♥", "這張給你：今天也很棒 ✓"), 1.8)
        }
    }

    func OrigNoteAbove(_ s: Pet, _ kind: String) {
        let a = s.OHandPoint()
        var b = s.OTopPoint()
        b.Y -= 10 * Double(S)
        Toss(OArt("sticky", kind), OPal("sticky"), a, b, 0.5, 30 * k, false, 2.0, nil)
    }

    // ---------- 選單 ----------
    func OrigMenuItems(_ p: Pet) -> [[String]]? {
        switch p.P.Id {
        case "boba":
            return [["抱抱 ♥", "hug"], ["打招呼", "hi"], ["敲敲螢幕", "knock"], ["吸管撐竿跳", "sig"],
                    ["噗珍珠", "shoot"], ["跳到別的視窗上", "jump"], ["瞇一下", "sleep"], ["丟球給她 ⚾", "ball"]]
        case "coffee":
            return [["抱抱 ♥", "hug"], ["打招呼", "hi"], ["敲敲螢幕（呼～）", "knock"], ["續杯！", "sig"],
                    ["打個哈欠", "yawn"], ["跳到別的視窗上", "jump"], ["補眠", "sleep"], ["丟球給他 ⚾", "ball"]]
        case "onigiri":
            return [["抱抱 ♥", "hug"], ["打招呼 吃飽沒？", "hi"], ["敲敲螢幕", "knock"], ["海苔衝浪", "sig"],
                    ["滾一滾", "tumble"], ["飯匙揮一揮", "paddle"], ["睡覺", "sleep"], ["丟球給他 ⚾", "ball"]]
        default:
            return [["貼貼 ♥", "hug"], ["打招呼", "hi"], ["敲敲螢幕", "knock"], ["貼到視窗上", "sig"],
                    ["寫一張便條給你", "write"], ["跳到別的視窗上", "jump"], ["睡覺", "sleep"], ["丟球給她 ⚾", "ball"]]
        }
    }

    func AddOrigMenu(_ m: ContextMenuStrip) {
        let grp = ToolStripMenuItem("續命小隊一起…")
        let gs: [[String]] = [["揪團訂飲料 🥤", "order"], ["下午茶續命乾杯", "teatime"], ["大合照 📷", "photo"],
                              ["點名", "rollcall"], ["下班說再見", "byebye"]]
        for gi in gs { let key = gi[1]; grp.DropDownItems.Add(gi[0], nil, { [self] in OrigScene(key) }) }
        m.Items.Add(grp)
    }

    // ---------- 每一格：午餐、下午三點 ----------
    func OrigTick(_ dt: Double) {
        if !OrigLineup { return }
        if LunchState != oLunchSeen {
            if LunchState == "eat" && oLunchSeen == "" && OutCount() >= 2 { Later(4) { [self] in if scene == nil && OrigLineup { OrigScene("lunch") } } }
            oLunchSeen = LunchState
        }
        let n = DateTime.Now
        let today = n.ToString("yyyy-MM-dd")
        if n.Hour == 15 && n.Minute < 10 && !Night && oTeaDay != today && scene == nil && OutCount() >= 2 && Feat("scenes") && !focusOn && !quietOn {
            oTeaDay = today
            OrigScene("teatime")
        }
    }

    // ---------- 串場：大家一起 ----------
    func OrigGroup(_ n: Int) {
        let r = rnd.NextDouble()
        if r < 0.35 { OrigScene("order") } else if r < 0.6 { OrigScene("teatime") } else { OrigPhoto() }
    }

    func OrigScene(_ key: String) {
        let outs = OrigOrder(OutPets())
        if outs.Count < 2 && key != "rollcall" && key != "byebye" { AllOut(); Later(2.6) { [self] in if OrigLineup { OrigScene(key) } }; return }
        switch key {
        case "order": SceneOrder(outs)
        case "teatime": SceneTeaTime(outs)
        case "lunch": SceneOrigLunch(outs)
        case "photo", "group": OrigPhoto()
        case "rollcall":
            let ids = List<String>()
            for p in outs { ids.Add(p.P.Id) }
            if ids.Count == 0 { ids.AddRange(Pal.OriginalIds) }
            OrigRollCall(ids)
        case "byebye": OrigNight(false)
        default: break
        }
    }

    // mac: C# 少一隻（Get 回 null）時在 Begin 丟例外被 Later 吞掉；這裡少一隻就不演（同 PikPairScene）
    func OrigPairScene(_ key: String) {
        func g(_ id: String) -> Pet? { return Get(id) }
        switch key {
        case "boba-coffee": if let a = g("boba"), let b = g("coffee") { SceneLatte(a, b) }
        case "boba-onigiri": if let a = g("boba"), let b = g("onigiri") { SceneCombo(a, b) }
        case "boba-sticky": if let a = g("boba"), let b = g("sticky") { SceneDrinkNote(a, b) }
        case "coffee-onigiri": if let a = g("coffee"), let b = g("onigiri") { SceneBreakfast(a, b) }
        case "coffee-sticky": if let a = g("coffee"), let b = g("sticky") { SceneDeadline(a, b) }
        case "onigiri-sticky": if let a = g("onigiri"), let b = g("sticky") { SceneImLunch(a, b) }
        default: break
        }
    }

    // ---------- 半糖 × 醒醒：珍珠拿鐵 ----------
    func SceneLatte(_ b: Pet, _ c: Pet) {
        Begin(b, c)
        At(0) { [self] in Face(b, c); b.ScenePose("idle", 30); c.OPose("doze", 30); c.Say("……zZ（站著睡著了）", 2); c.Mark(3) }
        At(2.2) { b.Say("醒醒～醒醒！上班了啦！", 2) }
        At(4.4) { c.Say("……再睡五分鐘", 1.8) }
        At(6.4) { [self] in
            b.FaceTo(c); b.OPose("blow", 1.4); b.Say("那…分你一顆珍珠！噗！", 1.8)
            var to = c.OTopPoint(); to.Y -= 1 * Double(S)
            Toss(OArt("boba", "PEARL"), OPal("boba"), b.OStrawTip(), to, 0.75, 90 * k, false, 0, { c.OLatte(70); c.OWire(6); c.OPose("wide", 30); c.Burst(6) })
        }
        At(8.6) { c.Say("！！……這是什麼？好好喝", 2.2) }
        At(11.0) { b.OPose("cheer", 2); b.Say("珍珠拿鐵！我們合體了～", 2.2) }
        At(13.4) { [self] in Face(b, c); b.ScenePose("hug", 2.4); c.ScenePose("hug", 2.4); c.Say("……醒了。謝謝。", 2.2) }
        At(16) { }
    }

    // ---------- 半糖 × 糰糰：超商早餐組合價 ----------
    func SceneCombo(_ b: Pet, _ o: Pet) {
        Begin(b, o)
        var tag: World.Prop? = nil
        At(0) { [self] in Face(b, o); b.ScenePose("idle", 30); o.ScenePose("idle", 30); o.Say("半糖！我們一起站好～", 1.8) }
        At(2.0) { o.WalkTo(b.Cx + Double(o.Cx < b.Cx ? -1 : 1) * Double(b.SW) * 1.35, 2) }
        At(3.6) { [self] in
            let mid = (b.Cx + o.Cx) / 2
            b.dir = b.Cx < o.Cx ? -1 : 1; o.dir = o.Cx < b.Cx ? -1 : 1
            b.OPose("cheer", 30); o.OPose("cheer", 30)
            let low = Math.Max(b.Foot, o.Foot) - 4 * Double(S)   // 像貨架上的價格牌：貼在腳邊
            tag = Toss(OArt("boba", "TAG"), OPal("boba"), PointF(mid, low - 200 * k), PointF(mid, low), 0.6, 0, false, 12, nil)
            b.Say("超商早餐組合！", 1.8)
        }
        At(5.6) { o.Say("飯糰＋飲料，組合價 49 元！", 2.2) }
        At(8.0) { b.Say("第二件六折喔～", 1.8) }
        At(10.0) { o.OPose("think", 30); o.Say("……我們是在賣自己嗎？", 2.2); o.Mark(2) }
        At(12.4) { [self] in RemoveProp(tag); Face(b, o); b.ScenePose("hug", 2.4); o.ScenePose("hug", 2.4); b.Say("嘿嘿～反正我們最搭！", 2.2) }
        At(15) { }
    }

    // ---------- 半糖 × 貼貼：揪團訂飲料 ----------
    func SceneDrinkNote(_ b: Pet, _ s: Pet) {
        Begin(b, s)
        var note: World.Prop? = nil
        At(0) { [self] in Face(b, s); b.ScenePose("idle", 30); s.OPose("write", 30); s.Say("揪團訂飲料囉！📝", 1.8) }
        At(2.0) { s.Say("半糖要喝什麼？", 1.6) }
        At(3.8) { b.OPose("cheer", 1.4); b.Say("珍奶，半糖少冰！", 1.8) }
        At(5.8) { s.Say("珍奶…半糖…少冰…（寫寫寫）", 2) }
        At(7.8) { [self] in
            var to = b.OFacePoint(); to.Y += 4 * Double(S)
            note = Toss(OArt("sticky", "NOTE_DRINK"), OPal("sticky"), s.OHandPoint(), to, 0.6, 50 * k, false, 6, nil)
            s.OPose("cheer", 1.2)
        }
        At(8.8) { b.ScenePose("idle", 30); b.Say("……等等，這不就是我嗎？", 2.2); b.Mark(2) }
        At(11.2) { s.OPose("panic", 1.8); s.Say("啊！點到你了！", 1.8) }
        At(13.2) { [self] in RemoveProp(note); b.OPose("cheer", 1.4); b.Say("沒關係～我最喜歡我自己了 ♥", 2.2) }
        At(15.6) { [self] in Face(b, s); b.ScenePose("hug", 2.4); s.ScenePose("hug", 2.4); s.Say("貼貼～", 1.8) }
        At(18.2) { }
    }

    // ---------- 醒醒 × 糰糰：早餐要吃 ----------
    func SceneBreakfast(_ c: Pet, _ o: Pet) {
        Begin(c, o)
        At(0) { [self] in Face(c, o); c.OPose("doze", 30); o.ScenePose("idle", 30); o.Say("醒醒，早餐吃了沒？", 1.8) }
        At(2.0) { c.Say("……我喝咖啡就好", 1.8) }
        At(4.0) { o.OPose("cheer", 1.4); o.Say("不行！早餐要吃！", 1.8) }
        At(5.8) { [self] in _ = Toss(OArt("onigiri", "MINI_ONIGIRI"), OPal("onigiri"), o.OHandPoint(), c.OHandPoint(), 0.7, 80 * k, true, 0, { c.OHold = "mini" }) }
        At(6.8) { c.OPose("pose", 30); c.Say("（咬一口）……", 1.6) }
        At(9.0) { c.OHold = ""; c.OWire(5); c.OPose("wide", 30); c.Burst(6); c.Say("……有飽足感。醒了。", 2.2) }
        At(11.4) { o.Say("吃飽沒？", 1.4) }
        At(12.6) { c.Say("吃飽了。", 1.4) }
        At(14.0) { [self] in Face(c, o); c.ScenePose("hug", 2.4); o.ScenePose("hug", 2.4); o.Say("嘿嘿，早餐最重要！", 2) }
        At(16.6) { }
    }

    // ---------- 醒醒 × 貼貼：死線前一晚 ----------
    func SceneDeadline(_ c: Pet, _ s: Pet) {
        Begin(c, s)
        At(0) { [self] in Face(c, s); c.ScenePose("idle", 30); s.OPose("panic", 30); s.Say("報告明天要交！！還沒寫完！", 2.2); s.Mark(1) }
        At(2.4) { c.OWire(10); c.OPose("wide", 30); c.Say("我陪你熬。（眼睛睜大）", 2.2) }
        At(4.8) { s.OPose("cheer", 1.2); s.Say("真的嗎？那…一起寫！", 2) }
        At(7.0) { s.OPose("write", 30); s.Say("（寫寫寫）", 1.4) }
        At(7.8) { c.Say("寫一段，喝一口…", 1.8) }
        At(10.0) { s.ScenePose("idle", 30); s.Say("……等等。", 1.4); s.Mark(2) }
        At(11.4) { [self] in
            let to = c.OFacePoint()
            Toss(OArt("sticky", "NOTE_ZZ"), OPal("sticky"), s.OHandPoint(), to, 0.6, 60 * k, false, 0, { c.ONote(14); c.OWire(0); c.OPose("doze", 30) })
            s.Say("先睡覺！健康第一！", 2)
        }
        At(14.0) { c.Say("……zZ（被貼睡著了）", 2.2); c.Mark(3) }
        At(16.4) { s.OPose("cheer", 1.4); s.Say("鬧鐘我幫你訂好了 📝", 2) }
        At(18.6) { }
    }

    // ---------- 糰糰 × 貼貼：我就是午餐 ----------
    func SceneImLunch(_ o: Pet, _ s: Pet) {
        Begin(o, s)
        var note: World.Prop? = nil
        At(0) { [self] in Face(o, s); o.ScenePose("idle", 30); s.OPose("write", 1.6); s.Say("提醒！12 點要吃午餐！", 1.8) }
        At(2.0) { [self] in
            var to = o.OFacePoint(); to.Y += 3 * Double(S)
            note = Toss(OArt("sticky", "NOTE_BANG"), OPal("sticky"), s.OHandPoint(), to, 0.6, 50 * k, false, 8, nil)
        }
        At(2.8) { o.OPose("cheer", 1.2); o.Say("好！吃什麼呢？", 1.6) }
        At(4.6) { o.OPose("think", 30); o.Say("……等等，我就是午餐耶？", 2.2) }
        At(7.0) { s.OPose("panic", 1.8); s.Say("啊！那、那你不能被吃！", 2) }
        At(9.2) { [self] in RemoveProp(note); o.OPose("cheer", 1.4); o.Say("嘿嘿，我們一起去吃便當吧！", 2.2) }
        At(11.6) { [self] in Face(o, s); o.ScenePose("hug", 2.4); s.ScenePose("hug", 2.4); s.Say("貼貼～", 1.6); o.Say("抱緊緊！", 1.6) }
        At(14.2) { }
    }

    // ---------- 大家：揪團訂飲料 ----------
    func SceneOrder(_ outs: List<Pet>) {
        let s: Pet! = Get("sticky")
        let boss: Pet = s != nil && outs.Contains(s) ? s! : outs[0]
        Begin(outs.ToArray())
        let lr = LineUp(outs, Lead(), 1.7)
        let cx = (lr[0] + lr[1]) / 2
        At(0) { boss.Say("揪團訂飲料囉！大家要喝什麼？📝", 2.2) }
        At(4.4) { for p in outs { p.FaceTo(boss); p.ScenePose("idle", 30) }; boss.OPose("write", 30); boss.dir = boss.Cx < cx ? 1 : -1 }
        var d = 5.0
        for p in outs {
            let pp = p
            let line = pp.P.Id == "boba" ? "珍奶，半糖少冰！" : (pp.P.Id == "coffee" ? "冰美式。大杯。" : (pp.P.Id == "onigiri" ? "我要…可以吃的！" : "我要綠茶，無糖～（記下來）"))
            At(d) { pp.OPose("cheer", 1.2); pp.Say(line, 1.9) }
            d += 2.1
        }
        At(d + 0.3) { boss.ScenePose("idle", 30); boss.Say("好！我下單了～", 1.8) }
        At(d + 3.0) { [self] in
            let b: Pal! = OPal("boba")
            for i in 0..<outs.Count {
                let pp = outs[i]
                Toss(b.Art["DRINK"], b, PointF(cx, lr[2] - 260 * k), pp.OHandPoint(), 0.8 + Double(i) * 0.15, 40 * k, false, 4.5, nil)
            }
            boss.Say("外送到了！🛵", 1.8)
        }
        At(d + 4.8) { for p in outs { p.OPose("cheer", 2.2); p.Mark(0) }; outs[0].Say("續命成功！乾杯～", 2.2) }
        At(d + 7.6) { }
    }

    // ---------- 大家：下午三點，下午茶續命乾杯 ----------
    func SceneTeaTime(_ outs: List<Pet>) {
        let b: Pet! = Get("boba")
        let lead: Pet = b != nil && outs.Contains(b) ? b! : outs[0]
        Begin(outs.ToArray())
        LineUp(outs, Lead(), 1.6)
        At(0) { lead.Say("三點了！下午茶續命時間～🥤", 2.2) }
        At(4.4) { for p in outs { p.FaceTo(lead); p.ScenePose("idle", 30) } }
        var d = 4.8
        for p in outs {
            let pp = p
            let line = pp.P.Id == "boba" ? "甜度補滿！" : (pp.P.Id == "coffee" ? "咖啡因補滿。" : (pp.P.Id == "onigiri" ? "肚子補滿！" : "水分補滿！記下來 ✓"))
            At(d) { pp.OPose("cheer", 1.4); pp.Say(line, 1.6); if pp.P.Id == "coffee" { pp.OWire(6) } }
            d += 1.7
        }
        At(d + 0.4) { for p in outs { p.OPose("cheer", 2.4); p.AddHeart(); p.Burst(5) }; lead.Say("續命！乾杯～！", 2.2) }
        At(d + 3.2) { for p in outs { p.ScenePose("wave", 1.6) } }
        At(d + 5.0) { }
    }

    // ---------- 大家：午餐一起吃（各拿各的） ----------
    func SceneOrigLunch(_ outs: List<Pet>) {
        Begin(outs.ToArray())
        LineUp(outs, Lead(), 1.8)
        At(0) { outs[0].Say("午餐時間！大家一起吃～🔔", 2) }
        var d = 4.6
        for p in outs {
            let pp = p
            let line = pp.P.Id == "boba" ? "雞排配珍奶，人生巔峰！" : (pp.P.Id == "coffee" ? "我吃可頌…配咖啡（我自己）" : (pp.P.Id == "onigiri" ? "雞腿便當！…飯糰吃便當很奇怪嗎？" : "滷肉飯！記下來：好吃 ✓"))
            At(d) { pp.ScenePose("idle", 30); pp.Say(line, 2.3) }
            d += 2.5
        }
        At(d + 0.4) { for p in outs { p.ScenePose("wave", 1.6) }; outs[outs.Count - 1].Say("開動！", 1.6) }
        At(d + 2.4) { }
    }

    // ---------- 大合照 ----------
    func OrigPhoto() {
        let outs = OrigOrder(OutPets())
        if outs.Count < 2 { AllOut(); Later(2.5) { [self] in if OrigLineup { OrigPhoto() } }; return }
        let l: Pet = Lead()
        Begin(outs.ToArray())
        let lr = LineUp(outs, l, 1.75)
        let left = lr[0], right = lr[1], foot = lr[2]
        At(0) { l.Say("續命小隊，來拍照～排好排好！", 2) }
        At(5.2) {
            for p in outs {
                p.dir = p.Cx < (left + right) / 2 ? 1 : -1
                if p.P.Id == "coffee" { p.OWire(4); p.OPose("wide", 30) } else { p.OPose("cheer", 30) }
            }
            l.Say("笑一個～ 3、2、1！", 1.6)
        }
        At(6.6) { [self] in
            Flash(Rectangle.FromLTRB(CInt(left - 120 * k), CInt(foot - 220 * k), CInt(right + 120 * k), CInt(foot + 20 * k)))
            let s: Pet! = Get("sticky")
            if s != nil && outs.Contains(s) { OrigNoteAbove(s, "MINI_NOTE") }
        }
        var d = 7.4
        for p in outs {
            let pp = p
            let line = pp.P.Id == "boba" ? "甜度滿分！🥤" : (pp.P.Id == "coffee" ? "……我有睜眼嗎？" : (pp.P.Id == "onigiri" ? "糰糰有拍到嗎？" : "記下來：今日合照 ✓"))
            At(d) { pp.Say(line, 1.15) }
            d += 1.2
        }
        At(d + 0.4) { }
    }

    // ---------- 早上點名：一隻一隻出來 ----------
    func OrigRollCall(_ ids: List<String>) {
        let order = List<Pet>()
        for id in Pal.OriginalIds { if ids.Contains(id) && Get(id) != nil { order.Add(Get(id)) } }
        var d = 0.4
        for p in order {
            let pp = p
            let line = pp.P.Id == "boba" ? "半糖！🥤" : (pp.P.Id == "coffee" ? "醒醒…（還沒醒）☕" : (pp.P.Id == "onigiri" ? "糰糰！吃飽沒？🍙" : "貼貼！待辦寫好了！📝"))
            Later(d) { [self] in if !pp.Out { BringOut(pp, false) } }
            Later(d + 1.0) { pp.Say(line, 1.8) }
            d += 1.6
        }
        Later(d + 1.0) { [self] in
            for p in order { if p.Out && p.Grounded() { p.ScenePose("wave", 1.8) } }
            if order.Count > 0 { Lead().Say("續命小隊，報到！", 2.6) }
        }
    }

    // ---------- 下班：貼貼貼一張「回家」，大家一個一個回櫃子（醒醒最後才睡）----------
    func OrigNight(_ nag: Bool) {
        let outs = OrigOrder(OutPets())
        if outs.Count == 0 { Lead().Say("續命小隊…下班囉～", 2.4); return }
        outs.Sort { a, b in let ka = a.P.Id == "coffee" ? 1 : 0, kb = b.P.Id == "coffee" ? 1 : 0; return ka < kb ? -1 : (ka == kb ? 0 : 1) }
        Begin(outs.ToArray())
        for p in outs { if p.Grounded() { p.ScenePose("idle", 60) } }
        var d = 0.2
        if nag { for p in outs { let pp = p; At(d) { pp.Say(pp.L("nag"), 2.6) }; d += 2.8 } }
        let s: Pet! = Get("sticky")
        if s != nil && outs.Contains(s) {
            At(d) { s.OPose("write", 1.4); s.Say("寫好了：下班！🏠", 1.8) }
            At(d + 1.2) { [self] in OrigNoteAbove(s, "NOTE_HOME") }
            d += 2.6
        }
        for p in outs {
            let pp = p
            let line = pp.P.Id == "boba" ? "打烊囉～明天再揪！" : (pp.P.Id == "onigiri" ? "回家吃飯囉～晚安！" : (pp.P.Id == "sticky" ? "明天的待辦，我都記好了！" : (Night ? "你們先睡…我也…zZ" : "……終於可以睡了")))
            At(d) { pp.ScenePose("wave", 2); pp.Say(line, 2.2) }
            At(d + 1.6) { pp.InScene = false; if pp.Out { pp.StowToShelf(false) } }
            d += 2.6
        }
        At(d + 0.6) { let last = outs[outs.Count - 1]; last.Say("續命小隊，下班！明天見～", 2.6) }
        At(d + 3.4) { }
    }

    // ---------- 通知的開場白、搶票 ----------
    static func OrigFlavor(_ id: String, _ kind: String) -> String? {
        if id != "boba" && id != "coffee" && id != "onigiri" && id != "sticky" { return nil }
        let keys: [String] = ["ci-run", "ci-ok", "ci-fail", "cmd-ok", "cmd-fail", "meeting", "meeting-now", "jira", "worklog",
                              "remind", "pc-cpu", "pc-ram", "pc-disk", "net-down", "net-up", "vpn", "download"]
        let i = keys.IndexOf(kind)
        if i < 0 { return nil }
        let bo: [String] = ["CI 出杯中～", "CI 過了！加珍珠！", "嗚…CI 灑出來了：", "跑完了～甜：", "咦？沒成功：", "等等要開會喔：", "開會了！快去～", "有新的 Jira 喔：", "今天的日誌好了～",
                            "⏰ 半糖提醒你：", "電腦好燙，要加冰了：", "記憶體快滿杯了：", "硬碟快滿杯了：", "網路斷了…外送叫不到了！", "網路回來了！甜～", "連不到公司網路（VPN 斷了？）", "下載好了～"]
        let co: [String] = ["CI 開跑了…我也要開機了：", "CI 過了。乾杯 ☕", "CI 倒了。……我醒了：", "跑完了：", "失敗了。先續杯再看：", "等等開會…我會撐住：", "開會了。醒醒：", "新的 Jira：", "日誌好了，可以睡了：",
                            "⏰ 醒醒提醒你（我醒著）：", "電腦比我還燙：", "記憶體快滿了：", "硬碟快滿了：", "網路斷了…正好補眠", "網路回來了。", "連不到公司網路（VPN 斷了？）", "下載好了："]
        let on: [String] = ["CI 出發！吃飽了嗎：", "CI 過了！加一顆滷蛋！", "CI 摔倒了！糰糰來扶：", "跑完了！嘿嘿：", "失敗了…吃飽再試：", "等等要開會，先吃點東西：", "開會了！快去：", "有新的 Jira：", "今天的日誌好了，吃飯吧：",
                            "⏰ 糰糰提醒你：", "電腦好燙，像剛出爐：", "記憶體快滿了，跟便當一樣：", "硬碟快塞爆了：", "網路斷了！嗚…", "網路回來了！嘿嘿", "連不到公司網路（VPN 斷了？）", "下載好了！"]
        let st: [String] = ["記下來：CI 開跑：", "CI 過了！打勾 ✓", "CI 掛了！記下來：", "跑完了 ✓：", "失敗了！記下來：", "提醒：等等要開會：", "開會了！快去！📝", "新的 Jira，記下來：", "日誌好了 ✓：",
                            "⏰ 提醒你：", "電腦好燙！記下來：", "記憶體快滿了：", "硬碟快滿了：", "網路斷了！記下來…", "網路回來了！✓", "連不到公司網路（VPN 斷了？）", "下載好了 ✓："]
        switch id { case "boba": return bo[i]; case "coffee": return co[i]; case "onigiri": return on[i]; default: break }
        return st[i]
    }

    static func OrigTicket(_ id: String, _ stage: Int, _ n: String, _ h: String) -> String? {
        if id != "boba" && id != "coffee" && id != "onigiri" && id != "sticky" { return nil }
        let bo: [String] = ["🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款喔～", "🎫 " + n + " 再 30 分鐘！半糖陪你等", "🎫 " + n + " 剩 10 分鐘！好緊張～", "🎫 準備！深呼吸～", "🎫 開搶！！衝呀～"]
        let co: [String] = ["🎫 " + n + " 還有 " + h + "開賣。先登入、綁好付款", "🎫 " + n + " 30 分鐘後開賣…我醒著", "🎫 " + n + " 剩 10 分鐘！咖啡因全開", "🎫 準備。手指放好。", "🎫 開搶！！醒了醒了！"]
        let on: [String] = ["🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款！", "🎫 " + n + " 再 30 分鐘！先吃飽", "🎫 " + n + " 剩 10 分鐘！糰糰陪你", "🎫 準備！嘿咻！", "🎫 開搶！！衝衝衝！"]
        let st: [String] = ["🎫 提醒：" + n + " 還有 " + h + "開賣！先登入、綁好付款", "🎫 提醒：" + n + " 再 30 分鐘！", "🎫 提醒：" + n + " 剩 10 分鐘！", "🎫 準備！我幫你倒數！", "🎫 開搶！！快快快！"]
        switch id { case "boba": return bo[stage]; case "coffee": return co[stage]; case "onigiri": return on[stage]; default: break }
        return st[stage]
    }
}
