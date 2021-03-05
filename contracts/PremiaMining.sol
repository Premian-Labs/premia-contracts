// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interface/IERC2612Permit.sol";


/// @author Premia (Forked from SushiSwap's MasterChef contract)
/// @title Allow staking of uPremia non tradable token (rewarded on protocol fees payment), to mine Premia allocated to "Interaction mining"
contract PremiaMining is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of PREMIAs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accPremiaPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accPremiaPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. PREMIAs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that PREMIAs distribution occurs.
        uint256 accPremiaPerShare; // Accumulated PREMIAs per share, times 1e12. See below.
    }

    // The PREMIA TOKEN!
    IERC20 public premia;
    // Block number when all PREMIA mining will end
    uint256 public endBlock;
    // Block number when bonus PREMIA period ends.
    uint256 public bonusEndBlock;
    // PREMIA tokens distributed per block.
    uint256 public premiaPerBlock = 4e18;
    // Bonus multiplier for early premia makers.
    uint256 public constant BONUS_MULTIPLIER = 25000; // 2.5x

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when PREMIA mining starts.
    uint256 public startBlock;

    ////////////
    // Events //
    ////////////

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    // Accelerated period : 360e3 blocks : 10 PREMIA per bloc for 360k blocks (~7.7 weeks)
    // Regular period :     3600e3 blocks : 4 PREMIA per bloc for 3.6m blocks (~77 weeks)
    /// @param _premia The premia token
    /// @param _startBlock Block at which the mining will start
    /// @param _bonusLength Number of block the accelerated period will last
    /// @param _postBonusLength Number of block regular period will last, after end of accelerated period
    constructor(IERC20 _premia, uint256 _startBlock, uint256 _bonusLength, uint256 _postBonusLength) {
        premia = _premia;

        startBlock = _startBlock;
        bonusEndBlock = _startBlock.add(_bonusLength);
        endBlock = bonusEndBlock.add(_postBonusLength);
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    /// @notice Get the pool length
    /// @return The amount of pools
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /// @notice Add a new lp to the pool. Can only be called by the owner.
    ///         XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param _allocPoint The alloc points for this new pool
    /// @param _lpToken The token to stake in this pool
    /// @param _withUpdate Whether we want to trigger a pool update or not
    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accPremiaPerShare: 0
        }));
    }

    /// @notice Update the given pool's PREMIA allocation point. Can only be called by the owner.
    /// @param _pid The pool id
    /// @param _allocPoint The new allocPoint
    /// @param _withUpdate Whether we want to trigger a pool update or not
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    /// @notice Return reward multiplier over the given _from to _to block. (Multiplier must be divided by 1e4)
    /// @param _from Start block
    /// @param _to End block
    /// @return Reward multiplier
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_from > endBlock) {
            return 0;
        } else if (_to > endBlock) {
            _to = endBlock;
        }

        if (_to <= bonusEndBlock) {
            return _to.sub(_from).mul(BONUS_MULTIPLIER);
        } else if (_from >= bonusEndBlock) {
            return _to.sub(_from).mul(1e4);
        } else {
            return bonusEndBlock.sub(_from).mul(BONUS_MULTIPLIER).add(
                _to.sub(bonusEndBlock).mul(1e4)
            );
        }
    }

    /// @notice View function to see pending PREMIAs on frontend.
    /// @param _pid The pool id
    /// @param _user The user address
    /// @return Pending premia of users for given pool
    function pendingPremia(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPremiaPerShare = pool.accPremiaPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 premiaReward = multiplier.mul(premiaPerBlock).div(1e4).mul(pool.allocPoint).div(totalAllocPoint);
            accPremiaPerShare = accPremiaPerShare.add(premiaReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accPremiaPerShare).div(1e12).sub(user.rewardDebt);
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /// @notice Update reward variables of the given pool to be up-to-date.
    /// @param _pid The pool id
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 premiaReward = multiplier.mul(premiaPerBlock).div(1e4).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accPremiaPerShare = pool.accPremiaPerShare.add(premiaReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    /// @notice Deposit using IERC2612 permit
    /// @param _pid The pool id
    /// @param _amount The amount to deposit
    /// @param _deadline Deadline after which permit will fail
    /// @param _v V
    /// @param _r R
    /// @param _s S
    function depositWithPermit(uint256 _pid, uint256 _amount, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) external {
        // Will revert if pool token doesnt implement permit
        IERC2612Permit(address(poolInfo[_pid].lpToken)).permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s);
        deposit(_pid, _amount);
    }

    /// @notice Deposit LP tokens to PremiaMining for PREMIA allocation.
    /// @param _pid The pool id
    /// @param _amount The amount to deposit
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accPremiaPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safePremiaTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPremiaPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    /// @notice Withdraw LP tokens from PremiaMining.
    /// @param _pid The pool id
    /// @param _amount The amount to withdraw
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accPremiaPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safePremiaTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPremiaPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param _pid The pool id
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    /// @notice Safe premia transfer function, just in case if rounding error causes contract to not have enough PREMIAs.
    /// @param _to The address to which send premia
    /// @param _amount The amount to send
    function safePremiaTransfer(address _to, uint256 _amount) internal {
        uint256 premiaBal = premia.balanceOf(address(this));
        if (_amount > premiaBal) {
            premia.safeTransfer(_to, premiaBal);
        } else {
            premia.safeTransfer(_to, _amount);
        }
    }
}
