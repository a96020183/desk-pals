// 測試用的假 glab／gh（test/desktop-work.js）：桌面版離屏時設 DESKPALS_FAKE_CLI＝這支，它就跑「node fake-cli.js glab|gh <參數…>」。
// 回什麼由 FAKE_CLI_STATE（JSON 檔，測試中途會改）決定；每次被叫都記一行到 FAKE_CLI_LOG（測試拿來確認沒碰 token、全關時一次都沒叫）。
const fs = require("fs");
const [, , tool, ...args] = process.argv;
const state = JSON.parse(fs.readFileSync(process.env.FAKE_CLI_STATE, "utf8"));
if (process.env.FAKE_CLI_LOG) fs.appendFileSync(process.env.FAKE_CLI_LOG, [tool, ...args].join(" ") + "\n");
const out = (v) => { process.stdout.write(typeof v === "string" ? v : JSON.stringify(v)); process.exit(0); };
const fail = (msg) => { process.stderr.write(msg + "\n"); process.exit(1); };
const t = state[tool];
if (!t || t.missing) fail(tool + ": not installed");
if (args[0] === "auth" && args[1] === "status") {
	// 跟真的一樣：登入資訊寫在 stderr、token 打星號
	if (!t.user) { process.stderr.write("You are not logged into any hosts.\n"); process.exit(1); }
	process.stderr.write(tool === "glab"
		? `${t.host}\n  ✓ Logged in to ${t.host} as ${t.user} (keyring)\n  ✓ Token found in operating system keyring: **************************\n`
		: `github.com\n  ✓ Logged in to github.com account ${t.user} (keyring)\n  - Active account: true\n  - Token: gho_************************************\n`);
	process.exit(0);
}
if (args[0] !== "api") fail("unexpected: " + args.join(" "));
let p = args[args.length - 1];
if (tool === "glab") {
	const i = args.indexOf("--hostname");
	if (i < 0 || args[i + 1] !== t.host) fail("wrong host");
	if (p.startsWith("todos")) out(t.todos || []);
	if (p.startsWith("events")) out(t.events || []);
	let m = /^projects\/(\d+)\/pipelines\?ref=([^&]+)/.exec(p);
	if (m) out((t.pipelines || {})[decodeURIComponent(m[2])] || []);
	m = /^projects\/(\d+)$/.exec(p);
	if (m && (t.projects || {})[m[1]]) out(t.projects[m[1]]);
	fail("404 " + p);
}
if (p.startsWith("notifications")) out(t.notifications || []);
if (/^users\/[^/]+\/events/.test(p)) out(t.events || []);
const m = /^repos\/([^/]+\/[^/]+)\/actions\/runs/.exec(p);
if (m) out({ workflow_runs: (t.runs || {})[m[1]] || [] });
fail("404 " + p);
