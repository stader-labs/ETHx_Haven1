// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import { HSETH } from "./HSETH.sol";
import { IStaderConfig } from "./interfaces/IStaderConfig.sol";
import { IStaderStakePoolManager } from "./interfaces/IStaderStakePoolManager.sol";
import { IStaderUserWithdrawManager } from "./interfaces/IStaderUserWithdrawManager.sol";
import { IStaderHavenStakingManager } from "./interfaces/IStaderHavenStakingManager.sol";

/**
 * @title ETHx wrapper for Haven1
 * @author Stader Labs
 * @notice The ETHx wrapper of hsETH token to interact with ETHx smart contracts
 */
contract StaderHavenStakingManager is IStaderHavenStakingManager, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant MANAGER = keccak256("MANAGER");

    uint256 public constant DECIMAL = 1e18;
    ///@notice total value of BPS.
    uint256 public constant totalBPS = 10_000;
    ///@notice maximum protocol fee value in BPS
    uint256 public constant MAX_FEE_IN_BPS = 1500;
    ///@notice last stored exchange rate of ETHx token.
    uint256 public lastStoredETHxER;
    ///@notice last stored amount of protocol fees in ETHx token.
    uint256 public lastStoredProtocolFeesAmount;
    ///@notice protocol fee in BPS.
    uint256 public feeInBPS;
    ///@notice Haven1 protocol treasury address for rewards.
    address public treasury;
    ///@notice address of ETHx's config contract.
    IStaderConfig public staderConfig;
    ///@notice address of hsETH token contract.
    HSETH public hsETH;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _admin,
        address _hsETH,
        address _treasury,
        address _staderConfig
    )
        external
        initializer
        onlyNonZeroAddress(_admin)
        onlyNonZeroAddress(_hsETH)
        onlyNonZeroAddress(_treasury)
        onlyNonZeroAddress(_staderConfig)
    {
        __Pausable_init();
        __AccessControl_init();
        feeInBPS = 1000; //10 % fee
        treasury = _treasury;
        hsETH = HSETH(_hsETH);
        staderConfig = IStaderConfig(_staderConfig);
        lastStoredETHxER = IStaderStakePoolManager(staderConfig.getStakePoolManager()).getExchangeRate();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice deposit ETH to recieve hsETH ignoring slippage
     */
    function deposit() external payable {
        deposit(0);
    }

    /**
     * @notice deposit ETH to receive hsETH.
     * @dev interacts with ETHx contract to mint ETHx token and then hsETH based on hsETH to ETHx ER.
     * @param _minimumHsETH minimum hsETH to mint considering slippage
     */
    function deposit(uint256 _minimumHsETH) public payable {
        IStaderStakePoolManager staderStakePoolManager = IStaderStakePoolManager(staderConfig.getStakePoolManager());
        computeLatestProtocolFees();
        uint256 currentHsETHToEThxER = getLastStoredHsETHToETHxRate();
        uint256 ethXShares = staderStakePoolManager.deposit{ value: msg.value }(address(this), "Haven1");
        uint256 hsETHToMint = (ethXShares * DECIMAL) / currentHsETHToEThxER;
        if (hsETHToMint < _minimumHsETH) {
            revert MinimumHsETHNotMet(_minimumHsETH, hsETHToMint);
        }
        hsETH.mint(msg.sender, hsETHToMint);
        emit Deposited(msg.sender, msg.value, ethXShares, hsETHToMint);
    }

    function requestWithdraw(uint256 _hsETH) external returns (uint256) {
        return requestWithdraw(_hsETH, type(uint256).max);
    }

    /**
     * @notice request withdraw by transferring hsETH to get back ETH.
     * @dev interacts with ETHx contracts to create withdraw request by transferring ETHx token.
     * @param _hsETH amount of hsETH token to burn.
     * @param _maximumETHxToBurn maximum ETHx to burn considering slippage.
     */
    function requestWithdraw(uint256 _hsETH, uint256 _maximumETHxToBurn) public returns (uint256) {
        computeLatestProtocolFees();
        uint256 currentHsETHToEThxER = getLastStoredHsETHToETHxRate();
        uint256 ethXShareToBurn = (_hsETH * currentHsETHToEThxER) / DECIMAL;

        if (ethXShareToBurn > _maximumETHxToBurn) {
            revert MaximumETHxExceeded(_maximumETHxToBurn, ethXShareToBurn);
        }

        hsETH.burnFrom(msg.sender, _hsETH);
        uint256 requestID = IStaderUserWithdrawManager(staderConfig.getUserWithdrawManager()).requestWithdraw(
            ethXShareToBurn, msg.sender, "Haven1"
        );
        emit WithdrawRequestReceived(msg.sender, ethXShareToBurn, _hsETH, requestID);
        return requestID;
    }

    /**
     * @notice transfers accrued protocol fees to the treasury.
     * @dev protocol fees is stored in ETHx token amount.
     */
    function withdrawProtocolFees() external onlyRole(MANAGER) {
        computeLatestProtocolFees();
        uint256 feeAmountToTransfer = lastStoredProtocolFeesAmount;
        lastStoredProtocolFeesAmount = 0;
        address ethxToken = staderConfig.getETHxToken();
        IERC20Upgradeable ethx = IERC20Upgradeable(ethxToken);
        ethx.safeTransfer(treasury, feeAmountToTransfer);
        emit WithdrawnProtocolFees(treasury, feeAmountToTransfer);
    }

    /**
     * @notice updates the ETHx exchange rate and protocol fees.
     * @dev computes the protocol fee based on the change in the value of ETHx tokens(in ETH) during an interval.
     */
    function computeLatestProtocolFees() public whenNotPaused {
        uint256 currentETHxER = IStaderStakePoolManager(staderConfig.getStakePoolManager()).getExchangeRate();
        (, uint256 increaseInETHxER) = SafeMath.trySub(currentETHxER, lastStoredETHxER);
        if (increaseInETHxER == 0) {
            return;
        }
        uint256 rewardsInETH = (
            increaseInETHxER
                * (ERC20Upgradeable(staderConfig.getETHxToken()).balanceOf(address(this)) - lastStoredProtocolFeesAmount)
        ) / DECIMAL;
        lastStoredProtocolFeesAmount += (rewardsInETH * feeInBPS * DECIMAL) / (totalBPS * currentETHxER);
        lastStoredETHxER = currentETHxER;
        emit UpdatedLastStoredProtocolFeesAmount(lastStoredETHxER, lastStoredProtocolFeesAmount);
    }

    /**
     * @notice approves ETHx token for ETHx userWithdrawalManager contract.
     * @param _maxAmount maximum amount to approve
     */
    function approveETHxWithdraw(uint256 _maxAmount) external onlyRole(MANAGER) {
        address userWithdrawalManager = staderConfig.getUserWithdrawManager();
        if (userWithdrawalManager == address(0)) {
            revert ZeroAddress();
        }
        ERC20Upgradeable(staderConfig.getETHxToken()).approve(userWithdrawalManager, _maxAmount);
    }

    /**
     * @notice updates the fees in BPS.
     * @dev only MANAGER role can call.
     * @param _feeInBPS new value of fee in BPS.
     */
    function updateFeeInBPS(uint256 _feeInBPS) external onlyRole(MANAGER) {
        if (_feeInBPS > MAX_FEE_IN_BPS) {
            revert InvalidInput();
        }
        computeLatestProtocolFees();
        feeInBPS = _feeInBPS;
        emit UpdatedFeeInBPS(feeInBPS);
    }

    /**
     * @notice updates the address of treasury.
     * @dev only MANAGER role can call.
     * @param _treasury new address of treasury.
     */
    function updateTreasuryAddress(address _treasury) external onlyNonZeroAddress(_treasury) onlyRole(MANAGER) {
        treasury = _treasury;
        emit UpdatedTreasuryAddress(treasury);
    }

    /**
     * @notice updates the address of hsETH token.
     * @dev only ADMIN role can call.
     * @param _hsETH new address of hsETH token.
     */
    function updateHsETHToken(address _hsETH) external onlyNonZeroAddress(_hsETH) onlyRole(DEFAULT_ADMIN_ROLE) {
        hsETH = HSETH(_hsETH);
        emit UpdatedHsETHTokenAddress(_hsETH);
    }

    /**
     * @notice updates the address of staderConfig contract.
     * @dev only ADMIN role can call.
     * @param _staderConfig new address of staderConfig.
     */
    function updateStaderConfig(address _staderConfig)
        external
        onlyNonZeroAddress(_staderConfig)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        staderConfig = IStaderConfig(_staderConfig);
        emit StaderConfigAddressUpdated(_staderConfig);
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

    ///@notice function to retrieve the latest exchange rate of hsETH / ETH.
    function getLatestHsETHExchangeRate() external view returns (uint256) {
        uint256 currentETHxER = IStaderStakePoolManager(staderConfig.getStakePoolManager()).getExchangeRate();

        (, uint256 increaseInETHxER) = SafeMath.trySub(currentETHxER, lastStoredETHxER);
        uint256 rewardsInETH = (
            increaseInETHxER
                * (ERC20Upgradeable(staderConfig.getETHxToken()).balanceOf(address(this)) - lastStoredProtocolFeesAmount)
        ) / DECIMAL;
        uint256 latestProtocolFeeAmount =
            lastStoredProtocolFeesAmount + (rewardsInETH * feeInBPS * DECIMAL) / (totalBPS * currentETHxER);

        uint256 hsETHTotalSupply = hsETH.totalSupply();
        uint256 ethXBalance =
            (IERC20Upgradeable(staderConfig.getETHxToken()).balanceOf(address(this)) - latestProtocolFeeAmount);
        uint256 latestHsETHToETHxER =
            (ethXBalance == 0 || hsETHTotalSupply == 0) ? DECIMAL : (ethXBalance * DECIMAL) / hsETHTotalSupply;
        return (latestHsETHToETHxER * currentETHxER) / DECIMAL;
    }

    /// @notice non-zero address modifier.
    modifier onlyNonZeroAddress(address _addr) {
        if (_addr == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
