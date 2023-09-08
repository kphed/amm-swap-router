// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {PathRegistry} from "src/PathRegistry.sol";
import {IPath} from "src/paths/IPath.sol";
import {UniswapV3Factory} from "src/paths/UniswapV3Factory.sol";
import {CurveStableSwapFactory} from "src/paths/CurveStableSwapFactory.sol";

interface ICurveStablecoin {
    function mint(address to, uint256 amount) external;
}

contract PathRegistryTest is Test {
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
    PathRegistry public immutable registry = new PathRegistry(address(this));

    event WithdrawERC20(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );
    event AddPath(bytes32 indexed pair, uint256 indexed index);
    event ApprovePath(IPath indexed path, address[] tokens);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    receive() external payable {}

    function _hashPair(
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
        bytes32 crvUSDETH = _hashPair(CRVUSD, WETH);
        IPath[] memory interfaces = new IPath[](2);
        interfaces[0] = IPath(
            curveStableSwapFactory.create(CURVE_CRVUSD_USDC, 1, 0)
        );
        interfaces[1] = IPath(
            uniswapV3Factory.create(UNISWAP_USDC_ETH, USDC, true)
        );

        registry.addPath(crvUSDETH, interfaces);

        interfaces[0] = IPath(
            curveStableSwapFactory.create(CURVE_CRVUSD_USDT, 0, 1)
        );
        interfaces[1] = IPath(
            uniswapV3Factory.create(UNISWAP_USDT_ETH, USDT, false)
        );

        registry.addPath(crvUSDETH, interfaces);
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
                             approvePath
    //////////////////////////////////////////////////////////////*/

    function testApprovePath() external {
        _setUpPools();

        bytes32 pair = _hashPair(CRVUSD, WETH);
        uint256 outerPathIndex = 0;
        uint256 innerPathIndex = 0;
        IPath path = IPath(
            registry.getPaths(pair)[outerPathIndex][innerPathIndex]
        );
        address[] memory tokens = path.tokens();

        vm.startPrank(address(registry));

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(
                type(uint256).max,
                ERC20(tokens[i]).allowance(address(registry), address(path))
            );

            // Set the registry's allowances to zero for the pool's tokens.
            tokens[i].safeApproveWithRetry(address(path), 0);

            assertEq(
                0,
                ERC20(tokens[i]).allowance(address(registry), address(path))
            );
        }

        vm.stopPrank();

        address msgSender = address(this);

        vm.prank(msgSender);
        vm.expectEmit(true, false, false, true, address(registry));

        emit ApprovePath(path, tokens);

        registry.approvePath(pair, outerPathIndex, innerPathIndex);

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(
                type(uint256).max,
                ERC20(tokens[i]).allowance(address(registry), address(path))
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                             addPath
    //////////////////////////////////////////////////////////////*/

    function testCannotAddPathUnauthorized() external {
        address unauthorizedMsgSender = address(1);
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[] memory interfaces = new IPath[](2);

        assertTrue(unauthorizedMsgSender != registry.owner());

        vm.prank(unauthorizedMsgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        registry.addPath(pair, interfaces);
    }

    function testCannotAddPathInvalidPair() external {
        address msgSender = registry.owner();
        bytes32 invalidTokenPair = bytes32(0);
        IPath[] memory interfaces = new IPath[](2);

        assertEq(bytes32(0), invalidTokenPair);

        vm.prank(msgSender);
        vm.expectRevert(PathRegistry.InvalidPair.selector);

        registry.addPath(invalidTokenPair, interfaces);
    }

    function testCannotAddPathEmptyArray() external {
        address msgSender = registry.owner();
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[] memory emptyInterfaces = new IPath[](0);

        assertEq(0, emptyInterfaces.length);

        vm.prank(msgSender);
        vm.expectRevert(PathRegistry.EmptyArray.selector);

        registry.addPath(pair, emptyInterfaces);
    }

    function testAddPath() external {
        address msgSender = registry.owner();
        bytes32 pair = _hashPair(CRVUSD, WETH);
        IPath[] memory interfaces = new IPath[](2);
        interfaces[0] = IPath(
            curveStableSwapFactory.create(CURVE_CRVUSD_USDC, 1, 0)
        );
        interfaces[1] = IPath(
            uniswapV3Factory.create(UNISWAP_USDC_ETH, USDC, true)
        );
        uint256 addIndex = registry.getPaths(pair).length;
        address[] memory curveCRVUSDUSDCTokens = IPath(interfaces[0]).tokens();
        address[] memory uniswapUSDCETH = IPath(interfaces[1]).tokens();

        assertEq(0, addIndex);

        vm.prank(msgSender);
        vm.expectEmit(true, true, false, true, address(registry));

        emit AddPath(pair, addIndex);

        registry.addPath(pair, interfaces);

        IPath[][] memory exchangePaths = registry.getPaths(pair);

        assertEq(1, exchangePaths.length);

        IPath[] memory _interfaces = exchangePaths[addIndex];

        assertEq(interfaces.length, _interfaces.length);

        for (uint256 i = 0; i < interfaces.length; ++i) {
            assertEq(address(interfaces[i]), address(_interfaces[i]));
        }

        for (uint256 i = 0; i < curveCRVUSDUSDCTokens.length; ++i) {
            assertEq(
                type(uint256).max,
                ERC20(curveCRVUSDUSDCTokens[i]).allowance(
                    address(registry),
                    address(interfaces[0])
                )
            );
        }

        for (uint256 i = 0; i < uniswapUSDCETH.length; ++i) {
            assertEq(
                type(uint256).max,
                ERC20(uniswapUSDCETH[i]).allowance(
                    address(registry),
                    address(interfaces[1])
                )
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                             getSwapOutput
    //////////////////////////////////////////////////////////////*/

    function testCannotGetSwapOutputZeroInput() external {
        _setUpPools();

        bytes32 pair = _hashPair(CRVUSD, WETH);
        uint256 zeroInput = 0;

        vm.expectRevert();

        registry.getSwapOutput(pair, zeroInput);
    }

    function testGetSwapOutputInvalidPair() external {
        _setUpPools();

        bytes32 invalidPair = bytes32(0);
        uint256 input = 1e18;

        // Does not revert, just doesn't do anything.
        (uint256 index, uint256 output) = registry.getSwapOutput(
            invalidPair,
            input
        );

        assertEq(0, index);
        assertEq(0, output);
    }
}
