/**
 * Obsidian-style callout detection for the Kissmark Document surface.
 *
 * A callout is a blockquote whose first paragraph starts with an `[!type]`
 * marker: `> [!note] 제목` on disk, `p("[!note] 제목")` as the first child of a
 * ProseMirror `blockquote`. The marker paragraph is shown as the callout label;
 * it stays part of the document model and the saved Markdown, so the file keeps
 * Obsidian compatibility.
 *
 * The helpers here are pure: they take the paragraph's text (or a ProseMirror
 * node-like object, which the tests fake with plain JSON) and return the type.
 */

/** `[!type]` at the start of a line, followed by optional spacing. */
const MARKER = /^\[!([A-Za-z][A-Za-z0-9_-]*)\][ \t]*/;

/**
 * Callout type of a marker paragraph, or `null` when the text is not a marker.
 * @param {string} text textContent of the callout's first paragraph
 * @returns {string | null} lowercased type (`note`, `warning`, `tip`, ...)
 */
export function calloutType(text) {
  const match = MARKER.exec(text ?? "");
  return match ? match[1].toLowerCase() : null;
}

/** The `[!type] ` marker for a new callout. @param {string} [type] */
export function calloutMarker(type = "note") {
  return `[!${type}] `;
}

/**
 * Callout type of a ProseMirror blockquote node (or a plain object with the
 * same shape: `{ firstChild: { type: { name }, textContent } }`).
 * @param {{ firstChild?: { type?: { name?: string }, textContent?: string } | null } | null} node
 * @returns {string | null}
 */
export function blockquoteCalloutType(node) {
  const first = node?.firstChild;
  if (!first || first.type?.name !== "paragraph") return null;
  return calloutType(first.textContent);
}

/**
 * Callout type of a Markdown blockquote (`> [!warning] 조심`), or `null`.
 * @param {string} markdown one or more blockquote lines
 */
export function calloutTypeFromMarkdown(markdown) {
  const lines = String(markdown ?? "").split(/\r?\n/);
  if (!/^[ \t]*>/.test(lines[0] ?? "")) return null;
  return calloutType(lines[0].replace(/^[ \t]*>[ \t]?/, ""));
}

/**
 * Crepe's Markdown serializer escapes the callout marker as `\[!note]`, which
 * Obsidian does not read as a callout. Every change the surface sends to Swift
 * carries the bare bracket; the document model keeps whatever Crepe holds.
 * @param {string} markdown
 */
export function unescapeCalloutMarkers(markdown) {
  return String(markdown ?? "").replace(/^([ \t]*(?:>[ \t]*)+)\\\[!/gm, "$1[!");
}
