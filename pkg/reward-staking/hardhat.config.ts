import '@typechain/hardhat';
import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-web3';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-truffle5';
import '@nomiclabs/hardhat-ganache';
import 'hardhat-gas-reporter';
import 'solidity-coverage';
import { config as dotEnvConfig } from 'dotenv';
dotEnvConfig();

import Web3 from 'web3';

import { HardhatUserConfig } from 'hardhat/types';

const web3 = new Web3('');
const gasPrice = web3.utils.toWei(web3.utils.toBN(process.env.GAS_PRICE_GWEI || 1), 'gwei');

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
// task("accounts", "Prints the list of accounts", async () => {
//   const accounts = await ethers.getSigners();
//
//   for (const account of accounts) {
//     console.log(account.address);
//   }
// });

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
const config: HardhatUserConfig = {
  defaultNetwork: 'hardhat',
  gasReporter: {
    currency: 'USD',
    gasPrice: 100,
  },
  paths: {
    sources: './contracts',
    tests: './test',
    artifacts: './artifacts',
    cache: './cache',
  },
  networks: {
    hardhat: {
      accounts: [
        // 5 accounts with 10^14 ETH each
        // Addresses:
        //   0x186e446fbd41dD51Ea2213dB2d3ae18B05A05ba8
        //   0x6824c889f6EbBA8Dac4Dd4289746FCFaC772Ea56
        //   0xCFf94465bd20C91C86b0c41e385052e61ed49f37
        //   0xEBAf3e0b7dBB0Eb41d66875Dd64d9F0F314651B3
        //   0xbFe6D5155040803CeB12a73F8f3763C26dd64a92
        {
          privateKey: '0b76cd75ac79574fdc38d176177fbacd05bc58f05f24e69145ba277729df48c2',
          balance: '100000000000000000000000000000000',
        },
        {
          privateKey: '0xca3547a47684862274b476b689f951fad53219fbde79f66c9394e30f1f0b4904',
          balance: '100000000000000000000000000000000',
        },
        {
          privateKey: '0x4bad9ef34aa208258e3d5723700f38a7e10a6bca6af78398da61e534be792ea8',
          balance: '100000000000000000000000000000000',
        },
        {
          privateKey: '0xffc03a3bd5f36131164ad24616d6cde59a0cfef48235dd8b06529fc0e7d91f7c',
          balance: '100000000000000000000000000000000',
        },
        {
          privateKey: '0x380c430a9b8fa9cce5524626d25a942fab0f26801d30bfd41d752be9ba74bd98',
          balance: '100000000000000000000000000000000',
        },
      ],
      allowUnlimitedContractSize: false,
      blockGasLimit: 40000000,
      gas: 40000000,
      gasPrice: 'auto',
      loggingEnabled: false,
    },
    testnet: {
      url: `https://rpc.testnet.fantom.network`,
      accounts: [process.env.PK as string],
    },
  },
  solidity: {
    compilers: [
      {
        version: '0.8.7',
        settings: {
          optimizer: {
            enabled: true,
            runs: 1000000,
          },
        },
      },
    ],
  },
  mocha: {
    timeout: 500000,
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: process.env.ETHERSCAN_API_KEY as string,
  },
};

export default config;
