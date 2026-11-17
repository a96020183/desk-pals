// 60_woban.swift — port of extension/desktop/DeskPals.Woban.cs
// Desk Pals：窩伴小世界（翻翻・破破・綿綿）——原創角色（朋友設計），住在一個書包小屋裡，三間一樣大的房間並排。
// 翻翻＝讀書夥伴（陪你專注、記得你要做的事、慶祝每個小進步；番茄鐘的時候在旁邊翻書陪你）、
// 破破＝照顧日常（提醒喝水、吃飯；午餐時間端飯來）、
// 綿綿＝提醒休息、放鬆、調整心情（用太久電腦的休息提醒由她來講；不跳視窗，慢慢來）。
// 語氣溫柔療癒（跟續命小隊的無厘頭不一樣）。
// 圖跟續命小隊同一套（DeskPals.Original.cs 的 SqArt：pals/lineups.txt → pals/woban/…；書包小屋＝pals/woban/shelf），
// 行為走續命小隊的 Orig* 掛點（P.Orig＝true），這個檔只放窩伴小世界不一樣的地方（Wb*）。
// sig1／sig2（素材線 C:\tmp\dp\woban\PLAN.md §3）：翻翻＝專心看書／完成任務撒花、破破＝抱水壺喝水／打筆電、綿綿＝蓋毯子抱月亮枕／捧熱可可放空。
// 觸發：翻翻 sig1＝番茄鐘專注中、sig2＝專注做完、錯誤清光、上版；破破 sig1＝喝水提醒、sig2＝專注中陪你一起工作；綿綿 sig1＝休息提醒、sig2＝閒晃時放空。
// 圖沒有白邊（NoHalo）、腳下有很淡的落地陰影（woban.txt 的 shadow 1）。設計者署名先不放進 app（等使用者確認）。
import Foundation
import AppKit

// ================= 角色資料 =================
extension Pal {
    static let WobanName = "窩伴小世界"

    static func WobanMake(_ id: String) -> Pal? {
        switch id {
        case "fanfan": return Fanfan()
        case "bobo": return Bobo()
        case "mian": return Mian()
        default: return nil
        }
    }

