// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

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
}

contract CurveStableSwap {
    function quoteTokenOutput(
        address pool,
        uint256 inputToken,
        uint256 outputToken,
        uint256 inputTokenAmount
    ) external view returns (uint256) {
        return
            ICurveCryptoV2(pool).get_dy(
                inputToken,
                outputToken,
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
            ICurveCryptoV2(pool).get_dx(
                inputToken,
                outputToken,
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
            ICurveCryptoV2(pool).exchange(
                inputToken,
                outputToken,
                inputTokenAmount,
                minOutputTokenAmount,
                false,
                address(this)
            );
    }
}
