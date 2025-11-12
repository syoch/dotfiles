import { createBinding, For } from "ags";
import AstalTray from "gi://AstalTray?version=0.1";


type TrayIconProps = {
  item: AstalTray.TrayItem,
}

function TrayIcon({ item }: TrayIconProps) {
  return (
    <menubutton
      tooltipMarkup={createBinding(item, "tooltipMarkup")}
      menuModel={createBinding(item, "menuModel")}
      onRealize={(self) => {
        createBinding(item, "actionGroup").as(ag => self.insert_action_group("dbusmenu", ag));
        self.insert_action_group("dbusmenu", item.action_group);
      }
      }
    >
      <image
        gicon={createBinding(item, "gicon")}
      />
    </menubutton>
  );
}



export function SysTray() {
  const tray = AstalTray.get_default();
  const items = createBinding(tray, "items");
  return (
    <box class="SysTray">
      <For each={items}>
        {(item, i) => (
          <TrayIcon item={item} />
        )}
      </For>
    </box>
  );
}