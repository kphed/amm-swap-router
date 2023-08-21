// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

contract PoolRegistry is Ownable {
    using SafeCastLib for uint256;

    mapping(address pool => mapping(uint256 tokenIndex => address token))
        public pools;

    event SetPool(address indexed pool, address[] tokens);

    constructor(address initialOwner) {
        _initializeOwner(initialOwner);
    }

    function setPool(
        address pool,
        address[] calldata tokens
    ) external onlyOwner {
        uint256 tokensLength = tokens.length;

        for (uint256 i = 0; i < tokensLength; ) {
            pools[pool][i] = tokens[i];

            unchecked {
                ++i;
            }
        }

        emit SetPool(pool, tokens);
    }
}
