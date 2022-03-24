// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

import {INewPremiaFeeDiscount} from "./INewPremiaFeeDiscount.sol";

interface IPremiaFeeDiscountOld {
    function setNewContract(INewPremiaFeeDiscount _newContract) external;

    function migrateStake() external;
}
