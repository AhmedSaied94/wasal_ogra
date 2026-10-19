"""The generator's intermediate description of every content type (research R1).

Both emitters read this one description, so the server models and the app models always have the
same classes, fields, names and optionality. Building it refuses any schema outside the profile
(R3), an inline object or enum (each must be a named `$defs` entry, so it has a class name), and
duplicate type names across files.
"""

from __future__ import annotations

import heapq
import keyword
import re
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Any, Literal

from wassal_content.profile import check_profile

__all__ = [
    "CodegenError",
    "EnumDef",
    "FieldDef",
    "Model",
    "ObjectDef",
    "TypeRef",
    "build_model",
    "dart_member",
    "python_member",
]


class CodegenError(ValueError):
    """The schemas can't be generated: they break the profile or the naming rules."""


@dataclass(frozen=True)
class TypeRef:
    """A field's type. `named` refers to an `ObjectDef` or `EnumDef` by name."""

    kind: Literal["str", "int", "bool", "named", "list", "map"]
    name: str = ""
    item: TypeRef | None = None

    def names(self) -> set[str]:
        """Every named type this type mentions."""
        if self.kind == "named":
            return {self.name}
        return self.item.names() if self.item else set()


@dataclass(frozen=True)
class FieldDef:
    json_name: str
    py_name: str
    dart_name: str
    type: TypeRef
    required: bool


@dataclass(frozen=True)
class ObjectDef:
    name: str
    part: str
    description: str
    fields: tuple[FieldDef, ...]

    def dependencies(self) -> set[str]:
        return set().union(*(f.type.names() for f in self.fields)) - {self.name}


@dataclass(frozen=True)
class EnumDef:
    name: str
    part: str
    description: str
    values: tuple[str | int, ...]

    @property
    def is_int(self) -> bool:
        return isinstance(self.values[0], int)

    def dependencies(self) -> set[str]:
        return set()


TypeDef = ObjectDef | EnumDef


@dataclass(frozen=True)
class Model:
    """Every type, in emission order (dependencies first, then by name), and each part's root."""

    types: tuple[TypeDef, ...]
    roots: Mapping[str, str]
    parts: tuple[str, ...]
    schema_set_version: str
    by_name: Mapping[str, TypeDef] = field(default_factory=dict)

    def part_types(self, part: str) -> list[TypeDef]:
        return [t for t in self.types if t.part == part]


_SUFFIX = ".schema.json"
_LOCAL = re.compile(r"^#/\$defs/(?P<name>[A-Za-z][A-Za-z0-9]*)$")
_FILE = re.compile(
    r"^(?P<part>[a-z][a-z0-9_]*)\.schema\.json(?:#/\$defs/(?P<name>[A-Za-z][A-Za-z0-9]*))?$"
)
_WORD = re.compile(r"[A-Za-z0-9]+")
_DART_KEYWORDS = frozenset(
    {
        "assert", "break", "case", "catch", "class", "const", "continue", "default", "do", "else",
        "enum", "extends", "false", "final", "finally", "for", "if", "in", "is", "new", "null",
        "rethrow", "return", "super", "switch", "this", "throw", "true", "try", "var", "void",
        "while", "with", "hashCode", "runtimeType", "toString", "noSuchMethod",
    }
)  # fmt: skip
# A freezed class already has these members, and so does every Dart enum.
_DART_FIELD_RESERVED = _DART_KEYWORDS | {"toJson", "copyWith"}
_DART_MEMBER_RESERVED = _DART_KEYWORDS | {"values", "index", "name"}


def python_field(json_name: str) -> str:
    """`ar-EG` → `ar_eg`; a valid identifier stays as it is."""
    name = json_name if json_name.isidentifier() else re.sub(r"[^0-9A-Za-z]", "_", json_name)
    name = name.lower() if name != json_name else name
    if keyword.iskeyword(name) or not name.isidentifier():
        raise CodegenError(f"property {json_name!r} has no Python name")
    return name


