// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IStandardPool {
    function tokens(address pool) external view returns (address[] memory);

    function quoteTokenOutput(
        address pool,
        uint256 inputTokenIndex,
        uint256 outputTokenIndex,
        uint256 inputTokenAmount
    ) external view returns (uint256);

    function quoteTokenInput(
        address pool,
        uint256 inputTokenIndex,
        uint256 outputTokenIndex,
        uint256 outputTokenAmount
    ) external view returns (uint256);

    function swap(
        address pool,
        uint256 inputTokenIndex,
        uint256 outputTokenIndex,
        uint256 inputTokenAmount
    ) external returns (uint256);
}
