# Отказы, sqlite, калибровка

Читать при сбое. Координаты — снимок скрипта, не второй источник правды:
менять в `cursor-stand.sh`, не «подкрутить xdotool в чате».

## Три механизма

| | мозг | тулы | как плодить |
|---|---|---|---|
| Cloud Agents | облако | чужая VM | API / MCP `cursor-cloud` |
| CLI `agent` | терминал | этот хост | `agent`, `store.db` |
| Agents Window + RC | облако | private worker этой машины | glass / этот стенд |

`/rename` CLI ≠ Rename сайдбара glass. CLI history ≠ resume в glass.

## sqlite

Профиль стенда: `$CURSOR_STAND_PROFILE/User/globalStorage/state.vscdb`
(дефолт `$XDG_DATA_HOME/cursor-stand` или `~/.local/share/cursor-stand`).
`glass_agents.py` читает `CURSOR_STAND_PROFILE`.

```bash
scripts/glass.sh selected          # selectedAgent, lastRealAgent
scripts/glass.sh resolve --id bc-…
scripts/glass.sh show bc-…         # class + поля пикера
scripts/glass.sh created-since <epoch_ms>
scripts/glass.sh handoff-ok /ABS/WS [since_ms [uuid]]   # с uuid — эта сессия; без него новейшая с since
scripts/glass.sh newest /ABS/WS [since_ms]      # только class=local-rc
scripts/glass.sh mine "$(hostname)"  # id name ws kind working; local-rc + local
scripts/glass.sh busy "$(hostname)"  # работающие; + локальный selected без записи
scripts/glass.sh convert-ok UUID /ABS/WS  # 0 local-rc папки; 2 ещё environment
scripts/glass.sh overlay-scan SHOT   # expensive-dismiss / move-working (код 0/3/1)
```

Ключи: `cloudAgentRepository.agents*`, `cursor/glass.selectedAgent`,
`cursorAuth/cachedEmail`. Писать в vscdb руками нельзя.

`glass_agents.py classify`: `local-rc` | `environment` | `private-incomplete`
| `other`.

| class | как узнаём |
|---|---|
| `environment` | `cloudTargetKey` начинается с `logicalEnvironment:` **или** `workspaceRootPath=/workspace` |
| `local-rc` | `usePrivateWorker` + непустые `privateWorkerDisplayName` и `workspaceRootPath`, и это не environment |
| `private-incomplete` | `usePrivateWorker`, но нет имени воркера или пути |
| `other` | остальное (Cloud без private worker) |

Поля для разбора (команда `show`): `bcId`, `name`, `class`,
`workspaceRootPath`, `localFsPath` (из `privateWorkspaceIdentifier.uri.fsPath`),
`privateWorkerDisplayName`, `cloudTargetKey`, `usePrivateWorker`,
`hasStartedVm`, `environmentPublicId`, `repoUrl`.

`localFsPath` на диске при `workspaceRootPath=/workspace` — это
Environment, привязанная к GitHub-репо на этой машине, **не** local-rc.
`newest` такие сессии не возвращает. `handoff-ok` с uuid проверяет эту
сессию. Без uuid смотрит новейшую с `since_ms` любого class и отказывает,
если это не local-rc запрошенной папки.

Успех новой сессии: `handoff-ok` код 0, не `usePrivateWorker` в одиночку.

## Worker not ready

Текст: `Selected private worker is not available` + Request ID.

Ждать процесс из профиля стенда с `--worker-dir` = папка handoff.
Не ждать worker из `~/.config/Cursor` (это стол / эта RC-сессия оркестратора).

```bash
scripts/wait-worker.sh /ABS/PROJECT
scripts/stand.sh composer-send --id bc-… --dry-run   # где поле ввода, ничего не жмёт
scripts/stand.sh composer-send --id bc-…             # resend в эту вкладку
```

`composer-send` ищет поле ввода по снимку: новый чат — над кнопкой «Plan New Idea»,
переписка — над футером `/path @ <hostname>`. Вид не узнан — не кликает. С `--id`
отказывает, если открыта другая вкладка (иначе текст уходит в чужую сессию).

