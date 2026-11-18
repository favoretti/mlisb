# mlisb

Markdown Like It Should Be. A native macOS app for viewing and quickly editing Markdown.

## What it is

mlisb is aimed at AI-assisted development, where repositories are full of `.md` files. It is built with SwiftUI and AppKit, using a TextKit 2 editor. The App Sandbox is on. It requires macOS 14 or later. Bundle id: `net.favoretti.mlisb`.

## Features

- Live editing. Markdown syntax is hidden except where the cursor is. A source mode shows all syntax.
- `mermaid` and `d2` code blocks render as diagrams in place. Source shows when the cursor enters the block. A failed render shows the error.
- The file's text is saved back unchanged, except where you typed.
- Autosave 1 second after typing stops. Silent reload when the file changes on disk. If both changed, a "Keep Mine / Load Theirs" banner appears.
- Folder sidebar: new file or folder, rename, drag to move, move to Trash, reveal in Finder, and Quick Look preview for images and PDFs.
- Table of contents, find, and a Format menu.
- Links to other Markdown files open in the app. `#anchor` links jump to the heading.
- Local images, and Open Recent.
- Export to HTML, PDF, JPEG and ePub. Copy as plain text, rich text, Markdown or HTML.

## Requirements

- Xcode (built with Xcode 27.2).
- XcodeGen: `brew install xcodegen`.
- Node and pnpm, only needed to build the diagram page.

## Build and run

1. `cd render && pnpm install && pnpm build` builds the mermaid and d2 page into `Kit/Sources/MlisbKit/Resources/render/`. That output is gitignored, so this step is required on a fresh clone.
2. `cd app && xcodegen generate`
3. `cd app && xcodebuild -project mlisb.xcodeproj -scheme mlisb -derivedDataPath .build/xcode build`. Or open `app/mlisb.xcodeproj` in Xcode and run. The app lands in `app/.build/xcode/Build/Products/Debug/mlisb.app`.

Re-run `xcodegen generate` after adding or removing source files. Local builds are ad-hoc signed.

## Tests

- App: `cd app && xcodebuild -project mlisb.xcodeproj -scheme mlisb -derivedDataPath .build/xcode test`. 17 tests, run inside the sandboxed app.
- Kit: `cd Kit && swift test`. 16 tests (diagram rendering, export).
- Engine: `cd Vendor/MarkdownEngine && swift test`. 690 tests. One upstream test, `MarkdownHTMLRendererTests` ("bare URLs and emails autolink"), fails on macOS 27. It is unrelated to our changes.

## Command-line tool

- `mlisb file.md`, `mlisb docs/`, `mlisb .`: open a file or folder.
- `mlisb new.md`: creates the file if missing.
- `some-command | mlisb -`: opens piped text as a temporary file.

The tool is a small shell script inside the app bundle. It calls `open`, which gives the sandboxed app access to the paths.

To install, choose **mlisb → Install Command Line Tool…**. The menu shows the command to copy:

```sh
sudo mkdir -p /usr/local/bin && sudo ln -sf '<path to mlisb.app>/Contents/Resources/bin/mlisb' /usr/local/bin/mlisb
```

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘O | Open |
| ⌘/ | Source mode |
| ⇧⌘T | Table of contents |
| ⌘F | Find |
| ⌘B | Bold |
| ⌘I | Italic |
| ⇧⌘X | Strikethrough |
| ⌘E | Inline code |
| ⌘K | Link |
| ⌘1 / ⌘2 / ⌘3 | Heading level 1 / 2 / 3 |

## Repository layout

- `app/`: SwiftUI app (XcodeGen `project.yml`, `Sources/`, `Tests/`).
- `Kit/`: Swift package MlisbKit (diagram RenderService, Exporter).
- `render/`: web source for the diagram page (mermaid and d2 WASM, bundled with esbuild).
- `Vendor/MarkdownEngine/`: our fork of nodes-app/swift-markdown-engine 0.16.0. Changes are listed in its `PATCHES.md`.
- `bin/mlisb`: the command-line script.
- `PLAN.md`: the plan and status.

## Known limits

- The editor does not render these. They show as plain text, and the file is never altered: setext headings, front matter, footnotes, reference-style links, raw HTML, `~~~` fences, and tables without outer pipes.
- Remote (http) images are not loaded. There is no underline command, no formatting bar over the selection, and no math yet.
- A diagram is fitted to the window width when it is drawn. It does not refit while the window is being resized.

## Licenses

- MarkdownEngine (vendored, modified): Apache-2.0.
- mermaid: MIT.
- D2: MPL-2.0.
- highlight.js: BSD-3-Clause, bundled by the engine's code-block product.
- The project itself has no license file yet.
