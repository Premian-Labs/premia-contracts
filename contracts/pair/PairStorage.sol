// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '../core/IPriceConsumer.sol';

library PairStorage {
  bytes32 internal constant STORAGE_SLOT = keccak256(
    'median.contracts.storage.Pair'
  );

  struct Layout {
    //addresses
    address oracle;
    address pool0;
    address pool1;
    IPriceConsumer IPrice;
    //constants
    uint256 window;
    int256 alpha;
    uint256 period;
    //time
    uint256 lasttimestamp;
    //prices
    int128 priceYesterday64x64;
    int128 priceToday64x64;
    //Rolling stats
    int128 logreturns;
    int128 emalogreturns_yesterday;
    int128 emalogreturns_today;
    int256 emavariance;
  }

  function layout () internal pure returns (Layout storage l) {
    bytes32 slot = STORAGE_SLOT;
    assembly { l.slot := slot }
  }

  function getPools (
    Layout storage l
  ) internal view returns (address, address) {
    return (l.pool0, l.pool1);
  }

  function setPools (
    Layout storage l,
    address pool0,
    address pool1
  ) internal {
    l.pool0 = pool0;
    l.pool1 = pool1;
  }
}
