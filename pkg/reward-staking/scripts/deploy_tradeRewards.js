// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hardhat = require('hardhat');
const utils = require('../utils/constants');

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const TradeVestingRewards = await hardhat.ethers.getContractFactory('TradeRewardsVesting');
  const tradeVestingRewards = await TradeVestingRewards.deploy();
  await tradeVestingRewards.deployed();
  await tradeVestingRewards.initialize(utils.contractAddress.rewardToken, utils.contractAddress.reservoir,
    utils.deployer, utils.updater);

  // eslint-disable-next-line no-undef
  console.log('TradeVestingRewards deployed to:', tradeVestingRewards.address);

  await tradeVestingRewards.addEvent('1636485730', '1637090530');
  console.log('First event has been added. Start Time: 1636485730, End Time: 1637090530');
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
