// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '@solidstate/contracts/utils/EnumerableSet.sol';
import '@solidstate/contracts/access/Ownable.sol';
import '@solidstate/contracts/utils/ReentrancyGuard.sol';

import "../../interface/IERC20Extended.sol";
import "../../interface/IPremiaOption.sol";
import "../../interface/IFeeCalculator.sol";
import "./MarketStorage.sol";

/// @author Premia
/// @title An option market contract
contract Market is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using MarketStorage for MarketStorage.Layout;
    using SafeERC20 for IERC20;

    uint256 private constant _inverseBasisPoint = 1e4;

    ////////////
    // Events //
    ////////////

    event OrderCreated(
        bytes32 indexed hash,
        address indexed maker,
        address indexed optionContract,
        MarketStorage.SaleSide side,
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

    ///////////
    // Admin //
    ///////////

    /// @notice Change the protocol fee recipient
    /// @param _feeRecipient New protocol fee recipient address
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "FeeRecipient cannot be 0x0 address");
        MarketStorage.layout().feeRecipient = _feeRecipient;
    }

    /// @notice Set new FeeCalculator contract
    /// @param _feeCalculator New FeeCalculator contract
    function setFeeCalculator(address _feeCalculator) external onlyOwner {
        MarketStorage.layout().feeCalculator = _feeCalculator;
    }


    /// @notice Add contract addresses to the list of whitelisted option contracts
    /// @param _addr The list of addresses to add
    function addWhitelistedOptionContracts(address[] memory _addr) external onlyOwner {
        MarketStorage.Layout storage l = MarketStorage.layout();

        for (uint256 i=0; i < _addr.length; i++) {
            l.whitelistedOptionContracts.add(_addr[i]);
        }
    }

    /// @notice Remove contract addresses from the list of whitelisted option contracts
    /// @param _addr The list of addresses to remove
    function removeWhitelistedOptionContracts(address[] memory _addr) external onlyOwner {
        MarketStorage.Layout storage l = MarketStorage.layout();

        for (uint256 i=0; i < _addr.length; i++) {
            l.whitelistedOptionContracts.remove(_addr[i]);
        }
    }

    /// @notice Add token addresses to the list of whitelisted payment tokens
    /// @param _addr The list of addresses to add
    function addWhitelistedPaymentTokens(address[] memory _addr) external onlyOwner {
        MarketStorage.Layout storage l = MarketStorage.layout();

        for (uint256 i=0; i < _addr.length; i++) {
            uint8 decimals = IERC20Extended(_addr[i]).decimals();
            require(decimals <= 18, "Too many decimals");
            l.whitelistedPaymentTokens.add(_addr[i]);
            l.paymentTokenDecimals[_addr[i]] = decimals;
        }
    }
    /// @notice Remove contract addresses from the list of whitelisted payment tokens
    /// @param _addr The list of addresses to remove
    function removeWhitelistedPaymentTokens(address[] memory _addr) external onlyOwner {
        MarketStorage.Layout storage l = MarketStorage.layout();

        for (uint256 i=0; i < _addr.length; i++) {
            l.whitelistedPaymentTokens.remove(_addr[i]);
        }
    }

    /// @notice Enable or disable delayed option writing which allow users to create option sell order without writing the option before the order is filled
    /// @param _state New state (true = enabled / false = disabled)
    function setDelayedWritingEnabled(bool _state) external onlyOwner {
        MarketStorage.layout().isDelayedWritingEnabled = _state;
    }

    //////////////////////////////////////////////////

    //////////
    // View //
    //////////

    function amounts(bytes32 _orderId) external view returns(uint256) {
        return MarketStorage.layout().amounts[_orderId];
    }

    /// @notice Get the amounts left to buy/sell for an order
    /// @param _orderIds A list of order hashes
    /// @return List of amounts left for each order
    function getAmountsBatch(bytes32[] memory _orderIds) external view returns(uint256[] memory) {
        MarketStorage.Layout storage l = MarketStorage.layout();

        uint256[] memory result = new uint256[](_orderIds.length);

        for (uint256 i=0; i < _orderIds.length; i++) {
            result[i] = l.amounts[_orderIds[i]];
        }

        return result;
    }

    /// @notice Get order hashes for a list of orders
    /// @param _orders A list of orders
    /// @return List of orders hashes
    function getOrderHashBatch(MarketStorage.Order[] memory _orders) external pure returns(bytes32[] memory) {
        bytes32[] memory result = new bytes32[](_orders.length);

        for (uint256 i=0; i < _orders.length; i++) {
            result[i] = getOrderHash(_orders[i]);
        }

        return result;
    }

    /// @notice Get the hash of an order
    /// @param _order The order from which to calculate the hash
    /// @return The order hash
    function getOrderHash(MarketStorage.Order memory _order) public pure returns(bytes32) {
        return keccak256(abi.encode(_order));
    }

    /// @notice Get the list of whitelisted option contracts
    /// @return The list of whitelisted option contracts
    function getWhitelistedOptionContracts() external view returns(address[] memory) {
        MarketStorage.Layout storage l = MarketStorage.layout();

        uint256 length = l.whitelistedOptionContracts.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = l.whitelistedOptionContracts.at(i);
        }

        return result;
    }

    /// @notice Get the list of whitelisted payment tokens
    /// @return The list of whitelisted payment tokens
    function getWhitelistedPaymentTokens() external view returns(address[] memory) {
        MarketStorage.Layout storage l = MarketStorage.layout();

        uint256 length = l.whitelistedPaymentTokens.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = l.whitelistedPaymentTokens.at(i);
        }

        return result;
    }

    /// @notice Check the validity of an order (Make sure order make has sufficient balance + allowance for required tokens)
    /// @param _order The order from which to check the validity
    /// @return Whether the order is valid or not
    function isOrderValid(MarketStorage.Order memory _order) public view returns(bool) {
        MarketStorage.Layout storage l = MarketStorage.layout();

        bytes32 hash = getOrderHash(_order);
        uint256 amountLeft = l.amounts[hash];

        if (amountLeft == 0) return false;

        // Expired
        if (_order.expirationTime == 0 || block.timestamp > _order.expirationTime) return false;

        IERC20 token = IERC20(_order.paymentToken);

        if (_order.side == MarketStorage.SaleSide.Buy) {
            uint8 decimals = _order.decimals;
            uint256 basePrice = _order.pricePerUnit * amountLeft / (10**decimals);
            uint256 makerFee = IFeeCalculator(l.feeCalculator).getFee(_order.maker, IFeeCalculator.FeeType.Maker);
            uint256 orderMakerFee = basePrice * makerFee / _inverseBasisPoint;
            uint256 totalPrice = basePrice + orderMakerFee;

            uint256 userBalance = token.balanceOf(_order.maker);
            uint256 allowance = token.allowance(_order.maker, address(this));

            return userBalance >= totalPrice && allowance >= totalPrice;
        } else if (_order.side == MarketStorage.SaleSide.Sell) {
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

                IPremiaOption.QuoteWrite memory quote = premiaOption.getWriteQuote(_order.maker, writeArgs, _order.decimals);

                uint256 userBalance = IERC20(quote.collateralToken).balanceOf(_order.maker);
                uint256 allowance = IERC20(quote.collateralToken).allowance(_order.maker, _order.optionContract);
                uint256 totalPrice = quote.collateral + quote.fee;

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
    function areOrdersValid(MarketStorage.Order[] memory _orders) external view returns(bool[] memory) {
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
    function createOrder(MarketStorage.Order memory _order, uint256 _amount) public returns(bytes32) {
        bytes32 hash;

        // If this is a buy order, isDelayedWriting is always false
        if (_order.side == MarketStorage.SaleSide.Buy) {
            _order.isDelayedWriting = false;
        }

        { // Scope to avoid stack too deep error
            MarketStorage.Layout storage l = MarketStorage.layout();

            require(l.whitelistedOptionContracts.contains(_order.optionContract), "Option contract not whitelisted");
            require(l.whitelistedPaymentTokens.contains(_order.paymentToken), "Payment token not whitelisted");

            IPremiaOption.OptionData memory data = IPremiaOption(_order.optionContract).optionData(_order.optionId);
            require(data.strikePrice > 0, "Option not found");
            require(block.timestamp < data.expiration, "Option expired");

            _order.maker = msg.sender;
            _order.expirationTime = data.expiration;
            _order.decimals = data.decimals;
            _order.salt = l.salt;

            hash = getOrderHash(_order);

            l.salt += 1;
            l.amounts[hash] = _amount;

            require(_order.decimals <= 18, "Too many decimals");
            require(_order.isDelayedWriting == false || l.isDelayedWritingEnabled, "Delayed writing disabled");
        }

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
            _order.decimals
        );

        return hash;
    }

    /// @notice Create an order for an option which has never been minted before (Will create a new optionId for this option)
    /// @param _order Order to create
    /// @param _amount Amount of options to buy / sell
    /// @param _option Option to create
    /// @return The hash of the order
    function createOrderForNewOption(MarketStorage.Order memory _order, uint256 _amount, MarketStorage.Option memory _option) external returns(bytes32) {
        _order.optionId = IPremiaOption(_order.optionContract).getOptionIdOrCreate(_option.token, _option.expiration, _option.strikePrice, _option.isCall);
        return createOrder(_order, _amount);
    }

    /// @notice Create a list of orders
    /// @param _orders Orders to create
    /// @param _amounts Amounts of options to buy / sell for each order
    /// @return The hashes of the orders
    function createOrders(MarketStorage.Order[] memory _orders, uint256[] memory _amounts) external returns(bytes32[] memory) {
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
    function createOrderAndTryToFill(MarketStorage.Order memory _order, uint256 _amount, MarketStorage.Order[] memory _orderCandidates, bool _writeOnBuyFill) external {
        require(_amount > 0, "Amount must be > 0");

        // Ensure candidate orders are valid
        for (uint256 i=0; i < _orderCandidates.length; i++) {
            require(_orderCandidates[i].side != _order.side, "Candidate order : Same order side");
            require(_orderCandidates[i].optionContract == _order.optionContract, "Candidate order : Diff option contract");
            require(_orderCandidates[i].optionId == _order.optionId, "Candidate order : Diff optionId");
        }

        uint256 totalFilled;
        if (_orderCandidates.length == 1) {
            totalFilled = fillOrder(_orderCandidates[0], _amount, _writeOnBuyFill);
        } else if (_orderCandidates.length > 1) {
            totalFilled = fillOrders(_orderCandidates, _amount, _writeOnBuyFill);
        }

        if (totalFilled < _amount) {
            createOrder(_order, _amount - totalFilled);
        }
    }

    /// @notice Write an option and create a sell order
    /// @dev OptionId will be filled automatically on the order object. Amount is defined in the option object.
    ///      Approval on option contract is required
    /// @param _order Order to create
    /// @return The hash of the order
    function writeAndCreateOrder(IPremiaOption.OptionWriteArgs memory _option, MarketStorage.Order memory _order) public returns(bytes32) {
        require(_order.side == MarketStorage.SaleSide.Sell, "Not a sell order");

        // This cannot be a delayed writing as we are writing the option now
        _order.isDelayedWriting = false;

        IPremiaOption optionContract = IPremiaOption(_order.optionContract);
        _order.optionId = optionContract.writeOptionFrom(msg.sender, _option);

        return createOrder(_order, _option.amount);
    }

    /// @notice Fill an existing order
    /// @param _order The order to fill
    /// @param _amount Max amount of options to buy or sell
    /// @param _writeOnBuyFill Write option prior to filling order when a buy order is passed
    /// @return Amount of options bought or sold
    function fillOrder(MarketStorage.Order memory _order, uint256 _amount, bool _writeOnBuyFill) public nonReentrant returns(uint256) {
        bytes32 hash = getOrderHash(_order);

        { // Scope to avoid stack too deep error
            MarketStorage.Layout storage l = MarketStorage.layout();

            require(_order.expirationTime != 0 && block.timestamp < _order.expirationTime, "Order expired");
            require(l.amounts[hash] > 0, "Order not found");
            require(_amount > 0, "Amount must be > 0");

            if (l.amounts[hash] < _amount) {
                _amount = l.amounts[hash];
            }

            l.amounts[hash] -= _amount;

            // If option has delayed minting on fill, we first need to mint it on behalf of order maker
            if (_order.side == MarketStorage.SaleSide.Sell && _order.isDelayedWriting) {
                IPremiaOption(_order.optionContract).writeOptionWithIdFrom(_order.maker, _order.optionId, _amount);
            } else if (_order.side == MarketStorage.SaleSide.Buy && _writeOnBuyFill) {
                IPremiaOption(_order.optionContract).writeOptionWithIdFrom(msg.sender, _order.optionId, _amount);
            }

            uint256 basePrice = _order.pricePerUnit * _amount / (10**_order.decimals);

            uint256 orderMakerFee = IFeeCalculator(l.feeCalculator).getFeeAmount(_order.maker, basePrice, IFeeCalculator.FeeType.Maker);
            uint256 orderTakerFee = IFeeCalculator(l.feeCalculator).getFeeAmount(msg.sender, basePrice, IFeeCalculator.FeeType.Taker);

            if (_order.side == MarketStorage.SaleSide.Buy) {
                IPremiaOption(_order.optionContract).safeTransferFrom(msg.sender, _order.maker, _order.optionId, _amount, "");

                IERC20(_order.paymentToken).safeTransferFrom(_order.maker, l.feeRecipient, orderMakerFee + orderTakerFee);
                IERC20(_order.paymentToken).safeTransferFrom(_order.maker, msg.sender, basePrice - orderTakerFee);

            } else {
                IERC20(_order.paymentToken).safeTransferFrom(msg.sender, l.feeRecipient, orderMakerFee + orderTakerFee);
                IERC20(_order.paymentToken).safeTransferFrom(msg.sender, _order.maker, basePrice - orderMakerFee);

                IPremiaOption(_order.optionContract).safeTransferFrom(_order.maker, msg.sender, _order.optionId, _amount, "");
            }
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
    /// @return Amount of options bought or sold
    function fillOrders(MarketStorage.Order[] memory _orders, uint256 _maxAmount, bool _writeOnBuyFill) public nonReentrant returns(uint256) {
        if (_maxAmount == 0) return 0;

        MarketStorage.Layout storage l = MarketStorage.layout();

        uint256 takerFee = IFeeCalculator(l.feeCalculator).getFee(msg.sender, IFeeCalculator.FeeType.Taker);

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

            MarketStorage.Order memory _order = _orders[i];
            bytes32 hash = getOrderHash(_order);

            // If nothing left to fill, continue
            if (l.amounts[hash] == 0) continue;
            // If expired, continue
            if (block.timestamp >= _order.expirationTime) continue;

            uint256 amount = l.amounts[hash];
            if (amountFilled + amount > _maxAmount) {
                amount = _maxAmount - amountFilled;
            }

            l.amounts[hash] -= amount;
            amountFilled += amount;

            // If option has delayed minting on fill, we first need to mint it on behalf of order maker
            if (_order.side == MarketStorage.SaleSide.Sell && _order.isDelayedWriting) {
                IPremiaOption(_order.optionContract).writeOptionWithIdFrom(_order.maker, _order.optionId, amount);
            } else if (_order.side == MarketStorage.SaleSide.Buy && _writeOnBuyFill) {
                IPremiaOption(_order.optionContract).writeOptionWithIdFrom(msg.sender, _order.optionId, amount);
            }

            uint256 basePrice = _order.pricePerUnit * amount / (10**_order.decimals);

            uint256 orderMakerFee = IFeeCalculator(l.feeCalculator).getFeeAmount(_order.maker, basePrice, IFeeCalculator.FeeType.Maker);
            uint256 orderTakerFee = basePrice * takerFee / _inverseBasisPoint;

            totalFee += orderMakerFee + orderTakerFee;

            if (_order.side == MarketStorage.SaleSide.Buy) {
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

        if (_orders[0].side == MarketStorage.SaleSide.Buy) {
            // Batch payment of fees
            IERC20(_orders[0].paymentToken).safeTransfer(l.feeRecipient, totalFee);
            // Send remainder of tokens after fee payment, to msg.sender
            IERC20(_orders[0].paymentToken).safeTransfer(msg.sender, totalAmount - totalFee);
        } else {
            // Batch payment of fees
            IERC20(_orders[0].paymentToken).safeTransferFrom(msg.sender, l.feeRecipient, totalFee);
        }

        return amountFilled;
    }

    /// @notice Cancel an existing order
    /// @param _order The order to cancel
    function cancelOrder(MarketStorage.Order memory _order) public {
        MarketStorage.Layout storage l = MarketStorage.layout();

        bytes32 hash = getOrderHash(_order);
        uint256 amountLeft = l.amounts[hash];

        require(amountLeft > 0, "Order not found");
        require(_order.maker == msg.sender, "Not order maker");
        delete l.amounts[hash];

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
    function cancelOrders(MarketStorage.Order[] memory _orders) external {
        for (uint256 i=0; i < _orders.length; i++) {
            cancelOrder(_orders[i]);
        }
    }
}
