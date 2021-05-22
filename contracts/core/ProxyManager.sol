// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/access/OwnableInternal.sol';

import './IProxyManager.sol';
import './ProxyManagerStorage.sol';

import '../market/MarketProxy.sol';
import '../option/OptionProxy.sol';

/**
 * @title Options pair management contract
 * @dev deployed standalone and connected to Median as diamond facet
 */
contract ProxyManager is IProxyManager, OwnableInternal {
  using ProxyManagerStorage for ProxyManagerStorage.Layout;

  function getOptionImplementation() override external view returns (address) {
    return ProxyManagerStorage.layout().optionImplementation;
  }

  function getMarketImplementation() override external view returns (address) {
    return ProxyManagerStorage.layout().marketImplementation;
  }

  function deployMarket(address _feeCalculator, address _feeRecipient) external onlyOwner returns(address) {
    address market = address(new MarketProxy(msg.sender, _feeCalculator, _feeRecipient));
    ProxyManagerStorage.layout().market = market;
    return market;
  }

  function deployOption(string memory _uri, address _denominator, address _feeCalculator, address _feeRecipient) external onlyOwner returns(address) {
    address option = address(new OptionProxy(msg.sender, _uri, _denominator, _feeCalculator, _feeRecipient));
    ProxyManagerStorage.layout().options[_denominator] = option;
    return option;
  }

  function getMarket() external view returns(address) {
    return ProxyManagerStorage.layout().market;
  }

  function getOption(address _denominator) external view returns(address) {
    return ProxyManagerStorage.layout().options[_denominator];
  }
}
