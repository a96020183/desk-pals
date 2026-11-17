// 紙箱櫃（公仔櫃的外觀，extension/desktop/pals/shelf）的離屏截圖測試：圖讀得到、大小對、三隻在格子裡、名牌上有字、
// 第 4 格是「做一隻你的公仔」入口（點了開做公仔視窗）、晚上稍微暗一點但不灰、外出中、點格子叫公仔出來、
// 收合鈕（看得出來是按鈕的貼紙：夠大、點擊範圍比按鈕大一圈、滑過會變色）、收起來是小紙箱／小書包（mini.png）、左鍵點它就打開櫃子。
// 用法：先用離屏模式（DESKPALS_OFFSCREEN=1、DESKPALS_ISOLATED=1、profile.txt＝done、mode.txt＝shelf）啟動桌面版，再
//   node test/desktop-shelf.js <pipe 或 socket> <截圖資料夾>
//   SHELF_LINEUP=pikmin：個人版的皮克敏一櫃（大格是休息花、沒有第 4 格入口）。
//   SHELF_LINEUP=woban：窩伴小世界的書包小屋（pals/woban/shelf：三間一樣大的房間左右並排、沒有第 4 格）。最後會送 quit。
// 不管現在幾點都一樣（CI 是 UTC）：一開始就 act light、act lunchend，並關掉串門子劇情（act feature scenes=0）——
//   續命小隊／窩伴小世界平日 15:00–15:10 只要外面有兩隻就自動演下午茶，大家會圍到櫃子前面，「外出中」的格子就被擋住
//   （CI 在 UTC 15:0x 跑到這裡時真的發生過：格 0 被沒電擋住、格 3 被躲躲擋住）。
const net = require("net");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const assert = require("node:assert/strict");

