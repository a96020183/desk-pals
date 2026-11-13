// CI smoke test for the Windows overlay running in offscreen mode (DESKPALS_OFFSCREEN=1):
// bring every pet out, exercise notify / focus / quiet / reminder, save a snapshot, quit.
const net = require("net");
const out = (process.env.GITHUB_WORKSPACE || process.cwd()).replace(/\\/g, "/");
const s = net.connect("\\\\.\\pipe\\desk-pals-ci");
s.setEncoding("utf8");
s.on("data", (d) => process.stdout.write("REPLY " + d));
s.on("error", (e) => { console.log("PIPE ERR", e.message); process.exit(1); });
const msgs = [
	"hello", "act all", "where",
	"notify ci-ok https://example.com CI test",
	"act focus 1", "act quiet 30",
	"remind " + (Date.now() + 60000) + " CI reminder",
	"ticket " + (Date.now() + 3 * 3600e3) + " 120 https://example.com CI ticket",
	"wait", "snap " + out + "/shot.png", "where",
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
