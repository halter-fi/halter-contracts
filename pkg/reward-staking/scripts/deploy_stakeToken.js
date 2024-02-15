const hardhat = require('hardhat');
const utils = require('../utils/constants');

async function main() {
  const StakeToken = await hardhat.ethers.getContractFactory('TERC20');
  const stakeToken = await StakeToken.deploy('Stake Token', 'ST', '1000000000000000000000000');
  await stakeToken.deployed();

  
  console.log('Reward Token deployed to:', stakeToken.address);
  console.log(`${utils.deployer} balance is: `, await stakeToken.balanceOf(utils.deployer));
  
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  // eslint-disable-next-line no-undef
  .then(() => process.exit(0))
  .catch((error) => {
    // eslint-disable-next-line no-undef
    console.error(error);
    // eslint-disable-next-line no-undef
    process.exit(1);
  });
