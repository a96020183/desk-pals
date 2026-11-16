// 續命小隊（躲躲、沒電、刺刺）的離屏測試：圖讀得到、沒電的液面跟 tools/squad_art/levels.json 對得上、電量會改顏色、
// 電量連動可以關、舊的像素版資料（半糖、醒醒、糰糰）轉給新三隻。
// 用法：先用離屏模式（DESKPALS_OFFSCREEN=1、DESKPALS_ISOLATED=1）啟動桌面版，資料夾＝<data>（啟動前可以先放舊的資料，見 SQUAD_LEGACY），再
//   node test/desktop-squad.js <pipe 或 socket> <截圖資料夾> <data 資料夾>
//   SQUAD_LEGACY=1：檢查舊資料有轉過去（CI 啟動前先放 bond-boba.txt、out-original.txt「boba coffee sticky」）。最後會送 quit。
const net = require("net");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const assert = require("node:assert/strict");

const pipe = process.argv[2] || "desk-pals-squadtest";
const shots = (process.argv[3] || path.join(__dirname, "..", "shots-squad")).split(String.fromCharCode(92)).join("/");
const data = process.argv[4] || "";
fs.mkdirSync(shots, { recursive: true });
const levels = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "tools", "squad_art", "levels.json"), "utf8")).levels;

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
// 數紅色、綠色的像素（液體的顏色；晚上會變暗，所以只看色相）
function hues(file) {
	const { w, h, px } = png(file);
	let red = 0, green = 0;
	for (let i = 0; i < w * h; i++) {
		const r = px[i * 4], g = px[i * 4 + 1], b = px[i * 4 + 2], a = px[i * 4 + 3];
		if (a < 200) continue;
		if (r > g * 1.6 && r > b * 1.6 && r > 90) red++;
		if (g > r * 1.3 && g > b * 1.3 && g > 80) green++;
	}
	return { red, green };
}

const results = [];
async function check(name, fn) {
	try { await fn(); results.push([true, name]); console.log("PASS  " + name); }
	catch (e) { results.push([false, name]); console.log("FAIL  " + name + "\n      " + String(e.message).split("\n").join("\n      ")); }
}

(async () => {
	await reply("hello", (b) => /lineup \w+/.test(b));
	send("act all");
	await sleep(5000);
	send("act light");
	let pos = await where();
	await check("三隻都出來了（續命小隊＝躲躲、沒電、刺刺）", () => { for (const id of ["duoduo", "meidian", "cici"]) assert.ok(pos[id], id + " 不在外面"); });

	const dump = await reply("battery-dump", (b) => /\nend\n/.test(b));
	const R = +(/ R=(\d+)/.exec(dump) || [])[1];
	await check("沒電的圖讀到了（1x 或 2x）", () => assert.ok(R === 4 || R === 8, dump.split("\n")[0]));
	await check("沒電每一張的液面（10／50／90%）跟 levels.json 一樣", () => {
		const tab = levels[R === 4 ? "1x" : "2x"];
		let n = 0;
		for (const m of dump.matchAll(/level (\S+) (\S+) (\S+) (\S+)/g)) {
			const t = tab[m[1]].table;
			assert.ok(Math.abs(+m[2] - t[10]) < 0.05 && Math.abs(+m[3] - t[50]) < 0.05 && Math.abs(+m[4] - t[90]) < 0.05, m[0] + " vs " + [t[10], t[50], t[90]]);
			n++;
		}
		assert.equal(n, 16);
	});

	// 電量 10% 紅、90% 綠：只留沒電一隻在外面，在他身上截一小塊
	send("act select meidian");
	await sleep(3500);
	send("act f_stand meidian");
	await sleep(1500);
	pos = await where();
	const m = pos.meidian;
	const rect = m ? { x: m.x - 40, y: m.y - 80, w: 160, h: 160 } : null;
	send("battery-set 10"); await sleep(800);
	const low = hues(await snap("squad-battery-10", rect));
	send("battery-set 90"); await sleep(800);
	const high = hues(await snap("squad-battery-90", rect));
	send("battery-set 50 charge"); await sleep(800);
	const chg = hues(await snap("squad-battery-charging", rect));
	await check("電量 10% 是紅的、90% 是綠的、充電中是綠的", () => {
		assert.ok(low.red > 30 && low.red > low.green, "10%: " + JSON.stringify(low));
		assert.ok(high.green > 200 && high.green > high.red * 2, "90%: " + JSON.stringify(high));
		assert.ok(chg.green > 100, "充電: " + JSON.stringify(chg));
	});
	send("battery-set 100");

	send("battery-link 0"); await sleep(1500);
	const off = await reply("battery-dump", (b) => /\nend\n/.test(b));
	await check("電量連動可以關（VS Code 推 battery-link 0）：固定滿電", () => { assert.match(off, /link=0/); assert.match(off, /^battery 100 /m); });
	send("battery-link 1");

	send("act all");
	await sleep(4000);
	// 串場、走路中的那隻要等他站穩才擺得了圖：重試幾次
	let posed = {};
	for (let tries = 0; tries < 8; tries++) {
		for (const [id, fr] of [["duoduo", "sig2"], ["meidian", "sig1"], ["cici", "sig1"]]) if (!posed[id]) send(`act f_${fr} ${id}`);
		await sleep(700);
		const p2 = await where();
		for (const id of ["duoduo", "meidian", "cici"]) if (p2[id] && p2[id].state === "orig") posed[id] = true;
		if (Object.keys(posed).length === 3) break;
	}
	await check("每隻都能擺任何一張圖（f_<動作>）", () => assert.deepEqual(Object.keys(posed).sort(), ["cici", "duoduo", "meidian"]));
	await snap("squad-signatures");

	if (process.env.SQUAD_LEGACY === "1" && data) {
		await check("舊的像素版資料轉給新三隻（半糖→躲躲、醒醒→沒電）", () => {
			assert.ok(fs.existsSync(path.join(data, "bond-duoduo.txt")), "bond-duoduo.txt");
			assert.ok(fs.existsSync(path.join(data, "bond-meidian.txt")), "bond-meidian.txt");
			assert.ok(fs.existsSync(path.join(data, "migrated-squad2.txt")));
			const out = fs.readFileSync(path.join(data, "out-original.txt"), "utf8");
			assert.ok(!/boba|coffee|onigiri|sticky/.test(out), out);
		});
	}

	send("quit");
	await sleep(1500);
	const ok = results.filter((r) => r[0]).length;
	console.log(`\n${ok}/${results.length} passed`);
	process.exit(ok === results.length ? 0 : 1);
})();
