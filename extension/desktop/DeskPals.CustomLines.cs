// Desk Pals：自己做的公仔（上傳圖片）的六種個性台詞：活潑、酷酷、害羞、搞笑、喵系、汪系。
// desk-pals.ps1 會把 DeskPals.cs 和 DeskPals.*.cs 接在一起編譯；這個檔的 using 放在 namespace 裡面，接起來才合法。
// 每種個性一個方法（CuLively…），各自完整：小波（Po）有的台詞 key 全部都有，另外加 x_ 開頭的（串場、午餐、通知開場白、搶票、分享文案、貓狗動作）。
// 名字直接接字串（me），不用 {me}；{n}{who}{tool}{u} 跟內建角色一樣，x_pair_* 可以用 {o}（另一隻的名字），x_ticket* 用 {t}{h}。
namespace DeskPals
{
    using System;
    using System.Collections.Generic;

    partial class Pal
    {
        public static readonly string[] Personas = { "lively", "cool", "shy", "funny", "cat", "dog" };

        public static string PersonaName(string id)
        {
            switch (id)
            {
                case "cool": return "酷酷";
                case "shy": return "害羞";
                case "funny": return "搞笑";
                case "cat": return "喵系";
                case "dog": return "汪系";
            }
            return "活潑";
        }

        public static string PersonaDesc(string id)
        {
            switch (id)
            {
                case "cool": return "話很少，但很可靠";
                case "shy": return "小小聲，默默陪你";
                case "funny": return "冷笑話停不下來";
                case "cat": return "高冷，但會偷偷黏你";
                case "dog": return "超黏人，看到你就搖尾巴";
            }
            return "精神超好、愛撒嬌";
        }

        public static string PersonaEmoji(string id)
        {
            switch (id)
            {
                case "cool": return "😎";
                case "shy": return "🙈";
                case "funny": return "🤡";
                case "cat": return "🐱";
                case "dog": return "🐶";
            }
            return "🧸";
        }

        void CuLines(string persona, string me)
        {
            switch (persona)
            {
                case "cool": CuCool(me); break;
                case "shy": CuShy(me); break;
                case "funny": CuFunny(me); break;
                case "cat": CuCat(me); break;
                case "dog": CuDog(me); break;
                default: CuLively(me); break;
            }
        }

        // ---------------- 活潑：精神超好、愛撒嬌 ----------------
        void CuLively(string me)
        {
            Say("talk", "今天也要元氣滿滿！", "嘿嘿，我在這裡喔～", "要不要喝口可樂？🥤", "螢幕好大，可以跑好遠！", me + "陪你一起努力！", "你剛剛是不是在偷笑？", "伸個懶腰～嗯～！");
            Say("talk_d", "下班時間到啦！快收工～", "還在忙？明天的你會接手的！", "我電量剩一格了…你也是吧？", "關機關機～回家吃好料！", "今天辛苦了，剩下的明天再說！");
            Say("save", "存好了！讚啦 👍", "存檔成功～安心！", "收好收好！", "叮！存起來了");
            Say("save_d", "存好了！那就可以下班啦", "存檔完成～快關機！", "存好了，走走走回家！");
            Say("pats", "嘿嘿，好舒服～", "再摸一下嘛！", "你今天超棒的！", "被摸摸就充飽電了！", "我最喜歡你的手了 ♥", "慢慢來，我陪你", "你辛苦了，換我摸摸你！", "嘻嘻，好癢又好開心");
            Say("pats_d", "摸完就回家喔！", "我的電量分你，快下班！", "嘿嘿…明天再繼續摸", "今天好累吧？回家休息～");
            Say("pats_hi", "能遇到你真的好幸運！", "我們是最強搭檔！", "最最最喜歡你了 ♥", "每天都要這樣陪著你！");
            Say("hugs", "抱抱！充電中～", "大大的抱抱！♥", "(つ´ω`)つ 抱緊緊", "抱一下，煩惱飛走！");
            Say("hugs_d", "晚安抱抱！然後回家", "抱完就要下班喔！", "抱抱～路上小心 ♥");
            Say("knock", "叩叩！看我看我！👀", "嗨～螢幕外面的你！", "我可以出去玩嗎？", "你在發呆嗎？叩叩！");
            Say("knock_d", "叩叩！下班時間到了啦！", "我看到你還在加班喔…", "叩叩叩！快回家！");
            Say("newwin", "新視窗！我去看看！", "哇，這是什麼？", "衝啊～去探險！");
            Say("newwin_d", "又開新的？明天再看啦", "不准再開了，下班！");
            Say("hi", "嗨！我是" + me + "！👋"); Say("hi_d", "嗨～下班了嗎？");
            Say("wake", "嗯…是你！我醒了！"); Say("wake_d", "嗯…我在充電…你也去睡嘛");
            Say("dizzy", "轉圈圈～頭好暈 @@"); Say("dizzy_d", "暈暈的…該睡了…");
            Say("dizzy_ok", "好了！我又活過來了！"); Say("dizzy_ok_d", "好了…那我們下班吧");
            Say("tickle", "哈哈哈好癢！", "不要啦～哈哈哈！", "再一次！不對，不要了！哈哈"); Say("tickle_d", "哈…好啦最後一次喔");
            Say("pat10", "今天第 {n} 次摸摸了！好開心 ♥"); Say("pat10_d", "第 {n} 次了～摸完就回家喔");
            Say("levelup", me + "好感度 Lv{n}！拿到「{u}」了 ♥"); Say("levelup_d", "Lv{n}！「{u}」明天戴給你看！");
            Say("missed", "你好幾天沒摸我了…🥺"); Say("missed_d", "好久沒摸了…明天要記得喔");
            Say("hover", "你在摸我嗎？嘿嘿～");
            Say("seek", "咦？那是什麼！"); Say("seek_lost", "啊，跑掉了…"); Say("seek_got", "抓到滑鼠了！耶！");
            Say("drag", "哇～飛起來了！"); Say("throw", "咻～～～！");
            Say("shelf_in", "我回家囉，掰掰 👋"); Say("shelf_in_d", "我先回家充電，你也是喔");
            Say("shelf_out", "出來玩囉！耶～"); Say("shelf_out_d", "咦？天黑了你怎麼還在？");
            Say("ball_go", "球！我來了！", "等我等我～", "這球我接定了！"); Say("ball_go_d", "最後一球喔！");
            Say("ball_catch", "接到了！傳回去～", "好球！再來！", "我是不是很厲害？"); Say("ball_catch_d", "接到了，然後下班！");
            Say("ball_end", "不玩了嗎？下次再玩！⚾"); Say("ball_end_d", "不玩了～那就回家吧");
            Say("ball_far", "球跑好遠喔～");
            Say("back", "我回來啦！"); Say("back_d", "回來了…該下班囉");
            Say("share_end", "分享結束～我回來了！");
            Say("welcome", "你回來了！我等你好久！"); Say("welcome_d", "回來了？是要來關機的吧！");
            Say("rest", "已經 {n} 分鐘了！起來喝口可樂、伸展一下！🥤"); Say("rest_d", "{n} 分鐘了…喝完可樂就下班吧 🥤");
            Say("night_on", "下班時間到了！"); Say("night_off", "早安！元氣補滿了 ☀");
            Say("sleep", "晚安～zZ"); Say("sleep_d", "晚安…你也快去睡");
            Say("jump", "跳～！"); Say("nojump", "附近沒有可以跳的地方耶");
            Say("errors", "哇！有 {n} 個錯誤！一起修！"); Say("errors_d", "{n} 個錯誤…明天再修啦");
            Say("errors_ok", "錯誤清光光！抱一個！"); Say("errors_ok_d", "修好了！可以下班啦！");
            Say("typing", "打字好快！加油加油！", "手指在飛耶！🔥", "衝衝衝！我幫你打氣！"); Say("typing_d", "打這麼快，是想快點下班吧？");
            Say("done", "{who} 做完了！快來看 👀"); Say("done_d", "{who} 做完了～你也該收工啦");
            Say("wait", "{who} 在等你回答喔～👋"); Say("wait_d", "{who} 在等你，回完就下班！");
            Say("ask", "{who} 有問題要問你！🙋"); Say("ask_d", "{who} 在問你問題，回完就回家");
            Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，要你按允許嗎？"); Say("stuck_tool_d", "{who} 停了 {n} 分鐘，去按一下就下班");
            Say("stuck", "{who} 好像卡住了…{n} 分鐘沒動，去看看？"); Say("stuck_d", "{who} 卡住 {n} 分鐘了，看完就回家");
            Say("unstuck", "{who} 又動起來了！👍"); Say("unstuck_d", "{who} 動了！");
            Say("tag", "上版成功！🎆"); Say("tag_dev", "測試機上好了！🎆"); Say("tag_prod", "上正式機了！辛苦了 🎉"); Say("tag_d", "上版成功！那現在可以下班了吧？");
            Say("late23", "好晚了耶，早點休息好不好 🌙"); Say("late12", "午餐吃了沒？"); Say("late15", "下午茶時間～來罐可樂吧 🥤");
            Say("late_d", "下班時間早就過了喔！"); Say("late_dd", "這麼晚了，關機睡覺！");
            Say("g_late", "這麼晚還在忙？我陪你 🌙"); Say("g_morning", "早安！今天也元氣滿滿 ☀"); Say("g_noon", "午安～吃飯了沒？");
            Say("g_evening", "晚上了，辛苦啦～"); Say("g_day", me + "出來玩囉！"); Say("g_d", "下班時間了！你怎麼還開著電腦？");
            Say("app_browser", "在逛什麼？我也要看！"); Say("app_code", "寫 code 時間！加油！"); Say("app_excel", "好多數字喔，加油！");
            Say("app_ppt", "做簡報？我幫你盯著！"); Say("app_word", "寫文件～慢慢來"); Say("app_chat", "有人找你嗎？"); Say("app_files", "在找檔案？我幫你找！");
            Say("app_other", "這是什麼？我也來看看！");
            Say("app_code_d", "還在寫？下班啦！"); Say("app_chat_d", "下班了，訊息明天再回！"); Say("app_office_d", "這份明天做也來得及！"); Say("app_other_d", "你在忙什麼？該下班了吧！");
            Say("s_birthday", "生日快樂！🎂 今天你最大！", "祝你生日快樂～許個願吧！", "今天什麼都不准煩惱 ♥");
            Say("s_cny", "新年快樂！恭喜發財 🧧", "紅包拿來～騙你的啦！");
            Say("s_xmas", "聖誕快樂！🎄", "我想要的禮物是你準時下班！");
            Say("s_newyear", "新年快樂！今年也請多指教 ✨");
            Say("s_halloween", "不給糖就搗蛋！🎃", "我今天扮成…一隻超可愛的公仔！");
            Say("s_friday", "星期五了！撐住！", "小週末～今天準時下班好不好？");
            Say("morning", "早安！" + me + "報到 ☀", "早安～今天也一起加油！");
            Say("goodnight", "晚安～我先回家了 👋", "今天辛苦了，晚安！");
            Say("nag", "下班時間到啦！", "快回家吃飯！", "電腦也要休息啦～");
            Say("react", "！", "怎麼了怎麼了？", "咦？");
            // ---- 串場、午餐、小幫手 ----
            Say("x_goal", "進球！🏀 我超準的！"); Say("x_goal_d", "進球！🏀 好，回家！");
            Say("x_cheer", "好球！", "耶～進了！"); Say("x_miss", "差一點點！再一次！");
            Say("x_photo", "耶～比個 YA！", "笑～咪咪～");
            Say("x_pair_hi", "{o}！一起玩嘛！"); Say("x_pair_ask", "{o}，你今天開心嗎？"); Say("x_pair_react", "嘿嘿，那就好！");
            Say("x_pair_ball", "接球～{o}！"); Say("x_pair_ball_end", "好好玩！再來一次！"); Say("x_pair_bye", "掰掰～等等見！");
            Say("x_lunch_start", "午餐時間！打開便當囉 🔔"); Say("x_lunch_nap", "吃飽飽…睡一下下"); Say("x_lunch_end", "回來工作囉！元氣滿滿！");
            Say("x_lunch_talk", "便當好香！", "這塊排骨分你一半！", "吃飽才有力氣！");
            Say("x_quiet_on", "噓～我安靜陪你 🤫"); Say("x_quiet_off", "安靜時間結束～可以講話了嗎？");
            Say("x_focus_end", "專注結束！休息 5 分鐘 ☕ 你超厲害！"); Say("x_wrap", "今天的我們超棒：");
            // ---- 通知開場白 ----
            Say("x_ci-run", "CI 出發囉："); Say("x_ci-ok", "CI 過了！耶！"); Say("x_ci-fail", "啊！CI 失敗了："); Say("x_cmd-ok", "指令跑完了："); Say("x_cmd-fail", "咦？指令失敗了：");
            Say("x_meeting", "等一下要開會喔："); Say("x_meeting-now", "會議開始了！快去："); Say("x_jira", "有新的 Jira！"); Say("x_worklog", "今天的工作日誌好了："); Say("x_worklog_d", "日誌好了！然後下班：");
            Say("x_remind", "⏰ 提醒你："); Say("x_pc-cpu", "電腦好燙喔："); Say("x_pc-ram", "記憶體快滿了："); Say("x_pc-disk", "硬碟快滿了：");
            Say("x_net-down", "網路斷了！"); Say("x_net-up", "網路回來了！👍"); Say("x_vpn", "連不到公司網路（VPN 斷了？）"); Say("x_download", "下載好了！");
            Say("x_ticket0", "🎫 {t} 還有 {h}開賣！先登入、綁好付款"); Say("x_ticket1", "🎫 {t} 再 30 分鐘開賣，網頁先開好！"); Say("x_ticket2", "🎫 {t} 剩 10 分鐘！好緊張～");
            Say("x_ticket3", "🎫 準備！手指放在按鈕上！"); Say("x_ticket4", "🎫 開搶！！衝衝衝！");
            Say("x_share", "我家的" + me + "住進我電腦了 ✨ #我的桌面公仔 #WoWoPals", me + "每天在我桌面上跑來跑去 ✨ #我的桌面公仔 #WoWoPals");
            Say("x_sig", "看我的招牌跳跳！"); Say("x_sit", "坐一下下～");
            // ---- 小動作 ----
            Say("x_push", "（推推）啊，掉下去了！"); Say("x_ignore", "哼，我在忙！（其實沒有）"); Say("x_comeback", "好啦好啦，我回來陪你了！");
            Say("x_loaf", "縮成一團…好舒服"); Say("x_wag", "開心到停不下來！"); Say("x_fetch_back", "撿回來了！再丟一次！"); Say("x_return", "你回來了！耶耶耶！");
        }

