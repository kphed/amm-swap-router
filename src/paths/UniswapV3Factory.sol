// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {LibClone} from "solady/utils/LibClone.sol";
import {UniswapV3} from "src/paths/UniswapV3.sol";

contract UniswapV3Factory {
    uint160 private constant _MIN_SQRT_RATIO = 4295128740;
    uint160 private constant _MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970341;

    address public immutable implementation = address(new UniswapV3());

    function create(
        address pool,
        address inputToken,
        bool zeroForOne
    ) external returns (address poolInterface) {
        poolInterface = LibClone.clone(
            implementation,
            abi.encodePacked(
                pool,
                inputToken,
                keccak256(abi.encodePacked(zeroForOne)),
                zeroForOne ? _MIN_SQRT_RATIO : _MAX_SQRT_RATIO
            )
        );

        UniswapV3(poolInterface).initialize();
    }
}
