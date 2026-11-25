# GAP-004. Ход ещё «Planning», а handoff уже конвертирует

Статус: закрыт [BL-046](../backlog/README.md).

## Факты

Готовность первого ответа была «футер This Computer и поле follow-up».
Кнопка Stop в эту проверку не входит: запасной круг у follow-up давал
ложный Stop.

25.11.2026, k-99, около 15:51 (+07). Handoff в
`/tmp/curskill-cycle-20261125` напечатал «первый ответ готов», кликнул
футер и Self-Hosted Worker, затем «Move agent while it's working?»,
Cancel, код 1. Снимок `var/shots/move-working-cancel-155123.png`, OCR:

- `Planning` 592,138, `next` 659,139, `moves` 693,141
- `follow-up` 658,1014
- `This` 606,1045

Локальный uuid `dcf231c1-1d86-4b4a-b167-fea060a282d8` в
`cloudAgentRepository` не появился. Search Agents его не открывает.
В сайдбаре остался черновик «Ready response».

## Догадка

Поле follow-up и футер рисуются раньше, чем модель заканчивает первый
ход. Надпись «Planning next moves» в это время ещё на экране.

## Не это

Отказ скрипта на диалоге Move agent. Cancel вместо Stop and Move —
задуманное поведение. Ломается решение «ход уже кончился».

## Проверка

25.11.2026, 20:03 (+07). Тот же цикл, `bc-bf8816dc`. В логе строка
«футер есть, но на экране Planning next moves — жду», затем «первый
ответ готов» и convert без диалога Move agent. Имя `full-cycle`,
`archive --id` код 0.
