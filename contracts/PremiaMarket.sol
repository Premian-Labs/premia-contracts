// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import "./interface/IERC20Extended.sol";
import "./interface/IPremiaOption.sol";
import "./interface/IFeeCalculator.sol";
import "./interface/IPremiaReferral.sol";
import "./interface/IPremiaUncutErc20.sol";


contract PremiaMarket is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20Extended;
    using EnumerableSet for EnumerableSet.AddressSet;

    IPremiaUncutErc20 public uPremia;
    IFeeCalculator public feeCalculator;

    EnumerableSet.AddressSet private _whitelistedOptionContracts;
    EnumerableSet.AddressSet private _whitelistedPaymentTokens;

    /* Recipient of protocol fees. */
    address public feeRecipient;

    enum SaleSide {Buy, Sell}

    /* Inverse basis point. */
    uint256 private constant _inverseBasisPoint = 1e4;

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
        /* Address of token used for payment. */
        address paymentToken;
        /* Price per unit (in paymentToken). */
        uint256 pricePerUnit;
        /* Number of decimals of token for which the option is for. */
        uint8 decimals;
        /* Expiration timestamp of option (Which is also expiration of order). */
        uint256 expirationTime;
        /* To ensure unique hash */
        uint256 salt;
    }

    struct Option {
        /* Token address */
        address token;
        /* Expiration timestamp of the option (Must follow expirationIncrement) */
        uint256 expiration;
        /* Strike price (Must follow strikePriceIncrement of token) */
        uint256 strikePrice;
        /* If true : Call option | If false : Put option */
        bool isCall;
    }

    /* OrderId -> Amount of options left to purchase/sell */
    mapping(bytes32 => uint256) public amounts;

    mapping(address => uint256) public uPremiaBalance;

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
        address paymentToken,
        uint256 pricePerUnit,
        uint8 decimals,
        uint256 expirationTime,
        uint256 salt,
        uint256 amount
    );

    event OrderFilled(
        bytes32 indexed hash,
        address indexed taker,
        address indexed optionContract,
        address maker,
        address paymentToken,
        uint256 amount,
        uint256 pricePerUnit,
        uint8 decimals
    );

    event OrderCancelled(
        bytes32 indexed hash,
        address indexed maker,
        address indexed optionContract,
        address paymentToken,
        uint256 amount,
        uint256 pricePerUnit,
        uint8 decimals
    );

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    constructor(IPremiaUncutErc20 _uPremia, IFeeCalculator _feeCalculator, address _feeRecipient) {
        require(_feeRecipient != address(0), "FeeRecipient cannot be 0x0 address");
        feeRecipient = _feeRecipient;
        uPremia = _uPremia;
        feeCalculator = _feeCalculator;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    /**
     * @dev Change the protocol fee recipient (owner only)
     * @param _feeRecipient New protocol fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "FeeRecipient cannot be 0x0 address");
        feeRecipient = _feeRecipient;
    }

    function setPremiaUncutErc20(IPremiaUncutErc20 _uPremia) external onlyOwner {
        uPremia = _uPremia;
    }

    function setFeeCalculator(IFeeCalculator _feeCalculator) external onlyOwner {
        feeCalculator = _feeCalculator;
    }

    function addWhitelistedOptionContracts(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedOptionContracts.add(_addr[i]);
        }
    }

    function removeWhitelistedOptionContracts(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedOptionContracts.remove(_addr[i]);
        }
    }

    function addWhitelistedPaymentTokens(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedPaymentTokens.add(_addr[i]);
        }
    }

    function removeWhitelistedPaymentTokens(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedPaymentTokens.remove(_addr[i]);
        }
    }

    //////////
    // View //
    //////////

    // Returns the amounts left to buy/sell for an order
    function getAmountsBatch(bytes32[] memory _orderIds) external view returns(uint256[] memory) {
        uint256[] memory result = new uint256[](_orderIds.length);

        for (uint256 i=0; i < _orderIds.length; i++) {
            result[i] = amounts[_orderIds[i]];
        }

        return result;
    }

    function getOrderHashBatch(Order[] memory _orders) external pure returns(bytes32[] memory) {
        bytes32[] memory result = new bytes32[](_orders.length);

        for (uint256 i=0; i < _orders.length; i++) {
            result[i] = getOrderHash(_orders[i]);
        }

        return result;
    }

    function getOrderHash(Order memory _order) public pure returns(bytes32) {
        return keccak256(abi.encode(_order));
    }

    function getWhitelistedOptionContracts() external view returns(address[] memory) {
        uint256 length = _whitelistedOptionContracts.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelistedOptionContracts.at(i);
        }

        return result;
    }

    function getWhitelistedPaymentTokens() external view returns(address[] memory) {
        uint256 length = _whitelistedPaymentTokens.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelistedPaymentTokens.at(i);
        }

        return result;
    }

    function isOrderValid(Order memory _order) public view returns(bool) {
        bytes32 hash = getOrderHash(_order);
        uint256 amountLeft = amounts[hash];

        if (amountLeft == 0) return false;

        // Expired
        if (_order.expirationTime == 0 || block.timestamp > _order.expirationTime) return false;

        IERC20Extended token = IERC20Extended(_order.paymentToken);

        IPremiaOption.OptionData memory optionData = IPremiaOption(_order.optionContract).optionData(_order.optionId);
        uint8 decimals = IERC20Extended(optionData.token).decimals();

        if (_order.side == SaleSide.Buy) {
            uint256 basePrice = _order.pricePerUnit.mul(amountLeft).div(10 ** decimals);
            uint256 orderMakerFee = basePrice.mul(feeCalculator.makerFee()).div(_inverseBasisPoint);
            uint256 totalPrice = basePrice.add(orderMakerFee);

            uint256 userBalance = token.balanceOf(_order.maker);
            uint256 allowance = token.allowance(_order.maker, address(this));

            return userBalance >= totalPrice && allowance >= totalPrice;
        } else if (_order.side == SaleSide.Sell) {
            IPremiaOption premiaOption = IPremiaOption(_order.optionContract);
            uint256 optionBalance = premiaOption.balanceOf(_order.maker, _order.optionId);
            bool isApproved = premiaOption.isApprovedForAll(_order.maker, address(this));

            return isApproved && optionBalance >= amountLeft;
        }

        return false;
    }

    function areOrdersValid(Order[] memory _orders) external view returns(bool[] memory) {
        bool[] memory result = new bool[](_orders.length);

        for (uint256 i=0; i < _orders.length; i++) {
            result[i] = isOrderValid(_orders[i]);
        }

        return result;
    }

    //////////
    // Main //
    //////////

    function claimUPremia() external {
        uint256 amount = uPremiaBalance[msg.sender];
        uPremiaBalance[msg.sender] = 0;
        IERC20Extended(address(uPremia)).safeTransfer(msg.sender, amount);
    }

    // Maker, salt and expirationTime will be overridden by this function
    function createOrder(Order memory _order, uint256 _amount) public returns(bytes32) {
        require(_whitelistedOptionContracts.contains(_order.optionContract), "Option contract not whitelisted");
        require(_whitelistedPaymentTokens.contains(_order.paymentToken), "Payment token not whitelisted");

        IPremiaOption.OptionData memory data = IPremiaOption(_order.optionContract).optionData(_order.optionId);
        require(block.timestamp < data.expiration, "Option expired");

        _order.maker = msg.sender;
        _order.expirationTime = data.expiration;
        _order.salt = salt;
        _order.decimals = IERC20Extended(data.token).decimals();

        salt = salt.add(1);

        bytes32 hash = getOrderHash(_order);
        amounts[hash] = _amount;

        emit OrderCreated(
            hash,
            _order.maker,
            _order.optionContract,
            _order.side,
            _order.taker,
            _order.optionId,
            _order.paymentToken,
            _order.pricePerUnit,
            _order.decimals,
            _order.expirationTime,
            _order.salt,
            _amount
        );

        return hash;
    }

    function createOrderForNewOption(Order memory _order, uint256 _amount, Option memory _option) public returns(bytes32) {
        _order.optionId = IPremiaOption(_order.optionContract).getOptionIdOrCreate(_option.token, _option.expiration, _option.strikePrice, _option.isCall);
        return createOrder(_order, _amount);
    }

    function createOrders(Order[] memory _orders, uint256[] memory _amounts) external returns(bytes32[] memory) {
        require(_orders.length == _amounts.length, "Arrays must have same length");

        bytes32[] memory result = new bytes32[](_orders.length);

        for (uint256 i=0; i < _orders.length; i++) {
            result[i] = createOrder(_orders[i], _amounts[i]);
        }

        return result;
    }

    // Will try to fill orderCandidates. If it cannot fill _amount, it will create a new order for the remaining amount to fill
    function createOrderAndTryToFill(Order memory _order, uint256 _amount, Order[] memory _orderCandidates) external {
        require(_amount > 0, "Amount must be > 0");

        // Ensure candidate orders are valid
        for (uint256 i=0; i < _orderCandidates.length; i++) {
            require(_orderCandidates[i].side != _order.side, "Candidate order : Same order side");
            require(_orderCandidates[i].optionContract == _order.optionContract, "Candidate order : Diff option contract");
            require(_orderCandidates[i].optionId == _order.optionId, "Candidate order : Diff optionId");
        }

        uint256 totalFilled;
        if (_orderCandidates.length == 1) {
            totalFilled = fillOrder(_orderCandidates[0], _amount);
        } else if (_orderCandidates.length > 1) {
            totalFilled = fillOrders(_orderCandidates, _amount);
        }

        if (totalFilled < _amount) {
            createOrder(_order, _amount.sub(totalFilled));
        }
    }

    function writeAndFillOrder(Order memory _order, uint256 _maxAmount, address _referrer) public returns(uint256) {
        bytes32 hash = getOrderHash(_order);

        // If nothing left to fill, return
        if (amounts[hash] == 0) return 0;

        uint256 amount = _maxAmount;
        if (amounts[hash] < amount) {
            amount = amounts[hash];
        }

        IPremiaOption optionContract = IPremiaOption(_order.optionContract);
        IPremiaOption.OptionData memory data = optionContract.optionData(_order.optionId);

        IPremiaOption.OptionWriteArgs memory writeArgs = IPremiaOption.OptionWriteArgs({
            token: data.token,
            amount: amount,
            strikePrice: data.strikePrice,
            expiration: data.expiration,
            isCall: data.isCall
        });

        optionContract.writeOptionFrom(msg.sender, writeArgs, _referrer);
        return fillOrder(_order, _maxAmount);
    }

    /**
     * @dev Fill an existing order
     * @param _order The order
     * @param _amount Max amount of options to buy/sell
     */
    function fillOrder(Order memory _order, uint256 _amount) public nonReentrant returns(uint256) {
        bytes32 hash = getOrderHash(_order);

        require(_order.expirationTime != 0 && block.timestamp < _order.expirationTime, "Order expired");
        require(amounts[hash] > 0, "Order not found");
        require(_amount > 0, "Amount must be > 0");
        require(_order.taker == address(0) || _order.taker == msg.sender, "Not specified taker");

        if (amounts[hash] < _amount) {
            _amount = amounts[hash];
        }

        amounts[hash] = amounts[hash].sub(_amount);

        uint256 basePrice = _order.pricePerUnit.mul(_amount).div(10 ** _order.decimals);

        (uint256 orderMakerFee,) = feeCalculator.getFeeAmounts(_order.maker, false, basePrice, IFeeCalculator.FeeType.Maker);
        (uint256 orderTakerFee,) = feeCalculator.getFeeAmounts(msg.sender, false, basePrice, IFeeCalculator.FeeType.Taker);

        if (_order.side == SaleSide.Buy) {
            IPremiaOption(_order.optionContract).safeTransferFrom(msg.sender, _order.maker, _order.optionId, _amount, "");

            IERC20Extended(_order.paymentToken).safeTransferFrom(_order.maker, feeRecipient, orderMakerFee.add(orderTakerFee));
            IERC20Extended(_order.paymentToken).safeTransferFrom(_order.maker, msg.sender, basePrice.sub(orderTakerFee));

        } else {
            IERC20Extended(_order.paymentToken).safeTransferFrom(msg.sender, feeRecipient, orderMakerFee.add(orderTakerFee));
            IERC20Extended(_order.paymentToken).safeTransferFrom(msg.sender, _order.maker, basePrice.sub(orderMakerFee));

            IPremiaOption(_order.optionContract).safeTransferFrom(_order.maker, msg.sender, _order.optionId, _amount, "");
        }

        uint256 paymentTokenPrice = uPremia.getTokenPrice(_order.paymentToken);

        // Mint uPremia
        if (address(uPremia) != address(0)) {
            uPremiaBalance[_order.maker] = uPremiaBalance[_order.maker].add(orderMakerFee.mul(paymentTokenPrice).div(1e18));
            uPremiaBalance[msg.sender] = uPremiaBalance[msg.sender].add(orderTakerFee.mul(paymentTokenPrice).div(1e18));
        }

        uPremia.mint(address(this), orderMakerFee.add(orderTakerFee).mul(paymentTokenPrice).div(1e18));

        emit OrderFilled(
            hash,
            msg.sender,
            _order.optionContract,
            _order.maker,
            _order.paymentToken,
            _amount,
            _order.pricePerUnit,
            _order.decimals
        );

        return _amount;
    }

    /**
     * @dev Fill a list of existing orders
     * @param _orders The orders
     * @param _maxAmount Max amount of options to buy/sell
     */
    function fillOrders(Order[] memory _orders, uint256 _maxAmount) public returns(uint256) {
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

        uint256 paymentTokenPrice = uPremia.getTokenPrice(_orders[0].paymentToken);

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
            // If order reserved for someone, continue
            if (_order.taker != address(0) && _order.taker != msg.sender) continue;

            uint256 amount = amounts[hash];
            if (amountFilled.add(amount) > _maxAmount) {
                amount = _maxAmount.sub(amountFilled);
            }

            amounts[hash] = amounts[hash].sub(amount);
            amountFilled = amountFilled.add(amount);

            uint256 basePrice = _order.pricePerUnit.mul(amount).div(10 ** _order.decimals);

            (uint256 orderMakerFee,) = feeCalculator.getFeeAmounts(_order.maker, false, basePrice, IFeeCalculator.FeeType.Maker);
            uint256 orderTakerFee = basePrice.mul(takerFee).div(_inverseBasisPoint);

            totalFee = totalFee.add(orderMakerFee).add(orderTakerFee);

            if (_order.side == SaleSide.Buy) {
                IPremiaOption(_order.optionContract).safeTransferFrom(msg.sender, _order.maker, _order.optionId, amount, "");

                // We transfer all to the contract, contract will pays fees, and send remainder to msg.sender
                IERC20Extended(_order.paymentToken).safeTransferFrom(_order.maker, address(this), basePrice.add(orderMakerFee));
                totalAmount = totalAmount.add(basePrice.add(orderMakerFee));

            } else {
                // We pay order maker, fees will be all paid at once later
                IERC20Extended(_order.paymentToken).safeTransferFrom(msg.sender, _order.maker, basePrice.sub(orderMakerFee));
                IPremiaOption(_order.optionContract).safeTransferFrom(_order.maker, msg.sender, _order.optionId, amount, "");
            }

            // Mint uPremia
            if (address(uPremia) != address(0)) {
                uPremiaBalance[_order.maker] = uPremiaBalance[_order.maker].add(orderMakerFee.mul(paymentTokenPrice).div(1e18));
                uPremiaBalance[msg.sender] = uPremiaBalance[msg.sender].add(orderTakerFee.mul(paymentTokenPrice).div(1e18));
            }

            emit OrderFilled(
                hash,
                msg.sender,
                _order.optionContract,
                _order.maker,
                _order.paymentToken,
                amount,
                _order.pricePerUnit,
                _order.decimals
            );
        }

        if (_orders[0].side == SaleSide.Buy) {
            // Batch payment of fees
            IERC20Extended(_orders[0].paymentToken).safeTransfer(feeRecipient, totalFee);
            // Send remainder of tokens after fee payment, to msg.sender
            IERC20Extended(_orders[0].paymentToken).safeTransfer(msg.sender, totalAmount.sub(totalFee));
        } else {
            // Batch payment of fees
            IERC20Extended(_orders[0].paymentToken).safeTransferFrom(msg.sender, feeRecipient, totalFee);
        }

        uPremia.mint(address(this), totalFee.mul(paymentTokenPrice).div(1e18));

        return amountFilled;
    }

    /**
     * @dev Cancel an existing order
     * @param _order The order
     */
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
            _order.pricePerUnit,
            _order.decimals
        );
    }

    /**
     * @dev Cancel a list of existing orders
     * @param _orders The orders
     */
    function cancelOrders(Order[] memory _orders) external {
        for (uint256 i=0; i < _orders.length; i++) {
            cancelOrder(_orders[i]);
        }
    }

}