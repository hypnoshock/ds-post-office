import ds from "downstream";

export default function update({ selected, world }) {
  const { tiles, mobileUnit } = selected || {};
  const selectedTile = tiles && tiles.length === 1 ? tiles[0] : undefined;
  const selectedBuilding = selectedTile?.building;
  const selectedUnit = mobileUnit;

  const kindID = selectedBuilding.kind?.id;
  const worldPostOffices = world.buildings.filter(
    (b) => b.kind?.id == kindID && b.id != selectedBuilding.id
  );

  const consignmentLedger = getConsignmentLedger(world.buildings);
  const packagesWaiting =
    selectedUnit &&
    consignmentLedger.reduce((acc, entry) => {
      return entry.toUnit == selectedUnit.id &&
        entry.equipee == selectedBuilding.id
        ? acc + 1
        : acc;
    }, 0);

  const allUnits = world.tiles.flatMap((tile) => tile.mobileUnits);

  const getEmptyBag = () => {
    if (!selectedUnit) {
      ds.log("no selected engineer");
      return;
    }

    const payload = ds.encodeCall("function getEmptyBag()", []);

    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, selectedUnit.id, payload],
    });
  };

  const logAddresses = () => {
    ds.log(`unit: ${selectedUnit.id}`);
    ds.log(`office: ${selectedBuilding.id}`);
  };

  const panic = () => {
    const payload = ds.encodeCall("function panic()", []);

    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, selectedUnit.id, payload],
    });
  };

  const sendBag = (values) => {
    if (!selectedUnit) {
      ds.log("no selected engineer");
      return;
    }
    if (!selectedBuilding) {
      ds.log("no selected building");
      return;
    }

    const toUnit = values["toUnit"];
    if (!toUnit) return;

    const toOffice = values["toOffice"] || selectedBuilding.id;
    const sendEquipSlot = +values["sendEquipSlot"];
    const payEquipSlot = +values["payEquipSlot"];

    ds.log(`to unit: ${toUnit}`);
    ds.log(`to office: ${toOffice}`);
    ds.log(`sendEquipSlot: ${sendEquipSlot} pay slot: ${payEquipSlot}`);

    const payload = ds.encodeCall(
      "function sendBag(uint8 sendEquipSlot, bytes24 toUnit, bytes24 toOffice, uint8 payEquipSlot)",
      [sendEquipSlot, toUnit, toOffice, payEquipSlot]
    );

    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, selectedUnit.id, payload],
    });
  };

  const collectBag = () => {
    if (!selectedUnit) {
      ds.log("no selected engineer");
      return;
    }
    if (!selectedBuilding) {
      ds.log("no selected building");
      return;
    }

    const payload = ds.encodeCall("function collectBag()", []);

    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, selectedUnit.id, payload],
    });

    ds.log("Use 2");
  };

  const collectBagsForDelivery = () => {
    ds.log("collectBagsForDelivery");

    const payload = ds.encodeCall("function collectForDelivery()", []);

    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, selectedUnit.id, payload],
    });
  };

  const deliverBags = () => {
    ds.log("deliverBags");

    const payload = ds.encodeCall("function deliverBags()", []);

    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, selectedUnit.id, payload],
    });
  };

  return {
    version: 1,
    components: [
      {
        type: "building",
        id: "post-office",
        title: `Hypno Post V2 (${selectedBuilding.id.slice(-6 * 2)})`,
        summary: `Send a bag of items addressed to a particular Unit and choose which post office to have it delivered to. ${
          packagesWaiting
            ? `\nThere are ${packagesWaiting} package${
                packagesWaiting > 1 ? "s" : ""
              } waiting for you.`
            : ""
        }`,
        content: [
          {
            id: "default",
            type: "inline",
            html: `
                <h2>Main Menu</h2>
                <p>Please select from the following options</p>
                <p>This post office ID: ${selectedBuilding.id.slice(-6 * 2)}</p>
              `,
            buttons: [
              {
                text: `I'm a Customer`,
                type: "toggle",
                content: "customerMenu",
                disabled: false,
              },
              {
                text: `I'm a Postman`,
                type: "toggle",
                content: "postmanMenu",
                disabled: false,
              },
              {
                text: `Help`,
                type: "toggle",
                content: "helpMenu",
                disabled: false,
              },
              // {
              //   text: `Panic`,
              //   type: "action",
              //   action: panic,
              //   disabled: false,
              // },
            ],
          },
          {
            id: "helpMenu",
            type: "inline",
            html: `
                <h2>Help</h2>
                <div>
                  <p>This building is still in development and a bit tricky to use at the moment!</p>
                </div>
              `,
            buttons: [
              // {
              //   text: `Log addresses`,
              //   type: "action",
              //   action: logAddresses,
              //   disabled: false,
              // },
              {
                text: `Return to main menu`,
                type: "toggle",
                content: "default",
                disabled: false,
              },
            ],
          },
          {
            id: "customerMenu",
            type: "inline",
            html: `
                <h2>Customer</h2>
                <p>From this menu you can send bags or collect any bags that are addressed to you at this building</p>
              `,
            buttons: [
              {
                text: `Send bag`,
                type: "toggle",
                content: "sendBag",
                disabled: false,
              },
              {
                text: `Collect bag${
                  packagesWaiting && packagesWaiting > 1 ? "s" : ""
                }`,
                type: "action",
                action: collectBag,
                disabled: !packagesWaiting || packagesWaiting == 0,
              },
              {
                text: `Get empty bag`,
                type: "action",
                action: getEmptyBag,
                disabled: false,
              },
              {
                text: `Return to main menu`,
                type: "toggle",
                content: "default",
                disabled: false,
              },
            ],
          },
          {
            id: "sendBag",
            type: "inline",
            html: `
              <h2>Send bag</h2>
              <p>Select bag number to send</p>
              <select name="sendEquipSlot">
                ${selectedUnit?.bags.map(
                  (equipSlot, index) =>
                    `<option value=${equipSlot.key}>${index + 1}</option>`
                )}
              </select>
              <p>Select bag number for payment</p>
              <select name="payEquipSlot">
                <option value='255'>No payment</option>
                ${selectedUnit?.bags.map(
                  (equipSlot, index) =>
                    `<option value=${equipSlot.key}>${index + 1}</option>`
                )}
              </select>
              <p>Recipient</p>
              <select name="toUnit">
                  <option value='${selectedUnit?.id}'>Yourself</option>
                  ${allUnits.map(
                    (s) =>
                      `<option value='${s.id}'>${
                        s.name ? s.name.value : s.id.slice(-8)
                      }</option>`
                  )}
              </select>
              <p>Destination office ID</p>
              <select name="toOffice">
                  <option value=''>This office</option>
                  ${worldPostOffices.map(
                    (building) =>
                      `<option value='${building.id}'>${building.id.slice(
                        -6 * 2
                      )}</option>`
                  )}
              </select>
              <button type="submit" style="width:100%; padding:5px; border-radius: 10px;">Send</button>
            `,
            submit: sendBag,
            buttons: [
              {
                text: `Back`,
                type: "toggle",
                content: "customerMenu",
                disabled: false,
              },
            ],
          },
          {
            id: "postmanMenu",
            type: "inline",
            html: `
                <h2>Postman</h2>
                <p>From this menu you collect bags for delivery or drop off bags</p>
              `,
            buttons: [
              {
                text: `Collect bags`,
                type: "action",
                action: collectBagsForDelivery,
                disabled: false,
              },
              {
                text: `Deliver bags`,
                type: "action",
                action: deliverBags,
                disabled: false,
              },
              {
                text: `Return to main menu`,
                type: "toggle",
                content: "default",
                disabled: false,
              },
            ],
          },
        ],
      },
    ],
  };
}

