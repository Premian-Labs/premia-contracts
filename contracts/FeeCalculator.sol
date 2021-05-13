// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

import "./interface/IPremiaFeeDiscount.sol";

/// @author Premia
/// @title Calculate protocol fees, including discount from xPremia locking
contract FeeCalculator is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;

    enum FeeType {Write, Exercise, Maker, Taker, FlashLoan}

    // Addresses which dont have to pay fees
    EnumerableSet.AddressSet private _whitelisted;

    uint256 public writeFee = 100; // 1%
    uint256 public exerciseFee = 100; // 1%
    uint256 public flashLoanFee = 20; // 0.2%

    uint256 public makerFee = 150; // 1.5%
    uint256 public takerFee = 150; // 1.5%

    uint256 private constant _inverseBasisPoint = 1e4;

    //

    // PremiaFeeDiscount contract, handling xPremia locking for fee discount
    IPremiaFeeDiscount public premiaFeeDiscount;

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    /// @param _premiaFeeDiscount Address of PremiaFeeDiscount contract
    constructor(IPremiaFeeDiscount _premiaFeeDiscount) {
        premiaFeeDiscount = _premiaFeeDiscount;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    /// @notice Set new address for PremiaFeeDiscount contract
    /// @param _premiaFeeDiscount The new contract address
    function setPremiaFeeDiscount(IPremiaFeeDiscount _premiaFeeDiscount) external onlyOwner {
        premiaFeeDiscount = _premiaFeeDiscount;
    }

    /// @notice Set new protocol fee for option writing
    /// @param _fee The new fee (In basis points)
    function setWriteFee(uint256 _fee) external onlyOwner {
        require(_fee <= 500); // Hardcoded max at 5%
        writeFee = _fee;
    }

    /// @notice Set new protocol fee for exercising options
    /// @param _fee The new fee (In basis points)
    function setExerciseFee(uint256 _fee) external onlyOwner {
        require(_fee <= 500); // Hardcoded max at 5%
        exerciseFee = _fee;
    }

    /// @notice Set new protocol fee for flashLoans
    /// @param _fee The new fee (In basis points)
    function setFlashLoanFee(uint256 _fee) external onlyOwner {
        require(_fee <= 500); // Hardcoded max at 5%
        flashLoanFee = _fee;
    }

    /// @notice Set new protocol fee for order maker
    /// @param _fee The new fee (In basis points)
    function setMakerFee(uint256 _fee) external onlyOwner {
        require(_fee <= 500); // Hardcoded max at 5%
        makerFee = _fee;
    }

    /// @notice Set new protocol fee for order taker
    /// @param _fee The new fee (In basis points)
    function setTakerFee(uint256 _fee) external onlyOwner {
        require(_fee <= 500); // Hardcoded max at 5%
        takerFee = _fee;
    }

    /// @notice Add addresses to the whitelist so that they dont have to pay fees. (Could be use to whitelist some contracts)
    /// @param _addr The addresses to add to the whitelist
    function addWhitelisted(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelisted.add(_addr[i]);
        }
    }

    /// @notice Removed addresses from the whitelist so that they have to pay fees again.
    /// @param _addr The addresses to remove the whitelist
    function removeWhitelisted(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelisted.remove(_addr[i]);
        }
    }

    //////////////////////////////////////////////////

    //////////
    // View //
    //////////

    /// @notice Get the list of whitelisted addresses
    /// @return The list of whitelisted addresses
    function getWhitelisted() external view returns(address[] memory) {
        uint256 length = _whitelisted.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelisted.at(i);
        }

        return result;
    }

    /// @notice Get fee (In basis points) to pay by a given user, for a given fee type
    /// @param _user The address for which to calculate the fee
    /// @param _feeType The type of fee
    /// @return The protocol fee to pay by _user (In basis points)
    function getFee(address _user, FeeType _feeType) external view returns(uint256) {
        if (_whitelisted.contains(_user)) return 0;

        uint256 fee = _getBaseFee(_feeType);

        // If premiaFeeDiscount contract is set, we calculate discount
        if (address(premiaFeeDiscount) != address(0)) {
            uint256 discount = premiaFeeDiscount.getDiscount(_user);
            fee = fee.mul(discount).div(_inverseBasisPoint);
        }

        return fee;
    }

    /// @notice Get the final fee amounts (In wei) to pay to protocol
    /// @param _user The address for which to calculate the fee
    /// @param _amount The amount for which fee needs to be calculated
    /// @param _feeType The type of fee
    /// @return Fee amount to pay to protocol
    function getFeeAmount(address _user, uint256 _amount, FeeType _feeType) external view returns(uint256) {
        if (_whitelisted.contains(_user)) return 0;

        uint256 baseFee = _amount.mul(_getBaseFee(_feeType)).div(_inverseBasisPoint);
        return getFeeAmountWithDiscount(_user, baseFee);
    }

    /// @notice Calculate protocol fee to pay, from a total fee (in wei), after applying all discounts
    /// @param _user The address for which to calculate the fee
    /// @param _baseFee The total fee to pay (without including any discount)
    /// @return Fee amount to pay to protocol
    function getFeeAmountWithDiscount(address _user, uint256 _baseFee) public view returns(uint256) {
        if (_whitelisted.contains(_user)) return 0;

        uint256 feeDiscount = 0;

        // If premiaFeeDiscount contract is set, we calculate discount
        if (address(premiaFeeDiscount) != address(0)) {
            uint256 discount = premiaFeeDiscount.getDiscount(_user);
            require(discount <= _inverseBasisPoint, "Discount > max");
            feeDiscount = _baseFee.mul(discount).div(_inverseBasisPoint);
        }

        return _baseFee.sub(feeDiscount);
    }

    //////////////////////////////////////////////////

    //////////////
    // Internal //
    //////////////

    /// @notice Get the base protocol fee, for a given fee type
    /// @param _feeType The type of fee
    /// @return The base protocol fee for _feeType (In basis points)
    function _getBaseFee(FeeType _feeType) internal view returns(uint256) {
        if (_feeType == FeeType.Write) {
            return writeFee;
        } else if (_feeType == FeeType.Exercise) {
            return exerciseFee;
        } else if (_feeType == FeeType.Maker) {
            return makerFee;
        } else if (_feeType == FeeType.Taker) {
            return takerFee;
        } else if (_feeType == FeeType.FlashLoan) {
            return flashLoanFee;
        }

        return 0;
    }
}