        // ---------------- 酷酷：話很少，但很可靠 ----------------
        void CuCool(string me)
        {
            Say("talk", "嗯。", "我在。", "可樂？🥤", "這畫面，還行。", "別急，穩著來。", me + "，待命中。", "今天沒什麼難得倒你。");
            Say("talk_d", "下班了。", "收工。", "明天再說。", "該走了。", "工作不會跑，你該走了。");
            Say("save", "存了。", "穩。👍", "存檔，完成。", "嗯，收好了。");
            Say("save_d", "存了。走吧。", "存好了。關機。");
            Say("pats", "……還行。", "嗯，不錯。", "別一直摸。…再一下。", "你今天表現不差。", "我在，放心。", "辛苦了。", "（點頭）");
            Say("pats_d", "摸完就下班。", "不是捨不得你，是你該走了。", "嗯。明天再來。");
            Say("pats_hi", "你是我認可的人。", "跟你一組，不錯。", "……我挺喜歡你的。");
            Say("hugs", "……就一下。", "抱。", "(　´_ゝ`)つ 嗯。");
            Say("hugs_d", "抱完回家。", "一下下就好。走吧。");
            Say("knock", "叩。你在看我？", "嗯，看到你了。", "出去走走。可以吧？");
            Say("knock_d", "叩叩。下班了沒？", "還在加班？不酷。");
            Say("newwin", "新的。我看看。", "嗯？", "有東西，去看。");
            Say("newwin_d", "別開了。", "明天再看。");
            Say("hi", me + "。嗨。"); Say("hi_d", "嗯。下班了沒？");
            Say("wake", "……醒了。"); Say("wake_d", "我在休息。你也是。");
            Say("dizzy", "停。頭暈。@@"); Say("dizzy_d", "……暈。睡了。");
            Say("dizzy_ok", "沒事。"); Say("dizzy_ok_d", "沒事。走吧。");
            Say("tickle", "……不准笑。", "別鬧。", "哼。…好吧，有點癢。"); Say("tickle_d", "夠了。下班。");
            Say("pat10", "今天第 {n} 次。…還不錯。"); Say("pat10_d", "第 {n} 次了。回家。");
            Say("levelup", "好感度 Lv{n}。「{u}」，收下了。"); Say("levelup_d", "Lv{n}。「{u}」。明天戴。");
            Say("missed", "幾天沒摸了。我沒在等。…真的。"); Say("missed_d", "好幾天了。哼。");
            Say("hover", "嗯？");
            Say("seek", "那是什麼。"); Say("seek_lost", "跑了。"); Say("seek_got", "抓到。");
            Say("drag", "放我下來。"); Say("throw", "……咻。");
            Say("shelf_in", "回去待著。"); Say("shelf_in_d", "我回去了。你也是。");
            Say("shelf_out", "出來透透氣。"); Say("shelf_out_d", "天黑了，你還在？");
            Say("ball_go", "球。", "我來。", "接得到。"); Say("ball_go_d", "最後一球。");
            Say("ball_catch", "接住。還你。", "好球。", "簡單。"); Say("ball_catch_d", "接到了。收工。");
            Say("ball_end", "不玩了？行。⚾"); Say("ball_end_d", "不玩了。下班。");
            Say("ball_far", "太遠了。");
            Say("back", "回來了。"); Say("back_d", "回來了。該走了。");
            Say("share_end", "分享完了。我回來了。");
            Say("welcome", "回來了。…歡迎。"); Say("welcome_d", "回來關機的吧。");
            Say("rest", "{n} 分鐘了。起來，喝口可樂，伸展一下。🥤"); Say("rest_d", "{n} 分鐘了。喝完可樂就下班。🥤");
            Say("night_on", "下班時間。"); Say("night_off", "早。☀");
            Say("sleep", "睡了。"); Say("sleep_d", "你也睡。");
            Say("jump", "跳。"); Say("nojump", "沒地方跳。");
            Say("errors", "{n} 個錯誤。冷靜。"); Say("errors_d", "{n} 個錯誤。明天修。");
            Say("errors_ok", "清空了。漂亮。"); Say("errors_ok_d", "清完了。下班。");
            Say("typing", "速度不錯。", "手感來了。", "穩，繼續。"); Say("typing_d", "打這麼快，想下班？");
            Say("done", "{who} 做完了。去看。"); Say("done_d", "{who} 做完了。你也收工。");
            Say("wait", "{who} 在等你。"); Say("wait_d", "{who} 在等你。回完就走。");
            Say("ask", "{who} 有問題問你。"); Say("ask_d", "{who} 在問。回完下班。");
            Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了。要你按允許？"); Say("stuck_tool_d", "{who} 停 {n} 分鐘了。按完就走。");
            Say("stuck", "{who} 卡住 {n} 分鐘了。去看。"); Say("stuck_d", "{who} 卡 {n} 分鐘。看完下班。");
            Say("unstuck", "{who} 動了。"); Say("unstuck_d", "{who} 動了。");
            Say("tag", "上版成功。🎆"); Say("tag_dev", "測試機，過。🎆"); Say("tag_prod", "正式機，上了。幹得好。🎉"); Say("tag_d", "上完了。下班。");
            Say("late23", "很晚了。睡。🌙"); Say("late12", "吃飯。"); Say("late15", "可樂時間。🥤");
            Say("late_d", "下班時間過了。"); Say("late_dd", "太晚了。關機。");
            Say("g_late", "這時間還在？我陪你。🌙"); Say("g_morning", "早。☀"); Say("g_noon", "午安。吃了沒。");
            Say("g_evening", "晚上了。辛苦。"); Say("g_day", me + "，上線。"); Say("g_d", "下班了。電腦還開著？");
            Say("app_browser", "在看什麼。"); Say("app_code", "寫 code。很好。"); Say("app_excel", "數字。加油。");
            Say("app_ppt", "簡報。排版我盯著。"); Say("app_word", "寫文件。慢慢來。"); Say("app_chat", "有人找你。"); Say("app_files", "找檔案？");
            Say("app_other", "這是什麼。");
            Say("app_code_d", "還寫？下班。"); Say("app_chat_d", "明天再回。"); Say("app_office_d", "明天做。"); Say("app_other_d", "該走了。");
            Say("s_birthday", "生日快樂。🎂 今天你最大。", "生日快樂。…蛋糕，我準備了。");
            Say("s_cny", "新年快樂。🧧", "紅包？我不缺。…你給的話我收。");
            Say("s_xmas", "聖誕快樂。🎄", "禮物？你準時下班就好。");
            Say("s_newyear", "新年快樂。今年也一起。✨");
            Say("s_halloween", "不給糖就搗蛋。🎃", "我不扮裝。…好啦，戴個面具。");
            Say("s_friday", "星期五。撐住。", "週末快到了。準時走。");
            Say("morning", "早。" + me + "報到。", "早。今天也穩穩的。");
            Say("goodnight", "晚安。我先回去了。", "今天辛苦了。晚安。");
            Say("nag", "下班。", "走了。", "關機。");
            Say("react", "！", "怎麼了。", "嗯？");
            // ---- 串場、午餐、小幫手 ----
            Say("x_goal", "進球。🏀 沒懸念。"); Say("x_goal_d", "進球。🏀 下班。");
            Say("x_cheer", "不錯。", "嗯，漂亮。"); Say("x_miss", "偏了。再來。");
            Say("x_photo", "（帥氣站好）", "……拍吧。");
            Say("x_pair_hi", "{o}。"); Say("x_pair_ask", "{o}，最近還好？"); Say("x_pair_react", "嗯。那就好。");
            Say("x_pair_ball", "{o}，接著。"); Say("x_pair_ball_end", "還行。下次再來。"); Say("x_pair_bye", "走了。");
            Say("x_lunch_start", "午餐。便當，開動。🔔"); Say("x_lunch_nap", "吃飽了。閉眼一下。"); Say("x_lunch_end", "回來工作。");
            Say("x_lunch_talk", "便當，不錯。", "滷蛋留到最後。", "安靜吃飯。");
            Say("x_quiet_on", "安靜。我懂。🤫"); Say("x_quiet_off", "安靜結束。");
            Say("x_focus_end", "專注結束！休息 5 分鐘 ☕ 幹得好。"); Say("x_wrap", "今天的紀錄：");
            // ---- 通知開場白 ----
            Say("x_ci-run", "CI 跑了："); Say("x_ci-ok", "CI 過了。"); Say("x_ci-fail", "CI 掛了。冷靜："); Say("x_cmd-ok", "指令跑完："); Say("x_cmd-fail", "指令失敗：");
            Say("x_meeting", "等等開會："); Say("x_meeting-now", "開會了。去："); Say("x_jira", "新的 Jira："); Say("x_worklog", "日誌好了："); Say("x_worklog_d", "日誌好了。下班：");
            Say("x_remind", "⏰ 提醒："); Say("x_pc-cpu", "電腦很燙："); Say("x_pc-ram", "記憶體快滿："); Say("x_pc-disk", "硬碟快滿：");
            Say("x_net-down", "網路斷了。"); Say("x_net-up", "網路回來了。👍"); Say("x_vpn", "連不到公司網路（VPN 斷了？）"); Say("x_download", "下載好了：");
            Say("x_ticket0", "🎫 {t} 還有 {h}開賣。先登入、綁好付款"); Say("x_ticket1", "🎫 {t} 30 分鐘後開賣。網頁先開"); Say("x_ticket2", "🎫 {t} 剩 10 分鐘。專心");
            Say("x_ticket3", "🎫 準備。手指就位"); Say("x_ticket4", "🎫 開搶。上！");
            Say("x_share", me + "住進我的桌面了。很酷。😎 #我的桌面公仔 #WoWoPals", "我的桌面多了一位" + me + "。 #我的桌面公仔 #WoWoPals");
            Say("x_sig", "看好了。"); Say("x_sit", "坐一下。");
            // ---- 小動作 ----
            Say("x_push", "（推）……掉了。"); Say("x_ignore", "（轉頭）現在不想理人。"); Say("x_comeback", "……好吧，陪你。");
            Say("x_loaf", "休息。別吵。"); Say("x_wag", "……我才沒有很開心。"); Say("x_fetch_back", "球。還你。"); Say("x_return", "回來了。…等你很久。");
        }

