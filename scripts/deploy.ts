import { ethers, run } from 'hardhat'
import {
    ERC1967Proxy__factory,
    LooteryFactory__factory,
    Lootery__factory,
} from '../typechain-types'

const RNGESUS_ADDRESS =
    '0xFBF562a98aB8584178efDcFd09755FF9A1e7E3a2' /** base mainnet; drand on BN254 v1 (old) */

async function main() {
    const [deployer] = await ethers.getSigners()

    const looteryImpl = await new Lootery__factory(deployer)
        .deploy()
        .then((tx) => tx.waitForDeployment())
    const factoryImpl = await new LooteryFactory__factory(deployer)
        .deploy()
        .then((tx) => tx.waitForDeployment())
    const initData = LooteryFactory__factory.createInterface().encodeFunctionData('init', [
        await looteryImpl.getAddress(),
        RNGESUS_ADDRESS,
    ])
    const factoryProxyArgs: Parameters<ERC1967Proxy__factory['deploy']> = [
        await factoryImpl.getAddress(),
        initData,
    ]
    const factoryProxy = await new ERC1967Proxy__factory(deployer)
        .deploy(...factoryProxyArgs)
        .then((tx) => tx.waitForDeployment())
    const factory = await LooteryFactory__factory.connect(await factoryProxy.getAddress(), deployer)
    console.log(`LooteryFactory deployed at: ${await factory.getAddress()}`)

    await new Promise((resolve) => setTimeout(resolve, 30_000))
    await run('verify:verify', {
        address: await looteryImpl.getAddress(),
        constructorArguments: [],
    })
    await run('verify:verify', {
        address: await factoryImpl.getAddress(),
        constructorArguments: [],
    })
    await run('verify:verify', {
        address: await factoryProxy.getAddress(),
        constructorArguments: factoryProxyArgs,
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
