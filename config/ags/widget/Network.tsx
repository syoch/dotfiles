import { createBinding, With } from "ags";
import AstalNetwork from "gi://AstalNetwork?version=0.1";


const network = AstalNetwork.get_default();

function Wired() {
  const wired = createBinding(network, "wired");

  const markup = wired.as((x) => {
    return [
      "Wired Connection",
      "State: " + x.state,
    ].join("\n");
  });

  return (
    <box visible={wired.as(Boolean)} tooltipMarkup={markup} class="Wired">
      <image
        iconName="network-wired-symbolic"
      />
    </box>
  );
}
function Wifi() {
  const wifi = createBinding(network, "wifi");

  const iconName = wifi.as((x) => x.iconName ?? "network-wireless");
  const ssid = wifi.as((x) => x.ssid ? `SSID: ${x.ssid}` : "No SSID");

  return (
    <box visible={wifi.as(Boolean)} tooltipMarkup={ssid} class="Wifi">
      <image
        iconName="network-wireless-symbolic"
      />
    </box>
  );
}

export function Network() {
  const wired_enabled = createBinding(network, "primary")
    .as(x => x == AstalNetwork.Primary.WIRED);

  return (
    <With value={wired_enabled}>
      {p => p ? <Wired /> : <Wifi />}
    </With>
  );
}