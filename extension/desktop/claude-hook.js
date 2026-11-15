#!/usr/bin/env node
// Claude Code hook → 通知桌面上的公仔櫃（Windows：named pipe；macOS：unix socket）。
// 用法（settings.json 的 hooks）：node claude-hook.js start|done|wait|post
//   start＝UserPromptSubmit、done＝Stop、wait＝Notification、post＝PostToolUse(Bash)：偵測 git push tag 成功 → 放煙火
// 桌面版沒開或任何錯誤都安靜結束（exit 0），絕不擋 Claude。
const net = require("net");
const os = require("os");
const path = require("path");

const ev = process.argv[2] || "";
const user = (os.userInfo().username || "me").replace(/[^A-Za-z0-9_.-]/g, "_");
// Windows 先找公仔櫃，找不到再找舊版 Spidey 小夥伴
const endpoints = process.platform === "win32"
	? ["\\\\.\\pipe\\desk-pals-" + user, "\\\\.\\pipe\\spidey-pet-" + user]
	: [path.join(os.homedir(), "Library", "Application Support", "SpideyDesktop", "spidey.sock")];

const bail = setTimeout(() => process.exit(0), 1500);

function send(line, i = 0) {
	if (i >= endpoints.length) process.exit(0);
	const s = net.connect(endpoints[i]);
	let ok = false;
	s.on("connect", () => { ok = true; s.end(line + "\n"); });
	s.on("error", () => { if (!ok) send(line, i + 1); else process.exit(0); });
	s.on("close", () => { if (ok) process.exit(0); });
}

// git push 帶 tag 而且成功 → 回傳 [tag, env]；否則 null
function tagPush(cmd, out) {
	if (!/\bgit\b[^\n|;&]*\bpush\b/.test(cmd)) return null;
	const text = String(out || "");
	if (/\b(rejected|fatal|error:)/i.test(text)) return null;
	const tagged = /--tags|--follow-tags|refs\/tags\//.test(cmd) || /\[new tag\]/.test(text);
	const m = /(\d+\.\d+\.\d+(?:-[A-Za-z]+\.\d+)?)/.exec(cmd) || /\[new tag\]\s+(\S+)/.exec(text);
	if (!tagged && !(m && /push\s+\S+\s+\S*\d+\.\d+\.\d+/.test(cmd))) return null;
	const tag = m ? m[1] : "tag";
	const env = /Production/i.test(tag + cmd) ? "prod" : /Development/i.test(tag + cmd) ? "dev" : "other";
	return [tag, env];
}

let raw = "";
if (process.stdin.isTTY) handle({});
else {
	process.stdin.setEncoding("utf8");
	process.stdin.on("data", (d) => (raw += d));
	process.stdin.on("end", () => {
		let j = {};
		try { j = JSON.parse(raw); } catch (e) {}
		handle(j);
	});
}

function handle(j) {
	const sid = String(j.session_id || "x").replace(/\s/g, "").slice(0, 40) || "x";
	if (ev === "start" || ev === "done" || ev === "wait") return send(`claude ${ev} ${sid}`);
	if (ev === "post") {
		const cmd = (j.tool_input && j.tool_input.command) || "";
		const r = j.tool_response || {};
		const out = typeof r === "string" ? r : [r.stdout, r.stderr, r.output].filter(Boolean).join("\n");
		const hit = tagPush(cmd, out);
		if (hit) {
			// 另外叫一支背景的 ci-watch 盯部署結果（hook 本身馬上結束，不擋 Claude）
			const cwd = (/(?:^|&&|;)\s*cd\s+("([^"]+)"|(\S+))/.exec(cmd) || [])[2] || (/(?:^|&&|;)\s*cd\s+(\S+)/.exec(cmd) || [])[1] || j.cwd;
			const dirArg = (/git\s+-C\s+("([^"]+)"|(\S+))/.exec(cmd) || []);
			const repo = dirArg[2] || dirArg[3] || cwd;
			if (repo && hit[0] !== "tag") {
				try {
					require("child_process").spawn(process.execPath, [path.join(__dirname, "ci-watch.js"), repo, hit[0], hit[1]],
						{ detached: true, stdio: "ignore", windowsHide: true }).unref();
				} catch (e) {}
			}
			return send(`tag ${hit[0]} ${hit[1]}`);
		}
	}
	clearTimeout(bail);
	process.exit(0);
}
