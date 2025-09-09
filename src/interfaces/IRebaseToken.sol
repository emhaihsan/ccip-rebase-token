// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IRebaseToken {
    function mint(address _to, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function balanceOf(address _user) external view returns (uint256);
}
