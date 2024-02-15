// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

// TO DO:
// Change user vestings[] to have indexes based on each time a reward object added to array
// instead of like it is now that there is a single object returned by week number

/** 
        @title Linear vesting for Halter trading volume rewards
        @author Gosha Skryuchenkov @ Prometeus Labs

        This contract is used to vest rewards. 
        Rewards amount is calculated for every user by a centralized service
        created by Prometeus Labs for Halter project.

        Same service adds information of rewards for each user into smart contract.
    */

contract TradeRewardsVesting is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20 for IERC20;

    IERC20 public rewardToken; // address of reward token
    address public owner; // address of contract owner
    address public reservoir; // address of reservoir contract, where rewards are stored

    struct Vesting {
        uint256 rewardRate; // Numerator of tokens in wei, that users accumulated per second
        address paymentAddress; // user's address
        uint256 lastPayment; // timestamp of last user's claim
        uint256 totalAmountOfSeconds; // Amount of seconds that need to pass for 100% to get accumulated
        uint256 penalty;
        uint256 pid;
    }

    struct Event {
        uint256 startTime; // timestamp of trading event start
        uint256 endTime; // timestamp of vesting end
    }
    uint256 public constant COEFF = 1e18;

    Event[] public events; // array of events

    mapping(address => Vesting[]) public vestings;
    //user address -> index in events array
    mapping(address => mapping(uint256 => uint256)) public userClaimed;

    /* ======================== Events ======================== */

    event TokensClaimed(address paymentAddress, uint256 amountClaimed);
    event TokensClaimedWithPenalty(address paymentAddress, uint256 penaltyAmount, uint256 totalReward);
    event EventAdded(uint256 pid, uint256 startTime, uint256 endTime);

    /* ======================== Modifiers ======================== */
    modifier nonZeroAddress(address x) {
        require(x != address(0), "token-zero-address");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "unauthorized");
        _;
    }

    bytes32 public constant TREASURY_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPDATER_ROLE = keccak256("BURNER_ROLE");

    /* ======================== CONSTRUCTOR ======================== */

    /** 
        @param _rewardToken The address of reward token
        @param _reservoir The address of reservoir contract, that stores rewards
        */
    function initialize(
        address _rewardToken,
        address _reservoir,
        address _treasury,
        address _updater
    ) external initializer nonZeroAddress(_rewardToken) {
        __AccessControl_init();
        _setupRole(TREASURY_ROLE, _treasury);
        _setupRole(UPDATER_ROLE, _updater);
        owner = msg.sender;
        rewardToken = IERC20(_rewardToken);
        reservoir = _reservoir;
    }

    /* ======================== OWNER FUNCTIONS ======================== */

    /**
        @param _startTime timestamp of Halter trading week start
        @param _endTime timestamp of vesting for same rewards

        This method adds "event". 
        Start of the event is considered to be a start of trading week.
        End time of the event is a summ of startTime and vesting period.
        */
    function addEvent(uint256 _startTime, uint256 _endTime) external onlyRole(TREASURY_ROLE) {
        uint256 pid = events.length;
        events.push(Event({ startTime: _startTime, endTime: _endTime }));

        emit EventAdded(pid, _startTime, _endTime);
    }

    /**
        @param _rewardRate amount of tokens user is going to be accumulating per second
        @param _paymentAddress user's address
        @param _pid index of event, that vesting is added for
        @param _totalAmountOfSeconds Amount of seconds that need to pass for 100% to get accumulated

        This events adds information about each user into the contract,
        so that users in future could claim their rewards
        */
    function addVesting(
        uint256 _rewardRate,
        address _paymentAddress,
        uint256 _pid,
        uint256 _totalAmountOfSeconds
    ) public onlyRole(UPDATER_ROLE) nonZeroAddress(_paymentAddress) {
        vestings[_paymentAddress].push(
            Vesting({
                rewardRate: _rewardRate,
                paymentAddress: _paymentAddress,
                lastPayment: 0,
                totalAmountOfSeconds: _totalAmountOfSeconds,
                penalty: 0,
                pid: _pid
            })
        );
    }

    /* ======================== MUTATIVE FUNCTIONS ======================== */
    /**
        This method calculates the amount that was vested already, by the time
        block with the transaction is mined.
        Rewards are transfered from reservoir.

        TO DO: iterate through all pids and claim all rewards + clean arrays
        */
    function claimReward() public nonReentrant {
        uint256 totalAmount;
        for (uint256 i = 0; i < vestings[msg.sender].length; i++) {
            uint256 count = (SafeMathUpgradeable.sub(block.timestamp, vestings[msg.sender][i].lastPayment));
            if (vestings[msg.sender][i].penalty == 0 && count != 0) {
                uint256 amount = calculateClaim(i);

                if (vestings[msg.sender][i].totalAmountOfSeconds < count) {
                    count = vestings[msg.sender][i].totalAmountOfSeconds;
                }

                vestings[msg.sender][i].totalAmountOfSeconds = SafeMathUpgradeable.sub(
                    vestings[msg.sender][i].totalAmountOfSeconds,
                    count
                );
                vestings[msg.sender][i].lastPayment = block.timestamp;

                userClaimed[msg.sender][i] = userClaimed[msg.sender][i].add(amount);
                totalAmount = totalAmount.add(amount);
            }
        }
        require(totalAmount != 0, "Claimed zero tokens");
        rewardToken.safeTransferFrom(address(reservoir), address(msg.sender), totalAmount);

        emit TokensClaimed(msg.sender, totalAmount);
    }

    /**
        This method allows user to claim rewards without waiting for vesting period to end.
        However, users get a 50% penalty for rewards, that are weren't accumulated according
        to vesting schedule yet.

        First accumulated rewards without penalty are getting transferd by calling claimReward(_pid) method
        Next rewards that are left getting calculated and transfered.
    */
    function emergencyClaim() public nonReentrant {
        uint256 totalReward = calculateAllClaims();
        uint256 rewardWithPenalty;
        for (uint256 i = 0; i < vestings[msg.sender].length; i++) {
            uint256 userTotalReward = vestings[msg.sender][i]
                .rewardRate
                .mul((events[vestings[msg.sender][i].pid].endTime.sub(events[vestings[msg.sender][i].pid].startTime)))
                .div(COEFF);
            rewardWithPenalty = rewardWithPenalty.add((userTotalReward.sub(userClaimed[msg.sender][i])).div(2));
            vestings[msg.sender][i].penalty = rewardWithPenalty;

            totalReward = totalReward.add(rewardWithPenalty);
        }

        rewardToken.safeTransferFrom(reservoir, msg.sender, totalReward);

        emit TokensClaimedWithPenalty(msg.sender, rewardWithPenalty, totalReward);
    }

    /* ======================== VIEWS ======================== */

    /**
        @param _index index of the event

        Returns final amount of rewards, that user can ever get.
        This amount is equal to amount that user will get after total vesting period is off, and 0 tokens are
        claimed before that point.

        TO DO: iterate through all _pids    
    */
    function getTotalPoolReward(uint256 _index) public view returns (uint256 reward) {
        if (vestings[msg.sender].length > 0) {
            reward = vestings[msg.sender][_index]
                .rewardRate
                .mul(
                    (
                        events[vestings[msg.sender][_index].pid].endTime.sub(
                            events[vestings[msg.sender][_index].pid].startTime
                        )
                    )
                )
                .div(COEFF);
        } else {
            revert("User hasn't staked anything");
        }
    }

    function getTotalRewards() public view returns (uint256 rewards) {
        if (vestings[msg.sender].length > 0) {
            for (uint256 i = 0; i < vestings[msg.sender].length; i++) {
                rewards = rewards
                    .add(
                        vestings[msg.sender][i].rewardRate.mul(
                            (
                                events[vestings[msg.sender][i].pid].endTime.sub(
                                    events[vestings[msg.sender][i].pid].startTime
                                )
                            )
                        )
                    )
                    .div(COEFF);
            }
        } else {
            revert("User hasn't staked anything");
        }
    }

    /**
        @param _index index of the event
        Returns the amount of tokens user can get by calling the emergency claim method
        */
    function getEmergencyClaimPoolReward(uint256 _index) public view returns (uint256) {
        uint256 rewardWithoutPenalty = calculateClaim(_index);
        return ((getTotalPoolReward(_index).sub(rewardWithoutPenalty)).div(2).add(rewardWithoutPenalty));
    }

    function getEmergencyClaimRewards() public view returns (uint256 rewards) {
        for (uint256 i = 0; i < vestings[msg.sender].length; i++) {
            uint256 rewardWithoutPenalty = calculateClaim(i);
            rewards = rewards.add((getTotalPoolReward(i).sub(rewardWithoutPenalty)).div(2).add(rewardWithoutPenalty));
        }
    }

    /**
        Returns the amount of accumulated rewards
    */
    function calculateAllClaims() public view returns (uint256 finalAmount) {
        for (uint256 i = 0; i < vestings[msg.sender].length; i++) {
            uint256 count = block.timestamp.sub(vestings[msg.sender][i].lastPayment);
            if (vestings[msg.sender][i].penalty == 0 && count != 0) {
                if (vestings[msg.sender][i].totalAmountOfSeconds < count) {
                    count = vestings[msg.sender][i].totalAmountOfSeconds;
                }
                finalAmount = finalAmount.add(count.mul(vestings[msg.sender][i].rewardRate).div(COEFF));
            }
        }
    }

    function calculateClaim(uint256 _index) public view returns (uint256 finalAmount) {
        if (vestings[msg.sender][_index].penalty == 0) {
            uint256 count = block.timestamp.sub(vestings[msg.sender][_index].lastPayment);
            if (count != 0) {
                if (vestings[msg.sender][_index].totalAmountOfSeconds < count) {
                    count = vestings[msg.sender][_index].totalAmountOfSeconds;
                }
                finalAmount = count.mul(vestings[msg.sender][_index].rewardRate).div(COEFF);
            }
        }
    }
}