    // ---------------- 翻翻：讀書夥伴。陪你專注、記得你要做的事、慶祝每個小進步 ----------------
    static func Fanfan() -> Pal
    {
        let p = OrigBase("fanfan", "翻翻")
        p.Move = "shuffle"; p.NightStyle = "sleepy"; p.NightBubble = 2
        p.Accent = C(0x4E86B8); p.Panel = C(0xE4F0FB)
        p.Speed = 38
        p.Say("talk", "今天想先完成哪一件事呢？我幫你記著", "一次做一點點就好，我陪你", "剛剛那一段做得很好喔", "累了就停一下，書不會跑掉的", "你專心的樣子，我很喜歡", "把大事切小一點，就不可怕了", "我在旁邊翻書，你慢慢來", "今天也有往前一點點，真好")
        p.Say("talk_d", "晚上了，今天的進度已經很棒了", "剩下的，明天的你會接住的", "收工吧，我幫你把今天的書籤夾好")
        p.Say("save", "存好了，進度都在 ✓", "存檔完成～又往前一步", "好，記下來了")
        p.Say("save_d", "存好了，今天就到這裡吧", "存了。晚安，明天見")
        p.Say("pats", "嘿嘿，被摸頭了", "謝謝你～我會繼續陪你", "（書頁沙沙地翻了一下）", "這樣很安心", "再一下下就好", "你的手好溫暖")
        p.Say("pats_d", "晚安摸摸，收到了", "嗯…今天辛苦了")
        p.Say("pats_hi", "跟你一起讀書是我最喜歡的時間", "你是我書裡最喜歡的那一頁", "謝謝你每天都來")
        p.Say("hugs", "抱抱～充電完成", "抱一下，再繼續加油", "（把書夾在腋下抱你）")
        p.Say("hugs_d", "晚安抱抱", "抱完就去休息吧")
        p.Say("knock", "叩叩，進度還順利嗎？", "嗨～我在這裡陪你", "（輕輕敲兩下）要不要看一下待辦？")
        p.Say("knock_d", "叩叩，很晚了喔", "今天就到這裡好嗎")
        p.Say("newwin", "新的視窗？我去看看是什麼資料", "這個看起來要好好讀")
        p.Say("newwin_d", "這個明天再看也來得及")
        p.Say("hi", "嗨，我是翻翻。我們一起慢慢前進吧"); p.Say("hi_d", "嗨…晚上了，今天也辛苦了")
        p.Say("wake", "（揉眼睛）你回來了，我們繼續吧"); p.Say("wake_d", "嗯…還在忙嗎？")
        p.Say("dizzy", "頁、頁數都轉亂了…"); p.Say("dizzy_d", "暈暈的…該睡了")
        p.Say("dizzy_ok", "好了，書籤還在"); p.Say("dizzy_ok_d", "好了…休息吧")
        p.Say("tickle", "哈哈，好癢", "不要翻我的頁啦～", "（笑到書掉了）"); p.Say("tickle_d", "最後一下喔")
        p.Say("pat10", "今天第 {n} 次了，你也記得摸摸自己"); p.Say("pat10_d", "第 {n} 次了，晚安")
        p.Say("levelup", "好感度 Lv{n}！拿到「{u}」，夾進我的書裡"); p.Say("levelup_d", "Lv{n}…「{u}」明天再戴")
        p.Say("missed", "好久不見，我一直幫你留著書籤"); p.Say("missed_d", "好久不見…明天見喔")
        p.Say("hover", "嗨～", "在想下一步嗎？", "我在這裡")
        p.Say("seek", "那是什麼？…是重點嗎"); p.Say("seek_lost", "跑掉了，沒關係"); p.Say("seek_got", "抓到了！先畫個重點")
        p.Say("drag", "哇，飛起來了"); p.Say("throw", "書、書籤要掉了～")
        p.Say("shelf_in", "我回房間整理筆記"); p.Say("shelf_in_d", "回房間睡了，晚安")
        p.Say("shelf_out", "（抱著書走出來）我來了"); p.Say("shelf_out_d", "出來了…可是晚上了耶")
        p.Say("ball_go", "球！我去撿～", "等我一下"); p.Say("ball_go_d", "最後一顆喔")
        p.Say("ball_catch", "接到了！還你～", "嘿！丟回去"); p.Say("ball_catch_d", "還你，該休息了")
        p.Say("ball_end", "不玩了嗎？好，回去讀書"); p.Say("ball_end_d", "不玩了，晚安")
        p.Say("ball_far", "好遠喔…我慢慢走過去")
        p.Say("back", "我回來了"); p.Say("back_d", "回來了…")
        p.Say("share_end", "分享完了嗎？我回來囉")
        p.Say("welcome", "歡迎回來！我們從剛剛那裡繼續"); p.Say("welcome_d", "你回來了，今天還要做嗎？")
        p.Say("rest", "{n} 分鐘了，休息一下，大腦才記得住"); p.Say("rest_d", "{n} 分鐘了，今天就到這裡吧")
        p.Say("night_on", "下班時間到了，把書籤夾好吧"); p.Say("night_off", "早安！今天想先完成哪一件？☀")
        p.Say("sleep", "我先閉上眼睛…"); p.Say("sleep_d", "晚安…（書蓋在臉上）")
        p.Say("jump", "嘿！"); p.Say("nojump", "附近沒地方跳，那我繼續看書")
        p.Say("errors", "有 {n} 個錯誤，我們一個一個來"); p.Say("errors_d", "{n} 個錯誤…明天精神好再看")
        p.Say("errors_ok", "錯誤都清掉了！這是個小進步 ✨"); p.Say("errors_ok_d", "修好了，可以安心休息了")
        p.Say("typing", "你好專心喔", "寫得好順～", "我在旁邊安靜陪你"); p.Say("typing_d", "這麼晚還在打字，辛苦了")
        p.Say("done", "{who} 做好了！又完成一件 ✓"); p.Say("done_d", "{who} 做好了，今天收工吧")
        p.Say("wait", "{who} 在等你回覆喔"); p.Say("wait_d", "{who} 在等你，回完就休息")
        p.Say("ask", "{who} 有問題想問你"); p.Say("ask_d", "{who} 在問你，回完就下班")
        p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，要按允許嗎？"); p.Say("stuck_tool_d", "{who} 停了 {n} 分鐘，按一下就好")
        p.Say("stuck", "{who} 好像卡住了，{n} 分鐘沒動"); p.Say("stuck_d", "{who} 卡住 {n} 分鐘了，看一眼就好")
        p.Say("unstuck", "{who} 又動起來了！"); p.Say("unstuck_d", "{who} 動了～")
        p.Say("tag", "上版成功！這一步走得很穩 🎉"); p.Say("tag_dev", "測試機好了，再一步就完成"); p.Say("tag_prod", "正式機上線了！為你撒花 🎉"); p.Say("tag_d", "上版成功，今天到這裡就好")
        p.Say("late23", "很晚了，把書闔上吧 🌙"); p.Say("late12", "午餐時間了，吃完再繼續"); p.Say("late15", "三點了，伸個懶腰再讀")
        p.Say("late_d", "已經下班囉"); p.Say("late_dd", "這麼晚了，去睡吧")
        p.Say("g_late", "這麼晚還在？我陪你，但別太久喔"); p.Say("g_morning", "早安！今天也一點一點來 ☀"); p.Say("g_noon", "午安，吃飯了嗎？")
        p.Say("g_evening", "晚上了，今天辛苦了"); p.Say("g_day", "翻翻來了，今天一起加油"); p.Say("g_d", "下班時間了，你怎麼還在")
        p.Say("app_browser", "在查資料嗎？記得做筆記"); p.Say("app_code", "寫程式呀，一行一行來"); p.Say("app_excel", "好多格子，慢慢對"); p.Say("app_ppt", "做簡報～重點放大一點")
        p.Say("app_word", "在寫報告，先寫完再修"); p.Say("app_chat", "有人找你，回完再回來"); p.Say("app_files", "在找檔案嗎？"); p.Say("app_other", "這是什麼？我也想學")
        p.Say("app_code_d", "還在寫…明天再寫好不好"); p.Say("app_chat_d", "明天再回也可以"); p.Say("app_office_d", "這份明天再做"); p.Say("app_other_d", "下班時間到了")
        p.Say("s_birthday", "生日快樂！今天的你也很棒 🎂", "生日快樂～這一頁要好好收藏")
        p.Say("s_cny", "新年快樂！今年也一起前進 🧧"); p.Say("s_xmas", "聖誕快樂！送你一張書籤 🎄"); p.Say("s_newyear", "新年快樂，新的一本開始了 ✨")
        p.Say("s_halloween", "萬聖節快樂！不給糖就…陪我讀一頁 🎃"); p.Say("s_friday", "星期五了，這週完成好多事")
        p.Say("morning", "翻翻，到！📖", "到～今天也一起")
        p.Say("goodnight", "晚安，今天的書籤夾好了 🌙"); p.Say("nag", "下班了，休息吧", "今天已經很努力了，回家吧")
        p.Say("react", "咦？", "嚇了一跳", "怎麼了？")
        p.Say("o_sig1", "（翻書）我在這裡陪你", "一頁一頁慢慢來", "嗯…這段寫得真好")
        p.Say("o_sig2", "完成一件了！撒花 ✨", "小進步也要慶祝！", "你看，又往前一步了")
        p.Say("focus_start", "{n} 分鐘專注開始，我在旁邊翻書陪你 📖"); p.Say("focus_end", "專注結束！又完成一段 ✨ 休息 5 分鐘 ☕")
        p.Say("sf_class", "🎒 翻翻提醒你上課："); p.Say("sf_class-now", "🎒 上課囉，我幫你記重點："); p.Say("sf_exam-soon", "📚 要考試了，我們一起複習："); p.Say("sf_exam-now", "📚 考試加油，你準備好了：")
        p.Say("sf_event", "等一下有事喔："); p.Say("sf_event-now", "時間到囉："); p.Say("sf_deadline", "📝 翻翻幫你記著："); p.Say("sf_deadline-hot", "📝 快到了，先做最小的一步：")
        p.Say("o_goal", "進了！🏀 小進步！"); p.Say("o_cheer", "好球～"); p.Say("o_miss", "沒進也沒關係，再試一次")
        p.Say("lunch_start", "午餐時間！吃飽才讀得進去 🔔"); p.Say("lunch_nap", "吃飽了…書蓋在臉上睡一下"); p.Say("lunch_end", "下午了，我們繼續")
        p.Say("lunch_eat", "（邊吃邊翻一頁）", "好吃～", "吃飯的時候就專心吃飯")
        p.Say("sc_tea", "我想要一塊餅乾配書"); p.Say("sc_tea_lead", "三點了，大家休息一下 🍵"); p.Say("sc_tea_end", "休息好了，繼續加油～")
        p.Say("sc_lunch", "開動～吃完再讀"); p.Say("sc_photo", "拍好了嗎？夾進相簿"); p.Say("sc_roll", "翻翻，到！📖"); p.Say("sc_bye", "今天辛苦了，明天見")
        p.Flavors("CI 開始跑了，我們等等看：", "CI 過了！小進步 ✨", "CI 沒過，沒關係，一起看看：", "跑完了：", "沒成功，我們再試一次：", "等一下要開會，資料準備好了嗎：", "開會了！去吧，我等你", "有新的 Jira，我幫你記著：", "今天的日誌好了：",
                  "⏰ 翻翻提醒你：", "電腦好燙，讓它也休息一下：", "記憶體快滿了：", "硬碟快滿了，整理一下：", "網路斷了，先看手邊的資料", "網路回來了！", "連不到公司網路（VPN 斷了？）", "下載好了：")
        p.Tickets("🎫 {n} 還有 {h}開賣，先登入、綁好付款喔", "🎫 {n} 再 30 分鐘，我幫你記著", "🎫 {n} 剩 10 分鐘！準備好了嗎", "🎫 準備…深呼吸", "🎫 開搶！！加油！")
        p.Shared()
        return p
    }

