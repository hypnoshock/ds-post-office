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
    function sendBag(uint8 sendEquipSlot, bytes24 toUnit, bytes24 toOffice, uint8 payEquipSlot) external;
    function collectBag() external;
    function collectForDelivery() external;
    function deliverBags() external;
    function panic() external;
}

uint8 constant MAX_EQUIP_SLOTS = 100; // was reverting at 256!

contract PostOffice is BuildingKind {
    // TODO: have one mapping and a struct
    mapping(bytes24 => bytes24) bagToUnit;
    mapping(bytes24 => bytes24) bagToOffice;
    mapping(bytes24 => bytes24) bagToPayment;

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
            (uint8 sendEquipSlot, bytes24 toUnit, bytes24 toOffice, uint8 payEquipSlot) =
                abi.decode(payload[4:], (uint8, bytes24, bytes24, uint8));

            bytes24 bag = s.getEquipSlot(unit, sendEquipSlot);
            require(bytes4(bag) == Kind.Bag.selector, "selected equip slot isn't a bag");
            require(bagToUnit[bag] == bytes24(0), "Cannot send as this bag is tracked for delivery");

            // Unequip from unit and set owner to building
            // TODO: Make a rule that only allows the owner to set the new owner
            s.setEquipSlot(unit, sendEquipSlot, bytes24(0));
            s.setOwner(bag, buildingInstance);

            // Set bag to next available equip slot
            _equipToNextAvailableSlot(s, buildingInstance, bag);

            // Log who and where the bag is destined to
            // TODO check that toUnit is a unit and check toOffice is a post office
            bagToUnit[bag] = toUnit;
            bagToOffice[bag] = toOffice;

            // payment
            if (payEquipSlot != 255) {
                bytes24 paymentBag = s.getEquipSlot(unit, payEquipSlot);
                require(bytes4(paymentBag) == Kind.Bag.selector, "selected payment slot isn't a bag");
                require(paymentBag != bag, "bag to send cannot be same as bag for payment");

                bagToPayment[bag] = paymentBag;

                s.setEquipSlot(unit, payEquipSlot, bytes24(0));
                s.setOwner(paymentBag, buildingInstance);
                _equipToNextAvailableSlot(s, buildingInstance, paymentBag);
            }

            return;
        }

        if (bytes4(payload) == PostOfficeActions.collectBag.selector) {
            // NOTE: Directly setting the state is illegal however, I wanted some way of knowing if the payload decoded correctly
            for (uint8 i = 0; i < MAX_EQUIP_SLOTS; i++) {
                bytes24 custodyBag = s.getEquipSlot(buildingInstance, i);

                // If bag belongs to Unit and is at this building.
                // && bagToOffice[custodyBag] == buildingInstance // Add this to if statement to enforce delivery. Without the addressee can collect from drop off point before delivery
                if (bagToUnit[custodyBag] == unit) {
                    // Unequip from building
                    s.setEquipSlot(buildingInstance, i, bytes24(0));
                    s.setOwner(custodyBag, s.getOwner(unit));

                    _equipToNextAvailableSlot(s, unit, custodyBag);
                    bagToUnit[custodyBag] = bytes24(0);
                    bagToOffice[custodyBag] = bytes24(0);

                    // payment (if the recipient picked it up themselves)
                    if (bagToPayment[custodyBag] != bytes24(0)) {
                        // Unequip from building
                        (uint8 payEquipSlot, bool found) =
                            _getEquipSlotForEquipment(s, buildingInstance, bagToPayment[custodyBag]);
                        require(found, "Payment bag not attached to building!!");

                        s.setEquipSlot(buildingInstance, payEquipSlot, bytes24(0));
                        s.setOwner(bagToPayment[custodyBag], s.getOwner(unit));

                        _equipToNextAvailableSlot(s, unit, bagToPayment[custodyBag]);
                        bagToPayment[custodyBag] = bytes24(0);
                    }
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

        if (bytes4(payload) == PostOfficeActions.panic.selector) {
            for (uint8 i = 2; i < MAX_EQUIP_SLOTS; i++) {
                bytes24 custodyBag = s.getEquipSlot(buildingInstance, i);

                // Unequip from building
                s.setEquipSlot(buildingInstance, i, bytes24(0));
                s.setOwner(custodyBag, s.getOwner(unit));

                _equipToNextAvailableSlot(s, unit, custodyBag);
            }
            return;
        }

        revert("No action matches sig:");
    }

    function _getEquipSlotForEquipment(State s, bytes24 equipee, bytes24 equipment)
        private
        view
        returns (uint8 equipSlot, bool found)
    {
        for (uint8 i = 0; i < MAX_EQUIP_SLOTS; i++) {
            if (s.getEquipSlot(equipee, i) == equipment) {
                return (i, true);
            }
        }

        return (0, false);
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

                // payment
                bytes24 paymentBag = bagToPayment[custodyBag];
                if (paymentBag != bytes24(0)) {
                    // Unequip from building
                    (uint8 payEquipSlot, bool found) = _getEquipSlotForEquipment(s, buildingInstance, paymentBag);
                    require(found, "Payment bag not attached to building!!");

                    s.setEquipSlot(buildingInstance, payEquipSlot, bytes24(0));
                    s.setOwner(paymentBag, bagToOffice[custodyBag]); // owner is set to destination office
                    _equipToNextAvailableSlot(s, unit, paymentBag);
                }
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

                // payment
                if (bagToPayment[bag] != bytes24(0)) {
                    require(
                        s.getOwner(bagToPayment[bag]) == buildingInstance,
                        "Payment bag not owned by destination office!"
                    );

                    // This effectively unlocks the bag for the postman
                    s.setOwner(bagToPayment[bag], s.getOwner(unit));
                    bagToPayment[bag] = bytes24(0);
                }
            }
        }
    }

    // TODO: Should be a rule. First thought is only the owner of the equipment or the equipee can choose who or what
    //       the equipment can be equipped to
    // TODO: Dangerous if called twice as there is no check to see if the equipment was already equipped to the node
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
                inc++;
            }
        }

        s.setOwner(bag, owner);
        s.setEquipSlot(seeker, equipSlot, bag);
    }
}