Не New Chat, не второй `handoff` параллельно, не печатать `--api-key`.

Первый convert на Home/No Repo — отдельный отказ (worker not ready /
Request ID в INVENTORY). Папка обязательна.

## IBus и палитра

`xdotool type` молчит из-за IBus. Везде `clip_paste`: clipboard **этого**
`$DISP` + ctrl+v, и только если `xclip -o` вернул тот же текст.

Search Agents (Ctrl+Alt+P): id вставляется только после проверки, что палитра
открыта (`palette-open`, до 3 попыток), — 07.10.2026 непроверенная вставка
уронила bc-id в поле ввода открытой сессии.
OCR рвёт короткое имя, кириллица каша. `palette-ok`
должен найти имя **или** bc-id / 12+ символов uuid без дефисов. Не нашёл —
Escape.

## Ловушка 3.23 Environment vs конвертация RC (07.10.2026)

На Cursor 3.23 три разных жеста, один из них RC:

| жест | что получается |
|---|---|
| Return в поиске папки, пока виден Recents | Environment, `/workspace` |
| слэш `/remote-control` | Environment даже при чипе This Computer (`bc-…`) |
| чип «Run on» → Self-Hosted Worker | выбирает Worker в *новом* чате, кнопка Set up Environment |
| футер This Computer → Continue on → Self-Hosted Worker | **local-rc** (`bc-…`, `bc-…`) |

Промежуточный environment первые секунды после конвертации — не отказ.
`convert-ok` ждёт `class=local-rc` + папка + воркер, до 90 с.

Не делать: rename сессии Environment в запрошенное имя; слэш; Include Changes;
считать чип Worker в новом чате локальным RC.

Локальный черновик сайдбара (нет `bc-`): если **не** работает — ПКМ →
**Discard**. Работающий локальный uuid (13.10: handoff упал на convert, агент
шёл 50 мин) — **не** Discard/Archive: `mine`/`busy` печатают `kind=local`;
дождаться конца хода → `convert --id`. Не Archive All Below.
`archive --id` только для записей `cloudAgentRepository`.

## Оверлеи, ломающие якоря (13.10.2026)

| UI | симптом | действие скрипта |
|---|---|---|
| Toast «Agent starting expensive processes» (правый низ, крестик ~1882,970) | `doctor`/handoff: нет `env-this-computer`; `composer-send`: «не узнал экран» | `overlay-scan` → клик крестика; **не** Manage Processes / Don't show again |
| «Move agent while it's working?» Cancel / Stop and Move | handoff ждал Exclude 90 с, «не стал local-rc»; агент продолжал локально | Cancel или Escape, **отказ**; **никогда** Stop and Move |

`stand_dismiss_overlays` вызывается перед якорями в handoff, convert,
composer-send (и тем самым в doctor dry-run). Снимки замера:
`var/shots/handoff-fail-convert-211747.png`, `20261013T2225*.png`.

## Якоря UI (glass 1920×1080 @ 0,0, пакет 3.23.23)

Таблица в `glass_agents.py` (`ANCHORS`). `anchor SHOT имя` → `x y` или код 1.
Зона — где искать, не точка клика.

| имя | токены | зона (x0,y0,x1,y1) |
|---|---|---|
| `new-chat` | New, Chat | 0,0,260,130 |
| `folder-chip` | main (клик левее) | 700,450,1100,520 |
| `folder-search` | repos | 740,490,1100,545 |
| `folder-result` | main + смещение | только если нет Recents |
| `env-this-computer` | This, Computer | 880,450,1200,530 |
| `env-self-hosted` | Worker (чип — стоп) | 880,450,1300,530 |
| `composer-pos` | Idea / футер hostname | по снимку |
| `footer-this-computer` | This, Computer | 400,1035,1100,1080 |
| `send-follow-up` | follow | 400,990,1100,1045 |
| `convert-self-hosted` | Worker (меню Continue on) | 500,990,1300,1065 |
| `exclude-changes` | Exclude, Changes | 850,540,1100,650 |
| `move-working` | Move, working | 650,450,1250,700 |
| `move-cancel` | Cancel | 900,550,1200,680 |
| `expensive-processes` | expensive, processes | 1450,920,1920,1080 |
| `customize` | Customize | 0,140,260,220 |
| `customize-mcps` | MCPs (запас McpPs) | 850,210,1200,290 |
| `customize-search` | Search | 700,170,1100,230 |
| `mcp-done` | Done (или синяя кнопка) | 1000,640,1250,740 |

