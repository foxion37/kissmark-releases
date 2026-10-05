import assert from "node:assert/strict";
import { test } from "node:test";
import { matchQuote, normalizeQuote, reviewHeadLabel, reviewRows } from "./review.mjs";

const pt = (id, checked) => ({ id, checked });

test("unchecked rows come first, each group keeps its order", () => {
  const rows = reviewRows([pt(1, true), pt(2, false), pt(3, true), pt(4, false)]);
  assert.deepEqual(rows.map((p) => p.id), [2, 4, 1, 3]);
});

test("head label counts only unchecked points and drops the count when none remain", () => {
  const pending = reviewHeadLabel([pt(1, false), pt(2, false), pt(3, true)], "2026-09-30");
  assert.equal(Number(pending.match(/\d+$/)?.[0]), 2);
  assert.equal(/\d/.test(reviewHeadLabel([pt(1, true)], "2026-09-30")), false);
  assert.equal(/\d/.test(reviewHeadLabel([], null)), false);
});


test("quotes normalize to plain collapsed text", () => {
  assert.equal(normalizeQuote("**중요한**  결정"), "중요한 결정");
  assert.equal(normalizeQuote("see [the docs](https://x.y/z) now"), "see the docs now");
  assert.equal(normalizeQuote("- [ ] 할 일\n  이어서"), "할 일 이어서");
  assert.equal(normalizeQuote("> 1. 첫째\n> 2. 둘째"), "첫째 둘째");
  assert.equal(normalizeQuote("`code` and _em_ and my_var"), "code and em and my_var");
});

test("matcher returns offsets into the original text", () => {
  const text = "앞  문장 입니다.   **결정**은 이렇다.";
  const m = matchQuote(text, "문장   입니다.");
  assert.equal(text.slice(m.from, m.to), "문장 입니다.");
  const b = matchQuote("a b c b c", "b c");
  assert.deepEqual(b, { from: 2, to: 5 });
});

test("no match, or an empty quote, gives null", () => {
  assert.equal(matchQuote("hello world", "goodbye"), null);
  assert.equal(matchQuote("hello", "  ** "), null);
});

test("the card's display form drops list markers and link syntax", () => {
  assert.equal(normalizeQuote("- 데이터 마이그레이션이 실패할 수 있으며"), "데이터 마이그레이션이 실패할 수 있으며");
  assert.equal(
    normalizeQuote("외부 API 의 [모니터링 문서](https://example.com) 기준"),
    "외부 API 의 모니터링 문서 기준",
  );
  assert.equal(normalizeQuote(null), "");
});
