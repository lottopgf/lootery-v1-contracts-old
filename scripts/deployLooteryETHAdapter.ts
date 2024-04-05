import { ethers, run } from 'hardhat'
import { LooteryETHAdapter__factory } from '../typechain-types'
import { config } from './config'

async function main() {
    const chainId = await ethers.provider.getNetwork().then((network) => network.chainId)
    const [deployer] = await ethers.getSigners()
    const looteryEthAdapterArgs: Parameters<LooteryETHAdapter__factory['deploy']> = [
        config[String(chainId)].weth,
    ]
    const looteryEthAdapter = await new LooteryETHAdapter__factory(deployer).deploy(
        ...looteryEthAdapterArgs,
    )
    console.log(`Deployed LooteryETHAdapter to: ${await looteryEthAdapter.getAddress()}`)

    await new Promise((resolve) => setTimeout(resolve, 30_000))
    await run('verify:verify', {
        address: await looteryEthAdapter.getAddress(),
        constructorArguments: looteryEthAdapterArgs,
    })
}

main()
    .then(() => {
        console.log('Done')
        process.exit(0)
    })
    .catch((err) => {
        console.error(err)
        process.exit(1)
    })
