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

    mapping(address token => uint256 index) public coins;

    constructor(address _pool, uint256 coinsCount) {
        pool = ICurveCryptoV2(_pool);

        for (uint256 i = 0; i < coinsCount; ) {
            coins[pool.coins(i)] = i;

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
            pool.get_dy(
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
            pool.get_dx(
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
            pool.exchange(
                coins[inputToken],
                coins[outputToken],
                inputTokenAmount,
                minOutputTokenAmount,
                false,
                address(this)
            );
    }
}
