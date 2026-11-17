// 桌面版「搗蛋」四個玩法的離屏測試（DESKPALS_OFFSCREEN=1 跑起來的桌面版，用 pipe 的測試指令驅動）：
//   搶游標、下班清場、購物警察、打字太兇。離屏模式一定用假的 MisFake：不會動到真的游標、視窗、鍵盤，
//   這裡用 mischief-fake 假裝「滑鼠停很久／你動了／前景是購物網站／打字很快／有兩個視窗／現在 18:05」，再看 mischief-dump。
// 用法：先用離屏模式啟動桌面版（pipe 名稱自訂；建議 DESKPALS_ISOLATED=1），再
//   node test/desktop-mischief.js <pipe> [截圖資料夾] [desk-pals.log 的路徑]
//   Mac：<pipe> 換成 unix socket 的路徑（桌面版的 argv[1]）。給了 log 路徑就順便檢查「收工前會把視窗叫回來」。
//   最後會送 quit（桌面版會收工）。MIS_PET＝要放出來的公仔（預設 duoduo，續命小隊的躲躲）。
const net = require("net");
const fs = require("fs");
const path = require("path");
const assert = require("node:assert/strict");

const pipe = process.argv[2] || "desk-pals-mistest";
const shots = (process.argv[3] || path.join(__dirname, "..", "shots-mischief")).replace(/\\/g, "/");
const logFile = process.argv[4] || "";
const PET = process.env.MIS_PET || "duoduo";

const s = net.connect(pipe.includes("/") ? pipe : "\\\\.\\pipe\\" + pipe);
s.setEncoding("utf8");
let buf = "";
s.on("data", (d) => { buf += d; });
s.on("error", (e) => { console.error("PIPE", e.message); process.exit(2); });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const send = (l) => s.write(l + "\n");

async function reply(cmd, done) {
	buf = "";
	send(cmd);
	for (let i = 0; i < 250 && !done(buf); i++) await sleep(40);   // 截圖在慢的機器上要好幾秒
	return buf;
}
async function dump() {
	const out = await reply("mischief-dump", (b) => /\nend\n/.test("\n" + b));
	const t = out.slice(out.indexOf("mischief "));
	return t.slice(0, t.indexOf("\nend\n") + 1);
}
async function where() {
	const out = await reply("where", (b) => /(^|\n)end\n/.test(b));
	const m = /pos (\S+) (-?\d+) (-?\d+) (\S+)/.exec(out);
	return m ? { id: m[1], x: +m[2], y: +m[3], state: m[4] } : null;
}
async function site(title) {
	const out = await reply("mischief-site " + title, (b) => /site .*\n/.test(b));
	return /site (.*)\n/.exec(out)[1];
}
async function snap(name) { await reply(`snap ${shots}/${name}.png`, (b) => b.includes("snapped")); }
const field = (d, k) => (new RegExp(`\\b${k}=(\\S*)`).exec(d.split("\n")[0]) || [])[1];
const fake = (d, k) => (new RegExp(`\\b${k}=(\\S*)`).exec(d.split("\n").find((l) => l.startsWith("fake ")) || "") || [])[1];
const calls = (d) => d.split("\n").filter((l) => l.startsWith("call ")).map((l) => l.slice(5));
const warps = (d) => +fake(d, "warps");
const cursor = (d) => fake(d, "cursor").split(",").map(Number);
// 等到 dump 符合條件（或時間到，回傳最後一次）。時間給得寬：CI 的機器慢、截圖會卡住主迴圈，公仔動畫的時間會比牆上時間走得慢
async function until(pred, ms) {
	let d = "";
	for (const end = Date.now() + ms; Date.now() < end;) { d = await dump(); if (pred(d)) return d; await sleep(200); }
	return d;
}
const kindIs = (k) => (d) => field(d, "kind") === k;

const results = [];
async function check(name, fn) {
	try { await fn(); results.push(["PASS", name]); }
	catch (e) { results.push(["FAIL", name + "\n      " + String(e.message).split("\n").slice(0, 12).join("\n      ")]); }
}
const restoredCount = () => { try { return (fs.readFileSync(logFile, "utf8").match(/mischief: restored 2 window/g) || []).length; } catch (e) { return 0; } };

