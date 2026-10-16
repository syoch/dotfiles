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
    package = mkOption {
      type = types.package;
      default = pkgs.opencode;
      description = "The opencode package to use.";
    };

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

  };

  config = mkIf cfg.enable {
    programs.opencode = {
      enable = true;
      package = cfg.package;
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
        ExecStart = "${pkgs.nodejs}/bin/node ${config.home.homeDirectory}/.local/share/opencode-mcp/node_modules/@playwright/mcp/cli.js --port 8931 --cdp-endpoint http://localhost:9222";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.services.opencode = {
      Unit = {
        Description = "OpenCode WebUI";
        Wants = [
          "playwright-mcp.service"
          "chromium-cdp.service"
        ];
        After = [
          "playwright-mcp.service"
          "chromium-cdp.service"
        ];
      };
      Service.ExecStart = "${cfg.package}/bin/opencode web --hostname 127.0.0.1 --port 12000";
      Install.WantedBy = [ "default.target" ];
    };

    # opencode binds loopback and has no authentication of its own. sv01 runs
    # the NextCloud Talk bridge, which must reach this server, so we open a
    # reverse tunnel from the desktop onto sv01's loopback rather than
    # publishing opencode on the Tailnet (which the phone is also a member of).
    #
    # `-R 127.0.0.1:<port>:127.0.0.1:12000` binds the *far* end to loopback,
    # so nothing off-host on sv01 can use it.
    systemd.user.services.opencode-sv01-tunnel = {
      Unit = {
        Description = "Reverse tunnel exposing opencode to sv01 loopback (Talk bridge)";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        # `writeShellApplication` returns the package directory, so the
        # executable is under `bin/`. Pointing ExecStart at the directory made
        # systemd fail with `203/EXEC: Is a directory`, restarting every 10s
        # forever (NRestarts reached 582) with the tunnel never coming up.
        ExecStart = "${
          pkgs.writeShellApplication {
            name = "opencode-sv01-tunnel";
            runtimeInputs = [ pkgs.openssh ];
            text = ''
              set -o errexit
              while true; do
                ssh -N \
                  -o BatchMode=yes \
                  -o ExitOnForwardFailure=yes \
                  -o ServerAliveInterval=30 \
                  -o ServerAliveCountMax=3 \
                  -o StrictHostKeyChecking=accept-new \
                  -R "127.0.0.1:$SV01_TUNNEL_PORT:127.0.0.1:12000" \
                  -L "127.0.0.1:$SV01_CTL_PORT:127.0.0.1:8787" \
                  "$SV01_USER@$SV01_HOST" || true
                sleep 10
              done
            '';
          }
        }/bin/opencode-sv01-tunnel";
        # systemd wants a list of KEY=VALUE, not an attribute set.
        Environment = [
          "SV01_USER=syoch"
          "SV01_HOST=100.96.100.1"
          "SV01_TUNNEL_PORT=12000"
          # The talk-post plugin needs the bridge's control API to resolve which
          # venue its opencode session speaks for. Forwarded over the same
          # tunnel so the bridge keeps listening on sv01 loopback only.
          "SV01_CTL_PORT=8788"
        ];
        Restart = "always";
        RestartSec = 10;
      };
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
        # `talk-post.ts` reads TALK_BRIDGE_CTL and NEXTCLOUD_URL from the
        # environment with loopback defaults, so no wiring is needed here.
        ".config/opencode/plugins/talk-post.ts".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/talk-post.ts";
        # Tools must live under tools/ to reach the model; a plugin's `tool: {}`
        # map is not exposed (verified with a probe). A named export becomes
        # `<file>_<export>`; a default export becomes just `<file>`.
        ".config/opencode/tools/talk-post.ts".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/tools/talk-post.ts";
        ".config/opencode/tools/talk-delegate.ts".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/tools/talk-delegate.ts";
        ".config/opencode/tools/talk-roles.ts".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/tools/talk-roles.ts";
        # NextCloud data access for the roles. These authenticate with the
        # role's own app password straight out of talk_bind, so they act as a
        # real user and inherit that user's permissions.
        ".config/opencode/tools/nextcloud-deck.ts".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/tools/nextcloud-deck.ts";
        ".config/opencode/tools/nextcloud-files.ts".source =
          config.lib.file.mkOutOfStoreSymlink "${opencodeSrc}/tools/nextcloud-files.ts";
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

    ];

    # ── Imperative activation scripts ──────────────────────────────────

    # Ensure package.json and bun install for plugin runtime imports.
    home.activation.opencodePlugins = mkIf cfg.agents.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Ensure package.json declares @opencode-ai/plugin.
        # Written via node — no shell heredoc (indented terminators inside
        # the Nix string silently swallow the rest of the script).
        if [ ! -f "$HOME/.config/opencode/package.json" ]; then
          ${pkgs.nodejs}/bin/node -e 'require("fs").writeFileSync(process.env.HOME + "/.config/opencode/package.json", JSON.stringify({ type: "module", dependencies: { "@opencode-ai/plugin": "1.18.31" }, devDependencies: { "@types/bun": "latest" } }, null, 2) + "\n")'
        else
          # Ensure @opencode-ai/plugin is declared. Use a tiny node
          # script to avoid pulling in jq.
          ${pkgs.nodejs}/bin/node -e '
            const fs = require("fs");
            const p = process.env.HOME + "/.config/opencode/package.json";
            const pkg = JSON.parse(fs.readFileSync(p, "utf8"));
            pkg.dependencies = pkg.dependencies || {};
            delete pkg.dependencies["mem0ai"];
            if (!pkg.dependencies["@opencode-ai/plugin"]) pkg.dependencies["@opencode-ai/plugin"] = "1.18.31";
            fs.writeFileSync(p, JSON.stringify(pkg, null, 2) + "\n");
          '
        fi

        # Compare the INSTALLED version, not just its presence. A directory
        # existence check cannot see a version bump, so raising the pin would
        # silently keep the old package on disk.
        installed=$(${pkgs.nodejs}/bin/node -e '
          try {
            const p = process.env.HOME + "/.config/opencode/node_modules/@opencode-ai/plugin/package.json";
            process.stdout.write(require("fs").existsSync(p) ? JSON.parse(require("fs").readFileSync(p, "utf8")).version : "");
          } catch { process.stdout.write(""); }
        ')
        if [ "$installed" != "1.18.31" ]; then
          echo "updating @opencode-ai/plugin (installed: \${"installed:-none"})"
          ${lib.getExe pkgs.bun} install --cwd "$HOME/.config/opencode" --no-save
        fi
      ''
    );

    # opencode resolves imports of symlinked plugin/tool sources from their
    # realpath (this repo) — expose the config-dir node_modules there so
    # runtime imports like '@opencode-ai/plugin' keep resolving.
    home.activation.opencodeNodeModules =
      mkIf (cfg.tasks.enable || cfg.agents.enable || cfg.memory-tool.enable)
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
