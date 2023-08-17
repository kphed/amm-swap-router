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

    mapping(address token => int128 index) public coins;

    constructor(ICurveStableSwap _pool, uint256 coinsCount) {
        pool = _pool;

        for (uint256 i = 0; i < coinsCount; ) {
            coins[pool.coins(i)] = int256(i).toInt128();

            unchecked {
                ++i;
            }
        }
    }

    function quoteTokenOutput(
        address inputToken,
        address outputToken,
        uint256 inputTokenAmount
    ) external view returns (uint256) {
        return
            ICurveStableSwap(pool).get_dy(
                coins[inputToken],
                coins[outputToken],
                inputTokenAmount
            );
    }

    function quoteTokenInput(
        address inputToken,
        address outputToken,
        uint256 outputTokenAmount
    ) external view returns (uint256) {
        return
            ICurveStableSwap(pool).get_dx(
                coins[inputToken],
                coins[outputToken],
                outputTokenAmount
            );
    }

    function swap(
        address inputToken,
        address outputToken,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount
    ) external returns (uint256) {
        return
            ICurveStableSwap(pool).exchange(
                coins[inputToken],
                coins[outputToken],
                inputTokenAmount,
                minOutputTokenAmount,
                address(this)
            );
    }
}