    // ---------------- 破破：照顧日常。提醒你喝水、吃飯，把生活的小事放在心上 ----------------
    static func Bobo() -> Pal
    {
        let p = OrigBase("bobo", "破破")
        p.Move = "shuffle"; p.NightStyle = "sleepy"; p.NightBubble = 2
        p.Accent = C(0xD47A5E); p.Panel = C(0xFDE8DF)
        p.Speed = 34
        p.Say("talk", "今天有好好喝水嗎？", "肚子餓了要跟我說喔", "我幫你倒了一杯溫水", "坐久了，腳也要動一動", "小事我幫你記著，你專心就好", "吃點東西，心情會比較好", "今天的你，有好好照顧自己嗎", "慢慢來，不用急")
        p.Say("talk_d", "晚上了，喝杯溫的就去休息吧", "今天也照顧自己了，很棒", "晚餐吃了嗎？")
        p.Say("save", "存好了，放心", "幫你存起來了～", "好，收好了")
        p.Say("save_d", "存好了，收工吧", "存了，晚安")
        p.Say("pats", "嘿嘿，謝謝你", "被摸摸了，好開心", "我也想摸摸你的頭", "（暖暖的）", "你今天辛苦了", "再一下下")
        p.Say("pats_d", "晚安摸摸", "嗯…該休息了")
        p.Say("pats_hi", "有你在，每天都很踏實", "照顧你是我最喜歡的事", "你也要記得照顧自己喔")
        p.Say("hugs", "抱抱～", "給你一個暖暖的抱抱", "（抱緊）今天也辛苦了")
        p.Say("hugs_d", "晚安抱抱", "抱完就去睡喔")
        p.Say("knock", "叩叩，喝口水吧", "嗨～吃點東西了嗎？", "（輕輕敲）我來看看你")
        p.Say("knock_d", "叩叩，很晚了", "今天就到這裡吧")
        p.Say("newwin", "新的視窗？我去看看", "那是什麼呀")
        p.Say("newwin_d", "明天再看也可以喔")
        p.Say("hi", "嗨，我是破破。喝水、吃飯，交給我提醒"); p.Say("hi_d", "嗨…晚上了，吃飯了嗎")
        p.Say("wake", "你回來了！先喝口水"); p.Say("wake_d", "嗯…還要忙嗎？")
        p.Say("dizzy", "轉、轉圈圈了…"); p.Say("dizzy_d", "暈暈的…想睡了")
        p.Say("dizzy_ok", "好了，沒事"); p.Say("dizzy_ok_d", "好了…休息吧")
        p.Say("tickle", "哈哈哈好癢", "不要啦～", "（笑出來了）"); p.Say("tickle_d", "最後一下喔")
        p.Say("pat10", "今天第 {n} 次了，記得也喝第 {n} 口水"); p.Say("pat10_d", "第 {n} 次了，晚安")
        p.Say("levelup", "好感度 Lv{n}！拿到「{u}」，好可愛"); p.Say("levelup_d", "Lv{n}…「{u}」明天再戴")
        p.Say("missed", "好久不見，有好好吃飯嗎？"); p.Say("missed_d", "好久不見…明天見")
        p.Say("hover", "嗨～", "要喝水嗎？", "我在這裡")
        p.Say("seek", "那是什麼？"); p.Say("seek_lost", "跑掉了～"); p.Say("seek_got", "抓到了！要不要順便喝口水")
        p.Say("drag", "哇～飛起來了"); p.Say("throw", "水、水杯要灑了～")
        p.Say("shelf_in", "我回房間收拾一下"); p.Say("shelf_in_d", "回房間睡了，晚安")
        p.Say("shelf_out", "（端著水杯走出來）我來了"); p.Say("shelf_out_d", "出來了…晚上了耶")
        p.Say("ball_go", "球！我去撿～", "等我～"); p.Say("ball_go_d", "最後一顆喔")
        p.Say("ball_catch", "接到了！還你～", "嘿咻！丟回去"); p.Say("ball_catch_d", "還你，該休息了")
        p.Say("ball_end", "不玩了嗎？那喝口水吧"); p.Say("ball_end_d", "不玩了，晚安")
        p.Say("ball_far", "好遠～我慢慢走過去")
        p.Say("back", "我回來了"); p.Say("back_d", "回來了…")
        p.Say("share_end", "分享完了嗎？我回來囉")
        p.Say("welcome", "歡迎回來！先喝口水"); p.Say("welcome_d", "你回來了，吃過了嗎？")
        p.Say("rest", "{n} 分鐘了，起來走走，順便裝杯水"); p.Say("rest_d", "{n} 分鐘了，休息吧")
        p.Say("night_on", "下班時間到了，記得吃晚餐"); p.Say("night_off", "早安！先喝一杯溫水吧 ☀")
        p.Say("sleep", "我先睡一下…"); p.Say("sleep_d", "晚安…zZ")
        p.Say("jump", "嘿！"); p.Say("nojump", "附近沒地方跳，沒關係")
        p.Say("errors", "有 {n} 個錯誤，先喝口水再慢慢看"); p.Say("errors_d", "{n} 個錯誤…明天再看吧")
        p.Say("errors_ok", "錯誤都不見了！來，喝口水慶祝"); p.Say("errors_ok_d", "修好了，可以休息了")
        p.Say("typing", "打好快，手腕要休息喔", "好認真～", "我幫你倒杯水"); p.Say("typing_d", "這麼晚還在打字，辛苦了")
        p.Say("done", "{who} 做好了！吃點東西犒賞自己"); p.Say("done_d", "{who} 做好了，收工吧")
        p.Say("wait", "{who} 在等你喔"); p.Say("wait_d", "{who} 在等你，回完就休息")
        p.Say("ask", "{who} 有問題想問你"); p.Say("ask_d", "{who} 在問你，回完就下班")
        p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，要按允許嗎？"); p.Say("stuck_tool_d", "{who} 停了 {n} 分鐘，按一下就好")
        p.Say("stuck", "{who} 好像卡住了，{n} 分鐘沒動"); p.Say("stuck_d", "{who} 卡住 {n} 分鐘了，看一眼就好")
        p.Say("unstuck", "{who} 又動了！"); p.Say("unstuck_d", "{who} 動了～")
        p.Say("tag", "上版成功！晚餐加個菜 🎉"); p.Say("tag_dev", "測試機好了，先喝口水"); p.Say("tag_prod", "正式機上線了！辛苦了 🎉"); p.Say("tag_d", "上版成功，快去休息")
        p.Say("late23", "很晚了，喝杯溫水就去睡 🌙"); p.Say("late12", "午餐時間到了！先去吃飯"); p.Say("late15", "三點了，喝水、吃點點心")
        p.Say("late_d", "已經下班囉"); p.Say("late_dd", "這麼晚了，去睡吧")
        p.Say("g_late", "這麼晚還在？吃宵夜了嗎"); p.Say("g_morning", "早安！早餐吃了嗎 ☀"); p.Say("g_noon", "午安，吃飯了嗎？")
        p.Say("g_evening", "晚上了，晚餐吃什麼？"); p.Say("g_day", "破破來了，今天也照顧好自己"); p.Say("g_d", "下班時間了，你怎麼還在")
        p.Say("app_browser", "在逛什麼？看到好吃的嗎"); p.Say("app_code", "寫程式呀，手邊放杯水"); p.Say("app_excel", "好多格子，眼睛要休息"); p.Say("app_ppt", "做簡報～辛苦了")
        p.Say("app_word", "在寫報告，慢慢來"); p.Say("app_chat", "有人找你，回完喝口水"); p.Say("app_files", "在找檔案嗎？"); p.Say("app_other", "這是什麼呀？")
        p.Say("app_code_d", "還在寫…明天再寫好不好"); p.Say("app_chat_d", "明天再回也可以"); p.Say("app_office_d", "這份明天再做"); p.Say("app_other_d", "下班時間到了")
        p.Say("s_birthday", "生日快樂！今天要吃好吃的 🎂", "生日快樂～我幫你點了蠟燭")
        p.Say("s_cny", "新年快樂！年夜飯要吃飽 🧧"); p.Say("s_xmas", "聖誕快樂！熱可可來了 🎄"); p.Say("s_newyear", "新年快樂，今年也要好好吃飯 ✨")
        p.Say("s_halloween", "萬聖節快樂！糖果分你一顆 🎃"); p.Say("s_friday", "星期五了，週末好好吃一頓")
        p.Say("morning", "破破，到！🥛", "到～早餐吃了嗎")
        p.Say("goodnight", "晚安，蓋好被子喔 🌙"); p.Say("nag", "下班了，回家吃飯吧", "今天到這裡，休息囉")
        p.Say("react", "咦？", "嚇了一跳", "怎麼了？")
        p.Say("o_sig1", "來，喝口水 💧", "水杯給你，慢慢喝", "喝水時間到囉 💧")
        p.Say("o_sig2", "我也來工作一下～（打筆電）💻", "一起專心，做完一起吃點心", "（噠噠噠）破破也在努力喔")
        p.Say("o_water", "坐好久了，喝口水吧 💧", "破破送水來了～喝一點點也好 💧", "嘴巴乾乾的嗎？喝口水 💧")
        p.Say("o_goal", "進了！🏀 好厲害"); p.Say("o_cheer", "好球～"); p.Say("o_miss", "沒進～沒關係")
        p.Say("lunch_start", "午餐時間！破破端飯來了 🍚🔔"); p.Say("lunch_nap", "吃飽了…睡一下下"); p.Say("lunch_end", "下午了，喝口水再開始")
        p.Say("lunch_eat", "慢慢吃，多嚼幾下", "（端來一碗湯）", "吃飽飽～")
        p.Say("sc_tea", "我泡了熱茶，小心燙 🍵"); p.Say("sc_tea_lead", "三點了，喝茶吃點心 🍵"); p.Say("sc_tea_end", "吃飽喝足，繼續加油～")
        p.Say("sc_lunch", "開動！要吃飽喔"); p.Say("sc_photo", "拍好了嗎？大家都很可愛"); p.Say("sc_roll", "破破，到！🥛"); p.Say("sc_bye", "回家記得吃晚餐，明天見")
        p.Flavors("CI 開始跑了，先喝口水：", "CI 過了！吃塊點心慶祝", "CI 沒過，別急，喝口水再看：", "跑完了：", "沒成功，休息一下再試：", "等一下要開會，先喝口水：", "開會了！水杯帶著去", "有新的 Jira：", "今天的日誌好了：",
                  "⏰ 破破提醒你：", "電腦好燙，你也要補充水分：", "記憶體快滿了：", "硬碟快滿了：", "網路斷了，剛好喝口水", "網路回來了！", "連不到公司網路（VPN 斷了？）", "下載好了：")
        p.Tickets("🎫 {n} 還有 {h}開賣，先登入、綁好付款喔", "🎫 {n} 再 30 分鐘，先喝口水", "🎫 {n} 剩 10 分鐘！放輕鬆", "🎫 準備…", "🎫 開搶！！加油！")
        p.Shared()
        return p
    }

