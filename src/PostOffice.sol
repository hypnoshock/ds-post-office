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
    function sendBag(bytes24 sendBag, bytes24 toUnit, bytes24 toOffice, bytes24 payBag) external;
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
    uint256 index; // TODO: Refactor bagToConsignment to be just the indexes and remove this
}

uint8 constant MAX_EQUIP_SLOT_INDEX = 254; // There appears to be a problem with state.getEquipSlot if used with 255

contract PostOffice is BuildingKind {
    Consignment[] public consignments;
    mapping(bytes24 => Consignment) bagToConsignment; // TODO: Refactor this to hold just consignmentLedger indexes instead of a full copy of the object
    bytes24 consignmentLedger;

    function use(Game ds, bytes24 buildingInstance, bytes24 unit, bytes calldata payload) public {
        State s = ds.getState();
        Dispatcher dispatcher = ds.getDispatcher();

        if (bytes4(payload) == PostOfficeActions.sendBag.selector) {
            (bytes24 sendBag, bytes24 toUnit, bytes24 toOffice, bytes24 payBag) =
                abi.decode(payload[4:], (bytes24, bytes24, bytes24, bytes24));

            _sendBag(dispatcher, s, buildingInstance, unit, sendBag, toUnit, toOffice, payBag);
        }

        if (bytes4(payload) == PostOfficeActions.collectBag.selector) {
            _collectBag(s, dispatcher, buildingInstance, unit);
        }

        if (bytes4(payload) == PostOfficeActions.collectForDelivery.selector) {
            _collectForDelivery(s, dispatcher, buildingInstance, unit);
        }

        if (bytes4(payload) == PostOfficeActions.deliverBags.selector) {
            _deliverBags(s, dispatcher, buildingInstance, unit);
        }

        // -- Will just give all the custody bags to the caller of this action. Used in development during bug fixing
        if (bytes4(payload) == PostOfficeActions.panic.selector) {
            for (uint8 i = 2; i <= MAX_EQUIP_SLOT_INDEX; i++) {
                bytes24 custodyBag = s.getEquipSlot(buildingInstance, i);
                if (bytes4(custodyBag) == Kind.Bag.selector) {
                    (uint8 equipSlot, bool found) = _getNextAvailableEquipSlot(s, unit);
                    require(found, "So spare equip slot found on unit");

                    dispatcher.dispatch(
                        abi.encodeCall(Actions.TRANSFER_BAG, (custodyBag, buildingInstance, unit, equipSlot))
                    );
                    dispatcher.dispatch(abi.encodeCall(Actions.TRANSFER_BAG_OWNERSHIP, (custodyBag, unit)));

                    Consignment storage c = bagToConsignment[custodyBag];
                    if (c.bag != bytes24(0)) {
                        _deleteConsignment(c);
                    }
                }
            }
        }

        _broadcastConsignments(s, dispatcher);

        // revert("No action matches function signature:");
    }

    /*
     * NOTE: Owner of the sendBag and payBag needs to be set to this building prior to this function being called
     */
    function _sendBag(
        Dispatcher dispatcher,
        State state,
        bytes24 buildingInstance,
        bytes24 unit,
        bytes24 sendBag,
        bytes24 toUnit,
        bytes24 toOffice,
        bytes24 payBag
    ) private {
        require(bytes4(sendBag) == Kind.Bag.selector, "Entity selected for send isn't a bag");
        require(bagToConsignment[sendBag].toUnit == bytes24(0), "Cannot send as this bag is tracked for delivery");
        require(bytes4(toUnit) == Kind.MobileUnit.selector, "toUnit is not a MobileUnit");
        require(
            state.getOwner(sendBag) == buildingInstance, "buildingInstance must have ownership of bag before sending"
        );

        {
            // Only works if ownership was transfered to the buildingInstance by the player before calling sendBag
            (uint8 equipSlot, bool found) = _getNextAvailableEquipSlot(state, buildingInstance);
            require(found, "Post office full. Cannot hold any more bags!");
            dispatcher.dispatch(abi.encodeCall(Actions.TRANSFER_BAG, (sendBag, unit, buildingInstance, equipSlot)));
        }

        // Log who and where the bag is destined to
        // TODO check that toOffice is a post office
        Consignment storage c = consignments.push();
        c.fromUnit = unit;
        c.toUnit = toUnit;
        c.toOffice = toOffice;
        c.bag = sendBag;
        c.paymentBag = payBag;
        c.equipee = buildingInstance;
        c.index = consignments.length - 1;
        bagToConsignment[sendBag] = c;

        // payment
        if (payBag != bytes24(0)) {
            require(bytes4(payBag) == Kind.Bag.selector, "Entity selected for payment isn't a bag");
            require(
                state.getOwner(payBag) == buildingInstance,
                "buildingInstance must have ownership of payment bag before sending"
            );
            (uint8 equipSlot, bool found) = _getNextAvailableEquipSlot(state, buildingInstance);
            require(found, "Post office full. Cannot hold any more bags!");

            dispatcher.dispatch(abi.encodeCall(Actions.TRANSFER_BAG, (payBag, unit, buildingInstance, equipSlot)));
        }
    }

    function _collectBag(State s, Dispatcher dispatcher, bytes24 buildingInstance, bytes24 unit) private {
        for (uint8 i = 0; i <= MAX_EQUIP_SLOT_INDEX; i++) {
            bytes24 custodyBag = s.getEquipSlot(buildingInstance, i);
            Consignment storage c = bagToConsignment[custodyBag];

            // If bag belongs to Unit and is at this building.
            // && bagToOffice[custodyBag] == buildingInstance // Add this to if statement to enforce delivery. Without the addressee can collect from drop off point before delivery
            if (c.toUnit == unit) {
                uint8 equipSlot;
                bool found;
                (equipSlot, found) = _getNextAvailableEquipSlot(s, unit);
                require(found, "Unit cannot carry any more bags!");

                dispatcher.dispatch(
                    abi.encodeCall(Actions.TRANSFER_BAG, (custodyBag, buildingInstance, unit, equipSlot))
                );
                dispatcher.dispatch(abi.encodeCall(Actions.TRANSFER_BAG_OWNERSHIP, (custodyBag, unit)));

                // payment (if the recipient picked it up themselves)
                if (c.paymentBag != bytes24(0)) {
                    (equipSlot, found) = _getNextAvailableEquipSlot(s, unit);
                    require(found, "Unit cannot carry any more bags!");

                    dispatcher.dispatch(
                        abi.encodeCall(Actions.TRANSFER_BAG, (c.paymentBag, buildingInstance, unit, equipSlot))
                    );
                    dispatcher.dispatch(abi.encodeCall(Actions.TRANSFER_BAG_OWNERSHIP, (c.paymentBag, unit)));
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

    function _collectForDelivery(State s, Dispatcher dispatcher, bytes24 buildingInstance, bytes24 unit) private {
        // NOTE: Directly setting the state is illegal however, I wanted some way of knowing if the payload decoded correctly
        for (uint8 i = 0; i <= MAX_EQUIP_SLOT_INDEX; i++) {
            bytes24 custodyBag = s.getEquipSlot(buildingInstance, i);
            Consignment storage c = bagToConsignment[custodyBag];
            if (c.toUnit != bytes24(0) && c.toOffice != buildingInstance) {
                uint8 equipSlot;
                bool found;
                (equipSlot, found) = _getNextAvailableEquipSlot(s, unit);
                require(found, "Unit cannot carry any more bags!");

                dispatcher.dispatch(
                    abi.encodeCall(Actions.TRANSFER_BAG, (custodyBag, buildingInstance, unit, equipSlot))
                );
                dispatcher.dispatch(abi.encodeCall(Actions.TRANSFER_BAG_OWNERSHIP, (custodyBag, c.toOffice)));

                c.equipee = unit;
                bagToConsignment[custodyBag] = c;
                consignments[c.index] = c;

                // payment
                if (c.paymentBag != bytes24(0)) {
                    (equipSlot, found) = _getNextAvailableEquipSlot(s, unit);
                    require(found, "Unit cannot carry any more bags!");

                    // NOTE: We purposely don't transfer ownership to the unit as they only gain ownership if they successfully deliver the sendBag
                    dispatcher.dispatch(
                        abi.encodeCall(Actions.TRANSFER_BAG, (c.paymentBag, buildingInstance, unit, equipSlot))
                    );
                    dispatcher.dispatch(abi.encodeCall(Actions.TRANSFER_BAG_OWNERSHIP, (c.paymentBag, c.toOffice)));
                }
            }
        }
    }

    function _deliverBags(State s, Dispatcher dispatcher, bytes24 buildingInstance, bytes24 unit) private {
        for (uint8 i = 0; i <= MAX_EQUIP_SLOT_INDEX; i++) {
            bytes24 bag = s.getEquipSlot(unit, i);
            Consignment storage c = bagToConsignment[bag];
            if (c.toOffice == buildingInstance) {
                uint8 equipSlot;
                bool found;
                (equipSlot, found) = _getNextAvailableEquipSlot(s, buildingInstance);
                require(found, "Post office cannot hold any more bags!");

                dispatcher.dispatch(abi.encodeCall(Actions.TRANSFER_BAG, (bag, unit, buildingInstance, equipSlot)));
                c.equipee = buildingInstance;
                bagToConsignment[bag] = c;
                consignments[c.index] = c;

                // payment
                if (c.paymentBag != bytes24(0)) {
                    // This effectively unlocks the bag for the postman
                    dispatcher.dispatch(abi.encodeCall(Actions.TRANSFER_BAG_OWNERSHIP, (c.paymentBag, unit)));
                }
            }
        }
    }

    function _getNextAvailableEquipSlot(State state, bytes24 equipee) private view returns (uint8, bool) {
        for (uint8 i = 0; i <= MAX_EQUIP_SLOT_INDEX; i++) {
            bytes24 equippedEntity = state.getEquipSlot(equipee, i);
            if (equippedEntity == bytes24(0)) {
                return (i, true);
            }
        }

        return (0, false);
    }

    function _broadcastConsignments(State s, Dispatcher dispatcher) private {
        if (consignmentLedger == bytes24(0)) {
            consignmentLedger = _getConsignmentLedger(s, dispatcher);
        }

        // store the ledger in the name annotation of the entity we own ... again, don't judge me (because Farm's did it first)
        // Base64.encode(abi.encode(consignments))
        s.annotate(consignmentLedger, "name", Base64.encode(abi.encode(consignments)));
    }

    function _getConsignmentLedger(State state, Dispatcher dispatcher) private returns (bytes24 ledger) {
        // we are using a item's "name" annotation as a place to store data that can be read by a client plugin
        // this is a horrible hack and probably makes no sence to look at... don't judge me (because Farm's did it first), we need Books

        // Marked 4 bytes is the item ID
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
