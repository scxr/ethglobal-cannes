import { useState } from 'react'
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount, useBalance, useChainId, useSwitchChain } from 'wagmi';
import { ViewProposals } from './components/ViewProposals';
import { CreateProposal } from './components/CreateProposal';
// import { ContractInteraction } from './components/ContractInteraction';
import './App.css'

function App() {
  const [showProposals, setShowProposals] = useState(false);
  const [showCreateProposal, setShowCreateProposal] = useState(false);
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { chains, switchNetwork } = useSwitchChain();
  const { data: balance } = useBalance({
    address,
  });

  if (showCreateProposal) {
    return <CreateProposal />;
  }

  if (showProposals) {
    return <ViewProposals />;
  }

  return (
    <div className="App">
      <header className="App-header">
        <h1>OmniDAO - Cross-Chain Governance</h1>
        
        {/* Rainbow Kit Connect Button */}
        <ConnectButton />
        
        {/* Example usage after connection */}
        {isConnected && (
          <div className="wallet-info">
            <h2>Wallet Information</h2>
            <p><strong>Address:</strong> {address}</p>
            <p><strong>Network:</strong> {chainId}</p>
            <p><strong>Balance:</strong> {balance?.formatted} {balance?.symbol}</p>
            
            {/* Network Switcher */}
            <div className="network-switcher">
              <h3>Switch Network:</h3>
              <div className="network-buttons">
                {chains.map((targetChain) => (
                  <button
                    key={targetChain.id}
                    onClick={() => switchNetwork?.(targetChain.id)}
                    disabled={!switchNetwork || targetChain.id === chain?.id}
                    className="network-button"
                  >
                    {targetChain.name}
                  </button>
                ))}
              </div>
            </div>
            
            {/* Smart Contract Interaction */}
            {/* <ContractInteraction /> */}
            
            {/* Example DAO Actions */}
            <div className="dao-actions">
              <h3>DAO Actions</h3>
              <button className="action-button" onClick={() => setShowCreateProposal(true)}>
                Create Proposal
              </button>
              <button className="action-button" onClick={() => setShowProposals(true)}>
                View Proposals
              </button>

            </div>
          </div>
        )}
        
        {!isConnected && (
          <div className="welcome">
            <p>Connect your wallet to interact with OmniDAO</p>
            <p>This is a cross-chain governance platform built with LayerZero</p>
          </div>
        )}
      </header>
    </div>
  )
}

export default App