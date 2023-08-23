// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IStandardPoolV2 {
    function tokens(address pool) external view returns (address[] memory);
}
