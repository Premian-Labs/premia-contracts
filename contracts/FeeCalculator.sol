// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';

import "./interface/IPremiaReferral.sol";
import "./interface/IPremiaFeeDiscount.sol";

// Contract used to provide token prices in USD, in order to calculate PremiaUncut reward to give to users.
// Prices will be updated manually every few days, as this use case doesnt really require very accurate price data
contract FeeCalculator is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;

    enum FeeType {Write, Exercise, Maker, Taker, FlashLoan}

    // Addresses which dont have to pay fees
    EnumerableSet.AddressSet private _whitelisted;

    uint256 public writeFee = 100; // 1%
    uint256 public exerciseFee = 100; // 1%
    uint256 public flashLoanFee = 20; // 0.2%

    // 10% of write/exercise fee | Referrer fee calculated after all discounts applied
    uint256 public referrerFee = 1000;
    // -10% from write/exercise fee
    uint256 public referredDiscount = 1000;

    /* For split fee orders, minimum required protocol maker fee, in basis points. Paid to owner (who can change it). */
    uint256 public makerFee = 150; // 1.5%

    /* For split fee orders, minimum required protocol taker fee, in basis points. Paid to owner (who can change it). */
    uint256 public takerFee = 150; // 1.5%

    uint256 private constant _inverseBasisPoint = 1e4;


    //

    IPremiaFeeDiscount public premiaFeeDiscount;

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    constructor(IPremiaFeeDiscount _premiaFeeDiscount) {
        premiaFeeDiscount = _premiaFeeDiscount;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    function setPremiaFeeDiscount(IPremiaFeeDiscount _premiaFeeDiscount) external onlyOwner {
        premiaFeeDiscount = _premiaFeeDiscount;
    }

    function setWriteFee(uint256 _fee) external onlyOwner {
        require(_fee <= 500);
        writeFee = _fee;
    }

    function setExerciseFee(uint256 _fee) external onlyOwner {
        require(_fee <= 500);
        exerciseFee = _fee;
    }

    function setFlashLoanFee(uint256 _fee) external onlyOwner {
        require(_fee <= 500);
        flashLoanFee = _fee;
    }

    function setReferrerFee(uint256 _fee) external onlyOwner {
        require(_fee <= 1e4);
        referrerFee = _fee;
    }

    function setReferredDiscount(uint256 _discount) external onlyOwner {
        require(_discount <= 1e4);
        referredDiscount = _discount;
    }

    function setMakerFee(uint256 _fee) external onlyOwner {
        require(_fee <= 500);
        makerFee = _fee;
    }

    function setTakerFee(uint256 _fee) external onlyOwner {
        require(_fee <= 500);
        takerFee = _fee;
    }

    function addWhitelisted(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelisted.add(_addr[i]);
        }
    }

    function removeWhitelisted(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelisted.remove(_addr[i]);
        }
    }

    //////////////////////////////////////////////////

    function getWhitelisted() external view returns(address[] memory) {
        uint256 length = _whitelisted.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelisted.at(i);
        }

        return result;
    }

    function getBaseFee(uint256 _amount, FeeType _feeType) public view returns(uint256) {
        if (_feeType == FeeType.Write) {
            return _amount.mul(writeFee).div(_inverseBasisPoint);
        } else if (_feeType == FeeType.Exercise) {
            return _amount.mul(exerciseFee).div(_inverseBasisPoint);
        } else if (_feeType == FeeType.Maker) {
            return _amount.mul(makerFee).div(_inverseBasisPoint);
        } else if (_feeType == FeeType.Taker) {
            return _amount.mul(takerFee).div(_inverseBasisPoint);
        } else if (_feeType == FeeType.FlashLoan) {
            return _amount.mul(flashLoanFee).div(_inverseBasisPoint);
        }

        return 0;
    }

    function getFees(address _user, bool _hasReferrer, uint256 _amount, FeeType _feeType) public view returns(uint256 _fee, uint256 _feeReferrer) {
        if (_whitelisted.contains(_user)) return (0,0);

        uint256 baseFee = getBaseFee(_amount, _feeType);
        return getFeesWithDiscount(_user, _hasReferrer, baseFee);
    }

    function getFeesWithDiscount(address _user, bool _hasReferrer, uint256 _baseFee) public view returns(uint256 _fee, uint256 _feeReferrer) {
        if (_whitelisted.contains(_user)) return (0,0);

        uint256 feeReferrer = 0;
        uint256 feeDiscount = 0;

        // If premiaFeeDiscount contract is set, we calculate discount
        if (address(premiaFeeDiscount) != address(0)) {
            uint256 discount = premiaFeeDiscount.getDiscount(_user);
            require(discount <= _inverseBasisPoint, "Discount > max");
            feeDiscount = _baseFee.mul(discount).div(_inverseBasisPoint);
        }

        if (_hasReferrer) {
            // feeDiscount = feeDiscount + ( (_feeAmountBase - feeDiscount ) * referredDiscountRate)
            feeDiscount = feeDiscount.add(_baseFee.sub(feeDiscount).mul(referredDiscount).div(_inverseBasisPoint));
            feeReferrer = _baseFee.sub(feeDiscount).mul(referrerFee).div(_inverseBasisPoint);
        }

        return (_baseFee.sub(feeDiscount).sub(feeReferrer), feeReferrer);
    }
}
