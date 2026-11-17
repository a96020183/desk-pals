// 公仔櫃 Desk Pals：右下角一個公仔櫃，選一隻出來在整個螢幕陪你
// 兩櫃：經典（Spidey／小波／史迪仔／人魚漢頓）、天線寶寶（丁丁／迪西／拉拉／小波，大格是小波）
// Windows：多角色桌面版（DeskPals.cs）；macOS：同一套的 Swift 移植（DeskPals.swift）
const vscode = require("vscode");
const fs = require("fs");
const os = require("os");
const net = require("net");
const cp = require("child_process");
const https = require("https");
const path = require("path");

// 各角色在狀態列／通知用的圖示和名字；lineup＝在哪一櫃（小波兩櫃都有）
const CHARS = {
	spidey: { emoji: "🕷", name: "Spidey", lineup: "classic" },
	po: { emoji: "🛴", name: "小波", lineup: "both" },
	stitch: { emoji: "👽", name: "史迪仔", lineup: "classic" },
	hangyodon: { emoji: "🐟", name: "人魚漢頓", lineup: "classic" },
	tinky: { emoji: "👜", name: "丁丁", lineup: "teletubbies" },
	dipsy: { emoji: "🎩", name: "迪西", lineup: "teletubbies" },
	laalaa: { emoji: "🟠", name: "拉拉", lineup: "teletubbies" },
	pkred: { emoji: "🔥", name: "紅皮克敏", lineup: "pikmin" },
	pkyellow: { emoji: "⚡", name: "黃皮克敏", lineup: "pikmin" },
	pkblue: { emoji: "💧", name: "藍皮克敏", lineup: "pikmin" },
};
const LINEUPS = {
	classic: { name: "經典一櫃", desc: "Spidey、小波、史迪仔、人魚漢頓", ids: ["spidey", "po", "stitch", "hangyodon"] },
	teletubbies: { name: "天線寶寶一櫃", desc: "丁丁、迪西、拉拉、小波（大格是小波）", ids: ["tinky", "dipsy", "laalaa", "po"] },
	pikmin: { name: "皮克敏一櫃", desc: "紅、黃、藍皮克敏（大格是休息花）", ids: ["pkred", "pkyellow", "pkblue"] },
};
const lineupSetting = () => { const v = vscode.workspace.getConfiguration("deskPals").get("lineup", "classic"); return LINEUPS[v] ? v : "classic"; };
const inLineup = (id, lu) => !!CHARS[id] && (CHARS[id].lineup === "both" || CHARS[id].lineup === lu);
let current = "spidey";
let flowerPct = null;   // 皮克敏一櫃：休息花（0 開好開滿 → 100 枯了）
const flowerMark = () => (flowerPct === null || !CHARS[current] || CHARS[current].lineup !== "pikmin" ? "" : (flowerPct >= 100 ? "🥀" : (flowerPct >= 60 ? "🌼" : "🌸")));
const E = () => (CHARS[current] || CHARS.spidey).emoji;
const N = () => (CHARS[current] || CHARS.spidey).name;

