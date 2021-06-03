// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeCast.sol';

import '@solidstate/contracts/access/Ownable.sol';
import '@solidstate/contracts/utils/ReentrancyGuard.sol';
import '@solidstate/contracts/token/ERC20/IERC2612.sol';

import './interface/INewPremiaFeeDiscount.sol';

/// @author Premia
/// @title A contract allowing you to lock xPremia to get Premia protocol fee discounts
contract PremiaFeeDiscount is Ownable, ReentrancyGuard {
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

    // The xPremia token
    IERC20 public xPremia;

    uint256 private constant _inverseBasisPoint = 1e4;

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

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    /// @param _xPremia The xPremia token
    constructor(IERC20 _xPremia) {
        OwnableStorage.layout().owner = msg.sender;

        xPremia = _xPremia;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    /// @notice Set a new PremiaFeeDiscount contract, to enable migration
    ///         Users will have to call the migration function themselves to migrate their own stake
    /// @param _newContract The new contract address
    function setNewContract(INewPremiaFeeDiscount _newContract) external onlyOwner {
        newContract = _newContract;
    }

    /// @notice Set a stake period multiplier
    /// @param _secondsLocked The length (in seconds) that the stake will be locked for
    /// @param _multiplier The multiplier (In basis points) that users will get from choosing this staking period
    function setStakePeriod(uint256 _secondsLocked, uint256 _multiplier) external onlyOwner {
        if (_isInArray(_secondsLocked, existingStakePeriods)) {
            existingStakePeriods.push(_secondsLocked);
        }

        stakePeriods[_secondsLocked] = _multiplier;
    }

    /// @notice Set new amounts and discounts values for stake levels
    /// @dev Previous stake levels will be removed and replace by the new ones given
    /// @param _stakeLevels The new stake levels to set
    function setStakeLevels(StakeLevel[] memory _stakeLevels) external onlyOwner {
        for (uint256 i=0; i < _stakeLevels.length; i++) {
            if (i > 0) {
                require(_stakeLevels[i].amount > _stakeLevels[i-1].amount && _stakeLevels[i].discount > _stakeLevels[i-1].discount, "Wrong stake level");
            }
        }

        delete stakeLevels;

        for (uint256 i=0; i < _stakeLevels.length; i++) {
            stakeLevels.push(_stakeLevels[i]);
        }
    }

    //////////////////////////////////////////////////

    //////////
    // Main //
    //////////

    /// @notice Allow a user to migrate their stake to a new PremiaFeeDiscount contract (If a new contract has been set),
    ///         while preserving same lockup expiration date
    function migrateStake() external nonReentrant {
        require(address(newContract) != address(0), "Migration disabled");

        UserInfo memory user = userInfo[msg.sender];
        require(user.balance > 0, "No stake");

        delete userInfo[msg.sender];

        xPremia.safeIncreaseAllowance(address(newContract), user.balance);
        newContract.migrate(msg.sender, user.balance, user.stakePeriod, user.lockedUntil);
        emit StakeMigrated(msg.sender, address(newContract), user.balance, user.stakePeriod, user.lockedUntil);
    }

    /// @notice Stake using IERC2612 permit
    /// @param _amount The amount of xPremia to stake
    /// @param _period The lockup period (in seconds)
    /// @param _deadline Deadline after which permit will fail
    /// @param _v V
    /// @param _r R
    /// @param _s S
    function stakeWithPermit(uint256 _amount, uint256 _period, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) external {
        IERC2612(address(xPremia)).permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s);
        stake(_amount, _period);
    }

    /// @notice Lockup xPremia for protocol fee discounts
    ///         Longer period of locking will apply a multiplier on the amount staked, in the fee discount calculation
    /// @param _amount The amount of xPremia to stake
    /// @param _period The lockup period (in seconds)
    function stake(uint256 _amount, uint256 _period) public nonReentrant {
        require(stakePeriods[_period] > 0, "Stake period does not exists");
        UserInfo storage user = userInfo[msg.sender];

        uint256 lockedUntil = block.timestamp + _period;
        require(lockedUntil > user.lockedUntil, "Cannot add stake with lower stake period");

        xPremia.safeTransferFrom(msg.sender, address(this), _amount);
        user.balance = user.balance + _amount;
        user.lockedUntil = lockedUntil.toUint64();
        user.stakePeriod = _period.toUint64();

        emit Staked(msg.sender, _amount, _period, lockedUntil);
    }

    /// @notice Unstake xPremia (If lockup period has ended)
    /// @param _amount The amount of xPremia to unstake
    function unstake(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        // We allow unstake if the stakePeriod that the user used has been disabled
        require(stakePeriods[user.stakePeriod] == 0 || user.lockedUntil <= block.timestamp, "Stake still locked");

        user.balance -= _amount;
        xPremia.safeTransfer(msg.sender, _amount);

        emit Unstaked(msg.sender, _amount);
    }

    //////////////////////////////////////////////////

    //////////
    // View //
    //////////

    /// @notice Get number of stake levels
    /// @return The amount of stake levels
    function stakeLevelsLength() external view returns(uint256) {
        return stakeLevels.length;
    }

    /// Calculate the stake amount of a user, after applying the bonus from the lockup period chosen
    /// @param _user The user from which to query the stake amount
    /// @return The user stake amount after applying the bonus
    function getStakeAmountWithBonus(address _user) public view returns(uint256) {
        UserInfo memory user = userInfo[_user];
        return user.balance * stakePeriods[user.stakePeriod] / _inverseBasisPoint;
    }

    /// @notice Calculate the % of fee discount for user, based on his stake
    /// @param _user The _user for which the discount is for
    /// @return Percentage of protocol fee discount (in basis point)
    ///         Ex : 1000 = 10% fee discount
    function getDiscount(address _user) external view returns(uint256) {
        uint256 userBalance = getStakeAmountWithBonus(_user);

        for (uint256 i=0; i < stakeLevels.length; i++) {
            StakeLevel memory level = stakeLevels[i];

            if (userBalance < level.amount) {
                uint256 amountPrevLevel;
                uint256 discountPrevLevel;

                // If stake is lower, user is in this level, and we need to LERP with prev level to get discount value
                if (i > 0) {
                    amountPrevLevel = stakeLevels[i - 1].amount;
                    discountPrevLevel = stakeLevels[i - 1].discount;
                } else {
                    // If this is the first level, prev level is 0 / 0
                    amountPrevLevel = 0;
                    discountPrevLevel = 0;
                }

                uint256 remappedDiscount = level.discount - discountPrevLevel;

                uint256 remappedAmount = level.amount - amountPrevLevel;
                uint256 remappedBalance = userBalance - amountPrevLevel;
                uint256 levelProgress = remappedBalance * _inverseBasisPoint / remappedAmount;

                return discountPrevLevel + (remappedDiscount * levelProgress / _inverseBasisPoint);
            }
        }

        // If no match found it means user is >= max possible stake, and therefore has max discount possible
        return stakeLevels[stakeLevels.length - 1].discount;
    }

    //////////////////////////////////////////////////

    //////////////
    // Internal //
    //////////////

    /// @notice Utility function to check if a value is inside an array
    /// @param _value The value to look for
    /// @param _array The array to check
    /// @return Whether the value is in the array or not
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
