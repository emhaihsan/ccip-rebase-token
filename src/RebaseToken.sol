// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Layout of the contract file:
// version
// imports
// errors
// interfaces, libraries, contract
// Inside Contract:
// Type declarations
// State variables
// Events
// Modifiers
// Functions
// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author Muhammad Ihsan
 * @notice This is a cross-chain rebase token that incentives users to deposit into a vault and gain interest
 * @notice The interest rate in the smart contract can only decrease and the rebase token can only decrease and the rebase
 * @notice Each will user will have their own interest rate that is the global interest rate when they deposited
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(
        uint256 oldInterestRate,
        uint256 newInterestRate
    );

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE =
        keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = 5e10; // Annual interest rate in basis points (e.g., 500 = 5%)
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("RebaseToken", "RBST") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Sets the interest rate for the rebase token
     * @param _newInterestRate The new interest rate in basis points (e.g., 500 = 5%)
     * @dev The interest rate can only decrease to prevent abuse
     */

    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // Set the interest rate
        if (_newInterestRate < s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(
                s_interestRate,
                _newInterestRate
            );
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Gets the principle balance of the user (the amount of tokens they have been minted)
     * @param _user The user to get the principle balance for
     * @return The principle balance of the user
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint the user tokens when they deposit into vault
     * @param _to The user to mint the tokens to
     * @param _amount The amount of tokens to mint
     */
    function mint(
        address _to,
        uint256 _amount
    ) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccuredInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /*
     * @notice Burn the user tokens when they withdraw from the vault
     * @param _from The user to burn the tokens from
     * @param _amount The amount of tokens to burn
     */

    function burn(
        address _from,
        uint256 _amount
    ) external onlyRole(MINT_AND_BURN_ROLE) {
        if (_amount == type(uint256).max) {
            _amount = super.balanceOf(_from);
        }
        _mintAccuredInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Calculates the balance for the user including accumulated interest for a user since their last update
     * @param _user The user to calculate the interest for
     * @return The accumulated interest multiplier (e.g., 1.05e18 for 5% interest)
     */

    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principle balance of the user (the number of tokens they have been minted to the user)
        // multiply the principle balance by the interest rate that has been accumulated in the time since balance was updated and the time since the last updated timestamp
        // return the principle balance + interest
        return
            (super.balanceOf(_user) *
                _calculateUserAccumulatedInterestSinceLastUpdate(_user)) /
            PRECISION_FACTOR;
    }

    /**
     * @notice Transfer the user tokens
     * @param _recipient The user to transfer the tokens to
     * @param _amount The amount of tokens to transfer
     * @return True if the transfer was successful
     */
    function transfer(
        address _recipient,
        uint256 _amount
    ) public override returns (bool) {
        // mint the accumulated interest for both the sender and recipient
        // this is done to ensure that the interest is correctly calculated
        // and that the interest is not lost when the tokens are transferred
        _mintAccuredInterest(msg.sender);
        _mintAccuredInterest(_recipient);

        // if the amount is set to the maximum uint256, then set it to the
        // balance of the sender
        if (_amount == type(uint256).max) {
            _amount = super.balanceOf(msg.sender);
        }

        // if the recipient has no previous balance, then set their interest rate
        // to the sender's interest rate. This is to ensure that the recipient's
        // interest rate is correctly set when the tokens are transferred.
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }

        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer the user tokens from a specific address
     * @param _sender The user to transfer the tokens from
     * @param _recipient The user to transfer the tokens to
     * @param _amount The amount of tokens to transfer
     * @return True if the transfer was successful
     */

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) public override returns (bool) {
        // mint the accumulated interest for both the sender and recipient
        // this is done to ensure that the interest is correctly calculated
        // and that the interest is not lost when the tokens are transferred
        _mintAccuredInterest(_sender);
        _mintAccuredInterest(_recipient);

        // if the amount is set to the maximum uint256, then set it to the
        // balance of the sender
        if (_amount == type(uint256).max) {
            _amount = super.balanceOf(_sender);
        }

        // if the recipient has no previous balance, then set their interest rate
        // to the sender's interest rate. This is to ensure that the recipient's
        // interest rate is correctly set when the tokens are transferred.
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }

        return super.transferFrom(_sender, _recipient, _amount);
    }

    /*
     * @notice Calculates the accumulated interest multiplier for a user since their last update
     * @param _user The user to calculate the interest for
     * @return The accumulated interest multiplier (e.g., 1.05e18 for 5% interest)
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(
        address _user
    ) internal view returns (uint256 linearInterest) {
        // we need to calculate the interest that has accumulated since the last update
        // this is going to be linear growth with time
        // 1. calculate the time since the last update
        // 2. calculate the amount of linear growth
        // principle amount (1 + ( interest rate * time elapsed))
        // deposit : 10 tokens
        // interest rate: 0.5 tokens per second
        // time elapsed is 2 seconds
        // 10 + (10 * 0.5 * 2 )
        uint256 timeElapsed = block.timestamp -
            s_userLastUpdatedTimestamp[_user];
        linearInterest = (PRECISION_FACTOR +
            (s_userInterestRate[_user] * timeElapsed));
    }

    /*
     * @notice Mints the accrued interest to the user since the last time they interacted with the protocol
     * @param _user The user to mint the interest to
     */

    function _mintAccuredInterest(address _user) internal {
        // 1. find their current balance of rebase tokens that have been minted to the user -> principle balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // 2. calculate their current balance including any interest -> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // calculate the number of tokens that need to be minted to the user -> (2) - (1)
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // mint the tokens to the user
        // set the users last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        _mint(_user, balanceIncrease);
    }

    /*
     * @notice Gets the current interest rate
     * @return The current interest rate in basis points (e.g., 500 = 5%)
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /*
     * @notice Gets the current interest rate
     * @return The current interest rate in basis points (e.g., 500 = 5%)
     */
    function getUserInterestRate(
        address _user
    ) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
