// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";

import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        (bool success, ) = payable(address(vault)).call{value: 1e18}("");
        vm.stopPrank();
    }

    function testDepositLinear(uint256 amount) public {
        vm.assume(amount > 1e4); // at least 0.00001 ETH
        amount = bound(amount, 1e4, type(uint96).max); // between 0.00001 ETH to 1 ETH
        // 1. deposit
        vm.startPrank(user);
        vm.deal(user, amount); // deposit into vault;
        // 2. check our rebase token balance
        uint256 balanceAfterDeposit = rebaseToken.balanceOf(user);
        assertEq(balanceAfterDeposit, amount);
        // 3. warp the time and check the balance again
        vm.warp(block.timestamp + 1 days);
        uint256 balanceAfterFirstWarp = rebaseToken.balanceOf(user);
        assertGt(balanceAfterFirstWarp, balanceAfterDeposit);
        // 4. warp the time again by the same amount and check the balance again
        vm.warp(block.timestamp + 1 days);
        uint256 balanceAfterSecondWarp = rebaseToken.balanceOf(user);
        assertGt(balanceAfterSecondWarp, balanceAfterFirstWarp);
    }
}
