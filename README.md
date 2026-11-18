# mlisb

Markdown Like It Should Be. A native macOS app for viewing and quickly editing Markdown.

## What it is

mlisb is aimed at AI-assisted development, where repositories are full of `.md` files. It is built with SwiftUI and AppKit, using a TextKit 2 editor. The App Sandbox is on. It requires macOS 14 or later. Bundle id: `net.favoretti.mlisb`.

## Features

- Live editing. Markdown syntax is hidden except where the cursor is. A source mode shows all syntax.
- `mermaid` and `d2` code blocks render as diagrams in place. Source shows when the cursor enters the block. A failed render shows the error.
- Math: `$…$` and `$$…$$` render in place; a formula that fails to parse stays as source.
- Settings (⌘,) set the text size (12 to 24 pt) and line width; View → Bigger, Smaller and Actual Size (⌘+, ⌘-, ⌘0) change the size.
- Markdown extensions: `md`, `markdown`, `mdown`, `mkd`, `mdx`, `qmd`, `rmd`, `mdc`.
- The file's text is saved back unchanged, except where you typed.
- Autosave 1 second after typing stops. Silent reload when the file changes on disk. If both changed, a "Keep Mine / Load Theirs" banner appears.
- Folder sidebar: new file or folder, rename, drag to move, move to Trash, reveal in Finder, and Quick Look preview for images and PDFs.
- Table of contents, find, and a Format menu.
- Find in Folder (⇧⌘F) searches every Markdown file in the sidebar. Open Quickly (⇧⌘O) jumps to a file, a heading or any menu command. The inspector's Problems tab (⇧⌘M) lists broken links, anchors, tables and fences.
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

- App: `cd app && xcodebuild -project mlisb.xcodeproj -scheme mlisb -derivedDataPath .build/xcode test`. Runs inside the sandboxed app. Launcher: `sh bin/test-mlisb.sh`.
- Kit: `cd Kit && swift test`. Covers diagram rendering, export.
- Engine: `cd Vendor/MarkdownEngine && swift test`. One upstream test, `MarkdownHTMLRendererTests` ("bare URLs and emails autolink"), fails on macOS 27. It is unrelated to our changes.

## Command-line tool

- `mlisb file.md`, `mlisb docs/`, `mlisb .`: open a file or folder.
- `mlisb notes.md:42` or `mlisb --line 42 notes.md`: open the file with the caret at the start of line 42. A line past the end goes to the last line. A file that really has a colon in its name opens as that file.
- `mlisb new.md`: creates the file if missing.
- `some-command | mlisb -`: opens piped text as a temporary file.
- `mlisb --help`: lists these forms.

#### Coding agent hook

`mlisb notify` reads one JSON object on stdin (a Claude Code `PostToolUse` payload), and if `tool_input.file_path` (or `tool_input.path`, or `tool_response.filePath`) is an existing `.md`, `.markdown`, `.mdown`, `.mkd`, `.mdx`, `.qmd`, `.rmd` or `.mdc` file, opens it in mlisb without taking focus. It prints nothing and always exits 0, so it never slows or fails the agent's turn.

`mlisb hook install` adds a `PostToolUse` hook (matcher `Write|Edit|MultiEdit`) running `<path to mlisb> notify` to `~/.claude/settings.json`. `mlisb hook uninstall` removes it. Both take `--settings PATH`. Other settings are kept, a copy of the old file is saved as `settings.json.mlisb-backup`, and a file that is not valid JSON is refused and left alone.

Line requests use a private `mlisb://line?file=<path>&line=<n>` URL. The script opens the file first, which gives the app access to it, then sends this URL to the window showing the file.

The tool is a small shell script inside the app bundle. It calls `open`, which gives the sandboxed app access to the paths.

To install, choose **mlisb → Install Command Line Tool…**. The menu shows the command to copy:

```sh
sudo mkdir -p /usr/local/bin && sudo ln -sf '<path to mlisb.app>/Contents/Resources/bin/mlisb' /usr/local/bin/mlisb
```

## Updates

mlisb updates itself with [Sparkle](https://sparkle-project.org) 2.10.0 (pinned exactly). The feed is `https://github.com/favoretti/mlisb/releases/latest/download/appcast.xml`. Updates are verified with the EdDSA public key in `SUPublicEDKey`. The updater only starts when the bundle has both `SUFeedURL` and `SUPublicEDKey`. Controls: **mlisb → Check for Updates…** and **Settings (⌘,) → Updates**.

The app is sandboxed, so `project.yml` adds what Sparkle's [sandboxing guide](https://sparkle-project.org/documentation/sandboxing/) requires: `SUEnableInstallerLauncherService` in Info.plist, and the `com.apple.security.temporary-exception.mach-lookup.global-name` entitlement with `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `-spki`. The downloader service stays off because the app has `com.apple.security.network.client`.

Release builds must sign these inside `Sparkle.framework`, each with Hardened Runtime (`-o runtime`), in this order, and never with `--deep`:

1. `Versions/B/XPCServices/Installer.xpc`
2. `Versions/B/XPCServices/Downloader.xpc`, with `--preserve-metadata=entitlements`. Or delete it, since it is unused here.
3. `Versions/B/Autoupdate`
4. `Versions/B/Updater.app`
5. `Sparkle.framework` itself

Then sign the app. Xcode's Archive and Export does all of this by itself.

Mac App Store variant (the store forbids self-updating): in `app/project.yml` drop the `Sparkle:` entry under `packages`, the `- package: Sparkle` dependency, the four `SU…` Info.plist keys, and the `mach-lookup.global-name` entitlement with its two entries. Then run `xcodegen generate`. All updater code is wrapped in `#if canImport(Sparkle)`, so it compiles away, along with the Settings window and the menu item.

## Releasing

`scripts/build-app.sh` builds a universal `dist/mlisb.app` and zips it. With no settings it signs
ad-hoc, which is enough to check the build:

```
VERSION=0.1.0 scripts/build-app.sh
```

Set `SIGN_IDENTITY` to a Developer ID identity to sign for distribution, and `NOTARY_PROFILE` to a
`notarytool` keychain profile to notarize and staple.

Pushing a tag `vX.Y.Z` runs `.github/workflows/release.yml`: it builds, signs and notarizes, runs
the tests, generates the update feed (`appcast.xml`), publishes a GitHub release and updates the
Homebrew cask. The workflow needs these repository secrets: `DEVELOPER_ID_P12`,
`DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `SPARKLE_ED_KEY`,
`TAP_DEPLOY_KEY`.

The app looks for updates at this repository's latest release, so releases must be publicly
downloadable for updates to work.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘O | Open |
| ⌘, | Settings |
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
