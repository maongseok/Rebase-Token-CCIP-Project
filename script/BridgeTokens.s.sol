// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {RebaseTokenPool} from "src/RebaseTokenPool.sol";
import {IERC20} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract BridgeTokensScript is Script {
    // function myrun(
    //     uint256 amountToBridge,
    //     Register.NetworkDetails memory networkDetails,
    //     Register.NetworkDetails memory remoteNetworkDetails,
    //     RebaseToken localToken,
    //     RebaseToken remoteToken
    // ) public {}
    function run() public {}

    function sendMessage(
        address receiverAddress,
        uint64 destinationChainSelector,
        address tokenToSendAddress,
        uint256 amountToSend,
        address linkTokenAddress,
        address routerAddress
    ) public {
        // revise this methode
        // CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        // Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails();

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: tokenToSendAddress, amount: amountToSend});

        vm.startBroadcast();
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverAddress),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: linkTokenAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
        });
        uint256 ccipFee = IRouterClient(routerAddress).getFee(destinationChainSelector, message);

        // any ierc20 will do the job we only need approve syntax
        IERC20(linkTokenAddress).approve(routerAddress, ccipFee);
        IERC20(tokenToSendAddress).approve(routerAddress, amountToSend);
        IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);
        vm.stopBroadcast();
    }
}

// revise
