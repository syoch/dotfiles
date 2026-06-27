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
  autoSkillTs = ./opencode/auto-skill.ts;
in
{
  options.hm-module.opencode = {
    enable = mkEnableOption "opencode";

    tasks = {
      enable = mkEnableOption "opencode tasks tool (tmux-backed background tasks)";
    };

    auto-skill = {
      enable = mkEnableOption ''
        auto-skill plugin: watches tool calls, detects repetition (>=3x) and
        error-recovery (>=2x) patterns, and on session.idle asks an LLM
        subagent to write a SKILL.md to ~/.config/opencode/skills/auto/
        (global) or .opencode/skills/auto/ (project) based on its judgement.
      '';
    };
  };

  config = mkIf cfg.enable {
    programs.opencode = {
      enable = true;
      settings = {
        permission = {
          webfetch = "allow";
          websearch = "allow";
        };
      } // lib.optionalAttrs cfg.auto-skill.enable {
        # Mem0 plugin is registered explicitly. auto-skill.ts is auto-discovered
        # by opencode from ~/.config/opencode/plugins/ and does not need to be
        # listed here.
        plugin = [ "@mem0/opencode-plugin" ];
      };
    };

    # Install the custom tool/plugin as real files (not Nix-store symlinks) so
    # Node module resolution can walk up to `~/.config/opencode/node_modules/`
    # to find @opencode-ai/plugin and mem0ai.
    home.activation.opencodeTools = mkIf cfg.tasks.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                mkdir -p "$HOME/.config/opencode/tools"
                install -m 0644 ${tasksTs} "$HOME/.config/opencode/tools/tasks.ts"
      ''
    );

    home.activation.opencodeAutoSkill = mkIf cfg.auto-skill.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                mkdir -p "$HOME/.config/opencode/plugins" "$HOME/.config/opencode/skills/auto"
                install -m 0644 ${autoSkillTs} "$HOME/.config/opencode/plugins/auto-skill.ts"

                # Ensure package.json has both @opencode-ai/plugin and mem0ai.
                if [ ! -f "$HOME/.config/opencode/package.json" ]; then
                  cat > "$HOME/.config/opencode/package.json" <<'EOF'
        {
          "type": "module",
          "dependencies": { "@opencode-ai/plugin": "1.14.35", "mem0ai": "^3.0.10" },
          "devDependencies": { "@types/bun": "latest" }
        }
        EOF
                else
                  # Add mem0ai if missing. Use a tiny node script to avoid
                  # pulling in jq.
                  ${pkgs.nodejs}/bin/node -e '
                    const fs = require("fs");
                    const p = process.env.HOME + "/.config/opencode/package.json";
                    const pkg = JSON.parse(fs.readFileSync(p, "utf8"));
                    pkg.dependencies = pkg.dependencies || {};
                    if (!pkg.dependencies["mem0ai"]) pkg.dependencies["mem0ai"] = "^3.0.10";
                    if (!pkg.dependencies["@opencode-ai/plugin"]) pkg.dependencies["@opencode-ai/plugin"] = "1.14.35";
                    fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + "\n");
                  '
                fi

                if [ ! -d "$HOME/.config/opencode/node_modules/mem0ai" ] || [ ! -d "$HOME/.config/opencode/node_modules/@opencode-ai/plugin" ]; then
                  ${lib.getExe pkgs.bun} install --cwd "$HOME/.config/opencode" --no-save
                fi
      ''
    );
  };
}
