// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/* TO DO:
     0) Add view function to check total vested rewards + total Unvested rewards
     0.1) Claim from all pools method
     0.2) Emergency claim from all pools method
     1) Test manualy
     2) Unit tests
     
*/

/** 
        @title LP Tokens staking for Halter Token farming with linear vesting.
        @author Gosha Skryuchenkov @ Prometeus Labs
        This contract is used for liquidity pool tokens staking.
        Users that stake LP Tokens farm rewards on every second bases.

        Rewards are distributed with a 6 months linear vesting, which
        starts at the moment of LP Tokens deposit.
        Reward tokens can be instantly claimed with a 50% penalty.
        Penalty is getting back to Reservoir, which hold funds for
        all events.

        LP Tokens may be withdrawn at any point, but that will stop
        the process of farming reward Tokens.
    */
contract LiquidityRewardsOld is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct PoolInfo {
        IERC20 token; // Address of Halter Liquidity Pool token
        uint256 startTime; // Timestamp of Reward Mining start
        uint256 endTime; // Timestamp of Reward Mining end
        uint256 rewardRateNumerator; // Reward rate per second Numerator
        uint256 rewardRateDenominator; // Reward rate per second Denominator
        uint256 totalPendingRewards; // Total amount of rewards that will ever get distributed to users in that pool
        uint256 stakedAmount; // Total amount of LPT currently staked by users in a pool
    }

    struct UserPoolInfo {
        uint256 stakedAmountLPT; // Amount of Halter Liquidity Pool tokens provided to the pool
        uint256 claimedRewards; // Amount of claimed rewards
    }

    struct FinalRewardAmount {
        uint256 amount; // Amount of reward tokens that will be distributed if user stays in the farming pool till the end
        uint256 unlockTime; // Timestamp of the moment that 100% of rewards will be vested for user
        uint256 startTime; // Timestamp of deposit
    }

    struct FalseRewards {
        uint256 amount; // Amount of rewards that user couldn't farm, since he/she/they widthdraw LPT from the pool
        uint256 startTime; // Timestamp of withdraw
    }

    uint256 public constant rewardsDuration = 86400 * 180; // Duration of vesting period in seconds. 180 days.
    IERC20 public rewardToken; // The reward token
    address public reservoir; // Address of the contract that holds DAO's assets

    // Info about each pool
    PoolInfo[] public poolInfo;

    // Pool pid of each pool by LPT address
    //LP token address returns pool index
    mapping(address => uint256) public poolPidByAddress;

    // user's address -> pid
    mapping(address => mapping(uint256 => UserPoolInfo)) public userPoolInfo;
    mapping(address => mapping(uint256 => FinalRewardAmount[])) public finalDirtyRewardsRegister;
    mapping(address => mapping(uint256 => FalseRewards[])) public finalFalseRewardsRegister;

    /* ======================== EVENT ======================== */
    event PoolCreated(address indexed token, uint256 indexed pid);
    event Deposited(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed pid, uint256 amount, bool leftBeforeEnd);
    event Claimed(address indexed user, uint256 indexed pid, uint256 amount, uint256 penaltyReward);

    /* ======================== CONSTRUCTOR ======================== */

    /**
    @param _rewardToken address of a reward Token
    @param _reservoir address of a smart contract that holds DAO funds
    */
    constructor(IERC20 _rewardToken, address _reservoir) {
        rewardToken = _rewardToken;
        reservoir = _reservoir;
    }

    /* ======================== OWNER FUNCTIONS ======================== */

    /**
    @param _token address of LPT token that will be deposited by users for farming
    @param _startTime timestamp of deposit event start
    @param _endTime timestamp of deposut event end
    @param _rewardRateNumerator amount of reward tokens in wei user can recieve per each wei of deposited _token per second
    @param _rewardRateDenominator amount of reward tokens in wei user can recieve per each wei of deposited _token per second

    This method creates a reward pool for a specific token
    */
    function createRewardPool(
        IERC20 _token,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _rewardRateNumerator,
        uint256 _rewardRateDenominator
    ) external onlyOwner {
        require(!isTokenAdded(_token), "Pool with that token was created already");

        uint256 pid = poolInfo.length;
        poolInfo.push(
            PoolInfo({
                token: _token,
                startTime: _startTime,
                endTime: _endTime,
                rewardRateNumerator: _rewardRateNumerator,
                rewardRateDenominator: _rewardRateDenominator,
                totalPendingRewards: 0,
                stakedAmount: 0
            })
        );
        poolPidByAddress[address(_token)] = pid.add(1);
        emit PoolCreated(address(_token), pid.add(1));
    }

    /* ======================== MUTATIVE FUNCTIONS ======================== */

    /** 
    @param _pid index of the token in the array of pools
    @param _amount amount of tokens that will be deposited to farm reward tokens

    This method deposits tokens into smart contract to start farming tokens in a specified reward pool.
    Transfers reward tokens for that user into the smart contract from the reservoir.
    Updates the total deposited amount of tokens into the smart contract.
    Updates the total amount of pending rewards that is required for future distibutions.
    Updates personal user amount of staked tokens into the smart contract in a specified reward pool.
    Creates a track of user's final reward in case he/she/they won't leave from the pool till the end of the event.
    */
    function depositLPT(uint256 _pid, uint256 _amount) external {
        require(block.timestamp <= poolInfo[_pid].endTime, "Deposit time has come to an end");
        require(_amount > 0, "No point to deposit 0");

        UserPoolInfo storage _userPoolInfo = userPoolInfo[msg.sender][_pid];

        poolInfo[_pid].stakedAmount = poolInfo[_pid].stakedAmount.add(_amount);
        uint256 finalRewardAmount = _calculateFinalRewardAmount(_pid, _amount);
        poolInfo[_pid].totalPendingRewards = poolInfo[_pid].totalPendingRewards.add(finalRewardAmount);
        require(
            rewardToken.balanceOf(reservoir) >= finalRewardAmount.add(poolInfo[_pid].totalPendingRewards),
            "Oops, not enough rewards for the event"
        );
        _userPoolInfo.stakedAmountLPT = _userPoolInfo.stakedAmountLPT.add(_amount);

        uint256 rewardUnlockTime = block.timestamp.add(rewardsDuration);
        finalDirtyRewardsRegister[msg.sender][_pid].push(
            FinalRewardAmount({ amount: finalRewardAmount, unlockTime: rewardUnlockTime, startTime: block.timestamp })
        );

        rewardToken.safeTransferFrom(reservoir, address(this), finalRewardAmount);
        poolInfo[_pid].token.safeTransferFrom(address(msg.sender), address(this), _amount);
        emit Deposited(msg.sender, _pid, _amount);
    }

    /**
    @param _pid index of the token in the array of pools
    @param _amount amount of tokens that user withdrows from a smart contract in a specified pool

    This method withdraws back tokens that were deposited into the smart contract in a specified pool.

    In case user didn't wait for farming event to end: creates a track of the amount of rewards,
    that user won't get to claim.
    Updates the amount of pending rewards for that pool.
    Transfer back to the reservoir extra reward tokens.

    Updates the amount of deposited tokens into the smart contract by a user.
    Updates of overal deposited tokens into the smart contract.
    */
    function withdrawLPT(uint256 _pid, uint256 _amount) external {
        require(userPoolInfo[msg.sender][_pid].stakedAmountLPT >= _amount, "Can't withdraw more than deposited");
        require(_amount > 0, "No point to withdraw 0");
        bool leftBeforeEnd = false;

        if (block.timestamp < poolInfo[_pid].endTime) {
            leftBeforeEnd = true;
            uint256 finalFalseRewardAmount = _calculateFinalRewardAmount(_pid, _amount);
            finalFalseRewardsRegister[msg.sender][_pid].push(
                FalseRewards({ amount: finalFalseRewardAmount, startTime: block.timestamp })
            );
            poolInfo[_pid].totalPendingRewards = poolInfo[_pid].totalPendingRewards.sub(finalFalseRewardAmount);
            rewardToken.safeTransfer(reservoir, finalFalseRewardAmount);
        }
        userPoolInfo[msg.sender][_pid].stakedAmountLPT = userPoolInfo[msg.sender][_pid].stakedAmountLPT.sub(_amount);
        poolInfo[_pid].stakedAmount = poolInfo[_pid].stakedAmount.sub(_amount);
        poolInfo[_pid].token.safeTransfer(address(msg.sender), _amount);
        emit Withdrawn(msg.sender, _pid, _amount, leftBeforeEnd);
    }

    /**
    @param _pid index of the token in the array of pools.
    @param _onlyVested boolean check that indicates if user withdraws only tokens that were vested,
    or whole amount with penalty on non-vested tokens.

    Calculates vested amount of tokens that can be claimed. By adding all possible rewards tracked by
    deposit events, and subbing all possible "false" rewards that were tracked by a withdraw.

    In case _onlyVested is true, transfers only vested tokens to user.
    Else, transfer vested tokens plus left tokens with a 50% penalty.
    Updates the total amount of pending rewards in a pool.
    Transfers penalty back to the reservoir.

    Updates personal amount of claimed rewards.
    */
    function claimRewards(uint256 _pid, bool _onlyVested) external {
        uint256 totalClaimableReward;
        uint256 idx = finalDirtyRewardsRegister[msg.sender][_pid].length;
        uint256 idxFalse = finalFalseRewardsRegister[msg.sender][_pid].length;
        uint256 vestedReward;
        for (uint256 i = 0; i < idx; i++) {
            totalClaimableReward = totalClaimableReward.add(finalDirtyRewardsRegister[msg.sender][_pid][i].amount);

            uint256 passedDirty = block.timestamp.sub(finalDirtyRewardsRegister[msg.sender][_pid][i].startTime);
            uint256 calcVestedReward = finalDirtyRewardsRegister[msg.sender][_pid][i].amount.mul(passedDirty);
            calcVestedReward = PRBMathUD60x18.div(calcVestedReward, rewardsDuration);

            vestedReward = vestedReward.add(calcVestedReward);
        }
        for (uint256 k = 0; k < idxFalse; k++) {
            totalClaimableReward = totalClaimableReward.sub(finalFalseRewardsRegister[msg.sender][_pid][k].amount);
            uint256 passedFalse = block.timestamp.sub(finalFalseRewardsRegister[msg.sender][_pid][k].startTime);
            uint256 calcVestedFalse = finalFalseRewardsRegister[msg.sender][_pid][k].amount.mul(passedFalse);
            calcVestedFalse = PRBMathUD60x18.div(calcVestedFalse, rewardsDuration);
            vestedReward = vestedReward.sub(calcVestedFalse);
        }

        uint256 reward;
        uint256 penaltyReward;
        if (_onlyVested) {
            reward = vestedReward;
        } else {
            penaltyReward = ((totalClaimableReward.sub(vestedReward)) / 2);
            reward = vestedReward.add(penaltyReward);
            poolInfo[_pid].totalPendingRewards = poolInfo[_pid].totalPendingRewards.sub(penaltyReward);
        }
        rewardToken.safeTransferFrom(reservoir, msg.sender, reward);
        userPoolInfo[msg.sender][_pid].claimedRewards = userPoolInfo[msg.sender][_pid].claimedRewards.add(reward);

        emit Claimed(msg.sender, _pid, reward, penaltyReward);
    }

    /* ======================== VIEWS ======================== */

    /**
    @param _token address of token
    */
    function isTokenAdded(IERC20 _token) public view returns (bool) {
        uint256 pid = poolPidByAddress[address(_token)];
        return poolInfo.length > pid && address(poolInfo[pid].token) == address(_token);
    }

    /**
    @param _pid pool index
    @param _amount amount of tokens for calculation

    Returns number of rewards that will be farmed/not farmed
    */
    function _calculateFinalRewardAmount(uint256 _pid, uint256 _amount) internal view returns (uint256) {
        return
            _amount.mul(poolInfo[_pid].rewardRateNumerator).mul((poolInfo[_pid].endTime - block.timestamp)).div(
                poolInfo[_pid].endTime - poolInfo[_pid].startTime
            ).div(1e18);
    }

    /**
    
    Returns total amount of vested rewards that can be claimed by user
    */
    function getTotalRewardsAfterVestingForAllPools() public view returns (uint256 totalReward) {
        uint256 dirtyClaimableReward;
        uint256 dirtyFalseReward;
        for (uint256 l; l < poolInfo.length; l++) {
            uint256 idx = finalDirtyRewardsRegister[msg.sender][l].length;
            uint256 idxFalse = finalFalseRewardsRegister[msg.sender][l].length;
            for (uint256 i = 0; i < idx; i++) {
                dirtyClaimableReward = dirtyClaimableReward.add(finalDirtyRewardsRegister[msg.sender][l][i].amount);
            }
            for (uint256 k = 0; k < idxFalse; k++) {
                dirtyFalseReward = dirtyFalseReward.add(finalFalseRewardsRegister[msg.sender][l][k].amount);
            }
        }
        totalReward = totalReward.add(dirtyClaimableReward.sub(dirtyFalseReward));
        return totalReward;
    }

    function getTotalClaimableVestedRewards() public view returns (uint256 reward) {
        uint256 totalClaimableReward;
        uint256 vestedReward;
        for (uint256 l; l <= poolInfo.length; l++) {
            uint256 idx = finalDirtyRewardsRegister[msg.sender][l].length;
            uint256 idxFalse = finalFalseRewardsRegister[msg.sender][l].length;

            for (uint256 i = 0; i < idx; i++) {
                totalClaimableReward = totalClaimableReward.add(finalDirtyRewardsRegister[msg.sender][l][i].amount);

                uint256 passedDirty = block.timestamp.sub(finalDirtyRewardsRegister[msg.sender][l][i].startTime);
                uint256 calcVestedReward = PRBMathUD60x18.mul(
                    finalDirtyRewardsRegister[msg.sender][l][i].amount,
                    passedDirty
                );
                calcVestedReward = PRBMathUD60x18.div(calcVestedReward, rewardsDuration);

                vestedReward = vestedReward.add(calcVestedReward);
            }
            for (uint256 k = 0; k < idxFalse; k++) {
                totalClaimableReward = totalClaimableReward.sub(finalFalseRewardsRegister[msg.sender][l][k].amount);

                uint256 passedFalse = block.timestamp.sub(finalFalseRewardsRegister[msg.sender][l][k].startTime);
                uint256 calcVestedFalse = PRBMathUD60x18.mul(
                    finalFalseRewardsRegister[msg.sender][l][k].amount,
                    passedFalse
                );
                calcVestedFalse = PRBMathUD60x18.div(calcVestedFalse, rewardsDuration);

                vestedReward = vestedReward.sub(calcVestedFalse);
            }
        }
        reward = vestedReward;
    }

    function getClaimableVestedRewardsForSpecificPool(uint256 _pid) public view returns (uint256 reward) {
        uint256 totalClaimableReward;
        uint256 vestedReward;
        uint256 idx = finalDirtyRewardsRegister[msg.sender][_pid].length;
        uint256 idxFalse = finalFalseRewardsRegister[msg.sender][_pid].length;

        for (uint256 i = 0; i < idx; i++) {
            totalClaimableReward = totalClaimableReward.add(finalDirtyRewardsRegister[msg.sender][_pid][i].amount);

            uint256 passedDirty = block.timestamp.sub(finalDirtyRewardsRegister[msg.sender][_pid][i].startTime);
            uint256 calcVestedReward = PRBMathUD60x18.mul(
                finalDirtyRewardsRegister[msg.sender][_pid][i].amount,
                passedDirty
            );
            calcVestedReward = PRBMathUD60x18.div(calcVestedReward, rewardsDuration);

            vestedReward = vestedReward.add(calcVestedReward);
        }
        for (uint256 k = 0; k < idxFalse; k++) {
            totalClaimableReward = totalClaimableReward.sub(finalFalseRewardsRegister[msg.sender][_pid][k].amount);

            uint256 passedFalse = block.timestamp.sub(finalFalseRewardsRegister[msg.sender][_pid][k].startTime);
            uint256 calcVestedFalse = PRBMathUD60x18.mul(
                finalFalseRewardsRegister[msg.sender][_pid][k].amount,
                passedFalse
            );
            calcVestedFalse = PRBMathUD60x18.div(calcVestedFalse, rewardsDuration);

            vestedReward = vestedReward.sub(calcVestedFalse);
        }
        reward = vestedReward;
    }
}
