"""Generate schema/waterx-config.schema.json from the two live (target-shape)
network files. Thin call site over gen_schema_lib; run from the repo root:
    python3 scripts/gen_schema.py"""
import json
import sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_schema_lib import SUI_ID, assert_descriptions_used, build_schema  # noqa: E402

m = json.load(open("mainnet.json"))
t = json.load(open("testnet.json"))

_MVR = {"type": "object", "properties": {
    "name": {"type": "string"}, "package_info_id": dict(SUI_ID), "app_cap_id": dict(SUI_ID),
    "git": {"type": "object", "properties": {"repo": {"type": "string"}, "path": {"type": "string"},
                                             "version": {"type": "integer"}},
            "required": ["repo", "path", "version"], "additionalProperties": False}},
    "required": ["name", "package_info_id", "app_cap_id"], "additionalProperties": False}

TOP = {
    # enum rather than const: quicktype crashes on ANY numeric `const`
    # (typed or not) while a one-value enum generates cleanly and enforces
    # the same pin in ajv and zod (review finding).
    "schema_version": {"type": "integer", "enum": [2],
                       "description": "Format discriminator. This repo serves only version 2 (the consolidated shape); parsers reject anything else."},
    "network": {"enum": ["mainnet", "testnet"]},
    "chain_id": {"type": "string", "minLength": 4},
    # uniform package identity — the ONLY fields allowed per package
    "packages": {"type": "object", "additionalProperties": {
        "type": "object", "properties": {
            "published_at": dict(SUI_ID), "original_id": dict(SUI_ID),
            "version": {"type": "integer", "minimum": 1},
            "upgrade_capability": dict(SUI_ID), "mvr": _MVR},
        "additionalProperties": False}},
    "symbols": {"type": "object", "additionalProperties": {
        "type": "object",
        "properties": {"kind": {"enum": ["perp", "spot", "xstock", "commodity", "fx", "prediction"]}},
        "required": ["kind"], "additionalProperties": False}},
}

schema = build_schema(
    m, t, TOP,
    schema_id="https://config.waterx.app/schema/waterx-config.schema.json",
    title="waterx-config network file",
    description="One WaterX network deployment in the consolidated shape: one symbol universe, uniform package identity, domain-grouped shared objects, and a named per-rule oracle registry. See docs/FIELDS.md.",
    required=["schema_version", "network", "chain_id", "symbols", "packages", "objects", "oracle_rules"],
)
json.dump(schema, open("schema/waterx-config.schema.json", "w"), indent=2, ensure_ascii=False)
assert_descriptions_used()
print("schema/waterx-config.schema.json written")