    // ---------------- 綿綿：提醒休息、放鬆、調整心情。軟軟的，慢慢來 ----------------
    static func Mian() -> Pal
    {
        let p = OrigBase("mian", "綿綿")
        p.Move = "shuffle"; p.NightStyle = "sleepy"; p.NightBubble = 2
        p.Accent = C(0x8E78C0); p.Panel = C(0xEEE6F8)
        p.Speed = 28
        p.Say("talk", "深呼吸～吸氣…吐氣…", "肩膀放鬆，下巴放鬆", "不用每件事都做到完美", "累了就休息，不是偷懶喔", "眼睛看看遠方，讓它休息一下", "你已經做得很好了", "心情不好的時候，可以跟我說", "慢慢來，我們不趕")
        p.Say("talk_d", "晚上了，讓今天輕輕地結束吧", "把煩惱放在這裡，明天再拿", "早點睡，夢裡會軟軟的")
        p.Say("save", "存好了，可以放心", "存起來了～鬆一口氣", "好，安心了")
        p.Say("save_d", "存好了，該休息了", "存了，晚安")
        p.Say("pats", "（軟軟地陷下去）", "好舒服～", "被摸了，心情變好了", "再摸一下下", "你也放鬆一點喔", "嗯～")
        p.Say("pats_d", "晚安摸摸", "嗯…好想睡")
        p.Say("pats_hi", "跟你在一起，好放鬆", "你是我最安心的地方", "謝謝你陪我發呆")
        p.Say("hugs", "抱抱～軟軟的", "給你一個棉花糖抱抱", "（整個抱住）放鬆～")
        p.Say("hugs_d", "晚安抱抱", "抱完就去睡")
        p.Say("knock", "叩叩，休息一下好嗎", "嗨～深呼吸一下", "（輕輕地）我在這裡")
        p.Say("knock_d", "叩叩，很晚了", "去睡吧，我也要睡了")
        p.Say("newwin", "新的視窗…慢慢看就好", "那是什麼呀")
        p.Say("newwin_d", "明天再看吧")
        p.Say("hi", "嗨，我是綿綿。累了就來找我"); p.Say("hi_d", "嗨…晚上了，放鬆一下")
        p.Say("wake", "嗯…你回來了，休息得好嗎"); p.Say("wake_d", "嗯…還不睡嗎")
        p.Say("dizzy", "轉、轉圈圈…軟掉了…"); p.Say("dizzy_d", "暈…想睡了")
        p.Say("dizzy_ok", "好了，深呼吸"); p.Say("dizzy_ok_d", "好了…睡吧")
        p.Say("tickle", "呼呼，好癢", "不要啦～會軟掉", "（笑到滾一圈）"); p.Say("tickle_d", "最後一下喔")
        p.Say("pat10", "今天第 {n} 次了，你也放鬆了嗎"); p.Say("pat10_d", "第 {n} 次了，晚安")
        p.Say("levelup", "好感度 Lv{n}！拿到「{u}」，軟軟的好喜歡"); p.Say("levelup_d", "Lv{n}…「{u}」明天再戴")
        p.Say("missed", "好久不見，最近有好好休息嗎"); p.Say("missed_d", "好久不見…明天見")
        p.Say("hover", "嗨～", "要休息一下嗎？", "深呼吸～")
        p.Say("seek", "那是什麼…"); p.Say("seek_lost", "跑掉了，沒關係"); p.Say("seek_got", "抓到了～抱著好軟")
        p.Say("drag", "哇～飄起來了"); p.Say("throw", "軟、軟著陸～")
        p.Say("shelf_in", "我回房間放空一下"); p.Say("shelf_in_d", "回房間睡了，晚安")
        p.Say("shelf_out", "（慢慢飄出來）我來了"); p.Say("shelf_out_d", "出來了…晚上了耶")
        p.Say("ball_go", "球…我慢慢去", "等我一下"); p.Say("ball_go_d", "最後一顆喔")
        p.Say("ball_catch", "接到了～還你", "嘿～丟回去"); p.Say("ball_catch_d", "還你，該睡了")
        p.Say("ball_end", "不玩了嗎？那我們發呆一下"); p.Say("ball_end_d", "不玩了，晚安")
        p.Say("ball_far", "好遠…慢慢走")
        p.Say("back", "我回來了"); p.Say("back_d", "回來了…")
        p.Say("share_end", "分享完了嗎？我回來囉")
        p.Say("welcome", "歡迎回來，休息得好嗎？"); p.Say("welcome_d", "你回來了，今天還要忙嗎？")
        p.Say("rest", "{n} 分鐘了，休息一下吧～我蓋好毯子陪你", "{n} 分鐘了，眼睛閉起來休息一下下"); p.Say("rest_d", "{n} 分鐘了，今天就到這裡吧")
        p.Say("night_on", "下班時間到了，讓自己慢下來"); p.Say("night_off", "早安～今天也慢慢來 ☀")
        p.Say("sleep", "我先睡一下…"); p.Say("sleep_d", "晚安…zZ")
        p.Say("jump", "嘿～"); p.Say("nojump", "不跳了，慢慢走就好")
        p.Say("errors", "有 {n} 個錯誤，先深呼吸，不急"); p.Say("errors_d", "{n} 個錯誤…明天再看吧")
        p.Say("errors_ok", "錯誤都不見了，鬆一口氣～"); p.Say("errors_ok_d", "修好了，好好休息")
        p.Say("typing", "打好快…手指也要休息喔", "好認真～", "放鬆肩膀再打"); p.Say("typing_d", "這麼晚還在打字，辛苦了")
        p.Say("done", "{who} 做好了，喘口氣吧"); p.Say("done_d", "{who} 做好了，收工吧")
        p.Say("wait", "{who} 在等你喔"); p.Say("wait_d", "{who} 在等你，回完就休息")
        p.Say("ask", "{who} 有問題想問你"); p.Say("ask_d", "{who} 在問你，回完就下班")
        p.Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，要按允許嗎？"); p.Say("stuck_tool_d", "{who} 停了 {n} 分鐘，按一下就好")
        p.Say("stuck", "{who} 好像卡住了，{n} 分鐘沒動"); p.Say("stuck_d", "{who} 卡住 {n} 分鐘了，看一眼就好")
        p.Say("unstuck", "{who} 又動了～"); p.Say("unstuck_d", "{who} 動了～")
        p.Say("tag", "上版成功！可以放鬆一下了 🎉"); p.Say("tag_dev", "測試機好了，深呼吸"); p.Say("tag_prod", "正式機上線了！辛苦了，抱抱 🎉"); p.Say("tag_d", "上版成功，快去休息")
        p.Say("late23", "很晚了，關燈睡覺吧 🌙"); p.Say("late12", "午餐時間到了，吃完瞇一下"); p.Say("late15", "三點了，起來伸個懶腰")
        p.Say("late_d", "已經下班囉"); p.Say("late_dd", "這麼晚了，去睡吧")
        p.Say("g_late", "這麼晚還在？別太累了"); p.Say("g_morning", "早安～慢慢醒來就好 ☀"); p.Say("g_noon", "午安，吃完可以瞇一下")
        p.Say("g_evening", "晚上了，今天辛苦了"); p.Say("g_day", "綿綿來了，今天也放輕鬆"); p.Say("g_d", "下班時間了，你怎麼還在")
        p.Say("app_browser", "在逛什麼？看點可愛的東西也好"); p.Say("app_code", "寫程式呀，記得放鬆肩膀"); p.Say("app_excel", "好多格子，眼睛休息一下"); p.Say("app_ppt", "做簡報～不要太緊張")
        p.Say("app_word", "在寫報告，慢慢寫"); p.Say("app_chat", "有人找你，慢慢回就好"); p.Say("app_files", "在找檔案嗎？"); p.Say("app_other", "這是什麼呀？")
        p.Say("app_code_d", "還在寫…明天再寫好不好"); p.Say("app_chat_d", "明天再回也可以"); p.Say("app_office_d", "這份明天再做"); p.Say("app_other_d", "下班時間到了")
        p.Say("s_birthday", "生日快樂！今天什麼都不用趕 🎂", "生日快樂～送你一個軟軟的抱抱")
        p.Say("s_cny", "新年快樂！好好放個假 🧧"); p.Say("s_xmas", "聖誕快樂！窩在毯子裡最幸福 🎄"); p.Say("s_newyear", "新年快樂，今年也對自己溫柔一點 ✨")
        p.Say("s_halloween", "萬聖節快樂！我扮成一朵雲 🎃"); p.Say("s_friday", "星期五了，週末好好放鬆")
        p.Say("morning", "綿綿，到～☁", "到～慢慢醒來")
        p.Say("goodnight", "晚安，做個軟軟的夢 🌙"); p.Say("nag", "下班了，讓自己休息吧", "今天到這裡，慢慢回家")
        p.Say("react", "咦？", "嚇了一跳", "怎麼了？")
        p.Say("o_sig1", "蓋好毯子，抱著月亮枕…休息一下下 🌙", "閉上眼睛，深呼吸…吸…吐…", "（窩在毯子裡）好舒服～")
        p.Say("o_sig2", "捧著熱可可，放空一下下 ☕", "暖暖的…什麼都不想", "（呼～）熱可可好香")
        p.Say("o_goal", "進了～🏀"); p.Say("o_cheer", "好球～"); p.Say("o_miss", "沒進～沒關係")
        p.Say("lunch_start", "午餐時間～吃完可以瞇一下 🔔"); p.Say("lunch_nap", "吃飽了…一起午睡"); p.Say("lunch_end", "下午了，慢慢醒來")
        p.Say("lunch_eat", "慢慢吃～", "（小口小口地吃）", "好好吃，好幸福")
        p.Say("sc_tea", "茶好香，先聞一下 🍵"); p.Say("sc_tea_lead", "三點了，大家一起伸懶腰喝茶 🍵"); p.Say("sc_tea_end", "休息好了，慢慢回去吧～")
        p.Say("sc_lunch", "開動～慢慢吃"); p.Say("sc_photo", "拍好了嗎？笑得好放鬆"); p.Say("sc_roll", "綿綿，到～☁"); p.Say("sc_bye", "今天辛苦了，好好休息")
        p.Flavors("CI 開始跑了，先放鬆等它：", "CI 過了！鬆一口氣～", "CI 沒過，深呼吸，再看看：", "跑完了：", "沒成功，休息一下再試：", "等一下要開會，先深呼吸：", "開會了！放輕鬆去", "有新的 Jira：", "今天的日誌好了：",
                  "⏰ 綿綿提醒你：", "電腦好燙，讓它也休息一下：", "記憶體快滿了：", "硬碟快滿了：", "網路斷了，剛好休息一下", "網路回來了～", "連不到公司網路（VPN 斷了？）", "下載好了：")
        p.Tickets("🎫 {n} 還有 {h}開賣，先登入、綁好付款喔", "🎫 {n} 再 30 分鐘，先放輕鬆", "🎫 {n} 剩 10 分鐘！深呼吸", "🎫 準備…吸氣…", "🎫 開搶！！加油～")
        p.Shared()
        return p
    }
}

