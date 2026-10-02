// The Settings window, mirroring `SettingsView` and `PlusSettingsView` in the macOS app.
// Credentials never reach this window: it sees masked keys and connection states only.

import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { h, featherIcon } from "./dom";
import { formatDate, t } from "./i18n";

type Connection = "openCodeGo" | "chatGPT" | "featherPlus";
type Section = "general" | "connection" | "plus" | "system";

type AppInfo = {
  locale: string;
  platform: "windows" | "linux" | "other";
  version: string;
  hotkeys: { id: string; label: string }[];
  chatgptModels: { id: string; name: string }[];
};

type Settings = {
  connection: Connection;
  model: string;
  hotkey: string;
  includeScreenshot: boolean;
  customInstructions: string;
  plusEnabled: boolean;
  plusProviderEnabled: boolean;
  hotkeyRegistered: boolean;
};

type Credentials = { apiKey: string | null; chatgptConnected: boolean; plusSignedIn: boolean };
type PlusAccount = { email: string; plan: "starter" | "max" | null; usage: { used: number; limit: number }[]; periodEnd: string | null };
type Capability = { id: string; available: boolean };

const CANCELLED = "cancelled";

export async function startSettings(root: HTMLElement, info: AppInfo): Promise<void> {
  document.body.classList.add("settings-body");
  document.title = t("Feather Settings");
  void getCurrentWindow().setTitle(t("Feather Settings"));

  let settings = await invoke<Settings>("get_settings");
  let credentials = await invoke<Credentials>("credential_status");
  const capabilities = await invoke<Capability[]>("capabilities");
  let section: Section = isConnected() ? "general" : "connection";

  // Transient view state, like the macOS view's @State.
  let isEditingKey = false;
  let models: string[] = [];
  let loadingModels = false;
  let modelsFailed = false;
  let signingIn: "chatGPT" | "plus" | null = null;
  let authError: string | null = null;
  let plusAccount: PlusAccount | null = null;
  let loadingAccount = false;
  let plusError: string | null = null;

  const sidebar = h("nav", { class: "sidebar", "aria-label": t("Feather Settings") });
  const detail = h("main", { class: "detail" });
  root.replaceChildren(h("div", { class: "settings" }, sidebar, detail));

  function isConnected(): boolean {
    switch (settings.connection) {
      case "openCodeGo":
        return credentials.apiKey !== null;
      case "chatGPT":
        return credentials.chatgptConnected;
      case "featherPlus":
        return credentials.plusSignedIn;
    }
  }

  async function set(name: string, value: unknown): Promise<void> {
    settings = await invoke<Settings>("set_setting", { name, value });
    render();
  }

  function sections(): Section[] {
    return (["general", "connection", "plus", "system"] as Section[]).filter((item) => item !== "plus" || settings.plusEnabled);
  }

  function title(item: Section): string {
    return { general: t("General"), connection: t("Connection"), plus: t("Feather Plus"), system: t("System") }[item];
  }

  function render(): void {
    sidebar.replaceChildren(
      h(
        "ul",
        {},
        ...sections().map((item) =>
          h(
            "li",
            {},
            h(
              "button",
              {
                type: "button",
                class: item === section ? "section selected" : "section",
                "aria-current": item === section ? "page" : "false",
                onclick: () => {
                  section = item;
                  void refreshCredentials();
                },
              },
              h("span", { class: `section-icon ${item}`, "aria-hidden": "true" }, sectionGlyph(item)),
              h("span", { class: "section-title" }, title(item)),
              item === "connection" && !isConnected() ? h("span", { class: "attention", title: t("Needs attention") }) : null,
            ),
          ),
        ),
      ),
      h("button", { type: "button", class: "quit", onclick: () => void invoke("quit") }, `⏻  ${t("Quit Feather")}`),
    );

    const views: Record<Section, () => HTMLElement[]> = { general, connection, plus, system };
    detail.replaceChildren(h("h1", {}, title(section)), ...views[section]());
  }

  // MARK: General

  function general(): HTMLElement[] {
    const hotkey = h(
      "select",
      { "aria-label": t("Open Feather"), onchange: (event) => void set("hotkey", (event.target as HTMLSelectElement).value) },
      ...info.hotkeys.map((option) => h("option", { value: option.id, selected: option.id === settings.hotkey }, option.label)),
    );
    const screenshot = h("input", {
      type: "checkbox",
      id: "include-screenshot",
      checked: settings.includeScreenshot,
      onchange: (event) => void set("includeScreenshot", (event.target as HTMLInputElement).checked),
    });
    const instructions = h("textarea", { rows: "4", "aria-label": t("Instructions") });
    instructions.value = settings.customInstructions;
    let saveTimer: number | undefined;
    instructions.addEventListener("input", () => {
      window.clearTimeout(saveTimer);
      saveTimer = window.setTimeout(async () => {
        settings = await invoke<Settings>("set_setting", { name: "customInstructions", value: instructions.value });
      }, 400);
    });

    return [
      group(t("Shortcut"), [row(t("Open Feather"), hotkey)], settings.hotkeyRegistered ? null : error(t("Another app is using this shortcut. Choose a different one."))),
      group(
        t("Context"),
        [
          h(
            "label",
            { class: "row toggle", for: "include-screenshot" },
            h("span", { class: "label" }, t("Include a screenshot of the active window"), h("small", {}, t("Gives the model visual context."))),
            screenshot,
          ),
        ],
        footnote(`✋ ${t("Nothing is captured until you press the shortcut, and the context is discarded when the panel closes.")}`),
      ),
      group(t("Instructions"), [instructions], footnote(t("Set writing preferences for every response, such as “Do not use emojis or em dashes.”"))),
      group(t("About"), [
        row(t("Version"), h("span", { class: "secondary" }, info.version)),
        h("div", { class: "row" }, h("button", { type: "button", onclick: () => void invoke("check_for_updates") }, t("Check for Updates…"))),
      ]),
    ];
  }

  // MARK: Connection

  function connection(): HTMLElement[] {
    const providers: [Connection, string][] = [
      ["openCodeGo", t("OpenCode Go")],
      ["chatGPT", t("ChatGPT")],
    ];
    if (settings.plusProviderEnabled) providers.push(["featherPlus", t("Feather Plus")]);
    const picker = h(
      "div",
      { class: "segmented", role: "radiogroup", "aria-label": t("Provider") },
      ...providers.map(([id, label]) =>
        h(
          "button",
          {
            type: "button",
            role: "radio",
            "aria-checked": String(settings.connection === id),
            class: settings.connection === id ? "selected" : "",
            onclick: async () => {
              authError = null;
              await set("connection", id);
              if (id === "openCodeGo" && models.length === 0) loadModels();
            },
          },
          label,
        ),
      ),
    );

    const account: HTMLElement[] = [h("div", { class: "row" }, picker)];
    let accountFootnote: HTMLElement | null = footnote(t("Credentials are stored in your system's secure credential storage."));
    switch (settings.connection) {
      case "openCodeGo":
        account.push(keyEditor());
        break;
      case "chatGPT":
        account.push(chatgptEditor());
        if (authError) accountFootnote = error(authError);
        else if (!credentials.chatgptConnected && signingIn !== "chatGPT") accountFootnote = footnote(t("Sign-in continues in your browser."));
        break;
      case "featherPlus":
        account.push(
          row(
            t("Account"),
            h(
              "span",
              { class: "inline" },
              credentials.plusSignedIn ? badge(t("Signed in")) : null,
              h("button", { type: "button", onclick: () => ((section = "plus"), render(), loadAccount()) }, credentials.plusSignedIn ? t("Manage…") : t("Sign in…")),
            ),
          ),
        );
        break;
    }

    const views = [group(t("Account"), account, accountFootnote)];
    // Feather Plus picks its own model, so there is nothing to choose.
    if (settings.connection !== "featherPlus") views.push(group(t("Model"), [modelEditor()], modelFootnote()));
    return views;
  }

  function keyEditor(): HTMLElement {
    if (credentials.apiKey === null || isEditingKey) {
      const input = h("input", { type: "password", placeholder: t("Paste your key"), autocomplete: "off", spellcheck: "false", "aria-label": t("API key") });
      const save = h("button", { type: "submit", class: "primary", disabled: true }, t("Save"));
      input.addEventListener("input", () => (save.disabled = input.value.trim() === ""));
      const form = h(
        "form",
        {
          class: "inline",
          onsubmit: async (event) => {
            event.preventDefault();
            const apiKey = input.value;
            input.value = "";
            try {
              credentials = await invoke<Credentials>("save_api_key", { apiKey });
              isEditingKey = false;
              models = [];
              render();
              loadModels();
            } catch (problem) {
              render();
              detail.append(error(String(problem)));
            }
          },
        },
        input,
        credentials.apiKey !== null
          ? h("button", { type: "button", onclick: () => ((isEditingKey = false), render()) }, t("Cancel"))
          : null,
        save,
      );
      queueMicrotask(() => input.focus());
      return row(t("API key"), form);
    }
    return row(
      t("API key"),
      h(
        "span",
        { class: "inline" },
        h("code", { class: "secondary" }, credentials.apiKey),
        h("button", { type: "button", onclick: () => ((isEditingKey = true), render()) }, t("Replace…")),
      ),
    );
  }

  function chatgptEditor(): HTMLElement {
    if (credentials.chatgptConnected) {
      return row(
        t("Account"),
        h(
          "span",
          { class: "inline" },
          badge(t("Connected")),
          h("button", { type: "button", onclick: async () => ((credentials = await invoke<Credentials>("disconnect_chatgpt")), render()) }, t("Disconnect")),
        ),
      );
    }
    const busy = signingIn === "chatGPT";
    return row(
      t("Account"),
      h(
        "span",
        { class: "inline" },
        busy ? h("span", { class: "spinner", "aria-hidden": "true" }) : null,
        h(
          "button",
          {
            type: "button",
            class: "primary",
            disabled: busy,
            onclick: async () => {
              signingIn = "chatGPT";
              authError = null;
              render();
              try {
                credentials = await invoke<Credentials>("sign_in_chatgpt");
              } catch (problem) {
                if (problem !== CANCELLED) authError = String(problem);
              }
              signingIn = null;
              render();
            },
          },
          busy ? t("Signing in…") : t("Sign in with ChatGPT"),
        ),
      ),
    );
  }

  function modelEditor(): HTMLElement {
    if (settings.connection === "chatGPT") {
      return row(
        t("Model"),
        h(
          "select",
          { "aria-label": t("Model"), onchange: (event) => void set("model", (event.target as HTMLSelectElement).value) },
          ...info.chatgptModels.map((model) => h("option", { value: model.id, selected: model.id === settings.model }, model.name)),
        ),
      );
    }
    const options = [...new Set([...models, settings.model])].sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" }));
    const noKey = credentials.apiKey === null;
    return row(
      t("Model"),
      h(
        "span",
        { class: "inline" },
        h(
          "select",
          { "aria-label": t("Model"), disabled: noKey || loadingModels, onchange: (event) => void set("model", (event.target as HTMLSelectElement).value) },
          ...options.map((model) => h("option", { value: model, selected: model === settings.model }, model)),
        ),
        loadingModels
          ? h("span", { class: "spinner", "aria-hidden": "true" })
          : h("button", { type: "button", class: "icon-button", disabled: noKey, title: t("Refresh"), "aria-label": t("Refresh"), onclick: loadModels }, "↻"),
      ),
    );
  }

  function modelFootnote(): HTMLElement | null {
    if (settings.connection !== "openCodeGo") return null;
    if (credentials.apiKey === null) return footnote(t("Add an API key to load the available models."));
    if (modelsFailed) return error(t("Couldn't load the models. Check your key and connection."));
    return null;
  }

  function loadModels(): void {
    if (loadingModels || credentials.apiKey === null) return;
    loadingModels = true;
    modelsFailed = false;
    render();
    invoke<string[]>("opencode_models")
      .then((fetched) => (models = fetched))
      .catch(() => (modelsFailed = true))
      .finally(() => {
        loadingModels = false;
        render();
      });
  }

  // MARK: Feather Plus

  function plus(): HTMLElement[] {
    if (!credentials.plusSignedIn) {
      const busy = signingIn === "plus";
      return [
        group(
          t("Feather Plus"),
          [
            h(
              "div",
              { class: "row login-box" },
              h("strong", {}, t("Sign in to Feather Plus")),
              h("span", { class: "secondary" }, t("Use your Feather Plus account.")),
              h(
                "span",
                { class: "inline" },
                busy ? h("span", { class: "spinner", "aria-hidden": "true" }) : null,
                busy
                  ? h("button", { type: "button", onclick: () => void invoke("cancel_sign_in") }, t("Cancel"))
                  : h("button", { type: "button", class: "primary", onclick: signInPlus }, t("Sign in")),
              ),
            ),
          ],
          plusError ? error(plusError) : footnote(t("Sign-in continues in your browser.")),
        ),
      ];
    }

    const account = plusAccount;
    const rows = [
      row(t("Email"), account ? h("span", { class: "selectable" }, account.email) : loadingAccount ? h("span", { class: "spinner" }) : h("span")),
      row(t("Plan"), account ? (account.plan ? badge(account.plan === "max" ? t("Max") : t("Starter")) : h("span", { class: "secondary" }, t("No plan"))) : h("span")),
    ];
    if (account?.plan && settings.plusProviderEnabled) {
      rows.push(
        row(
          t("Replies"),
          settings.connection === "featherPlus"
            ? badge(t("Using Feather Plus"))
            : h("button", { type: "button", onclick: () => void set("connection", "featherPlus") }, t("Use Feather Plus")),
        ),
      );
    }
    rows.push(
      h(
        "div",
        { class: "row spread" },
        h(
          "button",
          { type: "button", disabled: !account, onclick: () => void invoke("open_plus_account_page") },
          account?.plan ? t("Manage subscription…") : t("Choose a plan…"),
        ),
        h(
          "button",
          {
            type: "button",
            onclick: async () => {
              credentials = await invoke<Credentials>("plus_sign_out");
              plusAccount = null;
              plusError = null;
              render();
              // Signing out is how you switch accounts, so open the sign-in right away.
              void signInPlus();
            },
          },
          t("Sign out"),
        ),
      ),
    );

    const plusFooter = plusError
      ? h("p", { class: "footnote error-text" }, `⚠ ${plusError} `, h("button", { type: "button", class: "link", onclick: loadAccount }, t("Retry")))
      : null;
    const views = [group(t("Account"), rows, plusFooter)];
    if (account?.plan && account.usage.length > 0) {
      views.push(
        group(
          t("Usage this period"),
          account.usage.map((usage) =>
            h(
              "div",
              { class: "row usage" },
              h("div", { class: "spread" }, h("span", {}, t("Requests")), h("span", { class: "secondary" }, t("{used} of {limit}", { used: usage.used.toLocaleString(), limit: usage.limit.toLocaleString() }))),
              h("progress", { value: String(Math.min(usage.used, usage.limit)), max: String(Math.max(usage.limit, 1)), class: usage.used >= usage.limit ? "exhausted" : "" }),
            ),
          ),
          account.periodEnd ? footnote(t("Resets on {date}.", { date: formatDate(account.periodEnd) })) : null,
        ),
      );
    }
    return views;
  }

  async function signInPlus(): Promise<void> {
    signingIn = "plus";
    plusError = null;
    render();
    try {
      credentials = await invoke<Credentials>("sign_in_plus");
      loadAccount();
    } catch (problem) {
      if (problem !== CANCELLED) plusError = String(problem);
    }
    signingIn = null;
    render();
  }

  function loadAccount(): void {
    if (!credentials.plusSignedIn || loadingAccount) return;
    loadingAccount = true;
    plusError = null;
    render();
    invoke<PlusAccount | null>("plus_account")
      .then((account) => (plusAccount = account))
      .catch(async (problem: { unauthorized: boolean; message: string }) => {
        plusError = problem.message;
        if (problem.unauthorized) {
          plusAccount = null;
          credentials = await invoke<Credentials>("credential_status");
        }
      })
      .finally(() => {
        loadingAccount = false;
        render();
      });
  }

  // MARK: System

  function system(): HTMLElement[] {
    const available = (id: string) => capabilities.find((capability) => capability.id === id)?.available ?? false;
    const rows = [
      capabilityRow(t("Read the context around your cursor"), t("Reads the focused field, the selection, and the window's text through accessibility."), available("focused-context")),
      capabilityRow(t("Capture the active window"), t("Attaches a screenshot of the window you were using."), available("window-screenshot")),
      capabilityRow(t("Paste replies"), t("Pastes the reply into the field you were typing in."), available("automatic-insertion")),
    ];
    let note: string;
    if (info.platform === "linux" && !available("x11-session")) {
      note = t(
        "Feather is running in a Wayland session. Wayland does not let apps read or type into other windows, so Feather generates replies and copies them for you to paste. Log in with an X11 session to read context and paste automatically.",
      );
    } else if (info.platform === "linux") {
      note = t("Some apps only share their text when assistive technologies are enabled. If context is missing, turn on accessibility support in your desktop settings.");
    } else {
      note = t("Windows needs no extra permissions. Apps that run as administrator cannot be read or pasted into unless Feather also runs as administrator.");
    }
    return [group(t("What Feather can do here"), rows, footnote(note))];
  }

  // MARK: Refreshing

  async function refreshCredentials(): Promise<void> {
    credentials = await invoke<Credentials>("credential_status");
    render();
    if (section === "plus") loadAccount();
  }

  await listen("settings-changed", async () => {
    settings = await invoke<Settings>("get_settings");
    render();
  });
  // Plans change in the browser (checkout, the portal), so refresh when the window regains focus.
  await getCurrentWindow().onFocusChanged(({ payload: focused }) => {
    if (focused) void refreshCredentials();
  });

  render();
  if (settings.connection === "openCodeGo") loadModels();
}