function activate(context) {
	current = context.globalState.get("activeChar") || vscode.workspace.getConfiguration("deskPals").get("character", "spidey");
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
		bar.text = E() + flowerMark() + IDLE[idleIdx++ % IDLE.length];
	}, 700);
	bar.text = E();
	bar.show();
	context.subscriptions.push(bar, { dispose: () => clearInterval(barTick) });

	const desktop = new Desktop(context);
	desktop.onFocus = (on, mins) => { focusEnd = on ? Date.now() + mins * 60000 : 0; };
	desktop.onQuiet = (on, mins) => { quietEnd = on ? Date.now() + mins * 60000 : 0; };
	desktop.onFlower = (pct) => { flowerPct = pct; provider.post({ type: "flower", pct }); };
	// 桌面版換櫃（小屋「換一櫃」、設定視窗）→ VS Code 的設定跟著改（不再回送給桌面版）
	desktop.onLineup = (lu) => {
		if (!LINEUPS[lu] || lu === lineupSetting()) return;
		desktop.skipLineup = lu;
		vscode.workspace.getConfiguration("deskPals").update("lineup", lu, vscode.ConfigurationTarget.Global);
	};
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
		else if (msg.type === "errors" && msg.count > msg.prev) flash(current === "spidey" ? `${e}❗ 蜘蛛感應：${msg.count} 個錯誤` : current === "hangyodon" ? `${e}❗ 交給我這個英雄！${msg.count} 個錯誤` : current === "tinky" ? `${e}❗ 哎喲！${msg.count} 個錯誤` : `${e}❗ 有 ${msg.count} 個錯誤`, 5000);
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
		vscode.commands.registerCommand("deskPals.aiSetup", () => configureAiKey(context)),
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
		vscode.commands.registerCommand("deskPals.lineup", () => pickLineup(desktop)),
		vscode.commands.registerCommand("deskPals.all", () => desktop.send("act all")),
		vscode.commands.registerCommand("deskPals.home", () => desktop.send("act home")),
		vscode.commands.registerCommand("deskPals.focus", () => desktop.send(`act focus ${Math.max(1, vscode.workspace.getConfiguration("deskPals").get("focusMinutes", 25))}`)),
		vscode.commands.registerCommand("deskPals.focusStop", () => desktop.send("act focusstop")),
		vscode.commands.registerCommand("deskPals.quiet30", () => desktop.send("act quiet 30")),
		vscode.commands.registerCommand("deskPals.quiet120", () => desktop.send("act quiet 120")),
		vscode.commands.registerCommand("deskPals.quietOff", () => desktop.send("act quiet 0")),
		vscode.workspace.onDidChangeConfiguration((e) => {
			if (e.affectsConfiguration("deskPals.restMinutes") || e.affectsConfiguration("deskPals.idleMinutes") || e.affectsConfiguration("deskPals.birthday") || e.affectsConfiguration("deskPals.companyHost")) desktop.sendConfig();
			// 換一櫃（設定頁直接改也算）：桌面版當場換，不用重開
			if (e.affectsConfiguration("deskPals.lineup")) {
				const lu = lineupSetting();
				if (desktop.skipLineup === lu) { desktop.skipLineup = null; return; }
				desktop.setLineup(lu);
				flash(`${E()} 換成${LINEUPS[lu].name}囉！`, 3000);
			}
		})
	);

	// 實用功能：終端機長指令、推 tag 盯 CI、開會提醒、Jira 新單、工作日誌
	require("./practical").setup(context, desktop);

	// 第一次設定（你是？選一櫃、擺法）現在由桌面版自己的設定視窗做；這裡只負責把它開起來
	if (vscode.workspace.getConfiguration("deskPals").get("desktop", true)) desktop.start(false);
}

// 挑公仔：兩櫃的公仔都列出來；挑到另一櫃的公仔就順便換櫃（小波兩櫃都有，選現在這一櫃的小波就不換）
async function pickCharacter(context, desktop, provider, first) {
	const now = lineupSetting();
	const items = [];
	for (const lu of [now, ...Object.keys(LINEUPS).filter((x) => x !== now)]) {
		items.push({ label: `${LINEUPS[lu].name}${lu === now ? "（現在這一櫃）" : ""}`, kind: vscode.QuickPickItemKind.Separator });
		for (const id of LINEUPS[lu].ids) {
			items.push({
				label: `${CHARS[id].emoji} ${CHARS[id].name}`,
				description: lu === now && id === current ? "現在出來的是他" : (lu !== now ? `換成${LINEUPS[lu].name}` : ""),
				id, lineup: lu,
			});
		}
	}
	const pick = await vscode.window.showQuickPick(items, {
		title: first ? "公仔櫃：挑你的第一個公仔（之後點右下角的公仔櫃就能換）" : "公仔櫃：換誰出來？",
		placeHolder: "選一隻（選天線寶寶就會換成天線寶寶一櫃）",
	});
	if (first) context.globalState.update("picked", true);
	if (!pick || !pick.id) return;
	const cfg = vscode.workspace.getConfiguration("deskPals");
	await cfg.update("character", pick.id, vscode.ConfigurationTarget.Global);
	if (pick.lineup !== now) {
		// 換櫃＋指定這隻出來：一行告訴桌面版（設定改變的通知就不要再送一次）
		desktop.skipLineup = pick.lineup;
		await cfg.update("lineup", pick.lineup, vscode.ConfigurationTarget.Global);
		desktop.setLineup(pick.lineup, pick.id);
	} else if (desktop.connected()) desktop.send(`act select ${pick.id}`);
	else desktop.sendLater(`act select ${pick.id}`);
	desktop.onActive(pick.id);
}

