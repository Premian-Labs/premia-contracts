// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./Pool.sol";

library PoolTradingCompetitionStorage {
  bytes32 internal constant STORAGE_SLOT = keccak256(
    'premia.contracts.storage.PoolTradingCompetition'
  );

  struct Layout {
    bool liquidityQueueFixed;
  }

  function layout () internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly { l.slot := slot }
  }
}

contract PoolTradingCompetition is Pool {
    using EnumerableSet for EnumerableSet.AddressSet;
    using PoolStorage for PoolStorage.Layout;

    // 64x64 fixed point representation of 2e
    int128 private constant INITIAL_C_LEVEL_64x64 = 0x56fc2a2c515da32ea;

    constructor (
      address weth,
      address feeReceiver,
      int128 fee64x64,
      uint256 batchingPeriod
    ) Pool(weth, feeReceiver, fee64x64, batchingPeriod) {}

    function getAscending (
    bool isCall,
    address addr
    ) external view returns(address) {
        return PoolStorage.layout().liquidityQueueAscending[isCall][addr];
    }

    function getDescending (
        bool isCall,
        address addr
    ) external view returns(address) {
        return PoolStorage.layout().liquidityQueueDescending[isCall][addr];
    }

    function resetPool (int128 emaVarianceAnnualized64x64) external {
        require(
            msg.sender == 0xFBB8495A691232Cb819b84475F57e76aa9aBb6f1 ||
            msg.sender == 0x573C2AA43D3cD14501Ec116fDC83020Fd479Bb5E, 'Not admin'
        );

        PoolStorage.Layout storage l = PoolStorage.layout();
        l.emaVarianceAnnualized64x64 = emaVarianceAnnualized64x64;
        l.cLevelUnderlying64x64 = INITIAL_C_LEVEL_64x64;
        l.cLevelBase64x64 = INITIAL_C_LEVEL_64x64;
        l.emaLogReturns64x64 = 0;

        int128 newPrice64x64 = l.fetchPriceUpdate();
        if (l.getPriceUpdate(block.timestamp) == 0) {
            l.setPriceUpdate(block.timestamp, newPrice64x64);
        }

        l.updatedAt = block.timestamp;
    }

//    function fixLiquidityQueue (address[] memory wipeList) external {
//      PoolTradingCompetitionStorage.Layout storage l = PoolTradingCompetitionStorage.layout();
//
//      require(!l.liquidityQueueFixed);
//
//      _fixLiquidityQueue(true, wipeList);
//      _fixLiquidityQueue(false, wipeList);
//
//      l.liquidityQueueFixed = true;
//    }
//
//    function _fixLiquidityQueue (
//      bool isCall,
//      address[] memory wipeList
//    ) internal {
//      PoolStorage.Layout storage l = PoolStorage.layout();
//
//      uint256 tokenId = _getFreeLiquidityTokenId(isCall);
//
//      EnumerableSet.AddressSet storage holders = ERC1155EnumerableStorage.layout().accountsByToken[tokenId];
//
//      for (uint i; i < holders.length(); i++) {
//        l.removeUnderwriter(holders.at(i), isCall);
//      }
//
//      delete l.liquidityQueueAscending[isCall][address(0)];
//      delete l.liquidityQueueDescending[isCall][address(0)];
//
//      for (uint256 i; i < wipeList.length; i++) {
//        delete l.liquidityQueueAscending[isCall][wipeList[i]];
//        delete l.liquidityQueueDescending[isCall][wipeList[i]];
//      }
//
//      for (uint i; i < holders.length(); i++) {
//        l.addUnderwriter(holders.at(i), isCall);
//      }
//    }

    function getPriceUpdateAfter (
        uint timestamp
    ) external view returns (int128) {
        return PoolStorage.layout().getPriceUpdateAfter(timestamp);
    }

    function _beforeTokenTransfer (
        address operator,
        address from,
        address to,
        uint[] memory ids,
        uint[] memory amounts,
        bytes memory data
    ) override internal {
        require(from == address(0) || to == address(0), 'Transfer not allowed');
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}
