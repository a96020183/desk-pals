// 上架（Microsoft Store）前要成立的幾件事，用離屏模式的桌面版逐一驗（這支自己開、自己關桌面版，每個情境一個臨時資料夾）：
//   匿名回報（DeskPals.Stats.cs）：本機假的 HTTP 端點（DESKPALS_GA4_URL）收到什麼——
//     第一次設定完成送 lineup_pick、滿 7 天第一次打開送 day7_active（只一次）、關掉就不送、沒有 ID 不送、個人版不送；
//     內容只有 client_id（每次不同的亂數）、事件名、lineup／app_version／platform，沒有使用者名稱、電腦名稱、路徑。
//   搗蛋（DeskPals.Mischief.cs）：公開版全部預設關、第一次打開先跳說明（截圖）、舊使用者照原本的開關轉過去不打擾；個人版維持原樣。
//   第一次設定第一頁的匿名回報說明（截圖）；Store 版（DESKPALS_FAKE_PACKAGED，只有 exe）第二頁的「開機時自動出現」。
// 絕不連到 Google：一律指定本機假端點；桌面版在離屏模式沒有假端點也不會送。
//
// 用法：node test/desktop-store.js <endpoint 開頭> <工作資料夾> <截圖資料夾> public|personal <platform> -- <開桌面版的指令…>
//   指令裡的 {ep} 換成這次的 endpoint（Windows：pipe 名稱 <開頭>-<情境>；Mac：socket 路徑 <開頭>-<情境>.sock）
//   <platform>：預期的 platform 欄位（win-vscode／win-exe／mac）。STORE_FAKE_PACKAGED=1：也測 Store 版第二頁（只有 exe 才有）
//   例：node test/desktop-store.js desk-pals-store %TEMP%\dp-store shots public win-vscode -- powershell.exe -NoProfile -ExecutionPolicy Bypass -File build\public\extension\desktop\desk-pals.ps1 -PipeName {ep}
const cp = require("child_process");
const fs = require("fs");
const http = require("http");
const net = require("net");
const os = require("os");
const path = require("path");
const assert = require("node:assert/strict");

const argv = process.argv.slice(2);
const dash = argv.indexOf("--");
const [epBase, work, shots0, edition, platform] = argv.slice(0, dash);
const cmd = argv.slice(dash + 1);
const win = process.platform === "win32";
const shots = path.resolve(shots0).replace(/\\/g, "/");
const PUBLIC = edition === "public";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
async function check(name, fn) {
	try { await fn(); results.push(["PASS", name]); }
	catch (e) { results.push(["FAIL", name + "\n      " + String(e.message).split("\n").slice(0, 12).join("\n      ")]); }
}
fs.mkdirSync(work, { recursive: true });
fs.mkdirSync(shots, { recursive: true });

// ---- 假的 GA4 端點 ----
const got = [];
const srv = http.createServer((req, res) => {
	let body = "";
	req.setEncoding("utf8");
	req.on("data", (d) => { body += d; });
	req.on("end", () => { got.push({ method: req.method, url: req.url, headers: req.headers, body }); res.writeHead(204); res.end(); });
});
const CFG = { id: "G-TEST12345", secret: "test_Secret-0123456789", version: "9.8.7" };
const cfgFile = path.join(work, "ga4-test.txt");
fs.writeFileSync(cfgFile, `measurement_id=${CFG.id}\napi_secret=${CFG.secret}\nversion=${CFG.version}\n`);

