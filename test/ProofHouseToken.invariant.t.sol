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

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
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

    function transferFrom(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
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
}

contract ProofHouseTokenInvariantTest is Test {
    ProofHouseToken internal token;
    TokenHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        token = new ProofHouseToken();
        actors = [makeAddr("actor0"), makeAddr("actor1"), makeAddr("actor2"), makeAddr("actor3")];
        handler = new TokenHandler(token, actors);
        assertTrue(token.transfer(actors[0], 1_000_000_000 ether));

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.overdraw.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariantSupplyBalancesAndAllowancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            address account = actors[i];
            uint256 balance = token.balanceOf(account);
            assertEq(balance, handler.expectedBalance(account));
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
