import { createBinding, For } from "ags";
import app from "ags/gtk4/app";
import AstalTray from "gi://AstalTray?version=0.1";
import { exit } from "system";

app.start({
  instanceName: "Test",
  main() {
    const tray = AstalTray.get_default();
    const items = tray.items;
    console.log(items);
    for (const item of items) {
      console.log(item);
    }

    exit(0);
  },
});
