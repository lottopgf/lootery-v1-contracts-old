import { buildModule } from '@nomicfoundation/hardhat-ignition/modules'

export default buildModule('TicketSVGRenderer', (m) => ({
    ticketSVGRenderer: m.contract('TicketSVGRenderer', []),
}))
