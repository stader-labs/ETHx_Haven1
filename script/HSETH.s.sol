// SPDX-License-Identifier: UNLICENSED
// solhint-disable no-console
pragma solidity 0.8.16;

import { Script, console } from "forge-std/Script.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { HSETH } from "../contracts/HSETH.sol";

contract DeployHSETH is Script {
    event ProxyAdminCreated(address admin);
    event HsETHProxy(address proxy);
    event HsETHUpgrade(address proxy, address implementation);

    function deployAdmin() public {
        address admin = vm.envAddress("HSETH_ADMIN");
        vm.startBroadcast();
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        console.log("ProxyAdmin: ", address(proxyAdmin));
        proxyAdmin.transferOwnership(admin);
        emit ProxyAdminCreated(address(proxyAdmin));
        vm.stopBroadcast();
    }

    function proxyDeploy() public {
        address tempAdmin = msg.sender;
        // address admin = vm.envAddress("HSETH_ADMIN");
        address proxyAdmin = vm.envAddress("PROXY_ADMIN");
        vm.startBroadcast();
        HSETH implementation = new HSETH();
        bytes memory initializationCalldata = abi.encodeWithSelector(implementation.initialize.selector, tempAdmin);
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), proxyAdmin, initializationCalldata);
        console.log("hsETH Transparent Proxy: ", address(proxy));
        emit HsETHProxy(address(proxy));
        vm.stopBroadcast();
    }

    function proxyUpgrade() public {
        address proxyAdmin = vm.envAddress("PROXY_ADMIN");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        vm.startBroadcast();
        HSETH implementation = new HSETH();
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(proxyAddress);
        ProxyAdmin(proxyAdmin).upgrade(proxy, address(implementation));
        console.log("hsETH Transparent Proxy Upgraded: ", address(proxyAddress), " to ", address(implementation));
        emit HsETHUpgrade(address(proxyAddress), address(implementation));
        vm.stopBroadcast();
    }
}
