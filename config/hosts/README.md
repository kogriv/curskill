# Machine profiles

Russian: [README.ru.md](README.ru.md). English is the copy to follow.
Install order and system requirements: [SETUP.md](../../SETUP.md).

The script reads `config/hosts/$(hostname).env` unless `CURSOR_STAND_CONFIG`
is set. The live `.env` is not in git. A login, ports, paths, and the
sessions `archive` must not touch are written only there.

The empty sample is `example.env.example`. `install/install.sh` copies it
to `.env` only when that file does not exist yet and there is no
`$(hostname).env.example`. It does not change the stand timer or the
binaries in `/usr/local`.

An empty `CURSOR_STAND_DISPLAY_SH` means the screen script
`automation/display/stand-display.sh`. A display other than `:105` for
the `curskill-xorg` wrapper is one line `:N` in
`/etc/cursor-stand/display`. With no file, the wrapper allows only `:105`.

Do not click the owner's desktop. A second Xorg on the GPU can blink the
physical screen. Do not `up` while a person is at that monitor. `up` does
not recreate a screen that is already alive.
