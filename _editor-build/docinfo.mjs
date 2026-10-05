/**
 * Document info bar (polish 1.5, item 1).
 *
 * The floating SwiftUI overlay is gone; the document's path, save state and
 * dates now live in the DOM scroll flow, above the frontmatter box. Swift
 * pushes preformatted data with `KissmarkEditor.setDocumentInfo(info)`:
 *
 *   { path, saveState: "saved"|"saving"|"failed", saveLabel,
 *     modified, created, expanded }
 *
 * `saveLabel` and the dates are already Korean-formatted by Swift; the header
 * (문서 정보, save dot and label) and the row labels (폴더/수정일/생성일) are
 * rendered here. Everything is built with `textContent` — the path is
 * untrusted file-system text. Toggling posts `{ type: "infoExpanded",
 * expanded }` to Swift, which persists the choice and re-sends the info.
 */

import { animateWithToken, cssDuration, cssToken, prefersReducedMotion } from "./motion.mjs";
import { uiText } from "./ui-text.mjs";

/** Row labels rendered by the JS side (Korean UI copy). The save state has
 * no row: the header already shows it, with its status dot (1.7 lint). */
export const DOCINFO_LABELS = {
  path: uiText("폴더"),
  modified: uiText("수정일"),
  created: uiText("생성일"),
};

/**
 * Collapsed header copy (1.6). The file name already sits in the action bar,
 * so the header never repeats it: a fixed title plus the save state.
 */
export const DOCINFO_TITLE = uiText("문서 정보");

/** Location shown for a document at the top of the chosen folder. */
export const DOCINFO_ROOT_FOLDER = uiText("선택한 폴더");

/**
 * The folder that holds `path`, without the file name. Swift sends either a
 * path relative to the chosen folder (`Notes/a.md`) or an absolute one
 * (`/tmp/Notes/a.md`, `~/a.md`). A bare file name sits in the chosen folder;
 * POSIX and Windows separators both work, and the original spelling is kept.
 * @param {string} path
 */
function docinfoFolder(path) {
  if (typeof path !== "string" || path === "") return "";
  let text = path;
  while (text.length > 1 && /[\\/]$/.test(text)) text = text.slice(0, -1);
  const cut = Math.max(text.lastIndexOf("/"), text.lastIndexOf("\\"));
  if (cut === -1) return DOCINFO_ROOT_FOLDER;
  // `/a.md` and `C:\a.md` live in the root itself: keep its separator.
  if (cut === 0 || text.charAt(cut - 1) === ":") return text.slice(0, cut + 1);
  return text.slice(0, cut);
}

/**
 * The details grid: one row per field, Swift's preformatted values as-is.
 * Missing fields collapse to an empty value so the grid never shows
 * "undefined". The path row shows the containing folder, not the file.
 * @returns {Array<{ label: string, value: string }>}
 */
export function docinfoRows(info) {
  const data = info ?? {};
  const value = (key) => {
    const raw = data[key];
    return typeof raw === "string" && raw !== "" ? raw : "";
  };
  return [
    { label: DOCINFO_LABELS.path, value: docinfoFolder(data.path) },
    { label: DOCINFO_LABELS.modified, value: value("modified") },
    { label: DOCINFO_LABELS.created, value: value("created") },
  ];
}

const CHEVRON_SVG =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>';

/** Builds the card once: header button, then the (possibly closed) details panel. */
function buildDocInfo(container) {
  const card = document.createElement("div");
  card.className = "km-di-card";

  const head = document.createElement("button");
  head.type = "button";
  head.className = "km-di-head";
  head.setAttribute("aria-controls", "km-di-details");

  const summary = document.createElement("span");
  summary.className = "km-di-summary";
  summary.textContent = DOCINFO_TITLE;

  const save = document.createElement("span");
  save.className = "km-di-save";

  const chevron = document.createElement("span");
  chevron.className = "km-di-chevron";
  chevron.setAttribute("aria-hidden", "true");
  chevron.innerHTML = CHEVRON_SVG;
  head.append(summary, save, chevron);

  const panel = document.createElement("div");
  panel.className = "km-di-panel";
  panel.id = "km-di-details";
  const grid = document.createElement("div");
  grid.className = "km-di-grid";
  panel.appendChild(grid);

  card.append(head, panel);
  container.appendChild(card);
  return { card, head, save, panel, grid };
}

