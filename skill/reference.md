# Refusals, sqlite, calibration

Russian: [reference.ru.md](reference.ru.md). English is the copy to follow.

Read this when something fails. Coordinates are a snapshot of the script,
not a second source of truth. Change them in `cursor-stand.sh`, not by
"nudging xdotool in chat".

## Three mechanisms

| | brain | tools | how you spawn one |
|---|---|---|---|
| Cloud Agents | the cloud | someone else's VM | API / MCP `cursor-cloud` |
| CLI `agent` | the terminal | this host | `agent`, `store.db` |
| Agents Window + RC | the cloud | a private worker on this machine | glass / this stand |

CLI `/rename` is not the glass sidebar Rename. CLI history is not a glass resume.

## sqlite

The stand profile is `$CURSOR_STAND_PROFILE/User/globalStorage/state.vscdb`
(default `$XDG_DATA_HOME/cursor-stand` or `~/.local/share/cursor-stand`).
`glass_agents.py` reads `CURSOR_STAND_PROFILE`.

```bash
scripts/glass.sh selected          # selectedAgent, lastRealAgent
scripts/glass.sh resolve --id bc-…
scripts/glass.sh show bc-…         # class + picker fields
scripts/glass.sh created-since <epoch_ms>
scripts/glass.sh handoff-ok /ABS/WS [since_ms [uuid]]   # with uuid, that session; without it, the newest since
scripts/glass.sh newest /ABS/WS [since_ms]      # class=local-rc only
scripts/glass.sh mine "$(hostname)"  # id name ws kind working; local-rc + local
scripts/glass.sh busy "$(hostname)"  # running; plus a local selected with no row
scripts/glass.sh convert-ok UUID /ABS/WS  # 0 local-rc of the folder; 2 still environment
scripts/glass.sh overlay-scan SHOT   # expensive-dismiss / move-working (code 0/3/1)
```

Keys: `cloudAgentRepository.agents*`, `cursor/glass.selectedAgent`,
`cursorAuth/cachedEmail`. Do not write the vscdb by hand.

`glass_agents.py classify`: `local-rc` | `environment` | `private-incomplete`
| `other`.

| class | how it is recognized |
|---|---|
| `environment` | `cloudTargetKey` starts with `logicalEnvironment:` **or** `workspaceRootPath=/workspace` |
| `local-rc` | `usePrivateWorker` plus a non-empty `privateWorkerDisplayName` and `workspaceRootPath`, and it is not an environment |
| `private-incomplete` | `usePrivateWorker`, but no worker name or no path |
| `other` | the rest (Cloud without a private worker) |

Fields `show` prints: `bcId`, `name`, `class`, `workspaceRootPath`,
`localFsPath` (from `privateWorkspaceIdentifier.uri.fsPath`),
`privateWorkerDisplayName`, `cloudTargetKey`, `usePrivateWorker`,
`hasStartedVm`, `environmentPublicId`, `repoUrl`.

A `localFsPath` on disk while `workspaceRootPath=/workspace` is an
Environment bound to a GitHub repo on this machine, **not** a local-rc.
`newest` does not return those sessions. `handoff-ok` with a uuid checks
that session. Without a uuid it looks at the newest of any class since
`since_ms` and refuses unless it is a local-rc of the requested folder.

A new session succeeded when `handoff-ok` exits 0, not when
`usePrivateWorker` is set by itself.

## Worker not ready

The text is `Selected private worker is not available` plus a Request ID.

Wait for a process from the stand profile whose `--worker-dir` is the
handoff folder. Do not wait for a worker from `~/.config/Cursor` (that is
the owner's desktop, or this orchestrator's own RC session).

```bash
scripts/wait-worker.sh /ABS/PROJECT
scripts/stand.sh composer-send --id bc-… --dry-run   # where the input box is; presses nothing
scripts/stand.sh composer-send --id bc-…             # resend into this tab
```

