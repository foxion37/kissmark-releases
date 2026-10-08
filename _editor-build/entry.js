import { Crepe, CrepeFeature } from "@milkdown/crepe";
import { editorViewCtx, remarkStringifyOptionsCtx } from "@milkdown/kit/core";
import { Plugin, TextSelection } from "@milkdown/kit/prose/state";
import { Decoration, DecorationSet } from "@milkdown/kit/prose/view";
import { $prose } from "@milkdown/kit/utils";
import "@milkdown/crepe/theme/common/style.css";
import "@milkdown/crepe/theme/frame.css";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { EditorView } from "@codemirror/view";
import { tags } from "@lezer/highlight";

import { applyBlockOps, runCalloutMenuItem } from "./block-ops.mjs";
import { createBlockMenu } from "./block-menu.mjs";
import { blockquoteCalloutType, unescapeCalloutMarkers } from "./callout.mjs";
import { renderDocInfo } from "./docinfo.mjs";
import { matchQuote, renderReview } from "./review.mjs";
import { frontmatterRows, joinFrontmatter, splitFrontmatter } from "./frontmatter.mjs";
import { bulletIcon, checkBoxCheckedIcon, checkBoxUncheckedIcon } from "./icons.mjs";
import { playEntrance, prefersReducedMotion, withViewTransition } from "./motion.mjs";
import { notInputRulePlugin } from "./input-rules.mjs";
import { BANNED_TYPOGRAPHY, isStrongHeading, lintTypographyText } from "./typography.mjs";
import { createSourceView } from "./source-view.mjs";
import { currentKindKey, turnIntoOps } from "./turn-into.mjs";
import { uiLanguage, uiText } from "./ui-text.mjs";

/** Debounce for `change`, matching Crepe's own markdown listener. */
const CHANGE_DEBOUNCE = 200;
/** Blocks (after the info card and properties box) that join the opening entrance. */
const ENTRANCE_LIMIT = 12;
/** Plays the entrance anyway if no document info follows ready this soon: Swift
 * sends it in the same turn, and the surface is still near-transparent then. */
const ENTRANCE_FALLBACK_MS = 40;
/** Movement (px) above which a press on the block handle counts as a drag. */
const CLICK_SLOP = 4;

/**
 * Code block theme, replacing Crepe's default One Dark (which painted the
 * active-line gutter dark and the tokens in dark-only inks on light themes).
 * Surfaces, gutter and selection come from `reader.css`; only the token inks
 * live here, as `--km-*` references so every theme and scheme follows.
 * `lineWrapping` stays on: `--km-code-white-space` in reader.css decides whether
 * long lines actually wrap (Settings › 코드 › 자동 줄바꿈).
 */
const codeBlockTheme = [
  EditorView.lineWrapping,
  syntaxHighlighting(
    HighlightStyle.define([
      { tag: [tags.keyword, tags.operatorKeyword, tags.modifier, tags.controlKeyword], color: "var(--km-accent)" },
      { tag: [tags.string, tags.special(tags.string), tags.regexp, tags.inserted], color: "var(--km-success)" },
      { tag: [tags.number, tags.bool, tags.atom, tags.null, tags.typeName, tags.className], color: "var(--km-warn)" },
      { tag: [tags.tagName, tags.heading, tags.deleted, tags.invalid], color: "var(--km-danger)" },
      { tag: [tags.comment, tags.meta, tags.processingInstruction], color: "var(--km-muted)", fontStyle: "italic" },
      { tag: tags.strong, fontWeight: "650" },
      { tag: tags.emphasis, fontStyle: "italic" },
      { tag: tags.link, textDecoration: "underline" },
    ]),
  ),
];

/**
 * Local-only Milkdown Crepe host for Kissmark Document surface
 * (Read Mode + Edit Mode share one WKWebView, plus a CodeMirror source view).
 * Exposed as window.KissmarkEditor for the Swift bridge.
 */
