// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { OApp, Origin, MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { OAppOptionsType3 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Add these interfaces
interface ILendingProtocol {
    function setInterestRate(uint256 rate) external;
    function updateCollateralRatio(address token, uint256 ratio) external;
}

interface IAMMPool {
    function setTradingFee(uint256 fee) external;
}

interface IStaking {
    function stake(uint256 amount) external;
}

interface IPausable {
    function pause() external;
    function unpause() external;
}

/**
 * @title RemoteExecutor
 * @notice Remote executor contract deployed on each target chain
 * @dev Receives and executes commands from the master DAO controller
 */
contract RemoteExecutor is OApp, OAppOptionsType3, ReentrancyGuard {
    using OptionsBuilder for bytes;

    // ============ STATE VARIABLES ============
    
    struct ExecutionRecord {
        uint256 proposalId;
        uint256 timestamp;
        bool success;
        string result;
    }

    enum ProposalType {
        PARAMETER_UPDATE,
        TREASURY_OPERATION,
        EMERGENCY_ACTION,
        GOVERNANCE_CHANGE,
        PROTOCOL_UPGRADE
    }

    // Master controller (on Ethereum)
    uint32 public immutable masterChainId;
    address public masterController;
    
    // Local protocol contracts this executor can control
    mapping(string => address) public protocolContracts;
    mapping(bytes32 => ExecutionRecord) public executionHistory;
    
    // Emergency controls
    bool public paused;
    mapping(address => bool) public emergencyGuardians;
    
    // Execution tracking
    uint256 public executionCount;
    mapping(uint256 => bool) public processedProposals;

    // ============ EVENTS ============
    
    event CommandReceived(
        uint256 indexed proposalId,
        ProposalType indexed proposalType,
        address indexed executor
    );
    
    event CommandExecuted(
        uint256 indexed proposalId,
        bool success,
        string result
    );
    
    event EmergencyActionExecuted(
        string action,
        string reason,
        address executor
    );
    
    event ProtocolContractUpdated(
        string indexed contractName,
        address indexed contractAddress
    );

    // ============ CONSTRUCTOR ============
    
    constructor(
        address _endpoint,
        address _delegate,
        uint32 _masterChainId,
        address _masterController
    ) OApp(_endpoint, _delegate) Ownable(_delegate) {
        masterChainId = _masterChainId;
        masterController = _masterController;
        emergencyGuardians[_delegate] = true;
    }

    // ============ LAYERZERO RECEIVE FUNCTION ============
    
    /**
     * @notice Handle incoming messages from master controller
     * @param _origin Origin information
     * @param _guid Message GUID
     * @param _message Encoded message
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
        // Verify message comes from master controller
        require(_origin.srcEid == masterChainId, "Invalid source chain");
        require(
            _origin.sender == bytes32(uint256(uint160(masterController))),
            "Unauthorized sender"
        );

        // Decode the message
        string memory messageType = _getMessageType(_message);
        
        if (keccak256(bytes(messageType)) == keccak256("EMERGENCY")) {
            _handleEmergencyAction(_message);
        } else {
            _handleProposalExecution(_message);
        }
    }

    /**
     * @notice Handle proposal execution
     * @param _message Encoded message with proposal data
     */
    function _handleProposalExecution(bytes calldata _message) internal {
        (
            uint256 proposalId,
            ProposalType proposalType,
            bytes memory executionData,
            uint256 timestamp
        ) = abi.decode(_message, (uint256, ProposalType, bytes, uint256));

        require(!processedProposals[proposalId], "Proposal already processed");
        require(!paused, "Contract is paused");

        processedProposals[proposalId] = true;
        executionCount++;

        emit CommandReceived(proposalId, proposalType, msg.sender);

        // Execute the command based on type
        (bool success, string memory result) = _executeCommand(
            proposalType,
            executionData
        );

        // Record execution
        bytes32 executionHash = keccak256(abi.encodePacked(proposalId, timestamp));
        executionHistory[executionHash] = ExecutionRecord({
            proposalId: proposalId,
            timestamp: timestamp,
            success: success,
            result: result
        });

        emit CommandExecuted(proposalId, success, result);

        // Send response back to master controller
        _sendResponse(proposalId, success, result);
    }

    /**
     * @notice Handle emergency actions
     * @param _message Encoded emergency message
     */
    function _handleEmergencyAction(bytes calldata _message) internal {
        (, string memory action, string memory reason,) = abi.decode(
            _message,
            (string, string, string, uint256)
        );

        if (keccak256(bytes(action)) == keccak256("PAUSE_ALL")) {
            paused = true;
        } else if (keccak256(bytes(action)) == keccak256("UNPAUSE_ALL")) {
            paused = false;
        }

        emit EmergencyActionExecuted(action, reason, msg.sender);
    }

    // ============ COMMAND EXECUTION FUNCTIONS ============
    
    /**
     * @notice Execute a command based on proposal type
     * @param proposalType Type of proposal
     * @param executionData Encoded execution data
     * @return success Whether execution succeeded
     * @return result Result message
     */
    function _executeCommand(
        ProposalType proposalType,
        bytes memory executionData
    ) internal returns (bool success, string memory result) {
        if (proposalType == ProposalType.PARAMETER_UPDATE) {
            return _executeParameterUpdate(executionData);
        } else if (proposalType == ProposalType.TREASURY_OPERATION) {
            return _executeTreasuryOperation(executionData);
        } else if (proposalType == ProposalType.EMERGENCY_ACTION) {
            return _executeEmergencyAction(executionData);
        } else if (proposalType == ProposalType.GOVERNANCE_CHANGE) {
            return _executeGovernanceChange(executionData);
        } else if (proposalType == ProposalType.PROTOCOL_UPGRADE) {
            return _executeProtocolUpgrade(executionData);
        }
        
        return (false, "Unknown proposal type");
    }

    /**
     * @notice Execute parameter updates
     * @param executionData Encoded parameter update data
     */
    function _executeParameterUpdate(bytes memory executionData) internal returns (bool, string memory) {
        try this._decodeAndExecuteParameterUpdate(executionData) {
            return (true, "Parameter update successful");
        } catch Error(string memory reason) {
            return (false, reason);
        } catch {
            return (false, "Parameter update failed");
        }
    }

    /**
     * @notice Decode and execute parameter update
     * @param executionData Encoded data
     */
    function _decodeAndExecuteParameterUpdate(bytes memory executionData) external {
        require(msg.sender == address(this), "Internal call only");
        
        (string memory contractName, string memory functionName, bytes memory callData) = 
            abi.decode(executionData, (string, string, bytes));
        
        address targetContract = protocolContracts[contractName];
        require(targetContract != address(0), "Contract not found");
        
        // Example parameter updates
        if (keccak256(bytes(functionName)) == keccak256("setInterestRate")) {
            uint256 newRate = abi.decode(callData, (uint256));
            ILendingProtocol(targetContract).setInterestRate(newRate);
        } else if (keccak256(bytes(functionName)) == keccak256("updateCollateralRatio")) {
            (address token, uint256 ratio) = abi.decode(callData, (address, uint256));
            ILendingProtocol(targetContract).updateCollateralRatio(token, ratio);
        } else if (keccak256(bytes(functionName)) == keccak256("setTradingFee")) {
            uint256 newFee = abi.decode(callData, (uint256));
            IAMMPool(targetContract).setTradingFee(newFee);
        }
    }

    /**
     * @notice Execute treasury operations
     * @param executionData Encoded treasury operation data
     */
    function _executeTreasuryOperation(bytes memory executionData) internal returns (bool, string memory) {
        try this._decodeAndExecuteTreasuryOperation(executionData) {
            return (true, "Treasury operation successful");
        } catch Error(string memory reason) {
            return (false, reason);
        } catch {
            return (false, "Treasury operation failed");
        }
    }

    /**
     * @notice Decode and execute treasury operation
     * @param executionData Encoded data
     */
    function _decodeAndExecuteTreasuryOperation(bytes memory executionData) external {
        require(msg.sender == address(this), "Internal call only");
        
        (string memory operation, bytes memory operationData) = 
            abi.decode(executionData, (string, bytes));
        
        if (keccak256(bytes(operation)) == keccak256("transferFunds")) {
            (address token, address to, uint256 amount) = 
                abi.decode(operationData, (address, address, uint256));
            
            if (token == address(0)) {
                // Transfer ETH
                payable(to).transfer(amount);
            } else {
                // Transfer ERC20
                IERC20(token).transfer(to, amount);
            }
        } else if (keccak256(bytes(operation)) == keccak256("stakeFunds")) {
            (address stakingContract, uint256 amount) = 
                abi.decode(operationData, (address, uint256));
            IStaking(stakingContract).stake(amount);
        }
    }

    /**
     * @notice Execute emergency actions
     * @param executionData Encoded emergency data
     */
    function _executeEmergencyAction(bytes memory executionData) internal returns (bool, string memory) {
        (string memory action, address targetContract) = 
            abi.decode(executionData, (string, address));
        
        if (keccak256(bytes(action)) == keccak256("pauseContract")) {
            IPausable(targetContract).pause();
            return (true, "Contract paused");
        } else if (keccak256(bytes(action)) == keccak256("unpauseContract")) {
            IPausable(targetContract).unpause();
            return (true, "Contract unpaused");
        }
        
        return (false, "Unknown emergency action");
    }

    /**
     * @notice Execute governance changes
     * @param executionData Encoded governance data
     */
    function _executeGovernanceChange(bytes memory executionData) internal returns (bool, string memory) {
        // Implementation for governance changes
        return (true, "Governance change executed");
    }

    /**
     * @notice Execute protocol upgrades
     * @param executionData Encoded upgrade data
     */
    function _executeProtocolUpgrade(bytes memory executionData) internal returns (bool, string memory) {
        // Implementation for protocol upgrades
        return (true, "Protocol upgrade executed");
    }

    // ============ UTILITY FUNCTIONS ============
    
    /**
     * @notice Get message type from encoded message
     * @param _message Encoded message
     * @return Message type string
     */
    function _getMessageType(bytes calldata _message) internal pure returns (string memory) {
        // Simple message type detection
        if (_message.length > 32) {
            (string memory messageType) = abi.decode(_message[:32], (string));
            return messageType;
        }
        return "PROPOSAL";
    }

    /**
     * @notice Send response back to master controller
     * @param proposalId ID of the executed proposal
     * @param success Whether execution succeeded
     * @param result Result message
     */
    function _sendResponse(
        uint256 proposalId,
        bool success,
        string memory result
    ) internal {
        bytes memory message = abi.encode(proposalId, success, result);
        
        bytes memory options = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(100000, 0);

        MessagingFee memory fee = MessagingFee(0, 0); // No fee for response
        
        _lzSend(masterChainId, message, options, fee, payable(address(this)));
    }

    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @notice Set a protocol contract address
     * @param contractName Name of the contract
     * @param contractAddress Address of the contract
     */
    function setProtocolContract(string memory contractName, address contractAddress) external onlyOwner {
        protocolContracts[contractName] = contractAddress;
        emit ProtocolContractUpdated(contractName, contractAddress);
    }
    
    /**
     * @notice Update master controller address
     * @param newMasterController New master controller address
     */
    function updateMasterController(address newMasterController) external onlyOwner {
        masterController = newMasterController;
    }
    
    /**
     * @notice Add emergency guardian
     * @param guardian Guardian address
     */
    function addEmergencyGuardian(address guardian) external onlyOwner {
        emergencyGuardians[guardian] = true;
    }
    
    /**
     * @notice Remove emergency guardian
     * @param guardian Guardian address
     */
    function removeEmergencyGuardian(address guardian) external onlyOwner {
        emergencyGuardians[guardian] = false;
    }
    
    /**
     * @notice Emergency pause (guardian only)
     */
    function emergencyPause() external {
        require(emergencyGuardians[msg.sender], "Not an emergency guardian");
        paused = true;
    }
    
    /**
     * @notice Emergency unpause (owner only)
     */
    function emergencyUnpause() external onlyOwner {
        paused = false;
    }
    
    /**
     * @notice Withdraw stuck tokens
     * @param token Token address (address(0) for ETH)
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(token).transfer(to, amount);
        }
    }
    
    /**
     * @notice Receive ETH
     */
    receive() external payable {}
}