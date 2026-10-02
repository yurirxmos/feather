// The prompt panel, mirroring `PromptView` in the macOS app. It renders `PanelState` from Rust and
// sends intents back; captured content never lives here beyond the selection preview.

import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { h, featherIcon } from "./dom";
import { t } from "./i18n";

type ContextOptions = {
  includeApp: boolean;
  includeFocusedText: boolean;
  includeSelection: boolean;
  includeWindowText: boolean;
  includeWindow: boolean;
};

type PanelState = {
  appName: string | null;
  selectedPreview: string | null;
  hasFocusedText: boolean;
  hasWindowText: boolean;
  windowTextWasTruncated: boolean;
  options: ContextOptions;
  isCapturing: boolean;
  captureStatus: "readingScreen" | "capturingWindow" | null;
  result: string;
  streamingResult: string;
  isGenerating: boolean;
  generationStartedAt: number | null;
  errorMessage: string | null;
  notice: string | null;
  focusToken: number;
  restoreInstruction: string | null;
  restoreToken: number;
};

/** "12s" under a minute, then "1m 5s", then "1h 2m", like `ElapsedTime` in the macOS app. */
export function elapsed(seconds: number): string {
  const total = Math.max(0, Math.floor(seconds));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  if (hours > 0) return `${hours}h ${minutes}m`;
  if (minutes > 0) return `${minutes}m ${total % 60}s`;
  return `${total}s`;
}

