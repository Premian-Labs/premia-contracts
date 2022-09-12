// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {OwnableInternal} from "@solidstate/contracts/access/OwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {IExchangeHelper} from "./interfaces/IExchangeHelper.sol";

import {FeeConverterStorage} from "./FeeConverterStorage.sol";
import {IFeeConverter} from "./interfaces/IFeeConverter.sol";
import {IPremiaStaking} from "./staking/IPremiaStaking.sol";

/**
 * @author Premia
 * @title A contract receiving all protocol fees, swapping them for premia
 */
contract FeeConverter is IFeeConverter, OwnableInternal {
    using SafeERC20 for IERC20;

    address private immutable EXCHANGE_HELPER;
    address private immutable USDC;
    address private immutable PREMIA_STAKING;

    // The treasury address which will receive a portion of the protocol fees
    address private immutable TREASURY;
    // The percentage of protocol fees the treasury will get (in basis points)
    uint256 private constant TREASURY_SHARE = 2e3; // 20%

    uint256 private constant INVERSE_BASIS_POINT = 1e4;

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    modifier onlyAuthorized() {
        require(
            FeeConverterStorage.layout().isAuthorized[msg.sender] == true,
            "Not authorized"
        );
        _;
    }

    constructor(
        address exchangeHelper,
        address usdc,
        address premiaStaking,
        address treasury
    ) {
        EXCHANGE_HELPER = exchangeHelper;
        USDC = usdc;
        PREMIA_STAKING = premiaStaking;
        TREASURY = treasury;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    receive() external payable {}

    ///////////
    // Admin //
    ///////////

    /**
     * @notice Set a custom swap path for a token
     * @param account The account for which to set new value
     * @param isAuthorized Whether the account is authorized or not
     */
    function setAuthorized(address account, bool isAuthorized)
        external
        onlyOwner
    {
        FeeConverterStorage.layout().isAuthorized[account] = isAuthorized;

        emit SetAuthorized(account, isAuthorized);
    }

    //////////////////////////

    function convert(
        address sourceToken,
        address callee,
        address allowanceTarget,
        bytes calldata data
    ) external onlyAuthorized {
        uint256 amount = IERC20(sourceToken).balanceOf(address(this));

        if (amount == 0) return;

        IERC20(sourceToken).safeTransfer(EXCHANGE_HELPER, amount);

        uint256 outAmount = IExchangeHelper(EXCHANGE_HELPER).swapWithToken(
            sourceToken,
            USDC,
            amount,
            callee,
            allowanceTarget,
            data,
            address(this)
        );

        uint256 treasuryAmount = (outAmount * TREASURY_SHARE) /
            INVERSE_BASIS_POINT;

        IERC20(USDC).safeTransfer(TREASURY, treasuryAmount);
        IERC20(USDC).approve(PREMIA_STAKING, outAmount - treasuryAmount);
        IPremiaStaking(PREMIA_STAKING).addRewards(outAmount - treasuryAmount);

        emit Converted(
            msg.sender,
            sourceToken,
            amount,
            outAmount,
            treasuryAmount
        );
    }
}
