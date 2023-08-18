// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {PoolRegistry} from "src/PoolRegistry.sol";
import {ICurveCryptoV2, CurveCryptoV2} from "src/pools/CurveCryptoV2.sol";
import {ICurveStableSwap, CurveStableSwap} from "src/pools/CurveStableSwap.sol";

contract PoolRegistryTest is Test {
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
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

    PoolRegistry public immutable registry = new PoolRegistry(address(this));

    constructor() {
        address[] memory crvusdUSDTCoins = new address[](2);
        crvusdUSDTCoins[0] = CRVUSD;
        crvusdUSDTCoins[1] = USDT;
        address[] memory crvusdUSDCCoins = new address[](2);
        crvusdUSDCCoins[0] = CRVUSD;
        crvusdUSDCCoins[1] = USDC;
        address[] memory crvusdETHCRVCoins = new address[](3);
        crvusdETHCRVCoins[0] = CRVUSD;
        crvusdETHCRVCoins[1] = WETH;
        crvusdETHCRVCoins[2] = CRV;
        address[] memory usdtWBTCETHCoins = new address[](3);
        usdtWBTCETHCoins[0] = USDT;
        usdtWBTCETHCoins[1] = WBTC;
        usdtWBTCETHCoins[2] = WETH;
        address[] memory usdcWBTCETHCoins = new address[](3);
        usdcWBTCETHCoins[0] = USDC;
        usdcWBTCETHCoins[1] = WBTC;
        usdcWBTCETHCoins[2] = WETH;

        registry.setPool(CRVUSD_USDT, crvusdUSDTCoins);
        registry.setPool(CRVUSD_USDC, crvusdUSDCCoins);
        registry.setPool(CRVUSD_ETH_CRV, crvusdETHCRVCoins);
        registry.setPool(USDT_WBTC_ETH, usdtWBTCETHCoins);
        registry.setPool(USDC_WBTC_ETH, usdcWBTCETHCoins);
    }
}
