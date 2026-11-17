// 公仔櫃 Desk Pals：右下角一個公仔櫃，選一隻出來在整個螢幕陪你
// 幾櫃：續命小隊（原創：躲躲／沒電／刺刺，新安裝的預設）、經典、天線寶寶、皮克敏
// Windows：多角色桌面版（DeskPals.cs）；macOS：同一套的 Swift 移植（DeskPals.swift）
const vscode = require("vscode");
const fs = require("fs");
const os = require("os");
const net = require("net");
const cp = require("child_process");
const path = require("path");

// 各角色在狀態列／通知用的圖示和名字；lineup＝在哪一櫃（小波兩櫃都有）
const CHARS = {
	// <fan>
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
	// </fan>
	duoduo: { emoji: "📦", name: "躲躲", lineup: "original", squad: true },
	meidian: { emoji: "🔋", name: "沒電", lineup: "original", squad: true },
	cici: { emoji: "🌵", name: "刺刺", lineup: "original", squad: true },
	fanfan: { emoji: "📖", name: "翻翻", lineup: "woban", squad: true, dir: "woban" },
	bobo: { emoji: "💧", name: "破破", lineup: "woban", squad: true, dir: "woban" },
	mian: { emoji: "☁", name: "綿綿", lineup: "woban", squad: true, dir: "woban" },
};
// 舊的像素版續命小隊（半糖、醒醒、糰糰、貼貼）→ 新三隻（設定裡存的舊 id 照這個換；桌面版也同一套）
const OLD_IDS = { boba: "duoduo", coffee: "meidian", onigiri: "cici", sticky: "duoduo" };
const charSetting = (def) => { const v = vscode.workspace.getConfiguration("deskPals").get("character", def); return OLD_IDS[v] || v; };
// 側邊欄畫續命小隊用的幾句台詞（桌面版的完整台詞在 DeskPals.Original.cs）
const SQUAD_LINES = {
	duoduo: { save: ["存好了…（小聲）", "存起來了，跟我躲在箱子裡一樣安全"], save_d: ["存了，晚安（關箱子）"], pats: ["！！（整個縮進去）", "……再一下", "被摸了…紙箱都暖起來了"], pats_d: ["摸完我就要關箱子了"],
		tickle: ["嘻嘻嘻不要戳箱子", "（箱子在抖）"], hi: ["嗨…我是躲躲，平常住在箱子裡"], hi_d: ["嗨…天黑了，箱子要關了"], errors: ["有 {n} 個錯誤…我先躲一下"], errors_d: ["{n} 個錯誤…明天再說好不好"],
		errors_ok: ["錯誤不見了！我也可以出來了"], errors_ok_d: ["修好了…可以下班了"], rest: ["{n} 分鐘了…起來走走？我幫你看著位子（躲好）"], rest_d: ["{n} 分鐘了…回家吧"],
		wake: ["……（偷看）你回來了"], wake_d: ["……還沒下班嗎"], sleep: ["我先躲進去睡…"], night_on: ["天黑了…箱子要關門囉"], night_off: ["早…早安（打開箱子）☀"], x_sig: ["我不在我不在我不在"] },
	meidian: { save: ["存好了…省了一點電", "存檔完成…可以待機了嗎"], save_d: ["存好了，關機吧"], pats: ["被摸了…充了 1%", "嗯…這個是無線充電嗎", "你也很累吧"], pats_d: ["摸完就關機喔"],
		tickle: ["別戳！電會漏出來", "哈哈…這樣很耗電欸"], hi: ["嗨…我是沒電。很累，但還在"], hi_d: ["嗨…我快關機了"], errors: ["{n} 個錯誤…我電量掉了 {n}%（不是）"], errors_d: ["{n} 個錯誤…明天充飽電再修"],
		errors_ok: ["錯誤清光了！…好，我可以待機了"], errors_ok_d: ["修好了…關機吧"], rest: ["{n} 分鐘了…我們都沒電了，起來動一動"], rest_d: ["{n} 分鐘…下班充電吧"],
		wake: ["開機中……（轉圈圈）"], wake_d: ["……還要工作嗎"], sleep: ["待機中…"], night_on: ["下班時間…我要關機了"], night_off: ["早安…充電充到一半就被叫醒 ☀"], x_sig: ["插上了……嗯……這就是天堂"] },
	cici: { save: ["存好了。不用謝", "存了啦，看什麼"], save_d: ["存好了，快回家"], pats: ["摸、摸什麼摸…（花苞抖）", "再一下下而已喔", "我沒有很開心，是花苞自己動的"], pats_d: ["摸完就回家"],
		tickle: ["不准搔我癢！", "再戳我就炸毛了！"], hi: ["我是刺刺。不用跟我好（小聲：你好）"], hi_d: ["嗨…這麼晚了"], errors: ["{n} 個錯誤？…又不是我寫的"], errors_d: ["{n} 個錯誤…明天再修，回家"],
		errors_ok: ["修好了。…還算可以啦"], errors_ok_d: ["修好了…快回家"], rest: ["{n} 分鐘了，起來動。不是我關心你，是椅子很累"], rest_d: ["{n} 分鐘了…回家。現在。"],
		wake: ["我沒睡。只是閉目養神"], wake_d: ["…還不下班？"], sleep: ["我閉目養神一下"], night_on: ["下班了。…回家路上小心（小聲）"], night_off: ["早。…今天也要好好的 ☀"], x_sig: ["這、這是花粉過敏！"] },
	// 窩伴小世界（桌面版的完整台詞在 DeskPals.Woban.cs）
	fanfan: { save: ["存好了，進度都在 ✓", "存檔完成～又往前一步"], save_d: ["存好了，今天就到這裡吧"], pats: ["嘿嘿，被摸頭了", "謝謝你～我會繼續陪你", "這樣很安心"], pats_d: ["晚安摸摸，收到了"],
		tickle: ["哈哈，好癢", "不要翻我的頁啦～"], hi: ["嗨，我是翻翻。我們一起慢慢前進吧"], hi_d: ["嗨…晚上了，今天也辛苦了"], errors: ["有 {n} 個錯誤，我們一個一個來"], errors_d: ["{n} 個錯誤…明天精神好再看"],
		errors_ok: ["錯誤都清掉了！這是個小進步 ✨"], errors_ok_d: ["修好了，可以安心休息了"], rest: ["{n} 分鐘了，休息一下，大腦才記得住"], rest_d: ["{n} 分鐘了，今天就到這裡吧"],
		wake: ["（揉眼睛）你回來了，我們繼續吧"], wake_d: ["嗯…還在忙嗎？"], sleep: ["我先閉上眼睛…"], night_on: ["下班時間到了，把書籤夾好吧"], night_off: ["早安！今天想先完成哪一件？☀"], x_sig: ["完成一件了！撒花 ✨"] },
	bobo: { save: ["存好了，放心", "幫你存起來了～"], save_d: ["存好了，收工吧"], pats: ["嘿嘿，謝謝你", "被摸摸了，好開心", "你今天辛苦了"], pats_d: ["晚安摸摸"],
		tickle: ["哈哈哈好癢", "不要啦～"], hi: ["嗨，我是破破。喝水、吃飯，交給我提醒"], hi_d: ["嗨…晚上了，吃飯了嗎"], errors: ["有 {n} 個錯誤，先喝口水再慢慢看"], errors_d: ["{n} 個錯誤…明天再看吧"],
		errors_ok: ["錯誤都不見了！來，喝口水慶祝"], errors_ok_d: ["修好了，可以休息了"], rest: ["{n} 分鐘了，起來走走，順便裝杯水"], rest_d: ["{n} 分鐘了，休息吧"],
		wake: ["你回來了！先喝口水"], wake_d: ["嗯…還要忙嗎？"], sleep: ["我先睡一下…"], night_on: ["下班時間到了，記得吃晚餐"], night_off: ["早安！先喝一杯溫水吧 ☀"], x_sig: ["來，喝口水 💧"] },
	mian: { save: ["存好了，可以放心", "存起來了～鬆一口氣"], save_d: ["存好了，該休息了"], pats: ["（軟軟地陷下去）", "好舒服～", "被摸了，心情變好了"], pats_d: ["晚安摸摸"],
		tickle: ["呼呼，好癢", "不要啦～會軟掉"], hi: ["嗨，我是綿綿。累了就來找我"], hi_d: ["嗨…晚上了，放鬆一下"], errors: ["有 {n} 個錯誤，先深呼吸，不急"], errors_d: ["{n} 個錯誤…明天再看吧"],
		errors_ok: ["錯誤都不見了，鬆一口氣～"], errors_ok_d: ["修好了，好好休息"], rest: ["{n} 分鐘了，休息一下吧～我蓋好毯子陪你"], rest_d: ["{n} 分鐘了，今天就到這裡吧"],
		wake: ["嗯…你回來了，休息得好嗎"], wake_d: ["嗯…還不睡嗎"], sleep: ["我先睡一下…"], night_on: ["下班時間到了，讓自己慢下來"], night_off: ["早安～今天也慢慢來 ☀"], x_sig: ["捧著熱可可，放空一下下 ☕"] },
};
const LINEUPS = {
	original: { name: "續命小隊", desc: "躲躲、沒電、刺刺（原創角色，大格是躲躲）", ids: ["duoduo", "meidian", "cici"] },
	woban: { name: "窩伴小世界", desc: "翻翻、破破、綿綿（原創角色，住在書包小屋）", ids: ["fanfan", "bobo", "mian"] },
	// <fan>
	classic: { name: "經典一櫃", desc: "Spidey、小波、史迪仔、人魚漢頓", ids: ["spidey", "po", "stitch", "hangyodon"] },
	teletubbies: { name: "天線寶寶一櫃", desc: "丁丁、迪西、拉拉、小波（大格是小波）", ids: ["tinky", "dipsy", "laalaa", "po"] },
	pikmin: { name: "皮克敏一櫃", desc: "紅、黃、藍皮克敏（大格是休息花）", ids: ["pkred", "pkyellow", "pkblue"] },
	// </fan>
};
// 自己做的公仔（桌面版用 pals 告訴我們有誰）：狀態列圖示、名字、側邊欄小圖；有的話多一櫃「我的櫃」
let customPals = [];
function applyCustomPals(list, mine) {
	for (const id of Object.keys(CHARS)) if (CHARS[id].custom) delete CHARS[id];
	customPals = Array.isArray(list) ? list.filter((p) => p && /^cu[a-z0-9]{2,12}$/.test(p.id)) : [];
	for (const p of customPals) CHARS[p.id] = { emoji: p.emoji || "🧸", name: String(p.name || "小公仔").slice(0, 10), lineup: "mine", custom: true, img: p.img || "", lines: p.lines || {} };
	const ids = (Array.isArray(mine) ? mine : []).filter((id) => CHARS[id]);
	if (customPals.length && ids.length) LINEUPS.mine = { name: "我的櫃", desc: ids.map((id) => CHARS[id].name).join("、"), ids };
	else delete LINEUPS.mine;
}
const lineupSetting = () => { const v = vscode.workspace.getConfiguration("deskPals").get("lineup", "original"); return LINEUPS[v] ? v : "classic"; };   //@fan
// <public> const lineupSetting = () => { const v = vscode.workspace.getConfiguration("deskPals").get("lineup", "original"); return LINEUPS[v] ? v : "original"; };
// 使用者真的設過「哪一櫃」嗎？沒設過＝讓桌面版自己決定（照它上次的；全新安裝才是續命小隊），舊使用者不會因為預設值改了被換櫃
const lineupExplicit = () => { const i = vscode.workspace.getConfiguration("deskPals").inspect("lineup"); return !!i && (i.globalValue !== undefined || i.workspaceValue !== undefined || i.workspaceFolderValue !== undefined); };
const lineupDefaultPet = (lu) => (lu === "mine" && LINEUPS.mine ? LINEUPS.mine.ids[0] : lu === "teletubbies" ? "po" : (lu === "pikmin" ? "pkred" : (lu === "original" ? "duoduo" : (lu === "woban" ? "fanfan" : "spidey"))));   //@fan
// <public> const lineupDefaultPet = (lu) => (lu === "mine" && LINEUPS.mine ? LINEUPS.mine.ids[0] : (lu === "woban" ? "fanfan" : "duoduo"));
const inLineup = (id, lu) => !!CHARS[id] && (CHARS[id].lineup === "both" || CHARS[id].lineup === lu);
let current = "spidey";   //@fan
// <public> let current = "duoduo";
let flowerPct = null;   // 皮克敏一櫃：休息花（0 開好開滿 → 100 枯了）
const flowerMark = () => (flowerPct === null || !CHARS[current] || CHARS[current].lineup !== "pikmin" ? "" : (flowerPct >= 100 ? "🥀" : (flowerPct >= 60 ? "🌼" : "🌸")));   //@fan
// <public> const flowerMark = () => "";
const E = () => (CHARS[current] || CHARS.spidey).emoji;   //@fan
// <public> const E = () => (CHARS[current] || CHARS.duoduo).emoji;
const N = () => (CHARS[current] || CHARS.spidey).name;   //@fan
// <public> const N = () => (CHARS[current] || CHARS.duoduo).name;

