import assert from "node:assert/strict";
import test from "node:test";

import { currentKindKey, turnIntoOps } from "./turn-into.mjs";

const paragraph = { node: "paragraph" };
const heading = (level) => ({ node: "heading", level });
const listItem = (listType, listCount = 3) => ({ node: "listItem", listType, listCount });
const alone = (listType) => ({ node: "listItem", listType, listCount: 1 });
const blockquote = { node: "blockquote", callout: false };
const callout = { node: "blockquote", callout: true };


test("currentKindKey names the block for the check mark", () => {
  assert.equal(currentKindKey(paragraph), "text");
  assert.equal(currentKindKey(heading(3)), "h3");
  assert.equal(currentKindKey(listItem("bullet")), "bulletList");
  assert.equal(currentKindKey(listItem("ordered")), "orderedList");
  assert.equal(currentKindKey(listItem("task")), "taskList");
  assert.equal(currentKindKey(blockquote), "quote");
  assert.equal(currentKindKey(callout), "callout");
  // Blocks the menu cannot express show no check.
  assert.equal(currentKindKey({ node: "codeBlock" }), null);
  assert.equal(currentKindKey({ node: "divider" }), null);
  assert.equal(currentKindKey(undefined), null);
});

test("converting a block to what it already is is a no-op", () => {
  assert.deepEqual(turnIntoOps("text", paragraph), []);
  assert.deepEqual(turnIntoOps("h2", heading(2)), []);
  assert.deepEqual(turnIntoOps("bulletList", listItem("bullet")), []);
  assert.deepEqual(turnIntoOps("orderedList", listItem("ordered")), []);
  assert.deepEqual(turnIntoOps("taskList", listItem("task")), []);
  assert.deepEqual(turnIntoOps("quote", blockquote), []);
  assert.deepEqual(turnIntoOps("callout", callout), []);
});

test("a paragraph takes the plain wrap or set commands", () => {
  assert.deepEqual(turnIntoOps("h1", paragraph), ["heading:1"]);
  assert.deepEqual(turnIntoOps("h5", paragraph), ["heading:5"]);
  assert.deepEqual(turnIntoOps("bulletList", paragraph), ["wrap:bulletList"]);
  assert.deepEqual(turnIntoOps("orderedList", paragraph), ["wrap:orderedList"]);
  assert.deepEqual(turnIntoOps("taskList", paragraph), ["wrap:taskList"]);
  assert.deepEqual(turnIntoOps("quote", paragraph), ["wrap:blockquote"]);
  assert.deepEqual(turnIntoOps("callout", paragraph), ["wrap:blockquote", "callout-marker"]);
  assert.deepEqual(turnIntoOps("text", heading(3)), ["paragraph"]);
  assert.deepEqual(turnIntoOps("h4", heading(1)), ["heading:4"]);
});

test("a list item leaves its list before it changes kind", () => {
  assert.deepEqual(turnIntoOps("text", listItem("bullet")), ["lift"]);
  assert.deepEqual(turnIntoOps("h2", listItem("task")), ["lift", "heading:2"]);
  assert.deepEqual(turnIntoOps("quote", listItem("ordered")), ["lift", "wrap:blockquote"]);
  assert.deepEqual(turnIntoOps("callout", listItem("bullet")), [
    "lift",
    "wrap:blockquote",
    "callout-marker",
  ]);
});

test("a list of one changes kind in place, a longer list is split", () => {
  assert.deepEqual(turnIntoOps("orderedList", alone("bullet")), [
    "setListKind:orderedList",
    "setChecked:null",
  ]);
  assert.deepEqual(turnIntoOps("taskList", alone("bullet")), ["setChecked:false"]);
  assert.deepEqual(turnIntoOps("bulletList", alone("task")), [
    "setListKind:bulletList",
    "setChecked:null",
  ]);
  assert.deepEqual(turnIntoOps("orderedList", listItem("bullet")), ["lift", "wrap:orderedList"]);
  assert.deepEqual(turnIntoOps("taskList", listItem("bullet")), ["lift", "wrap:taskList"]);
  assert.deepEqual(turnIntoOps("bulletList", listItem("ordered")), ["lift", "wrap:bulletList"]);
});

test("a blockquote leaves the quote when it becomes another block", () => {
  assert.deepEqual(turnIntoOps("callout", blockquote), ["callout-marker"]);
  assert.deepEqual(turnIntoOps("text", blockquote), ["liftBlock"]);
  assert.deepEqual(turnIntoOps("h2", blockquote), ["liftBlock", "heading:2"]);
  assert.deepEqual(turnIntoOps("bulletList", blockquote), ["liftBlock", "wrap:bulletList"]);
  assert.deepEqual(turnIntoOps("taskList", blockquote), ["liftBlock", "wrap:taskList"]);
});

test("unknown targets convert nothing", () => {
  assert.deepEqual(turnIntoOps("page", paragraph), []);
  assert.deepEqual(turnIntoOps("h6", paragraph), []);
});

test("a heading becomes body text inside a new quote or callout", () => {
  assert.deepEqual(turnIntoOps("quote", heading(4)), ["paragraph", "wrap:blockquote"]);
  assert.deepEqual(turnIntoOps("callout", heading(2)), ["paragraph", "wrap:blockquote", "callout-marker"]);
});
