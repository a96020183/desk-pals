// 公仔櫃 Desk Pals：右下角一個公仔櫃（Spidey／小波／史迪仔／人魚漢頓），選一隻出來在整個螢幕陪你
// Windows：多角色桌面版（DeskPals.cs）；macOS：只有 Spidey（SpideyDesktop.swift）
const vscode = require("vscode");
const fs = require("fs");
const os = require("os");
const net = require("net");
const cp = require("child_process");
const path = require("path");

// 各角色在狀態列／通知用的圖示和名字
const CHARS = {
	spidey: { emoji: "🕷", name: "Spidey" },
	po: { emoji: "🛴", name: "小波" },
	stitch: { emoji: "👽", name: "史迪仔" },
	hangyodon: { emoji: "🐟", name: "人魚漢頓" },
};
let current = "spidey";
const E = () => (CHARS[current] || CHARS.spidey).emoji;
const N = () => (CHARS[current] || CHARS.spidey).name;

function activate(context) {
	current = process.platform === "darwin" ? "spidey"
		: context.globalState.get("activeChar") || vscode.workspace.getConfiguration("deskPals").get("character", "spidey");
	// ---- 狀態列上一直都在的小蜘蛛 ----
	const bar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 1000);
	bar.command = "deskPals.show";
	bar.tooltip = "公仔櫃（點我叫他出來）";
	const IDLE = ["", " ·", " ··", " ···", " ··", " ·"];
	let idleIdx = 0, flashUntil = 0, focusEnd = 0, quietEnd = 0;
	const flash = (text, ms = 3500) => { bar.text = text; flashUntil = Date.now() + ms; };
	const barTick = setInterval(() => {
		if (Date.now() < flashUntil) return;
		if (quietEnd > Date.now()) { bar.text = `${E()} 💤 ${Math.ceil((quietEnd - Date.now()) / 60000)} 分`; return; }
		if (focusEnd > Date.now()) { bar.text = `${E()} 🍅 ${Math.ceil((focusEnd - Date.now()) / 60000)} 分`; return; }
		bar.text = E() + IDLE[idleIdx++ % IDLE.length];
	}, 700);
	bar.text = E();
	bar.show();
	context.subscriptions.push(bar, { dispose: () => clearInterval(barTick) });

	const desktop = new Desktop(context);
	desktop.onFocus = (on, mins) => { focusEnd = on ? Date.now() + mins * 60000 : 0; };
	desktop.onQuiet = (on, mins) => { quietEnd = on ? Date.now() + mins * 60000 : 0; };
	// 桌面版換角色 → 狀態列、側邊欄跟著換
	desktop.onActive = (id) => {
		if (!CHARS[id] || id === current) return;
		current = id;
		context.globalState.update("activeChar", id);
		provider.post({ type: "character", id });
		flash(`${E()} ${N()} 出來陪你囉！`, 3000);
	};
	context.subscriptions.push(desktop);

	const provider = new PetView(context);
	const origPost = provider.post.bind(provider);
	provider.post = (msg) => {
		const dark = isDarkTime(new Date());
		const e = E();
		if (msg.type === "save") flash(dark ? `${e} 存了就快走。` : `${e}👍 存好了！`);
		else if (msg.type === "errors" && msg.count > msg.prev) flash(current === "spidey" ? `${e}❗ 蜘蛛感應：${msg.count} 個錯誤` : current === "hangyodon" ? `${e}❗ 交給我這個英雄！${msg.count} 個錯誤` : `${e}❗ 有 ${msg.count} 個錯誤`, 5000);
		else if (msg.type === "errors" && msg.count === 0) flash(dark ? `${e} 錯誤清完了，下班吧` : `${e}✨ 錯誤清光了！`);
		else if (msg.type === "idle") flash(`${e}💤`, 1e12);
		else if (msg.type === "wake") flash(`${e} 你回來啦！`, 2500);
		else if (msg.type === "rest") flash(`${e}🥤 起來喝口可樂、伸展一下！`, 15000);
		else if (msg.type === "hi") flash(`${e}👋 嗨！`, 2500);
		origPost(msg);
		desktop.forward(msg);
	};
	context.subscriptions.push(
		vscode.window.registerWebviewViewProvider("deskPals.view", provider, {
			webviewOptions: { retainContextWhenHidden: true },
		})
	);

	// ---- 存檔 → 比讚 ----
	let lastSave = 0;
	context.subscriptions.push(
		vscode.workspace.onDidSaveTextDocument(() => {
			const now = Date.now();
			if (now - lastSave < 1500) return;
			lastSave = now;
			provider.post({ type: "save" });
		})
	);

	// ---- 錯誤數 → 蜘蛛感應 ----
	let prevErrors = countErrors();
	let diagTimer;
	context.subscriptions.push(
		vscode.languages.onDidChangeDiagnostics(() => {
			clearTimeout(diagTimer);
			diagTimer = setTimeout(() => {
				const n = countErrors();
				if (n !== prevErrors) provider.post({ type: "errors", count: n, prev: prevErrors });
				prevErrors = n;
			}, 900);
		})
	);

	// ---- 活動追蹤 → 睡覺 / 休息提醒（側邊欄那隻；桌面版自己看整台電腦）----
	let lastActive = Date.now();
	let sessionStart = Date.now();
	let sleeping = false;
	const touch = () => {
		const now = Date.now();
		lastActive = now;
		if (sessionStart === null) sessionStart = now;
		if (sleeping) {
			sleeping = false;
			provider.post({ type: "wake" });
		}
	};
	// 打字速度：每 5 秒把打了幾個字傳給桌面版（只算 VS Code 裡的編輯，不碰整台電腦的鍵盤）
	let typed = 0;
	const typingTick = setInterval(() => { if (typed > 0) desktop.send(`typing ${typed}`); typed = 0; }, 5000);
	context.subscriptions.push({ dispose: () => clearInterval(typingTick) });
	context.subscriptions.push(
		vscode.workspace.onDidChangeTextDocument((e) => {
			if (e.document.uri.scheme === "file" || e.document.uri.scheme === "untitled") {
				touch();
				for (const c of e.contentChanges) if (c.text.length > 0 && c.text.length <= 3) typed += c.text.length; // 貼上大段不算
			}
		}),
		vscode.window.onDidChangeTextEditorSelection(touch),
		vscode.window.onDidChangeActiveTextEditor(touch)
	);

	const remindRest = () => {
		provider.post({ type: "rest" });
		// 桌面版開著的話由它提醒（看整台電腦），這裡不再跳通知
		if (!provider.visible() && !desktop.connected()) {
			vscode.window.showInformationMessage(`${E()} ${N()}：已經連續寫很久了，起來喝口可樂、伸展一下吧！🥤`);
		}
	};
	const tick = setInterval(() => {
		const cfg = vscode.workspace.getConfiguration("deskPals");
		const restMs = Math.max(1, cfg.get("restMinutes", 50)) * 60000;
		const idleMs = Math.max(1, cfg.get("idleMinutes", 5)) * 60000;
		const now = Date.now();
		if (now - lastActive > idleMs) {
			sessionStart = null;
			if (!sleeping) {
				sleeping = true;
				provider.post({ type: "idle" });
			}
		} else if (sessionStart !== null && now - sessionStart >= restMs) {
			sessionStart = now;
			remindRest();
		}
	}, 30000);
	context.subscriptions.push({ dispose: () => clearInterval(tick) });

	context.subscriptions.push(
		vscode.commands.registerCommand("deskPals.show", () => vscode.commands.executeCommand("deskPals.view.focus")),
		vscode.commands.registerCommand("deskPals.hi", () => provider.post({ type: "hi" })),
		vscode.commands.registerCommand("deskPals.restNow", remindRest),
		vscode.commands.registerCommand("deskPals.desktopOn", async () => {
			await vscode.workspace.getConfiguration("deskPals").update("desktop", true, vscode.ConfigurationTarget.Global);
			desktop.start(true);
		}),
		vscode.commands.registerCommand("deskPals.desktopOff", async () => {
			const pick = await vscode.window.showWarningMessage(
				"要收工嗎？桌面上的公仔和公仔櫃會離開，也不會再開機自動出現（之後可用「公仔櫃：放他到整個螢幕」叫回來）。",
				{ modal: true },
				"收工"
			);
			if (pick !== "收工") return;
			await vscode.workspace.getConfiguration("deskPals").update("desktop", false, vscode.ConfigurationTarget.Global);
			desktop.stop();
		}),
		vscode.commands.registerCommand("deskPals.hug", () => desktop.send("act hug")),
		vscode.commands.registerCommand("deskPals.knock", () => desktop.send("act knock")),
		vscode.commands.registerCommand("deskPals.ball", () => desktop.send("act ball")),
		vscode.commands.registerCommand("deskPals.hide", () => desktop.send("act hide")),
		vscode.commands.registerCommand("deskPals.bond", () => desktop.send("act bond")),
		vscode.commands.registerCommand("deskPals.pick", () => pickCharacter(context, desktop, provider, false)),
		vscode.commands.registerCommand("deskPals.all", () => desktop.send("act all")),
		vscode.commands.registerCommand("deskPals.home", () => desktop.send("act home")),
		vscode.commands.registerCommand("deskPals.focus", () => desktop.send(`act focus ${Math.max(1, vscode.workspace.getConfiguration("deskPals").get("focusMinutes", 25))}`)),
		vscode.commands.registerCommand("deskPals.focusStop", () => desktop.send("act focusstop")),
		vscode.commands.registerCommand("deskPals.quiet30", () => desktop.send("act quiet 30")),
		vscode.commands.registerCommand("deskPals.quiet120", () => desktop.send("act quiet 120")),
		vscode.commands.registerCommand("deskPals.quietOff", () => desktop.send("act quiet 0")),
		vscode.workspace.onDidChangeConfiguration((e) => {
			if (e.affectsConfiguration("deskPals.restMinutes") || e.affectsConfiguration("deskPals.idleMinutes") || e.affectsConfiguration("deskPals.birthday") || e.affectsConfiguration("deskPals.companyHost")) desktop.sendConfig();
		})
	);

	// 實用功能：終端機長指令、推 tag 盯 CI、開會提醒、Jira 新單、工作日誌
	require("./practical").setup(context, desktop);

	if (vscode.workspace.getConfiguration("deskPals").get("desktop", true)) desktop.start(false);

	// 第一次安裝：挑你的第一個公仔（從舊版 Spidey 升級的人直接沿用 Spidey）
	if (process.platform === "win32" && !context.globalState.get("picked")) {
		if (desktop.migratedFromSpidey) context.globalState.update("picked", true);
		else setTimeout(() => pickCharacter(context, desktop, provider, true), 2500);
	}
}

