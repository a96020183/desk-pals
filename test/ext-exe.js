// Windows：VS Code 擴充套件從 vsix 啟動時，跑的是 vsix 附上的 DeskPals.exe，不是 PowerShell（Add-Type 即時編譯）。
// 用法：node test/ext-exe.js <解開的 vsix 的 extension 資料夾> <工作資料夾> <pipe 名稱前綴（後面會加亂數）>
//
// 不開真的 VS Code：用假的 vscode 模組直接叫 extension.js 的 activate()（每一段「VS Code 開著的時間」是一個子程序，結束＝關掉 VS Code）。
// 全部關在工作資料夾裡：LOCALAPPDATA、APPDATA（開機捷徑）、USERPROFILE、TEMP（紀錄檔）都換成工作資料夾底下的；
// 桌面版用離屏＋隔離模式（DESKPALS_OFFSCREEN／DESKPALS_ISOLATED）、自己的 pipe（DESKPALS_PIPE），不碰使用者正在跑的公仔櫃。
// 只停自己開的程序（照 PID）。
//
// 一、從 PowerShell 版升級：擺一份舊的安裝（.cs＋desk-pals.ps1、指著 powershell.exe 的開機捷徑、資料），舊的在跑 →
//     擴充套件啟動：exe 放到 %LOCALAPPDATA%\DeskPals\app、--replace 叫舊的收工、開機捷徑改指 exe、資料不動、沒叫過 powershell.exe
// 二、exe 改版（擴充套件升級）時舊 exe 還開著：開著的檔案改名讓開、新的放上去、舊的收工換新的
// 三、同一版再開一次 VS Code：什麼都不換、不重開，上次改名的舊 exe 刪掉
// 四、vsix 沒附 exe（從原始碼跑）：退回 desk-pals.ps1（另一個工作資料夾、另一個 pipe）
// 五、裝了 Microsoft Store 版（MSIX 的檔案被虛擬化，看不到它寫的 standalone.json）：靠執行別名
//     %LOCALAPPDATA%\Microsoft\WindowsApps\DeskPals.exe 認出來 → 不放 exe、不建開機捷徑，叫別名起來、連過去
const cp = require("child_process");
const fs = require("fs");
const net = require("net");
const path = require("path");
const Module = require("module");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const read = (f, enc) => { try { return fs.readFileSync(f, enc); } catch (e) { return null; } };
const LNK = "公仔櫃 Desk Pals.lnk";

// ---------------------------------------------------------------- 子程序：一段「VS Code 開著」

