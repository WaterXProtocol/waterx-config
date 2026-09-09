import { z } from "zod";

export default z
  .object({
    schema_version: z
      .literal(2)
      .describe(
        "Format discriminator. This repo serves only version 2 (the consolidated shape); parsers reject anything else.",
      ),
    network: z.enum(["mainnet", "testnet"]),
    chain_id: z.string().min(4),
    symbols: z
      .record(
        z.object({
          kind: z.enum([
            "perp",
            "spot",
            "xstock",
            "commodity",
            "fx",
            "prediction",
          ]),
        }),
      )
      .describe(
        "The single symbol universe: the ONLY place a symbol is introduced. Every symbol-keyed map elsewhere must reference a key from here (CI-enforced).",
      ),
    packages: z.record(
      z.object({
        published_at: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe(
            "Package id of the current latest version — the tx-call target. Changes on every upgrade.",
          ),
        original_id: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe(
            "Package id of the FIRST publish. Never changes across upgrades; used to build type tags (<original_id>::module::Type).",
          ),
        version: z
          .number()
          .int()
          .gte(1)
          .describe(
            "On-chain package version: 1 at first publish, +1 per upgrade.",
          ),
        upgrade_capability: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe(
            "UpgradeCap object id. Deploy-time artifact; no runtime consumer.",
          )
          .optional(),
        mvr: z
          .object({
            name: z.string(),
            package_info_id: z
              .string()
              .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
              .describe("32-byte Sui object/package id."),
            app_cap_id: z
              .string()
              .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
              .describe("32-byte Sui object/package id."),
            git: z
              .object({
                repo: z.string(),
                path: z.string(),
                version: z.number().int(),
              })
              .optional(),
          })
          .describe(
            "Move Registry (MVR) registration for this package. Mainnet only today.",
          )
          .optional(),
      }),
    ),
    objects: z.object({
      oracle: z.object({
        oracle: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        listing_cap: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        aggregators: z
          .record(
            z
              .string()
              .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
              .describe("32-byte Sui object/package id."),
          )
          .describe(
            "Per-symbol on-chain Aggregator object id — the cross-rule weighted-median aggregation point.",
          ),
      }),
      perp: z.object({
        global_config: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        admin_cap: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("Admin capability object id."),
        market_registry_wlp: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        markets: z
          .record(
            z.object({
              market: z
                .string()
                .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
                .describe("32-byte Sui object/package id."),
              config: z
                .string()
                .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
                .describe("32-byte Sui object/package id."),
            }),
          )
          .describe("Per-symbol perp market: market + config object ids."),
      }),
      wlp: z.object({
        pool: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        aum: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        currency_type: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        metadata_cap: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        pool_tokens: z.record(
          z
            .string()
            .regex(
              new RegExp(
                "^0x[0-9a-fA-F]{1,64}::[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*$",
              ),
            )
            .describe("Fully-qualified Move type tag."),
        ),
      }),
      staking: z.object({
        admin_cap: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("Admin capability object id."),
        pools: z.record(
          z
            .string()
            .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
            .describe("32-byte Sui object/package id."),
        ),
        rewarders: z.record(
          z.record(
            z.object({
              rewarder_id: z
                .string()
                .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
                .describe("32-byte Sui object/package id."),
              coin_type: z
                .string()
                .regex(
                  new RegExp(
                    "^0x[0-9a-fA-F]{1,64}::[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*$",
                  ),
                )
                .describe("Fully-qualified Move type tag."),
              decimals: z.number().int(),
            }),
          ),
        ),
      }),
      account: z.object({
        registry: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        admin_cap: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("Admin capability object id."),
      }),
      referral: z.object({
        table: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
      }),
      credit: z.object({
        registry: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        credit_type: z
          .string()
          .regex(
            new RegExp(
              "^0x[0-9a-fA-F]{1,64}::[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*$",
            ),
          )
          .describe("Fully-qualified Move type tag."),
      }),
      custody: z.object({
        vault: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        assets: z
          .array(
            z.object({
              name: z.string(),
              type: z
                .string()
                .regex(
                  new RegExp(
                    "^0x[0-9a-fA-F]{1,64}::[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*$",
                  ),
                )
                .describe("Fully-qualified Move type tag."),
              decimal: z.number().int(),
              mint_fee_scaled: z
                .string()
                .regex(new RegExp("^[0-9]+$"))
                .describe(
                  "Unsigned integer as a decimal string — used where values may exceed 2^53 (u64/u128 amounts, 1e9-scaled prices).",
                ),
              burn_fee_scaled: z
                .string()
                .regex(new RegExp("^[0-9]+$"))
                .describe(
                  "Unsigned integer as a decimal string — used where values may exceed 2^53 (u64/u128 amounts, 1e9-scaled prices).",
                ),
              min_burn_amount: z
                .string()
                .regex(new RegExp("^[0-9]+$"))
                .describe(
                  "Unsigned integer as a decimal string — used where values may exceed 2^53 (u64/u128 amounts, 1e9-scaled prices).",
                ),
            }),
          )
          .describe(
            "Native-custody asset rows. mint_fee_scaled / burn_fee_scaled are u128 1e9-scaled (0 = no fee; 1_000_000 = 0.1%; 1_000_000_000 = 100%). min_burn_amount is the dust floor in the asset's smallest unit.",
          ),
      }),
      bridge: z.object({
        state: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        emitter_cap: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        wormhole_state: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        limits: z.object({
          max_mint_per_tx: z
            .string()
            .regex(new RegExp("^[0-9]+$"))
            .describe(
              "Unsigned integer as a decimal string — used where values may exceed 2^53 (u64/u128 amounts, 1e9-scaled prices).",
            ),
          max_burn_per_tx: z
            .string()
            .regex(new RegExp("^[0-9]+$"))
            .describe(
              "Unsigned integer as a decimal string — used where values may exceed 2^53 (u64/u128 amounts, 1e9-scaled prices).",
            ),
          daily_mint: z
            .string()
            .regex(new RegExp("^[0-9]+$"))
            .describe(
              "Unsigned integer as a decimal string — used where values may exceed 2^53 (u64/u128 amounts, 1e9-scaled prices).",
            ),
          daily_burn: z
            .string()
            .regex(new RegExp("^[0-9]+$"))
            .describe(
              "Unsigned integer as a decimal string — used where values may exceed 2^53 (u64/u128 amounts, 1e9-scaled prices).",
            ),
          personal_burn: z.object({
            cap_amount: z
              .string()
              .regex(new RegExp("^[0-9]+$"))
              .describe(
                "Unsigned integer as a decimal string — used where values may exceed 2^53 (u64/u128 amounts, 1e9-scaled prices).",
              ),
            window_ms: z
              .string()
              .regex(new RegExp("^[0-9]+$"))
              .describe(
                "Unsigned integer as a decimal string — used where values may exceed 2^53 (u64/u128 amounts, 1e9-scaled prices).",
              ),
          }),
        }),
      }),
      withdrawal_queue: z.object({
        queue: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        executors: z
          .array(
            z
              .string()
              .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
              .describe("32-byte Sui object/package id."),
          )
          .optional(),
      }),
      prediction: z.object({
        global_config: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        admin_cap: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("Admin capability object id."),
        market_registries: z.record(
          z
            .string()
            .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
            .describe("32-byte Sui object/package id."),
        ),
        settlement_coin_types: z.record(
          z
            .string()
            .regex(
              new RegExp(
                "^0x[0-9a-fA-F]{1,64}::[A-Za-z_][A-Za-z0-9_]*::[A-Za-z_][A-Za-z0-9_]*$",
              ),
            )
            .describe("Fully-qualified Move type tag."),
        ),
        claimable_link_config: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        gift_admin_cap: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
      }),
      usd: z.object({
        metadata_cap: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
      }),
      faucet: z
        .object({
          faucet: z
            .string()
            .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
            .describe("32-byte Sui object/package id."),
          whitelist: z.array(
            z
              .string()
              .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
              .describe("32-byte Sui object/package id."),
          ),
        })
        .optional(),
      mock_usdsui: z
        .object({
          currency_type: z
            .string()
            .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
            .describe("32-byte Sui object/package id."),
          metadata_cap: z
            .string()
            .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
            .describe("32-byte Sui object/package id."),
          treasury_cap: z
            .string()
            .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
            .describe("32-byte Sui object/package id."),
        })
        .optional(),
    }),
    oracle_rules: z.object({
      waterx: z.object({
        package: z.string(),
        rule_config_object: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        enclave: z
          .object({
            object: z
              .string()
              .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
              .describe("32-byte Sui object/package id."),
            cap: z
              .string()
              .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
              .describe("32-byte Sui object/package id."),
            config: z
              .string()
              .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
              .describe("32-byte Sui object/package id."),
            pubkey: z
              .string()
              .regex(new RegExp("^[0-9a-fA-F]{64}$"))
              .describe(
                "Registered enclave ed25519 pubkey (hex, no 0x). The SOLE config home; k8s-infra pins an independent env copy by design (boot-without-enclave).",
              ),
          })
          .describe(
            "The ONE home for enclave identity (object, cap, config, pubkey).",
          ),
      }),
      pyth: z.object({
        package: z.string(),
        pyth_config_object: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        pyth_price_feeds: z
          .record(
            z.object({
              feed_id: z
                .string()
                .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
                .describe(
                  "Pyth price-feed identifier (32-byte hex). NOT a Sui object id.",
                ),
              price_info_object: z
                .string()
                .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
                .describe(
                  "The shared PriceInfoObject itself — NOT the Field<PriceIdentifier, ID> wrapper object; passing the wrapper is the classic mistake.",
                ),
            }),
          )
          .describe(
            "Per-symbol Pyth price feed: feed_id (Pyth) + price_info_object (Sui object the keeper refreshes).",
          ),
      }),
      pyth_lazer: z
        .object({
          package: z.string(),
          lazer_state_object: z
            .string()
            .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
            .describe("32-byte Sui object/package id."),
          lazer_config_object: z
            .string()
            .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
            .describe("32-byte Sui object/package id."),
          lazer_feed_ids: z
            .record(z.number().int())
            .describe(
              "Per-symbol Pyth Lazer numeric feed id, as used by the keeper's Lazer WS subscription.",
            ),
        })
        .optional(),
      constant: z.object({
        package: z.string(),
        rule_config_object: z
          .string()
          .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
          .describe("32-byte Sui object/package id."),
        constant_prices: z
          .record(
            z.object({
              price: z
                .string()
                .regex(new RegExp("^[0-9]+$"))
                .describe(
                  "Unsigned integer as a decimal string — used where values may exceed 2^53 (u64/u128 amounts, 1e9-scaled prices).",
                ),
            }),
          )
          .describe(
            'Per-symbol constant price, 1e9-scaled decimal string (e.g. "1000000000" = 1.0).',
          ),
      }),
      supra: z
        .object({
          package: z.string(),
          rule_config_object: z
            .string()
            .regex(new RegExp("^0x[0-9a-fA-F]{64}$"))
            .describe("32-byte Sui object/package id."),
          pair_ids: z.record(z.number().int()),
        })
        .optional(),
    }),
    coin_registry: z
      .string()
      .regex(new RegExp("^0x[0-9a-fA-F]{1,64}$"))
      .describe("0x-prefixed hex id/address (Sui short-form or EVM)."),
    evm: z.object({
      bridge: z.object({
        chains: z.record(
          z.object({
            chain_id: z.number().int(),
            wormhole_chain_id: z.number().int(),
            wormhole_core: z
              .string()
              .regex(new RegExp("^0x[0-9a-fA-F]{1,64}$"))
              .describe(
                "Wormhole core contract address on this EVM chain (20-byte, 0x + 40 hex).",
              ),
            wormhole_executor: z
              .string()
              .regex(new RegExp("^0x[0-9a-fA-F]{1,64}$"))
              .describe("0x-prefixed hex id/address (Sui short-form or EVM)."),
            block_explorer: z.string(),
            deposit_vault: z
              .string()
              .regex(new RegExp("^0x[0-9a-fA-F]{1,64}$"))
              .describe(
                "Deposit vault contract address on this EVM chain (20-byte, 0x + 40 hex).",
              ),
            tokens: z.record(
              z
                .string()
                .regex(new RegExp("^0x[0-9a-fA-F]{1,64}$"))
                .describe(
                  "0x-prefixed hex id/address (Sui short-form or EVM).",
                ),
            ),
          }),
        ),
      }),
    }),
  })
  .describe(
    "One WaterX network deployment in the consolidated shape: one symbol universe, uniform package identity, domain-grouped shared objects, and a named per-rule oracle registry. See docs/FIELDS.md.",
  );
