import ds from "dawnseekers";

export default function update({ selected, world }) {
  const { tiles, seeker } = selected || {};
  const selectedTile = tiles && tiles.length === 1 ? tiles[0] : undefined;
  const selectedBuilding = selectedTile?.building;
  const selectedEngineer = seeker;

  const use1 = () => {
    if (!selectedEngineer) {
      ds.log("no selected engineer");
      return;
    }
    if (!selectedBuilding) {
      ds.log("no selected building");
      return;
    }

    const payload = ds.encodeCall(
      "function menuAction(uint8 menuNum, uint64 inc)",
      [1, 2]
    );

    ds.dispatch({
      name: "BUILDING_USE",
      args: [selectedBuilding.id, selectedEngineer.id, payload],
    });

    ds.log("Use 1");
  };

  const use2 = () => {
    if (!selectedEngineer) {
      ds.log("no selected engineer");
      return;
    }
    if (!selectedBuilding) {
      ds.log("no selected building");
      return;
    }

    const payload = ds.encodeCall(
      "function menuAction(uint8 menuNum, uint64 inc)",
      [2, 4]
    );

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
        id: "example-menu",
        title: "Example Menu",
        summary: `A small example of a context switching menu`,
        content: [
          {
            id: "default",
            type: "inline",
            html: `
                <h1>Main Menu</h1>
                <p>Please select a sub menu from the list below</p>
              `,
            buttons: [
              {
                text: `Menu 1`,
                type: "toggle",
                content: "menu1",
                disabled: false,
              },
              {
                text: `Menu 2`,
                type: "toggle",
                content: "menu2",
                disabled: false,
              },
            ],
          },
          {
            id: "menu1",
            type: "inline",
            html: `
              <h1>Menu 1</h1>
            `,
            buttons: [
              {
                text: `Use`,
                type: "action",
                action: use1,
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
            id: "menu2",
            type: "inline",
            html: `
              <h1>Menu 2</h1>
            `,
            buttons: [
              {
                text: `Use`,
                type: "action",
                action: use2,
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
