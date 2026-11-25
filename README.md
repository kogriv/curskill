# curskill

Отдельный X11-экран для Cursor Agents Window и Remote Control: свой
`DISPLAY`, свой профиль, мышь стола владельца не трогает.

Скилл называется `curskill`. Команда стенда — `automation/cursor-stand.sh`.
Профиль по умолчанию — `~/.local/share/cursor-stand`.

## Где работает

Linux и X11. Экран — NVIDIA Xorg на отдельном `DISPLAY` или Xvfb, если
карты нет. Выбор: `CURSOR_STAND_X=auto|xorg|xvfb`.

Не обещает и не проверялось: AMD, Intel iGPU, Wayland, Windows, macOS.

## Установка скилла

Из корня клона:

```bash
./install/install.sh
```

Скрипт вешает симлинки:

- `~/.cursor/skills/curskill` → `skill/`
- `~/.claude/skills/curskill` → `skill/`

и, если файла ещё нет, копирует `config/hosts/example.env.example` в
`config/hosts/$(hostname).env`. Этот `.env` в git не входит. Туда пишутся
порт прокси, пути и список сессий, которые `archive` не трогает.

`install.sh` стенд не поднимает и таймер systemd не переключает.

Без файла хоста прокси нет, список `archive` пуст, экран —
`automation/display/stand-display.sh`.

## Лицензия

[MIT](LICENSE).
