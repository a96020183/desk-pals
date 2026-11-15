// CI：自己做的公仔（離屏模式，DESKPALS_OFFSCREEN=1）——用一張當場產生的測試圖（不放真照片進 repo）
// 走一遍做公仔的四步 → 完成 → 全部出來 → 小圖示、.deskpal 匯出、分享短片（GIF＋說明文字）→ 收工。
// 用法：node .github/custom-smoke.js <socket|pipe> <輸出資料夾>
const net = require("net");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const ep = process.argv[2] || "desk-pals-ci";
const out = (process.argv[3] || process.cwd()).replace(/\\/g, "/");
fs.mkdirSync(out, { recursive: true });

// ---- 測試圖：240×240，白底上一隻橘色的圓胖貓（身體、頭、兩個耳朵、眼睛）----
function png(w, h, px) {
	const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
	const crc = (b) => { let c = 0xffffffff; for (const x of b) c = crcTable[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
	const chunk = (type, data) => {
		const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
		const td = Buffer.concat([Buffer.from(type), data]);
		const c = Buffer.alloc(4); c.writeUInt32BE(crc(td));
		return Buffer.concat([len, td, c]);
	};
	const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
	const raw = Buffer.alloc((w * 3 + 1) * h);
	for (let y = 0; y < h; y++) { raw[y * (w * 3 + 1)] = 0; for (let x = 0; x < w; x++) { const [r, g, b] = px(x, y); const o = y * (w * 3 + 1) + 1 + x * 3; raw[o] = r; raw[o + 1] = g; raw[o + 2] = b; } }
	return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}
const inE = (x, y, cx, cy, rx, ry) => ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1;
const inTri = (x, y, a, b, c) => { const s = (p, q, r) => (p[0] - r[0]) * (q[1] - r[1]) - (q[0] - r[0]) * (p[1] - r[1]); const d1 = s([x, y], a, b), d2 = s([x, y], b, c), d3 = s([x, y], c, a); return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0)); };
const img = path.join(out, "test-cat.png");
fs.writeFileSync(img, png(240, 240, (x, y) => {
	if (inE(x, y, 102, 108, 6, 8) || inE(x, y, 138, 108, 6, 8)) return [40, 30, 25];                       // 眼睛
	if (inE(x, y, 120, 112, 46, 40) || inE(x, y, 120, 182, 56, 44)                                          // 頭、身體
		|| inTri(x, y, [80, 96], [92, 50], [112, 80]) || inTri(x, y, [160, 96], [148, 50], [128, 80])) return [236, 146, 60];
	return [255, 255, 255];
}));

const s = net.connect(ep.includes("/") ? ep : "\\\\.\\pipe\\" + ep);
s.setEncoding("utf8");
let buf = "";
s.on("data", (d) => { buf += d; process.stdout.write("REPLY " + d); });
s.on("error", (e) => { console.log("PIPE ERR", e.message); process.exit(1); });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const send = (l) => { console.log("SEND " + l); s.write(l + "\n"); };
const snap = async (name) => { send(`snap ${out}/${name}.png`); await sleep(1200); };

s.on("connect", async () => {
	send("hello"); await sleep(2500);
	send("act setup skip"); await sleep(800);                        // 第一次的設定視窗
	send("custom new"); await sleep(800);
	send(`custom import ${img.replace(/\\/g, "/")}`); await sleep(3000);
	await snap("shot-custom-maker-0");
	send("custom press next"); await sleep(1500); await snap("shot-custom-maker-1");   // 去背
	send("custom press next"); await sleep(1500); await snap("shot-custom-maker-2");   // 像素／平滑
	send("custom press next"); await sleep(800);
	send("custom name 小橘"); send("custom press persona:cat"); await sleep(800);
	await snap("shot-custom-maker-3");
	send("custom press next"); await sleep(4000);                                       // 完成 → 換到「我的櫃」
	send("act all"); await sleep(4000);
	await snap("shot-custom");
	buf = ""; send("custom list");
	for (let i = 0; i < 60 && !/\npals |^pals /.test(buf); i++) await sleep(100);
	const m = /pals (\[.*\])/.exec(buf);
	const pals = m ? JSON.parse(m[1]) : [];
	console.log("PALS " + JSON.stringify(pals.map((p) => [p.id, p.name])));
	if (pals.length === 0) { console.log("FAIL no custom pal"); process.exit(1); }
	const id = pals[0].id;
	send(`custom icon ${id} 6 ${out}/custom-icon.png`); await sleep(800);
	send(`custom export ${id} ${out}/custom.deskpal`); await sleep(1500);
	send(`custom pet ${id} wag`); await sleep(1500);
	await snap("shot-custom-wag");
	const shareDir = `${out}/share`;
	send(`custom share ${shareDir}`);
	let gif = null;
	for (let i = 0; i < 120 && !gif; i++) {
		await sleep(500);
		if (fs.existsSync(shareDir)) gif = fs.readdirSync(shareDir).find((f) => f.endsWith(".gif"));
	}
	await sleep(1500);
	send("where"); await sleep(500);
	send("quit"); await sleep(1500);
	const fail = [];
	if (!gif) fail.push("no share gif");
	else {
		const g = fs.readFileSync(path.join(shareDir, gif));
		console.log(`GIF ${gif} ${g.length} bytes, header ${g.slice(0, 6).toString()}`);
		if (g.slice(0, 6).toString() !== "GIF89a" || g.length < 2000) fail.push("bad gif");
		const txt = path.join(shareDir, gif.replace(/\.gif$/, ".txt"));
		if (fs.existsSync(txt)) console.log("CAPTION " + fs.readFileSync(txt, "utf8"));
	}
	if (!fs.existsSync(`${out}/custom.deskpal`)) fail.push("no .deskpal export");
	else { const j = JSON.parse(fs.readFileSync(`${out}/custom.deskpal`, "utf8")); if (j.deskpal !== 1 || !j.source) fail.push("bad .deskpal"); }
	if (!fs.existsSync(`${out}/custom-icon.png`)) fail.push("no icon");
	console.log(fail.length ? "FAIL " + fail.join(", ") : "custom smoke OK");
	process.exit(fail.length ? 1 : 0);
});
