// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import "../interface/IPremiaLiquidityPool.sol";
import "../interface/IPoolControllerChild.sol";
import "../interface/IPremiaMiningV2.sol";

contract PremiaPoolController is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct DepositArgs {
        address pool;
        address[] tokens;
        uint256[] amounts;
        uint256 lockExpiration;
    }

    struct WithdrawExpiredArgs {
        address pool;
        address[] tokens;
    }

    // List of whitelisted liquidity pools;
    EnumerableSet.AddressSet private _whitelistedPools;

    IPremiaMiningV2 public premiaMining;

    ///////////
    // Event //
    ///////////

    event PremiaMiningUpdated(address indexed _addr);

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    ///////////
    // Admin //
    ///////////

    function upgradeController(IPoolControllerChild[] memory _children, address _newController) external onlyOwner {
        for (uint256 i=0; i < _children.length; i++) {
            _children[i].upgradeController(_newController);
        }
    }

    function setPremiaMining(IPremiaMiningV2 _premiaMining) external onlyOwner {
        premiaMining = _premiaMining;
        emit PremiaMiningUpdated(address(_premiaMining));
    }

    /// @notice Add contract addresses to the list of whitelisted option contracts
    /// @param _addr The list of addresses to add
    function addWhitelistedPools(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedPools.add(_addr[i]);
        }
    }

    /// @notice Remove contract addresses from the list of whitelisted option contracts
    /// @param _addr The list of addresses to remove
    function removeWhitelistedPools(address[] memory _addr) external onlyOwner {
        for (uint256 i=0; i < _addr.length; i++) {
            _whitelistedPools.remove(_addr[i]);
        }
    }

    //////////
    // View //
    //////////

    /// @notice Get the list of whitelisted option contracts
    /// @return The list of whitelisted option contracts
    function getWhitelistedPools() external view returns(address[] memory) {
        uint256 length = _whitelistedPools.length();
        address[] memory result = new address[](length);

        for (uint256 i=0; i < length; i++) {
            result[i] = _whitelistedPools.at(i);
        }

        return result;
    }

    //////////
    // Main //
    //////////

    function deposit(DepositArgs[] memory _deposits) external nonReentrant {
        for (uint256 i=0; i < _deposits.length; i++) {
            require(_whitelistedPools.contains(_deposits[i].pool), "Pool not whitelisted");
            IPremiaLiquidityPool(_deposits[i].pool).depositFrom(msg.sender, _deposits[i].tokens, _deposits[i].amounts, _deposits[i].lockExpiration);

            if (address(premiaMining) != address(0)) {
                for (uint256 j=0; j < _deposits[i].tokens.length; j++) {
                    premiaMining.deposit(msg.sender, _deposits[i].tokens[j], _deposits[i].amounts[j], _deposits[i].lockExpiration);
                }
            }
        }
    }

    function withdrawExpired(WithdrawExpiredArgs[] memory _withdrawals) external nonReentrant {
        for (uint256 i=0; i < _withdrawals.length; i++) {
            require(_whitelistedPools.contains(_withdrawals[i].pool), "Pool not whitelisted");
            IPremiaLiquidityPool(_withdrawals[i].pool).withdrawExpiredFrom(msg.sender, _withdrawals[i].tokens);
        }
    }
}
