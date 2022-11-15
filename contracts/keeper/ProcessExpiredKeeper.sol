// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {KeeperCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import {IERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/IERC1155Enumerable.sol";
import {IProxyManager} from "../core/IProxyManager.sol";
import {IPoolExercise} from "../pool/IPoolExercise.sol";
import {IPoolView} from "../pool/IPoolView.sol";
import {PoolStorage} from "../pool/PoolStorage.sol";

contract ProcessExpiredKeeper is KeeperCompatibleInterface {
    address private immutable PREMIA_DIAMOND;

    constructor(address premiaDiamond) {
        PREMIA_DIAMOND = premiaDiamond;
    }

    function checkUpkeep(
        bytes calldata
    ) external view returns (bool upkeepNeeded, bytes memory performData) {
        address[] memory poolList = IProxyManager(PREMIA_DIAMOND).getPoolList();

        for (uint256 i = 0; i < poolList.length; i++) {
            uint256[] memory tokenIds = IPoolView(poolList[i]).getTokenIds();

            for (uint256 j = 0; j < tokenIds.length; j++) {
                (
                    PoolStorage.TokenType tokenType,
                    uint64 maturity,

                ) = PoolStorage.parseTokenId(tokenIds[j]);

                if (
                    tokenType != PoolStorage.TokenType.LONG_CALL &&
                    tokenType != PoolStorage.TokenType.LONG_PUT
                ) continue;
                if (maturity > block.timestamp) continue;

                uint256 supply = IERC1155Enumerable(poolList[i]).totalSupply(
                    tokenIds[j]
                );
                return (true, abi.encode(poolList[i], tokenIds[j], supply));
            }
        }

        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external {
        (address pool, uint256 longTokenId, uint256 supply) = abi.decode(
            performData,
            (address, uint256, uint256)
        );

        IPoolExercise(pool).processExpired(longTokenId, supply);
    }
}
