/**
 * Notion-style Markdown input rules Crepe 7.22.2 does not ship.
 *
 * Crepe's commonmark preset already turns `# `..`###### `, `- ` / `* ` / `+ `,
 * `1. ` and `> ` into blocks, and its gfm preset converts `[] ` / `[ ] ` /
 * `[x] ` into a task item — but only *inside an existing list item* (its handler
 * walks up looking for a `list_item` ancestor). Typing `[] ` at the start of a
 * plain paragraph, which is the Notion gesture, does nothing today. `"` + Space
 * has no rule at all.
 *
 * The regexes are exported so `node --test` covers the matching behaviour, which
 * is where these rules fail: a stray `"` mid-sentence must not swallow the line.
 */

import { InputRule, inputRules, wrappingInputRule } from "@milkdown/kit/prose/inputrules";
import { findWrapping } from "@milkdown/kit/prose/transform";
import { blockquoteSchema, listItemSchema } from "@milkdown/kit/preset/commonmark";

/** `[]` or `[ ]` + Space at the start of a block. */
export const TASK_INPUT = /^\[\s?\]\s$/;

/** `"` + Space at the start of a block (Notion's quote gesture). */
export const QUOTE_INPUT = /^"\s$/;

/**
 * The rules, bound to the editor's schema.
 * @param {import('@milkdown/kit/ctx').Ctx} ctx
 */
function notInputRules(ctx) {
  const listItem = listItemSchema.type(ctx);
  return [
    new InputRule(TASK_INPUT, (state, _match, start, end) => {
      const $start = state.doc.resolve(start);
      for (let depth = $start.depth; depth > 0; depth--) {
        const node = $start.node(depth);
        if (node.type.name !== "list_item") continue;
        // Inside a list: mark the item itself. The gfm preset's rule only
        // matches `[ ]` / `[x]`, so `[] ` inside a bullet needs this branch.
        if (node.attrs.checked != null) return null;
        const pos = $start.before(depth);
        return state.tr
          .delete(start, end)
          .setNodeMarkup(pos, undefined, { ...node.attrs, checked: false });
      }
      // Plain paragraph: build the list item from scratch.
      const tr = state.tr.delete(start, end);
      const range = tr.doc.resolve(start).blockRange();
      const wrapping = range && findWrapping(range, listItem, { checked: false });
      if (!wrapping) return null;
      return tr.wrap(range, wrapping);
    }),
    wrappingInputRule(QUOTE_INPUT, blockquoteSchema.type(ctx)),
  ];
}

/** The rules as a ProseMirror plugin, for `$prose`. */
export function notInputRulePlugin(ctx) {
  return inputRules({ rules: notInputRules(ctx) });
}
