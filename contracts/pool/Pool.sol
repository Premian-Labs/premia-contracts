// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@solidstate/contracts/contracts/access/OwnableInternal.sol';
import '@solidstate/contracts/contracts/token/ERC20/ERC20.sol';
import '@solidstate/contracts/contracts/token/ERC20/IERC20.sol';
import '@solidstate/contracts/contracts/token/ERC1155/ERC1155Base.sol';

import '../pair/Pair.sol';
import './PoolStorage.sol';

/**
 * @title Openhedge option pool
 * @dev deployed standalone and referenced by PoolProxy
 */
contract Pool is OwnableInternal, ERC20, ERC1155Base {
  /**
   * @notice get address of PairProxy contract
   * @return pair address
   */
  function getPair () external view returns (address) {
    return PoolStorage.layout().pair;
  }

  /**
   * @notice get price of option contract
   * @param amount size of option contract
   * @param strikePrice option strike price
   * @param maturity timestamp of option maturity
   * @return price of option contract
   */
  function quote (
    uint amount,
    uint192 strikePrice,
    uint64 maturity
  ) public view returns (uint) {
    // TODO: calculate

    uint volatility = Pair(PoolStorage.layout().pair).getVolatility();
  }

  /**
   * @notice deposit underlying currency, underwriting puts of that currency with respect to base currency
   * @param amount quantity of underlying currency to deposit
   */
  function deposit (
    uint amount
  ) external {
    // TODO: convert ETH to WETH if applicable
    // TODO: set lockup period
    // TODO: calculate C value

    IERC20(
      PoolStorage.layout().underlying
    ).transferFrom(msg.sender, address(this), amount);

    // TODO: calculate amount minted
    uint minted;

    _mint(msg.sender, minted);
  }

  /**
   * @notice redeem pool share tokens for underlying asset
   * @param amount quantity of share tokens to redeem
   */
  function withdraw (
    uint amount
  ) external {
    // TODO: check lockup period
    // TODO: ensure available liquidity, queue if necessary

    _burn(msg.sender, amount);

    // TODO: calculate share of pool
    uint share;

    IERC20(
      PoolStorage.layout().underlying
    ).transfer(msg.sender, share);
  }

  /**
   * @notice purchase put option
   * @param amount size of option contract
   * @param strikePrice option strike price
   * @param maturity timestamp of option maturity
   */
  function purchase (
    uint amount,
    uint192 strikePrice,
    uint64 maturity
  ) external {
    // TODO: convert ETH to WETH if applicable

    IERC20(
      PoolStorage.layout().underlying
    ).transferFrom(
      msg.sender,
      address(this),
      quote(amount, strikePrice, maturity)
    );

    _mint(msg.sender, _tokenIdFor(strikePrice, maturity), amount, '');
  }

  /**
   * @notice exercise put option
   * @param amount quantity of option contract tokens to exercise
   * @param strikePrice option strike price
   * @param maturity timestamp of option maturity
   */
  function exercise (
    uint amount,
    uint192 strikePrice,
    uint64 maturity
  ) external {
    exercise(_tokenIdFor(strikePrice, maturity), amount);
  }

  /**
   * @notice exercise put option
   * @param id ERC1155 token id
   * @param amount quantity of option contract tokens to exercise
   */
  function exercise (
    uint id,
    uint amount
  ) public {
    _burn(msg.sender, id, amount);

    // TODO: send payment
  }

  /**
   * @notice calculate ERC1155 token id for given option parameters
   * @param strikePrice option strike price
   * @param maturity timestamp of option maturity
   * @return token id
   */
  function _tokenIdFor (
    uint192 strikePrice,
    uint64 maturity
  ) internal pure returns (uint) {
    return uint256(maturity) * (uint256(type(uint192).max) + 1) + strikePrice;
  }
}