async function pickCharacter(context, desktop, provider, first) {
	if (process.platform !== "win32") {
		vscode.window.showInformationMessage("Mac 版目前只有 Spidey。");
		return;
	}
	const items = Object.keys(CHARS).map((id) => ({
		label: `${CHARS[id].emoji} ${CHARS[id].name}`,
		description: id === current ? "現在出來的是他" : "",
		id,
	}));
	const pick = await vscode.window.showQuickPick(items, {
		title: first ? "公仔櫃：挑你的第一個公仔（之後點右下角的公仔櫃就能換）" : "公仔櫃：換誰出來？",
		placeHolder: "選一隻",
	});
	if (first) context.globalState.update("picked", true);
	if (!pick) return;
	await vscode.workspace.getConfiguration("deskPals").update("character", pick.id, vscode.ConfigurationTarget.Global);
	if (desktop.connected()) desktop.send(`act select ${pick.id}`);
	else desktop.sendLater(`act select ${pick.id}`);
	desktop.onActive(pick.id);
}

function countErrors() {
	let n = 0;
	for (const [, diags] of vscode.languages.getDiagnostics()) {
		for (const d of diags) if (d.severity === vscode.DiagnosticSeverity.Error) n++;
	}
	return n;
}

// 平日 18:00 之後到隔天 06:00 黑化（跟桌面版同一條規則）
function isDarkTime(n) {
	const wd = (d) => d >= 1 && d <= 5;
	if (n.getHours() >= 18) return wd(n.getDay());
	if (n.getHours() < 6) return wd((n.getDay() + 6) % 7);
	return false;
}

