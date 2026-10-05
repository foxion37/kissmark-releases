import assert from "node:assert/strict";
import { test } from "node:test";
import { docinfoRows } from "./docinfo.mjs";

test("the location row shows a parent, never repeats the file name", () => {
  assert.equal(docinfoRows({ path: "/tmp/Notes/a.md" })[0].value, "/tmp/Notes");
  assert.equal(docinfoRows({ path: "Notes/Sub/a.md" })[0].value, "Notes/Sub");
  assert.equal(docinfoRows({ path: "a.md" })[0].value, "선택한 폴더");
});
