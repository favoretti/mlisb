# Demo project for the screenshots

`orders-service/` is the made-up project that the README's screenshots in
[`docs/screenshots/`](../screenshots/) show. Keep it here so a screenshot can be retaken the same
way after the app changes.

## Taking a screenshot

1. Set macOS to dark mode, except for `hero-light.webp`.
2. Open `orders-service` in mlisb as a folder (File → Open…, or drop it on the Dock icon), in a
   window of its own (Window → Move Tab to New Window), with Settings → Show tabs set to
   "Across the top" so a single tab shows no tab bar.
3. Set up the scene for the screenshot (below), and size the window to about the size given, on a
   Retina screen so the image is twice that in pixels.
4. Press ⇧⌘4, then Space, and click the window. This keeps the window's shadow, as the existing
   screenshots have.
5. Convert it: `cwebp -q 85 Screenshot.png -o docs/screenshots/NAME.webp`.
6. Update the image's `alt` text in the README if what it shows changed.

| Screenshot | Scene | Window (points) |
| --- | --- | --- |
| `hero-dark.webp`, `hero-light.webp` | `docs/architecture.md` selected, Table of Contents open | 1320 × 860 |
| `source.webp` | `docs/data-flow.md` in its own window, Source mode (⌘/) | 830 × 870 |
| `diagrams.webp` | `docs/data-flow.md` in its own window, window not active | 860 × 900 |
| `palette.webp` | `docs/architecture.md` selected, Open Quickly (⇧⌘O) open, nothing typed | 1180 × 590 |
| `review.webp` | `docs/rollout-plan.md` after the edit below, Table of Contents off, the review bar's ▼ pressed until it reads "Change 1 of 4" | 1180 × 900 |

## The review scene

The change marks show what changed on disk since the file was last reviewed. To get them:

1. Open `docs/rollout-plan.md` in mlisb and leave it open.
2. Make the edit an agent would make:
   `cp docs/demo/rollout-plan.edited.md docs/demo/orders-service/docs/rollout-plan.md`
3. mlisb reloads the file, shows the review bar ("1 added · 2 changed · 1 removed") and marks a
   checked task, a reworded sentence, a new Rollback section and a removed risk. Press ⌥⌘↓, or ▼ in
   the bar, to step to a change.
4. Afterwards, put the file back with
   `git checkout docs/demo/orders-service/docs/rollout-plan.md` and press **Mark Reviewed**, so
   the next run starts from the original again.
