// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import "@solidstate/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@solidstate/contracts/token/ERC20/ERC20Permit.sol";
import "@solidstate/contracts/token/ERC20/ERC20MetadataStorage.sol";

import "@solidstate/contracts/token/ERC20/IERC2612.sol";

/// @author SushiSwap
/// @notice This contract handles swapping to and from xPremia, PremiaSwap's staking token.
contract PremiaStaking is ERC20, ERC20Permit {
    using ERC20MetadataStorage for ERC20MetadataStorage.Layout;
    using SafeERC20 for IERC20;
    IERC20 public premia;

    /// @param _premia The premia token
    constructor(IERC20 _premia) {
        ERC20MetadataStorage.Layout storage l = ERC20MetadataStorage.layout();

        l.setName("PremiaStaking");
        l.setSymbol("xPremia");
        l.setDecimals(18);

        premia = _premia;
    }

    /// @notice Enter using IERC2612 permit
    /// @param _amount The amount of premia to stake
    /// @param _deadline Deadline after which permit will fail
    /// @param _v V
    /// @param _r R
    /// @param _s S
    function enterWithPermit(uint256 _amount, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) public {
        IERC2612(address(premia)).permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s);
        enter(_amount);
    }

    /// @notice Enter the staking contract. Pay some PREMIAs. Earn some shares.
    ///         Locks Premia and mints xPremia
    /// @param _amount The amount of premia to stake
    function enter(uint256 _amount) public {
        // Gets the amount of Premia locked in the contract
        uint256 totalPremia = premia.balanceOf(address(this));
        // Gets the amount of xPremia in existence
        uint256 totalShares = totalSupply();
        // If no xPremia exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalPremia == 0) {
            _mint(msg.sender, _amount);
        }
        // Calculate and mint the amount of xPremia the Premia is worth. The ratio will change overtime, as xPremia is burned/minted and Premia deposited + gained from fees / withdrawn.
        else {
            uint256 what = _amount * totalShares / totalPremia;
            _mint(msg.sender, what);
        }
        // Lock the Premia in the contract
        premia.safeTransferFrom(msg.sender, address(this), _amount);
    }

    /// @notice Leave the staking contract. Claim back your PREMIAs.
    ///         Unlocks the staked + gained Premia and burns xPremia
    /// @param _share The amount of xPremia to burn, to withdraw share of premia
    function leave(uint256 _share) public {
        // Gets the amount of xPremia in existence
        uint256 totalShares = totalSupply();
        // Calculates the amount of Premia the xPremia is worth
        uint256 what = _share * premia.balanceOf(address(this)) / totalShares;
        _burn(msg.sender, _share);
        premia.safeTransfer(msg.sender, what);
    }
}
