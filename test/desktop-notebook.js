// 小本子（待辦／今天做了／筆記）的離屏測試：這支自己開、自己關桌面版（每個情境一個臨時資料夾），用 pipe 的 nb-… 指令驅動。
//   假資料（工程師、大學生）照 v011 SPEC 2b 的 log 格式寫進 <資料夾>\notebook\log-YYYY-MM-DD.jsonl；學校行事曆用本機的 ICS（浮動時間＝本地時間）。
//   驗：複製出去的字一個字都不差（簡單／詳細／附上連結）、Jira／MR／CI 掛到同一件事底下、不複製、待辦新增／勾掉／帶到隔天／排序、
//   學校作業自動進待辦、勾掉＝「交了…」、筆記一天一頁自動存、換日、攤開／收起、三頁的空白、預覽原地翻面（視窗不變大）、複製後櫃子裡的公仔講話。
//   剪貼簿：離屏模式不碰真的剪貼簿，用 nb-clip 拿「會複製的字」。
// 不管現在幾點都一樣（CI 是 UTC、cp1252）：時間全部用 study-clock 的假時鐘、資料用本地時間寫，一開始 act light、act lunchend、關串門子。
// 用法：node test/desktop-notebook.js <endpoint 開頭> <工作資料夾> <截圖資料夾> -- <開桌面版的指令…>
//   指令裡的 {ep} 換成這次的 endpoint。例：
//   node test/desktop-notebook.js desk-pals-nb %TEMP%\dp-nb shots\notebook -- build\win\DeskPals.exe --pipe {ep} --pet duoduo --lineup original
//   截圖：1920×1080（主螢幕整張）＋1366×768（從右下角切；櫃子、小本子的位置跟 1366 的螢幕一樣）。NB_SHOTS=0 不截圖。
const cp = require("child_process");
const fs = require("fs");
const net = require("net");
const path = require("path");
const assert = require("node:assert/strict");

const argv = process.argv.slice(2);
const dash = argv.indexOf("--");
const [epBase, work, shots0] = argv.slice(0, dash);
const cmd = argv.slice(dash + 1);
const win = process.platform === "win32";
const shots = path.resolve(shots0).replace(/\\/g, "/");
const doShots = process.env.NB_SHOTS !== "0";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
async function check(name, fn) {
	try { await fn(); results.push(["PASS", name]); }
	catch (e) { results.push(["FAIL", name + "\n      " + String(e.message).split("\n").slice(0, 16).join("\n      ")]); }
}
fs.mkdirSync(work, { recursive: true });
fs.mkdirSync(shots, { recursive: true });

let n = 0;
async function launch(name, data) {
	const ep = win ? `${epBase}-${name}-${++n}` : `${epBase}-${name}-${++n}.sock`;
	const target = win ? "\\\\.\\pipe\\" + ep : ep;
	const env = Object.assign({}, process.env, { DESKPALS_OFFSCREEN: "1", DESKPALS_ISOLATED: "1", DESKPALS_DATA_DIR: data });
	if (win && process.env.NB_PRIVATE_TEMP === "1") { env.TEMP = env.TMP = path.join(work, "tmp"); fs.mkdirSync(env.TEMP, { recursive: true }); }   // 本機跑：紀錄寫到自己的資料夾
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
	// 跟現在幾點無關：白天、沒有午餐、沒有串門子
	app.send("act light"); app.send("act lunchend"); app.send("act feature scenes=0"); app.send("act feature chatter=0");
	await sleep(300);
	return app;
}
function fresh(name) {
	const d = path.join(work, name);
	fs.rmSync(d, { recursive: true, force: true });
	fs.mkdirSync(path.join(d, "notebook"), { recursive: true });
	for (const [f, v] of Object.entries({ "profile.txt": "done", "mode.txt": "shelf", "lineup.txt": "original" })) fs.writeFileSync(path.join(d, f), v);
	return d;
}
const jl = (rows) => rows.map((r) => JSON.stringify(r)).join("\n") + "\n";
function writeLog(data, day, rows) { fs.writeFileSync(path.join(data, "notebook", `log-${day}.jsonl`), jl(rows)); }

