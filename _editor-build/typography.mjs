/**
 * 텍스트 정리 (Text Lint): display punctuation the app bans, replaced
 * char-for-char so the result stays predictable. Prose only — the caller
 * (entry.js) skips code blocks and inline code, so code never changes.
 *
 *   — (em dash, U+2014)     → -
 *   – (en dash, U+2013)     → -
 *   · (middle dot, U+00B7)  → ,
 */

/** Matches any character the lint replaces. */
export const BANNED_TYPOGRAPHY = /[\u2013\u2014\u00B7]/;

/** Char-for-char: every replacement is one character wide. */
export function lintTypographyText(text) {
  return text
    .replace(/\u2014/g, "-") // — em dash
    .replace(/\u2013/g, "-") // – en dash
    .replace(/\u00B7/g, ","); // · middle dot
}

/** Presentation only: never promote inline emphasis or nested/list text. */
export function isStrongHeading(node, parent) {
  if (parent?.type.name !== "doc" || node.type.name !== "paragraph"
      || !node.textContent.trim() || /[\r\n]/.test(node.textContent)) return false;
  for (let i = 0; i < node.childCount; i++) {
    const child = node.child(i);
    if (!child.isText || !child.marks.some(mark => mark.type.name === "strong")) return false;
  }
  return true;
}