Крестик toast: `find_expensive_dismiss` (OCR `x` у 1840–1915,945–995 или
fallback 1882,970). `convert` / handoff после первого READY зовут
`glass_convert_to_rc` (общий код). Локальный uuid до convert часто **нет** в
Search Agents — `convert --id` работает, если вкладка уже открыта (сразу после
`handoff --no-convert`); иначе отказ с подсказкой, не New agent.

MCP: `mcp list|find|enable|disable|add` → Customize → MCPs → Configure →
тоггл источника (зелёный = on). OCR имён короткие (`mt5`↔`mts`, `n8n`↔`nan`
или `gn` из-за иконки); повторный OCR вырезки имени, затем сверка с
mcp.json. Подстрока короче 3 символов именем не считается: «-» и «e»
раньше совпадали с любым известным сервером. Статус строки — `enabled`,
`disabled` или `error` (Needs Attention, «Error Show Output»).
`mcp-toggle` по пикселям дорожки. Не путать с Cloud Agents MCP dashboard.
Поиск Customize (`customize-search`) не кликать — ломает вкладки панели.

## Settings → Agents (22.11.2026, Cursor 3.30.14)

`settings agents` — только чтение. Клик ищет надпись и отказывается, если
точка ближе 42 px к Unregister, Log Out, Docs, Build, Manage или если
строка Agents — это Cloud Agents.

| шаг | что ищем | куда не кликать |
|---|---|---|
| `file` | File в строке меню | |
| `settings-item` | Settings, и рядом Exit | меню проекта (Log Out / Manage Environment) |
| `agents-nav` | Agents или «gents», если иконка съела букву | Cloud Agents, карточка Build on App |
| `back` | Back | поиск Settings |

Тумблер: зелёная дорожка x≈1386–1417 = on, серая ≈213,213,213 = off.
Выпадающий список читается вырезкой справа от подписи, не абзацем под ней.
Низ страницы — «Allowlist Options» или «always-allowed», не слово
Allowlists в абзаце Run Mode. На 22.11 ниже ещё Legacy Terminal Tool.

**UI ≠ lease RC.** `mcp find` / «N tools
enabled» — только Customize. Агент local-rc видит MCP, когда private worker
положил канон в
`$PROFILE/…/cursor-agent-worker/worker-data/<id>/projects/<slug>/mcps/<NAME>/`
(`SERVER_METADATA.json` + `tools/`). Если проектный `.cursor/mcp.json` +
enable не дают namespace в сессии — добавить тот же сервер в user
`~/.cursor/mcp.json` (`mcp add --user`), снова `enable`, открыть вкладку
папки, дождаться кэша; проверить `composer-send` («namespace … ready»).
Дубли кэша `project-0-<NAME>`, `user-<NAME>` — побочный эффект смены
идентификатора источника; после `ready` канон `<NAME>` оставить, дубли
можно снести. Ручная подкладка tool-файлов в кэш — не делать (stale
lease). Успех для пользователя «сессия увидела MCP» = ответ агента /
namespace `ready`, не строка в `mcp list`.

Rename/archive: X=120, Y=яркая полоса сайдбара; Y<130 = New Chat, отказ.
Если `shot` после шага — не тот UI: стоп, не крутить числа с голоса.

`up` без пути проекта. Если IDE — палитра «Open Agents Window» (скрипт).
IME в `up`: `GTK_IM_MODULE=xim`, `XMODIFIERS=""`.

dbus: не экспортировать мёртвый адрес из `state.env` (`dbus_addr_alive`).
Не писать `DBUS_SESSION_BUS_ADDRESS=...` словом перед бинарём (bash ищет
файл). `--password-store=basic` (gnome-keyring на стенде ломал логин).

## Тема, плейсхолдеры, правая панель (10.10.2026)

