// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {LibClone} from "solady/utils/LibClone.sol";
import {ICurveStableSwap, CurveStableSwap} from "src/paths/CurveStableSwap.sol";

contract CurveStableSwapFactory {
    address public immutable implementation = address(new CurveStableSwap());

    function create(
        address pool,
        uint48 inputTokenIndex,
        uint48 outputTokenIndex
    ) external returns (address poolInterface) {
        ICurveStableSwap poolContract = ICurveStableSwap(pool);
        poolInterface = LibClone.clone(
            implementation,
            abi.encodePacked(
                pool,
                inputTokenIndex,
                outputTokenIndex,
                poolContract.coins(uint256(inputTokenIndex)),
                poolContract.coins(uint256(outputTokenIndex))
            )
        );

        CurveStableSwap(poolInterface).initialize();
    }
}
