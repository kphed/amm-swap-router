// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {LibClone} from "solady/utils/LibClone.sol";
import {CurveStableSwap} from "src/pools/CurveStableSwap.sol";

contract CurveStableSwapFactory {
    address public immutable implementation = address(new CurveStableSwap());

    function create(
        address pool,
        uint48 inputTokenIndex,
        uint48 outputTokenIndex
    ) external returns (address poolInterface) {
        poolInterface = LibClone.clone(
            implementation,
            abi.encodePacked(pool, inputTokenIndex, outputTokenIndex)
        );

        CurveStableSwap(poolInterface).initialize();
    }
}
