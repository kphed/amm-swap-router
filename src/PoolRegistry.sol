// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable} from "solady/auth/Ownable.sol";

contract PoolRegistry is Ownable {
    struct Pool {
        address pool;
        address[] coins;
    }

    struct Swap {
        address pool;
        address inputToken;
        address outputToken;
    }

    struct Path {
        address path;
        bytes32 nextPathHash;
    }

    // Liquidity pools.
    Pool[] public pools;

    // Swaps.
    mapping(bytes32 swapHash => Swap swap) public swaps;

    // Token swap paths for a single pair.
    mapping(bytes32 tokenPairHash => Path[] path) public paths;

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
