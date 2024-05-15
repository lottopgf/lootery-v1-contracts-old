import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('LooteryImpl', (m) => ({
    looteryImpl: m.contract('Lootery', []),
}))
