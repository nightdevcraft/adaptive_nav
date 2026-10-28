# adaptive_nav

The repository of two Flutter packages:

| Package | | |
|---|---|---|
| [adaptive_nav](packages/adaptive_nav) | [![pub](https://img.shields.io/pub/v/adaptive_nav.svg)](https://pub.dev/packages/adaptive_nav) | A Navigator 2.0 router that renders one navigation state as a stack or as master-detail panes and keeps screen state across resizes and folds. |
| [adaptive_nav_ios](packages/adaptive_nav_ios) | [![pub](https://img.shields.io/pub/v/adaptive_nav_ios.svg)](https://pub.dev/packages/adaptive_nav_ios) | iPhone Duo geometry from UIKit for adaptive_nav: the side of the system's vertical bar, its status area and the fold. |

**[Try it in the browser](https://nightdevcraft.github.io/adaptive_nav/)**:
the example app, [`packages/adaptive_nav/example`](packages/adaptive_nav/example),
in a desktop window you can resize, on a phone and a tablet you can rotate,
and on iPhone Duo and Galaxy Z Fold8 you can fold.

## Working on it

The root is a [pub workspace](https://dart.dev/tools/pub/workspaces), not a
package: one `flutter pub get` here resolves both packages and the example
together, and the plugin builds against the adaptive_nav next door.

```sh
flutter pub get
cd packages/adaptive_nav && flutter test
```

A release is a tag: `adaptive_nav-v0.15.0` publishes
`packages/adaptive_nav`, `adaptive_nav_ios-v0.1.0` publishes
`packages/adaptive_nav_ios` (`.github/workflows/publish.yml`).