// ---- 開一個桌面版（每個情境自己的資料夾、endpoint）----
let n = 0;
async function launch(name, data, opts) {
	const ep = win ? `${epBase}-${name}-${++n}` : `${epBase}-${name}-${++n}.sock`;
	const target = win ? "\\\\.\\pipe\\" + ep : ep;
	const env = Object.assign({}, process.env, { DESKPALS_OFFSCREEN: "1", DESKPALS_ISOLATED: "1", DESKPALS_DATA_DIR: data });
	for (const k of ["DESKPALS_GA4_CONFIG", "DESKPALS_GA4_URL", "DESKPALS_FAKE_PACKAGED", "GA4_MEASUREMENT_ID", "GA4_API_SECRET"]) delete env[k];
	env.DESKPALS_GA4_CONFIG = opts.config ? cfgFile : path.join(work, "no-such-ga4.txt");   // 沒有 ID：連打包時內嵌的那份都不讀（CI 打包後的 exe 內嵌了真的 ID）
	env.DESKPALS_GA4_URL = `http://127.0.0.1:${srv.address().port}/mp/collect`;
	if (opts.packaged) env.DESKPALS_FAKE_PACKAGED = "1";
	if (win && process.env.STORE_PRIVATE_TEMP === "1") { env.TEMP = env.TMP = path.join(work, "tmp"); fs.mkdirSync(env.TEMP, { recursive: true }); }   // 本機跑：紀錄寫到自己的資料夾，不混進你正在用的 desk-pals.log
	const args = cmd.map((a) => a.replace(/\{ep\}/g, ep));
	const child = cp.spawn(args[0], args.slice(1), { env, stdio: "ignore", windowsHide: true });
	let exited = false;
	child.on("exit", () => { exited = true; });
	const sock = await new Promise((resolve, reject) => {
		const end = Date.now() + 90000;
		(function attempt() {
			const s = net.connect(target);
			s.setEncoding("utf8");
			s.once("connect", () => resolve(s));
			s.once("error", () => { if (Date.now() > end || exited) reject(new Error(`${name}: desktop did not start`)); else setTimeout(attempt, 500); });
		})();
	});
	let buf = "";
	sock.on("data", (d) => { buf += d; });
	sock.on("error", () => {});
	const app = {
		send: (l) => sock.write(l + "\n"),
		async reply(c, done) { buf = ""; sock.write(c + "\n"); for (let i = 0; i < 250 && !done(buf); i++) await sleep(40); return buf; },
		async block(c) { const o = await app.reply(c, (b) => /(^|\n)end\n/.test(b)); return o.slice(0, o.search(/(^|\n)end\n/) + 1); },
		async quit() {
			sock.write("quit\n");
			for (let i = 0; i < 100 && !exited; i++) await sleep(200);
			if (!exited) { try { process.kill(child.pid); } catch (e) {} throw new Error(`${name}: did not quit`); }
		},
	};
	await app.reply("hello", (b) => /lineup \w+/.test(b));
	return app;
}
const field = (line, k) => (new RegExp(`\\b${k}=(\\S*)`).exec(line) || [])[1];
async function mis(app) { const d = await app.block("mischief-dump"); return d.slice(d.indexOf("mischief ")).split("\n")[0]; }
async function stats(app) { const d = await app.block("stats-dump"); return d.slice(d.indexOf("stats ")).split("\n")[0]; }
async function setupInfo(app, pred) {
	for (let i = 0; i < 60; i++) { const s = await app.block("setup-info"); if (pred(s)) return s; await sleep(250); }
	return app.block("setup-info");
}
async function snap(app, name) { await app.reply(`snap ${shots}/${name}.png`, (b) => b.includes("snapped")); }
async function waitGot(count, ms) { for (const end = Date.now() + ms; Date.now() < end && got.length < count;) await sleep(100); return got.length; }
function fresh(name, files) {
	const d = path.join(work, name);
	fs.rmSync(d, { recursive: true, force: true });
	fs.mkdirSync(d, { recursive: true });
	for (const [f, t] of Object.entries(files || {})) fs.writeFileSync(path.join(d, f), t);
	return d;
}
const ymd = (daysAgo) => { const t = new Date(Date.now() - daysAgo * 86400000); return `${t.getFullYear()}-${String(t.getMonth() + 1).padStart(2, "0")}-${String(t.getDate()).padStart(2, "0")}`; };
async function finishSetup(app, lu) {
	await setupInfo(app, (s) => /setup step=0 first=1/.test(s));
	app.send(`act setup lu:${lu}`); await sleep(300);
	app.send("act setup next"); await sleep(500);
	app.send("act setup mode:shelf"); await sleep(300);
	app.send("act setup next"); await sleep(800);
}