`composer-send` finds the input box on the shot: a new chat is above the
"Plan New Idea" button, a thread is above the footer
`/path @ <hostname>`. An unrecognized screen is not clicked. With `--id`
it refuses when another tab is open (otherwise the text goes into someone
else's session).

Not a New Chat, not a second `handoff` in parallel, and do not print
`--api-key`.

The first convert on Home or No Repo is its own refusal (worker not
ready, a Request ID). The folder is required.

## IBus and the palette

`xdotool type` stays silent because of IBus. Everywhere the script uses
`clip_paste`: the clipboard of **this** `$DISP` plus ctrl+v, and only if
`xclip -o` returned the same text.

Search Agents (Ctrl+Alt+P): the id is pasted only after the palette is
confirmed open (`palette-open`, up to 3 tries). On 2026-10-07 an
unchecked paste dropped a bc-id into the input box of the open session.
OCR splits a short name. Cyrillic comes out as noise. `palette-ok` must
find the name **or** the bc-id / 12+ characters of a uuid without hyphens.
If it does not, Escape.

## The 3.23 Environment trap versus RC conversion (2026-10-07)

On Cursor 3.23 three different gestures, and one of them is RC:

| gesture | what you get |
|---|---|
| Return in the folder search while Recents is visible | Environment, `/workspace` |
| the slash `/remote-control` | Environment even with a This Computer chip (`bc-…`) |
| the "Run on" chip → Self-Hosted Worker | picks Worker in a *new* chat, button Set up Environment |
| footer This Computer → Continue on → Self-Hosted Worker | **local-rc** (`bc-…`) |

An intermediate environment while `convert-ok` is still waiting is not
a refusal. The wait is up to 90 s for `class=local-rc` plus the folder
plus the worker. On 2026-11-25, k-99, `/data/pro/mqlab`
(`cloudTargetKey=gitRepo:github.com/kogriv/mqlab`) was `environment`
with `workspaceRootPath=/workspace` at 10, 20, 30, 40 and 50 s, and
`local-rc` on `/data/pro/mqlab` at 60 s (`bc-0686f1ab`). The same day
`/tmp/curskill-e2e-20261125`, with no GitHub remote, was `local-rc` at
8 s. Judge the row after the command returns. If it is still
environment at 90 s, that is the refusal.

Do not: rename an Environment session to the requested name; use the
slash; Include Changes; treat the Worker chip in a new chat as local RC.

A local sidebar draft (no `bc-`): if it is **not** running, right click →
**Discard**. A running local uuid (2026-10-13: handoff failed at convert,
the agent ran for 50 minutes) is **not** Discard or Archive. `mine` /
`busy` print `kind=local`. Wait until the turn ends, then
`convert --id`. Not Archive All Below. `archive --id` is only for rows in
`cloudAgentRepository`.

## Overlays that break anchors (2026-10-13)

| UI | symptom | what the script does |
|---|---|---|
| Toast "Agent starting expensive processes" (bottom right, X near 1882,970) | `doctor` / handoff: no `env-this-computer`; `composer-send`: "did not recognize the screen" | `overlay-scan` → click the X; **not** Manage Processes / Don't show again |
| "Move agent while it's working?" Cancel / Stop and Move | handoff waited 90 s for Exclude, "did not become local-rc"; the agent kept running locally | Cancel or Escape, then **refuse**; **never** Stop and Move |

`stand_dismiss_overlays` runs before anchors in handoff, convert, and
composer-send (and therefore in the doctor dry-run). Measurement shots
live under the profile, not in the repository:
`var/shots/handoff-fail-convert-211747.png`, `20261013T2225*.png`.

The first turn is not finished while the shot shows "Planning next
moves", even if the footer and the follow-up field are already there
(2026-11-25, `move-working-cancel-155123.png`). Handoff keeps waiting.

## UI anchors (glass 1920×1080 at 0,0, package 3.23.23)

The table is in `glass_agents.py` (`ANCHORS`). `anchor SHOT name` prints
`x y` or exits 1. A zone is where to look, not the click point.

| name | tokens | zone (x0,y0,x1,y1) |
|---|---|---|
| `new-chat` | New, Chat | 0,0,260,130 |
| `folder-chip` | main (click to the left). If main is absent, the folder name to the left of This Computer in the new-chat chip | 700,450,1100,520 |
| `folder-search` | repos | 740,490,1100,545 |
| `folder-result` | a visible result row under the chip. No row, no click | only when Recents is absent |
| `env-this-computer` | This, Computer | 880,450,1200,530 |
| `env-self-hosted` | Worker (the chip is a stop) | 880,450,1300,530 |
| `composer-pos` | footer or follow-up when the thread is open; Idea only on a new chat | from the shot |
| `footer-this-computer` | This, Computer | 400,1035,1100,1080 |
| `send-follow-up` | follow | 400,990,1100,1045 |
| `convert-self-hosted` | Worker (the Continue on menu) | 500,990,1300,1065 |
| `exclude-changes` | Exclude, Changes | 850,540,1100,650 |
| `move-working` | Move, working | 650,450,1250,700 |
| `move-cancel` | Cancel | 900,550,1200,680 |
| `expensive-processes` | expensive, processes | 1450,920,1920,1080 |
| `customize` | Customize | 0,140,260,220 |
| `customize-mcps` | MCPs (fallback McpPs) | 850,210,1200,290 |
| `customize-search` | Search | 700,170,1100,230 |
| `mcp-done` | Done (or the blue button) | 1000,640,1250,740 |

The toast X: `find_expensive_dismiss` (OCR `x` near 1840–1915, 945–995, or
fallback 1882,970). After the first READY, `convert` and handoff call
`glass_convert_to_rc` (shared code). A local uuid before convert is often
**absent** from Search Agents. `convert --id` works when the tab is
already open (right after `handoff --no-convert`). Otherwise it refuses
with a hint, and it does not open New agent.

MCP: `mcp list|find|enable|disable|add` → Customize → MCPs → Configure →
the source toggle (green = on). OCR of short names is loose (`mt5`↔`mts`,
`n8n`↔`nan` or `gn` because of the icon). It OCRs the name crop again,
then compares with mcp.json. A substring shorter than 3 characters is not
a name: "-" and "e" used to match every known server. The row status is
`enabled`, `disabled`, or `error` (Needs Attention, "Error Show Output").
`mcp-toggle` reads pixels of the track. Do not confuse this with the
Cloud Agents MCP dashboard. Do not click Customize search
(`customize-search`): it breaks the panel tabs.

## Settings → Agents (2026-11-22, Cursor 3.30.14)

`settings agents` is read only. A click looks for the label and refuses
if the point is closer than 42 px to Unregister, Log Out, Docs, Build, or
Manage, or if the Agents row is Cloud Agents.

| step | what it looks for | where it does not click |
|---|---|---|
| `file` | File in the menu bar | |
| `settings-item` | Settings, with Exit nearby | the project menu (Log Out / Manage Environment) |
| `agents-nav` | Agents, or "gents" if the icon ate the letter | Cloud Agents, the Build on App card |
| `back` | Back | Settings search |

A toggle: a green track at x≈1386–1417 means on, grey ≈213,213,213 means
off. A dropdown is the crop to the right of the label, not the paragraph
under it. The bottom of the page is "Allowlist Options" or
"always-allowed", not the word Allowlists in the Run Mode paragraph. On
2026-11-22, Legacy Terminal Tool is further down.

**UI is not an RC lease.** `mcp find` / "N tools enabled" is only
Customize. A local-rc agent sees MCP when the private worker has written
the canon into
`$PROFILE/…/cursor-agent-worker/worker-data/<id>/projects/<slug>/mcps/<NAME>/`
(`SERVER_METADATA.json` plus `tools/`). If a project `.cursor/mcp.json`
plus enable still do not put the namespace in the session, add the same
server to the user `~/.cursor/mcp.json` (`mcp add --user`), `enable`
again, open the folder's tab, and wait for the cache. Check with
`composer-send` ("namespace … ready"). Cache duplicates `project-0-<NAME>`
and `user-<NAME>` are a side effect of the source id changing. After
`ready`, leave the canon `<NAME>` and the duplicates can go. Do not plant
tool files in the cache by hand (a stale lease). For the user, "the
session saw MCP" means the agent's reply or namespace `ready`, not a line
in `mcp list`.

Rename and archive: X=120, Y=the bright sidebar band. Y<130 is New Chat,
a refusal. If `shot` after a step is the wrong UI, stop. Do not tune
numbers from chat.

`up` takes no project path. If the IDE is up, the palette is "Open Agents
Window" (the script). IME in `up`: `GTK_IM_MODULE=xim`, `XMODIFIERS=""`.

dbus: do not export a dead address from `state.env` (`dbus_addr_alive`).
Do not write `DBUS_SESSION_BUS_ADDRESS=...` as a word in front of the
binary (bash looks for a file). `--password-store=basic` (gnome-keyring
broke login on the stand).

## Theme, placeholders, the right panel (2026-10-10)

- **The theme follows the time of day.** The stand profile has
  `window.autoDetectColorScheme: true`, so glass is light by day and dark
  at night. Anything that looks at brightness has to work both ways: the
  selected sidebar row is lighter than the background in the dark theme
  and darker in the light theme (`sidebar_selected_y` uses the offset from
  the base background). OCR anchors do not depend on the theme.
- **Labels drift without a package version change.** 3.23.23 stayed the
  same, and the folder picker placeholder became "Search repos, cloud
  environments…", and the model in the chip changed. Tesseract reads a
  grey placeholder unstably ("repos," → "re" + "5,"; "environments." /
  "environment:"). An anchor may have a spare word set, the `alt` key in
  `ANCHORS`. Comparison is a substring of 3 characters or more.
- **The right panel** shifts the chat left and breaks anchor zones.
  `close_right_panel` finds its edge on the shot and closes it with the
  toggle in the top right corner.
- **The selection may be a local draft** with no row in the profile (after
  `archive` or Discard an empty New Chat remains). `selected` then returns
  a uuid that is not in the agent list. That is not an error.
- **The worker key.** `workers` patches the installed `cursor-agent` so
  `--api-key` moves into `CURSOR_API_KEY`. The key is no longer in `ps`.
  Check with a count over `/proc/PID/cmdline`. Do not print the value.

## The move to 3.30

- **The Search Agents palette became "Search chats…"** (All/Chats/Files
  tabs). Ctrl+Alt+P is the same. `palette-open` recognizes both shapes.
  Search by bc-id works.
- **The Changes panel on the right opens after a repo folder is chosen,**
  not immediately after New Chat. `handoff` closes it a second time before
  checking the environment chip.
- **A new Cursor pulls a new agent CLI** (`Downloading Cursor Agent
  <ver>`). The extension's download timeout is 120 s. On a slow link
  (~170 MB at ~1 MB/s) it does not finish: `Activation failed:
  AbortError`, workers do not come up, and `ensure` keeps restarting
  Cursor. The fix: take the version from the extension log
  (`logs/*/window*/exthost/anysphere.cursor-agent-worker/`) and download
  it by hand with no timeout —
  `https://downloads.cursor.com/lab/<ver>/linux/x64/agent-cli-package.tar.gz`
  — then unpack `--strip-components=1` into
  `$PROFILE/User/globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions/<ver>/`
  (via `.tmp-…` and `mv`). Then `stand.sh workers`: it patches the
  launcher first (the key leaves argv), then opens the tabs. While doing
  this by hand, `stop` the timer. Do not `disable` it.

## park / ensure

`park` kills PIDs whose command line contains the stand profile plus a
worker start from there. An orchestrator whose worker-dir is
`~/.config/Cursor` is not a target, but a copy of the stand's
infra-worker on the same socket is: park cuts its tools (measured
park→up). Do not park yourself unless asked.

`ensure`: if the screen or Cursor is not whole, `up`; then `workers`
(open a tab for each folder `@ hostname`). If the workers are dead while
Cursor is alive, it restarts the GUI at most once in 30 minutes
(`var/last-restart`), without `hold`, and only when no agent is running
(`glass.sh busy`): a restart cuts that turn. `ensure` reads `busy` again
on a new shot immediately before the signal. A worker that comes up
resumes an agent with an unfinished turn (on 2026-10-07 that revived
"Greeting conversation"). After `workers`, check `busy`.

## Secrets

A worker command line contains `--api-key`. Cut it out of replies, git,
the skill, and chat screenshots. The launcher patch moves that flag into
`CURSOR_API_KEY` and drops it from argv. If `CURSOR_API_KEY` is already
set to a different value, the launcher exits and does not print either
value. A worker that is already running keeps its old argv until Cursor
starts it again. Sidebar shots contain session names. Do not put them in
the repo (`$PROFILE/var/shots/`). Glass login credentials do not go in git.
The login `xdg-open` log records the call, not the URL. The login Chrome
does not open a DevTools port.

## Proxy

An empty `CURSOR_STAND_PROXY` means `up` does not require a proxy, and
`cursor-proxy` starts Cursor with no `--proxy-server`. If it is set and
the host is localhost, `up` checks that the port is listening. The parser
is the URL parser: `user:pass@127.0.0.1` stays localhost. Doctor prints
the port, not the URL. When a proxy is set, the URL still has to sit in
Cursor's argv; that is the residual risk, and it is not printed. The port
number lives in `config/hosts/<host>.env`, not in the script. Do not
substitute someone else's port without `ss`.

`archive` refuses before any click when both `ARCHIVE_PROTECTED_IDS` and
`ARCHIVE_PROTECTED_NAMES` are empty. A session with `status=1` is refused
first. VNC stays on localhost. The password file is `$PROFILE/var/vnc.pass`,
mode `0600`, created when `up` starts x11vnc. The password is not printed
and not stored in git. An x11vnc that is already listening is left until
the port is free.

## Screenshot gates and the database

A click still needs the picture. A fact that is already in the stand
profile database is not refused because OCR cut a word. The inventory,
written for BL-070:

| gate | what the picture is for | fact already in the database |
|---|---|---|
| sidebar row before rename | the highlighted row is the session whose name is about to change | selected id equals the bc-id; the current name is `resolve` |
| sidebar row before archive | the highlighted row is the session about to be archived | selected id; name; `status` (a running turn is refused before the click) |
| Search Agents palette | the open palette shows this session before Return | the bc-id that was pasted; confirmation still needs the picture because the palette is not a database row |
| folder chip left of This Computer | which chip to click | no. The database does not say where the chip is drawn |
| Planning next moves | the turn has not finished, so convert waits | no. `status` can already be 1 while the words are still on screen; the words are the wait |
| composer-send field | where to click the input | the target bc-id and its folder. The field coordinates are only on the picture |
| MCP source toggle | whether that server's switch is on | `mcp.json` has the server definition. The on/off switch of the open Agents window is on the picture |
| Settings → Agents | the toggle and choice values | no database field is read for these. The command prints the picture and does not click |

`f33f2fd` already accepts a truncated sidebar token when at least half of the name word remains. Replacing the other gates is not part of this inventory.

## Doctor fields

Every `scripts/doctor.sh` run prints: host and user; the resolved script and its required commands; the display script and `CURSOR_STAND_X`; the binaries; whether a Cursor Agents window exists on the stand display (search only, the window is not moved); profile login as `да` or `нет` with no address; anchor lines from `doctor_anchor_lines` (package version, `ui-checked`, `CURSOR_STAND_UI_CALIBRATED`); whether the stand is busy; the proxy as a port number or "not set", never the URL; the count of workers started from the stand profile, with no command line; the owner's mouse as a location or `unavailable`.

Exit 0 means a click is allowed. Exit is not 0 when the last handoff line contains `ЗАБЛОКИРОВАН` or a required part is missing. A busy stand does not get `handoff --dry-run`. A mismatch between the calibrated major.minor and the package is a warning line, not a coordinate to type in chat.

## where to look

A successful handoff prints one block: bc-id, `https://cursor.com/agents/<bc-id>`, class `local-rc`, folder, worker, the requested name when there was one, the stand display, `vnc localhost` and `CURSOR_STAND_VNC`, the owner's mouse before and after, and that other tabs were not renamed. The VNC password, the proxy URL, and the login address are not in that block. x11vnc stays on localhost.

`scripts/glass.sh inventory` lists non-archived rows: id, name, folder, class (`local-rc`, `environment`, `private-incomplete`, `other`), working, worker. A selected uuid with no `cloudAgentRepository` row is `local-draft`. `discard --id` is only for that draft. A row that `resolve` can see is archive or convert, not Discard. Discard refuses when the word Stop is on the screen, when the id or name is protected, and when the Discard item is not in the sidebar menu. It does not click a neighbour and it does not use Archive All Below.

`mcp ready NAME --id` checks the open `local-rc` tab. The server must be in that folder's `mcp.json` or in the user `mcp.json`, and the MCPs panel must not say disabled. The tab then gets one composer message. Settings → Agents toggles are not clicked.
