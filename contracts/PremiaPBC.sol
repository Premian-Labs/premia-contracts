// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;


import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/access/Ownable.sol';


// Primary Bootstrap Contribution
contract PremiaPBC is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public premia;

    uint256 public startBlock;
    uint256 public endBlock;

    uint256 public premiaTotal;
    uint256 public ethTotal;

    address payable public treasury;

    mapping (address => uint256) public amountDeposited;
    mapping (address => bool) public hasCollected;

    ////////////
    // Events //
    ////////////

    event Contributed(address indexed user, uint256 amount);
    event Collected(address indexed user, uint256 amount);

    ///////////

    constructor(IERC20 _premia, uint256 _startBlock, uint256 _endBlock, address payable _treasury) {
        require(_startBlock < _endBlock, "EndBlock must be greater than StartBlock");
        premia = _premia;
        startBlock = _startBlock;
        endBlock = _endBlock;
        treasury = _treasury;
    }

    ///////////
    // Admin //
    ///////////

    // Add premia which will be distributed in the PBC
    function addPremia(uint256 _amount) external onlyOwner {
        require(block.number < endBlock, "PBC ended");

        premia.safeTransferFrom(msg.sender, address(this), _amount);
        premiaTotal = premiaTotal.add(_amount);
    }

    // Send eth collected during the PBC, to the treasury address
    function sendEthToTreasury() external onlyOwner {
        treasury.transfer(address(this).balance);
    }

    //

    // Return the current premia price in wei per premia
    function getPremiaPrice() external view returns(uint256) {
        return ethTotal.mul(1e18).div(premiaTotal);
    }

    // Deposit ETH to participate in the PBC
    function contribute() external payable nonReentrant {
        require(block.number >= startBlock, "PBC not started");
        require(msg.value > 0, "No eth sent");
        require(block.number < endBlock, "PBC ended");

        amountDeposited[msg.sender] = amountDeposited[msg.sender].add(msg.value);
        ethTotal = ethTotal.add(msg.value);
        emit Contributed(msg.sender, msg.value);
    }

    // Collect Premia after PBC has ended
    function collect() external nonReentrant {
        require(block.number > endBlock, "PBC not ended");
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
            premia.safeTransfer(_to, premiaBal);
        } else {
            premia.safeTransfer(_to, _amount);
        }
    }
}
