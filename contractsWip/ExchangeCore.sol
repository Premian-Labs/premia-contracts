pragma solidity >=0.6.0;

import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './util/ArrayUtils.sol';
import './util/ReentrancyGuarded.sol';

contract ExchangeCore is ReentrancyGuarded, Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  /* The token used to pay exchange fees. */
  IERC20 public exchangeToken;

  /* Cancelled / finalized orders, by hash. */
  mapping(bytes32 => bool) public cancelledOrFinalized;

  /* Orders verified by on-chain approval (alternative to ECDSA signatures so that smart contracts can place orders directly). */
  mapping(bytes32 => bool) public approvedOrders;

  /* For split fee orders, minimum required protocol maker fee, in basis points. Paid to owner (who can change it). */
  uint256 public minimumMakerProtocolFee = 0;

  /* For split fee orders, minimum required protocol taker fee, in basis points. Paid to owner (who can change it). */
  uint256 public minimumTakerProtocolFee = 0;

  /* Recipient of protocol fees. */
  address public protocolFeeRecipient;

  enum SaleSide {Buy, Sell}

  /* Inverse basis point. */
  uint256 public constant INVERSE_BASIS_POINT = 10000;

  /* An ECDSA signature. */

  struct Sig {
    /* v parameter */
    uint8 v;
    /* r parameter */
    bytes32 r;
    /* s parameter */
    bytes32 s;
  }

  /* An order on the exchange. */
  struct Order {
    /* Exchange address, intended as a versioning mechanism. */
    address exchange;
    /* Order maker address. */
    address maker;
    /* Order taker address, if specified. */
    address taker;
    /* Maker protocol fee of the order, unused for taker order. */
    uint256 makerProtocolFee;
    /* Taker protocol fee of the order, or maximum taker fee for a taker order. */
    uint256 takerProtocolFee;
    /* Order fee recipient or zero address for taker order. */
    address feeRecipient;
    /* Side (buy/sell). */
    SaleSide side;
    /* Token used to pay for the order, or the zero-address as a sentinel value for Ether. */
    address paymentToken;
    /* Token being purchased/sold in the order. */
    address saleToken;
    /* The amount of the saleToken being purchased/sold in the order. */
    uint256 saleTokenAmount;
    /* Base price of the order (in paymentTokens). */
    uint256 basePrice;
    /* Auction extra parameter - minimum bid increment for English auctions, starting/ending price difference. */
    uint256 extra;
    /* Listing timestamp. */
    uint256 listingTime;
    /* Expiration timestamp - 0 for no expiry. */
    uint256 expirationTime;
    /* Order salt, used to prevent duplicate hashes. */
    uint256 salt;
  }

  event OrderApprovedPartOne(
    bytes32 indexed hash,
    address indexed maker,
    address taker,
    uint256 makerProtocolFee,
    uint256 takerProtocolFee,
    address indexed feeRecipient,
    FeeMethod feeMethod,
    SaleSide side
  );
  event OrderApprovedPartTwo(
    bytes32 indexed hash,
    address paymentToken,
    address saleToken,
    address saleTokenAmount,
    uint256 basePrice,
    uint256 extra,
    uint256 listingTime,
    uint256 expirationTime,
    uint256 salt,
    bool orderbookInclusionDesired
  );
  event OrderCancelled(bytes32 indexed hash);
  event OrdersMatched(
    bytes32 buyHash,
    bytes32 sellHash,
    address indexed maker,
    address indexed taker,
    uint256 price,
    address indexed saleToken,
    uint256 saleTokenAmount,
    bytes32 indexed metadata
  );

  constructor(IERC20 _exchangeToken, address _protocolFeeRecipient) {
    exchangeToken = _exchangeToken;
    protocolFeeRecipient = _protocolFeeRecipient;
  }

  /**
   * @dev Change the minimum maker fee paid to the protocol (owner only)
   * @param newMinimumMakerProtocolFee New fee to set in basis points
   */
  function changeMinimumMakerProtocolFee(uint256 newMinimumMakerProtocolFee)
    public
    onlyOwner
  {
    minimumMakerProtocolFee = newMinimumMakerProtocolFee;
  }

  /**
   * @dev Change the minimum taker fee paid to the protocol (owner only)
   * @param newMinimumTakerProtocolFee New fee to set in basis points
   */
  function changeMinimumTakerProtocolFee(uint256 newMinimumTakerProtocolFee)
    public
    onlyOwner
  {
    minimumTakerProtocolFee = newMinimumTakerProtocolFee;
  }

  /**
   * @dev Change the protocol fee recipient (owner only)
   * @param newProtocolFeeRecipient New protocol fee recipient address
   */
  function changeProtocolFeeRecipient(address newProtocolFeeRecipient)
    public
    onlyOwner
  {
    protocolFeeRecipient = newProtocolFeeRecipient;
  }

  /**
   * @dev Transfer tokens
   * @param token Token to transfer
   * @param from Address to charge fees
   * @param to Address to receive fees
   * @param amount Amount of protocol tokens to charge
   */
  function transferNft(
    address token,
    address from,
    address to,
    uint256 amount
  ) internal {
    if (amount > 0) {
      require(ERC1155(token).transferFrom(from, to, amount));
    }
  }

  /**
   * @dev Transfer tokens
   * @param token Token to transfer
   * @param from Address to charge fees
   * @param to Address to receive fees
   * @param amount Amount of protocol tokens to charge
   */
  function transferTokens(
    address token,
    address from,
    address to,
    uint256 amount
  ) internal {
    if (amount > 0) {
      require(ERC20(token).transferFrom(from, to, amount));
    }
  }

  /**
   * @dev Charge a fee in protocol tokens
   * @param from Address to charge fees
   * @param to Address to receive fees
   * @param amount Amount of protocol tokens to charge
   */
  function chargeProtocolFee(
    address from,
    address to,
    uint256 amount
  ) internal {
    transferTokens(exchangeToken, from, to, amount);
  }

  /**
   * Calculate size of an order struct when tightly packed
   *
   * @param order Order to calculate size of
   * @return Size in bytes
   */
  function sizeOf(Order memory order) internal pure returns (uint256) {
    return ((0x14 * 7) + (0x20 * 9) + 4);
  }

  /**
   * @dev Hash an order, returning the canonical order hash, without the message prefix
   * @param order Order to hash
   * @return Hash of order
   */
  function hashOrder(Order memory order) internal pure returns (bytes32 hash) {
    /* Unfortunately abi.encodePacked doesn't work here, stack size constraints. */
    uint256 size = sizeOf(order);
    bytes memory array = new bytes(size);
    uint256 index;
    assembly {
      index := add(array, 0x20)
    }
    index = ArrayUtils.unsafeWriteAddress(index, order.exchange);
    index = ArrayUtils.unsafeWriteAddress(index, order.maker);
    index = ArrayUtils.unsafeWriteAddress(index, order.taker);
    index = ArrayUtils.unsafeWriteUint(index, order.makerProtocolFee);
    index = ArrayUtils.unsafeWriteUint(index, order.takerProtocolFee);
    index = ArrayUtils.unsafeWriteAddress(index, order.feeRecipient);
    index = ArrayUtils.unsafeWriteUint8(index, uint8(order.feeMethod));
    index = ArrayUtils.unsafeWriteUint8(index, uint8(order.side));
    index = ArrayUtils.unsafeWriteAddress(index, order.paymentToken);
    index = ArrayUtils.unsafeWriteAddress(index, order.saleToken);
    index = ArrayUtils.unsafeWriteUint(index, saleTokenAmount);
    index = ArrayUtils.unsafeWriteUint(index, order.basePrice);
    index = ArrayUtils.unsafeWriteUint(index, order.extra);
    index = ArrayUtils.unsafeWriteUint(index, order.listingTime);
    index = ArrayUtils.unsafeWriteUint(index, order.expirationTime);
    index = ArrayUtils.unsafeWriteUint(index, order.salt);
    assembly {
      hash := keccak256(add(array, 0x20), size)
    }
    return hash;
  }

  /**
   * @dev Hash an order, returning the hash that a client must sign, including the standard message prefix
   * @param order Order to hash
   * @return Hash of message prefix and order hash per Ethereum format
   */
  function hashToSign(Order memory order) internal pure returns (bytes32) {
    return keccak256('\x19Ethereum Signed Message:\n32', hashOrder(order));
  }

  /**
   * @dev Assert an order is valid and return its hash
   * @param order Order to validate
   * @param sig ECDSA signature
   */
  function requireValidOrder(Order memory order, Sig memory sig)
    internal
    view
    returns (bytes32)
  {
    bytes32 hash = hashToSign(order);
    require(validateOrder(hash, order, sig));
    return hash;
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
   * @dev Validate a provided previously approved / signed order, hash, and signature.
   * @param hash Order hash (already calculated, passed to avoid recalculation)
   * @param order Order to validate
   * @param sig ECDSA signature
   */
  function validateOrder(
    bytes32 hash,
    Order memory order,
    Sig memory sig
  ) internal view returns (bool) {
    /* Not done in an if-conditional to prevent unnecessary ecrecover evaluation, which seems to happen even though it should short-circuit. */

    /* Order must have not been canceled or already filled. */
    if (cancelledOrFinalized[hash]) {
      return false;
    }

    /* Order authentication. Order must be either:
        /* (a) previously approved */
    if (approvedOrders[hash]) {
      return true;
    }

    /* or (b) ECDSA-signed by maker. */
    if (ecrecover(hash, sig.v, sig.r, sig.s) == order.maker) {
      return true;
    }

    return false;
  }

  /**
   * @dev Approve an order and optionally mark it for orderbook inclusion. Must be called by the maker of the order
   * @param order Order to approve
   * @param orderbookInclusionDesired Whether orderbook providers should include the order in their orderbooks
   */
  function approveOrder(Order memory order, bool orderbookInclusionDesired)
    internal
  {
    /* CHECKS */

    /* Assert sender is authorized to approve order. */
    require(msg.sender == order.maker);

    /* Calculate order hash. */
    bytes32 hash = hashToSign(order);

    /* Assert order has not already been approved. */
    require(!approvedOrders[hash]);

    /* EFFECTS */

    /* Mark order as approved. */
    approvedOrders[hash] = true;

    /* Log approval event. Must be split in two due to Solidity stack size limitations. */
    {
      emit OrderApprovedPartOne(
        hash,
        order.exchange,
        order.maker,
        order.taker,
        order.makerProtocolFee,
        order.takerProtocolFee,
        order.feeRecipient,
        order.feeMethod,
        order.side
      );
    }
    {
      emit OrderApprovedPartTwo(
        hash,
        order.paymentToken,
        order.saleToken,
        order.saleTokenAmount,
        order.basePrice,
        order.extra,
        order.listingTime,
        order.expirationTime,
        order.salt,
        orderbookInclusionDesired
      );
    }
  }

  /**
   * @dev Cancel an order, preventing it from being matched. Must be called by the maker of the order
   * @param order Order to cancel
   * @param sig ECDSA signature
   */
  function cancelOrder(Order memory order, Sig memory sig) internal {
    /* CHECKS */

    /* Calculate order hash. */
    bytes32 hash = requireValidOrder(order, sig);

    /* Assert sender is authorized to cancel order. */
    require(msg.sender == order.maker);

    /* EFFECTS */

    /* Mark order as cancelled, preventing it from being matched. */
    cancelledOrFinalized[hash] = true;

    /* Log cancel event. */
    emit OrderCancelled(hash);
  }

  /**
   * @dev Calculate the current price of an order (convenience function)
   * @param order Order to calculate the price of
   * @return The current price of the order
   */
  function calculateCurrentPrice(Order memory order)
    internal
    view
    returns (uint256)
  {
    return order.basePrice;
  }

  /**
   * @dev Calculate the price two orders would match at, if in fact they would match (otherwise fail)
   * @param buy Buy-side order
   * @param sell Sell-side order
   * @return Match price
   */
  function calculateMatchPrice(Order memory buy, Order memory sell)
    internal
    view
    returns (uint256)
  {
    uint256 sellPrice = sell.basePrice;
    uint256 buyPrice = buy.basePrice;

    /* Require price cross. */
    require(buyPrice >= sellPrice);

    /* Maker/taker priority. */
    return sell.feeRecipient != address(0) ? sellPrice : buyPrice;
  }

  /**
   * @dev Get the NFT being transferred by each order, if in fact they would match (otherwise fail)
   * @param buy Buy-side order
   * @param sell Sell-side order
   * @return Match NFT
   */
  function getNftTransferred(Order memory buy, Order memory sell)
    internal
    view
    returns (address, uint256)
  {
    uint256 sellToken = sell.saleToken;
    uint256 buyToken = buy.saleToken;
    uint256 sellTokenAmount = sell.saleTokenAmount;
    uint256 buyTokenAmount = buy.saleTokenAmount;

    require(buyTokenAmount > 0);

    /* Require NFT cross. */
    require(buyToken >= sellToken && sellTokenAmount >= buyTokenAmount);

    return (buyToken, buyTokenAmount);
  }

  /**
   * @dev Execute all ERC20 token / Ether transfers associated with an order match (fees and buyer => seller transfer)
   * @param buy Buy-side order
   * @param sell Sell-side order
   */
  function executeFundsTransfer(Order memory buy, Order memory sell)
    internal
    returns (uint256)
  {
    /* Only payable in the special case of unwrapped Ether. */
    if (sell.paymentToken != address(0)) {
      require(msg.value == 0);
    }

    /* Calculate match price. */
    uint256 price = calculateMatchPrice(buy, sell);

    /* If paying using a token (not Ether), transfer tokens. This is done prior to fee payments to that a seller will have tokens before being charged fees. */
    if (price > 0 && sell.paymentToken != address(0)) {
      transferTokens(sell.paymentToken, buy.maker, sell.maker, price);
    }

    /* Amount that will be received by seller (for Ether). */
    uint256 receiveAmount = price;

    /* Amount that must be sent by buyer (for Ether). */
    uint256 requiredAmount = price;

    /* Determine maker/taker and charge fees accordingly. */
    if (sell.feeRecipient != address(0)) {
      /* Sell-side order is maker. */

      /* Charge maker fee to seller. */
      chargeProtocolFee(sell.maker, sell.feeRecipient, sell.makerProtocolFee);

      /* Charge taker fee to buyer. */
      chargeProtocolFee(buy.maker, sell.feeRecipient, sell.takerProtocolFee);
    } else {
      /* Buy-side order is maker. */

      /* Charge maker fee to buyer. */
      chargeProtocolFee(buy.maker, buy.feeRecipient, buy.makerProtocolFee);

      /* Charge taker fee to seller. */
      chargeProtocolFee(sell.maker, buy.feeRecipient, buy.takerProtocolFee);
    }

    if (sell.paymentToken == address(0)) {
      /* Special-case Ether, order must be matched by buyer. */
      require(msg.value >= requiredAmount);

      sell.maker.transfer(receiveAmount);
      /* Allow overshoot for variable-price auctions, refund difference. */
      uint256 diff = SafeMath.sub(msg.value, requiredAmount);

      if (diff > 0) {
        buy.maker.transfer(diff);
      }
    }

    /* This contract should never hold Ether, however, we cannot assert this, since it is impossible to prevent anyone from sending Ether e.g. with selfdestruct. */

    return price;
  }

  /**
   * @dev Execute all ERC1155 token transfers associated with an order match (seller => buyer transfer)
   * @param buy Buy-side order
   * @param sell Sell-side order
   */
  function executeNftTransfer(Order memory buy, Order memory sell)
    internal
    returns (address, uint256)
  {
    /* Calculate match price. */
    (address saleToken, uint256 saleTokenAmount) = getNftTransferred(buy, sell);

    if (saleToken != address(0)) {
      transferNft(saleToken, buy.taker, sell.taker, saleTokenAmount);
    }

    return (saleToken, saleTokenAmount);
  }

  /**
   * @dev Return whether or not two orders can be matched with each other by basic parameters (does not check order signatures / calldata or perform static calls)
   * @param buy Buy-side order
   * @param sell Sell-side order
   * @return Whether or not the two orders can be matched
   */
  function ordersCanMatch(Order memory buy, Order memory sell)
    internal
    view
    returns (bool)
  {
    return (/* Must be opposite-side. */
    (buy.side == SaleSide.Buy && sell.side == SaleSide.Sell) &&
      /* Must use same fee method. */
      (buy.feeMethod == sell.feeMethod) &&
      /* Must use same payment token. */
      (buy.paymentToken == sell.paymentToken) &&
      /* Must use same sale token. */
      (buy.saleToken == sell.saleToken) &&
      /* Must use matching sale token amount. */
      sell.saleTokenAmount >= buy.saleTokenAmount &&
      /* Must match maker/taker addresses. */
      (sell.taker == address(0) || sell.taker == buy.maker) &&
      (buy.taker == address(0) || buy.taker == sell.maker) &&
      /* One must be maker and the other must be taker (no bool XOR in Solidity). */
      ((sell.feeRecipient == address(0) && buy.feeRecipient != address(0)) ||
        (sell.feeRecipient != address(0) && buy.feeRecipient == address(0))) &&
      /* Buy-side order must be settleable. */
      canSettleOrder(buy.listingTime, buy.expirationTime) &&
      /* Sell-side order must be settleable. */
      canSettleOrder(sell.listingTime, sell.expirationTime));
  }

  /**
   * @dev Atomically match two orders, ensuring validity of the match, and execute all associated state transitions. Protected against reentrancy by a contract-global lock.
   * @param buy Buy-side order
   * @param buySig Buy-side order signature
   * @param sell Sell-side order
   * @param sellSig Sell-side order signature
   */
  function atomicMatch(
    Order memory buy,
    Sig memory buySig,
    Order memory sell,
    Sig memory sellSig,
    bytes32 metadata
  ) internal reentrancyGuard {
    /* CHECKS */

    /* Ensure buy order validity and calculate hash if necessary. */
    bytes32 buyHash;
    if (buy.maker != msg.sender) {
      buyHash = requireValidOrder(buy, buySig);
    }

    /* Ensure sell order validity and calculate hash if necessary. */
    bytes32 sellHash;
    if (sell.maker != msg.sender) {
      sellHash = requireValidOrder(sell, sellSig);
    }

    /* Must be matchable. */
    require(ordersCanMatch(buy, sell));

    /* EFFECTS */

    /* Mark previously signed or approved orders as finalized. */
    if (msg.sender != buy.maker) {
      cancelledOrFinalized[buyHash] = true;
    }
    if (msg.sender != sell.maker) {
      cancelledOrFinalized[sellHash] = true;
    }

    /* INTERACTIONS */

    /* Execute funds transfer and pay fees. */
    uint256 price = executeFundsTransfer(buy, sell);

    (address saleToken, uint256 saleTokenAmount) = executeNftTransfer(
      buy,
      sell
    );

    /* Log match event. */
    emit OrdersMatched(
      buyHash,
      sellHash,
      sell.feeRecipient != address(0) ? sell.maker : buy.maker,
      sell.feeRecipient != address(0) ? buy.maker : sell.maker,
      price,
      saleToken,
      saleTokenAmount,
      metadata
    );
  }
}