        // ---------------- 害羞：小小聲，默默陪你 ----------------
        void CuShy(string me)
        {
            Say("talk", "那個…今天也加油喔", "（小聲）我在這裡…", "要、要喝口可樂嗎？🥤", "被你看到了…", me + "會…安靜陪你", "那個…你辛苦了", "（偷看你一眼）");
            Say("talk_d", "那個…該下班了吧？", "（小聲）天黑了喔…", "你…要不要回家休息？", "明、明天再做也可以的…", "我會等你明天回來…");
            Say("save", "存、存好了…👍", "（小聲）存檔成功", "收好了喔…", "那個…存起來了");
            Say("save_d", "存好了…那、回家吧？", "存好了…可以下班了…");
            Say("pats", "欸…（臉紅）", "那、那個…好舒服", "被摸了…嘿嘿", "（小聲）可以再一下嗎…", "你…今天很努力喔", "我會一直在的…", "謝、謝謝你…");
            Say("pats_d", "那個…摸完要回家喔", "（小聲）你要早點休息…", "嘿嘿…明天見…");
            Say("pats_hi", "能遇到你…真好", "（小聲）最喜歡你了…♥", "我…會一直陪你");
            Say("hugs", "抱、抱抱…（臉紅）", "（小小聲）抱一下…", "(⁄ ⁄•⁄ω⁄•⁄ ⁄)つ ♥");
            Say("hugs_d", "抱完…就回家喔", "晚安抱抱…（小聲）");
            Say("knock", "叩、叩…你在嗎？", "那個…可以看我一下嗎…", "（輕輕敲）我想出去…");
            Say("knock_d", "叩…那個…下班了喔", "你…還在加班嗎…");
            Say("newwin", "新、新視窗…", "那個…我去看一下", "（探頭）");
            Say("newwin_d", "又開新的…明天再看好不好", "那個…別再開了…");
            Say("hi", "那個…我是" + me + "…👋"); Say("hi_d", "嗨…（小聲）下班了嗎？");
            Say("wake", "唔…是你…我醒了"); Say("wake_d", "唔…我在睡…你也去睡…");
            Say("dizzy", "頭、頭好暈…@@"); Say("dizzy_d", "暈暈的…想睡了…");
            Say("dizzy_ok", "好、好了…沒事"); Say("dizzy_ok_d", "沒事了…回家吧…");
            Say("tickle", "不、不要啦…好癢…", "（縮成一團）嘻…", "會、會笑出來啦…"); Say("tickle_d", "最、最後一次喔…");
            Say("pat10", "今天第 {n} 次了…（臉紅）"); Say("pat10_d", "第 {n} 次…那個…該回家了");
            Say("levelup", "好感度 Lv{n}…拿到「{u}」了（小聲）"); Say("levelup_d", "Lv{n}…「{u}」…明天戴給你看…");
            Say("missed", "那個…你好幾天沒摸我了…🥺"); Say("missed_d", "好久沒摸了…（小聲）");
            Say("hover", "那、那個…你在摸我嗎…");
            Say("seek", "那、那是什麼…"); Say("seek_lost", "不見了…"); Say("seek_got", "抓、抓到了…♥");
            Say("drag", "哇、哇…放我下來…"); Say("throw", "呀啊～～");
            Say("shelf_in", "我、我回去了…掰掰"); Say("shelf_in_d", "我先回去了…你也早點休息");
            Say("shelf_out", "那個…我出來了…"); Say("shelf_out_d", "天、天黑了耶…你還在…");
            Say("ball_go", "球、球…我去撿！", "等、等我一下…", "我、我試試看！"); Say("ball_go_d", "最後一球…好嗎？");
            Say("ball_catch", "接、接到了！給你…", "（小聲）我接到了耶", "還你…"); Say("ball_catch_d", "接到了…那個…回家吧");
            Say("ball_end", "不玩了嗎…下次再一起 ⚾"); Say("ball_end_d", "不玩了…那…下班吧");
            Say("ball_far", "球、球跑好遠…");
            Say("back", "我、我回來了…"); Say("back_d", "回來了…（小聲）");
            Say("share_end", "分享結束了…我可以出來了嗎？");
            Say("welcome", "你回來了…（小聲）我有在等"); Say("welcome_d", "你回來了…是要回家了嗎？");
            Say("rest", "那個…已經 {n} 分鐘了，起來喝口可樂、伸展一下好嗎？🥤"); Say("rest_d", "{n} 分鐘了…喝完可樂…就下班吧？🥤");
            Say("night_on", "那個…下班時間到了…"); Say("night_off", "早、早安…☀");
            Say("sleep", "晚安…（小聲）"); Say("sleep_d", "晚安…你也要睡喔…");
            Say("jump", "嘿、嘿咻…"); Say("nojump", "那個…附近沒地方跳…");
            Say("errors", "那個…有 {n} 個錯誤…"); Say("errors_d", "{n} 個錯誤…明天再修好不好…");
            Say("errors_ok", "錯誤都沒了…好厲害！"); Say("errors_ok_d", "修好了…那可以回家了…");
            Say("typing", "打、打好快…", "（小聲）加油…", "好、好厲害…"); Say("typing_d", "打這麼快…是想早點下班嗎…");
            Say("done", "那個…{who} 做完了…"); Say("done_d", "{who} 做完了…你也收工好嗎…");
            Say("wait", "那個…{who} 在等你回答…"); Say("wait_d", "{who} 在等你…回完就回家…");
            Say("ask", "{who} 好像有問題要問你…"); Say("ask_d", "{who} 在問你…回完就下班…");
            Say("stuck_tool", "那個…{who} 停在「{tool}」{n} 分鐘了，是不是在等你按允許？"); Say("stuck_tool_d", "{who} 停了 {n} 分鐘…按一下就回家…");
            Say("stuck", "{who} 好像卡住了…{n} 分鐘沒動…"); Say("stuck_d", "{who} 卡住 {n} 分鐘了…看完就下班…");
            Say("unstuck", "{who} 動起來了…太好了"); Say("unstuck_d", "{who} 動了…");
            Say("tag", "上、上版成功了！🎆"); Say("tag_dev", "測試機上好了…🎆"); Say("tag_prod", "上正式機了…辛苦了 🎉"); Say("tag_d", "上版成功了…那…下班吧？");
            Say("late23", "那個…好晚了…早點睡好嗎 🌙"); Say("late12", "那個…吃午餐了嗎？"); Say("late15", "要、要不要來罐可樂？🥤");
            Say("late_d", "下班時間…早就過了喔…"); Say("late_dd", "好晚了…關機睡覺吧…");
            Say("g_late", "這麼晚…我陪你一下下 🌙"); Say("g_morning", "早、早安…☀"); Say("g_noon", "午安…吃飯了嗎？");
            Say("g_evening", "晚上了…辛苦了"); Say("g_day", "那個…" + me + "出來了…"); Say("g_d", "那個…下班了…你怎麼還在？");
            Say("app_browser", "在看什麼…（偷看）"); Say("app_code", "寫 code…我安靜陪你"); Say("app_excel", "好多格子…加油");
            Say("app_ppt", "做簡報…好厲害"); Say("app_word", "寫文件…慢慢來"); Say("app_chat", "有、有人找你…"); Say("app_files", "在找東西嗎…");
            Say("app_other", "那個…這是什麼？");
            Say("app_code_d", "還在寫…該下班了…"); Say("app_chat_d", "訊息…明天再回好嗎"); Say("app_office_d", "這個…明天做也可以…"); Say("app_other_d", "那個…該回家了…");
            Say("s_birthday", "生、生日快樂！🎂", "（小聲）我有準備蛋糕…生日快樂");
            Say("s_cny", "新年快樂…恭喜發財 🧧", "紅、紅包…不用給我啦…");
            Say("s_xmas", "聖誕快樂…🎄", "（小聲）想跟你一起過聖誕…");
            Say("s_newyear", "新年快樂…今年也請多指教 ✨");
            Say("s_halloween", "不、不給糖就…搗蛋…🎃", "我扮成…（躲到後面）");
            Say("s_friday", "星期五了…再撐一下", "快週末了…今天早點下班好嗎");
            Say("morning", "早、早安…" + me + "來了", "早安…今天也一起加油…");
            Say("goodnight", "晚安…我先回去了", "今天辛苦了…晚安（小聲）");
            Say("nag", "那個…下班了…", "（拉拉你）回家吧…", "該休息了喔…");
            Say("react", "！", "怎、怎麼了？", "欸？");
            // ---- 串場、午餐、小幫手 ----
            Say("x_goal", "進、進球了！🏀"); Say("x_goal_d", "進球了…那、回家吧 🏀");
            Say("x_cheer", "好、好厲害…", "（小聲）進了耶"); Say("x_miss", "差一點點…");
            Say("x_photo", "（躲到後面一點）", "那、那個…要拍了嗎…");
            Say("x_pair_hi", "那個…{o}，你好…"); Say("x_pair_ask", "{o}…可以一起玩嗎？"); Say("x_pair_react", "（小聲）好開心…");
            Say("x_pair_ball", "{o}…接、接球！"); Say("x_pair_ball_end", "好好玩…謝謝你"); Say("x_pair_bye", "那、那我先走了…");
            Say("x_lunch_start", "那個…午餐時間，便當打開了 🔔"); Say("x_lunch_nap", "吃飽了…睡一下…"); Say("x_lunch_end", "回、回來工作了…");
            Say("x_lunch_talk", "便當好好吃…", "（小口小口吃）", "這個…分你一口？");
            Say("x_quiet_on", "我、我會很安靜的…🤫"); Say("x_quiet_off", "安靜時間結束了…（小聲）");
            Say("x_focus_end", "專注結束！休息 5 分鐘 ☕ 你好厲害…"); Say("x_wrap", "那個…今天的我們：");
            // ---- 通知開場白 ----
            Say("x_ci-run", "CI…開始跑了："); Say("x_ci-ok", "CI 過了…太好了！"); Say("x_ci-fail", "那個…CI 失敗了："); Say("x_cmd-ok", "指令跑完了…："); Say("x_cmd-fail", "指令…失敗了：");
            Say("x_meeting", "那個…等一下要開會："); Say("x_meeting-now", "會議開始了…快去："); Say("x_jira", "有新的 Jira…："); Say("x_worklog", "今天的日誌好了…："); Say("x_worklog_d", "日誌好了…然後回家吧：");
            Say("x_remind", "⏰ 那個…提醒你："); Say("x_pc-cpu", "電腦好燙…："); Say("x_pc-ram", "記憶體快滿了…："); Say("x_pc-disk", "硬碟快滿了…：");
            Say("x_net-down", "網、網路斷了！"); Say("x_net-up", "網路回來了…👍"); Say("x_vpn", "那個…連不到公司網路（VPN 斷了？）"); Say("x_download", "下載好了…：");
            Say("x_ticket0", "🎫 {t} 還有 {h}開賣…先登入、綁好付款喔"); Say("x_ticket1", "🎫 {t} 再 30 分鐘…網頁先開好"); Say("x_ticket2", "🎫 {t} 剩 10 分鐘…好緊張…");
            Say("x_ticket3", "🎫 準、準備…手指放好"); Say("x_ticket4", "🎫 開搶！衝、衝啊！");
            Say("x_share", "我家的" + me + "害羞地住進我電腦了 🙈 #我的桌面公仔 #WoWoPals", me + "每天偷偷在我桌面上陪我 ✨ #我的桌面公仔 #WoWoPals");
            Say("x_sig", "那、那我表演一下…"); Say("x_sit", "坐、坐一下…");
            // ---- 小動作 ----
            Say("x_push", "啊…（不小心推下去了）"); Say("x_ignore", "（害羞到轉過去）"); Say("x_comeback", "那個…我回來了…");
            Say("x_loaf", "縮起來…比較安心…"); Say("x_wag", "（開心得扭來扭去）"); Say("x_fetch_back", "撿、撿回來了…給你"); Say("x_return", "你回來了！…（小聲）好想你");
        }

