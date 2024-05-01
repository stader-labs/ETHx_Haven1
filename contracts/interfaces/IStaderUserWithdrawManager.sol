// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.16;

interface IStaderUserWithdrawManager {
    function requestWithdraw(
        uint256 _ethXAmount,
        address receiver,
        string calldata referralId
    )
        external
        returns (uint256);
}
