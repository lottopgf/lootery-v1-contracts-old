import { ethers } from 'hardhat'
import { time } from '@nomicfoundation/hardhat-network-helpers'
import {
    LooteryFactory,
    LooteryFactory__factory,
    Lootery__factory,
    MockRandomiser,
    MockRandomiser__factory,
} from '../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { parseEther } from 'ethers'
import { expect } from 'chai'
import { deployProxy } from './helpers/deployProxy'

function keccak(balls: bigint[]) {
    return ethers.solidityPackedKeccak256(
        balls.map((_) => 'uint8'),
        balls,
    )
}

describe('Lootery', () => {
    let mockRandomiser: MockRandomiser
    let factory: LooteryFactory
    let deployer: SignerWithAddress
    let bob: SignerWithAddress
    beforeEach(async () => {
        ;[deployer, bob] = await ethers.getSigners()

        mockRandomiser = await new MockRandomiser__factory(deployer).deploy()

        const looteryImpl = await new Lootery__factory(deployer).deploy()
        factory = await deployProxy({
            deployer,
            implementation: LooteryFactory__factory,
            initData: LooteryFactory__factory.createInterface().encodeFunctionData('init', [
                await looteryImpl.getAddress(),
                await mockRandomiser.getAddress(),
            ]),
        })
    })

    /**
     * Helper to create lotteries using the factory
     * @param args Lootery init args
     * @returns Lootery instance
     */
    async function createLotto(...args: Parameters<LooteryFactory['create']>) {
        const lottoAddress = await factory.computeNextAddress()
        await factory.create(...args)
        return Lootery__factory.connect(lottoAddress, deployer)
    }

    it('runs happy path', async () => {
        // Launch a lottery
        const gamePeriod = BigInt(1 * 60 * 60) // 1h
        const lotto = await createLotto(
            'Lotto',
            'LOTTO',
            5,
            69,
            gamePeriod,
            parseEther('0.1'),
            5000, // 50%
        )

        // Allow seeding jackpot
        await lotto.seedJackpot({
            value: parseEther('10'),
        })
        expect(await ethers.provider.getBalance(await lotto.getAddress())).to.eq(parseEther('10'))

        const gameId = await lotto.currentGameId()

        // Bob purchases a winning ticket
        const winningTicket = [3n, 11n, 22n, 29n, 42n]
        await lotto.connect(bob).purchase(
            [
                {
                    whomst: bob.address,
                    picks: winningTicket,
                },
            ],
            {
                value: parseEther('0.1'),
            },
        )
        // Bob receives NFT ticket
        expect(await lotto.balanceOf(bob.address)).to.eq(1)
        const ticketTokenId = 1
        expect(await lotto.ownerOf(ticketTokenId)).to.eq(bob.address)

        // Draw
        await time.increase(gamePeriod)
        await lotto.draw()
        const { requestId } = await lotto.randomnessRequest()
        expect(requestId).to.not.eq(0n)

        // Fulfill w/ mock randomiser
        const fulfilmentTx = await mockRandomiser
            .fulfillRandomWords(requestId, [6942069420])
            .then((tx) => tx.wait(1))
        const [emittedGameId, emittedBalls] = lotto.interface.decodeEventLog(
            'GameFinalised',
            fulfilmentTx?.logs?.[0].data!,
            fulfilmentTx?.logs?.[0].topics,
        ) as unknown as [bigint, bigint[]]
        expect(emittedGameId).to.eq(0)
        expect(emittedBalls).to.deep.eq(winningTicket)
        expect(await lotto.winningPickIds(emittedGameId)).to.eq(keccak(emittedBalls))

        // Bob claims entire pot
        const jackpot = await lotto.gameData(gameId).then((data) => data.jackpot)
        expect(jackpot).to.eq(parseEther('10.05'))
        const balanceBefore = await ethers.provider.getBalance(bob.address)
        await lotto.claimWinnings(ticketTokenId)
        expect(await ethers.provider.getBalance(bob.address)).to.eq(balanceBefore + jackpot)

        // Withdraw accrued fees
        const accruedFees = await lotto.accruedCommunityFees()
        expect(accruedFees).to.eq(parseEther('0.05'))
        await expect(lotto.withdrawAccruedFees()).to.emit(lotto, 'Transferred')
        expect(await lotto.accruedCommunityFees()).to.eq(0)
    })
})
