import { ethers, run } from 'hardhat'
import {
    ERC1967Proxy__factory,
    LooteryFactory__factory,
    Lootery__factory,
} from '../typechain-types'

interface Config {
    [chainId: string]: {
        anyrand: `0x${string}`
    }
}

const config: Config = {
    '8453': {
        /** base mainnet; drand on BN254 v2 (SVDW) */
        anyrand: '0xe3a8eca966457bfd7e0049543e07e8b691b3930e',
    },
    '666666666': {
        anyrand: '0x9309bd93a8b662d315Ce0D43bb95984694F120Cb',
    },
}

async function main() {
    const [deployer] = await ethers.getSigners()
    const chainId = await ethers.provider.getNetwork().then((network) => network.chainId)
    const { anyrand } = config[chainId.toString() as keyof typeof config]

    const looteryImpl = await new Lootery__factory(deployer)
        .deploy()
        .then((tx) => tx.waitForDeployment())
    const factoryImpl = await new LooteryFactory__factory(deployer)
        .deploy()
        .then((tx) => tx.waitForDeployment())
    const initData = LooteryFactory__factory.createInterface().encodeFunctionData('init', [
        await looteryImpl.getAddress(),
        anyrand,
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
