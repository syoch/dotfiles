{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.hm-module.opencode;
in
{
  options.hm-module.opencode = {
    enable = mkEnableOption "opencode";

    tasks = {
      enable = mkEnableOption "opencode tasks tool (tmux-backed background tasks)";
    };

    agents-tool = {
      enable = mkEnableOption ''
        agents tools: manage the .agents catalogs (list/categories/add/
        update/rename/remove/show) by dynamically scanning the directory tree
        and SKILL.md frontmatter instead of editing MANIFEST.md.
      '';
    };

    agents-bridge = {
      enable = mkEnableOption ''
        agents-bridge plugin: reads the .agents catalog (dynamically scanned
        from SKILL.md trees under ~/.agents/skills/ and <cwd>/.agents/skills/) and injects
        a compact [agents-bridge] block into the system prompt via
        experimental.chat.system.transform, so the agent knows which reusable
        scripts/skills are available without searching the directory tree.
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
        and global (~/.config/opencode/memory/, managed from config/memory/)
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

    agents-catalog = {
      enable = mkEnableOption ''
        symlink ~/.agents to the user-scope agent catalog managed in this
        repo (config/agents). Catalog layout: tech-stack subdirectories,
        each containing per-skill SKILL.md directories (frontmatter-driven,
        no MANIFEST).
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
        // lib.optionalAttrs cfg.agents-tool.enable {
          # catalog management custom tools (agents_*) run without per-use prompts
          "agents_*" = "allow";
        }
        // lib.optionalAttrs cfg.memory-tool.enable {
          # long-term memory custom tools (memory_*) run without per-use prompts
          "memory_*" = "allow";
        };
      };
    };

    systemd.user.services.opencode = {
      Unit.Description = "OpenCode WebUI";
      Service.ExecStart = "${pkgs.opencode}/bin/opencode web --hostname 127.0.0.1 --port 12000";
      Install.WantedBy = [ "default.target" ];
    };

    # Manage plugin/tool sources as out-of-store symlinks into this repo,
    # so edits are reflected immediately without a rebuild. Runtime imports
    # (@opencode-ai/plugin, bun) resolve via ~/.config/opencode/node_modules
    # as before (verified with a sandboxed opencode session).
    home.activation.opencodeTools = mkIf cfg.tasks.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.config/opencode/tools"
        ln -sfn "${config.home.homeDirectory}/dotfiles/modules-hm/apps/opencode/tasks.ts" "$HOME/.config/opencode/tools/tasks.ts"
      ''
    );

    # Manage the .agents catalog tools from the repo.
    home.activation.opencodeAgentsTool = mkIf cfg.agents-tool.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.config/opencode/tools"
        ln -sfn "${config.home.homeDirectory}/dotfiles/modules-hm/apps/opencode/agents.ts" "$HOME/.config/opencode/tools/agents.ts"
      ''
    );

    # Manage the long-term memory tool from the repo.
    home.activation.opencodeMemoryTool = mkIf cfg.memory-tool.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.config/opencode/tools"
        ln -sfn "${config.home.homeDirectory}/dotfiles/modules-hm/apps/opencode/memory.ts" "$HOME/.config/opencode/tools/memory.ts"
      ''
    );

    # Manage the global long-term memory dir from the repo (git-managed).
    home.activation.opencodeMemoryLink = mkIf cfg.memory-tool.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.config/opencode"
        ln -sfn "${config.home.homeDirectory}/dotfiles/config/memory" "$HOME/.config/opencode/memory"
      ''
    );

    # Manage the global AGENTS.md (behavioral rules) from the repo.
    home.activation.opencodeGlobalAgents = mkIf cfg.global-agents.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.config/opencode"
        ln -sfn "${config.home.homeDirectory}/dotfiles/modules-hm/apps/opencode/AGENTS.global.md" "$HOME/.config/opencode/AGENTS.md"
      ''
    );

    # Manage the custom design agent (consult-only primary agent) from the repo.
    home.activation.opencodeDesignAgent = mkIf cfg.design-agent.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.config/opencode/agents"
        ln -sfn "${config.home.homeDirectory}/dotfiles/modules-hm/apps/opencode/agents/design.md" "$HOME/.config/opencode/agents/design.md"
      ''
    );

    # opencode resolves imports of symlinked plugin/tool sources from their
    # realpath (this repo) — expose the config-dir node_modules there so
    # runtime imports like '@opencode-ai/plugin' keep resolving.
    home.activation.opencodeNodeModules = mkIf (cfg.tasks.enable || cfg.agents-bridge.enable || cfg.agents-tool.enable || cfg.memory-tool.enable || cfg.orchestration.enable) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ln -sfn "$HOME/.config/opencode/node_modules" "${config.home.homeDirectory}/dotfiles/modules-hm/apps/opencode/node_modules"
      ''
    );

    # Manage the orchestration plugin from the repo.
    home.activation.opencodeOrchestration = mkIf cfg.orchestration.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.config/opencode/plugins"
        ln -sfn "${config.home.homeDirectory}/dotfiles/modules-hm/apps/opencode/orchestration.ts" "$HOME/.config/opencode/plugins/orchestration.ts"
      ''
    );

    # Manage the orchestration agents (leader / proposer / critic) from the repo.
    home.activation.opencodeOrchestrationAgents = mkIf cfg.orchestration.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.config/opencode/agents"
        for f in leader proposer critic; do
          ln -sfn "${config.home.homeDirectory}/dotfiles/modules-hm/apps/opencode/agents/$f.md" "$HOME/.config/opencode/agents/$f.md"
        done
      ''
    );

    # Manage the user-scope agent catalog ~/.agents from this repo.
    # A real out-of-store symlink (activation, not home.file) so edits in
    # ~/dotfiles/config/agents are reflected immediately without a rebuild.
    home.activation.opencodeAgentsLink = mkIf cfg.agents-catalog.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ln -sfn "${config.home.homeDirectory}/dotfiles/config/agents" "$HOME/.agents"      ''
    );

    home.activation.opencodePlugins = mkIf cfg.agents-bridge.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                mkdir -p "$HOME/.config/opencode/plugins"
                ln -sfn "${config.home.homeDirectory}/dotfiles/modules-hm/apps/opencode/agents-bridge.ts" "$HOME/.config/opencode/plugins/agents-bridge.ts"

                # Ensure package.json declares @opencode-ai/plugin.
                if [ ! -f "$HOME/.config/opencode/package.json" ]; then
                  cat > "$HOME/.config/opencode/package.json" <<'EOF'
        {
          "type": "module",
          "dependencies": { "@opencode-ai/plugin": "1.14.35" },
          "devDependencies": { "@types/bun": "latest" }
        }
        EOF
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
  };
}