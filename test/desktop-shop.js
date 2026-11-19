// 商店那一批的離屏測試（DeskPals.Shop.cs）：兌換碼、打卡冊、換造型／櫃子外觀、商店設定的連結、續命小隊的喝水提醒。
// 這支自己開、自己關桌面版（每個情境一個臨時資料夾），用 pipe 的 shop-… 指令驅動，不碰你真的 DeskPals 資料夾和 pipe。
//   兌換碼：測試自己產生一把 P-256 測試金鑰（DESKPALS_CODE_TESTKEY，只有離屏模式收），照 App 的格式簽碼。
//     真的公鑰只驗「假的碼不會過」；要驗真的發碼工具，設 SHOP_REAL_CODE＝issue.py 發的一組碼（不要把真的碼寫進 repo）。
//   時間：一律假時鐘（DESKPALS_CLOCK 開場、study-clock 換日），不管現在幾點都一樣；喝水提醒用 shop-water-skip 快轉、study-idle 假裝在用電腦。
// 用法：node test/desktop-shop.js <endpoint 開頭> <工作資料夾> <截圖資料夾> -- <開桌面版的指令…>（{ep} 換成這次的 endpoint）
//   node test/desktop-shop.js dpshop %TEMP%\dp-shop shots\shop -- build\win\DeskPals.exe --pipe {ep}
const cp = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const net = require("net");
const path = require("path");
const zlib = require("zlib");
const assert = require("node:assert/strict");

const argv = process.argv.slice(2);
const dash = argv.indexOf("--");
const [epBase, work, shots0] = argv.slice(0, dash);
const cmd = argv.slice(dash + 1);
const win = process.platform === "win32";
const shots = path.resolve(shots0);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
async function check(name, fn) {
	try { await fn(); results.push(["PASS", name]); }
	catch (e) { results.push(["FAIL", name + "\n      " + String(e.message).split("\n").slice(0, 12).join("\n      ")]); }
}
fs.mkdirSync(work, { recursive: true });
fs.mkdirSync(shots, { recursive: true });

// ---------------- 碼（跟 DeskPals.Shop.cs 的 ShopCodes、v011 的 issue.py 同一個格式）----------------
const ALPHA = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const DOMAIN = Buffer.from("WoWoPals-code-v1");
// 項目順序＝第 i 個項目用第 i 個位元（0 起算）。要跟 DeskPals.Shop.cs 的 ShopCodes.Items、issue.py 的 ITEMS 一模一樣。
const ITEM_ORDER = [
	"xmas-costume", "exam-costume", "snow-costume", "lny-costume", "pajama-costume", "bday-costume",
	"xmas-cabinet", "exam-cabinet", "snow-cabinet", "lny-cabinet", "space-cabinet", "camp-cabinet",
];
const BIT = Object.fromEntries(ITEM_ORDER.map((n, i) => [n, 1 << i]));
const b64 = (s) => Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/"), "base64");
function keypair() {
	const k = crypto.generateKeyPairSync("ec", { namedCurve: "prime256v1" });
	const j = k.publicKey.export({ format: "jwk" });
	return { priv: k.privateKey, hex: b64(j.x).toString("hex").padStart(64, "0") + b64(j.y).toString("hex").padStart(64, "0") };
}
function b32(buf) {
	let bits = 0n;
	for (const b of buf) bits = (bits << 8n) | BigInt(b);
	const nchars = Math.ceil((buf.length * 8) / 5);
	bits <<= BigInt(nchars * 5 - buf.length * 8);   // 左補 0 到 5 的倍數（跟 issue.py 的 b32 一樣）
	let s = "";
	for (let i = nchars - 1; i >= 0; i--) s += ALPHA[Number((bits >> BigInt(i * 5)) & 31n)];
	return s.match(/.{1,4}/g).join("-");
}
function code(key, items, opt = {}) {
	let mask = 0;
	for (const it of items) mask |= BIT[it];
	const day = opt.day ?? 323, id = opt.id ?? 1;
	// 版本 1 ＋ 項目 bitmask 4 位元組（big-endian）＋ 日期 2 ＋ 流水號 2 ＝ 9 位元組
	const payload = Buffer.from([opt.ver ?? 1, (mask >>> 24) & 255, (mask >>> 16) & 255, (mask >>> 8) & 255, mask & 255, day >> 8, day & 255, id >> 8, id & 255]);
	const sig = crypto.sign("sha256", Buffer.concat([DOMAIN, payload]), { key: key.priv, dsaEncoding: "ieee-p1363" });
	if (opt.forgeMask !== undefined) payload.writeUInt32BE(opt.forgeMask >>> 0, 1);   // 簽完才改項目（假的）
	return b32(Buffer.concat([payload, sig]));
}
const flip = (c, i) => { const t = c.split(""); let k = -1; for (let j = 0; j < t.length; j++) if (t[j] !== "-" && ++k === i) { t[j] = t[j] === "Z" ? "Y" : "Z"; break; } return t.join(""); };

