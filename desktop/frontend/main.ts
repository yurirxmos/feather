import { invoke } from "@tauri-apps/api/core";
import { isRegistered, register, unregister } from "@tauri-apps/plugin-global-shortcut";
import "./styles.css";

type Capability = {
  id: string;
  title: string;
  available: boolean;
  detail: string;
};

type Probe = {
  platform: string;
  shortcut: string;
  capabilities: Capability[];
};

const shortcut = "CommandOrControl+Shift+Space";
const root = document.querySelector<HTMLElement>("#app");

if (!root) {
  throw new Error("The Feather probe root is missing.");
}

const app: HTMLElement = root;

function escapeHTML(value: string): string {
  const element = document.createElement("span");
  element.textContent = value;
  return element.innerHTML;
}

function render(probe: Probe, shortcutState: string, credentialState: string): void {
  const capabilities = probe.capabilities
    .map(
      (capability) => `
        <li class="capability ${capability.available ? "ready" : "pending"}">
          <span class="status" aria-hidden="true"></span>
          <div>
            <strong>${escapeHTML(capability.title)}</strong>
            <p>${escapeHTML(capability.detail)}</p>
          </div>
        </li>`,
    )
    .join("");

  app.innerHTML = `
    <section class="probe" aria-labelledby="title">
      <p class="eyebrow">Feather desktop probe</p>
      <h1 id="title">Start with the hard parts.</h1>
      <p class="intro">This build does not capture your screen or contact an AI provider. It checks the foundations needed for Feather on ${escapeHTML(probe.platform)}.</p>
      <div class="shortcut">
        <span>Temporary shortcut</span>
        <kbd>${escapeHTML(probe.shortcut)}</kbd>
      </div>
      <p class="shortcut-state" role="status">${escapeHTML(shortcutState)}</p>
      <ul class="capabilities" aria-label="Platform capabilities">${capabilities}</ul>
      <form class="credentials" id="opencode-key-form">
        <div>
          <p class="eyebrow">OpenCode Go</p>
          <h2>Connect your API key</h2>
          <p>Your key is stored by the operating system. Feather does not return it to this window after saving.</p>
        </div>
        <label for="opencode-api-key">API key</label>
        <div class="key-row">
          <input id="opencode-api-key" name="apiKey" type="password" autocomplete="off" spellcheck="false" required />
          <button type="submit">Save key</button>
        </div>
        <p class="credential-state" id="credential-state" role="status">${escapeHTML(credentialState)}</p>
      </form>
      <form class="prompt" id="prompt-form">
        <div>
          <p class="eyebrow">Write with Feather</p>
          <h2>What do you want to type?</h2>
        </div>
        <label for="instruction">Instruction</label>
        <textarea id="instruction" name="instruction" rows="4" placeholder="Reply that tomorrow at 2 pm works for me."></textarea>
        <button type="submit">Generate</button>
        <pre class="result" id="result" aria-live="polite"></pre>
      </form>
    </section>`;
}

function wireCredentialForm(probe: Probe, shortcutState: string): void {
  const form = document.querySelector<HTMLFormElement>("#opencode-key-form");
  const input = document.querySelector<HTMLInputElement>("#opencode-api-key");
  if (!form || !input) {
    return;
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const apiKey = input.value;
    input.value = "";
    try {
      await invoke("save_opencode_api_key", { apiKey });
      render(probe, shortcutState, "API key saved in secure storage.");
      wireCredentialForm(probe, shortcutState);
    } catch (error) {
      render(probe, shortcutState, `The API key was not saved: ${String(error)}`);
      wireCredentialForm(probe, shortcutState);
    }
  });
}

function wirePromptForm(): void {
  const form = document.querySelector<HTMLFormElement>("#prompt-form");
  const instruction = document.querySelector<HTMLTextAreaElement>("#instruction");
  const result = document.querySelector<HTMLElement>("#result");
  if (!form || !instruction || !result) {
    return;
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    result.textContent = "Writing…";
    try {
      result.textContent = await invoke<string>("generate_opencode", { instruction: instruction.value });
    } catch (error) {
      result.textContent = `Generation failed: ${String(error)}`;
    }
  });
}

async function configureShortcut(): Promise<string> {
  if (await isRegistered(shortcut)) {
    await unregister(shortcut);
  }
  await register(shortcut, async () => {
    await invoke("toggle_probe_window");
  });
  return "Global shortcut registered. Press it to show or hide this window.";
}

async function start(): Promise<void> {
  const probe = await invoke<Probe>("probe_status");
  const hasKey = await invoke<boolean>("has_opencode_api_key");
  let shortcutState: string;
  try {
    shortcutState = await configureShortcut();
  } catch (error) {
    shortcutState = `The global shortcut could not be registered: ${String(error)}`;
  }
  render(probe, shortcutState, hasKey ? "An API key is already stored securely." : "No API key is stored yet.");
  wireCredentialForm(probe, shortcutState);
  wirePromptForm();
}

void start();
