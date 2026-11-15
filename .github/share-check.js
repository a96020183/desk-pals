// CI：叫開著的桌面版（離屏）做一支分享短片（custom share），確認 GIF＋說明文字真的存出來（離屏時存到 <資料夾>/share）。
// 用法：node .github/share-check.js <pipe 名稱> <DESKPALS_DATA_DIR>
const net = require("net");
const fs = require("fs");
const path = require("path");
const [, , pipe, data] = process.argv;
const dir = path.join(data, "share");
const s = net.connect("\\\\.\\pipe\\" + pipe);
s.on("error", (e) => { console.log("PIPE ERR", e.message); process.exit(1); });
s.on("connect", () => {
	s.write("act all\n");
	setTimeout(() => s.write("custom share\n"), 2000);
	const t0 = Date.now();
	const iv = setInterval(() => {
		const gifs = fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith(".gif")) : [];
		const ok = gifs.find((g) => fs.existsSync(path.join(dir, g.replace(/\.gif$/, ".txt"))) && fs.statSync(path.join(dir, g)).size > 10000);
		if (ok) { console.log("share OK", ok, fs.statSync(path.join(dir, ok)).size, "bytes"); clearInterval(iv); s.end(); process.exit(0); }
		if (Date.now() - t0 > 60000) { console.log("share: no GIF in", dir); process.exit(1); }
	}, 500);
});
