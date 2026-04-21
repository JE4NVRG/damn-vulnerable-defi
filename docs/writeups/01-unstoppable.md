# Challenge #1: Unstoppable

- **Difficulty**: Easy
- **Category**: Invariant Mismatch
- **Severity**: High
- **Status**: SOLVED

## Overview

The Unstoppable vault is an ERC-4626 tokenized vault that offers flash loans. It maintains an internal invariant comparing the vault's token supply against its actual token balance. The vault is designed to be a reliable flash loan provider, but a critical flaw in how it tracks its accounting allows anyone to permanently brick the entire system with a single token transfer.

## Vulnerability

The vault enforces the following invariant inside its `flashLoan()` function:

```solidity
uint256 balanceBefore = totalAssets();
if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance();
```

This check assumes that `totalAssets()` (which calls `asset.balanceOf(address(this))`) will always equal the internally tracked share-to-asset conversion. However, ERC-20 tokens can be transferred directly to any address without invoking the vault's `deposit()` function. When tokens are sent directly via `token.transfer(address(vault), amount)`, the vault's `balanceOf` increases but `totalSupply` of shares remains unchanged, permanently breaking the invariant.

The core issue is **relying on `balanceOf()` for accounting instead of internal bookkeeping**. The vault conflates its actual token holdings with what it expects to hold based on deposits and withdrawals.

## Exploit Walkthrough

The exploit is elegantly simple — a single line of code:

```solidity
token.transfer(address(vault), 1);
```

**Step 1**: The attacker holds at least 1 DVT token.

**Step 2**: The attacker calls `token.transfer(address(vault), 1)`, sending 1 token directly to the vault contract, bypassing `deposit()`.

**Step 3**: Now `balanceOf(vault)` is `totalAssets + 1`, but `convertToShares(totalSupply)` still reflects the old balance. The invariant check in `flashLoan()` will always revert.

**Step 4**: Every subsequent call to `flashLoan()` reverts with `InvalidBalance()`. The vault is permanently bricked — no flash loans can ever be executed again. All deposited funds remain locked (deposits and withdrawals may still work, but the vault's primary function is destroyed).

## Real-World Impact

This pattern mirrors accounting invariant issues seen in production:

- **Compound Finance** has historically dealt with similar internal vs. external balance discrepancies, where direct token transfers could desynchronize internal accounting models.
- **ERC-4626 vault implementations** across DeFi have been audited specifically for this class of bug, as the standard's reliance on `totalAssets()` makes it a recurring attack surface.
- The broader lesson applies to any contract that uses `address(this).balance` or `token.balanceOf(address(this))` as a source of truth — including early Ethereum contracts vulnerable to selfdestruct-based forced ETH sends.

## Remediation

Replace `balanceOf()` reliance with internal accounting:

```solidity
// Before (vulnerable)
uint256 balanceBefore = totalAssets(); // uses balanceOf()
if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance();

// After (fixed)
uint256 balanceBefore = _internalBalance; // track deposits/withdrawals internally

function deposit(uint256 assets, address receiver) public override returns (uint256) {
    _internalBalance += assets;
    return super.deposit(assets, receiver);
}

function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
    _internalBalance -= assets;
    return super.withdraw(assets, receiver, owner);
}
```

Alternatively, remove the invariant check entirely and rely on the ERC-4626 share math, which is inherently donation-resistant when implemented correctly (the extra tokens simply accrue to existing shareholders).

## Key Takeaway

Never use `balanceOf(address(this))` as an invariant — external transfers can always break it.
