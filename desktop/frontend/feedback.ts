import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { h } from "./dom";
import { t } from "./i18n";

// The longest message the server accepts; JavaScript's `length` counts it the same way.
const MAX_MESSAGE_LENGTH = 5_000;

/** A short form that sends feedback to the team through `feather-api`. Mirrors `FeedbackView`. */
export function startFeedback(root: HTMLElement): void {
  document.body.classList.add("settings-body", "feedback-body");
  document.title = t("Send Feedback");
  void getCurrentWindow().setTitle(t("Send Feedback"));
  const close = () => void invoke("close_feedback");
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") close();
  });

  const message = h("textarea", { "aria-label": t("Your feedback"), placeholder: t("Your feedback") });
  const email = h("input", { type: "email", placeholder: t("Email (optional)"), "aria-label": t("Email (optional)"), autocomplete: "email" });
  const error = h("p", { class: "footnote error-text", role: "alert" });
  const send = h("button", { type: "submit", class: "primary", disabled: true }, t("Send"));
  let sending = false;

  const update = () => {
    const text = message.value.trim();
    const tooLong = text.length > MAX_MESSAGE_LENGTH;
    if (tooLong) error.textContent = t("Keep your message under 5,000 characters.");
    else if (error.dataset.kind === "length") error.textContent = "";
    error.dataset.kind = tooLong ? "length" : "";
    send.disabled = sending || !text || tooLong;
  };
  message.addEventListener("input", update);

  const form = h(
    "form",
    {
      class: "feedback",
      onsubmit: async (event: Event) => {
        event.preventDefault();
        if (send.disabled) return;
        sending = true;
        error.textContent = "";
        send.replaceChildren(h("span", { class: "spinner", "aria-label": t("Send") }));
        update();
        try {
          await invoke("send_feedback", { message: message.value, email: email.value });
          showThanks();
        } catch (reason) {
          error.textContent = String(reason);
          sending = false;
          send.replaceChildren(t("Send"));
          update();
        }
      },
    },
    h("p", {}, t("Tell us what works, what doesn't, or what you'd like Feather to do.")),
    h("div", { class: "card" }, message),
    h("div", { class: "field" }, email, h("small", { class: "secondary" }, t("Only if you'd like a reply."))),
    error,
    h(
      "div",
      { class: "feedback-actions" },
      h("small", { class: "secondary" }, t("Sends your message and the Feather and system versions. Nothing from your screen.")),
      h("button", { type: "button", onclick: close }, t("Cancel")),
      send,
    ),
  );

  const showThanks = () => {
    const done = h("button", { type: "button", class: "primary", onclick: close }, t("Done"));
    root.replaceChildren(
      h(
        "div",
        { class: "feedback-thanks" },
        h("div", { class: "check", "aria-hidden": "true" }, "✓"),
        h("h1", {}, t("Thanks for your feedback!")),
        h("p", { class: "secondary" }, t("It goes straight to the people who build Feather.")),
        done,
      ),
    );
    done.focus();
  };

  root.replaceChildren(form);
  message.focus();
}
