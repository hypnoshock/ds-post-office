// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Game} from "cog/Game.sol";
import {State} from "cog/State.sol";
import {Rel, Schema, Kind, Node} from "@ds/schema/Schema.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {BuildingKind} from "@ds/ext/BuildingKind.sol";
import {console} from "forge-std/console.sol";
import {Dispatcher} from "cog/Dispatcher.sol";
import "@ds/utils/Base64.sol";

using Schema for State;

// Check state by using graphQL playground at https://services-ds-test.dev.playmint.com/
/*
{
  game(id:"latest") {
    id
    state{
      buildings: nodes(match: {kinds: ["Building"]}) {
      	id
        equipSlots: edges(match: {kinds: ["Bag"], via:{rel: "Equip"}}) {
          key
          node {
            id
          }
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

struct Consignment {
    bytes24 fromUnit;
    bytes24 toUnit;
    bytes24 toOffice;
    bytes24 bag;
    bytes24 paymentBag;
    bytes24 equipee; // possibly useful for frontend
    uint8 equipSlot; // possibly not needed
}

uint8 constant MAX_EQUIP_SLOTS = 100; // was reverting at 256!

contract PostOffice is BuildingKind {
    Consignment[] public consignments;
    mapping(bytes24 => Consignment) bagToConsignment;
    bytes24 consignmentLedger;

    function use(Game ds, bytes24 buildingInstance, bytes24 unit, bytes calldata payload) public {
        State s = ds.getState();
        Dispatcher dispatcher = ds.getDispatcher();

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

            _sendBag(s, buildingInstance, unit, sendEquipSlot, toUnit, toOffice, payEquipSlot);
        }

        if (bytes4(payload) == PostOfficeActions.collectBag.selector) {
            _collectBag(s, buildingInstance, unit);
        }

        if (bytes4(payload) == PostOfficeActions.collectForDelivery.selector) {
            _collectForDelivery(s, buildingInstance, unit);
        }

        if (bytes4(payload) == PostOfficeActions.deliverBags.selector) {
            _deliverBags(s, buildingInstance, unit);
        }

        // -- Will just give all the custody bags to the caller of this action. Used in development during bug fixing
        if (bytes4(payload) == PostOfficeActions.panic.selector) {
            for (uint8 i = 2; i < MAX_EQUIP_SLOTS; i++) {
                bytes24 custodyBag = s.getEquipSlot(buildingInstance, i);

                // Unequip from building
                s.setEquipSlot(buildingInstance, i, bytes24(0));
                s.setOwner(custodyBag, s.getOwner(unit));

                _equipToNextAvailableSlot(s, unit, custodyBag);
            }
        }

        _broadcastConsignments(s, dispatcher);

        // revert("No action matches function signature:");
    }

    function _sendBag(
        State s,
        bytes24 buildingInstance,
        bytes24 unit,
        uint8 sendEquipSlot,
        bytes24 toUnit,
        bytes24 toOffice,
        uint8 payEquipSlot
    ) private {
        bytes24 bag = s.getEquipSlot(unit, sendEquipSlot);
        require(bytes4(bag) == Kind.Bag.selector, "selected equip slot isn't a bag");
        require(bagToConsignment[bag].toUnit == bytes24(0), "Cannot send as this bag is tracked for delivery");

        // Unequip from unit and set owner to building
        // TODO: Make a rule that only allows the owner to set the new owner
        s.setEquipSlot(unit, sendEquipSlot, bytes24(0));
        s.setOwner(bag, buildingInstance);

        // Log who and where the bag is destined to
        // TODO check that toUnit is a unit and check toOffice is a post office
        Consignment memory c = Consignment({
            fromUnit: unit,
            toUnit: toUnit,
            toOffice: toOffice,
            bag: bag,
            paymentBag: bytes24(0),
            equipee: buildingInstance,
            equipSlot: _equipToNextAvailableSlot(s, buildingInstance, bag)
        });
        consignments.push(c);
        bagToConsignment[bag] = c;

        // payment
        if (payEquipSlot != 255) {
            bytes24 paymentBag = s.getEquipSlot(unit, payEquipSlot);
            require(bytes4(paymentBag) == Kind.Bag.selector, "selected payment slot isn't a bag");
            require(paymentBag != bag, "bag to send cannot be same as bag for payment");

            c.paymentBag = paymentBag;

            s.setEquipSlot(unit, payEquipSlot, bytes24(0));
            s.setOwner(paymentBag, buildingInstance);
            _equipToNextAvailableSlot(s, buildingInstance, paymentBag);
        }
    }

    function _collectBag(State s, bytes24 buildingInstance, bytes24 unit) private {
        // NOTE: Directly setting the state is illegal however, I wanted some way of knowing if the payload decoded correctly
        for (uint8 i = 0; i < MAX_EQUIP_SLOTS; i++) {
            bytes24 custodyBag = s.getEquipSlot(buildingInstance, i);
            Consignment storage c = bagToConsignment[custodyBag];

            // If bag belongs to Unit and is at this building.
            // && bagToOffice[custodyBag] == buildingInstance // Add this to if statement to enforce delivery. Without the addressee can collect from drop off point before delivery
            if (c.toUnit == unit) {
                // Unequip from building
                s.setEquipSlot(buildingInstance, i, bytes24(0));
                s.setOwner(custodyBag, s.getOwner(unit));

                _equipToNextAvailableSlot(s, unit, custodyBag);

                // payment (if the recipient picked it up themselves)
                if (c.paymentBag != bytes24(0)) {
                    // Unequip from building
                    (uint8 payEquipSlot, bool found) = _getEquipSlotForEquipment(s, buildingInstance, c.paymentBag);
                    require(found, "Payment bag not attached to building!!");

                    s.setEquipSlot(buildingInstance, payEquipSlot, bytes24(0));
                    s.setOwner(c.paymentBag, s.getOwner(unit));

                    _equipToNextAvailableSlot(s, unit, c.paymentBag);
                }

                _deleteConsignment(c);
            }
        }
    }

    function _deleteConsignment(Consignment storage consignment) private {
        for (uint256 i = 0; i < consignments.length; i++) {
            if (consignments[i].bag == consignment.bag) {
                consignments[i] = consignments[consignments.length - 1];
                consignments.pop();

                delete bagToConsignment[consignment.bag];
            }
        }
    }

    function _collectForDelivery(State s, bytes24 buildingInstance, bytes24 unit) private {
        // NOTE: Directly setting the state is illegal however, I wanted some way of knowing if the payload decoded correctly
        for (uint8 i = 0; i < MAX_EQUIP_SLOTS; i++) {
            bytes24 custodyBag = s.getEquipSlot(buildingInstance, i);
            Consignment storage c = bagToConsignment[custodyBag];
            if (c.toUnit != bytes24(0) && c.toOffice != buildingInstance) {
                // Unequip from building
                s.setEquipSlot(buildingInstance, i, bytes24(0));
                s.setOwner(custodyBag, c.toOffice); // owner is set to destination office

                c.equipee = unit;
                c.equipSlot = _equipToNextAvailableSlot(s, unit, custodyBag);

                // payment
                if (c.paymentBag != bytes24(0)) {
                    // Unequip from building
                    (uint8 payEquipSlot, bool found) = _getEquipSlotForEquipment(s, buildingInstance, c.paymentBag);
                    require(found, "Payment bag not attached to building!!");

                    s.setEquipSlot(buildingInstance, payEquipSlot, bytes24(0));
                    s.setOwner(c.paymentBag, c.toOffice); // owner is set to destination office
                    _equipToNextAvailableSlot(s, unit, c.paymentBag);
                }
            }
        }
    }

    function _deliverBags(State s, bytes24 buildingInstance, bytes24 unit) private {
        for (uint8 i = 0; i < MAX_EQUIP_SLOTS; i++) {
            bytes24 bag = s.getEquipSlot(unit, i);
            Consignment storage c = bagToConsignment[bag];
            if (c.toOffice == buildingInstance) {
                // Unequip from unit and set owner to building
                s.setEquipSlot(unit, i, bytes24(0));
                // s.setOwner(bag, buildingInstance); // Owner should already be this office
                _equipToNextAvailableSlot(s, buildingInstance, bag);

                // payment
                if (c.paymentBag != bytes24(0)) {
                    require(
                        s.getOwner(c.paymentBag) == buildingInstance, "Payment bag not owned by destination office!"
                    );

                    // This effectively unlocks the bag for the postman
                    s.setOwner(c.paymentBag, s.getOwner(unit));
                    c.paymentBag = bytes24(0);
                }
            }
        }
    }

    function _broadcastConsignments(State s, Dispatcher dispatcher) private {
        if (consignmentLedger == bytes24(0)) {
            consignmentLedger = _getConsignmentLedger(s, dispatcher);
        }

        // store the ledger in the name annotation of the entity we own ... again, don't judge me (because Farm's did it first)
        dispatcher.dispatch(
            abi.encodeCall(Actions.NAME_OWNED_ENTITY, (consignmentLedger, Base64.encode(abi.encode(consignments))))
        );
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

    // TODO: Should be a rule. First thought is only the owner of the equipment or the equipee can choose who or what
    //       the equipment can be equipped to
    // TODO: Dangerous if called twice as there is no check to see if the equipment was already equipped to the node
    function _equipToNextAvailableSlot(State s, bytes24 equipee, bytes24 equipment) private returns (uint8 equipSlot) {
        for (equipSlot = 0; equipSlot < MAX_EQUIP_SLOTS; equipSlot++) {
            bytes24 heldEquipment = s.getEquipSlot(equipee, equipSlot);
            if (heldEquipment == bytes24(0)) {
                s.setEquipSlot(equipee, equipSlot, equipment);
                return equipSlot;
            }
        }

        revert("entity has run out of slots!");
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

    function _getConsignmentLedger(State state, Dispatcher dispatcher) private returns (bytes24 ledger) {
        // we are using a item's "name" annotation as a place to store data that can be read by a client plugin
        // this is a horrible hack and probably makes no sence to look at... don't judge me (because Farm's did it first), we need Books

        // Marked 4 bytes are the item ID
        //                 XXXXXXXX
        ledger = 0x6a7a67f0210d1f8300000001000000640000006400000064;
        if (state.getOwner(ledger) != 0) {
            return ledger;
        } else {
            dispatcher.dispatch(abi.encodeCall(Actions.REGISTER_ITEM_KIND, (ledger, "consignmentLedger", "")));
            bytes24[4] memory materialItem;
            materialItem[0] = 0x6a7a67f0cca240f900000001000000020000000000000000; // green goo
            materialItem[1] = 0x6a7a67f0e0f51af400000001000000000000000200000000; // blue goo
            materialItem[2] = 0x6a7a67f0006f223600000001000000000000000000000002; // red goo
            uint64[4] memory materialQty;
            materialQty[0] = 25;
            materialQty[1] = 25;
            materialQty[2] = 25;
            // Last 8 bytes are the ID
            bytes24 buildingKind = 0xbe92755c00000000000000000000000051a26be173f7f602;
            dispatcher.dispatch(
                abi.encodeCall(
                    Actions.REGISTER_BUILDING_KIND, (buildingKind, "Consignment office", materialItem, materialQty)
                )
            );
            bytes24[4] memory inputItem;
            inputItem[0] = 0x6a7a67f0cca240f900000001000000020000000000000000; // green goo
            inputItem[1] = 0x6a7a67f0e0f51af400000001000000000000000200000000; // blue goo
            inputItem[2] = 0x6a7a67f0006f223600000001000000000000000000000002; // red goo
            uint64[4] memory inputQty;
            inputQty[0] = 100;
            inputQty[1] = 100;
            inputQty[2] = 100;
            bytes24 outputItem = ledger;
            uint64 outputQty = 1;
            dispatcher.dispatch(
                abi.encodeCall(
                    Actions.REGISTER_CRAFT_RECIPE, (buildingKind, inputItem, inputQty, outputItem, outputQty)
                )
            );
            return ledger;
        }
    }
}
