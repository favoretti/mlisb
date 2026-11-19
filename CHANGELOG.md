# Changelog

What changed in each released version of mlisb, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

Nothing yet.

## [0.1.10] - 2026-11-19

### Changed

- Reopening many tabs at launch is faster: a tab in the background builds its editor when you first
  switch to it, and all editors share one syntax highlighter. With 17 tabs, every tab has its file
  after about 4 seconds instead of 7.
- While last time's windows reopen, a window shows "Reopening documents…" instead of offering a new
  document, and the tabs stay unnamed until their files arrive instead of all reading "mlisb".

### Fixed

- With tabs down the left side, the system's tab bar no longer flashes across the top at launch.

## [0.1.9] - 2026-11-19

### Changed

- The third-party notices open in their own window from **Help → Third-Party Notices**, which you can
  resize and search, with each license in a wrapping block. The About window only points there; its
  credits view could not be resized and cut off long lines.

## [0.1.8] - 2026-11-19

### Changed

- The list of tabs down the left side can be resized: drag its right edge. Double-click the edge for
  the default width. The width is the same in every window.

### Fixed

- The scroll bar shows while you scroll.
- Clicking a heading in Table of Contents scrolls to it, also far down a long document.
- Stepping through changes (⌥⌘↓ / ⌥⌘↑) scrolls to a change that is far down.
- The document's height no longer shifts while scrolling after the window changes width.

## [0.1.7] - 2026-11-19

### Changed

- The Quick Look preview fills the width of its window: widening the window widens the text,
  tables and code blocks instead of keeping a fixed column.

## [0.1.6] - 2026-11-19

### Changed

- The lines of a paragraph are joined and re-wrapped to the window, as GitHub shows them, so a file
  wrapped by hand no longer reads as a ragged column. The same goes for a list item's continuation
  lines and the lines of a quote. The file keeps its line breaks; Source Mode shows them, and a hard
  break (two trailing spaces or a backslash) stays a line break.
- Code blocks use the free space to the right of the text column, as wide tables already did.
- The title bar shows the full path of the open file, with the home folder as `~`. Tabs still show
  only the name.

### Fixed

- A line no longer wraps between a link and the punctuation after it, which left a lone `)` at the
  start of the next line.

## [0.1.5] - 2026-11-18

### Added

- Tabs can be shown as a list down the left side of the window: Settings → General → Show tabs.
  A folder tab keeps its file tree beside the list. Each tab has a close button on hover and a
  menu with Close Tab, Close Other Tabs and Move Tab to New Window; New Tab sits at the bottom.

## [0.1.4] - 2026-11-18

### Added

- Settings → General → Open files in: a file opened while a window is already showing becomes a
  new tab or a new window. The default is a new tab.

## [0.1.3] - 2026-11-18

### Added

- The windows that were open come back when mlisb starts, including after an update's Install and
  Relaunch. Settings → General → Reopen windows from last time turns this off.

### Fixed

- A document is saved when the app quits, so an edit typed in the last second before quitting is
  no longer at risk.

## [0.1.2] - 2026-11-18

### Changed

- A table too wide for the text column spreads into the free space on its right before its cells
  wrap tightly or it scrolls sideways.

## [0.1.1] - 2026-11-18

### Added

- Settings → Setup: make mlisb the default app for Markdown files, see where the `mlisb` command
  is installed or how to install it, and copy the command that connects Claude Code.
- File → New Document (⌘N), and a New Document button on the empty window. A new document is a
  file from the start, so it asks where to save first.
- Help → mlisb Help opens a built-in guide.

### Fixed

- Installing with Homebrew no longer prints a deprecation warning about the minimum macOS version.

## [0.1.0] - 2026-11-18

First release.

### Added

- Live editing of Markdown as GitHub would show it: the syntax appears only where the cursor is,
  and Source Mode (⌘/) shows all of it. Bytes that were not edited are saved back unchanged.
- Mermaid and D2 diagrams, math and highlighted code blocks, drawn in place with nothing to
  install.
- GitHub Flavored Markdown: tables, task lists, alerts, footnotes, front matter, reference links,
  strikethrough, autolinks and a safe subset of HTML.
- Change review: when a file changes on disk it reloads, and what is new since the last review is
  marked as added, rewritten or removed. Next and previous change, Mark Reviewed, and a local
  version history with compare and restore, kept for 30 days.
- A banner to keep your version or load the new one when a file changes while it has unsaved
  edits.
- Folder windows with a file tree: new file or folder, rename, drag to move, Move to Trash, Reveal
  in Finder, and a preview for images and PDFs.
- Open Quickly for files, headings and menu commands; Find in Folder; a table of contents; a
  Problems list for broken links, missing anchors, malformed tables and unclosed code fences.
- The `mlisb` command: open files and folders, open at a line (`file.md:42`), create a missing
  file, read piped text, and `mlisb hook install` to open every Markdown file Claude Code writes.
- Export to HTML, PDF, JPEG and ePub; copy as plain text, rich text, Markdown or HTML.
- Quick Look preview of Markdown files in Finder.
- Links to other Markdown files open in the app; anything that would leave the app asks first.
- Settings for text size and line width.
- Automatic updates, a Homebrew cask, and third-party license notices in the About window.

[Unreleased]: https://github.com/favoretti/mlisb/compare/v0.1.10...HEAD
[0.1.10]: https://github.com/favoretti/mlisb/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/favoretti/mlisb/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/favoretti/mlisb/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/favoretti/mlisb/releases/tag/v0.1.7
[0.1.6]: https://github.com/favoretti/mlisb/releases/tag/v0.1.6
[0.1.5]: https://github.com/favoretti/mlisb/releases/tag/v0.1.5
[0.1.4]: https://github.com/favoretti/mlisb/releases/tag/v0.1.4
[0.1.3]: https://github.com/favoretti/mlisb/releases/tag/v0.1.3
[0.1.2]: https://github.com/favoretti/mlisb/releases/tag/v0.1.2
[0.1.1]: https://github.com/favoretti/mlisb/releases/tag/v0.1.1
[0.1.0]: https://github.com/favoretti/mlisb/releases/tag/v0.1.0
