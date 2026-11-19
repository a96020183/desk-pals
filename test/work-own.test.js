// VS Code 擴充套件看懂桌面版的「work-own …」（桌面版在管的工作來源，擴充套件就不查、不通知）
const test = require("node:test");
const assert = require("node:assert/strict");
const { parseWorkOwn } = require("../extension/practical.js");

test("work-own：逗號隔開的來源", () => {
	assert.deepEqual([...parseWorkOwn("work-own jira,gitlab,ci")], ["jira", "gitlab", "ci"]);
	assert.deepEqual([...parseWorkOwn("work-own meet\r")], ["meet"]);
});
test("work-own -：桌面版什麼都沒管", () => assert.equal(parseWorkOwn("work-own -").size, 0));
test("別的訊息不算", () => {
	assert.equal(parseWorkOwn("lineup original"), null);
	assert.equal(parseWorkOwn("work-owner x"), null);
	assert.equal(parseWorkOwn(""), null);
});
