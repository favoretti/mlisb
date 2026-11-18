# mlisb: Markdown Like It Should Be

A native macOS app for viewing and quickly editing markdown, built for AI-assisted dev work
where every repo is full of `.md` files. Mermaid and D2 work out of the box. Publisher: favoretti.
Goal: Mac App Store release.

## Principles
- **Native first.** AppKit text editing, so input methods, spellcheck, dictation, Services,
  Writing Tools and accessibility all behave like they do in every other Mac app. WebKit is
  used only for what requires a browser engine: rendering diagrams and laying out exports.
- **The file text is the document.** No converting to HTML or rich text and back. Bytes you
  didn't touch stay exactly as they were, so git diffs show only real edits.
- **GitHub is the reference.** Rendering targets GitHub Flavored Markdown, since that is what
  developers and agents write for. Where we differ from github.com, that is a bug (list below).
- **Read first, edit second.** Opening a file is instant and shows it rendered. You edit in place.
- **Stays in sync with agents.** If an agent edits the file on disk, the app reloads it without asking.

## Features (v1.0)
| Feature | How |
|---|---|
| WYSIWYG editing, CommonMark + GFM, syntax hidden when you're not editing | MarkdownEngine (TextKit 2). `⌘/` switches between Live and Source |
| BIU formatting bar | A floating bar over the selection, plus `⌘B` / `⌘I` / `⌘U`. They wrap the selection in `**`, `*`, `<u>` (CommonMark has no underline). Also heading, list, quote, code and link buttons |
| Tables, quotes, lists, code blocks | MarkdownEngine, with code highlighting from its `MarkdownEngineCodeBlocks` product |
| Inline images and attachments | Paths relative to the file, served from the granted folder. Dropping in a file copies it into `./assets/` and inserts a link |
| Math | `MarkdownEngineLatex` (SwiftMath, native). Falls back to MathJax in the render WebView for anything SwiftMath can't handle |
| **Mermaid + D2** | The RenderService draws them as image attachments, cached by a hash of the source |
| Copy as plain text / rich text / Markdown / HTML | Every format comes from one Markdown → HTML step (swift-markdown / cmark-gfm), with diagrams inlined as SVG. Rich text = the HTML converted to an attributed string, put on the pasteboard as RTF + HTML |
| Export to PDF, JPG, ePub, HTML | One styled HTML document, laid out by the RenderService: PDF via `WKWebView.createPDF` / print, JPG via a full-page snapshot. ePub is that HTML packaged as XHTML + OPF in a zip (we write it, no dependency) |
| Manage files and folders in the sidebar | New file or folder, rename, move by dragging, Move to Trash (`FileManager.trashItem`), Reveal in Finder. All inside the granted folder |
| Tabs | macOS window tabs (`⌘T`, merge windows) come with `WindowGroup`, and each tab shares the same workspace. Build a custom tab bar only if native tabs feel wrong |
| Image preview in the editor | Selecting a non-markdown file in the sidebar shows it in a `QLPreviewView` (Quick Look), which also covers PDFs and other formats |
| **`mlisb` CLI** (like `code`) | `mlisb file.md`, `mlisb docs/`, `mlisb .`, `mlisb new.md` (creates the file), `… \| mlisb -` (pipe in an agent's output). See [CLI](#cli) |
| Table of contents | Headings from swift-markdown, shown in a trailing `.inspector` panel. Click one to scroll there, and the current section is highlighted |

## Architecture

```
app/     SwiftUI shell (XcodeGen project.yml): windows, sidebar, document load/save, menus
Kit/     Swift package MlisbKit: RenderService (diagrams), Exporter
render/  Web source for the diagram page (mermaid + d2 WASM). `pnpm build` writes it into Kit
Vendor/MarkdownEngine/  Our fork of nodes-app/swift-markdown-engine 0.16.0 (see its PATCHES.md)
bin/mlisb               The command-line launcher, copied into the app bundle

SwiftUI WindowGroup(for: URL) → WorkspaceView (root = a folder or a single file)
├─ Sidebar (folder roots only): lazy tree, file management, one FileWatcher per open folder
├─ EditorPane: MarkdownEngine editor | Quick Look preview for non-markdown files
│     ```mermaid / ```d2 → engine DiagramRenderer hook → DiagramStore → RenderService → image
└─ Inspector: table of contents

RenderService: one hidden WKWebView for the whole app, never visible
  - render(language, source, theme) async → SVG + vector PDF, cached
  - page is served from the app bundle over a private URL scheme; its CSP blocks all network
```

- **Engine fork.** The upstream engine had no hook for fenced blocks, opened relative links as
  `https://…`, rewrote `->` to `→` while typing, and moved the caret to the end on reload. We
  vendor it and keep the changes small and listed in `Vendor/MarkdownEngine/PATCHES.md`.
- **GitHub-flavored coverage.** Rendered like github.com: fenced code in every valid form
  (backticks or tildes, indented, inside lists and quotes) with highlighting, tables with or
  without outer pipes, task lists, strikethrough, autolinks, alerts, setext headings, front
  matter, reference-style links, footnotes, math, mermaid, and a safe subset of raw HTML
  (`kbd`, `sub`, `sup`, `mark`, `details`, `img`, comments and similar). The file is never altered.
- **Known differences from github.com:**
  - An opening fence with no closing fence stays ordinary text, so typing a fence does not
    turn the rest of the document into code.
  - `<br>` outside tables shows as a dimmed tag; `<details>` is always expanded.
  - A reference-style image (`![alt][label]`) is shown as a link, not drawn.
  - Footnote definitions do not span continuation lines; a code block inside a list item is
    drawn flush left.
  - Indented (four-space) code blocks and any HTML outside the safe subset show as plain text.
- **Diagrams**: when the cursor enters a block it shows source; leaving it renders. A failed
  render shows the renderer's error message in place of the diagram.
- **Saving**: automatic, 1 s after you stop typing and when the app loses focus. Written in
  place (same inode), never through a temp file.
- **Changes on disk**: if there are no unsaved edits, reload silently and keep the cursor.
  Otherwise show a "Keep Mine / Load Theirs" banner.
- **Opening**: a file inside an already-open folder is selected in that window; a file that is
  already open is focused, not opened twice.

## CLI
- A shell script of about 15 lines, shipped in the app at `mlisb.app/Contents/Resources/bin/mlisb`.
  It creates any file that doesn't exist yet. With `-` it writes stdin to a temp `.md` file. Then
  it runs `open -b <bundle-id> <paths>`.
- **Why a script that calls `open`:** a sandboxed app can only read files the user handed it.
  Opening through LaunchServices counts as handing them over, exactly like double-clicking in
  Finder. A compiled helper inside a sandboxed app would itself be sandboxed and couldn't read
  the paths it's given. The script runs as you, outside the sandbox, and just passes paths along.
- **Installing:** a sandboxed app can't write to `/usr/local/bin`. *mlisb → Install Command Line
  Tool…* shows the one-line command with a Copy button:
  `sudo ln -sf /Applications/mlisb.app/Contents/Resources/bin/mlisb /usr/local/bin/mlisb`.
  The direct-download DMG / Homebrew cask installs it automatically with the cask's `binary` stanza.
- Later: `file.md:42` to jump to a line (passed alongside the file through a URL scheme), and
  `--wait` so mlisb can be used as `$EDITOR`.

## App Store constraints
- **App Sandbox**: folders come from `NSOpenPanel` or the CLI, saved as security-scoped bookmarks.
  The app also needs the outgoing-network entitlement: WebKit's helper processes won't start
  without it, even for local content. A single
  file opened from Finder grants only that file, so offer "Grant folder access" when relative
  images need it. Exports go through `NSSavePanel`.
- **No running external programs**: D2 runs as WASM (it could later be linked as a Go
  c-archive), never the `d2` CLI.
- **Licenses**: MarkdownEngine and swift-markdown are Apache-2.0, mermaid / highlight.js /
  MathJax are MIT/BSD/Apache, D2 is MPL-2.0. The About window lists them all: `THIRD-PARTY-NOTICES.md`
  plus the license of every JavaScript package the build bundled.
- **Distribution**: needs an Apple Developer Program membership under favoretti.

## Status (2026-11-18)
Working:
- Editing: live and source views, mermaid, d2, math, code highlighting, Format menu, find.
- Reviewing: marks for what changed since the last review (added, rewritten, removed), next and
  previous change, Mark Reviewed, local version history with compare and restore.
- Navigating: folder sidebar with file management and Quick Look, table of contents, search
  across the folder, Open Quickly (files, headings, every menu command), a Problems list.
- Files: autosave, silent reload, conflict banner, links between documents, local images,
  export (HTML, PDF, JPEG, ePub) and copy-as, Open Recent, sandbox bookmarks.
- System: Quick Look preview, `mlisb` CLI (open at a line, the agent hook), settings for text
  size and line width, built-in updater, release script and workflow.

Not done or not verified:
- Finder thumbnails are built but the system did not pick them up in a development build.
- The updater has never installed a real update; that needs a second release. Version 0.1.0 was
  signed, notarized and published by the release workflow.
- Remote images, a formatting bar over the selection, underline, image drop into `./assets/`.
- See "Known differences from github.com" above.

## Milestones
0. **Spike (go/no-go on the engine)**: put MarkdownEngine in a bare app and open real
   agent-written docs. Check:
   - Saving gives byte-identical output for untouched regions.
   - Syntax is hidden except near the cursor, or can be made to behave that way.
   - It has hooks for custom fenced blocks and attachments.
   - Which parser it uses, and how it handles tricky CommonMark (nested and lazy lists,
     HTML blocks).
   - A 5k-line file stays smooth.
   - `open -b <id> some/folder` from Terminal gives the sandboxed app access to the whole folder,
     which the CLI depends on.
   - If it fails: write our own TextKit 2 styling on top of `swift-markdown` source ranges,
     falling back to CodeMirror in WebKit as a last resort.
1. **RenderService**: mermaid, d2, math fallback, cache, light/dark, errors.
2. **Shell**: workspace window, sidebar with file management, native tabs, open / autosave /
   reload, file associations (`.md`, `.markdown`, `.mdown`), sandbox and bookmarks, recents,
   Quick Look preview, `mlisb` CLI + Install Command Line Tool sheet.
3. **Writing tools**: BIU bar and shortcuts, table of contents inspector, image drop into
   `./assets/`, internal `.md` links open in the workspace, find.
4. **Share and export**: copy as plain / rich / Markdown / HTML; export HTML, PDF, JPG, ePub.
5. **Ship**: Acknowledgements, icon, App Store listing, TestFlight.

## Out of v1
Search across files, custom themes, plugins, DOCX export, iOS.

## Open
- Final name (check App Store Connect availability early).