// ---- nb-info ----
async function info(app) {
	const d = await app.block("nb-info");
	const head = /nb open=(\d)(.*)/.exec(d) || [];
	const o = { raw: d, open: head[1] === "1" };
	for (const m of (head[2] || "").matchAll(/(\w+)=(\S*)/g)) o[m[1]] = m[2];
	o.things = [...d.matchAll(/^thing (\S+) (on|off)( hot)? \| (.*?)(?: \| (.*))?$/gm)].map((m) => ({ id: m[1], on: m[2] === "on", hot: !!m[3], text: m[4], ids: m[5] }));
	o.todos = [...d.matchAll(/^todo (\S+) (school|mine)( carried)?( hot)? \| (.*?) \| (?:(.*?) \| )?(.*)$/gm)].map((m) => ({ id: m[1], src: m[2], carried: !!m[3], text: m[5], course: m[6] || "", due: m[7] }));
	o.jira = [...d.matchAll(/^jira (.*)$/gm)].map((m) => m[1]);
	o.groups = [...d.matchAll(/^group (.*)$/gm)].map((m) => m[1]);
	o.just = [...d.matchAll(/^justdone (.*)$/gm)].map((m) => m[1]);
	o.sum = (/^sum (.*)$/m.exec(d) || [])[1];
	o.hits = [...d.matchAll(/^hit (\S+) (\S+) (-?\d+) (-?\d+) (\d+) (\d+)$/gm)].map((m) => ({ act: m[1], arg: m[2], x: +m[3], y: +m[4], w: +m[5], h: +m[6] }));
	o.items = [...d.matchAll(/^todoitem (\S+) (\S+) (\S+) (\S+) (.*)$/gm)].map((m) => ({ id: m[1], src: m[2], due: m[3], created: m[4], text: m[5] }));
	o.note = JSON.parse((/^notetext (.*)$/m.exec(d) || [, '""'])[1]);
	o.said = (/^said (.*)$/m.exec(d) || [])[1];
	o.tabs = [...d.matchAll(/^tabbtn (\S+) (\d) (\S*) (-?\d+) (-?\d+) (\d+) (\d+)$/gm)].map((m) => ({ key: m[1], on: m[2] === "1", count: m[3] }));
	o.has = (s) => d.split("\n").some((l) => l.startsWith(s));
	return o;
}
async function text(app, kind) { const d = await app.block("nb-text " + kind); return JSON.parse(/text (.*)/.exec(d)[1]); }
async function clip(app) { const d = await app.block("nb-clip"); return JSON.parse(/clip (.*)/.exec(d)[1]); }
// 櫃子所在那個螢幕的右下角（櫃子貼著工作區右下、工作列 40px）：整張 1920×1080，和從右下角切的 1366×768
async function snap(app, name) {
	if (!doShots) return;
	await sleep(350);
	if (!app.screen) {
		const m = /shelf (-?\d+) (-?\d+) (\d+) (\d+)/.exec(await app.block("shelf-info"));
		app.screen = { right: +m[1] + +m[3] + 6, bottom: +m[2] + +m[4] + 40 };
	}
	const { right, bottom } = app.screen;
	await app.reply(`snap ${shots}/${name}-1920.png ${right - 1920} ${bottom - 1080} 1920 1080`, (b) => b.includes("snapped"));
	await app.reply(`snap ${shots}/${name}-1366.png ${right - 1366} ${bottom - 768} 1366 768`, (b) => b.includes("snapped"));
}
async function click(app, act, arg) {
	const o = await info(app);
	const h = o.hits.find((x) => x.act === act && (arg === undefined || x.arg === arg));
	assert.ok(h, `no hit ${act} ${arg || ""}\n${o.hits.map((x) => x.act + " " + x.arg).join(", ")}`);
	app.send(`nb-click ${h.x + (h.w >> 1)} ${h.y + (h.h >> 1)}`);
	await sleep(250);
}
const clock = async (app, t) => { app.send("study-clock " + t); await sleep(250); };

