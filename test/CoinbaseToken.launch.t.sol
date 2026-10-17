// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CoinbaseToken} from "../src/CoinbaseToken.sol";
import {TokenFactory} from "./helpers/TokenFactory.sol";

/// @dev Tests the token side of launch flows using isolated local actors.
/// This does not simulate Uniswap pricing, liquidity accounting, or swap execution.
contract CoinbaseTokenLaunchTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    CoinbaseToken internal token;
    TokenFactory internal factory;
    address internal distributor = makeAddr("distributor");
    address internal poolManager = makeAddr("poolManager");
    address internal requester = makeAddr("requester");
    address internal claimant = makeAddr("claimant");
    address internal trader = makeAddr("trader");

    function setUp() public {
        factory = new TokenFactory();
        token = factory.deploy(keccak256("token flow test"));
    }

    function test_distributionClaimsAndPoolTransfersDeliverExactAmounts() public {
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 8 / 10;
        uint256 remainder = SUPPLY - swarm - pool;

        vm.startPrank(address(factory));
        assertTrue(token.transfer(distributor, swarm));
        assertTrue(token.transfer(poolManager, pool));
        assertTrue(token.transfer(requester, remainder));
        vm.stopPrank();
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(poolManager), pool);
        assertEq(token.balanceOf(requester), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(claimant), swarm);
        assertEq(token.balanceOf(distributor), 0);

        uint256 bought = 123 ether;
        vm.prank(poolManager);
        assertTrue(token.transfer(trader, bought));
        assertEq(token.balanceOf(trader), bought);
        assertEq(token.balanceOf(poolManager), pool - bought);

        vm.prank(trader);
        assertTrue(token.transfer(poolManager, bought));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolManager), pool);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
