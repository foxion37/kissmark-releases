/**
 * Executes the conversion ops planned by `turn-into.mjs` through Crepe's own
 * commands (spec item 7). Kept out of `entry.js` so the command knowledge sits
 * next to the mapping it serves.
 */

import { commandsCtx, editorViewCtx } from "@milkdown/kit/core";
import {
  blockquoteSchema,
  bulletListSchema,
  clearTextInCurrentBlockCommand,
  hrSchema,
  liftListItemCommand,
  listItemSchema,
  orderedListSchema,
  paragraphSchema,
  setBlockTypeCommand,
  wrapInBlockTypeCommand,
  wrapInBlockquoteCommand,
  wrapInHeadingCommand,
} from "@milkdown/kit/preset/commonmark";
import { lift } from "@milkdown/kit/prose/commands";
import { TextSelection } from "@milkdown/kit/prose/state";

import { calloutMarker, calloutType } from "./callout.mjs";

const LIST_SCHEMAS = { bulletList: bulletListSchema, orderedList: orderedListSchema };

/** Position of the nearest ancestor with one of `names`, or null. */
function ancestorPos(view, ...names) {
  const { $from } = view.state.selection;
  for (let depth = $from.depth; depth > 0; depth--) {
    if (names.includes($from.node(depth).type.name)) return $from.before(depth);
  }
  return null;
}

/**
 * Makes the enclosing blockquote a callout. The `[!note]` marker gets its own
 * first paragraph so existing text stays the callout body (`> [!note]` / `>` /
 * `> text`, which Obsidian reads the same way); an empty first paragraph just
 * takes the marker. Idempotent: an existing marker leaves the block alone.
 * @param {import('@milkdown/kit/ctx').Ctx} ctx
 */
export function insertCalloutMarker(ctx) {
  const view = ctx.get(editorViewCtx);
  const { $from } = view.state.selection;
  for (let depth = $from.depth; depth > 0; depth--) {
    const node = $from.node(depth);
    if (node.type.name !== "blockquote") continue;
    const first = node.firstChild;
    if (!first || first.type.name !== "paragraph") return false;
    if (calloutType(first.textContent)) return false;
    const start = $from.start(depth);
    if (first.content.size === 0) {
      view.dispatch(view.state.tr.insertText(calloutMarker(), start + 1));
    } else {
      const { schema } = view.state;
      const label = schema.nodes.paragraph.create(null, schema.text(calloutMarker().trim()));
      view.dispatch(view.state.tr.insert(start, label));
    }
    return true;
  }
  return false;
}

/**
 * Runs `ops` against the current block. Returns true when anything changed.
 * @param {import('@milkdown/kit/ctx').Ctx} ctx
 * @param {string[]} ops
 */
export function applyBlockOps(ctx, ops) {
  const view = ctx.get(editorViewCtx);
  const commands = ctx.get(commandsCtx);
  let applied = false;

  for (const op of ops) {
    const separator = op.indexOf(":");
    const name = separator < 0 ? op : op.slice(0, separator);
    const arg = separator < 0 ? "" : op.slice(separator + 1);

    switch (name) {
      case "paragraph":
        applied =
          commands.call(setBlockTypeCommand.key, { nodeType: paragraphSchema.type(ctx) }) || applied;
        break;

      case "heading":
        applied = commands.call(wrapInHeadingCommand.key, Number(arg)) || applied;
        break;

      case "wrap": {
        const nodeType =
          arg === "blockquote"
            ? blockquoteSchema.type(ctx)
            : arg === "taskList"
              ? listItemSchema.type(ctx)
              : LIST_SCHEMAS[arg]?.type(ctx);
        if (!nodeType) break;
        const attrs = arg === "taskList" ? { checked: false } : null;
        applied = commands.call(wrapInBlockTypeCommand.key, { nodeType, attrs }) || applied;
        break;
      }

      case "insert": {
        // Crepe's insertHrCommand replaces the selection with the rule, which
        // silently fails at a caret inside a paragraph; insert it between blocks
        // instead and leave the caret in a textblock under the rule.
        const hr = hrSchema.type(ctx).create();
        const $from = view.state.selection.$from;
        const empty = $from.parent.type.name === "paragraph" && $from.parent.content.size === 0;
        const before = $from.before(1);
        // An empty block becomes the rule (Notion's gesture); otherwise the rule
        // lands below the caret's block.
        let tr = empty
          ? view.state.tr.delete(before, $from.after(1)).insert(before, hr)
          : view.state.tr.insert($from.after(1), hr);
        const ruleAt = empty ? before : $from.after(1);
        const next = tr.doc.resolve(ruleAt + hr.nodeSize).nodeAfter;
        let caret = ruleAt + hr.nodeSize + 1;
        if (!next || !next.isTextblock) {
          tr = tr.insert(ruleAt + hr.nodeSize, paragraphSchema.type(ctx).createAndFill());
          caret = ruleAt + hr.nodeSize + 1;
        }
        tr = tr.setSelection(TextSelection.near(tr.doc.resolve(caret)));
        view.dispatch(tr.scrollIntoView());
        applied = true;
        break;
      }

      case "lift":
        applied = commands.call(liftListItemCommand.key) || applied;
        break;

      case "liftBlock":
        applied = lift(view.state, view.dispatch, view) || applied;
        break;

      case "callout":
        // Wrap first, then mark: the marker lives inside the new blockquote.
        applied = commands.call(wrapInBlockquoteCommand.key) || applied;
        applied = insertCalloutMarker(ctx) || applied;
        break;

      case "callout-marker":
        applied = insertCalloutMarker(ctx) || applied;
        break;

      case "setListKind": {
        const pos = ancestorPos(view, "bullet_list", "ordered_list");
        const nodeType = LIST_SCHEMAS[arg]?.type(ctx);
        if (pos === null || !nodeType) break;
        view.dispatch(view.state.tr.setNodeMarkup(pos, nodeType));
        applied = true;
        break;
      }

      case "setChecked": {
        const pos = ancestorPos(view, "list_item");
        const node = pos === null ? null : view.state.doc.nodeAt(pos);
        if (!node) break;
        const checked = arg === "null" ? null : arg === "true";
        view.dispatch(view.state.tr.setNodeMarkup(pos, undefined, { ...node.attrs, checked }));
        applied = true;
        break;
      }

      default:
        break;
    }
  }

  return applied;
}

/**
 * The slash menu's callout item: the typed `/` goes away first, exactly like
 * Crepe's own items do.
 * @param {import('@milkdown/kit/ctx').Ctx} ctx
 */
export function runCalloutMenuItem(ctx) {
  const commands = ctx.get(commandsCtx);
  commands.call(clearTextInCurrentBlockCommand.key);
  return applyBlockOps(ctx, ["wrap:blockquote", "callout-marker"]);
}