        // ---------------- 搞笑：冷笑話停不下來 ----------------
        void CuFunny(string me)
        {
            Say("talk", "我今天的 KPI：可愛。", "要喝口可樂嗎？氣泡跟我一樣多 🥤", "Bug 是 feature 的遠房親戚。", "我是公仔，不是工仔。", me + "：專業陪笑三十年", "螢幕為什麼這麼亮？因為有我。", "今日運勢：大吉，因為有我。");
            Say("talk_d", "加班費我看不到，你也看不到。", "電腦都想睡了，你呢？", "下班不積極，思想有問題！", "明天的你會感謝今天早睡的你。", "再不走，我要開始講冷笑話了。");
            Say("save", "存檔！比存錢簡單多了 👍", "存好了，存款就不一定了", "Ctrl+S，人生救命鍵", "存起來！記性比我好");
            Say("save_d", "存好了，人也該存回家了", "存檔完畢，請攜帶隨身物品下班");
            Say("pats", "摸頭會長高嗎？試試看", "再摸要收費囉（騙你的）", "這是今日份的摸摸 ♥", "你的手比暖暖包還暖", "被摸到要融化了～", "摸一下，bug 少一個", "我宣布你是今日最佳員工", "嘿嘿，我很好摸吧");
            Say("pats_d", "摸完打卡下班！", "夜間摸摸加收服務費：早點睡", "摸摸 OK，加班 NO");
            Say("pats_hi", "你是我的頭號粉絲！", "我們這組合，可以出道了", "我最喜歡你了，這句不搞笑 ♥");
            Say("hugs", "抱抱！免費的喔", "人體暖暖包啟動！", "(つ´ω`)つ 抱一下不用錢");
            Say("hugs_d", "晚安抱抱，抱完下班", "抱完這下，電腦關機");
            Say("knock", "叩叩！外送到了…是我啦 👀", "哈囉～螢幕外的人類！", "叩叩！有人要聽笑話嗎？");
            Say("knock_d", "叩叩！保全巡邏，請你下班", "叩叩！你的床打電話來找你");
            Say("newwin", "新視窗！開箱囉！", "這是什麼？我要評分！", "又一個新世界！");
            Say("newwin_d", "還開？你是視窗收藏家嗎？", "新視窗明天再開，比較新鮮");
            Say("hi", "嗨！我是" + me + "，請多指教 👋"); Say("hi_d", "晚上好～下班沒？");
            Say("wake", "我沒睡！我在…閉目養神"); Say("wake_d", "我在充電…你也去充一下");
            Say("dizzy", "轉轉轉～世界在旋轉 @@"); Say("dizzy_d", "暈了…這就是加班的感覺嗎");
            Say("dizzy_ok", "復活！我是不死身！"); Say("dizzy_ok_d", "好了…那我們一起下班吧");
            Say("tickle", "哈哈哈住手！我要報警了！", "癢死了！你犯規！", "哈哈哈…我投降！"); Say("tickle_d", "哈…夜間禁止搔癢！");
            Say("pat10", "今天第 {n} 次摸摸！破紀錄了嗎？"); Say("pat10_d", "第 {n} 次了，摸摸額度用完，回家吧");
            Say("levelup", "叮咚！好感度 Lv{n}！獲得「{u}」！"); Say("levelup_d", "Lv{n}！「{u}」明天再秀給你看");
            Say("missed", "幾天沒摸我了？我要寫信給客服 🥺"); Say("missed_d", "好幾天沒摸…我都快生灰塵了");
            Say("hover", "滑鼠停我身上？要收停車費喔");
            Say("seek", "那是什麼？能吃嗎？"); Say("seek_lost", "可惡，被它跑了"); Say("seek_got", "抓到滑鼠！今晚加菜！");
            Say("drag", "綁架啊——！"); Say("throw", "我會飛——！");
            Say("shelf_in", "下班打卡，回櫃子囉 👋"); Say("shelf_in_d", "我先下班了，你呢？");
            Say("shelf_out", "我出來了！掌聲在哪？"); Say("shelf_out_d", "天黑了還叫我出來？加班費咧？");
            Say("ball_go", "球！看我的魔術接球！", "我是球王！", "讓開讓開！"); Say("ball_go_d", "最後一球，打完收工！");
            Say("ball_catch", "接到！觀眾請鼓掌！", "好球！我可以去打職棒了", "還你～下一球加點難度"); Say("ball_catch_d", "接到了，然後下班！");
            Say("ball_end", "不玩了？我還沒表演完耶 ⚾"); Say("ball_end_d", "比賽結束，大家回家！");
            Say("ball_far", "球跑去度假了…");
            Say("back", "我回來了！想我嗎？"); Say("back_d", "回來了…順便提醒你該下班了");
            Say("share_end", "分享完了？輪到我上場了吧！");
            Say("welcome", "你回來了！我數羊數到第 999 隻了"); Say("welcome_d", "回來了？是回來關機的吧");
            Say("rest", "已經 {n} 分鐘了！起來喝口可樂、伸展一下，屁股會謝謝你 🥤"); Say("rest_d", "{n} 分鐘了！喝完可樂就下班吧 🥤");
            Say("night_on", "下班鈴響了！叮叮叮！"); Say("night_off", "早安！今天的我也很好笑 ☀");
            Say("sleep", "晚安，zZ…（假裝打呼）"); Say("sleep_d", "晚安，你也去睡，不准偷滑手機");
            Say("jump", "跳！"); Say("nojump", "附近沒地方跳，我又不會飛");
            Say("errors", "{n} 個錯誤！bug 在開派對嗎"); Say("errors_d", "{n} 個錯誤…讓它們熬夜，你回家");
            Say("errors_ok", "錯誤歸零！你是除蟲大師！"); Say("errors_ok_d", "全修好了！下班理由 +1");
            Say("typing", "鍵盤要冒煙了！🔥", "打字速度：光速！", "手指在跳街舞耶！"); Say("typing_d", "打這麼快，是急著下班吧？");
            Say("done", "{who} 做完了！快來驗收 👀"); Say("done_d", "{who} 做完了，換你下班了");
            Say("wait", "{who} 在等你回話喔～👋"); Say("wait_d", "{who} 在等你，回完就打卡下班");
            Say("ask", "{who} 有問題！快舉手回答 🙋"); Say("ask_d", "{who} 在問你，回完就跑");
            Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，是在等你按允許嗎？"); Say("stuck_tool_d", "{who} 停了 {n} 分鐘，按完一起下班");
            Say("stuck", "{who} {n} 分鐘沒動了，在冥想嗎？去看看"); Say("stuck_d", "{who} 卡 {n} 分鐘了，看完就回家");
            Say("unstuck", "{who} 又動了！復活成功 👍"); Say("unstuck_d", "{who} 動了，你也動身回家吧");
            Say("tag", "上版成功！放煙火 🎆"); Say("tag_dev", "測試機上好了！先放小煙火 🎆"); Say("tag_prod", "上正式機！今晚加雞腿 🎉"); Say("tag_d", "上版成功！那現在可以下班了吧？");
            Say("late23", "這麼晚了，貓頭鷹都下班了 🌙"); Say("late12", "午餐吃什麼？我推薦…我不能吃"); Say("late15", "下午茶！可樂配洋芋片 🥤");
            Say("late_d", "下班時間早就過啦！"); Say("late_dd", "現在是睡覺時間，不是工作時間");
            Say("g_late", "夜貓子你好！我陪你 🌙"); Say("g_morning", "早安！今天的笑點已備妥 ☀"); Say("g_noon", "午安～吃飯皇帝大！");
            Say("g_evening", "晚上好！辛苦啦～"); Say("g_day", me + "閃亮登場！"); Say("g_d", "下班了還開電腦？電腦也想放假");
            Say("app_browser", "在逛什麼？購物車別太滿喔"); Say("app_code", "寫 code！bug 退散！"); Say("app_excel", "Excel！格子們排隊報數！");
            Say("app_ppt", "做簡報？記得放我的照片"); Say("app_word", "寫文件～字數夠嗎？"); Say("app_chat", "有人找你聊天？八卦分我"); Say("app_files", "找檔案？它一定在最後一個資料夾");
            Say("app_other", "這是什麼？看起來很厲害");
            Say("app_code_d", "還寫 code？下班才是最好的 commit"); Say("app_chat_d", "下班了，已讀不回是你的權利"); Say("app_office_d", "這份明天做，今天的你已經很棒了"); Say("app_other_d", "不管這是什麼，都該下班了");
            Say("s_birthday", "生日快樂！🎂 你又升級了！", "生日快樂，蛋糕我先試吃一口", "今天你是壽星，你最大！");
            Say("s_cny", "新年快樂！紅包拿來 🧧", "恭喜發財，紅包…我收現金");
            Say("s_xmas", "聖誕快樂！🎄", "聖誕老人說你今年很乖，可以準時下班");
            Say("s_newyear", "新年快樂！新年新希望：少一點 bug ✨");
            Say("s_halloween", "不給糖就搗蛋！🎃", "我扮成…一個正常人");
            Say("s_friday", "星期五！快樂星期五！", "週五了，今天的 bug 下週再說");
            Say("morning", "早安！" + me + "準時打卡 ☀", "早安～今天也請多指教！");
            Say("goodnight", "晚安～我先下班囉 👋", "今天辛苦了，夢裡見！");
            Say("nag", "下班！現在！立刻！", "你的床在哭了", "再不走我要唱歌了");
            Say("react", "！", "怎麼了怎麼了？", "誰叫我？");
            // ---- 串場、午餐、小幫手 ----
            Say("x_goal", "進球！🏀 三分球！"); Say("x_goal_d", "進球！🏀 收工！");
            Say("x_cheer", "好球！給你按讚", "神射手！"); Say("x_miss", "差一點！裁判，我要看重播！");
            Say("x_photo", "（比 YA 加鬥雞眼）", "等等，我的瀏海！");
            Say("x_pair_hi", "{o}！你今天也很好笑嗎？"); Say("x_pair_ask", "{o}，你知道 bug 最怕什麼嗎？"); Say("x_pair_react", "哈哈哈！你比我還好笑！");
            Say("x_pair_ball", "{o}！魔球來了！"); Say("x_pair_ball_end", "精彩！下一場再戰！"); Say("x_pair_bye", "掰啦，記得想我！");
            Say("x_lunch_start", "午餐時間！便當開箱 🔔"); Say("x_lunch_nap", "吃飽了…飯後想睡是人之常情"); Say("x_lunch_end", "回來工作！吃飽才有力氣抓 bug");
            Say("x_lunch_talk", "這個便當我給五顆星", "排骨是我的，不准偷吃", "吃飯皇帝大，bug 等一下");
            Say("x_quiet_on", "好，我把嘴巴拉上拉鍊 🤫"); Say("x_quiet_off", "安靜結束！我憋了好多笑話");
            Say("x_focus_end", "專注結束！休息 5 分鐘 ☕ 你是專注之王！"); Say("x_wrap", "今日戰報：");
            // ---- 通知開場白 ----
            Say("x_ci-run", "CI 出發！祝它一路順風："); Say("x_ci-ok", "CI 過了！放鞭炮！"); Say("x_ci-fail", "CI 掛了，它需要一點愛："); Say("x_cmd-ok", "指令跑完了："); Say("x_cmd-fail", "指令失敗了，不哭不哭：");
            Say("x_meeting", "等一下要開會，先去裝水："); Say("x_meeting-now", "會議開始了！快衝："); Say("x_jira", "新的 Jira 來敲門了："); Say("x_worklog", "今天的日誌好了："); Say("x_worklog_d", "日誌好了，然後打卡下班：");
            Say("x_remind", "⏰ 叮咚！提醒你："); Say("x_pc-cpu", "電腦燙到可以煎蛋了："); Say("x_pc-ram", "記憶體快滿了："); Say("x_pc-disk", "硬碟快塞爆了：");
            Say("x_net-down", "網路斷了！世界末日！"); Say("x_net-up", "網路回來了！人類得救了 👍"); Say("x_vpn", "連不到公司網路（VPN 斷了？）"); Say("x_download", "下載好了！");
            Say("x_ticket0", "🎫 {t} 還有 {h}開賣！先登入、綁好付款"); Say("x_ticket1", "🎫 {t} 再 30 分鐘開賣，網頁先開好"); Say("x_ticket2", "🎫 {t} 剩 10 分鐘！手指熱身！");
            Say("x_ticket3", "🎫 準備！深呼吸，不要手抖"); Say("x_ticket4", "🎫 開搶！！衝啊！");
            Say("x_share", "我家" + me + "住進我電腦了，還會講冷笑話 ✨ #我的桌面公仔 #WoWoPals", me + "在我桌面上班，薪水是摸摸 🤡 #我的桌面公仔 #WoWoPals");
            Say("x_sig", "看我的招牌絕技！"); Say("x_sit", "坐下，休息是為了走更長的路");
            // ---- 小動作 ----
            Say("x_push", "（推）喔不，地心引力贏了"); Say("x_ignore", "我在生氣（假的）"); Say("x_comeback", "好啦好啦，氣消了！");
            Say("x_loaf", "變身：麻糬模式"); Say("x_wag", "開心到搖頭晃腦！"); Say("x_fetch_back", "球撿回來了！有小費嗎？"); Say("x_return", "你回來了！我數羊數到睡著了！");
        }

