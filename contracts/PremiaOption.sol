// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './interface/IERC20.sol';

contract PremiaOption is Ownable, ERC1155 {
    using SafeMath for uint256;

    uint256 expirationIncrement = 3600 * 24 * 7; // 1 Week

    // ToDo : Add ability to modify increments
    struct TokenSettings {
        uint256 contractSize; // Amount of token per contract
        uint256 strikePriceIncrement; // Increment for strike price
        bool isDisabled; // Whether this token is disabled or not
    }

    struct NftData {
        address token;
        uint256 expiration;
        uint256 strikePrice;
        bool isCall;
    }

    IERC20 public dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    mapping (uint256 => uint256) public tokenSupply;

    address[] public tokens;
    mapping (address => TokenSettings) public tokenSettings;

    uint256 public nextNftId = 1;

    // token => expiration => strikePrice => isCall (1 for call, 0 for put) => nftId
    mapping (address => mapping(uint256 => mapping(uint256 => mapping (bool => uint256)))) public options;

    // ToDo : Keep track of option writers, so that they can recover funds on expiration

    constructor(string memory _uri) public ERC1155(_uri) {

    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    //////////
    // View //
    //////////

    function getOptionNftId(address _token, uint256 _expiration, uint256 _strikePrice, bool _isCall) public view returns(uint256) {
        return options[_token][_expiration][_strikePrice][_isCall];
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

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

        if (_isCall) {
            dai.transferFrom(msg.sender, address(this), _contractAmount.mul(_strikePrice));
        } else {
            IERC20 tokenErc20 = IERC20(_token);
            tokenErc20.transferFrom(msg.sender, address(this), _contractAmount.mul(settings.contractSize));
        }

        uint256 nftId = getOptionNftId(_token, _expiration, _strikePrice, _isCall);
        if (nftId == 0) {
            nftId = nextNftId;
            options[_token][_expiration][_strikePrice][_isCall] = nftId;
            nextNftId = nextNftId.add(1);
        }

        mint(msg.sender, nftId, _contractAmount);
    }

    function executeOption(uint256 _nftId, uint256 _amount) {
        // ToDo : Implement
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    //////////////
    // Internal //
    //////////////

    function mint(address _account, uint256 _id, uint256 _amount) internal {
        _mint(_account, _id, _amount, "");
        tokenSupply[_id] = tokenSupply[_id].add(_amount);
    }

    function burn(address _account, uint256 _id, uint256 _amount) internal {
        tokenSupply[_id] = tokenSupply[_id].sub(_amount);
        _burn(_account, _id, _amount);
    }

    function _preCheckOptionWrite(address _token, uint256 _contractAmount, uint256 _strikePrice, uint256 _expiration) internal view {
        TokenSettings memory settings = tokenSettings[_token];

        require(_isInArray(_token, tokens) == true, "Token not supported");
        require(_contractAmount > 0, "Contract amount must be > 0");
        require(_strikePrice > 0, "Strike price must be > 0");
        require(_strikePrice % settings.strikePriceIncrement == 0, "Wrong strikePrice increment");
        require(_expiration > block.timestamp, "Expiration already passed");
        require(_expiration % expirationIncrement == 0, "Wrong expiration timestamp");
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