// 台詞 key 對得起來：程式裡 L("key") 要的台詞，每一櫃、每一隻都要有（缺了桌面版只會 log「missing line」，泡泡是空的）。
// 掃 C# 原始碼（Windows 版；Mac 是同一套台詞的移植）：
//   ・圖片公仔（pals/lineups.txt 的每一櫃：續命小隊、窩伴小世界…）：DeskPals.Original.cs／Woban.cs 的 static Pal Xxx()
//   ・自己做的公仔：DeskPals.CustomLines.cs 的六種個性（CuLively…）＋ 讀書小幫手共用的 CuStudyLines
// 要的 key＝共用程式（DeskPals.cs、Mischief、Study、Share）＋各自那一類的程式（Original／Woban、Custom*）裡 L("…") 的第一個參數。
// 用 Lines.ContainsKey／TryGetValue 先檢查過的 key 是選配的；拼出來的 key（"o_" + kind）要在下面 DYNAMIC 列出怎麼展開，
// 沒列到的新寫法會讓測試失敗（提醒補上）。同人角色（Fan.cs、Pikmin.cs，只在個人版）不在這裡。
// 跑：node --test test/lines.test.js
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");

const DIR = path.join(__dirname, "..", "extension", "desktop");
// 個人版才有的段落（// <fan> … // </fan>、行尾 //@fan）拿掉：公開版和個人版的共用程式都要對得起來
const strip = (s) => s.replace(/^[ \t]*\/\/ <fan>[\s\S]*?^[ \t]*\/\/ <\/fan>[ \t]*$/gm, "").split("\n").map((l) => (/\/\/.*@fan\s*$/.test(l) ? "" : l)).join("\n");
const read = (f) => strip(fs.readFileSync(path.join(DIR, f), "utf8").replace(/^﻿/, ""));

const COMMON = ["DeskPals.cs", "DeskPals.Mischief.cs", "DeskPals.Study.cs", "DeskPals.Share.cs"];
const IMAGE = ["DeskPals.Original.cs", "DeskPals.Woban.cs"];
const CUSTOM = fs.readdirSync(DIR).filter((f) => /^DeskPals\.Custom\w*\.cs$/.test(f));

