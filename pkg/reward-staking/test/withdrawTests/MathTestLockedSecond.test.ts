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
const rewardRateThirdWeek = ethers.utils.parseEther('0.1');

const aliceFirstStake = ethers.utils.parseEther('20');
const aliceSecondStake = ethers.utils.parseEther('10');
const aliceFirstWithdraw = ethers.utils.parseEther('15');
const aliceSecondWithdraw = ethers.utils.parseEther('2.5');

describe('Halter Staking Second Withdraw Locked Test', function () {
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
    await this.halterStaking.setWeekState('1', '0');
    await this.halterStaking.setWeekState('2', '0');
    await this.halterStaking.setWeekState('3', '0');
    

    await this.stakeToken.connect(this.alice).approve(this.halterStaking.address, '900000000000000000000');
    await this.stakeToken.connect(this.bob).approve(this.halterStaking.address, '900000000000000000000');
    
    await advanceTime(-16);
    await this.halterStaking.connect(this.alice).stake(aliceFirstStake, '0');
  });
  context('Testing viewVestedRewards method with a single stake: ', function () {
      it('Should calculate rewards correctly after 2 withdraws', async function () {
        await advanceTime(week-10);
        await this.halterStaking.connect(this.alice).stake(aliceSecondStake, '0');
        await this.halterStaking.setWeekState('1', rewardRateSecondWeek);
        await advanceTime(20);

        await this.halterStaking.connect(this.alice).startWithdrawLock(aliceFirstWithdraw, '1');
        await advanceTime(week+16);
        await this.halterStaking.setWeekState('2', rewardRateThirdWeek);
        await this.halterStaking.connect(this.alice).startWithdrawLock(aliceSecondWithdraw, '2');
        await advanceTime(302385);
        console.log(
            'Time Passed since the start: ',
            (await latest()).sub((await this.halterStaking.weekInfo('0')).startTime).toString()
          );
        expect(await this.halterStaking.connect(this.alice.address).viewVestedRewards('2')).to.be.at.most(
            BN.from('2382944444444440000')
          );
          expect(await this.halterStaking.connect(this.alice.address).viewVestedRewards('2')).to.be.at.least(
            BN.from('2380944444444440000')
          );
        await advanceTime(302996);
        await this.halterStaking.connect(this.alice).claimRewards('3');

        expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.at.most(BN.from('3015888888888890000'));
        expect(await this.rewardToken.balanceOf(this.alice.address)).to.be.at.least(BN.from('3012888888888890000'));
      });
  });
});
