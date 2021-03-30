// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPriceConsumer {
  function getLatestPrice(address _feed) external view returns (int128);
}
