// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {PoolRegistry} from "src/PoolRegistry.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";
import {CurveCryptoV2} from "src/pools/CurveCryptoV2.sol";
import {CurveStableSwap} from "src/pools/CurveStableSwap.sol";
import {UniswapV3Fee500} from "src/pools/UniswapV3Fee500.sol";

contract PoolRegistryScript is Script {
    address public constant CURVE_CRVUSD_USDT =
        0x390f3595bCa2Df7d23783dFd126427CCeb997BF4;
    address public constant CURVE_CRVUSD_USDC =
        0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
    address public constant CURVE_CRVUSD_ETH_CRV =
        0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14;
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

        IStandardPool curveCryptoV2 = IStandardPool(
            address(new CurveCryptoV2())
        );
        IStandardPool curveStableSwap = IStandardPool(
            address(new CurveStableSwap())
        );
        IStandardPool uniswapV3Fee500 = IStandardPool(
            address(new UniswapV3Fee500())
        );
        PoolRegistry registry = new PoolRegistry(vm.envAddress("OWNER"));

        address[] memory pools = new address[](7);
        IStandardPool[] memory poolInterfaces = new IStandardPool[](7);
        pools[0] = CURVE_CRVUSD_USDT;
        pools[1] = CURVE_CRVUSD_USDC;
        pools[2] = CURVE_CRVUSD_ETH_CRV;
        pools[3] = CURVE_USDT_WBTC_ETH;
        pools[4] = CURVE_USDC_WBTC_ETH;
        pools[5] = UNISWAP_USDC_ETH;
        pools[6] = UNISWAP_USDT_ETH;
        poolInterfaces[0] = curveStableSwap;
        poolInterfaces[1] = curveStableSwap;
        poolInterfaces[2] = curveCryptoV2;
        poolInterfaces[3] = curveCryptoV2;
        poolInterfaces[4] = curveCryptoV2;
        poolInterfaces[5] = uniswapV3Fee500;
        poolInterfaces[6] = uniswapV3Fee500;
        bytes32 crvUSDETH = _hashTokenPair(CRVUSD, WETH);
        bytes32 ethCRVUSD = _hashTokenPair(WETH, CRVUSD);
        bytes32[] memory crvUSDETHPath1 = new bytes32[](2);
        bytes32[] memory crvUSDETHPath2 = new bytes32[](2);
        bytes32[] memory crvUSDETHPath3 = new bytes32[](2);
        bytes32[] memory ethCRVUSDPath1 = new bytes32[](2);
        bytes32[] memory ethCRVUSDPath2 = new bytes32[](2);
        bytes32[] memory ethCRVUSDPath3 = new bytes32[](2);
        crvUSDETHPath1[0] = _encodePath(CURVE_CRVUSD_USDC, 1, 0);
        crvUSDETHPath1[1] = _encodePath(CURVE_USDC_WBTC_ETH, 0, 2);
        crvUSDETHPath2[0] = _encodePath(CURVE_CRVUSD_USDT, 1, 0);
        crvUSDETHPath2[1] = _encodePath(UNISWAP_USDT_ETH, 1, 0);
        crvUSDETHPath3[0] = _encodePath(CURVE_CRVUSD_USDC, 1, 0);
        crvUSDETHPath3[1] = _encodePath(UNISWAP_USDC_ETH, 0, 1);
        ethCRVUSDPath1[0] = _encodePath(CURVE_USDC_WBTC_ETH, 2, 0);
        ethCRVUSDPath1[1] = _encodePath(CURVE_CRVUSD_USDC, 0, 1);
        ethCRVUSDPath2[0] = _encodePath(UNISWAP_USDT_ETH, 0, 1);
        ethCRVUSDPath2[1] = _encodePath(CURVE_CRVUSD_USDT, 0, 1);
        ethCRVUSDPath3[0] = _encodePath(UNISWAP_USDC_ETH, 1, 0);
        ethCRVUSDPath3[1] = _encodePath(CURVE_CRVUSD_USDC, 0, 1);

        bytes32[] memory tokenPairs = new bytes32[](6);
        tokenPairs[0] = crvUSDETH;
        tokenPairs[1] = crvUSDETH;
        tokenPairs[2] = crvUSDETH;
        tokenPairs[3] = ethCRVUSD;
        tokenPairs[4] = ethCRVUSD;
        tokenPairs[5] = ethCRVUSD;
        bytes32[][] memory paths = new bytes32[][](6);
        paths[0] = crvUSDETHPath1;
        paths[1] = crvUSDETHPath2;
        paths[2] = crvUSDETHPath3;
        paths[3] = ethCRVUSDPath1;
        paths[4] = ethCRVUSDPath2;
        paths[5] = ethCRVUSDPath3;

        registry.addPools(pools, poolInterfaces);
        registry.addExchangePaths(tokenPairs, paths);

        vm.stopBroadcast();
    }
}
