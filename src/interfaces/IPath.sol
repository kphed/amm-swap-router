// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPath {
    function pool() external pure returns (address);

    function tokens()
        external
        view
        returns (address inputToken, address outputToken);

    function quoteTokenOutput(uint256 amount) external view returns (uint256);

    function quoteTokenInput(uint256 amount) external view returns (uint256);

    function swap(uint256 amount) external returns (uint256);
}
