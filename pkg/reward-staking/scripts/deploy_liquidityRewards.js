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
  const Reservoir = await hardhat.ethers.getContractFactory('Reservoir');
  const reservoir = await Reservoir.deploy();
  await reservoir.deployed();
  const LiquidityRewards = await ethers.getContractFactory('LiquidityRewards');
  const liquidityMining = await LiquidityRewards.deploy();
  await liquidityMining.deployed();
  await liquidityMining.initialize(
    utils.contractAddress.reservoir,
    utils.contractAddress.rewardToken,
    utils.contractAddress.stakeToken,
    utils.liquidityInit.startWeekNumber,
    utils.liquidityInit.startWeekStartTime,
    utils.liquidityInit.startWeekEndTime,
    utils.liquidityInit.amountOfWeeksToSet,
    utils.liquidityInit.rewardsVestingDuration,
    utils.liquidityInit.depositEndTime,
    utils.deployer,
    utils.updater
  );

  // eslint-disable-next-line no-undef
  console.log('LiquidityMining deployed to:', liquidityMining.address);
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
