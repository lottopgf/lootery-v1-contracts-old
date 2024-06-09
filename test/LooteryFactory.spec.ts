import { ethers } from 'hardhat'
import {
    Lootery,
    LooteryFactory,
    LooteryFactory__factory,
    Lootery__factory,
    MockRandomiser,
    MockRandomiser__factory,
    TicketSVGRenderer__factory,
    TicketSVGRenderer,
} from '../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { expect } from 'chai'
import { deployProxy } from './helpers/deployProxy'

describe('LooteryFactory', () => {
    let mockRandomiser: MockRandomiser
    let factory: LooteryFactory
    let deployer: SignerWithAddress
    let bob: SignerWithAddress
    let ticketSVGRenderer: TicketSVGRenderer
    let looteryImpl: Lootery
    beforeEach(async () => {
        ;[deployer, bob] = await ethers.getSigners()
        mockRandomiser = await new MockRandomiser__factory(deployer).deploy()
        looteryImpl = await new Lootery__factory(deployer).deploy()
        ticketSVGRenderer = await new TicketSVGRenderer__factory(deployer).deploy()
        factory = await deployProxy({
            deployer,
            implementation: LooteryFactory__factory,
            initData: LooteryFactory__factory.createInterface().encodeFunctionData('init', [
                await looteryImpl.getAddress(),
                await mockRandomiser.getAddress(),
                await ticketSVGRenderer.getAddress(),
            ]),
        })
    })

    it('should set lootery master copy', async () => {
        const oldLooteryMasterCopy = await factory.getLooteryMasterCopy()
        expect(oldLooteryMasterCopy).to.eq(await looteryImpl.getAddress())

        const newLooterMasterCopy = await new Lootery__factory(deployer).deploy()
        await expect(
            factory.connect(bob).setLooteryMasterCopy(await newLooterMasterCopy.getAddress()),
        ).to.be.revertedWithCustomError(factory, 'AccessControlUnauthorizedAccount')
        await factory.setLooteryMasterCopy(await newLooterMasterCopy.getAddress())
        expect(await factory.getLooteryMasterCopy()).to.eq(await newLooterMasterCopy.getAddress())
    })

    it('should set randomiser', async () => {
        const oldRandomiser = await factory.getRandomiser()
        expect(oldRandomiser).to.eq(await mockRandomiser.getAddress())

        const newRandomiser = await new MockRandomiser__factory(deployer).deploy()
        await expect(
            factory.connect(bob).setRandomiser(await newRandomiser.getAddress()),
        ).to.be.revertedWithCustomError(factory, 'AccessControlUnauthorizedAccount')
        await factory.setRandomiser(await newRandomiser.getAddress())
        expect(await factory.getRandomiser()).to.eq(await newRandomiser.getAddress())
    })

    it('should set ticketSVGRenderer', async () => {
        const oldTicketSVGRenderer = await factory.getTicketSVGRenderer()
        expect(oldTicketSVGRenderer).to.eq(await ticketSVGRenderer.getAddress())

        const newTicketSVGRenderer = await new TicketSVGRenderer__factory(deployer).deploy()
        await expect(
            factory.connect(bob).setTicketSVGRenderer(await newTicketSVGRenderer.getAddress()),
        ).to.be.revertedWithCustomError(factory, 'AccessControlUnauthorizedAccount')
        await factory.setTicketSVGRenderer(await newTicketSVGRenderer.getAddress())
        expect(await factory.getTicketSVGRenderer()).to.eq(await newTicketSVGRenderer.getAddress())
    })
})
