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
    event AddExchangePath(bytes32 indexed tokenPair);

    error Duplicate();
    error InsufficientOutput();
    error PoolTokenNotSet();
    error PoolTokensIdentical();
    error UnauthorizedCaller();
    error FailedSwap(bytes);

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function _encodePath(
        address pool,
        uint48 inputTokenIndex,
        uint48 outputTokenIndex
    ) private pure returns (bytes32) {
        return
            bytes32(abi.encodePacked(pool, inputTokenIndex, outputTokenIndex));
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
            uint256[2][] memory tokenIndexes
        )
    {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        nextIndex = exchangePaths.nextIndex;
        pools = new address[][](nextIndex);
        tokenIndexes = new uint256[2][](nextIndex);

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
                tokenIndexes[i][0] = inputTokenIndex;
                tokenIndexes[i][1] = outputTokenIndex;
                listKey = list.elements[listKey].nextKey;
            }
        }
    }

    function getOutputAmount(
        bytes32 tokenPair,
        uint256 swapAmount
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
                LinkedList.List storage list = exchangePaths.paths[i];
                bytes32 listKey = list.head;

                while (listKey != bytes32(0)) {
                    (
                        address pool,
                        uint48 inputTokenIndex,
                        uint48 outputTokenIndex
                    ) = _decodePath(listKey);
                    swapAmount = poolInterfaces[pool].quoteTokenOutput(
                        pool,
                        inputTokenIndex,
                        outputTokenIndex,
                        swapAmount
                    );

                    if (listKey == list.tail) break;

                    listKey = list.elements[listKey].nextKey;
                }

                // Compare the latest output amount against the current best output amount.
                if (swapAmount > bestOutputAmount) {
                    bestOutputIndex = i;
                    bestOutputAmount = swapAmount;
                }
            }
        }
    }

    function getInputAmount(
        bytes32 tokenPair,
        uint256 swapAmount
    ) external view returns (uint256 bestInputIndex, uint256 bestInputAmount) {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        uint256 exchangePathsLength = exchangePaths.nextIndex;

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
                LinkedList.List storage list = exchangePaths.paths[i];
                bytes32 listKey = list.tail;

                while (listKey != bytes32(0)) {
                    (
                        address pool,
                        uint48 inputTokenIndex,
                        uint48 outputTokenIndex
                    ) = _decodePath(listKey);
                    swapAmount = poolInterfaces[pool].quoteTokenInput(
                        pool,
                        inputTokenIndex,
                        outputTokenIndex,
                        swapAmount
                    );

                    if (listKey == list.head) break;

                    listKey = list.elements[listKey].previousKey;
                }

                // Compare the latest input amount against the current best input amount.
                // If the best input amount is unset, set it.
                if (swapAmount < bestInputAmount || bestInputAmount == 0) {
                    bestInputIndex = i;
                    bestInputAmount = swapAmount;
                }
            }
        }
    }

    function swap(
        address inputToken,
        address outputToken,
        uint256 swapAmount,
        uint256 minOutputTokenAmount,
        uint256 pathIndex
    ) external returns (uint256) {
        inputToken.safeTransferFrom(msg.sender, address(this), swapAmount);

        LinkedList.List storage list = _exchangePaths[
            keccak256(abi.encodePacked(inputToken, outputToken))
        ].paths[pathIndex];
        bytes32 listKey = list.head;

        while (listKey != bytes32(0)) {
            (
                address pool,
                uint256 inputTokenIndex,
                uint256 outputTokenIndex
            ) = _decodePath(listKey);
            (bool success, bytes memory data) = address(poolInterfaces[pool])
                .delegatecall(
                    abi.encodeWithSelector(
                        IStandardPool.swap.selector,
                        pool,
                        inputTokenIndex,
                        outputTokenIndex,
                        swapAmount
                    )
                );

            if (!success) revert FailedSwap(data);

            swapAmount = abi.decode(data, (uint256));

            if (listKey == list.tail) break;

            listKey = list.elements[listKey].nextKey;
        }

        if (swapAmount < minOutputTokenAmount) revert InsufficientOutput();

        outputToken.safeTransfer(msg.sender, swapAmount);

        return swapAmount;
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
                // Pre-approve pools to spend tokens in order to save gas.
                tokens[i].safeApprove(pool, type(uint256).max);

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
        address[] calldata pools,
        uint48[2][] calldata tokenIndexes
    ) public onlyOwner {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        LinkedList.List storage exchangePathsList = exchangePaths.paths[
            exchangePaths.nextIndex
        ];
        uint256 poolsLength = pools.length;

        unchecked {
            ++exchangePaths.nextIndex;

            for (uint256 i = 0; i < poolsLength; ++i) {
                address pool = pools[i];
                uint48 inputTokenIndex = tokenIndexes[i][0];
                uint48 outputTokenIndex = tokenIndexes[i][1];

                // Throws if the token indexes are invalid (e.g. pool not set, or token index invalid).
                if (poolTokens[pool][inputTokenIndex] == address(0))
                    revert PoolTokenNotSet();
                if (poolTokens[pool][outputTokenIndex] == address(0))
                    revert PoolTokenNotSet();

                // Unless we're arbing (we're not), there should be no reason to swap the same tokens.
                if (inputTokenIndex == outputTokenIndex)
                    revert PoolTokensIdentical();

                exchangePathsList.push(
                    _encodePath(pool, inputTokenIndex, outputTokenIndex)
                );
            }
        }

        emit AddExchangePath(tokenPair);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        if (address(poolInterfaces[msg.sender]) == address(0))
            revert UnauthorizedCaller();

        address inputToken = abi.decode(data, (address));

        if (amount0Delta != 0) {
            inputToken.safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta != 0) {
            inputToken.safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }
}
