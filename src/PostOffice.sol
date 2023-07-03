// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/Game.sol";
import {State} from "cog/State.sol";
import {Rel, Schema, Kind} from "@ds/schema/Schema.sol";
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

interface PostOfficeActions {
    function sendBag(uint8 equipSlot, bytes24 toUnit) external;
    function collectBag() external;
}

contract PostOffice is BuildingKind {
    mapping(bytes24 => bytes24) bagToUnit;

    function use(Game ds, bytes24 buildingInstance, bytes24 unit, bytes calldata payload) public {
        State s = ds.getState();

        if (bytes4(payload) == PostOfficeActions.sendBag.selector) {
            (uint8 equipSlot, bytes24 toUnit) = abi.decode(payload[4:], (uint8, bytes24));

            bytes24 bag = s.getEquipSlot(unit, equipSlot);
            require(bytes4(bag) == Kind.Bag.selector, "selected equip slot isn't a bag");
            require(bagToUnit[bag] == bytes24(0), "Cannot send as this bag is tracked for delivery");

            // Unequip from unit and set owner to building
            // TODO: Make a rule that only allows the owner to set the new owner
            s.setEquipSlot(unit, equipSlot, bytes24(0));
            s.setOwner(bag, buildingInstance);

            // Set bag to next available equip slot
            equipToNextAvailableSlot(s, buildingInstance, bag);

            // Log who the bag is destined to
            bagToUnit[bag] = toUnit;

            return;
        }

        if (bytes4(payload) == PostOfficeActions.collectBag.selector) {
            // NOTE: Directly setting the state is illegal however, I wanted some way of knowing if the payload decoded correctly
            for (uint8 i = 0; i < 100; i++) {
                bytes24 custodyBag = s.getEquipSlot(buildingInstance, i);
                if (bagToUnit[custodyBag] == unit) {
                    // Unequip from building
                    s.setEquipSlot(buildingInstance, i, bytes24(0));
                    s.setOwner(custodyBag, bytes24(0)); // HACK: the owner is supposed to be the player so we don't have that info therefore making it 'public'

                    equipToNextAvailableSlot(s, unit, custodyBag);
                    bagToUnit[custodyBag] = bytes24(0);
                }
            }

            return;
        }

        revert("No action matches sig:");
    }

    // TODO: Should be a rule. First thought is only the owner of the equipment or the equipee can choose who or what
    //       the equipment can be equipped to
    function equipToNextAvailableSlot(State s, bytes24 equipee, bytes24 equipment) private {
        for (uint8 i = 0; i < 256; i++) {
            bytes24 heldEquipment = s.getEquipSlot(equipee, i);
            if (heldEquipment == bytes24(0)) {
                s.setEquipSlot(equipee, i, equipment);
                break;
            } else if (i == 255) {
                // Out of slots!
                revert("entity has run out of slots!");
            }
        }
    }
}
