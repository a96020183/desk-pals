// 工作來源（DeskPals.Work.cs）的離屏測試：這支自己開、自己關桌面版，不連網路。
//   假的 Jira／天氣／行事曆＝本機 HTTP 伺服器；假的 glab／gh＝test/fixtures/fake-cli.js（DESKPALS_FAKE_CLI，只在離屏模式有效）；
//   假的 Claude Code／Codex 對話＝臨時資料夾（CLAUDE_CONFIG_DIR、CODEX_HOME）；公司網路＝本機 TCP 埠。
//   要看的：全部預設關、預設什麼都不連；小本子紀錄的格式（SPEC 2b）；每個來源的提醒（公仔泡泡，用字跟 VS Code 版一樣）；
//   Jira token 用 DPAPI 存（PowerShell 解得開、檔案裡沒有明文）；設定重開還在；VS Code 送來的重複通知被丟掉；改名 WoWo Pals。
//   有時間的（到期、開會、下雨）都用假時鐘（work-clock），不看跑測試的當下幾點；CI 的 runner 是 UTC 也一樣。
//
// 用法：node test/desktop-work.js <endpoint 開頭> <工作資料夾> <截圖資料夾> -- <開桌面版的指令…，{ep} 換成 pipe 名稱>
//   例：node test/desktop-work.js desk-pals-work %TEMP%\dp-work shots\work -- build\win-personal\DeskPals.exe --pipe {ep}
// 只在 Windows 跑（DPAPI、pipe）。
const cp = require("child_process");
const fs = require("fs");
const http = require("http");
const net = require("net");
const os = require("os");
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
const p2 = (n) => String(n).padStart(2, "0");
const fmtLocal = (d) => `${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())}T${p2(d.getHours())}:${p2(d.getMinutes())}:${p2(d.getSeconds())}`;
const dayOf = (iso) => iso.slice(0, 10);
const jiraTime = (d) => { const o = -d.getTimezoneOffset(), a = Math.abs(o); return `${fmtLocal(d)}.000${o >= 0 ? "+" : "-"}${p2(Math.floor(a / 60))}${p2(a % 60)}`; };
async function until(what, fn, ms = 15000) {
	const end = Date.now() + ms;
	let last;
	while (Date.now() < end) { try { last = await fn(); if (last) return last; } catch (e) { last = e; } await sleep(200); }
	throw new Error("timed out waiting for " + what + (last instanceof Error ? ": " + last.message : ""));
}

fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(work, { recursive: true });
fs.mkdirSync(shots, { recursive: true });
const data = path.join(work, "data");
fs.mkdirSync(data, { recursive: true });
fs.writeFileSync(path.join(data, "profile.txt"), "done");
fs.writeFileSync(path.join(data, "mode.txt"), "shelf");
fs.writeFileSync(path.join(data, "features.txt"), "scenes=0\nlunch=0\nchatter=0\nset=scenes,lunch,chatter\n");   // 劇情、午餐不要在測試中途插進來
const tmp = path.join(work, "tmp");
fs.mkdirSync(tmp, { recursive: true });

