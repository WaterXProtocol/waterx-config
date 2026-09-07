// Example code that deserializes and serializes the model.
// extern crate serde;
// #[macro_use]
// extern crate serde_derive;
// extern crate serde_json;
//
// use generated_module::generated;
//
// fn main() {
//     let json = r#"{"answer": 42}"#;
//     let model: generated = serde_json::from_str(&json).unwrap();
// }

use serde::{Serialize, Deserialize};
use std::collections::HashMap;

/// One WaterX network deployment: package ids, shared objects, and the oracle feed registry.
/// WaterxConfig from the 2026-09-07 audit describing the CURRENT instances; fields present on
/// only one network carry a $comment and are optional. See docs/FIELDS.md for the rendered
/// reference.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxConfig {
    pub chain_id: String,

    /// Short-form Sui address/object id.
    pub coin_registry: Option<String>,

    pub deploy_tx_log: Option<Vec<DeployTxLog>>,

    pub evm: Option<Evm>,

    pub network: Network,

    pub packages: Packages,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DeployTxLog {
    pub action: String,

    pub checkpoint: String,

    pub digest: String,

    pub phase: String,

    pub timestamp: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Evm {
    pub bridge: Bridge,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Bridge {
    pub chains: HashMap<String, Chain>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Chain {
    pub block_explorer: String,

    pub chain_id: i64,

    /// Short-form Sui address/object id.
    pub deposit_vault: String,

    pub tokens: HashMap<String, String>,

    pub wormhole_chain_id: i64,

    /// Short-form Sui address/object id.
    pub wormhole_core: String,

    /// Short-form Sui address/object id.
    pub wormhole_executor: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Network {
    Mainnet,

    Testnet,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Packages {
    pub bucket_framework: Option<BucketFramework>,

    pub constant_rule: Option<ConstantRule>,

    pub enclave: Option<Enclave>,

    pub mock_sui: Option<MockSui>,

    pub mock_usdc: Option<MockUsdc>,

    pub mock_usdsui: Option<MockUsdsui>,

    pub native_custody: Option<NativeCustody>,

    pub pyth_lazer_rule: Option<PythLazerRule>,

    pub pyth_rule: Option<PythRule>,

    pub supra_rule: Option<SupraRule>,

    pub testnet_faucet: Option<TestnetFaucet>,

    pub usd: Option<Usd>,

    pub waterx_account: Option<WaterxAccount>,

    pub waterx_credit: Option<WaterxCredit>,

    pub waterx_oracle: Option<WaterxOracle>,

    pub waterx_perp: Option<WaterxPerp>,

    pub waterx_perp_view: Option<WaterxPerpView>,

    pub waterx_prediction: Option<WaterxPrediction>,

    pub waterx_prediction_gift: Option<WaterxPredictionGift>,

    pub waterx_referral: Option<WaterxReferral>,

    pub waterx_rule: Option<WaterxRule>,

    pub waterx_staking: Option<WaterxStaking>,

    pub withdrawal_queue: Option<WithdrawalQueue>,

    pub wlp: Option<Wlp>,

    pub wormhole_bridge: Option<WormholeBridge>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BucketFramework {
    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: Option<String>,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ConstantRule {
    pub config: String,

    /// Per-symbol constant price, 1e9-scaled decimal string (e.g. "1000000000" = 1.0).
    pub feeds: Feeds,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

/// Per-symbol constant price, 1e9-scaled decimal string (e.g. "1000000000" = 1.0).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub struct Feeds {
    pub usdcusd: Usdcusd,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Usdcusd {
    pub price: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Enclave {
    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub publish_checkpoint: String,

    pub publish_digest: String,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MockSui {
    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: Option<String>,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: Option<String>,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: Option<String>,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MockUsdc {
    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: Option<String>,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: Option<String>,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MockUsdsui {
    pub currency: Option<String>,

    pub metadata_cap: Option<String>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: Option<String>,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: Option<String>,

    pub treasury_cap: Option<String>,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: Option<String>,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct NativeCustody {
    pub assets: Vec<Asset>,

    /// Move Registry (MVR) registration for this package. Mainnet only today.
    pub mvr: Option<NativeCustodyMvr>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    pub vault: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Asset {
    /// Inline comment carried in DATA (audit P5). Migrates into schema descriptions in the
    /// Phase-2 cleanup; do not add new ones.
    #[serde(rename = "_comment")]
    pub comment: Option<String>,

    pub burn_fee_scaled: String,

    pub decimal: i64,

    pub min_burn_amount: String,

    pub mint_fee_scaled: String,

    pub name: String,

    #[serde(rename = "type")]
    pub asset_type: String,
}

/// Move Registry (MVR) registration for this package. Mainnet only today.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct NativeCustodyMvr {
    pub app_cap_id: String,

    pub git: PurpleGit,

    pub name: String,

    pub package_info_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PurpleGit {
    pub path: String,

    pub repo: String,

    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PythLazerRule {
    pub config: Option<String>,

    /// Per-symbol Pyth Lazer numeric feed id, as used by the keeper's Lazer WS subscription.
    pub feeds: Option<HashMap<String, i64>>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: Option<String>,

    pub state: Option<String>,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: Option<String>,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PythRule {
    pub config: String,

    /// Per-symbol Pyth price feed: feed_id (Pyth) + price_info_object (Sui object the keeper
    /// refreshes).
    pub feeds: HashMap<String, PythRuleFeed>,

    /// Move Registry (MVR) registration for this package. Mainnet only today.
    pub mvr: Option<PythRuleMvr>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PythRuleFeed {
    pub feed_id: String,

    pub price_info_object: String,
}

/// Move Registry (MVR) registration for this package. Mainnet only today.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PythRuleMvr {
    pub app_cap_id: String,

    pub git: FluffyGit,

    pub name: String,

    pub package_info_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FluffyGit {
    pub path: String,

    pub repo: String,

    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SupraRule {
    pub config: Option<String>,

    pub feeds: Option<HashMap<String, SupraRuleFeed>>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: Option<String>,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: Option<String>,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: Option<String>,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SupraRuleFeed {
    pub pair_id: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TestnetFaucet {
    pub faucet: Option<String>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: Option<String>,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: Option<String>,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: Option<String>,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: Option<i64>,

    pub whitelist: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Usd {
    pub metadata_cap: String,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxAccount {
    pub account_registry: String,

    /// Admin capability object id.
    pub admin_cap: String,

    /// Move Registry (MVR) registration for this package. Mainnet only today.
    pub mvr: Option<WaterxAccountMvr>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

/// Move Registry (MVR) registration for this package. Mainnet only today.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxAccountMvr {
    pub app_cap_id: String,

    pub git: TentacledGit,

    pub name: String,

    pub package_info_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TentacledGit {
    pub path: String,

    pub repo: String,

    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxCredit {
    pub credit_registry: String,

    pub credit_type: String,

    /// Move Registry (MVR) registration for this package. Mainnet only today.
    pub mvr: Option<WaterxCreditMvr>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

/// Move Registry (MVR) registration for this package. Mainnet only today.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxCreditMvr {
    pub app_cap_id: String,

    pub git: StickyGit,

    pub name: String,

    pub package_info_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StickyGit {
    pub path: String,

    pub repo: String,

    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxOracle {
    /// Per-symbol on-chain Aggregator object id — the cross-rule weighted-median aggregation
    /// point.
    pub aggregators: HashMap<String, String>,

    pub listing_cap: String,

    /// Move Registry (MVR) registration for this package. Mainnet only today.
    pub mvr: Option<WaterxOracleMvr>,

    pub oracle: String,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub publish_checkpoint: String,

    pub publish_digest: String,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

/// Move Registry (MVR) registration for this package. Mainnet only today.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxOracleMvr {
    pub app_cap_id: String,

    pub git: IndigoGit,

    pub name: String,

    pub package_info_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct IndigoGit {
    pub path: String,

    pub repo: String,

    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxPerp {
    /// Admin capability object id.
    pub admin_cap: String,

    pub global_config: String,

    pub market_registry_wlp: String,

    /// Per-symbol perp market: market + config object ids.
    pub markets: HashMap<String, Market>,

    /// Move Registry (MVR) registration for this package. Mainnet only today.
    pub mvr: Option<WaterxPerpMvr>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Market {
    pub config: String,

    pub market: String,
}

/// Move Registry (MVR) registration for this package. Mainnet only today.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxPerpMvr {
    pub app_cap_id: String,

    pub git: IndecentGit,

    pub name: String,

    pub package_info_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct IndecentGit {
    pub path: String,

    pub repo: String,

    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxPerpView {
    /// Move Registry (MVR) registration for this package. Mainnet only today.
    pub mvr: Option<WaterxPerpViewMvr>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

/// Move Registry (MVR) registration for this package. Mainnet only today.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxPerpViewMvr {
    pub app_cap_id: String,

    pub git: HilariousGit,

    pub name: String,

    pub package_info_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HilariousGit {
    pub path: String,

    pub repo: String,

    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxPrediction {
    /// Admin capability object id.
    pub admin_cap: String,

    pub global_config: String,

    pub market_registries: MarketRegistries,

    /// Move Registry (MVR) registration for this package. Mainnet only today.
    pub mvr: Option<WaterxPredictionMvr>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    pub settlement_coin_types: SettlementCoinTypes,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub struct MarketRegistries {
    pub usd: String,
}

/// Move Registry (MVR) registration for this package. Mainnet only today.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxPredictionMvr {
    pub app_cap_id: String,

    pub git: AmbitiousGit,

    pub name: String,

    pub package_info_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AmbitiousGit {
    pub path: String,

    pub repo: String,

    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub struct SettlementCoinTypes {
    pub usd: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxPredictionGift {
    /// Admin capability object id.
    pub admin_cap: String,

    pub claimable_link_config: String,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub publish_checkpoint: String,

    pub publish_digest: String,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxReferral {
    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    pub referral_table: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: Option<String>,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxRule {
    pub config: String,

    pub enabled: Option<bool>,

    pub enclave: String,

    pub enclave_cap: String,

    pub enclave_config: String,

    /// Registered enclave ed25519 pubkey (hex, no 0x). Duplicated in
    /// packages.enclave.enclave_pubkey — keep both in sync until R4 deduplicates.
    pub enclave_pubkey: String,

    /// QC feed registry, keyed by oracle symbol. The `weights` inside are OFF-CHAIN ONLY:
    /// waterx_rule on-chain validates sources/ticker/method/min_sources but has no notion of
    /// weights, so a weight change moves the signed price via a parameter no on-chain check can
    /// see (waterx-quote-center audit-scope I-16). Review weight changes as a trust-surface
    /// change.
    pub feeds: HashMap<String, WaterxRuleFeed>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub publish_checkpoint: String,

    pub publish_digest: String,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    pub register_checkpoint: Option<String>,

    pub register_digest: Option<String>,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxRuleFeed {
    pub kind: String,

    pub method: String,

    pub min_sources: i64,

    pub sources: Vec<Source>,

    pub ticker: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Source {
    pub name: String,

    pub weight: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxStaking {
    /// Admin capability object id.
    pub admin_cap: String,

    /// Move Registry (MVR) registration for this package. Mainnet only today.
    pub mvr: Option<WaterxStakingMvr>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub pools: Pools,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    pub rewarders: Rewarders,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

/// Move Registry (MVR) registration for this package. Mainnet only today.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WaterxStakingMvr {
    pub app_cap_id: String,

    pub git: CunningGit,

    pub name: String,

    pub package_info_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CunningGit {
    pub path: String,

    pub repo: String,

    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub struct Pools {
    pub wlp: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub struct Rewarders {
    pub wlp: HashMap<String, MockDeep>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MockDeep {
    pub coin_type: String,

    pub decimals: i64,

    pub rewarder_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WithdrawalQueue {
    pub executors: Option<Vec<String>>,

    /// Move Registry (MVR) registration for this package. Mainnet only today.
    pub mvr: Option<WithdrawalQueueMvr>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    pub queue: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,
}

/// Move Registry (MVR) registration for this package. Mainnet only today.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WithdrawalQueueMvr {
    pub app_cap_id: String,

    pub git: MagentaGit,

    pub name: String,

    pub package_info_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MagentaGit {
    pub path: String,

    pub repo: String,

    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Wlp {
    pub currency: String,

    pub metadata_cap: String,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub pool_tokens: PoolTokens,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,

    pub wlp_aum: String,

    pub wlp_pool: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub struct PoolTokens {
    pub usdcusd: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WormholeBridge {
    pub bridge: String,

    pub daily_burn_limit: String,

    pub daily_mint_limit: String,

    pub emitter_cap: String,

    pub max_burn_per_tx: String,

    pub max_mint_per_tx: String,

    /// Move Registry (MVR) registration for this package. Mainnet only today.
    pub mvr: Option<WormholeBridgeMvr>,

    /// Package id of the FIRST publish. Never changes across upgrades; used to build type tags
    /// (<original_id>::module::Type).
    pub original_id: String,

    pub personal_burn_cap: PersonalBurnCap,

    pub publish_checkpoint: Option<String>,

    pub publish_digest: Option<String>,

    /// Package id of the current latest version — the tx-call target. Changes on every upgrade.
    pub published_at: String,

    /// UpgradeCap object id. Deploy-time artifact; no runtime consumer.
    pub upgrade_capability: String,

    /// On-chain package version: 1 at first publish, +1 per upgrade.
    pub version: i64,

    pub wormhole_state: String,
}

/// Move Registry (MVR) registration for this package. Mainnet only today.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct WormholeBridgeMvr {
    pub app_cap_id: String,

    pub git: FriskyGit,

    pub name: String,

    pub package_info_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FriskyGit {
    pub path: String,

    pub repo: String,

    pub version: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PersonalBurnCap {
    pub cap_amount: String,

    pub window_ms: String,
}
