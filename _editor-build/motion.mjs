/**
 * Script-driven motion reads the same tokens as the stylesheet: reader.css
 * owns `--km-dur-*`, `--km-ease-out`, `--km-spring`, `--km-rise`, … on :root
 * (Reduce Motion already swaps them there), so WAAPI calls never hard-code a
 * second copy of the timing.
 */

/** @param {string} name a `--km-*` custom property on :root */
export function cssToken(name) {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

/** A `--km-dur-*` token in milliseconds (`160ms`, `0.2s`, or `0s`). */
export function cssDuration(name) {
  const value = cssToken(name);
  const number = parseFloat(value);
  if (!Number.isFinite(number)) return 0;
  return value.endsWith("ms") ? number : number * 1000;
}

export function prefersReducedMotion() {
  return window.matchMedia?.("(prefers-reduced-motion: reduce)").matches === true;
}

/**
 * `el.animate` with a token easing; an engine without `linear()` (Safari
 * before 17.2) rejects the spring, so it falls back to the ease-out curve.
 * @param {Element} el @param {Keyframe[]} keyframes @param {KeyframeAnimationOptions} options
 */
export function animateWithToken(el, keyframes, options) {
  if (typeof el.animate !== "function") return null;
  try {
    return el.animate(keyframes, options);
  } catch {
    return el.animate(keyframes, { ...options, easing: cssToken("--km-ease-out") || "ease-out" });
  }
}

/**
 * Staggered arrival of a freshly opened Document: each element rises from
 * `--km-rise` out of a `--km-blur` blur on the spring, `--km-stagger` apart.
 * Reduce Motion: one short fade, no travel. WAAPI leaves the DOM untouched,
 * so ProseMirror never sees a mutation.
 * @param {Element[]} elements in reading order
 */
export function playEntrance(elements) {
  const reduce = prefersReducedMotion();
  const from = reduce
    ? { opacity: 0 }
    : { opacity: 0, translate: `0 ${cssToken("--km-rise")}`, filter: `blur(${cssToken("--km-blur")})` };
  const to = reduce ? { opacity: 1 } : { opacity: 1, translate: "0 0", filter: "blur(0px)" };
  const duration = cssDuration(reduce ? "--km-dur" : "--km-dur-spring");
  const easing = cssToken(reduce ? "--km-ease-out" : "--km-spring");
  const stagger = reduce ? 0 : cssDuration("--km-stagger");
  elements.forEach((el, i) => {
    animateWithToken(el, [from, to], { duration, delay: i * stagger, easing, fill: "backwards" });
  });
}

let activeTransition = null;

/**
 * Runs `update` inside a same-document view transition (Safari 18+) tagged
 * `kind` for reader.css (`theme` crossfades, `view` blurs through). Without
 * the API, or while one is already running (a dragged color keeps changing),
 * `update` applies directly: the running transition's new layer is live.
 * @param {"theme" | "view"} kind @param {() => unknown} update
 */
export function withViewTransition(kind, update) {
  if (typeof document.startViewTransition !== "function" || activeTransition) return update();
  const root = document.documentElement;
  root.dataset.kmTransition = kind;
  const transition = document.startViewTransition(update);
  activeTransition = transition;
  transition.ready.catch(() => {});
  transition.finished
    .catch(() => {})
    .then(() => {
      if (activeTransition !== transition) return;
      activeTransition = null;
      delete root.dataset.kmTransition;
    });
  return transition.updateCallbackDone;
}