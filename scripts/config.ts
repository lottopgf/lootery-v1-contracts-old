export interface Config {
    [chainId: string]: {
        anyrand: `0x${string}`
        weth: `0x${string}`
    }
}

export const config: Config = {
    '100': {
        /** xdai */
        anyrand: '0x2df7b374816D20230c6086037B764cb7f80d0624',
        weth: '0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d', // WXDAI
    },
    '8453': {
        /** base mainnet; drand on BN254 v2 (SVDW) */
        anyrand: '0xe3a8eca966457bfd7e0049543e07e8b691b3930e',
        weth: '0xEb54dACB4C2ccb64F8074eceEa33b5eBb38E5387',
    },
    '666666666': {
        anyrand: '0x9309bd93a8b662d315Ce0D43bb95984694F120Cb',
        weth: '0xEb54dACB4C2ccb64F8074eceEa33b5eBb38E5387', // WDEGEN
    },
}
