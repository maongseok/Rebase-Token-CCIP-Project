// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author MDS
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault and gain interest in rewards
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate that is the global interest rate at the time of depositing
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    /*ERRORS*/
    error RebaseToken__interestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    /*STATE VARIABLES*/
    uint256 private constant PRECISION_FACTOR = 1e18;
    // revise access control 1
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE"); // to create our byte 32 role
    uint256 private s_interestRate = 5e10; // = (5 * PRECISION_FACTOR) / 1e8; // 5e17 for 50% = 0.5 * 1e18 = 5e17

    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    /*EVENTS*/
    event InterestRateSet(uint256 indexed newInterestRate);

    constructor() ERC20("RebaseToken", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account)
        external
        onlyOwner /* this give us the avoid super admin by making only owner to grant this role*/
    {
        // revise access control 2
        _grantRole(MINT_AND_BURN_ROLE, _account); // the internal one cause it has the logic
    }
    /**
     * @notice Set the interest rate in the contract
     * @param _newInterestRate The new interest rate to set
     * @dev the interest rate can only decrease
     */

    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // cei
        // Set the interest rate
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__interestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Get principle balance of a user. This is the number of tokens that have currently been minted to the user, not including any interest that has accrued since the last time the user interacted with the protocol.
     * @param _user The user to get principle Balance for
     * @return The principle balance of the user
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint the user tokens when they deposit into the vault
     * @param _to The user to mint the tokens to
     * @param _amount the amount of tokens to mint
     */
    // revise since it set interest rate to sender interest rate it may senderinterestRate be better
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        // revise access control 3 final step
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the user tokens when they withdraw from the vault
     * @param _from The user to burn amount from
     * @param _amount The amount of tokens to burn
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice calculate the balance for the user including the interest that has accumulated since the last update
     * (principle balance) + some interest
     * @param _user The user to calculate balance for
     * @return The balance of the user including the interest that has accumulated since the last update
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the principle balance of the user (the number of tokens that have actually been minted to the user)
        // multiply the principle balance by the interest that has accumulated in the time since the balance updated
        return (super.balanceOf(_user) * _calculatedUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }
    /**
     * @notice Transfer tokens from one user to another
     * @param _to The user to transfer the tokens to
     * @param _amount The amount of tokens to transfer
     * @return True if the tranfer was successful
     */

    function transfer(address _to, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_to);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        // in test stage test the senario provided to understand ln below more...
        // revise vid 6 min 7
        if (balanceOf(_to) == 0) {
            s_userInterestRate[_to] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_to, _amount);
    }

    /**
     * @notice Transfer tokens from one user to another
     * @param _from The user to transfer the tokens from
     * @param _to  The user to transfer the tokens to
     * @param _amount The amount of tokens to transfer
     * @return True if the transfer was successful
     */
    function transferFrom(address _from, address _to, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_from);
        _mintAccruedInterest(_to);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        if (balanceOf(_to) == 0) {
            s_userInterestRate[_to] = s_userInterestRate[_from];
        }
        return super.transferFrom(_from, _to, _amount);
    }

    /**
     * @notice Calculate the interest that has accumulated since the last update
     * @param _user The user to calculate the interest accumulated for
     * @return linearInterest The interest that has accumulated since the last update
     */
    function _calculatedUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // we need to calculate the interest that has accumulated since the last update
        // this is going to be linear growth with time
        // 1. calculate the time since the last update
        // 2. calculate the amount of linear growth
        // principle balance + (principle balance * user intrest rate * time elapsed)
        // principle balance(1+(user intrest rate * time elapsed))
        // deposit 10 tokens
        // interest 0.5 %
        // time elapsed 2 s
        // 10 +(10 * 0.5% * 2)
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        // PRECSION_FACTOR is 1 on 1e18 value
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    /**
     * @notice Mint the accrued interest to the user since the last time they interacted with the protocol (e.g. burn, mint, transfer)
     * @param _user The user to mint the accrued interest to
     *
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find their current balance of rebase tokens that have been minted to the user -> principle balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // (2) calculate their current balance including any interest -> balanceOf (any balance + the interest)
        uint256 currentBalance = balanceOf(_user);
        // calculate the number of tokens that need to be minted to the user -> (2) - (1)
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // set the users last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        // call _mint to mint the tokens to the user
        _mint(_user, balanceIncrease);
    }

    /*GETTERS FUNCTIONS*/

    /**
     * @notice Get the interest rate that is currently set for the contract, Any future depositors will receive this interest rate.
     * @return The present interest rate for the contract
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Get the interest rate for the user
     * @param _user The user to get the interest rate for
     * @return The interest rate for the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    function getMintAndBurnRole() external pure returns (bytes32) {
        return MINT_AND_BURN_ROLE;
    }
}

// revise       this keyword to check after the end of the project to make sure you're all set
// revise access control
