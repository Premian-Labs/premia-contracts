// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import "./interface/IPremiaBondingCurveUpgrade.sol";

// This contract is forked from Hegic's LinearBondingCurve
contract PremiaBondingCurve is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public premia;
    address payable public treasury;

    uint256 internal immutable K;
    uint256 internal immutable START_PRICE;
    uint256 public soldAmount;

    IPremiaBondingCurveUpgrade public newContract;
    uint256 public upgradeETA;
    uint256 public immutable upgradeDelay = 7 days;

    bool public isUpgradeDone;

    ////////////
    // Events //
    ////////////

    event Bought(address indexed account, uint256 amount, uint256 ethAmount);
    event Sold(address indexed account, uint256 amount, uint256 ethAmount, uint256 comission);

    event UpgradeStarted(address newContract, uint256 eta);
    event UpgradeCancelled(address newContract, uint256 eta);
    event UpgradePerformed(address newContract, uint256 premiaBalance, uint256 ethBalance, uint256 soldAmount);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    constructor(IERC20 _premia, address payable _treasury, uint256 _startPrice, uint256 _k) {
        premia = _premia;
        treasury = _treasury;
        START_PRICE = _startPrice;
        K = _k;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////////
    // Modifiers //
    ///////////////

    modifier notUpgraded() {
        require(!isUpgradeDone, "Contract has been upgraded");
        _;
    }

    //////////////////////////////////////////////////

    // Start upgrade of the contract (Upgrade will only be executable after 7 days have passed)
    function startUpgrade(IPremiaBondingCurveUpgrade _newContract) external onlyOwner notUpgraded {
        newContract = _newContract;
        upgradeETA = block.timestamp.add(upgradeDelay);
        emit UpgradeStarted(address(newContract), upgradeETA);
    }

    // Perform contract upgrade (Only callable 7 days after startUpgrade call)
    function doUpgrade() external onlyOwner notUpgraded {
        require(address(newContract) != address(0), "No new contract set");
        require(block.timestamp > upgradeETA, "Upgrade still timelocked");

        uint256 premiaBalance = premia.balanceOf(address(this));
        uint256 ethBalance = address(this).balance;
        premia.safeTransfer(address(newContract), premiaBalance);

        newContract.initialize{value: ethBalance}(premiaBalance, ethBalance, soldAmount);
        isUpgradeDone = true;
        emit UpgradePerformed(address(newContract), premiaBalance, ethBalance, soldAmount);
    }

    // Cancel a pending contract upgrade
    function cancelUpgrade() external onlyOwner notUpgraded {
        address _newContract = address(newContract);
        uint256 _upgradeETA = upgradeETA;

        delete newContract;
        delete upgradeETA;

        emit UpgradeCancelled(address(_newContract), _upgradeETA);
    }

    //////////////////////////////////////////////////

    function buy(uint256 tokenAmount) external payable notUpgraded {
        uint256 nextSold = soldAmount.add(tokenAmount);
        uint256 ethAmount = s(soldAmount, nextSold);
        soldAmount = nextSold;
        require(msg.value >= ethAmount, "Value is too small");
        premia.safeTransfer(msg.sender, tokenAmount);
        if (msg.value > ethAmount)
            msg.sender.transfer(msg.value.sub(ethAmount));
        emit Bought(msg.sender, tokenAmount, ethAmount);
    }

    function sell(uint256 tokenAmount) external notUpgraded {
        uint256 nextSold = soldAmount.sub(tokenAmount);
        uint256 ethAmount = s(nextSold, soldAmount);
        uint256 commission = ethAmount.div(10);
        uint256 refund = ethAmount.sub(commission);
        require(commission > 0);

        soldAmount = nextSold;
        premia.safeTransferFrom(msg.sender, address(this), tokenAmount);
        treasury.transfer(commission);
        msg.sender.transfer(refund);
        emit Sold(msg.sender, tokenAmount, refund, commission);
    }

    function s(uint256 x0, uint256 x1) public view returns (uint256) {
        require(x1 > x0);
        return x1.add(x0).mul(x1.sub(x0))
        .div(2).div(K)
        .add(START_PRICE.mul(x1.sub(x0)))
        .div(1e18);
    }
}
