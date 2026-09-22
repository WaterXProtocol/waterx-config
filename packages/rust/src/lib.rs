//! waterx-config — the official typed reader for WaterX network files.
//!
//! The CDN serves ONE format: the consolidated shape (`schema_version` 2).
//! Types in [`generated`] are produced from `schema/waterx-config.schema.json`
//! by quicktype (see the codegen workflow); do not edit by hand.
//!
//! Unknown fields are TOLERATED (serde default): live CDN data can gain fields
//! before a deployed consumer's pinned crate does. The strict reject-unknowns
//! and pattern checks are the repo's own ajv CI gate, where schema and data
//! move together; this crate enforces structure, types, the version pin, and
//! (when asked) the network.

pub mod generated;

pub use generated::WaterxConfig;

#[derive(Debug)]
#[non_exhaustive]
pub enum ConfigError {
    Parse(serde_json::Error),
    /// The document does not declare an integer `schema_version` of 2.
    /// `Some(v)` is a different (e.g. future) format; `None` means the field
    /// is missing or not an integer (a pre-flip legacy file, a stringified
    /// "2" from a templating layer, or a fractional/overflowing number).
    UnsupportedVersion(Option<i64>),
    NetworkMismatch { expected: String, got: String },
    /// The base URL is a forbidden source (raw.githubusercontent.com is
    /// rate-limited and banned by the repo README — same guard as the TS loader).
    #[cfg(feature = "fetch")]
    ForbiddenSource(String),
    #[cfg(feature = "fetch")]
    Http(reqwest::Error),
}

impl std::fmt::Display for ConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ConfigError::Parse(e) => write!(f, "config failed schema-derived parsing: {e}"),
            ConfigError::UnsupportedVersion(v) => match v {
                Some(v) => write!(f, "unsupported config schema_version {v} — this crate speaks version 2 only"),
                None => write!(f, "config schema_version is missing or not an integer — this crate speaks version 2 (integer) only"),
            },
            ConfigError::NetworkMismatch { expected, got } => {
                write!(f, "network mismatch: asked for {expected}, document says {got}")
            }
            #[cfg(feature = "fetch")]
            ConfigError::ForbiddenSource(base) => write!(
                f,
                "{base} is not a config source (raw.githubusercontent.com is 429-rate-limited; README forbids it) — use the CDN"
            ),
            #[cfg(feature = "fetch")]
            ConfigError::Http(e) => write!(f, "config fetch failed: {e}"),
        }
    }
}
impl std::error::Error for ConfigError {}

/// The ONLY sanctioned base URL. raw.githubusercontent.com is rate-limited and
/// forbidden by the repo README.
pub const CONFIG_CDN_BASE: &str = "https://config.waterx.app";

/// The one format this crate speaks. Hand-pinned because quicktype flattens
/// the schema's one-value enum to a plain i64; `schema_pin_matches_schema`
/// asserts it against the schema so this copy cannot drift.
pub const SCHEMA_VERSION: i64 = 2;

fn network_str(n: &generated::Network) -> &'static str {
    match n {
        generated::Network::Mainnet => "mainnet",
        generated::Network::Testnet => "testnet",
    }
}

/// Parse an already-fetched document. `expect_network`, when given, must match
/// the document's own `network` field — the guard that stops a mainnet binary
/// silently loading a testnet file.
pub fn parse_waterx_config(json: &str, expect_network: Option<&str>) -> Result<WaterxConfig, ConfigError> {
    // Fast path: one typed pass. `schema_version` is a required i64, so a
    // legacy (pre-flip) document cannot deserialize past this line.
    let cfg = match serde_json::from_str::<WaterxConfig>(json) {
        Ok(cfg) if cfg.schema_version == SCHEMA_VERSION => cfg,
        Ok(cfg) => return Err(ConfigError::UnsupportedVersion(Some(cfg.schema_version))),
        Err(e) => return parse_slow(json, e),
    };
    if let Some(expected) = expect_network {
        let got = network_str(&cfg.network);
        if got != expected {
            return Err(ConfigError::NetworkMismatch { expected: expected.into(), got: got.into() });
        }
    }
    Ok(cfg)
}

