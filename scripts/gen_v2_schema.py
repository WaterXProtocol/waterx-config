import json
exec(open('scripts/gen_schema_lib.py').read().replace("m = json.load(open('mainnet.json'))","m = json.load(open('v2/mainnet.json'))").replace("t = json.load(open('testnet.json'))","t = json.load(open('v2/testnet.json'))"))
m = json.load(open('v2/mainnet.json')); t = json.load(open('v2/testnet.json'))
def both(key):
    return merge(infer(m[key], key) if key in m else None,
                 infer(t[key], key) if key in t else None)
props = {
  "schema_version": {"const": 2},
  "network": {"enum": ["mainnet", "testnet"]},
  "chain_id": {"type": "string", "minLength": 4},
  "symbols": {"type": "object",
    "description": "The single symbol universe: the ONLY place a symbol is introduced. Every symbol-keyed map elsewhere must reference a key from here (CI-enforced).",
    "additionalProperties": {"type": "object", "properties": {"kind": {"enum": ["perp","spot","xstock","commodity","fx","prediction"]}}, "required": ["kind"], "additionalProperties": False}},
  "packages": {"type": "object",
    "description": "Package identity ONLY — uniform shape for every package; shared objects live under `objects`.",
    "additionalProperties": {"type": "object", "properties": {
        "published_at": {"$ref": "#/$defs/suiId"},
        "original_id": {"$ref": "#/$defs/suiId"},
        "version": {"type": "integer", "minimum": 1},
        "upgrade_capability": {"$ref": "#/$defs/suiId"},
        "mvr": {"type": "object", "properties": {"name": {"type": "string"}, "package_info_id": {"$ref": "#/$defs/suiId"}, "app_cap_id": {"$ref": "#/$defs/suiId"}, "git": {"type": "object", "properties": {"repo": {"type":"string"}, "path": {"type":"string"}, "version": {"type":"integer"}}, "required":["repo","path","version"], "additionalProperties": False}}, "required": ["name","package_info_id","app_cap_id"], "additionalProperties": False}},
      "additionalProperties": False}},
  "objects": both("objects"),
  "oracle_rules": both("oracle_rules"),
}
if "coin_registry" in m or "coin_registry" in t: props["coin_registry"] = both("coin_registry")
if "evm" in m or "evm" in t: props["evm"] = both("evm")
schema = {
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://config.waterx.app/schema/v2/waterx-config-v2.schema.json",
  "title": "waterx-config network file (v2)",
  "description": "The consolidated v2 shape (docs/V2-PROPOSAL.md): one symbol universe, uniform package identity, domain-grouped shared objects, and a named per-rule oracle registry. Derived mechanically from v1 by scripts/derive-v2.mjs until cutover.",
  "type": "object", "properties": props,
  "required": ["schema_version","network","chain_id","symbols","packages","objects","oracle_rules"],
  "additionalProperties": False,
  "$defs": {
    "suiId": {"type": "string", "pattern": "^0x[0-9a-fA-F]{64}$", "description": "32-byte Sui object/package id."},
    "suiType": {"type": "string", "pattern": "^0x[0-9a-fA-F]{1,64}::[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*$", "description": "Fully-qualified Move type tag."},
    "decString": {"type": "string", "pattern": "^[0-9]+$", "description": "Unsigned integer as a decimal string (u64/u128-safe)."},
  },
}
import os
os.makedirs('schema/v2', exist_ok=True)
json.dump(schema, open('schema/v2/waterx-config-v2.schema.json','w'), indent=2, ensure_ascii=False)
print("v2 schema written")
