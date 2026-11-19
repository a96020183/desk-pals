// 「工作設定」視窗（DeskPals.WorkSettings.cs，畫面照 v011\work-settings 的 D 版）的離屏測試：這支自己開、自己關桌面版，不連網路。
//   格子 ↔ 清單、按「開」先跳去填（填好才開）、找不到 gh 開不了、CI 要先開 GitLab／GitHub、儲存時沒填好的標紅、
//   Esc 一層一層退（清單 → 格子 → 關掉）、記住上次怎麼看、取消不存、儲存的設定重開還在、鍵盤（Tab／空白鍵）、
//   小屋選單「工作 → 工作設定…」、小本子的「來源」都打得開。截圖：100%、150%（DESKPALS_TEST_DPI=144）、1366×768。
// 用法：node test/desktop-worksettings.js <endpoint 開頭> <工作資料夾> <截圖資料夾> -- <開桌面版的指令…，{ep} 換成 pipe 名稱>
const cp = require("child_process");
const fs = require("fs");
const net = require("net");
const path = require("path");
const assert = require("node:assert/strict");

const argv = process.argv.slice(2);
const dash = argv.indexOf("--");
const [epBase, work0, shots0] = argv.slice(0, dash);
const cmd = argv.slice(dash + 1);
const work = path.resolve(work0);
const shots = path.resolve(shots0).replace(/\\/g, "/");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
async function check(name, fn) {
	try { await fn(); results.push(["PASS", name]); }
	catch (e) { results.push(["FAIL", name + "\n      " + String(e.message).split("\n").slice(0, 14).join("\n      ")]); }
}
fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(shots, { recursive: true });
const data = path.join(work, "data"), tmp = path.join(work, "tmp");
for (const d of [data, tmp]) fs.mkdirSync(d, { recursive: true });
for (const [f, v] of Object.entries({ "profile.txt": "done", "mode.txt": "shelf", "lineup.txt": "original", "features.txt": "scenes=0\nlunch=0\nchatter=0\nset=scenes,lunch,chatter\n" })) fs.writeFileSync(path.join(data, f), v);
const stateFile = path.join(work, "cli.json");
fs.writeFileSync(stateFile, JSON.stringify({ glab: { host: "gitlab.example.com", user: "tester" }, gh: { missing: true } }));   // 有 glab、沒有 gh
const logDir = path.join(work, "worklog");
fs.mkdirSync(logDir, { recursive: true });

