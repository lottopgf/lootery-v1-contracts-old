import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { SortConsumer, SortConsumer__factory } from '../typechain-types'
import { ethers } from 'hardhat'
import { expect } from 'chai'

describe('Sort', () => {
    let deployer: SignerWithAddress
    let sorter: SortConsumer
    beforeEach(async () => {
        ;[deployer] = await ethers.getSigners()
        sorter = await new SortConsumer__factory(deployer).deploy()
    })

    it(`should sort empty`, async () => {
        const sorted = await sorter.sort([])
        expect(sorted).to.deep.eq([])
    })

    it(`should sort single`, async () => {
        const sorted = await sorter.sort([69])
        expect(sorted).to.deep.eq([69])
    })

    it(`should sort two`, async () => {
        const sorted = await sorter.sort([69, 42])
        expect(sorted).to.deep.eq([42, 69])
    })

    for (let i = 0; i < 10; i++) {
        const randomArray = generateRandomArray()
        it(`should sort correctly against js impl: ${randomArray}`, async () => {
            const sorted = await sorter.sort(randomArray)
            expect(sorted).to.deep.eq(randomArray.slice().sort((a, b) => a - b))
        })
    }
})

function generateRandomArray() {
    const len = 5 + Math.ceil(Math.random() * 20)
    return Array(len)
        .fill(0)
        .map((_) => Math.floor(Math.random() * 256))
}
