// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interface/IPoolControllerChild.sol";

contract PremiaMiningV2 is Ownable, ReentrancyGuard, IPoolControllerChild {
    using SafeERC20 for IERC20;

    address public controller;
    IERC20 public premia;

    struct Pool {
        address token;
        uint256 allocPoints;
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

    // Token -> Weight (1000 = x1)
    mapping(address => uint256) tokenWeight;

    // User -> Expiration -> Score
    mapping(address => mapping(uint256 => uint256)) public userScore;

    // User -> Total score
    mapping(address => uint256) public userTotalScore;

    // Expiration -> score
    mapping(uint256 => uint256) public expirationScore;

    // User -> UserInfo
    mapping(address => uint256) public usersRewardDebt;

    uint256 public totalScore;
    uint256 public smallestExpiration;
    uint256 public lastUpdate;
    uint256 public accPremiaPerShare;

    mapping(uint256=>uint256) public accPremiaPerSharePerExp;

    ////////////
    // Events //
    ////////////

    event PremiaAdded(uint256 amount);
    event ControllerUpdated(address indexed newController);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event TokenWeightUpdated(address indexed token, uint256 weight);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    constructor(address _controller, IERC20 _premia) {
        controller = _controller;
        premia = _premia;
        lastUpdate = block.timestamp;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////////
    // Modifiers //
    ///////////////

    modifier onlyController() {
        require(msg.sender == controller, "Caller is not the controller");
        _;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    function upgradeController(address _newController) external override {
        require(msg.sender == owner() || msg.sender == controller, "Not owner or controller");
        controller = _newController;
        emit ControllerUpdated(_newController);
    }

    function setTokenWeights(address[] memory _tokens, uint256[] memory _weights) external onlyOwner {
        require(_tokens.length == _weights.length, "Array diff length");
        for (uint256 i=0; i < _tokens.length; i++) {
            tokenWeight[_tokens[i]] = _weights[i];
            emit TokenWeightUpdated(_tokens[i], _weights[i]);
        }
    }

    function addRewards(uint256 _amount) external onlyOwner {
        premia.safeTransferFrom(msg.sender, address(this), _amount);
        totalPremiaAdded += _amount;
    }

    //////////
    // Main //
    //////////

    function pendingReward(address _user) external view returns (uint256) {
        uint256 rewardDebt = usersRewardDebt[_user];
        uint256 expiration = (lastUpdate / _expirationIncrement) * _expirationIncrement + _baseExpiration;
        if (expiration < lastUpdate) {
            expiration += _expirationIncrement;
        }

        uint256 _userTotalScore = userTotalScore[_user];
        uint256 _totalScore = totalScore;
        uint256 _accPremiaPerShare;
        uint256 _totalPremiaRewarded = totalPremiaRewarded;

        if (expiration >= block.timestamp) {
            if (_totalScore == 0 || _userTotalScore == 0) return 0;

            uint256 elapsed = block.timestamp - lastUpdate;
            uint256 premiaAmount = _getPremiaAmountMined(elapsed, _totalPremiaRewarded);
            _totalPremiaRewarded += premiaAmount;

            _accPremiaPerShare = accPremiaPerShare + ((premiaAmount * premiaPerShareMult) / _totalScore);

            return _userTotalScore * _accPremiaPerShare / premiaPerShareMult - rewardDebt;
        }

        _accPremiaPerShare = _getAccPremiaPerShare(expiration);
        uint256 totalReward;

        totalReward += (_accPremiaPerShare * _userTotalScore / premiaPerShareMult) - rewardDebt;
        rewardDebt = _accPremiaPerShare * _userTotalScore / premiaPerShareMult;

        _userTotalScore -= userScore[_user][expiration];
        _totalScore -= expirationScore[expiration];


        while (_userTotalScore > 0 && (expiration + _expirationIncrement) < block.timestamp) {
            expiration += _expirationIncrement;

            _accPremiaPerShare = _getAccPremiaPerShare(expiration);
            totalReward += (_accPremiaPerShare * _userTotalScore / premiaPerShareMult) - rewardDebt;
            rewardDebt = _accPremiaPerShare * _userTotalScore / premiaPerShareMult;

            _userTotalScore -= userScore[_user][expiration];
            _totalScore -= expirationScore[expiration];
        }

        if (_userTotalScore > 0) {
            _accPremiaPerShare = _getAccPremiaPerShare(block.timestamp);
            totalReward += (_accPremiaPerShare * _userTotalScore / premiaPerShareMult) - rewardDebt;
        }

        return totalReward;
    }

    function updatePool() public {
        if (smallestExpiration != 0 && block.timestamp > smallestExpiration) {
            while (smallestExpiration <= block.timestamp) {
                _updateUntil(smallestExpiration);
                totalScore -= expirationScore[smallestExpiration];
                accPremiaPerSharePerExp[smallestExpiration] = accPremiaPerShare;
                smallestExpiration += _expirationIncrement;
            }
        }

        if (smallestExpiration != block.timestamp) {
            _updateUntil(block.timestamp);
        }
    }


    function deposit(address _user, address _token, uint256 _amount, uint256 _lockExpiration) external onlyController nonReentrant {
        updatePool();

        if (userTotalScore[_user] > 0) {
            // Pool already updated so we dont need to update it again
            _harvest(_user, false);
        }

        uint256 multiplier = _inverseBasisPoint + ((_lockExpiration - block.timestamp) * _inverseBasisPoint / _maxExpiration);
        uint256 score = _amount * (tokenWeight[_token] / _inverseBasisPoint) * multiplier / _inverseBasisPoint;

        userScore[_user][_lockExpiration] += score;
        userTotalScore[_user] += score;

        expirationScore[_lockExpiration] += score;
        totalScore += score;

        if (smallestExpiration == 0 || _lockExpiration < smallestExpiration) {
            smallestExpiration = _lockExpiration;
        }

        usersRewardDebt[_user] = userTotalScore[_user] * accPremiaPerShare / premiaPerShareMult;

        emit Deposit(_user, 0, _amount);
    }

    function harvest() external nonReentrant {
        _harvest(msg.sender, true);
    }

    //////////////
    // Internal //
    //////////////

    function _updateUntil(uint256 _timestamp) internal {
        if (_timestamp <= lastUpdate) return;

        if (totalScore > 0) {
            uint256 elapsed = _timestamp - lastUpdate;
            uint256 premiaAmount = _getPremiaAmountMined(elapsed, totalPremiaRewarded);

            accPremiaPerShare = accPremiaPerShare + ((premiaAmount * premiaPerShareMult) / totalScore);
            totalPremiaRewarded += premiaAmount;
        }

        lastUpdate = _timestamp;
    }

    function _harvest(address _user, bool _updatePool) internal {
        if (_updatePool) {
            updatePool();
        }

        // Harvest reward
        uint256 accAmount = userTotalScore[_user] * accPremiaPerShare / premiaPerShareMult;
        uint256 rewardAmount = accAmount - usersRewardDebt[_user];
        if (rewardAmount > 0) {
            _safePremiaTransfer(_user, rewardAmount);
        }

        usersRewardDebt[_user] = accAmount;

        emit Harvest(_user, 0, rewardAmount);
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

    function _getAccPremiaPerShare(uint256 _expiration) public view returns(uint256) {
        if (_expiration <= lastUpdate) {
            return accPremiaPerSharePerExp[_expiration];
        } else {
            uint256 result = accPremiaPerShare;
            uint256 score = totalScore;

            uint256 prevUpdate = lastUpdate;
            uint256 exp = smallestExpiration;
            uint256 _totalPremiaRewarded = totalPremiaRewarded;

            while (exp <= _expiration && score > 0) {
                uint256 elapsed = exp - prevUpdate;
                uint256 premiaAmount = _getPremiaAmountMined(elapsed, _totalPremiaRewarded);
                _totalPremiaRewarded += premiaAmount;

                result = result + ((premiaAmount * premiaPerShareMult) / score);

                score -= expirationScore[exp];
                prevUpdate = exp;
                exp += _expirationIncrement;
            }

            if (exp != _expiration && score > 0) {
                uint256 elapsed = _expiration - prevUpdate;
                uint256 premiaAmount = _getPremiaAmountMined(elapsed, _totalPremiaRewarded);
                _totalPremiaRewarded += premiaAmount;

                result = result + ((premiaAmount * premiaPerShareMult) / score);
            }

            return result;
        }
    }

    function _getPremiaAmountMined(uint256 _elapsed, uint256 _totalPremiaRewarded) internal view returns(uint256) {
        uint256 premiaAmount = premiaPerDay * _elapsed / (3600 * 24);

        if (premiaAmount > totalPremiaAdded - _totalPremiaRewarded) {
            premiaAmount = totalPremiaAdded - _totalPremiaRewarded;
        }

        return premiaAmount;
    }
}
