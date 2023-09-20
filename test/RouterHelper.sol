// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Router} from "src/Router.sol";
import {IPath} from "src/interfaces/IPath.sol";
import {UniswapV3Factory} from "src/paths/UniswapV3Factory.sol";
import {CurveStableSwapFactory} from "src/paths/CurveStableSwapFactory.sol";
import {CurveCryptoV2Factory} from "src/paths/CurveCryptoV2Factory.sol";

contract RouterHelper is Test {
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

    event Swap(
        address indexed inputToken,
        address indexed outputToken,
        uint256 indexed index,
        uint256 output,
        uint256 fees
    );

    receive() external payable {}

    constructor() {
        deal(CRVUSD, address(this), 1_000e18);
        deal(USDT, address(this), 1_000e6);
        deal(USDC, address(this), 1_000e6);
        deal(WSTETH, address(this), 1_000e6);
    }

    function _setUpRoutes() internal {
        _setUpRoutesCRVUSD_ETH();
        _setUpRoutesETH_CRVUSD();
    }

    function _hashPair(
        address inputToken,
        address outputToken
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(inputToken, outputToken));
    }

    function _getSwapOutput(
        IPath[] memory route,
        uint256 input
    ) internal view returns (uint256 quoteValue) {
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
    ) internal view returns (uint256 quoteValue) {
        uint256 routeIndex = route.length - 1;
        quoteValue = output.mulDivUp(ROUTER_FEE_BASE, ROUTER_FEE_DEDUCTED);

        while (true) {
            quoteValue = route[routeIndex].quoteTokenInput(quoteValue);

            if (routeIndex == 0) break;

            --routeIndex;
        }
    }

    function _setUpRoutesCRVUSD_ETH() private {
        IPath curveUSDC_CRVUSD = IPath(
            curveStableSwapFactory.create(CURVE_USDC_CRVUSD, 1, 0)
        );
        IPath uniswapUSDC_WETH = IPath(
            uniswapV3Factory.create(UNISWAP_USDC_WETH, true)
        );
        IPath curveUSDT_CRVUSD = IPath(
            curveStableSwapFactory.create(CURVE_USDT_CRVUSD, 1, 0)
        );
        IPath uniswapWETH_USDT = IPath(
            uniswapV3Factory.create(UNISWAP_WETH_USDT, false)
        );
        IPath uniswapWSTETH_WETH = IPath(
            uniswapV3Factory.create(UNISWAP_WSTETH_WETH, false)
        );

        USDC.safeTransfer(address(curveUSDC_CRVUSD), 1);
        CRVUSD.safeTransfer(address(curveUSDC_CRVUSD), 1);
        USDT.safeTransfer(address(curveUSDT_CRVUSD), 1);
        CRVUSD.safeTransfer(address(curveUSDT_CRVUSD), 1);

        IPath[] memory routes = new IPath[](2);
        routes[0] = IPath(curveUSDC_CRVUSD);
        routes[1] = IPath(uniswapUSDC_WETH);

        router.addRoute(routes);

        routes[0] = IPath(curveUSDT_CRVUSD);
        routes[1] = IPath(uniswapWETH_USDT);

        router.addRoute(routes);

        routes = new IPath[](3);
        routes[0] = IPath(curveUSDC_CRVUSD);
        routes[1] = IPath(uniswapUSDC_WETH);
        routes[2] = IPath(uniswapWSTETH_WETH);

        router.addRoute(routes);

        routes[0] = IPath(curveUSDT_CRVUSD);
        routes[1] = IPath(uniswapWETH_USDT);
        routes[2] = IPath(uniswapWSTETH_WETH);

        router.addRoute(routes);
    }

    function _setUpRoutesETH_CRVUSD() private {
        IPath uniswapUSDC_WETH = IPath(
            uniswapV3Factory.create(UNISWAP_USDC_WETH, false)
        );
        IPath curveUSDC_CRVUSD = IPath(
            curveStableSwapFactory.create(CURVE_USDC_CRVUSD, 0, 1)
        );
        IPath uniswapWETH_USDT = IPath(
            uniswapV3Factory.create(UNISWAP_WETH_USDT, true)
        );
        IPath curveUSDT_CRVUSD = IPath(
            curveStableSwapFactory.create(CURVE_USDT_CRVUSD, 0, 1)
        );
        IPath uniswapWSTETH_WETH = IPath(
            uniswapV3Factory.create(UNISWAP_WSTETH_WETH, true)
        );

        USDC.safeTransfer(address(curveUSDC_CRVUSD), 1);
        CRVUSD.safeTransfer(address(curveUSDC_CRVUSD), 1);
        USDT.safeTransfer(address(curveUSDT_CRVUSD), 1);
        CRVUSD.safeTransfer(address(curveUSDT_CRVUSD), 1);

        IPath[] memory routes = new IPath[](2);
        routes[0] = IPath(uniswapUSDC_WETH);
        routes[1] = IPath(curveUSDC_CRVUSD);

        router.addRoute(routes);

        routes[0] = IPath(uniswapWETH_USDT);
        routes[1] = IPath(curveUSDT_CRVUSD);

        router.addRoute(routes);

        routes = new IPath[](3);
        routes[0] = IPath(uniswapWSTETH_WETH);
        routes[1] = IPath(uniswapUSDC_WETH);
        routes[2] = IPath(curveUSDC_CRVUSD);

        router.addRoute(routes);

        routes[0] = IPath(uniswapWSTETH_WETH);
        routes[1] = IPath(uniswapWETH_USDT);
        routes[2] = IPath(curveUSDT_CRVUSD);

        router.addRoute(routes);
    }
}
