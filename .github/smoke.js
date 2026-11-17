// CI smoke test for the Windows / macOS overlay running in offscreen mode (DESKPALS_OFFSCREEN=1):
// first-run setup window, bring every pet out, exercise notify / focus / quiet / reminder, pixel menus (house + pet), snapshots, quit.
const net = require("net");
const out = (process.env.GITHUB_WORKSPACE || process.cwd()).replace(/\\/g, "/");
const s = net.connect(process.env.SMOKE_ENDPOINT || "\\\\.\\pipe\\desk-pals-ci");   // mac：unix socket 路徑
s.setEncoding("utf8");
s.on("data", (d) => process.stdout.write("REPLY " + d));
s.on("error", (e) => { console.log("PIPE ERR", e.message); process.exit(1); });
const msgs = [
	// 第一次打開：桌面版自己的設定視窗（選公仔 → 怎麼擺）
	"hello", "wait", "snap " + out + "/shot-setup.png",
	"act setup lu:classic", "act setup next", "act setup mode:single", "snap " + out + "/shot-setup-mode.png",
	"act setup mode:shelf", "act setup next", "wait",
	"act all", "where",
	"notify ci-ok https://example.com CI test",
	"act focus 1", "act quiet 30",
	"remind " + (Date.now() + 60000) + " CI reminder",
	"ticket " + (Date.now() + 3 * 3600e3) + " 120 https://example.com CI ticket",
	"wait", "snap " + out + "/shot.png", "where",
	// 天線寶寶一櫃：當場換櫃、全部出來、吐司時間
	"lineup teletubbies", "wait", "wait", "act all", "wait", "wait", "wait", "act scene toast", "wait", "wait", "wait", "wait", "wait",
	"snap " + out + "/shot-teletubbies.png", "where",
	// 收成蛋、右鍵蛋＝公仔小屋（像素選單）；公仔的右鍵選單
	"act egg", "wait", "wait", "act menu house", "act menuhover 2", "snap " + out + "/shot-house.png", "act menuclose",
	"act menu tinky", "act menuhover 3", "snap " + out + "/shot-menu.png", "act menuclose",
];
// SMOKE_PIKMIN=1（只有 Mac 的 job 另外跑一次，DESKPALS_ISOLATED=1）：皮克敏一櫃（個人用，不放進文件）
// 設定視窗 → 全部出來 → 休息花 → 一起搬顆粒 → 右鍵選單 → 花枯了 → 休息回來喝花蜜
const pikmin = [
	"hello", "wait", "act setup lu:pikmin", "act setup next", "snap " + out + "/shot-pikmin-setup.png",
	"act setup mode:shelf", "act setup next", "wait",
	"act all", "wait", "wait", "wait", "act flower 30", "act flower click", "wait", "snap " + out + "/shot-pikmin-flower.png",
	"act scene carry", "wait", "wait", "wait", "wait", "wait", "wait", "snap " + out + "/shot-pikmin.png", "where",
	"act menu pkred", "act menuhover 3", "snap " + out + "/shot-pikmin-menu.png", "act menuclose",
	"act flower 60", "act flower wilt", "wait", "wait", "wait", "wait", "snap " + out + "/shot-pikmin-wilt.png",
	"act flower rest", "wait", "wait", "wait", "wait", "wait", "wait", "snap " + out + "/shot-pikmin-nectar.png", "where",
];
// SMOKE_ORIGINAL=1（Mac 的 job）：全新安裝（沒傳櫃子）→ 預設續命小隊；整櫃、下午三點續命、沒電插在刺刺的盆土裡充電、電量、右鍵選單、午餐、天黑、下班
const W = (n) => Array(n).fill("wait");
const original = [
	"hello", "wait", "snap " + out + "/shot-original-setup.png",
	"act setup lu:original", "act setup next", "act setup mode:shelf", "act setup next", "wait",
	"act all", ...W(3), "act scene teatime", ...W(8), "snap " + out + "/shot-original.png", "where",
	"act scene cici-meidian", ...W(6), "snap " + out + "/shot-original-plug.png",
	"battery-set 15", "act f_sig2 meidian", "wait", "snap " + out + "/shot-original-battery.png", "battery-set 100",
	"act menu meidian", "act menuhover 1", "snap " + out + "/shot-original-menu.png", "act menuclose",
	"act lunch", ...W(2), "snap " + out + "/shot-original-lunch.png", "act lunchend", "wait",
	"act dark", "wait", "snap " + out + "/shot-original-night.png", "act scene byebye", ...W(6), "where",
];
if (process.env.SMOKE_PIKMIN === "1") msgs.splice(0, msgs.length, ...pikmin);
if (process.env.SMOKE_ORIGINAL === "1") msgs.splice(0, msgs.length, ...original);
let i = 0;
const t = setInterval(() => {
	if (i < msgs.length) {
		const m = msgs[i++];
		if (m !== "wait") s.write(m + "\n");
		return;
	}
	clearInterval(t);
	setTimeout(() => { s.write("quit\n"); setTimeout(() => process.exit(0), 1500); }, 2000);
}, 1200);
