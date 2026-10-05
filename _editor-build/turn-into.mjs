/**
 * Block conversion ("전환") planning for the Kissmark Document surface.
 *
 * The block menu and the slash menu turn the block that holds the caret into
 * another block kind. Which Milkdown/ProseMirror commands that takes depends on
 * both the target and the block we start from (a list item has to be lifted out
 * of its list before it can become a heading, a single-item list can change its
 * kind in place, ...). The mapping is pure and lives here; `entry.js` executes
 * the returned op list with Crepe commands.
 *
 * Op vocabulary (one op per string, optional `:argument`):
 *   paragraph            setBlockType(paragraph)
 *   heading:1..5         setBlockType(heading, {level})
 *   wrap:bulletList      wrapInBlockType(bulletList)
 *   wrap:orderedList     wrapInBlockType(orderedList)
 *   wrap:taskList        wrapInBlockType(listItem, {checked:false})
 *   wrap:blockquote      wrapInBlockquote
 *   insert:hr            insertHr
 *   callout              wrap in a blockquote + insert the `[!note] ` marker
 *   callout-marker       insert the `[!note] ` marker into the current quote
 *   lift                 liftListItem (leaves the list, splitting it if needed)
 *   liftBlock            lift (leaves the blockquote, splitting it if needed)
 *   setListKind:bulletList|orderedList
 *                        setNodeMarkup on the parent list (single-item list)
 *   setChecked:true|false|null
 *                        setNodeMarkup on the list item's `checked` attr
 */

import { uiText } from "./ui-text.mjs";

/** Menu items, in order. `key` doubles as the conversion target. */
export const TURN_INTO_ITEMS = [
  { key: "text", label: uiText("텍스트") },
  { key: "h1", label: uiText("제목 1") },
  { key: "h2", label: uiText("제목 2") },
  { key: "h3", label: uiText("제목 3") },
  { key: "h4", label: uiText("제목 4") },
  { key: "h5", label: uiText("제목 5") },
  { key: "taskList", label: uiText("할 일 목록") },
  { key: "bulletList", label: uiText("글머리 기호 목록") },
  { key: "orderedList", label: uiText("번호 매기기 목록") },
  { key: "quote", label: uiText("인용") },
  { key: "callout", label: uiText("콜아웃") },
];

/**
 * The menu key of the block the caret sits in, for the check mark.
 * @param {{node: string, level?: number, listType?: 'bullet'|'ordered'|'task', callout?: boolean}} info
 * @returns {string | null} a TURN_INTO_ITEMS key, or null for blocks the menu cannot express
 */
export function currentKindKey(info) {
  switch (info?.node) {
    case "paragraph":
      return "text";
    case "heading":
      return `h${info.level}`;
    case "blockquote":
      return info.callout ? "callout" : "quote";
    case "listItem":
      if (info.listType === "task") return "taskList";
      return info.listType === "ordered" ? "orderedList" : "bulletList";
    default:
      return null;
  }
}

/** @param {'bulletList'|'orderedList'|'taskList'} target @param {object} info */
function sameListKind(target, info) {
  return currentKindKey(info) === target;
}

/**
 * Ops that convert the caret's block into `target`.
 * @param {string} target a TURN_INTO_ITEMS key
 * @param {{node: string, level?: number, listType?: 'bullet'|'ordered'|'task', listCount?: number, callout?: boolean}} info
 * @returns {string[]} ordered op list; empty when the block already is `target`
 */
export function turnIntoOps(target, info) {
  const inList = info?.node === "listItem";
  const inQuote = info?.node === "blockquote";
  // A single-item list can change kind in place; a longer list is split by
  // lifting the item out (liftOutOfList closes the list on both sides).
  const alone = inList && info.listCount === 1;
  // Everything but a quote target leaves its container first: a list item is
  // lifted out of its list, a blockquote's paragraph out of the quote.
  const leave = [
    ...(inList ? ["lift"] : []),
    ...(inQuote && target !== "quote" && target !== "callout" ? ["liftBlock"] : []),
  ];

  switch (target) {
    case "text":
      if (info?.node === "paragraph") return [];
      if (inList) return ["lift"];
      if (inQuote) return ["liftBlock"];
      return ["paragraph"];

    case "h1":
    case "h2":
    case "h3":
    case "h4":
    case "h5": {
      const level = Number(target.slice(1));
      if (info?.node === "heading" && info.level === level) return [];
      return [...leave, `heading:${level}`];
    }

    case "bulletList":
    case "orderedList": {
      const listKind = target === "bulletList" ? "bulletList" : "orderedList";
      if (sameListKind(target, info)) return [];
      if (alone) return [`setListKind:${listKind}`, "setChecked:null"];
      return [...leave, `wrap:${listKind}`];
    }

    case "taskList":
      if (sameListKind(target, info)) return [];
      if (alone) return ["setChecked:false"];
      return [...leave, "wrap:taskList"];

    // A quote or callout holds body text (Notion): a heading becomes text first.
    case "quote":
      if (inQuote) return [];
      return [...leave, ...(info?.node === "heading" ? ["paragraph"] : []), "wrap:blockquote"];

    case "callout":
      if (inQuote) return info.callout ? [] : ["callout-marker"];
      return [...leave, ...(info?.node === "heading" ? ["paragraph"] : []), "wrap:blockquote", "callout-marker"];

    default:
      return [];
  }
}
