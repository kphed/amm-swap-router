// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {RouterHelper} from "test/RouterHelper.sol";

contract Router_constructor is Test, RouterHelper {
    function testConstructor() external {
        assertEq(address(this), router.owner());
    }
}
