/**
 * Document find: literal / case / whole-word / regex matching over text
 * segments, plus the ProseMirror and CodeMirror highlight plumbing. entry.js
 * feeds it ProseMirror textblocks (rendered view) or the whole file (source
 * view); the unit tests feed it strings and real editor states.
 *
 * Matches never cross a segment and report absolute offsets (`segment.start +
 * index`). Zero-width matches are visible caret markers. Highlighting is
 * decoration-only: no document change or history entry.
 */

import { StateEffect, StateField } from "@codemirror/state";
import { Decoration as CMDecoration, EditorView, ViewPlugin, WidgetType } from "@codemirror/view";
import { Plugin, PluginKey } from "@milkdown/kit/prose/state";
import { Decoration, DecorationSet } from "@milkdown/kit/prose/view";

const WORD_BOUNDARY = "(?!(?<=[\\p{L}\\p{M}\\p{N}_])(?=[\\p{L}\\p{M}\\p{N}_]))";

/** Escapes for a `u`-flag RegExp (no `-` or `/` escapes: invalid under `u`). */
const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");


/**
 * @param {string} query
 * @param {{ caseSensitive?: boolean, regex?: boolean, wholeWord?: boolean }} options
 * @returns {{ re: RegExp } | { error: "invalid-regex" }}
 */
export function buildPattern(query, { caseSensitive = false, regex = false, wholeWord = false } = {}) {
  let sources;
  if (regex) {
    sources = [query];
  } else {
    // Hangul may be stored precomposed (NFC) or decomposed (NFD): match both.
    sources = [...new Set([query.normalize("NFC"), query.normalize("NFD"), query])].map(escapeRegExp);
  }
  const source = sources.length === 1 ? sources[0] : sources.map((s) => `(?:${s})`).join("|");
  const bounded = wholeWord ? `${WORD_BOUNDARY}(?:${source})${WORD_BOUNDARY}` : source;
  try {
    return { re: new RegExp(bounded, `g${caseSensitive ? "" : "i"}mu`) };
  } catch {
    return { error: "invalid-regex" };
  }
}

/**
 * @param {{ start: number, text: string }[]} segments
 * @param {string} query empty query: no matches, no error
 * @param {{ caseSensitive?: boolean, wholeWord?: boolean, regex?: boolean }} options
 * @returns {{ matches: { from: number, to: number }[], error: null | "invalid-regex" }}
 */
export function findMatches(segments, query, options = {}) {
  if (typeof query !== "string" || query === "") return { matches: [], error: null };
  const built = buildPattern(query, options);
  if (built.error) return { matches: [], error: built.error };
  const { re } = built;
  const matches = [];
  for (const { start, text } of segments) {
    re.lastIndex = 0;
    for (let m = re.exec(text); m; m = re.exec(text)) {
      if (m[0] === "") {
        // Zero-width: step over one code point so the scan always advances.
        re.lastIndex = m.index + (text.codePointAt(m.index) > 0xffff ? 2 : 1);
      }
      const end = m.index + m[0].length;
      matches.push({ from: start + m.index, to: start + end });
    }
  }
  return { matches, error: null };
}

/** Next active index after `step` (wraps both ways); `-1` when nothing matches. */
export function stepIndex(active, total, step) {
  if (total === 0) return -1;
  const base = active < 0 ? (step < 0 ? 0 : -1) : active;
  return (((base + step) % total) + total) % total;
}

/* ------------------------------------------------------------ ProseMirror */

/**
 * One segment per textblock (paragraph, heading, code block, table cell
 * paragraph…). Inline formatting never splits a segment, so a match runs
 * across `**bold**` / `` `code` `` / links; non-text inlines (images, hard
 * breaks) become one placeholder per position so offsets stay exact.
 */
export function textblockSegments(doc) {
  const segments = [];
  doc.descendants((node, pos) => {
    if (!node.isTextblock) return true;
    let text = "";
    node.forEach((child) => {
      text += child.isText ? child.text : "\uFFFC".repeat(child.nodeSize);
    });
    segments.push({ start: pos + 1, text });
    return false;
  });
  return segments;
}

export const findKey = new PluginKey("kmFind");

function zeroFindMarker(active) {
  const marker = document.createElement("span");
  marker.className = active ? "km-find-match km-find-active km-find-zero" : "km-find-match km-find-zero";
  marker.setAttribute("aria-hidden", "true");
  return marker;
}

