// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {TokenAdminRegistry} from "@chainlink/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from
    "@chainlink/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@chainlink/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";

contract setPool is Script {
    function grantMintAndBurnRole(address token, address pool) public {
        vm.startBroadcast();
        IRebaseToken(token).grantMintAndBurnRole(pool);
        vm.stopBroadcast();
    }

    function setCCIPPremissions(address token, address pool) public {
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startBroadcast();
        RegistryModuleOwnerCustom(networkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(token);

        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).acceptAdminRole(token);
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).setPool(token, pool);
        vm.stopBroadcast();
    }
}
