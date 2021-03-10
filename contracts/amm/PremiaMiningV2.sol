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

    // Expiration -> score
    mapping(uint256 => uint256) public expirationScore;

    uint256 public totalScore;
    uint256 public smallestExpiration;
    uint256 public lastUpdate;

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

    function pendingReward() external view returns (uint256) {
        return 0;
    }

    function deposit(address _user, address _token, uint256 _amount, uint256 _lockExpiration) external onlyController nonReentrant {
        uint256 multiplier = _inverseBasisPoint + ((_lockExpiration - block.timestamp) * _inverseBasisPoint / _maxExpiration);
        uint256 score = userScore[_user][_lockExpiration] + (_amount * (tokenWeight[_token] / _inverseBasisPoint) * (multiplier / _inverseBasisPoint));

        userScore[_user][_lockExpiration] += score;
        expirationScore[_lockExpiration] += score;
        totalScore += score;

        if (smallestExpiration == 0 || _lockExpiration < smallestExpiration) {
            smallestExpiration = _lockExpiration;
        }
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
        require(_timestamp > lastUpdate, "Already up to date");

        // ToDo : Implement update logic

        lastUpdate = _timestamp;
    }

    function harvest(uint256 _lockExpiration) external nonReentrant {

    }
}
