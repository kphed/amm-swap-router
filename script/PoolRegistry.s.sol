// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {PoolRegistry} from "src/PoolRegistry.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";
import {CurveStableSwap} from "src/pools/CurveStableSwap.sol";
import {UniswapV3} from "src/pools/UniswapV3.sol";
import {CurveStableSwapFactory} from "src/pools/CurveStableSwapFactory.sol";
import {UniswapV3Factory} from "src/pools/UniswapV3Factory.sol";

contract PoolRegistryScript is Script {
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

    function _encodePath(
        address pool,
        uint48 inputTokenIndex,
        uint48 outputTokenIndex
    ) private pure returns (bytes32) {
        return
            bytes32(abi.encodePacked(pool, inputTokenIndex, outputTokenIndex));
    }

    function _hashTokenPair(
        address inputToken,
        address outputToken
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(inputToken, outputToken));
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        bytes32 crvUSDETH = _hashTokenPair(CRVUSD, WETH);
        bytes32 ethCRVUSD = _hashTokenPair(WETH, CRVUSD);
        address[] memory crvUSDETHPools = new address[](2);
        address[] memory ethCRVUSDPools = new address[](2);

        vm.startBroadcast(deployerPrivateKey);

        UniswapV3Factory uniswapV3Factory = new UniswapV3Factory();
        CurveStableSwapFactory curveStableSwapFactory = new CurveStableSwapFactory();
        crvUSDETHPools[0] = curveStableSwapFactory.create(
            CURVE_CRVUSD_USDC,
            1,
            0
        );
        crvUSDETHPools[1] = uniswapV3Factory.create(
            UNISWAP_USDC_ETH,
            USDC,
            true
        );
        ethCRVUSDPools[0] = uniswapV3Factory.create(
            UNISWAP_USDC_ETH,
            WETH,
            false
        );
        ethCRVUSDPools[1] = curveStableSwapFactory.create(
            CURVE_CRVUSD_USDC,
            0,
            1
        );
        PoolRegistry registry = new PoolRegistry(vm.envAddress("OWNER"));

        registry.addExchangePath(crvUSDETH, crvUSDETHPools);
        registry.addExchangePath(ethCRVUSD, ethCRVUSDPools);

        vm.stopBroadcast();
    }
}
