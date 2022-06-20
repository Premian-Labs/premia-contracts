// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {OwnableInternal} from "@solidstate/contracts/access/OwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";
import {IWETH} from "@solidstate/contracts/utils/IWETH.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {PremiaMakerStorage} from "./PremiaMakerStorage.sol";
import {IPremiaMaker} from "./interfaces/IPremiaMaker.sol";
import {IPoolIO} from "./pool/IPoolIO.sol";
import {IPremiaStaking} from "./staking/IPremiaStaking.sol";

/// @author Premia
/// @title A contract receiving all protocol fees, swapping them for premia
contract PremiaMaker is IPremiaMaker, OwnableInternal {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // The premia token
    address private immutable PREMIA;
    // The premia staking contract (xPremia)
    address private immutable PREMIA_STAKING;

    // The treasury address which will receive a portion of the protocol fees
    address private immutable TREASURY;
    // The percentage of protocol fees the treasury will get (in basis points)
    uint256 private constant TREASURY_FEE = 2e3; // 20%

    uint256 private constant INVERSE_BASIS_POINT = 1e4;

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    // @param premia The premia token
    // @param premiaStaking The premia staking contract (xPremia)
    // @param treasury The treasury address which will receive a portion of the protocol fees
    constructor(
        address premia,
        address premiaStaking,
        address treasury
    ) {
        PREMIA = premia;
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

    /// @notice Set a custom swap path for a token
    /// @param token The token
    /// @param path The swap path
    function setCustomPath(address token, address[] memory path)
        external
        onlyOwner
    {
        PremiaMakerStorage.layout().customPath[token] = path;
    }

    /// @notice Add UniswapRouters to the whitelist so that they can be used to swap tokens.
    /// @param accounts The addresses to add to the whitelist
    function addWhitelistedRouters(address[] memory accounts)
        external
        onlyOwner
    {
        PremiaMakerStorage.Layout storage l = PremiaMakerStorage.layout();

        for (uint256 i = 0; i < accounts.length; i++) {
            l.whitelistedRouters.add(accounts[i]);
        }
    }

    /// @notice Remove UniswapRouters from the whitelist so that they cannot be used to swap tokens.
    /// @param accounts The addresses to remove the whitelist
    function removeWhitelistedRouters(address[] memory accounts)
        external
        onlyOwner
    {
        PremiaMakerStorage.Layout storage l = PremiaMakerStorage.layout();

        for (uint256 i = 0; i < accounts.length; i++) {
            l.whitelistedRouters.remove(accounts[i]);
        }
    }

    //////////////////////////

    /// @notice Get a custom swap path for a token
    /// @param token The token
    /// @return The swap path
    function getCustomPath(address token)
        external
        view
        returns (address[] memory)
    {
        return PremiaMakerStorage.layout().customPath[token];
    }

    /// @notice Get the list of whitelisted routers
    /// @return The list of whitelisted routers
    function getWhitelistedRouters() external view returns (address[] memory) {
        PremiaMakerStorage.Layout storage l = PremiaMakerStorage.layout();

        uint256 length = l.whitelistedRouters.length();
        address[] memory result = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            result[i] = l.whitelistedRouters.at(i);
        }

        return result;
    }

    /// @notice Withdraw fees from pools, convert tokens into Premia, and send Premia to PremiaStaking contract
    /// @param pool Pool from which to withdraw fees
    /// @param router The UniswapRouter contract to use to perform the swap (Must be whitelisted)
    /// @param tokens The list of tokens to swap to premia
    function withdrawFeesAndConvert(
        address pool,
        address router,
        address[] memory tokens
    ) external {
        IPoolIO(pool).withdrawFees();

        for (uint256 i = 0; i < tokens.length; i++) {
            convert(router, tokens[i]);
        }
    }

    /// @notice Convert tokens into Premia, and send Premia to PremiaStaking contract
    /// @param router The UniswapRouter contract to use to perform the swap (Must be whitelisted)
    /// @param token The token to swap to premia
    function convert(address router, address token) public {
        PremiaMakerStorage.Layout storage l = PremiaMakerStorage.layout();

        require(
            l.whitelistedRouters.contains(router),
            "Router not whitelisted"
        );

        uint256 amount = IERC20(token).balanceOf(address(this));
        uint256 fee = (amount * TREASURY_FEE) / INVERSE_BASIS_POINT;
        uint256 amountMinusFee = amount - fee;

        IERC20(token).safeTransfer(TREASURY, fee);

        if (amountMinusFee == 0) return;

        IERC20(token).safeIncreaseAllowance(router, amountMinusFee);

        address nativeToken = IUniswapV2Router02(router).WETH();
        uint256 premiaAmount;

        if (token != PREMIA) {
            address[] memory path;

            if (token != nativeToken) {
                path = l.customPath[token];
                if (path.length == 0) {
                    path = new address[](3);
                    path[0] = token;
                    path[1] = nativeToken;
                    path[2] = PREMIA;
                }
            } else {
                path = new address[](2);
                path[0] = token;
                path[1] = PREMIA;
            }

            uint256[] memory amounts = IUniswapV2Router02(router)
                .swapExactTokensForTokens(
                    amountMinusFee,
                    0,
                    path,
                    address(this),
                    block.timestamp
                );

            premiaAmount = amounts[amounts.length - 1];
        } else {
            premiaAmount = amountMinusFee;

            // Just for the event
            router = address(0);
        }

        if (premiaAmount > 0) {
            IERC20(PREMIA).approve(PREMIA_STAKING, premiaAmount);
            IPremiaStaking(PREMIA_STAKING).addRewards(premiaAmount);

            emit Converted(
                msg.sender,
                router,
                token,
                amountMinusFee,
                premiaAmount
            );
        }
    }
}
