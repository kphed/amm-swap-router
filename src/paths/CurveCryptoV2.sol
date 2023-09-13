// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Clone} from "solady/utils/Clone.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IPath} from "src/paths/IPath.sol";

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

contract CurveCryptoV2 is Clone, IPath {
    using SafeTransferLib for address;

    uint256 private constant _OFFSET_POOL = 0;
    uint256 private constant _OFFSET_INPUT_TOKEN_INDEX = 20;
    uint256 private constant _OFFSET_OUTPUT_TOKEN_INDEX = 52;
    uint256 private constant _OFFSET_INPUT_TOKEN = 84;
    uint256 private constant _OFFSET_OUTPUT_TOKEN = 104;

    // Slippage should be handled by the caller.
    uint256 private constant _MIN_SWAP_AMOUNT = 1;

    bool private _initialized = false;

    event Initialized(
        address indexed msgSender,
        address indexed pool,
        address inputToken,
        address outputToken
    );

    error AlreadyInitialized();

    function initialize() external {
        if (_initialized) revert AlreadyInitialized();

        _initialized = true;
        address poolAddr = address(_pool());
        address inputToken = _inputToken();
        address outputToken = _outputToken();

        emit Initialized(msg.sender, poolAddr, inputToken, outputToken);

        inputToken.safeApproveWithRetry(poolAddr, type(uint256).max);
        outputToken.safeApproveWithRetry(poolAddr, type(uint256).max);
    }

    function _pool() private pure returns (ICurveCryptoV2) {
        return ICurveCryptoV2(_getArgAddress(_OFFSET_POOL));
    }

    function _inputTokenIndex() private pure returns (uint256) {
        return _getArgUint256(_OFFSET_INPUT_TOKEN_INDEX);
    }

    function _outputTokenIndex() private pure returns (uint256) {
        return _getArgUint256(_OFFSET_OUTPUT_TOKEN_INDEX);
    }

    function _inputToken() private pure returns (address) {
        return _getArgAddress(_OFFSET_INPUT_TOKEN);
    }

    function _outputToken() private pure returns (address) {
        return _getArgAddress(_OFFSET_OUTPUT_TOKEN);
    }

    function approveSpenders() external {
        address poolAddr = address(_pool());

        _inputToken().safeApproveWithRetry(poolAddr, type(uint256).max);
        _outputToken().safeApproveWithRetry(poolAddr, type(uint256).max);
    }

    function pool() external pure returns (address) {
        return _getArgAddress(_OFFSET_POOL);
    }

    function tokens() external pure returns (address, address) {
        return (_inputToken(), _outputToken());
    }

    function quoteTokenOutput(uint256 amount) external view returns (uint256) {
        return _pool().get_dy(_inputTokenIndex(), _outputTokenIndex(), amount);
    }

    function quoteTokenInput(uint256 amount) external view returns (uint256) {
        return _pool().get_dx(_inputTokenIndex(), _outputTokenIndex(), amount);
    }

    function swap(uint256 amount) external returns (uint256) {
        _inputToken().safeTransferFrom(msg.sender, address(this), amount);

        return
            _pool().exchange(
                _inputTokenIndex(),
                _outputTokenIndex(),
                amount,
                _MIN_SWAP_AMOUNT,
                false,
                msg.sender
            );
    }
}
