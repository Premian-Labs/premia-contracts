// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/math/SafeCast.sol';

import "./interface/IERC20Extended.sol";
import "./interface/IFeeCalculator.sol";
import "./interface/IFlashLoanReceiver.sol";
import "./interface/IPremiaReferral.sol";

import "./uniswapV2/interfaces/IUniswapV2Router02.sol";


/// @author Premia
/// @title An option contract
contract PremiaOption is Ownable, ERC1155, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct OptionWriteArgs {
        address token;                  // Token address
        uint256 amount;                 // Amount of tokens to write option for
        uint256 strikePrice;            // Strike price (Must follow strikePriceIncrement of token)
        uint256 expiration;             // Expiration timestamp of the option (Must follow expirationIncrement)
        bool isCall;                    // If true : Call option | If false : Put option
    }

    struct OptionData {
        address token;                  // Token address
        uint256 strikePrice;            // Strike price (Must follow strikePriceIncrement of token)
        uint256 expiration;             // Expiration timestamp of the option (Must follow expirationIncrement)
        bool isCall;                    // If true : Call option | If false : Put option
        uint256 claimsPreExp;           // Amount of options from which the funds have been withdrawn pre expiration
        uint256 claimsPostExp;          // Amount of options from which the funds have been withdrawn post expiration
        uint256 exercised;              // Amount of options which have been exercised
        uint256 supply;                 // Total circulating supply
        uint8 decimals;                 // Token decimals
    }

    // Total write cost = collateral + fee + feeReferrer
    struct QuoteWrite {
        address collateralToken;        // The token to deposit as collateral
        uint256 collateral;             // The amount of collateral to deposit
        uint8 collateralDecimals;       // Decimals of collateral token
        uint256 fee;                    // The amount of collateralToken needed to be paid as protocol fee
        uint256 feeReferrer;            // The amount of collateralToken which will be paid the referrer
    }

    // Total exercise cost = input + fee + feeReferrer
    struct QuoteExercise {
        address inputToken;             // Input token for exercise
        uint256 input;                  // Amount of input token to pay to exercise
        uint8 inputDecimals;            // Decimals of input token
        address outputToken;            // Output token from the exercise
        uint256 output;                 // Amount of output tokens which will be received on exercise
        uint8 outputDecimals;           // Decimals of output token
        uint256 fee;                    // The amount of inputToken needed to be paid as protocol fee
        uint256 feeReferrer;            // The amount of inputToken which will be paid to the referrer
    }

    struct Pool {
        uint256 tokenAmount;            // The amount of tokens in the option pool
        uint256 denominatorAmount;      // The amounts of denominator in the option pool
    }

    IERC20 public denominator;
    uint8 public denominatorDecimals;

    //////////////////////////////////////////////////

    // Address receiving protocol fees (PremiaMaker)
    address public feeRecipient;

    // PremiaReferral contract
    IPremiaReferral public premiaReferral;
    // FeeCalculator contract
    IFeeCalculator public feeCalculator;

    //////////////////////////////////////////////////

    // Whitelisted tokens for which options can be written (Each token must also have a non 0 strike price increment to be enabled)
    address[] public tokens;
    // Strike price increment mapping of each token
    mapping (address => uint256) public tokenStrikeIncrement;

    //////////////////////////////////////////////////

    // The option id of next option type which will be created
    uint256 public nextOptionId = 1;

    // Offset to add to Unix timestamp to make it Fri 23:59:59 UTC
    uint256 private constant _baseExpiration = 172799;
    // Expiration increment
    uint256 private constant _expirationIncrement = 1 weeks;
    // Max expiration time from now
    uint256 public maxExpiration = 365 days;

    // Uniswap routers allowed to be used for swap from flashExercise
    address[] public whitelistedUniswapRouters;

    // token => expiration => strikePrice => isCall (1 for call, 0 for put) => optionId
    mapping (address => mapping(uint256 => mapping(uint256 => mapping (bool => uint256)))) public options;

    // optionId => OptionData
    mapping (uint256 => OptionData) public optionData;

    // optionId => Pool
    mapping (uint256 => Pool) public pools;

    // account => optionId => amount of options written
    mapping (address => mapping (uint256 => uint256)) public nbWritten;

    ////////////
    // Events //
    ////////////

    event SetToken(address indexed token, uint256 strikePriceIncrement);
    event OptionIdCreated(uint256 indexed optionId, address indexed token);
    event OptionWritten(address indexed owner, uint256 indexed optionId, address indexed token, uint256 amount);
    event OptionCancelled(address indexed owner, uint256 indexed optionId, address indexed token, uint256 amount);
    event OptionExercised(address indexed user, uint256 indexed optionId, address indexed token, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed optionId, address indexed token, uint256 amount);
    event FeePaid(address indexed user, address indexed token, address indexed referrer, uint256 feeProtocol, uint256 feeReferrer);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    /// @param _uri URI of ERC1155 metadata
    /// @param _denominator The token used as denominator
    /// @param _feeCalculator FeeCalculator contract
    /// @param _premiaReferral PremiaReferral contract
    /// @param _feeRecipient Recipient of protocol fees (PremiaMaker)
    constructor(string memory _uri, IERC20 _denominator, IFeeCalculator _feeCalculator,
        IPremiaReferral _premiaReferral, address _feeRecipient) ERC1155(_uri) {
        denominator = _denominator;
        feeCalculator = _feeCalculator;
        feeRecipient = _feeRecipient;
        premiaReferral = _premiaReferral;
        denominatorDecimals = IERC20Extended(address(_denominator)).decimals();
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////////
    // Modifiers //
    ///////////////

    modifier notExpired(uint256 _optionId) {
        require(block.timestamp < optionData[_optionId].expiration, "Expired");
        _;
    }

    modifier expired(uint256 _optionId) {
        require(block.timestamp >= optionData[_optionId].expiration, "Not expired");
        _;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    /// @notice Set new URI for ERC1155 metadata
    /// @param _newUri The new URI
    function setURI(string memory _newUri) external onlyOwner {
        _setURI(_newUri);
    }

    /// @notice Set new protocol fee recipient
    /// @param _feeRecipient The new protocol fee recipient
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    /// @notice Set a new max expiration date for options writing (By default, 1 year from current date)
    /// @param _max The max amount of seconds in the future for which an option expiration can be set
    function setMaxExpiration(uint256 _max) external onlyOwner {
        maxExpiration = _max;
    }

    /// @notice Set a new PremiaReferral contract
    /// @param _premiaReferral The new PremiaReferral Contract
    function setPremiaReferral(IPremiaReferral _premiaReferral) external onlyOwner {
        premiaReferral = _premiaReferral;
    }

    /// @notice Set a new FeeCalculator contract
    /// @param _feeCalculator The new FeeCalculator Contract
    function setFeeCalculator(IFeeCalculator _feeCalculator) external onlyOwner {
        feeCalculator = _feeCalculator;
    }

    /// @notice Set settings for tokens to support writing of options paired to denominator
    /// @dev A value of 0 means this token is disabled and options cannot be written for it
    /// @param _tokens The list of tokens for which to set strike price increment
    /// @param _strikePriceIncrement The new strike price increment to set for each token
    function setTokens(address[] memory _tokens, uint256[] memory _strikePriceIncrement) external onlyOwner {
        require(_tokens.length == _strikePriceIncrement.length);

        for (uint256 i=0; i < _tokens.length; i++) {
            if (!_isInArray(_tokens[i], tokens)) {
                tokens.push(_tokens[i]);
            }

            require(_tokens[i] != address(denominator), "Cant add denominator");
            tokenStrikeIncrement[_tokens[i]] = _strikePriceIncrement[i];

            emit SetToken(_tokens[i], _strikePriceIncrement[i]);
        }
    }

    /// @notice Set a new list of whitelisted UniswapRouter contracts allowed to be used for flashExercise
    /// @param _addrList The new list of whitelisted routers
    function setWhitelistedUniswapRouters(address[] memory _addrList) external onlyOwner {
        delete whitelistedUniswapRouters;

        for (uint256 i=0; i < _addrList.length; i++) {
            whitelistedUniswapRouters.push(_addrList[i]);
        }
    }

    //////////////////////////////////////////////////

    //////////
    // View //
    //////////

    /// @notice Get the id of an option
    /// @param _token Token for which the option is for
    /// @param _expiration Expiration timestamp of the option
    /// @param _strikePrice Strike price of the option
    /// @param _isCall Whether the option is a call or a put
    /// @return The option id
    function getOptionId(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall) public view returns(uint256) {
        return options[_token][_expiration][_strikePrice][_isCall];
    }

    /// @notice Get the amount of whitelisted tokens
    /// @return The amount of whitelisted tokens
    function tokensLength() external view returns(uint256) {
        return tokens.length;
    }

    /// @notice Get a quote to write an option
    /// @param _from Address which will write the option
    /// @param _option The option to write
    /// @param _referrer Referrer
    /// @param _decimals The option token decimals
    /// @return The quote
    function getWriteQuote(address _from, OptionWriteArgs memory _option, address _referrer, uint8 _decimals) public view returns(QuoteWrite memory) {
        QuoteWrite memory quote;

        if (_option.isCall) {
            quote.collateralToken = _option.token;
            quote.collateral = _option.amount;
            quote.collateralDecimals = _decimals;
        } else {
            quote.collateralToken = address(denominator);
            quote.collateral = _option.amount.mul(_option.strikePrice).div(10**_decimals);
            quote.collateralDecimals = denominatorDecimals;
        }

        (uint256 fee, uint256 feeReferrer) = feeCalculator.getFeeAmounts(_from, _referrer != address(0), quote.collateral, IFeeCalculator.FeeType.Write);
        quote.fee = fee;
        quote.feeReferrer = feeReferrer;

        return quote;
    }

    /// @notice Get a quote to exercise an option
    /// @param _from Address which will exercise the option
    /// @param _option The option to exercise
    /// @param _referrer Referrer
    /// @param _decimals The option token decimals
    /// @return The quote
    function getExerciseQuote(address _from, OptionData memory _option, uint256 _amount, address _referrer, uint8 _decimals) public view returns(QuoteExercise memory) {
        QuoteExercise memory quote;

        uint256 tokenAmount = _amount;
        uint256 denominatorAmount = _amount.mul(_option.strikePrice).div(10**_decimals);

        if (_option.isCall) {
            quote.inputToken = address(denominator);
            quote.input = denominatorAmount;
            quote.inputDecimals = denominatorDecimals;
            quote.outputToken = _option.token;
            quote.output = tokenAmount;
            quote.outputDecimals = _option.decimals;
        } else {
            quote.inputToken = _option.token;
            quote.input = tokenAmount;
            quote.inputDecimals = _option.decimals;
            quote.outputToken = address(denominator);
            quote.output = denominatorAmount;
            quote.outputDecimals = denominatorDecimals;
        }

        (uint256 fee, uint256 feeReferrer) = feeCalculator.getFeeAmounts(_from, _referrer != address(0), quote.input, IFeeCalculator.FeeType.Exercise);
        quote.fee = fee;
        quote.feeReferrer = feeReferrer;

        return quote;
    }

    //////////////////////////////////////////////////

    //////////
    // Main //
    //////////

    /// @notice Get the id of the option, or create a new id if there is no existing id for it
    /// @param _token Token for which the option is for
    /// @param _expiration Expiration timestamp of the option
    /// @param _strikePrice Strike price of the option
    /// @param _isCall Whether the option is a call or a put
    /// @return The option id
    function getOptionIdOrCreate(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall) public returns(uint256) {
        uint256 optionId = getOptionId(_token, _expiration, _strikePrice, _isCall);

        if (optionId == 0) {
            _preCheckOptionIdCreate(_token, _strikePrice, _expiration);

            optionId = nextOptionId;
            options[_token][_expiration][_strikePrice][_isCall] = optionId;
            uint8 decimals = IERC20Extended(_token).decimals();
            require(decimals <= 18, "Too many decimals");

            pools[optionId] = Pool({ tokenAmount: 0, denominatorAmount: 0 });
                optionData[optionId] = OptionData({
                token: _token,
                expiration: _expiration,
                strikePrice: _strikePrice,
                isCall: _isCall,
                claimsPreExp: 0,
                claimsPostExp: 0,
                exercised: 0,
                supply: 0,
                decimals: decimals
            });

            emit OptionIdCreated(optionId, _token);

            nextOptionId = nextOptionId.add(1);
        }

        return optionId;
    }

    //////////////////////////////////////////////////

    /// @notice Write an option on behalf of an address with an existing option id (Used by market delayed writing)
    /// @dev Requires approval on option contract + token needed to write the option
    /// @param _from Address on behalf of which the option is written
    /// @param _optionId The id of the option to write
    /// @param _amount Amount of options to write
    /// @param _referrer Referrer
    /// @return The option id
    function writeOptionWithIdFrom(address _from, uint256 _optionId, uint256 _amount, address _referrer) external returns(uint256) {
        require(isApprovedForAll(_from, msg.sender), "Not approved");

        OptionData memory data = optionData[_optionId];
        OptionWriteArgs memory writeArgs = OptionWriteArgs({
        token: data.token,
        amount: _amount,
        strikePrice: data.strikePrice,
        expiration: data.expiration,
        isCall: data.isCall
        });

        return _writeOption(_from, writeArgs, _referrer);
    }

    /// @notice Write an option on behalf of an address
    /// @dev Requires approval on option contract + token needed to write the option
    /// @param _from Address on behalf of which the option is written
    /// @param _option The option to write
    /// @param _referrer Referrer
    /// @return The option id
    function writeOptionFrom(address _from, OptionWriteArgs memory _option, address _referrer) external returns(uint256) {
        require(isApprovedForAll(_from, msg.sender), "Not approved");
        return _writeOption(_from, _option, _referrer);
    }

    /// @notice Write an option
    /// @param _option The option to write
    /// @param _referrer Referrer
    /// @return The option id
    function writeOption(OptionWriteArgs memory _option, address _referrer) public returns(uint256) {
        return _writeOption(msg.sender, _option, _referrer);
    }

    /// @notice Write an option on behalf of an address
    /// @param _from Address on behalf of which the option is written
    /// @param _option The option to write
    /// @param _referrer Referrer
    /// @return The option id
    function _writeOption(address _from, OptionWriteArgs memory _option, address _referrer) internal nonReentrant returns(uint256) {
        require(_option.amount > 0, "Amount <= 0");

        uint256 optionId = getOptionIdOrCreate(_option.token, _option.expiration, _option.strikePrice, _option.isCall);

        // Set referrer or get current if one already exists
        _referrer = _trySetReferrer(_from, _referrer);

        QuoteWrite memory quote = getWriteQuote(_from, _option, _referrer, optionData[optionId].decimals);

        IERC20(quote.collateralToken).safeTransferFrom(_from, address(this), quote.collateral);
        _payFees(_from, IERC20(quote.collateralToken), _referrer, quote.fee, quote.feeReferrer, quote.collateralDecimals);

        if (_option.isCall) {
            pools[optionId].tokenAmount = pools[optionId].tokenAmount.add(quote.collateral);
        } else {
            pools[optionId].denominatorAmount = pools[optionId].denominatorAmount.add(quote.collateral);
        }

        nbWritten[_from][optionId] = nbWritten[_from][optionId].add(_option.amount);

        mint(_from, optionId, _option.amount);

        emit OptionWritten(_from, optionId, _option.token, _option.amount);

        return optionId;
    }

    //////////////////////////////////////////////////

    /// @notice Cancel an option on behalf of an address. This will burn the option ERC1155 and withdraw collateral.
    /// @dev Requires approval of the option contract
    ///      This is only doable by an address which wrote an amount of options >= _amount
    ///      Must be called before expiration
    /// @param _from Address on behalf of which the option is cancelled
    /// @param _optionId The id of the option to cancel
    /// @param _amount Amount to cancel
    function cancelOptionFrom(address _from, uint256 _optionId, uint256 _amount) external {
        require(isApprovedForAll(_from, msg.sender), "Not approved");
        _cancelOption(_from, _optionId, _amount);
    }

    /// @notice Cancel an option. This will burn the option ERC1155 and withdraw collateral.
    /// @dev This is only doable by an address which wrote an amount of options >= _amount
    ///      Must be called before expiration
    /// @param _optionId The id of the option to cancel
    /// @param _amount Amount to cancel
    function cancelOption(uint256 _optionId, uint256 _amount) public {
        _cancelOption(msg.sender, _optionId, _amount);
    }

    /// @notice Cancel an option on behalf of an address. This will burn the option ERC1155 and withdraw collateral.
    /// @dev This is only doable by an address which wrote an amount of options >= _amount
    ///      Must be called before expiration
    /// @param _from Address on behalf of which the option is cancelled
    /// @param _optionId The id of the option to cancel
    /// @param _amount Amount to cancel
    function _cancelOption(address _from, uint256 _optionId, uint256 _amount) internal nonReentrant {
        require(_amount > 0, "Amount <= 0");
        require(nbWritten[_from][_optionId] >= _amount, "Not enough written");

        burn(_from, _optionId, _amount);
        nbWritten[_from][_optionId] = nbWritten[_from][_optionId].sub(_amount);

        if (optionData[_optionId].isCall) {
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(_amount);
            IERC20(optionData[_optionId].token).safeTransfer(_from, _amount);
        } else {
            uint256 amount = _amount.mul(optionData[_optionId].strikePrice).div(10**optionData[_optionId].decimals);
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.sub(amount);
            denominator.safeTransfer(_from, amount);
        }

        emit OptionCancelled(_from, _optionId, optionData[_optionId].token, _amount);
    }

    //////////////////////////////////////////////////

    /// @notice Exercise an option on behalf of an address
    /// @dev Requires approval of the option contract
    /// @param _from Address on behalf of which the option will be exercised
    /// @param _optionId The id of the option to exercise
    /// @param _amount Amount to exercise
    /// @param _referrer Referrer
    function exerciseOptionFrom(address _from, uint256 _optionId, uint256 _amount, address _referrer) external {
        require(isApprovedForAll(_from, msg.sender), "Not approved");
        _exerciseOption(_from, _optionId, _amount, _referrer);
    }

    /// @notice Exercise an option
    /// @param _optionId The id of the option to exercise
    /// @param _amount Amount to exercise
    /// @param _referrer Referrer
    function exerciseOption(uint256 _optionId, uint256 _amount, address _referrer) public {
        _exerciseOption(msg.sender, _optionId, _amount, _referrer);
    }

    /// @notice Exercise an option on behalf of an address
    /// @param _from Address on behalf of which the option will be exercised
    /// @param _optionId The id of the option to exercise
    /// @param _amount Amount to exercise
    /// @param _referrer Referrer
    function _exerciseOption(address _from, uint256 _optionId, uint256 _amount, address _referrer) internal nonReentrant {
        require(_amount > 0, "Amount <= 0");

        OptionData storage data = optionData[_optionId];

        burn(_from, _optionId, _amount);
        data.exercised = uint256(data.exercised).add(_amount);

        // Set referrer or get current if one already exists
        _referrer = _trySetReferrer(_from, _referrer);

        QuoteExercise memory quote = getExerciseQuote(_from, data, _amount, _referrer, data.decimals);
        IERC20(quote.inputToken).safeTransferFrom(_from, address(this), quote.input);
        _payFees(_from, IERC20(quote.inputToken), _referrer, quote.fee, quote.feeReferrer, quote.inputDecimals);

        if (data.isCall) {
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(quote.output);
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.add(quote.input);
        } else {
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.sub(quote.output);
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.add(quote.input);
        }

        IERC20(quote.outputToken).safeTransfer(_from, quote.output);

        emit OptionExercised(_from, _optionId, data.token, _amount);
    }

    //////////////////////////////////////////////////

    /// @notice Withdraw collateral from an option post expiration on behalf of an address.
    ///         (Funds will be send to the address on behalf of which withdrawal is made)
    ///         Funds in the option pool will be distributed pro rata of amount of options written by the address
    ///         Ex : If after expiration date there has been 10 options written and there is 1 eth and 1000 DAI in the pool,
    ///              Withdraw for each option will be worth 0.1 eth and 100 dai
    /// @dev Only callable by addresses which have unclaimed funds for options they wrote
    ///      Requires approval of the option contract
    /// @param _from Address on behalf of which the withdraw call is made (Which will receive the withdrawn funds)
    /// @param _optionId The id of the option to withdraw funds from
    function withdrawFrom(address _from, uint256 _optionId) external {
        require(isApprovedForAll(_from, msg.sender), "Not approved");
        _withdraw(_from, _optionId);
    }

    /// @notice Withdraw collateral from an option post expiration
    ///         Funds in the option pool will be distributed pro rata of amount of options written by the address
    ///         Ex : If after expiration date there has been 10 options written and there is 1 eth and 1000 DAI in the pool,
    ///              Withdraw for each option will be worth 0.1 eth and 100 dai
    /// @dev Only callable by addresses which have unclaimed funds for options they wrote
    /// @param _optionId The id of the option to withdraw funds from
    function withdraw(uint256 _optionId) public {
        _withdraw(msg.sender, _optionId);
    }

    /// @notice Withdraw collateral from an option post expiration on behalf of an address.
    ///         (Funds will be send to the address on behalf of which withdrawal is made)
    ///         Funds in the option pool will be distributed pro rata of amount of options written by the address
    ///         Ex : If after expiration date there has been 10 options written and there is 1 eth and 1000 DAI in the pool,
    ///              Withdraw for each option will be worth 0.1 eth and 100 dai
    /// @dev Only callable by addresses which have unclaimed funds for options they wrote
    /// @param _from Address on behalf of which the withdraw call is made (Which will receive the withdrawn funds)
    /// @param _optionId The id of the option to withdraw funds from
    function _withdraw(address _from, uint256 _optionId) internal nonReentrant expired(_optionId) {
        require(nbWritten[_from][_optionId] > 0, "No option to claim");

        OptionData storage data = optionData[_optionId];

        uint256 nbTotal = uint256(data.supply).add(data.exercised).sub(data.claimsPreExp);

        // Amount of options user still has to claim funds from
        uint256 claimsUser = nbWritten[_from][_optionId];

        //

        uint256 denominatorAmount = pools[_optionId].denominatorAmount.mul(claimsUser).div(nbTotal);
        uint256 tokenAmount = pools[_optionId].tokenAmount.mul(claimsUser).div(nbTotal);

        //

        pools[_optionId].denominatorAmount.sub(denominatorAmount);
        pools[_optionId].tokenAmount.sub(tokenAmount);
        data.claimsPostExp = uint256(data.claimsPostExp).add(claimsUser);
        delete nbWritten[_from][_optionId];

        if (denominatorAmount > 0) {
            denominator.safeTransfer(_from, denominatorAmount);
        }

        if (tokenAmount > 0) {
            IERC20(optionData[_optionId].token).safeTransfer(_from, tokenAmount);
        }

        emit Withdraw(_from, _optionId, data.token, claimsUser);
    }

    //////////////////////////////////////////////////

    /// @notice Withdraw collateral from an option pre expiration on behalf of an address.
    ///         (Funds will be send to the address on behalf of which withdrawal is made)
    ///         Only opposite side of the collateral will be allocated when withdrawing pre expiration
    ///         If writer deposited WETH for a WETH/DAI call, he will only receive the strike amount in DAI from a pre-expiration withdrawal,
    ///         while doing a withdrawal post expiration would make him receive pro rata of funds left in the option pool at the expiration,
    ///         (Which might be both WETH and DAI if not all options have been exercised)
    ///
    /// @dev Requires approval of the option contract
    ///      Only callable by addresses which have unclaimed funds for options they wrote
    ///      This also requires options to have been exercised and not claimed
    ///      Ex : If a total of 10 options have been written (2 from Alice and 8 from Bob) and 3 options have been exercise :
    ///           - Alice will be allowed to call withdrawPreExpiration for her 2 options written
    ///           - Bob will only be allowed to call withdrawPreExpiration for 3 options he wrote
    ///           - If Alice call first withdrawPreExpiration for her 2 options,
    ///             there will be only 1 unclaimed exercised options that Bob will be allowed to withdrawPreExpiration
    ///
    /// @param _from Address on behalf of which the withdrawPreExpiration call is made (Which will receive the withdrawn funds)
    /// @param _optionId The id of the option to withdraw funds from
    /// @param _amount The amount of options for which withdrawPreExpiration
    function withdrawPreExpirationFrom(address _from, uint256 _optionId, uint256 _amount) external {
        require(isApprovedForAll(_from, msg.sender), "Not approved");
        _withdrawPreExpiration(_from, _optionId, _amount);
    }

    /// @notice Withdraw collateral from an option pre expiration
    ///         (Funds will be send to the address on behalf of which withdrawal is made)
    ///         Only opposite side of the collateral will be allocated when withdrawing pre expiration
    ///         If writer deposited WETH for a WETH/DAI call, he will only receive the strike amount in DAI from a pre-expiration withdrawal,
    ///         while doing a withdrawal post expiration would make him receive pro rata of funds left in the option pool at the expiration,
    ///         (Which might be both WETH and DAI if not all options have been exercised)
    ///
    /// @dev Only callable by addresses which have unclaimed funds for options they wrote
    ///      This also requires options to have been exercised and not claimed
    ///      Ex : If a total of 10 options have been written (2 from Alice and 8 from Bob) and 3 options have been exercise :
    ///           - Alice will be allowed to call withdrawPreExpiration for her 2 options written
    ///           - Bob will only be allowed to call withdrawPreExpiration for 3 options he wrote
    ///           - If Alice call first withdrawPreExpiration for her 2 options,
    ///             there will be only 1 unclaimed exercised options that Bob will be allowed to withdrawPreExpiration
    ///
    /// @param _optionId The id of the option to exercise
    /// @param _amount The amount of options for which withdrawPreExpiration
    function withdrawPreExpiration(uint256 _optionId, uint256 _amount) public {
        _withdrawPreExpiration(msg.sender, _optionId, _amount);
    }

    /// @notice Withdraw collateral from an option pre expiration on behalf of an address.
    ///         (Funds will be send to the address on behalf of which withdrawal is made)
    ///         Only opposite side of the collateral will be allocated when withdrawing pre expiration
    ///         If writer deposited WETH for a WETH/DAI call, he will only receive the strike amount in DAI from a pre-expiration withdrawal,
    ///         while doing a withdrawal post expiration would make him receive pro rata of funds left in the option pool at the expiration,
    ///         (Which might be both WETH and DAI if not all options have been exercised)
    ///
    /// @dev Only callable by addresses which have unclaimed funds for options they wrote
    ///      This also requires options to have been exercised and not claimed
    ///      Ex : If a total of 10 options have been written (2 from Alice and 8 from Bob) and 3 options have been exercise :
    ///           - Alice will be allowed to call withdrawPreExpiration for her 2 options written
    ///           - Bob will only be allowed to call withdrawPreExpiration for 3 options he wrote
    ///           - If Alice call first withdrawPreExpiration for her 2 options,
    ///             there will be only 1 unclaimed exercised options that Bob will be allowed to withdrawPreExpiration
    ///
    /// @param _from Address on behalf of which the withdrawPreExpiration call is made (Which will receive the withdrawn funds)
    /// @param _optionId The id of the option to withdraw funds from
    /// @param _amount The amount of options for which withdrawPreExpiration
    function _withdrawPreExpiration(address _from, uint256 _optionId, uint256 _amount) internal nonReentrant notExpired(_optionId) {
        require(_amount > 0, "Amount <= 0");

        // Amount of options user still has to claim funds from
        uint256 claimsUser = nbWritten[_from][_optionId];
        require(claimsUser >= _amount, "Not enough claims");

        OptionData storage data = optionData[_optionId];

        uint256 nbClaimable = uint256(data.exercised).sub(data.claimsPreExp);
        require(nbClaimable >= _amount, "Not enough claimable");

        //

        nbWritten[_from][_optionId] = nbWritten[_from][_optionId].sub(_amount);
        data.claimsPreExp = uint256(data.claimsPreExp).add(_amount);

        if (data.isCall) {
            uint256 amount = _amount.mul(data.strikePrice).div(10**data.decimals);
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.sub(amount);
            denominator.safeTransfer(_from, amount);
        } else {
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(_amount);
            IERC20(data.token).safeTransfer(_from, _amount);
        }
    }

    //////////////////////////////////////////////////

    /// @notice Flash exercise an option on behalf of an address
    ///         This is usable on options in the money, in order to use a portion of the option collateral
    ///         to swap a portion of it to the token required to exercise the option and pay protocol fees,
    ///         and send the profit to the address exercising.
    ///         This allows any option in the money to be exercised without the need of owning the token needed to exercise
    /// @dev Requires approval of the option contract
    /// @param _from Address on behalf of which the flash exercise is made (Which will receive the profit)
    /// @param _optionId The id of the option to flash exercise
    /// @param _amount Amount of option to flash exercise
    /// @param _referrer Referrer
    /// @param _router The UniswapRouter used to perform the swap (Needs to be a whitelisted router)
    /// @param _amountInMax Max amount of collateral token to use for the swap, for the tx to not be reverted
    /// @param _path Path used for the routing of the swap
    function flashExerciseOptionFrom(address _from, uint256 _optionId, uint256 _amount, address _referrer, IUniswapV2Router02 _router, uint256 _amountInMax, address[] memory _path) external {
        require(isApprovedForAll(_from, msg.sender), "Not approved");
        _flashExerciseOption(_from, _optionId, _amount, _referrer, _router, _amountInMax, _path);
    }

    /// @notice Flash exercise an option
    ///         This is usable on options in the money, in order to use a portion of the option collateral
    ///         to swap a portion of it to the token required to exercise the option and pay protocol fees,
    ///         and send the profit to the address exercising.
    ///         This allows any option in the money to be exercised without the need of owning the token needed to exercise
    /// @param _optionId The id of the option to flash exercise
    /// @param _amount Amount of option to flash exercise
    /// @param _referrer Referrer
    /// @param _router The UniswapRouter used to perform the swap (Needs to be a whitelisted router)
    /// @param _amountInMax Max amount of collateral token to use for the swap, for the tx to not be reverted
    /// @param _path Path used for the routing of the swap
    function flashExerciseOption(uint256 _optionId, uint256 _amount, address _referrer, IUniswapV2Router02 _router, uint256 _amountInMax, address[] memory _path) external {
        _flashExerciseOption(msg.sender, _optionId, _amount, _referrer, _router, _amountInMax, _path);
    }

    /// @notice Flash exercise an option on behalf of an address
    ///         This is usable on options in the money, in order to use a portion of the option collateral
    ///         to swap a portion of it to the token required to exercise the option and pay protocol fees,
    ///         and send the profit to the address exercising.
    ///         This allows any option in the money to be exercised without the need of owning the token needed to exercise
    /// @dev Requires approval of the option contract
    /// @param _from Address on behalf of which the flash exercise is made (Which will receive the profit)
    /// @param _optionId The id of the option to flash exercise
    /// @param _amount Amount of option to flash exercise
    /// @param _referrer Referrer
    /// @param _router The UniswapRouter used to perform the swap (Needs to be a whitelisted router)
    /// @param _amountInMax Max amount of collateral token to use for the swap, for the tx to not be reverted
    /// @param _path Path used for the routing of the swap
    function _flashExerciseOption(address _from, uint256 _optionId, uint256 _amount, address _referrer, IUniswapV2Router02 _router, uint256 _amountInMax, address[] memory _path) internal nonReentrant {
        require(_amount > 0, "Amount <= 0");

        burn(_from, _optionId, _amount);
        optionData[_optionId].exercised = uint256(optionData[_optionId].exercised).add(_amount);

        // Set referrer or get current if one already exists
        _referrer = _trySetReferrer(_from, _referrer);

        QuoteExercise memory quote = getExerciseQuote(_from, optionData[_optionId], _amount, _referrer, optionData[_optionId].decimals);

        IERC20 tokenErc20 = IERC20(optionData[_optionId].token);

        uint256 tokenAmountRequired = tokenErc20.balanceOf(address(this));
        uint256 denominatorAmountRequired = denominator.balanceOf(address(this));

        if (optionData[_optionId].isCall) {
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(quote.output);
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.add(quote.input);
        } else {
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.sub(quote.output);
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.add(quote.input);
        }

        //

        if (quote.output < _amountInMax) {
            _amountInMax = quote.output;
        }

        // Swap enough denominator to tokenErc20 to pay fee + strike price
        uint256 tokenAmountUsed = _swap(_router, quote.outputToken, quote.inputToken, quote.input.add(quote.fee).add(quote.feeReferrer), _amountInMax, _path)[0];

        // Pay fees
        _payFees(address(this), IERC20(quote.inputToken), _referrer, quote.fee, quote.feeReferrer, quote.inputDecimals);

        uint256 profit = quote.output.sub(tokenAmountUsed);

        // Send profit to sender
        IERC20(quote.outputToken).safeTransfer(_from, profit);

        //

        if (optionData[_optionId].isCall) {
            denominatorAmountRequired = denominatorAmountRequired.add(quote.input);
            tokenAmountRequired = tokenAmountRequired.sub(quote.output);
        } else {
            denominatorAmountRequired = denominatorAmountRequired.sub(quote.output);
            tokenAmountRequired = tokenAmountRequired.add(quote.input);
        }

        require(denominator.balanceOf(address(this)) >= denominatorAmountRequired, "Wrong denom bal");
        require(tokenErc20.balanceOf(address(this)) >= tokenAmountRequired, "Wrong token bal");

        emit OptionExercised(_from, _optionId, optionData[_optionId].token, _amount);
    }

    //////////////////////////////////////////////////

    /// @notice Flash loan collaterals sitting in this contract
    ///         Loaned amount + fee must be repaid by the end of the transaction for the transaction to not be reverted
    /// @param _tokenAddress Token to flashLoan
    /// @param _amount Amount to flashLoan
    /// @param _receiver Receiver of the flashLoan
    function flashLoan(address _tokenAddress, uint256 _amount, IFlashLoanReceiver _receiver) public nonReentrant {
        IERC20 _token = IERC20(_tokenAddress);
        uint256 startBalance = _token.balanceOf(address(this));
        _token.safeTransfer(address(_receiver), _amount);

        (uint256 fee,) = feeCalculator.getFeeAmounts(msg.sender, false, _amount, IFeeCalculator.FeeType.FlashLoan);

        _receiver.execute(_tokenAddress, _amount, _amount.add(fee));

        uint256 endBalance = _token.balanceOf(address(this));

        uint256 endBalanceRequired = startBalance.add(fee);

        require(endBalance >= endBalanceRequired, "Failed to pay back");
        _token.safeTransfer(feeRecipient, endBalance.sub(startBalance));

        endBalance = _token.balanceOf(address(this));
        require(endBalance >= startBalance, "Failed to pay back");
    }

    //////////////////////////////////////////////////

    //////////////
    // Internal //
    //////////////

    /// @notice Mint ERC1155 representing the option
    /// @dev Requires option to not be expired
    /// @param _account Address for which ERC1155 is minted
    /// @param _amount Amount minted
    function mint(address _account, uint256 _id, uint256 _amount) internal notExpired(_id) {
        OptionData storage data = optionData[_id];

        _mint(_account, _id, _amount, "");
        data.supply = uint256(data.supply).add(_amount);
    }

    /// @notice Burn ERC1155 representing the option
    /// @param _account Address from which ERC1155 is burnt
    /// @param _amount Amount burnt
    function burn(address _account, uint256 _id, uint256 _amount) internal notExpired(_id) {
        OptionData storage data = optionData[_id];

        data.supply = uint256(data.supply).sub(_amount);
        _burn(_account, _id, _amount);
    }

    /// @notice Utility function to check if a value is inside an array
    /// @param _value The value to look for
    /// @param _array The array to check
    /// @return Whether the value is in the array or not
    function _isInArray(address _value, address[] memory _array) internal pure returns(bool) {
        uint256 length = _array.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_array[i] == _value) {
                return true;
            }
        }

        return false;
    }

    /// @notice Pay protocol fees
    /// @param _from Address paying protocol fees
    /// @param _token The token in which protocol fees are paid
    /// @param _referrer The referrer of _from
    /// @param _fee Protocol fee to pay to feeRecipient
    /// @param _feeReferrer Fee to pay to referrer
    /// @param _decimals Token decimals
    function _payFees(address _from, IERC20 _token, address _referrer, uint256 _fee, uint256 _feeReferrer, uint8 _decimals) internal {
        if (_fee > 0) {
            // For flash exercise
            if (_from == address(this)) {
                _token.safeTransfer(feeRecipient, _fee);
            } else {
                _token.safeTransferFrom(_from, feeRecipient, _fee);
            }

        }

        if (_feeReferrer > 0) {
            // For flash exercise
            if (_from == address(this)) {
                _token.safeTransfer(_referrer, _feeReferrer);
            } else {
                _token.safeTransferFrom(_from, _referrer, _feeReferrer);
            }
        }

        emit FeePaid(_from, address(_token), _referrer, _fee, _feeReferrer);
    }

    /// @notice Try to set given referrer, returns current referrer if one already exists
    /// @param _user Address for which we try to set a referrer
    /// @param _referrer Potential referrer
    /// @return Actual referrer (Potential referrer, or actual referrer if one already exists)
    function _trySetReferrer(address _user, address _referrer) internal returns(address) {
        if (address(premiaReferral) != address(0)) {
            _referrer = premiaReferral.trySetReferrer(_user, _referrer);
        } else {
            _referrer = address(0);
        }

        return _referrer;
    }

    /// @notice Token swap (Used for flashExercise)
    /// @param _router The UniswapRouter contract to use to perform the swap (Must be whitelisted)
    /// @param _from Input token for the swap
    /// @param _to Output token of the swap
    /// @param _amount Amount of output tokens we want
    /// @param _amountInMax Max amount of input token to spend for the tx to not revert
    /// @param _path Path used for the routing of the swap
    /// @return Swap amounts
    function _swap(IUniswapV2Router02 _router, address _from, address _to, uint256 _amount, uint256 _amountInMax, address[] memory _path) internal returns (uint256[] memory) {
        require(_isInArray(address(_router), whitelistedUniswapRouters), "Router not whitelisted");

        IERC20(_from).approve(address(_router), _amountInMax);

        uint256[] memory amounts = _router.swapTokensForExactTokens(
            _amount,
            _amountInMax,
            _path,
            address(this),
            block.timestamp.add(60)
        );

        IERC20(_from).approve(address(_router), 0);

        return amounts;
    }

    /// @notice Check if option settings are valid (Reverts if not valid)
    /// @param _token Token for which option this
    /// @param _strikePrice Strike price of the option
    /// @param _expiration timestamp of the option
    function _preCheckOptionIdCreate(address _token, uint256 _strikePrice, uint256 _expiration) internal view {
        require(tokenStrikeIncrement[_token] != 0, "Token not supported");
        require(_strikePrice > 0, "Strike <= 0");
        require(_strikePrice % tokenStrikeIncrement[_token] == 0, "Wrong strike incr");
        require(_expiration > block.timestamp, "Exp passed");
        require(_expiration.sub(block.timestamp) <= maxExpiration, "Exp > 1 yr");
        require(_expiration % _expirationIncrement == _baseExpiration, "Wrong exp incr");
    }
}