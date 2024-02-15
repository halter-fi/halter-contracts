import { ethers } from 'hardhat';
import { expect } from 'chai';
import { advanceBlockTo, BigNumber as BN } from './utils/index';
import { waffle } from 'hardhat';

const SUPPLY = '100000000000000';
const provider = waffle.provider;
const SPAN = 2000;

describe('Reservoir', function () {
  before(async function () {
    this.signers = await ethers.getSigners();
    this.owner = this.signers[0];
    this.receiver = this.signers[1];

    this.RewardToken = await ethers.getContractFactory('TRewardToken');
    this.Reservoir = await ethers.getContractFactory('Reservoir');
  });

  beforeEach(async function () {
    this.rewardToken = await this.RewardToken.deploy(SUPPLY);
    this.reservoir = await this.Reservoir.deploy();

    this.supply = await this.rewardToken.totalSupply();
    await this.rewardToken.transfer(this.reservoir.address, this.supply);
  });

  it('should approve own balance to LM contract', async function () {
    expect(await this.rewardToken.allowance(this.reservoir.address, this.rewardToken.address)).to.be.equal(0);
    await this.reservoir.setApprove(this.rewardToken.address, this.receiver.address, this.supply);
    expect(await this.rewardToken.allowance(this.reservoir.address, this.receiver.address)).to.be.equal(this.supply);
  });

  it('should withdraw emergently the remaining tokens to owner', async function () {
    expect(await this.rewardToken.balanceOf(this.owner.address)).to.be.equal(0);
    await this.reservoir.ownerWithdraw(this.rewardToken.address);
    expect(await this.rewardToken.balanceOf(this.owner.address)).to.be.equal(this.supply);
  });
});
