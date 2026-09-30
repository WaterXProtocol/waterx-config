"""Post-pass over quicktype's generated.rs: add skip_serializing_if to every
Option field so serialization round-trips (quicktype has no flag for this;
without it absent optionals serialize as `"field": null`, which ajv and the
zod parser both reject — review finding). Run right after quicktype, from the
repo root; idempotent."""
import re

P = "packages/rust/src/generated.rs"
ATTR = '#[serde(skip_serializing_if = "Option::is_none")]'
src = open(P).read()
lines = src.split("\n")
out = []
for line in lines:
    m = re.match(r"^(\s*)pub [a-z_0-9]+: Option<", line)
    if m and (not out or ATTR not in out[-1]):
        out.append(f"{m.group(1)}{ATTR}")
    out.append(line)
open(P, "w").write("\n".join(out))
print(f"{P}: skip_serializing_if added to Option fields")
