// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
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
        address[] memory pools = new address[](2);
        pools[0] = curveStableSwapFactory.create(CURVE_CRVUSD_USDC, 1, 0);
        pools[1] = uniswapV3Factory.create(UNISWAP_USDC_ETH, USDC, true);

        registry.addExchangePath(crvUSDETH, pools);
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
            IStandardPool(interfaces[0]).tokens().length,
            registry.pools(CURVE_CRVUSD_USDC)
        );
        assertEq(
            IStandardPool(interfaces[1]).tokens().length,
            registry.pools(UNISWAP_USDC_ETH)
        );

        address[] memory _interfaces = exchangePaths[addIndex];

        assertEq(interfaces.length, _interfaces.length);

        for (uint256 i = 0; i < interfaces.length; ++i) {
            assertEq(interfaces[i], _interfaces[i]);
        }
    }
}
