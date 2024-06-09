import { ethers } from 'hardhat'
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { TestTicketSVG, TestTicketSVG__factory } from '../typechain-types'
import { encrypt } from '@kevincharm/gfc-fpe'

describe('TicketSVG', () => {
    let deployer: SignerWithAddress
    let ticketSVG: TestTicketSVG
    beforeEach(async () => {
        ;[deployer] = await ethers.getSigners()
        ticketSVG = await new TestTicketSVG__factory(deployer).deploy()
    })

    it('should render a ticket', async () => {
        const maxValue = 26
        const numPicks = 5
        const picks = Array(numPicks)
            .fill(0)
            .map((_, i) => 1n + encrypt(BigInt(i), BigInt(maxValue), 6942069420n, 4n, roundFn))
            .sort((a, b) => Number(a - b))
        const svg = await ticketSVG.render('The Lootery', maxValue, picks)
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
