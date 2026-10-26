"""Only the ledger changes a balance (B03 tasks.md T016, research R4, FR-009).

Every `.py` under `backend/apps` is parsed, and any other code that writes `jenehat` or `bonat`,
saves them, builds or inserts a `LedgerEntry`, or updates the wallet table in raw SQL fails the
test. The economy's and progress' own code also keeps money integral, and the operation handlers
never reach the ORM (research R5).
"""

from __future__ import annotations

import ast
from collections.abc import Iterator
from pathlib import Path

import pytest
from django.conf import settings

APPS = settings.BASE_DIR / "apps"
BALANCES = frozenset({"jenehat", "bonat"})
LEDGER = "apps/economy/services/ledger.py"
THIS = "apps/economy/tests/test_balance_writers.py"

# Paths (relative to backend/) a rule doesn't apply to, and why.
EXEMPT: dict[str, dict[str, str]] = {
    "assign": {
        LEDGER: "the one writer",
        # A content daily-reward day's amounts, not a wallet.
        "apps/content/services/importer.py": "content fields named like the currencies",
    },
    "write": {
        LEDGER: "the one writer",
        THIS: "the scanner's own examples",
        # The database's own guards are tested by inserting what the ledger never would.
        "apps/economy/tests/test_ledger.py": "the CHECK and append-only tests",
        "apps/economy/tests/test_models.py": "the append-only tests",
        "apps/economy/tests/test_invariant.py": "corrupts a wallet on purpose",
    },
}


def relative(path: Path) -> str:
    return path.relative_to(settings.BASE_DIR).as_posix()


def sources() -> Iterator[tuple[str, str]]:
    for path in sorted(APPS.rglob("*.py")):
        yield relative(path), path.read_text(encoding="utf-8")


def exempt(rule: str, name: str) -> bool:
    return name in EXEMPT[rule] or (rule == "write" and "/migrations/" in name)


def _names(node: ast.AST) -> set[str]:
    """String constants of a list or tuple literal."""
    if isinstance(node, (ast.List, ast.Tuple, ast.Set)):
        return {
            e.value for e in node.elts if isinstance(e, ast.Constant) and isinstance(e.value, str)
        }
    return set()


def _callee(call: ast.Call) -> str:
    func = call.func
    if isinstance(func, ast.Name):
        return func.id
    if isinstance(func, ast.Attribute):
        return func.attr
    return ""


def _receiver_chain(call: ast.Call) -> list[str]:
    """`LedgerEntry.objects.bulk_create` → ["LedgerEntry", "objects", "bulk_create"]."""
    parts: list[str] = []
    node: ast.AST = call.func
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
    return parts[::-1]


def _targets(node: ast.AST) -> Iterator[ast.AST]:
    if isinstance(node, ast.Assign):
        for target in node.targets:
            yield from _flatten(target)
    elif isinstance(node, (ast.AugAssign, ast.AnnAssign)):
        yield from _flatten(node.target)


def _flatten(target: ast.AST) -> Iterator[ast.AST]:
    if isinstance(target, (ast.Tuple, ast.List)):
        for element in target.elts:
            yield from _flatten(element)
    else:
        yield target


def violations(name: str, source: str) -> list[str]:
    """What `source` (the file at `name`) does that only the ledger may do."""
    found: list[str] = []
    tree = ast.parse(source, filename=name)
    for node in ast.walk(tree):
        line = f"{name}:{getattr(node, 'lineno', 0)}"
        if not exempt("assign", name):
            for target in _targets(node):
                if isinstance(target, ast.Attribute) and target.attr in BALANCES:
                    found.append(f"{line} assigns .{target.attr}")
        if exempt("write", name):
            continue
        if isinstance(node, ast.Call):
            found.extend(f"{line} {problem}" for problem in _call_problems(node))
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            text = node.value.lower()
            if "economy_wallet" in text and "update" in text:
                found.append(f"{line} updates economy_wallet in raw SQL")
    return found


LEDGER_READS = frozenset({"filter", "get", "all", "aggregate", "values_list", "exists", "count"})


def _call_problems(call: ast.Call) -> Iterator[str]:
    callee = _callee(call)
    keywords = {k.arg: k.value for k in call.keywords if k.arg}
    balance_keywords = BALANCES & set(keywords)
    if callee == "setattr" and len(call.args) > 1 and _names(ast.Tuple([call.args[1]])) & BALANCES:
        yield "setattr of a balance"
    creates = ("update", "create", "get_or_create", "update_or_create", "Wallet")
    if callee in creates and balance_keywords:
        yield f"{callee}() with {sorted(balance_keywords)}"
    saved = keywords.get("update_fields")
    if callee in ("save", "bulk_create") and saved is not None and _names(saved) & BALANCES:
        yield f"{callee}(update_fields=...) names a balance"
    if callee == "bulk_update":
        fields = keywords.get("fields") or (call.args[1] if len(call.args) > 1 else None)
        if fields is not None and _names(fields) & BALANCES:
            yield "bulk_update(fields=...) names a balance"
    chain = _receiver_chain(call)
    builds = callee == "LedgerEntry" or (chain[:2] == ["LedgerEntry", "objects"] and len(chain) > 2)
    if builds and chain[-1] not in LEDGER_READS:
        yield f"{'.'.join(chain)}() outside the ledger"


