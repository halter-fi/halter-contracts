import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-waffle';
// import 'hardhat-local-networks-config-plugin';

import '@balancer-labs/v2-common/setupTests';

import { task, types } from 'hardhat/config';
import { TASK_TEST } from 'hardhat/builtin-tasks/task-names';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

import test from './src/test';
import Task from './src/task';
import Verifier from './src/verifier';
import { Logger } from './src/logger';

task('deploy', 'Run deployment task')
  .addParam('id', 'Deployment task ID')
  .addFlag('force', 'Ignore previous deployments')
  .addOptionalParam('key', 'Etherscan API key to verify contracts')
  .setAction(
    async (args: { id: string; force?: boolean; key?: string; verbose?: boolean }, hre: HardhatRuntimeEnvironment) => {
      Logger.setDefaults(false, args.verbose || false);
      const verifier = args.key ? new Verifier(hre.network, args.key) : undefined;
      await Task.fromHRE(args.id, hre, verifier).run(args);
    }
  );

task('verify-contract', 'Run verification for a given contract')
  .addParam('id', 'Deployment task ID')
  .addParam('name', 'Contract name')
  .addParam('address', 'Contract address')
  .addParam('args', 'ABI-encoded constructor arguments')
  .addParam('key', 'Etherscan API key to verify contracts')
  .setAction(
    async (
      args: { id: string; name: string; address: string; key: string; args: string; verbose?: boolean },
      hre: HardhatRuntimeEnvironment
    ) => {
      Logger.setDefaults(false, args.verbose || false);
      const verifier = args.key ? new Verifier(hre.network, args.key) : undefined;

      await Task.fromHRE(args.id, hre, verifier).verify(args.name, args.address, args.args);
    }
  );

task(TASK_TEST)
  .addOptionalParam('fork', 'Optional network name to be forked block number to fork in case of running fork tests.')
  .addOptionalParam('blockNumber', 'Optional block number to fork in case of running fork tests.', undefined, types.int)
  .setAction(test);

// const config: HardhatUserConfig = {
//   defaultNetwork: 'hardhat',
//   gasReporter: {
//     currency: 'USD',
//     gasPrice: 100,
//   },
//   paths: {
//     sources: './contracts',
//     tests: './test',
//     artifacts: './artifacts',
//     cache: './cache',
//   },
//   networks: {
//     hardhat: {
//       accounts: [
//         // 5 accounts with 10^14 ETH each
//         // Addresses:
//         //   0x186e446fbd41dD51Ea2213dB2d3ae18B05A05ba8
//         //   0x6824c889f6EbBA8Dac4Dd4289746FCFaC772Ea56
//         //   0xCFf94465bd20C91C86b0c41e385052e61ed49f37
//         //   0xEBAf3e0b7dBB0Eb41d66875Dd64d9F0F314651B3
//         //   0xbFe6D5155040803CeB12a73F8f3763C26dd64a92
//         {
//           privateKey: '0b76cd75ac79574fdc38d176177fbacd05bc58f05f24e69145ba277729df48c2',
//           balance: '100000000000000000000000000000000',
//         },
//         {
//           privateKey: '0xca3547a47684862274b476b689f951fad53219fbde79f66c9394e30f1f0b4904',
//           balance: '100000000000000000000000000000000',
//         },
//         {
//           privateKey: '0x4bad9ef34aa208258e3d5723700f38a7e10a6bca6af78398da61e534be792ea8',
//           balance: '100000000000000000000000000000000',
//         },
//         {
//           privateKey: '0xffc03a3bd5f36131164ad24616d6cde59a0cfef48235dd8b06529fc0e7d91f7c',
//           balance: '100000000000000000000000000000000',
//         },
//         {
//           privateKey: '0x380c430a9b8fa9cce5524626d25a942fab0f26801d30bfd41d752be9ba74bd98',
//           balance: '100000000000000000000000000000000',
//         },
//       ],
//       allowUnlimitedContractSize: false,
//       blockGasLimit: 40000000,
//       gas: 40000000,
//       gasPrice: 'auto',
//       loggingEnabled: false,
//     },
//     testnet: {
//       url: `https://rpc.testnet.fantom.network`,
//       accounts: [process.env.PK as string],
//     },
//   },
//   solidity: {
//     compilers: [
//       {
//         version: '0.8.7',
//         settings: {
//           optimizer: {
//             enabled: true,
//             runs: 1000000,
//           },
//         },
//       },
//     ],
//   },
//   mocha: {
//     timeout: 500000,
//   },
//   etherscan: {
//     // Your API key for Etherscan
//     // Obtain one at https://etherscan.io/
//     apiKey: process.env.ETHERSCAN_API_KEY as string,
//   },
// };

export default {
  mocha: {
    timeout: 40000,
  },

  networks: {
    blastTestnet: {
      url: 'https://sepolia.blast.io',
      accounts: [''],
      chainId: 168587773,
    },
  },
};