export async function startPanel(root: HTMLElement): Promise<void> {
  document.body.classList.add("panel-body");

  const field = h("textarea", { class: "instruction", rows: "1", spellcheck: "true", "aria-label": t("What do you want to write?") });
  const icon = featherIcon();
  const content = h("div", { class: "panel-content" });
  const footer = h("div", { class: "panel-footer" });
  const panel = h(
    "section",
    { class: "panel", "data-tauri-drag-region": true },
    content,
    h("div", { class: "input-row" }, icon, field),
    footer,
  );
  root.replaceChildren(panel);

  let state: PanelState = await invoke<PanelState>("prompt_state");
  let focusToken = -1;
  let restoreToken = state.restoreToken;
  let timer: number | undefined;
  let typingTimer: number | undefined;

  const autosize = () => {
    field.style.height = "auto";
    field.style.height = `${Math.min(field.scrollHeight, 5 * 24)}px`;
  };

  const render = () => {
    const hasResult = state.result !== "" || state.isGenerating;
    const canInsert = state.result !== "" && !state.isGenerating;
    field.placeholder = hasResult ? t("Refine: shorter, more formal…") : t("What do you want to write?");
    field.disabled = state.isGenerating;
    panel.classList.toggle("generating", state.isGenerating);

    const blocks: (Node | null)[] = [];
    if (state.selectedPreview) blocks.push(h("p", { class: "selection-preview" }, state.selectedPreview));
    if (state.windowTextWasTruncated) blocks.push(h("p", { class: "caption" }, `ⓘ ${t("Partial context")}`));
    if (state.result) blocks.push(responseBlock(state.result, state.isGenerating));
    content.replaceChildren(...blocks.filter((block): block is Node => block !== null));

    const below: Node[] = [];
    window.clearInterval(timer);
    if (state.isGenerating) {
      const clock = h("span", { class: "elapsed" });
      const tick = () => {
        clock.textContent = elapsed((Date.now() - (state.generationStartedAt ?? Date.now())) / 1000);
      };
      tick();
      timer = window.setInterval(tick, 1000);
      below.push(
        h("hr"),
        h(
          "div",
          { class: "generating-row" },
          h("span", { class: "generating-label" }, t("Generating…")),
          clock,
          h("button", { class: "small-button", type: "button", onclick: () => void invoke("prompt_cancel_generation") }, t("Cancel")),
        ),
      );
      if (state.streamingResult) below.push(responseBlock(state.streamingResult, true));
    }
    if (state.errorMessage) below.push(h("p", { class: "error", role: "alert" }, `⚠ ${state.errorMessage}`));
    if (state.notice) below.push(h("p", { class: "notice", role: "status" }, state.notice));

    const chips = h("div", { class: "chips" });
    if (state.appName) chips.append(chip(state.appName, state.options.includeApp, "app"));
    if (state.selectedPreview !== null) chips.append(chip(t("Text selected"), state.options.includeSelection, "selection"));
    if (state.hasFocusedText) chips.append(chip(t("Focused text"), state.options.includeFocusedText, "focusedText"));
    if (state.isCapturing) {
      chips.append(
        h(
          "span",
          { class: "capturing" },
          h("span", { class: "spinner", "aria-hidden": "true" }),
          state.captureStatus === "capturingWindow" ? t("Capturing window…") : t("Reading screen…"),
        ),
      );
    }
    if (!state.appName && state.selectedPreview === null && !state.hasWindowText) {
      chips.append(h("span", { class: "caption" }, t("No app context")));
    }

    const hints = h("div", { class: "hints" });
    if (canInsert) {
      hints.append(
        keyHint("↵", t("Insert"), true),
        keyHint("Ctrl ↵", t("Copy"), false, () => void invoke("prompt_copy")),
        keyHint("Ctrl R", t("Retry"), false, () => void invoke("prompt_regenerate")),
      );
    } else {
      hints.append(keyHint("↵", t("Generate")));
    }
    footer.replaceChildren(...below, h("div", { class: "footer-row" }, chips, hints));

    if (state.focusToken !== focusToken || (!state.isGenerating && document.activeElement !== field)) {
      focusToken = state.focusToken;
      field.focus();
    }
    if (state.restoreToken !== restoreToken) {
      restoreToken = state.restoreToken;
      if (state.restoreInstruction && field.value === "") {
        field.value = state.restoreInstruction;
        autosize();
      }
    }
  };

  field.addEventListener("input", () => {
    autosize();
    icon.classList.toggle("typing", field.value !== "");
    window.clearTimeout(typingTimer);
    typingTimer = window.setTimeout(() => icon.classList.remove("typing"), 420);
  });

  window.addEventListener("keydown", (event) => {
    const control = event.ctrlKey || event.metaKey;
    if (event.key === "Escape") {
      event.preventDefault();
      void invoke("prompt_dismiss");
    } else if (event.key === "Enter" && control && !event.shiftKey && !event.altKey) {
      event.preventDefault();
      void invoke("prompt_copy");
    } else if (event.key === "Enter" && !control && !event.shiftKey && !event.altKey) {
      event.preventDefault();
      const instruction = field.value;
      void invoke("prompt_submit", { instruction });
      if (instruction.trim() !== "") {
        field.value = "";
        autosize();
      }
    } else if (control && !event.shiftKey && !event.altKey && event.key.toLowerCase() === "r") {
      event.preventDefault();
      void invoke("prompt_regenerate");
    }
  });

  // The window follows the panel's height, growing upward from its anchored bottom edge.
  new ResizeObserver(() => {
    void invoke("panel_resize", { height: Math.ceil(panel.getBoundingClientRect().height) });
  }).observe(panel);

  await listen<PanelState>("prompt-state", (event) => {
    state = event.payload;
    render();
  });
  render();
}

function responseBlock(text: string, muted: boolean): HTMLElement {
  return h("div", { class: muted ? "response muted" : "response" }, text);
}

function chip(title: string, isOn: boolean, option: string): HTMLElement {
  return h(
    "button",
    {
      class: isOn ? "chip" : "chip off",
      type: "button",
      "aria-pressed": String(isOn),
      onclick: () => void invoke("prompt_toggle_option", { option }),
    },
    title,
  );
}

function keyHint(key: string, label: string, highlighted = false, action?: () => void): HTMLElement {
  const content = [h("kbd", {}, key), h("span", {}, label)];
  const className = highlighted ? "key-hint highlighted" : "key-hint";
  return action
    ? h("button", { class: className, type: "button", "aria-label": label, onclick: action }, ...content)
    : h("span", { class: className }, ...content);
}
