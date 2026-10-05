import assert from "node:assert/strict";
import test from "node:test";

import { QUOTE_INPUT, TASK_INPUT } from "./input-rules.mjs";

/** The text before the caret that a rule matches: the block start plus typing. */
const typed = (...keys) => keys.join("");

test("[] + Space starts a task item, with or without the inner space", () => {
  assert.ok(TASK_INPUT.test(typed("[", "]", " ")));
  assert.ok(TASK_INPUT.test(typed("[", " ", "]", " ")));
});

test("[x] + Space is left to the gfm rule and other markers do not fire", () => {
  assert.ok(!TASK_INPUT.test(typed("[", "x", "]", " ")));
  assert.ok(!TASK_INPUT.test(typed("[", "]", "x")));
  assert.ok(!TASK_INPUT.test(typed("[", "]")));
  assert.ok(!TASK_INPUT.test(typed("-", " ", "[", "]", " ")));
  assert.ok(!TASK_INPUT.test(typed("[", "1", "]", " ")));
  assert.ok(!TASK_INPUT.test(typed("문장 ", "[", "]", " ")));
});

test('" + Space starts a quote, mid-sentence quotes do not', () => {
  assert.ok(QUOTE_INPUT.test(typed('"', " ")));
  assert.ok(!QUOTE_INPUT.test(typed('"', "x")));
  assert.ok(!QUOTE_INPUT.test(typed('"', "'", " ")));
  assert.ok(!QUOTE_INPUT.test(typed("그가 말했다", '"', " ")));
  assert.ok(!QUOTE_INPUT.test(typed(" ", '"', " ")));
});