// ================= 工程師的一天 =================
const ENG = [
	{ id: "calendar:standup@2026-11-19", t: "2026-11-19T09:30", end: "2026-11-19T09:45", src: "calendar", title: "每日站會" },
	{ id: "claude:a1b2c3", t: "2026-11-19T10:02", end: "2026-11-19T11:18", src: "claude", project: "desk-pals", title: "修好右鍵選單一開就關", key: "fix/menu-focus" },
	{ id: "jira:PBG-2231:resolved", t: "2026-11-19T11:05", src: "jira", project: "desk-pals", title: "右鍵選單一開就關", status: "工單解決了", ok: true, ref: "PBG-2231", url: "https://jira.example.com/browse/PBG-2231", key: "PBG-2231" },
	{ id: "gitlab:desk-pals:!128", t: "2026-11-19T11:20", src: "gitlab", project: "desk-pals", title: "修右鍵選單焦點", ref: "MR !128", url: "https://gitlab.example.com/web/desk-pals/-/merge_requests/128", key: "fix/menu-focus" },
	{ id: "ci:desk-pals:fix/menu-focus", t: "2026-11-19T11:24", src: "ci", project: "desk-pals", title: "CI", status: "CI 過了", ok: true, key: "fix/menu-focus" },
	{ id: "calendar:review@2026-11-19", t: "2026-11-19T13:30", end: "2026-11-19T14:20", src: "calendar", title: "結帳頁改版討論" },
	{ id: "codex:d4e5f6", t: "2026-11-19T14:25", end: "2026-11-19T15:40", src: "codex", project: "shop-web", title: "結帳頁金額少一位小數" },
	{ id: "jira:PBG-2240:created", t: "2026-11-19T14:50", src: "jira", project: "shop-web", title: "結帳頁金額少一位小數", status: "新開", ref: "PBG-2240", url: "https://jira.example.com/browse/PBG-2240" },
	{ id: "github:pixel-icons:#17", t: "2026-11-19T15:52", src: "github", project: "pixel-icons", title: "補 16px 圖示", status: "合併了", ok: true, ref: "PR #17", url: "https://github.com/you/pixel-icons/pull/17" },
	{ id: "ci:desk-pals:v0.10.4", t: "2026-11-19T16:10", end: "2026-11-19T16:20", src: "ci", project: "desk-pals", title: "發了 v0.10.4", status: "CI 沒過", ok: false, key: "v0.10.4" },
	{ id: "jira:PBG-2198:testing", t: "2026-11-19T16:30", src: "jira", project: "desk-pals", title: "設定頁字太小", status: "處理中", ref: "PBG-2198", url: "https://jira.example.com/browse/PBG-2198" },
	{ id: "ci:desk-pals:v0.10.4", t: "2026-11-19T16:10", end: "2026-11-19T16:41", src: "ci", project: "desk-pals", title: "發了 v0.10.4", status: "CI 過了", ok: true, retried: true, key: "v0.10.4" },   // 同一個 id 後寫的蓋前寫的
	{ id: "jira:PBG-2198:testing2", t: "2026-11-19T16:45", src: "jira", project: "desk-pals", title: "設定頁字太小", status: "測試中", ref: "PBG-2198", url: "https://jira.example.com/browse/PBG-2198" },   // 同一張單改兩次：只留最後
	{ id: "jira:PBG-2251:assigned", t: "2026-11-19T08:00", src: "jira", title: "設定頁深色模式跑版", status: "待處理", ref: "PBG-2251", todo: true },
	{ id: "jira:PBG-2263:assigned", t: "2026-11-19T08:00", src: "jira", title: "折扣碼不分大小寫", status: "處理中", ref: "PBG-2263", todo: true },
	{ id: "jira:PBG-2100:assigned", t: "2026-11-19T08:00", src: "jira", title: "已經結了的單", status: "完成", ref: "PBG-2100", todo: false },
];
const ENG_YESTERDAY = [{ id: "claude:y1", t: "2026-11-18T15:00", end: "2026-11-18T16:00", src: "claude", project: "desk-pals", title: "整理右鍵選單的測試" }];
const ENG_TODO = { items: [
	{ id: "t1", text: "回覆 QA 匯出格式的問題", created: "2026-11-18" },
	{ id: "t2", text: "寫 v0.10.4 更新說明", created: "2026-11-19", due: "2026-11-19T18:00" },
	{ id: "t3", text: "整理 shop-web 測試資料", created: "2026-11-19" },
	{ id: "t4", text: "跟後端對折扣碼規則", created: "2026-11-19", due: "2026-11-20" },
	{ id: "t5", text: "跟設計對了新版圖示", created: "2026-11-19" },
] };

const ENG_DETAIL = `11/19（四）進度

【desk-pals】
・10:02–11:18 修好右鍵選單一開就關
　- PBG-2231 解決了
　- MR !128，CI 過了
・16:10 發了 v0.10.4
　- CI 第一次沒過，16:41 重跑過了
・16:45 PBG-2198 設定頁字太小，測試中

【shop-web】
・14:25–15:40 結帳頁金額少一位小數
　- 新開 PBG-2240

【pixel-icons】
・15:52 PR #17 補 16px 圖示，合併了

【會議】
・13:30–14:20 結帳頁改版討論

【其他】
・17:02 跟設計對了新版圖示`;
const ENG_LINKS = `11/19（四）進度

【desk-pals】
・10:02–11:18 修好右鍵選單一開就關
　- PBG-2231 解決了 https://jira.example.com/browse/PBG-2231
　- MR !128，CI 過了 https://gitlab.example.com/web/desk-pals/-/merge_requests/128
・16:10 發了 v0.10.4
　- CI 第一次沒過，16:41 重跑過了
・16:45 PBG-2198 設定頁字太小，測試中 https://jira.example.com/browse/PBG-2198

【shop-web】
・14:25–15:40 結帳頁金額少一位小數
　- 新開 PBG-2240 https://jira.example.com/browse/PBG-2240

【pixel-icons】
・15:52 PR #17 補 16px 圖示，合併了 https://github.com/you/pixel-icons/pull/17

【會議】
・13:30–14:20 結帳頁改版討論

【其他】
・17:02 跟設計對了新版圖示`;
const ENG_SIMPLE = `・修好右鍵選單一開就關（desk-pals）
・發了 v0.10.4（desk-pals）
・PBG-2198 設定頁字太小，測試中（desk-pals）
・結帳頁金額少一位小數（shop-web）
・PR #17 補 16px 圖示，合併了（pixel-icons）
・開會：結帳頁改版討論
・跟設計對了新版圖示`;