// ================= 桌面版（整台電腦）=================
// Windows：%LOCALAPPDATA%\DeskPals ＋「啟動」資料夾捷徑，named pipe 溝通（多角色＋公仔櫃）
// macOS：~/Library/Application Support/SpideyDesktop ＋ LaunchAgent，unix socket 溝通（只有 Spidey）
class Desktop {
	constructor(context) {
		this.context = context;
		this.sock = null;
		this.want = false;
		this.spawns = 0;
		const user = (os.userInfo().username || "me").replace(/[^A-Za-z0-9_.-]/g, "_");
		this.win = process.platform === "win32";
		this.user = user;
		this.name = (this.win ? "desk-pals-" : "spidey-pet-") + user;
		this.supported = this.win || process.platform === "darwin";
		const local = process.env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local");
		this.oldHome = path.join(local, "SpideyDesktop"); // 舊版 Spidey 小夥伴（Windows）
		this.migratedFromSpidey = this.win && fs.existsSync(this.oldHome);
		this.home = this.win
			? path.join(local, "DeskPals")
			: path.join(os.homedir(), "Library", "Application Support", "SpideyDesktop");
		this.ps1 = "desk-pals.ps1";
		this.lnkName = "公仔櫃 Desk Pals.lnk";
		this.onActive = () => {};
		this.onFocus = () => {};
		this.onQuiet = () => {};
		// macOS 的 socket 放固定位置（開機由 launchd 啟動時 TMPDIR 不一定相同）
		this.endpoint = process.platform === "win32" ? "\\\\.\\pipe\\" + this.name : path.join(this.home, "spidey.sock");
	}
	connected() { return !!this.sock; }

