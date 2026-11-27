# Accessibility

mlisb should be usable by everyone who reads and edits Markdown on a Mac, including people who use
VoiceOver, the keyboard alone, larger text or other assistive technology. Where it falls short,
that is a bug.

## How the app is built for it

mlisb is native AppKit and SwiftUI, with no web view around the document. The text you read and
edit is a standard Mac text view, so VoiceOver, Voice Control, Dictation, Full Keyboard Access,
spell checking and Writing Tools work on it as they do in other Mac apps.

- **Text size:** **Settings → Reading → Text size** goes from 12 to 24 points, and ⌘+ / ⌘- / ⌘0
  change it in the window.
- **Line width:** Narrow, Medium, Wide or Full width, under **Settings → Reading**.
- **Light and dark:** the app follows the system appearance, and diagrams are drawn to match it.
- **Keyboard:** every main action has a menu command, and most have a shortcut (see the
  [shortcut table](README.md#keyboard-shortcuts)). **Open Quickly** (⇧⌘O) and **Find in Folder**
  (⇧⌘F) reach any file without the mouse.
- **Source mode** (⌘/) shows every Markdown marker as text, for anyone who prefers the raw file.

## Supported environments

macOS 14 or later, with the accessibility features built into macOS. VoiceOver is the screen
reader we test with.

## Known limitations

- Mermaid and D2 diagrams and math formulas are drawn as pictures, and VoiceOver does not describe
  them yet. Source mode (⌘/), or placing the caret inside the block, shows their text.
- Task-list checkboxes and note icons have no spoken label of their own.
- Increase Contrast, Reduce Transparency and Reduce Motion have not been checked systematically.
- The app has not had a full VoiceOver audit. The tab bar and the text view have had fixes, the
  sidebar, Open Quickly and the review bar have not been looked at closely.

## Reporting a barrier

Open an [issue](https://github.com/favoretti/mlisb/issues/new?template=bug_report.yml&labels=bug,accessibility)
and say which assistive technology you use, what you tried to do and what happened. A barrier
report is treated as a bug, not a feature request. If you would rather not post publicly, email
favoretti@gmail.com.
