// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {IPermit2, ISignatureTransfer} from "src/interfaces/IPermit2.sol";
import {IPath} from "src/interfaces/IPath.sol";
import {ReentrancyGuard} from "src/lib/ReentrancyGuard.sol";

/**
 * @title J.Page Router
 * @notice Cheap and efficient cross-AMM swaps.
 * @author kp (ppmoon69.eth)
 */
contract Router is Ownable, ReentrancyGuard {
    using SafeTransferLib for address;
    using SafeCastLib for uint256;
    using FixedPointMathLib for uint256;

    struct PermitParams {
        address owner;
        uint256 nonce;
        uint256 deadline;
        bytes signature;
    }

    // Each swap incurs a 2 bps (0.02%) fee.
    uint256 private constant _FEE_DEDUCTED = 9_998;
    uint256 private constant _FEE_BASE = 10_000;

    IPermit2 private constant _PERMIT2 =
        IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // Swap routes for a given token pair - each route is comprised of 1 or more paths.
    mapping(bytes32 pair => IPath[][] routes) private _routes;

    event WithdrawERC20(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );
    event AddRoute(
        address indexed inputToken,
        address indexed outputToken,
        IPath[] newRoute
    );
    event RemoveRoute(bytes32 indexed pair, uint256 indexed index);
    event ApprovePath(
        IPath indexed path,
        address indexed inputToken,
        address indexed outputToken
    );
    event Swap(
        address indexed inputToken,
        address indexed outputToken,
        uint256 indexed index,
        uint256 output,
        uint256 fees
    );

    error InsufficientOutput();
    error InvalidPair();
    error EmptyArray();
    error NoRoutesRemaining();

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
        // Throws if `recipient` is the zero address or if `amount` exceeds our balance.
        token.safeTransfer(recipient, amount);

        emit WithdrawERC20(token, recipient, amount);
    }

    /**
     * @notice Add a route.
     * @param  newRoute  IPath[]  New swap route.
     */
    function addRoute(IPath[] calldata newRoute) external onlyOwner {
        uint256 newRouteLength = newRoute.length;

        if (newRouteLength == 0) revert EmptyArray();

        unchecked {
            (address pairInputToken, ) = newRoute[0].tokens();

            // Will not underflow since route length is 1+.
            (, address pairOutputToken) = newRoute[newRouteLength - 1].tokens();

            IPath[] storage route = _routes[
                keccak256(abi.encodePacked(pairInputToken, pairOutputToken))
            ].push();

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

            emit AddRoute(pairInputToken, pairOutputToken, newRoute);
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

        unchecked {
            // Should be checked by the owner before calling.
            uint256 lastIndex = routes.length - 1;

            // At least 1 route must be remaining.
            if (lastIndex == 0) revert NoRoutesRemaining();

            if (index != lastIndex) routes[index] = routes[lastIndex];

            routes.pop();
        }

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

        inputToken.safeApproveWithRetry(address(path), type(uint256).max);
        outputToken.safeApproveWithRetry(address(path), type(uint256).max);

        emit ApprovePath(path, inputToken, outputToken);
    }

    /**
     * @notice Swap an input token for an output token.
     * @param  inputToken       address  Token to swap.
     * @param  outputToken      address  Token to receive.
     * @param  input            uint256  Amount of input token to swap.
     * @param  minOutput        uint256  Minimum amount of output token to receive.
     * @param  outputRecipient  address  Output token recipient address.
     * @param  routeIndex       uint256  Route index.
     * @param  referrer         address  Referrer address (receives 50% of the fees if specified).
     * @return output           uint256  Amount of output token received from the swap.
     */
    function _swap(
        address inputToken,
        address outputToken,
        uint256 input,
        uint256 minOutput,
        address outputRecipient,
        uint256 routeIndex,
        address referrer
    ) private returns (uint256 output) {
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

        // The difference between the balances before/after the swaps is the canonical output.
        output = outputToken.balanceOf(address(this)) - output;

        if (output < minOutput) revert InsufficientOutput();

        unchecked {
            uint256 originalOutput = output;
            output = originalOutput.mulDiv(_FEE_DEDUCTED, _FEE_BASE);

            // Will not overflow since `output` is 99.98% of `originalOutput`.
            uint256 fees = originalOutput - output;

            outputToken.safeTransfer(outputRecipient, output);

            // If the referrer is non-zero, split 50% of the fees (rounded down) with the referrer.
            // The remainder is kept by the contract which can later be withdrawn by the owner.
            if (referrer != address(0) && fees > 1) {
                // Will not overflow since `fees` is 2 or greater.
                outputToken.safeTransfer(referrer, fees / 2);
            }

            emit Swap(inputToken, outputToken, routeIndex, output, fees);
        }
    }

    /**
     * @notice Swap an input token for an output token (standard ERC20 approval).
     * @dev    See `_swap` for additional parameter details.
     */
    function swap(
        address inputToken,
        address outputToken,
        uint256 input,
        uint256 minOutput,
        uint256 routeIndex,
        address referrer
    ) external nonReentrant returns (uint256) {
        inputToken.safeTransferFrom(msg.sender, address(this), input);

        return
            _swap(
                inputToken,
                outputToken,
                input,
                minOutput,
                msg.sender,
                routeIndex,
                referrer
            );
    }

    /**
     * @notice Swap an input token for an output token (Permit2 allowance-based approval).
     * @dev    See `_swap` for additional parameter details.
     */
    function swap(
        address inputToken,
        address outputToken,
        uint160 input,
        uint256 minOutput,
        uint256 routeIndex,
        address referrer
    ) external nonReentrant returns (uint256) {
        _PERMIT2.transferFrom(msg.sender, address(this), input, inputToken);

        return
            _swap(
                inputToken,
                outputToken,
                input,
                minOutput,
                msg.sender,
                routeIndex,
                referrer
            );
    }

    /**
     * @notice Swap an input token for an output token (Permit2 signature-based approval).
     * @dev    See `_swap` for parameter details.
     */
    function swap(
        address inputToken,
        address outputToken,
        uint256 input,
        uint256 minOutput,
        uint256 routeIndex,
        address referrer,
        PermitParams calldata permitParams
    ) external nonReentrant returns (uint256) {
        _PERMIT2.permitTransferFrom(
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: inputToken,
                    amount: input
                }),
                nonce: permitParams.nonce,
                deadline: permitParams.deadline
            }),
            ISignatureTransfer.SignatureTransferDetails({
                to: address(this),
                requestedAmount: input
            }),
            permitParams.owner,
            permitParams.signature
        );

        return
            _swap(
                inputToken,
                outputToken,
                input,
                minOutput,
                // Transfer the output tokens to the input token owner, not `msg.sender`!
                // This enables token holders to delegate swaps and the associated gas fees.
                permitParams.owner,
                routeIndex,
                referrer
            );
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

    // Overridden to enforce 2-step ownership transfers.
    function transferOwnership(
        address newOwner
    ) public payable override onlyOwner {}

    // Overridden to enforce 2-step ownership transfers.
    function renounceOwnership() public payable override onlyOwner {}
}
