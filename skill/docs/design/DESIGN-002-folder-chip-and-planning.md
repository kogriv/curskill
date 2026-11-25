# DESIGN-002. Чип папки слева от This Computer, ход не кончился на Planning

Закрывает [GAP-003](../gaps/GAP-003-folder-chip-not-only-main.md) и
[GAP-004](../gaps/GAP-004-ready-while-planning.md).

## Чип

`find_anchor` для `folder-chip` и `folder-result` сначала ищет `main`,
как раньше. Если `main` нет, чип — самое правое длинное слово слева от
«This Computer» в полосе нового чата (y 430–560, не футер). Клик
`folder-chip` — центр этого слова. Клик `folder-result` — на 28 px левее
и на 68 px ниже, тот же сдвиг, что у ветки `main`.

Футерный This Computer (y≈1045) чипом не считается.

## Ход

`turn-busy SHOT` возвращает 0, когда на снимке рядом стоят `Planning` и
`next`. Handoff при футере и follow-up, но с этой парой, не начинает
convert и ждёт дальше, до прежних 90 с.

Слово Planning без next готовность не держит: так случайное слово в
тексте не растягивает ожидание на весь потолок.
