import { ethers } from 'hardhat'
import { loadFixture, time, setBalance } from '@nomicfoundation/hardhat-network-helpers'
import {
    Lootery,
    LooteryFactory,
    LooteryFactory__factory,
    Lootery__factory,
    MockRandomiser,
    MockRandomiser__factory,
    TestERC20__factory,
    type TestERC20,
} from '../typechain-types'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { BigNumberish, LogDescription, hexlify, parseEther } from 'ethers'
import { expect } from 'chai'
import { deployProxy } from './helpers/deployProxy'
import { encrypt } from '@kevincharm/gfc-fpe'
import crypto from 'node:crypto'

describe('Lootery', () => {
    let mockRandomiser: MockRandomiser
    let testERC20: TestERC20
    let factory: LooteryFactory
    let deployer: SignerWithAddress
    let bob: SignerWithAddress
    let alice: SignerWithAddress
    beforeEach(async () => {
        ;[deployer, bob, alice] = await ethers.getSigners()
        mockRandomiser = await new MockRandomiser__factory(deployer).deploy()
        testERC20 = await new TestERC20__factory(deployer).deploy(deployer)
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
            5000, // 50%,
            testERC20,
        )

        // Allow seeding jackpot
        await testERC20.mint(deployer, parseEther('10'))
        await testERC20.approve(lotto, parseEther('10'))
        await lotto.seedJackpot(parseEther('10'))
        expect(await testERC20.balanceOf(lotto)).to.eq(parseEther('10'))

        const gameId = await lotto.currentGameId()

        // Bob purchases a winning ticket for 0.1
        await testERC20.mint(bob, parseEther('0.1'))
        await testERC20.connect(bob).approve(lotto, parseEther('0.1'))

        const winningTicket = [3n, 11n, 22n, 29n, 42n]
        await lotto.connect(bob).purchase([
            {
                whomst: bob.address,
                picks: winningTicket,
            },
        ])
        // Bob receives NFT ticket
        expect(await lotto.balanceOf(bob.address)).to.eq(1)
        const ticketTokenId = 1
        expect(await lotto.ownerOf(ticketTokenId)).to.eq(bob.address)

        // Draw
        await time.increase(gamePeriod)
        await setBalance(await lotto.getAddress(), parseEther('0.1'))
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
        const balanceBefore = await testERC20.balanceOf(bob.address)
        await lotto.claimWinnings(ticketTokenId)
        expect(await testERC20.balanceOf(bob.address)).to.eq(balanceBefore + jackpot)

        // Withdraw accrued fees
        const accruedFees = await lotto.accruedCommunityFees()
        expect(accruedFees).to.eq(parseEther('0.049')) // 0.05 - vrfRequestPrice
        await expect(lotto.withdrawAccruedFees()).to.emit(testERC20, 'Transfer')
        expect(await lotto.accruedCommunityFees()).to.eq(0)
    })

    it('should let participants claim equal share if nobody won', async () => {
        const gamePeriod = 1n * 60n * 60n
        async function deploy() {
            return deployLotto({
                deployer,
                gamePeriod,
                prizeToken: testERC20,
            })
        }
        const { lotto, fastForwardAndDraw } = await loadFixture(deploy)

        await testERC20.mint(deployer, parseEther('10'))
        await testERC20.approve(lotto, parseEther('10'))

        const { tokenId: bobTokenId } = await purchaseTicket(lotto, bob.address, [1, 2, 3, 4, 5])
        const { tokenId: aliceTokenId } = await purchaseTicket(
            lotto,
            alice.address,
            [1, 2, 3, 4, 6],
        )
        const gameId = await lotto.tokenIdToGameId(bobTokenId)

        await fastForwardAndDraw(6942069320n)

        const { jackpot } = await lotto.gameData(gameId)
        const prizeShare = jackpot / 2n
        const bobBalanceBefore = await testERC20.balanceOf(bob.address)
        expect(await lotto.claimWinnings(bobTokenId))
            .to.emit(lotto, 'ConsolationClaimed')
            .withArgs(bobTokenId, gameId, bob.address, prizeShare)
        expect(await testERC20.balanceOf(bob.address)).to.eq(bobBalanceBefore + prizeShare)
        const aliceBalanceBefore = await testERC20.balanceOf(alice.address)
        expect(await lotto.claimWinnings(aliceTokenId))
            .to.emit(lotto, 'ConsolationClaimed')
            .withArgs(aliceTokenId, gameId, bob.address, prizeShare)
        expect(await testERC20.balanceOf(alice.address)).to.eq(aliceBalanceBefore + prizeShare)
    })

    it('should run games continuously, as long as gamePeriod has elapsed', async () => {
        const gamePeriod = 1n * 60n * 60n
        async function deploy() {
            return deployLotto({
                deployer,
                gamePeriod,
                prizeToken: testERC20,
            })
        }
        const { lotto, fastForwardAndDraw } = await loadFixture(deploy)

        // Buy some tickets
        await testERC20.mint(deployer, parseEther('10'))
        await testERC20.approve(lotto, parseEther('10'))

        await purchaseTicket(lotto, bob.address, [1, 2, 3, 4, 5])

        const initialGameId = await lotto.currentGameId()
        await fastForwardAndDraw(6942069320n)
        await expect(lotto.draw()).to.be.revertedWithCustomError(lotto, 'WaitLonger')
        for (let i = 0; i < 10; i++) {
            const gameId = await lotto.currentGameId()
            expect(gameId).to.eq(initialGameId + BigInt(i) + 1n)
            await time.increase(gamePeriod)
            await expect(lotto.draw()).to.emit(lotto, 'DrawSkipped').withArgs(gameId)
        }
    })
})

