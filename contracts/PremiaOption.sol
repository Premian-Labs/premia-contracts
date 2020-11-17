// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract PremiaOption is Ownable, ERC1155 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 expirationIncrement = 3600 * 24 * 7; // 1 Week

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
    }

    struct Pool {
        uint256 tokenAmount;
        uint256 daiAmount;
    }

    IERC20 public dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    //////////////////////////////////////////////////

    address[] public tokens;
    mapping (address => TokenSettings) public tokenSettings;

    //////////////////////////////////////////////////

    // Amount of circulating options (optionId => supply)
    mapping (uint256 => uint256) public optionSupply;

    // Amount of options which have been executed (optionId => executed)
    mapping (uint256 => uint256) public optionExecuted;

    // Amount of options from which the funds have been withdrawn post expiration
    mapping (uint256 => uint256) public optionClaimed;

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

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    constructor(string memory _uri) public ERC1155(_uri) {

    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////////
    // Modifiers //
    ///////////////

    modifier notExpired(uint256 _optionId) {
        require(block.timestamp < optionData[_optionId].expiration, "Option expired");
        _;
    }

    modifier expired(uint256 _optionId) {
        require(block.timestamp >= optionData[_optionId].expiration, "Option not expired");
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

            pools[optionId] = Pool({ tokenAmount: 0, daiAmount: 0});
            optionData[optionId] = OptionData({
                token: _token,
                expiration: _expiration,
                strikePrice: _strikePrice,
                isCall: _isCall
            });

            nextOptionId = nextOptionId.add(1);
        }

        if (_isCall) {
            uint256 amount = _contractAmount.mul(_strikePrice);
            dai.safeTransferFrom(msg.sender, address(this), amount);
            pools[optionId].daiAmount = pools[optionId].daiAmount.add(amount);
        } else {
            IERC20 tokenErc20 = IERC20(_token);
            uint256 amount = _contractAmount.mul(settings.contractSize);
            tokenErc20.safeTransferFrom(msg.sender, address(this), amount);
            pools[optionId].tokenAmount = pools[optionId].tokenAmount.add(amount);
        }

        nbWritten[msg.sender][optionId] = nbWritten[msg.sender][optionId].add(_contractAmount);

        mint(msg.sender, optionId, _contractAmount);
    }

    // Cancel an option before expiration, and withdraw deposit (Can only be called by writer of the option)
    // Must be called before expiration
    function cancelOption(uint256 _optionId, uint256 _contractAmount) public notExpired(_optionId) {
        require(_contractAmount > 0, "ContractAmount must be > 0");
        require(nbWritten[msg.sender][_optionId] >= _contractAmount, "Cant cancel more options than written");

        burn(msg.sender, _optionId, _contractAmount);
        nbWritten[msg.sender][_optionId] = nbWritten[msg.sender][_optionId].sub(_contractAmount);

        OptionData memory data = optionData[_optionId];
        TokenSettings memory settings = tokenSettings[data.token];

        if (data.isCall) {
            uint256 amount = _contractAmount.mul(data.strikePrice);
            pools[_optionId].daiAmount = pools[_optionId].daiAmount.sub(amount);
            dai.safeTransfer(msg.sender, amount);
        } else {
            IERC20 tokenErc20 = IERC20(data.token);
            uint256 amount = _contractAmount.mul(settings.contractSize);
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(amount);
            tokenErc20.safeTransfer(msg.sender, amount);
        }
    }

    function executeOption(uint256 _optionId, uint256 _contractAmount) public notExpired(_optionId) {
        require(_contractAmount > 0, "ContractAmount must be > 0");

        OptionData memory data = optionData[_optionId];
        TokenSettings memory settings = tokenSettings[data.token];

        burn(msg.sender, _optionId, _contractAmount);
        optionExecuted[_optionId] = optionExecuted[_optionId].add(_contractAmount);

        IERC20 tokenErc20 = IERC20(data.token);

        uint256 tokenAmount = _contractAmount.mul(settings.contractSize);
        uint256 daiAmount = _contractAmount.mul(data.strikePrice);

        if (data.isCall) {
            pools[_optionId].daiAmount = pools[_optionId].daiAmount.sub(daiAmount);
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.add(tokenAmount);

            tokenErc20.safeTransferFrom(msg.sender, address(this), tokenAmount);
            dai.safeTransfer(msg.sender, daiAmount);
        } else {
            pools[_optionId].tokenAmount = pools[_optionId].tokenAmount.sub(tokenAmount);
            pools[_optionId].daiAmount = pools[_optionId].daiAmount.add(daiAmount);

            dai.safeTransferFrom(msg.sender, address(this), daiAmount);
            tokenErc20.safeTransfer(msg.sender, tokenAmount);
        }
    }

    // Withdraw funds from an expired option
    function withdraw(uint256 _optionId) public expired(_optionId) {
        // ToDo : Also allow withdraw if option not expired, but all options from the pool have been executed ?
        require(nbWritten[msg.sender][_optionId] > 0, "No option funds to claim for this address");

        uint256 nbTotal = optionSupply[_optionId].add(optionExecuted[_optionId]);
        uint256 nbClaimed = optionClaimed[_optionId];

        // Amount of options from which funds have not been claimed yet
        uint256 claimsLeft = nbTotal.sub(nbClaimed);
        // Amount of options user still has to claim funds from
        uint256 claimsUser = nbWritten[msg.sender][_optionId];

        //

        uint256 daiAmount = pools[_optionId].daiAmount.mul(claimsLeft).div(claimsUser);
        uint256 tokenAmount = pools[_optionId].tokenAmount.mul(claimsLeft).div(claimsUser);

        //

        IERC20 tokenErc20 = IERC20(optionData[_optionId].token);

        pools[_optionId].daiAmount.sub(daiAmount);
        pools[_optionId].tokenAmount.sub(tokenAmount);
        optionClaimed[_optionId] = optionClaimed[_optionId].add(claimsUser);
        delete nbWritten[msg.sender][_optionId];

        dai.safeTransfer(msg.sender, daiAmount);
        tokenErc20.safeTransfer(msg.sender, tokenAmount);
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    //////////////
    // Internal //
    //////////////

//    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) internal override {
//    }

    function mint(address _account, uint256 _id, uint256 _amount) internal {
        _mint(_account, _id, _amount, "");
        optionSupply[_id] = optionSupply[_id].add(_amount);
    }

    function burn(address _account, uint256 _id, uint256 _amount) internal {
        optionSupply[_id] = optionSupply[_id].sub(_amount);
        _burn(_account, _id, _amount);
    }

    function _preCheckOptionWrite(address _token, uint256 _contractAmount, uint256 _strikePrice, uint256 _expiration) internal view {
        TokenSettings memory settings = tokenSettings[_token];

        require(_isInArray(_token, tokens) == true, "Token not supported");
        require(_contractAmount > 0, "Contract amount must be > 0");
        require(_strikePrice > 0, "Strike price must be > 0");
        require(_strikePrice % settings.strikePriceIncrement == 0, "Wrong strikePrice increment");
        require(_expiration > block.timestamp, "Expiration already passed");
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