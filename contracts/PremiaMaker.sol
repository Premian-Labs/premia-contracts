// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { Ownable } from '@solidstate/contracts/access/Ownable.sol';
import { OwnableInternal } from '@solidstate/contracts/access/OwnableInternal.sol';
import { EnumerableSet } from '@solidstate/contracts/utils/EnumerableSet.sol';

import { IUniswapV2Router02 } from './uniswapV2/interfaces/IUniswapV2Router02.sol';
import { IWETH } from './uniswapV2/interfaces/IWETH.sol';

import { PremiaMakerStorage } from './PremiaMakerStorage.sol';
import { IPool } from './pool/IPool.sol';

/// @author Premia
/// @title A contract receiving all protocol fees, swapping them for premia
contract PremiaMaker is OwnableInternal {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // The premia token
    address private immutable premia;
    // The premia staking contract (xPremia)
    address private immutable premiaStaking;

    // The treasury address which will receive a portion of the protocol fees
    address private immutable treasury;
    // The percentage of protocol fees the treasury will get (in basis points)
    uint256 private constant treasuryFee = 2e3; // 20%

    uint256 private constant _inverseBasisPoint = 1e4;

    ////////////
    // Events //
    ////////////

    event Converted(address indexed account, address indexed router, address indexed token, uint256 tokenAmount, uint256 premiaAmount);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    // @param _premia The premia token
    // @param _premiaStaking The premia staking contract (xPremia)
    // @param _treasury The treasury address which will receive a portion of the protocol fees
    constructor(address _premia, address _premiaStaking, address _treasury) {
        premia = _premia;
        premiaStaking = _premiaStaking;
        treasury = _treasury;
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
    function setCustomPath(address _token, address[] memory _path) external onlyOwner {
        PremiaMakerStorage.layout().customPath[_token] = _path;
    }

    /// @notice Add UniswapRouters to the whitelist so that they can be used to swap tokens.
    /// @param _addr The addresses to add to the whitelist
    function addWhitelistedRouter(address[] memory _addr) external onlyOwner {
        PremiaMakerStorage.Layout storage l = PremiaMakerStorage.layout();

        for (uint256 i=0; i < _addr.length; i++) {
            l.whitelistedRouters.add(_addr[i]);
        }
    }

    /// @notice Remove UniswapRouters from the whitelist so that they cannot be used to swap tokens.
    /// @param _addr The addresses to remove the whitelist
    function removeWhitelistedRouter(address[] memory _addr) external onlyOwner {
        PremiaMakerStorage.Layout storage l = PremiaMakerStorage.layout();

        for (uint256 i=0; i < _addr.length; i++) {
            l.whitelistedRouters.remove(_addr[i]);
        }
    }

    //////////////////////////

    /// @notice Get the list of whitelisted routers
    /// @return The list of whitelisted routers
    function getWhitelistedRouters() external view returns(address[] memory) {
        PremiaMakerStorage.Layout storage l = PremiaMakerStorage.layout();

        uint256 length = l.whitelistedRouters.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = l.whitelistedRouters.at(i);
        }

        return result;
    }

    /// @notice Withdraw fees from pools, convert tokens into Premia, and send Premia to PremiaStaking contract
    /// @param _pools List of pools from which to withdraw fees
    /// @param _router The UniswapRouter contract to use to perform the swap (Must be whitelisted)
    /// @param _tokens The list of tokens to swap to premia
    function withdrawFeesAndConvert(address[] memory _pools, IUniswapV2Router02 _router, address[] memory _tokens) public {
        for (uint256 i=0; i < _pools.length; i++) {
            IPool(_pools[i]).withdrawFees();
        }

        for (uint256 i=0; i < _tokens.length; i++) {
            convert(_router, _tokens[i]);
        }
    }

    /// @notice Convert tokens into Premia, and send Premia to PremiaStaking contract
    /// @param _router The UniswapRouter contract to use to perform the swap (Must be whitelisted)
    /// @param _token The token to swap to premia
    function convert(IUniswapV2Router02 _router, address _token) public {
        PremiaMakerStorage.Layout storage l = PremiaMakerStorage.layout();

        require(l.whitelistedRouters.contains(address(_router)), "Router not whitelisted");

        IERC20 token = IERC20(_token);

        uint256 amount = token.balanceOf(address(this));
        uint256 fee = amount * treasuryFee / _inverseBasisPoint;
        uint256 amountMinusFee = amount - fee;

        token.safeTransfer(treasury, fee);

        if (amountMinusFee == 0) return;

        token.safeIncreaseAllowance(address(_router), amountMinusFee);

        address weth = _router.WETH();
        uint256 premiaAmount;

        if (_token != address(premia)) {
            address[] memory path;

            if (_token != weth) {
                path = l.customPath[_token];
                if (path.length == 0) {
                    path = new address[](3);
                    path[0] = _token;
                    path[1] = weth;
                    path[2] = address(premia);
                }
            } else {
                path = new address[](2);
                path[0] = _token;
                path[1] = address(premia);
            }

            _router.swapExactTokensForTokens(
                amountMinusFee,
                0,
                path,
                premiaStaking,
                block.timestamp
            );
        } else {
            premiaAmount = amountMinusFee;
            IERC20(premia).safeTransfer(premiaStaking, premiaAmount);
            // Just for the event
            _router = IUniswapV2Router02(address(0));
        }

        emit Converted(msg.sender, address(_router), _token, amountMinusFee, premiaAmount);
    }
}
