// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {IPath} from "src/paths/IPath.sol";
import {ReentrancyGuard} from "src/lib/ReentrancyGuard.sol";

contract Router is Ownable, ReentrancyGuard {
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
    event ApprovePath(
        IPath indexed path,
        address indexed inputToken,
        address indexed outputToken
    );
    event Swap(
        address indexed msgSender,
        address indexed inputToken,
        address indexed outputToken,
        uint256 input,
        uint256 output,
        uint256 index
    );

    error InsufficientOutput();
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

        IPath[] storage route = _routes[pair].push();

        emit AddRoute(pair, newRoute);

        unchecked {
            for (uint256 i = 0; i < newRouteLength; ++i) {
                IPath path = newRoute[i];
                (address inputToken, address outputToken) = path.tokens();

                route.push(path);

                inputToken.safeApproveWithRetry(
                    address(path),
                    type(uint256).max
                );
                outputToken.safeApproveWithRetry(
                    address(path),
                    type(uint256).max
                );
            }
        }
    }

    /**
     * @notice Remove a route.
     * @param  pair   bytes32  Token pair.
     * @param  index  uint256  Route index.
     */
    function removeRoute(bytes32 pair, uint256 index) external onlyOwner {
        if (pair == bytes32(0)) revert InvalidPair();

        IPath[][] storage routes = _routes[pair];
        uint256 lastIndex = routes.length - 1;

        if (index != lastIndex) {
            // Set the last element to the removal index (the original will be removed).
            // Throws if the removal index is GTE to the length of the array.
            routes[index] = routes[lastIndex];
        }

        routes.pop();

        emit RemoveRoute(pair, index);
    }

    /**
     * @notice Approve a path contract to transfer our tokens.
     * @param  pair        bytes32  Token pair.
     * @param  routeIndex  uint256  Route index.
     * @param  pathIndex   uint256  Path index.
     */
    function approvePath(
        bytes32 pair,
        uint256 routeIndex,
        uint256 pathIndex
    ) external onlyOwner {
        IPath path = _routes[pair][routeIndex][pathIndex];
        (address inputToken, address outputToken) = path.tokens();

        emit ApprovePath(path, inputToken, outputToken);

        inputToken.safeApproveWithRetry(address(path), type(uint256).max);
        outputToken.safeApproveWithRetry(address(path), type(uint256).max);
    }

    /**
     * @notice Swap an input token for an output token over a series of paths.
     * @param  inputToken   address  Token to swap.
     * @param  outputToken  address  Token to receive.
     * @param  input        uint256  Amount of input token to swap.
     * @param  minOutput    uint256  Minimum amount of output token to receive.
     * @param  routeIndex   uint256  Route index.
     * @return output       uint256  Amount of output token received from the swap.
     */
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

        // Using the balance difference allows us to prevent malicious paths from stealing funds.
        output = outputToken.balanceOf(address(this)) - output;

        if (output < minOutput) revert InsufficientOutput();

        // Calculate the output amount with fees applied.
        output = output.mulDiv(_FEE_DEDUCTED, _FEE_BASE);

        // If the post-fee amount is less than the minimum, transfer the minimum to the swapper,
        // since we know that the pre-fee amount is greater than or equal to the minimum.
        if (output < minOutput) output = minOutput;

        emit Swap(
            msg.sender,
            inputToken,
            outputToken,
            input,
            output,
            routeIndex
        );

        outputToken.safeTransfer(msg.sender, output);
    }

    /**
     * @notice Get the best (highest) swap output for a given input amount.
     * @param  pair    bytes32  Token pair.
     * @param  input   uint256  Amount of input token to swap.
     * @return index   uint256  Route index with the highest output.
     * @return output  uint256  Amount of output token received from the swap.
     */
    function getSwapOutput(
        bytes32 pair,
        uint256 input
    ) external view returns (uint256 index, uint256 output) {
        IPath[][] memory routes = _routes[pair];
        uint256 routesLength = routes.length;

        unchecked {
            for (uint256 i = 0; i < routesLength; ++i) {
                IPath[] memory route = routes[i];
                uint256 routeLength = route.length;
                uint256 quoteValue = input;

                for (uint256 j = 0; j < routeLength; ++j) {
                    quoteValue = route[j].quoteTokenOutput(quoteValue);
                }

                if (quoteValue > output) {
                    index = i;
                    output = quoteValue;
                }
            }
        }

        output = output.mulDiv(_FEE_DEDUCTED, _FEE_BASE);
    }

    /**
     * @notice Get the best (lowest) swap input for a given output amount.
     * @param  pair    bytes32  Token pair.
     * @param  output  uint256  Amount of output token received from the swap.
     * @return index   uint256  Route index with the lowest input.
     * @return input   uint256  Amount of input token to swap.
     */
    function getSwapInput(
        bytes32 pair,
        uint256 output
    ) external view returns (uint256 index, uint256 input) {
        IPath[][] memory routes = _routes[pair];
        uint256 routesLength = routes.length;
        output = output.mulDivUp(_FEE_BASE, _FEE_DEDUCTED);

        unchecked {
            for (uint256 i = 0; i < routesLength; ++i) {
                IPath[] memory route = routes[i];
                uint256 routeIndex = route.length - 1;
                uint256 quoteValue = output;

                while (true) {
                    quoteValue = route[routeIndex].quoteTokenInput(quoteValue);

                    if (routeIndex == 0) break;

                    --routeIndex;
                }

                if (quoteValue < input || input == 0) {
                    index = i;
                    input = quoteValue;
                }
            }
        }
    }

    /**
     * @notice Get routes for a pair.
     * @param  pair  bytes32  Token pair.
     * @return       IPath[]  Routes and paths.
     */
    function getRoutes(bytes32 pair) external view returns (IPath[][] memory) {
        return _routes[pair];
    }
}
