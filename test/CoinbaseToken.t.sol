// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CoinbaseToken} from "../src/CoinbaseToken.sol";
import {TokenFactory} from "./helpers/TokenFactory.sol";

contract CoinbaseTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    CoinbaseToken internal token;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new CoinbaseToken();
    }

    function test_metadataAndEntireSupplyBelongToDeployer() public view {
        assertEq(token.name(), "COINBASE");
        assertEq(token.symbol(), "COIN");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_constructorEmitsExactlyOneMintEvent() public {
        vm.recordLogs();
        CoinbaseToken fresh = new CoinbaseToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_create2DeploymentMintsToFactoryNotTransactionOrigin() public {
        TokenFactory factory = new TokenFactory();
        bytes32 salt = keccak256("local launch test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(CoinbaseToken).creationCode)
                        )
                    )
                )
            )
        );
        vm.prank(alice, alice);
        CoinbaseToken launched = factory.deploy(salt);
        assertEq(address(launched), predicted);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.balanceOf(address(launched)), 0);
    }

    function test_transferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 25 ether);
        assertTrue(token.transfer(alice, 25 ether));
        assertEq(token.balanceOf(alice), 25 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 25 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_entireSupplyCanMoveAndReturn() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferDoesNotChangeBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_insufficientBalanceRevertsWithoutChangingBalances() public {
        token.transfer(alice, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        vm.prank(alice);
        token.transfer(bob, 11);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumTransferCannotOverflowBalances() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_approveEmitsEventAndOverwritesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 100);
        assertTrue(token.approve(spender, 100));
        assertEq(token.allowance(address(this), spender), 100);
        assertTrue(token.approve(spender, 50));
        assertEq(token.allowance(address(this), spender), 50);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_approveZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 100);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_revocationPreventsFurtherSpending() public {
        token.approve(spender, 100);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferFromMovesExactAmountAndConsumesAllowance() public {
        token.approve(spender, 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 60);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 60));
        assertEq(token.balanceOf(alice), 60);
        assertEq(token.balanceOf(address(this)), SUPPLY - 60);
        assertEq(token.allowance(address(this), spender), 40);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_exhaustedAllowanceCannotBeReused() public {
        token.approve(spender, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 100));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 100);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.transferFrom(address(this), bob, 2));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
    }

    function test_zeroTransferFromNeedsNoPositiveAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromToSelfConsumesAllowanceWithoutChangingBalance() public {
        token.approve(spender, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 80));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 20);
    }

    function test_transferFromRequiresAllowanceEvenWhenCallerOwnsTokens() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromInsufficientAllowanceIsAtomic() public {
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 10, 11));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 11);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferFromInsufficientBalanceRestoresAllowance() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        vm.prank(spender);
        token.transferFrom(alice, bob, 11);
        assertEq(token.allowance(alice, spender), 100);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromToZeroRestoresAllowance() public {
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroSourceCannotCreateTokensThroughTransferFrom() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(0), alice, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_deployerCannotSpendHolderFundsWithoutApproval() public {
        token.transfer(alice, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 100);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_noMintBurnOrAdministrativeEntryPoints() public {
        token.transfer(alice, 100);
        bytes[] memory calls = new bytes[](26);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1);
        calls[4] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[5] = abi.encodeWithSignature("initialize(address)", bob);
        calls[6] = abi.encodeWithSignature("owner()");
        calls[7] = abi.encodeWithSignature("setOwner(address)", bob);
        calls[8] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[9] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[10] = abi.encodeWithSignature("pause()");
        calls[11] = abi.encodeWithSignature("unpause()");
        calls[12] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[13] = abi.encodeWithSignature("blocklist(address)", alice);
        calls[14] = abi.encodeWithSignature("freeze(address)", alice);
        calls[15] = abi.encodeWithSignature("freezeAccount(address)", alice);
        calls[16] = abi.encodeWithSignature("setBlacklist(address,bool)", alice, true);
        calls[17] = abi.encodeWithSignature("setBlocked(address,bool)", alice, true);
        calls[18] = abi.encodeWithSignature("lock(address)", alice);
        calls[19] = abi.encodeWithSignature("disableTransfers()");
        calls[20] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[21] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 100);
        calls[22] = abi.encodeWithSignature("seize(address)", alice);
        calls[23] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[24] = abi.encodeWithSignature("_mint(address,uint256)", bob, 1);
        calls[25] = abi.encodeWithSignature("_burn(address,uint256)", alice, 1);

        address[3] memory callers = [address(this), alice, bob];
        for (uint256 i; i < callers.length; ++i) {
            for (uint256 j; j < calls.length; ++j) {
                vm.prank(callers[i]);
                (bool ok,) = address(token).call(calls[j]);
                assertFalse(ok);
                assertEq(token.totalSupply(), SUPPLY);
                assertEq(token.balanceOf(alice), 100);
                assertEq(token.balanceOf(bob), 0);
                assertEq(token.balanceOf(address(this)), SUPPLY - 100);
            }
        }
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_unknownSelectorAndNativeEtherAreRejected() public {
        (bool unknown,) = address(token).call(hex"deadbeef");
        assertFalse(unknown);
        vm.deal(address(this), 1 ether);
        (bool payment,) = address(token).call{value: 1 ether}("");
        assertFalse(payment);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_runtimeIsDeployableAndHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }

    function testFuzz_transferPreservesSupplyAndExactBalances(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalAndDelegatedTransfer(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 approved = bound(rawAllowance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, approved);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_overspendingRevertsAndPreservesState(uint256 rawBalance, uint256 rawExcess) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 excess = bound(rawExcess, 1, type(uint256).max - balance);
        token.transfer(alice, balance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, balance + excess)
        );
        vm.prank(alice);
        token.transfer(bob, balance + excess);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_spendingBeyondAllowanceReverts(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 approved = bound(rawAllowance, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, approved + 1, SUPPLY);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
