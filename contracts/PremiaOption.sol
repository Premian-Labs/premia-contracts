// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/SafeCast.sol';

import "./interface/IFeeCalculator.sol";
import "./interface/IFlashLoanReceiver.sol";
import "./interface/IPremiaReferral.sol";
import "./interface/IPremiaUncutErc20.sol";

import "./interface/uniswap/IUniswapV2Router02.sol";


contract PremiaOption is Ownable, ERC1155, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    struct TokenSettings {
        uint256 contractSize;           // Amount of token per contract
        uint256 strikePriceIncrement;   // Increment for strike price
        bool isDisabled;                // Whether this token is disabled or not
    }

    struct OptionWriteArgs {
        address token;                  // Token address
        uint256 contractAmount;         // Amount of contracts to write
        uint256 strikePrice;            // Strike price (Must follow strikePriceIncrement of token)
        uint64 expiration;              // Expiration timestamp of the option (Must follow expirationIncrement)
        bool isCall;                    // If true : Call option | If false : Put option
    }

    struct OptionData {
        address token;                  // Token address
        uint256 contractSize;           // Amount of token per contract
        uint256 strikePrice;            // Strike price (Must follow strikePriceIncrement of token)
        uint64 expiration;              // Expiration timestamp of the option (Must follow expirationIncrement)
        bool isCall;                    // If true : Call option | If false : Put option
        uint64 claimsPreExp;            // Amount of options from which the funds have been withdrawn pre expiration
        uint64 claimsPostExp;           // Amount of options from which the funds have been withdrawn post expiration
        uint64 exercised;               // Amount of options which have been exercised
        uint64 supply;                  // Total circulating supply
    }

    struct Pool {
        uint256 tokenAmount;
        uint256 denominatorAmount;
    }

    IERC20 public denominator;

    //////////////////////////////////////////////////

    address public feeRecipient;                     // Address receiving fees

    IPremiaReferral public premiaReferral;
    IPremiaUncutErc20 public uPremia;
    IFeeCalculator public feeCalculator;

    //////////////////////////////////////////////////

    address[] public tokens;
    mapping (address => TokenSettings) public tokenSettings;

    //////////////////////////////////////////////////

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

    event OptionIdCreated(uint256 indexed optionId, address indexed token);
    event OptionWritten(address indexed owner, uint256 indexed optionId, address indexed token, uint256 contractAmount);
    event OptionCancelled(address indexed owner, uint256 indexed optionId, address indexed token, uint256 contractAmount);
    event OptionExercised(address indexed user, uint256 indexed optionId, address indexed token, uint256 contractAmount);
    event Withdraw(address indexed user, uint256 indexed optionId, address indexed token, uint256 contractAmount);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    constructor(string memory _uri, IERC20 _denominator, IPremiaUncutErc20 _uPremia, IFeeCalculator _feeCalculator,
        IPremiaReferral _premiaReferral, address _feeRecipient) ERC1155(_uri) {
        denominator = _denominator;
        uPremia = _uPremia;
        feeCalculator = _feeCalculator;
        feeRecipient = _feeRecipient;
        premiaReferral = _premiaReferral;
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

    //////////
    // View //
    //////////

    function getOptionId(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall) public view returns(uint256) {
        return options[_token][_expiration][_strikePrice][_isCall];
    }

    function getOptionExpiration(uint256 _optionId) external view returns(uint256) {
        return optionData[_optionId].expiration;
    }

    function tokensLength() external view returns(uint256) {
        return tokens.length;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    function setURI(string memory newuri) external onlyOwner {
        _setURI(newuri);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    function setMaxExpiration(uint256 _max) external onlyOwner {
        maxExpiration = _max;
    }

    function setPremiaReferral(IPremiaReferral _premiaReferral) external onlyOwner {
        premiaReferral = _premiaReferral;
    }

    function setPremiaUncutErc20(IPremiaUncutErc20 _uPremia) external onlyOwner {
        uPremia = _uPremia;
    }

    function setFeeCalculator(IFeeCalculator _feeCalculator) external onlyOwner {
        feeCalculator = _feeCalculator;
    }

    // Set settings for a token to support writing of options paired to denominator
    function setToken(address _token, uint256 _contractSize, uint256 _strikePriceIncrement, bool _isDisabled) external onlyOwner {
        if (!_isInArray(_token, tokens)) {
            tokens.push(_token);
        }

        require(_isDisabled || _contractSize > 0, "Contract size <= 0");
        require(_isDisabled || _strikePriceIncrement > 0, "Strike <= 0");

        tokenSettings[_token] = TokenSettings({
            contractSize: _contractSize,
            strikePriceIncrement: _strikePriceIncrement,
            isDisabled: _isDisabled
        });
    }

    function setWhitelistedUniswapRouters(address[] memory _addrList) external onlyOwner {
        delete whitelistedUniswapRouters;

        for (uint256 i=0; i < _addrList.length; i++) {
            whitelistedUniswapRouters.push(_addrList[i]);
        }
    }

    ////////

    function writeOption(OptionWriteArgs memory _option, address _referrer) public nonReentrant {
        _preCheckOptionWrite(_option.token, _option.contractAmount, _option.strikePrice, _option.expiration);

        uint256 optionId = getOptionId(_option.token, _option.expiration, _option.strikePrice, _option.isCall);
        if (optionId == 0) {
            optionId = nextOptionId;
            options[_option.token][_option.expiration][_option.strikePrice][_option.isCall] = optionId;

            pools[optionId] = Pool({ tokenAmount: 0, denominatorAmount: 0 });
            optionData[optionId] = OptionData({
            token: _option.token,
            contractSize: tokenSettings[_option.token].contractSize,
            expiration: _option.expiration,
            strikePrice: _option.strikePrice,
            isCall: _option.isCall,
            claimsPreExp: 0,
            claimsPostExp: 0,
            exercised: 0,
            supply: 0
            });

            emit OptionIdCreated(optionId, _option.token);

            nextOptionId = nextOptionId.add(1);
        }

        // Set referrer or get current if one already exists
        _referrer = _trySetReferrer(_referrer);

        if (_option.isCall) {
            uint256 amount = _option.contractAmount.mul(optionData[optionId].contractSize);

            IERC20(_option.token).safeTransferFrom(msg.sender, address(this), amount);

            (uint256 fee, uint256 feeReferrer) = feeCalculator.getFees(msg.sender, _referrer != address(0), amount, IFeeCalculator.FeeType.Write);
            _payFees(msg.sender, IERC20(_option.token), _referrer, fee, feeReferrer);

            pools[optionId].tokenAmount = pools[optionId].tokenAmount.add(amount);
        } else {
            uint256 amount = _option.contractAmount.mul(_option.strikePrice);

            denominator.safeTransferFrom(msg.sender, address(this), amount);

            (uint256 fee, uint256 feeReferrer) = feeCalculator.getFees(msg.sender, _referrer != address(0), amount, IFeeCalculator.FeeType.Write);
            _payFees(msg.sender, denominator, _referrer, fee, feeReferrer);

            pools[optionId].denominatorAmount = pools[optionId].denominatorAmount.add(amount);
        }

        nbWritten[msg.sender][optionId] = nbWritten[msg.sender][optionId].add(_option.contractAmount);

        mint(msg.sender, optionId, _option.contractAmount);

        emit OptionWritten(msg.sender, optionId, _option.token, _option.contractAmount);
    }

    // Cancel an option before expiration, by burning the NFT for withdrawal of deposit (Can only be called by writer of the option)
    // Must be called before expiration (Expiration check is done in burn function call)
    function cancelOption(uint256 _optionId, uint256 _contractAmount) public nonReentrant {
        require(_contractAmount > 0, "Amount <= 0");
        require(nbWritten[msg.sender][_optionId] >= _contractAmount, "Not enough written");

        burn(msg.sender, _optionId, _contractAmount);
        nbWritten[msg.sender][_optionId] = nbWritten[msg.sender][_optionId].sub(_contractAmount);

        if (optionData[_optionId].isCall) {
            uint256 amount = _contractAmount.mul(optionData[_optionId].contractSize);
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(amount);
            IERC20(optionData[_optionId].token).safeTransfer(msg.sender, amount);
        } else {
            uint256 amount = _contractAmount.mul(optionData[_optionId].strikePrice);
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.sub(amount);
            denominator.safeTransfer(msg.sender, amount);
        }

        emit OptionCancelled(msg.sender, _optionId, optionData[_optionId].token, _contractAmount);
    }

    function exerciseOption(uint256 _optionId, uint256 _contractAmount, address _referrer) public nonReentrant {
        require(_contractAmount > 0, "Amount <= 0");

        OptionData storage data = optionData[_optionId];

        burn(msg.sender, _optionId, _contractAmount);
        data.exercised = uint256(data.exercised).add(_contractAmount).toUint64();

        IERC20 tokenErc20 = IERC20(data.token);

        uint256 tokenAmount = _contractAmount.mul(data.contractSize);
        uint256 denominatorAmount = _contractAmount.mul(data.strikePrice);

        // Set referrer or get current if one already exists
        _referrer = _trySetReferrer(_referrer);

        if (data.isCall) {
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(tokenAmount);
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.add(denominatorAmount);

            denominator.safeTransferFrom(msg.sender, address(this), denominatorAmount);

            (uint256 fee, uint256 feeReferrer) = feeCalculator.getFees(msg.sender, _referrer != address(0), denominatorAmount, IFeeCalculator.FeeType.Exercise);
            _payFees(msg.sender, denominator, _referrer, fee, feeReferrer);

            tokenErc20.safeTransfer(msg.sender, tokenAmount);
        } else {
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.sub(denominatorAmount);
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.add(tokenAmount);

            tokenErc20.safeTransferFrom(msg.sender, address(this), tokenAmount);

            (uint256 fee, uint256 feeReferrer) = feeCalculator.getFees(msg.sender, _referrer != address(0), tokenAmount, IFeeCalculator.FeeType.Exercise);
            _payFees(msg.sender, tokenErc20, _referrer, fee, feeReferrer);

            denominator.safeTransfer(msg.sender, denominatorAmount);
        }

        emit OptionExercised(msg.sender, _optionId, data.token, _contractAmount);
    }

    // Withdraw funds from an expired option (Only callable by writers with unclaimed options)
    // Funds are allocated pro-rate to writers.
    // Ex : If there is 10 ETH and 6000 denominator, a user who got 10% of options unclaimed will get 1 ETH and 600 denominator
    function withdraw(uint256 _optionId) public nonReentrant expired(_optionId) {
        require(nbWritten[msg.sender][_optionId] > 0, "No option to claim");

        OptionData storage data = optionData[_optionId];

        uint256 nbTotal = uint256(data.supply).add(data.exercised).sub(data.claimsPreExp);

        // Amount of options user still has to claim funds from
        uint256 claimsUser = nbWritten[msg.sender][_optionId];

        //

        uint256 denominatorAmount = pools[_optionId].denominatorAmount.mul(claimsUser).div(nbTotal);
        uint256 tokenAmount = pools[_optionId].tokenAmount.mul(claimsUser).div(nbTotal);

        //

        pools[_optionId].denominatorAmount.sub(denominatorAmount);
        pools[_optionId].tokenAmount.sub(tokenAmount);
        data.claimsPostExp = uint256(data.claimsPostExp).add(claimsUser).toUint64();
        delete nbWritten[msg.sender][_optionId];

        denominator.safeTransfer(msg.sender, denominatorAmount);
        IERC20(optionData[_optionId].token).safeTransfer(msg.sender, tokenAmount);

        emit Withdraw(msg.sender, _optionId, data.token, claimsUser);
    }

    // Withdraw funds from exercised unexpired option (Only callable by writers with unclaimed options)
    function withdrawPreExpiration(uint256 _optionId, uint256 _contractAmount) public nonReentrant notExpired(_optionId) {
        require(_contractAmount > 0, "Amount <= 0");

        // Amount of options user still has to claim funds from
        uint256 claimsUser = nbWritten[msg.sender][_optionId];
        require(claimsUser >= _contractAmount, "Not enough claims");

        OptionData storage data = optionData[_optionId];

        uint256 nbClaimable = uint256(data.exercised).sub(data.claimsPreExp);
        require(nbClaimable >= _contractAmount, "Not enough claimable");

        //

        nbWritten[msg.sender][_optionId] = nbWritten[msg.sender][_optionId].sub(_contractAmount);
        data.claimsPreExp = uint256(data.claimsPreExp).add(_contractAmount).toUint64();

        if (data.isCall) {
            uint256 amount = _contractAmount.mul(data.strikePrice);
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.sub(amount);
            denominator.safeTransfer(msg.sender, amount);
        } else {
            uint256 amount = _contractAmount.mul(data.contractSize);
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(amount);
            IERC20(data.token).safeTransfer(msg.sender, amount);
        }

    }

    function flashLoan(address _tokenAddress, uint256 _amount, IFlashLoanReceiver _receiver) public nonReentrant {
        IERC20 _token = IERC20(_tokenAddress);
        uint256 startBalance = _token.balanceOf(address(this));
        _token.safeTransfer(address(_receiver), _amount);

        (uint256 fee,) = feeCalculator.getFees(msg.sender, false, _amount, IFeeCalculator.FeeType.FlashLoan);

        _receiver.execute(_tokenAddress, _amount, _amount.add(fee));

        uint256 endBalance = _token.balanceOf(address(this));

        uint256 endBalanceRequired = startBalance.add(fee);

        require(endBalance >= endBalanceRequired, "Failed to pay back");
        _token.safeTransfer(feeRecipient, endBalance.sub(startBalance));

        endBalance = _token.balanceOf(address(this));
        require(endBalance >= startBalance, "Failed to pay back");
    }

    function flashExerciseOption(uint256 _optionId, uint256 _contractAmount, address _referrer, IUniswapV2Router02 _router, uint256 _amountInMax) public nonReentrant {
        require(_contractAmount > 0, "Amount <= 0");

        burn(msg.sender, _optionId, _contractAmount);
        optionData[_optionId].exercised = uint256(optionData[_optionId].exercised).add(_contractAmount).toUint64();

        IERC20 tokenErc20 = IERC20(optionData[_optionId].token);

        uint256 tokenAmount = _contractAmount.mul(optionData[_optionId].contractSize);
        uint256 denominatorAmount = _contractAmount.mul(optionData[_optionId].strikePrice);

        uint256 tokenAmountRequired = tokenErc20.balanceOf(address(this));
        uint256 denominatorAmountRequired = denominator.balanceOf(address(this));

        // Set referrer or get current if one already exists
        _referrer = _trySetReferrer(_referrer);

        if (optionData[_optionId].isCall) {
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(tokenAmount);
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.add(denominatorAmount);

            (uint256 fee, uint256 feeReferrer) = feeCalculator.getFees(msg.sender, _referrer != address(0), denominatorAmount, IFeeCalculator.FeeType.Exercise);

            // Swap enough denominator to tokenErc20 to pay fee + strike price
            uint256 tokenAmountUsed = _swap(_router, address(tokenErc20), address(denominator), denominatorAmount.add(fee).add(feeReferrer), _amountInMax)[0];

            // Pay fees
            _payFees(address(this), denominator, _referrer, fee, feeReferrer);

            uint256 profit = tokenAmount.sub(tokenAmountUsed);

            // Send profit to sender
            tokenErc20.safeTransfer(msg.sender, profit);

            denominatorAmountRequired = denominatorAmountRequired.add(denominatorAmount);
            tokenAmountRequired = tokenAmountRequired.sub(tokenAmount);
        } else {
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.sub(denominatorAmount);
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.add(tokenAmount);

            (uint256 fee, uint256 feeReferrer) = feeCalculator.getFees(msg.sender, _referrer != address(0), tokenAmount, IFeeCalculator.FeeType.Exercise);

            // Swap enough denominator to tokenErc20 to pay fee + strike price
            uint256 denominatorAmountUsed =  _swap(_router, address(denominator), address(tokenErc20), tokenAmount.add(fee).add(feeReferrer), _amountInMax)[0];

            _payFees(address(this), tokenErc20, _referrer, fee, feeReferrer);

            uint256 profit = denominatorAmount.sub(denominatorAmountUsed);

            // Send profit to sender
            denominator.safeTransfer(msg.sender, profit);

            denominatorAmountRequired = denominatorAmountRequired.sub(denominatorAmount);
            tokenAmountRequired = tokenAmountRequired.add(tokenAmount);
        }

        require(denominator.balanceOf(address(this)) >= denominatorAmountRequired, "Wrong denom bal");
        require(tokenErc20.balanceOf(address(this)) >= tokenAmountRequired, "Wrong token bal");

        emit OptionExercised(msg.sender, _optionId, optionData[_optionId].token, _contractAmount);
    }

    /////////////////////
    // Batch functions //
    /////////////////////

    function batchWriteOption(OptionWriteArgs[] memory _options, address _referrer) external {
        for (uint256 i = 0; i < _options.length; ++i) {
            writeOption(_options[i], _referrer);
        }
    }

    function batchCancelOption(uint256[] memory _optionId, uint256[] memory _contractAmount) external {
        require(_optionId.length == _contractAmount.length, "Arrays diff len");

        for (uint256 i = 0; i < _optionId.length; ++i) {
            cancelOption(_optionId[i], _contractAmount[i]);
        }
    }

    function batchWithdraw(uint256[] memory _optionId) external {
        for (uint256 i = 0; i < _optionId.length; ++i) {
            withdraw(_optionId[i]);
        }
    }

    function batchExerciseOption(uint256[] memory _optionId, uint256[] memory _contractAmount, address _referrer) external {
        require(_optionId.length == _contractAmount.length, "Arrays diff len");

        for (uint256 i = 0; i < _optionId.length; ++i) {
            exerciseOption(_optionId[i], _contractAmount[i], _referrer);
        }
    }

    function batchWithdrawPreExpiration(uint256[] memory _optionId, uint256[] memory _contractAmount) external {
        require(_optionId.length == _contractAmount.length, "Arrays diff len");

        for (uint256 i = 0; i < _optionId.length; ++i) {
            withdrawPreExpiration(_optionId[i], _contractAmount[i]);
        }
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    //////////////
    // Internal //
    //////////////

    function mint(address _account, uint256 _id, uint256 _amount) internal notExpired(_id) {
        OptionData storage data = optionData[_id];

        _mint(_account, _id, _amount, "");
        data.supply = uint256(data.supply).add(_amount).toUint64();
    }

    function burn(address _account, uint256 _id, uint256 _amount) internal notExpired(_id) {
        OptionData storage data = optionData[_id];

        data.supply = uint256(data.supply).sub(_amount).toUint64();
        _burn(_account, _id, _amount);
    }

    // Utility function to check if a value is inside an array
    function _isInArray(address _value, address[] memory _array) internal pure returns(bool) {
        uint256 length = _array.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_array[i] == _value) {
                return true;
            }
        }

        return false;
    }

    function _preCheckOptionWrite(address _token, uint256 _contractAmount, uint256 _strikePrice, uint256 _expiration) internal view {
        require(!tokenSettings[_token].isDisabled, "Token disabled");
        require(tokenSettings[_token].contractSize != 0, "Token not supported");
        require(_contractAmount > 0, "Amount <= 0");
        require(_strikePrice > 0, "Strike <= 0");
        require(_strikePrice % tokenSettings[_token].strikePriceIncrement == 0, "Wrong strike incr");
        require(_expiration > block.timestamp, "Exp passed");
        require(_expiration.sub(block.timestamp) <= 365 days, "Exp > 1 yr");
        require(_expiration % _expirationIncrement == _baseExpiration, "Wrong exp incr");
    }

    function _payFees(address _from, IERC20 _token, address _referrer, uint256 _fee, uint256 _feeReferrer) internal {
        if (_fee > 0) {
            _token.safeTransferFrom(_from, feeRecipient, _fee);
        }

        if (_feeReferrer > 0) {
            _token.safeTransferFrom(_from, _referrer, _feeReferrer);
        }

        // If uPremia rewards are enabled
        if (address(uPremia) != address(0)) {
            uint256 totalFee = _fee.add(_feeReferrer);
            if (totalFee > 0) {
                uPremia.mintReward(_from, address(_token), totalFee);
            }
        }
    }

    // Try to set given referrer, returns current referrer if one already exists
    function _trySetReferrer(address _referrer) internal returns(address) {
        if (address(premiaReferral) != address(0)) {
            _referrer = premiaReferral.trySetReferrer(msg.sender, _referrer);
        } else {
            _referrer = address(0);
        }

        return _referrer;
    }

    function _swap(IUniswapV2Router02 _router, address _from, address _to, uint256 _amount,uint256 _amountInMax) internal returns (uint256[] memory) {
        require(_isInArray(address(_router), whitelistedUniswapRouters), "Router not whitelisted");

        IERC20(_from).safeApprove(address(_router), _amountInMax);

        address[] memory path;
        address weth = _router.WETH();

        if (_from == weth || _to == weth) {
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            path = new address[](3);
            path[0] = _from;
            path[1] = weth;
            path[2] = _to;
        }

        uint256[] memory amounts = _router.swapTokensForExactTokens(
            _amount,
            _amountInMax,
            path,
            address(this),
            block.timestamp.add(60)
        );

        IERC20(_from).safeApprove(address(_router), 0);

        return amounts;
    }
}