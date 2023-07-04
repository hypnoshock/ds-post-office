// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/Game.sol";
import {State} from "cog/State.sol";
import {Rel, Schema, Kind, Node} from "@ds/schema/Schema.sol";
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
    function getEmptyBag() external;
    function sendBag(uint8 equipSlot, bytes24 toUnit, bytes24 toOffice) external;
    function collectBag() external;
    function collectForDelivery() external;
    function deliverBags() external;
}

uint8 constant MAX_EQUIP_SLOTS = 100; // was reverting at 256!

contract PostOffice is BuildingKind {
    mapping(bytes24 => bytes24) bagToUnit;
    mapping(bytes24 => bytes24) bagToOffice;

    function use(Game ds, bytes24 buildingInstance, bytes24 unit, bytes calldata payload) public {
        State s = ds.getState();

        if (bytes4(payload) == PostOfficeActions.getEmptyBag.selector) {
            (uint8 equipSlot, bool foundSlot) = _getNextAvailableEquipSlot(s, unit);
            if (foundSlot) {
                _spawnBag(s, unit, s.getOwner(unit), equipSlot);
            }
            return;
        }

        if (bytes4(payload) == PostOfficeActions.sendBag.selector) {
            (uint8 equipSlot, bytes24 toUnit, bytes24 toOffice) = abi.decode(payload[4:], (uint8, bytes24, bytes24));

            bytes24 bag = s.getEquipSlot(unit, equipSlot);
            require(bytes4(bag) == Kind.Bag.selector, "selected equip slot isn't a bag");
            require(bagToUnit[bag] == bytes24(0), "Cannot send as this bag is tracked for delivery");

            // Unequip from unit and set owner to building
            // TODO: Make a rule that only allows the owner to set the new owner
            s.setEquipSlot(unit, equipSlot, bytes24(0));
            s.setOwner(bag, buildingInstance);

            // Set bag to next available equip slot
            _equipToNextAvailableSlot(s, buildingInstance, bag);

            // Log who and where the bag is destined to
            // TODO check that toUnit is a unit and check toOffice is a post office
            bagToUnit[bag] = toUnit;
            bagToOffice[bag] = toOffice;

            return;
        }

        if (bytes4(payload) == PostOfficeActions.collectBag.selector) {
            // NOTE: Directly setting the state is illegal however, I wanted some way of knowing if the payload decoded correctly
            for (uint8 i = 0; i < MAX_EQUIP_SLOTS; i++) {
                bytes24 custodyBag = s.getEquipSlot(buildingInstance, i);

                // If bag belongs to Unit and is at this building.
                if (bagToUnit[custodyBag] == unit && bagToOffice[custodyBag] == buildingInstance) {
                    // Unequip from building
                    s.setEquipSlot(buildingInstance, i, bytes24(0));
                    s.setOwner(custodyBag, s.getOwner(unit));

                    _equipToNextAvailableSlot(s, unit, custodyBag);
                    bagToUnit[custodyBag] = bytes24(0);
                    bagToOffice[custodyBag] = bytes24(0);
                }
            }

            return;
        }

        if (bytes4(payload) == PostOfficeActions.collectForDelivery.selector) {
            _collectForDelivery(s, buildingInstance, unit);
            return;
        }

        if (bytes4(payload) == PostOfficeActions.deliverBags.selector) {
            _deliverBags(s, buildingInstance, unit);
            return;
        }

        revert("No action matches sig:");
    }

    function _collectForDelivery(State s, bytes24 buildingInstance, bytes24 unit) private {
        // NOTE: Directly setting the state is illegal however, I wanted some way of knowing if the payload decoded correctly
        for (uint8 i = 0; i < MAX_EQUIP_SLOTS; i++) {
            bytes24 custodyBag = s.getEquipSlot(buildingInstance, i);
            if (bagToOffice[custodyBag] != bytes24(0) && bagToOffice[custodyBag] != buildingInstance) {
                // Unequip from building
                s.setEquipSlot(buildingInstance, i, bytes24(0));
                s.setOwner(custodyBag, bagToOffice[custodyBag]); // owner is set to destination office

                _equipToNextAvailableSlot(s, unit, custodyBag);
            }
        }
    }

    function _deliverBags(State s, bytes24 buildingInstance, bytes24 unit) private {
        for (uint8 i = 0; i < MAX_EQUIP_SLOTS; i++) {
            bytes24 bag = s.getEquipSlot(unit, i);
            if (bagToOffice[bag] != bytes24(0) && bagToOffice[bag] == buildingInstance) {
                // Unequip from unit and set owner to building
                s.setEquipSlot(unit, i, bytes24(0));
                // s.setOwner(bag, buildingInstance); // Owner should already be this office
                _equipToNextAvailableSlot(s, buildingInstance, bag);
            }
        }
    }

    // TODO: Should be a rule. First thought is only the owner of the equipment or the equipee can choose who or what
    //       the equipment can be equipped to
    function _equipToNextAvailableSlot(State s, bytes24 equipee, bytes24 equipment) private {
        for (uint8 i = 0; i < MAX_EQUIP_SLOTS; i++) {
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

    function _getNextAvailableEquipSlot(State s, bytes24 equipee) private view returns (uint8, bool) {
        for (uint8 i = 0; i < MAX_EQUIP_SLOTS; i++) {
            bytes24 heldEquipment = s.getEquipSlot(equipee, i);
            if (heldEquipment == bytes24(0)) {
                return (i, true);
            }
        }

        return (0, false);
    }

    // TODO: Should be rule
    function _spawnBag(State s, bytes24 seeker, bytes24 owner, uint8 equipSlot) private {
        bytes24 bag;
        uint256 inc;
        while (bag == bytes24(0)) {
            bag = Node.Bag(uint64(uint256(keccak256(abi.encode(seeker, equipSlot, inc)))));
            if (s.getOwner(bag) != bytes24(0)) {
                bag = bytes24(0);
            }
        }

        s.setOwner(bag, owner);
        s.setEquipSlot(seeker, equipSlot, bag);
    }
}
