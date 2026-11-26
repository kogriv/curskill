# What curskill can do

Russian: [capabilities.ru.md](capabilities.ru.md). English is the copy to follow.

This is the catalog. [SKILL.md](SKILL.md) is the order an agent follows on
the stand. [reference.md](reference.md) is refusals, anchors, and the
doctor contract. Paths below are from the skill root. `scripts/stand.sh`
resolves `automation/cursor-stand.sh`.

The stand is one X11 display, default `:105`, and one Cursor profile.
A new agent is a new tab, not a new X server. Success of a new Remote
Control session is a `local-rc` row: the requested folder on this disk
and a worker `@ this host`. A picture of the words "This Computer" is
not that row.

`park`, `ensure`, and `down` stop the stand's Cursor. On this stand that
also stops the worker of a chat that is running here.

## Stand commands

### doctor

`scripts/doctor.sh` prints the host check: script, commands, display,
binaries, whether the Agents window is up, login as yes or no, anchor
lines, whether the stand is busy, the proxy as a port or "not set", the
worker count, and the owner's mouse. Exit 0 means a click is allowed.
A busy stand does not get `handoff --dry-run`. A mismatch between
`CURSOR_STAND_UI_CALIBRATED` and the package is a warning, not a click
coordinate. The command does not print a login address, a proxy URL, or
a worker command line, and it does not start the display.

### pick-display

`scripts/pick-display.sh` and `scripts/stand.sh pick-display` print which
renderer `CURSOR_STAND_X` would use: NVIDIA Xorg, Xvfb, or a refusal.
`auto` takes the GPU only when the driver, the config, and passwordless
sudo are present. `xorg` refuses instead of hiding on Xvfb. AMD, Intel,
and Wayland are not implemented. The command does not start the X server.

### status

`scripts/stand.sh status` prints the stand display, the profile, whether
the screen and the Cursor Agents window are up, whether VNC is listening,
and the profile login line. It does not click. The login line is not
copied into a reply to a person.

### up

`scripts/stand.sh up` brings the stand up: the X server, the window
manager, Cursor Agents at `0,0` × `1920×1080`, and x11vnc on localhost.
There is no folder path in the arguments. A living `:105` is not started
a second time. Without the Agents window the command does not succeed.
It does not create a session.

### workers

`scripts/stand.sh workers` opens `local-rc` tabs on this machine whose
folder has no worker yet, so the worker can start. A tab whose turn is
already running is not switched. It does not create a new session and
does not start `agent worker`.

### ensure

`scripts/stand.sh ensure` is what the timer does: `up` when the stand is
not whole, then `workers`. Run it by hand only when a person asked. It
can stop the stand's Cursor when it believes the stand is idle. It is
not a way to reload MCP or to apply a launcher change.

### shot

`scripts/stand.sh shot` writes a PNG of the stand display under the
profile's `var/shots/`. It does not click. Shots that show a login
address, a proxy URL, or a VNC password are not committed.

### handoff

`scripts/stand.sh handoff -w /ABS/PROJECT -n name --then 'task'` opens a
new Agents tab on that folder, sends a short first message, waits until
that turn ends, converts the footer from This Computer to Self-Hosted
Worker, then sends the task. Success is the "where to look" block: the
bc-id, `https://cursor.com/agents/<bc-id>`, class `local-rc`, the folder,
the worker `@ this host`, the name when one was asked, the stand display,
VNC on localhost, the owner's mouse, and that other tabs were not
renamed. The VNC password, the proxy URL, and the login address are not
in that block.

`--no-convert` leaves a local chat for a later `convert`. `--dry-run`
walks the anchors and does not press Return. The folder is an absolute
existing directory. The slash `/remote-control` is not used: on the
builds this stand measured it starts an Environment session. `agent
worker start` does not open this tab. Measured 2026-11-26: that command
exited unauthenticated and created no stand-profile tab.

### convert

`scripts/stand.sh convert --id <uuid|bc-|name>` performs the same footer
conversion on a tab that is already open. `--dry-run` does not press the
menu. It does not open New agent to find a closed tab. A final class of
`environment` is a stop, not a second round of the same clicks.

### rename

`scripts/stand.sh rename --id bc-… name` renames that sidebar row.
`--from` and `--current` select the row by the visible name or by the
selected tab. The click happens only when the highlighted row is that
session. Other tabs are not renamed.

### focus

`scripts/stand.sh focus --id bc-…` selects that session's tab. It does
not create a session and does not send text.

### archive

`scripts/stand.sh archive --id bc-…` archives one sidebar row that
`resolve` can see. A turn with `status=1` is refused. An empty
protection list is refused before the click. The menu item is Archive,
not Archive All Below. A protected id or name is refused.

### discard

`scripts/stand.sh discard --id <uuid>` removes one local draft that has
no row in the profile database. A row that `resolve` can see is archive
or convert, not Discard. The command refuses when the word Stop is on
the screen, when the id or name is protected, and when the right click
would land on a different tab. If the menu shows Archive because the
draft already replied, that one Archive item is used. Archive All Below
is not used. A missing menu item is a refusal, and a neighbouring point
is not clicked.

