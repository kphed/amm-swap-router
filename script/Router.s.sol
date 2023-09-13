// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Script.sol";
import {Router} from "src/Router.sol";
import {IPath} from "src/paths/IPath.sol";
import {CurveStableSwap} from "src/paths/CurveStableSwap.sol";
import {UniswapV3} from "src/paths/UniswapV3.sol";
import {CurveStableSwapFactory} from "src/paths/CurveStableSwapFactory.sol";
import {UniswapV3Factory} from "src/paths/UniswapV3Factory.sol";

contract RouterScript is Script {
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
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

    function _hashPair(
        address inputToken,
        address outputToken
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(inputToken, outputToken));
    }

    function _setUpPools(
        Router router,
        CurveStableSwapFactory curveStableSwapFactory,
        UniswapV3Factory uniswapV3Factory
    ) private {
        _setUpPoolsCRVUSD_ETH(router, curveStableSwapFactory, uniswapV3Factory);
        _setUpPoolsETH_CRVUSD(router, curveStableSwapFactory, uniswapV3Factory);
        _setUpPoolsCRVUSD_WSTETH(
            router,
            curveStableSwapFactory,
            uniswapV3Factory
        );
        _setUpPoolsWSTETH_CRVUSD(
            router,
            curveStableSwapFactory,
            uniswapV3Factory
        );
    }

    /**
     * @notice Conveniently add all available pools for more complex testing.
     */
    function _setUpPoolsCRVUSD_ETH(
        Router router,
        CurveStableSwapFactory curveStableSwapFactory,
        UniswapV3Factory uniswapV3Factory
    ) private {
        console.log("===");
        console.log("CRVUSD-ETH");
        bytes32 crvUSDETH = _hashPair(CRVUSD, WETH);
        IPath[] memory routes = new IPath[](2);
        routes[0] = IPath(
            curveStableSwapFactory.create(CURVE_USDC_CRVUSD, 1, 0)
        );

        console.log("CURVE_USDC_CRVUSD", address(routes[0]));

        routes[1] = IPath(uniswapV3Factory.create(UNISWAP_USDC_WETH, true));

        router.addRoute(crvUSDETH, routes);

        routes[0] = IPath(
            curveStableSwapFactory.create(CURVE_USDT_CRVUSD, 1, 0)
        );

        console.log("CURVE_USDT_CRVUSD", address(routes[0]));

        routes[1] = IPath(uniswapV3Factory.create(UNISWAP_WETH_USDT, false));

        router.addRoute(crvUSDETH, routes);
    }

    function _setUpPoolsETH_CRVUSD(
        Router router,
        CurveStableSwapFactory curveStableSwapFactory,
        UniswapV3Factory uniswapV3Factory
    ) private {
        console.log("===");
        console.log("CRVUSD-ETH");
        bytes32 ethCRVUSD = _hashPair(WETH, CRVUSD);
        IPath[] memory routes = new IPath[](2);
        routes[0] = IPath(uniswapV3Factory.create(UNISWAP_USDC_WETH, false));
        routes[1] = IPath(
            curveStableSwapFactory.create(CURVE_USDC_CRVUSD, 0, 1)
        );

        console.log("CURVE_USDC_CRVUSD", address(routes[1]));

        router.addRoute(ethCRVUSD, routes);

        routes[0] = IPath(uniswapV3Factory.create(UNISWAP_WETH_USDT, true));
        routes[1] = IPath(
            curveStableSwapFactory.create(CURVE_USDT_CRVUSD, 0, 1)
        );

        console.log("CURVE_USDT_CRVUSD", address(routes[1]));

        router.addRoute(ethCRVUSD, routes);
    }

    function _setUpPoolsCRVUSD_WSTETH(
        Router router,
        CurveStableSwapFactory curveStableSwapFactory,
        UniswapV3Factory uniswapV3Factory
    ) private {
        console.log("===");
        console.log("CRVUSD-WSTETH");
        bytes32 crvusdWSTETH = _hashPair(CRVUSD, WSTETH);
        IPath[] memory routes = new IPath[](3);
        routes[0] = IPath(
            curveStableSwapFactory.create(CURVE_USDC_CRVUSD, 1, 0)
        );

        console.log("CURVE_USDC_CRVUSD", address(routes[0]));

        routes[1] = IPath(uniswapV3Factory.create(UNISWAP_USDC_WETH, true));
        routes[2] = IPath(uniswapV3Factory.create(UNISWAP_WSTETH_WETH, false));

        router.addRoute(crvusdWSTETH, routes);

        routes[0] = IPath(
            curveStableSwapFactory.create(CURVE_USDT_CRVUSD, 1, 0)
        );

        console.log("CURVE_USDT_CRVUSD", address(routes[0]));

        routes[1] = IPath(uniswapV3Factory.create(UNISWAP_WETH_USDT, false));
        routes[2] = IPath(uniswapV3Factory.create(UNISWAP_WSTETH_WETH, false));

        router.addRoute(crvusdWSTETH, routes);
    }

    function _setUpPoolsWSTETH_CRVUSD(
        Router router,
        CurveStableSwapFactory curveStableSwapFactory,
        UniswapV3Factory uniswapV3Factory
    ) private {
        console.log("===");
        console.log("WSTETH-CRVUSD");
        bytes32 wstethCRVUSD = _hashPair(WSTETH, CRVUSD);
        IPath[] memory routes = new IPath[](3);
        routes[0] = IPath(uniswapV3Factory.create(UNISWAP_WSTETH_WETH, true));
        routes[1] = IPath(uniswapV3Factory.create(UNISWAP_USDC_WETH, false));
        routes[2] = IPath(
            curveStableSwapFactory.create(CURVE_USDC_CRVUSD, 0, 1)
        );

        console.log("CURVE_USDC_CRVUSD", address(routes[2]));

        router.addRoute(wstethCRVUSD, routes);

        routes[0] = IPath(uniswapV3Factory.create(UNISWAP_WSTETH_WETH, true));
        routes[1] = IPath(uniswapV3Factory.create(UNISWAP_WETH_USDT, true));
        routes[2] = IPath(
            curveStableSwapFactory.create(CURVE_USDT_CRVUSD, 0, 1)
        );

        console.log("CURVE_USDT_CRVUSD", address(routes[2]));

        router.addRoute(wstethCRVUSD, routes);
    }

    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        Router router = new Router(vm.envAddress("OWNER"));
        CurveStableSwapFactory curveStableSwapFactory = new CurveStableSwapFactory();
        UniswapV3Factory uniswapV3Factory = new UniswapV3Factory();

        _setUpPools(router, curveStableSwapFactory, uniswapV3Factory);

        console.log("");
        console.log("Router", address(router));
        console.log("CurveStableSwapFactory", address(curveStableSwapFactory));
        console.log("UniswapV3Factory", address(uniswapV3Factory));

        vm.stopBroadcast();
    }
}
