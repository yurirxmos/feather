type Child = Node | string | null | undefined | false;

/** Creates an element. Text is always set through text nodes, never parsed as HTML. */
export function h<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attributes: Record<string, string | boolean | ((event: Event) => void)> = {},
  ...children: Child[]
): HTMLElementTagNameMap[K] {
  const element = document.createElement(tag);
  for (const [name, value] of Object.entries(attributes)) {
    if (typeof value === "function") {
      element.addEventListener(name.replace(/^on/, "").toLowerCase(), value);
    } else if (value === true) {
      element.setAttribute(name, "");
    } else if (value !== false) {
      element.setAttribute(name, value);
    }
  }
  for (const child of children) {
    if (child) element.append(child);
  }
  return element;
}

const SVG = "http://www.w3.org/2000/svg";

/** The white feather from the app icon on a 24x24 grid, filled; shared with the macOS app's `FeatherShape`. */
export function featherIcon(className = "feather-icon"): SVGSVGElement {
  const svg = document.createElementNS(SVG, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("class", className);
  svg.setAttribute("aria-hidden", "true");
  const path = document.createElementNS(SVG, "path");
  path.setAttribute(
    "d",
    "M20.873 1.139C20.592 1.561 19.355 2.174 18.177 2.476C17.595 2.621 16.996 2.729 15.828 2.888C14.557 3.065 14.294 3.11 13.68 3.255C12.035 3.643 10.583 4.447 9.412 5.615C8.736 6.294 8.182 7.063 8.089 7.461C8.071 7.531 7.946 7.676 7.711 7.894C6.041 9.471 4.828 11.473 4.447 13.299C4.277 14.113 4.236 15.226 4.343 16.157C4.374 16.424 4.409 17.02 4.42 17.481C4.43 17.966 4.451 18.312 4.471 18.302C4.489 18.292 4.61 18.066 4.742 17.807C6.176 14.938 10.06 10.625 13.174 8.431C14.321 7.628 16.161 6.675 16.733 6.592C16.871 6.574 16.84 6.599 16.4 6.855C13.847 8.352 11.775 10.295 8.626 14.148C7.974 14.945 6.273 17.124 5.556 18.077C5.518 18.125 5.355 18.337 5.192 18.548C4.077 19.975 3.089 21.389 2.809 21.957C2.372 22.837 3.11 23.391 3.761 22.674C3.886 22.539 4.031 22.286 4.329 21.68C5.133 20.069 5.837 19.182 6.845 18.51C7.829 17.855 8.681 17.574 10.51 17.301C11.972 17.083 12.388 16.968 13.209 16.552C13.964 16.171 14.817 15.496 15.277 14.917C15.451 14.699 15.447 14.678 15.243 14.74C15.025 14.803 14.12 14.997 14.103 14.983C14.096 14.976 14.238 14.893 14.415 14.796C15.797 14.048 16.646 13.226 17.242 12.059C17.498 11.563 17.661 10.988 17.568 10.929C17.554 10.923 17.37 10.981 17.162 11.065C16.442 11.352 15.936 11.453 14.72 11.55C14.082 11.602 13.632 11.66 13.424 11.726L13.351 11.751L13.42 11.671C13.777 11.266 15 10.697 16.504 10.233C17.647 9.88 18.33 9.485 19.054 8.764C20.142 7.673 20.914 6.193 21.216 4.62C21.434 3.47 21.33 1.204 21.049 1.028C20.984 0.986 20.97 0.993 20.873 1.139Z",
  );
  svg.append(path);
  return svg;
}

/** A large four-point sparkle with a small one beside it, for Feather Plus, on a 24x24 grid. */
export function sparkleIcon(className = "sparkle"): SVGSVGElement {
  const svg = document.createElementNS(SVG, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("class", className);
  svg.setAttribute("aria-hidden", "true");
  for (const d of ["M10 3.5l1.9 5.6 5.6 1.9-5.6 1.9L10 18.5l-1.9-5.6L2.5 11l5.6-1.9Z", "M18.5 3l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8Z", "M18.5 15.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7Z"]) {
    const path = document.createElementNS(SVG, "path");
    path.setAttribute("d", d);
    svg.append(path);
  }
  return svg;
}

/** A head over shoulders, like SF Symbols' `person.crop.circle`, for the Account tab, on a 24x24 grid. */
export function personIcon(className = "glyph"): SVGSVGElement {
  const svg = document.createElementNS(SVG, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("class", className);
  svg.setAttribute("aria-hidden", "true");
  for (const d of ["M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z", "M4.5 20.5c1.2-3.6 4-5.5 7.5-5.5s6.3 1.9 7.5 5.5"]) {
    const path = document.createElementNS(SVG, "path");
    path.setAttribute("d", d);
    svg.append(path);
  }
  return svg;
}

/** A circle around three dots, like SF Symbols' `ellipsis.circle` on the macOS app's row menus. */
export function moreIcon(): SVGSVGElement {
  const svg = document.createElementNS(SVG, "svg");
  svg.setAttribute("viewBox", "0 0 20 20");
  svg.setAttribute("class", "more-icon");
  svg.setAttribute("aria-hidden", "true");
  const ring = document.createElementNS(SVG, "circle");
  ring.setAttribute("cx", "10");
  ring.setAttribute("cy", "10");
  ring.setAttribute("r", "8.25");
  ring.setAttribute("fill", "none");
  ring.setAttribute("stroke", "currentColor");
  ring.setAttribute("stroke-width", "1.5");
  svg.append(ring);
  for (const cx of ["6.25", "10", "13.75"]) {
    const dot = document.createElementNS(SVG, "circle");
    dot.setAttribute("cx", cx);
    dot.setAttribute("cy", "10");
    dot.setAttribute("r", "1.25");
    dot.setAttribute("fill", "currentColor");
    svg.append(dot);
  }
  return svg;
}

/**
 * The provider row icons, on a 20x20 grid, like the SF Symbols the macOS app uses: `check`
 * (checkmark.circle.fill), `circle`, `plus` (plus.circle), `plusFilled` (plus.circle.fill),
 * `card` (creditcard), `cancel` (xmark.circle), `signOut` (rectangle.portrait.and.arrow.right),
 * `success` (checkmark.circle), and `info` (info.circle).
 */
export function rowIcon(
  name: "check" | "circle" | "plus" | "plusFilled" | "card" | "cancel" | "signOut" | "success" | "info",
): SVGSVGElement {
  const svg = document.createElementNS(SVG, "svg");
  svg.setAttribute("viewBox", "0 0 20 20");
  svg.setAttribute("class", `row-icon ${name}`);
  svg.setAttribute("aria-hidden", "true");
  const add = (tag: string, attributes: Record<string, string>) => {
    const element = document.createElementNS(SVG, tag);
    for (const [key, value] of Object.entries(attributes)) element.setAttribute(key, value);
    svg.append(element);
  };
  const stroke = { fill: "none", stroke: "currentColor", "stroke-width": "1.5", "stroke-linecap": "round", "stroke-linejoin": "round" };
  const ring = () => add("circle", { cx: "10", cy: "10", r: "8.25", ...stroke });
  const filled = () => add("circle", { cx: "10", cy: "10", r: "9", fill: "currentColor" });
  const onFill = { ...stroke, stroke: "var(--on-icon, #fff)", "stroke-width": "1.75" };
  switch (name) {
    case "check":
      filled();
      add("path", { d: "M6.2 10.3l2.5 2.5 5.1-5.4", ...onFill });
      break;
    case "circle":
      ring();
      break;
    case "plus":
      ring();
      add("path", { d: "M10 6.5v7M6.5 10h7", ...stroke });
      break;
    case "plusFilled":
      filled();
      add("path", { d: "M10 6.5v7M6.5 10h7", ...onFill });
      break;
    case "card":
      add("rect", { x: "2.25", y: "4.75", width: "15.5", height: "10.5", rx: "2", ...stroke });
      add("path", { d: "M2.25 8.25h15.5M5.5 12.25h3", ...stroke });
      break;
    case "cancel":
      ring();
      add("path", { d: "M7.5 7.5l5 5M12.5 7.5l-5 5", ...stroke });
      break;
    case "signOut":
      add("path", { d: "M8 3.75H5.5a1.75 1.75 0 0 0-1.75 1.75v9A1.75 1.75 0 0 0 5.5 16.25H8", ...stroke });
      add("path", { d: "M8.5 10h8M13.5 6.75L16.75 10l-3.25 3.25", ...stroke });
      break;
    case "success":
      ring();
      add("path", { d: "M6.6 10.2l2.3 2.3 4.6-4.9", ...stroke });
      break;
    case "info":
      ring();
      add("path", { d: "M10 9v5", ...stroke });
      add("circle", { cx: "10", cy: "6.4", r: "0.9", fill: "currentColor" });
      break;
  }
  return svg;
}

/** Material's `keyboard_return` glyph on a 24x24 grid, shared with the macOS app's `ReturnKeyShape`. */
export function returnKeyIcon(): SVGSVGElement {
  const svg = document.createElementNS(SVG, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("class", "return-key-icon");
  svg.setAttribute("aria-hidden", "true");
  const path = document.createElementNS(SVG, "path");
  path.setAttribute("d", "M19 7v4H5.83l3.58-3.59L8 6l-6 6 6 6 1.41-1.41L5.83 13H21V7z");
  svg.append(path);
  return svg;
}
