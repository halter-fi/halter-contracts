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

  const StakingUnlocked = await hardhat.ethers.getContractFactory('HalterStakingUnlocked');
  const stakingUnlocked = await StakingUnlocked.deploy();
  await stakingUnlocked.deployed();
  await stakingUnlocked.initialize(
    utils.contractAddress.reservoir,
    utils.contractAddress.rewardToken,
    utils.contractAddress.stakeToken,
    utils.unlockedInit.startWeekNumber,
    utils.unlockedInit.startWeekStartTime,
    utils.unlockedInit.startWeekEndTime,
    utils.unlockedInit.amountOfWeeksToSet,
    utils.unlockedInit.rewardsVestingDuration,
    utils.deployer,
    utils.updater,
    utils.unlockedInit.decimalsDenominator
  );

  // eslint-disable-next-line no-undef
  console.log('Halter Staking Unlocked deployed to:', stakingUnlocked.address);
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
