// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interface/IPremiaAMM.sol";
import "../interface/IPoolControllerChild.sol";

contract PremiaMiningV2 is Ownable, ReentrancyGuard, IPoolControllerChild {
    using SafeERC20 for IERC20;

    IPremiaAMM public controller;
    IERC20 public premia;

    struct Pair {
        address token;
        address denominator;
        bool useToken;
    }

    struct PoolInfo {
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

    uint256 constant _inverseBasisPoint = 1e4;

    uint256 constant premiaPerShareMult = 1e12;

    // Max stake length multiplier
    uint256 public constant maxScoreMultiplier = 1e5; // 100% bonus if max stake length

    uint256 public premiaPerDay = 10000e18;

    // Total premia added to the contract as available reward
    uint256 public totalPremiaAdded;
    // Total premia allocated to users as reward
    uint256 public totalPremiaRewarded;

    //////
    //////

    uint256 totalAllocPoints;

    Pair[] public pairs;

    // Info of each pool. (Token -> Denominator -> useToken)
    mapping(address => mapping(address => mapping(bool => PoolInfo))) public poolInfo;

    // User -> Pool token -> Pool denominator -> useToken -> UserInfo
    mapping(address => mapping(address => mapping(address => mapping(bool => UserInfo)))) public userInfo;

    // User -> Pool token -> Pool denominator -> useToken -> Expiration -> Score
    mapping(address => mapping(address => mapping(address => mapping(bool => mapping(uint256 => uint256))))) public userScore;

    // Pool token -> Pool denominator -> useToken -> Expiration -> PoolExpInfo
    mapping(address => mapping(address => mapping(bool => mapping(uint256 => PoolExpInfo)))) public poolExpInfo;

    ////////////
    // Events //
    ////////////

    event PremiaAdded(uint256 amount);
    event ControllerUpdated(address indexed newController);
    event Deposit(address indexed user, address indexed token, address indexed denominator, bool useToken, uint256 amount);
    event Harvest(address indexed user, address indexed token, address indexed denominator, bool useToken, uint256 amount);
    event PoolSet(address indexed token, address indexed denominator, uint256 allocPoints);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    constructor(IPremiaAMM _controller, IERC20 _premia) {
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

    function addPool(address _token, address _denominator, uint256 _allocPoints, bool _withUpdate) external onlyOwner {
        require(poolInfo[_token][_denominator][true].lastUpdate == 0, "Pool already exists for token");
        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 halfAllocPoints = _allocPoints / 2;

        poolInfo[_token][_denominator][true] = PoolInfo({
            allocPoints: halfAllocPoints,
            totalScore: 0,
            smallestExpiration: 0,
            lastUpdate: block.timestamp,
            accPremiaPerShare: 0
        });

        poolInfo[_token][_denominator][false] = PoolInfo({
            allocPoints: halfAllocPoints,
            totalScore: 0,
            smallestExpiration: 0,
            lastUpdate: block.timestamp,
            accPremiaPerShare: 0
        });

        // useToken field does not matter here
        pairs.push(Pair(_token, _denominator, false));

        // We use halfAllocPoints in case there has been rounding
        totalAllocPoints += (halfAllocPoints * 2);

        emit PoolSet(_token, _denominator, _allocPoints);
    }

    function setPool(address _token, address _denominator, uint256 _allocPoints, bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 halfAllocPoints = _allocPoints / 2;

        // We use halfAllocPoints in case there has been rounding
        totalAllocPoints = totalAllocPoints - (poolInfo[_token][_denominator][true].allocPoints * 2) + (halfAllocPoints * 2);
        poolInfo[_token][_denominator][true].allocPoints = halfAllocPoints;
        poolInfo[_token][_denominator][false].allocPoints = halfAllocPoints;

        emit PoolSet(_token, _denominator, _allocPoints);
    }

    function upgradeController(address _newController) external override {
        require(msg.sender == owner() || msg.sender == address(controller), "Not owner or controller");
        controller = IPremiaAMM(_newController);
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
        for (uint256 i = 0; i < pairs.length; ++i) {
            updatePool(Pair(pairs[i].token, pairs[i].denominator, true));
            updatePool(Pair(pairs[i].token, pairs[i].denominator, false));
        }
    }

    /// @notice Get the list of pool pairs
    /// @return The list of pool pairs
    function getPairs() external view returns(Pair[] memory) {
        uint256 length = pairs.length;
        Pair[] memory result = new Pair[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = pairs[i];
        }

        return result;
    }

    function pendingReward(address _user, Pair memory _pair) external view returns (uint256) {
        PoolInfo memory pInfo = poolInfo[_pair.token][_pair.denominator][_pair.useToken];
        UserInfo memory uInfo = userInfo[_user][_pair.token][_pair.denominator][_pair.useToken];

        uint256 expiration = (pInfo.lastUpdate / _expirationIncrement) * _expirationIncrement + _baseExpiration;
        if (expiration < pInfo.lastUpdate) {
            expiration += _expirationIncrement;
        }

        uint256 _accPremiaPerShare;
        uint256 _totalPremiaRewarded = totalPremiaRewarded;

        if (expiration >= block.timestamp) {
            if (pInfo.totalScore == 0 || uInfo.totalScore == 0) return 0;

            uint256 elapsed = block.timestamp - pInfo.lastUpdate;
            uint256 premiaAmount = _getPremiaAmountMined(_pair, elapsed, _totalPremiaRewarded);
            _totalPremiaRewarded += premiaAmount;
            _accPremiaPerShare = pInfo.accPremiaPerShare + ((premiaAmount * premiaPerShareMult) / pInfo.totalScore);

            return (uInfo.totalScore * _accPremiaPerShare / premiaPerShareMult) - uInfo.rewardDebt;
        }

        _accPremiaPerShare = _getAccPremiaPerShare(_pair, expiration);
        uint256 totalReward;

        totalReward += (_accPremiaPerShare * uInfo.totalScore / premiaPerShareMult) - uInfo.rewardDebt;
        uInfo.rewardDebt = _accPremiaPerShare * uInfo.totalScore / premiaPerShareMult;

        uInfo.totalScore -= userScore[_user][_pair.token][_pair.denominator][_pair.useToken][expiration];
        pInfo.totalScore -= poolExpInfo[_pair.token][_pair.denominator][_pair.useToken][expiration].expScore;


        while (uInfo.totalScore > 0 && (expiration + _expirationIncrement) < block.timestamp) {
            expiration += _expirationIncrement;

            _accPremiaPerShare = _getAccPremiaPerShare(_pair, expiration);
            totalReward += (_accPremiaPerShare * uInfo.totalScore / premiaPerShareMult) - uInfo.rewardDebt;
            uInfo.rewardDebt = _accPremiaPerShare * uInfo.totalScore / premiaPerShareMult;

            uInfo.totalScore -= userScore[_user][_pair.token][_pair.denominator][_pair.useToken][expiration];
            pInfo.totalScore -= poolExpInfo[_pair.token][_pair.denominator][_pair.useToken][expiration].expScore;
        }

        if (uInfo.totalScore > 0) {
            _accPremiaPerShare = _getAccPremiaPerShare(_pair, block.timestamp);
            totalReward += (_accPremiaPerShare * uInfo.totalScore / premiaPerShareMult) - uInfo.rewardDebt;
        }

        return totalReward;
    }

    function updatePool(Pair memory _pair) public {
        PoolInfo storage pInfo = poolInfo[_pair.token][_pair.denominator][_pair.useToken];

        if (pInfo.smallestExpiration != 0 && block.timestamp > pInfo.smallestExpiration) {
            while (pInfo.smallestExpiration <= block.timestamp) {
                _updateUntil(_pair, pInfo.smallestExpiration);
                PoolExpInfo storage pExpInfo = poolExpInfo[_pair.token][_pair.denominator][_pair.useToken][pInfo.smallestExpiration];

                pInfo.totalScore -= pExpInfo.expScore;
                pExpInfo.expAccPremiaPerShare = pInfo.accPremiaPerShare;
                pInfo.smallestExpiration += _expirationIncrement;
            }
        }

        if (pInfo.smallestExpiration != block.timestamp) {
            _updateUntil(_pair, block.timestamp);
        }
    }


    function deposit(address _user, Pair memory _pair, uint256 _amount, uint256 _lockExpiration) external onlyController nonReentrant {
        updatePool(_pair);

        PoolInfo storage pInfo = poolInfo[_pair.token][_pair.denominator][_pair.useToken];
        UserInfo storage uInfo = userInfo[_user][_pair.token][_pair.denominator][_pair.useToken];

        if (uInfo.totalScore > 0) {
            // Pool already updated so we dont need to update it again
            _harvest(_user, _pair, false);
        }

        uint256 multiplier = _inverseBasisPoint + ((_lockExpiration - block.timestamp) * maxScoreMultiplier / _maxExpiration);
        uint256 score = _amount * multiplier / _inverseBasisPoint;

        userScore[_user][_pair.token][_pair.denominator][_pair.useToken][_lockExpiration] += score;
        uInfo.totalScore += score;

        poolExpInfo[_pair.token][_pair.denominator][_pair.useToken][_lockExpiration].expScore += score;
        pInfo.totalScore += score;

        if (pInfo.smallestExpiration == 0 || _lockExpiration < pInfo.smallestExpiration) {
            pInfo.smallestExpiration = _lockExpiration;
        }

        uInfo.rewardDebt = uInfo.totalScore * pInfo.accPremiaPerShare / premiaPerShareMult;

        emit Deposit(_user, _pair.token, _pair.denominator, _pair.useToken, _amount);
    }

    function harvest(Pair[] memory _pairs) external nonReentrant {
        for (uint256 i=0; i < _pairs.length; i++) {
            _harvest(msg.sender, _pairs[i], true);
        }
    }

    //////////////
    // Internal //
    //////////////

    function _updateUntil(Pair memory _pair, uint256 _timestamp) internal {
        PoolInfo storage pInfo = poolInfo[_pair.token][_pair.denominator][_pair.useToken];

        if (_timestamp <= pInfo.lastUpdate) return;

        if (pInfo.totalScore > 0) {
            uint256 elapsed = _timestamp - pInfo.lastUpdate;
            uint256 premiaAmount = _getPremiaAmountMined(_pair, elapsed, totalPremiaRewarded);

            pInfo.accPremiaPerShare += ((premiaAmount * premiaPerShareMult) / pInfo.totalScore);
            totalPremiaRewarded += premiaAmount;
        }

        pInfo.lastUpdate = _timestamp;
    }

    function _harvest(address _user, Pair memory _pair, bool _updatePool) internal {
        if (_updatePool) {
            updatePool(_pair);
        }

        UserInfo storage uInfo = userInfo[_user][_pair.token][_pair.denominator][_pair.useToken];

        // Harvest reward
        uint256 accAmount = uInfo.totalScore * poolInfo[_pair.token][_pair.denominator][_pair.useToken].accPremiaPerShare / premiaPerShareMult;
        uint256 rewardAmount = accAmount - uInfo.rewardDebt;
        if (rewardAmount > 0) {
            _safePremiaTransfer(_user, rewardAmount);
        }

        uInfo.rewardDebt = accAmount;

        emit Harvest(_user, _pair.token, _pair.denominator, _pair.useToken, rewardAmount);
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

    function _getAccPremiaPerShare(Pair memory _pair, uint256 _expiration) public view returns(uint256) {
        PoolInfo memory pInfo = poolInfo[_pair.token][_pair.denominator][_pair.useToken];

        if (_expiration <= pInfo.lastUpdate) {
            return poolExpInfo[_pair.token][_pair.denominator][_pair.useToken][_expiration].expAccPremiaPerShare;
        } else {
            uint256 _totalPremiaRewarded = totalPremiaRewarded;

            while (pInfo.smallestExpiration <= _expiration && pInfo.totalScore > 0) {
                uint256 elapsed = pInfo.smallestExpiration - pInfo.lastUpdate;
                uint256 premiaAmount = _getPremiaAmountMined(_pair, elapsed, _totalPremiaRewarded);
                _totalPremiaRewarded += premiaAmount;

                pInfo.accPremiaPerShare += ((premiaAmount * premiaPerShareMult) / pInfo.totalScore);

                pInfo.totalScore -= poolExpInfo[_pair.token][_pair.denominator][_pair.useToken][pInfo.smallestExpiration].expScore;
                pInfo.lastUpdate = pInfo.smallestExpiration;
                pInfo.smallestExpiration += _expirationIncrement;
            }

            if (pInfo.smallestExpiration != _expiration && pInfo.totalScore > 0) {
                uint256 elapsed = _expiration - pInfo.lastUpdate;
                uint256 premiaAmount = _getPremiaAmountMined(_pair, elapsed, _totalPremiaRewarded);
                _totalPremiaRewarded += premiaAmount;

                pInfo.accPremiaPerShare += ((premiaAmount * premiaPerShareMult) / pInfo.totalScore);
            }

            return pInfo.accPremiaPerShare;
        }
    }

    function _getPremiaAmountMined(Pair memory _pair, uint256 _elapsed, uint256 _totalPremiaRewarded) internal view returns(uint256) {
        uint256 premiaAmount = premiaPerDay * poolInfo[_pair.token][_pair.denominator][_pair.useToken].allocPoints * _elapsed / (3600 * 24) / totalAllocPoints;

        if (premiaAmount > totalPremiaAdded - _totalPremiaRewarded) {
            premiaAmount = totalPremiaAdded - _totalPremiaRewarded;
        }

        return premiaAmount;
    }
}
