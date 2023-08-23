// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {LibBitmap} from "solady/utils/LibBitmap.sol";
import {Solarray} from "solarray/Solarray.sol";
import {LinkedList} from "src/lib/LinkedList.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";

contract PoolRegistry is Ownable {
    using LibBitmap for LibBitmap.Bitmap;
    using Solarray for address[];
    using LinkedList for LinkedList.List;
    using SafeTransferLib for address;

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

    mapping(address pool => IStandardPool poolInterface) public poolInterfaces;
    mapping(address pool => address[] tokens) public poolTokens;
    mapping(uint256 index => address pool) public poolIndexes;
    mapping(bytes32 tokenPair => ExchangePaths paths) private _exchangePaths;
    mapping(address token => LibBitmap.Bitmap poolIndexes) private _tokenPools;

    event AddPool(address indexed pool, IStandardPool indexed poolInterface, uint256 indexed poolIndex);
    event AddExchangePath(
        bytes32 indexed tokenPair, uint256 indexed newPathIndex, uint256 indexed newPathLength, bytes32[] newPath
    );

    error Duplicate();
    error EmptyArray();
    error FailedCall(bytes);

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function _decodePath(bytes32 path)
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
     * @param  pool           address        Liquidity pool address.
     * @param  poolInterface  IStandardPool  Liquidity pool interface.
     */
    function addPool(address pool, IStandardPool poolInterface) external onlyOwner {
        if (address(poolInterfaces[pool]) != address(0)) revert Duplicate();

        // Store the new pool, along with the number of tokens in it.
        poolInterfaces[pool] = poolInterface;

        // Cache the pool index to save gas and allow `nextPoolIndex` to be incremented.
        uint256 poolIndex = nextPoolIndex;

        // Map index to pool address.
        poolIndexes[poolIndex] = pool;

        address[] memory tokens = IStandardPool(poolInterface).tokens(pool);
        uint256 tokensLength = tokens.length;
        address[] storage _poolTokens = poolTokens[pool];

        unchecked {
            // Extremely unlikely to ever overflow.
            ++nextPoolIndex;

            address token;

            for (uint256 i = 0; i < tokensLength; ++i) {
                token = tokens[i];

                _poolTokens.push(token);

                // Set the bit equal to the pool index for each token in the pool.
                _tokenPools[token].set(poolIndex);
            }
        }

        emit AddPool(pool, poolInterface, poolIndex);
    }

    function addExchangePath(bytes32 tokenPair, bytes32[] calldata newPath) external onlyOwner {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        uint256 newPathLength = newPath.length;
        uint256 newPathIndex = exchangePaths.nextIndex;

        ++exchangePaths.nextIndex;

        for (uint256 i = 0; i < newPathLength;) {
            exchangePaths.paths[newPathIndex].push(newPath[i]);

            unchecked {
                ++i;
            }
        }

        emit AddExchangePath(tokenPair, newPathIndex, newPathLength, newPath);
    }

    function poolsByToken(address token) external view returns (address[] memory _pools) {
        uint256 maxIterations = nextPoolIndex;

        for (uint256 i = 0; i < maxIterations;) {
            // Check whether the bit is set and append to the list of pools for the token.
            if (_tokenPools[token].get(i)) {
                _pools = _pools.append(poolIndexes[i]);
            }

            unchecked {
                ++i;
            }
        }
    }

    function exchangePath(bytes32 tokenPair, uint256 index)
        external
        view
        returns (address[] memory paths, uint48[] memory inputTokenIndexes, uint48[] memory outputTokenIndexes)
    {
        bytes32[] memory path = _exchangePaths[tokenPair].paths[index].getKeys();
        uint256 pathLength = path.length;
        paths = new address[](pathLength);
        inputTokenIndexes = new uint48[](pathLength);
        outputTokenIndexes = new uint48[](pathLength);

        for (uint256 i = 0; i < pathLength;) {
            (paths[i], inputTokenIndexes[i], outputTokenIndexes[i]) = _decodePath(path[i]);

            unchecked {
                ++i;
            }
        }
    }

    function nextExchangePathIndex(bytes32 tokenPair) external view returns (uint256) {
        return _exchangePaths[tokenPair].nextIndex;
    }

    function quoteTokenOutput(bytes32 tokenPair, uint256 inputTokenAmount)
        external
        view
        returns (uint256[] memory outputTokenAmounts)
    {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        outputTokenAmounts = new uint256[](exchangePaths.nextIndex);
        uint256 exchangePathsLength = exchangePaths.nextIndex;

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
                // For paths with 2+ pools, we need to store and pipe the outputs into each subsequent quote.
                // Initialized with `inputTokenAmount` since it's the very first input amount in the quote chain.
                uint256 transientQuote = inputTokenAmount;

                bytes32[] memory pathKeys = exchangePaths.paths[i].getKeys();
                uint256 pathKeysLength = pathKeys.length;

                for (uint256 j = 0; j < pathKeysLength; ++j) {
                    (address pool, uint48 inputTokenIndex, uint48 outputTokenIndex) = _decodePath(pathKeys[j]);

                    transientQuote =
                        poolInterfaces[pool].quoteTokenOutput(pool, inputTokenIndex, outputTokenIndex, transientQuote);
                }

                // Store the final quote for this path before it is reinitialized for the next path.
                outputTokenAmounts[i] = transientQuote;
            }
        }
    }

    function quoteTokenInput(bytes32 tokenPair, uint256 outputTokenAmount)
        external
        view
        returns (uint256[] memory inputTokenAmounts)
    {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        inputTokenAmounts = new uint256[](exchangePaths.nextIndex);
        uint256 exchangePathsLength = exchangePaths.nextIndex;

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
                // For paths with 2+ pools, we need to store and pipe the outputs into each subsequent quote.
                // Initialized with `inputTokenAmount` since it's the very first input amount in the quote chain.
                uint256 transientQuote = outputTokenAmount;

                bytes32[] memory pathKeys = exchangePaths.paths[i].getKeys();
                uint256 pathKeysLength = pathKeys.length;

                // Since we are fetching the input amount based on the output, we need to start from the last path element.
                while (true) {
                    --pathKeysLength;

                    (address pool, uint48 inputTokenIndex, uint48 outputTokenIndex) =
                        _decodePath(pathKeys[pathKeysLength]);

                    transientQuote =
                        poolInterfaces[pool].quoteTokenInput(pool, inputTokenIndex, outputTokenIndex, transientQuote);

                    if (pathKeysLength == 0) break;
                }

                // Store the final quote for this path before it is reinitialized for the next path.
                inputTokenAmounts[i] = transientQuote;
            }
        }
    }
}
