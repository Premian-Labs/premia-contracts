// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {OwnableInternal, OwnableStorage} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {PremiaMiningStorage} from "./PremiaMiningStorage.sol";
import {IPremiaMining} from "./IPremiaMining.sol";
import {IPoolIO} from "../pool/IPoolIO.sol";
import {IPoolView} from "../pool/IPoolView.sol";
import {IVxPremia} from "../staking/IVxPremia.sol";
import {VxPremiaStorage} from "../staking/VxPremiaStorage.sol";
import {IProxyManager} from "../core/IProxyManager.sol";

/**
 * @title Premia liquidity mining contract, derived from Sushiswap's MasterChef.sol ( https://github.com/sushiswap/sushiswap )
 */
contract PremiaMining is IPremiaMining, OwnableInternal {
    using PremiaMiningStorage for PremiaMiningStorage.Layout;
    using SafeERC20 for IERC20;

    address internal immutable PROXY_MANAGER;
    address internal immutable PREMIA;
    address internal immutable VX_PREMIA;

    uint256 private constant ONE_YEAR = 365 days;
    uint256 private constant INVERSE_BASIS_POINT = 1e4;
    uint256 private constant MIN_POINT_MULTIPLIER = 2500; // 25% -> If utilization rate is less than this value, we use this value instead

    constructor(address _proxyManager, address _premia, address _vxPremia) {
        PROXY_MANAGER = _proxyManager;
        PREMIA = _premia;
        VX_PREMIA = _vxPremia;
    }

    modifier onlyPool(address _pool) {
        _validatePool(_pool);
        _;
    }

    /**
     * @notice validate that pool is registered on the proxy manager and is the message sender
     * @param _pool pool to validate
     */
    function _validatePool(address _pool) private {
        require(msg.sender == _pool, "Not pool");

        PremiaMiningStorage.Layout storage l = PremiaMiningStorage.layout();

        if (l.pools[_pool]) return;

        address[] memory poolList = IProxyManager(PROXY_MANAGER).getPoolList();

        for (uint256 i = 0; i < poolList.length; i++) {
            l.pools[poolList[i]] = true;
        }

        require(!l.pools[_pool], "Not pool");
    }

    /**
     * @notice Add premia rewards to distribute. Can only be called by the owner
     * @param _amount Amount of premia to add
     */
    function addPremiaRewards(uint256 _amount) external onlyOwner {
        PremiaMiningStorage.Layout storage l = PremiaMiningStorage.layout();
        IERC20(PREMIA).safeTransferFrom(msg.sender, address(this), _amount);
        l.premiaAvailable += _amount;
    }

    /**
     * @notice Get amount of premia reward available to distribute
     * @return Amount of premia reward available to distribute
     */
    function premiaRewardsAvailable() external view returns (uint256) {
        return PremiaMiningStorage.layout().premiaAvailable;
    }

    /**
     * @notice Get the total allocation points
     * @return Total allocation points
     */
    function getTotalAllocationPoints() external view returns (uint256) {
        return PremiaMiningStorage.layout().totalAllocPoint;
    }

    /**
     * @notice Get pool info
     * @param pool address of the pool
     * @param isCallPool whether we want infos of the CALL pool or the PUT pool
     * @return Pool info
     */
    function getPoolInfo(
        address pool,
        bool isCallPool
    ) external view returns (PremiaMiningStorage.PoolInfo memory) {
        return PremiaMiningStorage.layout().poolInfo[pool][isCallPool];
    }

    /**
     * @notice Get the amount of premia emitted per year
     * @return Premia emitted per year
     */
    function getPremiaPerYear() external view returns (uint256) {
        return PremiaMiningStorage.layout().premiaPerYear;
    }

    /**
     * @notice Set new alloc points for an option pool. Can only be called by the owner.
     * @param _premiaPerYear Amount of PREMIA per year to allocate as reward across all pools
     */
    function setPremiaPerYear(uint256 _premiaPerYear) external onlyOwner {
        PremiaMiningStorage.layout().premiaPerYear = _premiaPerYear;
    }

    function _setPoolAllocPoints(
        PremiaMiningStorage.Layout storage l,
        IPremiaMining.PoolAllocPoints memory _data
    ) internal {
        if (_data.poolUtilizationRateBPS < MIN_POINT_MULTIPLIER) {
            _data.poolUtilizationRateBPS = MIN_POINT_MULTIPLIER;
        }

        uint256 allocPoints = (_data.votes * _data.poolUtilizationRateBPS) /
            INVERSE_BASIS_POINT;

        l.totalAllocPoint =
            l.totalAllocPoint -
            l.poolInfo[_data.pool][_data.isCallPool].allocPoint +
            allocPoints;
        l.poolInfo[_data.pool][_data.isCallPool].allocPoint = allocPoints;

        // If alloc points set for a new pool, we initialize the last reward timestamp
        if (l.poolInfo[_data.pool][_data.isCallPool].lastRewardTimestamp == 0) {
            l.poolInfo[_data.pool][_data.isCallPool].lastRewardTimestamp = block
                .timestamp;
        }

        emit UpdatePoolAlloc(
            _data.pool,
            _data.isCallPool,
            _data.votes,
            _data.poolUtilizationRateBPS
        );
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
    ) external view returns (uint256) {
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

        PremiaMiningStorage.Layout storage l = PremiaMiningStorage.layout();
        PremiaMiningStorage.PoolInfo storage pool = l.poolInfo[_pool][
            _isCallPool
        ];

        PremiaMiningStorage.UserInfo storage user = l.userInfo[_pool][
            _isCallPool
        ][_user];
        uint256 accPremiaPerShare = pool.accPremiaPerShare;

        if (
            block.timestamp > pool.lastRewardTimestamp &&
            TVL > 0 &&
            pool.allocPoint > 0
        ) {
            uint256 premiaReward = (((block.timestamp -
                pool.lastRewardTimestamp) * l.premiaPerYear) *
                pool.allocPoint) /
                l.totalAllocPoint /
                ONE_YEAR;

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
     * @param _utilizationRate Utilization rate of the pool (1e4 = 100%)
     */
    function updatePool(
        address _pool,
        bool _isCallPool,
        uint256 _totalTVL,
        uint256 _utilizationRate
    ) external onlyPool(_pool) {
        _updatePool(_pool, _isCallPool, _totalTVL, _utilizationRate);
    }

    /**
     * @notice Update reward variables of the given pool to be up-to-date. Only callable by the option pool
     * @param _pool Address of option pool contract
     * @param _isCallPool True if for call option pool, False if for put option pool
     * @param _totalTVL Total amount of tokens deposited in the option pool
     * @param _utilizationRate Utilization rate of the pool (1e4 = 100%)
     */
    function _updatePool(
        address _pool,
        bool _isCallPool,
        uint256 _totalTVL,
        uint256 _utilizationRate
    ) internal {
        PremiaMiningStorage.Layout storage l = PremiaMiningStorage.layout();

        PremiaMiningStorage.PoolInfo storage pool = l.poolInfo[_pool][
            _isCallPool
        ];

        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }

        if (_totalTVL > 0 && pool.allocPoint > 0) {
            uint256 premiaReward = (((block.timestamp -
                pool.lastRewardTimestamp) * l.premiaPerYear) *
                pool.allocPoint) /
                l.totalAllocPoint /
                ONE_YEAR;

            // If we are running out of rewards to distribute, distribute whats left
            if (premiaReward > l.premiaAvailable) {
                premiaReward = l.premiaAvailable;
            }

            l.premiaAvailable -= premiaReward;
            pool.accPremiaPerShare += (premiaReward * 1e12) / _totalTVL;
        }

        pool.lastRewardTimestamp = block.timestamp;

        _updatePoolAllocPoints(l, _pool, _isCallPool, _utilizationRate);
    }

    function _updatePoolAllocPoints(
        PremiaMiningStorage.Layout storage l,
        address pool,
        bool isCallPool,
        uint256 utilizationRate
    ) internal virtual {
        uint256 votes = IVxPremia(VX_PREMIA).getPoolVotes(
            VxPremiaStorage.VoteVersion.V2,
            abi.encodePacked(pool, isCallPool)
        );
        _setPoolAllocPoints(
            l,
            IPremiaMining.PoolAllocPoints(
                pool,
                isCallPool,
                votes,
                utilizationRate
            )
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
     * @param _utilizationRate Utilization rate of the pool (1e4 = 100%)
     */
    function allocatePending(
        address _user,
        address _pool,
        bool _isCallPool,
        uint256 _userTVLOld,
        uint256 _userTVLNew,
        uint256 _totalTVL,
        uint256 _utilizationRate
    ) external onlyPool(_pool) {
        _allocatePending(
            _user,
            _pool,
            _isCallPool,
            _userTVLOld,
            _userTVLNew,
            _totalTVL,
            _utilizationRate
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
     * @param _utilizationRate Utilization rate of the pool (1e4 = 100%)
     */
    function _allocatePending(
        address _user,
        address _pool,
        bool _isCallPool,
        uint256 _userTVLOld,
        uint256 _userTVLNew,
        uint256 _totalTVL,
        uint256 _utilizationRate
    ) internal {
        PremiaMiningStorage.Layout storage l = PremiaMiningStorage.layout();
        PremiaMiningStorage.PoolInfo storage pool = l.poolInfo[_pool][
            _isCallPool
        ];
        PremiaMiningStorage.UserInfo storage user = l.userInfo[_pool][
            _isCallPool
        ][_user];

        _updatePool(_pool, _isCallPool, _totalTVL, _utilizationRate);

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
     * @param _utilizationRate Utilization rate of the pool (1e4 = 100%)
     */
    function claim(
        address _user,
        address _pool,
        bool _isCallPool,
        uint256 _userTVLOld,
        uint256 _userTVLNew,
        uint256 _totalTVL,
        uint256 _utilizationRate
    ) external onlyPool(_pool) {
        PremiaMiningStorage.Layout storage l = PremiaMiningStorage.layout();

        _allocatePending(
            _user,
            _pool,
            _isCallPool,
            _userTVLOld,
            _userTVLNew,
            _totalTVL,
            _utilizationRate
        );

        uint256 reward = l.userInfo[_pool][_isCallPool][_user].reward;
        l.userInfo[_pool][_isCallPool][_user].reward = 0;
        _safePremiaTransfer(_user, reward);

        emit Claim(_user, _pool, _isCallPool, reward);
    }

    /**
     * @notice Trigger reward distribution by multiple pools
     * @param account address whose rewards to claim
     * @param pools list of pools to call
     * @param isCall list of bools indicating whether each pool is call pool
     */
    function multiClaim(
        address account,
        address[] calldata pools,
        bool[] calldata isCall
    ) external {
        require(pools.length == isCall.length);

        for (uint256 i; i < pools.length; i++) {
            IPoolIO(pools[i]).claimRewards(account, isCall[i]);
        }
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
            premia.safeTransfer(_to, premiaBal);
        } else {
            premia.safeTransfer(_to, _amount);
        }
    }
}
