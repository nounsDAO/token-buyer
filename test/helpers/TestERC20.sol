// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { ERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';

contract TestERC20 is ERC20 {
    uint8 internal immutable _decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 numDecimals
    ) ERC20(name_, symbol_) {
        _decimals = numDecimals;
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
