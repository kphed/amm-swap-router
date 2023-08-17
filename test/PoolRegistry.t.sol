// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "src/PoolRegistry.sol";

contract PoolRegistryTest is Test {
    PoolRegistry public immutable registry = new PoolRegistry();
}
