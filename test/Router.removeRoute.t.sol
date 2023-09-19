// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {RouterHelper} from "test/RouterHelper.sol";
import {IPath} from "src/paths/IPath.sol";
import {Router} from "src/Router.sol";

contract Router_removeRoute is Test, RouterHelper {
    event RemoveRoute(bytes32 indexed pair, uint256 indexed index);

    constructor() {
        _setUpRoutes();
    }

    function testCannotRemoveRouteUnauthorized() external {
        address msgSender = address(0);
        bytes32 pair = _hashPair(CRVUSD, WETH);
        uint256 index = 0;

        assertTrue(msgSender != router.owner());

        vm.prank(msgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        router.removeRoute(pair, index);
    }

    function testCannotRemoveRouteInvalidPair() external {
        address msgSender = router.owner();
        bytes32 pair = bytes32(0);

        uint256 index = 0;

        vm.prank(msgSender);
        vm.expectRevert(Router.InvalidPair.selector);

        router.removeRoute(pair, index);
    }

    function testRemoveRoute() external {
        address msgSender = router.owner();
        bytes32 pair = _hashPair(CRVUSD, WETH);
        uint256 index = 0;
        IPath[][] memory routesBefore = router.getRoutes(pair);
        bytes32 removedRoute = keccak256(abi.encodePacked(routesBefore[index]));

        assertTrue(index < routesBefore.length);

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(router));

        emit RemoveRoute(pair, index);

        router.removeRoute(pair, index);

        IPath[][] memory routes = router.getRoutes(pair);

        assertEq(routesBefore.length - 1, routes.length);

        for (uint256 i = 0; i < routes.length; ++i) {
            // Check the routes list to confirm that the route was removed.
            assertTrue(removedRoute != keccak256(abi.encodePacked(routes[i])));
        }
    }

    function testRemoveRouteFuzz(uint8 index) external {
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[][] memory routesBefore = router.getRoutes(pair);

        vm.assume(index < routesBefore.length);

        address msgSender = router.owner();
        bytes32 removedRoute = keccak256(abi.encodePacked(routesBefore[index]));
        uint256 lastIndex = routesBefore.length - 1;
        bytes32 lastRoute = keccak256(
            abi.encodePacked(routesBefore[lastIndex])
        );

        assertTrue(index < routesBefore.length);

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(router));

        emit RemoveRoute(pair, index);

        router.removeRoute(pair, index);

        IPath[][] memory routes = router.getRoutes(pair);

        assertEq(routesBefore.length - 1, routes.length);

        for (uint256 i = 0; i < routes.length; ++i) {
            // Check the routes list to confirm that the route was removed.
            assertTrue(removedRoute != keccak256(abi.encodePacked(routes[i])));
        }

        // If the removal index was not the last route index, then the last element replaced the element.
        if (index != lastIndex) {
            assertEq(lastRoute, keccak256(abi.encodePacked(routes[index])));
        }
    }
}
