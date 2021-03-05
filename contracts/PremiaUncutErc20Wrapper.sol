// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import '@openzeppelin/contracts/access/Ownable.sol';

import "./interface/IPremiaUncutErc20.sol";

/// @author Premia
/// @title Wrapper for uPremia reward in PremiaOption contract
/// @notice This wrapper is intended to solve a minor issue where uPremia reward would be minted in PremiaOption contract,
///         instead of user's wallet, when using flash exercise
contract PremiaUncutErc20Wrapper is Ownable {
    IPremiaUncutErc20 public uPremia;
    address public premiaOption;

    constructor(IPremiaUncutErc20 _uPremia, address _premiaOption) {
        uPremia = _uPremia;
        premiaOption = _premiaOption;
    }

    /// @notice Get the usd price of a token
    /// @param _token The token from which to give usd price
    /// @return The usd price
    function getTokenPrice(address _token) external view returns(uint256) {
        return uPremia.getTokenPrice(_token);
    }

    /// @notice Mint uPremia
    /// @param _account The address for which to mint
    /// @param _amount The amount to mint
    function mint(address _account, uint256 _amount) external onlyOwner {
        // Override premiaOption contract into tx origin
        if (_account == premiaOption) {
            _account = tx.origin;
        }

        return uPremia.mint(_account, _amount);
    }

    /// @notice Mint corresponding uPremia reward based on protocol fee paid
    /// @param _account The address for which to mint
    /// @param _token The token in which the protocol fee has been paid
    /// @param _feePaid The fee paid (in _token)
    /// @param _decimals The token decimals
    function mintReward(address _account, address _token, uint256 _feePaid, uint8 _decimals) external onlyOwner {
        // Override premiaOption contract into tx origin
        if (_account == premiaOption) {
            _account = tx.origin;
        }

        return uPremia.mintReward(_account, _token, _feePaid, _decimals);
    }
}
