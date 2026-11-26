#!/usr/bin/env python3
"""Разбор сессий glass на стенде: sqlite + OCR палитры Search Agents / MCP."""
from __future__ import annotations

import json
import os
import re
import sqlite3
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    Image = None  # type: ignore[misc, assignment]

def _profile_default() -> str:
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return str(Path(base) / "cursor-stand")


def local_workspace(ws: str) -> bool:
    """Абсолютный путь на диске машины. Облачный /workspace сюда не входит."""
    return bool(ws) and ws.startswith("/") and not ws.startswith("/workspace")


DB = Path(os.environ.get("CURSOR_STAND_PROFILE", _profile_default())) / (
    "User/globalStorage/state.vscdb"
)


def load_agents(db: Path = DB) -> list[dict]:
    """Все строки cloudAgentRepository.agents%, не одна произвольная.

    Одинаковый bcId из более позднего ключа не затирает уже прочитанный:
    порядок — по key. Строка, которая не список, роняет вызов.
    """
    uri = f"file:{db}?mode=ro"
    con = sqlite3.connect(uri, uri=True)
    try:
        rows = con.execute(
            "select key, value from ItemTable "
            "where key like 'cloudAgentRepository.agents%' order by key"
        ).fetchall()
    finally:
        con.close()
    agents: list[dict] = []
    seen: set[str] = set()
    for key, raw in rows:
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8")
        data = json.loads(raw)
        if not isinstance(data, list):
            raise SystemExit(f"load_agents: {key} не список")
        for item in data:
            if not isinstance(item, dict):
                continue
            bid = str(item.get("bcId") or "")
            if bid:
                if bid in seen:
                    continue
                seen.add(bid)
            agents.append(item)
    return agents


def selected_ids(db: Path = DB) -> tuple[str | None, str | None]:
    uri = f"file:{db}?mode=ro"
    con = sqlite3.connect(uri, uri=True)

    def one(key: str) -> str | None:
        r = con.execute("select value from ItemTable where key=?", (key,)).fetchone()
        if not r or r[0] in (None, "", "None"):
            return None
        v = r[0]
        return v.decode("utf-8") if isinstance(v, bytes) else str(v)

    return one("cursor/glass.selectedAgent"), one("cursor/glass.lastRealAgent")


def local_fs_path(a: dict) -> str:
    ident = a.get("privateWorkspaceIdentifier")
    if not isinstance(ident, dict):
        return ""
    uri = ident.get("uri")
    if not isinstance(uri, dict):
        return ""
    return str(uri.get("fsPath") or uri.get("path") or "")


def classify(a: dict) -> str:
    """local-rc | environment | private-incomplete | other.

    07.10.2026: пикер 3.23 по локальной папке взял GitHub-репо +
    logicalEnvironment, корень `/workspace`, hasStartedVm=false.
    Это не локальный RC, даже если This Computer и usePrivateWorker.
    """
    ctk = str(a.get("cloudTargetKey") or "")
    ws = a.get("workspaceRootPath") or ""
    pw = a.get("privateWorkerDisplayName") or ""
    if ctk.startswith("logicalEnvironment:") or ws == "/workspace":
        return "environment"
    if a.get("usePrivateWorker") and pw and ws:
        return "local-rc"
    if a.get("usePrivateWorker"):
        return "private-incomplete"
    return "other"


def fmt_agent(a: dict) -> str:
    return (
        f"{a.get('bcId')}  {a.get('name')!r}  "
        f"class={classify(a)}  "
        f"ws={a.get('workspaceRootPath') or '-'}  "
        f"pw={a.get('privateWorkerDisplayName') or '-'}"
    )


def show_agent(a: dict) -> None:
    ident = local_fs_path(a)
    print(f"bcId={a.get('bcId')}")
    print(f"name={a.get('name')!r}")
    print(f"class={classify(a)}")
    print(f"workspaceRootPath={a.get('workspaceRootPath')!r}")
    print(f"localFsPath={ident!r}")
    print(f"privateWorkerDisplayName={a.get('privateWorkerDisplayName')!r}")
    print(f"cloudTargetKey={a.get('cloudTargetKey')!r}")
    print(f"usePrivateWorker={a.get('usePrivateWorker')!r}")
    print(f"hasStartedVm={a.get('hasStartedVm')!r}")
    print(f"environmentPublicId={a.get('environmentPublicId')!r}")
    print(f"repoUrl={a.get('repoUrl')!r}")
    print(f"status={a.get('status')!r}")
    print(f"isArchived={a.get('isArchived')!r}")


def resolve(
    agents: list[dict],
    *,
    bc_id: str | None = None,
    from_name: str | None = None,
    current: bool = False,
) -> dict:
    if sum(bool(x) for x in (bc_id, from_name, current)) != 1:
        raise SystemExit("нужен ровно один селектор: --id, --from или --current")

    if current:
        sel, last = selected_ids()
        target = sel or last
        if not target:
            raise SystemExit("rename --current: sqlite не знает выделенную сессию")
        hits = [a for a in agents if a.get("bcId") == target]
        if len(hits) != 1:
            raise SystemExit(f"rename --current: нет записи {target} в профиле стенда")
        return hits[0]

    if bc_id:
        needle = bc_id.strip()
        if needle.startswith("https://"):
            needle = needle.rstrip("/").rsplit("/", 1)[-1]
        hits = [a for a in agents if a.get("bcId") == needle]
        if not hits:
            hits = [a for a in agents if (a.get("bcId") or "").startswith(needle)]
        if not hits:
            uid = bare_uuid(needle)
            if uid:
                hits = [a for a in agents if bare_uuid(a.get("bcId")) == uid]
        if not hits:
            raise SystemExit(f"нет сессии {needle} в профиле стенда")
        if len(hits) > 1:
            listing = "\n".join("  " + fmt_agent(a) for a in hits)
            raise SystemExit(f"id {needle} неоднозначен:\n{listing}")
        return hits[0]

    assert from_name is not None
    q = from_name.strip()
    ql = q.lower()
    exact = [a for a in agents if (a.get("name") or "") == q]
    if len(exact) == 1:
        return exact[0]
    iexact = [a for a in agents if (a.get("name") or "").lower() == ql]
    if len(iexact) == 1:
        return iexact[0]
    if len(exact) > 1 or len(iexact) > 1:
        hits = exact or iexact
        listing = "\n".join("  " + fmt_agent(a) for a in hits)
        raise SystemExit(
            f"имя {q!r} неоднозначно, укажи --id:\n{listing}"
        )
    sub = [a for a in agents if ql in (a.get("name") or "").lower()]
    if len(sub) == 1:
        return sub[0]
    if len(sub) > 1:
        listing = "\n".join("  " + fmt_agent(a) for a in sub)
        raise SystemExit(f"подстрока {q!r} неоднозначна, укажи --id:\n{listing}")
    listing = "\n".join("  " + fmt_agent(a) for a in agents[:12])
    raise SystemExit(f"нет сессии с именем {q!r}. Есть:\n{listing}")


