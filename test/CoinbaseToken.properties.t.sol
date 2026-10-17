// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CoinbaseToken} from "../src/CoinbaseToken.sol";

/// @dev Complements the basic ERC-20 tests with allowance boundaries, isolation,
/// failure/retry sequences, and properties relating multiple successful calls.
/// forge-config: default.fuzz.runs = 1000
contract CoinbaseTokenPropertiesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    CoinbaseToken internal token;
    address internal alice = makeAddr("property holder alice");
    address internal bob = makeAddr("property holder bob");
    address internal spender = makeAddr("property spender");
    address internal otherSpender = makeAddr("property other spender");

    function setUp() public {
        token = new CoinbaseToken();
    }

    function test_maxMinusOneAllowanceIsFiniteAndOneSmallestUnitIsSpendable() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);

        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unlimitedAllowanceCanBeReducedThenRevoked() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);

        token.approve(spender, type(uint256).max);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfApprovalIsRequiredAndConsumedLikeAnyOtherApproval() public {
        token.transfer(alice, 2);
        vm.prank(alice);
        assertTrue(token.approve(alice, 1));
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, alice), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_unlimitedAllowanceDoesNotAuthorizeMaximumTransferBeyondSupply() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromToZeroRevertsEvenWithUnlimitedApproval() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedTransferFromCanBeRetriedAfterFunding(uint256 rawAmount, bool unlimited) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        uint256 approved = unlimited ? type(uint256).max : amount;
        // An empty holder can authorize future receipts, but approval creates no funds.
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);

        assertTrue(token.transfer(alice, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), unlimited ? type(uint256).max : 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_allowancesAreIsolatedByBothOwnerAndSpender(
        uint256 rawAllowance,
        uint256 unrelatedAllowance,
        uint256 rawAmount
    ) public {
        uint256 approved = bound(rawAllowance, 1, SUPPLY / 2);
        uint256 amount = bound(rawAmount, 1, approved);
        token.transfer(alice, SUPPLY / 2);
        token.transfer(bob, SUPPLY / 2);
        vm.prank(alice);
        token.approve(spender, approved);
        vm.prank(alice);
        token.approve(otherSpender, unrelatedAllowance);
        vm.prank(bob);
        token.approve(spender, unrelatedAllowance);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.allowance(alice, otherSpender), unrelatedAllowance);
        assertEq(token.allowance(bob, spender), unrelatedAllowance);
        assertEq(token.allowance(bob, otherSpender), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), approved - amount);
        assertEq(token.allowance(alice, otherSpender), unrelatedAllowance);
        assertEq(token.allowance(bob, spender), unrelatedAllowance);
        assertEq(token.allowance(bob, otherSpender), 0);
        assertEq(token.balanceOf(alice), SUPPLY / 2 - amount);
        assertEq(token.balanceOf(bob), SUPPLY / 2 + amount);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.totalSupply(), SUPPLY);

        // Returning the tokens cannot restore the authorization that was spent.
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.allowance(alice, spender), approved - amount);
        assertEq(token.allowance(alice, otherSpender), unrelatedAllowance);
        assertEq(token.allowance(bob, spender), unrelatedAllowance);
        assertEq(token.balanceOf(alice), SUPPLY / 2);
        assertEq(token.balanceOf(bob), SUPPLY / 2);
    }

    function testFuzz_delegatedRoundTripRestoresBalancesButNotAllowances(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        token.transfer(alice, SUPPLY);
        vm.prank(alice);
        token.approve(spender, amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        vm.prank(bob);
        token.approve(spender, amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(bob, alice, amount));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function testFuzz_splitDelegatedSpendingMatchesSingleSpend(
        uint256 rawTotal,
        uint256 rawFirst,
        uint256 rawAllowance,
        bool unlimited
    ) public {
        uint256 total = bound(rawTotal, 0, SUPPLY);
        uint256 first = bound(rawFirst, 0, total);
        uint256 approved = unlimited ? type(uint256).max : bound(rawAllowance, total, type(uint256).max - 1);
        CoinbaseToken single = new CoinbaseToken();
        token.approve(spender, approved);
        single.approve(spender, approved);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, total - first));
        vm.prank(spender);
        assertTrue(single.transferFrom(address(this), alice, total));

        assertEq(token.balanceOf(alice), total);
        assertEq(token.balanceOf(address(this)), SUPPLY - total);
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), unlimited ? type(uint256).max : approved - total);
        assertEq(token.allowance(address(this), spender), single.allowance(address(this), spender));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }
}
