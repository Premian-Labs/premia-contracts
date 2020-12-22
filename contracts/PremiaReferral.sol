// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract PremiaReferral is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Referred => Referrer
    mapping (address => address) public referrals;

    // Addresses allowed to set referrers
    EnumerableSet.AddressSet private _whitelisted;

    event Referral(address indexed referrer, address indexed referred);

    //

    modifier onlyWhitelisted() {
        require(_whitelisted.contains(msg.sender), "Not whitelisted");
        _;
    }

    //

    // Set a new referrer if none has been set for referred address + return referrers for given referred
    function getReferrer(address _referred, address _potentialReferrer) public onlyWhitelisted returns(address) {
        if (_referred == address(0)) return address(0);

        if (referrals[_referred] == address(0) && _potentialReferrer != address(0)) {
            referrals[_referred] = _potentialReferrer;
            emit Referral(_potentialReferrer, _referred);
        }

        return referrals[_referred];
    }

    //

    function addWhitelisted(address[] memory _addr) public onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelisted.add(_addr[i]);
        }
    }

    function removeWhitelisted(address[] memory _addr) public onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelisted.remove(_addr[i]);
        }
    }

    function getWhitelisted() external view returns(address[] memory) {
        uint256 length = _whitelisted.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelisted.at(i);
        }

        return result;
    }
}