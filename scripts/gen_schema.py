"""Generate schema/waterx-config.schema.json (the canonical schema, consumed
by codegen and every parser) from the two live network files. Run from the
repo root:
    python3 scripts/gen_schema.py"""
import json
import sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_schema_lib import SUI_ID, apply_constraints, assert_anchors, build_schema  # noqa: E402

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
    # uniform package identity — the ONLY fields allowed per package, and the
    # identity trio is REQUIRED (an identity block missing published_at is a
    # sync bug, not a partial deploy; review finding).
    "packages": {"type": "object", "additionalProperties": {
        "type": "object", "properties": {
            "published_at": dict(SUI_ID), "original_id": dict(SUI_ID),
            "version": {"type": "integer", "minimum": 1},
            "upgrade_capability": dict(SUI_ID), "mvr": _MVR},
        "required": ["published_at", "original_id", "version"],
        "additionalProperties": False}},
    "symbols": {"type": "object", "additionalProperties": {
        "type": "object",
        "properties": {"kind": {"enum": ["perp", "spot", "xstock", "commodity", "fx", "prediction"]}},
        "required": ["kind"], "additionalProperties": False}},
}

# Hand-written constraints overlaid on inferred nodes of the CANONICAL schema.
# Pattern-class only: an exact-vocabulary ENUM must never go here — every
# future addition to it would break pinned parsers (the old closed-packages
# failure class). When a repo-only growable vocabulary next needs pinning,
# restore the gate-schema layer from git (`git show 99a11ab:scripts/gen_schema.py`
# — retired 2026-09-09 with venue_feeds, when its last vocabulary left).
CONSTRAINTS = {
    # Prose stays in schema/descriptions.json (the one prose channel;
    # annotate() gives it precedence).
    "oracle_rules/waterx/enclave/pubkey": {"pattern": "^[0-9a-fA-F]{64}$"},
}


# Every top-level key must appear here or in schema/optional-fields.json —
# build_schema fails otherwise (review finding: evm was silently optional).
# coin_registry was removed outright 2026-09-09: it held the Sui SYSTEM
# address 0xc (sui::coin_registry), a network-invariant constant like 0x6
# Clock — deployment config is not the place for it, and nothing ever read it.
REQUIRED_TOP = ["schema_version", "network", "chain_id", "symbols", "packages",
                "objects", "oracle_rules", "evm"]


def generate(m, t):
    """Build the canonical schema from two instance docs. Importable so
    scripts/test_gen_schema.py exercises the REAL TOP/constraints."""
    schema = build_schema(
        m, t, TOP,
        schema_id="https://config.waterx.app/schema/waterx-config.schema.json",
        title="waterx-config network file",
        description="One WaterX network deployment in the consolidated shape: one symbol universe, uniform package identity, domain-grouped shared objects, and a named per-rule oracle registry. See docs/FIELDS.md.",
        required=REQUIRED_TOP,
    )
    apply_constraints(schema, CONSTRAINTS)
    assert_anchors(schema)
    return schema


if __name__ == "__main__":
    m = json.load(open("mainnet.json"))
    t = json.load(open("testnet.json"))
    json.dump(generate(m, t), open("schema/waterx-config.schema.json", "w"), indent=2, ensure_ascii=False)
    print("schema/waterx-config.schema.json written")
