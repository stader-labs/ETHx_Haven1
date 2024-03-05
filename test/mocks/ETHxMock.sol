// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract ETHxMock is ERC20Upgradeable {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        _burn(account, amount);
    }
}
