/**
 * Icons for the Kissmark Document surface that Crepe does not ship:
 * the list markers (bullet / checkbox) and the glyphs of our own block menu.
 *
 * List markers go through Crepe's `ListItem` feature config and are inserted
 * with `innerHTML` after DOMPurify, so they stay to plain SVG shapes. Colours
 * come from CSS (`currentColor` / `fill`), never from attributes, so the theme
 * tokens stay the single source of truth.
 */

/** Bullet dot: one circle, sized by CSS to the body text. */
export const bulletIcon = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><circle cx="8" cy="8" r="2.6"/></svg>`;

/** Unchecked task box: hairline outline in the body text colour. */
export const checkBoxUncheckedIcon = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><rect x="2" y="2" width="12" height="12" rx="3" fill="none" stroke="currentColor" stroke-width="1.5"/></svg>`;

/** Checked task box: filled with the body text colour, check stroked in the page background. */
export const checkBoxCheckedIcon = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><rect x="2" y="2" width="12" height="12" rx="3" fill="currentColor"/><path class="km-check" d="M4.9 8.4l2.1 2.1 4.1-4.6" fill="none" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>`;

const svg = (body) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;

const dot = (cy) => `<circle cx="2.6" cy="${cy}" r="1.1" fill="currentColor" stroke="none"/>`;

/** Glyphs for the block menu rows. SVG values are markup, the rest are monograms. */
export const MENU_GLYPHS = {
  text: "T",
  h1: "H1",
  h2: "H2",
  h3: "H3",
  h4: "H4",
  h5: "H5",
  orderedList: "1.",
  bulletList: svg(`<path d="M6 4h8M6 8h8M6 12h8"/>${dot(4)}${dot(8)}${dot(12)}`),
  taskList: svg(`<rect x="1.4" y="1.4" width="6" height="6" rx="1.6"/><path d="M3 4.6l1.2 1.2 2-2.3"/><path d="M10 4.5h4.6M10 11.5h4.6M1.5 11.5h5"/>`),
  quote: svg(`<path d="M4 3v10"/><path d="M7 5h7M7 9h5"/>`),
  callout: svg(`<rect x="1.4" y="2.4" width="13.2" height="11.2" rx="2.4"/><path d="M4.4 6.6h7.2M4.4 9.6h4.6"/>`),
};

/** Check mark for the current block kind in the block menu. */
export const CHECK_GLYPH = svg(`<path d="M3.5 8.6l3 3 6-7"/>`);
