// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import '@solidstate/contracts/token/ERC1155/ERC1155Base.sol';
import '@solidstate/contracts/access/Ownable.sol';
import '@solidstate/contracts/utils/ReentrancyGuard.sol';

import "../../interface/IERC20Extended.sol";
import "../../interface/IFeeCalculator.sol";
import "../../interface/IFlashLoanReceiver.sol";
import './OptionStorage.sol';

import "../../uniswapV2/interfaces/IUniswapV2Router02.sol";


/// @author Premia
/// @title An option contract
contract Option is Ownable, ERC1155Base, ReentrancyGuard {
    using OptionStorage for OptionStorage.Layout;
    using SafeERC20 for IERC20;

    // Offset to add to Unix timestamp to make it Fri 23:59:59 UTC
    uint256 private constant _baseExpiration = 172799;
    // Expiration increment
    uint256 private constant _expirationIncrement = 1 weeks;


    ////////////
    // Events //
    ////////////

    event TokenWhitelisted(address indexed token, bool whitelisted);
    event OptionIdCreated(uint256 indexed optionId, address indexed token);
    event OptionWritten(address indexed owner, uint256 indexed optionId, address indexed token, uint256 amount);
    event OptionCancelled(address indexed owner, uint256 indexed optionId, address indexed token, uint256 amount);
    event OptionExercised(address indexed user, uint256 indexed optionId, address indexed token, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed optionId, address indexed token, uint256 amount);
    event FeePaid(address indexed user, address indexed token, uint256 fee);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////////
    // Modifiers //
    ///////////////

    modifier notExpired(uint256 _optionId) {
        require(block.timestamp < OptionStorage.layout().optionData[_optionId].expiration, "Expired");
        _;
    }

    modifier expired(uint256 _optionId) {
        require(block.timestamp >= OptionStorage.layout().optionData[_optionId].expiration, "Not expired");
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
        OptionStorage.layout().uri = _newUri;
    }

    /// @notice Set new protocol fee recipient
    /// @param _feeRecipient The new protocol fee recipient
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        OptionStorage.layout().feeRecipient = _feeRecipient;
    }

    /// @notice Set a new max expiration date for options writing (By default, 1 year from current date)
    /// @param _max The max amount of seconds in the future for which an option expiration can be set
    function setMaxExpiration(uint256 _max) external onlyOwner {
        OptionStorage.layout().maxExpiration = _max;
    }

    /// @notice Set a new FeeCalculator contract
    /// @param _feeCalculator The new FeeCalculator Contract
    function setFeeCalculator(address _feeCalculator) external onlyOwner {
        OptionStorage.layout().feeCalculator = _feeCalculator;
    }

    /// @notice Set whitelisting for token
    /// @param _tokens The list of tokens for which to set strike price increment
    /// @param _whitelist Whether each token is to be added to the whitelist or removed
    function setTokensWhitelisted(address[] memory _tokens, bool _whitelist) external onlyOwner {
        OptionStorage.Layout storage l = OptionStorage.layout();

        for (uint256 i=0; i < _tokens.length; i++) {
            l.whitelistedTokens[_tokens[i]] = _whitelist;
            emit TokenWhitelisted(_tokens[i], _whitelist);
        }
    }

    /// @notice Set a new list of whitelisted UniswapRouter contracts allowed to be used for flashExercise
    /// @param _addrList The new list of whitelisted routers
    function setWhitelistedUniswapRouters(address[] memory _addrList) external onlyOwner {
        OptionStorage.Layout storage l = OptionStorage.layout();

        delete l.whitelistedUniswapRouters;

        for (uint256 i=0; i < _addrList.length; i++) {
            l.whitelistedUniswapRouters.push(_addrList[i]);
        }
    }

    //////////////////////////////////////////////////

    //////////
    // View //
    //////////

    function uri(uint256) public view returns (string memory) {
        return OptionStorage.layout().uri;
    }

    function whitelistedTokens(address _token) external view returns(bool) {
        return OptionStorage.layout().whitelistedTokens[_token];
    }

    function nbWritten(address _user, uint256 _optionId) external view returns(uint256) {
        return OptionStorage.layout().nbWritten[_user][_optionId];
    }

    function optionData(uint256 _optionId) external view returns(OptionStorage.OptionData memory) {
        return OptionStorage.layout().optionData[_optionId];
    }

    /// @notice Get the id of an option
    /// @param _token Token for which the option is for
    /// @param _expiration Expiration timestamp of the option
    /// @param _strikePrice Strike price of the option
    /// @param _isCall Whether the option is a call or a put
    /// @return The option id
    function getOptionId(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall) public view returns(uint256) {
        return OptionStorage.layout().options[_token][_expiration][_strikePrice][_isCall];
    }

    /// @notice Get a quote to write an option
    /// @param _from Address which will write the option
    /// @param _option The option to write
    /// @param _decimals The option token decimals
    /// @return The quote
    function getWriteQuote(address _from, OptionStorage.OptionWriteArgs memory _option, uint8 _decimals) public view returns(OptionStorage.QuoteWrite memory) {
        OptionStorage.Layout storage l = OptionStorage.layout();
        OptionStorage.QuoteWrite memory quote;

        if (_option.isCall) {
            quote.collateralToken = _option.token;
            quote.collateral = _option.amount;
            quote.collateralDecimals = _decimals;
        } else {
            quote.collateralToken = l.denominator;
            quote.collateral = _option.amount * _option.strikePrice / (10**_decimals);
            quote.collateralDecimals = l.denominatorDecimals;
        }

        quote.fee = IFeeCalculator(l.feeCalculator).getFeeAmount(_from, quote.collateral, IFeeCalculator.FeeType.Write);

        return quote;
    }

    /// @notice Get a quote to exercise an option
    /// @param _from Address which will exercise the option
    /// @param _option The option to exercise
    /// @param _decimals The option token decimals
    /// @return The quote
    function getExerciseQuote(address _from, OptionStorage.OptionData memory _option, uint256 _amount, uint8 _decimals) public view returns(OptionStorage.QuoteExercise memory) {
        OptionStorage.Layout storage l = OptionStorage.layout();
        OptionStorage.QuoteExercise memory quote;

        uint256 tokenAmount = _amount;
        uint256 denominatorAmount = _amount * _option.strikePrice / (10**_decimals);

        if (_option.isCall) {
            quote.inputToken = l.denominator;
            quote.input = denominatorAmount;
            quote.inputDecimals = l.denominatorDecimals;
            quote.outputToken = _option.token;
            quote.output = tokenAmount;
            quote.outputDecimals = _option.decimals;
        } else {
            quote.inputToken = _option.token;
            quote.input = tokenAmount;
            quote.inputDecimals = _option.decimals;
            quote.outputToken = l.denominator;
            quote.output = denominatorAmount;
            quote.outputDecimals = l.denominatorDecimals;
        }

        quote.fee = IFeeCalculator(l.feeCalculator).getFeeAmount(_from, quote.input, IFeeCalculator.FeeType.Exercise);

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
        OptionStorage.Layout storage l = OptionStorage.layout();

        uint256 optionId = getOptionId(_token, _expiration, _strikePrice, _isCall);

        if (optionId == 0) {
            _preCheckOptionIdCreate(_token, _strikePrice, _expiration);

            optionId = l.nextOptionId;
            l.options[_token][_expiration][_strikePrice][_isCall] = optionId;
            uint8 decimals = IERC20Extended(_token).decimals();
            require(decimals <= 18, "Too many decimals");

            l.optionData[optionId].token = _token;
            l.optionData[optionId].expiration = _expiration;
            l.optionData[optionId].strikePrice = _strikePrice;
            l.optionData[optionId].isCall = _isCall;
            l.optionData[optionId].decimals = decimals;

            emit OptionIdCreated(optionId, _token);

            l.nextOptionId += 1;
        }

        return optionId;
    }

    //////////////////////////////////////////////////

    /// @notice Write an option on behalf of an address with an existing option id (Used by market delayed writing)
    /// @dev Requires approval on option contract + token needed to write the option
    /// @param _from Address on behalf of which the option is written
    /// @param _optionId The id of the option to write
    /// @param _amount Amount of options to write
    /// @return The option id
    function writeOptionWithIdFrom(address _from, uint256 _optionId, uint256 _amount) external returns(uint256) {
        require(isApprovedForAll(_from, msg.sender), "Not approved");

        OptionStorage.OptionData memory data = OptionStorage.layout().optionData[_optionId];
        OptionStorage.OptionWriteArgs memory writeArgs = OptionStorage.OptionWriteArgs({
            token: data.token,
            amount: _amount,
            strikePrice: data.strikePrice,
            expiration: data.expiration,
            isCall: data.isCall
        });

        return _writeOption(_from, writeArgs);
    }

    /// @notice Write an option on behalf of an address
    /// @dev Requires approval on option contract + token needed to write the option
    /// @param _from Address on behalf of which the option is written
    /// @param _option The option to write
    /// @return The option id
    function writeOptionFrom(address _from, OptionStorage.OptionWriteArgs memory _option) external returns(uint256) {
        require(isApprovedForAll(_from, msg.sender), "Not approved");
        return _writeOption(_from, _option);
    }

    /// @notice Write an option
    /// @param _option The option to write
    /// @return The option id
    function writeOption(OptionStorage.OptionWriteArgs memory _option) public returns(uint256) {
        return _writeOption(msg.sender, _option);
    }

    /// @notice Write an option on behalf of an address
    /// @param _from Address on behalf of which the option is written
    /// @param _option The option to write
    /// @return The option id
    function _writeOption(address _from, OptionStorage.OptionWriteArgs memory _option) internal nonReentrant returns(uint256) {
        require(_option.amount > 0, "Amount <= 0");

        OptionStorage.Layout storage l = OptionStorage.layout();

        uint256 optionId = getOptionIdOrCreate(_option.token, _option.expiration, _option.strikePrice, _option.isCall);

        OptionStorage.QuoteWrite memory quote = getWriteQuote(_from, _option, l.optionData[optionId].decimals);

        IERC20(quote.collateralToken).safeTransferFrom(_from, address(this), quote.collateral);
        _payFees(_from, IERC20(quote.collateralToken), quote.fee);

        if (_option.isCall) {
            l.pools[optionId].tokenAmount += quote.collateral;
        } else {
            l.pools[optionId].denominatorAmount += quote.collateral;
        }

        l.nbWritten[_from][optionId] += _option.amount;

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
        OptionStorage.Layout storage l = OptionStorage.layout();

        require(_amount > 0, "Amount <= 0");
        require(l.nbWritten[_from][_optionId] >= _amount, "Not enough written");

        burn(_from, _optionId, _amount);
        l.nbWritten[_from][_optionId] -= _amount;

        if (l.optionData[_optionId].isCall) {
            l.pools[_optionId].tokenAmount -= _amount;
            IERC20(l.optionData[_optionId].token).safeTransfer(_from, _amount);
        } else {
            uint256 amount = _amount * l.optionData[_optionId].strikePrice / (10 ** l.optionData[_optionId].decimals);
            l.pools[_optionId].denominatorAmount -= amount;
            IERC20(l.denominator).safeTransfer(_from, amount);
        }

        emit OptionCancelled(_from, _optionId, l.optionData[_optionId].token, _amount);
    }

    //////////////////////////////////////////////////

    /// @notice Exercise an option on behalf of an address
    /// @dev Requires approval of the option contract
    /// @param _from Address on behalf of which the option will be exercised
    /// @param _optionId The id of the option to exercise
    /// @param _amount Amount to exercise
    function exerciseOptionFrom(address _from, uint256 _optionId, uint256 _amount) external {
        require(isApprovedForAll(_from, msg.sender), "Not approved");
        _exerciseOption(_from, _optionId, _amount);
    }

    /// @notice Exercise an option
    /// @param _optionId The id of the option to exercise
    /// @param _amount Amount to exercise
    function exerciseOption(uint256 _optionId, uint256 _amount) public {
        _exerciseOption(msg.sender, _optionId, _amount);
    }

    /// @notice Exercise an option on behalf of an address
    /// @param _from Address on behalf of which the option will be exercised
    /// @param _optionId The id of the option to exercise
    /// @param _amount Amount to exercise
    function _exerciseOption(address _from, uint256 _optionId, uint256 _amount) internal nonReentrant {
        require(_amount > 0, "Amount <= 0");

        OptionStorage.Layout storage l = OptionStorage.layout();

        OptionStorage.OptionData storage data = l.optionData[_optionId];

        burn(_from, _optionId, _amount);
        data.exercised += _amount;

        OptionStorage.QuoteExercise memory quote = getExerciseQuote(_from, data, _amount, data.decimals);
        IERC20(quote.inputToken).safeTransferFrom(_from, address(this), quote.input);
        _payFees(_from, IERC20(quote.inputToken), quote.fee);

        if (data.isCall) {
            l.pools[_optionId].tokenAmount -= quote.output;
            l.pools[_optionId].denominatorAmount += quote.input;
        } else {
            l.pools[_optionId].denominatorAmount -= quote.output;
            l.pools[_optionId].tokenAmount += quote.input;
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
        OptionStorage.Layout storage l = OptionStorage.layout();

        // Amount of options user still has to claim funds from
        uint256 claimsUser = l.nbWritten[_from][_optionId];
        require(claimsUser > 0, "No option to claim");

        OptionStorage.OptionData storage data = l.optionData[_optionId];

        uint256 nbTotal = data.supply + data.exercised - data.claimsPreExp;
        //

        uint256 denominatorAmount = l.pools[_optionId].denominatorAmount * claimsUser / nbTotal;
        uint256 tokenAmount = l.pools[_optionId].tokenAmount * claimsUser / nbTotal;

        //

        data.claimsPostExp += claimsUser;
        delete l.nbWritten[_from][_optionId];

        if (denominatorAmount > 0) {
            IERC20(l.denominator).safeTransfer(_from, denominatorAmount);
        }

        if (tokenAmount > 0) {
            IERC20(l.optionData[_optionId].token).safeTransfer(_from, tokenAmount);
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

        OptionStorage.Layout storage l = OptionStorage.layout();

        // Amount of options user still has to claim funds from
        uint256 claimsUser = l.nbWritten[_from][_optionId];
        require(claimsUser >= _amount, "Not enough claims");

        OptionStorage.OptionData storage data = l.optionData[_optionId];

        uint256 nbClaimable = data.exercised - data.claimsPreExp;
        require(nbClaimable >= _amount, "Not enough claimable");

        //

        l.nbWritten[_from][_optionId] -= _amount;
        data.claimsPreExp += _amount;

        if (data.isCall) {
            uint256 amount = _amount * data.strikePrice / (10**data.decimals);
            l.pools[_optionId].denominatorAmount -= amount;
            IERC20(l.denominator).safeTransfer(_from, amount);
        } else {
            l.pools[_optionId].tokenAmount -= _amount;
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
    /// @param _router The UniswapRouter used to perform the swap (Needs to be a whitelisted router)
    /// @param _amountInMax Max amount of collateral token to use for the swap, for the tx to not be reverted
    /// @param _path Path used for the routing of the swap
    function flashExerciseOptionFrom(address _from, uint256 _optionId, uint256 _amount, IUniswapV2Router02 _router, uint256 _amountInMax, address[] memory _path) external {
        require(isApprovedForAll(_from, msg.sender), "Not approved");
        _flashExerciseOption(_from, _optionId, _amount, _router, _amountInMax, _path);
    }

    /// @notice Flash exercise an option
    ///         This is usable on options in the money, in order to use a portion of the option collateral
    ///         to swap a portion of it to the token required to exercise the option and pay protocol fees,
    ///         and send the profit to the address exercising.
    ///         This allows any option in the money to be exercised without the need of owning the token needed to exercise
    /// @param _optionId The id of the option to flash exercise
    /// @param _amount Amount of option to flash exercise
    /// @param _router The UniswapRouter used to perform the swap (Needs to be a whitelisted router)
    /// @param _amountInMax Max amount of collateral token to use for the swap, for the tx to not be reverted
    /// @param _path Path used for the routing of the swap
    function flashExerciseOption(uint256 _optionId, uint256 _amount, IUniswapV2Router02 _router, uint256 _amountInMax, address[] memory _path) external {
        _flashExerciseOption(msg.sender, _optionId, _amount, _router, _amountInMax, _path);
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
    /// @param _router The UniswapRouter used to perform the swap (Needs to be a whitelisted router)
    /// @param _amountInMax Max amount of collateral token to use for the swap, for the tx to not be reverted
    /// @param _path Path used for the routing of the swap
    function _flashExerciseOption(address _from, uint256 _optionId, uint256 _amount, IUniswapV2Router02 _router, uint256 _amountInMax, address[] memory _path) internal nonReentrant {
        require(_amount > 0, "Amount <= 0");

        burn(_from, _optionId, _amount);

        OptionStorage.Layout storage l = OptionStorage.layout();
        l.optionData[_optionId].exercised += _amount;

        OptionStorage.QuoteExercise memory quote = getExerciseQuote(_from, l.optionData[_optionId], _amount, l.optionData[_optionId].decimals);

        IERC20 tokenErc20 = IERC20(l.optionData[_optionId].token);

        uint256 tokenAmountRequired = tokenErc20.balanceOf(address(this));
        uint256 denominatorAmountRequired = IERC20(l.denominator).balanceOf(address(this));

        if (l.optionData[_optionId].isCall) {
            l.pools[_optionId].tokenAmount -= quote.output;
            l.pools[_optionId].denominatorAmount += quote.input;
        } else {
            l.pools[_optionId].denominatorAmount -= quote.output;
            l.pools[_optionId].tokenAmount += quote.input;
        }

        //

        if (quote.output < _amountInMax) {
            _amountInMax = quote.output;
        }

        // Swap enough denominator to tokenErc20 to pay fee + strike price
        uint256 tokenAmountUsed = _swap(_router, quote.outputToken, quote.input + quote.fee, _amountInMax, _path)[0];

        // Pay fees
        _payFees(address(this), IERC20(quote.inputToken), quote.fee);

        uint256 profit = quote.output - tokenAmountUsed;

        // Send profit to sender
        IERC20(quote.outputToken).safeTransfer(_from, profit);

        //

        if (l.optionData[_optionId].isCall) {
            denominatorAmountRequired += quote.input;
            tokenAmountRequired -= quote.output;
        } else {
            denominatorAmountRequired -= quote.output;
            tokenAmountRequired += quote.input;
        }

        require(IERC20(l.denominator).balanceOf(address(this)) >= denominatorAmountRequired, "Wrong denom bal");
        require(tokenErc20.balanceOf(address(this)) >= tokenAmountRequired, "Wrong token bal");

        emit OptionExercised(_from, _optionId, l.optionData[_optionId].token, _amount);
    }

    //////////////////////////////////////////////////

    /// @notice Flash loan collaterals sitting in this contract
    ///         Loaned amount + fee must be repaid by the end of the transaction for the transaction to not be reverted
    /// @param _tokenAddress Token to flashLoan
    /// @param _amount Amount to flashLoan
    /// @param _receiver Receiver of the flashLoan
    function flashLoan(address _tokenAddress, uint256 _amount, IFlashLoanReceiver _receiver) public nonReentrant {
        OptionStorage.Layout storage l = OptionStorage.layout();

        IERC20 _token = IERC20(_tokenAddress);
        uint256 startBalance = _token.balanceOf(address(this));
        _token.safeTransfer(address(_receiver), _amount);


        uint256 fee = IFeeCalculator(l.feeCalculator).getFeeAmount(msg.sender, _amount, IFeeCalculator.FeeType.FlashLoan);

        _receiver.execute(_tokenAddress, _amount, _amount + fee);

        uint256 endBalance = _token.balanceOf(address(this));

        uint256 endBalanceRequired = startBalance + fee;

        require(endBalance >= endBalanceRequired, "Failed to pay back");
        _token.safeTransfer(l.feeRecipient, endBalance - startBalance);

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
        OptionStorage.OptionData storage data = OptionStorage.layout().optionData[_id];

        _mint(_account, _id, _amount, "");
        data.supply += _amount;
    }

    /// @notice Burn ERC1155 representing the option
    /// @param _account Address from which ERC1155 is burnt
    /// @param _amount Amount burnt
    function burn(address _account, uint256 _id, uint256 _amount) internal notExpired(_id) {
        OptionStorage.OptionData storage data = OptionStorage.layout().optionData[_id];

        data.supply -= _amount;
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
    /// @param _fee Protocol fee to pay to feeRecipient
    function _payFees(address _from, IERC20 _token, uint256 _fee) internal {
        OptionStorage.Layout storage l = OptionStorage.layout();

        if (_fee > 0) {
            // For flash exercise
            if (_from == address(this)) {
                _token.safeTransfer(l.feeRecipient, _fee);
            } else {
                _token.safeTransferFrom(_from, l.feeRecipient, _fee);
            }

        }

        emit FeePaid(_from, address(_token), _fee);
    }

    /// @notice Token swap (Used for flashExercise)
    /// @param _router The UniswapRouter contract to use to perform the swap (Must be whitelisted)
    /// @param _from Input token for the swap
    /// @param _amount Amount of output tokens we want
    /// @param _amountInMax Max amount of input token to spend for the tx to not revert
    /// @param _path Path used for the routing of the swap
    /// @return Swap amounts
    function _swap(IUniswapV2Router02 _router, address _from, uint256 _amount, uint256 _amountInMax, address[] memory _path) internal returns (uint256[] memory) {
        OptionStorage.Layout storage l = OptionStorage.layout();

        require(_isInArray(address(_router), l.whitelistedUniswapRouters), "Router not whitelisted");

        IERC20(_from).approve(address(_router), _amountInMax);

        uint256[] memory amounts = _router.swapTokensForExactTokens(
            _amount,
            _amountInMax,
            _path,
            address(this),
            block.timestamp
        );

        IERC20(_from).approve(address(_router), 0);

        return amounts;
    }

    /// @notice Check if option settings are valid (Reverts if not valid)
    /// @param _token Token for which option this
    /// @param _strikePrice Strike price of the option
    /// @param _expiration timestamp of the option
    function _preCheckOptionIdCreate(address _token, uint256 _strikePrice, uint256 _expiration) internal view {
        OptionStorage.Layout storage l = OptionStorage.layout();

        require(l.whitelistedTokens[_token] == true, "Token not supported");
        require(_strikePrice > 0, "Strike <= 0");
        require(_expiration > block.timestamp, "Exp passed");
        require(_expiration - block.timestamp <= l.maxExpiration, "Exp > 1 yr");
        require(_expiration % _expirationIncrement == _baseExpiration, "Wrong exp incr");
    }
}
