// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/utils/SafeCast.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import "./interface/INewPremiaFeeDiscount.sol";

contract PremiaFeeDiscount is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    struct UserInfo {
        uint256 balance;      // Balance staked by user
        uint64 stakePeriod;   // Stake period selected by user
        uint64 lockedUntil;   // Timestamp at which the lock ends
    }

    struct StakeLevel {
        uint256 amount;       // Amount to stake
        uint256 discount;     // Discount when amount is reached
    }

    IERC20 public xPremia;

    uint256 public constant INVERSE_BASIS_POINT = 1e4;

    // User data with balance staked and date at which lock ends
    mapping (address => UserInfo) public userInfo;
    // Available lockup periods with their bonus (seconds lockup => multiplier (x1 = 1e4))
    mapping (uint256 => uint256) public stakePeriods;

    // List of all existing stake periods
    uint256[] public existingStakePeriods;

    // In case we want to upgrade this contract
    // Users will have to migrate their stake manually by calling migrateStake() so that there is no risk of funds being drained
    INewPremiaFeeDiscount public newContract;

    // Staking levels
    StakeLevel[] public stakeLevels;

    ////////////
    // Events //
    ////////////

    event Staked(address indexed user, uint256 amount, uint256 stakePeriod, uint256 lockedUntil);
    event Unstaked(address indexed user, uint256 amount);
    event StakeMigrated(address indexed user, address newContract, uint256 amount, uint256 stakePeriod, uint256 lockedUntil);

    ///////////

    constructor(IERC20 _xPremia) public {
        xPremia = _xPremia;
    }

    ///////////
    // Admin //
    ///////////

    // Set a new PremiaFeeDiscount contract, to enable migration
    function setNewContract(INewPremiaFeeDiscount _newContract) external onlyOwner {
        newContract = _newContract;
    }

    // Set a stake period multiplier
    function setStakePeriod(uint256 _secondsLocked, uint256 _multiplier) external onlyOwner {
        if (_isInArray(_secondsLocked, existingStakePeriods)) {
            existingStakePeriods.push(_secondsLocked);
        }

        stakePeriods[_secondsLocked] = _multiplier;
    }

    // Set new amounts and discounts values for stake levels
    function setStakeLevels(StakeLevel[] memory _stakeLevels) external onlyOwner {
        for (uint256 i=0; i < _stakeLevels.length; i++) {
            if (i > 0) {
                require(_stakeLevels[i].amount > _stakeLevels[i-1].amount && _stakeLevels[i].discount < _stakeLevels[i-1].discount, "Wrong stake level");
            }
        }

        delete stakeLevels;

        for (uint256 i=0; i < _stakeLevels.length; i++) {
            stakeLevels.push(_stakeLevels[i]);
        }
    }

    ///////////

    // Allow a user to migrate their stake to a new PremiaFeeDiscount contract, while preserving same lockup expiration date
    function migrateStake() external nonReentrant {
        require(address(newContract) != address(0), "Migration disabled");

        UserInfo memory user = userInfo[msg.sender];

        delete userInfo[msg.sender];

        newContract.migrate(msg.sender, user.balance, user.stakePeriod, user.lockedUntil);
        emit StakeMigrated(msg.sender, address(newContract), user.balance, user.stakePeriod, user.lockedUntil);
    }


    // Stake specified amount. The amount will be locked for the given period.
    // Longer period of locking will apply a multiplier on the amount staked, in the fee discount calculation
    function stake(uint256 _amount, uint256 _period) external nonReentrant {
        require(stakePeriods[_period] > 0, "Stake period does not exists");
        UserInfo storage user = userInfo[msg.sender];

        uint256 lockedUntil = block.timestamp.add(_period);
        require(lockedUntil > user.lockedUntil, "Cannot add stake with lower stake period");

        xPremia.transferFrom(msg.sender, address(this), _amount);
        user.balance = user.balance.add(_amount);
        user.lockedUntil = lockedUntil.toUint64();

        emit Staked(msg.sender, _amount, _period, lockedUntil);
    }

    // Unstake specified amount
    function unstake(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        // We allow unstake if the stakePeriod that the user used has been disabled
        require(stakePeriods[user.stakePeriod] == 0 || user.lockedUntil <= block.timestamp, "Stake still locked");

        user.balance = user.balance.sub(_amount);
        xPremia.transfer(msg.sender, _amount);

        emit Unstaked(msg.sender, _amount);
    }

    // Return number of stake levels
    function stakeLevelsLength() external view returns(uint256) {
        return stakeLevels.length;
    }

    // Return the % of the fee that user must pay, based on his stake
    function getDiscount(address _user) external view returns(uint256) {
        UserInfo memory user = userInfo[msg.sender];
        uint256 userBalance = user.balance.mul(stakePeriods[user.stakePeriod]).div(INVERSE_BASIS_POINT);

        for (uint256 i=0; i < stakeLevels.length; i++) {
            StakeLevel memory level = stakeLevels[i];

            if (userBalance < level.amount) {
                uint256 amountPrevLevel;
                uint256 discountPrevLevel;

                // If stake is lower, user is in this level, and we need to LERP with prev level to get discount value
                // If this is the first level, prev level is 0 / 0
                if (i > 0) {
                    amountPrevLevel = stakeLevels[i - 1].amount;
                    discountPrevLevel = stakeLevels[i - 1].discount;
                }

                uint256 remappedDiscount = level.discount.sub(discountPrevLevel);
                uint256 remappedBalance = userBalance.sub(amountPrevLevel);

                return discountPrevLevel.add(remappedBalance.mul(level.discount.sub(discountPrevLevel)).div(remappedDiscount));
            }
        }

        // If no match found it means user is >= max possible stake, and therefore has max discount possible
        return stakeLevels[stakeLevels.length - 1].discount;
    }

    //////////////
    // Internal //
    //////////////

    // Utility function to check if a value is inside an array
    function _isInArray(uint256 _value, uint256[] memory _array) internal pure returns(bool) {
        uint256 length = _array.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_array[i] == _value) {
                return true;
            }
        }

        return false;
    }
}
