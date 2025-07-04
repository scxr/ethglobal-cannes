import { useState } from 'react';
import { useContractRead, useContractWrite, usePrepareContractWrite, useWaitForTransaction } from 'wagmi';

// Example contract ABI (you'll need to replace with your actual contract ABI)
const CONTRACT_ABI = [
  {
    "inputs": [],
    "name": "proposalCount",
    "outputs": [{"type": "uint256"}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [{"type": "uint256"}],
    "name": "getProposal",
    "outputs": [{"type": "tuple", "components": [
      {"type": "uint256", "name": "proposalId"},
      {"type": "address", "name": "proposer"},
      {"type": "string", "name": "description"},
      {"type": "uint256", "name": "votesFor"},
      {"type": "uint256", "name": "votesAgainst"},
      {"type": "uint256", "name": "endTime"},
      {"type": "uint256", "name": "startTime"},
      {"type": "bool", "name": "executed"}
    ]}],
    "stateMutability": "view",
    "type": "function"
  },
  {
    "inputs": [
      {"type": "string", "name": "description"},
      {"type": "uint8", "name": "proposalType"},
      {"type": "bytes", "name": "executionData"},
      {"type": "uint32[]", "name": "targetChainIds"},
      {"type": "bytes32[]", "name": "remoteCallData"}
    ],
    "name": "createProposal",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  }
];

// Replace with your actual contract address
const CONTRACT_ADDRESS = '0xa77fB3F7a9eB499C137Be2e226bBa5CeEAd1f57e'; // Your deployed contract address

export function ContractInteraction() {
  const [proposalId, setProposalId] = useState(1);
  const [description, setDescription] = useState('');
  const [proposalType, setProposalType] = useState(0);

  // Read contract data
  const { data: proposalCount } = useContractRead({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: 'proposalCount',
  });

  const { data: proposal } = useContractRead({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: 'getProposal',
    args: [proposalId],
    enabled: !!proposalId,
  });

  // Prepare contract write
  const { config } = usePrepareContractWrite({
    address: CONTRACT_ADDRESS,
    abi: CONTRACT_ABI,
    functionName: 'createProposal',
    args: [
      description,
      proposalType,
      '0x', // executionData (empty for now)
      [], // targetChainIds (empty for now)
      [] // remoteCallData (empty for now)
    ],
    enabled: !!description,
  });

  // Write to contract
  const { data: writeData, write } = useContractWrite(config);

  // Wait for transaction
  const { isLoading: isPending, isSuccess } = useWaitForTransaction({
    hash: writeData?.hash,
  });

  const handleCreateProposal = () => {
    if (write) {
      write();
    }
  };

  return (
    <div className="contract-interaction">
      <h3>Smart Contract Interaction</h3>
      
      {/* Read Data */}
      <div className="read-section">
        <h4>Read Contract Data</h4>
        <p><strong>Total Proposals:</strong> {proposalCount?.toString() || 'Loading...'}</p>
        
        <div className="proposal-lookup">
          <label>
            Lookup Proposal ID:
            <input
              type="number"
              value={proposalId}
              onChange={(e) => setProposalId(Number(e.target.value))}
              min="1"
            />
          </label>
          {proposal && (
            <div className="proposal-details">
              <p><strong>Description:</strong> {proposal.description}</p>
              <p><strong>Proposer:</strong> {proposal.proposer}</p>
              <p><strong>Votes For:</strong> {proposal.votesFor.toString()}</p>
              <p><strong>Votes Against:</strong> {proposal.votesAgainst.toString()}</p>
              <p><strong>Executed:</strong> {proposal.executed ? 'Yes' : 'No'}</p>
            </div>
          )}
        </div>
      </div>

      {/* Write Data */}
      <div className="write-section">
        <h4>Create New Proposal</h4>
        <div className="form-group">
          <label>
            Description:
            <input
              type="text"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Enter proposal description"
            />
          </label>
        </div>
        
        <div className="form-group">
          <label>
            Proposal Type:
            <select value={proposalType} onChange={(e) => setProposalType(Number(e.target.value))}>
              <option value={0}>TREASURY_DELEGATION</option>
              <option value={1}>EMERGENCY</option>
              <option value={2}>GOVERNANCE_CHANGE</option>
              <option value={3}>PROTOCOL_UPGRADE</option>
              <option value={4}>PARAMETER_CHANGE</option>
              <option value={5}>OTHER</option>
            </select>
          </label>
        </div>

        <button
          onClick={handleCreateProposal}
          disabled={!write || isPending || !description}
          className="create-proposal-btn"
        >
          {isPending ? 'Creating Proposal...' : 'Create Proposal'}
        </button>

        {isSuccess && (
          <div className="success-message">
            <p>✅ Proposal created successfully!</p>
            <p>Transaction Hash: {writeData?.hash}</p>
          </div>
        )}
      </div>
    </div>
  );
} 