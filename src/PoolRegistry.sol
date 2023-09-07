// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";

contract PoolRegistry is Ownable {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    uint256 private constant _FEE_DEDUCTED = 9_999;
    uint256 private constant _FEE_BASE = 10_000;

    mapping(address pool => uint256 tokenCount) public pools;
    mapping(bytes32 tokenPair => address[][] path) public exchangePaths;

    event WithdrawERC20(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );
    event AddExchangePath(bytes32 indexed tokenPair, uint256 indexed addIndex);
    event RemoveExchangePath(
        bytes32 indexed tokenPair,
        uint256 indexed removeIndex
    );
    event ApprovePool(
        IStandardPool indexed poolInterface,
        address indexed pool,
        address[] tokens
    );

    error InsufficientOutput();
    error UnauthorizedCaller();
    error FailedSwap();
    error RemoveIndexOOB();
    error PoolDoesNotExist();
    error InvalidTokenPair();
    error EmptyArray();

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function withdrawERC20(
        address token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        token.safeTransfer(recipient, amount);

        emit WithdrawERC20(token, recipient, amount);
    }

    function addExchangePath(
        bytes32 tokenPair,
        address[] calldata interfaces
    ) external onlyOwner {
        if (tokenPair == bytes32(0)) revert InvalidTokenPair();

        uint256 interfacesLength = interfaces.length;

        if (interfacesLength == 0) revert EmptyArray();

        address[][] storage _exchangePaths = exchangePaths[tokenPair];
        uint256 addIndex = _exchangePaths.length;

        _exchangePaths.push();

        address[] storage paths = _exchangePaths[addIndex];

        unchecked {
            for (uint256 i = 0; i < interfacesLength; ++i) {
                address poolInterface = interfaces[i];
                address[] memory tokens = IStandardPool(poolInterface).tokens();
                address pool = IStandardPool(poolInterface).pool();
                uint256 tokensLength = tokens.length;
                pools[pool] = tokensLength;

                for (uint256 j = 0; j < tokensLength; ++j) {
                    tokens[j].safeApproveWithRetry(pool, type(uint256).max);
                }

                paths.push(poolInterface);
            }
        }

        emit AddExchangePath(tokenPair, addIndex);
    }

    function removeExchangePath(
        bytes32 tokenPair,
        uint256 removeIndex
    ) external onlyOwner {
        if (tokenPair == bytes32(0)) revert InvalidTokenPair();

        address[][] storage _exchangePaths = exchangePaths[tokenPair];
        uint256 lastIndex = _exchangePaths.length - 1;

        // Throw if the removal index is for an element that doesn't exist.
        if (removeIndex > lastIndex) revert RemoveIndexOOB();

        if (removeIndex != lastIndex) {
            // Set the last element to the removal index (the original will be removed).
            _exchangePaths[removeIndex] = _exchangePaths[lastIndex];
        }

        _exchangePaths.pop();

        emit RemoveExchangePath(tokenPair, removeIndex);
    }

    function approvePool(IStandardPool poolInterface) external {
        address[] memory tokens = poolInterface.tokens();
        address pool = poolInterface.pool();

        if (pools[pool] == 0) revert PoolDoesNotExist();

        uint256 tokensLength = tokens.length;

        for (uint256 i = 0; i < tokensLength; ) {
            tokens[i].safeApproveWithRetry(pool, type(uint256).max);

            unchecked {
                ++i;
            }
        }

        emit ApprovePool(poolInterface, pool, tokens);
    }

    function swap(
        address inputToken,
        address outputToken,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount,
        uint256 pathIndex
    ) external returns (uint256) {
        inputToken.safeTransferFrom(
            msg.sender,
            address(this),
            inputTokenAmount
        );

        address[] memory paths = exchangePaths[
            keccak256(abi.encodePacked(inputToken, outputToken))
        ][pathIndex];
        uint256 pathsLength = paths.length;

        unchecked {
            for (uint256 i = 0; i < pathsLength; ++i) {
                (bool success, bytes memory data) = paths[i].delegatecall(
                    abi.encodeWithSelector(
                        IStandardPool.swap.selector,
                        inputTokenAmount
                    )
                );

                if (!success) revert FailedSwap();

                inputTokenAmount = abi.decode(data, (uint256));
            }

            inputTokenAmount = inputTokenAmount.mulDiv(
                _FEE_DEDUCTED,
                _FEE_BASE
            );

            if (inputTokenAmount < minOutputTokenAmount)
                revert InsufficientOutput();
        }

        outputToken.safeTransfer(msg.sender, inputTokenAmount);

        return inputTokenAmount;
    }

    function getExchangePaths(
        bytes32 tokenPair
    ) external view returns (address[][] memory) {
        return exchangePaths[tokenPair];
    }

    function getOutputAmount(
        bytes32 tokenPair,
        uint256 swapAmount
    )
        external
        view
        returns (uint256 bestOutputIndex, uint256 bestOutputAmount)
    {
        address[][] memory _exchangePaths = exchangePaths[tokenPair];
        uint256 exchangePathsLength = _exchangePaths.length;

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
                address[] memory paths = _exchangePaths[i];
                uint256 pathsLength = paths.length;
                uint256 amount = swapAmount;

                for (uint256 j = 0; j < pathsLength; ++j) {
                    amount = IStandardPool(paths[j]).quoteTokenOutput(amount);
                }

                if (amount > bestOutputAmount) {
                    bestOutputIndex = i;
                    bestOutputAmount = amount;
                }
            }
        }

        bestOutputAmount = bestOutputAmount.mulDiv(_FEE_DEDUCTED, _FEE_BASE);
    }

    function getInputAmount(
        bytes32 tokenPair,
        uint256 swapAmount
    ) external view returns (uint256 bestInputIndex, uint256 bestInputAmount) {
        address[][] memory _exchangePaths = exchangePaths[tokenPair];
        uint256 exchangePathsLength = _exchangePaths.length;
        swapAmount = swapAmount.mulDiv(_FEE_BASE, _FEE_DEDUCTED);

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
                address[] memory paths = _exchangePaths[i];
                uint256 pathsLength = paths.length;
                uint256 amount = swapAmount;

                while (pathsLength != 0) {
                    --pathsLength;

                    amount = IStandardPool(paths[pathsLength]).quoteTokenInput(
                        amount
                    );
                }

                if (amount < bestInputAmount || bestInputAmount == 0) {
                    bestInputIndex = i;
                    bestInputAmount = amount;
                }
            }
        }
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        if (pools[msg.sender] == 0) revert UnauthorizedCaller();

        address inputToken = abi.decode(data, (address));

        if (amount0Delta > 0) {
            inputToken.safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            inputToken.safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }
}
