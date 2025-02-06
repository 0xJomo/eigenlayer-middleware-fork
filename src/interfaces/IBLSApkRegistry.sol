// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {BN254} from "../libraries/BN254.sol";

interface IBLSApkRegistryErrors {
    /// @dev Thrown when the caller is not the owner of the registry coordinator.
    error OnlyRegistryCoordinatorOwner();
    /// @dev Thrown when a quorum being created already exists.
    error QuorumAlreadyExists();
    /// @dev Thrown when a quorum does not exist.
    error QuorumDoesNotExist();
    /// @dev Thrown when a BLS pubkey provided is zero pubkey
    error ZeroPubKey();
    /// @dev Thrown when an operator has already registered a BLS pubkey.
    error OperatorAlreadyRegistered();
    /// @dev Thrown when the operator is not registered.
    error OperatorNotRegistered();
    /// @dev Thrown when a BLS pubkey has already been registered for an operator.
    error BLSPubkeyAlreadyRegistered();
    /// @dev Thrown when either the G1 signature is wrong, or G1 and G2 private key do not match.
    error InvalidBLSSignatureOrPrivateKey();
    /// @dev Thrown when the quorum apk update block number is too recent.
    error BlockNumberTooRecent();
    /// @dev Thrown when blocknumber and index provided is not the latest apk update.
    error BlockNumberNotLatest();
}

interface IBLSApkRegistryTypes {
    /// @notice Tracks the history of aggregate public key updates for a quorum.
    /// @dev Each update contains a hash of the aggregate public key and block numbers for timing.
    /// @param apkHash First 24 bytes of keccak256(apk_x0, apk_x1, apk_y0, apk_y1) representing the aggregate public key.
    /// @param updateBlockNumber Block number when this update occurred (inclusive).
    /// @param nextUpdateBlockNumber Block number when the next update occurred (exclusive), or 0 if this is the latest update.
    struct ApkUpdate {
        bytes24 apkHash;
        uint32 updateBlockNumber;
        uint32 nextUpdateBlockNumber;
    }

    /**
     * @notice Struct used when registering a new public key
     * @param pubkeyRegistrationSignature is the registration message signed by the private key of the operator
     * @param pubkeyG1 is the corresponding G1 public key of the operator 
     * @param pubkeyG2 is the corresponding G2 public key of the operator
     */     
    struct PubkeyRegistrationParams {
        BN254.G1Point pubkeyRegistrationSignature;
        BN254.G1Point pubkeyG1;
        BN254.G2Point pubkeyG2;
    }
}

interface IBLSApkRegistryEvents is IBLSApkRegistryTypes {
    /*
     * @notice Emitted when `operator` registers their BLS public key pair (`pubkeyG1` and `pubkeyG2`).
     * @param operator The address of the operator registering the keys.
     * @param pubkeyG1 The operator's G1 public key.
     * @param pubkeyG2 The operator's G2 public key.
     */
    event NewPubkeyRegistration(
        address indexed operator, BN254.G1Point pubkeyG1, BN254.G2Point pubkeyG2
    );

    // EVENTS
    /// @notice Emitted when `operator` update with the public keys `pubkeyG1` and `pubkeyG2`.
    event NewPubkeyUpdate(address indexed operator, BN254.G1Point pubkeyG1, BN254.G2Point pubkeyG2);

    // @notice Emitted when a new operator pubkey is registered for a set of quorums
    event OperatorAddedToQuorums(
        address operator,
        bytes32 operatorId,
        bytes quorumNumbers
    );

    // @notice Emitted when an operator pubkey is removed from a set of quorums
    event OperatorRemovedFromQuorums(
        address operator, 
        bytes32 operatorId,
        bytes quorumNumbers
    );
}

interface IBLSApkRegistry is IBLSApkRegistryErrors, IBLSApkRegistryEvents {
    /* STORAGE */

    /*
     * @notice Returns the address of the registry coordinator contract.
     * @return The address of the registry coordinator.
     * @dev This value is immutable and set during contract construction.
     */
    function registryCoordinator() external view returns (address);

    /*
     * @notice Maps `operator` to their BLS public key hash (`operatorId`).
     * @param operator The address of the operator.
     * @return operatorId The hash of the operator's BLS public key.
     */
    function operatorToPubkeyHash(
        address operator
    ) external view returns (bytes32 operatorId);

    /*
     * @notice Maps `pubkeyHash` to their corresponding `operator` address.
     * @param pubkeyHash The hash of a BLS public key.
     * @return operator The address of the operator who registered this public key.
     */
    function pubkeyHashToOperator(
        bytes32 pubkeyHash
    ) external view returns (address operator);

    /*
     * @notice Maps `operator` to their BLS public key in G1.
     * @dev Returns a non-encoded BN254.G1Point.
     * @param operator The address of the operator.
     * @return The operator's BLS public key in G1.
     */
    function operatorToPubkey(
        address operator
    ) external view returns (uint256, uint256);

