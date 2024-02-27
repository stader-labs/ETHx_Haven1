// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface IStaderHavenStakingManager {
    error ZeroAddress();
    error InvalidInput();
    error InvalidDepositAmount();
    error InvalidWithdrawAmount();

    event UpdatedHsETHTokenAddress(address hsETH);

    event UpdatedTreasuryAddress(address treasury);

    event UpdatedProtocolFee(uint256 protocolFeeBIPS);

    event StaderConfigAddressUpdated(address staderConfig);

    event WithdrawnProtocolFees(address treasury, uint256 protocolFeesAmount);

    event UpdatedLastStoredProtocolFeesAmount(uint256 ethXExchangeRate, uint256 protocolFeesInETHx);

    event Deposited(address indexed sender, uint256 ethAmount, uint256 ethXMinted, uint256 hsETHMinted);

    event WithdrawRequestReceived(address indexed sender, uint256 ethXToBurn, uint256 hsETHBurned, uint256 requestID);
}
