// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import '@openzeppelin/contracts/utils/EnumerableSet.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

/// @author Premia
/// @title Keep record of all referrals made
contract PremiaReferral is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Referred => Referrer
    mapping (address => address) public referrals;

    // Addresses allowed to set referrers
    EnumerableSet.AddressSet private _whitelisted;

    ////////////
    // Events //
    ////////////

    event Referral(address indexed referrer, address indexed referred);

    //////////////////////////////////////////////////

    ///////////////
    // Modifiers //
    ///////////////

    modifier onlyWhitelisted() {
        require(_whitelisted.contains(msg.sender), "Not whitelisted");
        _;
    }

    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    /// @notice Add a list of addresses to the whitelist allowing them to set referrals
    /// @param _addr The list of addresses
    function addWhitelisted(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelisted.add(_addr[i]);
        }
    }

    /// @notice Remove a list of addresses from the whitelist preventing them to set referrals
    /// @param _addr The list of addresses
    function removeWhitelisted(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelisted.remove(_addr[i]);
        }
    }

    //////////////////////////////////////////////////

    //////////
    // Main //
    //////////

    /// @notice Set a new referrer if none has been set for referred address + return referrers for given referred
    /// @param _referred The address for which to try to set a referrer
    /// @param _potentialReferrer A potential referrer to set, if the address does not have a referrer yet
    /// @return The referrer of the address
    function trySetReferrer(address _referred, address _potentialReferrer) external onlyWhitelisted returns(address) {
        if (_referred == address(0)) return address(0);

        if (referrals[_referred] == address(0) && _potentialReferrer != address(0)) {
            referrals[_referred] = _potentialReferrer;
            emit Referral(_potentialReferrer, _referred);
        }

        return referrals[_referred];
    }

    /// @notice Get the list of whitelisted addresses allowed to set new referrers
    /// @return The list of whitelisted addresses
    function getWhitelisted() external view returns(address[] memory) {
        uint256 length = _whitelisted.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelisted.at(i);
        }

        return result;
    }
}