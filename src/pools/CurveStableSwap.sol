// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Clone} from "solady/utils/Clone.sol";
import {IStandardPool} from "src/pools/IStandardPool.sol";

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

contract CurveStableSwap is Clone, IStandardPool {
    uint256 private constant _OFFSET_POOL = 0;
    uint256 private constant _OFFSET_INPUT_TOKEN_INDEX = 20;
    uint256 private constant _OFFSET_OUTPUT_TOKEN_INDEX = 26;

    // Slippage should be handled by the caller.
    uint256 private constant _MIN_SWAP_AMOUNT = 1;

    bool private _initialized = false;
    address[] private _tokens;

    error AlreadyInitialized();

    function _pool() private pure returns (ICurveStableSwap) {
        return ICurveStableSwap(_getArgAddress(_OFFSET_POOL));
    }

    function _inputTokenIndex() private pure returns (int48) {
        return int48(_getArgUint48(_OFFSET_INPUT_TOKEN_INDEX));
    }

    function _outputTokenIndex() private pure returns (int48) {
        return int48(_getArgUint48(_OFFSET_OUTPUT_TOKEN_INDEX));
    }

    function initialize() external {
        if (_initialized) revert AlreadyInitialized();

        _initialized = true;
        uint256 index = 0;
        ICurveStableSwap curveStableSwapPool = ICurveStableSwap(_pool());

        while (true) {
            try curveStableSwapPool.coins(index) returns (address token) {
                _tokens.push(token);

                unchecked {
                    ++index;
                }
            } catch {
                return;
            }
        }
    }

    function pool() external pure returns (address) {
        return _getArgAddress(_OFFSET_POOL);
    }

    function tokens() external view returns (address[] memory) {
        return _tokens;
    }

    function quoteTokenOutput(uint256 amount) external view returns (uint256) {
        return _pool().get_dy(_inputTokenIndex(), _outputTokenIndex(), amount);
    }

    function quoteTokenInput(uint256 amount) external view returns (uint256) {
        return _pool().get_dx(_inputTokenIndex(), _outputTokenIndex(), amount);
    }

    function swap(uint256 amount) external returns (uint256) {
        return
            _pool().exchange(
                _inputTokenIndex(),
                _outputTokenIndex(),
                amount,
                _MIN_SWAP_AMOUNT,
                address(this)
            );
    }
}
