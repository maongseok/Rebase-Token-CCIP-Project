// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    // we need to pass the token address to the constructor
    // create a deposit function that mints tokens to the user equal to the amount of ETH the user has sent
    // create a redeem function that burns tokens from the user and sends the user ETH
    // create a way to add rewards to the vault

    /*ERRORS*/
    error Vault__RedeemFailed();

    /*STATE VARIABLES*/
    IRebaseToken private immutable i_rebaseToken;

    /*EVENTS*/
    event Deposit(address indexed user, uint256 amount);
    event Reddem(address indexed user, uint256 amount);

    /*Constructor*/
    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    /*RECEIVE FUNCTION*/
    receive() external payable {}

    /*EXTERNAL FUNCTIONS*/

    /**
     * @notice Allows users to deposit ETH into the vault and mint rebase tokens in return
     */
    function deposit() external payable {
        i_rebaseToken.mint(msg.sender, msg.value, i_rebaseToken.getInterestRate());
        // we know mint has emit but we will need this in the bridging process
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Allows user to redeem their rebase tokens for ETH
     * @param _amount The amount of rebase tokens to redeem
     */
    function redeem(uint256 _amount) external {
        // to prevent dust problem
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        // 1. burn the token from the user
        i_rebaseToken.burn(msg.sender, _amount);
        //2. we need to sent the user ETH
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) revert Vault__RedeemFailed();
        emit Reddem(msg.sender, _amount);
    }

    /*GETTERS FUNCTIONS*/

    /**
     * @notice Get the address of the rebase token
     * @return The address of the rebase token
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
