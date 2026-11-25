# Команды стенда

Английский — источник правды: [README.md](README.md).

Канон — [`cursor-stand.sh`](./cursor-stand.sh).
Экран по умолчанию — [`display/stand-display.sh`](./display/stand-display.sh).
Образец прокси — [`settings.proxy.json`](./settings.proxy.json): порт `0`,
в профиль его не класть. Живой прокси задаёт `CURSOR_STAND_PROXY`
в `config/hosts/<hostname>.env`.

Обёртка Xorg — [`curskill-xorg`](./curskill-xorg). Разрешённый дисплей
читает из `/etc/cursor-stand/display`, иначе пускает только `:105`.
