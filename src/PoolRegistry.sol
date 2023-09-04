// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Solarray} from "solarray/Solarray.sol";
import {LinkedList} from "src/lib/LinkedList.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";

contract PoolRegistry is Ownable {
    using LinkedList for LinkedList.List;
    using SafeTransferLib for address;
    using Solarray for address[];
    using Solarray for uint256[];

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
    error PoolTokenNotSet();
    error PoolTokensIdentical();

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

    function getExchangePaths(
        bytes32 tokenPair
    )
        external
        view
        returns (
            uint256 nextIndex,
            address[][] memory pools,
            uint256[][] memory inputTokenIndexes,
            uint256[][] memory outputTokenIndexes
        )
    {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        nextIndex = exchangePaths.nextIndex;
        pools = new address[][](nextIndex);
        inputTokenIndexes = new uint256[][](nextIndex);
        outputTokenIndexes = new uint256[][](nextIndex);

        for (uint256 i = 0; i < nextIndex; ++i) {
            LinkedList.List storage list = exchangePaths.paths[i];
            bytes32 listKey = list.head;

            while (listKey != bytes32(0)) {
                (
                    address pool,
                    uint256 inputTokenIndex,
                    uint256 outputTokenIndex
                ) = _decodePath(listKey);
                pools[i] = pools[i].append(pool);
                inputTokenIndexes[i] = inputTokenIndexes[i].append(inputTokenIndex);
                outputTokenIndexes[i] = outputTokenIndexes[i].append(outputTokenIndex);
                listKey = list.elements[listKey].nextKey;
            }
        }
    }

    function getOutputAmount(
        bytes32 tokenPair,
        uint256 inputTokenAmount
    )
        external
        view
        returns (uint256 bestOutputIndex, uint256 bestOutputAmount)
    {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        uint256 exchangePathsLength = exchangePaths.nextIndex;

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
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
                    listKey = list.elements[listKey].nextKey;
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
    ) external view returns (uint256 bestInputIndex, uint256 bestInputAmount) {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        uint256 exchangePathsLength = exchangePaths.nextIndex;

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
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
                    listKey = list.elements[listKey].previousKey;
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

        LinkedList.List storage list = _exchangePaths[
            keccak256(abi.encodePacked(inputToken, outputToken))
        ].paths[pathIndex];
        bytes32 listKey = list.head;
        outputTokenAmount = inputTokenAmount;

        while (listKey != bytes32(0)) {
            (
                address pool,
                uint256 inputTokenIndex,
                uint256 outputTokenIndex
            ) = _decodePath(listKey);
            IStandardPool poolInterface = poolInterfaces[pool];

            poolTokens[pool][inputTokenIndex].safeTransfer(
                address(poolInterface),
                outputTokenAmount
            );

            outputTokenAmount = poolInterface.swap(
                pool,
                inputTokenIndex,
                outputTokenIndex,
                outputTokenAmount
            );
            listKey = list.elements[listKey].nextKey;
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
            bytes32 newPathItem;

            for (uint256 i = 0; i < newPathLength; ++i) {
                newPathItem = newPath[i];

                (
                    address pool,
                    uint48 inputTokenIndex,
                    uint48 outputTokenIndex
                ) = _decodePath(newPathItem);

                // Throws if the token indexes are invalid (e.g. pool not set, or token index invalid).
                if (poolTokens[pool][inputTokenIndex] == address(0))
                    revert PoolTokenNotSet();
                if (poolTokens[pool][outputTokenIndex] == address(0))
                    revert PoolTokenNotSet();

                // Unless we're arbing (we're not), there should be no reason to swap the same tokens.
                if (inputTokenIndex == outputTokenIndex)
                    revert PoolTokensIdentical();

                exchangePathsList.push(newPathItem);
            }
        }

        emit AddExchangePath(tokenPair, newPathIndex);
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
