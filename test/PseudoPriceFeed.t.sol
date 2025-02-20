// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PseudoPriceFeed} from "../src/mocks/PseudoPriceFeed.sol";

contract PseudoPriceFeedTest is Test {
    PseudoPriceFeed public t;

    function setUp() public {
        t = new PseudoPriceFeed(100, 8);
    }

    function testSetPrice() public {
        t.setPrice(200);
        assertEq(t.price(), 200);
    }

    function testSetPriceRevertsWhenSenderIsNotOwner() public {
        address notOwner = makeAddr("notOwner");
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );
        vm.prank(notOwner);
        t.setPrice(200);
    }

    function testLatestRoundData() public {
        skip(1000);
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = t.latestRoundData();
        assertEq(roundId, 0);
        assertEq(answer, 100);
        assertEq(startedAt, block.timestamp - 600);
        assertEq(updatedAt, block.timestamp - 600);
        assertEq(answeredInRound, 0);
    }
}