function activate(context) {
	const savedPals = context.globalState.get("customPals");
	if (savedPals) applyCustomPals(savedPals.pals, savedPals.mine);
	current = context.globalState.get("activeChar") || charSetting("spidey");   //@fan
	// <public> current = context.globalState.get("activeChar") || charSetting("duoduo");
	if (OLD_IDS[current]) current = OLD_IDS[current];   // 舊的像素版續命小隊
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
	// 桌面版說自己做的公仔有誰（新做、改、刪、匯入）→ 記起來、側邊欄更新
	desktop.onPals = (d) => {
		applyCustomPals(d.pals, d.mine);
		context.globalState.update("customPals", { pals: customPals.map((p) => ({ id: p.id, name: p.name, emoji: p.emoji, img: p.img, lines: p.lines })), mine: d.mine || [] });
		if (CHARS[current] && CHARS[current].custom) provider.post({ type: "character", id: current });
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
		else if (msg.type === "errors" && msg.count > msg.prev) flash(current === "spidey" ? `${e}❗ 蜘蛛感應：${msg.count} 個錯誤` : current === "hangyodon" ? `${e}❗ 交給我這個英雄！${msg.count} 個錯誤` : current === "tinky" ? `${e}❗ 哎喲！${msg.count} 個錯誤` : `${e}❗ 有 ${msg.count} 個錯誤`, 5000);   //@fan
		// <public> else if (msg.type === "errors" && msg.count > msg.prev) flash(`${e}❗ 有 ${msg.count} 個錯誤`, 5000);
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
				desktop.standalone()
					? `要收工嗎？桌面上的公仔和公仔櫃會離開（之後可用「公仔櫃：放他到整個螢幕」叫回來）。獨立版自己的開機自動啟動不受影響，要關請到${process.platform === "darwin" ? "「系統設定 → 一般 → 登入項目」" : " Windows「設定 → 應用程式 → 啟動」"}。`
					: "要收工嗎？桌面上的公仔和公仔櫃會離開，也不會再開機自動出現（之後可用「公仔櫃：放他到整個螢幕」叫回來）。",
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
		vscode.commands.registerCommand("deskPals.make", () => { if (desktop.connected()) desktop.send("custom new"); else { desktop.start(true); desktop.sendLater("custom new"); } }),
		vscode.commands.registerCommand("deskPals.share", () => { if (desktop.connected()) desktop.send("custom share"); else vscode.window.showInformationMessage("先打開整個螢幕版（公仔櫃：放他到整個螢幕），才能拍分享短片。"); }),
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
				if (!lineupExplicit()) return;   // 只是預設值變了（例如更新擴充套件）：不要動桌面版現在的櫃子
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
		placeHolder: "選一隻（選天線寶寶就會換成天線寶寶一櫃）",   //@fan
		// <public> placeHolder: "選一隻",
	});
	if (first) context.globalState.update("picked", true);
	if (!pick || !pick.id) return;
	const cfg = vscode.workspace.getConfiguration("deskPals");
	if (!CHARS[pick.id].custom) await cfg.update("character", pick.id, vscode.ConfigurationTarget.Global);   // 自己做的公仔不寫進設定（設定只認內建的）
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
		label: `${lu === "classic" ? "🕷" : (lu === "pikmin" ? "🌸" : (lu === "original" ? "🥤" : (lu === "woban" ? "🎒" : (lu === "mine" ? "🧸" : "☀"))))} ${LINEUPS[lu].name}`,   //@fan
		// <public> label: `${lu === "original" ? "🥤" : (lu === "woban" ? "🎒" : (lu === "mine" ? "🧸" : "☀"))} ${LINEUPS[lu].name}`,
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
// macOS：~/Library/Application Support/DeskPals ＋ LaunchAgent（local.desk-pals），unix socket（desk-pals.sock）溝通
// 舊版留下來的資料夾、socket、開機啟動項，由桌面版程式自己接手（叫舊的收工、搬資料、拿掉舊的開機啟動）
class Desktop {
	constructor(context) {
		this.context = context;
		this.sock = null;
		this.want = false;
		this.spawns = 0;
		const user = (os.userInfo().username || "me").replace(/[^A-Za-z0-9_.-]/g, "_");
		this.win = process.platform === "win32";
		this.user = user;
		// 測試用：DESKPALS_PIPE＝用別的 pipe（離屏測試不碰使用者正在跑的那一個）
		this.name = /^[A-Za-z0-9_.-]+$/.test(process.env.DESKPALS_PIPE || "") ? process.env.DESKPALS_PIPE : "desk-pals-" + user;
		this.supported = this.win || process.platform === "darwin";
		const local = process.env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local");
		this.home = this.win
			? path.join(local, "DeskPals")
			: path.join(os.homedir(), "Library", "Application Support", "DeskPals");
		this.ps1 = "desk-pals.ps1";
		// Windows 的 vsix 附了編好的 DeskPals.exe：放到 %LOCALAPPDATA%\DeskPals\app（擴充套件升級會刪掉舊版資料夾，不能從那裡跑），
		// 直接執行它（不再用隱藏的 PowerShell 即時編譯）。沒附 exe（從原始碼跑、Mac 用的通用版 vsix）才用 desk-pals.ps1。
		this.exeSrc = this.win ? path.join(context.extensionPath, "desktop", "DeskPals.exe") : "";
		this.exe = this.win ? path.join(this.home, "app", "DeskPals.exe") : "";
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
		this.onPals = () => {};
		// macOS 的 socket 放固定位置（開機由 launchd 啟動時 TMPDIR 不一定相同）
		this.endpoint = process.platform === "win32" ? "\\\\.\\pipe\\" + this.name : path.join(this.home, "desk-pals.sock");
	}
	connected() { return !!this.sock; }