// ---------------- 假的 Claude Code／Codex 對話 ----------------
const now0 = new Date();
const ago = (s) => new Date(now0.getTime() - s * 1000);
const claudeDir = path.join(work, "claude"), codexDir = path.join(work, "codex"), wslDir = path.join(work, "wsl", ".claude");
function claudeSession(root, folder, sid, lines, mtimeAgo) {
	const d = path.join(root, "projects", folder);
	fs.mkdirSync(d, { recursive: true });
	const f = path.join(d, sid + ".jsonl");
	fs.writeFileSync(f, lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
	const mt = ago(mtimeAgo);
	fs.utimesSync(f, mt, mt);
	return f;
}
const u = (t, content, extra) => Object.assign({ type: "user", isSidechain: false, sessionId: "x", cwd: "C:\\src\\desk-pals", timestamp: t.toISOString(), message: { role: "user", content } }, extra || {});
const a = (t, stop, content) => ({ type: "assistant", isSidechain: false, timestamp: t.toISOString(), message: { role: "assistant", stop_reason: stop, content: content || [{ type: "text", text: "好了" }] } });
const tA0 = ago(900), tA1 = ago(300);
claudeSession(claudeDir, "C--src-desk-pals", "sid-aaaa", [
	u(tA0, "<command-name>/clear</command-name>"),
	u(new Date(tA0.getTime() + 1000), "右鍵選單一打開就關掉，幫我查一下"),
	{ type: "ai-title", aiTitle: "修好右鍵選單一開就關", sessionId: "sid-aaaa" },
	a(new Date(tA0.getTime() + 60000), "tool_use", [{ type: "tool_use", name: "Read" }]),
	u(new Date(tA0.getTime() + 61000), [{ type: "tool_result", content: "…" }]),
	a(tA1, "end_turn"),
], 120);
const tB0 = ago(1500), tB1 = ago(400);
const longAsk = "幫我把結帳頁的金額改成兩位小數，然後跑測試看看有沒有壞掉的地方，順便整理一下 PR 說明跟截圖";
claudeSession(claudeDir, "C--src-shop-web", "sid-bbbb", [
	u(tB0, [{ type: "text", text: "<ide_opened_file>The user opened the file checkout.ts in the IDE.</ide_opened_file>" }, { type: "text", text: longAsk }], { cwd: "C:\\src\\shop-web" }),
	a(tB1, "end_turn"),
], 150);
claudeSession(claudeDir, "C--src-busy", "sid-busy", [   // 還在等工具：不記
	u(ago(600), "跑整套測試", { cwd: "C:\\src\\busy" }),
	a(ago(130), "tool_use", [{ type: "tool_use", name: "Bash" }]),
], 120);
const tM0 = ago(180), tM1 = ago(150);
claudeSession(claudeDir, "C--src-desk-pals", "sid-multi", [   // 前天開的對話今天又接著做：今天那筆從今天的第一句算
	u(ago(2 * 86400), "先看一下打包流程", { cwd: "C:\src\desk-pals" }),
	a(ago(2 * 86400 - 60), "end_turn"),
	u(tM0, "接著把安裝程式的標題改掉"),
	a(tM1, "end_turn"),
], 120);
const tW0 = ago(1200), tW1 = ago(700);
claudeSession(wslDir, "-home-me-notes", "sid-wsl1", [   // WSL 裡的 Claude：要設「別的資料夾」才看得到
	u(tW0, "把筆記整理成表格", { cwd: "/home/me/notes" }),
	a(tW1, "end_turn"),
], 200);
// Codex
const cd = new Date(now0); const cdir = path.join(codexDir, "sessions", String(cd.getFullYear()), p2(cd.getMonth() + 1), p2(cd.getDate()));
fs.mkdirSync(cdir, { recursive: true });
const tC0 = ago(1000), tC1 = ago(500);
const cf = path.join(cdir, "rollout-2026-11-19T10-00-00-0199aaaa-bbbb-cccc-dddd-eeeeffff0000.jsonl");
const ev = (t, type, payload) => JSON.stringify({ timestamp: t.toISOString(), type, payload });
fs.writeFileSync(cf, [
	ev(tC0, "session_meta", { id: "0199aaaa-bbbb-cccc-dddd-eeeeffff0000", timestamp: tC0.toISOString(), cwd: "C:\\src\\shop-web" }),
	ev(tC0, "response_item", { type: "message", role: "user", content: [{ type: "input_text", text: "<environment_context>cwd</environment_context>" }] }),
	ev(new Date(tC0.getTime() + 500), "event_msg", { type: "user_message", message: "把 README 的安裝步驟改成 winget" }),
	ev(new Date(tC0.getTime() + 600), "event_msg", { type: "task_started" }),
	ev(tC1, "event_msg", { type: "task_complete" }),
].join("\n") + "\n");
fs.utimesSync(cf, ago(120), ago(120));

// ---------------- 假的 glab／gh ----------------
const stateFile = path.join(work, "cli-state.json"), cliLog = path.join(work, "cli-calls.log");
const cli = { glab: { host: "gitlab.example.com", user: "tester", todos: [], events: [], projects: {}, pipelines: {} }, gh: { user: "octo", notifications: [], events: [], runs: {} } };
const saveCli = () => fs.writeFileSync(stateFile, JSON.stringify(cli));
saveCli();

// ---------------- 假的 Jira／天氣／行事曆 ----------------
const TOKEN = "tok-Sup3r-Secret-123", EMAIL = "me@example.com";
const jira = { open: [], due: [], recent: [], changed: [], comments: {} };
const issue = (key, summary, status, cat, extra) => ({ key, fields: Object.assign({ summary, status: { name: status, statusCategory: { key: cat } }, project: { name: "WoWo Pals" }, updated: jiraTime(ago(240)) }, extra || {}) });
const web = { wttrFail: false, wttr: null, metno: null, ics: "" };
const reqs = [];
const server = http.createServer((req, res) => {
	const url = new URL(req.url, "http://x");
	reqs.push(req.method + " " + req.url);
	const json = (o, code) => { res.writeHead(code || 200, { "Content-Type": "application/json" }); res.end(JSON.stringify(o)); };
	if (url.pathname.startsWith("/rest/api/3/")) {
		if (req.headers.authorization !== "Basic " + Buffer.from(EMAIL + ":" + TOKEN).toString("base64")) return json({ errorMessages: ["no"] }, 401);
		if (url.pathname === "/rest/api/3/myself") return json({ accountId: "me-1" });
		if (url.pathname === "/rest/api/3/search/jql") {
			const q = url.searchParams.get("jql");
			if (/status changed BY/.test(q)) return json({ issues: jira.changed });
			if (/duedate/.test(q)) return json({ issues: jira.due });
			if (/updated >= -20m/.test(q)) return json({ issues: jira.recent });
			if (/statusCategory != Done ORDER BY created/.test(q)) return json({ issues: jira.open });
			return json({ issues: [] });
		}
		const m = /^\/rest\/api\/3\/issue\/([^/]+)\/comment$/.exec(url.pathname);
		if (m) return json({ comments: jira.comments[m[1]] || [] });
		return json({}, 404);
	}
	if (url.pathname.startsWith("/wttr/")) return web.wttrFail ? json({}, 500) : json(web.wttr || {});
	if (url.pathname.startsWith("/metno/")) return json(web.metno || {});
	if (url.pathname === "/cal.ics") { res.writeHead(200, { "Content-Type": "text/calendar" }); return res.end(web.ics); }
	json({}, 404);
});

// ---------------- 開桌面版 ----------------
let n = 0, port = 0;
async function launch(name, iso) {
	const ep = `${epBase}-${name}-${++n}`;
	const env = Object.assign({}, process.env, {
		DESKPALS_OFFSCREEN: "1", DESKPALS_ISOLATED: "1", DESKPALS_DATA_DIR: iso || data, TEMP: tmp, TMP: tmp,
		CLAUDE_CONFIG_DIR: claudeDir, CODEX_HOME: codexDir,
		DESKPALS_FAKE_CLI: path.join(__dirname, "fixtures", "fake-cli.js"), FAKE_CLI_STATE: stateFile, FAKE_CLI_LOG: cliLog,
		DESKPALS_FAKE_WEB: `http://127.0.0.1:${port}`,
	});
	if (iso) { delete env.CLAUDE_CONFIG_DIR; delete env.CODEX_HOME; delete env.DESKPALS_DOWNLOADS_DIR; }
	if (iso === "no-data-dir") delete env.DESKPALS_DATA_DIR;   // 連資料資料夾都沒指定   // 沒設：桌面版自己決定看哪裡（離屏時不能是你的家目錄）
	const args = cmd.map((x) => x.replace(/\{ep\}/g, ep));
	const child = cp.spawn(args[0], args.slice(1), { env, stdio: "ignore", windowsHide: true });
	let exited = false;
	child.on("exit", () => { exited = true; });
	const target = "\\\\.\\pipe\\" + ep;
	const sock = await new Promise((resolve, reject) => {
		const end = Date.now() + 90000;
		(function attempt() {
			const s = net.connect(target);
			s.setEncoding("utf8");
			s.once("connect", () => resolve(s));
			s.once("error", () => { if (Date.now() > end || exited) reject(new Error(`${name}: desktop did not start`)); else setTimeout(attempt, 500); });
		})();
	});
	let buf = "", all = "";
	sock.on("data", (d) => { buf += d; all += d; });
	sock.on("error", () => {});
	const app = {
		ep, target,
		get all() { return all; },
		send: (l) => sock.write(l + "\n"),
		async reply(c, done) { buf = ""; sock.write(c + "\n"); for (let i = 0; i < 250 && !done(buf); i++) await sleep(40); return buf; },
		async block(c) { const o = await app.reply(c, (b) => /(^|\n)end\n/.test(b)); return o.slice(0, o.search(/(^|\n)end\n/) + 1); },
		async dump() { const d = await app.block("work-dump"); return d.slice(d.indexOf("work ")); },
		async quit() {
			sock.write("quit\n");
			for (let i = 0; i < 100 && !exited; i++) await sleep(200);
			if (!exited) { try { process.kill(child.pid); } catch (e) {} throw new Error(`${name}: did not quit`); }
		},
	};
	await app.reply("hello", (b) => /lineup \w+/.test(b) && /work-own /.test(b));
	return app;
}
const cfgOf = (d) => Object.fromEntries((/^work (.*)$/m.exec(d) || ["", ""])[1].split(" ").filter(Boolean).map((kv) => kv.split("=")));
const stateOf = (d) => Object.fromEntries((/^work-state (.*)$/m.exec(d) || ["", ""])[1].split(" ").filter(Boolean).map((kv) => kv.split("=")));
const ownOf = (d) => (/^work-own (.*)$/m.exec(d) || ["", ""])[1];
const notices = (d) => d.split("\n").filter((l) => l.startsWith("notice ")).map((l) => l.slice(7));
function readLog(day) {
	const f = path.join(data, "notebook", `log-${day}.jsonl`);
	if (!fs.existsSync(f)) return { raw: [], by: {} };
	const raw = fs.readFileSync(f, "utf8").split("\n").filter(Boolean);
	const by = {};
	for (const l of raw) { const o = JSON.parse(l); by[o.id] = o; }
	return { raw, by };
}
const todayStr = dayOf(fmtLocal(new Date()));

(async () => {
	await new Promise((r) => server.listen(0, "127.0.0.1", r));
	port = server.address().port;
	let app = await launch("a");
	const hello = app.all;

	// ================= 1. 全新安裝：全部關、什麼都不連 =================
	await check("全新安裝：工作來源全部預設關（Claude／Codex 的本機紀錄預設開），work-own -", async () => {
		const d = await app.dump();
		const c = cfgOf(d);
		for (const k of ["jira", "gitlab", "github", "ci", "meet", "rain", "vpn", "worklog"]) assert.equal(c[k], "0", k);
		assert.equal(c.ai, "1");
		assert.equal(c.token, "0");
		assert.equal(ownOf(d), "-");
		assert.match(hello, /work-own -\n/, "hello 後要告訴擴充套件桌面版沒在管任何來源");
	});
	app.send("work-poll");
	await sleep(2500);
	await check("全關的時候：沒叫 glab／gh、沒連任何網址", () => {
		assert.equal(fs.existsSync(cliLog) ? fs.readFileSync(cliLog, "utf8") : "", "");
		assert.deepEqual(reqs, []);
	});

	// ================= 2. Claude Code／Codex 做完的對話進小本子 =================
	await check("Claude：有 ai-title 用 ai-title，project＝cwd 的資料夾名，t／end＝第一筆／最後一筆", async () => {
		const e = await until("claude:sid-aaaa in the log", () => readLog(dayOf(fmtLocal(tA1))).by["claude:sid-aaaa"]);
		assert.deepEqual(e, { id: "claude:sid-aaaa", t: fmtLocal(tA0), end: fmtLocal(tA1), src: "claude", project: "desk-pals", title: "修好右鍵選單一開就關", ok: null, key: "desk-pals" });
	});
	await check("Claude：沒有 ai-title 用第一句需求（去掉 IDE 標籤、剪成 40 字）；還在等工具的對話不記", async () => {
		const e = await until("claude:sid-bbbb", () => readLog(dayOf(fmtLocal(tB1))).by["claude:sid-bbbb"]);
		assert.equal(e.title, longAsk.slice(0, 40) + "…");
		assert.equal(e.project, "shop-web");
		assert.equal(e.t, fmtLocal(tB0));
		assert.equal(readLog(todayStr).by["claude:sid-busy"], undefined);
	});
	await check("Claude：好幾天的對話，今天那筆從今天的第一筆開始", async () => {
		const e = await until("claude:sid-multi", () => readLog(dayOf(fmtLocal(tM1))).by["claude:sid-multi"]);
		assert.equal(e.t, fmtLocal(tM0)); assert.equal(e.end, fmtLocal(tM1)); assert.equal(e.title, "先看一下打包流程");
	});
	await check("Codex：第一句需求當標題、做完（task_complete）才記", async () => {
		const e = await until("codex entry", () => readLog(dayOf(fmtLocal(tC1))).by["codex:0199aaaa-bbbb-cccc-dddd-eeeeffff0000"]);
		assert.equal(e.title, "把 README 的安裝步驟改成 winget");
		assert.equal(e.src, "codex"); assert.equal(e.project, "shop-web");
		assert.equal(e.t, fmtLocal(tC0)); assert.equal(e.end, fmtLocal(tC1));
	});
	await check("進階：別的資料夾（WSL）設了才看", async () => {
		assert.equal(readLog(dayOf(fmtLocal(tW1))).by["claude:sid-wsl1"], undefined);
		app.send(`work-set claude_dir ${wslDir}`);
		const e = await until("WSL session", () => readLog(dayOf(fmtLocal(tW1))).by["claude:sid-wsl1"]);
		assert.equal(e.project, "notes"); assert.equal(e.title, "把筆記整理成表格");
	});

	// ================= 3. Jira =================
	app.send("work-clock 2026-11-23T08:00");   // 星期一早上 8 點：還沒到 09:30 的到期提醒
	jira.open = [issue("PBG-2231", "右鍵選單一開就關", "處理中", "indeterminate")];
	jira.changed = [issue("PBG-2231", "右鍵選單一開就關", "完成", "done"), issue("PBG-2198", "設定頁字太小", "測試中", "indeterminate")];
	app.send(`work-token ${TOKEN}`);
	app.send(`work-set jira_email ${EMAIL}`);
	app.send(`work-set jira_site http://127.0.0.1:${port}`);
	const beforeOwn = app.all.length;
	app.send("work-set jira 1");
	await check("Jira：打開後 work-own 有 jira（設定改了就告訴擴充套件）", async () => {
		await until("work-own jira", () => /work-own jira\n/.test(app.all.slice(beforeOwn)));
	});
	await check("Jira：第一次只記下來不提醒；未結單寫 jira-open.json；今天動過的單寫進小本子", async () => {
		const open = await until("jira-open.json", () => { const f = path.join(data, "notebook", "jira-open.json"); return fs.existsSync(f) && JSON.parse(fs.readFileSync(f, "utf8")); });
		assert.deepEqual(open, [{ key: "PBG-2231", title: "右鍵選單一開就關", status: "處理中", url: `http://127.0.0.1:${port}/browse/PBG-2231` }]);
		const log = await until("jira log", () => { const l = readLog(todayStr).by; return l["jira:PBG-2198:status"] && l; });
		const t = fmtLocal(ago(240));
		assert.deepEqual(log["jira:PBG-2231:resolved"], { id: "jira:PBG-2231:resolved", t, src: "jira", project: "WoWo Pals", title: "右鍵選單一開就關", status: "工單解決了", ok: true, ref: "PBG-2231", url: `http://127.0.0.1:${port}/browse/PBG-2231`, key: "PBG-2231" });
		assert.equal(log["jira:PBG-2198:status"].status, "測試中");
		assert.equal(log["jira:PBG-2198:status"].ok, null);
		assert.deepEqual(notices(await app.dump()).filter((x) => x.startsWith("jira")), []);
		assert.equal(stateOf(await app.dump()).jira, "ok");
	});
	jira.open.unshift(issue("PBG-2240", "結帳頁金額少一位小數", "待辦", "new"));
	jira.recent = [issue("PBG-2231", "右鍵選單一開就關", "完成", "done")];
	jira.comments["PBG-2231"] = [{ id: "9001", created: jiraTime(new Date(2026, 10, 23, 8, 5)), author: { accountId: "u-2", displayName: "王小明" },
		body: { type: "doc", content: [{ type: "paragraph", content: [{ type: "mention", attrs: { id: "me-1", text: "@我" } }, { type: "text", text: " 這張可以關了嗎" }] }] } }];
	app.send("work-poll");
	await check("Jira：新單指派給你、留言 @你 → 公仔提醒（用字跟 VS Code 版一樣）", async () => {
		const ns = await until("jira notices", async () => { const x = notices(await app.dump()).filter((s) => s.startsWith("jira")); return x.length >= 2 && x; });
		assert.deepEqual(ns, [
			`jira http://127.0.0.1:${port}/browse/PBG-2240 PBG-2240 指派給你了：結帳頁金額少一位小數`,
			`jira http://127.0.0.1:${port}/browse/PBG-2231?focusedCommentId=9001 王小明 在 PBG-2231 @你：@我 這張可以關了嗎`,
		]);
	});
	jira.due = [issue("PBG-1000", "舊單", "待辦", "new", { duedate: "2026-11-20" }), issue("PBG-2240", "結帳頁金額少一位小數", "待辦", "new", { duedate: "2026-11-23" }), issue("PBG-2198", "設定頁字太小", "測試中", "indeterminate", { duedate: "2026-11-24" })];
	app.send("work-clock 2026-11-23T09:35");
	app.send("work-poll");
	await check("Jira：平日 09:30 到期提醒（今天、明天、逾期），同一個時段只講一次", async () => {
		const due = await until("due notice", async () => notices(await app.dump()).find((s) => s.includes("到期")));
		const [, url, text] = /^jira (\S+) (.*)$/.exec(due);
		assert.equal(decodeURIComponent(url), `http://127.0.0.1:${port}/issues/?jql=assignee = currentUser() AND statusCategory != Done AND duedate >= -14d AND duedate <= endOfDay(1) ORDER BY duedate ASC`);
		assert.equal(text, "今天到期：PBG-2240；明天到期：PBG-2198；已經逾期 1 張");
		jira.due = [];   // 之後（假時鐘關掉）跑測試的當下如果剛好是平日 9:30 以後，不要再冒出到期提醒
		app.send("work-poll");
		await sleep(2500);
		assert.equal(notices(await app.dump()).filter((s) => s.includes("到期")).length, 1);
	});
	app.send("work-token wrong-token");
	app.send("work-poll");
	await check("Jira：token 錯了看得出來（給設定視窗顯示「連不上，檢查 token」）", async () => {
		await until("jira=auth", async () => stateOf(await app.dump()).jira === "auth");
	});
	app.send(`work-token ${TOKEN}`);

	// ================= 4. VS Code 送來的重複通知 =================
	await check("沒有重複通知：桌面版在管 Jira 時，VS Code（舊版擴充套件）送來的 jira 通知丟掉；沒在管的照常", async () => {
		const d0 = +stateOf(await app.dump()).dropped;
		app.send("notify jira https://example.com/browse/PBG-9 PBG-9 指派給你了：重複的");
		app.send("notify ci-ok - 從 ci-watch.js 來的");   // 盯 CI 還沒開：照常講
		await sleep(600);
		assert.equal(+stateOf(await app.dump()).dropped, d0 + 1);
	});

	// ================= 5. GitLab／GitHub／盯 CI =================
	app.send("work-clock off");
	const tPush = ago(40), tMr = ago(30), tTag = ago(20), tGh = ago(50);
	cli.glab.projects["12"] = { id: 12, name: "desk-pals", path: "desk-pals", path_with_namespace: "web/desk-pals", web_url: "https://gitlab.example.com/web/desk-pals" };
	cli.glab.events = [
		{ action_name: "pushed new", project_id: 12, created_at: tTag.toISOString(), push_data: { ref_type: "tag", ref: "1.2.0-Production.1", commit_count: 0, action: "created" } },
		{ action_name: "opened", project_id: 12, created_at: tMr.toISOString(), target_type: "MergeRequest", target_iid: 128, target_title: "修右鍵選單焦點" },
		{ action_name: "pushed to", project_id: 12, created_at: tPush.toISOString(), push_data: { ref_type: "branch", ref: "fix/menu", commit_count: 2, commit_title: "修右鍵選單焦點" } },
		{ action_name: "pushed to", project_id: 12, created_at: ago(400).toISOString(), push_data: { ref_type: "branch", ref: "fix/menu", commit_count: 1, commit_title: "先加測試" } },
	];
	cli.glab.pipelines["1.2.0-Production.1"] = [{ status: "running", web_url: "https://gitlab.example.com/web/desk-pals/-/pipelines/9" }];
	cli.gh.events = [
		{ type: "CreateEvent", repo: { name: "octo/pixel-icons" }, created_at: ago(10).toISOString(), payload: { ref_type: "tag", ref: "v0.11.0" } },
		{ type: "PullRequestEvent", repo: { name: "octo/pixel-icons" }, created_at: ago(20).toISOString(), payload: { action: "opened", number: 17, pull_request: { number: 17, title: "補 16px 圖示", html_url: "https://github.com/octo/pixel-icons/pull/17", merged: false, head: { ref: "icons-16" } } } },
		{ type: "PushEvent", repo: { name: "octo/pixel-icons" }, created_at: tGh.toISOString(), payload: { ref: "refs/heads/icons-16", size: 1, commits: [{ message: "補 16px 圖示\n\n細節" }] } },
	];
	cli.gh.runs["octo/pixel-icons"] = [{ head_branch: "main", status: "completed", conclusion: "success", html_url: "x" }, { head_branch: "v0.11.0", status: "completed", conclusion: "failure", html_url: "https://github.com/octo/pixel-icons/actions/runs/5" }];
	saveCli();
	app.send("work-set gitlab 1");
	app.send("work-set github 1");
	app.send("work-set ci 1");
	await check("盯 CI：從 glab／gh 看到你推了 tag（哪個終端機推的都算）→ 跑起來、沒過都會講", async () => {
		const ns = await until("ci notices", async () => { const x = notices(await app.dump()).filter((s) => s.startsWith("ci-")); return x.length >= 2 && x; });
		assert.ok(ns.includes("ci-run https://gitlab.example.com/web/desk-pals/-/pipelines/9 desk-pals 1.2.0-Production.1 正式機CI 開始跑了，好了叫你"), ns.join("\n"));
		assert.ok(ns.includes("ci-fail https://github.com/octo/pixel-icons/actions/runs/5 pixel-icons v0.11.0 部署失敗（failed），點我看 pipeline"), ns.join("\n"));
		await snap(app, "ci-fail-bubble");
	});
	await check("GitLab／GitHub／CI 寫進小本子（推了幾個 commit、開了 MR／PR、CI 結果）", async () => {
		const l = await until("gitlab/github log", () => { const b = readLog(todayStr).by; return b["github:octo/pixel-icons#17:opened"] && b["gitlab:web/desk-pals!128:opened"] && b; });
		assert.deepEqual(l["gitlab:web/desk-pals:push:fix/menu"], { id: "gitlab:web/desk-pals:push:fix/menu", t: fmtLocal(ago(400)), end: fmtLocal(tPush), src: "gitlab", project: "desk-pals", title: "修右鍵選單焦點", status: "推了 3 個 commit", ok: null, ref: "fix/menu", url: "https://gitlab.example.com/web/desk-pals/-/commits/fix/menu", key: "fix/menu" });
		assert.deepEqual(l["gitlab:web/desk-pals!128:opened"], { id: "gitlab:web/desk-pals!128:opened", t: fmtLocal(tMr), src: "gitlab", project: "desk-pals", title: "修右鍵選單焦點", status: "開了 MR", ok: null, ref: "MR !128", url: "https://gitlab.example.com/web/desk-pals/-/merge_requests/128", key: "web/desk-pals" });
		assert.equal(l["github:octo/pixel-icons:push:icons-16"].title, "補 16px 圖示");
		assert.equal(l["github:octo/pixel-icons:push:icons-16"].status, "推了 1 個 commit");
		assert.deepEqual(l["github:octo/pixel-icons#17:opened"], { id: "github:octo/pixel-icons#17:opened", t: fmtLocal(ago(20)), src: "github", project: "pixel-icons", title: "補 16px 圖示", status: "開了 PR", ok: null, ref: "PR #17", url: "https://github.com/octo/pixel-icons/pull/17", key: "icons-16" });
		const ci = l["ci:octo/pixel-icons:v0.11.0"];
		assert.equal(ci.status, "CI 沒過"); assert.equal(ci.ok, false); assert.equal(ci.title, "發 v0.11.0"); assert.ok(ci.end);
		const run = l["ci:web/desk-pals:1.2.0-Production.1"];
		assert.equal(run.status, "CI 跑起來了"); assert.equal(run.ok, null); assert.equal(run.end, undefined);
	});
	cli.glab.pipelines["1.2.0-Production.1"] = [{ status: "success", web_url: "https://gitlab.example.com/web/desk-pals/-/pipelines/9" }];
	saveCli();
	app.send("work-poll");
	await check("盯 CI：跑完了講「部署成功」，小本子那一筆改成 CI 過了（同一個 id 蓋過去）", async () => {
		await until("ci-ok", async () => notices(await app.dump()).some((s) => s === "ci-ok https://gitlab.example.com/web/desk-pals/-/pipelines/9 desk-pals 1.2.0-Production.1 正式機部署成功！"));
		const e = readLog(todayStr).by["ci:web/desk-pals:1.2.0-Production.1"];
		assert.equal(e.status, "CI 過了"); assert.equal(e.ok, true); assert.ok(e.end);
		assert.doesNotMatch(await app.dump(), /^watch gitlab /m);
		assert.match(await app.dump(), /^watch github octo\/pixel-icons v0\.11\.0/m, "沒過的還要繼續看（等重跑）");
	});
	cli.gh.runs["octo/pixel-icons"][1] = { head_branch: "v0.11.0", status: "in_progress", conclusion: null, html_url: "https://github.com/octo/pixel-icons/actions/runs/5" };
	saveCli();
	app.send("work-poll");
	await sleep(2500);
	cli.gh.runs["octo/pixel-icons"][1] = { head_branch: "v0.11.0", status: "completed", conclusion: "success", html_url: "https://github.com/octo/pixel-icons/actions/runs/5" };
	saveCli();
	app.send("work-poll");
	await check("盯 CI：沒過之後重跑過了 → 講「部署成功」，小本子那一筆 ok=true、retried=true（小本子寫「第一次沒過，重跑過了」）", async () => {
		await until("re-run ok", async () => notices(await app.dump()).some((s) => s === "ci-ok https://github.com/octo/pixel-icons/actions/runs/5 pixel-icons v0.11.0 部署成功！"));
		const ns = notices(await app.dump()).filter((s) => s.includes("pixel-icons v0.11.0"));
		assert.equal(ns.length, 2, "重跑中不另外講：" + ns.join("\n"));
		const e = readLog(todayStr).by["ci:octo/pixel-icons:v0.11.0"];
		assert.equal(e.status, "CI 過了"); assert.equal(e.ok, true); assert.equal(e.retried, true); assert.ok(e.end);
		assert.equal(readLog(todayStr).by["ci:web/desk-pals:1.2.0-Production.1"].retried, undefined);
		assert.doesNotMatch(await app.dump(), /^watch /m);
	});
	cli.glab.todos = [{ id: 501, action_name: "review_requested", target_type: "MergeRequest", target: { title: "結帳頁改版" }, author: { name: "Dennis" }, target_url: "https://gitlab.example.com/web/shop/-/merge_requests/3" }];
	cli.gh.notifications = [{ id: "77", reason: "review_requested", updated_at: new Date().toISOString(), subject: { title: "Add dark mode", url: "https://api.github.com/repos/octo/pixel-icons/pulls/18", type: "PullRequest" }, repository: { name: "pixel-icons", full_name: "octo/pixel-icons" } }];
	saveCli();
	app.send("work-poll");
	await check("GitLab 待辦、GitHub 通知：新的才講（第一次只記下來）", async () => {
		const ns = await until("todo + notification", async () => { const x = notices(await app.dump()).filter((s) => /^(gitlab|github) /.test(s)); return x.length >= 2 && x; });
		assert.deepEqual(ns.sort(), [
			"github https://github.com/octo/pixel-icons/pull/18 pixel-icons 請你 review：PR Add dark mode",
			"gitlab https://gitlab.example.com/web/shop/-/merge_requests/3 Dennis 請你 review：MR 結帳頁改版",
		]);
	});
	await check("glab／gh：只叫 auth status 和 api，從來不拿 token", () => {
		const calls = fs.readFileSync(cliLog, "utf8").split("\n").filter(Boolean);
		assert.ok(calls.length > 5);
		for (const c of calls) {
			assert.match(c, /^(glab|gh) (auth status|api )/, c);
			assert.doesNotMatch(c, /token/i, c);
		}
	});

	// ================= 6. 開會 =================
	web.ics = ["BEGIN:VCALENDAR", "VERSION:2.0", "BEGIN:VEVENT", "UID:m1@example.com", "DTSTART:20261123T140000", "DTEND:20261123T150000",
		"SUMMARY:結帳頁改版討論", "LOCATION:https://meet.google.com/abc-defg-hij", "END:VEVENT", "END:VCALENDAR", ""].join("\r\n");
	app.send("work-clock 2026-11-23T13:50");
	app.send(`work-set meet_url http://127.0.0.1:${port}/cal.ics`);
	app.send("work-set meet 1");
	await until("calendar fetched", async () => +stateOf(await app.dump()).meets > 0);
	app.send("work-clock 2026-11-23T13:55:05");
	await check("開會：開會前 5 分鐘提醒", async () => {
		const x = await until("meeting notice", async () => notices(await app.dump()).find((s) => s.startsWith("meeting ")));
		assert.equal(x, "meeting https://meet.google.com/abc-defg-hij 14:00 有會：結帳頁改版討論（5 分鐘後）");
	});
	app.send("work-clock 2026-11-23T14:00:05");
	await check("開會：開始時提醒、開會中自動安靜、會議寫進小本子", async () => {
		const x = await until("meeting-now notice", async () => notices(await app.dump()).find((s) => s.startsWith("meeting-now ")));
		assert.equal(x, "meeting-now https://meet.google.com/abc-defg-hij 結帳頁改版討論 開始了！點我進會議");
		await until("quiet on", async () => +stateOf(await app.dump()).quiet > 50);
		const e = readLog("2026-11-23").by[`calendar:m1@example.com@${new Date(2026, 10, 23, 14, 0).getTime()}`];
		assert.deepEqual(e, { id: `calendar:m1@example.com@${new Date(2026, 10, 23, 14, 0).getTime()}`, t: "2026-11-23T14:00:00", end: "2026-11-23T15:00:00", src: "calendar", title: "結帳頁改版討論", ok: null, url: "https://meet.google.com/abc-defg-hij" });
		const d0 = +stateOf(await app.dump()).dropped;
		app.send("notify meeting-now https://meet.google.com/abc-defg-hij 結帳頁改版討論 開始了！");   // VS Code 也排了同一場
		await sleep(500);
		assert.equal(+stateOf(await app.dump()).dropped, d0 + 1);
	});
	app.send("act quiet 0");

	// ================= 7. 下雨 =================
	web.wttr = { weather: [
		{ date: "2026-11-23", hourly: [{ time: "1500", chanceofrain: "90" }, { time: "1800", chanceofrain: "80" }, { time: "2100", chanceofrain: "60" }] },
		{ date: "2026-11-24", hourly: [{ time: "900", chanceofrain: "20" }] }] };
	app.send("work-clock 2026-11-23T17:35");
	app.send("work-set rain_place 台北");
	app.send("work-set rain 1");
	await check("下雨：平日 17:30 看 wttr.in（只送地點），等一下下班會下雨就提醒", async () => {
		const x = await until("rain notice", async () => notices(await app.dump()).find((s) => s.startsWith("rain ")));
		assert.equal(x, "rain - 等一下下班可能會下雨（降雨機率 80%），記得帶傘 ☔");
		assert.ok(reqs.some((r) => r.startsWith("GET /wttr/Taipei?format=j1")), reqs.join("\n"));
	});
	web.wttrFail = true;
	const met = [];
	for (let h = 0; h < 24; h++) met.push({ time: new Date(2026, 10, 27, h).toISOString(), data: { next_1_hours: { details: { precipitation_amount: h >= 18 && h < 22 ? 0.6 : 0 } } } });
	web.metno = { properties: { timeseries: met } };
	app.send("work-clock 2026-11-27T17:40");
	app.send("work-poll");
	await check("下雨：wttr.in 連不上改用 met.no 的雨量（星期五說下週一）", async () => {
		const x = await until("met.no notice", async () => notices(await app.dump()).filter((s) => s.startsWith("rain "))[1]);
		assert.equal(x, "rain - 等一下下班可能會下雨（預估雨量 2.4 mm），記得帶傘 ☔");
	});
	app.send("work-clock 2026-11-28T17:40");
	app.send("work-poll");
	await sleep(2000);
	await check("下雨：週末不講", async () => assert.equal(notices(await app.dump()).filter((s) => s.startsWith("rain ")).length, 2));
	app.send("work-clock off");

	// ================= 8. 公司網路（VPN）=================
	const tcp = net.createServer((s) => s.destroy());
	await new Promise((r) => tcp.listen(0, "127.0.0.1", r));
	const tport = tcp.address().port;
	app.send(`work-set vpn_host 127.0.0.1:${tport}`);
	app.send("work-set vpn 1");
	await check("公司網路：桌面版設的主機（host:port 也可以）優先，VS Code 的 companyHost 不蓋過去", async () => {
		await until("host set", async () => stateOf(await app.dump()).host === `127.0.0.1:${tport}`);
		assert.match(await app.reply("work-vpncheck", (b) => /work-vpn /.test(b)), /work-vpn ok 127\.0\.0\.1:/);
		app.send("config-host other.example.com");
		await sleep(400);
		assert.equal(stateOf(await app.dump()).host, `127.0.0.1:${tport}`);
		await new Promise((r) => tcp.close(r));
		assert.match(await app.reply("work-vpncheck", (b) => /work-vpn /.test(b)), /work-vpn down /);
	});

	// ================= 9. 工作日誌資料夾 =================
	const wl = path.join(work, "worklog");
	fs.mkdirSync(wl, { recursive: true });
	fs.writeFileSync(path.join(wl, "old.md"), "x"); fs.utimesSync(path.join(wl, "old.md"), ago(86400 * 3), ago(86400 * 3));
	app.send(`work-set worklog_dir ${wl}`);
	app.send("work-set worklog 1");
	await sleep(2500);
	fs.writeFileSync(path.join(wl, "2026-11-19.md"), "今天");
	app.send("work-poll");
	await check("工作日誌資料夾：今天出現新檔才講（第一次只記下來）", async () => {
		const x = await until("worklog notice", async () => { const w = notices(await app.dump()).filter((s) => s.startsWith("worklog ")); return w.length && w; });
		assert.equal(x.length, 1);
		assert.match(x[0], /^worklog file:\/\/\/.*2026-11-19\.md 今天的工作日誌好了：2026-11-19\.md$/);
	});
	await check("work-own：全部來源都交給桌面版（擴充套件連上時看得到）", async () => {
		assert.equal(ownOf(await app.dump()), "jira,gitlab,github,ci,meet,rain,vpn,worklog");
		const s = net.connect(app.target); s.setEncoding("utf8");
		let got = ""; s.on("data", (d) => { got += d; }); await new Promise((r) => s.once("connect", r)); s.write("hello\n");
		await until("hello reply", () => /work-own /.test(got));
		s.destroy();
		assert.match(got, /work-own jira,gitlab,github,ci,meet,rain,vpn,worklog\n/);
	});

	// ================= 10. 改名 WoWo Pals =================
	await check("改名：小屋選單「收工（關掉 WoWo Pals）」，沒有 Desk Pals", async () => {
		app.send("act menu house");
		await sleep(600);
		const m = await app.block("menu-info");
		await snap(app, "house-menu");
		app.send("act menuclose");
		assert.match(m, /收工（關掉 WoWo Pals）/);
		assert.doesNotMatch(m, /Desk Pals/);
	});
	app.send("custom new");
	await sleep(1200);
	await snap(app, "maker-photo-step");   // 選照片那一步下面要有「千萬不要使用有版權的照片」（看截圖）
	app.send("custom cancel");

	// ================= 11. 紀錄的格式（SPEC 2b）=================
	await check("紀錄格式：一行一筆合法 JSON，欄位只有 SPEC 2b 那幾個，時間是本地 ISO，ok 是 true／false／null", () => {
		const dir = path.join(data, "notebook");
		const files = fs.readdirSync(dir).filter((f) => /^log-\d{4}-\d\d-\d\d\.jsonl$/.test(f));
		assert.ok(files.length >= 2, files.join(","));
		const keys = ["id", "t", "end", "src", "project", "title", "status", "ok", "ref", "url", "key", "retried", "gone"];
		const srcs = ["claude", "codex", "jira", "gitlab", "github", "ci", "calendar", "school", "todo", "manual"];
		for (const f of files) {
			const lines = fs.readFileSync(path.join(dir, f), "utf8").split("\n");
			assert.equal(lines.pop(), "", f + " 要以換行結尾");
			const seen = new Set();
			for (const l of lines) {
				const o = JSON.parse(l);
				assert.deepEqual(Object.keys(o).filter((k) => !keys.includes(k)), [], l);
				assert.deepEqual(Object.keys(o), keys.filter((k) => k in o), "欄位順序 " + l);
				for (const k of ["id", "t", "src", "title"]) assert.equal(typeof o[k], "string", k + " " + l);
				assert.ok("ok" in o && (o.ok === null || typeof o.ok === "boolean"), l);
				assert.match(o.t, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$/);
				if ("end" in o) { assert.match(o.end, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$/); assert.ok(o.end >= o.t, l); }
				assert.ok(srcs.includes(o.src), l);
				assert.equal(f, `log-${dayOf(o.end || o.t)}.jsonl`, "寫在結束那天的檔 " + l);
				assert.ok(!seen.has(l), "一模一樣的一行寫了兩次 " + l);
				seen.add(l);
			}
		}
	});

	// ================= 12. 重開：設定、token、紀錄 =================
	const before = readLog(todayStr), idsBefore = new Set(Object.keys(before.by));
	await app.quit();
	await check("Jira token：DPAPI（目前使用者）加密，檔案裡沒有明文，PowerShell 的 ProtectedData 解得開", () => {
		const f = path.join(data, "jira-token.dat");
		const b = fs.readFileSync(f);
		assert.ok(!b.includes(Buffer.from(TOKEN, "utf8")) && !b.includes(Buffer.from(TOKEN, "utf16le")));
		assert.equal(b.readUInt32LE(0), 1, "DPAPI blob 的版本");
		const ps = `Add-Type -AssemblyName System.Security; $b=[IO.File]::ReadAllBytes('${f.replace(/'/g, "''")}'); $p=[Security.Cryptography.ProtectedData]::Unprotect($b,[Text.Encoding]::UTF8.GetBytes('WoWoPals.jira.v1'),'CurrentUser'); [Console]::Out.Write([Convert]::ToBase64String($p))`;
		const out = cp.execFileSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", ps], { encoding: "utf8" }).trim();
		assert.equal(Buffer.from(out, "base64").toString("utf8"), TOKEN);
		assert.doesNotMatch(fs.readFileSync(path.join(data, "work-config.txt"), "utf8"), new RegExp(TOKEN));
		assert.doesNotMatch(fs.readFileSync(path.join(tmp, "desk-pals.log"), "utf8"), new RegExp(TOKEN), "token 不能寫進紀錄檔");
	});
	app = await launch("b");
	await check("重開：設定都還在（work-config.txt）、token 還在、work-own 一連上就送", async () => {
		const c = cfgOf(await app.dump());
		assert.equal(c.jira, "1"); assert.equal(c.jira_site, `http://127.0.0.1:${port}`); assert.equal(c.jira_email, EMAIL); assert.equal(c.token, "1");
		assert.equal(c.meet_url, `http://127.0.0.1:${port}/cal.ics`); assert.equal(c.meet_before, "5"); assert.equal(c.rain_place, "台北");
		assert.equal(c.claude_dir, wslDir.replace(/ /g, "_"));
		assert.match(app.all, /work-own jira,gitlab,github,ci,meet,rain,vpn,worklog\n/);
	});
	app.send("work-poll");
	await sleep(4000);
	await check("重開：已經記過的對話、CI、待辦不會再寫一次或再講一次", async () => {
		assert.equal(readLog(todayStr).raw.filter((l) => idsBefore.has(JSON.parse(l).id)).length, before.raw.length);
		const ns = notices(await app.dump());
		assert.deepEqual(ns.filter((s) => /^(jira|gitlab|github|ci-)/.test(s)), [], ns.join("\n"));
	});
	app.send("work-set jira 0");
	await check("關掉 Jira：work-own 拿掉 jira，VS Code 的 jira 通知又照常", async () => {
		await until("own without jira", async () => !/jira/.test(ownOf(await app.dump())));
		const d0 = +stateOf(await app.dump()).dropped;
		app.send("notify jira - 照常");
		await sleep(400);
		assert.equal(+stateOf(await app.dump()).dropped, d0);
	});
	await app.quit();

	// ================= 13. 離屏（測試）沒設 CLAUDE_CONFIG_DIR／CODEX_HOME：不讀真的家目錄 =================
	const isoData = path.join(work, "iso-data");
	fs.mkdirSync(isoData, { recursive: true });
	app = await launch("iso", isoData);
	app.send("work-poll");
	await sleep(3000);
	await check("離屏測試沒設 CLAUDE_CONFIG_DIR／CODEX_HOME：只看資料資料夾裡的空資料夾，你家目錄的對話、下載、圖片、桌面一個都沒碰", async () => {
		const d = await app.dump();
		const roots = Object.fromEntries((/^work-roots (.*)$/m.exec(d) || ["", ""])[1].split(" ").filter(Boolean).map((kv) => kv.split("=")));
		const inIso = (p) => p.toLowerCase().startsWith((path.resolve(isoData) + path.sep).replace(/ /g, "_").toLowerCase());   // dump 把空白換成 _
		assert.ok(inIso(roots["home-claude"]), d);
		assert.ok(inIso(roots["home-codex"]), d);
		for (const r of (roots.claude + "|" + roots.codex).split("|").filter(Boolean)) assert.ok(inIso(r), "看了資料資料夾以外的地方：" + r);
		for (const k of ["downloads", "pictures", "desktop"]) assert.ok(inIso(roots[k]), k + "：" + roots[k]);
		const home = os.homedir().toLowerCase();
		assert.ok(!d.toLowerCase().includes(path.join(home, ".claude")) && !d.toLowerCase().includes(path.join(home, ".codex")), d);
		const files = [];
		(function walk(p) { for (const e of fs.readdirSync(p, { withFileTypes: true })) { const f = path.join(p, e.name); if (e.isDirectory()) walk(f); else files.push(f); } })(path.join(isoData, "test-home"));
		assert.deepEqual(files, [], "test-home 要是空的");
		assert.ok(!fs.existsSync(path.join(isoData, "notebook")), "沒有對話被寫進小本子");
	});
	await app.quit();
	await check("離屏連 DESKPALS_DATA_DIR 都沒設：資料放暫存資料夾，不用你真的 %LOCALAPPDATA%\\DeskPals", async () => {
		app = await launch("iso2", "no-data-dir");
		const d = await app.dump();
		const roots = Object.fromEntries((/^work-roots (.*)$/m.exec(d) || ["", ""])[1].split(" ").filter(Boolean).map((kv) => kv.split("=")));
		await app.quit();
		const want = path.join(tmp, "DeskPals-offscreen").replace(/ /g, "_").toLowerCase();
		assert.equal(roots.data.toLowerCase(), want, d);
		for (const k of ["home-claude", "home-codex", "downloads", "pictures", "desktop"]) assert.ok(roots[k].toLowerCase().startsWith(want + path.sep), k + "：" + roots[k]);
	});

	server.close();
	let fail = 0;
	for (const [r, name] of results) { console.log(`${r}  ${name}`); if (r !== "PASS") fail++; }
	console.log(`\n${results.length - fail}/${results.length} passed`);
	if (fail) { try { console.log(fs.readFileSync(path.join(tmp, "desk-pals.log"), "utf8").split("\n").filter((l) => /work|notebook|cli/.test(l)).slice(-40).join("\n")); } catch (e) {} }
	process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });

async function snap(app, name) { await app.reply(`snap ${shots}/${name}.png`, (b) => b.includes("snapped")); }
