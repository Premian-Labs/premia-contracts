// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import "../interface/IFlashLoanReceiver.sol";
import "../uniswapV2/interfaces/IUniswapV2Router02.sol";

interface IPremiaOption is IERC1155 {
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
        uint8 decimals;                 // Token decimals
    }

    // Total write cost = collateral + fee + feeReferrer
    struct QuoteWrite {
        address collateralToken;        // The token to deposit as collateral
        uint256 collateral;             // The amount of collateral to deposit
        uint8 collateralDecimals;       // Decimals of collateral token
        uint256 fee;                    // The amount of collateralToken needed to be paid as protocol fee
        uint256 feeReferrer;            // The amount of collateralToken which will be paid the referrer
    }

    // Total exercise cost = input + fee + feeReferrer
    struct QuoteExercise {
        address inputToken;             // Input token for exercise
        uint256 input;                  // Amount of input token to pay to exercise
        uint8 inputDecimals;            // Decimals of input token
        address outputToken;            // Output token from the exercise
        uint256 output;                 // Amount of output tokens which will be received on exercise
        uint8 outputDecimals;           // Decimals of output token
        uint256 fee;                    // The amount of inputToken needed to be paid as protocol fee
        uint256 feeReferrer;            // The amount of inputToken which will be paid to the referrer
    }

    struct Pool {
        uint256 tokenAmount;
        uint256 denominatorAmount;
    }

    function denominatorDecimals() external view returns(uint8);

    function maxExpiration() external view returns(uint256);
    function optionData(uint256 _optionId) external view returns (OptionData memory);
    function tokenStrikeIncrement(address _token) external view returns (uint256);
    function nbWritten(address _writer, uint256 _optionId) external view returns (uint256);

    function getOptionId(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall) external view returns(uint256);
    function getOptionIdOrCreate(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall) external returns(uint256);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    function getWriteQuote(address _from, OptionWriteArgs memory _option, address _referrer, uint8 _decimals) external view returns(QuoteWrite memory);
    function getExerciseQuote(address _from, OptionData memory _option, uint256 _amount, address _referrer, uint8 _decimals) external view returns(QuoteExercise memory);

    function writeOptionWithIdFrom(address _from, uint256 _optionId, uint256 _amount, address _referrer) external returns(uint256);
    function writeOption(address _token, OptionWriteArgs memory _option, address _referrer) external returns(uint256);
    function writeOptionFrom(address _from, OptionWriteArgs memory _option, address _referrer) external returns(uint256);
    function cancelOption(uint256 _optionId, uint256 _amount) external;
    function cancelOptionFrom(address _from, uint256 _optionId, uint256 _amount) external;
    function exerciseOption(uint256 _optionId, uint256 _amount) external;
    function exerciseOptionFrom(address _from, uint256 _optionId, uint256 _amount) external;
    function withdraw(uint256 _optionId) external;
    function withdrawFrom(address _from, uint256 _optionId) external;
    function withdrawPreExpiration(uint256 _optionId, uint256 _amount) external;
    function withdrawPreExpirationFrom(address _from, uint256 _optionId, uint256 _amount) external;
    function flashExerciseOption(uint256 _optionId, uint256 _amount, address _referrer, IUniswapV2Router02 _router, uint256 _amountInMax) external;
    function flashExerciseOptionFrom(address _from, uint256 _optionId, uint256 _amount, address _referrer, IUniswapV2Router02 _router, uint256 _amountInMax) external;
    function flashLoan(address _tokenAddress, uint256 _amount, IFlashLoanReceiver _receiver) external;

    /////////////////////
    // Batch functions //
    /////////////////////

    function batchWriteOption(OptionWriteArgs[] memory _options, address _referrer) external;
    function batchCancelOption(uint256[] memory _optionId, uint256[] memory _amounts) external;
    function batchWithdraw(uint256[] memory _optionId) external;
    function batchExerciseOption(uint256[] memory _optionId, uint256[] memory _amounts, address _referrer) external;
    function batchWithdrawPreExpiration(uint256[] memory _optionId, uint256[] memory _amounts) external;
}