function toHexString(bytes) {
  const hexString = Array.from(bytes, (byte) => {
    return ("0" + (byte & 0xff).toString(16)).slice(-2);
  }).join("");
  return hexString.length > 0 ? "0x" + hexString : "";
}

// No atob function in quickJS.
function base64_decode(s) {
  var base64chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  // remove/ignore any characters not in the base64 characters list
  //  or the pad character -- particularly newlines
  s = s.replace(new RegExp("[^" + base64chars.split("") + "=]", "g"), "");

  // replace any incoming padding with a zero pad (the 'A' character is zero)
  var p =
    s.charAt(s.length - 1) == "="
      ? s.charAt(s.length - 2) == "="
        ? "AA"
        : "A"
      : "";
  var r = "";
  s = s.substr(0, s.length - p.length) + p;

  // increment over the length of this encoded string, four characters at a time
  for (var c = 0; c < s.length; c += 4) {
    // each of these four characters represents a 6-bit index in the base64 characters list
    //  which, when concatenated, will give the 24-bit number for the original 3 characters
    var n =
      (base64chars.indexOf(s.charAt(c)) << 18) +
      (base64chars.indexOf(s.charAt(c + 1)) << 12) +
      (base64chars.indexOf(s.charAt(c + 2)) << 6) +
      base64chars.indexOf(s.charAt(c + 3));

    // split the 24-bit number into the original three 8-bit (ASCII) characters
    r += String.fromCharCode((n >>> 16) & 255, (n >>> 8) & 255, n & 255);
  }
  // remove any zero pad that was added to make this a multiple of 24 bits
  return r.substring(0, r.length - p.length);
}

