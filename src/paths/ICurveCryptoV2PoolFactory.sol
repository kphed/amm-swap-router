// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface ICurveCryptoV2PoolFactory {
    function get_coins(address) external view returns (address[3] memory);
}
