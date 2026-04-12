// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { DIEMPool } from "../../src/DIEMPool.sol";
import { MockDIEM } from "../mocks/MockDIEM.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

contract DIEMPoolTest is Test {
    DIEMPool public pool;
    MockDIEM public diem;
    MockERC20 public usdc;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_BALANCE = 10_000e18;
    uint256 public constant USDC_BALANCE = 100_000e6;

    function setUp() public {
        // Deploy tokens
        diem = new MockDIEM();
        usdc = new MockERC20("USDC", "USDC", 6);

        // Deploy pool
        vm.prank(owner);
        pool = new DIEMPool(address(diem), address(usdc), owner);

        // Mint tokens to users
        diem.mint(alice, INITIAL_BALANCE);
        diem.mint(bob, INITIAL_BALANCE);
        usdc.mint(owner, USDC_BALANCE);

        // Approve pool
        vm.prank(alice);
        diem.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        diem.approve(address(pool), type(uint256).max);
        vm.prank(owner);
        usdc.approve(address(pool), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public view {
        assertEq(address(pool.DIEM()), address(diem));
        assertEq(address(pool.yieldToken()), address(usdc));
        assertEq(pool.owner(), owner);
        assertEq(pool.totalStaked(), 0);
    }

    function test_Constructor_RevertsOnZeroAddress() public {
        vm.expectRevert(DIEMPool.ZeroAddress.selector);
        new DIEMPool(address(0), address(usdc), owner);

        vm.expectRevert(DIEMPool.ZeroAddress.selector);
        new DIEMPool(address(diem), address(0), owner);
    }

    /*//////////////////////////////////////////////////////////////
                             DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit() public {
        uint256 amount = 1000e18;

        vm.prank(alice);
        pool.deposit(amount);

        assertEq(pool.stakedAmount(alice), amount);
        assertEq(pool.totalStaked(), amount);
        // DIEM should be staked in the DIEM contract
        (uint256 stakedInDiem,,) = diem.stakedInfos(address(pool));
        assertEq(stakedInDiem, amount);
    }

    function test_Deposit_Multiple() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(bob);
        pool.deposit(2000e18);

        assertEq(pool.totalStaked(), 3000e18);
        assertEq(pool.stakedAmount(alice), 1000e18);
        assertEq(pool.stakedAmount(bob), 2000e18);
    }

    function test_Deposit_RevertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(DIEMPool.ZeroAmount.selector);
        pool.deposit(0);
    }

    function test_Deposit_RevertsWhenPaused() public {
        vm.prank(owner);
        pool.pause();

        vm.prank(alice);
        vm.expectRevert();
        pool.deposit(1000e18);
    }

    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.prank(alice);
        pool.deposit(amount);

        assertEq(pool.stakedAmount(alice), amount);
        assertEq(pool.totalStaked(), amount);
    }

    /*//////////////////////////////////////////////////////////////
                          WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RequestWithdraw() public {
        uint256 depositAmount = 1000e18;
        uint256 withdrawAmount = 400e18;

        vm.prank(alice);
        pool.deposit(depositAmount);

        vm.prank(alice);
        pool.requestWithdraw(withdrawAmount);

        // Check staker state
        assertEq(pool.stakedAmount(alice), depositAmount - withdrawAmount);
        (uint256 cooldownAmount, uint256 cooldownEnd, bool canComplete) =
            pool.withdrawalStatus(alice);
        assertEq(cooldownAmount, withdrawAmount);
        assertGt(cooldownEnd, block.timestamp);
        assertFalse(canComplete);

        // Check totals
        assertEq(pool.totalStaked(), depositAmount - withdrawAmount);
        (, uint256 totalInCooldown,,) = pool.getPoolStats();
        assertEq(totalInCooldown, withdrawAmount);
    }

    function test_CompleteWithdraw() public {
        uint256 amount = 1000e18;

        vm.prank(alice);
        pool.deposit(amount);

        vm.prank(alice);
        pool.requestWithdraw(amount);

        // Fast forward past cooldown
        vm.warp(block.timestamp + 1 days + 1);

        uint256 balanceBefore = diem.balanceOf(alice);

        vm.prank(alice);
        pool.completeWithdraw();

        // Check DIEM returned
        assertEq(diem.balanceOf(alice), balanceBefore + amount);

        // Check state cleared
        (uint256 cooldownAmount,,) = pool.withdrawalStatus(alice);
        assertEq(cooldownAmount, 0);
    }

    function test_CompleteWithdraw_RevertsBeforeCooldown() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.requestWithdraw(500e18);

        // Try to complete before cooldown
        vm.prank(alice);
        vm.expectRevert(DIEMPool.CooldownNotComplete.selector);
        pool.completeWithdraw();
    }

    function test_RequestWithdraw_RevertsOnZero() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        vm.expectRevert(DIEMPool.ZeroAmount.selector);
        pool.requestWithdraw(0);
    }

    function test_RequestWithdraw_RevertsOnInsufficientStake() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        vm.expectRevert(DIEMPool.InsufficientStake.selector);
        pool.requestWithdraw(1001e18);
    }

    function test_RequestWithdraw_RevertsIfCooldownPending() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.requestWithdraw(500e18);

        // Try to request another while cooldown is pending
        vm.prank(alice);
        vm.expectRevert(DIEMPool.CooldownAlreadyPending.selector);
        pool.requestWithdraw(200e18);
    }

    /*//////////////////////////////////////////////////////////////
                        YIELD DISTRIBUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DistributeYield() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        uint256 yieldAmount = 100e6;
        vm.prank(owner);
        pool.distributeYield(yieldAmount);

        // Check operator fee (5%)
        assertEq(pool.operatorPendingYield(), 5e6);

        // Check alice's pending yield (95%)
        assertEq(pool.pendingYield(alice), 95e6);
    }

    function test_DistributeYield_MultipleStakers() public {
        // Alice stakes 1000 DIEM, Bob stakes 3000 DIEM (1:3 ratio)
        vm.prank(alice);
        pool.deposit(1000e18);
        vm.prank(bob);
        pool.deposit(3000e18);

        // Owner distributes 100 USDC
        vm.prank(owner);
        pool.distributeYield(100e6);

        // 95 USDC to stakers: Alice gets 25%, Bob gets 75%
        assertEq(pool.pendingYield(alice), 23_750_000); // 95 * 0.25 = 23.75 USDC
        assertEq(pool.pendingYield(bob), 71_250_000); // 95 * 0.75 = 71.25 USDC
    }

    function test_DistributeYield_ExcludesCooldown() public {
        // Alice deposits and requests withdraw (goes to cooldown)
        vm.prank(alice);
        pool.deposit(1000e18);
        vm.prank(alice);
        pool.requestWithdraw(1000e18);

        // Bob deposits and stays staked
        vm.prank(bob);
        pool.deposit(1000e18);

        // Distribute yield - only Bob should get it
        vm.prank(owner);
        pool.distributeYield(100e6);

        assertEq(pool.pendingYield(alice), 0); // Alice in cooldown, no yield
        assertEq(pool.pendingYield(bob), 95e6); // Bob gets all 95%
    }

    function test_DistributeYield_RevertsOnZero() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(owner);
        vm.expectRevert(DIEMPool.ZeroAmount.selector);
        pool.distributeYield(0);
    }

    function test_DistributeYield_RevertsWithNoStakers() public {
        vm.prank(owner);
        vm.expectRevert(DIEMPool.NoStakers.selector);
        pool.distributeYield(100e6);
    }

    /*//////////////////////////////////////////////////////////////
                          CLAIM YIELD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ClaimYield() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(owner);
        pool.distributeYield(100e6);

        uint256 expectedYield = 95e6;
        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        pool.claimYield();

        assertEq(usdc.balanceOf(alice), balanceBefore + expectedYield);
        assertEq(pool.pendingYield(alice), 0);
    }

    function test_ClaimYield_RevertsWithNoYield() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        vm.expectRevert(DIEMPool.NoYieldToClaim.selector);
        pool.claimYield();
    }

    function test_ClaimOperatorYield() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(owner);
        pool.distributeYield(100e6);

        uint256 expectedFee = 5e6;
        uint256 balanceBefore = usdc.balanceOf(owner);

        vm.prank(owner);
        pool.claimOperatorYield();

        assertEq(usdc.balanceOf(owner), balanceBefore + expectedFee);
        assertEq(pool.operatorPendingYield(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                           EMERGENCY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EmergencyWithdraw() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(owner);
        pool.distributeYield(100e6);

        vm.prank(owner);
        pool.pause();

        // Note: In emergency, only liquid DIEM can be withdrawn
        // DIEM staked in the DIEM contract requires normal unstake flow

        vm.prank(alice);
        pool.emergencyWithdraw();

        // State should be cleared
        assertEq(pool.stakedAmount(alice), 0);
        assertEq(pool.pendingYield(alice), 0);
    }

    function test_EmergencyWithdraw_RevertsWhenNotPaused() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        vm.expectRevert();
        pool.emergencyWithdraw();
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLEX SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_FullFlow() public {
        // 1. Alice and Bob deposit
        vm.prank(alice);
        pool.deposit(1000e18);
        vm.prank(bob);
        pool.deposit(3000e18);

        // 2. Yield distribution
        vm.prank(owner);
        pool.distributeYield(100e6);

        // 3. Alice claims yield
        vm.prank(alice);
        pool.claimYield();
        assertEq(usdc.balanceOf(alice), 23_750_000);

        // 4. Alice requests withdraw
        vm.prank(alice);
        pool.requestWithdraw(1000e18);

        // 5. More yield distribution (Alice excluded - in cooldown)
        vm.prank(owner);
        pool.distributeYield(100e6);

        // Only Bob gets this yield (95% of 100 USDC)
        // Note: small rounding difference due to precision
        assertApproxEqAbs(pool.pendingYield(bob), 71_250_000 + 95_000_000, 3000); // Previous + new

        // 6. Fast forward and complete Alice's withdraw
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(alice);
        pool.completeWithdraw();

        // 7. Verify final state
        assertEq(diem.balanceOf(alice), INITIAL_BALANCE); // Got all DIEM back
        assertEq(pool.stakedAmount(alice), 0);
        assertEq(pool.totalStaked(), 3000e18); // Only Bob's stake remains
    }

    function test_GetCooldownDuration() public view {
        assertEq(pool.getCooldownDuration(), 1 days);
    }
}
