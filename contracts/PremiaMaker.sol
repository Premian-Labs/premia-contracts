// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/utils/EnumerableSet.sol';

import "./interface/uniswap/IUniswapV2Router02.sol";
import "./PremiaBondingCurve.sol";

contract PremiaMaker is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Addresses with minting rights
    EnumerableSet.AddressSet private _whitelistedRouters;

    IERC20 public premia;
    PremiaBondingCurve public premiaBondingCurve;
    address public premiaStaking;

    address public treasury;
    uint256 public treasuryFee = 2e3; // 20%
    uint256 public constant INVERSE_BASIS_POINT = 1e4;

    event Converted(address indexed account, address indexed router, address indexed token, uint256 tokenAmount, uint256 premiaAmount);

    constructor(IERC20 _premia, PremiaBondingCurve _premiaBondingCurve, address _premiaStaking, address _treasury) {
        premia = _premia;
        premiaBondingCurve = _premiaBondingCurve;
        premiaStaking = _premiaStaking;
        treasury = _treasury;
    }

    ///////////
    // Admin //
    ///////////

    function setTreasuryFee(uint256 _fee) external onlyOwner {
        require(_fee <= INVERSE_BASIS_POINT);
        treasuryFee = _fee;
    }

    function addWhitelistedRouter(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedRouters.add(_addr[i]);
        }
    }

    function removeWhitelistedRouter(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedRouters.remove(_addr[i]);
        }
    }

    //////////////////////////

    function getWhitelistedRouters() external view returns(address[] memory) {
        uint256 length = _whitelistedRouters.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelistedRouters.at(i);
        }

        return result;
    }

    // Convert tokens into ETH, use ETH to purchase Premia on the bonding curve, and send Premia to PremiaStaking contract
    function convert(IUniswapV2Router02 _router, address _token) public {
        require(_whitelistedRouters.contains(address(_router)), "Router not whitelisted");

        IERC20 token = IERC20(_token);

        uint256 amount = token.balanceOf(address(this));

        uint256 fee = amount.mul(treasuryFee).div(INVERSE_BASIS_POINT);
        token.safeTransfer(treasury, fee);

        token.safeIncreaseAllowance(address(_router), amount.sub(fee));

        address[] memory path = new address[](2);
        path[0] = _token;
        path[1] = _router.WETH();

        _router.swapExactTokensForETH(
            amount,
            0,
            path,
            address(this),
            block.timestamp.add(60)
        );

        uint256 premiaAmount = premiaBondingCurve.buyTokenWithExactEthAmount{value: address(this).balance}(0, premiaStaking);

        emit Converted(msg.sender, address(_router), _token, amount.sub(fee), premiaAmount);
    }
}
