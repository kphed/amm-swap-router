// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {LibClone} from "solady/utils/LibClone.sol";
import {ICurveCryptoV2, CurveCryptoV2} from "src/paths/CurveCryptoV2.sol";

contract CurveCryptoV2Factory {
    address public immutable implementation = address(new CurveCryptoV2());

    function create(
        address pool,
        uint256 inputTokenIndex,
        uint256 outputTokenIndex
    ) external returns (address poolInterface) {
        ICurveCryptoV2 poolContract = ICurveCryptoV2(pool);
        poolInterface = LibClone.clone(
            implementation,
            abi.encodePacked(
                pool,
                inputTokenIndex,
                outputTokenIndex,
                poolContract.coins(inputTokenIndex),
                poolContract.coins(outputTokenIndex)
            )
        );

        CurveCryptoV2(poolInterface).initialize();
    }
}
