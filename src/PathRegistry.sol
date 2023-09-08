// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {IPath} from "src/paths/IPath.sol";
import {ReentrancyGuard} from "src/lib/ReentrancyGuard.sol";

contract PathRegistry is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    uint256 private constant _FEE_DEDUCTED = 9_990;
    uint256 private constant _FEE_BASE = 10_000;

    mapping(bytes32 pair => IPath[][] path) private _paths;

    event WithdrawERC20(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );
    event AddPath(bytes32 indexed pair, uint256 indexed index);
    event ApprovePath(IPath indexed path, address[] tokens);

    error InsufficientOutput();
    error RemoveIndexOOB();
    error PoolDoesNotExist();
    error InvalidPair();
    error EmptyArray();

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function withdrawERC20(
        address token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        emit WithdrawERC20(token, recipient, amount);

        token.safeTransfer(recipient, amount);
    }

    function addPath(
        bytes32 pair,
        IPath[] calldata interfaces
    ) external onlyOwner {
        if (pair == bytes32(0)) revert InvalidPair();

        uint256 interfacesLength = interfaces.length;

        if (interfacesLength == 0) revert EmptyArray();

        IPath[][] storage exchangePaths = _paths[pair];
        uint256 addIndex = exchangePaths.length;

        exchangePaths.push();

        IPath[] storage paths = exchangePaths[addIndex];

        emit AddPath(pair, addIndex);

        unchecked {
            for (uint256 i = 0; i < interfacesLength; ++i) {
                IPath path = interfaces[i];
                address[] memory tokens = path.tokens();
                uint256 tokensLength = tokens.length;

                for (uint256 j = 0; j < tokensLength; ++j) {
                    tokens[j].safeApproveWithRetry(
                        address(path),
                        type(uint256).max
                    );
                }

                paths.push(path);
            }
        }
    }

    function approvePath(
        bytes32 pair,
        uint256 outerPathIndex,
        uint256 innerPathIndex
    ) external onlyOwner {
        IPath path = _paths[pair][outerPathIndex][innerPathIndex];
        address[] memory tokens = path.tokens();
        uint256 tokensLength = tokens.length;

        emit ApprovePath(path, tokens);

        for (uint256 i = 0; i < tokensLength; ) {
            tokens[i].safeApproveWithRetry(address(path), type(uint256).max);

            unchecked {
                ++i;
            }
        }
    }

    function swap(
        address inputToken,
        address outputToken,
        uint256 input,
        uint256 minOutput,
        uint256 index
    ) external nonReentrant returns (uint256 output) {
        inputToken.safeTransferFrom(msg.sender, address(this), input);

        IPath[] memory paths = _paths[
            keccak256(abi.encodePacked(inputToken, outputToken))
        ][index];
        uint256 pathsLength = paths.length;
        output = input;

        for (uint256 i = 0; i < pathsLength; ) {
            output = paths[i].swap(output);

            unchecked {
                ++i;
            }
        }

        if (output < minOutput) revert InsufficientOutput();

        output = output.mulDiv(_FEE_DEDUCTED, _FEE_BASE);

        // If the post-fee amount is less than the minimum, transfer the minimum to the swapper,
        // since we know that the pre-fee amount is greater than or equal to the minimum.
        if (output < minOutput) output = minOutput;

        outputToken.safeTransfer(msg.sender, output);
    }

    function getSwapOutput(
        bytes32 pair,
        uint256 input
    ) external view returns (uint256 index, uint256 output) {
        IPath[][] memory exchangePaths = _paths[pair];
        uint256 exchangePathsLength = exchangePaths.length;

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
                IPath[] memory paths = exchangePaths[i];
                uint256 pathsLength = paths.length;
                uint256 _input = input;

                for (uint256 j = 0; j < pathsLength; ++j) {
                    _input = paths[j].quoteTokenOutput(_input);
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
        IPath[][] memory exchangePaths = _paths[pair];
        uint256 exchangePathsLength = exchangePaths.length;
        output = output.mulDivUp(_FEE_BASE, _FEE_DEDUCTED);

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < exchangePathsLength; ++i) {
                IPath[] memory paths = exchangePaths[i];
                uint256 pathsLength = paths.length;
                uint256 _output = output;

                while (pathsLength != 0) {
                    --pathsLength;

                    _output = paths[pathsLength].quoteTokenInput(_output);
                }

                if (_output < input || input == 0) {
                    index = i;
                    input = _output;
                }
            }
        }
    }

    function getPaths(bytes32 pair) external view returns (IPath[][] memory) {
        return _paths[pair];
    }
}
