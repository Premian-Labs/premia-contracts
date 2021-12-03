// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";

import {OwnableInternal} from "@solidstate/contracts/access/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/utils/EnumerableSet.sol";
import {IWETH} from "@solidstate/contracts/utils/IWETH.sol";

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {PremiaMakerStorage} from "./PremiaMakerStorage.sol";
import {IPoolIO} from "./pool/IPoolIO.sol";

import {IPremiaMaker} from "./interface/IPremiaMaker.sol";

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

    ////////////
    // Events //
    ////////////

    event Converted(
        address indexed account,
        address indexed router,
        address indexed token,
        uint256 tokenAmount,
        uint256 premiaAmount
    );

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    // @param _premia The premia token
    // @param _premiaStaking The premia staking contract (xPremia)
    // @param _treasury The treasury address which will receive a portion of the protocol fees
    constructor(
        address _premia,
        address _premiaStaking,
        address _treasury
    ) {
        PREMIA = _premia;
        PREMIA_STAKING = _premiaStaking;
        TREASURY = _treasury;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    receive() external payable {}

    ///////////
    // Admin //
    ///////////

    /// @notice Set a custom swap path for a token
    /// @param _token The token
    /// @param _path The swap path
    function setCustomPath(address _token, address[] memory _path)
        external
        onlyOwner
    {
        PremiaMakerStorage.layout().customPath[_token] = _path;
    }

    /// @notice Add UniswapRouters to the whitelist so that they can be used to swap tokens.
    /// @param _addr The addresses to add to the whitelist
    function addWhitelistedRouter(address[] memory _addr) external onlyOwner {
        PremiaMakerStorage.Layout storage l = PremiaMakerStorage.layout();

        for (uint256 i = 0; i < _addr.length; i++) {
            l.whitelistedRouters.add(_addr[i]);
        }
    }

    /// @notice Remove UniswapRouters from the whitelist so that they cannot be used to swap tokens.
    /// @param _addr The addresses to remove the whitelist
    function removeWhitelistedRouter(address[] memory _addr)
        external
        onlyOwner
    {
        PremiaMakerStorage.Layout storage l = PremiaMakerStorage.layout();

        for (uint256 i = 0; i < _addr.length; i++) {
            l.whitelistedRouters.remove(_addr[i]);
        }
    }

    //////////////////////////

    /// @notice Get a custom swap path for a token
    /// @param _token The token
    /// @return The swap path
    function getCustomPath(address _token)
        external
        view
        override
        returns (address[] memory)
    {
        return PremiaMakerStorage.layout().customPath[_token];
    }

    /// @notice Get the list of whitelisted routers
    /// @return The list of whitelisted routers
    function getWhitelistedRouters()
        external
        view
        override
        returns (address[] memory)
    {
        PremiaMakerStorage.Layout storage l = PremiaMakerStorage.layout();

        uint256 length = l.whitelistedRouters.length();
        address[] memory result = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            result[i] = l.whitelistedRouters.at(i);
        }

        return result;
    }

    /// @notice Withdraw fees from pools, convert tokens into Premia, and send Premia to PremiaStaking contract
    /// @param _pool from which to withdraw fees
    /// @param _router The UniswapRouter contract to use to perform the swap (Must be whitelisted)
    /// @param _tokens The list of tokens to swap to premia
    function withdrawFeesAndConvert(
        address _pool,
        address _router,
        address[] memory _tokens
    ) external override {
        IPoolIO(_pool).withdrawFees();

        for (uint256 i = 0; i < _tokens.length; i++) {
            convert(_router, _tokens[i]);
        }
    }

    /// @notice Convert tokens into Premia, and send Premia to PremiaStaking contract
    /// @param _router The UniswapRouter contract to use to perform the swap (Must be whitelisted)
    /// @param _token The token to swap to premia
    function convert(address _router, address _token) public override {
        PremiaMakerStorage.Layout storage l = PremiaMakerStorage.layout();

        require(
            l.whitelistedRouters.contains(address(_router)),
            "Router not whitelisted"
        );

        IERC20 token = IERC20(_token);

        uint256 amount = token.balanceOf(address(this));
        uint256 fee = (amount * TREASURY_FEE) / INVERSE_BASIS_POINT;
        uint256 amountMinusFee = amount - fee;

        token.safeTransfer(TREASURY, fee);

        if (amountMinusFee == 0) return;

        token.safeIncreaseAllowance(_router, amountMinusFee);

        address weth = IUniswapV2Router02(_router).WETH();
        uint256 premiaAmount;

        if (_token != address(PREMIA)) {
            address[] memory path;

            if (_token != weth) {
                path = l.customPath[_token];
                if (path.length == 0) {
                    path = new address[](3);
                    path[0] = _token;
                    path[1] = weth;
                    path[2] = address(PREMIA);
                }
            } else {
                path = new address[](2);
                path[0] = _token;
                path[1] = address(PREMIA);
            }

            IUniswapV2Router02(_router).swapExactTokensForTokens(
                amountMinusFee,
                0,
                path,
                PREMIA_STAKING,
                block.timestamp
            );
        } else {
            premiaAmount = amountMinusFee;
            IERC20(PREMIA).safeTransfer(PREMIA_STAKING, premiaAmount);
            // Just for the event
            _router = address(0);
        }

        emit Converted(
            msg.sender,
            _router,
            _token,
            amountMinusFee,
            premiaAmount
        );
    }
}
