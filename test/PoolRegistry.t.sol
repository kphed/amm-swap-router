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
    address public constant CRVUSD_USDT = 0x390f3595bCa2Df7d23783dFd126427CCeb997BF4;
    address public constant CRVUSD_USDC = 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
    address public constant CRVUSD_ETH_CRV = 0x4eBdF703948ddCEA3B11f675B4D1Fba9d2414A14;
    address public constant USDT_WBTC_ETH = 0xf5f5B97624542D72A9E06f04804Bf81baA15e2B4;
    address public constant USDC_WBTC_ETH = 0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B;
    IStandardPool public immutable curveCryptoV2 = IStandardPool(address(new CurveCryptoV2()));
    IStandardPool public immutable curveStableSwap = IStandardPool(address(new CurveStableSwap()));
    PoolRegistry public immutable registry = new PoolRegistry(address(this));

    event AddPool(address indexed pool, IStandardPool indexed poolInterface, uint256 indexed poolIndex);
    event AddExchangePath(
        bytes32 indexed tokenPair, uint256 indexed newPathIndex, uint256 indexed newPathLength, bytes32[] newPath
    );

    /*//////////////////////////////////////////////////////////////
                             addPool
    //////////////////////////////////////////////////////////////*/

    function testCannotAddPool_Unauthorized() external {
        address unauthorizedMsgSender = address(0);
        address pool = CRVUSD_USDT;
        IStandardPool poolInterface = curveStableSwap;

        assertTrue(unauthorizedMsgSender != registry.owner());

        vm.prank(unauthorizedMsgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        registry.addPool(pool, poolInterface);
    }

    function testCannotAddPool_Duplicate() external {
        address msgSender = address(this);
        address pool = CRVUSD_USDT;
        IStandardPool poolInterface = curveStableSwap;

        assertEq(msgSender, registry.owner());

        vm.startPrank(msgSender);

        registry.addPool(pool, poolInterface);

        vm.expectRevert(PoolRegistry.Duplicate.selector);

        registry.addPool(pool, poolInterface);

        vm.stopPrank();
    }

    function testAddPool() external {
        address msgSender = address(this);
        address pool = CRVUSD_USDT;
        IStandardPool poolInterface = curveStableSwap;
        address[] memory poolTokens = poolInterface.tokens(pool);
        uint256 poolIndex = registry.nextPoolIndex();

        assertEq(msgSender, registry.owner());
        assertEq(address(0), address(registry.poolInterfaces(pool)));
        assertEq(address(0), registry.poolIndexes(poolIndex));

        vm.prank(msgSender);
        vm.expectEmit(true, true, true, true, address(registry));

        emit AddPool(pool, poolInterface, poolIndex);

        registry.addPool(pool, poolInterface);

        unchecked {
            for (uint256 i = 0; i < poolTokens.length; ++i) {
                assertEq(poolTokens[i], registry.poolTokens(pool, i));
            }
        }

        assertEq(address(poolInterface), address(registry.poolInterfaces(pool)));
        assertEq(pool, registry.poolIndexes(poolIndex));
    }
}
