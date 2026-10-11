import assert from "node:assert/strict";
import { test } from "node:test";
import { spawnSync } from "node:child_process";
import { EditorState as CMState } from "@codemirror/state";
import { history as cmHistory, undoDepth as cmUndoDepth } from "@codemirror/commands";
import { Schema } from "prosemirror-model";
import { EditorState as PMState, TextSelection } from "prosemirror-state";
import { history as pmHistory, undoDepth as pmUndoDepth } from "prosemirror-history";
import {
  findMatches,
  findProsePlugin,
  findSourceExtension,
  proseFindTransaction,
  sourceFindSpec,
  stepIndex,
  textblockSegments,
} from "./find.mjs";

const seg = (text, start = 0) => [{ start, text }];
const slices = (text, query, options) =>
  findMatches(seg(text), query, options).matches.map((m) => text.slice(m.from, m.to));

/* ------------------------------------------------------------------ matching */

test("literal search is case-insensitive by default and exact on request", () => {
  assert.deepEqual(slices("Kissmark kissmark KISSMARK", "kissmark"), ["Kissmark", "kissmark", "KISSMARK"]);
  assert.deepEqual(slices("Kissmark kissmark KISSMARK", "kissmark", { caseSensitive: true }), ["kissmark"]);
});

test("Korean literals match, composed or decomposed", () => {
  assert.deepEqual(slices("한글 문서와 한글.", "한글"), ["한글", "한글"]);
  const nfd = "한글 문서".normalize("NFD");
  assert.equal(findMatches(seg(nfd), "한글".normalize("NFC")).matches.length, 1);
  assert.equal(findMatches(seg("한글 문서".normalize("NFC")), "한글".normalize("NFD")).matches.length, 1);
});

test("whole word: Korean particles, underscores and punctuation edges", () => {
  assert.deepEqual(slices("한글을 쓴다 한글 한글입니다", "한글", { wholeWord: true }), ["한글"]);
  assert.deepEqual(slices("cat concat cat_ cat, cat", "cat", { wholeWord: true }), ["cat", "cat", "cat"]);
  // The query's own edge is punctuation: only a word character beside a word edge blocks it.
  assert.deepEqual(slices("x(foo)y (foo)", "(foo)", { wholeWord: true }), ["(foo)", "(foo)"]);
  // A rejected hit must not hide a valid one that starts inside it.
  assert.deepEqual(slices("aaa aa", "aa", { wholeWord: true }), ["aa"]);
});

test("regex mode honours the pattern; literal mode never does", () => {
  assert.deepEqual(slices("a1 b22 c333", "[a-z]\\d+", { regex: true }), ["a1", "b22", "c333"]);
  assert.deepEqual(slices("a.b a*b (x)", "a.b", {}), ["a.b"]);
  assert.deepEqual(slices("a*b aab", "a*b", {}), ["a*b"]);
  assert.deepEqual(slices("f(x) f[y] \\", "(", {}), ["("]);
  assert.deepEqual(slices("f(x)", "\\", {}), []);
  assert.deepEqual(slices("ABC abc", "b", { regex: true, caseSensitive: true }), ["b"]);
});

test("regex whole word still applies the boundary", () => {
  assert.deepEqual(slices("ab abc ab", "ab|abc", { regex: true, wholeWord: true }), ["ab", "abc", "ab"]);
});

test("invalid regex reports an error and no matches; literal mode never errors", () => {
  for (const query of ["(", "[a-", "*", "a{2,1}", "(?<n"]) {
    const result = findMatches(seg("a ( [ * b"), query, { regex: true });
    assert.deepEqual(result, { matches: [], error: "invalid-regex" }, query);
    assert.equal(findMatches(seg("a ( [ * b"), query, {}).error, null, query);
  }
});

test("empty query is no search at all", () => {
  assert.deepEqual(findMatches(seg("text"), ""), { matches: [], error: null });
});

test("zero-width regex matches preserve positions and terminate at code-point boundaries", () => {
  assert.deepEqual(findMatches(seg("abc"), "^", { regex: true }).matches, [{ from: 0, to: 0 }]);
  assert.deepEqual(findMatches(seg("a\n\nb"), "$", { regex: true }).matches, [
    { from: 1, to: 1 }, { from: 2, to: 2 }, { from: 4, to: 4 },
  ]);
  assert.deepEqual(findMatches(seg("😀a"), "(?=a)", { regex: true }).matches, [{ from: 2, to: 2 }]);
  assert.deepEqual(slices("baab", "a*", { regex: true }), ["", "aa", "", ""]);
});

