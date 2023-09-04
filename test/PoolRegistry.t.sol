// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PoolRegistry} from "src/PoolRegistry.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";
import {ICurveStableSwap, CurveStableSwap} from "src/pools/CurveStableSwap.sol";
import {UniswapV3Fee500} from "src/pools/UniswapV3Fee500.sol";

interface ICurveStablecoin {
    function mint(address to, uint256 amount) external;
}

contract PoolRegistryTest is Test {
    using SafeTransferLib for address;

    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant CURVE_CRVUSD_USDT =
        0x390f3595bCa2Df7d23783dFd126427CCeb997BF4;
    address public constant CURVE_CRVUSD_USDC =
        0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
    address public constant UNISWAP_USDC_ETH =
        0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address public constant UNISWAP_USDT_ETH =
        0x11b815efB8f581194ae79006d24E0d814B7697F6;
    address public constant CRVUSD_CONTROLLER =
        0xC9332fdCB1C491Dcc683bAe86Fe3cb70360738BC;
    IStandardPool public immutable curveStableSwap =
        IStandardPool(address(new CurveStableSwap()));
    IStandardPool public immutable uniswapV3Fee500 =
        IStandardPool(address(new UniswapV3Fee500()));
    PoolRegistry public immutable registry = new PoolRegistry(address(this));

    event AddPool(address indexed pool, address[] tokens);
    event AddExchangePath(bytes32 indexed tokenPair);

    receive() external payable {}

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

    function _mintCRVUSD(address recipient, uint256 amount) private {
        // crvUSD controller factory has permission to call `mint`.
        vm.prank(CRVUSD_CONTROLLER);

        ICurveStablecoin(CRVUSD).mint(recipient, amount);
    }

    /**
     * @notice Conveniently add all available pools for more complex testing.
     */
    function _setUpPools() private {
        registry.addPool(CURVE_CRVUSD_USDT, curveStableSwap);
        registry.addPool(CURVE_CRVUSD_USDC, curveStableSwap);
        registry.addPool(UNISWAP_USDC_ETH, uniswapV3Fee500);
        registry.addPool(UNISWAP_USDT_ETH, uniswapV3Fee500);

        bytes32 crvUSDETH = _hashTokenPair(CRVUSD, WETH);
        address[] memory pools = new address[](2);
        pools[0] = CURVE_CRVUSD_USDC;
        pools[1] = UNISWAP_USDC_ETH;
        uint48[2][] memory tokenIndexes = new uint48[2][](2);
        tokenIndexes[0][0] = 1;
        tokenIndexes[0][1] = 0;
        tokenIndexes[1][0] = 0;
        tokenIndexes[1][1] = 1;

        registry.addExchangePath(crvUSDETH, pools, tokenIndexes);

        pools = new address[](2);
        pools[0] = CURVE_CRVUSD_USDT;
        pools[1] = UNISWAP_USDT_ETH;
        tokenIndexes = new uint48[2][](2);
        tokenIndexes[0][0] = 1;
        tokenIndexes[0][1] = 0;
        tokenIndexes[1][0] = 1;
        tokenIndexes[1][1] = 0;

        registry.addExchangePath(crvUSDETH, pools, tokenIndexes);
    }

    /*//////////////////////////////////////////////////////////////
                             addPool
    //////////////////////////////////////////////////////////////*/

    function testCannotAddPoolUnauthorized() external {
        address unauthorizedMsgSender = address(1);
        address pool = CURVE_CRVUSD_USDC;
        IStandardPool poolInterface = curveStableSwap;

        assertTrue(unauthorizedMsgSender != registry.owner());

        vm.prank(unauthorizedMsgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        registry.addPool(pool, poolInterface);
    }

    function testCannotAddPoolDuplicate() external {
        address msgSender = registry.owner();
        address pool = CURVE_CRVUSD_USDC;
        IStandardPool poolInterface = curveStableSwap;

        vm.startPrank(msgSender);

        registry.addPool(pool, poolInterface);

        vm.expectRevert(PoolRegistry.Duplicate.selector);

        registry.addPool(pool, poolInterface);

        vm.stopPrank();
    }

    function testAddPool() external {
        address msgSender = registry.owner();
        address pool = CURVE_CRVUSD_USDC;
        IStandardPool poolInterface = curveStableSwap;
        address[] memory tokens = poolInterface.tokens(pool);

        vm.prank(msgSender);
        vm.expectEmit(true, false, false, true, address(registry));

        emit AddPool(pool, tokens);

        registry.addPool(pool, poolInterface);

        assertEq(
            address(poolInterface),
            address(registry.poolInterfaces(pool))
        );

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(tokens[i], registry.poolTokens(pool, i));
        }
    }

    /*//////////////////////////////////////////////////////////////
                             addPools
    //////////////////////////////////////////////////////////////*/

    function testCannotAddPoolsUnauthorized() external {
        address unauthorizedMsgSender = address(1);
        address[] memory pools = new address[](2);
        pools[0] = CURVE_CRVUSD_USDT;
        pools[1] = UNISWAP_USDT_ETH;
        IStandardPool[] memory poolInterfaces = new IStandardPool[](2);
        poolInterfaces[0] = curveStableSwap;
        poolInterfaces[1] = uniswapV3Fee500;

        assertTrue(unauthorizedMsgSender != registry.owner());

        vm.prank(unauthorizedMsgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        registry.addPools(pools, poolInterfaces);
    }

    function testCannotAddPoolsDuplicate() external {
        address msgSender = registry.owner();
        address[] memory pools = new address[](2);
        pools[0] = CURVE_CRVUSD_USDT;
        pools[1] = CURVE_CRVUSD_USDT;
        IStandardPool[] memory poolInterfaces = new IStandardPool[](2);
        poolInterfaces[0] = curveStableSwap;
        poolInterfaces[1] = curveStableSwap;

        vm.prank(msgSender);
        vm.expectRevert(PoolRegistry.Duplicate.selector);

        registry.addPools(pools, poolInterfaces);
    }

    function testAddPools() external {
        address msgSender = registry.owner();
        address[] memory pools = new address[](4);
        pools[0] = CURVE_CRVUSD_USDT;
        pools[1] = CURVE_CRVUSD_USDC;
        pools[2] = UNISWAP_USDC_ETH;
        pools[3] = UNISWAP_USDT_ETH;
        IStandardPool[] memory poolInterfaces = new IStandardPool[](4);
        poolInterfaces[0] = curveStableSwap;
        poolInterfaces[1] = curveStableSwap;
        poolInterfaces[2] = uniswapV3Fee500;
        poolInterfaces[3] = uniswapV3Fee500;

        vm.startPrank(msgSender);

        for (uint256 i = 0; i < pools.length; ++i) {
            vm.expectEmit(true, false, false, true, address(registry));

            emit AddPool(pools[i], poolInterfaces[i].tokens(pools[i]));
        }

        registry.addPools(pools, poolInterfaces);

        vm.stopPrank();

        for (uint256 i = 0; i < pools.length; ++i) {
            address pool = pools[i];
            IStandardPool poolInterface = poolInterfaces[i];

            assertEq(
                address(poolInterface),
                address(registry.poolInterfaces(pool))
            );

            address[] memory tokens = poolInterface.tokens(pool);

            for (uint256 j = 0; j < tokens.length; ++j) {
                assertEq(tokens[j], registry.poolTokens(pool, j));
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                             addExchangePath
    //////////////////////////////////////////////////////////////*/

    function testCannotAddExchangePathUnauthorized() external {
        address unauthorizedMsgSender = address(1);
        bytes32 tokenPair = _hashTokenPair(CRVUSD, WETH);
        address[] memory pools = new address[](1);
        pools[0] = CURVE_CRVUSD_USDC;
        uint48[2][] memory tokenIndexes = new uint48[2][](1);
        tokenIndexes[0][0] = 1;
        tokenIndexes[0][1] = 0;

        assertTrue(unauthorizedMsgSender != registry.owner());

        vm.prank(unauthorizedMsgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        registry.addExchangePath(tokenPair, pools, tokenIndexes);
    }

    function testCannotAddExchangePathPoolTokenNotSet1() external {
        address msgSender = registry.owner();
        bytes32 tokenPair = _hashTokenPair(CRVUSD, WETH);
        address[] memory pools = new address[](1);
        pools[0] = CURVE_CRVUSD_USDC;
        uint48[2][] memory tokenIndexes = new uint48[2][](1);
        tokenIndexes[0][0] = 1;
        tokenIndexes[0][1] = 0;

        assertEq(
            address(0),
            registry.poolTokens(CURVE_CRVUSD_USDC, tokenIndexes[0][0])
        );
        assertEq(
            address(0),
            registry.poolTokens(CURVE_CRVUSD_USDC, tokenIndexes[0][1])
        );

        vm.prank(msgSender);
        vm.expectRevert(PoolRegistry.PoolTokenNotSet.selector);

        registry.addExchangePath(tokenPair, pools, tokenIndexes);
    }

    function testCannotAddExchangePathPoolTokenNotSet2() external {
        address pool = CURVE_CRVUSD_USDC;
        IStandardPool poolInterface = curveStableSwap;

        registry.addPool(pool, poolInterface);

        address msgSender = registry.owner();
        bytes32 tokenPair = _hashTokenPair(CRVUSD, WETH);
        address[] memory pools = new address[](1);
        pools[0] = CURVE_CRVUSD_USDC;
        uint48[2][] memory tokenIndexes = new uint48[2][](1);
        tokenIndexes[0][0] = 2;
        tokenIndexes[0][1] = 0;

        assertEq(address(0), registry.poolTokens(pool, tokenIndexes[0][0]));
        assertTrue(address(0) != registry.poolTokens(pool, tokenIndexes[0][1]));

        vm.prank(msgSender);
        vm.expectRevert(PoolRegistry.PoolTokenNotSet.selector);

        registry.addExchangePath(tokenPair, pools, tokenIndexes);
    }

    function testCannotAddExchangePathPoolTokenNotSet3() external {
        address pool = CURVE_CRVUSD_USDC;
        IStandardPool poolInterface = curveStableSwap;

        registry.addPool(pool, poolInterface);

        address msgSender = registry.owner();
        bytes32 tokenPair = _hashTokenPair(CRVUSD, WETH);
        address[] memory pools = new address[](1);
        pools[0] = CURVE_CRVUSD_USDC;
        uint48[2][] memory tokenIndexes = new uint48[2][](1);
        tokenIndexes[0][0] = 0;
        tokenIndexes[0][1] = 2;

        assertTrue(address(0) != registry.poolTokens(pool, tokenIndexes[0][0]));
        assertEq(address(0), registry.poolTokens(pool, tokenIndexes[0][1]));

        vm.prank(msgSender);
        vm.expectRevert(PoolRegistry.PoolTokenNotSet.selector);

        registry.addExchangePath(tokenPair, pools, tokenIndexes);
    }

    function testCannotAddExchangePathPoolTokensIdentical() external {
        address pool = CURVE_CRVUSD_USDC;
        IStandardPool poolInterface = curveStableSwap;

        registry.addPool(pool, poolInterface);

        address msgSender = registry.owner();
        bytes32 tokenPair = _hashTokenPair(CRVUSD, WETH);
        address[] memory pools = new address[](1);
        pools[0] = CURVE_CRVUSD_USDC;
        uint48[2][] memory tokenIndexes = new uint48[2][](1);
        tokenIndexes[0][0] = 0;
        tokenIndexes[0][1] = 0;

        assertTrue(address(0) != registry.poolTokens(pool, tokenIndexes[0][0]));
        assertTrue(address(0) != registry.poolTokens(pool, tokenIndexes[0][0]));

        vm.prank(msgSender);
        vm.expectRevert(PoolRegistry.PoolTokensIdentical.selector);

        registry.addExchangePath(tokenPair, pools, tokenIndexes);
    }

    function testAddExchangePath() external {
        address[] memory pools = new address[](2);
        pools[0] = CURVE_CRVUSD_USDC;
        pools[1] = UNISWAP_USDC_ETH;
        IStandardPool[] memory poolInterfaces = new IStandardPool[](2);
        poolInterfaces[0] = curveStableSwap;
        poolInterfaces[1] = uniswapV3Fee500;

        registry.addPools(pools, poolInterfaces);

        uint48[2][] memory tokenIndexes = new uint48[2][](2);
        tokenIndexes[0][0] = 1;
        tokenIndexes[0][1] = 0;

        assertEq(CRVUSD, registry.poolTokens(pools[0], tokenIndexes[0][0]));
        assertEq(USDC, registry.poolTokens(pools[0], tokenIndexes[0][1]));

        tokenIndexes[1][0] = 0;
        tokenIndexes[1][1] = 1;

        assertEq(USDC, registry.poolTokens(pools[1], tokenIndexes[1][0]));
        assertEq(WETH, registry.poolTokens(pools[1], tokenIndexes[1][1]));

        address msgSender = registry.owner();
        bytes32 tokenPair = _hashTokenPair(CRVUSD, WETH);

        vm.prank(msgSender);
        vm.expectEmit(true, false, false, true, address(registry));

        emit AddExchangePath(tokenPair);

        registry.addExchangePath(tokenPair, pools, tokenIndexes);

        (
            uint256 nextIndex,
            address[][] memory _pools,
            uint256[2][] memory _tokenIndexes
        ) = registry.getExchangePaths(tokenPair);
        uint256 addedIndex = nextIndex - 1;

        for (uint256 i = 0; i < _pools.length; ++i) {
            assertEq(pools[i], _pools[addedIndex][i]);
            assertTrue(
                address(0) !=
                    registry.poolTokens(pools[i], _tokenIndexes[addedIndex][i])
            );
            assertTrue(
                address(0) !=
                    registry.poolTokens(pools[i], _tokenIndexes[addedIndex][i])
            );
        }
    }
}