s.on("connect", async () => {
	send("hello");
	await sleep(1500);
	send(`act out ${PET}`);
	await sleep(3500);
	send("mischief-fake reset");
	let d = await dump();
	const pos = (await where()) || { x: 400, y: 600 };
	// 游標放在公仔上方（不管螢幕多大都在畫面裡）
	const cx = pos.x > 420 ? pos.x - 300 : pos.x + 300, cy = Math.max(80, pos.y - 260);

	await check("離屏測試一定用假的副作用（不碰真的游標、視窗、鍵盤）；預設：搶游標、打字太兇關，其他開", () => {
		assert.equal(field(d, "backend"), "fake");
		assert.deepEqual(["grab", "clear", "shop", "typing", "grabmin"].map((k) => field(d, k)), ["0", "1", "1", "0", "3"]);
	});
	// 公開版全新安裝四個都關（test/desktop-store.js 測）；這裡的資料夾已經有 profile.txt＝舊使用者升級：照原本的預設轉過去、不再問
	if (field(d, "edition") === "public") await check("公開版舊使用者：照原本的開關轉過去（下班清場、購物警察算打開過，不跳說明）", () => assert.equal(field(d, "ack"), "clear,shop"));

	// ---------- 搶游標 ----------
	send(`mischief-fake cursor ${cx} ${cy}`);
	send("mischief-fake idle 400");
	await sleep(2000);
	d = await dump();
	await check("搶游標：預設關著，滑鼠停很久也不搶", () => { assert.equal(field(d, "kind"), "-"); assert.equal(warps(d), 0); });

	send("mischief-set grab 1");
	send("mischief-fake button 1");
	await sleep(1500);
	d = await dump();
	await check("搶游標：按著滑鼠鍵時絕不開始", () => { assert.equal(field(d, "grab"), "1"); assert.equal(field(d, "kind"), "-"); assert.equal(warps(d), 0); });
	send("mischief-fake button 0");
	send("mischief-fake fs 1");
	await sleep(1500);
	d = await dump();
	await check("搶游標：全螢幕（遊戲、影片）時絕不開始", () => { assert.equal(field(d, "kind"), "-"); assert.equal(warps(d), 0); });
	send("mischief-fake fs 0");
	send("mischief-fake fg 期末報告.pptx - PowerPoint 投影片放映");
	await sleep(1500);
	d = await dump();
	await check("搶游標：簡報播放中絕不開始", () => { assert.equal(field(d, "kind"), "-"); assert.equal(warps(d), 0); });
	send("mischief-fake fg ");

	d = await until(kindIs("grab"), 6000);
	await check("搶游標：滑鼠鍵盤都沒動 3 分鐘 → 開始搶", () => assert.equal(field(d, "kind"), "grab"));
	await sleep(1800);
	await snap("01-grab-hold");
	await sleep(1500);
	await snap("02-grab-carry");
	d = await until(kindIs("-"), 20000);
	await check("搶游標：叼著游標跑一段、放下（最多幾秒）", () => {
		assert.equal(field(d, "kind"), "-");
		assert.ok(warps(d) > 10, "warps=" + warps(d));
		const [x, y] = cursor(d);
		assert.ok(Math.abs(x - cx) + Math.abs(y - cy) > 60, `cursor ${x},${y} from ${cx},${cy}`);
		assert.ok(y > cy, "cursor should end lower (dragged to the floor): " + y);
	});
	await snap("03-grab-drop");
	await sleep(1500);
	d = await dump();
	await check("搶游標：同一段沒動只搶一次（之後有冷卻）", () => assert.equal(field(d, "kind"), "-"));

	// 你一動就放手
	send("mischief-fake input");
	send("act mischief cursor");
	await sleep(2600);
	d = await dump();
	const w0 = warps(d);
	await check("搶游標：測試指令可以直接演（act mischief cursor）", () => { assert.equal(field(d, "kind"), "grab"); });
	send("mischief-fake input");
	await sleep(500);
	d = await dump();
	const w1 = warps(d);
	await sleep(1200);
	const d2 = await dump();
	await snap("04-grab-caught");
	await check("搶游標：你一動（任何輸入）就立刻放手，不再移游標", () => {
		assert.equal(field(d, "kind"), "-");
		assert.equal(warps(d2), w1, `warps kept growing: ${w1} → ${warps(d2)}`);
		assert.ok(w0 >= 0);
		assert.ok(!/busy/.test(field(d2, "lead")), field(d2, "lead"));
	});

	// ---------- 購物警察 ----------
	await check("購物警察：網站清單（標題比對，不分大小寫）", async () => {
		assert.equal(await site("蝦皮購物 | 花得更少買得更好 - Google Chrome"), "蝦皮");
		assert.equal(await site("【momo購物網】週年慶 - Microsoft Edge"), "momo");
		assert.equal(await site("PChome 24h購物 - Google Chrome"), "PChome");
		assert.equal(await site("Amazon.com: Kindle Paperwhite - Google Chrome"), "Amazon");
		assert.equal(await site("博客來-原子習慣"), "博客來");
		assert.equal(await site("露天拍賣 | 台灣 NO.1 拍賣網站"), "露天");
		assert.equal(await site("淘宝网 - 淘！我喜欢"), "淘寶");
		assert.equal(await site("Yahoo奇摩購物中心 - 品牌旗艦"), "Yahoo 購物中心");
		assert.equal(await site("樂天市場 - 日本直送"), "樂天");
		assert.equal(await site("PChome Online 新聞 - Google Chrome"), "-");
		assert.equal(await site("EC2 Management Console - Google Chrome"), "-");
		assert.equal(await site("DeskPals.cs - Visual Studio Code"), "-");
	});
	send("mischief-fake fg Google - Google Chrome");
	await sleep(2500);
	d = await dump();
	await check("購物警察：一般網站不哭", () => { assert.equal(field(d, "kind"), "-"); assert.equal(field(d, "shopn"), "0"); });
	send("mischief-fake fg 蝦皮購物 | 花得更少買得更好 - Google Chrome");
	d = await until(kindIs("shop"), 10000);
	await check("購物警察：停在購物網站 2 秒 → 抱著錢包大哭", () => { assert.equal(field(d, "kind"), "shop"); assert.equal(field(d, "shopn"), "1"); });
	await sleep(800);
	await snap("05-shop-cry");
	d = await until(kindIs("-"), 20000);
	send("mischief-fake fg Google - Google Chrome");
	await sleep(1200);
	send("mischief-fake fg 蝦皮購物 | 花得更少買得更好 - Google Chrome");
	await sleep(3500);
	d = await dump();
	await check("購物警察：冷卻中切回購物網站不會再哭", () => { assert.equal(field(d, "kind"), "-"); assert.equal(field(d, "shopn"), "1"); });
	send("act mischief shop");
	d = await until(kindIs("shop"), 8000);
	await check("購物警察：act mischief shop 直接演（這個月第二次）", () => { assert.equal(field(d, "kind"), "shop"); assert.equal(field(d, "shopn"), "2"); });
	await sleep(1000);
	await snap("06-shop-second");
	d = await until(kindIs("-"), 20000);
	send("mischief-fake fg ");

	// ---------- 打字太兇（預設關）----------
	d = await dump();
	await check("打字太兇：預設關著，不數按鍵（掛鉤沒裝）", () => { assert.equal(field(d, "typing"), "0"); assert.equal(fake(d, "watching"), "0"); });
	send("mischief-fake typing 12 6");
	await sleep(7000);
	d = await dump();
	await check("打字太兇：關著時打很快也不會被震飛", () => assert.equal(field(d, "kind"), "-"));
	send("mischief-set typing 1");   // VS Code 設定推過來
	await sleep(1000);
	d = await dump();
	await check("打字太兇：打開就數按鍵次數（Windows 低階掛鉤／Mac 計數器）", () => { assert.equal(field(d, "typing"), "1"); assert.equal(fake(d, "watching"), "1"); });
	send("mischief-fake typing 4 5");
	await sleep(6500);
	d = await dump();
	await check("打字太兇：普通速度（每秒 4 下）不會被震飛", () => { assert.equal(field(d, "kind"), "-"); assert.ok(+fake(d, "keys") >= 15, "keys=" + fake(d, "keys")); });
	send("mischief-fake typing 12 14");
	d = await until(kindIs("typing"), 16000);
	await check("打字太兇：連續 4 秒每秒 12 下 → 震飛", () => assert.equal(field(d, "kind"), "typing"));
	await sleep(500);
	await snap("07-typing-fly");
	await sleep(1500);
	await snap("08-typing-dizzy");
	d = await until(kindIs("-"), 25000);
	await check("打字太兇：暈一下、爬回來就結束", () => assert.equal(field(d, "kind"), "-"));
	send("mischief-set typing 0");
	await sleep(1000);
	d = await dump();
	await check("打字太兇：關掉就不再數按鍵（掛鉤拿掉）", () => { assert.equal(field(d, "typing"), "0"); assert.equal(fake(d, "watching"), "0"); assert.ok(calls(d).includes("keywatch off")); });
	await check("打字太兇：VS Code 推的設定不會跳權限詢問（Mac 的輸入監控只在你自己打開開關時問）", () => assert.equal(fake(d, "asked"), "0"));
	send("act feature mis_typing=1");   // 小屋選單的開關（你自己按的）
	await sleep(1000);
	d = await dump();
	await check("打字太兇：你自己在小屋打開開關才問一次權限，掛鉤裝回去", () => { assert.equal(field(d, "typing"), "1"); assert.equal(fake(d, "asked"), "1"); assert.equal(fake(d, "watching"), "1"); });

	// ---------- 下班清場 ----------
	send("mischief-fake win 60 80 520 340 期末報告.docx - Word");
	send("mischief-fake win 380 160 560 360 收件匣 - Outlook");
	send("mischief-fake idle 0");
	send("mischief-fake clock 2026-11-16T17:30");
	await sleep(1800);
	d = await dump();
	await check("下班清場：還沒下班（17:30）不清", () => { assert.equal(field(d, "kind"), "-"); assert.equal(field(d, "pushed"), "0"); });
	await snap("09-clear-before");
	send("mischief-fake clock 2026-11-16T18:05");
	d = await until(kindIs("clear"), 8000);
	await check("下班清場：平日 18:00 後、人在電腦前 → 開始清場", () => assert.equal(field(d, "kind"), "clear"));
	await sleep(2300);
	await snap("10-clear-push");
	await sleep(700);
	await snap("11-clear-push2");
	d = await until(kindIs("-"), 35000);
	await check("下班清場：兩個視窗都只是縮小（不關閉），可以叫回來", () => {
		assert.equal(field(d, "kind"), "-");
		assert.equal(field(d, "pushed"), "2");
		assert.equal(field(d, "notice"), "1");
		assert.equal(field(d, "clearday"), "2026-11-16");
		const c = calls(d);
		assert.ok(c.includes("minimize 期末報告.docx - Word") && c.includes("minimize 收件匣 - Outlook"), c.join(" | "));
		assert.ok(!c.some((x) => /close|kill|quit|terminate/i.test(x)), c.join(" | "));
	});
	await snap("12-clear-done");
	send("mischief-fake clock 2026-11-16T19:00");
	await sleep(1800);
	d = await dump();
	await check("下班清場：一天只演一次", () => { assert.equal(field(d, "kind"), "-"); assert.equal(calls(d).filter((x) => x.startsWith("minimize")).length, 2); });
	const p2 = (await where()) || pos;
	send(`act click ${p2.x + 20},${p2.y + 30}`);
	await sleep(600);
	d = await dump();
	await check("下班清場：點公仔＝一鍵全部叫回來（後面的先，最前面的最後拿回焦點）", () => {
		assert.equal(field(d, "pushed"), "0");
		assert.equal(field(d, "notice"), "0");
		const r = calls(d).filter((x) => x.startsWith("restore"));
		assert.deepEqual(r, ["restore 期末報告.docx - Word", "restore 收件匣 - Outlook (front)"]);
	});
	send("act mischief clear");
	d = await until((x) => field(x, "kind") === "-" && field(x, "pushed") === "2", 35000);
	send("act mischief restore");
	await sleep(500);
	d = await dump();
	await check("下班清場：act mischief clear／restore（測試、錄影用）", () => {
		assert.equal(field(d, "pushed"), "0");
		assert.equal(calls(d).filter((x) => x.startsWith("restore")).length, 4);
	});

	// ---------- 設定 ----------
	send("act menu house");
	await sleep(500);
	await snap("13-house-menu");
	send("act menuclose");
	send("mischief-set grabmin 5");
	send("mischief-set clear 0");
	await sleep(400);
	d = await dump();
	await check("設定：VS Code 推 grabmin、開關", () => { assert.equal(field(d, "grabmin"), "5"); assert.equal(field(d, "clear"), "0"); });
	send("mischief-set clear 1");

	// ---------- 收工前把視窗叫回來 ----------
	const before = restoredCount();
	send("act mischief clear");
	d = await until((x) => field(x, "kind") === "-" && field(x, "pushed") === "2", 35000);
	await check("收工前：推走的視窗還在縮小中", () => assert.equal(field(d, "pushed"), "2"));
	send("quit");
	await sleep(2500);
	if (logFile) await check("收工（關掉 Desk Pals）前會先把推走的視窗全部叫回來", () => assert.equal(restoredCount(), before + 1, logFile));

	console.log(results.map((r) => r[0] + "  " + r[1]).join("\n"));
	const fail = results.filter((r) => r[0] === "FAIL").length;
	// GitHub Actions：失敗的項目也變成 annotation（在 Actions 頁面上直接看得到）
	if (process.env.GITHUB_ACTIONS) for (const r of results) if (r[0] === "FAIL") console.log("::error title=desktop-mischief::" + r[1].replace(/%/g, "%25").replace(/\r?\n/g, "%0A"));
	console.log(`\n${results.length - fail}/${results.length} passed`);
	s.end();
	process.exit(fail ? 1 : 0);
});