	start(userAsked) {
		if (!this.supported) {
			if (userAsked) vscode.window.showInformationMessage("公仔櫃桌面版目前支援 Windows 和 macOS。");
			return;
		}
		try { this.install(); } catch (e) { console.error("deskpals install", e); }
		this.want = true;
		this.spawns = 0;
		this.connect(60, false);
		if (userAsked) this.sendLater("act hi");
	}

	stop() {
		this.want = false;
		this.send("quit");
		try { this.uninstallAutostart(); } catch (e) { console.error("deskpals uninstall", e); }
	}

	send(line) { if (this.sock) this.sock.write(line + "\n"); }
	sendLater(line) { this.pending = line; }
	sendConfig() {
		const cfg = vscode.workspace.getConfiguration("deskPals");
		this.send(`config ${cfg.get("restMinutes", 50)} ${cfg.get("idleMinutes", 5)}`);
		const bd = String(cfg.get("birthday", "") || "").trim();
		this.send(`birthday ${/^\d{2}-\d{2}$/.test(bd) ? bd : ""}`);
		const host = String(cfg.get("companyHost", "") || "").trim();
		if (/^[\w.-]+$/.test(host)) this.send(`config-host ${host}`);
	}

	forward(msg) {
		if (msg.type === "save") this.send("save");
		else if (msg.type === "errors") this.send(`errors ${msg.count} ${msg.prev}`);
		else if (msg.type === "hi") this.send("act hi");
		// idle / wake / rest：桌面版自己看整台電腦的鍵盤滑鼠，不轉送
	}

