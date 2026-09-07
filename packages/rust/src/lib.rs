//! waterx-config — the official typed reader for WaterX network files.
//!
//! ONE public shape: the consolidated target format (docs/FLIP-PLAN.md).
//! Until flip day the CDN serves the legacy layout; [`parse_waterx_config`]
//! detects the shape (`schema_version`) and lifts a legacy document via
//! [`lift`] — the same mapping flip day itself uses — so consumers migrate
//! once and never see two formats.
//!
//! Types in [`generated`] are produced from the target schema by quicktype
//! (see the codegen workflow); do not edit by hand.
//! Unknown fields are TOLERATED (serde default): live CDN data can gain fields
//! before a deployed consumer's pinned crate does. The strict reject-unknowns
//! check is the repo's own ajv CI gate.

pub mod generated;
pub mod lift;

pub use generated::WaterxConfig;

#[derive(Debug)]
pub enum ConfigError {
    Parse(serde_json::Error),
    Lift(lift::LiftError),
    #[cfg(feature = "fetch")]
    NetworkMismatch { expected: String, got: String },
    #[cfg(feature = "fetch")]
    Http(reqwest::Error),
}

impl std::fmt::Display for ConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ConfigError::Parse(e) => write!(f, "config failed schema-derived parsing: {e}"),
            ConfigError::Lift(e) => write!(f, "{e}"),
            #[cfg(feature = "fetch")]
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

/// Parse an already-fetched document into the target shape, lifting a
/// legacy-shape document (no `schema_version`) transparently.
pub fn parse_waterx_config(json: &str) -> Result<WaterxConfig, ConfigError> {
    let value: serde_json::Value = serde_json::from_str(json).map_err(ConfigError::Parse)?;
    let is_target = value
        .get("schema_version")
        .and_then(serde_json::Value::as_i64)
        .is_some_and(|v| v >= 2);
    let target = if is_target {
        value
    } else {
        // strict:false — a consumer must tolerate a legacy field added after
        // its pinned crate version; flip completeness is repo CI's job.
        lift::lift_to_target(&value, false).map_err(ConfigError::Lift)?
    };
    serde_json::from_value(target).map_err(ConfigError::Parse)
}

/// Fetch + parse one network's config from the CDN.
#[cfg(feature = "fetch")]
pub async fn load_waterx_config(network: &str) -> Result<WaterxConfig, ConfigError> {
    let url = format!("{CONFIG_CDN_BASE}/{network}.json");
    let body = reqwest::get(&url)
        .await
        .map_err(ConfigError::Http)?
        .error_for_status()
        .map_err(ConfigError::Http)?
        .text()
        .await
        .map_err(ConfigError::Http)?;
    let cfg = parse_waterx_config(&body)?;
    let got = match cfg.network {
        generated::Network::Mainnet => "mainnet",
        generated::Network::Testnet => "testnet",
    };
    if got != network {
        return Err(ConfigError::NetworkMismatch { expected: network.into(), got: got.into() });
    }
    Ok(cfg)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(rel: &str) -> String {
        std::fs::read_to_string(format!("{}/../../{rel}", env!("CARGO_MANIFEST_DIR"))).unwrap()
    }

    /// The LIVE legacy files must lift + parse into the target shape, with the
    /// identity fields surviving at the same path (the flip-immunity guarantee).
    #[test]
    fn legacy_files_lift_and_parse() {
        for net in ["mainnet", "testnet"] {
            let cfg = parse_waterx_config(&fixture(&format!("{net}.json")))
                .unwrap_or_else(|e| panic!("{net}: {e}"));
            assert!(cfg.symbols.len() >= 31, "{net} symbols universe");
            assert!(cfg.oracle_rules.waterx.venue_feeds.contains_key("BTCUSD"));
            let wr = cfg.packages.get("waterx_rule").expect("waterx_rule identity");
            assert!(wr.published_at.as_deref().unwrap_or("").starts_with("0x"));
        }
    }

    /// A natively-target document parses identically (flip-day behavior).
    #[test]
    fn native_target_round_trips() {
        let legacy: serde_json::Value = serde_json::from_str(&fixture("mainnet.json")).unwrap();
        let lifted = lift::lift_to_target(&legacy, true).unwrap();
        let cfg = parse_waterx_config(&lifted.to_string()).unwrap();
        assert!(cfg.oracle_rules.waterx.venue_feeds.contains_key("BTCUSD"));
    }

    /// Forward-compat (same policy as the TS parser): unknown fields are
    /// tolerated on BOTH shapes at parse time — a consumer must survive a
    /// config addition made after its pinned version. Flip completeness is
    /// enforced by the STRICT lift, which repo CI runs (derive-target).
    #[test]
    fn unknown_field_is_tolerated_by_parser_but_caught_by_strict_lift() {
        let mut doc: serde_json::Value = serde_json::from_str(&fixture("mainnet.json")).unwrap();
        doc["packages"]["waterx_rule"]["surprise"] = serde_json::json!(1);
        assert!(parse_waterx_config(&doc.to_string()).is_ok(), "parser must tolerate");
        assert!(lift::lift_to_target(&doc, true).is_err(), "strict lift must catch");
        let legacy: serde_json::Value = serde_json::from_str(&fixture("mainnet.json")).unwrap();
        let mut lifted = lift::lift_to_target(&legacy, true).unwrap();
        lifted["surprise_top"] = serde_json::json!(1);
        assert!(parse_waterx_config(&lifted.to_string()).is_ok());
    }

    /// Cross-language drift guard: this port must produce EXACTLY what the
    /// canonical node lift (packages/ts/src/lift.mjs) produced. Run
    /// `node scripts/derive-target.mjs emit .build-target` first (CI does).
    #[test]
    fn lift_matches_node_lift() {
        for net in ["mainnet", "testnet"] {
            let path = format!("{}/../../.build-target/{net}.json", env!("CARGO_MANIFEST_DIR"));
            let node_out = std::fs::read_to_string(&path).unwrap_or_else(|_| {
                panic!("{path} missing — run `node scripts/derive-target.mjs emit .build-target` first; \
                        this test is the ONLY cross-language lift coupling and must not silently skip")
            });
            let node_val: serde_json::Value = serde_json::from_str(&node_out).unwrap();
            let legacy: serde_json::Value = serde_json::from_str(&fixture(&format!("{net}.json"))).unwrap();
            let rust_val = lift::lift_to_target(&legacy, true).unwrap();
            assert_eq!(rust_val, node_val, "{net}: rust lift drifted from node lift");
        }
    }
}
