// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IERC20} from "@solidstate/contracts/token/ERC20/IERC20.sol";
import {ERC20BaseInternal} from "@solidstate/contracts/token/ERC20/base/ERC20BaseInternal.sol";
import {IERC2612} from "@solidstate/contracts/token/ERC20/permit/IERC2612.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import "./IPremiaStaking.sol";

contract PremiaStakingMigration is ERC20BaseInternal {
    using SafeERC20 for IERC20;

    address private immutable PREMIA;
    address private immutable XPREMIA_OLD;

    constructor(address premia, address xPremiaOld) {
        PREMIA = premia;
        XPREMIA_OLD = xPremiaOld;
    }

    /**
     * @notice migrate deprecated xPremia using IERC2612 permit
     * @param amount quantity of xPremia to migrate
     * @param deadline timestamp after which permit will fail
     * @param v signature "v" value
     * @param r signature "r" value
     * @param s signature "s" value
     */
    function migrateWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        IERC2612(XPREMIA_OLD).permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );
        migrate(amount);
    }

    /**
     * @notice migrate deprecated xPremia
     * @param amount quantity of xPremia to migrate
     */
    function migrate(uint256 amount) public {
        IERC20(XPREMIA_OLD).safeTransferFrom(msg.sender, address(this), amount);

        uint256 oldPremiaBalance = IERC20(PREMIA).balanceOf(address(this));
        IPremiaStaking(XPREMIA_OLD).leave(amount);
        uint256 newPremiaBalance = IERC20(PREMIA).balanceOf(address(this));

        uint256 oldXPremiaBalance = _balanceOf(address(this));
        IPremiaStaking(address(this)).enter(
            newPremiaBalance - oldPremiaBalance
        );
        uint256 newXPremiaBalance = _balanceOf(address(this));

        _transfer(
            address(this),
            msg.sender,
            newXPremiaBalance - oldXPremiaBalance
        );
    }
}
