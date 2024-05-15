# Lootery

## Testing

1. Install deps with `yarn`
1. Run tests with `yarn test`

## Deploying

1. Export the desired deployer private key to environment variable `MAINNET_PK`
1. To deploy to a new network, ensure there exists a separate hardhat config file `hardhat.config.${network}.ts`.
    1. Ensure that the `network` and `etherscan` configurations are populated as needed.
    1. For existing configurations, ensure that you have the necessary environment variables set (RPC URLs, Etherscan API keys, etc)
1. Deploy with `yarn hardhat --config hardhat.config.${network}.ts --network ${network} run scripts/deploy.ts`
