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
    address public buyer = makeAddr("buyer");

    uint256 public constant INITIAL_DIEM = 10_000e18;
    uint256 public constant INITIAL_USDC = 100_000e6;

    function setUp() public {
        // Deploy tokens
        diem = new MockDIEM();
        usdc = new MockERC20("USDC", "USDC", 6);

        // Deploy pool
        vm.prank(owner);
        pool = new DIEMPool(address(diem), address(usdc), owner);

        // Mint tokens
        diem.mint(alice, INITIAL_DIEM);
        diem.mint(bob, INITIAL_DIEM);
        usdc.mint(buyer, INITIAL_USDC);
        usdc.mint(owner, INITIAL_USDC);

        // Approvals
        vm.prank(alice);
        diem.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        diem.approve(address(pool), type(uint256).max);
        vm.prank(buyer);
        usdc.approve(address(pool), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public view {
        assertEq(address(pool.DIEM()), address(diem));
        assertEq(address(pool.USDC()), address(usdc));
        assertEq(pool.owner(), owner);
        assertEq(pool.totalShares(), 0);
        assertEq(pool.totalStakedDIEM(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                             DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_FirstDepositor() public {
        uint256 amount = 1000e18;

        vm.prank(alice);
        pool.deposit(amount);

        // First depositor gets 1:1 shares
        (uint256 shares,,,,,) = pool.stakers(alice);
        assertEq(shares, amount);
        assertEq(pool.totalShares(), amount);
        assertEq(pool.totalStakedDIEM(), amount);

        // Credits should be available (1 DIEM = 1e6 credits)
        assertEq(pool.availableCreditsToday(), 1000e6);
    }

    function test_Deposit_SecondDepositor() public {
        // Alice deposits 1000 DIEM
        vm.prank(alice);
        pool.deposit(1000e18);

        // Bob deposits 1000 DIEM (should get same shares as Alice)
        vm.prank(bob);
        pool.deposit(1000e18);

        (uint256 aliceShares,,,,,) = pool.stakers(alice);
        (uint256 bobShares,,,,,) = pool.stakers(bob);

        assertEq(aliceShares, bobShares);
        assertEq(pool.totalShares(), 2000e18);
        assertEq(pool.totalStakedDIEM(), 2000e18);
    }

    function test_Deposit_AfterYield() public {
        // Alice deposits
        vm.prank(alice);
        pool.deposit(1000e18);

        // Buyer purchases credits (generates yield)
        vm.prank(buyer);
        pool.buyCredits(100e6); // Buy $100 worth of credits

        // Bob deposits same amount as Alice
        vm.prank(bob);
        pool.deposit(1000e18);

        // Bob should get same shares since ratio is based on DIEM not total value
        (uint256 aliceShares,,,,,) = pool.stakers(alice);
        (uint256 bobShares,,,,,) = pool.stakers(bob);

        assertEq(aliceShares, bobShares);
    }

    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, 1e18, INITIAL_DIEM);

        vm.prank(alice);
        pool.deposit(amount);

        assertEq(pool.totalStakedDIEM(), amount);
    }

    /*//////////////////////////////////////////////////////////////
                          CREDIT PURCHASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BuyCredits() public {
        // Alice stakes 1000 DIEM
        vm.prank(alice);
        pool.deposit(1000e18);

        uint256 creditAmount = 100e6; // $100 worth
        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);

        vm.prank(buyer);
        uint256 cost = pool.buyCredits(creditAmount);

        // Price should be BASE_PRICE (80%) at start of day
        assertEq(cost, 80e6); // $80 for $100 of credits

        // Buyer paid
        assertEq(usdc.balanceOf(buyer), buyerBalanceBefore - cost);

        // Credits reduced
        assertEq(pool.availableCreditsToday(), 900e6);
        assertEq(pool.creditsSoldToday(), 100e6);
    }

    function test_BuyCredits_YieldAccrues() public {
        // Alice stakes
        vm.prank(alice);
        pool.deposit(1000e18);

        // Buyer purchases
        vm.prank(buyer);
        pool.buyCredits(100e6);

        // Alice should have pending yield (95% of $80 = $76)
        uint256 pending = pool.pendingYield(alice);
        assertEq(pending, 76e6);

        // Operator should have 5% = $4
        assertEq(pool.operatorPendingUSDC(), 4e6);
    }

    function test_BuyCredits_YieldSplitBetweenStakers() public {
        // Alice stakes 1000 DIEM, Bob stakes 3000 DIEM (1:3 ratio)
        vm.prank(alice);
        pool.deposit(1000e18);
        vm.prank(bob);
        pool.deposit(3000e18);

        // Buyer purchases $100 credits at 80% = $80
        vm.prank(buyer);
        pool.buyCredits(100e6);

        // Staker amount: 95% of $80 = $76
        // Alice gets 25% = $19
        // Bob gets 75% = $57
        assertEq(pool.pendingYield(alice), 19e6);
        assertEq(pool.pendingYield(bob), 57e6);
    }

    function test_BuyCreditsWithMaxUSDC() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        uint256 maxUSDC = 100e6;

        vm.prank(buyer);
        uint256 credits = pool.buyCreditsWithMaxUSDC(maxUSDC);

        // At 80% price: $100 USDC = 125e6 credits
        assertEq(credits, 125e6);
    }

    function test_BuyCredits_RevertsOnInsufficientCredits() public {
        vm.prank(alice);
        pool.deposit(100e18); // Only 100 DIEM = $100 credits/day

        vm.prank(buyer);
        vm.expectRevert(DIEMPool.InsufficientCredits.selector);
        pool.buyCredits(200e6); // Try to buy $200 worth
    }

    /*//////////////////////////////////////////////////////////////
                          DYNAMIC PRICING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetCurrentPrice_StartOfDay() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        uint256 price = pool.getCurrentPrice();
        assertEq(price, 8000); // 80%
    }

    function test_GetCurrentPrice_EndOfDay_NoSales() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        // Fast forward to end of day
        vm.warp(block.timestamp + 23 hours);

        uint256 price = pool.getCurrentPrice();
        // Should be close to MIN_PRICE (50%) since no sales and late in day
        assertLt(price, 6000); // Less than 60%
        assertGe(price, 5000); // But not below 50%
    }

    function test_GetCurrentPrice_EndOfDay_HighUtilization() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        // Buy most of the credits
        vm.prank(buyer);
        pool.buyCredits(900e6); // 90% utilization

        // Fast forward
        vm.warp(block.timestamp + 23 hours);

        uint256 price = pool.getCurrentPrice();
        // High utilization = small discount even late in day
        assertGt(price, 7000); // Still above 70%
    }

    /*//////////////////////////////////////////////////////////////
                           DAILY RESET TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ResetDay() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        // Buy some credits
        vm.prank(buyer);
        pool.buyCredits(500e6);

        assertEq(pool.creditsSoldToday(), 500e6);
        assertEq(pool.availableCreditsToday(), 500e6);

        // Fast forward past midnight
        vm.warp(block.timestamp + 1 days + 1);

        // Trigger reset
        pool.resetDay();

        // Credits should be reset
        assertEq(pool.creditsSoldToday(), 0);
        assertEq(pool.availableCreditsToday(), 1000e6);
    }

    function test_ResetDay_TriggeredByDeposit() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.warp(block.timestamp + 1 days + 1);

        // Deposit triggers reset
        vm.prank(bob);
        pool.deposit(1000e18);

        assertEq(pool.creditsSoldToday(), 0);
        // Available = 1000 (reset) + 1000 (new deposit) = 2000
        assertEq(pool.availableCreditsToday(), 2000e6);
    }

    /*//////////////////////////////////////////////////////////////
                          CLAIM YIELD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ClaimYield() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(buyer);
        pool.buyCredits(100e6);

        uint256 pending = pool.pendingYield(alice);
        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        pool.claimYield();

        assertEq(usdc.balanceOf(alice), balanceBefore + pending);
        assertEq(pool.pendingYield(alice), 0);
    }

    function test_ClaimYield_DoesNotAffectOthers() public {
        vm.prank(alice);
        pool.deposit(1000e18);
        vm.prank(bob);
        pool.deposit(1000e18);

        vm.prank(buyer);
        pool.buyCredits(100e6);

        uint256 bobPendingBefore = pool.pendingYield(bob);

        vm.prank(alice);
        pool.claimYield();

        // Bob's pending should be unchanged
        assertEq(pool.pendingYield(bob), bobPendingBefore);
    }

    function test_ClaimOperatorYield() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(buyer);
        pool.buyCredits(100e6);

        uint256 pending = pool.operatorPendingUSDC();
        uint256 balanceBefore = usdc.balanceOf(owner);

        vm.prank(owner);
        pool.claimOperatorYield();

        assertEq(usdc.balanceOf(owner), balanceBefore + pending);
        assertEq(pool.operatorPendingUSDC(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                          WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RequestWithdraw() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.requestWithdraw(500e18);

        (
            uint256 shares,,
            uint256 pendingUSDC,
            uint256 stakedDIEM,
            uint256 cooldownDIEM,
            uint256 cooldownEnd
        ) = pool.stakers(alice);

        assertEq(stakedDIEM, 500e18);
        assertEq(cooldownDIEM, 500e18);
        assertGt(cooldownEnd, block.timestamp);
        assertEq(shares, 500e18); // Half shares burned

        // Available credits should be reduced
        assertEq(pool.availableCreditsToday(), 500e6);
    }

    function test_CompleteWithdraw() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.requestWithdraw(1000e18);

        // Fast forward past cooldown
        vm.warp(block.timestamp + 1 days + 1);

        uint256 balanceBefore = diem.balanceOf(alice);

        vm.prank(alice);
        pool.completeWithdraw();

        assertEq(diem.balanceOf(alice), balanceBefore + 1000e18);

        (,,, uint256 stakedDIEM, uint256 cooldownDIEM,) = pool.stakers(alice);
        assertEq(stakedDIEM, 0);
        assertEq(cooldownDIEM, 0);
    }

    function test_CancelWithdraw() public {
        vm.prank(alice);
        pool.deposit(1000e18);

        vm.prank(alice);
        pool.requestWithdraw(500e18);

        vm.prank(alice);
        pool.cancelWithdraw();

        (uint256 shares,,, uint256 stakedDIEM, uint256 cooldownDIEM,) = pool.stakers(alice);
        assertEq(stakedDIEM, 1000e18);
        assertEq(cooldownDIEM, 0);
        assertEq(shares, 1000e18);
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

        // 2. Buyer purchases credits
        vm.prank(buyer);
        pool.buyCredits(200e6); // $200 worth at 80% = $160 paid

        // 3. Check yields (95% of $160 = $152)
        // Alice: 25% of $152 = $38
        // Bob: 75% of $152 = $114
        assertEq(pool.pendingYield(alice), 38e6);
        assertEq(pool.pendingYield(bob), 114e6);

        // 4. Alice claims
        vm.prank(alice);
        pool.claimYield();
        assertEq(usdc.balanceOf(alice), 38e6);

        // 5. More purchases
        vm.prank(buyer);
        pool.buyCredits(100e6); // $80 paid

        // Alice should have new yield: 25% of ($80 * 95%) = $19
        assertEq(pool.pendingYield(alice), 19e6);

        // Bob accumulates: $114 + (75% of $76) = $114 + $57 = $171
        assertEq(pool.pendingYield(bob), 171e6);

        // 6. Alice requests withdrawal
        vm.prank(alice);
        pool.requestWithdraw(1000e18);

        // 7. New day
        vm.warp(block.timestamp + 1 days + 1);

        // 8. Alice completes withdrawal
        vm.prank(alice);
        pool.completeWithdraw();

        // 9. Verify state
        assertEq(diem.balanceOf(alice), INITIAL_DIEM); // Got all DIEM back
        assertEq(pool.totalStakedDIEM(), 3000e18); // Only Bob remains
        assertEq(pool.availableCreditsToday(), 3000e6); // Reset for new day
    }
}