def dart_field(json_name: str) -> str:
    """`trip_id` → `tripId`, `ar-EG` → `arEg`."""
    words: list[str] = _WORD.findall(json_name)
    if not words:
        raise CodegenError(f"property {json_name!r} has no Dart name")
    name = words[0].lower() + "".join(word[:1].upper() + word[1:].lower() for word in words[1:])
    if name in _DART_FIELD_RESERVED or name[0].isdigit():
        raise CodegenError(f"property {json_name!r} maps to a reserved Dart name {name!r}")
    return name


def python_member(value: str | int) -> str:
    """An enum member's Python name: `line_hay` → `LINE_HAY`, `50` → `V50`."""
    text = re.sub(r"[^0-9A-Za-z]", "_", str(value)).upper()
    return f"V{text}" if text[:1].isdigit() or not text else text


def dart_member(value: str | int) -> str:
    """An enum member's Dart name: `line_hay` → `lineHay`, `JENEHAT` → `jenehat`, `50` → `v50`."""
    words: list[str] = _WORD.findall(str(value))
    if not words:
        raise CodegenError(f"enum value {value!r} has no Dart name")
    name = words[0].lower() + "".join(word[:1].upper() + word[1:].lower() for word in words[1:])
    if name[0].isdigit():
        name = f"v{name}"
    if name in _DART_MEMBER_RESERVED:
        name = f"v{name[0].upper()}{name[1:]}"
    return name


class _Builder:
    def __init__(self, schemas: Mapping[str, Mapping[str, Any]]) -> None:
        self.schemas = schemas
        # (part, $defs name or None for the root) → (global type name, schema)
        self.named: dict[tuple[str, str | None], tuple[str, Mapping[str, Any]]] = {}
        self.aliases: dict[str, TypeRef] = {}
        self.types: dict[str, TypeDef] = {}
        self.resolving: set[str] = set()

    def collect(self) -> None:
        owners: dict[str, str] = {}
        for part, document in sorted(self.schemas.items()):
            entries: list[tuple[str | None, str, Mapping[str, Any]]] = [
                (name, name, schema) for name, schema in document.get("$defs", {}).items()
            ]
            if "title" in document:
                entries.append((None, str(document["title"]), document))
            for key, name, schema in entries:
                if name in owners:
                    raise CodegenError(
                        f"type {name!r} is defined in both {owners[name]} and {part}{_SUFFIX}"
                    )
                owners[name] = f"{part}{_SUFFIX}"
                self.named[(part, key)] = (name, schema)

    def target(self, ref: str, part: str) -> tuple[str, str | None]:
        local = _LOCAL.match(ref)
        if local:
            key: tuple[str, str | None] = (part, local.group("name"))
        else:
            other = _FILE.match(ref)
            if other is None:
                raise CodegenError(f"{part}{_SUFFIX}: unsupported $ref {ref!r}")
            key = (other.group("part"), other.group("name"))
        if key not in self.named:
            raise CodegenError(f"{part}{_SUFFIX}: $ref {ref!r} points at nothing")
        return key

    def type_of(self, schema: Mapping[str, Any], part: str, where: str) -> TypeRef:
        if "$ref" in schema:
            return self.resolve(self.target(str(schema["$ref"]), part))
        kind = schema.get("type")
        if kind in ("string", "integer") and "enum" in schema:
            raise CodegenError(f"{where}: an enum must be a named $defs entry")
        if kind == "string":
            return TypeRef("str")
        if kind == "integer":
            return TypeRef("int")
        if kind == "boolean":
            return TypeRef("bool")
        if kind == "array":
            return TypeRef("list", item=self.type_of(schema["items"], part, f"{where}/items"))
        if kind == "object" and isinstance(schema.get("additionalProperties"), dict):
            value = self.type_of(
                schema["additionalProperties"], part, f"{where}/additionalProperties"
            )
            return TypeRef("map", item=value)
        if kind == "object":
            raise CodegenError(f"{where}: an object must be a named $defs entry or a root")
        raise CodegenError(f"{where}: no type")

    def resolve(self, key: tuple[str, str | None]) -> TypeRef:
        name, schema = self.named[key]
        part = key[0]
        if name in self.types:
            return TypeRef("named", name=name)
        if name in self.aliases:
            return self.aliases[name]
        kind = schema.get("type")
        if kind == "object" and "properties" in schema:
            self.object(name, part, schema)
            return TypeRef("named", name=name)
        if kind in ("string", "integer") and "enum" in schema:
            values = tuple(schema["enum"])
            self.types[name] = EnumDef(name, part, str(schema.get("description", "")), values)
            self.check_members(name, values)
            return TypeRef("named", name=name)
        if name in self.resolving:
            raise CodegenError(f"type {name!r} refers to itself")
        self.resolving.add(name)
        alias = self.type_of(schema, part, f"{part}{_SUFFIX}#/$defs/{name}")
        self.resolving.discard(name)
        self.aliases[name] = alias
        return alias

    def check_members(self, name: str, values: tuple[str | int, ...]) -> None:
        for convert in (python_member, dart_member):
            members = [convert(value) for value in values]
            if len(set(members)) != len(members):
                raise CodegenError(f"enum {name!r}: two values map to the same member name")

    def object(self, name: str, part: str, schema: Mapping[str, Any]) -> None:
        # Registered before its fields resolve, so a field may refer back to this type.
        self.types[name] = ObjectDef(name, part, "", ())
        required = set(schema.get("required", []))
        fields = []
        for json_name, child in schema["properties"].items():
            where = f"{part}{_SUFFIX}#/{name}/properties/{json_name}"
            fields.append(
                FieldDef(
                    json_name=json_name,
                    py_name=python_field(json_name),
                    dart_name=dart_field(json_name),
                    type=self.type_of(child, part, where),
                    required=json_name in required,
                )
            )
        for convert in ("py_name", "dart_name"):
            names = [getattr(f, convert) for f in fields]
            if len(set(names)) != len(names):
                raise CodegenError(f"type {name!r}: two properties map to the same field name")
        self.types[name] = ObjectDef(name, part, str(schema.get("description", "")), tuple(fields))