function getConsignmentLedger(buildings) {
  // HACK: We are storing the ledger data as the name of the consignmentLedger item
  //       When books are implemented, they will enable the ability to store arbitrary state
  const consignmentOffices = buildings.filter(
    (b) => b.kind?.id == "0xbe92755c00000000000000000000000051a26be173f7f602"
  );
  if (consignmentOffices.length == 0) return [];

  const base64 = consignmentOffices[0].kind.outputs[0]?.item?.name?.value;
  if (!base64) return [];

  const binaryString = base64_decode(base64);

  const consignmentLedgerBytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    consignmentLedgerBytes[i] = binaryString.charCodeAt(i);
  }

  const numConsignments = consignmentLedgerBytes[63];

  // We we had the ethers decoder....
  // return decoder.decode(['tuple(bytes24, bytes24, bytes24, bytes24, bytes24, bytes24, uint8)[]'], bytes)[0];

  const structLen = 32 * 7;
  const ledger = [];
  for (var i = 0; i < numConsignments; i++) {
    ledger.push({
      fromUnit: toHexString(
        new Uint8Array(
          consignmentLedgerBytes.buffer,
          structLen * i + 32 * 2,
          24
        )
      ),
      toUnit: toHexString(
        new Uint8Array(
          consignmentLedgerBytes.buffer,
          structLen * i + 32 * 3,
          24
        )
      ),
      toOffice: toHexString(
        new Uint8Array(
          consignmentLedgerBytes.buffer,
          structLen * i + 32 * 4,
          24
        )
      ),
      bag: toHexString(
        new Uint8Array(
          consignmentLedgerBytes.buffer,
          structLen * i + 32 * 5,
          24
        )
      ),
      paymentBag: toHexString(
        new Uint8Array(
          consignmentLedgerBytes.buffer,
          structLen * i + 32 * 6,
          24
        )
      ),
      equipee: toHexString(
        new Uint8Array(
          consignmentLedgerBytes.buffer,
          structLen * i + 32 * 7,
          24
        )
      ),
      equipSlot: toHexString(
        new Uint8Array(
          consignmentLedgerBytes.buffer,
          structLen * i + 32 * 8,
          24
        )
      ),
    });
  }

  return ledger;
}
