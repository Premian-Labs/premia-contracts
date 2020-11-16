pragma solidity >=0.6.0;

import '@openzeppelin/contracts/math/SafeMath.sol';

library ISaleKind {
  /**
   * Side: buy or sell.
   */
  enum Side {Buy, Sell}

  /**
   * Currently supported kinds of sale: fixed price, Dutch auction.
   * English auctions cannot be supported without stronger escrow guarantees.
   * Future interesting options: Vickrey auction, nonlinear Dutch auctions.
   */
  enum SaleKind {FixedPrice, DutchAuction}

  /**
   * @dev Check whether the parameters of a sale are valid
   * @param saleKind Kind of sale
   * @param expirationTime Order expiration time
   * @return Whether the parameters were valid
   */
  function validateParameters(SaleKind saleKind, uint256 expirationTime)
    internal
    pure
    returns (bool)
  {
    /* Auctions must have a set expiration date. */
    return (saleKind == SaleKind.FixedPrice || expirationTime > 0);
  }

  /**
   * @dev Return whether or not an order can be settled
   * @dev Precondition: parameters have passed validateParameters
   * @param listingTime Order listing time
   * @param expirationTime Order expiration time
   */
  function canSettleOrder(uint256 listingTime, uint256 expirationTime)
    internal
    view
    returns (bool)
  {
    return (listingTime < now) && (expirationTime == 0 || now < expirationTime);
  }

  /**
   * @dev Calculate the settlement price of an order
   * @dev Precondition: parameters have passed validateParameters.
   * @param side Order side
   * @param saleKind Method of sale
   * @param basePrice Order base price
   * @param extra Order extra price data
   * @param listingTime Order listing time
   * @param expirationTime Order expiration time
   */
  function calculateFinalPrice(
    Side side,
    SaleKind saleKind,
    uint256 basePrice,
    uint256 extra,
    uint256 listingTime,
    uint256 expirationTime
  ) internal view returns (uint256 finalPrice) {
    if (saleKind == SaleKind.FixedPrice) {
      return basePrice;
    } else if (saleKind == SaleKind.DutchAuction) {
      uint256 diff = SafeMath.div(
        SafeMath.mul(extra, SafeMath.sub(now, listingTime)),
        SafeMath.sub(expirationTime, listingTime)
      );
      if (side == Side.Sell) {
        /* Sell-side - start price: basePrice. End price: basePrice - extra. */
        return SafeMath.sub(basePrice, diff);
      } else {
        /* Buy-side - start price: basePrice. End price: basePrice + extra. */
        return SafeMath.add(basePrice, diff);
      }
    }
  }
}
