// Example code that deserializes and serializes the model.
// extern crate serde;
// #[macro_use]
// extern crate serde_derive;
// extern crate serde_json;
//
// use generated_module::WaterxConfig;
//
// fn main() {
//     let json = r#"{"answer": 42}"#;
//     let model: WaterxConfig = serde_json::from_str(&json).unwrap();
// }

use serde::{Serialize, Deserialize};
use std::collections::HashMap;

/// One WaterX network deployment in the consolidated shape: one symbol universe, uniform
/// package identity, domain-grouped shared objects, and a named per-rule oracle registry.
/// See docs/FIELDS.md.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WaterxConfig {
    pub chain_id: String,

    /// 0x-prefixed hex id/address (Sui short-form or EVM).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub coin_registry: Option<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub evm: Option<Evm>,

    pub network: Network,

    pub objects: Objects,

    pub oracle_rules: OracleRules,

    pub packages: HashMap<String, Package>,

    /// Format discriminator. This repo serves only version 2 (the consolidated shape); parsers
    /// reject anything else.
    pub schema_version: i64,

    /// The single symbol universe: the ONLY place a symbol is introduced. Every symbol-keyed map
    /// elsewhere must reference a key from here (CI-enforced).
    pub symbols: HashMap<String, Symbol>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Evm {
    pub bridge: EvmBridge,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvmBridge {
    pub chains: HashMap<String, Chain>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Chain {
    pub block_explorer: String,

    pub chain_id: i64,

    /// Deposit vault contract address on this EVM chain (20-byte, 0x + 40 hex).
    pub deposit_vault: String,

    pub tokens: HashMap<String, String>,

    pub wormhole_chain_id: i64,

    /// Wormhole core contract address on this EVM chain (20-byte, 0x + 40 hex).
    pub wormhole_core: String,

    /// 0x-prefixed hex id/address (Sui short-form or EVM).
    pub wormhole_executor: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Network {
    Mainnet,

    Testnet,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Objects {
    pub account: Account,

    pub bridge: ObjectsBridge,

    pub credit: Credit,

    pub custody: Custody,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub faucet: Option<Faucet>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub mock_usdsui: Option<MockUsdsui>,

    pub oracle: Oracle,

    pub perp: Perp,

    pub prediction: Prediction,

    pub referral: Referral,

    pub staking: Staking,

    pub usd: Usd,

    pub withdrawal_queue: WithdrawalQueue,

    pub wlp: Wlp,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Account {
    /// Admin capability object id.
    pub admin_cap: String,

    pub registry: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObjectsBridge {
    pub emitter_cap: String,

    pub limits: Limits,

    pub state: String,

    pub wormhole_state: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Limits {
    pub daily_burn: String,

    pub daily_mint: String,

    pub max_burn_per_tx: String,

    pub max_mint_per_tx: String,

    pub personal_burn: PersonalBurn,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersonalBurn {
    pub cap_amount: String,

    pub window_ms: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Credit {
    pub credit_type: String,

    pub registry: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Custody {
    /// Native-custody asset rows. mint_fee_scaled / burn_fee_scaled are u128 1e9-scaled (0 = no
    /// fee; 1_000_000 = 0.1%; 1_000_000_000 = 100%). min_burn_amount is the dust floor in the
    /// asset's smallest unit.
    pub assets: Vec<Asset>,

    pub vault: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Asset {
    pub burn_fee_scaled: String,

    pub decimal: i64,

    pub min_burn_amount: String,

    pub mint_fee_scaled: String,

    pub name: String,

    #[serde(rename = "type")]
    pub asset_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Faucet {
    pub faucet: String,

    pub whitelist: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MockUsdsui {
    pub currency_type: String,

    pub metadata_cap: String,

    pub treasury_cap: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Oracle {
    /// Per-symbol on-chain Aggregator object id — the cross-rule weighted-median aggregation
    /// point.
    pub aggregators: HashMap<String, String>,

    pub listing_cap: String,

    pub oracle: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Perp {
    /// Admin capability object id.
    pub admin_cap: String,

    pub global_config: String,

    pub market_registry_wlp: String,

    /// Per-symbol perp market: market + config object ids.
    pub markets: HashMap<String, Market>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Market {
    pub config: String,

    pub market: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Prediction {
    /// Admin capability object id.
    pub admin_cap: String,

    pub claimable_link_config: String,

    pub gift_admin_cap: String,

    pub global_config: String,

    pub market_registries: HashMap<String, String>,

    pub settlement_coin_types: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Referral {
    pub table: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Staking {
    /// Admin capability object id.
    pub admin_cap: String,

    pub pools: HashMap<String, String>,

    pub rewarders: HashMap<String, HashMap<String, Rewarder>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Rewarder {
    pub coin_type: String,

    pub decimals: i64,

    pub rewarder_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Usd {
    pub metadata_cap: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WithdrawalQueue {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub executors: Option<Vec<String>>,

    pub queue: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Wlp {
    pub aum: String,

    pub currency_type: String,

    pub metadata_cap: String,

    pub pool: String,

    pub pool_tokens: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OracleRules {
    pub constant: Constant,

    pub pyth: Pyth,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub pyth_lazer: Option<PythLazer>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub supra: Option<Supra>,

    pub waterx: Waterx,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Constant {
    /// Per-symbol constant price, 1e9-scaled decimal string (e.g. "1000000000" = 1.0).
    pub constant_prices: HashMap<String, ConstantPrice>,

    pub package: String,

    pub rule_config_object: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConstantPrice {
    pub price: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Pyth {
    pub package: String,

    pub pyth_config_object: String,

    /// Per-symbol Pyth price feed: feed_id (Pyth) + price_info_object (Sui object the keeper
    /// refreshes).
    pub pyth_price_feeds: HashMap<String, PythPriceFeed>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PythPriceFeed {
    /// Pyth price-feed identifier (32-byte hex). NOT a Sui object id.
    pub feed_id: String,

    /// The shared PriceInfoObject itself — NOT the Field<PriceIdentifier, ID> wrapper object;
    /// passing the wrapper is the classic mistake.
    pub price_info_object: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PythLazer {
    pub lazer_config_object: String,

    /// Per-symbol Pyth Lazer numeric feed id, as used by the keeper's Lazer WS subscription.
    pub lazer_feed_ids: HashMap<String, i64>,

    pub lazer_state_object: String,

    pub package: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Supra {
    pub package: String,

    pub pair_ids: HashMap<String, i64>,

    pub rule_config_object: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Waterx {
    /// The ONE home for enclave identity (object, cap, config, pubkey).
    pub enclave: Enclave,

    pub package: String,

    pub rule_config_object: String,

    /// QC feed registry, keyed by oracle symbol. The `weights` inside are OFF-CHAIN ONLY:
    /// waterx_rule on-chain validates sources/ticker/method/min_sources but has no notion of
    /// weights, so a weight change moves the signed price via a parameter no on-chain check can
    /// see (waterx-quote-center audit-scope I-16). Review weight changes as a trust-surface
    /// change.
    pub venue_feeds: HashMap<String, VenueFeed>,
}

/// The ONE home for enclave identity (object, cap, config, pubkey).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Enclave {
    pub cap: String,

    pub config: String,

    pub object: String,

    /// Registered enclave ed25519 pubkey (hex, no 0x). The SOLE config home; k8s-infra pins an
    /// independent env copy by design (boot-without-enclave).
    pub pubkey: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VenueFeed {
    pub method: String,

    pub min_sources: i64,

    /// Venue set feeding the aggregate. Source names are a wire vocabulary shared with
    /// waterx_rule.move's on-chain u64 registry and quote-service resolve.rs (1 binance_spot_ws
    /// / binance_spot [REST], 2 binance_usdm_perp_ws, 3 bybit_linear_perp_ws, 4
    /// gateio_usdt_perp_ws, 5 bybit_spot_ws, 6 xstock_equity_rest, 7 okx_spot_ws, 8
    /// hyperliquid_perp_ws, 9 gateio_spot_ws, 10 kraken_spot_ws, 11 pyth_lazer_ws). A source id
    /// must be REGISTERED ON-CHAIN for the target network before a feed lists it — an
    /// unregistered id aborts on-chain validation at feed time (per-network registration is
    /// tracked in WL-1968).
    pub sources: Vec<Source>,

    pub ticker: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Source {
    pub name: String,

    pub weight: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Package {
    /// Move Registry (MVR) registration for this package. Mainnet only today.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mvr: Option<Mvr>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub upgrade_capability: Option<String>,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

/// Move Registry (MVR) registration for this package. Mainnet only today.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Mvr {
    pub app_cap_id: String,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub git: Option<Git>,

    pub name: String,

    pub package_info_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Git {
    pub path: String,

    pub repo: String,

    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Symbol {
    pub kind: Kind,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    Commodity,

    Fx,

    Perp,

    Prediction,

    Spot,

    Xstock,
}
