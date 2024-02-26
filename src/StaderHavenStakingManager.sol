// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "./HSETH.sol";
import "./interfaces/IStaderConfig.sol";
import "./interfaces/IStaderStakePoolManager.sol";
import "./interfaces/IStaderUserWithdrawManager.sol";
import "./interfaces/IStaderHavenStakingManager.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @title ETHx wrapper for Haven1
 * @author Stader Labs
 * @notice The ETHx wrapper of hsETH token to interact with ETHx smart contracts
 */
contract StaderHavenStakingManager is IStaderHavenStakingManager, AccessControlUpgradeable, PausableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public constant DECIMAL = 1e18;
    //total fee in BIPS
    uint256 public constant totalFee = 10_000;
    uint256 lastStoredHsETHToETHxER;
    //store the exchange rate of hsETH to ETH
    uint256 public lastStoredETHxER;
    //store the amount of protocol fees in ETHx token
    uint256 public lastStoredProtocolFeesAmount;
    //protocol fee in BIPS
    uint256 public protocolFeeBIPS;
    //haven1 protocol treasury address for rewards
    address public treasury;

    //address of ETHx's config contract
    IStaderConfig public staderConfig;

    HSETH public hsETH;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _admin,
        address _hsETH,
        address _staderConfig
    )
        external
        initializer
        onlyNonZeroAddress(_admin)
        onlyNonZeroAddress(_hsETH)
        onlyNonZeroAddress(_staderConfig)
    {
        __Pausable_init();
        __AccessControl_init();
        hsETH = HSETH(_hsETH);
        staderConfig = IStaderConfig(_staderConfig);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice deposit ETH to receive hsETH.
     * @dev interacts with ETHx contract to mint ETHx token and then hsETH based on hsETH to ETHx ER.
     */
    function deposit() external payable {
        IStaderStakePoolManager staderStakePoolManager = IStaderStakePoolManager(staderConfig.getStakePoolManager());
        if (msg.value > staderStakePoolManager.maxDeposit() || msg.value < staderStakePoolManager.minDeposit()) {
            revert InvalidDepositAmount();
        }
        computeLatestProtocolFees();
        uint256 currentHsETHToEThxER = getLastStoredHsETHToETHxRate();
        uint256 ethXShares = staderStakePoolManager.deposit{ value: msg.value }(address(this), "Haven1");
        uint256 hsETHToMint = (ethXShares * DECIMAL) / currentHsETHToEThxER;
        hsETH.mint(msg.sender, hsETHToMint);
        emit Deposited(msg.sender, msg.value, ethXShares, hsETHToMint);
    }

    /**
     * @notice request withdraw by transferring hsETH to get back ETH
     * @dev interacts with ETHx contracts to create withdraw request by transferring ETHx token.
     * @param _hsETH amount of hsETH token to burn.
     */
    function requestWithdraw(uint256 _hsETH) external returns (uint256) {
        computeLatestProtocolFees();
        uint256 currentHsETHToEThxER = getLastStoredHsETHToETHxRate();
        uint256 ethXShareToBurn = (_hsETH * currentHsETHToEThxER) / DECIMAL;
        uint256 assets = IStaderStakePoolManager(staderConfig.getStakePoolManager()).previewWithdraw(ethXShareToBurn);
        if (assets < staderConfig.getMinWithdrawAmount() || assets > staderConfig.getMaxWithdrawAmount()) {
            revert InvalidWithdrawAmount();
        }
        hsETH.burnFrom(msg.sender, _hsETH);
        uint256 requestID = IStaderUserWithdrawManager(staderConfig.getUserWithdrawManager()).requestWithdraw(
            ethXShareToBurn, msg.sender, "Haven1"
        );
        emit WithdrawRequestReceived(msg.sender, ethXShareToBurn, _hsETH, requestID);
        return requestID;
    }

    /**
     * @notice transfers protocol reward to the treasury.
     * @dev protocol fee is stored in ETHx token amount.
     */
    function withdrawProtocolFees() external {
        computeLatestProtocolFees();
        IERC20Upgradeable(staderConfig.getETHxToken()).safeTransferFrom(
            (address(this)), treasury, lastStoredProtocolFeesAmount
        );
        emit WithdrawnProtocolFees(treasury, lastStoredProtocolFeesAmount);
        lastStoredProtocolFeesAmount = 0;
    }

    /**
     * @notice updates the ETHx exchange rate and protocol fee
     * @dev computes the protocol fee based on the change in the value of ETHx tokens(in ETH) during an interval.
     */
    function computeLatestProtocolFees() public whenNotPaused {
        uint256 currentETHxER = IStaderStakePoolManager(staderConfig.getStakePoolManager()).getExchangeRate();
        if (currentETHxER == lastStoredETHxER) {
            return;
        }
        (, uint256 increaseInETHxER) = SafeMath.trySub(currentETHxER, lastStoredETHxER);
        uint256 rewardsInETH = (
            increaseInETHxER
                * (ERC20Upgradeable(staderConfig.getETHxToken()).balanceOf(address(this)) - lastStoredProtocolFeesAmount)
        ) / DECIMAL;
        lastStoredProtocolFeesAmount += (rewardsInETH * protocolFeeBIPS * DECIMAL) / (totalFee * currentETHxER);
        lastStoredETHxER = currentETHxER;
        emit UpdatedLastStoredProtocolFeesAmount(lastStoredETHxER, lastStoredProtocolFeesAmount);
    }

    /// @notice approves ETHx token for ETHx userWithdrawalManager contract.
    function maxApproveETHx() external {
        address userWithdrawalManager = staderConfig.getUserWithdrawManager();
        if (userWithdrawalManager == address(0)) {
            revert ZeroAddress();
        }
        ERC20Upgradeable(staderConfig.getETHxToken()).approve(userWithdrawalManager, type(uint256).max);
    }

    /**
     * @dev Triggers stopped state.
     * Contract must not be paused.
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Returns to normal state.
     * Contract must be paused.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice computes the hsETH to ETHx exchange rate.
     * @dev computed based on the total hsETH supply and ETHx balance of contract minus protocol fees.
     */
    function getLastStoredHsETHToETHxRate() public view returns (uint256) {
        uint256 hsETHTotalSupply = hsETH.totalSupply();
        uint256 ethXBalance =
            (IERC20Upgradeable(staderConfig.getETHxToken()).balanceOf(address(this)) - lastStoredProtocolFeesAmount);
        uint256 newExchangeRate =
            (ethXBalance == 0 || hsETHTotalSupply == 0) ? DECIMAL : (ethXBalance * DECIMAL) / hsETHTotalSupply;
        return newExchangeRate;
    }

    ///@notice function to retrieve the latest exchange rate of hsETH / ETH
    function getLatestHsETHExchangeRate() external view returns (uint256) {
        uint256 currentETHxER = IStaderStakePoolManager(staderConfig.getStakePoolManager()).getExchangeRate();

        (, uint256 increaseInETHxER) = SafeMath.trySub(currentETHxER, lastStoredETHxER);
        uint256 rewardsInETH = (
            increaseInETHxER
                * (ERC20Upgradeable(staderConfig.getETHxToken()).balanceOf(address(this)) - lastStoredProtocolFeesAmount)
        ) / DECIMAL;
        uint256 latestProtocolFeeAmount =
            lastStoredProtocolFeesAmount + (rewardsInETH * protocolFeeBIPS * DECIMAL) / (totalFee * currentETHxER);

        uint256 hsETHTotalSupply = hsETH.totalSupply();
        uint256 ethXBalance =
            (IERC20Upgradeable(staderConfig.getETHxToken()).balanceOf(address(this)) - latestProtocolFeeAmount);
        uint256 latestHsETHToETHxER =
            (ethXBalance == 0 || hsETHTotalSupply == 0) ? DECIMAL : (ethXBalance * DECIMAL) / hsETHTotalSupply;
        return (latestHsETHToETHxER * currentETHxER) / DECIMAL;
    }

    /// @notice non-zero address modifier
    modifier onlyNonZeroAddress(address _addr) {
        if (_addr == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