const pipe = process.argv[2] || "desk-pals-shelftest";
const shots = (process.argv[3] || path.join(__dirname, "..", "shots-shelf")).split(String.fromCharCode(92)).join("/");
const lineup = process.env.SHELF_LINEUP || "original";
const pik = lineup === "pikmin";
const wb = lineup === "woban";
const shelfDir = path.join(__dirname, "..", "extension", "desktop", "pals", ...(wb ? ["woban", "shelf"] : ["shelf"]));
const shelfTxt = path.join(shelfDir, "shelf.txt");
const miniPng = fs.readFileSync(path.join(shelfDir, "2x", "mini.png"));
const MINI2 = { w: miniPng.readUInt32BE(16), h: miniPng.readUInt32BE(20) };   // 收起來的樣子（2x 圖的大小）
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
async function info() {
	const out = await reply("shelf-info", (b) => /(^|\n)end\n/.test(b));
	const o = { cells: [] };
	const m = /shelf (-?\d+) (-?\d+) (\d+) (\d+) (\d) (\d+) (\d)(?: (\d+) (\S+))?/.exec(out);
	if (m) Object.assign(o, { x: +m[1], y: +m[2], w: +m[3], h: +m[4], collapsed: +m[5], S: +m[6], art: +m[7], n: m[8] ? +m[8] : 4, dir: m[9] || "shelf" });
	for (const c of out.matchAll(/cell (\d) (-?\d+) (-?\d+) (\d+) (\d+) (-?\d+) (-?\d+) (\d+) (\d+) (-?\d+) (-?\d+)/g))
		o.cells[+c[1]] = { open: { x: +c[2], y: +c[3], w: +c[4], h: +c[5] }, plate: { x: +c[6], y: +c[7], w: +c[8], h: +c[9] }, foot: { x: +c[10], y: +c[11] } };
	const t = /tab (-?\d+) (-?\d+) (\d+) (\d+)/.exec(out);
	if (t) o.tab = { x: +t[1], y: +t[2], w: +t[3], h: +t[4] };
	const th = /tabhit (-?\d+) (-?\d+) (\d+) (\d+) (\d)/.exec(out);
	if (th) o.tabhit = { x: +th[1], y: +th[2], w: +th[3], h: +th[4], hover: +th[5] };
	const mi = /mini (-?\d+) (-?\d+) (\d+) (\d+) (\d) (\d) (\S+)/.exec(out);
	if (mi) o.mini = { x: +mi[1], y: +mi[2], w: +mi[3], h: +mi[4], art: +mi[5], hover: +mi[6], name: mi[7] };
	o.maker = /maker 1/.test(out);
	o.raw = out;
	return o;
}
async function snap(name, r) { await reply(`snap ${shots}/${name}.png ${r.x} ${r.y} ${r.w} ${r.h}`, (b) => b.includes("snapped")); return png(path.join(shots, name + ".png")); }

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
// 在截圖 im（左上角＝螢幕 ox, oy）的一塊矩形（螢幕座標）裡數符合 fn(r, g, b) 的像素
function count(im, ox, oy, r, fn, inset) {
	const k = inset || 0;
	let n = 0;
	for (let y = Math.max(0, r.y - oy + k); y < Math.min(im.h, r.y - oy + r.h - k); y++)
		for (let x = Math.max(0, r.x - ox + k); x < Math.min(im.w, r.x - ox + r.w - k); x++) {
			const i = (y * im.w + x) * 4;
			if (fn(im.px[i], im.px[i + 1], im.px[i + 2])) n++;
		}
	return n;
}
const DESK = [0x5b, 0x7d, 0xa8];
const notDesk = (r, g, b) => Math.abs(r - DESK[0]) + Math.abs(g - DESK[1]) + Math.abs(b - DESK[2]) > 40;
// 公仔的顏色（紙箱、奶油色背板、名牌都不算）：藍（躲躲）、綠（沒電、刺刺）、紅；皮克敏多一個黃
const palColor = (r, g, b) => (g > r + 20 && g > b + 10) || (b > r + 25 && b > g) || (r > 170 && g < 110 && b < 110) || (pik && r > 200 && g > 170 && b < 90);
const ink = (r, g, b) => r + g + b < 330;              // 名牌上的字（深色）
const plus = (r, g, b) => r > 200 && g > 130 && g < 200 && b < 140 && r - b > 90;   // 第 4 格的橘色加號圓
function stats(im, ox, oy, a) {
	let n = 0, lum = 0, blue = 0, chroma = 0;
	for (let y = 0; y < im.h; y++) for (let x = 0; x < im.w; x++) {
		const i = (y * im.w + x) * 4, r = im.px[i], g = im.px[i + 1], b = im.px[i + 2];
		if (!notDesk(r, g, b)) continue;
		n++; lum += 0.3 * r + 0.59 * g + 0.11 * b; blue += b - r; chroma += Math.max(r, g, b) - Math.min(r, g, b);
	}
	return { cover: n / (im.w * im.h), lum: lum / Math.max(1, n), blue: blue / Math.max(1, n), chroma: chroma / Math.max(1, n) };
}
// 兩張同樣大小的截圖，在一塊矩形（螢幕座標）裡差很多的像素有幾個
function diffIn(a, b, ox, oy, r) {
	let n = 0;
	for (let y = Math.max(0, r.y - oy); y < Math.min(a.h, r.y - oy + r.h); y++)
		for (let x = Math.max(0, r.x - ox); x < Math.min(a.w, r.x - ox + r.w); x++) {
			const i = (y * a.w + x) * 4;
			if (Math.abs(a.px[i] - b.px[i]) + Math.abs(a.px[i + 1] - b.px[i + 1]) + Math.abs(a.px[i + 2] - b.px[i + 2]) > 60) n++;
		}
	return n;
}

const results = [];
async function check(name, fn) {
	try { await fn(); results.push([true, name]); console.log("PASS  " + name); }
	catch (e) { results.push([false, name]); console.log("FAIL  " + name + "\n      " + String(e.message).split("\n").join("\n      ")); }
}

