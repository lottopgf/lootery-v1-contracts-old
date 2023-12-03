import { ethers, run } from 'hardhat'
import { Lootery__factory, MockRandomiser__factory } from '../typechain-types'
import { parseEther } from 'ethers'

async function main() {
    const [deployer] = await ethers.getSigners()

    // **TESTNET ONLY**
    const mockRandomiser = await new MockRandomiser__factory(deployer)
        .deploy()
        .then((tx) => tx.waitForDeployment())
    console.log(`MockRandomiser deployed at: ${await mockRandomiser.getAddress()}`)

    const looteryArgs: Parameters<Lootery__factory['deploy']> = [
        'Test Lootery',
        'TLOOT',
        5,
        10,
        10 * 60 /** 10mins */,
        parseEther('0.001'),
        5000,
        (await mockRandomiser).getAddress(),
    ]
    const lootery = await new Lootery__factory(deployer)
        .deploy(...looteryArgs)
        .then((tx) => tx.waitForDeployment())
    console.log(`Lootery deployed at: ${await lootery.getAddress()}`)

    await new Promise((resolve) => setTimeout(resolve, 30_000))
    await run('verify:verify', {
        address: await mockRandomiser.getAddress(),
        constructorArguments: [],
    })
    await run('verify:verify', {
        address: await lootery.getAddress(),
        constructorArguments: looteryArgs,
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
