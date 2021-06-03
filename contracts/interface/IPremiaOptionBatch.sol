// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './IPremiaOption.sol';

/// @author Premia
interface IPremiaOptionBatch {
    function batchWriteOption(IPremiaOption _premiaOption, IPremiaOption.OptionWriteArgs[] memory _options) external;
    function batchCancelOption(IPremiaOption _premiaOption, uint256[] memory _optionId, uint256[] memory _amounts) external;
    function batchWithdraw(IPremiaOption _premiaOption, uint256[] memory _optionId) external;
    function batchExerciseOption(IPremiaOption _premiaOption, uint256[] memory _optionId, uint256[] memory _amounts) external;
    function batchWithdrawPreExpiration(IPremiaOption _premiaOption, uint256[] memory _optionId, uint256[] memory _amounts) external;
}
