// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IStandardPool {
    function tokens() external view returns (address[] memory);

    function tokenIndexes(address token) external view returns (uint256);

    function quoteTokenOutput(
        address inputToken,
        address outputToken,
        uint256 inputTokenAmount
    ) external view returns (uint256);

    function quoteTokenInput(
        address inputToken,
        address outputToken,
        uint256 outputTokenAmount
    ) external view returns (uint256);

    function swap(
        address inputToken,
        address outputToken,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount
    ) external returns (uint256);
}
