// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {Router} from "src/Router.sol";
import {IPath} from "src/paths/IPath.sol";
import {CurveStableSwap} from "src/paths/CurveStableSwap.sol";
import {UniswapV3} from "src/paths/UniswapV3.sol";
import {CurveStableSwapFactory} from "src/paths/CurveStableSwapFactory.sol";
import {UniswapV3Factory} from "src/paths/UniswapV3Factory.sol";

contract RouterScript is Script {
    address public constant CURVE_CRVUSD_USDT =
        0x390f3595bCa2Df7d23783dFd126427CCeb997BF4;
    address public constant CURVE_CRVUSD_USDC =
        0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
    address public constant UNISWAP_USDC_ETH =
        0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address public constant UNISWAP_USDT_ETH =
        0x11b815efB8f581194ae79006d24E0d814B7697F6;
    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function _hashPair(
        address inputToken,
        address outputToken
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(inputToken, outputToken));
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        bytes32 crvUSDETH = _hashPair(CRVUSD, WETH);
        bytes32 ethCRVUSD = _hashPair(WETH, CRVUSD);
        IPath[] memory crvUSDETHPools = new IPath[](2);
        IPath[] memory ethCRVUSDPools = new IPath[](2);

        vm.startBroadcast(deployerPrivateKey);

        UniswapV3Factory uniswapV3Factory = new UniswapV3Factory();
        CurveStableSwapFactory curveStableSwapFactory = new CurveStableSwapFactory();
        crvUSDETHPools[0] = IPath(
            curveStableSwapFactory.create(CURVE_CRVUSD_USDC, 1, 0)
        );
        crvUSDETHPools[1] = IPath(
            uniswapV3Factory.create(UNISWAP_USDC_ETH, true)
        );
        ethCRVUSDPools[0] = IPath(
            uniswapV3Factory.create(UNISWAP_USDC_ETH, false)
        );
        ethCRVUSDPools[1] = IPath(
            curveStableSwapFactory.create(CURVE_CRVUSD_USDC, 0, 1)
        );
        Router registry = new Router(vm.envAddress("OWNER"));

        registry.addRoute(crvUSDETH, crvUSDETHPools);
        registry.addRoute(ethCRVUSD, ethCRVUSDPools);

        console.log("===");
        console.log("Registry", address(registry));
        console.log("");
        console.log("=== crvUSD => WETH ===");
        console.log("CurveStableSwap: CRVUSD-USDC", address(crvUSDETHPools[0]));
        console.log("Uniswap: USDC-WETH", address(crvUSDETHPools[1]));
        console.log("");
        console.log("=== WETH => crvUSD ===");
        console.log("Uniswap: USDC-WETH", address(ethCRVUSDPools[0]));
        console.log("CurveStableSwap: CRVUSD-USDC", address(ethCRVUSDPools[1]));
        console.log("");
        console.log("===");

        vm.stopBroadcast();
    }
}
