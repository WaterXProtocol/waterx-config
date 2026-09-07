//! Legacy→target lift — the Rust port of the canonical mapping in
//! `packages/ts/src/lift.mjs`. Kept in lockstep by the
//! `lift_matches_node_lift` test, which asserts this implementation's output
//! is byte-equal (as JSON values) to the node lift's output for both networks.
//!
//! Operates on `serde_json::Value` so the mapping reads like the field table
//! it is; the typed [`crate::WaterxConfig`] parse happens after.

use serde_json::{json, Map, Value};

const IDENTITY: [&str; 5] = ["published_at", "original_id", "version", "upgrade_capability", "mvr"];
const FORENSICS: [&str; 4] = ["publish_digest", "publish_checkpoint", "register_digest", "register_checkpoint"];

pub struct Lifted {
    pub doc: Value,
    /// Legacy deploy forensics routed out of the hot path (empty on pruned files).
    pub forensics: Value,
}

#[derive(Debug)]
pub struct LiftError(pub String);
impl std::fmt::Display for LiftError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "lift failed: {}", self.0)
    }
}
impl std::error::Error for LiftError {}

/// Track consumed fields so any legacy field without a target disposition is a
/// hard error — a legacy addition cannot silently miss the flip story.
struct Taker<'a> {
    packages: &'a Map<String, Value>,
    taken: std::collections::HashMap<String, std::collections::HashSet<String>>,
}

impl<'a> Taker<'a> {
    fn take(&mut self, pkg: &str, field: &str) -> Option<Value> {
        let v = self.packages.get(pkg)?.as_object()?.get(field)?.clone();
        self.taken.entry(pkg.to_string()).or_default().insert(field.to_string());
        Some(v)
    }
}