def ocr_words(
    shot: Path, *, lang: str = "eng", psm: int = 11
) -> list[tuple[int, int, int, int, float, str]]:
    """tesseract tsv: (x, y, w, h, conf, text). Координаты окна 1920×1080."""
    out = subprocess.run(
        ["tesseract", str(shot), "stdout", "-l", lang, "--psm", str(psm), "tsv"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout
    words: list[tuple[int, int, int, int, float, str]] = []
    for line in out.splitlines()[1:]:
        f = line.split("\t")
        if len(f) >= 12 and f[11].strip():
            try:
                conf = float(f[10])
            except ValueError:
                conf = -1.0
            words.append(
                (int(f[6]), int(f[7]), int(f[8]), int(f[9]), conf, f[11].strip())
            )
    return words


def _norm_tok(s: str) -> str:
    return s.lower().strip(".,;:()[]<>\"'`‘’“”?!")


_UUID_RE = re.compile(
    r"^(?:bc-)?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$",
    re.I,
)


def bare_uuid(s: str | None) -> str | None:
    if not s:
        return None
    m = _UUID_RE.match(str(s).strip())
    return m.group(1).lower() if m else None


def agent_by_uuid(agents: list[dict], uid: str) -> dict | None:
    u = uid.lower().removeprefix("bc-")
    for a in agents:
        if (a.get("bcId") or "").removeprefix("bc-").lower() == u:
            return a
    return None


def find_expensive_dismiss(
    words: list[tuple[int, int, int, int, float, str]],
) -> tuple[int, int] | None:
    """Крестик toast «Agent starting expensive processes». Не Manage / Don't show again."""
    if not find_anchor(words, "expensive-processes"):
        return None
    xs = [
        (x, y, w, h)
        for x, y, w, h, _c, t in words
        if _norm_tok(t) == "x"
        and 1840 <= x <= 1915
        and 945 <= y <= 995
        and w <= 24
        and h <= 24
    ]
    if xs:
        x, y, w, h = max(xs, key=lambda b: b[0])
        return x + w // 2, y + h // 2
    return 1882, 970


def _tok_match(nt: str, tok: str) -> bool:
    compact = nt.replace("_", "").replace("-", "")
    return nt == tok or (len(tok) >= 3 and tok in compact)


# Якоря handoff 3.23. Замер BL-001 07.10.2026, glass 1920×1080.
# zone = (x0, y0, x1, y1). click: union-center | offset (dx, dy от центра
# объединения токенов) | from-token (токен, dx, dy).
ANCHORS: dict[str, dict] = {
    "new-chat": {
        "tokens": ("New", "Chat"),
        "zone": (0, 0, 260, 130),
        "click": "union-center",
    },
    "folder-chip": {
        "tokens": ("main",),
        "zone": (700, 450, 1100, 520),
        "click": ("from-token", "main", -55, 3),
    },
    "env-cloud": {
        "tokens": ("Cloud",),
        "zone": (880, 450, 1120, 520),
        "click": "union-center",
    },
    "env-this-computer": {
        "tokens": ("This", "Computer"),
        "zone": (880, 450, 1200, 530),
        "click": "union-center",
    },
    "env-self-hosted": {
        "tokens": ("Worker",),
        "zone": (880, 450, 1300, 530),
        "click": "union-center",
    },
    "folder-search": {
        # «Search» OCR часто режет до «earch» (conf 0, h-picker-135156).
        # «repos» в плейсхолдере стабилен (BL-001 и trace 07.10).
        "tokens": ("repos",),
        # 10.10.2026: плейсхолдер стал «Search repos, cloud environments…»,
        # «repos,» OCR рвёт на «re» + «5,»; конец надписи читается надёжнее, но
        # тоже плавает («environments.» / «environment:»), поэтому подстрока.
        # 26.11.2026 10:34: OCR прочитал environments как environmer.
        # «nvironment» в это слово не входит, «nviron» входит и в полную надпись.
        "alt": (("nvironment",), ("nviron",)),
        "zone": (740, 490, 1100, 545),
        "click": "union-center",
    },
    "folder-result": {
        # После фильтра поиска слово Search пропадает. Клик по первой
        # строке результата: смещение от чипа ветки `main` (BL-001: 850,553).
        # Вызывать только если якорь recents НЕ найден.
        "tokens": ("main",),
        "zone": (700, 450, 1100, 520),
        "click": ("from-token", "main", -28, 68),
    },
    "recents": {
        "tokens": ("Recents",),
        "zone": (740, 520, 1100, 590),
        "click": "union-center",
    },
    "set-environment": {
        "tokens": ("Set", "Environment"),
        "zone": (740, 600, 1100, 680),
        "click": "union-center",
    },
    "plan-idea": {
        "tokens": ("Idea",),
        "zone": (700, 550, 1300, 750),
        "click": ("offset", 0, -90),
    },
    "remote-control": {
        "tokens": ("remote-control",),
        "zone": (700, 580, 1200, 720),
        "click": "union-center",
    },
    "archive-item": {
        "tokens": ("Archive",),
        "zone": (100, 600, 280, 750),
        "click": "union-center",
    },
    # Конвертация локального чата → RC (замер владельца 07.10 14:28, y>1040).
    "footer-this-computer": {
        "tokens": ("This", "Computer"),
        "zone": (400, 1035, 1100, 1080),
        "click": "union-center",
    },
    "send-follow-up": {
        "tokens": ("follow",),
        "zone": (400, 990, 1100, 1045),
        "click": "union-center",
    },
    # Меню «Continue on» после клика по футеру: Worker ≈811,1024, не чип y≈482.
    "convert-self-hosted": {
        "tokens": ("Worker",),
        "zone": (500, 990, 1300, 1065),
        "click": "union-center",
    },
    # Диалог uncommitted: только Exclude Changes, не Include (x≈1113) и не Enter.
    "exclude-changes": {
        "tokens": ("Exclude", "Changes"),
        "zone": (850, 540, 1100, 650),
        "click": "union-center",
    },
    # Customize → MCPs.
    "customize": {
        "tokens": ("Customize",),
        "zone": (0, 140, 260, 220),
        "click": "union-center",
    },
    "customize-mcps": {
        # 22.11.2026 tesseract читает вкладку как McpPs. Зона шире: вкладки
        # съезжают вправо от карточки «Meet Grok Bot».
        "tokens": ("MCPs",),
        "alt": (("McpPs",), ("Mcp", "Ps")),
        "zone": (850, 210, 1200, 290),
        "click": "union-center",
    },
    "customize-search": {
        # Плейсхолдер «Search Plugins, Skills, MCPs…» в панели Customize.
        "tokens": ("Search",),
        "zone": (700, 170, 1100, 230),
        "click": "union-center",
    },
    "mcp-new-server": {
        "tokens": ("New", "MCP", "Server"),
        "zone": (700, 600, 1200, 900),
        "click": "union-center",
    },
    "mcp-done": {
        "tokens": ("Done",),
        "zone": (1000, 640, 1250, 740),
        "click": "union-center",
    },
    "mcp-reload": {
        "tokens": ("Reload",),
        "zone": (750, 640, 950, 740),
        "click": "union-center",
    },
    # «Move agent while it's working?» (13.10.2026): Cancel/Esc, никогда Stop and Move.
    "move-working": {
        "tokens": ("Move", "working"),
        "alt": (("Moving", "stop"), ("Move", "agent")),
        "zone": (650, 450, 1250, 700),
        "click": "union-center",
    },
    "move-cancel": {
        "tokens": ("Cancel",),
        "zone": (900, 550, 1200, 680),
        "click": "union-center",
    },
    # Toast «Agent starting expensive processes» (правый низ); крестик ~1882,970.
    "expensive-processes": {
        "tokens": ("expensive", "processes"),
        "zone": (1450, 920, 1920, 1080),
        "click": "union-center",
    },
}


def _in_zone(
    x: int, y: int, w: int, h: int, zone: tuple[int, int, int, int]
) -> bool:
    cx, cy = x + w // 2, y + h // 2
    x0, y0, x1, y1 = zone
    return x0 <= cx <= x1 and y0 <= cy <= y1


def _composer_this_computer(
    words: list[tuple[int, int, int, int, float, str]],
) -> tuple[int, int, int, int] | None:
    """«This Computer» чипа нового чата, не футер (тот ниже y=1035)."""
    this = None
    comp = None
    for x, y, w, h, _c, t in words:
        nt = _norm_tok(t)
        if not (430 <= y <= 560 and x >= 700):
            continue
        if nt == "this":
            this = (x, y, w, h)
        elif nt == "computer":
            comp = (x, y, w, h)
    if not this or not comp:
        return None
    if not (this[0] < comp[0] < this[0] + 180 and abs(this[1] - comp[1]) < 24):
        return None
    return this


def _folder_name_box(
    words: list[tuple[int, int, int, int, float, str]],
) -> tuple[int, int, int, int] | None:
    """Имя папки слева от чипа This Computer.

    Слово main — ветка внутри чипа. Если папка уже выбрана, OCR читает её
    имя и main нет (25.11.2026, handoff-fail-155702: curskill-cycle-20261125
    в 800,482, This Computer в 984,473).
    """
    this = _composer_this_computer(words)
    if not this:
        return None
    tx, ty, _tw, th = this
    best = None
    for x, y, w, h, _c, t in words:
        nt = _norm_tok(t)
        if len(nt) < 3 or w < 36 or x < 500:
            continue
        if abs((y + h / 2) - (ty + th / 2)) > 18:
            continue
        if x + w > tx - 6:
            continue
        if best is None or x > best[0]:
            best = (x, y, w, h)
    return best


def _folder_result_click(
    words: list[tuple[int, int, int, int, float, str]],
) -> tuple[int, int] | None:
    """Центр видимой строки пикера под чипом. Закрытый пикер — пусто.

    Смещение «на 68 px ниже» попадало в ленту, когда списка на снимке нет.
    """
    chip = None
    zone = ANCHORS["folder-chip"]["zone"]
    for x, y, w, h, _c, t in words:
        if _in_zone(x, y, w, h, zone) and _tok_match(_norm_tok(t), "main"):
            chip = (x, y, w, h)
            break
    if chip is None:
        chip = _folder_name_box(words)
    if chip is None:
        return None
    cy = chip[1] + chip[3] / 2
    # Строка поиска сидит примерно на 36 px ниже чипа. Результат — ниже неё.
    # 26.11.2026 h-filtered-103601: вставленный путь прочитан в поле поиска
    # на y=515, настоящая строка — на y=562. Порог +36 кликал поле.
    skip = {"repos", "search", "recents", "this", "computer", "nvironment"}
    best = None
    for x, y, w, h, _c, t in words:
        nt = _norm_tok(t)
        if len(nt) < 2 or nt in skip or "nviron" in nt:
            continue
        midy = y + h / 2
        if not (cy + 56 <= midy <= cy + 110):
            continue
        if not (700 <= x <= 1200):
            continue
        if best is None or (y, x) < (best[1], best[0]):
            best = (x, y, w, h)
    if best is None:
        return None
    x, y, w, h = best
    return x + w // 2, y + h // 2


def turn_still_planning(
    words: list[tuple[int, int, int, int, float, str]],
) -> bool:
    """«Planning next moves» — ход не кончился, даже если футер уже виден.

    25.11.2026 move-working-cancel-155123: Planning 592,138 и next 659,139
    одновременно с follow-up 658,1014 и This 606,1045.
    """
    heads = [
        (x, y)
        for x, y, _w, _h, _c, t in words
        if _norm_tok(t) == "planning" and x > 400 and 80 <= y <= 900
    ]
    for x, y, _w, _h, _c, t in words:
        if _norm_tok(t) != "next":
            continue
        for px, py in heads:
            if abs(y - py) < 20 and px < x < px + 200:
                return True
    return False


def find_anchor(
    words: list[tuple[int, int, int, int, float, str]], name: str
) -> tuple[int, int] | None:
    if name == "folder-result":
        return _folder_result_click(words)
    spec = ANCHORS.get(name)
    if not spec:
        return None
    zone = spec["zone"]
    # Основной набор слов и запасные ("alt"): надпись в интерфейсе меняется
    # между версиями, якорь должен пережить обе редакции.
    for tokens in (spec["tokens"], *spec.get("alt", ())):
        want = [_norm_tok(t) for t in tokens]
        found: dict[str, tuple[int, int, int, int]] = {}
        for x, y, w, h, _c, t in words:
            if not _in_zone(x, y, w, h, zone):
                continue
            nt = _norm_tok(t)
            for tok in want:
                if _tok_match(nt, tok):
                    found.setdefault(tok, (x, y, w, h))
        if all(t in found for t in want):
            break
    else:
        if name != "folder-chip":
            return None
        box = _folder_name_box(words)
        if not box:
            return None
        x, y, w, h = box
        return x + w // 2, y + h // 2
    boxes = [found[t] for t in want]
    x0 = min(b[0] for b in boxes)
    y0 = min(b[1] for b in boxes)
    x1 = max(b[0] + b[2] for b in boxes)
    y1 = max(b[1] + b[3] for b in boxes)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    click = spec["click"]
    if click == "union-center":
        return cx, cy
    if isinstance(click, tuple) and click[0] == "offset":
        return cx + int(click[1]), cy + int(click[2])
    if isinstance(click, tuple) and click[0] == "from-token":
        _, tok, dx, dy = click
        bx = found[_norm_tok(tok)]
        return bx[0] + bx[2] // 2 + int(dx), bx[1] + bx[3] // 2 + int(dy)
    return cx, cy


def composer_click(
    words: list[tuple[int, int, int, int, float, str]], host: str
) -> tuple[int, int] | None:
    """Поле ввода. Футер переписки важнее слова Idea в ленте.

    Новый чат без футера по-прежнему берёт plan-idea (кнопка, поле выше).
    """
    for x, y, _w, _h, _c, t in words:
        if host and host in t and y > 1000 and x > 260:
            return x + 250, y - 38
    follow = find_anchor(words, "send-follow-up")
    if follow:
        return follow
    footer = find_anchor(words, "footer-this-computer")
    if footer:
        return footer[0], footer[1] - 38
    return find_anchor(words, "plan-idea")


def archive_menu_click(
    words: list[tuple[int, int, int, int, float, str]],
) -> tuple[int, int] | None:
    """Пункт Archive в меню сайдбара. Не лента чата и не Archive All Below."""
    below_ys = [y for x, y, _w, _h, _c, t in words if t.lower() == "below" and 90 <= x <= 460]
    all_ys = [y for x, y, _w, _h, _c, t in words if t.lower() == "all" and 90 <= x <= 460]
    hits = [
        (x, y, w, h)
        for x, y, w, h, _c, t in words
        if t.lower() == "archive"
        and 90 <= x <= 460
        and all(abs(y - by) > 12 for by in below_ys)
        and all(abs(y - ay) > 12 for ay in all_ys)
    ]
    if not hits:
        return None
    x, y, w, h = hits[0]
    return x + w // 2, y + h // 2


def discard_menu_click(
    words: list[tuple[int, int, int, int, float, str]],
) -> tuple[int, int] | None:
    """Пункт Discard в меню сайдбара. Не Archive и не Archive All Below."""
    below_ys = [y for x, y, _w, _h, _c, t in words if t.lower() == "below" and 90 <= x <= 460]
    all_ys = [y for x, y, _w, _h, _c, t in words if t.lower() == "all" and 90 <= x <= 460]
    hits = [
        (x, y, w, h)
        for x, y, w, h, _c, t in words
        if t.lower() == "discard"
        and 90 <= x <= 460
        and all(abs(y - by) > 12 for by in below_ys)
        and all(abs(y - ay) > 12 for ay in all_ys)
    ]
    if not hits:
        return None
    x, y, w, h = hits[0]
    return x + w // 2, y + h // 2


def inventory_lines(agents: list[dict], selected: str | None) -> list[str]:
    """Вкладки профиля: id, имя, папка, класс, ход, воркер.

    Черновик без строки cloudAgentRepository — kind=local-draft.
    Архив и killed не входят.
    """
    lines: list[str] = []
    seen: set[str] = set()
    for a in agents:
        if a.get("isArchived") or a.get("isKilled"):
            continue
        bid = str(a.get("bcId") or "")
        uid = bare_uuid(bid) or bid
        if uid:
            seen.add(uid)
        working = "1" if a.get("status") == 1 else "0"
        lines.append(
            "\t".join(
                (
                    bid,
                    str(a.get("name") or ""),
                    str(a.get("workspaceRootPath") or ""),
                    classify(a),
                    working,
                    str(a.get("privateWorkerDisplayName") or ""),
                )
            )
        )
    uid = bare_uuid(selected)
    if uid and uid not in seen:
        lines.append(f"{uid}\t\t\tlocal-draft\t?\t")
    return lines


def foreign_name_changes(before: str, after: str, new_id: str) -> list[str]:
    """Чужие вкладки, у которых между двумя описями сменилось имя."""

    def names(text: str) -> dict[str, str]:
        out: dict[str, str] = {}
        for line in text.splitlines():
            parts = line.split("\t")
            if not parts or not parts[0]:
                continue
            out[parts[0]] = parts[1] if len(parts) > 1 else ""
        return out

    old, new = names(before), names(after)
    skip = {new_id}
    uid = bare_uuid(new_id)
    if uid:
        skip.add(uid)
        skip.add(f"bc-{uid}")
    changed: list[str] = []
    for ident, name in old.items():
        bare = bare_uuid(ident) or ident
        if ident in skip or bare in skip or f"bc-{bare}" in skip:
            continue
        if ident in new and new[ident] != name:
            changed.append(f"{ident}\t{name}\t{new[ident]}")
    return changed


def _row_token_hits(part: str, tokens: list[str]) -> bool:
    """Слово имени есть в строке. OCR режет хвост: instruction → instruc."""
    for tok in tokens:
        if len(tok) < 4:
            continue
        if part == tok:
            return True
        if part.startswith(tok) and len(tok) * 2 >= len(part):
            return True
        if tok.startswith(part) and len(part) * 2 >= len(tok):
            return True
    return False


def sidebar_row_matches(
    words: list[tuple[int, int, int, int, float, str]], y: int, name: str
) -> bool:
    """Имя сессии есть в словах строки сайдбара на этой Y. x>280 — не сайдбар."""
    parts = [p for p in _norm_tok(name).split() if len(p) >= 4]
    if not parts:
        return False
    tokens = [
        _norm_tok(t)
        for x, yy, w, h, _c, t in words
        if x <= 280 and abs((yy + h / 2) - y) <= 18 and _norm_tok(t)
    ]
    return all(_row_token_hits(part, tokens) for part in parts)


def ocr_image(path: Path) -> str:
    r = subprocess.run(
        ["tesseract", str(path), "stdout", "-l", "eng+rus", "--psm", "6"],
        check=False,
        capture_output=True,
        text=True,
    )
    return r.stdout or ""


def _compact_name(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", _norm_tok(s))


def _ocr_name_match(got: str, want: str) -> bool:
    """Имена MCP короткие; OCR часто mt5→mts, n8n→nan, ai-agent→aiagent.

    Подстрока короче 3 символов не считается: «-» и «e» раньше совпадали
    с любым известным именем (пустая строка после снятия дефиса — подстрока
    всего, одна буква входит в ai-agent-bridge).
    """
    ca, cb = _compact_name(got), _compact_name(want)
    if len(ca) < 2 or len(cb) < 2:
        return False
    if ca == cb:
        return True
    # Не подстрока: «register» входит в «unregister», «e» — в длинное имя.
    if abs(len(ca) - len(cb)) > 1 or max(len(ca), len(cb)) > 40:
        return False
    if len(ca) == len(cb):
        return sum(x != y for x, y in zip(ca, cb)) <= 1
    longer, shorter = (ca, cb) if len(ca) > len(cb) else (cb, ca)
    for i in range(len(longer)):
        if longer[:i] + longer[i + 1 :] == shorter:
            return True
    return False


def _ocr_crop(shot: Path, box: tuple[int, int, int, int], psm: int = 8) -> str:
    """Второй проход tesseract по вырезке. Пустая строка, если PIL нет."""
    if Image is None:
        return ""
    im = Image.open(shot)
    w, h = im.size
    x0, y0, x1, y1 = box
    x0, y0 = max(0, int(x0)), max(0, int(y0))
    x1, y1 = min(w, int(x1)), min(h, int(y1))
    if x1 - x0 < 8 or y1 - y0 < 8:
        return ""
    tmp = Path(os.environ.get("TMPDIR", "/tmp")) / f"cursor-stand-ocr-{os.getpid()}.png"
    im.crop((x0, y0, x1, y1)).save(tmp)
    try:
        out = subprocess.run(
            ["tesseract", str(tmp), "stdout", "-l", "eng", "--psm", str(psm)],
            capture_output=True,
            text=True,
            check=False,
        ).stdout
    finally:
        tmp.unlink(missing_ok=True)
    return " ".join(out.split())


_PROJECT_ID = re.compile(r"^project-\d+-(.+)$")


def server_name_from_id(sid: str, json_names: list[str]) -> str | None:
    """Имя сервера из id Cursor. Не режем имя с дефисом до последнего куска.

    user-ai-agent-bridge → ai-agent-bridge.
    project-0-app-tool → tool, если в json нет более длинного суффикса.
    project-0-app-long-name без известного имени не становится name.
    """
    s = str(sid).strip()
    if s.startswith("user-"):
        name = s[5:].strip()
        return name or None
    m = _PROJECT_ID.match(s)
    if not m:
        return None
    rest = m.group(1)
    matches = [n for n in json_names if n and (rest == n or rest.endswith("-" + n))]
    if matches:
        return max(matches, key=len)
    parts = rest.split("-")
    if len(parts) == 2 and parts[1]:
        return parts[1]
    return None


def known_mcp_names() -> list[str]:
    """Имена из mcp.json + mcpService.knownServerIds профиля стенда (без секретов)."""
    names: list[str] = []
    seen: set[str] = set()

    def add(name: str) -> None:
        key = str(name).strip()
        if key and key not in seen:
            seen.add(key)
            names.append(key)

    paths = [Path.home() / ".cursor" / "mcp.json"]
    ws = os.environ.get("CURSOR_STAND_MCP_WORKSPACE")
    if ws:
        paths.append(Path(ws) / ".cursor" / "mcp.json")
        paths.append(Path(ws) / ".mcp.json")
    for p in paths:
        if not p.is_file():
            continue
        try:
            raw = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        servers = raw.get("mcpServers") if isinstance(raw, dict) else None
        if not isinstance(servers, dict):
            continue
        for name in servers:
            add(str(name))
    # sqlite: user-demo / project-0-app-tool → demo / tool
    try:
        uri = f"file:{DB}?mode=ro"
        con = sqlite3.connect(uri, uri=True)
        row = con.execute(
            "select value from ItemTable where key='mcpService.knownServerIds'"
        ).fetchone()
        if row and row[0]:
            raw = row[0]
            if isinstance(raw, bytes):
                raw = raw.decode("utf-8", "replace")
            for sid in json.loads(raw):
                name = server_name_from_id(str(sid), names)
                if name:
                    add(name)
    except (OSError, sqlite3.Error, json.JSONDecodeError, TypeError):
        pass
    return names


def mcp_list_from_shot(
    shot: Path, known: list[str] | None = None
) -> list[dict[str, str]]:
    """Строки вкладки MCPs: name, status (enabled|disabled|error|unknown), detail."""
    words = ocr_words(shot)
    # Основная колонка Customize, не сайдбар.
    zone_words = [
        (x, y, w, h, c, t)
        for x, y, w, h, c, t in words
        if 700 <= x <= 1400 and 250 <= y <= 900
    ]
    names = known if known is not None else known_mcp_names()
    skip = {
        "user",
        "local",
        "new",
        "mcp",
        "server",
        "add",
        "custom",
        "connected",
        "needs",
        "attention",
        "tools",
        "resources",
        "enabled",
        "disabled",
        "error",
        "show",
        "output",
        "plugins",
        "skills",
        "rules",
        "commands",
        "hooks",
        "subagents",
        "browse",
        "marketplace",
    }
    # Якоря статуса → собрать имя из токенов чуть выше.
    anchors: list[tuple[int, str]] = []  # y, status
    for x, y, w, h, _c, t in zone_words:
        nt = _norm_tok(t)
        if nt == "disabled":
            anchors.append((y, "disabled"))
        elif nt == "error":
            anchors.append((y, "error"))
        elif nt in {"enabled", "tools"}:
            anchors.append((y, "enabled"))
    rows: list[dict[str, str]] = []
    used_y: list[int] = []
    for ay, status in anchors:
        detail = _mcp_status_detail(zone_words, ay, status)
        if any(abs(ay - uy) < 22 for uy in used_y):
            continue
        # имя — токены на 0..36 px выше якоря статуса
        name_toks = [
            (x, y, w, h, t)
            for x, y, w, h, _c, t in zone_words
            if 0 <= (ay - y) <= 36 and x < 1000
        ]
        match_name = None
        click = None
        for kn in names:
            for x, y, w, h, t in name_toks:
                if _ocr_name_match(t, kn):
                    match_name = kn
                    click = (x + w // 2, y + h // 2)
                    break
            if match_name:
                break
        if match_name is None:
            for x, y, w, h, t in name_toks:
                nt = _norm_tok(t)
                if len(nt) < 2 or len(nt) > 32 or nt in skip or nt.isdigit():
                    continue
                match_name = nt
                click = (x + w // 2, y + h // 2)
                break
        if not match_name or not click:
            continue
        used_y.append(ay)
        rows.append(
            {
                "name": match_name,
                "status": status,
                "detail": detail,
                "x": str(click[0]),
                "y": str(click[1]),
            }
        )
    # Имя в колонке есть, а слово Disabled/enabled OCR не прочитал
    # (26.11.2026 mcp-list-104458: curskill-probe виден, слова Disabled нет).
    seen = {r["name"].lower() for r in rows}
    for kn in names:
        if kn.lower() in seen:
            continue
        hit = None
        for x, y, w, h, _c, t in zone_words:
            if _ocr_name_match(t, kn):
                hit = (x, y, w, h)
                break
        if hit is None:
            continue
        x, y, w, h = hit
        rows.append(
            {
                "name": kn,
                "status": "unknown",
                "detail": "",
                "x": str(x + w // 2),
                "y": str(y + h // 2),
            }
        )
        seen.add(kn.lower())
    rows.sort(key=lambda r: int(r["y"]))
    known_list = names
    for row in rows:
        _refine_mcp_name(shot, row, known_list)
    return [r for r in rows if _mcp_name_ok(r["name"])]


def _mcp_status_detail(
    zone_words: list[tuple[int, int, int, int, float, str]], y: int, status: str
) -> str:
    """Строка под именем: «109 tools enabled», «7 tools, 5 resources enabled», «Error - Show Output»."""
    toks = [
        (x, t.strip("‘'\"`"))
        for x, yy, _w, _h, _c, t in zone_words
        if abs(yy - y) < 16 and x >= 740 and t.strip("‘'\"`-· ")
    ]
    toks.sort()
    parts: list[str] = []
    for _x, t in toks:
        nt = _norm_tok(t)
        if nt in {"user", "new", "mcp"}:
            continue
        if len(nt) <= 1 and not t[:1].isdigit():
            continue
        parts.append(t)
    text = " ".join(parts).strip()
    if status == "disabled":
        return text or "Disabled"
    if status == "error":
        return text or "Error"
    return text or "enabled"


def _mcp_name_ok(name: str) -> bool:
    compact = _compact_name(name)
    if len(compact) < 2 or compact in {"user", "new", "mcp", "server", "tools", "enabled"}:
        return False
    return True


def _refine_mcp_name(shot: Path, row: dict[str, str], known: list[str]) -> None:
    """Каноническое имя из known. Иконка слева от n8n на psm 11 читается как «gn»."""
    for kn in known:
        if _ocr_name_match(row["name"], kn):
            row["name"] = kn
            return
    x, y = int(row["x"]), int(row["y"])
    text = _ocr_crop(shot, (x - 36, y - 16, x + 110, y + 18), psm=8)
    for word in re.split(r"[\s,]+", text):
        for kn in known:
            if _ocr_name_match(word, kn):
                row["name"] = kn
                return
    # Вырезка читается лучше сырого токена («nan» вместо «gn»), даже если имени нет в known.
    for word in re.split(r"[\s,]+", text):
        if _mcp_name_ok(word) and not _norm_tok(word) == "user":
            row["name"] = word
            return


def mcp_row_pos(shot: Path, name: str, known: list[str] | None = None) -> tuple[int, int] | None:
    for row in mcp_list_from_shot(shot, known):
        if _ocr_name_match(row["name"], name) or row["name"] == name:
            return int(row["x"]), int(row["y"])
    # прямой OCR, если list не собрал
    for x, y, w, h, _c, t in ocr_words(shot):
        if 700 <= x <= 1200 and 280 <= y <= 850 and _ocr_name_match(t, name):
            return x + w // 2, y + h // 2
    return None


def mcp_source_toggle(shot: Path) -> tuple[str, int, int] | None:
    """В модалке Configure: (on|off, click_x, click_y). Клик — по дорожке тоггла источника."""
    if Image is None:
        return None
    im = Image.open(shot).convert("RGB")
    px = im.load()
    w, h = im.size
    # Y строки источника: OCR `mcp.json` / `.cursor` (модалка выше, когда виден Tools).
    row_y = None
    for x, y, _w, _h, _c, t in ocr_words(shot):
        tl = t.lower().replace(" ", "")
        # 26.11.2026 mcp-cfg-104652: «.cursor/mcp.json» прочитан как imepjson.
        if (
            "mcp.json" in tl
            or "mcpjson" in tl
            or "mepjson" in tl
            or "cursor/mcp" in tl
            or "cursor/mep" in tl
        ):
            if 700 <= x <= 1100:
                row_y = y + _h // 2
                break
    if row_y is None:
        # запас: первая зелёная дорожка тоггла в колонке справа модалки
        for y in range(300, min(700, h)):
            gcount = sum(
                1
                for x in range(1080, min(1160, w))
                if (lambda r, g, b: g > r + 25 and g > 100)(*px[x, y])
            )
            if gcount > 12:
                row_y = y
                break
    if row_y is None:
        return None
    x0, x1 = 1080, min(1160, w)
    y0, y1 = max(280, row_y - 24), min(h - 1, row_y + 24)
    green = 0
    whites: list[tuple[int, int]] = []
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y]
            if g > r + 25 and g > 100:
                green += 1
            if r > 220 and g > 220 and b > 220:
                whites.append((x, y))
    # Светлая модалка: фон белый, и «knob» из всех белых пикселей — это середина окна.
    # Выключенная дорожка — серая пилюля (mcp-cfg-104652: x 1099–1130, y 506–525).
    if len(whites) > 800 and green < 20:
        pill = [
            (x, y)
            for y in range(y0, y1)
            for x in range(x0, max(x0 + 1, x1 - 4))
            for r, g, b in [px[x, y]]
            if 190 <= r <= 236 and abs(r - g) < 15 and abs(g - b) < 15
        ]
        if len(pill) < 40:
            return None
        xs = [p[0] for p in pill]
        ys = [p[1] for p in pill]
        if not (18 <= max(xs) - min(xs) <= 60 and 8 <= max(ys) - min(ys) <= 28):
            return None
        return "off", (min(xs) + max(xs)) // 2, (min(ys) + max(ys)) // 2
    if not whites and green < 15:
        return None
    if whites:
        cy = sorted(y for _, y in whites)[len(whites) // 2]
        knob_mid = sorted(x for x, _ in whites)[len(whites) // 2]
    else:
        cy = row_y
        knob_mid = (x0 + x1) // 2
    track_left, track_right = x0 + 15, x1 - 15
    if green >= 20 and knob_mid >= (track_left + track_right) // 2 - 8:
        return "on", track_left + 8, cy
    return "off", track_right - 8, cy


def mcp_done_pos(shot: Path) -> tuple[int, int] | None:
    hit = find_anchor(ocr_words(shot), "mcp-done")
    if hit:
        return hit
    # Рядом с Reload (OCR стабилен). Done бывает синей или чёрной
    # (26.11.2026 mcp-cfg-105019: чёрная кнопка x 1089–1142).
    reload_y = None
    reload_x = 900
    for x, y, w, h, _c, t in ocr_words(shot):
        if _norm_tok(t) == "reload" and 700 <= x <= 950:
            reload_y = y + h // 2
            reload_x = x + w
            break
    if Image is None:
        return None
    im = Image.open(shot).convert("RGB")
    px = im.load()
    w, h = im.size
    y0 = max(600, (reload_y - 40) if reload_y else 640)
    y1 = min(h - 1, (reload_y + 40) if reload_y else 820)
    blues: list[tuple[int, int]] = []
    for y in range(y0, y1):
        for x in range(1000, min(1250, w)):
            r, g, b = px[x, y]
            if b > r + 40 and b > 150 and g > 100:
                blues.append((x, y))
    if len(blues) >= 40:
        xs = [p[0] for p in blues]
        ys = [p[1] for p in blues]
        return sum(xs) // len(xs), sum(ys) // len(ys)
    darks: list[tuple[int, int]] = []
    x_from = max(1000, reload_x + 40)
    for y in range(y0, y1):
        for x in range(x_from, min(1250, w)):
            r, g, b = px[x, y]
            if r < 60 and g < 60 and b < 60:
                darks.append((x, y))
    if len(darks) < 40:
        return None
    xs = [p[0] for p in darks]
    ys = [p[1] for p in darks]
    if max(xs) - min(xs) > 90 or max(ys) - min(ys) > 40:
        return None
    return (min(xs) + max(xs)) // 2, (min(ys) + max(ys)) // 2


def _atomic_write(path: Path, text: str, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    try:
        tmp.write_text(text, encoding="utf-8")
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            tmp.unlink()


def merge_mcp_json(
    path: Path,
    name: str,
    *,
    command: str | None = None,
    args: list[str] | None = None,
    url: str | None = None,
    transport: str = "stdio",
) -> None:
    """Добавить/обновить сервер в mcp.json. Токены/env не трогаем."""
    data: dict = {"mcpServers": {}}
    if path.is_file():
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict) and isinstance(loaded.get("mcpServers"), dict):
                data = loaded
        except (OSError, json.JSONDecodeError) as e:
            raise SystemExit(f"mcp.json битый {path}: {e}") from e
    servers = data.setdefault("mcpServers", {})
    if not isinstance(servers, dict):
        raise SystemExit(f"mcp.json: mcpServers не объект в {path}")
    prev = servers.get(name)
    entry = dict(prev) if isinstance(prev, dict) else {}
    if url:
        entry["url"] = url
        if transport:
            entry["type"] = transport
        entry.pop("command", None)
        entry.pop("args", None)
    else:
        if not command:
            raise SystemExit("mcp add: нужен --command или --url")
        entry["type"] = "stdio"
        entry["command"] = command
        entry["args"] = list(args or [])
        entry.pop("url", None)
    servers[name] = entry
    text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    if path.exists():
        mode = path.stat().st_mode & 0o777
    else:
        mode = 0o600
    _atomic_write(path, text, mode)


def palette_is_open(text: str) -> bool:
    """Палитра открыта по заголовку, не по одним словам chats и files."""
    low = text.lower()
    hits = sum(t in low for t in ("search agents", "projects", "actions", "settings"))
    if "search chats" in low or "search agents" in low or hits >= 3:
        return True
    return False


def palette_text_confirms(text: str, expected_name: str, extra: str | None = None) -> bool:
    """Имя или bc-id на палитре. Подстрока короче 12 символов не подтверждает."""
    low = text.lower().replace(" ", "")
    name = expected_name.strip()
    token = name.lower()
    bits = [token] if len(token) <= 16 else [token, " ".join(token.split()[:2])]
    if extra:
        bits.append(extra.strip())
        bits.append(extra.strip()[:20])

    def _squash(s: str) -> str:
        s = re.sub(r"[^0-9a-zа-яё]", "", s.lower())
        return s.translate(str.maketrans("1l0", "iio"))

    low_nodash = low.replace("-", "")
    low_squash = _squash(text)
    for b in bits:
        if not b:
            continue
        bl = b.lower()
        compact = re.sub(r"[^0-9a-zа-яё]", "", bl)
        # Короткое имя и пятибуквенный мусор OCR Return не подтверждают.
        if len(compact) < 12 and not bare_uuid(bl):
            continue
        if len(compact) >= 12 and (bl in text.lower() or bl.replace(" ", "") in low):
            return True
        if len(compact) >= 12 and compact[:12] in low_nodash:
            return True
        bare = bare_uuid(bl)
        if bare and bare.replace("-", "")[:12] in low_nodash:
            return True
        sq = _squash(bl)
        if len(sq) >= 12 and sq in low_squash:
            return True
    return False


def search_palette_ok(shot: Path, expected_name: str, extra: str | None = None) -> None:
    """Палитра Search Agents: есть Results с именем или bc-id, не один New agent."""
    from PIL import Image

    im = Image.open(shot)
    w, h = im.size
    crop = im.crop((int(w * 0.28), int(h * 0.22), int(w * 0.72), int(h * 0.72)))
    tmp = shot.with_name(shot.stem + "-palette.png")
    crop.save(tmp)
    text = ocr_image(tmp)
    found = palette_text_confirms(text, expected_name, extra)
    if not found:
        raise SystemExit(
            "Search Agents не показал сессию "
            f"{expected_name!r}. Не подтверждаю Return (иначе будет New agent).\n"
            f"OCR:\n{text[:400]}"
        )


def agent_on_host(a: dict, host: str) -> bool:
    """Сессия этой машины: local-rc @ host или локальный путь без чужого @."""
    pw = a.get("privateWorkerDisplayName") or ""
    ws = a.get("workspaceRootPath") or ""
    if pw.endswith(f"@ {host}"):
        return True
    if " @ " in pw:
        return False
    return local_workspace(ws)


def pick_handoff_agent(
    agents: list[dict], since_ms: int | None, uuid: str | None
) -> dict | None:
    """Uuid конвертации, если его дали. Иначе самая новая сессия с since_ms."""
    if uuid:
        uid = str(uuid).removeprefix("bc-").strip()
        hits = [
            a
            for a in agents
            if (a.get("bcId") or "").removeprefix("bc-") == uid
        ]
        return hits[0] if hits else None
    pool = list(agents)
    if since_ms:
        pool = [a for a in pool if int(a.get("createdAt") or 0) >= since_ms]
    if not pool:
        return None
    return max(pool, key=lambda a: int(a.get("createdAt") or 0))


def handoff_failure(a: dict, expected: str) -> str | None:
    kind = classify(a)
    ws = a.get("workspaceRootPath") or ""
    pw = a.get("privateWorkerDisplayName") or ""
    if kind == "environment":
        return (
            "handoff-ok: это Environment/GitHub (logicalEnvironment или "
            "/workspace), не локальный RC. Пикер 3.23 сматчил Recents/"
            "репо, не каталог на диске. Rename и повторный handoff теми "
            "же кликами запрещены."
        )
    if kind != "local-rc":
        return f"handoff-ok: class={kind}, ждали local-rc"
    if ws != expected:
        return f"handoff-ok: workspaceRootPath={ws!r} ждали {expected!r}"
    if expected.rstrip("/") not in pw:
        return f"handoff-ok: worker {pw!r} не содержит папку {expected}"
    return None


def newest_for_workspace(ws: str, since_ms: int | None = None) -> dict | None:
    agents = load_agents()
    hits = [
        a
        for a in agents
        if classify(a) == "local-rc" and (a.get("workspaceRootPath") or "") == ws
    ]
    if since_ms:
        hits = [a for a in hits if int(a.get("createdAt") or 0) >= since_ms]
    if not hits:
        return None
    return max(hits, key=lambda a: int(a.get("createdAt") or 0))


def stop_pos_from_shot(
    shot: Path, *, allow_round_fallback: bool = True
) -> tuple[int, int] | None:
    """Кнопка Stop у выполняющейся сессии (не сайдбар).

    allow_round_fallback=False — только слово Stop (для convert/ожидания READY:
    круглая кнопка у follow-up даёт ложное срабатывание).
    """
    words = ocr_words(shot)
    hits = [
        (x, y, w, h)
        for x, y, w, h, _c, t in words
        if t.lower() == "stop" and x > 250 and 40 < y < 900
    ]
    if hits:
        x, y, w, h = hits[0]
        return x + w // 2, y + h // 2
    if not allow_round_fallback:
        return None
    # Environment setup: слова Stop нет, стоп — круглая кнопка справа
    # от follow-up (bc-…, клик 1310,1019 → status=2).
    blobs = [
        (x, y, w, h)
        for x, y, w, h, _c, t in words
        if 980 < y < 1045 and x > 1100 and w < 80
    ]
    if not blobs:
        return None
    x, y, w, h = max(blobs, key=lambda b: b[0])
    return x + w // 2, y + h // 2


# Settings → Agents, только чтение. Замер 22.11.2026, glass 1920×1080, Cursor 3.30.14.
# Тумблер — пиксели дорожки справа (зелёная = on, серая = off). OCR слова on/off нет.
# Клик разрешён только в точки, которые возвращает settings_click_pos.

_AGENTS_ROWS: list[dict] = [
    {"key": "submit_ctrl_enter", "kind": "toggle", "any": [("Submit", "Ctrl")]},
    {"key": "default_environment", "kind": "choice", "any": [("Default", "Environment")]},
    {"key": "default_model", "kind": "choice", "any": [("Default", "Model")]},
    # Заголовок «New Messages» OCR рвёт (на живом снимке осталось «EOE»).
    # Устойчивая строка — описание «messages sent while Agent is working».
    {"key": "new_messages", "kind": "choice", "any": [("New", "Messages"), ("while", "working")]},
    {"key": "manual_queue", "kind": "choice", "any": [("Manually", "Queue"), ("Manually", "Sent")]},
    {"key": "usage_summary", "kind": "choice", "any": [("Usage", "Summary")]},
    {"key": "auto_approve_mode", "kind": "toggle", "any": [("Auto-Approve",), ("Approve", "Mode")]},
    {"key": "third_party_imports", "kind": "toggle", "any": [("Third-Party",), ("Third", "Party")]},
    {"key": "import_claude", "kind": "toggle", "any": [("Claude", "Conversations"), ("Claude", "Code")]},
    {
        "key": "remote_control",
        "kind": "toggle",
        "any": [("Enable", "Remote"), ("Remote", "computer")],
    },
    {
        "key": "register_computers",
        "kind": "toggle",
        "any": [("Automatically", "register"), ("register", "computers")],
    },
    {"key": "keep_awake", "kind": "toggle", "any": [("Keep", "Awake"), ("Computer", "Awake")]},
    {
        "key": "self_hosted_workers",
        "kind": "toggle",
        "any": [("self-hosted",), ("hosted", "workers"), ("local", "workers")],
    },
    {"key": "web_search", "kind": "toggle", "any": [("Web", "Search", "Tool")]},
    {"key": "auto_accept_web_search", "kind": "toggle", "any": [("Auto-Accept",), ("Accept", "Web")]},
    {"key": "web_fetch", "kind": "toggle", "any": [("Web", "Fetch")]},
    {"key": "wait_mcp_auth", "kind": "toggle", "any": [("MCP", "Authentication"), ("Wait", "MCP")]},
    {"key": "sync_skills_cloud", "kind": "toggle", "any": [("Sync", "Skills")]},
    {"key": "run_mode", "kind": "choice", "any": [("Run", "Mode")]},
    {"key": "read_access", "kind": "choice", "any": [("Read", "Access")]},
    {
        "key": "file_deletion_protection",
        "kind": "toggle",
        "any": [("File-Deletion",), ("Deletion", "Protection")],
    },
    {
        "key": "external_file_protection",
        "kind": "toggle",
        "any": [("External", "Protection"), ("External-File",)],
    },
    {"key": "legacy_terminal", "kind": "toggle", "any": [("Legacy", "Terminal")]},
]

# Эти ключи обязаны найтись, иначе settings agents — отказ, а не дырявый отчёт.
AGENTS_SETTINGS_REQUIRED = (
    "remote_control",
    "self_hosted_workers",
    "run_mode",
    "read_access",
    "external_file_protection",
    "file_deletion_protection",
    "web_search",
    "wait_mcp_auth",
    "new_messages",
)

# Печать settings agents. Ключ остаётся в коде, в строке — устойчивое имя.
AGENTS_SETTINGS_LABELS = {
    "remote_control": "Remote Control",
    "self_hosted_workers": "self-hosted workers",
    "new_messages": "New Messages",
    "run_mode": "Run Mode",
    "read_access": "Read Access",
    "file_deletion_protection": "File-Deletion Protection",
    "external_file_protection": "External-File Protection",
    "web_search": "Web Search",
    "wait_mcp_auth": "Wait for MCP Authentication",
    "computer_use_apps": "Computer Use",
    "legacy_terminal": "Legacy Terminal",
}


def format_settings_report(merged: dict[str, tuple[str, str]]) -> list[str]:
    order = [spec["key"] for spec in _AGENTS_ROWS] + [
        "allowlist_options",
        "computer_use_apps",
    ]
    lines: list[str] = []
    for key in order:
        if key not in merged:
            continue
        value, detail = merged[key]
        label = AGENTS_SETTINGS_LABELS.get(key, key)
        lines.append(f"{label}\t{value}\t{detail}")
    return lines


def settings_target_forbidden(
    words: list[tuple[int, int, int, int, float, str]], x: int, y: int, step: str
) -> bool:
    """Точка настроек попадает в запретную подпись."""
    if _near_token(words, x, y, {"unregister", "logout", "docs", "build", "manage"}, radius=42):
        return True
    if step == "agents-nav" and _near_token(words, x, y, {"cloud"}, radius=28):
        return True
    return False


def _label_eq(got: str, want: str) -> bool:
    """Равенство подписи. Не подстрока: «register» не должен совпасть с Unregister."""
    a = _compact_name(got)
    b = _compact_name(want)
    if not a or not b:
        return False
    if a == b:
        return True
    # External-ile, File-Deletion, self-hosted слипаются в один токен.
    return len(b) >= 6 and a.startswith(b)


def _band_has(
    words: list[tuple[int, int, int, int, float, str]],
    tokens: tuple[str, ...],
    *,
    x0: int,
    x1: int,
    y0: int,
    y1: int,
    slack: int = 16,
) -> tuple[int, int, int, int] | None:
    """Все токены в одной строке. Первое совпадение каждого слова не годится:
    «Default» встречается и у Environment, и у Model."""
    pools: list[list[tuple[int, int, int, int]]] = []
    for tok in tokens:
        hits: list[tuple[int, int, int, int]] = []
        for x, y, w, h, _c, t in words:
            cx, cy = x + w // 2, y + h // 2
            if x0 <= cx <= x1 and y0 <= cy <= y1 and _label_eq(t, tok):
                hits.append((x, y, w, h))
        if not hits:
            return None
        pools.append(hits[:8])
    best: tuple[int, list[tuple[int, int, int, int]]] | None = None

    def walk(i: int, acc: list[tuple[int, int, int, int]]) -> None:
        nonlocal best
        if i == len(pools):
            ys = [b[1] for b in acc]
            span = max(ys) - min(ys)
            if span <= slack and (best is None or span < best[0]):
                best = (span, list(acc))
            return
        for hit in pools[i]:
            acc.append(hit)
            walk(i + 1, acc)
            acc.pop()

    walk(0, [])
    if best is None:
        return None
    boxes = best[1]
    x0b = min(b[0] for b in boxes)
    y0b = min(b[1] for b in boxes)
    x1b = max(b[0] + b[2] for b in boxes)
    y1b = max(b[1] + b[3] for b in boxes)
    return x0b, y0b, x1b - x0b, y1b - y0b


def _content_words(
    words: list[tuple[int, int, int, int, float, str]],
) -> list[tuple[int, int, int, int, float, str]]:
    return [w for w in words if w[0] >= 360]


def read_toggle(im: object, y: int, x0: int = 1330, x1: int = 1480) -> str | None:
    """on/off по цвету дорожки на строке подписи. None — дорожки в полосе нет."""
    if Image is None or im is None:
        return None
    px = im.load()
    width, height = im.size
    best: tuple[int, str] | None = None
    # Дорожка иногда на 40 px ниже первой строки подписи (карточка Third-Party).
    for yy in range(max(0, y - 14), min(height, y + 58)):
        green_xs: list[int] = []
        gray_xs: list[int] = []
        for x in range(x0, min(x1, width)):
            r, g, b = px[x, yy]
            if g > r + 30 and g > 120 and g > b:
                green_xs.append(x)
            elif 200 <= r <= 230 and abs(r - g) < 10 and abs(g - b) < 10:
                gray_xs.append(x)
        state = None
        if len(green_xs) >= 12 and green_xs[-1] - green_xs[0] <= 48:
            state = "on"
        elif len(gray_xs) >= 12 and 16 <= gray_xs[-1] - gray_xs[0] <= 48:
            state = "off"
        if state is None:
            continue
        dist = abs(yy - y)
        if best is None or dist < best[0]:
            best = (dist, state)
    return None if best is None else best[1]


def _clean_choice(text: str) -> str:
    parts: list[str] = []
    for raw in text.replace("»", " ").replace("¥", " ").replace("~", " ").split():
        comp = _compact_name(raw)
        if len(comp) < 2:
            continue
        parts.append(raw.strip("‘'\"`~»¥|›<"))
    return " ".join(p for p in parts if p)


def _choice_value(
    shot: Path,
    y: int,
    y_hi: int | None,
) -> str:
    """Выпадающий список — вырезка справа от подписи, не абзац описания.

    Сначала строка самой подписи («Last Used»). Если там пусто, блок ниже
    до следующей подписи: у Run Mode значение сидит на второй строке карточки.
    """
    boxes = [(1260, y - 22, 1680, y + 32)]
    floor = y + 100
    if y_hi is not None:
        floor = min(floor, y_hi - 6)
    if floor > y + 40:
        boxes.append((1180, y + 24, 1700, floor))
    for box in boxes:
        text = _clean_choice(_ocr_crop(shot, box, psm=7))
        comp = _compact_name(text)
        if 3 <= len(comp) <= 48 and len(text.split()) <= 6:
            return text
    return "unseen"


def _row_hit(
    words: list[tuple[int, int, int, int, float, str]], spec: dict
) -> tuple[int, int, int, int] | None:
    content = _content_words(words)
    for group in spec["any"]:
        # Подпись живёт в колонке текста, не в значении справа и не в сайдбаре.
        box = _band_has(content, group, x0=360, x1=1280, y0=40, y1=1040, slack=22)
        if box:
            return box
    return None


def agents_settings_bottom(words: list[tuple[int, int, int, int, float, str]]) -> bool:
    """Низ страницы Agents. Слово Allowlists в абзаце Run Mode — ещё не низ."""
    if _band_has(
        words, ("Allowlist", "Options"), x0=360, x1=1500, y0=40, y1=1040, slack=20
    ):
        return True
    blob = "".join(_compact_name(t) for *_b, t in words)
    return "alwaysallowed" in blob


def agents_settings_from_shot(shot: Path) -> dict[str, tuple[str, str]]:
    """key → (value, detail). Пустой dict, если это не страница настроек."""
    words = ocr_words(shot, psm=6)
    if not _settings_page(words):
        return {}
    im = Image.open(shot).convert("RGB") if Image is not None else None
    found: list[tuple[dict, tuple[int, int, int, int]]] = []
    for spec in _AGENTS_ROWS:
        box = _row_hit(words, spec)
        if box:
            found.append((spec, box))
    found.sort(key=lambda item: item[1][1])
    out: dict[str, tuple[str, str]] = {}
    for i, (spec, box) in enumerate(found):
        _x, y, _w, h = box
        mid = y + h // 2
        y_hi = found[i + 1][1][1] if i + 1 < len(found) else None
        if spec["kind"] == "toggle":
            state = read_toggle(im, mid) if im is not None else None
            value = state or "unseen"
        else:
            value = _choice_value(shot, mid, y_hi)
        detail = ""
        if spec["key"] == "remote_control":
            link = any(
                _label_eq(t, "Connected") and abs(yy - mid) < 40 and xx > 400
                for xx, yy, _w, _h, _c, t in words
            )
            detail = "Connected" if link else "no Connected label"
        out[spec["key"]] = (value, detail)
    content = _content_words(words)
    if agents_settings_bottom(content):
        blob = " ".join(_norm_tok(t) for *_b, t in content).lower()
        flat = blob.replace(" ", "").replace("-", "")
        if "noalways" in flat or "no always" in blob:
            out["computer_use_apps"] = ("none", "No always-allowed apps")
        elif "always" in blob and "allowed" in blob:
            out["computer_use_apps"] = ("listed", "")
        out["allowlist_options"] = ("collapsed", "секцию не раскрываем")
    return out


def merge_agents_settings(
    shots: list[Path],
) -> dict[str, tuple[str, str]]:
    merged: dict[str, tuple[str, str]] = {}
    for shot in shots:
        for key, val in agents_settings_from_shot(shot).items():
            prev = merged.get(key)
            if prev is None or prev[0] in {"unseen", ""}:
                merged[key] = val
            elif val[0] not in {"unseen", ""} and prev[1] == "" and val[1]:
                merged[key] = (prev[0], val[1])
    return merged


def _near_token(
    words: list[tuple[int, int, int, int, float, str]],
    x: int,
    y: int,
    names: set[str],
    radius: int = 36,
) -> str | None:
    for wx, wy, ww, wh, _c, t in words:
        cx, cy = wx + ww // 2, wy + wh // 2
        if abs(cx - x) <= radius and abs(cy - y) <= radius and _norm_tok(t) in names:
            return _norm_tok(t)
    return None


def _settings_page(words: list[tuple[int, int, int, int, float, str]]) -> bool:
    # Поле поиска OCR иногда сливает в один мусорный токен. Якорь страницы —
    # Back слева сверху и пункт General в навигации.
    back = _band_has(words, ("Back",), x0=0, x1=160, y0=30, y1=110, slack=8)
    general = any(
        _label_eq(t, "General") and x < 220 and 110 < y < 230
        for x, y, _w, _h, _c, t in words
    )
    return bool(back) and general


def settings_click_pos(shot: Path, step: str) -> tuple[int, int] | None:
    """Точка клика шага открытия Settings → Agents. None — шаг не узнан или точка запрещена.

    step: file | settings-item | agents-nav | back | page
    page не кликается: (0, 0) значит «страница настроек уже открыта».
    """
    words = ocr_words(shot, psm=6)
    if step == "page":
        return (0, 0) if _settings_page(words) else None
    point: tuple[int, int] | None = None
    if step == "file":
        box = _band_has(words, ("File",), x0=20, x1=90, y0=0, y1=36, slack=8)
        if box:
            point = (box[0] + box[2] // 2, box[1] + box[3] // 2)
    elif step == "settings-item":
        # Меню File, не меню проекта (Log Out / Manage Environment).
        exit_box = _band_has(words, ("Exit",), x0=0, x1=200, y0=230, y1=340, slack=8)
        item = _band_has(words, ("Settings",), x0=0, x1=200, y0=180, y1=280, slack=8)
        logout = _near_token(words, 80, 250, {"logout", "log"}, radius=80)
        manage = any(
            _norm_tok(t) == "manage" and x < 280 and y < 400
            for x, y, _w, _h, _c, t in words
        )
        if exit_box and item and not logout and not manage:
            point = (item[0] + item[2] // 2, item[1] + item[3] // 2)
    elif step == "agents-nav":
        if not _settings_page(words):
            return None
        # Строка Agents, не Cloud Agents (та открывает браузер).
        # Иконка слипается с буквой: OCR даёт «gents», а полное «Agents» остаётся
        # только у строки Cloud Agents.
        cands = []
        for x, y, w, h, _c, t in words:
            comp = _compact_name(t)
            if x > 220 or not (180 <= y <= 340):
                continue
            if comp != "agents" and not (comp.endswith("gents") and len(comp) <= 8):
                continue
            cloud = any(
                _label_eq(t2, "Cloud") and abs(y2 - y) < 16 and x2 < 220
                for x2, y2, _w2, _h2, _c2, t2 in words
            )
            if cloud:
                continue
            cands.append((x + w // 2, y + h // 2))
        if cands:
            point = cands[0]
    elif step == "back":
        box = _band_has(words, ("Back",), x0=0, x1=160, y0=30, y1=100, slack=8)
        if box and _settings_page(words):
            point = (box[0] + box[2] // 2, box[1] + box[3] // 2)
    else:
        return None
    if point is None:
        return None
    if settings_target_forbidden(words, point[0], point[1], step):
        return None
    return point


def main(argv: list[str]) -> int:
    cmd = argv[1] if len(argv) > 1 else "help"
    if cmd == "resolve":
        # glass_agents.py resolve --id X | --from Y | --current
        bc_id = from_name = None
        current = False
        args = argv[2:]
        i = 0
        while i < len(args):
            if args[i] in ("--id", "-i") and i + 1 < len(args):
                bc_id = args[i + 1]
                i += 2
            elif args[i] in ("--from", "-f") and i + 1 < len(args):
                from_name = args[i + 1]
                i += 2
            elif args[i] in ("--current", "-c"):
                current = True
                i += 1
            else:
                print(f"неизвестный аргумент resolve: {args[i]}", file=sys.stderr)
                return 2
        a = resolve(load_agents(), bc_id=bc_id, from_name=from_name, current=current)
        print(a["bcId"])
        print(a.get("name") or "")
        print(a.get("workspaceRootPath") or "")
        return 0
    if cmd == "selected":
        sel, last = selected_ids()
        print(sel or "")
        print(last or "")
        return 0
    if cmd == "palette-ok":
        extra = argv[4] if len(argv) > 4 else None
        search_palette_ok(Path(argv[2]), argv[3], extra)
        return 0
    if cmd == "newest":
        # Только local-rc с workspaceRootPath == ws. Environment с
        # localFsPath облачной сессии сюда не попадает — иначе -n переименует
        # чужой тип сессии (замер 07.10.2026).
        ws = argv[2]
        since = int(argv[3]) if len(argv) > 3 else None
        a = newest_for_workspace(ws, since)
        if not a or classify(a) != "local-rc":
            return 1
        print(a["bcId"])
        print(a.get("name") or "")
        return 0
    if cmd == "show":
        a = resolve(load_agents(), bc_id=argv[2])
        show_agent(a)
        return 0
    if cmd == "created-since":
        since = int(argv[2])
        hits = [
            a
            for a in load_agents()
            if int(a.get("createdAt") or 0) >= since
            and not a.get("isArchived")
            and not a.get("isKilled")
        ]
        if not hits:
            return 1
        hits.sort(key=lambda x: int(x.get("createdAt") or 0), reverse=True)
        for a in hits:
            print(
                f"{a.get('bcId')}\t{classify(a)}\t{a.get('name') or ''}\t"
                f"{a.get('workspaceRootPath') or ''}\t"
                f"{a.get('privateWorkerDisplayName') or ''}\t"
                f"{a.get('cloudTargetKey') or ''}"
            )
        return 0
    if cmd == "handoff-ok":
        # handoff-ok /ABS/WS [since_ms [uuid]]
        # С uuid проверяется эта сессия. Без uuid — новейшая с since_ms.
        expected = argv[2]
        since = None
        uuid = None
        if len(argv) > 3 and argv[3]:
            if argv[3].isdigit():
                since = int(argv[3])
            else:
                uuid = argv[3]
        if len(argv) > 4 and argv[4]:
            uuid = argv[4]
        a = pick_handoff_agent(load_agents(), since, uuid)
        if a is None:
            print("handoff-ok: нет сессии для проверки", file=sys.stderr)
            return 1
        show_agent(a)
        err = handoff_failure(a, expected)
        if err:
            print(err, file=sys.stderr)
            return 1
        return 0
    if cmd == "inventory":
        sel, _last = selected_ids()
        for line in inventory_lines(load_agents(), sel):
            print(line)
        return 0
    if cmd == "names-changed":
        # names-changed BEFORE_FILE AFTER_FILE NEW_ID
        if len(argv) < 5:
            print("names-changed BEFORE AFTER NEW_ID", file=sys.stderr)
            return 2
        changes = foreign_name_changes(
            Path(argv[2]).read_text(encoding="utf-8"),
            Path(argv[3]).read_text(encoding="utf-8"),
            argv[4],
        )
        for line in changes:
            print(line)
        return 1 if changes else 0
    if cmd == "mine":
        # RC @ host (по одной свежей на папку) + локальные чаты без bc-/без worker.
        # Колонки: id TAB name TAB ws TAB kind TAB working
        # kind=local-rc|local; working=1|0|?  (локальный без записи — '?')
        host = argv[2]
        agents = load_agents()
        best: dict[str, dict] = {}
        for a in agents:
            if a.get("isArchived") or a.get("isKilled"):
                continue
            pw = a.get("privateWorkerDisplayName") or ""
            ws = a.get("workspaceRootPath") or ""
            if not ws or not pw.endswith(f"@ {host}"):
                continue
            if ws not in best or (a.get("updatedAt") or 0) > (
                best[ws].get("updatedAt") or 0
            ):
                best[ws] = a
        for ws, a in sorted(best.items()):
            working = "1" if a.get("status") == 1 else "0"
            print(
                f"{a['bcId']}\t{a.get('name') or ''}\t{ws}\tlocal-rc\t{working}"
            )
        sel, _last = selected_ids()
        uid = bare_uuid(sel)
        printed: set[str] = set()
        for a in best.values():
            u = bare_uuid(a.get("bcId"))
            if u:
                printed.add(u)
        # Локальные / private-incomplete на диске: без «@ host» и без чужого «@ ».
        for a in agents:
            if a.get("isArchived") or a.get("isKilled"):
                continue
            ws = a.get("workspaceRootPath") or ""
            pw = a.get("privateWorkerDisplayName") or ""
            if not ws or pw.endswith(f"@ {host}"):
                continue
            if " @ " in pw:
                continue  # RC другой машины (общий аккаунт)
            if not local_workspace(ws):
                continue
            u = bare_uuid(a.get("bcId"))
            if u and u in printed:
                continue
            if u:
                printed.add(u)
            working = "1" if a.get("status") == 1 else "0"
            print(
                f"{a.get('bcId') or ''}\t{a.get('name') or ''}\t{ws}\tlocal\t{working}"
            )
        # Выделенный uuid без записи / без worker @ host — не мусор (до convert).
        # Чужой «@ other-host» не показываем.
        if uid and uid not in printed:
            a = agent_by_uuid(agents, uid)
            pw = (a or {}).get("privateWorkerDisplayName") or ""
            if " @ " in pw and not pw.endswith(f"@ {host}"):
                return 0
            if a is None or not pw.endswith(f"@ {host}"):
                ws = (a or {}).get("workspaceRootPath") or ""
                name = (a or {}).get("name") or ""
                working = "?"
                if a is not None:
                    working = "1" if a.get("status") == 1 else "0"
                print(f"{uid}\t{name}\t{ws}\tlocal\t{working}")
        return 0
    if cmd == "palette-open":
        # Открыта ли палитра Search Agents (Ctrl+Alt+P) — до вставки bc-id.
        # Не открылась, а вставили — id уходит в поле ввода открытой сессии (07.10.2026).
        from PIL import Image

        shot = Path(argv[2])
        im = Image.open(shot)
        w, h = im.size
        tmp = shot.with_name(shot.stem + "-palopen.png")
        im.crop((int(w * 0.28), 0, int(w * 0.72), int(h * 0.72))).save(tmp)
        words = ocr_words(tmp)
        low = " ".join(t for *_rest, t in words)
        return 0 if palette_is_open(low) else 1
    if cmd == "composer-pos":
        # Где поле ввода на снимке окна glass (0,0 1920x1080): «x y» или код 1.
        # Новый чат — якорь plan-idea (кнопка Idea, поле ~90 px выше).
        # Переписка 3.23 — футер «/path @ <host>» внизу (поле ~38 px выше).
        # Переписка 3.30 — футер стал «This Computer (Self-Hosted Worker)»,
        #   «@ host» пропал; поле ввода — по плейсхолдеру «Send follow-up»
        #   (якорь send-follow-up, Cursor 3.30).
        shot, host = Path(argv[2]), argv[3]
        hit = composer_click(ocr_words(shot), host)
        if not hit:
            return 1
        print(hit[0], hit[1])
        return 0
    if cmd == "anchor":
        # anchor SHOT имя-якоря → «x y» или код 1
        shot, name = Path(argv[2]), argv[3]
        if name not in ANCHORS:
            print(f"неизвестный якорь {name!r}: {', '.join(ANCHORS)}", file=sys.stderr)
            return 2
        hit = find_anchor(ocr_words(shot), name)
        if not hit:
            return 1
        print(hit[0], hit[1])
        return 0
    if cmd == "turn-busy":
        # turn-busy SHOT → 0, если на снимке «Planning next moves».
        shot = Path(argv[2])
        return 0 if turn_still_planning(ocr_words(shot)) else 1
    if cmd == "busy":
        # Работающие агенты: RC @ host (status 1) + локальные status 1 +
        # выделенный локальный uuid без записи (до convert — иначе приняли за мусор).
        # Опционально SHOT: если selected local и на снимке Stop — тоже busy.
        host = argv[2]
        shot = Path(argv[3]) if len(argv) > 3 else None
        agents = load_agents()
        rows: list[tuple[str, str, str]] = []
        seen: set[str] = set()

        def add_row(aid: str, name: str, kind: str) -> None:
            key = bare_uuid(aid) or aid
            if key in seen:
                return
            seen.add(key)
            rows.append((aid, name, kind))

        for a in agents:
            if a.get("status") != 1 or a.get("isArchived") or a.get("isKilled"):
                continue
            pw = a.get("privateWorkerDisplayName") or ""
            ws = a.get("workspaceRootPath") or ""
            if pw.endswith(f"@ {host}"):
                add_row(a.get("bcId") or "", a.get("name") or "", "local-rc")
            elif (
                local_workspace(ws)
                and " @ " not in pw
            ):
                add_row(a.get("bcId") or "", a.get("name") or "", "local")
        sel, _last = selected_ids()
        uid = bare_uuid(sel)
        if uid and uid not in seen:
            a = agent_by_uuid(agents, uid)
            pw = (a or {}).get("privateWorkerDisplayName") or ""
            if " @ " in pw and not pw.endswith(f"@ {host}"):
                pass  # чужой host
            else:
                localish = a is None or not pw.endswith(f"@ {host}")
                if localish:
                    working = a is not None and a.get("status") == 1
                    if not working and shot and shot.is_file():
                        if stop_pos_from_shot(shot):
                            working = True
                    # Без снимка: unlisted selected = занят (13.10: 50 мин работы).
                    if working or a is None:
                        add_row(
                            sel or uid,
                            (a or {}).get("name") or "",
                            "local",
                        )
        for aid, name, kind in rows:
            print(f"{aid}\t{name}\t{kind}")
        return 0 if rows else 1
    if cmd == "is-archived":
        a = resolve(load_agents(), bc_id=argv[2])
        print("true" if a.get("isArchived") else "false")
        return 0 if a.get("isArchived") else 1
    if cmd == "stop-pos":
        # Кнопка Stop у выполняющейся сессии (не сайдбар).
        # stop-pos SHOT [--strict]  --strict = только слово Stop, без круглой кнопки.
        shot = Path(argv[2])
        strict = len(argv) > 3 and argv[3] in ("--strict", "strict")
        pos = stop_pos_from_shot(shot, allow_round_fallback=not strict)
        if not pos:
            return 1
        print(pos[0], pos[1])
        return 0
    if cmd == "overlay-scan":
        # overlay-scan SHOT → строки kind [x y]; код 0=есть dismiss, 3=move-working, 1=чисто.
        # move-working: жать только Cancel (координаты) или Escape; Stop and Move — никогда.
        # expensive-dismiss: крестик тоста; не Manage / Don't show again.
        shot = Path(argv[2])
        words = ocr_words(shot)
        # Только модалка: в ленте чата тоже бывает «Move agent while it's working?»
        # (GAP-002 текст) — без кнопки Cancel в зоне это ложное срабатывание.
        if find_anchor(words, "move-working"):
            cancel = find_anchor(words, "move-cancel")
            if cancel:
                print(f"move-working\t{cancel[0]}\t{cancel[1]}")
                return 3
        dismiss = find_expensive_dismiss(words)
        if dismiss:
            print(f"expensive-dismiss\t{dismiss[0]}\t{dismiss[1]}")
            return 0
        return 1
    if cmd == "menu-pos":
        # menu-pos SHOT Слово: центр пункта контекстного меню сайдбара (точное слово,
        # x 90–460). Для Rename; Archive — отдельный archive-pos (не «All Below»).
        shot, word = Path(argv[2]), argv[3]
        for x, y, w, h, _c, t in ocr_words(shot):
            if t == word and 90 <= x <= 460:
                print(x + w // 2, y + h // 2)
                return 0
        return 1
    if cmd == "text-has":
        # text-has SHOT NEEDLE → 0, если OCR содержит иголку. Текст снимка не печатает.
        if len(argv) < 4:
            print("text-has SHOT NEEDLE", file=sys.stderr)
            return 2
        text = ocr_image(Path(argv[2]))
        needle = argv[3]
        compact = re.sub(r"[^A-Za-z0-9-]", "", text)
        return 0 if needle in text or needle in compact else 1
    if cmd == "discard-pos":
        shot = Path(argv[2])
        pos = discard_menu_click(ocr_words(shot))
        if not pos:
            return 1
        print(pos[0], pos[1])
        return 0
    if cmd == "archive-pos":
        # Клик Archive в контекстном меню сайдбара, не «Archive All Below».
        hit = archive_menu_click(ocr_words(Path(argv[2])))
        if not hit:
            return 1
        print(hit[0], hit[1])
        return 0
    if cmd == "row-name":
        # row-name SHOT Y ИМЯ → 0, если имя есть в этой строке сайдбара.
        shot = Path(argv[2])
        y = int(argv[3])
        name = argv[4]
        return 0 if sidebar_row_matches(ocr_words(shot), y, name) else 1
    if cmd == "convert-ok":
        # convert-ok UUID /ABS/WS → 0 local-rc этой папки, 1 нет в sqlite,
        # 2 есть (часто промежуточный environment), ещё не local-rc.
        uuid = argv[2].removeprefix("bc-").strip()
        expected = argv[3]
        hits = [
            a
            for a in load_agents()
            if (a.get("bcId") or "").removeprefix("bc-") == uuid
        ]
        if not hits:
            return 1
        a = hits[0]
        show_agent(a)
        kind = classify(a)
        ws = a.get("workspaceRootPath") or ""
        pw = a.get("privateWorkerDisplayName") or ""
        if kind == "local-rc" and ws == expected and expected in pw:
            return 0
        return 2
    if cmd == "other":
        # Самая свежая сессия ЭТОГО хоста, кроме указанной: куда переключиться,
        # чтобы заново открыть уже выделенную вкладку.
        # other BC-ID HOSTNAME
        skip = argv[2]
        host = argv[3] if len(argv) > 3 else ""
        if not host:
            print("other: нужен хост вторым аргументом", file=sys.stderr)
            return 2
        cand = [
            a for a in load_agents()
            if a.get("bcId") != skip
            and not a.get("isArchived")
            and not a.get("isKilled")
            and agent_on_host(a, host)
        ]
        if not cand:
            return 1
        a = max(cand, key=lambda x: x.get("updatedAt") or 0)
        print(a["bcId"])
        print(a.get("name") or "")
        return 0
    if cmd == "mcp-list":
        # mcp-list SHOT [known,name,…]: строки вкладки MCPs (tsv name status detail x y)
        shot = Path(argv[2])
        known = argv[3].split(",") if len(argv) > 3 and argv[3] else None
        rows = mcp_list_from_shot(shot, known)
        for r in rows:
            print(f"{r['name']}\t{r['status']}\t{r['detail']}\t{r['x']}\t{r['y']}")
        return 0 if rows else 1
    if cmd == "mcp-row-pos":
        shot, name = Path(argv[2]), argv[3]
        known = argv[4].split(",") if len(argv) > 4 and argv[4] else None
        pos = mcp_row_pos(shot, name, known)
        if not pos:
            return 1
        print(pos[0], pos[1])
        return 0
    if cmd == "mcp-toggle":
        # mcp-toggle SHOT → state click_x click_y  (state=on|off; клик переключает)
        shot = Path(argv[2])
        got = mcp_source_toggle(shot)
        if not got:
            return 1
        state, x, y = got
        print(state, x, y)
        return 0
    if cmd == "mcp-done-pos":
        pos = mcp_done_pos(Path(argv[2]))
        if not pos:
            return 1
        print(pos[0], pos[1])
        return 0
    if cmd == "mcp-merge-json":
        # mcp-merge-json PATH NAME --command CMD [--arg A ...] | --url URL
        path, name = Path(argv[2]), argv[3]
        command = url = None
        args: list[str] = []
        transport = "stdio"
        i = 4
        while i < len(argv):
            if argv[i] == "--command" and i + 1 < len(argv):
                command = argv[i + 1]
                i += 2
            elif argv[i] == "--url" and i + 1 < len(argv):
                url = argv[i + 1]
                i += 2
            elif argv[i] == "--arg" and i + 1 < len(argv):
                args.append(argv[i + 1])
                i += 2
            elif argv[i] == "--type" and i + 1 < len(argv):
                transport = argv[i + 1]
                i += 2
            else:
                print(f"mcp-merge-json: неизвестный аргумент {argv[i]}", file=sys.stderr)
                return 2
        merge_mcp_json(
            path, name, command=command, args=args, url=url, transport=transport
        )
        print(path)
        return 0
    if cmd == "agents-settings":
        # agents-settings SHOT [SHOT...]: key, value, detail. Код 1, если нет обязательных ключей.
        shots = [Path(p) for p in argv[2:]]
        if not shots:
            print("agents-settings: нужен снимок", file=sys.stderr)
            return 2
        merged = merge_agents_settings(shots)
        if not merged:
            print("agents-settings: на снимках нет страницы Settings", file=sys.stderr)
            return 1
        for line in format_settings_report(merged):
            print(line)
        missing = [k for k in AGENTS_SETTINGS_REQUIRED if k not in merged or merged[k][0] in {"unseen", ""}]
        if missing:
            print("agents-settings: не разобраны " + ",".join(missing), file=sys.stderr)
            return 1
        return 0
    if cmd == "agents-settings-bottom":
        if len(argv) < 3:
            print("agents-settings-bottom SHOT", file=sys.stderr)
            return 2
        shot = Path(argv[2])
        return 0 if agents_settings_bottom(ocr_words(shot, psm=6)) else 1
    if cmd == "settings-pos":
        # settings-pos SHOT file|settings-item|agents-nav|back|page
        if len(argv) < 4:
            print("settings-pos SHOT file|settings-item|agents-nav|back|page", file=sys.stderr)
            return 2
        shot, step = Path(argv[2]), argv[3]
        pos = settings_click_pos(shot, step)
        if pos is None:
            print(f"settings-pos: нет безопасной точки {step}", file=sys.stderr)
            return 1
        if step == "page":
            print("ok")
            return 0
        print(pos[0], pos[1])
        return 0
    print(
        "usage: resolve|selected|palette-ok|newest|mine|inventory|names-changed|other|busy|"
        "composer-pos|palette-open|show|created-since|handoff-ok|"
        "is-archived|archive-pos|discard-pos|menu-pos|stop-pos|anchor|convert-ok|"
        "overlay-scan|"
        "mcp-list|mcp-row-pos|mcp-toggle|mcp-done-pos|mcp-merge-json|"
        "agents-settings|agents-settings-bottom|settings-pos",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
