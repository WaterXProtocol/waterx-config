"""Schema-inference library behind scripts/gen_schema.py (its only call
site — kept separate so the inference machinery stays importable and testable
without running the generator).

Design decisions this module enforces:

- **Map-ness is declared, never guessed.** schema/map-paths.json lists every
  open-keyed map by path. A previous key-count heuristic turned single-entry
  maps into closed structs with the ticker as a REQUIRED property, so adding a
  second constant-rule feed would have been a breaking type change in the
  published packages.
- **Descriptions are data.** schema/descriptions.json is keyed by wildcarded
  paths and applied at every depth by annotate(); prose never lives in Python
  literals again.
"""
import json
import os

_HERE = os.path.dirname(os.path.abspath(__file__))
_SCHEMA_DIR = os.path.join(_HERE, "..", "schema")

SUI_ID = {"$ref": "#/$defs/suiId"}
SUI_TYPE = {"$ref": "#/$defs/suiType"}
DEC_STR = {"$ref": "#/$defs/decString"}

DEFS = {
    "suiId": {"type": "string", "pattern": "^0x[0-9a-fA-F]{64}$",
              "description": "32-byte Sui object/package id."},
    "suiType": {"type": "string",
                "pattern": "^0x[0-9a-fA-F]{1,64}::[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*$",
                "description": "Fully-qualified Move type tag."},
    "decString": {"type": "string", "pattern": "^[0-9]+$",
                  "description": "Unsigned integer as a decimal string — used where values may exceed 2^53 (u64/u128 amounts, 1e9-scaled prices)."},
}


def _load(name):
    with open(os.path.join(_SCHEMA_DIR, name)) as f:
        return json.load(f)


_MAPS = _load("map-paths.json")["maps"]
DESCRIPTIONS = {k: v for k, v in _load("descriptions.json").items() if k != "_comment"}
DESCRIPTIONS_USED = set()


MAP_PATTERNS = [m["path"] for m in _MAPS]


def _path_matches(pattern, path):
    """'*' matches exactly one map-key segment — never an array's '[]', so a
    wildcarded description or map path cannot silently attach to array items."""
    pp, sp = pattern.split("/"), path.split("/")
    return len(pp) == len(sp) and all(a == b or (a == "*" and b != "[]") for a, b in zip(pp, sp))


def is_map_path(path):
    """Whether `path` is a declared open-keyed map ('*' = one segment)."""
    return any(_path_matches(p, path) for p in MAP_PATTERNS)


def describe(path):
    """Description for a /-joined path. First match wins (exact, then
    declaration order); registry keys use the same '*' wildcard as map paths.
    To describe an array's items, key the literal '[]' segment."""
    if path in DESCRIPTIONS:
        DESCRIPTIONS_USED.add(path)
        return DESCRIPTIONS[path]
    for key, text in DESCRIPTIONS.items():
        if _path_matches(key, path):
            DESCRIPTIONS_USED.add(key)
            return text
    return None


def assert_descriptions_used():
    """Stale-key gate: every authored description key must have matched at
    least one schema path in this generator run."""
    stale = set(DESCRIPTIONS) - DESCRIPTIONS_USED
    if stale:
        raise SystemExit(f"stale description key(s) — no schema path matched them: {sorted(stale)}")


def leaf_schema(v):
    if isinstance(v, bool):
        return {"type": "boolean"}
    if isinstance(v, int):
        return {"type": "integer"}
    if isinstance(v, float):
        return {"type": "number"}
    if v is None:
        return {}
    if isinstance(v, str):
        if v.startswith("0x") and len(v) == 66:
            return dict(SUI_ID)
        if "::" in v and v.startswith("0x"):
            return dict(SUI_TYPE)
        if v.startswith("0x") and v[2:] and all(c in "0123456789abcdefABCDEF" for c in v[2:]):
            return {"type": "string", "pattern": "^0x[0-9a-fA-F]{1,64}$",
                    "description": "0x-prefixed hex id/address (Sui short-form or EVM)."}
        if v.isdigit():
            return dict(DEC_STR)
        return {"type": "string"}
    raise TypeError(f"unhandled leaf {v!r}")


