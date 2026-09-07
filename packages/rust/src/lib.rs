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
    /// The document does not declare `schema_version` 2 — either a pre-flip
    /// legacy file or a future format this crate version does not speak.
    UnsupportedVersion(Option<i64>),
    NetworkMismatch { expected: String, got: String },
    #[cfg(feature = "fetch")]
    Http(reqwest::Error),
}

impl std::fmt::Display for ConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ConfigError::Parse(e) => write!(f, "config failed schema-derived parsing: {e}"),
            ConfigError::UnsupportedVersion(v) => write!(
                f,
                "unsupported config schema_version {v:?} — this crate speaks version 2 only"
            ),
            ConfigError::NetworkMismatch { expected, got } => {
                write!(f, "network mismatch: asked for {expected}, document says {got}")
            }
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
        Err(e) => parse_slow(json, e)?,
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
/// A missing/wrong `schema_version` becomes the legible [`ConfigError::UnsupportedVersion`];
/// the float spelling of 2 (producers that round-trip through a float writer
/// may emit 2.0 — same version, different token) is normalized and re-parsed,
/// so the tolerance costs the integer-spelled happy path nothing.
fn parse_slow(json: &str, typed_err: serde_json::Error) -> Result<WaterxConfig, ConfigError> {
    let Ok(mut value) = serde_json::from_str::<serde_json::Value>(json) else {
        return Err(ConfigError::Parse(typed_err));
    };
    let version = value.get("schema_version").and_then(|v| {
        v.as_i64().or_else(|| v.as_f64().filter(|f| f.fract() == 0.0).map(|f| f as i64))
    });
    if version != Some(SCHEMA_VERSION) {
        return Err(ConfigError::UnsupportedVersion(version));
    }
    value["schema_version"] = serde_json::json!(SCHEMA_VERSION);
    serde_json::from_value(value).map_err(ConfigError::Parse)
}

/// Fetch + parse one network's config from the CDN, with a 10s timeout.
#[cfg(feature = "fetch")]
pub async fn load_waterx_config(network: &str) -> Result<WaterxConfig, ConfigError> {
    let url = format!("{CONFIG_CDN_BASE}/{network}.json");
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(10))
        .build()
        .map_err(ConfigError::Http)?;
    let body = client
        .get(&url)
        .send()
        .await
        .map_err(ConfigError::Http)?
        .error_for_status()
        .map_err(ConfigError::Http)?
        .text()
        .await
        .map_err(ConfigError::Http)?;
    parse_waterx_config(&body, Some(network))
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
            assert!(cfg.oracle_rules.waterx.venue_feeds.contains_key("BTCUSD"));
            let wr = cfg.packages.get("waterx_rule").expect("waterx_rule identity");
            assert!(wr.published_at.as_deref().unwrap_or("").starts_with("0x"));
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
            (serde_json::json!(2.0), true),
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

    /// A mainnet binary must not silently load a testnet file.
    #[test]
    fn network_mismatch_rejected() {
        assert!(matches!(
            parse_waterx_config(&fixture("mainnet.json"), Some("testnet")),
            Err(ConfigError::NetworkMismatch { .. })
        ));
    }
}
