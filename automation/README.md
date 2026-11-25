# Stand commands

Russian: [README.ru.md](README.ru.md). English is the copy to follow.

The canon is [`cursor-stand.sh`](./cursor-stand.sh).
The default screen is [`display/stand-display.sh`](./display/stand-display.sh).
The proxy sample is [`settings.proxy.json`](./settings.proxy.json): port `0`.
Do not copy it into a profile. The live proxy is `CURSOR_STAND_PROXY`
in `config/hosts/<hostname>.env`.

The Xorg wrapper is [`curskill-xorg`](./curskill-xorg). The display it
allows is read from `/etc/cursor-stand/display`. Otherwise it allows only
`:105`.
