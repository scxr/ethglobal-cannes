import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { EndpointId } from '@layerzerolabs/lz-definitions'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts, deployments } = hre
    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    console.log(`Deploying RemoteExecutor on ${hre.network.name} testnet`)

    const layerZeroEndpoint = '0x6EDCE65403992e310A62460808c4b910D972f10f'
    const masterControllerAddress = process.env.MASTER_CONTROLLER_ADDRESS || '0x0000000000000000000000000000000000000000'

    await deploy('RemoteExecutor', {
        from: deployer,
        args: [
            layerZeroEndpoint,
            deployer,
            EndpointId.SEPOLIA_V2_TESTNET,
            masterControllerAddress,
        ],
        log: true,
        skipIfAlreadyDeployed: false,
    })
}

func.tags = ['RemoteExecutor']
func.skip = async (hre: HardhatRuntimeEnvironment) => hre.network.name === 'sepolia'

export default func