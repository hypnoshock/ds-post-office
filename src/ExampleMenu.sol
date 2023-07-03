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

contract ExampleMenu is BuildingKind {
    function use(Game ds, bytes24 buildingInstance, bytes24, /*seeker*/ bytes calldata payload) public {
        // From the payload, determine if we triggered use from menu 1 or menu 2
        (uint8 menuNum, uint64 data) = abi.decode(payload[4:], (uint8, uint64));

        // NOTE: Directly setting the state is illegal however, I wanted some way of knowing if the payload decoded correctly
        State s = ds.getState();
        ( /*bytes24 dstNodeId*/ , uint64 weight) = s.get(Rel.Balance.selector, menuNum, buildingInstance);
        s.set(Rel.Balance.selector, menuNum, buildingInstance, buildingInstance, weight + uint64(data));
    }
}
