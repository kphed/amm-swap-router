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

    // Path hashes (current swap hash, next swap hash) mapped to path details.
    mapping(bytes32 pathHash => Path path) public paths;

    // Token pairs mapped to their *head* path hashes.
    mapping(bytes32 tokenPairHash => bytes32[] pathHashes) public swapPaths;

    event SetPool(address indexed pool);
    event SetSwap(
        address indexed pool,
        address indexed inputToken,
        address indexed outputToken
    );
    event SetPath(bytes32[] swapHashes, bytes32[] pathHashes);
    event AddSwapPath(bytes32 indexed tokenPairHash, bytes32 indexed pathHash);
    event RemoveSwapPath(bytes32 indexed tokenPairHash, uint256 pathHashIndex);

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

    function setPath(
        bytes32[] calldata swapHashes
    ) external onlyOwner returns (bytes32[] memory pathHashes) {
        uint256 swapHashCounter = swapHashes.length;
        bytes32 nextPathHash;
        bytes32 pathHash;

        pathHashes = new bytes32[](swapHashCounter);

        while (true) {
            --swapHashCounter;

            // Compute the current path hash (swap hash and next path hash).
            pathHash = keccak256(
                abi.encode(swapHashes[swapHashCounter], nextPathHash)
            );

            // Store the path hash which will later be emitted.
            pathHashes[swapHashCounter] = pathHash;

            // Set the path in storage.
            paths[pathHash] = Path(swapHashes[swapHashCounter], nextPathHash);

            // Update the next path hash to the current.
            nextPathHash = pathHash;

            // Loop ends if we're already at the first element.
            if (swapHashCounter == 0) break;
        }

        emit SetPath(swapHashes, pathHashes);
    }

    function addSwapPath(
        address inputToken,
        address outputToken,
        bytes32 pathHash
    ) external onlyOwner {
        bytes32 tokenPairHash = keccak256(
            abi.encodePacked(inputToken, outputToken)
        );

        swapPaths[tokenPairHash].push(pathHash);

        emit AddSwapPath(tokenPairHash, pathHash);
    }

    function removeSwapPath(
        address inputToken,
        address outputToken,
        uint256 pathHashIndex
    ) external onlyOwner {
        bytes32 tokenPairHash = keccak256(
            abi.encodePacked(inputToken, outputToken)
        );
        bytes32[] storage pathHashes = swapPaths[tokenPairHash];
        uint256 lastIndex = pathHashes.length - 1;

        if (pathHashIndex != lastIndex) {
            // Replace the target removal element with the last element in the array.
            pathHashes[pathHashIndex] = pathHashes[lastIndex];
        }

        pathHashes.pop();

        emit RemoveSwapPath(tokenPairHash, pathHashIndex);
    }

    function getPool(uint256 index) external view returns (Pool memory) {
        return pools[index];
    }

    function getAllPools() external view returns (Pool[] memory) {
        return pools;
    }
}
