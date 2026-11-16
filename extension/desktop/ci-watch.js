#!/usr/bin/env node
// 推 tag 之後盯著 CI（GitLab 用 glab、GitHub 公開 repo 用匿名 API），結果告訴桌面上的公仔。
// 用法：node ci-watch.js <repo 目錄> <tag> [prod|dev|other]
// 沒裝 glab、不是 git repo、查不到 pipeline → 安靜結束。token 只交給 glab 自己處理，這裡不碰。
const cp = require("child_process");
const https = require("https");
const net = require("net");
const os = require("os");
const path = require("path");

const [, , dir, tag, env = "other"] = process.argv;
if (!dir || !tag) process.exit(0);

const user = (os.userInfo().username || "me").replace(/[^A-Za-z0-9_.-]/g, "_");
const endpoints = process.env.DESKPALS_ENDPOINT ? [process.env.DESKPALS_ENDPOINT]
	: process.platform === "win32" ? ["\\\\.\\pipe\\desk-pals-" + user]
	: [path.join(os.homedir(), "Library", "Application Support", "DeskPals", "desk-pals.sock")];

function send(line) {
	return new Promise((resolve) => {
		const tryAt = (i) => {
			if (i >= endpoints.length) return resolve();
			const s = net.connect(endpoints[i]);
			let ok = false;
			s.on("connect", () => { ok = true; s.end(line + "\n"); });
			s.on("error", () => (ok ? resolve() : tryAt(i + 1)));
			s.on("close", () => ok && resolve());
		};
		tryAt(0);
	});
}
const notify = (kind, url, text) => send(`notify ${kind} ${url || "-"} ${text.replace(/[\r\n]+/g, " ")}`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const where = env === "prod" ? "正式機" : env === "dev" ? "測試機" : "";

function remote() {
	try {
		const url = cp.execFileSync("git", ["-C", dir, "remote", "get-url", "origin"], { encoding: "utf8", windowsHide: true }).trim();
		// https://host/group/proj(.git) 或 git@host:group/proj(.git)
		let m = /^https?:\/\/(?:[^@/]+@)?([^/:]+)(?::\d+)?\/(.+?)(?:\.git)?\/?$/.exec(url) || /^[^@]+@([^:]+):(.+?)(?:\.git)?$/.exec(url);
		return m ? { host: m[1], path: m[2] } : null;
	} catch (e) {
		return null;
	}
}

function glabPipeline(host, proj) {
	try {
		const out = cp.execFileSync("glab", ["api", "--hostname", host,
			`projects/${encodeURIComponent(proj)}/pipelines?ref=${encodeURIComponent(tag)}&per_page=1`],
		{ encoding: "utf8", windowsHide: true, timeout: 20000, stdio: ["ignore", "pipe", "ignore"] });
		const list = JSON.parse(out);
		return list && list[0] ? { status: list[0].status, url: list[0].web_url } : null;
	} catch (e) {
		return undefined; // glab 沒裝／沒權限 → 放棄
	}
}

function githubRun(proj) {
	return new Promise((resolve) => {
		const req = https.get({
			host: "api.github.com",
			path: `/repos/${proj}/actions/runs?per_page=10`,
			headers: { "User-Agent": "desk-pals", Accept: "application/vnd.github+json" },
			timeout: 15000,
		}, (res) => {
			let body = "";
			res.on("data", (d) => (body += d));
			res.on("end", () => {
				try {
					const runs = (JSON.parse(body).workflow_runs || []).filter((r) => r.head_branch === tag);
					if (!runs.length) return resolve(null);
					const r = runs[0];
					const status = r.status !== "completed" ? "running" : r.conclusion === "success" ? "success" : "failed";
					resolve({ status, url: r.html_url });
				} catch (e) { resolve(undefined); }
			});
		});
		req.on("error", () => resolve(undefined));
		req.on("timeout", () => { req.destroy(); resolve(undefined); });
	});
}

(async () => {
	const r = remote();
	if (!r) return;
	const gh = r.host === "github.com";
	const look = () => (gh ? githubRun(r.path) : Promise.resolve(glabPipeline(r.host, r.path)));
	const name = r.path.split("/").pop();
	let announced = false, misses = 0;
	const deadline = Date.now() + 90 * 60000;
	await sleep(15000); // 給 CI 一點時間建 pipeline
	while (Date.now() < deadline) {
		const p = await look();
		if (p === undefined) return; // 工具或權限不行
		if (p === null) {
			if (++misses > 12) return; // 3 分鐘都沒有 pipeline → 這個 tag 不觸發 CI
		} else if (["success"].includes(p.status)) {
			return notify("ci-ok", p.url, `${name} ${tag} ${where}部署成功！`);
		} else if (["failed", "canceled", "cancelled"].includes(p.status)) {
			return notify("ci-fail", p.url, `${name} ${tag} ${where}部署失敗（${p.status}），點我看 pipeline`);
		} else if (!announced && ["running", "pending", "created", "waiting_for_resource", "preparing", "queued", "in_progress"].includes(p.status)) {
			announced = true;
			await notify("ci-run", p.url, `${name} ${tag} ${where}CI 開始跑了，好了叫你`);
		}
		await sleep(20000);
	}
})().catch(() => {}).finally(() => setTimeout(() => process.exit(0), 300));
