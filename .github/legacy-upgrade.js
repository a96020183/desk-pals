// CI：舊版「Spidey 小夥伴」→ 公仔櫃 的升級接手（個人版才有這段）。全部在臨時資料夾裡做，不碰真的安裝。
// 用法：node .github/legacy-upgrade.js upgrade|fresh <新版 endpoint> <舊資料夾> <開機啟動資料夾> <資料夾> <舊版 pipe（Windows）或 -> -- <開新版的指令…>
//   upgrade：擺一份假的舊安裝（舊資料夾、程式檔、感情等級、claude-hook.js、開機啟動項），假裝舊的還開著（舊的 pipe／socket），
//            再開新版（帶 DESKPALS_LEGACY_DIR／DESKPALS_AUTOSTART_DIR／DESKPALS_LEGACY_PIPE），檢查：
//            舊的收到 quit、舊的開機啟動項和程式檔拿掉了、感情等級搬過來（原檔還在）、維持經典一櫃、
//            舊位置的 claude-hook.js 換成轉發的小檔而且真的轉得過去、最後叫新版收工
//   fresh：沒有舊資料夾 → 新版開起來之後也不會建出舊資料夾、開機啟動資料夾裡什麼都沒有
const cp = require("child_process");
const fs = require("fs");
const net = require("net");
const path = require("path");

