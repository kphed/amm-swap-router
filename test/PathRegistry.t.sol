// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PathRegistry} from "src/PathRegistry.sol";
import {IPath} from "src/paths/IPath.sol";
import {UniswapV3Factory} from "src/paths/UniswapV3Factory.sol";
import {CurveStableSwapFactory} from "src/paths/CurveStableSwapFactory.sol";

interface ICurveStablecoin {
    function mint(address to, uint256 amount) external;
}

contract PathRegistryTest is Test {
    using SafeTransferLib for address;

    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant CURVE_CRVUSD_USDT =
        0x390f3595bCa2Df7d23783dFd126427CCeb997BF4;
    address public constant CURVE_CRVUSD_USDC =
        0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
    address public constant UNISWAP_USDC_ETH =
        0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address public constant UNISWAP_USDT_ETH =
        0x11b815efB8f581194ae79006d24E0d814B7697F6;
    address public constant CRVUSD_CONTROLLER =
        0xC9332fdCB1C491Dcc683bAe86Fe3cb70360738BC;
    UniswapV3Factory uniswapV3Factory = new UniswapV3Factory();
    CurveStableSwapFactory curveStableSwapFactory =
        new CurveStableSwapFactory();
    PathRegistry public immutable registry = new PathRegistry(address(this));

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

    receive() external payable {}

    function _hashPair(
        address inputToken,
        address outputToken
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(inputToken, outputToken));
    }

    function _mintCRVUSD(address recipient, uint256 amount) private {
        // crvUSD controller factory has permission to call `mint`.
        vm.prank(CRVUSD_CONTROLLER);

        ICurveStablecoin(CRVUSD).mint(recipient, amount);
    }

    /**
     * @notice Conveniently add all available pools for more complex testing.
     */
    function _setUpPools() private {
        bytes32 crvUSDETH = _hashPair(CRVUSD, WETH);
        IPath[] memory routes = new IPath[](2);
        routes[0] = IPath(
            curveStableSwapFactory.create(CURVE_CRVUSD_USDC, 1, 0)
        );
        routes[1] = IPath(uniswapV3Factory.create(UNISWAP_USDC_ETH, true));

        registry.addRoute(crvUSDETH, routes);

        routes[0] = IPath(
            curveStableSwapFactory.create(CURVE_CRVUSD_USDT, 1, 0)
        );
        routes[1] = IPath(uniswapV3Factory.create(UNISWAP_USDT_ETH, false));

        registry.addRoute(crvUSDETH, routes);

        bytes32 ethCRVUSD = _hashPair(WETH, CRVUSD);

        routes[0] = IPath(uniswapV3Factory.create(UNISWAP_USDC_ETH, false));
        routes[1] = IPath(
            curveStableSwapFactory.create(CURVE_CRVUSD_USDC, 0, 1)
        );

        registry.addRoute(ethCRVUSD, routes);

        routes[0] = IPath(uniswapV3Factory.create(UNISWAP_USDT_ETH, true));
        routes[1] = IPath(
            curveStableSwapFactory.create(CURVE_CRVUSD_USDT, 0, 1)
        );

        registry.addRoute(ethCRVUSD, routes);
    }

    /*//////////////////////////////////////////////////////////////
                             withdrawERC20
    //////////////////////////////////////////////////////////////*/

    function testCannotWithdrawERC20Unauthorized() external {
        address unauthorizedMsgSender = address(1);
        address token = CRVUSD;
        address recipient = address(this);
        uint256 amount = 1e18;

        assertTrue(unauthorizedMsgSender != registry.owner());

        vm.prank(unauthorizedMsgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        registry.withdrawERC20(token, recipient, amount);
    }

    function testWithdrawERC20() external {
        address msgSender = registry.owner();
        address token = CRVUSD;
        address recipient = address(this);
        uint256 amount = 1e18;

        _mintCRVUSD(address(registry), amount);

        assertEq(0, CRVUSD.balanceOf(address(this)));
        assertEq(amount, CRVUSD.balanceOf(address(registry)));

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(registry));

        emit WithdrawERC20(token, recipient, amount);

        registry.withdrawERC20(token, recipient, amount);

        assertEq(amount, CRVUSD.balanceOf(address(this)));
        assertEq(0, CRVUSD.balanceOf(address(registry)));
    }

    /*//////////////////////////////////////////////////////////////
                             addRoute
    //////////////////////////////////////////////////////////////*/

    function testCannotAddRouteUnauthorized() external {
        address unauthorizedMsgSender = address(1);
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[] memory newRoute = new IPath[](2);

        assertTrue(unauthorizedMsgSender != registry.owner());

        vm.prank(unauthorizedMsgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        registry.addRoute(pair, newRoute);
    }

    function testCannotAddRouteInvalidPair() external {
        address msgSender = registry.owner();
        bytes32 invalidTokenPair = bytes32(0);
        IPath[] memory newRoute = new IPath[](2);

        assertEq(bytes32(0), invalidTokenPair);

        vm.prank(msgSender);
        vm.expectRevert(PathRegistry.InvalidPair.selector);

        registry.addRoute(invalidTokenPair, newRoute);
    }

    function testCannotAddRouteEmptyArray() external {
        address msgSender = registry.owner();
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[] memory emptyNewRoute = new IPath[](0);

        assertEq(0, emptyNewRoute.length);

        vm.prank(msgSender);
        vm.expectRevert(PathRegistry.EmptyArray.selector);

        registry.addRoute(pair, emptyNewRoute);
    }

    function testAddRoute() external {
        address msgSender = registry.owner();
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[] memory newRoute = new IPath[](2);
        newRoute[0] = IPath(
            curveStableSwapFactory.create(CURVE_CRVUSD_USDC, 1, 0)
        );
        newRoute[1] = IPath(uniswapV3Factory.create(UNISWAP_USDC_ETH, true));
        uint256 addIndex = registry.getRoutes(pair).length;
        (
            address curveCRVUSDUSDCInputToken,
            address curveCRVUSDUSDCOutputToken
        ) = IPath(newRoute[0]).tokens();
        (
            address uniswapUSDCETHInputToken,
            address uniswapUSDCETHOutputToken
        ) = IPath(newRoute[1]).tokens();

        assertEq(0, addIndex);

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(registry));

        emit AddRoute(pair, newRoute);

        registry.addRoute(pair, newRoute);

        IPath[][] memory routes = registry.getRoutes(pair);

        assertEq(1, routes.length);

        IPath[] memory route = routes[addIndex];

        assertEq(newRoute.length, route.length);

        for (uint256 i = 0; i < newRoute.length; ++i) {
            assertEq(address(newRoute[i]), address(route[i]));
        }

        assertEq(
            type(uint256).max,
            ERC20(curveCRVUSDUSDCInputToken).allowance(
                address(registry),
                address(newRoute[0])
            )
        );
        assertEq(
            type(uint256).max,
            ERC20(curveCRVUSDUSDCOutputToken).allowance(
                address(registry),
                address(newRoute[0])
            )
        );
        assertEq(
            type(uint256).max,
            ERC20(uniswapUSDCETHInputToken).allowance(
                address(registry),
                address(newRoute[1])
            )
        );
        assertEq(
            type(uint256).max,
            ERC20(uniswapUSDCETHOutputToken).allowance(
                address(registry),
                address(newRoute[1])
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                             removeRoute
    //////////////////////////////////////////////////////////////*/

    function testCannotRemoveRouteUnauthorized() external {
        address unauthorizedMsgSender = address(1);
        bytes32 pair = _hashPair(CRVUSD, WETH);
        uint256 index = 0;

        assertTrue(unauthorizedMsgSender != registry.owner());

        vm.prank(unauthorizedMsgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        registry.removeRoute(pair, index);
    }

    function testCannotRemoveRouteInvalidPair() external {
        address msgSender = registry.owner();
        bytes32 invalidTokenPair = bytes32(0);
        uint256 index = 0;

        vm.prank(msgSender);
        vm.expectRevert(PathRegistry.InvalidPair.selector);

        registry.removeRoute(invalidTokenPair, index);
    }

    function testCannotRemoveRouteIndexOOB() external {
        _setUpPools();

        address msgSender = registry.owner();
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[][] memory routes = registry.getRoutes(pair);
        uint256 invalidIndex = routes.length + 1;

        assertGt(invalidIndex, routes.length);

        vm.prank(msgSender);
        vm.expectRevert(stdError.indexOOBError);

        registry.removeRoute(pair, invalidIndex);
    }

    function testRemoveRoute() external {
        _setUpPools();

        address msgSender = registry.owner();
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[][] memory routes = registry.getRoutes(pair);
        uint256 index = 0;
        uint256 lastIndex = routes.length - 1;
        IPath[] memory lastRoute = routes[lastIndex];

        assertTrue(index != lastIndex);
        assertEq(2, routes.length);

        for (uint256 i = 0; i < routes.length; ++i) {
            assertTrue(address(routes[index][i]) != address(lastRoute[i]));
        }

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(registry));

        emit RemoveRoute(pair, index);

        registry.removeRoute(pair, index);

        routes = registry.getRoutes(pair);

        assertEq(1, routes.length);

        for (uint256 i = 0; i < routes.length; ++i) {
            // The last exchange path now has the same index as the removed index.
            assertEq(address(routes[index][i]), address(lastRoute[i]));
        }
    }

    function testRemoveRouteLastIndex() external {
        _setUpPools();

        address msgSender = registry.owner();
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[][] memory routes = registry.getRoutes(pair);
        uint256 lastIndex = routes.length - 1;
        uint256 index = lastIndex;
        IPath[] memory lastPath = routes[lastIndex];

        assertEq(2, routes.length);

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(registry));

        emit RemoveRoute(pair, index);

        registry.removeRoute(pair, index);

        routes = registry.getRoutes(pair);
        lastIndex = routes.length - 1;

        assertEq(1, routes.length);

        for (uint256 i = 0; i < lastPath.length; ++i) {
            // The old last exchange path and the current last exchange path should not be equal.
            assertTrue(address(lastPath[i]) != address(routes[lastIndex][i]));
        }
    }

    /*//////////////////////////////////////////////////////////////
                             approvePath
    //////////////////////////////////////////////////////////////*/

    function testApprovePath() external {
        _setUpPools();

        bytes32 pair = _hashPair(CRVUSD, WETH);
        uint256 routeIndex = 0;
        uint256 pathIndex = 0;
        IPath path = IPath(registry.getRoutes(pair)[routeIndex][pathIndex]);
        (address inputToken, address outputToken) = path.tokens();

        vm.startPrank(address(registry));

        assertEq(
            type(uint256).max,
            ERC20(inputToken).allowance(address(registry), address(path))
        );
        assertEq(
            type(uint256).max,
            ERC20(outputToken).allowance(address(registry), address(path))
        );

        inputToken.safeApproveWithRetry(address(path), 0);
        outputToken.safeApproveWithRetry(address(path), 0);

        assertEq(
            0,
            ERC20(inputToken).allowance(address(registry), address(path))
        );
        assertEq(
            0,
            ERC20(outputToken).allowance(address(registry), address(path))
        );

        vm.stopPrank();

        address msgSender = address(this);

        vm.prank(msgSender);
        vm.expectEmit(true, false, false, true, address(registry));

        emit ApprovePath(path, inputToken, outputToken);

        registry.approvePath(pair, routeIndex, pathIndex);

        assertEq(
            type(uint256).max,
            ERC20(inputToken).allowance(address(registry), address(path))
        );
        assertEq(
            type(uint256).max,
            ERC20(outputToken).allowance(address(registry), address(path))
        );
    }

    /*//////////////////////////////////////////////////////////////
                             getSwapOutput
    //////////////////////////////////////////////////////////////*/

    function testCannotGetSwapOutputZeroInput() external {
        _setUpPools();

        bytes32 pair = _hashPair(CRVUSD, WETH);
        uint256 zeroInput = 0;

        vm.expectRevert();

        registry.getSwapOutput(pair, zeroInput);
    }

    function testGetSwapOutputInvalidPair() external {
        _setUpPools();

        bytes32 invalidPair = bytes32(0);
        uint256 input = 1e18;

        // Does not revert, just doesn't do anything.
        (uint256 index, uint256 output) = registry.getSwapOutput(
            invalidPair,
            input
        );

        assertEq(0, index);
        assertEq(0, output);
    }
}
