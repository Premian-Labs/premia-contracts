// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import "./interface/IPremiaOption.sol";

//import "hardhat/console.sol";

contract PremiaMarket is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _whitelistedOptionContracts;

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
        /* OptionId */
        uint256 optionId;
        /* Price per unit (in WETH). */
        uint256 pricePerUnit;
        /* Expiration timestamp of option (Which is also expiration of order). */
        uint256 expirationTime;
        /* To ensure unique hash */
        uint256 salt;
    }

    /* OrderId -> Amount of options left to purchase/sell */
    mapping(bytes32 => uint256) public amounts;

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
        uint256 pricePerUnit,
        uint256 expirationTime,
        uint256 salt,
        uint256 amount
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

    function getBlockTimestamp() public view returns(uint256) {
        return block.timestamp;
    }

    function getWhitelistedOptionContracts() external view returns(address[] memory) {
        uint256 length = _whitelistedOptionContracts.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelistedOptionContracts.at(i);
        }

        return result;
    }

    function isOrderValid(Order memory _order) public view returns(bool) {
        bytes32 hash = keccak256(abi.encode(_order));
        uint256 amountLeft = amounts[hash];

        if (amountLeft == 0) return false;

        // Expired
        if (_order.expirationTime == 0 || _order.expirationTime > getBlockTimestamp()) return false;

        if (_order.side == SaleSide.Buy) {
            uint256 basePrice = _order.pricePerUnit.mul(amountLeft);
            uint256 orderMakerFee = basePrice.mul(makerFee).div(INVERSE_BASIS_POINT);
            uint256 totalPrice = basePrice.add(orderMakerFee);

            uint256 userBalance = weth.balanceOf(_order.maker);
            uint256 allowance = weth.allowance(_order.maker, address(this));

            return userBalance >= totalPrice && allowance >= totalPrice;
        } else if (_order.side == SaleSide.Sell) {
            IPremiaOption premiaOption = IPremiaOption(_order.optionContract);
            uint256 optionBalance = premiaOption.balanceOf(_order.maker, amountLeft);
            bool isApproved = premiaOption.isApprovedForAll(_order.maker, address(this));

            return isApproved && optionBalance >= amountLeft;
        }

        return false;
    }

    function areOrdersValid(Order[] memory _orders) public view returns(bool[] memory) {
        bool[] memory result = new bool[](_orders.length);

        for (uint256 i=0; i < _orders.length; i++) {
            result[i] = isOrderValid(_orders[i]);
        }

        return result;
    }

    //////////
    // Main //
    //////////

    // Maker, salt and expirationTime will be overridden by this function
    function createOrder(Order memory _order, uint256 _amount) public {
        require(_whitelistedOptionContracts.contains(_order.optionContract), "Option contract not whitelisted");

        uint256 _expiration = IPremiaOption(_order.optionContract).getOptionExpiration(_order.optionId);
        require(getBlockTimestamp() < _expiration, "Option expired");

        _order.maker = msg.sender;
        _order.expirationTime = _expiration;
        _order.salt = salt;

        salt = salt.add(1);

        bytes32 hash = keccak256(abi.encode(_order));
        amounts[hash] = _amount;

        emit OrderCreated(
            hash,
            _order.maker,
            _order.optionContract,
            _order.side,
            _order.taker,
            _order.optionId,
            _order.pricePerUnit,
            _order.expirationTime,
            _order.salt,
            _amount
        );
    }

    function createOrders(Order[] memory _orders, uint256[] memory _amounts) public {
        require(_orders.length == _amounts.length, "Arrays must have same length");

        for (uint256 i=0; i < _orders.length; i++) {
            createOrder(_orders[i], _amounts[i]);
        }
    }

    /**
     * @dev Fill an existing order
     * @param _order The order
     * @param _maxAmount Max amount of options to buy/sell
     */
    function fillOrder(Order memory _order, uint256 _maxAmount) public nonReentrant {
        bytes32 hash = keccak256(abi.encode(_order));
        uint256 amountLeft = amounts[hash];

        require(amountLeft > 0, "Order not found");
        require(_order.expirationTime != 0 && _order.expirationTime < getBlockTimestamp(), "Order expired");
        require(_order.optionContract != address(0), "Order not found");
        require(_maxAmount > 0, "MaxAmount must be > 0");
        require(_order.taker == address(0) || _order.taker == msg.sender, "Not specified taker");

        uint256 amount = _maxAmount;
        if (amountLeft < _maxAmount) {
            amount = amountLeft;
        }

        amounts[hash] = amounts[hash].sub(amount);

        uint256 basePrice = _order.pricePerUnit.mul(amount);
        uint256 orderMakerFee = basePrice.mul(makerFee).div(INVERSE_BASIS_POINT);
        uint256 orderTakerFee = basePrice.mul(takerFee).div(INVERSE_BASIS_POINT);

        IPremiaOption optionContract = IPremiaOption(_order.optionContract);

        if (_order.side == SaleSide.Buy) {
            optionContract.safeTransferFrom(msg.sender, _order.maker, _order.optionId, amount, "");

            weth.transferFrom(_order.maker, treasury, orderMakerFee.add(orderTakerFee));
            weth.transferFrom(_order.maker, msg.sender, basePrice.sub(orderTakerFee));

        } else {
            weth.transferFrom(msg.sender, treasury, orderMakerFee.add(orderTakerFee));
            weth.transferFrom(msg.sender, _order.maker, basePrice.sub(orderMakerFee));

            optionContract.safeTransferFrom(_order.maker, msg.sender, _order.optionId, amount, "");
        }

        emit OrderFilled(
            hash,
            msg.sender,
            _order.optionContract,
            _order.maker,
            amount,
            _order.pricePerUnit
        );
    }

    /**
     * @dev Fill a list of existing orders
     * @param _orders The orders
     * @param _maxAmounts Max amount of options to buy/sell
     */
    function fillOrders(Order[] memory _orders, uint256[] memory _maxAmounts) public {
        require(_orders.length == _maxAmounts.length, "Arrays must have same length");
        for (uint256 i=0; i < _orders.length; i++) {
            fillOrder(_orders[i], _maxAmounts[i]);
        }
    }

    /**
     * @dev Cancel an existing order
     * @param _order The order
     */
    function cancelOrder(Order memory _order) public {
        bytes32 hash = keccak256(abi.encode(_order));
        uint256 amountLeft = amounts[hash];

        require(amountLeft > 0, "Order not found");
        require(_order.maker == msg.sender, "Not order maker");
        delete amounts[hash];

        emit OrderCancelled(
            hash,
            _order.maker,
            _order.optionContract,
            amountLeft,
            _order.pricePerUnit
        );
    }

    /**
     * @dev Cancel a list of existing orders
     * @param _orders The orders
     */
    function cancelOrders(Order[] memory _orders) public {
        for (uint256 i=0; i < _orders.length; i++) {
            cancelOrder(_orders[i]);
        }
    }

}