# Hosts

Russian: [hosts.ru.md](hosts.ru.md). English is the copy to follow.

A first machine: [SETUP.md](../SETUP.md) and `scripts/setup.sh`.
Until `CURSKILL_SETUP_DONE` is `1`, `doctor` does not click the glass UI.

One stand per machine. Ports, the profile, the screen, and the sessions
`archive` must not touch live in `config/hosts/$(hostname).env`.
The empty sample is `config/hosts/example.env.example`. The `.env` itself
is gitignored. Those values are not hardcoded in the script.

`install/install.sh` symlinks the `curskill` skill and does not replace
the timer. `doctor.sh` is required on an unfamiliar host. On a free stand
it clicks `handoff --dry-run` with no text and no Return. It does not
click a busy stand. Do not write a Cursor login into the repository.

The default screen is `automation/display/stand-display.sh`.
A display other than `:105` for `curskill-xorg` is one line `:N` in
`/etc/cursor-stand/display` (a root file). With no file, the wrapper
allows only `:105`.
