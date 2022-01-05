// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IKeeperCompatible} from "../interface/IKeeperCompatible.sol";
import {IPriceOracleGetter} from "../interface/IPriceOracleGetter.sol";
import {IPremiaOption} from "../interface/IPremiaOption.sol";

contract AutoExerciseKeeper is IKeeperCompatible {
    struct AutoExerciseOrder {
        uint256 amount;
        uint256 exercisePrice;
        uint256 strikePrice;
        uint256 expiration;
        uint256 optionId;
        address optionContract;
        address user; // address(0) = cancelled order
        address flashExerciseRouter; // address(0) = normal exercise
    }

    uint256 minTimeToExpiryBeforeExercise = 30 minutes;

    IPriceOracleGetter public priceOracle;

    // queue index => AutoExerciseOrder
    mapping(uint256 => bytes32) priceOrderQueue;
    uint256 priceOrderQueueLength = 1;

    // expiration date => queue index => AutoExerciseOrder
    mapping(uint256 => mapping(uint256 => bytes32)) expirationOrderQueues;
    // expiration date => queue index
    mapping(uint256 => uint256) expirationOrderQueueLengths;

    // bytes32 hash => AutoExerciseOrder
    mapping(bytes32 => AutoExerciseOrder) orders;

    function getHash(AutoExerciseOrder memory order)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(order));
    }

    function addPriceOrder(AutoExerciseOrder memory order) public {
        bytes32 hash = getHash(order);
        addPriceOrderHash(hash);
    }

    function addPriceOrderHash(bytes32 hash) public {
        priceOrderQueueLength += 1;
        priceOrderQueue[priceOrderQueueLength] = hash;
    }

    function addExpirationOrder(AutoExerciseOrder memory order) public {
        bytes32 hash = getHash(order);
        addExpirationOrderHash(hash, order.expiration);
    }

    function addExpirationOrderHash(bytes32 hash, uint256 expiration) public {
        expirationOrderQueueLengths[expiration] += 1;
        expirationOrderQueues[expiration][
            expirationOrderQueueLengths[expiration]
        ] = hash;
    }

    function removeOrder(AutoExerciseOrder memory order) public {
        bytes32 hash = getHash(order);
        removeOrderHash(hash);
    }

    function removeOrderHash(bytes32 hash) public {
        AutoExerciseOrder storage order = orders[hash];
        order.user = address(0);
        orders[hash] = order;
    }

    function cleanupExpiredOrders(uint256 expiration) public {
        uint256 expirationQueueLength = expirationOrderQueueLengths[expiration];

        uint256 i;
        for (i = 0; i < priceOrderQueueLength; i++) {
            bytes32 hash = priceOrderQueue[i];
            AutoExerciseOrder storage order = orders[hash];

            if (order.expiration < block.timestamp) {
                order.user = address(0);
                orders[hash] = order;
            }
        }

        for (i = 0; i < expirationQueueLength; i++) {
            bytes32 hash = expirationOrderQueues[expiration][i];
            AutoExerciseOrder storage order = orders[hash];

            if (order.expiration < block.timestamp) {
                order.user = address(0);
                orders[hash] = order;
            }
        }
    }

    function checkExercise(AutoExerciseOrder memory order)
        public
        view
        returns (bool)
    {
        IPremiaOption.OptionData memory data = IPremiaOption(
            order.optionContract
        ).optionData(order.optionId);
        uint256 assetPrice = priceOracle.getAssetPrice(data.token);

        if (data.isCall) {
            if (assetPrice >= order.exercisePrice) {
                return true;
            }
        } else if (assetPrice <= order.exercisePrice) {
            return true;
        }

        return false;
    }

    /**
     * @notice method that is simulated by the keepers to see if any work actually
     * needs to be performed. This method does does not actually need to be
     * executable, and since it is only ever simulated it can consume lots of gas.
     * @dev To ensure that it is never called, you may want to add the
     * cannotExecute modifier from KeeperBase to your implementation of this
     * method.
     * @param checkData specified in the upkeep registration so it is always the
     * same for a registered upkeep. This can easily be broken down into specific
     * arguments using `abi.decode`, so multiple upkeeps can be registered on the
     * same contract and easily differentiated by the contract.
     * @return upkeepNeeded boolean to indicate whether the keeper should call
     * performUpkeep or not.
     * @return performData bytes that the keeper should call performUpkeep with, if
     * upkeep is needed. If you would like to encode data to decode later, try
     * `abi.encode`.
     */
    function checkUpkeep(bytes calldata checkData)
        external
        view
        returns (bool upkeepNeeded, bytes memory performData)
    {
        (bool isExpirationOrder, uint256 expiration) = abi.decode(
            checkData,
            (bool, uint256)
        );
        uint256 maxQueueLength = isExpirationOrder
            ? expirationOrderQueueLengths[expiration]
            : priceOrderQueueLength;
        AutoExerciseOrder[] memory ordersToExercise = new AutoExerciseOrder[](
            maxQueueLength
        );

        if (isExpirationOrder) {
            bool isWithinTimeWindow = block.timestamp >
                (expiration - minTimeToExpiryBeforeExercise);

            if (!isWithinTimeWindow) {
                return (false, abi.encode(ordersToExercise));
            }

            uint256 queueLength = expirationOrderQueueLengths[expiration];

            for (uint256 i = 0; i < queueLength; i++) {
                bytes32 hash = expirationOrderQueues[expiration][i];
                AutoExerciseOrder memory order = orders[hash];

                if (checkExercise(order)) {
                    ordersToExercise[i] = order;
                }
            }
        } else {
            for (uint256 i = 0; i < priceOrderQueueLength; i++) {
                bytes32 hash = priceOrderQueue[i];
                AutoExerciseOrder memory order = orders[hash];

                if (checkExercise(order)) {
                    ordersToExercise[i] = order;
                }
            }
        }

        return (ordersToExercise.length > 0, abi.encode(ordersToExercise));
    }

    /**
     * @notice method that is actually executed by the keepers, via the registry.
     * The data returned by the checkUpkeep simulation will be passed into
     * this method to actually be executed.
     * @dev The input to this method should not be trusted, and the caller of the
     * method should not even be restricted to any single registry. Anyone should
     * be able call it, and the input should be validated, there is no guarantee
     * that the data passed in is the performData returned from checkUpkeep. This
     * could happen due to malicious keepers, racing keepers, or simply a state
     * change while the performUpkeep transaction is waiting for confirmation.
     * Always validate the data passed in.
     * @param performData is the data which was passed back from the checkData
     * simulation. If it is encoded, it can easily be decoded into other types by
     * calling `abi.decode`. This data should not be trusted, and should be
     * validated against the contract's current state.
     */
    function performUpkeep(bytes calldata performData) external {
        AutoExerciseOrder[] memory ordersToExercise = abi.decode(
            performData,
            (AutoExerciseOrder[])
        );

        AutoExerciseOrder memory order;
        for (uint256 i = 0; i < ordersToExercise.length; i++) {
            order = ordersToExercise[i];
            bytes32 hash = getHash(order);
            IPremiaOption optionContract = IPremiaOption(order.optionContract);

            if (order.flashExerciseRouter != address(0)) {
                uint256 maxAmountIn = order.amount * order.strikePrice;

                optionContract.flashExerciseOptionFrom(
                    order.user,
                    order.optionId,
                    order.amount,
                    IUniswapV2Router02(order.flashExerciseRouter),
                    maxAmountIn
                );
            } else {
                optionContract.exerciseOptionFrom(
                    order.user,
                    order.optionId,
                    order.amount
                );
            }

            orders[hash] = AutoExerciseOrder(
                order.amount,
                order.exercisePrice,
                order.strikePrice,
                order.expiration,
                order.optionId,
                order.optionContract,
                address(0),
                order.flashExerciseRouter
            );
        }
    }
}