// 換一櫃：經典／天線寶寶
async function pickLineup(desktop) {
	const now = lineupSetting();
	const items = Object.keys(LINEUPS).map((lu) => ({
		label: `${lu === "classic" ? "🕷" : (lu === "pikmin" ? "🌸" : "☀")} ${LINEUPS[lu].name}`,
		description: LINEUPS[lu].desc,
		detail: lu === now ? "現在是這一櫃" : undefined,
		lineup: lu,
	}));
	const pick = await vscode.window.showQuickPick(items, { title: "公仔櫃：換一櫃", placeHolder: "選一櫃" });
	if (!pick || pick.lineup === now) return;
	await vscode.workspace.getConfiguration("deskPals").update("lineup", pick.lineup, vscode.ConfigurationTarget.Global);   // 設定改變 → 送 lineup 給桌面版
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
// macOS：~/Library/Application Support/SpideyDesktop ＋ LaunchAgent，unix socket 溝通（同一套公仔櫃；資料夾沿用舊版 Spidey 的，hooks 設定不用改）
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
		this.home = this.win
			? path.join(local, "DeskPals")
			: path.join(os.homedir(), "Library", "Application Support", "SpideyDesktop");
		// 舊版只有 Spidey 的 Mac 桌面版（SpideyDesktop.swift）→ 換成公仔櫃
		this.macOldSpidey = process.platform === "darwin" && fs.existsSync(path.join(this.home, "SpideyDesktop.swift"));
		this.migratedFromSpidey = (this.win && fs.existsSync(this.oldHome)) || this.macOldSpidey;
		this.exe = "DeskPals.exe";
		this.sh = "desk-pals.sh";
		this.lnkName = "公仔櫃 Desk Pals.lnk";
		this.onActive = () => {};
		this.onLineup = () => {};
		this.skipLineup = null;
		this.lineupAck = null;
		this.restartedOnce = false;
		this.restarting = false;
		this.onFocus = () => {};
		this.onQuiet = () => {};
		this.onFlower = () => {};
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
	// 換櫃（可指定哪隻出來）。桌面版會回「lineup <櫃>」；沒回＝還在跑更新前的舊版程式，
	// 要天線寶寶一櫃時就重開一次桌面版，載入新版（每次啟動 VS Code 最多一次）
	setLineup(lu, pet) {
		const line = pet ? `lineup ${lu} ${pet}` : `lineup ${lu}`;
		if (!this.connected()) { this.sendLater(line); return; }
		this.lineupAck = null;
		this.send(line);
		if (lu === "classic" || this.restartedOnce) return;
		setTimeout(() => {
			if (this.connected() && this.lineupAck !== lu && !this.restartedOnce) {
				this.restartedOnce = true; this.restarting = true;
				this.send("quit");   // 關掉後 connect() 會自動重開（帶 -Lineup）
			}
		}, 3000);
	}
	sendLater(line) { this.pending = line; }
	sendConfig() {
		const cfg = vscode.workspace.getConfiguration("deskPals");
		// 櫃子以桌面版為準：連上時桌面版會回「lineup <櫃>」，設定跟著它（VS Code 這邊改設定才送 lineup 過去）
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
				if (line === "bye") { if (this.restarting) this.restarting = false; else this.want = false; } // 使用者從桌面右鍵「收工」（換櫃重開不算）
				const lu = /^lineup (\w+)$/.exec(line);
				if (lu) { this.lineupAck = lu[1]; this.onLineup(lu[1]); }
				const m = /^active (\w+)$/.exec(line);
				if (m) this.onActive(m[1]);
				const fl = /^flower (\d+)$/.exec(line);
				if (fl) this.onFlower(+fl[1]);
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
			? [this.exe, "claude-hook.js", "ci-watch.js"]
			: ["DeskPals.swift", this.sh, "claude-hook.js", "ci-watch.js"];
		const copy = (f, dir) => {
			const from = path.join(src, f), to = path.join(dir, f);
			const a = fs.readFileSync(from);
			let same = false;
			try { same = Buffer.compare(a, fs.readFileSync(to)) === 0; } catch (e) {}
			if (!same) fs.writeFileSync(to, a);
		};
		for (const f of files) copy(f, this.home);
		if (this.win && this.migratedFromSpidey) this.migrateFromSpidey(copy);
		if (process.platform === "darwin") {
			fs.chmodSync(path.join(this.home, this.sh), 0o755);
			if (this.macOldSpidey) this.migrateMacSpidey();
		}
		this.installAutostart();
	}

	installAutostart() {
		if (process.platform === "win32") {
			const startup = path.join(process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming"), "Microsoft", "Windows", "Start Menu", "Programs", "Startup");
			const lnk = path.join(startup, this.lnkName);
			const exe = path.join(this.home, this.exe);
			const script = [
				"$w = New-Object -ComObject WScript.Shell",
				"if (Test-Path -LiteralPath $env:SPIDEY_LNK) { $old = $w.CreateShortcut($env:SPIDEY_LNK); $owned = ($old.TargetPath -match '(?i)powershell\\.exe$' -and $old.Arguments -match '(?i)desk-pals\\.ps1'); if (-not $owned -and $old.TargetPath -ne $env:SPIDEY_EXE) { exit 0 } }",
				"$s = $w.CreateShortcut($env:SPIDEY_LNK)",
				"$s.TargetPath = $env:SPIDEY_EXE",
				"$s.Arguments = $env:SPIDEY_NAME",
				"$s.WindowStyle = 7",
				"$s.Description = '公仔櫃 Desk Pals（整個螢幕的像素公仔）'",
				"$s.Save()",
			].join("; ");
			cp.execFile("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script], {
				windowsHide: true,
				env: Object.assign({}, process.env, { SPIDEY_LNK: lnk, SPIDEY_EXE: exe, SPIDEY_NAME: this.name }),
			}, () => {});
		} else if (process.platform === "darwin") {
			const dir = path.join(os.homedir(), "Library", "LaunchAgents");
			const plist = path.join(dir, "local.spidey-pet.plist");
			const want = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.spidey-pet</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>${path.join(this.home, this.sh)}</string><string>${this.name}</string></array>
  <key>RunAtLoad</key><true/>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
`;
			let have = "";
			try { have = fs.readFileSync(plist, "utf8"); } catch (e) {}
			if (have === want) return;
			fs.mkdirSync(dir, { recursive: true });
			fs.writeFileSync(plist, want);
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
				const lu = lineupSetting();
				const pet = vscode.workspace.getConfiguration("deskPals").get("character", "spidey");
				p = cp.spawn(path.join(this.home, this.exe), [this.name, inLineup(pet, lu) ? pet : (lu === "teletubbies" ? "po" : (lu === "pikmin" ? "pkred" : "spidey")), lu],
					{ detached: true, stdio: "ignore", windowsHide: true });
			} else {
				const lu = lineupSetting();
				const pet = vscode.workspace.getConfiguration("deskPals").get("character", "spidey");
				p = cp.spawn("/bin/bash", [path.join(this.home, this.sh), this.name, inLineup(pet, lu) ? pet : (lu === "teletubbies" ? "po" : (lu === "pikmin" ? "pkred" : "spidey")), lu], { detached: true, stdio: "ignore" });
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

	// Mac 舊版（只有 Spidey）→ 公仔櫃：叫舊的 Spidey 收工、拿掉舊程式（同一個 socket，新版會接手）
	migrateMacSpidey() {
		this.macOldSpidey = false;
		this.restarting = true;   // 舊版收工時會送 bye，別當成使用者按了收工
		for (const f of ["SpideyDesktop.swift", "SpideyDesktop", "spidey-desktop.sh"]) {
			try { fs.unlinkSync(path.join(this.home, f)); } catch (e) {}
		}
		try {
			const s = net.connect(this.endpoint);
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
	async replyToChat(message) {
		const key = await this.context.secrets.get("deskPals.openaiApiKey");
		if (!key) {
			this.post({ type: "chatError", text: "先點「設定 AI」加入 OpenAI API 金鑰，皮克敏才能用 AI 回覆。金鑰會安全地保存在 VS Code。" });
			return;
		}
		const history = Array.isArray(message.history) ? message.history.slice(-8).filter((item) => item && (item.role === "user" || item.role === "assistant") && typeof item.content === "string").map((item) => ({ role: item.role, content: item.content.slice(0, 1200) })) : [];
		if (!history.length) return;
		try {
			const text = await requestPikminReply(key, history);
			this.post({ type: "chatReply", text });
		} catch (error) {
			const reason = error && error.message ? error.message : "未知錯誤";
			this.post({ type: "chatError", text: "我現在連不上 AI 服務，請檢查網路、API 金鑰與 API 帳務後再試。(" + reason.slice(0, 180) + ")" });
		}
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
		view.webview.onDidReceiveMessage(async (message) => {
			if (message && message.type === "setupAi") {
				await vscode.commands.executeCommand("deskPals.aiSetup");
				return;
			}
			if (message && message.type === "chat") await this.replyToChat(message);
		});
		setTimeout(() => this.post({ type: "character", id: current }), 300);
		view.onDidDispose(() => {
			if (this.view === view) this.view = undefined;
		});
	}
}

async function configureAiKey(context) {
	const action = await vscode.window.showQuickPick(["設定或更新 API 金鑰", "刪除已保存的 API 金鑰"], { title: "皮克敏 AI 設定", placeHolder: "AI 回覆會使用 OpenAI API，依你的 API 帳務計費" });
	if (!action) return;
	if (action === "刪除已保存的 API 金鑰") {
		await context.secrets.delete("deskPals.openaiApiKey");
		vscode.window.showInformationMessage("已刪除皮克敏 AI 金鑰。");
		return;
	}
	const key = await vscode.window.showInputBox({ password: true, ignoreFocusOut: true, title: "輸入 OpenAI API 金鑰", prompt: "金鑰只會存進 VS Code SecretStorage，不會寫入設定檔或聊天記錄。", placeHolder: "sk-…" , validateInput: value => value && !value.startsWith("sk-") ? "請輸入有效格式的 OpenAI API 金鑰（sk-…）" : null });
	if (!key) return;
	await context.secrets.store("deskPals.openaiApiKey", key.trim());
	vscode.window.showInformationMessage("皮克敏 AI 已設定完成。");
}

function requestPikminReply(apiKey, history) {
	const payload = JSON.stringify({
		model: "gpt-4.1-mini",
		instructions: "你是陪伴大學生的皮克敏夥伴，請用繁體中文、溫柔真誠又不說教的語氣回應。先理解對方的感受，再給一個小而實際的下一步。不要假裝是心理師或醫療專業人員；遇到危險或嚴重困擾時，鼓勵對方找可信任的人或專業協助。回答精簡，通常不超過 120 字。",
		input: history,
		max_output_tokens: 240
	});
	return new Promise((resolve, reject) => {
		const req = https.request({
			hostname: "api.openai.com", path: "/v1/responses", method: "POST",
			headers: { Authorization: "Bearer " + apiKey, "Content-Type": "application/json", "Content-Length": Buffer.byteLength(payload) },
		}, (res) => {
			let body = "";
			res.setEncoding("utf8");
			res.on("data", (chunk) => { body += chunk; });
			res.on("end", () => {
				let data;
				try { data = JSON.parse(body); } catch (e) { reject(new Error("AI 回傳格式無法讀取")); return; }
				if (res.statusCode < 200 || res.statusCode >= 300) {
					const detail = data.error && data.error.message ? data.error.message : "HTTP " + res.statusCode;
					reject(new Error(detail)); return;
				}
				const answer = (data.output || []).flatMap((item) => item.content || []).filter((item) => item.type === "output_text").map((item) => item.text || "").join("\n").trim();
				if (!answer) { reject(new Error("AI 沒有產生文字回覆")); return; }
				resolve(answer.slice(0, 2000));
			});
		});
		req.setTimeout(45000, () => req.destroy(new Error("AI 連線逾時")));
		req.on("error", reject);
		req.write(payload); req.end();
	});
}

function deactivate() {}

module.exports = { activate, deactivate };
