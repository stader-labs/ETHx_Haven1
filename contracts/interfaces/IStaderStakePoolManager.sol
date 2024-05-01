// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface IStaderStakePoolManager {
    function deposit(address _receiver, string calldata _referralId) external payable returns (uint256);

    function getExchangeRate() external view returns (uint256);
}
