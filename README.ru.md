# curskill

Английский — источник правды: [README.md](README.md).

## Документы

| | По-русски | English |
|---|---|---|
| Схемы: два экрана, переключатель GPU, handoff | [Как это устроено](skill/SKILL.ru.md#layout) | [How it is put together](skill/SKILL.md#layout) |
| Видеокарта и почему её можно не брать | [Чем рисовать](skill/display.ru.md#gpu) | [What draws the window](skill/display.md#gpu) |
| Зачем второй X-сервер | [display.ru.md](skill/display.ru.md) | [display.md](skill/display.md) |
| Установка, пакеты, файл хоста | [SETUP.ru.md](SETUP.ru.md) | [SETUP.md](SETUP.md) |
| Команды, которые выполняет агент | [SKILL.ru.md](skill/SKILL.ru.md) | [SKILL.md](skill/SKILL.md) |
| Отказы, якоря, sqlite | [reference.ru.md](skill/reference.ru.md) | [reference.md](skill/reference.md) |
| Один стенд на машину | [hosts.ru.md](skill/hosts.ru.md) | [hosts.md](skill/hosts.md) |
| Указатель скриптов | [automation/README.ru.md](automation/README.ru.md) | [automation/README.md](automation/README.md) |
| Разрывы, решения, бэклог | [skill/docs](skill/docs/README.md) | те же заметки |

Отдельный X11-экран для Cursor Agents Window и Remote Control: свой
`DISPLAY`, свой профиль, мышь стола владельца не трогает.

## Зачем

У Cursor три разных способа запустить агента, и это не одна сессия.

- Cloud Agents: модель и инструменты в облаке Cursor.
- Терминальный CLI `agent`: процесс на этой машине со своим хранилищем чатов. Это не вкладка Agents Window.
- Agents Window с Remote Control: чат — это десктопное приложение, а инструменты работают здесь как свой self-hosted worker.

API «открой новую вкладку Agents Window и включи Remote Control» нет. Слэш `/remote-control` этого не делает. На сборках, где стенд измеряли, слэш поднимает сессию Environment (облачный workspace `/workspace`), а не воркер на этом компьютере.

Кликать настоящий стол владельца — не тот инструмент. Эти клики двигают его мышь и забирают клавиатуру.

`automation/cursor-stand.sh` делает то же самое повторяемо. Он поднимает второй X11, за которым владелец не сидит, открывает там Cursor Agents в известном размере и кликает только этот экран. Якоря берутся из OCR снимка, не из координат, сказанных в чате. Текст вставляется из буфера: `xdotool type` съедает метод ввода. Успех — строка в базе профиля стенда: класс `local-rc`, запрошенная папка на этом диске и воркер `@ этот хост`. Снимок с надписью «This Computer» успехом не считается.

Один компьютер — один стенд. Новый агент — новая вкладка, не новый X-сервер. Второй Xorg на видеокарте, за монитором которой кто-то сидит, может моргнуть стол, поэтому стенд не поднимают, пока человек сам не скажет.

Видеокарта необязательна. Стенду нужно где-то нарисовать окно Cursor. Xvfb рисует его процессором и этого достаточно: те же клики, та же проверка, root не нужен. NVIDIA Xorg рисует то же окно на карте, и постоянно включённый стенд не тратит на это процессор. Карту не трогают, если NVIDIA нет, если Xorg нельзя запустить без пароля, или если у этого монитора кто-то сидит. AMD и Intel не сделаны. Схемы — [Как это устроено](skill/SKILL.ru.md#layout). Переключатель рендера — [Чем рисовать](skill/display.ru.md#gpu).

Скилл называется `curskill`. Команда стенда — `automation/cursor-stand.sh`.
Профиль по умолчанию — `~/.local/share/cursor-stand`.

## Где работает

Linux и X11. `CURSOR_STAND_X=xvfb` — программный экран.
`CURSOR_STAND_X=xorg` — NVIDIA или отказ. `auto`, это дефолт, берёт
карту только когда есть драйвер, Xorg и passwordless sudo, иначе
говорит об этом и берёт Xvfb.

Не обещает и не проверялось: AMD, Intel iGPU, Wayland, Windows, macOS.

Как ставить на новую машину, что уже должно быть в системе и что писать
в файл хоста: [SETUP.ru.md](SETUP.ru.md). Английский текст — [SETUP.md](SETUP.md). `skill/scripts/setup.sh` проверяет
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