(async () => {
	await reply("hello", (b) => /lineup \w+/.test(b));
	send("act light");
	send("act lunchend");   // CI 是 UTC：12 點剛好午休，大家會在櫃子裡拿便當
	send("act feature scenes=0");   // 15:00 的下午茶等時段劇情不要演（會把大家叫到櫃子前面）
	send("act unegg");
	// 全部回櫃子（早上點名、下班串場可能把大家叫出來：一直收到真的都在櫃子裡）
	let pos = {};
	for (let tries = 0; tries < 10; tries++) {
		send("act home");
		await sleep(tries ? 2500 : 4000);
		pos = await where();
		if (Object.keys(pos).length === 0) break;
	}
	await sleep(3500);   // 回櫃子的泡泡消失
	let I = await info();
	const area = { x: I.x, y: I.y, w: I.w, h: I.h };
	await check(wb ? "書包小屋的圖讀到了（woban/shelf：shelf.txt、box.png）" : "紙箱櫃的圖讀到了（shelf.txt、box.png）", () => { assert.equal(I.art, 1, I.raw); assert.equal(I.dir, wb ? "woban/shelf" : "shelf", I.raw); });
	await check("櫃子大小＝shelf.txt 的 2x 尺寸 × S/8", () => {
		const txt = fs.readFileSync(shelfTxt, "utf8");
		const [, W2, H2] = /size (\d+) (\d+)/.exec(txt).map(Number);
		assert.equal(I.w, Math.floor(W2 * I.S / 8 + 0.5), I.raw);
		assert.equal(I.h, Math.floor(H2 * I.S / 8 + 0.5), I.raw);
		assert.equal(I.collapsed, 0);
		for (const c of I.cells) {
			assert.ok(c.open.x >= I.x && c.open.y >= I.y && c.open.x + c.open.w <= I.x + I.w && c.open.y + c.open.h <= I.y + I.h, "格子在櫃子裡 " + JSON.stringify(c));
			assert.ok(c.plate.y >= c.open.y + c.open.h - 2, "名牌在開口下面 " + JSON.stringify(c));
			assert.ok(c.foot.y > c.open.y && c.foot.y <= c.open.y + c.open.h && c.foot.x > c.open.x && c.foot.x < c.open.x + c.open.w, "腳底在開口裡 " + JSON.stringify(c));
		}
	});
	if (wb) await check("書包小屋：三間差不多大的房間（差 8% 內），左右並排、地板同高", () => {
		assert.equal(I.n, 3, I.raw);
		assert.equal(I.cells.length, 3, I.raw);
		for (let i = 1; i < 3; i++) {
			const a = I.cells[i - 1].open, b = I.cells[i].open;
			assert.ok(Math.abs(a.w - b.w) <= a.w * 0.08 && Math.abs(a.h - b.h) <= a.h * 0.08 && Math.abs(a.y + a.h - b.y - b.h) <= 2, "差不多大、同一排 " + JSON.stringify([a, b]));
			assert.ok(b.x >= a.x + a.w, "左右並排、不重疊 " + JSON.stringify([a, b]));
		}
	});
	await check("一開始大家都在櫃子裡", () => assert.deepEqual(Object.keys(pos), []));

	const day = await snap("shelf-day", area);
	const dayS = stats(day, area.x, area.y);
	await check("白天：櫃子畫出來了（大部分不是桌布）", () => assert.ok(dayS.cover > 0.6, JSON.stringify(dayS)));
	const palCells = pik ? [1, 2, 3] : [0, 1, 2];
	const dayPal = I.cells.map((c) => count(day, area.x, area.y, c.open, palColor));
	// 窩伴小世界的房間是粉彩色（跟公仔的顏色分不開）：改成比「在家」和「外出中」兩張截圖的差（見下面外出中那段）
	if (!wb) await check("三隻在格子裡（" + palCells.join("、") + "）", () => { for (const i of palCells) assert.ok(dayPal[i] > 40, "格 " + i + " 沒有公仔的顏色: " + JSON.stringify(dayPal)); });
	await check(I.cells.length + " 塊名牌上都有字", () => {
		const n = I.cells.map((c) => count(day, area.x, area.y, c.plate, ink, 2));
		for (let i = 0; i < I.cells.length; i++) assert.ok(n[i] >= 6, "名牌 " + i + " 沒有字: " + JSON.stringify(n));
	});
	if (pik) {
		await check("皮克敏一櫃：大格是休息花（粉紅花瓣）", () => assert.ok(count(day, area.x, area.y, I.cells[0].open, (r, g, b) => r > 200 && g > 110 && g < 190 && b > 140) > 20));
	} else if (!wb) {
		await check("第 4 格是「做一隻你的公仔」入口（加號＋一行字）", () => {
			const c = I.cells[3].open;
			assert.ok(count(day, area.x, area.y, c, plus) > 10, "沒有橘色加號");
			assert.ok(count(day, area.x, area.y, { x: c.x, y: c.y, w: c.w, h: Math.round(c.h * 0.3) }, (r, g, b) => r < 170 && r > g && g > b && r - b > 30) > 8, "上面沒有字");
		});
	}

	send("act dark");
	await sleep(4500);   // 「天黑了」的泡泡
	const night = await snap("shelf-night", area);
	const nightS = stats(night, area.x, area.y);
	await check("晚上：櫃子暗一點，但顏色不變灰（程式調色，不是另一張圖）", () => {
		assert.ok(nightS.lum < dayS.lum * 0.92 && nightS.lum > dayS.lum * 0.6, "暗得不對: " + JSON.stringify({ dayS, nightS }));
		assert.ok(nightS.blue >= dayS.blue - 1, "反而變暖了: " + JSON.stringify({ dayS, nightS }));   // 夜色很淡（藍 ×0.88 對紅綠 ×0.86／0.83），格子小燈又是暖的：只要求不偏暖
		assert.ok(nightS.chroma > dayS.chroma * 0.7, "變灰了（顏色掉太多）: " + JSON.stringify({ dayS, nightS }));
		assert.ok(nightS.cover > 0.6, "櫃子不見了: " + JSON.stringify(nightS));
	});
	send("act light");
	await sleep(1500);

	// 外出中：全部放出來，格子裡只剩淡淡的剪影＋「外出中」牌子
	send("act all");
	await sleep(5000);
	const away = await snap("shelf-away", area);
	const awayPal = I.cells.map((c) => count(away, area.x, area.y, c.open, palColor));
	if (wb) {
		const diff = I.cells.map((c) => {
			let n = 0;
			for (let y = c.open.y - area.y; y < c.open.y - area.y + c.open.h; y++)
				for (let x = c.open.x - area.x; x < c.open.x - area.x + c.open.w; x++) {
					const i = (y * day.w + x) * 4;
					if (Math.abs(day.px[i] - away.px[i]) + Math.abs(day.px[i + 1] - away.px[i + 1]) + Math.abs(day.px[i + 2] - away.px[i + 2]) > 60) n++;
				}
			return n;
		});
		await check("三隻在房間裡（在家／外出中兩張截圖，每間都差很多）", () => { for (const i of palCells) assert.ok(diff[i] > 300, "房間 " + i + ": " + JSON.stringify(diff)); });
	} else await check("外出中：格子裡的公仔不見了（只剩剪影）", () => { for (const i of palCells) assert.ok(awayPal[i] < dayPal[i] * 0.5, "格 " + i + ": " + JSON.stringify({ dayPal, awayPal })); });

	// 點格子：叫那一隻出來
	for (let tries = 0; tries < 10; tries++) {
		send("act home");
		await sleep(tries ? 2500 : 4000);
		pos = await where();
		if (Object.keys(pos).length === 0) break;
	}
	const c1 = I.cells[1];
	send(`act click ${c1.foot.x},${c1.open.y + Math.round(c1.open.h / 2)}`);
	await sleep(2500);
	pos = await where();
	await check("點小格：那一隻出來了", () => assert.equal(Object.keys(pos).length, 1, JSON.stringify(pos)));
	send("act home");
	await sleep(3000);

	if (!pik && !wb) {
		const c3 = I.cells[3];
		send(`act click ${c3.foot.x},${c3.open.y + Math.round(c3.open.h / 2)}`);
		await sleep(1500);
		I = await info();
		await check("點第 4 格：開「做一隻你的公仔」視窗", () => assert.ok(I.maker, I.raw));
		await snap("shelf-maker", { x: area.x - 900, y: Math.max(0, area.y - 300), w: 900 + area.w, h: area.h + 300 });
		send("custom cancel");
		await sleep(800);
	}

	// 收合鈕：看得出來是按鈕（夠大），點擊範圍比按鈕大一圈但不蓋到格子；滑過會變色
	await check("收合鈕夠大（至少 12×4.5 格），點擊範圍比按鈕大一圈、不蓋到格子開口", () => {
		const t = I.tab, h = I.tabhit;
		assert.ok(t && h, I.raw);
		assert.ok(t.w >= 12 * I.S && t.h >= 4.5 * I.S, "按鈕太小 " + JSON.stringify(t));
		assert.ok(h.x < t.x && h.y < t.y && h.x + h.w > t.x + t.w && h.w >= t.w + 2 * I.S, "點擊範圍沒有比按鈕大 " + JSON.stringify({ t, h }));
		assert.ok(t.x >= I.x && t.y >= I.y && t.x + t.w <= I.x + I.w, "按鈕跑出櫃子 " + JSON.stringify(t));
		for (const c of I.cells) assert.ok(h.y + h.h <= c.open.y, "點擊範圍蓋到格子 " + JSON.stringify({ h, c: c.open }));
	});
	const topBand = { x: area.x, y: area.y, w: area.w, h: Math.min(area.h, I.tabhit.y + I.tabhit.h - area.y + 8 * I.S) };
	const tabOff = await snap("shelf-tab", area);
	send(`act shelfhover ${I.tab.x + Math.round(I.tab.w / 2)},${I.tab.y + Math.round(I.tab.h / 2)}`);
	await sleep(400);
	const hovI = await info();
	const tabOn = await snap("shelf-tab-hover", area);
	await check("滑過收合鈕：按鈕變色、浮起來（下面出現「收成" + (wb ? "小書包" : "小紙箱") + "」）", () => {
		assert.equal(hovI.tabhit.hover, 1, hovI.raw);
		assert.ok(diffIn(tabOff, tabOn, area.x, area.y, topBand) > 150, "畫面沒變: " + diffIn(tabOff, tabOn, area.x, area.y, topBand));
	});
	send(`act shelfhover ${area.x + Math.round(area.w / 2)},${area.y + area.h - 4}`);
	await sleep(300);

	// 點在按鈕外面、點擊範圍裡面（按鈕左邊一點點）：也算點到 → 收起來
	send(`act click ${I.tab.x - 2},${I.tab.y + Math.round(I.tab.h / 2)}`);
	await sleep(1800);
	const egg = await info();
	await check("點收合鈕旁邊（點擊範圍裡、按鈕外）：收起來", () => assert.equal(egg.collapsed, 1, egg.raw));
	await sleep(1200);
	await check("收起來是" + (wb ? "小書包" : "小紙箱") + "（mini.png，大小＝2x 圖 × S/8），在櫃子右下角", () => {
		const m = egg.mini;
		assert.ok(m, egg.raw);
		assert.equal(m.art, 1, egg.raw);
		assert.equal(m.name, wb ? "小書包" : "小紙箱", egg.raw);
		assert.equal(m.w, Math.floor(MINI2.w * egg.S / 8 + 0.5), egg.raw);
		assert.equal(m.h, Math.floor(MINI2.h * egg.S / 8 + 0.5), egg.raw);
		assert.ok(m.x + m.w <= egg.x + egg.w && m.y + m.h <= egg.y + egg.h && m.x > egg.x + egg.w / 2, egg.raw);
	});
	const mini = await snap("shelf-mini", { x: egg.mini.x - 8, y: egg.mini.y - 8, w: egg.mini.w + 16, h: egg.mini.h + 10 });
	await check("收起來的圖畫出來了（大部分不是桌布）", () => {
		const m = egg.mini, n = count(mini, m.x - 8, m.y - 8, m, notDesk);
		assert.ok(n > m.w * m.h * 0.6, "只有 " + n + " / " + m.w * m.h);
	});
	send("act dark");
	await sleep(1500);
	await snap("shelf-mini-night", { x: egg.mini.x - 8, y: egg.mini.y - 8, w: egg.mini.w + 16, h: egg.mini.h + 10 });
	send("act light");
	await sleep(800);
	// 整櫃模式：左鍵點收起來的小紙箱／小書包＝打開櫃子（不是叫公仔出來）
	send(`act click ${egg.mini.x + Math.round(egg.mini.w / 2)},${egg.mini.y + Math.round(egg.mini.h / 2)}`);
	await sleep(1800);
	const back = await info();
	pos = await where();
	await check("左鍵點收起來的" + (wb ? "小書包" : "小紙箱") + "：櫃子打開、沒有公仔被叫出來", () => {
		assert.equal(back.collapsed, 0, back.raw);
		assert.deepEqual(Object.keys(pos), [], JSON.stringify(pos));
	});
	await sleep(1500);
	await snap("shelf-reopened", area);

	const bad = results.filter((r) => !r[0]);
	console.log(`\n${results.length - bad.length}/${results.length} passed`);
	send("quit");
	await sleep(1500);
	process.exit(bad.length ? 1 : 0);
})();
