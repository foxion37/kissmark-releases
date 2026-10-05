import assert from "node:assert/strict";
import test from "node:test";

import { Schema } from "@milkdown/kit/prose/model";
import { BANNED_TYPOGRAPHY, isStrongHeading, lintTypographyText } from "./typography.mjs";

test("em dash, en dash, and middle dot map to plain equivalents", () => {
  assert.equal(lintTypographyText("A — B"), "A - B");
  assert.equal(lintTypographyText("2020–2024"), "2020-2024");
  assert.equal(lintTypographyText("사과·배·포도"), "사과,배,포도");
});

test("plain text passes through untouched", () => {
  const text = "일반 문장, 하이픈 - 숫자 123, 하트 ♥";
  assert.equal(lintTypographyText(text), text);
});

test("repeated and mixed banned characters all change", () => {
  assert.equal(lintTypographyText("—–·"), "--,");
  assert.equal(BANNED_TYPOGRAPHY.test("—–·"), true);
});

test("every replacement stays one character wide (positions never shift)", () => {
  for (const original of ["—", "–", "·"]) {
    assert.equal([...lintTypographyText(original)].length, 1);
  }
  assert.equal(BANNED_TYPOGRAPHY.test("AB"), false);
});

test("only an entirely bold top-level paragraph becomes a visual subheading", () => {
  const schema = new Schema({
    nodes: {
      doc: { content: "block+" },
      paragraph: { group: "block", content: "inline*" },
      text: { group: "inline" },
      hard_break: { group: "inline", inline: true },
      blockquote: { group: "block", content: "block+" },
    },
    marks: { strong: {}, emphasis: {} },
  });
  const bold = schema.marks.strong.create();
  const text = (value, marks = []) => schema.text(value, marks);
  const paragraph = (...content) => schema.nodes.paragraph.create(null, content);
  const whole = paragraph(text("Small ", [bold]), text("heading", [bold, schema.marks.emphasis.create()]));
  const doc = schema.nodes.doc.create(null, whole);
  assert.equal(isStrongHeading(whole, doc), true);
  for (const ordinary of [
    paragraph(text("Prefix "), text("bold", [bold])),
    paragraph(text("bold", [bold]), text(" suffix")),
    paragraph(text("   ", [bold])),
    paragraph(text("one\ntwo", [bold])),
    paragraph(text("one", [bold]), schema.nodes.hard_break.create(), text("two", [bold])),
    paragraph(),
  ]) assert.equal(isStrongHeading(ordinary, doc), false);
  assert.equal(isStrongHeading(whole, schema.nodes.blockquote.create(null, whole)), false);
});
