import Task from '../../src/task';

export type LidoRelayerDeployment = {
  Vault: string;
  wstETH: string;
};

const Vault = new Task('20210418-vault');

export default {
  mainnet: {
    Vault,
    wstETH: '0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0',
  },
  kovan: {
    Vault,
    wstETH: '0x12164e5366a577D5EF32A4F87152C5552bEc03b0',
  },
};
