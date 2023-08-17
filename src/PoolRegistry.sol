// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {EnumerableMap} from "openzeppelin/utils/structs/EnumerableMap.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract PoolRegistry is Ownable {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    EnumerableMap.AddressToUintMap private _pools;

    event SetPool(
        address indexed pool,
        address indexed poolInterface,
        bool indexed isNew
    );

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function _addrToUint256(address addr) private pure returns (uint256) {
        return uint256(uint160(addr));
    }

    function setPool(address pool, address poolInterface) external onlyOwner {
        bool isNew = _pools.set(pool, _addrToUint256(poolInterface));

        emit SetPool(pool, poolInterface, isNew);
    }
}