const argv = process.argv.slice(2);
const dash = argv.indexOf("--");
const [mode, ep0, legacy, autostart, data, oldPipe] = argv.slice(0, dash);
const cmd = argv.slice(dash + 1);
const win = process.platform === "win32";
const pipe = (n) => (win && !n.startsWith("\\\\") ? "\\\\.\\pipe\\" + n : n);
const ep = pipe(ep0);
let problems = 0;
const check = (ok, what) => { console.log((ok ? "ok   " : "FAIL ") + what); if (!ok) problems++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const exists = (f) => { try { fs.lstatSync(f); return true; } catch (e) { return false; } };
const read = (f) => { try { return fs.readFileSync(f, "utf8"); } catch (e) { return null; } };

const progFiles = win ? ["SpideyDesktop.cs", "spidey-desktop.ps1", "ci-watch.js"]
	: ["SpideyDesktop.swift", "SpideyDesktop", "spidey-desktop.sh", "DeskPals.swift", "DeskPals", "desk-pals.sh", "ci-watch.js", "standalone.json"];
const agent = path.join(autostart, win ? "Spidey 小夥伴.lnk" : "local.spidey-pet.plist");
const oldEp = win ? pipe(oldPipe) : path.join(legacy, "spidey.sock");

// 收一行（或幾行）的小伺服器：舊版的 pipe／socket、轉發測試用的「新版」
function listen(where, onLine) {
	const srv = net.createServer((s) => {
		let b = "";
		s.setEncoding("utf8");
		s.on("data", (d) => {
			b += d;
			let i;
			while ((i = b.indexOf("\n")) >= 0) { onLine(b.slice(0, i).trim()); b = b.slice(i + 1); }
		});
		s.on("error", () => {});
	});
	return new Promise((resolve, reject) => { srv.on("error", reject); srv.listen(where, () => resolve(srv)); });
}

// hello → 新版回「lineup <櫃>」
function hello(timeoutMs) {
	return new Promise((resolve) => {
		const end = Date.now() + timeoutMs;
		(function attempt() {
			const s = net.connect(ep);
			let b = "";
			s.setEncoding("utf8");
			s.on("connect", () => s.write("hello\n"));
			s.on("data", (d) => {
				b += d;
				const m = /lineup (\w+)/.exec(b);
				if (m) { s.end(); resolve(m[1]); }
			});
			s.on("error", () => { if (Date.now() > end) resolve(null); else setTimeout(attempt, 500); });
		})();
	});
}

function sendLine(where, line) {
	return new Promise((resolve) => {
		const s = net.connect(where);
		s.on("connect", () => s.end(line + "\n", resolve));
		s.on("error", () => resolve());
	});
}

(async () => {
	for (const d of [autostart, data]) fs.mkdirSync(d, { recursive: true });
	let gotQuit = false, oldSrv = null;
	if (mode === "upgrade") {
		fs.mkdirSync(legacy, { recursive: true });
		for (const f of progFiles) fs.writeFileSync(path.join(legacy, f), "old program\n");
		fs.writeFileSync(path.join(legacy, "claude-hook.js"), "// old hook\nprocess.exit(3);\n");
		fs.writeFileSync(path.join(legacy, "bond.txt"), "321 2026-11-01");
		fs.writeFileSync(path.join(legacy, "pats.txt"), "2026-11-01 4");
		fs.writeFileSync(agent, "old autostart\n");
		// VS Code 擴充套件／安裝程式會把 claude-hook.js 放在新的資料夾
		fs.copyFileSync(path.join(__dirname, "..", "extension", "desktop", "claude-hook.js"), path.join(data, "claude-hook.js"));
		oldSrv = await listen(oldEp, (l) => { if (l === "quit") gotQuit = true; });
		console.log("fake old app listening on", oldEp);
	} else if (exists(legacy)) {
		console.log("FAIL fresh: legacy folder already exists", legacy);
		process.exit(1);
	}

	const env = Object.assign({}, process.env, {
		DESKPALS_OFFSCREEN: "1", DESKPALS_ISOLATED: "1", DESKPALS_DATA_DIR: data,
		DESKPALS_LEGACY_DIR: legacy, DESKPALS_AUTOSTART_DIR: autostart,
	});
	if (win && oldPipe && oldPipe !== "-") env.DESKPALS_LEGACY_PIPE = oldPipe;
	const logFile = path.join(path.dirname(data), path.basename(data) + "-run.log");
	const out = fs.openSync(logFile, "w");
	const child = cp.spawn(cmd[0], cmd.slice(1), { env, stdio: ["ignore", out, out], windowsHide: true });
	let exited = false;
	child.on("exit", (c) => { exited = true; console.log("new app exited", c); });

	const lineup = await hello(90000);
	check(lineup !== null, "new app answers on " + ep + (lineup ? " (lineup " + lineup + ")" : ""));
	if (mode === "upgrade") {
		const end = Date.now() + 15000;
		while (!gotQuit && Date.now() < end) await sleep(200);
		await sleep(1000);
		check(gotQuit, "old app got quit on " + oldEp);
		check(!exists(agent), "old autostart removed: " + path.basename(agent));
		for (const f of progFiles) check(!exists(path.join(legacy, f)), "old program file removed: " + f);
		if (!win) check(!exists(oldEp), "old socket removed");
		check(read(path.join(data, "bond-spidey.txt")) === "321 2026-11-01", "bond.txt copied to bond-spidey.txt");
		check(read(path.join(data, "pats-spidey.txt")) === "2026-11-01 4", "pats.txt copied to pats-spidey.txt");
		check(read(path.join(legacy, "bond.txt")) === "321 2026-11-01", "old bond.txt kept (copy, not move)");
		check(lineup === "classic", "upgraded user stays in the classic lineup");
		const stub = read(path.join(legacy, "claude-hook.js")) || "";
		check(stub.includes("require(") && stub.includes(JSON.stringify(path.join(data, "claude-hook.js")).slice(1, -1)), "old claude-hook.js is a stub pointing at the new one");
		// 轉發真的通：舊位置的 hook → 新位置的 hook → DESKPALS_ENDPOINT
		const hookEp = win ? pipe("desk-pals-hooktest-" + process.pid) : path.join(path.dirname(data), "hooktest-" + process.pid + ".sock");
		let got = "";
		const hookSrv = await listen(hookEp, (l) => { got = got || l; });
		const r = cp.spawnSync(process.execPath, [path.join(legacy, "claude-hook.js"), "start"], {
			input: JSON.stringify({ session_id: "legacy-test" }), env: Object.assign({}, process.env, { DESKPALS_ENDPOINT: hookEp }), timeout: 10000,
		});
		await sleep(300);
		check(r.status === 0, "stub exits 0 (status " + r.status + ")");
		check(got === "claude start legacy-test", "stub forwards to the new hook (got: " + JSON.stringify(got) + ")");
		hookSrv.close();
		// 新的資料夾、開機啟動資料夾裡不能多出舊名字的東西（bond-spidey.txt／pats-spidey.txt 是 Spidey 這隻角色的存檔，不算）
		const odd = fs.readdirSync(data).filter((f) => /spidey/i.test(f) && !/^(bond|pats)-spidey\.txt$/.test(f));
		check(odd.length === 0, "no legacy-named files in the data folder " + JSON.stringify(odd));
	} else {
		check(!exists(legacy), "fresh install: legacy folder not created");
		const left = fs.readdirSync(autostart);
		check(left.length === 0, "fresh install: nothing in the autostart folder " + JSON.stringify(left));
		const odd = fs.readdirSync(data).filter((f) => /spidey/i.test(f));
		check(odd.length === 0, "fresh install: no legacy-named files in the data folder " + JSON.stringify(odd));
	}

	await sendLine(ep, "quit");
	const end = Date.now() + 15000;
	while (!exited && Date.now() < end) await sleep(200);
	check(exited, "new app quit");
	if (!exited) try { child.kill(); } catch (e) {}
	if (oldSrv) oldSrv.close();
	if (problems) { console.log("---- " + logFile); console.log(read(logFile) || ""); }
	console.log(problems ? problems + " problem(s)" : "legacy upgrade test OK");
	process.exit(problems ? 1 : 0);
})().catch((e) => { console.log("FAIL", e); process.exit(1); });
