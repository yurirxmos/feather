// The Settings window, mirroring `SettingsView` and `PlusSettingsView` in the macOS app.
// Credentials never reach this window: it sees masked keys and connection states only.

import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { h, featherIcon, moreIcon, rowIcon } from "./dom";
import { formatDate, t } from "./i18n";
// The original logos, shared with the macOS app (its `ProviderLogos` resources).
import openAILogo from "../../Sources/Feather/ProviderLogos/openai_logo.svg";
import openCodeLogo from "../../Sources/Feather/ProviderLogos/opencode_logo.png";

type Connection = "openCodeGo" | "chatGPT" | "featherPlus";
type Section = "general" | "connection" | "plus" | "system";

type AppInfo = {
  locale: string;
  platform: "windows" | "linux" | "other";
  /** On Linux, the display server. */
  session: "x11" | "wayland" | "unknown" | null;
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
  launchAtLogin: boolean;
  onboardingCompleted: boolean | null;
};

type Credentials = { apiKey: string | null; chatgptConnected: boolean; plusSignedIn: boolean };
/** Usage is model cost in micro-dollars; it is shown as `percentUsed`, never as money. */
type PlusAccount = { email: string; plan: "monthly" | "yearly" | null; usage: { used: number; limit: number; percentUsed: number }[]; periodEnd: string | null };
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
  // The welcome guide runs once on every install, including ones that already have credentials.
  let onboardingStep: number | null = settings.onboardingCompleted ? null : 0;

  // Transient view state, like the macOS view's @State.
  let isEditingKey = false;
  let models: string[] = [];
  let loadingModels = false;
  let modelsFailed = false;
  let chatgptModels = info.chatgptModels;
  let loadingChatgptModels = false;
  let chatgptModelsFailed = false;
  let signingIn: "chatGPT" | "plus" | null = null;
  /** The provider row whose ⋯ menu is open. */
  let openMenu: Connection | null = null;

  // The ⋯ menu closes on a click elsewhere or Escape, and arrow keys move between its items.
  document.addEventListener("click", () => {
    if (openMenu === null) return;
    openMenu = null;
    render();
  });
  document.addEventListener("keydown", (event) => {
    if (openMenu === null) return;
    if (event.key === "Escape") {
      event.preventDefault();
      openMenu = null;
      render();
      return;
    }
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
    event.preventDefault();
    const items = [...document.querySelectorAll<HTMLButtonElement>(".row-menu [role=menuitem]")];
    const index = items.indexOf(document.activeElement as HTMLButtonElement);
    items[(index + (event.key === "ArrowDown" ? 1 : items.length - 1)) % items.length]?.focus();
  });
  let authError: string | null = null;
  let plusAccount: PlusAccount | null = null;
  let loadingAccount = false;
  let plusError: string | null = null;
  // Set when a Feather Plus account signs in, until its plan is known: then Settings asks once
  // whether to reply with Feather Plus, as the macOS app's `UseFeatherPlusAlert`.
  let offerFeatherPlus = false;

  const sidebar = h("nav", { class: "sidebar", "aria-label": t("Feather Settings") });
  const detail = h("main", { class: "detail" });
  const shell = h("div", { class: "settings" }, sidebar, detail);
  const wizardView = h("div", { class: "onboarding" });

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
    if (onboardingStep !== null) {
      if (root.firstChild !== wizardView) root.replaceChildren(wizardView);
      renderOnboarding(onboardingStep);
      return;
    }
    if (root.firstChild !== shell) root.replaceChildren(shell);
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
    const launchAtLogin = h("input", {
      type: "checkbox",
      id: "launch-at-login",
      checked: settings.launchAtLogin,
      onchange: (event) => {
        // The system can refuse, so a failure puts the checkbox back to what the system reports.
        void set("launchAtLogin", (event.target as HTMLInputElement).checked).catch(render);
      },
    });
    const screenshot = h("input", {
      type: "checkbox",
      id: "include-screenshot",
      checked: settings.includeScreenshot,
      onchange: (event) => void set("includeScreenshot", (event.target as HTMLInputElement).checked),
    });
    const instructions = h("textarea", {
      rows: "5",
      "aria-label": t("Instructions"),
      placeholder: t("For example: Write in a friendly tone and keep replies short."),
    });
    instructions.value = settings.customInstructions;
    let saveTimer: number | undefined;
    // One-click instructions, mirroring `InstructionsEditor` in the macOS app.
    const suggestions = [
      [t("No emojis"), t("Do not use emojis.")],
      [t("No em dashes"), t("Do not use em dashes.")],
      [t("Keep it short"), t("Keep replies short and to the point.")],
      [t("Friendly tone"), t("Write in a warm, friendly tone.")],
    ].map(([label, instruction]) => {
      const add = () => {
        const current = instructions.value.trim();
        instructions.value = current ? `${current}\n${instruction}` : instruction;
        instructions.dispatchEvent(new Event("input"));
      };
      return { instruction, button: h("button", { type: "button", onclick: add }, `+ ${label}`) };
    });
    const updateSuggestions = () => {
      for (const { instruction, button } of suggestions) button.disabled = instructions.value.includes(instruction);
    };
    updateSuggestions();
    instructions.addEventListener("input", () => {
      updateSuggestions();
      window.clearTimeout(saveTimer);
      saveTimer = window.setTimeout(async () => {
        settings = await invoke<Settings>("set_setting", { name: "customInstructions", value: instructions.value });
      }, 400);
    });

    return [
      group(t("Shortcut"), [row(t("Open Feather"), hotkey)], shortcutNote()),
      group(
        t("Instructions"),
        [instructions, h("div", { class: "suggestions" }, ...suggestions.map(({ button }) => button))],
        footnote(t("Feather follows these in every reply. Write your own or add a suggestion.")),
      ),
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
        footnote(t("Nothing is captured until you press the shortcut, and the context is discarded when the panel closes.")),
      ),
      group(t("Startup"), [
        h(
          "label",
          { class: "row toggle", for: "launch-at-login" },
          h("span", { class: "label" }, t("Open Feather at login"), h("small", {}, t("Starts Feather in the background when you sign in to your computer."))),
          launchAtLogin,
        ),
      ]),
      group(t("About"), [
        row(t("Version"), h("span", { class: "secondary" }, info.version)),
        h("div", { class: "row" }, h("button", { type: "button", onclick: () => void invoke("check_for_updates") }, t("Check for Updates…"))),
        h("div", { class: "row" }, h("button", { type: "button", onclick: () => void set("onboardingCompleted", false).then(startOnboarding) }, t("Show Welcome Guide…"))),
      ]),
    ];
  }

  // MARK: Connection

  // Providers that are set up come first, with the one in use marked; the rest wait below with a
  // Set Up button. Which one is in use after credentials change is decided in Rust
  // (`connection_after_setup_change`), which emits "settings-changed".

  const ORDER: Connection[] = ["featherPlus", "chatGPT", "openCodeGo"];

  function providers(): Connection[] {
    return ORDER.filter((id) => id !== "featherPlus" || settings.plusProviderEnabled);
  }

  function isSetUp(id: Connection): boolean {
    switch (id) {
      case "openCodeGo":
        return credentials.apiKey !== null;
      case "chatGPT":
        return credentials.chatgptConnected;
      case "featherPlus":
        return credentials.plusSignedIn;
    }
  }

  function providerName(id: Connection): string {
    return { featherPlus: t("Feather Plus"), chatGPT: t("ChatGPT"), openCodeGo: t("OpenCode Go") }[id];
  }

  function connection(): HTMLElement[] {
    const views: HTMLElement[] = [];
    // Feather Plus is set apart above the free providers.
    if (providers().includes("featherPlus")) views.push(group(null, [plusCard()]));
    views.push(
      group(
        t("Free plan"),
        freeRows(),
        footnote(t("Use your own ChatGPT account or OpenCode Go key. Credentials are stored in your system's secure credential storage.")),
      ),
    );
    // Feather Plus picks its own model, so there is nothing to choose.
    if (isSetUp(settings.connection) && settings.connection !== "featherPlus") {
      views.push(group(t("Model"), [modelEditor()], modelFootnote()));
    }
    if (authError) views.push(error(authError));
    return views;
  }

  /** Ready providers first; the ones still to set up below them, dimmed. */
  function freeRows(): HTMLElement[] {
    const free: Connection[] = ["chatGPT", "openCodeGo"];
    const ready = free.filter(isSetUp);
    const pending = free.filter((id) => !isSetUp(id));
    return [...ready, ...pending].map(providerRow);
  }

  function plusCard(): HTMLElement {
    const setUpAlready = isSetUp("featherPlus");
    const perks = setUpAlready
      ? null
      : h(
          "ul",
          { class: "perks" },
          ...[t("Answers your questions"), t("No API key to manage"), t("$4 a month or $36 a year")].map((perk) => h("li", {}, perk)),
        );
    return h(
      "div",
      { class: "row plus-card" },
      h(
        "div",
        { class: "plus-card-head" },
        providerIcon("featherPlus"),
        h(
          "span",
          { class: "label" },
          h("strong", {}, t("Feather Plus")),
          h("small", {}, setUpAlready ? providerDetail("featherPlus") : t("No API key, and it also answers questions. Paid plan.")),
        ),
        providerAccessory("featherPlus"),
      ),
      perks,
    );
  }

  function providerRow(id: Connection): HTMLElement {
    const main = h(
      "div",
      { class: isSetUp(id) || id === "featherPlus" ? "row provider" : "row provider pending" },
      providerIcon(id),
      h("span", { class: "label" }, h("span", {}, providerName(id)), h("small", { class: id === "openCodeGo" && isSetUp(id) ? "mono" : "" }, providerDetail(id))),
      providerAccessory(id),
    );
    if (id === "openCodeGo" && isEditingKey) return h("div", { class: "provider-group" }, main, keyForm());
    return main;
  }

  /** Feather Plus uses Feather's mark, the app icon's white feather on blue; ChatGPT and OpenCode Go their black logos on white. */
  function providerIcon(id: Connection): HTMLElement {
    if (id === "featherPlus") return h("span", { class: "provider-icon featherPlus", "aria-hidden": "true" }, featherIcon("feather-mark"));
    return h(
      "span",
      { class: `provider-icon logo ${id}`, "aria-hidden": "true" },
      h("img", { src: id === "chatGPT" ? openAILogo : openCodeLogo, alt: "" }),
    );
  }

  function providerDetail(id: Connection): string {
    if (!isSetUp(id)) {
      return {
        featherPlus: t("No API key, and it also answers questions. Paid plan."),
        chatGPT: t("Sign in with your ChatGPT account. Free."),
        openCodeGo: t("Paste an OpenCode Go API key. Free."),
      }[id];
    }
    switch (id) {
      case "openCodeGo":
        return credentials.apiKey ?? "";
      case "chatGPT":
        return t("Signed in");
      case "featherPlus":
        if (!plusAccount) return t("Signed in");
        return plusAccount.plan === "yearly" ? t("Yearly plan") : plusAccount.plan === "monthly" ? t("Monthly plan") : t("No plan yet");
    }
  }

  /**
   * An icon button with its label as accessible name and as a quick tooltip (`data-tip`, see
   * styles.css), like the macOS app's `iconButton` with `.help`.
   */
  function iconButton(icon: Parameters<typeof rowIcon>[0], label: string, onclick: () => void, attributes: Record<string, string | boolean> = {}): HTMLElement {
    // A tooltip names the action; the trailing "…" belongs on buttons that open something.
    return h("button", { type: "button", class: `icon-button row-action ${icon}`, "data-tip": label.replace(/…$/, ""), "aria-label": label, onclick, ...attributes }, rowIcon(icon));
  }

  /**
   * The row's actions, as icons with tooltips: a check when in use, a circle to use it, a plus to
   * set it up, a card to choose a Feather Plus plan, and the ⋯ menu for the rest.
   */
  function providerAccessory(id: Connection): HTMLElement {
    const busy = (id === "chatGPT" && signingIn === "chatGPT") || (id === "featherPlus" && signingIn === "plus");
    if (busy) {
      return h(
        "span",
        { class: "inline" },
        h("span", { class: "spinner", "aria-hidden": "true" }),
        iconButton("cancel", t("Cancel"), () => void invoke("cancel_sign_in")),
      );
    }
    if (!isSetUp(id)) {
      if (id === "openCodeGo" && isEditingKey) return h("span");
      return iconButton(id === "featherPlus" ? "plusFilled" : "plus", t("Set Up…"), () => setUp(id), { disabled: signingIn !== null });
    }
    let status: HTMLElement;
    if (id === "featherPlus" && plusAccount && !plusAccount.plan) {
      status = iconButton("card", t("Choose a plan…"), () => void invoke("open_plus_account_page"));
    } else if (settings.connection === id) {
      status = h("span", { class: "row-action in-use", "data-tip": t("In use"), tabindex: "0", role: "img", "aria-label": t("In use") }, rowIcon("check"));
    } else {
      status = iconButton("circle", t("Use"), async () => {
        await set("connection", id);
        if (id === "openCodeGo" && models.length === 0) loadModels();
        if (id === "chatGPT") loadChatgptModels();
      });
    }
    return h("span", { class: "inline row-actions" }, status, ...providerActions(id));
  }

  /**
   * The row's secondary actions, in a menu behind a ⋯ button, like the macOS app's row menus.
   * Destructive actions are tinted red.
   */
  function providerActions(id: Connection): HTMLElement[] {
    const items: { label: string; destructive?: boolean; run: () => void | Promise<void> }[] = {
      openCodeGo: [
        { label: t("Replace…"), run: () => ((isEditingKey = true), render()) },
        {
          label: t("Remove Key"),
          destructive: true,
          run: async () => {
            credentials = await invoke<Credentials>("delete_api_key");
            models = [];
            render();
          },
        },
      ],
      chatGPT: [{ label: t("Disconnect"), destructive: true, run: async () => ((credentials = await invoke<Credentials>("disconnect_chatgpt")), render()) }],
      featherPlus: [{ label: t("Manage…"), run: () => ((section = "plus"), render(), loadAccount()) }],
    }[id];
    const open = openMenu === id;
    const button = h(
      "button",
      {
        type: "button",
        class: "icon-button more-button",
        "data-tip": t("More"),
        "aria-label": t("More"),
        "aria-haspopup": "menu",
        "aria-expanded": String(open),
        onclick: (event: Event) => {
          event.stopPropagation();
          openMenu = open ? null : id;
          render();
          if (!open) document.querySelector<HTMLButtonElement>(".row-menu [role=menuitem]")?.focus();
        },
      },
      moreIcon(),
    );
    if (!open) return [h("span", { class: "more" }, button)];
    const menu = h(
      "div",
      { class: "row-menu", role: "menu" },
      ...items.map((item) =>
        h(
          "button",
          {
            type: "button",
            role: "menuitem",
            class: item.destructive ? "destructive" : "",
            onclick: (event: Event) => {
              event.stopPropagation();
              openMenu = null;
              void item.run();
              render();
            },
          },
          item.label,
        ),
      ),
    );
    return [h("span", { class: "more" }, button, menu)];
  }

  function setUp(id: Connection): void {
    authError = null;
    switch (id) {
      case "openCodeGo":
        isEditingKey = true;
        render();
        return;
      case "chatGPT":
        void signInChatGPT();
        return;
      case "featherPlus":
        void signInPlus();
        return;
    }
  }

  async function signInChatGPT(): Promise<void> {
    signingIn = "chatGPT";
    render();
    try {
      credentials = await invoke<Credentials>("sign_in_chatgpt");
    } catch (problem) {
      if (problem !== CANCELLED) authError = String(problem);
    }
    signingIn = null;
    render();
    loadChatgptModels();
  }

  function keyForm(): HTMLElement {
    const input = h("input", { type: "password", placeholder: t("Paste your key"), autocomplete: "off", spellcheck: "false", "aria-label": t("API key") });
    const save = h("button", { type: "submit", class: "primary", disabled: true }, t("Save"));
    input.addEventListener("input", () => (save.disabled = input.value.trim() === ""));
    queueMicrotask(() => input.focus());
    return h(
      "form",
      {
        class: "row key-form",
        onsubmit: async (event) => {
          event.preventDefault();
          const apiKey = input.value;
          input.value = "";
          try {
            credentials = await invoke<Credentials>("save_api_key", { apiKey });
            isEditingKey = false;
            authError = null;
            models = [];
            render();
            loadModels();
          } catch (problem) {
            authError = String(problem);
            render();
          }
        },
      },
      input,
      h("button", { type: "button", onclick: () => ((isEditingKey = false), render()) }, t("Cancel")),
      save,
    );
  }

  function modelEditor(): HTMLElement {
    if (settings.connection === "chatGPT") {
      const options = chatgptModels.some((model) => model.id === settings.model)
        ? chatgptModels
        : [...chatgptModels, { id: settings.model, name: settings.model }];
      return row(
        t("Model"),
        h(
          "span",
          { class: "inline" },
          h(
            "select",
            { "aria-label": t("Model"), disabled: loadingChatgptModels, onchange: (event) => void set("model", (event.target as HTMLSelectElement).value) },
            ...options.map((model) => h("option", { value: model.id, selected: model.id === settings.model }, model.name)),
          ),
          loadingChatgptModels
            ? h("span", { class: "spinner", "aria-hidden": "true" })
            : h("button", { type: "button", class: "icon-button", title: t("Refresh"), "aria-label": t("Refresh"), onclick: loadChatgptModels }, "↻"),
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
    if (settings.connection === "chatGPT") {
      return chatgptModelsFailed ? error(t("Couldn't load your ChatGPT models. Showing the defaults.")) : null;
    }
    if (settings.connection !== "openCodeGo") return null;
    if (modelsFailed) return error(t("Couldn't load the models. Check your key and connection."));
    return null;
  }

  /** Asks ChatGPT which models this account can use; the built-in list stays if that fails. */
  function loadChatgptModels(): void {
    if (loadingChatgptModels || !credentials.chatgptConnected) return;
    loadingChatgptModels = true;
    chatgptModelsFailed = false;
    render();
    invoke<{ id: string; name: string }[]>("chatgpt_models")
      .then((fetched) => (chatgptModels = fetched))
      .catch(() => (chatgptModelsFailed = true))
      .finally(() => {
        loadingChatgptModels = false;
        render();
      });
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
      row(t("Plan"), account ? (account.plan ? badge(account.plan === "yearly" ? t("Plus Yearly") : t("Plus Monthly")) : h("span", { class: "secondary" }, t("No plan"))) : h("span")),
    ];
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
          t("Usage this month"),
          account.usage.map((usage) =>
            h(
              "div",
              { class: "row usage" },
              h("div", { class: "spread" }, h("span", {}, t("This month's allowance")), h("span", { class: "secondary" }, t("{percent}% used", { percent: usage.percentUsed }))),
              h("progress", { value: String(usage.percentUsed), max: "100", class: usage.used >= usage.limit ? "exhausted" : "" }),
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
      // Signing in may have switched the provider in Rust; read it before deciding to ask.
      settings = await invoke<Settings>("get_settings");
      offerFeatherPlus = true;
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
      .then((account) => {
        plusAccount = account;
        if (offerFeatherPlus && account?.plan) {
          offerFeatherPlus = false;
          if (settings.connection !== "featherPlus") askToUseFeatherPlus();
        }
      })
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
    if (info.platform === "linux" && info.session === "wayland") {
      note = t(
        "Feather is running in a Wayland session. Wayland does not let apps look at or type into other windows, so Feather reads the app in front through accessibility and copies each reply for you to paste.",
      );
    } else if (info.platform === "linux") {
      note = t("Some apps only share their text when assistive technologies are enabled. If context is missing, turn on accessibility support in your desktop settings.");
    } else {
      note = t("Windows needs no extra permissions. Apps that run as administrator cannot be read or pasted into unless Feather also runs as administrator.");
    }
    return [group(t("What Feather can do here"), rows, footnote(note))];
  }

  /**
   * What to say under the shortcut. On Wayland an app cannot listen for a global shortcut, so the
   * desktop's own keyboard settings must run Feather with `--prompt`; elsewhere the only problem is
   * another app owning the shortcut.
   */
  function shortcutNote(): HTMLElement | null {
    if (info.platform === "linux" && info.session === "wayland") {
      return footnote(
        t("Wayland does not let apps listen for a global shortcut. In your desktop's keyboard settings, add a shortcut that runs Feather with the --prompt option, or open Feather from its tray menu."),
      );
    }
    return settings.hotkeyRegistered ? null : error(t("Another app is using this shortcut. Choose a different one."));
  }

  /** Asks whether to switch replies to Feather Plus, naming the provider in use now. */
  function askToUseFeatherPlus(): void {
    const current = providerName(settings.connection);
    const dialog = h(
      "dialog",
      { class: "confirm", "aria-labelledby": "confirm-title" },
      h("div", { class: "confirm-icon", "aria-hidden": "true" }, featherIcon("feather-mark")),
      h("h2", { id: "confirm-title" }, t("Use Feather Plus for replies?")),
      h("p", {}, t("Feather is using {provider} now. You can switch again in Settings > Connection anytime.", { provider: current })),
      h(
        "div",
        { class: "confirm-actions" },
        h("button", { type: "button", onclick: () => dialog.close() }, t("Keep {provider}", { provider: current })),
        h(
          "button",
          {
            type: "button",
            class: "primary",
            onclick: async () => {
              dialog.close();
              await set("connection", "featherPlus");
            },
          },
          t("Use Feather Plus"),
        ),
      ),
    );
    dialog.addEventListener("close", () => dialog.remove());
    document.body.append(dialog);
    dialog.showModal();
    dialog.querySelector<HTMLButtonElement>(".primary")?.focus();
  }

  // MARK: Onboarding

  // The first-run welcome guide, mirroring `OnboardingView` in the macOS app. Windows needs no
  // permissions, so it has no permissions step: welcome, connect, try it out.

  const STEPS = ["welcome", "connect", "try"] as const;
  // One element for the whole guide: the window regains focus when the panel closes, which
  // re-renders, and the reply pasted into the box must survive that.
  const sample = h("textarea", { rows: "4", "aria-label": t("Try it out"), placeholder: t("Your reply appears here") });

  function startOnboarding(): void {
    onboardingStep = 0;
    render();
  }

  async function finishOnboarding(): Promise<void> {
    onboardingStep = null;
    section = "general";
    await set("onboardingCompleted", true);
  }

  function renderOnboarding(step: number): void {
    const name = STEPS[step];
    const last = step === STEPS.length - 1;
    const shortcut = info.hotkeys.find((option) => option.id === settings.hotkey)?.label ?? settings.hotkey;
    const go = (to: number) => () => {
      onboardingStep = to;
      render();
    };

    let body: HTMLElement[];
    let canContinue = true;
    if (name === "welcome") {
      body = [
        h("div", { class: "welcome-icon", "aria-hidden": "true" }, featherIcon("feather-mark")),
        h("h1", {}, t("Welcome to Feather")),
        h("p", { class: "lead" }, t("Press a shortcut anywhere. Feather reads what is on your screen, writes a reply, and pastes it into the field you are typing in.")),
      ];
    } else if (name === "connect") {
      canContinue = isConnected();
      body = [
        h("h1", {}, t("Connect a provider")),
        h("p", { class: "lead" }, t("Choose how Feather gets its replies. You can change this later in Settings.")),
        ...connection(),
      ];
    } else {
      body = [
        h("h1", {}, t("Try it out")),
        h(
          "p",
          { class: "lead" },
          info.platform === "linux" && info.session === "wayland"
            ? t("Click the box below, then open Feather from its tray menu or your own shortcut. Say what you want, and Feather writes it here.")
            : t("Click the box below, then press {shortcut}. Say what you want, and Feather writes it here.", { shortcut }),
        ),
        h("div", { class: "card" }, sample),
        ...[shortcutNote()].filter((note): note is HTMLElement => note !== null),
        footnote(t("Nothing is captured until you press the shortcut, and the context is discarded when the panel closes.")),
      ];
    }

    const back = step > 0 ? h("button", { type: "button", onclick: go(step - 1) }, t("Back")) : h("span");
    const next = h(
      "button",
      { type: "button", class: "primary", disabled: !canContinue, onclick: last ? () => void finishOnboarding() : go(step + 1) },
      name === "welcome" ? t("Get Started") : last ? t("Finish") : t("Continue"),
    );
    wizardView.replaceChildren(
      h("div", { class: "onboarding-body" }, ...body),
      h(
        "footer",
        { class: "onboarding-footer" },
        back,
        h("span", { class: "secondary" }, !canContinue ? t("Connect a provider to continue.") : t("Step {current} of {total}", { current: step + 1, total: STEPS.length })),
        next,
      ),
    );
    if (name === "try" && document.activeElement === document.body) sample.focus();
  }

  // MARK: Refreshing

  async function refreshCredentials(): Promise<void> {
    credentials = await invoke<Credentials>("credential_status");
    render();
    if (section === "plus" || section === "connection") loadAccount();
  }

  await listen("settings-changed", async () => {
    settings = await invoke<Settings>("get_settings");
    render();
  });
  // A reply for this window, such as the welcome guide's practice box, arrives here instead of
  // being pasted. Re-renders on focus can move the box, so fall back to it during the guide.
  await listen<string>("insert-text", ({ payload: text }) => {
    const active = document.activeElement;
    const field =
      active instanceof HTMLTextAreaElement || (active instanceof HTMLInputElement && active.type === "text")
        ? active
        : onboardingStep !== null && STEPS[onboardingStep] === "try"
          ? sample
          : null;
    if (!field) {
      void navigator.clipboard.writeText(text);
      return;
    }
    field.focus();
    field.setRangeText(text, field.selectionStart ?? field.value.length, field.selectionEnd ?? field.value.length, "end");
    field.dispatchEvent(new Event("input", { bubbles: true }));
  });
  // Plans change in the browser (checkout, the portal), so refresh when the window regains focus.
  await getCurrentWindow().onFocusChanged(({ payload: focused }) => {
    if (focused) void refreshCredentials();
  });

  render();
  if (settings.connection === "openCodeGo") loadModels();
  if (settings.connection === "chatGPT") loadChatgptModels();
  if (section === "connection") loadAccount();
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