        // ---------------- 喵系：高冷，但會偷偷黏你 ----------------
        void CuCat(string me)
        {
            Say("talk", "……喵。", "這個位置是我的。", "罐罐呢？", "（舔爪子）", "你的鍵盤，好溫暖。", me + "在巡視領土。", "（盯著你）……沒事。", "可樂？我喝水就好。🥤");
            Say("talk_d", "天黑了，該餵我然後去睡。", "下班。我說了算。", "……你還不睡？喵。", "我的晚餐時間到了，你的下班時間也是。", "（打哈欠）你也該休息了。");
            Say("save", "存好了。喵。", "（踩一下 Ctrl+S）", "嗯，存了。👍", "勉強幫你看著。存好了。");
            Say("save_d", "存了。快回家餵我。", "存好了。關燈，睡覺。");
            Say("pats", "……還可以。", "（呼嚕呼嚕）", "下巴…對，就是那裡。", "我沒有很喜歡。…繼續。", "喵～（瞇眼）", "只准摸頭。", "（蹭你的手）");
            Say("pats_d", "摸完就去睡。", "（呼嚕）…晚了，回家。", "嗯…明天再摸。");
            Say("pats_hi", "（翻肚子）……只給你看。", "你是我的人類。", "（輕輕咬一下）這是喜歡的意思。");
            Say("hugs", "……就一下下。喵。", "（勉強被抱）", "(=´ω`=) 抱吧。");
            Say("hugs_d", "抱完回家。", "（呼嚕）晚安。");
            Say("knock", "（拍螢幕）喂。", "喵！看這裡。", "（用爪子敲敲）放我出去。");
            Say("knock_d", "（拍拍）下班了。", "喵…你還在？");
            Say("newwin", "（耳朵豎起來）", "新的東西…我去聞聞。", "喵？");
            Say("newwin_d", "不要再開了。", "明天再看。喵。");
            Say("hi", "喵。我是" + me + "。"); Say("hi_d", "喵…下班了沒？");
            Say("wake", "（伸懶腰）……幹嘛。"); Say("wake_d", "我在睡。你也是。");
            Say("dizzy", "喵嗚…頭好暈 @@"); Say("dizzy_d", "暈…睡了…");
            Say("dizzy_ok", "（甩甩頭）沒事。"); Say("dizzy_ok_d", "好了。回家。");
            Say("tickle", "（咬你）", "喵！不准摸肚子！", "（踢踢）……再來我就咬了"); Say("tickle_d", "夠了。喵。");
            Say("pat10", "今天第 {n} 次了。…准了。"); Say("pat10_d", "第 {n} 次。睡覺。");
            Say("levelup", "好感度 Lv{n}。「{u}」…還算喜歡。"); Say("levelup_d", "Lv{n}。「{u}」。明天戴。");
            Say("missed", "好幾天沒摸我。…我也沒在等。🥺"); Say("missed_d", "哼。好幾天了。");
            Say("hover", "（尾巴勾住滑鼠）");
            Say("seek", "（壓低身體）……獵物。"); Say("seek_lost", "跑了。我本來就不想抓。"); Say("seek_got", "（撲！）抓到了。");
            Say("drag", "喵嗚——放開！"); Say("throw", "喵～～！（準備四腳著地）");
            Say("shelf_in", "我回窩了。"); Say("shelf_in_d", "回窩睡覺。你也是。");
            Say("shelf_out", "（伸懶腰）巡邏時間。"); Say("shelf_out_d", "夜貓出動。…你怎麼還在？");
            Say("ball_go", "（盯）……喵！", "我要那顆。", "（屁股扭扭）撲！"); Say("ball_go_d", "最後一次。");
            Say("ball_catch", "抓到了。…不還。…好啦還你。", "（用爪子撥回去）", "太簡單了。"); Say("ball_catch_d", "抓到了。睡覺。");
            Say("ball_end", "不玩了？我本來就累了 ⚾"); Say("ball_end_d", "不玩了。回家。");
            Say("ball_far", "太遠了。我不撿。");
            Say("back", "我回來了。沒有想你。"); Say("back_d", "回來了。");
            Say("share_end", "分享完了？這裡還是我的地盤。");
            Say("welcome", "你回來了。…（蹭蹭）"); Say("welcome_d", "回來了。是要回家餵我吧？");
            Say("rest", "已經 {n} 分鐘了。起來喝口可樂、伸個懶腰，像我這樣。🥤"); Say("rest_d", "{n} 分鐘了。喝完可樂就下班。🥤");
            Say("night_on", "天黑了。夜貓時間，人類下班。"); Say("night_off", "早。（伸懶腰）☀");
            Say("sleep", "（縮成一團）zZ"); Say("sleep_d", "睡了。你也睡。");
            Say("jump", "（輕巧一跳）"); Say("nojump", "沒有高的地方。無聊。");
            Say("errors", "{n} 個錯誤。（嫌棄）"); Say("errors_d", "{n} 個錯誤。明天再說。");
            Say("errors_ok", "清乾淨了。…還不錯。"); Say("errors_ok_d", "修好了。下班。");
            Say("typing", "（想踩你的鍵盤）", "打好快。我也想打。", "（盯著游標）"); Say("typing_d", "打完了就去睡。");
            Say("done", "{who} 做完了。去看。"); Say("done_d", "{who} 做完了。你也收工。");
            Say("wait", "{who} 在等你。喵。"); Say("wait_d", "{who} 在等你。回完就睡。");
            Say("ask", "{who} 在問你。（尾巴甩甩）"); Say("ask_d", "{who} 在問。回完下班。");
            Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，大概在等你按允許。"); Say("stuck_tool_d", "{who} 停 {n} 分鐘了。按完就回家。");
            Say("stuck", "{who} {n} 分鐘沒動了。睡著了？去看看。"); Say("stuck_d", "{who} 卡 {n} 分鐘。看完下班。");
            Say("unstuck", "{who} 動了。喵。"); Say("unstuck_d", "{who} 動了。");
            Say("tag", "上版成功。賞你摸一下。🎆"); Say("tag_dev", "測試機，過了。🎆"); Say("tag_prod", "上正式機了。今晚開罐罐。🎉"); Say("tag_d", "上完了。下班。");
            Say("late23", "人類該睡了。🌙"); Say("late12", "午餐。我的罐罐呢？"); Say("late15", "點心時間。可樂給你，肉泥給我 🥤");
            Say("late_d", "下班時間過了。"); Say("late_dd", "太晚了。關機。睡覺。");
            Say("g_late", "夜貓子。我陪你。🌙"); Say("g_morning", "早。…我的早餐呢？☀"); Say("g_noon", "午安。吃了沒。");
            Say("g_evening", "晚上了。辛苦。"); Say("g_day", me + "出巡。"); Say("g_d", "下班了。為什麼還開著電腦？");
            Say("app_browser", "在看什麼？有貓影片嗎？"); Say("app_code", "寫 code。我坐鍵盤旁邊。"); Say("app_excel", "好多格子。像我的窩。");
            Say("app_ppt", "簡報？放我的照片。"); Say("app_word", "寫字。我想踩一下。"); Say("app_chat", "有人找你？…不准理別人。"); Say("app_files", "找東西？我幫你推下桌。");
            Say("app_other", "這是什麼。我聞一下。");
            Say("app_code_d", "還寫？去睡。"); Say("app_chat_d", "明天再回。現在陪我。"); Say("app_office_d", "明天做。"); Say("app_other_d", "下班。喵。");
            Say("s_birthday", "生日快樂。🎂 蛋糕上的奶油給我。", "今天你最大。…只有今天。");
            Say("s_cny", "新年快樂。🧧", "紅包？我要罐罐。");
            Say("s_xmas", "聖誕快樂。🎄", "禮物拆完，箱子給我。");
            Say("s_newyear", "新年快樂。今年也歸我管。✨");
            Say("s_halloween", "不給肉泥就搗蛋。🎃", "我扮成…一隻貓。很像吧？");
            Say("s_friday", "星期五。早點回來陪我。", "週末到了。你可以整天陪我睡。");
            Say("morning", "早。" + me + "巡邏開始。", "（伸懶腰）早。今天也陪你。");
            Say("goodnight", "晚安。我回窩了。", "（呼嚕）晚安。");
            Say("nag", "下班。", "（躺在鍵盤上）不准再打了。", "回家。");
            Say("react", "（耳朵一豎）", "喵？", "……嗯？");
            // ---- 串場、午餐、小幫手 ----
            Say("x_goal", "（優雅落地）進球。🏀"); Say("x_goal_d", "進球。回窩睡覺 🏀");
            Say("x_cheer", "……還行。", "（尾巴甩一下）"); Say("x_miss", "偏了。我是故意的。");
            Say("x_photo", "（看別的地方）", "……拍快點。");
            Say("x_pair_hi", "{o}。（聞聞）"); Say("x_pair_ask", "{o}，你有罐罐嗎？"); Say("x_pair_react", "（尾巴翹高）…可以。");
            Say("x_pair_ball", "（撥）{o}，給你。"); Say("x_pair_ball_end", "玩夠了。睡覺。"); Say("x_pair_bye", "（頭也不回地走掉）");
            Say("x_lunch_start", "午餐。便當裡的魚歸我 🔔"); Say("x_lunch_nap", "吃飽了…（縮成麻糬）"); Say("x_lunch_end", "（伸懶腰）回來工作。");
            Say("x_lunch_talk", "魚，好吃。", "（偷挖一口便當）", "這塊肉…我先檢查。");
            Say("x_quiet_on", "安靜？我本來就很安靜。🤫"); Say("x_quiet_off", "安靜結束。可以餵我了。");
            Say("x_focus_end", "專注結束！休息 5 分鐘 ☕ 來摸我。"); Say("x_wrap", "今天的巡邏報告：");
            // ---- 通知開場白 ----
            Say("x_ci-run", "CI 在跑。我盯著："); Say("x_ci-ok", "CI 過了。喵。"); Say("x_ci-fail", "CI 壞了。（嫌棄）："); Say("x_cmd-ok", "指令跑完了："); Say("x_cmd-fail", "指令失敗了。不是我推的：");
            Say("x_meeting", "等等要開會："); Say("x_meeting-now", "開會了。去吧："); Say("x_jira", "新的 Jira："); Say("x_worklog", "日誌好了："); Say("x_worklog_d", "日誌好了。回家餵我：");
            Say("x_remind", "⏰ 喵。提醒你："); Say("x_pc-cpu", "電腦好燙，好適合睡："); Say("x_pc-ram", "記憶體快滿了："); Say("x_pc-disk", "硬碟快滿了：");
            Say("x_net-down", "網路斷了。不是我咬的！"); Say("x_net-up", "網路回來了。喵 👍"); Say("x_vpn", "連不到公司網路（VPN 斷了？）"); Say("x_download", "下載好了：");
            Say("x_ticket0", "🎫 {t} 還有 {h}開賣。先登入、綁好付款"); Say("x_ticket1", "🎫 {t} 再 30 分鐘開賣。網頁先開好"); Say("x_ticket2", "🎫 {t} 剩 10 分鐘。（尾巴甩甩）");
            Say("x_ticket3", "🎫 準備。像撲獵物那樣"); Say("x_ticket4", "🎫 開搶！撲！");
            Say("x_share", "我家" + me + "住進我電腦了 🐾 #我的桌面公仔 #WoWoPals", me + "現在連我的桌面都要佔領 🐾 #我的桌面公仔 #WoWoPals", "上班有" + me + "盯著，不敢偷懶 🐱 #我的桌面公仔 #WoWoPals");
            Say("x_sig", "（伸懶腰，然後一躍）"); Say("x_sit", "（坐下，尾巴繞好）");
            // ---- 貓的小動作：推東西、不理你又回來、縮成土司 ----
            Say("x_push", "（推）……掉下去了。", "（盯著你，慢慢推）", "這個不需要。（推）"); Say("x_ignore", "（背對你）", "現在不想理你。"); Say("x_comeback", "（蹭蹭）……只是剛好路過。", "（跳回你旁邊）");
            Say("x_loaf", "（縮成土司）", "（收起腳，變成麻糬）"); Say("x_wag", "（尾巴豎得直直的）"); Say("x_fetch_back", "（叼回來，放下，走掉）"); Say("x_return", "你回來了。（假裝沒在等）");
        }

