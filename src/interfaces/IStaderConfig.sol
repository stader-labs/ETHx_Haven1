// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface IStaderConfig {
    function getETHxToken() external view returns (address);

    function getStakePoolManager() external view returns (address);

    function getUserWithdrawManager() external view returns (address);

    function getMinWithdrawAmount() external view returns (uint256);

    function getMaxWithdrawAmount() external view returns (uint256);
}
