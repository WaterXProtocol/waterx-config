/**
 * @waterx-protocol/config — the official typed reader for waterx-config.
 *
 * The CDN serves ONE format: the consolidated shape (schema_version 2).
 *
 *   import { loadWaterxConfig } from "@waterx-protocol/config";
 *   const cfg = await loadWaterxConfig("mainnet");
 *   cfg.oracle_rules.waterx.venue_feeds["BTCUSD"].sources; // fully typed
 *
 * The validator is GENERATED from schema/waterx-config.schema.json; CI fails
 * if it drifts. Do not edit schema.ts by hand.
 *
 * Unknown fields are TOLERATED: consumers parse live CDN data that can gain
 * fields before this package version does. ID patterns, required fields and
 * the schema_version pin still bite; the strict reject-unknowns check is the
 * config repo's own ajv CI gate, where schema and data move together.
 */
import waterxConfigSchema from "./schema.ts";
import type { z } from "zod";

export { waterxConfigSchema };

/** The full network document. */
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
  /** HTTP status of the failed response, when the failure was an HTTP error. */
  readonly status?: number;
  constructor(message: string, opts: { cause?: unknown; status?: number } = {}) {
    super(message, { cause: opts.cause });
    this.name = "WaterxConfigError";
    this.status = opts.status;
  }
}

export interface LoadOptions {
  /** Override the CDN base (tests, staging CDN). Never raw.githubusercontent.com. */
  baseUrl?: string;
  fetchImpl?: typeof fetch;
  /** Per-attempt timeout in ms (default 10_000). */
  timeoutMs?: number;
  /** Total attempts (default 3, exponential backoff). Minimum 1. */
  attempts?: number;
}

/** Statuses worth retrying: server errors, and the rate/timeout pair. */
const RETRYABLE_STATUS = (s: number) => s >= 500 || s === 429 || s === 408;

/** Fetch + parse one network's config. Throws WaterxConfigError on any failure. */
export async function loadWaterxConfig(network: Network, opts: LoadOptions = {}): Promise<WaterxConfig> {
  const base = (opts.baseUrl ?? CONFIG_CDN_BASE).replace(/\/+$/, "");
  if (/raw\.githubusercontent\.com/i.test(base)) {
    throw new WaterxConfigError(
      "raw.githubusercontent.com is not a config source (429-rate-limited; README forbids it). Use the CDN.",
    );
  }
  const url = `${base}/${network}.json`;
  const doFetch = opts.fetchImpl ?? fetch;
  const attempts = Math.max(1, opts.attempts ?? 3);
  let lastErr: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      const res = await doFetch(url, { signal: AbortSignal.timeout(opts.timeoutMs ?? 10_000) });
      if (!res.ok) throw new WaterxConfigError(`GET ${url}: HTTP ${res.status}`, { status: res.status });
      return parseWaterxConfig(await res.json(), network);
    } catch (e) {
      lastErr = e;
      // Retry classification by TYPE, never by message text (a URL containing
      // "abort" must not flip a 404 into a retryable): retryable = HTTP 5xx /
      // 429 / 408, and timeouts/aborts. Everything else is permanent.
      const retryable =
        (e instanceof WaterxConfigError && e.status !== undefined && RETRYABLE_STATUS(e.status)) ||
        (e instanceof DOMException && (e.name === "TimeoutError" || e.name === "AbortError")) ||
        (!(e instanceof WaterxConfigError) && e instanceof Error && !(e instanceof TypeError && /json/i.test(e.message)));
      if (!retryable) throw e;
      if (i < attempts - 1) await new Promise((r) => setTimeout(r, 500 * 2 ** i));
    }
  }
  throw new WaterxConfigError(`failed to load ${url} after ${attempts} attempts`, { cause: lastErr });
}

/** Parse an already-fetched document (pinned file, test fixture). */
export function parseWaterxConfig(doc: unknown, expectNetwork?: Network): WaterxConfig {
  const parsed = waterxConfigSchema.safeParse(doc);
  if (!parsed.success) {
    const issues = parsed.error.issues.slice(0, 5).map((i) => `${i.path.join(".")}: ${i.message}`).join("; ");
    throw new WaterxConfigError(`config failed schema validation: ${issues}`);
  }
  if (expectNetwork && parsed.data.network !== expectNetwork) {
    throw new WaterxConfigError(`network mismatch: asked for ${expectNetwork}, document says ${parsed.data.network}`);
  }
  return parsed.data;
}
