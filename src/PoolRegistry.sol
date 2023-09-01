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

    function getOutputAmount(
        bytes32 tokenPair,
        uint256 inputTokenAmount
    ) public view returns (uint256 bestOutputIndex, uint256 bestOutputAmount) {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        uint256 exchangePathsLength = exchangePaths.nextIndex;

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
                // For paths with 2+ pools, we need to store and pipe the outputs into each subsequent quote.
                // Initialized with `inputTokenAmount` since it's the very first input amount in the quote chain.
                uint256 transientQuote = inputTokenAmount;

                LinkedList.List storage list = exchangePaths.paths[i];
                bytes32 listKey = list.head;

                while (listKey != bytes32(0)) {
                    (
                        address pool,
                        uint48 inputTokenIndex,
                        uint48 outputTokenIndex
                    ) = _decodePath(listKey);

                    transientQuote = poolInterfaces[pool].quoteTokenOutput(
                        pool,
                        inputTokenIndex,
                        outputTokenIndex,
                        transientQuote
                    );

                    listKey = list.elements[listKey].previousKey;
                }

                // Compare the latest output amount against the current best output amount.
                if (transientQuote > bestOutputAmount) {
                    bestOutputIndex = i;
                    bestOutputAmount = transientQuote;
                }
            }
        }
    }

    function getInputAmount(
        bytes32 tokenPair,
        uint256 outputTokenAmount
    ) public view returns (uint256 bestInputIndex, uint256 bestInputAmount) {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        uint256 exchangePathsLength = exchangePaths.nextIndex;

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
                // For paths with 2+ pools, we need to store and pipe the outputs into each subsequent quote.
                // Initialized with `inputTokenAmount` since it's the very first input amount in the quote chain.
                uint256 transientQuote = outputTokenAmount;

                LinkedList.List storage list = exchangePaths.paths[i];
                bytes32 listKey = list.tail;

                while (listKey != bytes32(0)) {
                    (
                        address pool,
                        uint48 inputTokenIndex,
                        uint48 outputTokenIndex
                    ) = _decodePath(listKey);

                    transientQuote = poolInterfaces[pool].quoteTokenInput(
                        pool,
                        inputTokenIndex,
                        outputTokenIndex,
                        transientQuote
                    );

                    listKey = list.elements[listKey].nextKey;
                }

                // Compare the latest input amount against the current best input amount.
                // If the best input amount is unset, set it.
                if (transientQuote < bestInputAmount || bestInputAmount == 0) {
                    bestInputIndex = i;
                    bestInputAmount = transientQuote;
                }
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
