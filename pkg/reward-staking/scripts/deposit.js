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

  const depositePoolToken = async (poolToken, amount) => {
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

    const reward = await liquidityMining.rewards(accounts[0].address);
    console.log("reward ", reward.toString());
    const claimedReward = await liquidityMining.claimedRewards(
      accounts[0].address
    );
    console.log("claimedReward ", claimedReward.toString());

    const poolInfo = await liquidityMining.poolInfo(pid);
    console.log(
      "poolInfo accRewardPerShare ",
      poolInfo.accRewardPerShare.toString()
    );
    console.log("poolInfo allocPoint: ", poolInfo.allocPoint.toString());
    console.log(
      "poolInfo lastRewardBlock:: ",
      poolInfo.lastRewardBlock.toString()
    );

    const userPoolInfo = await liquidityMining.userPoolInfo(
      pid,
      accounts[0].address
    );
    console.log("userPoolInfo amount: ", userPoolInfo.amount.toString());
    console.log(
      "userPoolInfo accruedReward: ",
      userPoolInfo.accruedReward.toString()
    );

    console.log("Deposite pool ", pid.toString());
    await (
      await liquidityMining.deposit(pid, amount, { gasLimit: "200000" })
    ).wait();
    console.log("Deposited! ");
  };

  /*await depositePoolToken(
    "0xC6032343E4D2Ef11499a5C82fd6AbC13175327d5", BN.from(1000).mul((10**18).toString()));
  await depositePoolToken(
    "0x96daB12D1E020E59f8eC80ffcF6E4c91c6487A89", BN.from(1000).mul((10**6).toString()));
  await depositePoolToken(
    "0xcd88DB75303D468fAA437728294e1A462b4a8ee0", BN.from(1000).mul((10**6).toString()));
  await addPoolToken("UNI", 20);*/
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
