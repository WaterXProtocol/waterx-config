/**
 * @waterx/config — the official typed reader for waterx-config.
 *
 * The CDN serves ONE format: the consolidated shape (schema_version 2).
 *
 *   import { loadWaterxConfig } from "@waterx/config";
 *   const cfg = await loadWaterxConfig("mainnet");
 *   cfg.objects.oracle.aggregators["BTCUSD"]; // fully typed
 *
 * The validator is GENERATED from schema/waterx-config.schema.json; CI fails
 * if it drifts. Do not edit schema.ts by hand.
 *
 * Unknown fields are ACCEPTED but NOT PRESERVED: parsing validates live CDN
 * data that can gain fields before this package version does, and returns
 * the typed view — zod strips keys this version doesn't know (open maps like
 * `packages` keep every entry; unknown FIELDS on known objects are dropped).
 * Therefore NEVER re-serialize a parse result back into a config file — a
 * read-modify-write tool must patch the ORIGINAL document and use
 * parseWaterxConfig only to validate it. ID patterns, required fields and
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
// Direct index type — the schema marks this required, and if that ever
// changes the compiler should break the alias loudly (review finding:
// NonNullable<> wrappers taught consumers the wrong nullability).
export type PerpMarket = WaterxConfig["objects"]["perp"]["markets"][string];

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
  /** Base backoff delay in ms (default 500; attempt i waits base * 2^i). */
  backoffBaseMs?: number;
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
  try {
    new URL(url); // a malformed baseUrl is permanent — fail once, before the loop
  } catch (e) {
    throw new WaterxConfigError(`invalid config URL ${url}`, { cause: e });
  }
  const doFetch = opts.fetchImpl ?? fetch;
  // Number.isFinite guards NaN/Infinity (Math.max(1, NaN) is NaN — review
  // finding: a NaN here made the loop body never run).
  const attempts = Number.isFinite(opts.attempts) ? Math.max(1, Math.floor(opts.attempts!)) : 3;
  let lastErr: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      const res = await doFetch(url, { signal: AbortSignal.timeout(opts.timeoutMs ?? 10_000) });
      if (!res.ok) throw new WaterxConfigError(`GET ${url}: HTTP ${res.status}`, { status: res.status });
      return parseWaterxConfig(await res.json(), network);
    } catch (e) {
      lastErr = e;
      // Retry classification by TYPE, never by message text. Our own errors
      // retry only on a retryable HTTP status (schema/network-mismatch
      // failures carry no status and are permanent). A SyntaxError is a
      // malformed body — permanent (NOT TypeError: Response.json() rejects
      // with SyntaxError; review finding — the old TypeError guard was dead
      // and re-fetched unparseable bodies). Everything else (network
      // TypeError, timeout/abort DOMException) is transient.
      const retryable = e instanceof WaterxConfigError
        ? e.status !== undefined && RETRYABLE_STATUS(e.status)
        : !(e instanceof SyntaxError);
      if (!retryable) throw e;
      if (i < attempts - 1) await new Promise((r) => setTimeout(r, (opts.backoffBaseMs ?? 500) * 2 ** i));
    }
  }
  // Surface the last HTTP status so circuit-breakers can distinguish 429
  // from 5xx without string-matching the cause (review finding).
  throw new WaterxConfigError(`failed to load ${url} after ${attempts} attempts`, {
    cause: lastErr,
    status: lastErr instanceof WaterxConfigError ? lastErr.status : undefined,
  });
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