	// 有裝獨立版（Windows 安裝程式／Microsoft Store、Mac 的 Desk Pals.app）嗎？有的話它寫了 standalone.json：
	// 這邊就不再自己編一份、不建開機啟動，只負責連上它（沒開就叫它起來）。檔案在、程式不在了（被刪掉）＝當作沒裝。
	// Microsoft Store 版（MSIX，檔案系統被虛擬化）寫的 standalone.json 通常只有它自己看得到：改看它的執行別名
	// %LOCALAPPDATA%\Microsoft\WindowsApps\DeskPals.exe（AppxManifest 的 AppExecutionAlias；裝了 Store 版才有）。
	standalone() {
		const exists = (target) => {
			try { fs.lstatSync(target); } catch (e) { if (e.code === "ENOENT" || e.code === "ENOTDIR") return false; }   // Store 版的 WindowsApps 捷徑 stat 會報別的錯：算在
			return true;
		};
		try {
			const j = JSON.parse(fs.readFileSync(path.join(this.home, "standalone.json"), "utf8").replace(/^\uFEFF/, ""));
			const target = this.win ? j.exe : j.app;
			if (target && exists(target)) return j;
		} catch (e) {}
		if (this.win) {
			const alias = path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), "AppData", "Local"), "Microsoft", "WindowsApps", "DeskPals.exe");
			if (exists(alias)) return { kind: "msix", exe: alias };
		}
		return null;
	}

	// 桌面那邊收工了（使用者按的、或獨立版安裝／升級時先關掉舊的）：之後獨立版又開起來就自動接回去（不會自己去開它）
	watch() {
		clearTimeout(this.watchTimer);
		this.watchTimer = setTimeout(() => {
			if (this.userStopped || this.want || this.sock) return;
			if (!this.standalone()) { this.watch(); return; }
			const s = net.connect(this.endpoint);
			s.on("connect", () => { s.destroy(); if (!this.userStopped && !this.sock) { this.want = true; this.spawns = 3; this.connect(10, true); } });
			s.on("error", () => this.watch());
		}, 10000);
	}

	start(userAsked) {
		if (!this.supported) {
			if (userAsked) vscode.window.showInformationMessage("公仔櫃桌面版目前支援 Windows 和 macOS。");
			return;
		}
		let fresh = false;
		try { fresh = this.install(); } catch (e) { console.error("deskpals install", e); }
		this.userStopped = false;
		this.want = true;
		this.spawns = 0;
		if (fresh) {
			// 剛放上新的 exe（從 PowerShell 版升級、或 exe 改版了）：--replace 請開著的舊版收工，換新的上來（資料不動）。
			// 舊版收工時會說 bye，這次不算使用者按收工
			this.replacing = true;
			clearTimeout(this.replaceTimer);
			this.replaceTimer = setTimeout(() => { this.replacing = false; }, 30000);
			this.spawns = 1;
			this.spawn(true);
			this.connect(60, true);
		} else this.connect(60, false);
		if (userAsked) this.sendLater("act hi");
	}

	stop() {
		this.want = false;
		this.userStopped = true;
		this.send("quit");
		if (this.standalone()) return;   // 獨立版的開機啟動是它自己的（安裝程式／Store／App），不動
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
		if (lu === "classic" || lu === "mine" || this.restartedOnce) return;   //@fan
		// <public> if (lu === "mine" || this.restartedOnce) return;
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
		if (this.onConfig) this.onConfig();   // 讀書小幫手（practical.js）：熬夜／考試設定、學校行事曆的作業
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
				if (line === "bye") { if (this.restarting) this.restarting = false; else if (this.replacing) this.replacing = false; else this.want = false; } // 使用者從桌面右鍵「收工」（換櫃重開、換新版 exe 不算）
				const lu = /^lineup (\w+)$/.exec(line);
				if (lu) { this.lineupAck = lu[1]; this.onLineup(lu[1]); }
				const m = /^active (\w+)$/.exec(line);
				if (m) this.onActive(m[1]);
				const pl = /^pals (\{.*\})$/.exec(line);
				if (pl) { try { this.onPals(JSON.parse(pl[1])); } catch (e) { console.error("deskpals pals", e); } }
				const fl = /^flower (\d+)$/.exec(line);
				if (fl) this.onFlower(+fl[1]);
				const f = /^focus (on|off)(?: (\d+))?$/.exec(line);
				if (f) this.onFocus(f[1] === "on", +(f[2] || 0));
				const q = /^quiet (on|off)(?: (\d+))?$/.exec(line);
				if (q) this.onQuiet(q[1] === "on", +(q[2] || 0));
				if (this.onLine) this.onLine(line);   // 其他訊息交給 practical.js（考試清單、作業標成交了）
			}
		});
		s.on("error", () => {});
		s.on("close", () => {
			if (ok) {
				if (this.sock === s) this.sock = null;
				if (this.want) setTimeout(() => this.connect(60, false), 1500);
				else this.watch();
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
				const log = this.win ? "%TEMP%\\desk-pals.log" : "~/Library/Logs/desk-pals.log";
				vscode.window.showWarningMessage(`公仔櫃桌面版沒有啟動成功，詳情見 ${log}`);
			}
		});
	}

	// 把桌面版複製到固定位置（擴充套件更新後路徑會變，開機啟動要指向固定的地方）。回傳 true＝剛換上新的 exe（要換掉開著的舊版）
	install() {
		const src = path.join(this.context.extensionPath, "desktop");
		fs.mkdirSync(this.home, { recursive: true });
		const sa = this.standalone();
		// Windows 有附 exe：只放 exe（＋hooks／CI 小腳本）；放不上去（例如被防毒軟體拿走）才退回 PowerShell 版
		let fresh = false;
		this.useExe = false;
		if (!sa && this.win && fs.existsSync(this.exeSrc)) {
			try { fresh = this.installExe(); this.useExe = true; } catch (e) { console.error("deskpals exe", e); }
		}
		// Windows（PowerShell 版）：DeskPals.cs 和所有 DeskPals.*.cs（皮克敏、自己做的公仔、分享短片…）都要帶過去
		const files = sa || this.useExe ? ["claude-hook.js", "ci-watch.js"]   // 獨立版：只放 hooks／CI 用的小腳本，桌面版本體和開機啟動都交給它
			: this.win
			? fs.readdirSync(src).filter((f) => /^DeskPals(\.[A-Za-z]+)?\.cs$/.test(f)).concat(["desk-pals.ps1", "claude-hook.js", "ci-watch.js"])
			: ["DeskPals.swift", this.sh, "claude-hook.js", "ci-watch.js"];
		const copy = (f, dir) => {
			const from = path.join(src, f), to = path.join(dir, f);
			const a = fs.readFileSync(from);
			let same = false;
			try { same = Buffer.compare(a, fs.readFileSync(to)) === 0; } catch (e) {}
			if (!same) fs.writeFileSync(to, a);
		};
		for (const f of files) copy(f, this.home);
		if (sa) return false;
		if (this.useExe) { this.installAutostart(); return fresh; }   // 圖都內嵌在 exe 裡
		// 圖（續命小隊 pals/squad、紙箱櫃 pals/shelf）：桌面版從自己旁邊的 pals 讀
		const copyDir = (rel) => {
			const from = path.join(src, rel);
			for (const e of fs.readdirSync(from, { withFileTypes: true })) {
				const r = path.join(rel, e.name);
				if (e.isDirectory()) { fs.mkdirSync(path.join(this.home, r), { recursive: true }); copyDir(r); } else copy(r, this.home);
			}
		};
		try { fs.mkdirSync(path.join(this.home, "pals"), { recursive: true }); copyDir("pals"); } catch (e) { console.error("deskpals pals", e); }
		if (process.platform === "darwin") fs.chmodSync(path.join(this.home, this.sh), 0o755);
		this.installAutostart();
		return false;
	}

	// vsix 裡的 DeskPals.exe → %LOCALAPPDATA%\DeskPals\app\DeskPals.exe。一樣就不動，回傳 false；不一樣（第一次、擴充套件升級）就換上去，回傳 true。
	// 開著的 exe 不能覆寫但可以改名：舊的先改名成 DeskPals.exe.old-…（還開著也沒關係，收工後下次再刪），新的再放上去。
	installExe() {
		const dir = path.dirname(this.exe);
		fs.mkdirSync(dir, { recursive: true });
		for (const f of fs.readdirSync(dir)) {
			const full = path.join(dir, f);
			try {
				if (/^DeskPals\.exe\.old-/.test(f) || (/^DeskPals\.exe\.new-/.test(f) && Date.now() - fs.statSync(full).mtimeMs > 60000)) fs.unlinkSync(full);
			} catch (e) {}   // 舊的還開著：下次再刪
		}
		const want = fs.readFileSync(this.exeSrc);
		let have = null;
		try { have = fs.readFileSync(this.exe); } catch (e) {}
		if (have && Buffer.compare(want, have) === 0) return false;
		const tmp = `${this.exe}.new-${process.pid}`;
		fs.writeFileSync(tmp, want);
		// 防毒軟體剛掃新檔時會鎖一下：改名失敗就等一下再試
		const retry = (fn) => {
			for (let i = 0; ; i++) {
				try { return fn(); } catch (e) {
					if (i >= 10 || !["EBUSY", "EPERM", "EACCES"].includes(e.code)) throw e;
					Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 200);
				}
			}
		};
		const old = `${this.exe}.old-${process.pid}-${Date.now()}`;
		try {
			if (have) retry(() => fs.renameSync(this.exe, old));
			retry(() => fs.renameSync(tmp, this.exe));
		} catch (e) {
			try { fs.unlinkSync(tmp); } catch (e2) {}
			if (have && !fs.existsSync(this.exe)) { try { fs.renameSync(old, this.exe); } catch (e2) {} }
			if (have && fs.existsSync(this.exe)) { console.error("deskpals exe: kept the old one", e); return false; }   // 換不掉：先用舊的，下次再換
			throw e;
		}
		return true;
	}

	installAutostart() {
		if (process.platform === "win32") {
			const startup = path.join(process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming"), "Microsoft", "Windows", "Start Menu", "Programs", "Startup");
			const lnk = path.join(startup, this.lnkName);
			if (this.useExe) {
				// exe 版：捷徑由 exe 自己建／改（舊版擴充套件留下、指著 powershell.exe 的同名捷徑也直接換成 exe）。
				// 做過就記在 app\autostart.txt，之後每次啟動不用再叫 exe
				const mark = path.join(path.dirname(this.exe), "autostart.txt");
				const key = `${lnk}|${this.name}|${this.exe}`;
				let have = "";
				try { have = fs.readFileSync(mark, "utf8"); } catch (e) {}
				if (have === key && fs.existsSync(lnk)) return;
				cp.execFile(this.exe, ["--autostart", lnk, "--pipe", this.name], { windowsHide: true, timeout: 30000 }, (err) => {
					if (err) { console.error("deskpals autostart", err); return; }
					try { fs.writeFileSync(mark, key); } catch (e) {}
				});
				return;
			}
			if (fs.existsSync(lnk)) return;
			const ps1 = path.join(this.home, this.ps1);
			const script = [
				// WScript.Shell 存檔走系統 ANSI 字碼頁：英文 Windows 存不了中文檔名 → 先存成英文暫存名，再改名
				"$d = Split-Path -LiteralPath $env:DESKPALS_LNK; New-Item -ItemType Directory -Force -Path $d | Out-Null",
				"$t = Join-Path $d ('desk-pals-' + $PID + '.lnk')",
				"$s = (New-Object -ComObject WScript.Shell).CreateShortcut($t)",
				"$s.TargetPath = \"$env:SystemRoot\\System32\\WindowsPowerShell\\v1.0\\powershell.exe\"",
				"$s.Arguments = '-NoProfile -WindowStyle Hidden -File \"' + $env:DESKPALS_PS1 + '\" -PipeName ' + $env:DESKPALS_PIPE",
				"$s.WindowStyle = 7",
				"$s.Description = '公仔櫃 Desk Pals（整個螢幕的像素公仔）'",
				"$s.Save()",
				"Move-Item -LiteralPath $t -Destination $env:DESKPALS_LNK -Force",
			].join("; ");
			cp.execFile("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script], {
				windowsHide: true,
				env: Object.assign({}, process.env, { DESKPALS_LNK: lnk, DESKPALS_PS1: ps1, DESKPALS_PIPE: this.name }),
			}, () => {});
		} else if (process.platform === "darwin") {
			const dir = path.join(os.homedir(), "Library", "LaunchAgents");
			const plist = path.join(dir, "local.desk-pals.plist");
			const want = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.desk-pals</string>
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
			const plist = path.join(os.homedir(), "Library", "LaunchAgents", "local.desk-pals.plist");
			if (fs.existsSync(plist)) fs.unlinkSync(plist);
		}
	}

	spawn(replace) {
		try {
			let p;
			const sa = this.standalone();
			if (sa) {
				// 獨立版：直接叫它（Mac 用 open，讓它以自己的 App 身分跑，權限不算在 VS Code 頭上）
				const lu = lineupSetting();
				const pet = charSetting("spidey");   //@fan
				// <public> const pet = charSetting("duoduo");
				const pp = inLineup(pet, lu) && /^\w+$/.test(pet) ? pet : lineupDefaultPet(lu);
				p = this.win
					? cp.spawn(sa.exe, ["--pipe", this.name, "--pet", pp].concat(lineupExplicit() ? ["--lineup", lu] : []), { detached: true, stdio: "ignore", windowsHide: true })
					: cp.spawn("/usr/bin/open", ["-a", sa.app, "--args", this.endpoint, pp, lineupExplicit() ? lu : ""], { detached: true, stdio: "ignore" });
			} else if (this.win && this.useExe) {
				// vsix 附的 exe（已放到 app\DeskPals.exe）：直接執行，不經過 PowerShell。replace＝剛換上新版，先請開著的舊版收工
				const lu = lineupSetting();
				const pet = charSetting("spidey");   //@fan
				// <public> const pet = charSetting("duoduo");
				const pp = inLineup(pet, lu) && /^\w+$/.test(pet) ? pet : lineupDefaultPet(lu);
				p = cp.spawn(this.exe, (replace ? ["--replace"] : []).concat(["--pipe", this.name, "--pet", pp], lineupExplicit() ? ["--lineup", lu] : []), { detached: true, stdio: "ignore", windowsHide: true });
			} else if (process.platform === "win32") {
				// detached 的 powershell 沒有主控台會直接結束；改由短命的 powershell 用 Start-Process 叫一支獨立的起來
				const lu = lineupSetting();
				const pet = charSetting("spidey");   //@fan
				// <public> const pet = charSetting("duoduo");
				const args = `-NoProfile -WindowStyle Hidden -File "${path.join(this.home, this.ps1)}" -PipeName ${this.name} -Pet ${inLineup(pet, lu) && /^\w+$/.test(pet) ? pet : lineupDefaultPet(lu)}${lineupExplicit() ? " -Lineup " + lu : ""}`;
				p = cp.spawn("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", "Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList $env:DESKPALS_ARGS"],
					{ stdio: "ignore", windowsHide: true, env: Object.assign({}, process.env, { DESKPALS_ARGS: args }) });
			} else {
				const lu = lineupSetting();
				const pet = charSetting("spidey");   //@fan
				// <public> const pet = charSetting("duoduo");
				p = cp.spawn("/bin/bash", [path.join(this.home, this.sh), this.name, inLineup(pet, lu) ? pet : lineupDefaultPet(lu), lineupExplicit() ? lu : ""], { detached: true, stdio: "ignore" });
			}
			p.on("error", () => {});
			p.unref();
		} catch (e) {
			console.error("deskpals spawn", e);
		}
	}

	dispose() { clearTimeout(this.watchTimer); if (this.sock) this.sock.end(); }
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
		if (!this.view) return;
		if (msg.type === "character" && CHARS[msg.id] && CHARS[msg.id].custom) this.view.webview.postMessage(customMsg(msg.id));
		if (msg.type === "character" && CHARS[msg.id] && CHARS[msg.id].squad) this.view.webview.postMessage(squadMsg(this.context, msg.id));
		this.view.webview.postMessage(msg);
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

