// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable} from "solady/auth/Ownable.sol";
import {LibBitmap} from "solady/utils/LibBitmap.sol";
import {Solarray} from "solarray/Solarray.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";
import {LinkedList} from "src/lib/LinkedList.sol";

contract PoolRegistry is Ownable {
    using LibBitmap for LibBitmap.Bitmap;
    using Solarray for address[];
    using LinkedList for LinkedList.List;

    struct ExchangePaths {
        uint256 nextIndex;
        mapping(uint256 index => LinkedList.List path) paths;
    }

    // Byte offsets for decoding paths (packed ABI encoding).
    uint256 private constant PATH_POOL_OFFSET = 20;
    uint256 private constant PATH_INPUT_TOKEN_OFFSET = 26;
    uint256 private constant PATH_OUTPUT_TOKEN_OFFSET = 32;

    // Maintaining a numeric index allows our pools to be enumerated.
    uint256 public nextPoolIndex = 0;

    // Pools mapped to their token count for easy lookup and dupe-checking.
    mapping(address pool => uint256 tokenCount) public pools;

    // Pool indexes mapped to pool addresses.
    mapping(uint256 index => address pool) public poolsByIndex;

    // Token pairs mapped to their exchange paths.
    mapping(bytes32 tokenPair => ExchangePaths paths) private _exchangePaths;

    // Token addresses mapped to pool indexes (pool index = bit).
    mapping(address token => LibBitmap.Bitmap poolIndexMap)
        private _poolsByToken;

    event AddPool(
        address indexed pool,
        uint256 indexed poolIndex,
        uint256 indexed tokenCount,
        address[] tokens
    );
    event AddExchangePath(
        bytes32 indexed tokenPair,
        uint256 indexed newPathIndex,
        uint256 indexed newPathLength,
        bytes32[] newPath
    );

    error Duplicate();
    error EmptyArray();

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function _decodePath(
        bytes32 path
    )
        private
        pure
        returns (address pool, uint48 inputTokenIndex, uint48 outputTokenIndex)
    {
        bytes memory _path = abi.encodePacked(path);

        assembly {
            pool := mload(add(_path, PATH_POOL_OFFSET))
            inputTokenIndex := mload(add(_path, PATH_INPUT_TOKEN_OFFSET))
            outputTokenIndex := mload(add(_path, PATH_OUTPUT_TOKEN_OFFSET))
        }
    }

    /**
     * @notice Add a liquidity pool.
     * @param  pool  address  Liquidity pool address.
     */
    function addPool(address pool) external onlyOwner {
        if (pools[pool] != 0) revert Duplicate();

        address[] memory tokens = IStandardPool(pool).tokens();

        // Store the new pool, along with the number of tokens in it.
        pools[pool] = tokens.length;

        // Cache the pool index to save gas and allow `nextPoolIndex` to be incremented.
        uint256 poolIndex = nextPoolIndex;

        // Map index to pool address.
        poolsByIndex[poolIndex] = pool;

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

    function addExchangePath(
        bytes32 tokenPair,
        bytes32[] calldata newPath
    ) external onlyOwner {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        uint256 newPathLength = newPath.length;
        uint256 newPathIndex = exchangePaths.nextIndex;

        ++exchangePaths.nextIndex;

        for (uint256 i = 0; i < newPathLength; ) {
            exchangePaths.paths[newPathIndex].push(newPath[i]);

            unchecked {
                ++i;
            }
        }

        emit AddExchangePath(tokenPair, newPathIndex, newPathLength, newPath);
    }

    function poolsByToken(
        address token
    ) external view returns (address[] memory _pools) {
        uint256 maxIterations = nextPoolIndex;

        for (uint256 i = 0; i < maxIterations; ) {
            // Check whether the bit is set and append to the list of pools for the token.
            if (_poolsByToken[token].get(i))
                _pools = _pools.append(poolsByIndex[i]);

            unchecked {
                ++i;
            }
        }
    }

    function exchangePath(
        bytes32 tokenPair,
        uint256 index
    )
        external
        view
        returns (
            address[] memory paths,
            uint48[] memory inputTokenIndexes,
            uint48[] memory outputTokenIndexes
        )
    {
        bytes32[] memory path = _exchangePaths[tokenPair]
            .paths[index]
            .getKeys();
        uint256 pathLength = path.length;
        paths = new address[](pathLength);
        inputTokenIndexes = new uint48[](pathLength);
        outputTokenIndexes = new uint48[](pathLength);

        for (uint256 i = 0; i < pathLength; ) {
            (
                paths[i],
                inputTokenIndexes[i],
                outputTokenIndexes[i]
            ) = _decodePath(path[i]);

            unchecked {
                ++i;
            }
        }
    }

    function nextExchangePathIndex(
        bytes32 tokenPair
    ) external view returns (uint256) {
        return _exchangePaths[tokenPair].nextIndex;
    }
}
