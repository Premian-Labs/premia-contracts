// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import "../interface/IFlashLoanReceiver.sol";
import "../uniswapV2/interfaces/IUniswapV2Router02.sol";

interface IPremiaOption is IERC1155 {
    struct TokenSettings {
        uint256 strikePriceIncrement;   // Increment for strike price
        uint8 decimals;                 // Number of decimals for the token
        bool isDisabled;                // Whether this token is disabled or not
    }

    struct OptionWriteArgs {
        address token;                  // Token address
        uint256 amount;                 // Amount of tokens to write option for
        uint256 strikePrice;            // Strike price (Must follow strikePriceIncrement of token)
        uint256 expiration;             // Expiration timestamp of the option (Must follow expirationIncrement)
        bool isCall;                    // If true : Call option | If false : Put option
    }

    struct OptionData {
        address token;                  // Token address
        uint256 strikePrice;            // Strike price (Must follow strikePriceIncrement of token)
        uint256 expiration;             // Expiration timestamp of the option (Must follow expirationIncrement)
        bool isCall;                    // If true : Call option | If false : Put option
        uint256 claimsPreExp;           // Amount of options from which the funds have been withdrawn pre expiration
        uint256 claimsPostExp;          // Amount of options from which the funds have been withdrawn post expiration
        uint256 exercised;              // Amount of options which have been exercised
        uint256 supply;                 // Total circulating supply
    }

    struct Pool {
        uint256 tokenAmount;
        uint256 denominatorAmount;
    }

    function maxExpiration() external view returns(uint256);
    function optionData(uint256 _optionId) external view returns (OptionData memory);
    function nbWritten(address _writer, uint256 _optionId) external view returns (uint256);

    function getOptionId(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall) external view returns(uint256);
    function getOptionIdOrCreate(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall) external returns(uint256);
    function getTotalFee(address _user, uint256 _price, bool _hasReferrer, bool _isWrite) external view returns(uint256);
    function getFees(address _user, uint256 _price, bool _hasReferrer, bool _isWrite) external view returns(uint256 _fee, uint256 _feeReferrer);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    function writeOption(address _token, OptionWriteArgs memory _option, address _referrer) external;
    function writeOptionFrom(address _from, OptionWriteArgs memory _option, address _referrer) external;
    function cancelOption(uint256 _optionId, uint256 _amount) external;
    function exerciseOption(uint256 _optionId, uint256 _amount) external;
    function exerciseOptionFrom(address _from, uint256 _optionId, uint256 _amount) external;
    function withdraw(uint256 _optionId) external;
    function withdrawPreExpiration(uint256 _optionId, uint256 _amount) external;
    function flashLoan(address _tokenAddress, uint256 _amount, IFlashLoanReceiver _receiver) external;
    function flashExerciseOption(uint256 _optionId, uint256 _amount, address _referrer, IUniswapV2Router02 _router, uint256 _amountInMax) external;

    /////////////////////
    // Batch functions //
    /////////////////////

    function batchWriteOption(OptionWriteArgs[] memory _options, address _referrer) external;
    function batchCancelOption(uint256[] memory _optionId, uint256[] memory _amounts) external;
    function batchWithdraw(uint256[] memory _optionId) external;
    function batchExerciseOption(uint256[] memory _optionId, uint256[] memory _amounts, address _referrer) external;
    function batchWithdrawPreExpiration(uint256[] memory _optionId, uint256[] memory _amounts) external;
}