	connect(left, spawned) {
		if (!this.want || this.sock) return;
		const s = net.connect(this.endpoint);
		let ok = false, buf = "";
		s.setEncoding("utf8");
		s.on("connect", () => {
			ok = true;
			this.sock = s;
			s.write("hello\n");
			this.sendConfig();
			if (this.pending) { this.send(this.pending); this.pending = null; }
		});
		s.on("data", (d) => {
			buf += d;
			let i;
			while ((i = buf.indexOf("\n")) >= 0) {
				const line = buf.slice(0, i).trim();
				buf = buf.slice(i + 1);
				if (line === "bye") this.want = false; // 使用者從桌面右鍵「收工」
				const m = /^active (\w+)$/.exec(line);
				if (m) this.onActive(m[1]);
				const f = /^focus (on|off)(?: (\d+))?$/.exec(line);
				if (f) this.onFocus(f[1] === "on", +(f[2] || 0));
				const q = /^quiet (on|off)(?: (\d+))?$/.exec(line);
				if (q) this.onQuiet(q[1] === "on", +(q[2] || 0));
			}
		});
		s.on("error", () => {});
		s.on("close", () => {
			if (ok) {
				if (this.sock === s) this.sock = null;
				if (this.want) setTimeout(() => this.connect(60, false), 1500);
				return;
			}
			if (!spawned) {
				if (this.spawns >= 3) { this.want = false; return; }
				this.spawns++;
				this.spawn();
				spawned = true;
			}
			if (left > 0) setTimeout(() => this.connect(left - 1, spawned), 500);
			else {
				this.want = false;
				const log = this.win ? "%TEMP%\\desk-pals.log" : "~/Library/Logs/spidey-desktop.log";
				vscode.window.showWarningMessage(`公仔櫃桌面版沒有啟動成功，詳情見 ${log}`);
			}
		});
	}

	// 把桌面版複製到固定位置（擴充套件更新後路徑會變，開機啟動要指向固定的地方）
	install() {
		const src = path.join(this.context.extensionPath, "desktop");
		fs.mkdirSync(this.home, { recursive: true });
		const files = this.win
			? ["DeskPals.cs", "desk-pals.ps1", "claude-hook.js", "ci-watch.js"]
			: ["SpideyDesktop.swift", "spidey-desktop.sh", "claude-hook.js", "ci-watch.js"];
		const copy = (f, dir) => {
			const from = path.join(src, f), to = path.join(dir, f);
			const a = fs.readFileSync(from);
			let same = false;
			try { same = Buffer.compare(a, fs.readFileSync(to)) === 0; } catch (e) {}
			if (!same) fs.writeFileSync(to, a);
		};
		for (const f of files) copy(f, this.home);
		if (this.migratedFromSpidey) this.migrateFromSpidey(copy);
		if (process.platform === "darwin") fs.chmodSync(path.join(this.home, "spidey-desktop.sh"), 0o755);
		this.installAutostart();
	}