function keccak(balls: bigint[]) {
    return ethers.solidityPackedKeccak256(
        balls.map((_) => 'uint8'),
        balls,
    )
}

async function deployLotto({
    deployer,
    gamePeriod,
    prizeToken,
}: {
    deployer: SignerWithAddress
    /** seconds */
    gamePeriod: bigint
    prizeToken: TestERC20
}) {
    const mockRandomiser = await new MockRandomiser__factory(deployer).deploy()
    const lotto = await deployProxy({
        deployer,
        implementation: Lootery__factory,
        initData: await Lootery__factory.createInterface().encodeFunctionData('init', [
            deployer.address,
            'Lotto',
            'LOTTO',
            5,
            69,
            gamePeriod,
            parseEther('0.1'),
            5000, // 50%
            await mockRandomiser.getAddress(),
            await prizeToken.getAddress(),
        ]),
    })
    // Seed initial jackpot with 10 ETH
    await prizeToken.mint(deployer, parseEther('10'))
    await prizeToken.approve(lotto, parseEther('10'))
    await lotto.seedJackpot(parseEther('10'))

    const fastForwardAndDraw = async (randomness: bigint) => {
        // Draw
        await time.increase(gamePeriod)
        await setBalance(await lotto.getAddress(), parseEther('0.1'))
        await lotto.draw()
        const { requestId } = await lotto.randomnessRequest()

        // Fulfill w/ mock randomiser
        const fulfilmentTx = await mockRandomiser
            .fulfillRandomWords(requestId, [randomness])
            .then((tx) => tx.wait(1))
        const [, emittedBalls] = lotto.interface.decodeEventLog(
            'GameFinalised',
            fulfilmentTx?.logs?.[0].data!,
            fulfilmentTx?.logs?.[0].topics,
        ) as unknown as [bigint, bigint[]]
        return emittedBalls
    }

    return {
        lotto,
        mockRandomiser,
        fastForwardAndDraw,
    }
}

/**
 * Purchase a slikpik ticket. Lotto must be connected to an account
 * with enough funds to buy a ticket.
 * @param connectedLotto Lottery contract
 * @param whomst Who to mint the ticket to
 */
async function slikpik(connectedLotto: Lootery, whomst: string) {
    const numPicks = await connectedLotto.numPicks()
    const domain = await connectedLotto.maxBallValue()
    const ticketPrice = await connectedLotto.ticketPrice()
    // Generate shuffled pick
    const seed = BigInt(hexlify(crypto.getRandomValues(new Uint8Array(32))))
    const roundFn = (R: bigint, i: bigint, seed: bigint, domain: bigint) => {
        return BigInt(
            ethers.solidityPackedKeccak256(
                ['uint256', 'uint256', 'uint256', 'uint256'],
                [R, i, seed, domain],
            ),
        )
    }
    const picks: bigint[] = []
    for (let i = 0; i < numPicks; i++) {
        const pick = 1n + encrypt(BigInt(i), domain, seed, 4n, roundFn)
        picks.push(pick)
    }
    picks.sort((a, b) => Number(a - b))
    const tx = await connectedLotto
        .purchase([
            {
                whomst,
                picks,
            },
        ])
        .then((tx) => tx.wait())
    const parsedLogs = tx!.logs
        .map((log) =>
            connectedLotto.interface.parseLog({ topics: log.topics as string[], data: log.data }),
        )
        .filter((value): value is LogDescription => !!value)
    const ticketPurchasedEvent = parsedLogs.find((log) => log.name === 'TicketPurchased')
    const [, , tokenId] = ticketPurchasedEvent!.args
    return {
        tokenId,
    }
}

/**
 * Purchase a ticket. Lotto must be connected to an account
 * with enough funds to buy a ticket.
 * @param connectedLotto Lottery contract
 * @param whomst Who to mint the ticket to
 * @param picks Picks
 */
async function purchaseTicket(connectedLotto: Lootery, whomst: string, picks: BigNumberish[]) {
    const numPicks = await connectedLotto.numPicks()
    if (picks.length !== Number(numPicks)) {
        throw new Error(`Invalid number of picks (expected ${numPicks}, got picks.length)`)
    }
    const ticketPrice = await connectedLotto.ticketPrice()
    const tx = await connectedLotto
        .purchase([
            {
                whomst,
                picks,
            },
        ])
        .then((tx) => tx.wait())
    const lottoAddress = await connectedLotto.getAddress()
    const parsedLogs = tx!.logs
        .filter((log) => log.address === lottoAddress)
        .map((log) =>
            connectedLotto.interface.parseLog({ topics: log.topics as string[], data: log.data }),
        )
        .filter((value): value is LogDescription => !!value)
    const ticketPurchasedEvent = parsedLogs.find((log) => log.name === 'TicketPurchased')
    const [, , tokenId] = ticketPurchasedEvent!.args
    return {
        tokenId,
    }
}