async function session(extDir) {
	// 擴充套件叫了什麼程式都記下來（spawn／execFile…）
	const calls = [];
	for (const fn of ["spawn", "execFile", "exec", "spawnSync", "execFileSync", "execSync", "fork"]) {
		const real = cp[fn];
		cp[fn] = function (file, ...rest) { calls.push({ fn, file: String(file), args: Array.isArray(rest[0]) ? rest[0].map(String) : [] }); return real.call(this, file, ...rest); };
	}
	const warnings = [];
	const any = new Proxy(function () {}, { get: (t, k) => (k === "then" ? undefined : k === Symbol.iterator ? [][Symbol.iterator].bind([]) : any), apply: () => any, construct: () => any });
	const cfg = { get: (k, d) => d, inspect: () => undefined, update: async () => {}, has: () => false };
	const disposable = () => ({ dispose() {} });
	const vscode = new Proxy({
		window: new Proxy({
			createStatusBarItem: () => ({ show() {}, hide() {}, dispose() {} }),
			registerWebviewViewProvider: disposable,
			showWarningMessage: async (m) => { warnings.push(String(m)); },
			showInformationMessage: async () => {},
			showErrorMessage: async (m) => { warnings.push(String(m)); },
		}, { get: (t, k) => (k in t ? t[k] : disposable) }),
		workspace: new Proxy({ getConfiguration: () => cfg }, { get: (t, k) => (k in t ? t[k] : disposable) }),
		languages: new Proxy({ getDiagnostics: () => [] }, { get: (t, k) => (k in t ? t[k] : disposable) }),
		commands: { registerCommand: disposable, executeCommand: async () => {} },
		StatusBarAlignment: { Left: 1, Right: 2 },
		ConfigurationTarget: { Global: 1, Workspace: 2 },
	}, { get: (t, k) => (k in t ? t[k] : any) });
	const realLoad = Module._load;
	Module._load = function (req, parent, isMain) { return req === "vscode" ? vscode : realLoad.call(this, req, parent, isMain); };
	// 實用功能（行事曆、Jira、天氣…）不在這個測試裡：換成空的
	const prac = path.join(extDir, "practical.js");
	const m = new Module(prac); m.filename = prac; m.loaded = true; m.exports = { setup() {} };
	require.cache[prac] = m;

	const store = {};
	const context = { extensionPath: extDir, subscriptions: [], globalState: { get: (k, d) => (k in store ? store[k] : d), update: async (k, v) => { store[k] = v; }, keys: () => Object.keys(store) } };
	require(path.join(extDir, "extension.js")).activate(context);
	const desktop = context.subscriptions.find((s) => s && typeof s.connected === "function" && typeof s.spawn === "function");
	const mark = path.join(process.env.LOCALAPPDATA, "DeskPals", "app", "autostart.txt");
	const end = Date.now() + 120000;
	while (Date.now() < end && !(desktop.connected() && (!desktop.useExe || fs.existsSync(mark)))) await sleep(250);
	// 換版時先連到舊的、舊的收工後再接到新的：等一下再確認一次還連著（接回新的）
	await sleep(3000);
	const end2 = Date.now() + 30000;
	while (Date.now() < end2 && !desktop.connected()) await sleep(250);
	console.log(JSON.stringify({ connected: desktop.connected(), useExe: !!desktop.useExe, calls, warnings }));
	process.exit(0);
}

// ---------------------------------------------------------------- 主程序
let problems = 0;
const check = (ok, what) => { console.log((ok ? "ok   " : "FAIL ") + what); if (!ok) problems++; return ok; };
const mine = new Set();   // 這個測試開的（或擴充套件替這個測試開的）程序：最後照 PID 收

function envFor(W, pipe) {
	const e = Object.assign({}, process.env, {
		LOCALAPPDATA: path.join(W, "local"), APPDATA: path.join(W, "roaming"), USERPROFILE: path.join(W, "home"), HOME: path.join(W, "home"),
		TEMP: path.join(W, "tmp"), TMP: path.join(W, "tmp"), CLAUDE_CONFIG_DIR: path.join(W, "home", ".claude"), CODEX_HOME: path.join(W, "home", ".codex"),
		DESKPALS_OFFSCREEN: "1", DESKPALS_ISOLATED: "1", DESKPALS_DATA_DIR: path.join(W, "local", "DeskPals"), DESKPALS_PIPE: pipe,
	});
	for (const d of ["local", "roaming", "home", "tmp"]) fs.mkdirSync(path.join(W, d), { recursive: true });
	return e;
}
const startupDir = (W) => path.join(W, "roaming", "Microsoft", "Windows", "Start Menu", "Programs", "Startup");

function runSession(extDir, env) {
	const r = cp.spawnSync(process.execPath, [__filename, "--session", extDir], { env, encoding: "utf8", timeout: 180000, windowsHide: true });
	const line = (r.stdout || "").trim().split("\n").pop();
	try { return JSON.parse(line); } catch (e) { console.log(r.stdout, r.stderr); return { error: "no result" }; }
}

// pipe 名稱出現在命令列的程序（不含查詢自己的 powershell：pipe 名稱用環境變數傳）
function procs(pipe) {
	const ps = "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($env:Q) } | ForEach-Object { [pscustomobject]@{ pid = $_.ProcessId; name = $_.Name; exe = $_.ExecutablePath; cmd = $_.CommandLine } } | ConvertTo-Json -Compress";
	const r = cp.spawnSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", ps], { env: Object.assign({}, process.env, { Q: pipe }), encoding: "utf8", windowsHide: true });
	const out = (r.stdout || "").trim();
	if (!out) return [];
	const j = JSON.parse(out);
	const list = (Array.isArray(j) ? j : [j]).filter((p) => /^(DeskPals\.exe|powershell\.exe)$/i.test(p.name || "") && p.pid !== process.pid);
	for (const p of list) mine.add(p.pid);
	return list;
}
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch (e) { return false; } };
async function waitGone(pid, ms) { const end = Date.now() + ms; while (Date.now() < end && alive(pid)) await sleep(250); return !alive(pid); }