        // ---------------- 汪系：超黏人，看到你就搖尾巴 ----------------
        void CuDog(string me)
        {
            Say("talk", "汪！今天也一起努力！", "要喝口可樂嗎？我幫你叼過來！🥤", "（搖尾巴）汪！", "你在做什麼？我也要！", me + "隨時待命！汪！", "好想出去散步喔～", "你是世界上最棒的人！");
            Say("talk_d", "汪…下班時間到了！", "散步時間！我們回家吧！", "（咬住你的衣角）回家啦～", "你累了吧？回家休息！汪", "明天再一起努力！");
            Say("save", "汪！存好了！👍", "存檔成功！（搖尾巴）", "我幫你守著！存好了！", "汪汪！收好了！");
            Say("save_d", "存好了！回家散步！", "存好了！汪！下班下班！");
            Say("pats", "汪～好舒服！", "（尾巴搖到停不下來）", "再摸！再摸！", "你是最棒的主人！", "（翻肚子）這邊也要！", "你辛苦了！舔舔你！", "汪！好開心！", "我會一直保護你！");
            Say("pats_d", "摸完我們就回家！", "汪…你今天好累吧", "（趴下）明天再玩…");
            Say("pats_hi", "你是我的全世界！", "汪！最最最喜歡你！", "一輩子跟著你！");
            Say("hugs", "抱抱！汪！", "（撲上去）大抱抱！", "(U・ᴥ・U)つ ♥");
            Say("hugs_d", "晚安抱抱！回家囉！", "抱完一起回家！");
            Say("knock", "汪！看我看我！👀", "（鼻子貼玻璃）汪！", "可以出去玩嗎？汪汪！");
            Say("knock_d", "汪…該回家了！", "（扒扒螢幕）下班下班！");
            Say("newwin", "汪！新的！", "我去看看！（衝）", "（嗅嗅）這是什麼？");
            Say("newwin_d", "汪…明天再看！", "不要再開了，回家！");
            Say("hi", "汪！我是" + me + "！👋"); Say("hi_d", "汪～下班了嗎？");
            Say("wake", "汪！你來了！我醒了！"); Say("wake_d", "（迷迷糊糊搖尾巴）你也去睡…");
            Say("dizzy", "汪嗚…轉圈圈 @@"); Say("dizzy_d", "暈暈…想睡了…");
            Say("dizzy_ok", "汪！我好了！再玩！"); Say("dizzy_ok_d", "好了！回家囉！");
            Say("tickle", "汪哈哈！好癢！", "（打滾）汪汪汪！", "再來！再來！"); Say("tickle_d", "汪…最後一次！");
            Say("pat10", "今天第 {n} 次摸摸！汪！好幸福！"); Say("pat10_d", "第 {n} 次了！摸完回家！");
            Say("levelup", "汪！好感度 Lv{n}！拿到「{u}」了！"); Say("levelup_d", "Lv{n}！「{u}」明天戴給你看！汪");
            Say("missed", "你好幾天沒摸我了…嗚嗚 🥺"); Say("missed_d", "好久沒摸了…我一直在等你");
            Say("hover", "汪？你在摸我嗎？（搖尾巴）");
            Say("seek", "汪！那是什麼！"); Say("seek_lost", "嗚…跑掉了"); Say("seek_got", "抓到了！汪汪！");
            Say("drag", "汪嗚～要去哪裡？"); Say("throw", "汪～～～！");
            Say("shelf_in", "我回狗窩囉！汪！"); Say("shelf_in_d", "我回去顧家，你也早點回來！");
            Say("shelf_out", "汪！出來玩了！"); Say("shelf_out_d", "汪？天黑了，你怎麼還在？");
            Say("ball_go", "球！球！球！", "汪！我去撿！", "（衝刺）等我！"); Say("ball_go_d", "最後一球！汪！");
            Say("ball_catch", "接到了！再丟一次！", "汪！我很棒吧！", "（叼著球）還要還要！"); Say("ball_catch_d", "接到了！回家吧！");
            Say("ball_end", "不玩了嗎…好吧，下次再玩！⚾"); Say("ball_end_d", "不玩了！那我們回家！");
            Say("ball_far", "球好遠…我還是會去撿！");
            Say("back", "汪！我回來了！"); Say("back_d", "回來了！該回家囉！");
            Say("share_end", "分享完了？汪！我回來了！");
            Say("welcome", "你回來了！！汪汪汪！"); Say("welcome_d", "你回來了！是要帶我回家嗎？");
            Say("rest", "已經 {n} 分鐘了！起來喝口可樂、伸展一下，順便摸摸我！🥤"); Say("rest_d", "{n} 分鐘了！喝完可樂就回家散步吧 🥤");
            Say("night_on", "汪…下班時間到了！"); Say("night_off", "早安！汪！今天也好開心 ☀");
            Say("sleep", "（趴下）晚安…汪"); Say("sleep_d", "晚安！你也要睡喔！");
            Say("jump", "汪！跳！"); Say("nojump", "這裡沒地方跳…汪");
            Say("errors", "汪汪！有 {n} 個錯誤！我來顧！"); Say("errors_d", "{n} 個錯誤…明天再修，先回家！");
            Say("errors_ok", "錯誤都沒了！汪！抱抱！"); Say("errors_ok_d", "修好了！回家囉！");
            Say("typing", "打好快！汪汪加油！", "（跟著打字聲搖尾巴）", "你好厲害！汪！"); Say("typing_d", "打快一點，早點回家！");
            Say("done", "汪！{who} 做完了！快來看 👀"); Say("done_d", "{who} 做完了！收工回家！");
            Say("wait", "{who} 在等你回答喔！汪 👋"); Say("wait_d", "{who} 在等你，回完就回家！");
            Say("ask", "{who} 有問題要問你！🙋"); Say("ask_d", "{who} 在問你，回完就下班！");
            Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了，是不是在等你按允許？汪！"); Say("stuck_tool_d", "{who} 停了 {n} 分鐘！按完回家！");
            Say("stuck", "汪！{who} {n} 分鐘沒動了，去看看！"); Say("stuck_d", "{who} 卡住 {n} 分鐘，看完就回家！");
            Say("unstuck", "{who} 又動了！汪！👍"); Say("unstuck_d", "{who} 動了！");
            Say("tag", "上版成功！汪汪汪！🎆"); Say("tag_dev", "測試機成功！汪！🎆"); Say("tag_prod", "上正式機了！你最棒了！🎉"); Say("tag_d", "上版成功！現在可以回家了吧？汪");
            Say("late23", "好晚了…汪，早點睡 🌙"); Say("late12", "午餐時間！我也餓了！"); Say("late15", "下午茶！可樂給你，骨頭給我 🥤");
            Say("late_d", "下班時間過了！汪！"); Say("late_dd", "好晚了！關機睡覺！");
            Say("g_late", "這麼晚了…我陪你！汪 🌙"); Say("g_morning", "早安！汪！看到你好開心 ☀"); Say("g_noon", "午安！吃飯了嗎？汪");
            Say("g_evening", "晚上了！辛苦了！汪"); Say("g_day", me + "來了！汪汪！"); Say("g_d", "下班了！你怎麼還在？汪");
            Say("app_browser", "在看什麼？有狗狗影片嗎？"); Say("app_code", "寫 code！我在旁邊守著！"); Say("app_excel", "好多格子！加油！汪");
            Say("app_ppt", "做簡報？我幫你看！"); Say("app_word", "寫文件～加油！"); Say("app_chat", "有人找你！汪！"); Say("app_files", "找東西？我鼻子很靈！");
            Say("app_other", "汪？這是什麼？");
            Say("app_code_d", "還在寫…回家啦！汪"); Say("app_chat_d", "明天再回！陪我散步！"); Say("app_office_d", "明天做嘛～汪"); Say("app_other_d", "下班了！回家！");
            Say("s_birthday", "生日快樂！汪汪汪！🎂", "今天你最大！我幫你吹蠟燭！");
            Say("s_cny", "新年快樂！汪！🧧", "恭喜發財！今年也要一起散步！");
            Say("s_xmas", "聖誕快樂！🎄", "我想要的禮物…是新的球！");
            Say("s_newyear", "新年快樂！今年也要一起！✨");
            Say("s_halloween", "不給零食就搗蛋！🎃", "我扮成…一隻狼！嗷嗚～");
            Say("s_friday", "星期五！週末可以出去玩了嗎？", "快放假了！汪汪！");
            Say("morning", "早安！" + me + "報到！汪！", "早安～今天也要一起努力！");
            Say("goodnight", "晚安！我回狗窩囉！", "今天辛苦了！晚安，汪");
            Say("nag", "汪！下班！", "（叼來你的包包）回家啦！", "散步時間到了！");
            Say("react", "汪？", "汪！", "怎麼了怎麼了？");
            // ---- 串場、午餐、小幫手 ----
            Say("x_goal", "汪！進球！🏀"); Say("x_goal_d", "進球！回家囉！🏀");
            Say("x_cheer", "汪汪！好厲害！", "（跳起來）汪！"); Say("x_miss", "差一點！再來再來！");
            Say("x_photo", "（吐舌頭笑）汪！", "我要站中間！");
            Say("x_pair_hi", "{o}！汪汪！（聞聞）"); Say("x_pair_ask", "{o}，要不要一起玩球？"); Say("x_pair_react", "汪！好耶！");
            Say("x_pair_ball", "{o}，接球！汪！"); Say("x_pair_ball_end", "好好玩！再一次！"); Say("x_pair_bye", "掰掰！汪！");
            Say("x_lunch_start", "午餐時間！汪！便當好香 🔔"); Say("x_lunch_nap", "吃飽了…（趴著睡）"); Say("x_lunch_end", "汪！回來工作囉！");
            Say("x_lunch_talk", "便當好好吃！汪！", "這塊肉…可以給我嗎？", "（盯著你的便當流口水）");
            Say("x_quiet_on", "汪…（小聲）我乖乖的 🤫"); Say("x_quiet_off", "安靜結束！汪汪！");
            Say("x_focus_end", "專注結束！休息 5 分鐘 ☕ 來摸摸我！汪"); Say("x_wrap", "汪！今天的我們：");
            // ---- 通知開場白 ----
            Say("x_ci-run", "汪！CI 出發了："); Say("x_ci-ok", "CI 過了！汪汪！"); Say("x_ci-fail", "汪嗚…CI 失敗了："); Say("x_cmd-ok", "指令跑完了！"); Say("x_cmd-fail", "指令失敗了…汪嗚：");
            Say("x_meeting", "等一下要開會喔！"); Say("x_meeting-now", "會議開始了！快去："); Say("x_jira", "汪！有新的 Jira："); Say("x_worklog", "今天的日誌好了："); Say("x_worklog_d", "日誌好了！回家吧：");
            Say("x_remind", "⏰ 汪！提醒你："); Say("x_pc-cpu", "電腦好燙！汪："); Say("x_pc-ram", "記憶體快滿了："); Say("x_pc-disk", "硬碟快滿了：");
            Say("x_net-down", "網路斷了！汪汪！"); Say("x_net-up", "網路回來了！汪 👍"); Say("x_vpn", "連不到公司網路（VPN 斷了？）"); Say("x_download", "下載好了！汪！");
            Say("x_ticket0", "🎫 {t} 還有 {h}開賣！先登入、綁好付款"); Say("x_ticket1", "🎫 {t} 再 30 分鐘！我陪你等！"); Say("x_ticket2", "🎫 {t} 剩 10 分鐘！汪汪！");
            Say("x_ticket3", "🎫 準備！手指放好！"); Say("x_ticket4", "🎫 開搶！！衝啊！汪！");
            Say("x_share", "我家" + me + "住進我電腦了 🐾 #我的桌面公仔 #WoWoPals", me + "每天在我桌面上搖尾巴 🐶 #我的桌面公仔 #WoWoPals", "上班有" + me + "陪，心情好好 🐾 #我的桌面公仔 #WoWoPals");
            Say("x_sig", "汪！看我轉圈圈！"); Say("x_sit", "（乖乖坐好）汪！");
            // ---- 狗的小動作：搖尾巴、撿球回來、你回來就跳 ----
            Say("x_push", "汪？（不小心撞下去了）", "（咬咬…掉下去了）"); Say("x_ignore", "（假裝在聞地板）"); Say("x_comeback", "汪！我回來了！不生氣了！");
            Say("x_loaf", "（趴下，下巴放地上）"); Say("x_wag", "（尾巴搖到屁股都在動）", "汪汪！好開心！"); Say("x_fetch_back", "汪！撿回來了！再丟一次！", "（叼著球跑回來）給你！"); Say("x_return", "你回來了！！汪汪汪！（跳跳跳）");
        }
    }

