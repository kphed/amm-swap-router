// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";

contract PoolRegistry is Ownable {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    uint256 private constant _FEE_ADDED = 10_001;
    uint256 private constant _FEE_DEDUCTED = 9_999;
    uint256 private constant _FEE_BASE = 10_000;

    mapping(address pool => bool isSet) public pools;
    mapping(bytes32 tokenPair => address[][] path) public exchangePaths;

    event AddExchangePath(bytes32 indexed tokenPair);

    error InsufficientOutput();
    error UnauthorizedCaller();
    error FailedSwap(bytes);
    error RemovalIndexOOB();

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function withdrawERC20(address token, uint256 amount) external onlyOwner {
        token.safeTransfer(msg.sender, amount);
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

            bestOutputAmount = bestOutputAmount.mulDiv(
                _FEE_DEDUCTED,
                _FEE_BASE
            );
        }
    }

    function getInputAmount(
        bytes32 tokenPair,
        uint256 swapAmount
    ) external view returns (uint256 bestInputIndex, uint256 bestInputAmount) {
        address[][] memory _exchangePaths = exchangePaths[tokenPair];
        uint256 exchangePathsLength = _exchangePaths.length;
        swapAmount = swapAmount.mulDiv(_FEE_ADDED, _FEE_BASE);

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

                if (!success) revert FailedSwap(data);

                inputTokenAmount = abi.decode(data, (uint256));
            }

            if (inputTokenAmount < minOutputTokenAmount)
                revert InsufficientOutput();

            inputTokenAmount = inputTokenAmount.mulDiv(
                _FEE_DEDUCTED,
                _FEE_BASE
            );
        }

        outputToken.safeTransfer(msg.sender, inputTokenAmount);

        return inputTokenAmount;
    }

    function addExchangePath(
        bytes32 tokenPair,
        address[] calldata interfaces
    ) external onlyOwner {
        address[][] storage _exchangePaths = exchangePaths[tokenPair];
        uint256 exchangePathsLength = _exchangePaths.length;

        _exchangePaths.push();

        address[] storage paths = _exchangePaths[exchangePathsLength];
        uint256 interfacesLength = interfaces.length;

        unchecked {
            for (uint256 i = 0; i < interfacesLength; ++i) {
                address poolInterface = interfaces[i];
                address[] memory tokens = IStandardPool(poolInterface).tokens();
                address pool = IStandardPool(poolInterface).pool();
                pools[pool] = true;

                for (uint256 j = 0; j < tokens.length; ++j) {
                    tokens[j].safeApproveWithRetry(pool, type(uint256).max);
                }

                paths.push(poolInterface);
            }
        }

        emit AddExchangePath(tokenPair);
    }

    function removeExchangePath(
        bytes32 tokenPair,
        uint256 removalIndex
    ) external onlyOwner {
        address[][] storage _exchangePaths = exchangePaths[tokenPair];
        uint256 lastIndex = _exchangePaths.length - 1;

        // Throw if the removal index is for an element that doesn't exist.
        if (removalIndex > lastIndex) revert RemovalIndexOOB();

        if (removalIndex != lastIndex) {
            // Set the last element to the removal index (the original will be removed).
            _exchangePaths[removalIndex] = _exchangePaths[lastIndex];
        }

        _exchangePaths.pop();
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        if (!pools[msg.sender]) revert UnauthorizedCaller();

        address inputToken = abi.decode(data, (address));

        if (amount0Delta > 0) {
            inputToken.safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            inputToken.safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }
}
