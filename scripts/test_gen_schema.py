"""Regression tests for the generator's fail-closed guarantees (review
findings). Dependency-free; run from the repo root:
    python3 scripts/test_gen_schema.py
Wired into codegen.yml so the guarantees cannot regress silently."""
import copy
import json
import sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_schema  # noqa: E402  (importable: generation runs only under __main__)

M = json.load(open("mainnet.json"))
T = json.load(open("testnet.json"))


def build(m, t):
    return gen_schema.generate(m, t)


def expect_exit(label, m, t, needle):
    try:
        build(m, t)
    except SystemExit as e:
        assert needle in str(e), f"{label}: wrong failure: {e}"
        print(f"  ok {label}")
        return
    raise AssertionError(f"{label}: generator should have FAILED and did not")


# 1. The live pair must build (sanity — the real run is codegen's).
build(copy.deepcopy(M), copy.deepcopy(T))
print("  ok live instances build")

# 2. Deleting a required field on ONE network must fail, not go optional
#    (declared requiredness — review finding).
t = copy.deepcopy(T)
del t["oracle_rules"]["waterx"]["rule_config_object"]
expect_exit("one-network field deletion fails", copy.deepcopy(M), t,
            "schema/optional-fields.json")

# 3. A corrupted id must fail the merge, not widen the map's schema to
#    plain string (conflict raising — review finding).
m = copy.deepcopy(M)
sym = next(iter(m["objects"]["perp"]["markets"]))
m["objects"]["perp"]["markets"][sym]["market"] = "0xdead"
expect_exit("corrupted id fails, never widens", m, copy.deepcopy(T), "type conflict")

# 4. A null leaf must fail, not become accept-anything.
m = copy.deepcopy(M)
m["objects"]["oracle"]["listing_cap"] = None
expect_exit("null leaf fails", m, copy.deepcopy(T), "null at")

# 5. A _comment in served data must fail, not be blessed as a property.
t = copy.deepcopy(T)
t["objects"]["oracle"]["_comment"] = "note"
expect_exit("_comment in data fails", copy.deepcopy(M), t, "_comment in instance data")

# 6. A stale optional-fields entry must fail (the list can only shrink):
#    simulate by making a declared-optional field present on BOTH networks.
m, t = copy.deepcopy(M), copy.deepcopy(T)
present = m["oracle_rules"].get("pyth_lazer") or t["oracle_rules"]["pyth_lazer"]
m["oracle_rules"]["pyth_lazer"] = copy.deepcopy(present)
t["oracle_rules"]["pyth_lazer"] = copy.deepcopy(present)
if "supra" in t["oracle_rules"]:
    m["oracle_rules"]["supra"] = copy.deepcopy(t["oracle_rules"]["supra"])
m["objects"]["faucet"] = copy.deepcopy(t["objects"]["faucet"])
m["objects"]["mock_usdsui"] = copy.deepcopy(t["objects"]["mock_usdsui"])
ex = m["objects"]["withdrawal_queue"].get("executors") or t["objects"]["withdrawal_queue"].get("executors")
m["objects"]["withdrawal_queue"]["executors"] = copy.deepcopy(ex)
t["objects"]["withdrawal_queue"]["executors"] = copy.deepcopy(ex)
expect_exit("stale optional-fields entry fails", m, t, "stale optional-fields")

# 7. Top-level requiredness is a decision: an undeclared new top key fails.
t2 = copy.deepcopy(T)
t2["mystery_section"] = {"x": 1}
expect_exit("undeclared top-level key fails", copy.deepcopy(M), t2,
            "neither in the required list nor declared")

# 8. Deleting a REQUIRED top-level key from one network must keep it required
#    in the schema (so ajv rejects the mutated instance) — never demote it.
t2 = copy.deepcopy(T)
del t2["evm"]
schema8 = build(copy.deepcopy(M), t2)
assert "evm" in schema8["required"], "evm must stay in root required"
print("  ok one-network top-level deletion cannot demote requiredness")

# 9. A single-instance subtree cannot silently shrink: deleting a child of
#    the mainnet-only pyth_lazer fails on its anchor.
m2 = copy.deepcopy(M)
del m2["oracle_rules"]["pyth_lazer"]["lazer_state_object"]
expect_exit("anchored child deletion fails", m2, copy.deepcopy(T),
            "anchored field oracle_rules/pyth_lazer/lazer_state_object is missing")

print("test_gen_schema: all guarantees hold")
