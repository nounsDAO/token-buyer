// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { DebtQueue } from '../src/libs/DebtQueue.sol';

contract DebtQueueTest is Test {
    using DebtQueue for DebtQueue.DebtDeque;

    DebtQueue.DebtDeque public queue;

    function test_popFront() public {
        queue.pushBack(DebtQueue.DebtEntry({ account: address(1), amount: 100 }));

        DebtQueue.DebtEntry memory popped = queue.popFront();

        assertEq(popped.account, address(1));
        assertEq(popped.amount, 100);
    }

    function test_popFront_manyItems() public {
        queue.pushBack(DebtQueue.DebtEntry({ account: address(1), amount: 100 }));
        queue.pushBack(DebtQueue.DebtEntry({ account: address(2), amount: 200 }));
        queue.pushBack(DebtQueue.DebtEntry({ account: address(3), amount: 300 }));

        DebtQueue.DebtEntry memory popped;

        popped = queue.popFront();
        assertEq(popped.account, address(1));
        assertEq(popped.amount, 100);

        popped = queue.popFront();
        assertEq(popped.account, address(2));
        assertEq(popped.amount, 200);

        popped = queue.popFront();
        assertEq(popped.account, address(3));
        assertEq(popped.amount, 300);
    }
}
