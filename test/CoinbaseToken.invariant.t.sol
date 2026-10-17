// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CoinbaseToken} from "../src/CoinbaseToken.sol";

/// @dev Maintains an independent ledger while fuzzing transfers and allowance changes.
contract TokenHandler is Test {
    CoinbaseToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(CoinbaseToken token_) {
        token = token_;
        actors = [makeAddr("actor0"), makeAddr("actor1"), makeAddr("actor2"), makeAddr("actor3")];
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        uint256 available = expectedBalance[from] < approved ? expectedBalance[from] : approved;
        uint256 amount = bound(rawAmount, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
    }

    /// @dev Concentrate balances as well as split them, including emptying and refilling holders.
    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    /// @dev Reach revocation and both sides of the infinite-allowance boundary deliberately.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 mode) external {
        uint256[5] memory amounts = [uint256(0), 1, 1_000_000_000 ether, type(uint256).max - 1, type(uint256).max];
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], amounts[mode % amounts.length]);
    }

    function transferTooMuch(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        _expectFailure(
            from,
            abi.encodeCall(token.transfer, (to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function transferToZero(uint256 fromSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        _expectFailure(
            from,
            abi.encodeCall(token.transfer, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        _expectFailure(
            actors[ownerSeed % actors.length],
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function transferFromBeyondAllowance(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 rawAllowance)
        external
    {
        // Find a funded holder so allowance is the only failing precondition. There is
        // always one: all of the fixed supply stays within the four tracked actors.
        address from = _fundedActor(fromSeed);
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approved = bound(rawAllowance, 0, expectedBalance[from] - 1);
        _approve(from, spender, approved);
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (from, to, approved + 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
    }

    function transferFromBeyondBalance(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 rawAmount,
        bool unlimited
    ) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max - 1);
        _approve(from, spender, unlimited ? type(uint256).max : amount);
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (from, to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function transferFromToZero(uint256 fromSeed, uint256 spenderSeed, uint256 rawAmount, bool unlimited) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        _approve(from, spender, unlimited ? type(uint256).max : amount);
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (from, address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _fundedActor(uint256 seed) internal view returns (address) {
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[(seed % actors.length + i) % actors.length];
            if (expectedBalance[actor] > 0) return actor;
        }
        revert("no holder owns the fixed supply");
    }

    function _expectFailure(address caller, bytes memory data, bytes memory expectedError) internal {
        vm.prank(caller);
        (bool success, bytes memory reason) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(reason, expectedError, "unexpected failure reason");
        // Do not update the ghost ledger on failure. The invariants then check every
        // holder and owner/spender pair, including rollback of any allowance debit.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract CoinbaseTokenInvariantTest is Test {
    CoinbaseToken internal token;
    TokenHandler internal handler;
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function setUp() public {
        token = new CoinbaseToken();
        handler = new TokenHandler(token);
        token.transfer(handler.actors(0), SUPPLY);

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.transferAll.selector;
        selectors[4] = TokenHandler.approveBoundary.selector;
        selectors[5] = TokenHandler.transferTooMuch.selector;
        selectors[6] = TokenHandler.transferToZero.selector;
        selectors[7] = TokenHandler.approveZeroSpender.selector;
        selectors[8] = TokenHandler.transferFromBeyondAllowance.selector;
        selectors[9] = TokenHandler.transferFromBeyondBalance.selector;
        selectors[10] = TokenHandler.transferFromToZero.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyIsFixedAndAllBalancesAreAccountedFor() public view {
        uint256 accounted;
        for (uint256 i; i < 4; ++i) {
            accounted += token.balanceOf(handler.actors(i));
        }
        assertEq(accounted, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function invariant_balancesAndAllowancesMatchIndependentLedger() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner));
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }

    /// @dev Every holder must still be able to move its entire balance after a random
    /// sequence, including failed calls. The return transfer restores the ghost state.
    function afterInvariant() public {
        for (uint256 i; i < 4; ++i) {
            address from = handler.actors(i);
            address to = handler.actors((i + 1) % 4);
            uint256 amount = handler.expectedBalance(from);
            vm.prank(from);
            assertTrue(token.transfer(to, amount));
            assertEq(token.balanceOf(from), 0);
            assertEq(token.balanceOf(to), handler.expectedBalance(to) + amount);
            vm.prank(to);
            assertTrue(token.transfer(from, amount));
            invariant_balancesAndAllowancesMatchIndependentLedger();
            invariant_supplyIsFixedAndAllBalancesAreAccountedFor();
        }
    }
}
