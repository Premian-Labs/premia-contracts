// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IPremiaBondingCurveUpgrade} from "./interface/IPremiaBondingCurveUpgrade.sol";
import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

contract PremiaBondingCurveDeprecation is IPremiaBondingCurveUpgrade {
    using SafeERC20 for IERC20;

    address internal immutable PREMIA;
    address internal immutable TIMELOCK;
    address internal immutable TREASURY;

    constructor(
        address _premia,
        address _timelock,
        address _treasury
    ) {
        PREMIA = _premia;
        TIMELOCK = _timelock;
        TREASURY = _treasury;
    }

    function initialize(
        uint256 _premiaBalance,
        uint256,
        uint256
    ) external payable override {
        // Send PREMIA to timelocked contract
        IERC20(PREMIA).safeTransfer(TIMELOCK, _premiaBalance);

        if (msg.value > 0) {
            // Send with data to avoid multisig contract to reject transfer
            (bool sent, ) = payable(TREASURY).call{value: msg.value}("0x1");
            require(sent, "ETH transfer failed");
        }
    }
}
