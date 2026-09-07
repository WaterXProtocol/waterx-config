"""Generate schema/waterx-config-target.schema.json — the post-flip shape —
from the LIFTED instances (emitted by derive-target.mjs into a build dir).
Run from repo root:
  node scripts/derive-target.mjs emit .build-target
  python3 scripts/gen_target_schema.py
"""
import json
import sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_schema_lib import DEC_STR, SUI_ID, build_schema  # noqa: E402

m = json.load(open(".build-target/mainnet.json"))
t = json.load(open(".build-target/testnet.json"))

_MVR = {"type": "object", "properties": {
    "name": {"type": "string"}, "package_info_id": dict(SUI_ID), "app_cap_id": dict(SUI_ID),
    "git": {"type": "object", "properties": {"repo": {"type": "string"}, "path": {"type": "string"},
                                             "version": {"type": "integer"}},
            "required": ["repo", "path", "version"], "additionalProperties": False}},
    "required": ["name", "package_info_id", "app_cap_id"], "additionalProperties": False}


def top_extra(m, t, maps):
    return {
        "schema_version": {"const": 2},
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
    m, t, "target", top_extra,
    schema_id="https://config.waterx.app/schema/waterx-config-target.schema.json",
    title="waterx-config network file (flip target)",
    description="The consolidated post-flip shape (docs/FLIP-PLAN.md): one symbol universe, uniform package identity, domain-grouped shared objects, and a named per-rule oracle registry. Until flip day this validates the LIFTED form of the served files; on flip day it becomes the schema of mainnet.json/testnet.json themselves.",
    required=["schema_version", "network", "chain_id", "symbols", "packages", "objects", "oracle_rules"],
)
json.dump(schema, open("schema/waterx-config-target.schema.json", "w"), indent=2, ensure_ascii=False)
print("schema/waterx-config-target.schema.json written")
