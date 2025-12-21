# Minimal Savings Vaults (Time-Locked sBTC)

A minimal on-chain savings protocol on Stacks where users deposit mBTC (mock Bitcoin) into time-locked vaults with optional early withdrawal penalties.

## Features

- Time-locked vaults with custom lock periods
- Early withdrawal with configurable penalty (default 1%)
- Simple savings flow with a single vault contract
- Fully on-chain and deterministic

## Architecture

### Contract Overview

```
├── sip-010-trait.clar          # SIP-010 fungible token standard
├── mock-sbtc.clar              # Mock sBTC token for testing
└── savings-vault.clar          # Savings vaults and time locks
```

### Vault Flow

```
User
  └─> savings-vault.create-vault
        └─> mock-sbtc.transfer (user → savings-vault)

User
  └─> savings-vault.deposit
        └─> mock-sbtc.transfer (user → savings-vault)

User
  └─> savings-vault.withdraw
        ├─> check lock expiry
        └─> mock-sbtc.transfer (savings-vault → user)
```

## Setup

### Prerequisites

- Clarinet v3.10.0 or later
- Node.js v18 or later
- Git

### Installation

```bash
# Install dependencies
npm install

# Verify contracts compile
clarinet check

# Run tests
npm test
```

## Testing

```bash
# Run all tests
npm test
```

## Deployment

### Local Devnet

```bash
./scripts/deploy.sh local
```

### Testnet

```bash
# Configure your wallet in settings/Testnet.toml
./scripts/deploy.sh testnet
```

### Mainnet

Before mainnet deployment:

1. Replace `mock-sbtc` with the real sBTC contract
2. Audit all contracts thoroughly
3. Test extensively on testnet

```bash
./scripts/deploy.sh mainnet
```

### Post-Deployment

```bash
# For testnet: Mint test tokens
clarinet console
>>> (contract-call? .mock-sbtc mint u1000000000000 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

## Usage

### Create a Vault

```clarity
(contract-call? .savings-vault create-vault
  u100000000000    ;; 1000 sBTC (8 decimals)
  u4320            ;; 30 days in blocks
)
```

### Deposit to Existing Vault

```clarity
(contract-call? .savings-vault deposit
  u1              ;; vault-id
  u50000000000    ;; 500 sBTC
)
```

### Withdraw After Lock Expires

```clarity
(contract-call? .savings-vault withdraw
  u1              ;; vault-id
  u50000000000    ;; amount to withdraw
)
```

### Early Withdrawal (with Penalty)

```clarity
(contract-call? .savings-vault early-withdraw
  u1              ;; vault-id
  u50000000000    ;; amount to withdraw
)
;; Returns: { penalty: u500000000, received: u49500000000 }
```
