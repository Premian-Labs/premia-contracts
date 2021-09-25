// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IPool} from "./pool/IPool.sol";
import {PoolStorage} from "./pool/PoolStorage.sol";
import {NFTDisplay} from "./libraries/NFTDisplay.sol";
import {IPremiaOptionNFTDisplay} from "./IPremiaOptionNFTDisplay.sol";

contract PremiaOptionNFTDisplay is IPremiaOptionNFTDisplay {
    using Strings for uint256;

    function tokenURI(address _pool, uint256 _tokenId)
        external
        view
        override
        returns (string memory)
    {
        IPool pool = IPool(_pool);
        PoolStorage.PoolSettings memory settings = pool.getPoolSettings();
        (
            PoolStorage.TokenType tokenType,
            uint64 maturity,
            int128 strikePrice
        ) = pool.getParametersForTokenId(_tokenId);

        bool isCall = tokenType == PoolStorage.TokenType.SHORT_CALL ||
            tokenType == PoolStorage.TokenType.LONG_CALL;
        bool isLong = tokenType == PoolStorage.TokenType.LONG_CALL ||
            tokenType == PoolStorage.TokenType.LONG_PUT;

        IERC20Metadata baseToken = IERC20Metadata(settings.base);
        IERC20Metadata underlyingToken = IERC20Metadata(settings.underlying);

        return
            NFTDisplay.buildTokenURI(
                NFTDisplay.BuildTokenURIParams({
                    tokenId: _tokenId,
                    pool: _pool,
                    base: settings.base,
                    underlying: settings.underlying,
                    maturity: maturity,
                    strikePrice: strikePrice,
                    isCall: isCall,
                    isLong: isLong,
                    baseSymbol: baseToken.symbol(),
                    underlyingSymbol: underlyingToken.symbol()
                })
            );
    }
}
