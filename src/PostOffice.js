import ds from "dawnseekers";

export default function update({ selected, world }) {
  const { tiles, seeker } = selected || {};
  const selectedTile = tiles && tiles.length === 1 ? tiles[0] : undefined;
  const selectedBuilding = selectedTile?.building;
  const selectedEngineer = seeker;

  const sendBag = (values) => {
    if (!selectedEngineer) {
      ds.log("no selected engineer");
      return;
    }
    if (!selectedBuilding) {
      ds.log("no selected building");
      return;
    }

    const recipient = values["recipient"];
    if (!recipient) return;

    ds.log(`sending bag at equip slot: ${+values["equipSlot"]}`);
    ds.log(`to unit: ${recipient}`);

    const payload = ds.encodeCall(
      "function sendBag(uint8 equipSlot, bytes24 toUnit)",
      [+values["equipSlot"], recipient]
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
      args: [selectedBuilding.id, selectedEngineer.id, payload], // bytes ordered msb first: menuNum, increment
    });

    ds.log("Use 2");
  };

  return {
    version: 1,
    components: [
      {
        type: "building",
        id: "post-office",
        title: "Hypno Post",
        summary: `Send a bag of items addressed to a particular Unit to the nearest office`,
        content: [
          {
            id: "default",
            type: "inline",
            html: `
                <h1>Main Menu</h1>
                <p>Please select from the following options</p>
              `,
            buttons: [
              {
                text: `Send bag`,
                type: "toggle",
                content: "sendBag",
                disabled: false,
              },
              {
                text: `Collect bag`,
                type: "toggle",
                content: "collectBag",
                disabled: false,
              },
            ],
          },
          {
            id: "sendBag",
            type: "inline",
            html: `
              <h2>Send bag</h2>
              <label>Select equip slot</label>
              <select name="equipSlot">
                <option>0</option>
                <option>1</option>
                <option>2</option>
                <option>3</option>
              </select>
              <label>Recipient's unit ID</label>
              <input type="text" name="recipient"></input>
              <button type="submit" style="width:100%; padding:5px; border-radius: 10px;">Send</button>
          </select>
            `,
            submit: sendBag,
            buttons: [
              // {
              //   text: `Send`,
              //   type: "action",
              //   action: sendBag,
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