	installAutostart() {
		if (process.platform === "win32") {
			const startup = path.join(process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming"), "Microsoft", "Windows", "Start Menu", "Programs", "Startup");
			const lnk = path.join(startup, this.lnkName);
			if (fs.existsSync(lnk)) return;
			const ps1 = path.join(this.home, this.ps1);
			const script = [
				"$s = (New-Object -ComObject WScript.Shell).CreateShortcut($env:SPIDEY_LNK)",
				"$s.TargetPath = \"$env:SystemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\"",
				"$s.Arguments = '-NoProfile -WindowStyle Hidden -File \"' + $env:SPIDEY_PS1 + '\" -PipeName ' + $env:SPIDEY_NAME",
				"$s.WindowStyle = 7",
				"$s.Description = '公仔櫃 Desk Pals（整個螢幕的像素公仔）'",
				"$s.Save()",
			].join("; ");
			cp.execFile("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script], {
				windowsHide: true,
				env: Object.assign({}, process.env, { SPIDEY_LNK: lnk, SPIDEY_PS1: ps1, SPIDEY_NAME: this.name }),
			}, () => {});
		} else if (process.platform === "darwin") {
			const dir = path.join(os.homedir(), "Library", "LaunchAgents");
			const plist = path.join(dir, "local.spidey-pet.plist");
			if (fs.existsSync(plist)) return;
			fs.mkdirSync(dir, { recursive: true });
			fs.writeFileSync(plist, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.spidey-pet</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>${path.join(this.home, "spidey-desktop.sh")}</string><string>${this.name}</string></array>
  <key>RunAtLoad</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
`);
		}
	}

	uninstallAutostart() {
		if (process.platform === "win32") {
			const lnk = path.join(process.env.APPDATA || "", "Microsoft", "Windows", "Start Menu", "Programs", "Startup", this.lnkName);
			if (fs.existsSync(lnk)) fs.unlinkSync(lnk);
		} else if (process.platform === "darwin") {
			const plist = path.join(os.homedir(), "Library", "LaunchAgents", "local.spidey-pet.plist");
			if (fs.existsSync(plist)) fs.unlinkSync(plist);
		}
	}

	spawn() {
		try {
			let p;
			if (process.platform === "win32") {
				// detached 的 powershell 沒有主控台會直接結束；改由短命的 powershell 用 Start-Process 叫一支獨立的起來
				const pet = vscode.workspace.getConfiguration("deskPals").get("character", "spidey");
				const args = `-NoProfile -WindowStyle Hidden -File "${path.join(this.home, this.ps1)}" -PipeName ${this.name} -Pet ${CHARS[pet] ? pet : "spidey"}`;
				p = cp.spawn("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList $env:SPIDEY_ARGS"],
					{ stdio: "ignore", windowsHide: true, env: Object.assign({}, process.env, { SPIDEY_ARGS: args }) });
			} else {
				p = cp.spawn("/bin/bash", [path.join(this.home, "spidey-desktop.sh"), this.name], { detached: true, stdio: "ignore" });
			}
			p.on("error", () => {});
			p.unref();
		} catch (e) {
			console.error("deskpals spawn", e);
		}
	}

	// 舊版 Spidey 小夥伴 → 公仔櫃：關掉舊的桌面版、拿掉舊的開機捷徑；
	// 舊位置的 claude-hook.js 也換新（你 settings.json 的 hooks 指著那裡，新版會改送到公仔櫃）
	migrateFromSpidey(copy) {
		const oldLnk = path.join(process.env.APPDATA || "", "Microsoft", "Windows", "Start Menu", "Programs", "Startup", "Spidey 小夥伴.lnk");
		try { if (fs.existsSync(oldLnk)) fs.unlinkSync(oldLnk); } catch (e) {}
		try { copy("claude-hook.js", this.oldHome); copy("ci-watch.js", this.oldHome); } catch (e) {}
		try {
			const s = net.connect("\\\\.\\pipe\\spidey-pet-" + this.user);
			s.on("connect", () => s.end("quit\n"));
			s.on("error", () => {});
		} catch (e) {}
	}

	dispose() { if (this.sock) this.sock.end(); }
}

class PetView {
	constructor(context) {
		this.context = context;
		this.view = undefined;
	}
	visible() {
		return !!(this.view && this.view.visible);
	}
	post(msg) {
		if (this.view) this.view.webview.postMessage(msg);
	}
	resolveWebviewView(view) {
		this.view = view;
		view.webview.options = { enableScripts: true };
		const nonce = Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
		const htmlPath = path.join(this.context.extensionPath, "media", "pet.html");
		view.webview.html = fs
			.readFileSync(htmlPath, "utf8")
			.replace(/\{\{nonce\}\}/g, nonce)
			.replace(/\{\{csp\}\}/g, view.webview.cspSource)
			.replace(/\{\{character\}\}/g, current);
		setTimeout(() => this.post({ type: "character", id: current }), 300);
		view.onDidDispose(() => {
			if (this.view === view) this.view = undefined;
		});
	}
}

function deactivate() {}

module.exports = { activate, deactivate };