/// Cold path, entered only when the typed parse fails: classify the failure.
/// A missing/non-integer/wrong `schema_version` becomes the legible
/// [`ConfigError::UnsupportedVersion`]; anything else returns the ORIGINAL
/// typed error — the only one carrying line/column (review finding: the old
/// re-parse discarded it, and its float-2.0 tolerance served a producer that
/// does not exist while every other integer field stayed strict anyway).
fn parse_slow(json: &str, typed_err: serde_json::Error) -> Result<WaterxConfig, ConfigError> {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(json) else {
        return Err(ConfigError::Parse(typed_err));
    };
    match value.get("schema_version").and_then(serde_json::Value::as_i64) {
        Some(SCHEMA_VERSION) => Err(ConfigError::Parse(typed_err)),
        other => Err(ConfigError::UnsupportedVersion(other)),
    }
}

/// Host-exact forbidden-source test, applied to the initial URL AND every
/// redirect hop (review finding: the base-string guard alone was bypassable
/// by an allowed URL redirecting to raw.githubusercontent.com).
#[cfg(feature = "fetch")]
fn forbidden_host(host: &str) -> bool {
    let h = host.to_ascii_lowercase();
    h == "raw.githubusercontent.com" || h.ends_with(".raw.githubusercontent.com")
}

/// One process-wide client: rebuilding it per call re-parses the root cert
/// store and drops the connection pool — and the CDN's cache headers are
/// tuned for re-polling consumers (review finding). The redirect policy
/// vets every hop's host.
#[cfg(feature = "fetch")]
fn http_client() -> &'static reqwest::Client {
    static CLIENT: std::sync::OnceLock<reqwest::Client> = std::sync::OnceLock::new();
    CLIENT.get_or_init(|| {
        reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(10))
            .redirect(reqwest::redirect::Policy::custom(|attempt| {
                if attempt.url().host_str().is_some_and(forbidden_host) {
                    attempt.error("redirect to a forbidden config source (raw.githubusercontent.com)")
                } else if attempt.previous().len() > 5 {
                    attempt.error("too many redirects")
                } else {
                    attempt.follow()
                }
            }))
            .build()
            .expect("default reqwest client")
    })
}

/// Fetch + parse one network's config from the CDN (10s per-attempt timeout,
/// 3 attempts with exponential backoff on 429/408/5xx and transport errors —
/// the same classification as the TS loader).
#[cfg(feature = "fetch")]
pub async fn load_waterx_config(network: &str) -> Result<WaterxConfig, ConfigError> {
    load_waterx_config_from(CONFIG_CDN_BASE, network).await
}

/// Retry backoff base; tiny under test so the retry loop is exercisable fast.
#[cfg(all(feature = "fetch", not(test)))]
const BACKOFF_BASE_MS: u64 = 500;
#[cfg(all(feature = "fetch", test))]
const BACKOFF_BASE_MS: u64 = 1;

