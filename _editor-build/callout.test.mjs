import assert from "node:assert/strict";
import test from "node:test";

import {
  blockquoteCalloutType,
  calloutMarker,
  calloutType,
  calloutTypeFromMarkdown,
  unescapeCalloutMarkers,
} from "./callout.mjs";

/** Minimal ProseMirror-shaped blockquote: doc > blockquote > paragraph > text. */
function blockquoteJson(text) {
  return {
    type: { name: "blockquote" },
    firstChild: {
      type: { name: "paragraph" },
      textContent: text,
      content: [{ type: { name: "text" }, text }],
    },
  };
}

test("a marker paragraph names its callout type", () => {
  assert.equal(calloutType("[!note] 읽어 주세요"), "note");
  assert.equal(calloutType("[!WARNING] 조심"), "warning");
  assert.equal(calloutType("[!tip]"), "tip");
  assert.equal(calloutType("[!todo]- 접힌 콜아웃"), "todo");
});

test("plain text and other brackets are not callouts", () => {
  assert.equal(calloutType("그냥 문단입니다"), null);
  assert.equal(calloutType("[note] 대괄호만"), null);
  assert.equal(calloutType("앞에 글자가 [!note]"), null);
  assert.equal(calloutType(""), null);
  assert.equal(calloutType(undefined), null);
});

test("the marker is detected in ProseMirror blockquote JSON", () => {
  assert.equal(blockquoteCalloutType(blockquoteJson("[!danger] 되돌릴 수 없음")), "danger");
  assert.equal(blockquoteCalloutType(blockquoteJson("인용문입니다")), null);
  assert.equal(blockquoteCalloutType({ type: { name: "blockquote" }, firstChild: null }), null);
  assert.equal(blockquoteCalloutType(null), null);
  // A first child that is not a paragraph (e.g. a nested list) is not a callout.
  assert.equal(
    blockquoteCalloutType({
      type: { name: "blockquote" },
      firstChild: { type: { name: "bullet_list" }, textContent: "[!note] x" },
    }),
    null,
  );
});

test("the marker is detected in Obsidian markdown", () => {
  assert.equal(calloutTypeFromMarkdown("> [!note] 제목\n> 본문"), "note");
  assert.equal(calloutTypeFromMarkdown(">[!summary] 요약"), "summary");
  assert.equal(calloutTypeFromMarkdown("> 인용문\n> [!note] 두 번째 줄"), null);
  assert.equal(calloutTypeFromMarkdown("[!note] 인용이 아님"), null);
  assert.equal(calloutTypeFromMarkdown(""), null);
});

test("the new-callout marker spells Obsidian's syntax", () => {
  assert.equal(calloutMarker(), "[!note] ");
  assert.equal(calloutMarker("warning"), "[!warning] ");
});

test("Crepe's escaped callout marker is unescaped for the file", () => {
  assert.equal(unescapeCalloutMarkers("> \\[!note] 제목\n> 본문\n"), "> [!note] 제목\n> 본문\n");
  assert.equal(unescapeCalloutMarkers("> > \\[!tip] 중첩\n"), "> > [!tip] 중첩\n");
  // Only quoted markers: a plain escaped bracket is left alone.
  assert.equal(unescapeCalloutMarkers("\\[!note] 대괄호\n"), "\\[!note] 대괄호\n");
  assert.equal(unescapeCalloutMarkers("> 일반 인용\n"), "> 일반 인용\n");
  assert.equal(unescapeCalloutMarkers(""), "");
});