function sectionGlyph(section: Section): Node {
  if (section === "plus") return featherIcon("glyph");
  return document.createTextNode({ general: "⚙", connection: "⇄", system: "⛨" }[section as Exclude<Section, "plus">]);
}

function group(title: string | null, rows: HTMLElement[], foot: HTMLElement | null = null): HTMLElement {
  return h("section", { class: "group" }, title ? h("h2", {}, title) : null, h("div", { class: "card" }, ...rows), foot);
}

function row(label: string, control: Node): HTMLElement {
  return h("div", { class: "row" }, h("span", { class: "label" }, label), control);
}

function capabilityRow(title: string, detail: string, available: boolean): HTMLElement {
  return h(
    "div",
    { class: "row" },
    h("span", { class: "label" }, title, h("small", {}, detail)),
    h("span", { class: "status" }, h("span", { class: available ? "dot green" : "dot orange", "aria-hidden": "true" }), available ? t("Available") : t("Unavailable")),
  );
}

function badge(text: string): HTMLElement {
  return h("span", { class: "status" }, h("span", { class: "dot green", "aria-hidden": "true" }), text);
}

function footnote(text: string): HTMLElement {
  return h("p", { class: "footnote" }, text);
}

function error(text: string): HTMLElement {
  return h("p", { class: "footnote error-text", role: "alert" }, `⚠ ${text}`);
}