// ================= 大學生的一天 =================
const CLASSES_ICS = `BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Google Inc//Google Calendar 70.9054//EN
X-WR-CALNAME:課表
BEGIN:VEVENT
UID:ds-lecture@example.edu
DTSTART:20261105T081000
DTEND:20261105T100000
RRULE:FREQ=WEEKLY;BYDAY=TH
SUMMARY:資料結構
LOCATION:資工館 101
END:VEVENT
BEGIN:VEVENT
UID:media-lecture@example.edu
DTSTART:20261105T132000
DTEND:20261105T151000
RRULE:FREQ=WEEKLY;BYDAY=TH
SUMMARY:媒體與社會
LOCATION:社科院 204
END:VEVENT
END:VCALENDAR
`;
const CANVAS_ICS = `BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Instructure//Canvas//EN
BEGIN:VEVENT
UID:event-assignment-9003
DTSTART:20261119T235900
DTEND:20261119T235900
SUMMARY:HW3 二元搜尋樹 [資料結構]
URL:https://cool.example.edu/courses/1/assignments/9003
END:VEVENT
BEGIN:VEVENT
UID:event-assignment-9004
DTSTART:20261120T235900
DTEND:20261120T235900
SUMMARY:HW4 [資料結構]
URL:https://cool.example.edu/courses/1/assignments/9004
END:VEVENT
BEGIN:VEVENT
UID:event-assignment-9101
DTSTART:20261121T235900
DTEND:20261121T235900
SUMMARY:期中報告大綱 [統計學]
URL:https://cool.example.edu/courses/2/assignments/9101
END:VEVENT
END:VCALENDAR
`;
const STU = [
	{ id: "claude:bst", t: "2026-11-19T10:20", end: "2026-11-19T11:45", src: "claude", project: "資料結構", title: "修好 BST 刪除節點的測試", key: "bst-delete" },
	{ id: "github:ds-hw3:#4", t: "2026-11-19T11:50", src: "github", project: "ds-hw3", title: "BST 刪除節點", status: "合併了，測試過了", ok: true, ref: "PR #4", url: "https://github.com/you/ds-hw3/pull/4", key: "bst-delete" },
	{ id: "codex:login", t: "2026-11-19T15:30", end: "2026-11-19T16:40", src: "codex", project: "team-app", title: "分組專題登入頁", key: "login-page" },
	{ id: "github:team-app:#12", t: "2026-11-19T16:45", src: "github", project: "team-app", title: "登入頁", status: "測試沒過", ok: false, ref: "PR #12", url: "https://github.com/team-7/team-app/pull/12" },
	{ id: "calendar:team@2026-11-19", t: "2026-11-19T19:00", end: "2026-11-19T20:00", src: "calendar", project: "team-app", title: "分組報告討論（線上）" },
];
const STU_TODO = { items: [
	{ id: "u1", text: "回組員分工訊息", created: "2026-11-19", due: "2026-11-19T22:00" },
	{ id: "u2", text: "借統計學課本", created: "2026-11-18" },
	{ id: "u3", text: "複習資料結構第 6 章", created: "2026-11-19" },
	{ id: "u4", text: "統計學讀完第 5 章", created: "2026-11-19" },
	{ id: "u5", text: "期末報告投影片做了 6 頁", created: "2026-11-19" },
] };
const STU_DETAIL = `11/19（四）進度

【資料結構】
・08:10–10:00 上課：資料結構
・10:05 交了 HW3 二元搜尋樹
・10:20–11:45 修好 BST 刪除節點的測試
　- PR #4 合併了，測試過了

【媒體與社會】
・13:20–15:10 上課：媒體與社會

【team-app】
・15:30–16:40 分組專題登入頁
　- PR #12，測試沒過
・19:00–20:00 開會：分組報告討論（線上）

【其他】
・20:05 統計學讀完第 5 章
・20:10 期末報告投影片做了 6 頁`;
const STU_SIMPLE = `・上課：資料結構
・交了 HW3 二元搜尋樹（資料結構）
・修好 BST 刪除節點的測試（資料結構）
・上課：媒體與社會
・分組專題登入頁（team-app）
・開會：分組報告討論（線上）
・統計學讀完第 5 章
・期末報告投影片做了 6 頁`;

