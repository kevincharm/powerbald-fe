// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8;

import {IRandomiserGen2} from "./interfaces/IRandomiserGen2.sol";
import {Authorised} from "./vendor/Authorised.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {IRandomiserCallbackSingle} from "./interfaces/IRandomiserCallbackSingle.sol";

/// @title ChainlinkVRFV2Randomiser
/// @author kevincharm
/// @notice Consume Chainlink's subscription-managed VRFv2 wrapper to return a
///     random number.
/// @dev NB: Not audited.
contract ChainlinkVRFV2Randomiser is
    IRandomiserGen2,
    Authorised,
    VRFConsumerBaseV2
{
    /// --- VRF SHIT ---
    /// @notice VRF Coordinator (V2)
    /// @dev https://docs.chain.link/vrf/v2/subscription/supported-networks
    address public immutable vrfCoordinator;
    /// @notice LINK token (make sure it's the ERC-677 one)
    /// @dev PegSwap: https://pegswap.chain.link
    address public immutable linkToken;
    /// @notice LINK token unit
    uint256 public immutable juels;
    /// @dev VRF Coordinator LINK premium per request
    uint256 public immutable linkPremium;
    /// @notice Each gas lane has a different key hash; each gas lane
    ///     determines max gwei that will be used for the callback
    bytes32 public immutable gasLaneKeyHash;
    /// @notice Max gas price for gas lane used in gasLaneKeyHash
    /// @dev This is used purely for gas estimation
    uint256 public immutable gasLaneMaxWei;
    /// @notice Absolute gas limit for callbacks
    uint32 public immutable callbackGasLimit;
    /// @notice VRF subscription ID; created during deployment
    uint64 public immutable subId;

    /// @notice requestId => contract to callback
    /// @dev contract must implement IRandomiserCallbackSingle
    mapping(uint256 => address) public callbackTargets;

    event RandomNumberRequested(uint256 indexed requestId);
    event RandomNumberFulfilled(uint256 indexed requestId, uint256 randomness);

    error InvalidFeedConfig(address feed, uint8 decimals);
    error InvalidFeedAnswer(
        int256 price,
        uint256 latestRoundId,
        uint256 updatedAt
    );

    constructor(
        address vrfCoordinator_,
        address linkToken_,
        uint256 linkPremium_,
        bytes32 gasLaneKeyHash_,
        uint256 gasLaneMaxWei_,
        uint32 callbackGasLimit_,
        uint64 subId_
    ) VRFConsumerBaseV2(vrfCoordinator_) {
        vrfCoordinator = vrfCoordinator_;
        linkToken = linkToken_;
        juels = 10 ** LinkTokenInterface(linkToken_).decimals();
        linkPremium = linkPremium_;
        gasLaneKeyHash = gasLaneKeyHash_;
        gasLaneMaxWei = gasLaneMaxWei_;
        callbackGasLimit = callbackGasLimit_;
        // NB: This contract must be added as a consumer to this subscription
        subId = subId_;
    }

    function typeAndVersion() external pure virtual returns (string memory) {
        return "ChainlinkVRFV2Randomiser 1.0.0-single";
    }

    /// @notice Request a random number
    /// @param callbackContract Target contract to callback with random numbers
    /// @param minConfirmations Number of block confirmations to wait.
    function getRandomNumber(
        address callbackContract,
        uint32 /** callbackGasLimit */,
        uint16 minConfirmations
    ) public payable override onlyAuthorised returns (uint256 requestId) {
        requestId = VRFCoordinatorV2Interface(vrfCoordinator)
            .requestRandomWords(
                gasLaneKeyHash,
                subId,
                minConfirmations,
                callbackGasLimit,
                1
            );
        callbackTargets[requestId] = callbackContract;
        emit RandomNumberRequested(requestId);
    }

    /// @notice Callback function used by VRF Coordinator
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomness
    ) internal override {
        address target = callbackTargets[requestId];
        delete callbackTargets[requestId];
        IRandomiserCallbackSingle(target).receiveRandomWord(
            requestId,
            randomness[0]
        );
        emit RandomNumberFulfilled(requestId, randomness[0]);
    }
}
