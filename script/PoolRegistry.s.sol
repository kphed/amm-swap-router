// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {PoolRegistry} from "src/PoolRegistry.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";
import {CurveCryptoV2} from "src/pools/CurveCryptoV2.sol";
import {CurveStableSwap} from "src/pools/CurveStableSwap.sol";
import {UniswapV3} from "src/pools/UniswapV3.sol";

contract PoolRegistryScript is Script {
    address public constant CURVE_CRVUSD_USDT =
        0x390f3595bCa2Df7d23783dFd126427CCeb997BF4;
    address public constant CURVE_CRVUSD_USDC =
        0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
    address public constant CURVE_USDT_WBTC_ETH =
        0xf5f5B97624542D72A9E06f04804Bf81baA15e2B4;
    address public constant CURVE_USDC_WBTC_ETH =
        0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B;
    address public constant UNISWAP_USDC_ETH =
        0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address public constant UNISWAP_USDT_ETH =
        0x11b815efB8f581194ae79006d24E0d814B7697F6;
    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
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

        vm.startBroadcast(deployerPrivateKey);

        IStandardPool curveStableSwap = IStandardPool(
            address(new CurveStableSwap())
        );
        IStandardPool uniswapV3 = IStandardPool(address(new UniswapV3()));
        PoolRegistry registry = new PoolRegistry(vm.envAddress("OWNER"));

        address[] memory pools = new address[](4);
        IStandardPool[] memory poolInterfaces = new IStandardPool[](4);
        pools[0] = CURVE_CRVUSD_USDT;
        pools[1] = CURVE_CRVUSD_USDC;
        pools[2] = UNISWAP_USDC_ETH;
        pools[3] = UNISWAP_USDT_ETH;
        poolInterfaces[0] = curveStableSwap;
        poolInterfaces[1] = curveStableSwap;
        poolInterfaces[2] = uniswapV3;
        poolInterfaces[3] = uniswapV3;

        registry.addPools(pools, poolInterfaces);

        bytes32 crvUSDETH = _hashTokenPair(CRVUSD, WETH);
        address[] memory crvUSDETHPools = new address[](2);
        crvUSDETHPools[0] = CURVE_CRVUSD_USDC;
        crvUSDETHPools[1] = UNISWAP_USDC_ETH;
        uint48[2][] memory crvUSDETHTokenIndexes = new uint48[2][](2);
        crvUSDETHTokenIndexes[0][0] = 1;
        crvUSDETHTokenIndexes[0][1] = 0;
        crvUSDETHTokenIndexes[1][0] = 0;
        crvUSDETHTokenIndexes[1][1] = 1;

        registry.addExchangePath(
            crvUSDETH,
            crvUSDETHPools,
            crvUSDETHTokenIndexes
        );

        bytes32 ethCRVUSD = _hashTokenPair(WETH, CRVUSD);
        address[] memory ethCRVUSDPools = new address[](2);
        ethCRVUSDPools[0] = UNISWAP_USDC_ETH;
        ethCRVUSDPools[1] = CURVE_CRVUSD_USDC;
        uint48[2][] memory ethCRVUSDTokenIndexes = new uint48[2][](2);
        ethCRVUSDTokenIndexes[0][0] = 1;
        ethCRVUSDTokenIndexes[0][1] = 0;
        ethCRVUSDTokenIndexes[1][0] = 0;
        ethCRVUSDTokenIndexes[1][1] = 1;

        registry.addExchangePath(
            ethCRVUSD,
            ethCRVUSDPools,
            ethCRVUSDTokenIndexes
        );

        vm.stopBroadcast();
    }
}