def test_only_the_ledger_writes_a_balance() -> None:
    found = [v for name, source in sources() for v in violations(name, source)]
    assert found == []


def test_the_exemptions_exist() -> None:
    for paths in EXEMPT.values():
        for path in paths:
            assert (settings.BASE_DIR / path).is_file(), path


@pytest.mark.parametrize(
    "snippet",
    [
        "wallet.jenehat = 5",
        "wallet.bonat += 1",
        "a, wallet.jenehat = 1, 2",
        "setattr(wallet, 'bonat', 3)",
        "Wallet.objects.filter(pk=1).update(jenehat=F('jenehat') + 1)",
        "Wallet.objects.create(player=p, bonat=10)",
        "Wallet(player=p, jenehat=10)",
        "wallet.save(update_fields=['bonat'])",
        "Wallet.objects.bulk_update(rows, ['jenehat'])",
        "Wallet.objects.bulk_update(rows, fields=('bonat',))",
        "LedgerEntry(player=p, delta=1)",
        "LedgerEntry.objects.bulk_create(rows)",
        "LedgerEntry.objects.create(delta=1)",
        "cursor.execute('UPDATE economy_wallet SET bonat = %s', [1])",
    ],
)
def test_the_scanner_catches_a_balance_write(snippet: str) -> None:
    assert violations("apps/somewhere/services/thing.py", snippet)


@pytest.mark.parametrize(
    "snippet",
    [
        "total = wallet.jenehat + 1",
        "wallet.save(update_fields=['fuel', 'timeline_at'])",
        "LedgerEntry.objects.filter(player=p).aggregate(s=Sum('delta'))",
        "cursor.execute('SELECT jenehat FROM economy_wallet')",
    ],
)
def test_the_scanner_lets_reads_through(snippet: str) -> None:
    assert violations("apps/somewhere/services/thing.py", snippet) == []


def test_the_ledger_itself_may_write() -> None:
    assert violations(LEDGER, "wallet.jenehat += delta\nLedgerEntry.objects.bulk_create(e)") == []


# -- integer money in the economy's and progress' code (constitution II) --------------------------

MONEY_PACKAGES = ("apps/economy", "apps/progress")


def money_modules() -> Iterator[tuple[str, ast.Module]]:
    for name, source in sources():
        if not name.startswith(MONEY_PACKAGES) or "/tests/" in name or "/migrations/" in name:
            continue
        yield name, ast.parse(source, filename=name)


def float_problems(name: str, tree: ast.Module) -> Iterator[str]:
    for node in ast.walk(tree):
        line = f"{name}:{getattr(node, 'lineno', 0)}"
        if isinstance(node, (ast.BinOp, ast.AugAssign)) and isinstance(node.op, ast.Div):
            yield f"{line} true division"
        elif isinstance(node, ast.Name) and node.id in ("float", "Decimal"):
            yield f"{line} {node.id}"
        elif isinstance(node, ast.Constant) and isinstance(node.value, float):
            yield f"{line} float literal"
        elif isinstance(node, ast.Attribute) and node.attr in ("FloatField", "DecimalField"):
            yield f"{line} {node.attr}"


def test_economy_and_progress_code_has_no_float_money() -> None:
    found = [p for name, tree in money_modules() for p in float_problems(name, tree)]
    assert found == []


@pytest.mark.parametrize("snippet", ["x = a / 2", "x /= 2", "float(x)", "Decimal('1')", "x = 0.5"])
def test_the_money_scan_catches_floats(snippet: str) -> None:
    assert list(float_problems("apps/economy/services/thing.py", ast.parse(snippet)))


# -- handlers never reach the ORM (research R5) ----------------------------------------------------

OPS = APPS / "economy" / "services" / "ops"


def orm_problems(name: str, tree: ast.Module) -> Iterator[str]:
    for node in ast.walk(tree):
        line = f"{name}:{getattr(node, 'lineno', 0)}"
        if isinstance(node, ast.Attribute) and node.attr == "objects":
            yield f"{line} .objects"
        elif isinstance(node, ast.ImportFrom) and (node.module or "").startswith("django.db"):
            yield f"{line} imports {node.module}"
        elif isinstance(node, ast.Import) and any(
            a.name.startswith("django.db") for a in node.names
        ):
            yield f"{line} imports django.db"


def test_handlers_change_the_state_only_through_the_batch() -> None:
    found = [
        problem
        for path in sorted(OPS.glob("*.py"))
        for problem in orm_problems(relative(path), ast.parse(path.read_text(encoding="utf-8")))
    ]
    assert found == []


@pytest.mark.parametrize(
    "snippet", ["Wallet.objects.get(pk=1)", "from django.db import connection", "import django.db"]
)
def test_the_handler_scan_catches_the_orm(snippet: str) -> None:
    assert list(orm_problems("apps/economy/services/ops/thing.py", ast.parse(snippet)))
