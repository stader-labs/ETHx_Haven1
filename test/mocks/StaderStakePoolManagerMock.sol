// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "./ETHxMock.sol";

contract StaderStakePoolManagerMock {
    error InvalidDepositAmount();

    ETHxMock ethX;
    uint256 constant DECIMAL = 1e18;

    constructor(address _ethX) {
        ethX = ETHxMock(_ethX);
    }

    function deposit(address _receiver, string calldata) external payable returns (uint256) {
        uint256 asset = msg.value;
        if (msg.value > maxDeposit() || msg.value < minDeposit()) {
            revert InvalidDepositAmount();
        }
        uint256 shareToMint = (asset * DECIMAL) / getExchangeRateInternal(asset);
        ethX.mint(_receiver, shareToMint);
        return shareToMint;
    }

    function maxDeposit() public pure returns (uint256) {
        return 100 ether;
    }

    function minDeposit() public pure returns (uint256) {
        return 0.1 ether;
    }

    function previewWithdraw(uint256 _shares) external view returns (uint256) {
        return (_shares * getExchangeRate()) / DECIMAL;
    }

    function getExchangeRateInternal(uint256 _asset) internal view returns (uint256) {
        uint256 totalETHXSupply = ethX.totalSupply();
        uint256 totalETHBalance = address(this).balance - _asset;
        uint256 newExchangeRate =
            (totalETHBalance == 0 || totalETHXSupply == 0) ? DECIMAL : (totalETHBalance * DECIMAL) / totalETHXSupply;
        return newExchangeRate;
    }

    function getExchangeRate() public view returns (uint256) {
        uint256 totalETHXSupply = ethX.totalSupply();
        uint256 totalETHBalance = address(this).balance;
        uint256 newExchangeRate =
            (totalETHBalance == 0 || totalETHXSupply == 0) ? DECIMAL : (totalETHBalance * DECIMAL) / totalETHXSupply;
        return newExchangeRate;
    }

    receive() external payable { }
}
