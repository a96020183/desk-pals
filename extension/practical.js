// 公仔櫃的實用功能（VS Code 這邊收集資料，透過 desktop.send("notify ...") 交給桌面公仔）：
//   終端機長指令跑完、推 tag 後盯 CI、開會前提醒（行事曆 ICS）、Jira 新單指派給你、工作日誌產生好了
let vscode = null;
try { vscode = require("vscode"); } catch (e) { /* 單元測試時沒有 vscode */ }
const fs = require("fs");
const path = require("path");
const https = require("https");
const cp = require("child_process");

const cfg = () => vscode.workspace.getConfiguration("deskPals");
const clean = (s) => String(s || "").replace(/[\r\n]+/g, " ").trim();

function setup(context, desktop) {
	const notify = (kind, url, text) => desktop.send(`notify ${kind} ${url || "-"} ${clean(text)}`);
	const subs = context.subscriptions;
	terminal(context, desktop, notify);
	const cal = calendar(notify, desktop);
	const jira = jiraWatch(context, notify);
	const wl = worklog(context, notify);
	const rain = weather(context, notify);
	const gl = gitlabTodos(context, notify);
	subs.push({ dispose: () => { cal.stop(); jira.stop(); wl.stop(); rain.stop(); gl.stop(); } });
	subs.push(vscode.workspace.onDidChangeConfiguration((e) => {
		if (e.affectsConfiguration("deskPals.calendarIcsUrl") || e.affectsConfiguration("deskPals.meetingRemindMinutes")) cal.restart();
		if (e.affectsConfiguration("deskPals.jira")) jira.restart();
		if (e.affectsConfiguration("deskPals.worklogDir")) wl.restart();
		if (e.affectsConfiguration("deskPals.weatherLocation")) rain.restart();
		if (e.affectsConfiguration("deskPals.gitlabHosts")) gl.restart();
	}));
	subs.push(vscode.commands.registerCommand("deskPals.jiraSetup", () => jiraSetup(context, jira)));
	subs.push(vscode.commands.registerCommand("deskPals.remind", () => remindMe(desktop)));
	subs.push(vscode.commands.registerCommand("deskPals.ticket", () => ticketMe(desktop)));
	studySetup(context, desktop);
}

// ---------------- 終端機：長指令跑完、推 tag 盯 CI ----------------
const INTERACTIVE = /^\s*(codex|claude|ssh|vim?|nvim|nano|less|more|top|htop|python3?|node|pwsh|powershell|bash|cmd)\s*$|\b(dev|serve|watch|start|preview|tail\s+-f|docker\s+compose\s+up)\b/i;

function terminal(context, desktop, notify) {
	if (!vscode.window.onDidEndTerminalShellExecution || !vscode.window.onDidStartTerminalShellExecution) return;
	const started = new Map();
	context.subscriptions.push(
		vscode.window.onDidStartTerminalShellExecution((e) => started.set(e.execution, Date.now())),
		vscode.window.onDidEndTerminalShellExecution((e) => {
			const t0 = started.get(e.execution);
			started.delete(e.execution);
			const cmd = (e.execution && e.execution.commandLine && e.execution.commandLine.value) || "";
			const cwd = e.execution && e.execution.cwd ? e.execution.cwd.fsPath : (e.terminal.shellIntegration && e.terminal.shellIntegration.cwd ? e.terminal.shellIntegration.cwd.fsPath : "");

			// 推 tag 成功 → 煙火（原本就有）＋盯 CI
			if (e.exitCode === 0 && /\bgit\b[^\n|;&]*\bpush\b/.test(cmd)) {
				const m = /(\d+\.\d+\.\d+(?:-[A-Za-z]+\.\d+)?)/.exec(cmd);
				if (/--tags|--follow-tags|refs\/tags\//.test(cmd) || m) {
					const env = /Production/i.test(cmd) ? "prod" : /Development/i.test(cmd) ? "dev" : "other";
					desktop.send(`tag ${m ? m[1] : "tag"} ${env}`);
					if (m && cwd) watchCi(desktop, cwd, m[1], env);
				}
				return;
			}

			// 長指令跑完（30 秒以上；你正盯著 VS Code 而且不到 2 分鐘就不吵你）
			if (!t0 || !cmd || INTERACTIVE.test(cmd)) return;
			const secs = Math.round((Date.now() - t0) / 1000);
			if (secs < 30) return;
			if (vscode.window.state.focused && secs < 120) return;
			const dur = secs >= 60 ? `${Math.floor(secs / 60)} 分 ${secs % 60} 秒` : `${secs} 秒`;
			const short = cmd.length > 40 ? cmd.slice(0, 40) + "…" : cmd;
			if (e.exitCode === 0 || e.exitCode === undefined) notify("cmd-ok", "-", `指令跑完了（${dur}）：${short}`);
			else notify("cmd-fail", "-", `指令失敗了（exit ${e.exitCode}，${dur}）：${short}`);
		})
	);
}

function watchCi(desktop, cwd, tag, env) {
	try {
		const script = path.join(desktop.home, "ci-watch.js");
		if (!fs.existsSync(script)) return;
		// VS Code 本身（Electron）設 ELECTRON_RUN_AS_NODE 就能當 node 跑，不用另外裝 node
		cp.spawn(process.execPath, [script, cwd, tag, env], {
			detached: true, stdio: "ignore", windowsHide: true,
			env: Object.assign({}, process.env, { ELECTRON_RUN_AS_NODE: "1" }),
		}).unref();
	} catch (e) { console.error("deskpals ci", e); }
}

