import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('LooteryFactory', (m) => ({
    looteryFactoryProxy: m.contract('ERC1967Proxy', [
        m.contract('LooteryFactory', []),
        m.getParameter('factoryInitData', '0x'),
    ]),
}))
