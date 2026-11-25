# Installing curskill

Russian: [SETUP.ru.md](SETUP.ru.md). English is the copy to follow.

A person and an agent both read this file. It is about the first machine:
what must already be installed, what is copied from the repository, and
which lines to write in the host file. This file does not start the stand.

Order:

1. Check the machine (`skill/scripts/setup.sh`). Show the person what is missing.
2. Install packages only after the person agrees.
3. `./install/install.sh` — skill symlinks and an empty host file.
4. Fill `config/hosts/$(hostname).env` from the comments in that file.
5. `cursor-proxy`, the Xorg wrapper, and the timer are a separate yes.
6. Set `CURSKILL_SETUP_DONE=1`.
7. `up` and the timer only after the person says to bring the stand up.

Until `CURSKILL_SETUP_DONE` is `1`, `doctor` does not click the glass UI.

## What must already be installed

Linux and X11. This stand does not draw on Wayland, Windows, or macOS.
AMD and Intel were not tested as the stand's GPU.

The person installs the Cursor package for Linux and signs in.
The agent does not copy `state.vscdb` and does not move a login.

Commands without which `doctor` fails:

| Command | Debian/Ubuntu package | Why |
|---|---|---|
| `xdotool` | `xdotool` | clicks on the stand's screen |
| `xclip` | `xclip` | paste text; `xdotool type` does not work here |
| `python3` | `python3` | read sessions |
| `import` or `scrot` | `imagemagick` or `scrot` | a screenshot; one of the two is enough |
| Pillow | `python3-pil` | read the screenshot |
| `tesseract` | `tesseract-ocr` and `tesseract-ocr-eng` | button anchors |
| `Xorg` | `xserver-xorg-core` | the binary is required even when the screen will be Xvfb |
| `xdpyinfo` | `x11-utils` | is the display alive |

`skill/scripts/setup.sh` prints which of these are missing and does not
install packages. The package names above are Debian and Ubuntu. Another
distribution needs the same commands.

The rest is a fork, not one required set:

| Command or file | If it is missing |
|---|---|
| `xrandr` (`x11-xserver-utils`) | an empty screen gets no monitor |
| `Xvfb` (`xvfb`) | no fallback off the GPU |
| NVIDIA driver and passwordless sudo | `auto` raises Xvfb, not the GPU |
| `openbox`, `x11vnc` | `up` may not finish the window and the viewer |
| tesseract language `rus` | pass the session name with `--id` |
| a mouse on `:1` | desktop isolation cannot be measured; handoff is still allowed |
| a proxy | empty `CURSOR_STAND_PROXY` means connect directly |
| a systemd timer | the stand comes up only by hand, with `up` |

## Three doors

### 1. The skill

From the clone root:

```bash
./install/install.sh
```

This creates `~/.cursor/skills/curskill` and
`~/.claude/skills/curskill`. If there is no host file yet, it copies
`config/hosts/example.env.example` to `config/hosts/$(hostname).env`.
That file is not in git.

`install.sh` does not install packages, does not write sudoers, does not
enable the timer, and does not start the screen.

### 2. The host file

`automation/cursor-stand.sh` reads it. An empty variable means the
script default. The agent does not fill a value by guessing.

The agent writes these after measuring:

- `CURSOR_STAND_DISPLAY` — `:105` when `xdpyinfo -display :105` is quiet
  (the display is free). If it is taken, ask for another number.
- `CURSOR_STAND_VNC` — `5916` when the port is free (`ss`). Otherwise ask.
- `CURSOR_STAND_X` — empty (`auto`) when NVIDIA, `Xorg`, and passwordless
  sudo are all present. Otherwise `xvfb`, and say so.

Only the person answers:

- `CURSOR_STAND_PROXY` — a URL, or empty. Do not invent a port.
- `CURSOR_STAND_SOCKS`, and any addition to `CURSOR_STAND_NO_PROXY` —
  only when a proxy already exists.
- `ARCHIVE_PROTECTED_IDS` and `ARCHIVE_PROTECTED_NAMES` — sessions
  `archive` must not touch. While these are empty, do not run `archive`:
  the list protects nobody.
- whether a timer is wanted.

Leave empty:

- `CURSOR_STAND_PROFILE` — becomes `~/.local/share/cursor-stand`.
- `CURSOR_STAND_DISPLAY_SH` — the screen script
  `automation/display/stand-display.sh`.
- `CURSKILL_XORG_CONF` — the config next to that script. Its BusID is a placeholder.
- `CURSOR_STAND_WORKSPACE` — each chat gets a folder with `-w`, not a default.
- `CURSOR_STAND_ORIG_DISPLAY` — `:1`, mouse measurement only. Do not click there.

Do not write passwords, a Cursor login, or worker keys into the file.

Set `CURSKILL_SETUP_DONE=1` last, when the packages are present and the
person has answered about the proxy, the monitor, and the timer.

### 3. Root and the timer

These are not apt packages. Copy them after a separate yes.

- `automation/cursor-proxy` → `/usr/local/bin/cursor-proxy`.
  Without it `up` does not start Cursor. That is not a reason to invent a proxy.
- `automation/curskill-xorg` → `/usr/local/sbin/curskill-xorg`,
  only for an NVIDIA screen. The person adds the sudoers line.
  The wrapper allows only `:105`. Another number is one line `:N` in
  `/etc/cursor-stand/display`.
- `automation/systemd/cursor-stand.service` and `cursor-stand.timer` go
  to `~/.config/systemd/user/`. In `ExecStart`, replace `/ABS/CLONE` with
  the clone directory. Enable the timer only if the person asked for the
  stand to come up by itself. While someone is at the monitor of this GPU,
  do not `up`: a second Xorg can blink that desktop.

## Check

```bash
skill/scripts/setup.sh
skill/scripts/doctor.sh
```

`setup.sh` changes nothing. Until `CURSKILL_SETUP_DONE=1`, `doctor.sh`
does not click. After that, on a free living stand, it clicks
`handoff --dry-run`: no Return and no text.

## Check from scratch

On a machine where the skill is already installed, a container walks the
install path. From the clone root:

```bash
docker/test-fresh-install.sh
```

It builds a local image `curskill-install:bookworm` (the packages from
this file, without Cursor and without `cursor-proxy`) and runs a copy of
the repository inside the container. The host file is not copied back,
and the screen is not started.

Two steps:

1. Empty Debian. `setup.sh` fails and names the missing command.
2. The image with packages. `setup.sh` passes, `install.sh` creates the
   symlinks and copies an empty host file. `doctor` does not click before
   `CURSKILL_SETUP_DONE=1`, and does not click after it while the screen
   is down.

The image is not published. A Cursor login, the timer, and Xorg on a GPU
are outside this check.
