// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OApp, Origin, MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { OAppOptionsType3 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract OmniDaoController is OApp, OAppOptionsType3 {
    /// @notice Last string received from any remote chain
    // string public lastMessage;
    struct Proposal {
        uint256 proposalId;
        address proposer;
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 endTime;
        uint256 startTime;
        bool executed;
        ProposalType proposalType;
        bytes executionData;
        uint32[] targetChainIds;
        bytes32[] remoteCallData;
    }

    enum VoteType {
        FOR,
        AGAINST,
        ABSTAIN
    }

    enum ProposalType {
        TREASURY_DELEGATION,
        EMERGENCY,
        GOVERNANCE_CHANGE,
        PROTOCOL_UPGRADE,
        PARAMETER_CHANGE,
        OTHER
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => VoteType)) public votes;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(address => uint256) public votingPower;
    mapping(uint32 => bool) public supportedChains;
    mapping(uint32 => address) public remoteExecutors;
    mapping(bytes32 => bool) public executedOperations;
    mapping(uint32 => uint256) public lastExecutionNonce;

    uint256 public proposalCount;
    uint256 public votingPeriod;
    uint256 public minimumVotingPower;
    uint256 public quorumThreshold;
    uint256 public totalVotingPower;


    bool public isPaused;
    mapping(address => bool) public isPausable;

    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description, ProposalType proposalType);
    event VoteCast(uint256 indexed proposalId, address indexed voter, VoteType vote);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);
    event VotingPowerUpdated(address indexed voter, uint256 newVotingPower);
    event ChainSupportUpdated(uint32 indexed chainId, bool supported);
    event RemoteExecutorUpdated(uint32 indexed chainId, address executor);
    event Paused(bool isPaused);
    event RemoteOperationSent(uint32 indexed chainId, address indexed executor, bytes32 indexed operationId, bytes data);



    /// @notice Msg type for sending a string, for use in OAppOptionsType3 as an enforced option
    uint16 public constant SEND = 1;


    constructor(address _endpoint, address _owner) OApp(_endpoint, _owner) Ownable(_owner) {}

    // ──────────────────────────────────────────────────────────────────────────────
    // 0. (Optional) Quote business logic
    //
    // Example: Get a quote from the Endpoint for a cost estimate of sending a message.
    // Replace this to mirror your own send business logic.
    // ──────────────────────────────────────────────────────────────────────────────

    /**
     * @notice Quotes the gas needed to pay for the full omnichain transaction in native gas or ZRO token.
     * @param _dstEid Destination chain's endpoint ID.
     * @param _string The string to send.
     * @param _options Message execution options (e.g., for sending gas to destination).
     * @param _payInLzToken Whether to return fee in ZRO token.
     * @return fee A `MessagingFee` struct containing the calculated gas fee in either the native token or ZRO token.
     */
    function quoteSendString(
        uint32 _dstEid,
        string calldata _string,
        bytes calldata _options,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        bytes memory _message = abi.encode(_string);
        // combineOptions (from OAppOptionsType3) merges enforced options set by the contract owner
        // with any additional execution options provided by the caller
        fee = _quote(_dstEid, _message, combineOptions(_dstEid, SEND, _options), _payInLzToken);
    }


    /**
     * @notice Create a new proposal
     * @param description Human readable description
     * @param proposalType Type of proposal
     * @param executionData Local execution data (if any)
     * @param targetChainIds Array of chain IDs to execute on
     * @param remoteCallData Array of calldata for each target chain
     */
    function createProposal(
        string memory description,
        ProposalType proposalType,
        bytes memory executionData,
        uint32[] memory targetChainIds,
        bytes32[] memory remoteCallData
    ) external {
        require(votingPower[msg.sender] >= minimumVotingPower, "Insufficient voting power");
        require(targetChainIds.length == remoteCallData.length, "Array length mismatch");
        require(!isPaused, "Contract is paused for emergency");
        
        uint256 proposalId = ++proposalCount;

        proposals[proposalId] = Proposal({
            proposalId: proposalId,
            proposer: msg.sender,
            description: description,
            votesFor: 0,
            votesAgainst: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + votingPeriod,
            executed: false,
            proposalType: proposalType,
            executionData: executionData,
            targetChainIds: targetChainIds,
            remoteCallData: remoteCallData
        });

        emit ProposalCreated(proposalId, msg.sender, description, proposalType);
    }

    /**
     * @notice Cast a vote on a proposal
     * @param proposalId ID of the proposal to vote on
     * @param voteType Type of vote (FOR, AGAINST, ABSTAIN)
     */
    function vote(uint256 proposalId, VoteType voteType) external {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.proposalId != 0, "Proposal does not exist");
        require(block.timestamp <= proposal.endTime, "Voting period ended");
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        require(votingPower[msg.sender] > 0, "No voting power");

        hasVoted[proposalId][msg.sender] = true;
        votes[proposalId][msg.sender] = voteType;

        uint256 weight = votingPower[msg.sender];

        if (voteType == VoteType.FOR) {
            proposal.votesFor += weight;
        } else if (voteType == VoteType.AGAINST) {
            proposal.votesAgainst += weight;
        }

        emit VoteCast(proposalId, msg.sender, voteType);
    }

    function executeProposal(uint256 proposalId) external payable nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.id != 0, "Proposal does not exist");
        require(block.timestamp > proposal.endTime, "Voting period not ended");
        require(!proposal.executed, "Already executed");
        require(_proposalPassed(proposalId), "Proposal did not pass");

        proposal.executed = true;

        if (proposal.executionData.length > 0) {
            _executeLocal(proposal.executionData);
        }

        bool success = _executeRemote(proposalId, proposal);

        emit ProposalExecuted(proposalId);
    }

    function _executeRemote(
        uint256 proposalId,
        Proposal storage proposal
    ) internal returns (bool) {
       require(msg.value > 0, "No funds to cover gas");

       uint256 totalChains = proposal.targetChainIds.length;
       uint256 gasPerChain = msg.value / totalChains;

       for (uint256 i = 0; i < totalChains; i++) {
        uint32 targetChain = proposal.targetChainIds[i];
        require(supportedChains[targetChain], "Unsupported chain");
        require(remoteExecutors[targetChain] != address(0), "No executor on target chain");

        bytes memory message = abi.encode(proposalId, proposal.proposalType, proposal.remoteCallData[i], block.timestamp);

        bytes32 operationHash = keccak256(abi.encodePacked(proposalId, targetChain, i));

        bytes memory options = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(200000, 0)
            .addExecutorOrderedExecutionOption();

        MessagingFee memory fee = MessagingFee(gasPerChain, 0);

        _lzSend(targetChain, message, options, fee, payable(msg.sender));

        executedOperations[operationHash] = true;
        lastExecutionNonce[targetChain]++;

        emit RemoteOperationSent(targetChain, remoteExecutors[targetChain], operationHash, proposal.remoteCallData[i]);
       }

       return true;
    }

    function executeLocal() internal {}


    // ──────────────────────────────────────────────────────────────────────────────
    // 1. Send business logic
    //
    // Example: send a simple string to a remote chain. Replace this with your
    // own state-update logic, then encode whatever data your application needs.
    // ──────────────────────────────────────────────────────────────────────────────

    /// @notice Send a string to a remote OApp on another chain
    /// @param _dstEid   Destination Endpoint ID (uint32)
    /// @param _string  The string to send
    /// @param _options  Execution options for gas on the destination (bytes)
    function sendString(uint32 _dstEid, string calldata _string, bytes calldata _options) external payable {
        // 1. (Optional) Update any local state here.
        //    e.g., record that a message was "sent":
        //    sentCount += 1;

        // 2. Encode any data structures you wish to send into bytes
        //    You can use abi.encode, abi.encodePacked, or directly splice bytes
        //    if you know the format of your data structures
        bytes memory _message = abi.encode(_string);

        // 3. Call OAppSender._lzSend to package and dispatch the cross-chain message
        //    - _dstEid:   remote chain's Endpoint ID
        //    - _message:  ABI-encoded string
        //    - _options:  combined execution options (enforced + caller-provided)
        //    - MessagingFee(msg.value, 0): pay all gas as native token; no ZRO
        //    - payable(msg.sender): refund excess gas to caller
        //
        //    combineOptions (from OAppOptionsType3) merges enforced options set by the contract owner
        //    with any additional execution options provided by the caller
        _lzSend(
            _dstEid,
            _message,
            combineOptions(_dstEid, SEND, _options),
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // 2. Receive business logic
    //
    // Override _lzReceive to decode the incoming bytes and apply your logic.
    // The base OAppReceiver.lzReceive ensures:
    //   • Only the LayerZero Endpoint can call this method
    //   • The sender is a registered peer (peers[srcEid] == origin.sender)
    // ──────────────────────────────────────────────────────────────────────────────

    /// @notice Invoked by OAppReceiver when EndpointV2.lzReceive is called
    /// @dev   _origin    Metadata (source chain, sender address, nonce)
    /// @dev   _guid      Global unique ID for tracking this message
    /// @param _message   ABI-encoded bytes (the string we sent earlier)
    /// @dev   _executor  Executor address that delivered the message
    /// @dev   _extraData Additional data from the Executor (unused here)
    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        // 1. Decode the incoming bytes into a string
        //    You can use abi.decode, abi.decodePacked, or directly splice bytes
        //    if you know the format of your data structures
        string memory _string = abi.decode(_message, (string));

        // 2. Apply your custom logic. In this example, store it in `lastMessage`.
        lastMessage = _string;

        // 3. (Optional) Trigger further on-chain actions.
        //    e.g., emit an event, mint tokens, call another contract, etc.
        //    emit MessageReceived(_origin.srcEid, _string);
    }
}
