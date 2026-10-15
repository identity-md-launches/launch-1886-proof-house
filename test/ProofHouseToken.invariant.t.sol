// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ProofHouseToken} from "../src/ProofHouseToken.sol";

/// @dev Tracks balances and allowances independently of the token across randomized action sequences.
contract TokenHandler is Test {
    ProofHouseToken internal immutable token;
    address[4] internal actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(ProofHouseToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = 1_000_000_000 ether;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) public {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        uint256 maximum = expectedBalance[from] < approved ? expectedBalance[from] : approved;
        amount = bound(amount, 0, maximum);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        if (approved != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function overdraw(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        vm.prank(from);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, balance + 1)
        );
        token.transfer(to, balance + 1);
    }

    // Force boundaries as well as arbitrary amounts: uniform uint256 inputs rarely select
    // an exact remaining balance or the sentinel for unlimited approval.
    function transferBoundary(uint256 fromSeed, uint256 toSeed, uint256 edge) external {
        uint256 balance = expectedBalance[actors[fromSeed % actors.length]];
        transfer(fromSeed, toSeed, edge % 3 == 0 ? 0 : (edge % 3 == 1 && balance > 0 ? 1 : balance));
    }

    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 edge) external {
        uint256[5] memory amounts = [uint256(0), 1, 1_000_000_000 ether, type(uint256).max - 1, type(uint256).max];
        approve(ownerSeed, spenderSeed, amounts[edge % amounts.length]);
    }

    function transferFromBoundary(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 maximum = expectedBalance[from];
        if (expectedAllowance[from][spender] < maximum) maximum = expectedAllowance[from][spender];
        transferFrom(fromSeed, spenderSeed, toSeed, maximum);
    }

    function insufficientAllowance(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 approved) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        approved = bound(approved, 0, 1_000_000_000 ether);
        approve(fromSeed, spenderSeed, approved);
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        token.transferFrom(from, to, approved + 1);
        // The global model checks every balance and allowance after this rejected call.
    }

    function insufficientBalance(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, bool unlimited) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = balance + 1;
        approve(fromSeed, spenderSeed, unlimited ? type(uint256).max : amount);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        token.transferFrom(from, to, amount);
        // In particular, a finite allowance spent before the balance check must be restored.
    }

    function invalidReceiver(uint256 fromSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        approve(fromSeed, spenderSeed, unlimited ? type(uint256).max : amount);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(from, address(0), amount);
    }

    function invalidSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract ProofHouseTokenInvariantTest is Test {
    ProofHouseToken internal token;
    TokenHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        token = new ProofHouseToken();
        actors = [makeAddr("actor0"), makeAddr("actor1"), makeAddr("actor2"), makeAddr("actor3")];
        handler = new TokenHandler(token, actors);
        assertTrue(token.transfer(actors[0], 1_000_000_000 ether));

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.overdraw.selector;
        selectors[4] = TokenHandler.transferBoundary.selector;
        selectors[5] = TokenHandler.approveBoundary.selector;
        selectors[6] = TokenHandler.transferFromBoundary.selector;
        selectors[7] = TokenHandler.insufficientAllowance.selector;
        selectors[8] = TokenHandler.insufficientBalance.selector;
        selectors[9] = TokenHandler.invalidReceiver.selector;
        selectors[10] = TokenHandler.invalidSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariantSupplyBalancesAndAllowancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            address account = actors[i];
            uint256 balance = token.balanceOf(account);
            assertEq(balance, handler.expectedBalance(account));
            assertEq(token.allowance(account, address(0)), 0);
            sum += balance;
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(account, actors[j]), handler.expectedAllowance(account, actors[j]));
            }
        }
        assertEq(sum, 1_000_000_000 ether);
        assertEq(token.totalSupply(), sum);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.name(), "Proof House");
        assertEq(token.symbol(), "ARTIFACTS");
        assertEq(token.decimals(), 18);
    }
}
