import { DeployFunction } from 'hardhat-deploy/types'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { getNamedAccounts, deployments } = hre
    const { deploy } = deployments
    const { deployer } = await getNamedAccounts()

    console.log(`Deploying OmniDaoController on ${hre.network.name} testnet`)

    const layerZeroEndpoint = '0x6EDCE65403992e310A62460808c4b910D972f10f'

    await deploy('OmniDaoController', {
        from: deployer,
        args: [layerZeroEndpoint, deployer],
        log: true,
        skipIfAlreadyDeployed: false,
    })

    // Set governance parameters
    const contract = await hre.ethers.getContract('OmniDaoController')
    
    try {
        const currentPeriod = await contract.votingPeriod()
        if (currentPeriod.toString() === '0') {
            console.log('Setting testnet governance parameters...')
            await contract.setGovernanceParams(
                1 * 60 * 60, // 1 hour voting period
                3000, // 30% quorum
                100   // low minimum voting power
            )
            console.log('Testnet governance parameters set')
        }
    } catch (error) {
        console.log('Could not set governance params:', (error as Error).message)
    }
}

func.tags = ['OmniDaoController']
func.skip = async (hre: HardhatRuntimeEnvironment) => hre.network.name !== 'sepolia'

export default func