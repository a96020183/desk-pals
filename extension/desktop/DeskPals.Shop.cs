// 錢的部分（0.11）：兌換碼、打卡冊、季節商品（造型、櫃子外觀）、商店設定、續命小隊的喝水提醒。只有資料和規則，畫面另外做。
// 掛在別的檔的地方（都只有一兩行，標「商店」）：
//   DeskPals.cs：TickInner → ShopTick()、OnMsg 的 default → ShopMsg()、FeatureList＋WorkFeats 的 sq_water、ShelfArt 的外觀（Skin）
//   DeskPals.Custom.cs：CuCompose 畫配件（SqCostume.Draw）、CuCanvasSize 加上配件超出的範圍
//   DeskPals.Original.cs：OrigTick → WaterTick（喝水提醒兩櫃共用）、沒電的 o_water 台詞
//   DeskPals.Woban.cs：WbTick 不再管喝水（搬來這裡）
// 存檔（%DataDir%，只在這台電腦）：
//   redeemed.txt  兌換過的碼，一行一組（存碼本身，每次開都重新驗；只改檔案加項目沒有用）
//   stamps.txt    打卡冊蓋過章的日子，一行一個 yyyy-MM-dd（本地日期；沒來的日子不會歸零，是收集不是連續）
//   wear.txt      穿什麼：costume.<lineup>=<造型 id>、cabinet.<lineup>=<櫃子外觀 id>
// 商店設定（價錢、綠界收款連結、FPS 識別碼、預約表單）：pals/shop.txt（跟其他 pals 檔一起內嵌進 exe）
// 測試用（只在離屏模式）：DESKPALS_CLOCK＝一開始的假時間（yyyy-MM-ddTHH:mm，之後用 study-clock 改）、DESKPALS_CODE_TESTKEY＝多收一把測試公鑰（X、Y 各 64 個十六進位字接在一起）、DESKPALS_SHOP_FILE＝改讀這份商店設定、
//   shop-open <要開什麼>（只記下網址不開瀏覽器）、shop-water-skip <分鐘>、shop-render <公仔> <動作> <png>
// pipe：shop-info、shop-redeem <碼>、shop-wear costume|cabinet <id>、shop-water
namespace DeskPals
{
    using System;
    using System.Collections.Generic;
    using System.Diagnostics;
    using System.Drawing;
    using System.Drawing.Drawing2D;
    using System.Drawing.Imaging;
    using System.IO;
    using System.Security.Cryptography;
    using System.Text;

    // ================= 兌換碼：離線驗（ECDSA P-256＋SHA-256，App 只有公鑰；發碼工具在 repo 外面）=================
    // 碼＝6 個位元組（版本 1、項目、日期＝2026-01-01 起第幾天、流水號）＋64 位元組簽章（r‖s）→ Crockford base32 112 個字，4 個字一組用 - 隔開。
    // 簽的內容＝"WoWoPals-code-v1"＋那 6 個位元組。不綁電腦：同一組碼在自己的另一台電腦也能再輸入一次。
    static class ShopCodes
    {
        public const string PubX = "7434d12d51eecaaf0615633afdce1a555b4a1d64937d303f6a882392df114b25", PubY = "717de3a0e8a7fd2422df19f314847f1e441b282919fbd0223c90c4316d4df112";
        public const string Alpha = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
        public const int Bytes = 70, Chars = 112;
        static readonly byte[] Domain = Encoding.ASCII.GetBytes("WoWoPals-code-v1");
        public static readonly string[] Items = { "xmas-costume", "xmas-cabinet", "exam-costume", "exam-cabinet" };   // 第 i 個＝第 i 個位元
        static readonly DateTime Epoch = new DateTime(2026, 1, 1);

        public class Code { public string Text; public string[] Items; public DateTime Date; public int Id; }

        // 使用者打的字 → 只留碼的字（大小寫都可以、O 當 0、I 和 L 當 1、空白和 - 不算）；有不是碼的字＝null
        public static string Clean(string s)
        {
            if (s == null) return null;
            StringBuilder b = new StringBuilder();
            foreach (char c0 in s.ToUpperInvariant())
            {
                char c = c0 == 'O' ? '0' : (c0 == 'I' || c0 == 'L' ? '1' : c0);
                if (c == '-' || c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '　' || c == '‐' || c == '‑' || c == '–' || c == '—' || c == '－') continue;
                if (Alpha.IndexOf(c) < 0) return null;
                b.Append(c);
            }
            return b.ToString();
        }

        // 4 個字一組
        public static string Pretty(string clean)
        {
            StringBuilder b = new StringBuilder();
            for (int i = 0; i < clean.Length; i++) { if (i > 0 && i % 4 == 0) b.Append('-'); b.Append(clean[i]); }
            return b.ToString();
        }

