/**
 * @waterx-protocol/config — the official typed reader for waterx-config.
 *
 * One import replaces every hand-rolled partial type in SDK/FE/BE/agent:
 *
 *   import { loadWaterxConfig } from "@waterx-protocol/config";
 *   const cfg = await loadWaterxConfig("mainnet");
 *   cfg.packages.waterx_rule?.feeds["BTCUSD"].sources; // fully typed
 *
 * The runtime validator is GENERATED from schema/waterx-config.schema.json
 * (scripts/deref-schema.mjs → json-schema-to-zod); CI fails if it drifts.
 * Do not edit schema.ts by hand.
 */
import waterxConfigSchema from "./schema.ts";
import waterxConfigSchemaTolerant from "./schema-tolerant.ts";
import type { z } from "zod";

export { waterxConfigSchema, waterxConfigSchemaTolerant };

/** The full network file, inferred from the generated Zod schema. */
export type WaterxConfig = z.infer<typeof waterxConfigSchema>;
export type WaterxPackages = WaterxConfig["packages"];
export type WaterxRulePackage = NonNullable<WaterxPackages["waterx_rule"]>;
export type WaterxRuleFeed = WaterxRulePackage["feeds"][string];
export type PythRuleFeed = NonNullable<WaterxPackages["pyth_rule"]>["feeds"][string];
export type PerpMarket = NonNullable<WaterxPackages["waterx_perp"]>["markets"][string];

export type Network = "mainnet" | "testnet";

/**
 * The ONLY sanctioned base URL. raw.githubusercontent.com is rate-limited
 * (429) and explicitly forbidden by the repo README — this loader exists so
 * no consumer ever hardcodes it again.
 */
export const CONFIG_CDN_BASE = "https://config.waterx.app";

export class WaterxConfigError extends Error {
  override readonly cause?: unknown;
  constructor(message: string, cause?: unknown) {
    super(message);
    this.name = "WaterxConfigError";
    this.cause = cause;
  }
}

export interface ParseOptions {
  /**
   * Reject unknown fields. Default FALSE: consumers parse live CDN data that
   * can gain fields before this package version does — tolerating unknowns is
   * what keeps an additive config change from breaking deployed consumers.
   * Strict mode is for tests/CI against a pinned document; the config repo's
   * own ajv gate is the authoritative strict check.
   */
  strict?: boolean;
}

export interface LoadOptions extends ParseOptions {
  /** Override the CDN base (tests, staging CDN). Never point this at raw.githubusercontent.com. */
  baseUrl?: string;
  fetchImpl?: typeof fetch;
  /** Per-attempt timeout in ms (default 10_000). */
  timeoutMs?: number;
  /** Total attempts (default 3, exponential backoff). */
  attempts?: number;
}

/** Fetch + strictly parse one network's config. Throws WaterxConfigError on any failure. */
export async function loadWaterxConfig(network: Network, opts: LoadOptions = {}): Promise<WaterxConfig> {
  const base = (opts.baseUrl ?? CONFIG_CDN_BASE).replace(/\/+$/, "");
  if (/raw\.githubusercontent\.com/.test(base)) {
    throw new WaterxConfigError("raw.githubusercontent.com is not a config source (429-rate-limited; README forbids it). Use the CDN.");
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
        return parseWaterxConfig(await res.json(), network, opts);
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

/** Parse an already-fetched document (pinned file, test fixture). Tolerant of
 * unknown fields by default — see ParseOptions.strict. */
export function parseWaterxConfig(doc: unknown, expectNetwork?: Network, opts: ParseOptions = {}): WaterxConfig {
  const schema = opts.strict ? waterxConfigSchema : waterxConfigSchemaTolerant;
  const parsed = schema.safeParse(doc);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .slice(0, 5)
      .map((i) => `${i.path.join(".")}: ${i.message}`)
      .join("; ");
    throw new WaterxConfigError(`config failed schema validation: ${issues}`);
  }
  if (expectNetwork && parsed.data.network !== expectNetwork) {
    throw new WaterxConfigError(`network mismatch: asked for ${expectNetwork}, document says ${parsed.data.network}`);
  }
  return parsed.data as WaterxConfig;
}
