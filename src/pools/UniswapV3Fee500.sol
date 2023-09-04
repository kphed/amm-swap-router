// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

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

contract UniswapV3Fee500 {
    IUniswapV3 private constant QUOTER =
        IUniswapV3(0xc80f61d1bdAbD8f5285117e1558fDDf8C64870FE);
    uint160 private constant MIN_SQRT_RATIO = 4295128740;
    uint160 private constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970341;
    uint24 private constant FEE = 500;

    function _encodeInputToken(
        address pool,
        uint256 inputTokenIndex
    ) internal view returns (bytes memory) {
        address token0 = IUniswapV3(pool).token0();
        address token1 = IUniswapV3(pool).token1();

        return abi.encode(inputTokenIndex == 0 ? token0 : token1);
    }

    function tokens(
        address pool
    ) external view returns (address[] memory _tokens) {
        IUniswapV3 _pool = IUniswapV3(pool);
        _tokens = new address[](2);
        _tokens[0] = _pool.token0();
        _tokens[1] = _pool.token1();
    }

    function quoteTokenOutput(
        address pool,
        uint256 inputTokenIndex,
        uint256,
        uint256 inputTokenAmount
    ) external view returns (uint256) {
        bool zeroForOne = inputTokenIndex == 0 ? true : false;
        (int256 amount0, int256 amount1) = QUOTER.quote(
            pool,
            inputTokenIndex == 0 ? true : false,
            int256(inputTokenAmount),
            zeroForOne ? MIN_SQRT_RATIO : MAX_SQRT_RATIO
        );

        return uint256(zeroForOne ? -amount1 : -amount0);
    }

    function quoteTokenInput(
        address pool,
        uint256 inputTokenIndex,
        uint256,
        uint256 outputTokenAmount
    ) external view returns (uint256) {
        bool zeroForOne = inputTokenIndex == 0 ? true : false;
        (int256 amount0, int256 amount1) = QUOTER.quote(
            pool,
            zeroForOne,
            -int256(outputTokenAmount),
            zeroForOne ? MIN_SQRT_RATIO : MAX_SQRT_RATIO
        );

        return uint256(zeroForOne ? amount0 : amount1);
    }

    function swap(
        address pool,
        uint256 inputTokenIndex,
        uint256,
        uint256 inputTokenAmount
    ) external returns (uint256) {
        bool zeroForOne = inputTokenIndex == 0 ? true : false;
        (int256 amount0, int256 amount1) = IUniswapV3(pool).swap(
            address(this),
            zeroForOne,
            int256(inputTokenAmount),
            zeroForOne ? MIN_SQRT_RATIO : MAX_SQRT_RATIO,
            _encodeInputToken(pool, inputTokenIndex)
        );

        return zeroForOne ? uint256(-amount1) : uint256(-amount0);
    }
}
