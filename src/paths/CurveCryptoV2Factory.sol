// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibClone} from "solady/utils/LibClone.sol";
import {ICurveCryptoV2, CurveCryptoV2} from "src/paths/CurveCryptoV2.sol";
import {ICurveCryptoV2PoolFactory} from "src/interfaces/ICurveCryptoV2PoolFactory.sol";

contract CurveCryptoV2Factory {
    ICurveCryptoV2PoolFactory private constant _POOL_FACTORY =
        ICurveCryptoV2PoolFactory(0x0c0e5f2fF0ff18a3be9b835635039256dC4B4963);
    address public immutable implementation = address(new CurveCryptoV2());
    mapping(bytes32 params => address clone) public deployments;

    error InvalidPool();
    error IdenticalTokens();

    function create(
        address pool,
        uint256 inputTokenIndex,
        uint256 outputTokenIndex
    ) external returns (address poolInterface) {
        if (pool == address(0)) revert InvalidPool();
        if (inputTokenIndex == outputTokenIndex) revert IdenticalTokens();

        bytes32 deploymentKey = keccak256(
            abi.encodePacked(pool, inputTokenIndex, outputTokenIndex)
        );

        // If a clone with the same args has already been deployed, return it.
        if (deployments[deploymentKey] != address(0)) {
            return deployments[deploymentKey];
        }

        address[3] memory coins = _POOL_FACTORY.get_coins(pool);
        poolInterface = LibClone.clone(
            implementation,
            abi.encodePacked(
                pool,
                inputTokenIndex,
                outputTokenIndex,
                // Throws if the indexes are invalid/out of bounds.
                coins[inputTokenIndex],
                coins[outputTokenIndex]
            )
        );
        deployments[deploymentKey] = poolInterface;

        CurveCryptoV2(poolInterface).initialize();
    }
}