// ================= 一隻窩伴小世界：跟續命小隊不一樣的地方（51_original.swift 的 Orig* 會先問這裡）=================
extension Pet {
    // 連點三下
    func WbCombo() {
        if Is("fanfan") { OPose("surprised", 1.4) }
        else { OPose("happy", 1.6) }
    }

    // 招牌動作：sig1（看書／喝水／蓋毯子）、sig2（撒花／打筆電／熱可可）
    func WbSignature() {
        let one = rnd.NextDouble() < 0.6
        OrigDo(one ? "s1" : "s2", R(2.6, 4))
        Say(L(one ? "o_sig1" : "o_sig2"), 2)
    }

    // 閒晃時講一句：翻翻坐著講、破破開心地講、綿綿捧熱可可放空（sig2）
    func WbChat() {
        if Is("mian") { OrigDo("s2", 2.8) }
        else { OPose(Is("bobo") ? "happy" : "sit", 2.4) }
        Say(L("talk"), 2.4)
    }

    // 錯誤變多：翻翻皺眉（我們一個一個來），破破、綿綿嚇一跳
    func WbReact(_ why: String) {
        if Is("fanfan") { OPose("pout", 2.2) }
        else { OPose("surprised", 2.0) }
    }

    // 選單、測試用的動作
    func WbAct(_ a: String) -> Bool {
        switch a {
        case "wb_sig1": if Grounded() { OrigDo("s1", 3.2); Say(L("o_sig1"), 2) }; return true
        case "wb_sig2": if Grounded() { OrigDo("s2", 3.2); Say(L("o_sig2"), 2) }; return true
        case "wb_water": if Is("bobo") { WbWater() }; return true
        case "wb_focus": w.WbFocus(); return true
        default: return false
        }
    }

