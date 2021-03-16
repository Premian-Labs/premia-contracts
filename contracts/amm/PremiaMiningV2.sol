// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "hardhat/console.sol";

import "../interface/IPoolControllerChild.sol";

contract PremiaMiningV2 is Ownable, ReentrancyGuard, IPoolControllerChild {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 lastUpdate;
        uint256 rewardDebt;
    }

    address public controller;
    IERC20 public premia;

    // Offset to add to Unix timestamp to make it Fri 23:59:59 UTC
    uint256 public constant _baseExpiration = 172799;
    // Expiration increment
    uint256 public constant _expirationIncrement = 1 weeks;
    // Max expiration time from now
    uint256 public _maxExpiration = 365 days;

    uint256 public constant _inverseBasisPoint = 1000;

    uint256 public premiaPerDay = 10000e18;

    // Token -> Weight (1000 = x1)
    mapping(address => uint256) tokenWeight;

    // User -> Expiration -> Score
    mapping(address => mapping(uint256 => uint256)) public userScore;

    // User -> Total score
    mapping(address => uint256) public userTotalScore;

    // Expiration -> score
    mapping(uint256 => uint256) public expirationScore;

    // User -> UserInfo
    mapping(address => UserInfo) public usersInfo;

    uint256 public totalScore;
    uint256 public smallestExpiration;
    uint256 public lastUpdate;
    uint256 public accPremiaPerShare;

    ////////////
    // Events //
    ////////////

    event ControllerUpdated(address indexed newController);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
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

    function setTokenWeights(address[] memory _tokens, uint256[] memory _weights) external {
        require(_tokens.length == _weights.length, "Array diff length");
        for (uint256 i=0; i < _tokens.length; i++) {
            tokenWeight[_tokens[i]] = _weights[i];
            emit TokenWeightUpdated(_tokens[i], _weights[i]);
        }
    }

    //////////
    // Main //
    //////////

    function pendingReward(address _user) external returns (uint256) {
        UserInfo memory info = usersInfo[_user];
        uint256 lastUserUpdate = info.lastUpdate;
        uint256 expiration = (lastUserUpdate / _expirationIncrement) * _expirationIncrement + _baseExpiration;
        if (expiration < lastUserUpdate) {
            expiration += _expirationIncrement;
        }

        uint256 score = userTotalScore[_user];

        console.log("Score", score, totalScore);

        if (expiration >= block.timestamp) {
            uint256 shares = (block.timestamp - lastUserUpdate) * score;
            uint256 updatedAccPremiaPerShare = _accPremiaPerShare() - info.rewardDebt;

            console.log("----");
            console.log(score, shares, updatedAccPremiaPerShare, shares * updatedAccPremiaPerShare / 1e12);

            return shares * updatedAccPremiaPerShare / 1e12;
        }

        uint256 shares = (expiration - lastUserUpdate) * score;
        score -= userScore[_user][expiration];

        while ((expiration + _expirationIncrement) < block.timestamp) {
            shares += _expirationIncrement * score;
            score -= userScore[_user][expiration];
            expiration += _expirationIncrement;
        }

        console.log(block.timestamp, expiration);
        shares += (block.timestamp - expiration) * score;

        uint256 updatedAccPremiaPerShare = _accPremiaPerShare() - info.rewardDebt;
        console.log("----");
        console.log(score, shares, updatedAccPremiaPerShare, shares * updatedAccPremiaPerShare / 1e12);

        return shares * updatedAccPremiaPerShare / 1e12;
    }

    function deposit(address _user, address _token, uint256 _amount, uint256 _lockExpiration) external view onlyController nonReentrant {
        updatePool();

        // ToDo : Move that after reward given to user
        if (usersInfo[_user].lastUpdate == 0) {
            usersInfo[_user].lastUpdate = block.timestamp;
            usersInfo[_user].rewardDebt = accPremiaPerShare;
        }

        console.log(_user);
        console.log(_token);
        console.log(_amount);
        console.log(_lockExpiration);

        uint256 multiplier = _inverseBasisPoint + ((_lockExpiration - block.timestamp) * _inverseBasisPoint / _maxExpiration);
        uint256 score = _amount * (tokenWeight[_token] / _inverseBasisPoint) * multiplier / _inverseBasisPoint;

        console.log("Mult", multiplier);
        console.log("Score", _amount * (tokenWeight[_token] / _inverseBasisPoint), score);

        userScore[_user][_lockExpiration] += score;
        userTotalScore[_user] += score;

        expirationScore[_lockExpiration] += score;
        totalScore += score;

        if (smallestExpiration == 0 || _lockExpiration < smallestExpiration) {
            smallestExpiration = _lockExpiration;
        }
    }

    function _accPremiaPerShare() internal view returns(uint256) {
        console.log("_accPremiaPerShare", smallestExpiration, totalScore, block.timestamp);
        if (smallestExpiration == 0 || totalScore == 0) return 0;

        uint256 result = accPremiaPerShare;
        uint256 score = totalScore;

        uint256 prevUpdate = lastUpdate;
        uint256 exp = smallestExpiration;

        while ((exp) < block.timestamp) {
            uint256 elapsed = exp - prevUpdate;
            uint256 premiaAmount = premiaPerDay * elapsed / (3600 * 24);
            console.log("Amount", premiaAmount);

            result = result + ((premiaAmount * 1e12) / (score * elapsed));

            score -= expirationScore[exp];
            prevUpdate = exp;
            exp += _expirationIncrement;
        }

        uint256 elapsed = block.timestamp - prevUpdate;
        if (score * elapsed > 0) {
            uint256 premiaAmount = premiaPerDay * elapsed / (3600 * 24);
            console.log("Amount", premiaAmount);

            result = result + ((premiaAmount * 1e12) / (score * elapsed));
        }

        return result;
    }

    function updatePool() public {
        if (smallestExpiration != 0 && block.timestamp > smallestExpiration) {
            while (smallestExpiration < block.timestamp) {
                _updateUntil(smallestExpiration);
                totalScore -= expirationScore[smallestExpiration];
                smallestExpiration += _expirationIncrement;
            }
        }

        _updateUntil(block.timestamp);
    }

    function _updateUntil(uint256 _timestamp) internal {
        console.log("Timestamp", _timestamp, lastUpdate);
        if (_timestamp <= lastUpdate) return;

        if (totalScore > 0) {
            uint256 elapsed = _timestamp - lastUpdate;
            uint256 premiaAmount = premiaPerDay * elapsed / (3600 * 24);

            console.log(accPremiaPerShare);
            console.log(premiaAmount);
            console.log(totalScore);
            accPremiaPerShare = accPremiaPerShare + ((premiaAmount * 1e12) / (totalScore * elapsed));
        }

        lastUpdate = _timestamp;
    }

    function harvest(uint256 _lockExpiration) external nonReentrant {
//        UserInfo storage info = usersInfo[msg.sender];
//        uint256 lastUserUpdate = info.lastUpdate;
//        uint256 expiration = (lastUserUpdate / _expirationIncrement) * _expirationIncrement + _baseExpiration;
//        if (expiration < lastUserUpdate) {
//            expiration += _expirationIncrement;
//        }
//
//        uint256 score = userTotalScore[msg.sender];
//        uint256 shares = (expiration - lastUserUpdate) * score;
//        score -= userScore[msg.sender][expiration];
//
//        while ((expiration + _expirationIncrement) < block.timestamp) {
//            shares += _expirationIncrement * score;
//            score -= userScore[msg.sender][expiration];
//            expiration += _expirationIncrement;
//        }
//
//        shares += (block.timestamp - expiration) * score;
//
//        uint256 rewardAmount = shares * accPremiaPerShare / 1e12;
//
//        if (rewardAmount > 0) {
//            premia.transfer(msg.sender, rewardAmount);
//        }
//
//        userTotalScore[msg.sender] = score;
//
//        info.lastUpdate = block.timestamp;
    }
}
