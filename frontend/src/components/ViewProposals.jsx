import React from 'react';

const dummyProposals = [
  {
    id: 1,
    title: 'Increase Treasury Allocation',
    description: 'Proposal to increase the DAO treasury allocation by 10%.',
    proposer: '0x1234...abcd',
    votesFor: 42,
    votesAgainst: 10,
    status: 'Active',
  },
  {
    id: 2,
    title: 'Add New Chain Support',
    description: 'Proposal to add support for Polygon zkEVM.',
    proposer: '0xabcd...1234',
    votesFor: 30,
    votesAgainst: 5,
    status: 'Passed',
  },
  {
    id: 3,
    title: 'Emergency Pause',
    description: 'Proposal to pause the protocol due to a security incident.',
    proposer: '0xdead...beef',
    votesFor: 15,
    votesAgainst: 25,
    status: 'Rejected',
  },
];

export function ViewProposals() {
  return (
    <div className="view-proposals">
      <h2>Proposals</h2>
      <ul className="proposal-list">
        {dummyProposals.map((proposal) => (
          <li key={proposal.id} className="proposal-item">
            <h3>{proposal.title}</h3>
            <p><strong>Description:</strong> {proposal.description}</p>
            <p><strong>Proposer:</strong> {proposal.proposer}</p>
            <p><strong>Votes For:</strong> {proposal.votesFor} | <strong>Votes Against:</strong> {proposal.votesAgainst}</p>
            <p><strong>Status:</strong> <span className={`status status-${proposal.status.toLowerCase()}`}>{proposal.status}</span></p>
          </li>
        ))}
      </ul>
    </div>
  );
} 