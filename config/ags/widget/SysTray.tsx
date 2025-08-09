import { createBinding, For } from "ags";
import AstalTray from "gi://AstalTray?version=0.1";


type TrayIconProps = {
  item: AstalTray.TrayItem,
}

function TrayIcon({ item }: TrayIconProps) {
  const tooltip_markup = createBinding(item, "tooltipMarkup").as((markup) => markup ?? "");
  return (
    <menubutton
      tooltipMarkup={tooltip_markup}
      menuModel={item.menuModel}
    >
      <image
        iconName={item.iconName}
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