// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/**
 * @title hsETH token Contract
 * @author Stader Labs
 * @notice The ERC20 contract for the hsETH token
 */
contract HSETH is Initializable, ERC20Upgradeable, PausableUpgradeable, AccessControlUpgradeable {
    error ZeroAddress();

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant MANAGER = keccak256("MANAGER");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin) external initializer onlyNonZeroAddress(_admin) {
        __ERC20_init("hsETH", "hsETH");
        __Pausable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice Mints hsETH when called by an authorized caller
     * @param to the account to mint to
     * @param amount the amount of hsETH to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        _mint(to, amount);
    }

    /**
     * @notice Burns hsETH when called by an authorized caller
     * @param account the account to burn from
     * @param amount the amount of hsETH to burn
     */
    function burnFrom(address account, uint256 amount) external onlyRole(BURNER_ROLE) whenNotPaused {
        _burn(account, amount);
    }

    /**
     * @dev Triggers stopped state.
     * Contract must not be paused.
     */
    function pause() external onlyRole(MANAGER) {
        _pause();
    }

    /**
     * @dev Returns to normal state.
     * Contract must be paused
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    modifier onlyNonZeroAddress(address _addr) {
        if (_addr == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
