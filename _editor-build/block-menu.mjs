/**
 * Kissmark's own "블록 전환" popover (spec item 7).
 *
 * Crepe's block handle has no menu hook, so the surface builds one: a search
 * field plus the conversion list, anchored to the block the handle points at.
 * The DOM is local, built with createElement, and styled by `reader.css` with
 * the `--km-*` tokens. The only markup that goes through innerHTML is our own
 * icon set in `icons.mjs`.
 */

import { CHECK_GLYPH, MENU_GLYPHS } from "./icons.mjs";
import { TURN_INTO_ITEMS } from "./turn-into.mjs";
import { uiText } from "./ui-text.mjs";

const MAX_HEIGHT = 320;

/** @param {HTMLElement} el @param {string} glyph SVG markup or a short monogram. */
function setGlyph(el, glyph) {
  if (glyph.startsWith("<")) el.innerHTML = glyph;
  else el.textContent = glyph;
}

/**
 * @param {{ onSelect: (key: string) => void }} options
 */
export function createBlockMenu({ onSelect, onClose }) {
  const root = document.createElement("div");
  root.className = "km-block-menu";
  root.hidden = true;
  root.setAttribute("role", "dialog");
  root.setAttribute("aria-label", uiText("블록 전환"));

  const search = document.createElement("input");
  search.type = "text";
  search.className = "km-bm-search";
  search.placeholder = uiText("블록 전환");
  search.setAttribute("aria-label", uiText("블록 검색"));
  search.setAttribute("role", "combobox");
  search.setAttribute("aria-expanded", "true");
  search.setAttribute("autocomplete", "off");
  search.setAttribute("spellcheck", "false");

  const list = document.createElement("div");
  list.className = "km-bm-list";
  list.setAttribute("role", "listbox");
  list.setAttribute("aria-label", uiText("전환"));

  const label = document.createElement("div");
  label.className = "km-bm-group-label";
  label.textContent = uiText("전환");

  root.append(search, label, list);
  document.body.appendChild(root);

  /** @type {{ row: HTMLButtonElement, key: string }[]} */
  let rows = [];
  let highlighted = 0;
  /** Menu key of the block the menu was opened for (check mark, filter default). */
  let blockKey = null;
  /** Height of the last opened menu, to pick the opening side before measuring. */
  let lastHeight = null;

  function highlight(index) {
    if (rows.length === 0) return;
    highlighted = (index + rows.length) % rows.length;
    rows.forEach((entry, i) => {
      const on = i === highlighted;
      entry.row.classList.toggle("is-active", on);
      entry.row.setAttribute("aria-selected", on ? "true" : "false");
    });
    search.setAttribute("aria-activedescendant", rows[highlighted].row.id);
    rows[highlighted].row.scrollIntoView({ block: "nearest" });
  }

  function fill() {
    const filter = search.value.trim().toLowerCase();
    list.textContent = "";
    rows = [];
    for (const item of TURN_INTO_ITEMS) {
      if (filter && !item.label.toLowerCase().includes(filter)) continue;
      const row = document.createElement("button");
      row.type = "button";
      row.className = "km-bm-item";
      row.id = `km-bm-${item.key}`;
      row.dataset.key = item.key;
      row.setAttribute("role", "option");
      row.setAttribute("aria-selected", "false");

      const icon = document.createElement("span");
      icon.className = "km-bm-icon";
      setGlyph(icon, MENU_GLYPHS[item.key] ?? "");

      const text = document.createElement("span");
      text.className = "km-bm-label";
      text.textContent = item.label;

      const check = document.createElement("span");
      check.className = "km-bm-check";
      if (item.key === blockKey) setGlyph(check, CHECK_GLYPH);

      row.append(icon, text, check);
      list.appendChild(row);
      rows.push({ row, key: item.key });
    }
    const current = rows.findIndex((entry) => entry.key === blockKey);
    highlight(current < 0 ? 0 : current);
  }

  function select(key) {
    close();
    onSelect(key);
  }

  function close() {
    if (root.hidden) return;
    const hadFocus = root.contains(document.activeElement);
    root.hidden = true;
    rows = [];
    // The list and query stay until the next open() refills them, so the
    // closing fade shows the menu as it was instead of an emptied box.
    // Hand the keyboard back to the editor instead of a hidden input.
    if (hadFocus) onClose?.();
  }

  function isOpen() {
    return !root.hidden;
  }

  /** Shows the menu next to `rect` (the block handle or the caret line). */
  function open(rect, currentKey) {
    blockKey = currentKey;
    search.value = "";
    fill();
    // The side is chosen before the menu shows, so its opening pop starts from
    // the anchor: from the last measured height (or the cap) until measured.
    const fits = (height) => rect.bottom + 6 + height <= window.innerHeight - 8;
    root.dataset.side = fits(lastHeight ?? MAX_HEIGHT) ? "below" : "above";
    root.hidden = false;
    // Layout size, not the rect: the opening pop starts scaled down.
    const width = root.offsetWidth;
    const height = (lastHeight = root.offsetHeight);
    const left = Math.max(8, Math.min(rect.left, window.innerWidth - width - 8));
    const above = !fits(height);
    const top = above ? Math.max(8, rect.top - height - 6) : rect.bottom + 6;
    root.dataset.side = above ? "above" : "below";
    root.style.left = `${Math.round(left)}px`;
    root.style.top = `${Math.round(top)}px`;
    root.style.maxHeight = `${Math.min(MAX_HEIGHT, window.innerHeight - 16)}px`;
    search.focus();
  }

  search.addEventListener("input", () => {
    if (isOpen()) fill();
  });

  search.addEventListener("keydown", (event) => {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      highlight(highlighted + 1);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      highlight(highlighted - 1);
    } else if (event.key === "Enter") {
      event.preventDefault();
      if (rows[highlighted]) select(rows[highlighted].key);
    } else if (event.key === "Escape") {
      event.preventDefault();
      close();
    }
  });

  list.addEventListener("pointerdown", (event) => {
    const row = event.target instanceof Element ? event.target.closest(".km-bm-item") : null;
    if (!(row instanceof HTMLElement) || !row.dataset.key) return;
    // Keep the search field focused: the editor never sees this press.
    event.preventDefault();
    select(row.dataset.key);
  });

  document.addEventListener(
    "pointerdown",
    (event) => {
      if (!isOpen()) return;
      if (event.target instanceof Node && root.contains(event.target)) return;
      close();
    },
    true,
  );

  return { open, close, isOpen };
}
