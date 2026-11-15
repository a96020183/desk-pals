// Desk Pals：皮克敏一櫃（紅、黃、藍皮克敏＋大格的休息花）。個人用的同人像素，與任天堂無關。
// desk-pals.ps1 會把 DeskPals.cs 和 DeskPals.*.cs 接在一起編譯；這個檔的 using 放在 namespace 裡面，接起來才合法。
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.Drawing;
    using System.Drawing.Drawing2D;
    using System.IO;
    using System.Windows.Forms;

    // ================= 角色資料 =================
    partial class Pal
    {
        public bool Pik;                     // 皮克敏（頭上的葉子／花苞／花會長大）
        public const string Pikmin = "pikmin";
        public static readonly string[] PikminIds = { "pkred", "pkyellow", "pkblue" };

        static List<Pal> PikminPals() { return new List<Pal>(new Pal[] { PikRed(), PikYellow(), PikBlue() }); }

        // 18 格寬的格子，身體在第 8～9 欄。頭上的葉子／花苞／花另外疊在莖的頂端（每隻每天各自長）
        static readonly string[] PK_STEM = {
            "..........r.......",
            ".........r........",
            ".........r........",
            "........rr........" };
        static readonly string[] PK_HEAD = {
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
            ".....oorrrRoo....." };
        static readonly string[] PK_BODY = {
            ".......orRo.......",
            "......orrrRo......",
            ".....r.orRo.r.....",
            "....r..orRo..r....",
            ".......orRRo......" };
        static readonly string[] PK_BODY_UP = {
            "....r..orRo..r....",
            ".....rorrrRor.....",
            ".......orRo.......",
            ".......orRo.......",
            ".......orRRo......" };
        static readonly string[] PK_LEGS_A = { ".......o...o......", "......oo...oo....." };
        static readonly string[] PK_LEGS_B = { "......o.....o.....", ".....oo.....oo...." };
        static readonly string[] PK_LEGS_SIT = { "......oo...oo....." };
        static readonly string[] PK_LEAF = {
            "............GGGG..",
            "..........GGgGGGG.",
            ".........GgGGGGG..",
            "........GgGGGG....",
            "........GGG......." };
        static readonly string[] PK_BUD = {
            "..................",
            ".........WW.......",
            "........WWWW......",
            "........WWWw......",
            "........GWwG......" };
        static readonly string[] PK_FLOWER = {
            ".......WW..WW.....",
            "......WWWwwWWW....",
            ".......wWYYWw.....",
            "......WWWyyWWW....",
            ".......WW.gWW....." };

        static int Dusk(int rgb)
        {
            int r = (rgb >> 16) & 255, g = (rgb >> 8) & 255, b = rgb & 255;
            return ((int)(r * 0.72 + 8) << 16) | ((int)(g * 0.70 + 12) << 8) | (int)Math.Min(255, b * 0.75 + 40);   // 天黑：暗一點、偏一點點藍，不要變成泥巴色
        }
        void PCol(char c, int day) { Col(c, day, Dusk(day)); }

        static Pal PikBase(string id, string name, int r, int R, int h, int o)
        {
            Pal p = new Pal();
            p.Id = id; p.Name = name; p.Pik = true; p.BallKind = "tennis"; p.NightStyle = "sleepy"; p.NightBubble = 3;
            p.Halo = Color.White; p.HaloNight = C(0xB8C4F0);
            p.Art["STEM"] = PK_STEM; p.Art["HEAD"] = PK_HEAD; p.Art["BODY"] = PK_BODY; p.Art["ARMS_UP"] = PK_BODY_UP;
            p.Art["LEGS_A"] = PK_LEGS_A; p.Art["LEGS_B"] = PK_LEGS_B; p.Art["LEGS_SIT"] = PK_LEGS_SIT;
            p.Art["LEAF"] = PK_LEAF; p.Art["BUD"] = PK_BUD; p.Art["FLOWER"] = PK_FLOWER;
            int total = PK_LEAF.Length + PK_STEM.Length + PK_HEAD.Length + PK_BODY.Length + PK_LEGS_A.Length;
            p.TopRows = total - 16;
            p.BodyTop = 16 - PK_LEGS_A.Length - PK_BODY.Length;
            p.HeadTop = p.BodyTop - PK_HEAD.Length;
            p.FaceRow = 6; p.EyeRow = -1; p.NoGlasses = true;
            p.HatRow = p.HeadTop + 2; p.HatCol = 0; p.ScarfRow = p.HeadTop + 11; p.GlassRow = p.HeadTop + 6;
            p.BadgeRow = p.BodyTop + 2; p.BadgeCol = 5; p.SideRow = p.BodyTop + 1;
            p.PCol('r', r); p.PCol('R', R); p.PCol('h', h); p.PCol('o', o);
            p.PCol('W', 0xFFFFFF); p.PCol('w', 0xE2E6D2); p.PCol('K', 0x111111); p.PCol('G', 0x3E9E3A); p.PCol('g', 0x7CCB5A);
            p.PCol('y', 0xE09A1A); p.PCol('O', 0xF2852A); p.PCol('b', 0x5AA8E8); p.PCol('v', 0x7A4FC4); p.PCol('V', 0x56309A);
            p.PCol('k', 0x2A2A2A); p.PCol('e', 0xF2B418); p.PCol('N', 0xB81E1C); p.PCol('n', 0xFF8C7C); p.PCol('M', 0xF29AA6);
            p.Accent = C(o); p.Panel = C(0xE8F0D8);
            return p;
        }

        // 共用台詞（皮克敏話很少：噗咿！嘿咻！＋短短的中文）
        void PikLines(string me)
        {
            Say("talk", "噗咿！", "噗咿～", "嘿咻！", me + "在這裡～", "噗咿？（歪頭）", "要喝可樂嗎？噗咿！🥤");
            Say("talk_d", "噗咿…（想睡）", "天黑了…回土裡睡覺…", "噗咿…晚安…", "下班了…噗咿");
            Say("save", "噗咿！存好了！", "嘿咻！收好了～", "噗咿！👍"); Say("save_d", "存好了…噗咿…回家吧", "收好了…晚安");
            Say("pats", "噗咿～", "噗咿！（開心）", "嘿嘿…噗咿", "（葉子晃晃）噗咿！", "喜歡～噗咿！");
            Say("pats_d", "噗咿…（想睡）", "摸摸…然後回家…", "嗯…噗咿…晚安");
            Say("pats_hi", "噗咿！最喜歡你了！", "我們是好夥伴！噗咿！", "一直跟著你～噗咿！");
            Say("hugs", "噗咿～抱抱！", "抱抱！噗咿！", "(つ´ω`)つ 噗咿"); Say("hugs_d", "抱抱…晚安…噗咿", "抱完回家…");
            Say("knock", "叩叩！噗咿！", "噗咿？（敲敲）", "要出去！噗咿！"); Say("knock_d", "叩叩…天黑了…回家", "噗咿…下班了…");
            Say("newwin", "噗咿！", "噗咿？新的！", "嘿咻！去看看！"); Say("newwin_d", "噗咿…明天再看…", "天黑了…關掉吧");
            Say("hi", "噗咿！" + me + "！👋"); Say("hi_d", "噗咿…（揮手）");
            Say("wake", "噗咿？醒了！"); Say("wake_d", "噗咿…還在睡…");
            Say("dizzy", "噗咿咿咿…@@"); Say("dizzy_d", "暈…睡覺…");
            Say("dizzy_ok", "噗咿！好了！"); Say("dizzy_ok_d", "好了…回家…");
            Say("pat10", "今天第 {n} 次！噗咿！"); Say("pat10_d", "第 {n} 次…晚安…");
            Say("levelup", "好感度 Lv{n}！拿到「{u}」！噗咿！"); Say("levelup_d", "Lv{n}…「{u}」…明天戴");
            Say("missed", "好久沒摸了…噗咿…🥺"); Say("missed_d", "好久沒摸了…");
            Say("hover", "噗咿？摸摸？");
            Say("seek", "噗咿？那是什麼？"); Say("seek_lost", "噗咿…不見了"); Say("seek_got", "抓到了！噗咿！");
            Say("drag", "噗咿咿咿！"); Say("throw", "噗咿～～～！");
            Say("shelf_in", "噗咿～回土裡囉"); Say("shelf_in_d", "噗咿…回土裡睡覺…");
            Say("shelf_out", "（從土裡探頭）噗咿？", "（土裡）噗咿～"); Say("shelf_out_d", "（土裡）…天黑了耶？");
            Say("ball_go", "噗咿！球！", "嘿咻！搬回去！", "大家來搬！"); Say("ball_go_d", "最後一顆…");
            Say("ball_catch", "嘿咻嘿咻～還你！", "搬回來了！噗咿！", "噗咿！好重！"); Say("ball_catch_d", "搬回來了…回家…");
            Say("ball_end", "不玩了？噗咿～"); Say("ball_end_d", "不玩了…睡覺…");
            Say("ball_far", "球太遠了…噗咿…");
            Say("back", "噗咿！回來了！"); Say("back_d", "噗咿…回來了…");
            Say("share_end", "分享完了？噗咿！");
            Say("welcome", "噗咿！你回來了！"); Say("welcome_d", "回來了…是要回家了嗎？");
            Say("rest", "花都枯了…起來喝口可樂、走一走 🥤"); Say("rest_d", "花都枯了…喝完可樂就下班吧 🥤");
            Say("night_on", "天黑了…噗咿…回土裡睡覺"); Say("night_off", "噗咿！早安！太陽出來了 ☀");
            Say("sleep", "噗咿…zZ"); Say("sleep_d", "晚安…噗咿…");
            Say("jump", "嘿咻！"); Say("nojump", "噗咿…跳不上去");
            Say("errors", "噗咿！有 {n} 個錯誤！"); Say("errors_d", "{n} 個錯誤…明天再修…");
            Say("errors_ok", "錯誤搬光了！噗咿！"); Say("errors_ok_d", "修好了…回家吧");
            Say("typing", "嘿咻嘿咻！打好快！", "噗咿！加油！", "手指跑好快～噗咿！"); Say("typing_d", "快打完…回家…");
            Say("done", "噗咿！{who} 做完了！"); Say("done_d", "{who} 做完了…回家吧");
            Say("wait", "{who} 在等你回答！噗咿！"); Say("wait_d", "{who} 在等你…回完回家");
            Say("ask", "{who} 有問題！噗咿？"); Say("ask_d", "{who} 在問你…回完回家");
            Say("stuck_tool", "{who} 停在「{tool}」{n} 分鐘了！要按允許嗎？噗咿？"); Say("stuck_tool_d", "{who} 停了 {n} 分鐘…按一下回家");
            Say("stuck", "{who} 不動了…{n} 分鐘！噗咿！"); Say("stuck_d", "{who} 卡 {n} 分鐘…看一下回家");
            Say("unstuck", "{who} 動了！噗咿！"); Say("unstuck_d", "{who} 動了…");
            Say("tag", "上版成功！噗咿！🎉"); Say("tag_dev", "測試機成功！嘿咻！"); Say("tag_prod", "正式機成功！大家噗咿！🎉"); Say("tag_d", "上版了…回家睡覺");
            Say("late23", "好晚了…噗咿…🌙"); Say("late12", "吃飯了沒？果汁！"); Say("late15", "點心時間～花蜜！");
            Say("late_d", "天黑了…回家吧"); Say("late_dd", "好晚…睡覺！");
            Say("g_late", "這麼晚…" + me + "陪你 🌙"); Say("g_morning", "噗咿！早安！"); Say("g_noon", "噗咿！午安～吃了沒？");
            Say("g_evening", "噗咿～晚上了"); Say("g_day", "噗咿！" + me + "出來了！"); Say("g_d", "天黑了…你怎麼還在？噗咿…");
            Say("app_browser", "噗咿？在看什麼？"); Say("app_code", "寫 code！噗咿！"); Say("app_excel", "好多格子…噗咿？");
            Say("app_ppt", "簡報～噗咿！"); Say("app_word", "寫字字～"); Say("app_chat", "有人找你？噗咿？"); Say("app_files", "找東西？一起搬！");
            Say("app_other", "噗咿？這是什麼？");
            Say("app_code_d", "還在寫…回家吧"); Say("app_chat_d", "明天再回…"); Say("app_office_d", "明天再做…噗咿"); Say("app_other_d", "回家…噗咿…");
            Say("s_birthday", "生日快樂！噗咿！🎂", "大家搬蛋糕來了！嘿咻！"); Say("s_cny", "新年快樂！噗咿！🧧"); Say("s_xmas", "聖誕快樂！噗咿！🎄");
            Say("s_newyear", "新年快樂！噗咿！✨"); Say("s_halloween", "不給糖就搗蛋！噗咿！🎃"); Say("s_friday", "星期五！噗咿！", "快放假了～嘿咻！");
            Say("morning", me + "！噗咿！"); Say("goodnight", "噗咿…晚安…（鑽回土裡）", "晚安～噗咿");
            Say("nag", "噗咿…下班了…", "回家吧…噗咿", "天黑了…回土裡…");
            Say("react", "噗咿？", "噗咿！", "咿？");
        }

        // ---------------- 紅皮克敏：勇敢、有點衝，會冒小火花 ----------------
        static Pal PikRed()
        {
            Pal p = PikBase("pkred", "紅皮克敏", 0xE8312F, 0xB4201F, 0xFF7A6A, 0x7A1414);
            p.Speed = 75; p.Move = "march";
            p.PikLines("小紅");
            p.Say("talk", "噗咿！", "嘿！誰要打架！", "小紅不怕火！", "衝啊！噗咿！", "嘿咻！我最勇敢", "要喝可樂嗎？噗咿！🥤");
            p.Say("tickle", "嘿！別鬧！噗咿！", "噗咿！（冒火）", "再摸我就生氣囉！"); p.Say("tickle_d", "噗咿…不鬧了…");
            p.Say("hi", "噗咿！小紅！👋（握拳）");
            p.Say("seek", "嘿！那是什麼！衝！");
            p.Say("ball_go", "球！小紅來！", "衝啊！搬回去！");
            p.Shared();
            return p;
        }

        // ---------------- 黃皮克敏：大耳朵、最愛被丟得高高的、會放小電花 ----------------
        static Pal PikYellow()
        {
            Pal p = PikBase("pkyellow", "黃皮克敏", 0xF6C51E, 0xD49A0C, 0xFFE47A, 0x8A5A06);
            p.Speed = 70; p.Move = "hop";
            p.PikLines("小黃");
            p.Say("talk", "噗咿！", "丟我丟我！要飛高高！", "耳朵動動～噗咿", "滋滋～（電電）", "嘿咻！小黃最高！", "要喝可樂嗎？噗咿！🥤");
            p.Say("tickle", "噗咿咿！癢！（電電）", "滋滋滋～嘻嘻", "再丟一次！"); p.Say("tickle_d", "噗咿…不鬧了…");
            p.Say("drag", "噗咿！要丟了嗎！要丟了嗎！"); p.Say("throw", "噗咿～～～飛高高！");
            p.Say("hi", "噗咿！小黃！👋（耳朵揮揮）");
            p.Shared();
            return p;
        }

        // ---------------- 藍皮克敏：冷靜、會游泳、吐泡泡 ----------------
        static Pal PikBlue()
        {
            Pal p = PikBase("pkblue", "藍皮克敏", 0x2E6BE6, 0x1F4CB8, 0x6E9CFF, 0x14286E);
            p.Speed = 62; p.Move = "swim";
            p.PikLines("小藍");
            p.Say("talk", "噗咿。", "咕嚕咕嚕～", "小藍會游泳喔", "不要急，慢慢來", "水裡很舒服…噗咿", "要喝可樂嗎？噗咿 🥤");
            p.Say("tickle", "咕嚕咕嚕！（吐泡泡）", "噗咿～好癢", "嘻…泡泡～"); p.Say("tickle_d", "咕嚕…睡覺…");
            p.Say("hi", "噗咿。小藍。👋");
            p.Shared();
            return p;
        }
    }

    // ================= 一隻皮克敏 =================
    partial class Pet
    {
        string pikAct = "";              // 皮克敏專屬動作（state == "pik"）
        double pikT, pikTarget = double.NaN, flameT, sparkT;
        int pikIdx;
        public bool PikCarrying;         // 串場：一起搬東西
        public string PikHold = "";      // 手上拿的（午餐水果、果汁）
        int pikStage = -1; string pikStageDay = "";
        public bool PikGoing { get { return state == "pik" && pikAct == "goto"; } }

        // 頭上的葉子／花苞／花：每天重新從葉子開始，喝花蜜長大（記在資料夾，一天一份）
        public int PikStage
        {
            get
            {
                string today = DateTime.Now.ToString("yyyy-MM-dd");
                if (pikStage < 0 || pikStageDay != today)
                {
                    pikStage = 0; pikStageDay = today;
                    try
                    {
                        string[] a = File.ReadAllText(Path.Combine(World.DataDir, "pikstage-" + P.Id + ".txt")).Trim().Split(' ');
                        int s; if (a.Length == 2 && a[0] == today && int.TryParse(a[1], out s)) pikStage = Math.Max(0, Math.Min(2, s));
                    }
                    catch { }
                }
                return pikStage;
            }
        }
        public void PikGrow()
        {
            int s = Math.Min(2, PikStage + 1);
            pikStage = s;
            try { Directory.CreateDirectory(World.DataDir); File.WriteAllText(Path.Combine(World.DataDir, "pikstage-" + P.Id + ".txt"), pikStageDay + " " + s); } catch { }
        }
        public void PikSetStage(int s) { pikStage = Math.Max(0, Math.Min(2, s)); pikStageDay = DateTime.Now.ToString("yyyy-MM-dd"); }
        string[] PikTop() { int s = PikStage; return A(s == 2 ? "FLOWER" : (s == 1 ? "BUD" : "LEAF")); }

        string pendAct; double pendDur, pendTarget = double.NaN;   // 在空中被叫去做事：落地再做（不然會停在半空中）
        public void PikDo(string act, double dur)
        {
            if (state == "air" || state == "fling" || state == "drag") { pendAct = act; pendDur = dur; pendTarget = pikTarget; return; }
            pikAct = act; pikT = 0; SetState("pik", dur);
            if (act == "punch") flameT = Math.Max(flameT, 1.0);
        }
        public void PikGoto(double tx, string act, double dur) { pikTarget = tx; PikDo(act, dur); }
        public void PikFollow(int idx, double dur) { pikIdx = idx; PikDo("follow", dur); }
        public void PikSpark(double sec) { sparkT = Math.Max(sparkT, sec); }
        public void PikFlame(double sec) { flameT = Math.Max(flameT, sec); }
        public void PikPop(string text)
        {
            // 從土裡被拔出來：噗！
            Jump(dir * 40 * k, -380 * k); Burst(6); Say(text ?? Pick(new string[] { "噗！", "噗！噗咿！", "（拔出來）噗咿！" }), 1.2);
        }

        // 連點三下
        void PikCombo()
        {
            Say(L("tickle"), 1.8);
            if (!Grounded() || state == "dizzy") return;
            if (Is("pkred")) { PikDo("punch", 1.2); }
            else if (Is("pkyellow")) { sparkT = 1.4; Jump(dir * 30 * k, -520 * k); }
            else { SetState("idle", 1.6); for (int i = 0; i < 5; i++) Mark(5); }
        }

        void PikSignature()
        {
            if (!Grounded()) return;
            if (Is("pkred")) { PikDo("punch", 1.6); Say(Pick(new string[] { "嘿！嘿！看我的！", "衝啊！噗咿！", "（冒火）嘿！" }), 1.4); }
            else if (Is("pkyellow")) { sparkT = 2.2; Jump(dir * 60 * k, -820 * k); Say(Pick(new string[] { "噗咿～～飛高高！", "滋滋～跳！" }), 1.4); }
            else { PikDo("swim", 3.4); Say(Pick(new string[] { "咕嚕咕嚕～游泳！", "小藍會游泳喔～" }), 1.6); }
        }

        bool PikAct(string a)
        {
            switch (a)
            {
                case "whistle": w.Whistle(); return true;
                case "pikfight": if (Grounded()) { PikDo("punch", 1.6); Say("嘿！嘿！", 1.2); } return true;
                case "pikjump": if (Grounded()) { sparkT = 2.2; Jump(dir * 60 * k, -820 * k); Say("噗咿～～！", 1.2); } return true;
                case "pikswim": if (Grounded()) { PikDo("swim", 3.4); Say("咕嚕咕嚕～", 1.2); } return true;
                case "pikmill": if (Grounded()) { PikDo("mill", 3.2); Say("噗咿？", 0.8); } return true;
            }
            return false;
        }

        void PikDecide(double r, Rectangle wa)
        {
            if (r < .16) SetState("idle", R(1.5, 3.5));
            else if (r < .42) { dir = rnd.NextDouble() < .5 ? -1 : 1; SetState("walk", R(2.5, 6)); }
            else if (r < .52) { if (!JumpToPlatform()) Hop(); }
            else if (r < .60) PikDo("mill", R(2.5, 4));                         // 沒事做：原地繞來繞去
            else if (r < .66) PikSignature();
            else if (r < .70) Hug(L("hugs"), 2.2);
            else if (r < (Night ? .75 : .73)) Knock(L("knock"), "ambient");
            else if (r < .76 && lateCd <= 0 && LateLine() != null) LateTick();
            else if (r < .79 && SeasonLine() != null) { Say(SeasonLine(), 3); SetState("idle", 3); }
            else if (r < .90) { SetState("idle", 2.5); Say(L("talk"), 2.2); }
            else { dir = -dir; SetState("walk", R(2, 5)); }
        }

        int PikEdge(bool right)
        {
            double brave = Is("pkred") ? 0.7 : (Is("pkyellow") ? 0.6 : 0.4);
            if (rnd.NextDouble() > brave) { dir = -dir; return 1; }
            x += dir * 4 * k;
            if (Is("pkyellow")) { Jump(dir * 120 * k, -560 * k); sparkT = 1.2; Say("噗咿～！", 0.8); }
            else { Jump(dir * 130 * k, -300 * k); Say(Is("pkred") ? "嘿！" : "噗咿。", 0.8); }
            return 2;
        }

        bool PikLanded(bool wasRolling)
        {
            if (pendAct != null) { string a = pendAct; pendAct = null; pikTarget = pendTarget; SetState("idle", 0.1); PikDo(a, pendDur); return true; }
            if (Is("pkyellow") && lastLandVy > 700 * k) { SetState("pose", 1.2); poseKind = "photo"; Say(Pick(new string[] { "噗咿！好高！再一次！", "再丟一次！噗咿！" }), 1.6); sparkT = 1; return true; }
            if (Is("pkred") && lastLandVy > 900 * k) { PikDo("punch", 1.0); Say("嘿！沒事！", 1.2); return true; }
            return false;
        }

        bool PikLand(string a)
        {
            if (a == "pksprout") { PikDo("sprout", R(0.5, 0.8)); return true; }
            return false;
        }

        // 被拿起來丟：黃皮克敏最愛，飛得更高
        void PikThrown(ref double tvx, ref double tvy)
        {
            if (!Is("pkyellow")) return;
            tvy = tvy * 1.3 - 260 * k;
            sparkT = 1.6;
        }

        void PikReact(string why)
        {
            if (Is("pkred")) PikDo("punch", 1.2);
            else if (Is("pkyellow")) { sparkT = 1; Jump(0, -300 * k); }
            else { SetState("idle", 2); Mark(4); }
        }

        string PikLine(string kind)
        {
            switch (kind)
            {
                case "goal": return Is("pkyellow") ? "噗咿！飛進去了！再一次！🏀" : (Is("pkred") ? "嘿！進球！🏀" : "噗咿。進球～🏀");
                case "cheer": return Pick(new string[] { "噗咿！", "噗咿噗咿！", "嘿咻！" });
                case "miss": return Is("pkyellow") ? "噗咿～差一點！再丟一次！" : "噗咿…沒進…";
            }
            return "噗咿！";
        }

        // ---------- 球：大家把球搬回來給你 ----------
        void PikBall()
        {
            w.HoldBall(this);
            Point c = Cursor.Position;
            Rectangle wa = w.WA(Cx, y + SH / 2.0);
            PikGoto(Clamp(c.X, wa.Left + SW, wa.Right - SW), "carryball", 3.2);
            Say(Pick(new string[] { "嘿咻嘿咻！", "噗咿！搬回去！", "嘿咻～" }), 1.4);
        }

        bool PikStep(double dt)
        {
            if (flameT > 0) flameT -= dt;
            if (sparkT > 0) sparkT -= dt;
            if (P.Id == "pkblue" && state == "walk" && rnd.NextDouble() < dt * 0.3) Mark(5);
            if (state != "pik") return false;
            pikT += dt;
            switch (pikAct)
            {
                case "sprout":
                    if (t < 0) PikPop(null);
                    return true;
                case "dig":
                    return true;   // 世界控制何時收回櫃子
                case "follow":
                    {
                        Point c = Cursor.Position;
                        Pet lead = w.Lead();
                        double side = (lead != null ? lead.Cx : Cx) < c.X ? -1 : 1;   // 大家排在游標同一邊，一列
                        double tx = c.X + side * (pikIdx + 1) * SW * 1.25;
                        if (Math.Abs(tx - Cx) > 5) { dir = tx > Cx ? 1 : -1; if (MoveOnGround(dt, 170 * k)) return true; }
                        if (rnd.NextDouble() < dt * 0.4) Say(Pick(new string[] { "噗咿！", "嘿咻！" }), 0.7);
                        if (t < 0) SetState("idle", 1);
                        return true;
                    }
                case "march": case "carry": case "carryball": case "goto":
                    {
                        double sp = pikAct == "march" ? 120 : (pikAct == "goto" ? 150 : 55);
                        if (!double.IsNaN(pikTarget) && Math.Abs(pikTarget - Cx) > SW * 0.5 && pikAct != "carryball") sp = 150;   // 還沒到位置：先跑過去
                        if (!double.IsNaN(pikTarget) && Math.Abs(pikTarget - Cx) > 3)
                        {
                            dir = pikTarget > Cx ? 1 : -1;
                            double step = Math.Min(Math.Abs(pikTarget - Cx), sp * k * dt);
                            double nx = x + dir * step;
                            if (w.Inside(nx + (dir > 0 ? SW : 0), y + SH / 2.0)) x = nx;
                        }
                        if (pikAct == "carryball" && (t < 0 || Math.Abs(pikTarget - Cx) <= 3))
                        {
                            if (w.Holder == this) { w.ReleaseBall(Cx, y + (P.HeadTop - 2) * S, 0, 0); KickBallToCursor(0.55); }
                            Say(L("ball_catch"), 1.6);
                            SetState("idle", 1);
                            return true;
                        }
                        if (pikAct == "carryball" && rnd.NextDouble() < dt * 0.5 && Bt <= 0) Say("嘿咻嘿咻！", 0.8);
                        if (t < 0) SetState("idle", InScene ? 30 : 1);
                        return true;
                    }
                case "swim":
                    x += dir * 38 * k * dt;
                    if (!w.Inside(x + (dir > 0 ? SW : 0), y + SH / 2.0)) dir = -dir;
                    if (supH != IntPtr.Zero && (Cx < supL + 4 || Cx > supR - 4)) dir = -dir;
                    if (rnd.NextDouble() < dt * 4) Mark(5);
                    if (t < 0) SetState("idle", InScene ? 30 : 1);
                    return true;
                case "drown":
                    if (rnd.NextDouble() < dt * 3) Mark(4);
                    if (t < 0) SetState("idle", InScene ? 30 : 1);
                    return true;
                case "mill":
                    if (Math.Floor(pikT * 1.4) != Math.Floor((pikT - dt) * 1.4)) dir = -dir;
                    MoveOnGround(dt, 30 * k);
                    if (t < 0) SetState("idle", 1);
                    return true;
                case "drink":
                    if (pikT >= 0.9 && pikT - dt < 0.9) { PikGrow(); Burst(10); AddHeart(); Say(PikStage == 2 ? "噗咿！開花了！🌼" : "噗咿！（長大了）", 1.8); }
                    if (t < 0) { SetState("idle", InScene ? 30 : 1); if (!InScene) Jump(0, -300 * k); }
                    return true;
                default:   // punch／lift／tug／worry／throwup／cheer：站著做動作
                    if (pikAct == "worry" && rnd.NextDouble() < dt * 1.5) Mark(4);
                    if (t < 0) SetState("idle", InScene ? 30 : 1);
                    return true;
            }
        }

        double PikBob()
        {
            if (state == "dance") return Math.Abs(Math.Sin(anim * 8)) * 5 * k;
            if (Is("pkyellow") && (state == "walk" || state == "goto")) return Math.Abs(Math.Sin(anim * 9)) * 3 * k;   // 蹦蹦跳
            if (state == "pik" && pikAct == "mill") return Math.Abs(Math.Sin(anim * 7)) * 2 * k;
            return 0;
        }

        // ---------- 畫 ----------
        string[] PikHead(string face)
        {
            string[] h = (string[])A("HEAD").Clone();
            char[] r6 = h[6].ToCharArray(), r7 = h[7].ToCharArray(), r8 = h[8].ToCharArray(), r9 = h[9].ToCharArray(), r10 = h[10].ToCharArray();
            int[] eyes = { 4, 11 };
            foreach (int e in eyes)
            {
                if (face == "SLEEPY") { r6[e] = r6[e + 1] = r6[e + 2] = 'r'; r7[e] = r7[e + 1] = r7[e + 2] = 'o'; }
                else if (face == "HAPPY") { r6[e] = 'r'; r6[e + 1] = 'o'; r6[e + 2] = 'r'; r7[e] = 'o'; r7[e + 1] = 'r'; r7[e + 2] = 'o'; }
                else if (face == "DIZZY") { r6[e] = 'o'; r6[e + 1] = 'r'; r6[e + 2] = 'o'; r7[e] = 'r'; r7[e + 1] = 'o'; r7[e + 2] = 'r'; }
                else if (face == "WORRY") { r6[e] = 'W'; r6[e + 1] = 'W'; r6[e + 2] = 'W'; r7[e + 1] = 'K'; }
                else if (face == "LOOKUP") { r6[e + 1] = 'K'; r7[e + 1] = 'W'; }
            }
            if (Is("pkred")) { r8[8] = 'n'; r8[9] = 'n'; r9[8] = 'N'; r9[9] = 'N'; }
            if (Is("pkblue")) { r9[8] = 'M'; r9[9] = 'M'; r10[7] = 'M'; r10[10] = 'M'; if (face == "HAPPY") { r9[7] = 'M'; r9[10] = 'M'; r10[7] = 'r'; r10[10] = 'r'; } }
            h[6] = new string(r6); h[7] = new string(r7); h[8] = new string(r8); h[9] = new string(r9); h[10] = new string(r10);
            if (Is("pkyellow"))
            {
                // 尖尖的大耳朵（往外往上）；興奮時耳朵翹高一點
                bool up = sparkT > 0 || (state == "pik" && pikAct == "cheer") || (state == "pose" && Step2(4));
                int[][] ear = up
                    ? new int[][] { new int[] { 2, 0, 'o' }, new int[] { 3, 0, 'o' }, new int[] { 3, 1, 'e' }, new int[] { 3, 2, 'o' }, new int[] { 4, 0, 'o' }, new int[] { 4, 1, 'e' }, new int[] { 4, 2, 'e' }, new int[] { 4, 3, 'e' }, new int[] { 5, 1, 'o' }, new int[] { 5, 2, 'o' } }
                    : new int[][] { new int[] { 3, 0, 'o' }, new int[] { 4, 0, 'o' }, new int[] { 4, 1, 'e' }, new int[] { 4, 2, 'o' }, new int[] { 5, 0, 'o' }, new int[] { 5, 1, 'e' }, new int[] { 5, 2, 'e' }, new int[] { 5, 3, 'e' }, new int[] { 6, 1, 'o' }, new int[] { 6, 2, 'o' } };
                foreach (int[] e in ear)
                {
                    char[] row = h[e[0]].ToCharArray();
                    row[e[1]] = (char)e[2]; row[17 - e[1]] = (char)e[2];
                    h[e[0]] = new string(row);
                }
            }
            return h;
        }

        Fr FramePik()
        {
            bool sleep = state == "sleep", hug = state == "hug";
            bool nightIdle = Night && state == "idle" && !InScene && !HoldingFood();
            string act = state == "pik" ? pikAct : "";
            string face = null;
            if (sleep || nightIdle || (state == "pik" && act == "dig")) face = "SLEEPY";
            else if (hug || state == "dance" || act == "drink" || act == "cheer" || (state == "pose" && poseKind == "photo")) face = "HAPPY";
            else if (state == "dizzy" || act == "drown") face = "DIZZY";
            else if (act == "worry") face = "WORRY";
            else if (act == "lift" || act == "carry" || act == "carryball" || act == "tug") face = "LOOKUP";
            List<string> rows = new List<string>(PikTop());
            rows.AddRange(A("STEM"));
            rows.AddRange(PikHead(face));
            bool armsUp = state == "air" || state == "fling" || state == "drag" || state == "kick" || state == "catch" || hug || (state == "dance" && Step2(4)) || (state == "wave" && Step2(4))
                || (state == "pose" && poseKind == "photo") || act == "lift" || act == "carry" || act == "carryball" || act == "tug" || act == "cheer" || act == "throwup" || act == "drown" || (act == "punch" && Step2(6));
            rows.AddRange(A(armsUp ? "ARMS_UP" : "BODY"));
            bool sit = sleep || nightIdle;
            bool moving = state == "walk" || state == "seek" || state == "fetch" || state == "hide" || state == "goto" || act == "follow" || act == "march" || act == "carry" || act == "carryball" || act == "goto" || act == "mill";
            bool step = (moving && Step2(Is("pkyellow") ? 9 : 8)) || (state == "dance" && Step2(4));
            if (sit) rows.AddRange(A("LEGS_SIT"));
            else rows.AddRange(A(step ? "LEGS_B" : "LEGS_A"));
            string[] all = rows.ToArray();
            Fr f;
            if (act == "sprout" || act == "dig")
            {
                // 埋在土裡：只露出頭頂的葉子和一點點頭
                int show = PikTop().Length + A("STEM").Length + 3;
                if (act == "dig") show = Math.Max(PikTop().Length + 1, (int)Math.Round(all.Length - pikT / 0.8 * (all.Length - PikTop().Length - 1)));
                string[] cut = new string[Math.Min(show, all.Length)];
                Array.Copy(all, cut, cut.Length);
                f = F(cut); f.Acc = false;
                return f;
            }
            if (act == "swim" || act == "drown")
            {
                // 泡在水裡：下半身沒入水面
                string[] cut = new string[all.Length - 5];
                Array.Copy(all, cut, cut.Length);
                f = F(cut); f.Top = act == "drown" ? 3 + (Step2(5) ? 1 : 0) : 2;
                return f;
            }
            f = F(all);
            if (sit) f.AccDy = 1;
            if (rolling) { f.Rot = (int)Math.Floor(anim * 14) % 4; f.Acc = false; }
            return f;
        }

        static readonly string[] PK_FLAME = { "..Y..", ".YOY.", "YOOOY", ".OOO." };
        static readonly string[] PK_SPARK = { "Y.", ".Y", "Y.", ".Y" };
        static readonly string[] PK_PUDDLE_FRONT = { ".bBBBBBBBBBBBBb.", "bBBbbBBBBBbbBBBb" };
        static readonly string[] PK_STRAW = { ".G.G.", "SSSSS", "SYSYS", ".SSS.", "..S.." };
        static readonly string[] PK_BANANA = { "....1", "..YY1", ".YYY.", "YYY..", ".Y..." };
        static readonly string[] PK_GRAPE = { "..G..", ".vv..", "vVvv.", ".vVv.", "..v.." };
        static readonly string[] PK_JUICE = { ".G..", "WWWW", "WOOW", "WOOW", ".WW." };
        static readonly string[] PK_MOUND = { "....1111111111....", "..11222222222211..", ".1222222222222221." };

        void DrawPikBehind(Graphics g, Fr f, int bx, int by, int ps, bool fx)
        {
            string act = state == "pik" ? pikAct : "";
            if (act == "swim" || act == "drown")
                using (SolidBrush wb = new SolidBrush(Color.FromArgb(Night ? 120 : 140, 90, 168, 232)))
                    g.FillEllipse(wb, bx - 4 * ps, by + 12 * ps, 20 * ps, 5 * ps);
        }

        void DrawPikFront(Graphics g, Fr f, int bx, int by, int ps, bool fx)
        {
            string act = state == "pik" ? pikAct : "";
            if (act == "sprout" || act == "dig") { DrawAt(g, PK_MOUND, -3, 13, bx, by, ps, fx, false, true); return; }
            if (act == "swim" || act == "drown") { DrawAt(g, PK_PUDDLE_FRONT, -2, 14 - (Step2(3) ? 1 : 0) * 0, bx, by, ps, Step2(3), false, false); }
            if (f.Rot != 0 || f.Fy) return;
            int top = f.Top + 16 - f.Rows.Length;   // 圖的第一列在框的第幾列
            int headRow = top + PikTop().Length + A("STEM").Length;
            if (Is("pkred") && (flameT > 0 || act == "punch") && Step2(10)) DrawAt(g, PK_FLAME, 9.5, headRow - 1, bx, by, ps, fx, false, true);
            if (Is("pkyellow") && sparkT > 0)
            {
                bool flip = Step2(12);
                DrawAt(g, PK_SPARK, flip ? -4 : -5, headRow + 3, bx, by, ps, false, false, true);
                DrawAt(g, PK_SPARK, flip ? 14 : 15, headRow + 3, bx, by, ps, false, false, true);
            }
            if ((act == "carryball" || pendAct == "carryball") && w.Holder == this)
            {
                string[] ball = w.BallKind == "baseball" ? BALLART : TBALL;
                DrawAt(g, ball, 4, headRow - 3, bx, by, ps, fx, false, true);
            }
            if (PikHold != "") DrawAt(g, PikHoldArt(PikHold), 9.5, P.BodyTop - 2 + f.AccDy, bx, by, ps, fx, false, true);
        }

        string[] PikHoldArt(string what)
        {
            switch (what)
            {
                case "straw": return PK_STRAW;
                case "banana": return PK_BANANA;
                case "grape": return PK_GRAPE;
            }
            return PK_JUICE;
        }

        string PikFruit() { return Is("pkred") ? "straw" : (Is("pkyellow") ? "banana" : "grape"); }

        string PikLunchLine(string phase)
        {
            string fruit = Is("pkred") ? "草莓" : (Is("pkyellow") ? "香蕉" : "葡萄");
            if (phase == "start") return "噗咿！午餐！" + fruit + "汁 🔔";
            if (phase == "nap") return "吃飽了…噗咿…zZ";
            if (phase == "end") return "噗咿！回來工作！";
            return Pick(new string[] { fruit + "！好甜！噗咿！", "果汁～咕嘟咕嘟", "嘿咻！再一口！" });
        }

        void DrawPikLunch(Graphics g, Fr f, int bx, int by, int ps, bool fx, int bite)
        {
            if (PikHold != "") return;   // 串場已經拿著水果了
            DrawAt(g, PikHoldArt(PikFruit()), 9.5, P.BodyTop - 2 + bite + f.AccDy, bx, by, ps, fx, false, true);
            DrawAt(g, PK_JUICE, -2.5, P.BodyTop - 1 + f.AccDy, bx, by, ps, fx, false, true);
        }

        int PikShelfRows() { return 16 + P.TopRows + 1; }

        // 櫃子裡：站在土上；紅的握拳冒火、黃的耳朵動動跳一下、藍的吐泡泡；晚上坐著睡
        void DrawPikShelf(Graphics g, int fx, int bx, int by, int ps, bool flip, double tt, bool blink, Rectangle cell)
        {
            string face = null;
            bool up = false;
            int hop = 0;
            if (Night) face = "SLEEPY";
            else if (Is("pkred") && (tt % 7) < 1.2) { up = Step2(6); face = "LOOKUP"; }
            else if (Is("pkyellow") && (tt % 5) < 0.5) { hop = -ps * 2; up = true; face = "HAPPY"; }
            else if (blink) face = "SLEEPY";
            double keepSpark = sparkT;
            if (Is("pkyellow") && !Night && (tt % 5) < 0.9) sparkT = 1;   // 耳朵翹起來
            List<string> rows = new List<string>(PikTop());
            rows.AddRange(A("STEM"));
            rows.AddRange(PikHead(face));
            rows.AddRange(A(up ? "ARMS_UP" : "BODY"));
            rows.AddRange(A(Night ? "LEGS_SIT" : "LEGS_A"));
            sparkT = keepSpark;
            string[] r = rows.ToArray();
            int dy = Night ? 1 : 0;
            DrawPix(g, r, bx - (r[0].Length - 12) / 2 * ps, by + (16 - r.Length) * ps + hop, ps, flip, false, true);
            DrawAccessories(g, bx, by + hop, ps, flip, dy, face == null);
            int headRow = 16 - r.Length + PikTop().Length + A("STEM").Length;
            if (Is("pkred") && !Night && (tt % 7) < 1.2 && Step2(10)) DrawAt(g, PK_FLAME, 9.5, headRow - 1, bx, by, ps, flip, false, true);
            if (Is("pkyellow") && !Night && (tt % 5) < 0.9)
            {
                DrawAt(g, PK_SPARK, -5, headRow + 3, bx, by + hop, ps, false, false, true);
                DrawAt(g, PK_SPARK, 15, headRow + 3, bx, by + hop, ps, false, false, true);
            }
            if (Is("pkblue") && !Night)
                using (Pen bp = new Pen(Color.FromArgb(190, 150, 215, 255), Math.Max(1f, ps * 0.35f)))
                    for (int i = 0; i < 3; i++)
                    {
                        double ph = (tt * 0.5 + i / 3.0) % 1;
                        float rr = (float)(ps * (0.5 + ph * 0.9)), px = fx + (float)(Math.Sin(ph * 9 + i) * ps) + (flip ? -3 : 3) * ps, py = by + (headRow + 7) * ps - (float)(ph * 10 * ps);
                        if (py > cell.Y + rr) g.DrawEllipse(bp, px - rr, py - rr, 2 * rr, 2 * rr);
                    }
            if (w.Lunch) DrawAt(g, PikHoldArt(PikFruit()), 9.5, P.BodyTop - 2, bx, by, ps, flip, false, true);
        }
    }

    // ================= 公仔櫃：土、大格的休息花 =================
    partial class ShelfForm
    {
        public bool Pik;                     // 皮克敏一櫃：格子底下是土和草，大格種一朵休息花

        // 每一格底下一層土＋小草（公仔站在土上）
        void DrawSoil(Graphics g, RectangleF inner, bool tall)
        {
            GraphicsState st = g.Save();
            g.SetClip(inner);
            float soil = tall ? inner.Height * 0.16f : inner.Height * 0.09f;
            RectangleF band = new RectangleF(inner.X, inner.Bottom - soil, inner.Width, soil + 1);
            Color s1 = Night ? C(0x4A3828) : C(0x8A5E3A), s2 = Night ? C(0x2E2218) : C(0x5E3E24);
            using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(band.X, band.Y - 1, band.Width, band.Height + 2), s1, s2, 90f)) g.FillRectangle(lb, band);
            // 土粒
            Random r = new Random(tall ? 4 : 9);
            using (SolidBrush pb = new SolidBrush(Color.FromArgb(70, 30, 18, 8)))
                for (int i = 0; i < (tall ? 26 : 10); i++)
                    g.FillRectangle(pb, band.X + (float)r.NextDouble() * band.Width, band.Y + 2 + (float)r.NextDouble() * (band.Height - 3), Math.Max(1f, U * 0.5f), Math.Max(1f, U * 0.5f));
            // 草
            using (Pen gp = new Pen(Night ? C(0x3E6A3A) : C(0x5CB04A), Math.Max(1f, U * 0.45f)))
                for (int i = 0; i < (tall ? 14 : 7); i++)
                {
                    float gx = band.X + (float)((i + r.NextDouble() * 0.7) / (tall ? 14 : 7)) * band.Width, h = U * (1.2f + (float)r.NextDouble() * 1.4f);
                    g.DrawLine(gp, gx, band.Y + 1, gx - U * 0.4f, band.Y - h);
                    g.DrawLine(gp, gx + U * 0.6f, band.Y + 1, gx + U * 0.9f, band.Y - h * 0.8f);
                }
            g.Restore(st);
        }

        // 大格：花圃（土堆比較高）
        void DrawFlowerBed(Graphics g, Rectangle c)
        {
            RectangleF inner = new RectangleF(c.X, c.Y, c.Width, c.Height - plateH);
            float top = inner.Bottom - inner.Height * 0.16f;
            using (SolidBrush mb = new SolidBrush(Night ? C(0x3E2E20) : C(0x6E4A2C)))
                g.FillEllipse(mb, inner.X + inner.Width * 0.12f, top - inner.Height * 0.035f, inner.Width * 0.76f, inner.Height * 0.09f);
            using (SolidBrush hb = new SolidBrush(Color.FromArgb(50, 255, 230, 200)))
                g.FillEllipse(hb, inner.X + inner.Width * 0.25f, top - inner.Height * 0.03f, inner.Width * 0.4f, inner.Height * 0.025f);
        }

        // 休息花（像素畫）：越久沒休息越垂、花瓣一片一片掉、顏色變淡；休息回來會慢慢恢復、滴出花蜜
        void DrawRestFlower(Graphics g, Rectangle c, double t)
        {
            double wilt; int petals; double regrow; bool nectar; double bubble;
            w.FlowerLook(out wilt, out petals, out regrow, out nectar, out bubble);
            RectangleF inner = new RectangleF(c.X, c.Y, c.Width, c.Height - plateH);
            int u = Math.Max(2, TU);
            float soilTop = inner.Bottom - inner.Height * 0.16f - inner.Height * 0.03f;
            float baseX = inner.X + inner.Width / 2f;
            float L = inner.Height * 0.52f;
            double sway = wilt < 0.4 ? Math.Sin(t * 1.3) * 0.05 : 0;
            double theta = Math.Pow(Math.Min(1, wilt), 1.3) * 2.5 + sway;     // 0 直直的 → 約 143°（花整個垂下來）
            Color stemC = Mix(Night ? C(0x3E7A3A) : C(0x4CA040), C(0x8A7A48), Math.Max(0, (wilt - 0.5) / 0.5));
            Color leafC = Mix(Night ? C(0x4C8A44) : C(0x62BE4E), C(0x9A8A50), Math.Max(0, (wilt - 0.5) / 0.5));
            // 莖：沿著越來越彎的曲線一格一格點
            float x = baseX, y = soilTop;
            int n = (int)(L / u);
            PointF[] pts = new PointF[n + 1];
            pts[0] = new PointF(x, y);
            for (int i = 1; i <= n; i++)
            {
                double s = i / (double)n, q = Math.Max(0, Math.Min(1, (s - 0.42) / 0.58)), a = theta * q * q * (3 - 2 * q) * Math.Min(1, s / 0.42 * 0.25 + 0.75);   // 只有上半段彎：像真的花垂下來
                x += (float)(Math.Sin(a) * u); y -= (float)(Math.Cos(a) * u);
                pts[i] = new PointF(x, y);
            }
            // 垂下來的花不要超出格子：往旁邊的位移照比例收一點
            float maxDx = 0;
            foreach (PointF p in pts) maxDx = Math.Max(maxDx, p.X - baseX);
            float allowed = inner.Right - 6.5f * u - baseX;
            if (maxDx > allowed && maxDx > 0) for (int i = 0; i <= n; i++) pts[i] = new PointF(baseX + (pts[i].X - baseX) * allowed / maxDx, pts[i].Y);
            using (SolidBrush sb = new SolidBrush(stemC))
                foreach (PointF p in pts) g.FillRectangle(sb, Snap(p.X - u, u), Snap(p.Y, u), 2 * u, u);
            // 兩片葉子（枯了就垂下來）
            bool droop = wilt > 0.6;
            string[] leafR = droop ? new string[] { "LL...", ".LLL.", "..LLL" } : new string[] { "..LLL", ".LLL.", "LL..." };
            PointF lp1 = pts[Math.Max(1, n / 4)], lp2 = pts[Math.Max(1, n / 2)];
            PixelArt(g, leafR, lp1.X + u, lp1.Y - (droop ? 0 : 2 * u), u, leafC, false);
            PixelArt(g, leafR, lp2.X - 6 * u, lp2.Y - (droop ? 0 : 2 * u), u, leafC, true);
            // 掉在土上的花瓣
            Color petalC = Mix(Night ? C(0xD898B8) : C(0xFFA6CC), C(0xA8805A), Math.Max(0, Math.Min(1, (wilt - 0.25) / 0.65)));
            Color petalD = Mix(petalC, C(0x6A4A3A), 0.35);
            int fallen = 6 - petals;
            for (int i = 0; i < fallen; i++)
                using (SolidBrush fb = new SolidBrush(Mix(C(0xC89070), C(0x8A6A4A), i / 6.0)))
                    g.FillRectangle(fb, Snap(baseX + (i % 2 == 0 ? 1 : -1) * (3 + i * 2.2f) * u, u), Snap(soilTop + u * (1 + i % 2), u), 2 * u, u);
            // 花：六片圓圓的花瓣（有外框）＋中心，跟著莖的方向轉
            PointF head = pts[n];
            double tilt = theta;
            float R = 3.6f * u * (float)regrow;
            string[] petal = regrow < 0.75 ? new string[] { ".P.", "PPP", ".P." } : new string[] { ".PP.", "PPPP", "PPPP", ".PP." };
            Color outline = Mix(petalC, C(0x5A2A3A), 0.55);
            for (int pass = 0; pass < 2; pass++)
                for (int i = 0; i < 6; i++)
                {
                    if (i >= petals) continue;
                    double a = tilt + i * Math.PI / 3 - Math.PI / 2;
                    float px = head.X + (float)(Math.Cos(a) * R) - petal[0].Length * u / 2f, py = head.Y + (float)(Math.Sin(a) * R) - petal.Length * u / 2f;
                    if (pass == 0) { PixelArt(g, petal, px - u, py, u, outline, false); PixelArt(g, petal, px + u, py, u, outline, false); PixelArt(g, petal, px, py - u, u, outline, false); PixelArt(g, petal, px, py + u, u, outline, false); }
                    else { PixelArt(g, petal, px, py, u, petalC, false); PixelArt(g, new string[] { "P" }, px + u, py + u, u, Mix(petalC, Color.White, 0.45), false); }
                }
            Color cen = Mix(Night ? C(0xE0B840) : C(0xFFD84A), C(0x9A7A3A), Math.Max(0, (wilt - 0.4) / 0.6));
            string[] disc = { ".ccc.", "ccccc", "ccccc", "ccccc", ".ccc." };
            PixelArt(g, disc, head.X - 2.5f * u - u, head.Y - 2.5f * u, u, Mix(cen, C(0x7A4A10), 0.5), false);
            PixelArt(g, disc, head.X - 2.5f * u + u, head.Y - 2.5f * u, u, Mix(cen, C(0x7A4A10), 0.5), false);
            PixelArt(g, disc, head.X - 2.5f * u, head.Y - 2.5f * u - u, u, Mix(cen, C(0x7A4A10), 0.5), false);
            PixelArt(g, disc, head.X - 2.5f * u, head.Y - 2.5f * u + u, u, Mix(cen, C(0x7A4A10), 0.5), false);
            PixelArt(g, disc, head.X - 2.5f * u, head.Y - 2.5f * u, u, cen, false);
            // 小臉：精神好＝笑、快枯了＝難過、枯了＝閉眼
            string[] face = wilt >= 0.99 || Night ? new string[] { ".....", ".....", ".k.k.", ".....", "....." }
                : (wilt < 0.5 ? new string[] { ".....", ".k.k.", ".....", ".k.k.", "..k.." } : new string[] { ".....", ".k.k.", ".....", "..k..", ".k.k." });
            PixelArt(g, face, head.X - 2.5f * u, head.Y - 2.5f * u, u, C(0x5A3A1A), false);
            // 花蜜：恢復後在花心閃閃、往下滴
            if (nectar)
            {
                double ph = (t * 1.2) % 1;
                using (SolidBrush nb = new SolidBrush(Color.FromArgb(230, 255, 196, 40)))
                using (SolidBrush hl = new SolidBrush(Color.FromArgb(240, 255, 255, 220)))
                {
                    float dy = (float)(ph * (soilTop - head.Y - 4 * u));
                    g.FillEllipse(nb, head.X - u, head.Y + 2 * u + dy, 2 * u, 2.6f * u);
                    g.FillRectangle(hl, head.X - u / 2f, head.Y + 2.4f * u + dy, Math.Max(1, u / 2), Math.Max(1, u / 2));
                }
            }
        }

        static float Snap(float v, int u) { return (float)Math.Floor(v / u) * u; }
        static float Snap2(float v, int u) { return Math.Max(u, (float)Math.Round(v / u) * u); }
        static void PixelArt(Graphics g, string[] art, float x, float y, int u, Color c, bool flip)
        {
            using (SolidBrush b = new SolidBrush(c))
                for (int r = 0; r < art.Length; r++)
                    for (int i = 0; i < art[r].Length; i++)
                        if (art[r][flip ? art[r].Length - 1 - i : i] != '.') g.FillRectangle(b, Snap(x, u) + i * u, Snap(y, u) + r * u, u, u);
        }
    }

    // ================= World：休息花、吹哨子、皮克敏的串場 =================
    partial class World
    {
        public bool PikLineup { get { return lineup == Pal.Pikmin; } }
        public static double TestIdle;      // 測試用（DESKPALS_ISOLATED）：假裝鍵盤滑鼠閒置了幾秒

        double flowerStart = double.NaN;          // 這一段連續使用從哪時開始（真的休息過才重算；提醒過不重算）
        double flowerFrom, flowerRecover = -1;
        int petalsShown = 6;
        bool nectarReady;
        BubbleForm flowerBub;
        double flowerBubT;
        int lastFlowerSent = -1;
        double flowerSendT;
        string lastLunchSeen = "";

        double FlowerRaw()
        {
            if (double.IsNaN(flowerStart)) flowerStart = sessionStart;
            double end = sysIdle ? Now - W.IdleSeconds() : Now;   // 你離開的時候花不會繼續枯
            return Math.Max(0, Math.Min(1, (end - flowerStart) / Math.Max(60, restMin * 60)));
        }
        public double FlowerShown()
        {
            if (flowerRecover >= 0) { double e = Math.Min(1, flowerRecover / 4.0); e = e * e * (3 - 2 * e); return flowerFrom * (1 - e); }
            return FlowerRaw();
        }
        static int PetalsFor(double wv) { return 6 - (int)Math.Min(6, Math.Floor(Math.Max(0, wv - 0.42) / 0.095)); }

        public void FlowerLook(out double wilt, out int petals, out double regrow, out bool nectar, out double bubble)
        {
            wilt = FlowerShown();
            petals = petalsShown;
            regrow = flowerRecover >= 0 && flowerFrom > 0.42 ? 0.5 + 0.5 * Math.Min(1, flowerRecover / 4.0) : 1;
            nectar = nectarReady;
            bubble = flowerBubT;
        }

        int UsedMinutes() { if (double.IsNaN(flowerStart)) flowerStart = sessionStart; return (int)Math.Floor((Now - flowerStart) / 60); }

        // 點花：連續用了多久、還有多久會枯
        void FlowerClicked()
        {
            int used = UsedMinutes(), limit = (int)Math.Round(restMin);
            string text;
            if (FlowerRaw() >= 1) text = "花都枯了…起來喝口可樂、走一走 🥤\n（已經連續用 " + used + " 分鐘了）";
            else if (used < 1) text = "剛休息過，花開得好好的 🌸\n再 " + limit + " 分鐘會開始累喔";
            else text = "已經連續用電腦 " + used + " 分鐘了\n再 " + Math.Max(1, limit - used) + " 分鐘花就要枯了 🌸";
            ShowFlowerBubble(text, 5);
        }

        void ShowFlowerBubble(string text, double sec)
        {
            if (shelf == null || Hidden) return;
            if (flowerBub == null) flowerBub = new BubbleForm(Color.FromArgb(0x5C, 0xB0, 0x4A));
            flowerBubSize = flowerBub.Measure(text, FlowerRaw() >= 1, Night ? 3 : 0, null);
            flowerBubT = sec;
            PlaceFlowerBub();
            if (!W.Shown(flowerBub)) flowerBub.Show();
            W.KeepOnTop(flowerBub);
        }
        Size flowerBubSize;
        // 泡泡跟著花（櫃子收成蛋時改在蛋上面）
        void PlaceFlowerBub()
        {
            if (flowerBub == null || shelf == null) return;
            Size sz = flowerBubSize;
            Rectangle c = shelf.Collapsed ? shelf.EggScreen() : shelf.CellScreen(0);
            Rectangle wa = WA(c.X + c.Width / 2.0, c.Y);
            int bx = Math.Max(wa.Left, Math.Min(wa.Right - sz.Width, c.X + c.Width / 2 - sz.Width / 2));
            int by = Math.Max(wa.Top, shelf.Collapsed ? c.Y - sz.Height - 4 : c.Y + c.Height / 4 - sz.Height);
            Rectangle nb = new Rectangle(bx, by, sz.Width, sz.Height);
            if (flowerBub.Bounds != nb) flowerBub.Bounds = nb;
        }

        // 休息時間到了（取代一般的休息提醒）：花枯了，皮克敏跑來擔心、拉你的游標
        void PikWiltAlarm()
        {
            if (double.IsNaN(flowerStart)) flowerStart = sessionStart;
            if (FlowerRaw() < 1) flowerStart = Math.Min(flowerStart, Now - restMin * 60);   // 設定改短了：直接枯
            ShowFlowerBubble("花都枯了…起來喝口可樂、走一走 🥤", 9);
            sceneCd = Math.Max(sceneCd, 20);
            List<Pet> outs = OutPets();
            if (outs.Count == 0) return;
            AbortScene();
            Rectangle a = shelf.Area;
            Rectangle wa = WA(a.Left - 100 * k, a.Bottom - 4);
            for (int i = 0; i < outs.Count; i++)
            {
                Pet p = outs[i];
                double tx = Math.Max(wa.Left + p.SW, a.Left - (60 + i * 70) * k);
                p.WakeIfSleep();
                if (i == 0 && outs.Count > 1)
                {
                    // 第一隻跑去拉你的游標
                    p.Say("噗咿…！（拉拉你）休息一下嘛…", 4);
                    Point c = Cursor.Position;
                    if (p.Grounded()) p.PikGoto(Math.Max(wa.Left + p.SW, Math.Min(wa.Right - p.SW, c.X)), "goto", 3);
                    Pet pp = p;
                    Later(3.2, delegate { if (pp.Out && pp.Grounded()) { pp.PikDo("tug", 3); pp.Say("休息…噗咿…", 2); } });
                    continue;
                }
                Pet q = p; double qx = tx; string line = i % 2 == 0 ? "花…噗咿…" : "枯掉了…噗咿…";
                if (q.OnFloor && Math.Abs(q.Foot - wa.Bottom) < 3) q.PikGoto(qx, "goto", 4);
                else q.JumpTo(qx, wa.Bottom);
                Later(2.8 + i * 0.3, delegate { if (q.Out && q.Grounded()) { q.dir = 1; q.PikDo("worry", 4); q.Say(line, 2.4); } });
            }
        }

        // 真的休息回來了（閒置超過設定的分鐘數）：花慢慢恢復，然後滴花蜜
        void PikRested()
        {
            if (double.IsNaN(flowerStart)) flowerStart = sessionStart;
            double from = FlowerShown();
            flowerStart = Now;
            if (from < 0.08) return;
            flowerFrom = from; flowerRecover = 0;
            nectarReady = false;
        }

        void PikTick(double dt)
        {
            if (!PikLineup)
            {
                if (flowerBub != null && W.Shown(flowerBub)) flowerBub.Hide();
                return;
            }
            if (flowerBubT > 0) { flowerBubT -= dt; if (flowerBubT <= 0 || Hidden) { flowerBubT = 0; if (flowerBub != null) flowerBub.Hide(); } else PlaceFlowerBub(); }
            if (flowerRecover >= 0)
            {
                double before = flowerRecover;
                flowerRecover += dt;
                if (before < 4 && flowerRecover >= 4) { flowerRecover = -1; if (flowerFrom > 0.15) Nectar(); }
            }
            petalsShown = PetalsFor(FlowerShown());
            // 給 VS Code 狀態列：花的狀態（每 5% 一格）
            flowerSendT -= dt;
            if (flowerSendT <= 0)
            {
                flowerSendT = 2;
                int pct = (int)Math.Round(FlowerShown() * 20) * 5;
                if (pct != lastFlowerSent) { lastFlowerSent = pct; lock (clients) foreach (Client c in clients) Send(c, "flower " + pct + "\n"); }
            }
            StepCarry(dt);
            StepNectar();
            // 午餐：兩隻以上在外面時一起切大水果
            if (LunchState != lastLunchSeen) { if (LunchState == "eat" && lastLunchSeen == "" && OutCount() >= 2) Later(4, delegate { if (scene == null) PikScene("fruit"); }); lastLunchSeen = LunchState; }
        }

        // ---------- 花蜜：休息回來，花滴出花蜜；外面的皮克敏跑過去喝 → 葉子→花苞→花 ----------
        readonly List<Prop> nectarDrops = new List<Prop>();
        readonly Dictionary<Prop, Pet> nectarFor = new Dictionary<Prop, Pet>();
        static readonly string[] NECTAR_ART = { "..y..", ".yYy.", "yYWYy", "yYYYy", ".yyy." };

        void Nectar()
        {
            nectarReady = true;
            Later(6, delegate { nectarReady = false; });
            List<Pet> outs = OutPets();
            if (outs.Count == 0 || Hidden)
            {
                // 都在櫃子裡：在櫃子裡喝
                foreach (Pet p in Pets) p.PikGrow();
                ShowFlowerBubble("休息回來了！花蜜滴下來 🍯\n大家在櫃子裡喝到了，噗咿！", 4.5);
                return;
            }
            ShowFlowerBubble("休息回來了！花又開了 🌸\n花蜜滴下來囉，噗咿！", 4);
            AbortScene();
            sceneCd = Math.Max(sceneCd, 25);   // 喝完花蜜之前不要開始別的串場
            Rectangle a = shelf.Area, c0 = shelf.CellScreen(0);
            Rectangle wa = WA(a.Left - 60 * k, a.Bottom - 4);
            Pal owner = Pal.Get("pkyellow");
            for (int i = 0; i < outs.Count; i++)
            {
                Pet p = outs[i];
                double dx = Math.Max(wa.Left + p.SW, a.Left - (40 + i * 75) * k);
                Prop d = Toss(NECTAR_ART, owner, new PointF(c0.X + c0.Width / 2f, c0.Y + c0.Height / 3f), new PointF((float)dx, (float)(wa.Bottom - 3 * S)), 0.9 + i * 0.15, 120 * k, false, 40, null);
                if (d == null) { p.PikGrow(); continue; }
                nectarDrops.Add(d); nectarFor[d] = p;
                Pet pp = p; double tx = dx;
                Later(0.6 + i * 0.2, delegate
                {
                    if (!pp.Out) return;
                    pp.WakeIfSleep();
                    pp.Say("噗咿！花蜜！", 1.2);
                    if (pp.OnFloor && Math.Abs(pp.Foot - wa.Bottom) < 3) pp.PikGoto(tx, "goto", 6);
                    else pp.JumpTo(tx, wa.Bottom);
                });
            }
        }

        void StepNectar()
        {
            for (int i = nectarDrops.Count - 1; i >= 0; i--)
            {
                Prop d = nectarDrops[i];
                Pet p;
                if (!nectarFor.TryGetValue(d, out p) || !props.Contains(d)) { nectarDrops.RemoveAt(i); nectarFor.Remove(d); continue; }
                if (d.Legs.Count > 0 || !p.Out) continue;
                if (Math.Abs(p.Cx - d.X) < p.SW * 0.6 && Math.Abs(p.Foot - (d.Y + 3 * S)) < 30 * k && p.Grounded() && (p.state != "pik" || p.PikGoing))
                {
                    RemoveProp(d); nectarDrops.RemoveAt(i); nectarFor.Remove(d);
                    p.PikDo("drink", 1.8);
                }
                else if (p.Grounded() && p.state != "pik" && p.state != "air" && Math.Abs(p.Cx - d.X) >= p.SW * 0.6 && Math.Abs(p.Foot - (d.Y + 3 * S)) < 30 * k) p.PikGoto(d.X, "goto", 5);
            }
        }

        // ---------- 吹哨子：外面的皮克敏全部跑來跟著游標 ----------
        public void Whistle()
        {
            List<Pet> outs = OutPets();
            if (outs.Count == 0) { Lead().Say("（大家都在土裡）噗咿？", 1.6); return; }
            AbortScene();
            Pet l = Lead();
            sceneCd = Math.Max(sceneCd, 12);
            l.Say("嗶——！（吹哨子）", 1.4);
            for (int i = 0; i < outs.Count; i++)
            {
                Pet p = outs[i]; int idx = i;
                p.WakeIfSleep();
                Later(0.3 + i * 0.45, delegate { if (p.Out && p.Grounded()) { p.PikFollow(idx, 9); if (p != l) p.Say("噗咿！", 0.6); } });
            }
        }

        // ---------- 一起搬東西（顆粒、可樂、球）：數字＝要幾隻 ----------
        Prop carryProp; List<Pet> carriers; double carryX, carryTarget, carryLift; string carryWhat = "";
        static readonly string[][] DIGITS = {
            new string[] { "WWW", "W.W", "W.W", "W.W", "WWW" }, new string[] { ".W.", "WW.", ".W.", ".W.", "WWW" }, new string[] { "WWW", "..W", "WWW", "W..", "WWW" },
            new string[] { "WWW", "..W", ".WW", "..W", "WWW" }, new string[] { "W.W", "W.W", "WWW", "..W", "..W" }, new string[] { "WWW", "W..", "WWW", "..W", "WWW" } };
        static string[] PelletArt(int n)
        {
            string[] o = { "...ooooo...", ".oorrrrroo.", ".orhrrrrrRo", "orhrrrrrrRo", "orrrrrrrrRo", "orrrrrrrrRo", "orrrrrrrrRo", "orrrrrrrRRo", ".orrrrrRRo.", ".ooRRRRRoo.", "...ooooo..." };
            char[][] g = new char[o.Length][];
            for (int i = 0; i < o.Length; i++) g[i] = o[i].ToCharArray();
            string[] d = DIGITS[Math.Max(0, Math.Min(5, n))];
            for (int r = 0; r < 5; r++) for (int c = 0; c < 3; c++) if (d[r][c] == 'W') g[3 + r][4 + c] = 'W';
            string[] res = new string[o.Length];
            for (int i = 0; i < o.Length; i++) res[i] = new string(g[i]);
            return res;
        }
        static readonly string[] COLA_ART = { ".7777.", "777777", "SSSSSS", "SWWSSS", "SSWWWS", "SSSSWS", "SSSSSS", "777777", ".7777." };

        void StartCarry(List<Pet> who, string what, double fromX, double toX)
        {
            carriers = who; carryWhat = what; carryX = fromX; carryTarget = toX; carryLift = 0;
            Pal owner = Pal.Get(what == "pellet" ? "pkred" : "pkblue");
            string[] art = what == "pellet" ? PelletArt(who.Count) : COLA_ART;
            Rectangle wa = WA(fromX, who[0].Foot - 4);
            carryProp = NewProp(art, null, owner, S, fromX, wa.Bottom - art.Length * S / 2.0, false);
            carryProp.Hold = 999;
        }

        void StepCarry(double dt)
        {
            if (carryProp == null) return;
            if (!props.Contains(carryProp) || carriers == null) { carryProp = null; return; }
            List<Pet> live = new List<Pet>();
            foreach (Pet p in carriers) if (p.Out && p.PikCarrying) live.Add(p);
            double headY = double.MaxValue;
            foreach (Pet p in carriers) if (p.Out) headY = Math.Min(headY, p.Foot - p.SH + (p.P.HeadTop - 1) * p.S);
            if (live.Count > 0)
            {
                carryLift = Math.Min(1, carryLift + dt * 1.2);
                bool ready = true;
                for (int i = 0; i < live.Count; i++) if (Math.Abs(live[i].Cx - (carryX + (i - (live.Count - 1) / 2.0) * live[i].SW * 1.1)) > live[i].SW * 0.4) ready = false;
                if (!ready) for (int i = 0; i < live.Count; i++) live[i].PikGoto(carryX + (i - (live.Count - 1) / 2.0) * live[i].SW * 1.1, "carry", 30);
                if (carryLift >= 1 && ready)
                {
                    double sp = 55 * k * dt * Math.Min(1, live.Count / (double)carriers.Count);
                    carryX += Math.Sign(carryTarget - carryX) * Math.Min(Math.Abs(carryTarget - carryX), sp);
                    for (int i = 0; i < live.Count; i++) live[i].PikGoto(carryX + (i - (live.Count - 1) / 2.0) * live[i].SW * 1.1, "carry", 30);
                }
            }
            Rectangle wa = WA(carryX, carriers[0].Foot - 4);
            double ground = wa.Bottom - carryProp.F.Height / 2.0, above = headY == double.MaxValue ? ground : headY - carryProp.F.Height / 2.0 + S;
            carryProp.X = carryX; carryProp.Y = ground + (above - ground) * carryLift;
            PlaceProp(carryProp);
        }

        void EndCarry()
        {
            if (carryProp != null) { Prop cp = carryProp; carryProp = null; Rectangle c0 = shelf.CellScreen(0); cp.Hold = 0; cp.Go(c0.X + c0.Width / 2.0, c0.Y + c0.Height / 2.0, 0.7, 60 * k, delegate { if (shelf.Collapsed) shelf.Gulp(); }); }
            if (carriers != null) foreach (Pet p in carriers) p.PikCarrying = false;
            carriers = null;
        }

        // ---------- 右鍵選單 ----------
        string[][] PikMenuItems(Pet p)
        {
            string sig = p.P.Id == "pkred" ? "握拳冒火 🔥" : (p.P.Id == "pkyellow" ? "跳高高 ⚡" : "游泳 💧");
            return new string[][] { new string[] { "抱抱 ♥", "hug" }, new string[] { "打招呼 噗咿！", "hi" }, new string[] { "敲敲螢幕", "knock" }, new string[] { "吹哨子（大家跟著游標）", "whistle" },
                new string[] { sig, "sig" }, new string[] { "跳到別的視窗上", "jump" }, new string[] { "睡覺", "sleep" }, new string[] { "丟球給他（大家搬回來）⚾", "ball" } };
        }

        void AddPikMenu(ContextMenuStrip m)
        {
            ToolStripMenuItem grp = new ToolStripMenuItem("皮克敏一起…");
            string[][] gs = { new string[] { "一起搬顆粒", "carry" }, new string[] { "排隊遊行", "march" }, new string[] { "花蜜派對 🍯", "party" }, new string[] { "一起切大草莓", "fruit" },
                new string[] { "大合照 📷", "photo" }, new string[] { "點名", "rollcall" }, new string[] { "回土裡睡覺", "byebye" } };
            foreach (string[] gi in gs) { string key = gi[1]; grp.DropDownItems.Add(gi[0], null, delegate { if (key == "photo") GroupPhoto(); else PikScene(key); }); }
            m.Items.Add(grp);
            m.Items.Add("休息花：還能撐多久？🌸", null, delegate { FlowerClicked(); });
        }

        // ---------- 串場 ----------
        void PikGroup(int n)
        {
            double r = rnd.NextDouble();
            if (r < .3) PikScene("carry"); else if (r < .55) PikScene("march"); else if (r < .75) PikScene("party"); else GroupPhoto();
        }

        List<Pet> PikOrder(List<Pet> l)
        {
            List<Pet> o = new List<Pet>();
            foreach (string id in Pal.PikminIds) foreach (Pet p in l) if (p.P.Id == id) o.Add(p);
            return o;
        }

        // 大家排到櫃子左邊的地板上（不管原本在哪個視窗上）
        // 大家排到地板上（在帶頭那隻附近；nearShelf＝排到櫃子左邊）；離太遠就用跳的
        double[] PikGather(List<Pet> outs, double spacing, double startAt) { return PikGather(outs, spacing, startAt, false); }
        double[] PikGather(List<Pet> outs, double spacing, double startAt, bool nearShelf)
        {
            Rectangle a = shelf.Area;
            Pet l = outs[0];
            Rectangle wa = WA(nearShelf ? a.Left - 200 * k : l.Cx, a.Bottom - 4);
            double foot = wa.Bottom, width = (outs.Count - 1) * outs[0].SW * spacing;
            double center = nearShelf ? a.Left - 80 * k - width / 2 - outs[0].SW : l.Cx;
            double maxRight = Math.Min(wa.Right, a.Left) - outs[0].SW * 0.8;
            center = Math.Max(wa.Left + outs[0].SW + width / 2, Math.Min(maxRight - width / 2, center));
            double first = center - width / 2;
            for (int i = 0; i < outs.Count; i++)
            {
                Pet p = outs[i];
                double tx = first + i * p.SW * spacing;
                At(startAt + i * 0.3, delegate
                {
                    if (p.OnFloor && Math.Abs(p.Foot - foot) < 3 && Math.Abs(tx - p.Cx) < 320 * k) p.WalkTo(tx, 10);
                    else p.JumpTo(tx, foot);
                });
            }
            return new double[] { first, first + width, foot };
        }

        void PikScene(string key)
        {
            List<Pet> outs = PikOrder(OutPets());
            if (outs.Count < 2 && key != "rollcall" && key != "byebye") { AllOut(); Later(2.6, delegate { PikScene(key); }); return; }
            switch (key)
            {
                case "carry": SceneCarry(outs, "pellet"); break;
                case "cola": SceneCarry(outs, "cola"); break;
                case "march": SceneMarch(outs); break;
                case "party": SceneNectarParty(outs); break;
                case "fruit": SceneFruit(outs); break;
                case "rollcall": PikRollCall(new List<string>(Pal.PikminIds)); break;
                case "byebye": PikNight(false); break;
            }
        }

        void PikPairScene(string key)
        {
            switch (key)
            {
                case "pkred-pkyellow": SceneToss(Get("pkred"), Get("pkyellow")); break;
                case "pkblue-pkred": SceneRescue(Get("pkblue"), Get("pkred")); break;
                case "pkblue-pkyellow": SceneCarry(new List<Pet>(new Pet[] { Get("pkyellow"), Get("pkblue") }), "cola"); break;
            }
        }

        // 紅丟黃：紅皮克敏把黃皮克敏丟到高高的地方
        void SceneToss(Pet red, Pet yel)
        {
            Begin(red, yel);
            At(0, delegate { Face(red, yel); red.ScenePose("idle", 30); yel.ScenePose("idle", 30); yel.Say("小紅！丟我！要飛高高！", 2); yel.PikSpark(1.5); });
            At(2.1, delegate { red.Say("嘿！準備好了！", 1.4); red.WalkTo(yel.Cx + (red.Cx < yel.Cx ? -1 : 1) * yel.SW * 0.7, 1); });
            At(3.4, delegate { red.FaceTo(yel); red.PikDo("throwup", 0.8); red.Say("嘿咻——！", 1); });
            At(3.7, delegate
            {
                Plat best = null;
                foreach (Plat p in Plats) if (p.Top < yel.Foot - 120 * k && p.Top > yel.Foot - 700 * k && Math.Abs((p.Left + p.Right) / 2.0 - yel.Cx) < 700 * k && p.Right - p.Left > yel.SW * 2) { best = p; break; }
                yel.InScene = false;
                if (best != null) yel.JumpTo(Math.Max(best.Left + yel.SW, Math.Min(best.Right - yel.SW, yel.Cx)), best.Top);
                else yel.Jump(red.dir * 90 * k, -900 * k);
                yel.InScene = true;
                yel.PikSpark(2.2); yel.Say("噗咿～～～！", 1.6);
            });
            At(6.4, delegate { yel.Say("好高！再一次！噗咿！", 2); red.ScenePose("hop", 0); });
            At(8.6, delegate { red.Say("嘿嘿，小紅力氣最大！", 2); red.PikFlame(1.2); });
            At(10.8, delegate { });
        }

        // 藍救紅：紅掉進水窪，藍游過去拉他上來
        void SceneRescue(Pet blue, Pet red)
        {
            Begin(blue, red);
            At(0, delegate { Face(blue, red); blue.ScenePose("idle", 30); red.ScenePose("idle", 30); red.Say("嘿！我也要玩水！", 1.8); });
            At(1.9, delegate { red.ScenePose("hop", 0); });
            At(2.6, delegate { red.PikDo("drown", 30); red.Say("噗咿！噗咿！（不會游泳）", 2.4); });
            At(4.6, delegate { blue.Say("別怕，我來！", 1.4); blue.WalkTo(red.Cx + (blue.Cx < red.Cx ? -1 : 1) * red.SW * 0.9, 1); });
            At(6.2, delegate { blue.FaceTo(red); blue.PikDo("swim", 30); blue.Say("咕嚕咕嚕～", 1.4); });
            At(7.8, delegate { blue.PikDo("lift", 30); red.ScenePose("idle", 30); red.PikPop("噗哈！"); });
            At(9.4, delegate { blue.ScenePose("idle", 30); Face(blue, red); red.Say("謝謝小藍…（滴水）", 2); red.Mark(4); });
            At(11.6, delegate { blue.Say("小紅怕水，小藍怕火，剛剛好。", 2.4); });
            At(14.2, delegate { blue.ScenePose("hug", 2.2); red.ScenePose("hug", 2.2); red.Say("噗咿！", 1.4); });
            At(16.6, delegate { });
        }

        // 大家一起搬顆粒（或可樂）回櫃子：嘿咻嘿咻
        void SceneCarry(List<Pet> who, string what)
        {
            who = PikOrder(who);
            foreach (Pet p in who) if (p == null || !p.Out) return;
            Pet l = who[0];
            Begin(who.ToArray());
            double[] lr = PikGather(who, 1.2, 0.3);
            double cx = (lr[0] + lr[1]) / 2;
            At(0, delegate { l.Say(what == "cola" ? "噗咿！可樂罐！一起搬！" : "噗咿！顆粒！數字是 " + who.Count + "，要 " + who.Count + " 隻！", 2.4); });
            At(3.8, delegate { StartCarry(who, what, cx, shelf.Area.Left - 30 * k); foreach (Pet p in who) { p.FaceTo(l); p.ScenePose("idle", 30); } });
            At(4.6, delegate { foreach (Pet p in who) { p.PikCarrying = true; p.PikDo("lift", 30); } l.Say("嘿咻！", 1.2); });
            for (int s3 = 0; s3 < 10; s3++) { int idx = s3; At(5.6 + s3 * 2.6, delegate { if (carryProp != null) who[idx % who.Count].Say("嘿咻嘿咻！", 1.4); }); }
            for (int s2 = 0; s2 < 120; s2++)
                At(6.0 + s2 * 0.25, delegate
                {
                    if (carryProp == null || Math.Abs(carryX - carryTarget) > 2) return;
                    EndCarry(); foreach (Pet p in who) { p.ScenePose("idle", 30); p.Burst(4); } l.Say("搬回去了！噗咿！", 2);
                    double tEnd = sceneT;
                    At(tEnd + 2.0, delegate { foreach (Pet p in who) p.ScenePose("hop", 0); });
                    At(tEnd + 3.2, delegate { if (scene != null) scene.Clear(); });
                });
            At(36, delegate { EndCarry(); });
        }

        // 吹哨子排隊遊行
        double marchX, marchDir; bool marchOn;
        void SceneMarch(List<Pet> outs)
        {
            Pet l = outs[0];
            Begin(outs.ToArray());
            double[] lr = PikGather(outs, 1.3, 0.3);
            At(0, delegate { l.Say("嗶——！排隊！", 1.8); });
            At(4.2, delegate
            {
                marchX = lr[1] + 20 * k; marchDir = -1; marchOn = true;
                foreach (Pet p in outs) p.Say("噗咿！", 0.8);
            });
            for (int s = 0; s < 40; s++)
            {
                double at = 4.4 + s * 0.2;
                At(at, delegate
                {
                    if (!marchOn) return;
                    Rectangle wa = WA(marchX, lr[2] - 4);
                    marchX += marchDir * 120 * k * 0.2;
                    if (marchX < wa.Left + 60 * k) { marchDir = 1; }
                    if (marchX > shelf.Area.Left - 40 * k) { marchDir = -1; }
                    for (int i = 0; i < outs.Count; i++) outs[i].PikGoto(marchX - marchDir * (i + 1) * outs[i].SW * 1.3, "march", 30);
                });
            }
            At(6.4, delegate { l.Say("一、二！一、二！", 1.6); });
            At(9.4, delegate { outs[outs.Count - 1].Say("噗咿！噗咿！", 1.4); });
            At(12.6, delegate { marchOn = false; foreach (Pet p in outs) { p.ScenePose("idle", 30); p.ScenePose("hop", 0); } l.Say("解散！噗咿！", 1.6); });
            At(14, delegate { });
        }

        // 花蜜派對：在花前面集合，花滴下花蜜
        void SceneNectarParty(List<Pet> outs)
        {
            Begin(outs.ToArray());
            PikGather(outs, 1.5, 0.3, true);
            At(0, delegate { outs[0].Say("噗咿！去花那邊！", 1.6); });
            At(4.4, delegate { foreach (Pet p in outs) { p.dir = 1; p.ScenePose("idle", 30); } ShowFlowerBubble("花蜜派對！噗咿！🍯", 3); });
            At(5.2, delegate { AbortScene(); Nectar(); });
        }

        // 午餐：大家一起切一顆大水果
        static readonly string[] BIGFRUIT = { "....GgG....", "...GGgGG...", ".SSSSSSSSS.", "SSYSSSSYSSS", "SSSSSYSSSSS", "SYSSSSSSYSS", "SSSSYSSSSSS", ".SSSSSSYSS.", "..SSSSSSS..", "....SSS...." };
        void SceneFruit(List<Pet> outs)
        {
            Pet l = outs[0];
            Begin(outs.ToArray());
            double[] lr = PikGather(outs, 1.6, 0.3);
            double cx = (lr[0] + lr[1]) / 2;
            Prop fruit = null;
            At(0, delegate { l.Say("噗咿！午餐！大草莓！", 2); });
            At(3.6, delegate { fruit = Toss(BIGFRUIT, Pal.Get("pkred"), new PointF((float)cx, (float)(lr[2] - 300 * k)), new PointF((float)cx, (float)(lr[2] - 5 * S)), 0.8, 0, false, 30, delegate { l.Say("咚！", 0.8); }); });
            At(4.8, delegate { foreach (Pet p in outs) { p.FaceTo(l); p.dir = p.Cx < cx ? 1 : -1; p.PikDo("punch", 1.2); } l.Say("嘿！嘿！切開！", 1.4); });
            At(6.4, delegate { RemoveProp(fruit); foreach (Pet p in outs) { p.PikHold = "straw"; p.ScenePose("idle", 30); p.Burst(4); } l.Say("一人一塊！噗咿！", 1.8); });
            At(8.6, delegate { l.Say("好甜！咕嘟咕嘟～", 1.6); foreach (Pet p in outs) p.Mark(0); });
            At(11, delegate { foreach (Pet p in outs) { p.PikHold = ""; p.ScenePose("hop", 0); } });
            At(12, delegate { });
        }

        // 早上點名：一隻一隻從土裡拔出來
        void PikRollCall(List<string> ids)
        {
            List<Pet> order = new List<Pet>();
            foreach (string id in Pal.PikminIds) if (ids.Contains(id) && Get(id) != null) order.Add(Get(id));
            double d = 0.4;
            foreach (Pet p in order)
            {
                Pet pp = p;
                Later(d, delegate { if (!pp.Out) BringOut(pp, false); });
                Later(d + 1.9, delegate { pp.Say(pp.P.Name.Substring(0, 1) + "！噗咿！", 1.6); });
                d += 1.5;
            }
            Later(d + 1.6, delegate { if (order.Count > 0) Lead().Say("全員到齊！噗咿！", 2.4); foreach (Pet p in order) if (p.Out && p.Grounded()) p.ScenePose("wave", 1.6); });
        }

        // 下班：一隻一隻鑽回櫃子的土裡
        void PikNight(bool nag)
        {
            List<Pet> outs = PikOrder(OutPets());
            if (outs.Count == 0) { Lead().Say("噗咿…晚安…", 2.4); return; }
            Begin(outs.ToArray());
            foreach (Pet p in outs) if (p.Grounded()) p.ScenePose("idle", 60);
            double d = 0.2;
            if (nag) foreach (Pet p in outs) { Pet pp = p; At(d, delegate { pp.Say(pp.L("nag"), 2.4); }); d += 2.6; }
            foreach (Pet p in outs)
            {
                Pet pp = p;
                At(d, delegate { pp.Say("噗咿…晚安…", 1.6); pp.PikDo("dig", 30); });
                At(d + 1.0, delegate { pp.InScene = false; if (pp.Out) pp.StowToShelf(false); });
                d += 1.8;
            }
            At(d + 0.5, delegate { Pet last = outs[outs.Count - 1]; last.Say("（土裡）噗咿…zZ", 2.6); });
            At(d + 3.2, delegate { });
        }

        // ---------- 皮克敏一櫃的開場白 ----------
        static string PikFlavor(string id, string kind)
        {
            if (id != "pkred" && id != "pkyellow" && id != "pkblue") return null;
            string[] keys = { "ci-run", "ci-ok", "ci-fail", "cmd-ok", "cmd-fail", "meeting", "meeting-now", "jira", "worklog",
                              "remind", "pc-cpu", "pc-ram", "pc-disk", "net-down", "net-up", "vpn", "download" };
            string[] t = { "噗咿！CI 出發：", "CI 過了！噗咿！", "噗咿！CI 倒了：", "跑完了！嘿咻：", "噗咿？失敗了：", "等等要開會：", "開會了！噗咿！快去：", "有新的 Jira！噗咿：", "日誌好了，噗咿：",
                           "⏰ 噗咿！提醒你：", "電腦好燙！噗咿：", "記憶體快滿了：", "硬碟快滿了：", "網路斷了！噗咿…", "網路回來了！噗咿！", "連不到公司網路（VPN 斷了？）", "下載好了！大家搬回來了：" };
            int i = Array.IndexOf(keys, kind);
            return i < 0 ? null : t[i];
        }
        static string PikTicket(string id, int stage, string n, string h)
        {
            if (id != "pkred" && id != "pkyellow" && id != "pkblue") return null;
            string[] t = { "🎫 " + n + " 還有 " + h + "開賣！先登入、綁好付款！噗咿！", "🎫 " + n + " 再 30 分鐘！噗咿！", "🎫 " + n + " 剩 10 分鐘！嘿咻！", "🎫 準備！噗咿…", "🎫 開搶！！衝啊！噗咿！" };
            return t[stage];
        }

        // 測試用（只在離屏模式）：act flower <快轉分鐘>｜rest｜click
        void PikFlowerAct(string arg)
        {
            if (arg == "click") { FlowerClicked(); return; }
            if (!App.Offscreen) return;
            double m;
            if (arg == "rest") { PikRested(); return; }
            if (arg.StartsWith("idle") && double.TryParse(arg.Substring(4), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out m)) { TestIdle = m; return; }
            if (arg == "wilt") { PikWiltAlarm(); return; }
            if (arg.StartsWith("stage") && arg.Length == 6) { int s = arg[5] - '0'; foreach (Pet p in Pets) p.PikSetStage(s); return; }
            if (double.TryParse(arg, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out m)) { flowerRecover = -1; flowerStart = Now - m * 60; }
        }
    }
}
