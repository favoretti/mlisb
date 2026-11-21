# Contributing to mlisb

Thanks for taking the time. Bug reports, rendering differences and pull requests are all welcome.
Everyone taking part agrees to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting a problem

- **Something broke or behaves oddly:** open a [bug report](https://github.com/favoretti/mlisb/issues/new?template=bug_report.yml).
- **A document looks different from how github.com shows it:** open a
  [rendering difference](https://github.com/favoretti/mlisb/issues/new?template=rendering_difference.yml).
  GitHub is the reference, so a difference is a bug unless it is on the
  [known list](README.md#where-it-differs-from-github).
- **Something is hard or impossible to use with assistive technology:** see [ACCESSIBILITY.md](ACCESSIBILITY.md).
- **A security problem:** do not open an issue. Follow [SECURITY.md](SECURITY.md).

The most useful thing in any report is the Markdown that shows the problem. A few lines pasted into
the issue, or the file attached, saves a lot of guessing.

## Before you write code

For anything bigger than a small fix, open an issue first and say what you plan to do. It avoids
work that does not fit where the app is going. The principles in [PLAN.md](PLAN.md) explain most
decisions:

- **Native first.** AppKit text editing; WebKit only where a browser engine is required (diagrams,
  export layout).
- **The file text is the document.** Bytes the user did not touch are saved back exactly as they
  were. A change that rewrites untouched text is a bug.
- **GitHub is the reference** for how a document renders.
- **Everything stays on the Mac.** The app runs in the App Sandbox. No network renderers, no
  external binaries, and any link that leaves the app asks first.

## Building and testing

[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) has the full setup. In short:

```sh
cd render && pnpm install && pnpm build && cd ..
cd app && xcodegen generate && cd ..
```

All three test suites must pass before a pull request is merged:

```sh
(cd Kit && swift test)
(cd Vendor/MarkdownEngine && swift test)
(cd app && xcodebuild -project mlisb.xcodeproj -scheme mlisb -derivedDataPath .build/xcode test)
```

A bug fix comes with a test that fails without it, where that is practical.

## Pull requests

- One change per pull request, on a branch from `main`.
- Write the commit title as what the user gets, in plain words: "Tables in exports format their
  cells", not "fix: exporter bug". Put the reasoning, what you tried and what you ruled out in the
  commit body and the pull request description.
- Keep code comments short: what a reader needs at that line, nothing more.
- **Keep the documents in step.** A change a user can see updates, in the same pull request,
  `CHANGELOG.md` (a line under Unreleased), `README.md` (feature text, the Settings table and the
  shortcut table) and `app/Help/mlisb Help.md`.
- **Changes to the vendored engine** in `Vendor/MarkdownEngine` are marked with a `// mlisb:`
  comment and listed in its `PATCHES.md`.
- Include a screenshot for anything that changes how the app looks, in both light and dark mode.

## Licensing

mlisb is MIT-licensed. By contributing, you agree that your contribution is released under the
same [license](LICENSE). Code in `Vendor/MarkdownEngine` stays under its Apache-2.0 license.
