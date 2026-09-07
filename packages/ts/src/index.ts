/**
 * @waterx-protocol/config — the official typed reader for waterx-config.
 *
 * ONE public shape: the consolidated target format (docs/FLIP-PLAN.md).
 * Until flip day the CDN serves the legacy layout; this parser detects the
 * shape (`schema_version`) and lifts a legacy document into the target shape
 * via the same mapping the flip itself will use (src/lift.mjs), so consumers
 * migrate once and never see two formats:
 *
 *   import { loadWaterxConfig } from "@waterx-protocol/config";
 *   const cfg = await loadWaterxConfig("mainnet");
 *   cfg.oracle_rules.waterx.venue_feeds["BTCUSD"].sources; // fully typed
 *
 * Validators are GENERATED from the schemas (scripts/deref-schema.mjs →
 * json-schema-to-zod); CI fails if they drift. Do not edit schema*.ts by hand.
 *
 * Unknown fields are TOLERATED: consumers parse live CDN data that can gain
 * fields before this package version does. The strict reject-unknowns check is
 * the config repo's own ajv CI gate, where schema and data move together.
 */
import waterxConfigSchema from "./schema.ts";
import legacySchema from "./schema-legacy.ts";
// The flip mapping — single implementation shared with scripts/derive-target.mjs.
// Plain JS module (compiled via allowJs) so repo scripts can import it directly.
import { liftToTarget } from "./lift.mjs";
import type { z } from "zod";

export { waterxConfigSchema };

/** The full network document, in the consolidated (target) shape. */
export type WaterxConfig = z.infer<typeof waterxConfigSchema>;
export type WaterxPackages = WaterxConfig["packages"];
export type SymbolsRegistry = WaterxConfig["symbols"];
export type OracleRules = WaterxConfig["oracle_rules"];
export type VenueFeed = NonNullable<OracleRules["waterx"]>["venue_feeds"][string];
export type PerpMarket = NonNullable<WaterxConfig["objects"]["perp"]>["markets"][string];

export type Network = "mainnet" | "testnet";

/**
 * The ONLY sanctioned base URL. raw.githubusercontent.com is rate-limited
 * (429) and forbidden by the repo README — this loader exists so no consumer
 * ever hardcodes it again.
 */
export const CONFIG_CDN_BASE = "https://config.waterx.app";

export class WaterxConfigError extends Error {
  constructor(message: string, cause?: unknown) {
    super(message, { cause });
    this.name = "WaterxConfigError";
  }
}

export interface LoadOptions {
  /** Override the CDN base (tests, staging CDN). Never raw.githubusercontent.com. */
  baseUrl?: string;
  fetchImpl?: typeof fetch;
  /** Per-attempt timeout in ms (default 10_000). */
  timeoutMs?: number;
  /** Total attempts (default 3, exponential backoff). */
  attempts?: number;
}

/** Fetch + parse one network's config. Throws WaterxConfigError on any failure. */
export async function loadWaterxConfig(network: Network, opts: LoadOptions = {}): Promise<WaterxConfig> {
  const base = (opts.baseUrl ?? CONFIG_CDN_BASE).replace(/\/+$/, "");
  if (/raw\.githubusercontent\.com/.test(base)) {
    throw new WaterxConfigError(
      "raw.githubusercontent.com is not a config source (429-rate-limited; README forbids it). Use the CDN.",
    );
  }
  const url = `${base}/${network}.json`;
  const doFetch = opts.fetchImpl ?? fetch;
  const attempts = opts.attempts ?? 3;
  let lastErr: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), opts.timeoutMs ?? 10_000);
      try {
        const res = await doFetch(url, { signal: ctrl.signal });
        if (!res.ok) throw new WaterxConfigError(`GET ${url}: HTTP ${res.status}`);
        return parseWaterxConfig(await res.json(), network);
      } finally {
        clearTimeout(timer);
      }
    } catch (e) {
      lastErr = e;
      if (e instanceof WaterxConfigError && !/HTTP 5|abort/i.test(String(e.message))) throw e;
      if (i < attempts - 1) await new Promise((r) => setTimeout(r, 500 * 2 ** i));
    }
  }
  throw new WaterxConfigError(`failed to load ${url} after ${attempts} attempts`, lastErr);
}

function zodIssues(error: z.ZodError): string {
  return error.issues.slice(0, 5).map((i) => `${i.path.join(".")}: ${i.message}`).join("; ");
}

/**
 * Parse an already-fetched document (pinned file, test fixture) into the
 * target shape. Legacy-shape documents (no `schema_version`) are first
 * validated against the legacy schema, then lifted — so pre-flip consumers get
 * the exact post-flip shape today, and flip day is a non-event for them.
 */
export function parseWaterxConfig(doc: unknown, expectNetwork?: Network): WaterxConfig {
  let candidate = doc;
  const version = (doc as { schema_version?: unknown })?.schema_version;
  if (typeof version !== "number" || version < 2) {
    const legacy = legacySchema.safeParse(doc);
    if (!legacy.success) {
      throw new WaterxConfigError(`legacy config failed schema validation: ${zodIssues(legacy.error)}`);
    }
    try {
      // strict:false — a consumer must tolerate a legacy field added after its
      // pinned version; flip completeness is enforced by repo CI (derive-target).
      candidate = liftToTarget(legacy.data, { strict: false });
    } catch (e) {
      throw new WaterxConfigError(`legacy config could not be lifted to the target shape: ${String(e)}`, e);
    }
  }
  const parsed = waterxConfigSchema.safeParse(candidate);
  if (!parsed.success) {
    throw new WaterxConfigError(`config failed schema validation: ${zodIssues(parsed.error)}`);
  }
  if (expectNetwork && parsed.data.network !== expectNetwork) {
    throw new WaterxConfigError(`network mismatch: asked for ${expectNetwork}, document says ${parsed.data.network}`);
  }
  return parsed.data;
}
