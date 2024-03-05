pragma solidity 0.8.16;

import "../src/HSETH.sol";
import "./mocks/ETHxMock.sol";
import "./mocks/StaderConfigMock.sol";
import "./mocks/StaderStakePoolManagerMock.sol";
import "./mocks/StaderUserWithdrawManagerMock.sol";
import "../src/StaderHavenStakingManager.sol";

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract StaderHavenStakingManagerTest is Test {
    uint256 public constant DECIMAL = 1e18;
    address admin;
    address manager;
    address treasury;
    HSETH hsETH;
    address ethX;
    StaderConfigMock staderConfig;
    address userWithdrawManager;
    address staderStakePoolManager;
    StaderHavenStakingManager staderHavenStakingManager;

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

        ProxyAdmin proxyAdmin = new ProxyAdmin();
        address hsETHImpl = address(new HSETH());
        address staderHavenStakingManagerImpl = address(new StaderHavenStakingManager());

        TransparentUpgradeableProxy hsETHProxy = new TransparentUpgradeableProxy(hsETHImpl, address(proxyAdmin), "");
        hsETH = HSETH(address(hsETHProxy));
        hsETH.initialize(admin);

        TransparentUpgradeableProxy staderHavenStakingManagerProxy =
            new TransparentUpgradeableProxy(staderHavenStakingManagerImpl, address(proxyAdmin), "");

        staderHavenStakingManager = StaderHavenStakingManager(address(staderHavenStakingManagerProxy));
        staderHavenStakingManager.initialize(admin, address(hsETH), treasury, address(staderConfig));
        vm.startPrank(admin);
        staderHavenStakingManager.grantRole(staderHavenStakingManager.MANAGER(), manager);
        hsETH.grantRole(hsETH.MINTER_ROLE(), address(staderHavenStakingManager));
        hsETH.grantRole(hsETH.BURNER_ROLE(), address(staderHavenStakingManager));
        vm.stopPrank();
    }

    function test_initializeWithZeroAddress() external {
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

    function test_initialize() external {
        assertEq(staderHavenStakingManager.feeInBPS(), 1000);
        assertEq(staderHavenStakingManager.DECIMAL(), 1e18);
        assertEq(staderHavenStakingManager.totalBPS(), 10_000);
        assertEq(staderHavenStakingManager.MAX_FEE_IN_BPS(), 1500);
        assertEq(staderHavenStakingManager.lastStoredETHxER(), 0);
        assertEq(staderHavenStakingManager.lastStoredProtocolFeesAmount(), 0);
        assertEq(staderHavenStakingManager.treasury(), treasury);
        assertEq(address(staderHavenStakingManager.hsETH()), address(hsETH));
        assertEq(address(staderHavenStakingManager.staderConfig()), address(staderConfig));
        assertEq(staderHavenStakingManager.hasRole(staderHavenStakingManager.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(staderHavenStakingManager.hasRole(staderHavenStakingManager.MANAGER(), manager), true);
    }

    //Starting with ETHx/ETH ER as 1:1, will increase it to see the impact on hsETH to ETH ER (should be less than
    // latest ETHx ER).
    function test_depositWithZeroInitialSupplyOfETHx(uint64 randomSeed, uint64 amount) external {
        vm.assume(randomSeed > 0);
        vm.assume(amount > 0.1 ether && amount < 100 ether);
        address user = vm.addr(randomSeed);
        vm.deal(user, 5 * uint256(amount));

        uint256 ethXER1 = StaderStakePoolManagerMock(payable(staderStakePoolManager)).getExchangeRate();
        assertEq(ETHxMock(ethX).balanceOf(address(staderHavenStakingManager)), 0);

        //depositing less than min and more than max deposit limit
        vm.prank(user);
        vm.expectRevert(IStaderHavenStakingManager.InvalidDepositAmount.selector);
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

    //Testing unstake along with withdrawing protocol fee to check if any residue ETHx token in the contract.
    //This test verifies that there is residue ETHx token in the contract which is fine as rounding is preferring
    // protocol.
    function test_requestWithdrawWithSingleUser(uint64 randomSeed, uint64 amount) external {
        vm.assume(randomSeed > 0);
        vm.assume(amount > 0.1 ether && amount < 100 ether);
        address user = vm.addr(randomSeed);
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

        vm.startPrank(manager);
        staderHavenStakingManager.maxApproveETHx();
        staderHavenStakingManager.pause();
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert("Pausable: paused");
        staderHavenStakingManager.requestWithdraw(userHsETHHolding);

        vm.prank(admin);
        staderHavenStakingManager.unpause();

        vm.startPrank(user);
        vm.expectRevert(IStaderHavenStakingManager.InvalidWithdrawAmount.selector);
        staderHavenStakingManager.requestWithdraw(1);
        staderHavenStakingManager.requestWithdraw(userHsETHHolding);
        vm.stopPrank();

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

    //Testing withdraw along with withdrawing protocol fee to check if any residue ETHx token in the contract with
    // multiple users.
    //This test verifies that there is residue ETHx token in the contract which is fine as rounding is preferring
    // protocol.
    function test_requestWithdrawWithTwoUsers(uint64 randomSeed1, uint64 randomSeed2, uint64 amount) external {
        vm.assume(randomSeed1 > 0 && randomSeed2 > 0 && randomSeed1 != randomSeed2);
        vm.assume(amount > 0.1 ether && amount < 100 ether);
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
        staderHavenStakingManager.maxApproveETHx();
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

    function test_maxApprovingEThxWithUserWithdrawManagerAsZeroAddr() external {
        vm.mockCall(
            address(staderConfig),
            abi.encodeWithSelector(StaderConfigMock.getUserWithdrawManager.selector),
            abi.encode(address(0))
        );
        vm.expectRevert();
        staderHavenStakingManager.maxApproveETHx();
        vm.prank(manager);
        vm.expectRevert(IStaderHavenStakingManager.ZeroAddress.selector);
        staderHavenStakingManager.maxApproveETHx();
    }

    function test_updateFeeInBPS(uint64 input1, uint64 input2) external {
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

    function test_updateTreasuryAddress(uint64 randomSeed) external {
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

    function test_updateHsETHToken(uint64 randomSeed) external {
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

    function test_updateStaderConfig(uint64 randomSeed) external {
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
}
