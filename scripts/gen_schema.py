"""Generate schema/waterx-config.schema.json — the CURRENT (pre-flip) shape —
from the two live instances. Thin call site over gen_schema_lib; run from the
repo root: python3 scripts/gen_schema.py"""
import collections
import json
import sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_schema_lib import build_schema, infer, map_paths, merge  # noqa: E402

m = json.load(open("mainnet.json"))
t = json.load(open("testnet.json"))


def packages_schema(m, t, maps):
    """Per-package: union of both networks, optionality from presence."""
    out = {}
    for p in sorted(set(m["packages"]) | set(t["packages"])):
        schemas, presence = {}, collections.defaultdict(list)
        for net, doc in (("mainnet", m), ("testnet", t)):
            body = doc["packages"].get(p)
            if not isinstance(body, dict):
                continue
            for k, v in body.items():
                presence[k].append(net)
                schemas[k] = merge(schemas.get(k), infer(v, f"packages/{p}/{k}", maps))
        props, required = {}, []
        for k, s in sorted(schemas.items()):
            if len(presence[k]) == 1:
                s = {**s, "$comment": f"present only on {presence[k][0]} today"}
            props[k] = s
            if len(presence[k]) == 2:
                required.append(k)
        pkg = {"type": "object", "properties": props, "additionalProperties": False}
        if required:
            pkg["required"] = required
        if not (p in m["packages"] and p in t["packages"]):
            where = "mainnet" if p in m["packages"] else "testnet"
            pkg["$comment"] = f"package exists only on {where} today"
        out[p] = pkg
    return {"packages": {"type": "object", "properties": out, "additionalProperties": False},
            "network": {"enum": ["mainnet", "testnet"]},
            "chain_id": {"type": "string", "minLength": 4}}


schema = build_schema(
    m, t, "legacy", packages_schema,
    schema_id="https://config.waterx.app/schema/waterx-config.schema.json",
    title="waterx-config network file",
    description="One WaterX network deployment: package ids, shared objects, and the oracle feed registry. Describes the CURRENT served shape; the flip target is schema/waterx-config-target.schema.json. Fields present on only one network carry a $comment and are optional. See docs/FIELDS.md.",
    required=["network", "chain_id", "packages"],
)
json.dump(schema, open("schema/waterx-config.schema.json", "w"), indent=2, ensure_ascii=False)
print("schema/waterx-config.schema.json written")
