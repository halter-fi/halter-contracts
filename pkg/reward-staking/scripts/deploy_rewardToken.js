const hardhat = require('hardhat');
const utils = require('../utils/constants');

async function main() {
  const RewardToken = await hardhat.ethers.getContractFactory('TRewardToken');
  const rewardToken = await RewardToken.deploy('1000000000000000000000000');
  await rewardToken.deployed();

  
  console.log('Reward Token deployed to:', rewardToken.address);
  console.log(`${utils.deployer} balance is: `, await rewardToken.balanceOf(utils.deployer));
  
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
