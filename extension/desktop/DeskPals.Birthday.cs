// Desk Pals：生日大驚喜。平常（非生日）這一整個檔都不動作。
//
// 生日當天（World.SeasonNow=="birthday"，由 Season() 依 birthday（MM-DD）判斷）：
//   1) 本來就有的：每隻公仔捧著蛋糕、會說生日快樂（DeskPals.cs 的 DrawAccessories／SeasonLine）。
//   2) 這個檔多加的「很有畫面感」大驚喜：全員出櫃、戴派對帽（bday 造型美術進來前先用像素帽 fallback）、
//      放煙火灑彩帶、一起圍過來唱歌跳舞冒愛心。只演幾秒，收尾乾淨。
//
// 重播（擁有者說：不要一天一次）：
//   - 當天第一次看到 → 自動播一次（bday-auto.txt 記「今天」，只擋自動那一次）。
//   - 之後想看幾次就幾次：公仔小屋 → 娛樂 →「生日驚喜 再看一次」、或點公仔捧著的蛋糕。
//   - 分享短片（DeskPals.Share.cs）在生日當天自動變成生日版，所以驚喜能被錄下來分享。
//
// 生日存哪：本機 birthday.txt（World.DataDir）。VS Code 的 deskPals.birthday 設定、pipe「birthday MM-DD」、
//   第一次設定精靈三邊同步——哪邊設都存到這裡。
//
// 絕不依賴真實日期：是不是生日一律走 Season()，Season() 用 App.Now()（離屏測試可用 DESKPALS_FAKE_NOW 假時鐘）。
//
// pipe（測試用）：bday-info（印出現在狀態）、act bday（＝再看一次）。
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.IO;
    using System.Reflection;

    partial class World
    {
        // 慶祝中：公仔戴派對帽／bday 造型（給 DrawAccessories 看）
        public bool BdayHatOn;
        bool bdayPlaying;       // 正在播大驚喜
        int bdayPlays;          // 這次開機播了幾次（含自動與手動；測試用）

        // 今天是不是生日（有設生日、且 Season() 判定是 birthday）
        public bool BirthdayOn { get { return birthday.Length == 5 && SeasonNow == "birthday"; } }

        // 現在存的生日（MM-DD；沒設＝空字串）——第一次設定精靈帶入用
        public string Birthday { get { return birthday; } }

        // 生日字串正規化成 MM-DD；不合法（含空白）回空字串＝沒設
        static string NormBirthday(string s)
        {
            s = (s ?? "").Trim();
            if (s.Length == 4 && AllDigits(s)) s = s.Substring(0, 2) + "-" + s.Substring(2);
            if (s.Length == 5 && s[2] == '-' && AllDigits(s.Substring(0, 2)) && AllDigits(s.Substring(3)))
            {
                int mm, dd;
                if (int.TryParse(s.Substring(0, 2), out mm) && int.TryParse(s.Substring(3), out dd)
                    && mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31)
                    return mm.ToString("00") + "-" + dd.ToString("00");
            }
            return "";
        }

        static bool AllDigits(string s)
        {
            foreach (char c in s) if (c < '0' || c > '9') return false;
            return s.Length > 0;
        }

        // 設生日（VS Code 設定／pipe／第一次設定精靈都走這裡）：存本機、重算節日
        public void SetBirthday(string s)
        {
            birthday = NormBirthday(s);
            WriteText("birthday.txt", birthday);   // 跟 VS Code deskPals.birthday、pipe 同步的那一份
            SeasonNow = Season();
            BirthdayAutoCheck();   // 當場設到今天生日（VS Code／精靈）也會自動播一次（當天只自動一次）
        }

        // 開機讀本機存的生日
        void LoadBirthday()
        {
            string s = ReadText("birthday.txt");
            if (s.Length > 0) birthday = NormBirthday(s);
        }

        // 當天第一次看到就自動播一次；bday-auto.txt 只記「今天播過了」，不決定是不是生日
        void BirthdayAutoCheck()
        {
            if (!BirthdayOn || Hidden) return;
            string today = App.Now().ToString("yyyy-MM-dd");
            if (ReadText("bday-auto.txt") == today) return;
            WriteText("bday-auto.txt", today);
            Later(1.5, delegate { if (BirthdayOn) BirthdayShow(); });
        }

        // 大驚喜本體：全員出櫃、戴帽、煙火、聚過來唱歌跳舞（想播幾次就幾次）
        public void BirthdayShow()
        {
            if (!BirthdayOn || Hidden) return;
            bdayPlays++;
            AllOut();                              // 全員出櫃
            BdayHatOn = true;                      // 戴派對帽（或之後的 bday 造型）
            bdayPlaying = true;
            Fireworks(ShelfWA(), 12, -1);          // 煙火／彩帶（小屋關掉煙火的話 Fireworks 自己會略過）
            Later(0.5, delegate { BirthdayGather(); });
            Later(5.5, delegate { bdayPlaying = false; });
            Later(6.5, delegate { BdayHatOn = false; RenderShelf(); });
        }

        // 聚過來一起唱（說生日快樂）、跳舞、冒愛心
        void BirthdayGather()
        {
            List<Pet> outs = OutPets();
            Pet lead = Lead();
            double delay = 0;
            foreach (Pet p in outs)
            {
                Pet pp = p;
                Later(delay, delegate { if (pp.Out) pp.BdayCelebrate(pp.BdayLine()); });
                delay += 0.22;
            }
            if (outs.Count == 0 && lead != null) lead.BdayCelebrate(lead.BdayLine());
            if (outs.Count > 0) Later(2.5, delegate { Fireworks(ShelfWA(), 8, -1); });   // 中段再補一波
        }

        // 點公仔捧著的蛋糕＝再看一次（生日當天才有；正在播就當普通摸）
        public bool BirthdayCakeClick(Pet p)
        {
            if (!BirthdayOn || Hidden || bdayPlaying) return false;
            BirthdayShow();
            return true;
        }

        // bday 造型美術（costume id「bday」）有沒有進來：embedded resource 或 DataDir\pals 底下有就用，
        // 沒有就回 false → DrawAccessories 用像素派對帽 fallback，一切照常不壞。
        bool? bdayCostume;
        public bool BdayCostumeAvailable()
        {
            if (bdayCostume.HasValue) return bdayCostume.Value;
            bool found = false;
            try
            {
                foreach (string n in Assembly.GetExecutingAssembly().GetManifestResourceNames())
                    if (n.IndexOf("bday", StringComparison.OrdinalIgnoreCase) >= 0) { found = true; break; }
            }
            catch { }
            if (!found)
            {
                try
                {
                    string dir = Path.Combine(DataDir, "pals");
                    if (Directory.Exists(dir))
                        foreach (string f in Directory.GetFiles(dir, "bday*.png", SearchOption.AllDirectories)) { found = true; break; }
                }
                catch { }
            }
            bdayCostume = found;
            return found;
        }

        // 測試用（test/desktop-birthday.js）
        string BdayInfo()
        {
            string auto = ReadText("bday-auto.txt");
            return "bday birthday=" + (birthday == "" ? "-" : birthday)
                + " season=" + (SeasonNow == "" ? "-" : SeasonNow)
                + " on=" + (BirthdayOn ? 1 : 0)
                + " playing=" + (bdayPlaying ? 1 : 0)
                + " hat=" + (BdayHatOn ? 1 : 0)
                + " plays=" + bdayPlays
                + " auto=" + (auto == "" ? "-" : auto)
                + " costume=" + (BdayCostumeAvailable() ? 1 : 0)
                + " out=" + OutCount()
                + "\n";
        }
    }

    partial class Pet
    {
        // 生日那句話（每個角色各自的 s_birthday；沒有就用通用那句）
        public string BdayLine()
        {
            string s = L("s_birthday");
            return string.IsNullOrEmpty(s) ? "生日快樂！🎂" : s;
        }

        // 一隻公仔的慶祝：醒來、跳舞、唱（說）生日快樂、冒愛心彩花
        public void BdayCelebrate(string line)
        {
            WakeIfSleep();
            if (Grounded()) SetState("dance", 4);
            Say(line, 4.5);
            Burst(12);
            AddHeart(); AddHeart();
        }
    }
}