- **Тема меняется по времени суток.** В профиле стенда
  `window.autoDetectColorScheme: true`, поэтому днём glass светлый, ночью тёмный.
  Всё, что смотрит на яркость, обязано работать в обе стороны: выделенная строка
  сайдбара в тёмной теме светлее фона, в светлой — темнее (`sidebar_selected_y`
  берёт отклонение от базового фона). Якоря OCR от темы не зависят.
- **Надписи плывут без смены версии пакета.** 3.23.23 тот же, а плейсхолдер
  пикера папки стал «Search repos, cloud environments…», модель в чипе — другой.
  Серый плейсхолдер tesseract читает нестабильно («repos,» → «re» + «5,»;
  «environments.» / «environment:»). У якоря может быть запасной набор слов —
  ключ `alt` в `ANCHORS`; сравнение — подстрока от 3 символов.
- **Правая панель** сдвигает чат влево и ломает зоны якорей. `close_right_panel`
  находит её границу на снимке и закрывает переключателем в правом верхнем углу.
- **Выделенным может быть локальный черновик** без записи в профиле (после
  `archive` или Discard остаётся пустой New Chat) — `selected` вернёт uuid,
  которого нет в списке агентов; это не ошибка.
- **Ключ воркера.** `workers` патчит установленные `cursor-agent`, чтобы
  `--api-key` уходил в `CURSOR_API_KEY`; в `ps` ключа больше нет. Проверять
  счётчиком по `/proc/PID/cmdline`, значение не печатать.

## Обновление до 3.30

- **Палитра Search Agents → «Search chats…»** (вкладки All/Chats/Files). Ctrl+Alt+P
  тот же; `palette-open` узнаёт оба вида. Поиск по bc-id работает.
- **Правая панель Changes открывается после выбора папки-репо**, не сразу после
  New Chat. `handoff` закрывает её второй раз перед проверкой чипа среды.
- **Новый Cursor тянет новый agent CLI** (`Downloading Cursor Agent <ver>`), таймаут
  загрузки в расширении 120 с. На канале LTE (~170 МБ при ~1 МБ/с) он не успевает:
  `Activation failed: AbortError`, воркеры не поднимаются, `ensure` крутит
  перезапуски Cursor. Лечение: версию из лога расширения
  (`logs/*/window*/exthost/anysphere.cursor-agent-worker/`) скачать руками без
  таймаута — `https://downloads.cursor.com/lab/<ver>/linux/x64/agent-cli-package.tar.gz` —
  и распаковать `--strip-components=1` в
  `$PROFILE/User/globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions/<ver>/`
  (через `.tmp-…` и `mv`). Затем `stand.sh workers`: он сначала патчит launcher
  (ключ вне argv), потом открывает вкладки. Таймер на время ручной работы — `stop`, не `disable`.

## park / ensure

`park` убивает PID, у которых cmdline содержит профиль стенда + worker
start оттуда. Оркестратор с worker-dir в `~/.config/Cursor` не цель, но
копия infra-worker **стенда** на том же сокете — цель: park оборвёт её
тулы (замер park→up). Не park себя без просьбы.

`ensure`: если экран/Cursor не целые — `up`; потом `workers` (открыть
вкладку каждой папки `@ hostname`). Если воркеры мертвы при живом Cursor —
перезапуск GUI не чаще раза в 30 мин (`var/last-restart`), без `hold`, и только
если нет работающего агента (`glass.sh busy`): перезапуск обрывает его ход.
Поднятый воркер возобновляет агента с незавершённым ходом (07.10.2026 так ожил
«Greeting conversation») — после `workers` проверь `busy`.

## Секреты

В cmdline worker есть `--api-key`. В ответах, git, скилле, снимках
чата — вырезать. Снимки сайдбара содержат имена сессий; в репо не класть
(`$PROFILE/var/shots/`). Креды логина glass не в git.

## Прокси

`CURSOR_STAND_PROXY` пустой — `up` прокси не требует. Если задан и это
localhost, `up` проверяет, что порт слушает. Число порта — в
`config/hosts/<host>.env`, не в скрипте. Чужой порт не подставлять без `ss`.
