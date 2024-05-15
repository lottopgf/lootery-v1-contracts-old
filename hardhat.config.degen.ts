import { HardhatUserConfig } from 'hardhat/types'
import config from './hardhat.config'

const configWithNetwork: HardhatUserConfig = {
    ...config,
    defaultNetwork: 'degen',
    networks: {
        degen: {
            chainId: 666666666,
            url: process.env.DEGEN_URL as string,
            accounts: [process.env.MAINNET_PK as string],
        },
    },
    etherscan: {
        apiKey: {
            degen: 'cafebabe',
        },
        customChains: [
            {
                network: 'degen',
                chainId: 666666666,
                urls: {
                    apiURL: 'https://explorer.degen.tips/api',
                    browserURL: 'https://explorer.degen.tips',
                },
            },
        ],
    },
}

export default configWithNetwork
