import ds from "dawnseekers";

export default function update({ selected, world }) {
  const { tiles, seeker } = selected || {};
  const selectedTile = tiles && tiles.length === 1 ? tiles[0] : undefined;
  const selectedBuilding = selectedTile?.building;
  const selectedEngineer = seeker;

  const getEmptyBag = () => {
    if (!selectedEngineer) {
      ds.log("no selected engineer");
      return;
    }

    const payload = ds.encodeCall("function getEmptyBag()", []);

    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, selectedEngineer.id, payload],
    });
  };

  const logAddresses = () => {
    ds.log(`unit: ${selectedEngineer.id}`);
    ds.log(`office: ${selectedBuilding.id}`);
  };

  const sendBag = (values) => {
    if (!selectedEngineer) {
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

    ds.log(`sending bag at equip slot: ${+values["equipSlot"]}`);
    ds.log(`to unit: ${toUnit}`);
    ds.log(`to office: ${toOffice}`);

    const payload = ds.encodeCall(
      "function sendBag(uint8 equipSlot, bytes24 toUnit, bytes24 toOffice)",
      [+values["equipSlot"], toUnit, toOffice]
    );

    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, selectedEngineer.id, payload],
    });
  };

  const collectBag = () => {
    if (!selectedEngineer) {
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
      args: [selectedBuilding.id, selectedEngineer.id, payload],
    });

    ds.log("Use 2");
  };

  const collectBagsForDelivery = () => {
    ds.log("collectBagsForDelivery");

    const payload = ds.encodeCall("function collectForDelivery()", []);

    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, selectedEngineer.id, payload],
    });
  };

  const deliverBags = () => {
    ds.log("deliverBags");

    const payload = ds.encodeCall("function deliverBags()", []);

    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, selectedEngineer.id, payload],
    });
  };

  return {
    version: 1,
    components: [
      {
        type: "building",
        id: "post-office",
        title: "Hypno Post",
        summary: `Send a bag of items addressed to a particular Unit and choose which post office to have it delivered to`,
        content: [
          {
            id: "default",
            type: "inline",
            html: `
                <h2>Main Menu</h2>
                <p>Please select from the following options</p>
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
                text: `Log addresses`,
                type: "action",
                action: logAddresses,
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
              <p>Select bag number</p>
              <select name="equipSlot">
                ${selectedEngineer.bags.map(
                  (equipSlot, index) =>
                    `<option value=${equipSlot.key}>${index + 1}</option>`
                )}
              </select>
              <p>Recipient's unit ID</p>
              <input type="text" name="toUnit"></input>
              <p>Destination office ID (leave blank for this office)</p>
              <input type="text" name="toOffice"></input>
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
