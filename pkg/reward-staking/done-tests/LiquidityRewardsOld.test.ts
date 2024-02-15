import { ethers } from 'hardhat';
import { expect } from 'chai';
import { advanceBlockTo, BigNumber as BN, advanceTimeAndBlock as advanceTime } from './utils/index';

import { waffle } from 'hardhat';
const provider = waffle.provider;
const supply = '50000000000000000000000000000000000000';
const week = 604800;
const coeff = 1e18;

const rewardRateNumerator = 150;
const rewardRateDenominator = 100000;

describe('LiquidityRewards OLD', function () {
  before(async function () {
    this.signers = await ethers.getSigners();
    this.minter = this.signers[0];
    this.alice = this.signers[1];
    this.bob = this.signers[2];
    this.carol = this.signers[3];

    this.LiquidityRewards = await ethers.getContractFactory('LiquidityRewardsOld');
    this.TERC20 = await ethers.getContractFactory('TERC20');
    this.RewardToken = await ethers.getContractFactory('TRewardToken');
    this.Reservoir = await ethers.getContractFactory('Reservoir');
  });

  beforeEach(async function () {
    this.rewardToken = await this.RewardToken.deploy(supply);
    this.reservoir = await this.Reservoir.deploy();
    this.supply = await this.rewardToken.totalSupply();
    this.reservoirInitialBalance = '50000000000000000000000000';

    this.prepareReservoir = async function () {
      await this.rewardToken.connect(this.minter).transfer(this.reservoir.address, supply);
      await this.reservoir.setApprove(this.rewardToken.address, this.liquidityRewards.address, this.supply);
    };
    const blockNumBefore = await ethers.provider.getBlockNumber();
    const blockBefore = await ethers.provider.getBlock(blockNumBefore);
    this.timestampBefore = blockBefore.timestamp;

    this.liquidityRewards = await this.LiquidityRewards.deploy(this.rewardToken.address, this.reservoir.address);
    this.poolToken = await this.TERC20.deploy('LPToken', 'LP', '100000000000000000000000000000000');
    await this.poolToken.transfer(this.alice.address, '40000000000000000000');
    await this.poolToken.transfer(this.bob.address, '40000000000000000000');
    await this.poolToken.transfer(this.carol.address, '40000000000000000000');
    this.poolToken2 = await this.TERC20.deploy('LPtoken2', 'LP2', '100000000000000000000000000000000');
    await this.poolToken2.transfer(this.alice.address, '40000000000000000000');
    await this.poolToken2.transfer(this.bob.address, '40000000000000000000');
    await this.poolToken2.transfer(this.carol.address, '40000000000000000000');

    await this.liquidityRewards.deployed();
    await this.prepareReservoir;
    await this.liquidityRewards.createRewardPool(
      this.poolToken.address,
      this.timestampBefore,
      this.timestampBefore + week,
      rewardRateNumerator,
      rewardRateDenominator
    );
  });

  context('Testing "createRewardPool" & mutations: ', function () {
    it('Should set correct state variables', async function () {
      const rewardToken = await this.liquidityRewards.rewardToken();

      expect(rewardToken).to.equal(this.rewardToken.address);
      const poolInfo = await this.liquidityRewards.poolInfo(0);

      expect(poolInfo.token).to.equal(this.poolToken.address);
      expect(poolInfo.startTime.toNumber()).to.equal(this.timestampBefore);
      expect(poolInfo.endTime.toNumber()).to.equal(this.timestampBefore + week);
      expect(poolInfo.rewardRateNumerator).to.equal(rewardRateNumerator);
      expect(poolInfo.rewardRateDenominator).to.equal(rewardRateDenominator);
      expect(poolInfo.totalPendingRewards.toNumber()).to.equal(0);
      expect(poolInfo.stakedAmount.toNumber()).to.equal(0);
    });
  });

  context('Testing "depositLPT" calculations & mutations: ', function () {
    beforeEach(async function () {
      await this.rewardToken.connect(this.minter).transfer(this.reservoir.address, this.reservoirInitialBalance);
      await this.reservoir.setApprove(this.rewardToken.address, this.liquidityRewards.address, this.supply);
    });

    it('Should let user deposit LP tokens and mutate state correctly', async function () {
      //depositing from Alice 10 wei of LPT
      await this.poolToken.connect(this.alice).approve(this.liquidityRewards.address, '10');
      await this.liquidityRewards.connect(this.alice).depositLPT('0', '10');

      //depositing from Bob 3 wei of LPT
      await this.poolToken.connect(this.bob).approve(this.liquidityRewards.address, '10');
      await this.liquidityRewards.connect(this.bob).depositLPT('0', '3');
      const poolInfo = await this.liquidityRewards.poolInfo(0);
      const userPoolInfoAlice = await this.liquidityRewards.userPoolInfo(this.alice.address, '0');
      const userPoolInfoBob = await this.liquidityRewards.userPoolInfo(this.bob.address, '0');
      expect(userPoolInfoAlice.stakedAmountLPT.toNumber()).to.equal(10);
      expect(userPoolInfoBob.stakedAmountLPT.toNumber()).to.equal(3);

      const finalDirtyRewardsAlice = await this.liquidityRewards.finalDirtyRewardsRegister(
        this.alice.address,
        '0',
        '0'
      );
      const finalDirtyRewardsBob = await this.liquidityRewards.finalDirtyRewardsRegister(this.bob.address, '0', '0');
      const finalPendingRewardsAlice = async () => {
        const returnAmount = Math.round(
          (10 *
            (await poolInfo.rewardRateNumerator).toNumber() *
            ((await poolInfo.endTime).toNumber() - finalDirtyRewardsAlice.startTime.toNumber())) /
            poolInfo.rewardRateDenominator /
            10e18
        );
        return returnAmount;
      };
      expect((await finalDirtyRewardsAlice.amount).toNumber()).to.equal(await finalPendingRewardsAlice());

      const finalPendingRewardsBob = async () => {
        const returnAmount = Math.round(
          (3 *
            (await poolInfo.rewardRateNumerator).toNumber() *
            ((await poolInfo.endTime).toNumber() - finalDirtyRewardsBob.startTime.toNumber())) /
            poolInfo.rewardRateDenominator /
            10e18
        );
        return returnAmount;
      };

      expect((await finalDirtyRewardsBob.amount).toNumber()).to.equal(await finalPendingRewardsBob());

      expect((await poolInfo.stakedAmount).toNumber()).to.equal(13);
      expect((await poolInfo.totalPendingRewards).toNumber()).to.equal(
        (await finalPendingRewardsAlice()) + (await finalPendingRewardsBob())
      );

      expect((await this.poolToken.balanceOf(this.liquidityRewards.address)).toNumber()).to.equal(13);
      expect((await this.rewardToken.balanceOf(this.liquidityRewards.address)).toNumber()).to.equal(
        (await poolInfo.totalPendingRewards).toNumber()
      );
    });
    it('Should not let users deposit into event that has ended', async function () {
      advanceTime(1912578289);
      await this.poolToken.connect(this.alice).approve(this.liquidityRewards.address, '10');
      expect(this.liquidityRewards.connect(this.alice).depositLPT('0', '10')).to.revertedWith(
        'Deposit time has come to an end'
      );
    });
  });
  context('Testing "withdrawLPT" calculations & mutations: ', async function () {
    beforeEach(async function () {
      await this.rewardToken.connect(this.minter).transfer(this.reservoir.address, this.reservoirInitialBalance);
      await this.reservoir.setApprove(this.rewardToken.address, this.liquidityRewards.address, this.supply);
      await this.poolToken.connect(this.alice).approve(this.liquidityRewards.address, '10');
      await this.liquidityRewards.connect(this.alice).depositLPT('0', '10');
      await this.poolToken.connect(this.bob).approve(this.liquidityRewards.address, '10');
      await this.liquidityRewards.connect(this.bob).depositLPT('0', '3');
      this.aliceBalanceBeforeWithdraw = await this.poolToken.balanceOf(this.alice.address);
    });
    it('Should withdraw correct amount & calculate correctly false reward register', async function () {
      const withdrawAmount = '10';
      const reservoirBalance = await this.rewardToken.balanceOf(this.reservoir.address);
      await this.liquidityRewards.connect(this.alice).withdrawLPT('0', withdrawAmount);
      expect(await this.poolToken.balanceOf(this.liquidityRewards.address)).to.equal(3);
      expect(await this.poolToken.balanceOf(this.alice.address)).to.equal(
        BN.from(this.aliceBalanceBeforeWithdraw).add(BN.from(withdrawAmount))
      );
      const poolInfo = await this.liquidityRewards.poolInfo(0);

      const falseRewardsAlice = await this.liquidityRewards.finalFalseRewardsRegister(this.alice.address, '0', '0');
      const falseAliceTest = Math.round(
        ((poolInfo.endTime - falseRewardsAlice.startTime) * poolInfo.rewardRateNumerator * parseInt(withdrawAmount)) /
          poolInfo.rewardRateDenominator /
          10e18
      );
      expect(await this.rewardToken.balanceOf(this.reservoir.address)).to.equal(
        BN.from(reservoirBalance).add(BN.from(falseRewardsAlice.amount))
      );
      expect(falseRewardsAlice.amount).to.equal(falseAliceTest);
    });
    it('Should allow withdraw after deposit event times ends & should withdraw correct amount', async function () {
      await advanceTime(86400 * 7);
      const bobBalanceBeforeWithdraw = await this.poolToken.balanceOf(this.bob.address);
      const reservoirBalance = await this.rewardToken.balanceOf(this.reservoir.address);
      await this.liquidityRewards.connect(this.bob).withdrawLPT('0', '3');
      expect(await this.rewardToken.balanceOf(this.reservoir.address)).to.equal(reservoirBalance);
      expect(await this.poolToken.balanceOf(this.liquidityRewards.address)).to.equal(10);
      expect(await this.poolToken.balanceOf(this.bob.address)).to.equal(
        BN.from(bobBalanceBeforeWithdraw).add(BN.from('3'))
      );
    });
    it('Should not allow to withdraw more than staked', async function () {
      expect(this.liquidityRewards.connect(this.bob).withdrawLPT('0', '4')).to.revertedWith(
        "Can't withdraw more than deposited"
      );
    });
  });
  context('Testing false boolean "claimRewards" calculations & mutations: ', async function () {
    beforeEach(async function () {
      const AmountAlice = '10000000000000000000';
      const AmountBob = 30;

      await this.rewardToken
        .connect(this.minter)
        .transfer(this.reservoir.address, this.rewardToken.balanceOf(this.minter.address));
      await this.reservoir.setApprove(this.rewardToken.address, this.liquidityRewards.address, this.supply);
      await this.poolToken.connect(this.alice).approve(this.liquidityRewards.address, AmountAlice);
      await this.liquidityRewards.connect(this.alice).depositLPT('0', AmountAlice);
      await this.poolToken.connect(this.bob).approve(this.liquidityRewards.address, AmountBob);
      await this.liquidityRewards.connect(this.bob).depositLPT('0', AmountBob);
      await advanceTime(1000);
      await this.liquidityRewards.connect(this.alice).withdrawLPT('0', AmountAlice);

      await advanceTime(86400 * 7);
      await this.liquidityRewards.connect(this.bob).withdrawLPT('0', AmountBob);
      await advanceTime(86400 * 7);
    });
    it('claim should not revert', async function () {
      const aliceBalanceBeforeClaim = await this.rewardToken.balanceOf(this.alice.address);
      await this.liquidityRewards.connect(this.alice).claimRewards('0', 'true');
      const aliceBalanceAfterClaim = await this.rewardToken.balanceOf(this.alice.address);
      expect(aliceBalanceBeforeClaim).to.not.equal(aliceBalanceAfterClaim);
    });
    it('get getTotalRewardsAfterVestingForAllPools() should not revert', async function () {
      await this.liquidityRewards.connect(this.bob).getTotalRewardsAfterVestingForAllPools();
    });
  });
});
