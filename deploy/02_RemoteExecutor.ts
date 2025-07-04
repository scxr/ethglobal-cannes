import { type DeployFunction } from 'hardhat-deploy/types'
import { EndpointId } from '@layerzerolabs/lz-definitions'

const deployRemoteExecutor: DeployFunction = async (hre) => {
    const { getNamedAccounts, deployments } = hre
    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    console.log(`Deploying RemoteExecutor on ${hre.network.name} testnet`)

    // LayerZero V2 testnet endpoint (same for all testnets)
    const layerZeroEndpoint = '0x6EDCE65403992e310A62460808c4b910D972f10f'
    const masterControllerAddress = process.env.MASTER_CONTROLLER_ADDRESS || '0x0000000000000000000000000000000000000000'

    await deploy('RemoteExecutor', {
        from: deployer,
        args: [
            layerZeroEndpoint,
            deployer,
            EndpointId.SEPOLIA_V2_TESTNET, // Sepolia testnet endpoint ID
            masterControllerAddress,
        ],
        log: true,
        skipIfAlreadyDeployed: false,
    })
}

deployRemoteExecutor.tags = ['RemoteExecutor']
deployRemoteExecutor.skip = (hre) => hre.network.name === 'sepolia'

export default deployRemoteExecutor