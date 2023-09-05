// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @notice Solidity LinkedList implementation, based on the LinkedList library from the Celo protocol monorepo.
 * @notice Heavily modified (e.g. traversing from head => tail uses the `nextKey` instead of `previousKey` (original)).
 * @author kp (ppmoon69.eth)
 */
library LinkedList {
    struct Element {
        bytes32 previousKey;
        bytes32 nextKey;
    }

    struct List {
        bytes32 head;
        bytes32 tail;
        mapping(bytes32 => Element) elements;
    }

    error UndefinedKey();

    /**
     * @notice Inserts an element at the tail of the doubly linked list.
     * @param list A storage pointer to the underlying list.
     * @param key The key of the element to insert.
     */
    function push(List storage list, bytes32 key) internal {
        if (key == bytes32(0)) revert UndefinedKey();

        if (list.head == bytes32(0)) {
            list.tail = key;
            list.head = key;
        } else {
            bytes32 previousTail = list.tail;

            // Update the previous tail to point to the new tail.
            list.elements[previousTail].nextKey = key;

            // Set the new tail.
            list.tail = key;

            // Set the new tail to point to the previous tail.
            list.elements[key].previousKey = previousTail;
        }
    }
}