let n = 0;
async function launch(name, dpi) {
	const ep = `${epBase}-${name}-${++n}`;
	const env = Object.assign({}, process.env, {
		DESKPALS_OFFSCREEN: "1", DESKPALS_ISOLATED: "1", DESKPALS_DATA_DIR: data, TEMP: tmp, TMP: tmp,
		CLAUDE_CONFIG_DIR: path.join(work, "no-claude"), CODEX_HOME: path.join(work, "no-codex"),
		DESKPALS_FAKE_CLI: path.join(__dirname, "fixtures", "fake-cli.js"), FAKE_CLI_STATE: stateFile,
	});
	if (dpi) env.DESKPALS_TEST_DPI = String(dpi); else delete env.DESKPALS_TEST_DPI;
	const args = cmd.map((x) => x.replace(/\{ep\}/g, ep));
	const child = cp.spawn(args[0], args.slice(1), { env, stdio: "ignore", windowsHide: true });
	let exited = false;
	child.on("exit", () => { exited = true; });
	const sock = await new Promise((resolve, reject) => {
		const end = Date.now() + 90000;
		(function attempt() {
			const s = net.connect("\\\\.\\pipe\\" + ep);
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
	app.send("act light"); app.send("act lunchend");
	return app;
}
async function ws(app) {
	const d = await app.block("work-settings info");
	if (/^ws none/m.test(d)) return null;
	const head = Object.fromEntries((/^ws (.*)$/m.exec(d) || ["", ""])[1].split(" ").map((kv) => [kv.slice(0, kv.indexOf("=")), kv.slice(kv.indexOf("=") + 1)]));
	const src = {};
	for (const m of d.matchAll(/^src (\w+) want=(\d) on=(\d) lock=(\d) state=(\S+) kind=(\w+)$/gm)) src[m[1]] = { want: +m[2], on: +m[3], lock: +m[4], state: m[5], kind: m[6] };
	const hits = {};
	for (const m of d.matchAll(/^hit (\S+) (-?\d+) (-?\d+) (\d+) (\d+)$/gm)) hits[m[1]] = { x: +m[2], y: +m[3], w: +m[4], h: +m[5] };
	const tb = {};
	for (const m of d.matchAll(/^tb (\S+) ?(.*)$/gm)) tb[m[1]] = m[2];
	const lead = ((/^lead (.*)$/m.exec(d) || ["", ""])[1]).replace(/_/g, " ");
	return Object.assign(head, { src, hits, tb, lead, raw: d });
}
async function cfg(app) {
	const d = await app.block("work-dump");
	return Object.fromEntries((/^work (.*)$/m.exec(d) || ["", ""])[1].split(" ").map((kv) => kv.split("=")));
}
const act = async (app, l) => { app.send(l); await sleep(300); };
async function snap(app, name) {
	const s = await ws(app);
	await app.reply(`snap ${shots}/${name}.png`, (b) => b.includes("snapped"));
	return s;
}

(async () => {
	let app = await launch("a");
	await act(app, "work-settings open");
	await sleep(1500);   // glab／gh 偵測
	let s = await ws(app);
	await check("打開：先看格子、視窗標題 WoWo Pals・工作設定、九個來源、Claude／Codex 預設開、其他關", () => {
		assert.equal(s.view, "grid"); assert.equal(s.title, "WoWo_Pals・工作設定");
		assert.deepEqual(Object.keys(s.src), ["claude", "jira", "gitlab", "github", "ci", "meet", "rain", "net", "worklog"]);
		assert.equal(s.src.claude.on, 1);
		for (const k of ["jira", "gitlab", "github", "ci", "meet", "rain", "net", "worklog"]) assert.equal(s.src[k].on, 0, k);
		assert.ok(s.hits["tile:worklog"], "第九格 工作日誌資料夾");
	});
	await check("格子上的狀態：找不到 gh（有怎麼裝）、CI 要先開 GitLab 或 GitHub、要填的寫要先填", () => {
		assert.equal(s.src.github.state, "找不到_gh"); assert.ok(s.hits["howto:github"]);
		assert.equal(s.src.ci.lock, 1); assert.equal(s.src.ci.state, "先打開_GitLab_或_GitHub");
		for (const k of ["jira", "meet", "rain", "net", "worklog"]) assert.equal(s.src[k].state, "要先填", k);
		assert.equal(s.src.gitlab.state, "關著");
	});
	await snap(app, "grid-fresh-100");
	await act(app, "work-settings press sw:github");
	s = await ws(app);
	await check("找不到 gh：按「開」開不起來，跳到 GitHub 那一頁、焦點在「怎麼裝」", () => {
		assert.equal(s.src.github.want, 0); assert.equal(s.view, "list"); assert.equal(s.sel, "github"); assert.equal(s.focus, "howto:github");
	});
	await act(app, "work-settings press howto:github");
	await check("怎麼裝：打開 gh 的官網", async () => assert.equal((await ws(app)).link, "https://cli.github.com/"));
	await act(app, "work-settings key esc");
	await check("Esc：清單 → 格子（焦點回到剛剛那格）", async () => { s = await ws(app); assert.equal(s.view, "grid"); assert.equal(s.focus, "tile:github"); });
	await act(app, "work-settings key esc");
	await check("Esc：格子 → 關掉（跟取消一樣）", async () => assert.equal(await ws(app), null));

	// ---- 要填的：按開先跳去填，填好自己開 ----
	await act(app, "work-settings open");
	await act(app, "work-settings press sw:jira");
	s = await ws(app);
	await check("Jira 按「開」：跳到清單的 Jira、焦點在第一個空格、開關還是關（填好才開）", () => {
		assert.equal(s.view, "list"); assert.equal(s.sel, "jira"); assert.equal(s.focus, "tb:jira_site");
		assert.equal(s.src.jira.on, 0); assert.equal(s.src.jira.want, 0); assert.equal(s.pending, "jira");
		assert.equal(s.lead, "填好這三格就會開始");
		assert.deepEqual(Object.keys(s.tb).sort(), ["jira_email", "jira_site", "token"]);
	});
	await snap(app, "jira-jump-100");
	await act(app, "work-settings type jira_site yourteam.atlassian.net");
	await act(app, "work-settings type jira_email not-an-email");
	await check("還沒填完（信箱不對、沒 token）：還是關", async () => { s = await ws(app); assert.equal(s.src.jira.on, 0); });
	await act(app, "work-settings type jira_email me@yourteam.com");
	await act(app, "work-settings type token tok-123");
	await check("三格填好：自己開了", async () => { s = await ws(app); assert.equal(s.src.jira.on, 1); assert.equal(s.pending, "-"); assert.equal(s.src.jira.state, "已接上"); });
	await snap(app, "jira-filled-100");
	// 下雨按開又不填：不會被偷偷打開
	await act(app, "work-settings press tab:rain");
	await act(app, "work-settings press sw:rain");
	await check("下雨按「開」：焦點在地點；沒填就存＝不開", async () => { s = await ws(app); assert.equal(s.focus, "tb:rain_place"); assert.equal(s.src.rain.on, 0); });
	// GitLab（有 glab）→ CI 解鎖
	await act(app, "work-settings press tab:gitlab");
	await act(app, "work-settings press sw:gitlab");
	await check("GitLab 開了 CI 才能開", async () => { s = await ws(app); assert.equal(s.src.gitlab.on, 1); assert.equal(s.src.ci.lock, 0); });
	await act(app, "work-settings press sw:ci");
	await act(app, "work-settings press tab:worklog");
	await act(app, "work-settings press sw:worklog");
	await act(app, "work-settings type worklog_dir " + path.join(work, "no-such-folder"));
	await check("工作日誌資料夾：資料夾不存在＝不開；存在就開", async () => {
		s = await ws(app); assert.equal(s.src.worklog.on, 0);
		await act(app, "work-settings type worklog_dir " + logDir);
		s = await ws(app); assert.equal(s.src.worklog.on, 1);
	});
	await act(app, "work-settings save");
	await check("儲存：開了的都存進設定（token 加密存）、只按了開沒填的不開、視窗關掉", async () => {
		assert.equal(await ws(app), null);
		const c = await cfg(app);
		assert.equal(c.jira, "1"); assert.equal(c.jira_site, "yourteam.atlassian.net"); assert.equal(c.jira_email, "me@yourteam.com"); assert.equal(c.token, "1");
		assert.equal(c.gitlab, "1"); assert.equal(c.ci, "1"); assert.equal(c.rain, "0"); assert.equal(c.worklog, "1"); assert.equal(c.github, "0");
		assert.ok(!fs.readFileSync(path.join(data, "work-config.txt"), "utf8").includes("tok-123"));
	});

	// ---- 儲存時沒填好的：跳過去標紅 ----
	await act(app, "work-settings open");
	await check("記住上次怎麼看：上次在清單的工作日誌，再打開還是那裡", async () => { s = await ws(app); assert.equal(s.view, "list"); assert.equal(s.sel, "worklog"); });
	await act(app, "work-settings press tab:meet");
	await act(app, "work-settings press sw:meet");
	await act(app, "work-settings type meet_url https://calendar.example.com/me.ics");
	await check("開會：填好網址就開", async () => { s = await ws(app); assert.equal(s.src.meet.on, 1); });
	await act(app, "work-settings type meet_url 不是網址");
	await act(app, "work-settings save");
	s = await ws(app);
	await check("開著的來源被改壞了再存：不關、跳到那一頁、那一格標紅、說哪裡不對（紅色那格不是網址）", () => {
		assert.ok(s, "視窗不該關"); assert.equal(s.sel, "meet"); assert.equal(s.bad, "meet_url"); assert.equal(s.focus, "tb:meet_url");
		assert.equal(s.lead, "紅色那格不是網址");
	});
	await snap(app, "meet-bad-100");
	await act(app, "work-settings type meet_url webcal://calendar.example.com/me.ics");
	await act(app, "work-settings save");
	await check("改好再存：關掉，開會的網址（webcal 當 https）存進去", async () => {
		assert.equal(await ws(app), null);
		const c = await cfg(app);
		assert.equal(c.meet, "1"); assert.equal(c.meet_url, "webcal://calendar.example.com/me.ics");
	});

	// ---- 取消不存、鍵盤 ----
	await act(app, "work-settings open");
	await act(app, "work-settings press view:grid");
	await act(app, "work-settings press sw:claude");
	await check("格子上按 Claude 的「關」：關了（不用填東西的直接切）", async () => { s = await ws(app); assert.equal(s.src.claude.on, 0); });
	await act(app, "work-settings close");
	await check("取消：剛剛的不存（Claude／Codex 還是開著）", async () => assert.equal((await cfg(app)).ai, "1"));
	await act(app, "work-settings open");
	await check("切到格子以後，下次打開是格子", async () => { s = await ws(app); assert.equal(s.view, "grid"); });
	for (let i = 0; i < 4; i++) await act(app, "work-settings key tab");
	await check("Tab：格子、清單、Claude 那格、Claude 的開關……依序走", async () => { s = await ws(app); assert.equal(s.focus, "sw:claude"); });
	await act(app, "work-settings key space");
	await check("空白鍵：按下焦點所在的開關", async () => { s = await ws(app); assert.equal(s.src.claude.on, 0); });
	await act(app, "work-settings key space");
	await snap(app, "grid-work-100");
	await act(app, "work-settings press tile:jira");
	await snap(app, "jira-list-100");
	await act(app, "work-settings close");

	// ---- 入口：小屋選單、小本子 ----
	await check("小屋選單「工作 → 工作設定…」打得開", async () => {
		app.send("act menu house"); await sleep(800);
		let d = await app.block("menu-info");
		const wi = [...d.matchAll(/row (\d+) (\d+) (\w+) (\d) (\d) (\d) (.*)/g)].find((m) => m[7] === "工作");
		app.send(`act menuclick ${wi[1]}`); await sleep(500);
		d = await app.block("menu-info");
		const it = [...d.matchAll(/row (\d+) (\d+) (\w+) (\d) (\d) (\d) (.*)/g)].find((m) => m[7] === "工作設定…");
		assert.ok(it, d);
		app.send(`act menuclick ${it[1]}`); await sleep(800);
		assert.ok(await ws(app), "沒打開");
		await act(app, "work-settings close");
	});
	await check("小本子的「來源」打開工作設定", async () => {
		await act(app, "nb-open"); await sleep(600);
		await act(app, "nb-act sources"); await sleep(600);
		assert.ok(await ws(app), "沒打開");
		await act(app, "work-settings close"); await act(app, "nb-close");
	});
	await app.quit();

	// ---- 重開還在；150% 的樣子 ----
	app = await launch("b", 144);
	await act(app, "work-settings open"); await sleep(1200);
	await check("重開（150%）：存過的還在，Jira 已接上", async () => {
		s = await ws(app);
		// 螢幕夠高就是 900x900；CI 的螢幕比較矮時，視窗會照設計變矮、加捲軸（寬度多一條捲軸）
		const [w150, h150] = s.size.split("x").map(Number);
		if (h150 === 900) assert.equal(w150, 900, s.size);
		else { assert.ok(h150 < 900 && h150 >= 240, s.size); assert.equal(s.scroll, "1", s.size); assert.ok(w150 >= 900 && w150 <= 930, s.size); }
		assert.equal(s.src.jira.on, 1); assert.equal(s.src.meet.on, 1); assert.equal(s.src.gitlab.on, 1); assert.equal(s.src.worklog.on, 1);
	});
	await act(app, "work-settings press view:grid");
	await snap(app, "grid-work-150");
	await act(app, "work-settings press tile:jira");
	await snap(app, "jira-list-150");
	await act(app, "work-settings press tab:meet");
	await snap(app, "meet-150");
	await act(app, "work-settings close");
	await app.quit();

	// ---- 螢幕太矮（假裝 200%：視窗 1200 高放不進 1040 的工作區）：內容可以捲，儲存按得到 ----
	app = await launch("c", 192);
	await act(app, "work-settings open"); await sleep(800);
	await check("螢幕放不下（200%）：視窗變矮、裡面可以捲", async () => {
		s = await ws(app);
		assert.equal(s.scroll, "1", s.raw.split("\n")[0]);
		const [w, h] = s.size.split("x").map(Number);
		assert.ok(h < 1200 && h >= 240, s.size);   // 比整個 1200 矮（離屏的工作區是 1080）
		assert.ok(s.hits.save, "儲存還在（捲下去按得到）");
	});
	await act(app, "work-settings close");
	await app.quit();

	let fail = 0;
	for (const [r, name] of results) { console.log(`${r}  ${name}`); if (r !== "PASS") fail++; }
	console.log(`\n${results.length - fail}/${results.length} passed`);
	process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
