# Supporting other coding agents

**Status (v0.2): Gemini CLI, Cursor and Codex are WIRED** — installers in
`app/Roster/Data/ProviderInstallers.swift`, payload dialects in
`ClaudeEvent.swift`, one shared relay script at `~/.roster/roster-hook.sh`.
Everything below was verified against each tool's documentation, not
against a live run: real-world validation reports are very welcome (that
is issue-tracker material). opencode and Kimi remain research-only.

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

### Cursor — ★★☆ feasible for the IDE, CLI still catching up

Cursor 1.7+ has `hooks.json` (`~/.cursor/hooks.json` global, or per
project) with stdin-JSON hooks: `beforeSubmitPrompt` (→ prompt
submitted), `stop` with a completed/aborted/error status (→ finished /
failed), plus `conversation_id` and `workspace_roots` for identity and
desks. That is a decent Roster vocabulary.

Caveats: the payload has no obvious "needs input" event; community
reports say the **CLI** (`cursor-agent`) doesn't fire all documented
events yet; and Cursor sessions are IDE windows, so presence scanning has
no documented on-disk session artifact. Verdict: wire the hooks, accept
that presence-only detection may not exist.

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
4. **Cursor** — after the CLI's hooks stabilize.
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
