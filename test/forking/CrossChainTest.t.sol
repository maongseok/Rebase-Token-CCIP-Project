// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from
    "@chainlink/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@chainlink/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";

import {RebaseToken} from "src/RebaseToken.sol";
import {RebaseTokenPool} from "src/RebaseTokenPool.sol";
import {TokenPool} from "@chainlink/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@chainlink/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Vault} from "src/Vault.sol";

import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {IERC20} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract CrossChainTest is Test {
    address owner = makeAddr("owner");
    address sender = makeAddr("sender");
    address receiver = makeAddr("receiver");
    uint256 SEND_VALUE = 1e5;

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;

    RebaseTokenPool sepoliaTokenPool;
    RebaseTokenPool arbSepoliaPool;

    Vault vault;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbNetworkDetails;

    function setUp() public {
        sepoliaFork = vm.createSelectFork("sepolia-eth");
        arbSepoliaFork = vm.createFork("sepolia-arb");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        // revise this sheatcode make this address avaible in both chains
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 1. Deploy and configure on sepolia
        // getting network information
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        sepoliaToken = new RebaseToken();

        vault = new Vault(IRebaseToken(address(sepoliaToken)));

        sepoliaTokenPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        // grant mint and burn role to the pool
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaTokenPool));

        // setting admin
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        // setting token to the pool
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaTokenPool)
        );
        vm.stopPrank();

        // 2. Deploy and configure on arbitrum
        vm.selectFork(arbSepoliaFork);
        arbNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        arbSepoliaToken = new RebaseToken();

        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbNetworkDetails.rmnProxyAddress,
            arbNetworkDetails.routerAddress
        );
        // grant mint and burn role to the pool
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));

        // setting admin
        RegistryModuleOwnerCustom(arbNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaToken)
        );
        TokenAdminRegistry(arbNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));

        // setting token to the pool
        TokenAdminRegistry(arbNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbSepoliaToken), address(arbSepoliaPool)
        );
        vm.stopPrank();
    }

    function configureTokenPool(
        uint256 forkId,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteToken
    ) public {
        vm.selectFork(forkId);
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);

        vm.prank(owner);
        //           struct ChainUpdate {
        //     uint64 remoteChainSelector; // Remote chain selector
        //     bytes[] remotePoolAddresses; // Address of the remote pool, ABI encoded in the case of a remote EVM chain.
        //     bytes remoteTokenAddress; // Address of the remote token, ABI encoded in the case of a remote EVM chain.
        //     RateLimiter.Config outboundRateLimiterConfig; // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
        //     RateLimiter.Config inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
        //   }
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool(localPool).applyChainUpdates(new uint64[](0), chainsToAdd);
    }

    function bridgeTokensToReceiver(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        //sending a cross chain msg

        //   struct EVM2AnyMessage {
        //     bytes receiver; // abi.encode(receiver address) for dest EVM chains.
        //     bytes data; // Data payload.
        //     EVMTokenAmount[] tokenAmounts; // Token transfers.
        //     address feeToken; // Address of feeToken. address(0) means you will send msg.value.
        //     bytes extraArgs; // Populate this with _argsToBytes(EVMExtraArgsV2).
        //   }
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            // revise for the function we call 0 means we did not set it and theres two struct parameters check main folder
            // extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})) EVMExtraArgsV1
            extraArgs: ""
        });
        // get fees and send ccip with getting links too @notice you can remove this also to free slots then do the check the other function
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);
        ccipLocalSimulatorFork.requestLinkFromFaucet(sender, fee);
        vm.prank(sender);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);

        vm.prank(sender);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);
        uint256 localBalanceBefore = localToken.balanceOf(sender);

        vm.prank(sender);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);
        uint256 localBalanceAfter = localToken.balanceOf(sender);
        assertEq(localBalanceBefore, localBalanceAfter + amountToBridge);

        // /gt red to walk around vm.warp git prob by free slots /uint256 senderInterestRate = localToken.getUserInterestRate(sender);

        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes);
        uint256 receiverBalanceBefore = remoteToken.balanceOf(receiver);
        // we order ccip to send us the msg
        // revise this ln almost killed me
        vm.selectFork(localFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        // uint256 receiverInterestRate = remoteToken.getUserInterestRate(receiver);
        vm.selectFork(remoteFork);
        assertEq(remoteToken.balanceOf(receiver), receiverBalanceBefore + amountToBridge);
        // assertEq(receiverInterestRate, senderInterestRate);
    }

    function bridgeTokensToSender(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(sender),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: ""
        });

        ccipLocalSimulatorFork.requestLinkFromFaucet(
            receiver,
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message) * 10
        );
        //
        vm.prank(receiver);
        //* 10 to prevent recalculation of fee going up
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, type(uint64).max);
        // IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message) * 12
        //     / 10

        vm.prank(receiver);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);
        uint256 localBalanceBefore = localToken.balanceOf(receiver);

        vm.prank(receiver);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);
        uint256 localBalanceAfter = localToken.balanceOf(receiver);
        assertEq(localBalanceBefore, localBalanceAfter + amountToBridge);
        uint256 receiverInterestRate = localToken.getUserInterestRate(receiver);

        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes);
        uint256 senderBalanceBefore = remoteToken.balanceOf(sender);

        vm.selectFork(localFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        uint256 senderInterestRate = remoteToken.getUserInterestRate(sender);
        vm.selectFork(remoteFork);
        assertEq(remoteToken.balanceOf(sender), senderBalanceBefore + amountToBridge);
        assertEq(senderInterestRate, receiverInterestRate);
    }
    /**
     * @dev this function test from sender to receiver and back from receiver to sender
     */

    function testBridgeAllTokensINAndBack() public {
        // configuring the token pool
        /**
         * @notice there's a reselection of fork network in the function
         */
        configureTokenPool(
            sepoliaFork,
            address(sepoliaTokenPool),
            arbNetworkDetails.chainSelector,
            address(arbSepoliaPool),
            address(arbSepoliaToken)
        );
        configureTokenPool(
            arbSepoliaFork,
            address(arbSepoliaPool),
            sepoliaNetworkDetails.chainSelector,
            address(sepoliaTokenPool),
            address(sepoliaToken)
        );
        vm.selectFork(sepoliaFork);
        vm.deal(sender, SEND_VALUE);
        vm.prank(sender);
        // revise
        vault.deposit{value: SEND_VALUE}();
        // if you love doing work that look great but do same job unless if it address then typecast is a must
        // Vault(payable(address(vault))).deposit{value: SEND_VALUE}();

        assertEq(sepoliaToken.balanceOf(sender), SEND_VALUE);

        // --- FIRST BRIDGE ---
        bridgeTokensToReceiver(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );
        assertEq(arbSepoliaToken.balanceOf(receiver), SEND_VALUE, "Receiver did not get tokens on Arbitrum");

        vm.selectFork(sepoliaFork);
        assertEq(sepoliaToken.balanceOf(sender), 0, "Sender tokens were not burned on sepolia");
        // --- RETURN BRIDGE ---

        vm.warp(block.timestamp + 1 hours);
        bridgeTokensToSender(
            SEND_VALUE,
            arbSepoliaFork,
            sepoliaFork,
            arbNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaToken,
            sepoliaToken
        );
        assertEq(sepoliaToken.balanceOf(sender), SEND_VALUE, "sender did not get tokens back on Sepolia");
        vm.selectFork(arbSepoliaFork);
        assertEq(arbSepoliaToken.balanceOf(receiver), 0, "Receiver's tokens were not burned on Arbitrum");
    }
}
// revise
