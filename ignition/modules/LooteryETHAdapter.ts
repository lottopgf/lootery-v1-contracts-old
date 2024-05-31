import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('LooteryETHAdapter', (m) => ({
    looteryEthAdapter: m.contract('LooteryETHAdapter', [m.getParameter('weth')]),
}))
