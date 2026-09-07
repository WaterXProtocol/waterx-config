"""Generate the JSON Schema for waterx-config from the live instances.

Describes the CURRENT state (Phase 1 of the audit): every field that exists in
either network is captured; fields present in only one network are optional.
Hand-tuned parts: shared $defs (suiId, suiType, decString), the four feeds
shapes, and descriptions for hot / hazardous fields.
"""
import json, collections

m = json.load(open('mainnet.json'))
t = json.load(open('testnet.json'))

SUI_ID = {"$ref": "#/$defs/suiId"}
SUI_TYPE = {"$ref": "#/$defs/suiType"}
DEC_STR = {"$ref": "#/$defs/decString"}

DESCRIPTIONS = {
    ("*", "published_at"): "Package id of the current latest version — the tx-call target. Changes on every upgrade.",
    ("*", "original_id"): "Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type).",
    ("*", "version"): "On-chain package version: 1 at first publish, +1 per upgrade.",
    ("*", "upgrade_capability"): "UpgradeCap object id. Deploy-time artifact; no runtime consumer.",
    ("*", "mvr"): "Move Registry (MVR) registration for this package. Mainnet only today.",
    ("*", "admin_cap"): "Admin capability object id.",
    ("waterx_rule", "feeds"): "QC feed registry, keyed by oracle symbol. The `weights` inside are OFF-CHAIN ONLY: waterx_rule on-chain validates sources/ticker/method/min_sources but has no notion of weights, so a weight change moves the signed price via a parameter no on-chain check can see (waterx-quote-center audit-scope I-16). Review weight changes as a trust-surface change.",
    ("waterx_rule", "enclave_pubkey"): "Registered enclave ed25519 pubkey (hex, no 0x). Duplicated in packages.enclave.enclave_pubkey — keep both in sync until R4 deduplicates.",
    ("pyth_rule", "feeds"): "Per-symbol Pyth price feed: feed_id (Pyth) + price_info_object (Sui object the keeper refreshes).",
    ("pyth_lazer_rule", "feeds"): "Per-symbol Pyth Lazer numeric feed id, as used by the keeper's Lazer WS subscription.",
    ("constant_rule", "feeds"): "Per-symbol constant price, 1e9-scaled decimal string (e.g. \"1000000000\" = 1.0).",
    ("waterx_oracle", "aggregators"): "Per-symbol on-chain Aggregator object id — the cross-rule weighted-median aggregation point.",
    ("waterx_perp", "markets"): "Per-symbol perp market: market + config object ids.",
}

def leaf_schema(v, path):
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
        if v.startswith("0x") and all(c in "0123456789abcdefABCDEF" for c in v[2:]) and v[2:]:
            return {"type": "string", "pattern": "^0x[0-9a-fA-F]{1,64}$",
                    "description": "Short-form Sui address/object id."}
        if "::" in v and v.startswith("0x"):
            return dict(SUI_TYPE)
        if v.isdigit():
            return dict(DEC_STR)
        return {"type": "string"}
    raise TypeError(path)

def merge(a, b):
    if a is None: return b
    if b is None: return a
    if a == b: return a
    ta, tb = a.get("type"), b.get("type")
    if "$ref" in a and "$ref" in b and a != b:
        return {"type": "string"}  # mixed string kinds -> plain string
    if "$ref" in a or "$ref" in b:
        return {"type": "string"}
    if ta == tb == "object":
        apa, apb = a.get("additionalProperties"), b.get("additionalProperties")
        # a schema-valued additionalProperties is a MAP — merging must keep it,
        # not collapse to a closed object (that bug rejected every map key).
        ap_schemas = [x for x in (apa, apb) if isinstance(x, dict)]
        props = dict(a.get("properties", {}))
        req = set(a.get("required", []))
        for k, sc in b.get("properties", {}).items():
            props[k] = merge(props.get(k), sc)
        req &= set(b.get("required", []))
        if ap_schemas:
            ap = ap_schemas[0] if len(ap_schemas) == 1 else merge(*ap_schemas)
            out = {"type": "object", "additionalProperties": ap}
            if props: out["properties"] = props
            return out
        out = {"type": "object", "properties": props, "additionalProperties": False}
        if req: out["required"] = sorted(req)
        return out
    if ta == tb == "array":
        return {"type": "array", "items": merge(a.get("items"), b.get("items"))}
    if {ta, tb} == {"integer", "number"}:
        return {"type": "number"}
    return {"type": [ta, tb] if ta and tb else "string"}

