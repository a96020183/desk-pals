// 窩伴小世界（翻翻・破破・綿綿）的離屏測試，兩種模式：
//   WOBAN_MODE=setup：全新安裝（資料夾是空的）→ 開機設定第一頁：兩櫃原創大大的二選一（續命小隊／窩伴小世界）、
//     用自己的照片做一隻、匯入朋友的公仔還在；個人版（WOBAN_PERSONAL=1）下面另外有經典、天線寶寶、皮克敏三櫃。
//     選窩伴小世界 → 整櫃 → 完成：換成窩伴小世界；選了哪櫃只記在本機 log（給了 log 路徑就檢查）。
//   WOBAN_MODE=pals（預設）：lineup＝woban 啟動 → 三隻都出來、每隻 16 張動作圖都畫得出來（每張截一小塊，不是空的）、
//     書包小屋三間、招牌動作／喝水提醒／串場不出錯、換櫃（小屋選單「換一櫃」走的同一條）來回。
// 用法：先用離屏模式（DESKPALS_OFFSCREEN=1、DESKPALS_ISOLATED=1）啟動桌面版，再
//   node test/desktop-woban.js <pipe 或 socket> <截圖資料夾> [desk-pals.log 的路徑]
// 不管現在幾點都一樣（CI 是 UTC）：一開始就 act light、act lunchend。最後會送 quit。
const net = require("net");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const assert = require("node:assert/strict");

const pipe = process.argv[2] || "desk-pals-wobantest";
const shots = (process.argv[3] || path.join(__dirname, "..", "shots-woban")).split(String.fromCharCode(92)).join("/");
const logFile = process.argv[4] || "";
const MODE = process.env.WOBAN_MODE || "pals";
const PERSONAL = process.env.WOBAN_PERSONAL === "1";
const IDS = ["fanfan", "bobo", "mian"];
const FRAMES = ["stand", "walk1", "walk2", "jump", "sleep", "happy", "held", "sit", "grab", "push", "cry", "blown", "sig1", "sig2", "surprised", "pout"];
fs.mkdirSync(shots, { recursive: true });

const s = net.connect(pipe.includes("/") ? pipe : ["", "", ".", "pipe", pipe].join(String.fromCharCode(92)));
s.setEncoding("utf8");
let buf = "";
s.on("data", (d) => { buf += d; });
s.on("error", (e) => { console.error("PIPE", e.message); process.exit(2); });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const send = (l) => s.write(l + "\n");
async function reply(cmd, done) { buf = ""; send(cmd); for (let i = 0; i < 300 && !done(buf); i++) await sleep(40); return buf; }
async function where() {
	const out = await reply("where", (b) => /(^|\n)end\n/.test(b));
	const o = {};
	for (const m of out.matchAll(/pos (\S+) (-?\d+) (-?\d+) (\S+)/g)) o[m[1]] = { x: +m[2], y: +m[3], state: m[4] };
	return o;
}
async function setupInfo() {
	const out = await reply("setup-info", (b) => /(^|\n)end\n/.test(b));
	const o = { btns: {}, raw: out };
	const h = /setup step=(\d+) first=(\d) lu=(\S+) mode=(\S+) w=(\d+) h=(\d+) featured=(\S*)/.exec(out);
	if (h) Object.assign(o, { step: +h[1], first: +h[2], lu: h[3], mode: h[4], w: +h[5], h: +h[6], featured: h[7].split(",") });
	for (const m of out.matchAll(/btn (\S+) (-?\d+) (-?\d+) (\d+) (\d+) (\d) (\d)/g)) o.btns[m[1]] = { x: +m[2], y: +m[3], w: +m[4], h: +m[5], on: +m[6], enabled: +m[7] };
	return o;
}
async function snap(name, r) { await reply(`snap ${shots}/${name}.png` + (r ? ` ${r.x} ${r.y} ${r.w} ${r.h}` : ""), (b) => b.includes("snapped")); return path.join(shots, name + ".png"); }

