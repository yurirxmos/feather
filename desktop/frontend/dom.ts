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
