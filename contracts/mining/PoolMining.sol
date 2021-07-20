// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OwnableInternal, OwnableStorage} from "@solidstate/contracts/access/OwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {PoolMiningStorage} from "./PoolMiningStorage.sol";
import {IPoolMining} from "./IPoolMining.sol";
import {IPoolView} from "../pool/IPoolView.sol";

/**
 * @title Premia liquidity mining contract, derived from Sushiswap's MasterChev.sol ( https://github.com/sushiswap/sushiswap )
 */
contract PoolMining is IPoolMining, OwnableInternal {
    using PoolMiningStorage for PoolMiningStorage.Layout;
    using SafeERC20 for IERC20;

    address internal immutable DIAMOND;
    address internal immutable PREMIA;

    event Claim(
        address indexed user,
        address indexed pool,
        bool indexed isCallPool,
        uint256 rewardAmount
    );
    event UpdatePoolAlloc(address indexed pool, uint256 allocPoints);

    constructor(address _diamond, address _premia) {
        DIAMOND = _diamond;
        PREMIA = _premia;
    }

    modifier onlyPool(address _pool) {
        require(msg.sender == _pool, "Not pool");
        _;
    }

    modifier onlyDiamondOrOwner() {
        require(
            msg.sender == DIAMOND ||
                msg.sender == OwnableStorage.layout().owner,
            "Not diamond or owner"
        );
        _;
    }

    /**
     * @notice Add premia rewards to distribute. Can only be called by the owner
     * @param _amount Amount of premia to add
     */
    function addPremiaRewards(uint256 _amount) external override onlyOwner {
        PoolMiningStorage.Layout storage l = PoolMiningStorage.layout();
        IERC20(PREMIA).safeTransferFrom(msg.sender, address(this), _amount);
        l.premiaAvailable += _amount;
    }

    /**
     * @notice Get amount of premia reward available to distribute
     * @return Amount of premia reward available to distribute
     */
    function premiaRewardsAvailable() external view returns (uint256) {
        return PoolMiningStorage.layout().premiaAvailable;
    }

    /**
     * @notice Set new alloc points for an option pool. Can only be called by the owner.
     * @param _premiaPerBlock Amount of PREMIA per block to allocate as reward accross all pools
     */
    function setPremiaPerBlock(uint256 _premiaPerBlock) external onlyOwner {
        PoolMiningStorage.layout().premiaPerBlock = _premiaPerBlock;
    }

    /**
     * @notice Add a new option pool to the liquidity mining. Can only be called by the owner or premia diamond
     * @param _pool Address of option pool contract
     * @param _allocPoint Weight of this pool in the reward calculation
     */
    function add(address _pool, uint256 _allocPoint)
        external
        override
        onlyDiamondOrOwner
    {
        PoolMiningStorage.Layout storage l = PoolMiningStorage.layout();
        require(
            l.poolInfo[_pool][true].lastRewardBlock == 0 &&
                l.poolInfo[_pool][false].lastRewardBlock == 0,
            "Pool exists"
        );

        l.totalAllocPoint += (_allocPoint * 2);

        l.poolInfo[_pool][true] = PoolMiningStorage.PoolInfo({
            allocPoint: _allocPoint,
            lastRewardBlock: block.number,
            accPremiaPerShare: 0
        });

        l.poolInfo[_pool][false] = PoolMiningStorage.PoolInfo({
            allocPoint: _allocPoint,
            lastRewardBlock: block.number,
            accPremiaPerShare: 0
        });

        l.optionPoolList.push(_pool);

        emit UpdatePoolAlloc(_pool, _allocPoint);
    }

    /**
     * @notice Set new alloc points for an option pool. Can only be called by the owner or premia diamond
     * @param _pool Address of option pool contract
     * @param _allocPoint Weight of this pool in the reward calculation
     */
    function set(address _pool, uint256 _allocPoint)
        external
        override
        onlyDiamondOrOwner
    {
        PoolMiningStorage.Layout storage l = PoolMiningStorage.layout();

        require(
            l.poolInfo[_pool][true].lastRewardBlock > 0 &&
                l.poolInfo[_pool][false].lastRewardBlock > 0,
            "Pool does not exists"
        );

        l.totalAllocPoint =
            l.totalAllocPoint -
            l.poolInfo[_pool][true].allocPoint -
            l.poolInfo[_pool][false].allocPoint +
            (_allocPoint * 2);

        l.poolInfo[_pool][true].allocPoint = _allocPoint;
        l.poolInfo[_pool][false].allocPoint = _allocPoint;

        emit UpdatePoolAlloc(_pool, _allocPoint);
    }

    /**
     * @notice Get pending premia reward for a user on a pool
     * @param _pool Address of option pool contract
     * @param _isCallPool True if for call option pool, False if for put option pool
     */
    function pendingPremia(
        address _pool,
        bool _isCallPool,
        address _user
    ) external view override returns (uint256) {
        uint256 TVL;
        uint256 userTVL;

        {
            (uint256 underlyingTVL, uint256 baseTVL) = IPoolView(_pool)
                .getTotalTVL();
            TVL = _isCallPool ? underlyingTVL : baseTVL;
        }

        {
            (uint256 userUnderlyingTVL, uint256 userBaseTVL) = IPoolView(_pool)
                .getUserTVL(_user);
            userTVL = _isCallPool ? userUnderlyingTVL : userBaseTVL;
        }

        PoolMiningStorage.Layout storage l = PoolMiningStorage.layout();
        PoolMiningStorage.PoolInfo storage pool = l.poolInfo[_pool][
            _isCallPool
        ];
        PoolMiningStorage.UserInfo storage user = l.userInfo[_pool][
            _isCallPool
        ][_user];
        uint256 accPremiaPerShare = pool.accPremiaPerShare;

        if (block.number > pool.lastRewardBlock && TVL != 0) {
            uint256 premiaReward = ((block.number - pool.lastRewardBlock) *
                l.premiaPerBlock *
                pool.allocPoint) / l.totalAllocPoint;

            // If we are running out of rewards to distribute, distribute whats left
            if (premiaReward > l.premiaAvailable) {
                premiaReward = l.premiaAvailable;
            }

            accPremiaPerShare += (premiaReward * 1e12) / TVL;
        }
        return
            ((userTVL * accPremiaPerShare) / 1e12) -
            user.rewardDebt +
            user.reward;
    }

    /**
     * @notice Update reward variables of the given pool to be up-to-date. Only callable by the option pool
     * @param _pool Address of option pool contract
     * @param _isCallPool True if for call option pool, False if for put option pool
     * @param _totalTVL Total amount of tokens deposited in the option pool
     */
    function updatePool(
        address _pool,
        bool _isCallPool,
        uint256 _totalTVL
    ) external override onlyPool(_pool) {
        _updatePool(_pool, _isCallPool, _totalTVL);
    }

    /**
     * @notice Update reward variables of the given pool to be up-to-date. Only callable by the option pool
     * @param _pool Address of option pool contract
     * @param _isCallPool True if for call option pool, False if for put option pool
     * @param _totalTVL Total amount of tokens deposited in the option pool
     */
    function _updatePool(
        address _pool,
        bool _isCallPool,
        uint256 _totalTVL
    ) internal {
        PoolMiningStorage.Layout storage l = PoolMiningStorage.layout();

        PoolMiningStorage.PoolInfo storage pool = l.poolInfo[_pool][
            _isCallPool
        ];

        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (_totalTVL == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 premiaReward = ((block.number - pool.lastRewardBlock) *
            l.premiaPerBlock *
            pool.allocPoint) / l.totalAllocPoint;

        // If we are running out of rewards to distribute, distribute whats left
        if (premiaReward > l.premiaAvailable) {
            premiaReward = l.premiaAvailable;
        }

        l.premiaAvailable -= premiaReward;
        pool.accPremiaPerShare += (premiaReward * 1e12) / _totalTVL;
        pool.lastRewardBlock = block.number;
    }

    /**
     * @notice Allocate pending rewards to a user. Only callable by the option pool
     * @param _user User for whom allocate the rewards
     * @param _pool Address of option pool contract
     * @param _isCallPool True if for call option pool, False if for put option pool
     * @param _userTVLOld Total amount of tokens deposited in the option pool by user before the allocation update
     * @param _userTVLNew Total amount of tokens deposited in the option pool by user after the allocation update
     * @param _totalTVL Total amount of tokens deposited in the option pool
     */
    function allocatePending(
        address _user,
        address _pool,
        bool _isCallPool,
        uint256 _userTVLOld,
        uint256 _userTVLNew,
        uint256 _totalTVL
    ) external override onlyPool(_pool) {
        _allocatePending(
            _user,
            _pool,
            _isCallPool,
            _userTVLOld,
            _userTVLNew,
            _totalTVL
        );
    }

    /**
     * @notice Allocate pending rewards to a user. Only callable by the option pool
     * @param _user User for whom allocate the rewards
     * @param _pool Address of option pool contract
     * @param _isCallPool True if for call option pool, False if for put option pool
     * @param _userTVLOld Total amount of tokens deposited in the option pool by user before the allocation update
     * @param _userTVLNew Total amount of tokens deposited in the option pool by user after the allocation update
     * @param _totalTVL Total amount of tokens deposited in the option pool
     */
    function _allocatePending(
        address _user,
        address _pool,
        bool _isCallPool,
        uint256 _userTVLOld,
        uint256 _userTVLNew,
        uint256 _totalTVL
    ) internal {
        PoolMiningStorage.Layout storage l = PoolMiningStorage.layout();
        PoolMiningStorage.PoolInfo storage pool = l.poolInfo[_pool][
            _isCallPool
        ];
        PoolMiningStorage.UserInfo storage user = l.userInfo[_pool][
            _isCallPool
        ][_user];

        _updatePool(_pool, _isCallPool, _totalTVL);

        user.reward +=
            ((_userTVLOld * pool.accPremiaPerShare) / 1e12) -
            user.rewardDebt;

        user.rewardDebt = (_userTVLNew * pool.accPremiaPerShare) / 1e12;
    }

    /**
     * @notice Update user reward allocation + claim allocated PREMIA reward. Only callable by the option pool
     * @param _user User claiming the rewards
     * @param _pool Address of option pool contract
     * @param _isCallPool True if for call option pool, False if for put option pool
     * @param _userTVLOld Total amount of tokens deposited in the option pool by user before the allocation update
     * @param _userTVLNew Total amount of tokens deposited in the option pool by user after the allocation update
     * @param _totalTVL Total amount of tokens deposited in the option pool
     */
    function claim(
        address _user,
        address _pool,
        bool _isCallPool,
        uint256 _userTVLOld,
        uint256 _userTVLNew,
        uint256 _totalTVL
    ) external override onlyPool(_pool) {
        PoolMiningStorage.Layout storage l = PoolMiningStorage.layout();

        _allocatePending(
            _user,
            _pool,
            _isCallPool,
            _userTVLOld,
            _userTVLNew,
            _totalTVL
        );

        uint256 reward = l.userInfo[_pool][_isCallPool][_user].reward;
        l.userInfo[_pool][_isCallPool][_user].reward = 0;
        IERC20(PREMIA).safeTransfer(_user, reward);

        emit Claim(_user, _pool, _isCallPool, reward);
    }

    /**
     * @notice Safe premia transfer function, just in case if rounding error causes pool to not have enough PREMIA.
     * @param _to Address where to transfer the Premia
     * @param _amount Amount of tokens to transfer
     */
    function _safePremiaTransfer(address _to, uint256 _amount) internal {
        IERC20 premia = IERC20(PREMIA);

        uint256 premiaBal = premia.balanceOf(address(this));
        if (_amount > premiaBal) {
            premia.transfer(_to, premiaBal);
        } else {
            premia.transfer(_to, _amount);
        }
    }
}
