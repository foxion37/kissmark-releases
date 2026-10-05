/**
 * Source view (spec item 6): CodeMirror 6 over the raw Markdown file, frontmatter
 * included, inside the same WKWebView as Crepe.
 *
 * The surface keeps one view for the lifetime of the page; entering source view
 * hides Crepe and shows this one, leaving it hands the text back so Crepe mounts
 * from it. Edits are reported through the same debounced `change` message as
 * Crepe's, so Swift sees no difference between the two views.
 *
 * Theming is `reader.css` (the surface's CSS SSOT): this module only wires the
 * extensions, the Markdown language and the syntax colours, which have to be
 * inline styles because they are generated per token class.
 */

import { EditorState, Compartment } from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { markdown } from "@codemirror/lang-markdown";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags } from "@lezer/highlight";

const highlight = HighlightStyle.define([
  { tag: tags.heading, color: "var(--km-text)", fontWeight: "650" },
  { tag: tags.strong, fontWeight: "650" },
  { tag: tags.emphasis, fontStyle: "italic" },
  { tag: tags.strikethrough, textDecoration: "line-through" },
  { tag: tags.link, color: "var(--km-accent)", textDecoration: "underline" },
  { tag: tags.url, color: "var(--km-muted)" },
  { tag: tags.monospace, color: "var(--km-code-fg)" },
  { tag: tags.quote, color: "var(--km-muted)" },
  { tag: tags.processingInstruction, color: "var(--km-muted)" },
  { tag: tags.meta, color: "var(--km-muted)" },
]);

/**
 * @param {{ parent: HTMLElement, onDocChanged: (markdown: string) => void }} options
 */
export function createSourceView({ parent, onDocChanged }) {
  const editable = new Compartment();
  /** @type {EditorView | null} */
  let view = null;
  /** Set while the surface replaces the document itself (no user edit). */
  let applying = false;

  /** Extensions that differ between read and edit mode. */
  function access(isEditable) {
    return [EditorView.editable.of(isEditable), EditorState.readOnly.of(!isEditable)];
  }

  function extensions(isEditable) {
    return [
      EditorView.lineWrapping,
      history(),
      keymap.of([...defaultKeymap, ...historyKeymap]),
      markdown(),
      syntaxHighlighting(highlight),
      editable.of(access(isEditable)),
      EditorView.updateListener.of((update) => {
        if (update.docChanged && !applying) onDocChanged(update.state.doc.toString());
      }),
    ];
  }

  function doc() {
    return view ? view.state.doc.toString() : "";
  }

  /** Replaces the whole document without reporting it as a user edit. */
  function setText(markdown) {
    if (!view) return;
    const next = markdown ?? "";
    if (view.state.doc.toString() === next) return;
    applying = true;
    try {
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: next } });
    } finally {
      applying = false;
    }
  }

  /** Shows `markdown` in the source view, creating the editor on first use. */
  function attach(markdown, isEditable) {
    if (!view) {
      view = new EditorView({
        parent,
        state: EditorState.create({ doc: markdown ?? "", extensions: extensions(isEditable) }),
      });
      return;
    }
    view.dispatch({ effects: editable.reconfigure(access(isEditable)) });
    setText(markdown);
  }

  function setEditable(isEditable) {
    if (!view) return;
    view.dispatch({ effects: editable.reconfigure(access(isEditable)) });
  }

  return {
    attach,
    setText,
    setEditable,
    getText: doc,
    focus: () => view?.focus(),
  };
}
