# curskill

Отдельный X11-экран для Cursor Agents Window и Remote Control: свой
`DISPLAY`, свой профиль, мышь стола владельца не трогает.

Скилл называется `curskill`. Команда стенда — `automation/cursor-stand.sh`.
Профиль по умолчанию — `~/.local/share/cursor-stand`.

## Где работает

Linux и X11. Экран — NVIDIA Xorg на отдельном `DISPLAY` или Xvfb, если
карты нет. Выбор: `CURSOR_STAND_X=auto|xorg|xvfb`.

Не обещает и не проверялось: AMD, Intel iGPU, Wayland, Windows, macOS.

Как ставить на новую машину, что уже должно быть в системе и что писать
в файл хоста: [SETUP.md](SETUP.md). `skill/scripts/setup.sh` проверяет
команды и сам пакеты не ставит. Установку с пустой системы гоняет
`docker/test-fresh-install.sh`: контейнер, не этот хост.

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
