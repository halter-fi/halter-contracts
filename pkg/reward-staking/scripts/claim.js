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

  console.log("Claiming ");
  await (await liquidityMining.claim({ gasLimit: "200000" })).wait();
  console.log("Done! ");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
