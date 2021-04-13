// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library PairStorage {
  bytes32 internal constant STORAGE_SLOT = keccak256(
    'median.contracts.storage.Pair'
  );

  struct Layout {
    address oracle;
    address pool0;
    address pool1;

    // length of accounting period, in seconds
    uint256 period;
    // number of periods in EMA window
    uint256 window;
    uint256 lasttimestamp;

    int128 oldEmaLogReturns64x64;
    int128 newEmaLogReturns64x64;
    int128 emaVarianceAnnualized64x64;

    mapping (uint256 => int128) dayToOpeningPrice64x64;
    mapping (uint256 => int128) dayToClosingPrice64x64;
    mapping (uint256 => uint256) dayToRoundId;
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
