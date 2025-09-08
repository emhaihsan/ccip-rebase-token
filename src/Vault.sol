// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    // we need to pass the token address to the constructor
    // create a deposit function that mints tokens to the user equal to the amount of ETH deposited
    // create a redeem function that burns tokens from the user and sends the user ETH
    // create a way to add rewards to the vault
    IRebaseToken private immutable i_rebaseToken;

    event Deposited(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    error Vault__RedeemFailed();

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    /**
     * @notice Deposit ETH into the vault and receive RebaseTokens
     * @dev Mints RebaseTokens to the sender equal to the amount of ETH sent
     * @dev Emits a {Deposited} event
     */
    function deposit() external payable {
        // we need to use the amount of ETH the user has sent to mint tokens to the user
        IRebaseToken(i_rebaseToken).mint(msg.sender, msg.value);
        emit Deposited(msg.sender, msg.value);
    }

    /**
     *
     * @param _amount The amount of rebase tokens to redeem for ETH from the vault
     * @dev Burns RebaseTokens from the sender and sends the sender ETH equal to the amount of tokens burned
     * @dev Emits a {Redeem} event
     */
    function redeem(uint256 _amount) external {
        // 1. burn the tokens from the user
        i_rebaseToken.burn(msg.sender, _amount);
        // 2. send the user ETH equal to the amount of tokens burned
        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        // 3. we need to make sure the transfer was successful
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    /**
     * @notice Get the address of the RebaseToken contract
     * @return The address of the RebaseToken contract
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
