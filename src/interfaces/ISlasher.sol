// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IAllocationManager} from
    "eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";

interface ISlasherEvents {
    event SlashingRequested(
        uint256 indexed requestId,
        address indexed operator,
        uint32 indexed operatorSetId,
        uint256[] wadsToSlash,
        string description
    );

    event SlashingRequestCancelled(uint256 indexed requestId);

    event OperatorSlashed(
        uint256 indexed slashingRequestId,
        address indexed operator,
        uint32 indexed operatorSetId,
        uint256[] wadsToSlash,
        string description
    );
}

interface ISlasherErrors {
    /// @dev Thrown when the caller is not the veto committee
    error OnlyVetoCommittee();
    /// @dev Thrown when the caller is not the slasher
    error OnlySlasher();
    /// @dev Thrown when the veto period has passed
    error VetoPeriodPassed();
    /// @dev Thrown when the veto period has not passed
    error VetoPeriodNotPassed();
    /// @dev Thrown when the slashing request is cancelled
    error SlashingRequestIsCancelled();
    /// @dev Thrown when the slashing request was not already requested
    error SlashingRequestNotRequested();
}

interface ISlasherTypes {
    enum SlashingStatus {
        Null,
        Requested,
        Completed,
        Cancelled
    }

    struct SlashingRequest {
        IAllocationManager.SlashingParams params;
        uint256 requestTimestamp;
        SlashingStatus status;
    }
}

interface ISlasher is ISlasherEvents, ISlasherTypes, ISlasherErrors {}
