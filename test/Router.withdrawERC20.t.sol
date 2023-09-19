// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {RouterHelper} from "test/RouterHelper.sol";

contract Router_withdrawERC20 is Test, RouterHelper {
    using SafeTransferLib for address;

    event WithdrawERC20(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function testCannotWithdrawERC20Unauthorized() external {
        address msgSender = address(0);
        address recipient = address(this);
        uint256 amount = 1;

        assertTrue(msgSender != router.owner());

        vm.prank(msgSender);
        vm.expectRevert(Ownable.Unauthorized.selector);

        router.withdrawERC20(CRVUSD, recipient, amount);
    }

    function testCannotWithdrawERC20_TransferFailed_InvalidAmount() external {
        address msgSender = router.owner();
        address recipient = address(this);
        uint256 amount = CRVUSD.balanceOf(address(router)) + 1;

        vm.prank(msgSender);
        vm.expectRevert(SafeTransferLib.TransferFailed.selector);

        router.withdrawERC20(CRVUSD, recipient, amount);
    }

    function testCannotWithdrawERC20_TransferFailed_InvalidRecipient()
        external
    {
        address msgSender = router.owner();
        address recipient = address(0);
        uint256 amount = CRVUSD.balanceOf(address(router));

        vm.prank(msgSender);
        vm.expectRevert(SafeTransferLib.TransferFailed.selector);

        router.withdrawERC20(CRVUSD, recipient, amount);
    }

    function testWithdrawERC20() external {
        address msgSender = router.owner();
        address recipient = address(this);
        uint256 amount = CRVUSD.balanceOf(address(router));
        uint256 recipientBalanceBefore = CRVUSD.balanceOf(recipient);
        uint256 routerBalanceBefore = CRVUSD.balanceOf(address(router));

        vm.prank(msgSender);

        // emit WithdrawERC20(address indexed,address indexed,uint256);
        vm.expectEmit(true, true, false, true, address(router));

        emit WithdrawERC20(CRVUSD, recipient, amount);

        // emit Transfer(address indexed,address indexed,uint256);
        vm.expectEmit(true, true, false, true, CRVUSD);

        emit Transfer(address(router), recipient, amount);

        router.withdrawERC20(CRVUSD, recipient, amount);

        assertEq(
            routerBalanceBefore - amount,
            CRVUSD.balanceOf(address(router))
        );
        assertEq(
            recipientBalanceBefore + amount,
            CRVUSD.balanceOf(address(recipient))
        );
    }

    function testWithdrawERC20Fuzz(
        address recipient,
        uint256 crvusdBalance,
        uint256 amount
    ) external {
        deal(CRVUSD, address(router), crvusdBalance);

        address msgSender = router.owner();
        uint256 recipientBalanceBefore = CRVUSD.balanceOf(recipient);
        uint256 routerBalanceBefore = CRVUSD.balanceOf(address(router));

        vm.prank(msgSender);

        if (recipient == address(0) || (crvusdBalance < amount)) {
            vm.expectRevert(SafeTransferLib.TransferFailed.selector);

            router.withdrawERC20(CRVUSD, recipient, amount);
        } else {
            // emit WithdrawERC20(address indexed,address indexed,uint256);
            vm.expectEmit(true, true, false, true, address(router));

            emit WithdrawERC20(CRVUSD, recipient, amount);

            // emit Transfer(address indexed,address indexed,uint256);
            vm.expectEmit(true, true, false, true, CRVUSD);

            emit Transfer(address(router), recipient, amount);

            router.withdrawERC20(CRVUSD, recipient, amount);

            assertEq(
                routerBalanceBefore - amount,
                CRVUSD.balanceOf(address(router))
            );
            assertEq(
                recipientBalanceBefore + amount,
                CRVUSD.balanceOf(recipient)
            );
        }
    }
}