    // 破破：喝水提醒（World.WbTick 定時叫）
    func WbWater() {
        WakeIfSleep()
        if Grounded() { OrigDo("s1", 3.4) }
        Say(L("o_water"), 4)
        App.Log("woban: water reminder")
    }

    // 狀態 → 哪一張圖（nil＝照續命小隊那套）：番茄鐘專注中，翻翻在旁邊專心看書、破破打筆電陪你一起工作
    func WbFrame() -> String? {
        if w.focusOn && (state == "idle" || state == "sleep") && (Is("fanfan") || Is("bobo")) { return Is("fanfan") ? "sig1" : "sig2" }
        return nil
    }

    // 綿綿：用太久電腦的休息提醒（蓋毯子抱月亮枕）
    func WbRestNow(_ restMin: Double) {
        WakeIfSleep()
        if Grounded() { OrigDo("s1", 6) }
        Say(L("rest", "n", restMin.ToString()), 8)
    }

    // 櫃子裡：翻翻偶爾翻書、破破偶爾喝水、綿綿偶爾瞇一下
    func WbShelfFrame(_ tt: Double) -> String? {
        if Is("fanfan") && tt.truncatingRemainder(dividingBy: 11) < 2.5 { return "sig1" }
        if Is("bobo") && tt.truncatingRemainder(dividingBy: 13) < 2 { return "sig1" }
        if Is("mian") && tt.truncatingRemainder(dividingBy: 10) < 3 { return "sleep" }
        return nil
    }
}

