import { Astal, Gtk, Gdk } from "ags/gtk4";
import { FocusedClient, Workspaces } from "./Hyprland";
import { createPoll } from "ags/time";
import AstalBattery from "gi://AstalBattery";
import Mpris from "gi://AstalMpris";
import { Accessor, createBinding, createComputed, For } from "ags";
import { MemoryUsageWidget } from "./MemUsage";
import { CPUUsageWidget } from "./CPUUsage";
import { SysTray } from "./SysTray";
import { Network } from "./Network";



function BatteryLevel() {
  const bat = AstalBattery.get_default();
  const is_present = createBinding(bat, "isPresent");
  const icon = createBinding(bat, "batteryIconName");

  const percentage = createBinding(bat, "percentage").as((p) => 100 * p);
  const text = createComputed([percentage], (perc) => {
    return `${perc.toFixed(0)}%`;
  });

  return (
    <box
      class="Battery"
    >
      <label label={text} />
    </box >
  );
}


function Time({ format = "%H:%M - %A %e." }) {
  const time = createPoll("", 1000, [
    'date',
    `+${format}`,
  ]);

  return (
    <label class="Time" label={time} />
  );
}

function Media({ i, player }: { i: Accessor<number>, player: Mpris.Player }) {
  const title = createBinding(player, "title");
  const available = createBinding(player, "available");


  return (
    <box class="Media" visible={available}>
      <button class="Title" onClicked={() => player.play_pause()} tooltip_text={title.as(x => `Player ${x}`)}>
        <label label={i.as(x => x.toString())}></label>
      </button>
    </box>
  );
}

function MediaPlayer() {
  const mpris = Mpris.get_default();
  const players = createBinding(mpris, "players");

  return (
    <box class="MediaPlayer">
      <For each={players}>
        {(player, i) =>
          (<Media i={i} player={player} />)
        }
      </For>
    </box>
  );
}


export default function Bar(monitor: Gdk.Monitor) {
  const { TOP, LEFT, RIGHT } = Astal.WindowAnchor;

  return (
    <window
      visible
      class="Bar"
      gdkmonitor={monitor}
      exclusivity={Astal.Exclusivity.EXCLUSIVE}
      anchor={TOP | LEFT | RIGHT}
    >
      <Gtk.CenterBox orientation={Gtk.Orientation.HORIZONTAL}>
        <Workspaces $type="start" />

        <MediaPlayer $type="center" />

        <box $type="end">
          <SysTray />
          <Network />

          <CPUUsageWidget />
          <MemoryUsageWidget />
          <BatteryLevel />

          <Time format="%m/%d %H:%M:%S" />
        </box>
      </Gtk.CenterBox>
    </window>
  );
}
