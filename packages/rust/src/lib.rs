//! waterx-config — the official typed reader for WaterX network files.
//!
//! Types in [`generated`] are produced from `schema/waterx-config.schema.json`
//! by quicktype (see scripts/ + the codegen workflow); do not edit by hand.
//! Every struct is `deny_unknown_fields`, so a field added to the JSON without
//! a schema change fails parsing here — that is the point.
//!
//! Pattern-level constraints (object-id hex shape etc.) are enforced by the
//! repo's ajv gate on every PR; this crate enforces structure and types.

pub mod generated;
pub use generated::*;

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

/// Strictly parse an already-fetched document.
pub fn parse_waterx_config(json: &str) -> Result<WaterxConfig, ConfigError> {
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

    /// The schema↔data↔parser triangle: both live instances MUST parse.
    #[test]
    fn both_networks_parse_strictly() {
        for net in ["mainnet", "testnet"] {
            let cfg = parse_waterx_config(&fixture(net)).unwrap_or_else(|e| panic!("{net}: {e}"));
            assert!(cfg.packages.waterx_rule.is_some(), "{net} lost waterx_rule");
        }
    }

    /// A field the schema does not know about must fail parsing — otherwise
    /// config drift silently reappears, which is the disease this repo has.
    #[test]
    fn unknown_field_is_rejected() {
        let mut doc: serde_json::Value = serde_json::from_str(&fixture("mainnet")).unwrap();
        doc["packages"]["waterx_rule"]["surprise"] = serde_json::json!(1);
        assert!(parse_waterx_config(&doc.to_string()).is_err());
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
