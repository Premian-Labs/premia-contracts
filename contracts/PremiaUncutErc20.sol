// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "./interface/IPriceProvider.sol";
import "./ERC20Permit.sol";

/// @author Premia
/// @title A non tradable token rewarded on protocol fees payment (~ 1 uPremia for each USD paid in protocol fee)
///        used exclusively for mining of premia allocated for "Interaction mining"
/// @notice Only addresses whitelisted will be allowed to send/receive uPremia
///         Anyone can send to a whitelisted address
///         A whitelisted address can send to anyone
contract PremiaUncutErc20 is ERC20Permit, Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Addresses with minting rights
    EnumerableSet.AddressSet private _minters;

    // Whitelisted addresses which can receive/send uPremia
    EnumerableSet.AddressSet private _whitelisted;

    // PriceProvider contract
    IPriceProvider public priceProvider;

    ////////////
    // Events //
    ////////////

    event Rewarded(address indexed account, address indexed token, uint256 feePaid, uint256 rewardAmount);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    /// @param _priceProvider PriceProvider contract
    constructor(IPriceProvider _priceProvider) ERC20("PremiaUncut", "uPremia") {
        priceProvider = _priceProvider;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////////
    // Modifiers //
    ///////////////

    modifier onlyMinter() {
        require(_minters.contains(msg.sender), "No minting rights");
        _;
    }

    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    /// @notice Set a new PriceProvider contract
    /// @param _priceProvider The new contract
    function setPriceProvider(IPriceProvider _priceProvider) external onlyOwner {
        priceProvider = _priceProvider;
    }

    /// @notice Give minting rights to a list of addresses
    /// @param _addr The list of addresses to which give minting rights
    function addMinter(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _minters.add(_addr[i]);
        }
    }

    /// @notice Remove minting rights to a list of addresses
    /// @param _addr The list of addresses from which to remove minting rights
    function removeMinter(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _minters.remove(_addr[i]);
        }
    }

    /// @notice Add a list of addresses which can send/receive uPremia
    /// @param _addr The list of addresses
    function addWhitelisted(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelisted.add(_addr[i]);
        }
    }

    /// @notice Remove a list of addresses from the whitelist allowing receiving/sending uPremia
    /// @param _addr The list of addresses
    function removeWhitelisted(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelisted.remove(_addr[i]);
        }
    }

    //////////////////////////////////////////////////

    /////////////
    // Minters //
    /////////////

    /// @notice Mint uPremia
    /// @param _account The address for which to mint
    /// @param _amount The amount to mint
    function mint(address _account, uint256 _amount) external onlyMinter {
        _mint(_account, _amount);
    }

    /// @notice Mint corresponding uPremia reward based on protocol fee paid
    /// @param _account The address for which to mint
    /// @param _token The token in which the protocol fee has been paid
    /// @param _feePaid The fee paid (in _token)
    function mintReward(address _account, address _token, uint256 _feePaid) external onlyMinter {
        uint256 tokenPrice = priceProvider.getTokenPrice(_token);
        if (tokenPrice == 0 || _feePaid == 0) return;

        uint256 rewardAmount = _feePaid.mul(tokenPrice).div(1e18);
        _mint(_account, rewardAmount);

        emit Rewarded(_account, _token, _feePaid, rewardAmount);
    }

    //////////////////////////////////////////////////

    //////////
    // View //
    //////////

    /// @notice Get the usd price of a token
    /// @param _token The token from which to give usd price
    /// @return The usd price
    function getTokenPrice(address _token) external view returns(uint256) {
        return priceProvider.getTokenPrice(_token);
    }

    // @notice Get the list of addresses with minting rights
    // @return The list of addresses with minting rights
    function getMinters() external view returns(address[] memory) {
        uint256 length = _minters.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _minters.at(i);
        }

        return result;
    }

    // @notice Get the list of addresses allowed to send/receive uPremia
    // @return The list of addresses allowed to send/receive uPremia
    function getWhitelisted() external view returns(address[] memory) {
        uint256 length = _whitelisted.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelisted.at(i);
        }

        return result;
    }

    //////////////////////////////////////////////////

    //////////////
    // Internal //
    //////////////

    // @notice Override of ERC20 beforeTokenTransfer, to only allow send/receive uPremia by whitelisted addresses
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        require(from == address(0) || _whitelisted.contains(to) || _whitelisted.contains(from), "Transfer not allowed");
    }
}