test("whole-word matching terminates on supplementary letters and keeps later matches", () => {
  const source = `import {findMatches} from ${JSON.stringify(new URL("./find.mjs", import.meta.url).href)}; console.log(JSON.stringify(findMatches([{start:0,text:"a𐐀b 𐐀"}],"𐐀",{wholeWord:true}).matches));`;
  const result = spawnSync(process.execPath, ["--input-type=module", "-e", source], { encoding: "utf8", timeout: 3000 });
  assert.equal(result.status, 0, "Unicode word-boundary scan must terminate");
  assert.deepEqual(JSON.parse(result.stdout), [{ from: 5, to: 7 }]);
});

test("offsets are absolute and matches never cross segments", () => {
  const segments = [
    { start: 1, text: "foo bar" },
    { start: 20, text: "bar foo" },
  ];
  assert.deepEqual(findMatches(segments, "foo").matches, [
    { from: 1, to: 4 },
    { from: 24, to: 27 },
  ]);
  assert.deepEqual(findMatches(segments, "bar bar").matches, []);
});

test("source text: newlines participate and ^/$ are per line", () => {
  const text = "# 제목\n\n- 항목 one\n- 항목 two\n";
  assert.deepEqual(slices(text, "^- 항목", { regex: true }), ["- 항목", "- 항목"]);
  assert.deepEqual(slices(text, "one\\n- ", { regex: true }), ["one\n- "]);
});

test("query text is never interpreted: markup, quotes and script stay literal", () => {
  const text = `<img src=x onerror=alert(1)> "quoted" \\n \${x} \`tick\``;
  for (const query of ["<img src=x onerror=alert(1)>", '"quoted"', "\\n", "${x}", "`tick`"]) {
    assert.equal(findMatches(seg(text), query).matches.length, 1, query);
  }
});

test("stepIndex wraps both ways and handles empty results", () => {
  assert.equal(stepIndex(-1, 3, 1), 0);
  assert.equal(stepIndex(-1, 3, -1), 2);
  assert.equal(stepIndex(2, 3, 1), 0);
  assert.equal(stepIndex(0, 3, -1), 2);
  assert.equal(stepIndex(1, 1, 1), 0);
  assert.equal(stepIndex(0, 0, 1), -1);
});

/* ------------------------------------------------------ rendered (ProseMirror) */

const schema = new Schema({
  nodes: {
    doc: { content: "block+" },
    paragraph: { group: "block", content: "inline*" },
    text: { group: "inline" },
    image: { group: "inline", inline: true, atom: true },
  },
  marks: { strong: {}, code: {} },
});
const p = (...kids) => schema.node("paragraph", null, kids);
const t = (text, ...marks) => schema.text(text, marks.map((m) => schema.mark(m)));
const classesOf = (state, plugin) =>
  plugin
    .getState(state)
    .find()
    .map((d) => ({ from: d.from, to: d.to, class: d.type.attrs.class }));

test("a match runs across inline formatting and positions address the document", () => {
  const doc = schema.node("doc", null, [
    p(t("한글 "), t("문서", "strong"), t("를 `검색`"), schema.node("image"), t("끝")),
    p(t("x"), t("-ab", "code"), t("c")),
  ]);
  const segments = textblockSegments(doc);
  assert.equal(segments.length, 2);
  for (const [query, expected] of [
    ["글 문서를", "글 문서를"],
    ["abc", "-abc".slice(1)],
    ["끝", "끝"],
  ]) {
    const { matches } = findMatches(segments, query);
    assert.equal(matches.length, 1, query);
    assert.equal(doc.textBetween(matches[0].from, matches[0].to), expected, query);
  }
  // The image placeholder is not text a query can hit.
  assert.equal(findMatches(segments, "검색끝").matches.length, 0);
});

function proseState(doc, plugin) {
  return PMState.create({ doc, plugins: [pmHistory(), plugin] });
}

test("prose highlights are decorations only: no doc change, no history, selection kept", () => {
  const doc = schema.node("doc", null, [p(t("alpha beta alpha")), p(t("Alpha"))]);
  const plugin = findProsePlugin();
  let state = proseState(doc, plugin);
  state = state.apply(state.tr.insertText("!", 1, 1)); // a real user edit: one undo step
  const edited = state.doc;
  state = state.apply(state.tr.setSelection(TextSelection.create(state.doc, 3, 5)));
  const selection = state.selection;
  assert.equal(pmUndoDepth(state), 1);

  const { matches } = findMatches(textblockSegments(state.doc), "alpha");
  assert.equal(matches.length, 3);
  const next = state.apply(proseFindTransaction(state, matches, 1));

  assert.ok(next.doc.eq(edited), "document unchanged");
  assert.equal(pmUndoDepth(next), 1, "no undo entry");
  assert.ok(next.selection.eq(selection), "selection untouched");
  assert.deepEqual(
    classesOf(next, plugin).map((d) => d.class),
    ["km-find-match", "km-find-match km-find-active", "km-find-match"]
  );

  const cleared = next.apply(proseFindTransaction(next, [], -1));
  assert.deepEqual(classesOf(cleared, plugin), []);
  assert.ok(cleared.doc.eq(edited));
  assert.equal(pmUndoDepth(cleared), 1);
});

