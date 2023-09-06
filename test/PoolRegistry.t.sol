// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PoolRegistry} from "src/PoolRegistry.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";
import {UniswapV3Factory} from "src/pools/UniswapV3Factory.sol";
import {CurveStableSwapFactory} from "src/pools/CurveStableSwapFactory.sol";

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
    UniswapV3Factory uniswapV3Factory = new UniswapV3Factory();
    CurveStableSwapFactory curveStableSwapFactory =
        new CurveStableSwapFactory();
    PoolRegistry public immutable registry = new PoolRegistry(address(this));

    event WithdrawERC20(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );
    event AddExchangePath(bytes32 indexed tokenPair, uint256 indexed addIndex);
    event RemoveExchangePath(
        bytes32 indexed tokenPair,
        uint256 indexed removeIndex
    );
    event ApprovePool(
        IStandardPool indexed poolInterface,
        address indexed pool,
        address[] tokens
    );

    receive() external payable {}

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
        bytes32 crvUSDETH = _hashTokenPair(CRVUSD, WETH);
        address[] memory interfaces = new address[](2);
        interfaces[0] = curveStableSwapFactory.create(CURVE_CRVUSD_USDC, 1, 0);
        interfaces[1] = uniswapV3Factory.create(UNISWAP_USDC_ETH, USDC, true);

        registry.addExchangePath(crvUSDETH, interfaces);

        interfaces[0] = curveStableSwapFactory.create(CURVE_CRVUSD_USDT, 0, 1);
        interfaces[1] = uniswapV3Factory.create(UNISWAP_USDT_ETH, USDT, false);

        registry.addExchangePath(crvUSDETH, interfaces);
    }

    /*//////////////////////////////////////////////////////////////
                             withdrawERC20
    //////////////////////////////////////////////////////////////*/

    function testCannotWithdrawERC20Unauthorized() external {
        address unauthorizedMsgSender = address(1);
        address token = CRVUSD;
        address recipient = address(this);
        uint256 amount = 1e18;

        assertTrue(unauthorizedMsgSender != registry.owner());

        vm.prank(unauthorizedMsgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        registry.withdrawERC20(token, recipient, amount);
    }

    function testWithdrawERC20() external {
        address msgSender = registry.owner();
        address token = CRVUSD;
        address recipient = address(this);
        uint256 amount = 1e18;

        _mintCRVUSD(address(registry), amount);

        assertEq(0, CRVUSD.balanceOf(address(this)));
        assertEq(amount, CRVUSD.balanceOf(address(registry)));

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(registry));

        emit WithdrawERC20(token, recipient, amount);

        registry.withdrawERC20(token, recipient, amount);

        assertEq(amount, CRVUSD.balanceOf(address(this)));
        assertEq(0, CRVUSD.balanceOf(address(registry)));
    }

    /*//////////////////////////////////////////////////////////////
                             approvePool
    //////////////////////////////////////////////////////////////*/

    function testApprovePool() external {
        _setUpPools();

        address pool = CURVE_CRVUSD_USDC;
        bytes32 tokenPair = _hashTokenPair(CRVUSD, WETH);
        IStandardPool poolInterface = IStandardPool(
            registry.getExchangePaths(tokenPair)[0][0]
        );

        assertEq(pool, poolInterface.pool());

        address[] memory tokens = poolInterface.tokens();

        vm.startPrank(address(registry));

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(
                type(uint256).max,
                ERC20(tokens[i]).allowance(address(registry), pool)
            );

            // Set the registry's allowances to zero for the pool's tokens.
            tokens[i].safeApproveWithRetry(pool, 0);

            assertEq(0, ERC20(tokens[i]).allowance(address(registry), pool));
        }

        vm.stopPrank();

        address msgSender = address(this);

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(registry));

        emit ApprovePool(poolInterface, pool, tokens);

        registry.approvePool(poolInterface);

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(
                type(uint256).max,
                ERC20(tokens[i]).allowance(address(registry), pool)
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                             addExchangePath
    //////////////////////////////////////////////////////////////*/

    function testCannotAddExchangePathUnauthorized() external {
        address unauthorizedMsgSender = address(1);
        bytes32 tokenPair = _hashTokenPair(CRVUSD, WETH);
        address[] memory interfaces = new address[](2);

        assertTrue(unauthorizedMsgSender != registry.owner());

        vm.prank(unauthorizedMsgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        registry.addExchangePath(tokenPair, interfaces);
    }

    function testCannotAddExchangePathInvalidTokenPair() external {
        address msgSender = registry.owner();
        bytes32 invalidTokenPair = bytes32(0);
        address[] memory interfaces = new address[](2);

        assertEq(bytes32(0), invalidTokenPair);

        vm.prank(msgSender);
        vm.expectRevert(PoolRegistry.InvalidTokenPair.selector);

        registry.addExchangePath(invalidTokenPair, interfaces);
    }

    function testCannotAddExchangePathEmptyArray() external {
        address msgSender = registry.owner();
        bytes32 tokenPair = _hashTokenPair(CRVUSD, WETH);
        address[] memory emptyInterfaces = new address[](0);

        assertEq(0, emptyInterfaces.length);

        vm.prank(msgSender);
        vm.expectRevert(PoolRegistry.EmptyArray.selector);

        registry.addExchangePath(tokenPair, emptyInterfaces);
    }

    function testAddExchangePath() external {
        address msgSender = registry.owner();
        bytes32 tokenPair = _hashTokenPair(CRVUSD, WETH);
        address[] memory interfaces = new address[](2);
        interfaces[0] = curveStableSwapFactory.create(CURVE_CRVUSD_USDC, 1, 0);
        interfaces[1] = uniswapV3Factory.create(UNISWAP_USDC_ETH, USDC, true);
        uint256 addIndex = registry.getExchangePaths(tokenPair).length;
        address[] memory curveCRVUSDUSDCTokens = IStandardPool(interfaces[0])
            .tokens();
        address[] memory uniswapUSDCETH = IStandardPool(interfaces[1]).tokens();

        assertEq(0, addIndex);
        assertEq(0, registry.pools(CURVE_CRVUSD_USDC));
        assertEq(0, registry.pools(UNISWAP_USDC_ETH));

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(registry));

        emit AddExchangePath(tokenPair, addIndex);

        registry.addExchangePath(tokenPair, interfaces);

        address[][] memory exchangePaths = registry.getExchangePaths(tokenPair);

        assertEq(1, exchangePaths.length);
        assertEq(
            curveCRVUSDUSDCTokens.length,
            registry.pools(CURVE_CRVUSD_USDC)
        );
        assertEq(uniswapUSDCETH.length, registry.pools(UNISWAP_USDC_ETH));

        address[] memory _interfaces = exchangePaths[addIndex];

        assertEq(interfaces.length, _interfaces.length);

        for (uint256 i = 0; i < interfaces.length; ++i) {
            assertEq(interfaces[i], _interfaces[i]);
        }

        for (uint256 i = 0; i < curveCRVUSDUSDCTokens.length; ++i) {
            assertEq(
                type(uint256).max,
                ERC20(curveCRVUSDUSDCTokens[i]).allowance(
                    address(registry),
                    CURVE_CRVUSD_USDC
                )
            );
        }

        for (uint256 i = 0; i < uniswapUSDCETH.length; ++i) {
            assertEq(
                type(uint256).max,
                ERC20(uniswapUSDCETH[i]).allowance(
                    address(registry),
                    UNISWAP_USDC_ETH
                )
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                             removeExchangePath
    //////////////////////////////////////////////////////////////*/

    function testCannotRemoveExchangePathUnauthorized() external {
        address unauthorizedMsgSender = address(1);
        bytes32 tokenPair = _hashTokenPair(CRVUSD, WETH);
        uint256 removeIndex = 0;

        assertTrue(unauthorizedMsgSender != registry.owner());

        vm.prank(unauthorizedMsgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        registry.removeExchangePath(tokenPair, removeIndex);
    }

    function testCannotRemoveExchangePathInvalidTokenPair() external {
        address msgSender = registry.owner();
        bytes32 invalidTokenPair = bytes32(0);
        uint256 removeIndex = 0;

        vm.prank(msgSender);
        vm.expectRevert(PoolRegistry.InvalidTokenPair.selector);

        registry.removeExchangePath(invalidTokenPair, removeIndex);
    }

    function testCannotRemoveExchangePathRemovalIndex() external {
        _setUpPools();

        address msgSender = registry.owner();
        bytes32 tokenPair = _hashTokenPair(CRVUSD, WETH);
        address[][] memory exchangePaths = registry.getExchangePaths(tokenPair);
        uint256 invalidRemoveIndex = exchangePaths.length + 1;

        assertGt(invalidRemoveIndex, exchangePaths.length);

        vm.prank(msgSender);
        vm.expectRevert(PoolRegistry.RemoveIndexOOB.selector);

        registry.removeExchangePath(tokenPair, invalidRemoveIndex);
    }

    function testRemoveExchangePath() external {
        _setUpPools();

        address msgSender = registry.owner();
        bytes32 tokenPair = _hashTokenPair(CRVUSD, WETH);
        address[][] memory exchangePaths = registry.getExchangePaths(tokenPair);
        uint256 removeIndex = 0;
        uint256 lastIndex = exchangePaths.length - 1;
        address[] memory lastExchangePath = exchangePaths[lastIndex];

        assertTrue(removeIndex != lastIndex);
        assertEq(2, exchangePaths.length);

        for (uint256 i = 0; i < exchangePaths.length; ++i) {
            assertTrue(exchangePaths[removeIndex][i] != lastExchangePath[i]);
        }

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(registry));

        emit RemoveExchangePath(tokenPair, removeIndex);

        registry.removeExchangePath(tokenPair, removeIndex);

        exchangePaths = registry.getExchangePaths(tokenPair);

        assertEq(1, exchangePaths.length);

        for (uint256 i = 0; i < exchangePaths.length; ++i) {
            // The last exchange path now has the same index as the removed index.
            assertEq(exchangePaths[removeIndex][i], lastExchangePath[i]);
        }
    }

    function testRemoveExchangePathLastIndex() external {
        _setUpPools();

        address msgSender = registry.owner();
        bytes32 tokenPair = _hashTokenPair(CRVUSD, WETH);
        address[][] memory exchangePaths = registry.getExchangePaths(tokenPair);
        uint256 lastIndex = exchangePaths.length - 1;
        uint256 removeIndex = lastIndex;
        address[] memory lastExchangePath = exchangePaths[lastIndex];

        assertEq(2, exchangePaths.length);

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(registry));

        emit RemoveExchangePath(tokenPair, removeIndex);

        registry.removeExchangePath(tokenPair, removeIndex);

        exchangePaths = registry.getExchangePaths(tokenPair);
        lastIndex = exchangePaths.length - 1;

        assertEq(1, exchangePaths.length);

        for (uint256 i = 0; i < lastExchangePath.length; ++i) {
            // The old last exchange path and the current last exchange path should not be equal.
            assertTrue(lastExchangePath[i] != exchangePaths[lastIndex][i]);
        }
    }
}
