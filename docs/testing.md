# Testing Roster, from zero

The full manual pass. Steps 1–2 need nothing but Xcode; step 3 onwards
needs Claude Code installed. Every step says what you should *see* — if
you see something else, that's a bug worth filing.

## 0. Clean slate (optional)

Skip this on a first install; use it to re-test the onboarding.

```sh
# Quit Roster first.
defaults delete com.lndev.roster            # window prefs, panel toggle
rm -rf ~/Library/Application\ Support/Roster  # spool + remembered desks
```

Remove Roster's hooks from `~/.claude/settings.json` (everything else in
the file is preserved):

```sh
python3 - <<'EOF'
import json, pathlib
p = pathlib.Path.home() / '.claude/settings.json'
d = json.loads(p.read_text())
hooks = d.get('hooks', {})
for event in list(hooks):
    kept = []
    for entry in hooks[event]:
        inner = [h for h in entry.get('hooks', [])
                 if 'Roster/events.jsonl' not in h.get('command', '')]
        if inner:
            entry['hooks'] = inner
            kept.append(entry)
    if kept: hooks[event] = kept
    else: hooks.pop(event)
d['hooks'] = hooks
p.write_text(json.dumps(d, indent=2, sort_keys=True))
print('Roster hooks removed')
EOF
```

(Timestamped backups from previous installs sit next to the file:
`ls ~/.claude/settings.json.roster-backup-*`.)

## 1. Build & unit tests

```sh
cd app
xcodegen
open Roster.xcodeproj
```

- **⌘U** — the whole suite (state machine, walk rule, event parsing,
  settings merge, geometry, desk persistence) must be green.
- **⌘R** — the app launches: blueprint room, banner at the top, three
  demo desks with seated dots, monitors breathing.

## 2. The choreography, offline (simulation panel)

The panel is visible while not connected (later: Debug → Show Simulation
Panel, ⇧⌘D).

| Action | Expected |
|---|---|
| `Finished` on dockkeep | stands, dashed path draws itself, 2.9 s crossing, waits at LN's desk with a halo — and stays |
| `Answered` on it | walks back, sits, monitor breathes again |
| `Needs input` | stands next to its chair, dot goes hollow, ring pulses |
| `Error` | dot turns red with a cross, pulled back to its station |
| `+ circle` | second dot fades in; the two spread around the chair |
| `Finished` on two agents | they queue side by side at your desk |
| `End` | dot fades out; the desk stays |
| Click any dot | popover: status, "No summary yet", folder actions disabled (demo desks have no repo), `Reviewed` on a finished agent |
| System appearance toggle | ink-on-paper ↔ night blueprint |
| View → Keep on Top (⌥⌘T) | window floats above other apps |

## 3. Presence, automatically (still not connected)

With Roster running, open a terminal in any repository and start
`claude`. Within ~30 s a desk appears, named after the folder, with a
seated working dot — no setup, read-only. The popover's *Open in VS
Code* / *Open Terminal* now work (real path). On a Cursor desk the first
button reads *Open in Cursor* and raises that project's Cursor window.

Rich states are NOT expected yet: without the hook the room only knows
who is present.

## 4. Connect, then the real thing

1. Click **Connect** in the banner. Check:
   ```sh
   grep -c roster-v3 ~/.claude/settings.json    # ≥ 1
   ls ~/.claude/settings.json.roster-backup-*   # backup exists
   ```
2. **Restart your claude session** — hooks load at session start.
3. Short turn ("say ok"): the agent must **stay seated**. That's the
   walk rule: < 45 s of work doesn't earn a crossing.
4. Long turn ("explore this repo and summarize its architecture, take
   your time"): on completion — stand, beat, crossing, halo. If another
   app is frontmost, a notification fires (allow it on first ask).
5. Click the dot: the summary is the agent's last message. `Reviewed`
   sends it home.
6. Trigger a permission prompt (ask for a command it must confirm): the
   dot stands and pulses. Answer in the terminal: it sits back.
7. End the session: the dot fades out, the desk stays.
8. Quit and relaunch Roster: desks come back (empty seats), and it
   reconnects silently — no banner. The spool replay restores states.

Plumbing checks, if anything looks off:

```sh
tail -5 ~/Library/Application\ Support/Roster/events.jsonl
log stream --predicate 'subsystem == "com.lndev.roster"' --level info
```

## 4b. Cursor IDE (Agent Chat / Cmd+K)

Not the `cursor-agent` CLI. Requires `~/.cursor` present; Connect wires
`~/.cursor/hooks.json`.

1. After Connect, confirm the four IDE events:
   ```sh
   python3 - <<'EOF'
   import json, pathlib
   h = json.loads((pathlib.Path.home()/'.cursor/hooks.json').read_text())
   print(sorted(h.get('hooks', {})))
   EOF
   # expect sessionStart, beforeSubmitPrompt, stop, sessionEnd among them
   ```
2. Optionally clear a corrupted spool from an older install:
   `:> ~/Library/Application\ Support/Roster/events.jsonl`
3. In Cursor IDE Agent Chat, open a real workspace and send a short
   prompt. A desk named after the folder should appear (hook and/or the
   `agent-transcripts` presence scan within ~30 s).
4. A longer turn that finishes: agent walks on `stop` / completed.
5. Spool lines must be **one JSON object each**. Cursor may still run
   Claude's Roster hook in parallel — that is expected — but lines must
   not glue:
   ```sh
   tail -f ~/Library/Application\ Support/Roster/events.jsonl
   ```
6. Optional debug: Cursor's hooks log under
   `~/Library/Application Support/Cursor/logs/**/cursor.hooks*.log`
   should show both the Claude `cat` hook and `roster-hook.sh cursor`
   exiting 0.

## 5. Robustness

- Quit Roster, run a few turns in a session, relaunch → the room
  catches up from the spool replay.
- Sessions in a 7th repository are ignored: the room caps at six desks
  by design.
- A session killed without SessionEnd retires on its own once its
  transcript has been quiet for 20 minutes.

## 6. The site

```sh
cd site
pnpm install
pnpm dev        # http://localhost:3000 → redirects to /en
```

- `/en` and `/fr`, switcher in the header, `d` toggles dark mode.
- The hero room loops the walk; it freezes under
  System Settings → Accessibility → Reduce Motion.
- `pnpm build && pnpm typecheck && pnpm lint` — all green.
