# Supporting other coding agents

**Status: Gemini CLI, Cursor IDE and Codex are WIRED** — installers in
`app/Roster/Data/ProviderInstallers.swift`, payload dialects in
`ClaudeEvent.swift`, one shared relay script at `~/.roster/roster-hook.sh`.
Cursor IDE has been live-validated (3.15 + Claude hooks coexistence).
opencode and Kimi remain research-only; `cursor-agent` CLI / cloud agents
are deferred.

This document is the honest research behind that wiring — Gemini CLI,
Codex, Cursor, opencode, Kimi, DeepSeek — gathered from each tool's
documentation in August 2026, with a feasibility verdict per tool and the
architecture that makes them all fit.

The code-side seam already exists: `AgentProvider`
(`app/Roster/Data/AgentProvider.swift`) is the protocol every source
conforms to, and the room only ever consumes normalized events. Adding a
tool means writing one adapter; nothing in the office, the choreography or
the UI changes.

## The shape of every adapter

`ClaudeCodeSource` set the pattern, and it generalizes:

1. **Discovery (read-only, automatic).** Find the tool's config/session
   folders (`~/.claude*`, `~/.gemini`, `~/.codex`, …) and scan whatever
   session artifacts it leaves on disk. This powers *presence* — an agent
   appears in the room — without touching the user's setup.
2. **Wiring (consent-gated write).** On "Connect", install the tool's own
   notification mechanism (hook, notify program, plugin) so it appends one
   JSON line per event to a spool file under
   `~/Library/Application Support/Roster/`. Always after a timestamped
   backup, always idempotent, always removable.
3. **Translation.** Map the tool's events onto Roster's vocabulary:
   session started / prompt submitted / needs input / finished / failed /
   session ended. Whatever a tool can't express simply never fires — the
   agent still sits and works, it just never stands up.

When the second adapter lands, `ClaudeEvent` should be renamed
`AgentEvent`, and each spool line should carry a `provider` field so one
watcher can tail one spool for everyone.

## Tool by tool

### Gemini CLI — ★★★ feasible, do it first

Gemini CLI grew a full hooks system, openly modeled on the same idea as
Claude Code's: hooks live in `settings.json` (`~/.gemini/settings.json`),
receive a JSON payload on **stdin** carrying `session_id`,
`transcript_path`, `cwd` and `hook_event_name`, and are grouped per event
with matchers.

Relevant events: `SessionStart`, `SessionEnd`, `Notification`,
`AfterAgent` (turn done), `BeforeAgent` (prompt submitted). That covers
Roster's whole vocabulary except the fine-grained "waiting for input"
distinctions, which `Notification` should carry.

The adapter is close to a copy of `HookInstaller` with different event
names, plus one caveat: Gemini hook commands are expected to print *only
JSON* on stdout, so the spool-append command must stay silent (ours
already is). Session transcripts live under `~/.gemini/tmp/<hash>/` and
can back the presence scan.

### Codex CLI (OpenAI) — ★★☆ feasible, partial vocabulary

Codex has exactly one external notification: a `notify` program in
`~/.codex/config.toml` that runs on **`agent-turn-complete`**, receiving a
JSON blob as its final **argv** (not stdin) with `thread-id`, `cwd`,
`input-messages` and `last-assistant-message`.

That maps cleanly to *finished* (with a summary!) but nothing else. The
gaps: no needs-input event, no session-end event. **Presence is
implemented** (v0.3): Roster scans `~/.codex/sessions/YYYY/MM/DD/
rollout-*.jsonl` and decodes each file's first line —
`{"type":"session_meta","payload":{"id":…,"cwd":…}}`, verified live
against codex 0.147.0. That line embeds the CLI's whole system prompt
(~18 KB measured), so the read window is 256 KB, not a few KB. The
`payload.id` equals notify's `thread-id`: the desk that presence creates
is the same session the end-of-turn events later enrich, and the usual
mtime sweep retires quiet rollouts.

Two real risks to design around: `notify` is a *single* global value —
if the user already has one, Roster must wrap it, not replace it (chain
the previous program from ours) — and it's TOML, so editing must be
conservative (append-only, backup first). Recent Codex versions have been
adding richer lifecycle hooks; worth re-checking before building.

