# DIEMpool Smart Contracts

Non-custodial staking pool for DIEM tokens that enables yield generation from AI inference credit sales.

## Overview

DIEMpool allows DIEM token holders to stake their tokens and earn yield from AI inference credits being sold to developers. The pooled DIEM generates inference credits that are sold at a discount to buyers, with 95% of revenue flowing to stakers and 5% to the protocol operator.

### Key Features

- **Non-custodial**: Only the original staker can withdraw their DIEM
- **No lockup**: Withdraw anytime
- **Daily yield**: Revenue distributed as it comes in
- **Transparent**: All accounting on-chain

## Contracts

| Contract | Description |
|----------|-------------|
| `DIEMPool.sol` | Core staking vault - handles deposits, withdrawals, and yield distribution |
| `CreditMarket.sol` | (Coming soon) Dynamic pricing market for inference credits |

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Build

```bash
forge build
```

### Test

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test test_Stake

# Run fuzz tests with more runs
FOUNDRY_PROFILE=ci forge test
```

### Gas Report

```bash
forge test --gas-report
```

### Coverage

```bash
forge coverage
```

### Format

```bash
forge fmt
```

### Deploy

```bash
# Dry run
forge script script/Deploy.s.sol --rpc-url $RPC_URL

# Deploy
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

## Architecture

```
┌─────────────┐     stake      ┌─────────────┐
│   Stakers   │ ──────────────►│  DIEMPool   │
│ (DIEM held) │◄────────────── │  Contract   │
└─────────────┘   yield (95%)  └─────────────┘
                                      │
                                      │ distributeYield()
                                      │
                               ┌──────┴──────┐
                               │  Operator   │
                               │ (5% fee)    │
                               └─────────────┘
```

## Security

### Non-custodial Model

- `stake()`: Only the caller can deposit their tokens
- `unstake()`: Only the staker can withdraw their own tokens
- `emergencyWithdraw()`: Available when paused, allows stakers to exit (forfeits pending yield)

### Operator Permissions

The operator (owner) can:
- Distribute yield from credit sales
- Claim their 5% fee
- Pause/unpause the contract

The operator **cannot**:
- Withdraw stakers' DIEM
- Modify the fee percentage (hardcoded at 5%)
- Prevent users from unstaking (except via pause)

### Audit Status

⚠️ **Not yet audited** - Use at your own risk

## License

MIT
