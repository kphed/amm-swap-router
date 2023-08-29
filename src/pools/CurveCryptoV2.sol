// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Solarray} from "solarray/Solarray.sol";

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
    using SafeTransferLib for address;
    using Solarray for address[];

    function tokens(
        address pool
    ) external view returns (address[] memory _tokens) {
        uint256 index = 0;
        ICurveCryptoV2 _pool = ICurveCryptoV2(pool);

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

    function quoteTokenOutput(
        address pool,
        uint256 inputTokenIndex,
        uint256 outputTokenIndex,
        uint256 inputTokenAmount
    ) external view returns (uint256) {
        return
            ICurveCryptoV2(pool).get_dy(
                inputTokenIndex,
                outputTokenIndex,
                inputTokenAmount
            );
    }

    function quoteTokenInput(
        address pool,
        uint256 inputTokenIndex,
        uint256 outputTokenIndex,
        uint256 outputTokenAmount
    ) external view returns (uint256) {
        return
            ICurveCryptoV2(pool).get_dx(
                inputTokenIndex,
                outputTokenIndex,
                outputTokenAmount
            );
    }

    function swap(
        address pool,
        uint256 inputTokenIndex,
        uint256 outputTokenIndex,
        uint256 inputTokenAmount
    ) external returns (uint256) {
        ICurveCryptoV2 _pool = ICurveCryptoV2(pool);

        _pool.coins(inputTokenIndex).safeApprove(pool, inputTokenAmount);

        return
            _pool.exchange(
                inputTokenIndex,
                outputTokenIndex,
                inputTokenAmount,
                1,
                false,
                msg.sender
            );
    }
}
