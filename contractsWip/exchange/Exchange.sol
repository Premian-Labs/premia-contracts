pragma solidity >=0.6.0;

import './ExchangeCore.sol';

contract Exchange is ExchangeCore {
  /**
   * @dev Call guardedArrayReplace - library function exposed for testing.
   */
  function guardedArrayReplace(
    bytes array,
    bytes desired,
    bytes mask
  ) public pure returns (bytes) {
    ArrayUtils.guardedArrayReplace(array, desired, mask);
    return array;
  }

  /**
   * Test copy byte array
   *
   * @param arrToCopy Array to copy
   * @return byte array
   */
  function testCopy(bytes arrToCopy) public pure returns (bytes) {
    bytes memory arr = new bytes(arrToCopy.length);
    uint256 index;
    assembly {
      index := add(arr, 0x20)
    }
    ArrayUtils.unsafeWriteBytes(index, arrToCopy);
    return arr;
  }

  /**
   * Test write address to bytes
   *
   * @param addr Address to write
   * @return byte array
   */
  function testCopyAddress(address addr) public pure returns (bytes) {
    bytes memory arr = new bytes(0x14);
    uint256 index;
    assembly {
      index := add(arr, 0x20)
    }
    ArrayUtils.unsafeWriteAddress(index, addr);
    return arr;
  }

  /**
   * @dev Call hashOrder - Solidity ABI encoding limitation workaround, hopefully temporary.
   */
  function hashOrder_(
    address[6] addrs,
    uint256[9] uints,
    FeeMethod feeMethod,
    SaleSide side
  ) public pure returns (bytes32) {
    return
      hashOrder(
        Order(
          addrs[0],
          addrs[1],
          addrs[2],
          uints[0],
          uints[1],
          uints[2],
          uints[3],
          addrs[3],
          feeMethod,
          side,
          addrs[4],
          ERC20(addrs[5]),
          uints[4],
          uints[5],
          uints[6],
          uints[7],
          uints[8]
        )
      );
  }

  /**
   * @dev Call hashToSign - Solidity ABI encoding limitation workaround, hopefully temporary.
   */
  function hashToSign_(
    address[6] addrs,
    uint256[9] uints,
    FeeMethod feeMethod,
    SaleSide side
  ) public pure returns (bytes32) {
    return
      hashToSign(
        Order(
          addrs[0],
          addrs[1],
          addrs[2],
          uints[0],
          uints[1],
          uints[2],
          uints[3],
          addrs[3],
          feeMethod,
          side,
          addrs[4],
          ERC20(addrs[5]),
          uints[4],
          uints[5],
          uints[6],
          uints[7],
          uints[8]
        )
      );
  }

  /**
   * @dev Call validateOrderParameters - Solidity ABI encoding limitation workaround, hopefully temporary.
   */
  function validateOrderParameters_(
    address[6] addrs,
    uint256[9] uints,
    FeeMethod feeMethod,
    SaleSide side
  ) public view returns (bool) {
    Order memory order = Order(
      addrs[0],
      addrs[1],
      addrs[2],
      uints[0],
      uints[1],
      uints[2],
      uints[3],
      addrs[3],
      feeMethod,
      side,
      addrs[4],
      ERC20(addrs[5]),
      uints[4],
      uints[5],
      uints[6],
      uints[7],
      uints[8]
    );
    return validateOrderParameters(order);
  }

  /**
   * @dev Call validateOrder - Solidity ABI encoding limitation workaround, hopefully temporary.
   */
  function validateOrder_(
    address[6] addrs,
    uint256[9] uints,
    FeeMethod feeMethod,
    SaleSide side,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public view returns (bool) {
    Order memory order = Order(
      addrs[0],
      addrs[1],
      addrs[2],
      uints[0],
      uints[1],
      uints[2],
      uints[3],
      addrs[3],
      feeMethod,
      side,
      addrs[4],
      ERC20(addrs[5]),
      uints[4],
      uints[5],
      uints[6],
      uints[7],
      uints[8]
    );
    return validateOrder(hashToSign(order), order, Sig(v, r, s));
  }

  /**
   * @dev Call approveOrder - Solidity ABI encoding limitation workaround, hopefully temporary.
   */
  function approveOrder_(
    address[6] addrs,
    uint256[9] uints,
    FeeMethod feeMethod,
    SaleSide side,
    bool orderbookInclusionDesired
  ) public {
    Order memory order = Order(
      addrs[0],
      addrs[1],
      addrs[2],
      uints[0],
      uints[1],
      uints[2],
      uints[3],
      addrs[3],
      feeMethod,
      side,
      addrs[4],
      ERC20(addrs[5]),
      uints[4],
      uints[5],
      uints[6],
      uints[7],
      uints[8]
    );
    return approveOrder(order, orderbookInclusionDesired);
  }

  /**
   * @dev Call cancelOrder - Solidity ABI encoding limitation workaround, hopefully temporary.
   */
  function cancelOrder_(
    address[6] addrs,
    uint256[9] uints,
    FeeMethod feeMethod,
    SaleSide side,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public {
    return
      cancelOrder(
        Order(
          addrs[0],
          addrs[1],
          addrs[2],
          uints[0],
          uints[1],
          uints[2],
          uints[3],
          addrs[3],
          feeMethod,
          side,
          addrs[4],
          ERC20(addrs[5]),
          uints[4],
          uints[5],
          uints[6],
          uints[7],
          uints[8]
        ),
        Sig(v, r, s)
      );
  }

  /**
   * @dev Call calculateCurrentPrice - Solidity ABI encoding limitation workaround, hopefully temporary.
   */
  function calculateCurrentPrice_(
    address[6] addrs,
    uint256[9] uints,
    FeeMethod feeMethod,
    SaleSide side
  ) public view returns (uint256) {
    return
      calculateCurrentPrice(
        Order(
          addrs[0],
          addrs[1],
          addrs[2],
          uints[0],
          uints[1],
          uints[2],
          uints[3],
          addrs[3],
          feeMethod,
          side,
          addrs[4],
          ERC20(addrs[5]),
          uints[4],
          uints[5],
          uints[6],
          uints[7],
          uints[8]
        )
      );
  }

  /**
   * @dev Call ordersCanMatch - Solidity ABI encoding limitation workaround, hopefully temporary.
   */
  function ordersCanMatch_(
    address[14] addrs,
    uint256[18] uints,
    uint8[8] feeMethodsSidesKindsHowToCalls,
    bytes calldataBuy,
    bytes calldataSell,
    bytes replacementPatternBuy,
    bytes replacementPatternSell,
    bytes staticExtradataBuy,
    bytes staticExtradataSell
  ) public view returns (bool) {
    Order memory buy = Order(
      addrs[0],
      addrs[1],
      addrs[2],
      uints[0],
      uints[1],
      uints[2],
      uints[3],
      addrs[3],
      FeeMethod(feeMethodsSidesKindsHowToCalls[0]),
      SaleSide(feeMethodsSidesKindsHowToCalls[1]),
      addrs[4],
      ERC20(addrs[5]),
      uints[4],
      uints[5],
      uints[6],
      uints[7],
      uints[8]
    );
    Order memory sell = Order(
      addrs[7],
      addrs[8],
      addrs[9],
      uints[9],
      uints[10],
      uints[11],
      uints[12],
      addrs[10],
      FeeMethod(feeMethodsSidesKindsHowToCalls[4]),
      SaleSide(feeMethodsSidesKindsHowToCalls[5]),
      addrs[11],
      addrs[12],
      ERC20(addrs[13]),
      uints[13],
      uints[14],
      uints[15],
      uints[16],
      uints[17]
    );
    return ordersCanMatch(buy, sell);
  }

  /**
   * @dev Return whether or not two orders' calldata specifications can match
   * @param buyCalldata Buy-side order calldata
   * @param buyReplacementPattern Buy-side order calldata replacement mask
   * @param sellCalldata Sell-side order calldata
   * @param sellReplacementPattern Sell-side order calldata replacement mask
   * @return Whether the orders' calldata can be matched
   */
  function orderCalldataCanMatch(
    bytes buyCalldata,
    bytes buyReplacementPattern,
    bytes sellCalldata,
    bytes sellReplacementPattern
  ) public pure returns (bool) {
    if (buyReplacementPattern.length > 0) {
      ArrayUtils.guardedArrayReplace(
        buyCalldata,
        sellCalldata,
        buyReplacementPattern
      );
    }
    if (sellReplacementPattern.length > 0) {
      ArrayUtils.guardedArrayReplace(
        sellCalldata,
        buyCalldata,
        sellReplacementPattern
      );
    }
    return ArrayUtils.arrayEq(buyCalldata, sellCalldata);
  }

  /**
   * @dev Call calculateMatchPrice - Solidity ABI encoding limitation workaround, hopefully temporary.
   */
  function calculateMatchPrice_(
    address[14] addrs,
    uint256[18] uints,
    uint8[8] feeMethodsSidesKindsHowToCalls,
    bytes calldataBuy,
    bytes calldataSell,
    bytes replacementPatternBuy,
    bytes replacementPatternSell,
    bytes staticExtradataBuy,
    bytes staticExtradataSell
  ) public view returns (uint256) {
    Order memory buy = Order(
      addrs[0],
      addrs[1],
      addrs[2],
      uints[0],
      uints[1],
      uints[2],
      uints[3],
      addrs[3],
      FeeMethod(feeMethodsSidesKindsHowToCalls[0]),
      SaleSide(feeMethodsSidesKindsHowToCalls[1]),
      addrs[4],
      ERC20(addrs[5]),
      uints[4],
      uints[5],
      uints[6],
      uints[7],
      uints[8]
    );
    Order memory sell = Order(
      addrs[7],
      addrs[8],
      addrs[9],
      uints[9],
      uints[10],
      uints[11],
      uints[12],
      addrs[10],
      FeeMethod(feeMethodsSidesKindsHowToCalls[4]),
      SaleSide(feeMethodsSidesKindsHowToCalls[5]),
      SaleKindInterface.SaleKind(feeMethodsSidesKindsHowToCalls[6]),
      addrs[11],
      addrs[12],
      ERC20(addrs[13]),
      uints[13],
      uints[14],
      uints[15],
      uints[16],
      uints[17]
    );
    return calculateMatchPrice(buy, sell);
  }

  /**
   * @dev Call atomicMatch - Solidity ABI encoding limitation workaround, hopefully temporary.
   */
  function atomicMatch_(
    address[14] addrs,
    uint256[18] uints,
    uint8[8] feeMethodsSidesKindsHowToCalls,
    bytes calldataBuy,
    bytes calldataSell,
    bytes replacementPatternBuy,
    bytes replacementPatternSell,
    bytes staticExtradataBuy,
    bytes staticExtradataSell,
    uint8[2] vs,
    bytes32[5] rssMetadata
  ) public payable {
    return
      atomicMatch(
        Order(
          addrs[0],
          addrs[1],
          addrs[2],
          uints[0],
          uints[1],
          uints[2],
          uints[3],
          addrs[3],
          FeeMethod(feeMethodsSidesKindsHowToCalls[0]),
          SaleSide(feeMethodsSidesKindsHowToCalls[1]),
          SaleKindInterface.SaleKind(feeMethodsSidesKindsHowToCalls[2]),
          addrs[4],
          addrs[5],
          ERC20(addrs[5]),
          uints[4],
          uints[5],
          uints[6],
          uints[7],
          uints[8]
        ),
        Sig(vs[0], rssMetadata[0], rssMetadata[1]),
        Order(
          addrs[7],
          addrs[8],
          addrs[9],
          uints[9],
          uints[10],
          uints[11],
          uints[12],
          addrs[10],
          FeeMethod(feeMethodsSidesKindsHowToCalls[4]),
          SaleSide(feeMethodsSidesKindsHowToCalls[5]),
          SaleKindInterface.SaleKind(feeMethodsSidesKindsHowToCalls[6]),
          addrs[11],
          addrs[12],
          ERC20(addrs[13]),
          uints[13],
          uints[14],
          uints[15],
          uints[16],
          uints[17]
        ),
        Sig(vs[1], rssMetadata[2], rssMetadata[3]),
        rssMetadata[4]
      );
  }
}
