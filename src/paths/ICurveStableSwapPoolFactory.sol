// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface ICurveStableSwapPoolFactory {
    function get_coins(address) external view returns (address[4] memory);
}
