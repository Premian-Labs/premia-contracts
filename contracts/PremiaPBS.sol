// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;


import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "./interface/IPremiaBondingCurve.sol";


// Primary Bootstrap Contribution
contract PremiaPBS is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    IERC20 public premia;

    uint256 public startBlock;
    uint256 public endBlock;

    uint256 public premiaTotal;
    uint256 public ethTotal;

    mapping (address => uint256) public amountDeposited;
    mapping (address => bool) public hasCollected;

    IPremiaBondingCurve public premiaBondingCurve;

    ////////////
    // Events //
    ////////////

    event Contributed(address indexed user, uint256 amount);
    event Collected(address indexed user, uint256 amount);

    ///////////

    constructor(IERC20 _premia, uint256 _startBlock, uint256 _endBlock) {
        require(_startBlock < _endBlock, "EndBlock must be greater than StartBlock");
        premia = _premia;
        startBlock = _startBlock;
        endBlock = _endBlock;
    }

    ///////////
    // Admin //
    ///////////

    // Add premia which will be distributed in the PBS
    function addPremia(uint256 _amount) external onlyOwner {
        require(block.number < endBlock, "PBS ended");

        premia.transferFrom(msg.sender, address(this), _amount);
        premiaTotal = premiaTotal.add(_amount);
    }

    // Send eth collected during the PBS, to the _to address
    function sendEth(address payable _to) external onlyOwner {
        _to.transfer(address(this).balance);
    }

    // Set the PremiaBondingCurve contract address, to be able to initialize the bonding curve once contribution has ended
    function setPremiaBondingCurve(IPremiaBondingCurve _premiaBondingCurve) external onlyOwner {
        premiaBondingCurve = _premiaBondingCurve;
    }

    //

    // Initialize the start price of the bonding price, using the final PREMIA:ETH ratio defined by the PBS
    function initializeBondingCurve() external {
        require(block.number > endBlock, "PBS not ended");
        require(premiaBondingCurve.isInitialized() == false, "Bonding curve already initialized");

        premiaBondingCurve.initialize(premiaTotal.mul(1e18).div(ethTotal));
    }

    // Deposit ETH to participate in the PBS
    function contribute() external payable nonReentrant {
        require(block.number >= startBlock, "PBS not started");
        require(msg.value > 0, "No eth sent");
        require(block.number < endBlock, "PBS ended");

        amountDeposited[msg.sender] = amountDeposited[msg.sender].add(msg.value);
        ethTotal = ethTotal.add(msg.value);
        emit Contributed(msg.sender, msg.value);
    }

    // Collect Premia after PBS has ended
    function collect() external nonReentrant {
        require(block.number > endBlock, "PBS not ended");
        require(hasCollected[msg.sender] == false, "Address already collected its reward");
        require(amountDeposited[msg.sender] > 0, "Address did not contribute");

        hasCollected[msg.sender] = true;
        uint256 contribution = amountDeposited[msg.sender].mul(1e12).div(ethTotal);
        uint256 premiaAmount = premiaTotal.mul(contribution).div(1e12);
        safePremiaTransfer(msg.sender, premiaAmount);
        emit Collected(msg.sender, premiaAmount);
    }

    // Safe premia transfer function, just in case if rounding error causes contract to not have enough PREMIAs.
    function safePremiaTransfer(address _to, uint256 _amount) internal {
        uint256 premiaBal = premia.balanceOf(address(this));
        if (_amount > premiaBal) {
            premia.transfer(_to, premiaBal);
        } else {
            premia.transfer(_to, _amount);
        }
    }
}