// 一筆送出去的資料：只有允許的東西
const secretWords = [os.userInfo().username, os.hostname(), os.homedir(), work, process.env.USERDOMAIN || "", process.env.COMPUTERNAME || ""].filter((w) => w && w.length >= 3).map((w) => w.toLowerCase());
function checkHit(h, ev, lineup) {
	assert.equal(h.method, "POST");
	const u = new URL(h.url, "http://x");
	assert.equal(u.pathname, "/mp/collect");
	assert.deepEqual([...u.searchParams.keys()].sort(), ["api_secret", "measurement_id"]);
	assert.equal(u.searchParams.get("measurement_id"), CFG.id);
	assert.equal(u.searchParams.get("api_secret"), CFG.secret);
	const j = JSON.parse(h.body);
	assert.deepEqual(Object.keys(j).sort(), ["client_id", "events", "non_personalized_ads"]);
	assert.match(j.client_id, /^\d{9,10}\.\d{9,10}$/);
	assert.equal(j.events.length, 1);
	assert.deepEqual(Object.keys(j.events[0]).sort(), ["name", "params"]);
	assert.equal(j.events[0].name, ev);
	assert.deepEqual(j.events[0].params, { lineup, app_version: CFG.version, platform });
	const okHeaders = new Set(["host", "content-type", "content-length", "connection", "user-agent", "accept", "accept-encoding", "accept-language"]);
	for (const k of Object.keys(h.headers)) assert.ok(okHeaders.has(k), "unexpected header " + k + ": " + h.headers[k]);
	if (h.headers["user-agent"] !== undefined) assert.equal(h.headers["user-agent"], "DeskPals");
	if (h.headers["accept-language"] !== undefined) assert.equal(h.headers["accept-language"], "*");
	const all = (h.url + "\n" + h.body + "\n" + JSON.stringify(h.headers)).toLowerCase();
	for (const w of secretWords) assert.ok(!all.includes(w), "payload contains " + w);
	return j.client_id;
}

srv.listen(0, "127.0.0.1", async () => {
	try {
		if (PUBLIC) await publicRuns(); else await personalRuns();
	} catch (e) { results.push(["FAIL", "run: " + e.message]); }
	srv.close();
	console.log(results.map((r) => r[0] + "  " + r[1]).join("\n"));
	const fail = results.filter((r) => r[0] === "FAIL").length;
	if (process.env.GITHUB_ACTIONS) for (const r of results) if (r[0] === "FAIL") console.log("::error title=desktop-store::" + r[1].replace(/%/g, "%25").replace(/\r?\n/g, "%0A"));
	console.log(`\n${results.length - fail}/${results.length} passed`);
	process.exit(fail ? 1 : 0);
});

