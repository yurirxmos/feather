import { defineConfig } from "vite";

const host = process.env.TAURI_DEV_HOST;

export default defineConfig({
  clearScreen: false,
  server: {
    host: host ?? "127.0.0.1",
    port: 1420,
    strictPort: true,
    // The provider logos are the macOS app's `ProviderLogos` resources.
    fs: { allow: [".", "../Sources/Feather/ProviderLogos"] },
  },
  envPrefix: ["VITE_", "TAURI_"],
  // WebView2 and WebKitGTK both support top-level await.
  build: { target: "es2022" },
});