function createAPI() {
  /** @type {Crepe | null} */
  let crepe = null;
  /** @type {(markdown: string) => void | null} */
  let onChange = null;
  let applying = false;
  /**
   * "The user changed the document" flag. Only an edited Document gets a final
   * change on Lock — Crepe's serialization can differ from the file bytes
   * (`# A` → `# A\n`), so an unedited Lock must not post anything that would
   * rewrite the file. Armed by the ProseMirror plugin registered in `mount`:
   * any root transaction that changed the doc while in Edit Mode. DOM events
   * are not used — they fire in locked code blocks, and keymap edits (Enter,
   * ⌘B, ⌘Z) preventDefault before `beforeinput` exists.
   */
  let userEdited = false;
  /**
   * The file text as Swift last knew it: what was mounted, or what this side last
   * posted. The source view starts from it so an unedited Document shows its own
   * bytes (`-` bullets, `---` rules), not Crepe's re-serialization.
   */
  let rawText = "";
  /** @type {'read' | 'edit'} */
  let mode = "edit";
  /** @type {'render' | 'source'} */
  let view = "render";
  /**
   * Raw frontmatter block, fences included. Crepe only ever sees the body; the
   * box above the editor is a read-only view of this string, and every message
   * to Swift carries `front + body` so the file on disk stays whole.
   * @type {string}
   */
  let front = "";
  /** CodeMirror source view, created the first time source view is entered. */
  let source = null;
  /** Source view holds text Crepe has not mounted yet. */
  /** Pending debounced `change` from the source view. */
  let sourceTimer = 0;
  /**
   * Last document info from Swift (polish 1.5, item 1). Callable before ready:
   * stored here and rendered after mount; re-sent whenever any field changes.
   * @type {{ path: string, saveState: string, saveLabel: string,
   *          modified: string, created: string, expanded: boolean } | null}
   */
  let docInfo = null;

  /** Renders the info bar from the stored info; the toggle reports to Swift. */
  function renderDocInfoBar() {
    const container = document.getElementById("docinfo");
    if (!container) return;
    renderDocInfo(container, docInfo, {
      expanded: Boolean(docInfo?.expanded),
      onToggle: (expanded) => {
        if (docInfo) docInfo.expanded = expanded;
        window.webkit?.messageHandlers?.kissmark?.postMessage({
          type: "infoExpanded",
          expanded,
        });
      },
    });
  }

  /**
   * Last review payload from Swift (round 3). Callable before ready, like the
   * document info. `null` hides the card and clears the highlights.
   * @type {{ points: object[], completedLabel: string|null, expanded: boolean } | null}
   */
  let review = null;

  function post(message) {
    window.webkit?.messageHandlers?.kissmark?.postMessage(message);
  }

  function renderReviewCard() {
    const container = document.getElementById("review");
    if (!container) return;
    renderReview(container, review, {
      onCheck: (id) => post({ type: "reviewCheck", id }),
      onUncheck: (id) => post({ type: "reviewUncheck", id }),
      onComment: (id, comment) => post({ type: "reviewComment", id, comment }),
      onComplete: () => post({ type: "reviewComplete" }),
      onToggle: (expanded) => {
        if (review) review.expanded = expanded;
        post({ type: "reviewExpanded", expanded });
      },
      onReveal: revealReviewMark,
    });
  }

  /** Scrolls the body highlight of point `id` into view (no-op without a match). */
  function revealReviewMark(id) {
    document
      .querySelector(`.km-review-mark[data-km-review-id="${Number(id)}"]`)
      ?.scrollIntoView({ block: "center", behavior: prefersReducedMotion() ? "auto" : "smooth" });
  }

  /**
   * Highlight ranges of every unchecked point: the first textblock whose text
   * holds the quote. Inline code and non-text inlines become placeholder
   * characters of the same width, so no match runs through them and positions
   * stay exact; code blocks are skipped.
   */
  function reviewMarks(doc) {
    const marks = [];
    const points = (review?.points ?? []).filter((p) => !p.checked && p.quote);
    if (points.length === 0) return marks;
    const blocks = [];
    doc.descendants((node, pos) => {
      if (node.type.name === "code_block" || node.type.spec.code) return false;
      if (!node.isTextblock) return true;
      let text = "";
      node.forEach((child) => {
        const code = child.marks.some((m) => m.type.name === "inlineCode" || m.type.spec.code);
        text += child.isText && !code ? child.text : "\uFFFC".repeat(child.nodeSize);
      });
      blocks.push({ start: pos + 1, text });
      return false;
    });
    for (const p of points) {
      for (const block of blocks) {
        const hit = matchQuote(block.text, p.quote);
        if (!hit) continue;
        const kind = typeof p.kind === "string" ? p.kind : "agent";
        marks.push(
          Decoration.inline(block.start + hit.from, block.start + hit.to, {
            class: `km-review-mark km-review-${kind}`,
            "data-km-review-id": String(p.id),
          })
        );
        break;
      }
    }
    return marks;
  }

  /**
   * Renders the read-only properties box. Built with `textContent` only — the
   * frontmatter is untrusted text and must never be parsed as HTML. The path
   * from the info push lets a title that repeats the file name drop out.
   */
  function renderFrontmatter() {
    const container = document.getElementById("frontmatter");
    if (!container) return;
    container.textContent = "";
    const rows = frontmatterRows(front, docInfo?.path);
    if (rows.length === 0) {
      container.hidden = true;
      return;
    }
    const box = document.createElement("div");
    box.className = "km-fm-box";
    for (const row of rows) {
      const rowEl = document.createElement("div");
      rowEl.className = "km-fm-row";
      if (row.raw !== undefined) {
        const raw = document.createElement("span");
        raw.className = "km-fm-raw";
        raw.textContent = row.raw;
        rowEl.appendChild(raw);
      } else {
        const key = document.createElement("span");
        key.className = "km-fm-key";
        key.textContent = row.key;
        const value = document.createElement("span");
        value.className = "km-fm-value";
        value.textContent = row.value;
        rowEl.appendChild(key);
        rowEl.appendChild(value);
      }
      box.appendChild(rowEl);
    }
    container.appendChild(box);
    container.hidden = false;
  }

  function applyModeClass() {
    document.documentElement.dataset.kmMode = mode;
    document.body?.classList.toggle("km-mode-read", mode === "read");
    document.body?.classList.toggle("km-mode-edit", mode === "edit");
    const root = document.getElementById("editor");
    if (root) {
      root.setAttribute("aria-label", mode === "read" ? uiText("문서 읽기") : uiText("문서 편집"));
      root.setAttribute("aria-readonly", mode === "read" ? "true" : "false");
    }
    if (mode === "read") menu.close();
  }

  function applyViewClass() {
    // The block menu belongs to the rendered view only.
    if (view === "source") menu.close();
    document.documentElement.dataset.kmView = view;
    document.body?.classList.toggle("km-view-source", view === "source");
    const el = document.getElementById("source");
    if (el) el.hidden = view !== "source";
  }

  /* ------------------------------------------------------------------ blocks */

  /** What the caret's block is, for the menu check mark and the conversion plan. */
  function describeBlock(ctx) {
    const { $from } = ctx.get(editorViewCtx).state.selection;
    for (let depth = $from.depth; depth > 0; depth--) {
      const node = $from.node(depth);
      if (node.type.name === "list_item") {
        const listType =
          node.attrs.checked == null
            ? node.attrs.listType === "ordered"
              ? "ordered"
              : "bullet"
            : "task";
        return { node: "listItem", listType, listCount: $from.node(depth - 1)?.childCount ?? 1 };
      }
      if (node.type.name === "blockquote") {
        return { node: "blockquote", callout: Boolean(blockquoteCalloutType(node)) };
      }
    }
    const top = $from.depth > 0 ? $from.node(1) : null;
    switch (top?.type.name) {
      case "heading":
        return { node: "heading", level: top.attrs.level };
      case "code_block":
        return { node: "codeBlock" };
      case "hr":
        return { node: "divider" };
      default:
        return { node: "paragraph" };
    }
  }

  /** Converts the caret's block into `target` (a TURN_INTO_ITEMS key). */
  function turnIntoTarget(target) {
    if (mode !== "edit" || view !== "render") return;
    runEditorAction((ctx) => {
      const ops = turnIntoOps(target, describeBlock(ctx));
      return ops.length > 0 && applyBlockOps(ctx, ops);
    });
  }

  /** The menu's current block, plus the rect the popover should hang from. */
  function blockAnchor() {
    let anchor = null;
    runEditorAction((ctx) => {
      const editorView = ctx.get(editorViewCtx);
      const coords = editorView.coordsAtPos(editorView.state.selection.from);
      anchor = {
        info: describeBlock(ctx),
        rect: { left: coords.left, right: coords.right, top: coords.top, bottom: coords.bottom },
      };
      return true;
    });
    return anchor;
  }

  function openMenuAt(rect, info) {
    if (mode !== "edit" || view !== "render") return;
    menu.open(rect, currentKindKey(info));
  }

  /** ⌘/ — the menu for the selection's block. */
  function openMenuForSelection() {
    const anchor = blockAnchor();
    if (anchor) openMenuAt(anchor.rect, anchor.info);
  }

  /** A press (not a drag) on the block handle's drag item opens the same menu. */
  function dragHandleFrom(target) {
    if (!(target instanceof Element)) return null;
    const item = target.closest(".milkdown-block-handle .operation-item");
    if (!item) return null;
    const items = item.parentElement?.querySelectorAll(".operation-item");
    // The first item is Crepe's own add button; only the second is the handle.
    if (!items || items.length < 2 || items[1] !== item) return null;
    return item;
  }

  function openMenuForHandle(rect) {
    runEditorAction((ctx) => {
      const editorView = ctx.get(editorViewCtx);
      const at = editorView.posAtCoords({ left: rect.right + 8, top: rect.top + rect.height / 2 });
      if (!at) return false;
      // Act on the block the handle points at, not on wherever the caret was.
      const $pos = editorView.state.doc.resolve(at.pos);
      editorView.dispatch(
        editorView.state.tr.setSelection(TextSelection.near($pos))
      );
      return true;
    });
    const anchor = blockAnchor();
    if (anchor) openMenuAt(rect, anchor.info);
  }

  /* ------------------------------------------------------------------ mount */

  async function mount(markdown) {
    const root = document.getElementById("editor");
    if (!root) throw new Error("missing #editor");
    rawText = markdown ?? "";
    const parts = splitFrontmatter(markdown ?? "");
    front = parts.front;
    renderFrontmatter();
    renderDocInfoBar();
    renderReviewCard();
    if (crepe) {
      await crepe.destroy();
      crepe = null;
      root.innerHTML = "";
    }

    applyModeClass();
    applyViewClass();

    crepe = new Crepe({
      root,
      defaultValue: parts.body,
      features: {
        [CrepeFeature.Latex]: false,
        [CrepeFeature.ImageBlock]: false,
        [CrepeFeature.TopBar]: false,
        [CrepeFeature.AI]: false,
        // Toolbar hides itself when the view is not editable; block/slash chrome is
        // hidden by editor.html in km-mode-read. Mount once; Lock only flips readonly.
      },
      featureConfigs: {
        [CrepeFeature.ListItem]: {
          bulletIcon,
          checkBoxCheckedIcon,
          checkBoxUncheckedIcon,
        },
        [CrepeFeature.Placeholder]: { text: uiText("내용을 입력하세요…") },
        [CrepeFeature.LinkTooltip]: { inputPlaceholder: uiText("링크를 붙여넣으세요…") },
        [CrepeFeature.Toolbar]: {
          boldLabel: uiText("굵게"),
          italicLabel: uiText("기울임"),
          strikethroughLabel: uiText("취소선"),
          codeLabel: uiText("코드"),
          linkLabel: uiText("링크"),
        },
        [CrepeFeature.CodeMirror]: {
          // `null`, not omitted: Crepe deep-merges its defaults (One Dark) into
          // anything left undefined — and into any object passed here.
          theme: null,
          extensions: codeBlockTheme,
          searchPlaceholder: uiText("언어 검색"),
          copyText: uiText("복사"),
          noResultText: uiText("결과 없음"),
        },
        [CrepeFeature.BlockEdit]: {
          // Slash menu labels come from the app catalogue; H6 is not offered (spec item 7).
          textGroup: {
            label: uiText("텍스트"),
            text: { label: uiText("텍스트") },
            h1: { label: uiText("제목 1") },
            h2: { label: uiText("제목 2") },
            h3: { label: uiText("제목 3") },
            h4: { label: uiText("제목 4") },
            h5: { label: uiText("제목 5") },
            h6: null,
            quote: { label: uiText("인용") },
            divider: { label: uiText("구분선") },
          },
          listGroup: {
            label: uiText("목록"),
            bulletList: { label: uiText("글머리 기호 목록") },
            orderedList: { label: uiText("번호 매기기 목록") },
            taskList: { label: uiText("할 일 목록") },
          },
          advancedGroup: {
            label: uiText("고급"),
            image: null,
            codeBlock: { label: uiText("코드 블록") },
            table: { label: uiText("표") },
          },
          buildMenu: (builder) => {
            builder.getGroup("text")?.addItem("callout", {
              label: uiText("콜아웃"),
              onRun: runCalloutMenuItem,
            });
          },
        },
      },
    });

    // Write lists and rules the way Notion and most Markdown files type them
    // (`- item`, `---`), so an edit elsewhere does not turn them into `*`/`***`.
    crepe.editor.config((ctx) => {
      ctx.update(remarkStringifyOptionsCtx, (prev) => ({ ...prev, bullet: "-", rule: "-" }));
    });

    crepe.editor.use(
      $prose(
        () =>
          new Plugin({
            appendTransaction(trs) {
              // Root doc changes only: appended transactions (trailing
              // paragraph, history bookkeeping) never arm the flag, and the
              // `applying`/`mode` guards exclude setMarkdown and Read Mode.
              if (
                !applying &&
                mode === "edit" &&
                trs.some((tr) => tr.docChanged && !tr.getMeta("appendedTransaction"))
              ) {
                userEdited = true;
              }
              return null;
            },
          })
      )
    );

    // `[]` + Space and `"` + Space, which Crepe's presets do not cover.
    crepe.editor.use($prose((ctx) => notInputRulePlugin(ctx)));

    // Presentation decorations preserve Markdown and its block semantics.
    crepe.editor.use(
      $prose(
        () =>
          new Plugin({
            props: {
              decorations(state) {
                const marks = [];
                state.doc.descendants((node, pos, parent) => {
                  if (isStrongHeading(node, parent)) {
                    marks.push(Decoration.node(pos, pos + node.nodeSize, { class: "km-strong-heading" }));
                    return false;
                  }
                  if (node.type.name !== "blockquote") return true;
                  const type = blockquoteCalloutType(node);
                  if (!type) return false;
                  marks.push(
                    Decoration.node(pos, pos + node.nodeSize, {
                      class: `callout callout-${type}`,
                      "data-callout": type,
                    })
                  );
                  const label = node.firstChild;
                  if (label) {
                    marks.push(
                      Decoration.node(pos + 1, pos + 1 + label.nodeSize, {
                        class: "callout-label",
                      })
                    );
                  }
                  return false;
                });
                return DecorationSet.create(state.doc, marks);
              },
            },
          })
      )
    );

    // Body highlights of unchecked review quotes. Recomputed when the doc or
    // the review changes (setReview dispatches a `kmReview` meta).
    crepe.editor.use(
      $prose(
        () =>
          new Plugin({
            state: {
              init: (_config, state) => DecorationSet.create(state.doc, reviewMarks(state.doc)),
              apply: (tr, set, _old, state) =>
                tr.docChanged || tr.getMeta("kmReview")
                  ? DecorationSet.create(state.doc, reviewMarks(state.doc))
                  : set,
            },
            props: {
              decorations(state) {
                return this.getState(state);
              },
            },
          })
      )
    );

    // Mirror each code block's `language` attr onto its wrapper DOM as
    // `data-language`: the Crepe node view only exposes the language through
    // the picker's list items, and reader.css labels the block from it.
    crepe.editor.use(
      $prose(
        () =>
          new Plugin({
            view(editorView) {
              const sync = (view) => {
                view.state.doc.descendants((node, pos) => {
                  if (node.type.name !== "code_block") return false;
                  const dom = view.nodeDOM(pos);
                  if (dom instanceof HTMLElement) {
                    const language = node.attrs.language ?? "";
                    if (dom.dataset.language !== language) dom.dataset.language = language;
                  }
                  return false;
                });
              };
              sync(editorView);
              return {
                update(view, _prevState, tr) {
                  if (tr?.docChanged) sync(view);
                },
              };
            },
          })
      )
    );

    crepe.on((listener) => {
      listener.markdownUpdated((_ctx, next) => {
        if (applying || mode === "read" || view === "source") return;
        // This message is debounced (200 ms) and may still be in flight when Lock
        // arrives, in which case Swift drops it — the final change posted by
        // `setMode` is what carries the text in that case.
        if (typeof onChange === "function") onChange((rawText = getMarkdown(next)));
      });
    });

    await crepe.create();
    userEdited = false;
    crepe.setReadonly(mode === "read");
    // Swift may have asked for source view before the editor was ready.
    if (view === "source") enterSource();
  }

  /* -------------------------------------------------------------- source view */

  function ensureSource() {
    if (!source) {
      source = createSourceView({
        parent: document.getElementById("source"),
        onDocChanged: () => {
          userEdited = true;
          scheduleSourceChange();
        },
      });
    }
    return source;
  }

  function scheduleSourceChange() {
    clearTimeout(sourceTimer);
    sourceTimer = setTimeout(() => {
      sourceTimer = 0;
      if (mode !== "edit" || view !== "source") return;
      if (typeof onChange === "function") onChange((rawText = getMarkdown()));
    }, CHANGE_DEBOUNCE);
  }

  /** Crepe out of the way, CodeMirror over the whole raw file. */
  function enterSource() {
    // Read the text while the rendered view is still the active one:
    // `getMarkdown()` prefers the source view as soon as `view` says so.
    const text = userEdited ? getMarkdown() : rawText;
    view = "source";
    applyViewClass();
    ensureSource().attach(text, mode === "edit");
  }

  /** Back to the rendered document, rebuilt from the source text. */
  async function leaveSource() {
    clearTimeout(sourceTimer);
    sourceTimer = 0;
    const text = source?.getText();
    view = "render";
    if (text === undefined) {
      applyViewClass();
      return;
    }
    // Always rebuild: the source view is authoritative while it is up, and a
    // hidden Crepe must not keep stale content (spec item 6).
    const edited = userEdited;
    applying = true;
    try {
      await mount(text);
    } finally {
      applying = false;
    }
    userEdited = edited;
    applyViewClass();
  }

  /* ------------------------------------------------------------- churn-free */

  function runEditorAction(action) {
    if (!crepe || mode === "read") return false;
    try {
      crepe.editor.action(action);
      return true;
    } catch {
      return false;
    }
  }

  function applyMarkupShortcut(event) {
    const applied = performMarkupShortcut(event);
    // The listener runs in the capture phase (see DOMContentLoaded): once a
    // shortcut is handled here, stop the event so ProseMirror's own keymap
    // (e.g. Mod-Alt-N -> wrapInHeadingCommand) cannot dispatch a second tr.
    if (applied) event.stopPropagation();
    return applied;
  }

  /** Notion's block shortcuts (spec item 7); every one stops ProseMirror's keymap. */
  function performMarkupShortcut(event) {
    if (mode !== "edit" || view !== "render") return false;
    const meta = event.metaKey || event.ctrlKey;
    if (!meta) return false;

    if (event.altKey) {
      const digit = event.code.match(/^Digit([0-6])$/)?.[1];
      if (digit !== undefined) {
        event.preventDefault();
        turnIntoTarget(
          { 0: "text", 1: "h1", 2: "h2", 3: "h3", 4: "taskList", 5: "bulletList", 6: "orderedList" }[
            digit
          ]
        );
        return true;
      }
      if (event.code === "Period") {
        event.preventDefault();
        turnIntoTarget("quote");
        return true;
      }
      if (event.code === "Minus" || event.code === "NumpadSubtract") {
        event.preventDefault();
        runEditorAction((ctx) => applyBlockOps(ctx, ["insert:hr"]));
        return true;
      }
      if (event.code === "KeyC") {
        event.preventDefault();
        turnIntoTarget("callout");
        return true;
      }
      return false;
    }

    if (event.code === "Slash" || event.code === "NumpadDivide") {
      event.preventDefault();
      openMenuForSelection();
      return true;
    }
    return false;
  }

  async function setMarkdown(markdown) {
    applying = true;
    try {
      if (view === "source" && crepe) {
        // A push while the source view is up only replaces the text.
        rawText = markdown ?? "";
        ensureSource().setText(rawText);
      } else {
        await mount(markdown ?? "");
      }
    } finally {
      applying = false;
    }
  }

  /** Posts the final change and clears the dirty flag; only an edited Document calls it. */
  function postFinalChange() {
    if (!crepe && !source) return;
    window.webkit?.messageHandlers?.kissmark?.postMessage({
      type: "change",
      markdown: (rawText = getMarkdown()),
      final: true,
    });
    userEdited = false;
  }

  async function setMode(next) {
    const normalized = next === "read" ? "read" : "edit";
    if (!crepe) {
      mode = normalized;
      applyModeClass();
      return;
    }
    if (mode === "edit" && normalized === "read" && userEdited) {
      postFinalChange();
    }
    mode = normalized;
    if (view === "source" && source) source.setEditable(mode === "edit");
    crepe.setReadonly(mode === "read");
    applyModeClass();
  }

  /**
   * Swift's "코드 보기" toggle. Callable before or after ready. Switches run one
   * after another, and `view` flips inside the transition's update, so until
   * the repaint happens getMarkdown(), setMarkdown() and setMode() keep
   * addressing the view that is still on screen.
   */
  let viewSwitch = Promise.resolve();
  function setViewMode(next) {
    const target = next === "source" ? "source" : "render";
    if (!crepe) {
      view = target;
      applyViewClass();
      return viewSwitch;
    }
    viewSwitch = viewSwitch
      .then(() => {
        if (target === view && (target === "render" || source)) return undefined;
        return withViewTransition("view", target === "source" ? enterSource : leaveSource);
      })
      // One failed switch must not stall every later one.
      .catch((error) => console.error(error));
    return viewSwitch;
  }

  function getMarkdown(body) {
    if (view === "source" && source) return unescapeCalloutMarkers(source.getText());
    const editor = body ?? (crepe ? crepe.getMarkdown() : "");
    return unescapeCalloutMarkers(joinFrontmatter(front, editor));
  }

  function focus() {
    if (mode === "read") return;
    if (view === "source") {
      source?.focus();
      return;
    }
    const el = document.querySelector(".milkdown .ProseMirror");
    // preventScroll: a focus-induced scroll would rubber-band the page and
    // flash a gap between the action bar and the document info card.
    if (el instanceof HTMLElement) el.focus({ preventScroll: true });
  }

  function setOnChange(fn) {
    onChange = fn;
  }

  /**
   * Swift's document info push (polish 1.5, item 1). Idempotent, callable
   * before ready (stored, rendered after mount) and in any mode or view —
   * the bar is the first element of the scroll flow in both views.
   * A new path (first push after mount, or a document switch) also redraws
   * the properties box, whose title filter depends on the file name.
   */
  function setDocumentInfo(info) {
    const previousPath = docInfo?.path;
    docInfo = info && typeof info === "object" ? info : null;
    renderDocInfoBar();
    if (docInfo?.path !== previousPath) renderFrontmatter();
    if (entrancePending) requestAnimationFrame(playOpeningEntrance);
  }

  /**
   * Swift's review push (round 3). Idempotent, callable before ready and in
   * any mode or view; the highlights are refreshed through a plugin meta.
   */
  function setReview(next) {
    review = next && typeof next === "object" ? next : null;
    renderReviewCard();
    if (crepe) {
      try {
        crepe.editor.action((ctx) => {
          const editorView = ctx.get(editorViewCtx);
          editorView.dispatch(editorView.state.tr.setMeta("kmReview", true).setMeta("addToHistory", false));
        });
      } catch {
        // Not mounted yet: the plugin's init reads `review` on mount.
      }
    }
    if (entrancePending) requestAnimationFrame(playOpeningEntrance);
  }

  /**
   * The opening entrance runs once per surface (every Document gets a fresh
   * page), after the first info push so the info card rises with the text.
   * A later remount (an outside edit, leaving the source view) never replays it.
   */
  let entrancePending = false;
  function armOpeningEntrance() {
    entrancePending = true;
    setTimeout(playOpeningEntrance, ENTRANCE_FALLBACK_MS);
  }

  function playOpeningEntrance() {
    if (!entrancePending) return;
    entrancePending = false;
    const blocks = document.querySelector(".milkdown .ProseMirror")?.children ?? [];
    const targets = [
      document.querySelector("#docinfo:not([hidden]) .km-di-card"),
      document.querySelector("#review:not([hidden]) .km-di-card"),
      document.querySelector("#frontmatter:not([hidden]) .km-fm-box"),
      ...Array.from(blocks).slice(0, ENTRANCE_LIMIT),
    ].filter((el) => el && el.getBoundingClientRect().top < window.innerHeight);
    playEntrance(targets);
  }

  /**
   * Swift's style updates, in send order. A palette change (theme, accent,
   * light/dark, an element color) crossfades the page; anything sent while
   * that crossfade is still capturing joins it, so no older update can land
   * after a newer one. Everything else applies at once and glides on the
   * registered --km-* numbers.
   * @type {Array<() => void> | null}
   */
  let styleQueue = null;
  function applyStyle(apply, crossfade) {
    if (styleQueue) {
      styleQueue.push(apply);
      return;
    }
    if (!crossfade) {
      apply();
      return;
    }
    styleQueue = [apply];
    withViewTransition("theme", () => {
      const queue = styleQueue;
      styleQueue = null;
      for (const run of queue) run();
    });
  }

  function getMode() {
    return mode;
  }

  const menu = createBlockMenu({ onSelect: (key) => turnIntoTarget(key), onClose: () => focus() });

  // A press without movement on the block handle's drag item opens the block
  // menu. The handle is Crepe's, so the press is observed, never owned.
  let handlePress = null;
  window.addEventListener(
    "pointerdown",
    (event) => {
      const item = dragHandleFrom(event.target);
      handlePress = item
        ? { x: event.clientX, y: event.clientY, rect: item.getBoundingClientRect() }
        : null;
    },
    true
  );
  window.addEventListener(
    "pointerup",
    (event) => {
      const press = handlePress;
      handlePress = null;
      if (!press) return;
      if (
        Math.abs(event.clientX - press.x) > CLICK_SLOP ||
        Math.abs(event.clientY - press.y) > CLICK_SLOP
      ) {
        return;
      }
      openMenuForHandle(press.rect);
    },
    true
  );

  // Seed mode before first mount (Swift injects this).
  if (window.__KISSMARK_INITIAL_MODE__ === "read" || window.__KISSMARK_INITIAL_MODE__ === "edit") {
    mode = window.__KISSMARK_INITIAL_MODE__;
  }

  /**
   * 텍스트 정리: replaces banned display punctuation (em/en dash, middle dot)
   * char-for-char in prose text — never inside fenced code or inline code.
   * Edit Mode only (a locked Document never changes); one undoable
   * transaction; every mapping is one character wide, so positions hold.
   * Returns whether anything changed.
   */
  function cleanTypography() {
    if (mode !== "edit" || view === "source" || !crepe) return false;
    return crepe.editor.action((ctx) => {
      const editorView = ctx.get(editorViewCtx);
      const { state } = editorView;
      const tr = state.tr;
      let changed = false;
      state.doc.descendants((node, pos) => {
        if (!node.isText) return true;
        if (node.marks.some((mark) => mark.type.name === "inlineCode" || mark.type.spec.code)) return true;
        // `node.parent` is unset on traversal callbacks; resolve instead.
        const $from = state.doc.resolve(pos);
        for (let depth = $from.depth; depth > 0; depth--) {
          const ancestor = $from.node(depth);
          if (ancestor.type.name === "code_block" || ancestor.type.spec.code) return true;
        }
        if (!BANNED_TYPOGRAPHY.test(node.text ?? "")) return true;
        const next = lintTypographyText(node.text);
        if (next !== node.text) {
          tr.replaceWith(pos, pos + node.text.length, state.schema.text(next, node.marks));
          changed = true;
        }
        return false;
      });
      if (changed) editorView.dispatch(tr);
      return changed;
    });
  }

  return {
    mount,
    setMarkdown,
    setMode,
    setViewMode,
    getMode,
    getMarkdown,
    focus,
    setOnChange,
    setDocumentInfo,
    applyMarkupShortcut,
    setReview,
    armOpeningEntrance,
    applyStyle,
    cleanTypography,
  };
}

