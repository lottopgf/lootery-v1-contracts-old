import { ethers, ignition, run } from 'hardhat'
import { LooteryFactory__factory } from '../typechain-types'
import { config } from './config'
import LooteryImplModule from '../ignition/modules/LooteryImpl'
import LooteryFactoryModule from '../ignition/modules/LooteryFactory'
import LooteryETHAdapterModule from '../ignition/modules/LooteryETHAdapter'
import TicketSVGRendererModule from '../ignition/modules/TicketSVGRenderer'

async function main() {
    const chainId = await ethers.provider.getNetwork().then((network) => network.chainId)
    const { anyrand, weth } = config[chainId.toString() as keyof typeof config]

    const { ticketSVGRenderer } = await ignition.deploy(TicketSVGRendererModule)
    const { looteryImpl } = await ignition.deploy(LooteryImplModule)
    const factoryInitData = LooteryFactory__factory.createInterface().encodeFunctionData('init', [
        await looteryImpl.getAddress(),
        anyrand,
        await ticketSVGRenderer.getAddress(),
    ])
    const { looteryFactoryProxy } = await ignition.deploy(LooteryFactoryModule, {
        parameters: {
            LooteryFactory: {
                factoryInitData,
            },
        },
    })
    console.log(`LooteryFactory deployed at: ${await looteryFactoryProxy.getAddress()}`)

    // Periphery
    const { looteryEthAdapter } = await ignition.deploy(LooteryETHAdapterModule, {
        parameters: {
            LooteryETHAdapter: {
                weth,
            },
        },
    })
    console.log(`LooteryETHAdapter deployed at: ${await looteryEthAdapter.getAddress()}`)

    // Verify all
    await run(
        {
            scope: 'ignition',
            task: 'verify',
        },
        {
            // Not sure this is stable, but works for now
            deploymentId: `chain-${chainId.toString()}`,
        },
    )
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
