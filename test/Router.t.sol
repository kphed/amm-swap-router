// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Router} from "src/Router.sol";
import {IPath} from "src/paths/IPath.sol";
import {UniswapV3Factory} from "src/paths/UniswapV3Factory.sol";
import {CurveStableSwapFactory} from "src/paths/CurveStableSwapFactory.sol";
import {CurveCryptoV2Factory} from "src/paths/CurveCryptoV2Factory.sol";

interface ICurveStablecoin {
    function mint(address to, uint256 amount) external;
}

contract RouterTest is Test {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant CURVE_CRVUSD_ETH_CRV =
        0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14;
    address public constant CURVE_CRVUSD_TBTC_WSTETH =
        0x2889302a794dA87fBF1D6Db415C1492194663D13;
    address public constant CURVE_USDT_CRVUSD =
        0x390f3595bCa2Df7d23783dFd126427CCeb997BF4;
    address public constant CURVE_USDC_CRVUSD =
        0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
    address public constant UNISWAP_USDC_WETH =
        0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address public constant UNISWAP_WETH_USDT =
        0x11b815efB8f581194ae79006d24E0d814B7697F6;
    address public constant UNISWAP_WSTETH_WETH =
        0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa;
    address public constant CRVUSD_CONTROLLER =
        0xC9332fdCB1C491Dcc683bAe86Fe3cb70360738BC;
    uint256 public constant ROUTER_FEE_DEDUCTED = 9_998;
    uint256 public constant ROUTER_FEE_BASE = 10_000;
    UniswapV3Factory public immutable uniswapV3Factory = new UniswapV3Factory();
    CurveStableSwapFactory public immutable curveStableSwapFactory =
        new CurveStableSwapFactory();
    CurveCryptoV2Factory public immutable curveCryptoV2Factory =
        new CurveCryptoV2Factory();
    Router public immutable router = new Router(address(this));

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
        address indexed inputToken,
        address indexed outputToken,
        uint256 indexed index,
        uint256 output,
        uint256 fees
    );
    event Transfer(address indexed from, address indexed to, uint256 amount);

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

    function _setUpPools() private {
        _setUpPoolsCRVUSD_ETH();
        _setUpPoolsETH_CRVUSD();
        _setUpPoolsCRVUSD_WSTETH();
        _setUpPoolsWSTETH_CRVUSD();
    }

    /**
     * @notice Conveniently add all available pools for more complex testing.
     */
    function _setUpPoolsCRVUSD_ETH() private {
        bytes32 crvUSDETH = _hashPair(CRVUSD, WETH);
        IPath[] memory routes = new IPath[](2);
        routes[0] = IPath(
            curveStableSwapFactory.create(CURVE_USDC_CRVUSD, 1, 0)
        );
        routes[1] = IPath(uniswapV3Factory.create(UNISWAP_USDC_WETH, true));

        router.addRoute(crvUSDETH, routes);

        routes[0] = IPath(
            curveStableSwapFactory.create(CURVE_USDT_CRVUSD, 1, 0)
        );
        routes[1] = IPath(uniswapV3Factory.create(UNISWAP_WETH_USDT, false));

        router.addRoute(crvUSDETH, routes);
    }

    function _setUpPoolsETH_CRVUSD() private {
        bytes32 ethCRVUSD = _hashPair(WETH, CRVUSD);
        IPath[] memory routes = new IPath[](2);
        routes[0] = IPath(uniswapV3Factory.create(UNISWAP_USDC_WETH, false));
        routes[1] = IPath(
            curveStableSwapFactory.create(CURVE_USDC_CRVUSD, 0, 1)
        );

        router.addRoute(ethCRVUSD, routes);

        routes[0] = IPath(uniswapV3Factory.create(UNISWAP_WETH_USDT, true));
        routes[1] = IPath(
            curveStableSwapFactory.create(CURVE_USDT_CRVUSD, 0, 1)
        );

        router.addRoute(ethCRVUSD, routes);
    }

    function _setUpPoolsCRVUSD_WSTETH() private {
        bytes32 crvusdWSTETH = _hashPair(CRVUSD, WSTETH);
        IPath[] memory routes = new IPath[](3);
        routes[0] = IPath(
            curveStableSwapFactory.create(CURVE_USDC_CRVUSD, 1, 0)
        );
        routes[1] = IPath(uniswapV3Factory.create(UNISWAP_USDC_WETH, true));
        routes[2] = IPath(uniswapV3Factory.create(UNISWAP_WSTETH_WETH, false));

        router.addRoute(crvusdWSTETH, routes);

        routes[0] = IPath(
            curveStableSwapFactory.create(CURVE_USDT_CRVUSD, 1, 0)
        );
        routes[1] = IPath(uniswapV3Factory.create(UNISWAP_WETH_USDT, false));
        routes[2] = IPath(uniswapV3Factory.create(UNISWAP_WSTETH_WETH, false));

        router.addRoute(crvusdWSTETH, routes);
    }

    function _setUpPoolsWSTETH_CRVUSD() private {
        bytes32 wstethCRVUSD = _hashPair(WSTETH, CRVUSD);
        IPath[] memory routes = new IPath[](3);
        routes[0] = IPath(uniswapV3Factory.create(UNISWAP_WSTETH_WETH, true));
        routes[1] = IPath(uniswapV3Factory.create(UNISWAP_USDC_WETH, false));
        routes[2] = IPath(
            curveStableSwapFactory.create(CURVE_USDC_CRVUSD, 0, 1)
        );

        router.addRoute(wstethCRVUSD, routes);

        routes[0] = IPath(uniswapV3Factory.create(UNISWAP_WSTETH_WETH, true));
        routes[1] = IPath(uniswapV3Factory.create(UNISWAP_WETH_USDT, true));
        routes[2] = IPath(
            curveStableSwapFactory.create(CURVE_USDT_CRVUSD, 0, 1)
        );

        router.addRoute(wstethCRVUSD, routes);
    }

    function _getSwapOutput(
        IPath[] memory route,
        uint256 input
    ) private view returns (uint256 quoteValue) {
        uint256 routeLength = route.length;
        quoteValue = input;

        for (uint256 j = 0; j < routeLength; ++j) {
            quoteValue = route[j].quoteTokenOutput(quoteValue);
        }

        quoteValue = quoteValue.mulDiv(ROUTER_FEE_DEDUCTED, ROUTER_FEE_BASE);
    }

    function _getSwapInput(
        IPath[] memory route,
        uint256 output
    ) private view returns (uint256 quoteValue) {
        uint256 routeIndex = route.length - 1;
        quoteValue = output.mulDivUp(ROUTER_FEE_BASE, ROUTER_FEE_DEDUCTED);

        while (true) {
            quoteValue = route[routeIndex].quoteTokenInput(quoteValue);

            if (routeIndex == 0) break;

            --routeIndex;
        }
    }

    /*//////////////////////////////////////////////////////////////
                             withdrawERC20
    //////////////////////////////////////////////////////////////*/

    function testCannotWithdrawERC20Unauthorized() external {
        address unauthorizedMsgSender = address(1);
        address token = CRVUSD;
        address recipient = address(this);
        uint256 amount = 1e18;

        assertTrue(unauthorizedMsgSender != router.owner());

        vm.prank(unauthorizedMsgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        router.withdrawERC20(token, recipient, amount);
    }

    function testWithdrawERC20() external {
        address msgSender = router.owner();
        address token = CRVUSD;
        address recipient = address(this);
        uint256 amount = 1e18;

        _mintCRVUSD(address(router), amount);

        assertEq(0, CRVUSD.balanceOf(address(this)));
        assertEq(amount, CRVUSD.balanceOf(address(router)));

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(router));

        emit WithdrawERC20(token, recipient, amount);

        router.withdrawERC20(token, recipient, amount);

        assertEq(amount, CRVUSD.balanceOf(address(this)));
        assertEq(0, CRVUSD.balanceOf(address(router)));
    }

    /*//////////////////////////////////////////////////////////////
                             addRoute
    //////////////////////////////////////////////////////////////*/

    function testCannotAddRouteUnauthorized() external {
        address unauthorizedMsgSender = address(1);
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[] memory newRoute = new IPath[](2);

        assertTrue(unauthorizedMsgSender != router.owner());

        vm.prank(unauthorizedMsgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        router.addRoute(pair, newRoute);
    }

    function testCannotAddRouteInvalidPair() external {
        address msgSender = router.owner();
        bytes32 invalidTokenPair = bytes32(0);
        IPath[] memory newRoute = new IPath[](2);

        assertEq(bytes32(0), invalidTokenPair);

        vm.prank(msgSender);
        vm.expectRevert(Router.InvalidPair.selector);

        router.addRoute(invalidTokenPair, newRoute);
    }

    function testCannotAddRouteEmptyArray() external {
        address msgSender = router.owner();
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[] memory emptyNewRoute = new IPath[](0);

        assertEq(0, emptyNewRoute.length);

        vm.prank(msgSender);
        vm.expectRevert(Router.EmptyArray.selector);

        router.addRoute(pair, emptyNewRoute);
    }

    function testAddRoute() external {
        address msgSender = router.owner();
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[] memory newRoute = new IPath[](2);
        newRoute[0] = IPath(
            curveStableSwapFactory.create(CURVE_USDC_CRVUSD, 1, 0)
        );
        newRoute[1] = IPath(uniswapV3Factory.create(UNISWAP_USDC_WETH, true));
        uint256 addIndex = router.getRoutes(pair).length;
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
        vm.expectEmit(true, true, false, true, address(router));

        emit AddRoute(pair, newRoute);

        router.addRoute(pair, newRoute);

        IPath[][] memory routes = router.getRoutes(pair);

        assertEq(1, routes.length);

        IPath[] memory route = routes[addIndex];

        assertEq(newRoute.length, route.length);
        assertEq(
            keccak256(abi.encodePacked(newRoute)),
            keccak256(abi.encodePacked(route))
        );
        assertEq(
            type(uint256).max,
            ERC20(curveCRVUSDUSDCInputToken).allowance(
                address(router),
                address(newRoute[0])
            )
        );
        assertEq(
            type(uint256).max,
            ERC20(curveCRVUSDUSDCOutputToken).allowance(
                address(router),
                address(newRoute[0])
            )
        );
        assertEq(
            type(uint256).max,
            ERC20(uniswapUSDCETHInputToken).allowance(
                address(router),
                address(newRoute[1])
            )
        );
        assertEq(
            type(uint256).max,
            ERC20(uniswapUSDCETHOutputToken).allowance(
                address(router),
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

        assertTrue(unauthorizedMsgSender != router.owner());

        vm.prank(unauthorizedMsgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        router.removeRoute(pair, index);
    }

    function testCannotRemoveRouteInvalidPair() external {
        address msgSender = router.owner();
        bytes32 invalidTokenPair = bytes32(0);
        uint256 index = 0;

        vm.prank(msgSender);
        vm.expectRevert(Router.InvalidPair.selector);

        router.removeRoute(invalidTokenPair, index);
    }

    function testCannotRemoveRouteIndexOOB() external {
        _setUpPools();

        address msgSender = router.owner();
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[][] memory routes = router.getRoutes(pair);
        uint256 invalidIndex = routes.length + 1;

        assertGt(invalidIndex, routes.length);

        vm.prank(msgSender);
        vm.expectRevert(stdError.indexOOBError);

        router.removeRoute(pair, invalidIndex);
    }

    function testRemoveRoute() external {
        _setUpPools();

        address msgSender = router.owner();
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[][] memory routes = router.getRoutes(pair);
        uint256 index = 0;
        uint256 lastIndex = routes.length - 1;
        IPath[] memory lastRoute = routes[lastIndex];

        assertTrue(index != lastIndex);
        assertEq(2, routes.length);
        assertTrue(
            keccak256(abi.encodePacked(routes[index])) !=
                keccak256(abi.encodePacked(lastRoute))
        );

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(router));

        emit RemoveRoute(pair, index);

        router.removeRoute(pair, index);

        routes = router.getRoutes(pair);

        assertEq(1, routes.length);
        assertEq(
            keccak256(abi.encodePacked(routes[index])),
            keccak256(abi.encodePacked(lastRoute))
        );
    }

    function testRemoveRouteLastIndex() external {
        _setUpPools();

        address msgSender = router.owner();
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[][] memory routes = router.getRoutes(pair);
        uint256 lastIndex = routes.length - 1;
        uint256 index = lastIndex;
        IPath[] memory lastPath = routes[lastIndex];

        assertEq(2, routes.length);
        assertEq(
            keccak256(abi.encodePacked(lastPath)),
            keccak256(abi.encodePacked(routes[lastIndex]))
        );

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(router));

        emit RemoveRoute(pair, index);

        router.removeRoute(pair, index);

        routes = router.getRoutes(pair);
        lastIndex = routes.length - 1;

        assertEq(1, routes.length);
        assertTrue(
            keccak256(abi.encodePacked(lastPath)) !=
                keccak256(abi.encodePacked(routes[lastIndex]))
        );
    }

    /*//////////////////////////////////////////////////////////////
                             approvePath
    //////////////////////////////////////////////////////////////*/

    function testApprovePath() external {
        _setUpPools();

        bytes32 pair = _hashPair(CRVUSD, WETH);
        uint256 routeIndex = 0;
        uint256 pathIndex = 0;
        IPath path = IPath(router.getRoutes(pair)[routeIndex][pathIndex]);
        (address inputToken, address outputToken) = path.tokens();

        vm.startPrank(address(router));

        assertEq(
            type(uint256).max,
            ERC20(inputToken).allowance(address(router), address(path))
        );
        assertEq(
            type(uint256).max,
            ERC20(outputToken).allowance(address(router), address(path))
        );

        inputToken.safeApproveWithRetry(address(path), 0);
        outputToken.safeApproveWithRetry(address(path), 0);

        assertEq(
            0,
            ERC20(inputToken).allowance(address(router), address(path))
        );
        assertEq(
            0,
            ERC20(outputToken).allowance(address(router), address(path))
        );

        vm.stopPrank();

        address msgSender = address(this);

        vm.prank(msgSender);
        vm.expectEmit(true, false, false, true, address(router));

        emit ApprovePath(path, inputToken, outputToken);

        router.approvePath(pair, routeIndex, pathIndex);

        assertEq(
            type(uint256).max,
            ERC20(inputToken).allowance(address(router), address(path))
        );
        assertEq(
            type(uint256).max,
            ERC20(outputToken).allowance(address(router), address(path))
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

        router.getSwapOutput(pair, zeroInput);
    }

    function testGetSwapOutputInvalidPair() external {
        _setUpPools();

        bytes32 invalidPair = bytes32(0);
        uint256 input = 1e18;

        // Does not revert, just doesn't do anything.
        (uint256 index, uint256 output) = router.getSwapOutput(
            invalidPair,
            input
        );

        assertEq(0, index);
        assertEq(0, output);
    }

    function testGetSwapOutput() external {
        _setUpPools();

        bytes32 pair = _hashPair(CRVUSD, WETH);
        uint256 input = 100e18;
        IPath[][] memory routes = router.getRoutes(pair);
        uint256[] memory outputs = new uint256[](routes.length);
        uint256 bestOutputIndex = 0;
        uint256 bestOutput = 0;

        for (uint256 i = 0; i < routes.length; ++i) {
            outputs[i] = _getSwapOutput(routes[i], input);

            if (outputs[i] > bestOutput) {
                bestOutputIndex = i;
                bestOutput = outputs[i];
            }
        }

        (uint256 index, uint256 output) = router.getSwapOutput(pair, input);

        assertEq(bestOutputIndex, index);
        assertEq(bestOutput, output);
    }

    /*//////////////////////////////////////////////////////////////
                             getSwapInput
    //////////////////////////////////////////////////////////////*/

    function testCannotGetSwapInputZeroInput() external {
        _setUpPools();

        bytes32 pair = _hashPair(CRVUSD, WETH);
        uint256 zeroOutput = 0;

        vm.expectRevert();

        router.getSwapInput(pair, zeroOutput);
    }

    function testGetSwapInputInvalidPair() external {
        _setUpPools();

        bytes32 invalidPair = bytes32(0);
        uint256 output = 1e18;
        (uint256 index, uint256 input) = router.getSwapInput(
            invalidPair,
            output
        );

        assertEq(0, index);
        assertEq(0, input);
    }

    function testGetSwapInput() external {
        _setUpPools();

        bytes32 pair = _hashPair(CRVUSD, WETH);
        uint256 output = 1e18;
        IPath[][] memory routes = router.getRoutes(pair);
        uint256[] memory inputs = new uint256[](routes.length);
        uint256 bestInputIndex = 0;
        uint256 bestInput = 0;

        for (uint256 i = 0; i < routes.length; ++i) {
            inputs[i] = _getSwapInput(routes[i], output);

            if (inputs[i] < bestInput || bestInput == 0) {
                bestInputIndex = i;
                bestInput = inputs[i];
            }
        }

        (uint256 index, uint256 input) = router.getSwapInput(pair, output);

        assertEq(bestInputIndex, index);
        assertEq(bestInput, input);
    }

    /*//////////////////////////////////////////////////////////////
                             swap
    //////////////////////////////////////////////////////////////*/

    function testCannotSwapInsufficientOutput() external {
        _setUpPools();

        bytes32 pair = _hashPair(CRVUSD, WETH);
        uint256 input = 1_000e18;
        (uint256 index, uint256 output) = router.getSwapOutput(pair, input);
        uint256 excessiveOutput = output * 2;

        _mintCRVUSD(address(this), input);
        CRVUSD.safeApprove(address(router), input);

        vm.expectRevert(Router.InsufficientOutput.selector);

        router.swap(CRVUSD, WETH, input, excessiveOutput, index, address(0));
    }

    function testSwap() external {
        _setUpPools();

        bytes32 pair = _hashPair(CRVUSD, WETH);
        uint256 input = 1_000e18;
        (uint256 index, uint256 output) = router.getSwapOutput(pair, input);
        uint256 preFeeOutput = output.mulDivUp(
            ROUTER_FEE_BASE,
            ROUTER_FEE_DEDUCTED
        );
        uint256 expectedFees = preFeeOutput - output;

        assertLt(output, preFeeOutput);
        assertEq(expectedFees + output, preFeeOutput);

        _mintCRVUSD(address(this), input);
        CRVUSD.safeApprove(address(router), input);

        uint256 inputBalanceBefore = CRVUSD.balanceOf(address(this));
        uint256 outputBalanceBefore = WETH.balanceOf(address(this));
        uint256 inputAllowanceBefore = ERC20(CRVUSD).allowance(
            address(this),
            address(router)
        );
        uint256 feesBalanceBefore = WETH.balanceOf(address(router));

        vm.expectEmit(true, true, false, true, CRVUSD);

        emit Transfer(address(this), address(router), input);

        vm.expectEmit(true, true, true, true, address(router));

        emit Swap(CRVUSD, WETH, index, output, expectedFees);

        vm.expectEmit(true, true, false, true, WETH);

        emit Transfer(address(router), address(this), output);

        uint256 actualOutput = router.swap(
            CRVUSD,
            WETH,
            input,
            output,
            index,
            address(0)
        );

        assertEq(output, actualOutput);
        assertEq(inputBalanceBefore - input, CRVUSD.balanceOf(address(this)));
        assertEq(
            inputAllowanceBefore - input,
            ERC20(CRVUSD).allowance(address(this), address(router))
        );
        assertEq(outputBalanceBefore + output, WETH.balanceOf(address(this)));
        assertEq(
            feesBalanceBefore + expectedFees,
            WETH.balanceOf(address(router))
        );
    }
}