    /*
     * @notice Stores the history of aggregate public key updates for `quorumNumber` at `index`.
     * @dev Returns a non-encoded IBLSApkRegistryTypes.ApkUpdate.
     * @param quorumNumber The identifier of the quorum.
     * @param index The index in the history array.
     * @return The APK update entry at the specified index for the given quorum.
     * @dev Each entry contains the APK hash, update block number, and next update block number.
     */
    function apkHistory(
        uint8 quorumNumber,
        uint256 index
    ) external view returns (bytes24, uint32, uint32);

    /*
     * @notice Maps `quorumNumber` to their current aggregate public key.
     * @dev Returns a non-encoded BN254.G1Point.
     * @param quorumNumber The identifier of the quorum.
     * @return The current APK as a G1 point.
     */
    function currentApk(
        uint8 quorumNumber
    ) external view returns (uint256, uint256);

    /* ACTIONS */

    /*
     * @notice Registers `operator`'s pubkey for `quorumNumbers`.
     * @param operator The address of the operator to register.
     * @param quorumNumbers The quorum numbers to register for, where each byte is an 8-bit integer.
     * @dev Access restricted to the RegistryCoordinator.
     * @dev Preconditions (assumed, not validated):
     *      1. `quorumNumbers` has no duplicatesd
     *      2. `quorumNumbers.length` != 0
     *      3. `quorumNumbers` is ordered ascending
     *      4. The operator is not already registered
     */
    function registerOperator(address operator, bytes calldata quorumNumbers) external;

    /*
     * @notice Deregisters `operator`'s pubkey from `quorumNumbers`.
     * @param operator The address of the operator to deregister.
     * @param quorumNumbers The quorum numbers to deregister from, where each byte is an 8-bit integer.
     * @dev Access restricted to the RegistryCoordinator.
     * @dev Preconditions (assumed, not validated):
     *      1. `quorumNumbers` has no duplicates
     *      2. `quorumNumbers.length` != 0
     *      3. `quorumNumbers` is ordered ascending
     *      4. The operator is not already deregistered
     *      5. `quorumNumbers` is a subset of the operator's registered quorums
     */
    function deregisterOperator(address operator, bytes calldata quorumNumbers) external;

    /*
     * @notice Initializes `quorumNumber` by pushing its first APK update.
     * @param quorumNumber The number of the new quorum.
     */
    function initializeQuorum(
        uint8 quorumNumber
    ) external;

    /*
     * @notice Registers `operator` as the owner of a BLS public key using `params` and `pubkeyRegistrationMessageHash`.
     * @param operator The operator for whom the key is being registered.
     * @param params Contains the G1 & G2 public keys and ownership proof signature.
     * @param pubkeyRegistrationMessageHash The hash that must be signed to prove key ownership.
     * @return operatorId The unique identifier (pubkey hash) for this operator.
     * @dev Called by the RegistryCoordinator.
     */
    function registerBLSPublicKey(
        address operator,
        IBLSApkRegistryTypes.PubkeyRegistrationParams calldata params,
        BN254.G1Point calldata pubkeyRegistrationMessageHash
    ) external returns (bytes32 operatorId);

    function updateBLSPublicKey(
        IBLSApkRegistryTypes.PubkeyRegistrationParams calldata params
    ) external returns (bytes32 operatorId);

    /**
     * @notice Returns the pubkey and pubkey hash of an operator
     * @dev Reverts if the operator has not registered a valid pubkey
     */
    function getRegisteredPubkey(address operator) external view returns (BN254.G1Point memory, bytes32);

    /// @notice Returns the current APK for the provided `quorumNumber `
    function getApk(uint8 quorumNumber) external view returns (BN254.G1Point memory);

    /// @notice Returns the index of the quorumApk index at `blockNumber` for the provided `quorumNumber`
    function getApkIndicesAtBlockNumber(bytes calldata quorumNumbers, uint256 blockNumber) external view returns(uint32[] memory);

    /// @notice Returns the `ApkUpdate` struct at `index` in the list of APK updates for the `quorumNumber`
    function getApkUpdateAtIndex(uint8 quorumNumber, uint256 index) external view returns (IBLSApkRegistryTypes.ApkUpdate memory);

    /// @notice Returns the operator address for the given `pubkeyHash`
    function getOperatorFromPubkeyHash(bytes32 pubkeyHash) external view returns (address);

    /**
     * @notice get 24 byte hash of the apk of `quorumNumber` at `blockNumber` using the provided `index`;
     * called by checkSignatures in BLSSignatureChecker.sol.
     * @param quorumNumber is the quorum whose ApkHash is being retrieved
     * @param blockNumber is the number of the block for which the latest ApkHash will be retrieved
     * @param index is the index of the apkUpdate being retrieved from the list of quorum apkUpdates in storage
     */
    function getApkHashAtBlockNumberAndIndex(uint8 quorumNumber, uint32 blockNumber, uint256 index) external view returns (bytes24);

    /*
 * @notice Returns the number of APK updates for `quorumNumber`.
     * @param quorumNumber The quorum to query.
     * @return The length of the APK history.
     */
    function getApkHistoryLength(
        uint8 quorumNumber
    ) external view returns (uint32);

    /// @notice returns the ID used to identify the `operator` within this AVS.
    /// @dev Returns zero in the event that the `operator` has never registered for the AVS
    function getOperatorId(address operator) external view returns (bytes32);
}
