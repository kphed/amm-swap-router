// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {PoolRegistry} from "src/PoolRegistry.sol";
import {ICurveCryptoV2, CurveCryptoV2} from "src/pools/CurveCryptoV2.sol";
import {ICurveStableSwap, CurveStableSwap} from "src/pools/CurveStableSwap.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";

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
    address public immutable SP_CRVUSD_USDT =
        address(new CurveStableSwap(CRVUSD_USDT, 2));
    address public immutable SP_CRVUSD_USDC =
        address(new CurveStableSwap(CRVUSD_USDC, 2));
    address public immutable SP_CRVUSD_ETH_CRV =
        address(new CurveCryptoV2(CRVUSD_ETH_CRV, 3));
    address public immutable SP_USDT_WBTC_ETH =
        address(new CurveCryptoV2(USDT_WBTC_ETH, 3));
    address public immutable SP_USDC_WBTC_ETH =
        address(new CurveCryptoV2(USDC_WBTC_ETH, 3));

    PoolRegistry public immutable registry = new PoolRegistry(address(this));

    event AddPool(
        address indexed pool,
        uint256 indexed poolIndex,
        uint256 indexed tokenCount,
        address[] tokens
    );

    /*//////////////////////////////////////////////////////////////
                             addPool
    //////////////////////////////////////////////////////////////*/

    function testCannotAddPool_Unauthorized() external {
        address unauthorizedMsgSender = address(0);

        assertTrue(unauthorizedMsgSender != registry.owner());

        vm.prank(unauthorizedMsgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        registry.addPool(SP_CRVUSD_USDT);
    }

    function testCannotAddPool_PoolAlreadyExists() external {
        address msgSender = address(this);
        address pool = SP_CRVUSD_USDT;

        assertEq(msgSender, registry.owner());

        vm.startPrank(msgSender);

        registry.addPool(pool);

        vm.expectRevert(PoolRegistry.PoolAlreadyExists.selector);

        registry.addPool(pool);

        vm.stopPrank();
    }

    function testAddPool() external {
        address msgSender = address(this);
        address pool = SP_CRVUSD_USDT;
        address[] memory poolTokens = IStandardPool(pool).tokens();

        assertEq(msgSender, registry.owner());
        assertEq(0, registry.pools(pool));

        uint256 poolIndex = registry.nextPoolIndex();

        vm.prank(msgSender);
        vm.expectEmit(true, true, true, true, address(registry));

        emit AddPool(pool, poolIndex, poolTokens.length, poolTokens);

        registry.addPool(pool);

        unchecked {
            for (uint256 i = 0; i < poolTokens.length; ++i) {
                address[] memory poolsByToken = registry.poolsByToken(
                    poolTokens[i]
                );
                bool poolFound = false;

                for (uint256 j = 0; j < poolsByToken.length; ++j) {
                    if (poolsByToken[j] == pool) {
                        // Mark pool as found.
                        poolFound = true;
                        break;
                    }
                }

                assertTrue(poolFound);
            }
        }

        assertEq(poolTokens.length, registry.pools(pool));
        assertEq(pool, registry.poolIndexes(poolIndex));
    }
}
