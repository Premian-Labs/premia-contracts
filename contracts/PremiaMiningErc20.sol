// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract PremiaMiningErc20 is ERC20, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Addresses with minting rights
    EnumerableSet.AddressSet private _minters;

    // Whitelisted receiver can receive from any address
    EnumerableSet.AddressSet private _whitelistedReceivers;

    //

    constructor() public ERC20("PremiaMining", "PREMIA_MINING") { }

    //

    modifier onlyMinter() {
        require(_minters.contains(msg.sender), "No minting rights");
        _;
    }

    //

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        require(_whitelistedReceivers.contains(to), "Transfer not allowed");
    }

    //

    function mint(address account, uint256 amount) public onlyMinter {
        _mint(account, amount);
    }

    //

    function addMinter(address[] memory _addr) public onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _minters.add(_addr[i]);
        }
    }

    function removeMinter(address[] memory _addr) public onlyOwner {
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

    function addWhitelistedReceiver(address[] memory _addr) public onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedReceivers.add(_addr[i]);
        }
    }

    function removeWhitelistedReceiver(address[] memory _addr) public onlyOwner {
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