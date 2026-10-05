/**
 * App-owned UI copy. Swift resolves the running language from the app
 * catalogue and injects `window.__KISSMARK_UI__ = { language, messages }`
 * before this bundle runs; messages are keyed by the catalogue's Korean source
 * string. A missing entry (tests, standalone fixture) shows the key itself.
 * Never route user Markdown, paths, quotes or comments through here.
 */

const ui = () => globalThis.__KISSMARK_UI__;

/** @param {string} key catalogue key (Korean source copy) */
export function uiText(key) {
  const value = ui()?.messages?.[key];
  return typeof value === "string" && value !== "" ? value : key;
}

export function uiLanguage() {
  const language = ui()?.language;
  return typeof language === "string" && language !== "" ? language : "ko";
}
