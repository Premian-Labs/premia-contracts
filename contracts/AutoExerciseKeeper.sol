// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interface/IKeeperCompatible.sol";
import './interface/IPriceOracleGetter.sol';
import './interface/IPremiaOption.sol';

contract AutoExerciseKeeper is IKeeperCompatible {
    struct AutoExerciseOrder {
      uint256 exercisePrice;
      uint256 optionId;
      address optionContract;
      address user; // 0x00 = cancelled order
      bool shouldFlashExercise;
    }

    IPriceOracleGetter public priceOracle;

    // queue index => AutoExerciseOrder
    mapping(uint256 => bytes32) priceOrderQueue;
    uint256 priceOrderQueueFirst= 1;
    uint256 priceOrderQueueLast = 0;

    // expiration date => AutoExerciseOrder
    mapping(uint256 => bytes32[]) expirationOrders;
    mapping(bytes32 => AutoExerciseOrder) orders;

    function getHash(AutoExerciseOrder memory order) returns (bytes32) {
      return abi.encode(order);
    }

    function enqueuePriceOrder(AutoExerciseOrder memory order) public {
        bytes32 hash = getHash(order);
        enqueuePriceOrderHash(hash);
    }

    function enqueuePriceOrderHash(bytes32 hash) public {
        priceOrderQueueLast += 1;
        priceOrderQueue[priceOrderQueueLast] = hash;
    }

    function dequeuePriceOrder() public returns (AutoExerciseOrder memory order) {
        bytes32 hash = dequeuePriceOrderHash();
        return abi.decode(hash, AutoExerciseOrder);
    }

    function dequeuePriceOrderHash() public returns (bytes32 hash) {
        require(priceOrderQueueLast >= priceOrderQueueFirst);  // non-empty queue

        hash = priceOrderQueue[priceOrderQueueFirst];

        delete priceOrderQueue[priceOrderQueueFirst];
        priceOrderQueueFirst += 1;
    }

    function addExpirationOrder(AutoExerciseOrder memory order, uint256 expiration) public {
        bytes32 hash = getHash(order);
        addExpirationOrderHash(hash);
    }

    function addExpirationOrderHash(bytes32 hash, uint256 expiration) public {
        expirationOrders[expiration].push(hash);
    }

    function removeOrder(AutoExerciseOrder memory order) public {
        bytes32 hash = getHash(order);
        removeOrderHash(hash);
    }

    function removeOrderHash(bytes32 hash) public {
        AutoExerciseOrder storage order = orders[hash];

        order.user = 0x00;

        orders[hash] = order;
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
  function checkUpkeep(bytes calldata checkData) external view override returns (bool upkeepNeeded, bytes memory performData) {
    (bool isExpirationOrder, uint256 expiration) = abi.decode(checkData, (bool,uint256));
    AutoExerciseOrder[] memory ordersToExercise;
    
    if (isExpirationOrder) {
      for (uint256 i = expirationOrderQueueFirst; i < expirationOrderQueueLast; i++) {
        AutoExerciseOrder memory order = expirationOrderQueue[i];
        IPremiaOption.OptionData memory data = IPremiaOption(order.optionContract).optionData(order.optionId);
        
        uint256 assetPrice = priceOracle.getAssetPrice(data.token);

        if (data.isCall) {
          if (assetPrice >= order.exercisePrice) {
            ordersToExercise.push(order);
          }
        } else if (assetPrice <= order.exercisePrice) {
          ordersToExercise.push(order);
        }
      }
    } else {
      for (uint256 i = priceOrderQueueFirst; i < priceOrderQueueLast; i++) {
        AutoExerciseOrder memory order = priceOrderQueue[i];
        IPremiaOption.OptionData memory data = IPremiaOption(order.optionContract).optionData(order.optionId);
        
        uint256 assetPrice = priceOracle.getAssetPrice(data.token);

        if (data.isCall) {
          if (assetPrice >= order.exercisePrice) {
            ordersToExercise.push(order);
          }
        } else if (assetPrice <= order.exercisePrice) {
          ordersToExercise.push(order);
      }
    }

    if (ordersToExercise.length < 1) {
      upkeepNeeded = false;
      performData = abi.encode(false);
    } else {
      upkeepNeeded = true;
      performData = abi.encode(isExpirationOrder, ordersToExercise);
    }
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
  function performUpkeep(bytes calldata performData) external override {

  }
}

