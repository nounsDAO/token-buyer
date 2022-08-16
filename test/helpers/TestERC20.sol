// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import { ERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';

contract TestERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}
