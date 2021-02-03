// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import "./interface/IPremiaBondingCurveUpgrade.sol";
import "./interface/IERC2612Permit.sol";

/// @author Premia (Code forked from Hegic's LinearBondingCurve)
/// @title A premia <-> eth linear bonding curve
contract PremiaBondingCurve is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // The premia token
    IERC20 public premia;
    // The treasury address (which will receive commission on Premia sales)
    address payable public treasury;

    // Price increase for each token sold
    uint256 internal immutable k;
    // Starting price of the bonding curve
    uint256 internal immutable startPrice;
    // Total tokens sold
    uint256 public soldAmount;

    // New PremiaBondingCurve contract address, if an upgrade is pending
    IPremiaBondingCurveUpgrade public newContract;
    // The timestamp after which upgrade will be executable
    uint256 public upgradeETA;
    // The delay after which upgrade can be executed (From date at which startUpgrade has been called)
    uint256 public immutable upgradeDelay = 7 days;

    // Whether an upgrade has been done or not
    // If this is true, buy / sell will be disabled on this contract
    bool public isUpgradeDone;

    ////////////
    // Events //
    ////////////

    event Bought(address indexed account, address indexed sentTo, uint256 amount, uint256 ethAmount);
    event Sold(address indexed account, uint256 amount, uint256 ethAmount, uint256 comission);

    event UpgradeStarted(address newContract, uint256 eta);
    event UpgradeCancelled(address newContract, uint256 eta);
    event UpgradePerformed(address newContract, uint256 premiaBalance, uint256 ethBalance, uint256 soldAmount);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    /// @param _premia The premia token
    /// @param _treasury The treasury address (which will receive commission on Premia sales)
    /// @param _startPrice Starting price of the bonding curve
    /// @param _k Steepness of the curve (Lower value is steeper)
    constructor(IERC20 _premia, address payable _treasury, uint256 _startPrice, uint256 _k) {
        premia = _premia;
        treasury = _treasury;
        startPrice = _startPrice;
        k = _k;
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

    ///////////
    // Admin //
    ///////////

    /// @notice Start upgrade of the contract (Will have to go through the 7 days timelock before being able to execute)
    /// @param _newContract The new contract where funds will be migrated
    function startUpgrade(IPremiaBondingCurveUpgrade _newContract) external onlyOwner notUpgraded {
        newContract = _newContract;
        upgradeETA = block.timestamp.add(upgradeDelay);
        emit UpgradeStarted(address(newContract), upgradeETA);
    }

    /// @notice Perform the upgrade, if the 7 days timelock has passed
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

    /// @notice Cancel a pending contract upgrade
    function cancelUpgrade() external onlyOwner notUpgraded {
        address _newContract = address(newContract);
        uint256 _upgradeETA = upgradeETA;

        delete newContract;
        delete upgradeETA;

        emit UpgradeCancelled(address(_newContract), _upgradeETA);
    }

    //////////////////////////////////////////////////

    //////////
    // Main //
    //////////

    /// @notice Buy exact amount of premia (Will refund user any extra eth paid)
    /// @param _tokenAmount The amount of tokens to buy
    function buyExactTokenAmount(uint256 _tokenAmount) external payable notUpgraded {
        uint256 nextSold = soldAmount.add(_tokenAmount);
        uint256 ethAmount = getEthCost(soldAmount, nextSold);
        soldAmount = nextSold;
        require(msg.value >= ethAmount, "Value is too small");
        premia.safeTransfer(msg.sender, _tokenAmount);
        if (msg.value > ethAmount)
            msg.sender.transfer(msg.value.sub(ethAmount));
        emit Bought(msg.sender, msg.sender, _tokenAmount, ethAmount);
    }

    /// @notice Buy premia with exact eth amount
    /// @param _minToken The minimum amount of token needed to not have transaction reverted
    /// @param _sendTo The address which will receive the tokens
    /// @return The final amount of tokens purchased
    function buyTokenWithExactEthAmount(uint256 _minToken, address _sendTo) external payable notUpgraded returns(uint256) {
        uint256 ethAmount = msg.value;
        uint256 tokenAmount = getTokensPurchasable(ethAmount);
        require(tokenAmount >= _minToken, "< _minToken");
        soldAmount = soldAmount.add(tokenAmount);
        premia.safeTransfer(_sendTo, tokenAmount);
        emit Bought(msg.sender, _sendTo, tokenAmount, ethAmount);

        return tokenAmount;
    }

    /// @notice Sell using IERC2612 permit
    /// @param _tokenAmount The amount of tokens to sell
    /// @param _minEth The eth needed to not have the transaction reverted
    /// @param _deadline Deadline after which permit will fail
    /// @param _v V
    /// @param _r R
    /// @param _s S
    function sellWithPermit(uint256 _tokenAmount, uint256 _minEth, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) external {
        IERC2612Permit(address(premia)).permit(msg.sender, address(this), _tokenAmount, _deadline, _v, _r, _s);
        sell(_tokenAmount, _minEth);
    }

    /// @notice Sell premia tokens for eth
    /// @param _tokenAmount The amount of tokens to sell
    /// @param _minEth The eth needed to not have the transaction reverted
    function sell(uint256 _tokenAmount, uint256 _minEth) public notUpgraded {
        uint256 nextSold = soldAmount.sub(_tokenAmount);
        uint256 ethAmount = getEthCost(nextSold, soldAmount);
        require(ethAmount >= _minEth, "< _minEth");
        uint256 commission = ethAmount.div(10);
        uint256 refund = ethAmount.sub(commission);
        require(commission > 0);

        soldAmount = nextSold;
        premia.safeTransferFrom(msg.sender, address(this), _tokenAmount);
        treasury.transfer(commission);
        msg.sender.transfer(refund);
        emit Sold(msg.sender, _tokenAmount, refund, commission);
    }

    //////////////////////////////////////////////////

    //////////
    // View //
    //////////

    /// @notice Calculate eth cost to purchase tokens from x0 to x1
    /// @param _x0 The lower point on the curve from which to calculate eth cost
    /// @param _x1 The upper point on the curve from which to calculate eth cost
    /// @return The eth cost
    function getEthCost(uint256 _x0, uint256 _x1) public view returns (uint256) {
        require(_x1 > _x0);
        return _x1.add(_x0).mul(_x1.sub(_x0))
        .div(2).div(k)
        .add(startPrice.mul(_x1.sub(_x0)))
        .div(1e18);
    }

    /// @notice Calculate the amount of tokens purchasable with a known eth amount
    /// @param _ethAmount The eth amount to use for the purchase
    /// @return The amount of tokens purchasable with _ethAmount
    function getTokensPurchasable(uint256 _ethAmount) public view returns(uint256) {
        // x0 = soldAmount
        uint256 x1 = _sqrt(
            _ethAmount.mul(2e18).mul(k)
            .add(k.mul(k).mul(startPrice).mul(startPrice))
            .add(k.mul(2).mul(startPrice).mul(soldAmount))
            .add(soldAmount.mul(soldAmount)))
        .sub(k.mul(startPrice));

        return x1 - soldAmount;
    }

    //////////////////////////////////////////////////

    //////////////
    // Internal //
    //////////////

    /// @notice Square root calculation using Babylonian method
    ///        https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method
    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
