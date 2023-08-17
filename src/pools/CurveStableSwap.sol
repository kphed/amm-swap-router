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
}

contract CurveStableSwap {
    using SafeCastLib for int256;

    function quoteTokenOutput(
        address pool,
        uint256 inputToken,
        uint256 outputToken,
        uint256 inputTokenAmount
    ) external view returns (uint256) {
        return
            ICurveStableSwap(pool).get_dy(
                int256(inputToken).toInt128(),
                int256(outputToken).toInt128(),
                inputTokenAmount
            );
    }

    function quoteTokenInput(
        address pool,
        uint256 inputToken,
        uint256 outputToken,
        uint256 outputTokenAmount
    ) external view returns (uint256) {
        return
            ICurveStableSwap(pool).get_dx(
                int256(inputToken).toInt128(),
                int256(outputToken).toInt128(),
                outputTokenAmount
            );
    }

    function swap(
        address pool,
        uint256 inputToken,
        uint256 outputToken,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount
    ) external returns (uint256) {
        return
            ICurveStableSwap(pool).exchange(
                int256(inputToken).toInt128(),
                int256(outputToken).toInt128(),
                inputTokenAmount,
                minOutputTokenAmount,
                address(this)
            );
    }
}