window.KissmarkEditor = createAPI();

// Static chrome of editor.html follows the running app language (set before first paint of the mounted editor).
document.documentElement.lang = uiLanguage();
document.getElementById("source")?.setAttribute("aria-label", uiText("원문"));

window.addEventListener("DOMContentLoaded", () => {
  const initial = window.__KISSMARK_INITIAL_MARKDOWN__ ?? "";
  window.KissmarkEditor.mount(initial).then(() => {
    window.KissmarkEditor.armOpeningEntrance();
    window.webkit?.messageHandlers?.kissmark?.postMessage({
      type: "ready",
      markdown: window.KissmarkEditor.getMarkdown(),
      mode: window.KissmarkEditor.getMode(),
    });
  }).catch((error) => {
    window.webkit?.messageHandlers?.kissmark?.postMessage({
      type: "error",
      message: String(error?.message ?? error),
    });
  });

  window.KissmarkEditor.setOnChange((markdown) => {
    window.webkit?.messageHandlers?.kissmark?.postMessage({
      type: "change",
      markdown,
    });
  });

  // Capture phase + stopPropagation (inside applyMarkupShortcut when it handles
  // the key): ProseMirror's keymap listens on view.dom and runs before a
  // bubble-phase window listener — without this it would dispatch a second,
  // duplicate tr for every markup shortcut we handle.
  window.addEventListener("keydown", (event) => {
    window.KissmarkEditor.applyMarkupShortcut(event);
  }, true);
});
