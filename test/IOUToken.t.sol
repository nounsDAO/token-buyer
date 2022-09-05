// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import 'forge-std/Test.sol';
import { IOUToken } from '../src/IOUToken.sol';

contract IOUTokenTest is Test {
    uint8 constant DECIMALS = 18;

    IOUToken iou;
    address admin = address(42);
    address minter = address(1337);
    address burner = address(31337);

    function setUp() public {
        iou = new IOUToken('IOU Token', 'IOU', DECIMALS, admin);

        vm.startPrank(admin);
        iou.grantRole(iou.MINTER_ROLE(), minter);
        iou.grantRole(iou.BURNER_ROLE(), burner);
        vm.stopPrank();
    }

    function test_mint_revertsForNonMinter() public {
        vm.expectRevert(
            'AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6'
        );
        iou.mint(address(1), 100);
    }

    function test_mint_revertsForBurner() public {
        // to make sure minter and burner are distinct roles
        vm.prank(burner);
        vm.expectRevert(
            'AccessControl: account 0x0000000000000000000000000000000000007a69 is missing role 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6'
        );
        iou.mint(address(1), 100);
    }

    function test_mint_worksForMinter() public {
        assertEq(iou.balanceOf(address(1)), 0);

        vm.prank(minter);
        iou.mint(address(1), 100);

        assertEq(iou.balanceOf(address(1)), 100);
    }

    function test_burn_revertsForNonBurner() public {
        vm.prank(minter);
        iou.mint(address(1), 100);
        assertEq(iou.balanceOf(address(1)), 100);

        vm.expectRevert(
            'AccessControl: account 0xb4c79dab8f259c7aee6e5b2aa729821864227e84 is missing role 0x3c11d16cbaffd01df69ce1c404f6340ee057498f5f00246190ea54220576a848'
        );
        iou.burn(address(1), 100);
    }

    function test_burn_revertsForMinter() public {
        // to make sure minter and burner are distinct roles
        vm.prank(minter);
        iou.mint(address(1), 100);
        assertEq(iou.balanceOf(address(1)), 100);

        vm.prank(minter);
        vm.expectRevert(
            'AccessControl: account 0x0000000000000000000000000000000000000539 is missing role 0x3c11d16cbaffd01df69ce1c404f6340ee057498f5f00246190ea54220576a848'
        );
        iou.burn(address(1), 100);
    }

    function test_burn_worksForBurner() public {
        vm.prank(minter);
        iou.mint(address(1), 100);
        assertEq(iou.balanceOf(address(1)), 100);

        vm.prank(burner);
        iou.burn(address(1), 100);

        assertEq(iou.balanceOf(address(1)), 0);
    }

    function test_roles_adminCanGrantMinterAndBurner() public {
        address newMinterBurner = address(0xdead);

        vm.startPrank(admin);
        iou.grantRole(iou.MINTER_ROLE(), newMinterBurner);
        iou.grantRole(iou.BURNER_ROLE(), newMinterBurner);
        vm.stopPrank();

        assertTrue(iou.hasRole(iou.MINTER_ROLE(), newMinterBurner));
        assertTrue(iou.hasRole(iou.BURNER_ROLE(), newMinterBurner));
    }

    function test_roles_minterCantGrantMinterRole() public {
        bytes32 role = iou.MINTER_ROLE();

        vm.expectRevert(
            'AccessControl: account 0x0000000000000000000000000000000000000539 is missing role 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775'
        );
        vm.prank(minter);
        iou.grantRole(role, address(0xdead));
    }

    function test_roles_burnerCantGrantBurnerRole() public {
        bytes32 role = iou.BURNER_ROLE();

        vm.expectRevert(
            'AccessControl: account 0x0000000000000000000000000000000000007a69 is missing role 0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775'
        );
        vm.prank(burner);
        iou.grantRole(role, address(0xdead));
    }

    function test_roles_adminCanGrantAdmin() public {
        address newAdmin = address(0xdead);
        bytes32 role = iou.ADMIN_ROLE();

        vm.prank(admin);
        iou.grantRole(role, newAdmin);

        assertTrue(iou.hasRole(role, newAdmin));
    }

    function test_decimals_returnsConstructorSetValue() public {
        assertEq(iou.decimals(), DECIMALS);

        iou = new IOUToken('IOU Token', 'IOU', DECIMALS + 3, admin);

        assertEq(iou.decimals(), DECIMALS + 3);
    }
}
