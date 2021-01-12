// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "./interface/IPriceProvider.sol";
import "./ERC20Permit.sol";

contract PremiaUncutErc20 is ERC20Permit, Ownable {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Addresses with minting rights
    EnumerableSet.AddressSet private _minters;

    // Whitelisted receiver can receive from any address
    EnumerableSet.AddressSet private _whitelistedReceivers;

    IPriceProvider public priceProvider;

    event Rewarded(address indexed account, address indexed token, uint256 feePaid, uint256 rewardAmount);

    //

    constructor(IPriceProvider _priceProvider) ERC20("PremiaUncut", "uPremia") {
        priceProvider = _priceProvider;
    }

    //

    modifier onlyMinter() {
        require(_minters.contains(msg.sender), "No minting rights");
        _;
    }

    //

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        require(from == address(0) || _whitelistedReceivers.contains(to), "Transfer not allowed");
    }

    //

    function mintReward(address _account, address _token, uint256 _feePaid) external onlyMinter {
        uint256 tokenPrice = priceProvider.getTokenPrice(_token);
        if (tokenPrice == 0 || _feePaid == 0) return;

        uint256 rewardAmount = _feePaid.mul(tokenPrice).div(1e18);
        _mint(_account, rewardAmount);

        emit Rewarded(_account, _token, _feePaid, rewardAmount);
    }

    //

    function setPriceProvider(IPriceProvider _priceProvider) external onlyOwner {
        priceProvider = _priceProvider;
    }

    function addMinter(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _minters.add(_addr[i]);
        }
    }

    function removeMinter(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _minters.remove(_addr[i]);
        }
    }

    function getMinters() external view returns(address[] memory) {
        uint256 length = _minters.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _minters.at(i);
        }

        return result;
    }

    //

    function addWhitelistedReceiver(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedReceivers.add(_addr[i]);
        }
    }

    function removeWhitelistedReceiver(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedReceivers.remove(_addr[i]);
        }
    }

    function getWhitelistedReceivers() external view returns(address[] memory) {
        uint256 length = _whitelistedReceivers.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelistedReceivers.at(i);
        }

        return result;
    }
}