async function publicRuns() {
	// ---------- 全新安裝：第一頁說明、搗蛋全關＋第一次打開的說明、選完送 lineup_pick ----------
	let app = await launch("fresh", fresh("fresh"), { config: true });
	let s = await setupInfo(app, (x) => /setup step=0 first=1/.test(x));
	await check("第一次設定第一頁：有匿名回報的說明（note=1）", () => assert.equal(field(s.split("\n")[0], "note"), "1"));
	await snap(app, "setup-page1");
	let d = await mis(app);
	await check("公開版全新安裝：四個搗蛋全部預設關，沒裝鍵盤掛鉤", async () => {
		assert.equal(field(d, "edition"), "public");
		assert.deepEqual(["grab", "clear", "shop", "typing"].map((k) => field(d, k)), ["0", "0", "0", "0"]);
		assert.equal(field(d, "ack"), "-");
		const full = await app.block("mischief-dump");
		assert.match(full, /watching=0/);
	});
	let st = await stats(app);
	await check("匿名回報：公開版＋有 ID＝可用、預設開、還沒送", () => {
		assert.deepEqual(["public", "available", "on", "pick", "day7", "platform", "version"].map((k) => field(st, k)), ["1", "1", "1", "-", "-", platform, CFG.version]);
	});
	app.send("act setup close"); await sleep(400);
	app.send("act mischief toggle:typing"); await sleep(600);
	d = await mis(app);
	await check("打字太兇：第一次打開先跳說明，還沒打開、沒裝掛鉤", async () => {
		assert.equal(field(d, "ask"), "typing"); assert.equal(field(d, "typing"), "0");
		assert.match(await app.block("mischief-dump"), /watching=0/);
	});
	await snap(app, "consent-typing");
	app.send("act mischief consent:no"); await sleep(600);
	d = await mis(app);
	await check("說明視窗按「先不要」：不打開、下次還會問", () => { assert.equal(field(d, "ask"), "-"); assert.equal(field(d, "typing"), "0"); assert.equal(field(d, "ack"), "-"); });
	for (const k of ["clear", "shop", "grab"]) {
		app.send(`act mischief toggle:${k}`); await sleep(500);
		d = await mis(app);
		await check(`${k}：第一次打開先跳說明`, () => { assert.equal(field(d, "ask"), k); assert.equal(field(d, k), "0"); });
		if (k === "clear") await snap(app, "consent-clear");
		app.send("act mischief consent:ok"); await sleep(600);
		d = await mis(app);
		await check(`${k}：按「好，打開」才打開，記住看過了`, () => { assert.equal(field(d, "ask"), "-"); assert.equal(field(d, k), "1"); assert.ok(field(d, "ack").split(",").includes(k), field(d, "ack")); });
	}
	app.send("act mischief toggle:clear"); await sleep(400);
	app.send("act mischief toggle:clear"); await sleep(400);
	d = await mis(app);
	await check("看過說明的：關掉再打開不會再問", () => { assert.equal(field(d, "ask"), "-"); assert.equal(field(d, "clear"), "1"); });
	app.send("mischief-set typing 1"); await sleep(500);
	d = await mis(app);
	await check("VS Code 設定裡自己打開的：算打開過，不跳說明", () => { assert.equal(field(d, "typing"), "1"); assert.equal(field(d, "ask"), "-"); assert.ok(field(d, "ack").split(",").includes("typing")); });
	app.send("mischief-set typing 0"); await sleep(300);
	const consent = fs.readFileSync(path.join(work, "fresh", "mischief-consent.txt"), "utf8");
	await check("看過說明的記在 mischief-consent.txt", () => assert.match(consent, /^v1\n(mis_\w+\n)+$/));
	// 第一次設定（從頭開一次）
	await app.quit();
	app = await launch("fresh", path.join(work, "fresh"), { config: true });
	await finishSetup(app, "woban");
	await waitGot(1, 8000);
	await check("第一次設定完成：送一次 lineup_pick（woban）", () => { assert.equal(got.length, 1); checkHit(got[0], "lineup_pick", "woban"); });
	st = await stats(app);
	await check("記下第一次設定的日期、已經送過", () => { assert.equal(field(st, "installed"), ymd(0)); assert.equal(field(st, "pick"), "sent"); });
	const p = await app.block("stats-payload lineup_pick mine");
	await check("我的櫃（自己做的公仔）回報成 custom", () => { const j = JSON.parse(p.trim()); assert.equal(j.events[0].params.lineup, "custom"); });
	await check("client_id 每次都不一樣（本機不存 ID）", async () => {
		const a = JSON.parse((await app.block("stats-payload day7_active woban")).trim()).client_id;
		const b = JSON.parse((await app.block("stats-payload day7_active woban")).trim()).client_id;
		assert.notEqual(a, b);
		const files = fs.readdirSync(path.join(work, "fresh")).map((f) => { try { return fs.readFileSync(path.join(work, "fresh", f), "utf8"); } catch (e) { return ""; } }).join("\n");
		assert.ok(!files.includes(a) && !files.includes(b) && !files.includes(JSON.parse(got[0].body).client_id), "client id stored on disk");
	});
	app.send("act setup"); await sleep(600);
	s = await app.block("setup-info");
	await check("重新設定（不是第一次）：沒有那行說明", () => assert.equal(field(s.split("\n")[0], "note"), "0"));
	app.send("act setup close");
	app.send("act menu house"); await sleep(600);
	await snap(app, "house-menu");
	app.send("act menuclose");
	app.send("act stats 0"); await sleep(300);
	st = await stats(app);
	await check("小屋關掉匿名回報：on=0（anon-stats.txt）", () => { assert.equal(field(st, "on"), "0"); assert.match(fs.readFileSync(path.join(work, "fresh", "anon-stats.txt"), "utf8"), /on=0/); });
	await app.quit();

	// ---------- 滿 7 天：送 day7_active 一次 ----------
	const day7Files = (extra) => Object.assign({ "profile.txt": "done", "mode.txt": "shelf", "lineup.txt": "woban", "mischief-consent.txt": "v1\n", "anon-stats.txt": `installed=${ymd(8)}\npick=sent\n${extra || ""}` });
	const d7 = fresh("day7", day7Files());
	app = await launch("day7", d7, { config: true });
	await waitGot(2, 10000);
	await check("滿 7 天第一次打開：送 day7_active（現在開著的櫃）", () => { assert.equal(got.length, 2); checkHit(got[1], "day7_active", "woban"); });
	await check("兩次送的 client_id 不一樣", () => assert.notEqual(JSON.parse(got[0].body).client_id, JSON.parse(got[1].body).client_id));
	await app.quit();
	app = await launch("day7", d7, { config: true });
	await sleep(6000);
	await check("day7_active 只送一次（再開一次不送）", () => assert.equal(got.length, 2));
	await app.quit();
	app = await launch("day7early", fresh("day7early", Object.assign(day7Files(), { "anon-stats.txt": `installed=${ymd(5)}\npick=sent\n` })), { config: true });
	await sleep(6000);
	await check("還沒滿 7 天：不送", () => assert.equal(got.length, 2));
	await app.quit();

	// ---------- 關掉：完全不送 ----------
	app = await launch("off", fresh("off", day7Files("on=0\n")), { config: true });
	await sleep(6000);
	await check("關掉匿名回報：滿 7 天也不送", () => assert.equal(got.length, 2));
	await app.quit();
	app = await launch("offpick", fresh("offpick", { "anon-stats.txt": "on=0\n" }), { config: true });
	await finishSetup(app, "original");
	await sleep(4000);
	await check("關掉匿名回報：第一次設定也不送", () => assert.equal(got.length, 2));
	await app.quit();

	// ---------- 沒有 ID：停用 ----------
	app = await launch("noid", fresh("noid"), { config: false });
	s = await setupInfo(app, (x) => /setup step=0 first=1/.test(x));
	await check("沒有 ID：第一頁沒有那行說明", () => assert.equal(field(s.split("\n")[0], "note"), "0"));
	st = await stats(app);
	await check("沒有 ID：匿名回報停用", () => assert.equal(field(st, "available"), "0"));
	await finishSetup(app, "woban");
	await sleep(4000);
	await check("沒有 ID：第一次設定不送", () => assert.equal(got.length, 2));
	await app.quit();
	app = await launch("noid7", fresh("noid7", day7Files()), { config: false });
	await sleep(6000);
	await check("沒有 ID：滿 7 天也不送", () => assert.equal(got.length, 2));
	await app.quit();

	// ---------- 舊使用者升級：照原本的開關轉過去，不打擾 ----------
	app = await launch("old1", fresh("old1", { "profile.txt": "done", "mode.txt": "shelf", "lineup.txt": "original" }), { config: true });
	d = await mis(app);
	await check("舊使用者（沒動過開關）：維持原本的預設（下班清場、購物警察開著），也不會再問", () => {
		assert.deepEqual(["grab", "clear", "shop", "typing"].map((k) => field(d, k)), ["0", "1", "1", "0"]);
		assert.equal(field(d, "ack"), "clear,shop");
	});
	app.send("act mischief toggle:shop"); await sleep(400);
	app.send("act mischief toggle:shop"); await sleep(400);
	d = await mis(app);
	await check("舊使用者：本來開著的關掉再打開不跳說明", () => { assert.equal(field(d, "ask"), "-"); assert.equal(field(d, "shop"), "1"); });
	await app.quit();
	app = await launch("old2", fresh("old2", { "profile.txt": "done", "mode.txt": "shelf", "lineup.txt": "original", "features.txt": "scenes=1\nmis_grab=1\nmis_clear=1\nmis_shop=0\nmis_typing=0\n" }), { config: true });
	d = await mis(app);
	await check("舊使用者（改過開關）：照 features.txt，開著的算打開過", () => {
		assert.deepEqual(["grab", "clear", "shop", "typing"].map((k) => field(d, k)), ["1", "1", "0", "0"]);
		assert.equal(field(d, "ack"), "grab,clear");
	});
	app.send("act mischief toggle:shop"); await sleep(500);
	d = await mis(app);
	await check("舊使用者：本來關著的第一次打開還是會先問", () => { assert.equal(field(d, "ask"), "shop"); assert.equal(field(d, "shop"), "0"); });
	app.send("act mischief consent:no"); await sleep(300);
	await app.quit();
	app = await launch("old2", path.join(work, "old2"), { config: true });
	d = await mis(app);
	await check("再開一次：不會重新轉換（遷移只做一次）", () => { assert.equal(field(d, "ack"), "grab,clear"); assert.equal(field(d, "shop"), "0"); });
	await app.quit();

	// ---------- Store 版（假的）：第二頁「開機時自動出現」 ----------
	if (process.env.STORE_FAKE_PACKAGED === "1") {
		app = await launch("store", fresh("store"), { config: true, packaged: true });
		await setupInfo(app, (x) => /setup step=0 first=1/.test(x));
		app.send("act setup lu:original"); await sleep(300);
		app.send("act setup next"); await sleep(500);
		app.send("act setup mode:shelf"); await sleep(300);
		s = await app.block("setup-info");
		await check("Store 版第二頁：有「開機時自動出現」勾選（預設勾著）", () => assert.match(s, /\nbtn autostart \d+ \d+ \d+ \d+ 1 1\n/));
		await snap(app, "setup-page2-store");
		app.send("act setup autostart"); await sleep(300);
		s = await app.block("setup-info");
		await check("Store 版第二頁：可以取消勾選", () => assert.match(s, /\nbtn autostart \d+ \d+ \d+ \d+ 0 1\n/));
		await app.quit();
	}
}

