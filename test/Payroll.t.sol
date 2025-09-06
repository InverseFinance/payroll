// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Payroll} from "../src/Payroll.sol";
import {MockERC20} from "./utils/MockERC20.sol";

contract PayrollTest is Test {
    Payroll public payroll;
    MockERC20 public dola;

    address public governance;
    address public treasury;
    address public alice;
    address public bob;

    event SetRecipient(address recipient, uint256 amount, uint256 endTime);
    event RecipientRemoved(address recipient);
    event AmountWithdrawn(address recipient, uint256 amount);

    function setUp() public {
        governance = makeAddr("governance");
        treasury = makeAddr("treasury");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        dola = new MockERC20("DOLA", "DOLA");
        dola.mint(treasury, 1_000_000 ether);

        payroll = new Payroll(treasury, governance, address(dola));

        vm.prank(treasury);
        dola.approve(address(payroll), type(uint256).max);
    }

    function test_constructor_sets_immutables() public {
        assertEq(payroll.treasuryAddress(), treasury);
        assertEq(payroll.governance(), governance);
        assertEq(address(payroll.DOLA()), address(dola));
    }

    function test_setRecipient_only_governance() public {
        uint256 endTime = block.timestamp + 10;
        vm.prank(alice);
        vm.expectRevert(bytes("DolaPayroll::setRecipient: only governance"));
        payroll.setRecipient(alice, 100, endTime);
    }

    function test_setRecipient_zero_address_reverts() public {
        uint256 endTime = block.timestamp + 10;
        vm.prank(governance);
        vm.expectRevert(bytes("DolaPayroll::setRecipient: zero address!"));
        payroll.setRecipient(address(0), 100, endTime);
    }

    function test_setRecipient_sets_fields_and_emits_event() public {
        uint256 t0 = 1_000_000;
        vm.warp(t0);

        uint256 endTime = t0 + 10_000;
        uint256 yearly = 365 days * 1_000; // ratePerSecond should be 1_000

        vm.expectEmit(true, true, true, true);
        emit SetRecipient(alice, yearly, endTime);

        vm.prank(governance);
        payroll.setRecipient(alice, yearly, endTime);

        (uint256 lastClaim, uint256 ratePerSecond, uint256 end) = payroll.recipients(alice);
        assertEq(lastClaim, t0);
        assertEq(ratePerSecond, 1_000);
        assertEq(end, endTime);
    }

    function test_setRecipient_past_end_normalized_to_now() public {
        uint256 t0 = 2_000_000;
        vm.warp(t0);

        uint256 pastEnd = t0 - 1_234;
        uint256 yearly = 365 days * 10;

        vm.expectEmit(true, true, true, true);
        emit SetRecipient(alice, yearly, t0);

        vm.prank(governance);
        payroll.setRecipient(alice, yearly, pastEnd);

        (, uint256 ratePerSecond, uint256 end) = payroll.recipients(alice);
        assertEq(ratePerSecond, 10);
        assertEq(end, t0);
    }

    function test_balanceOf_during_active_period() public {
        uint256 t0 = 3_000_000;
        vm.warp(t0);
        uint256 yearly = 365 days * 10; // rate 10/sec

        vm.prank(governance);
        payroll.setRecipient(alice, yearly, t0 + 10_000);

        vm.warp(t0 + 1234); // 1234 seconds passed
        uint256 bal = payroll.balanceOf(alice);
        assertEq(bal, 10 * 1234);
    }

    function test_balanceOf_after_end_time() public {
        uint256 t0 = 4_000_000;
        vm.warp(t0);
        uint256 yearly = 365 days * 10; // rate 10/sec

        vm.prank(governance);
        payroll.setRecipient(alice, yearly, t0 + 400);

        vm.warp(t0 + 1_000); // past end
        uint256 bal = payroll.balanceOf(alice);
        // accrues only until end (400 seconds)
        assertEq(bal, 10 * 400);
    }

    function test_withdraw_transfers_and_resets_unclaimed_and_emits_event() public {
        uint256 t0 = 5_000_000;
        vm.warp(t0);
        uint256 yearly = 365 days * 20; // rate 20/sec

        vm.prank(governance);
        payroll.setRecipient(alice, yearly, t0 + 10_000);

        vm.warp(t0 + 123);
        uint256 expectedAmount = 20 * 123;

        uint256 treasuryBefore = dola.balanceOf(treasury);
        uint256 aliceBefore = dola.balanceOf(alice);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit AmountWithdrawn(alice, expectedAmount);
        payroll.withdraw();

        uint256 treasuryAfter = dola.balanceOf(treasury);
        uint256 aliceAfter = dola.balanceOf(alice);

        assertEq(treasuryAfter, treasuryBefore - expectedAmount);
        assertEq(aliceAfter, aliceBefore + expectedAmount);
        assertEq(payroll.unclaimed(alice), 0);
    }

    function test_updateRecipient_accrues_prior_unclaimed_before_rate_change() public {
        uint256 t0 = 6_000_000;
        vm.warp(t0);
        uint256 yearly1 = 365 days * 10; // 10/sec
        uint256 yearly2 = 365 days * 20; // 20/sec

        vm.prank(governance);
        payroll.setRecipient(alice, yearly1, t0 + 10_000);

        vm.warp(t0 + 100);
        // Changing to a new rate; internal updateRecipient should accrue the first 100 * 10
        vm.prank(governance);
        payroll.setRecipient(alice, yearly2, t0 + 20_000);

        // unclaimed should contain the accrued amount from the first schedule
        assertEq(payroll.unclaimed(alice), 10 * 100);

        // New accrual from the second schedule after lastClaim reset at t0+100
        vm.warp(t0 + 150);
        uint256 bal = payroll.balanceOf(alice);
        // 100*10 (old) + 50*20 (new)
        assertEq(bal, (10 * 100) + (20 * 50));
    }
}
