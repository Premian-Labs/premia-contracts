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

    constructor (
      address weth,
      address feeReceiver,
      int128 fee64x64,
      uint256 batchingPeriod
    ) Pool(weth, feeReceiver, fee64x64, batchingPeriod) {}

    function getUnderwriter (
      bool isCall
    ) external view returns(address) {
      return PoolStorage.layout().liquidityQueueAscending[isCall][address(0)];
    }

    function fixLiquidityQueue () external {
      PoolTradingCompetitionStorage.Layout storage l = PoolTradingCompetitionStorage.layout();

      require(!l.liquidityQueueFixed);

      _fixLiquidityQueue(true);
      _fixLiquidityQueue(false);

      l.liquidityQueueFixed = true;
    }

    function _fixLiquidityQueue (
      bool isCall
    ) internal {
      PoolStorage.Layout storage l = PoolStorage.layout();

      uint256 tokenId = _getFreeLiquidityTokenId(isCall);

      EnumerableSet.AddressSet storage holders = ERC1155EnumerableStorage.layout().accountsByToken[tokenId];

      for (uint i; i < holders.length(); i++) {
        l.removeUnderwriter(holders.at(i), isCall);
      }

      for (uint i; i < holders.length(); i++) {
        l.addUnderwriter(holders.at(i), isCall);
      }
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
