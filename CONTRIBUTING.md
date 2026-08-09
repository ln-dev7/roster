# Contributing to Roster

Thanks for considering it. Roster is small on purpose — the bar for a
change is not "is it useful?" but **"does it improve the GIF?"**: the
room, the walk, the glanceability. Dashboards, diffs, kanban views and
multi-agent support are deliberately out of scope (see
`docs/decisions.md` for the full reasoning).

## Setup

```sh
brew install xcodegen
cd app
xcodegen
open Roster.xcodeproj   # ⌘R to run, ⌘U for the tests
```

The `.xcodeproj` is generated — `app/project.yml` is the source of truth.
After adding or removing a source file, run `xcodegen` again. Never
commit the project file.

## Ground rules

- **The room stays calm.** No looping animation that runs while nothing
  is happening; state is carried by shape, not by color.
- **The core stays UI-free and tested.** `Roster/Core` compiles into the
  test bundle directly; every state transition needs a test
  (`docs/testing.md` has the manual pass).
- **Fragile things stay isolated.** Anything that reads Claude Code's
  undocumented internals lives behind `Data/ClaudeCodeSource` and must
  fail silently. The documented hooks are the only source of truth.
- **Decisions get written down.** If your change settles a real choice,
  add a line to `docs/decisions.md`.
- Comments and commit messages are in English; commits are small and
  explain *why*.

## Good first issues

Look for the [`good first issue`](https://github.com/ln-dev7/roster/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
label — each one states the files involved and the expected behavior.

## The site

`site/` is a Next.js app (see `site/README.md`). UI components go through
the shadcn CLI; all copy lives in `site/messages/` in both locales.
