// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/Game.sol";
import {State} from "cog/State.sol";
import {Rel, Schema} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {BuildingKind} from "@ds/ext/BuildingKind.sol";
import {console} from "forge-std/console.sol";

using Schema for State;

// Check state by using graphQL playground at https://services-ds-test.dev.playmint.com/
/*
{
  game(id:"latest") {
    id
    state{
      buildings: nodes(match: {kinds: ["Building"]}) {
      	id
        test: edges(match: {kinds: ["Building"], via:{rel: "Balance"}}) {
          key
          weight
        }
      }
    }
  }
}
*/

interface MenuActions {
    function useMenu1() external;
    function useMenu2(uint64 inc) external;
}

contract ExampleMenu is BuildingKind {
    function use(Game ds, bytes24 buildingInstance, bytes24, /*seeker*/ bytes calldata payload) public {
        // From the payload, decode the action
        uint8 menuNum;
        uint8 inc;

        if (bytes4(payload) == MenuActions.useMenu1.selector) {
            menuNum = 1;
            inc = 1;
            // no parameters to decode for this action
        }

        if (bytes4(payload) == MenuActions.useMenu2.selector) {
            menuNum = 2;
            (inc) = abi.decode(payload[4:], (uint8));
        }

        require(menuNum != 0, "ExampleMenu: menu number not set. Check function encoding");

        // NOTE: Directly setting the state is illegal however, I wanted some way of knowing if the payload decoded correctly
        State s = ds.getState();
        ( /*bytes24 dstNodeId*/ , uint64 weight) = s.get(Rel.Balance.selector, menuNum, buildingInstance);
        s.set(Rel.Balance.selector, menuNum, buildingInstance, buildingInstance, weight + inc);
    }
}
