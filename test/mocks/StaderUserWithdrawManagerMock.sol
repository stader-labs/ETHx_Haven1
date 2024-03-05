// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "./ETHxMock.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract StaderUserWithdrawManagerMock {
    ETHxMock ethX;

    using SafeERC20Upgradeable for IERC20Upgradeable;

    constructor(address _ethX) {
        ethX = ETHxMock(_ethX);
    }

    function requestWithdraw(uint256 _ethXAmount, address, string calldata) external returns (uint256) {
        IERC20Upgradeable(ethX).safeTransferFrom(msg.sender, (address(this)), _ethXAmount);
        return 1;
    }
}
