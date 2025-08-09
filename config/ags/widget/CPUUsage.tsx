import { createBinding } from "ags";
import { readFileAsync } from "ags/file";
import { property, register } from "ags/gobject";
import GLib from "gi://GLib?version=2.0";
import GObject from "gi://GObject?version=2.0";

@register({ GTypeName: "CPUCoreUsage" })
class CPUCoreUsage extends GObject.Object {
  @property(Number) usage = 0;

  constructor(core: number) {
    super();

    let last_sum = 0;
    let last_idle = 0;

    setInterval(async () => {
      const f = await readFileAsync("/proc/stat");
      const cpu_line = f
        .split("\n")
        .filter((l) => l.startsWith(`cpu${core}`))[0];

      const [_, ...times] = cpu_line.split(" ").map(Number);
      const idle = times[3];
      const total = times.reduce((a, b) => a + b);

      const delta_total = total - last_sum;
      last_sum = total;

      const delta_idle = idle - last_idle;
      last_idle = idle;

      const usage = 1 - delta_idle / delta_total;

      this.usage = usage;
      this.notify("usage");
    }, 100);
  }
}

@register({ GTypeName: "CPUUsage" })
class CPUUsage extends GObject.Object {
  @property(Number)
  usage: number = 0;

  //* Singleton
  static instance: CPUUsage;

  static get_default() {
    if (!CPUUsage.instance) {
      CPUUsage.instance = new CPUUsage();
    }

    return CPUUsage.instance;
  }


  constructor() {
    super();

    const cores = GLib.get_num_processors();
    const usages = Array.from({ length: cores }, (_, i) => new CPUCoreUsage(i));

    let usage_percentages = Array.from({ length: cores }, () => 0);
    usages.map((usage, i) =>
      createBinding(usage, "usage").subscribe(() => {
        usage_percentages[i] = usage.usage;
      })
    );

    setInterval(() => {
      this.usage = usage_percentages.reduce((a, b) => a + b, 0) / cores;
      this.notify("usage");
    }, 1000);
  }
}

export function CPUUsageWidget() {
  const cpu = CPUUsage.get_default();
  const usage = createBinding(cpu, "usage");
  return (
    <box class="CPUUsage" tooltipMarkup={usage.as(x => `CPU: ${(x * 100).toFixed(3)} %`)}>
      <label label={usage.as((u) => `${Math.floor(u * 100)} %`)} />
    </box>
  );
}