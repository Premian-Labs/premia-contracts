// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IPremiaMaker {
    event Converted(
        address indexed account,
        address indexed router,
        address indexed token,
        uint256 tokenAmount,
        uint256 premiaAmount
    );

    function getCustomPath(address _token)
        external
        view
        returns (address[] memory);

    function getWhitelistedRouters() external view returns (address[] memory);

    function convert(address _router, address _token) external;

    function withdrawFeesAndConvert(
        address _pool,
        address _router,
        address[] memory _tokens
    ) external;
}