test("prose highlights follow an edit until the host re-queries", () => {
  const doc = schema.node("doc", null, [p(t("one two one"))]);
  const plugin = findProsePlugin();
  let state = proseState(doc, plugin);
  state = state.apply(proseFindTransaction(state, findMatches(textblockSegments(doc), "one").matches, 0));
  state = state.apply(state.tr.insertText("XX", 1, 1)); // before both matches
  assert.deepEqual(
    classesOf(state, plugin).map(({ from, to }) => state.doc.textBetween(from, to)),
    ["one", "one"]
  );
  // Re-query after the edit: mode/text transition recomputes from the new doc.
  const again = findMatches(textblockSegments(state.doc), "xxone");
  assert.equal(again.matches.length, 1);
});

test("plugin tells the host when the document changed, not on find transactions", () => {
  let calls = 0;
  const plugin = findProsePlugin({ onDocChanged: () => calls++ });
  const view = plugin.spec.view();
  const doc = schema.node("doc", null, [p(t("abc"))]);
  const state = proseState(doc, plugin);
  const find = state.apply(proseFindTransaction(state, [{ from: 1, to: 3 }], 0));
  view.update({ state: find }, state);
  assert.equal(calls, 0);
  const edited = find.apply(find.tr.insertText("z", 1, 1));
  view.update({ state: edited }, find);
  assert.equal(calls, 1);
});

/* ---------------------------------------------------------- source (CodeMirror) */

const sourceState = (doc) => CMState.create({ doc, extensions: [cmHistory(), findSourceExtension] });
const marks = (state) => {
  const out = [];
  state.field(findSourceExtension).between(0, state.doc.length, (from, to, value) => {
    out.push({ from, to, class: value.spec.class });
  });
  return out;
};

test("source highlights are effects only: text, history and selection are untouched", () => {
  const text = "# 제목\n\nalpha Beta alpha\n";
  let state = sourceState(text);
  state = state.update({ changes: { from: 0, to: 0, insert: "> " }, userEvent: "input.type" }).state;
  const edited = state.doc.toString();
  state = state.update({ selection: { anchor: 3, head: 5 } }).state;
  const selection = state.selection.main;
  assert.equal(cmUndoDepth(state), 1);

  const { matches } = findMatches(seg(edited), "alpha");
  const next = state.update(sourceFindSpec(matches, 1, true)).state;

  assert.equal(next.doc.toString(), edited);
  assert.equal(cmUndoDepth(next), 1);
  assert.equal(next.selection.main.from, selection.from);
  assert.equal(next.selection.main.to, selection.to);
  assert.deepEqual(
    marks(next).map((m) => [edited.slice(m.from, m.to), m.class]),
    [
      ["alpha", "km-find-match"],
      ["alpha", "km-find-match km-find-active"],
    ]
  );
  assert.deepEqual(marks(next.update(sourceFindSpec([], -1)).state), []);
});

test("source highlights are mapped through edits and clamped to the document", () => {
  let state = sourceState("one two one");
  state = state.update(sourceFindSpec(findMatches(seg("one two one"), "one").matches, 0)).state;
  state = state.update({ changes: { from: 0, to: 0, insert: "ZZ" } }).state;
  assert.deepEqual(
    marks(state).map((m) => state.doc.sliceString(m.from, m.to)),
    ["one", "one"]
  );
  // A stale request (longer text than the doc now holds) must not throw or paint outside.
  const shrunk = state.update({ changes: { from: 0, to: state.doc.length, insert: "one" } }).state;
  const stale = shrunk.update(sourceFindSpec([{ from: 0, to: 3 }, { from: 8, to: 20 }], 0)).state;
  assert.deepEqual(marks(stale).map((m) => [m.from, m.to]), [[0, 3]]);
});

test("render → source → render re-query finds the same text in both coordinate systems", () => {
  const source = "한글 **문서**를 검색\n\n다음 문서\n";
  const doc = schema.node("doc", null, [p(t("한글 "), t("문서", "strong"), t("를 검색")), p(t("다음 문서"))]);
  const inSource = findMatches(seg(source), "문서").matches;
  const inRender = findMatches(textblockSegments(doc), "문서").matches;
  assert.equal(inSource.length, 2);
  assert.equal(inRender.length, 2);
  assert.deepEqual(
    inRender.map((m) => doc.textBetween(m.from, m.to)),
    ["문서", "문서"]
  );
  // Source also sees the markup characters render hides.
  assert.equal(findMatches(seg(source), "**문서**").matches.length, 1);
  assert.equal(findMatches(textblockSegments(doc), "**문서**").matches.length, 0);
});
