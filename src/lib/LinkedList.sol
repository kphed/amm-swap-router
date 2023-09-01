// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title Maintains a doubly linked list keyed by bytes32.
 * @dev Following the `next` pointers will lead you to the head, rather than the tail.
 * @dev Imported from the Celo protocol monorepo (git commit hash ce93c3fcbdc4072b0cf4aea731bc1af0a8068fe6)
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
    error DuplicateKey();
    error InvalidKey();
    error InvalidPreviousKey();
    error InvalidNextKey();
    error UndefinedPreviousAndNextKey();
    error UndefinedPreviousKey();
    error UndefinedNextKey();
    error KeyNotInList();

    /**
     * @notice Inserts an element into a doubly linked list.
     * @param list A storage pointer to the underlying list.
     * @param key The key of the element to insert.
     * @param previousKey The key of the element that comes before the element to insert.
     * @param nextKey The key of the element that comes after the element to insert.
     */
    function insert(
        List storage list,
        bytes32 key,
        bytes32 previousKey,
        bytes32 nextKey
    ) internal {
        if (key == bytes32(0)) revert UndefinedKey();
        if (contains(list, key)) revert DuplicateKey();
        if (previousKey == key || nextKey == key) revert InvalidKey();

        // If the list is empty (the head should never be empty bytes otherwise), set the head and tail to the key.
        if (list.head == bytes32(0)) {
            list.tail = key;
            list.head = key;
        } else {
            // Throw if neither the previous nor next keys are defined.
            if (previousKey == bytes32(0) && nextKey == bytes32(0))
                revert UndefinedPreviousAndNextKey();

            list.elements[key] = Element(previousKey, nextKey);

            if (previousKey != bytes32(0)) {
                // Throw if the previous key is specified but does not exist.
                if (!contains(list, previousKey)) revert UndefinedPreviousKey();

                Element storage previousElement = list.elements[previousKey];

                if (previousElement.nextKey != nextKey) revert InvalidNextKey();

                previousElement.nextKey = key;
            } else {
                list.tail = key;
            }

            if (nextKey != bytes32(0)) {
                // Throw if the previous key is specified but does not exist.
                if (!contains(list, nextKey)) revert UndefinedNextKey();

                Element storage nextElement = list.elements[nextKey];

                if (nextElement.previousKey != previousKey)
                    revert InvalidPreviousKey();

                nextElement.previousKey = key;
            } else {
                list.head = key;
            }
        }
    }

    /**
     * @notice Inserts an element at the tail of the doubly linked list.
     * @param list A storage pointer to the underlying list.
     * @param key The key of the element to insert.
     */
    function push(List storage list, bytes32 key) internal {
        if (key == bytes32(0)) revert UndefinedKey();
        if (contains(list, key)) revert DuplicateKey();

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

    /**
     * @notice Removes an element from the doubly linked list.
     * @param list A storage pointer to the underlying list.
     * @param key The key of the element to remove.
     */
    function remove(List storage list, bytes32 key) internal {
        Element storage element = list.elements[key];

        if (key == bytes32(0) || !contains(list, key)) revert KeyNotInList();

        if (element.previousKey != bytes32(0)) {
            list.elements[element.previousKey].nextKey = element.nextKey;
        } else {
            list.tail = element.nextKey;
        }

        if (element.nextKey != bytes32(0)) {
            list.elements[element.nextKey].previousKey = element.previousKey;
        } else {
            list.head = element.previousKey;
        }

        delete list.elements[key];
    }

    /**
     * @notice Updates an element in the list.
     * @param list A storage pointer to the underlying list.
     * @param key The element key.
     * @param previousKey The key of the element that comes before the updated element.
     * @param nextKey The key of the element that comes after the updated element.
     */
    function update(
        List storage list,
        bytes32 key,
        bytes32 previousKey,
        bytes32 nextKey
    ) internal {
        if (key == previousKey || key == nextKey || !contains(list, key))
            revert InvalidKey();

        remove(list, key);
        insert(list, key, previousKey, nextKey);
    }

    /**
     * @notice Returns whether or not a particular key is present in the sorted list.
     * @param list A storage pointer to the underlying list.
     * @param key The element key.
     * @return Whether or not the key is in the sorted list.
     */
    function contains(
        List storage list,
        bytes32 key
    ) internal view returns (bool) {
        // If the key is the head or tail, or has a previous key defined then it exists.
        if (
            list.elements[key].previousKey != bytes32(0) ||
            list.elements[key].nextKey != bytes32(0) ||
            list.head == key ||
            list.tail == key
        ) return true;

        return false;
    }
}
