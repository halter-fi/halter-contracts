// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

const BN = hre.ethers.BigNumber;

async function main() {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }

  const liquidityMiningAddress = "0xf3f2Da88908cC84458ff311DcE42b2E3A871A6AD";
  console.log("Get LiquidityMining ", liquidityMiningAddress);
  const LiquidityMining = await hre.ethers.getContractFactory(
    "LiquidityMining"
  );
  const liquidityMining = await LiquidityMining.attach(liquidityMiningAddress);

  const RewardToken = await hre.ethers.getContractFactory("TRewardToken");

  const withdrawPoolToken = async (poolToken, amount) => {
    const rewardToken = await RewardToken.attach(poolToken);
    console.log("Pool token: ", rewardToken.address);

    console.log("Approve amount ", amount.toString());
    await (
      await rewardToken.approve(
        liquidityMiningAddress,
        hre.ethers.constants.MaxUint256
      )
    ).wait();

    const pid = await liquidityMining.poolPidByAddress(rewardToken.address);

    console.log("Withdraw pool ", pid.toString());
    await (
      await liquidityMining.withdraw(pid, amount, { gasLimit: "200000" })
    ).wait();
    console.log("Withdrawed! ");
  };

  /*await withdrawPoolToken(
    "0xC6032343E4D2Ef11499a5C82fd6AbC13175327d5", BN.from(1000).mul((10**18).toString()));
  await withdrawPoolToken(
    "0x96daB12D1E020E59f8eC80ffcF6E4c91c6487A89", BN.from(1000).mul((10**6).toString()));
  await withdrawPoolToken(
    "0xcd88DB75303D468fAA437728294e1A462b4a8ee0", BN.from(1000).mul((10**6).toString()));
  await addPoolToken("UNI", 20); */
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
