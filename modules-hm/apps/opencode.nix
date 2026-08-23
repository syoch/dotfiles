{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.hm-module.opencode;
  dotfiles = "${config.home.homeDirectory}/dotfiles";
  opencodeSrc = "${dotfiles}/modules-hm/apps/opencode";
in
{
  options.hm-module.opencode = {
    enable = mkEnableOption "opencode";

    tasks = {
      enable = mkEnableOption "opencode tasks tool (tmux-backed background tasks)";
    };

    agents = {
      enable = mkEnableOption ''
        .agents catalog management + bridge plugin.
        Symlinks ~/.agents to config/agents, enables agents_* tools for
        catalog management, and activates agents-bridge plugin that scans
        SKILL.md trees and injects a compact catalog block into the system prompt.
      '';
    };

    design-agent = {
      enable = mkEnableOption ''
        design agent: consult-only primary agent for design discussions
        (requirements elicitation, logic/architecture design, tradeoff
        analysis). Never implements or pushes toward implementation; records
        settled design decisions via the memory tool (design/<topic>).
      '';
    };

    memory-tool = {
      enable = mkEnableOption ''
        memory tools: durable long-term memory at project (.agents/memory/) and global (~/.agents/memory/)
        scope. memory_save (save|overwrite|append) / get / list / remove.
      '';
    };

    global-agents = {
      enable = mkEnableOption ''
        manage ~/.config/opencode/AGENTS.md (global agent instructions:
        native-first processing, lossless collection, /tmp workspace
        protection, .agents catalog and knowledge-driven skill promotion
        flow). Source: opencode/AGENTS.global.md.
      '';
    };

    orchestration = {
      enable = mkEnableOption ''
        orchestration plugin + agents: multi-agent orchestration for
        brainstorm/discussion/parallel research. Provides the
        orchestrate_run tool (leader-only, code-gated) that runs participant
        agents (proposer/critic/design) against persistent per-run sessions
        (.agents/orchestration/<name>.json) with sequential/parallel modes.
        Includes leader (subagent, strong model) / proposer / critic agent
        definitions.
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
        }
        // lib.optionalAttrs cfg.agents.enable {
          # catalog management custom tools (agents_*) run without per-use prompts
          "agents_*" = "allow";
        }
        // lib.optionalAttrs cfg.memory-tool.enable {
          # long-term memory custom tools (memory_*) run without per-use prompts
          "memory_*" = "allow";
        };

        # Playwright MCP runs as the always-on playwright-mcp.service
        # (HTTP transport on :8931) which attaches every session to the
        # shared chromium-cdp browser. Python scripts share the same browser
        # by connecting to CDP :9222 directly.
        mcp.playwright = {
          type = "remote";
          url = "http://localhost:8931/mcp";
          enabled = true;
        };
      };
    };

    systemd.user.services.chromium-cdp = {
      Unit.Description = "Chromium CDP Server";
      Service = {
        ExecStart =
          let
            chromium-headless = "${pkgs.chromium}/bin/chromium --headless --remote-debugging-port=9222 --user-data-dir=%h/.cache/chromium-cdp --no-first-run --disable-gpu --no-sandbox";
            chromium-headed = "${pkgs.chromium}/bin/chromium --remote-debugging-port=9222 --user-data-dir=%h/.cache/chromium-cdp --no-first-run --no-sandbox";
          in
          "${pkgs.bash}/bin/bash -c 'if [ \"$CHROMIUM_HEADED\" = \"1\" ]; then exec ${chromium-headed}; else exec ${chromium-headless}; fi'";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    # Playwright MCP server, always-on with HTTP transport (:8931).
    # Attaches every browser session to the shared chromium-cdp instance.
    # Provisioned by home.activation.opencodeMcp (~/.local/share/opencode-mcp);
    # store node binary is used because the user service PATH lacks node.
    systemd.user.services.playwright-mcp = {
      Unit = {
        Description = "Playwright MCP Server (HTTP transport)";
        Requires = [ "chromium-cdp.service" ];
        After = [ "chromium-cdp.service" ];
      };
      Service = {
        ExecStart =
          "${pkgs.nodejs}/bin/node ${config.home.homeDirectory}/.local/share/opencode-mcp/node_modules/@playwright/mcp/cli.js --port 8931 --cdp-endpoint http://localhost:9222";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.services.opencode = {
      Unit = {
        Description = "OpenCode WebUI";
        Requires = [
          "playwright-mcp.service"
          "chromium-cdp.service"
        ];
        After = [
          "playwright-mcp.service"
          "chromium-cdp.service"
        ];
      };
      Service.ExecStart = "${pkgs.opencode}/bin/opencode web --hostname 127.0.0.1 --port 12000";
      Install.WantedBy = [ "default.target" ];
    };

    # ── Declarative out-of-store symlinks ──────────────────────────────
    # All plugin/tool sources are symlinked directly into this repo so
    # edits are reflected immediately without a rebuild. Runtime imports
    # (@opencode-ai/plugin, bun) resolve via ~/.config/opencode/node_modules.
    home.file = mkMerge [
      # tasks tool
      (mkIf cfg.tasks.enable {
        ".config/opencode/tools/tasks.ts".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/tasks.ts";
      })

      # agents catalog tools + bridge + ~/.agents symlink
      (mkIf cfg.agents.enable {
        ".config/opencode/tools/agents.ts".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/agents.ts";
        ".config/opencode/plugins/agents-bridge.ts".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/agents-bridge.ts";
        ".agents".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/agents";
      })

      # memory tool
      (mkIf cfg.memory-tool.enable {
        ".config/opencode/tools/memory.ts".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/memory.ts";
      })

      # global AGENTS.md
      (mkIf cfg.global-agents.enable {
        ".config/opencode/AGENTS.md".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/AGENTS.global.md";
      })

      # design agent
      (mkIf cfg.design-agent.enable {
        ".config/opencode/agents/design.md".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/agents/design.md";
      })

      # orchestration plugin + agents
      (mkIf cfg.orchestration.enable {
        ".config/opencode/plugins/orchestration.ts".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/orchestration.ts";
        ".config/opencode/agents/leader.md".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/agents/leader.md";
        ".config/opencode/agents/proposer.md".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/agents/proposer.md";
        ".config/opencode/agents/critic.md".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/agents/critic.md";
      })
    ];

    # ── Imperative activation scripts ──────────────────────────────────

    # Ensure package.json and bun install for plugin runtime imports.
    home.activation.opencodePlugins = mkIf cfg.agents.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Ensure package.json declares @opencode-ai/plugin.
        # Written via node — no shell heredoc (indented terminators inside
        # the Nix string silently swallow the rest of the script).
        if [ ! -f "$HOME/.config/opencode/package.json" ]; then
          ${pkgs.nodejs}/bin/node -e 'require("fs").writeFileSync(process.env.HOME + "/.config/opencode/package.json", JSON.stringify({ type: "module", dependencies: { "@opencode-ai/plugin": "1.14.35" }, devDependencies: { "@types/bun": "latest" } }, null, 2) + "\n")'
        else
          # Ensure @opencode-ai/plugin is declared. Use a tiny node
          # script to avoid pulling in jq.
          ${pkgs.nodejs}/bin/node -e '
            const fs = require("fs");
            const p = process.env.HOME + "/.config/opencode/package.json";
            const pkg = JSON.parse(fs.readFileSync(p, "utf8"));
            pkg.dependencies = pkg.dependencies || {};
            delete pkg.dependencies["mem0ai"];
            if (!pkg.dependencies["@opencode-ai/plugin"]) pkg.dependencies["@opencode-ai/plugin"] = "1.14.35";
            fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + "\n");
          '
        fi

        if [ ! -d "$HOME/.config/opencode/node_modules/@opencode-ai/plugin" ]; then
          ${lib.getExe pkgs.bun} install --cwd "$HOME/.config/opencode" --no-save
        fi
      ''
    );

    # opencode resolves imports of symlinked plugin/tool sources from their
    # realpath (this repo) — expose the config-dir node_modules there so
    # runtime imports like '@opencode-ai/plugin' keep resolving.
    home.activation.opencodeNodeModules =
      mkIf (cfg.tasks.enable || cfg.agents.enable || cfg.memory-tool.enable || cfg.orchestration.enable)
        (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            ln -sfn "$HOME/.config/opencode/node_modules" "${opencodeSrc}/node_modules"
          ''
        );

    # Ensure @playwright/mcp is installed for the playwright-mcp.service.
    # IMPORTANT: this lives in its own prefix (~/.local/share/opencode-mcp),
    # NOT in ~/.config/opencode/package.json — opencode rewrites that file on
    # startup and strips dependencies it does not manage itself.
    # The package.json is written via node (no shell heredoc: indented
    # terminators inside the Nix string silently swallow the rest of the
    # activation script).
    home.activation.opencodeMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.local/share/opencode-mcp"
      if [ ! -f "$HOME/.local/share/opencode-mcp/package.json" ]; then
        ${pkgs.nodejs}/bin/node -e 'require("fs").writeFileSync(process.env.HOME + "/.local/share/opencode-mcp/package.json", JSON.stringify({ type: "module", dependencies: { "@playwright/mcp": "latest" }, devDependencies: {} }, null, 2) + "\n")'
      fi

      if [ ! -d "$HOME/.local/share/opencode-mcp/node_modules/@playwright/mcp" ]; then
        ${lib.getExe pkgs.bun} install --cwd "$HOME/.local/share/opencode-mcp" --no-save
      fi
    '';
  };
}
