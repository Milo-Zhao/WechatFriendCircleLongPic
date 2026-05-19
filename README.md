# WeChat Long Pic

Compose several photos into one vertical long picture, with a designated thumbnail dropped at the **exact geometric center** — so that when you post it to WeChat Moments (微信朋友圈), the automatically-cropped feed preview shows the image *you* picked, not a random slice of the middle.

Three native ports of the same app, sharing one algorithm:

| Platform | Stack | Status | Install size |
|---|---|---|---|
| **macOS** | SwiftUI + CoreGraphics | Built & runs | ~1.3 MB `.app` |
| **iOS** | SwiftUI + UIKit + PhotosUI | Builds for simulator | – |
| **Windows** | Tauri 2 + Svelte + Rust + WebView2 | Built & runs | ~2.1 MB MSI |

Inspired by [paul-zz/WechatLongPic](https://github.com/paul-zz/WechatLongPic), originally a PyQt5 tool.

---

## What it does

WeChat (and many feed apps) generate a thumbnail from long images by **center-cropping a square**. By stacking your photos and inserting a chosen image as a `W × W` square at the geometric center of the long pic, that thumbnail is what shows up in the Moments feed — while tapping the post still reveals the full stack.

Example use cases:

- A nine-image collage where the feed preview is a single chosen highlight image.
- A photo essay where the social-feed preview is a deliberate hook rather than the literal middle pixel.
- A meme/joke where the preview teases something different from the punchline below.

Reference: this technique is widely documented in Chinese photography communities, e.g. [zhihu.com/question/39845451](https://www.zhihu.com/question/39845451).

---

## How it works

For each composition:

1. **Scale** every non-thumbnail image to the output width (default 1080 px), preserving aspect ratio.
2. **Square-crop** the chosen thumbnail image — either center-cropped or with a custom drag-to-position square — then scale to `W × W`.
3. **Stack** the tiles top-to-bottom in the user's chosen order.
4. **Pad the bottom** (or top, whichever is shorter) with white so the thumbnail's vertical midpoint coincides with the long pic's midpoint. This is what guarantees the WeChat crop lands on the right image.

### Auto-arrange

A weighted optimizer chooses both the **thumbnail** and the **ordering** to minimize a blend of two costs:

- `paddingFraction` — how much white space the centering forces (`= paddingPixels / composedHeight`)
- `cropLossFraction` — pixels discarded when the chosen thumbnail is square-cropped (`= 1 − min(w,h)/max(w,h)`)

```
score = (1 − α) · paddingFraction + α · cropLossFraction
```

where `α ∈ [0, 1]` is the user's "less padding ↔ less cropping" slider. Implemented as a boolean subset-sum DP over the integer scaled heights, restricted to sums with `2·topSpace ≥ S` so any padding always lands at the **bottom** (so the long pic never has whitespace at the top of someone's feed).

Two auto-arrange modes are switched on automatically:

- **No thumbnail starred** → algorithm picks both the thumbnail and the ordering.
- **One thumbnail starred** → algorithm keeps that choice fixed and only optimizes the ordering.

---

## macOS

Native SwiftUI app, runs as a Swift Package executable or as a bundled `.app`.

```bash
swift build -c release          # release binary at .build/release/WechatLongPicGUI
swift run                       # quickest dev path
open build/WeChatLongPic.app    # pre-built bundle (after running the bundling steps)
```

Requires macOS 13+ and Swift 5.9+ (Xcode 15 or Command Line Tools).

Bundled `.app` is ~1.3 MB, ad-hoc signed. Source: [Sources/WechatLongPicGUI/](Sources/WechatLongPicGUI/). Shared cross-platform logic lives in [Sources/WechatLongPicGUI/Shared/](Sources/WechatLongPicGUI/Shared/).

---

## iOS

Native SwiftUI app generated via XcodeGen.

```bash
xcodegen generate
xcodebuild -project WeChatLongPicIOS.xcodeproj -scheme WeChatLongPic \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# or just open in Xcode and ⌘R
open WeChatLongPicIOS.xcodeproj
```

Requires Xcode 15+, iOS 17+ deployment target. Uses `PhotosPicker` for input and `PHAssetChangeRequest` to save the composed long pic into the Photos library.

Source: [iOS/Sources/](iOS/Sources/). Project spec: [project.yml](project.yml).

---

## Windows

Tauri 2 desktop app with a Svelte UI and a Rust backend (using the [`image`](https://crates.io/crates/image) crate). ~2.1 MB MSI installer (4.3 MB extracted exe), ~60–100 MB idle RAM. Verified built and launches on Windows 11 with Rust 1.95 + MSVC.

**On a Windows machine:**

```powershell
cd windows
npm install
npx tauri icon ..\icon.png
npx tauri build
# → src-tauri\target\release\bundle\msi\*.msi
```

**From any other OS (CI):** push the repo to GitHub. The workflow at [`.github/workflows/windows-build.yml`](.github/workflows/windows-build.yml) builds the MSI on a `windows-latest` runner and uploads it as the **WeChatLongPic-Windows** artifact. (Cross-compiling Tauri from macOS/Linux to Windows isn't practical because `wry`'s Windows backend depends on MSVC libraries.)

Source: [windows/](windows/). Per-platform notes: [windows/README.md](windows/README.md).

---

## Repository layout

```
WechatFriendCircleLongPic/
├── Package.swift                    macOS Swift Package
├── project.yml                      iOS Xcode project (XcodeGen)
├── README.md                        ← you are here
├── icon.png                         shared 1024×1024 icon source
├── Sources/WechatLongPicGUI/
│   ├── App.swift, ContentView.swift, CropPickerView.swift, IconGenerator.swift
│   └── Shared/                      cross-platform: composer, optimizer, model
│       ├── ImageProcessor.swift     compose() — stitch + center the thumbnail
│       ├── AutoArrange.swift        recommend() — subset-sum optimizer
│       ├── ImageItem.swift          model, platform-typealias preview
│       └── PlatformImage.swift      NSImage/UIImage typealias
├── iOS/Sources/                     iOS-specific App, ContentView, CropPicker, model
├── iOS/Assets.xcassets/             iOS app icon + accent color
├── windows/
│   ├── src/                         Svelte 4 + TypeScript UI
│   └── src-tauri/src/               Rust IPC commands + image work
└── .github/workflows/
    └── windows-build.yml            CI builds the Windows MSI
```

---

## Status & known gaps

- The macOS app has been built and exercised end-to-end.
- The iOS app builds for simulator; on a real device you'll need a `DEVELOPMENT_TEAM` in [project.yml](project.yml).
- The Windows app has been built locally on Windows 11 (Rust 1.95, MSVC, Node 20+) and launches successfully. The included GitHub Actions workflow remains the easiest way to produce the MSI from a non-Windows host.
- The "center crop" used as the WeChat preview is documented WeChat behavior as of 2024–2025 but is, of course, ultimately at the mercy of whatever crop heuristic WeChat applies. If they change it, the trick stops working.

## Credit

Original PyQt5 implementation and the core idea: [paul-zz/WechatLongPic](https://github.com/paul-zz/WechatLongPic).

## License

This is a personal port. Adopt the original project's license terms if you're redistributing.
