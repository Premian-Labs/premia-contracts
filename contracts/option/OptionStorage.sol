// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library OptionStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256(
        'premia.contracts.storage.Option'
    );

    struct Layout {
        // Used as the URI for all token types by relying on ID substitution, e.g. https://token-cdn-domain/{id}.json
        string uri;

        address denominator;
        uint8 denominatorDecimals;

        // Address receiving protocol fees (PremiaMaker)
        address feeRecipient;

        // FeeCalculator contract
        address feeCalculator;

        //////////////////////////////////////////////////

        // Whitelisted tokens for which options can be written
        mapping (address => bool) whitelistedTokens;

        //////////////////////////////////////////////////

        // The option id of next option type which will be created
        uint256 nextOptionId;

        // Max expiration time from now
        uint256 maxExpiration;

        // Uniswap routers allowed to be used for swap from flashExercise
        address[] whitelistedUniswapRouters;

        // token => expiration => strikePrice => isCall (1 for call, 0 for put) => optionId
        mapping (address => mapping(uint256 => mapping(uint256 => mapping (bool => uint256)))) options;

        // optionId => OptionData
        mapping (uint256 => OptionData) optionData;

        // optionId => Pool
        mapping (uint256 => Pool) pools;

        // account => optionId => amount of options written
        mapping (address => mapping (uint256 => uint256)) nbWritten;
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
        uint8 decimals;                 // Token decimals
        uint256 claimsPreExp;           // Amount of options from which the funds have been withdrawn pre expiration
        uint256 claimsPostExp;          // Amount of options from which the funds have been withdrawn post expiration
        uint256 exercised;              // Amount of options which have been exercised
        uint256 supply;                 // Total circulating supply
    }

    // Total write cost = collateral + fee
    struct QuoteWrite {
        address collateralToken;        // The token to deposit as collateral
        uint256 collateral;             // The amount of collateral to deposit
        uint8 collateralDecimals;       // Decimals of collateral token
        uint256 fee;                    // The amount of collateralToken needed to be paid as protocol fee
    }

    // Total exercise cost = input + fee
    struct QuoteExercise {
        address inputToken;             // Input token for exercise
        uint256 input;                  // Amount of input token to pay to exercise
        uint8 inputDecimals;            // Decimals of input token
        address outputToken;            // Output token from the exercise
        uint256 output;                 // Amount of output tokens which will be received on exercise
        uint8 outputDecimals;           // Decimals of output token
        uint256 fee;                    // The amount of inputToken needed to be paid as protocol fee
    }

    struct Pool {
        uint256 tokenAmount;            // The amount of tokens in the option pool
        uint256 denominatorAmount;      // The amounts of denominator in the option pool
    }

    function layout () internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly { l.slot := slot }
    }
}
