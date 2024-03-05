// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

contract StaderConfigMock {
    address ethX;
    address staderStakePoolManager;
    address userWithdrawManager;

    function updateETHxToken(address _ethXToken) external {
        ethX = _ethXToken;
    }

    function updateStaderStakePoolManager(address _staderStakePoolManager) external {
        staderStakePoolManager = _staderStakePoolManager;
    }

    function updateUserWithdrawManager(address _userWithdrawManager) external {
        userWithdrawManager = _userWithdrawManager;
    }

    function getETHxToken() external view returns (address) {
        return ethX;
    }

    function getStakePoolManager() external view returns (address) {
        return staderStakePoolManager;
    }

    function getUserWithdrawManager() external view returns (address) {
        return userWithdrawManager;
    }

    function getMinWithdrawAmount() external pure returns (uint256) {
        return 0.1 ether;
    }

    function getMaxWithdrawAmount() external pure returns (uint256) {
        return 100 ether;
    }
}