// L( 的第一個參數（括號、字串都算進去）
function lCalls(src, file) {
	const out = [];
	const re = /(^|[^\w])L\(/g;
	let m;
	while ((m = re.exec(src))) {
		let i = m.index + m[0].length, depth = 0, str = null, arg = "";
		for (; i < src.length; i++) {
			const c = src[i];
			if (str) { arg += c; if (c === "\\") { arg += src[++i]; continue; } if (c === str) str = null; continue; }
			if (c === '"' || c === "'") { str = c; arg += c; continue; }
			if (c === "(") depth++;
			if (c === ")") { if (depth === 0) break; depth--; }
			if (c === "," && depth === 0) break;
			arg += c;
		}
		const line = src.slice(0, m.index).split("\n").length;
		out.push({ arg: arg.trim(), where: `${file}:${line}` });
	}
	return out;
}

// 拼出來的 key 怎麼展開（原始碼 → 會要哪些 key）；null＝選配，缺了只是不說
const DYNAMIC = [
	{ re: /^"o_"\s*\+\s*kind$/, keys: (all) => [...all.matchAll(/OrigLine\("(\w+)"\)/g)].map((m) => "o_" + m[1]) },
	{ re: /^"s_"\s*\+\s*w\.SeasonNow$/, keys: () => null },   // 節日台詞：沒有就不說（SeasonLine 回 null）
	{ re: /^key$/, keys: (all) => [...all.matchAll(/ShareLine\("(\w+)"\)/g)].map((m) => m[1]) },
	{ re: /^string key$/, keys: () => [] },   // L 本身的宣告
];

function wanted(files, label) {
	const all = files.map(read).join("\n");
	const keys = new Set(), unknown = [];
	for (const f of files) {
		for (const c of lCalls(read(f), f)) {
			if (/^"[A-Za-z0-9_]+"$/.test(c.arg)) { keys.add(c.arg.slice(1, -1)); continue; }
			if (!/\+/.test(c.arg) && /"/.test(c.arg)) { for (const s of c.arg.matchAll(/"([A-Za-z0-9_]+)"/g)) keys.add(s[1]); continue; }   // a ? "x" : "y"
			const d = DYNAMIC.find((x) => x.re.test(c.arg));
			if (!d) { unknown.push(`${c.where} L(${c.arg})`); continue; }
			for (const k of d.keys(all) || []) keys.add(k);
		}
	}
	assert.deepEqual(unknown, [], `${label}: L() with a built key — add how it expands to DYNAMIC in test/lines.test.js`);
	return { keys, all };
}

// 選配：程式先用 ContainsKey／TryGetValue 檢查過
function optional(all) {
	const exact = new Set([...all.matchAll(/(?:ContainsKey|TryGetValue)\("([A-Za-z0-9_]+)"\s*[,)]/g)].map((m) => m[1]));
	const prefixes = [...all.matchAll(/(?:ContainsKey|TryGetValue)\("([A-Za-z0-9_]+)"\s*\+/g)].map((m) => m[1]);
	return (k) => exact.has(k) || prefixes.some((p) => k.startsWith(p));
}

// 一個函式（static Pal Xxx()／void CuXxx(string me)）裡 Say("key", …) 定義的 key
function defs(file, headRe) {
	const s = read(file);
	const heads = [...s.matchAll(headRe)].map((m) => ({ name: m[1], at: m.index }));
	const out = {};
	heads.forEach((h, i) => {
		const body = s.slice(h.at, i + 1 < heads.length ? heads[i + 1].at : s.length);
		out[h.name] = new Set([...body.matchAll(/\bSay\("([A-Za-z0-9_]+)"/g)].map((m) => m[1]));
	});
	return out;
}

test("圖片公仔：pals/lineups.txt 的每一櫃、每一隻都有程式裡要的台詞", () => {
	const lineups = fs.readFileSync(path.join(DIR, "pals", "lineups.txt"), "utf8").split(/\r?\n/).filter((l) => l.trim() && !l.startsWith("#"));
	assert.ok(lineups.length >= 2, "lineups.txt has the lineups");
	const pals = Object.assign({}, ...IMAGE.map((f) => defs(f, /static Pal (\w+)\(\)/g)));
	const factory = {};
	for (const f of IMAGE) for (const m of read(f).matchAll(/case "(\w+)": return (\w+)\(\);/g)) factory[m[1]] = m[2];
	const { keys, all } = wanted(COMMON.concat(IMAGE), "image pals");
	const opt = optional(COMMON.concat(IMAGE).map(read).join("\n"));
	// o_xxx 的招牌台詞是各自的（照角色分支呼叫），只有 OrigLine 的進球／加油／沒進是大家都要的
	const kinds = new Set([...all.matchAll(/OrigLine\("(\w+)"\)/g)].map((m) => "o_" + m[1]));
	const need = [...keys].filter((k) => !/^x_/.test(k) && !(/^o_/.test(k) && !kinds.has(k)) && !opt(k)).sort();
	assert.ok(need.includes("lunch_eat") && need.includes("lunch_start"), "lunch lines are checked");
	const problems = [];
	for (const line of lineups) {
		const ids = line.split(/\s+/).filter((w) => /^[a-z]+$/.test(w));
		for (const id of ids) {
			if (!factory[id]) continue;   // 這一行的其他字（lineup id、資料夾）
			const have = pals[factory[id]];
			const miss = need.filter((k) => !have.has(k));
			if (miss.length) problems.push(`${id}: ${miss.join(" ")}`);
		}
	}
	const covered = new Set();
	for (const line of lineups) for (const w of line.split(/\s+/)) if (factory[w]) covered.add(w);
	assert.ok(covered.size >= 6, "every character in lineups.txt was checked (" + [...covered].join(",") + ")");
	assert.deepEqual(problems, [], "missing lines");
});

test("自己做的公仔：六種個性都有程式裡要的台詞", () => {
	const tpl = defs("DeskPals.CustomLines.cs", /void (Cu\w+)\(string me\)/g);
	const study = tpl.CuStudyLines || new Set();
	const personas = Object.keys(tpl).filter((n) => n !== "CuStudyLines");
	assert.equal(personas.length, 6, "six personas: " + personas.join(","));
	const { keys } = wanted(COMMON.concat(CUSTOM), "custom pals");
	const opt = optional(COMMON.concat(CUSTOM).map(read).join("\n"));
	const need = [...keys].filter((k) => !/^o_/.test(k) && !opt(k)).sort();
	const problems = [];
	for (const n of personas) {
		const miss = need.filter((k) => !tpl[n].has(k) && !study.has(k));
		if (miss.length) problems.push(`${n}: ${miss.join(" ")}`);
	}
	assert.deepEqual(problems, [], "missing lines");
});
