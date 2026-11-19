// 生日大驚喜的離屏測試（FAKE 時鐘＝DESKPALS_FAKE_NOW，絕不看真實日期）。
// 由 BDAY_MODE 決定這一輪測什麼（每一輪是一個獨立的桌面版實例，各有自己的假時鐘與資料夾）：
//   setup  ：全新安裝 → 第一次設定第二頁有「生日（MM-DD）」欄位，打字會存起來（也可留空）。截圖：birthday-setup-field.png
//   day    ：生日當天（資料夾預先放 birthday.txt）→ Season()=birthday、自動播一次、之後點蛋糕／act bday／娛樂選單都能再看。截圖：birthday-celebration.png
//   nonday ：有設生日但今天不是 → 什麼都不觸發。
//   blank  ：沒設生日 → 永遠不觸發。
// 用法：node test/desktop-birthday.js <pipe> <截圖資料夾> <資料夾>
const net = require("net");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const assert = require("node:assert/strict");

const pipe = process.argv[2] || "desk-pals-bdaytest";
const shots = (process.argv[3] || path.join(__dirname, "..", "shots-bday")).split(String.fromCharCode(92)).join("/");
const dataDir = process.argv[4] || process.env.DESKPALS_DATA_DIR || "";
const MODE = process.env.BDAY_MODE || "day";
fs.mkdirSync(shots, { recursive: true });

const s = net.connect(pipe.includes("/") ? pipe : ["", "", ".", "pipe", pipe].join(String.fromCharCode(92)));
s.setEncoding("utf8");
let buf = "";
s.on("data", (d) => { buf += d; });
s.on("error", (e) => { console.error("PIPE", e.message); process.exit(2); });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const send = (l) => s.write(l + "\n");
async function reply(cmd, done) { buf = ""; send(cmd); for (let i = 0; i < 300 && !done(buf); i++) await sleep(40); return buf; }

async function bday() {
	const out = await reply("bday-info", (b) => /(^|\n)end\n/.test(b));
	const o = { raw: out };
	const m = /bday birthday=(\S+) season=(\S+) on=(\d) playing=(\d) hat=(\d) plays=(\d+) auto=(\S+) costume=(\d) out=(\d+)/.exec(out);
	if (m) Object.assign(o, { birthday: m[1], season: m[2], on: +m[3], playing: +m[4], hat: +m[5], plays: +m[6], auto: m[7], costume: +m[8], out: +m[9] });
	return o;
}
async function setupInfo() {
	const out = await reply("setup-info", (b) => /(^|\n)end\n/.test(b));
	const o = { btns: {}, raw: out };
	const h = /setup step=(\d+) first=(\d) lu=(\S+) mode=(\S+) w=(\d+) h=(\d+) featured=(\S*) note=(\d) bday=(\S+) bdayfocus=(\d)/.exec(out);
	if (h) Object.assign(o, { step: +h[1], first: +h[2], lu: h[3], mode: h[4], w: +h[5], h: +h[6], bday: h[9], bdayfocus: +h[10] });
	for (const m of out.matchAll(/btn (\S+) (-?\d+) (-?\d+) (\d+) (\d+) (\d) (\d)/g)) o.btns[m[1]] = { x: +m[2], y: +m[3], w: +m[4], h: +m[5], on: +m[6], enabled: +m[7] };
	return o;
}
async function menuInfo() {
	const out = await reply("menu-info", (b) => /(^|\n)end\n/.test(b));
	const rows = [];
	for (const m of out.matchAll(/row (\d+) (\d+) (\S+) (\d) (\d) (\d) (.*)/g)) rows.push({ i: +m[1], depth: +m[2], kind: m[3], sub: +m[4], open: +m[5], text: m[7] });
	return { rows, raw: out };
}
async function where() {
	const out = await reply("where", (b) => /(^|\n)end\n/.test(b));
	const o = {};
	for (const m of out.matchAll(/pos (\S+) (-?\d+) (-?\d+) (\S+)/g)) o[m[1]] = { x: +m[2], y: +m[3], state: m[4] };
	return o;
}
async function snap(name, r) { await reply(`snap ${shots}/${name}.png` + (r ? ` ${r.x} ${r.y} ${r.w} ${r.h}` : ""), (b) => b.includes("snapped")); return png(path.join(shots, name + ".png")); }

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
const DESK = [0x5b, 0x7d, 0xa8];
function nonDesk(im) { let n = 0; for (let i = 0; i < im.w * im.h; i++) { const r = im.px[i * 4], g = im.px[i * 4 + 1], b = im.px[i * 4 + 2]; if (Math.abs(r - DESK[0]) + Math.abs(g - DESK[1]) + Math.abs(b - DESK[2]) > 40) n++; } return n; }

