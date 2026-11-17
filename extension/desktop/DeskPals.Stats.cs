// Desk Pals：匿名回報（只有公開版；個人版 App.Public＝false，什麼都不送）。幫我們知道大家選哪一櫃、哪一櫃留得住人，決定下一櫃做什麼。
//
// 只送兩個事件到 GA4 Measurement Protocol（POST https://www.google-analytics.com/mp/collect?measurement_id=…&api_secret=…）：
//   lineup_pick   第一次設定完成時選了哪一櫃：lineup＝original／woban／custom（我的櫃），加上 app_version、platform
//   day7_active   第一次設定滿 7 天後第一次打開時，現在開著哪一櫃（只送一次；有送過 lineup_pick 才送，數字才對得起來）
//   platform：win-exe（安裝程式／單獨的 DeskPals.exe）、win-msix（Microsoft Store）、win-vscode（VS Code 擴充套件）、mac
//
// 不帶任何認得出你的東西：client_id 每次送都是新的亂數（本機不存任何 ID），沒有使用者名稱、電腦名稱、路徑、
//   不送 User-Agent；Google 收得到的只有連線本身的 IP（GA4 不存 IP）。
// 送不出去就算了：不重試、不排隊，在背景執行緒送（不卡畫面），5 秒逾時。
// 可以關：小屋「匿名回報選了哪一櫃」（anon-stats.txt 的 on=0）；關掉之後完全不送。第一次設定的第一頁有一行說明。
//
// ID 不寫在程式裡：打包時 tools/variant.py 從環境變數 GA4_MEASUREMENT_ID／GA4_API_SECRET（CI 的 repo variable／secret）
//   寫成 pals/ga4.txt（measurement_id=…、api_secret=…、version=…），exe 內嵌、vsix／.app 放在 pals 資料夾。
//   沒有這個檔（或格式不對）＝整個停用：不送、小屋沒有開關、設定頁沒有那行說明。
// 測試：DESKPALS_GA4_CONFIG＝另一份 ga4.txt、DESKPALS_GA4_URL＝假的端點（test/desktop-store.js）。
//   離屏測試、CI（GITHUB_ACTIONS／CI）沒指定假端點就一律不送，絕不會從測試送到 Google。
// 狀態（anon-stats.txt，只有這些）：on=0|1、installed=第一次設定的日期、pick=sent、day7=done
//
// pipe（測試用）：stats-dump；stats-payload <事件> <櫃>（印出會送的 JSON，不送）；act stats 0|1（＝小屋的開關）
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.IO;
    using System.Net;
    using System.Security.Cryptography;
    using System.Text;
    using System.Text.RegularExpressions;
    using System.Threading;
    using System.Windows.Forms;

    static class Stats
    {
        public const string DefaultUrl = "https://www.google-analytics.com/mp/collect";
        public static string Platform = "win-vscode";   // DeskPals.Main.cs（獨立版 exe）改成 win-exe／win-msix；desk-pals.ps1（VS Code）就是這個
        static bool loaded;
        static string mid, secret, ver = "";

        // 打包時注入的 ID（pals/ga4.txt；測試可用 DESKPALS_GA4_CONFIG 指另一份）
        static void Load()
        {
            if (loaded) return;
            loaded = true;
            if (!App.Public) return;
            string text = null;
            try
            {
                string cfg = Environment.GetEnvironmentVariable("DESKPALS_GA4_CONFIG");
                if (!string.IsNullOrEmpty(cfg)) { if (File.Exists(cfg)) text = File.ReadAllText(cfg); }
                else { byte[] b = SqArt.Read("ga4.txt"); if (b != null) text = Encoding.UTF8.GetString(b); }
            }
            catch { text = null; }
            if (text == null) return;
            string m = null, s = null;
            foreach (string line in text.Split('\n'))
            {
                string t = line.Trim().TrimStart('﻿');
                int eq = t.IndexOf('=');
                if (eq <= 0) continue;
                string k = t.Substring(0, eq).Trim(), v = t.Substring(eq + 1).Trim();
                if (k == "measurement_id") m = v;
                else if (k == "api_secret") s = v;
                else if (k == "version") ver = v;
            }
            if (m == null || s == null || !Regex.IsMatch(m, "^G-[A-Z0-9]{4,20}$") || !Regex.IsMatch(s, "^[A-Za-z0-9_-]{8,64}$")) { App.Log("stats: ga4.txt incomplete, disabled"); return; }
            if (!Regex.IsMatch(ver, "^[0-9A-Za-z.+-]{1,32}$")) ver = "unknown";
            mid = m; secret = s;
        }

        // 這一份能回報嗎（公開版＋有 ID）
        public static bool Available { get { Load(); return mid != null; } }
        public static string AppVersion { get { Load(); return ver; } }

        // 櫃的名字（只有這三種；其他一律 other）
        public static string LineupKey(string lu)
        {
            if (lu == Pal.Mine) return "custom";
            if (lu == "original" || lu == "woban") return lu;
            return "other";
        }

        // 每次都是新的亂數（GA4 要的格式：數字.數字），不存
        static string NewClientId()
        {
            byte[] b = new byte[8];
            using (RNGCryptoServiceProvider r = new RNGCryptoServiceProvider()) r.GetBytes(b);
            uint a = BitConverter.ToUInt32(b, 0) % 1000000000u, c = BitConverter.ToUInt32(b, 4) % 1000000000u;
            return (a + 100000000u).ToString() + "." + (c + 100000000u).ToString();
        }

        static string J(string s)
        {
            StringBuilder sb = new StringBuilder("\"");
            foreach (char ch in s)
            {
                if (ch == '"' || ch == '\\') sb.Append('\\').Append(ch);
                else if (ch < 0x20) sb.Append("\\u" + ((int)ch).ToString("x4"));
                else sb.Append(ch);
            }
            return sb.Append('"').ToString();
        }

        // 要送的內容（全部就這些）
        public static string Payload(string ev, string lineup)
        {
            return "{\"client_id\":" + J(NewClientId()) + ",\"non_personalized_ads\":true,\"events\":[{\"name\":" + J(ev)
                + ",\"params\":{\"lineup\":" + J(LineupKey(lineup)) + ",\"app_version\":" + J(AppVersion) + ",\"platform\":" + J(Platform) + "}}]}";
        }

        // 測試／CI 不能送到 Google：離屏模式、CI 上一定要指定假端點
        static string Url()
        {
            string u = Environment.GetEnvironmentVariable("DESKPALS_GA4_URL");
            if (!string.IsNullOrEmpty(u)) return u;
            if (App.Offscreen || !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("GITHUB_ACTIONS")) || !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("CI"))) return null;
            return DefaultUrl;
        }

        // 背景送一次；失敗就算了。回傳 false＝沒有送（沒有 ID、測試環境沒有假端點）
        public static bool Send(string ev, string lineup)
        {
            if (!Available) return false;
            string url = Url();
            if (url == null) { App.Log("stats: " + ev + " skipped (test environment)"); return false; }
            string full = url + (url.IndexOf('?') >= 0 ? "&" : "?") + "measurement_id=" + Uri.EscapeDataString(mid) + "&api_secret=" + Uri.EscapeDataString(secret);
            byte[] body = new UTF8Encoding(false).GetBytes(Payload(ev, lineup));
            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072;   // TLS 1.2
                    HttpWebRequest r = (HttpWebRequest)WebRequest.Create(full);
                    r.Method = "POST";
                    r.ContentType = "application/json";
                    r.Timeout = 5000; r.ReadWriteTimeout = 5000;
                    r.AllowAutoRedirect = false;
                    r.KeepAlive = false;
                    r.ServicePoint.Expect100Continue = false;
                    r.ContentLength = body.Length;
                    using (Stream s = r.GetRequestStream()) s.Write(body, 0, body.Length);
                    using (HttpWebResponse resp = (HttpWebResponse)r.GetResponse()) App.Log("stats: " + ev + " sent (" + (int)resp.StatusCode + ")");
                }
                catch (Exception ex) { App.Log("stats: " + ev + " not sent (" + ex.GetType().Name + ")"); }
            });
            return true;
        }
    }

    partial class World
    {
        readonly Dictionary<string, string> statsState = new Dictionary<string, string>();

        void StatsLoad()
        {
            statsState.Clear();
            foreach (string line in ReadText("anon-stats.txt").Split('\n'))
            {
                int eq = line.IndexOf('=');
                if (eq > 0) statsState[line.Substring(0, eq).Trim()] = line.Substring(eq + 1).Trim();
            }
        }
        void StatsSave()
        {
            StringBuilder sb = new StringBuilder();
            foreach (string k in new string[] { "on", "installed", "pick", "day7" })
            {
                string v;
                if (statsState.TryGetValue(k, out v)) sb.Append(k + "=" + v + "\n");
            }
            WriteText("anon-stats.txt", sb.ToString());
        }
        string StatsGet(string k) { string v; return statsState.TryGetValue(k, out v) ? v : ""; }
        public bool StatsOn { get { return Stats.Available && StatsGet("on") != "0"; } }

        // Start 裡：滿 7 天後第一次打開 → day7_active（只送一次）
        void StatsStart()
        {
            if (!App.Public) return;
            StatsLoad();
            DateTime inst;
            if (StatsGet("day7") != "" || StatsGet("pick") != "sent" || !DateTime.TryParseExact(StatsGet("installed"), "yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out inst)) return;
            if ((DateTime.Today - inst).TotalDays < 7) return;
            if (StatsOn && !Stats.Send("day7_active", lineup)) return;   // 測試環境沒假端點：下次再看
            statsState["day7"] = "done";
            StatsSave();
        }

        // 第一次設定完成（ApplySetup）：記下日期、送 lineup_pick
        void StatsPicked(string lu)
        {
            if (!App.Public) return;
            StatsLoad();
            if (StatsGet("installed") == "") statsState["installed"] = DateTime.Today.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);
            if (StatsGet("pick") == "" && StatsOn && Stats.Send("lineup_pick", lu)) statsState["pick"] = "sent";
            StatsSave();
        }

        // 小屋的開關（有 ID 的公開版才有）
        void StatsHouseMenu(ToolStripItemCollection items)
        {
            if (!Stats.Available) return;
            ToolStripMenuItem mi = new ToolStripMenuItem("匿名回報選了哪一櫃（幫我們決定下一櫃）");
            mi.CheckOnClick = true;
            mi.Checked = StatsOn;
            mi.Click += delegate { StatsSet(!StatsOn); mi.Checked = StatsOn; };
            items.Add(mi);
        }
        void StatsSet(bool on)
        {
            if (!Stats.Available) return;
            StatsLoad();
            statsState["on"] = on ? "1" : "0";
            StatsSave();
            App.Log("stats: " + (on ? "on" : "off"));
            Lead().Say(on ? "好～會匿名回報你選了哪一櫃" : "好～不回報了，什麼都不會送出去", 2);
        }
        void StatsAct(string arg) { if (arg == "0" || arg == "1") StatsSet(arg == "1"); }

        // 測試用：stats-dump、stats-payload <事件> <櫃>
        bool StatsMsg(Client c, string[] p, string line)
        {
            switch (p[0])
            {
                case "stats-dump":
                    StatsLoad();
                    Send(c, "stats public=" + (App.Public ? 1 : 0) + " available=" + (Stats.Available ? 1 : 0) + " on=" + (StatsOn ? 1 : 0)
                        + " installed=" + (StatsGet("installed") == "" ? "-" : StatsGet("installed")) + " pick=" + (StatsGet("pick") == "" ? "-" : StatsGet("pick"))
                        + " day7=" + (StatsGet("day7") == "" ? "-" : StatsGet("day7")) + " platform=" + Stats.Platform + " version=" + (Stats.Available ? Stats.AppVersion : "-") + "\nend\n");
                    return true;
                case "stats-payload":
                    Send(c, (p.Length >= 3 && Stats.Available ? Stats.Payload(p[1], p[2]) : "-") + "\nend\n");
                    return true;
            }
            return false;
        }
    }
}
