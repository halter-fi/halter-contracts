// SPDX-License-Identifier: MIT

//
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract LiquidityRewards is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20 for IERC20;

    struct WeekInfo {
        uint256 startTime; // 00:00 Monday of the week
        uint256 endTime; // 23:59 Sunday of the same week
        uint256 rewardRate;
        uint256 totalStakedAmount;
        uint256 highestStakedPoint;
        bool isUpdated;
    }
    struct UserStake {
        uint256 staked;
        uint256 secondsTillWeekEnd;
        uint256 weekNumber;
        uint256 lastWeekCalculated;
    }
    struct UserWithdraw {
        uint256 stakesWithdrawn;
        uint256 secondsTillWeekEnd;
        uint256 weekNumber;
        uint256 lastWeekCalculated;
    }
    struct CalcUnvestedReward {
        uint256 amount;
        uint256 unlockTime;
        uint256 recordTime;
    }

    IERC20 public stakeToken;
    IERC20 public rewardToken;
    address public reservoir;
    uint256 public rewardsVestingDuration;
    uint256 public depositEndTime;
    uint256 public constant secondsInAWeek = 604800;
    uint256 public constant withdrawUnlockTime = 604800;
    uint256 public constant rewardRateCoeff = 1e18;

    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    mapping(address => uint256) public userStaked;
    mapping(uint256 => WeekInfo) public weekInfo; // returns info about specific week. See structure "WeekInfo"
    mapping(address => UserStake[]) public userStake; // returns info about user stakes in a specific week
    mapping(address => UserWithdraw[]) public userWithdraw; // returns info about user withdraws in a specific week
    mapping(address => CalcUnvestedReward[]) public rewardUnclaimed; // returns amount of calculated unclaimed rewards
    mapping(address => uint256) public falseRewardClaimed; // returns amount of "falsly" claimed "false" rewards
    mapping(address => CalcUnvestedReward[]) public falseRewardUnclaimed; // returns the amount of "false"

    /* ============================== EVENTS ============================== */
    event Staked(address staker, uint256 weekNumber, uint256 amount);
    event Withdrawn(address staker, uint256 amount);
    event Claimed(address claimer, uint256 amount);
    event EmergencyClaimed(address claimer, uint256 rewardAmount, uint256 penaltyAmount);

    /* ======================== INITIALIZER ======================== */
    function initialize(
        address _reservoir,
        IERC20 _rewardToken,
        IERC20 _stakeToken,
        uint256 _startWeekNumber,
        uint256 _startWeekStartTime,
        uint256 _startWeekEndTime,
        uint256 _amountOfWeeksToSet,
        uint256 _rewardsVestingDuration,
        uint256 _depositEndTime,
        address _treasury,
        address _updater
    ) external initializer {
        __AccessControl_init();
        _setupRole(TREASURY_ROLE, _treasury);
        _setupRole(UPDATER_ROLE, _updater);
        reservoir = _reservoir;
        rewardToken = _rewardToken;
        stakeToken = _stakeToken;
        rewardsVestingDuration = _rewardsVestingDuration;
        depositEndTime = _depositEndTime;
        setWeekInfo(_startWeekNumber, _startWeekStartTime, _startWeekEndTime, _amountOfWeeksToSet);
    }

    modifier duringCorrectWeek(uint256 _weekNumber) {
        require(
            weekInfo[_weekNumber].endTime >= block.timestamp && weekInfo[_weekNumber].startTime <= block.timestamp,
            "Invalid week number"
        );
        _;
    }

    modifier updated(uint256 _weekNumber) {
        require(weekInfo[_weekNumber].isUpdated == true, "Week data not set yet");
        _;
    }

    /* ==================================================================== */
    /* ========================= OWNER FUNCTIONS ========================== */
    /* ==================================================================== */
    /**
    @param _weekNumber starting calendar week number, that is going to be updated
    @param _startTime 00:00 timestamp of Monday of _weekNumber. UTC time zone.
    @param _endTime 23:59 timestmap of Sunday of _weekNumber. UTC time zone.
    @param _amountOfWeeks amount of weeks ahead of _weekNumber that you would like to update
     */
    function setWeekInfo(
        uint256 _weekNumber,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _amountOfWeeks
    ) public onlyRole(TREASURY_ROLE) {
        weekInfo[_weekNumber].startTime = _startTime;
        weekInfo[_weekNumber].endTime = _endTime;
        for (uint256 i = _weekNumber; i < (_weekNumber + _amountOfWeeks); i++) {
            _startTime = _startTime.add(secondsInAWeek);
            _endTime = _endTime.add(secondsInAWeek);
            uint256 weekNumber = i.add(1);
            weekInfo[weekNumber].startTime = _startTime;
            weekInfo[weekNumber].endTime = _endTime;
        }
    }

    /**
    @param _weekNumber calendar week number, that will be updated
    @param _rewardRate rate per Halter token per second
    */
    function setWeekState(uint256 _weekNumber, uint256 _rewardRate) public onlyRole(UPDATER_ROLE) {
        weekInfo[_weekNumber].rewardRate = _rewardRate;
        weekInfo[_weekNumber + 1].totalStakedAmount = stakeToken.balanceOf(address(this));
        weekInfo[_weekNumber + 1].highestStakedPoint = weekInfo[_weekNumber].totalStakedAmount;
        weekInfo[_weekNumber].isUpdated = true;
    }

    /* ==================================================================== */
    /* ======================== MUTATIVE FUNCTIONS ======================== */
    /* ==================================================================== */

    /**
    @param _amount amount of tokens that user would like to stake
    @param _weekNumber current weekNumber. Sent in externally to minimize gas costs.
    This method stakes stakeToken into the contract.
    Checks if amount is bigger than 0 and with weekNumber is correct before implementing method.
    Updates: 
      | Total amount of stakes done during the week _weekNumber
      | User's stakes amount done during whole smart contract existence
    Saves amount, of how many seconds are left until 23:59:59 of sunday of _weekNumber, and _weekNumber into
    an array of user's stake, for further tracking.
    Transfers stakeToken from user to contract.
    */
    function stake(uint256 _amount, uint256 _weekNumber)
        public
        duringCorrectWeek(_weekNumber)
        nonReentrant
    {
        require(_amount >= 0, "Can't stake 0");
        require(block.timestamp < depositEndTime, "Too late to deposit");

        weekInfo[_weekNumber].totalStakedAmount = weekInfo[_weekNumber].totalStakedAmount.add(_amount);
        if (weekInfo[_weekNumber].totalStakedAmount > weekInfo[_weekNumber].highestStakedPoint) {
            weekInfo[_weekNumber].highestStakedPoint = weekInfo[_weekNumber].totalStakedAmount;
        }
        userStaked[msg.sender] = userStaked[msg.sender].add(_amount);

        userStake[msg.sender].push(
            UserStake({
                staked: _amount,
                secondsTillWeekEnd: _secondsBeforeWeekEnd(_weekNumber),
                weekNumber: _weekNumber,
                lastWeekCalculated: 0
            })
        );
        stakeToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _weekNumber, _amount);
    }

    /**
    @param _amount amount of stakeToken that user wants to withdraw back from the contract
    @param _weekNumber current weekNumber. Sent in externally to minimize gas costs.
    This method withdraws stakeTokens from the contract back to the user.
    Before the method check that _amount is more than 0 and that _weekNumber is correct.
    Checks if user invested less or equal _amount of rewardToken in the past.
    Updates: 
        | Total rewardToken withdraws during the week
        | User's stakes amount done during whole smart contract existence
    
    Saves amount, of how many seconds are left until 23:59:59 of sunday of _weekNumber, and _weekNumber into
    an array of user's withdraw, for further tracking.
    */
    function withdraw(uint256 _amount, uint256 _weekNumber)
        public
        duringCorrectWeek(_weekNumber)
        nonReentrant
    {
        require(_amount > 0, "Can't withdraw 0");
        require(userStaked[msg.sender] >= _amount, "Can't withdraw more than deposited");

        weekInfo[_weekNumber].totalStakedAmount = weekInfo[_weekNumber].totalStakedAmount.sub(_amount);
        userWithdraw[msg.sender].push(
            UserWithdraw({
                stakesWithdrawn: _amount,
                secondsTillWeekEnd: _secondsBeforeWeekEnd(_weekNumber),
                weekNumber: _weekNumber,
                lastWeekCalculated: 0
            })
        );
        userStaked[msg.sender] = userStaked[msg.sender].sub(_amount);

        stakeToken.safeTransfer(msg.sender, _amount);
        emit Withdrawn(msg.sender, _amount);
    }

    /**
    @param _weekNumber current weekNumber. Sent in externally to minimize gas costs.
    This method claims rewardToken that got vested. Itirates through every stake that user has ever done,
    and through every withdraw that user has made to calculate
    "dirty amount of rewards" and "dirty amount of withdraws".
    MATHEMATICAL LOGIC:
    Mathematical logic is like that: as soon as user stakes his tokens in we assume he/she/they
    is never going leave the pool, making the rewards farm eternal.
    However, if the user does leave, we track the amount of rewards that he/she/they
    started loosing from the moment of leave.
    Such calculation also happens eternally. In order to minimize amount of iterations in future,
    users will calculate their
    rewards only once for weeks that have passed.
    In the end we sub the amount of "dirty false rewards" from the "dirty rewards",
    getting us the right amount of rewards, that user should get. 
    Later on the amount goes through the vesting period. Vested rewards are given to user.
    Other rewards are getting memorized so that user wouldn't have to recalculate them again in future.
    Transfers vested reward from the reservoir to the user
    */
    function claimRewards(uint256 _weekNumber) public duringCorrectWeek(_weekNumber) nonReentrant updated(_weekNumber) {
        uint256 reward;
        uint256 vestedDirtyReward = _calculateVestedDirtyReward(_weekNumber);
        uint256 vestedDirtyWithdraw = _calculateVestedDirtyWithdraw(_weekNumber);
        vestedDirtyWithdraw = vestedDirtyWithdraw.add(_getFalseVestedReward());
        vestedDirtyReward = vestedDirtyReward.add(_getVestedReward());
        if (vestedDirtyReward < vestedDirtyWithdraw) {
            reward = 0;
        } else {
            reward = vestedDirtyReward - vestedDirtyWithdraw;
        }
        require(reward > 0, "Can't claim 0");
        rewardToken.safeTransferFrom(reservoir, msg.sender, reward);

        emit Claimed(msg.sender, reward);
    }

    function emergencyClaim(uint256 _weekNumber)
        public
        duringCorrectWeek(_weekNumber)
        nonReentrant
        updated(_weekNumber)
    {
        uint256 reward;
        uint256 vestedDirtyReward = _calculateVestedDirtyReward(_weekNumber);
        uint256 vestedDirtyWithdraw = _calculateVestedDirtyWithdraw(_weekNumber);
        vestedDirtyWithdraw = vestedDirtyWithdraw.add(_getFalseVestedReward());
        vestedDirtyReward = vestedDirtyReward.add(_getVestedReward());
        if (vestedDirtyReward < vestedDirtyWithdraw) {
            reward = 0;
        } else {
            reward = vestedDirtyReward - vestedDirtyWithdraw;
        }

        uint256 penalty;
        for (uint256 i = 0; i < rewardUnclaimed[msg.sender].length; i++) {
            if (rewardUnclaimed[msg.sender][i].unlockTime <= block.timestamp) {
                reward = reward.add(rewardUnclaimed[msg.sender][i].amount);
                rewardUnclaimed[msg.sender][i].amount = rewardUnclaimed[msg.sender][i].amount.sub(reward);
            } else {
                reward = reward.add(rewardUnclaimed[msg.sender][i].amount.div(2));
                penalty = penalty.add(reward);
            }
            rewardUnclaimed[msg.sender][i].amount = 0;
        }
        for (uint256 l = 0; l < falseRewardUnclaimed[msg.sender].length; l++) {
            if (falseRewardUnclaimed[msg.sender][l].unlockTime <= block.timestamp) {
                reward = reward.sub(falseRewardUnclaimed[msg.sender][l].amount);
            } else {
                reward = reward.sub(falseRewardUnclaimed[msg.sender][l].amount.div(2));
                penalty = penalty.sub(falseRewardUnclaimed[msg.sender][l].amount.div(2));
            }
            falseRewardUnclaimed[msg.sender][l].amount = 0;
        }
        rewardToken.safeTransferFrom(reservoir, msg.sender, reward);
        emit EmergencyClaimed(msg.sender, reward, penalty);
    }

    function emergencyWeekUnlock(uint256 _weekNumber) public onlyRole(EMERGENCY_ROLE) {
        weekInfo[_weekNumber].isUpdated = true;
    }

    /* ==================================================================== */
    /* ======================== VIEW FUNCTIONS ============================ */
    /* ==================================================================== */

    function viewVestedRewards(uint256 _weekNumber)
        public
        view
        duringCorrectWeek(_weekNumber)
        returns (uint256 reward)
    {
        if (userStake[msg.sender].length > 0) {
            uint256 vestedDirtyReward = _viewVestedReward();
            uint256 vestedDirtyWithdraw = _viewFalseVestedReward();
            vestedDirtyWithdraw = vestedDirtyWithdraw.add(_viewVestedDirtyWithdraw(_weekNumber));
            vestedDirtyReward = vestedDirtyReward.add(_viewVestedDirtyReward(_weekNumber));
            reward = vestedDirtyReward - vestedDirtyWithdraw;
        } else {
            revert("User hasn't staked anything");
        }
    }

    function viewTotalRewards(uint256 _weekNumber) public view duringCorrectWeek(_weekNumber) returns (uint256 reward) {
        if (userStake[msg.sender].length > 0) {
            uint256 vestedDirtyReward = _viewTotalDirtyReward(_weekNumber);
            uint256 vestedDirtyWithdraw = _viewTotalDirtyWithdraw(_weekNumber);
            vestedDirtyWithdraw = vestedDirtyWithdraw.add(_viewTotalFalseReward());
            vestedDirtyReward = vestedDirtyReward.add(_viewTotalReward());
            reward = vestedDirtyReward - vestedDirtyWithdraw;
        } else {
            revert("User hasn't staked anything");
        }
    }

    function viewEmergencyRewards(uint256 _weekNumber)
        public
        view
        duringCorrectWeek(_weekNumber)
        returns (uint256 reward)
    {
        uint256 vestedDirtyReward = _viewTotalDirtyReward(_weekNumber);
        uint256 vestedDirtyWithdraw = _viewTotalDirtyWithdraw(_weekNumber);
        vestedDirtyWithdraw = vestedDirtyWithdraw.add(_viewTotalFalseReward());
        vestedDirtyReward = vestedDirtyReward.add(_viewTotalReward());
        if (vestedDirtyReward < vestedDirtyWithdraw) {
            reward = 0;
        } else {
            reward = vestedDirtyReward - vestedDirtyWithdraw;
        }

        uint256 penalty;
        for (uint256 i = 0; i < rewardUnclaimed[msg.sender].length; i++) {
            if (rewardUnclaimed[msg.sender][i].unlockTime <= block.timestamp) {
                reward = reward.add(rewardUnclaimed[msg.sender][i].amount);
            } else {
                reward = reward.add(rewardUnclaimed[msg.sender][i].amount.div(2));
                penalty = penalty.add(reward);
            }
        }
        for (uint256 l = 0; l < falseRewardUnclaimed[msg.sender].length; l++) {
            if (falseRewardUnclaimed[msg.sender][l].unlockTime <= block.timestamp) {
                reward = reward.sub(falseRewardUnclaimed[msg.sender][l].amount);
            } else {
                reward = reward.sub(falseRewardUnclaimed[msg.sender][l].amount.div(2));
                penalty = penalty.sub(falseRewardUnclaimed[msg.sender][l].amount.div(2));
            }
        }
    }

    /* ==================================================================== */
    /* ======================== INTERNAL FUNCTIONS ======================== */
    /* ==================================================================== */
    function _calcAllWithdrawsAgain(uint256 _index, uint256 _weekNumber)
        internal
        view
        returns (uint256 totalVestedWithdraw)
    {
        for (uint256 k = (userWithdraw[msg.sender][_index].lastWeekCalculated.add(1)); k < _weekNumber; k++) {
            uint256 weeklyReward = secondsInAWeek.mul(weekInfo[k].rewardRate);
            totalVestedWithdraw = totalVestedWithdraw.add(weeklyReward);
        }
    }

    function _viewTotalFalseReward() internal view returns (uint256 reward) {
        for (uint256 i = 0; i < falseRewardUnclaimed[msg.sender].length; i++) {
            reward = reward.add(falseRewardUnclaimed[msg.sender][i].amount);
        }
    }

    function _viewTotalReward() internal view returns (uint256 reward) {
        for (uint256 i = 0; i < rewardUnclaimed[msg.sender].length; i++) {
            reward = reward.add(rewardUnclaimed[msg.sender][i].amount);
        }
    }

    function _viewTotalDirtyWithdraw(uint256 _weekNumber) internal view returns (uint256 totalVestedWithdraw) {
        uint256 idx = userWithdraw[msg.sender].length;
        for (uint256 i = 0; i < idx; i++) {
            if (userWithdraw[msg.sender][i].weekNumber != _weekNumber) {
                uint256 week = userWithdraw[msg.sender][i].weekNumber;
                // Checks if user had claimed rewards before, so that calculations for the same weeks
                // wouldn't get recalculated again
                if (userWithdraw[msg.sender][i].lastWeekCalculated > 0) {
                    if (
                        weekInfo[userWithdraw[msg.sender][i].lastWeekCalculated.sub(1)].endTime > weekInfo[week].endTime
                    ) {
                        require(
                            userWithdraw[msg.sender][i].lastWeekCalculated.sub(1) != _weekNumber,
                            "New rewards weren't calculated yet"
                        );
                        totalVestedWithdraw = totalVestedWithdraw.add(_calcAllWithdrawsAgain(i, _weekNumber));
                    }
                } else {
                    uint256 vestedReward = weekInfo[week].rewardRate.mul(secondsInAWeek).mul(
                        userWithdraw[msg.sender][i].stakesWithdrawn
                    );

                    totalVestedWithdraw = totalVestedWithdraw.add(vestedReward);

                    // Calculates reward amount for each week that has passed after the first week of stake
                    // following the same logic as used in a first week.
                    for (uint256 l = (week.add(1)); l < _weekNumber; l++) {
                        totalVestedWithdraw = totalVestedWithdraw.add(secondsInAWeek.mul(weekInfo[l].rewardRate));
                    }
                }
            }
        }
    }

    function _calcAllStakesAgain(uint256 _index, uint256 _weekNumber)
        internal
        view
        returns (uint256 totalVestedReward)
    {
        for (uint256 k = (userStake[msg.sender][_index].lastWeekCalculated.add(1)); k < _weekNumber; k++) {
            uint256 weeklyReward = secondsInAWeek.mul(weekInfo[k].rewardRate);
            totalVestedReward = totalVestedReward.add(weeklyReward);
        }
    }

    function _viewTotalDirtyReward(uint256 _weekNumber) internal view returns (uint256 totalVestedReward) {
        uint256 idx = userStake[msg.sender].length;
        for (uint256 i = 0; i < idx; i++) {
            if (userStake[msg.sender][i].weekNumber != _weekNumber) {
                uint256 week = userStake[msg.sender][i].weekNumber;
                // Checks if user had claimed rewards before, so that calculations for the same weeks
                // wouldn't get recalculated again
                if (userStake[msg.sender][i].lastWeekCalculated > 0) {
                    totalVestedReward = totalVestedReward.add(_calcAllStakesAgain(i, _weekNumber));
                } else {
                    uint256 vestedReward = weekInfo[week].rewardRate.mul(userStake[msg.sender][i].staked).div(
                        rewardRateCoeff
                    );

                    totalVestedReward = totalVestedReward.add(vestedReward);
                }

                // Calculates reward amount for each week that has passed after the first week of stake
                // following the same logic as used in a first week.
                for (uint256 l = (week.add(1)); l < _weekNumber; l++) {
                    totalVestedReward = totalVestedReward.add(
                        weekInfo[l].rewardRate.mul(userStake[msg.sender][i].staked).div(rewardRateCoeff)
                    );
                }
            }
        }
    }

    function _getVestedDirtyWithdraw(uint256 _weekNumber, uint256 _idx)
        internal
        view
        returns (uint256 vestedDirtyWithdraw)
    {
        uint256 totalDirtyWithdraw;
        for (uint256 i = 0; i < _idx; i++) {
            if (userWithdraw[msg.sender][i].weekNumber != _weekNumber) {
                uint256 week = userWithdraw[msg.sender][i].weekNumber;
                uint256 dirtyWithdraw = userWithdraw[msg.sender][i].stakesWithdrawn.mul(weekInfo[week].rewardRate).mul(
                    userStake[msg.sender][i].secondsTillWeekEnd
                );
                uint256 weeksPassed = _weekNumber.sub(week).sub(1);
                uint256 timePassed = userWithdraw[msg.sender][i].secondsTillWeekEnd.add(
                    weeksPassed.mul(secondsInAWeek)
                );
                uint256 timeLeft;
                if (timePassed > rewardsVestingDuration) {
                    timeLeft = 0;
                } else {
                    timeLeft = rewardsVestingDuration.sub(timePassed);
                }
                for (uint256 k = (week.add(1)); k <= _weekNumber; k++) {
                    dirtyWithdraw = dirtyWithdraw.add(secondsInAWeek.mul(weekInfo[k].rewardRate));
                }

                totalDirtyWithdraw = totalDirtyWithdraw.add(dirtyWithdraw);
                if (timeLeft > 0) {
                    vestedDirtyWithdraw = vestedDirtyWithdraw.add(
                        totalDirtyWithdraw.div(rewardsVestingDuration.div(timePassed))
                    );
                } else {
                    vestedDirtyWithdraw = vestedDirtyWithdraw.add(totalDirtyWithdraw);
                }
            }
        }
    }

    function _calcUnvestedStake(
        uint256 _weekIndex,
        uint256 _stakeIndex,
        uint256 _vestedReward,
        uint256 _time
    ) internal view returns (uint256 unvestedReward) {
        unvestedReward = weekInfo[_weekIndex].rewardRate.mul(_time).mul(userStake[msg.sender][_stakeIndex].staked);
        unvestedReward = unvestedReward.div(secondsInAWeek).div(rewardRateCoeff);
        unvestedReward = _vestedReward > unvestedReward ? 0 : unvestedReward.sub(_vestedReward);
    }

    function _calcUnvestedWithdraw(
        uint256 _weekIndex,
        uint256 _stakeIndex,
        uint256 _vestedReward,
        uint256 _time
    ) internal view returns (uint256 unvestedWithdraw) {
        unvestedWithdraw = weekInfo[_weekIndex].rewardRate.mul(_time).mul(
            userWithdraw[msg.sender][_stakeIndex].stakesWithdrawn
        );
        unvestedWithdraw = unvestedWithdraw.div(secondsInAWeek).div(rewardRateCoeff);
        unvestedWithdraw = _vestedReward > unvestedWithdraw ? 0 : unvestedWithdraw.sub(_vestedReward);
    }

    function _calcVestedWithdraw(
        uint256 _weekIndex,
        uint256 _stakeIndex,
        uint256 _secondsPassed,
        uint256 _time
    ) internal view returns (uint256 vestedWithdraw) {
        vestedWithdraw = weekInfo[_weekIndex]
            .rewardRate
            .mul(_time)
            .mul(userWithdraw[msg.sender][_stakeIndex].stakesWithdrawn)
            .mul(_secondsPassed);
        vestedWithdraw = vestedWithdraw.div(secondsInAWeek).div(rewardRateCoeff).div(rewardsVestingDuration);
    }

    function _calcVestedStake(
        uint256 _weekIndex,
        uint256 _stakeIndex,
        uint256 _secondsPassed,
        uint256 _time
    ) internal view returns (uint256 vestedReward) {
        vestedReward = weekInfo[_weekIndex].rewardRate.mul(_time).mul(userStake[msg.sender][_stakeIndex].staked).mul(
            _secondsPassed
        );
        vestedReward = vestedReward.div(secondsInAWeek).div(rewardRateCoeff).div(rewardsVestingDuration);
    }

    function _calculateVestedDirtyWithdraw(uint256 _weekNumber) internal returns (uint256 totalVestedWithdraw) {
        for (uint256 i = 0; i < userWithdraw[msg.sender].length; i++) {
            if (userWithdraw[msg.sender][i].weekNumber != _weekNumber) {
                uint256 week = userWithdraw[msg.sender][i].weekNumber;
                uint256 secondsPassed;
                // Checks if user had claimed rewards before, so that calculations for the same weeks
                // wouldn't get recalculated again
                if (userWithdraw[msg.sender][i].lastWeekCalculated > 0) {
                    totalVestedWithdraw = totalVestedWithdraw.add(_calcWithdrawsAgain(i, _weekNumber));
                } else {
                    secondsPassed = _calculateVestedTime(week).add(userWithdraw[msg.sender][i].secondsTillWeekEnd);

                    // Checks if vesting period for that week has passed
                    if (secondsPassed > rewardsVestingDuration) {
                        // If true: adds whole reward amount into the total reward amount
                        uint256 vestedReward = weekInfo[week]
                            .rewardRate
                            .mul(userWithdraw[msg.sender][i].secondsTillWeekEnd)
                            .mul(userWithdraw[msg.sender][i].stakesWithdrawn);
                        vestedReward = vestedReward.div(rewardRateCoeff).div(secondsInAWeek);

                        totalVestedWithdraw = totalVestedWithdraw.add(vestedReward);
                    } else {
                        // Otherwise: calculates what amount has been vested yet and what hasnt'
                        uint256 vestedReward = _calcVestedWithdraw(
                            week,
                            i,
                            secondsPassed,
                            userWithdraw[msg.sender][i].secondsTillWeekEnd
                        );
                        totalVestedWithdraw = totalVestedWithdraw.add(vestedReward);
                        uint256 unvestedReward = _calcVestedWithdraw(week, i, vestedReward, secondsPassed);
                        falseRewardUnclaimed[msg.sender].push(
                            CalcUnvestedReward({
                                amount: unvestedReward,
                                unlockTime: block.timestamp.add(rewardsVestingDuration.sub(secondsPassed)),
                                recordTime: block.timestamp
                            })
                        );
                    }
                }
                // Calculates reward amount for each week that has passed after the first week of stake
                // following the same logic as used in a first week.
                uint256 l;
                if (userWithdraw[msg.sender][i].lastWeekCalculated == 0) {
                    l = week.add(1);
                } else {
                    l = userWithdraw[msg.sender][i].lastWeekCalculated;
                }
                for (l; l < _weekNumber; l++) {
                    if (l != _weekNumber) {
                        uint256 weeklyReward = weekInfo[l].rewardRate.mul(userStake[msg.sender][i].staked).div(
                            rewardRateCoeff
                        );
                        secondsPassed = _calculateVestedTime(l).add(secondsInAWeek);
                        if (secondsPassed > rewardsVestingDuration) {
                            totalVestedWithdraw = totalVestedWithdraw.add(weeklyReward);
                        } else {
                            uint256 vestedReward = _calcVestedWithdraw(l, i, secondsPassed, secondsInAWeek);
                            totalVestedWithdraw = totalVestedWithdraw.add(vestedReward);
                            uint256 unvestedReward = _calcUnvestedWithdraw(l, i, vestedReward, secondsInAWeek);
                            //  Updates user's unclaimed rewards
                            falseRewardUnclaimed[msg.sender].push(
                                CalcUnvestedReward({
                                    amount: unvestedReward,
                                    unlockTime: block.timestamp.add(rewardsVestingDuration.sub(secondsPassed)),
                                    recordTime: block.timestamp
                                })
                            );
                        }
                    }
                }
            }
            // Updates the time that user's rewards for that stake were calculated
            userWithdraw[msg.sender][i].lastWeekCalculated = _weekNumber;
        }
    }

    function _viewVestedDirtyWithdraw(uint256 _weekNumber) internal view returns (uint256 totalVestedWithdraw) {
        for (uint256 i = 0; i < userWithdraw[msg.sender].length; i++) {
            if (userWithdraw[msg.sender][i].weekNumber != _weekNumber) {
                uint256 week = userWithdraw[msg.sender][i].weekNumber;
                uint256 secondsPassed;
                // Checks if user had claimed rewards before, so that calculations for the same weeks
                // wouldn't get recalculated again
                if (userWithdraw[msg.sender][i].lastWeekCalculated > 0) {
                    totalVestedWithdraw = totalVestedWithdraw.add(_calcWithdrawsAgain(i, _weekNumber));
                } else {
                    secondsPassed = _calculateVestedTime(week).add(userWithdraw[msg.sender][i].secondsTillWeekEnd);

                    // Checks if vesting period for that week has passed
                    if (secondsPassed > rewardsVestingDuration) {
                        // If true: adds whole reward amount into the total reward amount
                        uint256 vestedReward = weekInfo[week]
                            .rewardRate
                            .mul(userWithdraw[msg.sender][i].secondsTillWeekEnd)
                            .mul(userWithdraw[msg.sender][i].stakesWithdrawn);
                        vestedReward = vestedReward.div(rewardRateCoeff).div(secondsInAWeek);

                        totalVestedWithdraw = totalVestedWithdraw.add(vestedReward);
                    } else {
                        // Otherwise: calculates what amount has been vested yet and what hasnt'
                        uint256 vestedReward = _calcVestedWithdraw(
                            week,
                            i,
                            secondsPassed,
                            userWithdraw[msg.sender][i].secondsTillWeekEnd
                        );
                        totalVestedWithdraw = totalVestedWithdraw.add(vestedReward);
                    }
                }

                // Calculates reward amount for each week that has passed after the first week of stake
                // following the same logic as used in a first week.
                uint256 l;
                if (userWithdraw[msg.sender][i].lastWeekCalculated == 0) {
                    l = week.add(1);
                } else {
                    l = userWithdraw[msg.sender][i].lastWeekCalculated;
                }
                for (l; l < _weekNumber; l++) {
                    if (l != _weekNumber) {
                        uint256 weeklyReward = weekInfo[l]
                            .rewardRate
                            .mul(userWithdraw[msg.sender][i].stakesWithdrawn)
                            .div(rewardRateCoeff);
                        secondsPassed = _calculateVestedTime(l).add(secondsInAWeek);
                        if (secondsPassed > rewardsVestingDuration) {
                            totalVestedWithdraw = totalVestedWithdraw.add(weeklyReward);
                        } else {
                            uint256 vestedReward = _calcVestedWithdraw(l, i, secondsPassed, secondsInAWeek);
                            totalVestedWithdraw = totalVestedWithdraw.add(vestedReward);
                        }
                    }
                }
            }
        }
    }

    function _calcStakesAgain(uint256 _index, uint256 _weekNumber) internal view returns (uint256 totalVestedReward) {
        for (uint256 k = (userStake[msg.sender][_index].lastWeekCalculated.add(1)); k < _weekNumber; k++) {
            uint256 secondsPassed = _calculateVestedTime(k).add(secondsInAWeek);
            uint256 weeklyReward = userStake[msg.sender][_index].staked.mul(weekInfo[k].rewardRate).div(
                rewardRateCoeff
            );
            if (secondsPassed > rewardsVestingDuration) {
                totalVestedReward = totalVestedReward.add(weeklyReward);
            } else {
                uint256 vestedReward = _calcVestedStake(k, _index, secondsPassed, secondsInAWeek);
                totalVestedReward = totalVestedReward.add(vestedReward);
            }
        }
    }

    function _calcWithdrawsAgain(uint256 _index, uint256 _weekNumber)
        internal
        view
        returns (uint256 totalVestedWithdraw)
    {
        for (uint256 k = (userWithdraw[msg.sender][_index].lastWeekCalculated.add(1)); k < _weekNumber; k++) {
            uint256 weeklyReward = secondsInAWeek.mul(weekInfo[k].rewardRate).div(rewardRateCoeff);
            uint256 secondsPassed = _calculateVestedTime(k).add(secondsInAWeek);
            if (secondsPassed > rewardsVestingDuration) {
                totalVestedWithdraw = totalVestedWithdraw.add(weeklyReward);
            } else {
                uint256 vestedReward = _calcVestedWithdraw(k, _index, secondsPassed, secondsInAWeek);
                totalVestedWithdraw = totalVestedWithdraw.add(vestedReward);
            }
        }
    }

    function _calculateVestedDirtyReward(uint256 _weekNumber) internal returns (uint256 totalVestedReward) {
        for (uint256 i = 0; i < userStake[msg.sender].length; i++) {
            if (userStake[msg.sender][i].weekNumber != _weekNumber) {
                uint256 week = userStake[msg.sender][i].weekNumber;
                uint256 secondsPassed;
                // Checks if user had claimed rewards before, so that calculations for the same weeks
                // wouldn't get recalculated again
                if (userStake[msg.sender][i].lastWeekCalculated > 0) {
                    totalVestedReward = totalVestedReward.add(_calcStakesAgain(i, _weekNumber));
                } else {
                    secondsPassed = _calculateVestedTime(week).add(userStake[msg.sender][i].secondsTillWeekEnd);

                    // Checks if vesting period for that week has passed
                    if (secondsPassed > rewardsVestingDuration) {
                        // If true: adds whole reward amount into the total reward amount
                        uint256 vestedReward = weekInfo[week]
                            .rewardRate
                            .mul(userStake[msg.sender][i].secondsTillWeekEnd)
                            .mul(userStake[msg.sender][i].staked);
                        vestedReward = vestedReward.div(rewardRateCoeff).div(secondsInAWeek);

                        totalVestedReward = totalVestedReward.add(vestedReward);
                    } else {
                        // Otherwise: calculates what amount has been vested yet and what hasnt'
                        uint256 vestedReward = _calcVestedStake(
                            week,
                            i,
                            secondsPassed,
                            userStake[msg.sender][i].secondsTillWeekEnd
                        );
                        totalVestedReward = totalVestedReward.add(vestedReward);
                        uint256 unvestedReward = _calcUnvestedStake(week, i, vestedReward, secondsPassed);
                        rewardUnclaimed[msg.sender].push(
                            CalcUnvestedReward({
                                amount: unvestedReward,
                                unlockTime: block.timestamp.add(rewardsVestingDuration.sub(secondsPassed)),
                                recordTime: block.timestamp
                            })
                        );
                    }
                }
                // Calculates reward amount for each week that has passed after the first week of stake
                // following the same logic as used in a first week.
                uint256 l;
                if (userStake[msg.sender][i].lastWeekCalculated == 0) {
                    l = week.add(1);
                } else {
                    l = userStake[msg.sender][i].lastWeekCalculated;
                }
                for (l; l < _weekNumber; l++) {
                    if (l != _weekNumber) {
                        uint256 weeklyReward = weekInfo[l].rewardRate.mul(userStake[msg.sender][i].staked).div(
                            rewardRateCoeff
                        );
                        secondsPassed = _calculateVestedTime(l).add(secondsInAWeek);
                        if (secondsPassed > rewardsVestingDuration) {
                            totalVestedReward = totalVestedReward.add(weeklyReward);
                        } else {
                            uint256 vestedReward = _calcVestedStake(l, i, secondsPassed, secondsInAWeek);
                            totalVestedReward = totalVestedReward.add(vestedReward);
                            uint256 unvestedReward = _calcUnvestedStake(l, i, vestedReward, secondsInAWeek);
                            //  Updates user's unclaimed rewards
                            rewardUnclaimed[msg.sender].push(
                                CalcUnvestedReward({
                                    amount: unvestedReward,
                                    unlockTime: block.timestamp.add(rewardsVestingDuration.sub(secondsPassed)),
                                    recordTime: block.timestamp
                                })
                            );
                        }
                    }
                }
                // Updates the time that user's rewards for that stake were calculated
                userStake[msg.sender][i].lastWeekCalculated = _weekNumber;
            }
        }
    }

    function _viewVestedDirtyReward(uint256 _weekNumber) internal view returns (uint256 totalVestedReward) {
        for (uint256 i = 0; i < userStake[msg.sender].length; i++) {
            if (userStake[msg.sender][i].weekNumber != _weekNumber) {
                uint256 week = userStake[msg.sender][i].weekNumber;
                uint256 secondsPassed;
                // Checks if user had claimed rewards before, so that calculations for the same weeks
                // wouldn't get recalculated again
                if (userStake[msg.sender][i].lastWeekCalculated > 0) {
                    totalVestedReward = totalVestedReward.add(_calcStakesAgain(i, _weekNumber));
                } else {
                    secondsPassed = _calculateVestedTime(week).add(userStake[msg.sender][i].secondsTillWeekEnd);

                    // Checks if vesting period for that week has passed
                    if (secondsPassed > rewardsVestingDuration) {
                        // If true: adds whole reward amount into the total reward amount
                        uint256 vestedReward = weekInfo[week]
                            .rewardRate
                            .mul(userStake[msg.sender][i].secondsTillWeekEnd)
                            .mul(userStake[msg.sender][i].staked);
                        vestedReward = vestedReward.div(rewardRateCoeff).div(secondsInAWeek);

                        totalVestedReward = totalVestedReward.add(vestedReward);
                    } else {
                        // Otherwise: calculates what amount has been vested yet and what hasnt'
                        uint256 vestedReward = _calcVestedStake(
                            week,
                            i,
                            secondsPassed,
                            userStake[msg.sender][i].secondsTillWeekEnd
                        );
                        totalVestedReward = totalVestedReward.add(vestedReward);
                    }
                }
                // Calculates reward amount for each week that has passed after the first week of stake
                // following the same logic as used in a first week.
                uint256 l;
                if (userStake[msg.sender][i].lastWeekCalculated == 0) {
                    l = week.add(1);
                } else {
                    l = userStake[msg.sender][i].lastWeekCalculated;
                }
                for (l; l < _weekNumber; l++) {
                    if (l != _weekNumber) {
                        uint256 weeklyReward = weekInfo[l].rewardRate.mul(userStake[msg.sender][i].staked).div(
                            rewardRateCoeff
                        );
                        secondsPassed = _calculateVestedTime(l).add(secondsInAWeek);
                        if (secondsPassed > rewardsVestingDuration) {
                            totalVestedReward = totalVestedReward.add(weeklyReward);
                        } else {
                            uint256 vestedReward = _calcVestedStake(l, i, secondsPassed, secondsInAWeek);
                            totalVestedReward = totalVestedReward.add(vestedReward);
                        }
                    }
                }
            }
        }
    }

    /** 
    This method calculates 
    */
    function _getVestedReward() internal returns (uint256 reward) {
        for (uint256 i = 0; i < rewardUnclaimed[msg.sender].length; i++) {
            if (rewardUnclaimed[msg.sender][i].unlockTime <= block.timestamp) {
                reward = reward.add(rewardUnclaimed[msg.sender][i].amount);
            } else {
                uint256 currentReward = rewardUnclaimed[msg.sender][i]
                    .amount
                    .mul(block.timestamp.sub(rewardUnclaimed[msg.sender][i].recordTime))
                    .div(rewardUnclaimed[msg.sender][i].unlockTime.sub(rewardUnclaimed[msg.sender][i].recordTime));
                rewardUnclaimed[msg.sender][i].amount = rewardUnclaimed[msg.sender][i].amount.sub(currentReward);
                rewardUnclaimed[msg.sender][i].recordTime = block.timestamp;
                reward = reward.add(currentReward);
            }
        }
    }

    function _viewVestedReward() internal view returns (uint256 reward) {
        for (uint256 i = 0; i < rewardUnclaimed[msg.sender].length; i++) {
            if (rewardUnclaimed[msg.sender][i].unlockTime <= block.timestamp) {
                reward = reward.add(rewardUnclaimed[msg.sender][i].amount);
            } else {
                reward = reward.add(
                    rewardUnclaimed[msg.sender][i]
                        .amount
                        .mul(block.timestamp.sub(rewardUnclaimed[msg.sender][i].recordTime))
                        .div(rewardUnclaimed[msg.sender][i].unlockTime.sub(rewardUnclaimed[msg.sender][i].recordTime))
                );
            }
        }
    }

    function _getFalseVestedReward() internal returns (uint256 reward) {
        for (uint256 i = 0; i < falseRewardUnclaimed[msg.sender].length; i++) {
            if (falseRewardUnclaimed[msg.sender][i].unlockTime <= block.timestamp) {
                reward = reward.add(falseRewardUnclaimed[msg.sender][i].amount);
            } else {
                reward = reward.add(
                    falseRewardUnclaimed[msg.sender][i]
                        .amount
                        .mul(block.timestamp.sub(falseRewardUnclaimed[msg.sender][i].recordTime))
                        .div(
                            falseRewardUnclaimed[msg.sender][i].unlockTime.sub(
                                falseRewardUnclaimed[msg.sender][i].recordTime
                            )
                        )
                );
                falseRewardUnclaimed[msg.sender][i].amount = falseRewardUnclaimed[msg.sender][i].amount.sub(reward);
                falseRewardUnclaimed[msg.sender][i].recordTime = block.timestamp;
            }
        }
    }

    function _viewFalseVestedReward() internal view returns (uint256 reward) {
        for (uint256 i = 0; i < falseRewardUnclaimed[msg.sender].length; i++) {
            if (falseRewardUnclaimed[msg.sender][i].unlockTime <= block.timestamp) {
                reward = reward.add(falseRewardUnclaimed[msg.sender][i].amount);
            } else {
                reward = reward.add(
                    falseRewardUnclaimed[msg.sender][i].amount.mul(
                        block.timestamp.sub(falseRewardUnclaimed[msg.sender][i].recordTime).div(
                            falseRewardUnclaimed[msg.sender][i].unlockTime.sub(
                                falseRewardUnclaimed[msg.sender][i].recordTime
                            )
                        )
                    )
                );
            }
        }
    }

    // UTILS

    function _calculateVestedTime(uint256 _weekNumber) internal view returns (uint256) {
        return block.timestamp.sub(weekInfo[_weekNumber].endTime);
    }

    function _secondsBeforeWeekEnd(uint256 _week) internal view returns (uint256) {
        return (weekInfo[_week].endTime.sub(block.timestamp));
    }
}
