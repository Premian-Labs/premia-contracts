// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {PremiaStaking} from "./PremiaStaking.sol";
import {FeeDiscount} from "./FeeDiscount.sol";

contract PremiaStakingWithFeeDiscount is PremiaStaking, FeeDiscount {
    constructor(address premia)
        PremiaStaking(premia)
        FeeDiscount(address(this))
    {}

    function _transferPremia(
        address holder,
        address recipient,
        uint256 amount
    ) internal override {
        _transfer(holder, recipient, amount);
    }
}