        static byte[] Decode(string clean)
        {
            if (clean == null || clean.Length != Chars) return null;
            byte[] o = new byte[Bytes];
            int acc = 0, nb = 0, k = 0;
            foreach (char c in clean)
            {
                acc = (acc << 5) | Alpha.IndexOf(c); nb += 5;
                if (nb >= 8) { nb -= 8; o[k++] = (byte)(acc >> nb); acc &= (1 << nb) - 1; }
            }
            return k == Bytes ? o : null;
        }

        static byte[] Hex(string h) { byte[] b = new byte[h.Length / 2]; for (int i = 0; i < b.Length; i++) b[i] = Convert.ToByte(h.Substring(i * 2, 2), 16); return b; }

        static List<ECDsaCng> keys;
        static List<ECDsaCng> Keys()
        {
            if (keys != null) return keys;
            keys = new List<ECDsaCng>();
            keys.Add(Key(PubX + PubY));
            string t = Environment.GetEnvironmentVariable("DESKPALS_CODE_TESTKEY");
            if (App.Offscreen && !string.IsNullOrEmpty(t) && t.Length == 128) { try { keys.Add(Key(t)); } catch (Exception ex) { App.Log("shop: test key: " + ex.Message); } }
            return keys;
        }

        // BCRYPT_ECCKEY_BLOB：ECS1（P-256 公鑰）、長度 32、X、Y
        static ECDsaCng Key(string xy)
        {
            byte[] b = new byte[8 + 64];
            BitConverter.GetBytes(0x31534345).CopyTo(b, 0);
            BitConverter.GetBytes(32).CopyTo(b, 4);
            Hex(xy).CopyTo(b, 8);
            ECDsaCng e = new ECDsaCng(CngKey.Import(b, CngKeyBlobFormat.EccPublicBlob));
            e.HashAlgorithm = CngAlgorithm.Sha256;
            return e;
        }

        // 驗：不對（打錯、假的、改過的）＝null
        public static Code Check(string text)
        {
            string c = Clean(text);
            byte[] raw = Decode(c);
            if (raw == null || raw[0] != 1) return null;
            byte[] msg = new byte[Domain.Length + 6], sig = new byte[64];
            Domain.CopyTo(msg, 0);
            Array.Copy(raw, 0, msg, Domain.Length, 6);
            Array.Copy(raw, 6, sig, 0, 64);
            bool ok = false;
            try { foreach (ECDsaCng k in Keys()) if (k.VerifyData(msg, sig)) { ok = true; break; } }
            catch (Exception ex) { App.Log("shop: verify: " + ex.Message); }
            if (!ok) return null;
            List<string> it = new List<string>();
            for (int i = 0; i < Items.Length; i++) if ((raw[1] & (1 << i)) != 0) it.Add(Items[i]);
            Code r = new Code();
            r.Text = c; r.Items = it.ToArray(); r.Date = Epoch.AddDays((raw[2] << 8) | raw[3]); r.Id = (raw[4] << 8) | raw[5];
            return r;
        }
    }

    // ================= 造型：疊在原本 16 張動作圖上的配件（格式見 pals/<資料夾>/<公仔>/costume/<造型>/costume.txt 的註解）=================
    // 座標＝2x 圖的像素（1x 除以 2），原點＝公仔原圖左上角；配件圖在 <1x|2x>/<名稱>.png（續命小隊另有同尺寸的白邊 <名稱>.halo.png）。
    // 畫法（跟美術的 tools/costume.py compose() 一樣）：全部配件的白邊 → back 配件 → 公仔原圖（沒電先上完電量的色）→ front 配件；
    //   每件：左右翻轉 → 縮放 → 以圖的中心順時針轉 → 中心對到 (x, y)。執行時跟著公仔一起轉、翻、縮，所以不用另外存合成好的圖。
    class SqCostume
    {
        public string Id = "";
        public int PadL, PadT, PadR, PadB;      // 配件最多超出原畫布多少（這個解析度的像素）
        public float K = 1;                     // 2x 座標 → 這個解析度
        class Piece { public Bitmap Img, Halo; public bool Back; public float X, Y, Rot, Sc; public bool Flip; }
        readonly Dictionary<string, List<Piece>> poses = new Dictionary<string, List<Piece>>();
        static readonly Dictionary<string, SqCostume> cache = new Dictionary<string, SqCostume>();

        public static string Dir(string palId, string costume)
        {
            SqLineup q = SqArt.LineupOf(palId);
            return q == null ? null : q.Dir + "/" + palId + "/costume/" + costume;
        }
        public static bool Exists(string palId, string costume) { string d = Dir(palId, costume); return d != null && SqArt.Read(d + "/costume.txt") != null; }

