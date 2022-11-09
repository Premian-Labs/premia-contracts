// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {SolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {FeeDiscountStorage} from "./FeeDiscountStorage.sol";
import {PremiaStakingStorage} from "./PremiaStakingStorage.sol";

contract PremiaStakingUpgrade is SolidStateERC20, OwnableInternal {
    using SafeCast for uint256;

    event UserUpgraded(
        address indexed user,
        uint256 oldStake,
        uint256 oldBalance,
        uint256 newBalance
    );

    event Stake(
        address indexed user,
        uint256 amount,
        uint256 stakePeriod,
        uint256 lockedUntil
    );

    address internal immutable PREMIA;
    uint256 internal constant INVERSE_BASIS_POINT = 1e4;

    constructor(address premia) {
        PREMIA = premia;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal pure override {
        require(from == address(0) || to == address(0), "upgrade in process");
    }

    function upgrade(address[] memory users) external onlyOwner {
        FeeDiscountStorage.Layout storage oldL = FeeDiscountStorage.layout();
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        if (oldL.xPremiaToPremiaRatio == 0) {
            oldL.xPremiaToPremiaRatio = _getXPremiaToPremiaRatio();
        }

        // We distribute all available PREMIA rewards, as going forward this will be stable instead of PREMIA
        if (l.availableRewards > 0) {
            l.availableRewards = 0;
        }

        for (uint256 i = 0; i < users.length; i++) {
            _upgradeUser(users[i]);
        }
    }

    function _upgradeUser(address userAddress) internal {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        // Process the pending withdrawal if there is one
        if (l.withdrawals[userAddress].startDate > 0) {
            uint256 amount = l.withdrawals[userAddress].amount;
            l.pendingWithdrawal -= amount;
            delete l.withdrawals[userAddress];

            IERC20(PREMIA).transfer(userAddress, amount);
        }

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

        if (oldBalance + oldStake == 0) return;

        l.totalPower += _calculateStakeAmountWithBonus(newBalance, 0);

        // Exception for xPremia held in the arbitrum bridge wallet
        // We burn balance from Arbitrum bridge, and credit on mainnet the amounts to users based on their balance on Arbitrum
        // -----------------------------------------
        // !!!  THIS NEEDS TO BE PROCESSED LAST !!!
        // -----------------------------------------
        if (
            userAddress == address(0xa3A7B6F88361F48403514059F1F16C8E78d60EeC)
        ) {
            _burn(userAddress, oldBalance);

            //

            address[4] memory users = [
                address(0xB351e199b63088D714dfC2E37A68c8620E33567e),
                address(0x88B38e2d7fecE2bc584eA1e75bF06448825C5182),
                address(0x5ca1ea5549E4e7CB64Ae35225E11865d2572b3F9),
                address(0xC4D7a84A49d9Deb0118363D4D02Df784d896141D)
            ];

            uint256[4] memory userBalances = [
                uint256(50000e18), // 50000
                uint256(1e18), // 1
                uint256(9e18), // 10
                uint256(3438629288748208579477) // 3438.629288748208579477
            ];

            for (uint256 i = 0; i < users.length; i++) {
                _mint(
                    users[i],
                    (userBalances[i] * oldL.xPremiaToPremiaRatio) / 1e18
                );
                emit Stake(
                    users[i],
                    (userBalances[i] * oldL.xPremiaToPremiaRatio) / 1e18,
                    0,
                    block.timestamp
                );
            }

            emit UserUpgraded(userAddress, oldStake, oldBalance, 0);
        } else {
            _burn(address(this), oldStake);
            _mint(userAddress, newBalance - oldBalance);

            // We emit this event to initialize data correctly for the subgraph
            emit Stake(userAddress, newBalance, 0, block.timestamp);

            emit UserUpgraded(userAddress, oldStake, oldBalance, newBalance);
        }
    }

    function _getStakePeriodMultiplierBPS(uint256 period)
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
            (balance * _getStakePeriodMultiplierBPS(stakePeriod)) /
            INVERSE_BASIS_POINT;
    }

    function _getXPremiaToPremiaRatio() internal view returns (uint256) {
        return (_getAvailablePremiaAmount() * 1e18) / _totalSupply();
    }

    function _getAvailablePremiaAmount() internal view returns (uint256) {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        return IERC20(PREMIA).balanceOf(address(this)) - l.pendingWithdrawal;
    }
}
