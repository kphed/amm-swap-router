// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {EnumerableMap} from "openzeppelin/utils/structs/EnumerableMap.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract PoolRegistry is Ownable {
    struct Path {
        address pool;
        address inputToken;
        address outputToken;
    }

    using EnumerableMap for EnumerableMap.AddressToUintMap;

    EnumerableMap.AddressToUintMap private _pools;
    mapping(bytes32 pair => Path[][] path) public paths;

    event SetPool(
        address indexed pool,
        address indexed poolInterface,
        bool indexed isNew
    );
    event SetPaths(
        address indexed inputToken,
        address indexed outputToken,
        Path[][] newPaths
    );

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function _addrToUint256(address addr) private pure returns (uint256) {
        return uint256(uint160(addr));
    }

    function _uint256ToAddr(uint256 addr) private pure returns (address) {
        return address(uint160(addr));
    }

    function setPool(address pool, address poolInterface) external onlyOwner {
        bool isNew = _pools.set(pool, _addrToUint256(poolInterface));

        emit SetPool(pool, poolInterface, isNew);
    }

    function setPaths(
        address inputToken,
        address outputToken,
        Path[][] memory newPaths
    ) external onlyOwner {
        bytes32 pair = keccak256(abi.encodePacked(inputToken, outputToken));

        paths[pair] = newPaths;

        emit SetPaths(inputToken, outputToken, newPaths);
    }
}
