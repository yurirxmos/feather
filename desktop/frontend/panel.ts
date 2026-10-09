// The prompt panel, mirroring `PromptView` in the macOS app. It renders `PanelState` from Rust and
// sends intents back; captured content never lives here beyond the selection preview.

import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { h, featherIcon, returnKeyIcon, rowIcon } from "./dom";
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
  /** The shortcut was pressed while typing in a field, such as a message or email body. */
  focusIsInTextField: boolean;
  options: ContextOptions;
  isCapturing: boolean;
  captureStatus: "readingScreen" | "capturingWindow" | null;
  result: string;
  streamingResult: string;
  answer: string;
  streamingAnswer: string;
  isGenerating: boolean;
  generationStartedAt: number | null;
  errorMessage: string | null;
  notice: string | null;
  /** Whether `notice` reports something done, such as a copy, rather than something to review. */
  noticeIsSuccess: boolean;
  /** Shown alone, briefly, after a reply was pasted. */
  confirmation: string | null;
  /** No provider is connected yet, so the panel only offers to open Settings. */
  needsSetup: boolean;
  /** The app Insert pastes into. */
  insertTarget: string | null;
  captureCount: number;
  hasScreenshot: boolean;
  /** How many recent conversations ↑ can bring back. */
  recentCount: number;
  focusToken: number;
  restoreInstruction: string | null;
  restoreToken: number;
  /** Set while ↑ and ↓ show a recent conversation. */
  browsing: { position: number; count: number; instruction: string } | null;
  /** The last instruction was a question on a connection that only assists typing. */
  suggestsPlus: boolean;
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
  const inputRow = h("div", { class: "input-row" }, icon, field);
  const footer = h("div", { class: "panel-footer" });
  // Status changes the panel shows only visually are read out from here. It stays in the page,
  // because screen readers only announce changes to a live region that already exists.
  const announcer = h("p", { class: "sr-only", "aria-live": "polite" });
  const panel = h("section", { class: "panel", "data-tauri-drag-region": true }, content, inputRow, footer);
  root.replaceChildren(panel, announcer);

  // Drawn, wired, and sized before asking Rust for anything, so the panel stays usable and shows
  // the reason if the state cannot be loaded.
  let state: PanelState = EMPTY_STATE;
  let focusToken = -1;
  let restoreToken = state.restoreToken;
  let timer: number | undefined;
  let typingTimer: number | undefined;
  let hints = h("div", { class: "hints" });

  const autosize = () => {
    field.style.height = "auto";
    field.style.height = `${Math.min(field.scrollHeight, 5 * 24)}px`;
  };

  const announce = (message: string | null) => {
    if (!message) return;
    announcer.textContent = "";
    // Setting the text after a frame makes a repeated message announce again.
    window.requestAnimationFrame(() => (announcer.textContent = message));
  };

  const submit = () => {
    const instruction = field.value;
    void invoke("prompt_submit", { instruction });
    if (instruction.trim() !== "" && !state.needsSetup) {
      field.value = "";
      autosize();
      renderHints();
    }
  };

  const newConversation = () => {
    field.value = "";
    autosize();
    void invoke("prompt_new_conversation");
  };

  const hasResult = () => state.result !== "" || state.answer !== "" || state.isGenerating;
  const canInsert = () => state.result !== "" && !state.isGenerating;
  const canCopyAnswer = () => state.result === "" && state.answer !== "" && !state.isGenerating;

  /** Enter refines or generates while there is an instruction, and inserts once the field is
   * empty and a reply is ready; the hint always names what Enter will do. */
  const renderHints = () => {
    const next = h("div", { class: "hints" });
    // Ctrl+N works at any time; the hint shows once there is a conversation to leave.
    if (hasResult()) next.append(keyHint(["Ctrl N"], t("New"), false, newConversation));
    if (field.value.trim() !== "" && !state.isGenerating) {
      next.append(keyHint([returnKeyIcon()], hasResult() ? t("Refine") : t("Generate"), false, submit));
    } else if (canInsert()) {
      const label = state.insertTarget ? t("Insert into {app}", { app: state.insertTarget }) : t("Insert");
      next.append(keyHint([returnKeyIcon()], label, true, () => void invoke("prompt_insert")));
    } else if (canCopyAnswer()) {
      // Only an answer came back, so there is nothing to insert.
      next.append(keyHint([returnKeyIcon()], t("Copy"), true, () => void invoke("prompt_copy")));
    } else if (field.value === "" && !hasResult() && !state.browsing && state.recentCount > 0) {
      next.append(keyHint(["↑"], t("Recent"), false, () => void invoke("prompt_browse", { direction: "older" })));
    }
    if (canInsert()) next.append(keyHint(["Ctrl", returnKeyIcon()], t("Copy"), false, () => void invoke("prompt_copy")));
    if (canInsert() || canCopyAnswer()) next.append(keyHint(["Ctrl R"], t("Retry"), false, () => void invoke("prompt_regenerate")));
    hints.replaceWith(next);
    hints = next;
  };

  const renderSetup = () => {
    inputRow.hidden = true;
    content.replaceChildren(
      h("div", { class: "setup" }, featherIcon(), h("p", { class: "setup-text" }, t("Connect a provider in Settings so Feather can write for you."))),
    );
    footer.replaceChildren(
      h("div", { class: "footer-row end" }, keyHint([returnKeyIcon()], t("Open Settings"), true, () => void invoke("prompt_open_settings"))),
    );
  };

  const renderConfirmation = (text: string) => {
    inputRow.hidden = true;
    footer.replaceChildren();
    const check = rowIcon("success");
    check.classList.add("confirmation-icon");
    content.replaceChildren(h("p", { class: "confirmation" }, check, h("span", {}, text)));
  };

  const render = () => {
    window.clearInterval(timer);
    panel.classList.toggle("generating", state.isGenerating);
    if (state.confirmation) return renderConfirmation(state.confirmation);
    if (state.needsSetup) return renderSetup();
    inputRow.hidden = false;

    field.placeholder = hasResult() ? t("Refine: shorter, more formal…") : t("What do you want to write?");
    // The panel opens before the window text is read; typing waits for it.
    field.disabled = state.isGenerating || state.captureStatus === "readingScreen";

    // Once a new reply starts arriving it takes the place of the previous one, so there is only
    // ever one reply on screen, always in the same spot above the field.
    const isStreaming = state.isGenerating && (state.streamingAnswer !== "" || state.streamingResult !== "");
    const answer = isStreaming ? state.streamingAnswer : state.answer;
    const result = isStreaming ? state.streamingResult : state.result;

    const blocks: (Node | null)[] = [];
    if (state.selectedPreview) blocks.push(h("p", { class: "selection-preview" }, state.selectedPreview));
    if (state.browsing) blocks.push(browsingCaption(state.browsing));
    // Paid plans answer questions; the answer is for reading and only the suggestion is inserted.
    if (answer) blocks.push(h("p", { class: "block-label" }, t("Answer")), h("p", { class: state.isGenerating ? "answer muted" : "answer" }, answer));
    if (answer && result) blocks.push(h("p", { class: "block-label" }, t("Suggested text")));
    if (result) blocks.push(responseBlock(result, state.isGenerating));
    content.replaceChildren(...blocks.filter((block): block is Node => block !== null));

    const below: Node[] = [];
    if (state.isGenerating) {
      const clock = h("span", { class: "elapsed", "aria-hidden": "true" });
      const tick = () => {
        clock.textContent = elapsed((Date.now() - (state.generationStartedAt ?? Date.now())) / 1000);
      };
      tick();
      timer = window.setInterval(tick, 1000);
      below.push(
        h(
          "div",
          { class: "generating-row" },
          h("span", { class: "generating-label" }, t("Generating…")),
          clock,
          h(
            "button",
            { class: "small-button", type: "button", "aria-label": t("Cancel"), onclick: () => void invoke("prompt_cancel_generation") },
            t("Cancel"),
            h("kbd", {}, "Esc"),
          ),
        ),
      );
    }
    if (state.errorMessage) {
      const warning = rowIcon("info");
      warning.classList.add("status-icon");
      below.push(h("p", { class: "error" }, warning, h("span", {}, state.errorMessage)));
    }
    if (state.notice) {
      const glyph = rowIcon(state.noticeIsSuccess ? "success" : "info");
      glyph.classList.add("status-icon");
      below.push(h("p", { class: "notice" }, glyph, h("span", {}, state.notice)));
    }
    if (state.suggestsPlus && !state.isGenerating && state.result) {
      below.push(h("p", { class: "caption" }, t("To get answers to your questions while Feather writes, subscribe to Feather Plus.")));
    }

    const chips = h("div", { class: "chips" });
    if (state.focusIsInTextField) {
      chips.append(h("span", { class: "field-badge", title: t("Feather opened while you were typing; Insert writes the reply in that field") }, t("Typing in a field")));
    }
    if (state.appName) chips.append(chip(state.appName, state.options.includeApp, "app", t("Feather knows which app you are in")));
    if (state.selectedPreview !== null) chips.append(chip(t("Text selected"), state.options.includeSelection, "selection", t("Feather sees the text you selected")));
    if (state.hasWindowText) {
      // A window too large to read whole within the capture limits is read in part.
      chips.append(
        state.windowTextWasTruncated
          ? chip(t("Partial window"), state.options.includeWindowText, "windowText", t("This window is too large to read whole, so Feather read only part of it"))
          : chip(t("Window"), state.options.includeWindowText, "windowText", t("Feather is reading the window you are in")),
      );
    }
    if (state.hasScreenshot) chips.append(chip(t("Screenshot"), state.options.includeWindow, "window", t("Feather sends a picture of the window with your request")));
    if (state.captureCount > 1) {
      chips.append(
        chipCaption(
          t("{count} captures", { count: state.captureCount }),
          t("You pressed the shortcut more than once in this app, so Feather combined what it read each time."),
        ),
      );
    }
    if (state.isCapturing) {
      chips.append(
        h(
          "span",
          { class: "capturing" },
          h("span", { class: "spinner", "aria-hidden": "true" }),
          state.captureStatus === "capturingWindow" ? t("Capturing window…") : t("Reading window…"),
        ),
      );
    }
    if (!state.appName && state.selectedPreview === null && !state.hasWindowText) {
      chips.append(h("span", { class: "caption" }, t("No app context")));
    }

    footer.replaceChildren(...below, h("div", { class: "footer-row" }, chips, hints));
    renderHints();
  };

  const apply = (next: PanelState) => {
    const previous = state;
    state = next;
    render();

    // Focus goes back to the field when the panel shows and once it can be typed in again, never
    // on every update, so Tab can reach the chips and hints.
    const finished = previous.isGenerating && !state.isGenerating;
    const unlocked = previous.captureStatus === "readingScreen" && state.captureStatus !== "readingScreen";
    if (state.focusToken !== focusToken || finished || unlocked) {
      focusToken = state.focusToken;
      if (!state.needsSetup && !state.confirmation) field.focus();
    }
    if (state.restoreToken !== restoreToken) {
      restoreToken = state.restoreToken;
      if (state.restoreInstruction && field.value === "") {
        field.value = state.restoreInstruction;
        autosize();
        renderHints();
      }
    }

    if (state.errorMessage && state.errorMessage !== previous.errorMessage) announce(state.errorMessage);
    else if (state.confirmation && state.confirmation !== previous.confirmation) announce(state.confirmation);
    else if (state.notice && state.notice !== previous.notice) announce(state.notice);
    else if (finished && (state.result || state.answer)) announce(t("Reply ready."));
  };

  field.addEventListener("input", () => {
    autosize();
    renderHints();
    icon.classList.toggle("typing", field.value !== "");
    // Each keystroke swings the feather the other way around its nib, like writing.
    icon.classList.toggle("upstroke");
    window.clearTimeout(typingTimer);
    typingTimer = window.setTimeout(() => icon.classList.remove("typing"), 420);
  });

  window.addEventListener("keydown", (event) => {
    const control = event.ctrlKey || event.metaKey;
    if (event.key === "Escape") {
      // Esc stops a running reply; otherwise it closes, and ↑ brings the conversation back.
      event.preventDefault();
      void invoke("prompt_dismiss");
    } else if (event.key === "Enter" && control && !event.shiftKey && !event.altKey) {
      event.preventDefault();
      void invoke("prompt_copy");
    } else if (event.key === "Enter" && !control && !event.shiftKey && !event.altKey) {
      // Enter on a focused hint or chip activates it instead.
      if (event.target instanceof HTMLButtonElement) return;
      event.preventDefault();
      submit();
    } else if (
      (event.key === "ArrowUp" || event.key === "ArrowDown") &&
      !control && !event.shiftKey && !event.altKey &&
      field.value === "" && !state.isGenerating && !state.needsSetup
    ) {
      // With an empty field, ↑ and ↓ move through recent conversations.
      event.preventDefault();
      void invoke("prompt_browse", { direction: event.key === "ArrowUp" ? "older" : "newer" });
    } else if (control && !event.shiftKey && !event.altKey && event.key.toLowerCase() === "n") {
      event.preventDefault();
      newConversation();
    } else if (control && !event.shiftKey && !event.altKey && event.key.toLowerCase() === "r") {
      event.preventDefault();
      void invoke("prompt_regenerate");
    }
  });

  // The window follows the panel's height, growing upward from its anchored bottom edge.
  new ResizeObserver(() => {
    void invoke("panel_resize", { height: Math.ceil(panel.getBoundingClientRect().height) });
  }).observe(panel);

  render();
  try {
    await listen<PanelState>("prompt-state", (event) => apply(event.payload));
    const initial = await invoke<PanelState>("prompt_state");
    restoreToken = initial.restoreToken;
    apply(initial);
  } catch (error) {
    apply({ ...state, errorMessage: String(error) });
  }
}

