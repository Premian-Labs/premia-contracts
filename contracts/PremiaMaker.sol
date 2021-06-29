// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {Ownable} from '@solidstate/contracts/access/Ownable.sol';
import {OwnableStorage} from '@solidstate/contracts/access/OwnableStorage.sol';
import {EnumerableSet} from '@solidstate/contracts/utils/EnumerableSet.sol';
import {IWETH} from '@solidstate/contracts/utils/IWETH.sol';

import {IUniswapV2Router02} from '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

/// @author Premia
/// @title A contract receiving all protocol fees, swapping them for premia
contract PremiaMaker is Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // UniswapRouter contracts which can be used to swap tokens
    EnumerableSet.AddressSet private _whitelistedRouters;

    // The premia token
    IERC20 public premia;
    // The premia staking contract (xPremia)
    address public premiaStaking;

    // The treasury address which will receive a portion of the protocol fees
    address public treasury;
    // The percentage of protocol fees the treasury will get (in basis points)
    uint256 public treasuryFee = 2e3; // 20%

    uint256 private constant _inverseBasisPoint = 1e4;

    // Set a custom swap path for a token
    mapping(address=>address[]) public customPath;

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
    constructor(IERC20 _premia, address _premiaStaking, address _treasury) {
        OwnableStorage.layout().owner = msg.sender;

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
        customPath[_token] = _path;
    }

    /// @notice Set a new treasury fee
    /// @param _fee New fee
    function setTreasuryFee(uint256 _fee) external onlyOwner {
        require(_fee <= _inverseBasisPoint);
        treasuryFee = _fee;
    }

    /// @notice Add UniswapRouters to the whitelist so that they can be used to swap tokens.
    /// @param _addr The addresses to add to the whitelist
    function addWhitelistedRouter(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedRouters.add(_addr[i]);
        }
    }

    /// @notice Remove UniswapRouters from the whitelist so that they cannot be used to swap tokens.
    /// @param _addr The addresses to remove the whitelist
    function removeWhitelistedRouter(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedRouters.remove(_addr[i]);
        }
    }

    //////////////////////////

    /// @notice Get the list of whitelisted routers
    /// @return The list of whitelisted routers
    function getWhitelistedRouters() external view returns(address[] memory) {
        uint256 length = _whitelistedRouters.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelistedRouters.at(i);
        }

        return result;
    }

    /// @notice Convert tokens into Premia, and send Premia to PremiaStaking contract
    /// @param _router The UniswapRouter contract to use to perform the swap (Must be whitelisted)
    /// @param _token The token to swap to premia
    function convert(IUniswapV2Router02 _router, address _token) public {
        require(_whitelistedRouters.contains(address(_router)), "Router not whitelisted");

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
                path = customPath[_token];
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
            premia.safeTransfer(premiaStaking, premiaAmount);
            // Just for the event
            _router = IUniswapV2Router02(address(0));
        }

        emit Converted(msg.sender, address(_router), _token, amountMinusFee, premiaAmount);
    }
}
