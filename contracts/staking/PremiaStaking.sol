// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@solidstate/contracts/token/ERC20/ERC20.sol";
import {IERC2612} from "@solidstate/contracts/token/ERC20/permit/IERC2612.sol";
import {ERC20Permit} from "@solidstate/contracts/token/ERC20/permit/ERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./IPremiaStaking.sol";

contract PremiaStaking is IPremiaStaking, ERC20, ERC20Permit {
    using SafeERC20 for IERC20;

    address private immutable PREMIA;

    constructor(address premia) {
        PREMIA = premia;
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function enterWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        IERC2612(PREMIA).permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );
        enter(amount);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function enter(uint256 amount) public override {
        // Gets the amount of Premia locked in the contract
        uint256 totalPremia = IERC20(PREMIA).balanceOf(address(this));
        // Gets the amount of xPremia in existence
        uint256 totalShares = totalSupply();
        // If no xPremia exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalPremia == 0) {
            _mint(msg.sender, amount);
        }
        // Calculate and mint the amount of xPremia the Premia is worth. The ratio will change overtime, as xPremia is burned/minted and Premia deposited + gained from fees / withdrawn.
        else {
            uint256 what = (amount * totalShares) / totalPremia;
            _mint(msg.sender, what);
        }
        // Lock the Premia in the contract
        IERC20(PREMIA).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function leave(uint256 amount) external override {
        // Gets the amount of xPremia in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of Premia the xPremia is worth
        uint256 what = (amount * IERC20(PREMIA).balanceOf(address(this))) /
            totalShares;
        _burn(msg.sender, amount);
        IERC20(PREMIA).safeTransfer(msg.sender, what);
    }
}
