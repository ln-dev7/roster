# Decisions

Short log of the choices that shape Roster, so contributors (and future us)
know _why_, not just _what_. Dates are decision dates.

## Product (2026-08-08)

- **Not a dashboard.** Conductor, Vibe Kanban, and Claude Code's own
  `claude agents` view already do lists/states/diffs well. Roster's only
  bet is the animated spatial metaphor — if a screen starts looking like a
  table or a kanban, it's off course.
- **The deliverable is the GIF.** Visual craft and the walk animation beat
  feature coverage, always. The scope test for any addition:
  _does it improve the GIF?_
- **Stations are projects, not agents.** Agents are ephemeral; the repo you
  work on persists. Two agents can share one station.
- **V0 scope:** Claude Code only, VS Code only, one machine, five visual
  states (+ error), three click actions (open editor, open terminal, show
  summary). Everything else is out.
- Known neighbors, found during research: `liuyixin-louis/agentroom`
  (Tauri, pixel art, multi-CLI) and `harishkotra/agent-office` (web,
  simulated agents). The niche is validated, not occupied — Roster
  differentiates on native macOS craft and the "comes to _your_ desk"
  moment.

## Visual direction (2026-08-08)

- **Blueprint.** Top-down architect's plan, fine strokes, ink on paper
  (light) / night blueprint (dark). Agents are dots: filled = working,
  hollow + pulse = waiting for you, moving along a self-drawing dashed
  line = coming to your desk. No accent color; shape carries state. Chosen
  over "soft geometric" mockup and over pixel art (deliberately avoided:
  that's the competitors' aesthetic).
- Calm at rest is a hard requirement: when everyone works, (almost)
  nothing moves.

## Data source (2026-08-08)

- **Primary: Claude Code hooks** — documented interface; `Notification`
  matchers (`agent_needs_input`, `agent_completed`, `permission_prompt`,
  `idle_prompt`), `Stop` (with `last_assistant_message` — powers the
  summary action), `StopFailure` (error state), `SessionStart`/`SessionEnd`.
- **Transport: spool file.** The installed hook appends the event JSON to
  `~/Library/Application Support/Roster/events.jsonl`; Roster watches it
  with FSEvents. Works while Roster is closed (catch-up on launch), no
  local server, no network.
- **Bootstrap: transcript scan.** On launch, recent-mtime scan of
  `~/.claude/projects/` to reconstruct current state. Undocumented format →
  enrichment only, never source of truth, isolated behind a thin
  `AgentEventSource` layer.
- Installing the hook edits `~/.claude/settings.json`: done in-app, with
  explicit consent and a backup of the file first. It is the app's only
  invasive act.

## Tech (2026-08-08)

- **SwiftUI, no SpriteKit.** SwiftUI is retained-mode: a calm room costs ~0
  CPU, which matters for an app open all day. SpriteKit's render loop never
  sleeps and needs manual pausing. Our animation needs (A→B easing walk,
  small pulses) fit `KeyframeAnimator`/implicit animations. SpriteKit only
  wins with dozens of characters/particles/physics — all out of scope.
- macOS 14 deployment target; XcodeGen; hardened runtime; **no sandbox**
  (must read `~/.claude` and write the hook) → no Mac App Store, Developer
  ID + notarized DMG on GitHub Releases instead. Same pipeline as DockKeep.
- **Sparkle: wired but silent.** Ships in increment 5 together with the
  release pipeline; update check stays off until roster.lndev.me serves the
  appcast. Kept out of the prototype on purpose — no dead code in the
  kill-gate build.
- Window: normal window with an "always on top" toggle (increment 4).
  Native macOS notification when an agent reaches your desk. Terminal
  action opens Terminal.app at the project folder (finding the _exact_
  terminal window of a session is not reliably possible).

## Name (2026-08-08)

"Roster" kept after checking GitHub / npm / Homebrew / Mac App Store.
Closest neighbor: `firatcand/roster` (Claude Code multi-agent _framework_,
17★) — different sub-niche, cohabitation accepted. Verified fallbacks if it
ever bites: Homeroom, Workroom, Rollcall.

## Cursor IDE (2026-08-12)

- **Supported surface is Cursor IDE** (Agent Chat / Cmd+K), not
  `cursor-agent` CLI or cloud agents. Hooks live in `~/.cursor/hooks.json`
  (`sessionStart`, `beforeSubmitPrompt`, `stop`, `sessionEnd`).
- **Cursor imports Claude Code user hooks.** When both are Connected,
  one IDE step runs Claude's Roster `cat` append and our Cursor relay in
  parallel. Claude hooks must therefore end every spool write with an
  explicit newline (`#roster-v3`), the shared relay uses a mkdir lock, and
  the spool reader splits glued JSON objects so a corrupted line still
  yields the tagged Cursor event. `workspace_roots` identifies the
  untagged copy, so it files transcripts under `cursor:<id>` rather than
  a key no desk can match.
- **IDE presence** scans `~/.cursor/projects/*/agent-transcripts/<id>/<id>.jsonl`
  (undocumented → enrichment only, fail silently). Subagent transcripts
  are ignored. Rich states still need Connect.
- **The editor action follows the provider.** A Cursor desk offers "Open
  in Cursor", the terminal CLIs keep V0's VS Code default (they own no
  window, and their sessions often run in VS Code's terminal). Handing the
  app the project folder is enough to raise the window already holding it —
  no per-window addressing needed, so nothing to guess.
