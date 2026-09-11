## 0.9.0

First public release. The API is still settling — pre-1.0, so breaking changes
come in minor versions.

- `NavState` / `BranchStack` / `NavEntry`: immutable navigation state with
  value equality.
- `AdaptiveRouterDelegate`: `push`, `pop`, `popWithResult`, `replace`,
  `resetTo`, `resetDetailTo`, `popToRoot`, `goBranch`, system back handling and
  a single exit-guard gate across every way out of a screen.
- Three layouts from one state: compact (navigation bar, detail over the bar),
  medium (rail, one pane) and expanded (rail, master-detail panes), with the
  screens' element tree preserved across every transition.
- `AdaptiveRouteInformationParser` plus an app-supplied `RouteCodec` for deep
  links and cold start.
- Configurable chrome: custom bar and rail builders, a drawer, hidden branches,
  a chromeless mode and a redirect hook.
- Pane decoration (margins, gap, radius, canvas, borders), a draggable pane
  divider through `PaneSplitController`, and an immersive mode that slides the
  rail away.
