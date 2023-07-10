// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import {Game} from "@ds/Game.sol";
import {Actions} from "@ds/actions/Actions.sol";
import {Node, Schema, State} from "@ds/schema/Schema.sol";
import {ItemUtils, ItemConfig} from "@ds/utils/ItemUtils.sol";
import {BuildingUtils, BuildingConfig, Material, Input, Output} from "@ds/utils/BuildingUtils.sol";
import {ExampleMenu} from "../src/ExampleMenu.sol";
import {PostOffice} from "../src/PostOffice.sol";

using Schema for State;

// Generating a random number in nodejs
/*

function genRandomNumber(byteCount, radix) {
  return BigInt('0x' + crypto.randomBytes(byteCount).toString('hex')).toString(radix)
}
genRandomNumber(8, 10)

*/

// BUILDING_KIND_EXTENSION_ID=4594675476523367340 GAME_ADDRESS=0x1D8e3A7Dc250633C192AC1bC9D141E1f95C419AB forge script script/Deploy.sol --broadcast --verify --rpc-url "https://network-ds-test.dev.playmint.com"

contract Deployer is Script {
    function setUp() public {}

    function run() public {
        uint256 playerDeploymentKey = vm.envOr(
            "PLAYER_DEPLOYMENT_KEY", uint256(0x24941b1db84a65ded87773081c700c22f50fe26c8f9d471dc480207d96610ffd)
        );

        address gameAddr = vm.envOr("GAME_ADDRESS", address(0x1D8e3A7Dc250633C192AC1bC9D141E1f95C419AB));
        Game ds = Game(gameAddr);

        // * it must be between 1 and 9223372036854775807 (8 bytes 64bit)
        // * if someone else has already registered the number, then you can't have it
        uint64 extensionID = uint64(vm.envUint("BUILDING_KIND_EXTENSION_ID"));

        // connect as the player...
        vm.startBroadcast(playerDeploymentKey);

        // deploy
        bytes24 postOffice = registerPostOffice(ds, extensionID);

        console2.log("postOffice", uint256(bytes32(postOffice)));

        vm.stopBroadcast();
    }

    // register a new
    function registerPostOffice(Game ds, uint64 extensionID) public returns (bytes24 buildingKind) {
        // find the base item ids we will use as inputs for our hammer factory
        bytes24 none = 0x0;
        bytes24 glassGreenGoo = ItemUtils.GlassGreenGoo();
        bytes24 beakerBlueGoo = ItemUtils.BeakerBlueGoo();
        bytes24 flaskRedGoo = ItemUtils.FlaskRedGoo();

        // register a new building kind
        return BuildingUtils.register(
            ds,
            BuildingConfig({
                id: extensionID,
                name: "Post Office V2 (Under Construction)",
                materials: [
                    Material({quantity: 10, item: glassGreenGoo}), // these are what it costs to construct the factory
                    Material({quantity: 10, item: beakerBlueGoo}),
                    Material({quantity: 10, item: flaskRedGoo}),
                    Material({quantity: 0, item: none})
                ],
                inputs: [
                    Input({quantity: 0, item: none}),
                    Input({quantity: 0, item: none}),
                    Input({quantity: 0, item: none}),
                    Input({quantity: 0, item: none})
                ],
                outputs: [
                    Output({quantity: 0, item: none}) // this is the output that can be crafted given the inputs
                ],
                implementation: address(new PostOffice()),
                plugin: vm.readFile("src/PostOffice.js")
            })
        );
    }
}
