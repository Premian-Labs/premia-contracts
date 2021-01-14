// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import "../interface/IFlashLoanReceiver.sol";
import "../uniswapV2/interfaces/IUniswapV2Router02.sol";

interface IPremiaOption is IERC1155 {
    struct TokenSettings {
        uint256 contractSize;           // Amount of token per contract
        uint256 strikePriceIncrement;   // Increment for strike price
        bool isDisabled;                // Whether this token is disabled or not
    }

    struct OptionData {
        address token;                  // Token address
        uint256 contractSize;           // Amount of token per contract
        uint256 expiration;             // Expiration timestamp of the option (Must follow expirationIncrement)
        uint256 strikePrice;            // Strike price (Must follow strikePriceIncrement of token)
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

    struct Privileges {
        bool isWhitelistedWriteExercise;          // If address is allowed to write / exercise without fee
        bool isWhitelistedFlashLoanReceiver;     // If address is allowed to do a flash loan without fee
        bool isWhitelistedUniswapRouter;         // If address is an accepted uniswap router
    }

    function getOptionId(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall) external view returns(uint256);
    function getOptionIdOrCreate(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall) external returns(uint256);
    function getOptionExpiration(uint256 _optionId) external view returns(uint256);
    function privileges(address _user) external view returns(Privileges memory);
    function getTotalFee(address _user, uint256 _price, bool _hasReferrer, bool _isWrite) external view returns(uint256);
    function getFees(address _user, uint256 _price, bool _hasReferrer, bool _isWrite) external view returns(uint256 _fee, uint256 _feeReferrer);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    function writeOption(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall, uint256 _contractAmount) external;
    function cancelOption(uint256 _optionId, uint256 _contractAmount) external;
    function exerciseOption(uint256 _optionId, uint256 _contractAmount) external;
    function withdraw(uint256 _optionId) external;
    function withdrawPreExpiration(uint256 _optionId, uint256 _contractAmount) external;
    function flashLoan(address _tokenAddress, uint256 _amount, IFlashLoanReceiver _receiver) external;
    function flashExerciseOption(uint256 _optionId, uint256 _contractAmount, address _referrer, IUniswapV2Router02 _router, uint256 _amountInMax) external;

    /////////////////////
    // Batch functions //
    /////////////////////

    function batchWriteOption(address[] memory _token, uint256[] memory _expiration, uint256[] memory _strikePrice, bool[] memory _isCall, uint256[] memory _contractAmount) external;
    function batchCancelOption(uint256[] memory _optionId, uint256[] memory _contractAmount) external;
    function batchWithdraw(uint256[] memory _optionId) external;
    function batchExerciseOption(uint256[] memory _optionId, uint256[] memory _contractAmount, address _referrer) external;
    function batchWithdrawPreExpiration(uint256[] memory _optionId, uint256[] memory _contractAmount) external;
}