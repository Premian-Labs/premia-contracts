// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import "./interface/IPremiaOption.sol";

contract PremiaMarket is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _whitelistedOptionContracts;

    mapping(bytes32 => Order) public orders;

    /* For split fee orders, minimum required protocol maker fee, in basis points. Paid to owner (who can change it). */
    uint256 public makerFee = 1500; // 1.5%

    /* For split fee orders, minimum required protocol taker fee, in basis points. Paid to owner (who can change it). */
    uint256 public takerFee = 1500; // 1.5%

    /* Recipient of protocol fees. */
    address public treasury;

    enum SaleSide {Buy, Sell}

    /* Inverse basis point. */
    uint256 public constant INVERSE_BASIS_POINT = 1e5;

    IERC20 public weth;

    /* Salt to prevent duplicate hash. */
    uint256 salt = 0;

    /* An order on the exchange. */
    struct Order {
        /* Order maker address. */
        address maker;
        /* Order taker address, if specified. */
        address taker;
        /* Side (buy/sell). */
        SaleSide side;
        /* Address of optionContract from which option is from. */
        address optionContract;
        /* The amount of options being purchased/sold in the order. */
        uint256 optionAmount;
        /* OptionId */
        uint256 optionId;
        /* Price per unit (in WETH). */
        uint256 pricePerUnit;
        /* Expiration timestamp of option (Which is also expiration of order). */
        uint256 expirationTime;
    }

    ////////////
    // Events //
    ////////////

    event OrderCreated(
        bytes32 indexed hash,
        address indexed maker,
        address indexed optionContract,
        SaleSide side,
        address taker,
        uint256 optionId,
        uint256 optionAmount,
        uint256 pricePerUnit,
        uint256 expirationTime
    );

    event OrderFilled(
        bytes32 indexed hash,
        address indexed taker,
        address indexed optionContract,
        address maker,
        uint256 amount,
        uint256 pricePerUnit
    );

    event OrderCancelled(
        bytes32 indexed hash,
        address indexed maker,
        address indexed optionContract,
        uint256 amount,
        uint256 pricePerUnit
    );

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    constructor(address _treasury, IERC20 _weth) public {
        treasury = _treasury;
        weth = _weth;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    /**
     * @dev Set the minimum maker fee paid to the protocol (owner only)
     * @param _fee New fee to set in basis points
     */
    function setMakerFee(uint256 _fee) public onlyOwner {
        require(_fee >= 0 && _fee < 1e4); // New value cannot be > 10%
        makerFee = _fee;
    }

    /**
     * @dev Change the minimum taker fee paid to the protocol (owner only)
     * @param _fee New fee to set in basis points
     */
    function setTakerFee(uint256 _fee) public onlyOwner {
        require(_fee >= 0 && _fee < 1e4); // New value cannot be > 10%
        takerFee = _fee;
    }

    /**
     * @dev Change the protocol fee recipient (owner only)
     * @param _treasury New protocol fee recipient address
     */
    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    function addWhitelistedOptionContracts(address[] memory _addr) public onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedOptionContracts.add(_addr[i]);
        }
    }

    function removeWhitelistedOptionContracts(address[] memory _addr) public onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedOptionContracts.remove(_addr[i]);
        }
    }

    //////////
    // View //
    //////////

    function getWhitelistedOptionContracts() external view returns(address[] memory) {
        uint256 length = _whitelistedOptionContracts.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelistedOptionContracts.at(i);
        }

        return result;
    }

    function isOrderValid(bytes32 _orderId) public view returns(bool) {
        Order memory order = orders[_orderId];

        // Expired
        if (order.expirationTime == 0 || order.expirationTime > block.timestamp) return false;

        if (order.side == SaleSide.Buy) {
            uint256 basePrice = order.pricePerUnit.mul(order.optionAmount);
            uint256 orderMakerFee = basePrice.mul(makerFee).div(INVERSE_BASIS_POINT);
            uint256 totalPrice = basePrice.add(orderMakerFee);

            uint256 userBalance = weth.balanceOf(order.maker);
            uint256 allowance = weth.allowance(order.maker, address(this));

            return userBalance >= totalPrice && allowance >= totalPrice;
        } else if (order.side == SaleSide.Sell) {
            IPremiaOption premiaOption = IPremiaOption(order.optionContract);
            uint256 optionBalance = premiaOption.balanceOf(order.maker, order.optionAmount);
            bool isApproved = premiaOption.isApprovedForAll(order.maker, address(this));

            return isApproved && optionBalance >= order.optionAmount;
        }

        return false;
    }

    function areOrdersValid(bytes32[] memory _orderIds) public view returns(bool[] memory) {
        bool[] memory result = new bool[](_orderIds.length);

        for (uint256 i=0; i < _orderIds.length; i++) {
            result[i] = isOrderValid(_orderIds[i]);
        }

        return result;
    }

    //////////
    // Main //
    //////////

    function createOrder(address _taker, SaleSide _side, address _optionContract, uint256 _optionAmount, uint256 _optionId, uint256 _pricePerUnit) public {
        require(_whitelistedOptionContracts.contains(order.optionContract), "Option contract not whitelisted");


        uint256 _expiration = IPremiaOption(_optionContract).getOptionExpiration(_optionId);
        require(_expiration < block.timestamp, "Option expired");

        Order memory order = Order({
            maker: msg.sender,
            taker: _taker,
            side: _side,
            optionContract: _optionContract,
            optionAmount: _optionAmount,
            optionId: _optionId,
            pricePerUnit: _pricePerUnit,
            expirationTime: _expiration
        });

        bytes32 hash = keccak256(abi.encode(order, salt));
        salt = salt.add(1);

        orders[hash] = order;

        emit OrderCreated(
            hash,
            order.maker,
            order.optionContract,
            order.side,
            order.taker,
            order.optionId,
            order.optionAmount,
            order.pricePerUnit,
            order.expirationTime
        );
    }

    function createOrders(address[] memory _taker, SaleSide[] memory _side, address[] memory _optionContract, uint256[] memory _optionAmount, uint256[] memory _optionId, uint256[] memory _pricePerUnit) public {
        require(_taker.length == _side.length, "Arrays must have same length");
        require(_taker.length == _optionContract.length, "Arrays must have same length");
        require(_taker.length == _optionAmount.length, "Arrays must have same length");
        require(_taker.length == _optionId.length, "Arrays must have same length");
        require(_taker.length == _pricePerUnit.length, "Arrays must have same length");

        for (uint256 i=0; i < _taker.length; i++) {
            createOrder(_taker[i], _side[i], _optionContract[i], _optionAmount[i], _optionId[i], _pricePerUnit[i]);
        }
    }

    /**
     * @dev Fill an existing order
     * @param _orderId Order id
     * @param _maxAmount Max amount of options to buy/sell
     */
    function fillOrder(bytes32 _orderId, uint256 _maxAmount) public nonReentrant {
        Order storage order = orders[_orderId];
        require(order.expirationTime != 0 && order.expirationTime < block.timestamp, "Order expired");
        require(order.optionContract != address(0), "Order not found");
        require(_maxAmount > 0, "MaxAmount must be > 0");
        require(order.taker == address(0) || order.taker == msg.sender, "Not specified taker");

        uint256 amount = _maxAmount;
        if (order.optionAmount < _maxAmount) {
            amount = order.optionAmount;
        }

        require(amount > 0, "Nothing left to fill");

        order.optionAmount = order.optionAmount.sub(amount);

        uint256 basePrice = order.pricePerUnit.mul(amount);
        uint256 orderMakerFee = basePrice.mul(makerFee).div(INVERSE_BASIS_POINT);
        uint256 orderTakerFee = basePrice.mul(takerFee).div(INVERSE_BASIS_POINT);

        IPremiaOption optionContract = IPremiaOption(order.optionContract);

        if (order.side == SaleSide.Buy) {
            optionContract.safeTransferFrom(msg.sender, order.maker, order.optionId, amount, "");

            weth.transferFrom(order.maker, treasury, orderMakerFee.add(orderTakerFee));
            weth.transferFrom(order.maker, msg.sender, basePrice.sub(orderTakerFee));

        } else {
            weth.transferFrom(msg.sender, treasury, orderMakerFee.add(orderTakerFee));
            weth.transferFrom(msg.sender, order.maker, basePrice.sub(orderMakerFee));

            optionContract.safeTransferFrom(order.maker, msg.sender, order.optionId, amount, "");
        }

        if (order.optionAmount == 0) {
            delete orders[_orderId];
        } else {
            orders[_orderId].optionAmount = orders[_orderId].optionAmount.sub(amount);
        }

        emit OrderFilled(
            _orderId,
            msg.sender,
            order.optionContract,
            order.maker,
            amount,
            order.pricePerUnit
        );
    }

    /**
     * @dev Fill a list of existing orders
     * @param _orderIdList Order id list
     * @param _maxAmounts Max amount of options to buy/sell
     */
    function fillOrders(bytes32[] memory _orderIdList, uint256[] memory _maxAmounts) public {
        require(_orderIdList.length == _maxAmounts.length, "Arrays must have same length");
        for (uint256 i=0; i < _orderIdList.length; i++) {
            fillOrder(_orderIdList[i], _maxAmounts[i]);
        }
    }

    /**
     * @dev Cancel an existing order
     * @param _orderId The order id
     */
    function cancelOrder(bytes32 _orderId) public {
        Order memory order = orders[_orderId];
        require(order.optionContract != address(0), "Order not found");
        require(order.maker == msg.sender, "Not order maker");
        delete orders[_orderId];

        emit OrderCancelled(
            _orderId,
            order.maker,
            order.optionContract,
            order.optionAmount,
            order.pricePerUnit
        );
    }

    /**
     * @dev Cancel a list of existing orders
     * @param _orderIdList The list of order ids
     */
    function cancelOrders(bytes32[] memory _orderIdList) public {
        for (uint256 i=0; i < _orderIdList.length; i++) {
            cancelOrder(_orderIdList[i]);
        }
    }

}