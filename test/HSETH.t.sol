// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "../src/HSETH.sol";

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract HSETHTest is Test {
    address admin;
    address manager;
    HSETH hsETH;

    function setUp() public {
        admin = vm.addr(100);
        manager = vm.addr(101);

        HSETH hsETHImpl = new HSETH();
        ProxyAdmin proxyAdmin = new ProxyAdmin();

        TransparentUpgradeableProxy hsETHProxy =
            new TransparentUpgradeableProxy(address(hsETHImpl), address(proxyAdmin), "");

        hsETH = HSETH(address(hsETHProxy));
        hsETH.initialize(admin);
        vm.startPrank(admin);
        hsETH.grantRole(hsETH.MANAGER(), manager);
        vm.stopPrank();
    }

    function test_initializeWithZeroAddress() external {
        HSETH hsETH2;
        HSETH hsETHImpl = new HSETH();
        ProxyAdmin proxyAdmin = new ProxyAdmin();

        TransparentUpgradeableProxy hsETHProxy =
            new TransparentUpgradeableProxy(address(hsETHImpl), address(proxyAdmin), "");

        hsETH2 = HSETH(address(hsETHProxy));
        vm.expectRevert(HSETH.ZeroAddress.selector);
        hsETH2.initialize(address(0));
    }

    function test_initialize() external {
        assertEq(hsETH.hasRole(hsETH.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(hsETH.paused(), false);
    }

    function testFail_mintWithoutRole(uint64 randomSeed, uint64 amount) external {
        vm.assume(randomSeed > 0);
        address receiver = vm.addr(randomSeed);
        vm.prank(receiver);
        hsETH.mint(receiver, amount);
    }

    function test_mint(uint64 randomSeed, uint64 amount) external {
        vm.assume(randomSeed > 0);
        address receiver = vm.addr(randomSeed);
        vm.startPrank(admin);
        hsETH.grantRole(hsETH.MINTER_ROLE(), receiver);
        vm.stopPrank();
        vm.prank(receiver);
        hsETH.mint(receiver, amount);
        assertEq(hsETH.totalSupply(), amount);
        assertEq(hsETH.balanceOf(receiver), amount);
    }

    function test_mintWithPause(uint64 randomSeed, uint64 amount) external {
        vm.assume(randomSeed > 0);
        address receiver = vm.addr(randomSeed);
        vm.startPrank(admin);
        hsETH.grantRole(hsETH.MINTER_ROLE(), receiver);
        vm.stopPrank();
        vm.prank(manager);
        hsETH.pause();
        vm.startPrank(receiver);
        vm.expectRevert("Pausable: paused");
        hsETH.mint(receiver, amount);
        vm.stopPrank();
        vm.prank(admin);
        hsETH.unpause();
        vm.prank(receiver);
        hsETH.mint(receiver, amount);
        assertEq(hsETH.totalSupply(), amount);
        assertEq(hsETH.balanceOf(receiver), amount);
    }

    function test_Burn(uint64 randomSeed, uint64 tokenAmount, uint64 burnAmount) external {
        vm.assume(randomSeed > 0);
        vm.assume(burnAmount < tokenAmount);
        address sender = vm.addr(randomSeed);
        vm.startPrank(admin);
        hsETH.grantRole(hsETH.BURNER_ROLE(), sender);
        hsETH.grantRole(hsETH.MINTER_ROLE(), sender);
        vm.stopPrank();
        vm.startPrank(sender);
        hsETH.mint(sender, tokenAmount);
        hsETH.burnFrom(sender, burnAmount);
        assertEq(hsETH.totalSupply(), tokenAmount - burnAmount);
        assertEq(hsETH.balanceOf(sender), tokenAmount - burnAmount);
    }

    function testFail_burnMoreThanBalance(uint64 randomSeed, uint64 tokenAmount, uint64 burnAmount) external {
        vm.assume(randomSeed > 0 && burnAmount > 0);
        vm.assume(burnAmount > tokenAmount);
        address sender = vm.addr(randomSeed);
        vm.startPrank(admin);
        hsETH.grantRole(hsETH.BURNER_ROLE(), sender);
        hsETH.grantRole(hsETH.MINTER_ROLE(), sender);
        vm.stopPrank();
        vm.startPrank(sender);
        hsETH.mint(sender, tokenAmount);
        hsETH.burnFrom(sender, burnAmount);
    }

    function testFail_BurnWhenPaused(uint64 randomSeed, uint64 tokenAmount, uint64 burnAmount) external {
        vm.assume(randomSeed > 0 && burnAmount > 0);
        vm.assume(burnAmount > tokenAmount);
        address sender = vm.addr(randomSeed);
        vm.startPrank(admin);
        hsETH.grantRole(hsETH.BURNER_ROLE(), sender);
        hsETH.grantRole(hsETH.MINTER_ROLE(), sender);
        vm.stopPrank();
        vm.prank(sender);
        hsETH.mint(sender, tokenAmount);
        vm.prank(manager);
        hsETH.pause();
        vm.prank(sender);
        hsETH.burnFrom(sender, burnAmount);
    }
}
