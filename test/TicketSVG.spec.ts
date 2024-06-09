import { ethers } from 'hardhat'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { TicketSVGRenderer, TicketSVGRenderer__factory } from '../typechain-types'
import { encrypt } from '@kevincharm/gfc-fpe'

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
})

function roundFn(R: bigint, i: bigint, seed: bigint, domain: bigint) {
    return BigInt(
        ethers.solidityPackedKeccak256(
            ['uint256', 'uint256', 'uint256', 'uint256'],
            [R, i, seed, domain],
        ),
    )
}
