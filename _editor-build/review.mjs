/**
 * Review card (round 3): the in-flow 검토 card under 문서 정보, and the pure
 * helpers the body highlights use. Every string is untrusted (agent text), so
 * the DOM is built with textContent only. Idempotent in place, like docinfo.
 */

import { uiText } from "./ui-text.mjs";

export const REVIEW_TITLE = uiText("검토");
export const REVIEW_DONE_HEAD = uiText("검토 완료됨");
export const REVIEW_EMPTY = uiText("검토할 포인트가 없습니다.");
export const REVIEW_COMPLETE = uiText("검토 완료");
export const REVIEW_COMMENT_PLACEHOLDER = uiText("코멘트 (선택)");

export const REVIEW_KIND_LABELS = {
  agent: uiText("에이전트"),
  decision: uiText("결정"),
  warning: uiText("경고"),
  failure: uiText("실패"),
  next: uiText("다음"),
  task: uiText("할 일"),
  changed: uiText("변경"),
};

/** Unchecked points first, then checked ones; each group keeps its created order. */
export function reviewRows(points) {
  const list = Array.isArray(points) ? points : [];
  return [...list.filter((p) => !p.checked), ...list.filter((p) => p.checked)];
}

/** `검토 3` while points are unchecked; `검토 완료됨` once none are and a completion exists. */
export function reviewHeadLabel(points, completedLabel) {
  const open = (Array.isArray(points) ? points : []).filter((p) => !p.checked).length;
  if (open > 0) return `${REVIEW_TITLE} ${open}`;
  return completedLabel ? REVIEW_DONE_HEAD : REVIEW_TITLE;
}

export function reviewKindLabel(kind) {
  return REVIEW_KIND_LABELS[kind] ?? REVIEW_KIND_LABELS.agent;
}

/**
 * A quote as plain text: inline Markdown markers stripped, whitespace
 * collapsed. Leading list and quote markers go per line, so a multi-line
 * quote joins into one run of words.
 */