pub fn lift_to_target(legacy: &Value) -> Result<Lifted, LiftError> {
    let root = legacy.as_object().ok_or_else(|| LiftError("document is not an object".into()))?;
    let pkgs = root
        .get("packages")
        .and_then(Value::as_object)
        .ok_or_else(|| LiftError("no packages object".into()))?;
    let mut tk = Taker { packages: pkgs, taken: Default::default() };

    // §2 packages: uniform identity
    let mut packages = Map::new();
    for name in pkgs.keys() {
        let mut entry = Map::new();
        for f in IDENTITY {
            if let Some(v) = tk.take(name, f) {
                if !v.is_null() {
                    entry.insert(f.into(), v);
                }
            }
        }
        for f in FORENSICS {
            tk.take(name, f); // routed to forensics below
        }
        packages.insert(name.clone(), Value::Object(entry));
    }

    // §1 symbols from waterx_rule.feeds (kind moves here); venue_feeds keeps the rest
    let venue_src = tk.take("waterx_rule", "feeds").unwrap_or_else(|| json!({}));
    let mut symbols = Map::new();
    let mut venue_feeds = Map::new();
    if let Some(feeds) = venue_src.as_object() {
        for (sym, feed) in feeds {
            let mut feed = feed.as_object().cloned().unwrap_or_default();
            let kind = feed.remove("kind").unwrap_or_else(|| json!("perp"));
            symbols.insert(sym.clone(), json!({ "kind": kind }));
            venue_feeds.insert(sym.clone(), Value::Object(feed));
        }
    }

    // §4 oracle rules
    let mut oracle_rules = Map::new();
    {
        let mut waterx = Map::new();
        waterx.insert("package".into(), json!("waterx_rule"));
        if let Some(v) = tk.take("waterx_rule", "config") {
            waterx.insert("rule_config_object".into(), v);
        }
        let mut enclave = Map::new();
        for (from, to) in [("enclave", "object"), ("enclave_cap", "cap"), ("enclave_config", "config"), ("enclave_pubkey", "pubkey")] {
            if let Some(v) = tk.take("waterx_rule", from) {
                enclave.insert(to.into(), v);
            }
        }
        waterx.insert("enclave".into(), Value::Object(enclave));
        waterx.insert("venue_feeds".into(), Value::Object(venue_feeds));
        oracle_rules.insert("waterx".into(), Value::Object(waterx));
    }
    if pkgs.contains_key("pyth_rule") {
        let mut r = Map::new();
        r.insert("package".into(), json!("pyth_rule"));
        if let Some(v) = tk.take("pyth_rule", "config") {
            r.insert("pyth_config_object".into(), v);
        }
        r.insert("pyth_price_feeds".into(), tk.take("pyth_rule", "feeds").unwrap_or_else(|| json!({})));
        oracle_rules.insert("pyth".into(), Value::Object(r));
    }
    if pkgs.contains_key("pyth_lazer_rule") {
        let mut r = Map::new();
        r.insert("package".into(), json!("pyth_lazer_rule"));
        if let Some(v) = tk.take("pyth_lazer_rule", "state") {
            r.insert("lazer_state_object".into(), v);
        }
        if let Some(v) = tk.take("pyth_lazer_rule", "config") {
            r.insert("lazer_config_object".into(), v);
        }
        r.insert("lazer_feed_ids".into(), tk.take("pyth_lazer_rule", "feeds").unwrap_or_else(|| json!({})));
        oracle_rules.insert("pyth_lazer".into(), Value::Object(r));
    }
    if pkgs.contains_key("constant_rule") {
        let mut r = Map::new();
        r.insert("package".into(), json!("constant_rule"));
        if let Some(v) = tk.take("constant_rule", "config") {
            r.insert("rule_config_object".into(), v);
        }
        r.insert("constant_prices".into(), tk.take("constant_rule", "feeds").unwrap_or_else(|| json!({})));
        oracle_rules.insert("constant".into(), Value::Object(r));
    }
    if pkgs.contains_key("supra_rule") {
        let mut r = Map::new();
        r.insert("package".into(), json!("supra_rule"));
        if let Some(v) = tk.take("supra_rule", "config") {
            r.insert("rule_config_object".into(), v);
        }
        let feeds = tk.take("supra_rule", "feeds").unwrap_or_else(|| json!({}));
        let mut pair_ids = Map::new();
        if let Some(f) = feeds.as_object() {
            for (sym, v) in f {
                pair_ids.insert(sym.clone(), v.get("pair_id").cloned().unwrap_or(Value::Null));
            }
        }
        r.insert("pair_ids".into(), Value::Object(pair_ids));
        oracle_rules.insert("supra".into(), Value::Object(r));
    }

    // §3 objects by domain — (domain, target key, legacy pkg, legacy field)
    let mut objects: Map<String, Value> = Map::new();
    let mut put = |objects: &mut Map<String, Value>, tk: &mut Taker, domain: &str, key: &str, pkg: &str, field: &str| {
        if let Some(v) = tk.take(pkg, field) {
            objects
                .entry(domain.to_string())
                .or_insert_with(|| Value::Object(Map::new()))
                .as_object_mut()
                .unwrap()
                .insert(key.to_string(), v);
        }
    };
    for (domain, key, pkg, field) in [
        ("oracle", "oracle", "waterx_oracle", "oracle"),
        ("oracle", "listing_cap", "waterx_oracle", "listing_cap"),
        ("oracle", "aggregators", "waterx_oracle", "aggregators"),
        ("perp", "global_config", "waterx_perp", "global_config"),
        ("perp", "admin_cap", "waterx_perp", "admin_cap"),
        ("perp", "market_registry_wlp", "waterx_perp", "market_registry_wlp"),
        ("perp", "markets", "waterx_perp", "markets"),
        ("wlp", "pool", "wlp", "wlp_pool"),
        ("wlp", "aum", "wlp", "wlp_aum"),
        ("wlp", "currency_type", "wlp", "currency"),
        ("wlp", "metadata_cap", "wlp", "metadata_cap"),
        ("wlp", "pool_tokens", "wlp", "pool_tokens"),
        ("staking", "admin_cap", "waterx_staking", "admin_cap"),
        ("staking", "pools", "waterx_staking", "pools"),
        ("staking", "rewarders", "waterx_staking", "rewarders"),
        ("account", "registry", "waterx_account", "account_registry"),
        ("account", "admin_cap", "waterx_account", "admin_cap"),
        ("referral", "table", "waterx_referral", "referral_table"),
        ("credit", "registry", "waterx_credit", "credit_registry"),
        ("credit", "credit_type", "waterx_credit", "credit_type"),
        ("custody", "vault", "native_custody", "vault"),
        ("bridge", "state", "wormhole_bridge", "bridge"),
        ("bridge", "emitter_cap", "wormhole_bridge", "emitter_cap"),
        ("bridge", "wormhole_state", "wormhole_bridge", "wormhole_state"),
        ("withdrawal_queue", "queue", "withdrawal_queue", "queue"),
        ("withdrawal_queue", "executors", "withdrawal_queue", "executors"),
        ("prediction", "global_config", "waterx_prediction", "global_config"),
        ("prediction", "admin_cap", "waterx_prediction", "admin_cap"),
        ("prediction", "market_registries", "waterx_prediction", "market_registries"),
        ("prediction", "settlement_coin_types", "waterx_prediction", "settlement_coin_types"),
        ("prediction", "claimable_link_config", "waterx_prediction_gift", "claimable_link_config"),
        ("prediction", "gift_admin_cap", "waterx_prediction_gift", "admin_cap"),
        ("usd", "metadata_cap", "usd", "metadata_cap"),
        ("faucet", "faucet", "testnet_faucet", "faucet"),
        ("faucet", "whitelist", "testnet_faucet", "whitelist"),
        ("mock_usdsui", "currency_type", "mock_usdsui", "currency"),
        ("mock_usdsui", "metadata_cap", "mock_usdsui", "metadata_cap"),
        ("mock_usdsui", "treasury_cap", "mock_usdsui", "treasury_cap"),
    ] {
        put(&mut objects, &mut tk, domain, key, pkg, field);
    }
    // custody assets: strip _comment (audit P5)
    if let Some(assets) = tk.take("native_custody", "assets") {
        let cleaned: Vec<Value> = assets
            .as_array()
            .map(|a| {
                a.iter()
                    .map(|x| {
                        let mut o = x.as_object().cloned().unwrap_or_default();
                        o.remove("_comment");
                        Value::Object(o)
                    })
                    .collect()
            })
            .unwrap_or_default();
        objects
            .entry("custody".to_string())
            .or_insert_with(|| Value::Object(Map::new()))
            .as_object_mut()
            .unwrap()
            .insert("assets".into(), Value::Array(cleaned));
    }
    // bridge limits block
    {
        let mut limits = Map::new();
        for (from, to) in [
            ("max_mint_per_tx", "max_mint_per_tx"),
            ("max_burn_per_tx", "max_burn_per_tx"),
            ("daily_mint_limit", "daily_mint"),
            ("daily_burn_limit", "daily_burn"),
            ("personal_burn_cap", "personal_burn"),
        ] {
            if let Some(v) = tk.take("wormhole_bridge", from) {
                limits.insert(to.into(), v);
            }
        }
        if !limits.is_empty() {
            objects
                .entry("bridge".to_string())
                .or_insert_with(|| Value::Object(Map::new()))
                .as_object_mut()
                .unwrap()
                .insert("limits".into(), Value::Object(limits));
        }
    }

    // leftover detection
    let mut leftovers = Vec::new();
    for (name, body) in pkgs {
        if let Some(o) = body.as_object() {
            for f in o.keys() {
                if !tk.taken.get(name).is_some_and(|s| s.contains(f)) {
                    leftovers.push(format!("{name}.{f}"));
                }
            }
        }
    }
    if !leftovers.is_empty() {
        return Err(LiftError(format!("legacy fields with no flip disposition (extend lift.rs AND lift.mjs): {}", leftovers.join(", "))));
    }

    let mut doc = Map::new();
    doc.insert("schema_version".into(), json!(2));
    doc.insert("network".into(), root.get("network").cloned().unwrap_or(Value::Null));
    doc.insert("chain_id".into(), root.get("chain_id").cloned().unwrap_or(Value::Null));
    doc.insert("symbols".into(), Value::Object(symbols));
    doc.insert("packages".into(), Value::Object(packages));
    doc.insert("objects".into(), Value::Object(objects));
    doc.insert("oracle_rules".into(), Value::Object(oracle_rules));
    if let Some(v) = root.get("coin_registry") {
        doc.insert("coin_registry".into(), v.clone());
    }
    if let Some(v) = root.get("evm") {
        doc.insert("evm".into(), v.clone());
    }

    let forensics = json!({
        "network": root.get("network").cloned().unwrap_or(Value::Null),
        "deploy_tx_log": root.get("deploy_tx_log").cloned().unwrap_or_else(|| json!([])),
        "package_publish": pkgs.iter().filter_map(|(name, body)| {
            let o = body.as_object()?;
            let m: Map<String, Value> = FORENSICS.iter()
                .filter_map(|f| o.get(*f).map(|v| (f.to_string(), v.clone())))
                .collect();
            (!m.is_empty()).then(|| (name.clone(), Value::Object(m)))
        }).collect::<Map<_, _>>(),
    });

    Ok(Lifted { doc: Value::Object(doc), forensics })
}