    // 讀書小幫手（DeskPals.Study.cs）：上課／考試／行程／作業的開場白、考試的一句、熬夜提醒（{hm}＝幾點）、搶課倒數（{t} 課名、{h} 幾小時）
    partial class Pal
    {
        void CuStudyLines(string persona, string me)
        {
            switch (persona)
            {
                case "cool":
                    Say("x_class", "🎒 要上課了："); Say("x_class-now", "🎒 上課了，走。"); Say("x_exam-soon", "📚 要考試了，穩住："); Say("x_exam-now", "📚 考試開始。你可以："); Say("x_event", "等等有事："); Say("x_event-now", "開始了："); Say("x_deadline", "📝 作業："); Say("x_deadline-hot", "📝 快截止了，別拖："); Say("x_deadline-hot_d", "📝 快截止了…交完就睡："); Say("x_exam_prefix", "嗯，"); Say("x_exam_tail", "讀一點，就很酷。"); Say("x_late0", "{hm}。很晚了，該睡了 🌙"); Say("x_late1", "{hm}。熬夜不酷，睡覺才酷。"); Say("x_late2", "{hm}。去睡。真的。😴"); Say("x_course0", "🎓 {t} 還有 {h}開放選課，先登入、志願排好"); Say("x_course1", "🎓 {t} 再 30 分鐘，課號抄好"); Say("x_course2", "🎓 {t} 剩 10 分鐘，穩住"); Say("x_course3", "🎓 準備。手放加選鍵上。"); Say("x_course4", "🎓 開放了。加選！");
                    break;
                case "shy":
                    Say("x_class", "🎒 那個…要上課了："); Say("x_class-now", "🎒 （小聲）上課時間到了…"); Say("x_exam-soon", "📚 那個…快考試了："); Say("x_exam-now", "📚 考試開始了…加油："); Say("x_event", "那個…等一下有事："); Say("x_event-now", "（小聲）開始了："); Say("x_deadline", "📝 那個…作業："); Say("x_deadline-hot", "📝 快、快截止了："); Say("x_deadline-hot_d", "📝 快截止了…寫完就睡喔："); Say("x_exam_prefix", "那個…"); Say("x_exam_tail", "我（小聲）陪你讀…"); Say("x_late0", "那個…已經 {hm} 了…要不要去睡？🌙"); Say("x_late1", "（小聲）{hm} 了…明天會很累的…"); Say("x_late2", "{hm} 了！拜、拜託去睡…😴"); Say("x_course0", "🎓 那個…{t} 還有 {h}開放選課，先登入喔"); Say("x_course1", "🎓 {t} 再 30 分鐘…課號抄好了嗎？"); Say("x_course2", "🎓 {t} 剩 10 分鐘…好緊張"); Say("x_course3", "🎓 準、準備…"); Say("x_course4", "🎓 開放了！快加選！（小聲）");
                    break;
                case "funny":
                    Say("x_class", "🎒 上課時間（不是下課，很遺憾）："); Say("x_class-now", "🎒 上課了！睡覺請小聲："); Say("x_exam-soon", "📚 考試要來了，書在哪？"); Say("x_exam-now", "📚 考試開始！猜 C 不保證對："); Say("x_event", "等一下有事，不是我編的："); Say("x_event-now", "開演了："); Say("x_deadline", "📝 作業在敲門："); Say("x_deadline-hot", "📝 死線在跑百米："); Say("x_deadline-hot_d", "📝 死線熬夜中，你別陪它："); Say("x_exam_prefix", "冷知識："); Say("x_exam_tail", "讀一頁，等於少擔心一頁。"); Say("x_late0", "{hm} 了！現在睡還算早睡（騙你的）🌙"); Say("x_late1", "{hm} 了，你的黑眼圈要升級成熊貓了"); Say("x_late2", "{hm}！再不睡太陽要來跟你打招呼了 😴"); Say("x_course0", "🎓 {t} 還有 {h}開放選課！先登入，手指熱身"); Say("x_course1", "🎓 {t} 再 30 分鐘，課號背起來"); Say("x_course2", "🎓 {t} 剩 10 分鐘！手速決勝負"); Say("x_course3", "🎓 預備——別先按！"); Say("x_course4", "🎓 開放了！！手速全開！");
                    break;
                case "cat":
                    Say("x_class", "🎒 喵。要上課了："); Say("x_class-now", "🎒 上課了。我在這裡睡，你去："); Say("x_exam-soon", "📚 要考試了。本喵罩你："); Say("x_exam-now", "📚 考試開始。喵："); Say("x_event", "等一下有事。記一下："); Say("x_event-now", "開始了，喵："); Say("x_deadline", "📝 作業。別讓我提醒第二次："); Say("x_deadline-hot", "📝 快截止了。喵！"); Say("x_deadline-hot_d", "📝 快截止了…寫完陪我睡："); Say("x_exam_prefix", "喵，"); Say("x_exam_tail", "我趴在課本上陪你（不准移開我）。"); Say("x_late0", "{hm} 了。本喵都睡第三輪了 🌙"); Say("x_late1", "{hm}。被窩比螢幕暖，喵。"); Say("x_late2", "{hm}！我要坐在鍵盤上了 😴"); Say("x_course0", "🎓 {t} 還有 {h}開放選課。先登入，喵"); Say("x_course1", "🎓 {t} 再 30 分鐘。課號抄好"); Say("x_course2", "🎓 {t} 剩 10 分鐘。尾巴豎起來了"); Say("x_course3", "🎓 準備……（壓低身體）"); Say("x_course4", "🎓 開放了！撲！");
                    break;
                case "dog":
                    Say("x_class", "🎒 汪！要上課囉："); Say("x_class-now", "🎒 上課了！汪汪，快去："); Say("x_exam-soon", "📚 要考試了！我幫你加油汪："); Say("x_exam-now", "📚 考試開始！你最棒了汪："); Say("x_event", "汪！等一下有事："); Say("x_event-now", "開始了！汪："); Say("x_deadline", "📝 汪！作業："); Say("x_deadline-hot", "📝 汪汪！快截止了："); Say("x_deadline-hot_d", "📝 快截止了…寫完我們去睡汪："); Say("x_exam_prefix", "汪！"); Say("x_exam_tail", "我坐在旁邊陪你讀，乖乖的！"); Say("x_late0", "{hm} 了汪…我趴著等你去睡 🌙"); Say("x_late1", "{hm} 了！散步明天再說，先睡覺汪"); Say("x_late2", "{hm}！！汪汪汪！去睡覺！😴"); Say("x_course0", "🎓 {t} 還有 {h}開放選課！先登入汪"); Say("x_course1", "🎓 {t} 再 30 分鐘！課號叼好了嗎"); Say("x_course2", "🎓 {t} 剩 10 分鐘！尾巴搖好快"); Say("x_course3", "🎓 坐下…等…"); Say("x_course4", "🎓 開放了！衝啊汪！");
                    break;
                default:
                    Say("x_class", "🎒 要上課囉！" + me + "提醒你："); Say("x_class-now", "🎒 上課時間！衝！"); Say("x_exam-soon", "📚 要考試了，" + me + "幫你加油："); Say("x_exam-now", "📚 考試開始！你可以的："); Say("x_event", "等一下有事喔："); Say("x_event-now", "時間到囉："); Say("x_deadline", "📝 作業提醒："); Say("x_deadline-hot", "📝 快截止了！衝刺："); Say("x_deadline-hot_d", "📝 快截止了…寫完就睡喔："); Say("x_exam_prefix", "嘿！"); Say("x_exam_tail", "" + me + "陪你讀！"); Say("x_late0", "已經 {hm} 了！今天先到這裡好不好？🌙"); Say("x_late1", "{hm} 了，明天還要元氣滿滿，去睡吧"); Say("x_late2", "{hm}！真的該睡了 😴"); Say("x_course0", "🎓 {t} 還有 {h}開放選課！先登入、志願排好"); Say("x_course1", "🎓 {t} 再 30 分鐘！選課頁先開好"); Say("x_course2", "🎓 {t} 剩 10 分鐘！好緊張"); Say("x_course3", "🎓 準備！手指放好！"); Say("x_course4", "🎓 開放了！！快加選！");
                    break;
            }
        }
    }
}
