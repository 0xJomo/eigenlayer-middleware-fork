// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {ISlasher} from "../../interfaces/ISlasher.sol";
import {ISlashingRegistryCoordinator} from "../../interfaces/ISlashingRegistryCoordinator.sol";

contract SlasherStorage is ISlasher {
    /**
     *
     *                            CONSTANTS AND IMMUTABLES
     *
     */

    /// @notice the AllocationManager that tracks OperatorSets and Slashing in EigenLayer
    IAllocationManager public immutable allocationManager;
    /// @notice the SlashingRegistryCoordinator for this AVS
    ISlashingRegistryCoordinator public immutable slashingRegistryCoordinator;
    /**
     *
     *                                    STATE
     *
     */
    address public slasher;

    uint256 public nextRequestId;

    constructor(
        IAllocationManager _allocationManager,
        ISlashingRegistryCoordinator _slashingRegistryCoordinator
    ) {
        allocationManager = _allocationManager;
        slashingRegistryCoordinator = _slashingRegistryCoordinator;
    }

    uint256[48] private __gap;
}