// ---------------- 行事曆：開會前提醒（Google／Outlook 的 ICS 私人網址）----------------
function calendar(notify, desktop) {
	let poll, timers = [], fired = new Set();
	const stop = () => { clearInterval(poll); timers.forEach(clearTimeout); timers = []; };
	const load = async () => {
		const url = String(cfg().get("calendarIcsUrl", "") || "").trim();
		if (!/^https:\/\//i.test(url)) return;
		let text;
		try { text = await get(url); } catch (e) { console.error("deskpals ics", e.message); return; }
		timers.forEach(clearTimeout); timers = [];
		const before = Math.max(1, Number(cfg().get("meetingRemindMinutes", 5)) || 5);
		const now = Date.now(), until = now + 26 * 3600e3;
		// 行事曆擁有者（私人網址裡就有信箱）：他按了「不參加」的會不提醒
		const owner = decodeURIComponent((/\/ical\/([^/]+)\//.exec(url) || [])[1] || "");
		// 同一時間好幾場 → 合成一則
		const groups = new Map();
		for (const o of occurrences(parseIcs(text, owner), now - 60e3, until)) {
			const g = groups.get(o.start);
			if (!g) groups.set(o.start, Object.assign({}, o, { uid: o.uid, names: [o.summary] }));
			else { g.names.push(o.summary); g.uid += "+" + o.uid; if (!g.link) g.link = o.link; g.end = Math.max(g.end, o.end); }
		}
		for (const ev of groups.values()) {
			ev.summary = ev.names.length > 1 ? ev.names.slice(0, 2).join("、") + (ev.names.length > 2 ? ` 等 ${ev.names.length} 場` : "") : ev.names[0];
			const hhmm = new Date(ev.start).toLocaleTimeString("zh-TW", { hour: "2-digit", minute: "2-digit", hour12: false });
			const key = ev.uid + "@" + ev.start;
			const at1 = ev.start - before * 60e3;
			if (at1 > now && at1 - now < 26 * 3600e3 && !fired.has(key + "-pre"))
				timers.push(setTimeout(() => { fired.add(key + "-pre"); notify("meeting", ev.link, `${hhmm} 有會：${ev.summary}（${before} 分鐘後）`); }, at1 - now));
			if (ev.start > now && !fired.has(key + "-now"))
				timers.push(setTimeout(() => {
					fired.add(key + "-now");
					notify("meeting-now", ev.link, `${ev.summary} 開始了！${ev.link ? "點我進會議" : ""}`);
					// 開會中自動安靜到會議結束
					if (cfg().get("meetingAutoQuiet", true)) {
						const mins = Math.round((ev.end - Date.now()) / 60e3);
						if (mins > 0) setTimeout(() => desktop.send(`act quiet ${Math.min(mins, 240)}`), 1500);
					}
				}, ev.start - now));
		}
	};
	const start = () => { stop(); load(); poll = setInterval(load, 10 * 60e3); };
	start();
	return { stop, restart: start };
}

function get(url, headers = {}, redirects = 3) {
	return new Promise((resolve, reject) => {
		const req = https.get(url, { headers: Object.assign({ "User-Agent": "desk-pals" }, headers), timeout: 20000 }, (res) => {
			if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && redirects > 0) {
				res.resume();
				return resolve(get(new URL(res.headers.location, url).toString(), headers, redirects - 1));
			}
			if (res.statusCode !== 200) { res.resume(); return reject(new Error("HTTP " + res.statusCode)); }
			let body = "";
			res.setEncoding("utf8");
			res.on("data", (d) => (body += d));
			res.on("end", () => resolve(body));
		});
		req.on("error", reject);
		req.on("timeout", () => req.destroy(new Error("timeout")));
	});
}

// ---- ICS 解析（夠用就好：單次、DAILY／WEEKLY／MONTHLY／YEARLY、EXDATE、單次改期、取消）----
function parseIcs(text, owner) {
	owner = String(owner || "").toLowerCase();
	const lines = text.replace(/\r\n[ \t]/g, "").replace(/\n[ \t]/g, "").split(/\r?\n/);
	const events = [];
	let cur = null;
	for (const line of lines) {
		if (line === "BEGIN:VEVENT") { cur = { exdates: [] }; continue; }
		if (line === "END:VEVENT") { if (cur) events.push(cur); cur = null; continue; }
		if (!cur) continue;
		const i = line.indexOf(":");
		if (i < 0) continue;
		const left = line.slice(0, i), value = line.slice(i + 1);
		const [name, ...params] = left.split(";");
		const p = {};
		for (const kv of params) { const j = kv.indexOf("="); if (j > 0) p[kv.slice(0, j).toUpperCase()] = kv.slice(j + 1).replace(/^"|"$/g, ""); }
		const unesc = (s) => s.replace(/\\n/gi, "\n").replace(/\\([,;\\])/g, "$1");
		switch (name.toUpperCase()) {
			case "UID": cur.uid = value; break;
			case "SUMMARY": cur.summary = unesc(value); break;
			case "LOCATION": cur.location = unesc(value); break;
			case "DESCRIPTION": cur.description = unesc(value); break;
			case "URL": cur.url = value; break;
			case "X-GOOGLE-CONFERENCE": cur.conf = value; break;
			case "STATUS": cur.status = value.toUpperCase(); break;
			case "RRULE": cur.rrule = value; break;
			case "DTSTART": cur.start = parseTime(value, p); break;
			case "DTEND": cur.end = parseTime(value, p); break;
			case "RECURRENCE-ID": cur.recurrenceId = parseTime(value, p); break;
			case "ATTENDEE":
				if (owner && value.toLowerCase() === "mailto:" + owner && (p.PARTSTAT || "").toUpperCase() === "DECLINED") cur.declined = true;
				break;
			case "EXDATE": for (const v of value.split(",")) { const t = parseTime(v, p); if (t) cur.exdates.push(t.utc); } break;
		}
	}
	return events;
}

// 回傳 { utc, wall:{y,m,d,h,mi,s}, tz, allDay }
function parseTime(v, p) {
	const m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/.exec(v.trim());
	if (!m) return null;
	const wall = { y: +m[1], m: +m[2], d: +m[3], h: +(m[4] || 0), mi: +(m[5] || 0), s: +(m[6] || 0) };
	const allDay = !m[4] || p.VALUE === "DATE";
	const tz = m[7] ? "UTC" : p.TZID || null;
	return { utc: wallToUtc(wall, tz), wall, tz, allDay };
}

// 某時區的牆上時間 → UTC 毫秒（沒時區＝本機時間）
function wallToUtc(w, tz) {
	if (!tz) return new Date(w.y, w.m - 1, w.d, w.h, w.mi, w.s).getTime();
	const guess = Date.UTC(w.y, w.m - 1, w.d, w.h, w.mi, w.s);
	if (tz === "UTC") return guess;
	try {
		const off = (t) => {
			const f = new Intl.DateTimeFormat("en-US", { timeZone: tz, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" });
			const o = {};
			for (const part of f.formatToParts(new Date(t))) o[part.type] = +part.value;
			return Date.UTC(o.year, o.month - 1, o.day, o.hour, o.minute, o.second) - t;
		};
		let t = guess - off(guess);
		t = guess - off(t);
		return t;
	} catch (e) {
		return new Date(w.y, w.m - 1, w.d, w.h, w.mi, w.s).getTime();
	}
}

const DAYS = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];

function occurrences(events, from, to) {
	const out = [];
	const overrides = new Map(); // uid@原本時間 → 改期後的事件（或取消）
	for (const e of events) if (e.recurrenceId && e.uid) overrides.set(e.uid + "@" + e.recurrenceId.utc, e);
	const push = (e, startUtc, parent) => {
		if (e.status === "CANCELLED" || e.declined) return;
		if (startUtc < from || startUtc > to) return;
		const src = e.end && e.start ? e : parent && parent.end && parent.start ? parent : null;
		const len = src ? Math.max(5 * 60e3, src.end.utc - src.start.utc) : 30 * 60e3;
		out.push({ uid: e.uid || e.summary, start: startUtc, end: startUtc + len, summary: e.summary || (parent && parent.summary) || "（沒有標題）", link: meetLink(e) || (parent ? meetLink(parent) : "") });
	};
	for (const e of events) {
		if (!e.start || e.start.allDay || e.recurrenceId) continue;
		if (!e.rrule) { push(e, e.start.utc); continue; }
		const r = {};
		for (const kv of e.rrule.split(";")) { const [k, v] = kv.split("="); r[k] = v; }
		const freq = r.FREQ, interval = Math.max(1, +(r.INTERVAL || 1)), count = r.COUNT ? +r.COUNT : Infinity;
		const until = r.UNTIL ? (parseTime(r.UNTIL, {}) || {}).utc : Infinity;
		const byday = r.BYDAY ? r.BYDAY.split(",") : null;
		const bymd = r.BYMONTHDAY ? r.BYMONTHDAY.split(",").map(Number) : null;
		const w = e.start.wall;
		const day0 = Date.UTC(w.y, w.m - 1, w.d);
		const endDay = Date.UTC(new Date(to).getUTCFullYear(), new Date(to).getUTCMonth(), new Date(to).getUTCDate()) + 2 * 864e5;
		const mon0 = Date.UTC(w.y, w.m - 1, w.d) - ((new Date(day0).getUTCDay() + 6) % 7) * 864e5; // 起始那週的週一
		let n = 0;
		for (let t = day0; t <= endDay && n < count; t += 864e5) {
			const d = new Date(t);
			const Y = d.getUTCFullYear(), M = d.getUTCMonth() + 1, D = d.getUTCDate(), wd = d.getUTCDay();
			let ok = false;
			if (freq === "DAILY") ok = Math.round((t - day0) / 864e5) % interval === 0 && (!byday || byday.some((b) => b.slice(-2) === DAYS[wd]));
			else if (freq === "WEEKLY") {
				const weeks = Math.floor((t - mon0) / (7 * 864e5));
				ok = weeks % interval === 0 && (byday ? byday.some((b) => b.slice(-2) === DAYS[wd]) : wd === new Date(day0).getUTCDay());
			} else if (freq === "MONTHLY") {
				const months = (Y - w.y) * 12 + (M - w.m);
				if (months % interval === 0) {
					if (byday) ok = byday.some((b) => {
						const mm = /^([+-]?\d+)?(\w\w)$/.exec(b);
						if (!mm || mm[2] !== DAYS[wd]) return false;
						if (!mm[1]) return true;
						const nth = +mm[1];
						if (nth > 0) return Math.ceil(D / 7) === nth;
						const dim = new Date(Date.UTC(Y, M, 0)).getUTCDate();
						return Math.ceil((dim - D + 1) / 7) === -nth;
					});
					else ok = (bymd || [w.d]).includes(D);
				}
			} else if (freq === "YEARLY") ok = (Y - w.y) % interval === 0 && M === w.m && D === w.d;
			if (!ok) continue;
			const startUtc = wallToUtc({ y: Y, m: M, d: D, h: w.h, mi: w.mi, s: w.s }, e.start.tz);
			if (startUtc > until) break;
			n++;
			if (e.exdates.includes(startUtc)) continue;
			const ov = overrides.get((e.uid || "") + "@" + startUtc);
			if (ov) { if (ov.start) push(ov, ov.start.utc, e); continue; }
			push(e, startUtc);
		}
	}
	return out.sort((a, b) => a.start - b.start);
}

function meetLink(e) {
	if (e.conf && /^https:\/\//.test(e.conf)) return e.conf;
	const text = [e.location, e.description, e.url].filter(Boolean).join(" ");
	const m = /https:\/\/(?:meet\.google\.com|[\w.-]*zoom\.us|teams\.microsoft\.com|teams\.live\.com)\/[^\s"<>)]+/i.exec(text);
	return m ? m[0] : e.url && /^https:\/\//.test(e.url) ? e.url : "";
}

// ---------------- Jira：新單指派給你 ----------------
async function jiraCreds(context) {
	const file = String(cfg().get("jira.credentialsFile", "") || "").trim();
	if (file) {
		try {
			const j = JSON.parse(fs.readFileSync(file.replace(/^~(?=[\\/])/, require("os").homedir()), "utf8"));
			if (j.site && j.email && j.api_token) return { site: j.site, email: j.email, token: j.api_token };
		} catch (e) { console.error("deskpals jira creds file", e.message); }
	}
	const site = String(cfg().get("jira.site", "") || "").trim(), email = String(cfg().get("jira.email", "") || "").trim();
	const token = await context.secrets.get("deskPals.jiraToken");
	return site && email && token ? { site, email, token } : null;
}

function jiraWatch(context, notify) {
	let timer;
	const stop = () => clearInterval(timer);
	let me = null; // 自己的 accountId（判斷 @ 提及用）

	const api = async (c, p) => JSON.parse(await get(`https://${c.host}${p}`, {
		Authorization: "Basic " + Buffer.from(`${c.email}:${c.token}`).toString("base64"),
		Accept: "application/json",
	}));
	const search = (c, jql, fields, max = 100) =>
		api(c, `/rest/api/3/search/jql?jql=${encodeURIComponent(jql)}&fields=${fields}&maxResults=${max}`).then((d) => d.issues || []);
	const adfText = (n) => !n ? "" : n.type === "text" ? n.text || "" : n.type === "mention" ? (n.attrs && n.attrs.text) || "@" : (n.content || []).map(adfText).join(n.type === "paragraph" ? " " : "");

	// 1) 新單指派給你
	const assigned = async (c) => {
		const jql = "assignee = currentUser() AND statusCategory != Done ORDER BY created DESC";
		const issues = await search(c, jql, "summary");
		const key = "jiraSeen:" + c.host;
		const seen = context.globalState.get(key);
		const now = issues.map((i) => i.key);
		if (!seen) { context.globalState.update(key, now); return; } // 第一次只記下來，不通知
		const fresh = issues.filter((i) => !seen.includes(i.key));
		for (const i of fresh.slice(0, 3)) {
			const sum = clean(i.fields && i.fields.summary).slice(0, 40);
			notify("jira", `https://${c.host}/browse/${i.key}`, `${i.key} 指派給你了：${sum}`);
		}
		if (fresh.length > 3) notify("jira", `https://${c.host}/issues/?jql=${encodeURIComponent(jql)}`, `還有 ${fresh.length - 3} 張新單指派給你`);
		context.globalState.update(key, Array.from(new Set(seen.concat(now))).slice(-500));
	};

	// 2) 到期提醒：平日 09:30、16:30 各看一次（今天到期／明天到期／已逾期）
	const due = async (c) => {
		const d = new Date(), wd = d.getDay(), hm = d.getHours() * 60 + d.getMinutes();
		if (wd === 0 || wd === 6) return;
		const slot = hm >= 16 * 60 + 30 ? "pm" : hm >= 9 * 60 + 30 ? "am" : null;
		if (!slot) return;
		const k = `jiraDue:${c.host}:${d.toDateString()}:${slot}`;
		if (context.globalState.get(k)) return;
		context.globalState.update(k, true);
		const jql = "assignee = currentUser() AND statusCategory != Done AND duedate >= -14d AND duedate <= endOfDay(1) ORDER BY duedate ASC";
		const issues = await search(c, jql, "summary,duedate", 50);
		if (!issues.length) return;
		const today = new Date(); today.setHours(0, 0, 0, 0);
		const bucket = { over: [], today: [], tmr: [] };
		for (const i of issues) {
			const dd = i.fields && i.fields.duedate ? new Date(i.fields.duedate + "T00:00:00") : null;
			if (!dd) continue;
			const diff = Math.round((dd - today) / 864e5);
			(diff < 0 ? bucket.over : diff === 0 ? bucket.today : bucket.tmr).push(i.key);
		}
		const parts = [];
		if (bucket.today.length) parts.push(`今天到期：${bucket.today.slice(0, 3).join("、")}${bucket.today.length > 3 ? ` 等 ${bucket.today.length} 張` : ""}`);
		if (bucket.tmr.length) parts.push(`明天到期：${bucket.tmr.slice(0, 3).join("、")}${bucket.tmr.length > 3 ? ` 等 ${bucket.tmr.length} 張` : ""}`);
		if (bucket.over.length) parts.push(`已經逾期 ${bucket.over.length} 張`);
		if (!parts.length) return;
		const one = issues.length === 1 ? `https://${c.host}/browse/${issues[0].key}` : `https://${c.host}/issues/?jql=${encodeURIComponent(jql)}`;
		notify("jira", one, parts.join("；"));
	};

	// 3) 有人在留言 @你（看你有參與的單：負責、回報、關注）
	const mentions = async (c) => {
		if (!me) me = (await api(c, "/rest/api/3/myself")).accountId;
		if (!me) return;
		const k = "jiraMention:" + c.host;
		const since = context.globalState.get(k);
		const now = Date.now();
		if (!since) { context.globalState.update(k, now); return; }
		const issues = await search(c, "updated >= -20m AND (watcher = currentUser() OR assignee = currentUser() OR reporter = currentUser()) ORDER BY updated DESC", "summary", 20);
		let newest = since;
		for (const i of issues) {
			const cm = await api(c, `/rest/api/3/issue/${i.key}/comment?orderBy=-created&maxResults=5`);
			for (const x of cm.comments || []) {
				const t = Date.parse(x.created);
				if (!(t > since)) continue;
				if (x.author && x.author.accountId === me) continue;
				if (!JSON.stringify(x.body || {}).includes(`"id":"${me}"`)) continue;
				newest = Math.max(newest, t);
				const who = (x.author && x.author.displayName) || "有人";
				const text = clean(adfText(x.body)).slice(0, 40);
				notify("jira", `https://${c.host}/browse/${i.key}?focusedCommentId=${x.id}`, `${who} 在 ${i.key} @你：${text}`);
			}
		}
		context.globalState.update(k, Math.max(newest, now - 60e3));
	};

	const check = async () => {
		const cr = await jiraCreds(context);
		if (!cr) return;
		const c = Object.assign({}, cr, { host: cr.site.replace(/^https?:\/\//, "").replace(/\/.*$/, "") });
		for (const step of [assigned, due, mentions]) {
			try { await step(c); } catch (e) { console.error("deskpals jira", step.name, e.message); }
		}
	};
	const start = () => { stop(); setTimeout(check, 20e3); timer = setInterval(check, 3 * 60e3); };
	start();
	return { stop, restart: start, check };
}

async function jiraSetup(context, jira) {
	const site = await vscode.window.showInputBox({ title: "Jira 網站", placeHolder: "例如 yourteam.atlassian.net", value: cfg().get("jira.site", "") });
	if (!site) return;
	const email = await vscode.window.showInputBox({ title: "Jira 登入信箱", value: cfg().get("jira.email", "") });
	if (!email) return;
	const token = await vscode.window.showInputBox({ title: "Jira API token（https://id.atlassian.com/manage-profile/security/api-tokens 建立）", password: true });
	if (!token) return;
	await cfg().update("jira.site", site.trim(), vscode.ConfigurationTarget.Global);
	await cfg().update("jira.email", email.trim(), vscode.ConfigurationTarget.Global);
	await context.secrets.store("deskPals.jiraToken", token.trim());
	jira.restart();
	vscode.window.showInformationMessage("Jira 設定好了：有新單指派給你時，公仔會來通知你。");
}

// ---------------- 工作日誌：資料夾裡出現今天的新檔 ----------------
function worklog(context, notify) {
	let timer;
	const stop = () => clearInterval(timer);
	const check = () => {
		const dir = String(cfg().get("worklogDir", "") || "").trim();
		if (!dir || !fs.existsSync(dir)) return;
		const key = "worklogSeen:" + dir;
		const last = context.globalState.get(key);
		let newest = null;
		for (const f of fs.readdirSync(dir)) {
			if (!/\.(md|txt|docx?|xlsx?)$/i.test(f)) continue;
			const st = fs.statSync(path.join(dir, f));
			if (!newest || st.mtimeMs > newest.t) newest = { f, t: st.mtimeMs };
		}
		if (!newest) return;
		if (last === undefined) { context.globalState.update(key, newest.t); return; }
		if (newest.t <= last) return;
		context.globalState.update(key, newest.t);
		const today = new Date().toDateString() === new Date(newest.t).toDateString();
		if (today) notify("worklog", "file:///" + path.join(dir, newest.f).replace(/\\/g, "/"), `今天的工作日誌好了：${newest.f}`);
	};
	const start = () => { stop(); check(); timer = setInterval(check, 60e3); };
	start();
	return { stop, restart: start };
}

// ---------------- 下雨提醒（免費、不用申請：wttr.in 降雨機率，連不上改用 met.no 預估雨量）----------------
// 平日 17:30 看：等一下下班（18–21 點）會不會下雨、下一個上班日會不會下雨
const CITY = {
	台北: [25.05, 121.53, "Taipei"], 臺北: [25.05, 121.53, "Taipei"], 新北: [25.01, 121.47, "New Taipei"], 桃園: [24.99, 121.31, "Taoyuan"],
	新竹: [24.80, 120.97, "Hsinchu"], 台中: [24.15, 120.67, "Taichung"], 臺中: [24.15, 120.67, "Taichung"], 台南: [22.99, 120.21, "Tainan"],
	臺南: [22.99, 120.21, "Tainan"], 高雄: [22.63, 120.30, "Kaohsiung"], 基隆: [25.13, 121.74, "Keelung"], 宜蘭: [24.76, 121.75, "Yilan"],
	花蓮: [23.99, 121.60, "Hualien"], 台東: [22.76, 121.14, "Taitung"], 臺東: [22.76, 121.14, "Taitung"], 嘉義: [23.48, 120.45, "Chiayi"],
	彰化: [24.08, 120.54, "Changhua"], 苗栗: [24.56, 120.82, "Miaoli"], 屏東: [22.67, 120.49, "Pingtung"], 南投: [23.91, 120.68, "Nantou"],
	雲林: [23.71, 120.54, "Yunlin"], 香港: [22.32, 114.17, "Hong Kong"], 九龍: [22.32, 114.18, "Kowloon"], 澳門: [22.20, 113.55, "Macau"],
};
const ymd = (x) => `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, "0")}-${String(x.getDate()).padStart(2, "0")}`;
const nextWorkday = (d) => { const n = new Date(d); do n.setDate(n.getDate() + 1); while (n.getDay() === 0 || n.getDay() === 6); return n; };

function weather(context, notify) {
	let timer;
	const stop = () => clearInterval(timer);
	const place = () => {
		const loc = String(cfg().get("weatherLocation", "") || "").trim();
		if (!loc) return null;
		const m = /^(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)$/.exec(loc);
		if (m) return { q: `${m[1]},${m[2]}`, lat: +m[1], lon: +m[2] };
		const c = CITY[loc.replace(/[市縣]$/, "")];
		return c ? { q: c[2], lat: c[0], lon: c[1] } : { q: loc };
	};
	// 回傳 { tonight, next }：各自是降雨機率（%）或 null；或改用雨量（mm）
	const look = async (p, d) => {
		try {
			const j = JSON.parse(await get(`https://wttr.in/${encodeURIComponent(p.q)}?format=j1&lang=zh-tw`));
			return rainFromWttr(j, d);
		} catch (e) {
			if (p.lat === undefined) throw e;
			const j = JSON.parse(await get(`https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=${p.lat.toFixed(2)}&lon=${p.lon.toFixed(2)}`, { "User-Agent": "desk-pals/0.4" }));
			return rainFromMetno(j, d);
		}
	};
	const check = async (force) => {
		const d = new Date(), wd = d.getDay(), hm = d.getHours() * 60 + d.getMinutes();
		if (!force && (wd === 0 || wd === 6 || hm < 17 * 60 + 30 || hm > 19 * 60)) return;
		const k = "rain:" + d.toDateString();
		if (!force && context.globalState.get(k)) return;
		const p = place();
		if (!p) return;
		const r = await look(p, d);
		context.globalState.update(k, true);
		const msg = rainText(r, d);
		if (msg) notify("rain", "-", msg);
		return msg;
	};
	const start = () => {
		stop();
		setTimeout(() => check(false).catch((e) => console.error("deskpals rain", e.message)), 30e3);
		timer = setInterval(() => check(false).catch((e) => console.error("deskpals rain", e.message)), 10 * 60e3);
	};
	start();
	return { stop, restart: start, check };
}

function rainFromWttr(j, d) {
	const days = j.weather || [];
	const pick = (date, from, to) => {
		const day = days.find((x) => x.date === date);
		if (!day) return null;
		let mx = null;
		for (const h of day.hourly || []) {
			const hr = Math.floor(+h.time / 100);
			if (hr >= from && hr <= to) mx = Math.max(mx || 0, +h.chanceofrain || 0);
		}
		return mx;
	};
	return { unit: "%", tonight: pick(ymd(d), 18, 21), next: pick(ymd(nextWorkday(d)), 6, 21) };
}

function rainFromMetno(j, d) {
	const ts = (j.properties && j.properties.timeseries) || [];
	const sum = (from, to) => {
		let mm = 0, any = false;
		for (const t of ts) {
			const at = Date.parse(t.time);
			if (at < from || at >= to) continue;
			const one = t.data && t.data.next_1_hours;
			if (one) { mm += one.details.precipitation_amount || 0; any = true; }
		}
		return any ? Math.round(mm * 10) / 10 : null;
	};
	const day = (x, h) => { const y = new Date(x); y.setHours(h, 0, 0, 0); return y.getTime(); };
	const nx = nextWorkday(d);
	return { unit: "mm", tonight: sum(day(d, 18), day(d, 22)), next: sum(day(nx, 6), day(nx, 22)) };
}

function rainText(r, d) {
	if (!r) return "";
	const label = d.getDay() === 5 ? "下週一" : "明天";
	const hit = (v) => v !== null && v !== undefined && (r.unit === "%" ? v >= 50 : v >= 1);
	const fmt = (v) => (r.unit === "%" ? `降雨機率 ${v}%` : `預估雨量 ${v} mm`);
	const parts = [];
	if (hit(r.tonight)) parts.push(`等一下下班可能會下雨（${fmt(r.tonight)}）`);
	if (hit(r.next)) parts.push(`${label}${r.unit === "%" ? "" : "可能下雨，"}${fmt(r.next)}`);
	return parts.length ? `${parts.join("，")}，記得帶傘 ☔` : "";
}

// ---------------- GitLab：待辦（請你 review、指派 MR、@你、pipeline 失敗…）----------------
// 用 glab 已登入的身分查 /todos，token 交給 glab 自己處理
const TODO_TEXT = {
	review_requested: "請你 review", assigned: "指派給你", mentioned: "@你", directly_addressed: "@你",
	build_failed: "pipeline 失敗", approval_required: "需要你核准", unmergeable: "沒辦法合併了", marked: "加了待辦",
};
function gitlabTodos(context, notify) {
	let timer;
	const stop = () => clearInterval(timer);
	const run = (host) => new Promise((resolve) => {
		cp.execFile("glab", ["api", "--hostname", host, "todos?state=pending&per_page=20"], { windowsHide: true, timeout: 30000 }, (err, out) => {
			if (err) return resolve(null);
			try { resolve(JSON.parse(out)); } catch (e) { resolve(null); }
		});
	});
	const check = async () => {
		const hosts = cfg().get("gitlabHosts", []) || [];
		for (const host of hosts) {
			const list = await run(host);
			if (!list) continue;
			const key = "glTodo:" + host;
			const seen = context.globalState.get(key);
			const ids = list.map((t) => t.id);
			if (!seen) { context.globalState.update(key, ids); continue; } // 第一次只記下來
			const fresh = list.filter((t) => !seen.includes(t.id));
			for (const t of fresh.slice(0, 3)) {
				const who = (t.author && t.author.name) || "有人";
				const what = TODO_TEXT[t.action_name] || t.action_name;
				const title = clean(t.target && t.target.title).slice(0, 36);
				const ref = t.target_type === "MergeRequest" ? "MR" : t.target_type === "Issue" ? "Issue" : "";
				notify(t.action_name === "build_failed" ? "ci-fail" : "gitlab", t.target_url || "-", `${who} ${what}：${ref} ${title}`);
			}
			if (fresh.length > 3) notify("gitlab", `https://${host}/dashboard/todos`, `GitLab 還有 ${fresh.length - 3} 件新待辦`);
			context.globalState.update(key, Array.from(new Set(seen.concat(ids))).slice(-500));
		}
	};
	const start = () => { stop(); setTimeout(check, 25e3); timer = setInterval(check, 3 * 60e3); };
	start();
	return { stop, restart: start, check };
}

// ---------------- 搶票提醒（存在桌面版；開賣前 1–2 小時、30 分、10 分、1 分、開搶各叫一次）----------------
// 日期可以打：2026-12-20、12/20、12-20；時間：20:00、2000
function parseTicketTime(dateText, timeText, now = new Date()) {
	const dm = /^(?:(\d{4})[-/.])?(\d{1,2})[-/.](\d{1,2})$/.exec(String(dateText || "").trim());
	const tm = /^(\d{1,2})[:：]?(\d{2})$/.exec(String(timeText || "").trim());
	if (!dm || !tm) return null;
	const y = dm[1] ? +dm[1] : now.getFullYear();
	const d = new Date(y, +dm[2] - 1, +dm[3], +tm[1], +tm[2], 0, 0);
	if (!dm[1] && d < now) d.setFullYear(y + 1); // 沒寫年份又已經過了 → 明年
	return d.getTime() > now.getTime() ? d.getTime() : null;
}

// 搶票、搶課（選課系統開放）共用同一套：只有用字、圖示和送給桌面版的指令不同
const RUSH = {
	ticket: {
		icon: "🎫", title: "搶票提醒", what: "什麼票？", whatEg: "例如：五月天 演唱會", day: "哪一天開賣？", time: "幾點開賣？", timeEg: "例如 12:00",
		url: "售票網址（可留空）", urlEg: "https://…  開搶時點公仔直接打開", verb: "開賣", go: "開搶",
	},
	course: {
		icon: "🎓", title: "搶課提醒", what: "搶哪門課？", whatEg: "例如：通識熱門課、體育（羽球）", day: "選課系統哪一天開放？", time: "幾點開放？", timeEg: "例如 09:00",
		url: "選課系統網址（可留空）", urlEg: "https://…  開放時點公仔直接打開選課系統", verb: "開放選課", go: "開放",
	},
};

async function ticketMe(desktop, kind = "ticket") {
	const w = RUSH[kind] || RUSH.ticket;
	const name = await vscode.window.showInputBox({ title: `${w.title}（1/4）：${w.what}`, placeHolder: w.whatEg });
	if (!name) return;
	const date = await vscode.window.showInputBox({ title: `${w.title}（2/4）：${w.day}`, placeHolder: "例如 2026-12-20 或 12/20" });
	if (!date) return;
	const time = await vscode.window.showInputBox({ title: `${w.title}（3/4）：${w.time}`, placeHolder: w.timeEg });
	if (!time) return;
	const at = parseTicketTime(date, time);
	if (!at) { vscode.window.showWarningMessage("看不懂這個日期／時間，或已經過了。日期打 2026-12-20 或 12/20，時間打 12:00。"); return; }
	const url = await vscode.window.showInputBox({ title: `${w.title}（4/4）：${w.url}`, placeHolder: w.urlEg, validateInput: (v) => !v || /^https?:\/\//i.test(v) ? null : "要 http:// 或 https:// 開頭" });
	if (url === undefined) return;
	const lead = await vscode.window.showQuickPick([{ label: "提前 2 小時開始提醒", v: 120 }, { label: "提前 1 小時開始提醒", v: 60 }], { title: "什麼時候開始提醒？" });
	if (!lead) return;
	desktop.send(`${kind === "course" ? "course" : "ticket"} ${at} ${lead.v} ${url ? url.trim() : "-"} ${clean(name)}`);
	const when = new Date(at).toLocaleString("zh-TW", { month: "numeric", day: "numeric", weekday: "short", hour: "2-digit", minute: "2-digit", hour12: false });
	vscode.window.showInformationMessage(`${w.icon} 記下來了：${clean(name)}，${when} ${w.verb}。${w.verb}前 ${lead.v / 60} 小時、30 分、10 分、1 分和${w.go}時都會叫你。`);
}

// ---------------- 提醒我…（存在桌面版，VS Code 關了也照樣提醒）----------------
// 時間可以打：10（分鐘）、1.5h、15:30、下班（17:50）
function parseWhen(t, now = new Date()) {
	t = String(t || "").trim().toLowerCase();
	let m;
	if (/^下班/.test(t)) { const d = new Date(now); d.setHours(17, 50, 0, 0); return d > now ? d.getTime() : null; }
	if ((m = /^(\d{1,2})[:：](\d{2})$/.exec(t))) {
		const d = new Date(now); d.setHours(+m[1], +m[2], 0, 0);
		if (d <= now) d.setDate(d.getDate() + 1);
		return d.getTime();
	}
	if ((m = /^(\d+(?:\.\d+)?)\s*(h|小時|hr|hrs)$/.exec(t))) return now.getTime() + +m[1] * 3600e3;
	if ((m = /^(\d+)\s*(m|分|分鐘|min|mins)?$/.exec(t))) return now.getTime() + +m[1] * 60e3;
	return null;
}

async function remindMe(desktop) {
	const what = await vscode.window.showInputBox({ title: "公仔櫃：提醒我…", placeHolder: "要提醒什麼？例如：回覆 Dennis 的訊息" });
	if (!what) return;
	const pick = await vscode.window.showQuickPick(
		[{ label: "10 分鐘後", v: "10" }, { label: "30 分鐘後", v: "30" }, { label: "1 小時後", v: "1h" }, { label: "下班前（17:50）", v: "下班" }, { label: "自己輸入時間…", v: "" }],
		{ title: "什麼時候提醒？" });
	if (!pick) return;
	let when = pick.v;
	if (!when) when = await vscode.window.showInputBox({ title: "什麼時候提醒？", placeHolder: "例如 45（分鐘）、1.5h、15:30" });
	const at = parseWhen(when);
	if (!at) { vscode.window.showWarningMessage("看不懂這個時間，可以打 45、1.5h 或 15:30"); return; }
	desktop.send(`remind ${at} ${clean(what)}`);
	const hhmm = new Date(at).toLocaleTimeString("zh-TW", { hour: "2-digit", minute: "2-digit", hour12: false });
	vscode.window.setStatusBarMessage(`⏰ ${hhmm} 提醒你：${clean(what)}`, 4000);
}

// ================= 讀書小幫手：學校行事曆（上課提醒、作業死線）、考試倒數、搶課 =================
// 全部在桌面版做（DeskPals.Study.cs：自己抓 ICS、分類、提醒；沒有 VS Code 也能用）。
// 這裡只做三件事：把你在 VS Code 設過的設定推給桌面版（以 VS Code 為準）、指令（搶課、考試、這週要交的、加行事曆）、
// 狀態列顯示最近的死線／考試（桌面版送 study-state 過來）。上課提醒不在這裡排，免得跟桌面版重複。

// 設定可以是一個網址、好幾個（陣列，或用空白／逗號／換行隔開）；webcal:// 當成 https://
function schoolUrls(v) {
	const list = Array.isArray(v) ? v : String(v || "").split(/[\s,，]+/);
	const out = [];
	for (let u of list) {
		u = String(u || "").trim().replace(/^webcals?:\/\//i, "https://");
		if (/^https:\/\/\S+$/i.test(u) && !out.includes(u)) out.push(u);
	}
	return out;
}

// "01:00" → "01:00"；空白 → "off"；看不懂 → 預設
const hhmmOk = (v, d) => { const s = String(v === undefined || v === null ? d : v).trim(); return /^\d{1,2}[:：]\d{2}$/.test(s) ? s.replace("：", ":") : (s === "" ? "off" : d); };

// 你在 VS Code 設過的（使用者／工作區設定有值）才推給桌面版；沒設過的就用桌面版自己的設定（公仔小屋 → 讀書小幫手設定）
function studySetLines(get, isSet) {
	const lines = [];
	const keys = [["schoolIcsUrl", "urls"], ["classRemindMinutes", "remind"], ["classAutoQuiet", "autoquiet"], ["lateNightStart", "late"], ["examNudgeTime", "nudge"]].filter((k) => isSet(k[0])).map((k) => k[1]);
	lines.push(`study-vs ${keys.join(",") || "-"}`);   // 哪幾項由 VS Code 管（拿掉的那幾項，桌面版設定視窗就能改回來）
	if (isSet("schoolIcsUrl")) lines.push(("study-set urls " + schoolUrls(get("schoolIcsUrl", [])).join(" ")).trim());
	if (isSet("classRemindMinutes")) lines.push(`study-set remind ${Math.max(1, Math.min(120, Number(get("classRemindMinutes", 10)) || 10))}`);
	if (isSet("classAutoQuiet")) lines.push(`study-set autoquiet ${get("classAutoQuiet", true) ? 1 : 0}`);
	if (isSet("lateNightStart")) lines.push(`study-set late ${hhmmOk(get("lateNightStart", "01:00"), "01:00")}`);
	if (isSet("examNudgeTime")) lines.push(`study-set nudge ${hhmmOk(get("examNudgeTime", "20:00"), "20:00")}`);
	lines.push(`study-set workcal ${schoolUrls(get("calendarIcsUrl", ""))[0] || "-"}`);   // 開會提醒用的那份：桌面版不重複提醒
	return lines;
}

const shortName = (s, n = 8) => (s.length > n ? s.slice(0, n) + "…" : s);
const fmtWhen = (t) => new Date(t).toLocaleString("zh-TW", { month: "numeric", day: "numeric", weekday: "short", hour: "2-digit", minute: "2-digit", hour12: false });
function leftText(ms) {
	if (ms < 3600e3) return `剩 ${Math.max(1, Math.ceil(ms / 60e3))} 分`;
	if (ms < 48 * 3600e3) return `剩 ${Math.floor(ms / 3600e3)} 小時`;
	return `剩 ${Math.floor(ms / 864e5)} 天`;
}
function daysLeft(at, now) {
	const a = new Date(at), b = new Date(now);
	a.setHours(0, 0, 0, 0); b.setHours(0, 0, 0, 0);
	return Math.round((a - b) / 864e5);
}

function studySetup(context, desktop) {
	const subs = context.subscriptions;
	const st = { state: null };   // 桌面版送來的：{ bar, school, d:[{id,due,title,course,url}], e:[{id,at,name}] }
	const bar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 999);
	bar.command = "deskPals.deadlines";
	bar.tooltip = "公仔櫃：最近的作業死線／考試（點我看這週要交的）";
	const refresh = () => { const t = st.state && st.state.bar; if (t) { bar.text = t; bar.show(); } else bar.hide(); };
	subs.push(bar);

	const sync = () => {
		const c = cfg();
		const isSet = (k) => { const i = c.inspect(k); return !!i && (i.globalValue !== undefined || i.workspaceValue !== undefined || i.workspaceFolderValue !== undefined); };
		for (const line of studySetLines((k, d) => c.get(k, d), isSet)) desktop.send(line);
		desktop.send("study-hello");
	};
	const prevCfg = desktop.onConfig;
	desktop.onConfig = () => { if (prevCfg) prevCfg(); sync(); };   // 每次連上桌面版都推一次
	const prevLine = desktop.onLine;
	desktop.onLine = (line) => {
		if (prevLine) prevLine(line);
		const m = /^study-state (.*)$/.exec(line);
		if (m) { try { st.state = JSON.parse(m[1]); } catch (e) { st.state = null; } refresh(); }
	};
	subs.push(vscode.workspace.onDidChangeConfiguration((e) => {
		if (["schoolIcsUrl", "classRemindMinutes", "classAutoQuiet", "lateNightStart", "examNudgeTime", "calendarIcsUrl"].some((k) => e.affectsConfiguration("deskPals." + k))) sync();
	}));
	subs.push(vscode.commands.registerCommand("deskPals.course", () => ticketMe(desktop, "course")));
	subs.push(vscode.commands.registerCommand("deskPals.exam", () => examMe(desktop)));
	subs.push(vscode.commands.registerCommand("deskPals.deadlines", () => showDeadlines(st, desktop)));
	subs.push(vscode.commands.registerCommand("deskPals.schoolSetup", () => schoolSetupCmd()));
}

async function examMe(desktop) {
	const name = await vscode.window.showInputBox({ title: "考試倒數（1/3）：什麼考試？", placeHolder: "例如：微積分期末考" });
	if (!name) return;
	const date = await vscode.window.showInputBox({ title: "考試倒數（2/3）：哪一天？", placeHolder: "例如 2027-01-08 或 1/8" });
	if (!date) return;
	const time = await vscode.window.showInputBox({ title: "考試倒數（3/3）：幾點開始？", value: "09:00" });
	if (!time) return;
	const at = parseTicketTime(date, time);
	if (!at) { vscode.window.showWarningMessage("看不懂這個日期／時間，或已經過了。日期打 2027-01-08 或 1/8，時間打 09:00。"); return; }
	desktop.send(`exam ${at} ${clean(name)}`);
	vscode.window.showInformationMessage(`📚 記下來了：${clean(name)}，${fmtWhen(at)}。考前兩週每天倒數、前一天晚上和當天早上都會提醒你；7 天內專注會變成「讀書 25 分鐘」。`);
}

async function showDeadlines(st, desktop) {
	const now = Date.now(), s = st.state || {};
	const items = [];
	if (s.school) {
		const ds = (s.d || []).filter((x) => x.due > now);
		items.push({ label: "這週要交的", kind: vscode.QuickPickItemKind.Separator });
		if (!ds.length) items.push({ label: "🎉 這週沒有要交的作業" });
		for (const x of ds) items.push({ label: `📝 ${x.title}`, description: x.course, detail: `${fmtWhen(x.due)} 截止（${leftText(x.due - now)}）`, d: x });
	}
	const ex = (s.e || []).filter((e) => e.at > now);
	if (ex.length) {
		items.push({ label: "考試", kind: vscode.QuickPickItemKind.Separator });
		for (const e of ex) { const d = daysLeft(e.at, now); items.push({ label: `📚 ${e.name}`, detail: `${fmtWhen(e.at)}（${d <= 0 ? "今天" : d === 1 ? "明天" : `還有 ${d} 天`}）`, e }); }
	}
	items.push({ label: "", kind: vscode.QuickPickItemKind.Separator });
	items.push({ label: "📚 新增考試倒數…", cmd: "deskPals.exam" });
	if (!s.school) items.push({ label: "🎒 加入學校行事曆（Canvas／NTU COOL／Moodle／Google Classroom）…", cmd: "deskPals.schoolSetup" });
	const pick = await vscode.window.showQuickPick(items, { title: "公仔櫃：這週要交的", placeHolder: s.school ? "選一份作業：打開或標成交了" : "還沒設定學校行事曆" });
	if (!pick) return;
	if (pick.cmd) { vscode.commands.executeCommand(pick.cmd); return; }
	if (pick.d) {
		const acts = [{ label: "✅ 交了，不用再提醒", v: "done" }];
		if (pick.d.url) acts.unshift({ label: "🔗 打開作業頁", v: "open" });
		const a = await vscode.window.showQuickPick(acts, { title: pick.d.title });
		if (!a) return;
		if (a.v === "open") vscode.env.openExternal(vscode.Uri.parse(pick.d.url));
		else desktop.send(`study-done ${pick.d.id}`);
	} else if (pick.e) {
		const a = await vscode.window.showQuickPick([{ label: "🗑 取消這個考試倒數", v: "del" }], { title: pick.e.name });
		if (a) desktop.send(`exam-del ${pick.e.id}`);
	}
}

async function schoolSetupCmd() {
	const url = await vscode.window.showInputBox({
		title: "加入學校行事曆（ICS 網址）",
		placeHolder: "https://…（Canvas／NTU COOL：行事曆 → 行事曆摘要；Moodle：行事曆 → 匯出；Google 日曆：iCal 格式的私密網址）",
		validateInput: (v) => schoolUrls(v).length ? null : "要 https:// 或 webcal:// 開頭的網址",
	});
	if (!url) return;
	const now = schoolUrls(cfg().get("schoolIcsUrl", []));
	for (const u of schoolUrls(url)) if (!now.includes(u)) now.push(u);
	await cfg().update("schoolIcsUrl", now, vscode.ConfigurationTarget.Global);   // 設定改變 → 推給桌面版
	vscode.window.showInformationMessage(`🎒 加好了（共 ${now.length} 個學校行事曆）。上課前會提醒你，作業截止前 3 天、1 天、3 小時、1 小時也會叫你。`);
}

module.exports = { setup, parseIcs, occurrences, parseWhen, parseTicketTime, rainText, rainFromWttr, rainFromMetno, schoolUrls, hhmmOk, studySetLines };
