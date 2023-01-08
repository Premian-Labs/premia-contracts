// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";

import {PoolBase} from "../pool/PoolBase.sol";
import {PoolStorage} from "../pool/PoolStorage.sol";

contract PoolMock is PoolBase {
    using PoolStorage for PoolStorage.Layout;

    constructor(
        address ivolOracle,
        address wrappedNativeToken,
        address premiaMining,
        address feeReceiver,
        address feeDiscount,
        int128 feePremium64x64,
        address exchangeHelper
    )
        PoolBase(
            ivolOracle,
            wrappedNativeToken,
            premiaMining,
            feeReceiver,
            feeDiscount,
            feePremium64x64,
            exchangeHelper
        )
    {}

    function formatTokenId(
        PoolStorage.TokenType tokenType,
        uint64 maturity,
        int128 strikePrice
    ) external pure returns (uint256) {
        return PoolStorage.formatTokenId(tokenType, maturity, strikePrice);
    }

    function parseTokenId(
        uint256 tokenId
    ) external pure returns (PoolStorage.TokenType, uint64, int128) {
        return PoolStorage.parseTokenId(tokenId);
    }

    function mint(address account, uint256 tokenId, uint256 amount) external {
        _mint(account, tokenId, amount);
    }

    function burn(address account, uint256 tokenId, uint256 amount) external {
        _burn(account, tokenId, amount);
    }

    function addUnderwriter(address account, bool isCallPool) external {
        PoolStorage.addUnderwriter(PoolStorage.layout(), account, isCallPool);
    }

    function removeUnderwriter(address account, bool isCallPool) external {
        PoolStorage.removeUnderwriter(
            PoolStorage.layout(),
            account,
            isCallPool
        );
    }

    function getUnderwriter() external view returns (address) {
        return PoolStorage.layout().liquidityQueueAscending[true][address(0)];
    }

    function getPriceUpdateAfter(
        uint256 timestamp
    ) external view returns (int128) {
        return PoolStorage.layout().getPriceUpdateAfter(timestamp);
    }

    function setPriceUpdate(uint256 timestamp, int128 price64x64) external {
        PoolStorage.layout().setPriceUpdate(timestamp, price64x64);
    }
}
