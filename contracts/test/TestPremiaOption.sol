// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "./TestTime.sol";

import "hardhat/console.sol";

contract TestPremiaOption is Ownable, ERC1155, TestTime {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public expirationIncrement = 3600 * 24 * 7; // 1 Week

    // ToDo : Add ability to modify increments
    struct TokenSettings {
        uint256 contractSize; // Amount of token per contract
        uint256 strikePriceIncrement; // Increment for strike price
        bool isDisabled; // Whether this token is disabled or not
    }

    struct OptionData {
        address token;
        uint256 expiration;
        uint256 strikePrice;
        bool isCall;
        uint256 claimsPreExp;  // Amount of options from which the funds have been withdrawn pre expiration
        uint256 claimsPostExp; // Amount of options from which the funds have been withdrawn post expiration
        uint256 exercised;     // Amount of options which have been exercised
        uint256 supply;        // Total circulating supply
    }

    struct Pool {
        uint256 tokenAmount;
        uint256 daiAmount;
        uint256 tokenPerShare;
        uint256 daiPerShare;
    }

    IERC20 public dai;

    //////////////////////////////////////////////////

    address[] public tokens;
    mapping (address => TokenSettings) public tokenSettings;

    //////////////////////////////////////////////////

    uint256 public nextOptionId = 1;

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

    event OptionWritten(address indexed owner, uint256 indexed optionId, uint256 amount);
    event OptionCancelled(address indexed owner, uint256 indexed optionId, uint256 amount);
    event OptionExercised(address indexed user, uint256 indexed optionId, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed optionId, uint256 amount);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    constructor(string memory _uri, IERC20 _dai) public ERC1155(_uri) {
        dai = _dai;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////////
    // Modifiers //
    ///////////////

    modifier notExpired(uint256 _optionId) {
        require(timestamp < optionData[_optionId].expiration, "Option expired");
        _;
    }

    modifier expired(uint256 _optionId) {
        require(timestamp >= optionData[_optionId].expiration, "Option not expired");
        _;
    }

    //////////
    // View //
    //////////

    function getOptionId(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall) public view returns(uint256) {
        return options[_token][_expiration][_strikePrice][_isCall];
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    // Add a new token to support writing of options paired to DAI
    function addToken(address _token, uint256 _contractSize, uint256 _strikePriceIncrement) public onlyOwner {
        require(_isInArray(_token, tokens) == false, "Token already added");
        require(_strikePriceIncrement > 0, "Strike increment must be > 0");
        tokens.push(_token);

        tokenSettings[_token] = TokenSettings({
            contractSize: _contractSize,
            strikePriceIncrement: _strikePriceIncrement,
            isDisabled: false
        });
    }

    function writeOption(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall, uint256 _contractAmount) public {
        _preCheckOptionWrite(_token, _contractAmount, _strikePrice, _expiration);

        TokenSettings memory settings = tokenSettings[_token];

        uint256 optionId = getOptionId(_token, _expiration, _strikePrice, _isCall);
        if (optionId == 0) {
            optionId = nextOptionId;
            options[_token][_expiration][_strikePrice][_isCall] = optionId;

            pools[optionId] = Pool({ tokenAmount: 0, daiAmount: 0, tokenPerShare: 0, daiPerShare: 0});
            optionData[optionId] = OptionData({
                token: _token,
                expiration: _expiration,
                strikePrice: _strikePrice,
                isCall: _isCall,
                claimsPreExp: 0,
                claimsPostExp: 0,
                exercised: 0,
                supply: 0
            });

            nextOptionId = nextOptionId.add(1);
        }

        if (_isCall) {
            IERC20 tokenErc20 = IERC20(_token);
            uint256 amount = _contractAmount.mul(settings.contractSize);
            tokenErc20.safeTransferFrom(msg.sender, address(this), amount);
            pools[optionId].tokenAmount = pools[optionId].tokenAmount.add(amount);
        } else {
            uint256 amount = _contractAmount.mul(_strikePrice);
            dai.safeTransferFrom(msg.sender, address(this), amount);
            pools[optionId].daiAmount = pools[optionId].daiAmount.add(amount);
        }

        nbWritten[msg.sender][optionId] = nbWritten[msg.sender][optionId].add(_contractAmount);

        mint(msg.sender, optionId, _contractAmount);

        emit OptionWritten(msg.sender, optionId, _contractAmount);
    }

    // Cancel an option before expiration, by burning the NFT for withdrawal of deposit (Can only be called by writer of the option)
    // Must be called before expiration
    function cancelOption(uint256 _optionId, uint256 _contractAmount) public notExpired(_optionId) {
        require(_contractAmount > 0, "ContractAmount must be > 0");
        require(nbWritten[msg.sender][_optionId] >= _contractAmount, "Cant cancel more options than written");

        burn(msg.sender, _optionId, _contractAmount);
        nbWritten[msg.sender][_optionId] = nbWritten[msg.sender][_optionId].sub(_contractAmount);

        OptionData memory data = optionData[_optionId];
        TokenSettings memory settings = tokenSettings[data.token];

        if (data.isCall) {
            IERC20 tokenErc20 = IERC20(data.token);
            uint256 amount = _contractAmount.mul(settings.contractSize);
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(amount);
            tokenErc20.safeTransfer(msg.sender, amount);
        } else {
            uint256 amount = _contractAmount.mul(data.strikePrice);
            pools[_optionId].daiAmount = pools[_optionId].daiAmount.sub(amount);
            dai.safeTransfer(msg.sender, amount);
        }

        emit OptionCancelled(msg.sender, _optionId, _contractAmount);
    }

    function exerciseOption(uint256 _optionId, uint256 _contractAmount) public notExpired(_optionId) {
        require(_contractAmount > 0, "ContractAmount must be > 0");

        OptionData storage data = optionData[_optionId];
        TokenSettings memory settings = tokenSettings[data.token];

        burn(msg.sender, _optionId, _contractAmount);
        data.exercised = data.exercised.add(_contractAmount);

        IERC20 tokenErc20 = IERC20(data.token);

        uint256 tokenAmount = _contractAmount.mul(settings.contractSize);
        uint256 daiAmount = _contractAmount.mul(data.strikePrice);

        if (data.isCall) {
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(tokenAmount);
            pools[_optionId].daiAmount = pools[_optionId].daiAmount.add(daiAmount);

            dai.safeTransferFrom(msg.sender, address(this), daiAmount);
            tokenErc20.safeTransfer(msg.sender, tokenAmount);
        } else {
            pools[_optionId].daiAmount = pools[_optionId].daiAmount.sub(daiAmount);
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.add(tokenAmount);

            tokenErc20.safeTransferFrom(msg.sender, address(this), tokenAmount);
            dai.safeTransfer(msg.sender, daiAmount);
        }

        emit OptionExercised(msg.sender, _optionId, _contractAmount);
    }

    // Withdraw funds from an expired option (Only callable by writers with unclaimed options)
    // Funds are allocated pro-rate to writers.
    // Ex : If there is 10 ETH and 6000 DAI, a user who got 10% of options unclaimed will get 1 ETH and 600 DAI
    function withdraw(uint256 _optionId) public expired(_optionId) {
        require(nbWritten[msg.sender][_optionId] > 0, "No option funds to claim for this address");

        OptionData storage data = optionData[_optionId];

        uint256 nbTotalWithClaimedPreExp = data.supply.add(data.exercised);
        uint256 claimsPreExp = data.claimsPreExp;
        uint256 nbTotal = nbTotalWithClaimedPreExp.sub(claimsPreExp);

        // Amount of options user still has to claim funds from
        uint256 claimsUser = nbWritten[msg.sender][_optionId];

        //

        uint256 daiAmount = pools[_optionId].daiAmount.mul(claimsUser).div(nbTotal);
        uint256 tokenAmount = pools[_optionId].tokenAmount.mul(claimsUser).div(nbTotal);

        //

        IERC20 tokenErc20 = IERC20(optionData[_optionId].token);

        pools[_optionId].daiAmount.sub(daiAmount);
        pools[_optionId].tokenAmount.sub(tokenAmount);
        data.claimsPostExp = data.claimsPostExp.add(claimsUser);
        delete nbWritten[msg.sender][_optionId];

        dai.safeTransfer(msg.sender, daiAmount);
        tokenErc20.safeTransfer(msg.sender, tokenAmount);

        emit Withdraw(msg.sender, _optionId, claimsUser);
    }

    // Withdraw funds from exercised unexpired option (Only callable by writers with unclaimed options)
    function withdrawPreExpiration(uint256 _optionId, uint256 _contractAmount) public notExpired(_optionId) {
        require(_contractAmount > 0, "Contract amount must be > 0");

        // Amount of options user still has to claim funds from
        uint256 claimsUser = nbWritten[msg.sender][_optionId];

        require(claimsUser >= _contractAmount, "Address does not have enough claims left");

        OptionData storage data = optionData[_optionId];
        TokenSettings memory settings = tokenSettings[data.token];

        uint256 claimsPreExp = data.claimsPreExp;
        uint256 nbClaimable = data.exercised.sub(claimsPreExp);

        require(nbClaimable > 0, "No option to claim funds from");
        require(nbClaimable >= _contractAmount, "Not enough options claimable");

        //

        if (data.isCall) {
            uint256 amount = _contractAmount.mul(data.strikePrice);
            dai.safeTransfer(msg.sender, amount);
            pools[_optionId].daiAmount = pools[_optionId].daiAmount.sub(amount);
        } else {
            IERC20 tokenErc20 = IERC20(data.token);
            uint256 amount = _contractAmount.mul(settings.contractSize);
            tokenErc20.safeTransfer(msg.sender, amount);
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(amount);
        }

        nbWritten[msg.sender][_optionId] = nbWritten[msg.sender][_optionId].sub(_contractAmount);
        data.claimsPreExp = data.claimsPreExp.add(_contractAmount);
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    //////////////
    // Internal //
    //////////////

    //    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) internal override {
    //    }

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

    function _preCheckOptionWrite(address _token, uint256 _contractAmount, uint256 _strikePrice, uint256 _expiration) internal view {
        TokenSettings memory settings = tokenSettings[_token];

        require(_isInArray(_token, tokens) == true, "Token not supported");
        require(_contractAmount > 0, "Contract amount must be > 0");
        require(_strikePrice > 0, "Strike price must be > 0");
        require(_strikePrice % settings.strikePriceIncrement == 0, "Wrong strikePrice increment");
        require(_expiration > timestamp, "Expiration already passed");
        require(_expiration % expirationIncrement == 0, "Wrong expiration timestamp increment");
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