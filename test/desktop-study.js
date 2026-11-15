// 桌面版讀書小幫手的離屏測試（DESKPALS_OFFSCREEN=1 跑起來的桌面版，用 pipe 的測試指令驅動）：
//   本機的範例 ICS（test/fixtures，照 Canvas／Moodle／Classroom／Google 真實格式寫）＋假時鐘 → 分類、上課提醒、自動安靜、
//   作業死線、考試倒數、熬夜提醒、搶課、設定（含 VS Code 優先）。不連網路。
// 用法：先用離屏模式啟動桌面版（pipe 名稱自訂），再 node test/desktop-study.js <pipe> [截圖資料夾]
//   Mac：<pipe> 換成 unix socket 的路徑（桌面版的 argv[1]）
// 時區：範例的時間用台北時間寫，要在 UTC+8 的電腦上跑。
const net = require("net");
const path = require("path");
const assert = require("node:assert/strict");

const pipe = process.argv[2] || "desk-pals-studytest";
const shots = (process.argv[3] || path.join(__dirname, "..", "shots")).replace(/\\/g, "/");
const fx = (f) => path.join(__dirname, "fixtures", f).replace(/\\/g, "/");
const CANVAS = "https://cool.ntu.edu.tw/feeds/calendars/user_AbCdEf0123456789.ics";
const MOODLE = "https://moodle.example.edu.tw/calendar/export_execute.php?userid=12&authtoken=0123abcd&preset_what=all&preset_time=recentupcoming";
const CLASSROOM = "https://calendar.google.com/calendar/ical/c_classroom8f3e2a1b%40group.calendar.google.com/private-0123456789abcdef/basic.ics";
const GOOGLE = "https://calendar.google.com/calendar/ical/student%40example.com/private-0123456789abcdef/basic.ics";

// Windows：pipe 名稱；Mac：unix socket 的路徑（含 / 就當成路徑，見 .github/workflows/build.yml）
const s = net.connect(pipe.includes("/") ? pipe : "\\\\.\\pipe\\" + pipe);
s.setEncoding("utf8");
let buf = "";
s.on("data", (d) => { buf += d; });
s.on("error", (e) => { console.error("PIPE", e.message); process.exit(2); });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const send = (l) => s.write(l + "\n");
async function dump() {
	buf = "";
	send("study-dump");
	for (let i = 0; i < 100 && !/\nend\n/.test("\n" + buf); i++) await sleep(50);
	const out = buf.slice(buf.indexOf("study now="));
	return out.slice(0, out.indexOf("\nend\n") + 1);
}
async function snap(name) { buf = ""; send(`snap ${shots}/${name}.png`); for (let i = 0; i < 100 && !buf.includes("snapped"); i++) await sleep(50); }
const lines = (d, kind) => d.split("\n").filter((l) => l.startsWith(kind + " "));
const field = (d, k) => (new RegExp(`\\b${k}=(\\S*)`).exec(d.split("\n")[0]) || [])[1];
const results = [];
async function check(name, fn) {
	try { await fn(); results.push(["PASS", name]); }
	catch (e) { results.push(["FAIL", name + "\n      " + String(e.message).split("\n").slice(0, 12).join("\n      ")]); }
}