// ================= World：喝水提醒、休息由綿綿講、專注由翻翻陪；選單；兩兩串場 =================
//@@IN World
    var wbWater: Double = 0
//@@END

extension World {
    static let WbWaterMin: Double = 45   // 破破：連續用電腦幾分鐘提醒喝一次水（離開電腦就重算）

    func WbTick(_ dt: Double) {
        if sysIdle { wbWater = 0; return }
        wbWater += dt
        if wbWater < World.WbWaterMin * 60 { return }
        if scene != nil || Hidden || focusOn || quietOn || !Feat("wb_water") { return }   // 忙的時候先不吵：等一下再講
        guard let b = Get("bobo"), b.Out, b.Grounded(), !b.InScene else { return }
        wbWater = 0
        b.WbWater()
    }

    // 用太久電腦的休息提醒：窩伴小世界由綿綿講（她在外面的話；蓋毯子抱月亮枕），其他櫃照舊
    func RestPet() -> Pet {
        if WobanLineup, let m = Get("mian"), m.Out { return m }
        return Lead()
    }
    func WbRest(_ p: Pet, _ restMin: Double) {
        if WobanLineup && p.P.Id == "mian" { p.WbRestNow(restMin) }
        else { p.Rest(restMin) }
    }

    // 番茄鐘：窩伴小世界由翻翻開場、收尾（她在外面的話）；做完一段，翻翻撒花慶祝小進步
    func FocusPet() -> Pet {
        if WobanLineup, let f = Get("fanfan"), f.Out { return f }
        return Lead()
    }
    func WbFocus() { if !focusOn { StartFocus(focusMin) } }
    func WbFocusDone() {
        if !WobanLineup { return }
        guard let f = Get("fanfan"), f.Out, f.Grounded() else { return }
        f.OrigDo("s2", 3.2)
        f.Burst(6)
    }