export function normalizeQuote(quote) {
  return String(quote ?? "")
    .split("\n")
    .map((line) => line.replace(/^\s*(?:>\s*)*(?:(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?)?/, ""))
    .join(" ")
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/`+/g, "")
    .replace(/\*+/g, "")
    // Emphasis underscores only; `snake_case` keeps its own.
    .replace(/(^|[^\p{L}\p{N}])_+|_+(?=[^\p{L}\p{N}]|$)/gu, "$1")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Finds `quote` (normalized here) inside `text` with whitespace collapsed the
 * same way. Returns `{ from, to }` as offsets into the ORIGINAL `text`
 * (`to` exclusive), or null. First match wins.
 */
export function matchQuote(text, quote) {
  const needle = normalizeQuote(quote);
  if (!needle) return null;
  let hay = "";
  const map = [];
  let inSpace = false;
  for (let i = 0; i < text.length; i++) {
    if (/\s/.test(text[i])) {
      if (inSpace) continue;
      inSpace = true;
      hay += " ";
    } else {
      inSpace = false;
      hay += text[i];
    }
    map.push(i);
  }
  const at = hay.indexOf(needle);
  if (at < 0) return null;
  return { from: map[at], to: map[at + needle.length - 1] + 1 };
}

const CHEVRON_SVG =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>';
const CHECK_SVG =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>';

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

function setText(node, text) {
  if (node.textContent !== text) node.textContent = text;
}

function buildCard(container) {
  const card = el("div", "km-di-card");
  const head = el("button", "km-di-head");
  head.type = "button";
  head.setAttribute("aria-controls", "km-rv-details");
  const summary = el("span", "km-di-summary");
  const chevron = el("span", "km-di-chevron");
  chevron.setAttribute("aria-hidden", "true");
  chevron.innerHTML = CHEVRON_SVG;
  head.append(summary, chevron);

  const panel = el("div", "km-di-panel");
  panel.id = "km-rv-details";
  const inner = el("div", "km-rv-inner");
  const list = el("div", "km-rv-list");
  const empty = el("div", "km-rv-empty", REVIEW_EMPTY);
  const foot = el("div", "km-rv-foot");
  const complete = el("button", "km-rv-complete", REVIEW_COMPLETE);
  complete.type = "button";
  const done = el("span", "km-rv-done");
  foot.append(complete, done);
  inner.append(list, empty, foot);
  panel.appendChild(inner);

  card.append(head, panel);
  container.appendChild(card);
  return { card, head, summary, panel, list, empty, complete, done, rows: new Map(), cb: {} };
}

function setOpen(parts, open) {
  if (parts.card.hasAttribute("data-open") === open) return;
  parts.card.toggleAttribute("data-open", open);
  parts.head.setAttribute("aria-expanded", open ? "true" : "false");
  parts.panel.inert = !open;
}

function buildRow(parts) {
  const row = el("div", "km-rv-row");
  const check = el("button", "km-rv-check");
  check.type = "button";
  check.innerHTML = CHECK_SVG;
  const body = el("div", "km-rv-body");
  const kind = el("span", "km-rv-kind");
  const quote = el("button", "km-rv-quote");
  quote.type = "button";
  const note = el("div", "km-rv-note");
  const comment = el("input", "km-rv-comment");
  comment.type = "text";
  comment.placeholder = REVIEW_COMMENT_PLACEHOLDER;
  comment.setAttribute("aria-label", REVIEW_COMMENT_PLACEHOLDER);
  body.append(kind, quote, note, comment);
  row.append(check, body);

  const r = { row, check, kind, quote, note, comment, id: 0, checked: false, known: "" };
  check.addEventListener("click", () => (r.checked ? parts.cb.onUncheck : parts.cb.onCheck)?.(r.id));
  quote.addEventListener("click", () => parts.cb.onReveal?.(r.id));
  comment.addEventListener("keydown", (event) => {
    if (event.key === "Enter") comment.blur();
  });
  comment.addEventListener("blur", () => {
    if (!r.checked || comment.value === r.known) return;
    r.known = comment.value;
    parts.cb.onComment?.(r.id, comment.value);
  });
  return r;
}

function updateRow(r, p) {
  r.id = p.id;
  r.checked = Boolean(p.checked);
  const kind = REVIEW_KIND_LABELS[p.kind] ? p.kind : "agent";
  r.row.dataset.kind = kind;
  r.row.toggleAttribute("data-checked", r.checked);
  r.check.setAttribute("aria-pressed", r.checked ? "true" : "false");
  r.check.setAttribute("aria-label", reviewKindLabel(kind));
  setText(r.kind, reviewKindLabel(kind));
  setText(r.quote, normalizeQuote(p.quote));
  const note = typeof p.note === "string" ? p.note : "";
  setText(r.note, note);
  r.note.hidden = note === "";
  r.comment.hidden = !r.checked;
  const comment = typeof p.comment === "string" ? p.comment : "";
  r.known = comment;
  // Never overwrite what the reader is typing.
  if (document.activeElement !== r.comment && r.comment.value !== comment) r.comment.value = comment;
}

/**
 * Renders `container` (#review) from `review` (null hides it). Rows are keyed
 * by point id and updated in place, so a typed comment and the accordion
 * spring survive the push that follows every action.
 *
 * @param {HTMLElement} container
 * @param {{ points: object[], completedLabel: string|null, expanded: boolean } | null} review
 * @param {{ onCheck?, onUncheck?, onComment?, onComplete?, onToggle?, onReveal? }} callbacks
 */
export function renderReview(container, review, callbacks = {}) {
  if (!review) {
    container.hidden = true;
    return;
  }
  container.hidden = false;

  let parts = container._kmReview;
  if (!parts || !container.contains(parts.card)) {
    container.textContent = "";
    parts = container._kmReview = buildCard(container);
    parts.head.addEventListener("click", () => {
      const next = parts.head.getAttribute("aria-expanded") !== "true";
      setOpen(parts, next);
      parts.cb.onToggle?.(next);
    });
    parts.complete.addEventListener("click", () => parts.cb.onComplete?.());
  }
  parts.cb = callbacks;
  setOpen(parts, Boolean(review.expanded));

  const points = Array.isArray(review.points) ? review.points : [];
  const completedLabel = typeof review.completedLabel === "string" ? review.completedLabel : "";
  setText(parts.summary, reviewHeadLabel(points, completedLabel));
  setText(parts.done, completedLabel ? `${REVIEW_COMPLETE}: ${completedLabel}` : "");
  parts.done.hidden = completedLabel === "";
  parts.empty.hidden = points.length > 0;

  const ordered = reviewRows(points);
  const live = new Set(ordered.map((p) => p.id));
  for (const [id, r] of parts.rows) {
    if (!live.has(id)) {
      r.row.remove();
      parts.rows.delete(id);
    }
  }
  ordered.forEach((p, i) => {
    let r = parts.rows.get(p.id);
    if (!r) parts.rows.set(p.id, (r = buildRow(parts)));
    updateRow(r, p);
    if (parts.list.children[i] !== r.row) parts.list.insertBefore(r.row, parts.list.children[i] ?? null);
  });
}