// ---------------- 開／關桌面版 ----------------
let n = 0;
async function launch(name, data, extraEnv = {}) {
	const ep = win ? `${epBase}-${name}-${++n}` : `${epBase}-${name}-${++n}.sock`;
	const target = win ? "\\\\.\\pipe\\" + ep : ep;
	const env = Object.assign({}, process.env, { DESKPALS_OFFSCREEN: "1", DESKPALS_ISOLATED: "1", DESKPALS_DATA_DIR: data, CLAUDE_CONFIG_DIR: path.join(data, "no-claude"), CODEX_HOME: path.join(data, "no-codex") }, extraEnv);
	if (win && process.env.SHOP_PRIVATE_TEMP === "1") { env.TEMP = env.TMP = path.join(work, "tmp"); fs.mkdirSync(env.TEMP, { recursive: true }); }
	for (const k of Object.keys(env)) if (env[k] === null) delete env[k];
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
		async info() { const o = await app.block("shop-info"); const r = { cfg: {}, pal: {} }; for (const l of o.split("\n")) { const [k, ...v] = l.split(" "); if (k === "cfg") { const e = v.join(" ").indexOf("="); r.cfg[v.join(" ").slice(0, e)] = v.join(" ").slice(e + 1); } else if (k === "pal") r.pal[v[0]] = v[1].split("=")[1]; else if (k) r[k] = v.join(" "); } return r; },
		async redeem(c) { return (await app.block("shop-redeem " + c)).trim(); },
		async wear(kind, id) { return (await app.block(`shop-wear ${kind} ${id}`)).trim(); },
		async quit() {
			sock.write("quit\n");
			for (let i = 0; i < 100 && !exited; i++) await sleep(200);
			if (!exited) { try { process.kill(child.pid); } catch (e) {} throw new Error(`${name}: did not quit`); }
		},
	};
	await app.reply("hello", (b) => /lineup \w+/.test(b));
	app.send("act light"); app.send("act lunchend"); app.send("act feature scenes=0"); app.send("act feature chatter=0");
	await sleep(1500);   // 第一格：蓋章、穿上造型
	return app;
}
function fresh(name, files = {}) {
	const d = path.join(work, name);
	fs.rmSync(d, { recursive: true, force: true });
	fs.mkdirSync(d, { recursive: true });
	for (const [f, v] of Object.entries(Object.assign({ "profile.txt": "done", "mode.txt": "shelf", "lineup.txt": "original" }, files))) fs.writeFileSync(path.join(d, f), v);
	return d;
}
function png(file) {
	const b = fs.readFileSync(file);
	let p = 8, w = 0, h = 0, ct = 0; const idat = [];
	while (p < b.length) {
		const len = b.readUInt32BE(p), type = b.toString("ascii", p + 4, p + 8), d = b.subarray(p + 8, p + 8 + len);
		if (type === "IHDR") { w = d.readUInt32BE(0); h = d.readUInt32BE(4); ct = d[9]; }
		if (type === "IDAT") idat.push(d);
		p += 12 + len;
	}
	const bpp = ct === 6 ? 4 : 3, raw = zlib.inflateSync(Buffer.concat(idat)), stride = w * bpp, out = Buffer.alloc(w * h * 4);
	let prev = Buffer.alloc(stride);
	for (let y = 0; y < h; y++) {
		const f = raw[y * (stride + 1)], line = Buffer.from(raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
		for (let i = 0; i < stride; i++) {
			const a = i >= bpp ? line[i - bpp] : 0, up = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
			let v = line[i];
			if (f === 1) v += a; else if (f === 2) v += up; else if (f === 3) v += (a + up) >> 1;
			else if (f === 4) { const pp = a + up - c, pa = Math.abs(pp - a), pb = Math.abs(pp - up), pc = Math.abs(pp - c); v += pa <= pb && pa <= pc ? a : (pb <= pc ? up : c); }
			line[i] = v & 255;
		}
		for (let x = 0; x < w; x++) for (let k = 0; k < 4; k++) out[(y * w + x) * 4 + k] = k < bpp ? line[x * bpp + k] : 255;
		prev = line;
	}
	return { w, h, px: out };
}
const opaque = (im, x0 = 0, y0 = 0, x1 = im.w, y1 = im.h) => { let c = 0; for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) if (im.px[(y * im.w + x) * 4 + 3] > 60) c++; return c; };

// ---------------- 四個商店視窗（cui pipe；離屏畫面）----------------
function parseCui(o) {
	const r = { kind: "", focus: "", link: "", size: "", scroll: "", hits: new Set(), tb: {}, extra: [] };
	for (const l of o.split("\n")) {
		const t = l.split(" ");
		if (t[0] === "cui") { for (const kv of t.slice(1)) { const e = kv.indexOf("="); if (e > 0 && r[kv.slice(0, e)] !== undefined) r[kv.slice(0, e)] = kv.slice(e + 1); } }
		else if (t[0] === "hit") r.hits.add(t[1]);
		else if (t[0] === "tb") r.tb[t[1]] = t.slice(2).join(" ");
		else if (t[0] && t[0] !== "end") r.extra.push(l);
	}
	r.extraText = r.extra.join("\n");
	return r;
}

