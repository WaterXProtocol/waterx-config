"""Shared schema-inference library for the two generators (current-shape and
target-shape). The generators are thin call sites over this module — there must
be exactly ONE copy of merge/infer/annotate (a previous revision had three,
and they drifted).

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


DESCRIPTIONS = {k: v for k, v in _load("descriptions.json").items() if k != "_comment"}
_MAPS = _load("map-paths.json")["maps"]


def map_paths(shape):
    """The declared open-keyed map paths for 'legacy' or 'target'."""
    return {m[shape] for m in _MAPS}


def describe(path):
    """Description for a /-joined path, honoring single-segment '*' wildcards."""
    if path in DESCRIPTIONS:
        return DESCRIPTIONS[path]
    parts = path.split("/")
    for key, text in DESCRIPTIONS.items():
        kp = key.split("/")
        if len(kp) == len(parts) and all(a == "*" or a == b for a, b in zip(kp, parts)):
            return text
    return None


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
                    "description": "Short-form Sui address/object id."}
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


def infer(v, path, maps):
    """Infer a schema for value v at /-joined `path`; `maps` declares which
    paths are open-keyed maps (from map_paths())."""
    if isinstance(v, dict):
        if path in maps:
            item = None
            for k in v:
                item = merge(item, infer(v[k], f"{path}/{k}", maps))
            return {"type": "object", "additionalProperties": item if item is not None else {}}
        props, req = {}, []
        for k, val in v.items():
            if k == "_comment":  # audit P5: comments belong in descriptions, not data
                props[k] = {"type": "string", "deprecated": True,
                            "description": "Inline comment carried in DATA. Do not add new ones."}
                continue
            props[k] = infer(val, f"{path}/{k}", maps)
            req.append(k)
        return {"type": "object", "properties": props,
                "required": sorted(req), "additionalProperties": False}
    if isinstance(v, list):
        item = None
        for x in v:
            item = merge(item, infer(x, path, maps))
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
        annotate(it, path)
    return node


def build_schema(m, t, shape, top_extra, schema_id, title, description, required):
    """Assemble a full document schema from two network instances.

    `top_extra(m, t, maps)` returns the dict of top-level properties beyond the
    generic per-key inference (or {} to infer everything generically).
    """
    maps = map_paths(shape)
    keys = [k for k in {**t, **m} if k != "packages"]
    props = {}
    for k in keys:
        props[k] = merge(infer(m[k], k, maps) if k in m else None,
                         infer(t[k], k, maps) if k in t else None)
    props.update(top_extra(m, t, maps))
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
