// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import "./interface/IERC20Extended.sol";
import "./interface/IPremiaOption.sol";
import "./interface/IFeeCalculator.sol";
import "./interface/IPremiaReferral.sol";

/// @author Premia
/// @title An option market contract
contract PremiaMarket is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // FeeCalculator contract
    IFeeCalculator public feeCalculator;
    // PremiaReferral contract
    IPremiaReferral public premiaReferral;

    // List of whitelisted option contracts for which users can create orders
    EnumerableSet.AddressSet private _whitelistedOptionContracts;
    // List of whitelisted payment tokens that users can use to buy / sell options
    EnumerableSet.AddressSet private _whitelistedPaymentTokens;

    mapping(address => uint8) public paymentTokenDecimals;

    // Recipient of protocol fees
    address public feeRecipient;

    enum SaleSide {Buy, Sell}

    uint256 private constant _inverseBasisPoint = 1e4;

    // Salt to prevent duplicate hash
    uint256 salt = 0;

    // An order on the exchange
    struct Order {
        address maker;              // Order maker address
        SaleSide side;              // Side (buy/sell)
        bool isDelayedWriting;      // If true, option has not been written yet
        address optionContract;     // Address of optionContract from which option is from
        uint256 optionId;           // OptionId
        address paymentToken;       // Address of token used for payment
        uint256 pricePerUnit;       // Price per unit (in paymentToken) with 18 decimals
        uint256 expirationTime;     // Expiration timestamp of option (Which is also expiration of order)
        uint256 salt;               // To ensure unique hash
        uint8 decimals;             // Option token decimals
    }

    struct Option {
        address token;              // Token address
        uint256 expiration;         // Expiration timestamp of the option (Must follow expirationIncrement)
        uint256 strikePrice;        // Strike price (Must follow strikePriceIncrement of token)
        bool isCall;                // If true : Call option | If false : Put option
    }

    // OrderId -> Amount of options left to purchase/sell
    mapping(bytes32 => uint256) public amounts;

    // Whether delayed option writing is enabled or not
    // This allow users to create a sell order for an option, without writing it, and delay the writing at the moment the order is filled
    bool public isDelayedWritingEnabled = true;

    ////////////
    // Events //
    ////////////

    event OrderCreated(
        bytes32 indexed hash,
        address indexed maker,
        address indexed optionContract,
        SaleSide side,
        bool isDelayedWriting,
        uint256 optionId,
        address paymentToken,
        uint256 pricePerUnit,
        uint256 expirationTime,
        uint256 salt,
        uint256 amount,
        uint8 decimals
    );

    event OrderFilled(
        bytes32 indexed hash,
        address indexed taker,
        address indexed optionContract,
        address maker,
        address paymentToken,
        uint256 amount,
        uint256 pricePerUnit
    );

    event OrderCancelled(
        bytes32 indexed hash,
        address indexed maker,
        address indexed optionContract,
        address paymentToken,
        uint256 amount,
        uint256 pricePerUnit
    );

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    /// @param _feeCalculator FeeCalculator contract
    /// @param _feeRecipient Address receiving protocol fees (PremiaMaker)
    constructor(IFeeCalculator _feeCalculator, address _feeRecipient, IPremiaReferral _premiaReferral) {
        require(_feeRecipient != address(0), "FeeRecipient cannot be 0x0 address");
        feeRecipient = _feeRecipient;
        feeCalculator = _feeCalculator;
        premiaReferral = _premiaReferral;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    /// @notice Change the protocol fee recipient
    /// @param _feeRecipient New protocol fee recipient address
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "FeeRecipient cannot be 0x0 address");
        feeRecipient = _feeRecipient;
    }

    /// @notice Set new FeeCalculator contract
    /// @param _feeCalculator New FeeCalculator contract
    function setFeeCalculator(IFeeCalculator _feeCalculator) external onlyOwner {
        feeCalculator = _feeCalculator;
    }


    /// @notice Add contract addresses to the list of whitelisted option contracts
    /// @param _addr The list of addresses to add
    function addWhitelistedOptionContracts(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedOptionContracts.add(_addr[i]);
        }
    }

    /// @notice Remove contract addresses from the list of whitelisted option contracts
    /// @param _addr The list of addresses to remove
    function removeWhitelistedOptionContracts(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedOptionContracts.remove(_addr[i]);
        }
    }

    /// @notice Add token addresses to the list of whitelisted payment tokens
    /// @param _addr The list of addresses to add
    function addWhitelistedPaymentTokens(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            uint8 decimals = IERC20Extended(_addr[i]).decimals();
            require(decimals <= 18, "Too many decimals");
            _whitelistedPaymentTokens.add(_addr[i]);
            paymentTokenDecimals[_addr[i]] = decimals;
        }
    }
    /// @notice Remove contract addresses from the list of whitelisted payment tokens
    /// @param _addr The list of addresses to remove
    function removeWhitelistedPaymentTokens(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedPaymentTokens.remove(_addr[i]);
        }
    }

    /// @notice Enable or disable delayed option writing which allow users to create option sell order without writing the option before the order is filled
    /// @param _state New state (true = enabled / false = disabled)
    function setDelayedWritingEnabled(bool _state) external onlyOwner {
        isDelayedWritingEnabled = _state;
    }

    //////////////////////////////////////////////////

    //////////
    // View //
    //////////

    /// @notice Get the amounts left to buy/sell for an order
    /// @param _orderIds A list of order hashes
    /// @return List of amounts left for each order
    function getAmountsBatch(bytes32[] memory _orderIds) external view returns(uint256[] memory) {
        uint256[] memory result = new uint256[](_orderIds.length);

        for (uint256 i=0; i < _orderIds.length; i++) {
            result[i] = amounts[_orderIds[i]];
        }

        return result;
    }

    /// @notice Get order hashes for a list of orders
    /// @param _orders A list of orders
    /// @return List of orders hashes
    function getOrderHashBatch(Order[] memory _orders) external pure returns(bytes32[] memory) {
        bytes32[] memory result = new bytes32[](_orders.length);

        for (uint256 i=0; i < _orders.length; i++) {
            result[i] = getOrderHash(_orders[i]);
        }

        return result;
    }

    /// @notice Get the hash of an order
    /// @param _order The order from which to calculate the hash
    /// @return The order hash
    function getOrderHash(Order memory _order) public pure returns(bytes32) {
        return keccak256(abi.encode(_order));
    }

    /// @notice Get the list of whitelisted option contracts
    /// @return The list of whitelisted option contracts
    function getWhitelistedOptionContracts() external view returns(address[] memory) {
        uint256 length = _whitelistedOptionContracts.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelistedOptionContracts.at(i);
        }

        return result;
    }

    /// @notice Get the list of whitelisted payment tokens
    /// @return The list of whitelisted payment tokens
    function getWhitelistedPaymentTokens() external view returns(address[] memory) {
        uint256 length = _whitelistedPaymentTokens.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelistedPaymentTokens.at(i);
        }

        return result;
    }

    /// @notice Check the validity of an order (Make sure order make has sufficient balance + allowance for required tokens)
    /// @param _order The order from which to check the validity
    /// @return Whether the order is valid or not
    function isOrderValid(Order memory _order) public view returns(bool) {
        bytes32 hash = getOrderHash(_order);
        uint256 amountLeft = amounts[hash];

        if (amountLeft == 0) return false;

        // Expired
        if (_order.expirationTime == 0 || block.timestamp > _order.expirationTime) return false;

        IERC20 token = IERC20(_order.paymentToken);

        if (_order.side == SaleSide.Buy) {
            uint8 decimals = _order.decimals;
            uint256 basePrice = _order.pricePerUnit * amountLeft / (10**decimals);
            uint256 makerFee = feeCalculator.getFee(_order.maker, false, IFeeCalculator.FeeType.Maker);
            uint256 orderMakerFee = basePrice * makerFee / _inverseBasisPoint;
            uint256 totalPrice = basePrice + orderMakerFee;

            uint256 userBalance = token.balanceOf(_order.maker);
            uint256 allowance = token.allowance(_order.maker, address(this));

            return userBalance >= totalPrice && allowance >= totalPrice;
        } else if (_order.side == SaleSide.Sell) {
            IPremiaOption premiaOption = IPremiaOption(_order.optionContract);
            bool isApproved = premiaOption.isApprovedForAll(_order.maker, address(this));

            if (_order.isDelayedWriting) {
                IPremiaOption.OptionData memory data = premiaOption.optionData(_order.optionId);
                IPremiaOption.OptionWriteArgs memory writeArgs = IPremiaOption.OptionWriteArgs({
                    token: data.token,
                    amount: amountLeft,
                    strikePrice: data.strikePrice,
                    expiration: data.expiration,
                    isCall: data.isCall
                });

                IPremiaOption.QuoteWrite memory quote = premiaOption.getWriteQuote(_order.maker, writeArgs, address(0), _order.decimals);

                uint256 userBalance = IERC20(quote.collateralToken).balanceOf(_order.maker);
                uint256 allowance = IERC20(quote.collateralToken).allowance(_order.maker, _order.optionContract);
                uint256 totalPrice = quote.collateral + quote.fee + quote.feeReferrer;

                return isApproved && userBalance >= totalPrice && allowance >= totalPrice;

            } else {
                uint256 optionBalance = premiaOption.balanceOf(_order.maker, _order.optionId);
                return isApproved && optionBalance >= amountLeft;
            }
        }

        return false;
    }

    /// @notice Check the validity of a list of orders (Make sure order make has sufficient balance + allowance for required tokens)
    /// @param _orders The orders from which to check the validity
    /// @return Whether the orders are valid or not
    function areOrdersValid(Order[] memory _orders) external view returns(bool[] memory) {
        bool[] memory result = new bool[](_orders.length);

        for (uint256 i=0; i < _orders.length; i++) {
            result[i] = isOrderValid(_orders[i]);
        }

        return result;
    }

    //////////////////////////////////////////////////

    //////////
    // Main //
    //////////

    /// @notice Create a new order
    /// @dev Maker, salt and expirationTime will be overridden by this function
    /// @param _order Order to create
    /// @param _amount Amount of options to buy / sell
    /// @return The hash of the order
    function createOrder(Order memory _order, uint256 _amount) public returns(bytes32) {
        require(_whitelistedOptionContracts.contains(_order.optionContract), "Option contract not whitelisted");
        require(_whitelistedPaymentTokens.contains(_order.paymentToken), "Payment token not whitelisted");

        IPremiaOption.OptionData memory data = IPremiaOption(_order.optionContract).optionData(_order.optionId);
        require(data.strikePrice > 0, "Option not found");
        require(block.timestamp < data.expiration, "Option expired");

        _order.maker = msg.sender;
        _order.expirationTime = data.expiration;
        _order.decimals = data.decimals;
        _order.salt = salt;

        require(_order.decimals <= 18, "Too many decimals");

        if (_order.isDelayedWriting) {
            require(isDelayedWritingEnabled, "Delayed writing disabled");
        }

        // If this is a buy order, isDelayedWriting is always false
        if (_order.side == SaleSide.Buy) {
            _order.isDelayedWriting = false;
        }

        salt += 1;

        bytes32 hash = getOrderHash(_order);
        amounts[hash] = _amount;
        uint8 decimals = _order.decimals;

        emit OrderCreated(
            hash,
            _order.maker,
            _order.optionContract,
            _order.side,
            _order.isDelayedWriting,
            _order.optionId,
            _order.paymentToken,
            _order.pricePerUnit,
            _order.expirationTime,
            _order.salt,
            _amount,
            decimals
        );

        return hash;
    }

    /// @notice Create an order for an option which has never been minted before (Will create a new optionId for this option)
    /// @param _order Order to create
    /// @param _amount Amount of options to buy / sell
    /// @param _option Option to create
    /// @return The hash of the order
    /// @param _referrer Referrer
    function createOrderForNewOption(Order memory _order, uint256 _amount, Option memory _option, address _referrer) external returns(bytes32) {
        // If this is a delayed writing on a sell order, we need to set referrer now, so that it is used when writing is done
        if (address(premiaReferral) != address(0) && _order.isDelayedWriting && _order.side == SaleSide.Sell) {
            _referrer = premiaReferral.trySetReferrer(msg.sender, _referrer);
        }

        _order.optionId = IPremiaOption(_order.optionContract).getOptionIdOrCreate(_option.token, _option.expiration, _option.strikePrice, _option.isCall);
        return createOrder(_order, _amount);
    }

    /// @notice Create a list of orders
    /// @param _orders Orders to create
    /// @param _amounts Amounts of options to buy / sell for each order
    /// @return The hashes of the orders
    function createOrders(Order[] memory _orders, uint256[] memory _amounts) external returns(bytes32[] memory) {
        require(_orders.length == _amounts.length, "Arrays must have same length");

        bytes32[] memory result = new bytes32[](_orders.length);

        for (uint256 i=0; i < _orders.length; i++) {
            result[i] = createOrder(_orders[i], _amounts[i]);
        }

        return result;
    }

    /// @notice Try to fill orders passed as candidates, and create order for remaining unfilled amount
    /// @param _order Order to create
    /// @param _amount Amount of options to buy / sell
    /// @param _orderCandidates Accepted orders to be filled
    /// @param _writeOnBuyFill Write option prior to filling order when a buy order is passed
    /// @param _referrer Referrer
    function createOrderAndTryToFill(Order memory _order, uint256 _amount, Order[] memory _orderCandidates, bool _writeOnBuyFill, address _referrer) external {
        require(_amount > 0, "Amount must be > 0");

        // Ensure candidate orders are valid
        for (uint256 i=0; i < _orderCandidates.length; i++) {
            require(_orderCandidates[i].side != _order.side, "Candidate order : Same order side");
            require(_orderCandidates[i].optionContract == _order.optionContract, "Candidate order : Diff option contract");
            require(_orderCandidates[i].optionId == _order.optionId, "Candidate order : Diff optionId");
        }

        uint256 totalFilled;
        if (_orderCandidates.length == 1) {
            totalFilled = fillOrder(_orderCandidates[0], _amount, _writeOnBuyFill, _referrer);
        } else if (_orderCandidates.length > 1) {
            totalFilled = fillOrders(_orderCandidates, _amount, _writeOnBuyFill, _referrer);
        }

        if (totalFilled < _amount) {
            createOrder(_order, _amount - totalFilled);
        }
    }

    /// @notice Write an option and create a sell order
    /// @dev OptionId will be filled automatically on the order object. Amount is defined in the option object.
    ///      Approval on option contract is required
    /// @param _order Order to create
    /// @param _referrer Referrer
    /// @return The hash of the order
    function writeAndCreateOrder(IPremiaOption.OptionWriteArgs memory _option, Order memory _order, address _referrer) public returns(bytes32) {
        require(_order.side == SaleSide.Sell, "Not a sell order");

        // This cannot be a delayed writing as we are writing the option now
        _order.isDelayedWriting = false;

        IPremiaOption optionContract = IPremiaOption(_order.optionContract);
        _order.optionId = optionContract.writeOptionFrom(msg.sender, _option, _referrer);

        return createOrder(_order, _option.amount);
    }

    /// @notice Fill an existing order
    /// @param _order The order to fill
    /// @param _amount Max amount of options to buy or sell
    /// @param _writeOnBuyFill Write option prior to filling order when a buy order is passed
    /// @param _referrer Referrer
    /// @return Amount of options bought or sold
    function fillOrder(Order memory _order, uint256 _amount, bool _writeOnBuyFill, address _referrer) public nonReentrant returns(uint256) {
        bytes32 hash = getOrderHash(_order);

        require(_order.expirationTime != 0 && block.timestamp < _order.expirationTime, "Order expired");
        require(amounts[hash] > 0, "Order not found");
        require(_amount > 0, "Amount must be > 0");

        if (amounts[hash] < _amount) {
            _amount = amounts[hash];
        }

        amounts[hash] -= _amount;

        // If option has delayed minting on fill, we first need to mint it on behalf of order maker
        if (_order.side == SaleSide.Sell && _order.isDelayedWriting) {
            // We do not pass a referrer, cause referrer used is the one of the order maker
            IPremiaOption(_order.optionContract).writeOptionWithIdFrom(_order.maker, _order.optionId, _amount, address(0));
        } else if (_order.side == SaleSide.Buy && _writeOnBuyFill) {
            IPremiaOption(_order.optionContract).writeOptionWithIdFrom(msg.sender, _order.optionId, _amount, _referrer);
        }

        uint256 basePrice = _order.pricePerUnit * _amount / (10**_order.decimals);

        (uint256 orderMakerFee,) = feeCalculator.getFeeAmounts(_order.maker, false, basePrice, IFeeCalculator.FeeType.Maker);
        (uint256 orderTakerFee,) = feeCalculator.getFeeAmounts(msg.sender, false, basePrice, IFeeCalculator.FeeType.Taker);

        if (_order.side == SaleSide.Buy) {
            IPremiaOption(_order.optionContract).safeTransferFrom(msg.sender, _order.maker, _order.optionId, _amount, "");

            IERC20(_order.paymentToken).safeTransferFrom(_order.maker, feeRecipient, orderMakerFee + orderTakerFee);
            IERC20(_order.paymentToken).safeTransferFrom(_order.maker, msg.sender, basePrice - orderTakerFee);

        } else {
            IERC20(_order.paymentToken).safeTransferFrom(msg.sender, feeRecipient, orderMakerFee + orderTakerFee);
            IERC20(_order.paymentToken).safeTransferFrom(msg.sender, _order.maker, basePrice - orderMakerFee);

            IPremiaOption(_order.optionContract).safeTransferFrom(_order.maker, msg.sender, _order.optionId, _amount, "");
        }

        emit OrderFilled(
            hash,
            msg.sender,
            _order.optionContract,
            _order.maker,
            _order.paymentToken,
            _amount,
            _order.pricePerUnit
        );

        return _amount;
    }


    /// @notice Fill a list of existing orders
    /// @dev All orders passed must :
    ///         - Use same payment token
    ///         - Be on the same order side
    ///         - Be for the same option contract and optionId
    /// @param _orders The list of orders to fill
    /// @param _maxAmount Max amount of options to buy or sell
    /// @param _writeOnBuyFill Write option prior to filling order when a buy order is passed
    /// @param _referrer Referrer
    /// @return Amount of options bought or sold
    function fillOrders(Order[] memory _orders, uint256 _maxAmount, bool _writeOnBuyFill, address _referrer) public nonReentrant returns(uint256) {
        if (_maxAmount == 0) return 0;

        uint256 takerFee = feeCalculator.getFee(msg.sender, false, IFeeCalculator.FeeType.Taker);

        // We make sure all orders are same side / payment token / option contract / option id
        if (_orders.length > 1) {
            for (uint256 i=0; i < _orders.length; i++) {
                require(i == 0 || _orders[0].paymentToken == _orders[i].paymentToken, "Different payment tokens");
                require(i == 0 || _orders[0].side == _orders[i].side, "Different order side");
                require(i == 0 || _orders[0].optionContract == _orders[i].optionContract, "Different option contract");
                require(i == 0 || _orders[0].optionId == _orders[i].optionId, "Different option id");
            }
        }

        uint256 totalFee;
        uint256 totalAmount;
        uint256 amountFilled;

        for (uint256 i=0; i < _orders.length; i++) {
            if (amountFilled >= _maxAmount) break;

            Order memory _order = _orders[i];
            bytes32 hash = getOrderHash(_order);

            // If nothing left to fill, continue
            if (amounts[hash] == 0) continue;
            // If expired, continue
            if (block.timestamp >= _order.expirationTime) continue;

            uint256 amount = amounts[hash];
            if (amountFilled + amount > _maxAmount) {
                amount = _maxAmount - amountFilled;
            }

            amounts[hash] -= amount;
            amountFilled += amount;

            // If option has delayed minting on fill, we first need to mint it on behalf of order maker
            if (_order.side == SaleSide.Sell && _order.isDelayedWriting) {
                // We do not pass a referrer, cause referrer used is the one of the order maker
                IPremiaOption(_order.optionContract).writeOptionWithIdFrom(_order.maker, _order.optionId, amount, address(0));
            } else if (_order.side == SaleSide.Buy && _writeOnBuyFill) {
                IPremiaOption(_order.optionContract).writeOptionWithIdFrom(msg.sender, _order.optionId, amount, _referrer);
            }

            uint256 basePrice = _order.pricePerUnit * amount / (10**_order.decimals);

            (uint256 orderMakerFee,) = feeCalculator.getFeeAmounts(_order.maker, false, basePrice, IFeeCalculator.FeeType.Maker);
            uint256 orderTakerFee = basePrice * takerFee / _inverseBasisPoint;

            totalFee += orderMakerFee + orderTakerFee;

            if (_order.side == SaleSide.Buy) {
                IPremiaOption(_order.optionContract).safeTransferFrom(msg.sender, _order.maker, _order.optionId, amount, "");

                // We transfer all to the contract, contract will pays fees, and send remainder to msg.sender
                IERC20(_order.paymentToken).safeTransferFrom(_order.maker, address(this), basePrice + orderMakerFee);
                totalAmount += basePrice + orderMakerFee;

            } else {
                // We pay order maker, fees will be all paid at once later
                IERC20(_order.paymentToken).safeTransferFrom(msg.sender, _order.maker, basePrice - orderMakerFee);
                IPremiaOption(_order.optionContract).safeTransferFrom(_order.maker, msg.sender, _order.optionId, amount, "");
            }

            emit OrderFilled(
                hash,
                msg.sender,
                _order.optionContract,
                _order.maker,
                _order.paymentToken,
                amount,
                _order.pricePerUnit
            );
        }

        if (_orders[0].side == SaleSide.Buy) {
            // Batch payment of fees
            IERC20(_orders[0].paymentToken).safeTransfer(feeRecipient, totalFee);
            // Send remainder of tokens after fee payment, to msg.sender
            IERC20(_orders[0].paymentToken).safeTransfer(msg.sender, totalAmount - totalFee);
        } else {
            // Batch payment of fees
            IERC20(_orders[0].paymentToken).safeTransferFrom(msg.sender, feeRecipient, totalFee);
        }

        return amountFilled;
    }

    /// @notice Cancel an existing order
    /// @param _order The order to cancel
    function cancelOrder(Order memory _order) public {
        bytes32 hash = getOrderHash(_order);
        uint256 amountLeft = amounts[hash];

        require(amountLeft > 0, "Order not found");
        require(_order.maker == msg.sender, "Not order maker");
        delete amounts[hash];

        emit OrderCancelled(
            hash,
            _order.maker,
            _order.optionContract,
            _order.paymentToken,
            amountLeft,
            _order.pricePerUnit
        );
    }

    /// @notice Cancel a list of existing orders
    /// @param _orders The list of orders to cancel
    function cancelOrders(Order[] memory _orders) external {
        for (uint256 i=0; i < _orders.length; i++) {
            cancelOrder(_orders[i]);
        }
    }
}