// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {LibClone} from "solady/utils/LibClone.sol";
import {IUniswapV3, UniswapV3} from "src/paths/UniswapV3.sol";

interface IUniswapV3Factory {
    function getPool(address, address, uint24) external view returns (address);
}

contract UniswapV3Factory {
    IUniswapV3Factory private constant _POOL_FACTORY =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    uint160 private constant _MIN_SQRT_RATIO = 4295128740;
    uint160 private constant _MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970341;
    address public immutable implementation = address(new UniswapV3());
    mapping(bytes32 params => address clone) public deployments;

    error InvalidPool();

    function create(
        address pool,
        bool zeroForOne
    ) external returns (address poolInterface) {
        if (pool == address(0)) revert InvalidPool();

        bytes32 deploymentKey = keccak256(abi.encodePacked(pool, zeroForOne));

        // If a clone with the same args has already been deployed, return it.
        if (deployments[deploymentKey] != address(0)) {
            return deployments[deploymentKey];
        }

        IUniswapV3 poolContract = IUniswapV3(pool);
        address inputToken = zeroForOne
            ? poolContract.token0()
            : poolContract.token1();
        address outputToken = zeroForOne
            ? poolContract.token1()
            : poolContract.token0();

        // Check whether the pool was deployed by the canonical Uniswap V3 factory.
        if (
            pool !=
            _POOL_FACTORY.getPool(inputToken, outputToken, poolContract.fee())
        ) revert InvalidPool();

        poolInterface = LibClone.clone(
            implementation,
            abi.encodePacked(
                pool,
                zeroForOne ? poolContract.token0() : poolContract.token1(),
                zeroForOne ? poolContract.token1() : poolContract.token0(),
                keccak256(abi.encodePacked(zeroForOne)),
                zeroForOne ? _MIN_SQRT_RATIO : _MAX_SQRT_RATIO
            )
        );
        deployments[deploymentKey] = poolInterface;
    }
}