// 側邊欄要畫自己做的公仔：桌面版存好的小圖（icon.png）轉成 data URL，連同幾句台詞一起送過去
function customMsg(id) {
	const c = CHARS[id];
	let img = "";
	try {
		if (c.img && /icon\.png$/.test(c.img) && fs.statSync(c.img).size < 2 * 1024 * 1024) img = "data:image/png;base64," + fs.readFileSync(c.img).toString("base64");
	} catch (e) {}
	const restMin = Math.max(1, vscode.workspace.getConfiguration("deskPals").get("restMinutes", 50));
	return { type: "custom", id, name: c.name, img, lines: c.lines || {}, restMin };
}

// 側邊欄畫圖片公仔（續命小隊、窩伴小世界）：桌面版同一套圖（desktop/pals/<資料夾>/<id>/icon.png）轉成 data URL＋幾句台詞
function squadMsg(context, id) {
	let img = "";
	try { img = "data:image/png;base64," + fs.readFileSync(path.join(context.extensionPath, "desktop", "pals", CHARS[id].dir || "squad", id, "icon.png")).toString("base64"); } catch (e) {}
	const restMin = Math.max(1, vscode.workspace.getConfiguration("deskPals").get("restMinutes", 50));
	return { type: "custom", id, name: CHARS[id].name, img, lines: SQUAD_LINES[id] || {}, restMin };
}

function deactivate() {}

module.exports = { activate, deactivate };
