// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {Multicall} from "@solidstate/contracts/utils/Multicall.sol";

import {IUniswapV3Factory} from "../vendor/uniswap/IUniswapV3Factory.sol";

import {ChainlinkWrapper} from "./ChainlinkWrapper.sol";
import {ChainlinkWrapperInternal} from "./ChainlinkWrapperInternal.sol";
import {ChainlinkWrapperStorage} from "./ChainlinkWrapperStorage.sol";
import {IChainlinkWrapper} from "./IChainlinkWrapper.sol";

contract ChainlinkWrapper is
    ChainlinkWrapperInternal,
    IChainlinkWrapper,
    Multicall,
    SafeOwnable
{
    using ChainlinkWrapperStorage for ChainlinkWrapperStorage.Layout;

    constructor(
        IUniswapV3Factory uniswapV3Factory,
        AggregatorV3Interface tokenOutUSDOracle,
        address tokenIn,
        address tokenOut
    )
        ChainlinkWrapperInternal(
            uniswapV3Factory,
            tokenOutUSDOracle,
            tokenIn,
            tokenOut
        )
    {}

    /// @inheritdoc IChainlinkWrapper
    function decimals() external view returns (uint8) {
        return TOKEN_OUT_USD_ORACLE.decimals();
    }

    /// @inheritdoc IChainlinkWrapper
    function latestAnswer() external view returns (int256) {
        return _quote();
    }

    /// @inheritdoc IChainlinkWrapper
    function factory() external view returns (IUniswapV3Factory) {
        return UNISWAP_V3_FACTORY;
    }

    /// @inheritdoc IChainlinkWrapper
    function oracle() external view returns (AggregatorV3Interface) {
        return TOKEN_OUT_USD_ORACLE;
    }

    /// @inheritdoc IChainlinkWrapper
    function pair() external view returns (address, address) {
        return (TOKEN_IN, TOKEN_OUT);
    }

    /// @inheritdoc IChainlinkWrapper
    function period() external view returns (uint32) {
        return ChainlinkWrapperStorage.layout().period;
    }

    /// @inheritdoc IChainlinkWrapper
    function cardinalityPerMinute() external view returns (uint8) {
        return ChainlinkWrapperStorage.layout().cardinalityPerMinute;
    }

    /// @inheritdoc IChainlinkWrapper
    function targetCardinality() external view returns (uint16) {
        return ChainlinkWrapperStorage.layout().targetCardinality;
    }

    /// @inheritdoc IChainlinkWrapper
    function supportedFeeTiers() external view returns (uint24[] memory) {
        return ChainlinkWrapperStorage.layout().feeTiers;
    }

    /// @inheritdoc IChainlinkWrapper
    function setPeriod(uint32 newPeriod) external onlyOwner {
        if (newPeriod == 0) revert ChainlinkWrapper__PeriodNotSet();

        ChainlinkWrapperStorage.Layout storage l = ChainlinkWrapperStorage
            .layout();

        l.period = newPeriod;

        l.targetCardinality =
            uint16((newPeriod * l.cardinalityPerMinute) / 60) +
            1;

        emit UpdatedPeriod(newPeriod);
    }

    /// @inheritdoc IChainlinkWrapper
    function setCardinalityPerMinute(
        uint8 newCardinalityPerMinute
    ) external onlyOwner {
        if (newCardinalityPerMinute == 0)
            revert ChainlinkWrapper__CardinalityPerMinuteNotSet();

        ChainlinkWrapperStorage.Layout storage l = ChainlinkWrapperStorage
            .layout();

        l.cardinalityPerMinute = newCardinalityPerMinute;

        l.targetCardinality =
            uint16((l.period * newCardinalityPerMinute) / 60) +
            1;

        emit UpdatedCardinalityPerMinute(newCardinalityPerMinute);
    }

    /// @inheritdoc IChainlinkWrapper
    function insertFeeTier(uint24 feeTier) external onlyOwner {
        if (UNISWAP_V3_FACTORY.feeAmountTickSpacing(feeTier) == 0)
            revert ChainlinkWrapper__InvalidFeeTier(feeTier);

        uint24[] storage feeTiers = ChainlinkWrapperStorage.layout().feeTiers;
        uint256 feeTiersLength = feeTiers.length;

        for (uint256 i; i < feeTiersLength; i++) {
            if (feeTiers[i] == feeTier)
                revert ChainlinkWrapper__FeeTierExists(feeTier);
        }

        feeTiers.push(feeTier);
    }
}
