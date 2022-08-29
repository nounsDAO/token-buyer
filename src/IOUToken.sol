// SPDX-License-Identifier: GPL-3.0

/// @title Nouns IOU Token

/*********************************
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░██░░░████░░██░░░████░░░ *
 * ░░██████░░░████████░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░██░░██░░░████░░██░░░████░░░ *
 * ░░░░░░█████████░░█████████░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ *
 *********************************/

pragma solidity ^0.8.15;

import { ERC20 } from 'openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import { AccessControlEnumerable } from 'openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol';

/**
 * @notice An ERC20 token representing a debt {Payer} owes its payment recipients. {Payer} can mint this token whenever a
 * payment is created with insufficient payment token balance; {Payer} can then burn this token when recipients redeem it for
 * the desired payment token.
 * @dev To work properly with {Payer}, must have the same decimals as the payment token.
 */
contract IOUToken is ERC20, AccessControlEnumerable {
    bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
    bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');
    bytes32 public constant BURNER_ROLE = keccak256('BURNER_ROLE');

    uint8 public _decimals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address admin
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;

        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(BURNER_ROLE, ADMIN_ROLE);
        _setupRole(ADMIN_ROLE, admin);
    }

    // TODO add permissions
    function mint(address account, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(account, amount);
    }

    // TODO add permissions
    function burn(address account, uint256 amount) public onlyRole(BURNER_ROLE) {
        _burn(account, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
