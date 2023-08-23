// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {Solarray} from "solarray/Solarray.sol";

interface ICurveStableSwap {
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256 dy);

    function get_dx(int128 i, int128 j, uint256 dy) external view returns (uint256 dx);

    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy, address receiver) external returns (uint256);

    function coins(uint256 index) external view returns (address);
}

contract CurveStableSwap {
    using SafeCastLib for int256;
    using Solarray for address[];

    function tokens(address pool) external view returns (address[] memory _tokens) {
        uint256 index = 0;
        ICurveStableSwap _pool = ICurveStableSwap(pool);

        while (true) {
            try _pool.coins(index) returns (address token) {
                _tokens = _tokens.append(token);

                unchecked {
                    ++index;
                }
            } catch {
                return _tokens;
            }
        }
    }

    function quoteTokenOutput(address pool, uint256 inputTokenIndex, uint256 outputTokenIndex, uint256 inputTokenAmount)
        external
        view
        returns (uint256)
    {
        return ICurveStableSwap(pool).get_dy(
            int256(inputTokenIndex).toInt128(), int256(outputTokenIndex).toInt128(), inputTokenAmount
        );
    }

    function quoteTokenInput(address pool, uint256 inputTokenIndex, uint256 outputTokenIndex, uint256 outputTokenAmount)
        external
        view
        returns (uint256)
    {
        return ICurveStableSwap(pool).get_dx(
            int256(inputTokenIndex).toInt128(), int256(outputTokenIndex).toInt128(), outputTokenAmount
        );
    }

    function swap(
        address pool,
        uint256 inputTokenIndex,
        uint256 outputTokenIndex,
        uint256 inputTokenAmount,
        uint256 minOutputTokenAmount
    ) external returns (uint256) {
        return ICurveStableSwap(pool).exchange(
            int256(inputTokenIndex).toInt128(),
            int256(outputTokenIndex).toInt128(),
            inputTokenAmount,
            minOutputTokenAmount,
            address(this)
        );
    }
}
