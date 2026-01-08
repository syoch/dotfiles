local wezterm = require 'wezterm'
local config = wezterm.config_builder()

local keybinds = require 'keybinds'

config.keys = keybinds.keys
config.key_tables = keybinds.key_tables

config.automatically_reload_config = true
config.font = wezterm.font_with_fallback {
  {
    family = "FiraCode Nerd Font Mono",
    weight = "Regular",
    harfbuzz_features = { 'calt=1', 'clig=1', 'liga=1' },
  },
  "Noto Sans Mono CJK JP",
}
config.font_size = 8

config.mux_enable_ssh_agent = false

config.enable_wayland = false
config.use_ime = true
config.window_background_opacity = 0.7
config.color_scheme = 'OneDark (base16)'
config.window_frame = {
  inactive_titlebar_bg = "none",
  active_titlebar_bg = "none",
}

config.window_decorations = "RESIZE"
config.inactive_pane_hsb = {
  saturation = 0.9,
  brightness = 0.8,
}
config.show_new_tab_button_in_tab_bar = false
config.colors = {
  tab_bar = {
    inactive_tab_edge = "none",
  },
}
config.default_cursor_style = 'BlinkingBar'



-- and finally, return the configuration to wezterm
return config
