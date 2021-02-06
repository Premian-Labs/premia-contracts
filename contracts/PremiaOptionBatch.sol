// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./interface/IPremiaOption.sol";

/// @author Premia
/// @title Batch functions to interact with PremiaOption
contract PremiaOptionBatch {
    /// @notice Write multiple options at once
    /// @param _premiaOption A PremiaOption contract
    /// @param _options Options to write
    /// @param _referrer Referrer
    function batchWriteOption(IPremiaOption _premiaOption, IPremiaOption.OptionWriteArgs[] memory _options, address _referrer) external {
        for (uint256 i = 0; i < _options.length; ++i) {
            _premiaOption.writeOptionFrom(msg.sender, _options[i], _referrer);
        }
    }

    /// @notice Cancel multiple options at once
    /// @param _premiaOption A PremiaOption contract
    /// @param _optionId List of ids of options to cancel
    /// @param _amounts Amount to cancel for each option
    function batchCancelOption(IPremiaOption _premiaOption, uint256[] memory _optionId, uint256[] memory _amounts) external {
        require(_optionId.length == _amounts.length, "Arrays diff len");

        for (uint256 i = 0; i < _optionId.length; ++i) {
            _premiaOption.cancelOptionFrom(msg.sender, _optionId[i], _amounts[i]);
        }
    }

    /// @notice Withdraw funds from multiple options at once
    /// @param _premiaOption A PremiaOption contract
    /// @param _optionId List of ids of options to withdraw funds from
    function batchWithdraw(IPremiaOption _premiaOption, uint256[] memory _optionId) external {
        for (uint256 i = 0; i < _optionId.length; ++i) {
            _premiaOption.withdrawFrom(msg.sender, _optionId[i]);
        }
    }

    /// @notice Exercise multiple options at once
    /// @param _premiaOption A PremiaOption contract
    /// @param _optionId List of ids of options to exercise
    /// @param _amounts Amount to exercise for each option
    /// @param _referrer Referrer
    function batchExerciseOption(IPremiaOption _premiaOption, uint256[] memory _optionId, uint256[] memory _amounts, address _referrer) external {
        require(_optionId.length == _amounts.length, "Arrays diff len");

        for (uint256 i = 0; i < _optionId.length; ++i) {
            _premiaOption.exerciseOptionFrom(msg.sender, _optionId[i], _amounts[i], _referrer);
        }
    }

    /// @notice Withdraw funds pre expiration from multiple options at once
    /// @param _premiaOption A PremiaOption contract
    /// @param _optionId List of ids of options to withdraw funds from
    /// @param _amounts Amount to withdraw pre expiration for each option
    function batchWithdrawPreExpiration(IPremiaOption _premiaOption, uint256[] memory _optionId, uint256[] memory _amounts) external {
        require(_optionId.length == _amounts.length, "Arrays diff len");

        for (uint256 i = 0; i < _optionId.length; ++i) {
            _premiaOption.withdrawPreExpirationFrom(msg.sender, _optionId[i], _amounts[i]);
        }
    }
}