(async () => {
	const K = keypair(), OTHER = keypair();
	const keyEnv = { DESKPALS_CODE_TESTKEY: K.hex, DESKPALS_CLOCK: "2026-12-01T10:00" };

	// ================= 兌換碼 =================
	{
		const d = fresh("codes");
		const app = await launch("codes", d, keyEnv);
		const xc = code(K, ["xmas-costume"], { id: 11 });
		await check("兌換碼：117 個字、4 個字一組（最後一組 1 個字）", () => { assert.equal(xc.replace(/-/g, "").length, 117); assert.match(xc, /^([0-9A-Z]{4}-){29}[0-9A-Z]$/); });
		await check("對的碼：兌換成功、拿到聖誕造型", async () => assert.equal(await app.redeem(xc), "redeem ok xmas-costume"));
		await check("同一組再輸入一次：已經兌換過（不會重複）", async () => assert.equal(await app.redeem(xc), "redeem again xmas-costume"));
		const two = code(K, ["xmas-cabinet", "exam-cabinet"], { id: 12 });
		const messy = "  " + two.replace(/-/g, "").toLowerCase().replace(/0/g, "o").replace(/1/g, "l").match(/.{1,7}/g).join(" ") + "\n";
		await check("小寫、O 當 0、L 當 1、亂加空白、沒有 -：一樣認得", async () => assert.equal(await app.redeem(messy), "redeem ok xmas-cabinet,exam-cabinet"));
		await check("改了一個字的碼（簽章那段）：不對", async () => assert.equal(await app.redeem(flip(code(K, ["exam-costume"], { id: 13 }), 80)), "redeem bad -"));
		await check("改了一個字的碼（日期那段）：不對", async () => assert.equal(await app.redeem(flip(code(K, ["exam-costume"], { id: 14 }), 4)), "redeem bad -"));
		await check("簽完偷改項目（聖誕造型 → 偷加其他項目）：不對", async () => assert.equal(await app.redeem(code(K, ["xmas-costume"], { id: 15, forgeMask: 0xfff })), "redeem bad -"));
		await check("別的金鑰簽的碼：不對", async () => assert.equal(await app.redeem(code(OTHER, ["exam-costume"], { id: 16 })), "redeem bad -"));
		await check("版本不是 1：不對", async () => assert.equal(await app.redeem(code(K, ["exam-costume"], { id: 17, ver: 2 })), "redeem bad -"));
		await check("少一個字、多一個字、有不是碼的字（U、#）：不對", async () => {
			const c = code(K, ["exam-costume"], { id: 18 }).replace(/-/g, "");
			assert.equal(await app.redeem(c.slice(0, -1)), "redeem bad -");
			assert.equal(await app.redeem(c + "0"), "redeem bad -");
			assert.equal(await app.redeem(c.slice(0, -1) + "U"), "redeem bad -");
			assert.equal(await app.redeem("#" + c.slice(1)), "redeem bad -");
			assert.equal(await app.redeem(""), "redeem bad -");
		});
		if (process.env.SHOP_REAL_CODE) await check("issue.py 發的真的碼（正式公鑰）：兌換成功", async () => assert.match(await app.redeem(process.env.SHOP_REAL_CODE), /^redeem ok /));
		const inf = await app.info();
		await check("有的項目：聖誕造型、聖誕櫃、考試週櫃（考試週造型沒有）", () => assert.equal(inf.owned, process.env.SHOP_REAL_CODE ? inf.owned : "exam-cabinet,xmas-cabinet,xmas-costume"));
		await check("沒買的不能穿：考試週造型鎖著", async () => assert.equal(await app.wear("costume", "exam"), "wear locked"));
		await check("買了的可以穿：聖誕造型、考試週櫃", async () => { assert.equal(await app.wear("costume", "xmas"), "wear ok"); assert.equal(await app.wear("cabinet", "exam"), "wear ok"); });
		await check("不存在的造型 id：bad", async () => assert.equal(await app.wear("costume", "pirate"), "wear bad"));
		await app.quit();

		// 重開：還在（存碼本身、重新驗）；有人在 redeemed.txt 亂加一行不算
		fs.appendFileSync(path.join(d, "redeemed.txt"), "ZZZZ-ZZZZ\n" + code(OTHER, ["exam-costume"], { id: 19 }).replace(/-/g, "") + "\n");
		const app2 = await launch("codes2", d, keyEnv);
		const i2 = await app2.info();
		await check("重開以後兌換過的還在", () => assert.match(i2.owned, /xmas-costume/));
		await check("redeemed.txt 亂加的、別的金鑰簽的：不算", () => assert.doesNotMatch(i2.owned, /exam-costume/));
		await check("穿的造型、櫃子重開還在（續命小隊三隻都穿聖誕）", () => {
			assert.match(i2.wear, /costume=xmas cabinet=exam lineup=original/);
			for (const id of ["duoduo", "meidian", "cici"]) assert.equal(i2.pal[id], "xmas", id + " " + JSON.stringify(i2.pal));
		});
		await check("紙箱櫃換成考試週外觀（圖在）", () => assert.equal(i2.skin, "shelf:exam:1"));
		await app2.quit();

		// 同一組碼在「另一台電腦」（另一個資料夾）也能用
		const d3 = fresh("codes-other-pc");
		const app3 = await launch("codes3", d3, keyEnv);
		await check("同一組碼在另一台電腦再輸入一次：一樣兌換成功", async () => assert.equal(await app3.redeem(xc), "redeem ok xmas-costume"));
		await app3.quit();

		// 沒有測試金鑰（正式的樣子）：測試金鑰簽的碼不收
		const d4 = fresh("codes-prod");
		const app4 = await launch("codes4", d4, { DESKPALS_CODE_TESTKEY: null, DESKPALS_CLOCK: "2026-12-01T10:00" });
		await check("沒設測試金鑰：測試簽的碼不收（App 只認正式公鑰）", async () => assert.equal(await app4.redeem(code(K, ["xmas-costume"], { id: 20 })), "redeem bad -"));
		await app4.quit();
	}

	// ================= 打卡冊 =================
	{
		const d = fresh("stamps");
		const app = await launch("stamps1", d, keyEnv);
		let i = await app.info();
		await check("第一次打開：蓋一個章（12/1）", () => assert.equal(i.stamps, "1 today=1 last=2026-12-01"));
		await sleep(800);
		i = await app.info();
		await check("公仔講一次：今天的章蓋好了 1／30", () => assert.equal(i.said, "今天的章蓋好了 1／30"));
		await check("沒集滿：小圍巾鎖著", async () => assert.equal(await app.wear("costume", "scarf"), "wear locked"));
		app.send("study-clock 2026-12-01T22:30");
		await sleep(1500);
		await check("同一天晚一點：不會再蓋", async () => assert.match((await app.info()).stamps, /^1 /));
		app.send("study-clock 2026-12-02T00:05");
		await sleep(1500);
		await check("開著過了半夜：隔天也蓋（2 個）", async () => assert.equal((await app.info()).stamps, "2 today=1 last=2026-12-02"));
		await app.quit();
		const app2 = await launch("stamps2", d, Object.assign({}, keyEnv, { DESKPALS_CLOCK: "2026-12-02T09:00" }));
		await sleep(800);
		i = await app2.info();
		await check("同一天重開：不會再蓋、不講話", () => { assert.match(i.stamps, /^2 /); assert.equal(i.said, "-"); });
		await app2.quit();
		const app3 = await launch("stamps3", d, Object.assign({}, keyEnv, { DESKPALS_CLOCK: "2026-12-09T09:00" }));
		await check("隔了一週才來：不會歸零（3 個）", async () => assert.equal((await app3.info()).stamps, "3 today=1 last=2026-12-09"));
		await app3.quit();
		// 已經有 29 個：第 30 個換小圍巾
		const days = [];
		for (let k = 0; k < 29; k++) days.push(new Date(Date.UTC(2026, 9, 1 + k * 2)).toISOString().slice(0, 10));
		const d2 = fresh("stamps30", { "stamps.txt": days.join("\n") + "\n2026-10-03\nbad-line\n" });
		const app4 = await launch("stamps4", d2, Object.assign({}, keyEnv, { DESKPALS_CLOCK: "2026-12-20T08:00" }));
		await sleep(800);
		i = await app4.info();
		await check("第 30 個章：講一句、小圍巾可以穿了", async () => {
			assert.equal(i.stamps, "30 today=1 last=2026-12-20");
			assert.equal(i.said, "第 30 個章，圍巾是你的了");
			assert.equal(await app4.wear("costume", "scarf"), "wear ok");
			const j = await app4.info();
			for (const id of ["duoduo", "meidian", "cici"]) assert.equal(j.pal[id], "scarf", id);
		});
		app4.send("study-clock 2026-12-21T08:00");
		await sleep(1600);
		await check("30 個以後照樣蓋（第 31 個，往下一階 60 前進）", async () => { const j = await app4.info(); assert.equal(j.stamps, "31 today=1 last=2026-12-21"); assert.equal(j.said, "今天的章蓋好了 31／60"); });
		await app4.quit();
	}

	// ================= 造型：兩櫃各記各的、畫得出來 =================
	{
		const d = fresh("wear");
		const app = await launch("wear", d, keyEnv);
		await app.redeem(code(K, ["xmas-costume", "exam-costume", "xmas-cabinet", "exam-cabinet"], { id: 30 }));
		assert.equal(await app.wear("costume", "exam"), "wear ok");
		const base = path.join(shots, "render-duoduo-stand-none.png"), dress = path.join(shots, "render-duoduo-stand-exam.png");
		await app.wear("costume", "-");
		await sleep(1300);
		const r0 = (await app.block(`shop-render duoduo stand ${base}`)).trim();
		await app.wear("costume", "exam");
		await sleep(1300);
		const r1 = (await app.block(`shop-render duoduo stand ${dress}`)).trim();
		await check("合成：穿了造型的圖比原圖大（四邊加 pad）、多出配件", () => {
			assert.match(r0, /^render \d+x\d+ r=[48]$/); assert.match(r1, /^render \d+x\d+ r=[48]$/);
			const a = png(base), b = png(dress);
			assert.ok(b.w >= a.w && b.h >= a.h && (b.w > a.w || b.h > a.h), r0 + " / " + r1);
			assert.ok(opaque(b) > opaque(a) + 100, opaque(a) + " → " + opaque(b));
		});
		for (const f of ["stand", "sleep", "push"]) for (const id of ["duoduo", "meidian", "cici"]) await app.block(`shop-render ${id} ${f} ${path.join(shots, `render-${id}-${f}-exam.png`)}`);
		app.send("act all");
		await sleep(3000);
		await app.reply(`snap ${shots}/wear-original-exam.png`, (b) => b.includes("snapped"));
		await app.reply("lineup woban", (b) => /lineup woban/.test(b));
		await sleep(2500);
		let i = await app.info();
		await check("換到窩伴小世界：這一櫃還沒選，照原本的樣子", () => { assert.match(i.wear, /costume= cabinet= lineup=woban/); for (const id of ["fanfan", "bobo", "mian"]) assert.equal(i.pal[id], "-", id); assert.equal(i.skin, "woban/shelf:-:0"); });
		await app.wear("costume", "xmas"); await app.wear("cabinet", "xmas");
		await sleep(1300);
		i = await app.info();
		await check("窩伴小世界穿聖誕、書包小屋換聖誕外觀", () => { for (const id of ["fanfan", "bobo", "mian"]) assert.equal(i.pal[id], "xmas", id); assert.equal(i.skin, "woban/shelf:xmas:1"); });
		app.send("act all");
		await sleep(3000);
		await app.reply(`snap ${shots}/wear-woban-xmas.png`, (b) => b.includes("snapped"));
		await app.reply("lineup original", (b) => /lineup original/.test(b));
		await sleep(2500);
		i = await app.info();
		await check("換回續命小隊：還是考試週造型（各記各的）", () => { assert.match(i.wear, /costume=exam cabinet= lineup=original/); assert.equal(i.pal.duoduo, "exam"); });
		await app.quit();
	}

	// ================= 商店設定：連結從 pals/shop.txt 來 =================
	{
		const cfg = path.join(work, "shop-test.txt");
		fs.writeFileSync(cfg, "# test\nprice_item_twd=100\necpay_xmas_costume=https://pay.example.test/xc\necpay_coffee_2=https://pay.example.test/c2\ncustom_form=https://form.example.test/custom\necpay_exam_cabinet=javascript:alert(1)\nfps_id=1234567\nmail=a96020183@gmail.com\n");
		const d = fresh("links");
		const app = await launch("links", d, Object.assign({}, keyEnv, { DESKPALS_SHOP_FILE: cfg }));
		const open = async (w) => (await app.block("shop-open " + w)).trim();
		await check("設定檔：讀的是指定的那份，FPS 識別碼、信箱都在", async () => { const i = await app.info(); assert.equal(i.config, "file"); assert.equal(i.cfg.fps_id, "1234567"); assert.equal(i.cfg.mail, "a96020183@gmail.com"); });
		await check("聖誕造型的綠界連結", async () => assert.equal(await open("xmas-costume"), "open https://pay.example.test/xc"));
		await check("請喝兩杯咖啡的連結", async () => assert.equal(await open("coffee-2"), "open https://pay.example.test/c2"));
		await check("訂做公仔的預約表單", async () => assert.equal(await open("custom"), "open https://form.example.test/custom"));
		await check("沒填的、不是 https 的：不開", async () => { assert.equal(await open("exam-costume"), "open -"); assert.equal(await open("exam-cabinet"), "open -"); });
		await app.quit();
		const d2 = fresh("links-default");
		const app2 = await launch("links2", d2, keyEnv);
		await check("沒指定：用 exe 裡的 pals/shop.txt（價錢、信箱）", async () => { const i = await app2.info(); assert.equal(i.config, "pals"); assert.equal(i.cfg.price_item_twd, "100"); assert.equal(i.cfg.price_item_hkd, "25"); assert.equal(i.cfg.coffee_twd, "60"); assert.equal(i.cfg.mail, "a96020183@gmail.com"); });
		await app2.quit();
	}

	// ================= 喝水提醒（45 分鐘；假的時間）=================
	{
		const d = fresh("water");
		const app = await launch("water", d, keyEnv);
		app.send("study-idle 0");   // 假裝一直在用電腦
		app.send("act select meidian");
		await sleep(3500);
		const water = async (min) => (await app.block("shop-water-skip " + min)).trim();
		await check("開關：沒電提醒喝水在「工作」、預設開（跟破破一樣）", async () => { const f = await app.block("feat-info"); assert.match(f, / sq_water=1/); assert.match(f, / wb_water=1/); });
		await water(-1000);
		await check("44 分鐘：還不講", async () => assert.match(await water(44), /last=-$/));
		let r = "";
		for (let k = 0; k < 10 && !/last=meidian/.test(r); k++) { r = await water(k === 0 ? 1.5 : 0); if (!/last=meidian/.test(r)) await sleep(500); }
		await check("過了 45 分鐘：沒電講喝水，時間重算", () => assert.match(r, /^water t=0 last=meidian$/));
		await check("沒電插上充電（log：squad: water reminder）", async () => { const log = path.join(process.env.SHOP_PRIVATE_TEMP === "1" ? path.join(work, "tmp") : process.env.TEMP || "", "desk-pals.log"); if (fs.existsSync(log)) assert.match(fs.readFileSync(log, "utf8"), /squad: water reminder/); });
		app.send("study-idle 99999");   // 離開電腦
		await sleep(500);
		await check("離開電腦：時間歸零，快轉也不算", async () => assert.match(await water(50), /^water t=0 /));
		app.send("study-idle 0");
		app.send("act feature sq_water=0");
		await sleep(400);
		await check("關掉開關：過了 45 分鐘也不講（等開了再說）", async () => { const t = await water(46); assert.match(t, /t=27\d\d /); });
		app.send("act feature sq_water=1");
		await app.reply("lineup woban", (b) => /lineup woban/.test(b));
		app.send("act select bobo");
		await sleep(3500);
		r = "";
		for (let k = 0; k < 10 && !/last=bobo/.test(r); k++) { r = await water(0); if (!/last=bobo/.test(r)) await sleep(500); }
		await check("窩伴小世界：一樣的時間，破破講", () => assert.match(r, /last=bobo/));
		await app.quit();
	}

	// ================= 四個畫面（cui）：開、互動、鎖住→商店、兌換→解鎖→穿、打卡章、空設定備援 =================
	{
		const stamp30 = Array.from({ length: 30 }, (_, k) => new Date(Date.UTC(2026, 0, 1 + k)).toISOString().slice(0, 10)).join("\n") + "\n";
		const d = fresh("ui", { "stamps.txt": stamp30 });
		const app = await launch("ui", d, Object.assign({}, keyEnv, { DESKPALS_CLOCK: "2026-12-20T09:00" }));
		const open = async (which) => { app.send("cui open " + which); await sleep(400); };
		const press = async (id) => { app.send("cui press " + id); await sleep(350); };
		const typeIn = async (key, text) => { app.send(`cui type ${key} ${text}`); await sleep(150); };
		const info = async () => parseCui(await app.block("cui info"));

		// 打卡冊（B 繪本跨頁）：開得起來、章數顯示（12/20 補第 31 個，已滿 30）
		await open("checkin");
		let ci = await info();
		await check("打卡冊：開得起來、顯示章數（滿 30、未滿 60）", () => {
			assert.equal(ci.kind, "checkin");
			assert.match(ci.extraText, /stamps 31 today=1 goal30=1 goal60=0/);
			assert.ok(ci.hits.has("close") && ci.hits.has("picker"), [...ci.hits].join(","));
		});
		await app.reply(`snap ${shots}/ui-checkin.png`, (b) => b.includes("snapped"));

		// 打卡冊 →「去我的公仔穿」→ 造型選擇（C 試穿舞台）
		await press("picker");
		let pk = await info();
		await check("打卡冊的『去我的公仔穿』：切到造型選擇", () => assert.equal(pk.kind, "picker"));

		// 造型選擇：穿已解鎖的小圍巾（打卡滿 30），馬上就穿上
		await press("costume:scarf");
		pk = await info();
		await check("造型選擇：選小圍巾，公仔馬上穿上（costume=scarf）", () => assert.match(pk.extraText, /costume=scarf /));
		await app.reply(`snap ${shots}/ui-picker.png`, (b) => b.includes("snapped"));

		// 造型選擇：鎖著的聖誕造型（還沒買）→ 跳去季節商店（A 分區）
		await press("costume:xmas");
		let sh = await info();
		await check("造型選擇：點鎖住的聖誕造型 → 打開季節商店", () => assert.equal(sh.kind, "shop"));

		// 季節商店：空設定備援（shop.txt 連結全空）：香港 FPS 顯示「—」、信箱在；咖啡／訂做沒有連結 → 不給按（即將推出）
		await check("季節商店：空設定備援（FPS=-、信箱在、咖啡／訂做『即將推出』沒有按鈕）", () => {
			assert.match(sh.extraText, /cfg mail=a96020183@gmail.com fps=- ecpay=-/);
			assert.ok(sh.hits.has("item:xmas-costume") && sh.hits.has("item:exam-cabinet"), [...sh.hits].join(","));
			assert.ok(!sh.hits.has("buy:coffee") && !sh.hits.has("buy:custom"), "空連結不該有購買按鈕");
			assert.ok(sh.hits.has("code"), "有『輸入解鎖碼』");
		});
		await app.reply(`snap ${shots}/ui-shop-empty.png`, (b) => b.includes("snapped"));

		// 季節商店 →「輸入解鎖碼」→ 票根（C）
		await press("code");
		let co = await info();
		await check("季節商店的『輸入解鎖碼』：切到票根輸入畫面", () => { assert.equal(co.kind, "code"); assert.ok("code" in co.tb, JSON.stringify(co.tb)); });

		// 票根：貼上有效的碼 → 解鎖成功
		await typeIn("code", code(K, ["xmas-costume", "exam-costume"], { id: 40 }));
		await press("unlock");
		co = await info();
		await check("票根：貼上有效的碼、按解鎖 → 成功、收進櫃子", () => assert.match(co.extraText, /result ok items (xmas-costume,exam-costume|exam-costume,xmas-costume)/));
		await app.reply(`snap ${shots}/ui-code.png`, (b) => b.includes("snapped"));

		// 票根：亂打的碼 → 不對
		await typeIn("code", "ZZZZ-ZZZZ-ZZZZ");
		await press("unlock");
		co = await info();
		await check("票根：亂打的碼 → 看起來不對", () => assert.match(co.extraText, /result bad /));

		// 解鎖後回造型選擇：聖誕造型現在穿得上了（redeem→unlock→wear 整條）
		await open("picker");
		await press("costume:xmas");
		pk = await info();
		await check("解鎖後：聖誕造型穿得上了（costume=xmas，不再跳商店）", () => { assert.equal(pk.kind, "picker"); assert.match(pk.extraText, /costume=xmas /); });

		// 造型選擇：換季節櫃子外觀（已買聖誕櫃？沒有 → 鎖住 → 跳商店）；買了的考試週櫃可穿
		await press("skin:exam");
		sh = await info();
		await check("造型選擇：點沒買的考試週櫃 → 打開季節商店", () => assert.equal(sh.kind, "shop"));

		// 已擁有的項目在商店顯示（給截圖對 mockup 的『已擁有』狀態）
		await check("季節商店：已兌換的聖誕造型標為已擁有", () => assert.match(sh.extraText, /item xmas-costume owned=1/));
		await app.reply(`snap ${shots}/ui-shop-owned.png`, (b) => b.includes("snapped"));

		// 關閉：沒有視窗了
		app.send("cui close");
		await sleep(250);
		await check("關閉：商店視窗收掉（cui none）", async () => assert.match(await app.block("cui info"), /cui none/));

		// 設定檔有填連結時：咖啡／訂做會出現可按的按鈕（對照空設定）
		const cfg = path.join(work, "ui-shop-filled.txt");
		fs.writeFileSync(cfg, "price_item_twd=100\nprice_item_hkd=25\ncoffee_twd=60\necpay_coffee_1=https://pay.example.test/c1\ncustom_early_twd=300\ncustom_form=https://form.example.test/c\nfps_id=1234567\nmail=a96020183@gmail.com\n");
		await app.quit();
		const app2 = await launch("ui-filled", fresh("ui-filled"), Object.assign({}, keyEnv, { DESKPALS_SHOP_FILE: cfg }));
		app2.send("cui open shop");
		await sleep(400);
		const sh2 = parseCui(await app2.block("cui info"));
		await check("季節商店：連結有填時，咖啡／訂做出現可按的按鈕、FPS 顯示識別碼", () => {
			assert.ok(sh2.hits.has("buy:coffee") && sh2.hits.has("buy:custom"), [...sh2.hits].join(","));
			assert.match(sh2.extraText, /cfg mail=a96020183@gmail.com fps=1234567/);
		});
		await app2.quit();
	}

	// ================= 資料驅動：打卡獎勵階梯＋季節商品清單都吃設定（加一行就多一項，不用改程式）=================
	{
		const cfg = path.join(work, "catalog.txt");
		// future／mystery 是故意沒有美術的 id：用來驗「即將推出」（美術未到）那條路；snow 美術已經在了，所以是鎖著（沒買）不是即將。
		fs.writeFileSync(cfg,
			"price_item_twd=100\nprice_item_hkd=25\nmail=a96020183@gmail.com\n" +
			"reward.30=scarf 同款小圍巾\nreward.60=grad 畢業帽\nreward.300=future 未來裝\n" +
			"costume.xmas=聖誕造型 | xmas-costume\ncabinet.xmas=聖誕 | xmas-cabinet\n" +
			"costume.snow=雪裝 | snow-costume | 120 | 30\ncabinet.snow=雪 | snow-cabinet\n" +
			"costume.mystery=神秘裝 | mystery-costume\n");
		const app = await launch("catalog", fresh("catalog"), Object.assign({}, keyEnv, { DESKPALS_SHOP_FILE: cfg, DESKPALS_CLOCK: "2026-12-20T09:00" }));
		app.send("cui open checkin"); await sleep(400);
		const ci = parseCui(await app.block("cui info"));
		await check("打卡獎勵階梯吃設定：三階 30／60／300，未來裝(300)美術未到", () => {
			assert.match(ci.extraText, /reward 30 scarf /);
			assert.match(ci.extraText, /reward 60 grad /);
			assert.match(ci.extraText, /reward 300 future got=0 art=0/);
		});
		await app.reply(`snap ${shots}/ui-catalog-checkin.png`, (b) => b.includes("snapped"));
		app.send("cui open picker"); await sleep(400);
		const pk = parseCui(await app.block("cui info"));
		await check("造型清單吃設定：未來裝／神秘裝(無美術＝即將)、雪裝(有美術、沒買＝鎖著)", () => {
			assert.match(pk.extraText, /tile future soon/);
			assert.match(pk.extraText, /tile mystery soon/);
			assert.match(pk.extraText, /tile snow lock/);
			assert.match(pk.extraText, /skin snow lock/);
		});
		app.send("cui open shop"); await sleep(400);
		const sh = parseCui(await app.block("cui info"));
		await check("季節商店吃設定：多了雪裝／雪櫃（兌換碼項目 snow-*）", () => {
			assert.ok(sh.hits.has("item:snow-costume") && sh.hits.has("item:snow-cabinet"), [...sh.hits].join(","));
			assert.match(sh.extraText, /item snow-costume owned=0/);
		});
		await app.reply(`snap ${shots}/ui-catalog-shop.png`, (b) => b.includes("snapped"));
		await app.quit();
	}

	// ================= 付費項目：12 個全部兌換得了、兌換後各自穿得上 =================
	{
		const d = fresh("paid-all");
		const app = await launch("paidall", d, keyEnv);
		const paidCostumes = [["xmas", "xmas-costume"], ["exam", "exam-costume"], ["snow", "snow-costume"], ["lny", "lny-costume"], ["pajama", "pajama-costume"], ["bday", "bday-costume"]];
		const paidCabinets = [["xmas", "xmas-cabinet"], ["exam", "exam-cabinet"], ["snow", "snow-cabinet"], ["lny", "lny-cabinet"], ["space", "space-cabinet"], ["camp", "camp-cabinet"]];
		const allItems = paidCostumes.concat(paidCabinets).map((p) => p[1]);
		await check("一組碼可以含全部 12 個付費項目（32 位元 bitmask）：兌換成功", async () => {
			const r = await app.redeem(code(K, allItems, { id: 50 }));
			assert.match(r, /^redeem ok /, r);
			assert.deepEqual(r.slice("redeem ok ".length).split(",").sort(), allItems.slice().sort());
		});
		for (const [id, item] of paidCostumes) await check(`付費造型 ${id}（${item}）兌換後穿得上`, async () => assert.equal(await app.wear("costume", id), "wear ok"));
		for (const [id, item] of paidCabinets) await check(`付費櫃子外觀 ${id}（${item}）兌換後換得上`, async () => assert.equal(await app.wear("cabinet", id), "wear ok"));
		await app.quit();
	}

	// ================= 打卡階梯：六階各自到門檻就解鎖對應造型 =================
	{
		const mkDays = (n) => Array.from({ length: n }, (_, k) => new Date(Date.UTC(2026, 0, 1 + k)).toISOString().slice(0, 10)).join("\n") + "\n";
		const tiers = [[30, "scarf"], [60, "grad"], [90, "flower"], [120, "animal"], [150, "headset"], [180, "cape"]];
		const d = fresh("tiers", { "stamps.txt": mkDays(180) });
		const app = await launch("tiers", d, Object.assign({}, keyEnv, { DESKPALS_CLOCK: "2026-12-01T09:00" }));
		for (const [days, id] of tiers) await check(`打卡 ${days} 階梯：${id} 解鎖、穿得上`, async () => assert.equal(await app.wear("costume", id), "wear ok"));
		await app.quit();
		const d2 = fresh("tiers120", { "stamps.txt": mkDays(120) });
		const app2 = await launch("tiers120", d2, Object.assign({}, keyEnv, { DESKPALS_CLOCK: "2026-12-01T09:00" }));
		await check("只打卡 120：animal(120) 解鎖，headset(150)／cape(180) 還鎖著", async () => {
			assert.equal(await app2.wear("costume", "animal"), "wear ok");
			assert.equal(await app2.wear("costume", "headset"), "wear locked");
			assert.equal(await app2.wear("costume", "cape"), "wear locked");
		});
		await app2.quit();
	}

	for (const [s, m] of results) console.log(s + "  " + m);
	const fails = results.filter((r) => r[0] === "FAIL").length;
	console.log(`${results.length - fails}/${results.length} passed`);
	process.exit(fails ? 1 : 0);
})().catch((e) => { console.error("FAIL  crashed: " + (e && e.stack || e)); process.exit(1); });
