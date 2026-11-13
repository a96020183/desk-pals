// Spidey 小夥伴：側邊欄像素寵物 ＋ 整台電腦都跑得到的桌面版
const vscode = require("vscode");
const fs = require("fs");
const os = require("os");
const net = require("net");
const cp = require("child_process");
const path = require("path");

function activate(context) {
	// ---- 狀態列上一直都在的小蜘蛛 ----
	const bar = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 1000);
	bar.command = "spideyPet.show";
	bar.tooltip = "Spidey 小夥伴（點我叫他出來）";
	const IDLE = ["🕷 ", "🕷 ·", "🕷 ··", "🕷 ···", "🕸 ···", "🕸 ··", "🕸 ·", "🕷 "];
	let idleIdx = 0, flashUntil = 0;
	const flash = (text, ms = 3500) => { bar.text = text; flashUntil = Date.now() + ms; };
	const barTick = setInterval(() => {
		if (Date.now() < flashUntil) return;
		bar.text = IDLE[idleIdx++ % IDLE.length];
	}, 700);
	bar.text = IDLE[0];
	bar.show();
	context.subscriptions.push(bar, { dispose: () => clearInterval(barTick) });

	const desktop = new Desktop(context);
	context.subscriptions.push(desktop);

	const provider = new SpideyView(context);
	const origPost = provider.post.bind(provider);
	provider.post = (msg) => {
		const dark = isDarkTime(new Date());
		if (msg.type === "save") flash(dark ? "🕷 存了就快走。" : "🕷👍 存好了！");
		else if (msg.type === "errors" && msg.count > msg.prev) flash(`🕷❗ 蜘蛛感應：${msg.count} 個錯誤`, 5000);
		else if (msg.type === "errors" && msg.count === 0) flash(dark ? "🕷 錯誤清完了，下班吧" : "🕷✨ 錯誤清光了！");
		else if (msg.type === "idle") flash("🕷💤", 1e12);
		else if (msg.type === "wake") flash("🕷 你回來啦！", 2500);
		else if (msg.type === "rest") flash("🕷🥤 起來喝水伸展一下！", 15000);
		else if (msg.type === "hi") flash("🕷👋 嗨！", 2500);
		origPost(msg);
		desktop.forward(msg);
	};
	context.subscriptions.push(
		vscode.window.registerWebviewViewProvider("spideyPet.view", provider, {
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
			vscode.window.showInformationMessage("🕷 Spidey：已經連續寫很久了，起來喝口水、伸展一下吧！");
		}
	};
	const tick = setInterval(() => {
		const cfg = vscode.workspace.getConfiguration("spideyPet");
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
		vscode.commands.registerCommand("spideyPet.show", () => vscode.commands.executeCommand("spideyPet.view.focus")),
		vscode.commands.registerCommand("spideyPet.hi", () => provider.post({ type: "hi" })),
		vscode.commands.registerCommand("spideyPet.restNow", remindRest),
		vscode.commands.registerCommand("spideyPet.desktopOn", async () => {
			await vscode.workspace.getConfiguration("spideyPet").update("desktop", true, vscode.ConfigurationTarget.Global);
			desktop.start(true);
		}),
		vscode.commands.registerCommand("spideyPet.desktopOff", async () => {
			const pick = await vscode.window.showWarningMessage(
				"要收工嗎？桌面上的 Spidey 會離開，也不會再開機自動出現（之後可用「Spidey：放他到整個螢幕」叫回來）。",
				{ modal: true },
				"收工"
			);
			if (pick !== "收工") return;
			await vscode.workspace.getConfiguration("spideyPet").update("desktop", false, vscode.ConfigurationTarget.Global);
			desktop.stop();
		}),
		vscode.commands.registerCommand("spideyPet.hug", () => desktop.send("act hug")),
		vscode.commands.registerCommand("spideyPet.knock", () => desktop.send("act knock")),
		vscode.commands.registerCommand("spideyPet.ball", () => desktop.send("act ball")),
		vscode.commands.registerCommand("spideyPet.hide", () => desktop.send("act hide")),
		vscode.commands.registerCommand("spideyPet.bond", () => desktop.send("act bond")),
		vscode.workspace.onDidChangeConfiguration((e) => {
			if (e.affectsConfiguration("spideyPet.restMinutes") || e.affectsConfiguration("spideyPet.idleMinutes") || e.affectsConfiguration("spideyPet.birthday")) desktop.sendConfig();
		})
	);

	// 終端機 git push tag 成功 → 放煙火（需要 VS Code 的 shell integration）
	if (vscode.window.onDidEndTerminalShellExecution) {
		context.subscriptions.push(
			vscode.window.onDidEndTerminalShellExecution((e) => {
				const cmd = (e.execution && e.execution.commandLine && e.execution.commandLine.value) || "";
				if (e.exitCode !== 0 || !/\bgit\b[^\n|;&]*\bpush\b/.test(cmd)) return;
				const m = /(\d+\.\d+\.\d+(?:-[A-Za-z]+\.\d+)?)/.exec(cmd);
				if (!/--tags|--follow-tags|refs\/tags\//.test(cmd) && !m) return;
				const env = /Production/i.test(cmd) ? "prod" : /Development/i.test(cmd) ? "dev" : "other";
				desktop.send(`tag ${m ? m[1] : "tag"} ${env}`);
			})
		);
	}

	if (vscode.workspace.getConfiguration("spideyPet").get("desktop", true)) desktop.start(false);
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
// Windows：%LOCALAPPDATA%\SpideyDesktop ＋「啟動」資料夾捷徑，named pipe 溝通
// macOS：~/Library/Application Support/SpideyDesktop ＋ LaunchAgent，unix socket 溝通
class Desktop {
	constructor(context) {
		this.context = context;
		this.sock = null;
		this.want = false;
		this.spawns = 0;
		const user = (os.userInfo().username || "me").replace(/[^A-Za-z0-9_.-]/g, "_");
		this.name = "spidey-pet-" + user;
		this.supported = process.platform === "win32" || process.platform === "darwin";
		this.home = process.platform === "win32"
			? path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local"), "SpideyDesktop")
			: path.join(os.homedir(), "Library", "Application Support", "SpideyDesktop");
		// macOS 的 socket 放固定位置（開機由 launchd 啟動時 TMPDIR 不一定相同）
		this.endpoint = process.platform === "win32" ? "\\\\.\\pipe\\" + this.name : path.join(this.home, "spidey.sock");
	}
	connected() { return !!this.sock; }

	start(userAsked) {
		if (!this.supported) {
			if (userAsked) vscode.window.showInformationMessage("Spidey 桌面版目前支援 Windows 和 macOS。");
			return;
		}
		try { this.install(); } catch (e) { console.error("spidey install", e); }
		this.want = true;
		this.spawns = 0;
		this.connect(60, false);
		if (userAsked) this.sendLater("act hi");
	}

	stop() {
		this.want = false;
		this.send("quit");
		try { this.uninstallAutostart(); } catch (e) { console.error("spidey uninstall", e); }
	}

	send(line) { if (this.sock) this.sock.write(line + "\n"); }
	sendLater(line) { this.pending = line; }
	sendConfig() {
		const cfg = vscode.workspace.getConfiguration("spideyPet");
		this.send(`config ${cfg.get("restMinutes", 50)} ${cfg.get("idleMinutes", 5)}`);
		const bd = String(cfg.get("birthday", "") || "").trim();
		this.send(`birthday ${/^\d{2}-\d{2}$/.test(bd) ? bd : ""}`);
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
				const log = process.platform === "win32" ? "%TEMP%\\spidey-desktop.log" : "~/Library/Logs/spidey-desktop.log";
				vscode.window.showWarningMessage(`Spidey 桌面版沒有啟動成功，詳情見 ${log}`);
			}
		});
	}

	// 把桌面版複製到固定位置（擴充套件更新後路徑會變，開機啟動要指向固定的地方）
	install() {
		const src = path.join(this.context.extensionPath, "desktop");
		fs.mkdirSync(this.home, { recursive: true });
		const files = process.platform === "win32"
			? ["SpideyDesktop.cs", "spidey-desktop.ps1", "claude-hook.js"]
			: ["SpideyDesktop.swift", "spidey-desktop.sh", "claude-hook.js"];
		for (const f of files) {
			const from = path.join(src, f), to = path.join(this.home, f);
			const a = fs.readFileSync(from);
			let same = false;
			try { same = Buffer.compare(a, fs.readFileSync(to)) === 0; } catch (e) {}
			if (!same) fs.writeFileSync(to, a);
		}
		if (process.platform === "darwin") fs.chmodSync(path.join(this.home, "spidey-desktop.sh"), 0o755);
		this.installAutostart();
	}

	installAutostart() {
		if (process.platform === "win32") {
			const startup = path.join(process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming"), "Microsoft", "Windows", "Start Menu", "Programs", "Startup");
			const lnk = path.join(startup, "Spidey 小夥伴.lnk");
			if (fs.existsSync(lnk)) return;
			const ps1 = path.join(this.home, "spidey-desktop.ps1");
			const script = [
				"$s = (New-Object -ComObject WScript.Shell).CreateShortcut($env:SPIDEY_LNK)",
				"$s.TargetPath = \"$env:SystemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\"",
				"$s.Arguments = '-NoProfile -WindowStyle Hidden -File \"' + $env:SPIDEY_PS1 + '\" -PipeName ' + $env:SPIDEY_NAME",
				"$s.WindowStyle = 7",
				"$s.Description = 'Spidey 小夥伴（整個螢幕的像素小蜘蛛人）'",
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
			const lnk = path.join(process.env.APPDATA || "", "Microsoft", "Windows", "Start Menu", "Programs", "Startup", "Spidey 小夥伴.lnk");
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
				const args = `-NoProfile -WindowStyle Hidden -File "${path.join(this.home, "spidey-desktop.ps1")}" -PipeName ${this.name}`;
				p = cp.spawn("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList $env:SPIDEY_ARGS"],
					{ stdio: "ignore", windowsHide: true, env: Object.assign({}, process.env, { SPIDEY_ARGS: args }) });
			} else {
				p = cp.spawn("/bin/bash", [path.join(this.home, "spidey-desktop.sh"), this.name], { detached: true, stdio: "ignore" });
			}
			p.on("error", () => {});
			p.unref();
		} catch (e) {
			console.error("spidey spawn", e);
		}
	}

	dispose() { if (this.sock) this.sock.end(); }
}

class SpideyView {
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
			.replace(/\{\{csp\}\}/g, view.webview.cspSource);
		view.onDidDispose(() => {
			if (this.view === view) this.view = undefined;
		});
	}
}

function deactivate() {}

module.exports = { activate, deactivate };
