// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable} from "solady/auth/Ownable.sol";
import {LibBitmap} from "solady/utils/LibBitmap.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";

contract PoolRegistry is Ownable {
    using LibBitmap for LibBitmap.Bitmap;

    // Maintaining a numeric index allows our pools to be enumerated.
    uint256 public nextPoolIndex = 0;

    // Liquidity pools and their token count.
    mapping(address pool => uint256 tokenCount) public pools;

    // Pool indexes mapped to pool addresses.
    mapping(uint256 index => address pool) public poolIndexes;

    // Token addresses mapped to pool indexes (pool index = bit).
    mapping(address token => LibBitmap.Bitmap) private _tokenPools;

    event AddPool(
        address indexed pool,
        uint256 indexed poolIndex,
        uint256 indexed tokenCount,
        address[] tokens
    );

    error PoolAlreadyExists();

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    /**
     * @notice Add a liquidity pool.
     * @param  pool  address  Liquidity pool address.
     */
    function addPool(address pool) external onlyOwner {
        if (pools[pool] != 0) revert PoolAlreadyExists();

        address[] memory tokens = IStandardPool(pool).tokens();

        // Store the new pool, along with the number of tokens in it.
        pools[pool] = tokens.length;

        // Cache the pool index to save gas and allow `nextPoolIndex` to be incremented.
        uint256 poolIndex = nextPoolIndex;

        // Map index to pool address.
        poolIndexes[poolIndex] = pool;

        ++nextPoolIndex;

        uint256 tokenIndex = tokens.length - 1;

        while (true) {
            // Set the bit equal to the pool index for each token in the pool.
            _tokenPools[tokens[tokenIndex]].set(poolIndex);

            // Break loop if all pool tokens have had their bits set.
            if (tokenIndex == 0) break;

            --tokenIndex;
        }

        emit AddPool(pool, poolIndex, tokens.length, tokens);
    }

    function getTokenPool(
        address token,
        uint256 poolIndex
    ) external view returns (bool) {
        return _tokenPools[token].get(poolIndex);
    }
}
