// 公仔櫃收起來（小紙箱／小書包）的預設與點擊，用離屏模式的桌面版逐一驗（這支自己開、自己關桌面版，每個情境一個臨時資料夾）：
//   沒有 mode.txt（全新安裝、設定精靈沒按完）＝整櫃，櫃子是打開的；以前預設「只要一隻」，有人一直不知道有櫃子。
//   存過 mode.txt 的照舊（single 的還是只要一隻）。
//   只要一隻：左鍵點收起來的小紙箱＝叫那隻出來（第一次會說明一下，只說一次）；整櫃：左鍵點它＝打開櫃子。
//
// 用法：node test/desktop-egg.js <endpoint 開頭> <工作資料夾> <截圖資料夾> -- <開桌面版的指令…>
//   指令裡的 {ep} 換成這次的 endpoint（Windows：pipe 名稱 <開頭>-<情境>；Mac：socket 路徑 <開頭>-<情境>.sock）
//   例：node test/desktop-egg.js desk-pals-egg %TEMP%\dp-egg shots -- powershell.exe -NoProfile -ExecutionPolicy Bypass -File build\public\extension\desktop\desk-pals.ps1 -PipeName {ep}
const cp = require("child_process");
const fs = require("fs");
const net = require("net");
const path = require("path");
const assert = require("node:assert/strict");

const argv = process.argv.slice(2);
const dash = argv.indexOf("--");
const [epBase, work, shots0] = argv.slice(0, dash);
const cmd = argv.slice(dash + 1);
const win = process.platform === "win32";
const shots = path.resolve(shots0).replace(/\\/g, "/");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
async function check(name, fn) {
	try { await fn(); results.push(["PASS", name]); }
	catch (e) { results.push(["FAIL", name + "\n      " + String(e.message).split("\n").slice(0, 12).join("\n      ")]); }
}
fs.mkdirSync(work, { recursive: true });
fs.mkdirSync(shots, { recursive: true });

let n = 0;
async function launch(name, data) {
	const ep = win ? `${epBase}-${name}-${++n}` : `${epBase}-${name}-${++n}.sock`;
	const target = win ? "\\\\.\\pipe\\" + ep : ep;
	const env = Object.assign({}, process.env, { DESKPALS_OFFSCREEN: "1", DESKPALS_ISOLATED: "1", DESKPALS_DATA_DIR: data });
	if (win && process.env.EGG_PRIVATE_TEMP === "1") { env.TEMP = env.TMP = path.join(work, "tmp"); fs.mkdirSync(env.TEMP, { recursive: true }); }   // 本機跑：紀錄寫到自己的資料夾
	const args = cmd.map((a) => a.replace(/\{ep\}/g, ep));
	const child = cp.spawn(args[0], args.slice(1), { env, stdio: "ignore", windowsHide: true });
	let exited = false;
	child.on("exit", () => { exited = true; });
	const sock = await new Promise((resolve, reject) => {
		const end = Date.now() + 90000;
		(function attempt() {
			const s = net.connect(target);
			s.setEncoding("utf8");
			s.once("connect", () => resolve(s));
			s.once("error", () => { if (Date.now() > end || exited) reject(new Error(`${name}: desktop did not start`)); else setTimeout(attempt, 500); });
		})();
	});
	let buf = "";
	sock.on("data", (d) => { buf += d; });
	sock.on("error", () => {});
	const app = {
		send: (l) => sock.write(l + "\n"),
		async reply(c, done) { buf = ""; sock.write(c + "\n"); for (let i = 0; i < 250 && !done(buf); i++) await sleep(40); return buf; },
		async block(c) { const o = await app.reply(c, (b) => /(^|\n)end\n/.test(b)); return o.slice(0, o.search(/(^|\n)end\n/) + 1); },
		async quit() {
			sock.write("quit\n");
			for (let i = 0; i < 100 && !exited; i++) await sleep(200);
			if (!exited) { try { process.kill(child.pid); } catch (e) {} throw new Error(`${name}: did not quit`); }
		},
	};
	await app.reply("hello", (b) => /lineup \w+/.test(b));
	return app;
}
function fresh(name, files) {
	const d = path.join(work, name);
	fs.rmSync(d, { recursive: true, force: true });
	fs.mkdirSync(d, { recursive: true });
	for (const [f, v] of Object.entries(files || {})) fs.writeFileSync(path.join(d, f), v);
	return d;
}
async function mode(app) { const d = await app.block("mode-info"); return (/mode .*/.exec(d) || [""])[0]; }
async function shelfInfo(app) {
	const out = await app.block("shelf-info");
	const o = { raw: out };
	const m = /shelf (-?\d+) (-?\d+) (\d+) (\d+) (\d) (\d+)/.exec(out);
	if (m) Object.assign(o, { x: +m[1], y: +m[2], w: +m[3], h: +m[4], collapsed: +m[5], S: +m[6] });
	const mi = /mini (-?\d+) (-?\d+) (\d+) (\d+) (\d) (\d) (\S+)/.exec(out);
	if (mi) o.mini = { x: +mi[1], y: +mi[2], w: +mi[3], h: +mi[4], art: +mi[5], name: mi[7] };
	return o;
}
async function where(app) {
	const out = await app.block("where");
	const o = {};
	for (const m of out.matchAll(/pos (\S+) (-?\d+) (-?\d+) (\S+)/g)) o[m[1]] = { x: +m[2], y: +m[3], state: m[4] };
	return o;
}
async function snap(app, name, r) { await app.reply(`snap ${shots}/${name}.png` + (r ? ` ${r.x} ${r.y} ${r.w} ${r.h}` : ""), (b) => b.includes("snapped")); }
const field = (line, k) => (new RegExp(`\\b${k}=(\\S*)`).exec(line) || [])[1];

