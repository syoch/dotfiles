hl.monitor({
  output = "desc:AU Optronics 0xB78F",
  mode = "1920x1080@60.16",
  position = "4373x0",
  scale = 1.0,
});
hl.monitor({
  output = "desc:BOE Display demoset-1",
  mode = "1920x1080@60.0",
  position = "533x0",
  scale = 1.0,
});
hl.monitor({
  output = "desc:Acer Technologies SB240Y 0x1040716F",
  mode = "1920x1080@74.97",
  position = "2453x0",
  scale = 1.0,
});

hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

hl.on("hyprland.start", function()
  hl.exec_cmd("wezterm")
  hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=Hyprland")
  hl.exec_cmd("systemctl --user start desktop-session.target")
  hl.exec_cmd("fcitx5 -d")
end)

hl.config({
  general = {
    gaps_in = 5,
    gaps_out = 5,

    border_size = 1,

    col = {
      active_border = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
      inactive_border = "rgba(595959aa)",
    },

    resize_on_border = false,

    -- layout = "dwindle",
  },
  decoration = {
    rounding = 8,
    blur = {
      enabled = true,
      size = 6,
      passes = 1,
      brightness = 0.4,
      ignore_opacity = true
    }
  },
  input = {
    kb_layout = "jp",
    sensitivity = 0.1,
    touchpad = {
      natural_scroll = true
    }
  }
});
hl.curve("myBezier", {
  type = "bezier",
  points = { { 0.05, 0.9 }, { 0.1, 1.05 } },
});
hl.animation({ leaf = "windows", bezier = "myBezier", enabled = true, speed = 7 });
hl.animation({ leaf = "windowsOut", bezier = "myBezier", enabled = true, speed = 7, style = "popin 80%" });

local mainMod = "SUPER"
-- defined launchers
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd("wezterm-gui"));
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("thunar"));
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("wofi --show drun -I"));
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"));
hl.bind("Print", hl.dsp.exec_cmd("~/.config/hypr/screenshot.sh"));

-- window operations
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag());
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize());
hl.bind(mainMod .. " + CTRL + SHIFT + C", hl.dsp.window.kill());
hl.bind(mainMod .. " + CTRL + V", hl.dsp.window.float());
hl.bind(mainMod .. " + CTRL + F", hl.dsp.window.fullscreen());
hl.bind(mainMod .. " + CTRL + T", hl.dsp.group.toggle());

-- navigation
hl.bind(mainMod .. " + left", hl.dsp.focus { direction = "left" });
hl.bind(mainMod .. " + right", hl.dsp.focus { direction = "right" });
hl.bind(mainMod .. " + up", hl.dsp.focus { direction = "up" });
hl.bind(mainMod .. " + down", hl.dsp.focus { direction = "down" });

-- workspace operations
for i = 1, 10 do
  local key = i % 10 -- 10 maps to key 0
  hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
  hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- special workspace
hl.workspace_rule({ workspace = "special:sp1", on_created_empty = "wezterm", gaps_out = 15 })
hl.bind(mainMod .. " + SHIFT + A", hl.dsp.workspace.toggle_special("sp1"))
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.window.move({ workspace = "special:sp1" }))
hl.workspace_rule({ workspace = "special:sp2", on_created_empty = "wezterm", gaps_out = 15 })
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.workspace.toggle_special("sp2"))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.window.move({ workspace = "special:sp2" }))


-- window rules
hl.window_rule({
  name     = "fix-xwayland-drags",
  match    = {
    class      = "^$",
    title      = "^$",
    xwayland   = true,
    float      = true,
    fullscreen = false,
    pin        = false,
  },

  no_focus = true,
})

hl.window_rule({
  name  = "Float (by class)",
  match = { class = "^(firefox|wlfreerdp|Qemu-kvm|scrcpy)$" },
  float = true,
})
hl.window_rule({
  name  = "Float (by title)",
  match = { title = "^(ファイル操作の進捗|フォルダーを開く|ファイルを開く|名前を付けて保存|パスワードを作成|.* の名前を変更)$" },
  float = true,
})
hl.window_rule({
  name  = "Pin the PIP window",
  match = { title = "^(ピクチャーインピクチャー)$" },
  pin   = true,
})
hl.window_rule({
  name           = "Prevent maximization",
  match          = { title = ".*" },
  suppress_event = "maximize",
})
