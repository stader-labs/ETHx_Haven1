// SDPX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

// solhint-disable

import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import { Test, console } from "forge-std/Test.sol";

import { HSETH } from "../contracts/HSETH.sol";
import { StaderHavenStakingManager } from "../contracts/StaderHavenStakingManager.sol";
import { IStaderHavenStakingManager } from "../contracts/interfaces/IStaderHavenStakingManager.sol";
import { IStaderStakePoolManager } from "../contracts/interfaces/IStaderStakePoolManager.sol";

import { ETHxMock } from "./mocks/ETHxMock.sol";
import { StaderConfigMock } from "./mocks/StaderConfigMock.sol";
import { StaderStakePoolManagerMock } from "./mocks/StaderStakePoolManagerMock.sol";
import { StaderUserWithdrawManagerMock } from "./mocks/StaderUserWithdrawManagerMock.sol";

contract StaderHavenStakingManagerTest is Test {
    uint256 public constant DECIMAL = 1e18;

    event Upgraded(address indexed implementation);
    event WithdrawnProtocolFees(address treasury, uint256 protocolFeesAmount);

    address private admin;
    address private manager;
    address private treasury;
    ProxyAdmin private proxyAdmin;
    HSETH private hsETH;
    address private ethX;
    StaderConfigMock private staderConfig;
    address private userWithdrawManager;
    address private staderStakePoolManager;
    StaderHavenStakingManager private staderHavenStakingManager;

    function setUp() public {
        admin = vm.addr(100);
        manager = vm.addr(101);
        treasury = vm.addr(102);
        ethX = address(new ETHxMock());
        userWithdrawManager = address(new StaderUserWithdrawManagerMock(ethX));
        staderConfig = new StaderConfigMock();
        staderStakePoolManager = address(new StaderStakePoolManagerMock(ethX));

        staderConfig.updateETHxToken(ethX);
        staderConfig.updateUserWithdrawManager(userWithdrawManager);
        staderConfig.updateStaderStakePoolManager(staderStakePoolManager);

        proxyAdmin = new ProxyAdmin();
        proxyAdmin.transferOwnership(admin);
        address hsETHImpl = address(new HSETH());
        address staderHavenStakingManagerImpl = address(new StaderHavenStakingManager());

        bytes memory hsETHInitData = abi.encodeWithSelector(HSETH.initialize.selector, admin);
        TransparentUpgradeableProxy hsETHProxy =
            new TransparentUpgradeableProxy(hsETHImpl, address(proxyAdmin), hsETHInitData);
        hsETH = HSETH(address(hsETHProxy));

        bytes memory staderHavenStakingManagerInitData = abi.encodeWithSelector(
            StaderHavenStakingManager.initialize.selector, admin, address(hsETH), treasury, address(staderConfig)
        );
        TransparentUpgradeableProxy staderHavenStakingManagerProxy = new TransparentUpgradeableProxy(
            staderHavenStakingManagerImpl, address(proxyAdmin), staderHavenStakingManagerInitData
        );

        staderHavenStakingManager = StaderHavenStakingManager(address(staderHavenStakingManagerProxy));
        vm.startPrank(admin);
        staderHavenStakingManager.grantRole(staderHavenStakingManager.MANAGER(), manager);
        hsETH.grantRole(hsETH.MINTER_ROLE(), address(staderHavenStakingManager));
        hsETH.grantRole(hsETH.BURNER_ROLE(), address(staderHavenStakingManager));
        vm.stopPrank();
    }

    function testInitializeWithZeroAddress() external {
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        StaderHavenStakingManager staderHavenStakingManager2;

        address staderHavenStakingManagerImpl = address(new StaderHavenStakingManager());

        TransparentUpgradeableProxy staderHavenStakingManagerProxy =
            new TransparentUpgradeableProxy(staderHavenStakingManagerImpl, address(proxyAdmin), "");

        staderHavenStakingManager2 = StaderHavenStakingManager(address(staderHavenStakingManagerProxy));
        vm.expectRevert(IStaderHavenStakingManager.ZeroAddress.selector);
        staderHavenStakingManager2.initialize(address(0), address(hsETH), treasury, address(staderConfig));
        vm.expectRevert(IStaderHavenStakingManager.ZeroAddress.selector);
        staderHavenStakingManager2.initialize(admin, address(0), treasury, address(staderConfig));
        vm.expectRevert(IStaderHavenStakingManager.ZeroAddress.selector);
        staderHavenStakingManager2.initialize(admin, address(hsETH), address(0), address(staderConfig));
        vm.expectRevert(IStaderHavenStakingManager.ZeroAddress.selector);
        staderHavenStakingManager2.initialize(admin, address(hsETH), treasury, address(0));
    }

    function testInitialize() external {
        assertEq(staderHavenStakingManager.feeInBPS(), 1000);
        assertEq(staderHavenStakingManager.DECIMAL(), 1e18);
        assertEq(staderHavenStakingManager.totalBPS(), 10_000);
        assertEq(staderHavenStakingManager.MAX_FEE_IN_BPS(), 1500);
        assertEq(
            staderHavenStakingManager.lastStoredETHxER(),
            StaderStakePoolManagerMock(payable(staderStakePoolManager)).getExchangeRate()
        );
        assertEq(staderHavenStakingManager.lastStoredProtocolFeesAmount(), 0);
        assertEq(staderHavenStakingManager.treasury(), treasury);
        assertEq(address(staderHavenStakingManager.hsETH()), address(hsETH));
        assertEq(address(staderHavenStakingManager.staderConfig()), address(staderConfig));
        assertEq(staderHavenStakingManager.hasRole(staderHavenStakingManager.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(staderHavenStakingManager.hasRole(staderHavenStakingManager.MANAGER(), manager), true);
    }

    //Starting with ETHx/ETH ER as 1:1, will increase it to see the impact on hsETH to ETH ER (should be less than
    // latest ETHx ER).
    function testDepositWithZeroInitialSupplyOfETHx(uint64 amount) external {
        vm.assume(amount > staderConfig.getMinWithdrawAmount() && amount < 100 ether);
        address user = vm.addr(0x101);
        vm.deal(user, 5 * uint256(amount));

        uint256 ethXER1 = StaderStakePoolManagerMock(payable(staderStakePoolManager)).getExchangeRate();
        assertEq(ETHxMock(ethX).balanceOf(address(staderHavenStakingManager)), 0);

        //depositing less than min and more than max deposit limit
        vm.prank(user);
        vm.expectRevert(StaderStakePoolManagerMock.InvalidDepositAmount.selector);
        staderHavenStakingManager.deposit{ value: 1 }();

        vm.prank(manager);
        staderHavenStakingManager.pause();

        vm.prank(user);
        vm.expectRevert("Pausable: paused");
        staderHavenStakingManager.deposit{ value: amount }();

        vm.prank(admin);
        staderHavenStakingManager.unpause();
        vm.startPrank(user);
        staderHavenStakingManager.deposit{ value: amount }();

        //send ether to increase the ETHx ER
        payable(staderStakePoolManager).call{ value: 2 * uint256(amount) }("");
        uint256 ethXER2 = StaderStakePoolManagerMock(payable(staderStakePoolManager)).getExchangeRate();
        uint256 deltaETHxER = ethXER2 - ethXER1;
        uint256 rewardsInETH = (deltaETHxER * ETHxMock(ethX).balanceOf(address(staderHavenStakingManager))) / DECIMAL;
        uint256 protocolFees = (rewardsInETH * 1000 * DECIMAL) / (10_000 * ethXER2);
        staderHavenStakingManager.deposit{ value: amount }();

        vm.stopPrank();
        assertEq(staderHavenStakingManager.lastStoredProtocolFeesAmount(), protocolFees);
        assertGe(staderHavenStakingManager.lastStoredETHxER(), staderHavenStakingManager.getLatestHsETHExchangeRate());
        assertGe(hsETH.totalSupply(), ETHxMock(ethX).totalSupply());
        assertEq(ETHxMock(ethX).totalSupply(), (amount * DECIMAL) / ethXER1 + (amount * DECIMAL) / ethXER2);
        assertEq(
            ETHxMock(ethX).balanceOf(address(staderHavenStakingManager)),
            (amount * DECIMAL) / ethXER1 + (amount * DECIMAL) / ethXER2
        );
        staderHavenStakingManager.computeLatestProtocolFees();
        assertGe(
            (
                (
                    (ETHxMock(ethX).balanceOf(address(staderHavenStakingManager)))
                        - staderHavenStakingManager.lastStoredProtocolFeesAmount()
                )
            ),
            (hsETH.totalSupply() * staderHavenStakingManager.getLastStoredHsETHToETHxRate()) / DECIMAL
        );
    }

    function testDepositWithMinimumTokenRequirementNotMet() external {
        uint256 amount = 1 ether;
        address user = vm.addr(0x101);
        vm.deal(user, amount);
        vm.expectRevert(
            abi.encodeWithSelector(IStaderHavenStakingManager.MinimumHsETHNotMet.selector, amount + 1 gwei, amount)
        );
        vm.prank(user);
        staderHavenStakingManager.deposit{ value: amount }(amount + 1 gwei);
    }

    function testDepositWithMinimumTokenRequirement() external {
        uint256 amount = 1 ether;
        address user = vm.addr(0x101);
        vm.deal(user, amount);
        vm.prank(user);
        staderHavenStakingManager.deposit{ value: amount }(amount);
        assertEq(hsETH.balanceOf(user), amount);
        assertEq(hsETH.totalSupply(), amount);
    }

    //Testing unstake along with withdrawing protocol fee to check if any residue ETHx token in the contract.
    //This test verifies that there is residue ETHx token in the contract which is fine as rounding is preferring
    // protocol.
    function testRequestWithdrawWithSingleUser(uint64 amount) external {
        vm.assume(amount > staderConfig.getMinWithdrawAmount() && amount < 100 ether);
        address user = vm.addr(0x101);
        vm.deal(user, 5 * uint256(amount));

        vm.startPrank(user);
        assertEq(ETHxMock(ethX).balanceOf(address(staderHavenStakingManager)), 0);
        staderHavenStakingManager.deposit{ value: amount }();
        //send ether to increase the ETHx ER
        payable(staderStakePoolManager).call{ value: 2 * uint256(amount) }("");
        staderHavenStakingManager.deposit{ value: amount }();

        uint256 userHsETHHolding = hsETH.balanceOf(user);
        vm.expectRevert("ERC20: insufficient allowance");
        staderHavenStakingManager.requestWithdraw(userHsETHHolding);
        vm.stopPrank();

        vm.prank(manager);
        staderHavenStakingManager.approveETHxWithdraw(userHsETHHolding);

        vm.prank(user);
        staderHavenStakingManager.requestWithdraw(userHsETHHolding);

        uint256 protocolFee = staderHavenStakingManager.lastStoredProtocolFeesAmount();
        vm.prank(manager);
        staderHavenStakingManager.withdrawProtocolFees();

        assertEq(ETHxMock(ethX).balanceOf(treasury), protocolFee);
        assertEq(hsETH.totalSupply(), 0);
        assertEq(staderHavenStakingManager.lastStoredProtocolFeesAmount(), 0);
        assertApproxEqAbs(ETHxMock(ethX).balanceOf(address(staderHavenStakingManager)), 0, 10);
        //increase ETHx ER to see the rewards on residue ETHx token in the contract
        payable(staderStakePoolManager).call{ value: 100 * uint256(amount) }("");
        staderHavenStakingManager.computeLatestProtocolFees();
        assertEq(staderHavenStakingManager.lastStoredProtocolFeesAmount(), 0);
    }

    function testRequestWithdrawWhenPaused() external {
        uint256 amount = 1 ether;
        address user = vm.addr(0x101);
        vm.deal(user, 5 * uint256(amount));

        vm.startPrank(user);
        assertEq(ETHxMock(ethX).balanceOf(address(staderHavenStakingManager)), 0);
        staderHavenStakingManager.deposit{ value: amount }();
        //send ether to increase the ETHx ER
        payable(staderStakePoolManager).call{ value: 2 * uint256(amount) }("");
        staderHavenStakingManager.deposit{ value: amount }();

        uint256 userHsETHHolding = hsETH.balanceOf(user);
        vm.stopPrank();

        vm.startPrank(manager);
        staderHavenStakingManager.approveETHxWithdraw(userHsETHHolding);
        staderHavenStakingManager.pause();
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert("Pausable: paused");
        staderHavenStakingManager.requestWithdraw(userHsETHHolding);
    }

    function testDepositWhenPaused() external {
        uint256 amount = 1 ether;
        address user = vm.addr(0x101);
        vm.deal(user, 5 * uint256(amount));

        vm.prank(manager);
        staderHavenStakingManager.pause();
        vm.prank(user);
        vm.expectRevert("Pausable: paused");
        staderHavenStakingManager.deposit{ value: amount }();
    }

    function testRequestWithdrawProtocolFeeEvent(uint64 amount) external {
        vm.assume(amount > staderConfig.getMinWithdrawAmount() && amount < 100 ether);
        address user = vm.addr(0x101);
        vm.deal(user, 5 * uint256(amount));

        vm.startPrank(user);
        assertEq(ETHxMock(ethX).balanceOf(address(staderHavenStakingManager)), 0);
        staderHavenStakingManager.deposit{ value: amount }();
        //send ether to increase the ETHx ER
        payable(staderStakePoolManager).call{ value: 2 * uint256(amount) }("");
        staderHavenStakingManager.deposit{ value: amount }();
        vm.stopPrank();

        uint256 userHsETHHolding = hsETH.balanceOf(user);

        vm.prank(manager);
        staderHavenStakingManager.approveETHxWithdraw(userHsETHHolding);
        vm.prank(user);
        staderHavenStakingManager.requestWithdraw(userHsETHHolding);
        uint256 protocolFee = staderHavenStakingManager.lastStoredProtocolFeesAmount();

        vm.expectEmit();
        emit WithdrawnProtocolFees(treasury, protocolFee);
        vm.prank(manager);
        staderHavenStakingManager.withdrawProtocolFees();
    }

    function testRequestWithdrawProtocolFeeWhenPaused() external {
        uint256 amount = 1 ether;
        address user = vm.addr(0x101);
        vm.deal(user, 5 * uint256(amount));

        vm.startPrank(user);
        assertEq(ETHxMock(ethX).balanceOf(address(staderHavenStakingManager)), 0);
        staderHavenStakingManager.deposit{ value: amount }();
        //send ether to increase the ETHx ER
        payable(staderStakePoolManager).call{ value: 2 * uint256(amount) }("");
        staderHavenStakingManager.deposit{ value: amount }();
        vm.stopPrank();
        vm.startPrank(manager);
        staderHavenStakingManager.pause();
        vm.expectRevert("Pausable: paused");
        staderHavenStakingManager.withdrawProtocolFees();
        vm.stopPrank();
    }

    function testRequestWithdrawWithRequiredMaximum() external {
        uint256 amount = 1 ether;
        address user = vm.addr(0x101);
        vm.deal(user, 5 * uint256(amount));

        vm.startPrank(user);
        assertEq(ETHxMock(ethX).balanceOf(address(staderHavenStakingManager)), 0);
        staderHavenStakingManager.deposit{ value: amount }();
        //send ether to increase the ETHx ER
        payable(staderStakePoolManager).call{ value: 2 * uint256(amount) }("");
        staderHavenStakingManager.deposit{ value: amount }();
        vm.stopPrank();

        uint256 userHsETHHolding = hsETH.balanceOf(user);

        vm.prank(manager);
        staderHavenStakingManager.approveETHxWithdraw(userHsETHHolding);

        vm.expectRevert(
            abi.encodeWithSelector(
                IStaderHavenStakingManager.MaximumETHxExceeded.selector,
                678_571_428_571_428_571,
                1_266_666_666_666_666_666
            )
        );
        vm.prank(user);
        staderHavenStakingManager.requestWithdraw(userHsETHHolding, userHsETHHolding / 2);
    }

    //Testing withdraw along with withdrawing protocol fee to check if any residue ETHx token in the contract with
    // multiple users.
    //This test verifies that there is residue ETHx token in the contract which is fine as rounding is preferring
    // protocol.
    function testRequestWithdrawWithTwoUsers(uint64 randomSeed1, uint64 randomSeed2, uint64 amount) external {
        vm.assume(randomSeed1 > 0 && randomSeed2 > 0 && randomSeed1 != randomSeed2);
        vm.assume(amount > staderConfig.getMinWithdrawAmount() && amount < 100 ether);
        address user = vm.addr(randomSeed1);
        address user2 = vm.addr(randomSeed2);
        vm.deal(user, 5 * uint256(amount));
        vm.deal(user2, 5 * uint256(amount));
        vm.startPrank(user);
        assertEq(ETHxMock(ethX).balanceOf(address(staderHavenStakingManager)), 0);
        staderHavenStakingManager.deposit{ value: amount }();
        //send ether to increase the ETHx ER
        payable(staderStakePoolManager).call{ value: 100 * uint256(amount) }("");
        vm.stopPrank();
        vm.startPrank(user2);
        staderHavenStakingManager.deposit{ value: amount }();
        payable(staderStakePoolManager).call{ value: 100 * uint256(amount) }("");
        staderHavenStakingManager.deposit{ value: amount }();

        uint256 user1HsETHHolding = hsETH.balanceOf(user);
        uint256 user2HsETHHolding = hsETH.balanceOf(user2);

        vm.stopPrank();
        vm.prank(manager);
        staderHavenStakingManager.approveETHxWithdraw(user1HsETHHolding + user2HsETHHolding);
        vm.prank(user);
        staderHavenStakingManager.requestWithdraw(user1HsETHHolding);
        vm.prank(user2);
        staderHavenStakingManager.requestWithdraw(user2HsETHHolding);
        vm.prank(manager);
        staderHavenStakingManager.withdrawProtocolFees();
        assertEq(hsETH.totalSupply(), 0);
        assertEq(staderHavenStakingManager.lastStoredProtocolFeesAmount(), 0);
        assertEq(ETHxMock(ethX).balanceOf(address(staderHavenStakingManager)), 0);
        //increase ETHx ER to see the rewards on residue ETHx token in the contract
        payable(staderStakePoolManager).call{ value: 100 * uint256(amount) }("");
        staderHavenStakingManager.computeLatestProtocolFees();
        assertEq(staderHavenStakingManager.lastStoredProtocolFeesAmount(), 0);
    }

    function testMaxApprovingEThxWithUserWithdrawManagerAsZeroAddr() external {
        vm.mockCall(
            address(staderConfig),
            abi.encodeWithSelector(StaderConfigMock.getUserWithdrawManager.selector),
            abi.encode(address(0))
        );
        vm.expectRevert();
        staderHavenStakingManager.approveETHxWithdraw(1 ether);
        vm.prank(manager);
        vm.expectRevert(IStaderHavenStakingManager.ZeroAddress.selector);
        staderHavenStakingManager.approveETHxWithdraw(1 ether);
    }

    function testUpdateFeeInBPS(uint64 input1, uint64 input2) external {
        vm.assume(input1 <= staderHavenStakingManager.MAX_FEE_IN_BPS());
        vm.assume(input2 > staderHavenStakingManager.MAX_FEE_IN_BPS());

        vm.expectRevert();
        staderHavenStakingManager.updateFeeInBPS(input1);
        vm.startPrank(manager);
        vm.expectRevert(IStaderHavenStakingManager.InvalidInput.selector);
        staderHavenStakingManager.updateFeeInBPS(input2);
        staderHavenStakingManager.updateFeeInBPS(input1);
        assertEq(staderHavenStakingManager.feeInBPS(), input1);
    }

    function testUpdateFeeInBPSWhenPaused() external {
        uint256 input1 = staderHavenStakingManager.MAX_FEE_IN_BPS() - 1;
        vm.startPrank(manager);
        staderHavenStakingManager.pause();
        vm.expectRevert("Pausable: paused");
        staderHavenStakingManager.updateFeeInBPS(input1);
        vm.stopPrank();
    }

    function testUpdateTreasuryAddress(uint64 randomSeed) external {
        vm.assume(randomSeed > 0);
        address treasuryAddr = vm.addr(randomSeed);

        vm.expectRevert();
        staderHavenStakingManager.updateTreasuryAddress(treasuryAddr);
        vm.startPrank(manager);
        vm.expectRevert(IStaderHavenStakingManager.ZeroAddress.selector);
        staderHavenStakingManager.updateTreasuryAddress(address(0));
        staderHavenStakingManager.updateTreasuryAddress(treasuryAddr);
        assertEq(staderHavenStakingManager.treasury(), treasuryAddr);
    }

    function testUpdateHsETHToken(uint64 randomSeed) external {
        vm.assume(randomSeed > 0);
        address hsETHTokenAddr = vm.addr(randomSeed);

        vm.expectRevert();
        staderHavenStakingManager.updateHsETHToken(hsETHTokenAddr);
        vm.startPrank(admin);
        vm.expectRevert(IStaderHavenStakingManager.ZeroAddress.selector);
        staderHavenStakingManager.updateHsETHToken(address(0));
        staderHavenStakingManager.updateHsETHToken(hsETHTokenAddr);
        assertEq(address(staderHavenStakingManager.hsETH()), hsETHTokenAddr);
    }

    function testUpdateStaderConfig(uint64 randomSeed) external {
        vm.assume(randomSeed > 0);
        address staderConfigAddr = vm.addr(randomSeed);

        vm.expectRevert();
        staderHavenStakingManager.updateStaderConfig(staderConfigAddr);
        vm.startPrank(admin);
        vm.expectRevert(IStaderHavenStakingManager.ZeroAddress.selector);
        staderHavenStakingManager.updateStaderConfig(address(0));
        staderHavenStakingManager.updateStaderConfig(staderConfigAddr);
        assertEq(address(staderHavenStakingManager.staderConfig()), staderConfigAddr);
    }

    function testProxyUpgradeWorkflow() public {
        address newImpl = address(new StaderHavenStakingManager());
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(address(staderHavenStakingManager));
        vm.prank(admin);
        vm.expectEmit();
        emit Upgraded(newImpl);
        proxyAdmin.upgrade(proxy, newImpl);
    }
}
