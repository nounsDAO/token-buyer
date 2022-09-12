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
}
