// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import "../interface/IPremiaPoolController.sol";
import "../interface/IPoolControllerChild.sol";

contract PremiaMiningV2 is Ownable, ReentrancyGuard, IPoolControllerChild {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    IPremiaPoolController public controller;
    IERC20 public premia;

    struct PoolInfo {
        address token;
        uint256 allocPoints;
        uint256 totalScore;
        uint256 smallestExpiration;
        uint256 lastUpdate;
        uint256 accPremiaPerShare;
    }

    struct PoolExpInfo {
        uint256 expScore;
        uint256 expAccPremiaPerShare;
    }

    struct UserInfo {
        uint256 totalScore;
        uint256 rewardDebt;
    }

    // Offset to add to Unix timestamp to make it Fri 23:59:59 UTC
    uint256 public constant _baseExpiration = 172799;
    // Expiration increment
    uint256 public constant _expirationIncrement = 1 weeks;
    // Max expiration time from now
    uint256 public _maxExpiration = 365 days;

    uint256 public constant _inverseBasisPoint = 1000;

    uint256 constant premiaPerShareMult = 1e12;

    uint256 public premiaPerDay = 10000e18;

    // Total premia added to the contract as available reward
    uint256 public totalPremiaAdded;
    // Total premia allocated to users as reward
    uint256 public totalPremiaRewarded;

    //////
    //////

    uint256 totalAllocPoints;

    // Addresses allowed to set referrers
    EnumerableSet.AddressSet private _poolTokens;

    // Info of each pool.
    mapping(address => PoolInfo) public poolInfo;

    // Pool token -> User -> UserInfo
    mapping(address => mapping(address => UserInfo)) public userInfo;

    // Pool token -> User -> Expiration -> Score
    mapping(address => mapping(address => mapping(uint256 => uint256))) public userScore;

    // Pool token -> Expiration -> PoolExpInfo
    mapping(address => mapping(uint256 => PoolExpInfo)) public poolExpInfo;

    ////////////
    // Events //
    ////////////

    event PremiaAdded(uint256 amount);
    event ControllerUpdated(address indexed newController);
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Harvest(address indexed user, address indexed token, uint256 amount);
    event PoolSet(address indexed token, uint256 allocPoints);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    constructor(IPremiaPoolController _controller, IERC20 _premia) {
        controller = _controller;
        premia = _premia;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////////
    // Modifiers //
    ///////////////

    modifier onlyController() {
        require(msg.sender == address(controller), "Caller is not the controller");
        _;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    function addPool(address _token, uint256 _allocPoints, bool _withUpdate) external onlyOwner {
        require(!_poolTokens.contains(_token), "Pool already exists for token");
        if (_withUpdate) {
            massUpdatePools();
        }

        poolInfo[_token] = PoolInfo({
        token: _token,
        allocPoints: _allocPoints,
        totalScore: 0,
        smallestExpiration: 0,
        lastUpdate: block.timestamp,
        accPremiaPerShare: 0
        });

        _poolTokens.add(_token);

        totalAllocPoints += _allocPoints;
        emit PoolSet(_token, _allocPoints);
    }

    function setPool(address _token, uint256 _allocPoints, bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoints = totalAllocPoints - poolInfo[_token].allocPoints + _allocPoints;
        poolInfo[_token].allocPoints = _allocPoints;
        emit PoolSet(_token, _allocPoints);
    }

    function upgradeController(address _newController) external override {
        require(msg.sender == owner() || msg.sender == address(controller), "Not owner or controller");
        controller = IPremiaPoolController(_newController);
        emit ControllerUpdated(_newController);
    }

    function addRewards(uint256 _amount) external onlyOwner {
        premia.safeTransferFrom(msg.sender, address(this), _amount);
        totalPremiaAdded += _amount;
    }

    //////////
    // Main //
    //////////

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        for (uint256 i = 0; i < _poolTokens.length(); ++i) {
            updatePool(_poolTokens.at(i));
        }
    }

    /// @notice Get the list of pool tokens addresses
    /// @return The list of pool tokens addresses
    function getPoolTokens() external view returns(address[] memory) {
        uint256 length = _poolTokens.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _poolTokens.at(i);
        }

        return result;
    }

    function pendingReward(address _user, address _token) external view returns (uint256) {
        PoolInfo memory pInfo = poolInfo[_token];
        UserInfo memory uInfo = userInfo[_token][_user];

        uint256 expiration = (pInfo.lastUpdate / _expirationIncrement) * _expirationIncrement + _baseExpiration;
        if (expiration < pInfo.lastUpdate) {
            expiration += _expirationIncrement;
        }

        uint256 _accPremiaPerShare;
        uint256 _totalPremiaRewarded = totalPremiaRewarded;

        if (expiration >= block.timestamp) {
            if (pInfo.totalScore == 0 || uInfo.totalScore == 0) return 0;

            uint256 elapsed = block.timestamp - pInfo.lastUpdate;
            uint256 premiaAmount = _getPremiaAmountMined(_token, elapsed, _totalPremiaRewarded);
            _totalPremiaRewarded += premiaAmount;
            _accPremiaPerShare = pInfo.accPremiaPerShare + ((premiaAmount * premiaPerShareMult) / pInfo.totalScore);

            return (uInfo.totalScore * _accPremiaPerShare / premiaPerShareMult) - uInfo.rewardDebt;
        }

        _accPremiaPerShare = _getAccPremiaPerShare(_token, expiration);
        uint256 totalReward;

        totalReward += (_accPremiaPerShare * uInfo.totalScore / premiaPerShareMult) - uInfo.rewardDebt;
        uInfo.rewardDebt = _accPremiaPerShare * uInfo.totalScore / premiaPerShareMult;

        uInfo.totalScore -= userScore[_token][_user][expiration];
        pInfo.totalScore -= poolExpInfo[_token][expiration].expScore;


        while (uInfo.totalScore > 0 && (expiration + _expirationIncrement) < block.timestamp) {
            expiration += _expirationIncrement;

            _accPremiaPerShare = _getAccPremiaPerShare(_token, expiration);
            totalReward += (_accPremiaPerShare * uInfo.totalScore / premiaPerShareMult) - uInfo.rewardDebt;
            uInfo.rewardDebt = _accPremiaPerShare * uInfo.totalScore / premiaPerShareMult;

            uInfo.totalScore -= userScore[_token][_user][expiration];
            pInfo.totalScore -= poolExpInfo[_token][expiration].expScore;
        }

        if (uInfo.totalScore > 0) {
            _accPremiaPerShare = _getAccPremiaPerShare(_token, block.timestamp);
            totalReward += (_accPremiaPerShare * uInfo.totalScore / premiaPerShareMult) - uInfo.rewardDebt;
        }

        return totalReward;
    }

    function updatePool(address _token) public {
        PoolInfo storage pInfo = poolInfo[_token];

        if (pInfo.smallestExpiration != 0 && block.timestamp > pInfo.smallestExpiration) {
            while (pInfo.smallestExpiration <= block.timestamp) {
                _updateUntil(_token, pInfo.smallestExpiration);
                pInfo.totalScore -= poolExpInfo[_token][pInfo.smallestExpiration].expScore;
                poolExpInfo[_token][pInfo.smallestExpiration].expAccPremiaPerShare = pInfo.accPremiaPerShare;
                pInfo.smallestExpiration += _expirationIncrement;
            }
        }

        if (pInfo.smallestExpiration != block.timestamp) {
            _updateUntil(_token, block.timestamp);
        }
    }


    function deposit(address _user, address _token, uint256 _amount, uint256 _lockExpiration) external onlyController nonReentrant {
        updatePool(_token);

        PoolInfo storage pInfo = poolInfo[_token];
        UserInfo storage uInfo = userInfo[_token][_user];

        if (uInfo.totalScore > 0) {
            // Pool already updated so we dont need to update it again
            _harvest(_user, _token, false);
        }

        uint256 multiplier = _inverseBasisPoint + ((_lockExpiration - block.timestamp) * _inverseBasisPoint / _maxExpiration);
        uint256 score = _amount * multiplier / _inverseBasisPoint;

        userScore[_token][_user][_lockExpiration] += score;
        uInfo.totalScore += score;

        poolExpInfo[_token][_lockExpiration].expScore += score;
        pInfo.totalScore += score;

        if (pInfo.smallestExpiration == 0 || _lockExpiration < pInfo.smallestExpiration) {
            pInfo.smallestExpiration = _lockExpiration;
        }

        uInfo.rewardDebt = uInfo.totalScore * pInfo.accPremiaPerShare / premiaPerShareMult;

        emit Deposit(_user, _token, _amount);
    }

    function harvest(address[] memory _tokens) external nonReentrant {
        for (uint256 i=0; i < _tokens.length; i++) {
            _harvest(msg.sender, _tokens[i], true);
        }
    }

    //////////////
    // Internal //
    //////////////

    function _updateUntil(address _token, uint256 _timestamp) internal {
        PoolInfo storage pInfo = poolInfo[_token];

        if (_timestamp <= pInfo.lastUpdate) return;

        if (pInfo.totalScore > 0) {
            uint256 elapsed = _timestamp - pInfo.lastUpdate;
            uint256 premiaAmount = _getPremiaAmountMined(_token, elapsed, totalPremiaRewarded);

            pInfo.accPremiaPerShare += ((premiaAmount * premiaPerShareMult) / pInfo.totalScore);
            totalPremiaRewarded += premiaAmount;
        }

        pInfo.lastUpdate = _timestamp;
    }

    function _harvest(address _user, address _token, bool _updatePool) internal {
        if (_updatePool) {
            updatePool(_token);
        }

        UserInfo storage uInfo = userInfo[_token][_user];

        // Harvest reward
        uint256 accAmount = uInfo.totalScore * poolInfo[_token].accPremiaPerShare / premiaPerShareMult;
        uint256 rewardAmount = accAmount - uInfo.rewardDebt;
        if (rewardAmount > 0) {
            _safePremiaTransfer(_user, rewardAmount);
        }

        uInfo.rewardDebt = accAmount;

        emit Harvest(_user, _token, rewardAmount);
    }

    /// @notice Safe premia transfer function, just in case if rounding error causes contract to not have enough PREMIAs.
    /// @param _to The address to which send premia
    /// @param _amount The amount to send
    function _safePremiaTransfer(address _to, uint256 _amount) internal {
        uint256 premiaBal = premia.balanceOf(address(this));
        if (_amount > premiaBal) {
            premia.safeTransfer(_to, premiaBal);
        } else {
            premia.safeTransfer(_to, _amount);
        }
    }

    function _getAccPremiaPerShare(address _token, uint256 _expiration) public view returns(uint256) {
        PoolInfo memory pInfo = poolInfo[_token];

        if (_expiration <= pInfo.lastUpdate) {
            return poolExpInfo[_token][_expiration].expAccPremiaPerShare;
        } else {
            uint256 _totalPremiaRewarded = totalPremiaRewarded;

            while (pInfo.smallestExpiration <= _expiration && pInfo.totalScore > 0) {
                uint256 elapsed = pInfo.smallestExpiration - pInfo.lastUpdate;
                uint256 premiaAmount = _getPremiaAmountMined(_token, elapsed, _totalPremiaRewarded);
                _totalPremiaRewarded += premiaAmount;

                pInfo.accPremiaPerShare += ((premiaAmount * premiaPerShareMult) / pInfo.totalScore);

                pInfo.totalScore -= poolExpInfo[_token][pInfo.smallestExpiration].expScore;
                pInfo.lastUpdate = pInfo.smallestExpiration;
                pInfo.smallestExpiration += _expirationIncrement;
            }

            if (pInfo.smallestExpiration != _expiration && pInfo.totalScore > 0) {
                uint256 elapsed = _expiration - pInfo.lastUpdate;
                uint256 premiaAmount = _getPremiaAmountMined(_token, elapsed, _totalPremiaRewarded);
                _totalPremiaRewarded += premiaAmount;

                pInfo.accPremiaPerShare += ((premiaAmount * premiaPerShareMult) / pInfo.totalScore);
            }

            return pInfo.accPremiaPerShare;
        }
    }

    function _getPremiaAmountMined(address _token, uint256 _elapsed, uint256 _totalPremiaRewarded) internal view returns(uint256) {
        uint256 premiaAmount = premiaPerDay * poolInfo[_token].allocPoints * _elapsed / (3600 * 24) / totalAllocPoints;

        if (premiaAmount > totalPremiaAdded - _totalPremiaRewarded) {
            premiaAmount = totalPremiaAdded - _totalPremiaRewarded;
        }

        return premiaAmount;
    }
}
