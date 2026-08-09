# Good first issues — ready to open

Paste each of these as a GitHub issue with the `good first issue` label
(plus the suggested extra label) once the repo is public. They are
scoped, verified against the codebase, and all pass the scope test.

---

## 1. Rename a workstation

**Labels:** `good first issue`, `enhancement`

Desks are named after the repository folder (`Workstation.name`, set in
`Office.workstationIndex(forPath:)`). A folder called `frontend-v2-final`
deserves a nicer plate.

Add a rename affordance — simplest path: a small "Rename…" button in
`AgentPopover`, or a right-click on the dot. Persist the custom name via
`WorkstationStore` (the `Workstation` struct is already `Codable`).
Keep the label style untouched (uppercase, monospaced, letter-spaced).

Files: `Core/Office.swift`, `UI/AgentPopover.swift`,
`Data/WorkstationStore.swift`.

---

## 2. Choose your terminal app

**Labels:** `good first issue`, `enhancement`

"Open Terminal" hardcodes Terminal.app
(`Data/WorkspaceActions.swift`). Add a picker in Settings → General
(iTerm2 `com.googlecode.iterm2`, Warp `dev.warp.Warp-Stable`, Ghostty
`com.mitchellh.ghostty`), stored in `@AppStorage`, with Terminal.app as
default. Hide choices whose app isn't installed
(`NSWorkspace.urlForApplication(withBundleIdentifier:)` returns nil).

Files: `Data/WorkspaceActions.swift`, `UI/SettingsView.swift`.

---

## 3. Optional sound when an agent reaches your desk

**Labels:** `good first issue`, `enhancement`

V0 shipped silent by design. Add a Settings toggle (default OFF) that
plays a short system sound (`NSSound(named:)`) alongside the arrival
notification. Respect the existing "Notify when an agent reaches your
desk" toggle — no sound when notifications are off.

Files: `Data/Notifier.swift`, `UI/SettingsView.swift`,
`UI/ContentView.swift` (the `onAgentArrived` closure).

---

## 4. French localization of the app

**Labels:** `good first issue`, `i18n`

The development language is English and XcodeGen already turns `.lproj`
folders under `Roster/Resources` into localized resources (see the
comment in `project.yml`). Move the user-facing strings (banner, popover,
Settings, menu items) to a strings catalog and add French. The site is
already bilingual — the app should follow.

Files: most of `UI/`, `Resources/`.

---

## 5. A "Play demo loop" button for recording the GIF

**Labels:** `good first issue`, `tooling`

The simulation panel (Debug → Show Simulation Panel) can stage every
state, but recording the README GIF means clicking buttons in rhythm.
Add a "Play demo loop" button that runs a fixed choreography on the demo
room: work → one agent finishes and walks → waits → reviewed → walks
back → another needs input → answered — with tasteful pauses, looping
until stopped. Everything needed exists on `Office`; it's a scripted
sequence of the calls the panel already makes.

Files: `UI/SimulationPanel.swift`, `Core/Office.swift` (nothing new
needed, just orchestration).

---

## 6. Make the staleness window adjustable

**Labels:** `good first issue`, `enhancement`

A session killed without a clean exit disappears after 20 minutes of
transcript silence (`staleAfter` in `Data/ClaudeCodeSource.swift`).
Expose it in Settings → Claude Code as a stepper or slider (5–60 min,
default 20), stored in `@AppStorage`, read live by the rescan.

Files: `Data/ClaudeCodeSource.swift`, `UI/SettingsView.swift`.
