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

/** The Feather glyph on a 24x24 grid, shared with the macOS app's `FeatherShape`. */
export function featherIcon(className = "feather-icon"): SVGSVGElement {
  const svg = document.createElementNS(SVG, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("class", className);
  svg.setAttribute("aria-hidden", "true");
  const path = document.createElementNS(SVG, "path");
  path.setAttribute(
    "d",
    "M12.67 19C13.201 19 13.71 18.789 14.086 18.412L20.24 12.24C22.583 9.897 22.583 6.097 20.24 3.75C17.897 1.407 14.097 1.407 11.75 3.75L5.586 9.914C5.211 10.289 5 10.798 5 11.328V18C5 18.552 5.448 19 6 19Z M16 8 2 22 M17.5 15H9",
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
 * `card` (creditcard), `cancel` (xmark.circle), and `signOut` (rectangle.portrait.and.arrow.right).
 */
export function rowIcon(name: "check" | "circle" | "plus" | "plusFilled" | "card" | "cancel" | "signOut"): SVGSVGElement {
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