class SourceZeroMatch extends WidgetType {
  constructor(active) { super(); this.active = active; }
  eq(other) { return this.active === other.active; }
  toDOM() { return zeroFindMarker(this.active); }
}

function proseDecorations(doc, { matches, active }) {
  const size = doc.content.size;
  return DecorationSet.create(
    doc,
    matches
      .filter((m) => m.from >= 0 && m.from <= m.to && m.to <= size)
      .map((m, i) =>
        m.from === m.to
          ? Decoration.widget(m.from, () => zeroFindMarker(i === active), { side: 1 })
          : Decoration.inline(m.from, m.to, {
              class: i === active ? "km-find-match km-find-active" : "km-find-match",
            })
      )
  );
}

/**
 * Highlight-only plugin. Decorations are replaced through `proseFindTransaction`
 * and merely mapped across edits; `onDocChanged` tells the host to recompute.
 */
export function findProsePlugin({ onDocChanged } = {}) {
  return new Plugin({
    key: findKey,
    state: {
      init: () => DecorationSet.empty,
      apply(tr, set) {
        const meta = tr.getMeta(findKey);
        if (meta) return proseDecorations(tr.doc, meta);
        return tr.docChanged ? set.map(tr.mapping, tr.doc) : set;
      },
    },
    props: {
      decorations: (state) => findKey.getState(state),
    },
    view: () => ({
      update(view, prev) {
        if (!prev.doc.eq(view.state.doc)) onDocChanged?.();
      },
    }),
  });
}

/** Meta-only transaction: no steps, no history entry, selection untouched. */
export function proseFindTransaction(state, matches, active) {
  return state.tr.setMeta(findKey, { matches, active }).setMeta("addToHistory", false);
}

/* ------------------------------------------------------------- CodeMirror */

const setFindEffect = StateEffect.define();

function sourceDecorations(length, { matches, active }) {
  return CMDecoration.set(
    matches
      .filter((m) => m.from >= 0 && m.from <= m.to && m.to <= length)
      .map((m, i) =>
        m.from === m.to
          ? CMDecoration.widget({ widget: new SourceZeroMatch(i === active), side: 1 }).range(m.from)
          : CMDecoration.mark({
              class: i === active ? "km-find-match km-find-active" : "km-find-match",
            }).range(m.from, m.to)
      ),
    true
  );
}

/** Highlight field for the source view; it never touches the document. */
export const findSourceExtension = StateField.define({
  create: () => CMDecoration.none,
  update(set, tr) {
    for (const effect of tr.effects) {
      if (effect.is(setFindEffect)) return sourceDecorations(tr.state.doc.length, effect.value);
    }
    return tr.docChanged ? set.map(tr.changes) : set;
  },
  provide: (field) => EditorView.decorations.from(field),
});

/** Effects-only transaction spec for a source view (`reveal` scrolls the active match in). */
export function sourceFindSpec(matches, active, reveal = false) {
  const effects = [setFindEffect.of({ matches, active })];
  const target = matches[active];
  if (reveal && target) effects.push(EditorView.scrollIntoView(target.from, { y: "center" }));
  return { effects };
}

/** Code editors are mounted lazily and may be destroyed while off-screen. */
export function findCodeExtension(onReady) {
  return [findSourceExtension, ViewPlugin.define((view) => {
    requestAnimationFrame(() => { if (view.dom.isConnected) onReady(); });
    return {};
  })];
}

/** Crepe's fenced-code node views own CodeMirror DOM, outside PM decorations. */
export function applyCodeFind(view, matches, active, reveal = false) {
  let cursor = 0;
  let pendingReveal = false;
  view.state.doc.descendants((node, pos) => {
    if (node.type.name !== "code_block") return true;
    const start = pos + 1;
    const end = start + node.content.size;
    while (cursor < matches.length && matches[cursor].from < start) cursor++;
    const local = [];
    let selected = -1;
    while (cursor < matches.length && matches[cursor].from <= end) {
      const match = matches[cursor];
      if (match.to <= end) {
        if (cursor === active) selected = local.length;
        local.push({ from: match.from - start, to: match.to - start });
      }
      cursor++;
    }
    const block = view.nodeDOM(pos);
    const element = block?.querySelector?.(".cm-editor");
    const code = element && EditorView.findFromDOM(element);
    if (reveal && selected >= 0) {
      block?.scrollIntoView?.({ block: "center", behavior: "auto" });
      pendingReveal = !code;
    }
    if (code) code.dispatch(sourceFindSpec(local, selected, reveal && selected >= 0));
    return false;
  });
  return pendingReveal;
}
