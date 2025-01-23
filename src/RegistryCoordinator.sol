// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IAllocationManager} from "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IBLSApkRegistry} from "./interfaces/IBLSApkRegistry.sol";
import {IStakeRegistry} from "./interfaces/IStakeRegistry.sol";
import {IIndexRegistry} from "./interfaces/IIndexRegistry.sol";
import {IServiceManager} from "./interfaces/IServiceManager.sol";
import {IRegistryCoordinator} from "./interfaces/IRegistryCoordinator.sol";

import {BitmapUtils} from "./libraries/BitmapUtils.sol";
import {SlashingRegistryCoordinator} from "./SlashingRegistryCoordinator.sol";

/**
 * @title A `RegistryCoordinator` that has three registries:
 *      1) a `StakeRegistry` that keeps track of operators' stakes
 *      2) a `BLSApkRegistry` that keeps track of operators' BLS public keys and aggregate BLS public keys for each quorum
 *      3) an `IndexRegistry` that keeps track of an ordered list of operators for each quorum
 *
 * @author Layr Labs, Inc.
 */
contract RegistryCoordinator is SlashingRegistryCoordinator, IRegistryCoordinator {
    using BitmapUtils for *;

    /// @notice the ServiceManager for this AVS, which forwards calls onto EigenLayer's core contracts
    IServiceManager public immutable serviceManager;

    constructor(
        IServiceManager _serviceManager,
        IStakeRegistry _stakeRegistry,
        IBLSApkRegistry _blsApkRegistry,
        IIndexRegistry _indexRegistry,
        IAllocationManager _allocationManager,
        IPauserRegistry _pauserRegistry
    )
        SlashingRegistryCoordinator(
            _stakeRegistry,
            _blsApkRegistry,
            _indexRegistry,
            _allocationManager,
            _pauserRegistry
        )
    {
        serviceManager = _serviceManager;
    }

    /**
     *
     *                         EXTERNAL FUNCTIONS
     *
     */

    /// @inheritdoc IRegistryCoordinator
    function registerOperator(
        bytes memory quorumNumbers,
        string memory socket,
        IBLSApkRegistry.PubkeyRegistrationParams memory params,
        SignatureWithSaltAndExpiry memory operatorSignature
    ) external onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
        require(!isOperatorSetAVS, OperatorSetsEnabled());
        /**
         * If the operator has NEVER registered a pubkey before, use `params` to register
         * their pubkey in blsApkRegistry
         *
         * If the operator HAS registered a pubkey, `params` is ignored and the pubkey hash
         * (operatorId) is fetched instead
         */
        bytes32 operatorId = _getOrCreateOperatorId(msg.sender, params);

        // Register the operator in each of the registry contracts and update the operator's
        // quorum bitmap and registration status
        uint32[] memory numOperatorsPerQuorum = _registerOperator({
            operator: msg.sender,
            operatorId: operatorId,
            quorumNumbers: quorumNumbers,
            socket: socket
        }).numOperatorsPerQuorum;

        // For each quorum, validate that the new operator count does not exceed the maximum
        // (If it does, an operator needs to be replaced -- see `registerOperatorWithChurn`)
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            uint8 quorumNumber = uint8(quorumNumbers[i]);

            require(
                numOperatorsPerQuorum[i] <= _quorumParams[quorumNumber].maxOperatorCount,
                MaxQuorumsReached()
            );
        }

        // If the operator wasn't registered for any quorums, update their status
        // and register them with this AVS in EigenLayer core (DelegationManager)
        if (_operatorInfo[msg.sender].status != OperatorStatus.REGISTERED) {
            _operatorInfo[msg.sender] =
                OperatorInfo({operatorId: operatorId, status: OperatorStatus.REGISTERED});

            serviceManager.registerOperatorToAVS(msg.sender, operatorSignature);
            emit OperatorRegistered(msg.sender, operatorId);
        }
    }

    /// @inheritdoc IRegistryCoordinator
    function registerOperatorWithChurn(
        bytes calldata quorumNumbers,
        string memory socket,
        IBLSApkRegistry.PubkeyRegistrationParams memory params,
        OperatorKickParam[] memory operatorKickParams,
        SignatureWithSaltAndExpiry memory churnApproverSignature,
        SignatureWithSaltAndExpiry memory operatorSignature
    ) external onlyWhenNotPaused(PAUSED_REGISTER_OPERATOR) {
        require(!isOperatorSetAVS, OperatorSetsEnabled());

        /**
         * If the operator has NEVER registered a pubkey before, use `params` to register
         * their pubkey in blsApkRegistry
         *
         * If the operator HAS registered a pubkey, `params` is ignored and the pubkey hash
         * (operatorId) is fetched instead
         */
        bytes32 operatorId = _getOrCreateOperatorId(msg.sender, params);

        _registerOperatorWithChurn({
            operator: msg.sender,
            operatorId: operatorId,
            quorumNumbers: quorumNumbers,
            socket: socket,
            operatorKickParams: operatorKickParams,
            churnApproverSignature: churnApproverSignature
        });

        // If the operator wasn't registered for any quorums, update their status
        // and register them with this AVS in EigenLayer core (DelegationManager)
        if (_operatorInfo[msg.sender].status != OperatorStatus.REGISTERED) {
            _operatorInfo[msg.sender] =
                OperatorInfo({operatorId: operatorId, status: OperatorStatus.REGISTERED});

            serviceManager.registerOperatorToAVS(msg.sender, operatorSignature);
            emit OperatorRegistered(msg.sender, operatorId);
        }

        // If the operator kicked is not registered for any quorums, update their status
        // and deregister them from the AVS via the EigenLayer core contracts
        if (_operatorInfo[operatorKickParams[0].operator].status != OperatorStatus.REGISTERED) {
            _operatorInfo[operatorKickParams[0].operator].status = OperatorStatus.DEREGISTERED;
            serviceManager.deregisterOperatorFromAVS(operatorKickParams[0].operator);
            emit OperatorDeregistered(operatorKickParams[0].operator, operatorId);
        }
    }

    /// @inheritdoc IRegistryCoordinator
    function deregisterOperator(
        bytes memory quorumNumbers
    ) external onlyWhenNotPaused(PAUSED_DEREGISTER_OPERATOR) {
        // Check that the quorum numbers are M2 quorums and not operator sets
        // if operator sets are enabled
        for (uint256 i = 0; i < quorumNumbers.length; i++) {
            require(!isOperatorSetAVS || isM2Quorum[uint8(quorumNumbers[i])], OperatorSetsEnabled());
        }
        _deregisterOperator({operator: msg.sender, quorumNumbers: quorumNumbers});
    }

    /// @inheritdoc IRegistryCoordinator
    function enableOperatorSets() external onlyOwner {
        require(!isOperatorSetAVS, OperatorSetsEnabled());

        // Set all existing quorums as m2 quorums
        for (uint8 i = 0; i < quorumCount; i++) {
            isM2Quorum[i] = true;
        }

        // Enable operator sets mode
        isOperatorSetAVS = true;
    }

    /// @dev Hook to allow for any post-deregister logic
    function _afterDeregisterOperator(address operator, bytes32 operatorId, bytes memory quorumNumbers, uint192 newBitmap) internal virtual override {
        // If the operator is no longer registered for any quorums, update their status and deregister
        // them from the AVS via the EigenLayer core contracts
        if (newBitmap.isEmpty()) {
            _operatorInfo[operator].status = OperatorStatus.DEREGISTERED;
            serviceManager.deregisterOperatorFromAVS(operator);
            emit OperatorDeregistered(operator, operatorId);
        }
    }
}
