// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IStandardPool {
    function pool() external pure returns (address);

    function tokens() external view returns (address[] memory);

    function quoteTokenOutput(uint256 amount) external view returns (uint256);

    function quoteTokenInput(uint256 amount) external view returns (uint256);

    function swap(uint256 amount) external returns (uint256);
}
