import { ethers } from 'hardhat'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { TicketSVGRenderer, TicketSVGRenderer__factory } from '../typechain-types'
import { encrypt } from '@kevincharm/gfc-fpe'
import { expect } from 'chai'

describe('TicketSVG', () => {
    let deployer: SignerWithAddress
    let ticketSVGRenderer: TicketSVGRenderer
    beforeEach(async () => {
        ;[deployer] = await ethers.getSigners()
        ticketSVGRenderer = await new TicketSVGRenderer__factory(deployer).deploy()
    })

    it('should render a ticket', async () => {
        const maxValue = 26
        const numPicks = 5
        const picks = Array(numPicks)
            .fill(0)
            .map((_, i) => 1n + encrypt(BigInt(i), BigInt(maxValue), 6942069420n, 4n, roundFn))
            .sort((a, b) => Number(a - b))
        const svg = await ticketSVGRenderer.renderSVG('The Lootery', maxValue, picks)
        console.log('picks:', picks)
        console.log(`data:image/svg+xml;base64,${btoa(svg)}`)
    })

    it('should render a ticket for numPick=1', async () => {
        const maxValue = 5
        const picks = [5]
        const svg = await ticketSVGRenderer.renderSVG('The Lootery', maxValue, picks)
        console.log('picks:', picks)
        console.log(`data:image/svg+xml;base64,${btoa(svg)}`)
    })

    it('should revert when trying to render an out of range pick', async () => {
        const maxValue = 1
        const picks = [5]
        await expect(ticketSVGRenderer.renderSVG('The Lootery', maxValue, picks))
            .to.be.revertedWithCustomError(ticketSVGRenderer, 'OutOfRange')
            .withArgs(5, 1)
    })
})

function roundFn(R: bigint, i: bigint, seed: bigint, domain: bigint) {
    return BigInt(
        ethers.solidityPackedKeccak256(
            ['uint256', 'uint256', 'uint256', 'uint256'],
            [R, i, seed, domain],
        ),
    )
}