/** Opens or closes the card; the CSS springs the rows, `inert` keeps a closed panel out of reach. */
function setOpen(parts, open) {
  // Swift re-sends the info (e.g. right after a toggle, with the save-state
  // refresh). Re-applying the state the card already has would replay the
  // accordion spring and jump the layout under the pointer — a gap appearing
  // and disappearing between the action bar and the card. No-op instead.
  if (parts.card.hasAttribute("data-open") === open) return;
  parts.card.toggleAttribute("data-open", open);
  parts.head.setAttribute("aria-expanded", open ? "true" : "false");
  parts.panel.inert = !open;
}

/** Swaps the save label; a change after the first render resolves in from a soft blur. */
function setSaveState(save, info) {
  const label = typeof info.saveLabel === "string" ? info.saveLabel : "";
  const state = typeof info.saveState === "string" ? info.saveState : "";
  save.hidden = label === "";
  save.dataset.kmSaveState = state;
  if (save.textContent === label) return;
  const changed = save.textContent !== "";
  save.textContent = label;
  if (!changed) return;
  animateWithToken(
    save,
    prefersReducedMotion()
      ? [{ opacity: 0 }, { opacity: 1 }]
      : [
          // A caption-sized swap: a third of the rise, half the blur.
          {
            opacity: 0,
            filter: `blur(calc(${cssToken("--km-blur")} / 2))`,
            translate: `0 calc(${cssToken("--km-rise")} / 3)`,
          },
          { opacity: 1, filter: "blur(0px)", translate: "0 0" },
        ],
    { duration: cssDuration("--km-dur-quick"), easing: cssToken("--km-ease-out") },
  );
}

/**
 * Renders `container` (#docinfo) from `info`. Idempotent and in place: the
 * card is built once and later calls only update text and state, so the
 * accordion spring and the save-label crossfade are never cut short by a
 * rebuild (Swift re-sends the info on every save and after each toggle).
 * `onToggle(expanded)` fires from the header button after the local state
 * has flipped; the latest callback wins.
 *
 * @param {HTMLElement} container
 * @param {{ path: string, expanded: boolean } | null} info null hides the bar.
 * @param {{ expanded?: boolean, onToggle?: (expanded: boolean) => void }} state
 */
export function renderDocInfo(container, info, { expanded = false, onToggle } = {}) {
  if (!info) {
    container.hidden = true;
    return expanded;
  }
  container.hidden = false;

  let parts = container._kmDocInfo;
  if (!parts || !container.contains(parts.card)) {
    container.textContent = "";
    parts = container._kmDocInfo = buildDocInfo(container);
    parts.head.addEventListener("click", () => {
      const next = parts.head.getAttribute("aria-expanded") !== "true";
      setOpen(parts, next);
      parts.onToggle?.(next);
    });
  }
  parts.onToggle = typeof onToggle === "function" ? onToggle : null;
  setOpen(parts, expanded);
  setSaveState(parts.save, info);

  const rows = docinfoRows(info);
  if (parts.grid.children.length !== rows.length) {
    parts.grid.textContent = "";
    for (const row of rows) {
      const rowEl = document.createElement("div");
      rowEl.className = "km-di-row";
      const label = document.createElement("span");
      label.className = "km-di-label";
      label.textContent = row.label;
      const valueEl = document.createElement("span");
      valueEl.className = "km-di-value";
      rowEl.append(label, valueEl);
      parts.grid.appendChild(rowEl);
    }
  }
  rows.forEach((row, i) => {
    const valueEl = parts.grid.children[i].lastElementChild;
    if (valueEl.textContent !== row.value) valueEl.textContent = row.value;
  });
  return expanded;
}
