import { EndpointId } from '@layerzerolabs/lz-definitions'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'
import { TwoWayConfig, generateConnectionsConfig } from '@layerzerolabs/metadata-tools'
import { OAppEnforcedOption, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

const sepoliaContract: OmniPointHardhat = {
    eid: EndpointId.SEPOLIA_V2_TESTNET,
    contractName: 'OmniDaoController',
}

const arbitrumSepoliaContract: OmniPointHardhat = {
    eid: EndpointId.ARBSEP_V2_TESTNET,
    contractName: 'RemoteExecutor',
}

const amoyContract: OmniPointHardhat = {
    eid: EndpointId.AMOY_V2_TESTNET,
    contractName: 'RemoteExecutor',
}

const bscTestnetContract: OmniPointHardhat = {
    eid: EndpointId.BSC_V2_TESTNET,
    contractName: 'RemoteExecutor',
}

const optimismSepoliaContract: OmniPointHardhat = {
    eid: EndpointId.OPTSEP_V2_TESTNET,
    contractName: 'RemoteExecutor',
}

const baseSepoliaContract: OmniPointHardhat = {
    eid: EndpointId.BASESEP_V2_TESTNET,
    contractName: 'RemoteExecutor',
}

// For this example's simplicity, we will use the same enforced options values for sending to all chains
// For production, you should ensure `gas` is set to the correct value through profiling the gas usage of calling OApp._lzReceive(...) on the destination chain
// To learn more, read https://docs.layerzero.network/v2/concepts/applications/oapp-standard#execution-options-and-enforced-settings
const CONTROLLER_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
    {
        msgType: 1, // SEND message type
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 200000, // Higher gas for proposal execution
        value: 0,
    },
]

const EXECUTOR_ENFORCED_OPTIONS: OAppEnforcedOption[] = [
    {
        msgType: 1, // SEND message type  
        optionType: ExecutorOptionType.LZ_RECEIVE,
        gas: 100000, // Lower gas for response messages
        value: 0,
    },
]

// To connect all the above chains to each other, we need the following pathways:
// Optimism <-> Avalanche
// Optimism <-> Arbitrum
// Avalanche <-> Arbitrum

// With the config generator, pathways declared are automatically bidirectional
// i.e. if you declare A,B there's no need to declare B,A
const pathways: TwoWayConfig[] = [
    // Sepolia Controller <-> Arbitrum Sepolia Executor
    [
        sepoliaContract,
        arbitrumSepoliaContract,
        [['LayerZero Labs'], []], // DVN configuration
        [1, 1], // confirmations
        [EXECUTOR_ENFORCED_OPTIONS, CONTROLLER_ENFORCED_OPTIONS], // enforced options
    ],
    // Sepolia Controller <-> Polygon Amoy Executor
    [
        sepoliaContract,
        amoyContract,
        [['LayerZero Labs'], []],
        [1, 1],
        [EXECUTOR_ENFORCED_OPTIONS, CONTROLLER_ENFORCED_OPTIONS],
    ],
    // Sepolia Controller <-> BSC Testnet Executor
    [
        sepoliaContract,
        bscTestnetContract,
        [['LayerZero Labs'], []],
        [1, 1],
        [EXECUTOR_ENFORCED_OPTIONS, CONTROLLER_ENFORCED_OPTIONS],
    ],
    // Sepolia Controller <-> Optimism Sepolia Executor
    [
        sepoliaContract,
        optimismSepoliaContract,
        [['LayerZero Labs'], []],
        [1, 1],
        [EXECUTOR_ENFORCED_OPTIONS, CONTROLLER_ENFORCED_OPTIONS],
    ],
    // Sepolia Controller <-> Base Sepolia Executor
    [
        sepoliaContract,
        baseSepoliaContract,
        [['LayerZero Labs'], []],
        [1, 1],
        [EXECUTOR_ENFORCED_OPTIONS, CONTROLLER_ENFORCED_OPTIONS],
    ],
]
export default async function () {
    // Generate the connections config based on the pathways
    const connections = await generateConnectionsConfig(pathways)
    
    return {
        contracts: [
            { contract: sepoliaContract },
            { contract: arbitrumSepoliaContract },
            { contract: amoyContract },
            { contract: bscTestnetContract },
            { contract: optimismSepoliaContract },
            { contract: baseSepoliaContract },
        ],
        connections,
    }
}