def infer(v, path):
    if isinstance(v, dict):
        # map-like? (symbol keyed) — heuristics: >3 keys all UPPER or values same shape
        keys = list(v)
        symbolish = all(k.isupper() or k in ("WLP", "USD", "USDC") for k in keys)
        chainish = (path.endswith(".chains") and all(k.islower() for k in keys))
        if keys and all(isinstance(x, str) for x in keys) and len(keys) >= 2 and (symbolish or chainish):
            item = None
            for k in keys:
                item = merge(item, infer(v[k], f"{path}.{k}"))
            return {"type": "object", "additionalProperties": item}
        props, req = {}, []
        for k, val in v.items():
            if k == "_comment":
                props[k] = {"type": "string", "deprecated": True,
                            "description": "Inline comment carried in DATA (audit P5). Migrates into schema descriptions in the Phase-2 cleanup; do not add new ones."}
                continue
            props[k] = infer(val, f"{path}.{k}")
            req.append(k)
        return {"type": "object", "properties": props, "required": sorted(req), "additionalProperties": False}
    if isinstance(v, list):
        item = None
        for x in v:
            item = merge(item, infer(x, path + "[]"))
        return {"type": "array", "items": item or {}}
    return leaf_schema(v, path)

# ── package schemas: union of both networks, optionality from presence ──
packages = {}
allpk = sorted(set(m["packages"]) | set(t["packages"]))
for p in allpk:
    schemas, presence = {}, collections.defaultdict(list)
    for net, doc in (("mainnet", m), ("testnet", t)):
        body = doc["packages"].get(p)
        if not isinstance(body, dict):
            continue
        for k, v in body.items():
            presence[k].append(net)
            schemas[k] = merge(schemas.get(k), infer(v, f"{p}.{k}"))
    props = {}
    required = []
    for k, s in sorted(schemas.items()):
        d = DESCRIPTIONS.get((p, k)) or DESCRIPTIONS.get(("*", k))
        if d:
            s = {**s, "description": d}
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
    packages[p] = pkg

top_props = {
    "network": {"enum": ["mainnet", "testnet"]},
    "chain_id": {"type": "string", "minLength": 4},
    "coin_registry": merge(
        infer(m["coin_registry"], "coin_registry") if "coin_registry" in m else None,
        infer(t["coin_registry"], "coin_registry") if "coin_registry" in t else None,
    ) or {},
    "packages": {"type": "object", "properties": packages, "additionalProperties": False},
    "evm": merge(infer(m["evm"], "evm"), infer(t["evm"], "evm") if "evm" in t else None),
    "deploy_tx_log": merge(infer(m["deploy_tx_log"], "deploy_tx_log"),
                           infer(t["deploy_tx_log"], "deploy_tx_log") if "deploy_tx_log" in t else None),
}

schema = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$id": "https://config.waterx.app/schema/waterx-config.schema.json",
    "title": "waterx-config network file",
    "description": "One WaterX network deployment: package ids, shared objects, and the oracle feed registry. Generated from the 2026-09-07 audit describing the CURRENT instances; fields present on only one network carry a $comment and are optional. See docs/FIELDS.md for the rendered reference.",
    "type": "object",
    "properties": top_props,
    "required": ["network", "chain_id", "packages"],
    "additionalProperties": False,
    "$defs": {
        "suiId": {"type": "string", "pattern": "^0x[0-9a-fA-F]{64}$", "description": "32-byte Sui object/package id."},
        "suiType": {"type": "string", "pattern": "^0x[0-9a-fA-F]{1,64}::[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*$", "description": "Fully-qualified Move type tag."},
        "decString": {"type": "string", "pattern": "^[0-9]+$", "description": "Unsigned integer as a decimal string — used where values may exceed 2^53 (u64/u128 amounts, 1e9-scaled prices)."},
    },
}
json.dump(schema, open("schema/waterx-config.schema.json", "w"), indent=2, ensure_ascii=False)
print("schema written")
