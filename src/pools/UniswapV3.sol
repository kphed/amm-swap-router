// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IUniswapV3 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    struct QuoteExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amount;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function token0() external view returns (address);

    function token1() external view returns (address);

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params) external view returns (uint256);

    function quoteExactOutputSingle(QuoteExactOutputSingleParams memory params)
        external
        returns (uint256, uint160, uint32, uint256);
}

contract UniswapV3Fee500 {
    IUniswapV3 private constant QUOTER = IUniswapV3(0xc80f61d1bdAbD8f5285117e1558fDDf8C64870FE);
    IUniswapV3 private constant QUOTER_V2 = IUniswapV3(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);

    uint24 private constant FEE = 500;

    function tokens(address pool) external view returns (address[] memory _tokens) {
        IUniswapV3 _pool = IUniswapV3(pool);

        _tokens = new address[](2);
        _tokens[0] = _pool.token0();
        _tokens[1] = _pool.token1();
    }

    function quoteTokenOutput(address pool, uint256 inputTokenIndex, uint256 outputTokenIndex, uint256 inputTokenAmount)
        external
        view
        returns (uint256)
    {
        address token0 = IUniswapV3(pool).token0();
        address token1 = IUniswapV3(pool).token1();

        return QUOTER.quoteExactInputSingle(
            IUniswapV3.QuoteExactInputSingleParams({
                tokenIn: inputTokenIndex == 0 ? token0 : token1,
                tokenOut: outputTokenIndex == 1 ? token1 : token0,
                amountIn: inputTokenAmount,
                fee: FEE,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function quoteTokenInput(address pool, uint256 inputTokenIndex, uint256 outputTokenIndex, uint256 outputTokenAmount)
        external
        view
        returns (uint256 inputTokenAmount)
    {}

    function swap(
        address pool,
        uint256 inputTokenIndex,
        uint256 outputTokenIndex,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount
    ) external returns (uint256) {}
}
