// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import "./interface/ITokenSettingsCalculator.sol";

contract PremiaOption is Ownable, ERC1155 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct TokenSettings {
        uint256 contractSize;           // Amount of token per contract
        uint256 strikePriceIncrement;   // Increment for strike price
        bool isDisabled;                // Whether this token is disabled or not
    }

    struct OptionData {
        address token;                  // Token address
        uint256 contractSize;           // Amount of token per contract
        uint256 expiration;             // Expiration timestamp of the option (Must follow expirationIncrement)
        uint256 strikePrice;            // Strike price (Must follow strikePriceIncrement of token)
        bool isCall;                    // If true : Call option | If false : Put option
        uint256 claimsPreExp;           // Amount of options from which the funds have been withdrawn pre expiration
        uint256 claimsPostExp;          // Amount of options from which the funds have been withdrawn post expiration
        uint256 exercised;              // Amount of options which have been exercised
        uint256 supply;                 // Total circulating supply
    }

    struct Pool {
        uint256 tokenAmount;
        uint256 denominatorAmount;
    }

    IERC20 public denominator;

    //////////////////////////////////////////////////

    address[] public tokens;
    mapping (address => TokenSettings) public tokenSettings;

    //////////////////////////////////////////////////

    uint256 public nextOptionId = 1;

    address public treasury; // Treasury address receiving fees

    uint256 public baseExpiration = 172799;         // Offset to add to Unix timestamp to make it Fri 23:59:59 UTC
    uint256 public expirationIncrement = 1 weeks;   // Expiration increment
    uint256 public maxExpiration = 365 days;        // Max expiration time from now

    uint256 public writeFee = 1e3;                  // 1%
    uint256 public exerciseFee = 1e3;               // 1%

    // This contract is used to define automatically an initial contractSize and strikePriceIncrement for a newly added token
    // Disabled on launch, might be added later, so that admin does not need to add tokens manually
    ITokenSettingsCalculator public tokenSettingsCalculator;

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

    constructor(string memory _uri, IERC20 _denominator, address _treasury) public ERC1155(_uri) {
        denominator = _denominator;
        treasury = _treasury;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////////
    // Modifiers //
    ///////////////

    modifier notExpired(uint256 _optionId) {
        require(getBlockTimestamp() < optionData[_optionId].expiration, "Option expired");
        _;
    }

    modifier expired(uint256 _optionId) {
        require(getBlockTimestamp() >= optionData[_optionId].expiration, "Option not expired");
        _;
    }

    //////////
    // View //
    //////////

    function getBlockTimestamp() public view returns(uint256) {
        return block.timestamp;
    }

    function getOptionId(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall) public view returns(uint256) {
        return options[_token][_expiration][_strikePrice][_isCall];
    }

    function getAllTokens() public view returns(address[] memory) {
        return tokens;
    }

    function getOptionDataBatch(uint256[] memory _optionIds) public view returns(OptionData[] memory) {
        OptionData[] memory result = new OptionData[](_optionIds.length);

        for (uint256 i = 0; i < _optionIds.length; ++i) {
            uint256 optionId = _optionIds[i];
            result[i] = optionData[optionId];
        }

        return result;
    }

    function getNbOptionWrittenBatch(address _user, uint256[] memory _optionIds) public view returns(uint256[] memory) {
        uint256[] memory result = new uint256[](_optionIds.length);

        for (uint256 i = 0; i < _optionIds.length; ++i) {
            uint256 optionId = _optionIds[i];
            result[i] = nbWritten[_user][optionId];
        }

        return result;
    }

    function getPoolBatch(uint256[] memory _optionIds) public view returns(Pool[] memory) {
        Pool[] memory result = new Pool[](_optionIds.length);

        for (uint256 i = 0; i < _optionIds.length; ++i) {
            uint256 optionId = _optionIds[i];
            result[i] = pools[optionId];
        }

        return result;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    function setTokenDisabled(address _token, bool _isDisabled) public onlyOwner {
        tokenSettings[_token].isDisabled = _isDisabled;
    }

    function setTokenSettingsCalculator(ITokenSettingsCalculator _addr) public onlyOwner {
        tokenSettingsCalculator = _addr;
    }

    function setTreasury(address _treasury) public onlyOwner {
        require(_treasury != address(0), "Treasury cannot be 0x0 address");
        treasury = _treasury;
    }

    function setMaxExpiration(uint256 _max) public onlyOwner {
        require(_max >= 0, "Max expiration cannot be negative");
        maxExpiration = _max;
    }

    function setWriteFee(uint256 _fee) public onlyOwner {
        require(_fee >= 0, "Fee must be >= 0");
        writeFee = _fee;
    }

    function setExerciseFee(uint256 _fee) public onlyOwner {
        require(_fee >= 0, "Fee must be >= 0");
        exerciseFee = _fee;
    }

    // Set settings for a token to support writing of options paired to denominator
    function setToken(address _token, uint256 _contractSize, uint256 _strikePriceIncrement) public onlyOwner {
        _setToken(_token, _contractSize, _strikePriceIncrement);
    }

    ////////

    function writeOption(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall, uint256 _contractAmount) public {
        // If token has never been used before, we request a default contractSize and strikePriceIncrement to initialize it
        // (If tokenSettingsCalculator contract is defined)
        if (address(tokenSettingsCalculator) != address(0) && _isInArray(_token, tokens) == false) {
            (
            uint256 contractSize,
            uint256 strikePrinceIncrement
            ) = tokenSettingsCalculator.getTokenSettings(_token, address(denominator));

            _setToken(_token, contractSize, strikePrinceIncrement);
        }

        //

        _preCheckOptionWrite(_token, _contractAmount, _strikePrice, _expiration);

        TokenSettings memory settings = tokenSettings[_token];

        uint256 optionId = getOptionId(_token, _expiration, _strikePrice, _isCall);
        if (optionId == 0) {
            optionId = nextOptionId;
            options[_token][_expiration][_strikePrice][_isCall] = optionId;

            pools[optionId] = Pool({ tokenAmount: 0, denominatorAmount: 0 });
            optionData[optionId] = OptionData({
            token: _token,
            contractSize: settings.contractSize,
            expiration: _expiration,
            strikePrice: _strikePrice,
            isCall: _isCall,
            claimsPreExp: 0,
            claimsPostExp: 0,
            exercised: 0,
            supply: 0
            });

            emit OptionIdCreated(optionId, _token);

            nextOptionId = nextOptionId.add(1);
        }

        OptionData memory data = optionData[optionId];

        if (_isCall) {
            IERC20 tokenErc20 = IERC20(_token);

            uint256 amount = _contractAmount.mul(data.contractSize);
            uint256 feeAmount = amount.mul(writeFee).div(1e5);

            tokenErc20.safeTransferFrom(msg.sender, address(this), amount);
            tokenErc20.safeTransferFrom(msg.sender, treasury, feeAmount);

            pools[optionId].tokenAmount = pools[optionId].tokenAmount.add(amount);
        } else {
            uint256 amount = _contractAmount.mul(_strikePrice);
            uint256 feeAmount = amount.mul(writeFee).div(1e5);

            denominator.safeTransferFrom(msg.sender, address(this), amount);
            denominator.safeTransferFrom(msg.sender, treasury, feeAmount);

            pools[optionId].denominatorAmount = pools[optionId].denominatorAmount.add(amount);
        }

        nbWritten[msg.sender][optionId] = nbWritten[msg.sender][optionId].add(_contractAmount);

        mint(msg.sender, optionId, _contractAmount);

        emit OptionWritten(msg.sender, optionId, _token, _contractAmount);
    }

    // Cancel an option before expiration, by burning the NFT for withdrawal of deposit (Can only be called by writer of the option)
    // Must be called before expiration
    function cancelOption(uint256 _optionId, uint256 _contractAmount) public notExpired(_optionId) {
        require(_contractAmount > 0, "ContractAmount must be > 0");
        require(nbWritten[msg.sender][_optionId] >= _contractAmount, "Cant cancel more options than written");

        burn(msg.sender, _optionId, _contractAmount);
        nbWritten[msg.sender][_optionId] = nbWritten[msg.sender][_optionId].sub(_contractAmount);

        OptionData memory data = optionData[_optionId];

        if (data.isCall) {
            IERC20 tokenErc20 = IERC20(data.token);
            uint256 amount = _contractAmount.mul(data.contractSize);
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(amount);
            tokenErc20.safeTransfer(msg.sender, amount);
        } else {
            uint256 amount = _contractAmount.mul(data.strikePrice);
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.sub(amount);
            denominator.safeTransfer(msg.sender, amount);
        }

        emit OptionCancelled(msg.sender, _optionId, data.token, _contractAmount);
    }

    function exerciseOption(uint256 _optionId, uint256 _contractAmount) public notExpired(_optionId) {
        require(_contractAmount > 0, "ContractAmount must be > 0");

        OptionData storage data = optionData[_optionId];

        burn(msg.sender, _optionId, _contractAmount);
        data.exercised = data.exercised.add(_contractAmount);

        IERC20 tokenErc20 = IERC20(data.token);

        uint256 tokenAmount = _contractAmount.mul(data.contractSize);
        uint256 denominatorAmount = _contractAmount.mul(data.strikePrice);

        if (data.isCall) {
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(tokenAmount);
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.add(denominatorAmount);

            uint256 feeAmount = denominatorAmount.mul(exerciseFee).div(1e5);

            denominator.safeTransferFrom(msg.sender, address(this), denominatorAmount);
            denominator.safeTransferFrom(msg.sender, treasury, feeAmount);

            tokenErc20.safeTransfer(msg.sender, tokenAmount);
        } else {
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.sub(denominatorAmount);
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.add(tokenAmount);

            uint256 feeAmount = tokenAmount.mul(exerciseFee).div(1e5);

            tokenErc20.safeTransferFrom(msg.sender, address(this), tokenAmount);
            tokenErc20.safeTransferFrom(msg.sender, treasury, feeAmount);

            denominator.safeTransfer(msg.sender, denominatorAmount);
        }

        emit OptionExercised(msg.sender, _optionId, data.token, _contractAmount);
    }

    // Withdraw funds from an expired option (Only callable by writers with unclaimed options)
    // Funds are allocated pro-rate to writers.
    // Ex : If there is 10 ETH and 6000 denominator, a user who got 10% of options unclaimed will get 1 ETH and 600 denominator
    function withdraw(uint256 _optionId) public expired(_optionId) {
        require(nbWritten[msg.sender][_optionId] > 0, "No option funds to claim for this address");

        OptionData storage data = optionData[_optionId];

        uint256 nbTotalWithClaimedPreExp = data.supply.add(data.exercised);
        uint256 claimsPreExp = data.claimsPreExp;
        uint256 nbTotal = nbTotalWithClaimedPreExp.sub(claimsPreExp);

        // Amount of options user still has to claim funds from
        uint256 claimsUser = nbWritten[msg.sender][_optionId];

        //

        uint256 denominatorAmount = pools[_optionId].denominatorAmount.mul(claimsUser).div(nbTotal);
        uint256 tokenAmount = pools[_optionId].tokenAmount.mul(claimsUser).div(nbTotal);

        //

        IERC20 tokenErc20 = IERC20(optionData[_optionId].token);

        pools[_optionId].denominatorAmount.sub(denominatorAmount);
        pools[_optionId].tokenAmount.sub(tokenAmount);
        data.claimsPostExp = data.claimsPostExp.add(claimsUser);
        delete nbWritten[msg.sender][_optionId];

        denominator.safeTransfer(msg.sender, denominatorAmount);
        tokenErc20.safeTransfer(msg.sender, tokenAmount);

        emit Withdraw(msg.sender, _optionId, data.token, claimsUser);
    }

    // Withdraw funds from exercised unexpired option (Only callable by writers with unclaimed options)
    function withdrawPreExpiration(uint256 _optionId, uint256 _contractAmount) public notExpired(_optionId) {
        require(_contractAmount > 0, "Contract amount must be > 0");

        // Amount of options user still has to claim funds from
        uint256 claimsUser = nbWritten[msg.sender][_optionId];

        require(claimsUser >= _contractAmount, "Address does not have enough claims left");

        OptionData storage data = optionData[_optionId];

        uint256 claimsPreExp = data.claimsPreExp;
        uint256 nbClaimable = data.exercised.sub(claimsPreExp);

        require(nbClaimable > 0, "No option to claim funds from");
        require(nbClaimable >= _contractAmount, "Not enough options claimable");

        //

        nbWritten[msg.sender][_optionId] = nbWritten[msg.sender][_optionId].sub(_contractAmount);
        data.claimsPreExp = data.claimsPreExp.add(_contractAmount);

        if (data.isCall) {
            uint256 amount = _contractAmount.mul(data.strikePrice);
            pools[_optionId].denominatorAmount = pools[_optionId].denominatorAmount.sub(amount);
            denominator.safeTransfer(msg.sender, amount);
        } else {
            IERC20 tokenErc20 = IERC20(data.token);
            uint256 amount = _contractAmount.mul(data.contractSize);
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(amount);
            tokenErc20.safeTransfer(msg.sender, amount);
        }

    }

    /////////////////////
    // Batch functions //
    /////////////////////

    function batchWriteOption(address[] memory _token, uint256[] memory _expiration, uint256[] memory _strikePrice, bool[] memory _isCall, uint256[] memory _contractAmount) public {
        require(_token.length == _expiration.length, "All arrays must have same length");
        require(_token.length == _strikePrice.length, "All arrays must have same length");
        require(_token.length == _isCall.length, "All arrays must have same length");
        require(_token.length == _contractAmount.length, "All arrays must have same length");

        for (uint256 i = 0; i < _token.length; ++i) {
            writeOption(_token[i], _expiration[i], _strikePrice[i], _isCall[i], _contractAmount[i]);
        }
    }

    function batchCancelOption(uint256[] memory _optionId, uint256[] memory _contractAmount) public {
        require(_optionId.length == _contractAmount.length, "All arrays must have same length");

        for (uint256 i = 0; i < _optionId.length; ++i) {
            cancelOption(_optionId[i], _contractAmount[i]);
        }
    }

    function batchWithdraw(uint256[] memory _optionId) public {
        for (uint256 i = 0; i < _optionId.length; ++i) {
            withdraw(_optionId[i]);
        }
    }

    function batchWithdrawPreExpiration(uint256[] memory _optionId, uint256[] memory _contractAmount) public {
        require(_optionId.length == _contractAmount.length, "All arrays must have same length");

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
        data.supply = data.supply.add(_amount);
    }

    function burn(address _account, uint256 _id, uint256 _amount) internal notExpired(_id) {
        OptionData storage data = optionData[_id];

        data.supply = data.supply.sub(_amount);
        _burn(_account, _id, _amount);
    }

    // Add a new token to support writing of options paired to denominator
    function _setToken(address _token, uint256 _contractSize, uint256 _strikePriceIncrement) internal {
        if (_isInArray(_token, tokens) == false) {
            tokens.push(_token);
        }

        require(_contractSize > 0, "Contract size must be > 0");
        require(_strikePriceIncrement > 0, "Strike increment must be > 0");

        tokenSettings[_token] = TokenSettings({
        contractSize: _contractSize,
        strikePriceIncrement: _strikePriceIncrement,
        isDisabled: false
        });
    }

    function _preCheckOptionWrite(address _token, uint256 _contractAmount, uint256 _strikePrice, uint256 _expiration) internal view {
        TokenSettings memory settings = tokenSettings[_token];

        require(settings.isDisabled == false, "Token is disabled");
        require(_isInArray(_token, tokens) == true, "Token not supported");
        require(_contractAmount > 0, "Contract amount must be > 0");
        require(_strikePrice > 0, "Strike price must be > 0");
        require(_strikePrice % settings.strikePriceIncrement == 0, "Wrong strikePrice increment");
        require(_expiration > getBlockTimestamp(), "Expiration already passed");
        require(_expiration.sub(getBlockTimestamp()) <= 365 days, "Expiration must be <= 1 year");
        require(_expiration % expirationIncrement == baseExpiration, "Wrong expiration timestamp increment");
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

}