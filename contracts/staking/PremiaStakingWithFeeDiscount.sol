// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {PremiaStaking} from "./PremiaStaking.sol";
import {FeeDiscount} from "./FeeDiscount.sol";
import {IPremiaStakingWithFeeDiscount} from "./IPremiaStakingWithFeeDiscount.sol";

contract PremiaStakingWithFeeDiscount is
    IPremiaStakingWithFeeDiscount,
    PremiaStaking,
    FeeDiscount
{
    constructor(address lzEndpoint, address premia)
        PremiaStaking(lzEndpoint, premia)
        FeeDiscount(address(this))
    {}

    function _transferXPremia(
        address holder,
        address recipient,
        uint256 amount
    ) internal override {
        _transfer(holder, recipient, amount);
    }
}
