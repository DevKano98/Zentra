import '@nomicfoundation/hardhat-toolbox';
import 'dotenv/config';

export default {
  solidity: {
    version: '0.8.28',
    settings: {
      optimizer: { enabled: true, runs: 200 }
    }
  },
  networks: {
    hardhat: { chainId: 1337 },
    polygon_amoy: {
      url: process.env.ALCHEMY_POLYGON_AMOY_URL,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      chainId: 80002,
      gasPrice: 'auto'
    }
  },
  paths: {
    sources: './contracts',
    tests: './test',
    scripts: './scripts'
  }
};