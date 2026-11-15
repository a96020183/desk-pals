// CI：確認桌面版的 pipe／socket 有在回話（hello → 回 lineup …），可選擇順便叫它收工。
// 用法：node .github/ping.js <endpoint> [quit]     endpoint：Windows 填 pipe 名稱，mac 填 socket 路徑
const net = require("net");
const [, , ep, after] = process.argv;
const target = process.platform === "win32" && !ep.startsWith("\\\\") ? "\\\\.\\pipe\\" + ep : ep;
let tries = 0;
(function attempt() {
	const s = net.connect(target);
	let buf = "";
	s.setEncoding("utf8");
	s.on("connect", () => s.write("hello\n"));
	s.on("data", (d) => {
		buf += d;
		const m = /lineup (\w+)/.exec(buf);
		if (!m) return;
		console.log("ping OK:", target, "lineup", m[1]);
		if (after === "quit") s.write("quit\n");
		setTimeout(() => process.exit(0), 800);
	});
	s.on("error", (e) => {
		if (++tries >= 40) { console.log("ping FAILED:", target, e.message); process.exit(1); }
		setTimeout(attempt, 500);
	});
})();
setTimeout(() => { console.log("ping timeout:", target); process.exit(1); }, 40000);
