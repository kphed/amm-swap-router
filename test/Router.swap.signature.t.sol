// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Router} from "src/Router.sol";
import {RouterHelper} from "test/RouterHelper.sol";
import {IPath} from "src/interfaces/IPath.sol";
import {SignatureVerification} from "test/lib/SignatureVerification.sol";

contract Router_swap_signature is Test, RouterHelper {
    using SafeTransferLib for address;

    // Default but modifiable swap params (declaring as storage variables to avoid "stack too deep").
    address public msgSender = address(this);
    address public permitOwner = TEST_ACCOUNT;
    uint256 public input = 1_000e18;
    uint256 public nonce = input;
    uint256 public deadline = block.timestamp + 1 hours;
    address public inputToken = CRVUSD;
    address public outputToken = WETH;
    uint256 public minOutput = 1;
    uint256 public routeIndex = 0;
    address public referrer = address(this);

    function _marshallParams()
        private
        view
        returns (Router.PermitParams memory permitParams)
    {
        permitParams = Router.PermitParams({
            owner: permitOwner,
            nonce: input,
            deadline: deadline,
            signature: _signPermitTransferFrom(CRVUSD, input, nonce, deadline)
        });
    }

    function testCannotSwapInvalidSignature() external {
        Router.PermitParams memory permitParams = _marshallParams();
        permitParams.signature = bytes("");

        vm.prank(msgSender);
        vm.expectRevert(SignatureVerification.InvalidSignatureLength.selector);

        router.swap(
            inputToken,
            outputToken,
            input,
            minOutput,
            routeIndex,
            referrer,
            permitParams
        );

        // Recompute to start from a valid base.
        permitParams = _marshallParams();

        // Can be anything other than 27 or 28. Will result in ecrecover returning the zero address.
        permitParams.signature[64] = bytes1(uint8(0));

        vm.prank(msgSender);
        vm.expectRevert(SignatureVerification.InvalidSignature.selector);

        router.swap(
            inputToken,
            outputToken,
            input,
            minOutput,
            routeIndex,
            referrer,
            permitParams
        );

        permitParams = _marshallParams();

        // Will be a valid signature but wrong signer address.
        permitParams.owner = address(1);

        vm.prank(msgSender);
        vm.expectRevert(SignatureVerification.InvalidSigner.selector);

        router.swap(
            inputToken,
            outputToken,
            input,
            minOutput,
            routeIndex,
            referrer,
            permitParams
        );
    }

    function testCannotSwapTransferFromFailed() external {
        _setUpRoutes();

        Router.PermitParams memory permitParams = _marshallParams();

        vm.prank(msgSender);
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));

        router.swap(
            inputToken,
            outputToken,
            input,
            minOutput,
            routeIndex,
            referrer,
            permitParams
        );
    }

    function testCannotSwapNoRoutes() external {
        Router.PermitParams memory permitParams = _marshallParams();
        IPath[][] memory routes = router.getRoutes(
            _hashPair(inputToken, outputToken)
        );

        deal(inputToken, permitOwner, input);

        assertEq(0, routes.length);

        vm.prank(msgSender);
        vm.expectRevert(stdError.indexOOBError);

        router.swap(
            inputToken,
            outputToken,
            input,
            minOutput,
            routeIndex,
            referrer,
            permitParams
        );
    }
}
