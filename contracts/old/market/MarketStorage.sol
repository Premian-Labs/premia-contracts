// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/utils/EnumerableSet.sol';

library MarketStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256(
        'premia.contracts.storage.Market'
    );

    struct Layout {
        // FeeCalculator contract
        address feeCalculator;

        // List of whitelisted option contracts for which users can create orders
        EnumerableSet.AddressSet whitelistedOptionContracts;

        // List of whitelisted option contracts for which users can create orders
        EnumerableSet.AddressSet whitelistedPaymentTokens;

        mapping(address => uint8) paymentTokenDecimals;

        // Recipient of protocol fees
        address feeRecipient;

        // Salt to prevent duplicate hash
        uint256 salt;

        // OrderId -> Amount of options left to purchase/sell
        mapping(bytes32 => uint256) amounts;

        // Whether delayed option writing is enabled or not
        // This allow users to create a sell order for an option, without writing it, and delay the writing at the moment the order is filled
        bool isDelayedWritingEnabled;

    }

    // An order on the exchange
    struct Order {
        address maker;              // Order maker address
        SaleSide side;              // Side (buy/sell)
        bool isDelayedWriting;      // If true, option has not been written yet
        address optionContract;     // Address of optionContract from which option is from
        uint256 optionId;           // OptionId
        address paymentToken;       // Address of token used for payment
        uint256 pricePerUnit;       // Price per unit (in paymentToken) with 18 decimals
        uint256 expirationTime;     // Expiration timestamp of option (Which is also expiration of order)
        uint256 salt;               // To ensure unique hash
        uint8 decimals;             // Option token decimals
    }

    struct Option {
        address token;              // Token address
        uint256 expiration;         // Expiration timestamp of the option (Must follow expirationIncrement)
        uint256 strikePrice;        // Strike price (Must follow strikePriceIncrement of token)
        bool isCall;                // If true : Call option | If false : Put option
    }

    enum SaleSide {Buy, Sell}

    function layout () internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly { l.slot := slot }
    }
}