def _ordered(types: Mapping[str, TypeDef]) -> tuple[TypeDef, ...]:
    """Dependencies first; among the ready types, alphabetical. Cycles are refused."""
    waiting = {name: type_.dependencies() for name, type_ in types.items()}
    ready = [name for name, deps in waiting.items() if not deps]
    heapq.heapify(ready)
    order: list[TypeDef] = []
    while ready:
        name = heapq.heappop(ready)
        order.append(types[name])
        del waiting[name]
        for other, deps in waiting.items():
            if name in deps:
                deps.discard(name)
                if not deps:
                    heapq.heappush(ready, other)
    if waiting:
        raise CodegenError(f"types refer to each other in a cycle: {', '.join(sorted(waiting))}")
    return tuple(order)


def build_model(schemas: Mapping[str, Mapping[str, Any]], schema_set_version: str) -> Model:
    """Build the description from parsed schema files, keyed by part (the file name stem)."""
    violations = check_profile({f"{part}{_SUFFIX}": doc for part, doc in schemas.items()})
    if violations:
        lines = "\n".join(
            f"  {v.file}{('#' + v.pointer) if v.pointer else ''}: {v.message}" for v in violations
        )
        raise CodegenError(f"the schemas are outside the profile:\n{lines}")
    builder = _Builder(schemas)
    builder.collect()
    for key in sorted(builder.named, key=lambda k: (k[0], k[1] or "")):
        builder.resolve(key)
    roots = {
        part: builder.named[(part, None)][0]
        for part in sorted(schemas)
        if (part, None) in builder.named
    }
    types = _ordered(builder.types)
    return Model(
        types=types,
        roots=roots,
        parts=tuple(sorted(schemas)),
        schema_set_version=schema_set_version,
        by_name={t.name: t for t in types},
    )
