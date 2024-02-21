// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './HSETH.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IStaderUserWithdrawManager.sol';

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

/**
 * @title ETHx wrapper for Haven1
 * @author Stader Labs
 * @notice The ETHx wrapper of hsETH token to interact with ETHx smart contracts
 */

contract StaderHavenStakingManager is AccessControlUpgradeable, PausableUpgradeable{
        
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant DECIMAL = 1e18;
    //total fee in BIPS
    uint256 public constant totalFee = 10000;
    uint256 lastStoredHsETHToETHxER;
    //store the exchange rate of hsETH to ETH
    uint256 public lastStoredETHxER;
    //store the amount of protocol fee in ETHx token 
    uint256 public lastStoredProtocolFeeAmount;
    //protocol fee in BIPS
    uint256 public protocolFee;
    //haven1 protocol treasury address for rewards
    address public treasury;

    //address of ETHx's config contract
    IStaderConfig public staderConfig;

    HSETH public hsETH ;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _hsETH, address _staderConfig) external initializer{
            __Pausable_init();
            __AccessControl_init();
            //TODO check zero address for _admin, _hsETH and _staderConfig
            hsETH = HSETH(_hsETH);
            staderConfig = IStaderConfig(_staderConfig);
            _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    function stake() payable external {
            //TODO check of min/max deposit limit
            updateExchangeRate();
            uint256 currentHsETHToEThxER = getLastStoredHsETHToETHxRate();
            uint256 ethXShares = IStaderStakePoolManager(staderConfig.getStakePoolManager()).deposit{value: msg.value}(address(this),'Haven1');
            hsETH.mint(msg.sender, (ethXShares*DECIMAL)/currentHsETHToEThxER);
            //TODO emit event here 
    }

    function unStake(uint256 _hsETH) external returns(uint256){
            updateExchangeRate();
            uint256 currentHsETHToEThxER = getLastStoredHsETHToETHxRate();
            uint256 ethXShareToBurn = (_hsETH*currentHsETHToEThxER)/DECIMAL;
            //TODO check for min/max ETHx unstake amount
            hsETH.burnFrom(msg.sender, _hsETH);
            uint256 requestID = IStaderUserWithdrawManager(staderConfig.getUserWithdrawManager()).requestWithdraw(ethXShareToBurn,msg.sender, 'Haven1');
            //TODO emit event here 
            return requestID;
    }

    function withdrawProtocolFee() external {
            updateExchangeRate();
            IERC20Upgradeable(staderConfig.getETHxToken()).safeTransferFrom((address(this)), treasury, lastStoredProtocolFeeAmount);
            //TODO emit event here 
    }

    function updateExchangeRate() public whenNotPaused{
            uint256 currentETHxER  = IStaderStakePoolManager(staderConfig.getStakePoolManager()).getExchangeRate();
            if(currentETHxER == lastStoredETHxER){
                return;
            }
            (,uint256 increaseInETHxER) = SafeMath.trySub(currentETHxER, lastStoredETHxER);
            uint256 rewardsInETH  = (increaseInETHxER*(ERC20Upgradeable(staderConfig.getETHxToken()).balanceOf(address(this))-lastStoredProtocolFeeAmount))/DECIMAL;
            lastStoredProtocolFeeAmount += (rewardsInETH*protocolFee* DECIMAL)/(totalFee*currentETHxER);
            lastStoredETHxER = currentETHxER;
    }

    /**
     * @dev Triggers stopped state.
     * Contract must not be paused.
     */
    function pause() external {
        //TODO put a role for this (introduce PAUSER role?)
        _pause();
    }

    /**
     * @dev Returns to normal state.
     * Contract must be paused
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }


    function getLastStoredHsETHToETHxRate() public view returns(uint256) {
            uint256 hsETHTotalSupply = hsETH.totalSupply();
            uint256 ethXBalance =  (IERC20Upgradeable(staderConfig.getETHxToken()).balanceOf(address(this))- lastStoredProtocolFeeAmount);
            uint256 newExchangeRate = (ethXBalance == 0 || hsETHTotalSupply == 0)
                ? DECIMAL
                : (ethXBalance * DECIMAL) / hsETHTotalSupply;
            return newExchangeRate;
    }

    ///@notice function to retrieve the latest exchange rate of hsETH / ETH
    function getLatestHsETHExchangeRate() external view returns (uint256){
            uint256 currentETHxER  = IStaderStakePoolManager(staderConfig.getStakePoolManager()).getExchangeRate();

            (,uint256 increaseInETHxER) = SafeMath.trySub(currentETHxER, lastStoredETHxER);
            uint256 rewardsInETH  = (increaseInETHxER*(ERC20Upgradeable(staderConfig.getETHxToken()).balanceOf(address(this))-lastStoredProtocolFeeAmount))/DECIMAL;
            uint256 latestProtocolFeeAmount = lastStoredProtocolFeeAmount + (rewardsInETH*protocolFee* DECIMAL)/(totalFee*currentETHxER);
            
            uint256 hsETHTotalSupply = hsETH.totalSupply();
            uint256 ethXBalance =  (IERC20Upgradeable(staderConfig.getETHxToken()).balanceOf(address(this))- latestProtocolFeeAmount);
            uint256 latestHsETHToETHxER = (ethXBalance == 0 || hsETHTotalSupply == 0)
                ? DECIMAL
                : (ethXBalance * DECIMAL) / hsETHTotalSupply;
            return (latestHsETHToETHxER* currentETHxER)/DECIMAL;
    }
}
