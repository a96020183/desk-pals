#!/usr/bin/env node
// Claude Code hook → 通知桌面上的 Spidey。
// 用法（settings.json 的 hooks）：node claude-hook.js start|done|wait|post
//   start＝UserPromptSubmit、done＝Stop、wait＝Notification、post＝PostToolUse(Bash)：偵測 git push tag 成功 → 放煙火
// 桌面版沒開或任何錯誤都安靜結束（exit 0），絕不擋 Claude。
const net = require("net");
const os = require("os");
const path = require("path");

const ev = process.argv[2] || "";
const user = (os.userInfo().username || "me").replace(/[^A-Za-z0-9_.-]/g, "_");
const endpoint = process.platform === "win32"
	? "\\\\.\\pipe\\spidey-pet-" + user
	: path.join(os.homedir(), "Library", "Application Support", "SpideyDesktop", "spidey.sock");

const bail = setTimeout(() => process.exit(0), 1500);

function send(line) {
	const s = net.connect(endpoint);
	s.on("connect", () => s.end(line + "\n"));
	s.on("error", () => process.exit(0));
	s.on("close", () => process.exit(0));
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
		if (hit) return send(`tag ${hit[0]} ${hit[1]}`);
	}
	clearTimeout(bail);
	process.exit(0);
}
