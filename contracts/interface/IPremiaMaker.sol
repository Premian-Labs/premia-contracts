// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPremiaMaker {
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
