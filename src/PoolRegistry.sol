// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {LinkedList} from "src/lib/LinkedList.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";

contract PoolRegistry is Ownable {
    using LinkedList for LinkedList.List;
    using SafeTransferLib for address;

    struct ExchangePaths {
        uint256 nextIndex;
        mapping(uint256 index => LinkedList.List path) paths;
    }

    // Byte offsets for decoding paths (packed ABI encoding).
    uint256 private constant _PATH_POOL_OFFSET = 20;
    uint256 private constant _PATH_INPUT_TOKEN_OFFSET = 26;
    uint256 private constant _PATH_OUTPUT_TOKEN_OFFSET = 32;

    mapping(address pool => IStandardPool poolInterface) public poolInterfaces;
    mapping(address pool => mapping(uint256 index => address token) tokens)
        public poolTokens;
    mapping(bytes32 tokenPair => ExchangePaths paths) private _exchangePaths;

    event AddPool(address indexed pool, address[] tokens);
    event AddExchangePath(
        bytes32 indexed tokenPair,
        uint256 indexed newPathIndex
    );

    error Duplicate();
    error InsufficientOutput();

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
            pool := mload(add(_path, _PATH_POOL_OFFSET))
            inputTokenIndex := mload(add(_path, _PATH_INPUT_TOKEN_OFFSET))
            outputTokenIndex := mload(add(_path, _PATH_OUTPUT_TOKEN_OFFSET))
        }
    }

    function getExchangePath(
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

    function getOutputAmounts(
        bytes32 tokenPair,
        uint256 inputTokenAmount
    ) public view returns (uint256[] memory outputTokenAmounts) {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        uint256 exchangePathsLength = exchangePaths.nextIndex;
        outputTokenAmounts = new uint256[](exchangePathsLength);

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
                // For paths with 2+ pools, we need to store and pipe the outputs into each subsequent quote.
                // Initialized with `inputTokenAmount` since it's the very first input amount in the quote chain.
                uint256 transientQuote = inputTokenAmount;

                bytes32[] memory pathKeys = exchangePaths.paths[i].getKeys();
                uint256 pathKeysLength = pathKeys.length;

                for (uint256 j = 0; j < pathKeysLength; ++j) {
                    (
                        address pool,
                        uint48 inputTokenIndex,
                        uint48 outputTokenIndex
                    ) = _decodePath(pathKeys[j]);

                    transientQuote = poolInterfaces[pool].quoteTokenOutput(
                        pool,
                        inputTokenIndex,
                        outputTokenIndex,
                        transientQuote
                    );
                }

                // Store the final quote for this path before it is reinitialized for the next path.
                outputTokenAmounts[i] = transientQuote;
            }
        }
    }

    function getInputAmounts(
        bytes32 tokenPair,
        uint256 outputTokenAmount
    ) public view returns (uint256[] memory inputTokenAmounts) {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        uint256 exchangePathsLength = exchangePaths.nextIndex;
        inputTokenAmounts = new uint256[](exchangePathsLength);

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

                    (
                        address pool,
                        uint48 inputTokenIndex,
                        uint48 outputTokenIndex
                    ) = _decodePath(pathKeys[pathKeysLength]);

                    transientQuote = poolInterfaces[pool].quoteTokenInput(
                        pool,
                        inputTokenIndex,
                        outputTokenIndex,
                        transientQuote
                    );

                    if (pathKeysLength == 0) break;
                }

                // Store the final quote for this path before it is reinitialized for the next path.
                inputTokenAmounts[i] = transientQuote;
            }
        }
    }

    function getBestOutputAmount(
        bytes32 tokenPair,
        uint256 inputTokenAmount
    ) external view returns (uint256 pathIndex, uint256 outputAmount) {
        uint256[] memory outputAmounts = getOutputAmounts(
            tokenPair,
            inputTokenAmount
        );
        uint256 oLen = outputAmounts.length;

        for (uint256 i = 0; i < oLen; ) {
            if (outputAmounts[i] > outputAmount) {
                pathIndex = i;
                outputAmount = outputAmounts[i];
            }

            unchecked {
                ++i;
            }
        }
    }

    function getBestInputAmount(
        bytes32 tokenPair,
        uint256 outputTokenAmount
    ) external view returns (uint256 pathIndex, uint256 inputAmount) {
        uint256[] memory inputAmounts = getInputAmounts(
            tokenPair,
            outputTokenAmount
        );
        uint256 iLen = inputAmounts.length;

        // We need a non-zero starting value for `inputAmount` since the best input amount is the lowest.
        inputAmount = inputAmounts[0];

        for (uint256 i = 1; i < iLen; ) {
            if (inputAmounts[i] < inputAmount) {
                pathIndex = i;
                inputAmount = inputAmounts[i];
            }

            unchecked {
                ++i;
            }
        }
    }

    function swap(
        address inputToken,
        address outputToken,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount,
        uint256 pathIndex
    ) external returns (uint256 outputTokenAmount) {
        inputToken.safeTransferFrom(
            msg.sender,
            address(this),
            inputTokenAmount
        );

        bytes32[] memory pathKeys = _exchangePaths[
            keccak256(abi.encodePacked(inputToken, outputToken))
        ].paths[pathIndex].getKeys();
        uint256 pathKeysLength = pathKeys.length;
        outputTokenAmount = inputTokenAmount;

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < pathKeysLength; ++i) {
                (
                    address pool,
                    uint256 inputTokenIndex,
                    uint256 outputTokenIndex
                ) = _decodePath(pathKeys[i]);
                IStandardPool poolInterface = poolInterfaces[pool];

                // Transfer token to pool contract so that it can handle swapping.
                // Save 1 SLOAD by using `inputToken` on the first iteration.
                (i == 0 ? inputToken : poolTokens[pool][inputTokenIndex])
                    .safeTransfer(address(poolInterface), outputTokenAmount);

                outputTokenAmount = poolInterface.swap(
                    pool,
                    inputTokenIndex,
                    outputTokenIndex,
                    outputTokenAmount
                );
            }
        }

        if (outputTokenAmount < minOutputTokenAmount)
            revert InsufficientOutput();

        outputToken.safeTransfer(msg.sender, outputTokenAmount);
    }

    /**
     * @notice Add a liquidity pool.
     * @param  pool           address        Liquidity pool address.
     * @param  poolInterface  IStandardPool  Liquidity pool interface.
     */
    function addPool(
        address pool,
        IStandardPool poolInterface
    ) public onlyOwner {
        // Should not allow redundant pools from being added.
        if (address(poolInterfaces[pool]) != address(0)) revert Duplicate();

        // Store the new pool, along with the number of tokens in it.
        poolInterfaces[pool] = poolInterface;

        address[] memory tokens = poolInterface.tokens(pool);
        uint256 tokensLength = tokens.length;

        unchecked {
            for (uint256 i = 0; i < tokensLength; ++i) {
                poolTokens[pool][i] = tokens[i];
            }
        }

        emit AddPool(pool, tokens);
    }

    function addExchangePath(
        bytes32 tokenPair,
        bytes32[] calldata newPath
    ) public onlyOwner {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        uint256 newPathLength = newPath.length;
        uint256 newPathIndex = exchangePaths.nextIndex;
        LinkedList.List storage exchangePathsList = exchangePaths.paths[
            newPathIndex
        ];

        unchecked {
            ++exchangePaths.nextIndex;

            for (uint256 i = 0; i < newPathLength; ++i) {
                exchangePathsList.push(newPath[i]);
            }
        }

        emit AddExchangePath(tokenPair, newPathIndex);
    }

    function addPools(
        address[] calldata pools,
        IStandardPool[] calldata interfaces
    ) external onlyOwner {
        uint256 poolsLength = pools.length;

        for (uint256 i = 0; i < poolsLength; ) {
            addPool(pools[i], interfaces[i]);

            unchecked {
                ++i;
            }
        }
    }

    function addExchangePaths(
        bytes32[] calldata tokenPairs,
        bytes32[][] calldata newPaths
    ) external onlyOwner {
        uint256 tokenPairsLength = tokenPairs.length;

        for (uint256 i = 0; i < tokenPairsLength; ) {
            addExchangePath(tokenPairs[i], newPaths[i]);

            unchecked {
                ++i;
            }
        }
    }
}
