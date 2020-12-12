// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';

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

    function getOptionId(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall) external view returns(uint256);
    function getOptionExpiration(uint256 _optionId) external view returns(uint256);
    function getAllTokens() external view returns(address[] memory);
    function getOptionDataBatch(uint256[] memory _optionIds) external view returns(OptionData[] memory);
    function getNbOptionWrittenBatch(address _user, uint256[] memory _optionIds) external view returns(uint256[] memory);
    function getPoolBatch(uint256[] memory _optionIds) external view returns(Pool[] memory);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    function writeOption(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall, uint256 _contractAmount) external;
    function cancelOption(uint256 _optionId, uint256 _contractAmount) external;
    function exerciseOption(uint256 _optionId, uint256 _contractAmount) external;
    function withdraw(uint256 _optionId) external;
    function withdrawPreExpiration(uint256 _optionId, uint256 _contractAmount) external;

    /////////////////////
    // Batch functions //
    /////////////////////

    function batchWriteOption(address[] memory _token, uint256[] memory _expiration, uint256[] memory _strikePrice, bool[] memory _isCall, uint256[] memory _contractAmount) external;
    function batchCancelOption(uint256[] memory _optionId, uint256[] memory _contractAmount) external;
    function batchWithdraw(uint256[] memory _optionId) external;
    function batchWithdrawPreExpiration(uint256[] memory _optionId, uint256[] memory _contractAmount) external;
}