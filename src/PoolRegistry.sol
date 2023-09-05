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

    function _decodePath(bytes32 path) private pure returns (address pool) {
        return address(uint160(uint256(path)));
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
        uint256 amount = swapAmount;

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
                LinkedList.List storage list = exchangePaths.paths[i];
                bytes32 listKey = list.head;

                while (listKey != bytes32(0)) {
                    address pool = _decodePath(listKey);
                    amount = IStandardPool(pool).quoteTokenOutput(amount);

                    if (listKey == list.tail) {
                        // Compare the latest output amount against the current best output amount.
                        if (amount > bestOutputAmount) {
                            bestOutputIndex = i;
                            bestOutputAmount = amount;
                        }

                        amount = swapAmount;

                        break;
                    }

                    listKey = list.elements[listKey].nextKey;
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
        uint256 amount = swapAmount;

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
                LinkedList.List storage list = exchangePaths.paths[i];
                bytes32 listKey = list.tail;

                while (listKey != bytes32(0)) {
                    address pool = _decodePath(listKey);
                    amount = IStandardPool(pool).quoteTokenInput(amount);

                    if (listKey == list.head) {
                        // Compare the latest input amount against the current best input amount.
                        // If the best input amount is unset, set it.
                        if (amount < bestInputAmount || bestInputAmount == 0) {
                            bestInputIndex = i;
                            bestInputAmount = amount;
                        }

                        amount = swapAmount;

                        break;
                    }

                    listKey = list.elements[listKey].previousKey;
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
            address pool = _decodePath(listKey);
            (bool success, bytes memory data) = pool.delegatecall(
                abi.encodeWithSelector(IStandardPool.swap.selector, swapAmount)
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

    function addExchangePath(
        bytes32 tokenPair,
        address[] calldata interfaces
    ) public onlyOwner {
        ExchangePaths storage exchangePaths = _exchangePaths[tokenPair];
        LinkedList.List storage exchangePathsList = exchangePaths.paths[
            exchangePaths.nextIndex
        ];
        uint256 interfacesLength = interfaces.length;

        unchecked {
            ++exchangePaths.nextIndex;

            for (uint256 i = 0; i < interfacesLength; ++i) {
                address poolInterface = interfaces[i];
                address[] memory tokens = IStandardPool(poolInterface).tokens();
                address pool = IStandardPool(poolInterface).pool();

                for (uint256 j = 0; j < tokens.length; ++j) {
                    tokens[j].safeApproveWithRetry(pool, type(uint256).max);
                }

                exchangePathsList.push(
                    bytes32(uint256(uint160(poolInterface)))
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
        address inputToken = abi.decode(data, (address));

        if (amount0Delta > 0) {
            inputToken.safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            inputToken.safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }
}