s.on("connect", async () => {
	send("hello");
	await sleep(1500);
	send("study-idle 0");
	send("study-clock 2026-11-16T09:00");
	send(`study-ics ${fx("canvas-ntucool.ics")} ${CANVAS}`);
	send(`study-ics ${fx("moodle.ics")} ${MOODLE}`);
	send(`study-ics ${fx("classroom.ics")} ${CLASSROOM}`);
	send(`study-ics ${fx("google-personal.ics")} ${GOOGLE}`);
	await sleep(800);
	let d = await dump();

	await check("Canvas／Moodle／Classroom／Google：作業死線（標題、課名、截止時間、連結）", () => {
		assert.deepEqual(lines(d, "deadline"), [
			"deadline 2026-11-17T23:00 stage=1 期中心得討論 Required Replies (2) [GEN1234] https://cool.ntu.edu.tw/courses/40001/assignments/88000",
			"deadline 2026-11-17T23:59 stage=1 Lab report 2 [PHYS101] https://moodle.example.edu.tw/calendar/view.php?view=day&time=1794931140",
			"deadline 2026-11-18T17:00 stage=1 Essay draft [高三英文 (3年2班)] https://classroom.google.com/c/NzY1NDMyMTA5ODc2/a/OTg3NjU0MzIxMDk4/details",
			"deadline 2026-11-18T23:59 stage=1 HW3：Integration by parts [MATH4006] https://cool.ntu.edu.tw/courses/33845/assignments/1234567",
			"deadline 2026-11-19T23:59 stage=0 Reading log 5 [高三英文 (3年2班)] https://classroom.google.com/c/NzY1NDMyMTA5ODc2/a/ODc2NTQzMjEwOTg3/details",
			"deadline 2026-11-20T23:59 stage=0 期中報告初稿 [GEN1234] https://cool.ntu.edu.tw/courses/40001/assignments/1234599",
			"deadline 2026-11-21T22:00 stage=0 Quiz 4 [PHYS101] https://moodle.example.edu.tw/calendar/view.php?view=day&time=1795269600",
			"deadline 2026-11-21T23:00 stage=0 期末報告繳交截止 -",
			"deadline 2026-11-26T23:59 stage=0 期末專題 [CS-入門] https://moodle.example.edu.tw/calendar/view.php?view=day&time=1795708740",
		]);
	});
	await check("行事曆上的考試進考試倒數（Canvas 活動、自己日曆的小考）", () => {
		assert.deepEqual(lines(d, "exam").map((l) => l.replace(/ daily=\S* before=\d morning=\d/, "")), [
			"exam ics 2026-11-17T08:10 英文小考",
			"exam ics 2026-11-25T09:00 期中考（MATH4006）",
		]);
	});
	await check("上課／行程／考試提醒排程（Office hours 是行程、Lecture 是上課、EXDATE 那天沒有）", () => {
		assert.deepEqual(lines(d, "plan"), [
			"plan 2026-11-16T10:10 class q=0 10:20 微積分（一）・新生教學館 202（10 分鐘後）",
			"plan 2026-11-16T10:20 class-now q=110 微積分（一）",
			"plan 2026-11-16T12:50 class q=0 13:00 Lecture 7: Optics（10 分鐘後）",
			"plan 2026-11-16T13:00 class-now q=120 Lecture 7: Optics",
			"plan 2026-11-16T13:50 event q=0 14:00 Office hours（MATH4006）・天數館 3F 助教室（10 分鐘後）",
			"plan 2026-11-16T14:00 event-now q=0 Office hours（MATH4006）（點我打開）",
			"plan 2026-11-16T18:50 event q=0 19:00 社團幹部開會（10 分鐘後）",
			"plan 2026-11-16T19:00 event-now q=0 社團幹部開會",
			"plan 2026-11-17T08:00 exam-soon q=0 08:10 英文小考・共同 104（10 分鐘後），文具帶好，加油！",
			"plan 2026-11-17T08:10 exam-now q=30 英文小考，加油！🍀",
		]);
		assert.equal(field(d, "school"), "1");
	});
	await check("狀態列文字：7 天內的考試（明天）", () => assert.match(d, /\nbar 📚 英文小考 明天\n/));

	// 上課：課前提醒 → 開始 → 自動安靜 110 分
	send("study-clock 2026-11-16T10:09:56");
	await sleep(7000);
	await snap("01-class-pre");
	d = await dump();
	await check("上課提醒：課前 10 分鐘講了", () => assert.match(d, /plan 2026-11-16T10:10 class q=0 fired /));
	send("study-clock 2026-11-16T10:19:56");
	await sleep(7000);
	await snap("02-class-now");
	await sleep(9000);   // 上課了那則講完 10 秒後才自動安靜
	d = await dump();
	await check("上課提醒：開始時講了，上課中自動安靜（110 分）", () => {
		assert.match(d, /plan 2026-11-16T10:20 class-now q=110 fired /);
		assert.ok(+field(d, "quiet") >= 100, "quiet=" + field(d, "quiet"));
	});
	send("act quiet 0");

	// 考試：前一天 20:00（加上另一場的倒數）
	send("study-clock 2026-11-16T20:00:30");
	await sleep(4500);
	await snap("03-exam-daybefore");
	d = await dump();
	await check("考試倒數：前一天晚上（明天英文小考）＋期中考還有 9 天，一則講完", () => {
		assert.match(d, /exam ics 2026-11-17T08:10 daily=20261116 before=1 morning=0 英文小考/);
		assert.match(d, /exam ics 2026-11-25T09:00 daily=20261116 before=0 morning=0 期中考/);
	});
	// 死線：前一天（24 小時內）
	send("study-clock 2026-11-16T23:01");
	await sleep(4500);
	await snap("04-deadline-1d");
	d = await dump();
	await check("作業死線：24 小時內講一次（stage 1 → 2）", () => assert.match(d, /deadline 2026-11-17T23:00 stage=2 期中心得討論/));

	// 熬夜：01:05 第一次、02:10 第二次、離開 15 分鐘後就不吵
	send("study-clock 2026-11-17T01:05");
	await sleep(4500);
	await snap("05-latenight-1");
	d = await dump();
	await check("熬夜提醒：01:00 後第一次", () => { assert.equal(field(d, "lateLevel"), "0"); assert.equal(field(d, "lateKey"), "20261116"); });
	send("study-clock 2026-11-17T02:10");
	await sleep(4500);
	d = await dump();
	await check("熬夜提醒：02:00 後再講一次", () => assert.equal(field(d, "lateLevel"), "1"));
	send("study-idle 1000");
	await sleep(4500);
	send("study-clock 2026-11-17T03:10");
	await sleep(4500);
	d = await dump();
	await check("熬夜提醒：離開電腦就當你睡了，03:00 不再吵", () => { assert.equal(field(d, "asleep"), "1"); assert.equal(field(d, "lateLevel"), "1"); });
	send("study-idle 0");

	// 考試當天早上
	send("study-clock 2026-11-17T07:12");
	await sleep(4500);
	d = await dump();
	await check("考試當天早上（08:10 的考試，07:10 提醒）", () => assert.match(d, /exam ics 2026-11-17T08:10 daily=20261117 before=1 morning=1 英文小考/));

	// 死線：同一刻兩份到（2 小時前、3 小時前）→ 合成一則
	send("study-clock 2026-11-17T20:59:30");
	await sleep(4500);
	await snap("06-deadline-combined");
	d = await dump();
	await check("作業死線：兩份同時到（3 小時、1 天）合成一則", () => {
		assert.match(d, /deadline 2026-11-17T23:00 stage=3 期中心得討論/);
		assert.match(d, /deadline 2026-11-17T23:59 stage=3 Lab report 2/);
	});
	await check("狀態列：24 小時內的作業", () => assert.match(d, /\nbar 📝 期中心得討論 R… 剩 2 小時\n/));

	// 交了：不再提醒、重掃也不會回來
	send("study-done " + "event-sub-assignment-88001@" + Date.parse("2026-11-17T15:00:00Z"));
	send(`study-ics ${fx("canvas-ntucool.ics")} ${CANVAS}`);
	await sleep(800);
	d = await dump();
	await check("交了的作業：重掃也不會回來", () => assert.ok(!/期中心得討論/.test(d)));

	// 安靜中不吵：新的一晚，安靜時就算到了也不講
	send("act quiet 30");
	send("study-clock 2026-11-18T01:30");
	await sleep(4500);
	d = await dump();
	await check("熬夜提醒：安靜時不講", () => { assert.equal(field(d, "lateKey"), "20261117"); assert.equal(field(d, "lateLevel"), "-1"); });
	send("act quiet 0");

	// 自己加考試、搶課
	send("study-clock off");
	const exAt = Date.now() + 5 * 864e5;
	send(`exam ${exAt} 微積分期末考`);
	const courseAt = Date.now() + 9 * 60e3 + 30e3;
	send(`course ${courseAt} 60 https://course.example.edu.tw/ 通識熱門課（羽球）`);
	send(`ticket ${Date.now() + 3 * 3600e3} 120 https://tickets.example.com/ 五月天演唱會`);
	await sleep(5000);
	await snap("07-course-badge");
	d = await dump();
	await check("自己加的考試、搶課（Kind＝course）、搶票照舊", () => {
		assert.match(d, /\nexam me \S+ daily=\S* before=0 morning=0 微積分期末考\n/);
		assert.match(d, /\nticket course \S+ stage=3 通識熱門課（羽球）\n/);
		assert.match(d, /\nticket ticket \S+ stage=0 五月天演唱會\n/);
	});

	// 選單：公仔的右鍵 → 小幫手展開
	send("act menu spidey");
	await sleep(400);
	send("act menuhover 0");
	await snap("08-pet-menu");
	send("act menuclose");

	// 設定視窗（桌面版自己的）：填網址、存
	send("study-ics clear");
	send("study-settings open");
	await sleep(500);
	send("study-settings set urls webcal://cool.ntu.edu.tw/feeds/calendars/user_X.ics https://moodle.example.edu.tw/calendar/export_execute.php?userid=1&authtoken=a");
	send("study-settings set late 00:30");
	send("study-settings set remind 15");
	await sleep(400);
	await snap("09-settings");
	send("study-settings save");
	await sleep(500);
	d = await dump();
	await check("設定視窗：存網址（webcal→https）、上課前 15 分、熬夜 00:30", () => {
		assert.equal(field(d, "urls"), "2"); assert.equal(field(d, "remind"), "15"); assert.equal(field(d, "late"), "00:30");
	});
	// VS Code 推設定：以 VS Code 為準，設定視窗鎖住
	send("study-vs urls,late");
	send("study-set urls https://x.example.edu.tw/a.ics");
	send("study-set late off");
	send("study-set workcal -");
	await sleep(400);
	send("study-settings open");
	await sleep(400);
	await snap("10-settings-vscode");
	send("study-settings close");
	d = await dump();
	await check("VS Code 推設定：網址、熬夜以 VS Code 為準", () => { assert.equal(field(d, "urls"), "1"); assert.equal(field(d, "late"), "off"); assert.equal(field(d, "vs"), "urls,late"); });
	send("study-vs -");
	await sleep(300);
	d = await dump();
	await check("VS Code 拿掉設定：交還給桌面版", () => assert.equal(field(d, "vs"), ""));

	// 今天的小結
	send("act wrap");
	await sleep(1500);
	await snap("11-wrap");

	console.log(results.map((r) => r[0] + "  " + r[1]).join("\n"));
	const fail = results.filter((r) => r[0] === "FAIL").length;
	console.log(`\n${results.length - fail}/${results.length} passed`);
	s.end();
	process.exit(fail ? 1 : 0);
});
