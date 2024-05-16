// SPDX-License-Identifier: UNLICENSED
// solhint-disable no-console
pragma solidity 0.8.16;

import { Script, console } from "forge-std/Script.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { StaderHavenStakingManager } from "../contracts/StaderHavenStakingManager.sol";
import { HSETH } from "../contracts/HSETH.sol";

contract DeployStakingManager is Script {
    event StakingManagerProxy(address proxy);
    event StakingManagerUpgrade(address proxy, address implementation);

    bytes32 constant ADMIN_ROLE = 0x00;

    function proxyDeploy() public {
        address tempAdmin = msg.sender;
        address admin = vm.envAddress("HSETH_ADMIN");
        address proxyAdmin = vm.envAddress("PROXY_ADMIN");
        address hsETH = vm.envAddress("HSETH");
        address treasury = vm.envAddress("TREASURY");
        address staderConfig = vm.envAddress("STADER_CONFIG");
        vm.startBroadcast();
        StaderHavenStakingManager implementation = new StaderHavenStakingManager();
        bytes memory initializationCalldata =
            abi.encodeWithSelector(implementation.initialize.selector, tempAdmin, hsETH, treasury, staderConfig);
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), proxyAdmin, initializationCalldata);
        console.log("StakingManager Transparent Proxy: ", address(proxy));
        StaderHavenStakingManager staderHavenStakingManager = StaderHavenStakingManager(address(proxy));
        staderHavenStakingManager.grantRole(staderHavenStakingManager.MANAGER(), admin);
        HSETH hsETHToken = HSETH(hsETH);
        hsETHToken.grantRole(hsETHToken.MINTER_ROLE(), address(staderHavenStakingManager));
        hsETHToken.grantRole(hsETHToken.BURNER_ROLE(), address(staderHavenStakingManager));

        hsETHToken.grantRole(ADMIN_ROLE, admin);
        staderHavenStakingManager.grantRole(ADMIN_ROLE, admin);

        hsETHToken.renounceRole(ADMIN_ROLE, tempAdmin);
        staderHavenStakingManager.renounceRole(ADMIN_ROLE, tempAdmin);

        emit StakingManagerProxy(address(proxy));
        vm.stopBroadcast();
    }

    function proxyUpgrade() public {
        address proxyAdmin = vm.envAddress("PROXY_ADMIN");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");
        vm.startBroadcast();
        StaderHavenStakingManager implementation = new StaderHavenStakingManager();
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(proxyAddress);
        ProxyAdmin(proxyAdmin).upgrade(proxy, address(implementation));
        console.log(
            "StakingManager Transparent Proxy Upgraded: ", address(proxyAddress), " to ", address(implementation)
        );
        emit StakingManagerUpgrade(address(proxyAddress), address(implementation));
        vm.stopBroadcast();
    }
}
