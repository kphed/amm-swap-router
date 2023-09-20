// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Router} from "src/Router.sol";
import {IPath} from "src/interfaces/IPath.sol";
import {CurveStableSwap} from "src/paths/CurveStableSwap.sol";
import {UniswapV3} from "src/paths/UniswapV3.sol";
import {CurveStableSwapFactory} from "src/paths/CurveStableSwapFactory.sol";
import {UniswapV3Factory} from "src/paths/UniswapV3Factory.sol";

contract RouterScript is Script {
    using SafeTransferLib for address;

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
    }

    /**
     * @notice Conveniently add all available pools for more complex testing.
     */
    function _setUpPoolsCRVUSD_ETH(
        Router router,
        CurveStableSwapFactory curveStableSwapFactory,
        UniswapV3Factory uniswapV3Factory
    ) private {
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

    function _setUpPoolsETH_CRVUSD(
        Router router,
        CurveStableSwapFactory curveStableSwapFactory,
        UniswapV3Factory uniswapV3Factory
    ) private {
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

    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        Router router = new Router(vm.envAddress("OWNER"));

        WSTETH.safeTransfer(address(router), 1);
        WETH.safeTransfer(address(router), 1);
        USDC.safeTransfer(address(router), 1);
        USDT.safeTransfer(address(router), 1);
        CRVUSD.safeTransfer(address(router), 1);

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
