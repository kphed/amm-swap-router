// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable} from "solady/auth/Ownable.sol";
import {LibBitmap} from "solady/utils/LibBitmap.sol";
import {Solarray} from "solarray/Solarray.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";

contract PoolRegistry is Ownable {
    using LibBitmap for LibBitmap.Bitmap;
    using Solarray for address[];

    // Maintaining a numeric index allows our pools to be enumerated.
    uint256 public nextPoolIndex = 0;

    // Liquidity pools and their token count.
    mapping(address pool => uint256 tokenCount) public pools;

    // Pool indexes mapped to pool addresses.
    mapping(uint256 index => address pool) public poolIndexes;

    // Token addresses mapped to pool indexes (pool index = bit).
    mapping(address token => LibBitmap.Bitmap poolIndexes)
        private _poolsByToken;

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

        unchecked {
            // Extremely unlikely to ever overflow.
            ++nextPoolIndex;

            // If this underflows, will result in index OOB error when reading the `tokens` array below.
            uint256 tokenIndex = tokens.length - 1;

            while (true) {
                // Set the bit equal to the pool index for each token in the pool.
                _poolsByToken[tokens[tokenIndex]].set(poolIndex);

                // Break loop if all pool tokens have had their bits set.
                if (tokenIndex == 0) break;

                // Will not overflow due to the loop break check.
                --tokenIndex;
            }
        }

        emit AddPool(pool, poolIndex, tokens.length, tokens);
    }

    function poolsByToken(
        address token
    ) external view returns (address[] memory _pools) {
        uint256 maxIterations = nextPoolIndex;

        for (uint256 i = 0; i < maxIterations; ) {
            // Check whether the bit is set and append to the list of pools for the token.
            if (_poolsByToken[token].get(i))
                _pools = _pools.append(poolIndexes[i]);

            unchecked {
                ++i;
            }
        }
    }
}
