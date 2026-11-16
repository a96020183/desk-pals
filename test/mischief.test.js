// practical.js 的「搗蛋」設定推送（VS Code 設過的才推給桌面版）。桌面版本身的四個玩法在 test/desktop-mischief.js 用離屏模式測。
// 跑：node --test test/mischief.test.js
const test = require("node:test");
const assert = require("node:assert/strict");
const P = require("../extension/practical.js");

test("mischiefSetLines：沒在 VS Code 設過就什麼都不推（用桌面版公仔小屋的開關）", () => {
	assert.deepEqual(P.mischiefSetLines((k, d) => d, () => false), []);
});

test("mischiefSetLines：設過的才推；開關 0/1、分鐘數夾在 1～60", () => {
	const vals = { "mischief.grabCursor": true, "mischief.shoppingPolice": false, "mischief.grabMinutes": 5 };
	const get = (k, d) => (k in vals ? vals[k] : d);
	const isSet = (k) => k in vals;
	assert.deepEqual(P.mischiefSetLines(get, isSet), ["mischief-set grab 1", "mischief-set shop 0", "mischief-set grabmin 5"]);
	assert.deepEqual(P.mischiefSetLines((k, d) => (k === "mischief.grabMinutes" ? 999 : d), (k) => k === "mischief.grabMinutes"), ["mischief-set grabmin 60"]);
	assert.deepEqual(P.mischiefSetLines((k, d) => (k === "mischief.grabMinutes" ? "abc" : d), (k) => k === "mischief.grabMinutes"), ["mischief-set grabmin 3"]);
	assert.deepEqual(P.mischiefSetLines((k, d) => (k === "mischief.grabMinutes" ? 0.2 : d), (k) => k === "mischief.grabMinutes"), ["mischief-set grabmin 3"]);
});

test("mischiefSetLines：四個開關的名字跟桌面版的 mischief-set 一致", () => {
	const all = ["mischief.grabCursor", "mischief.clearAtOffWork", "mischief.shoppingPolice", "mischief.typingTooHard"];
	assert.deepEqual(P.mischiefSetLines(() => true, (k) => all.includes(k)), ["mischief-set grab 1", "mischief-set clear 1", "mischief-set shop 1", "mischief-set typing 1"]);
});

test("package.json：四個開關＋分鐘數都有設定項，搶游標預設關、其他預設開", () => {
	const props = require("../extension/package.json").contributes.configuration.properties;
	assert.equal(props["deskPals.mischief.grabCursor"].default, false);
	assert.equal(props["deskPals.mischief.grabMinutes"].default, 3);
	for (const k of ["clearAtOffWork", "shoppingPolice", "typingTooHard"]) assert.equal(props["deskPals.mischief." + k].default, true, k);
});
