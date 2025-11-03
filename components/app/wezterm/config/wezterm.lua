local wezterm = require 'wezterm'
local config = wezterm.config_builder()

local keybinds = require 'keybinds'

config.keys = keybinds.keys
config.key_tables = keybinds.key_tables

config.automatically_reload_config = true
config.font = wezterm.font_with_fallback({ "FiraCode Nerd Font Mono", "Noto Sans Mono CJK JP" })
config.font_size = 8

config.mux_enable_ssh_agent = false

config.enable_wayland = false
config.use_ime = true
config.window_background_opacity = 0.85
-- config.color_scheme = 'OneDark (base16)'
config.window_frame = {
  inactive_titlebar_bg = "none",
  active_titlebar_bg = "none",
}
config.inactive_pane_hsb = {
  saturation = 0.9,
  brightness = 0.8,
}
config.show_new_tab_button_in_tab_bar = false


-- and finally, return the configuration to wezterm
return config
