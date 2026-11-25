# Профили машин

Английский — источник правды: [README.md](README.md).
Порядок и требования к системе — [SETUP.ru.md](../../SETUP.ru.md).
Скрипт читает `config/hosts/$(hostname).env`, если нет `CURSOR_STAND_CONFIG`.
Живой `.env` в git не входит. Логин, порты, пути и список сессий, которые
`archive` не трогает, пишутся только туда.

Образец пустой: `example.env.example`. `install/install.sh` копирует его в
`.env`, только когда своего файла ещё нет и нет `$(hostname).env.example`.
Таймер стенда и бинари в `/usr/local` он не меняет.

Пустой `CURSOR_STAND_DISPLAY_SH` — экран из `automation/display/stand-display.sh`.
Дисплей не `:105` для обёртки `curskill-xorg` — одна строка `:N` в
`/etc/cursor-stand/display`. Без файла обёртка пускает только `:105`.

Стол владельца не кликать. Второй Xorg на видеокарте может моргнуть
физический экран — не делать `up`, если у монитора человек. Живой экран
`up` не пересоздаёт.
