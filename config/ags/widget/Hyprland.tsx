import AstalHyprland from "gi://AstalHyprland?version=0.1";
import { createBinding, For } from "ags";

const hypr = AstalHyprland.get_default();

type WSProps = {
  ws: AstalHyprland.Workspace;
}
function Workspace({ ws }: WSProps) {
  const is_focused = createBinding(hypr, "focusedWorkspace").
    as(x => x === ws);

  const monitor_color_table = [
    "#8cc",
    "#c8c",
    "#cc8",
  ];

  const color_rgb = monitor_color_table[ws.monitor.id % monitor_color_table.length];

  return (
    <button
      class={is_focused.as(x => x ? "focused" : "unfocused")}
      onClicked={() => ws.focus()}
      css={`color: ${color_rgb};`}
    >
      {`${ws.id}`}
    </button>
  );
}

export function Workspaces() {
  const workspaces = createBinding(hypr, "workspaces").
    as(x => x.filter(x => x.id > 0).
      sort((a, b) => a.id - b.id));

  return (
    <box class="Workspaces">
      <For each={workspaces}>
        {(ws, i) =>
          (<Workspace ws={ws} />)
        }
      </For>
    </box>
  )
}

export function FocusedClient() {
  const focused = createBinding(hypr, "focusedClient").
    as(x => x?.title ?? "No focused client");
  return (
    <box class="Focused" visible>
      <label label={focused} />
    </box>
  );
}