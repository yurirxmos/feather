import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { setLocale } from "./i18n";
import { startFeedback } from "./feedback";
import { startPanel } from "./panel";
import { startSettings } from "./settings";
import "./styles.css";

type AppInfo = Parameters<typeof startSettings>[1];

const root = document.querySelector<HTMLElement>("#app");
if (!root) throw new Error("The Feather root element is missing.");

// One page serves every window; the window label picks the view.
const info = await invoke<AppInfo>("app_info");
setLocale(info.locale);
const label = getCurrentWindow().label;
if (label === "panel") {
  await startPanel(root);
} else if (label === "feedback") {
  startFeedback(root);
} else {
  await startSettings(root, info);
}