const results = [];
async function check(name, fn) {
	try { await fn(); results.push([true, name]); console.log("PASS  " + name); }
	catch (e) { results.push([false, name]); console.log("FAIL  " + name + "\n      " + String(e.message).split("\n").join("\n      ")); }
}

async function testSetup() {
	let I;
	for (let i = 0; i < 40; i++) { I = await setupInfo(); if (I.step === 0 && I.btns.next) break; await sleep(500); }
	await check("全新安裝：開機就是第一次設定第一頁", () => assert.equal(I.step, 0, I.raw));
	// 選一櫃 → 下一步到第二頁
	const lu = Object.keys(I.btns).find((k) => k.startsWith("lu:")).slice(3);
	send(`act setup lu:${lu}`); await sleep(300);
	send("act setup next"); await sleep(600);
	I = await setupInfo();
	await check("第二頁有生日欄位、預設留空", () => { assert.equal(I.step, 1, I.raw); assert.ok(I.btns.bday, "no bday field\n" + I.raw); assert.equal(I.bday, "-", I.raw); });
	// 打字：點欄位 → 一位一位輸入（模擬 act setup bday:03-15 的等價直接設法也測）
	send("act setup bday:03-15"); await sleep(300);
	I = await setupInfo();
	await check("輸入生日 03-15 → 欄位記住", () => assert.equal(I.bday, "03-15", I.raw));
	await snap("birthday-setup-field");
	await check("設定第二頁截圖畫得出東西（生日欄位）", () => { const im = png(path.join(shots, "birthday-setup-field.png")); assert.ok(nonDesk(im) > 2000, "blank setup shot"); });
	// 清除 → 留空 → 再設 → 完成，應寫進 birthday.txt
	send("act setup bdayclear"); await sleep(200);
	I = await setupInfo();
	await check("清除 → 回到留空", () => assert.equal(I.bday, "-", I.raw));
	send("act setup bday:1225"); await sleep(200);
	send("act setup next"); await sleep(800);   // 完成
	await check("完成設定：生日存進 birthday.txt（跟 VS Code／pipe 同一份）", () => {
		const f = path.join(dataDir, "birthday.txt");
		assert.ok(fs.existsSync(f), "no birthday.txt");
		assert.equal(fs.readFileSync(f, "utf8").trim(), "12-25");
	});
	const info = await bday();
	await check("設定精靈設的生日，桌面版當場生效（SetBirthday）", () => assert.equal(info.birthday, "12-25", info.raw));
}

async function waitHatOff() { let info; for (let i = 0; i < 80; i++) { info = await bday(); if (info.hat === 0 && info.playing === 0) return info; await sleep(300); } return info; }

