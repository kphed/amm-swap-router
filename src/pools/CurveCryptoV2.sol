// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface ICurveCryptoV2 {
    function get_dy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256 dy);

    function get_dx(
        uint256 i,
        uint256 j,
        uint256 dy
    ) external view returns (uint256 dx);

    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 minDy,
        bool useEth,
        address receiver
    ) external returns (uint256);

    function coins(uint256 index) external view returns (address);
}

contract CurveCryptoV2 {
    ICurveCryptoV2 public immutable pool;

    address[] private _tokens;

    // Token addresses to their indexes for easy lookups.
    mapping(address token => uint256 index) public tokenIndexes;

    constructor(address _pool, uint256 coinsCount) {
        pool = ICurveCryptoV2(_pool);
        address token;

        for (uint256 i = 0; i < coinsCount; ) {
            token = pool.coins(i);
            tokenIndexes[token] = i;

            _tokens.push(token);

            unchecked {
                ++i;
            }
        }
    }

    function tokens() external view returns (address[] memory) {
        return _tokens;
    }

    function quoteTokenOutput(
        uint256 inputTokenIndex,
        uint256 outputTokenIndex,
        uint256 inputTokenAmount
    ) external view returns (uint256) {
        return pool.get_dy(inputTokenIndex, outputTokenIndex, inputTokenAmount);
    }

    function quoteTokenInput(
        uint256 inputTokenIndex,
        uint256 outputTokenIndex,
        uint256 outputTokenAmount
    ) external view returns (uint256) {
        return
            pool.get_dx(inputTokenIndex, outputTokenIndex, outputTokenAmount);
    }

    function swap(
        uint256 inputTokenIndex,
        uint256 outputTokenIndex,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount
    ) external returns (uint256) {
        return
            pool.exchange(
                inputTokenIndex,
                outputTokenIndex,
                inputTokenAmount,
                minOutputTokenAmount,
                false,
                address(this)
            );
    }
}