def merge(a, b):
    """Merge two inferred schemas (presence in either network)."""
    if a is None or a == {}:
        return b
    if b is None or b == {}:
        return a
    if a == b:
        return a
    if "$ref" in a or "$ref" in b:
        return {"type": "string"}  # mixed string kinds -> plain string
    ta, tb = a.get("type"), b.get("type")
    if ta == tb == "object":
        ap_schemas = [x for x in (a.get("additionalProperties"), b.get("additionalProperties"))
                      if isinstance(x, dict)]
        props = dict(a.get("properties", {}))
        req = set(a.get("required", []))
        for k, sc in b.get("properties", {}).items():
            props[k] = merge(props.get(k), sc)
        req &= set(b.get("required", []))
        if ap_schemas:  # a MAP on either side stays a map
            ap = ap_schemas[0] if len(ap_schemas) == 1 else merge(*ap_schemas)
            out = {"type": "object", "additionalProperties": ap}
            if props:
                out["properties"] = props
            return out
        out = {"type": "object", "properties": props, "additionalProperties": False}
        if req:
            out["required"] = sorted(req)
        return out
    if ta == tb == "array":
        return {"type": "array", "items": merge(a.get("items"), b.get("items"))}
    if {ta, tb} == {"integer", "number"}:
        return {"type": "number"}
    return {"type": [ta, tb] if ta and tb else "string"}


def infer(v, path):
    """Infer a schema for value v at /-joined `path`. Map-ness comes from the
    declared registry (is_map_path)."""
    if isinstance(v, dict):
        if is_map_path(path):
            item = None
            for k in v:
                item = merge(item, infer(v[k], f"{path}/*"))
            return {"type": "object", "additionalProperties": item if item is not None else {}}
        props, req = {}, []
        for k, val in v.items():
            if k == "_comment":  # audit P5: comments belong in descriptions, not data
                props[k] = {"type": "string", "deprecated": True,
                            "description": "Inline comment carried in DATA. Do not add new ones."}
                continue
            props[k] = infer(val, f"{path}/{k}")
            req.append(k)
        return {"type": "object", "properties": props,
                "required": sorted(req), "additionalProperties": False}
    if isinstance(v, list):
        item = None
        for x in v:
            item = merge(item, infer(x, f"{path}/[]"))
        return {"type": "array", "items": item or {}}
    return leaf_schema(v)


def annotate(node, path=""):
    """Attach descriptions from the registry at every depth (in place)."""
    if not isinstance(node, dict):
        return node
    d = describe(path) if path else None
    if d and "description" not in node:
        node["description"] = d
    for k, sub in node.get("properties", {}).items():
        annotate(sub, f"{path}/{k}".lstrip("/"))
    ap = node.get("additionalProperties")
    if isinstance(ap, dict):
        annotate(ap, f"{path}/*".lstrip("/"))
    it = node.get("items")
    if isinstance(it, dict):
        annotate(it, f"{path}/[]".lstrip("/"))
    return node


def build_schema(m, t, top_extra, schema_id, title, description, required):
    """Assemble a full document schema from two network instances.

    `top_extra` is a dict of hand-written top-level properties that override
    the generic per-key inference.
    """
    # Instance-document key order; a key owned by a hand-written top_extra
    # schema takes that schema at its natural position and is never inferred.
    props = {}
    for k in {**t, **m}:
        props[k] = top_extra[k] if k in top_extra else merge(
            infer(m[k], k) if k in m else None,
            infer(t[k], k) if k in t else None)
    for k, v in top_extra.items():
        props.setdefault(k, v)
    props = {k: v for k, v in props.items() if v}
    schema = {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": schema_id,
        "title": title,
        "description": description,
        "type": "object",
        "properties": props,
        "required": required,
        "additionalProperties": False,
        "$defs": DEFS,
    }
    annotate(schema)
    return schema