(async () => {
	// ---------------- 工程師 ----------------
	{
		const data = fresh("eng");
		writeLog(data, "2026-11-19", ENG);
		writeLog(data, "2026-11-18", ENG_YESTERDAY);
		fs.writeFileSync(path.join(data, "notebook", "todo.json"), JSON.stringify(ENG_TODO));
		const app = await launch("eng", data);
		await clock(app, "2026-11-19T17:00");
		app.send("nb-open");
		await sleep(600);
		let o = await info(app);
		await check("第一次打開停在「今天做了」；446 寬（加左邊凸出的線圈 10）× 670", () => {
			assert.ok(o.open, o.raw);
			assert.equal(o.tab, "done");
			assert.equal(o.spread, "0");
			assert.equal(+o.w, 456); assert.equal(+o.h, 670);
		});
		await check("停在公仔櫃左邊：底部離工作列 8px、木框右緣離櫃子 16px", async () => {
			const sh = await app.block("shelf-info");
			const m = /shelf (-?\d+) (-?\d+) (\d+) (\d+)/.exec(sh);
			assert.equal(+o.frame + 446 + 16, +m[1]);
			assert.equal(+o.y + 670, +m[2] + +m[4] - 8);
		});
		await check("合併：Jira、MR、CI 掛到同一個對話底下，句尾是白話結果；同一張單只留最後；指派給我的不在今天做了", () => {
			assert.deepEqual(o.things.map((t) => t.text), [
				"修好右鍵選單一開就關，工單解決了，CI 過了",
				"發了 v0.10.4，CI 重跑後過了",
				"設定頁字太小，測試中",
				"結帳頁金額少一位小數，開了單",
				"補 16px 圖示，合併了",
				"每日站會",
				"結帳頁改版討論",
			]);
			assert.deepEqual(o.groups, ["desk-pals", "shop-web", "pixel-icons", "會議"]);
			assert.equal(o.sum, "今天 7 件 | CI 都過了");
		});
		await check("頁籤：待辦 7（5 件＋Jira 2）、今天做了 7、筆記沒有數字", () => {
			assert.deepEqual(o.tabs.map((t) => [t.key, t.on, t.count]), [["todo", false, "7"], ["done", true, "7"], ["note", false, ""]]);
		});
		app.send("nb-hoverthing claude:a1b2c3");
		await sleep(150);
		o = await info(app);
		await check("滑過一行：代號和時間才出現，旁邊有「不複製」", () => {
			const t = o.things.find((x) => x.id === "claude:a1b2c3");
			assert.ok(t.hot);
			assert.equal(t.ids, "PBG-2231　MR !128　10:02–11:18");
			assert.ok(o.hits.some((h) => h.act === "off" && h.arg === "claude:a1b2c3"));
		});
		await snap(app, "eng-done-hover");
		app.send("nb-hoverthing -");
		// 不複製：點那一行的「不複製」（用真的點擊位置）
		app.send("nb-hoverthing calendar:standup@2026-11-19");
		await sleep(150);
		await click(app, "off", "calendar:standup@2026-11-19");
		app.send("nb-hoverthing -");
		await sleep(150);
		o = await info(app);
		await check("不複製：那行變灰加刪除線、右邊「要複製」、底部「會複製 6 件」；存在 edits-2026-11-19.json", () => {
			assert.equal(o.things.find((x) => x.id === "calendar:standup@2026-11-19").on, false);
			assert.ok(o.hits.some((h) => h.act === "on" && h.arg === "calendar:standup@2026-11-19"));
			assert.ok(o.has("foot 6 "), o.raw);
			const ed = JSON.parse(fs.readFileSync(path.join(data, "notebook", "edits-2026-11-19.json"), "utf8"));
			assert.deepEqual(ed.off, ["calendar:standup@2026-11-19"]);
		});

		// 待辦：勾掉 → 今天做了（17:02）
		await click(app, "tab", "todo");
		o = await info(app);
		await check("待辦：從昨天、今天到期紅字、明天、Jira 指派給我（只顯示狀態，結了的不列）", () => {
			assert.equal(o.tab, "todo");
			assert.deepEqual(o.todos.map((t) => [t.id, t.carried, t.text, t.due]), [
				["t1", true, "回覆 QA 匯出格式的問題", ""], ["t2", false, "寫 v0.10.4 更新說明", "今天 18:00 !"], ["t3", false, "整理 shop-web 測試資料", ""],
				["t4", false, "跟後端對折扣碼規則", "明天"], ["t5", false, "跟設計對了新版圖示", ""]]);
			assert.deepEqual(o.jira, ["PBG-2251 設定頁深色模式跑版 | 待處理", "PBG-2263 折扣碼不分大小寫 | 處理中"]);
			assert.ok(!o.hits.some((h) => h.act === "tick" && /PBG/.test(h.arg)), "Jira 不能勾");
		});
		await clock(app, "2026-11-19T17:02");
		await click(app, "tick", "t5");
		o = await info(app);
		await check("勾掉：先留在原地「▶ 今天做了」，頁籤數字 +1；log 多一筆 src=todo、時間是勾的時間", () => {
			assert.deepEqual(o.just, ["跟設計對了新版圖示"]);
			assert.equal(o.tabs.find((t) => t.key === "done").count, "8");
			assert.equal(o.tabs.find((t) => t.key === "todo").count, "6");
			const log = fs.readFileSync(path.join(data, "notebook", "log-2026-11-19.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
			const f = log.find((x) => x.id === "todo:t5");
			assert.equal(f.src, "todo"); assert.equal(f.title, "跟設計對了新版圖示"); assert.equal(f.t, "2026-11-19T17:02:00");
		});
		await sleep(2200);
		o = await info(app);
		await check("一下子之後那一行就不在待辦了", () => assert.deepEqual(o.just, []));

		// 排序：Alt+↓、拖曳
		app.send("nb-hovertodo t1");
		app.send("nb-key alt-down");
		await sleep(200);
		o = await info(app);
		await check("Alt+↓：滑鼠下面那一件往下一格（存進 todo.json）", () => {
			assert.deepEqual(o.items.map((t) => t.id), ["t2", "t1", "t3", "t4"]);
			assert.deepEqual(JSON.parse(fs.readFileSync(path.join(data, "notebook", "todo.json"), "utf8")).items.map((t) => t.id), ["t2", "t1", "t3", "t4"]);
		});
		app.send("nb-key alt-up");
		app.send("nb-drag t4 0");
		await sleep(200);
		o = await info(app);
		await check("Alt+↑ 回去、拖到最上面", () => assert.deepEqual(o.items.map((t) => t.id), ["t4", "t1", "t2", "t3"]));
		app.send("nb-drag t4 3");

		// 新增：打一行＋期限（週六 22:00）
		app.send("nb-type todo 買海報紙");
		await click(app, "due");
		o = await info(app);
		await check("小日曆：今天、明天、週六…、時間", () => assert.ok(o.has("duepick"), o.raw));
		await click(app, "dueday", "2");
		await click(app, "duetime", "1320");
		o = await info(app);
		await check("選了期限：輸入框右邊出現「週六 22:00」", () => assert.ok(o.has("field todo 買海報紙 | 週六 22:00"), o.raw));
		await snap(app, "eng-todo-typing");
		app.send("nb-key todo enter");
		await sleep(200);
		o = await info(app);
		await check("Enter：加到最下面，帶期限、今天建立", () => {
			const t = o.items[o.items.length - 1];
			assert.equal(t.text, "買海報紙"); assert.equal(t.due, "2026-11-21T22:00"); assert.equal(t.created, "2026-11-19");
			assert.ok(o.has("field todo -"), "輸入框清空");
		});
		await snap(app, "eng-todo");

		// 取消勾（點錯了）
		const added = o.items[o.items.length - 1].id;
		await click(app, "tick", added);
		await click(app, "untick", added);
		o = await info(app);
		await check("勾錯了再點一次：回到待辦，今天做了不會多一件（log 寫 gone）", () => {
			assert.ok(o.items.some((t) => t.id === added));
			assert.equal(o.tabs.find((t) => t.key === "done").count, "8");
		});

		// 今天做了：複製
		await click(app, "tab", "done");
		await check("詳細（不附連結）：照 NOTES v5 的格式", async () => assert.equal(await text(app, "detail"), ENG_DETAIL));
		await check("詳細（附上連結）", async () => assert.equal(await text(app, "links"), ENG_LINKS));
		await check("簡單", async () => assert.equal(await text(app, "simple"), ENG_SIMPLE));
		const before = await info(app);
		await click(app, "pv");
		o = await info(app);
		await check("預覽：在原頁翻面（視窗不長高），預設詳細、不附連結", () => {
			assert.equal(o.preview, "1"); assert.equal(o.h, before.h); assert.equal(o.w, before.w);
			assert.ok(o.has("preview detail links=0"), o.raw);
		});
		await snap(app, "eng-preview");
		await click(app, "links");
		await click(app, "kind", "simple");
		o = await info(app);
		await check("預覽：切簡單、勾附上連結", () => { assert.ok(o.has("preview simple links=1"), o.raw); assert.ok(o.has("pvbar open simple links=1")); });
		await snap(app, "eng-preview-simple");
		await click(app, "copy", "detail");
		await sleep(400);
		o = await info(app);
		await check("複製詳細（勾了附上連結）：剪貼簿的字＝附連結的詳細；按鈕變「已複製詳細」；櫃子裡的公仔說話", async () => {
			assert.equal(await clip(app), ENG_LINKS);
			assert.equal(o.copied, "detail");
			assert.equal(o.said, "好了，去貼上吧");
		});
		await click(app, "pv");
		await snap(app, "eng-copied");
		await click(app, "copy", "simple");
		await check("複製簡單", async () => assert.equal(await clip(app), ENG_SIMPLE));
		app.send("nb-act links");
		await sleep(3200);

		// 改字：點一下標題改
		await click(app, "edit", "claude:a1b2c3");
		app.send("nb-type edit 修好右鍵選單一開就關（焦點）");
		app.send("nb-key edit enter");
		await sleep(250);
		await check("點一下標題就能改字（存在 edits），複製出去也用新的字", async () => {
			const t = await text(app, "simple");
			assert.ok(t.startsWith("・修好右鍵選單一開就關（焦點）（desk-pals）"), t);
			const ed = JSON.parse(fs.readFileSync(path.join(data, "notebook", "edits-2026-11-19.json"), "utf8"));
			assert.equal(ed.titles["claude:a1b2c3"], "修好右鍵選單一開就關（焦點）");
		});
		await click(app, "edit", "claude:a1b2c3");
		app.send("nb-type edit 修好右鍵選單一開就關");
		app.send("nb-key edit enter");
		await sleep(200);
		await snap(app, "eng-done");

		// 補一件做過的事
		app.send("nb-type done 回了設計稿的意見");
		app.send("nb-key done enter");
		await sleep(300);
		o = await info(app);
		await check("補一件做過的事：加在其他，時間是現在", async () => {
			assert.ok(o.things.some((t) => t.text === "回了設計稿的意見"));
			assert.ok((await text(app, "detail")).endsWith("・17:02 回了設計稿的意見"));
		});
		// 手寫的改成空白＝刪掉
		const mine = o.things.find((t) => t.text === "回了設計稿的意見").id;
		await click(app, "edit", mine);
		app.send("nb-type edit  ");
		app.send("nb-key edit enter");
		await sleep(250);
		o = await info(app);
		await check("手寫的改成空白＝刪掉（edits 的 gone）", () => {
			assert.ok(!o.things.some((t) => t.id === mine));
			assert.deepEqual(JSON.parse(fs.readFileSync(path.join(data, "notebook", "edits-2026-11-19.json"), "utf8")).gone, [mine]);
		});

		// 筆記：自動存、一天一頁
		await click(app, "tab", "note");
		o = await info(app);
		await check("筆記空白：提示字、「複製筆記」不能按、沒有「已存」", () => { assert.ok(o.has("note saved=- empty")); assert.ok(!o.hits.some((h) => h.act === "copy")); });
		await snap(app, "eng-empty-note");
		await clock(app, "2026-11-19T17:08");
		app.send("nb-type note PBG-2240：後端回傳金額是字串，parseFloat 前先 trim\\n折扣碼要不要分大小寫 → 明天問 PM\\ntag v0.10.4 前記得改 changelog\\n");
		await sleep(1400);
		o = await info(app);
		await check("筆記自動存：note-2026-11-19.txt、「已存 17:08」", () => {
			assert.equal(fs.readFileSync(path.join(data, "notebook", "note-2026-11-19.txt"), "utf8"), "PBG-2240：後端回傳金額是字串，parseFloat 前先 trim\n折扣碼要不要分大小寫 → 明天問 PM\ntag v0.10.4 前記得改 changelog\n");
			assert.equal(o.saved, "17:08");
		});
		await snap(app, "eng-note");
		await click(app, "copy", "note");
		await check("複製筆記：照原樣、沒有標頭", async () => assert.equal(await clip(app), "PBG-2240：後端回傳金額是字串，parseFloat 前先 trim\n折扣碼要不要分大小寫 → 明天問 PM\ntag v0.10.4 前記得改 changelog"));

		// 換日：◀ 昨天
		await click(app, "prev");
		o = await info(app);
		await check("◀：昨天的今天做了、筆記是另一頁（空的）；▶ 能按、出現「回今天」", () => {
			assert.equal(o.day, "2026-11-18");
			assert.equal(o.note, "");
			assert.ok(o.hits.some((h) => h.act === "next") && o.hits.some((h) => h.act === "today"));
		});
		app.send("nb-type note 昨天的筆記");
		await sleep(1300);
		await click(app, "tab", "done");
		o = await info(app);
		await check("昨天：只有昨天的事，標頭寫「昨天」", () => {
			assert.deepEqual(o.things.map((t) => t.text), ["整理右鍵選單的測試"]);
			assert.equal(o.sum, "昨天 1 件");
		});
		await snap(app, "eng-yesterday");
		await click(app, "today");
		await click(app, "tab", "note");
		o = await info(app);
		await check("回今天：今天的筆記還在；昨天那頁另外存", () => {
			assert.equal(o.day, "2026-11-19");
			assert.ok(o.note.startsWith("PBG-2240"));
			assert.equal(fs.readFileSync(path.join(data, "notebook", "note-2026-11-18.txt"), "utf8"), "昨天的筆記");
		});

		// 攤開／收起
		await click(app, "spread");
		o = await info(app);
		await check("攤開：760×636（放得進 1366×768）、沒有頁籤、左頁待辦＋筆記、右頁今天做了；右緣不動", () => {
			assert.equal(o.spread, "1"); assert.equal(+o.w, 770); assert.equal(+o.h, 636);
			assert.equal(o.tabs.length, 0);
			assert.ok(o.todos.length > 0 && o.has("note saved="));
			assert.equal(o.things.length, 8, o.things.map((t) => t.text).join(" / "));
			assert.ok(+o.h + 8 <= 728 && 760 + 16 + 256 + 6 <= 1366, "1366×768 放得下");
		});
		await snap(app, "eng-spread");
		await click(app, "spread");
		o = await info(app);
		await check("收起：回到攤開前的那一頁（筆記）", () => { assert.equal(o.spread, "0"); assert.equal(o.tab, "note"); assert.equal(+o.w, 456); });
		app.send("nb-close");
		await sleep(300);
		app.send("nb-open");
		await sleep(500);
		o = await info(app);
		await check("再打開：記得上次停在哪一頁", () => assert.equal(o.tab, "note"));
		await app.quit();
	}

	// ---------------- 大學生（學校行事曆）----------------
	{
		const data = fresh("stu");
		writeLog(data, "2026-11-19", STU);
		fs.writeFileSync(path.join(data, "notebook", "todo.json"), JSON.stringify(STU_TODO));
		const ics1 = path.join(work, "classes.ics"), ics2 = path.join(work, "canvas.ics");
		fs.writeFileSync(ics1, CLASSES_ICS); fs.writeFileSync(ics2, CANVAS_ICS);
		const app = await launch("stu", data);
		await clock(app, "2026-11-19T10:05");
		app.send(`study-ics ${ics1.replace(/\\/g, "/")} https://calendar.google.com/calendar/ical/student%40example.com/private-0123/basic.ics`);
		app.send(`study-ics ${ics2.replace(/\\/g, "/")} https://cool.example.edu/feeds/calendars/user_abc.ics`);
		await sleep(600);
		app.send("nb-open todo");
		await sleep(600);
		let o = await info(app);
		await check("學校的作業自動進待辦（課名、截止時間），放在最上面", () => {
			assert.deepEqual(o.todos.slice(0, 3).map((t) => [t.src, t.text, t.course, t.due]), [
				["school", "HW3 二元搜尋樹", "資料結構", "今天 23:59 !"], ["school", "HW4", "資料結構", "明天 23:59"], ["school", "期中報告大綱", "統計學", "週六 23:59"]]);
			assert.ok(o.todos.find((t) => t.id === "u2").carried);
		});
		await snap(app, "stu-todo");
		const hw3 = o.todos[0].id;
		await click(app, "tick", hw3);
		await sleep(2200);
		o = await info(app);
		await check("勾掉作業＝交了：從待辦拿掉，學校那邊記成交了（study-done.txt）", () => {
			assert.ok(!o.todos.some((t) => t.text === "HW3 二元搜尋樹"));
			assert.match(fs.readFileSync(path.join(data, "study-done.txt"), "utf8"), /event-assignment-9003/);
		});
		await clock(app, "2026-11-19T20:05");
		await click(app, "tick", "u4");
		await clock(app, "2026-11-19T20:10");
		await click(app, "tick", "u5");
		await clock(app, "2026-11-19T20:15");
		await sleep(2000);
		app.send("nb-reload");
		await click(app, "tab", "done");
		o = await info(app);
		await check("今天做了：上過的課（照課表）、交了 HW3 在那一課底下、PR 掛在對話底下、測試沒過寫在最上面", () => {
			assert.deepEqual(o.things.map((t) => t.text), [
				"上課", "交了 HW3 二元搜尋樹", "修好 BST 刪除節點的測試，合併了，測試過了", "上課",
				"分組專題登入頁，測試沒過", "開會：分組報告討論（線上）", "統計學讀完第 5 章", "期末報告投影片做了 6 頁"]);
			assert.deepEqual(o.groups, ["資料結構", "媒體與社會", "team-app", "其他"]);
			assert.equal(o.sum, "今天 8 件 | team-app 測試沒過");
		});
		await check("學生的詳細", async () => assert.equal(await text(app, "detail"), STU_DETAIL));
		await check("學生的簡單", async () => assert.equal(await text(app, "simple"), STU_SIMPLE));
		await snap(app, "stu-done");
		await click(app, "copy", "detail");
		await sleep(300);
		await snap(app, "stu-copied");
		await click(app, "spread");
		await snap(app, "stu-spread");
		await app.quit();
	}

	// ---------------- 空白（剛裝好）----------------
	{
		const data = fresh("empty");
		const app = await launch("empty", data);
		await clock(app, "2026-11-19T17:10");
		app.send("nb-open");
		await sleep(600);
		let o = await info(app);
		await check("今天做了空白：「接上之後，做過的事會自己記下來」、來源清單、補一件的輸入框、複製按鈕不能按", () => {
			assert.equal(o.tab, "done");
			assert.ok(o.has("empty done"));
			assert.ok(o.hits.some((h) => h.act === "connect" && h.arg === "jira"));
			assert.ok(!o.hits.some((h) => h.act === "connect" && h.arg === "claude"), "Claude Code／Codex 已接上");
			assert.ok(o.has("foot -1 copied=- off"), o.raw);
			assert.ok(!o.hits.some((h) => h.act === "copy"));
		});
		await snap(app, "empty-done");
		await click(app, "connect", "jira");
		await check("「接上」打開工作設定（work-sources 提供 OpenWorkSettings）", async () => { o = await info(app); assert.ok(o.said && o.said !== "-"); });
		await click(app, "tab", "todo");
		o = await info(app);
		await check("待辦空白：「還沒有待辦」＋輸入框", () => assert.ok(o.has("empty todo")));
		await snap(app, "empty-todo");
		await click(app, "tab", "note");
		await snap(app, "empty-note");
		await app.quit();
	}

	let fail = 0;
	for (const [r, t] of results) { console.log(r + "  " + t); if (r === "FAIL") fail++; }
	console.log(`${results.length - fail}/${results.length} passed`);
	process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