async function testDay() {
	// 預先放好 birthday.txt（＝之前設定過），開機就是生日當天
	let info;
	for (let i = 0; i < 40; i++) { info = await bday(); if (info.season === "birthday") break; await sleep(300); }
	await check("生日當天：Season()=birthday、on=1", () => { assert.equal(info.season, "birthday", info.raw); assert.equal(info.on, 1, info.raw); assert.equal(info.birthday, "03-15", info.raw); });
	send("light"); await sleep(200);   // 固定白天，截圖乾淨（不看真實時間）
	// 自動播一次：等 auto 記號寫下、plays>=1
	for (let i = 0; i < 40; i++) { info = await bday(); if (info.plays >= 1) break; await sleep(300); }
	await check("當天第一次看到：自動播一次（plays>=1、auto 記下今天）", () => { assert.ok(info.plays >= 1, info.raw); assert.notEqual(info.auto, "-", info.raw); });
	await waitHatOff();   // 等自動那次收尾
	// 再看一次：act bday（＝娛樂選單那一項做的事）；戴帽、全員出櫃
	const p0 = (await bday()).plays;
	send("act bday");
	for (let i = 0; i < 30; i++) { info = await bday(); if (info.hat === 1) break; await sleep(100); }
	await check("可重播：act bday → plays 增加（不是一天一次）", () => assert.equal(info.plays, p0 + 1, `p0=${p0} ${info.raw}`));
	await check("慶祝中：公仔出櫃、戴派對帽（bday 造型沒進來→像素帽 fallback）", () => { assert.equal(info.hat, 1, info.raw); assert.ok(info.out >= 1, info.raw); assert.equal(info.costume, 0, "costume art should be absent now\n" + info.raw); });
	await sleep(1400);   // 等公仔都出來、煙火噴開再截圖
	const cel = await snap("birthday-celebration");
	await check("慶祝截圖畫得出東西（公仔＋煙火）", () => assert.ok(nonDesk(cel) > 5000, "blank celebration shot"));
	await waitHatOff();
	// 再看一次：點公仔捧著的蛋糕
	const w = await where();
	const one = Object.values(w).find((p) => p && typeof p.x === "number");
	const p2 = (await bday()).plays;
	if (one) send(`act click ${one.x},${one.y}`);
	for (let i = 0; i < 20; i++) { info = await bday(); if (info.plays > p2) break; await sleep(150); }
	await check("可重播：點蛋糕（公仔）→ plays 再增加", () => assert.ok(info.plays > p2, `p2=${p2} ${info.raw}`));
	await waitHatOff();
	// 娛樂選單那一項只有生日當天才有
	send("act menu house"); await sleep(500);
	let M = await menuInfo();
	const fun = M.rows.find((r) => /娛樂/.test(r.text));
	await check("公仔小屋有「娛樂」子選單", () => assert.ok(fun, M.raw));
	if (fun) { send(`act menuclick ${fun.i}`); await sleep(400); M = await menuInfo(); }
	await check("生日當天：娛樂裡有「生日驚喜 再看一次」", () => assert.ok(M.rows.some((r) => /生日驚喜/.test(r.text)), M.raw));
	send("menuclose");
}

async function testNonDay() {
	let info;
	for (let i = 0; i < 20; i++) { info = await bday(); if (info.birthday === "03-15") break; await sleep(300); }
	await check("有設生日、但今天不是 → season 不是 birthday、on=0", () => { assert.equal(info.birthday, "03-15", info.raw); assert.notEqual(info.season, "birthday", info.raw); assert.equal(info.on, 0, info.raw); });
	const p = info.plays;
	send("act bday"); await sleep(500);
	info = await bday();
	await check("非生日：act bday 不觸發", () => assert.equal(info.plays, p, info.raw));
	send("act menu house"); await sleep(400);
	const M = await menuInfo();
	// 展開娛樂（若有）後也不該有生日那一項
	const fun = M.rows.find((r) => /娛樂/.test(r.text));
	if (fun) { send(`act menuclick ${fun.i}`); await sleep(300); }
	const M2 = await menuInfo();
	await check("非生日：娛樂裡沒有「生日驚喜」那一項", () => assert.ok(!M2.rows.some((r) => /生日驚喜/.test(r.text)), M2.raw));
	send("menuclose");
}

async function testBlank() {
	let info;
	for (let i = 0; i < 20; i++) { info = await bday(); if (i > 3) break; await sleep(300); }
	await check("沒設生日：birthday=-、on=0", () => { assert.equal(info.birthday, "-", info.raw); assert.equal(info.on, 0, info.raw); });
	const p = info.plays;
	send("act bday"); await sleep(500);
	info = await bday();
	await check("留空＝永遠不觸發：act bday 不觸發", () => assert.equal(info.plays, p, info.raw));
}

(async () => {
	s.on("connect", () => {});
	await new Promise((r) => (s.readyState === "open" ? r() : s.once("connect", r)));
	send("hello"); await sleep(400);
	if (MODE === "setup") await testSetup();
	else if (MODE === "day") await testDay();
	else if (MODE === "nonday") await testNonDay();
	else if (MODE === "blank") await testBlank();
	const failed = results.filter((r) => !r[0]).length;
	console.log(`\n${MODE}: ${results.length - failed}/${results.length} passed`);
	await sleep(300);
	process.exit(failed ? 1 : 0);
})();