async function personalRuns() {
	let app = await launch("per", fresh("per"), { config: true });
	const s = await setupInfo(app, (x) => /setup step=0 first=1/.test(x));
	await check("個人版：第一頁沒有匿名回報的說明", () => assert.equal(field(s.split("\n")[0], "note"), "0"));
	let d = await mis(app);
	await check("個人版：搗蛋維持原本的預設（下班清場、購物警察開著）", () => {
		assert.equal(field(d, "edition"), "personal");
		assert.deepEqual(["grab", "clear", "shop", "typing"].map((k) => field(d, k)), ["0", "1", "1", "0"]);
	});
	app.send("act setup close"); await sleep(300);
	app.send("act mischief toggle:typing"); await sleep(500);
	d = await mis(app);
	await check("個人版：打開搗蛋不跳說明", () => { assert.equal(field(d, "ask"), "-"); assert.equal(field(d, "typing"), "1"); });
	const st = await stats(app);
	await check("個人版：匿名回報不存在（有 ID 也一樣）", () => { assert.equal(field(st, "public"), "0"); assert.equal(field(st, "available"), "0"); });
	await app.quit();
	app = await launch("per", path.join(work, "per"), { config: true });
	await finishSetup(app, "original");
	await sleep(4000);
	await app.quit();
	app = await launch("per7", fresh("per7", { "profile.txt": "done", "mode.txt": "shelf", "lineup.txt": "original", "anon-stats.txt": `installed=${ymd(8)}\npick=sent\n` }), { config: true });
	await sleep(6000);
	await app.quit();
	await check("個人版：第一次設定、滿 7 天都完全不送", () => assert.equal(got.length, 0));
	await check("個人版：不會建 anon-stats.txt、mischief-consent.txt", () => {
		assert.ok(!fs.existsSync(path.join(work, "per", "anon-stats.txt")));
		assert.ok(!fs.existsSync(path.join(work, "per", "mischief-consent.txt")));
	});
}
