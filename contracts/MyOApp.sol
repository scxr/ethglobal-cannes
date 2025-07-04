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



    /**
     * @notice Execute a passed proposal
     * @param proposalId ID of the proposal to execute
     */
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

    /**
     * @notice Execute a proposal on remote chains
     * @param proposalId ID of the proposal to execute
     * @param proposal Proposal struct
     * @return bool True if execution was successful
     */
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


    /**
     * @notice Execute a proposal on the local chain
     * @param proposal Proposal struct
     */
    function executeLocal(Proposal storage proposal) internal {
        // TODO: Implement local execution
    }

    /**
     * @notice Pause the contract for emergency
     */
    function emergencyPause() external  {
        require(!isPaused, "Already paused");
        require(isPausable[msg.sender], "Not an emergency guardian");


        isPaused = true;
        emit Paused(true);

        _sendEmergencyAction("PAUSE_ALL", "Emergency pause activated");
    }

    function emergencyUnpause() external  {
        require(isPaused, "Not paused");
        require(isPausable[msg.sender], "Not an emergency guardian");
        
        isPaused = false;
        _sendEmergencyAction("UNPAUSE_ALL", "Emergency pause deactivated");
        emit Paused(false);
    }


    /**
     * @notice Send an emergency action to all supported chains
     * @param action The action to send
     * @param reason The reason for the action
     */
    function _sendEmergencyAction(string memory action, string memory reason) internal {
        uint32[] memory allChains = _getAllSupportedChains();
        
        for (uint256 i = 0; i < allChains.length; i++) {
            uint32 chainId = allChains[i];
            if (remoteExecutors[chainId] != address(0)) {
                bytes memory message = abi.encode("EMERGENCY", action, reason, block.timestamp);
                
                bytes memory options = OptionsBuilder.newOptions()
                    .addExecutorLzReceiveOption(100000, 0);

                MessagingFee memory fee = MessagingFee(0.001 ether, 0);
                
                _lzSend(chainId, message, options, fee, payable(msg.sender));
            }
        }

        emit EmergencyAction(msg.sender, action, allChains);
    }

    /**
     * @notice Set a remote executor for a chain
     * @param chainId The chain ID to set the executor for
     * @param executor The executor address
     */
    function setRemoteExecutor(uint32 chainId, address executor) external onlyOwner {
        remoteExecutors[chainId] = executor;
        supportedChains[chainId] = true;
        
        emit RemoteExecutorUpdated(chainId, executor);
    }

    /**
     * @notice Update the voting power for an account
     * @param account The account to update the voting power for
     * @param power The new voting power
     */
    function updateVotingPower(address account, uint256 power) external onlyOwner {
        uint256 oldPower = votingPower[account];
        votingPower[account] = power;
        
        totalVotingPower = totalVotingPower - oldPower + power;
    }
    
    /**
     * @notice Set the governance parameters
     * @param _votingPeriod The voting period
     * @param _quorumThreshold The quorum threshold
     * @param _minVotingPower The minimum voting power
     */
    function setGovernanceParams(
        uint256 _votingPeriod,
        uint256 _quorumThreshold,
        uint256 _minVotingPower
    ) external onlyOwner {
        votingPeriod = _votingPeriod;
        quorumThreshold = _quorumThreshold;
        minimumVotingPower = _minVotingPower;
    }

    /**
     * @notice Check if a proposal has passed
     * @param proposalId ID of the proposal to check
     * @return bool True if the proposal has passed
     */
    function _proposalPassed(uint256 proposalId) internal view returns (bool) {
        Proposal memory proposal = proposals[proposalId];
        uint256 totalVotes = proposal.votesFor + proposal.votesAgainst;
        
        // Check quorum
        if (totalVotes < (totalVotingPower * quorumThreshold) / 10000) {
            return false;
        }
        
        // Check majority
        return proposal.votesFor > proposal.votesAgainst;
    }

    /**
     * @notice Get a proposal
     * @param proposalId ID of the proposal to get
     * @return Proposal struct
     */
    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    /**
     * @notice Get the voting power for an account
     * @param account The account to get the voting power for
     * @return uint256 The voting power for the account
     */
    function getVotingPower(address account) external view returns (uint256) {
        return votingPower[account];
    }

    /**
     * @notice Quote the gas needed to send a message
     * @param targetChain The target chain ID
     * @param message The message to send
     * @param options The options for the message
     * @param payInLzToken Whether to pay in ZRO token
     * @return MessagingFee The gas fee
     */
    function quote(
        uint32 targetChain,
        bytes memory message,
        bytes memory options,
        bool payInLzToken
    ) public view returns (MessagingFee memory) {
        return _quote(targetChain, message, options, payInLzToken);
    }

    /**
     * @notice Get the next nonce for a chain
     * @param srcEid The source chain ID
     * @param sender The sender address
     * @return uint64 The next nonce
     */
    function nextNonce(uint32 srcEid, bytes32 sender) public view virtual returns (uint64) {
        return endpoint.nextNonce(srcEid, sender);
    }

    /**
     * @notice Receive ETH
     */
    receive() external payable {}

    
    /// @notice Send a string to a remote OApp on another chain
    /// @param _dstEid   Destination Endpoint ID (uint32)
    /// @param _string  The string to send
    /// @param _options  Execution options for gas on the destination (bytes)
    function sendString(uint32 _dstEid, string calldata _string, bytes calldata _options) external payable {

        bytes memory _message = abi.encode(_string);

        _lzSend(
            _dstEid,
            _message,
            combineOptions(_dstEid, SEND, _options),
            MessagingFee(msg.value, 0),
            payable(msg.sender)
        );
    }



    /// @notice Invoked by OAppReceiver when EndpointV2.lzReceive is called
    /// @dev   _origin    Metadata (source chain, sender address, nonce)
    /// @dev   _guid      Global unique ID for tracking this message
    /// @param _message   ABI-encoded bytes (the string we sent earlier)
    /// @dev   _executor  Executor address that delivered the message
    /// @dev   _extraData Additional data from the Executor (unused here)
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        require(
            remoteExecutors[_origin.srcEid] != address(0) &&
            _origin.sender == bytes32(uint256(uint160(remoteExecutors[_origin.srcEid]))),
            "Unauthorized sender"
        );

        // Decode the response
        (uint256 proposalId, bool success, string memory result) = abi.decode(
            _message,
            (uint256, bool, string)
        );

        // Handle the response (emit events, update state, etc.)
        emit RemoteOperationSent(proposalId, _origin.srcEid, keccak256(_message));
        // 3. (Optional) Trigger further on-chain actions.
        //    e.g., emit an event, mint tokens, call another contract, etc.
        //    emit MessageReceived(_origin.srcEid, _string);
    }

}
