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

/// The consolidated post-flip shape (docs/FLIP-PLAN.md): one symbol universe, uniform
/// package identity, domain-grouped shared objects, and a named per-rule oracle registry.
/// Until flip day this validates the LIFTED form of the served files; on flip day it becomes
/// the schema of mainnet.json/testnet.json themselves.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WaterxConfig {
    pub chain_id: String,

    /// Short-form Sui address/object id.
    pub coin_registry: Option<String>,

    pub evm: Option<Evm>,

    pub network: Network,

    pub objects: Objects,

    pub oracle_rules: OracleRules,

    pub packages: HashMap<String, Package>,

    pub schema_version: f64,

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

    /// Short-form Sui address/object id.
    pub deposit_vault: String,

    pub tokens: Tokens,

    pub wormhole_chain_id: i64,

    /// Short-form Sui address/object id.
    pub wormhole_core: String,

    /// Short-form Sui address/object id.
    pub wormhole_executor: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub struct Tokens {
    /// Short-form Sui address/object id.
    #[serde(rename = "tUSDC")]
    pub t_usdc: Option<String>,

    /// Short-form Sui address/object id.
    #[serde(rename = "tUSDT")]
    pub t_usdt: Option<String>,

    /// Short-form Sui address/object id.
    pub usdc: Option<String>,

    /// Short-form Sui address/object id.
    pub usdt: Option<String>,
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

    pub faucet: Option<Faucet>,

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
    pub aggregators: HashMap<String, String>,

    pub listing_cap: String,

    pub oracle: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Perp {
    pub admin_cap: String,

    pub global_config: String,

    pub market_registry_wlp: String,

    pub markets: HashMap<String, Market>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Market {
    pub config: String,

    pub market: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Prediction {
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
    pub admin_cap: String,

    pub pools: HashMap<String, String>,

    pub rewarders: HashMap<String, Rewarder>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub struct Rewarder {
    pub deep: Option<Deep>,

    pub mock_deep: Option<MockDeep>,

    pub usdc: Option<Usdc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Deep {
    pub coin_type: String,

    pub decimals: i64,

    pub rewarder_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MockDeep {
    pub coin_type: String,

    pub decimals: i64,

    pub rewarder_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Usdc {
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

    pub pyth_lazer: Option<PythLazer>,

    pub supra: Option<Supra>,

    pub waterx: Waterx,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Constant {
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

    pub pyth_price_feeds: HashMap<String, PythPriceFeed>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PythPriceFeed {
    pub feed_id: String,

    pub price_info_object: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PythLazer {
    pub lazer_config_object: String,

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

    /// QC feed registry (was packages.waterx_rule.feeds). `weights` remain OFF-CHAIN ONLY —
    /// audit-scope I-16 trust surface.
    pub venue_feeds: HashMap<String, VenueFeed>,
}

/// The ONE home for enclave identity (object, cap, config, pubkey).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Enclave {
    pub cap: String,

    pub config: String,

    pub object: String,

    pub pubkey: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VenueFeed {
    pub method: String,

    pub min_sources: i64,

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
    pub mvr: Option<Mvr>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: Option<String>,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: Option<String>,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: Option<i64>,
}

/// Move Registry (MVR) registration for this package. Mainnet only today.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Mvr {
    pub app_cap_id: String,

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
