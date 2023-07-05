import ds from "dawnseekers";

export default function update({ selected, world }) {
  const { tiles, mobileUnit } = selected || {};
  const selectedTile = tiles && tiles.length === 1 ? tiles[0] : undefined;
  const selectedBuilding = selectedTile?.building;
  const selectedUnit = mobileUnit;

  const kindID = selectedBuilding.kind?.id;
  const worldPostOffices = world.buildings.filter(
    (b) => b.kind?.id == kindID && b.id != selectedBuilding.id
  );

  const allSeekers = world.tiles.flatMap((tile) => tile.seekers);

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
        title: `Hypno Post (${selectedBuilding.id.slice(-6 * 2)})`,
        summary: `Send a bag of items addressed to a particular Unit and choose which post office to have it delivered to`,
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
                text: `Collect bags`,
                type: "toggle",
                content: "collectBag",
                disabled: false,
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
                  ${allSeekers.map(
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
            id: "collectBag",
            type: "inline",
            html: `
              <h2>Collect Bag(s)</h2>
            `,
            buttons: [
              {
                text: `Collect`,
                type: "action",
                action: collectBag,
                disabled: false,
              },
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