const EMPTY_STATE: PanelState = {
  appName: null,
  selectedPreview: null,
  hasFocusedText: false,
  hasWindowText: false,
  windowTextWasTruncated: false,
  focusIsInTextField: false,
  options: { includeApp: true, includeFocusedText: true, includeSelection: true, includeWindowText: true, includeWindow: false },
  isCapturing: false,
  captureStatus: null,
  result: "",
  streamingResult: "",
  answer: "",
  streamingAnswer: "",
  isGenerating: false,
  generationStartedAt: null,
  errorMessage: null,
  notice: null,
  noticeIsSuccess: false,
  confirmation: null,
  needsSetup: false,
  insertTarget: null,
  captureCount: 0,
  hasScreenshot: false,
  recentCount: 0,
  focusToken: 0,
  restoreInstruction: null,
  restoreToken: 0,
  browsing: null,
  suggestsPlus: false,
};

function browsingCaption(browsing: NonNullable<PanelState["browsing"]>): HTMLElement {
  return h(
    "div",
    { class: "browsing" },
    h(
      "p",
      { class: "browsing-title" },
      h("span", {}, `↺ ${t("Previous conversation {current} of {total}", { current: browsing.position, total: browsing.count })}`),
      h("kbd", {}, "↑ ↓"),
    ),
    browsing.instruction ? h("p", { class: "browsing-instruction" }, browsing.instruction) : null,
  );
}

function responseBlock(text: string, muted: boolean): HTMLElement {
  return h("div", { class: muted ? "response muted" : "response" }, text);
}

/** A context source the user can leave out of this request. */
function chip(title: string, isOn: boolean, option: string, hint: string): HTMLElement {
  return h(
    "button",
    {
      class: isOn ? "chip" : "chip off",
      type: "button",
      title: hint,
      "aria-pressed": String(isOn),
      "aria-description": hint,
      onclick: () => void invoke("prompt_toggle_option", { option }),
    },
    title,
  );
}

/** Information next to the chips that cannot be switched off. */
function chipCaption(title: string, hint: string): HTMLElement {
  return h("span", { class: "chip-caption", title: hint, "aria-description": hint }, title);
}

function keyHint(keys: (string | Node)[], label: string, highlighted = false, action?: () => void): HTMLElement {
  const content = [h("kbd", {}, ...keys), h("span", { class: "key-label" }, label)];
  const className = highlighted ? "key-hint highlighted" : "key-hint";
  return action
    ? h("button", { class: className, type: "button", "aria-label": label, title: label, onclick: action }, ...content)
    : h("span", { class: className }, ...content);
}
