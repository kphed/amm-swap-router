// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {RouterHelper} from "test/RouterHelper.sol";
import {Router} from "src/Router.sol";
import {IPath} from "src/paths/IPath.sol";

contract Router_approvePath is Test, RouterHelper {
    using SafeTransferLib for address;

    event ApprovePath(
        IPath indexed path,
        address indexed inputToken,
        address indexed outputToken
    );
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    constructor() {
        _setUpRoutes();
    }

    function testCannotApprovePathUnauthorized() external {
        address msgSender = address(0);
        bytes32 pair = _hashPair(CRVUSD, WETH);
        uint256 routeIndex = 0;
        uint256 pathIndex = 0;

        assertTrue(msgSender != router.owner());

        vm.prank(msgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        router.approvePath(pair, routeIndex, pathIndex);
    }

    function testApprovePath() external {
        address msgSender = router.owner();
        bytes32 pair = _hashPair(CRVUSD, WETH);
        uint256 routeIndex = 0;
        uint256 pathIndex = 0;
        IPath path = router.getRoutes(pair)[routeIndex][pathIndex];
        (address pathInputToken, address pathOutputToken) = path.tokens();

        vm.startPrank(address(router));

        pathInputToken.safeApprove(address(path), 0);
        pathOutputToken.safeApprove(address(path), 0);

        assertEq(
            0,
            ERC20(pathInputToken).allowance(address(router), address(path))
        );
        assertEq(
            0,
            ERC20(pathOutputToken).allowance(address(router), address(path))
        );

        vm.stopPrank();
        vm.prank(msgSender);
        vm.expectEmit(true, true, true, true, address(router));

        emit ApprovePath(path, pathInputToken, pathOutputToken);

        vm.expectEmit(true, true, false, true, pathInputToken);

        emit Approval(address(router), address(path), type(uint256).max);

        vm.expectEmit(true, true, false, true, pathOutputToken);

        emit Approval(address(router), address(path), type(uint256).max);

        router.approvePath(pair, routeIndex, pathIndex);

        assertEq(
            type(uint256).max,
            ERC20(pathInputToken).allowance(address(router), address(path))
        );
        assertEq(
            type(uint256).max,
            ERC20(pathOutputToken).allowance(address(router), address(path))
        );
    }
}
