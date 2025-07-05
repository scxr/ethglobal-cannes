import React, { useState } from 'react';
import { sepolia, arbitrumSepolia, optimismSepolia, baseSepolia } from 'wagmi/chains';
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import contractAbi from '../assets/abis/OmniDaoController.json';

const SUPPORTED_CHAINS = [
  sepolia,
  arbitrumSepolia,
  optimismSepolia,
  baseSepolia,
];
const PROPOSAL_TYPES = {
    'TREASURY_DELEGATION': 0,
    'EMERGENCY': 1,
    'GOVERNANCE_CHANGE': 2,
    'PROTOCOL_UPGRADE': 3,
    'PARAMETER_CHANGE': 4,
    'OTHER': 5
  };
  
const TOKENS = [
  { symbol: 'ETH', name: 'Ethereum' },
  { symbol: 'ARB', name: 'Arbitrum' },
  { symbol: 'OP', name: 'Optimism' },
  { symbol: 'USDC', name: 'USD Coin' },
  // Add more as needed
];

const CONTRACT_ADDRESS = '0x1dCEd2fF4Db43Dd10B15140E3FDc590b01f3F321'; // replace with your address

export function CreateProposal() {
  const { address } = useAccount();
  
  const { data: txHash, writeContract, isPending, error: writeError } = useWriteContract();
  const { isSuccess, isLoading } = useWaitForTransactionReceipt({ hash: txHash });

  const [title, setTitle] = useState('');
  const [errors, setErrors] = useState([]);
  const [description, setDescription] = useState('');
  const [type, setType] = useState('TREASURY_DELEGATION');
  const [selectedChains, setSelectedChains] = useState([]);
  const [emergencyAction, setEmergencyAction] = useState('pause');
  const [swapFrom, setSwapFrom] = useState('');
  const [swapTo, setSwapTo] = useState('');
  const [swapAmount, setSwapAmount] = useState('');
  const [submitted, setSubmitted] = useState(false);
  const [swaps, setSwaps] = useState([
    { from: 'ETH', to: 'ARB', percent: '' }
  ]);
  // Effect to handle transaction success
  React.useEffect(() => {
    if (isSuccess) {
      setSubmitted(true);
    }
  }, [isSuccess]);

  const handleChainToggle = (chainId) => {
    setSelectedChains((prev) =>
      prev.includes(chainId)
        ? prev.filter((id) => id !== chainId)
        : [...prev, chainId]
    );
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    console.log('Address:', address);
    console.log('Contract address:', CONTRACT_ADDRESS);
    console.log('Args:', [title, description, swaps]);
    
    const validationErrors = validate();
    if (validationErrors.length > 0) {
      setErrors(validationErrors);
      return;
    }
    setErrors([]);
  
    try {
      console.log('About to call writeContract...');
      await writeContract({
        address: CONTRACT_ADDRESS,
        abi: contractAbi,
        functionName: 'createProposal',
        args: [description, PROPOSAL_TYPES[type], "0x" , [1], ["0x0000000000000000000000000000000000000000000000000000000000000000"]],
        account: address,
      });
      console.log('writeContract called successfully');
    } catch (err) {
      console.error('Error calling writeContract:', err);
      setErrors([err.message || 'Contract call failed']);
    }
  };

  const handleSwapChange = (idx, field, value) => {
    setSwaps(swaps =>
      swaps.map((swap, i) =>
        i === idx ? { ...swap, [field]: value } : swap
      )
    );
  };

  const addSwap = () => setSwaps([...swaps, { from: '', to: '', percent: '' }]);
  const removeSwap = idx => setSwaps(swaps => swaps.filter((_, i) => i !== idx));

  const validate = () => {
    const errs = [];
    if (!title.trim()) errs.push("Title is required.");
    if (!description.trim()) errs.push("Description is required.");

    if (type === "TREASURY_DELEGATION") {
      if (swaps.length === 0) errs.push("At least one swap is required.");
      let totalPercent = 0;
      swaps.forEach((swap, idx) => {
        if (!swap.from) errs.push(`Swap #${idx + 1}: 'From' token is required.`);
        if (!swap.to) errs.push(`Swap #${idx + 1}: 'To' token is required.`);
        if (swap.from === swap.to) errs.push(`Swap #${idx + 1}: 'From' and 'To' tokens must be different.`);
        if (!swap.percent) errs.push(`Swap #${idx + 1}: Percent is required.`);
        if (swap.percent <= 0 || swap.percent > 100) errs.push(`Swap #${idx + 1}: Percent must be between 1 and 100.`);
        totalPercent += Number(swap.percent) || 0;
      });
      if (totalPercent > 100) errs.push("Total percent for all swaps cannot exceed 100%.");
    } else {
      if (selectedChains.length === 0) errs.push("Select at least one supported chain.");
    }

    return errs;
  };

  if (submitted) {
    return (
      <div className="create-proposal-success">
        <h2>Proposal Submitted!</h2>
        <p>Your proposal has been created (dummy, not on-chain).</p>
        <p><strong>Selected Chains:</strong> {selectedChains.map(id => {
          const chain = SUPPORTED_CHAINS.find(c => c.id === id);
          return chain ? chain.name : id;
        }).join(', ')}</p>
        <button onClick={() => setSubmitted(false)}>Create Another</button>
      </div>
    );
  }

  return (
    <div className="create-proposal">
      <h2>Create Proposal</h2>
      <form onSubmit={handleSubmit} className="proposal-form">
        <div className="form-group">
          <label>
            Title:
            <input
              type="text"
              value={title}
              onChange={e => setTitle(e.target.value)}
              required
            />
          </label>
        </div>
        <div className="form-group">
          <label>
            Description:
            <textarea
              value={description}
              onChange={e => setDescription(e.target.value)}
              required
            />
          </label>
        </div>
        <div className="form-group">
          <label>
            Type:
            <select value={type} onChange={e => setType(e.target.value)}>
              <option value="TREASURY_DELEGATION">Treasury Delegation</option>
              <option value="EMERGENCY">Emergency</option>
              <option value="GOVERNANCE_CHANGE">Governance Change</option>
              <option value="PROTOCOL_UPGRADE">Protocol Upgrade</option>
              <option value="PARAMETER_CHANGE">Parameter Change</option>
              <option value="OTHER">Other</option>
            </select>
          </label>
        </div>
        {/* Dynamic fields based on proposal type */}
        {type === 'EMERGENCY' && (
          <div className="form-group">
            <label>
              Emergency Action:
              <select value={emergencyAction} onChange={e => setEmergencyAction(e.target.value)}>
                <option value="pause">Pause</option>
                <option value="unpause">Unpause</option>
                <option value="other">Other</option>
              </select>
            </label>
          </div>
        )}
        {type === 'TREASURY_DELEGATION' && (
          <div className="form-group">
            <label>Swaps:</label>
            {swaps.map((swap, idx) => (
              <div key={idx} style={{ display: 'flex', gap: '1em', alignItems: 'center', marginBottom: '0.5em' }}>
                <select
                  value={swap.from}
                  onChange={e => handleSwapChange(idx, 'from', e.target.value)}
                  required
                >
                  <option value="">From</option>
                  {TOKENS.map(token => (
                    <option key={token.symbol} value={token.symbol}>{token.name}</option>
                  ))}
                </select>
                <span>→</span>
                <select
                  value={swap.to}
                  onChange={e => handleSwapChange(idx, 'to', e.target.value)}
                  required
                >
                  <option value="">To</option>
                  {TOKENS.map(token => (
                    <option key={token.symbol} value={token.symbol}>{token.name}</option>
                  ))}
                </select>
                <input
                  type="number"
                  min="0"
                  max="100"
                  value={swap.percent}
                  onChange={e => handleSwapChange(idx, 'percent', e.target.value)}
                  placeholder="%"
                  style={{ width: '4em' }}
                  required
                />
                <span>%</span>
                {swaps.length > 1 && (
                  <button type="button" onClick={() => removeSwap(idx)} style={{ color: 'red' }}>✕</button>
                )}
              </div>
            ))}
            <button type="button" onClick={addSwap} style={{ marginTop: '0.5em' }}>Add Swap</button>
          </div>
        )}
        {type !== 'TREASURY_DELEGATION' && (
          <div className="form-group">
            <label>
              Select Supported Chains:
              <div className="chain-checklist">
                {SUPPORTED_CHAINS.map(chain => (
                  <label key={chain.id} className="chain-checkbox">
                    <input
                      type="checkbox"
                      checked={selectedChains.includes(chain.id)}
                      onChange={() => handleChainToggle(chain.id)}
                    />
                    {chain.name}
                  </label>
                ))}
              </div>
            </label>
          </div>
        )}

        {errors.length > 0 && (
          <div style={{ color: 'red', marginBottom: '1em' }}>
            <ul>
              {errors.map((err, i) => <li key={i}>{err}</li>)}
            </ul>
          </div>
        )}

        {isPending && <p>Transaction pending...</p>}
        {isLoading && <p>Waiting for confirmation...</p>}
        {isSuccess && <p style={{ color: 'green' }}>Proposal submitted on-chain!</p>}
        {writeError && <p style={{ color: 'red' }}>{writeError.message}</p>}

        <button type="submit" className="action-button">Submit Proposal</button>
      </form>
    </div>
  );
}