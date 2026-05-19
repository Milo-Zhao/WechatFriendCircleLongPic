# WeChat Long Pic — Windows (Tauri 2 + Svelte + Rust)

A Windows desktop port of the same WeChat Moments long-picture tool. Stitches several photos vertically, drops a designated thumbnail at the exact geometric center so that the Moments preview crop lands on the image you picked.

## Stack

- **Tauri 2** — small native shell using the system WebView2 (preinstalled on Windows 11; auto-installs on Windows 10).
- **Svelte 4 + Vite + TypeScript** — UI.
- **Rust** — all image work uses the [`image`](https://crates.io/crates/image) crate, no Pillow/ImageMagick required.

Installed size is ~10 MB. Idle RAM ~60–100 MB.

## Building locally on Windows

You need:

- **Node 18+** (`node --version`)
- **Rust** via [rustup](https://www.rust-lang.org/tools/install)
- **Visual Studio Build Tools** with the *Desktop development with C++* workload (Tauri needs MSVC for Windows builds)
- **WebView2 runtime** — preinstalled on Windows 11; on Windows 10, run [Microsoft's installer](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) once

Then, from this `windows/` directory:

```powershell
npm install
npx tauri icon ..\icon.png         # one-time, generates icons/*
npx tauri dev                       # development with hot reload
npx tauri build                     # produces installers in src-tauri\target\release\bundle\
```

Outputs:

- `src-tauri\target\release\bundle\msi\*.msi` — MSI installer
- `src-tauri\target\release\bundle\nsis\*-setup.exe` — NSIS installer
- `src-tauri\target\release\wechat-long-pic.exe` — bare executable

## Building from a Mac (or any non-Windows machine)

Tauri **cannot cross-compile from macOS to Windows** because `wry` (its webview crate) on Windows depends on MSVC libraries that don't exist on macOS. Use the GitHub Actions workflow instead:

1. Push the repo to GitHub.
2. The workflow at [`.github/workflows/windows-build.yml`](../.github/workflows/windows-build.yml) runs on every push touching `windows/` and on manual dispatch.
3. After it finishes, download the **WeChatLongPic-Windows** artifact from the run's summary page. The artifact contains the `.msi` installer.

## How it works

Same algorithm as the macOS/iOS versions; ported to Rust:

1. Every non-thumbnail image is scaled to `output_width` preserving aspect ratio. The chosen thumbnail is center-cropped (or custom-cropped) to a square, then scaled to `W × W`.
2. Tiles are stacked top→bottom in the user's order.
3. The bottom of the long pic is padded with white so the thumbnail's vertical midpoint matches the long pic's midpoint. This is the centered square WeChat Moments will crop for the feed preview.
4. **Auto Arrange** picks the thumbnail and ordering minimizing `(1 − α) · paddingFraction + α · cropLossFraction`, where α is the "less padding ↔ less cropping" slider. Implemented as a boolean subset-sum DP restricted to `2·topSpace ≥ S` so padding always lands at the bottom, never the top.

Rust core lives in [`src-tauri/src/compose.rs`](src-tauri/src/compose.rs) and [`src-tauri/src/arrange.rs`](src-tauri/src/arrange.rs); the Svelte UI is in [`src/`](src/).
