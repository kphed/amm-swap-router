// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Clone} from "solady/utils/Clone.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IPath} from "src/paths/IPath.sol";

interface IUniswapV3 {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function quote(
        address poolAddress,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) external view returns (int256 amount0, int256 amount1);

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

contract UniswapV3 is Clone, IPath {
    using SafeTransferLib for address;

    uint256 private constant _OFFSET_POOL = 0;
    uint256 private constant _OFFSET_INPUT_TOKEN = 20;
    uint256 private constant _OFFSET_OUTPUT_TOKEN = 40;
    uint256 private constant _OFFSET_ZERO_FOR_ONE = 60;
    uint256 private constant _OFFSET_ZERO_FOR_ONE_LENGTH = 32;
    uint256 private constant _OFFSET_SQRT_PRICE_LIMIT = 92;

    // keccak256(abi.encodePacked(true)).
    bytes32 private constant _TRUE =
        0x5fe7f977e71dba2ea1a68e21057beebb9be2ac30c6410aa38d4f3fbe41dcffd2;

    IUniswapV3 private constant _QUOTER =
        IUniswapV3(0xc80f61d1bdAbD8f5285117e1558fDDf8C64870FE);

    error UnauthorizedCaller();

    function _pool() private pure returns (address) {
        return _getArgAddress(_OFFSET_POOL);
    }

    function _inputToken() private pure returns (address) {
        return _getArgAddress(_OFFSET_INPUT_TOKEN);
    }

    function _outputToken() private pure returns (address) {
        return _getArgAddress(_OFFSET_OUTPUT_TOKEN);
    }

    function _zeroForOne() private pure returns (bool) {
        return
            bytes32(
                _getArgBytes(_OFFSET_ZERO_FOR_ONE, _OFFSET_ZERO_FOR_ONE_LENGTH)
            ) == _TRUE
                ? true
                : false;
    }

    function _sqrtPriceLimit() private pure returns (uint160) {
        return _getArgUint160(_OFFSET_SQRT_PRICE_LIMIT);
    }

    function _encodeSwapData() private view returns (bytes memory) {
        return abi.encode(msg.sender, _getArgAddress(_OFFSET_INPUT_TOKEN));
    }

    function pool() external pure returns (address) {
        return _getArgAddress(_OFFSET_POOL);
    }

    function tokens() external pure returns (address, address) {
        return (_inputToken(), _outputToken());
    }

    function quoteTokenOutput(uint256 amount) external view returns (uint256) {
        bool zeroForOne = _zeroForOne();
        (int256 amount0, int256 amount1) = _QUOTER.quote(
            _pool(),
            zeroForOne,
            int256(amount),
            _sqrtPriceLimit()
        );

        return uint256(zeroForOne ? -amount1 : -amount0);
    }

    function quoteTokenInput(uint256 amount) external view returns (uint256) {
        bool zeroForOne = _zeroForOne();
        (int256 amount0, int256 amount1) = _QUOTER.quote(
            _pool(),
            zeroForOne,
            -int256(amount),
            _sqrtPriceLimit()
        );

        return uint256(zeroForOne ? amount0 : amount1);
    }

    function swap(uint256 amount) external returns (uint256) {
        bool zeroForOne = _zeroForOne();
        (int256 amount0, int256 amount1) = IUniswapV3(_pool()).swap(
            msg.sender,
            zeroForOne,
            int256(amount),
            _sqrtPriceLimit(),
            _encodeSwapData()
        );

        return zeroForOne ? uint256(-amount1) : uint256(-amount0);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        if (msg.sender != _pool()) revert UnauthorizedCaller();

        (address payer, address inputToken) = abi.decode(
            data,
            (address, address)
        );

        if (amount0Delta > 0) {
            inputToken.safeTransferFrom(
                payer,
                msg.sender,
                uint256(amount0Delta)
            );
        } else if (amount1Delta > 0) {
            inputToken.safeTransferFrom(
                payer,
                msg.sender,
                uint256(amount1Delta)
            );
        }
    }
}