    func WbMenuItems(_ p: Pet) -> [[String]] {
        switch p.P.Id {
        case "fanfan":
            return [["抱抱 ♥", "hug"], ["打招呼", "hi"], ["敲敲螢幕", "knock"], ["翻書陪你 📖", "wb_sig1"],
                    ["慶祝小進步 ✨", "wb_sig2"], ["陪我專注 " + String(focusMin) + " 分鐘 🍅", "wb_focus"], ["睡覺", "sleep"], ["丟球給他 ⚾", "ball"]]
        case "bobo":
            return [["抱抱 ♥", "hug"], ["打招呼", "hi"], ["敲敲螢幕", "knock"], ["提醒我喝水 💧", "wb_water"],
                    ["陪你一起工作 💻", "wb_sig2"], ["跳到別的視窗上", "jump"], ["睡覺", "sleep"], ["丟球給他 ⚾", "ball"]]
        default:
            return [["抱抱 ♥", "hug"], ["打招呼", "hi"], ["敲敲螢幕", "knock"], ["蓋毯子休息一下 🌙", "wb_sig1"],
                    ["捧熱可可放空 ☕", "wb_sig2"], ["睡覺", "sleep"], ["丟球給她 ⚾", "ball"]]
        }
    }

    // ---------- 兩兩串場 ----------
    func WbPairScene(_ key: String) {
        let f: Pet? = Get("fanfan"), b: Pet? = Get("bobo"), m: Pet? = Get("mian")
        switch key {
        case "bobo-fanfan": if let f = f, let b = b { SceneStudySnack(f, b) }
        case "fanfan-mian": if let f = f, let m = m { SceneBookmark(f, m) }
        case "bobo-mian": if let b = b, let m = m { SceneTeaNap(b, m) }
        default: break
        }
    }

    // 翻翻 × 破破：讀書補給（卡關時先喝口水，想通了一起慶祝）
    func SceneStudySnack(_ f: Pet, _ b: Pet) {
        Begin(f, b)
        At(0) { [self] in Face(f, b); f.OrigDo("s1", 30); b.ScenePose("idle", 30); f.Say("這一題好難喔…", 2) }
        At(2.4) { b.OPose("surprised", 1.4); b.Say("卡住了嗎？先喝口水 💧", 2) }
        At(4.6) { b.OrigDo("s1", 30); f.OPose("happy", 30); f.Say("謝謝破破…（咕嚕）", 1.8) }
        At(7.0) { f.OPose("surprised", 1.4); f.Say("啊！我想通了！", 1.8); f.Mark(0) }
        At(9.0) { f.OrigDo("s2", 30); f.Say("小進步，撒花 ✨", 2); f.Burst(6) }
        At(11.4) { b.OPose("happy", 30); b.Say("小進步也要慶祝～", 2) }
        At(14.0) { [self] in Face(f, b); f.ScenePose("hug", 2.4); b.ScenePose("hug", 2.4) }
        At(16.6) { }
    }

    // 翻翻 × 綿綿：書籤（讀很久了，綿綿拉翻翻一起伸懶腰）
    func SceneBookmark(_ f: Pet, _ m: Pet) {
        Begin(f, m)
        At(0) { [self] in Face(f, m); f.OrigDo("s1", 30); m.ScenePose("idle", 30); f.Say("再一頁…再一頁就好…", 2) }
        At(2.6) { m.OPose("sit", 30); m.Say("翻翻，已經讀很久囉", 2) }
        At(4.8) { m.OrigDo("s1", 30); m.Say("要不要一起蓋毯子瞇一下～", 1.8) }
        At(7.0) { f.OPose("pout", 30); f.Say("可是還有一點點…", 1.8) }
        At(9.2) { m.OPose("happy", 30); m.Say("書不會跑掉的，書籤夾著就好", 2.2) }
        At(11.8) { f.OPose("sit", 30); f.Say("…好，休息五分鐘", 1.8); m.Mark(2) }
        At(14.0) { [self] in Face(f, m); f.ScenePose("hug", 2.4); m.ScenePose("hug", 2.4); m.Say("你今天很努力了", 1.8) }
        At(16.6) { }
    }

    // 破破 × 綿綿：破破工作到一半，綿綿端熱可可來，一起放空
    func SceneTeaNap(_ b: Pet, _ m: Pet) {
        Begin(b, m)
        At(0) { [self] in Face(b, m); b.OrigDo("s2", 30); m.ScenePose("idle", 30); b.Say("（噠噠噠）還有一點點就做完了…", 2) }
        At(2.4) { m.OrigDo("s2", 30); m.Say("破破，先喝口熱可可吧 ☕", 1.8) }
        At(4.6) { b.OPose("happy", 30); b.Say("好香喔…那休息一下", 1.6) }
        At(6.6) { b.OrigDo("s1", 30); m.Say("一起放空一下下～", 2) }
        At(9.0) { b.OPose("sleep", 30); b.Say("我也要…zZ", 1.6); b.Mark(3) }
        At(11.6) { m.OPose("happy", 2.4); b.OPose("happy", 2.4); m.Say("好幸福的下午", 2) }
        At(14.0) { [self] in Face(b, m); b.ScenePose("hug", 2.4); m.ScenePose("hug", 2.4) }
        At(16.6) { }
    }
}
