// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {ABDKMath64x64Token} from "@solidstate/abdk-math-extensions/contracts/ABDKMath64x64Token.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@solidstate/contracts/token/ERC20/ERC20.sol";
import {IERC2612} from "@solidstate/contracts/token/ERC20/permit/IERC2612.sol";
import {ERC20Permit} from "@solidstate/contracts/token/ERC20/permit/ERC20Permit.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

import {FeeDiscountStorage} from "./FeeDiscountStorage.sol";
import {IPremiaStaking} from "./IPremiaStaking.sol";
import {PremiaStakingStorage} from "./PremiaStakingStorage.sol";
import {OFT} from "../layerZero/token/oft/OFT.sol";

contract PremiaStaking is IPremiaStaking, OFT, ERC20Permit {
    using SafeERC20 for IERC20;
    using ABDKMath64x64 for int128;
    using SafeCast for uint256;

    address internal immutable PREMIA;

    int128 internal constant ONE_64x64 = 0x10000000000000000;
    int128 internal constant DECAY_RATE_64x64 = 0x487a423b63e; // 2.7e-7
    uint256 internal constant INVERSE_BASIS_POINT = 1e4;
    uint256 internal constant MAX_PERIOD = 4 * 365 days;
    uint256 internal constant ACC_REWARD_PRECISION = 1e12;

    constructor(address lzEndpoint, address premia) OFT(lzEndpoint) {
        PREMIA = premia;
    }

    function _send(
        address from,
        uint16 dstChainId,
        bytes memory,
        uint256 amount,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes memory adapterParams
    ) internal virtual override {
        _updateRewards();

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        uint256 underlyingAmount = (amount * _getXPremiaToPremiaRatio()) / 1e18;

        bytes memory toAddress = abi.encodePacked(from);
        _debitFrom(from, dstChainId, toAddress, amount);

        if (underlyingAmount < l.debt) {
            l.debt -= underlyingAmount;
        } else {
            l.reserved += underlyingAmount - l.debt;
            l.debt = 0;
        }

        bytes memory payload = abi.encode(toAddress, underlyingAmount);
        _lzSend(
            dstChainId,
            payload,
            refundAddress,
            zroPaymentAddress,
            adapterParams
        );

        uint64 nonce = lzEndpoint.getOutboundNonce(dstChainId, address(this));
        emit SendToChain(from, dstChainId, toAddress, underlyingAmount, nonce);
        emit BridgedOut(from, underlyingAmount, amount);
    }

    function _creditTo(
        uint16,
        address toAddress,
        uint256 underlyingAmount
    ) internal override {
        _updateRewards();

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        uint256 totalPremia = _getStakedPremiaAmount();

        uint256 amount = _mintShares(toAddress, underlyingAmount, totalPremia);

        if (underlyingAmount < l.reserved) {
            l.reserved -= underlyingAmount;
        } else {
            l.debt += underlyingAmount - l.reserved;
            l.reserved = 0;
        }

        emit BridgedIn(toAddress, underlyingAmount, amount);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function addRewards(uint256 amount) external {
        _addRewards(amount);
    }

    function _addRewards(uint256 amount) internal {
        _updateRewards();

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        IERC20(PREMIA).safeTransferFrom(msg.sender, address(this), amount);
        l.availableRewards += amount;

        emit RewardsAdded(amount);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getAvailableRewards() external view returns (uint256) {
        return PremiaStakingStorage.layout().availableRewards;
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getPendingRewards() external view returns (uint256) {
        return _getPendingRewards();
    }

    function _getPendingRewards() internal view returns (uint256) {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        return
            l.availableRewards -
            _decay(l.availableRewards, l.lastRewardUpdate, block.timestamp);
    }

    function _updateRewards() internal {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        if (l.lastRewardUpdate == 0) {
            l.lastRewardUpdate = block.timestamp;
            return;
        }

        if (l.availableRewards == 0) return;

        l.availableRewards -= _getPendingRewards();
        l.lastRewardUpdate = block.timestamp;
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function stakeWithPermit(
        uint256 amount,
        uint256 period,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        IERC2612(address(PREMIA)).permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );
        _stake(amount, period);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function stake(uint256 amount, uint256 period) external {
        _stake(amount, period);
    }

    function _beforeStake(uint256 amount, uint256 period) internal virtual {}

    function _stake(uint256 amount, uint256 period) internal {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        require(period <= MAX_PERIOD, "Gt max period");
        PremiaStakingStorage.UserInfo storage user = l.userInfo[msg.sender];

        uint256 lockedUntil = block.timestamp + period;
        require(
            lockedUntil > user.lockedUntil,
            "Cannot add stake with lower stake period"
        );

        _updateRewards();

        uint256 balance = _balanceOf(msg.sender);
        uint256 reward = ((l.accRewardPerShare * balance) /
            ACC_REWARD_PRECISION) - user.rewardDebt;

        // ToDo : Event for reward ?

        _beforeStake(amount + reward, period);

        IERC20(PREMIA).safeTransferFrom(msg.sender, address(this), amount);

        user.rewardDebt = (balance + reward + amount) * l.accRewardPerShare;

        uint256 currentPower;
        if (balance > 0) {
            currentPower = _calculateStakeAmountWithBonus(
                balance,
                user.stakePeriod
            );
        }

        user.lockedUntil = lockedUntil.toUint64();
        user.stakePeriod = period.toUint64();

        uint256 newPower = _calculateStakeAmountWithBonus(
            balance + amount + reward,
            user.stakePeriod
        );

        _updateTotalPower(l, currentPower, newPower);

        _mint(msg.sender, amount + reward);

        // ToDo : Keep both ?
        emit Deposit(msg.sender, amount);
        emit Staked(msg.sender, amount, period, lockedUntil);
    }

    function _updateTotalPower(
        PremiaStakingStorage.Layout storage l,
        uint256 oldUserPower,
        uint256 newUserPower
    ) internal {
        if (newUserPower == oldUserPower) return;

        if (newUserPower > oldUserPower) {
            l.totalPower += newUserPower - oldUserPower;
        } else {
            l.totalPower -= oldUserPower - newUserPower;
        }
    }

    function _beforeUnstake(uint256 amount) internal virtual {}

    /**
     * @inheritdoc IPremiaStaking
     */
    function startWithdraw(uint256 amount) external {
        _updateRewards();

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        PremiaStakingStorage.UserInfo storage user = l.userInfo[msg.sender];

        require(user.lockedUntil <= block.timestamp, "Stake still locked");

        // ToDo : Upgrade user ?

        _beforeUnstake(amount);

        uint256 balance = _balanceOf(msg.sender);
        uint256 reward = ((l.accRewardPerShare * balance) /
            ACC_REWARD_PRECISION) - user.rewardDebt;

        _burn(msg.sender, amount);
        balance -= amount;

        user.rewardDebt = balance * l.accRewardPerShare;

        l.totalPower -= _calculateStakeAmountWithBonus(
            amount,
            user.stakePeriod
        );

        emit Unstaked(msg.sender, amount);

        //

        // ToDo : Omnichain logic to check there is enough Premia available on this chain

        l.withdrawals[msg.sender].amount += amount + reward;
        l.withdrawals[msg.sender].startDate = block.timestamp;

        emit StartWithdrawal(msg.sender, amount + reward, block.timestamp);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function withdraw() external {
        _updateRewards();

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        uint256 startDate = l.withdrawals[msg.sender].startDate;

        require(startDate > 0, "No pending withdrawal");
        require(
            block.timestamp > startDate + l.withdrawalDelay,
            "Withdrawal still pending"
        );

        uint256 amount = l.withdrawals[msg.sender].amount;
        delete l.withdrawals[msg.sender];

        IERC20(PREMIA).safeTransfer(msg.sender, amount);

        emit Withdrawal(msg.sender, amount);

        //
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getStakeAmountWithBonus(address user)
        external
        view
        returns (uint256)
    {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        PremiaStakingStorage.UserInfo memory userInfo = l.userInfo[msg.sender];
        return
            _calculateStakeAmountWithBonus(
                _balanceOf(user),
                userInfo.stakePeriod
            );
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getDiscount(address user) external view returns (uint256) {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        PremiaStakingStorage.UserInfo memory userInfo = l.userInfo[user];

        uint256 userBalance = _calculateStakeAmountWithBonus(
            _balanceOf(user),
            userInfo.stakePeriod
        );

        IPremiaStaking.StakeLevel[] memory stakeLevels = _getStakeLevels();

        for (uint256 i = 0; i < stakeLevels.length; i++) {
            IPremiaStaking.StakeLevel memory level = stakeLevels[i];

            if (userBalance < level.amount) {
                uint256 amountPrevLevel;
                uint256 discountPrevLevel;

                // If stake is lower, user is in this level, and we need to LERP with prev level to get discount value
                if (i > 0) {
                    amountPrevLevel = stakeLevels[i - 1].amount;
                    discountPrevLevel = stakeLevels[i - 1].discount;
                } else {
                    // If this is the first level, prev level is 0 / 0
                    amountPrevLevel = 0;
                    discountPrevLevel = 0;
                }

                uint256 remappedDiscount = level.discount - discountPrevLevel;

                uint256 remappedAmount = level.amount - amountPrevLevel;
                uint256 remappedBalance = userBalance - amountPrevLevel;
                uint256 levelProgress = (remappedBalance *
                    INVERSE_BASIS_POINT) / remappedAmount;

                return
                    discountPrevLevel +
                    ((remappedDiscount * levelProgress) / INVERSE_BASIS_POINT);
            }
        }

        // If no match found it means user is >= max possible stake, and therefore has max discount possible
        return stakeLevels[stakeLevels.length - 1].discount;
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getStakeLevels()
        external
        pure
        returns (IPremiaStaking.StakeLevel[] memory stakeLevels)
    {
        return _getStakeLevels();
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getStakePeriodMultiplier(uint256 period)
        external
        pure
        returns (uint256)
    {
        return _getStakePeriodMultiplier(period);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getUserInfo(address user)
        external
        view
        returns (PremiaStakingStorage.UserInfo memory)
    {
        return PremiaStakingStorage.layout().userInfo[user];
    }

    function _mintShares(
        address to,
        uint256 amount,
        uint256 totalPremia
    ) internal returns (uint256) {
        // Gets the amount of xPremia in existence
        uint256 totalShares = _totalSupply();
        // If no xPremia exists, mint it 1:1 to the amount put in
        if (totalShares == 0 || totalPremia == 0) {
            _mint(to, amount);
            return amount;
        }
        // Calculate and mint the amount of xPremia the Premia is worth. The ratio will change overtime, as xPremia is burned/minted and Premia deposited + gained from fees / withdrawn.
        else {
            uint256 shares = (amount * totalShares) / totalPremia;
            _mint(to, shares);
            return shares;
        }
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getWithdrawalDelay() external view returns (uint256) {
        return PremiaStakingStorage.layout().withdrawalDelay;
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function setWithdrawalDelay(uint256 delay) external {
        PremiaStakingStorage.layout().withdrawalDelay = delay;
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getDebt() external view returns (uint256) {
        return PremiaStakingStorage.layout().debt;
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getReserved() external view returns (uint256) {
        return PremiaStakingStorage.layout().reserved;
    }

    function getPendingWithdrawal(address user)
        external
        view
        returns (
            uint256 amount,
            uint256 startDate,
            uint256 unlockDate
        )
    {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        amount = l.withdrawals[user].amount;
        startDate = l.withdrawals[user].startDate;
        unlockDate = startDate + l.withdrawalDelay;
    }

    function _decay(
        uint256 pendingRewards,
        uint256 oldTimestamp,
        uint256 newTimestamp
    ) internal pure returns (uint256) {
        return
            ONE_64x64
                .sub(DECAY_RATE_64x64)
                .pow(newTimestamp - oldTimestamp)
                .mulu(pendingRewards);
    }

    function _getStakeLevels()
        internal
        pure
        returns (IPremiaStaking.StakeLevel[] memory stakeLevels)
    {
        stakeLevels = new IPremiaStaking.StakeLevel[](4);

        stakeLevels[0] = IPremiaStaking.StakeLevel(5000 * 1e18, 2500); // -25%
        stakeLevels[1] = IPremiaStaking.StakeLevel(50000 * 1e18, 5000); // -50%
        stakeLevels[2] = IPremiaStaking.StakeLevel(250000 * 1e18, 7500); // -75%
        stakeLevels[3] = IPremiaStaking.StakeLevel(500000 * 1e18, 9500); // -95%
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

    /**
     * @inheritdoc IPremiaStaking
     */
    function getXPremiaToPremiaRatio() external view returns (uint256) {
        return _getXPremiaToPremiaRatio();
    }

    function _getXPremiaToPremiaRatio() internal view returns (uint256) {
        return
            ((_getStakedPremiaAmount() + _getPendingRewards()) * 1e18) /
            _totalSupply();
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getStakedPremiaAmount() external view returns (uint256) {
        return _getStakedPremiaAmount() + _getPendingRewards();
    }

    function _getStakedPremiaAmount() internal view returns (uint256) {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        return _getAvailablePremiaAmount() - l.reserved + l.debt;
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getAvailablePremiaAmount() external view returns (uint256) {
        return _getAvailablePremiaAmount();
    }

    function _getAvailablePremiaAmount() internal view returns (uint256) {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        return
            IERC20(PREMIA).balanceOf(address(this)) -
            l.pendingWithdrawal -
            l.availableRewards;
    }
}
