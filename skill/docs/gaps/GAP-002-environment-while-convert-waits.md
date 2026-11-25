# GAP-002. Пока convert ждёт, git-папка выглядит как Environment

Статус: закрыт формулировкой в скилле, [BL-044](../backlog/README.md).
Код ожидания `convert-ok` (до 90 с) не менялся: в замере он дождался.

## Факты

25.11.2026, k-99, handoff `-w /data/pro/mqlab -n cur-mql`,
`bc-0686f1ab-21e5-4596-ba36-ea94eb866417`. `convert-ok` печатал на 10, 20,
30, 40 и 50-й секундах:

- `class=environment`
- `workspaceRootPath=/workspace`
- `privateWorkerDisplayName=None`
- `cloudTargetKey=gitRepo:github.com/kogriv/mqlab`
- `localFsPath=/data/pro/mqlab`

На 60-й секунде та же строка стала `class=local-rc`,
`workspaceRootPath=/data/pro/mqlab`,
`privateWorkerDisplayName=/data/pro/mqlab @ k-99`. `handoff-ok` — код 0.

В тот же день handoff в `/tmp/curskill-e2e-20261125` (папка без
GitHub-remote): `convert-ok` на 8-й секунде уже `local-rc`, строк
`environment` в выводе не было. Сессия `bc-ce8cf694`.

Скилл до правки говорил в схеме и в шаге 10: `class=environment` — стоп,
не rename, не второй handoff. `reference` называл это «первыми секундами».
Пятьдесят секунд под эту фразу не подходят, и агент, читающий только
`SKILL.md`, остановился бы на промежуточной строке.

## Догадка

Папка, у которой Cursor видит GitHub-репозиторий, сначала получает
облачную строку `/workspace`, и только потом поля локального воркера.
Связь видна по двум прогонам одного дня. Отдельного опыта «репозиторий
без remote» и «не-git с remote» нет.

## Не это

Итоговая сессия `cur-mql` сломанной не была. Ждать дольше 90 с незачем:
если на 90-й секунде класс всё ещё environment, это уже отказ, как и
раньше.
