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

    // Each swap incurs a 1 bps (0.01%) fee.
    uint256 private constant _FEE_DEDUCTED = 9_999;
    uint256 private constant _FEE_BASE = 10_000;

    // Swap routes for a given token pair - each route is comprised of 1 or more paths.
    mapping(bytes32 pair => IPath[][] path) private _routes;

    event WithdrawERC20(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );
    event AddRoute(bytes32 indexed pair, IPath[] newRoute);
    event RemoveRoute(bytes32 indexed pair, uint256 indexed index);
    event ApprovePath(IPath indexed path, address[] tokens);

    error InsufficientOutput();
    error RemoveIndexOOB();
    error InvalidPair();
    error EmptyArray();

    /**
     * @param initialOwner  address  The initial owner of the contract.
     */
    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    /**
     * @notice Withdraw an ERC20 token from the contract.
     * @param  token      address  Token to withdraw.
     * @param  recipient  address  Recipient of the tokens.
     * @param  amount     uint256  Token amount.
     */
    function withdrawERC20(
        address token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        emit WithdrawERC20(token, recipient, amount);

        token.safeTransfer(recipient, amount);
    }

    /**
     * @notice Add a route.
     * @param  pair      bytes32  Token pair.
     * @param  newRoute  IPath[]  New swap route.
     */
    function addRoute(
        bytes32 pair,
        IPath[] calldata newRoute
    ) external onlyOwner {
        if (pair == bytes32(0)) revert InvalidPair();

        uint256 newRouteLength = newRoute.length;

        if (newRouteLength == 0) revert EmptyArray();

        IPath[][] storage routes = _routes[pair];
        IPath[] storage route = routes.push();

        emit AddRoute(pair, newRoute);

        unchecked {
            for (uint256 i = 0; i < newRouteLength; ++i) {
                IPath path = newRoute[i];
                address[] memory tokens = path.tokens();
                uint256 tokensLength = tokens.length;

                route.push(path);

                for (uint256 j = 0; j < tokensLength; ++j) {
                    tokens[j].safeApproveWithRetry(
                        address(path),
                        type(uint256).max
                    );
                }
            }
        }
    }

    function removeRoute(bytes32 pair, uint256 index) external onlyOwner {
        if (pair == bytes32(0)) revert InvalidPair();

        IPath[][] storage routes = _routes[pair];
        uint256 lastIndex = routes.length - 1;

        // Throw if the removal index is for an element that doesn't exist.
        if (index > lastIndex) revert RemoveIndexOOB();

        if (index != lastIndex) {
            // Set the last element to the removal index (the original will be removed).
            routes[index] = routes[lastIndex];
        }

        routes.pop();

        emit RemoveRoute(pair, index);
    }

    function approvePath(
        bytes32 pair,
        uint256 routeIndex,
        uint256 pathIndex
    ) external onlyOwner {
        IPath path = _routes[pair][routeIndex][pathIndex];
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
        uint256 routeIndex
    ) external nonReentrant returns (uint256 output) {
        inputToken.safeTransferFrom(msg.sender, address(this), input);

        IPath[] memory route = _routes[
            keccak256(abi.encodePacked(inputToken, outputToken))
        ][routeIndex];
        uint256 routeLength = route.length;
        output = outputToken.balanceOf(address(this));

        for (uint256 i = 0; i < routeLength; ) {
            input = route[i].swap(input);

            unchecked {
                ++i;
            }
        }

        // Prevent any chance of a malicious path rugging by evaluating the output token balance diff.
        output = outputToken.balanceOf(address(this)) - output;

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
        IPath[][] memory routes = _routes[pair];
        uint256 routesLength = routes.length;

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < routesLength; ++i) {
                IPath[] memory route = routes[i];
                uint256 routeLength = route.length;
                uint256 _input = input;

                for (uint256 j = 0; j < routeLength; ++j) {
                    _input = route[j].quoteTokenOutput(_input);
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
        IPath[][] memory routes = _routes[pair];
        uint256 routesLength = routes.length;
        output = output.mulDivUp(_FEE_BASE, _FEE_DEDUCTED);

        // Loop iterator variables are bound by exchange path list lengths and will not overflow.
        unchecked {
            for (uint256 i = 0; i < routesLength; ++i) {
                IPath[] memory route = routes[i];
                uint256 routeLength = route.length;
                uint256 _output = output;

                while (routeLength != 0) {
                    --routeLength;

                    _output = route[routeLength].quoteTokenInput(_output);
                }

                if (_output < input || input == 0) {
                    index = i;
                    input = _output;
                }
            }
        }
    }

    function getRoutes(bytes32 pair) external view returns (IPath[][] memory) {
        return _routes[pair];
    }
}
