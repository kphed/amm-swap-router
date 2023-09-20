// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {RouterHelper} from "test/RouterHelper.sol";
import {Router} from "src/Router.sol";
import {IPath} from "src/interfaces/IPath.sol";

contract Router_addRoute is Test, RouterHelper {
    IPath[] private route;

    event AddRoute(
        address indexed inputToken,
        address indexed outputToken,
        IPath[] newRoute
    );
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );

    constructor() {
        route.push(
            IPath(curveStableSwapFactory.create(CURVE_USDC_CRVUSD, 1, 0))
        );
        route.push(IPath(uniswapV3Factory.create(UNISWAP_USDC_WETH, true)));
    }

    function testCannotAddRouteUnauthorized() external {
        address msgSender = address(0);

        assertTrue(msgSender != router.owner());

        vm.prank(msgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        router.addRoute(route);
    }

    function testCannotAddRouteEmptyArray() external {
        address msgSender = router.owner();
        route = new IPath[](0);

        vm.prank(msgSender);
        vm.expectRevert(Router.EmptyArray.selector);

        router.addRoute(route);
    }

    function testAddRoute() external {
        address msgSender = router.owner();
        (address pairInputToken, ) = route[0].tokens();
        (, address pairOutputToken) = route[route.length - 1].tokens();
        bytes32 pair = _hashPair(pairInputToken, pairOutputToken);
        IPath[][] memory routesBefore = router.getRoutes(pair);

        vm.prank(msgSender);

        for (uint256 i = 0; i < route.length; ++i) {
            (address inputToken, address outputToken) = route[i].tokens();

            vm.expectEmit(true, true, false, true, inputToken);

            emit Approval(
                address(router),
                address(route[i]),
                type(uint256).max
            );

            vm.expectEmit(true, true, false, true, outputToken);

            emit Approval(
                address(router),
                address(route[i]),
                type(uint256).max
            );
        }

        vm.expectEmit(true, true, false, true, address(router));

        emit AddRoute(pairInputToken, pairOutputToken, route);

        router.addRoute(route);

        IPath[][] memory routesAfter = router.getRoutes(pair);

        assertEq(routesBefore.length + 1, routesAfter.length);
        assertEq(
            keccak256(abi.encodePacked(route)),
            keccak256(abi.encodePacked(routesAfter[routesBefore.length]))
        );

        for (uint256 i = 0; i < route.length; ++i) {
            (address inputToken, address outputToken) = route[i].tokens();

            assertEq(
                ERC20(inputToken).allowance(address(router), address(route[i])),
                type(uint256).max
            );
            assertEq(
                ERC20(outputToken).allowance(
                    address(router),
                    address(route[i])
                ),
                type(uint256).max
            );
        }
    }
}
