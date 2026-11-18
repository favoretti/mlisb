# Changelog

What changed in each released version of mlisb, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

Nothing yet.

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

[Unreleased]: https://github.com/favoretti/mlisb/compare/v0.1.5...HEAD
[0.1.5]: https://github.com/favoretti/mlisb/releases/tag/v0.1.5
[0.1.4]: https://github.com/favoretti/mlisb/releases/tag/v0.1.4
[0.1.3]: https://github.com/favoretti/mlisb/releases/tag/v0.1.3
[0.1.2]: https://github.com/favoretti/mlisb/releases/tag/v0.1.2
[0.1.1]: https://github.com/favoretti/mlisb/releases/tag/v0.1.1
[0.1.0]: https://github.com/favoretti/mlisb/releases/tag/v0.1.0
