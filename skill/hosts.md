# Хосты

Первая машина: [SETUP.md](../SETUP.md) и `scripts/setup.sh`.
Пока `CURSKILL_SETUP_DONE` не равен `1`, `doctor` по glass не кликает.

Один стенд на машину. Порты, профиль, экран и список сессий, которые
`archive` не трогает, живут в `config/hosts/$(hostname).env`.
Пустой образец — `config/hosts/example.env.example`. Сам `.env` в gitignore.
В скрипт эти значения не зашиты.

`install/install.sh` вешает симлинки скилла `curskill` и не подменяет
таймер. `doctor.sh` на незнакомом хосте обязателен. На свободном стенде
он кликает `handoff --dry-run` без текста и без Return. Занятый стенд
он не кликает. Логин Cursor в репозиторий не писать.

Экран по умолчанию — `automation/display/stand-display.sh`.
Дисплей не `:105` для `curskill-xorg` задаётся одной строкой `:N` в
`/etc/cursor-stand/display` (файл root). Без файла обёртка пускает только `:105`.
