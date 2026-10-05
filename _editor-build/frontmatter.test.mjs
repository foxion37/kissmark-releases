import assert from "node:assert/strict";
import test from "node:test";

import { frontmatterRows, joinFrontmatter, splitFrontmatter } from "./frontmatter.mjs";

/** Round-trips through split/join and asserts the bytes are unchanged. */
function assertRoundTrip(markdown) {
  const { front, body } = splitFrontmatter(markdown);
  assert.equal(joinFrontmatter(front, body), markdown);
  return { front, body };
}

test("no frontmatter leaves the whole document as body", () => {
  const markdown = "# Title\n\nBody text\n";
  const { front, body } = assertRoundTrip(markdown);
  assert.equal(front, "");
  assert.equal(body, markdown);
});

test("a document that is only frontmatter round-trips", () => {
  const markdown = "---\ntitle: Only\n---\n";
  const { front, body } = assertRoundTrip(markdown);
  assert.equal(front, markdown);
  assert.equal(body, "");
});

test("frontmatter with a body round-trips", () => {
  const markdown = "---\ntitle: Hi\ntags: [a, b]\n---\n# Heading\n\ntext\n";
  const { front, body } = assertRoundTrip(markdown);
  assert.equal(front, "---\ntitle: Hi\ntags: [a, b]\n---\n");
  assert.equal(body, "# Heading\n\ntext\n");
});

test("a thematic break in the body is not mistaken for a fence", () => {
  const markdown = "---\ntitle: Hi\n---\nbefore\n\n---\n\nafter\n";
  const { front, body } = assertRoundTrip(markdown);
  assert.equal(front, "---\ntitle: Hi\n---\n");
  assert.equal(body, "before\n\n---\n\nafter\n");
});

test("a leading thematic break without a closing fence is not frontmatter", () => {
  const markdown = "---\n\njust a break, no frontmatter\n";
  const { front, body } = assertRoundTrip(markdown);
  assert.equal(front, "");
  assert.equal(body, markdown);
});

test("two thematic breaks are body, not metadata", () => {
  const markdown = "---\n\nfirst\n\n---\n\nmiddle\n\n---\n\nlast\n";
  const { front, body } = assertRoundTrip(markdown);
  assert.equal(front, "");
  assert.equal(body, markdown);
  assert.deepEqual(frontmatterRows(markdown), []);
});

test("a fenced run with no mapping line stays body", () => {
  const markdown = "---\n# only a comment\n- a list item\n---\nbody\n";
  const { front, body } = assertRoundTrip(markdown);
  assert.equal(front, "");
  assert.equal(body, markdown);
  assert.deepEqual(frontmatterRows(markdown), []);
});

test("prose with a colon is not a mapping line", () => {
  const markdown = "---\n\nSee http://example.com: it is a link\n\n---\n";
  const { front } = assertRoundTrip(markdown);
  assert.equal(front, "");
});

test("`...` closes the block", () => {
  const markdown = "---\ntitle: Hi\n...\nbody\n";
  const { front, body } = assertRoundTrip(markdown);
  assert.equal(front, "---\ntitle: Hi\n...\n");
  assert.equal(body, "body\n");
});

test("CRLF line endings are preserved byte-for-byte", () => {
  const markdown = "---\r\ntitle: Hi\r\n---\r\nbody\r\n";
  const { front, body } = assertRoundTrip(markdown);
  assert.equal(front, "---\r\ntitle: Hi\r\n---\r\n");
  assert.equal(body, "body\r\n");
});

test("a leading BOM is preserved and does not hide the fence", () => {
  const markdown = "\uFEFF---\ntitle: Hi\n---\nbody\n";
  const { front, body } = assertRoundTrip(markdown);
  assert.equal(front, "\uFEFF---\ntitle: Hi\n---\n");
  assert.equal(body, "body\n");
});

test("interior blank lines and trailing spaces are preserved", () => {
  const markdown = "---\ntitle: Hi\n\nnum: 1  \n---\nbody\n";
  const { front, body } = assertRoundTrip(markdown);
  assert.equal(front, "---\ntitle: Hi\n\nnum: 1  \n---\n");
  assert.equal(body, "body\n");
});

test("a closing fence without a trailing newline still ends the block", () => {
  const markdown = "---\ntitle: Hi\n---";
  const { front, body } = assertRoundTrip(markdown);
  assert.equal(front, markdown);
  assert.equal(body, "");
});

test("a body typed after a front-only document gets one separating LF", () => {
  assert.equal(joinFrontmatter("---\ntitle: Hi\n---", "# Body\n"), "---\ntitle: Hi\n---\n# Body\n");
});

test("a body typed after a CRLF front-only document gets one separating CRLF", () => {
  assert.equal(
    joinFrontmatter("---\r\ntitle: Hi\r\n---", "# Body\r\n"),
    "---\r\ntitle: Hi\r\n---\r\n# Body\r\n"
  );
});

test("an empty body joins exactly", () => {
  assert.equal(joinFrontmatter("---\ntitle: Hi\n---", ""), "---\ntitle: Hi\n---");
  assert.equal(joinFrontmatter("", "# Body\n"), "# Body\n");
  assert.equal(joinFrontmatter("", ""), "");
});

test("a body that already starts with a newline is not double-separated", () => {
  assert.equal(joinFrontmatter("---\ntitle: Hi\n---", "\n# Body\n"), "---\ntitle: Hi\n---\n# Body\n");
});

test("rows split key/value lines and keep anything else raw", () => {
  const rows = frontmatterRows("---\ntitle: Hi\n# a comment\nlist:\n  - one\nraw line\n---\n");
  assert.deepEqual(rows, [
    { key: "title", value: "Hi" },
    { raw: "# a comment" },
    { key: "list", value: "" },
    { raw: "  - one" },
    { raw: "raw line" },
  ]);
});

test("rows keep a colon inside the value", () => {
  assert.deepEqual(frontmatterRows("---\nurl: https://example.com/a\n---\n"), [
    { key: "url", value: "https://example.com/a" },
  ]);
});

test("rows accept a non-ASCII key", () => {
  assert.deepEqual(frontmatterRows("---\n제목: 문서\n---\n"), [{ key: "제목", value: "문서" }]);
});

test("rows ignore a BOM and CRLF endings", () => {
  assert.deepEqual(frontmatterRows("\uFEFF---\r\ntitle: Hi\r\n---\r\n"), [
    { key: "title", value: "Hi" },
  ]);
});

test("rows for a plain document are empty", () => {
  assert.deepEqual(frontmatterRows("# Title\n"), []);
  assert.deepEqual(frontmatterRows(""), []);
});

test("the read-only properties box omits only a redundant file title", () => {
  const front = "---\ntitle: \"Note\"\nauthor: Q\n---\n";
  assert.deepEqual(frontmatterRows(front, "Notes/Note.md"), [{ key: "author", value: "Q" }]);
  assert.deepEqual(frontmatterRows(front, "Notes/Other.md"), [
    { key: "title", value: "\"Note\"" }, { key: "author", value: "Q" },
  ]);
});

test("a continuing title is not mistaken for a duplicate filename", () => {
  const front = "---\ntitle: Note\n  Part 2\nauthor: Q\n---\n";
  assert.deepEqual(frontmatterRows(front, "Notes/Note.md"), [
    { key: "title", value: "Note" },
    { raw: "  Part 2" },
    { key: "author", value: "Q" },
  ]);
});
