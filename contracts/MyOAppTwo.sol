// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { OApp, Origin, MessagingFee } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import { OAppOptionsType3 } from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title MultichainDAOController
 * @notice LayerZero V2 OApp for cross-chain DAO governance and treasury management
 * @dev Master contract deployed on Ethereum, controls remote executors on other chains
 */
contract MultichainDAOController is OApp, OAppOptionsType3, ReentrancyGuard {
    using OAppOptionsType3 for bytes;

    // ============ STATE VARIABLES ============
    
    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        ProposalType proposalType;
        bytes executionData;
        uint32[] targetChains;
        bytes[] remoteCalldata;
    }

    enum ProposalType {
        PARAMETER_UPDATE,
        TREASURY_OPERATION,
        EMERGENCY_ACTION,
        GOVERNANCE_CHANGE,
        PROTOCOL_UPGRADE
    }

    enum VoteType {
        FOR,
        AGAINST,
        ABSTAIN
    }

    // Core governance state
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(address => VoteType)) public votes;
    mapping(address => uint256) public votingPower;
    mapping(uint32 => address) public remoteExecutors;
    mapping(uint32 => bool) public supportedChains;
    
    uint256 public proposalCount;
    uint256 public votingPeriod = 7 days;
    uint256 public minVotingPower = 1000e18; // Minimum tokens to propose
    uint256 public quorumThreshold = 4000; // 40% (basis points)
    uint256 public totalVotingPower;
    
    // Emergency controls
    bool public emergencyPaused;
    mapping(address => bool) public emergencyGuardians;
    
    // Cross-chain operation tracking
    mapping(bytes32 => bool) public executedOperations;
    mapping(uint32 => uint256) public lastExecutionNonce;

    // ============ EVENTS ============
    
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string description,
        uint32[] targetChains
    );
    
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        VoteType voteType,
        uint256 weight
    );
    
    event ProposalExecuted(
        uint256 indexed proposalId,
        bool success,
        uint32[] targetChains
    );
    
    event RemoteOperationSent(
        uint256 indexed proposalId,
        uint32 indexed targetChain,
        bytes32 operationHash
    );
    
    event RemoteExecutorUpdated(
        uint32 indexed chainId,
        address indexed executor
    );
    
    event EmergencyAction(
        address indexed guardian,
        string action,
        uint32[] targetChains
    );

    // ============ CONSTRUCTOR ============
    
    constructor(
        address _endpoint,
        address _delegate
    ) OApp(_endpoint, _delegate) Ownable(_delegate) {
        // Set initial emergency guardians
        emergencyGuardians[_delegate] = true;
    }

    // ============ GOVERNANCE FUNCTIONS ============
    
    /**
     * @notice Create a new governance proposal
     * @param description Human readable description
     * @param proposalType Type of proposal
     * @param executionData Local execution data (if any)
     * @param targetChains Array of chain IDs to execute on
     * @param remoteCalldata Array of calldata for each target chain
     */
    function createProposal(
        string memory description,
        ProposalType proposalType,
        bytes memory executionData,
        uint32[] memory targetChains,
        bytes[] memory remoteCalldata
    ) external {
        require(votingPower[msg.sender] >= minVotingPower, "Insufficient voting power");
        require(targetChains.length == remoteCalldata.length, "Array length mismatch");
        require(!emergencyPaused, "Emergency paused");

        uint256 proposalId = ++proposalCount;
        
        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            description: description,
            votesFor: 0,
            votesAgainst: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + votingPeriod,
            executed: false,
            proposalType: proposalType,
            executionData: executionData,
            targetChains: targetChains,
            remoteCalldata: remoteCalldata
        });

        emit ProposalCreated(proposalId, msg.sender, description, targetChains);
    }

    /**
     * @notice Vote on a proposal
     * @param proposalId ID of the proposal
     * @param voteType Type of vote (FOR/AGAINST/ABSTAIN)
     */
    function vote(uint256 proposalId, VoteType voteType) external {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.id != 0, "Proposal does not exist");
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

        emit VoteCast(proposalId, msg.sender, voteType, weight);
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

        // Execute local actions if any
        if (proposal.executionData.length > 0) {
            _executeLocal(proposal.executionData);
        }

        // Execute remote actions
        bool success = _executeRemote(proposalId, proposal);

        emit ProposalExecuted(proposalId, success, proposal.targetChains);
    }

    // ============ CROSS-CHAIN FUNCTIONS ============
    
    /**
     * @notice Send cross-chain operations to remote executors
     * @param proposalId ID of the proposal
     * @param proposal Proposal struct
     */
    function _executeRemote(uint256 proposalId, Proposal memory proposal) internal returns (bool) {
        require(msg.value > 0, "Must send gas for cross-chain execution");
        
        uint256 totalChains = proposal.targetChains.length;
        uint256 gasPerChain = msg.value / totalChains;
        
        for (uint256 i = 0; i < totalChains; i++) {
            uint32 targetChain = proposal.targetChains[i];
            require(supportedChains[targetChain], "Unsupported chain");
            require(remoteExecutors[targetChain] != address(0), "No executor on target chain");

            // Prepare the message
            bytes memory message = abi.encode(
                proposalId,
                proposal.proposalType,
                proposal.remoteCalldata[i],
                block.timestamp
            );

            // Create operation hash for tracking
            bytes32 operationHash = keccak256(abi.encodePacked(proposalId, targetChain, i));
            
            // Prepare LayerZero options
            bytes memory options = OptionsBuilder.newOptions()
                .addExecutorLzReceiveOption(200000, 0) // 200k gas limit
                .addExecutorOrderedExecutionOption();

            // Send the message
            MessagingFee memory fee = MessagingFee(gasPerChain, 0);
            
            _lzSend(
                targetChain,
                message,
                options,
                fee,
                payable(msg.sender)
            );

            executedOperations[operationHash] = true;
            lastExecutionNonce[targetChain]++;

            emit RemoteOperationSent(proposalId, targetChain, operationHash);
        }

        return true;
    }

    /**
     * @notice Handle responses from remote chains
     * @param _origin Origin information
     * @param _guid Message GUID
     * @param _message Encoded message from remote chain
     * @param _executor Executor address
     * @param _extraData Extra data
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        // Verify the message comes from a trusted remote executor
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
    }

    // ============ EMERGENCY FUNCTIONS ============
    
    /**
     * @notice Emergency pause all operations
     */
    function emergencyPause() external {
        require(emergencyGuardians[msg.sender], "Not an emergency guardian");
        emergencyPaused = true;
        
        // Send emergency pause to all chains
        _sendEmergencyAction("PAUSE_ALL", "Emergency pause activated");
    }

    /**
     * @notice Emergency unpause operations
     */
    function emergencyUnpause() external onlyOwner {
        emergencyPaused = false;
        
        // Send emergency unpause to all chains
        _sendEmergencyAction("UNPAUSE_ALL", "Emergency pause deactivated");
    }

    /**
     * @notice Send emergency action to all supported chains
     * @param action Action to perform
     * @param reason Reason for the action
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

    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @notice Set remote executor for a chain
     * @param chainId LayerZero chain ID
     * @param executor Address of the remote executor
     */
    function setRemoteExecutor(uint32 chainId, address executor) external onlyOwner {
        remoteExecutors[chainId] = executor;
        supportedChains[chainId] = true;
        
        emit RemoteExecutorUpdated(chainId, executor);
    }

    /**
     * @notice Update voting power for an address
     * @param account Address to update
     * @param power New voting power
     */
    function updateVotingPower(address account, uint256 power) external onlyOwner {
        uint256 oldPower = votingPower[account];
        votingPower[account] = power;
        
        totalVotingPower = totalVotingPower - oldPower + power;
    }

    /**
     * @notice Set governance parameters
     * @param _votingPeriod New voting period
     * @param _quorumThreshold New quorum threshold (basis points)
     * @param _minVotingPower Minimum voting power to create proposals
     */
    function setGovernanceParams(
        uint256 _votingPeriod,
        uint256 _quorumThreshold,
        uint256 _minVotingPower
    ) external onlyOwner {
        votingPeriod = _votingPeriod;
        quorumThreshold = _quorumThreshold;
        minVotingPower = _minVotingPower;
    }

    // ============ VIEW FUNCTIONS ============
    
    /**
     * @notice Check if a proposal passed
     * @param proposalId ID of the proposal
     * @return Whether the proposal passed
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
     * @notice Get all supported chain IDs
     * @return Array of supported chain IDs
     */
    function _getAllSupportedChains() internal view returns (uint32[] memory) {
        // This would need to be implemented based on your specific chains
        // For demo purposes, returning a static array
        uint32[] memory chains = new uint32[](4);
        chains[0] = 30102; // Arbitrum Sepolia
        chains[1] = 30109; // Polygon Mumbai
        chains[2] = 30184; // Base Sepolia
        chains[3] = 30106; // Avalanche Fuji
        return chains;
    }

    /**
     * @notice Get proposal details
     * @param proposalId ID of the proposal
     * @return Proposal struct
     */
    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    /**
     * @notice Execute local actions (override this based on your needs)
     * @param data Execution data
     */
    function _executeLocal(bytes memory data) internal virtual {
        // Implementation depends on what local actions you want to support
        // For example: updating local contract parameters, treasury operations, etc.
    }

    // ============ LAYERZERO V2 REQUIRED FUNCTIONS ============
    
    /**
     * @notice Quote the fee for sending a message
     * @param targetChain Target chain ID
     * @param message Message to send
     * @param options LayerZero options
     * @param payInLzToken Whether to pay in LZ token
     * @return MessagingFee struct
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
     * @notice Get the next nonce for a source endpoint
     * @param srcEid Source endpoint ID
     * @param sender Sender address
     * @return Next nonce
     */
    function nextNonce(uint32 srcEid, bytes32 sender) public view virtual returns (uint64) {
        return endpoint.nextNonce(srcEid, sender);
    }

    // Allow contract to receive Ether for cross-chain gas payments
    receive() external payable {}
}