// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";

contract PoolRegistry is Ownable {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    uint256 private constant _FEE_DEDUCTED = 9_990;
    uint256 private constant _FEE_BASE = 10_000;

    mapping(address pool => uint256 tokenCount) public pools;
    mapping(bytes32 pair => address[][] path) public exchangePaths;

    event WithdrawERC20(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );
    event AddExchangePath(bytes32 indexed pair, uint256 indexed index);
    event RemoveExchangePath(bytes32 indexed pair, uint256 indexed index);
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

    receive() external payable {}

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
        bytes32 pair,
        address[] calldata interfaces
    ) external onlyOwner {
        if (pair == bytes32(0)) revert InvalidTokenPair();

        uint256 interfacesLength = interfaces.length;

        if (interfacesLength == 0) revert EmptyArray();

        address[][] storage _exchangePaths = exchangePaths[pair];
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

        emit AddExchangePath(pair, addIndex);
    }

    function removeExchangePath(
        bytes32 pair,
        uint256 removeIndex
    ) external onlyOwner {
        if (pair == bytes32(0)) revert InvalidTokenPair();

        address[][] storage _exchangePaths = exchangePaths[pair];
        uint256 lastIndex = _exchangePaths.length - 1;

        // Throw if the removal index is for an element that doesn't exist.
        if (removeIndex > lastIndex) revert RemoveIndexOOB();

        if (removeIndex != lastIndex) {
            // Set the last element to the removal index (the original will be removed).
            _exchangePaths[removeIndex] = _exchangePaths[lastIndex];
        }

        _exchangePaths.pop();

        emit RemoveExchangePath(pair, removeIndex);
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
        uint256 input,
        uint256 minOutput,
        uint256 index
    ) external returns (uint256) {
        inputToken.safeTransferFrom(msg.sender, address(this), input);

        address[] memory paths = exchangePaths[
            keccak256(abi.encodePacked(inputToken, outputToken))
        ][index];
        uint256 pathsLength = paths.length;

        unchecked {
            for (uint256 i = 0; i < pathsLength; ++i) {
                (bool success, bytes memory data) = paths[i].delegatecall(
                    abi.encodeWithSelector(IStandardPool.swap.selector, input)
                );

                if (!success) revert FailedSwap();

                input = abi.decode(data, (uint256));
            }

            input = input.mulDiv(_FEE_DEDUCTED, _FEE_BASE);

            if (input < minOutput) revert InsufficientOutput();
        }

        outputToken.safeTransfer(msg.sender, input);

        return input;
    }

    function getExchangePaths(
        bytes32 pair
    ) external view returns (address[][] memory) {
        return exchangePaths[pair];
    }

    function getSwapOutput(
        bytes32 pair,
        uint256 input
    ) external view returns (uint256 index, uint256 output) {
        address[][] memory _exchangePaths = exchangePaths[pair];
        uint256 exchangePathsLength = _exchangePaths.length;

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
                address[] memory paths = _exchangePaths[i];
                uint256 pathsLength = paths.length;
                uint256 _input = input;

                for (uint256 j = 0; j < pathsLength; ++j) {
                    _input = IStandardPool(paths[j]).quoteTokenOutput(_input);
                }

                if (_input > output) {
                    index = i;
                    output = _input;
                }
            }
        }

        output = output.mulDiv(_FEE_DEDUCTED, _FEE_BASE);
    }

    function getSwapInput(
        bytes32 pair,
        uint256 output
    ) external view returns (uint256 index, uint256 input) {
        address[][] memory _exchangePaths = exchangePaths[pair];
        uint256 exchangePathsLength = _exchangePaths.length;

        console.log("output", output);

        output = output.mulDiv(_FEE_BASE, _FEE_DEDUCTED);

        console.log("output", output);

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
                address[] memory paths = _exchangePaths[i];
                uint256 pathsLength = paths.length;
                uint256 _output = output;

                while (pathsLength != 0) {
                    --pathsLength;

                    _output = IStandardPool(paths[pathsLength]).quoteTokenInput(
                            _output
                        );
                }

                if (_output < input || input == 0) {
                    index = i;
                    input = _output;
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