        // 這隻公仔有美術的造型 id（pals/<lu>/<pal>/costume/<id>/costume.txt 存在的）：讓造型清單能自己發現新造型
        public static List<string> ListIds(string palId)
        {
            List<string> o = new List<string>();
            SqLineup q = SqArt.LineupOf(palId);
            if (q == null) return o;
            string parent = q.Dir + "/" + palId + "/costume";
            foreach (string id in SqArt.SubDirs(parent)) if (SqArt.Read(parent + "/" + id + "/costume.txt") != null) o.Add(id);
            return o;
        }

        // r＝1（1x）或 2（2x）。讀不到（還沒有圖）＝null，公仔照原本的樣子
        public static SqCostume Load(string palId, string costume, int r)
        {
            if (string.IsNullOrEmpty(costume)) return null;
            string key = palId + "/" + costume + "/" + r;
            SqCostume c;
            if (cache.TryGetValue(key, out c)) return c;
            c = Parse(palId, costume, r);
            cache[key] = c;
            return c;
        }

        static SqCostume Parse(string palId, string costume, int r)
        {
            string d = Dir(palId, costume);
            byte[] meta = d == null ? null : SqArt.Read(d + "/costume.txt");
            if (meta == null) { App.Log("costume missing: " + palId + " " + costume); return null; }
            SqCostume c = new SqCostume();
            c.Id = costume; c.K = r == 1 ? 0.5f : 1f;
            Dictionary<string, Bitmap> imgs = new Dictionary<string, Bitmap>(), halos = new Dictionary<string, Bitmap>();
            System.Globalization.CultureInfo inv = System.Globalization.CultureInfo.InvariantCulture;
            foreach (string line in Encoding.UTF8.GetString(meta).Split('\n'))
            {
                string t = line.Trim().TrimStart('﻿');
                if (t == "" || t.StartsWith("#")) continue;
                string[] a = t.Split(new char[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                if (a[0] == "pad" && a.Length >= 5)
                {
                    int[] v = new int[4];
                    for (int i = 0; i < 4; i++) int.TryParse(a[i + 1], out v[i]);
                    c.PadL = (int)(v[0] * c.K); c.PadT = (int)(v[1] * c.K); c.PadR = (int)(v[2] * c.K); c.PadB = (int)(v[3] * c.K);
                    continue;
                }
                if (a[0] == "piece" && a.Length >= 2)
                {
                    Bitmap b = SqArt.Png(d + "/" + r + "x/" + a[1] + ".png");
                    if (b == null) { App.LogAlways("costume piece missing: " + d + "/" + r + "x/" + a[1] + ".png"); continue; }
                    imgs[a[1]] = b;
                    Bitmap h = SqArt.Png(d + "/" + r + "x/" + a[1] + ".halo.png");
                    if (h != null) halos[a[1]] = h;
                    continue;
                }
                if (a.Length < 8 || Array.IndexOf(SqArt.Keys, a[0]) < 0) continue;
                Bitmap im;
                if (!imgs.TryGetValue(a[1], out im)) continue;
                Piece p = new Piece();
                p.Img = im; halos.TryGetValue(a[1], out p.Halo);
                p.Back = a[2] == "back";
                float x, y, rot, sc;
                if (!float.TryParse(a[3], System.Globalization.NumberStyles.Float, inv, out x) || !float.TryParse(a[4], System.Globalization.NumberStyles.Float, inv, out y)
                    || !float.TryParse(a[5], System.Globalization.NumberStyles.Float, inv, out rot) || !float.TryParse(a[6], System.Globalization.NumberStyles.Float, inv, out sc)) continue;
                p.X = x * c.K; p.Y = y * c.K; p.Rot = rot; p.Sc = sc; p.Flip = a[7] == "1";
                List<Piece> l;
                if (!c.poses.TryGetValue(a[0], out l)) { l = new List<Piece>(); c.poses[a[0]] = l; }
                l.Add(p);
            }
            return c;
        }

        public int Count(string frame) { List<Piece> l; return frame != null && poses.TryGetValue(frame, out l) ? l.Count : 0; }

        // 畫在原圖下面的：白邊、back 配件。m＝畫公仔原圖用的同一個轉換，(L, T)＝原圖左上角
        public void DrawUnder(Graphics g, Matrix m, string frame, float L, float T)
        {
            List<Piece> l;
            if (frame == null || !poses.TryGetValue(frame, out l)) return;
            foreach (Piece p in l) if (p.Halo != null) Put(g, m, p, p.Halo, L, T);
            foreach (Piece p in l) if (p.Back) Put(g, m, p, p.Img, L, T);
        }
        public void DrawOver(Graphics g, Matrix m, string frame, float L, float T)
        {
            List<Piece> l;
            if (frame == null || !poses.TryGetValue(frame, out l)) return;
            foreach (Piece p in l) if (!p.Back) Put(g, m, p, p.Img, L, T);
        }

        static void Put(Graphics g, Matrix m, Piece p, Bitmap img, float L, float T)
        {
            using (Matrix pm = m.Clone())
            {
                pm.Translate(L + p.X, T + p.Y);
                if (Math.Abs(p.Rot) > 0.01) pm.Rotate(p.Rot);
                pm.Scale(p.Flip ? -p.Sc : p.Sc, p.Sc);
                g.Transform = pm;
                g.DrawImage(img, new RectangleF(-img.Width / 2f, -img.Height / 2f, img.Width, img.Height), new RectangleF(0, 0, img.Width, img.Height), GraphicsUnit.Pixel);
            }
            g.ResetTransform();
        }

        // 一張動作圖穿上造型（原畫布四邊加 pad）：測試、預覽用
        public static Bitmap Render(CuSprite s, string frame)
        {
            Bitmap fr;
            if (!s.Frames.TryGetValue(frame, out fr)) return null;
            if (s.Liquid != null) { Bitmap lq = SqBattery.Frame(s, frame); if (lq != null) fr = lq; }
            SqCostume c = s.Costume;
            int pl = c == null ? 0 : c.PadL, pt = c == null ? 0 : c.PadT;
            Bitmap o = new Bitmap(fr.Width + pl + (c == null ? 0 : c.PadR), fr.Height + pt + (c == null ? 0 : c.PadB), PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(o))
            using (Matrix m = new Matrix())
            {
                g.Clear(Color.Transparent);
                g.InterpolationMode = InterpolationMode.HighQualityBicubic; g.PixelOffsetMode = PixelOffsetMode.HighQuality; g.CompositingQuality = CompositingQuality.HighQuality;
                if (c != null) c.DrawUnder(g, m, frame, pl, pt);
                g.DrawImage(fr, new Rectangle(pl, pt, fr.Width, fr.Height), 0, 0, fr.Width, fr.Height, GraphicsUnit.Pixel);
                if (c != null) c.DrawOver(g, m, frame, pl, pt);
            }
            return o;
        }
    }

    // ================= 季節商店的設定（pals/shop.txt）=================
    static class ShopConfig
    {
        static Dictionary<string, string> v;
        static List<string> order;          // key 的出現順序（Dictionary 不保證順序，清單要照設定檔排）
        public static string Source = "";
        public static Dictionary<string, string> All()
        {
            if (v != null) return v;
            v = new Dictionary<string, string>();
            order = new List<string>();
            string f = App.Offscreen ? Environment.GetEnvironmentVariable("DESKPALS_SHOP_FILE") : null;
            byte[] b = null;
            if (!string.IsNullOrEmpty(f)) { try { b = File.ReadAllBytes(f); Source = "file"; } catch { b = null; } }
            if (b == null) { b = SqArt.Read("shop.txt"); Source = b == null ? "none" : "pals"; }
            if (b == null) { App.LogAlways("pals/shop.txt missing"); return v; }
            foreach (string line in Encoding.UTF8.GetString(b).Split('\n'))
            {
                string t = line.Trim().TrimStart('﻿');
                if (t == "" || t.StartsWith("#")) continue;
                int eq = t.IndexOf('=');
                if (eq <= 0) continue;
                string key = t.Substring(0, eq).Trim();
                if (!v.ContainsKey(key)) order.Add(key);
                v[key] = t.Substring(eq + 1).Trim();
            }
            return v;
        }
        public static string Get(string key) { string s; return All().TryGetValue(key, out s) ? s : ""; }
        public static void Reload() { v = null; rewards = null; sellables = null; }

        // ========= 資料驅動的清單：打卡獎勵階梯、季節商店賣的（都可以只改 pals/shop.txt／丟美術，不用改程式）=========
        // 打卡獎勵：`reward.<天數> = <造型 id> <顯示名>`（例 `reward.90 = pajama 睡衣`）。沒設定時用內建的 scarf 30／grad 60。
        // 季節商品：`costume.<id>` 或 `cabinet.<id> = <顯示名> | <兌換碼項目> | <NT 價> | <HK 價>`（後三項可省；兌換碼項目省略＝<id>-<kind>）。
        public class Reward { public int Days; public string Id = ""; public string Name = ""; }
        public class Sellable { public string Kind = "", Id = "", Name = "", CodeItem = "", Twd = "", Hkd = ""; }
        static List<Reward> rewards;
        static List<Sellable> sellables;

        public static List<Reward> Rewards()
        {
            if (rewards != null) return rewards;
            All();
            List<Reward> l = new List<Reward>();
            foreach (string k in order)
            {
                if (!k.StartsWith("reward.")) continue;
                int days;
                if (!int.TryParse(k.Substring(7), out days) || days <= 0) continue;
                string[] a = v[k].Split(new char[] { ' ', '\t' }, 2, StringSplitOptions.RemoveEmptyEntries);
                if (a.Length == 0 || a[0] == "") continue;
                Reward r = new Reward();
                r.Days = days; r.Id = a[0].Trim(); r.Name = a.Length > 1 ? a[1].Trim() : a[0].Trim();
                l.Add(r);
            }
            if (l.Count == 0)   // 內建預設（設定檔沒寫時）
            {
                l.Add(MkReward(30, "scarf", "同款小圍巾"));
                l.Add(MkReward(60, "grad", "畢業帽"));
            }
            l.Sort(delegate(Reward x, Reward y) { return x.Days.CompareTo(y.Days); });
            rewards = l;
            return l;
        }
        static Reward MkReward(int d, string id, string nm) { Reward r = new Reward(); r.Days = d; r.Id = id; r.Name = nm; return r; }

        public static List<Sellable> Sellables()
        {
            if (sellables != null) return sellables;
            All();
            List<Sellable> l = new List<Sellable>();
            foreach (string k in order)
            {
                string kind = k.StartsWith("costume.") ? "costume" : (k.StartsWith("cabinet.") ? "cabinet" : null);
                if (kind == null) continue;
                string id = k.Substring(kind.Length + 1).Trim();
                if (id == "") continue;
                string[] f = v[k].Split('|');
                Sellable s = new Sellable();
                s.Kind = kind; s.Id = id;
                s.Name = f.Length > 0 && f[0].Trim() != "" ? f[0].Trim() : id;
                s.CodeItem = f.Length > 1 && f[1].Trim() != "" ? f[1].Trim() : id + "-" + kind;
                s.Twd = f.Length > 2 ? f[2].Trim() : "";
                s.Hkd = f.Length > 3 ? f[3].Trim() : "";
                l.Add(s);
            }
            if (l.Count == 0)   // 內建預設
            {
                l.Add(MkSell("costume", "xmas", "聖誕造型", "xmas-costume"));
                l.Add(MkSell("cabinet", "xmas", "聖誕", "xmas-cabinet"));
                l.Add(MkSell("costume", "exam", "期末考造型", "exam-costume"));
                l.Add(MkSell("cabinet", "exam", "期末考", "exam-cabinet"));
            }
            sellables = l;
            return l;
        }
        static Sellable MkSell(string kind, string id, string nm, string code) { Sellable s = new Sellable(); s.Kind = kind; s.Id = id; s.Name = nm; s.CodeItem = code; return s; }

        public static Reward RewardFor(string costumeId) { foreach (Reward r in Rewards()) if (r.Id == costumeId) return r; return null; }
        public static Sellable SellFor(string kind, string id) { foreach (Sellable s in Sellables()) if (s.Kind == kind && s.Id == id) return s; return null; }
        public static int LastRewardDays() { List<Reward> r = Rewards(); return r.Count == 0 ? 60 : r[r.Count - 1].Days; }

        // 要開的網址：<項目>（xmas-costume…）、coffee-1～3、custom（訂做公仔的預約表單）。沒填＝""（畫面上那顆按鈕先不顯示）
        public static string Link(string what)
        {
            string k = what == "custom" ? "custom_form" : "ecpay_" + what.Replace('-', '_');
            string u = Get(k);
            return u.StartsWith("https://") || u.StartsWith("http://") ? u : "";
        }
    }

    partial class World
    {
        // ---------------- 兌換過的 ----------------
        readonly List<string> codes = new List<string>();          // 驗過的碼（Clean 過）
        readonly HashSet<string> owned = new HashSet<string>();    // 有的項目（xmas-costume…）
        bool shopLoaded;

        void ShopLoad()
        {
            // 測試：一開始就用假時鐘（第一格就會蓋章，等 pipe 再送 study-clock 就晚了）；只在離屏模式
            string fc = !shopLoaded && App.Offscreen ? Environment.GetEnvironmentVariable("DESKPALS_CLOCK") : null;
            DateTime fd;
            if (!string.IsNullOrEmpty(fc) && DateTime.TryParse(fc, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out fd)) studyShift = fd - DateTime.Now;
            shopLoaded = true;
            codes.Clear(); owned.Clear();
            foreach (string line in ReadText("redeemed.txt").Split('\n'))
            {
                ShopCodes.Code c = ShopCodes.Check(line);
                if (c == null) { if (line.Trim() != "") App.Log("shop: redeemed.txt has a bad line"); continue; }
                if (codes.Contains(c.Text)) continue;
                codes.Add(c.Text);
                foreach (string it in c.Items) owned.Add(it);
            }
            stamps.Clear();
            foreach (string line in ReadText("stamps.txt").Split('\n'))
            {
                DateTime d;
                string t = line.Trim();
                if (DateTime.TryParseExact(t, "yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out d) && !stamps.Contains(t)) stamps.Add(t);
            }
            wear.Clear();
            foreach (string line in ReadText("wear.txt").Split('\n'))
            {
                int eq = line.IndexOf('=');
                if (eq > 0) wear[line.Substring(0, eq).Trim()] = line.Substring(eq + 1).Trim();
            }
        }

        public bool Owns(string item) { if (!shopLoaded) ShopLoad(); return owned.Contains(item); }

        // 兌換：ok（新的）｜again（這組碼這台電腦已經兌換過）｜bad（打錯、假的、改過的）
        public string Redeem(string text, out string[] items)
        {
            if (!shopLoaded) ShopLoad();
            items = new string[0];
            ShopCodes.Code c = ShopCodes.Check(text);
            if (c == null) { App.Log("shop: redeem bad"); return "bad"; }
            items = c.Items;
            if (codes.Contains(c.Text)) return "again";
            codes.Add(c.Text);
            foreach (string it in c.Items) owned.Add(it);
            WriteText("redeemed.txt", string.Join("\n", codes.ToArray()) + "\n");
            App.Log("shop: redeemed " + string.Join(",", c.Items) + " #" + c.Id);
            return "ok";
        }

        // ---------------- 打卡冊：每天第一次打開蓋一個章；30 個換長駐造型（小圍巾）----------------
        public const int StampGoal = 30;
        public const int StampGoal2 = 60;
        public const string StampCostume = "scarf";
        public const string StampCostume2 = "grad";   // 畢業帽：第二套常駐造型（美術之後補；補圖不用改程式）
        readonly List<string> stamps = new List<string>();
        string stampDay = "";
        double shopNext;
        string shopSaid = "";
        public int StampCount { get { if (!shopLoaded) ShopLoad(); return stamps.Count; } }
        public bool StampedToday { get { return stamps.Contains(SNow().ToString("yyyy-MM-dd")); } }

        void ShopTick()
        {
            if (Now < shopNext) return;
            shopNext = Now + 1;
            if (!shopLoaded) ShopLoad();
            string today = SNow().ToString("yyyy-MM-dd");
            if (today != stampDay)
            {
                stampDay = today;
                if (!stamps.Contains(today))
                {
                    stamps.Add(today);
                    WriteText("stamps.txt", string.Join("\n", stamps.ToArray()) + "\n");
                    App.Log("stamp " + today + " n=" + stamps.Count);
                    int n = stamps.Count;
                    // 一天只講一次（同一天再打開不講）；剛打開讓早上點名先講完
                    Later(App.Offscreen ? 0.5 : 8, delegate { StampSay(n); });
                }
            }
            WearApply();
        }

        // 下一階還差幾個章的里程碑（沒有更高的＝0）
        public int NextReward(int n) { foreach (ShopConfig.Reward r in ShopConfig.Rewards()) if (r.Days > n) return r.Days; return 0; }

        void StampSay(int n)
        {
            string s = null;
            foreach (ShopConfig.Reward r in ShopConfig.Rewards()) if (r.Days == n) { s = "第 " + n + " 個章，" + r.Name + "是你的了"; break; }
            if (s == null) { int next = NextReward(n); s = next > 0 ? "今天的章蓋好了 " + n + "／" + next : "今天的章蓋好了，第 " + n + " 個"; }
            shopSaid = s;
            if (Hidden || Pets.Count == 0) return;
            Lead().Say(s, 3.2);
        }

        // ---------------- 穿什麼（每一櫃各自記）----------------
        readonly Dictionary<string, string> wear = new Dictionary<string, string>();
        string wearSig = "";

        // 這一櫃能選的造型／櫃子外觀（資料驅動）：""（不穿）＋打卡獎勵（含美術未到的）＋季節商店賣的＋有美術但沒列到的。照設定順序、去重。
        public List<string> CostumeIds()
        {
            List<string> o = new List<string>(); o.Add("");
            foreach (ShopConfig.Reward r in ShopConfig.Rewards()) if (!o.Contains(r.Id)) o.Add(r.Id);
            foreach (ShopConfig.Sellable s in ShopConfig.Sellables()) if (s.Kind == "costume" && !o.Contains(s.Id)) o.Add(s.Id);
            foreach (string id in SqCostume.ListIds(PreviewPalId())) if (!o.Contains(id)) o.Add(id);
            return o;
        }
        public List<string> SkinIds()
        {
            List<string> o = new List<string>(); o.Add("");
            foreach (ShopConfig.Sellable s in ShopConfig.Sellables()) if (s.Kind == "cabinet" && !o.Contains(s.Id)) o.Add(s.Id);
            foreach (string id in SkinArtIds()) if (!o.Contains(id)) o.Add(id);
            return o;
        }
        // 這一櫃有美術的櫃子外觀 id（shelf/skin/<id>/<r>x/box.png 存在的）
        public List<string> SkinArtIds()
        {
            List<string> o = new List<string>();
            SqLineup q = SqArt.Lineup(lineup);
            string dir = q != null && SqArt.Read(q.Dir + "/shelf/shelf.txt") != null ? q.Dir + "/shelf" : "shelf";
            foreach (string id in SqArt.SubDirs(dir + "/skin")) if (SqArt.Read(dir + "/skin/" + id + "/2x/box.png") != null || SqArt.Read(dir + "/skin/" + id + "/1x/box.png") != null) o.Add(id);
            return o;
        }
        // 造型是「即將推出」：是已知項目（打卡獎勵或季節商品）但美術還沒到
        public bool CostumeSoon(string palId, string id)
        {
            if (string.IsNullOrEmpty(id) || SqCostume.Exists(palId, id)) return false;
            return ShopConfig.RewardFor(id) != null || ShopConfig.SellFor("costume", id) != null;
        }

        public string WearOf(string kind, string lu) { if (!shopLoaded) ShopLoad(); string s; return wear.TryGetValue(kind + "." + lu, out s) && CanWear(kind, s) ? s : ""; }

        // 有沒有：打卡獎勵＝章數到了；季節商品＝兌換過那個項目；都不是但有美術＝當免費可穿（丟美術即可）
        public bool CanWear(string kind, string id)
        {
            if (string.IsNullOrEmpty(id)) return true;
            if (kind == "costume") { ShopConfig.Reward r = ShopConfig.RewardFor(id); if (r != null) return StampCount >= r.Days; }
            ShopConfig.Sellable s = ShopConfig.SellFor(kind, id);
            if (s != null) return Owns(s.CodeItem);
            if (kind == "costume") return SqCostume.Exists(PreviewPalId(), id);
            return SkinArtIds().Contains(id);
        }

        // locked＝還沒有（畫面要打開商店／打卡冊）
        public string SetWear(string kind, string id)
        {
            if (kind != "costume" && kind != "cabinet") return "bad";
            if (!(kind == "costume" ? CostumeIds() : SkinIds()).Contains(id)) return "bad";
            if (!CanWear(kind, id)) return "locked";
            wear[kind + "." + lineup] = id;
            StringBuilder b = new StringBuilder();
            foreach (KeyValuePair<string, string> kv in wear) b.Append(kv.Key + "=" + kv.Value + "\n");
            WriteText("wear.txt", b.ToString());
            App.Log("wear " + kind + "." + lineup + "=" + id);
            WearApply();
            return "ok";
        }

        // 現在這一櫃的公仔換上造型、櫃子換外觀（每秒看一次有沒有變）
        void WearApply()
        {
            string cos = WearOf("costume", lineup), skin = WearOf("cabinet", lineup);
            long ids = 0;
            foreach (Pet p in Pets) if (p.P.Spr != null) ids = ids * 31 + System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(p.P.Spr);   // 圖重新讀過（換解析度）也要再穿一次
            string sig = lineup + "|" + cos + "|" + skin + "|" + ids;
            if (sig == wearSig) return;
            wearSig = sig;
            foreach (Pet p in Pets)
            {
                if (!p.P.Orig || p.P.Spr == null) continue;
                SqLineup q = SqArt.LineupOf(p.P.Id);
                string want = q != null && q.Id == lineup ? cos : "";   // 來我的櫃作客的照舊
                p.P.Spr.Costume = SqCostume.Load(p.P.Id, want, p.P.Spr.R <= 4 ? 1 : 2);
            }
            ShelfArt.SkinOf = delegate(string lu) { return WearOf("cabinet", lu); };
            ShelfArt.For(lineup);   // 現在這一櫃的櫃子換外觀（櫃子每一格都重畫，下一格就看得到）
        }

        // ---------------- 喝水提醒：窩伴小世界由破破、續命小隊由沒電（插著充電，你也喝口水）----------------
        public const double WaterMin = 45;   // 連續用電腦幾分鐘提醒一次（離開電腦就重算）
        double waterT;
        string waterLast = "";

        bool WaterAway() { return studyIdleFake >= 0 ? studyIdleFake > idleMin * 60 : sysIdle; }

        void WaterTick(double dt)
        {
            if (WaterAway()) { waterT = 0; return; }
            waterT += dt;
            WaterCheck();
        }

        void WaterCheck()
        {
            if (waterT < WaterMin * 60) return;
            string who = WobanLineup ? "bobo" : (lineup == Pal.Original ? "meidian" : null);
            string feat = WobanLineup ? "wb_water" : "sq_water";
            if (who == null) { waterT = 0; return; }
            if (scene != null || Hidden || focusOn || quietOn || !Feat(feat)) return;   // 忙的時候先不吵：等一下再講
            Pet b = Get(who);
            if (b == null || !b.Out || !b.Grounded() || b.InScene) return;
            waterT = 0;
            waterLast = who;
            if (who == "bobo") b.WbWater(); else b.SqWater();
        }

        // ---------------- pipe ----------------
        string shopOpened = "";
        public void ShopOpen(string what)
        {
            string u = ShopConfig.Link(what);
            shopOpened = u;
            App.Log("shop: open " + what + (u == "" ? " (not set)" : ""));
            if (u == "" || App.Offscreen) return;
            try { Process.Start(new ProcessStartInfo(u) { UseShellExecute = true }); } catch (Exception ex) { App.Log("shop: open: " + ex.Message); }
        }

        bool ShopMsg(Client c, string[] p, string line)
        {
            if (!p[0].StartsWith("shop-")) return false;
            if (!shopLoaded) ShopLoad();
            string t = line.Trim();
            switch (p[0])
            {
                case "shop-info":
                    {
                        StringBuilder b = new StringBuilder();
                        string[] own = new string[owned.Count]; owned.CopyTo(own);
                        Array.Sort(own, StringComparer.Ordinal);
                        b.Append("owned " + (own.Length == 0 ? "-" : string.Join(",", own)) + "\n");
                        b.Append("codes " + codes.Count + "\n");
                        b.Append("stamps " + stamps.Count + " today=" + (StampedToday ? 1 : 0) + " last=" + (stamps.Count == 0 ? "-" : stamps[stamps.Count - 1]) + "\n");
                        b.Append("said " + (shopSaid == "" ? "-" : shopSaid) + "\n");
                        b.Append("wear costume=" + WearOf("costume", lineup) + " cabinet=" + WearOf("cabinet", lineup) + " lineup=" + lineup + "\n");
                        foreach (Pet x in Pets) if (x.P.Orig && x.P.Spr != null) b.Append("pal " + x.P.Id + " costume=" + (x.P.Spr.Costume == null ? "-" : x.P.Spr.Costume.Id) + "\n");
                        b.Append("skin " + (shelf == null ? "-" : shelf.Kit.Dir + ":" + (shelf.Kit.Skin == "" ? "-" : shelf.Kit.Skin) + ":" + (shelf.Kit.SkinArt ? 1 : 0)) + "\n");
                        ShopConfig.All();   // 先讀設定檔，Source 才有值
                        b.Append("config " + ShopConfig.Source + "\n");
                        foreach (KeyValuePair<string, string> kv in ShopConfig.All()) b.Append("cfg " + kv.Key + "=" + kv.Value + "\n");
                        Send(c, b + "end\n");
                    }
                    break;
                case "shop-redeem":
                    {
                        string[] it;
                        string r = Redeem(p.Length >= 2 ? t.Substring(t.IndexOf(' ') + 1) : "", out it);
                        Send(c, "redeem " + r + " " + (it.Length == 0 ? "-" : string.Join(",", it)) + "\nend\n");
                    }
                    break;
                case "shop-wear": Send(c, "wear " + (p.Length >= 3 ? SetWear(p[1], p[2] == "-" ? "" : p[2]) : (p.Length == 2 ? SetWear(p[1], "") : "bad")) + "\nend\n"); break;
                case "shop-water": Send(c, "water t=" + (int)waterT + " last=" + (waterLast == "" ? "-" : waterLast) + "\nend\n"); break;
                default:
                    if (!App.Offscreen) break;
                    switch (p[0])
                    {
                        case "shop-open": ShopOpen(p.Length >= 2 ? p[1] : ""); Send(c, "open " + (shopOpened == "" ? "-" : shopOpened) + "\nend\n"); break;
                        case "shop-water-skip": { double m; if (p.Length >= 2 && double.TryParse(p[1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out m)) { if (!WaterAway()) { waterT += m * 60; if (waterT < 0) waterT = 0; } WaterCheck(); } Send(c, "water t=" + (int)waterT + " last=" + (waterLast == "" ? "-" : waterLast) + "\nend\n"); } break;
                        case "shop-render":
                            {
                                Pet x = p.Length >= 4 ? Get(p[1]) : null;
                                Bitmap o = x == null || x.P.Spr == null ? null : SqCostume.Render(x.P.Spr, p[2]);
                                if (o != null) { try { o.Save(t.Substring(NthSpace(t, 3) + 1), ImageFormat.Png); } catch (Exception ex) { App.Log("shop-render: " + ex.Message); } }
                                Send(c, "render " + (o == null ? "none" : o.Width + "x" + o.Height + " r=" + x.P.Spr.R) + "\nend\n");
                                if (o != null) o.Dispose();
                            }
                            break;
                    }
                    break;
            }
            return true;
        }
    }

    partial class Pet
    {
        // 沒電：喝水提醒（World.WaterTick 定時叫）。插上充電，你也喝口水
        public void SqWater()
        {
            WakeIfSleep();
            if (Grounded()) OrigDo("charge", 3.4);
            Say(L("o_water"), 4);
            App.Log("squad: water reminder");
        }
    }
}
