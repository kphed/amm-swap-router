// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {PoolRegistry} from "src/PoolRegistry.sol";
import {CurveCryptoV2} from "src/pools/CurveCryptoV2.sol";
import {CurveStableSwap} from "src/pools/CurveStableSwap.sol";

contract PoolRegistryTest is Test {
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant CRVUSD_USDT =
        0x390f3595bCa2Df7d23783dFd126427CCeb997BF4;
    address public constant CRVUSD_USDC =
        0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
    address public constant CRVUSD_ETH_CRV =
        0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14;
    address public constant USDT_WBTC_ETH =
        0xf5f5B97624542D72A9E06f04804Bf81baA15e2B4;
    address public constant USDC_WBTC_ETH =
        0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B;

    address public immutable curveCryptoV2 = address(new CurveCryptoV2());
    address public immutable curveStableSwap = address(new CurveStableSwap());
    PoolRegistry public immutable registry = new PoolRegistry(address(this));

    constructor() {
        registry.setPool(CRVUSD_USDT, curveStableSwap);
        registry.setPool(CRVUSD_USDC, curveStableSwap);
        registry.setPool(CRVUSD_ETH_CRV, curveCryptoV2);
        registry.setPool(USDT_WBTC_ETH, curveCryptoV2);
        registry.setPool(USDC_WBTC_ETH, curveCryptoV2);

        // crvUSD => ETH
        PoolRegistry.Path[] memory crvUSDETHPath1 = new PoolRegistry.Path[](1);
        crvUSDETHPath1[0] = PoolRegistry.Path(CRVUSD_ETH_CRV, CRVUSD, WETH);

        // crvUSD => USDT => ETH
        PoolRegistry.Path[] memory crvUSDETHPath2 = new PoolRegistry.Path[](2);
        crvUSDETHPath2[0] = PoolRegistry.Path(CRVUSD_ETH_CRV, CRVUSD, USDT);
        crvUSDETHPath2[1] = PoolRegistry.Path(USDT_WBTC_ETH, USDT, WETH);

        // crvUSD => USDC => ETH
        PoolRegistry.Path[] memory crvUSDETHPath3 = new PoolRegistry.Path[](2);
        crvUSDETHPath3[0] = PoolRegistry.Path(CRVUSD_USDC, CRVUSD, USDC);
        crvUSDETHPath3[1] = PoolRegistry.Path(USDC_WBTC_ETH, USDC, WETH);

        PoolRegistry.Path[][] memory newPaths = new PoolRegistry.Path[][](3);
        newPaths[0] = crvUSDETHPath1;
        newPaths[1] = crvUSDETHPath2;
        newPaths[2] = crvUSDETHPath3;

        registry.setPaths(CRVUSD, WETH, newPaths);
    }
}
