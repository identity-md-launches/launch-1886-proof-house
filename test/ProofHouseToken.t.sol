// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ProofHouseToken} from "../src/ProofHouseToken.sol";

/// @dev A local deployment probe; no address from this fixture is used by production code.
contract TokenFactoryProbe {
    function deploy(bytes32 salt) external returns (ProofHouseToken) {
        return new ProofHouseToken{salt: salt}();
    }

    function move(ProofHouseToken token, address to, uint256 amount) external {
        require(token.transfer(to, amount), "transfer failed");
    }
}

contract RejectingRecipient {
    fallback() external {
        revert("recipient must not be called");
    }
}

/// forge-config: default.fuzz.runs = 1000
contract ProofHouseTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    ProofHouseToken internal token;
    address internal alice;
    address internal bob;
    address internal spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new ProofHouseToken();
    }

    function testMetadataAndInitialSupply() public view {
        assertEq(token.name(), "Proof House");
        assertEq(token.symbol(), "ARTIFACTS");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function testConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        ProofHouseToken fresh = new ProofHouseToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function testDirectDeploymentMintsToCaller() public {
        vm.prank(alice);
        ProofHouseToken fresh = new ProofHouseToken();
        assertEq(fresh.balanceOf(alice), SUPPLY);
        assertEq(fresh.balanceOf(address(this)), 0);
    }

    function testFactoryDeploymentAndLaunchTransfersAreExact() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        vm.prank(alice);
        ProofHouseToken fresh = factory.deploy(keccak256("launch"));
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.balanceOf(alice), 0);
        assertEq(fresh.balanceOf(address(this)), 0);

        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool");
        uint256 swarm = SUPPLY / 10;
        uint256 liquidity = SUPPLY * 8 / 10;
        factory.move(fresh, distributor, swarm);
        factory.move(fresh, pool, liquidity);
        factory.move(fresh, alice, SUPPLY - swarm - liquidity);
        assertEq(fresh.balanceOf(address(factory)), 0);
        assertEq(fresh.balanceOf(distributor), swarm);
        assertEq(fresh.balanceOf(pool), liquidity);
        assertEq(fresh.balanceOf(alice), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(fresh.transfer(bob, swarm));
        assertEq(fresh.balanceOf(distributor), 0);
        assertEq(fresh.balanceOf(bob), swarm);
        // Exercise pool-to-trader and trader-to-pool token movements with no exemptions.
        vm.prank(pool);
        assertTrue(fresh.transfer(spender, 17 ether));
        vm.prank(spender);
        assertTrue(fresh.transfer(pool, 17 ether));
        assertEq(fresh.balanceOf(spender), 0);
        assertEq(fresh.balanceOf(pool), liquidity);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function testTransferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 123 ether);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testEntireSupplyCanMoveAndReturn() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testSelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferDoesNotCallRecipient() public {
        RejectingRecipient recipient = new RejectingRecipient();
        assertTrue(token.transfer(address(recipient), 1 ether));
        assertEq(token.balanceOf(address(recipient)), 1 ether);
    }

    function testRevertTransferToZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testRevertZeroTransferToZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function testRevertTransferAboveBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testRevertTransferFromEmptyAccount() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function testApprovalEmitsEventAndIsIsolated() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 42 ether);
        assertTrue(token.approve(spender, 42 ether));
        assertEq(token.allowance(address(this), spender), 42 ether);
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testApprovalCanBeReplacedAndRevoked() public {
        assertTrue(token.approve(spender, 42 ether));
        assertTrue(token.approve(spender, 7 ether));
        assertEq(token.allowance(address(this), spender), 7 ether);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testApprovalDoesNotRequireBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
    }

    function testRevertApprovalToZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function testTransferFromSpendsFiniteAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(spender, 100 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 40 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 40 ether);
        assertEq(token.balanceOf(alice), 40 ether);
        assertEq(token.allowance(address(this), spender), 60 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testExactAllowanceIsExhausted() public {
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function testUnlimitedAllowanceRemainsUnchanged() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 5 ether));
        assertTrue(token.transferFrom(address(this), bob, 6 ether));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.balanceOf(bob), 6 ether);
    }

    function testMaxMinusOneAllowanceIsFiniteAndCanReplaceUnlimitedApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function testOwnerUsingTransferFromStillNeedsAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
    }

    function testIndependentSpendersCannotReuseExhaustedAllowance() public {
        assertTrue(token.approve(spender, 3));
        assertTrue(token.approve(bob, 5));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 3));
        assertEq(token.allowance(address(this), bob), 5);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), alice, 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), alice, 5));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.balanceOf(alice), 8);
        assertEq(token.balanceOf(address(this)), SUPPLY - 8);
    }

    function testDelegatedEntireSupplyRoundTripExhaustsAllowances() public {
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);

        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, address(this), SUPPLY));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testMaximumTransferFromWithUnlimitedApprovalRevertsWithoutChangingState() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testSelfTransferFromConsumesAllowanceWithoutChangingBalance() public {
        assertTrue(token.approve(spender, 10 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 4 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 6 ether);
    }

    function testZeroTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), 0);
    }

    function testRevertTransferFromWithWrongSpender() public {
        assertTrue(token.approve(spender, 1 ether));
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1 ether));
        token.transferFrom(address(this), alice, 1 ether);
        assertEq(token.allowance(address(this), spender), 1 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testRevertTransferFromAboveAllowance() public {
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 1, 2));
        token.transferFrom(address(this), alice, 2);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(alice), 0);
    }

    function testRevertTransferFromAboveBalanceRestoresAllowance() public {
        assertTrue(token.approve(spender, SUPPLY + 1));
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transferFrom(address(this), alice, SUPPLY + 1);
        assertEq(token.allowance(address(this), spender), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testRevertTransferFromToZeroRestoresAllowance() public {
        assertTrue(token.approve(spender, 7));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), 7);
        assertEq(token.allowance(address(this), spender), 7);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testRevertTransferFromZeroSender() public {
        // OpenZeppelin validates the allowance owner before attempting the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
    }

    function testDeployerCannotTakeHolderTokens() public {
        assertTrue(token.transfer(alice, 100 ether));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1 ether)
        );
        token.transferFrom(alice, address(this), 1 ether);
        assertEq(token.balanceOf(alice), 100 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function testNoMintBurnOrAdministrativeEntryPoints() public {
        bytes[] memory calls = new bytes[](14);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", alice, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[7] = abi.encodeWithSignature("freeze(address)", alice);
        calls[8] = abi.encodeWithSignature("seize(address)", alice);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", alice);
        calls[10] = abi.encodeWithSignature("upgradeTo(address)", alice);
        calls[11] = abi.encodeWithSignature("initialize(address)", alice);
        calls[12] = abi.encodeWithSignature("setMinter(address)", alice);
        calls[13] = abi.encodeWithSignature("owner()");
        assertTrue(token.transfer(alice, 100 ether));
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSuccess,) = address(token).call(calls[i]);
            assertFalse(deployerSuccess);
            vm.prank(bob);
            (bool outsiderSuccess,) = address(token).call(calls[i]);
            assertFalse(outsiderSuccess);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 100 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
    }

    function testRuntimeHasNoForbiddenOpcodesOrOversizedCode() public view {
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

    function testRejectsNativeCurrency() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransfersConserveSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzSelfTransfersPreserveSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferFromAccounting(uint256 approved, uint256 spent) public {
        spent = bound(spent, 0, SUPPLY);
        approved = bound(approved, spent, type(uint256).max);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, spent));
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.balanceOf(alice), spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferAboveBalanceIsAtomic(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzInsufficientAllowanceIsAtomic(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY - 1);
        amount = bound(amount, approved + 1, SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
        );
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzzFailedDelegatedSpendCanBeRetriedAfterFunding(uint256 funded, uint256 requested, uint256 approved)
        public
    {
        funded = bound(funded, 0, SUPPLY - 1);
        requested = bound(requested, funded + 1, SUPPLY);
        approved = bound(approved, requested, type(uint256).max);
        assertTrue(token.transfer(alice, funded));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, funded, requested)
        );
        token.transferFrom(alice, bob, requested);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), funded);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - funded);
        assertEq(token.totalSupply(), SUPPLY);

        // The rejected spend must leave the original approval usable, including when
        // an empty account approved tokens before it ever received them.
        assertTrue(token.transfer(alice, requested - funded));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, requested));
        assertEq(token.allowance(alice, spender), approved == type(uint256).max ? approved : approved - requested);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), requested);
        assertEq(token.balanceOf(address(this)), SUPPLY - requested);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzInvalidDelegatedRecipientRestoresAllowance(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzNonzeroRecipientsReceiveExactAmount(address recipient, uint256 amount) public {
        // Map the two excluded recipients into the valid domain without discarding a run.
        if (recipient == address(0) || recipient == address(this)) recipient = alice;
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
