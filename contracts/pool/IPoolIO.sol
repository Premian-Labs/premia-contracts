// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {IPoolInternal} from "./IPoolInternal.sol";

/**
 * @notice Pool interface for LP position and platform fee management functions
 */
interface IPoolIO {
    /**
     * @notice set timestamp after which reinvestment is disabled
     * @param timestamp timestamp to begin divestment
     * @param isCallPool whether we set divestment timestamp for the call pool or put pool
     */
    function setDivestmentTimestamp(uint64 timestamp, bool isCallPool) external;

    /**
     * @notice deposit underlying currency, underwriting calls of that currency with respect to base currency
     * @param amount quantity of underlying currency to deposit
     * @param isCallPool whether to deposit underlying in the call pool or base in the put pool
     */
    function deposit(uint256 amount, bool isCallPool) external payable;

    /**
     * @notice  swap any token to collateral asset through exchange proxy and deposit
     * @dev     any attached msg.value will be wrapped.
     *          if tokenIn is wrappedNativeToken, both msg.value and {amountInMax} amount of wrappedNativeToken will be used
     * @param s swap arguments
     * @param isCallPool whether to deposit underlying in the call pool or base in the put pool
     */
    function swapAndDeposit(
        IPoolInternal.SwapArgs memory s,
        bool isCallPool
    ) external payable;

    /**
     * @notice redeem pool share tokens for underlying asset
     * @param amount quantity of share tokens to redeem
     * @param isCallPool whether to deposit underlying in the call pool or base in the put pool
     */
    function withdraw(uint256 amount, bool isCallPool) external;

    /**
     * @notice reassign short position to new underwriter
     * @param tokenId ERC1155 token id (long or short)
     * @param contractSize quantity of option contract tokens to reassign
     * @param divest whether to withdraw freed funds after reassignment
     * @return baseCost quantity of tokens required to reassign short position
     * @return feeCost quantity of tokens required to pay fees
     * @return amountOut quantity of liquidity freed and transferred to owner
     */
    function reassign(
        uint256 tokenId,
        uint256 contractSize,
        bool divest
    ) external returns (uint256 baseCost, uint256 feeCost, uint256 amountOut);

    /**
     * @notice reassign set of short position to new underwriter
     * @param tokenIds array of ERC1155 token ids (long or short)
     * @param contractSizes array of quantities of option contract tokens to reassign
     * @param divest whether to withdraw freed funds after reassignment
     * @return baseCosts quantities of tokens required to reassign each short position
     * @return feeCosts quantities of tokens required to pay fees
     * @return amountOutCall quantity of call pool liquidity freed and transferred to owner
     * @return amountOutPut quantity of put pool liquidity freed and transferred to owner
     */
    function reassignBatch(
        uint256[] calldata tokenIds,
        uint256[] calldata contractSizes,
        bool divest
    )
        external
        returns (
            uint256[] memory baseCosts,
            uint256[] memory feeCosts,
            uint256 amountOutCall,
            uint256 amountOutPut
        );

    /**
     * @notice transfer accumulated fees to the fee receiver
     * @return amountOutCall quantity of underlying tokens transferred
     * @return amountOutPut quantity of base tokens transferred
     */
    function withdrawFees()
        external
        returns (uint256 amountOutCall, uint256 amountOutPut);

    /**
     * @notice burn corresponding long and short option tokens and withdraw collateral
     * @param tokenId ERC1155 token id (long or short)
     * @param contractSize quantity of option contract tokens to annihilate
     * @param divest whether to withdraw freed funds after annihilation
     */
    function annihilate(
        uint256 tokenId,
        uint256 contractSize,
        bool divest
    ) external;

    /**
     * @notice claim earned PREMIA emissions
     * @param isCallPool true for call, false for put
     */
    function claimRewards(bool isCallPool) external;

    /**
     * @notice claim earned PREMIA emissions on behalf of given account
     * @param account account on whose behalf to claim rewards
     * @param isCallPool true for call, false for put
     */
    function claimRewards(address account, bool isCallPool) external;

    /**
     * @notice TODO
     */
    function updateMiningPools() external;
}
