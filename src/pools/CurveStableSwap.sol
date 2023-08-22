// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

interface ICurveStableSwap {
    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256 dy);

    function get_dx(
        int128 i,
        int128 j,
        uint256 dy
    ) external view returns (uint256 dx);

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 minDy,
        address receiver
    ) external returns (uint256);

    function coins(uint256 index) external view returns (address);
}

contract CurveStableSwap {
    using SafeCastLib for int256;

    ICurveStableSwap public immutable pool;

    address[] private _tokens;

    // Token addresses to their indexes for easy lookups.
    mapping(address token => uint256 index) public tokenIndexes;

    constructor(address _pool, uint256 coinsCount) {
        pool = ICurveStableSwap(_pool);
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
        return
            ICurveStableSwap(pool).get_dy(
                int256(inputTokenIndex).toInt128(),
                int256(outputTokenIndex).toInt128(),
                inputTokenAmount
            );
    }

    function quoteTokenInput(
        uint256 inputTokenIndex,
        uint256 outputTokenIndex,
        uint256 outputTokenAmount
    ) external view returns (uint256) {
        return
            ICurveStableSwap(pool).get_dx(
                int256(inputTokenIndex).toInt128(),
                int256(outputTokenIndex).toInt128(),
                outputTokenAmount
            );
    }

    function swap(
        uint256 inputTokenIndex,
        uint256 outputTokenIndex,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount
    ) external returns (uint256) {
        return
            ICurveStableSwap(pool).exchange(
                int256(inputTokenIndex).toInt128(),
                int256(outputTokenIndex).toInt128(),
                inputTokenAmount,
                minOutputTokenAmount,
                address(this)
            );
    }
}
