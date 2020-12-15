// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract PremiaErc20 is ERC20, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Addresses with minting rights
    EnumerableSet.AddressSet private _minters;

    uint256 private _maxSupply = 1e26; // Hardcoded 100m max supply

    constructor(uint256 amount) public ERC20("Premia", "PREMIA") {
        require(amount <= _maxSupply);
        _mint(msg.sender, amount);
    }

    //

    modifier onlyMinter() {
        require(_minters.contains(msg.sender), "No minting rights");
        _;
    }

    //

    function mint(address account, uint256 amount) public onlyMinter {
        require(totalSupply().add(amount) <= _maxSupply);
        _mint(account, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
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
}