// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibClone} from "solady/utils/LibClone.sol";
import {ICurveStableSwap, CurveStableSwap} from "src/paths/CurveStableSwap.sol";
import {ICurveStableSwapPoolFactory} from "src/interfaces/ICurveStableSwapPoolFactory.sol";

contract CurveStableSwapFactory {
    ICurveStableSwapPoolFactory private constant _POOL_FACTORY =
        ICurveStableSwapPoolFactory(0x4F8846Ae9380B90d2E71D5e3D042dff3E7ebb40d);
    address public immutable implementation = address(new CurveStableSwap());
    mapping(bytes32 params => address clone) public deployments;

    error InvalidPool();
    error IdenticalTokens();

    function create(
        address pool,
        uint48 inputTokenIndex,
        uint48 outputTokenIndex
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

        // Verify pool validity and get token addresses.
        address[4] memory coins = _POOL_FACTORY.get_coins(pool);

        poolInterface = LibClone.clone(
            implementation,
            abi.encodePacked(
                pool,
                inputTokenIndex,
                outputTokenIndex,
                // Throws if the indexes are invalid/out of bounds.
                coins[uint256(inputTokenIndex)],
                coins[uint256(outputTokenIndex)]
            )
        );
        deployments[deploymentKey] = poolInterface;

        CurveStableSwap(poolInterface).initialize();
    }
}
