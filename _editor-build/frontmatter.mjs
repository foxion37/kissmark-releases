/**
 * Frontmatter handling for the Kissmark Document surface.
 *
 * Kissmark never edits frontmatter: the raw `---` block is peeled off before the
 * Markdown body goes into Crepe and is glued back verbatim on the way out. The
 * raw bytes (BOM, CRLF, interior whitespace, closing fence spelling) are
 * preserved exactly, so an untouched document round-trips byte-for-byte.
 *
 * Supported fences: the opening line must be `---` at offset 0 (optionally after
 * a UTF-8 BOM); the block ends at the first following line that is exactly `---`
 * or `...` (trailing spaces/tabs allowed). A block with no closing line is not
 * frontmatter.
 *
 * Plausibility guard: a `---` run is also how Markdown writes a thematic break,
 * and `---\n\ntext\n\n---\n\nmore` is a body, not metadata. A block only counts
 * as frontmatter when its interior holds at least one mapping line
 * (`key: value`), which is what a properties box can actually show. Everything
 * else stays body, untouched.
 */

const OPEN_FENCE = /^---[ \t]*\r?\n/;
const CLOSE_FENCE = /^(---|\.\.\.)[ \t]*$/;
const KEY_VALUE = /^([^\s:][^\s:]*):[ \t]?(.*)$/;

/** @typedef {{ front: string, body: string }} FrontmatterSplit */
/** @typedef {{ key: string, value: string } | { raw: string }} FrontmatterRow */

/**
 * Locates a fenced block at offset 0, without judging whether it is metadata.
 *
 * @param {string} text
 * @returns {{ front: string, interior: string, body: string } | null} `front`
 *   includes the BOM, both fences, and a trailing newline when the source had one.
 */
function matchFencedBlock(text) {
  let bom = "";
  let rest = text;
  if (rest.charCodeAt(0) === 0xfeff) {
    bom = rest.charAt(0);
    rest = rest.slice(1);
  }
  const open = OPEN_FENCE.exec(rest);
  if (!open) return null;

  let index = open[0].length;
  while (index <= rest.length) {
    const newline = rest.indexOf("\n", index);
    const stop = newline === -1 ? rest.length : newline;
    const line = rest.slice(index, stop).replace(/\r$/, "");
    if (CLOSE_FENCE.test(line)) {
      const closeEnd = newline === -1 ? rest.length : newline + 1;
      return {
        front: bom + rest.slice(0, closeEnd),
        interior: rest.slice(open[0].length, index),
        body: rest.slice(closeEnd),
      };
    }
    if (newline === -1) break;
    index = newline + 1;
  }
  return null;
}

function interiorLines(interior) {
  return (typeof interior === "string" ? interior : "").split("\n").map((line) =>
    line.endsWith("\r") ? line.slice(0, -1) : line
  );
}

/** @returns {boolean} whether the interior holds at least one `key: value` line. */
function hasMappingLine(interior) {
  return interiorLines(interior).some((line) => KEY_VALUE.test(line));
}

/**
 * @param {string} markdown
 * @returns {FrontmatterSplit} `front + body` is always the original string.
 */
export function splitFrontmatter(markdown) {
  const text = typeof markdown === "string" ? markdown : "";
  const block = matchFencedBlock(text);
  if (!block || !hasMappingLine(block.interior)) return { front: "", body: text };
  return { front: block.front, body: block.body };
}

/**
 * Glues the raw block back in front of the body.
 *
 * A document that ends at its closing fence has no trailing line ending, so a
 * body the user then types would otherwise concatenate into `---# Body`. When
 * the body is non-empty and neither side already supplies a line break, insert
 * exactly one (matching the block's own LF/CRLF style).
 *
 * @param {string} front
 * @param {string} body
 */
export function joinFrontmatter(front, body) {
  const rawFront = typeof front === "string" ? front : "";
  const rawBody = typeof body === "string" ? body : "";
  if (!rawFront || !rawBody) return rawFront + rawBody;
  if (rawFront.endsWith("\n") || rawBody.startsWith("\n")) return rawFront + rawBody;
  return rawFront + (rawFront.includes("\r\n") ? "\r\n" : "\n") + rawBody;
}

/**
 * File name without its last extension (`Notes/Note.md` → `Note`), NFC so a
 * decomposed macOS path compares equal to typed Hangul.
 * @param {string} path
 */
function fileStem(path) {
  if (typeof path !== "string") return "";
  const name = path.split(/[\\/]/).filter((part) => part !== "").pop() ?? "";
  const dot = name.lastIndexOf(".");
  return (dot > 0 ? name.slice(0, dot) : name).normalize("NFC");
}

/** A scalar with one pair of matching outer quotes and surrounding whitespace removed. */
function plainScalar(value) {
  const text = value.trim();
  const quoted = text.length >= 2 && (text[0] === '"' || text[0] === "'") && text.at(-1) === text[0];
  return (quoted ? text.slice(1, -1).trim() : text).normalize("NFC");
}

/**
 * Row list for the read-only properties box: `key: value` lines become key/value
 * rows; comments, list items, and anything else stay raw. Never returns HTML.
 * With the document's `path`, a `title` that only repeats the file name is left
 * out (the action bar already shows it); any other title stays. Display only:
 * the raw block is never touched.
 *
 * @param {string} front
 * @param {string} [path]
 * @returns {FrontmatterRow[]}
 */
export function frontmatterRows(front, path) {
  const text = typeof front === "string" ? front : "";
  const block = matchFencedBlock(text);
  if (!block || !hasMappingLine(block.interior)) return [];

  const stem = fileStem(path);
  const rows = [];
  const lines = interiorLines(block.interior);
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index];
    if (line.trim() === "") continue;
    const pair = KEY_VALUE.exec(line);
    if (pair) {
      let next = index + 1;
      while (next < lines.length && lines[next].trim() === "") next++;
      const continues = next < lines.length && /^[ \t]/.test(lines[next]);
      if (stem !== "" && pair[1] === "title" && plainScalar(pair[2]) === stem && !continues) continue;
      rows.push({ key: pair[1], value: pair[2] });
    } else {
      rows.push({ raw: line });
    }
  }
  return rows;
}
