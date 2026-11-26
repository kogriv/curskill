# curskill

Russian: [README.ru.md](README.ru.md). English is the copy to follow.

What the skill can do, command by command: [capabilities.md](skill/capabilities.md).

## Docs

| | English | Russian |
|---|---|---|
| Diagrams: two displays, the GPU switch, handoff | [How it is put together](skill/SKILL.md#layout) | [Как это устроено](skill/SKILL.ru.md#layout) |
| GPU, and why you can skip it | [What draws the window](skill/display.md#gpu) | [Чем рисовать](skill/display.ru.md#gpu) |
| Why a second X server | [display.md](skill/display.md) | [display.ru.md](skill/display.ru.md) |
| Install, packages, host file | [SETUP.md](SETUP.md) | [SETUP.ru.md](SETUP.ru.md) |
| What the skill can do | [capabilities.md](skill/capabilities.md) | [capabilities.ru.md](skill/capabilities.ru.md) |
| What the agent does on the stand | [SKILL.md](skill/SKILL.md) | [SKILL.ru.md](skill/SKILL.ru.md) |
| Failures, anchors, sqlite | [reference.md](skill/reference.md) | [reference.ru.md](skill/reference.ru.md) |
| One stand per machine | [hosts.md](skill/hosts.md) | [hosts.ru.md](skill/hosts.ru.md) |
| Script index | [automation/README.md](automation/README.md) | [automation/README.ru.md](automation/README.ru.md) |
| Gaps, design, backlog, roadmap | [skill/docs](skill/docs/README.md) | same notes, Russian |

A separate X11 display for Cursor Agents Window and Remote Control.
Its own `DISPLAY`, its own profile. It does not touch the mouse on the
owner's desktop.

The skill is named `curskill`. The stand command is
`automation/cursor-stand.sh`. The default profile is
`~/.local/share/cursor-stand`.

## Why

Cursor can run an agent in three ways, and they are not the same session.

- Cloud Agents: the model and the tools run in Cursor's cloud.
- The terminal `agent` CLI: a process on this machine, with its own chat
  store. It is not an Agents Window tab.
- Agents Window with Remote Control: the chat is the desktop app, and the
  tools run here as a private self-hosted worker.

There is no API for "open a new Agents Window tab and attach Remote
Control". The slash `/remote-control` does not do that. On the builds this
stand was measured against, that slash starts an Environment session (a
cloud workspace at `/workspace`), not a worker on this computer.

Clicking the owner's real desktop is the wrong tool for the same job.
Those clicks move the owner's mouse and take the keyboard.

`automation/cursor-stand.sh` is the repeatable way. It raises a second X11
display the owner is not sitting at, opens Cursor Agents there at a fixed
size, and clicks only that display. Anchors come from OCR of the picture
on that display, not from coordinates typed in chat. Text is pasted from
the clipboard, because `xdotool type` is swallowed by the input method.
Success is a row in the stand's own profile database: class `local-rc`,
the folder you asked for on this disk, and a worker named `@ this
hostname`. A screenshot that says "This Computer" is not success.

One machine has one stand. Another agent is another tab, not another X
server. A second Xorg on a GPU someone is watching can blink their
monitor, so the stand is not brought up until a person says to.

The GPU is optional. The stand has to paint a Cursor window somewhere.
Xvfb paints it on the CPU and is a complete stand: same clicks, same
check, no root. NVIDIA Xorg paints the same window on the card, so a
stand that stays up does not spend that CPU. Skip the GPU when there is
no NVIDIA, when sudo cannot start Xorg, or when a person is at that
monitor. AMD and Intel are not implemented. The diagrams are in
[How it is put together](skill/SKILL.md#layout). The renderer switch is
in [What draws the window](skill/display.md#gpu).

## Where it runs

Linux and X11. `CURSOR_STAND_X=xvfb` is software rendering.
`CURSOR_STAND_X=xorg` is NVIDIA or a refusal. `auto`, the default, uses
the GPU only when the driver, Xorg, and passwordless sudo are all
present, and otherwise says so and uses Xvfb.

Not promised and not tested: AMD, Intel iGPU, Wayland, Windows, macOS.

What must already be installed, and what to write in the host file:
[SETUP.md](SETUP.md). `skill/scripts/setup.sh` checks commands and does
not install packages. A from-scratch install is exercised in a container,
not on this host: `docker/test-fresh-install.sh`.

## Install the skill

From the clone root:

```bash
./install/install.sh
```

The script creates symlinks:

- `~/.cursor/skills/curskill` → `skill/`
- `~/.claude/skills/curskill` → `skill/`

and, if the file is not there yet, copies
`config/hosts/example.env.example` to `config/hosts/$(hostname).env`.
That `.env` is not in git. It holds the proxy, paths, and the sessions
`archive` must leave alone.

`install.sh` does not start the stand and does not switch the systemd
timer.

With no host file there is no proxy, the `archive` list is empty, and the
screen is `automation/display/stand-display.sh`.

## License

[MIT](LICENSE).