/// Same as [`load_waterx_config`], from an alternative base URL (the staging
/// CDN alias, a test server). raw.githubusercontent.com is refused — enforced,
/// not just documented (same guard as the TS loader).
#[cfg(feature = "fetch")]
pub async fn load_waterx_config_from(base: &str, network: &str) -> Result<WaterxConfig, ConfigError> {
    if base.to_ascii_lowercase().contains("raw.githubusercontent.com") {
        return Err(ConfigError::ForbiddenSource(base.to_string()));
    }
    let url = format!("{}/{network}.json", base.trim_end_matches('/'));
    // Normalized host check on the parsed URL (the substring guard above is
    // a fast path; this is the authoritative one — redirect hops get the
    // same test in the client's redirect policy).
    if let Ok(parsed) = reqwest::Url::parse(&url) {
        if parsed.host_str().is_some_and(forbidden_host) {
            return Err(ConfigError::ForbiddenSource(base.to_string()));
        }
    }
    let mut last: Option<ConfigError> = None;
    for attempt in 0..3u32 {
        if attempt > 0 {
            tokio::time::sleep(std::time::Duration::from_millis(BACKOFF_BASE_MS * (1 << (attempt - 1)))).await;
        }
        match http_client().get(&url).send().await {
            Ok(resp) => {
                let status = resp.status();
                let retryable = status.as_u16() == 429 || status.as_u16() == 408 || status.is_server_error();
                match resp.error_for_status() {
                    // A parse/network-mismatch failure is permanent — return it as-is.
                    Ok(ok) => match ok.text().await {
                        Ok(body) => return parse_waterx_config(&body, Some(network)),
                        Err(e) => last = Some(ConfigError::Http(e)), // body cut off mid-read: retry
                    },
                    Err(e) => {
                        let err = ConfigError::Http(e);
                        if !retryable {
                            return Err(err);
                        }
                        last = Some(err);
                    }
                }
            }
            // Transport errors (DNS, refused, timeout) are transient.
            Err(e) => last = Some(ConfigError::Http(e)),
        }
    }
    Err(last.expect("at least one attempt ran"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(rel: &str) -> String {
        std::fs::read_to_string(format!("{}/../../{rel}", env!("CARGO_MANIFEST_DIR"))).unwrap()
    }

    /// The schema↔data↔parser triangle: both live instances MUST parse.
    #[test]
    fn both_networks_parse() {
        for net in ["mainnet", "testnet"] {
            let cfg = parse_waterx_config(&fixture(&format!("{net}.json")), Some(net))
                .unwrap_or_else(|e| panic!("{net}: {e}"));
            assert_eq!(cfg.schema_version, 2);
            assert!(!cfg.symbols.is_empty() && cfg.symbols.contains_key("BTCUSD"),
                "{net}: the symbols universe must exist and hold the flagship symbol");
            assert!(cfg.objects.oracle.aggregators.contains_key("BTCUSD"));
            let wr = cfg.packages.get("waterx_rule").expect("waterx_rule identity");
            // published_at is a REQUIRED String now (identity trio; review finding)
            assert!(wr.published_at.starts_with("0x"));
        }
    }

    /// Forward-compat: unknown fields and NEW packages are tolerated/visible.
    #[test]
    fn unknown_fields_tolerated_and_new_packages_visible() {
        let mut doc: serde_json::Value = serde_json::from_str(&fixture("mainnet.json")).unwrap();
        doc["oracle_rules"]["waterx"]["surprise"] = serde_json::json!(1);
        doc["packages"]["brand_new_pkg"] = serde_json::json!({
            "published_at": format!("0x{}", "a".repeat(64)),
            "original_id": format!("0x{}", "b".repeat(64)),
            "version": 1
        });
        let cfg = parse_waterx_config(&doc.to_string(), None).unwrap();
        assert!(cfg.packages.contains_key("brand_new_pkg"), "uniform map keeps new packages visible");
    }

    /// The version pin accepts the float spelling of 2 and nothing else.
    #[test]
    fn version_pin() {
        let base: serde_json::Value = serde_json::from_str(&fixture("mainnet.json")).unwrap();
        for (v, ok) in [
            (serde_json::json!(2), true),
            (serde_json::json!(2.0), false), // not an integer token; no producer emits it
            (serde_json::json!(3), false),
            (serde_json::json!(2.5), false),
            (serde_json::json!("2"), false),
        ] {
            let mut doc = base.clone();
            doc["schema_version"] = v.clone();
            let r = parse_waterx_config(&doc.to_string(), None);
            assert_eq!(r.is_ok(), ok, "schema_version {v} → {r:?}");
        }
        let mut doc = base;
        doc.as_object_mut().unwrap().remove("schema_version");
        assert!(matches!(
            parse_waterx_config(&doc.to_string(), None),
            Err(ConfigError::UnsupportedVersion(None))
        ), "a legacy (pre-flip) document is refused with a version error");
    }

    /// The hand-pinned SCHEMA_VERSION must equal the schema's enum — the one
    /// copy quicktype cannot carry (it flattens a one-value enum to i64).
    #[test]
    fn schema_pin_matches_schema() {
        let schema: serde_json::Value =
            serde_json::from_str(&fixture("schema/waterx-config.schema.json")).unwrap();
        assert_eq!(
            schema["properties"]["schema_version"]["enum"],
            serde_json::json!([SCHEMA_VERSION])
        );
    }

    /// A genuine shape error (version fine) must surface the TYPED error,
    /// which carries line/column — not a repackaged one without position.
    #[test]
    fn shape_errors_keep_position_info() {
        let mut doc: serde_json::Value = serde_json::from_str(&fixture("mainnet.json")).unwrap();
        doc["packages"]["waterx_rule"]["version"] = serde_json::json!("two");
        let err = parse_waterx_config(&serde_json::to_string_pretty(&doc).unwrap(), None).unwrap_err();
        match err {
            ConfigError::Parse(e) => {
                assert!(e.line() > 0, "typed serde error must keep its position: {e}");
            }
            other => panic!("expected Parse, got {other}"),
        }
    }

    /// Round-trip: serializing a parsed config must not emit `null` for
    /// absent optionals (ajv and zod both reject null there).
    #[test]
    fn serialization_round_trips_without_nulls() {
        for net in ["mainnet", "testnet"] {
            let cfg = parse_waterx_config(&fixture(&format!("{net}.json")), Some(net)).unwrap();
            let out = serde_json::to_string(&cfg).unwrap();
            assert!(!out.contains(":null") && !out.contains(": null"),
                "{net}: absent Options must be skipped, not serialized as null");
            parse_waterx_config(&out, Some(net)).unwrap_or_else(|e| panic!("{net} re-parse: {e}"));
        }
    }

    /// A mainnet binary must not silently load a testnet file.
    #[test]
    fn network_mismatch_rejected() {
        assert!(matches!(
            parse_waterx_config(&fixture("mainnet.json"), Some("testnet")),
            Err(ConfigError::NetworkMismatch { .. })
        ));
    }

    /// The raw.githubusercontent ban is enforced, case-insensitively, before
    /// any network I/O.
    #[cfg(feature = "fetch")]
    #[tokio::test]
    async fn raw_githubusercontent_refused() {
        for base in ["https://raw.githubusercontent.com/x/y/main", "https://RAW.GithubUserContent.com/x"] {
            assert!(matches!(
                load_waterx_config_from(base, "mainnet").await,
                Err(ConfigError::ForbiddenSource(_))
            ));
        }
    }

    /// Retryable statuses are retried (3 attempts), and the final error is
    /// the HTTP error — exercised against a real local socket.
    #[cfg(feature = "fetch")]
    #[tokio::test]
    async fn retryable_status_is_retried_three_times() {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let hits = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let hits2 = hits.clone();
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut s) = stream else { break };
                let mut buf = [0u8; 1024];
                let _ = s.read(&mut buf);
                hits2.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                let _ = s.write_all(b"HTTP/1.1 429 Too Many Requests\r\ncontent-length: 0\r\nconnection: close\r\n\r\n");
            }
        });
        let err = load_waterx_config_from(&format!("http://{addr}"), "mainnet").await.unwrap_err();
        assert!(matches!(err, ConfigError::Http(_)), "final error keeps the HTTP cause: {err}");
        assert_eq!(hits.load(std::sync::atomic::Ordering::SeqCst), 3, "429 must be retried to exhaustion");
    }

    /// A redirect to the forbidden source must be refused mid-flight — the
    /// initial-URL guard alone is bypassable via Location (review finding).
    #[cfg(feature = "fetch")]
    #[tokio::test]
    async fn redirect_to_forbidden_source_refused() {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut s) = stream else { break };
                let mut buf = [0u8; 1024];
                let _ = s.read(&mut buf);
                let _ = s.write_all(b"HTTP/1.1 301 Moved Permanently\r\nlocation: https://raw.githubusercontent.com/WaterXProtocol/waterx-config/main/mainnet.json\r\ncontent-length: 0\r\nconnection: close\r\n\r\n");
            }
        });
        let err = load_waterx_config_from(&format!("http://{addr}"), "mainnet").await.unwrap_err();
        // reqwest wraps the policy's message: assert the refusal kind, and
        // find our policy text in the source chain.
        let ConfigError::Http(e) = &err else { panic!("expected Http, got {err}") };
        assert!(e.is_redirect(), "the redirect policy must be what refused it: {e}");
        let mut cause: Option<&dyn std::error::Error> = Some(e);
        let mut found = false;
        while let Some(c) = cause {
            if c.to_string().contains("forbidden config source") { found = true; break; }
            cause = c.source();
        }
        assert!(found, "policy reason must be in the error chain: {e:?}");
    }

    /// A permanent status (404) is NOT retried.
    #[cfg(feature = "fetch")]
    #[tokio::test]
    async fn permanent_status_is_not_retried() {
        use std::io::{Read, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = listener.local_addr().unwrap();
        let hits = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let hits2 = hits.clone();
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut s) = stream else { break };
                let mut buf = [0u8; 1024];
                let _ = s.read(&mut buf);
                hits2.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                let _ = s.write_all(b"HTTP/1.1 404 Not Found\r\ncontent-length: 0\r\nconnection: close\r\n\r\n");
            }
        });
        let err = load_waterx_config_from(&format!("http://{addr}"), "mainnet").await.unwrap_err();
        assert!(matches!(err, ConfigError::Http(_)));
        assert_eq!(hits.load(std::sync::atomic::Ordering::SeqCst), 1, "404 must not be retried");
    }
}
