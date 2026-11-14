// CI smoke test for the Windows / macOS overlay running in offscreen mode (DESKPALS_OFFSCREEN=1):
// first-run setup window, bring every pet out, exercise notify / focus / quiet / reminder, pixel menus (house + pet), snapshots, quit.
const net = require("net");
const out = (process.env.GITHUB_WORKSPACE || process.cwd()).replace(/\\/g, "/");
const s = net.connect(process.env.SMOKE_ENDPOINT || "\\\\.\\pipe\\desk-pals-ci");   // mac：unix socket 路徑
s.setEncoding("utf8");
s.on("data", (d) => process.stdout.write("REPLY " + d));
s.on("error", (e) => { console.log("PIPE ERR", e.message); process.exit(1); });
const msgs = [
	// 第一次打開：桌面版自己的設定視窗（你是？→ 選一櫃 → 怎麼擺）
	"hello", "wait", "snap " + out + "/shot-setup.png",
	"act setup work", "act setup next", "act setup next", "act setup mode:single", "snap " + out + "/shot-setup-mode.png",
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