// 讀／建捷徑用 WScript.Shell，但它只認系統 ANSI 字碼頁：英文 Windows（CI）上中文檔名讀寫都會失敗。
// 所以一律在同一個資料夾用純英文的暫存檔名操作，再改名（捷徑的內容跟檔名無關）
function asciiTmp(lnk) { return path.join(path.dirname(lnk), "tmp-" + process.pid + "-" + Date.now() + ".lnk"); }
function lnkInfo(lnk) {
	if (!fs.existsSync(lnk)) return {};
	const tmp = asciiTmp(lnk);
	fs.copyFileSync(lnk, tmp);
	const ps = "$s = (New-Object -ComObject WScript.Shell).CreateShortcut($env:L); [pscustomobject]@{ target = $s.TargetPath; args = $s.Arguments } | ConvertTo-Json -Compress";
	const r = cp.spawnSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", ps], { env: Object.assign({}, process.env, { L: tmp }), encoding: "utf8", windowsHide: true });
	fs.unlinkSync(tmp);
	try { return JSON.parse(r.stdout.trim()); } catch (e) { return {}; }
}
// 舊版擴充套件建的捷徑（同一個寫法：powershell.exe -File desk-pals.ps1）
function oldLnk(lnk, ps1, pipe) {
	fs.mkdirSync(path.dirname(lnk), { recursive: true });
	const tmp = asciiTmp(lnk);
	const ps = "$s = (New-Object -ComObject WScript.Shell).CreateShortcut($env:L); $s.TargetPath = \"$env:SystemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\"; $s.Arguments = '-NoProfile -WindowStyle Hidden -File \"' + $env:S + '\" -PipeName ' + $env:Q; $s.WindowStyle = 7; $s.Save()";
	cp.spawnSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", ps], { env: Object.assign({}, process.env, { L: tmp, S: ps1, Q: pipe }), windowsHide: true });
	fs.renameSync(tmp, lnk);
}
// 「開機」資料夾不存在、檔名有任何 ANSI 字碼頁都沒有的字（泰文、拉丁擴充）：exe --autostart 還是要建得出來（本機重現英文 Windows 上的情況）
function autostartUnicode(exe, W, pipe) {
	const lnk = path.join(W, "no-such-dir", "Startup", "公仔櫃 \u0e01 \u0109 Desk Pals.lnk");
	const run = () => cp.spawnSync(exe, ["--autostart", lnk, "--pipe", pipe], { windowsHide: true, timeout: 30000 }).status;
	check(run() === 0 && fs.existsSync(lnk), "exe --autostart creates a shortcut with a non-ANSI name in a missing folder");
	const li = lnkInfo(lnk);
	check(path.resolve(li.target || "x") === exe && li.args === "--pipe " + pipe, "  … pointing to the exe (" + li.target + " " + li.args + ")");
	const before = fs.statSync(lnk).mtimeMs;
	check(run() === 0 && fs.statSync(lnk).mtimeMs === before, "  … second run leaves it alone");
	oldLnk(lnk, "C:\\old\\desk-pals.ps1", pipe);
	check(/powershell\.exe$/i.test(lnkInfo(lnk).target || ""), "  … (old PowerShell shortcut put back)");
	check(run() === 0 && path.resolve(lnkInfo(lnk).target || "x") === exe, "  … and an old PowerShell one under that name gets repointed");
}

function ask(pipe, line, wantRe, ms) {
	return new Promise((resolve) => {
		const s = net.connect("\\\\.\\pipe\\" + pipe);
		let buf = "", done = false;
		const fin = (v) => { if (done) return; done = true; s.destroy(); resolve(v); };
		s.setEncoding("utf8");
		s.on("connect", () => s.write(line + "\n"));
		s.on("data", (d) => { buf += d; const m = wantRe && wantRe.exec(buf); if (m || !wantRe) fin(m ? m[0] : true); });
		s.on("error", () => fin(null));
		setTimeout(() => fin(wantRe ? null : true), ms || 3000);
	});
}
async function waitPipe(pipe, ms) { const end = Date.now() + ms; while (Date.now() < end) { if (await ask(pipe, "hello", /lineup \w+/, 1500)) return true; await sleep(500); } return false; }

