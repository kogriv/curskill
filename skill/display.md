# The Cursor stand's screen

Russian: [display.ru.md](display.ru.md). English is the copy to follow.

How X is started: `automation/display/stand-display.sh`.
This text is so an agent does not mix up the owner's desktop, the GPU, and VNC.

## Why a separate X server

Computer use on `:1` takes the owner's focus and input. The stand is a
second X11 server with one window, "Cursor Agents". The person looks at
their desktop or a phone. The agent clicks only `$CURSOR_STAND_DISPLAY`
(default `:105`).

The stand is not:

- a Cursor window pushed into a corner of the owner's desktop;
- Xvfb "by default, so we do not touch the GPU";
- Wayland, weston, or cage;
- a second GPU server "per session".

New agents are tabs of the **same** glass on the **same** `:105`.

## Where the window sits

After `up`, and before handoff, the script:

1. finds the window named `Cursor Agents` on `$DISP`;
2. `windowactivate`, `windowmove 0 0`, `windowsize 1920 1080`.

`handoff`, `composer-send`, and the slash click are calibrated to that
geometry and to Cursor 3.21. If glass is 1280×800 and not at the origin
(that happened after park→up without normalizing), clicks miss. The
script normalizes the window. Do not pick a size by hand. A new Cursor
major (measured on 3.23.23: the Environment picker) is not a reason to
tune coordinates. See [reference.md](reference.md).

Viewing: `x11vnc -display :105 -rfbport 5916 -localhost -forever -shared
-nopw`. The port does not listen outside the machine. Do not put a VNC
password in git.

The script does not move the owner's desktop. The `:1` mouse before and
after an operation must match, or the status is `unavailable` (that
machine has no `:1` mouse). A move while `unavailable` is not checked.
A move while the mouse is alive means isolation is broken, unless the
owner at the desk moved it.

<a id="gpu"></a>

## What draws it: GPU Xorg or Xvfb

The GPU is optional. Both paths paint one Cursor Agents window at
1920×1080, and handoff does not care which one it was.

Xvfb paints that window on the CPU (llvmpipe / SwiftShader), about 0.6 of
a core while the window stays up. No root, and it never opens a second
Xorg on a card a person is watching. That is enough for a real session.
NVIDIA Xorg paints the same window on the card, so a stand that is left
up (the timer brings it back) does not keep paying that CPU. Take the GPU
when the card is NVIDIA, Xorg starts without a password, and nobody is at
that monitor. Otherwise stay on Xvfb. AMD and Intel are not implemented.

`CURSOR_STAND_X` is `auto`, `xorg`, or `xvfb`. The default is `auto`.
This is the current scheme. The skill does not ask in chat: leave
`auto`, or the person explicitly asks for `xorg` or `xvfb`. Before `up`:

```bash
scripts/pick-display.sh
```

### `auto` (default)

`stand_pick_xserver` picks **xorg-nvidia** when all of these are true:

- the file `$CURSOR_STAND_NVIDIA_DRV` (default
  `/usr/lib/x86_64-linux-gnu/nvidia/xorg/nvidia_drv.so`);
- the xorg config next to the screen script (`xorg-nvidia-headless.conf`);
- the `Xorg` binary;
- passwordless root: `sudo -n true`, or NOPASSWD on
  `/usr/local/sbin/curskill-xorg` (the wrapper sets BusID from `lspci`).

Otherwise it prints a warning and returns `xvfb`. There is no silent
fallback. That is on purpose: SwiftShader burns a core without saying so.

### `xorg`

The same checks. Any gap is an **exit**, not Xvfb. Use this when the GPU
is required (a measurement, or the person said "the card only").

### `xvfb`

Straight to `Xvfb :105 -screen 0 1920x1080x24`. Root is not required.
Electron uses software rendering. This is a full stand, including one
left up. On a machine with a free NVIDIA card the GPU path is how you
avoid the CPU cost. It is not required.

There is no AMD branch, no Intel branch, no CUDA branch, no "second
monitor" branch. There is no "a window on `:1` if the GPU is busy".

## GPU Xorg config

`AutoAddGPU off`, `AutoAddDevices off`, `DontVTSwitch`, a virtual
1920×1080, `UseDisplayDevice None`, `AllowEmptyInitialConfiguration`.
Without that, a second Xorg takes the keyboard into the stand window
through udev.

The BusID in the repository is the placeholder `PCI:0:0:0`. The
`curskill-xorg` wrapper rewrites it from `lspci` before start. Do not
write someone else's slot into the config. `up` does not recreate a
`:105` that is already alive.

Stop by the PID from `/tmp/.X<N>-lock` or from state, and only that
`$disp`. Never `pkill Xorg`: the owner's desktop `:1` may be on the same
card.

When `:105` is already alive, `up` does not start a second server. It
only adopts the live one.

## Display number

Calibration is pinned to `:105` and VNC `5916`. Another number only if
that one is taken, and then the anchors have to be measured again.

## Env that touches the screen

`CURSOR_STAND_DISPLAY`, `CURSOR_STAND_VNC`, `CURSOR_STAND_ORIG_DISPLAY`,
`CURSOR_STAND_DISPLAY_SH`, `CURSOR_STAND_X`, `CURSOR_STAND_NVIDIA_DRV`,
`CURSKILL_XORG`.

`unset WAYLAND_DISPLAY`; `GDK_BACKEND=x11`, `QT_QPA_PLATFORM=xcb`,
IME `xim` (otherwise IBus swallows `xdotool type`, which is why typing
is forbidden).
