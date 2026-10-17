// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
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
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
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
}

contract CoinbaseTokenInvariantTest is Test {
    CoinbaseToken internal token;
    TokenHandler internal handler;
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function setUp() public {
        token = new CoinbaseToken();
        handler = new TokenHandler(token);
        token.transfer(handler.actors(0), SUPPLY);

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
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
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
    }
}