function copyDir(from, to) {
	fs.mkdirSync(to, { recursive: true });
	for (const e of fs.readdirSync(from, { withFileTypes: true })) {
		const a = path.join(from, e.name), b = path.join(to, e.name);
		if (e.isDirectory()) copyDir(a, b); else fs.copyFileSync(a, b);
	}
}

async function main() {
	const [extDir0, W0, prefix] = process.argv.slice(2);
	if (!extDir0 || !W0 || !/^[A-Za-z0-9_.-]+$/.test(prefix || "")) { console.log("usage: node test/ext-exe.js <extension dir> <work dir> <pipe prefix>"); process.exit(2); }
	// pipe 名稱＝前綴＋亂數：只有這次測試的程序命令列裡有完整的名字（叫這個測試的 shell 只有前綴，不會被當成測試的程序）
	const pipe = prefix + "-" + require("crypto").randomBytes(4).toString("hex");
	console.log("pipe " + pipe);
	const extDir = path.resolve(extDir0), W = path.resolve(W0);
	if (process.platform !== "win32") { console.log("Windows only"); process.exit(0); }
	if (!fs.existsSync(path.join(extDir, "desktop", "DeskPals.exe"))) { console.log("FAIL no desktop/DeskPals.exe in " + extDir); process.exit(1); }
	if (fs.existsSync(W)) fs.rmSync(W, { recursive: true, force: true });
	const env = envFor(W, pipe);
	const home = path.join(W, "local", "DeskPals"), app = path.join(home, "app"), exe = path.join(app, "DeskPals.exe");
	const lnk = path.join(startupDir(W), LNK);
	const log = path.join(W, "tmp", "desk-pals.log");
	try {
		// ---------- 一、PowerShell 版 → exe 版 ----------
		console.log("== 1. upgrade from the PowerShell version (old one running)");
		const src = path.join(extDir, "desktop");
		fs.mkdirSync(home, { recursive: true });
		for (const f of fs.readdirSync(src)) if (/^DeskPals(\.[A-Za-z]+)?\.cs$/.test(f) || f === "desk-pals.ps1" || f === "claude-hook.js" || f === "ci-watch.js") fs.copyFileSync(path.join(src, f), path.join(home, f));
		copyDir(path.join(src, "pals"), path.join(home, "pals"));
		const data = { "profile.txt": "done", "mode.txt": "shelf", "lineup.txt": "original", "bond-duoduo.txt": "7", "keep-me.txt": "使用者的資料" };
		for (const [f, v] of Object.entries(data)) fs.writeFileSync(path.join(home, f), v);
		oldLnk(lnk, path.join(home, "desk-pals.ps1"), pipe);
		check(/powershell\.exe$/i.test(lnkInfo(lnk).target || ""), "old startup shortcut points to powershell.exe");
		const old = cp.spawn("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(home, "desk-pals.ps1"), "-PipeName", pipe], { env, stdio: "ignore", windowsHide: true });
		mine.add(old.pid);
		check(await waitPipe(pipe, 180000), "old PowerShell version is up (pid " + old.pid + ")");

		const s1 = runSession(extDir, env);
		check(!s1.error, "session 1 ran " + (s1.error || ""));
		check(s1.connected && s1.useExe, "extension connected, exe mode");
		const called = (s1.calls || []).map((c) => path.basename(c.file) + " " + c.args.join(" "));
		console.log("     extension ran: " + JSON.stringify(called));
		check(!(s1.calls || []).some((c) => /powershell|pwsh/i.test(c.file)), "extension never ran powershell.exe");
		check((s1.calls || []).some((c) => path.resolve(c.file) === exe && c.args[0] === "--replace"), "extension ran app\\DeskPals.exe --replace");
		check((s1.calls || []).some((c) => path.resolve(c.file) === exe && c.args[0] === "--autostart"), "extension ran app\\DeskPals.exe --autostart");
		check(!(s1.calls || []).some((c) => c.file.toLowerCase().startsWith(extDir.toLowerCase())), "nothing runs from the extension's install folder");
		check(await waitGone(old.pid, 30000), "old PowerShell version quit");
		check(await waitPipe(pipe, 30000), "new desktop answers on the pipe");
		let ps = procs(pipe);
		console.log("     on the pipe: " + JSON.stringify(ps.map((p) => p.name + " " + p.exe)));
		check(ps.length === 1 && path.resolve(ps[0].exe || "") === exe, "exactly one process on the pipe, and it is %LOCALAPPDATA%\\DeskPals\\app\\DeskPals.exe");
		check(!ps.some((p) => /powershell/i.test(p.name)), "no powershell.exe on the pipe");
		const pidA = ps.length ? ps[0].pid : 0;
		const lg = read(log, "utf8") || "";
		check(new RegExp("exe \\S+ replace pipe=" + pipe).test(lg), "desk-pals.log: exe started in replace mode");
		const li = lnkInfo(lnk);
		check(path.resolve(li.target || "x") === exe && li.args === "--pipe " + pipe, "startup shortcut now points to the exe (" + li.target + " " + li.args + ")");
		check(fs.readdirSync(startupDir(W)).length === 1, "still one startup shortcut");
		autostartUnicode(exe, W, pipe);
		for (const [f, v] of Object.entries(data)) if (f !== "lineup.txt") check(read(path.join(home, f), "utf8") === v, "data untouched: " + f);
		check(Buffer.compare(read(exe), read(path.join(src, "DeskPals.exe"))) === 0, "app\\DeskPals.exe is the vsix's exe");
		check(!(s1.warnings || []).length, "no warnings " + JSON.stringify(s1.warnings || []));

		// ---------- 二、exe 改版、舊 exe 還開著 ----------
		console.log("== 2. extension upgrade while the old exe is running (locked file)");
		const ext2 = path.join(W, "ext2");
		copyDir(extDir, ext2);
		fs.appendFileSync(path.join(ext2, "desktop", "DeskPals.exe"), Buffer.alloc(512));   // 內容不同的「新版」（PE 後面多的資料不影響執行）
		const s2 = runSession(ext2, env);
		check(s2.connected && s2.useExe, "session 2 connected");
		check((s2.calls || []).some((c) => path.resolve(c.file) === exe && c.args[0] === "--replace"), "new exe started with --replace");
		check(!(s2.calls || []).some((c) => /powershell|pwsh/i.test(c.file)), "no powershell.exe");
		check(await waitGone(pidA, 30000), "old exe quit (pid " + pidA + ")");
		check(await waitPipe(pipe, 30000), "pipe answers");
		ps = procs(pipe);
		check(ps.length === 1 && path.resolve(ps[0].exe || "") === exe && ps[0].pid !== pidA, "one new exe process on the pipe");
		const pidB = ps.length ? ps[0].pid : 0;
		check(Buffer.compare(read(exe), read(path.join(ext2, "desktop", "DeskPals.exe"))) === 0, "app\\DeskPals.exe replaced with the new one");
		const olds = fs.readdirSync(app).filter((f) => /^DeskPals\.exe\.old-/.test(f));
		check(olds.length === 1, "the running exe was renamed out of the way (" + olds.join(",") + ")");

		// ---------- 三、同一版再開一次 ----------
		console.log("== 3. same version again (VS Code restart)");
		const s3 = runSession(ext2, env);
		check(s3.connected, "session 3 connected");
		check(!(s3.calls || []).some((c) => c.args[0] === "--replace" || c.args[0] === "--autostart"), "no --replace / --autostart: " + JSON.stringify((s3.calls || []).map((c) => path.basename(c.file) + " " + c.args.join(" "))));
		check(alive(pidB) && procs(pipe).length === 1, "same exe keeps running (pid " + pidB + ")");
		check(fs.readdirSync(app).filter((f) => /^DeskPals\.exe\.(old|new)-/.test(f)).length === 0, "renamed old exe cleaned up");

		await ask(pipe, "quit", null, 1500);
		check(await waitGone(pidB, 15000), "quit");

		// ---------- 四、沒附 exe：退回 desk-pals.ps1 ----------
		console.log("== 4. no exe in the extension (running from source): falls back to desk-pals.ps1");
		const W4 = path.join(W, "fallback"), pipe4 = pipe + "-ps1";
		const env4 = envFor(W4, pipe4);
		const ext4 = path.join(W, "ext4");
		copyDir(extDir, ext4);
		fs.unlinkSync(path.join(ext4, "desktop", "DeskPals.exe"));
		const s4 = runSession(ext4, env4);
		check(s4.connected && !s4.useExe, "connected through desk-pals.ps1");
		check((s4.calls || []).some((c) => /powershell/i.test(c.file)), "used powershell.exe");
		check(!fs.existsSync(path.join(W4, "local", "DeskPals", "app")), "no app folder");
		const lnk4 = path.join(startupDir(W4), LNK);   // 「開機」資料夾本來不存在；中文檔名（英文 Windows 上也要建得出來）
		for (let i = 0; i < 40 && !fs.existsSync(lnk4); i++) await sleep(250);
		check(/powershell\.exe$/i.test(lnkInfo(lnk4).target || ""), "PowerShell version created its startup shortcut (" + LNK + ")");
		procs(pipe4);
		await ask(pipe4, "quit", null, 1500);
		await sleep(3000);

		// ---------- 五、Microsoft Store 版：認執行別名 ----------
		console.log("== 5. Microsoft Store version installed (found by its execution alias, no standalone.json)");
		const W5 = path.join(W, "store"), pipe5 = pipe + "-msix";
		const env5 = envFor(W5, pipe5);
		const alias = path.join(W5, "local", "Microsoft", "WindowsApps", "DeskPals.exe");
		fs.mkdirSync(path.dirname(alias), { recursive: true });
		fs.copyFileSync(path.join(extDir, "desktop", "DeskPals.exe"), alias);   // 測試用：真的別名是 AppExecLink，這裡放一支一樣的 exe
		const s5 = runSession(extDir, env5);
		check(s5.connected && !s5.useExe, "connected to the Store app");
		check((s5.calls || []).some((c) => path.resolve(c.file) === alias && c.args.includes("--pipe")), "started the execution alias");
		check(!(s5.calls || []).some((c) => c.args[0] === "--autostart" || c.args[0] === "--replace"), "no --autostart / --replace (the Store app owns its startup)");
		check(!fs.existsSync(path.join(W5, "local", "DeskPals", "app")), "no app folder (did not install its own exe)");
		check(!fs.existsSync(startupDir(W5)) || fs.readdirSync(startupDir(W5)).length === 0, "no startup shortcut");
		const ps5 = procs(pipe5);
		check(ps5.length === 1 && path.resolve(ps5[0].exe || "") === alias, "one process on the pipe, and it is the Store app");
		await ask(pipe5, "quit", null, 1500);
		await sleep(3000);
	} finally {
		for (const p of [pipe, pipe + "-ps1", pipe + "-msix"]) procs(p);
		await sleep(1000);
		for (const pid of mine) if (pid !== process.pid && alive(pid)) { try { process.kill(pid); console.log("stopped leftover pid " + pid); } catch (e) {} }
		const lg = read(log, "utf8");
		if (lg) console.log("---- desk-pals.log (last lines)\n" + lg.trim().split("\n").slice(-15).join("\n"));
		// 台詞 key 對不起來、圖讀不到：都算失敗（log 是這個測試自己的 TEMP，只有這次的）
		const bad = (lg || "").split("\n").filter((l) => /missing line|art missing|lineups\.txt missing|autostart: (?!new |\S+ -> )/.test(l));
		check(!bad.length, "desk-pals.log has no missing lines / missing art / autostart errors" + (bad.length ? "\n       " + bad.slice(0, 8).join("\n       ") : ""));
	}
	console.log(problems ? `ext-exe: ${problems} problem(s)` : "ext-exe: all ok");
	process.exit(problems ? 1 : 0);
}

if (process.argv[2] === "--session") session(process.argv[3]).catch((e) => { console.log(JSON.stringify({ error: String(e && e.stack || e) })); process.exit(1); });
else main().catch((e) => { console.error(e); process.exit(1); });
