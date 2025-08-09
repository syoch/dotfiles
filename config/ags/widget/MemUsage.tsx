import { createBinding } from "ags";
import { readFileAsync } from "ags/file";
import { getter, property, register } from "ags/gobject";
import { Gtk } from "ags/gtk4";
import GObject from "gi://GObject?version=2.0";

@register({ GTypeName: "MemoryUsage" })
class MemoryUsage extends GObject.Object {
  @property(Number) phys_avail = 0;
  /* @getter(Number)
  get phys_avail() { return this.phys_avail; } */

  @property(Number) phys_total = 0;
  /* @getter(Number)
  get phys_total() { return this.phys_total; } */

  @property(Number) swap_avail = 0;
  /* @getter(Number)
  get swap_avail() { return this.swap_avail; } */

  @property(Number) swap_total = 0;
  /* @getter(Number)
  get swap_total() { return this.swap_total; } */

  async sync_memory_usage() {
    type MemInfo = {
      MemTotal: number;
      MemFree: number;
      MemAvailable: number;
      SwapTotal: number;
      SwapFree: number;
    };

    const f = await readFileAsync("/proc/meminfo");

    const table = f
      .split("\n")
      .map((line) => {
        const [k, v] = line.split(":");
        if (!k || !v) {
          return [k, v];
        }

        const size_str = v.replace(/\s+(\d+)\s*kB\s*/g, "$1");
        const size = Number(size_str) * 1024;

        return [k.trim(), size];
      })
      .reduce(
        (a, [k, v]) => ({
          ...a,
          [k]: v,
        }),
        {}
      ) as MemInfo;

    // MemTotal is the total usable ram (i.e. physical ram minus a few reserved bits and the kernel binary code)
    this.phys_total = table.MemTotal; // 256MB reserved for kernel
    this.phys_avail = table.MemAvailable;
    this.swap_total = table.SwapTotal;
    this.swap_avail = table.SwapTotal - table.SwapFree;

    this.notify("phys_avail");
    this.notify("phys_total");
    this.notify("swap_avail");
    this.notify("swap_total");
  }

  constructor() {
    super();

    setInterval(async () => {
      await this.sync_memory_usage();
    }, 1000);
  }
}

function FormatSize(size: number) {
  const units = ["B", "KB", "MB", "GB", "TB"];
  let unit = 0;

  while (size > 1024 && unit < units.length) {
    size /= 1024;
    unit++;
  }

  return `${size.toFixed(2)} ${units[unit]}`.trim();
}

export function MemoryUsageWidget() {
  const mem = new MemoryUsage();

  const phy_free = createBinding(mem, "phys_avail").as(FormatSize);
  const swap_free = createBinding(mem, "swap_avail").as(FormatSize);
  const used_percentage = createBinding(mem, "phys_total").as((_) => {
    const total_memory = mem.phys_total + mem.swap_total;
    const free_memory = mem.phys_avail + mem.swap_avail;

    const used_memory = total_memory - free_memory;
    return ((used_memory / total_memory) * 100);
  });

  const text = used_percentage.as((perc) => {
    return `${perc.toFixed(0)}%`;
  });
  const tooltip = used_percentage.as((perc) => {
    return [
      "Physical Memory:",
      `  Total: ${FormatSize(mem.phys_total)}`,
      `  Available: ${phy_free.get()}`,
      "Swap Memory:",
      `  Total: ${FormatSize(mem.swap_total)}`,
      `  Available: ${swap_free.get()}`,
      `Used: ${perc} %`,
    ].join("\n");
  });

  return (
    <box class="MemoryUsage" tooltipText={tooltip}>
      <label
        label={text}
        tooltipMarkup={tooltip}
      />
    </box>
  );
}