<p align="center">
  <!-- The demo GIF lands here before anything else. It IS the readme. -->
  <em>(demo GIF coming with the first release)</em>
</p>

# Roster

**Your coding agents, in a room. They come to your desk when they're done.**

Roster is a macOS app that shows your Claude Code sessions as colleagues in a
small office, drawn like an architect's blueprint. They work at their
stations; when one needs you, it stands up; when one finishes, it gets up,
crosses the room, and waits at your desk.

Not a dashboard. No lists, no columns, no diffs — other tools do that well.
Roster is the glanceable, ambient version: the state of the room *is* the
state of your agents.

## Status

Early prototype — increment 1 of 5: the walk, with simulated data.
If the walk isn't delightful, nothing else gets built.

## Build

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
cd app
xcodegen
open Roster.xcodeproj   # then ⌘R
```

The `.xcodeproj` is generated and not versioned; `app/project.yml` is the
source of truth.

## Repository layout

```
app/      the macOS app (Swift, SwiftUI, XcodeGen)
site/     the product site — later (roster.lndev.me)
shared/   assets shared between app and site
scripts/  build, release and tooling scripts — later
docs/     decisions and notes
```

## License

MIT — see [LICENSE](LICENSE).
