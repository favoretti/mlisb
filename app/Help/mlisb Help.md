# mlisb Help

mlisb shows Markdown the way GitHub would, and lets you edit it in place. This page is itself a Markdown file, opened read-only.

## Reading and editing

- Click into a line to edit it. The syntax shows only where the cursor is.
- **View → Source Mode** (⌘/) shows all the syntax at once.
- A paragraph wraps to the window, as on GitHub, even if the file breaks it into shorter lines. The file keeps its line breaks, and Source Mode shows them. Two spaces or a backslash at the end of a line make a line break that always shows.
- The title bar shows the full path of the open file.
- Changes save by themselves, one second after you stop typing. Only what you typed changes in the file.
- **File → New Document…** (⌘N) starts a new file. **File → Open…** (⌘O) opens a file or a whole folder.

## Diagrams, math and code

A `mermaid` or `d2` code block draws as a diagram. Put the cursor inside it to see its source.

```mermaid
flowchart LR
    Write --> Save --> Review
```

```d2
direction: right
you -> mlisb: open a file
mlisb -> you: rendered
```

Math goes between dollar signs, like $e^{i\pi} + 1 = 0$, and code blocks are highlighted:

```swift
print("Markdown like it should be")
```

## Seeing what changed

When a file changes on disk while it is open, mlisb reloads it and marks what is different since you last looked: added lines in green, rewritten lines in amber, and a marker where lines were removed.

- ⌥⌘↓ and ⌥⌘↑ step through the changes.
- **Mark Reviewed** (⌥⌘R) clears the marks.
- **Version History** (⌃⌘H) compares with an earlier version, or restores one. Versions are kept for 30 days.

If you were typing when the file changed, a banner lets you keep your version or load the new one.

## Finding things

- **Open Quickly** (⇧⌘O) finds a file in the folder, a heading in the document or any menu command.
- **Find in Folder** (⇧⌘F) searches every Markdown file in the sidebar. **Find** (⌘F) searches the document.
- **Table of Contents** (⇧⌘T) and **Problems** (⇧⌘M) open in the panel on the right. Problems lists broken links, anchors that point nowhere, malformed tables and code fences that never close.

## Setting up

Open **mlisb → Settings** (⌘,). Under **General**:

- **Reopen windows from last time.** On by default, so the app comes back as you left it.
- **Open files in** a new tab or a new window.
- **Show tabs** across the top, or as a list down the left side. Drag the list's right edge to make it wider or narrower.

Under **Setup**:

- **Default app for Markdown files.** Make Default opens every Markdown file with mlisb.
- **Command line tool.** Shows where the `mlisb` command is installed, or how to install it.
- **Claude Code.** Run `mlisb hook install` in Terminal, and every Markdown file the agent writes opens in mlisb without taking focus. `mlisb hook uninstall` removes it.

## From the terminal

```sh
mlisb .                  # open the current folder
mlisb docs/plan.md:42    # open a file at line 42
mlisb notes.md           # creates the file if it does not exist
pbpaste | mlisb -        # read piped text
```

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘N | New document |
| ⌘O | Open a file or folder |
| ⇧⌘O | Open Quickly |
| ⇧⌘F | Find in Folder |
| ⌘F | Find in the document |
| ⌘/ | Source mode |
| ⇧⌘T | Table of contents |
| ⇧⌘M | Problems |
| ⌥⌘↓ / ⌥⌘↑ | Next / previous change |
| ⌥⌘R | Mark Reviewed |
| ⌃⌘H | Version history |
| ⌘B / ⌘I / ⇧⌘X | Bold / italic / strikethrough |
| ⌘E / ⌘K | Inline code / link |
| ⌘1 / ⌘2 / ⌘3 | Heading level 1 / 2 / 3 |
| ⌘+ / ⌘- / ⌘0 | Bigger / smaller / actual size |
| ⌘, | Settings |

## More

- **File → Export** saves HTML, PDF, JPEG or ePub. **Edit → Copy as** copies plain text, rich text, Markdown or HTML.
- Press Space on a Markdown file in Finder for a rendered preview. It fills the Quick Look window, so widen the window to see more.
- Links to other Markdown files open in mlisb. Anything that would leave the app asks first.
- The project, its source and its issue tracker: [mlisb on GitHub](https://github.com/favoretti/mlisb).
