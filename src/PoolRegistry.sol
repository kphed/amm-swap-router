// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

contract PoolRegistry is Ownable {
    using SafeCastLib for uint256;

    struct Pool {
        address pool;
        address[] coins;
    }

    struct Swap {
        address pool;
        uint48 inputTokenIndex;
        uint48 outputTokenIndex;
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
    event SetSwap(
        address indexed pool,
        address indexed inputToken,
        address indexed outputToken
    );

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

    function setSwap(
        uint256 poolIndex,
        uint256 inputTokenIndex,
        uint256 outputTokenIndex
    ) external onlyOwner {
        Pool memory pool = pools[poolIndex];

        swaps[
            keccak256(
                // Allows us to store the swap at a unique ID and easily look up.
                abi.encode(
                    pool.pool,
                    pool.coins[inputTokenIndex],
                    pool.coins[outputTokenIndex]
                )
            )
        ] = Swap(
            pool.pool,
            inputTokenIndex.toUint48(),
            outputTokenIndex.toUint48()
        );

        emit SetSwap(
            pool.pool,
            pool.coins[inputTokenIndex],
            pool.coins[outputTokenIndex]
        );
    }

    function getPool(uint256 index) external view returns (Pool memory) {
        return pools[index];
    }

    function getAllPools() external view returns (Pool[] memory) {
        return pools;
    }
}
