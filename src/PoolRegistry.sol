// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable} from "solady/auth/Ownable.sol";

contract PoolRegistry is Ownable {
    struct Pool {
        address pool;
        address[] coins;
    }

    Pool[] public pools;

    event SetPool(address indexed pool);

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function setPool(
        address pool,
        address[] calldata coins
    ) external onlyOwner {
        pools.push(Pool(pool, coins));

        emit SetPool(pool);
    }

    function getPool(uint256 index) external view returns (Pool memory) {
        return pools[index];
    }

    function getAllPools() external view returns (Pool[] memory) {
        return pools;
    }
}
