{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.hm-module.opencode;
  tasksTs = ./opencode/tasks.ts;
in
{
  options.hm-module.opencode = {
    enable = mkEnableOption "opencode";

    tasks = {
      enable = mkEnableOption "opencode tasks tool (tmux-backed background tasks)";
    };
  };

  config = mkIf cfg.enable {
    programs.opencode = {
      enable = true;
      settings.plugin = [ "opencode-gemini-auth@latest" ];
      settings.permission = {
        webfetch = "allow";
        websearch = "allow";
      };
    };

    # Install the custom tool as a real file (not a Nix-store symlink) so
    # Node module resolution can walk up to `~/.config/opencode/node_modules/`
    # to find @opencode-ai/plugin.
    home.activation.opencodeTools = mkIf cfg.tasks.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.config/opencode/tools"
        install -m 0644 ${tasksTs} "$HOME/.config/opencode/tools/tasks.ts"

        if [ ! -f "$HOME/.config/opencode/package.json" ]; then
          cat > "$HOME/.config/opencode/package.json" <<'EOF'
{
  "type": "module",
  "dependencies": { "@opencode-ai/plugin": "1.14.35" },
  "devDependencies": { "@types/bun": "latest" }
}
EOF
        fi

        if [ ! -d "$HOME/.config/opencode/node_modules/@opencode-ai/plugin" ]; then
          ${lib.getExe pkgs.bun} install --cwd "$HOME/.config/opencode" --no-save
        fi
      ''
    );
  };
}
