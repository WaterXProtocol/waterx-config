//! waterx-config — the official typed reader for WaterX network files.
//!
//! Types in [`generated`] are produced from `schema/waterx-config.schema.json`
//! by quicktype (see scripts/ + the codegen workflow); do not edit by hand.
//!
//! Unknown fields are TOLERATED (serde default): consumers parse live CDN data
//! that can gain fields before their pinned crate version does, and an
//! additive config change must never break a deployed consumer. The strict,
//! reject-unknowns check is the config repo's own ajv CI gate — the place
//! where data and schema always move together.

pub mod generated;
pub mod generated_v2;
pub use generated::*;
pub use generated_v2::WaterxConfigV2;

#[derive(Debug)]
pub enum ConfigError {
    Parse(serde_json::Error),
    NetworkMismatch { expected: String, got: String },
    #[cfg(feature = "fetch")]
    Http(reqwest::Error),
}

impl std::fmt::Display for ConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ConfigError::Parse(e) => write!(f, "config failed schema-derived parsing: {e}"),
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

/// Parse an already-fetched v1 document (unknown fields tolerated).
pub fn parse_waterx_config(json: &str) -> Result<WaterxConfig, ConfigError> {
    serde_json::from_str(json).map_err(ConfigError::Parse)
}

/// Parse an already-fetched v2 document (/v2/<network>.json; unknown fields tolerated).
pub fn parse_waterx_config_v2(json: &str) -> Result<WaterxConfigV2, ConfigError> {
    serde_json::from_str(json).map_err(ConfigError::Parse)
}

/// Fetch + strictly parse one network's config from the CDN.
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
    let got = format!("{:?}", cfg.network).to_lowercase();
    if got != network {
        return Err(ConfigError::NetworkMismatch { expected: network.into(), got });
    }
    Ok(cfg)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> String {
        std::fs::read_to_string(format!("{}/../../{name}.json", env!("CARGO_MANIFEST_DIR"))).unwrap()
    }

    /// v2: both derived instances must parse, and the consolidated shape holds.
    #[test]
    fn both_v2_networks_parse() {
        for net in ["mainnet", "testnet"] {
            let json = std::fs::read_to_string(format!("{}/../../v2/{net}.json", env!("CARGO_MANIFEST_DIR"))).unwrap();
            let cfg = parse_waterx_config_v2(&json).unwrap_or_else(|e| panic!("v2 {net}: {e}"));
            assert_eq!(cfg.schema_version as i64, 2, "schema_version pin");
            assert!(cfg.symbols.len() >= 31, "{net} symbols universe");
            assert!(cfg.oracle_rules.waterx.venue_feeds.contains_key("BTCUSD"));
        }
    }

    /// The schema↔data↔parser triangle: both live instances MUST parse.
    #[test]
    fn both_networks_parse_strictly() {
        for net in ["mainnet", "testnet"] {
            let cfg = parse_waterx_config(&fixture(net)).unwrap_or_else(|e| panic!("{net}: {e}"));
            assert!(cfg.packages.waterx_rule.is_some(), "{net} lost waterx_rule");
        }
    }

    /// Forward-compat: a field this crate version does not know about must be
    /// tolerated — the live CDN document can gain fields before a deployed
    /// consumer upgrades. (Reject-unknowns lives in the repo's ajv CI gate,
    /// where schema and data always move together.)
    #[test]
    fn unknown_field_is_tolerated() {
        let mut doc: serde_json::Value = serde_json::from_str(&fixture("mainnet")).unwrap();
        doc["packages"]["waterx_rule"]["surprise"] = serde_json::json!(1);
        assert!(parse_waterx_config(&doc.to_string()).is_ok());
    }

    #[test]
    fn waterx_rule_feed_shape_is_typed() {
        let cfg = parse_waterx_config(&fixture("mainnet")).unwrap();
        let feeds = &cfg.packages.waterx_rule.as_ref().unwrap().feeds;
        let btc = feeds.get("BTCUSD").expect("BTCUSD feed");
        assert!(!btc.ticker.is_empty());
        assert!(btc.sources.iter().all(|s| s.weight >= 1));
    }
}
