// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {AddressUtils} from "@solidstate/contracts/utils/AddressUtils.sol";
import {Math} from "@solidstate/contracts/utils/Math.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC2612} from "@solidstate/contracts/token/ERC20/permit/IERC2612.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

import {IExchangeHelper} from "../interfaces/IExchangeHelper.sol";
import {IPremiaStaking} from "./IPremiaStaking.sol";
import {PremiaStakingStorage} from "./PremiaStakingStorage.sol";
import {OFT} from "../layerZero/token/oft/OFT.sol";
import {OFTCore} from "../layerZero/token/oft/OFTCore.sol";
import {IOFTCore} from "../layerZero/token/oft/IOFTCore.sol";
import {BytesLib} from "../layerZero/util/BytesLib.sol";

contract PremiaStaking is IPremiaStaking, OFT {
    using SafeERC20 for IERC20;
    using ABDKMath64x64 for int128;
    using AddressUtils for address;
    using BytesLib for bytes;

    address internal immutable PREMIA;
    address internal immutable REWARD_TOKEN;
    address internal immutable EXCHANGE_HELPER;

    int128 internal constant ONE_64x64 = 0x10000000000000000;
    int128 internal constant DECAY_RATE_64x64 = 0x487a423b63e; // 2.7e-7 -> Distribute around half of the current balance over a month
    uint256 internal constant INVERSE_BASIS_POINT = 1e4;
    uint64 internal constant MAX_PERIOD = 4 * 365 days;
    uint256 internal constant ACC_REWARD_PRECISION = 1e30;
    uint256 internal constant MAX_CONTRACT_DISCOUNT = 3000; // -30%
    uint256 internal constant WITHDRAWAL_DELAY = 10 days;

    struct UpdateArgsInternal {
        address user;
        uint256 balance;
        uint256 oldPower;
        uint256 newPower;
        uint256 reward;
        uint256 unstakeReward;
    }

    constructor(
        address lzEndpoint,
        address premia,
        address rewardToken,
        address exchangeHelper
    ) OFT(lzEndpoint) {
        PREMIA = premia;
        REWARD_TOKEN = rewardToken;
        EXCHANGE_HELPER = exchangeHelper;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal virtual override {
        if (from == address(0) || to == address(0)) return;

        revert PremiaStaking__CantTransfer();
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getRewardToken() external view returns (address) {
        return REWARD_TOKEN;
    }

    function estimateSendFee(
        uint16 dstChainId,
        bytes memory toAddress,
        uint256 amount,
        bool useZro,
        bytes memory adapterParams
    )
        public
        view
        virtual
        override(OFTCore, IOFTCore)
        returns (uint256 nativeFee, uint256 zroFee)
    {
        // Convert bytes to address
        address to;
        assembly {
            to := mload(add(toAddress, 32))
        }

        PremiaStakingStorage.UserInfo storage u = PremiaStakingStorage
            .layout()
            .userInfo[to];

        // mock the payload for send()
        bytes memory payload = abi.encode(
            PT_SEND,
            to,
            amount,
            u.stakePeriod,
            u.lockedUntil
        );

        return
            lzEndpoint.estimateFees(
                dstChainId,
                address(this),
                payload,
                useZro,
                adapterParams
            );
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
        _beforeUnstake(from, amount);

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        PremiaStakingStorage.UserInfo storage u = l.userInfo[from];

        UpdateArgsInternal memory args = _getInitialUpdateArgsInternal(
            l,
            u,
            from
        );

        bytes memory toAddress = abi.encodePacked(from);
        _debitFrom(from, dstChainId, toAddress, amount);

        args.newPower = _calculateUserPower(
            args.balance - amount + args.unstakeReward,
            u.stakePeriod
        );

        _updateUser(l, u, args);

        bytes memory payload = abi.encode(
            PT_SEND,
            toAddress,
            amount,
            u.stakePeriod,
            u.lockedUntil
        );
        _lzSend(
            dstChainId,
            payload,
            refundAddress,
            zroPaymentAddress,
            adapterParams,
            msg.value
        );

        emit SendToChain(from, dstChainId, toAddress, amount);
    }

    function _sendAck(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64,
        bytes memory payload
    ) internal virtual override {
        (
            ,
            bytes memory toAddressBytes,
            uint256 amount,
            uint64 stakePeriod,
            uint64 lockedUntil
        ) = abi.decode(payload, (uint16, bytes, uint256, uint64, uint64));

        address to = toAddressBytes.toAddress(0);

        _creditTo(to, amount, stakePeriod, lockedUntil, true);
        emit ReceiveFromChain(srcChainId, srcAddress, to, amount);
    }

    function _creditTo(
        address toAddress,
        uint256 amount,
        uint64 stakePeriod,
        uint64 creditLockedUntil,
        bool bridge
    ) internal {
        unchecked {
            _updateRewards();

            PremiaStakingStorage.Layout storage l = PremiaStakingStorage
                .layout();
            PremiaStakingStorage.UserInfo storage u = l.userInfo[toAddress];

            UpdateArgsInternal memory args = _getInitialUpdateArgsInternal(
                l,
                u,
                toAddress
            );

            uint64 lockedUntil = u.lockedUntil;

            uint64 lockLeft = uint64(
                _calculateWeightedAverage(
                    creditLockedUntil > block.timestamp
                        ? creditLockedUntil - block.timestamp
                        : 0,
                    lockedUntil > block.timestamp
                        ? lockedUntil - block.timestamp
                        : 0,
                    amount + args.unstakeReward,
                    args.balance
                )
            );

            u.lockedUntil = lockedUntil = uint64(block.timestamp) + lockLeft;

            u.stakePeriod = uint64(
                _calculateWeightedAverage(
                    stakePeriod,
                    u.stakePeriod,
                    amount + args.unstakeReward,
                    args.balance
                )
            );

            args.newPower = _calculateUserPower(
                args.balance + amount + args.unstakeReward,
                u.stakePeriod
            );

            _mint(toAddress, amount);

            _updateUser(l, u, args);

            if (bridge) {
                emit BridgeLock(toAddress, u.stakePeriod, lockedUntil);
            } else {
                emit Stake(toAddress, amount, u.stakePeriod, lockedUntil);
            }
        }
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function addRewards(uint256 amount) external {
        _updateRewards();

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        IERC20(REWARD_TOKEN).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        l.availableRewards += amount;

        emit RewardsAdded(amount);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getAvailableRewards()
        external
        view
        returns (uint256 rewards, uint256 unstakeRewards)
    {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        rewards = l.availableRewards - _getPendingRewards();
        unstakeRewards = l.availableUnstakeRewards;
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

        if (
            l.lastRewardUpdate == 0 ||
            l.totalPower == 0 ||
            l.availableRewards == 0
        ) {
            l.lastRewardUpdate = block.timestamp;
            return;
        }

        uint256 pendingRewards = _getPendingRewards();

        l.accRewardPerShare +=
            (pendingRewards * ACC_REWARD_PRECISION) /
            l.totalPower;
        l.availableRewards -= pendingRewards;
        l.lastRewardUpdate = block.timestamp;
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function stakeWithPermit(
        uint256 amount,
        uint64 period,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        IERC2612(PREMIA).permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );

        IERC20(PREMIA).safeTransferFrom(msg.sender, address(this), amount);

        _stake(msg.sender, amount, period);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function stake(uint256 amount, uint64 period) external {
        IERC20(PREMIA).safeTransferFrom(msg.sender, address(this), amount);
        _stake(msg.sender, amount, period);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function updateLock(uint64 period) external {
        if (period > MAX_PERIOD) revert PremiaStaking__ExcessiveStakePeriod();

        _updateRewards();

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        PremiaStakingStorage.UserInfo storage u = l.userInfo[msg.sender];

        uint64 oldPeriod = u.stakePeriod;

        if (period <= oldPeriod) revert PremiaStaking__PeriodTooShort();

        UpdateArgsInternal memory args = _getInitialUpdateArgsInternal(
            l,
            u,
            msg.sender
        );

        unchecked {
            uint64 lockToAdd = period - oldPeriod;
            u.lockedUntil =
                uint64(Math.max(u.lockedUntil, block.timestamp)) +
                lockToAdd;
            u.stakePeriod = period;

            args.newPower = _calculateUserPower(
                args.balance + args.unstakeReward,
                period
            );
        }

        _updateUser(l, u, args);

        emit UpdateLock(msg.sender, oldPeriod, period);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function harvestAndStake(
        IPremiaStaking.SwapArgs memory s,
        uint64 stakePeriod
    ) external {
        uint256 amountRewardToken = _harvest(msg.sender);

        if (amountRewardToken == 0) return;

        IERC20(REWARD_TOKEN).safeTransfer(EXCHANGE_HELPER, amountRewardToken);

        uint256 amountPremia = IExchangeHelper(EXCHANGE_HELPER).swapWithToken(
            REWARD_TOKEN,
            PREMIA,
            amountRewardToken,
            s.callee,
            s.allowanceTarget,
            s.data,
            s.refundAddress
        );

        if (amountPremia < s.amountOutMin)
            revert PremiaStaking__InsufficientSwapOutput();

        _stake(msg.sender, amountPremia, stakePeriod);
    }

    function _calculateWeightedAverage(
        uint256 A,
        uint256 B,
        uint256 weightA,
        uint256 weightB
    ) internal pure returns (uint256) {
        return (A * weightA + B * weightB) / (weightA + weightB);
    }

    function _stake(
        address toAddress,
        uint256 amount,
        uint64 stakePeriod
    ) internal {
        if (stakePeriod > MAX_PERIOD)
            revert PremiaStaking__ExcessiveStakePeriod();

        unchecked {
            _creditTo(
                toAddress,
                amount,
                stakePeriod,
                uint64(block.timestamp) + stakePeriod,
                false
            );
        }
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getPendingUserRewards(
        address user
    ) external view returns (uint256 reward, uint256 unstakeReward) {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        PremiaStakingStorage.UserInfo storage u = l.userInfo[user];

        uint256 accRewardPerShare = l.accRewardPerShare;
        if (l.lastRewardUpdate > 0 && l.availableRewards > 0) {
            accRewardPerShare +=
                (_getPendingRewards() * ACC_REWARD_PRECISION) /
                l.totalPower;
        }

        reward =
            u.reward +
            _calculateReward(
                accRewardPerShare,
                _calculateUserPower(_balanceOf(user), u.stakePeriod),
                u.rewardDebt
            );

        unstakeReward = _calculateReward(
            l.accUnstakeRewardPerShare,
            _calculateUserPower(_balanceOf(user), u.stakePeriod),
            u.unstakeRewardDebt
        );
    }

    function harvest() external {
        uint256 amount = _harvest(msg.sender);
        IERC20(REWARD_TOKEN).safeTransfer(msg.sender, amount);
    }

    function _harvest(address account) internal returns (uint256 amount) {
        _updateRewards();

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        PremiaStakingStorage.UserInfo storage u = l.userInfo[account];

        UpdateArgsInternal memory args = _getInitialUpdateArgsInternal(
            l,
            u,
            account
        );

        if (args.unstakeReward > 0) {
            args.newPower = _calculateUserPower(
                args.balance + args.unstakeReward,
                u.stakePeriod
            );
        } else {
            args.newPower = args.oldPower;
        }

        _updateUser(l, u, args);

        amount = u.reward;
        u.reward = 0;

        emit Harvest(account, amount);
    }

    function _updateTotalPower(
        PremiaStakingStorage.Layout storage l,
        uint256 oldUserPower,
        uint256 newUserPower
    ) internal {
        if (newUserPower > oldUserPower) {
            l.totalPower += newUserPower - oldUserPower;
        } else if (newUserPower < oldUserPower) {
            l.totalPower -= oldUserPower - newUserPower;
        }
    }

    function _beforeUnstake(address user, uint256 amount) internal virtual {}

    /**
     * @inheritdoc IPremiaStaking
     */
    function earlyUnstake(uint256 amount) external {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        _startWithdraw(
            l,
            l.userInfo[msg.sender],
            amount,
            (amount * _getEarlyUnstakeFeeBPS(msg.sender)) / 1e4
        );
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getEarlyUnstakeFeeBPS(
        address user
    ) external view returns (uint256 feePercentage) {
        return _getEarlyUnstakeFeeBPS(user);
    }

    function _getEarlyUnstakeFeeBPS(
        address user
    ) internal view returns (uint256 feePercentageBPS) {
        uint256 lockedUntil = PremiaStakingStorage
            .layout()
            .userInfo[user]
            .lockedUntil;

        if (lockedUntil <= block.timestamp)
            revert PremiaStaking__StakeNotLocked();

        uint256 lockLeft;

        unchecked {
            lockLeft = lockedUntil - block.timestamp;
        }

        feePercentageBPS = (lockLeft * 2500) / 365 days; // 25% fee per year left
        if (feePercentageBPS > 7500) {
            feePercentageBPS = 7500; // Capped at 75%
        }
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function startWithdraw(uint256 amount) external {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        PremiaStakingStorage.UserInfo storage u = l.userInfo[msg.sender];

        if (u.lockedUntil > block.timestamp)
            revert PremiaStaking__StakeLocked();

        _startWithdraw(l, u, amount, 0);
    }

    function _startWithdraw(
        PremiaStakingStorage.Layout storage l,
        PremiaStakingStorage.UserInfo storage u,
        uint256 amount,
        uint256 fee
    ) internal {
        if (_getAvailablePremiaAmount() < amount - fee)
            revert PremiaStaking__NotEnoughLiquidity();

        _updateRewards();
        _beforeUnstake(msg.sender, amount);

        UpdateArgsInternal memory args = _getInitialUpdateArgsInternal(
            l,
            u,
            msg.sender
        );

        _burn(msg.sender, amount);
        l.pendingWithdrawal += amount - fee;

        if (fee > 0) {
            l.accUnstakeRewardPerShare +=
                (fee * ACC_REWARD_PRECISION) /
                (l.totalPower - args.oldPower); // User who early unstake doesnt collect any of the fee

            l.availableUnstakeRewards += fee;
        }

        args.newPower = _calculateUserPower(
            args.balance - amount + args.unstakeReward,
            u.stakePeriod
        );

        _updateUser(l, u, args);

        l.withdrawals[msg.sender].amount += amount - fee;
        l.withdrawals[msg.sender].startDate = block.timestamp;

        emit Unstake(msg.sender, amount, fee, block.timestamp);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function withdraw() external {
        _updateRewards();

        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        uint256 startDate = l.withdrawals[msg.sender].startDate;

        if (startDate == 0) revert PremiaStaking__NoPendingWithdrawal();

        unchecked {
            if (block.timestamp <= startDate + WITHDRAWAL_DELAY)
                revert PremiaStaking__WithdrawalStillPending();
        }

        uint256 amount = l.withdrawals[msg.sender].amount;
        l.pendingWithdrawal -= amount;
        delete l.withdrawals[msg.sender];

        IERC20(PREMIA).safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getTotalPower() external view returns (uint256) {
        return PremiaStakingStorage.layout().totalPower;
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getUserPower(address user) external view returns (uint256) {
        return
            _calculateUserPower(
                _balanceOf(user),
                PremiaStakingStorage.layout().userInfo[user].stakePeriod
            );
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getDiscountBPS(address user) external view returns (uint256) {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();

        uint256 userPower = _calculateUserPower(
            _balanceOf(user),
            l.userInfo[user].stakePeriod
        );

        // If user is a contract, we use a different formula based on % of total power owned by the contract
        if (user.isContract()) {
            // Require 50% of overall staked power for contract to have max discount
            if (userPower >= l.totalPower >> 1) {
                return MAX_CONTRACT_DISCOUNT;
            } else {
                return
                    (userPower * MAX_CONTRACT_DISCOUNT) / (l.totalPower >> 1);
            }
        }

        IPremiaStaking.StakeLevel[] memory stakeLevels = _getStakeLevels();

        uint256 length = stakeLevels.length;

        unchecked {
            for (uint256 i = 0; i < length; i++) {
                IPremiaStaking.StakeLevel memory level = stakeLevels[i];

                if (userPower < level.amount) {
                    uint256 amountPrevLevel;
                    uint256 discountPrevLevelBPS;

                    // If stake is lower, user is in this level, and we need to LERP with prev level to get discount value
                    if (i > 0) {
                        amountPrevLevel = stakeLevels[i - 1].amount;
                        discountPrevLevelBPS = stakeLevels[i - 1].discountBPS;
                    } else {
                        // If this is the first level, prev level is 0 / 0
                        amountPrevLevel = 0;
                        discountPrevLevelBPS = 0;
                    }

                    uint256 remappedDiscountBPS = level.discountBPS -
                        discountPrevLevelBPS;

                    uint256 remappedAmount = level.amount - amountPrevLevel;
                    uint256 remappedPower = userPower - amountPrevLevel;
                    uint256 levelProgressBPS = (remappedPower *
                        INVERSE_BASIS_POINT) / remappedAmount;

                    return
                        discountPrevLevelBPS +
                        ((remappedDiscountBPS * levelProgressBPS) /
                            INVERSE_BASIS_POINT);
                }
            }

            // If no match found it means user is >= max possible stake, and therefore has max discount possible
            return stakeLevels[length - 1].discountBPS;
        }
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
    function getStakePeriodMultiplierBPS(
        uint256 period
    ) external pure returns (uint256) {
        return _getStakePeriodMultiplierBPS(period);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getUserInfo(
        address user
    ) external view returns (PremiaStakingStorage.UserInfo memory) {
        return PremiaStakingStorage.layout().userInfo[user];
    }

    function getPendingWithdrawals() external view returns (uint256) {
        return PremiaStakingStorage.layout().pendingWithdrawal;
    }

    function getPendingWithdrawal(
        address user
    )
        external
        view
        returns (uint256 amount, uint256 startDate, uint256 unlockDate)
    {
        PremiaStakingStorage.Layout storage l = PremiaStakingStorage.layout();
        amount = l.withdrawals[user].amount;
        startDate = l.withdrawals[user].startDate;

        if (startDate > 0) {
            unlockDate = startDate + WITHDRAWAL_DELAY;
        }
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

        stakeLevels[0] = IPremiaStaking.StakeLevel(5000 * 1e18, 1000); // -10%
        stakeLevels[1] = IPremiaStaking.StakeLevel(50000 * 1e18, 2500); // -25%
        stakeLevels[2] = IPremiaStaking.StakeLevel(500000 * 1e18, 3500); // -35%
        stakeLevels[3] = IPremiaStaking.StakeLevel(2500000 * 1e18, 6000); // -60%
    }

    function _getStakePeriodMultiplierBPS(
        uint256 period
    ) internal pure returns (uint256) {
        uint256 oneYear = 365 days;

        if (period == 0) return 2500; // x0.25
        if (period >= 4 * oneYear) return 42500; // x4.25

        return 2500 + (period * 1e4) / oneYear; // 0.25x + 1.0x per year lockup
    }

    function _calculateUserPower(
        uint256 balance,
        uint64 stakePeriod
    ) internal pure returns (uint256) {
        return
            (balance * _getStakePeriodMultiplierBPS(stakePeriod)) /
            INVERSE_BASIS_POINT;
    }

    function _calculateReward(
        uint256 accRewardPerShare,
        uint256 power,
        uint256 rewardDebt
    ) internal pure returns (uint256) {
        return
            ((accRewardPerShare * power) / ACC_REWARD_PRECISION) - rewardDebt;
    }

    function _calculateRewards(
        PremiaStakingStorage.Layout storage l,
        PremiaStakingStorage.UserInfo storage u,
        uint256 power
    ) internal view returns (uint256 reward, uint256 unstakeReward) {
        reward = _calculateReward(l.accRewardPerShare, power, u.rewardDebt);

        unstakeReward = _calculateReward(
            l.accUnstakeRewardPerShare,
            power,
            u.unstakeRewardDebt
        );
    }

    function _creditRewards(
        PremiaStakingStorage.Layout storage l,
        PremiaStakingStorage.UserInfo storage u,
        address user,
        uint256 reward,
        uint256 unstakeReward
    ) internal {
        u.reward += reward;

        if (unstakeReward > 0) {
            l.availableUnstakeRewards -= unstakeReward;
            _mint(user, unstakeReward);
            emit EarlyUnstakeRewardCollected(user, unstakeReward);
        }
    }

    function _updateRewardDebt(
        PremiaStakingStorage.Layout storage l,
        PremiaStakingStorage.UserInfo storage u,
        uint256 power
    ) internal {
        u.rewardDebt = _calculateRewardDebt(l.accRewardPerShare, power);
        u.unstakeRewardDebt = _calculateRewardDebt(
            l.accUnstakeRewardPerShare,
            power
        );
    }

    function _getInitialUpdateArgsInternal(
        PremiaStakingStorage.Layout storage l,
        PremiaStakingStorage.UserInfo storage u,
        address user
    ) internal view returns (UpdateArgsInternal memory) {
        UpdateArgsInternal memory args;
        args.user = user;
        args.balance = _balanceOf(user);

        if (args.balance > 0) {
            args.oldPower = _calculateUserPower(args.balance, u.stakePeriod);
        }

        {
            (uint256 reward, uint256 unstakeReward) = _calculateRewards(
                l,
                u,
                args.oldPower
            );

            args.reward = reward;
            args.unstakeReward = unstakeReward;
        }

        return args;
    }

    function _calculateRewardDebt(
        uint256 accRewardPerShare,
        uint256 power
    ) internal pure returns (uint256) {
        return (power * accRewardPerShare) / ACC_REWARD_PRECISION;
    }

    function _updateUser(
        PremiaStakingStorage.Layout storage l,
        PremiaStakingStorage.UserInfo storage u,
        UpdateArgsInternal memory args
    ) internal {
        _updateRewardDebt(l, u, args.newPower);
        _creditRewards(l, u, args.user, args.reward, args.unstakeReward);
        _updateTotalPower(l, args.oldPower, args.newPower);
    }

    /**
     * @inheritdoc IPremiaStaking
     */
    function getAvailablePremiaAmount() external view returns (uint256) {
        return _getAvailablePremiaAmount();
    }

    function _getAvailablePremiaAmount() internal view returns (uint256) {
        return
            IERC20(PREMIA).balanceOf(address(this)) -
            PremiaStakingStorage.layout().pendingWithdrawal;
    }
}