(async () => {
	// 1. 全新安裝：沒有任何檔案 → 整櫃、櫃子打開（設定精靈自己會跳出來，這裡不按）
	{
		const app = await launch("fresh", fresh("fresh"));
		await sleep(2500);
		const m = await mode(app), I = await shelfInfo(app);
		await check("全新安裝（還沒設定）：整櫃、櫃子打開", () => {
			assert.ok(m.startsWith("mode shelf "), m);
			assert.equal(field(m, "profile"), "0", m);
			assert.equal(I.collapsed, 0, I.raw);
		});
		await app.quit();
	}
	// 2. 設定精靈沒按完（有別的檔案、沒有 profile.txt 也沒有 mode.txt）→ 整櫃
	{
		const app = await launch("noprofile", fresh("noprofile", { "lineup.txt": "original", "out.txt": "duoduo" }));
		await sleep(1500);
		const m = await mode(app), I = await shelfInfo(app);
		await check("沒按完設定（沒有 mode.txt、沒有 profile.txt）：整櫃、櫃子打開", () => {
			assert.ok(m.startsWith("mode shelf "), m);
			assert.equal(I.collapsed, 0, I.raw);
		});
		await app.quit();
	}
	// 3. 存過 mode.txt＝single 的照舊；左鍵點小紙箱＝叫他出來（第一次說明一下），再點一下回去
	{
		const app = await launch("single", fresh("single", { "lineup.txt": "original", "mode.txt": "single duoduo" }));
		await sleep(1500);
		app.send("act home");
		await sleep(3500);
		const m = await mode(app), I = await shelfInfo(app);
		await check("mode.txt＝single 的照舊：只要一隻、收起來", () => {
			assert.ok(m.startsWith("mode single duoduo"), m);
			assert.equal(field(m, "collapsed"), "1", m);
			assert.equal(field(m, "hint"), "0", m);
			assert.ok(I.mini && I.mini.art === 1 && I.mini.name === "小紙箱", I.raw);
		});
		const c = `${I.mini.x + Math.round(I.mini.w / 2)},${I.mini.y + Math.round(I.mini.h / 2)}`;
		app.send(`act click ${c}`);
		await sleep(3200);
		const pos = await where(app), m2 = await mode(app);
		await check("只要一隻：左鍵點小紙箱＝叫他出來，第一次有說明泡泡（記在 egg-hint.txt）", () => {
			assert.deepEqual(Object.keys(pos), ["duoduo"], JSON.stringify(pos));
			assert.equal(field(m2, "collapsed"), "1", m2);
			assert.equal(field(m2, "hint"), "1", m2);
		});
		const wa = { x: Math.max(0, I.x - 500), y: Math.max(0, I.y - 160), w: I.w + 500, h: I.h + 160 };
		await snap(app, "single-first-click", wa);
		app.send(`act click ${c}`);
		await sleep(3000);
		const pos2 = await where(app);
		await check("只要一隻：再點一下回小紙箱裡", () => assert.deepEqual(Object.keys(pos2), [], JSON.stringify(pos2)));
		await app.quit();
	}
	// 4. 整櫃、上次收起來：左鍵點小紙箱＝打開櫃子（不是叫公仔出來）
	{
		const app = await launch("shelfegg", fresh("shelfegg", { "profile.txt": "done", "lineup.txt": "original", "mode.txt": "shelf", "shelf-state.txt": "egg" }));
		await sleep(1500);
		app.send("act home");
		await sleep(3500);
		const I = await shelfInfo(app);
		await check("整櫃、上次收起來：開起來還是收著（小紙箱）", () => { assert.equal(I.collapsed, 1, I.raw); assert.equal(I.mini.art, 1, I.raw); });
		await snap(app, "shelf-collapsed-box", { x: I.mini.x - 40, y: I.mini.y - 40, w: I.mini.w + 50, h: I.mini.h + 42 });
		app.send(`act click ${I.mini.x + Math.round(I.mini.w / 2)},${I.mini.y + Math.round(I.mini.h / 2)}`);
		await sleep(2000);
		const I2 = await shelfInfo(app), pos = await where(app);
		await check("整櫃：左鍵點小紙箱＝打開櫃子、沒有公仔被叫出來", () => {
			assert.equal(I2.collapsed, 0, I2.raw);
			assert.deepEqual(Object.keys(pos), [], JSON.stringify(pos));
		});
		await app.quit();
	}

	for (const [k, v] of results) console.log(k + "  " + v);
	const bad = results.filter((r) => r[0] !== "PASS");
	console.log(`\n${results.length - bad.length}/${results.length} passed`);
	process.exit(bad.length ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
