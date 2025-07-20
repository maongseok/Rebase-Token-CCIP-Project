// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestRebaseToken is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    /* you can user owner = address(this) and remove the vm.startprank in setUp
    you can also do vm.startBrodcast in setUp and get owner = the deffault address of foundry in Base.sol */
    address public user = makeAddr("user");

    uint256 constant SEND_VALUE = type(uint96).max;
    uint256 constant STARTING_BALANCE = type(uint96).max;

    function setUp() public {
        vm.startPrank(owner);
        vm.deal(owner, STARTING_BALANCE);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        // (bool success,) = payable(address(vault)).call{value: SEND_VALUE}("");
        // require(success, "txn failed");
        vm.stopPrank();
    }

    // revise
    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
        require(success, "txn failed");
    }
    // fuzz

    function testDepositLinear(uint256 amount) public {
        //this will revert
        //vm.assume(amount > 1e5);
        //modifiy amount to be between this bounds
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        // 2. check our rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("startBalance", startBalance);
        assertEq(startBalance, amount);
        // 3. warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startBalance);
        // 4. warp the time again by the same amount and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);

        // revise
        // this to handle the smaller up down due the /
        assertApproxEqAbs(middleBalance - startBalance, endBalance - middleBalance, 1);

        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        // arrange
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, amount);
        uint256 userBalanceBeforeDeposit = address(user).balance;
        vault.deposit{value: amount}();
        uint256 userBalanceAfterDeposit = address(user).balance;
        uint256 userBalanceOfRTDeposited = rebaseToken.balanceOf(user);
        // act
        vault.redeem(type(uint256).max);
        uint256 userBalanceAfterRedeem = address(user).balance;
        uint256 userBalanceOfRTAfterRedeem = rebaseToken.balanceOf(user);
        vm.stopPrank();

        // assert
        assertEq(userBalanceBeforeDeposit, amount);
        assertEq(userBalanceAfterDeposit, 0);
        assertEq(userBalanceAfterRedeem, amount);

        assertEq(userBalanceOfRTDeposited, amount);
        assertEq(userBalanceOfRTAfterRedeem, 0);
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        // arrange
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);
        time = bound(time, 1000, type(uint96).max); // in s
        console.log("vault Balance", address(vault).balance);

        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();
        uint256 userBalanceOfRTDeposited = rebaseToken.balanceOf(user);

        vm.warp(block.timestamp + time);
        uint256 userBalanceOfRTAfterTime = rebaseToken.balanceOf(user);

        vm.deal(owner, userBalanceOfRTAfterTime - depositAmount);
        vm.prank(owner);
        addRewardsToVault(userBalanceOfRTAfterTime - depositAmount);

        console.log("User Balance Plus interest", userBalanceOfRTAfterTime);
        console.log("vault Balance", address(vault).balance);

        // act
        vm.prank(user);
        vault.redeem(type(uint256).max);
        uint256 userBalanceOfRTAfterRedeem = rebaseToken.balanceOf(user);

        // assert
        uint256 interest = userBalanceOfRTAfterTime - userBalanceOfRTDeposited;
        assertEq(address(user).balance, depositAmount + interest);
        assertEq(address(user).balance, userBalanceOfRTAfterTime);
        assertEq(userBalanceOfRTAfterRedeem, 0);
    }

    function testPartialTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 2e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 user2BalanceOfRTBeforeTransfer = rebaseToken.balanceOf(user2);
        uint256 userBalanceOfRTBeforeTransfer = rebaseToken.balanceOf(user);
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);

        // owner reduce intrest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);

        uint256 user2BalanceOfRTAfterTransfer = rebaseToken.balanceOf(user2);
        uint256 userBalanceOfRTAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2InterestRate = rebaseToken.getUserInterestRate(user2);

        assertEq(user2BalanceOfRTBeforeTransfer, 0);
        assertEq(userBalanceOfRTBeforeTransfer, amount);
        assertEq(user2BalanceOfRTAfterTransfer, amountToSend);
        assertEq(userBalanceOfRTAfterTransfer, amount - amountToSend);

        //check interest rate inherited
        assertEq(userInterestRate, user2InterestRate);
        assertEq(user2InterestRate, 5e10);
    }

    function testCannotSetInterestRateIfNotOwner(uint256 newInterestRate) public {
        vm.prank(user);
        // revise what the bytes4 stand for
        // vm.expectPartialRevert(bytes4(Ownable.OwnableUnauthorizedAccount.selector));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testCannotCallBurn(uint256 amount) public {
        vm.prank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.burn(user, amount);
    }

    function testCannotCallMint(uint256 amount) public {
        bytes32 mintAndBurnRole = rebaseToken.getMintAndBurnRole();
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, mintAndBurnRole)
        );
        //vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.mint(user, amount, userInterestRate);
    }

    function testCannotCallMintAndBurn() public {
        bytes32 mintAndBurnRole = rebaseToken.getMintAndBurnRole();
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        // revise the problem i guess the problem from user being address 0 o
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, mintAndBurnRole)
        );
        // vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        vm.prank(user);
        rebaseToken.mint(user, 100, userInterestRate);

        vm.prank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.burn(user, 100);
    }

    function testGetPrincipleAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        vm.warp(block.timestamp + 1 hours);
        uint256 userPrincipleBalance = rebaseToken.principleBalanceOf(user);
        assertEq(userPrincipleBalance, amount);
    }

    function testGetRebaseTokenAddress() public view {
        address rebaseTokenAddress = vault.getRebaseTokenAddress();
        address expectedRebaseTokenAddress = address(rebaseToken);
        assertEq(rebaseTokenAddress, expectedRebaseTokenAddress);
    }
    //revise this how test the getter function with interest rate decreasing

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate =
            bound(newInterestRate, initialInterestRate, /*+1 if in the function > without the =*/ type(uint96).max);
        vm.expectRevert(
            abi.encodeWithSelector(RebaseToken.RebaseToken__interestRateCanOnlyDecrease.selector, 5e10, newInterestRate)
        );
        vm.prank(owner);
        rebaseToken.setInterestRate(newInterestRate);

        assertEq(initialInterestRate, 5e10);
    }

    function testSetInterestRate(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, 0, initialInterestRate - 1);

        // check if the interestRate has been updated
        vm.prank(owner);
        rebaseToken.setInterestRate(newInterestRate);
        uint256 updatedInterestRate = rebaseToken.getInterestRate();
        assertEq(newInterestRate, updatedInterestRate);

        // check if someone deposited this will be there new interest rate

        vm.prank(user);
        vm.deal(user, STARTING_BALANCE);
        vault.deposit{value: SEND_VALUE}();
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        assertEq(userInterestRate, newInterestRate);
    }

    function testCannotWithdrawMoreThanBalance() public {
        vm.startPrank(user);
        vm.deal(user, STARTING_BALANCE);
        vault.deposit{value: SEND_VALUE}();
        vm.expectRevert();
        vault.redeem(SEND_VALUE + 1);
        vm.stopPrank();
    }

    // revise already tested in hybrid test so it won't up the coverage
    function testGetInterestRate() public view {
        uint256 interestRate = rebaseToken.getInterestRate();
        uint256 expectedInterestRate = 5e10;
        assertEq(interestRate, expectedInterestRate);
    }

    function testGetUserInterestRate() public {
        vm.startPrank(user);
        vm.deal(user, STARTING_BALANCE);
        vault.deposit{value: SEND_VALUE}();
        uint256 interestRate = rebaseToken.getUserInterestRate(user);
        uint256 expectedInterestRate = 5e10;
        assertEq(interestRate, expectedInterestRate);
    }

    function testGetMintAndBurnRole() public view {
        bytes32 mintAndBurnRole = rebaseToken.getMintAndBurnRole();
        bytes32 expectedMintAndBurnRole = keccak256("MINT_AND_BURN_ROLE");
        assertEq(mintAndBurnRole, expectedMintAndBurnRole);
    }

    function testBalanceOf(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.deal(user, amount);
        vm.startPrank(user);
        vault.deposit{value: amount}();
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        uint256 time = 3600 seconds;
        vm.warp(block.timestamp + time);
        uint256 interestAmount = (amount * userInterestRate * time) / 1e18;

        uint256 userNewBalance = rebaseToken.balanceOf(user);
        vm.stopPrank();

        assertGt(userNewBalance, amount);
        assertEq(userNewBalance, amount + interestAmount);
    }

    function testTransferFrom(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 2e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);
        address user2 = makeAddr("user2");

        vm.deal(user, amount);
        vm.startPrank(user);
        vault.deposit{value: amount}();
        IERC20(rebaseToken).approve(user2, amountToSend);
        vm.stopPrank();

        uint256 user2BalanceOfRTBeforeTransfer = rebaseToken.balanceOf(user2);
        uint256 userBalanceOfRTBeforeTransfer = rebaseToken.balanceOf(user);
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);

        // owner reduce intrest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        vm.prank(user2);
        rebaseToken.transferFrom(user, user2, amountToSend);

        uint256 user2BalanceOfRTAfterTransfer = rebaseToken.balanceOf(user2);
        uint256 userBalanceOfRTAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2InterestRate = rebaseToken.getUserInterestRate(user2);

        assertEq(user2BalanceOfRTBeforeTransfer, 0);
        assertEq(userBalanceOfRTBeforeTransfer, amount);
        assertEq(user2BalanceOfRTAfterTransfer, amountToSend);
        assertEq(userBalanceOfRTAfterTransfer, amount - amountToSend);

        //check interest rate inherited
        assertEq(userInterestRate, user2InterestRate);
        assertEq(user2InterestRate, 5e10);
    }
}
// fuzz
// revise
// above search for the comment to org later

// we can still work on the type(unit256).max will get the full balance but it checked and the coverage is 95.92% i guess we can go
