import { ethers } from 'hardhat';
import { expect } from 'chai';
import { advanceBlockTo, BigNumber as BN, advanceTimeAndBlock as advanceTime, latest } from '../utils/index';

import { waffle } from 'hardhat';
const provider = waffle.provider;
const supply = ethers.utils.parseEther('90000000000000000'); 
const week = 604800;

const rewardsVestingDuration = (86400 * 90).toString();
const rewardRateFirstWeek = ethers.utils.parseEther('0.5');
const rewardRateSecondWeek = ethers.utils.parseEther('0.25');

const aliceFirstStake = ethers.utils.parseEther('10');
const aliceSecondStake = ethers.utils.parseEther('25');
const aliceFirstWithdraw = ethers.utils.parseEther('15');

describe('Halter Staking First Claim Locked Test', function () {
  before(async function () {
    const firstWeekStartTime = (await latest()).toNumber();
    const firstWeekEndTime = firstWeekStartTime + week - 1;
    this.signers = await ethers.getSigners();
    this.minter = this.signers[0];
    this.alice = this.signers[1];
    this.bob = this.signers[2];
    this.carol = this.signers[3];

    this.HalterStaking = await ethers.getContractFactory('HalterStakingLocked');
    this.TERC20 = await ethers.getContractFactory('TERC20');
    this.RewardToken = await ethers.getContractFactory('TRewardToken');
    this.Reservoir = await ethers.getContractFactory('Reservoir');
    this.rewardToken = await this.RewardToken.deploy(supply);
    this.reservoir = await this.Reservoir.deploy();
    this.supply = await this.rewardToken.totalSupply();

    this.stakeToken = await this.TERC20.deploy('LPToken', 'LP', '90000000000000000000000000000000000');
    await this.stakeToken.transfer(this.alice.address, '900000000000000000000');
    await this.stakeToken.transfer(this.bob.address, '900000000000000000000');
    await this.stakeToken.transfer(this.carol.address, '900000000000000000000');

    this.halterStaking = await this.HalterStaking.deploy();

    await this.halterStaking.initialize(
      this.reservoir.address,
      this.rewardToken.address,
      this.stakeToken.address,
      '0',
      firstWeekStartTime,
      firstWeekEndTime,
      '5',
      rewardsVestingDuration,
      this.minter.address,
      this.minter.address,
      this.minter.address
    );

    await this.rewardToken.connect(this.minter).transfer(this.reservoir.address, this.supply);
    await this.reservoir.setApprove(this.rewardToken.address, this.halterStaking.address, this.supply);

    await this.halterStaking.deployed();
    await this.prepareReservoir;
    await this.halterStaking.setWeekState('0', rewardRateFirstWeek);
    await this.halterStaking.setWeekState('1', rewardRateSecondWeek);
    await this.halterStaking.setWeekState('2', '0');
    await this.halterStaking.setWeekState('3', '0');

    await this.stakeToken.connect(this.alice).approve(this.halterStaking.address, '900000000000000000000');
    await this.stakeToken.connect(this.bob).approve(this.halterStaking.address, '900000000000000000000');

    await this.halterStaking.connect(this.alice).stake(aliceFirstStake, '0');
  });
  context('At contract deploy: ', function () {
    it('Should set rewards correctly: ', async function () {
      const weekInfo = await this.halterStaking.weekInfo('0');
      const weekInfo2 = await this.halterStaking.weekInfo('1');

      expect(weekInfo.rewardRate).to.equal(rewardRateFirstWeek);
      expect(weekInfo2.rewardRate).to.equal(rewardRateSecondWeek);
    });
  });
  context('Testing viewVestedRewards method with a single stake: ', function () {
    it('Should calculate return of viewVestedRewards correctly: ', async function () {
      await advanceTime(week);
      expect(await this.halterStaking.connect(this.alice.address).viewVestedRewards('1')).to.be.at.most(
        BN.from('388898888888890000')
      );
      expect(await this.halterStaking.connect(this.alice.address).viewVestedRewards('1')).to.be.at.least(
        BN.from('388868888888870000')
      );
      await advanceTime(-604800);
    });
  });
  context('Testing viewVestedRewards method with a single stake: ', function () {
    it('Should calculate return of viewTotalRewards correctly: ', async function () {
      await advanceTime(604800);
      expect((await this.halterStaking.connect(this.alice.address).viewTotalRewards('1')).toString()).to.equal('5000000000000000000');
      await advanceTime(-604800);
    });
  });
  context('Testing claimRewards method with 2 stakes, but one was done during current week: ', function () {
    it('Should calculate transfer amount correctly and transfer it', async function () {
      await advanceTime(604800);
      await this.halterStaking.connect(this.alice).stake(aliceSecondStake, '1');
      await advanceTime(302400);
      await this.halterStaking.connect(this.alice).claimRewards('1');
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.at.most(
        BN.from('583343333333333000')
      );
      expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.at.least(
        BN.from('583313333333333000')
      );
      await advanceTime((-604800-302400));
    });
  });
});