### Cursor IDE — ★★★ wired (CLI / cloud deferred)

**Supported surface: Cursor IDE** (Agent Chat / Cmd+K), not
`cursor-agent` CLI or cloud agents.

Cursor 1.7+ has `hooks.json` (`~/.cursor/hooks.json` global, or per
project) with stdin-JSON hooks. Roster installs
`sessionStart` / `beforeSubmitPrompt` / `stop` / `sessionEnd`, mapping
them onto the room vocabulary via `conversation_id` (or `session_id`)
and `workspace_roots`. There is still no fine-grained "needs input"
event.

**Live validation (2026-08-12, Cursor 3.15.6):** Cursor also loads
Roster's Claude Code hooks from `~/.claude/settings.json` and runs them
on overlapping steps. Without a trailing newline on the Claude `cat`
append, the two writers glued JSON onto one spool line and Roster
dropped the event. Fixed by Claude hooks `#roster-v3` (explicit newline),
a mkdir lock in `roster-hook.sh`, and multi-object splitting in the
spool reader. The untagged copy is recognized by its `workspace_roots`
field, so the staleness sweep files both copies under the same
`cursor:<id>` key instead of a phantom unprefixed one.

**Presence (v0.4+):** parent transcripts at
`~/.cursor/projects/<slug>/agent-transcripts/<id>/<id>.jsonl` back the
30 s scan (`CursorTranscripts`). Undocumented → enrichment only; slug→path
only when the reconstructed directory exists. Subagents under
`…/subagents/` are ignored. No process liveness check (IDE processes do
not sit in the workspace cwd).

CLI (`cursor-agent`) still reports incomplete hook coverage — left alone
on purpose.

### opencode — ★★☆ feasible via a plugin

opencode is extended with TypeScript plugins
(`~/.config/opencode/plugin/`), which subscribe to events —
`session.created`, `session.idle` (turn done), `session.error`,
`permission.ask` (→ needs input!), `session.deleted` — and can run shell
commands. A ~30-line plugin appending to Roster's spool covers the whole
vocabulary, arguably better than Codex. "Install" means dropping one
`.ts` file in the plugin folder — easy to add, easy to remove. DeepSeek,
Kimi and friends running *through* opencode get covered for free.

### Kimi CLI (Moonshot) — ★☆☆ research first

Documentation on hooks or session logs is thin; no verified event
mechanism as of this writing. Needs hands-on investigation before any
promise. Parked.

### DeepSeek — not a tool

DeepSeek ships models, not an agent CLI of its own; people run DeepSeek
through opencode, aider and similar. Supporting the *tools* covers the
*model vendors* — Roster should never care whose model is talking.

## Suggested order

1. **Gemini CLI** — same architecture, biggest overlap, real hooks.
2. **opencode** — tiny plugin, full vocabulary, covers many models.
3. **Codex** — finished-only, but the summary payload is great.
4. **Cursor IDE** — done (hooks + presence); CLI/cloud later if hooks stabilize.
5. **Kimi** — once someone can test it for real.

Each adapter should ship with the same guarantees Claude Code got:
presence without consent, one backup per touched config, self-healing
idempotent installs, and silent failure when a tool's undocumented format
drifts.

## Sources

- [Gemini CLI hooks reference](https://github.com/google-gemini/gemini-cli/blob/main/docs/hooks/index.md)
  and [the hooks announcement](https://developers.googleblog.com/tailor-gemini-cli-to-your-workflow-with-hooks/)
- [Codex notify deep-dive](https://backgrind.com/blog/codex-cli-notifications/)
  and [codex#4005 (notify payload fields)](https://github.com/openai/codex/issues/4005)
- [Cursor hooks deep-dive](https://blog.gitbutler.com/cursor-hooks-deep-dive)
  and [Cursor 1.7 hooks (InfoQ)](https://www.infoq.com/news/2025/10/cursor-hooks/)
- [opencode plugins guide](https://gist.github.com/CypherpunkSamurai/30dc0b7683c06560a74f783097c5f912)
  and [opencode#16879 (session.idle)](https://github.com/anomalyco/opencode/issues/16879)
