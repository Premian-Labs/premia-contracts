// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {OwnableInternal} from "@solidstate/contracts/access/OwnableInternal.sol";
import {ERC20} from "@solidstate/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";

import {FeeDiscountStorage} from "./FeeDiscountStorage.sol";
import {PremiaStakingStorage} from "./PremiaStakingStorage.sol";

contract PremiaStakingUpgrade is ERC20, OwnableInternal {
    using SafeCast for uint256;

    address internal immutable PREMIA;
    uint256 internal constant INVERSE_BASIS_POINT = 1e4;

    constructor(address premia) {
        PREMIA = premia;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from == address(0) || to == address(0), "upgrade in process");
    }

    function upgrade(address[] memory users) external onlyOwner {
        FeeDiscountStorage.Layout storage oldL = FeeDiscountStorage.layout();

        if (oldL.xPremiaToPremiaRatio == 0) {
            oldL.xPremiaToPremiaRatio = _getXPremiaToPremiaRatio();
        }

        for (uint256 i = 0; i < users.length; i++) {
            _upgradeUser(users[i]);
        }
    }

    function _upgradeUser(address userAddress) internal {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        PremiaStakingStorage.UserInfo storage user = l.userInfo[userAddress];

        uint256 oldBalance = _balanceOf(userAddress);

        FeeDiscountStorage.Layout storage oldL = FeeDiscountStorage.layout();
        FeeDiscountStorage.UserInfo storage oldUser = oldL.userInfo[
            userAddress
        ];

        uint256 oldStake = oldUser.balance;
        user.lockedUntil = block.timestamp.toUint64();

        uint256 newBalance = ((oldBalance + oldStake) *
            oldL.xPremiaToPremiaRatio) / 1e18;

        delete oldL.userInfo[userAddress];

        l.totalPower += _calculateStakeAmountWithBonus(newBalance, 0);

        _burn(address(this), oldStake);
        _mint(userAddress, newBalance - oldBalance);

        // ToDo : Event ?
    }

    function _getStakePeriodMultiplier(uint256 period)
        internal
        pure
        returns (uint256)
    {
        uint256 oneYear = 365 days;

        if (period == 0) return 2500; // x0.25
        if (period >= 4 * oneYear) return 42500; // x4.25

        return 2500 + (period * 1e4) / oneYear; // 0.25x + 1.0x per year lockup
    }

    function _calculateStakeAmountWithBonus(uint256 balance, uint64 stakePeriod)
        internal
        pure
        returns (uint256)
    {
        return
            (balance * _getStakePeriodMultiplier(stakePeriod)) /
            INVERSE_BASIS_POINT;
    }

    function _getXPremiaToPremiaRatio() internal view returns (uint256) {
        return (_getAvailablePremiaAmount() * 1e18) / _totalSupply();
    }

    function _getAvailablePremiaAmount() internal view returns (uint256) {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        return
            IERC20(PREMIA).balanceOf(address(this)) -
            l.pendingWithdrawal -
            l.availableRewards;
    }
}
