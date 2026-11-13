// Inspect raw JSON members rather than a parser's last-wins object representation.
// Used by validate.yml for both served network documents; no dependencies.
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const assertNoDuplicateKeys = (source, filename = "<json>") => {
  // Establish valid JSON grammar first. This value is never written back to disk.
  JSON.parse(source);
  const objects = [];
  // Consume entire quoted strings, including escapes, so braces in values do
  // not affect nesting. Only a string followed by ':' can be an object key.
  for (const match of source.matchAll(/"(?:\\.|[^"\\])*"|[{}\[\]]/g)) {
    const token = match[0];
    if (token === "{") objects.push(new Set());
    else if (token === "[") objects.push(null);
    else if (token === "}" || token === "]") objects.pop();
    else if (/^\s*:/.test(source.slice(match.index + token.length))) {
      const key = JSON.parse(token);
      const keys = objects.at(-1);
      if (keys.has(key)) {
        const line = source.slice(0, match.index).split("\n").length;
        throw new SyntaxError(
          filename + ":" + line + ": duplicate JSON key " + JSON.stringify(key),
        );
      }
      keys.add(key);
    }
  }
};

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const files = process.argv.slice(2);
  for (const file of files.length > 0
    ? files
    : ["mainnet.json", "testnet.json"]) {
    const path = resolve(fileURLToPath(new URL("..", import.meta.url)), file);
    try {
      assertNoDuplicateKeys(readFileSync(path, "utf8"), file);
      console.log(file + ": no duplicate JSON keys");
    } catch (error) {
      console.error(error.message);
      process.exitCode = 1;
    }
  }
}