### composer-send

`scripts/stand.sh composer-send --id bc-… 'text'` pastes into that tab's
input and presses Return, then waits until that tab's turn has started.
The input is found on the shot. A Move agent dialog cancels the send.
Another tab is not focused to make the click easier. `agent resume` is
not a substitute.

### wait-worker

`scripts/stand.sh wait-worker /ABS/PROJECT` waits until the private
worker for that folder is running. The command line of the worker is
not printed.

### mcp

Customize → MCPs on the stand window. The Agents window reads a project
`.cursor/mcp.json`. A `local-rc` tab's worker reads
`~/.cursor/mcp.json` at start and does not read the project file. A
worker that is already running does not reread the user file. A new tab
of the same folder uses that same worker. Settings → Agents toggles are
not clicked. `agent mcp` is not changed.

#### list

`scripts/stand.sh mcp list` prints the servers visible on the MCPs
panel and a status of `enabled`, `disabled`, or `error`. It does not
toggle them.

#### find

`scripts/stand.sh mcp find NAME` prints that server's row, or exits 1
when the panel does not show it. A line here is not proof that a
`local-rc` tab can call the server.

#### enable

`scripts/stand.sh mcp enable NAME` turns that server's source toggle on.
It is idempotent when the toggle is already on. It does not fill the
New MCP Server form.

#### disable

`scripts/stand.sh mcp disable NAME` turns that source toggle off.

#### add

`scripts/stand.sh mcp add -w /ABS -n NAME --command /path` writes the
project file for the Agents window and then enables the toggle.
`scripts/stand.sh mcp add --user -n NAME --command /path` writes the
user file, which is the file a new worker will prewarm. Secrets are not
passed on argv. The project file alone does not make the tab see the
server.

#### ready

`scripts/stand.sh mcp ready NAME --id bc-…` checks one open `local-rc`
tab. The name must be in the user `~/.cursor/mcp.json`, and this
folder's worker cache must already contain it. The panel must not say
disabled. The tab then gets one composer message. Success is the tool's
token, or the reply `MCP-SEEN`. `MCP-MISSING` inside the prompt bubble
does not count. A project file alone is refused before the message.

### settings

`scripts/stand.sh settings agents` opens Settings → Agents, scrolls, and
prints the required rows: Remote Control, self-hosted workers, the queue
of new messages, Run Mode, Read Access, delete protection, protection of
files outside the folder, Web Search, waiting on MCP, and further down
Computer Use and Legacy Terminal. It switches nothing. It does not click
Cloud Agents, Docs, Unregister All, Log Out, Manage Environment, or
Build on App.

### park

`scripts/stand.sh park` stops the stand's Cursor and its workers. The X
server and VNC stay up. It does not stop the owner's desktop Cursor.
On a stand whose worker is this chat, the turn stops with the process.

### down

`scripts/stand.sh down` does `park` and then stops x11vnc for the stand
display. The X server stays up.

### down-display

`scripts/stand.sh down-display` stops the stand's X server, and only that
display. It refuses while the stand's Cursor is still running. It does
not stop an X server on the owner's display.

## Reading the profile

`scripts/glass.sh` reads the stand profile. These commands do not click.

### inventory

`scripts/glass.sh inventory` lists non-archived rows: id, name, folder,
class (`local-rc`, `environment`, `private-incomplete`, `other`), whether
a turn is running, and the worker. A selected uuid with no database row
is `local-draft`. `agent ls` is not the source.

### selected

`scripts/glass.sh selected` prints the selected session id.

### show

`scripts/glass.sh show bc-…` prints class, folder, worker, and archive
state for that id.

### newest

`scripts/glass.sh newest /ABS/PROJECT [since_ms]` prints the newest
`local-rc` row for that folder. An `environment` row is not a match.

### created-since

`scripts/glass.sh created-since <epoch_ms>` lists sessions created after
that time.

### handoff-ok

`scripts/glass.sh handoff-ok /ABS/PROJECT [since_ms [uuid]]` exits 0 when
that folder's row is `local-rc` with a worker on this host. A row that
is still `environment` while convert is waiting is not a failure by
itself.

### mine

`scripts/glass.sh mine "$(hostname)"` lists this machine's `local-rc`
and local rows, with a working column.

### busy

`scripts/glass.sh busy "$(hostname)"` lists rows whose turn is running,
plus a selected local draft that has no database row.

## What these commands do not do

They do not wrap the terminal `agent`: print mode, persist, resume,
worktree, sandbox, models, rules, or plugins. They do not start `agent
worker` and they do not run a worker pool. They do not keep a second MCP
approval list for the CLI. They do not create a Cloud Agent. They do not
open files in the editor (`--goto`, `--diff`, `--merge`). They do not
edit Settings → Agents. They do not open VNC beyond localhost.

Other `glass_agents.py` verbs (`anchor`, `reply-has`, `mcp-list`, and
the rest) are how the stand script reads a shot. They are not a second
way to drive the window from chat.
