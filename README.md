# Markdown Viewer

English | [简体中文](README.zh-CN.md)

A native macOS SwiftUI + WKWebView offline Markdown reader. Apple Silicon, macOS 13+.

The interface language follows your macOS language settings (Chinese or English).

- `Reader.swift`: main application source.
- `Resources/reader.html`: layout and rendering template.
- `Resources/*.lproj`: localized text and welcome documents.
- `Resources/vendor/`: third-party libraries bundled for offline use, version records, and licenses.
- `Assets/AppIcon-D1.svg`: current icon (paper on a teal background, an ink-colored M, and a vermilion seal); `AppIcon-D1-small.svg` is the simplified version for 16/32 px, and `AppIcon-D1.icns` is generated from both. The old `AppIcon-D-down.*` icons are retained.
- `make_icon.py`: generates `AppIcon-D1.icns` and `AppIcon-D1.png` from the two SVGs, rendered with `Assets/svg2png.swift` (WebKit) to preserve transparent margins. Do not convert with qlmanage: it fills transparent areas with white.
- `inline_katex_fonts.py`: embeds KaTeX fonts as data URIs in `Resources/vendor/katex.css` for offline use.
- `Probe.swift`: early toolchain verification source, unused by the main app.
- `Tests/Harness.swift`: integration checks for real WebKit rendering, PDF export, and tab routing; `Tests/results.json` contains the results.
- `toolchain.py`: shared compiler options, SDK selection, and version numbers for building and testing.

Build: `python3 build.py`. Requires Apple Command Line Tools; Xcode and a paid developer certificate are not required. Produces `MarkdownReader.app` with an ad-hoc local signature.
Test: `python3 test.py`, which compiles and runs `Tests/Harness.swift`, writes results to `Tests/results.json`, and saves light/dark rendering screenshots in `.build/`.
Create a disk image: `python3 package.py`, producing `dist/MarkdownViewer-<version>-arm64.dmg` without overwriting an existing image. Version numbers are maintained centrally in `toolchain.py`.

Toolchain note: SwiftUI's `@State` in the macOS 27 SDK depends on a macro plugin shipped only with Xcode. When only Command Line Tools are installed, `toolchain.py` automatically uses the newest installed macOS 26.x SDK instead. Set the `READER_SDK` environment variable to specify an SDK path.

Supports opening files, drag and drop, multiple windows and tabs (⌘T for a new tab, ⌘N for a new window; files opened from a window open in new tabs, and already-open files are brought to the front), Finder Open With, outlines, tables, syntax highlighting, math formulas, Mermaid diagrams, relative-path local images, find, source view, themes, font sizes, recent files, and PDF export. Typography follows Typora's default style, with a graphite-gray palette in dark mode. Source files are not modified; use ⌘R to reload after changes. If “Close windows when quitting an application” is disabled in System Settings, each window restores its document when the app relaunches.

Limits: Markdown documents up to 5 MB; images up to 20 MB. Images must be within the document directory or its subdirectories. Remote images, SVG, and symbolic links that escape that directory are not loaded. This is a read-only tool with no editing features.

Math: inline `$...$`, display `$$...$$`, or ```` ```math ```` code blocks, rendered with KaTeX. Commands that can generate links or HTML, such as `\href`, are not supported. Currency amounts such as `$5` are not treated as formulas; `\$` produces a dollar sign.

Mermaid diagrams: use ```` ```mermaid ```` code blocks. Rendering uses the strict security level, and generated SVG is sanitized again with DOMPurify. Clickable links in diagrams are disabled. Syntax errors display the error reason and original source. Diagram colors follow the light/dark theme, and PDF export waits for diagrams to finish rendering. The Mermaid library is about 5 MB and is loaded only when a document contains a mermaid code block.

To prevent unusual documents from slowing down the reader, each document renders at most 2,000 formulas (up to 5,000 characters each) and 50 diagrams (up to 50,000 characters each and 300,000 characters total); excess content is displayed as source. Diagram CSS retains only rules scoped to that diagram, and styles referencing external URLs are discarded. PDF export waits up to 15 seconds for diagrams; if the document changes during that wait, export is canceled with a message. Recent file paths and reading settings are stored in local preferences.

The app has not been notarized by Apple; first launch on another Mac may require permission in System Settings. Tested on macOS 15.7.5 with Apple Silicon; other systems still need actual runtime verification.

## ☕ Buy Me a Coffee

This tool is free to use. If it helps you, you are welcome to [buy me a coffee](https://github.com/boyeye#-%E8%AF%B7%E6%88%91%E5%96%9D%E6%9D%AF%E5%92%96%E5%95%A1--buy-me-a-coffee) by scanning the WeChat QR code, with any amount you choose. Thank you for your support ❤️

If you find it useful, you can [buy me a coffee](https://github.com/boyeye#-%E8%AF%B7%E6%88%91%E5%96%9D%E6%9D%AF%E5%92%96%E5%95%A1--buy-me-a-coffee).
