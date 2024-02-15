import { ethers } from 'hardhat';
import { expect } from 'chai';
import { advanceBlockTo, BigNumber as BN, advanceTimeAndBlock as advanceTime } from './utils/index';

import { waffle } from 'hardhat';
const provider = waffle.provider;
const supply = '50000000000000000000000000000000';
const week = 604800;

const firstWeekStartTime = 1636092231;
const firstWeekEndTime = 1636092231 + week - 1;

const rewardsVestingDuration = week * 15;

describe('Liquidity Rewards', function () {
  before(async function () {
    this.signers = await ethers.getSigners();
    this.minter = this.signers[0];
    this.alice = this.signers[1];
    this.bob = this.signers[2];
    this.carol = this.signers[3];

    this.LiquidityRewards = await ethers.getContractFactory('LiquidityRewards');
    this.TERC20 = await ethers.getContractFactory('TERC20');
    this.RewardToken = await ethers.getContractFactory('TRewardToken');
    this.Reservoir = await ethers.getContractFactory('Reservoir');
  });
  beforeEach(async function () {
    this.rewardToken = await this.RewardToken.deploy(supply);
    this.reservoir = await this.Reservoir.deploy();
    this.supply = await this.rewardToken.totalSupply();
    this.reservoirInitialBalance = '50000000000000000000000000';

    this.stakeToken = await this.TERC20.deploy('LPToken', 'LP', '100000000000000000000');
    await this.stakeToken.transfer(this.alice.address, '1000');
    await this.stakeToken.transfer(this.bob.address, '1000');
    await this.stakeToken.transfer(this.carol.address, '1000');

    this.liquidityRewards = await this.LiquidityRewards.deploy();

    await this.liquidityRewards.initialize(
      this.reservoir.address,
      this.rewardToken.address,
      this.stakeToken.address,
      '0',
      firstWeekStartTime,
      firstWeekEndTime,
      '5',
      rewardsVestingDuration,
      this.minter.address,
      this.minter.address
    );

    await this.rewardToken.connect(this.minter).transfer(this.reservoir.address, this.supply);
    await this.reservoir.setApprove(this.rewardToken.address, this.liquidityRewards.address, this.supply);

    await this.liquidityRewards.deployed();
    await this.prepareReservoir;
    await this.liquidityRewards.setWeekState('0', '1');
    await this.liquidityRewards.setWeekState('1', '2');

    await this.stakeToken.connect(this.alice).approve(this.liquidityRewards.address, '1000000');
    await this.stakeToken.connect(this.bob).approve(this.liquidityRewards.address, '1000000');
  });
  context('At contract deploy: ', function () {
    it('Should set weeks timestamp variables correctly: ', async function () {
      const weekInfo = await this.liquidityRewards.weekInfo('1');
      const weekInfo2 = await this.liquidityRewards.weekInfo('2');
      expect(weekInfo.startTime).to.equal(firstWeekStartTime + week);
      expect(weekInfo.endTime).to.equal(firstWeekEndTime + week);
      const twoWeeks = week * 2;
      expect(weekInfo2.startTime).to.equal(firstWeekStartTime + twoWeeks);
      expect(weekInfo2.endTime).to.equal(firstWeekEndTime + twoWeeks);
    });
    it('Should set rewards correctly: ', async function () {
      const weekInfo = await this.liquidityRewards.weekInfo('0');
      const weekInfo2 = await this.liquidityRewards.weekInfo('1');

      expect(weekInfo.rewardRate).to.equal(1);
      expect(weekInfo2.rewardRate).to.equal(2);
    });
  });
  context('Testing "stake" calculations, mutations and transfer: ', function () {
    const aliceStake = 10;
    const bobStake1 = 5;
    const bobStake2 = 20;

    beforeEach(async function () {
      const secondsToProperWeek =
        firstWeekStartTime - (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
      advanceTime(secondsToProperWeek + 5);
      const balanceAlice = (await this.stakeToken.balanceOf(this.alice.address)).toNumber();
      const balanceBob = (await this.stakeToken.balanceOf(this.bob.address)).toNumber();
      const balanceContract = (await this.stakeToken.balanceOf(this.liquidityRewards.address)).toNumber();

      await this.liquidityRewards.connect(this.alice).stake(aliceStake, '0');
      expect(await this.stakeToken.balanceOf(this.liquidityRewards.address)).to.equal(balanceContract + aliceStake);
      await this.liquidityRewards.connect(this.bob).stake(bobStake1, '0');
      expect(await this.stakeToken.balanceOf(this.liquidityRewards.address)).to.equal(
        balanceContract + aliceStake + bobStake1
      );

      expect(await this.stakeToken.balanceOf(this.alice.address)).to.equal(balanceAlice - aliceStake);
      expect(await this.stakeToken.balanceOf(this.bob.address)).to.equal(balanceBob - bobStake1);
    });
    it('Should set totalStakedAmount correctly', async function () {
      const weekInfo = await this.liquidityRewards.weekInfo('0');
      const weekInfo2 = await this.liquidityRewards.weekInfo('1');
      expect(weekInfo.totalStakedAmount).to.equal(aliceStake + bobStake1);
      expect(weekInfo2.totalStakedAmount).to.equal(0);
      advanceTime(week);
      await this.liquidityRewards.connect(this.bob).stake(bobStake2, '1');
      expect((await this.liquidityRewards.weekInfo('0')).totalStakedAmount).to.not.equal(
        aliceStake + bobStake1 + bobStake2
      );
      expect((await this.liquidityRewards.weekInfo('1')).totalStakedAmount).to.equal(bobStake2);
    });
    it('Should set highestStakedPoint correctly', async function () {
      const weekInfo = await this.liquidityRewards.weekInfo('0');
      const weekInfo2 = await this.liquidityRewards.weekInfo('1');
      expect(weekInfo.highestStakedPoint).to.equal(aliceStake + bobStake1);
      expect(weekInfo2.highestStakedPoint).to.equal(0);
      await this.liquidityRewards.connect(this.alice).stake(aliceStake, '0');
      expect((await this.liquidityRewards.weekInfo('0')).highestStakedPoint).to.equal(
        aliceStake + bobStake1 + aliceStake
      );

      advanceTime(week);
      await this.liquidityRewards.connect(this.bob).stake(bobStake2, '1');
      expect((await this.liquidityRewards.weekInfo('0')).highestStakedPoint).to.not.equal(
        aliceStake + bobStake1 + bobStake2
      );
      expect((await this.liquidityRewards.weekInfo('1')).highestStakedPoint).to.equal(bobStake2);
    });

    it('Should set userStaked correctly', async function () {
      const userStakedAlice = await this.liquidityRewards.userStaked(this.alice.address);
      const userStakedBob = await this.liquidityRewards.userStaked(this.bob.address);
      expect(userStakedAlice).to.equal(aliceStake);
      expect(userStakedBob).to.equal(bobStake1);
      await this.liquidityRewards.connect(this.alice).stake(aliceStake, '0');
      expect(await this.liquidityRewards.userStaked(this.alice.address)).to.equal(aliceStake + aliceStake);

      advanceTime(week);
      await this.liquidityRewards.connect(this.bob).stake(bobStake2, '1');
      expect(await this.liquidityRewards.userStaked(this.alice.address)).to.equal(aliceStake + aliceStake);
      expect(await this.liquidityRewards.userStaked(this.bob.address)).to.equal(bobStake2 + bobStake1);
    });

    it('Should push correct userStake to an array', async function () {
      // to do: update with 3 other object properties
      const userStakedAlice = await this.liquidityRewards.userStake(this.alice.address, '0');
      const userStakedBob = await this.liquidityRewards.userStake(this.bob.address, '0');
      expect(userStakedAlice.staked).to.equal(aliceStake);
      expect(userStakedBob.staked).to.equal(bobStake1);
      await this.liquidityRewards.connect(this.alice).stake(aliceStake, '0');
      expect((await this.liquidityRewards.userStake(this.alice.address, '1')).staked).to.equal(aliceStake);

      advanceTime(week);
      await this.liquidityRewards.connect(this.bob).stake(bobStake2, '1');
      expect((await this.liquidityRewards.userStake(this.alice.address, '0')).staked).to.equal(aliceStake);
      expect((await this.liquidityRewards.userStake(this.alice.address, '1')).staked).to.equal(aliceStake);
      expect((await this.liquidityRewards.userStake(this.bob.address, '1')).staked).to.equal(bobStake2);

      // userStake(this.bob.address, '1')).secondsTillWeekEnd

      expect((await this.liquidityRewards.userStake(this.bob.address, '1')).secondsTillWeekEnd).to.not.equal(0);
      expect((await this.liquidityRewards.userStake(this.alice.address, '0')).secondsTillWeekEnd).to.not.equal(0);
    });
  });
  context('Testing "claimRewads" calculations, transfer and mutations: ', function () {
    const aliceStake = 10;
    const bobStake1 = 5;
    const bobStake2 = 20;

    beforeEach(async function () {
      const secondsToProperWeek =
        firstWeekStartTime - (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
      advanceTime(secondsToProperWeek + 5);
      const balanceAlice = (await this.stakeToken.balanceOf(this.alice.address)).toNumber();
      const balanceBob = (await this.stakeToken.balanceOf(this.bob.address)).toNumber();
      const balanceContract = (await this.stakeToken.balanceOf(this.liquidityRewards.address)).toNumber();

      await this.liquidityRewards.connect(this.alice).stake(aliceStake, '0');
      expect(await this.stakeToken.balanceOf(this.liquidityRewards.address)).to.equal(balanceContract + aliceStake);
      await this.liquidityRewards.connect(this.bob).stake(bobStake1, '0');
      expect(await this.stakeToken.balanceOf(this.liquidityRewards.address)).to.equal(
        balanceContract + aliceStake + bobStake1
      );

      expect(await this.stakeToken.balanceOf(this.alice.address)).to.equal(balanceAlice - aliceStake);
      expect(await this.stakeToken.balanceOf(this.bob.address)).to.equal(balanceBob - bobStake1);
      advanceTime(week);
      await this.liquidityRewards.connect(this.bob).stake(bobStake2, '1');
      expect(await this.stakeToken.balanceOf(this.bob.address)).to.equal(balanceBob - bobStake1 - bobStake2);
      advanceTime(week);

      await this.liquidityRewards.connect(this.alice).claimRewards('2');
    });

    it('Should transfer rewards', async function () {
      advanceTime(3 * week);
      const balanceBefore = await this.rewardToken.balanceOf(this.bob.address);
      await this.liquidityRewards.connect(this.bob).claimRewards('5');

      expect(await this.rewardToken.balanceOf(this.bob.address)).to.not.equal(balanceBefore);
    });

    it('Should set rewardUnclaimed after claim before vesting expires', async function () {
      await this.liquidityRewards.connect(this.bob).claimRewards('2');
      const rewardsUnclaimed = await this.liquidityRewards.rewardUnclaimed(this.bob.address, '0');

      expect(rewardsUnclaimed.amount).to.not.equal(0);
    });
    it('Should transfer more rewards after bigger vesting period is past', async function () {
      await this.liquidityRewards.connect(this.bob).claimRewards('2');
      const balanceBefore = await this.rewardToken.balanceOf(this.bob.address);
      advanceTime(3 * week);
      advanceTime(10);
      await this.liquidityRewards.connect(this.bob).claimRewards('5');

      expect(await this.rewardToken.balanceOf(this.bob.address)).to.not.equal(balanceBefore);
    });
  });
  context('Testing withdraw calculations, mutations and actions: ', function () {
    const aliceStake = 10;
    const bobStake1 = 5;
    const bobStake2 = 20;

    beforeEach(async function () {
      const secondsToProperWeek =
        firstWeekStartTime - (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
      advanceTime(secondsToProperWeek + 5);
      const balanceAlice = (await this.stakeToken.balanceOf(this.alice.address)).toNumber();
      const balanceBob = (await this.stakeToken.balanceOf(this.bob.address)).toNumber();
      const balanceContract = (await this.stakeToken.balanceOf(this.liquidityRewards.address)).toNumber();

      await this.liquidityRewards.connect(this.alice).stake(aliceStake, '0');
      expect(await this.stakeToken.balanceOf(this.liquidityRewards.address)).to.equal(balanceContract + aliceStake);
      await this.liquidityRewards.connect(this.bob).stake(bobStake1, '0');
      expect(await this.stakeToken.balanceOf(this.liquidityRewards.address)).to.equal(
        balanceContract + aliceStake + bobStake1
      );

      expect(await this.stakeToken.balanceOf(this.alice.address)).to.equal(balanceAlice - aliceStake);
      expect(await this.stakeToken.balanceOf(this.bob.address)).to.equal(balanceBob - bobStake1);
      advanceTime(week);
      await this.liquidityRewards.connect(this.bob).stake(bobStake2, '1');
      expect(await this.stakeToken.balanceOf(this.bob.address)).to.equal(balanceBob - bobStake1 - bobStake2);
      advanceTime(week);

      await this.liquidityRewards.connect(this.alice).withdraw(aliceStake / 2, '2');
      const aliceStakeAmount = (await this.liquidityRewards.userStaked(this.alice.address)).toNumber();
      expect(aliceStakeAmount).to.equal(aliceStake / 2);
    });
    it('Should correctly remove staked amount from the field', async function () {
      const aliceWithdraw = 5;

      const aliceStake = (await this.liquidityRewards.userStaked(this.alice.address)).toNumber();

      await this.liquidityRewards.connect(this.alice).withdraw(5, '2');

      expect(aliceStake - aliceWithdraw).to.equal(
        (await this.liquidityRewards.userStaked(this.alice.address)).toNumber()
      );
    });

    it('Should correctly set up userWithdraw', async function () {
      const aliceWithdrawBefore = 5;

      const firstUserWithdraw = await this.liquidityRewards.userWithdraw(this.alice.address, '0');
      expect(firstUserWithdraw.stakesWithdrawn).to.equal(aliceWithdrawBefore);
      expect(firstUserWithdraw.secondsTillWeekEnd).to.be.at.least(1);
      expect(firstUserWithdraw.secondsTillWeekEnd).to.be.at.most(week);
      expect(firstUserWithdraw.weekNumber).to.be.equal(2);
    });

    it('Should correctly calculate userStake', async function () {
      const aliceWithdrawBefore = 5;

      const stakesBefore = (await this.liquidityRewards.userStaked(this.alice.address)).toNumber();

      await this.liquidityRewards.connect(this.alice).withdraw(aliceWithdrawBefore, '2');
      expect(stakesBefore - aliceWithdrawBefore).to.equal(
        (await this.liquidityRewards.userStaked(this.alice.address)).toNumber()
      );
    });
    it('Should withdraw tokens', async function () {
      const aliceWithdrawBefore = 5;
      advanceTime(604800);

      const balanceBeforeAlice = await this.stakeToken.balanceOf(this.alice.address);

      await this.liquidityRewards.connect(this.alice).withdraw(aliceWithdrawBefore, '3');

      expect(balanceBeforeAlice).to.not.equal(await this.stakeToken.balanceOf(this.alice.address));
    });
  });

  context('Testing emergency claim calculations, mutations and actions: ', function () {
    const aliceStake = 10;
    const bobStake1 = 5;
    const bobStake2 = 20;

    beforeEach(async function () {
      const secondsToProperWeek =
        firstWeekStartTime - (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
      advanceTime(secondsToProperWeek + 5);
      const balanceAlice = (await this.stakeToken.balanceOf(this.alice.address)).toNumber();
      const balanceBob = (await this.stakeToken.balanceOf(this.bob.address)).toNumber();
      const balanceContract = (await this.stakeToken.balanceOf(this.liquidityRewards.address)).toNumber();

      await this.liquidityRewards.connect(this.alice).stake(aliceStake, '0');
      expect(await this.stakeToken.balanceOf(this.liquidityRewards.address)).to.equal(balanceContract + aliceStake);
      await this.liquidityRewards.connect(this.bob).stake(bobStake1, '0');
      expect(await this.stakeToken.balanceOf(this.liquidityRewards.address)).to.equal(
        balanceContract + aliceStake + bobStake1
      );

      expect(await this.stakeToken.balanceOf(this.alice.address)).to.equal(balanceAlice - aliceStake);
      expect(await this.stakeToken.balanceOf(this.bob.address)).to.equal(balanceBob - bobStake1);
      advanceTime(week);
      await this.liquidityRewards.connect(this.bob).stake(bobStake2, '1');
      expect(await this.stakeToken.balanceOf(this.bob.address)).to.equal(balanceBob - bobStake1 - bobStake2);
      advanceTime(week);

      await this.liquidityRewards.connect(this.alice).withdraw(aliceStake / 2, '2');
      const aliceStakeAmount = (await this.liquidityRewards.userStaked(this.alice.address)).toNumber();
      expect(aliceStakeAmount).to.equal(aliceStake / 2);
      advanceTime(week);
      this.aliceBalance = await this.rewardToken.balanceOf(this.alice.address);
      await this.liquidityRewards.connect(this.alice).emergencyClaim('3');
    });
    it('Should claim rewards', async function () {
      expect(this.aliceBalance).to.not.equal(await this.rewardToken.balanceOf(this.alice.address));
    });
  });
});
