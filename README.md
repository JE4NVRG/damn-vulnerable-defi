# Damn Vulnerable DeFi Solutions by Je4nDev

A complete, hands-on solve of **Damn Vulnerable DeFi v4** using **Foundry**, focused on learning smart contract security by exploiting realistic vulnerabilities and proving each exploit with passing tests.

> Status: **18 / 18 challenges solved** ✅

This repository is my practical Solidity security lab. The goal was not just to "finish the CTF", but to build real auditing instincts through:

- reading vulnerable code,
- identifying the broken assumption,
- writing the exploit,
- validating it with reproducible tests,
- and extracting the security lesson behind each bug.

## Why this repo exists

I wanted a portfolio that shows actual exploit development, not just theory.

This repo demonstrates:
- Solidity + Foundry workflow in WSL
- exploit construction in realistic DeFi scenarios
- debugging through failing traces and invariant reasoning
- security pattern recognition across lending, governance, oracles, wallets, upgradeability, distributions, bridges, and timelocks

## Tech stack

- **Solidity 0.8.25**
- **Foundry**
- **WSL + VS Code**
- **Mainnet fork testing** for fork-dependent challenges

## Challenge status

| # | Challenge | Status | Main vulnerability pattern |
|---|---|---|---|
| 1 | Unstoppable | ✅ | Invariant mismatch |
| 2 | Naive Receiver | ✅ | Fixed fee drain |
| 3 | Truster | ✅ | Arbitrary external call |
| 4 | Selfie | ✅ | Flash loan governance |
| 5 | The Rewarder | ✅ | Merkle claim duplication |
| 6 | Puppet | ✅ | Spot-price oracle manipulation |
| 7 | Compromised | ✅ | Leaked private keys |
| 8 | Puppet V2 | ✅ | Uniswap V2 oracle manipulation |
| 9 | Free Rider | ✅ | NFT marketplace accounting flaw + flash swap |
| 10 | Side Entrance | ✅ | Flash loan accounting bug |
| 11 | Withdrawal | ✅ | State change before external call |
| 12 | ABI Smuggling | ✅ | Hardcoded calldata offset / auth bypass |
| 13 | Backdoor | ✅ | Safe setup delegatecall abuse |
| 14 | Wallet Mining | ✅ | Proxy storage collision / reinitialization |
| 15 | Shards | ✅ | Broken refund math |
| 16 | Climber | ✅ | Timelock execution-order bug |
| 17 | Puppet V3 | ✅ | Short-window TWAP manipulation |
| 18 | Curvy Puppet | ✅ | Manipulable LP valuation / virtual price abuse |

## Key security lessons

Across the full set, the main patterns I trained were:

1. **Never trust external balances as internal accounting**
2. **Fixed fees and loops can become drain vectors**
3. **User-controlled arbitrary calls are usually fatal**
4. **Flash loans can temporarily buy power, not just liquidity**
5. **Claim tracking must happen before value transfer**
6. **Spot and weak-TWAP oracles are manipulable**
7. **Credentials leaked in docs are still exploit paths**
8. **State changes before external calls create inconsistent finality**
9. **ABI assumptions can become access control bypasses**
10. **Upgradeable/proxy storage layout mistakes can reopen initialization**
11. **Timelocks are only safe if validation happens before effects**
12. **LP pricing and vault math can be manipulated if treated as trusted oracles**

## Repository structure

Each challenge follows the original DVDF layout:

- `src/<challenge>/` → vulnerable contracts and challenge prompt
- `test/<challenge>/<Challenge>.t.sol` → exploit implementation and validation

My solutions live directly in the corresponding **Foundry test files**.

## Running the solutions

### Install
```bash
forge install
```

### Run a specific challenge
```bash
forge test --match-contract BackdoorChallenge -vvv
```

### Run the full suite
```bash
forge test -vvv
```

## Mainnet fork challenges

Some challenges require a mainnet archive RPC.
Create a `.env` file from `.env.sample`:

```env
MAINNET_FORKING_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
```

This is required for:
- `PuppetV3`
- `CurvyPuppet`

## Notes on approach

I solved these sequentially as deliberate security practice, not by trying to skip straight to bug bounties.
The focus was:

- exploit-first understanding,
- reproducing the bug in code,
- learning the real-world security analogy,
- and building material worthy of a public audit portfolio.

## Next steps

The next step after this repository is turning the solutions into cleaner public writeups, with:

- bug summary
- root cause
- exploit path
- impact
- mitigation
- final passing test

## Credit

Original challenge set by **The Red Guild**:
- Repo: https://github.com/theredguild/damn-vulnerable-defi
- Website: https://damnvulnerabledefi.xyz

This repository is a personal educational solve/portfolio built on top of their work.

## Disclaimer

All vulnerable code in this repository is intentionally insecure and exists for educational purposes only.

**Do not use these patterns in production.**
