import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { setLocale } from "./i18n";
import { startPanel } from "./panel";
import { startSettings } from "./settings";
import "./styles.css";

type AppInfo = Parameters<typeof startSettings>[1];

const root = document.querySelector<HTMLElement>("#app");
if (!root) throw new Error("The Feather root element is missing.");

// One page serves both windows; the window label picks the view.
const info = await invoke<AppInfo>("app_info");
setLocale(info.locale);
if (getCurrentWindow().label === "panel") {
  await startPanel(root);
} else {
  await startSettings(root, info);
}
