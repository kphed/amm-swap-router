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

        console.log("curveCryptoV2", address(curveCryptoV2));
        console.log("curveStableSwap", address(curveStableSwap));
        console.log("uniswapV3Fee500", address(uniswapV3Fee500));
        console.log("registry", address(registry));
        console.log("owner", registry.owner());

        registry.addPool(CURVE_CRVUSD_USDT, curveStableSwap);
        registry.addPool(CURVE_CRVUSD_USDC, curveStableSwap);
        registry.addPool(CURVE_CRVUSD_ETH_CRV, curveCryptoV2);
        registry.addPool(CURVE_USDT_WBTC_ETH, curveCryptoV2);
        registry.addPool(CURVE_USDC_WBTC_ETH, curveCryptoV2);
        registry.addPool(UNISWAP_USDC_ETH, uniswapV3Fee500);
        registry.addPool(UNISWAP_USDT_ETH, uniswapV3Fee500);

        bytes32 crvUSDETH = _hashTokenPair(CRVUSD, WETH);
        bytes32[] memory crvUSDETHPath1 = new bytes32[](2);
        crvUSDETHPath1[0] = _encodePath(CURVE_CRVUSD_USDC, 1, 0);
        crvUSDETHPath1[1] = _encodePath(CURVE_USDC_WBTC_ETH, 0, 2);

        registry.addExchangePath(crvUSDETH, crvUSDETHPath1);

        bytes32[] memory crvUSDETHPath2 = new bytes32[](2);
        crvUSDETHPath2[0] = _encodePath(CURVE_CRVUSD_USDT, 1, 0);
        crvUSDETHPath2[1] = _encodePath(UNISWAP_USDT_ETH, 1, 0);

        registry.addExchangePath(crvUSDETH, crvUSDETHPath2);

        bytes32[] memory crvUSDETHPath3 = new bytes32[](2);
        crvUSDETHPath3[0] = _encodePath(CURVE_CRVUSD_USDC, 1, 0);
        crvUSDETHPath3[1] = _encodePath(UNISWAP_USDC_ETH, 0, 1);

        registry.addExchangePath(crvUSDETH, crvUSDETHPath3);

        bytes32 ethCRVUSD = _hashTokenPair(WETH, CRVUSD);
        bytes32[] memory ethCRVUSDPath1 = new bytes32[](2);
        ethCRVUSDPath1[0] = _encodePath(CURVE_USDC_WBTC_ETH, 2, 0);
        ethCRVUSDPath1[1] = _encodePath(CURVE_CRVUSD_USDC, 0, 1);

        registry.addExchangePath(ethCRVUSD, ethCRVUSDPath1);

        bytes32[] memory ethCRVUSDPath2 = new bytes32[](2);
        ethCRVUSDPath2[0] = _encodePath(UNISWAP_USDT_ETH, 0, 1);
        ethCRVUSDPath2[1] = _encodePath(CURVE_CRVUSD_USDT, 0, 1);

        registry.addExchangePath(ethCRVUSD, ethCRVUSDPath2);

        bytes32[] memory ethCRVUSDPath3 = new bytes32[](2);
        ethCRVUSDPath3[0] = _encodePath(UNISWAP_USDC_ETH, 1, 0);
        ethCRVUSDPath3[1] = _encodePath(CURVE_CRVUSD_USDC, 0, 1);

        registry.addExchangePath(ethCRVUSD, ethCRVUSDPath3);

        vm.stopBroadcast();
    }
}
