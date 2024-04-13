import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers'
import { CombinationsConsumer, CombinationsConsumer__factory } from '../typechain-types'
import { ethers } from 'hardhat'
import { expect } from 'chai'

describe('Combinations', () => {
    let deployer: SignerWithAddress
    let combinations: CombinationsConsumer
    beforeEach(async () => {
        ;[deployer] = await ethers.getSigners()
        combinations = await new CombinationsConsumer__factory(deployer).deploy()
    })

    it('should compute n-choose-k', async () => {
        expect(await combinations.choose(5, 5)).to.eq(1)
        expect(await combinations.choose(5, 4)).to.eq(5)
        expect(await combinations.choose(5, 3)).to.eq(10)
        expect(await combinations.choose(5, 2)).to.eq(10)
        expect(await combinations.choose(5, 1)).to.eq(5)
    })

    it('should generate 5-choose-4 combinations', async () => {
        /// Generate expected combination set for [1, 2, 6, 13, 18]
        const expectedCombinations: [bigint, bigint, bigint, bigint][] = [
            [2n, 6n, 13n, 18n],
            [1n, 6n, 13n, 18n],
            [1n, 2n, 13n, 18n],
            [1n, 2n, 6n, 18n],
            [1n, 2n, 6n, 13n],
        ]
        /// Get actual generated combination set from contract
        const [combos, gasCost] = await combinations.genCombinations([1, 2, 6, 13, 18], 4)
        ///
        expect(combos).to.include.deep.members(expectedCombinations)
        ///
        console.log(`[5-choose-4 combos] gas: ${gasCost}`)
    })

    it('should generate 5-choose-3 combinations', async () => {
        // [1, 10, 64, 132, 255]
        const expectedCombinations: [bigint, bigint, bigint][] = [
            [1n, 10n, 64n],
            [1n, 10n, 132n],
            [1n, 10n, 255n],
            [1n, 64n, 132n],
            [1n, 64n, 255n],
            [1n, 132n, 255n],
            [10n, 64n, 132n],
            [10n, 64n, 255n],
            [10n, 132n, 255n],
            [64n, 132n, 255n],
        ]
        ///
        const [combos, gasCost] = await combinations.genCombinations([1, 10, 64, 132, 255], 3)
        ///
        expect(combos).to.include.deep.members(expectedCombinations)
        ///
        console.log(`[5-choose-3 combos] gas: ${gasCost}`)
    })

    it('should generate 5-choose-2 combinations', async () => {
        /// [5, 11, 42, 78, 198]
        const expectedCombinations: [bigint, bigint][] = [
            [5n, 11n],
            [5n, 42n],
            [5n, 78n],
            [5n, 198n],
            [11n, 42n],
            [11n, 78n],
            [11n, 198n],
            [42n, 78n],
            [42n, 198n],
            [78n, 198n],
        ]
        const [combos, gasCost] = await combinations.genCombinations([5, 11, 42, 78, 198], 2)
        expect(combos).to.include.deep.members(expectedCombinations)
        console.log(`[5-choose-2 combos] gas: ${gasCost}`)
    })

    it('should generate 6-choose-5 combinations', async () => {
        /// [1, 5, 42, 89, 211, 254]
        const expectedCombinations: [bigint, bigint, bigint, bigint, bigint][] = [
            [1n, 5n, 42n, 89n, 211n],
            [1n, 5n, 42n, 89n, 254n],
            [1n, 5n, 42n, 211n, 254n],
            [1n, 5n, 89n, 211n, 254n],
            [1n, 42n, 89n, 211n, 254n],
            [5n, 42n, 89n, 211n, 254n],
        ]
        const [combos, gasCost] = await combinations.genCombinations([1, 5, 42, 89, 211, 254], 5)
        expect(combos).to.include.deep.members(expectedCombinations)
        console.log(`[6-choose-5 combos] gas: ${gasCost}`)
    })

    it('should generate 6-choose-4 combinations', async () => {
        /// [1, 5, 42, 89, 211, 254]
        const expectedCombinations: [bigint, bigint, bigint, bigint][] = [
            [1n, 5n, 42n, 89n],
            [1n, 5n, 42n, 211n],
            [1n, 5n, 42n, 254n],
            [1n, 5n, 89n, 211n],
            [1n, 5n, 89n, 254n],
            [1n, 5n, 211n, 254n],
            [1n, 42n, 89n, 211n],
            [1n, 42n, 89n, 254n],
            [1n, 42n, 211n, 254n],
            [1n, 89n, 211n, 254n],
            [5n, 42n, 89n, 211n],
            [5n, 42n, 89n, 254n],
            [5n, 42n, 211n, 254n],
            [5n, 89n, 211n, 254n],
            [42n, 89n, 211n, 254n],
        ]
        const [combos, gasCost] = await combinations.genCombinations([1, 5, 42, 89, 211, 254], 4)
        expect(combos).to.include.deep.members(expectedCombinations)
        console.log(`[6-choose-4 combos] gas: ${gasCost}`)
    })

    it('should generate 6-choose-3 combinations', async () => {
        /// [1, 5, 42, 89, 211, 254]
        const expectedCombinations: [bigint, bigint, bigint][] = [
            [1n, 5n, 42n],
            [1n, 5n, 89n],
            [1n, 5n, 211n],
            [1n, 5n, 254n],
            [1n, 42n, 89n],
            [1n, 42n, 211n],
            [1n, 42n, 254n],
            [1n, 89n, 211n],
            [1n, 89n, 254n],
            [1n, 211n, 254n],
            [5n, 42n, 89n],
            [5n, 42n, 211n],
            [5n, 42n, 254n],
            [5n, 89n, 211n],
            [5n, 89n, 254n],
            [5n, 211n, 254n],
            [42n, 89n, 211n],
            [42n, 89n, 254n],
            [42n, 211n, 254n],
            [89n, 211n, 254n],
        ]
        const [combos, gasCost] = await combinations.genCombinations([1, 5, 42, 89, 211, 254], 3)
        expect(combos).to.include.deep.members(expectedCombinations)
        console.log(`[6-choose-3 combos] gas: ${gasCost}`)
    })
})
