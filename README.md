# Decentralized Bitcoin-Backed Perpetual Savings Vaults (Auto-Yield in sBTC)

A trustless DeFi savings protocol on Stacks blockchain where users deposit mBTC (mock Bitcoin) into time-locked vaults that automatically earn and compound yield through on-chain adapters.

## 🌟 Features

- **Time-Locked Vaults**: Create vaults with configurable lock periods (7/30/90/180 days)
- **Auto-Yield Generation**: Funds automatically allocated to yield-generating adapters
- **Auto-Compounding**: Periodic harvest and reinvestment of yields
- **Perpetual Mode**: Auto-renew yields without full unlocks
- **Early Withdrawal**: Option to withdraw early with configurable penalty (default 1%)
- **Multiple Adapters**: Support for lending, LP, and other yield strategies
- **Fully On-Chain**: Deterministic, trustless, and reproducible
- **Security-First**: Built with Clarity 3, comprehensive error handling, and access controls

## 📋 Table of Contents

- [Architecture](#architecture)
- [Setup](#setup)
- [Testing](#testing)
- [Deployment](#deployment)
- [Usage](#usage)
- [Contract API](#contract-api)
- [Security](#security)
- [License](#license)

## 🏗️ Architecture

### Contract Overview

```
├── sip-010-trait.clar              # SIP-010 fungible token standard
├── arkadiko-yield-adapter-trait.clar   # Adapter interface
├── mock-sbtc.clar                  # Mock sBTC token for testing
├── arkadiko-yield-adapter.clar     # Mock yield adapter (5% APY)
├── time-lock.clar                  # Lock period management
├── vault-factory.clar              # Vault creation and registry
├── auto-yield-engine.clar          # Yield allocation and compounding
└── main-vault.clar                 # User-facing operations
```

### Contract Interactions

```
┌─────────────┐
│   User      │
└──────┬──────┘
       │
       ↓
┌─────────────────┐       ┌──────────────────┐
│  main-vault     │←─────→│  vault-factory   │
└────────┬────────┘       └──────────────────┘
         │                         ↓
         │                 ┌──────────────────┐
         │                 │   time-lock      │
         │                 └──────────────────┘
         ↓
┌─────────────────┐       ┌──────────────────┐
│ auto-yield-     │←─────→│  adapter (trait) │
│ engine          │       └────────┬─────────┘
└─────────────────┘                │
         ↑                         ↓
         │                 ┌──────────────────┐
         └─────────────────│ arkadiko-adapter │
                           └──────────────────┘
```

## 🚀 Setup

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) v3.10.0 or later
- [Node.js](https://nodejs.org/) v18 or later
- [Git](https://git-scm.com/)

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd savingvault

# Install dependencies
npm install

# Verify contracts compile
clarinet check

# Run tests
npm test
```

## 🧪 Testing

The project includes comprehensive test coverage:

```bash
# Run all tests
npm test

# Run with coverage
npm run test:coverage

# Run specific test file
npm test -- vault-integration.test.ts
```

### Test Coverage

- ✅ Vault creation and initialization
- ✅ Deposit and withdrawal operations
- ✅ Time-lock enforcement
- ✅ Early withdrawal with penalties
- ✅ Yield generation and harvesting
- ✅ Auto-compounding
- ✅ Perpetual vault renewal
- ✅ Access control and authorization
- ✅ Edge cases and error handling

## 📦 Deployment

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

⚠️ **IMPORTANT**: Before mainnet deployment:

1. Replace `mock-sbtc` with real sBTC contract
2. Replace `arkadiko-yield-adapter` with production adapter
3. Audit all contracts thoroughly
4. Test extensively on testnet

```bash
./scripts/deploy.sh mainnet
```

### Post-Deployment Configuration

```bash
# Authorize contracts to interact with time-lock
clarinet console
>>> (contract-call? .main-vault authorize-time-lock-caller)

# For testnet: Mint test tokens
>>> (contract-call? .mock-sbtc mint u1000000000000 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

## 💡 Usage

### Creating a Vault

```clarity
;; Create a 30-day locked vault with 1000 sBTC
(contract-call? .main-vault create-vault-with-deposit
  u100000000000    ;; 1000 sBTC (8 decimals)
  u4320            ;; 30 days in blocks
  .arkadiko-yield-adapter
  false            ;; not perpetual
)
```

### Depositing to Existing Vault

```clarity
(contract-call? .main-vault deposit
  u1              ;; vault-id
  u50000000000    ;; 500 sBTC
)
```

### Withdrawing After Lock Expires

```clarity
;; Wait for lock period to expire
(contract-call? .main-vault withdraw
  u1              ;; vault-id
  u50000000000    ;; amount to withdraw
)
```

### Early Withdrawal (with Penalty)

```clarity
(contract-call? .main-vault early-withdraw
  u1              ;; vault-id
  u50000000000    ;; amount to withdraw
)
;; Returns: { penalty: u50000000, received: u49950000000 }
```

### Harvesting Yield

```clarity
(contract-call? .main-vault harvest-yield u1)
```

### Compounding Yield

```clarity
(contract-call? .main-vault compound-yield u1)
```

### Renewing Perpetual Vault

```clarity
(contract-call? .main-vault renew-perpetual-vault u1)
```

## 📚 Contract API

### main-vault.clar

#### Public Functions

- `create-vault-with-deposit(amount, lock-period, adapter, is-perpetual)` - Create and fund new vault
- `deposit(vault-id, amount)` - Add funds to existing vault
- `withdraw(vault-id, amount)` - Withdraw after lock expires
- `early-withdraw(vault-id, amount)` - Withdraw with penalty
- `harvest-yield(vault-id)` - Collect accrued yield
- `compound-yield(vault-id)` - Reinvest yield into principal
- `renew-perpetual-vault(vault-id)` - Renew perpetual vault

#### Read-Only Functions

- `get-vault-balance(vault-id)` - Get vault principal balance
- `get-vault-total-value(vault-id)` - Get principal + accrued yield
- `can-withdraw-now(vault-id)` - Check if withdrawal allowed
- `get-withdrawal-info(vault-id, amount)` - Get penalty calculation

### vault-factory.clar

#### Public Functions

- `create-vault(initial-deposit, lock-period, adapter, is-perpetual)` - Create vault record
- `close-vault(vault-id)` - Close empty vault
- `update-vault-balance(vault-id, new-balance)` - Update balance (authorized only)
- `update-vault-yield(vault-id, yield-amount)` - Update yield (authorized only)

#### Read-Only Functions

- `get-vault-info(vault-id)` - Get complete vault data
- `get-user-vaults(user)` - Get list of user's vault IDs
- `get-vault-count()` - Get total number of vaults
- `is-vault-owner(vault-id, user)` - Check ownership

### time-lock.clar

#### Public Functions

- `create-lock(vault-id, lock-period, is-perpetual, owner)` - Create time lock
- `extend-lock(vault-id, additional-blocks)` - Extend lock period
- `renew-lock(vault-id)` - Renew perpetual lock
- `set-early-withdrawal-penalty(new-penalty)` - Set penalty rate (admin)

#### Read-Only Functions

- `check-lock-expiry(vault-id)` - Check if lock expired
- `is-locked(vault-id)` - Check if currently locked
- `blocks-until-unlock(vault-id)` - Blocks remaining until unlock
- `calculate-penalty(amount, vault-id)` - Calculate early withdrawal penalty

### auto-yield-engine.clar

#### Public Functions

- `allocate-to-adapter(vault-id, amount)` - Allocate funds to yield adapter
- `harvest-yield(vault-id)` - Harvest yield from adapter
- `compound-yield(vault-id)` - Compound harvested yield
- `withdraw-from-adapter(vault-id, amount)` - Withdraw from adapter
- `auto-harvest-and-compound(vault-id)` - Combined harvest & compound

#### Read-Only Functions

- `get-vault-yield-state(vault-id)` - Get yield tracking data
- `get-auto-compound-settings()` - Get compounding configuration
- `should-compound(vault-id)` - Check if ready to compound

## 🔒 Security

### Security Features

1. **Access Control**: Principal-based ownership verification
2. **Error Handling**: Comprehensive error codes and assertions
3. **Time-Lock Enforcement**: Block-height based lock periods
4. **Safe Arithmetic**: Standard Clarity arithmetic operations
5. **Event Logging**: All major operations emit events
6. **Authorization**: Restricted admin functions
7. **Emergency Pause**: Circuit breaker for main-vault

### Error Codes

| Code | Description |
|------|-------------|
| `u100` | Insufficient balance |
| `u101` | Invalid amount |
| `u102` | Transfer failed |
| `u400` | Invalid amount |
| `u401` | Invalid lock period |
| `u402` | Invalid adapter |
| `u403` | Unauthorized |
| `u404` | Vault not found |
| `u405` | Still locked |
| `u406` | Invalid lock period |
| `u407` | Invalid penalty |
| `u408` | Vault inactive |

### Auditing Recommendations

Before mainnet deployment:

- [ ] Complete formal security audit
- [ ] Verify all arithmetic operations
- [ ] Test edge cases extensively
- [ ] Review access control mechanisms
- [ ] Validate adapter integrations
- [ ] Test emergency procedures
- [ ] Verify upgrade paths

## 🔧 Configuration

### Lock Periods

- **7 days**: 1,008 blocks (~10 min/block)
- **30 days**: 4,320 blocks
- **90 days**: 12,960 blocks
- **180 days**: 25,920 blocks

### Yield Parameters

- **Simulated APY**: 5% (500 basis points)
- **Compounding Threshold**: 0.01 sBTC minimum
- **Early Withdrawal Penalty**: 1% (100 basis points, max 10%)

### Customization

Edit constants in respective contracts:

```clarity
;; In arkadiko-yield-adapter.clar
(define-constant simulated-apy u500)  ;; 5%

;; In time-lock.clar
(define-data-var early-withdrawal-penalty uint u100)  ;; 1%

;; In auto-yield-engine.clar
(define-data-var min-compound-amount uint u1000000)  ;; 0.01 sBTC
```

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details

## 🙏 Acknowledgments

- Stacks Foundation
- Clarity Language Team
- Arkadiko Protocol (inspiration for adapter design)
- Bitcoin and sBTC contributors

## 📞 Support

- Documentation: [docs link]
- Discord: [discord link]
- Twitter: [twitter handle]
- Issues: GitHub Issues

---

**⚠️ Disclaimer**: This is experimental DeFi software. Use at your own risk. Always verify contract addresses and test thoroughly before depositing significant funds.
# The-Vault
