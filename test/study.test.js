// practical.js 讀書小幫手（VS Code 這邊只剩推設定和指令）＋開會提醒的迴歸測試。不連網路、時間用假的。
// 學校行事曆的抓取／分類／提醒在桌面版（DeskPals.Study.cs），由 test/desktop-study.js 用離屏模式測。
// 跑法：node --test test/study.test.js
process.env.TZ = "Asia/Taipei";
const test = require("node:test");
const assert = require("node:assert/strict");
const P = require("../extension/practical.js");

const NOW = Date.UTC(2026, 10, 16, 1, 0);   // 2026-11-16（一）09:00 台北

test("schoolUrls：一個、陣列、空白／逗號分隔、webcal、重複、不合法", () => {
	assert.deepEqual(P.schoolUrls(""), []);
	assert.deepEqual(P.schoolUrls(undefined), []);
	assert.deepEqual(P.schoolUrls("https://a.tw/x.ics"), ["https://a.tw/x.ics"]);
	assert.deepEqual(P.schoolUrls(["https://a.tw/x.ics", " webcal://b.tw/y.ics ", "http://c.tw/z.ics", "https://a.tw/x.ics", ""]), ["https://a.tw/x.ics", "https://b.tw/y.ics"]);
	assert.deepEqual(P.schoolUrls("https://a.tw/1.ics, https://a.tw/2.ics\nwebcals://a.tw/3.ics"), ["https://a.tw/1.ics", "https://a.tw/2.ics", "https://a.tw/3.ics"]);
});

test("hhmmOk：時間格式、空白＝關掉、亂打用預設", () => {
	assert.equal(P.hhmmOk("01:00", "01:00"), "01:00");
	assert.equal(P.hhmmOk("0:30", "01:00"), "0:30");
	assert.equal(P.hhmmOk("23：30", "01:00"), "23:30");
	assert.equal(P.hhmmOk("", "01:00"), "off");
	assert.equal(P.hhmmOk(undefined, "20:00"), "20:00");
	assert.equal(P.hhmmOk("晚上", "20:00"), "20:00");
});

test("studySetLines：只推使用者在 VS Code 設過的；開會用的行事曆一定告訴桌面版", () => {
	const vals = { schoolIcsUrl: ["webcal://cool.ntu.edu.tw/feeds/calendars/user_abc.ics", "https://x.tw/b.ics"], lateNightStart: "", calendarIcsUrl: "https://calendar.google.com/calendar/ical/me%40x.com/private-1/basic.ics" };
	const get = (k, d) => (k in vals ? vals[k] : d);
	const lines = P.studySetLines(get, (k) => k === "schoolIcsUrl" || k === "lateNightStart");
	assert.deepEqual(lines, [
		"study-vs urls,late",
		"study-set urls https://cool.ntu.edu.tw/feeds/calendars/user_abc.ics https://x.tw/b.ics",
		"study-set late off",
		"study-set workcal https://calendar.google.com/calendar/ical/me%40x.com/private-1/basic.ics",
	]);
	// 什麼都沒設：交給桌面版自己的設定
	assert.deepEqual(P.studySetLines((k, d) => d, () => false), ["study-vs -", "study-set workcal -"]);
	// 設成空的＝清掉
	assert.deepEqual(P.studySetLines((k, d) => (k === "schoolIcsUrl" ? [] : d), (k) => k === "schoolIcsUrl").slice(0, 2), ["study-vs urls", "study-set urls"]);
});

// ---- 迴歸：開會提醒用的解析不變 ----
test("迴歸：開會行事曆的 RRULE／EXDATE／RECURRENCE-ID／取消／不參加", () => {
	const ics = [
		"BEGIN:VCALENDAR",
		"BEGIN:VEVENT", "UID:standup", "SUMMARY:Standup", "DTSTART;TZID=Asia/Taipei:20261102T093000", "DTEND;TZID=Asia/Taipei:20261102T094500",
		"RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR", "EXDATE;TZID=Asia/Taipei:20261117T093000", "DESCRIPTION:https://meet.google.com/aaa-bbbb-ccc", "END:VEVENT",
		"BEGIN:VEVENT", "UID:standup", "RECURRENCE-ID;TZID=Asia/Taipei:20261118T093000", "SUMMARY:Standup（改到十點）", "DTSTART;TZID=Asia/Taipei:20261118T100000", "DTEND;TZID=Asia/Taipei:20261118T101500", "END:VEVENT",
		"BEGIN:VEVENT", "UID:standup", "RECURRENCE-ID;TZID=Asia/Taipei:20261119T093000", "STATUS:CANCELLED", "DTSTART;TZID=Asia/Taipei:20261119T093000", "END:VEVENT",
		"BEGIN:VEVENT", "UID:skip", "SUMMARY:不想去的會", "DTSTART:20261116T060000Z", "DTEND:20261116T070000Z", "ATTENDEE;PARTSTAT=DECLINED:mailto:me@x.com", "END:VEVENT",
		"END:VCALENDAR",
	].join("\r\n");
	const occ = P.occurrences(P.parseIcs(ics, "me@x.com"), NOW, NOW + 5 * 864e5);
	assert.deepEqual(occ.map((o) => [o.summary, new Date(o.start).toISOString()]), [
		["Standup", "2026-11-16T01:30:00.000Z"],
		["Standup（改到十點）", "2026-11-18T02:00:00.000Z"],
		["Standup", "2026-11-20T01:30:00.000Z"],
	]);
	assert.equal(occ[0].link, "https://meet.google.com/aaa-bbbb-ccc");
	assert.equal(occ[0].end - occ[0].start, 15 * 60e3);
});

test("迴歸：搶票／搶課共用的日期解析", () => {
	const now = new Date(2026, 10, 16, 9, 0);
	assert.equal(P.parseTicketTime("2026-12-20", "20:00", now), new Date(2026, 11, 20, 20, 0).getTime());
	assert.equal(P.parseTicketTime("12/20", "2000", now), new Date(2026, 11, 20, 20, 0).getTime());
	assert.equal(P.parseTicketTime("1/8", "09:00", now), new Date(2027, 0, 8, 9, 0).getTime());   // 沒寫年份又過了 → 明年
	assert.equal(P.parseTicketTime("2026-11-01", "09:00", now), null);
});
