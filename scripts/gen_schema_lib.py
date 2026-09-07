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
  literals again. An authored description ALWAYS beats inferred prose, and a
  key that matched nothing fails the build.
- **Conflicts fail loud.** The schema is inferred from the two live instances,
  so any silent widening would let corrupted data LOOSEN the contract the ajv
  gate checks it against (review finding: a truncated id used to erase the
  suiId pattern for a whole map, on both networks, with CI green). merge()
  therefore raises on any cross-network type disagreement, and a JSON null
  is refused outright — undeclared drift fails the generator, never reshapes
  the schema.
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


MAP_PATTERNS = [m["path"] for m in _MAPS]


def _path_matches(pattern, path):
    """'*' matches exactly one map-key segment — never an array's '[]', so a
    wildcarded description or map path cannot silently attach to array items."""
    pp, sp = pattern.split("/"), path.split("/")
    return len(pp) == len(sp) and all(a == b or (a == "*" and b != "[]") for a, b in zip(pp, sp))


def is_map_path(path):
    """Whether `path` is a declared open-keyed map ('*' = one segment)."""
    return any(_path_matches(p, path) for p in MAP_PATTERNS)


def describe(path, used):
    """Description for a /-joined path. First match wins (exact, then
    declaration order); registry keys use the same '*' wildcard as map paths.
    To describe an array's items, key the literal '[]' segment. Matched keys
    are recorded in `used` so build_schema can fail on stale ones."""
    if path in DESCRIPTIONS:
        used.add(path)
        return DESCRIPTIONS[path]
    for key, text in DESCRIPTIONS.items():
        if _path_matches(key, path):
            used.add(key)
            return text
    return None


def leaf_schema(v, path):
    if isinstance(v, bool):
        return {"type": "boolean"}
    if isinstance(v, int):
        return {"type": "integer"}
    if isinstance(v, float):
        return {"type": "number"}
    if v is None:
        # A null would infer as accept-anything and silently erase the field's
        # constraints everywhere (schema, zod, Rust). Refuse it at the source.
        raise SystemExit(
            f"gen_schema: null at {path} — omit the field until it has a value; "
            "a null here would strip the field's type/pattern from the schema for both networks")
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
    raise TypeError(f"unhandled leaf {v!r} at {path}")


def _conflict(a, b, path):
    raise SystemExit(
        f"gen_schema: type conflict at {path}: {a} vs {b} — the two networks (or two "
        "values in one map/array) disagree on this field's shape. Declare the intended "
        "shape (fix the data, or hand-write the schema for this path) instead of letting "
        "the generator widen it silently.")


def merge(a, b, path):
    """Merge two inferred schemas (presence in either network). Any genuine
    disagreement RAISES — silent widening would loosen the contract the ajv
    gate validates the very same data against."""
    if a is None or a == {}:
        return b
    if b is None or b == {}:
        return a
    if a == b:
        return a
    if "$ref" in a or "$ref" in b:
        _conflict(a, b, path)
    ta, tb = a.get("type"), b.get("type")
    if ta == tb == "object":
        # A map carries a SCHEMA in additionalProperties; a struct carries
        # the literal False. Presence alone doesn't discriminate.
        a_map = isinstance(a.get("additionalProperties"), dict)
        b_map = isinstance(b.get("additionalProperties"), dict)
        if a_map != b_map:
            _conflict(a, b, path)  # map on one side, struct on the other
        if a_map:
            return {"type": "object",
                    "additionalProperties": merge(a["additionalProperties"],
                                                  b["additionalProperties"], f"{path}/*")}
        props = dict(a.get("properties", {}))
        for k, sc in b.get("properties", {}).items():
            props[k] = merge(props.get(k), sc, f"{path}/{k}")
        req = set(a.get("required", [])) & set(b.get("required", []))
        out = {"type": "object", "properties": props, "additionalProperties": False}
        if req:
            out["required"] = sorted(req)
        return out
    if ta == tb == "array":
        return {"type": "array", "items": merge(a.get("items"), b.get("items"), f"{path}/[]")}
    _conflict(a, b, path)


def infer(v, path):
    """Infer a schema for value v at /-joined `path`. Map-ness comes from the
    declared registry (is_map_path)."""
    if isinstance(v, dict):
        if "_comment" in v:
            # audit P5: prose belongs in schema/descriptions.json, keyed by
            # this path — never in the served data.
            raise SystemExit(
                f"gen_schema: _comment in instance data at {path} — move the text to "
                f"schema/descriptions.json under a key for this path and delete it from the data")
        if is_map_path(path):
            item = None
            for k in v:
                item = merge(item, infer(v[k], f"{path}/*"), f"{path}/*")
            return {"type": "object", "additionalProperties": item if item is not None else {}}
        props, req = {}, []
        for k, val in v.items():
            props[k] = infer(val, f"{path}/{k}")
            req.append(k)
        return {"type": "object", "properties": props,
                "required": sorted(req), "additionalProperties": False}
    if isinstance(v, list):
        item = None
        for x in v:
            item = merge(item, infer(x, f"{path}/[]"), f"{path}/[]")
        return {"type": "array", "items": item or {}}
    return leaf_schema(v, path)


def annotate(node, used, path=""):
    """Attach descriptions from the registry at every depth (in place). An
    authored description OVERWRITES inferred prose — the registry is the one
    prose channel, and a silently-losing authored description was a review
    finding (leaf_schema's generic hex text used to shadow two authored EVM
    warnings while the stale-key gate stayed green)."""
    if not isinstance(node, dict):
        return node
    if path:
        d = describe(path, used)
        if d:
            node["description"] = d
    for k, sub in node.get("properties", {}).items():
        annotate(sub, used, f"{path}/{k}".lstrip("/"))
    ap = node.get("additionalProperties")
    if isinstance(ap, dict):
        annotate(ap, used, f"{path}/*".lstrip("/"))
    it = node.get("items")
    if isinstance(it, dict):
        annotate(it, used, f"{path}/[]".lstrip("/"))
    return node


def apply_constraints(schema, constraints):
    """Overlay hand-written constraints onto the generated schema at data
    paths ('*' = map item, '[]' = array items). A path that no longer resolves
    FAILS the build — a constraint must never silently detach from the field
    it guards."""
    for path, extra in constraints.items():
        node = schema
        try:
            for seg in path.split("/"):
                if seg == "*":
                    node = node["additionalProperties"]
                elif seg == "[]":
                    node = node["items"]
                else:
                    node = node["properties"][seg]
        except (KeyError, TypeError):
            raise SystemExit(
                f"gen_schema: constraint path {path} no longer resolves in the generated "
                "schema — the data moved; move the constraint with it") from None
        node.update(extra)
    return schema


def build_schema(m, t, top_extra, schema_id, title, description, required):
    """Assemble a full document schema from two network instances.

    `top_extra` is a dict of hand-written top-level properties that override
    the generic per-key inference. Raises on stale description keys, so a
    failed build never leaves a half-written schema behind (the caller writes
    the file only after this returns).
    """
    used = set()
    # Instance-document key order; a key owned by a hand-written top_extra
    # schema takes that schema at its natural position and is never inferred.
    props = {}
    for k in {**t, **m}:
        props[k] = top_extra[k] if k in top_extra else merge(
            infer(m[k], k) if k in m else None,
            infer(t[k], k) if k in t else None, k)
    for k, v in top_extra.items():
        if k not in props:
            props[k] = v
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
    annotate(schema, used)
    stale = set(DESCRIPTIONS) - used
    if stale:
        raise SystemExit(f"stale description key(s) — no schema path matched them: {sorted(stale)}")
    return schema
