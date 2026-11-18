# Local changes to MarkdownEngine

Base: upstream tag 0.16.0 (see `UPSTREAM`). Every change is marked with a `// mlisb:` comment.
To see the full diff: `diff -ru <upstream checkout>/Sources Sources`.

| Change | Files |
|---|---|
| Overlay scroller always (no legacy scroller with a track) | `TextView/ClampedScrollView.swift` |
| `DiagramRenderer` service: fenced blocks drawn as images, source shown when the caret is inside | `Services/MarkdownEditorServices.swift`, `Styling/MarkdownStyler+Diagrams.swift` (new), `Styling/MarkdownStyler.swift`, `TextView/NativeTextViewWrapper.swift` |
| `NativeTextViewWrapper.onOpenLink: ((String) -> Bool)?`: markdown links and bare URLs offered to the embedder with the raw target; `true` = handled | `TextView/NativeTextViewWrapper.swift`, `TextView/Coordinator/NativeTextViewCoordinator.swift`, `TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift` |
| `ListStyle.arrowReplacementEnabled` (default true): opt out of the `->` to `→` rewrite | `Configuration/MarkdownEditorConfiguration.swift`, `Input/MarkdownListHandler.swift` |
| `MarkdownEditorConfiguration.revealAllSyntax` (default false): styled source mode, every construct treated as active; runtime flip restyles in place | `Configuration/MarkdownEditorConfiguration.swift`, `Styling/MarkdownASTStyler.swift`, `Parser/MarkdownDetection.swift`, `TextView/Coordinator/NativeTextViewCoordinator+Restyling.swift`, `TextView/NativeTextViewWrapper.swift` |
| External `text` replace for the same `documentId` keeps selection (clamped) and scroll; rebuild now clamps a restored selection instead of dropping it | `TextView/NativeTextViewWrapper.swift`, `TextView/Coordinator/NativeTextViewCoordinator+Restyling.swift` |
| List continuation lines (hard-wrapped item text) take the item's text indent; their source indentation collapses | `Styling/MarkdownASTStyler.swift` |

Tests: `Tests/MarkdownEngineTests/MlisbPatchTests.swift`.

Known upstream test failure on macOS 27 (not caused by these changes):
`MarkdownHTMLRendererTests` "bare URLs and emails autolink" (`www.example.com`).