// 最小的 PNG 解碼（8 位元 RGB／RGBA、不交錯；桌面版 snap 存的就是這種）
function png(file) {
	const b = fs.readFileSync(file);
	let p = 8, w = 0, h = 0, ct = 0; const idat = [];
	while (p < b.length) {
		const len = b.readUInt32BE(p), type = b.toString("ascii", p + 4, p + 8), d = b.subarray(p + 8, p + 8 + len);
		if (type === "IHDR") { w = d.readUInt32BE(0); h = d.readUInt32BE(4); ct = d[9]; assert.equal(d[8], 8, "bit depth"); }
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
const DESK = [0x5b, 0x7d, 0xa8];
// 不是桌布的像素有幾個、整張的簡單指紋（比兩張圖是不是一樣）
function look(file) {
	const im = png(file);
	let n = 0, hash = 0;
	for (let i = 0; i < im.w * im.h; i++) {
		const r = im.px[i * 4], g = im.px[i * 4 + 1], b = im.px[i * 4 + 2];
		if (Math.abs(r - DESK[0]) + Math.abs(g - DESK[1]) + Math.abs(b - DESK[2]) > 40) { n++; hash = (hash * 31 + r * 7 + g * 3 + b + i) % 1000000007; }
	}
	return { n, hash };
}

const results = [];
async function check(name, fn) {
	try { await fn(); results.push([true, name]); console.log("PASS  " + name); }
	catch (e) { results.push([false, name]); console.log("FAIL  " + name + "\n      " + String(e.message).split("\n").join("\n      ")); }
}
const logText = () => { try { return fs.readFileSync(logFile, "utf8"); } catch (e) { return ""; } };

async function setupMode() {
	await reply("hello", (b) => /lineup \w+/.test(b));
	let I = null;
	for (let i = 0; i < 30; i++) { I = await setupInfo(); if (I.step === 0 && I.btns.make) break; await sleep(500); }
	await snap("woban-setup-first");
	await check("全新安裝：開機就是設定視窗第一頁", () => { assert.equal(I.step, 0, I.raw); assert.equal(I.first, 1, I.raw); });
	await check("第一頁主打兩櫃原創：續命小隊、窩伴小世界（大大的，各佔一半寬）", () => {
		assert.deepEqual([...I.featured].sort(), ["original", "woban"], I.raw);
		for (const id of ["original", "woban"]) {
			const b = I.btns["lu:" + id];
			assert.ok(b, "沒有 lu:" + id + "\n" + I.raw);
			assert.ok(b.w > I.w * 0.4 && b.h > I.h * 0.3, "不夠大 " + id + " " + JSON.stringify(b) + " 視窗 " + I.w + "x" + I.h);
		}
		const a = I.btns["lu:original"], b = I.btns["lu:woban"];
		assert.ok(Math.abs(a.y - b.y) <= 1 && Math.abs(a.w - b.w) <= 1 && Math.abs(a.h - b.h) <= 1, "兩櫃一樣大、並排 " + JSON.stringify([a, b]));
	});
	await check("第一次：兩櫃都不先選，「下一步」要選了才能按", () => {
		assert.equal(I.lu, "-", I.raw);
		assert.equal(I.btns["lu:original"].on + I.btns["lu:woban"].on, 0, I.raw);
		assert.equal(I.btns.next.enabled, 0, I.raw);
	});
	await check("還在：用自己的照片做一隻、匯入朋友的公仔", () => { assert.ok(I.btns.make, I.raw); assert.ok(I.btns.import, I.raw); });
	const fan = ["classic", "teletubbies", "pikmin"];
	if (PERSONAL) await check("個人版：下面另外有經典、天線寶寶、皮克敏三櫃（小卡）", () => {
		for (const id of fan) { const b = I.btns["lu:" + id]; assert.ok(b, "沒有 lu:" + id); assert.ok(b.y > I.btns.make.y && b.w < I.btns["lu:woban"].w, id + " " + JSON.stringify(b)); }
	});
	else await check("公開版：沒有同人櫃", () => { for (const id of fan) assert.ok(!I.btns["lu:" + id], "多了 lu:" + id); });

	send("act setup lu:woban");
	await sleep(600);
	I = await setupInfo();
	await snap("woban-setup-picked");
	await check("點窩伴小世界：選起來、可以下一步", () => { assert.equal(I.lu, "woban", I.raw); assert.equal(I.btns["lu:woban"].on, 1); assert.equal(I.btns.next.enabled, 1); });
	send("act setup next"); await sleep(600);
	send("act setup mode:shelf"); await sleep(400);
	I = await setupInfo();
	await check("第二步：整櫃", () => { assert.equal(I.step, 1, I.raw); assert.equal(I.mode, "shelf", I.raw); });
	send("act setup next");
	await sleep(3000);
	const hello = await reply("hello", (b) => /lineup \w+/.test(b));
	await check("完成：換成窩伴小世界", () => assert.match(hello, /lineup woban/));
	if (logFile) await check("選了哪櫃只記在本機 log（first-run pick woban）", () => assert.match(logText(), /setup: first-run pick woban \(shelf, order (original,woban|woban,original)\)/));
	await sleep(3000);
	const pos = await where();
	await check("窩伴小世界的三隻出來了", () => { for (const id of IDS) assert.ok(pos[id], id + " 不在外面: " + JSON.stringify(pos)); });
	await snap("woban-after-setup");
}

async function palsMode() {
	const hi = await reply("hello", (b) => /lineup \w+/.test(b));
	await check("啟動在窩伴小世界（lineup woban）", () => assert.match(hi, /lineup woban/));
	send("act light");
	send("act lunchend");
	send("act all");
	await sleep(5000);
	let pos = await where();
	await check("三隻都出來了（翻翻、破破、綿綿）", () => { for (const id of IDS) assert.ok(pos[id], id + " 不在外面: " + JSON.stringify(pos)); });
	await snap("woban-desktop");

	// 每隻 16 張：只留那一隻在外面、擺好那張圖、在他身上截一塊（不是空的、每張不一樣）
	const looks = {};
	for (const id of IDS) {
		let p = null;
		for (let tries = 0; tries < 12 && !p; tries++) {
			send("act select " + id);
			await sleep(tries ? 1500 : 3000);
			send(`act f_stand ${id}`);
			await sleep(700);
			const w = await where();
			if (w[id] && w[id].state === "orig" && Object.keys(w).length === 1) p = w[id];
		}
		if (!p) { const w = await where(); await check(id + "：站得定（一隻在外面）", () => assert.fail(JSON.stringify(w))); continue; }
		const rect = { x: p.x - 70, y: p.y - 150, w: 230, h: 230 };
		looks[id] = {};
		for (const f of FRAMES) {
			send(`act f_${f} ${id}`);
			await sleep(350);
			looks[id][f] = look(await snap(`woban-${id}-${f}`, rect));
		}
	}
	await check("每隻 16 張動作圖都畫得出來（不是空的）", () => {
		for (const id of IDS) for (const f of FRAMES) assert.ok(looks[id] && looks[id][f] && looks[id][f].n > 400, id + " " + f + " " + JSON.stringify(looks[id] && looks[id][f]));
	});
	await check("每隻至少 12 張看起來不一樣（真的換圖，不是一直同一張）", () => {
		for (const id of IDS) { const hs = new Set(FRAMES.map((f) => looks[id][f].hash)); assert.ok(hs.size >= 12, id + " 只有 " + hs.size + " 種"); }
	});

	// 招牌動作、喝水提醒（選單裡的動作）
	send("act all");
	await sleep(4000);
	let posed = {};
	for (let tries = 0; tries < 8; tries++) {
		for (const [id, a] of [["fanfan", "wb_sig2"], ["bobo", "wb_water"], ["mian", "wb_sig1"]]) if (!posed[id]) send(`act ${a} ${id}`);
		await sleep(700);
		const w = await where();
		for (const id of IDS) if (w[id] && w[id].state === "orig") posed[id] = true;
		if (Object.keys(posed).length === 3) break;
	}
	await snap("woban-signatures");
	await check("招牌動作（翻翻撒花、破破送水、綿綿蓋毯子）", () => assert.deepEqual(Object.keys(posed).sort(), ["bobo", "fanfan", "mian"]));
	if (logFile) await check("破破的喝水提醒有講（log：woban: water reminder）", () => assert.match(logText(), /woban: water reminder/));

	// 串場：兩兩、大家一起
	for (const sc of ["bobo-fanfan", "fanfan-mian", "bobo-mian", "teatime", "photo", "rollcall"]) {
		send("act scene " + sc);
		await sleep(sc.includes("-") ? 9000 : 7000);
		if (sc === "bobo-fanfan" || sc === "teatime") await snap("woban-scene-" + sc);
		send("act all");
		await sleep(1500);
	}
	pos = await where();
	await check("串場演完還在（沒當掉）", () => assert.ok(Object.keys(pos).length >= 1, JSON.stringify(pos)));
	if (logFile) await check("沒有缺台詞（log 沒有 missing line fanfan／bobo／mian）", () => assert.ok(!/missing line (fanfan|bobo|mian)\./.test(logText()), (logText().match(/missing line .*/g) || []).join("; ")));

	// 書包小屋：三間
	const si = await reply("shelf-info", (b) => /(^|\n)end\n/.test(b));
	await check("櫃子是書包小屋（woban/shelf、三間）", () => assert.match(si, /^shelf .* 1 3 woban\/shelf$/m));

	// 換櫃：續命小隊 → 紙箱櫃；再換回來 → 書包小屋
	send("lineup original");
	await sleep(3500);
	const si2 = await reply("shelf-info", (b) => /(^|\n)end\n/.test(b));
	await check("換成續命小隊：櫃子換成紙箱櫃（4 格）", () => assert.match(si2, /^shelf .* 1 4 shelf$/m));
	send("lineup woban");
	await sleep(3500);
	const si3 = await reply("shelf-info", (b) => /(^|\n)end\n/.test(b));
	await check("再換回窩伴小世界：書包小屋", () => assert.match(si3, /^shelf .* 1 3 woban\/shelf$/m));
	send("act menu house"); await sleep(600);
	await snap("woban-house-menu");
	send("act menuclose");
}

(async () => {
	if (MODE === "setup") await setupMode(); else await palsMode();
	send("quit");
	await sleep(1500);
	const ok = results.filter((r) => r[0]).length;
	console.log(`\n${ok}/${results.length} passed`);
	process.exit(ok === results.length ? 0 : 1);
})();
