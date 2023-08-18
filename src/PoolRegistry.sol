// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

contract PoolRegistry is Ownable {
    using SafeCastLib for uint256;

    struct Pool {
        address pool;
        address[] tokens;
    }

    struct Swap {
        address pool;
        uint48 inputTokenIndex;
        uint48 outputTokenIndex;
    }

    struct Path {
        bytes32 swapHash;
        // Hash of the current swapHash and the next swapHash.
        bytes32 nextPathHash;
    }

    // Liquidity pools.
    Pool[] public pools;

    // Swap hashes (pool, input index, output index) mapped to swap details.
    mapping(bytes32 swapHash => Swap swap) public swaps;

    // Pash hashes (current swap hash, next swap hash) mapped to path details.
    mapping(bytes32 pathHash => Path path) public paths;

    // Token swap paths for a single pair.
    mapping(bytes32 tokenPairHash => bytes32[] swapHashes) public swapPaths;

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
        address[] calldata tokens
    ) external onlyOwner {
        pools.push(Pool(pool, tokens));

        emit SetPool(pool);
    }

    function setSwap(
        uint256 poolIndex,
        uint256 inputTokenIndex,
        uint256 outputTokenIndex
    ) external onlyOwner returns (bytes32 swapHash) {
        Pool memory pool = pools[poolIndex];
        swapHash = keccak256(
            // Allows us to store the swap at a unique ID and easily look up.
            abi.encode(
                pool.pool,
                pool.tokens[inputTokenIndex],
                pool.tokens[outputTokenIndex]
            )
        );
        swaps[swapHash] = Swap(
            pool.pool,
            inputTokenIndex.toUint48(),
            outputTokenIndex.toUint48()
        );

        emit SetSwap(
            pool.pool,
            pool.tokens[inputTokenIndex],
            pool.tokens[outputTokenIndex]
        );
    }

    function setPath(bytes32[] calldata swapHashes) external onlyOwner {
        // Start from the last swap hash index.
        uint256 swapHashIndex = swapHashes.length - 1;

        // Compute the tail nextPathHash since it's a special case.
        bytes32 nextPathHash = keccak256(
            abi.encode(swapHashes[swapHashIndex], bytes32(0))
        );

        while (true) {
            --swapHashIndex;

            // Compute the current path hash (swap hash and next path hash).
            bytes32 pathHash = keccak256(
                abi.encode(swapHashes[swapHashIndex], nextPathHash)
            );

            // Store the path in order to retrieve in the future.
            paths[pathHash] = Path(pathHash, nextPathHash);

            // Update the next path hash to the current.
            nextPathHash = pathHash;

            if (swapHashIndex == 0) break;
        }
    }

    function getPool(uint256 index) external view returns (Pool memory) {
        return pools[index];
    }

    function getAllPools() external view returns (Pool[] memory) {
        return pools;
    }
}
