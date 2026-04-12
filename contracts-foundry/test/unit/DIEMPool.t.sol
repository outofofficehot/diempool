// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console2 } from "forge-std/Test.sol";
import { DIEMPool } from "../../src/DIEMPool.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

contract DIEMPoolTest is Test {
    DIEMPool public pool;
    MockERC20 public diem;
    MockERC20 public usdc;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 public constant INITIAL_BALANCE = 10_000e18;
    uint256 public constant USDC_BALANCE = 100_000e6;

    function setUp() public {
        // Deploy tokens
        diem = new MockERC20("DIEM", "DIEM", 18);
        usdc = new MockERC20("USDC", "USDC", 6);

        // Deploy pool
        vm.prank(owner);
        pool = new DIEMPool(address(diem), address(usdc), owner);

        // Mint tokens to users
        diem.mint(alice, INITIAL_BALANCE);
        diem.mint(bob, INITIAL_BALANCE);
        diem.mint(charlie, INITIAL_BALANCE);
        usdc.mint(owner, USDC_BALANCE);

        // Approve pool
        vm.prank(alice);
        diem.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        diem.approve(address(pool), type(uint256).max);
        vm.prank(charlie);
        diem.approve(address(pool), type(uint256).max);
        vm.prank(owner);
        usdc.approve(address(pool), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public view {
        assertEq(address(pool.diemToken()), address(diem));
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
                              STAKE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Stake() public {
        uint256 amount = 1000e18;

        vm.prank(alice);
        pool.stake(amount);

        assertEq(pool.stakedAmount(alice), amount);
        assertEq(pool.totalStaked(), amount);
        assertEq(diem.balanceOf(address(pool)), amount);
        assertEq(diem.balanceOf(alice), INITIAL_BALANCE - amount);
    }

    function test_Stake_Multiple() public {
        vm.prank(alice);
        pool.stake(1000e18);

        vm.prank(bob);
        pool.stake(2000e18);

        assertEq(pool.totalStaked(), 3000e18);
        assertEq(pool.stakedAmount(alice), 1000e18);
        assertEq(pool.stakedAmount(bob), 2000e18);
    }

    function test_Stake_RevertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(DIEMPool.ZeroAmount.selector);
        pool.stake(0);
    }

    function test_Stake_RevertsWhenPaused() public {
        vm.prank(owner);
        pool.pause();

        vm.prank(alice);
        vm.expectRevert();
        pool.stake(1000e18);
    }

    function testFuzz_Stake(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.prank(alice);
        pool.stake(amount);

        assertEq(pool.stakedAmount(alice), amount);
        assertEq(pool.totalStaked(), amount);
    }

    /*//////////////////////////////////////////////////////////////
                             UNSTAKE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Unstake() public {
        uint256 stakeAmount = 1000e18;
        uint256 unstakeAmount = 400e18;

        vm.prank(alice);
        pool.stake(stakeAmount);

        vm.prank(alice);
        pool.unstake(unstakeAmount);

        assertEq(pool.stakedAmount(alice), stakeAmount - unstakeAmount);
        assertEq(pool.totalStaked(), stakeAmount - unstakeAmount);
        assertEq(diem.balanceOf(alice), INITIAL_BALANCE - stakeAmount + unstakeAmount);
    }

    function test_Unstake_Full() public {
        uint256 amount = 1000e18;

        vm.prank(alice);
        pool.stake(amount);

        vm.prank(alice);
        pool.unstake(amount);

        assertEq(pool.stakedAmount(alice), 0);
        assertEq(pool.totalStaked(), 0);
        assertEq(diem.balanceOf(alice), INITIAL_BALANCE);
    }

    function test_Unstake_RevertsOnZero() public {
        vm.prank(alice);
        pool.stake(1000e18);

        vm.prank(alice);
        vm.expectRevert(DIEMPool.ZeroAmount.selector);
        pool.unstake(0);
    }

    function test_Unstake_RevertsOnInsufficientStake() public {
        vm.prank(alice);
        pool.stake(1000e18);

        vm.prank(alice);
        vm.expectRevert(DIEMPool.InsufficientStake.selector);
        pool.unstake(1001e18);
    }

    /*//////////////////////////////////////////////////////////////
                        YIELD DISTRIBUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DistributeYield() public {
        // Alice stakes 1000 DIEM
        vm.prank(alice);
        pool.stake(1000e18);

        // Owner distributes 100 USDC
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
        pool.stake(1000e18);
        vm.prank(bob);
        pool.stake(3000e18);

        // Owner distributes 100 USDC
        vm.prank(owner);
        pool.distributeYield(100e6);

        // 95 USDC to stakers: Alice gets 25%, Bob gets 75%
        assertEq(pool.pendingYield(alice), 23_750_000); // 95 * 0.25 = 23.75 USDC
        assertEq(pool.pendingYield(bob), 71_250_000); // 95 * 0.75 = 71.25 USDC
    }

    function test_DistributeYield_RevertsOnZero() public {
        vm.prank(alice);
        pool.stake(1000e18);

        vm.prank(owner);
        vm.expectRevert(DIEMPool.ZeroAmount.selector);
        pool.distributeYield(0);
    }

    function test_DistributeYield_RevertsWithNoStakers() public {
        vm.prank(owner);
        vm.expectRevert(DIEMPool.NoStakers.selector);
        pool.distributeYield(100e6);
    }

    function test_DistributeYield_OnlyOwner() public {
        vm.prank(alice);
        pool.stake(1000e18);

        vm.prank(alice);
        vm.expectRevert();
        pool.distributeYield(100e6);
    }

    /*//////////////////////////////////////////////////////////////
                          CLAIM YIELD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ClaimYield() public {
        vm.prank(alice);
        pool.stake(1000e18);

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
        pool.stake(1000e18);

        vm.prank(alice);
        vm.expectRevert(DIEMPool.NoYieldToClaim.selector);
        pool.claimYield();
    }

    function test_ClaimOperatorYield() public {
        vm.prank(alice);
        pool.stake(1000e18);

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
                              EXIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Exit() public {
        vm.prank(alice);
        pool.stake(1000e18);

        vm.prank(owner);
        pool.distributeYield(100e6);

        uint256 diemBefore = diem.balanceOf(alice);
        uint256 usdcBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        pool.exit();

        assertEq(diem.balanceOf(alice), diemBefore + 1000e18);
        assertEq(usdc.balanceOf(alice), usdcBefore + 95e6);
        assertEq(pool.stakedAmount(alice), 0);
        assertEq(pool.pendingYield(alice), 0);
    }

    /*//////////////////////////////////////////////////////////////
                           EMERGENCY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EmergencyWithdraw() public {
        vm.prank(alice);
        pool.stake(1000e18);

        vm.prank(owner);
        pool.distributeYield(100e6);

        vm.prank(owner);
        pool.pause();

        uint256 balanceBefore = diem.balanceOf(alice);

        vm.prank(alice);
        pool.emergencyWithdraw();

        // Gets DIEM back but forfeits yield
        assertEq(diem.balanceOf(alice), balanceBefore + 1000e18);
        assertEq(pool.stakedAmount(alice), 0);
        assertEq(pool.pendingYield(alice), 0);
    }

    function test_EmergencyWithdraw_RevertsWhenNotPaused() public {
        vm.prank(alice);
        pool.stake(1000e18);

        vm.prank(alice);
        vm.expectRevert();
        pool.emergencyWithdraw();
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLEX SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ComplexScenario_MultipleDistributions() public {
        // Alice stakes 1000 DIEM
        vm.prank(alice);
        pool.stake(1000e18);

        // First distribution: 100 USDC
        vm.prank(owner);
        pool.distributeYield(100e6);

        // Bob stakes 1000 DIEM (same as Alice now)
        vm.prank(bob);
        pool.stake(1000e18);

        // Second distribution: 100 USDC (split 50/50 between Alice and Bob)
        vm.prank(owner);
        pool.distributeYield(100e6);

        // Alice: 95 + 47.5 = 142.5 USDC
        // Bob: 47.5 USDC
        assertEq(pool.pendingYield(alice), 142_500_000);
        assertEq(pool.pendingYield(bob), 47_500_000);
    }

    function test_ComplexScenario_StakeUnstakeDistribute() public {
        // Alice stakes 2000 DIEM
        vm.prank(alice);
        pool.stake(2000e18);

        // Distribution 1
        vm.prank(owner);
        pool.distributeYield(100e6);

        // Alice unstakes half
        vm.prank(alice);
        pool.unstake(1000e18);

        // Her pending yield should be preserved
        assertEq(pool.pendingYield(alice), 95e6);

        // Bob stakes 1000 DIEM (same as Alice now)
        vm.prank(bob);
        pool.stake(1000e18);

        // Distribution 2
        vm.prank(owner);
        pool.distributeYield(100e6);

        // Alice: 95 + 47.5 = 142.5 USDC
        // Bob: 47.5 USDC
        assertEq(pool.pendingYield(alice), 142_500_000);
        assertEq(pool.pendingYield(bob), 47_500_000);
    }
}
