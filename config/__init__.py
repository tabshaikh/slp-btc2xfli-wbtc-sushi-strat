## Ideally, they have one file with the settings for the strat and deployment
## This file would allow them to configure so they can test, deploy and interact with the strategy

BADGER_DEV_MULTISIG = "0xb65cef03b9b89f99517643226d76e286ee999e77"

WANT = "0x164fe0239d703379bddde3c80e4d4800a1cd452b"  ## BTC2X-FLI/WBTC-SLP Token https://etherscan.io/token/0x164fe0239d703379bddde3c80e4d4800a1cd452b
REWARD_TOKEN = "0x6b3595068778dd592e39a122f4f5a5cf09c90fe2"  ## Sushi Token

PROTECTED_TOKENS = [WANT, REWARD_TOKEN]
## Fees in Basis Points
DEFAULT_GOV_PERFORMANCE_FEE = 1000
DEFAULT_PERFORMANCE_FEE = 1000
DEFAULT_WITHDRAWAL_FEE = 50

FEES = [DEFAULT_GOV_PERFORMANCE_FEE, DEFAULT_PERFORMANCE_FEE, DEFAULT_WITHDRAWAL_FEE]

REGISTRY = "0xFda7eB6f8b7a9e9fCFd348042ae675d1d652454f"  # Multichain BadgerRegistry
