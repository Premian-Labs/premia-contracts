// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "base64-sol/base64.sol";

import {NFTSVG} from "./NFTSVG.sol";

library NFTDisplay {
    using Strings for uint256;
    using Strings for uint256;
    using ABDKMath64x64 for int128;

    uint256 constant SECONDS_PER_DAY = 24 * 60 * 60;
    uint256 constant SECONDS_PER_HOUR = 60 * 60;
    uint256 constant SECONDS_PER_MINUTE = 60;
    int256 constant OFFSET19700101 = 2440588;

    struct BuildTokenURIParams {
        uint256 tokenId;
        address pool;
        address base;
        address underlying;
        uint64 maturity;
        int128 strikePrice;
        bool isCall;
        bool isLong;
        string baseSymbol;
        string underlyingSymbol;
    }

    function buildTokenURI(BuildTokenURIParams memory _params)
        public
        pure
        returns (string memory)
    {
        string memory base64image;

        {
            string memory svgImage = buildSVGImage(_params);
            base64image = Base64.encode(bytes(svgImage));
        }

        string memory description = buildDescription(_params);
        string memory name = buildName(_params);
        string memory attributes = buildAttributes(_params);

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                "{",
                                '"image":"',
                                "data:image/svg+xml;base64,",
                                base64image,
                                '",',
                                '"description":"',
                                description,
                                '",',
                                '"name":"',
                                name,
                                '",',
                                attributes,
                                "}"
                            )
                        )
                    )
                )
            );
    }

    function buildSVGImage(BuildTokenURIParams memory _params)
        public
        pure
        returns (string memory)
    {
        string memory maturityString = maturityToString(_params.maturity);
        string memory strikePriceString = fixedToDecimalString(
            _params.strikePrice
        );

        return
            NFTSVG.buildSVG(
                NFTSVG.CreateSVGParams({
                    isCall: _params.isCall,
                    isLong: _params.isLong,
                    baseSymbol: _params.baseSymbol,
                    underlyingSymbol: _params.underlyingSymbol,
                    strikePriceString: strikePriceString,
                    maturityString: maturityString
                })
            );
    }

    function buildDescription(BuildTokenURIParams memory _params)
        public
        pure
        returns (string memory)
    {
        string memory descriptionPartA = buildDescriptionPartA(
            _params.pool,
            _params.base,
            _params.underlying,
            _params.baseSymbol,
            _params.underlyingSymbol,
            _params.isLong
        );

        return
            string(
                abi.encodePacked(
                    descriptionPartA,
                    _params.baseSymbol,
                    "\\n\\nMaturity: ",
                    maturityToString(_params.maturity),
                    "\\n\\nStrike Price: ",
                    strikePriceToString(
                        _params.strikePrice,
                        _params.baseSymbol
                    ),
                    "\\n\\nType: ",
                    optionTypeToString(_params.isCall, _params.isLong),
                    "\\n\\nToken ID: ",
                    _params.tokenId.toString(),
                    "\\n\\n",
                    unicode"⚠️ DISCLAIMER: Due diligence is imperative when assessing this NFT. Double check the option details and make sure token addresses match the expected tokens, as token symbols may be imitated."
                )
            );
    }

    function buildDescriptionPartA(
        address pool,
        address base,
        address underlying,
        string memory baseSymbol,
        string memory underlyingSymbol,
        bool isLong
    ) public pure returns (string memory) {
        string memory pairName = getPairName(baseSymbol, underlyingSymbol);
        bytes memory bufferA = abi.encodePacked(
            "This NFT represents a ",
            longShortToString(isLong),
            " option position in a Premia V2 ",
            pairName,
            " pool. The owner of the NFT can transfer or ",
            isLong ? "exercise" : "sell",
            " the position.",
            "\\n\\nPool Address: "
        );

        bytes memory bufferB = abi.encodePacked(
            addressToString(pool),
            "\\n\\n",
            underlyingSymbol,
            " Address: ",
            addressToString(underlying),
            "\\n\\n",
            " Address: ",
            addressToString(base)
        );

        return string(abi.encodePacked(bufferA, bufferB));
    }

    function buildName(BuildTokenURIParams memory _params)
        public
        pure
        returns (string memory)
    {
        string memory pairName = getPairName(
            _params.baseSymbol,
            _params.underlyingSymbol
        );

        return
            string(
                abi.encodePacked(
                    "Premia - ",
                    pairName,
                    " - ",
                    maturityToString(_params.maturity),
                    " - ",
                    strikePriceToString(
                        _params.strikePrice,
                        _params.baseSymbol
                    ),
                    " - ",
                    optionTypeToString(_params.isCall, _params.isLong)
                )
            );
    }

    function buildAttributes(BuildTokenURIParams memory _params)
        public
        pure
        returns (string memory)
    {
        string memory pairName = getPairName(
            _params.baseSymbol,
            _params.underlyingSymbol
        );

        bytes memory buffer = abi.encodePacked(
            '"attributes":[',
            '{"trait_type":"Market","value":"Premia V2"},',
            '{"trait_type":"Pair","value":"',
            pairName,
            '"},',
            '{"trait_type":"Underlying Token","value":"',
            addressToString(_params.underlying),
            '"},'
        );

        return
            string(
                abi.encodePacked(
                    buffer,
                    '{"trait_type":"Base Token","value":"',
                    addressToString(_params.base),
                    '"},',
                    '{"trait_type":"Maturity","value":"',
                    maturityToString(_params.maturity),
                    '"},',
                    '{"trait_type":"Strike Price","value":"',
                    strikePriceToString(
                        _params.strikePrice,
                        _params.baseSymbol
                    ),
                    '"},',
                    '{"trait_type":"Type","value":"',
                    optionTypeToString(_params.isCall, _params.isLong),
                    '"}',
                    "]"
                )
            );
    }

    function getPairName(
        string memory baseSymbol,
        string memory underlyingSymbol
    ) public pure returns (string memory) {
        return string(abi.encodePacked(underlyingSymbol, "/", baseSymbol));
    }

    function maturityToString(uint64 maturity)
        internal
        pure
        returns (string memory)
    {
        (uint256 year, uint256 month, uint256 date) = timestampToDate(maturity);

        return
            string(
                abi.encodePacked(
                    date.toString(),
                    "-",
                    monthToString(month),
                    "-",
                    year.toString()
                )
            );
    }

    function strikePriceToString(int128 strikePrice, string memory baseSymbol)
        internal
        pure
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    fixedToDecimalString(strikePrice),
                    " ",
                    baseSymbol
                )
            );
    }

    function optionTypeToString(bool isCall, bool isLong)
        internal
        pure
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    isLong ? "LONG " : "SHORT ",
                    isCall ? "CALL" : "PUT"
                )
            );
    }

    function longShortToString(bool isLong)
        internal
        pure
        returns (string memory)
    {
        return isLong ? "LONG" : "SHORT";
    }

    function monthToString(uint256 month)
        internal
        pure
        returns (string memory)
    {
        if (month == 1) {
            return "JAN";
        } else if (month == 2) {
            return "FEB";
        } else if (month == 3) {
            return "MAR";
        } else if (month == 4) {
            return "APR";
        } else if (month == 5) {
            return "MAY";
        } else if (month == 6) {
            return "JUN";
        } else if (month == 7) {
            return "JUL";
        } else if (month == 8) {
            return "AUG";
        } else if (month == 9) {
            return "SEP";
        } else if (month == 10) {
            return "OCT";
        } else if (month == 11) {
            return "NOV";
        }

        return "DEC";
    }

    function addressToString(address addr) public pure returns (string memory) {
        bytes memory data = abi.encodePacked(addr);
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[3 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }

    function fixedToDecimalString(int128 value64x64)
        public
        pure
        returns (string memory)
    {
        bool negative = value64x64 < 0;
        uint256 integer = uint256(value64x64.abs().toUInt());
        int128 decimal64x64 = value64x64 - int128(int256(integer << 64));
        uint256 decimal = (decimal64x64 * 1000).toUInt();
        string memory decimalString = "";

        if (decimal > 0) {
            decimalString = string(
                abi.encodePacked(".", onlySignificant(decimal))
            );
        }

        return
            string(
                abi.encodePacked(
                    negative ? "-" : "",
                    commaSeparateInteger(integer),
                    decimalString
                )
            );
    }

    function onlySignificant(uint256 decimal)
        public
        pure
        returns (string memory)
    {
        bytes memory b = bytes(decimal.toString());
        bytes memory buffer;
        bool foundSignificant;

        for (uint256 i; i < b.length; i++) {
            if (!foundSignificant && b[b.length - i - 1] != bytes1("0"))
                foundSignificant = true;

            if (foundSignificant) {
                buffer = abi.encodePacked(b[b.length - i - 1], buffer);
            }
        }

        return string(buffer);
    }

    function commaSeparateInteger(uint256 integer)
        public
        pure
        returns (string memory)
    {
        bytes memory b = bytes(integer.toString());
        bytes memory buffer;

        for (uint256 i; i < b.length; i++) {
            if (i > 0 && i % 3 == 0) {
                buffer = abi.encodePacked(b[b.length - i - 1], ",", buffer);
            } else {
                buffer = abi.encodePacked(b[b.length - i - 1], buffer);
            }
        }

        return string(buffer);
    }

    /*
     * Source: https://github.com/bokkypoobah/BokkyPooBahsDateTimeLibrary/blob/master/contracts/BokkyPooBahsDateTimeLibrary.sol
     */
    function timestampToDate(uint256 timestamp)
        internal
        pure
        returns (
            uint256 year,
            uint256 month,
            uint256 day
        )
    {
        (year, month, day) = _daysToDate(timestamp / SECONDS_PER_DAY);
    }

    function _daysToDate(uint256 _days)
        internal
        pure
        returns (
            uint256 year,
            uint256 month,
            uint256 day
        )
    {
        int256 __days = int256(_days);

        int256 L = __days + 68569 + OFFSET19700101;
        int256 N = (4 * L) / 146097;
        L = L - (146097 * N + 3) / 4;
        int256 _year = (4000 * (L + 1)) / 1461001;
        L = L - (1461 * _year) / 4 + 31;
        int256 _month = (80 * L) / 2447;
        int256 _day = L - (2447 * _month) / 80;
        L = _month / 11;
        _month = _month + 2 - 12 * L;
        _year = 100 * (N - 49) + _year + L;

        year = uint256(_year);
        month = uint256(_month);
        day = uint256(_day);
    }
}
