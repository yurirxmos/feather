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

function render(probe: Probe, shortcutState: string): void {
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
    </section>`;
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
  try {
    render(probe, await configureShortcut());
  } catch (error) {
    render(probe, `The global shortcut could not be registered: ${String(error)}`);
  }
}

void start();
